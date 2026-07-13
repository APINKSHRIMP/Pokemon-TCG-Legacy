extends Node

######################################################################################################################################################
################################################################### CPU AI #########################################################################
######################################################################################################################################################
#
# This file contains all CPU decision-making, evaluation, and turn orchestration.
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

# Fix 2: CPU evaluation cache
var _cached_cpu_eval: Dictionary = {}
var _cpu_eval_dirty: bool = true

func get_cpu_evaluation() -> Dictionary:
	if _cpu_eval_dirty or _cached_cpu_eval.is_empty():
		_cached_cpu_eval = build_cpu_evaluation()
		_cpu_eval_dirty = false
	return _cached_cpu_eval.duplicate(true)

func invalidate_cpu_evaluation() -> void:
	_cpu_eval_dirty = true

func opponent_start_turn_checks() -> void:
	if main._should_bail():
		return
	# Reset trainer lock from Headache
	main.trainer_effects.reset_trainer_lock(true)
	main.turn_number += 1
	print("OPPONENT'S TURN START. TURN NUMBER IS ", main.turn_number)
	await get_tree().create_timer(0.5).timeout
	if main._should_bail(): return
	main.opponents_turn_active = true
	main.reset_field_pokemon_turn_flags(true)

	await main.show_message("Your opponent draws a card")
	if main._should_bail(): return
	var drawn_card = await main.draw_card_from_deck(true)

	if drawn_card == null:
		return

	# MATCH EFFECT: draw_count — draw extra cards at turn start (deck-out handled inside)
	for extra_draw in range(main.match_effects.turn_start_draw_count(true) - 1):
		var extra_card = await main.draw_card_from_deck(true)
		if extra_card == null:
			return

	main.refresh_hand_display(true)
	main.update_deck_icon(true)

	# Update Ditto Transform state
	main.powers_and_bodies.update_ditto_transform(true)
	main.powers_and_bodies.update_ditto_transform(false)

	# NEO1: process turn-start tools (Gold Berry, Berry, Miracle Berry) and Char counters for CPU's side
	await main.powers_and_bodies.process_turn_start_tools_and_counters(true)
	if main._should_bail(): return

	# EX11 Holon Ruins (ex11-96 Stadium): once per turn, a player with a δ Pokemon in play may draw a
	# card, then discard a card.
	await main.trainer_effects.holon_ruins_offer_draw(true)
	if main._should_bail(): return

	# EX12 Power Tree / Strange Cave (Stadiums): once-per-turn optional actions.
	await main.trainer_effects.ex12_power_tree_offer(true)
	if main._should_bail(): return
	await main.trainer_effects.ex12_strange_cave_offer(true)
	if main._should_bail(): return

	await cpu_turn_orchestrator()
	if main._should_bail(): return

# Orchestrates all CPU decision phases in the correct order
func cpu_turn_orchestrator() -> void:
	if main._should_bail():
		return
	# Phase 0: Activate beneficial Pokemon Powers (Rain Dance, Energy Trans, Damage Swap)
	await main.powers_and_bodies.cpu_phase_activate_powers()
	if main._should_bail(): return
	if main.opponent_turn_force_end:
		main.opponent_turn_force_end = false
		await get_tree().create_timer(0.5).timeout
		await main.show_message("Your opponent ends their turn")
		if main._should_bail(): return
		await main.inbetween_turn_checks(false)
		return

	if main._should_bail():
		return
	# Phase 1a: Play Bill first (always highest priority)
	await cpu_phase_play_trainer_cards_priority()
	if main._should_bail(): return
	if main.opponent_turn_force_end:
		main.opponent_turn_force_end = false
		await get_tree().create_timer(0.5).timeout
		await main.show_message("Your opponent ends their turn")
		if main._should_bail(): return
		await main.inbetween_turn_checks(false)
		return

	if main._should_bail():
		return
	# Phase 2: Evolution plays
	await cpu_phase_evolution()
	if main._should_bail(): return

	if main._should_bail():
		return
	# Phase 3: Bench pokemon plays (uses existing priority scoring)
	await cpu_phase_bench_play()
	if main._should_bail(): return

	if main._should_bail():
		return
	# Phase 4: Build evaluation AFTER all board-altering plays have resolved
	var cpu_eval = get_cpu_evaluation()

	# Phase 4b: Play remaining trainer cards after evolutions/bench plays
	await cpu_phase_play_trainer_cards_remaining()
	if main._should_bail(): return
	if main.opponent_turn_force_end:
		main.opponent_turn_force_end = false
		await get_tree().create_timer(0.5).timeout
		await main.show_message("Your opponent ends their turn")
		if main._should_bail(): return
		await main.inbetween_turn_checks(false)
		return

	if main._should_bail():
		return
	# Phase 5: First retreat evaluation (before energy attachment)
	var retreat_deferred = await cpu_phase_retreat_first_pass(cpu_eval)

	# Phase 6: Energy attachment
	# MATCH EFFECT: extra_energy_per_turn — loop until the per-turn limit is reached
	# (the phase early-returns once opponent_energy_played_this_turn flips or hand is empty)
	for _attach_round in range(main.match_effects.energy_attach_limit(true)):
		await cpu_phase_energy_attachment(cpu_eval)
		if main._should_bail(): return
		if main.opponent_energy_played_this_turn:
			break
		invalidate_cpu_evaluation()
		cpu_eval = get_cpu_evaluation()

	if main._should_bail():
		return
	# Phase 7: Second retreat pass (only if Phase 5 deferred pending energy)
	if retreat_deferred:
		cpu_eval = get_cpu_evaluation()
		await cpu_phase_retreat_second_pass(cpu_eval)
		if main._should_bail(): return

	if main._should_bail():
		return
	# Phase 7b: Final trainer card check (re-evaluate after energy/retreat)
	await cpu_phase_play_trainer_cards_remaining()
	if main._should_bail(): return
	if main.opponent_turn_force_end:
		main.opponent_turn_force_end = false
		await get_tree().create_timer(0.5).timeout
		await main.show_message("Your opponent ends their turn")
		if main._should_bail(): return
		await main.inbetween_turn_checks(false)
		return

	if main._should_bail():
		return
	# Phase 8: Attack decision (must always be last)
	await cpu_phase_attack(cpu_eval)
	if main._should_bail(): return

	if main._should_bail():
		return
	await get_tree().create_timer(0.5).timeout
	if main._should_bail(): return
	await main.show_message("Your opponent ends their turn")
	if main._should_bail(): return
	await main.inbetween_turn_checks(false)
	if main._should_bail(): return

# CPU plays any valid evolutions from hand onto field pokemon using pair scoring
func opponent_setup_pokemon_from_hand() -> void:
	var selected_pokemon = select_opponent_pokemon_for_setup(main.opponent_hand)
	var active_pokemon = selected_pokemon.get("active")
	var bench_pokemon_list = selected_pokemon.get("bench", [])
	
	# Remove active pokemon from hand and set it as active
	main.opponent_hand.erase(active_pokemon)
	main.opponent_active_pokemon = active_pokemon
	main.opponent_active_pokemon.current_location = "active"
	main.opponent_active_pokemon.placed_on_field_this_turn = true
	
	# Remove bench pokemon from hand and add to bench
	for bench_pokemon in bench_pokemon_list:
		main.opponent_hand.erase(bench_pokemon)
		bench_pokemon.current_location = "bench"
		bench_pokemon.placed_on_field_this_turn = true
		main.opponent_bench.append(bench_pokemon)
	
	# Update displays
	main.display_pokemon(true)  # true = opponent
	main.refresh_hand_display(true)

# Handles start-of-turn duties then hands off to the CPU decision orchestrator
func build_cpu_evaluation() -> Dictionary:
	var eval = {}

	# Game state context (1.14, 1.15)
	eval["cpu_prizes_remaining"] = main.opponent_prize_cards.size()
	eval["player_prizes_remaining"] = main.player_prize_cards.size()
	eval["game_phase"] = "late" if (eval["cpu_prizes_remaining"] <= 2 or eval["player_prizes_remaining"] <= 2) else "early"

	# KO threat assessment (1.1, 1.2, 1.3)
	eval.merge(evaluate_ko_threats())

	# Per-pokemon data: energy requirements, evolution potential, attack readiness
	eval["pokemon_data"] = {}
	var all_cpu_pokemon = get_all_cpu_field_pokemon()
	for pokemon in all_cpu_pokemon:
		var key = pokemon.get_instance_id()
		eval["pokemon_data"][key] = evaluate_single_pokemon(pokemon)

	# CPU offensive capability (1.11, 1.13)
	eval["cpu_can_ko_player_active"] = can_cpu_ko_player_active()
	eval["has_viable_bench_attacker"] = check_viable_bench_attacker()

	return eval

# Returns an array of all CPU pokemon currently on the field (active + bench)
func get_all_cpu_field_pokemon() -> Array:
	var pokemon = []
	if main.opponent_active_pokemon != null:
		pokemon.append(main.opponent_active_pokemon)
	pokemon.append_array(main.opponent_bench)
	return pokemon

# Evaluates a single pokemon's energy requirements, attack readiness, and evolution potential
func evaluate_single_pokemon(pokemon: card_object) -> Dictionary:
	var data = {}

	# 1.4 and 1.5: Per-attack unmet energy and overall attack readiness
	var attack_data = []
	var can_attack = false
	for attack in pokemon.metadata.get("attacks", []):
		var unmet = get_unmet_energy_count(attack, pokemon)
		var damage_range = main.attack_effects.estimate_attack_damage_range(attack)
		attack_data.append({
			"name": attack.get("name", ""),
			"cost": attack.get("cost", []),
			"unmet": unmet,
			"damage_min": damage_range["min"],
			"damage_max": damage_range["max"],
			"text": attack.get("text", "")
		})
		if unmet == 0:
			can_attack = true
	data["attack_data"] = attack_data
	data["can_attack"] = can_attack

	# 1.7: Evolution in hand
	data["evolution_in_hand"] = null
	for card in main.opponent_hand:
		if main.can_evolve_from(card, pokemon):
			data["evolution_in_hand"] = card
			break

	# 1.8: Evolution in deck or prize cards
	data["evolution_in_deck_or_prizes"] = false
	if data["evolution_in_hand"] == null:
		for card in main.opponent_deck + main.opponent_prize_cards:
			if main.can_evolve_from(card, pokemon):
				data["evolution_in_deck_or_prizes"] = true
				break

	# 1.10: Can evolve further (check all sources)
	data["can_evolve_further"] = data["evolution_in_hand"] != null or data["evolution_in_deck_or_prizes"]

	# 1.9: If evolution exists, does the evolved form need more energy than currently attached
	data["evolved_form_needs_energy"] = false
	var evo_card = data["evolution_in_hand"]
	if evo_card == null:
		# Check deck/prizes for the actual card data to inspect attacks
		for card in main.opponent_deck + main.opponent_prize_cards:
			if main.can_evolve_from(card, pokemon):
				evo_card = card
				break
	if evo_card != null:
		for attack in evo_card.metadata.get("attacks", []):
			if get_unmet_energy_count(attack, pokemon) > 0:
				data["evolved_form_needs_energy"] = true
				break

	return data

# Parses an attack's damage string and returns min/max estimate (placeholder until full effect parsing)
func evaluate_ko_threats() -> Dictionary:
	var result = {
		"cpu_active_guaranteed_ko": false,
		"cpu_active_potential_ko": false,
		"player_bench_ko_threat": false
	}

	if main.opponent_active_pokemon == null or main.player_active_pokemon == null:
		return result

	var cpu_active_hp = main.opponent_active_pokemon.current_hp
	var player_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])

	# 1.1 and 1.2: Check each attack on the player's active pokemon
	for attack in main.player_active_pokemon.metadata.get("attacks", []):
		var unmet = get_unmet_energy_count(attack, main.player_active_pokemon)
		# Skip if player can't use this attack even with one more energy
		if unmet > 1:
			continue
		var damage_range = main.attack_effects.estimate_attack_damage_range(attack, main.player_active_pokemon, main.opponent_active_pokemon)
		var min_result = main.calculate_final_damage(damage_range["min"], player_types, main.opponent_active_pokemon)
		var max_result = main.calculate_final_damage(damage_range["max"], player_types, main.opponent_active_pokemon)

		if unmet == 0:
			# Attack is usable right now
			if min_result["damage"] >= cpu_active_hp:
				result["cpu_active_guaranteed_ko"] = true
			elif max_result["damage"] >= cpu_active_hp:
				result["cpu_active_potential_ko"] = true
		else:
			# Attack is 1 energy away — treat as potential since player will likely attach
			if min_result["damage"] >= cpu_active_hp:
				result["cpu_active_potential_ko"] = true

	# 1.3: Check if player could retreat into a bench KO threat
	var retreat_cost = main.get_retreat_cost(main.player_active_pokemon)
	var current_energy = main.player_active_pokemon.attached_energies.size()
	# Player can retreat now, or is 1 energy away from retreating
	var player_can_retreat = current_energy >= retreat_cost or current_energy >= (retreat_cost - 1)

	if player_can_retreat:
		for bench_pokemon in main.player_bench:
			var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])
			for attack in bench_pokemon.metadata.get("attacks", []):
				var unmet = get_unmet_energy_count(attack, bench_pokemon)
				# Bench pokemon needs to be ready now — player can only attach 1 energy total
				# If they spend it on retreat cost they can't also power up the bench attacker
				if unmet > 0:
					continue
				var damage_range = main.attack_effects.estimate_attack_damage_range(attack, bench_pokemon, main.opponent_active_pokemon)
				var min_result = main.calculate_final_damage(damage_range["min"], bench_types, main.opponent_active_pokemon)
				if min_result["damage"] >= cpu_active_hp:
					result["player_bench_ko_threat"] = true
					break
			if result["player_bench_ko_threat"]:
				break

	return result

# Returns how many energy cards a pokemon still needs to use a specific attack
func get_unmet_energy_count(attack: Dictionary, pokemon: card_object) -> int:
	var required_cost = attack.get("cost", []).duplicate()
	# EX5 Primal Pull (Claydol ex5-2): while a Primal Pull Claydol is Active, each player's Evolved
	# Pokemon pays Colorless more Energy to use its attacks.
	if not main.is_basic_pokemon(pokemon) and main.powers_and_bodies.is_ex5_primal_pull_active():
		required_cost.append("Colorless")
	if required_cost.size() == 0:
		return 0

	var pool = []
	# gym1-47 Erika's Oddish Photosynthesis: all energy attached provides Grass instead of usual type
	var photosynthesis_on = main.powers_and_bodies.is_photosynthesis_active(pokemon)
	# NEO1 Wild Growth: Grass Energy on Grass Pokemon counts as 2 Grass
	var wild_growth_on = main.powers_and_bodies.is_wild_growth_active() and "Grass" in pokemon.metadata.get("types", [])
	# MATCH EFFECT: rainbow_energy — every attached energy provides any type
	# (multi-providers like DCE provide that many "Any" units)
	var rainbow_rule_on = main.match_effects.rainbow_energy_active(main.match_effects.is_card_on_opponent_side(pokemon))
	for attached in pokemon.attached_energies:
		if rainbow_rule_on:
			var provided_rainbow = main.get_energy_provided_by_card(attached)
			for _i in range(max(1, provided_rainbow.size())):
				pool.append("Any")
		# Charizard Energy Burn: all energy attached to Charizard counts as Fire
		elif main.powers_and_bodies.is_energy_burn_active(pokemon):
			pool.append("Fire")
			# If the energy provides 2 (like DCE), add a second Fire
			var provided = main.get_energy_provided_by_card(attached)
			if provided.size() > 1:
				for _i in range(provided.size() - 1):
					pool.append("Fire")
		# EX6 Energy Flame (Charizard ex): all Energy attached to Charizard ex counts as Fire
		elif main.powers_and_bodies.is_ex6_energy_flame_active(pokemon):
			pool.append("Fire")
			var provided_flame = main.get_energy_provided_by_card(attached)
			if provided_flame.size() > 1:
				for _i in range(provided_flame.size() - 1):
					pool.append("Fire")
		# EX12 Stages of Evolution (Magmar ex12-21): while Magmar is an Evolved Pokemon, all Energy
		# attached to it are Fire Energy instead of their usual types.
		elif main.powers_and_bodies.is_ex12_stages_fire_active(pokemon):
			var provided_sf = main.get_energy_provided_by_card(attached)
			for _i in range(max(1, provided_sf.size())):
				pool.append("Fire")
		# ECARD1 Burning Energy (Charizard): basic Energy on this side counts as Fire this turn
		elif main.powers_and_bodies.is_ecard1_burning_energy_active(pokemon) and "Special" not in attached.metadata.get("subtypes", []):
			pool.append("Fire")
		# ECARD1 Dark Aura (Tyranitar): all Energy attached to Tyranitar counts as Darkness
		elif main.powers_and_bodies.is_ecard1_dark_aura_active(pokemon):
			var provided_dark = main.get_energy_provided_by_card(attached)
			for _i in range(max(1, provided_dark.size())):
				pool.append("Darkness")
		# ECARD3 Rare Metal (Steelix): basic Energy attached to Steelix provides Metal instead
		elif main.powers_and_bodies.is_ecard3_rare_metal_active(pokemon) and "Special" not in attached.metadata.get("subtypes", []):
			pool.append("Metal")
		# ECARD3 Prismatic Body (Ditto): basic Energy attached to Ditto provides any 1 type
		elif main.powers_and_bodies.is_ecard3_prismatic_body_active(pokemon) and "Special" not in attached.metadata.get("subtypes", []):
			pool.append("Any")
		# ECARD2 Ion Coating (Lanturn): Lightning Energy on this Pokemon counts as Water this turn
		elif pokemon.has_effect("ecard2_ion_coating") and "Lightning" in main.get_energy_provided_by_card(attached):
			pool.append("Water")
		elif photosynthesis_on:
			var provided = main.get_energy_provided_by_card(attached)
			for _i in range(max(1, provided.size())):
				pool.append("Grass")
		elif wild_growth_on:
			var provided = main.get_energy_provided_by_card(attached)
			if "Grass" in provided:
				pool.append("Grass")
				pool.append("Grass")  # Wild Growth: 1 Grass Energy = 2 Grass
			else:
				pool.append_array(provided)
		# Ditto Transform: all energy counts as any type
		elif pokemon.is_ditto_transformed:
			var provided = main.get_energy_provided_by_card(attached)
			for _i in range(provided.size()):
				pool.append("Any")
		else:
			pool.append_array(main.get_energy_provided_by_card(attached))

	var unmet = 0

	# Pass 1: typed requirements first
	for requirement in required_cost:
		if requirement == "Colorless":
			continue
		var exact_index = pool.find(requirement)
		if exact_index != -1:
			pool.remove_at(exact_index)
		else:
			var any_index = pool.find("Any")
			if any_index != -1:
				pool.remove_at(any_index)
			else:
				unmet += 1

	# Pass 2: colorless requirements consume whatever remains
	for requirement in required_cost:
		if requirement != "Colorless":
			continue
		if pool.size() > 0:
			pool.remove_at(0)
		else:
			unmet += 1

	return unmet

# Checks if the CPU's active can KO the player's active with currently usable attacks (1.11)
func can_cpu_ko_player_active() -> bool:
	if main.opponent_active_pokemon == null or main.player_active_pokemon == null:
		return false

	var cpu_types = main.opponent_active_pokemon.metadata.get("types", ["Colorless"])
	var player_hp = main.player_active_pokemon.current_hp

	for attack in main.opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, main.opponent_active_pokemon) > 0:
			continue
		var damage_range = main.attack_effects.estimate_attack_damage_range(attack)
		var result = main.calculate_final_damage(damage_range["min"], cpu_types, main.player_active_pokemon)
		if result["damage"] >= player_hp:
			return true

	return false

# Checks if any bench pokemon is ready or near-ready to attack and can survive a hit (1.13)
func check_viable_bench_attacker() -> bool:
	if main.player_active_pokemon == null or main.opponent_active_pokemon == null:
		return false

	var player_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])

	# Find the player's strongest currently usable attack damage
	var player_max_damage = 0
	for attack in main.player_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, main.player_active_pokemon) > 0:
			continue
		var damage_range = main.attack_effects.estimate_attack_damage_range(attack)
		var result = main.calculate_final_damage(damage_range["max"], player_types, main.opponent_active_pokemon)
		player_max_damage = max(player_max_damage, result["damage"])

	for bench_pokemon in main.opponent_bench:
		var is_ready = false
		for attack in bench_pokemon.metadata.get("attacks", []):
			var unmet = get_unmet_energy_count(attack, bench_pokemon)
			if unmet > 1:
				continue
			# Ready now, or 1 energy away with a matching energy in hand
			if unmet == 0:
				is_ready = true
				break
			for card in main.opponent_hand:
				if card.metadata.get("supertype", "").to_lower() != "energy":
					continue
				var energy_types = main.get_energy_provided_by_card(card)
				var cost = attack.get("cost", [])
				for req in cost:
					if req in energy_types or req == "Colorless":
						is_ready = true
						break
				if is_ready:
					break
			if is_ready:
				break

		if not is_ready:
			continue

		# Check if this bench pokemon would survive the player's strongest attack
		var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])
		var damage_to_bench = main.calculate_final_damage(player_max_damage, player_types, bench_pokemon)
		if bench_pokemon.current_hp > damage_to_bench["damage"]:
			return true

	return false

# R.2, R.4: Evaluates whether the energy cost of retreating is worth paying
func _any_bench_survives_player_attack() -> bool:
	if main.player_active_pokemon == null:
		return true
	var player_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])
	for bench_pokemon in main.opponent_bench:
		var bench_hp = bench_pokemon.current_hp
		var bench_would_die = false
		for p_attack in main.player_active_pokemon.metadata.get("attacks", []):
			if get_unmet_energy_count(p_attack, main.player_active_pokemon) > 0:
				continue
			var p_range = main.attack_effects.estimate_attack_damage_range(p_attack, main.player_active_pokemon, bench_pokemon)
			var p_result = main.calculate_final_damage(p_range["min"], player_types, bench_pokemon)
			if p_result["damage"] >= bench_hp:
				bench_would_die = true
				break
		if not bench_would_die:
			return true
	return false

