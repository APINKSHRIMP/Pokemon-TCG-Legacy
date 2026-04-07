extends Node

######################################################################################################################################################
############################################################## ATTACK EFFECTS ######################################################################
######################################################################################################################################################
#
# This file contains all attack effect parsing, application, and special attack execution.
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

func get_flip_context(text: String, effect_pos: int) -> String:
	var before = text.substr(0, effect_pos)
	var heads_pos = before.rfind("if heads")
	var tails_pos = before.rfind("if tails")
	if heads_pos == -1 and tails_pos == -1:
		return "none"
	if heads_pos > tails_pos:
		return "heads"
	return "tails"
		
# Searches for a defender status across three text patterns, returns position or -1
func find_defender_status_pos(text: String, status: String, has_defender_prefix: bool) -> int:
	var direct_pos = text.find("the defending pokémon is now " + status)
	if direct_pos != -1:
		return direct_pos
	if has_defender_prefix:
		var and_pos = text.find("and " + status)
		if and_pos != -1:
			return and_pos
		var it_pos = text.find("it is now " + status)
		if it_pos != -1:
			return it_pos
	return -1
	
# Applies a single parsed status effect to the correct pokemon and updates the UI
func extract_number_before(text: String, keyword: String) -> int:
	var pos = text.find(keyword)
	if pos == -1:
		return -1
	var i = pos - 1
	while i >= 0 and text[i] == " ":
		i -= 1
	var num_str = ""
	while i >= 0 and text[i].is_valid_int():
		num_str = text[i] + num_str
		i -= 1
	if num_str != "":
		return int(num_str)
	return -1

														######### Effects from text ##########
																
# Applies self-damage from an attack effect to the attacker
func parse_attack_base_damage(attack: Dictionary) -> int:
	var raw_damage = attack.get("damage", "0")
	var numeric_damage = ""
	for character in raw_damage:
		if character.is_valid_int():
			numeric_damage += character
	return int(numeric_damage) if numeric_damage != "" else 0

# Handles the confusion coin flip when an attacker is confused
# Returns true if the attack FAILS (attacker hurt itself), false if the attack can proceed
func estimate_attack_damage_range(attack: Dictionary, attacker: card_object = null, defender: card_object = null) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", "0"))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower() if attacker else ""
	
	# --- COIN FLIP MULTIPLICATIVE (×) ---
	if "×" in damage_str or "x" in damage_str:
		if "times the number of damage counters" in text:
			# Flail-type: damage × self damage counters
			if attacker:
				var counters = attacker.get_damage_counters()
				return {"min": base_damage * counters, "max": base_damage * counters}
			return {"min": 0, "max": base_damage * 10}
		if "flip a coin until" in text:
			return {"min": 0, "max": base_damage * 5}
		elif "flip 3 coins" in text:
			return {"min": 0, "max": base_damage * 3}
		elif "flip 2 coins" in text:
			return {"min": 0, "max": base_damage * 2}
		return {"min": 0, "max": base_damage * 2}
	
	# --- "IF TAILS, DOES NOTHING" ---
	if "if tails, this attack does nothing" in text:
		return {"min": 0, "max": base_damage}
	
	# --- HALF HP (Raticate Super Fang) ---
	if "equal to half" in text and "remaining hp" in text:
		if defender:
			var dmg = int(ceil(defender.current_hp / 2.0 / 10.0)) * 10
			return {"min": dmg, "max": dmg}
		return {"min": 10, "max": 60}
	
	# --- CONDITION-GATED (Haunter Dream Eater) ---
	if "can't use this attack unless" in text:
		if defender:
			if "asleep" in text and defender.special_condition != "Asleep":
				return {"min": 0, "max": 0}
			if "poisoned" in text and not defender.is_poisoned:
				return {"min": 0, "max": 0}
		return {"min": 0, "max": base_damage}
	
	var min_dmg = base_damage
	var max_dmg = base_damage
	
	# --- HEADS/TAILS +BONUS ---
	if "+" in damage_str and "if heads" in text and "more damage" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		min_dmg = base_damage
		max_dmg = base_damage + bonus
	
	# --- PER DEFENDER ENERGY ---
	if "for each energy card attached to the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each energy")
		if extracted > 0:
			per = extracted
		if defender:
			var count = defender.attached_energies.size()
			min_dmg += per * count
			max_dmg += per * count
		else:
			max_dmg += per * 4
	
	# --- EXTRA ENERGY BEYOND COST ---
	if "more damage for each" in text and "not used to pay" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
			var bonus_type = ""
			for tkw in type_keywords:
				if tkw + " energy attached" in text:
					bonus_type = tkw.capitalize()
					break
			if bonus_type != "":
				var total = 0
				for e in attacker.attached_energies:
					if bonus_type in main.get_energy_provided_by_card(e):
						total += 1
				var cost_count = 0
				for c in attack.get("cost", []):
					if c == bonus_type:
						cost_count += 1
				var extra = max(0, total - cost_count)
				var cap = 99
				if "after the" in text and "don't count" in text:
					var after_pos = text.find("after the")
					var after_text = text.substr(after_pos + 10, 10)
					var cap_num = ""
					for ch in after_text:
						if ch.is_valid_int():
							cap_num += ch
						else:
							break
					if cap_num != "":
						cap = max(0, int(cap_num) - cost_count)
				elif "can't add more than" in text and "damage in this way" in text:
					var cap_dmg = extract_number_before(text, "damage in this way")
					if cap_dmg > 0:
						cap = cap_dmg / per
				extra = min(extra, cap)
				min_dmg += per * extra
				max_dmg += per * extra
		else:
			max_dmg += per * 2
	
	# --- PER DAMAGE COUNTER ON DEFENDING ---
	if "for each damage counter on the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if defender:
			var counters = defender.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
		else:
			max_dmg += per * 8
	
	# --- PER SELF DAMAGE COUNTER ---
	if attacker_name != "" and ("for each damage counter on " + attacker_name) in text and "minus" not in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
	
	# --- MINUS PER SELF DAMAGE COUNTER ---
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg = max(0, base_damage - per * counters)
			max_dmg = min_dmg
		else:
			min_dmg = 0
	
	# --- PER BENCH COUNT ---
	if "for each of your benched" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var bench = main.opponent_bench if attacker == main.opponent_active_pokemon else main.player_bench
			min_dmg += per * bench.size()
			max_dmg += per * bench.size()
		else:
			max_dmg += per * 5
	
	return {"min": min_dmg, "max": max_dmg}

# Evaluates KO threats from the player against the CPU's active pokemon (1.1, 1.2, 1.3)
func handle_attack_confusion(attacker: card_object, is_opponent: bool) -> bool:
	if attacker.special_condition != "Confused":
		return false
	await main.show_message(attacker.metadata["name"].to_upper() + " IS CONFUSED! FLIPPING COIN...")
	if main._should_bail(): return false
	var coin = await main.flip_coin()
	if coin:
		return false
	var self_damage = 20
	if main.confusion_rules == "modern_era_confusion_rules":
		self_damage = 30
	if main.confusion_rules == "base_set_confusion_rules":
		var self_types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(self_damage, self_types, attacker)
		self_damage = result["damage"]
	# Dark Primeape Frenzy: +30 damage when confused (even to self)
	self_damage += main.powers_and_bodies.check_frenzy_bonus(attacker)
	attacker.current_hp = max(0, attacker.current_hp - self_damage)
	await main.show_message("THE ATTACK FAILED! " + attacker.metadata["name"].to_upper() + " HURT ITSELF FOR " + str(self_damage) + " DAMAGE!")
	if main._should_bail(): return false
	var attacker_label_pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
	main.show_floating_label("-" + str(self_damage) + "HP", attacker_label_pos, Color.YELLOW, true)
	main.display_hp_circles_above_align(attacker, is_opponent)
	print("CONFUSED: ", attacker.metadata["name"], " hurt itself for ", self_damage)
	await main.check_all_knockouts()
	if main._should_bail(): return false
	return true

# Handles the blind coin flip when an attacker cannot see
# Returns true if the attack FAILS (missed), false if the attack can proceed
func handle_attack_blind(attacker: card_object, is_opponent: bool) -> bool:
	if not attacker.is_blind:
		return false
	await main.show_message(attacker.metadata["name"].to_upper() + " CAN'T SEE! FLIPPING COIN...")
	if main._should_bail(): return false
	var blind_coin = await main.flip_coin()
	if not blind_coin:
		await main.show_message("THE ATTACK FAILED!")
		if main._should_bail(): return false
		attacker.is_blind = false
		main.update_status_icons(attacker, is_opponent)
		return true
	attacker.is_blind = false
	main.update_status_icons(attacker, is_opponent)
	return false

