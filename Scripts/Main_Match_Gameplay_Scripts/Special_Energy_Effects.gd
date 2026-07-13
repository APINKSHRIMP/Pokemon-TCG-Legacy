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
		"Multi Energy":
			# EX6 Multi Energy: provides every type of Energy but only 1 at a time (like Rainbow).
			# The "provides Colorless when the Pokemon already has another Special Energy attached"
			# anti-combo rule needs the holder's context (unavailable here) and is simplified out.
			return ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Darkness", "Metal"]
		"Aqua Energy":
			# Provides Water + Darkness (2 Energy at a time); attach only to Team Aqua Pokemon
			return ["Water", "Darkness"]
		"Magma Energy":
			# Provides Fighting and/or Darkness (2 Energy at a time); attach only to Team Magma Pokemon
			return ["Fighting", "Darkness"]
		"Dark Metal Energy":
			# EX7: provides Darkness and Metal, but only 1 Energy at a time (like Rainbow/Multi).
			return ["Darkness", "Metal"]
		"R Energy":
			# EX7: provides 2 Darkness Energy. Attach only to a "Dark"/"Rocket's" Pokémon.
			return ["Darkness", "Darkness"]
		"Boost Energy":
			# EX8: provides 3 Colorless. Attach only to Evolved; discard at end of the turn attached.
			return ["Colorless", "Colorless", "Colorless"]
		"Heal Energy":
			# EX8: provides 1 Colorless (on-attach heal handled in apply_on_attach_effects).
			return ["Colorless"]
		"Scramble Energy":
			# EX8: baseline 1 Colorless; the prize-conditional "3 of any type" form is resolved with
			# holder context in Main.get_energy_provided_by_card (this fallback is used when no holder
			# is known, e.g. deck-building previews).
			return ["Colorless"]
		"Cyclone Energy":
			# ecard3/ex10/ex16: provides 1 Colorless (on-attach forced switch handled in apply_on_attach_effects).
			return ["Colorless"]
		"Warp Energy":
			# ecard2/ex10/ex16: provides 1 Colorless (on-attach self-switch handled in apply_on_attach_effects).
			return ["Colorless"]
		"Holon Energy FF", "Holon Energy GL", "Holon Energy WP":
			# EX11: each provides 1 Colorless. The conditional bonuses (no Weakness / no Resistance /
			# status immunity / free retreat / -10 from opp ex) are passive and gated on a matching
			# basic Energy also being attached — see the ex11_holon_* helpers below.
			return ["Colorless"]
		"React Energy":
			# EX12: provides 1 Colorless. Its whole identity is being a countable "React Energy" card
			# (many ex12 cards search/count/move it). The Gorebyss "Reactive Booster" upgrade (React on a
			# Huntail/Gorebyss provides 2 of every type) needs holder context and is resolved in
			# Main.get_energy_provided_by_card.
			return ["Colorless"]
		# --- FUTURE SETS: Add new special energies below ---
		# "Boost Energy":
		#	return ["Colorless", "Colorless", "Colorless"]
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

	# EX9 Cursed Glare (Cacturne ex ex9-91): while it is a side's Active, the OTHER side can't attach any
	# Special Energy (except Darkness and Metal) from hand to its Active Pokemon.
	if "Special" in energy_card.metadata.get("subtypes", []) and card_name not in ["Darkness Energy", "Metal Energy"]:
		var target_is_opp = target_pokemon.is_owner_opp(main)
		var target_active = main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon
		if target_pokemon == target_active:
			var opposing_active = main.player_active_pokemon if target_is_opp else main.opponent_active_pokemon
			if opposing_active != null and opposing_active.has_ability("Cursed Glare") and not main.powers_and_bodies.is_power_blocked_by_status(opposing_active):
				return {"allowed": false, "reason": "CURSED GLARE! CAN'T ATTACH SPECIAL ENERGY TO YOUR ACTIVE POKEMON!"}

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
		"Darkness Energy", "Metal Energy", "Recycle Energy", "Multi Energy", "Dark Metal Energy", "Heal Energy", "React Energy":
			return {"allowed": true, "reason": ""}
		"Boost Energy":
			# EX8: can be attached only to an Evolved Pokemon.
			if main.is_basic_pokemon(target_pokemon):
				return {"allowed": false, "reason": "BOOST ENERGY CAN ONLY BE ATTACHED TO AN EVOLVED POKEMON!"}
			return {"allowed": true, "reason": ""}
		"Scramble Energy":
			# EX8: can be attached only to an Evolved Pokemon (excluding Pokemon-ex).
			if main.is_basic_pokemon(target_pokemon) or main.is_ex_pokemon(target_pokemon):
				return {"allowed": false, "reason": "SCRAMBLE ENERGY CAN ONLY BE ATTACHED TO AN EVOLVED POKEMON (NOT ex)!"}
			return {"allowed": true, "reason": ""}
		"R Energy":
			var rname = target_pokemon.metadata.get("name", "")
			if "Dark" not in rname and "Rocket's" not in rname:
				return {"allowed": false, "reason": "R ENERGY CAN ONLY BE ATTACHED TO A DARK OR ROCKET'S POKEMON!"}
			return {"allowed": true, "reason": ""}
		"Aqua Energy":
			if "Team Aqua" not in target_pokemon.metadata.get("name", ""):
				return {"allowed": false, "reason": "AQUA ENERGY CAN ONLY BE ATTACHED TO A TEAM AQUA POKEMON!"}
			return {"allowed": true, "reason": ""}
		"Magma Energy":
			if "Team Magma" not in target_pokemon.metadata.get("name", ""):
				return {"allowed": false, "reason": "MAGMA ENERGY CAN ONLY BE ATTACHED TO A TEAM MAGMA POKEMON!"}
			return {"allowed": true, "reason": ""}
		"Double Rainbow Energy":
			# Only on Evolved Pokemon, excluding Pokemon-ex
			if main.is_basic_pokemon(target_pokemon) or main.is_ex_pokemon(target_pokemon):
				return {"allowed": false, "reason": "DOUBLE RAINBOW ENERGY CAN ONLY BE ATTACHED TO AN EVOLVED POKEMON (NOT ex)!"}
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
		
		"Heal Energy":
			# EX8: when attached from hand, remove 1 damage counter and all Special Conditions.
			# If attached to a Pokemon-ex, Heal Energy has no effect other than providing Energy.
			if main.is_ex_pokemon(target_pokemon):
				return false
			var applied = false
			var had_status = target_pokemon.special_condition != "" or target_pokemon.is_poisoned or target_pokemon.is_burned
			if had_status:
				main.clear_all_statuses(target_pokemon, is_opponent)
				main.update_status_icons(target_pokemon, is_opponent)
				applied = true
			var heal_max_hp = target_pokemon.get_max_hp()
			var rule_heal = main.match_effects.modify_heal_amount(10, is_opponent)
			if rule_heal > 0 and target_pokemon.current_hp < heal_max_hp:
				target_pokemon.current_hp = min(heal_max_hp, target_pokemon.current_hp + rule_heal)
				main.display_hp_circles_above_align(target_pokemon, is_opponent)
				applied = true
			if applied:
				await main.show_message("HEAL ENERGY! REMOVED 1 DAMAGE COUNTER AND ALL SPECIAL CONDITIONS FROM " + pokemon_name + "!")
				if main._should_bail(): return true
			return applied

		"Warp Energy":
			# When attached from hand, you may switch the Pokemon it's attached to with 1 of your
			# Benched Pokemon. (CPU skips this situational switch.)
			if is_opponent: return false
			var w_bench = main.player_bench
			if w_bench.is_empty(): return false
			var w_yes = await main.trainer_effects.gym1_prompt_yes_no(target_pokemon, "WARP ENERGY", "Switch " + pokemon_name + " with a Benched Pokemon?", "YES", "NO")
			if main._should_bail(): return true
			if not w_yes: return false
			if target_pokemon == main.player_active_pokemon:
				await main.attack_effects.apply_self_switch(target_pokemon, false)
				if main._should_bail(): return true
			else:
				var old_active = main.player_active_pokemon
				var idx = w_bench.find(target_pokemon)
				main.player_active_pokemon = target_pokemon
				target_pokemon.current_location = "active"
				if old_active != null and idx != -1:
					old_active.current_location = "bench"
					w_bench[idx] = old_active
				main.display_pokemon(false)
			await main.show_message("WARP ENERGY! SWITCHED YOUR ACTIVE POKEMON!")
			if main._should_bail(): return true
			return true

		"Cyclone Energy":
			# When attached from hand to your Active Pokemon, you may switch 1 of your opponent's
			# Benched Pokemon with their Active Pokemon (you choose). (CPU skips.)
			if is_opponent: return false
			if target_pokemon != main.player_active_pokemon: return false
			var c_bench = main.opponent_bench
			if c_bench.is_empty(): return false
			var c_yes = await main.trainer_effects.gym1_prompt_yes_no(target_pokemon, "CYCLONE ENERGY", "Switch one of the opponent's Benched Pokemon into their Active spot?", "YES", "NO")
			if main._should_bail(): return true
			if not c_yes: return false
			var chosen = await main.card_ops.choose_card(c_bench, false, "CYCLONE ENERGY", "Choose the opponent's Benched Pokemon to switch in", "SELECT", false)
			if main._should_bail(): return true
			if chosen == null: return false
			var old_opp = main.opponent_active_pokemon
			var c_idx = c_bench.find(chosen)
			main.opponent_active_pokemon = chosen
			chosen.current_location = "active"
			if old_opp != null and c_idx != -1:
				old_opp.current_location = "bench"
				c_bench[c_idx] = old_opp
			main.display_pokemon(true)
			await main.show_message("CYCLONE ENERGY! THE OPPONENT'S " + chosen.metadata.get("name","").to_upper() + " IS NOW ACTIVE!")
			if main._should_bail(): return true
			return true

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
		"R Energy":
			# EX7: "When your turn ends, discard R Energy."
			return true
		"Boost Energy":
			# EX8: "Discard Boost Energy at the end of the turn it was attached."
			return true
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
			"R Energy":
				# EX7: +10 damage to the opponent's Active per R Energy attached (before W/R)
				bonus += 10
			"Double Rainbow Energy":
				# Damage done to the opponent by the holder is reduced by 10 (after W/R)
				bonus -= 10
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
		
		"Multi Energy":
			# EX6 Multi Energy: matches any single type, no drawback. Best when it unlocks an attack.
			score += 25.0
			if is_active:
				score += 10.0
			for attack in target_pokemon.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, target_pokemon) == 1:
					score += 40.0
					break

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
		"Aqua Energy", "Magma Energy":
			# Provides 2 Energy at once (great burst) but is discarded at end of turn, so it is only
			# worth attaching on the Active when it enables an attack this turn.
			if not is_active:
				return -50.0
			score += 20.0
			for attack in target_pokemon.metadata.get("attacks", []):
				var unmet = main.cpu_ai.get_unmet_energy_count(attack, target_pokemon)
				if unmet >= 1 and unmet <= 2:
					score += 60.0
					break
		"Double Rainbow Energy":
			# Provides 2 of any type but reduces the holder's damage by 10
			score += 30.0
			if is_active:
				score += 10.0
		"Dark Metal Energy":
			# EX7: flexible Darkness/Metal (1 at a time), no drawback.
			score += 20.0
			if is_active:
				score += 10.0
		"R Energy":
			# EX7: 2 Darkness + 10 more damage, but discarded at end of turn — only worth it on the
			# Active when it enables an attack this turn.
			if not is_active:
				return -50.0
			score += 25.0
			for attack in target_pokemon.metadata.get("attacks", []):
				var unmet = main.cpu_ai.get_unmet_energy_count(attack, target_pokemon)
				if unmet >= 1 and unmet <= 2:
					score += 60.0
					break
		"Boost Energy":
			# EX8: 3 Colorless burst but discarded at end of turn and locks retreat — only worth it on
			# the Active when it enables an attack this turn.
			if not is_active:
				return -50.0
			score += 20.0
			for attack in target_pokemon.metadata.get("attacks", []):
				var unmet = main.cpu_ai.get_unmet_energy_count(attack, target_pokemon)
				if unmet >= 1 and unmet <= 3:
					score += 60.0
					break
		"Heal Energy":
			# EX8: Colorless + heals 10 and cures status (no effect on ex).
			if not main.is_ex_pokemon(target_pokemon):
				if target_pokemon.special_condition != "" or target_pokemon.is_poisoned or target_pokemon.is_burned:
					score += 40.0
				if target_pokemon.current_hp < target_pokemon.get_max_hp():
					score += 15.0
			score += 5.0
		"Scramble Energy":
			# EX8: flexible 3-Energy while behind on Prizes; otherwise 1 Colorless.
			score += 15.0
			if is_active:
				score += 10.0
			for attack in target_pokemon.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, target_pokemon) <= 3:
					score += 30.0
					break

		"React Energy":
			# EX12: 1 Colorless, but its value spikes on ex12 cards that scale off / gate on React Energy
			# (Machamp Swift Blow, Flygon ex Reactive Blast, Aerodactyl Reactive Protection, etc.).
			score += 10.0
			if is_active:
				score += 5.0
			var rname = target_pokemon.metadata.get("name", "")
			var rtext = ""
			for ab in target_pokemon.metadata.get("abilities", []):
				rtext += ab.get("text", "")
			for atk in target_pokemon.metadata.get("attacks", []):
				rtext += atk.get("text", "")
			if "React Energy" in rtext:
				score += 25.0
			for attack in target_pokemon.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, target_pokemon) == 1:
					score += 20.0
					break

	return score