# Scores all (pokemon, energy_card) pairs and attaches the best one (Phase 0, 2, 3)
func evaluate_opponents_start_setup_pokemon_choices(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var total_score = 0.0
	var score_breakdown = []
	
	# Apply all 5 criteria
	var criterion_1 = criterion_1_single_energy_attack(basic_pokemon)
	total_score += criterion_1.get("score_change", 0)
	score_breakdown.append(criterion_1.get("reason", ""))
	
	var criterion_2 = criterion_2_evolution_available(basic_pokemon, hand)
	total_score += criterion_2.get("score_change", 0)
	score_breakdown.append(criterion_2.get("reason", ""))
	
	var criterion_3 = criterion_3_energy_type_match(basic_pokemon, hand)
	total_score += criterion_3.get("score_change", 0)
	score_breakdown.append(criterion_3.get("reason", ""))
	
	var criterion_4 = criterion_4_pokemon_hp(basic_pokemon)
	total_score += criterion_4.get("score_change", 0)
	score_breakdown.append(criterion_4.get("reason", ""))
	
	var criterion_5 = criterion_5_attack_damage(basic_pokemon)
	total_score += criterion_5.get("score_change", 0)
	score_breakdown.append(criterion_5.get("reason", ""))
	
	return {
		"pokemon_name": basic_pokemon.metadata.get("name", "Unknown"),
		"total_score": total_score,
		"breakdown": score_breakdown
	}

# Evaluates all basic pokemon, returns highest scorer as active and next 3 as bench
func select_opponent_pokemon_for_setup(hand: Array) -> Dictionary:
	var all_basic_pokemon = main.get_all_basic_pokemon(hand)
	
	if all_basic_pokemon.size() == 0:
		print("Error: No basic pokemon found in hand")
		return {"active": null, "bench": []}
	
	# Score all basic pokemon
	var scored_pokemon = []
	for pokemon in all_basic_pokemon:
		var evaluation = evaluate_opponents_start_setup_pokemon_choices(pokemon, hand)
		scored_pokemon.append({
			"pokemon": pokemon,
			"score": evaluation.get("total_score", 0),
			"breakdown": evaluation.get("breakdown", [])
		})
	
	# Sort by score (highest first)
	scored_pokemon.sort_custom(func(a, b): return a["score"] > b["score"])
	
	# First is active, next up to 3 are bench
	var active_pokemon = scored_pokemon[0]["pokemon"]
	var bench_pokemon = []
	for i in range(1, min(4, scored_pokemon.size())):
		bench_pokemon.append(scored_pokemon[i]["pokemon"])
	
	# Print results
	print("Opponent AI selected active: " + active_pokemon.metadata.get("name", "Unknown") + " (Score: " + str(int(scored_pokemon[0]["score"])) + ")")
	for reason in scored_pokemon[0]["breakdown"]:
		print("  - " + reason)
		
	print("__________________________________________________________________")
	
	print("Opponent AI selected " + str(bench_pokemon.size()) + " bench pokemon")
	for i in range(bench_pokemon.size()):
		print("  " + str(i + 1) + ". " + bench_pokemon[i].metadata.get("name", "Unknown") + " (Score: " + str(int(scored_pokemon[i + 1]["score"])) + ")")
		for reason in scored_pokemon[i+1]["breakdown"]:
			print("  - " + reason)
			
		print("__________________________________________________________________")
		
	return {
		"active": active_pokemon,
		"bench": bench_pokemon
	}

# PRIORITY CRITERION #1: Single energy attack check
# If pokemon can attack for only 1 energy: big boost (+100)
# If all attacks need 2+ energy: penalty (-50)
func criterion_1_single_energy_attack(basic_pokemon: card_object) -> Dictionary:
	var min_cost_attack = get_minimum_cost_attack(basic_pokemon)
	
	if min_cost_attack.is_empty():
		return {"score_change": 0, "reason": "No attacks found"}
	
	var min_cost = min_cost_attack.get("cost", 999)
	
	if min_cost == 1:
		return {
			"score_change": 100.0,
			"reason": "Can attack for only 1 energy. (+100 points)"
		}
	else:
		return {
			"score_change": -50.0,
			"reason": "Minimum attack cost is " + str(min_cost) + " energy. (-50 points)"
		}

# PRIORITY CRITERION #2: Check for evolution paths (Stage 1 and Stage 2)
# For Each Stage 1 evolution in hand that can evolve from the basic (+100)
# If there is a stage 1 that then also has a Stage 2 evolution then additional (+100)
func criterion_2_evolution_available(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var score_change = 0.0
	var reason = "No evolutions in hand (+0)"
	var stage_1_list = []
	var has_stage_2_chain = false
	
	# Find all Stage 1 evolutions for this basic pokemon
	for card in hand:
		if card.metadata.has("subtypes") and card.metadata["subtypes"].has("Stage 1"):
			if main.can_evolve_from(card, basic_pokemon):
				stage_1_list.append(card)
				score_change += 100.0
	
	# Check if ANY of the Stage 1s has a Stage 2 evolution (only count once)
	if stage_1_list.size() > 0:
		for stage_1 in stage_1_list:
			if main.has_evolution(stage_1, hand, "Stage 2"):
				has_stage_2_chain = true
				break
		
		if has_stage_2_chain:
			score_change += 100.0
			reason = "Has " + str(stage_1_list.size()) + " Stage 1(s) with Stage 2 chain. (+"+str(score_change) +" points)"
		else:
			reason = "Has " + str(stage_1_list.size()) + " Stage 1 evolution(s) (+"+str(score_change) +" points)"
	
	return {
		"score_change": score_change,
		"reason": reason
	}
	
# PRIORITY CRITERION #3: Check if basic energy types in hand match pokemon type
# Pokemon type matches available basic energy: +30 per matching energy card
# Colorless pokemon: +15 per basic energy card in hand (flexible but lower priority)
# Pokemon type does NOT match available basic energy: -150
func criterion_3_energy_type_match(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var pokemon_type = main.get_pokemon_type(basic_pokemon)
	
	# Count basic energy cards in hand
	var basic_energies_in_hand = []
	for card in hand:
		if main.is_basic_energy_card(card):
			basic_energies_in_hand.append(card)
	
	# If no basic energies at all, no match possible
	if basic_energies_in_hand.is_empty():
		return {
			"score_change": 0,
			"reason": "No basic energy cards in hand"
		}
	
	# Handle Colorless pokemon - gets +20 per basic energy available
	if pokemon_type == "Colorless":
		var score_bonus = 15.0 * basic_energies_in_hand.size()
		return {
			"score_change": score_bonus,
			"reason": "Colorless type - " + str(basic_energies_in_hand.size()) + " basic energies available (+"+str(score_bonus) +" points)"
		}
	
	# For typed pokemon, count matching energies
	var matching_energy_count = 0
	for energy_card in basic_energies_in_hand:
		var energy_type = main.get_energy_type_from_card(energy_card)
		if energy_type == pokemon_type:
			matching_energy_count += 1
	
	# If matching energies found
	if matching_energy_count > 0:
		var score_bonus = 30.0 * matching_energy_count
		return {
			"score_change": score_bonus,
			"reason": "Has " + str(matching_energy_count) + " " + pokemon_type + " energy card(s) (+"+str(score_bonus) +" points)"
		}
	
	# No matching energy found
	return {
		"score_change": -150.0,
		"reason": "No matching " + pokemon_type + " energy in hand (-150 points)"
	}	
	
# PRIORITY CRITERION #4: Higher HP is more durable and valuable
# Score = HP * 2
# e.g 50HP = +60
# e.g 100HP = +150
func criterion_4_pokemon_hp(basic_pokemon: card_object) -> Dictionary:
	var hp = main.get_pokemon_hp(basic_pokemon)
	var score_bonus = hp * 2
	
	return {
		"score_change": score_bonus,
		"reason": "HP: " + str(hp) + " (+" + str(int(score_bonus)) + " points)"
	}
	
# PRIORITY CRITERION #5: Damage output potential (either 1 bonus or 2 bonuses if more than 1 attack)
# 1-energy attack damage: damage * 3 (immediate threat). e.g 10 = +30, 20 = +60, 30 = +90
# Efficiency bonus (only if 2+ attacks): (highest_damage / energy_cost) * 3. e.g 4*Energy for 80 damage = +60
func criterion_5_attack_damage(basic_pokemon: card_object) -> Dictionary:
	if not basic_pokemon.metadata.has("attacks") or basic_pokemon.metadata["attacks"].size() == 0:
		return {
			"score_change": 0,
			"reason": "No attacks available"
		}
	
	var attack_count = basic_pokemon.metadata["attacks"].size()
	var score_bonus = 0.0
	var reason_parts = []
	
	# Check for 1-energy attack damage
	var min_cost_attack = get_minimum_cost_attack(basic_pokemon)
	if not min_cost_attack.is_empty() and min_cost_attack.get("cost") == 1:
		var one_energy_damage = min_cost_attack.get("damage", 0)
		var one_energy_bonus = one_energy_damage * 3
		score_bonus += one_energy_bonus
		reason_parts.append(str(one_energy_damage) + " damage at 1 energy (+" + str(one_energy_bonus) + " points)")
		
		# Check if the lowest cost attack has an effect (additional text)
		var attack_text = min_cost_attack.get("text", "")
		var attack_penalty = get_attack_text_penalty(attack_text, basic_pokemon.metadata.get("name", ""))
		
		if attack_penalty < 0:
			score_bonus += attack_penalty
			reason_parts.append("1-energy attack has penalty (" + str(attack_penalty) + " points)")
		elif attack_text != "":
			score_bonus += 20.0
			reason_parts.append("1-energy attack has beneficial effect (+20 points)")
	

	# Check if the lowest cost attack has an effect (additional text)	
	# Only add efficiency bonus if pokemon has 2+ attacks
	if attack_count >= 2:
		var max_attack = get_maximum_damage_attack(basic_pokemon)
		var max_damage = max_attack.get("damage", 0)
		var max_cost = max_attack.get("cost", 1)
		var attack_text = max_attack.get("text", "")
		
		# Check if highest damage attack has an effect
		var attack_penalty = get_attack_text_penalty(attack_text, basic_pokemon.metadata.get("name", ""))
		
		if attack_penalty < 0:
			score_bonus += attack_penalty
			reason_parts.append("Highest damage attack has penalty (" + str(attack_penalty) + " points)")
		elif attack_text != "":
			score_bonus += 20.0
			reason_parts.append("Highest damage attack has beneficial effect (+20 points)")
		
		# Only calculate efficiency if there's actual damage
		if max_damage > 0:
			var efficiency = float(max_damage) / float(max_cost)
			var efficiency_bonus = efficiency * 3.0
			score_bonus += efficiency_bonus
			reason_parts.append("highest damage efficiency " + str(max_damage) + "/" + str(max_cost) + " energy (+" + str(efficiency_bonus) + " points)")
	
	var reason = "Damage: " + ", ".join(reason_parts)
	
	return {
		"score_change": score_bonus,
		"reason": reason
	}	

# Helper function to check attack text for negative self-inflicted effects
# Only penalizes exact patterns where energy is discarded from the attacking pokemon
# Returns the penalty score (negative value) if found, 0 if no penalty
func evaluate_evolution_pair(evo_card: card_object, target: card_object) -> Dictionary:
	var score = 0.0
	var reasons = []

	# HP improvement: new max HP minus target's CURRENT HP (accounts for damage taken)
	var current_hp = target.current_hp
	var new_max_hp = int(evo_card.metadata.get("hp", "0"))
	var hp_gain = new_max_hp - current_hp
	score += hp_gain * 1.5
	reasons.append("HP gain: +" + str(hp_gain) + " (+" + str(hp_gain * 1.5) + " pts)")

	# Attack improvement: compare best damage output
	var old_best = get_maximum_damage_attack(target)
	var new_best = get_maximum_damage_attack(evo_card)
	var old_damage = old_best.get("damage", 0)
	var new_damage = new_best.get("damage", 0)
	var damage_gain = new_damage - old_damage
	score += damage_gain * 2.0
	reasons.append("Damage gain: +" + str(damage_gain) + " (+" + str(damage_gain * 2.0) + " pts)")

	# Energy compatibility: does target's attached energy satisfy any of the evolved form's attack costs
	var has_usable_attack_after = false
	for attack in evo_card.metadata.get("attacks", []):
		if main.check_attack_requirements(attack, target):
			has_usable_attack_after = true
			break
	if has_usable_attack_after:
		score += 150.0
		reasons.append("Can attack immediately after evolving (+150 pts)")

	# Active pokemon bonus: evolving the active is more urgent
	if target.current_location == "active":
		score += 75.0
		reasons.append("Target is active pokemon (+75 pts)")

	# Existing energy investment: more attached energy means more value preserved
	var energy_count = target.attached_energies.size()
	if energy_count > 0:
		score += energy_count * 25.0
		reasons.append("Target has " + str(energy_count) + " energy attached (+" + str(energy_count * 25.0) + " pts)")

	# Future evolution chain: check hand, deck, and prize cards
	var has_next_stage_in_hand = false
	var has_next_stage_in_deck_or_prizes = false
	for card in main.opponent_hand:
		if card != evo_card and main.can_evolve_from(card, evo_card):
			has_next_stage_in_hand = true
			break
	if not has_next_stage_in_hand:
		for card in main.opponent_deck + main.opponent_prize_cards:
			if main.can_evolve_from(card, evo_card):
				has_next_stage_in_deck_or_prizes = true
				break
	if has_next_stage_in_hand:
		score += 120.0
		reasons.append("Next evolution stage in hand (+120 pts)")
	elif has_next_stage_in_deck_or_prizes:
		score += 40.0
		reasons.append("Next evolution stage in deck or prizes (+40 pts)")

	return {
		"score": score,
		"evo_card": evo_card,
		"target": target,
		"reasons": reasons
	}
			
# Computes all Phase 1 helper evaluations and returns them as a dictionary
func get_attack_text_penalty(attack_text: String, pokemon_name: String) -> int:
	if attack_text == "":
		return 0
	
	var text = attack_text
	
	# Check for "discard all" attached to THIS pokemon (-70)
	if ("Discard all Energy cards attached to " + pokemon_name in text) or \
	   ("Discard all basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard all" in text and "Energy cards attached to " + pokemon_name in text):
		return -70
	
	# Check for "discard 3" attached to THIS pokemon (-50)
	if ("Discard 3 Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 3 basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 3" in text and "Energy cards attached to " + pokemon_name in text):
		return -50
	
	# Check for "discard 2" attached to THIS pokemon (-30)
	if ("Discard 2 Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 2 basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 2" in text and "Energy cards attached to " + pokemon_name in text):
		return -30
	
	# Check for "discard 1" or "discard a" attached to THIS pokemon (-10)
	if ("Discard 1" in text and "Energy card attached to " + pokemon_name in text) or \
	   ("Discard a" in text and "Energy card attached to " + pokemon_name in text) or \
	   ("Discard a basic Energy card attached to " + pokemon_name in text):
		return -10
	
	# Check for damage reduction effects (-20)
	if "damage minus" in text.to_lower():
		return -20
	
	# Check for self-damage effects (X damage to itself = -X*0.5)
	if pokemon_name in text and "damage to itself" in text.to_lower():
		var pattern = "does "
		var lower_text = text.to_lower()
		var start_index = lower_text.find(pattern)
		
		if start_index != -1:
			start_index += pattern.length()
			var number_str = ""
			for i in range(start_index, lower_text.length()):
				var numericalchar = lower_text[i]
				if numericalchar.is_valid_int():
					number_str += numericalchar
				elif number_str != "":
					break
			
			if number_str != "":
				var damage = int(number_str)
				var penalty = int(damage * 0.5)
				return -penalty
	
	return 0

# Criterion 2 is used simply just to check which cards have an evolution available at all. However,
# This scores each pairing (evolution_card, target_pokemon) for CPU evolution decisions, not just to check if there is one at all.
func evaluate_retreat_reasons(cpu_eval: Dictionary) -> bool:
	var active_key = main.opponent_active_pokemon.get_instance_id()
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})
	var can_attack = active_data.get("can_attack", false)

	# Reason 1: Mutual guaranteed KO situation
	# Only ignore the guaranteed KO threat if WE can also guarantee a KO back
	if cpu_eval.get("cpu_active_guaranteed_ko", false) and can_attack:
		# Check if our attack is guaranteed to KO the player's active
		var player_hp = main.player_active_pokemon.current_hp
		var guaranteed_ko_player = false
		
		for attack in active_data.get("attack_data", []):
			if attack["unmet"] == 0:  # Can use this attack
				if attack["damage_min"] >= player_hp:  # Guaranteed to KO
					guaranteed_ko_player = true
					break
					
		if guaranteed_ko_player:
			print("CPU NOT retreating: mutual KO - will attack and trade")
			return false  # Don't retreat, attack instead
		else:
			# Before retreating, check if any bench pokemon would actually survive
			# If all bench options would ALSO be guaranteed KO'd, retreating is pointless
			var any_bench_survives = false
			var player_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])
			for bench_pokemon in main.opponent_bench:
				var bench_hp = bench_pokemon.current_hp
				var bench_would_die = false
				for p_attack in main.player_active_pokemon.metadata.get("attacks", []):
					if get_unmet_energy_count(p_attack, main.player_active_pokemon) > 0:
						continue
					var p_range = main.attack_effects.estimate_attack_damage_range(p_attack, main.player_active_pokemon, bench_pokemon)
					var p_result = main.calculate_final_damage(p_range["min"], player_types, bench_pokemon)
					if p_result["damage"] >= bench_hp:
						bench_would_die = true
						break
				if not bench_would_die:
					any_bench_survives = true
					break
			
			if not any_bench_survives:
				print("CPU NOT retreating: all bench pokemon also face guaranteed KO")
				return false
			
			print("CPU considering retreat: guaranteed KO threat and cannot KO back")
			return true  # Do retreat, we'd lose the trade

	# Reason 2: Active is at risk of KO (potential or bench threat)
	if cpu_eval.get("cpu_active_potential_ko", false) or cpu_eval.get("player_bench_ko_threat", false):
		# Before retreating, check if any bench pokemon would survive
		if not _any_bench_survives_player_attack():
			print("CPU NOT retreating: all bench pokemon also face KO from potential threat")
			return false
		print("CPU considering retreat: potential KO threat")
		return true

	# Reason 3: Active cannot attack and has no path to attacking within 1-2 turns
	if not can_attack:
		var nearest_attack = 999
		for attack in active_data.get("attack_data", []):
			if attack["unmet"] < nearest_attack:
				nearest_attack = attack["unmet"]

		# Count matching energy cards in hand
		var matching_energy_in_hand = 0
		for card in main.opponent_hand:
			if card.metadata.get("supertype", "").to_lower() != "energy":
				continue
			var energy_types = main.get_energy_provided_by_card(card)
			for attack in active_data.get("attack_data", []):
				for req in attack.get("cost", []):
					if req == "Colorless" or req in energy_types:
						matching_energy_in_hand += 1
						break

		if nearest_attack > matching_energy_in_hand + 1:
			print("CPU considering retreat: active has no viable attack path")
			return true

	return false

# Helper: checks if any bench pokemon survives the player's best usable attack
func is_retreat_cost_worthwhile(cpu_eval: Dictionary) -> bool:
	var active = main.opponent_active_pokemon
	var retreat_cost = main.get_retreat_cost(active)
	var active_key = active.get_instance_id()
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})

	# Free retreat is always worthwhile
	if retreat_cost == 0:
		return true

	# Check what state the active ends up in after losing retreat cost energy
	var energy_after_retreat = active.attached_energies.size() - retreat_cost
	var can_attack_after = false
	for attack in active.metadata.get("attacks", []):
		# Simulate the energy pool after discarding retreat cost
		var simulated_pool = []
		for i in range(energy_after_retreat):
			simulated_pool.append_array(main.get_energy_provided_by_card(active.attached_energies[i]))
		var required = attack.get("cost", [])
		if simulated_pool.size() >= required.size():
			can_attack_after = true
			break

	# R.2 rule of thumb: if retreat strips more than half the energy needed for primary attack
	var max_attack = get_maximum_damage_attack(active)
	var primary_attack_cost = max_attack.get("cost", 1)
	var energy_lost_ratio = float(retreat_cost) / float(max(primary_attack_cost, 1))

	# R.4: High-investment pokemon preservation overrides the ratio check
	var guaranteed_ko = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var has_evo = active_data.get("can_evolve_further", false)
	var high_investment = active.attached_energies.size() >= 3 or has_evo
	var high_hp = active.current_hp > int(active.metadata.get("hp", "0")) * 0.5

	if guaranteed_ko and high_investment and high_hp:
		print("CPU retreat worthwhile: preserving high-investment pokemon")
		return true

	# Losing more than half the energy for primary attack is generally bad
	if energy_lost_ratio > 0.5 and not can_attack_after:
		print("CPU retreat not worthwhile: would lose " + str(retreat_cost) + " energy and cannot attack from bench")
		return false

	# If active can still contribute from the bench after retreating, it's worthwhile
	if can_attack_after:
		print("CPU retreat worthwhile: active retains enough energy to attack from bench")
		return true

	# Default: retreat is worthwhile if there's a real threat
	if guaranteed_ko:
		return true

	return false

# Evaluates whether active should retreat before energy attachment (R.1-R.4)
func cpu_phase_retreat_first_pass(cpu_eval: Dictionary) -> bool:
	if main.opponent_active_pokemon == null or main.opponent_bench.size() == 0:
		return false
	# MATCH EFFECT: no_retreat — CPU never considers retreating when blocked
	if main.match_effects.retreat_blocked(true):
		return false
	if main.opponent_retreated_this_turn:
		return false
	if main.opponent_active_pokemon.special_condition in ["Paralyzed", "Asleep"]:
		print("CPU cannot retreat: active is ", main.opponent_active_pokemon.special_condition)
		return false

	# R.1: Should the active pokemon retreat?
	var should_consider = evaluate_retreat_reasons(cpu_eval)
	if not should_consider:
		return false

	var retreat_cost = main.get_retreat_cost(main.opponent_active_pokemon)
	var current_energy = main.opponent_active_pokemon.attached_energies.size()

	# R.3: Exactly 1 energy short — defer to after energy attachment
	if current_energy == retreat_cost - 1 and not main.opponent_energy_played_this_turn:
		print("CPU retreat deferred: 1 energy short, will re-evaluate after attachment")
		return true

	# R.2: Can the active actually pay retreat cost right now?
	if current_energy < retreat_cost:
		print("CPU cannot retreat: not enough energy (" + str(current_energy) + "/" + str(retreat_cost) + ")")
		return false

	# R.2 continued: Is paying the retreat cost worth the energy loss?
	if not is_retreat_cost_worthwhile(cpu_eval):
		print("CPU retreat not worthwhile: energy loss too high")
		return false

	# R.5: Pick the best replacement and execute
	await execute_cpu_retreat(cpu_eval)
	if main._should_bail(): return false
	return false

# Re-evaluates retreat after energy attachment if first pass deferred (R.3)
func cpu_phase_retreat_second_pass(cpu_eval: Dictionary) -> void:
	if main.opponent_active_pokemon == null or main.opponent_bench.size() == 0:
		return
	# MATCH EFFECT: no_retreat — CPU never considers retreating when blocked
	if main.match_effects.retreat_blocked(true):
		return
	if main.opponent_retreated_this_turn:
		return
	if main.opponent_active_pokemon.special_condition in ["Paralyzed", "Asleep"]:
		print("CPU retreat second pass: active is ", main.opponent_active_pokemon.special_condition)
		return

	var retreat_cost = main.get_retreat_cost(main.opponent_active_pokemon)
	var current_energy = main.opponent_active_pokemon.attached_energies.size()

	# Verify retreat is now mechanically possible after energy attachment
	if current_energy < retreat_cost:
		print("CPU retreat second pass: still cannot pay retreat cost")
		return

	# Re-check if retreat reasons still apply with updated board state
	if not evaluate_retreat_reasons(cpu_eval):
		print("CPU retreat second pass: reasons no longer apply")
		return

	# Re-check if the cost is worthwhile
	if not is_retreat_cost_worthwhile(cpu_eval):
		print("CPU retreat second pass: cost not worthwhile")
		return

	await execute_cpu_retreat(cpu_eval)
	if main._should_bail(): return
	
# Scores each bench pokemon as a potential active replacement, returns the best choice
func execute_cpu_retreat(cpu_eval: Dictionary) -> void:
	# MATCH EFFECT: no_retreat — belt-and-braces guard for any direct callers
	if main.match_effects.retreat_blocked(true):
		return
	var best_replacement = pick_best_bench_replacement(main.opponent_bench, main.player_active_pokemon, cpu_eval)

	if best_replacement == null:
		print("CPU retreat failed: no valid bench replacement")
		return

	# ECARD3 Mirage Stadium: any retreat attempt requires a coin flip — tails blocks it entirely
	var mirage_ok = await main.trainer_effects.mirage_stadium_check(true)
	if main._should_bail(): return
	if not mirage_ok:
		return

	var pre_check = await main.check_confused_retreat(main.opponent_active_pokemon, true, "pre_energy")
	if not pre_check:
		main.display_hp_circles_above_align(main.opponent_active_pokemon, true)
		await main.check_all_knockouts()
		if main._should_bail(): return
		main.display_pokemon(true)
		return
		
	# Discard energy for retreat cost
	var retreat_cost = main.get_retreat_cost(main.opponent_active_pokemon)
	var discarded_energies = []
	for i in range(retreat_cost):
		if main.opponent_active_pokemon.attached_energies.size() > 0:
			var energy = main.opponent_active_pokemon.attached_energies.pop_back()
			main.send_card_to_discard(energy, true)
			discarded_energies.append(energy)

	var post_check = await main.check_confused_retreat(main.opponent_active_pokemon, true, "post_energy")
	if not post_check:
		main.display_pokemon(true)
		main.display_active_pokemon_energies(true)
		return

	# [CHASE] (neo4-57 Unown [C]): player's active Unown [C] may deal 1 damage counter when CPU retreats
	await main.powers_and_bodies.check_neo4_chase(main.opponent_active_pokemon, true)
	if main._should_bail(): return
	# ECARD2 Suction Cups (Octillery): if player's Active is Octillery, discard CPU's energy when it retreats
	main.powers_and_bodies.check_suction_cups(main.opponent_active_pokemon, true)

	# Swap positions
	var old_active = main.opponent_active_pokemon
	main.opponent_bench.erase(best_replacement)
	main.opponent_bench.append(old_active)
	old_active.current_location = "bench"
	best_replacement.current_location = "active"
	main.opponent_active_pokemon = best_replacement
	main.opponent_retreated_this_turn = true

	print("CPU retreated " + old_active.metadata["name"] + " for " + best_replacement.metadata["name"])
	await main.animate_retreat(old_active, best_replacement, discarded_energies, true)
	if main._should_bail(): return
	# NEO3 Balloon Berry (neo3-60): if CPU used Balloon Berry for free retreat, discard it
	main.trainer_effects.consume_balloon_berry(old_active, true)
	main.clear_all_statuses(old_active, true)
	main.display_pokemon(true)
	main.display_active_pokemon_energies(true)

	# Update Ditto Transform after active switch
	main.powers_and_bodies.update_ditto_transform(true)
	main.powers_and_bodies.update_ditto_transform(false)

	# NEO3 Magma Pool (Magcargo neo3-33): when Magcargo retreats, both pokemon take 20 damage
	main.powers_and_bodies.check_magma_pool(old_active, main.opponent_active_pokemon, true)
	await main.check_all_knockouts()
	if main._should_bail(): return
	# Sinkhole (Dark Dugtrio): damage to retreating Pokemon
	await main.powers_and_bodies.check_sinkhole(old_active, true)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	# NEO2 Pursuit (Umbreon): if retreating opponent pokemon has pursuit_active, take 10 damage
	if old_active.pursuit_active:
		old_active.pursuit_active = false
		old_active.current_hp = max(0, old_active.current_hp - 10)
		main.display_hp_circles_above_align(old_active, true)
		await main.show_message("PURSUIT! " + old_active.metadata.get("name","").to_upper() + " TAKES 10 DAMAGE FOR RETREATING!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	# NEO2 Spikes (Forretress): 10 damage to new opponent active after CPU retreat
	await main.powers_and_bodies.check_spikes(best_replacement, true)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

	# Fix 2: Invalidate CPU evaluation cache after retreat changes board
	invalidate_cpu_evaluation()

# CPU automatically picks a random prize card and moves it to hand
func pick_best_bench_replacement(bench: Array, against_pokemon: card_object, cpu_eval: Dictionary) -> card_object:
	var best_replacement: card_object = null
	var best_score: float = -999.0

	for bench_pokemon in bench:
		var score = score_bench_as_replacement(bench_pokemon, against_pokemon, cpu_eval)
		if score > best_score:
			best_score = score
			best_replacement = bench_pokemon

	return best_replacement

# Scores a single bench pokemon as a potential active replacement considering attacks, survivability, and type matchups
func score_bench_as_replacement(bench_pokemon: card_object, against_pokemon: card_object, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var bench_key = bench_pokemon.get_instance_id()
	var bench_data = cpu_eval["pokemon_data"].get(bench_key, {})
	if bench_data.is_empty():
		bench_data = evaluate_single_pokemon(bench_pokemon)

	var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])

	# Can already attack: strong preference
	if bench_data.get("can_attack", false):
		score += 200.0

	# Among attackers, prefer one that can KO the opposing active
	if bench_data.get("can_attack", false) and against_pokemon != null:
		for attack in bench_data.get("attack_data", []):
			if attack["unmet"] > 0:
				continue
			var result = main.calculate_final_damage(attack["damage_min"], bench_types, against_pokemon)
			if result["damage"] >= against_pokemon.current_hp:
				score += 150.0
				break

	# Closest to attacking if can't attack yet
	if not bench_data.get("can_attack", false):
		var lowest_unmet = 999
		for attack in bench_data.get("attack_data", []):
			if attack["unmet"] < lowest_unmet:
				lowest_unmet = attack["unmet"]
		if lowest_unmet < 999:
			score += max(0.0, 80.0 - (lowest_unmet * 25.0))

	# Survivability: can this pokemon take a hit from the opposing active
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		var enemy_max_damage = 0
		for attack in against_pokemon.metadata.get("attacks", []):
			if get_unmet_energy_count(attack, against_pokemon) > 0:
				continue
			var damage_range = main.attack_effects.estimate_attack_damage_range(attack)
			var result = main.calculate_final_damage(damage_range["max"], enemy_types, bench_pokemon)
			enemy_max_damage = max(enemy_max_damage, result["damage"])
		if bench_pokemon.current_hp > enemy_max_damage:
			score += 100.0

	# Type advantage: our attacks hit the opponent's weakness
	if against_pokemon != null:
		for weakness in against_pokemon.metadata.get("weaknesses", []):
			if weakness["type"] in bench_types:
				score += 75.0
				break

	# Type disadvantage: opponent's attacks hit our weakness
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		for weakness in bench_pokemon.metadata.get("weaknesses", []):
			if weakness["type"] in enemy_types:
				score -= 60.0
				break

	# Resistance bonus: we resist the opponent's type
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		for resistance in bench_pokemon.metadata.get("resistances", []):
			if resistance["type"] in enemy_types:
				score += 50.0
				break

	# HP tiebreaker
	score += bench_pokemon.current_hp * 0.1

	return score