# Checks if the defender is fully invincible and blocks the attack entirely
# Returns true if the attack is blocked
func resolve_attack_variable_damage(attack: Dictionary, attacker: card_object, defender: card_object, is_opponent: bool) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", ""))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower()
	var resolved_damage = base_damage
	var messages: Array = []
	var flip_result: String = ""
	var attack_failed: bool = false
	
	# ---- CONDITION-GATED ATTACKS (must check first - attack may not proceed) ----
	if "can't use this attack" in text and "unless the defending" in text:
		if "asleep" in text and defender.special_condition != "Asleep":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT ASLEEP!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "poisoned" in text and not defender.is_poisoned:
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT POISONED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "confused" in text and defender.special_condition != "Confused":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT CONFUSED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- ENERGY-GATED ATTACKS (Dark Charmeleon Fireball, Dark Flareon Playing with Fire) ----
	if "use this attack only if there are any" in text and "energy cards attached" in text:
		var required_type = ""
		var type_keywords = ["fire", "water", "grass", "lightning", "psychic", "fighting"]
		for tkw in type_keywords:
			if tkw + " energy cards attached" in text:
				required_type = tkw.capitalize()
				break
		if required_type != "":
			var has_required = false
			for e in attacker.attached_energies:
				var provided = main.get_energy_provided_by_card(e)
				if required_type in provided:
					has_required = true
					break
			if not has_required:
				resolved_damage = 0
				attack_failed = true
				messages.append("ATTACK FAILED! NO " + required_type.to_upper() + " ENERGY ATTACHED!")
				return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- DAMAGE COUNTER MULTIPLICATIVE (Kingler Flail) ----
	if ("×" in damage_str or "x" in damage_str or "X" in damage_str) and "times the number of damage counters on" in text:
		var counters = attacker.get_damage_counters()
		resolved_damage = base_damage * counters
		messages.append(str(counters) + " DAMAGE COUNTERS! " + str(resolved_damage) + " DAMAGE!")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}

	# ---- COIN FLIP MULTIPLICATIVE DAMAGE (×) ----
	if ("×" in damage_str or "x" in damage_str or "X" in damage_str) and "times the number of heads" in text:
		var flip_count = 0
		var flip_until_tails = false
		
		if "flip a coin until you get tails" in text:
			flip_until_tails = true
		elif "flip 5 coins" in text:
			flip_count = 5
		elif "flip 4 coins" in text:
			flip_count = 4
		elif "flip 3 coins" in text:
			flip_count = 3
		elif "flip 2 coins" in text:
			flip_count = 2
		elif "flip a coin" in text:
			flip_count = 1
		
		var heads_count = 0
		# Use silent mode for multi-flips — just animate quickly, show summary at end
		var use_silent = (flip_count > 1 or flip_until_tails)
		if flip_until_tails:
			while true:
				var coin = await main.flip_coin(use_silent)
				if coin:
					heads_count += 1
				else:
					break
		else:
			for i in range(flip_count):
				var coin = await main.flip_coin(use_silent)
				if coin:
					heads_count += 1
		
		resolved_damage = base_damage * heads_count
		# Always show the final summary as a message
		messages.append("GOT " + str(heads_count) + " HEADS! " + str(resolved_damage) + " DAMAGE!")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- "IF TAILS, THIS ATTACK DOES NOTHING" (Nidoran Horn Hazard) ----
	if "if tails, this attack does nothing" in text:
		var coin = await main.flip_coin()
		if not coin:
			resolved_damage = 0
			attack_failed = true
			flip_result = "tails"
			messages.append("ATTACK DOES NOTHING!")
		else:
			flip_result = "heads"
		# Check for Farfetch'd style permanent disable
		if "can't use this attack again" in text:
			var attack_name = attack.get("name", "")
			if "as long as" in text and "stays in play" in text:
				attacker.disabled_attacks[attack_name] = "while_in_play"
				print("ATTACK DISABLED: ", attack_name, " disabled while ", attacker_name, " is in play")
			else:
				attacker.disabled_attacks[attack_name] = "entire_game"
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- HEADS/TAILS BONUS DAMAGE (Nidoking Thrash "30+", Electabuzz Thunderpunch) ----
	if "+" in damage_str and "if heads" in text and "more damage" in text and "flip a coin" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		var coin = await main.flip_coin()
		if coin:
			resolved_damage = base_damage + bonus
			flip_result = "heads"
			print("COIN BONUS: +", bonus, " damage")
		else:
			flip_result = "tails"
	
	# ---- HALF HP DAMAGE (Raticate Super Fang) ----
	if "equal to half" in text and "remaining hp" in text:
		var half_hp = defender.current_hp / 2.0
		resolved_damage = int(ceil(half_hp / 10.0)) * 10
		print("SUPER FANG: ", resolved_damage, " damage (half of ", defender.current_hp, " HP)")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- PER DEFENDER ENERGY (Mewtwo Psychic) ----
	if "for each energy card attached to the defending" in text:
		var per_energy = 10
		var energy_pos = text.find("more damage for each energy")
		if energy_pos != -1:
			var extracted = extract_number_before(text, "more damage for each energy")
			if extracted > 0:
				per_energy = extracted
		var energy_count = defender.attached_energies.size()
		var bonus = per_energy * energy_count
		resolved_damage += bonus
		print("PER DEFENDER ENERGY: +", bonus, " (", energy_count, " energies)")
	
	# ---- EXTRA ENERGY BEYOND COST (Poliwag Water Gun, Blastoise Hydro Pump) ----
	if "more damage for each" in text and "not used to pay" in text:
		var bonus_energy_type = ""
		var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
		for tkw in type_keywords:
			if tkw + " energy attached" in text and "not used to pay" in text:
				bonus_energy_type = tkw.capitalize()
				break
		
		if bonus_energy_type != "":
			# Count how many of that energy type are attached
			var total_of_type = 0
			for attached in attacker.attached_energies:
				var provided = main.get_energy_provided_by_card(attached)
				if bonus_energy_type in provided:
					total_of_type += 1
			
			# Calculate how many bonus-type energies are consumed by the FULL attack cost
			# This includes typed requirements AND colorless slots filled by bonus-type energy
			var cost = attack.get("cost", [])
			var typed_needed = 0
			var colorless_needed = 0
			for c in cost:
				if c == bonus_energy_type:
					typed_needed += 1
				elif c == "Colorless":
					colorless_needed += 1
			
			# Non-bonus energies fill colorless slots first
			var non_bonus_attached = attacker.attached_energies.size() - total_of_type
			var colorless_filled_by_non_bonus = min(colorless_needed, non_bonus_attached)
			var colorless_from_bonus = colorless_needed - colorless_filled_by_non_bonus
			
			var used_for_cost = typed_needed + colorless_from_bonus
			var extra_count = max(0, total_of_type - used_for_cost)
			
			# Parse the cap: "Extra Water Energy after the 2nd don't count"
			# OR: "You can't add more than 20 damage in this way" (Lapras, Omanyte, Seadra, Omastar)
			var cap = 99
			if "after the" in text and "don't count" in text:
				var after_pos = text.find("after the")
				var after_text = text.substr(after_pos + 10, 10)
				var cap_num = ""
				for ch in after_text:
					if ch.is_valid_int():
						cap_num += ch
					else:
						break
				if cap_num != "":
					# Cap is the max total bonus-type that count, minus those used for cost
					cap = max(0, int(cap_num) - used_for_cost)
			elif "can't add more than" in text and "damage in this way" in text:
				var cap_dmg = extract_number_before(text, "damage in this way")
				if cap_dmg > 0:
					var per_e = 10
					var ext = extract_number_before(text, "more damage for each")
					if ext > 0:
						per_e = ext
					cap = cap_dmg / per_e
			
			extra_count = min(extra_count, cap)
			
			var per_energy_bonus = 10
			var extracted_per = extract_number_before(text, "more damage for each")
			if extracted_per > 0:
				per_energy_bonus = extracted_per
			
			var bonus = per_energy_bonus * extra_count
			resolved_damage += bonus
			print("EXTRA ENERGY: +", bonus, " (", extra_count, " extra ", bonus_energy_type, " beyond ", used_for_cost, " used for cost)")
	
	# ---- PER DAMAGE COUNTER ON DEFENDING (Jynx Meditate, Mr. Mime Meditate) ----
	if "for each damage counter on the defending" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = defender.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("DEFENDER COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- PER DAMAGE COUNTER ON SELF - ADDITIONAL (Tauros Rampage) ----
	if ("for each damage counter on " + attacker_name) in text and "minus" not in text and "defending" not in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("SELF COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- MINUS PER DAMAGE COUNTER ON SELF (Machoke Karate Chop "50-") ----
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var reduction = per_counter * damage_counters
		resolved_damage = max(0, base_damage - reduction)
		print("KARATE CHOP: -", reduction, " (", damage_counters, " counters)")
	
	# ---- PER BENCHED POKEMON (Wigglytuff Do the Wave) ----
	if "for each of your benched" in text:
		var per_bench = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per_bench = extracted
		var bench = main.opponent_bench if is_opponent else main.player_bench
		var bonus = per_bench * bench.size()
		resolved_damage += bonus
		print("BENCH BONUS: +", bonus, " (", bench.size(), " benched)")
	
	# ---- ADDITIONAL DAMAGE IF DEFENDER HAS STATUS ----
	if "if the defending pokémon is poisoned" in text and "more damage" in text:
		if defender.is_poisoned:
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (poisoned)")
	if "if the defending pokémon is confused" in text and "more damage" in text:
		if defender.special_condition == "Confused":
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (confused)")
	
	return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}

# Displays modifier floating labels, the damage floating label, applies HP reduction,
# and updates the HP circles for the defender
func execute_metronome(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = main.get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await main.show_message("NO ATTACKS TO COPY!")
		if main._should_bail(): return
		return
	
	var chosen_attack: Dictionary = {}
	
	if is_opponent:
		# CPU chooses: pick the attack with highest damage potential
		var best_score = -999.0
		var cpu_types = attacker.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = estimate_attack_damage_range(attack, attacker, defender)
			var result = main.calculate_final_damage(dmg_range["max"], cpu_types, defender)
			var score = float(result["damage"])
			var parsed = parse_card_text_effects(attack.get("text", ""), attacker.metadata.get("name", ""))
			score += main.cpu_ai.score_parsed_effects(parsed, defender)
			if score > best_score:
				best_score = score
				chosen_attack = attack
	else:
		# Player chooses: show attack names as buttons
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		
		# Clear and show attack buttons
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = atk.get("name", "Attack") + " (" + str(atk.get("damage", "0")) + ")"
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		
		var selected_index = await main.special_attack_selected
		chosen_attack = defender_attacks[selected_index]
		
		# Clean up buttons
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	
	await main.show_message(attacker.metadata["name"].to_upper() + " COPIES " + chosen_attack.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	# Execute the copied attack (ignore energy costs and energy discard requirements)
	var variable_result = await resolve_attack_variable_damage(chosen_attack, attacker, defender, is_opponent)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await main.show_message(msg)
			if main._should_bail(): return
		return
	
	for msg in variable_result["messages"]:
		await main.show_message(msg)
		if main._should_bail(): return
	
	# Use attacker's own type for Metronome (Clefairy stays Colorless)
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(resolved_base, attacking_types, defender)
	var final_damage = result["damage"]
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		main.show_floating_label("NO EFFECT", inv_label_pos, true)
		return
	
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, resolved_base)
	if main._should_bail(): return
	
	# Apply non-discard effects from the copied attack
	var attack_text = chosen_attack.get("text", "")
	var effects = parse_card_text_effects(attack_text, attacker.metadata.get("name", ""))
	var filtered_effects = []
	for effect in effects:
		if effect["type"] != "energy_discard_self":
			filtered_effects.append(effect)
	if filtered_effects.size() > 0:
		await apply_card_text_effects(filtered_effects, attacker, defender, is_opponent, flip_result)
		if main._should_bail(): return

# MIRROR MOVE (Pidgeotto): Replay the last attack received
func execute_mirror_move(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var last_attack = main.last_attack_on_opponent if is_opponent else main.last_attack_on_player
	
	if last_attack.is_empty() or not last_attack.has("damage"):
		await main.show_message("MIRROR MOVE FAILED! NO ATTACK TO MIRROR!")
		if main._should_bail(): return
		return
	
	var mirrored_damage = last_attack["damage"]
	var mirrored_attack = last_attack.get("attack", {})
	
	await main.show_message(attacker.metadata["name"].to_upper() + " MIRRORS THE LAST ATTACK FOR " + str(mirrored_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		main.show_floating_label("NO EFFECT", inv_label_pos, true)
		return
	
	mirrored_damage = main.apply_defender_no_damage_shield(defender, mirrored_damage, !is_opponent)
	
	if mirrored_damage > 0:
		var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		main.show_floating_label("-" + str(mirrored_damage) + "HP", defender_label_pos, true)
		defender.current_hp = max(0, defender.current_hp - mirrored_damage)
		main.display_hp_circles_above_align(defender, !is_opponent)
	
	if mirrored_attack.has("text"):
		var effects = parse_card_text_effects(mirrored_attack.get("text", ""), attacker.metadata.get("name", ""))
		if effects.size() > 0:
			await apply_card_text_effects(effects, attacker, defender, is_opponent)
			if main._should_bail(): return

# AMNESIA (Poliwhirl): Disable one of the opponent's attacks for next turn
func execute_amnesia(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = main.get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await main.show_message("NO ATTACKS TO DISABLE!")
		if main._should_bail(): return
		return
	
	var chosen_attack_name: String = ""
	
	if is_opponent:
		var best_score = -999.0
		var defender_types = defender.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = estimate_attack_damage_range(attack, defender, attacker)
			var result = main.calculate_final_damage(dmg_range["max"], defender_types, attacker)
			var score = float(result["damage"])
			if score > best_score:
				best_score = score
				chosen_attack_name = attack.get("name", "")
	else:
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = "DISABLE: " + atk.get("name", "Attack")
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		
		var selected_index = await main.special_attack_selected
		chosen_attack_name = defender_attacks[selected_index].get("name", "")
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	
	if chosen_attack_name != "":
		defender.disabled_attacks[chosen_attack_name] = "end_of_turn"
		await main.show_message(defender.metadata["name"].to_upper() + " FORGOT HOW TO USE " + chosen_attack_name.to_upper() + "!")
		if main._should_bail(): return
		print("AMNESIA: Disabled ", chosen_attack_name, " on ", defender.metadata["name"])

# CONVERSION (Porygon): Change weakness (1) or resistance (2) type
func execute_conversion(attacker: card_object, defender: card_object, is_opponent: bool, is_conversion_1: bool) -> void:
	var energy_types = ["Fighting", "Fire", "Grass", "Lightning", "Psychic", "Water"]
	var chosen_type: String = ""
	
	# Conversion 1: Only works if the defending pokemon has a weakness
	if is_conversion_1:
		var weaknesses = defender.metadata.get("weaknesses", [])
		if weaknesses.size() == 0:
			await main.show_message("CONVERSION FAILED! OPPONENT HAS NO WEAKNESS!")
			if main._should_bail(): return
			return
	
	if is_opponent:
		if is_conversion_1:
			var cpu_type = attacker.metadata.get("types", ["Colorless"])[0]
			chosen_type = cpu_type if cpu_type in energy_types else energy_types[0]
		else:
			var player_type = defender.metadata.get("types", ["Colorless"])[0]
			if player_type != "Colorless" and player_type in energy_types:
				chosen_type = player_type
			else:
				chosen_type = energy_types[0]
	else:
		var energy_uids = ["base1-97", "base1-98", "base1-99", "base1-100", "base1-101", "base1-102"]
		var energy_cards: Array = []
		for uid in energy_uids:
			var meta = main.get_card_metadata(uid)
			if meta != null:
				var card = card_object.new(uid, meta)
				energy_cards.append(card)
		
		if energy_cards.size() > 0:
			main.energy_type_selection_active = true
			main.show_enlarged_array_selection_mode(energy_cards)
			main.cancel_button.visible = false
			if is_conversion_1:
				main.header_label.text = "CONVERSION 1: CHANGE OPPONENT'S WEAKNESS"
			else:
				main.header_label.text = "CONVERSION 2: CHANGE YOUR RESISTANCE"
			main.hint_label.text = "Select an energy type"
			main.action_button.text = "SELECT TYPE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.energy_type_selected
			if main._should_bail(): return
			chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "").strip_edges() if main.selected_card_for_action else ""
			main.energy_type_selection_active = false
			main.hide_selection_mode_display_main()
	
	if chosen_type != "" and chosen_type != "Colorless":
		if is_conversion_1:
			defender.temporary_weakness = chosen_type
			await main.show_message(defender.metadata["name"].to_upper() + "'S WEAKNESS CHANGED TO " + chosen_type.to_upper() + "!")
			if main._should_bail(): return
		else:
			attacker.temporary_resistance = chosen_type
			await main.show_message(attacker.metadata["name"].to_upper() + "'S RESISTANCE CHANGED TO " + chosen_type.to_upper() + "!")
			if main._should_bail(): return
	else:
		await main.show_message("CONVERSION FAILED!")
		if main._should_bail(): return

												######### Main effect parsers helpers ##########

# Parses attack effect text and returns an array of effect dictionaries for evaluation or application
func parse_card_text_effects(attack_text: String, attacker_name: String) -> Array:
	if attack_text == "":
		return []

	var effects: Array = []
	var text = attack_text.to_lower()
	var lower_name = attacker_name.to_lower()
	var has_defender_prefix = "the defending pokémon is now" in text

	# --- STATUS: Defender status conditions ---
	var defender_statuses = ["paralyzed", "asleep", "poisoned", "confused", "burned"]
	for status in defender_statuses:
		var pos = find_defender_status_pos(text, status, has_defender_prefix)
		if pos != -1:
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "defender", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Defender ", status.capitalize(), " | Flip: ", flip)

	# --- STATUS: Self-inflicted status ---
	var self_statuses = ["confused", "asleep", "poisoned", "paralyzed", "burned"]
	for status in self_statuses:
		if lower_name + " is now " + status in text:
			var pos = text.find(lower_name + " is now " + status)
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "self", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Self ", status.capitalize(), " | Flip: ", flip)

	# --- TOXIC: Enhanced poison (20 instead of 10) ---
	if "20 poison damage instead of 10" in text or "put 2 damage counters instead of 1" in text:
		var flip = get_flip_context(text, text.find("instead"))
		effects.append({"type": "toxic", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Toxic upgrade | Flip: ", flip)

	# --- SELF DAMAGE: Attacker damages itself ---
	if lower_name in text and "damage to itself" in text:
		var damage = extract_number_before(text, "damage to itself")
		if damage > 0:
			var flip = get_flip_context(text, text.find("damage to itself"))
			effects.append({"type": "self_damage", "target": "self", "damage": damage, "flip": flip})
			print("EFFECT PARSED: Self Damage -> ", damage, " | Flip: ", flip)

	# --- ENERGY DISCARD SELF: Attacker discards own energy ---
	if "discard" in text and "energy" in text and ("attached to " + lower_name) in text:
		var discard_pos = text.find("discard")
		var flip = get_flip_context(text, discard_pos)
		var count = 0
		var energy_type = "any"
		if "discard all" in text and ("energy cards attached to " + lower_name) in text:
			count = -1
		elif "discard a " in text or "discard 1 " in text:
			count = 1
		elif "discard 2" in text:
			count = 2
		elif "discard 3" in text:
			count = 3
		else:
			count = 1
		var type_keywords = ["fire", "water", "grass", "lightning", "psychic", "fighting", "darkness", "metal"]
		for type_name in type_keywords:
			if "discard" in text and type_name + " energy" in text and ("attached to " + lower_name) in text:
				energy_type = type_name.capitalize()
				break
		effects.append({"type": "energy_discard_self", "target": "self", "count": count, "energy_type": energy_type, "flip": flip})
		print("EFFECT PARSED: Energy Discard Self -> Count: ", count, " Type: ", energy_type, " | Flip: ", flip)

	# --- ENERGY DISCARD DEFENDER: Remove energy from defending pokemon ---
	if "discard" in text and "energy" in text and "attached to" in text:
		var is_defender_energy = false
		if "attached to the defending" in text:
			is_defender_energy = true
		if "attached to it" in text and "defending" in text:
			is_defender_energy = true
		if "choose 1 of them and discard it" in text and "energy cards attached to it" in text:
			is_defender_energy = true
		if is_defender_energy:
			var discard_pos = text.find("discard")
			var flip = get_flip_context(text, discard_pos)
			effects.append({"type": "energy_discard_defender", "target": "defender", "count": 1, "flip": flip})
			print("EFFECT PARSED: Energy Discard Defender | Flip: ", flip)

	# --- BENCH DAMAGE: Damage to benched pokemon ---
	if "damage to each" in text and "bench" in text:
		# Special case: Articuno-style where heads = opponent bench, tails = own bench
		if "your opponent's benched" in text and "your own benched" in text:
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			effects.append({"type": "bench_damage", "target": "main.opponent_bench", "damage": damage, "flip": "heads"})
			effects.append({"type": "bench_damage", "target": "own_bench", "damage": damage, "flip": "tails"})
			print("EFFECT PARSED: Bench Damage -> COIN FLIP: heads=opponent, tails=own for ", damage)
		else:
			var bench_target = "all_benches"
			if "your opponent's benched" in text or "opponent's benched" in text:
				bench_target = "main.opponent_bench"
			elif "your own benched" in text:
				bench_target = "own_bench"
			elif "each player's bench" in text:
				bench_target = "all_benches"
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			var flip = get_flip_context(text, text.find("damage to each"))
			effects.append({"type": "bench_damage", "target": bench_target, "damage": damage, "flip": flip})
			print("EFFECT PARSED: Bench Damage -> ", bench_target, " for ", damage, " | Flip: ", flip)

	# --- BLIND / SMOKESCREEN: Defender must flip to attack next turn ---
	if "tries to attack" in text and "if tails" in text and "does nothing" in text:
		effects.append({"type": "blind", "target": "defender", "flip": "none"})
		print("EFFECT PARSED: Blind / Smokescreen -> Defender")

	# --- INVINCIBLE: Prevent all effects including damage next turn ---
	if "prevent all effects of attacks, including damage" in text:
		var flip = get_flip_context(text, text.find("prevent all effects"))
		effects.append({"type": "invincible", "target": "self", "flip": flip})
		print("EFFECT PARSED: Invincible -> Self | Flip: ", flip)

	# --- NO DAMAGE: Prevent damage only next turn (other effects still happen) ---
	if "prevent all damage done to" in text and "prevent all effects of attacks" not in text:
		var flip = get_flip_context(text, text.find("prevent all damage"))
		effects.append({"type": "no_damage", "target": "self", "flip": flip})
		print("EFFECT PARSED: No Damage -> Self | Flip: ", flip)

	# --- RETREAT LOCK: Defender can't retreat ---
	if "can't retreat" in text and "defending" in text:
		var flip = get_flip_context(text, text.find("can't retreat"))
		effects.append({"type": "retreat_lock", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Retreat Lock -> Defender | Flip: ", flip)

	# --- DRAW CARDS ---
	if "draw a card" in text and "your opponent" not in text:
		effects.append({"type": "draw", "target": "self", "count": 1, "flip": "none"})
		print("EFFECT PARSED: Draw 1 card")
	elif "draw " in text and "cards" in text and "your opponent" not in text:
		var count = extract_number_before(text, "cards")
		if count > 0:
			effects.append({"type": "draw", "target": "self", "count": count, "flip": "none"})
			print("EFFECT PARSED: Draw ", count, " cards")

	# --- SELF HEAL ALL: Remove all damage from attacker ---
	if "remove all damage counters from " + lower_name in text:
		var flip = get_flip_context(text, text.find("remove all damage"))
		effects.append({"type": "self_heal", "target": "self", "amount": -1, "flip": flip})
		print("EFFECT PARSED: Self Heal All | Flip: ", flip)

	# --- SELF HEAL PARTIAL: Remove X damage counters from attacker ---
	if "remove" in text and "damage counter" in text and lower_name in text and "remove all" not in text:
		var amount = extract_number_before(text, "damage counter")
		if amount > 0:
			var flip = get_flip_context(text, text.find("remove"))
			effects.append({"type": "self_heal", "target": "self", "amount": amount, "flip": flip})
			print("EFFECT PARSED: Self Heal ", amount, " counters | Flip: ", flip)

	# --- DESTINY BOND ---
	if "knocks out " + lower_name in text and "knock out that" in text:
		effects.append({"type": "destiny_bond", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Destiny Bond -> Self")

	# --- SHIELDED DAMAGE (Onix Harden): Prevent damage at or below threshold ---
	# "During your opponent's next turn, whenever 30 or less damage is done to Onix, prevent that damage."
	if "or less damage is done to" in text and "prevent that damage" in text:
		var threshold = extract_number_before(text, "or less damage")
		if threshold > 0:
			effects.append({"type": "shielded_damage", "target": "self", "threshold": threshold, "flip": "none"})
			print("EFFECT PARSED: Shielded Damage -> threshold ", threshold)

	# --- FORCE SWITCH (Pidgey/Pidgeotto Whirlwind, Ninetales Lure) ---
	# Whirlwind: "he or she chooses 1" = defender picks
	# Lure: "choose 1 of them and switch it" (without "he or she") = attacker picks
	if ("switches it with" in text or "switch it with" in text) and ("benched" in text or "bench" in text):
		if "defending pokémon" in text or "active pokémon" in text:
			var flip = get_flip_context(text, text.find("switch"))
			var chooser = "defender"
			# "he or she chooses" = defender picks (Whirlwind)
			# Otherwise attacker picks (Lure)
			if "he or she chooses" not in text and "they choose" not in text:
				chooser = "attacker"
			effects.append({"type": "force_switch", "target": "defender", "chooser": chooser, "flip": flip})
			print("EFFECT PARSED: Force Switch -> Defender | Chooser: ", chooser, " | Flip: ", flip)


	# --- DAMAGE REDUCTION NEXT TURN (Minimize, Pounce, Snivel) ---
	if ("damage done" in text or "damage done by" in text) and "reduced by" in text and ("next turn" in text or "opponent's next turn" in text):
		var reduction = extract_number_before(text, "after applying")
		if reduction <= 0:
			reduction = 20
		effects.append({"type": "damage_reduction", "target": "self", "amount": reduction, "flip": "none"})
		print("EFFECT PARSED: Damage Reduction -> Self ", reduction)

	# --- ATTACK BLOCK NEXT TURN (Tail Wag, Leer) ---
	if "can't attack" in text and lower_name in text and "next turn" in text:
		var flip = get_flip_context(text, text.find("can't attack"))
		effects.append({"type": "attack_block", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Attack Block -> Defender | Flip: ", flip)

	# --- SELF SWITCH (Exeggutor Teleport) ---
	if "switch " + lower_name + " with" in text and "benched" in text:
		effects.append({"type": "self_switch", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Self Switch -> Self")

	# --- BENCH DAMAGE SINGLE (Pikachu Spark) ---
	if "choose 1 of them" in text and "damage to it" in text and "bench" in text and "damage to each" not in text:
		var damage = extract_number_before(text, "damage to it")
		if damage <= 0:
			damage = 10
		effects.append({"type": "bench_damage_single", "target": "opponent_bench", "damage": damage, "flip": "none"})
		print("EFFECT PARSED: Bench Damage Single -> ", damage)

	# --- TRAINER LOCK (Psyduck Headache) ---
	if "can't play trainer" in text and "next turn" in text:
		effects.append({"type": "trainer_lock", "target": "opponent", "flip": "none"})
		print("EFFECT PARSED: Trainer Lock -> Opponent")

	# --- LEECH SEED (Exeggcute) ---
	if "unless all damage" in text and "is prevented" in text and "remove 1 damage counter" in text:
		effects.append({"type": "leech_seed", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Leech Seed heal")

	# --- FOUL ODOR: Both pokemon confused ---
	if "both" in text and "defending" in text and lower_name in text and "confused" in text:
		effects.append({"type": "status", "target": "defender", "status": "Confused", "flip": "none"})
		effects.append({"type": "status", "target": "self", "status": "Confused", "flip": "none"})
		print("EFFECT PARSED: Foul Odor -> Both Confused")

	if effects.size() == 0:
		print("EFFECT PARSED: No recognised effects in: ", text.left(80))

	return effects
	
# Applies parsed effect dictionaries to the game state with coin flip gating
# pre_flip_result: if a coin was already flipped during damage resolution, use this instead of re-flipping
func apply_card_text_effects(effects: Array, attacker: card_object, defender: card_object, is_opponent_attacking: bool, pre_flip_result: String = "") -> void:
	var flip_result: String = pre_flip_result
	var needs_flip: bool = false
	
	# Only flip if we don't already have a result from damage resolution
	if flip_result == "":
		for effect in effects:
			if effect.get("flip", "none") != "none":
				needs_flip = true
				break

		if needs_flip:
			var coin = await main.flip_coin()
			flip_result = "heads" if coin else "tails"

	for effect in effects:
		var required_flip = effect.get("flip", "none")
		if required_flip != "none" and flip_result != required_flip:
			print("EFFECT SKIPPED: Needed ", required_flip, " but got ", flip_result)
			continue

		if effect.get("target") == "defender" and defender.is_invincible:
			print("EFFECT BLOCKED: Defender is invincible - skipping ", effect["type"])
			continue

		if effect["type"] == "status":
			await main.apply_status_effect(effect, attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "toxic":
			await apply_toxic(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_damage":
			await apply_self_damage(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "energy_discard_self":
			await apply_energy_discard_self(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "energy_discard_defender":
			await apply_energy_discard_defender(effect, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "bench_damage":
			await apply_bench_damage(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "blind":
			await apply_blind_effect(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "no_damage":
			apply_no_damage_effect(attacker, is_opponent_attacking)
		if effect["type"] == "invincible":
			apply_invincible_effect(attacker, is_opponent_attacking)
		if effect["type"] == "retreat_lock":
			await apply_retreat_lock(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "draw":
			await apply_draw_effect(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_heal":
			await apply_self_heal(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "destiny_bond":
			await apply_destiny_bond(attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "shielded_damage":
			apply_shielded_damage(effect, attacker, is_opponent_attacking)
		if effect["type"] == "force_switch":
			await apply_force_switch(effect, is_opponent_attacking)
			if main._should_bail(): return
			
		if effect["type"] == "damage_reduction":
			await apply_damage_reduction(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "attack_block":
			await apply_attack_block(effect, attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_switch":
			await apply_self_switch(attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "bench_damage_single":
			await apply_bench_damage_single(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "leech_seed":
			await apply_leech_seed(attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "trainer_lock":
			await apply_trainer_lock(is_opponent_attacking)
			if main._should_bail(): return
########################################################### END EFFECT PARSING FUNCTIONS #############################################################
######################################################################################################################################################

#                ##      ##      ########  ####    ##  ########
#               ####    ####        ##     ## ##   ##     ##
#              ##  ##  ##  ##       ##     ##  ##  ##     ##
#             ##    ####    ##      ##     ##   ## ##     ##
#            ##      ##      ##  ########  ##    ####   #######

######################################################################################################################################################
################################################### SMALL FUNCTIONS TO HELP WITH CODE READABILITY ####################################################

# Function to get all basic pokemon from a given array of cards
func apply_self_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var damage = effect.get("damage", 0)
	attacker.current_hp = max(0, attacker.current_hp - damage)
	var name = attacker.metadata.get("name", "Unknown")
	var label_x = 1030 if is_opponent_attacking else 530
	await main.show_message(name.to_upper() + " DEALT " + str(damage) + " DAMAGE TO ITSELF!")
	if main._should_bail(): return
	main.show_floating_label("-" + str(damage) + "HP", Vector2(label_x, 300), true)
	main.display_hp_circles_above_align(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " took ", damage, " self-damage. HP: ", attacker.current_hp)

# Discards energy from the attacker as an attack cost
func apply_energy_discard_self(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	var energy_type = effect.get("energy_type", "any")
	var name = attacker.metadata.get("name", "Unknown")
	var to_discard: Array = []

	if count == -1:
		to_discard = attacker.attached_energies.duplicate()
	else:
		for i in range(count):
			var found = false
			for j in range(attacker.attached_energies.size() - 1, -1, -1):
				var energy = attacker.attached_energies[j]
				if energy in to_discard:
					continue
				if energy_type == "any":
					to_discard.append(energy)
					found = true
					break
				else:
					var provided = main.get_energy_provided_by_card(energy)
					if energy_type in provided:
						to_discard.append(energy)
						found = true
						break
			if not found and energy_type != "any":
				for j in range(attacker.attached_energies.size() - 1, -1, -1):
					var energy = attacker.attached_energies[j]
					if energy not in to_discard:
						to_discard.append(energy)
						break

	var discard_node = main.opponent_discard_icon if is_opponent_attacking else main.player_discard_icon
	var from_node = main.find_card_ui_for_object(attacker)
	if from_node == null:
		from_node = main.opponent_active_container if is_opponent_attacking else main.player_active_container

	for energy in to_discard:
		var energy_texture = main.get_card_texture(energy)
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		var discard_pile = main.opponent_discard_pile if is_opponent_attacking else main.player_discard_pile
		discard_pile.append(energy)
		await main.animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, main.card_scales[10])
		if main._should_bail(): return
		main.display_active_pokemon_energies(is_opponent_attacking)

	# Update discard pile display immediately (no message box)
	main.update_discard_pile_display(is_opponent_attacking)
	main.display_active_pokemon_energies(is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " discarded ", to_discard.size(), " energy cards")

# Discards energy from the defending pokemon - with selection UI for choosing which energy
func apply_energy_discard_defender(effect: Dictionary, defender: card_object, is_opponent_attacking: bool) -> void:
	if defender.attached_energies.size() == 0:
		print("EFFECT SKIPPED: Defender has no energy to discard")
		return
	var name = defender.metadata.get("name", "Unknown")
	var is_defender_player = is_opponent_attacking
	var is_defender_opponent = !is_opponent_attacking
	
	var energy_to_discard: card_object = null
	
	if is_defender_opponent:
		# Player is attacking — player chooses which of opponent's energies to discard
		main.opponent_blocker.visible = false
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(defender.attached_energies)
		main.cancel_button.visible = false
		main.header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		main.hint_label.text = "Choose an energy card to discard from the defending Pokemon"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_discard = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	elif is_defender_player:
		# Opponent is attacking — player chooses which of their own energies to discard
		main.opponent_blocker.visible = false
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(defender.attached_energies)
		main.cancel_button.visible = false
		main.header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		main.hint_label.text = "Your opponent forces you to discard an energy card"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_discard = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
	if energy_to_discard != null:
		var energy_texture = main.get_card_texture(energy_to_discard)
		var from_node = main.find_card_ui_for_object(defender)
		var defender_is_opp = is_defender_opponent
		if from_node == null:
			from_node = main.opponent_active_container if defender_is_opp else main.player_active_container
		var discard_node = main.opponent_discard_icon if defender_is_opp else main.player_discard_icon
		
		defender.attached_energies.erase(energy_to_discard)
		energy_to_discard.current_location = "discard"
		var discard_pile = main.opponent_discard_pile if defender_is_opp else main.player_discard_pile
		discard_pile.append(energy_to_discard)
		
		await main.animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, main.card_scales[10])
		if main._should_bail(): return
		main.update_discard_pile_display(defender_is_opp)
		
		await main.show_message("AN ENERGY WAS DISCARDED FROM " + name.to_upper() + "!")
		if main._should_bail(): return
		# Refresh the defender's energy display (not the attacker's)
		main.display_active_pokemon_energies(defender_is_opp)
		print("EFFECT APPLIED: Discarded energy from ", name)

# Applies damage to benched pokemon based on target scope
# Applies damage to benched pokemon based on target scope, showing floating labels sequentially
func apply_bench_damage(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var bench_target = effect.get("target", "main.opponent_bench")
	var damage = effect.get("damage", 10)
	var benches_to_hit: Array = []

	if bench_target == "main.opponent_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
		else:
			benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})
	elif bench_target == "own_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})
		else:
			benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
	elif bench_target == "all_benches":
		benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
		benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})

	for bench_info in benches_to_hit:
		var bench_container = main.opponent_bench_container if bench_info["is_opponent"] else main.player_bench_container
		for i in range(bench_info["bench"].size()):
			var pokemon = bench_info["bench"][i]
			pokemon.current_hp = max(0, pokemon.current_hp - damage)
			print("BENCH DAMAGE: ", pokemon.metadata.get("name", ""), " took ", damage, " damage. HP: ", pokemon.current_hp)
			
			# Show floating label at this bench pokemon's approximate position
			var bench_card_ui = null
			if i < bench_container.get_child_count():
				bench_card_ui = bench_container.get_child(i)
			if bench_card_ui != null and is_instance_valid(bench_card_ui):
				var label_pos = bench_card_ui.global_position + Vector2(0, -20)
				main.show_floating_label("-" + str(damage), label_pos, true)
			
			# Stagger labels by 0.1 seconds for visual sequence
			await get_tree().create_timer(0.1).timeout
			if main._should_bail(): return

# Sets the blind flag on the defending pokemon and updates icons
func apply_blind_effect(defender: card_object, is_opponent_attacking: bool) -> void:
	defender.is_blind = true
	var is_def_opponent = !is_opponent_attacking
	main.update_status_icons(defender, is_def_opponent)
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T SEE! MUST FLIP TO ATTACK!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " is now Blind")

# Sets the no_damage flag on the attacker and updates icons
func apply_no_damage_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_no_damage = true
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has no_damage shield")

# Sets the invincible flag on the attacker and updates icons
func apply_invincible_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.is_invincible = true
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " is invincible")

# Sets the retreat lock on the defending pokemon
func apply_retreat_lock(defender: card_object, is_opponent_attacking: bool) -> void:
	if is_opponent_attacking:
		main.player_retreat_disabled = true
	else:
		main.opponent_retreat_disabled = true
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T RETREAT!")
	if main._should_bail(): return
	print("EFFECT APPLIED: Retreat locked for ", defender.metadata.get("name", ""))

# Draws cards for the attacker
func apply_draw_effect(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	for i in range(count):
		await main.draw_card_from_deck(is_opponent_attacking)
		if main._should_bail(): return
	var who = "CPU" if is_opponent_attacking else "Player"
	await main.show_message(who.to_upper() + " DREW " + str(count) + " CARD(S)!")
	if main._should_bail(): return
	if is_opponent_attacking:
		main.refresh_hand_display(true)
	else:
		main.refresh_hand_display(false)
	print("EFFECT APPLIED: ", who, " drew ", count, " card(s)")

# Heals damage from the attacker
func apply_self_heal(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var name = attacker.metadata.get("name", "Unknown")
	var max_hp = int(attacker.metadata.get("hp", "0"))
	var amount = effect.get("amount", -1)
	var healed = 0

	if amount == -1:
		healed = max_hp - attacker.current_hp
		attacker.current_hp = max_hp
	else:
		var heal_hp = amount * 10
		healed = min(heal_hp, max_hp - attacker.current_hp)
		attacker.current_hp = min(max_hp, attacker.current_hp + heal_hp)

	if healed > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent_attacking)
		await main.show_message(name.to_upper() + " HEALED " + str(healed) + " HP!")
		if main._should_bail(): return
		print("EFFECT APPLIED: ", name, " healed ", healed, " HP. Now at: ", attacker.current_hp)
	else:
		print("EFFECT SKIPPED: ", name, " already at full HP")

# Applies the toxic upgrade setting poison damage to 20
func apply_toxic(defender: card_object, is_opponent_attacking: bool) -> void:
	defender.is_poisoned = true
	defender.poison_damage = 20
	var is_def_opponent = !is_opponent_attacking
	main.update_status_icons(defender, is_def_opponent)
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " poison upgraded to Toxic (20 damage)")

# Sets destiny bond flag on the attacker
func apply_destiny_bond(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_destiny_bond = true
	main.update_status_icons(attacker, is_opponent_attacking)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS BOUND BY DESTINY!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has Destiny Bond")

# Sets the shielded damage threshold on the attacker (Onix Harden)
func apply_shielded_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var threshold = effect.get("threshold", 30)
	attacker.shielded_damage_threshold = threshold
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " shielded damage threshold = ", threshold)

# Forces the defending player to switch their active pokemon with a bench pokemon
# chooser: "defender" = defender picks (Whirlwind), "attacker" = attacker picks (Lure)
func apply_force_switch(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var target_bench = main.player_bench if is_opponent_attacking else main.opponent_bench
	var is_target_opponent = !is_opponent_attacking
	var chooser = effect.get("chooser", "defender")
	
	if target_bench.size() == 0:
		print("FORCE SWITCH: No bench pokemon available")
		return
	
	var new_active: card_object = null
	
	if is_target_opponent:
		# Target is the opponent (CPU)
		if chooser == "attacker":
			# Lure: PLAYER picks from opponent's bench
			main.opponent_blocker.visible = false
			main.forced_switch_selection_active = true
			main.show_enlarged_array_selection_mode(main.opponent_bench)
			main.cancel_button.visible = false
			main.header_label.text = "CHOOSE A POKEMON TO SWITCH IN!"
			main.hint_label.text = "Select an opponent's bench Pokemon to force into active"
			main.action_button.text = "FORCE SWITCH"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.forced_switch_chosen
			if main._should_bail(): return
			new_active = main.selected_card_for_action
			main.forced_switch_selection_active = false
			main.hide_selection_mode_display_main()
			main.opponent_blocker.visible = true
		else:
			# Whirlwind: CPU picks its own bench replacement
			var cpu_eval = main.cpu_ai.build_cpu_evaluation()
			new_active = main.cpu_ai.pick_best_bench_replacement(main.opponent_bench, main.player_active_pokemon, cpu_eval)
			if new_active == null:
				new_active = main.opponent_bench[0]
		
		if new_active != null:
			var old_active = main.opponent_active_pokemon
			await main.show_message("OPPONENT WAS FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			if main._should_bail(): return
			
			# Animate the swap
			await main.animate_retreat(old_active, new_active, [], true)
			if main._should_bail(): return
			
			# Perform the swap
			main.opponent_bench.erase(new_active)
			main.opponent_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			main.opponent_active_pokemon = new_active
			main.clear_all_statuses(old_active, true)
			
			main.display_pokemon(true)
			main.display_active_pokemon_energies(true)
	else:
		# Target is the player
		if chooser == "attacker":
			# Lure: CPU picks from player's bench (pick the weakest)
			var worst_pokemon: card_object = null
			var worst_hp = 9999
			for bp in main.player_bench:
				if bp.current_hp < worst_hp:
					worst_hp = bp.current_hp
					worst_pokemon = bp
			new_active = worst_pokemon if worst_pokemon else main.player_bench[0]
		else:
			# Whirlwind: Player picks their own bench replacement
			main.opponent_blocker.visible = false
			main.forced_switch_selection_active = true
			main.show_enlarged_array_selection_mode(main.player_bench)
			main.cancel_button.visible = false
			main.header_label.text = "FORCED SWITCH!"
			main.hint_label.text = "Choose a bench Pokemon to switch in as your new active"
			main.action_button.text = "SWITCH IN"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.forced_switch_chosen
			if main._should_bail(): return
			new_active = main.selected_card_for_action
			main.forced_switch_selection_active = false
			main.hide_selection_mode_display_main()
			main.opponent_blocker.visible = true
		
		if new_active != null:
			var old_active = main.player_active_pokemon
			await main.show_message("FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			if main._should_bail(): return
			
			await main.animate_retreat(old_active, new_active, [], false)
			if main._should_bail(): return
			
			main.player_bench.erase(new_active)
			main.player_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			main.player_active_pokemon = new_active
			main.clear_all_statuses(old_active, false)
			
			main.display_pokemon(false)
			main.display_active_pokemon_energies(false)



# Applies damage reduction for next turn (Minimize/Pounce/Snivel)
func apply_damage_reduction(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var amount = effect.get("amount", 20)
	attacker.damage_reduction_next_turn = amount
	main.update_status_icons(attacker, is_opponent_attacking)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " REDUCES DAMAGE BY " + str(amount) + " NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " damage reduction = ", amount)

# Applies attack block for next turn (Tail Wag/Leer)
func apply_attack_block(effect: Dictionary, attacker: card_object, defender: card_object, is_opponent_attacking: bool) -> void:
	defender.attack_blocked_next_turn = true
	defender.attack_blocked_by_id = attacker.get_instance_id()
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T ATTACK " + attacker.metadata.get("name", "").to_upper() + " NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " can't attack ", attacker.metadata.get("name", ""))

# Self switch with bench (Exeggutor Teleport)
func apply_self_switch(attacker: card_object, is_opponent_attacking: bool) -> void:
	var bench = main.opponent_bench if is_opponent_attacking else main.player_bench
	if bench.size() == 0:
		await main.show_message("NO BENCH POKEMON TO SWITCH WITH!")
		if main._should_bail(): return
		return
	
	var new_active: card_object = null
	if is_opponent_attacking:
		# CPU picks best replacement
		var cpu_eval = main.cpu_ai.build_cpu_evaluation()
		new_active = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, cpu_eval)
		if new_active == null:
			new_active = bench[0]
	else:
		# Player picks
		main.opponent_blocker.visible = false
		main.forced_switch_selection_active = true
		main.show_enlarged_array_selection_mode(bench)
		main.cancel_button.visible = true
		main.header_label.text = "TELEPORT: CHOOSE REPLACEMENT"
		main.hint_label.text = "Select a bench Pokemon to switch in"
		main.action_button.text = "SWITCH"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.forced_switch_chosen
		if main._should_bail(): return
		new_active = main.selected_card_for_action
		main.forced_switch_selection_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
	if new_active == null:
		return
	
	var old_active = attacker
	await main.show_message(old_active.metadata["name"].to_upper() + " SWITCHED WITH " + new_active.metadata["name"].to_upper() + "!")
	if main._should_bail(): return
	await main.animate_retreat(old_active, new_active, [], is_opponent_attacking)
	if main._should_bail(): return
	
	bench.erase(new_active)
	bench.append(old_active)
	old_active.current_location = "bench"
	new_active.current_location = "active"
	if is_opponent_attacking:
		main.opponent_active_pokemon = new_active
	else:
		main.player_active_pokemon = new_active
	main.clear_all_statuses(old_active, is_opponent_attacking)
	main.display_pokemon(is_opponent_attacking)
	main.display_active_pokemon_energies(is_opponent_attacking)

# Bench damage to a single chosen target (Pikachu Spark)
func apply_bench_damage_single(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var damage = effect.get("damage", 10)
	var target_bench = main.player_bench if is_opponent_attacking else main.opponent_bench
	var is_target_opponent = !is_opponent_attacking
	
	if target_bench.size() == 0:
		print("BENCH DAMAGE SINGLE: No bench targets")
		return
	
	var target: card_object = null
	
	if is_target_opponent:
		# CPU is the target side — CPU picks which bench pokemon takes damage
		# For player attacking: player picks opponent's bench target
		main.opponent_blocker.visible = false
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_bench)
		main.cancel_button.visible = false
		main.header_label.text = "CHOOSE A BENCHED POKEMON"
		main.hint_label.text = "This attack does " + str(damage) + " damage to 1 benched Pokemon"
		main.action_button.text = "DEAL DAMAGE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		target = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	else:
		# Player is the target side — CPU chooses which player bench to damage
		var weakest_hp = 9999
		for bp in target_bench:
			if bp.current_hp < weakest_hp:
				weakest_hp = bp.current_hp
				target = bp
		if target == null and target_bench.size() > 0:
			target = target_bench[0]
	
	if target != null:
		target.current_hp = max(0, target.current_hp - damage)
		await main.show_message(target.metadata.get("name", "").to_upper() + " TOOK " + str(damage) + " BENCH DAMAGE!")
		if main._should_bail(): return
		print("BENCH DAMAGE SINGLE: ", target.metadata.get("name", ""), " took ", damage)

# Leech Seed: heal 1 damage counter from attacker if damage was dealt
func apply_leech_seed(attacker: card_object, defender: card_object, is_opponent_attacking: bool) -> void:
	var max_hp = int(attacker.metadata.get("hp", "0"))
	if attacker.current_hp < max_hp and defender.current_hp > 0:
		attacker.current_hp = min(max_hp, attacker.current_hp + 10)
		main.display_hp_circles_above_align(attacker, is_opponent_attacking)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " HEALED 10 HP!")
		if main._should_bail(): return
		print("LEECH SEED: ", attacker.metadata.get("name", ""), " healed 10 HP")

# SWORDS DANCE: Set flag to boost Slash next turn
func execute_swords_dance(attacker: card_object, is_opponent: bool) -> void:
	attacker.swords_dance_active = true
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " USED SWORDS DANCE! SLASH POWERED UP!")
	if main._should_bail(): return
	print("SWORDS DANCE: ", attacker.metadata.get("name", ""), " Slash buffed for next turn")

# HURRICANE: Deal 30 damage, return defender to hand unless KO'd
func execute_hurricane(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
	if main._should_bail(): return
	
	# If defender is NOT KO'd, return it and all attached cards to hand
	if defender.current_hp > 0:
		# Defender's hand is on the opposite side of the attacker
		var target_hand = main.player_hand if is_opponent else main.opponent_hand
		var target_bench = main.player_bench if is_opponent else main.opponent_bench
		
		# Move all attached energies to hand
		for energy in defender.attached_energies:
			target_hand.append(energy)
		defender.attached_energies.clear()
		
		# Move all pre-evolutions to hand
		for pre_evo in defender.attached_pre_evolutions:
			target_hand.append(pre_evo)
		defender.attached_pre_evolutions.clear()
		
		# Move defender itself to hand
		target_hand.append(defender)
		defender.current_location = "hand"
		
		# Remove from active slot on defender's side
		if is_opponent:
			# CPU attacked, defender is player's active
			if defender == main.player_active_pokemon:
				main.player_active_pokemon = null
			else:
				target_bench.erase(defender)
		else:
			# Player attacked, defender is opponent's active
			if defender == main.opponent_active_pokemon:
				main.opponent_active_pokemon = null
			else:
				target_bench.erase(defender)
		
		main.clear_all_statuses(defender, !is_opponent)
		await main.show_message(defender.metadata.get("name", "").to_upper() + " WAS RETURNED TO HAND!")
		if main._should_bail(): return
		main.display_pokemon(!is_opponent)
		main.refresh_hand_display(!is_opponent)
		main.display_active_pokemon_energies(!is_opponent)
		
		# Handle post-knockout replacement for the returned pokemon's side
		await main.handle_post_knockout(!is_opponent)
		if main._should_bail(): return

# CHAIN LIGHTNING: 20 to defender, 10 to each same-type bench (both sides)
func execute_chain_lightning(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(20, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 20)
	if main._should_bail(): return
	
	# If defender is Colorless, no chain lightning
	var defender_types = defender.metadata.get("types", ["Colorless"])
	if "Colorless" in defender_types:
		await main.show_message("NO CHAIN LIGHTNING - COLORLESS TARGET!")
		if main._should_bail(): return
		return
	
	# Damage all benched pokemon of the same type (BOTH sides)
	var target_type = defender_types[0]
	var all_benches = [
		{"bench": main.player_bench, "is_opponent": false},
		{"bench": main.opponent_bench, "is_opponent": true}
	]
	for bench_info in all_benches:
		for pokemon in bench_info["bench"]:
			var pokemon_types = pokemon.metadata.get("types", [])
			if target_type in pokemon_types:
				pokemon.current_hp = max(0, pokemon.current_hp - 10)
				print("CHAIN LIGHTNING: ", pokemon.metadata.get("name", ""), " took 10 damage")
	await main.show_message("CHAIN LIGHTNING HIT ALL " + target_type.to_upper() + " BENCHED POKEMON!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# BIG EGGSPLOSION: Flip coins = attached energy, 20 per heads
func execute_big_eggsplosion(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var energy_count = attacker.attached_energies.size()
	if energy_count == 0:
		await main.show_message("NO ENERGY ATTACHED - 0 DAMAGE!")
		if main._should_bail(): return
		return
	
	await main.show_message("FLIPPING " + str(energy_count) + " COINS!")
	if main._should_bail(): return
	
	var heads = 0
	var use_silent = energy_count > 1
	for i in range(energy_count):
		var coin = await main.flip_coin(use_silent)
		if coin:
			heads += 1
	
	var base_damage = 20 * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(base_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return

# BOYFRIENDS (Nidoqueen): 20 + 20 per Nidoking in play
func execute_boyfriends(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var nidoking_count = 0
	var all_pokemon = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)
	for p in all_pokemon:
		if p.metadata.get("name", "") == "Nidoking":
			nidoking_count += 1
	
	var base_damage = 20 + (20 * nidoking_count)
	await main.show_message("BOYFRIENDS: " + str(nidoking_count) + " NIDOKING IN PLAY! " + str(base_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return

# MEGA DRAIN: Deal 40 damage, heal half (rounded up to nearest 10)
func execute_mega_drain(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(40, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 40)
	if main._should_bail(): return
	
	# Heal attacker for half of actual damage dealt (rounded up to nearest 10)
	var actual_damage = min(final_damage, defender.current_hp + final_damage)  # damage before KO check
	var heal_amount = int(ceil(actual_damage / 2.0 / 10.0)) * 10
	var max_hp = int(attacker.metadata.get("hp", "0"))
	var healed = min(heal_amount, max_hp - attacker.current_hp)
	if healed > 0:
		attacker.current_hp = min(max_hp, attacker.current_hp + healed)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " HEALED " + str(healed) + " HP!")
		if main._should_bail(): return

# LEECH LIFE: Deal damage, heal equal to damage dealt after W/R
func execute_leech_life(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return
	
	# Heal attacker equal to final damage dealt
	var max_hp = int(attacker.metadata.get("hp", "0"))
	var healed = min(final_damage, max_hp - attacker.current_hp)
	if healed > 0:
		attacker.current_hp = min(max_hp, attacker.current_hp + healed)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " DRAINED " + str(healed) + " HP!")
		if main._should_bail(): return

# CALL FOR FAMILY/FRIEND: Search deck for specific basic pokemon
func execute_call_for_pokemon(attacker: card_object, is_opponent: bool, search_names: Array, search_type: String) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	if bench.size() >= 5:
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	
	# Find matching basic pokemon in deck
	var valid_cards: Array = []
	for card in deck:
		var subtypes = card.metadata.get("subtypes", [])
		if "Basic" not in subtypes:
			continue
		var card_name = card.metadata.get("name", "")
		if search_names.size() > 0:
			if card_name in search_names:
				valid_cards.append(card)
		elif search_type != "":
			var card_types = card.metadata.get("types", [])
			if search_type in card_types:
				valid_cards.append(card)
		else:
			valid_cards.append(card)
	
	if valid_cards.size() == 0:
		await main.show_message("NO MATCHING POKEMON FOUND IN DECK!")
		if main._should_bail(): return
		# Shuffle deck anyway
		deck.shuffle()
		return
	
	var chosen: card_object = null
	if is_opponent:
		# CPU picks the card with the highest HP (best bench addition)
		var best_hp = -1
		for card in valid_cards:
			var hp = int(card.metadata.get("hp", "0"))
			if hp > best_hp:
				best_hp = hp
				chosen = card
	else:
		# Player picks from valid cards
		main.opponent_blocker.visible = false
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(valid_cards)
		main.cancel_button.visible = true
		main.header_label.text = "CHOOSE A POKEMON FROM YOUR DECK"
		main.hint_label.text = "Select a Basic Pokemon to put on your bench"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
	if chosen != null and bench.size() < 5:
		deck.erase(chosen)
		chosen.current_location = "bench"
		chosen.current_hp = int(chosen.metadata.get("hp", "0"))
		chosen.placed_on_field_this_turn = true
		bench.append(chosen)
		await main.show_message(chosen.metadata.get("name", "").to_upper() + " WAS PLACED ON THE BENCH!")
		if main._should_bail(): return
		main.display_pokemon(is_opponent)
	
	# Shuffle deck after search
	deck.shuffle()
######################################################### SPECIAL ATTACK FUNCTIONS ############################################################

# METRONOME (Clefairy): Copy one of the opponent's attacks and execute it

######################################################################################################################################################
############################################## BASE3 (FOSSIL) ATTACK EFFECTS #########################################################################
######################################################################################################################################################

# TRAINER LOCK (Psyduck Headache): Block opponent trainer play next turn
func apply_trainer_lock(is_opponent_attacking: bool) -> void:
	if is_opponent_attacking:
		main.trainer_effects.player_trainer_locked = true
	else:
		main.trainer_effects.opponent_trainer_locked = true
	await main.show_message("OPPONENT CAN'T PLAY TRAINER CARDS NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: Trainer lock for next turn")

# SONICBOOM (Magneton): Fixed damage ignoring Weakness and Resistance
func execute_sonicboom(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var final_damage = base_damage
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	
	# Display WITHOUT W/R modifiers — pass empty modifiers and use base_damage directly
	var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
	main.show_floating_label("-" + str(final_damage) + "HP", defender_label_pos, true)
	defender.current_hp = max(0, defender.current_hp - final_damage)
	main.display_hp_circles_above_align(defender, !is_opponent)
	await main.show_message("SONICBOOM: " + str(final_damage) + " DAMAGE! (IGNORES W/R)")
	if main._should_bail(): return
	print("SONICBOOM: ", final_damage, " damage (no W/R)")

# WILDFIRE (Moltres): Discard any number of Fire Energy, mill that many from opponent deck
func execute_wildfire(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	# Count Fire Energy attached
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	var discard_count = 0
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if is_opponent:
		# CPU strategy: discard all fire energy for maximum mill damage
		# unless it would cripple attack readiness
		var target_deck = main.player_deck
		discard_count = min(fire_energies.size(), target_deck.size())
		if discard_count == 0:
			await main.show_message("OPPONENT'S DECK IS EMPTY!")
			if main._should_bail(): return
			return
		for i in range(discard_count):
			var e = fire_energies[i]
			attacker.attached_energies.erase(e)
			e.current_location = "discard"
			discard_pile.append(e)
		main.display_active_pokemon_energies(true)
	else:
		# Player selects fire energies one at a time, cancel to stop
		await main.show_message("WILDFIRE: SELECT FIRE ENERGY TO DISCARD (CANCEL TO STOP)")
		if main._should_bail(): return
		
		var keep_discarding = true
		while keep_discarding and fire_energies.size() > 0:
			main.trainer_energy_selection_active = true
			main.show_enlarged_array_selection_mode(fire_energies)
			main.header_label.text = "WILDFIRE: SELECT FIRE ENERGY"
			main.hint_label.text = "Each energy discarded mills 1 card from opponent's deck"
			main.action_button.text = "DISCARD"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = true
			await main.trainer_target_selected
			if main._should_bail(): return
			var selected = main.selected_card_for_action
			main.trainer_energy_selection_active = false
			main.hide_selection_mode_display_main()
			
			if selected == null:
				keep_discarding = false
			else:
				attacker.attached_energies.erase(selected)
				selected.current_location = "discard"
				discard_pile.append(selected)
				fire_energies.erase(selected)
				discard_count += 1
				main.display_active_pokemon_energies(false)
	
	if discard_count == 0:
		return
	
	# Mill cards from opponent's deck
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	var milled = min(discard_count, target_deck.size())
	for i in range(milled):
		var card = target_deck.pop_front()
		card.current_location = "discard"
		target_discard.append(card)
	
	main.update_discard_pile_display(!is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("WILDFIRE: DISCARDED " + str(milled) + " CARDS FROM OPPONENT'S DECK!")
	if main._should_bail(): return
	print("WILDFIRE: Milled ", milled, " cards from opponent deck")

# GIGASHOCK (Raichu): 30 damage + 10 to up to 3 opponent bench Pokemon
func execute_gigashock(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	# Deal 30 to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
	if main._should_bail(): return
	
	# Deal 10 to up to 3 opponent bench pokemon
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var is_target_opponent = !is_opponent
	
	if target_bench.size() == 0:
		print("GIGASHOCK: No bench targets")
		return
	
	if target_bench.size() <= 3:
		# Hit all bench pokemon
		for bp in target_bench:
			bp.current_hp = max(0, bp.current_hp - 10)
			print("GIGASHOCK: ", bp.metadata.get("name", ""), " took 10 bench damage")
		await main.show_message("GIGASHOCK HIT ALL BENCHED POKEMON FOR 10 DAMAGE!")
		if main._should_bail(): return
	else:
		# Need to choose 3 targets
		if is_target_opponent:
			# Player picks 3 from opponent bench
			var targets_chosen: Array = []
			for pick in range(3):
				var remaining: Array = []
				for bp in target_bench:
					if bp not in targets_chosen:
						remaining.append(bp)
				if remaining.size() == 0:
					break
				main.opponent_blocker.visible = false
				main.trainer_pokemon_selection_active = true
				main.show_enlarged_array_selection_mode(remaining)
				main.cancel_button.visible = false
				main.header_label.text = "GIGASHOCK: CHOOSE TARGET " + str(pick + 1) + " OF 3"
				main.hint_label.text = "Select a benched Pokemon to deal 10 damage"
				main.action_button.text = "SHOCK"
				main.action_button.disabled = true
				main.action_button.theme = main.theme_disabled
				await main.trainer_target_selected
				if main._should_bail(): return
				var chosen = main.selected_card_for_action
				main.trainer_pokemon_selection_active = false
				main.hide_selection_mode_display_main()
				main.opponent_blocker.visible = true
				if chosen != null:
					targets_chosen.append(chosen)
			for bp in targets_chosen:
				bp.current_hp = max(0, bp.current_hp - 10)
				print("GIGASHOCK: ", bp.metadata.get("name", ""), " took 10 bench damage")
			await main.show_message("GIGASHOCK HIT " + str(targets_chosen.size()) + " BENCHED POKEMON!")
			if main._should_bail(): return
		else:
			# CPU picks 3 weakest from player bench
			var targets = main.cpu_ai.cpu_choose_bench_damage_targets(3, 10)
			for bp in targets:
				bp.current_hp = max(0, bp.current_hp - 10)
				print("GIGASHOCK: ", bp.metadata.get("name", ""), " took 10 bench damage")
			await main.show_message("GIGASHOCK HIT " + str(targets.size()) + " BENCHED POKEMON!")
			if main._should_bail(): return
	
	# Check for bench KOs from Gigashock damage
	await main.check_all_knockouts()
	if main._should_bail(): return

# THUNDERSTORM (Zapdos): 40 damage + flip per bench, heads=20 damage, tails count = self damage
func execute_thunderstorm(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	# Deal 40 to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(40, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 40)
	if main._should_bail(): return
	
	# Flip for each opponent bench pokemon
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var tails_count = 0
	
	if target_bench.size() > 0:
		var use_silent = target_bench.size() > 1
		for bp in target_bench:
			var coin = await main.flip_coin(use_silent)
			if coin:
				bp.current_hp = max(0, bp.current_hp - 20)
				print("THUNDERSTORM: ", bp.metadata.get("name", ""), " took 20 bench damage (heads)")
			else:
				tails_count += 1
				print("THUNDERSTORM: Tails for ", bp.metadata.get("name", ""))
		await main.show_message("THUNDERSTORM: " + str(target_bench.size() - tails_count) + " HEADS, " + str(tails_count) + " TAILS!")
		if main._should_bail(): return
	
	# Self-damage: 10 × number of tails
	if tails_count > 0:
		var self_damage = tails_count * 10
		attacker.current_hp = max(0, attacker.current_hp - self_damage)
		var label_x = 1030 if is_opponent else 530
		main.show_floating_label("-" + str(self_damage) + "HP", Vector2(label_x, 300), true)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK " + str(self_damage) + " RECOIL DAMAGE!")
		if main._should_bail(): return
	
	# Check for bench and self KOs from Thunderstorm damage
	await main.check_all_knockouts()
	if main._should_bail(): return

# PROPHECY (Hypno): Look at top 3 cards of either deck and rearrange
func execute_prophecy(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	if is_opponent:
		# CPU strategy: look at own deck top 3 and rearrange for best draws
		# Simple: sort by priority (energy first if needed, then pokemon, then trainers)
		var deck = main.opponent_deck
		if deck.size() < 2:
			return
		var count = min(3, deck.size())
		# CPU just peeks but doesn't meaningfully rearrange (too complex for AI)
		await main.show_message("OPPONENT USED PROPHECY TO REARRANGE DECK!")
		if main._should_bail(): return
		# Simple heuristic: put energy cards on top if CPU needs energy
		var top_cards = []
		for i in range(count):
			top_cards.append(deck[i])
		# Sort: energy needed? put energy first
		var active = main.opponent_active_pokemon
		var needs_energy = false
		if active != null:
			for attack in active.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, active) > 0:
					needs_energy = true
					break
		if needs_energy:
			top_cards.sort_custom(func(a, b):
				var a_is_energy = a.metadata.get("supertype", "") == "Energy"
				var b_is_energy = b.metadata.get("supertype", "") == "Energy"
				if a_is_energy and not b_is_energy: return true
				if b_is_energy and not a_is_energy: return false
				return false
			)
			for i in range(count):
				deck[i] = top_cards[i]
		print("PROPHECY: CPU rearranged top ", count, " cards")
	else:
		# Player chooses which deck to look at, then rearranges
		# Step 1: Choose deck
		await main.show_message("PROPHECY: CHOOSE A DECK TO LOOK AT")
		if main._should_bail(): return
		
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
				continue
			child.queue_free()
		
		var btn_own = Button.new()
		btn_own.text = "YOUR DECK"
		btn_own.custom_minimum_size = Vector2(350, 50)
		btn_own.theme = main.theme_green
		main.attack_buttons_container.add_child(btn_own)
		btn_own.pressed.connect(func(): main.special_attack_selected.emit(0))
		
		var btn_opp = Button.new()
		btn_opp.text = "OPPONENT'S DECK"
		btn_opp.custom_minimum_size = Vector2(350, 50)
		btn_opp.theme = main.theme_green
		main.attack_buttons_container.add_child(btn_opp)
		btn_opp.pressed.connect(func(): main.special_attack_selected.emit(1))
		
		var deck_choice = await main.special_attack_selected
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
		
		var deck = main.player_deck if deck_choice == 0 else main.opponent_deck
		var deck_name = "YOUR" if deck_choice == 0 else "OPPONENT'S"
		
		if deck.size() == 0:
			await main.show_message(deck_name + " DECK IS EMPTY!")
			if main._should_bail(): return
			return
		
		var count = min(3, deck.size())
		var top_cards: Array = []
		for i in range(count):
			top_cards.append(deck[i])
		
		# Show cards and let player reorder using selection mode
		# Player picks cards in the order they want them (first pick = top of deck)
		var reordered: Array = []
		var remaining = top_cards.duplicate()
		
		for pick in range(count):
			if remaining.size() == 1:
				reordered.append(remaining[0])
				break
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(remaining)
			main.cancel_button.visible = false
			main.header_label.text = "PROPHECY: PICK CARD FOR POSITION " + str(pick + 1)
			main.hint_label.text = "This card will be " + (["1st (TOP)", "2nd", "3rd"])[pick] + " from top"
			main.action_button.text = "PLACE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.trainer_target_selected
			if main._should_bail(): return
			var chosen = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
			if chosen != null:
				reordered.append(chosen)
				remaining.erase(chosen)
		
		# Apply reorder to deck
		for i in range(reordered.size()):
			deck[i] = reordered[i]
		
		await main.show_message("PROPHECY: REARRANGED TOP " + str(count) + " CARDS OF " + deck_name + " DECK!")
		if main._should_bail(): return
		print("PROPHECY: Player rearranged top ", count, " cards of ", deck_name, " deck")

# ENERGY CONVERSION (Gastly): Retrieve up to 2 Energy cards from discard, 10 self damage
func execute_energy_conversion(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	# Find energy cards in discard
	var energy_in_discard: Array = []
	for card in discard:
		if card.metadata.get("supertype", "") == "Energy":
			energy_in_discard.append(card)
	
	if energy_in_discard.size() == 0:
		await main.show_message("NO ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
	else:
		var retrieve_count = min(2, energy_in_discard.size())
		
		if is_opponent:
			# CPU picks best energy cards
			for i in range(retrieve_count):
				if energy_in_discard.size() == 0:
					break
				var chosen = energy_in_discard[0]
				discard.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				energy_in_discard.erase(chosen)
			main.refresh_hand_display(true)
			main.update_discard_pile_display(true)
			await main.show_message("ENERGY CONVERSION: RETRIEVED " + str(retrieve_count) + " ENERGY!")
			if main._should_bail(): return
		else:
			# Player selects up to 2 energy cards from discard
			var retrieved = 0
			for pick in range(retrieve_count):
				if energy_in_discard.size() == 0:
					break
				main.trainer_pokemon_selection_active = true
				main.show_enlarged_array_selection_mode(energy_in_discard)
				main.cancel_button.visible = (pick > 0)  # Can cancel after first pick
				main.header_label.text = "ENERGY CONVERSION: PICK ENERGY " + str(pick + 1)
				main.hint_label.text = "Select an Energy card to add to your hand"
				main.action_button.text = "RETRIEVE"
				main.action_button.disabled = true
				main.action_button.theme = main.theme_disabled
				await main.trainer_target_selected
				if main._should_bail(): return
				var chosen = main.selected_card_for_action
				main.trainer_pokemon_selection_active = false
				main.hide_selection_mode_display_main()
				if chosen == null:
					break
				discard.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				energy_in_discard.erase(chosen)
				retrieved += 1
			main.refresh_hand_display(false)
			main.update_discard_pile_display(false)
			if retrieved > 0:
				await main.show_message("ENERGY CONVERSION: RETRIEVED " + str(retrieved) + " ENERGY!")
				if main._should_bail(): return
	
	# Self damage: 10 to Gastly
	attacker.current_hp = max(0, attacker.current_hp - 10)
	var label_x = 1030 if is_opponent else 530
	main.show_floating_label("-10HP", Vector2(label_x, 300), true)
	main.display_hp_circles_above_align(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK 10 RECOIL DAMAGE!")
	if main._should_bail(): return
	print("ENERGY CONVERSION: Retrieved energy, 10 self damage")

# SPACING OUT (Slowpoke): Flip, heads = remove 1 damage counter. Can't use if no damage.
func execute_spacing_out(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	var max_hp = int(attacker.metadata.get("hp", "0"))
	if attacker.current_hp >= max_hp:
		await main.show_message("SPACING OUT FAILED! NO DAMAGE TO HEAL!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin()
	if coin:
		attacker.current_hp = min(max_hp, attacker.current_hp + 10)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message("SPACING OUT: HEALED 10 HP!")
		if main._should_bail(): return
	else:
		await main.show_message("SPACING OUT: TAILS! NOTHING HAPPENED!")
		if main._should_bail(): return
	print("SPACING OUT: coin=", "heads" if coin else "tails")

# SCAVENGE (Slowpoke): Discard 1 Psychic Energy, retrieve a Trainer from discard
func execute_scavenge(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	# Check for Psychic Energy attached
	var psychic_energy: card_object = null
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Psychic" in provided:
			psychic_energy = e
			break
	
	if psychic_energy == null:
		await main.show_message("NO PSYCHIC ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	# Find trainer cards in discard
	var trainers_in_discard: Array = []
	for card in discard:
		if card.metadata.get("supertype", "") == "Trainer":
			trainers_in_discard.append(card)
	
	if trainers_in_discard.size() == 0:
		await main.show_message("NO TRAINER CARDS IN DISCARD PILE!")
		if main._should_bail(): return
		return
	
	# Discard the Psychic Energy
	attacker.attached_energies.erase(psychic_energy)
	psychic_energy.current_location = "discard"
	discard.append(psychic_energy)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	var chosen: card_object = null
	if is_opponent:
		# CPU picks the highest scored trainer
		var best_score = -999.0
		for card in trainers_in_discard:
			var score = main.cpu_ai.cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				chosen = card
	else:
		# Player selects
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(trainers_in_discard)
		main.cancel_button.visible = false
		main.header_label.text = "SCAVENGE: CHOOSE A TRAINER CARD"
		main.hint_label.text = "Select a Trainer to retrieve from discard"
		main.action_button.text = "RETRIEVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	
	if chosen != null:
		discard.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("SCAVENGE: RETRIEVED " + chosen.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("SCAVENGE: Retrieved ", chosen.metadata.get("name", ""))

# ABSORB (Kabutops): 40 damage, heal half of damage dealt (rounded up to nearest 10)
# This is identical to execute_mega_drain — reuse it directly via routing

######################################################################################################################################################
################################################### BASE5 (TEAM ROCKET) ATTACK EFFECTS ###############################################################
######################################################################################################################################################

# Dark Arbok - Stare: Choose 1 of opponent's Pokemon, 10 damage no W/R, disable power
func execute_stare(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var is_target_opponent = !is_opponent
	var target_bench: Array
	var target_active: card_object
	var all_targets: Array = []
	
	if is_target_opponent:
		target_bench = main.opponent_bench
		target_active = main.opponent_active_pokemon
	else:
		target_bench = main.player_bench
		target_active = main.player_active_pokemon
	
	if target_active != null:
		all_targets.append(target_active)
	all_targets.append_array(target_bench)
	
	if all_targets.size() == 0:
		await main.show_message("NO VALID TARGETS!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		# Player chooses target
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(all_targets)
		main.header_label.text = "CHOOSE A POKÉMON TO DAMAGE"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	else:
		# CPU picks lowest HP target for best KO chance
		var targets = all_targets.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]
	
	if selected == null:
		return
	
	# Apply 10 damage directly (no W/R)
	selected.current_hp = max(0, selected.current_hp - 10)
	var is_selected_opponent = is_target_opponent
	main.display_hp_circles_above_align(selected, is_selected_opponent)
	await main.show_message("STARE DEALT 10 DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	# Disable power if target has one
	var abilities = selected.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("type", "") == "Pokémon Power" or ability.get("type", "") == "Pokemon Power":
			selected.power_disabled_until_end_of_next_turn = true
			await main.show_message(selected.metadata.get("name", "").to_upper() + "'S POWER IS DISABLED!")
			if main._should_bail(): return
			break
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Stare on ", selected.metadata.get("name", ""))

# Dark Golbat - Flitter / Diglett - Dig Under / Meowth - Coin Hurl: Choose opponent Pokemon, X damage no W/R
func execute_snipe_no_wr(attacker: card_object, defender: card_object, is_opponent: bool, damage: int, requires_flip: bool = false) -> void:
	var is_target_opponent = !is_opponent
	var target_bench: Array
	var target_active: card_object
	var all_targets: Array = []
	
	if is_target_opponent:
		target_bench = main.opponent_bench
		target_active = main.opponent_active_pokemon
	else:
		target_bench = main.player_bench
		target_active = main.player_active_pokemon
	
	if target_active != null:
		all_targets.append(target_active)
	all_targets.append_array(target_bench)
	
	if all_targets.size() == 0:
		await main.show_message("NO VALID TARGETS!")
		if main._should_bail(): return
		return
	
	if requires_flip:
		var coin = await main.flip_coin()
		if not coin:
			await main.show_message("TAILS! ATTACK MISSED!")
			if main._should_bail(): return
			return
	
	var selected: card_object = null
	
	if not is_opponent:
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(all_targets)
		main.header_label.text = "CHOOSE A POKÉMON TO DAMAGE"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	else:
		var targets = all_targets.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]
	
	if selected == null:
		return
	
	selected.current_hp = max(0, selected.current_hp - damage)
	var is_selected_opponent = is_target_opponent
	main.display_hp_circles_above_align(selected, is_selected_opponent)
	await main.show_message(str(damage) + " DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "! (NO W/R)")
	if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Snipe no W/R ", damage, " on ", selected.metadata.get("name", ""))

# Dark Charizard - Continuous Fireball: Flip coins = Fire Energy count, 50×heads, discard heads Fire Energy
func execute_continuous_fireball(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	
	var flip_count = fire_energies.size()
	var heads_count = 0
	for i in range(flip_count):
		var coin = await main.flip_coin(flip_count > 1)
		if coin:
			heads_count += 1
	
	var total_damage = 50 * heads_count
	await main.show_message("GOT " + str(heads_count) + " HEADS! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			
			if main.check_defender_invincible(defender, !is_opponent):
				pass
			else:
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
	
	# Discard Fire Energy equal to heads count
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var to_discard = min(heads_count, fire_energies.size())
	for i in range(to_discard):
		var energy = fire_energies[i]
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		discard_pile.append(energy)
	
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	if to_discard > 0:
		await main.show_message("DISCARDED " + str(to_discard) + " FIRE ENERGY!")
		if main._should_bail(): return
	
	# Store attack tracking
	if is_opponent:
		main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Continuous Fireball - ", heads_count, " heads, ", total_damage, " damage")

# Dark Hypno - Bench Manipulation: Opponent flips coins = bench count, 20×tails to active, no W/R
func execute_bench_manipulation(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var bench_count = target_bench.size()
	
	if bench_count == 0:
		await main.show_message("OPPONENT HAS NO BENCH POKÉMON! 0 DAMAGE!")
		if main._should_bail(): return
		return
	
	var tails_count = 0
	for i in range(bench_count):
		var coin = await main.flip_coin(bench_count > 1)
		if not coin:
			tails_count += 1
	
	var total_damage = 20 * tails_count
	await main.show_message(str(tails_count) + " TAILS! " + str(total_damage) + " DAMAGE! (NO W/R)")
	if main._should_bail(): return
	
	if total_damage > 0:
		# Apply directly to active (no W/R)
		defender.current_hp = max(0, defender.current_hp - total_damage)
		main.display_hp_circles_above_align(defender, !is_opponent)
		main.show_floating_label("-" + str(total_damage) + "HP", Vector2(530 if is_opponent else 1030, 300), true)
		if total_damage > 0:
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
			await main.powers_and_bodies.check_strikes_back(defender, attacker, !is_opponent)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Bench Manipulation - ", tails_count, " tails, ", total_damage, " damage")

# Dark Machamp - Fling: Shuffle opponent's active + attached cards into deck
func execute_fling(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE FLING! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var target_active: card_object
	var target_deck: Array
	if is_opponent:
		target_active = main.player_active_pokemon
		target_deck = main.player_deck
	else:
		target_active = main.opponent_active_pokemon
		target_deck = main.opponent_deck
	
	if target_active == null:
		return
	
	var name = target_active.metadata.get("name", "")
	
	# Shuffle all attached energies back into deck
	for e in target_active.attached_energies:
		e.current_location = "deck"
		target_deck.append(e)
	target_active.attached_energies.clear()
	
	# Shuffle all attached pre-evolutions back into deck
	for pre in target_active.attached_pre_evolutions:
		pre.current_location = "deck"
		target_deck.append(pre)
	target_active.attached_pre_evolutions.clear()
	
	# Shuffle attached trainer cards back into deck
	for ac in target_active.attached_cards:
		ac.current_location = "deck"
		target_deck.append(ac)
	target_active.attached_cards.clear()
	
	# Shuffle the active pokemon itself back
	target_active.current_location = "deck"
	main.clear_all_statuses(target_active, !is_opponent)
	target_active.current_hp = int(target_active.metadata.get("hp", "0"))
	target_deck.append(target_active)
	
	# Shuffle deck
	target_deck.shuffle()
	
	# Clear active slot
	if is_opponent:
		main.player_active_pokemon = null
	else:
		main.opponent_active_pokemon = null
	
	main.display_pokemon(!is_opponent)
	main.display_active_pokemon_energies(!is_opponent)
	main.update_deck_icon(!is_opponent)
	
	await main.show_message(name.to_upper() + " WAS SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	
	# Force opponent to choose new active from bench
	await main.handle_post_knockout(!is_opponent)
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fling shuffled ", name, " into deck")

# Dark Magneton - Magnetic Lines: Move 1 basic energy from defender to opponent's bench
func execute_magnetic_lines(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# First do 30 damage normally
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Check if defender has basic energy and opponent has bench
	var basic_energies: Array = []
	for e in defender.attached_energies:
		if main.is_basic_energy_card(e):
			basic_energies.append(e)
	
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if basic_energies.size() == 0 or target_bench.size() == 0:
		if basic_energies.size() == 0:
			await main.show_message("NO BASIC ENERGY ON DEFENDER!")
			if main._should_bail(): return
		elif target_bench.size() == 0:
			await main.show_message("OPPONENT HAS NO BENCH TO MOVE ENERGY TO!")
			if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
		return
	
	var chosen_energy: card_object = null
	var chosen_bench: card_object = null
	
	if not is_opponent:
		# Player chooses energy from defender
		# For simplicity, auto-pick the first basic energy (player could choose)
		chosen_energy = basic_energies[0]
		
		# Player chooses bench target
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_bench)
		main.header_label.text = "CHOOSE BENCH POKÉMON TO RECEIVE ENERGY"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen_bench = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	else:
		# CPU picks first basic energy and first bench pokemon
		chosen_energy = basic_energies[0]
		chosen_bench = target_bench[0]
	
	if chosen_energy != null and chosen_bench != null:
		defender.attached_energies.erase(chosen_energy)
		chosen_bench.attached_energies.append(chosen_energy)
		main.display_active_pokemon_energies(!is_opponent)
		await main.show_message("MOVED ENERGY TO " + chosen_bench.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Magnetic Lines")

# Dark Vileplume - Petal Whirlwind: Flip 3 coins, 30×heads, 2+ heads = self confused
func execute_petal_whirlwind(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var heads_count = 0
	for i in range(3):
		var coin = await main.flip_coin(true)
		if coin:
			heads_count += 1
	
	var total_damage = 30 * heads_count
	await main.show_message("GOT " + str(heads_count) + " HEADS! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.player_attacked_this_turn = true
	
	# 2+ heads = self confused
	if heads_count >= 2:
		attacker.special_condition = "Confused"
		main.update_status_icons(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Petal Whirlwind - ", heads_count, " heads")

# Dark Weezing - Mass Explosion: 20× total Koffing/Weezing/Dark Weezing in play, then 20 to each
func execute_mass_explosion(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_names = ["Koffing", "Weezing", "Dark Weezing"]
	
	# Count all matching pokemon in play (both sides)
	var all_matching: Array = []
	var all_player: Array = []
	if main.player_active_pokemon != null:
		all_player.append(main.player_active_pokemon)
	all_player.append_array(main.player_bench)
	var all_opponent: Array = []
	if main.opponent_active_pokemon != null:
		all_opponent.append(main.opponent_active_pokemon)
	all_opponent.append_array(main.opponent_bench)
	
	for p in all_player:
		if p.metadata.get("name", "") in target_names:
			all_matching.append({"pokemon": p, "is_opponent": false})
	for p in all_opponent:
		if p.metadata.get("name", "") in target_names:
			all_matching.append({"pokemon": p, "is_opponent": true})
	
	var count = all_matching.size()
	var total_damage = 20 * count
	
	await main.show_message(str(count) + " KOFFING/WEEZING IN PLAY! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	# Apply main damage to defender with W/R
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.player_attacked_this_turn = true
	
	# Then 20 damage to each Koffing/Weezing/Dark Weezing (no W/R, even own)
	for match_info in all_matching:
		var target = match_info["pokemon"]
		if target.current_hp <= 0:
			continue
		target.current_hp = max(0, target.current_hp - 20)
		main.display_hp_circles_above_align(target, match_info["is_opponent"])
		await main.show_message(target.metadata.get("name", "").to_upper() + " TOOK 20 EXPLOSION DAMAGE!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mass Explosion - ", count, " matching pokemon")

# Dark Electrode - Energy Bomb: 30 damage, then move all energy to bench
func execute_energy_bomb(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage first
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Move all energy to bench
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if bench.size() == 0:
		# No bench - discard all energy
		for e in attacker.attached_energies.duplicate():
			attacker.attached_energies.erase(e)
			e.current_location = "discard"
			discard_pile.append(e)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("NO BENCH! ALL ENERGY DISCARDED!")
		if main._should_bail(): return
	else:
		# Distribute energy to bench pokemon
		var energies = attacker.attached_energies.duplicate()
		attacker.attached_energies.clear()
		
		if not is_opponent:
			# Player distributes - for simplicity, spread evenly
			var idx = 0
			for e in energies:
				bench[idx % bench.size()].attached_energies.append(e)
				idx += 1
		else:
			# CPU distributes to pokemon that need energy most
			for e in energies:
				var best_target: card_object = null
				var best_unmet = 0
				for bp in bench:
					for attack in bp.metadata.get("attacks", []):
						var unmet = main.cpu_ai.get_unmet_energy_count(attack, bp)
						if unmet > best_unmet:
							best_unmet = unmet
							best_target = bp
				if best_target == null:
					best_target = bench[0]
				best_target.attached_energies.append(e)
		
		main.display_active_pokemon_energies(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("ALL ENERGY MOVED TO BENCH!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Energy Bomb")

# Dark Golduck - Third Eye: Discard 1 energy to draw up to 3 cards
func execute_third_eye(attacker: card_object, is_opponent: bool) -> void:
	if attacker.attached_energies.size() == 0:
		await main.show_message("NO ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	# Discard 1 energy
	var energy = attacker.attached_energies[attacker.attached_energies.size() - 1]
	attacker.attached_energies.erase(energy)
	energy.current_location = "discard"
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	discard_pile.append(energy)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await main.show_message("DISCARDED 1 ENERGY!")
	if main._should_bail(): return
	
	# Draw up to 3 cards
	var draw_count = min(3, (main.opponent_deck if is_opponent else main.player_deck).size())
	for i in range(draw_count):
		await main.draw_card_from_deck(is_opponent)
		if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	
	await main.show_message("DREW " + str(draw_count) + " CARD(S)!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Third Eye - drew ", draw_count, " cards")

# Dark Machoke - Drag Off: Switch bench->active before damage, then 20 damage
func execute_drag_off(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE DRAG OFF! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		# Player chooses opponent bench to drag
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_bench)
		main.header_label.text = "CHOOSE BENCH POKÉMON TO DRAG OUT"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	else:
		# CPU picks weakest bench pokemon
		var targets = target_bench.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]
	
	if selected == null:
		return
	
	# Switch the selected bench with active
	var old_active: card_object
	if is_opponent:
		old_active = main.player_active_pokemon
		main.player_bench.erase(selected)
		main.player_bench.append(old_active)
		old_active.current_location = "bench"
		selected.current_location = "active"
		main.player_active_pokemon = selected
		main.clear_all_statuses(old_active, false)
	else:
		old_active = main.opponent_active_pokemon
		main.opponent_bench.erase(selected)
		main.opponent_bench.append(old_active)
		old_active.current_location = "bench"
		selected.current_location = "active"
		main.opponent_active_pokemon = selected
		main.clear_all_statuses(old_active, true)
	
	main.display_pokemon(!is_opponent)
	main.display_active_pokemon_energies(!is_opponent)
	
	await main.show_message("DRAGGED " + selected.metadata.get("name", "").to_upper() + " TO ACTIVE!")
	if main._should_bail(): return
	
	# Now do 20 damage to the new defender
	var new_defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(20, attacking_types, new_defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(new_defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(new_defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(new_defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, new_defender, final_damage, result["modifiers"], is_opponent, 20)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Drag Off - dragged ", selected.metadata.get("name", ""))

# Dark Persian - Fascinate: Flip heads = switch opponent bench with active (no damage)
func execute_fascinate(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE FASCINATE! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin()
	if not coin:
		await main.show_message("TAILS! FASCINATE FAILED!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_bench)
		main.header_label.text = "CHOOSE BENCH POKÉMON TO SWITCH IN"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	else:
		# CPU picks weakest bench pokemon
		var targets = target_bench.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]
	
	if selected == null:
		return
	
	# Switch
	var old_active: card_object
	if is_opponent:
		old_active = main.player_active_pokemon
		main.player_bench.erase(selected)
		main.player_bench.append(old_active)
		old_active.current_location = "bench"
		selected.current_location = "active"
		main.player_active_pokemon = selected
		main.clear_all_statuses(old_active, false)
	else:
		old_active = main.opponent_active_pokemon
		main.opponent_bench.erase(selected)
		main.opponent_bench.append(old_active)
		old_active.current_location = "bench"
		selected.current_location = "active"
		main.opponent_active_pokemon = selected
		main.clear_all_statuses(old_active, true)
	
	main.display_pokemon(!is_opponent)
	main.display_active_pokemon_energies(!is_opponent)
	await main.show_message(selected.metadata.get("name", "").to_upper() + " WAS SWITCHED IN!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fascinate - switched in ", selected.metadata.get("name", ""))

# Dark Rapidash - Flame Pillar: 30 damage, optionally discard 1 Fire to do 10 bench damage
func execute_flame_pillar(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Check for optional Fire Energy discard for bench damage
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if fire_energies.size() > 0 and target_bench.size() > 0:
		var do_discard = false
		if is_opponent:
			# CPU only discards extra fire energy if guaranteed to be KO'd next turn
			# (wasting energy when you'll survive is bad value)
			var ko_threats = main.cpu_ai.evaluate_ko_threats()
			do_discard = ko_threats.get("cpu_active_guaranteed_ko", false)
		else:
			# Player chooses: show yes/no via attack selection buttons
			main.special_attack_selection_active = true
			main.buttons_only_blocker.visible = true
			main.attack_buttons_container.visible = true
			main.main_buttons_container.visible = false
			for child in main.attack_buttons_container.get_children():
				if child.name == "cancel_attack_mode_button":
					child.visible = false
					continue
				child.queue_free()
			
			var btn_yes = Button.new()
			btn_yes.text = "YES - DISCARD FIRE ENERGY"
			btn_yes.custom_minimum_size = Vector2(350, 50)
			btn_yes.theme = main.theme_green
			main.attack_buttons_container.add_child(btn_yes)
			btn_yes.pressed.connect(func(): main.special_attack_selected.emit(0))
			
			var btn_no = Button.new()
			btn_no.text = "NO - SKIP"
			btn_no.custom_minimum_size = Vector2(350, 50)
			btn_no.theme = main.theme_green
			main.attack_buttons_container.add_child(btn_no)
			btn_no.pressed.connect(func(): main.special_attack_selected.emit(1))
			
			await main.show_message("DISCARD FIRE ENERGY FOR 10 BENCH DAMAGE?")
			if main._should_bail(): return
			
			var selected_index = await main.special_attack_selected
			do_discard = (selected_index == 0)
			
			for child in main.attack_buttons_container.get_children():
				if child.name == "cancel_attack_mode_button":
					child.visible = true
					continue
				child.queue_free()
			main.attack_buttons_container.visible = false
			main.main_buttons_container.visible = true
			main.special_attack_selection_active = false
			main.buttons_only_blocker.visible = false
		
		if do_discard:
			# Discard 1 fire energy
			var energy = fire_energies[0]
			attacker.attached_energies.erase(energy)
			energy.current_location = "discard"
			var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			discard_pile.append(energy)
			main.display_active_pokemon_energies(is_opponent)
			
			# Choose bench target
			var bench_target: card_object = null
			if not is_opponent:
				main.trainer_pokemon_selection_active = true
				main.show_enlarged_array_selection_mode(target_bench)
				main.header_label.text = "CHOOSE BENCH POKÉMON FOR 10 DAMAGE"
				main.action_button.text = "SELECT"
				main.action_button.disabled = true
				await main.trainer_target_selected
				if main._should_bail(): return
				bench_target = main.selected_card_for_action
				main.trainer_pokemon_selection_active = false
				main.hide_selection_mode_display_main()
			else:
				var targets = target_bench.duplicate()
				targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
				bench_target = targets[0]
			
			if bench_target != null:
				bench_target.current_hp = max(0, bench_target.current_hp - 10)
				main.display_hp_circles_above_align(bench_target, !is_opponent)
				await main.show_message("10 DAMAGE TO " + bench_target.metadata.get("name", "").to_upper() + "!")
				if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Flame Pillar")

# Dark Wartortle - Mirror Shell: Counter attack for equal damage next turn
func execute_mirror_shell(attacker: card_object, is_opponent: bool) -> void:
	attacker.mirror_shell_active = true
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " SET UP MIRROR SHELL!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mirror Shell active on ", attacker.metadata.get("name", ""))

# Magikarp - Rapid Evolution: Search deck for Gyarados or Dark Gyarados and evolve
func execute_rapid_evolution(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var valid_evolutions: Array = []
	
	for card in deck:
		var name = card.metadata.get("name", "")
		if name == "Gyarados" or name == "Dark Gyarados":
			valid_evolutions.append(card)
	
	if valid_evolutions.size() == 0:
		await main.show_message("NO GYARADOS OR DARK GYARADOS IN DECK!")
		if main._should_bail(): return
		return
	
	var chosen: card_object = null
	
	if not is_opponent:
		if valid_evolutions.size() == 1:
			chosen = valid_evolutions[0]
		else:
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(valid_evolutions)
			main.header_label.text = "CHOOSE EVOLUTION"
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			await main.trainer_target_selected
			if main._should_bail(): return
			chosen = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
	else:
		# CPU picks first available
		chosen = valid_evolutions[0]
	
	if chosen == null:
		return
	
	# Evolve Magikarp
	deck.erase(chosen)
	attacker.attached_pre_evolutions.append(card_object.new(attacker.uid, attacker.metadata.duplicate(true)))
	attacker.uid = chosen.uid
	attacker.metadata = chosen.metadata.duplicate(true)
	var old_max = attacker.current_hp
	attacker.current_hp = int(chosen.metadata.get("hp", "0")) - (int(attacker.attached_pre_evolutions[attacker.attached_pre_evolutions.size() - 1].metadata.get("hp", "0")) - old_max)
	attacker.current_hp = min(int(chosen.metadata.get("hp", "0")), max(1, attacker.current_hp))
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.play_evolution_effect(attacker)
	await main.show_message("MAGIKARP EVOLVED INTO " + chosen.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Rapid Evolution into ", chosen.metadata.get("name", ""))

# Abra - Vanish: Shuffle Abra and all attached cards into deck
func execute_vanish(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	# Discard all attached cards
	for e in attacker.attached_energies:
		e.current_location = "discard"
		discard.append(e)
	attacker.attached_energies.clear()
	
	for pre in attacker.attached_pre_evolutions:
		pre.current_location = "discard"
		discard.append(pre)
	attacker.attached_pre_evolutions.clear()
	
	for ac in attacker.attached_cards:
		ac.current_location = "discard"
		discard.append(ac)
	attacker.attached_cards.clear()
	
	# Shuffle Abra into deck
	main.clear_all_statuses(attacker, is_opponent)
	attacker.current_hp = int(attacker.metadata.get("hp", "0"))
	attacker.current_location = "deck"
	deck.append(attacker)
	
	var is_active = false
	if is_opponent:
		if main.opponent_active_pokemon == attacker:
			main.opponent_active_pokemon = null
			is_active = true
		else:
			main.opponent_bench.erase(attacker)
	else:
		if main.player_active_pokemon == attacker:
			main.player_active_pokemon = null
			is_active = true
		else:
			main.player_bench.erase(attacker)
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await main.show_message("ABRA VANISHED INTO THE DECK!")
	if main._should_bail(): return
	
	if is_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return
	
	print("ATTACK EXECUTED: Vanish")

# Mankey - Mischief: Shuffle opponent's deck
func execute_mischief(attacker: card_object, is_opponent: bool) -> void:
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	target_deck.shuffle()
	await main.show_message("OPPONENT'S DECK WAS SHUFFLED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mischief - shuffled opponent deck")

# Slowpoke - Afternoon Nap: Search deck for Psychic Energy, attach to self
func execute_afternoon_nap(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var psychic_energies: Array = []
	
	for card in deck:
		if card.metadata.get("supertype", "") == "Energy" and "Psychic" in card.metadata.get("name", ""):
			psychic_energies.append(card)
	
	if psychic_energies.size() == 0:
		await main.show_message("NO PSYCHIC ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	
	var chosen = psychic_energies[0]
	deck.erase(chosen)
	attacker.attached_energies.append(chosen)
	deck.shuffle()
	
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ATTACHED PSYCHIC ENERGY TO " + attacker.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Afternoon Nap")

# Dark Raichu - Surprise Thunder: 30 damage + double flip for bench spread
func execute_surprise_thunder(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# First flip
	var coin1 = await main.flip_coin()
	if coin1:
		# Second flip
		var coin2 = await main.flip_coin()
		var bench_damage = 20 if coin2 else 10
		
		var target_bench = main.player_bench if is_opponent else main.opponent_bench
		await main.show_message(("HEADS AGAIN! " if coin2 else "TAILS! ") + str(bench_damage) + " TO EACH BENCH!")
		if main._should_bail(): return
		
		for bp in target_bench:
			bp.current_hp = max(0, bp.current_hp - bench_damage)
			main.display_hp_circles_above_align(bp, !is_opponent)
	else:
		await main.show_message("TAILS! NO BENCH DAMAGE!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Surprise Thunder")

# Dark Charmeleon - Fireball: 70 damage, gated on Fire Energy, flip heads=discard 1, tails=nothing
func execute_dark_charmeleon_fireball(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY! CAN'T USE FIREBALL!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin()
	if coin:
		# Heads: discard 1 fire energy, do 70 damage
		var energy = fire_energies[0]
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		discard_pile.append(energy)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		
		await main.show_message("HEADS! DISCARDED FIRE ENERGY!")
		if main._should_bail(): return
		
		var attacking_types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(70, attacking_types, defender, attacker)
		var final_damage = result["damage"]
		
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 70)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
			main.player_attacked_this_turn = true
	else:
		await main.show_message("TAILS! FIREBALL FIZZLED!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Dark Charmeleon Fireball")

# Check and apply Mirror Shell counter damage
func check_mirror_shell(damaged_pokemon: card_object, attacker: card_object, damage_dealt: int, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if not damaged_pokemon.mirror_shell_active:
		return
	
	damaged_pokemon.mirror_shell_active = false
	
	# Counter damage is blocked by attacker's shields
	if attacker.is_invincible:
		await main.show_message("MIRROR SHELL BLOCKED! TARGET IS INVINCIBLE!")
		if main._should_bail(): return
		print("EFFECT: Mirror Shell blocked by invincibility")
		return
	if attacker.has_no_damage:
		await main.show_message("MIRROR SHELL BLOCKED! NO DAMAGE SHIELD!")
		if main._should_bail(): return
		print("EFFECT: Mirror Shell blocked by no-damage shield")
		return
	
	# Counter equal damage to attacker (no W/R, just raw)
	attacker.current_hp = max(0, attacker.current_hp - damage_dealt)
	main.display_hp_circles_above_align(attacker, !is_damaged_opponent)
	await main.show_message("MIRROR SHELL! " + str(damage_dealt) + " DAMAGE REFLECTED!")
	if main._should_bail(): return
	print("EFFECT: Mirror Shell reflected ", damage_dealt, " damage")


# MAGNETISM (Magnemite): 10 + 10 per Magnemite/Magneton/Dark Magneton on bench
func execute_magnetism(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var target_names = ["Magnemite", "Magneton", "Dark Magneton"]
	var count = 0
	for bp in bench:
		if bp.metadata.get("name", "") in target_names:
			count += 1
	
	var total_damage = 10 + (10 * count)
	await main.show_message(str(count) + " MAGNEMITE/MAGNETON ON BENCH! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if transparency_blocked:
		return
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
	if main._should_bail(): return
	print("MAGNETISM: ", total_damage, " damage (", count, " bench magnets)")