######################################################################################################################################################
############################################### EX11 (EX DELTA SPECIES) HOLON ENERGY HELPERS #########################################################
######################################################################################################################################################
# Holon Energy FF/GL/WP each provide 1 Colorless and grant a conditional passive bonus if a matching
# basic Energy is ALSO attached. All bonuses are ignored while attached to a Pokemon-ex.

func _has_holon_energy(pokemon: card_object, holon_name: String) -> bool:
	if pokemon == null: return false
	for e in pokemon.attached_energies:
		if e.metadata.get("name","") == holon_name:
			return true
	return false

func _has_basic_energy_type(pokemon: card_object, type_name: String) -> bool:
	if pokemon == null: return false
	for e in pokemon.attached_energies:
		if "Basic" in e.metadata.get("subtypes", []) and type_name in main.get_energy_provided_by_card(e):
			return true
	return false

# Holon Energy FF + basic Fire: the holder has no Weakness. (Consulted in has_no_weakness_body.)
func ex11_holon_ff_no_weakness(pokemon: card_object) -> bool:
	if pokemon == null or main.is_ex_pokemon(pokemon): return false
	return _has_holon_energy(pokemon, "Holon Energy FF") and _has_basic_energy_type(pokemon, "Fire")

# Holon Energy FF + basic Fighting: the holder's attack damage isn't affected by Resistance.
func ex11_holon_ff_ignore_resistance(pokemon: card_object) -> bool:
	if pokemon == null or main.is_ex_pokemon(pokemon): return false
	return _has_holon_energy(pokemon, "Holon Energy FF") and _has_basic_energy_type(pokemon, "Fighting")