# Scores a single (pokemon, energy_card) pair using all Phase 2 rules
func cpu_phase_energy_attachment(cpu_eval: Dictionary) -> void:
	# Phase 0.1: Skip if no energy cards in hand
	var energy_cards_in_hand = []
	for card in main.opponent_hand:
		if card.metadata.get("supertype", "").to_lower() == "energy":
			energy_cards_in_hand.append(card)

	if energy_cards_in_hand.is_empty() or main.opponent_energy_played_this_turn:
		return

	# Phase 0.2: Build candidate targets (active + bench)
	var candidates = get_all_cpu_field_pokemon()

	# Phase 2: Score every (pokemon, energy_card) pair
	var scored_pairs = []
	for pokemon in candidates:
		var key = pokemon.get_instance_id()
		var pokemon_data = cpu_eval["pokemon_data"].get(key, {})
		for energy_card in energy_cards_in_hand:
			var score = score_energy_pair(pokemon, energy_card, cpu_eval, pokemon_data)
			scored_pairs.append({
				"pokemon": pokemon,
				"energy_card": energy_card,
				"score": score
			})

	if scored_pairs.is_empty():
		return

	# Phase 3.1: Sort by score descending
	scored_pairs.sort_custom(func(a, b): return a["score"] > b["score"])
	var best = scored_pairs[0]

	# Phase 3.3: Tiebreaking
	best = resolve_energy_tiebreak(scored_pairs, cpu_eval)

	# Phase 3.4: Always attach even if score is negative
	var target = best["pokemon"]
	var energy = best["energy_card"]

	print("CPU attaching " + energy.metadata["name"] + " to " + target.metadata["name"] + " (Score: " + str(int(best["score"])) + ")")

	# Check special energy attachment restrictions
	var subtypes = energy.metadata.get("subtypes", [])
	if "Special" in subtypes:
		var attach_check = main.special_energy_effects.can_attach_to(energy, target)
		if not attach_check["allowed"]:
			print("CPU energy attachment blocked: ", attach_check["reason"])
			return
	# Pure Body (Suicune): block Water Energy if Suicune has no energies to discard
	if main.powers_and_bodies.check_pure_body_block(energy, target):
		print("CPU energy attachment blocked: Pure Body — no energy to discard")
		return
	# ECARD2 Anti-Lightning (Zapdos): can't attach Lightning Energy from hand to Zapdos
	if main.powers_and_bodies.check_anti_lightning_block(energy, target):
		print("CPU energy attachment blocked: Anti-Lightning")
		return
	# ECARD3 Water Immunity (Articuno) / Fire Immunity (Moltres): can't attach that type of Energy
	if main.powers_and_bodies.check_ecard3_type_immunity_block(energy, target):
		print("CPU energy attachment blocked: type immunity")
		return

	# EX5 Freeze Lock (Regice ex ex5-97): can't attach Energy from hand to a Freeze-Locked Pokemon
	if target.has_effect("ex5_energy_lock"):
		print("CPU energy attachment blocked: Freeze Lock")
		return

	# Perform the attachment
	main.opponent_hand.erase(energy)
	target.attached_energies.append(energy)
	# EX5 Island Cave (ex5-89): attaching to a Water/Fighting/Metal Pokemon clears Special Conditions
	main.trainer_effects.ex5_island_cave_on_attach(target, true)
	# MATCH EFFECT: extra_energy_per_turn — flag only set once the per-turn limit is reached
	main.opponent_energy_attach_count += 1
	main.opponent_energy_played_this_turn = main.opponent_energy_attach_count >= main.match_effects.energy_attach_limit(true)

	await main.show_message("Opponent attached " + energy.metadata["name"].to_upper() + " to " + target.metadata["name"].to_upper() + "!")
	if main._should_bail(): return

	var energy_target_node = main.opponent_energy_container if target == main.opponent_active_pokemon else main.opponent_bench_container
	var energy_texture = main.get_card_texture(energy)
	await main.animate_card_a_to_b(main.opponent_hand_container, energy_target_node, 0.2, energy_texture, main.card_scales[12])
	if main._should_bail(): return

	main.refresh_hand_display(true)
	main.display_pokemon(true)
	main.display_active_pokemon_energies(true)
	await get_tree().process_frame
	if main._should_bail(): return
	await main.play_energy_attached_effect(target, energy)
	if main._should_bail(): return
	
	# Apply special energy on-attach effects (Rainbow self-damage, Full Heal cure, Potion heal, etc.)
	if "Special" in subtypes:
		await main.special_energy_effects.apply_on_attach_effects(energy, target, true)
		if main._should_bail(): return
		# EX11 Delta Moon (Umbreon δ): opponent attaching a Special Energy takes 1 counter on that Pokemon.
		await main.powers_and_bodies.check_ex11_delta_moon(target, true)
		if main._should_bail(): return

	# GYM2 Blaine's Ninetales Healing Fire — heal 10 when Fire energy is attached from hand
	await main.powers_and_bodies.check_healing_fire(target, energy, true)
	if main._should_bail(): return
	# NEO2 Energy Evolution (Eevee neo2-38): on energy attach, flip for matching evo
	await main.powers_and_bodies.check_energy_evolution(target, energy, true)
	if main._should_bail(): return
	# GYM2 Sabrina's Gastly Gaseous Form — +10 HP per Psychic energy attached
	main.powers_and_bodies.refresh_gaseous_form_hp()
	# NEO3 Triggered Poison (Crobat neo3-4): if energy is attached to a pokemon with triggered_poison_active, poison it
	await main.powers_and_bodies.check_triggered_poison(target, true)
	if main._should_bail(): return
	# NEO3 Lightning Burst (Flaaffy neo3-28): when Lightning Energy attached, deal 10 to each player bench
	main.powers_and_bodies.check_lightning_burst(target, energy, true)
	# NEO4 Conductivity (Dark Ampharos neo4-1): opponent's Ampharos deals 10 to this Pokemon
	main.powers_and_bodies.check_neo4_conductivity(target, true)
	if main._should_bail(): return
	# NP Pure Body (Suicune): discard an energy after Water Energy attached
	await main.powers_and_bodies.check_pure_body_discard(energy, target, true)
	if main._should_bail(): return
	# ECARD2 Pokemon Park: energy attached from hand to a Benched Pokemon heals 1 damage counter
	if target != main.opponent_active_pokemon:
		main.trainer_effects.pokemon_park_on_bench_energy_attach(target, true)
	# ECARD2/ECARD3 Crystal Type: matching-type Energy attach temporarily changes the holder's type
	main.powers_and_bodies.check_crystal_type_attach(target, energy, true)
	# ECARD3 Self-healing (Flareon): Fire Energy attach from hand cures all Special Conditions
	main.powers_and_bodies.check_ecard3_self_healing(target, energy, true)
	# EX1 Natural Cure (Combusken/Grovyle/Marshtomp): matching-type Energy attach cures all Special Conditions
	main.powers_and_bodies.check_ex1_natural_cure(target, energy, true)
	# EX1 Natural Remedy (Swampert ex1-23): Water Energy attach from hand heals 1 damage counter
	main.powers_and_bodies.check_ex1_natural_remedy(target, energy, true)
	# EX12 Reactive Healing (Tangela) / Fire Remedy (Arcanine ex): on-attach body triggers.
	main.powers_and_bodies.check_ex12_reactive_healing(target, energy, true)
	main.powers_and_bodies.check_ex12_fire_remedy(target, energy, true)
	# EX7 Saturation (Quagsire ex7-26 / Wooper ex7-81): Water Energy attach clears conditions + heals
	main.powers_and_bodies.check_ex7_saturation(target, energy, true)
	# EX8 Lightning Burst (Rocket's Raikou ex ex8-108): Darkness Energy attach may switch a Defender
	await main.powers_and_bodies.check_ex8_lightning_burst(target, energy, true)

	# MATCH EFFECTS: energy_attach_halve_hp / energy_attach_full_heal
	await main.apply_energy_attach_match_effects(target, true)
	if main._should_bail(): return

	# Fix 2: Invalidate CPU evaluation cache after energy attachment
	invalidate_cpu_evaluation()
	
# Chooses and executes an attack to end the CPU turn (Phase 8)
func score_energy_pair(pokemon: card_object, energy_card: card_object, cpu_eval: Dictionary, pokemon_data: Dictionary) -> float:
	var score = 0.0
	var is_active = (pokemon == main.opponent_active_pokemon)
	var energy_types = main.get_energy_provided_by_card(energy_card)
	
	# DCE restriction: only attach to pokemon with an attack requiring 2+ Colorless
	if main.trainer_effects.is_double_colorless_energy(energy_card):
		var has_2_colorless_attack = false
		for attack in pokemon.metadata.get("attacks", []):
			var colorless_count = 0
			for req in attack.get("cost", []):
				if req == "Colorless":
					colorless_count += 1
			if colorless_count >= 2:
				has_2_colorless_attack = true
				break
		if not has_2_colorless_attack:
			return -500.0  # Hard disqualification: this pokemon can't effectively use DCE
	
	# Flat active/bench modifier: active pokemon almost always takes priority
	if is_active:
		score += 40.0
	else:
		score -= 20.0
	
	# 2.1, 2.2, 2.3: Energy type matching (can disqualify a pair)
	score += score_energy_type_match(pokemon, energy_types, pokemon_data, is_active)

	# 2.4, 2.5: Active pokemon needs energy
	if is_active:
		score += score_active_needs_energy(pokemon, energy_types, pokemon_data)

	# 2.6: Active pokemon already fully powered
	if is_active:
		score += score_active_overpowered(pokemon_data, cpu_eval)

	# 2.7, 2.8, 2.9: Active pokemon under KO threat
	if is_active:
		score += score_active_ko_threat(pokemon, energy_types, pokemon_data, cpu_eval)

	# 2.10, 2.11: Evolution potential
	score += score_evolution_potential(pokemon, pokemon_data, cpu_eval, is_active)

	# 2.12, 2.13, 2.14: Bench pokemon scoring
	if not is_active:
		score += score_bench_candidate(pokemon, pokemon_data, cpu_eval)

	# 2.15: Attack self-discard consideration
	score += score_self_discard_penalty(pokemon)

	# Special energy scoring (Rainbow self-damage, Full Heal cure, etc.)
	var subtypes = energy_card.metadata.get("subtypes", [])
	if "Special" in subtypes:
		score += main.special_energy_effects.score_special_energy_attachment(energy_card, pokemon, is_active)

	# EXTRA ENERGY BEYOND COST: Score bonus for attacks like Poliwag/Blastoise that do more damage with extra energy
	if is_active:
		for attack in pokemon.metadata.get("attacks", []):
			var atk_text = attack.get("text", "").to_lower()
			if "more damage for each" in atk_text and "not used to pay" in atk_text:
				# Check if we haven't hit the cap yet
				var cost = attack.get("cost", [])
				var bonus_type = ""
				var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
				for tkw in type_keywords:
					if tkw + " energy attached" in atk_text:
						bonus_type = tkw.capitalize()
						break
				if bonus_type != "":
					var current_of_type = 0
					for e in pokemon.attached_energies:
						if bonus_type in main.get_energy_provided_by_card(e):
							current_of_type += 1
					var needed_for_cost = 0
					for c in cost:
						if c == bonus_type:
							needed_for_cost += 1
					var extra = max(0, current_of_type - needed_for_cost)
					# Parse cap
					var cap = 99
					if "after the" in atk_text and "don't count" in atk_text:
						var after_pos = atk_text.find("after the")
						var after_text = atk_text.substr(after_pos + 10, 10)
						var cap_num = ""
						for ch in after_text:
							if ch.is_valid_int():
								cap_num += ch
							else:
								break
						if cap_num != "":
							cap = max(0, int(cap_num) - needed_for_cost)
					
					if extra < cap:
						# We can benefit from more energy of this type
						var provides_bonus_type = false
						for provided in energy_types:
							if provided == bonus_type:
								provides_bonus_type = true
								break
						if provides_bonus_type:
							# Check if CPU won't be KO'd next turn (no point in over-investing)
							var ko_threats = evaluate_ko_threats()
							if not ko_threats["cpu_active_guaranteed_ko"]:
								score += 60.0
								print("ENERGY SCORE: +60 for extra energy bonus attack on ", pokemon.metadata["name"])

	return score
	
# 2.1, 2.2, 2.3: Checks if energy type is useful for this pokemon
func score_energy_type_match(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary, is_active: bool) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# Gather all specific (non-colorless) energy types needed across all attacks
	var needed_types = []
	for attack in attack_data:
		for req in attack.get("cost", []):
			if req != "Colorless" and req not in needed_types:
				needed_types.append(req)

	# Check if this energy provides a type that matches any attack cost
	var has_type_match = false
	for provided in energy_types:
		if provided in needed_types or provided == "Any":
			has_type_match = true
			break

	# Direct type match — this energy is exactly what the pokemon wants
	if has_type_match:
		score += 80.0 if is_active else 60.0
		return score

	# Check if this pokemon has any attacks with unmet colorless slots
	var has_unmet_colorless_slots = false
	for attack in attack_data:
		if attack["unmet"] <= 0:
			continue
		# Count how many colorless slots exist in this attack's cost
		var colorless_in_cost = attack["cost"].count("Colorless")
		if colorless_in_cost > 0:
			has_unmet_colorless_slots = true
			break

	# Any energy can fill colorless slots — moderate positive match
	if has_unmet_colorless_slots:
		score += 50.0 if is_active else 35.0
		return score

	# 2.2: Does attaching this energy fill a colorless slot and unlock an attack?
	var unlocks_via_colorless = false
	for attack in attack_data:
		if attack["unmet"] <= 0:
			continue
		var colorless_in_cost = attack["cost"].count("Colorless")
		if colorless_in_cost == 0:
			continue
		if attack["unmet"] == 1:
			var typed_unmet = attack["unmet"] - colorless_in_cost
			if typed_unmet <= 0:
				unlocks_via_colorless = true
				break

	if unlocks_via_colorless:
		score += 40.0 if is_active else 30.0
		return score

	# 2.3: Check if ANY pokemon in play needs this energy type specifically
	var any_pokemon_needs_type = false
	for field_pokemon in get_all_cpu_field_pokemon():
		if field_pokemon == pokemon:
			continue
		for attack in field_pokemon.metadata.get("attacks", []):
			for req in attack.get("cost", []):
				if req != "Colorless":
					for provided in energy_types:
						if provided == req or provided == "Any":
							any_pokemon_needs_type = true

	if any_pokemon_needs_type:
		score -= 200.0
		return score

	# Nobody needs this type — colorless fallback scoring
	var total_unmet_colorless = 0
	for attack in attack_data:
		if attack["unmet"] > 0:
			total_unmet_colorless += attack["cost"].count("Colorless")

	if total_unmet_colorless > 0:
		score += total_unmet_colorless * 5.0
		if is_active:
			score += 10.0
		return score

	score -= 200.0
	return score
	
# 2.4, 2.5: Active pokemon has unmet energy requirements
func score_active_needs_energy(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# 2.4: Active has at least one attack with unmet energy
	var has_unmet = false
	var lowest_unmet = 999
	for attack in attack_data:
		if attack["unmet"] > 0:
			has_unmet = true
			if attack["unmet"] < lowest_unmet:
				lowest_unmet = attack["unmet"]

	if has_unmet:
		score += 80.0
		# Progress bonus: the closer to unlocking, the more valuable each energy is
		if lowest_unmet <= 3:
			score += max(0.0, 80.0 - (lowest_unmet * 20.0))

	# 2.5: Would this specific energy unlock a currently unusable attack?
	for attack in attack_data:
		if attack["unmet"] != 1:
			continue
		var remaining_type = get_remaining_requirement(attack, pokemon)
		if remaining_type == null:
			continue
		if remaining_type == "Colorless":
			score += 100.0
			break
		for provided in energy_types:
			if provided == remaining_type or provided == "Any":
				score += 100.0
				break

	return score
	
# Returns the energy type of the single remaining unmet requirement, or null if not exactly 1 unmet
func get_remaining_requirement(attack_info: Dictionary, pokemon: card_object) -> String:
	if attack_info["unmet"] != 1:
		return ""
	var cost = attack_info["cost"].duplicate()

	# Build the available energy pool from attached energies
	var pool = []
	for attached in pokemon.attached_energies:
		pool.append_array(main.get_energy_provided_by_card(attached))

	# Remove typed requirements that are already satisfied
	for req in cost:
		if req == "Colorless":
			continue
		var idx = pool.find(req)
		if idx != -1:
			pool.remove_at(idx)
			cost[cost.find(req)] = "_SATISFIED_"
		else:
			var any_idx = pool.find("Any")
			if any_idx != -1:
				pool.remove_at(any_idx)
				cost[cost.find(req)] = "_SATISFIED_"
			else:
				return req

	# All typed requirements met — remaining must be colorless
	for req in cost:
		if req == "Colorless":
			if pool.size() > 0:
				pool.remove_at(0)
			else:
				return "Colorless"

	return ""

# 2.6: Penalises over-investment when active is already fully powered
func score_active_overpowered(pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var attack_data = pokemon_data.get("attack_data", [])

	# Check if all attacks already have energy requirements met
	var all_attacks_met = true
	for attack in attack_data:
		if attack["unmet"] > 0:
			all_attacks_met = false
			break

	if not all_attacks_met:
		return 0.0

	# Exception: if this pokemon can evolve and the evolved form needs more energy
	if pokemon_data.get("can_evolve_further", false) and pokemon_data.get("evolved_form_needs_energy", false):
		return 0.0

	return -100.0

# 2.7, 2.8, 2.9: Adjusts score when active is threatened with KO
func score_active_ko_threat(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var can_attack = pokemon_data.get("can_attack", false)
	var guaranteed_ko = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var potential_ko = cpu_eval.get("cpu_active_potential_ko", false)
	var bench_ko_threat = cpu_eval.get("player_bench_ko_threat", false)

	if not guaranteed_ko and not potential_ko and not bench_ko_threat:
		return 0.0

	# 2.8: Check if attaching this energy would enable a KO on the player's active
	var enables_ko = false
	if main.player_active_pokemon != null:
		var cpu_types = pokemon.metadata.get("types", ["Colorless"])
		var player_hp = main.player_active_pokemon.current_hp
		var attack_data = pokemon_data.get("attack_data", [])

		for attack in attack_data:
			if attack["unmet"] != 1:
				continue
			var remaining = get_remaining_requirement(attack, pokemon)
			if remaining == "":
				continue
			var type_matches = remaining == "Colorless"
			if not type_matches:
				for provided in energy_types:
					if provided == remaining or provided == "Any":
						type_matches = true
						break
			if not type_matches:
				continue
			var result = main.calculate_final_damage(attack["damage_min"], cpu_types, main.player_active_pokemon)
			if result["damage"] >= player_hp:
				enables_ko = true
				break

	if enables_ko:
		# Striking first is extremely valuable — override KO threat penalties
		if cpu_eval.get("cpu_prizes_remaining", 6) == 1:
			return 500.0
		return 250.0

	# 2.7a: Guaranteed KO and active can already attack — don't invest further
	if guaranteed_ko and can_attack:
		# 2.9: Partial override — extra damage before going down if bench backup exists
		if cpu_eval.get("has_viable_bench_attacker", false):
			var unlocks_stronger = false
			for attack in pokemon_data.get("attack_data", []):
				if attack["unmet"] == 1:
					unlocks_stronger = true
					break
			if unlocks_stronger:
				return -80.0
		return -150.0

	# 2.7c: Guaranteed KO and cannot attack yet
	if guaranteed_ko and not can_attack:
		var would_enable_attack = false
		for attack in pokemon_data.get("attack_data", []):
			if attack["unmet"] == 1:
				would_enable_attack = true
				break
		
		if not would_enable_attack:
			return -200.0
		else:
			return -100.0
			
	return 0.0

# 2.10, 2.11: Scores evolution potential for energy investment
func score_evolution_potential(pokemon: card_object, pokemon_data: Dictionary, cpu_eval: Dictionary, is_active: bool) -> float:
	var score = 0.0
	var has_evo_in_hand = pokemon_data.get("evolution_in_hand", null) != null
	var has_evo_in_deck = pokemon_data.get("evolution_in_deck_or_prizes", false)
	var needs_energy = pokemon_data.get("evolved_form_needs_energy", false)

	# 2.10a: Evolution in hand and evolved form needs more energy
	if has_evo_in_hand and needs_energy:
		score += 100.0

	# 2.10b: Evolution in deck/prizes only — less certain
	elif has_evo_in_deck and needs_energy:
		score += 50.0

	# 2.11: Active already doing its job — redirect to evolving bench pokemon
	if is_active and cpu_eval.get("cpu_can_ko_player_active", false):
		var dominated_by_bench_evo = false
		for bench_pokemon in main.opponent_bench:
			var bench_key = bench_pokemon.get_instance_id()
			var bench_data = cpu_eval["pokemon_data"].get(bench_key, {})
			var bench_has_evo = bench_data.get("evolution_in_hand", null) != null or bench_data.get("evolution_in_deck_or_prizes", false)
			var bench_needs_energy = bench_data.get("evolved_form_needs_energy", false)
			if bench_has_evo and bench_needs_energy:
				dominated_by_bench_evo = true
				break

		if dominated_by_bench_evo:
			score -= 70.0

	return score

# 2.12, 2.13, 2.14: Scores bench pokemon as energy targets
func score_bench_candidate(pokemon: card_object, pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# 2.12: Base score for bench pokemon with unmet energy
	var has_unmet = false
	for attack in attack_data:
		if attack["unmet"] > 0:
			has_unmet = true
			break

	if has_unmet:
		score += 50.0

	# 2.13: Boost bench when active is doomed and can already attack
	var active_doomed = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var active_key = main.opponent_active_pokemon.get_instance_id() if main.opponent_active_pokemon != null else -1
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})
	var active_can_attack = active_data.get("can_attack", false)

	if active_doomed and active_can_attack:
		score += 100.0

		# Prefer bench pokemon that can survive the player's strongest usable attack
		if main.player_active_pokemon != null:
			var player_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])
			var player_max_damage = 0
			for attack in main.player_active_pokemon.metadata.get("attacks", []):
				if get_unmet_energy_count(attack, main.player_active_pokemon) > 0:
					continue
				var damage_range = main.attack_effects.estimate_attack_damage_range(attack)
				var result = main.calculate_final_damage(damage_range["max"], player_types, pokemon)
				player_max_damage = max(player_max_damage, result["damage"])

			if pokemon.current_hp > player_max_damage:
				score += 40.0

	# 2.14: Proximity bonus — fewer unmet energy means closer to attacking
	var lowest_unmet = 999
	for attack in attack_data:
		if attack["unmet"] > 0 and attack["unmet"] < lowest_unmet:
			lowest_unmet = attack["unmet"]

	if lowest_unmet < 999:
		score += max(0.0, 60.0 - (lowest_unmet * 20.0))

	return score

# 2.15: Penalises pokemon whose preferred attack discards attached energy
func score_self_discard_penalty(pokemon: card_object) -> float:
	var pokemon_name = pokemon.metadata.get("name", "")
	var max_attack = get_maximum_damage_attack(pokemon)

	if max_attack.is_empty():
		return 0.0

	var penalty = get_attack_text_penalty(max_attack.get("text", ""), pokemon_name)

	# Scale down — this is a tiebreaker, not a dealbreaker
	return penalty * 0.3

# Resolves tiebreaks when multiple pairs share the highest score (3.3)
func resolve_energy_tiebreak(scored_pairs: Array, cpu_eval: Dictionary) -> Dictionary:
	var best_score = scored_pairs[0]["score"]

	# Collect all pairs that share the top score
	var tied = []
	for pair in scored_pairs:
		if pair["score"] == best_score:
			tied.append(pair)
		else:
			break

	if tied.size() == 1:
		return tied[0]

	# Tiebreak 1: Prefer active pokemon over bench
	var active_only = tied.filter(func(p): return p["pokemon"] == main.opponent_active_pokemon)
	if active_only.size() == 1:
		return active_only[0]
	if active_only.size() > 1:
		tied = active_only

	# Tiebreak 2: Prefer pokemon closer to having a usable attack (lowest unmet)
	var best_unmet = 999
	for pair in tied:
		var key = pair["pokemon"].get_instance_id()
		var pokemon_data = cpu_eval["pokemon_data"].get(key, {})
		for attack in pokemon_data.get("attack_data", []):
			if attack["unmet"] > 0 and attack["unmet"] < best_unmet:
				best_unmet = attack["unmet"]

	var closest = tied.filter(func(p):
		var key = p["pokemon"].get_instance_id()
		var pd = cpu_eval["pokemon_data"].get(key, {})
		var lowest = 999
		for attack in pd.get("attack_data", []):
			if attack["unmet"] > 0 and attack["unmet"] < lowest:
				lowest = attack["unmet"]
		return lowest == best_unmet
	)
	if closest.size() == 1:
		return closest[0]
	if closest.size() > 1:
		tied = closest

	# Tiebreak 3: Prefer pokemon with higher remaining HP
	var best_hp = -1
	for pair in tied:
		if pair["pokemon"].current_hp > best_hp:
			best_hp = pair["pokemon"].current_hp

	for pair in tied:
		if pair["pokemon"].current_hp == best_hp:
			return pair

	return tied[0]

