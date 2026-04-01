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
	attacker.current_hp = max(0, attacker.current_hp - self_damage)
	await main.show_message("THE ATTACK FAILED! " + attacker.metadata["name"].to_upper() + " HURT ITSELF FOR " + str(self_damage) + " DAMAGE!")
	if main._should_bail(): return false
	var attacker_label_pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
	main.show_floating_label("-" + str(self_damage) + "HP", attacker_label_pos, true)
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