# Holon Energy GL + basic Grass ("can't be affected by any Special Conditions") OR Holon Energy WP +
# basic Water ("prevent all effects, excluding damage, done by your opponent"). Both modeled as
# Special-Condition immunity (the engine's central scope for "prevent non-damage effects").
func ex11_holon_status_immune(pokemon: card_object) -> bool:
	if pokemon == null or main.is_ex_pokemon(pokemon): return false
	if _has_holon_energy(pokemon, "Holon Energy GL") and _has_basic_energy_type(pokemon, "Grass"):
		return true
	if _has_holon_energy(pokemon, "Holon Energy WP") and _has_basic_energy_type(pokemon, "Water"):
		return true
	return false

# Holon Energy GL + basic Lightning: damage done by the opponent's Pokemon-ex is reduced by 10.
func ex11_holon_gl_reduce_ex(pokemon: card_object) -> bool:
	if pokemon == null or main.is_ex_pokemon(pokemon): return false
	return _has_holon_energy(pokemon, "Holon Energy GL") and _has_basic_energy_type(pokemon, "Lightning")

# Holon Energy WP + basic Psychic: the holder's Retreat Cost is 0.
func ex11_holon_wp_free_retreat(pokemon: card_object) -> bool:
	if pokemon == null or main.is_ex_pokemon(pokemon): return false
	return _has_holon_energy(pokemon, "Holon Energy WP") and _has_basic_energy_type(pokemon, "Psychic")