# Scores the value of parsed attack effects for CPU attack selection
func score_parsed_effects(effects: Array, defender: card_object) -> float:
	var score = 0.0

	for effect in effects:
		var flip_mult = 1.0
		if effect.get("flip", "none") != "none":
			flip_mult = 0.5

		if effect["type"] == "status" and effect["target"] == "defender":
			if defender.special_condition == effect["status"]:
				continue
			match effect["status"]:
				"Paralyzed":
					score += 80.0 * flip_mult
				"Asleep":
					score += 50.0 * flip_mult
				"Confused":
					score += 40.0 * flip_mult
				"Poisoned":
					if not defender.is_poisoned:
						score += 30.0 * flip_mult
				"Burned":
					if not defender.is_burned:
						score += 25.0 * flip_mult

		if effect["type"] == "status" and effect["target"] == "self":
			match effect["status"]:
				"Confused":
					score -= 30.0 * flip_mult
				"Asleep":
					score -= 40.0 * flip_mult
				"Poisoned":
					score -= 30.0 * flip_mult
				"Burned":
					score -= 25.0 * flip_mult

		if effect["type"] == "toxic":
			if not defender.is_poisoned or defender.poison_damage < 20:
				score += 50.0 * flip_mult

		if effect["type"] == "self_damage":
			score -= effect.get("damage", 0) * 0.5

		if effect["type"] == "energy_discard_self":
			var count = effect.get("count", 1)
			if count == -1:
				score -= 70.0
			else:
				score -= count * 10.0

		if effect["type"] == "energy_discard_defender":
			if defender.attached_energies.size() > 0:
				score += 25.0 * flip_mult

		if effect["type"] == "bench_damage":
			var target_bench_size = 0
			if effect["target"] == "main.opponent_bench":
				target_bench_size = main.player_bench.size()
			elif effect["target"] == "own_bench":
				target_bench_size = main.opponent_bench.size()
				score -= effect.get("damage", 0) * target_bench_size * 0.3
				continue
			elif effect["target"] == "all_benches":
				target_bench_size = main.player_bench.size()
				var own_penalty = effect.get("damage", 0) * main.opponent_bench.size() * 0.3
				score -= own_penalty
			score += effect.get("damage", 0) * target_bench_size * 0.3

		if effect["type"] == "blind":
			score += 30.0 * flip_mult

		if effect["type"] == "retreat_lock":
			score += 20.0 * flip_mult

		if effect["type"] == "draw":
			score += 15.0 * effect.get("count", 1)

		if effect["type"] == "self_heal":
			var max_hp = int(effects[0].get("damage", 0)) if false else 0
			var damage_on_attacker = 0
			if main.opponent_active_pokemon != null:
				var max_hp_real = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
				damage_on_attacker = max_hp_real - main.opponent_active_pokemon.current_hp
			if damage_on_attacker > 0:
				score += 20.0 * flip_mult

		if effect["type"] == "invincible":
			score += 60.0 * flip_mult

		if effect["type"] == "no_damage":
			score += 40.0 * flip_mult

		if effect["type"] == "destiny_bond":
			var attacker_hp_pct = 0.0
			if main.opponent_active_pokemon != null:
				var max_hp = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
				attacker_hp_pct = float(main.opponent_active_pokemon.current_hp) / max(max_hp, 1)
			if attacker_hp_pct <= 0.3:
				score += 50.0
			else:
				score += 10.0

		if effect["type"] == "shielded_damage":
			# Harden is more valuable when we expect low damage attacks next turn
			score += 25.0 * flip_mult

		if effect["type"] == "force_switch":
			# Forcing a switch is useful if the defender has built up energy/status
			if defender.attached_energies.size() >= 2:
				score += 25.0 * flip_mult
			else:
				score += 10.0 * flip_mult


		if effect["type"] == "self_switch":
			# Value depends on board state — retreat to safety if low HP
			if main.opponent_active_pokemon != null:
				var active_hp_pct = float(main.opponent_active_pokemon.current_hp) / max(int(main.opponent_active_pokemon.metadata.get("hp", "1")), 1)
				if active_hp_pct < 0.3:
					score += 40.0  # Retreat to safety
				else:
					score -= 20.0  # Probably don't want to switch
		
		if effect["type"] == "bench_damage_single":
			if main.player_bench.size() > 0:
				score += effect.get("damage", 10) * 0.5

		if effect["type"] == "leech_seed_heal":
			var damage_on_attacker = 0
			if main.opponent_active_pokemon != null:
				var max_hp_r = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
				damage_on_attacker = max_hp_r - main.opponent_active_pokemon.current_hp
			if damage_on_attacker > 0:
				score += 10.0

		if effect["type"] == "damage_reduction":
			score += 15.0

		if effect["type"] == "attack_block":
			score += 20.0 * flip_mult

		if effect["type"] == "leech_seed":
			if main.opponent_active_pokemon != null:
				var dmg = int(main.opponent_active_pokemon.metadata.get("hp", "0")) - main.opponent_active_pokemon.current_hp
				if dmg > 0:
					score += 5.0

	if defender.is_invincible:
		var defender_bonus = 0.0
		for effect in effects:
			if effect.get("target") == "defender":
				defender_bonus = 0.0
				break
		score = min(score, score - defender_bonus)

	return score
	
################################################### END OPPONENT PRIORITISE FUNCTIONALITY FUNCTIONS ##################################################
######################################################################################################################################################
 
# #######  ######   ##   ##        ######   #######    ####### #######
# ##       ##   ##  ##   ##        ##      ##     ##  ##       ##
# ##       ######   ##   ##  ##### ##      ##     ##  ##       #######
# ##       ##       ##   ##        ##      ##     ##  ##       ##
# #######  ##       #######        #######  #######   ##       #######

######################################################################################################################################################
###################################################### OPPONENT GENERAL FUNCTIONALITY FUNCTIONS ######################################################

# Load all the opponent's data
func cpu_phase_attack(cpu_eval: Dictionary) -> void:
	if main.opponent_active_pokemon == null or main.player_active_pokemon == null:
		return
	
	if main.turn_number <= 1:
		return
	
	if main.opponent_active_pokemon.special_condition == "Paralyzed":
		print("CPU cannot attack: active is Paralyzed")
		return
	if main.opponent_active_pokemon.special_condition == "Asleep":
		print("CPU cannot attack: active is Asleep")
		return
	
	# Check attack readiness from live board state, not stale cpu_eval
	var has_usable_attack = false
	for attack in main.opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, main.opponent_active_pokemon) == 0 and not main.is_attack_disabled(main.opponent_active_pokemon, attack.get("name", "")):
			has_usable_attack = true
			break

	if not has_usable_attack:
		print("CPU cannot attack: no usable attacks")
		return

	var cpu_types = main.opponent_active_pokemon.metadata.get("types", ["Colorless"])
	var player_hp = main.player_active_pokemon.current_hp
	var attacks = main.opponent_active_pokemon.metadata.get("attacks", [])
	var pokemon_name = main.opponent_active_pokemon.metadata.get("name", "")
	
	# Check if CPU is guaranteed to be KO'd next turn
	var ko_threats = evaluate_ko_threats()
	var cpu_will_be_koed = ko_threats["cpu_active_guaranteed_ko"]
	
	# Score each usable attack
	var best_attack_index = -1
	var best_attack_score = -999.0

	for i in range(attacks.size()):
		var attack = attacks[i]
		var attack_name_lower = attack.get("name", "").to_lower()
		var attack_text = attack.get("text", "").to_lower()
		
		if get_unmet_energy_count(attack, main.opponent_active_pokemon) > 0:
			continue
		if main.is_attack_disabled(main.opponent_active_pokemon, attack.get("name", "")):
			continue

		var score = 0.0
		var damage_range = main.attack_effects.estimate_attack_damage_range(attack, main.opponent_active_pokemon, main.player_active_pokemon)
		var min_result = main.calculate_final_damage(damage_range["min"], cpu_types, main.player_active_pokemon)
		var max_result = main.calculate_final_damage(damage_range["max"], cpu_types, main.player_active_pokemon)
		var parsed_effects = main.attack_effects.parse_card_text_effects(attack.get("text", ""), pokemon_name)

		# ---- GUARANTEED KO: Strongly prefer ----
		if min_result["damage"] >= player_hp:
			score += 500.0
			score -= (min_result["damage"] - player_hp) * 0.5
		# ---- POTENTIAL KO: Variable damage might KO ----
		elif max_result["damage"] >= player_hp:
			score += 200.0
		
		# ---- BASE DAMAGE CONTRIBUTION ----
		score += min_result["damage"] * 2.0

		# ---- STATUS CONDITION SCORING (items 6-7) ----
		var has_status_effect_only = false
		for effect in parsed_effects:
			if effect["type"] == "status" and effect["target"] == "defender":
				var status = effect["status"]
				var already_has = false
				if status in ["Paralyzed", "Asleep", "Confused"]:
					already_has = (main.player_active_pokemon.special_condition == status)
				elif status == "Poisoned":
					already_has = main.player_active_pokemon.is_poisoned
				elif status == "Burned":
					already_has = main.player_active_pokemon.is_burned
				
				if already_has:
					# Defender already has this status - strongly deprioritise this attack
					# if there's another attack available, use that instead
					score -= 100.0
					has_status_effect_only = true
				# If not already applied, the existing score_parsed_effects handles the bonus

		# ---- SELF DAMAGE VS GUARANTEED KO (items 8-9) ----
		var has_self_damage = false
		var self_damage_amount = 0
		var has_energy_discard = false
		var discard_count = 0
		for effect in parsed_effects:
			if effect["type"] == "self_damage":
				has_self_damage = true
				self_damage_amount = effect.get("damage", 0)
			if effect["type"] == "energy_discard_self":
				has_energy_discard = true
				discard_count = effect.get("count", 1)
		
		# If this attack guarantees KO but has drawbacks, and another attack ALSO guarantees KO without drawbacks
		# prefer the one without drawbacks (item 8, 9)
		if min_result["damage"] >= player_hp:
			if has_energy_discard:
				score -= 50.0  # Penalise discard on guaranteed KO (prefer no-drawback KO)
			if has_self_damage:
				score -= 20.0  # Penalise self-damage on guaranteed KO (less penalty than discard)
		
		# ---- ZAPDOS-STYLE: Both attacks have drawbacks (item 10) ----
		# Self-damage is less bad than energy discard
		if has_self_damage and not has_energy_discard:
			# Check if self-damage would KO us
			if main.opponent_active_pokemon.current_hp - self_damage_amount <= 0:
				score -= 300.0  # Strongly avoid suicide
			else:
				score -= self_damage_amount * 0.3  # Light penalty
		
		if has_energy_discard:
			if discard_count == -1:
				score -= 70.0  # Heavy penalty for discard all
			else:
				score -= discard_count * 15.0
			
			# But if we're going to be KO'd next turn anyway, discard matters less
			if cpu_will_be_koed:
				if discard_count == -1:
					score += 40.0  # Reduce penalty
				else:
					score += discard_count * 8.0
		
		# ---- HEAL ATTACKS (item 11: Starmie/Kadabra Recover) ----
		if "remove all damage counters" in attack_text and damage_range["min"] == 0:
			var current_damage = main.opponent_active_pokemon.get_max_hp() - main.opponent_active_pokemon.current_hp
			if current_damage == 0:
				score -= 200.0  # No damage to heal - waste of attack
			elif cpu_will_be_koed:
				# Check if healing would prevent the KO
				var would_survive = false
				for player_attack in main.player_active_pokemon.metadata.get("attacks", []):
					if get_unmet_energy_count(player_attack, main.player_active_pokemon) == 0:
						var p_range = main.attack_effects.estimate_attack_damage_range(player_attack, main.player_active_pokemon, main.opponent_active_pokemon)
						var p_types = main.player_active_pokemon.metadata.get("types", ["Colorless"])
						var p_result = main.calculate_final_damage(p_range["max"], p_types, main.opponent_active_pokemon)
						if p_result["damage"] < main.opponent_active_pokemon.get_max_hp():
							would_survive = true
				if would_survive:
					score += 150.0  # Healing saves us from KO
				else:
					score -= 50.0  # Healing won't save us, better to attack
			else:
				score -= 100.0  # Not in danger, prefer attacking
		
		# ---- BARRIER/INVINCIBLE ATTACKS (item 11.6: Mewtwo Barrier) ----
		if "prevent all effects of attacks, including damage" in attack_text and damage_range["min"] == 0:
			if cpu_will_be_koed:
				# Check if other attacks can KO the player
				var other_can_ko = false
				for j in range(attacks.size()):
					if j == i:
						continue
					var other_attack = attacks[j]
					if get_unmet_energy_count(other_attack, main.opponent_active_pokemon) > 0:
						continue
					var other_range = main.attack_effects.estimate_attack_damage_range(other_attack, main.opponent_active_pokemon, main.player_active_pokemon)
					var other_result = main.calculate_final_damage(other_range["min"], cpu_types, main.player_active_pokemon)
					if other_result["damage"] >= player_hp:
						other_can_ko = true
						break
				if other_can_ko:
					score -= 100.0  # Can KO with other attack, do that instead
				else:
					score += 100.0  # Can't KO, protect ourselves
			else:
				score -= 80.0  # Not in danger, prefer attacking
		
		# ---- GYM1 (GYM HEROES) ATTACK SCORING ----
		var g1_cpu_active = main.opponent_active_pokemon
		var g1_opp_bench = main.player_bench
		# Discharge: expected damage from discarding all Lightning Energy (cancels the generic discard penalty)
		if "lightning energy cards you discarded" in attack_text:
			var g1_lc = 0
			for e in g1_cpu_active.attached_energies:
				if "Lightning" in main.get_energy_provided_by_card(e):
					g1_lc += 1
			score += 140.0 + g1_lc * 15.0 * 2.0
			if g1_lc * 30 >= player_hp:
				score += 150.0
		# Take Away: escape tool — strong when about to be KO'd, wasteful otherwise
		if "take away" in attack_name_lower:
			score += 90.0 if cpu_will_be_koed else -80.0
		# Crosscounter: counter-attack, excellent when expecting a heavy hit
		if "for double that amount" in attack_text:
			score += 120.0 if cpu_will_be_koed else 40.0
		# Fire Wall: bonus for the counter-attack setup
		if "active pokémon for 10 damage" in attack_text:
			score += 20.0
		# Shadow Images: defensive dodge shield
		if "this effect lasts until" in attack_text:
			score += 90.0 if cpu_will_be_koed else 45.0
		# Deflector: damage-halving shield
		if "divide that damage in half" in attack_text:
			score += 80.0 if cpu_will_be_koed else 40.0
		# Pain Amplifier: only worthwhile if the opponent has damaged Pokemon
		if "put a damage counter on each of your opponent" in attack_text:
			var g1_dmgd = 0
			if main.player_active_pokemon != null and main.player_active_pokemon.get_damage_counters() > 0:
				g1_dmgd += 1
			for bp in g1_opp_bench:
				if bp.get_damage_counters() > 0:
					g1_dmgd += 1
			score += (g1_dmgd * 30.0) if g1_dmgd > 0 else -80.0
		# Knockout Needle: expected bonus damage from the double coin flip
		if "30 damage plus 60 more damage" in attack_text:
			score += 30.0
			if main.player_active_pokemon != null and main.player_active_pokemon.current_hp <= 90:
				score += 60.0
		# Spread attacks: extra value for benched targets
		if ("choose up to 3 of them" in attack_text) or ("choose up to 2 of them" in attack_text) or ("that isn't water" in attack_text) or ("each grass pokémon on your opponent's bench" in attack_text) or ("10 damage to each of your opponent's pokémon" in attack_text):
			score += g1_opp_bench.size() * 12.0
		# Lucky Shot: bench-only, useless without a bench target
		if "benched pokémon and flip a coin" in attack_text:
			score += 20.0 if g1_opp_bench.size() > 0 else -150.0
		# Lava Burst: variable Fire-mill damage
		if "discard the top 5 cards" in attack_text:
			score += 25.0
		# Water Punch: expected bonus per Water Energy
		if "30 damage plus 10 damage for each heads" in attack_text:
			var g1_wc = 0
			for e in g1_cpu_active.attached_energies:
				if "Water" in main.get_energy_provided_by_card(e):
					g1_wc += 1
			score += g1_wc * 5.0 * 2.0
		# Night Spirits: expected damage scales with ghosts in play
		if "total number of sabrina's gastlys" in attack_text:
			var g1_ghosts = 0
			var g1_ghost_names = ["Sabrina's Gastly", "Sabrina's Haunter", "Sabrina's Gengar"]
			if g1_cpu_active.metadata.get("name", "") in g1_ghost_names:
				g1_ghosts += 1
			for bp in main.opponent_bench:
				if bp.metadata.get("name", "") in g1_ghost_names:
					g1_ghosts += 1
			score += g1_ghosts * 15.0 * 2.0
		# Eggsplosion: expected damage scales with attached Energy
		if "number of energy attached to erika's exeggcute" in attack_text:
			score += g1_cpu_active.attached_energies.size() * 5.0 * 2.0
		# Full Speed Charge: heavy recoil risk
		if "number of tails to" in attack_text:
			score += 80.0
			if g1_cpu_active.current_hp <= 60:
				score -= 120.0
		# Healing Pollen (Venomoth): only good when the CPU has damaged Pokemon
		if "remove 1 damage counter from each of your pokémon" in attack_text:
			var g1_team_dmg = g1_cpu_active.get_max_hp() - g1_cpu_active.current_hp
			for bp in main.opponent_bench:
				g1_team_dmg += bp.get_max_hp() - bp.current_hp
			score += min(g1_team_dmg * 0.4, 90.0) if g1_team_dmg > 0 else -100.0
		# Fairy Power / Fidget: do nothing useful for the CPU — strongly avoid
		if "return any number of your pokémon in play" in attack_text:
			score -= 90.0
		if "fidget" in attack_name_lower:
			score -= 110.0
		# Card-advantage / search utility — modest value, prefer a real attack when one is available
		if "shuffle your hand into your deck" in attack_text:
			score += 25.0 if main.opponent_hand.size() <= 3 else 5.0
		if "search your deck for a basic energy card" in attack_text:
			score += 12.0
		if "any number of pokémon named" in attack_text:
			score += 18.0
		if "search your deck for that many basic energy" in attack_text:
			score += 15.0
		if "from your discard pile and attach" in attack_text and "lightning energy" in attack_text:
			score += 20.0
		if "basic pokémon with misty in its name" in attack_text or "basic pokémon card with brock in its name" in attack_text:
			score += 15.0 if main.opponent_bench.size() < 5 else -50.0
		# Focus Energy: only set up when not under pressure
		if "focus energy" in attack_name_lower:
			score += 10.0 if not cpu_will_be_koed else -60.0

		# ---- GYM2 (GYM CHALLENGE) ATTACK SCORING ----
		if main.opponent_active_pokemon.uid.begins_with("gym2-"):
			var g2c = main.opponent_active_pokemon
			# Earthdrill is unusable unless Lie Low was used last turn
			if attack_name_lower == "earthdrill" and g2c.gym2_lie_low_counter < 1:
				score -= 9999.0
			# Variable damage the estimator can't see
			if attack_name_lower == "roaring flames":
				var g2fire = 0
				for e in g2c.attached_energies:
					for pp in main.get_energy_provided_by_card(e):
						if pp == "Fire":
							g2fire += 1
				score += g2fire * 40.0
			if attack_name_lower == "thunder flare":
				score += g2c.get_damage_counters() * 20.0
			if attack_name_lower == "power ball":
				score += 30.0
			if attack_name_lower == "love lariat":
				score += 40.0
				for bp in main.opponent_bench:
					if bp.metadata.get("name", "") == "Giovanni's Nidoking":
						score += 60.0
			# Self-damage attacks: avoid when they would be suicide
			if attack_name_lower == "detonate" and g2c.current_hp <= 50:
				score -= 250.0
			if attack_name_lower == "risky attack" and g2c.current_hp <= 60:
				score -= 120.0
			if attack_name_lower == "electroburn":
				var g2l = 0
				for e in g2c.attached_energies:
					for pp in main.get_energy_provided_by_card(e):
						if pp == "Lightning":
							g2l += 1
				if g2c.current_hp <= g2l * 10:
					score -= 300.0
			# Disruption / setup utility
			if attack_name_lower == "dark wave":
				score += 30.0
			if attack_name_lower == "super removal":
				score += 25.0
			if attack_name_lower == "dragon tornado":
				score += main.player_bench.size() * 8.0
			if attack_name_lower == "intimidate":
				score += 40.0 if (main.player_active_pokemon != null and main.player_active_pokemon.get_max_hp() <= 50) else -60.0
			if attack_name_lower == "juxtapose":
				var g2self = g2c.get_max_hp() - g2c.current_hp
				var g2opp = main.player_active_pokemon.get_max_hp() - main.player_active_pokemon.current_hp
				score += float(g2self - g2opp) * 0.4
			if attack_name_lower == "giant growth" and not g2c.ditto_giant_growth:
				score += 20.0
			if attack_name_lower == "lie low":
				score += 70.0 if cpu_will_be_koed else 25.0
			# Attacks that do nothing useful for the CPU
			if attack_name_lower == "helping hand" or attack_name_lower == "psyscan":
				score -= 60.0
			if attack_name_lower == "group therapy":
				var g2heal = 0
				for bp in main.opponent_bench:
					if bp.get_damage_counters() > 0:
						g2heal += 1
				if g2c.get_damage_counters() > 0:
					g2heal += 1
				score += (g2heal * 15.0) if g2heal > 0 else -70.0

		# ---- SI1 (SOUTHERN ISLANDS) + BASEP (BASE SET PROMOS) ATTACK SCORING ----
		# SI1 attacks (all have 0 base damage in dispatch; score by utility)
		if attack_name_lower == "sharpshooter":
			score += 20.0 * min(1, main.player_bench.size())
		if attack_name_lower == "gentle song":
			var opp_e_count = main.player_active_pokemon.attached_energies.size() if main.player_active_pokemon != null else 0
			score += opp_e_count * 15.0
		if attack_name_lower == "revelation":
			score += 20.0 if main.opponent_hand.size() <= 3 else 5.0
		if attack_name_lower == "lick wounds":
			var own_dmg = main.opponent_active_pokemon.get_max_hp() - main.opponent_active_pokemon.current_hp
			score += min(own_dmg * 0.5, 50.0) if own_dmg > 0 else -80.0
		if attack_name_lower == "paradise pollen":
			score += 20.0 if (main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "") else -40.0
		if attack_name_lower == "rainbow wave":
			score += 20.0
		if attack_name_lower == "strange scent":
			score += 15.0 if (main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "") else -40.0
		if attack_name_lower == "tongue stretch":
			score += 15.0
		if attack_name_lower == "squirt":
			var own_dmg2 = main.opponent_active_pokemon.get_max_hp() - main.opponent_active_pokemon.current_hp
			score += min(own_dmg2 * 0.4, 40.0) if own_dmg2 > 0 else -80.0
		if attack_name_lower == "tentacle grip":
			score += 20.0
		# basep attacks (explicit scoring for attacks estimator can't fully score)
		if attack_name_lower == "sacred wing":
			score += 40.0  # expected average: 0.5×60 + 0.5×20 = 40
		if attack_name_lower == "miraculous comeback":
			var total_poke = (1 if main.opponent_active_pokemon != null else 0) + main.opponent_bench.size() \
				+ (1 if main.player_active_pokemon != null else 0) + main.player_bench.size()
			score += total_poke * 5.0
		if attack_name_lower == "pain split":
			score += main.opponent_active_pokemon.get_damage_counters() * 8.0
		if attack_name_lower == "seething anger":
			score += main.opponent_active_pokemon.get_damage_counters() * 5.0
		if attack_name_lower == "lightning rod":
			score += 10.0
		if attack_name_lower == "lightning bolt":
			var has_mark = false
			if main.player_active_pokemon != null and main.player_active_pokemon.lightning_rod_marked:
				has_mark = true
			if not has_mark:
				for bp in main.player_bench:
					if bp.lightning_rod_marked:
						has_mark = true
						break
			if has_mark:
				score += 20.0
		if attack_name_lower == "energy absorption":
			var discard_e = 0
			for c in main.opponent_discard_pile:
				if c.metadata.get("supertype", "") == "Energy":
					discard_e += 1
			score += min(discard_e * 15.0, 50.0)
		if attack_name_lower == "recharge":
			var has_lightning = false
			for e in main.opponent_active_pokemon.attached_energies:
				if "Lightning" in main.get_energy_provided_by_card(e):
					has_lightning = true
					break
			score += 25.0 if not has_lightning else 5.0
		if attack_name_lower == "let's play!":
			score += 20.0 if main.opponent_bench.size() < 5 else -50.0
		if attack_name_lower == "jump over":
			score += 10.0 * main.player_bench.size()
		if attack_name_lower == "energy control":
			var opp_e = main.player_active_pokemon.attached_energies.size() if main.player_active_pokemon != null else 0
			score += min(opp_e * 10.0, 40.0)
		if attack_name_lower == "devolution beam":
			var evolved_c = 0
			if main.player_active_pokemon != null and main.player_active_pokemon.attached_pre_evolutions.size() > 0:
				evolved_c += 1
			for bp in main.player_bench:
				if bp.attached_pre_evolutions.size() > 0:
					evolved_c += 1
			score += evolved_c * 15.0
		if attack_name_lower == "burning fire":
			var spare_fire = 0
			for e in main.opponent_active_pokemon.attached_energies:
				if "Fire" in main.get_energy_provided_by_card(e):
					spare_fire += 1
			score += min(spare_fire * 8.0, 40.0)
		if attack_name_lower == "protective flame":
			score += main.opponent_bench.size() * 10.0
		if attack_name_lower == "paint" or attack_name_lower == "texture magic":
			score += 15.0
		if attack_name_lower == "rapid spin":
			score += 15.0

		# ---- NEO1 (NEO GENESIS) ATTACK SCORING ----
		if attack_name_lower == "riptide":
			var water_count = 0
			for c in main.opponent_discard_pile:
				if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
					water_count += 1
			score += water_count * 8.0  # scale with water in discard
		if attack_name_lower == "flower dance":
			var bellosom_count = 0
			var all_field: Array = []
			if main.player_active_pokemon != null: all_field.append(main.player_active_pokemon)
			if main.opponent_active_pokemon != null: all_field.append(main.opponent_active_pokemon)
			all_field.append_array(main.player_bench + main.opponent_bench)
			for p in all_field:
				if "Bellossom" in p.metadata.get("name",""):
					bellosom_count += 1
			score += bellosom_count * 25.0  # 30 damage per bellossom
		if attack_name_lower == "zzzap":
			var power_count = 0
			var all_field2: Array = []
			if main.player_active_pokemon != null: all_field2.append(main.player_active_pokemon)
			all_field2.append_array(main.player_bench)
			for p in all_field2:
				for ab in p.metadata.get("abilities",[]):
					if ab.get("type","") in ["Pokémon Power","Pokemon Power","Poké-Power","Poke-Power"]:
						power_count += 1
						break
			score += power_count * 15.0  # 20 damage per powered pokemon
		if attack_name_lower == "earthquake":
			var bench_penalty = main.opponent_bench.size() * 10.0
			score -= bench_penalty  # penalize own bench damage
		if attack_name_lower == "flame wheel":
			var fire_count = 0
			for e in main.opponent_active_pokemon.attached_energies:
				if "Fire" in main.get_energy_provided_by_card(e):
					fire_count += 1
			if fire_count < 3:
				score -= 9999.0  # can't use without 3 fire
		if attack_name_lower == "elemental blast":
			var has_fire = false; var has_water = false; var has_lightning = false
			for e in main.opponent_active_pokemon.attached_energies:
				var prov = main.get_energy_provided_by_card(e)
				if "Fire" in prov: has_fire = true
				if "Water" in prov: has_water = true
				if "Lightning" in prov: has_lightning = true
			if not (has_fire and has_water and has_lightning):
				score -= 9999.0  # can't use without all three
		if attack_name_lower == "chomp":
			score += main.opponent_active_pokemon.get_damage_counters() * 5.0
		if attack_name_lower == "riptide" or attack_name_lower == "blizzard":
			if main.opponent_bench.size() > 0 and attack_name_lower == "blizzard":
				score -= main.opponent_bench.size() * 5.0  # mild penalty for own bench risk
		if attack_name_lower == "endure":
			score += 30.0 if cpu_will_be_koed else -50.0
		if attack_name_lower == "eeeeeeek":
			score += 20.0 if main.opponent_hand.size() <= 2 else -50.0
		if attack_name_lower == "squaredance" or attack_name_lower == "pilfer":
			score += 10.0
		if attack_name_lower == "super metronome":
			score += 40.0  # copying opponent attack can be very powerful
		if attack_name_lower == "screech":
			score += 15.0  # sets up future damage bonus
		if attack_name_lower == "zzzap":
			score -= 10.0 if main.opponent_bench.size() > 0 else 0.0  # penalize if own pokemon have powers too

		# ---- NEO2 (NEO DISCOVERY) ATTACK SCORING ----
		if attack_name_lower == "hydrocutter":
			var energy_count = min(3, main.opponent_active_pokemon.attached_energies.size())
			score += energy_count * 15.0  # more energy = more coin flips = more damage
		if attack_name_lower == "false swipe":
			var def_hp = main.player_active_pokemon.current_hp if main.player_active_pokemon else 0
			score += max(0, def_hp / 2.0)  # always useful; value = half current HP
		if attack_name_lower == "trample":
			var bench_count = main.player_bench.size() + main.opponent_bench.size()
			score += bench_count * 10.0  # more bench = more bonus damage
		if attack_name_lower == "crunch":
			score += 20.0  # future damage bonus is very useful
		if attack_name_lower == "sketch":
			var last = main.last_attack_on_opponent
			if not last.is_empty() and last.has("damage"):
				score += float(last["damage"]) * 0.8
		if attack_name_lower == "counter":
			score += 25.0 if cpu_will_be_koed else 10.0
		if attack_name_lower == "shockwave":
			var opp_pokemon_count = 1 + main.player_bench.size()
			score += opp_pokemon_count * 8.0  # 10 to each + force switch
		if attack_name_lower == "belly drum":
			score += 15.0 if main.opponent_active_pokemon.current_hp >= 40 else -9999.0  # needs HP to spare
		if attack_name_lower == "fury cutter":
			score += 25.0  # average expected ~30 damage
		if attack_name_lower == "burst":
			score -= main.opponent_bench.size() * 5.0  # penalize if own bench at risk
		if attack_name_lower == "electric bolt":
			if main.opponent_active_pokemon.lock_on_active:
				score += 40.0  # guaranteed hit
		if attack_name_lower == "spike barrage":
			var water_count = 0
			for e in main.opponent_active_pokemon.attached_energies:
				if "Water" in main.get_energy_provided_by_card(e):
					water_count += 1
			score += water_count * 15.0
		if attack_name_lower == "collect fire":
			var has_fire_discard = false
			for c in main.opponent_discard_pile:
				if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
					has_fire_discard = true
					break
			if not has_fire_discard: score -= 20.0
		if attack_name_lower == "dust devil":
			var non_fighting_count = 0
			for poke in [main.player_active_pokemon] + main.player_bench + main.opponent_bench:
				if poke != null and "Fighting" not in poke.metadata.get("types",["Colorless"]):
					non_fighting_count += 1
			score += non_fighting_count * 8.0
		if attack_name_lower == "triple poison":
			score += 30.0  # 30/turn is very powerful
		if attack_name_lower == "secrete poison":
			score += 20.0  # reactive counter is situationally good
		if attack_name_lower == "harden":
			score += 15.0  # defensive setup
		if attack_name_lower == "lock-on":
			score += 30.0 if not main.opponent_active_pokemon.lock_on_active else -50.0  # only once

		# ---- EX1 (RUBY & SAPPHIRE) ATTACK SCORING ----
		if attack_name_lower == "mega throw":
			if main.is_ex_pokemon(main.player_active_pokemon):
				score += 80.0  # +40 damage bonus is huge against a 2-prize target
		if attack_name_lower == "fire stream":
			var ex1_has_fire = false
			for e in main.opponent_active_pokemon.attached_energies:
				if "Fire" in main.get_energy_provided_by_card(e):
					ex1_has_fire = true
					break
			if ex1_has_fire and main.player_bench.size() > 0:
				score += 10.0 * main.player_bench.size()  # bonus bench spread, worth the energy discard
			else:
				score -= 15.0  # no bench to hit or no Fire Energy to discard
		if attack_name_lower == "water arrow" or attack_name_lower == "lava burn":
			var ex1_lowest_bench_hp = 9999
			for bp in main.player_bench:
				if bp.current_hp < ex1_lowest_bench_hp:
					ex1_lowest_bench_hp = bp.current_hp
			if main.player_bench.size() > 0 and ex1_lowest_bench_hp <= 20:
				score += 60.0  # can snipe a near-dead Benched Pokemon for a bonus KO
		if attack_name_lower == "critical move" or attack_name_lower == "fire spin":
			# Both disable the user's own next attack — only worth it if it KOs now
			if not cpu_will_be_koed and damage_range.get("max", 0) < player_hp:
				score -= 60.0  # locking out next turn isn't worth it unless this KOs
		if attack_name_lower == "shakedown" or attack_name_lower == "knock off":
			score += 20.0 if main.player_hand.size() > 3 else 5.0  # hand disruption worth more vs a full hand
		if attack_name_lower == "repulsion":
			score += 50.0 if main.player_bench.size() > 0 else -9999.0  # does nothing without opponent Bench

		# ---- EX2 (SANDSTORM) ATTACK SCORING ----
		var ex2_defender = main.player_active_pokemon
		var ex2_def_has_condition = ex2_defender != null and (ex2_defender.special_condition != "" or ex2_defender.is_poisoned or ex2_defender.is_burned)
		var ex2_def_evolved = ex2_defender != null and ex2_defender.attached_pre_evolutions.size() > 0
		var ex2_opp_has_evolved = false
		for _p in ([main.player_active_pokemon] if main.player_active_pokemon != null else []) + main.player_bench:
			if _p.attached_pre_evolutions.size() > 0:
				ex2_opp_has_evolved = true
				break
		if attack_name_lower == "extra poison" and ex2_defender != null and main.is_ex_pokemon(ex2_defender):
			score += 40.0  # Asleep + Poisoned on a 2-prize target
		if attack_name_lower == "target slash" and ex2_defender != null and ex2_defender.metadata.get("name","") == "Seviper":
			score += 30.0
		if attack_name_lower == "super slash" and ex2_def_evolved:
			score += 30.0
		if attack_name_lower == "pester" and ex2_def_has_condition:
			score += 20.0
		if attack_name_lower == "special blow" and ex2_defender != null:
			for e in ex2_defender.attached_energies:
				if "Special" in e.metadata.get("subtypes", []):
					score += 40.0
					break
		if (attack_name_lower == "dark mind" or attack_name_lower == "thunder spear"):
			var ex2_low_bench = 9999
			for bp in main.player_bench:
				if bp.current_hp < ex2_low_bench:
					ex2_low_bench = bp.current_hp
			if main.player_bench.size() > 0 and ex2_low_bench <= 20:
				score += 40.0  # snipe a near-dead Benched Pokemon
		if attack_name_lower in ["cosmic draw", "pull down", "time spiral"]:
			score += 25.0 if ex2_opp_has_evolved else -20.0  # do nothing / little without opponent Evolved
		if attack_name_lower == "feedback" and ex2_defender != null:
			score += 5.0 * main.player_hand.size()  # scales with opponent's hand size
		if attack_name_lower == "lazy punch":
			score -= 40.0  # locks the user's own next turn for no immediate payoff
		if attack_name_lower == "super deep dive" and main.opponent_bench.size() == 0:
			score -= 9999.0  # does nothing without a Bench to switch to

		# ---- GENERAL EFFECT SCORING ----
		var effect_score = score_parsed_effects(parsed_effects, main.player_active_pokemon)
		score += effect_score

		if score > best_attack_score:
			best_attack_score = score
			best_attack_index = i

	if best_attack_index == -1:
		print("CPU found no suitable attack")
		return

	# Execute the chosen attack
	var chosen_attack = attacks[best_attack_index]
	var chosen_name = chosen_attack.get("name", "")
	var chosen_text = chosen_attack.get("text", "").to_lower()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_attack_sound)
	await main.show_message("Opponent's " + main.opponent_active_pokemon.metadata["name"].to_upper() + " used " + chosen_name.to_upper() + "!")
	if main._should_bail(): return

	# Baby Pokemon rule: CPU must flip before attacking a Baby Pokemon (tails = CPU turn ends)
	if await main.attack_effects.check_baby_rule(main.player_active_pokemon, true):
		return

	# SCARE (neo4-5 Dark Feraligatr): player's active Dark Feraligatr blocks CPU Baby from attacking
	if "Baby" in main.opponent_active_pokemon.metadata.get("subtypes", []) and main.powers_and_bodies.is_scare_active(true):
		await main.show_message("SCARE! DARK FERALIGATR PREVENTS BABY POKÉMON FROM ATTACKING!")
		if main._should_bail(): return
		return

	# GYM2 Misty's Gyarados Rebellion — flip 2; both tails cancels the attack and shuffles Gyarados into deck
	if await main.powers_and_bodies.check_rebellion(main.opponent_active_pokemon, true):
		main.opponent_attacked_this_turn = true
		return

	# EX12 Pattern Distraction (Spinda ex12-26): if the opposing Active Spinda has this Body and the CPU's
	# attacker is a Basic Pokemon, flip a coin; tails cancels the attack.
	if await main.powers_and_bodies.check_ex12_pattern_distraction(main.opponent_active_pokemon, true):
		main.opponent_attacked_this_turn = true
		return

	# GYM1-120 Vermilion City Gym pre-attack flip (CPU side). Optional flip for Lt. Surge attacker.
	await main.maybe_vermilion_lt_surge_flip(main.opponent_active_pokemon, true)
	if main._should_bail(): return


	# GYM2 pre-processing: attack-dict modifications before dispatch
	if main.opponent_active_pokemon.uid.begins_with("gym2-"):
		if main.opponent_active_pokemon.ditto_giant_growth and chosen_name.to_lower() == "pound":
			chosen_attack = chosen_attack.duplicate()
			chosen_attack["damage"] = "30"
		if main.opponent_active_pokemon.gym2_focus_energy_active and chosen_name.to_lower() == "quick attack":
			chosen_attack = chosen_attack.duplicate()
			chosen_attack["damage"] = str(main.attack_effects.parse_attack_base_damage(chosen_attack) * 2) + "+"
			main.opponent_active_pokemon.gym2_focus_energy_active = false

	# Unified dispatch: handles GYM2, GYM1, Base1-5, and generic special attacks.
	# MATCH EFFECT: raw_damage_only — skip special dispatch so the attack falls through
	# to the generic printed-damage path with no card-text effects.
	if not main.match_effects.raw_damage_only(true):
		if await main.attack_effects.dispatch_attack(chosen_attack, main.opponent_active_pokemon, main.player_active_pokemon, true):
			return

	# Check attack_blocked flag (Tail Wag / Leer) - benching either pokemon ends this
	if main.opponent_active_pokemon.attack_blocked_next_turn:
		if main.player_active_pokemon != null and main.player_active_pokemon.get_instance_id() == main.opponent_active_pokemon.attack_blocked_by_id:
			await main.show_message(main.opponent_active_pokemon.metadata["name"].to_upper() + " CAN'T ATTACK!")
			if main._should_bail(): return
			main.opponent_active_pokemon.attack_blocked_next_turn = false
			main.opponent_active_pokemon.attack_blocked_by_id = -1
			main.display_active_pokemon_energies(true)
			return
		else:
			# Benching broke the effect
			main.opponent_active_pokemon.attack_blocked_next_turn = false
			main.opponent_active_pokemon.attack_blocked_by_id = -1

	# Coin-flip attack block (Sand-attack / Smokescreen): flip — tails = CPU can't attack
	if main.opponent_active_pokemon.attack_flip_blocked:
		main.opponent_active_pokemon.attack_flip_blocked = false
		var flip = await main.flip_coin(false, true)
		if not flip:
			await main.show_message("Opponent's " + main.opponent_active_pokemon.metadata.get("name", "").to_upper() + " CAN'T ATTACK! (SAND-ATTACK)")
			if main._should_bail(): return
			return
		await main.show_message("Heads! Opponent's " + main.opponent_active_pokemon.metadata.get("name", "").to_upper() + " CAN ATTACK!")
		if main._should_bail(): return

	# Swords Dance: boost Slash damage (base Scyther = 60, ex8 Ninjask = 80)
	if main.opponent_active_pokemon.swords_dance_active and chosen_name.to_lower() == "slash":
		var sd_dmg = main.opponent_active_pokemon.swords_dance_slash_damage if main.opponent_active_pokemon.swords_dance_slash_damage > 0 else 60
		chosen_attack = chosen_attack.duplicate()
		chosen_attack["damage"] = str(sd_dmg)
		main.opponent_active_pokemon.swords_dance_active = false
		main.opponent_active_pokemon.swords_dance_slash_damage = 0
		await main.show_message("SWORDS DANCE BOOST! SLASH DOES " + str(sd_dmg) + " DAMAGE!")
		if main._should_bail(): return

	# GYM1 Focus Energy (Gnaw) / ECARD3 Focus Energy (Mega Punch): if active, double base damage
	if main.opponent_active_pokemon.focus_energy_active and chosen_name.to_lower() in ["gnaw", "mega punch"]:
		chosen_attack = chosen_attack.duplicate()
		var cpu_doubled = main.attack_effects.parse_attack_base_damage(chosen_attack) * 2
		chosen_attack["damage"] = str(cpu_doubled)
		main.opponent_active_pokemon.focus_energy_active = false
		await main.show_message("FOCUS ENERGY! " + chosen_name.to_upper() + " DOES " + str(cpu_doubled) + " DAMAGE!")
		if main._should_bail(): return
	
	if await main.attack_effects.handle_attack_confusion(main.opponent_active_pokemon, true):
		main.display_active_pokemon_energies(true)
		return
	
	if await main.attack_effects.handle_attack_blind(main.opponent_active_pokemon, true):
		main.display_active_pokemon_energies(true)
		return
	
	# Resolve variable damage with coin flips
	# MATCH EFFECT: raw_damage_only — flatten "20x"/"10+" to the printed number, no flips
	var variable_result
	if main.match_effects.raw_damage_only(true):
		variable_result = {"damage": main.attack_effects.parse_attack_base_damage(chosen_attack), "flip_result": "", "attack_failed": false, "messages": []}
	else:
		variable_result = await main.attack_effects.resolve_attack_variable_damage(chosen_attack, main.opponent_active_pokemon, main.player_active_pokemon, true)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await main.show_message(msg)
			if main._should_bail(): return
		var _cpu_pae1 = main.attack_effects.parse_card_text_effects(chosen_attack.get("text", ""), main.opponent_active_pokemon.metadata.get("name", ""))
		if _cpu_pae1.size() > 0:
			await main.attack_effects.apply_card_text_effects(_cpu_pae1, main.opponent_active_pokemon, main.player_active_pokemon, true, flip_result)
		if main._should_bail(): return
		main.display_active_pokemon_energies(true)
		return
	
	for msg in variable_result["messages"]:
		await main.show_message(msg)
		if main._should_bail(): return
	
	var result = main.calculate_final_damage(resolved_base, cpu_types, main.player_active_pokemon, main.opponent_active_pokemon)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(main.player_active_pokemon, false):
		main.display_active_pokemon_energies(true)
		return

	final_damage = main.apply_defender_no_damage_shield(main.player_active_pokemon, final_damage, false)

	await main.display_and_apply_attack_damage(main.opponent_active_pokemon, main.player_active_pokemon, final_damage, result["modifiers"], true, resolved_base)
	if main._should_bail(): return
	
	# Store last attack for Mirror Move tracking
	main.last_attack_on_player = {"damage": final_damage, "attack": chosen_attack, "attacker_types": cpu_types}
	main.opponent_attacked_this_turn = true
	
	# MATCH EFFECT: raw_damage_only — card-text effects are skipped entirely
	var _cpu_pae2 = [] if main.match_effects.raw_damage_only(true) else main.attack_effects.parse_card_text_effects(chosen_attack.get("text", ""), main.opponent_active_pokemon.metadata.get("name", ""))

	# Clear one-shot attack boosts after any attack completes
	main.opponent_active_pokemon.clear_attack_boost_flags()
	if _cpu_pae2.size() > 0:
		await main.attack_effects.apply_card_text_effects(_cpu_pae2, main.opponent_active_pokemon, main.player_active_pokemon, true, flip_result)
	if main._should_bail(): return

	await main.check_all_knockouts()
	if main._should_bail(): return
	main.display_active_pokemon_energies(true)

