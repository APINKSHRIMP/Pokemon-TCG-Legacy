extends Node

######################################################################################################################################################
########################################################## SPECIAL ENERGY EFFECTS ###################################################################
######################################################################################################################################################
#
# This file handles ALL special energy card logic:
#   - What energy type(s) a special energy provides while in play
#   - On-attach effects (damage, healing, status cure, etc.)
#   - Attachment restrictions (type-locked, condition-locked)
#   - End-of-turn discard requirements (Boost Energy, etc.)
#   - Passive bonuses/drawbacks while attached (Darkness/Metal damage modifiers)
#
# All game state, signals, and node references are accessed through the main back-reference.
#
# ADDING NEW SPECIAL ENERGIES:
#   1. Add the card name to get_energy_types_provided() to define what energy it provides
#   2. Add attachment restriction logic to can_attach_to() if it has type/condition restrictions
#   3. Add on-attach effects to apply_on_attach_effects() (damage, heal, cure, etc.)
#   4. Add to must_discard_end_of_turn() if it self-discards after the turn
#   5. Add to get_damage_modifier() if it modifies outgoing/incoming damage (Darkness/Metal)
#   6. Add CPU scoring to score_special_energy_attachment() for AI decision-making
#

var main: Node

######################################################################################################################################################
############################################### ENERGY TYPE PROVISION (what types does this card provide while in play) ##############################
######################################################################################################################################################

# Returns the energy types this special energy card provides while attached/in play.
# This is called by Main_Match_Core_Gameplay_Script.get_energy_provided_by_card() for special energies.
func get_energy_types_provided(card_name: String) -> Array:
	# MIRACULOUS WIND (neo4-14 Light Dragonite): all Special Energy becomes Colorless while active
	if main.powers_and_bodies.is_miraculous_wind_active():
		return ["Colorless"]
	match card_name:
		"Double Colorless Energy":
			return ["Colorless", "Colorless"]
		"Double Rainbow Energy":
			return ["Any", "Any"]
		"Rainbow Energy":
			# Counts as every type but only provides 1 energy at a time
			# Returning all types lets get_unmet_energy_count match any single typed requirement
			return ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting"]
		"Full Heal Energy":
			return ["Colorless"]
		"Potion Energy":
			return ["Colorless"]
		"Darkness Energy":
			return ["Darkness"]
		"Metal Energy":
			return ["Metal"]
		"Recycle Energy":
			return ["Colorless"]
		# --- FUTURE SETS: Add new special energies below ---
		# "Boost Energy":
		#	return ["Colorless", "Colorless", "Colorless"]
		# "Dark Metal Energy":
		#	return ["Darkness", "Metal"]
		_:
			return []

# Returns true if this card name is a known special energy handled by this system
func is_known_special_energy(card_name: String) -> bool:
	return get_energy_types_provided(card_name).size() > 0

######################################################################################################################################################
############################################### ATTACHMENT RESTRICTIONS (can this energy be attached to this pokemon?) ################################
######################################################################################################################################################

# Returns {"allowed": bool, "reason": String}
# Called BEFORE the energy is attached. If not allowed, the attachment is blocked.
func can_attach_to(energy_card: card_object, target_pokemon: card_object) -> Dictionary:
	var card_name = energy_card.metadata.get("name", "")

	# Pure Body (basep-53/np-30 Suicune): when attaching Water Energy to Suicune,
	# Suicune must have at least 1 energy to discard — block if it has none.
	if not main.powers_and_bodies.is_power_blocked(target_pokemon):
		for ab in target_pokemon.metadata.get("abilities", []):
			if ab.get("name", "") == "Pure Body":
				var energy_provided = get_energy_types_provided(card_name)
				if "Water" in energy_provided:
					if target_pokemon.attached_energies.is_empty():
						return {"allowed": false, "reason": "PURE BODY! " + target_pokemon.metadata.get("name", "").to_upper() + " HAS NO ENERGY TO DISCARD!"}

	match card_name:
		"Rainbow Energy", "Full Heal Energy", "Potion Energy", "Double Colorless Energy", \
		"Darkness Energy", "Metal Energy", "Recycle Energy":
			return {"allowed": true, "reason": ""}
		# --- FUTURE SETS: Add type-locked energies below ---
		# "Boost Energy":
		#	var subtypes = target_pokemon.metadata.get("subtypes", [])
		#	if "Stage 2" not in subtypes:
		#		return {"allowed": false, "reason": "Boost Energy can only be attached to Stage 2 Pokémon!"}
		#	return {"allowed": true, "reason": ""}
		_:
			# Unknown special energy — allow by default
			return {"allowed": true, "reason": ""}