# CPU evaluates and plays basic pokemon from hand onto bench using threshold scoring
func get_minimum_cost_attack(pokemon_card: card_object) -> Dictionary:
	if not pokemon_card.metadata.has("attacks") or pokemon_card.metadata["attacks"].size() == 0:
		return {}
	
	var min_cost_attack = null
	var min_cost = 999
	
	for attack in pokemon_card.metadata["attacks"]:
		var cost = int(attack.get("convertedEnergyCost", 999))
		if cost < min_cost:
			min_cost = cost
			min_cost_attack = attack
	
	if min_cost_attack == null:
		return {}
	
	return {
		"cost": min_cost,
		"damage": main.attack_effects.parse_attack_base_damage(min_cost_attack),
		"attack_name": min_cost_attack.get("name", ""),
		"text": min_cost_attack.get("text", "")
	}
	
# Helper function to get the highest damage attack and return all its data
func get_maximum_damage_attack(pokemon_card: card_object) -> Dictionary:
	if not pokemon_card.metadata.has("attacks") or pokemon_card.metadata["attacks"].size() == 0:
		return {}
	
	var max_damage = 0
	var max_damage_attack = null
	
	for attack in pokemon_card.metadata["attacks"]:
		var damage = main.attack_effects.parse_attack_base_damage(attack)
		if damage > max_damage:
			max_damage = damage
			max_damage_attack = attack
	
	if max_damage_attack == null:
		return {}
	
	return {
		"damage": max_damage,
		"cost": int(max_damage_attack.get("convertedEnergyCost", 1)),
		"text": max_damage_attack.get("text", ""),
		"attack_name": max_damage_attack.get("name", "")
	}

# Main function to evaluate a basic pokemon and return a score by calling criterion 1-5 and returns the total score with breakdown reasoning
func cpu_phase_bench_play() -> void:
	var bench_thresholds = {0: -999, 1: 100, 2: 200, 3: 350, 4: 500}

	while main.opponent_bench.size() < 5:
		var current_bench_count = main.opponent_bench.size()
		var score_threshold = bench_thresholds.get(current_bench_count, 9999)

		# Score all basic pokemon in hand using existing priority criteria
		var best_card: card_object = null
		var best_score: float = -999.0
		for card in main.opponent_hand:
			if not main.is_basic_pokemon(card):
				continue
			var result = evaluate_opponents_start_setup_pokemon_choices(card, main.opponent_hand)
			var score = result.get("total_score", 0)
			if score > best_score:
				best_score = score
				best_card = card

		# Stop if no basic pokemon in hand or best doesn't meet threshold
		if best_card == null or best_score <= score_threshold:
			break

		# Play the pokemon onto the bench
		main.opponent_hand.erase(best_card)
		best_card.current_location = "bench"
		best_card.placed_on_field_this_turn = true
		main.opponent_bench.append(best_card)

		print("CPU played " + best_card.metadata["name"] + " to bench (Score: " + str(int(best_score)) + ", Threshold: " + str(score_threshold) + ")")

		await main.show_message("Opponent placed " + best_card.metadata["name"].to_upper() + " on the bench!")
		if main._should_bail(): return
		var card_texture = main.get_card_texture(best_card)
		await main.animate_card_a_to_b(main.opponent_hand_container, main.opponent_bench_container, 0.3, card_texture, main.card_scales[11])
		if main._should_bail(): return
		main.display_pokemon(true)
		main.refresh_hand_display(true)

		# GYM2-119 Rocket's Minefield Gym — coin flip per benched Basic from hand; tails = 20 damage
		await main.trainer_effects.gym2_minefield_gym_trigger(best_card, true)
		if main._should_bail(): return

		# GYM2 Giovanni's Persian Call the Boss — search deck for a Giovanni trainer
		await main.powers_and_bodies.trigger_call_the_boss(best_card, true)
		if main._should_bail(): return
		# NEO2 [Engage]/[Increase] (Unown [E]/[I]): on-play triggers
		if "[Engage]" in str(best_card.metadata.get("abilities",[])):
			await main.powers_and_bodies.trigger_neo2_unown_engage(best_card, true)
			if main._should_bail(): return
		elif "[Increase]" in str(best_card.metadata.get("abilities",[])):
			await main.powers_and_bodies.trigger_neo2_unown_increase(best_card, true)
			if main._should_bail(): return
		# EX4-83 Team Magma Hideout: playing a non-Team-Magma Basic from hand adds 1 damage counter
		await main.trainer_effects.ex4_team_magma_hideout_trigger(best_card, true)
		if main._should_bail(): return
		# EX8 Dragon Boost (Rayquaza ex ex8-102): move any number of basic Energy to Rayquaza ex
		await main.powers_and_bodies.trigger_ex8_dragon_boost(best_card, true)
		if main._should_bail(): return
		# EX12 Support Navigation (Lapras ex12-8): on benching from hand, search deck for a Supporter → hand.
		if best_card.has_ability("Support Navigation"):
			await main.powers_and_bodies.trigger_ex12_support_navigation(best_card, true)
			if main._should_bail(): return

# R.5: Selects the best bench replacement and performs the retreat
func cpu_phase_evolution() -> void:
	if main.turn_number <= 2:
		return
	
	# Check Aerodactyl's Prehistoric Power
	if main.powers_and_bodies.is_prehistoric_power_active():
		print("CPU: Evolution blocked by Prehistoric Power")
		return

	while true:
		# Build list of all valid (evo_card, target) pairs and score them
		var scored_pairs = []
		for card in main.opponent_hand:
			var valid_targets = main.get_valid_evolution_targets(card, true)
			for target in valid_targets:
				var result = evaluate_evolution_pair(card, target)
				scored_pairs.append(result)

		if scored_pairs.is_empty():
			break

		# Sort by score descending and pick the best pair
		scored_pairs.sort_custom(func(a, b): return a["score"] > b["score"])
		var best = scored_pairs[0]

		print("CPU evolving " + best["target"].metadata["name"] + " into " + best["evo_card"].metadata["name"] + " (Score: " + str(int(best["score"])) + ")")
		for reason in best["reasons"]:
			print("  - " + reason)

		# Set the globals that perform_evolution reads from
		main.evolution_card_awaiting_target = best["evo_card"]
		main.selected_card_for_action = best["target"]
		await main.perform_evolution(true)
		if main._should_bail(): return

		await main.show_message("Opponent evolved " + best["target"].metadata["name"].to_upper() + " into " + best["evo_card"].metadata["name"].to_upper() + "!")
		if main._should_bail(): return
	
		var evo_target_node = main.opponent_active_container if best["evo_card"].current_location == "active" else main.opponent_bench_container
		var evo_scale = main.card_scales[8] if best["evo_card"].current_location == "active" else main.card_scales[11]
		var evo_texture = main.get_card_texture(best["evo_card"])
		await main.animate_card_a_to_b(main.opponent_hand_container, evo_target_node, 0.3, evo_texture, evo_scale)
		if main._should_bail(): return

		main.display_pokemon(true)
		main.display_active_pokemon_energies(true)
		main.refresh_hand_display(true)
		
		# Fix 2: Invalidate CPU evaluation cache after evolution changes board
		invalidate_cpu_evaluation()

		await get_tree().process_frame
		if main._should_bail(): return
	
		await main.play_evolution_effect(best["evo_card"])
		if main._should_bail(): return

		# Clean up globals
		main.evolution_card_awaiting_target = null
		main.selected_card_for_action = null

# R.1: Determines if there is a reason for the active to consider retreating
func cpu_score_trainer_card(card: card_object) -> float:
	var card_id = card.uid.to_lower()

	# EX1+ one-Supporter-per-turn rule: if the CPU has already played a Supporter this turn, a
	# second one is unplayable — score it far below the play threshold so the CPU keeps evaluating
	# its OTHER trainers instead of locking onto an unplayable Supporter and stopping.
	if "Supporter" in card.metadata.get("subtypes", []) and main.trainer_effects.opponent_played_supporter_this_turn:
		return -100.0

	match card_id:
		"base1-91": return 100.0 # Bill: always play
		"base1-88": return _cpu_score_professor_oak(card)
		"base1-71": return _cpu_score_computer_search(card)
		"base1-72": return _cpu_score_devolution_spray()
		"base1-73": return _cpu_score_impostor_prof_oak()
		"base1-74": return _cpu_score_item_finder()
		"base1-75": return _cpu_score_lass()
		"base1-76": return _cpu_score_pokemon_breeder()
		"base1-77": return _cpu_score_pokemon_trader()
		"base1-78": return _cpu_score_scoop_up()
		"base1-79": return _cpu_score_super_energy_removal()
		"base1-80": return _cpu_score_defender()
		"base1-81": return _cpu_score_energy_retrieval()
		"base1-82": return _cpu_score_full_heal()
		"base1-83": return _cpu_score_maintenance()
		"base1-84": return _cpu_score_pluspower()
		"base1-85": return _cpu_score_pokemon_center()
		"base1-86": return -100.0 # Pokemon Flute: CPU never plays
		"base1-87": return 60.0 # Pokedex
		"base1-89": return _cpu_score_revive()
		"base1-90": return _cpu_score_super_potion()
		"base1-92": return _cpu_score_energy_removal()
		"base1-93": return _cpu_score_gust_of_wind()
		"base1-94": return _cpu_score_potion()
		"base1-95": return _cpu_score_switch()
		"base1-70": return _cpu_score_clefairy_doll()
		"base3-58": return _cpu_score_mr_fuji()
		"base3-59": return 70.0  # Energy Search: almost always useful
		"base3-60": return _cpu_score_gambler()
		"base3-61": return 30.0  # Recycle: low priority, coin flip dependent
		"base3-62": return _cpu_score_clefairy_doll()  # Mysterious Fossil: same as bench tokens
		"base2-64": return _cpu_score_poke_ball()  # Poké Ball
		"base5-15", "base5-71": return 80.0  # Here Comes Team Rocket: always decent (info advantage)
		"base5-16", "base5-72": return _cpu_score_rockets_sneak_attack()
		"base5-73": return _cpu_score_the_bosss_way()
		"base5-74": return _cpu_score_challenge()
		"base5-75": return 20.0  # Digger: coin-flip dependent, low value
		"base5-76": return _cpu_score_imposter_oaks_revenge()
		"base5-77": return _cpu_score_nightly_garbage_run()
		"base5-78": return _cpu_score_goop_gas_attack()
		"base5-79": return _cpu_score_sleep_trainer()
		# ============================ GYM1 (GYM HEROES) CPU SCORING ============================
		"gym1-15", "gym1-98": return _cpu_score_gym1_brock()
		"gym1-16", "gym1-100": return _cpu_score_gym1_erika()
		"gym1-17", "gym1-101": return _cpu_score_gym1_lt_surge()
		"gym1-18", "gym1-102": return _cpu_score_gym1_misty()
		"gym1-19": return _cpu_score_gym1_rockets_trap()
		"gym1-97": return _cpu_score_gym1_blaines_quiz()
		"gym1-99": return _cpu_score_gym1_charity()
		"gym1-105": return _cpu_score_gym1_blaines_last_resort(card)
		"gym1-106": return _cpu_score_gym1_brocks_training_method()
		"gym1-109": return _cpu_score_gym1_erikas_maids()
		"gym1-110": return _cpu_score_gym1_erikas_perfume()
		"gym1-111": return _cpu_score_gym1_good_manners(card)
		"gym1-112": return _cpu_score_gym1_lt_surges_treaty()
		"gym1-113": return _cpu_score_gym1_minion()
		"gym1-114": return _cpu_score_gym1_mistys_wrath()
		"gym1-116": return _cpu_score_gym1_recall()
		"gym1-117": return _cpu_score_gym1_sabrinas_esp()
		"gym1-118": return _cpu_score_gym1_secret_mission()
		"gym1-119": return _cpu_score_gym1_tickling_machine()
		"gym1-121": return _cpu_score_gym1_blaines_gamble()
		"gym1-122": return _cpu_score_gym1_energy_flow()
		"gym1-123": return _cpu_score_gym1_mistys_duel()
		"gym1-125": return _cpu_score_gym1_sabrinas_gaze()
		"gym1-126": return _cpu_score_gym1_trash_exchange()
		# ============================ GYM1 (GYM HEROES) STADIUM SCORING ============================
		"gym1-103": return _cpu_score_gym1_no_removal_gym()
		"gym1-104": return _cpu_score_gym1_rockets_training_gym()
		"gym1-107": return _cpu_score_gym1_celadon_city_gym()
		"gym1-108": return _cpu_score_gym1_cerulean_city_gym()
		"gym1-115": return _cpu_score_gym1_pewter_city_gym()
		"gym1-120": return _cpu_score_gym1_vermilion_city_gym()
		"gym1-124": return _cpu_score_gym1_narrow_gym()
		# ============================ GYM2 (GYM CHALLENGE) CPU SCORING ============================
		"gym2-17", "gym2-100": return _cpu_score_gym2_blaine(card)
		"gym2-18", "gym2-104": return _cpu_score_gym2_giovanni()
		"gym2-19", "gym2-106": return _cpu_score_gym2_koga()
		"gym2-20", "gym2-110": return _cpu_score_gym2_sabrina()
		"gym2-101": return _cpu_score_gym2_brocks_protection()
		"gym2-103": return _cpu_score_gym2_erikas_kindness()
		"gym2-105": return _cpu_score_gym2_giovannis_last_resort()
		"gym2-107": return -100.0  # Lt. Surge's Secret Plan: simplified version, CPU skips
		"gym2-108": return _cpu_score_gym2_mistys_wish()
		"gym2-111": return _cpu_score_gym2_blaines_quiz_2()
		"gym2-112": return _cpu_score_gym2_blaines_quiz_3()
		"gym2-115": return _cpu_score_gym2_koga_ninja_trick()
		"gym2-116": return _cpu_score_gym2_master_ball()
		"gym2-117": return _cpu_score_gym2_max_revive(card)
		"gym2-118": return _cpu_score_gym2_mistys_tears(card)
		"gym2-120": return _cpu_score_gym2_rockets_secret_experiment()
		"gym2-121": return _cpu_score_gym2_sabrinas_psychic_control()
		"gym2-124": return _cpu_score_gym2_fervor()
		"gym2-125": return _cpu_score_gym2_transparent_walls()
		"gym2-126": return _cpu_score_gym2_warp_point()
		# ============================ GYM2 (GYM CHALLENGE) STADIUM SCORING ============================
		"gym2-102": return _cpu_score_gym2_chaos_gym()
		"gym2-109": return _cpu_score_gym2_resistance_gym()
		"gym2-113": return _cpu_score_gym2_cinnabar_city_gym()
		"gym2-114": return _cpu_score_gym2_fuchsia_city_gym()
		"gym2-119": return _cpu_score_gym2_rockets_minefield_gym()
		"gym2-122": return _cpu_score_gym2_saffron_city_gym()
		"gym2-123": return _cpu_score_gym2_viridian_city_gym()
		# ============================ NEO1 (NEO GENESIS) TRAINER SCORING ============================
		"neo1-83": return 40.0   # Arcade Game: coin flip game corner, decent
		"neo1-85": return _cpu_score_neo1_energy_charge()
		"neo1-86": return _cpu_score_neo1_focus_band()
		"neo1-87": return _cpu_score_neo1_mary()
		"neo1-88": return 60.0   # PokéGear: look at top 7 for trainers, good
		"neo1-89": return _cpu_score_neo1_super_energy_retrieval()
		"neo1-90": return 50.0   # Time Capsule: recover cards, moderate
		"neo1-91": return 60.0   # Bill's Teleporter: heads draw 4
		"neo1-92": return 30.0   # Card-Flip Game: draw 2 if correct
		"neo1-93": return _cpu_score_neo1_gold_berry()
		"neo1-94": return _cpu_score_neo1_miracle_berry()
		"neo1-95": return 55.0   # New Pokédex: see top 5, rearrange
		"neo1-96": return _cpu_score_neo1_professor_elm()
		"neo1-97": return 60.0   # Sprout Tower stadium: useful defensive
		"neo1-98": return _cpu_score_neo1_super_scoop_up()
		"neo1-99": return _cpu_score_neo1_berry()
		"neo1-100": return _cpu_score_neo1_double_gust()
		"neo1-101": return _cpu_score_neo1_moo_moo_milk()
		"neo1-102": return 40.0  # Pokemon March: bench search
		"neo1-103": return _cpu_score_neo1_super_rod()
		# neo1-84 Ecogym and neo1-97 Sprout Tower handled by stadiums (scored above)
		"neo1-84": return 50.0   # Ecogym stadium: protect non-colorless energy
		# ---- NEO2 (NEO DISCOVERY) TRAINER SCORING ----
		"neo2-72": return _cpu_score_neo2_fossil_egg()
		"neo2-73": return _cpu_score_neo2_hyper_devolution_spray()
		"neo2-74": return _cpu_score_neo2_ruin_wall()
		"neo2-75": return 40.0  # Energy Ark: 2 coin flips for basic energy
		# ---- ECARD1 (EXPEDITION) TRAINER SCORING ----
		"ecard1-137": return _cpu_score_maintenance() # Bill's Maintenance: shuffle-1/draw-3, same family as Maintenance
		"ecard1-138": return 55.0  # Copycat: value depends on opponent's hand size, moderate default
		"ecard1-139": return _cpu_score_poke_ball()  # Dual Ball
		"ecard1-140": return _cpu_score_energy_removal()  # Energy Removal 2
		"ecard1-141": return 45.0  # Energy Restore: coin-flip dependent basic energy recovery
		"ecard1-142": return 55.0  # Mary's Impulse: variable draw, decent default
		"ecard1-143": return _cpu_score_poke_ball()  # Master Ball
		"ecard1-144": return 35.0  # Multi Technical Machine 01: situational, one-turn attack swap
		"ecard1-145": return _cpu_score_pokemon_center()  # Pokemon Nurse
		"ecard1-146": return _cpu_score_gust_of_wind()  # Pokemon Reversal
		"ecard1-147": return 40.0  # Power Charge: coin-flip energy recycling
		"ecard1-148": return _cpu_score_neo1_professor_elm()  # Professor Elm's Training Method
		"ecard1-149": return _cpu_score_professor_oak(card)  # Professor Oak's Research
		"ecard1-150": return 35.0  # Strength Charm: modest one-off damage boost
		"ecard1-151": return _cpu_score_neo1_super_scoop_up()  # Super Scoop Up
		"ecard1-152": return _cpu_score_gust_of_wind()  # Warp Point
		"ecard1-153": return 70.0  # Energy Search
		"ecard1-154": return _cpu_score_full_heal()
		"ecard1-155": return _cpu_score_neo1_moo_moo_milk()  # Moo-Moo Milk
		"ecard1-156": return _cpu_score_potion()
		"ecard1-157": return _cpu_score_switch()
		# ---- ECARD2 (AQUAPOLIS) TRAINER SCORING ----
		"ecard2-119", "ecard2-121", "ecard2-122", "ecard2-124", "ecard2-127", "ecard2-129", "ecard2-132", "ecard2-140":
			return 30.0  # Type Cubes: situational, one-turn attack swap onto a type-matching Pokemon
		"ecard2-120": return 45.0  # Energy Switch: modest utility, energy redistribution
		"ecard2-123": return 65.0  # Forest Guardian: card selection with deck reshuffle, solid value
		"ecard2-125": return 35.0  # Healing Berry: passive safety net, low upfront value
		"ecard2-126": return 60.0  # Juggler: draw power at the cost of energy, good if energy-flooded
		"ecard2-128": return 40.0  # Memory Berry: situational extra attack access
		"ecard2-130": return 70.0  # Pokemon Fan Club: free bench development, high value early
		"ecard2-131": return 50.0  # Pokemon Park (Stadium): passive bench-healing utility
		"ecard2-133": return 55.0  # Seer: conditional basic energy fetch
		"ecard2-134": return _cpu_score_energy_removal()  # Super Energy Removal 2: same family as Energy Removal
		"ecard2-135": return 35.0  # Time Shard: reactive, situational energy recovery
		"ecard2-136": return 25.0  # Town Volunteers: defensive deck-thinning-protection, low proactive value
		"ecard2-137": return 30.0  # Traveling Salesman: only useful with TM/Tool cards in deck
		"ecard2-118": return 55.0  # Apricorn Forest (Stadium): free bench development over time
		"ecard2-138": return 20.0  # Undersea Ruins (Stadium): situational, usually self-harming
		"ecard2-139": return 40.0  # Power Plant (Stadium): energy type flexibility
		"ecard2-141": return 40.0  # Weakness Guard: situational defensive utility
		# ---- ECARD3 (SKYRIDGE) TRAINER SCORING ----
		"ecard3-119": return 45.0  # Ancient Ruins (Stadium): passive card-advantage safety net
		"ecard3-120": return 55.0  # Relic Hunter: search for Supporter/Stadium, good consistency tool
		"ecard3-121": return 40.0  # Apricorn Maker: only useful with Ball cards in deck
		"ecard3-123": return 50.0  # Desert Shaman: symmetric hand refresh, situational
		"ecard3-124": return _cpu_score_poke_ball()  # Fast Ball
		"ecard3-125": return 45.0  # Fisherman: energy recovery, useful mid-late game
		"ecard3-126": return _cpu_score_poke_ball()  # Friend Ball
		"ecard3-127": return _cpu_score_potion()  # Hyper Potion
		"ecard3-128": return 35.0  # Lure Ball: coin-flip dependent Evolution recovery
		"ecard3-132": return 15.0  # Mirage Stadium (Stadium): hurts both sides' retreat equally, low proactive value
		"ecard3-137": return 40.0  # Mystery Zone (Stadium): situational Evolution-for-Energy trade
		"ecard3-138": return 55.0  # Oracle: deck manipulation, solid consistency
		"ecard3-140": return 50.0  # Underground Expedition: bottom-of-deck card advantage
		"ecard3-141": return 45.0  # Underground Lake (Stadium): free bench Pokemon if Omanyte/Kabuto in discard
		"ecard3-122": return 40.0  # Crystal Shard (Tool): type-override utility, discards itself after attacking
		"ecard3-139": return 35.0  # Star Piece (Tool): situational bench-evolve trigger
		"ecard3-129", "ecard3-130", "ecard3-131", "ecard3-133", "ecard3-134", "ecard3-135", "ecard3-136":
			return 30.0  # Miracle Sphere/Mystery Plate (Technical Machines): situational, energy-combo/prize-count gated
		# ---- EX1 (RUBY & SAPPHIRE) TRAINER SCORING ----
		"ex1-80": return _cpu_score_energy_removal()  # Energy Removal 2
		"ex1-81": return 40.0  # Energy Restore: modest energy recovery
		"ex1-82": return 30.0  # Energy Switch: situational energy redistribution
		"ex1-83": return 55.0  # Lady Outing (Supporter): flexible multi-type Energy search
		"ex1-84": return 40.0  # Lum Berry (Tool): passive Special Condition safety net
		"ex1-85": return 45.0  # Oran Berry (Tool): passive healing safety net
		"ex1-86": return _cpu_score_poke_ball()  # Poke Ball
		"ex1-87": return 35.0  # Pokemon Reversal: coin-flip-dependent disruption
		"ex1-88": return 50.0  # PokeNav: guaranteed card selection from top 3
		"ex1-89": return 65.0  # Professor Birch (Supporter): strong hand refill, best early/when low on cards
		"ex1-90": return 30.0  # Energy Search: reliable but low-impact
		"ex1-91": return _cpu_score_potion()  # Potion
		"ex1-92": return _cpu_score_switch()  # Switch
		# ---- EX2 (SANDSTORM) TRAINER SCORING ----
		"ex2-86": return _cpu_score_full_heal()  # Double Full Heal: same value as Full Heal
		"ex2-87": return 55.0  # Lanette's Net Search (Supporter): flexible multi-type Basic search
		"ex2-88": return _cpu_score_ex2_rare_candy()  # Rare Candy: only if a valid evolution jump exists
		"ex2-89": return _cpu_score_ex2_wallys_training()  # Wally's Training (Supporter): only if Active can evolve
		"ex2-90", "ex2-91", "ex2-92": return _cpu_score_clefairy_doll()  # Fossils: same as bench tokens
		# ============================ EX3 (EX DRAGON) CPU SCORING =============================
		"ex3-82": return 35.0  # Balloon Berry (Tool): free-retreat safety net
		"ex3-83": return 45.0  # Buffer Piece (Tool): -20 damage for a turn cycle
		"ex3-84": return 40.0  # Energy Recycle System (Item): basic Energy recovery
		"ex3-87": return _cpu_score_ex3_mr_brineys_compassion()  # only worth it to save a damaged Pokemon
		"ex3-88": return 60.0  # TV Reporter (Supporter): net +2 cards
		# ── EX4 (Team Magma vs Team Aqua) ──
		"ex4-69": return 55.0  # Team Aqua Schemer (Supporter): discard 1 Pokemon, draw 3-4
		"ex4-70": return 55.0  # Team Magma Schemer (Supporter): discard 1 Pokemon, draw 3-4
		"ex4-71": return 50.0  # Archie (Supporter): fetch a Team Aqua Pokemon to the Bench
		"ex4-72": return 45.0  # Dual Ball (Item): coin-flip Basic search
		"ex4-73": return 50.0  # Maxie (Supporter): fetch a Team Magma Pokemon to the Bench
		"ex4-74": return 35.0  # Strength Charm (Tool): one-off +10 damage
		"ex4-75": return 45.0  # Team Aqua Ball (Item): coin-flip Team Aqua search
		"ex4-76": return 40.0  # Team Aqua Belt (Tool): between-turn free evolution
		"ex4-77": return 55.0  # Team Aqua Conspirator (Supporter): up to 2 Basic/Energy search
		"ex4-80": return 45.0  # Team Magma Ball (Item): coin-flip Team Magma search
		"ex4-81": return 40.0  # Team Magma Belt (Tool): between-turn free evolution
		"ex4-82": return 55.0  # Team Magma Conspirator (Supporter): up to 2 Basic/Energy search
		"ex4-85": return 40.0  # Warp Point (Item): switch both Actives (disruption)
		# ── EX8 (EX Deoxys) ──
		"ex8-84": return 35.0  # Balloon Berry (Tool): free-retreat safety net
		"ex8-85": return 30.0  # Crystal Shard (Tool): type-override utility
		"ex8-86": return 30.0  # Energy Charge (Item): coin-flip Energy recovery to deck
		"ex8-87": return 45.0  # Lady Outing (Supporter): up to 3 different basic Energy to hand
		"ex8-88": return 55.0  # Master Ball (Item): dig 7 for any Pokemon
		"ex8-90": return 55.0  # Professor Cozmo's Discovery (Supporter): draw 2-3
		"ex8-92": return 35.0  # Strength Charm (Tool): one-off +10 damage
		# ── EX9 (EX Emerald) — mostly ex1/ex2 reprints, mirror those scores ──
		"ex9-76": return _cpu_score_full_heal()          # Double Full Heal
		"ex9-77": return 55.0                            # Lanette's Net Search (Supporter)
		"ex9-78": return 30.0                            # Lum Berry (Tool): between-turn status cure
		"ex9-79": return 55.0                            # Mr. Stone's Project (Supporter): up to 2 basic Energy
		"ex9-80": return 30.0                            # Oran Berry (Tool): between-turn heal 20
		"ex9-81": return 50.0                            # PokéNav
		"ex9-82": return 65.0                            # Professor Birch (Supporter)
		"ex9-83": return _cpu_score_ex2_rare_candy()     # Rare Candy
		"ex9-84": return 50.0                            # Scott (Supporter): fetch Supporters/Stadiums
		"ex9-85": return _cpu_score_ex2_wallys_training() # Wally's Training (Supporter)
		# ex9-75 Battle Frontier (Stadium) uses the generic stadium-play heuristic.
		# ── EX10 (EX Unseen Forces) ──
		"ex10-81": return 40.0                           # Energy Recycle System: recover basic Energy
		"ex10-82": return _cpu_score_energy_removal()    # Energy Removal 2
		"ex10-84": return 35.0                           # Energy Switch
		"ex10-86": return 60.0                           # Mary's Request (Supporter): draw
		"ex10-87": return 45.0                           # Poké Ball
		"ex10-88": return 40.0                           # Pokémon Reversal
		"ex10-89": return 55.0                           # Professor Elm's Training Method (Supporter)
		"ex10-93": return 40.0                           # Warp Point
		"ex10-94": return 20.0                           # Energy Search
		"ex10-95": return _cpu_score_potion()            # Potion
		# ex10 Pokémon Tools (Curse Powder/Energy Root/Fluffy Berry/Protective Orb/Sitrus Berry/Solid Rage)
		"ex10-80": return 30.0                           # Curse Powder (Tool)
		"ex10-83": return 25.0                           # Energy Root (Tool): +20 HP (blocks abilities)
		"ex10-85": return 30.0                           # Fluffy Berry (Tool): free retreat
		"ex10-90": return 30.0                           # Protective Orb (Tool): no Weakness
		"ex10-91": return 35.0                           # Sitrus Berry (Tool): between-turn heal 30
		"ex10-92": return 35.0                           # Solid Rage (Tool): +20 damage while ahead on prizes
		# ── EX13 (EX Holon Phantoms) ──
		"ex13-85": return 55.0                           # Holon Adventurer (Supporter): discard 1, draw 3-4
		"ex13-86": return 40.0                           # Holon Fossil (Item): coin-flip fossil Pokemon to Bench
		"ex13-88": return 55.0                           # Mr. Stone's Project (Supporter): up to 2 basic Energy
		"ex13-89": return 55.0                           # Professor Cozmo's Discovery (Supporter): draw 2-3
		"ex13-90": return _cpu_score_ex2_rare_candy()    # Rare Candy
		# Holon Lake (ex13-87 Stadium) uses the generic stadium-play heuristic.
	return 0.0

# MR. BRINEY'S COMPASSION (ex3-87): only valuable when the CPU has a damaged non-ex Pokemon worth
# saving (returning it to hand heals it and rescues it from a knockout).
func _cpu_score_ex3_mr_brineys_compassion() -> float:
	var best = 0
	for p in main.card_ops.get_all_pokemon_in_play(true):
		if main.is_ex_pokemon(p):
			continue
		best = max(best, p.get_damage_counters())
	if best >= 4:
		return 55.0
	if best >= 2:
		return 25.0
	return -100.0

# RARE CANDY (ex2-88): valuable only when the CPU has a Basic in play with a matching evolution in hand.
func _cpu_score_ex2_rare_candy() -> float:
	for p in main.card_ops.get_all_pokemon_in_play(true):
		if not main.is_basic_pokemon(p) or p.placed_on_field_this_turn:
			continue
		for h in main.opponent_hand:
			if h.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(h, p):
				return 75.0
	return -100.0

# WALLY'S TRAINING (ex2-89): only useful if the Active can be evolved by a card in the deck.
func _cpu_score_ex2_wallys_training() -> float:
	var active = main.opponent_active_pokemon
	if active == null or active.placed_on_field_this_turn:
		return -100.0
	for c in main.opponent_deck:
		if c.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(c, active):
			return 55.0
	return -100.0

func _cpu_score_neo1_energy_charge() -> float:
	var energy_in_discard = 0
	for c in main.opponent_discard_pile:
		if c.metadata.get("supertype","") == "Energy":
			energy_in_discard += 1
	return 40.0 if energy_in_discard >= 2 else 10.0

func _cpu_score_neo1_focus_band() -> float:
	var active = main.opponent_active_pokemon
	if active == null: return -50.0
	# Only attach if active doesn't already have a tool
	for ac in active.attached_cards:
		if main.trainer_effects.is_attached_trainer(ac):
			return -50.0
	var hp_pct = float(active.current_hp) / max(1, active.get_max_hp())
	return 60.0 if hp_pct < 0.5 else 30.0

func _cpu_score_neo1_mary() -> float:
	var hand_size = main.opponent_hand.size()
	return 50.0 if hand_size <= 3 else 20.0

func _cpu_score_neo1_super_energy_retrieval() -> float:
	var basic_e = 0
	for c in main.opponent_discard_pile:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basic_e += 1
	if basic_e < 2: return -50.0
	return 70.0 if basic_e >= 4 else 50.0

func _cpu_score_neo1_gold_berry() -> float:
	var all_cpu: Array = []
	if main.opponent_active_pokemon != null: all_cpu.append(main.opponent_active_pokemon)
	all_cpu.append_array(main.opponent_bench)
	for p in all_cpu:
		var dmg = p.get_max_hp() - p.current_hp
		# Only attach if no tool already and has 40+ damage
		var has_tool = false
		for ac in p.attached_cards:
			if main.trainer_effects.is_attached_trainer(ac): has_tool = true; break
		if not has_tool and dmg >= 40:
			return 65.0
	# Check if about to take damage
	if main.opponent_active_pokemon != null:
		for ac in main.opponent_active_pokemon.attached_cards:
			if main.trainer_effects.is_attached_trainer(ac): return -50.0
		return 35.0  # preemptive attachment
	return -50.0

func _cpu_score_neo1_miracle_berry() -> float:
	var active = main.opponent_active_pokemon
	if active == null: return -50.0
	if active.special_condition != "" or active.is_poisoned or active.is_burned:
		# Already have status — miracle berry will cure it at turn start
		for ac in active.attached_cards:
			if main.trainer_effects.is_attached_trainer(ac): return -50.0
		return 70.0
	for ac in active.attached_cards:
		if main.trainer_effects.is_attached_trainer(ac): return -50.0
	return 25.0  # preemptive

func _cpu_score_neo1_professor_elm() -> float:
	var hand = main.opponent_hand
	# Only use if hand is bad (few cards or mostly unhelpful)
	if hand.size() > 5: return -20.0
	return 70.0 if hand.size() <= 3 else 40.0