######################################################################################################################################################
############################################### ON-ATTACH EFFECTS (triggered when played from hand onto a pokemon) ###################################
######################################################################################################################################################

# Applies any on-attach effects. Called AFTER the energy is successfully attached.
# Returns true if an effect was applied (for UI messaging purposes).
func apply_on_attach_effects(energy_card: card_object, target_pokemon: card_object, is_opponent: bool) -> bool:
	var card_name = energy_card.metadata.get("name", "")
	var pokemon_name = target_pokemon.metadata.get("name", "").to_upper()
	
	match card_name:
		"Rainbow Energy":
			# 10 damage to the pokemon it's attached to (no W/R)
			target_pokemon.current_hp = max(0, target_pokemon.current_hp - 10)
			main.display_hp_circles_above_align(target_pokemon, is_opponent)
			var label_x = 1030 if is_opponent else 530
			main.show_floating_label("-10HP", Vector2(label_x, 300), true)
			await main.show_message("RAINBOW ENERGY DEALT 10 DAMAGE TO " + pokemon_name + "!")
			if main._should_bail(): return true
			await main.check_all_knockouts()
			if main._should_bail(): return true
			return true
		
		"Full Heal Energy":
			# Cure all status conditions when played from hand
			var had_status = target_pokemon.special_condition != "" or target_pokemon.is_poisoned or target_pokemon.is_burned
			main.clear_all_statuses(target_pokemon, is_opponent)
			if had_status:
				main.update_status_icons(target_pokemon, is_opponent)
				await main.show_message(pokemon_name + " WAS CURED OF ALL STATUS CONDITIONS!")
				if main._should_bail(): return true
			return had_status
		
		"Potion Energy":
			# Heal 1 damage counter (10 HP) when played from hand
			# MATCH EFFECTS: no_healing / healing_multiplier gate
			var max_hp = int(target_pokemon.metadata.get("hp", "0"))
			var rule_heal = main.match_effects.modify_heal_amount(10, is_opponent)
			if rule_heal > 0 and target_pokemon.current_hp < max_hp:
				var actual_heal = min(rule_heal, max_hp - target_pokemon.current_hp)
				target_pokemon.current_hp = min(max_hp, target_pokemon.current_hp + rule_heal)
				main.display_hp_circles_above_align(target_pokemon, is_opponent)
				SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
				var label_x = 1030 if is_opponent else 530
				main.show_floating_label("+" + str(actual_heal) + "HP", Vector2(label_x, 300), true)
				await main.show_message("POTION ENERGY HEALED " + str(actual_heal) + " HP FROM " + pokemon_name + "!")
				if main._should_bail(): return true
				return true
			return false
		
		# --- FUTURE SETS: Add on-attach effects below ---
		# "Boost Energy":
		#	# No on-attach effect, but must be discarded at end of turn
		#	return false
		# "Darkness Energy":
		#	# No on-attach effect — damage modifier is passive
		#	return false
		# "Metal Energy":
		#	# No on-attach effect — damage modifier is passive
		#	return false
	
	return false

######################################################################################################################################################
############################################### END-OF-TURN DISCARD (energies that must be discarded at turn end) ####################################
######################################################################################################################################################

# Returns true if this energy must be discarded at the end of the turn it was attached.
func must_discard_end_of_turn(card_name: String) -> bool:
	match card_name:
		# "Boost Energy":
		#	return true
		_:
			return false

# Called during end-of-turn processing. Scans all pokemon on one side and discards
# any special energies flagged for end-of-turn removal.
func process_end_of_turn_discards(is_opponent: bool) -> void:
	var all_pokemon: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)
	
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	for pokemon in all_pokemon:
		var to_remove: Array = []
		for energy in pokemon.attached_energies:
			var energy_name = energy.metadata.get("name", "")
			# Only discard if it was attached THIS turn and is flagged for end-of-turn discard
			if energy.attached_this_turn and must_discard_end_of_turn(energy_name):
				to_remove.append(energy)
		
		for energy in to_remove:
			pokemon.attached_energies.erase(energy)
			energy.current_location = "discard"
			discard_pile.append(energy)
			await main.show_message(energy.metadata.get("name", "").to_upper() + " WAS DISCARDED!")
			if main._should_bail(): return
		
		if to_remove.size() > 0:
			main.display_active_pokemon_energies(is_opponent)
			main.update_discard_pile_display(is_opponent)