func _cpu_score_neo1_super_scoop_up() -> float:
	# Good to scoop when a bench pokemon is badly damaged
	var best_dmg = 0
	for bp in main.opponent_bench:
		var dmg = bp.get_max_hp() - bp.current_hp
		if dmg > best_dmg: best_dmg = dmg
	return 60.0 if best_dmg >= 40 else 20.0

func _cpu_score_neo1_berry() -> float:
	var all_cpu: Array = []
	if main.opponent_active_pokemon != null: all_cpu.append(main.opponent_active_pokemon)
	all_cpu.append_array(main.opponent_bench)
	for p in all_cpu:
		var dmg = p.get_max_hp() - p.current_hp
		var has_tool = false
		for ac in p.attached_cards:
			if main.trainer_effects.is_attached_trainer(ac): has_tool = true; break
		if not has_tool and dmg >= 20:
			return 45.0
	if main.opponent_active_pokemon != null:
		for ac in main.opponent_active_pokemon.attached_cards:
			if main.trainer_effects.is_attached_trainer(ac): return -50.0
		return 25.0
	return -50.0

func _cpu_score_neo1_double_gust() -> float:
	# Use when player has a weaker benched target
	var player_bench = main.player_bench
	if player_bench.size() == 0: return -50.0
	var weakest_bench_hp = 9999
	for bp in player_bench:
		weakest_bench_hp = min(weakest_bench_hp, bp.current_hp)
	var player_active_hp = main.player_active_pokemon.current_hp if main.player_active_pokemon != null else 9999
	return 60.0 if weakest_bench_hp < player_active_hp else 20.0

func _cpu_score_neo1_moo_moo_milk() -> float:
	var all_cpu: Array = []
	if main.opponent_active_pokemon != null: all_cpu.append(main.opponent_active_pokemon)
	all_cpu.append_array(main.opponent_bench)
	var max_dmg = 0
	for p in all_cpu:
		max_dmg = max(max_dmg, p.get_max_hp() - p.current_hp)
	return 50.0 if max_dmg >= 30 else 10.0

func _cpu_score_neo1_super_rod() -> float:
	var has_evo = false; var has_basic = false
	for c in main.opponent_discard_pile:
		if c.metadata.get("supertype","") == "Pokémon":
			var sub = c.metadata.get("subtypes",[])
			if "Stage 1" in sub or "Stage 2" in sub: has_evo = true
			if "Basic" in sub: has_basic = true
	return 60.0 if has_evo else (40.0 if has_basic else -50.0)

func _cpu_score_neo2_fossil_egg() -> float:
	var bench = main.opponent_bench
	if bench.size() >= main.get_max_bench_size(): return -100.0
	for c in main.opponent_hand + main.opponent_deck:
		if "Mysterious Fossil" in c.metadata.get("evolvesFrom",""):
			return 50.0
	return -50.0

func _cpu_score_neo2_hyper_devolution_spray() -> float:
	var all_cpu = ([main.opponent_active_pokemon] if main.opponent_active_pokemon else []) + main.opponent_bench
	for p in all_cpu:
		if p.attached_pre_evolutions.size() > 0:
			return 30.0
	return -100.0

func _cpu_score_neo2_ruin_wall() -> float:
	if main.opponent_bench.size() >= main.get_max_bench_size(): return -100.0
	for c in main.opponent_deck:
		if "Unown" in c.metadata.get("name","") and main.is_basic_pokemon(c):
			return 45.0
	return -50.0

func _cpu_score_professor_oak(card: card_object) -> float:
	var hand = main.opponent_hand
	if hand.size() > 5: return -50.0
	# Check for playable evolutions
	for c in hand:
		if c == card: continue
		var subtypes = c.metadata.get("subtypes", [])
		if "Stage 2" in subtypes: return -50.0
		if "Stage 1" in subtypes:
			var targets = main.get_valid_evolution_targets(c, true)
			if targets.size() > 0: return -50.0 + (-20.0)
	if hand.size() <= 1: return 90.0
	if hand.size() <= 3: return 70.0
	if hand.size() <= 4: return 40.0
	return -50.0

func _cpu_score_computer_search(card: card_object) -> float:
	if main.opponent_hand.size() < 3: return 0.0
	return 60.0

func _cpu_score_devolution_spray() -> float:
	return -100.0

func _cpu_score_impostor_prof_oak() -> float:
	if main.player_hand.size() >= 7:
		return 50.0 + (main.player_hand.size() - 7) * 10.0
	return 0.0

func _cpu_score_item_finder() -> float:
	if main.opponent_hand.size() < 3: return 0.0
	var trainers_in_discard = []
	for c in main.opponent_discard_pile:
		if main.trainer_effects.is_trainer_card(c):
			trainers_in_discard.append(c)
	if trainers_in_discard.size() == 0: return 0.0
	var best = 0.0
	for t in trainers_in_discard:
		best = max(best, cpu_score_trainer_card(t))
	return best if best >= 50.0 else 0.0

func _cpu_score_lass() -> float:
	var score = 0.0
	# Add 30 if CPU has no playable trainers
	var has_playable = false
	for c in main.opponent_hand:
		if main.trainer_effects.is_trainer_card(c) and cpu_score_trainer_card(c) > 30:
			has_playable = true
	if not has_playable: score += 30.0
	# Add based on player hand size
	if main.player_hand.size() > 4:
		score += 5.0 * (main.player_hand.size() - 4)
	# Subtract for own playable trainers lost
	for c in main.opponent_hand:
		if main.trainer_effects.is_trainer_card(c) and cpu_score_trainer_card(c) > 30:
			score -= 15.0
	return score

func _cpu_score_pokemon_breeder() -> float:
	for card in main.opponent_hand:
		var subtypes = card.metadata.get("subtypes", [])
		if "Stage 2" in subtypes:
			var all_pokemon = []
			if main.opponent_active_pokemon != null: all_pokemon.append(main.opponent_active_pokemon)
			all_pokemon.append_array(main.opponent_bench)
			for p in all_pokemon:
				if not p.placed_on_field_this_turn and main.is_basic_pokemon(p) and main.trainer_effects._basic_matches_stage2(p, card):
					return 100.0
	return -100.0

func _cpu_score_pokemon_trader() -> float:
	for card in main.opponent_hand:
		if card.metadata.get("supertype", "").to_lower() != "pokémon": continue
		if main.is_basic_pokemon(card):
			var name = card.metadata.get("name", "")
			var already_in_play = false
			if main.opponent_active_pokemon != null and main.opponent_active_pokemon.metadata.get("name", "") == name:
				already_in_play = true
			for bp in main.opponent_bench:
				if bp.metadata.get("name", "") == name: already_in_play = true
			if already_in_play: return 70.0
	return 0.0

func _cpu_score_scoop_up() -> float:
	var all_pokemon = []
	if main.opponent_active_pokemon != null: all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	for p in all_pokemon:
		var max_hp = int(p.metadata.get("hp", "0"))
		if p.current_hp <= max_hp / 2 and main.opponent_bench.size() > 0:
			return 80.0
	return 0.0

func _cpu_score_super_energy_removal() -> float:
	if main.player_active_pokemon == null: return 0.0
	var p_energy = main.player_active_pokemon.attached_energies.size()
	# Check own energy available
	var own_energy = false
	if main.opponent_active_pokemon != null and main.opponent_active_pokemon.attached_energies.size() > 0:
		own_energy = true
	for bp in main.opponent_bench:
		if bp.attached_energies.size() > 0: own_energy = true
	if not own_energy: return 0.0
	if p_energy >= 3: return 90.0
	if p_energy >= 2: return 60.0
	return 0.0

func _cpu_score_defender() -> float:
	if main.opponent_active_pokemon == null or main.player_active_pokemon == null: return 0.0
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false): return 60.0
	return 0.0

func _cpu_score_energy_retrieval() -> float:
	var energy_in_hand = 0
	for c in main.opponent_hand:
		if c.metadata.get("supertype", "").to_lower() == "energy":
			energy_in_hand += 1
	var basic_in_discard = 0
	for c in main.opponent_discard_pile:
		if main.is_basic_energy_card(c): basic_in_discard += 1
	if energy_in_hand <= 1 and basic_in_discard >= 2: return 70.0
	if energy_in_hand <= 1 and basic_in_discard >= 1: return 40.0
	return 0.0

func _cpu_score_full_heal() -> float:
	if main.opponent_active_pokemon == null: return 0.0
	match main.opponent_active_pokemon.special_condition:
		"Paralyzed": return 100.0
		"Confused": return 80.0
		"Asleep": return 60.0
	if main.opponent_active_pokemon.is_poisoned: return 40.0
	return 0.0

func _cpu_score_maintenance() -> float:
	if main.opponent_hand.size() < 4: return 0.0
	return 30.0

func _cpu_score_pluspower() -> float:
	if main.opponent_active_pokemon == null or main.player_active_pokemon == null: return 0.0
	var pp_bonus = (main.opponent_active_pokemon.pluspower_count + 1) * 10
	# Check if this KOs
	for attack in main.opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, main.opponent_active_pokemon) > 0: continue
		var dmg_range = main.attack_effects.estimate_attack_damage_range(attack, main.opponent_active_pokemon, main.player_active_pokemon)
		var types = main.opponent_active_pokemon.metadata.get("types", ["Colorless"])
		var result_without = main.calculate_final_damage(dmg_range["min"], types, main.player_active_pokemon)
		if result_without["damage"] < main.player_active_pokemon.current_hp:
			var result_with = result_without["damage"] + pp_bonus
			if result_with >= main.player_active_pokemon.current_hp:
				return 90.0
	return 30.0

func _cpu_score_pokemon_center() -> float:
	var total_damage = 0
	var total_max_hp = 0
	var energy_lost = 0
	var all_pokemon = []
	if main.opponent_active_pokemon != null: all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	for p in all_pokemon:
		var max_hp = int(p.metadata.get("hp", "0"))
		var dmg = max_hp - p.current_hp
		if dmg > 0:
			total_damage += dmg
			total_max_hp += max_hp
			energy_lost += p.attached_energies.size()
	if total_max_hp == 0: return 0.0
	if float(total_damage) / float(total_max_hp) > 0.5:
		return max(0.0, 80.0 - energy_lost * 10.0)
	return 0.0

func _cpu_score_revive() -> float:
	if main.opponent_bench.size() >= main.get_max_bench_size(): return 0.0
	for c in main.opponent_discard_pile:
		if main.is_basic_pokemon(c):
			var result = evaluate_opponents_start_setup_pokemon_choices(c, main.opponent_hand)
			if result.get("total_score", 0) >= 250:
				return 70.0
	return 0.0

func _cpu_score_super_potion() -> float:
	if main.opponent_active_pokemon == null: return 0.0
	var max_hp = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
	var dmg = max_hp - main.opponent_active_pokemon.current_hp
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false) and dmg >= 40 and main.opponent_active_pokemon.attached_energies.size() > 0:
		return 90.0
	return 0.0

func _cpu_score_energy_removal() -> float:
	if main.player_active_pokemon == null: return 0.0
	var e = main.player_active_pokemon.attached_energies.size()
	if e >= 2: return 60.0
	if e == 1: return 30.0
	return 0.0

func _cpu_score_gust_of_wind() -> float:
	if main.player_bench.size() == 0: return 0.0
	for bp in main.player_bench:
		if main.opponent_active_pokemon != null:
			var types = main.opponent_active_pokemon.metadata.get("types", ["Colorless"])
			for attack in main.opponent_active_pokemon.metadata.get("attacks", []):
				if get_unmet_energy_count(attack, main.opponent_active_pokemon) > 0: continue
				var dmg_range = main.attack_effects.estimate_attack_damage_range(attack, main.opponent_active_pokemon, bp)
				var result = main.calculate_final_damage(dmg_range["min"], types, bp)
				if result["damage"] >= bp.current_hp:
					return 85.0
	return 0.0

func _cpu_score_potion() -> float:
	if main.opponent_active_pokemon == null: return 0.0
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false):
		var max_hp = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
		if main.opponent_active_pokemon.current_hp + 20 > max_hp * 0.5:
			return 60.0
	return 0.0

func _cpu_score_switch() -> float:
	if main.opponent_bench.size() == 0: return 0.0
	var cpu_eval = get_cpu_evaluation()
	if evaluate_retreat_reasons(cpu_eval):
		return 70.0
	return 0.0

func _cpu_score_clefairy_doll() -> float:
	if main.opponent_bench.size() < 3: return 20.0
	return -100.0

# CPU plays highest-priority trainer cards (Bill first)
func cpu_phase_play_trainer_cards_priority() -> void:
	# Check trainer lock (Psyduck Headache)
	if main.trainer_effects.opponent_trainer_locked:
		print("CPU: Trainer cards locked this turn (Headache)")
		return
	var played = true
	while played:
		played = false
		var best_card: card_object = null
		var best_score = 29.9 # Threshold: play cards scoring >= 30
		# MATCH EFFECT: trainer_discard_cost — demand more value when each trainer costs cards
		best_score += 10.0 * main.match_effects.trainer_discard_cost(true)

		for card in main.opponent_hand:
			if not main.trainer_effects.is_trainer_card(card): continue
			var score = cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				best_card = card

		if best_card != null:
			# Validate the card can actually be played before committing
			var validation_error = main.trainer_effects.validate_trainer_can_be_played(best_card, true)
			if validation_error != "":
				# Skip this card and continue looking
				# Mark it so we don't try it again this loop
				main.opponent_hand.erase(best_card)
				main.opponent_hand.append(best_card)  # Move to end
				break
			await main.trainer_effects.play_trainer_card(best_card, true)
			if main._should_bail(): return
			if main.opponent_turn_force_end:
				return  # turn was force-ended by a trainer card; let the orchestrator wrap up
			played = true

# CPU re-evaluates and plays remaining trainer cards
func cpu_phase_play_trainer_cards_remaining() -> void:
	# Check trainer lock (Psyduck Headache)
	if main.trainer_effects.opponent_trainer_locked:
		return
	var played = true
	while played:
		played = false
		var best_card: card_object = null
		var best_score = 29.9 # Threshold: play cards scoring >= 30
		# MATCH EFFECT: trainer_discard_cost — demand more value when each trainer costs cards
		best_score += 10.0 * main.match_effects.trainer_discard_cost(true)

		for card in main.opponent_hand:
			if not main.trainer_effects.is_trainer_card(card): continue
			var score = cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				best_card = card

		if best_card != null:
			# Validate the card can actually be played before committing
			var validation_error = main.trainer_effects.validate_trainer_can_be_played(best_card, true)
			if validation_error != "":
				break
			await main.trainer_effects.play_trainer_card(best_card, true)
			if main._should_bail(): return
			if main.opponent_turn_force_end:
				return  # turn was force-ended by a trainer card; let the orchestrator wrap up
			played = true

# CPU search deck helpers
func cpu_search_deck_for_best_card(deck: Array) -> card_object:
	# Priority: draw trainers > evolution cards > energy > basic pokemon
	var best: card_object = null
	var best_score = -1.0
	for card in deck:
		var score = 0.0
		var name = card.metadata.get("name", "").to_lower()
		if name == "bill": score = 100.0
		elif name == "professor oak" and main.opponent_hand.size() <= 3: score = 90.0
		elif card.metadata.get("supertype", "").to_lower() == "pokémon" and not main.is_basic_pokemon(card):
			var targets = main.get_valid_evolution_targets(card, true)
			if targets.size() > 0: score = 80.0
		elif card.metadata.get("supertype", "").to_lower() == "energy": score = 50.0
		elif main.is_basic_pokemon(card) and main.opponent_bench.size() < 3: score = 40.0
		if score > best_score:
			best_score = score
			best = card
	return best

func cpu_search_deck_for_best_pokemon(pokemon_list: Array) -> card_object:
	var best: card_object = null
	var best_score = -1.0
	for card in pokemon_list:
		var score = 0.0
		if not main.is_basic_pokemon(card):
			var targets = main.get_valid_evolution_targets(card, true)
			if targets.size() > 0: score = 80.0
			else: score = 20.0
		else:
			var result = evaluate_opponents_start_setup_pokemon_choices(card, main.opponent_hand)
			score = result.get("total_score", 0) / 10.0
		if score > best_score:
			best_score = score
			best = card
	return best

############################################### Section G: POKEMON POWER SYSTEM ######################################################################

# Opens the Pokemon Power selection menu
func opponent_take_prize_card() -> void:
	if main.opponent_prize_cards.size() == 0:
		return
	
	var random_index = randi() % main.opponent_prize_cards.size()
	var chosen_card = main.opponent_prize_cards[random_index]
	
	await main.show_message("OPPONENT TAKES A PRIZE CARD!")
	if main._should_bail(): return
	await main.take_prize_card(chosen_card, true)
	if main._should_bail(): return

################################################## END OPPONENT PRIORITISE FUNCTIONALITY FUNCTIONS ###################################################
######################################################################################################################################################

######################################################################################################################################################
#  ########  ######     ##     ########  ##    ##  ########  ######          &&&&&&&          #######    #######  ##      ##  ########  ######    #######
#     ##     ##   ##   ####       ##     ###   ##  ##        ##   ##        &&      &         ##    ##  ##     ## ##      ##  ##        ##   ##  ##
#     ##     ######   ##  ##      ##     ## ## ##  ########  ######    ###  &&&&&&      ###   #######   ##     ## ##  ##  ##  ########  ######    #######
#     ##     ##  ##  ########     ##     ##  ####  ##        ##  ##        &&     &&&         ##        ##     ## ## #### ##  ##        ##  ##         ##
#     ##     ##   ## ##      ## #######  ##   ###  ########  ##   ##        &&&&&& &          ##         #######   ###  ###   ########  ##   ##  #######
######################################################################################################################################################
##################################################### TRAINER CARD & POKEMON POWER FUNCTIONS ########################################################

############################################### Section A: HELPER FUNCTIONS #########################################################################

# Returns true if the Pokemon has any status condition that blocks Pokemon Powers



# Returns priority score for discarding a card (lower = discard first)
func evaluate_hand_card_priority(card: card_object, hand: Array) -> int:
	if hand.size() <= 2:
		return 99
	
	var supertype = card.metadata.get("supertype", "")
	
	if supertype == "Energy":
		var energy_count = 0
		for c in hand:
			if c.metadata.get("supertype") == "Energy":
				energy_count += 1
		if energy_count >= 3:
			return 1
		else:
			return 99
	
	var subtypes = card.metadata.get("subtypes", [])
	if "Stage 1" in subtypes or "Stage 2" in subtypes:
		return 4
	
	if supertype == "Pokémon":
		if "Basic" in subtypes:
			if main.opponent_bench.size() >= 2:
				return 2
			else:
				return 4
	
	if supertype == "Trainer":
		var subtype = subtypes[0] if subtypes.size() > 0 else ""
		if subtype == "Supporter":
			return 4
		else:
			return 3
	
	return 3

# Chooses bench damage targets sorted by lowest HP first (maximize KOs)
func cpu_choose_bench_damage_targets(count: int, damage_per: int) -> Array:
	var bench = main.player_bench
	if bench.size() == 0:
		return []
	var targets = bench.duplicate()
	targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return targets.slice(0, min(count, targets.size()))


######################################################################################################################################################
############################################## BASE3 (FOSSIL) CPU SCORING ############################################################################
######################################################################################################################################################

func _cpu_score_mr_fuji() -> float:
	# Good if a bench pokemon is heavily damaged
	var best_damage = 0
	for bp in main.opponent_bench:
		var dmg = int(bp.metadata.get("hp", "0")) - bp.current_hp
		if dmg > best_damage:
			best_damage = dmg
	if best_damage >= 40:
		return 50.0 + best_damage
	if best_damage >= 20:
		return 20.0
	return -50.0  # No damaged bench pokemon, not useful

func _cpu_score_gambler() -> float:
	var hand = main.opponent_hand
	# Only gamble if hand is very small (desperate for cards)
	if hand.size() <= 2:
		return 60.0
	if hand.size() <= 3:
		return 30.0
	# With bigger hands, risk of losing good cards is too high
	return -50.0

func _cpu_score_poke_ball() -> float:
	# Poké Ball: coin flip search for any Basic or Evolution card
	# Good when CPU needs evolutions or bench setup, but coin-flip dependent (50% fail)
	var bench = main.opponent_bench
	var hand = main.opponent_hand
	# Higher priority if bench is empty or CPU has evolutions to find
	var has_evolvable = false
	var all_pokemon = get_all_cpu_field_pokemon()
	for p in all_pokemon:
		var evolves_to = p.metadata.get("evolvesTo", [])
		if evolves_to.size() > 0:
			has_evolvable = true
			break
	if bench.size() < 2:
		return 55.0  # Need bench presence
	if has_evolvable:
		return 45.0  # Might find evolution
	return 25.0  # Low priority filler

######################################################################################################################################################
############################################ BASE5 (TEAM ROCKET) CPU TRAINER SCORING #################################################################
######################################################################################################################################################

func _cpu_score_rockets_sneak_attack() -> float:
	var player_hand = main.player_hand
	var has_trainer = false
	for c in player_hand:
		if c.metadata.get("supertype", "") == "Trainer":
			has_trainer = true
			break
	if not has_trainer:
		return -100.0  # Can't play
	return 70.0  # Removing a trainer is strong disruption

func _cpu_score_the_bosss_way() -> float:
	var deck = main.opponent_deck
	for card in deck:
		var name = card.metadata.get("name", "")
		var subtypes = card.metadata.get("subtypes", [])
		if name.begins_with("Dark ") and card.metadata.get("supertype", "") == "Pokémon":
			if "Stage 1" in subtypes or "Stage 2" in subtypes:
				# Check if we have matching basic on field
				var all_cpu = get_all_cpu_field_pokemon()
				for p in all_cpu:
					if card.metadata.get("evolvesFrom", "") == p.metadata.get("name", ""):
						return 85.0  # Can evolve immediately next turn
				return 60.0  # Good to have in hand
	return -100.0  # No Dark evolutions in deck

func _cpu_score_challenge() -> float:
	var cpu_bench = main.opponent_bench
	var cpu_deck = main.opponent_deck
	if cpu_bench.size() >= main.get_max_bench_size():
		return 50.0  # Bench full, we'll draw 2 if declined
	# Check if CPU has basics in deck
	var has_basics = false
	for card in cpu_deck:
		if main.is_basic_pokemon(card):
			has_basics = true
			break
	if has_basics and cpu_bench.size() < 3:
		return 40.0  # Might benefit if accepted
	return 50.0  # Draw 2 if declined is decent

func _cpu_score_imposter_oaks_revenge() -> float:
	if main.opponent_hand.size() < 2:
		return -100.0  # Need at least 1 to discard
	if main.player_hand.size() >= 6:
		return 75.0  # Big disruption
	if main.player_hand.size() >= 4:
		return 50.0
	return 10.0  # Not worth it if player has few cards

func _cpu_score_nightly_garbage_run() -> float:
	var discard = main.opponent_discard_pile
	var valid_count = 0
	for card in discard:
		if card.metadata.get("supertype", "") == "Pokémon" or main.is_basic_energy_card(card):
			valid_count += 1
	if valid_count == 0:
		return -100.0
	if valid_count >= 3:
		return 65.0
	return 40.0

func _cpu_score_goop_gas_attack() -> float:
	# Good if opponent has active powers (check player's field)
	var player_pokemon: Array = []
	if main.player_active_pokemon != null:
		player_pokemon.append(main.player_active_pokemon)
	player_pokemon.append_array(main.player_bench)
	
	for p in player_pokemon:
		var abilities = p.metadata.get("abilities", [])
		if abilities.size() > 0:
			return 70.0  # Opponent has powers, worth shutting down
	return -10.0  # No powers to block

func _cpu_score_sleep_trainer() -> float:
	var defender = main.player_active_pokemon
	if defender == null:
		return -100.0
	if defender.special_condition != "":
		return -20.0  # Already has a condition
	return 30.0  # 50% chance of sleep, moderate value

######################################################################################################################################################
######################################################## GYM1 (GYM HEROES) CPU SCORING ##############################################################
######################################################################################################################################################

func _cpu_score_gym1_brock() -> float:
	# Heal 10 from each damaged. Total healing scales with number damaged.
	var damaged_count = 0
	for p in get_all_cpu_field_pokemon():
		if p.current_hp < int(p.metadata.get("hp", "0")):
			damaged_count += 1
	if damaged_count == 0:
		return -100.0
	# 30 base, +15 per additional damaged
	return 30.0 + 15.0 * damaged_count

func _cpu_score_gym1_erika() -> float:
	var hand = main.opponent_hand
	if hand.size() >= 6:
		return -50.0  # Don't overdraw; symmetric refill
	if hand.size() <= 2:
		return 55.0
	return 25.0

func _cpu_score_gym1_lt_surge() -> float:
	# Useful if our current active is bad against the player's active.
	if main.opponent_active_pokemon == null:
		return -100.0
	if main.opponent_bench.size() >= main.get_max_bench_size():
		return -100.0
	var has_basic = false
	for c in main.opponent_hand:
		if main.is_basic_pokemon(c):
			has_basic = true
			break
	if not has_basic:
		return -100.0
	# Score higher when our active is in trouble
	var max_hp = int(main.opponent_active_pokemon.metadata.get("hp", "0"))
	if main.opponent_active_pokemon.current_hp <= max_hp / 3:
		return 55.0
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false):
		return 50.0
	return 5.0

func _cpu_score_gym1_misty() -> float:
	# Only useful if we have a Misty-named active that's set to attack and we can spare 2 cards.
	if main.opponent_active_pokemon == null:
		return -100.0
	if not ("Misty" in main.opponent_active_pokemon.metadata.get("name", "")):
		return -100.0
	if main.opponent_hand.size() < 4:
		return -50.0  # Don't strip the hand too thin
	# Is the +20 going to KO?
	if main.player_active_pokemon != null:
		for attack in main.opponent_active_pokemon.metadata.get("attacks", []):
			if get_unmet_energy_count(attack, main.opponent_active_pokemon) > 0:
				continue
			var dmg_range = main.attack_effects.estimate_attack_damage_range(attack, main.opponent_active_pokemon, main.player_active_pokemon)
			var types = main.opponent_active_pokemon.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(dmg_range["min"], types, main.player_active_pokemon)
			if result["damage"] + 20 >= main.player_active_pokemon.current_hp and result["damage"] < main.player_active_pokemon.current_hp:
				return 90.0  # Boost guarantees KO
	return 25.0

func _cpu_score_gym1_rockets_trap() -> float:
	if main.player_hand.size() == 0:
		return -100.0
	# Coin-flip dependent. Mild disruption.
	return 25.0 + min(3, main.player_hand.size()) * 5.0

func _cpu_score_gym1_blaines_quiz() -> float:
	# 50/50. We profit either way: we draw 2 OR opp draws 2. Slight positive expected value, but symmetric.
	if main.opponent_hand.size() >= 7:
		return -20.0
	return 15.0

func _cpu_score_gym1_charity() -> float:
	# CPU never reduces own outgoing damage, so this card provides no benefit to CPU.
	return -100.0

func _cpu_score_gym1_blaines_last_resort(card: card_object) -> float:
	# Only playable when hand has no other cards (validation checks this).
	for c in main.opponent_hand:
		if c != card:
			return -100.0
	return 100.0  # Free 5-card refill

func _cpu_score_gym1_brocks_training_method() -> float:
	var deck = main.opponent_deck
	for c in deck:
		if c.metadata.get("supertype", "") == "Pokémon" and "Brock" in c.metadata.get("name", ""):
			return 75.0
	return -100.0

func _cpu_score_gym1_erikas_maids() -> float:
	if main.opponent_hand.size() < 4:
		return -50.0  # Don't strip hand
	var deck = main.opponent_deck
	for c in deck:
		if c.metadata.get("supertype", "") == "Pokémon" and "Erika" in c.metadata.get("name", ""):
			return 65.0
	return -100.0

func _cpu_score_gym1_erikas_perfume() -> float:
	# CPU rarely benefits from auto-benching opponent's basics.
	return -100.0

func _cpu_score_gym1_good_manners(card: card_object) -> float:
	# Only playable if no Basic in hand. Score very high in that case.
	for c in main.opponent_hand:
		if c == card:
			continue
		if main.is_basic_pokemon(c):
			return -100.0
	# Check deck has basics
	for c in main.opponent_deck:
		if main.is_basic_pokemon(c):
			return 80.0
	return -100.0

func _cpu_score_gym1_lt_surges_treaty() -> float:
	# The OPPONENT (player) chooses. Heuristic: if CPU is behind on prizes, the player will likely deny prizes (let CPU draw 1).
	# Either way: outcome is mildly positive (1 prize OR 1 draw). Moderate but symmetric.
	return 20.0

func _cpu_score_gym1_minion() -> float:
	if main.player_bench.size() == 0:
		return 0.0  # Coin flip with no payoff bench
	# 25% chance both heads. Strong disruption if it lands. Risk: turn ends.
	return 30.0

func _cpu_score_gym1_mistys_wrath() -> float:
	if main.opponent_deck.size() == 0:
		return -100.0
	# Strong: see top 7, pick 2, but throw away 5. Worth it when hand is medium and deck is healthy.
	if main.opponent_hand.size() <= 3:
		return 55.0
	if main.opponent_hand.size() <= 5:
		return 35.0
	return 10.0

func _cpu_score_gym1_recall() -> float:
	# CPU doesn't currently consider pre-evolution attacks during attack scoring; skip.
	return -100.0

func _cpu_score_gym1_sabrinas_esp() -> float:
	# Needs a Sabrina-named pokemon in play
	var has_sabrina = false
	for p in get_all_cpu_field_pokemon():
		if "Sabrina" in p.metadata.get("name", ""):
			has_sabrina = true
			break
	if not has_sabrina:
		return -100.0
	return 30.0

func _cpu_score_gym1_secret_mission() -> float:
	# Look at opp hand (info) + discard-and-draw cycling. Worth more when our hand has dead cards.
	if main.opponent_hand.size() <= 2:
		return -20.0
	return 35.0

func _cpu_score_gym1_tickling_machine() -> float:
	# Massive disruption on heads (player's whole hand). Risk: tails ends turn.
	# Score scales with how disruptive it is — bigger player hand = better target.
	if main.player_hand.size() == 0:
		return -100.0
	# Only consider once attacking phase is unlikely to be wasted: i.e. we've already attacked / can't KO.
	# For simplicity, only play it when player has 4+ cards in hand.
	if main.player_hand.size() >= 4:
		return 45.0
	return 10.0

func _cpu_score_gym1_blaines_gamble() -> float:
	if main.opponent_hand.size() < 3:
		return -50.0  # too risky with a thin hand
	if main.opponent_hand.size() >= 5:
		return 40.0
	return 15.0

func _cpu_score_gym1_energy_flow() -> float:
	# CPU only uses this on heavily-damaged bench (to save energies). Score based on that.
	var any_target = false
	for p in get_all_cpu_field_pokemon():
		if p.attached_energies.size() == 0:
			continue
		var max_hp = int(p.metadata.get("hp", "0"))
		if p.current_hp <= max_hp / 2:
			any_target = true
			break
	if not any_target:
		return -100.0
	return 40.0

func _cpu_score_gym1_mistys_duel() -> float:
	# Coin flip; winner gets a fresh hand. Worth playing when our hand is thin OR very large.
	if main.opponent_hand.size() <= 2:
		return 45.0
	if main.opponent_hand.size() >= 7:
		return 35.0
	return 10.0

func _cpu_score_gym1_sabrinas_gaze() -> float:
	# Refill both hands to their previous size. Only useful when our hand is very small.
	if main.opponent_hand.size() <= 2:
		return 50.0
	return -50.0

func _cpu_score_gym1_trash_exchange() -> float:
	# Shuffle discard into deck and discard top X. Net deck recovery if discard has good cards.
	if main.opponent_discard_pile.size() < 4:
		return -50.0
	# Score scales with discard usefulness
	var useful = 0
	for c in main.opponent_discard_pile:
		var st = c.metadata.get("supertype", "")
		if st == "Pokémon" or st == "Energy":
			useful += 1
	if useful >= 6:
		return 40.0
	return 15.0

######################################################################################################################################################
###################################################### GYM2 (GYM CHALLENGE) CPU SCORING #############################################################
######################################################################################################################################################

func _cpu_score_gym2_blaine(card: card_object) -> float:
	# Needs unused energy attach, 2 Fire energy in hand, and a Blaine in play
	if main.opponent_energy_played_this_turn or main.opponent_blaine_double_attach_used:
		return -100.0
	var fire = 0
	for c in main.opponent_hand:
		if c == card:
			continue
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Fire Energy":
			fire += 1
	if fire < 2:
		return -100.0
	var has_blaine = false
	for p in get_all_cpu_field_pokemon():
		if "Blaine" in p.metadata.get("name", ""):
			has_blaine = true
			break
	if not has_blaine:
		return -100.0
	return 80.0  # Double-attach is very strong

func _cpu_score_gym2_giovanni() -> float:
	# Useful only if we have a Giovanni pokemon AND a hand evolution that would otherwise be blocked
	var has_giovanni = false
	for p in get_all_cpu_field_pokemon():
		if "Giovanni" in p.metadata.get("name", ""):
			has_giovanni = true
			break
	if not has_giovanni:
		return -100.0
	# Check hand for a Giovanni evolution
	for c in main.opponent_hand:
		if c.metadata.get("supertype", "") != "Pokémon":
			continue
		if "Giovanni" not in c.metadata.get("name", ""):
			continue
		var subs = c.metadata.get("subtypes", [])
		if "Stage 1" in subs or "Stage 2" in subs:
			return 60.0
	return -50.0

func _cpu_score_gym2_koga() -> float:
	# Worth playing if we have a Koga active about to attack the player
	if main.opponent_active_pokemon == null or main.player_active_pokemon == null:
		return -100.0
	if not ("Koga" in main.opponent_active_pokemon.metadata.get("name", "")):
		return -100.0
	# Already poisoned? Less useful
	if main.player_active_pokemon.is_poisoned:
		return 5.0
	# Check if we can actually attack this turn
	for atk in main.opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(atk, main.opponent_active_pokemon) == 0:
			return 55.0
	return 10.0

func _cpu_score_gym2_sabrina() -> float:
	# Useful when an inactive Sabrina has stockpiled energy that another Sabrina needs
	var sabs: Array = []
	for p in get_all_cpu_field_pokemon():
		if "Sabrina" in p.metadata.get("name", ""):
			sabs.append(p)
	if sabs.size() < 2:
		return -100.0
	# Score if any source has >= 2 energies and at least one other Sabrina has 0
	var has_loaded = false
	var has_empty = false
	for s in sabs:
		if s.attached_energies.size() >= 2:
			has_loaded = true
		if s.attached_energies.size() == 0:
			has_empty = true
	if has_loaded and has_empty:
		return 55.0
	return 5.0

func _cpu_score_gym2_brocks_protection() -> float:
	var has_brock = false
	var loaded = false
	for p in get_all_cpu_field_pokemon():
		if "Brock" in p.metadata.get("name", ""):
			has_brock = true
			if p.attached_energies.size() >= 2:
				loaded = true
	if not has_brock:
		return -100.0
	# More valuable when there's an energy stockpile to protect
	if loaded:
		return 40.0
	return 15.0

func _cpu_score_gym2_erikas_kindness() -> float:
	# Total healing benefit minus the benefit to the player
	var cpu_dmg = 0
	var player_dmg = 0
	for p in get_all_cpu_field_pokemon():
		var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
		if dmg > 0:
			cpu_dmg += min(20, dmg)
	for p in [main.player_active_pokemon] + main.player_bench:
		if p == null:
			continue
		var dmg2 = int(p.metadata.get("hp", "0")) - p.current_hp
		if dmg2 > 0:
			player_dmg += min(20, dmg2)
	var net = cpu_dmg - player_dmg
	if cpu_dmg == 0:
		return -50.0
	if net >= 20:
		return 50.0
	if net >= 0:
		return 20.0
	return -20.0

func _cpu_score_gym2_giovannis_last_resort() -> float:
	# Heals a Giovanni pokemon fully but discards hand. Worth it only when CPU is desperate and Giovanni is heavily damaged.
	var best_damage = 0
	for p in get_all_cpu_field_pokemon():
		if "Giovanni" not in p.metadata.get("name", ""):
			continue
		var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
		if dmg > best_damage:
			best_damage = dmg
	if best_damage < 40:
		return -100.0
	# Hand discard cost
	if main.opponent_hand.size() >= 5:
		return -30.0
	if best_damage >= 80:
		return 60.0
	return 20.0

func _cpu_score_gym2_mistys_wish() -> float:
	# Mild: drawing 1 OR a prize swap. Not high impact.
	if main.opponent_prize_cards.size() == 0:
		return -100.0
	if main.opponent_hand.size() <= 3:
		return 20.0
	return 10.0

func _cpu_score_gym2_blaines_quiz_2() -> float:
	# 50/50 — symmetric.
	if main.opponent_hand.size() >= 7:
		return -20.0
	return 12.0

func _cpu_score_gym2_blaines_quiz_3() -> float:
	# 50/50 with 3-card payout — slightly better than Quiz #2.
	if main.opponent_hand.size() >= 6:
		return -20.0
	return 18.0

func _cpu_score_gym2_koga_ninja_trick() -> float:
	# Need a Koga-named active
	if main.opponent_active_pokemon == null:
		return -100.0
	if not ("Koga" in main.opponent_active_pokemon.metadata.get("name", "")):
		return -100.0
	# Useful when the bench has a stronger defender to swap to
	if main.opponent_bench.size() == 0:
		return 0.0
	return 35.0

func _cpu_score_gym2_master_ball() -> float:
	if main.opponent_deck.size() == 0:
		return -100.0
	# Strong tutor — 7 cards is a lot of pickup space
	if main.opponent_hand.size() <= 4:
		return 65.0
	return 35.0

func _cpu_score_gym2_max_revive(card: card_object) -> float:
	if main.opponent_bench.size() >= main.get_max_bench_size():
		return -100.0
	# Need 2 Energy in hand
	var e = 0
	for c in main.opponent_hand:
		if c == card:
			continue
		if c.metadata.get("supertype", "") == "Energy":
			e += 1
	if e < 2:
		return -100.0
	# Useful when a strong basic is in discard
	var best_score = 0
	for c in main.opponent_discard_pile:
		if main.is_basic_pokemon(c):
			var result = evaluate_opponents_start_setup_pokemon_choices(c, main.opponent_hand)
			best_score = max(best_score, result.get("total_score", 0))
	if best_score >= 250:
		return 55.0
	if best_score > 0:
		return 25.0
	return -100.0

func _cpu_score_gym2_mistys_tears(card: card_object) -> float:
	# Discard 1 → search 2 Water Energy. Need water-aligned attackers in play.
	var avail = 0
	for c in main.opponent_hand:
		if c != card:
			avail += 1
	if avail < 1:
		return -100.0
	# Any Water Energy still in deck?
	var has_water = false
	for c in main.opponent_deck:
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Water Energy":
			has_water = true
			break
	if not has_water:
		return -100.0
	# Want a Water-type attacker on field
	for p in get_all_cpu_field_pokemon():
		if "Water" in p.metadata.get("types", []):
			return 55.0
	return 10.0

func _cpu_score_gym2_rockets_secret_experiment() -> float:
	# Heads = best tutor in the game; tails = trainer lock on SELF (bad).
	# 50/50 — only play it when hand is thin and we can afford the lock risk.
	if main.opponent_hand.size() <= 2:
		return 45.0
	return 10.0

func _cpu_score_gym2_sabrinas_psychic_control() -> float:
	# 50% to use one of player's discarded trainers. Score based on what's there.
	var opp_discard = main.player_discard_pile
	var best = 0.0
	for c in opp_discard:
		if not main.trainer_effects.is_trainer_card(c):
			continue
		if main.trainer_effects.is_attached_trainer(c) or main.trainer_effects.is_bench_token_trainer(c) or main.trainer_effects.is_stadium_trainer(c):
			continue
		best = max(best, cpu_score_trainer_card(c))
	if best <= 30:
		return -50.0
	return best * 0.5  # half the value (50% chance)

func _cpu_score_gym2_fervor() -> float:
	# Top-3 reveal; Fire Energy to hand, rest to discard. Worth it if Fire is a major energy type for our deck.
	var fire_in_deck = 0
	for c in main.opponent_deck:
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Fire Energy":
			fire_in_deck += 1
	if fire_in_deck == 0:
		return -100.0
	# Probability-ish weighting
	if fire_in_deck >= 8:
		return 40.0
	if fire_in_deck >= 4:
		return 20.0
	return 5.0

func _cpu_score_gym2_transparent_walls() -> float:
	# Useful when the player has bench-damage attacks or we're protecting setup.
	if main.opponent_bench.size() <= 1:
		return -20.0
	# Check if any of our bench is at risk (low HP)
	for bp in main.opponent_bench:
		var max_hp = int(bp.metadata.get("hp", "0"))
		if bp.current_hp <= max_hp / 2:
			return 50.0
	return 20.0

func _cpu_score_gym2_warp_point() -> float:
	# Forces opp's bench swap AND your own. Good when player's active is hard to KO and a weaker bench exists.
	if main.player_bench.size() == 0:
		return -50.0
	# Score by whether a weaker player-bench would be a better target
	var p_active = main.player_active_pokemon
	if p_active == null:
		return -50.0
	for bp in main.player_bench:
		var bp_hp = int(bp.metadata.get("hp", "0"))
		var pa_hp = int(p_active.metadata.get("hp", "0"))
		if bp_hp < pa_hp:
			return 45.0
	return 15.0

############################################# GYM1 (GYM HEROES) STADIUM SCORING #####################################################

# Returns the number of CPU pokemon in play (active + bench) whose name contains the given substring.
func _cpu_count_named_pokemon_in_play(name_substring: String) -> int:
	var n = 0
	if main.opponent_active_pokemon != null and name_substring in main.opponent_active_pokemon.metadata.get("name", ""):
		n += 1
	for bp in main.opponent_bench:
		if name_substring in bp.metadata.get("name", ""):
			n += 1
	return n

# Returns the count of player pokemon in play whose name contains the substring (for "stadium helps opponent" checks)
func _player_count_named_pokemon_in_play(name_substring: String) -> int:
	var n = 0
	if main.player_active_pokemon != null and name_substring in main.player_active_pokemon.metadata.get("name", ""):
		n += 1
	for bp in main.player_bench:
		if name_substring in bp.metadata.get("name", ""):
			n += 1
	return n

# Generic check: does the current stadium already benefit the CPU? If yes, avoid overwriting it.
func _cpu_current_stadium_helps_cpu() -> bool:
	if main.current_stadium_card == null:
		return false
	# If CPU played the current stadium, assume it's helpful to them
	if main.current_stadium_owner_is_opponent:
		return true
	# Otherwise check: if the active stadium is one of the synergy stadiums and CPU has matching pokemon
	var uid = main.current_stadium_card.uid.to_lower()
	match uid:
		"gym1-104": return false  # +1 retreat on Active hurts both equally; usually neutral
		"gym1-108": return _cpu_count_named_pokemon_in_play("Misty") > 0
		"gym1-115": return _cpu_count_named_pokemon_in_play("Brock") > 0
		"gym1-120": return _cpu_count_named_pokemon_in_play("Lt. Surge") > 0
	return false

# gym1-103 No Removal Gym — taxes opponent's Energy Removal/Super Energy Removal cards 2 hand discards each.
# Only useful if player is likely to use those. Assume modest base value.
func _cpu_score_gym1_no_removal_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	# Mild value — disrupts player removal cards. Higher if our active has lots of energy invested.
	var score = 15.0
	if main.opponent_active_pokemon != null:
		score += float(main.opponent_active_pokemon.attached_energies.size()) * 8.0
	return score

# gym1-104 Rocket's Training Gym — +1 retreat for both Active pokemon. Helps the side whose Active has high cost already.
func _cpu_score_gym1_rockets_training_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	# Bad if our own active needs to retreat soon; good if player's active wants to retreat
	if main.opponent_active_pokemon == null:
		return 0.0
	var our_cost = main.opponent_active_pokemon.metadata.get("retreatCost", []).size()
	var player_cost = 0
	if main.player_active_pokemon != null:
		player_cost = main.player_active_pokemon.metadata.get("retreatCost", []).size()
	# Score = how much it hurts player relative to us
	return float(player_cost - our_cost) * 12.0 + 5.0

# gym1-107 Celadon City Gym — needs Erika pokemon in deck/play to be valuable
func _cpu_score_gym1_celadon_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var erika_in_play = _cpu_count_named_pokemon_in_play("Erika")
	var erika_in_deck_hand = 0
	for c in main.opponent_deck:
		if "Erika" in c.metadata.get("name", ""):
			erika_in_deck_hand += 1
	for c in main.opponent_hand:
		if "Erika" in c.metadata.get("name", ""):
			erika_in_deck_hand += 1
	if erika_in_play == 0 and erika_in_deck_hand == 0:
		return -100.0
	return 20.0 + erika_in_play * 25.0 + erika_in_deck_hand * 5.0

# gym1-108 Cerulean City Gym — Misty-named pokemon retreat -1
func _cpu_score_gym1_cerulean_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var misty_count = _cpu_count_named_pokemon_in_play("Misty")
	var player_misty = _player_count_named_pokemon_in_play("Misty")
	if misty_count == 0 and player_misty == 0:
		return -100.0
	# Helps both sides equally, prefer if CPU has more
	return (misty_count - player_misty) * 30.0 + 10.0

# gym1-115 Pewter City Gym — Brock-named pokemon ignore resistance
func _cpu_score_gym1_pewter_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var brock_count = _cpu_count_named_pokemon_in_play("Brock")
	var player_brock = _player_count_named_pokemon_in_play("Brock")
	if brock_count == 0 and player_brock == 0:
		return -100.0
	return (brock_count - player_brock) * 30.0 + 10.0

# gym1-120 Vermilion City Gym — Lt. Surge attackers may flip for +10 / -10 self
func _cpu_score_gym1_vermilion_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var surge_count = _cpu_count_named_pokemon_in_play("Lt. Surge")
	var player_surge = _player_count_named_pokemon_in_play("Lt. Surge")
	if surge_count == 0 and player_surge == 0:
		return -100.0
	return (surge_count - player_surge) * 30.0 + 10.0

# gym1-124 Narrow Gym — bench cap reduced to 4. Good when opponent has 5 bench (forces a return).
func _cpu_score_gym1_narrow_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	# Bad if CPU itself has 5 bench
	if main.opponent_bench.size() >= 5:
		return -100.0
	var score = 0.0
	if main.player_bench.size() >= 5:
		score += 60.0  # forces player to return one
	# Score by how much CPU has bench room headroom vs player
	score += float(main.player_bench.size() - main.opponent_bench.size()) * 10.0
	return score

############################################# GYM2 (GYM CHALLENGE) STADIUM SCORING ##################################################

# gym2-102 Chaos Gym — Every non-stadium trainer played has a 50% chance of fizzling.
# Good when player relies on trainers heavily AND CPU has few trainers in hand (so it doesn't backfire).
func _cpu_score_gym2_chaos_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	# Count trainers in CPU's own hand vs estimate of player's reliance
	var cpu_trainers_in_hand = 0
	for c in main.opponent_hand:
		if main.trainer_effects.is_trainer_card(c) and not main.trainer_effects.is_stadium_trainer(c):
			cpu_trainers_in_hand += 1
	# Heuristic: each CPU trainer-in-hand is -10 (fizzle risk); player hand size > 5 is +5 each over (probably has trainers)
	var score = 25.0
	score -= cpu_trainers_in_hand * 10.0
	if main.player_hand.size() > 5:
		score += (main.player_hand.size() - 5) * 5.0
	return score

# gym2-109 Resistance Gym — All Resistance reduced by 20. Helps whichever side ATTACKS pokemon with Resistance.
# Hard to tell at score time who'll benefit more; assume neutral-positive when player's active has resistance.
func _cpu_score_gym2_resistance_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var score = 5.0
	# +25 if player's active has resistance
	if main.player_active_pokemon != null and main.player_active_pokemon.metadata.get("resistances", []).size() > 0:
		score += 25.0
	# -25 if CPU's active has resistance (we'd lose protection)
	if main.opponent_active_pokemon != null and main.opponent_active_pokemon.metadata.get("resistances", []).size() > 0:
		score -= 25.0
	return score

# gym2-113 Cinnabar City Gym — Water Pokemon ignore Weakness vs Blaine pokemon. Useful for Blaine decks vs Water threats.
func _cpu_score_gym2_cinnabar_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var cpu_blaine = _cpu_count_named_pokemon_in_play("Blaine")
	var player_blaine = _player_count_named_pokemon_in_play("Blaine")
	if cpu_blaine == 0 and player_blaine == 0:
		return -100.0
	# Cinnabar HURTS the side with Blaine pokemon (their Weakness to Water becomes ignored), so prefer ONLY if player has Blaine and CPU doesn't
	# Wait — re-read: "Ignore Weakness when a Water Pokemon does damage to a Blaine pokemon"
	# So a Water attacker getting +0 instead of doubled means LESS damage to the Blaine defender. This HELPS the Blaine side.
	# So CPU plays it if CPU has Blaine pokemon (especially Fire types — Blaine pokemon are weak to Water).
	return (cpu_blaine - player_blaine) * 30.0 + 10.0

# gym2-114 Fuchsia City Gym — once-per-turn Koga shuffle recovery
func _cpu_score_gym2_fuchsia_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var cpu_koga = _cpu_count_named_pokemon_in_play("Koga")
	var koga_in_deck_hand = 0
	for c in main.opponent_deck:
		if "Koga" in c.metadata.get("name", ""):
			koga_in_deck_hand += 1
	for c in main.opponent_hand:
		if "Koga" in c.metadata.get("name", ""):
			koga_in_deck_hand += 1
	if cpu_koga == 0 and koga_in_deck_hand == 0:
		return -100.0
	return 15.0 + cpu_koga * 20.0 + koga_in_deck_hand * 3.0

# gym2-119 Rocket's Minefield Gym — coin flip per Basic benched from hand; tails = 20 damage
# Good when CPU has its bench mostly set up and player is still benching pokemon.
func _cpu_score_gym2_rockets_minefield_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	# Bad if CPU still has many Basics in hand to bench
	var cpu_basics_in_hand = 0
	for c in main.opponent_hand:
		if main.is_basic_pokemon(c):
			cpu_basics_in_hand += 1
	var score = 30.0
	score -= cpu_basics_in_hand * 12.0
	# Better if our bench is already set up
	if main.opponent_bench.size() >= 3:
		score += 15.0
	return score

# gym2-122 Saffron City Gym — return basic Energy from Sabrina pokemon to hand (recycle)
func _cpu_score_gym2_saffron_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var cpu_sabrina = _cpu_count_named_pokemon_in_play("Sabrina")
	var sabrina_in_deck_hand = 0
	for c in main.opponent_deck:
		if "Sabrina" in c.metadata.get("name", ""):
			sabrina_in_deck_hand += 1
	for c in main.opponent_hand:
		if "Sabrina" in c.metadata.get("name", ""):
			sabrina_in_deck_hand += 1
	if cpu_sabrina == 0 and sabrina_in_deck_hand == 0:
		return -100.0
	return 10.0 + cpu_sabrina * 20.0 + sabrina_in_deck_hand * 2.0

# gym2-123 Viridian City Gym — Giovanni pokemon heal 20 (or 10) when evolving
func _cpu_score_gym2_viridian_city_gym() -> float:
	if _cpu_current_stadium_helps_cpu():
		return -50.0
	var cpu_giovanni = _cpu_count_named_pokemon_in_play("Giovanni")
	var giovanni_in_deck_hand = 0
	for c in main.opponent_deck:
		if "Giovanni" in c.metadata.get("name", ""):
			giovanni_in_deck_hand += 1
	for c in main.opponent_hand:
		if "Giovanni" in c.metadata.get("name", ""):
			giovanni_in_deck_hand += 1
	if cpu_giovanni == 0 and giovanni_in_deck_hand == 0:
		return -100.0
	return 15.0 + cpu_giovanni * 15.0 + giovanni_in_deck_hand * 3.0