######################################################################################################################################################
############################################### PASSIVE DAMAGE MODIFIERS (Darkness/Metal bonus/reduction while attached) #############################
######################################################################################################################################################

# Returns a damage modifier dictionary for outgoing attacks from this pokemon.
# Called during damage calculation if the attacker has special energies attached.
# Returns: {"bonus": int, "reduction": int}
# bonus = extra damage added to attacks, reduction = damage reduced from incoming attacks
func get_outgoing_damage_modifier(pokemon: card_object) -> Dictionary:
	# MIRACULOUS WIND: suppress Darkness/Metal passive effects
	if main.powers_and_bodies.is_miraculous_wind_active():
		return {"bonus": 0}
	var bonus = 0
	#var pokemon_types = pokemon.metadata.get("types", [])

	for energy in pokemon.attached_energies:
		var energy_name = energy.metadata.get("name", "")
		match energy_name:
			"Darkness Energy":
				# +10 outgoing damage to the opponent's Active per Darkness Energy attached
				bonus += 10
			_:
				pass

	return {"bonus": bonus}

# Returns incoming damage reduction from special energies (e.g. Metal Energy)
func get_incoming_damage_reduction(pokemon: card_object) -> int:
	# MIRACULOUS WIND: suppress Metal Energy damage reduction
	if main.powers_and_bodies.is_miraculous_wind_active():
		return 0
	var reduction = 0
	#var pokemon_types = pokemon.metadata.get("types", [])

	for energy in pokemon.attached_energies:
		var energy_name = energy.metadata.get("name", "")
		match energy_name:
			"Metal Energy":
				# -10 incoming damage (after W/R) per Metal Energy attached
				reduction += 10
			_:
				pass

	return reduction

######################################################################################################################################################
############################################### CPU AI SCORING (how valuable is attaching this special energy?) ######################################
######################################################################################################################################################

# Returns a score adjustment for the CPU when considering attaching a special energy.
# Higher = more desirable to attach. Called from CPU_AI energy attachment scoring.
func score_special_energy_attachment(energy_card: card_object, target_pokemon: card_object, is_active: bool) -> float:
	var card_name = energy_card.metadata.get("name", "")
	var score = 0.0
	
	# First check if attachment is even allowed
	var attach_check = can_attach_to(energy_card, target_pokemon)
	if not attach_check["allowed"]:
		return -9999.0
	
	match card_name:
		"Rainbow Energy":
			# Very flexible (matches any type) but costs 10 HP
			# More valuable on high-HP pokemon and when specific typed energy is needed
			var hp_pct = float(target_pokemon.current_hp) / max(int(target_pokemon.metadata.get("hp", "1")), 1)
			if hp_pct <= 0.2:
				score -= 50.0  # Too risky on low HP pokemon
			elif target_pokemon.current_hp <= 10:
				return -9999.0  # Would KO self
			else:
				score += 30.0  # Flexible type matching is valuable
			# Extra value if this unlocks an attack (the typed requirement match is huge)
			for attack in target_pokemon.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, target_pokemon) == 1:
					score += 40.0
					break
		
		"Full Heal Energy":
			# Only provides Colorless, but cures status
			if target_pokemon.special_condition != "" or target_pokemon.is_poisoned or target_pokemon.is_burned:
				score += 60.0  # Curing status is very valuable
				if target_pokemon.special_condition == "Paralyzed":
					score += 20.0  # Extra priority for Paralyzed
			# Otherwise it's just a colorless energy
			score += 5.0
		
		"Potion Energy":
			# Colorless + heals 10
			var max_hp = int(target_pokemon.metadata.get("hp", "0"))
			if target_pokemon.current_hp < max_hp:
				score += 15.0  # Heal is a nice bonus
			score += 5.0  # Colorless baseline
		
		"Double Colorless Energy":
			# Provides 2 colorless — always good
			score += 25.0
			if is_active:
				score += 10.0
		
		"Darkness Energy":
			score += 20.0
			if is_active:
				score += 15.0
		"Metal Energy":
			score += 20.0
			if is_active:
				score += 10.0
		"Recycle Energy":
			score += 10.0
			if is_active:
				score += 5.0
		# --- FUTURE SETS ---
		# "Boost Energy": if is_active: score += 40.0 else: score -= 50.0

	return score
