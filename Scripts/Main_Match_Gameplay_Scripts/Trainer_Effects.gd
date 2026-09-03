extends Node

######################################################################################################################################################
############################################################## TRAINER EFFECTS #####################################################################
######################################################################################################################################################
#
# This file contains trainer card effects, Pokémon Powers, and related helpers.
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

# ── Trainer dispatch registry ──────────────────────────────────────────────────
# Maps lowercased card UID → async Callable(card, is_opponent).
# Add new set registrations by calling _register_<set>_trainers() from _ensure_trainer_dispatch_ready().
var _trainer_dispatch: Dictionary = {}
var _trainer_dispatch_ready := false

func _ensure_trainer_dispatch_ready() -> void:
	if _trainer_dispatch_ready:
		return
	_trainer_dispatch_ready = true
	_register_base_trainers()
	_register_gym1_trainers()
	_register_gym2_trainers()
	_register_basep_trainers()
	_register_neo1_trainers()
	_register_neo2_trainers()
	_register_neo3_trainers()
	_register_neo4_trainers()
	_register_np_trainers()
	_register_ecard1_trainers()
	_register_ecard2_trainers()
	_register_ecard3_trainers()
	_register_ex1_trainers()
	_register_ex2_trainers()
	_register_ex3_trainers()
	_register_ex4_trainers()
	_register_ex5_trainers()
	_register_ex6_trainers()
	_register_ex7_trainers()
	_register_ex8_trainers()
	_register_ex9_trainers()
	_register_ex10_trainers()
	_register_ex11_trainers()
	_register_ex12_trainers()
	_register_ex13_trainers()
	_register_ex14_trainers()
	_register_ex15_trainers()
	_register_ex16_trainers()
	_register_pop_trainers()

# EX9 (EX EMERALD) trainers. Most are reprints of ex1/ex2 cards — reuse the existing effect functions
# with the ex9 UID. Lum Berry (ex9-78) / Oran Berry (ex9-80) are Pokemon Tools whose attach is generic
# and whose between-turns effect is ex1_lum_berry_check / ex1_oran_berry_check (ex9 UIDs added there).
# Battle Frontier (ex9-75) is a Stadium that resolves generically; its passive effect lives in
# is_power_blocked / battle_frontier_disables (Powers_And_Bodies_Effects).
func _register_ex9_trainers() -> void:
	_trainer_dispatch["ex9-76"] = func(c, opp): await effect_ex2_double_full_heal(opp)      # Double Full Heal (Item)
	_trainer_dispatch["ex9-77"] = func(c, opp): await effect_ex2_lanettes_net_search(opp)   # Lanette's Net Search (Supporter)
	_trainer_dispatch["ex9-79"] = func(c, opp): await effect_ex9_mr_stones_project(opp)     # Mr. Stone's Project (Supporter)
	_trainer_dispatch["ex9-81"] = func(c, opp): await effect_ex1_pokenav(opp)               # PokéNav (Item)
	_trainer_dispatch["ex9-82"] = func(c, opp): await effect_ex1_professor_birch(opp)       # Professor Birch (Supporter)
	_trainer_dispatch["ex9-83"] = func(c, opp): await effect_ex2_rare_candy(opp)            # Rare Candy (Item)
	_trainer_dispatch["ex9-84"] = func(c, opp): await effect_ex9_scott(opp)                 # Scott (Supporter)
	_trainer_dispatch["ex9-85"] = func(c, opp): await effect_ex2_wallys_training(opp)       # Wally's Training (Supporter)

# MR. STONE'S PROJECT (ex9-79, Supporter): search your deck for up to 2 basic Energy cards and put
# them into your hand; OR search your discard pile for up to 2 basic Energy cards and put them into
# your hand (deck version shuffles afterward).
func effect_ex9_mr_stones_project(is_opponent: bool) -> void:
	var from_discard := false
	if is_opponent:
		# CPU: prefer the deck (keeps the discard as a fallback resource).
		from_discard = false
	else:
		from_discard = await gym1_prompt_yes_no(main.player_active_pokemon, "MR. STONE'S PROJECT", "Search your DECK or your DISCARD PILE for up to 2 basic Energy?", "DECK", "DISCARD") == false
	var energy_filter = func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", [])
	if not from_discard:
		var found = await main.card_ops.search_deck_to_hand(is_opponent, energy_filter, "MR. STONE'S PROJECT: CHOOSE UP TO 2 BASIC ENERGY", 2)
		if main._should_bail(): return
		await main.show_message("MR. STONE'S PROJECT! ADDED " + str(found.size()) + " ENERGY TO HAND!" if found.size() > 0 else "NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
	else:
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		var pool = discard.filter(energy_filter)
		if pool.is_empty():
			await main.show_message("MR. STONE'S PROJECT: NO BASIC ENERGY IN DISCARD PILE!")
			if main._should_bail(): return
			return
		var taken := 0
		for i in range(2):
			pool = discard.filter(energy_filter)
			if pool.is_empty(): break
			var pick: card_object
			if is_opponent:
				pick = main.cpu_ai.cpu_pick_best_keep(pool)  # recover the Energy type the attacker needs
			else:
				pick = await main.card_ops.prompt_select_card(pool, "MR. STONE'S PROJECT", "Choose a basic Energy from your discard pile (or cancel to stop)", "TAKE", true, true)
				if main._should_bail(): return
				if pick == null: break
			await main.card_ops.recover_to_hand(pick, is_opponent)
			if main._should_bail(): return
			taken += 1
		await main.show_message("MR. STONE'S PROJECT! RECOVERED " + str(taken) + " ENERGY FROM THE DISCARD PILE!")
		if main._should_bail(): return
	print("TRAINER: Mr. Stone's Project")

# SCOTT (ex9-84, Supporter): search your deck for up to 3 cards in any combination of Supporter and
# Stadium cards and put them into your hand. Shuffle your deck afterward.
func effect_ex9_scott(is_opponent: bool) -> void:
	var filter_fn = func(c):
		if c.metadata.get("supertype","") != "Trainer": return false
		var st = c.metadata.get("subtypes", [])
		return "Supporter" in st or "Stadium" in st
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "SCOTT: CHOOSE UP TO 3 SUPPORTER/STADIUM CARDS", 3)
	if main._should_bail(): return
	await main.show_message("SCOTT! ADDED " + str(found.size()) + " CARD(S) TO HAND!" if found.size() > 0 else "NO SUPPORTER/STADIUM CARDS IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Scott — found ", found.size())

func _register_ex8_trainers() -> void:
	_trainer_dispatch["ex8-86"] = func(c, opp): await effect_ex8_energy_charge(opp)                  # Energy Charge (Item)
	_trainer_dispatch["ex8-87"] = func(c, opp): await effect_ex8_lady_outing(opp)                    # Lady Outing (Supporter)
	_trainer_dispatch["ex8-88"] = func(c, opp): await effect_ex8_master_ball(opp)                    # Master Ball (Item)
	_trainer_dispatch["ex8-90"] = func(c, opp): await effect_ex8_professor_cozmos_discovery(opp)     # Professor Cozmo's Discovery (Supporter)
	# ex8-84 Balloon Berry, ex8-85 Crystal Shard, ex8-92 Strength Charm are Pokémon Tools (generic
	# attach path); ex8-89 Meteor Falls & ex8-91 Space Center are Stadiums (passive, resolved generically).

# ENERGY CHARGE (ex8-86, Item): flip a coin. If heads, search your discard for 2 Energy cards (1 if only
# 1), show them, and shuffle them into your deck.
func effect_ex8_energy_charge(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENERGY CHARGE FAILED!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var moved = 0
	while moved < 2:
		var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy")
		if pool.is_empty(): break
		var chosen: card_object
		if is_opponent:
			chosen = main.cpu_ai.cpu_pick_best_keep(pool)  # recycle the most useful Energy back into the deck
		else:
			chosen = await main.card_ops.choose_card(pool, false, "ENERGY CHARGE", "Choose an Energy to shuffle into your deck (" + str(moved + 1) + " of 2)", "SELECT", moved > 0, Callable(), true)
			if main._should_bail(): return
			if chosen == null: break
		discard.erase(chosen)
		chosen.current_location = "deck"
		deck.append(chosen)
		moved += 1
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("ENERGY CHARGE! SHUFFLED " + str(moved) + " ENERGY INTO YOUR DECK!")
	if main._should_bail(): return

# LADY OUTING (ex8-87, Supporter): search your deck for up to 3 different types of basic Energy cards
# and put them into your hand.
func effect_ex8_lady_outing(is_opponent: bool) -> void:
	var chosen_types: Array = []
	var found = 0
	while found < 3:
		var pool = _ex8_basic_energy_pool(is_opponent, chosen_types)
		if pool.is_empty(): break
		var chosen: card_object
		if is_opponent:
			chosen = main.cpu_ai.cpu_pick_best_keep(pool)  # fetch a basic Energy type the attacker actually needs
		else:
			chosen = await main.card_ops.choose_card(pool, false, "LADY OUTING", "Choose a basic Energy of a NEW type (" + str(found + 1) + " of 3)", "SELECT", found > 0, Callable(), true)
			if main._should_bail(): return
			if chosen == null: break
		var deck = main.opponent_deck if is_opponent else main.player_deck
		var hand = main.opponent_hand if is_opponent else main.player_hand
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		for t in main.get_energy_provided_by_card(chosen):
			if t not in chosen_types: chosen_types.append(t)
		found += 1
	var deck2 = main.opponent_deck if is_opponent else main.player_deck
	deck2.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("LADY OUTING! ADDED " + str(found) + " BASIC ENERGY TO HAND!")
	if main._should_bail(): return

# Deck basic Energy cards whose provided type is not already among `exclude_types`.
func _ex8_basic_energy_pool(is_opponent: bool, exclude_types: Array) -> Array:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	return deck.filter(func(c):
		if c.metadata.get("supertype","") != "Energy": return false
		if "Basic" not in c.metadata.get("subtypes", []): return false
		for t in main.get_energy_provided_by_card(c):
			if t not in exclude_types: return true
		return false)

# MASTER BALL (ex8-88, Item): look at the top 7 cards of your deck, choose a Basic Pokemon or Evolution
# card, put it into your hand, and put the other 6 back on top; shuffle your deck afterward.
func effect_ex8_master_ball(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if deck.is_empty():
		await main.show_message("YOUR DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top: Array = []
	for i in range(min(7, deck.size())):
		top.append(deck[i])
	var pool = top.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
	if pool.is_empty():
		deck.shuffle()
		main.update_deck_icon(is_opponent)
		await main.show_message("MASTER BALL! NO POKEMON IN THE TOP 7.")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = main.cpu_ai.cpu_pick_best_keep(pool)  # fetch the Pokemon that completes a line / is playable now
	else:
		chosen = await main.card_ops.choose_card(pool, false, "MASTER BALL", "Choose a Basic Pokemon or Evolution card to put into your hand", "TAKE", false, Callable(), true)
		if main._should_bail(): return
		if chosen == null: chosen = pool[0]
	deck.erase(chosen)
	chosen.current_location = "hand"
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("MASTER BALL! ADDED " + chosen.metadata.get("name","").to_upper() + " TO HAND!")
	if main._should_bail(): return

# PROFESSOR COZMO'S DISCOVERY (ex8-90, Supporter): flip a coin. If heads, draw the bottom 3 cards of
# your deck. If tails, draw the top 2 cards of your deck.
func effect_ex8_professor_cozmos_discovery(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.show_message("HEADS! DRAW THE BOTTOM 3 CARDS!")
		if main._should_bail(): return
		var n = min(3, deck.size())
		for i in range(n):
			var c = deck[deck.size() - 1]
			deck.remove_at(deck.size() - 1)
			c.current_location = "hand"
			hand.append(c)
	else:
		await main.show_message("TAILS! DRAW THE TOP 2 CARDS!")
		if main._should_bail(): return
		await main.card_ops.draw_n(is_opponent, 2)
		if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if main._should_bail(): return

func _register_base_trainers() -> void:
	_trainer_dispatch["base1-88"] = func(c, opp): await effect_professor_oak(c, opp)
	_trainer_dispatch["base1-89"] = func(c, opp): await effect_revive(opp)
	_trainer_dispatch["base1-90"] = func(c, opp): await effect_super_potion(c, opp)
	_trainer_dispatch["base1-91"] = func(c, opp): await effect_bill(opp)
	_trainer_dispatch["base1-92"] = func(c, opp): await effect_energy_removal(opp)
	_trainer_dispatch["base1-93"] = func(c, opp): await effect_gust_of_wind(opp)
	_trainer_dispatch["base1-94"] = func(c, opp): await effect_potion(opp)
	_trainer_dispatch["base1-95"] = func(c, opp): await effect_switch(opp)
	_trainer_dispatch["base1-71"] = func(c, opp): await effect_computer_search(c, opp)
	_trainer_dispatch["base1-72"] = func(c, opp): await effect_devolution_spray(opp)
	_trainer_dispatch["base1-73"] = func(c, opp): await effect_impostor_professor_oak(opp)
	_trainer_dispatch["base1-74"] = func(c, opp): await effect_item_finder(c, opp)
	_trainer_dispatch["base1-75"] = func(c, opp): await effect_lass(opp)
	_trainer_dispatch["base1-76"] = func(c, opp): await effect_pokemon_breeder(opp)
	_trainer_dispatch["base1-77"] = func(c, opp): await effect_pokemon_trader(c, opp)
	_trainer_dispatch["base1-78"] = func(c, opp): await effect_scoop_up(opp)
	_trainer_dispatch["base1-79"] = func(c, opp): await effect_super_energy_removal(opp)
	_trainer_dispatch["base1-81"] = func(c, opp): await effect_energy_retrieval(c, opp)
	_trainer_dispatch["base1-82"] = func(c, opp): await effect_full_heal(opp)
	_trainer_dispatch["base1-83"] = func(c, opp): await effect_maintenance(c, opp)
	_trainer_dispatch["base1-85"] = func(c, opp): await effect_pokemon_center(opp)
	_trainer_dispatch["base1-86"] = func(c, opp): await effect_pokemon_flute(opp)
	_trainer_dispatch["base1-87"] = func(c, opp): await effect_pokedex(opp)
	_trainer_dispatch["base2-64"] = func(c, opp): await effect_poke_ball(opp)
	_trainer_dispatch["base3-58"] = func(c, opp): await effect_mr_fuji(opp)
	_trainer_dispatch["base3-59"] = func(c, opp): await effect_energy_search(opp)
	_trainer_dispatch["base3-60"] = func(c, opp): await effect_gambler(opp)
	_trainer_dispatch["base3-61"] = func(c, opp): await effect_recycle(opp)
	var fn_hctr = func(c, opp): await effect_here_comes_team_rocket(opp)
	_trainer_dispatch["base5-15"] = fn_hctr;  _trainer_dispatch["base5-71"] = fn_hctr
	var fn_rsa = func(c, opp): await effect_rockets_sneak_attack(opp)
	_trainer_dispatch["base5-16"] = fn_rsa;   _trainer_dispatch["base5-72"] = fn_rsa
	_trainer_dispatch["base5-73"] = func(c, opp): await effect_the_boss_way(opp)
	_trainer_dispatch["base5-74"] = func(c, opp): await effect_challenge(opp)
	_trainer_dispatch["base5-75"] = func(c, opp): await effect_digger(opp)
	_trainer_dispatch["base5-76"] = func(c, opp): await effect_imposter_oaks_revenge(c, opp)
	_trainer_dispatch["base5-77"] = func(c, opp): await effect_nightly_garbage_run(opp)
	_trainer_dispatch["base5-78"] = func(c, opp): await effect_goop_gas_attack(opp)
	_trainer_dispatch["base5-79"] = func(c, opp): await effect_sleep_trainer(opp)

func _register_gym1_trainers() -> void:
	var fn_brock = func(c, opp): await gym1_effect_brock(opp)
	_trainer_dispatch["gym1-15"] = fn_brock;  _trainer_dispatch["gym1-98"] = fn_brock
	var fn_erika = func(c, opp): await gym1_effect_erika(opp)
	_trainer_dispatch["gym1-16"] = fn_erika;  _trainer_dispatch["gym1-100"] = fn_erika
	var fn_surge = func(c, opp): await gym1_effect_lt_surge(opp)
	_trainer_dispatch["gym1-17"] = fn_surge;  _trainer_dispatch["gym1-101"] = fn_surge
	var fn_misty = func(c, opp): await gym1_effect_misty(c, opp)
	_trainer_dispatch["gym1-18"] = fn_misty;  _trainer_dispatch["gym1-102"] = fn_misty
	_trainer_dispatch["gym1-19"]  = func(c, opp): await gym1_effect_rockets_trap(opp)
	_trainer_dispatch["gym1-97"]  = func(c, opp): await gym1_effect_blaines_quiz(opp)
	_trainer_dispatch["gym1-105"] = func(c, opp): await gym1_effect_blaines_last_resort(opp)
	_trainer_dispatch["gym1-106"] = func(c, opp): await gym1_effect_brocks_training_method(opp)
	_trainer_dispatch["gym1-109"] = func(c, opp): await gym1_effect_erikas_maids(c, opp)
	_trainer_dispatch["gym1-110"] = func(c, opp): await gym1_effect_erikas_perfume(opp)
	_trainer_dispatch["gym1-111"] = func(c, opp): await gym1_effect_good_manners(opp)
	_trainer_dispatch["gym1-112"] = func(c, opp): await gym1_effect_lt_surges_treaty(opp)
	_trainer_dispatch["gym1-113"] = func(c, opp): await gym1_effect_minion_of_team_rocket(opp)
	_trainer_dispatch["gym1-114"] = func(c, opp): await gym1_effect_mistys_wrath(opp)
	_trainer_dispatch["gym1-116"] = func(c, opp): await gym1_effect_recall(opp)
	_trainer_dispatch["gym1-118"] = func(c, opp): await gym1_effect_secret_mission(opp)
	_trainer_dispatch["gym1-119"] = func(c, opp): await gym1_effect_tickling_machine(opp)
	_trainer_dispatch["gym1-121"] = func(c, opp): await gym1_effect_blaines_gamble(c, opp)
	_trainer_dispatch["gym1-122"] = func(c, opp): await gym1_effect_energy_flow(opp)
	_trainer_dispatch["gym1-123"] = func(c, opp): await gym1_effect_mistys_duel(opp)
	_trainer_dispatch["gym1-125"] = func(c, opp): await gym1_effect_sabrinas_gaze(opp)
	_trainer_dispatch["gym1-126"] = func(c, opp): await gym1_effect_trash_exchange(opp)

func _register_gym2_trainers() -> void:

	var fn_blaine = func(c, opp): await gym2_effect_blaine(opp)
	_trainer_dispatch["gym2-17"] = fn_blaine;  _trainer_dispatch["gym2-100"] = fn_blaine
	var fn_giovanni = func(c, opp): await gym2_effect_giovanni(opp)
	_trainer_dispatch["gym2-18"] = fn_giovanni; _trainer_dispatch["gym2-104"] = fn_giovanni
	var fn_koga = func(c, opp): await gym2_effect_koga(opp)
	_trainer_dispatch["gym2-19"] = fn_koga;    _trainer_dispatch["gym2-106"] = fn_koga
	var fn_sabrina = func(c, opp): await gym2_effect_sabrina(opp)
	_trainer_dispatch["gym2-20"] = fn_sabrina; _trainer_dispatch["gym2-110"] = fn_sabrina
	_trainer_dispatch["gym2-103"] = func(c, opp): await gym2_effect_erikas_kindness(opp)
	_trainer_dispatch["gym2-105"] = func(c, opp): await gym2_effect_giovannis_last_resort(opp)
	_trainer_dispatch["gym2-107"] = func(c, opp): await gym2_effect_lt_surges_secret_plan(opp)
	_trainer_dispatch["gym2-108"] = func(c, opp): await gym2_effect_mistys_wish(opp)
	_trainer_dispatch["gym2-111"] = func(c, opp): await gym2_effect_blaines_quiz_2(opp)
	_trainer_dispatch["gym2-112"] = func(c, opp): await gym2_effect_blaines_quiz_3(opp)
	_trainer_dispatch["gym2-116"] = func(c, opp): await gym2_effect_master_ball(opp)
	_trainer_dispatch["gym2-117"] = func(c, opp): await gym2_effect_max_revive(c, opp)
	_trainer_dispatch["gym2-118"] = func(c, opp): await gym2_effect_mistys_tears(c, opp)
	_trainer_dispatch["gym2-120"] = func(c, opp): await gym2_effect_rockets_secret_experiment(opp)
	_trainer_dispatch["gym2-121"] = func(c, opp): await gym2_effect_sabrinas_psychic_control(opp)
	_trainer_dispatch["gym2-124"] = func(c, opp): await gym2_effect_fervor(opp)
	_trainer_dispatch["gym2-125"] = func(c, opp): await gym2_effect_transparent_walls(opp)
	_trainer_dispatch["gym2-126"] = func(c, opp): await gym2_effect_warp_point(opp)

func _register_basep_trainers() -> void:
	_trainer_dispatch["basep-16"] = func(c, opp): await effect_computer_error(opp)
	_trainer_dispatch["basep-40"] = func(c, opp): await effect_pokemon_center(opp)
	# basep-41 Lucky Stadium and basep-42 Pokemon Tower are handled via resolve_stadium_trainer

func _register_neo1_trainers() -> void:
	_trainer_dispatch["neo1-83"] = func(c, opp): await effect_neo1_arcade_game(opp)
	# neo1-84 Ecogym and neo1-97 Sprout Tower are stadiums — handled via resolve_stadium_trainer
	_trainer_dispatch["neo1-85"] = func(c, opp): await effect_neo1_energy_charge(opp)
	# neo1-86 Focus Band, neo1-93 Gold Berry, neo1-94 Miracle Berry, neo1-99 Berry — attached tools
	_trainer_dispatch["neo1-87"] = func(c, opp): await effect_neo1_mary(opp)
	_trainer_dispatch["neo1-88"] = func(c, opp): await effect_neo1_pokegear(opp)
	_trainer_dispatch["neo1-89"] = func(c, opp): await effect_neo1_super_energy_retrieval(c, opp)
	_trainer_dispatch["neo1-90"] = func(c, opp): await effect_neo1_time_capsule(opp)
	_trainer_dispatch["neo1-91"] = func(c, opp): await effect_neo1_bills_teleporter(opp)
	_trainer_dispatch["neo1-92"] = func(c, opp): await effect_neo1_card_flip_game(opp)
	_trainer_dispatch["neo1-95"] = func(c, opp): await effect_neo1_new_pokedex(opp)
	_trainer_dispatch["neo1-96"] = func(c, opp): await effect_neo1_professor_elm(c, opp)
	_trainer_dispatch["neo1-98"] = func(c, opp): await effect_neo1_super_scoop_up(opp)
	_trainer_dispatch["neo1-100"] = func(c, opp): await effect_neo1_double_gust(opp)
	_trainer_dispatch["neo1-101"] = func(c, opp): await effect_neo1_moo_moo_milk(opp)
	_trainer_dispatch["neo1-102"] = func(c, opp): await effect_neo1_pokemon_march(opp)
	_trainer_dispatch["neo1-103"] = func(c, opp): await effect_neo1_super_rod(opp)

# ── Trainer validation registry ────────────────────────────────────────────────
# Maps lowercased card UID → Callable(card, is_opponent) -> String.
# Returns "" if valid, or an error message string if the card cannot be played.
# Global checks (trainer lock, Hay Fever) are handled inline in validate_trainer_can_be_played.
var _validator_dispatch: Dictionary = {}
var _validator_dispatch_ready := false

func _ensure_validator_dispatch_ready() -> void:
	if _validator_dispatch_ready:
		return
	_validator_dispatch_ready = true
	_register_base_validations()
	_register_gym1_validations()
	_register_gym2_validations()
	_register_ex5_validations()
	_register_ex11_validations()
	_register_ex13_validations()
	_register_ex14_validations()
	_register_ex16_validations()
	# When adding Neo1/Neo2/etc., append: _register_neo1_validations()

func _register_base_validations() -> void:
	_validator_dispatch["base1-76"] = func(c, opp):  # Pokemon Breeder
		var hand = main.opponent_hand if opp else main.player_hand
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		var bench = main.opponent_bench if opp else main.player_bench
		var stage2_cards = hand.filter(func(x): return x != c and "Stage 2" in x.metadata.get("subtypes",[]))
		if stage2_cards.is_empty(): return "No Stage 2 Pokemon in hand to play!"
		var all_in_play = ([] + ([active] if active else []) + bench)
		for s2 in stage2_cards:
			for p in all_in_play:
				if not p.placed_on_field_this_turn and main.is_basic_pokemon(p) and _basic_matches_stage2(p, s2):
					return ""
		return "No valid Basic Pokemon to evolve with Breeder!"

	_validator_dispatch["base1-72"] = func(c, opp):  # Devolution Spray
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		var bench = main.opponent_bench if opp else main.player_bench
		if active != null and active.attached_pre_evolutions.size() > 0: return ""
		for bp in bench:
			if bp.attached_pre_evolutions.size() > 0: return ""
		return "No evolved Pokemon to devolve!"

	_validator_dispatch["base1-94"] = func(c, opp):  # Potion
		var damaged = build_field_pokemon_array(opp).filter(func(p): return p.current_hp < int(p.metadata.get("hp","0")))
		return "" if damaged.size() > 0 else "No Pokemon with damage to heal!"

	_validator_dispatch["base1-90"] = func(c, opp):  # Super Potion
		for p in build_field_pokemon_array(opp):
			if p.current_hp < int(p.metadata.get("hp","0")) and p.attached_energies.size() > 0: return ""
		return "No Pokemon with both damage and energy for Super Potion!"

	_validator_dispatch["base1-92"] = func(c, opp):  # Energy Removal
		for p in build_field_pokemon_array(not opp):
			if p.attached_energies.size() > 0:
				if main.is_stadium_in_play(StadiumIds.NO_REMOVAL_GYM):
					var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
					if others.size() < 2: return "No Removal Gym: need 2 other cards in hand!"
				return ""
		return "Opponent has no energy to remove!"

	_validator_dispatch["base1-79"] = func(c, opp):  # Super Energy Removal
		var own_has_e = build_field_pokemon_array(opp).any(func(p): return p.attached_energies.size() > 0)
		if not own_has_e: return "You have no energy to discard for Super Energy Removal!"
		var opp_has_e = build_field_pokemon_array(not opp).any(func(p): return p.attached_energies.size() > 0)
		if not opp_has_e: return "Opponent has no energy to remove!"
		if main.is_stadium_in_play(StadiumIds.NO_REMOVAL_GYM):
			var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
			if others.size() < 2: return "No Removal Gym: need 2 other cards in hand!"
		return ""

	_validator_dispatch["base1-70"] = func(c, opp):  # Clefairy Doll
		var bench = main.opponent_bench if opp else main.player_bench
		return "" if bench.size() < main.get_max_bench_size() else "Bench is full! Cannot place Clefairy Doll!"

	_validator_dispatch["base1-71"] = func(c, opp):  # Computer Search
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 2 else "Need at least 2 other cards in hand to discard!"

	_validator_dispatch["base1-74"] = func(c, opp):  # Item Finder
		var hand = main.opponent_hand if opp else main.player_hand
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		if hand.filter(func(x): return x != c).size() < 2: return "Need at least 2 other cards in hand to discard!"
		if discard.filter(func(x): return is_trainer_card(x)).is_empty(): return "No Trainer cards in the discard pile!"
		return ""

	_validator_dispatch["base1-81"] = func(c, opp):  # Energy Retrieval
		var hand = main.opponent_hand if opp else main.player_hand
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		if discard.filter(func(x): return main.is_basic_energy_card(x)).is_empty(): return "No Basic Energy in discard pile!"
		if hand.filter(func(x): return x != c).is_empty(): return "Need at least 1 other card in hand to discard!"
		return ""

	_validator_dispatch["base1-83"] = func(c, opp):  # Maintenance
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 2 else "Need at least 2 other cards in hand!"

	_validator_dispatch["base1-89"] = func(c, opp):  # Revive
		var bench = main.opponent_bench if opp else main.player_bench
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		if bench.size() >= main.get_max_bench_size(): return "Bench is full!"
		if discard.filter(func(x): return main.is_basic_pokemon(x)).is_empty(): return "No Basic Pokemon in discard pile!"
		return ""

	_validator_dispatch["base1-93"] = func(c, opp):  # Gust of Wind
		var opp_bench = main.player_bench if opp else main.opponent_bench
		return "" if opp_bench.size() > 0 else "Opponent has no bench Pokemon!"

	_validator_dispatch["base1-95"] = func(c, opp):  # Switch
		var bench = main.opponent_bench if opp else main.player_bench
		return "" if bench.size() > 0 else "No bench Pokemon to switch with!"

	_validator_dispatch["base1-86"] = func(c, opp):  # Pokemon Flute
		var opp_bench = main.player_bench if opp else main.opponent_bench
		if opp_bench.size() >= 5: return "Opponent's bench is full!"
		var opp_discard = main.player_discard_pile if opp else main.opponent_discard_pile
		return "" if opp_discard.any(func(x): return main.is_basic_pokemon(x)) else "No Basic Pokemon in opponent's discard pile!"

	_validator_dispatch["base1-82"] = func(c, opp):  # Full Heal
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		if active == null: return "No active Pokemon!"
		return "" if (active.special_condition != "" or active.is_poisoned or active.is_burned) else "Active Pokemon has no conditions to heal!"

	_validator_dispatch["base1-77"] = func(c, opp):  # Pokemon Trader
		var hand = main.opponent_hand if opp else main.player_hand
		var deck = main.opponent_deck if opp else main.player_deck
		if hand.filter(func(x): return x != c and x.metadata.get("supertype","").to_lower() == "pokémon").is_empty(): return "No Pokemon in hand to trade!"
		if deck.filter(func(x): return x.metadata.get("supertype","").to_lower() == "pokémon").is_empty(): return "No Pokemon in deck to trade for!"
		return ""

	var fn_rsa_v = func(c, opp):  # Rocket's Sneak Attack
		var target = main.player_hand if opp else main.opponent_hand
		return "" if target.any(func(x): return x.metadata.get("supertype","") == "Trainer") else "Opponent has no Trainer cards in hand!"
	_validator_dispatch["base5-16"] = fn_rsa_v;  _validator_dispatch["base5-72"] = fn_rsa_v

	_validator_dispatch["base5-73"] = func(c, opp):  # The Boss's Way
		var deck = main.opponent_deck if opp else main.player_deck
		for x in deck:
			var st = x.metadata.get("subtypes",[])
			if x.metadata.get("name","").begins_with("Dark ") and x.metadata.get("supertype","") == "Pokémon" and ("Stage 1" in st or "Stage 2" in st): return ""
		return "No Dark evolution cards in deck!"

	_validator_dispatch["base5-76"] = func(c, opp):  # Imposter Oak's Revenge
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 1 else "Need at least 1 other card in hand to discard!"

	_validator_dispatch["base5-77"] = func(c, opp):  # Nightly Garbage Run
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		for x in discard:
			if x.metadata.get("supertype","") == "Pokémon" or main.is_basic_energy_card(x): return ""
		return "No valid cards in discard pile!"

func _register_gym1_validations() -> void:
	var fn_brock_v = func(c, opp):  # gym1-15/98 Brock
		return "" if build_field_pokemon_array(opp).any(func(p): return p.current_hp < int(p.metadata.get("hp","0"))) else "No damaged Pokemon to heal!"
	_validator_dispatch["gym1-15"] = fn_brock_v;  _validator_dispatch["gym1-98"] = fn_brock_v

	var fn_surge_v = func(c, opp):  # gym1-17/101 Lt. Surge
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		var bench = main.opponent_bench if opp else main.player_bench
		var hand = main.opponent_hand if opp else main.player_hand
		if active == null: return "No Active Pokemon to swap!"
		if bench.size() >= main.get_max_bench_size(): return "Bench is full!"
		return "" if hand.any(func(x): return x != c and main.is_basic_pokemon(x)) else "No Basic Pokemon in hand!"
	_validator_dispatch["gym1-17"] = fn_surge_v;  _validator_dispatch["gym1-101"] = fn_surge_v

	var fn_misty_v = func(c, opp):  # gym1-18/102 Misty
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 2 else "Need at least 2 other cards to discard!"
	_validator_dispatch["gym1-18"] = fn_misty_v;  _validator_dispatch["gym1-102"] = fn_misty_v

	_validator_dispatch["gym1-19"]  = func(c, opp):  # Rocket's Trap
		var opp_hand = main.player_hand if opp else main.opponent_hand
		return "" if opp_hand.size() > 0 else "Opponent has no cards in hand!"

	_validator_dispatch["gym1-99"]  = func(c, opp):  # Charity
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		return "" if active != null else "No Active Pokemon to attach Charity to!"

	_validator_dispatch["gym1-105"] = func(c, opp):  # Blaine's Last Resort
		var hand = main.opponent_hand if opp else main.player_hand
		return "" if hand.filter(func(x): return x != c).is_empty() else "You may only play this when no other cards are in hand!"

	_validator_dispatch["gym1-106"] = func(c, opp):  # Brock's Training Method
		var deck = main.opponent_deck if opp else main.player_deck
		return "" if deck.any(func(x): return x.metadata.get("supertype","") == "Pokémon" and "Brock" in x.metadata.get("name","")) else "No Brock Pokemon in deck!"

	_validator_dispatch["gym1-109"] = func(c, opp):  # Erika's Maids
		var hand = main.opponent_hand if opp else main.player_hand
		var deck = main.opponent_deck if opp else main.player_deck
		if hand.filter(func(x): return x != c).size() < 2: return "Need at least 2 other cards to discard!"
		return "" if deck.any(func(x): return x.metadata.get("supertype","") == "Pokémon" and "Erika" in x.metadata.get("name","")) else "No Erika Pokemon in deck!"

	_validator_dispatch["gym1-110"] = func(c, opp):  # Erika's Perfume
		var opp_hand = main.player_hand if opp else main.opponent_hand
		return "" if opp_hand.size() > 0 else "Opponent has no cards in hand!"

	_validator_dispatch["gym1-111"] = func(c, opp):  # Good Manners
		var hand = main.opponent_hand if opp else main.player_hand
		var deck = main.opponent_deck if opp else main.player_deck
		for x in hand:
			if x != c and main.is_basic_pokemon(x): return "You can't play this with a Basic Pokemon in hand!"
		return "" if deck.any(func(x): return main.is_basic_pokemon(x)) else "No Basic Pokemon in deck!"

	_validator_dispatch["gym1-113"] = func(c, opp): return ""  # Minion — always playable

	_validator_dispatch["gym1-116"] = func(c, opp):  # Recall
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		if active == null: return "No Active Pokemon!"
		return "" if active.attached_pre_evolutions.size() > 0 else "Active has no Basic/Evolution cards to recall attacks from!"

	_validator_dispatch["gym1-117"] = func(c, opp):  # Sabrina's ESP
		return "" if build_field_pokemon_array(opp).any(func(p): return "Sabrina" in p.metadata.get("name","")) else "No Sabrina Pokemon in play!"

	_validator_dispatch["gym1-118"] = func(c, opp):  # Secret Mission
		var opp_hand = main.player_hand if opp else main.opponent_hand
		return "" if opp_hand.size() > 0 else "Opponent has no cards in hand!"

	_validator_dispatch["gym1-119"] = func(c, opp):  # Tickling Machine
		var opp_hand = main.player_hand if opp else main.opponent_hand
		return "" if opp_hand.size() > 0 else "Opponent has no cards in hand!"

	_validator_dispatch["gym1-121"] = func(c, opp):  # Blaine's Gamble
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 1 else "No other cards in hand to discard!"

	_validator_dispatch["gym1-122"] = func(c, opp):  # Energy Flow
		return "" if build_field_pokemon_array(opp).any(func(p): return p.attached_energies.size() > 0) else "No attached energies to return!"

	_validator_dispatch["gym1-126"] = func(c, opp):  # Trash Exchange
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		return "" if discard.size() > 0 else "Discard pile is empty!"

func _register_gym2_validations() -> void:
	var fn_blaine_v = func(c, opp):  # gym2-17/100 Blaine
		var hand = main.opponent_hand if opp else main.player_hand
		var ep = main.opponent_energy_played_this_turn if opp else main.player_energy_played_this_turn
		var used = main.opponent_blaine_double_attach_used if opp else main.player_blaine_double_attach_used
		if ep: return "You already attached your free Energy this turn!"
		if used: return "Blaine has already been played this turn!"
		var fire_count = hand.filter(func(x): return x != c and x.metadata.get("supertype","") == "Energy" and "Basic" in x.metadata.get("subtypes",[]) and x.metadata.get("name","") == "Fire Energy").size()
		if fire_count < 2: return "Need at least 2 Fire Energy in hand!"
		return "" if build_field_pokemon_array(opp).any(func(p): return "Blaine" in p.metadata.get("name","")) else "No Blaine Pokemon in play!"
	_validator_dispatch["gym2-17"] = fn_blaine_v;  _validator_dispatch["gym2-100"] = fn_blaine_v

	var fn_giovanni_v = func(c, opp):  # gym2-18/104 Giovanni
		return "" if build_field_pokemon_array(opp).any(func(p): return "Giovanni" in p.metadata.get("name","")) else "No Giovanni Pokemon in play!"
	_validator_dispatch["gym2-18"] = fn_giovanni_v; _validator_dispatch["gym2-104"] = fn_giovanni_v

	var fn_sabrina_v = func(c, opp):  # gym2-20/110 Sabrina
		var sabs = build_field_pokemon_array(opp).filter(func(p): return "Sabrina" in p.metadata.get("name",""))
		if sabs.size() < 2: return "Need at least 2 Sabrina Pokemon in play!"
		return "" if sabs.any(func(p): return p.attached_energies.size() > 0) else "No Sabrina Pokemon has energy to transfer!"
	_validator_dispatch["gym2-20"] = fn_sabrina_v; _validator_dispatch["gym2-110"] = fn_sabrina_v

	_validator_dispatch["gym2-101"] = func(c, opp):  # Brock's Protection
		return "" if build_field_pokemon_array(opp).any(func(p): return "Brock" in p.metadata.get("name","")) else "No Brock Pokemon in play!"

	_validator_dispatch["gym2-103"] = func(c, opp):  # Erika's Kindness
		for side in [opp, not opp]:
			if build_field_pokemon_array(side).any(func(p): return p.current_hp < int(p.metadata.get("hp","0"))): return ""
		return "No damaged Pokemon!"

	_validator_dispatch["gym2-105"] = func(c, opp):  # Giovanni's Last Resort
		for p in build_field_pokemon_array(opp):
			if "Giovanni" in p.metadata.get("name","") and p.current_hp < int(p.metadata.get("hp","0")): return ""
		return "No damaged Giovanni Pokemon!"

	_validator_dispatch["gym2-107"] = func(c, opp):  # Lt. Surge's Secret Plan
		var bench = main.opponent_bench if opp else main.player_bench
		var hand = main.opponent_hand if opp else main.player_hand
		if bench.size() >= main.get_max_bench_size(): return "Bench is full!"
		return "" if hand.size() > 1 else "No other cards in hand!"

	_validator_dispatch["gym2-108"] = func(c, opp):  # Misty's Wish
		var prizes = main.opponent_prize_cards if opp else main.player_prize_cards
		return "" if prizes.size() > 0 else "No Prize cards left!"

	var fn_bq_v = func(c, opp):  # Blaine's Quiz 2/3
		var others = (main.opponent_hand if opp else main.player_hand).filter(func(x): return x != c)
		return "" if others.size() >= 1 else "Need at least 1 other card in hand!"
	_validator_dispatch["gym2-111"] = fn_bq_v;  _validator_dispatch["gym2-112"] = fn_bq_v

	_validator_dispatch["gym2-115"] = func(c, opp):  # Koga's Ninja Trick
		var active = main.opponent_active_pokemon if opp else main.player_active_pokemon
		return "" if (active != null and "Koga" in active.metadata.get("name","")) else "Active Pokemon must have Koga in its name!"

	_validator_dispatch["gym2-116"] = func(c, opp):  # Master Ball
		var deck = main.opponent_deck if opp else main.player_deck
		return "" if deck.size() > 0 else "Deck is empty!"

	_validator_dispatch["gym2-117"] = func(c, opp):  # Max Revive
		var bench = main.opponent_bench if opp else main.player_bench
		var hand = main.opponent_hand if opp else main.player_hand
		var discard = main.opponent_discard_pile if opp else main.player_discard_pile
		if bench.size() >= main.get_max_bench_size(): return "Bench is full!"
		if hand.filter(func(x): return x != c and x.metadata.get("supertype","") == "Energy").size() < 2: return "Need at least 2 Energy cards in hand!"
		return "" if discard.any(func(x): return main.is_basic_pokemon(x)) else "No Basic Pokemon in discard pile!"

	_validator_dispatch["gym2-118"] = func(c, opp):  # Misty's Tears
		var hand = main.opponent_hand if opp else main.player_hand
		var deck = main.opponent_deck if opp else main.player_deck
		if hand.filter(func(x): return x != c).is_empty(): return "Need at least 1 other card to discard!"
		return "" if deck.any(func(x): return x.metadata.get("supertype","") == "Energy" and x.metadata.get("name","") == "Water Energy") else "No Water Energy in deck!"

	_validator_dispatch["gym2-121"] = func(c, opp):  # Sabrina's Psychic Control
		var opp_discard = main.player_discard_pile if opp else main.opponent_discard_pile
		for x in opp_discard:
			if is_trainer_card(x) and not is_attached_trainer(x) and not is_bench_token_trainer(x) and not is_stadium_trainer(x): return ""
		return "Opponent has no eligible Trainer cards in discard!"

	_validator_dispatch["gym2-124"] = func(c, opp):  # Fervor
		var deck = main.opponent_deck if opp else main.player_deck
		return "" if deck.size() > 0 else "Deck is empty!"

	_validator_dispatch["gym2-126"] = func(c, opp):  # Warp Point
		return "" if (main.player_bench.size() > 0 or main.opponent_bench.size() > 0) else "Neither player has benched Pokemon!"

# Trainer lock flags (Psyduck Headache)
var player_trainer_locked: bool = false
var opponent_trainer_locked: bool = false
var player_supporter_locked: bool = false   # ecard2 Addictive Pollen (Vileplume) — no Supporter cards this turn
var opponent_supporter_locked: bool = false
var player_trainer_except_supporter_locked: bool = false   # ex8 Disconnect (Manectric ex) — no non-Supporter Trainers this turn
var opponent_trainer_except_supporter_locked: bool = false

# EX1+: real TCG rule — only 1 Supporter card per turn. Retroactively covers every existing
# Supporter (ecard1-3 onward); reset at the start of each side's own turn.
var player_played_supporter_this_turn: bool = false
var opponent_played_supporter_this_turn: bool = false

func is_trainer_card(card: card_object) -> bool:
	return card.metadata.get("supertype", "").to_lower() == "trainer"

# Returns true if a card is a bench token trainer (Clefairy Doll, Mysterious Fossil)
func is_bench_token_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	# Bench tokens have an HP field in their metadata
	if card.metadata.has("hp") and int(card.metadata.get("hp", "0")) > 0:
		var rules = card.metadata.get("rules", [])
		for rule in rules:
			if "as if it were a basic" in rule.to_lower():
				return true
	return false

# Returns true if a card is an attached trainer (PlusPower, Defender, GYM1 Charity / Sabrina's ESP, GYM2 Brock's Protection / Koga's Ninja Trick)
func is_attached_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	var card_name = card.metadata.get("name", "").to_lower()
	if card_name in ["pluspower", "defender"]:
		return true
	# GYM1 attached tools
	var uid = card.uid.to_lower()
	if uid == "gym1-99" or uid == "gym1-117":
		return true
	# GYM2 attached tools
	if uid == "gym2-101" or uid == "gym2-115":
		return true
	# NEO1 Pokemon Tools
	if uid in ["neo1-86", "neo1-93", "neo1-94", "neo1-99"]:
		return true
	# NEO3 Pokemon Tools
	if uid == "neo3-60":
		return true
	# NEO4 Pokemon Tools (EXP.ALL, Counterattack Claws, Magnifier)
	if uid in ["neo4-93", "neo4-97", "neo4-101"]:
		return true
	# ECARD1 Strength Charm (Pokemon Tool) + Multi Technical Machine 01
	if uid in ["ecard1-150", "ecard1-144"]:
		return true
	# ECARD2 Weakness Guard (no Pokemon Tool subtype, but still an attach-effect card)
	if uid == "ecard2-141":
		return true
	# Any Pokémon Tool card (covers ecard2's Healing Berry/Memory Berry/Time Shard and future ones)
	if "Pokémon Tool" in card.metadata.get("subtypes", []):
		return true
	# Any Technical Machine card (ecard1-144, ecard2's 8 Cubes, and any future ones): all attach
	# to a field Pokemon and grant its attack instead of the holder's own
	if "Technical Machine" in card.metadata.get("subtypes", []):
		return true
	return false

# Returns true if a card is a stadium trainer (future-proofing)
func is_stadium_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	var subtypes = card.metadata.get("subtypes", [])
	for st in subtypes:
		if st.to_lower() == "stadium":
			return true
	return false

# Checks if Charizard's Energy Burn power is active on a pokemon
func is_double_colorless_energy(card: card_object) -> bool:
	return card.metadata.get("name", "") == "Double Colorless Energy"

############################################# END TRAINER CARD & POKEMON POWER FUNCTIONS ############################################################
######################################################################################################################################################


#           ########  ####    ##  #######  ##   ##  ########
#              ##     ## ##   ##  ##    ## ##   ##     ##
#              ##     ##  ##  ##  #######  ##   ##     ##
#              ##     ##   ## ##  ##       ##   ##     ##
#           ########  ##    ####  ##       #######     ##
######################################################################################################################################################
########################################################### USER INPUT ON CLICK FUNCTIONS ############################################################

# Card action button is the physical button that appears when in card selection mode, allows attaching energies, playing pokemon and trainer cards
func build_field_pokemon_array(is_opponent: bool) -> Array:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var combined = bench.duplicate()
	if active != null:
		combined.append(active)
	return combined

# Returns the lowest-priority cards from the CPU's hand for discarding
# exclude_card: the trainer card being played (must not be discarded)
func discard_pluspower_from_pokemon(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null or pokemon.pluspower_count <= 0:
		return
	# Remove PlusPower attached_cards
	var to_remove = []
	for card in pokemon.attached_cards:
		if card.metadata.get("name", "").to_lower() == "pluspower":
			to_remove.append(card)
	var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
	var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
	for card in to_remove:
		pokemon.attached_cards.erase(card)
		card.current_location = "discard"
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		discard.append(card)
		# Animate PlusPower from attached cards container to discard pile
		var card_texture = main.get_card_texture(card)
		await main.animate_card_a_to_b(attached_node, discard_node, 0.2, card_texture, main.card_scales[10])
		if main._should_bail(): return
	pokemon.pluspower_count = 0
	main.update_discard_pile_display(is_opponent)
	display_attached_trainer_cards(is_opponent)
	if to_remove.size() > 0:
		print("END OF TURN: Discarded ", to_remove.size(), " PlusPower(s) from ", pokemon.metadata.get("name", ""))

# Ticks down Defender turn counters and discards expired Defenders
func tick_defender_counters(is_opponent: bool) -> void:
	var all_pokemon = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)
	
	for pokemon in all_pokemon:
		if pokemon.defender_turns_remaining < 0:
			continue
		pokemon.defender_turns_remaining -= 1
		if pokemon.defender_turns_remaining < 0:
			# Discard the Defender card
			var to_remove = []
			for card in pokemon.attached_cards:
				if card.metadata.get("name", "").to_lower() == "defender":
					to_remove.append(card)
			var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
			var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
			for card in to_remove:
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
				discard.append(card)
				# Animate Defender from attached cards container to discard pile
				var card_texture = main.get_card_texture(card)
				await main.animate_card_a_to_b(attached_node, discard_node, 0.2, card_texture, main.card_scales[10])
			# ISSUE #90 FIX: the expiring Defenders were discarded but defender_count was left at its old
			# value (the PlusPower equivalent above always zeroed pluspower_count). defender_turns_remaining
			# going to -1 masked it — until the NEXT Defender was attached, which set turns back to 0 and did
			# defender_count += 1 on top of the phantom count. One physical Defender then blocked 40+ damage.
			pokemon.defender_count = 0
			print("ISSUE #90 FIX ACTIVE: cleared defender_count on ", pokemon.metadata.get("name", ""), " when its Defender(s) expired (", to_remove.size(), " discarded)")
			main.update_discard_pile_display(is_opponent)
			display_attached_trainer_cards(is_opponent)
			# ISSUE #59 (retest sub-issue 2): display_attached_trainer_cards only refreshes the ACTIVE
			# Pokémon's tool container. A Defender expiring on a BENCH Pokémon (whose tools are drawn by
			# build_pokemon_slot via display_pokemon) otherwise stayed on screen until the next full board
			# refresh — i.e. it "only vanished when the next defender was attached". Refresh the board too.
			main.display_pokemon(is_opponent)
			print("ISSUE #59 FIX ACTIVE: Defender discarded + board refreshed on ", pokemon.metadata.get("name", ""))

# Displays attached trainer cards (PlusPower, Defender) next to active pokemon
func display_attached_trainer_cards(is_opponent: bool) -> void:
	var container = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon

	# ISSUE #172: remove_child BEFORE queue_free. queue_free only takes effect at
	# the END of the frame, so the old peek-stack was still parented and still
	# being drawn while the new one was added on top of it — which is why a
	# discard could leave the wrong number of tool cards on screen and then look
	# like it discarded two on the following refresh. Detaching first makes the
	# rebuild atomic. Same trap the deck builder's grid and the attack row hit.
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	
	if active == null:
		return
	
	var card_size = main.card_scales[11]  # Same size as energy cards
	# ISSUE #160: the tool stack is clamped exactly like the energy stack, so a
	# fourth or fifth tool cannot walk off the edge of the board.
	var overlap_offset = main._stack_offset(active.attached_cards.size(), card_size.x)
	for i in range(active.attached_cards.size()):
		var attached = active.attached_cards[i]
		var display = TextureRect.new()
		display.set_script(main.card_display_script)
		container.add_child(display)
		display.load_card_image(attached.uid, card_size, attached)
		display.position.x = overlap_offset * i if is_opponent else -(i * overlap_offset)
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE

############################################### Section B: SHARED CPU DISCARD PRIORITY #############################################################

# Builds a combined array of bench + active pokemon with active last (for enlarged display with spacer)
func cpu_get_discard_priority(hand: Array, count: int, exclude_card: card_object = null) -> Array:
	var candidates = []
	for card in hand:
		if card == exclude_card:
			continue
		# Higher priority = keep (discarded last). The per-card override lets playtesting protect combo pieces.
		var priority = _score_card_for_discard(card) + main.cpu_ai.cpu_decision_override(card, "discard")
		candidates.append({"card": card, "priority": priority})
	
	# Sort by priority ascending (lowest priority = discard first)
	candidates.sort_custom(func(a, b): return a["priority"] < b["priority"])
	
	var result = []
	for i in range(min(count, candidates.size())):
		result.append(candidates[i]["card"])
	return result

# Scores a card for discard priority (lower = more likely to be discarded)
func _score_card_for_discard(card: card_object) -> float:
	var score = 50.0 # default middle
	var supertype = card.metadata.get("supertype", "").to_lower()
	var subtypes = card.metadata.get("subtypes", [])
	
	# Priority 1: Duplicate Basic Pokemon already in play
	if supertype == "pokémon" and main.is_basic_pokemon(card):
		var card_name = card.metadata.get("name", "")
		var already_in_play = false
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.metadata.get("name", "") == card_name:
			already_in_play = true
		for bp in main.opponent_bench:
			if bp.metadata.get("name", "") == card_name:
				already_in_play = true
		if already_in_play and main.opponent_bench.size() >= 2:
			return 10.0
	
	# Priority 2: Excess energy (if hand has 3+ energy cards)
	if supertype == "energy":
		var energy_count = 0
		for c in main.opponent_hand:
			if c.metadata.get("supertype", "").to_lower() == "energy":
				energy_count += 1
		if energy_count >= 4:
			return 15.0
		elif energy_count >= 3:
			return 25.0
		# Never discard last energy
		if energy_count <= 1:
			return 90.0
		return 40.0
	
	# Priority 3: Unplayable evolution cards
	if supertype == "pokémon" and not main.is_basic_pokemon(card):
		var evolves_from = card.metadata.get("evolvesFrom", "")
		var has_base_in_play = false
		var has_base_in_hand = false
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.metadata.get("name", "") == evolves_from:
			has_base_in_play = true
		for bp in main.opponent_bench:
			if bp.metadata.get("name", "") == evolves_from:
				has_base_in_play = true
		for c in main.opponent_hand:
			if c.metadata.get("name", "") == evolves_from:
				has_base_in_hand = true
		
		if not has_base_in_play and not has_base_in_hand:
			# Check if it's Stage 2 (never discard if possible)
			if "Stage 2" in subtypes:
				return 30.0
			return 20.0
		# Has matching base: high value, don't discard
		if "Stage 2" in subtypes:
			return 95.0
		return 80.0
	
	# Priority 4: Low-priority trainer cards
	if supertype == "trainer":
		var trainer_score = main.cpu_ai.cpu_score_trainer_card(card)
		if trainer_score <= 0:
			return 18.0
		if trainer_score <= 30:
			return 35.0
		return 70.0
	
	# Priority 5: Basic pokemon with full bench
	if supertype == "pokémon" and main.is_basic_pokemon(card):
		if main.opponent_bench.size() >= 4:
			return 22.0
		return 55.0
	
	return score

############################################### Section C: TRAINER CARD PLAY ANIMATION ##############################################################

# Validates whether a trainer card can be played based on current game state
# Returns empty string if playable, or an error message if conditions aren't met
func _basic_matches_stage2(basic: card_object, stage2: card_object) -> bool:
	var s2_evolves_from = stage2.metadata.get("evolvesFrom", "")
	if s2_evolves_from == "":
		return false
	# The Stage 2 evolves from a Stage 1 name. Check if any Stage 1 with that name evolves from this Basic.
	var basic_name = basic.metadata.get("name", "")
	# Fix 1: Use cached set metadata instead of reading from disk every call
	var set_prefix = stage2.uid.split("-")[0]
	var set_cards = main.get_set_cards(set_prefix)
	if set_cards.is_empty():
		# Cache miss — force a load via get_card_metadata to populate the cache, then retry
		main.get_card_metadata(stage2.uid)
		set_cards = main.get_set_cards(set_prefix)
	for card_data in set_cards:
		if card_data.get("name", "") == s2_evolves_from:
			if card_data.get("evolvesFrom", "") == basic_name:
				return true
	return false

# base1-77 — Pokemon Trader: Trade 1 Pokemon from hand for 1 from deck
func _cpu_pokedex_priority(card: card_object) -> float:
	var score = 0.0
	var name = card.metadata.get("name", "").to_lower()
	var supertype = card.metadata.get("supertype", "").to_lower()
	
	if name == "bill" or name == "professor oak":
		score += 100.0
	elif supertype == "energy":
		var energy_in_hand = 0
		for c in main.opponent_hand:
			if c.metadata.get("supertype", "").to_lower() == "energy":
				energy_in_hand += 1
		if energy_in_hand <= 1:
			score += 80.0
		else:
			score += 40.0
	elif supertype == "pokémon" and not main.is_basic_pokemon(card):
		# Evolution that can be played
		var evolves_from = card.metadata.get("evolvesFrom", "")
		var has_base = false
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.metadata.get("name", "") == evolves_from:
			has_base = true
		for bp in main.opponent_bench:
			if bp.metadata.get("name", "") == evolves_from:
				has_base = true
		score += 70.0 if has_base else 20.0
	elif supertype == "trainer":
		score += 50.0
	elif supertype == "pokémon" and main.is_basic_pokemon(card):
		score += 30.0 if main.opponent_bench.size() < 5 else 10.0
	
	return score

# base1-89 — Revive: Put Basic from discard to bench at half HP
func validate_trainer_can_be_played(card: card_object, is_opponent: bool) -> String:
	# Check trainer lock (Psyduck Headache)
	if is_opponent and opponent_trainer_locked:
		return "Trainer cards are locked this turn!"
	if not is_opponent and player_trainer_locked:
		return "Trainer cards are locked this turn!"

	# Check Hay Fever (Dark Vileplume) - blocks all trainer cards
	if main.powers_and_bodies.is_hay_fever_active():
		# ISSUE #175: name the card doing it. "Hay Fever:" on its own reads as a
		# rule the player has broken rather than as an opposing Pokemon's Power.
		return "Dark Vileplume's Hay Fever prevents Trainer cards being played"

	# ecard2 Addictive Pollen (Vileplume): blocks Supporter cards specifically, for one turn
	if "Supporter" in card.metadata.get("subtypes", []):
		if is_opponent and opponent_supporter_locked:
			return "Addictive Pollen: Supporter cards are locked this turn!"
		if not is_opponent and player_supporter_locked:
			return "Addictive Pollen: Supporter cards are locked this turn!"
		# ex2 Primal Veil (Armaldo): while an Armaldo is Active, NO player can play Supporters
		if main.powers_and_bodies.is_ex2_primal_veil_active():
			return "Primal Veil: no player can play Supporter cards!"
		# EX1+: only 1 Supporter card per turn
		if is_opponent and opponent_played_supporter_this_turn:
			return "You can only play 1 Supporter card each turn!"
		if not is_opponent and player_played_supporter_this_turn:
			return "You can only play 1 Supporter card each turn!"

	# ex2 Primal Lock (Aerodactyl ex): the opponent can't play Pokémon Tool cards
	if "Pokémon Tool" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex2_primal_lock_blocking(is_opponent):
		return "Primal Lock: you can't play Pokémon Tool cards!"

	# ex5 Block Dust (Vileplume ex ex5-100): opponent can't play non-Supporter Trainer cards
	if "Supporter" not in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex5_block_dust_blocking(is_opponent):
		return "Block Dust: you can't play Trainer cards (except Supporters)!"

	# ex10 Lonesome (Houndoom): while the opponent has fewer Pokémon in play, you can't play Trainer
	# cards except Supporters.
	if "Supporter" not in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex10_lonesome_active(is_opponent):
		return "Lonesome: you can't play Trainer cards (except Supporters)!"

	# ex8 Commanding Aura (Hariyama ex ex8-100): opponent can't play Stadium cards
	if "Stadium" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex8_commanding_aura_active(is_opponent):
		return "Commanding Aura: you can't play Stadium cards!"

	# ex13 Delta Block (Golduck δ ex13-43): while a Holon Stadium is in play, the opponent of Golduck's
	# owner can't play Stadium cards from hand.
	if "Stadium" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex13_delta_block_active(is_opponent):
		return "Delta Block: you can't play Stadium cards!"

	# ex9 Mystic Scale (Milotic ex ex9-96): while a Milotic ex is in play, no player can play a
	# Technical Machine card.
	if "Technical Machine" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex9_mystic_scale_in_play():
		return "Mystic Scale: no player can play Technical Machine cards!"

	# ex8 Disconnect (Manectric ex ex8-101): non-Supporter Trainer lock for one turn
	if "Supporter" not in card.metadata.get("subtypes", []):
		if (is_opponent and opponent_trainer_except_supporter_locked) or (not is_opponent and player_trainer_except_supporter_locked):
			return "Disconnect: you can't play Trainer cards (except Supporters) this turn!"

	# MATCH EFFECT: trainer_discard_cost — must have enough OTHER cards in hand to pay
	var rule_discard_cost = main.match_effects.trainer_discard_cost(is_opponent)
	if rule_discard_cost > 0:
		var hand = main.opponent_hand if is_opponent else main.player_hand
		if hand.size() - 1 < rule_discard_cost:
			return "Special match rule: you must discard " + str(rule_discard_cost) + " other card(s) to play a Trainer!"

	_ensure_validator_dispatch_ready()
	var uid = card.uid.to_lower()
	if _validator_dispatch.has(uid):
		return _validator_dispatch[uid].call(card, is_opponent)
	return ""

# Main entry point for playing a trainer card (handles animation, routing, and discard)
func play_trainer_card(card: card_object, is_opponent: bool) -> void:
	# Check trainer lock (Psyduck Headache)
	if is_opponent and opponent_trainer_locked:
		await main.show_message("TRAINER CARDS ARE LOCKED THIS TURN!")
		if main._should_bail(): return
		return
	if not is_opponent and player_trainer_locked:
		await main.show_message("TRAINER CARDS ARE LOCKED THIS TURN!")
		if main._should_bail(): return
		return
	# ecard2 Addictive Pollen: blocks Supporter cards specifically, for one turn
	if "Supporter" in card.metadata.get("subtypes", []):
		if (is_opponent and opponent_supporter_locked) or (not is_opponent and player_supporter_locked):
			await main.show_message("ADDICTIVE POLLEN: SUPPORTER CARDS ARE LOCKED THIS TURN!")
			if main._should_bail(): return
			return
		# ex2 Primal Veil (Armaldo): while an Armaldo is Active, NO player can play Supporters
		if main.powers_and_bodies.is_ex2_primal_veil_active():
			await main.show_message("PRIMAL VEIL: NO PLAYER CAN PLAY SUPPORTER CARDS!")
			if main._should_bail(): return
			return
		# EX1+: only 1 Supporter card per turn
		if (is_opponent and opponent_played_supporter_this_turn) or (not is_opponent and player_played_supporter_this_turn):
			await main.show_message("YOU CAN ONLY PLAY 1 SUPPORTER CARD EACH TURN!")
			if main._should_bail(): return
			return

	# ex2 Primal Lock (Aerodactyl ex): the opponent can't play Pokémon Tool cards
	if "Pokémon Tool" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex2_primal_lock_blocking(is_opponent):
		await main.show_message("PRIMAL LOCK: YOU CAN'T PLAY POKÉMON TOOL CARDS!")
		if main._should_bail(): return
		return

	# ex5 Block Dust (Vileplume ex ex5-100): opponent can't play non-Supporter Trainer cards
	if "Supporter" not in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex5_block_dust_blocking(is_opponent):
		await main.show_message("BLOCK DUST: YOU CAN'T PLAY TRAINER CARDS (EXCEPT SUPPORTERS)!")
		if main._should_bail(): return
		return

	# ex8 Commanding Aura (Hariyama ex ex8-100): opponent can't play Stadium cards
	if "Stadium" in card.metadata.get("subtypes", []) and main.powers_and_bodies.is_ex8_commanding_aura_active(is_opponent):
		await main.show_message("COMMANDING AURA: YOU CAN'T PLAY STADIUM CARDS!")
		if main._should_bail(): return
		return

	# ex8 Disconnect (Manectric ex ex8-101): non-Supporter Trainer lock for one turn
	if "Supporter" not in card.metadata.get("subtypes", []) and ((is_opponent and opponent_trainer_except_supporter_locked) or (not is_opponent and player_trainer_except_supporter_locked)):
		await main.show_message("DISCONNECT: YOU CAN'T PLAY TRAINER CARDS (EXCEPT SUPPORTERS) THIS TURN!")
		if main._should_bail(): return
		return

	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var who = "Opponent" if is_opponent else "You"
	var card_name = card.metadata.get("name", "Unknown")

	# MATCH EFFECT: trainer_discard_cost — pay the discard cost before the trainer resolves.
	# (Cost is paid even if Mind Games / Chaos Gym later wastes the card.)
	var rule_discard_cost = main.match_effects.trainer_discard_cost(is_opponent)
	if rule_discard_cost > 0:
		if hand.size() - 1 < rule_discard_cost:
			await main.show_message("NOT ENOUGH CARDS TO PAY THE TRAINER COST!")
			if main._should_bail(): return
			return
		if not is_opponent:
			await main.show_message("SPECIAL MATCH RULE: DISCARD " + str(rule_discard_cost) + " CARD(S) TO PLAY " + card_name.to_upper() + "!")
			if main._should_bail(): return
		var paid = await main.card_ops.discard_from_hand(is_opponent, rule_discard_cost, card)
		if main._should_bail(): return
		if paid.size() < rule_discard_cost:
			return

	# Remove from hand first
	hand.erase(card)
	main.refresh_hand_display(is_opponent)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_trainer_sound)

	# NEO1 Mind Games (Slowking): whenever opponent plays a Trainer, may flip — heads: cancel it (card goes to top of deck)
	if not is_stadium_trainer(card):
		if await main.powers_and_bodies.check_mind_games(is_opponent):
			var opp_deck = main.opponent_deck if is_opponent else main.player_deck
			card.current_location = "deck"
			opp_deck.insert(0, card)
			main.update_deck_icon(is_opponent)
			main.refresh_hand_display(is_opponent)
			return

	# GYM2-102 Chaos Gym — Whenever a player plays a non-Stadium Trainer, flip a coin. Tails: card is wasted (discarded with no effect).
	# Simplification: the "opponent may steal the card" mechanic is skipped (same approach as Lt. Surge's Secret Plan).
	if main.is_stadium_in_play(StadiumIds.CHAOS_GYM) and not is_stadium_trainer(card):
		await main.show_message("CHAOS GYM: FLIPPING COIN FOR " + card_name.to_upper() + "...")
		if main._should_bail(): return
		var chaos_heads = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if not chaos_heads:
			await main.show_message("TAILS! " + card_name.to_upper() + " IS DISCARDED WITH NO EFFECT!")
			if main._should_bail(): return
			card.current_location = "discard"
			discard.append(card)
			var hand_node_chaos = main.opponent_hand_container if is_opponent else main.player_hand_container
			var discard_node_chaos = main.opponent_discard_icon if is_opponent else main.player_discard_icon
			var ctex_chaos = main.get_card_texture(card)
			await main.animate_card_a_to_b(hand_node_chaos, discard_node_chaos, 0.3, ctex_chaos, main.card_scales[10])
			if main._should_bail(): return
			main.update_discard_pile_display(is_opponent)
			main.cpu_ai.invalidate_cpu_evaluation()
			return

	# Step 1: Show trainer card animation
	await show_trainer_card_played_animation(card, is_opponent)
	
	# Step 2: Route to the correct handler based on card type
	if is_bench_token_trainer(card):
		await resolve_bench_token_trainer(card, is_opponent)
	elif is_attached_trainer(card):
		await resolve_attached_trainer(card, is_opponent)
	elif is_stadium_trainer(card):
		await resolve_stadium_trainer(card, is_opponent)
	else:
		# GYM1-103 No Removal Gym: Energy Removal / Super Energy Removal require an extra 2-card hand discard
		var card_uid_lower = card.uid.to_lower()
		if card_uid_lower in ["base1-92", "base1-79"]:
			var paid = await gym1_no_removal_gym_pay_tax(card, is_opponent)
			if not paid:
				# Tax failed (shouldn't normally happen due to validation) — refund the card
				card.current_location = "hand"
				hand.append(card)
				main.refresh_hand_display(is_opponent)
				return
		# Standard trainer: send to discard and update display BEFORE resolving effect
		card.current_location = "discard"
		discard.append(card)
		main.update_discard_pile_display(is_opponent)
		# EX1+: only 1 Supporter card per turn — mark it used now that it's committed to resolving
		if "Supporter" in card.metadata.get("subtypes", []):
			if is_opponent:
				opponent_played_supporter_this_turn = true
			else:
				player_played_supporter_this_turn = true
		await resolve_standard_trainer(card, is_opponent)
	
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_pokemon(not is_opponent)
	
	# Fix 2: Invalidate CPU evaluation cache — trainer cards can change board state
	main.cpu_ai.invalidate_cpu_evaluation()

# Displays the trainer card animation overlay
func show_trainer_card_played_animation(card: card_object, is_opponent: bool) -> void:
	var who = "Opponent" if is_opponent else "You"
	var card_name = card.metadata.get("name", "Unknown")
	
	# ISSUE #214 / #235: the WHOLE board goes, not a hand-written list of four
	# icons plus a white sheet over the rest. The attack rows beside the active
	# Pokemon were the ones this list kept missing, so they sat over the card that
	# had just been played. See main.set_card_showcase_visible.
	main.set_card_showcase_visible(true)
	
	
	# Display the card in the container
	var card_display = TextureRect.new()
	card_display.set_script(main.card_display_script)
	main.played_trainer_container.add_child(card_display)
	card_display.load_card_image(card.uid, main.card_scales[1], card)
	
	# Show message
	await main.show_message(who + " played " + card_name + "!")
	
	# Clean up the card; set_card_showcase_visible restores the board.
	# ISSUE #170: detach before freeing, or the next showcase parents its card
	# alongside this one for a frame.
	for child in main.played_trainer_container.get_children():
		main.played_trainer_container.remove_child(child)
		child.queue_free()
	main.set_card_showcase_visible(false)
	
	# Animate card to appropriate destination
	var hand_container_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	var card_texture = main.get_card_texture(card)
	
	if is_bench_token_trainer(card):
		var bench_container_node = main.opponent_bench_container if is_opponent else main.player_bench_container
		await main.animate_card_a_to_b(hand_container_node, bench_container_node, 0.3, card_texture, main.card_scales[10])
	elif is_attached_trainer(card):
		# Don't animate here - attached trainers animate to their target in resolve_attached_trainer
		pass
	elif is_stadium_trainer(card):
		# Stadium cards animate to the stadium zone (the resolve_stadium_trainer function handles the rest)
		await main.animate_card_a_to_b(hand_container_node, main.stadium_card_container, 0.3, card_texture, main.card_scales[10])
	else:
		# Standard trainers animate to the discard pile
		var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
		await main.animate_card_a_to_b(hand_container_node, discard_node, 0.3, card_texture, main.card_scales[10])

############################################### Section D: STANDARD TRAINER CARD EFFECTS ############################################################

# Routes a standard trainer card to its specific effect function
func resolve_standard_trainer(card: card_object, is_opponent: bool) -> void:
	_ensure_trainer_dispatch_ready()
	var uid = card.uid.to_lower()
	if _trainer_dispatch.has(uid):
		await _trainer_dispatch[uid].call(card, is_opponent)
		return
	print("Unknown trainer card: ", card.uid, " (", card.metadata.get("name",""), ")")

# Resolves bench token trainer placement (Clefairy Doll, Mysterious Fossil)
func resolve_bench_token_trainer(card: card_object, is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("Bench is full! Cannot place " + card.metadata.get("name", "") + "!")
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard.append(card)
		return
	
	# Place on bench with proper flags
	card.current_location = "bench"
	card.placed_on_field_this_turn = true
	card.no_prize_on_ko = true
	card.is_bench_token = true
	# Read HP from card metadata, fallback to 10
	var hp_str = card.metadata.get("hp", "10")
	card.current_hp = int(hp_str) if hp_str != "" else 10
	bench.append(card)
	
	main.display_pokemon(is_opponent)
	var name = card.metadata.get("name", "")
	await main.show_message(name + " was placed on the bench!")
	print("BENCH TOKEN: ", name, " placed on bench with ", card.current_hp, " HP")

# Resolves attached trainer card placement (PlusPower, Defender)
func resolve_attached_trainer(card: card_object, is_opponent: bool) -> void:
	var card_name = card.metadata.get("name", "").to_lower()
	
	if card_name == "pluspower":
		# Attach to active pokemon
		var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		if active == null:
			await main.show_message("No active Pokemon to attach PlusPower to!")
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return
		active.attached_cards.append(card)
		active.pluspower_count += 1
		# ISSUE #54 FIX: fly PlusPower to its EXACT final tool slot (position AND size), read off the
		# freshly-built attached-trainer stack — same fix as ISSUE #40 for energy. Previously it flew to
		# the container origin and landed ~150-200px below the energy cards.
		var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
		var card_texture = main.get_card_texture(card)
		var pp_rect = main.measure_and_hide_new_active_tool_slot(is_opponent)
		var pp_pos = pp_rect.get("position", main._ANIM_POS_SENTINEL)
		var pp_size = pp_rect.get("size", main.card_scales[11])
		await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10], pp_size, pp_pos)
		# ISSUE #59 FIX (retest sub-issue 2): board refresh BEFORE the message so the tool is visibly
		# attached while the message is up.
		display_attached_trainer_cards(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("PlusPower attached to " + active.metadata.get("name", "").to_upper() + "!")
		print("PLUSPOWER: Attached to ", active.metadata.get("name", ""), " (total: ", active.pluspower_count, ")")
	
	elif card_name == "defender":
		if is_opponent:
			# CPU always attaches to its own active
			var active = main.opponent_active_pokemon
			if active == null:
				return
			active.attached_cards.append(card)
			active.defender_turns_remaining = 0
			active.defender_count += 1
			# ISSUE #54 FIX: fly Defender to its exact final tool slot (see PlusPower above).
			var hand_node = main.opponent_hand_container
			var attached_node = main.opponent_attached_cards_container
			var card_texture = main.get_card_texture(card)
			var def_rect = main.measure_and_hide_new_active_tool_slot(true)
			var def_pos = def_rect.get("position", main._ANIM_POS_SENTINEL)
			var def_size = def_rect.get("size", main.card_scales[11])
			await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10], def_size, def_pos)
			# ISSUE #85 FIX: drop the "(-20 damage)" suffix — the message just states the attachment.
			# ISSUE #59 FIX (retest sub-issue 2): refresh the board BEFORE the message so the tool is
			# visibly attached while the message is on screen, rather than appearing after it closes.
			display_attached_trainer_cards(true)
			main.display_pokemon(true)
			await main.show_message("Defender attached to " + active.metadata.get("name", "") + "!")
		else:
			# Player chooses target
			var targets = build_field_pokemon_array(false)
			if targets.size() == 0:
				return
			
			var target = await main.card_ops.prompt_select_card(targets, "ATTACH DEFENDER", "Choose a Pokemon to attach Defender to", "ATTACH", false)
			if main._should_bail(): return
			
			if target != null:
				target.attached_cards.append(card)
				target.defender_turns_remaining = 0
				target.defender_count += 1
				# ISSUE #54 FIX: fly Defender to its exact final spot. For the Active that's the tool slot
				# (as PlusPower); for a Bench target it's that Pokémon's real bench slot position.
				var hand_node = main.player_hand_container
				# ISSUE #236: both branches through the one helper, so the bench case
				# also gets the right SIZE (it kept the 150x206 hand size before) and
				# arrives behind the Pokemon rather than on top of it.
				await main.animate_attach_to_pokemon(card, target, false, hand_node)
				# ISSUE #59 FIX (retest sub-issue 2): a BENCH target's tools are drawn by display_pokemon,
				# not display_attached_trainer_cards (which only rebuilds the Active's tool stack), so the
				# Defender wasn't visible on the bench until some later refresh. Refresh the board first.
				display_attached_trainer_cards(false)
				main.display_pokemon(false)
				print("ISSUE #59 FIX ACTIVE: board refreshed before the Defender attach message")
				await main.show_message("Defender attached to " + target.metadata.get("name", "") + "!")

	# GYM1 Charity (gym1-99) — attach to your own Active Pokemon
	elif card.uid.to_lower() == "gym1-99":
		var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		if active == null:
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return
		active.attached_cards.append(card)
		active.gym1_charity_attached = true
		var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
		# the ACTIVE Pokemon's tool container whatever it had been attached to.
		# main.animate_attach_to_pokemon aims at the Pokemon that received it.
		await main.animate_attach_to_pokemon(card, active, is_opponent, hand_node)
		display_attached_trainer_cards(is_opponent)
		# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
		# display_attached_trainer_cards (which only rebuilds the Active's stack).
		main.display_pokemon(is_opponent)
		await main.show_message("CHARITY ATTACHED TO " + active.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("CHARITY: Attached to ", active.metadata.get("name", ""))

	# GYM1 Sabrina's ESP (gym1-117) — attach to a Sabrina-named pokemon in play
	elif card.uid.to_lower() == "gym1-117":
		# Build list of valid Sabrina-named targets
		var sabrina_targets: Array = []
		for p in build_field_pokemon_array(is_opponent):
			if "Sabrina" in p.metadata.get("name", ""):
				sabrina_targets.append(p)
		if sabrina_targets.size() == 0:
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return

		var target: card_object = null
		if is_opponent:
			# CPU: pick the highest-HP Sabrina pokemon (likely the active/intended attacker)
			var best_hp = -1
			for p in sabrina_targets:
				if p.current_hp > best_hp:
					best_hp = p.current_hp
					target = p
			# Prefer the active if it's a Sabrina-named pokemon
			if main.opponent_active_pokemon != null and main.opponent_active_pokemon in sabrina_targets:
				target = main.opponent_active_pokemon
		else:
			# ISSUE #156: always ask, even with one legal target.
			target = await main.card_ops.prompt_select_card(sabrina_targets, "ATTACH SABRINA'S ESP", "Choose a Sabrina Pokemon", "ATTACH", false)
			if main._should_bail(): return

		if target == null:
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return

		target.attached_cards.append(card)
		target.gym1_sabrina_esp_attached = true
		target.gym1_sabrina_esp_credit_active = true
		var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
		# the ACTIVE Pokemon's tool container whatever it had been attached to.
		# main.animate_attach_to_pokemon aims at the Pokemon that received it.
		await main.animate_attach_to_pokemon(card, target, is_opponent, hand_node)
		display_attached_trainer_cards(is_opponent)
		# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
		# display_attached_trainer_cards (which only rebuilds the Active's stack).
		main.display_pokemon(is_opponent)
		await main.show_message("SABRINA'S ESP ATTACHED TO " + target.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("SABRINA'S ESP: Attached to ", target.metadata.get("name", ""))

	# GYM2 Brock's Protection (gym2-101) — attach to a Brock-named pokemon
	elif card.uid.to_lower() == "gym2-101":
		await gym2_attach_named_tool(card, is_opponent, "Brock", "gym2_brocks_protection_attached", "BROCK'S PROTECTION")

	# NEO1 Pokemon Tools (Focus Band, Gold Berry, Miracle Berry, Berry): attach to chosen Pokemon
	elif card.uid.to_lower() in ["neo1-86", "neo1-93", "neo1-94", "neo1-99"]:
		await neo1_attach_tool(card, is_opponent)
		return

	# ECARD1 Strength Charm (ecard1-150): Pokemon Tool — shares the one-tool-per-Pokemon slot
	elif card.uid.to_lower() == "ecard1-150":
		await neo1_attach_tool(card, is_opponent)
		return

	# ECARD2 Weakness Guard (ecard2-141): attach to chosen own Pokemon, grants no Weakness until
	# discarded (end of your opponent's next turn — see gym1_end_of_turn_cleanup)
	elif card.uid.to_lower() == "ecard2-141":
		var wg_targets = build_field_pokemon_array(is_opponent)
		if wg_targets.is_empty():
			var wg_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			wg_discard.append(card)
			return
		var wg_target: card_object = null
		if is_opponent:
			wg_target = main.opponent_active_pokemon if main.opponent_active_pokemon != null else wg_targets[0]
		else:
			# ISSUE #156: always ask, even with one legal target.
			wg_target = await main.card_ops.prompt_select_card(wg_targets, "ATTACH WEAKNESS GUARD", "Choose a Pokemon to remove its Weakness", "ATTACH", false)
			if main._should_bail(): return
		if wg_target == null:
			var wg_discard2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			wg_discard2.append(card)
			return
		wg_target.attached_cards.append(card)
		wg_target.temporary_weakness = "NONE_ECARD2_WEAKNESS_GUARD"
		wg_target.set_effect("ecard2_weakness_guard", "end_of_opponent_turn")
		# ISSUE #236: aim at the Pokemon that received it, not at the Active's stack.
		var wg_hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		await main.animate_attach_to_pokemon(card, wg_target, is_opponent, wg_hand_node)
		display_attached_trainer_cards(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("WEAKNESS GUARD ATTACHED TO " + wg_target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		print("TRAINER: Weakness Guard attached to ", wg_target.metadata.get("name",""))
		return

	# EX14 Cessation Crystal (ex14-74) / Mysterious Shard (ex14-81): Pokémon Tools that may only be
	# attached to a Pokémon that is NOT a Pokémon-ex.
	elif card.uid.to_lower() in ["ex14-74", "ex14-81"]:
		await neo1_attach_tool(card, is_opponent, func(p): return not main.is_ex_pokemon(p))
		return

	# Any Pokémon Tool card not otherwise handled above (ecard2 Healing Berry/Memory Berry/Time
	# Shard, and any future ones): standard one-tool-per-Pokemon attach
	elif "Pokémon Tool" in card.metadata.get("subtypes", []):
		await neo1_attach_tool(card, is_opponent)
		return

	# Any Technical Machine card: attach to a Pokemon in play (own subtype, no tool-slot restriction).
	# ecard1-144 Multi Technical Machine 01 works on any Pokemon; ecard2's 8 type Cubes ("Fire Cube
	# 01" etc.) only attach to a Pokemon of the matching type — parsed from the card's own name.
	elif "Technical Machine" in card.metadata.get("subtypes", []):
		var targets = build_field_pokemon_array(is_opponent)
		var required_type = ""
		for t in ["Darkness","Fighting","Fire","Grass","Lightning","Metal","Psychic","Water"]:
			if (t + " Cube") in card.metadata.get("name",""):
				required_type = t
				break
		if required_type != "":
			targets = targets.filter(func(p): return required_type in p.metadata.get("types", []))
		# EX4 Team Aqua/Magma Technical Machine 01: only attach to a Pokemon with the matching team name
		var tm_name = card.metadata.get("name","")
		if "Team Aqua" in tm_name:
			targets = targets.filter(func(p): return "Team Aqua" in p.metadata.get("name",""))
		elif "Team Magma" in tm_name:
			targets = targets.filter(func(p): return "Team Magma" in p.metadata.get("name",""))
		if targets.size() == 0:
			var discard_tm = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard_tm.append(card)
			if required_type != "":
				await main.show_message("NO " + required_type.to_upper() + " POKEMON TO ATTACH " + card.metadata.get("name","").to_upper() + " TO!")
				if main._should_bail(): return
			return
		var target_tm: card_object = null
		if is_opponent:
			target_tm = main.opponent_active_pokemon if main.opponent_active_pokemon in targets else targets[0]
		else:
			# ISSUE #156: always ask, even with one legal target.
			target_tm = await main.card_ops.prompt_select_card(targets, "ATTACH " + card.metadata.get("name","").to_upper(), "Choose a Pokemon to attach it to", "ATTACH", false)
			if main._should_bail(): return
		if target_tm == null:
			var discard_tm2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard_tm2.append(card)
			return
		target_tm.attached_cards.append(card)
		var hand_node_tm = main.opponent_hand_container if is_opponent else main.player_hand_container
		# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
		# the ACTIVE Pokemon's tool container whatever it had been attached to.
		# main.animate_attach_to_pokemon aims at the Pokemon that received it.
		await main.animate_attach_to_pokemon(card, target_tm, is_opponent, hand_node_tm)
		display_attached_trainer_cards(is_opponent)
		# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
		# display_attached_trainer_cards (which only rebuilds the Active's stack).
		main.display_pokemon(is_opponent)
		await main.show_message(card.metadata.get("name","").to_upper() + " ATTACHED TO " + target_tm.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		print("TRAINER: ", card.metadata.get("name",""), " attached to ", target_tm.metadata.get("name",""))
		return

	# NEO3 Balloon Berry (neo3-60): attach to chosen Pokemon — makes retreat free once, then discards
	elif card.uid.to_lower() == "neo3-60":
		await neo3_attach_tool(card, is_opponent)
		return

	# NEO4 Pokemon Tools (EXP.ALL, Counterattack Claws, Magnifier): attach to a chosen Pokemon
	elif card.uid.to_lower() in ["neo4-93", "neo4-97", "neo4-101"]:
		await neo3_attach_tool(card, is_opponent)
		return

	# GYM2 Koga's Ninja Trick (gym2-115) — attach to Active Koga-named pokemon
	elif card.uid.to_lower() == "gym2-115":
		var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		if active == null or not ("Koga" in active.metadata.get("name", "")):
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return
		active.attached_cards.append(card)
		active.gym2_koga_ninja_trick_attached = true
		var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
		# the ACTIVE Pokemon's tool container whatever it had been attached to.
		# main.animate_attach_to_pokemon aims at the Pokemon that received it.
		await main.animate_attach_to_pokemon(card, active, is_opponent, hand_node)
		display_attached_trainer_cards(is_opponent)
		# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
		# display_attached_trainer_cards (which only rebuilds the Active's stack).
		main.display_pokemon(is_opponent)
		await main.show_message("KOGA'S NINJA TRICK ATTACHED TO " + active.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("KOGA'S NINJA TRICK: Attached to ", active.metadata.get("name", ""))

# Generic helper for "attach to a named pokemon in play" tools (Brock's Protection-style).
func gym2_attach_named_tool(card: card_object, is_opponent: bool, name_substr: String, flag_name: String, display_name: String) -> void:
	var targets: Array = []
	for p in build_field_pokemon_array(is_opponent):
		if name_substr in p.metadata.get("name", ""):
			targets.append(p)
	if targets.size() == 0:
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard.append(card)
		return
	var target: card_object = null
	if is_opponent:
		# CPU: prefer pokemon with most energies attached (most worth protecting)
		var best_e = -1
		for p in targets:
			if p.attached_energies.size() > best_e:
				best_e = p.attached_energies.size()
				target = p
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(targets, "ATTACH " + display_name, "Choose a " + name_substr + " Pokemon", "ATTACH", false)
		if main._should_bail(): return
	if target == null:
		var discard2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard2.append(card)
		return
	target.attached_cards.append(card)
	target.set(flag_name, true)
	var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
	# the ACTIVE Pokemon's tool container whatever it had been attached to.
	# main.animate_attach_to_pokemon aims at the Pokemon that received it.
	await main.animate_attach_to_pokemon(card, target, is_opponent, hand_node)
	display_attached_trainer_cards(is_opponent)
	# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
	# display_attached_trainer_cards (which only rebuilds the Active's stack).
	main.display_pokemon(is_opponent)
	await main.show_message(display_name + " ATTACHED TO " + target.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print(display_name, ": Attached to ", target.metadata.get("name", ""))

# --- INDIVIDUAL TRAINER EFFECTS ---

# base1-91 — Bill: Draw 2 cards
func player_select_cards_to_discard(hand: Array, count: int, title: String, hint: String) -> void:
	main.trainer_discard_selected.clear()
	main.trainer_discard_cards_needed = count
	main.trainer_discard_selection_active = true
	
	main.show_enlarged_array_selection_mode(hand)
	main.header_label.text = title
	main.hint_label.text = hint + " (0/" + str(count) + " selected)"
	main.action_button.text = str(count) + " MORE"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = false
	
	await main.trainer_discard_selection_done
	main.trainer_discard_selection_active = false
	main.hide_selection_mode_display_main()
# Master scoring function: returns the CPU priority score for a trainer card
func effect_bill(is_opponent: bool) -> void:
	await main.card_ops.draw_n(is_opponent, 2)
	if main._should_bail(): return

# base1-88 — Professor Oak: Discard hand, draw 7
func effect_professor_oak(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand_container_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
	
	# Animate each hand card going to discard
	var hand_copy = hand.duplicate()
	for card in hand_copy:
		card.current_location = "discard"
		discard.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(hand_container_node, discard_node, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(GameState.match_time(0.1)).timeout
		if main._should_bail(): return
	hand.clear()
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await get_tree().create_timer(GameState.match_time(0.3)).timeout
	if main._should_bail(): return
	
	# Draw 7 new cards with animation per card
	await main.card_ops.draw_n(is_opponent, 7)
	if main._should_bail(): return

# base1-71 — Computer Search: Discard 2, search deck for any 1 card
func effect_computer_search(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if is_opponent:
		# CPU: use discard priority and search priority
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.refresh_hand_display(true)
		
		# CPU search logic
		var search_card = main.cpu_ai.cpu_search_deck_for_best_card(deck)
		if search_card != null:
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			await main.show_message("Opponent searched their deck for a card!")
			if main._should_bail(): return
		deck.shuffle()
		main.refresh_hand_display(true)
		main.update_deck_icon(true)
	else:
		# Player: select 2 cards to discard
		if hand.size() < 2:
			await main.show_message("Not enough cards in hand to discard!")
			if main._should_bail(): return
			return
		
		await player_select_cards_to_discard(hand, 2, "COMPUTER SEARCH", "Select 2 cards to discard")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)
		
		# Player searches deck
		if deck.size() > 0:
			var chosen = await main.card_ops.prompt_select_card(deck, "SEARCH YOUR DECK", "Select any card to add to your hand", "TAKE CARD", false, true)
			if main._should_bail(): return

			if chosen != null:
				deck.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				# Animate card from deck to hand
				var card_texture = main.get_card_texture(chosen)
				await main.animate_card_a_to_b(main.player_deck_icon, main.player_hand_container, 0.3, card_texture, main.card_scales[10])
				if main._should_bail(): return
		
		deck.shuffle()
		main.refresh_hand_display(false)
		main.update_deck_icon(false)

# base1-72 — Devolution Spray: Devolve a pokemon
func effect_devolution_spray(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	# Find all evolved pokemon on the field
	var evolved_pokemon = []
	if active != null and active.attached_pre_evolutions.size() > 0:
		evolved_pokemon.append(active)
	for bp in bench:
		if bp.attached_pre_evolutions.size() > 0:
			evolved_pokemon.append(bp)
	
	if evolved_pokemon.size() == 0:
		await main.show_message("No evolved Pokemon to devolve!")
		if main._should_bail(): return
		return
	
	var target: card_object = null
	var devolve_to: card_object = null

	if is_opponent:
		# CPU picks the most damaged evolved pokemon
		var worst_pct = 1.0
		for p in evolved_pokemon:
			var max_hp = int(p.metadata.get("hp", "0"))
			if max_hp <= 0:
				continue
			var pct = float(p.current_hp) / float(max_hp)
			if pct < worst_pct:
				worst_pct = pct
				target = p
		if target == null:
			target = evolved_pokemon[0]
		# CPU always devolves to the lowest pre-evolution (the basic)
		devolve_to = target.attached_pre_evolutions[0]
		await main.show_message("Opponent used Devolution Spray on " + target.metadata.get("name", "") + "!")
		if main._should_bail(): return
	else:
		# Step 1: Player selects which pokemon to devolve
		target = await main.card_ops.prompt_select_card(evolved_pokemon, "DEVOLUTION SPRAY", "Choose an evolved Pokemon to devolve", "SELECT", false)
		if main._should_bail(): return
		if target == null:
			return
		# Step 2: If multiple pre-evolutions exist (Stage 2), let player choose which to devolve to
		if target.attached_pre_evolutions.size() == 1:
			devolve_to = target.attached_pre_evolutions[0]
		else:
			devolve_to = await main.card_ops.prompt_select_card(target.attached_pre_evolutions, "DEVOLVE TO WHICH STAGE?", "Select which card to devolve " + target.metadata.get("name", "") + " into", "DEVOLVE", false)
			if main._should_bail(): return
		if devolve_to == null:
			return

	# ── Shared devolve logic (both CPU and player) ───────────────────────────
	var field_location = target.current_location
	var devolve_index = target.attached_pre_evolutions.find(devolve_to)
	var evo_card = target
	evo_card.current_location = "discard"
	discard.append(evo_card)
	# Discard all pre-evolutions above the chosen devolve target
	var cards_to_discard_from_chain = []
	for i in range(devolve_index + 1, target.attached_pre_evolutions.size()):
		cards_to_discard_from_chain.append(target.attached_pre_evolutions[i])
	for card in cards_to_discard_from_chain:
		card.current_location = "discard"
		discard.append(card)
		target.attached_pre_evolutions.erase(card)
	target.attached_pre_evolutions.erase(devolve_to)
	# Transfer attachments to the new form
	devolve_to.attached_energies = evo_card.attached_energies.duplicate()
	evo_card.attached_energies.clear()
	devolve_to.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	target.attached_pre_evolutions.clear()
	devolve_to.attached_cards = evo_card.attached_cards.duplicate()
	evo_card.attached_cards.clear()
	# Transfer damage, clamping so it has at least 10 HP
	var max_hp_old = int(evo_card.metadata.get("hp", "0"))
	var damage_taken = max_hp_old - evo_card.current_hp
	var new_max_hp = int(devolve_to.metadata.get("hp", "0"))
	devolve_to.current_hp = max(10, new_max_hp - damage_taken)
	devolve_to.current_location = field_location
	main.clear_all_statuses(devolve_to, is_opponent)
	# Replace in the appropriate slot
	var active_ref = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if evo_card == active_ref:
		if is_opponent:
			main.opponent_active_pokemon = devolve_to
		else:
			main.player_active_pokemon = devolve_to
	else:
		var b = main.opponent_bench if is_opponent else main.player_bench
		var idx = b.find(evo_card)
		if idx != -1:
			b[idx] = devolve_to
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message(evo_card.metadata.get("name", "") + " devolved into " + devolve_to.metadata.get("name", "") + "!")
	if main._should_bail(): return

# base1-73 — Impostor Professor Oak: Opponent shuffles hand into deck, draws 7
func effect_impostor_professor_oak(is_opponent: bool) -> void:
	# Target is the OTHER player
	var target_hand = main.player_hand if is_opponent else main.opponent_hand
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	var target_is_opponent = not is_opponent
	var target_hand_container = main.player_hand_container if is_opponent else main.opponent_hand_container
	var target_deck_node = main.player_deck_icon if is_opponent else main.opponent_deck_icon
	
	# Animate each card from hand to deck
	var hand_copy = target_hand.duplicate()
	for card in hand_copy:
		card.current_location = "deck"
		target_deck.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(target_hand_container, target_deck_node, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(GameState.match_time(0.1)).timeout
		if main._should_bail(): return
	target_hand.clear()
	target_deck.shuffle()
	main.refresh_hand_display(target_is_opponent)
	main.update_deck_icon(target_is_opponent)
	
	await get_tree().create_timer(GameState.match_time(0.3)).timeout
	if main._should_bail(): return
	
	# Draw 7 cards with per-card animation
	await main.card_ops.draw_n(target_is_opponent, 7)
	if main._should_bail(): return
	await main.show_message("Hand was shuffled into deck and drew 7 cards!")
	if main._should_bail(): return

# base1-74 — Item Finder: Discard 2, retrieve 1 Trainer from discard
func effect_item_finder(played_card: card_object, is_opponent: bool) -> void:
	if check_pokemon_tower_blocks_recovery():
		await main.show_message("POKEMON TOWER! CANNOT RECOVER CARDS FROM DISCARD!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	# Find trainer cards in discard pile (exclude the Item Finder just played)
	var trainers_in_discard = []
	for card in discard:
		if is_trainer_card(card) and card != played_card:
			trainers_in_discard.append(card)
	
	if trainers_in_discard.size() == 0:
		await main.show_message("No Trainer cards in the discard pile!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		
		# CPU picks highest priority trainer from discard
		var best_trainer: card_object = null
		var best_score = -999.0
		for t in trainers_in_discard:
			var score = main.cpu_ai.cpu_score_trainer_card(t)
			if score > best_score:
				best_score = score
				best_trainer = t
		if best_trainer != null:
			discard.erase(best_trainer)
			best_trainer.current_location = "hand"
			hand.append(best_trainer)
			await main.show_message("Opponent retrieved " + best_trainer.metadata.get("name", "") + " from discard pile!")
			if main._should_bail(): return
		main.refresh_hand_display(true)
	else:
		if hand.size() < 2:
			await main.show_message("Not enough cards in hand to discard!")
			if main._should_bail(): return
			return
		await player_select_cards_to_discard(hand, 2, "ITEM FINDER", "Select 2 cards to discard")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		
		# Player picks from discard trainers
		var chosen = await main.card_ops.prompt_select_card(trainers_in_discard, "ITEM FINDER", "Select a Trainer card from your discard pile", "RETRIEVE", false, true)
		if main._should_bail(): return
		
		if chosen != null:
			discard.erase(chosen)
			chosen.current_location = "hand"
			hand.append(chosen)
			# Animate trainer from discard to hand
			var trainer_texture = main.get_card_texture(chosen)
			await main.animate_card_a_to_b(main.player_discard_icon, main.player_hand_container, 0.3, trainer_texture, main.card_scales[10])
			if main._should_bail(): return
			await main.show_message("Retrieved " + chosen.metadata.get("name", "") + " from discard pile!")
			if main._should_bail(): return
		main.refresh_hand_display(false)

# base1-75 — Lass: Both players shuffle Trainer cards from hand into deck
func effect_lass(is_opponent: bool) -> void:
	# Identify trainer cards in both hands
	var p_trainers = []
	for card in main.player_hand:
		if is_trainer_card(card):
			p_trainers.append(card)
	var o_trainers = []
	for card in main.opponent_hand:
		if is_trainer_card(card):
			o_trainers.append(card)
	
	# Show opponent's hand face-up to the player
	if main.opponent_hand.size() > 0:
		# ISSUE #75 FIX: when the CPU plays Lass this reveal happens during the opponent's turn, so the
		# full-screen opponent_blocker is up and swallows every click — the player could neither scroll
		# the revealed hand nor press DONE. Suspend it for the duration of the reveal.
		var restore_blocker_lass = main.suspend_opponent_blocker("effect_lass reveal")
		# Use trainer_pokemon_selection mode so the cancel/Done button triggers main.trainer_target_selected
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(main.opponent_hand)
		# Force face-up display by redrawing without hiding
		var display_container = main.large_selection_container if main.opponent_hand.size() > 7 else main.small_selection_container
		var display_size = main.card_scales[5] if main.opponent_hand.size() > 7 else main.card_scales[main.opponent_hand.size()]
		main.display_hand_cards_array(main.opponent_hand, display_container, display_size, false)
		main.header_label.text = "OPPONENT'S HAND REVEALED"
		main.hint_label.text = str(o_trainers.size()) + " Trainer card(s) will be shuffled into deck"
		main.action_button.visible = false
		main.cancel_button.visible = true
		main.cancel_button.text = "DONE"
		main.cancel_button.theme = main.theme_green
		main.cancel_button.offset_left = -219.0
		main.cancel_button.offset_right = 219.0
		await main.trainer_target_selected
		if main._should_bail():
			main.restore_opponent_blocker(restore_blocker_lass, "effect_lass reveal")
			return
		main.trainer_pokemon_selection_active = false
		main.cancel_button.text = "Cancel"
		main.cancel_button.theme = main.theme_red
		main.hide_selection_mode_display_main()
		main.restore_opponent_blocker(restore_blocker_lass, "effect_lass reveal")

	# Animate player trainers going to deck
	for card in p_trainers:
		main.player_hand.erase(card)
		card.current_location = "deck"
		main.player_deck.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(main.player_hand_container, main.player_deck_icon, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(GameState.match_time(0.1)).timeout
		if main._should_bail(): return
		main.update_deck_icon(false)
	
	# Animate opponent trainers going to deck
	for card in o_trainers:
		main.opponent_hand.erase(card)
		card.current_location = "deck"
		main.opponent_deck.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(main.opponent_hand_container, main.opponent_deck_icon, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(GameState.match_time(0.1)).timeout
		if main._should_bail(): return
		main.update_deck_icon(true)
	
	main.player_deck.shuffle()
	main.opponent_deck.shuffle()
	main.refresh_hand_display(false)
	main.refresh_hand_display(true)
	main.update_deck_icon(false)
	main.update_deck_icon(true)
	await main.show_message("All Trainer cards shuffled back into decks!")
	if main._should_bail(): return

# base1-76 — Pokemon Breeder: Place Stage 2 directly on matching Basic
func effect_pokemon_breeder(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	
	# Find Stage 2 cards in hand
	var stage2_cards = []
	for card in hand:
		var subtypes = card.metadata.get("subtypes", [])
		if "Stage 2" in subtypes:
			stage2_cards.append(card)
	
	if stage2_cards.size() == 0:
		await main.show_message("No Stage 2 Pokemon in hand!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# CPU: find best Stage 2 + Basic match
		for s2 in stage2_cards:
			var evolves_from_s1 = s2.metadata.get("evolvesFrom", "")
			# Find the Stage 1 this evolves from, then find that Stage 1's basic
			# For Breeder, we need the Basic that the Stage 2 ultimately comes from
			# Check all pokemon in play to see if any Basic matches
			var all_in_play = []
			if active != null:
				all_in_play.append(active)
			all_in_play.append_array(bench)
			
			for pokemon in all_in_play:
				if pokemon.placed_on_field_this_turn:
					continue
				if not main.is_basic_pokemon(pokemon):
					continue
				# Check if this Basic eventually leads to the Stage 2
				if _basic_matches_stage2(pokemon, s2):
					main.evolution_card_awaiting_target = s2
					main.selected_card_for_action = pokemon
					main.perform_evolution(true)
					await main.show_message("Opponent used Pokemon Breeder to evolve " + pokemon.metadata.get("name", "") + " into " + s2.metadata.get("name", "") + "!")
					if main._should_bail(): return
					main.display_pokemon(true)
					main.display_active_pokemon_energies(true)
					main.refresh_hand_display(true)
					main.evolution_card_awaiting_target = null
					main.selected_card_for_action = null
					return
	else:
		# Player: select Stage 2 card, then select matching Basic
		var s2_card = await main.card_ops.prompt_select_card(stage2_cards, "POKEMON BREEDER", "Select a Stage 2 Pokemon to play", "SELECT", false)
		if main._should_bail(): return

		if s2_card == null:
			return

		# Find valid basic targets - bench first, active last (for spacer display)
		var targets = []
		for bp in bench:
			if not bp.placed_on_field_this_turn and main.is_basic_pokemon(bp) and _basic_matches_stage2(bp, s2_card):
				targets.append(bp)
		if active != null and not active.placed_on_field_this_turn and main.is_basic_pokemon(active) and _basic_matches_stage2(active, s2_card):
			targets.append(active)

		if targets.size() == 0:
			await main.show_message("No valid Basic Pokemon to evolve!")
			if main._should_bail(): return
			return

		var target = await main.card_ops.prompt_select_card(targets, "POKEMON BREEDER", "Select a Basic Pokemon to evolve into " + s2_card.metadata.get("name", ""), "EVOLVE", false)
		if main._should_bail(): return
		
		if target != null:
			main.evolution_card_awaiting_target = s2_card
			main.selected_card_for_action = target
			main.perform_evolution(false)
			main.display_pokemon(false)
			main.display_active_pokemon_energies(false)
			main.refresh_hand_display(false)
			await main.play_evolution_effect(s2_card)
			if main._should_bail(): return
			main.evolution_card_awaiting_target = null
			main.selected_card_for_action = null

# Helper: checks if a Basic pokemon is the correct base for a Stage 2 (via intermediate Stage 1)
# ISSUE #44: pop a single card up FULL-SCREEN (reusing the trainer-card-view overlay) WHILE its
# message is shown, then hide it — used for "show this card to your opponent" moments so the player
# actually sees the card on screen (like a played trainer) before it animates to its destination.
func show_card_with_message(card: card_object, message: String) -> void:
	# ISSUE #214 / #235: the WHOLE board goes, not a hand-written list of four
	# icons plus a white sheet over the rest. The attack rows beside the active
	# Pokemon were the ones this list kept missing, so they sat over the card that
	# had just been played. See main.set_card_showcase_visible.
	main.set_card_showcase_visible(true)
	var card_display = TextureRect.new()
	card_display.set_script(main.card_display_script)
	main.played_trainer_container.add_child(card_display)
	card_display.load_card_image(card.uid, main.card_scales[1], card)
	await main.show_message(message)
	for child in main.played_trainer_container.get_children():
		main.played_trainer_container.remove_child(child)
		child.queue_free()
	main.set_card_showcase_visible(false)

func effect_pokemon_trader(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	# Find Pokemon in hand
	var pokemon_in_hand = []
	for card in hand:
		if card.metadata.get("supertype", "").to_lower() == "pokémon":
			pokemon_in_hand.append(card)
	
	var pokemon_in_deck = []
	for card in deck:
		if card.metadata.get("supertype", "").to_lower() == "pokémon":
			pokemon_in_deck.append(card)
	
	if pokemon_in_hand.size() == 0 or pokemon_in_deck.size() == 0:
		await main.show_message("Cannot trade - need Pokemon in both hand and deck!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# ISSUE #44 FIX: Pokémon Trader says "show them to your opponent", so the player must SEE both
		# the Pokémon shuffled in and the one taken out, with a message + animation for each step:
		#   1) message "shuffled X into their deck" 2) fly X (face-up) hand->deck 3) shuffle animation
		#   4) message "added Y to their hand"      5) fly Y (face-up) deck->hand.
		print("ISSUE #44 FIX ACTIVE: Pokemon Trader shows both cards with animated hand<->deck flow")
		var trade_away = cpu_get_discard_priority(pokemon_in_hand, 1, played_card)
		if trade_away.size() == 0:
			return
		var card_to_trade = trade_away[0]
		var search_card = main.cpu_ai.cpu_search_deck_for_best_pokemon(pokemon_in_deck)
		if search_card == null:
			return
		# Step 1-3: shuffle the hand Pokémon into the deck. ISSUE #44: pop the card up full-screen WITH
		# the message first (like a played trainer), hide it, THEN animate it moving to the deck.
		await show_card_with_message(card_to_trade, "Opponent shuffled " + card_to_trade.metadata.get("name", "") + " into their deck!")
		if main._should_bail(): return
		hand.erase(card_to_trade)
		card_to_trade.current_location = "deck"
		deck.append(card_to_trade)
		var trade_texture = main.get_card_texture(card_to_trade)
		await main.animate_card_a_to_b(main.opponent_hand_container, main.opponent_deck_icon, 0.3, trade_texture, main.card_scales[12])
		if main._should_bail(): return
		main.refresh_hand_display(true)
		main.update_deck_icon(true)
		deck.shuffle()
		await main.animate_deck_shuffle(true)
		if main._should_bail(): return
		# Step 4-5: take the searched Pokémon out of the deck into the hand. ISSUE #44: pop it up
		# full-screen WITH the message first, hide it, THEN animate it moving to the hand.
		await show_card_with_message(search_card, "Opponent added " + search_card.metadata.get("name", "") + " to their hand!")
		if main._should_bail(): return
		deck.erase(search_card)
		search_card.current_location = "hand"
		hand.append(search_card)
		var search_texture = main.get_card_texture(search_card)
		await main.animate_card_a_to_b(main.opponent_deck_icon, main.opponent_hand_container, 0.3, search_texture, main.card_scales[12])
		if main._should_bail(): return
		main.refresh_hand_display(true)
		main.update_deck_icon(true)
	else:
		var card_to_trade = await main.card_ops.prompt_select_card(pokemon_in_hand, "POKEMON TRADER", "Select a Pokemon from your hand to trade", "TRADE", false)
		if main._should_bail(): return

		if card_to_trade == null:
			return

		var search_card = await main.card_ops.prompt_select_card(pokemon_in_deck, "POKEMON TRADER", "Select a Pokemon from your deck", "TAKE", false, true)
		if main._should_bail(): return
		
		if search_card != null:
			hand.erase(card_to_trade)
			card_to_trade.current_location = "deck"
			deck.append(card_to_trade)
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			deck.shuffle()
			# Animate traded card to deck and searched card to hand
			var trade_texture = main.get_card_texture(card_to_trade)
			main.animate_card_a_to_b(main.player_hand_container, main.player_deck_icon, 0.2, trade_texture, main.card_scales[10])
			await get_tree().create_timer(GameState.match_time(0.2)).timeout
			if main._should_bail(): return
			var search_texture = main.get_card_texture(search_card)
			await main.animate_card_a_to_b(main.player_deck_icon, main.player_hand_container, 0.3, search_texture, main.card_scales[10])
			if main._should_bail(): return
			main.refresh_hand_display(false)
			main.update_deck_icon(false)

# base1-78 — Scoop Up: Return Basic card to hand, discard attachments
func effect_scoop_up(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	# Get all pokemon in play (bench first, active last for spacer display)
	var all_in_play = build_field_pokemon_array(is_opponent)
	
	if all_in_play.size() == 0:
		return
	
	var target: card_object = null
	
	if is_opponent:
		# CPU: pick the pokemon at lowest HP that is guaranteed KO'd
		for pokemon in all_in_play:
			if pokemon.current_hp <= int(pokemon.metadata.get("hp", "0")) / 2:
				target = pokemon
				break
		if target == null:
			return
	else:
		target = await main.card_ops.prompt_select_card(all_in_play, "SCOOP UP", "Select a Pokemon to return its Basic card to your hand", "SCOOP UP", false)
		if main._should_bail(): return
	
	if target == null:
		return
	
	# Find the original Basic card (at the bottom of the pre-evolution chain)
	var basic_card = target
	if target.attached_pre_evolutions.size() > 0:
		basic_card = target.attached_pre_evolutions[0]
		target.attached_pre_evolutions.erase(basic_card)

	# ISSUE #91 FIX: Scoop Up used to resolve entirely off-screen — every attachment vanished at once
	# and the Pokemon was simply gone by the time the message appeared. It is now narrated in the order
	# it happens: announce the play, strip the attachments one at a time (board refreshed after each),
	# then fly the Basic card up into the hand.
	var scooper = "OPPONENT" if is_opponent else "PLAYER"
	print("ISSUE #91 FIX ACTIVE: animating Scoop Up on ", target.metadata.get("name", ""))
	await main.show_message(scooper + " USED SCOOP UP ON " + target.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

	# Grab the on-board node BEFORE anything is removed, so the card can fly from where it sat.
	var target_node = main.find_card_ui_for_object(target)

	# Discard all attachments (energies, evolutions, attached cards) — one at a time, animated.
	await main.card_ops.discard_all_attachments_animated(target, is_opponent)
	if main._should_bail(): return

	# If the target itself is NOT the basic (it's an evolution), discard it too
	if target != basic_card:
		target.current_location = "discard"
		discard.append(target)

	# Remove from play
	if target == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon):
		if is_opponent:
			main.opponent_active_pokemon = null
		else:
			main.player_active_pokemon = null
	elif target in bench:
		bench.erase(target)

	# Return basic card to hand with fresh state
	basic_card.current_location = "hand"
	basic_card.current_hp = basic_card.get_max_hp()
	basic_card.pluspower_count = 0
	basic_card.defender_count = 0
	basic_card.defender_turns_remaining = -1
	main.clear_all_statuses(basic_card, is_opponent)
	hand.append(basic_card)

	# ISSUE #91: fly the Basic card from its board slot to the hand. The board is cleared first so the
	# slot is empty while the card travels, then the hand is refreshed once it lands.
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	var scoop_from = target_node if (target_node != null and is_instance_valid(target_node)) else hand_node
	var basic_texture = main.opponent_card_back_texture if is_opponent else main.get_card_texture(basic_card)
	await main.animate_card_a_to_b(scoop_from, hand_node, 0.3, basic_texture, main.card_scales[10])
	if main._should_bail(): return

	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)

	# If the active was scooped, need bench replacement (no prize)
	var current_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if current_active == null:
		if bench.size() == 0:
			await main.show_message("No Pokemon remaining!")
			if main._should_bail(): return
			main.game_end_logic(not is_opponent)
			return
		if is_opponent:
			var cpu_eval = main.cpu_ai.get_cpu_evaluation()
			var replacement = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, cpu_eval)
			if replacement == null:
				replacement = bench[0]
			bench.erase(replacement)
			replacement.current_location = "active"
			main.opponent_active_pokemon = replacement
			main.display_pokemon(true)
			main.display_active_pokemon_energies(true)
			await main.show_message("Opponent sent " + replacement.metadata.get("name", "") + " to the active spot!")
			if main._should_bail(): return
		else:
			main.knockout_bench_selection_active = true
			main.show_enlarged_array_selection_mode(main.player_bench)
			main.cancel_button.visible = false
			main.header_label.text = "CHOOSE NEW ACTIVE POKEMON"
			main.hint_label.text = "Your active was scooped up - select a replacement"
			main.action_button.text = "SET ACTIVE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.knockout_replacement_chosen
			if main._should_bail(): return
			main.display_active_pokemon_energies(false)

# base1-79 — Super Energy Removal: Discard 1 own energy, remove up to 2 from opponent
func effect_super_energy_removal(is_opponent: bool) -> void:
	var own_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	
	# Find own pokemon with energy (using combined array with active last)
	var own_all = build_field_pokemon_array(is_opponent)
	var own_with_energy = own_all.filter(func(p): return p.attached_energies.size() > 0)
	
	# Find opponent pokemon with energy (using combined array with active last)
	# GYM2 Brock's Protection (gym2-101): exclude protected pokemon
	var target_all = build_field_pokemon_array(not is_opponent)
	var target_with_energy = target_all.filter(func(p): return p.attached_energies.size() > 0 and not p.gym2_brocks_protection_attached)
	
	if own_with_energy.size() == 0:
		await main.show_message("No energy to discard from your own Pokemon!")
		if main._should_bail(): return
		return
	if target_with_energy.size() == 0:
		await main.show_message("Opponent has no energy to remove!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# CPU logic
		var source = own_with_energy[0]
		for p in own_with_energy:
			if p.attached_energies.size() > source.attached_energies.size():
				source = p
		var energy = source.attached_energies.pop_back()
		energy.current_location = "discard"
		own_discard.append(energy)
		
		var target_active = main.player_active_pokemon
		var target = target_active if target_active != null and target_active.attached_energies.size() > 0 else (target_with_energy[0] if target_with_energy.size() > 0 else null)
		if target != null:
			var removed = 0
			while removed < 2 and target.attached_energies.size() > 0:
				var e = target.attached_energies.pop_back()
				e.current_location = "discard"
				target_discard.append(e)
				removed += 1
			await main.show_message("Opponent removed " + str(removed) + " energy from " + target.metadata.get("name", "") + "!")
			if main._should_bail(): return
		main.display_active_pokemon_energies(true)
		main.display_active_pokemon_energies(false)
		main.update_discard_pile_display(false)
		main.update_discard_pile_display(true)
	else:
		var source = await main.card_ops.prompt_select_card(own_with_energy, "SUPER ENERGY REMOVAL - YOUR POKEMON", "Select your Pokemon to discard 1 energy from", "SELECT", false)
		if main._should_bail(): return
		
		if source == null or source.attached_energies.size() == 0:
			return
		
		# Step 2: Player selects which energy to discard from their own pokemon
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(source.attached_energies)
		main.cancel_button.visible = false
		main.header_label.text = "DISCARD YOUR ENERGY"
		main.hint_label.text = "Select 1 energy to discard"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.defender_energy_chosen
		if main._should_bail(): return
		var own_energy = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		
		if own_energy == null:
			return
		source.attached_energies.erase(own_energy)
		own_energy.current_location = "discard"
		own_discard.append(own_energy)
		main.display_active_pokemon_energies(false)
		main.update_discard_pile_display(false)
		
		var target = await main.card_ops.prompt_select_card(target_with_energy, "SUPER ENERGY REMOVAL - OPPONENT", "Select opponent's Pokemon to remove up to 2 energy", "SELECT", false)
		if main._should_bail(): return
		
		if target == null:
			return
		
		# Step 4: Remove up to 2 energy using multi-select
		var max_remove = min(2, target.attached_energies.size())
		var removed = 0
		if max_remove <= 2 and target.attached_energies.size() <= 2:
			# 2 or fewer - just take them all
			while target.attached_energies.size() > 0 and removed < 2:
				var e = target.attached_energies.pop_back()
				e.current_location = "discard"
				target_discard.append(e)
				var from_node = main.find_card_ui_for_object(target)
				if from_node == null:
					from_node = main.opponent_active_container if target == main.opponent_active_pokemon else main.opponent_bench_container
				var e_tex = main.get_card_texture(e)
				await main.animate_card_a_to_b(from_node, main.opponent_discard_icon, 0.2, e_tex, main.card_scales[10])
				if main._should_bail(): return
				removed += 1
		else:
			# Player selects which 2 energies using multi-select mode
			main.trainer_discard_selected.clear()
			main.trainer_discard_cards_needed = 2
			main.trainer_discard_selection_active = true
			
			main.show_enlarged_array_selection_mode(target.attached_energies)
			main.cancel_button.visible = false
			main.header_label.text = "REMOVE ENERGY (SELECT 2)"
			main.hint_label.text = "Select 2 energies to remove (0/2 selected)"
			main.action_button.text = "2 MORE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			
			await main.trainer_discard_selection_done
			if main._should_bail(): return
			main.trainer_discard_selection_active = false
			main.hide_selection_mode_display_main()
			
			for e in main.trainer_discard_selected:
				target.attached_energies.erase(e)
				e.current_location = "discard"
				target_discard.append(e)
				var from_node = main.find_card_ui_for_object(target)
				if from_node == null:
					from_node = main.opponent_active_container if target == main.opponent_active_pokemon else main.opponent_bench_container
				var e_tex = main.get_card_texture(e)
				await main.animate_card_a_to_b(from_node, main.opponent_discard_icon, 0.2, e_tex, main.card_scales[10])
				if main._should_bail(): return
			removed = main.trainer_discard_selected.size()
			main.trainer_discard_selected.clear()
		
		main.display_active_pokemon_energies(true)
		main.update_discard_pile_display(true)
		if removed > 0:
			await main.show_message("Removed " + str(removed) + " energy from " + target.metadata.get("name", "") + "!")
			if main._should_bail(): return

# base1-81 — Energy Retrieval: Discard 1, get up to 2 Basic Energy from discard
func effect_energy_retrieval(played_card: card_object, is_opponent: bool) -> void:
	if check_pokemon_tower_blocks_recovery():
		await main.show_message("POKEMON TOWER! CANNOT RECOVER CARDS FROM DISCARD!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	# Find basic energy in discard
	var basic_energies = []
	for card in discard:
		if main.is_basic_energy_card(card):
			basic_energies.append(card)

	if basic_energies.size() == 0:
		await main.show_message("No Basic Energy cards in discard pile!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 1, played_card)
		if to_discard.size() == 0:
			return
		hand.erase(to_discard[0])
		to_discard[0].current_location = "discard"
		discard.append(to_discard[0])
		
		var retrieved = 0
		for energy in basic_energies.duplicate():
			if retrieved >= 2:
				break
			discard.erase(energy)
			energy.current_location = "hand"
			hand.append(energy)
			retrieved += 1
		await main.show_message("Opponent retrieved " + str(retrieved) + " Basic Energy from discard!")
		if main._should_bail(): return
		main.refresh_hand_display(true)
	else:
		if hand.size() < 1:
			await main.show_message("Not enough cards to discard!")
			if main._should_bail(): return
			return
		await player_select_cards_to_discard(hand, 1, "ENERGY RETRIEVAL", "Select 1 card to discard")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		
		# Player picks up to 2 basic energy from discard using multi-select
		# Recalculate basic energies after discard
		basic_energies.clear()
		for card in discard:
			if main.is_basic_energy_card(card):
				basic_energies.append(card)
		
		if basic_energies.size() > 0:
			var max_retrieve = min(2, basic_energies.size())
			main.trainer_discard_selected.clear()
			main.trainer_discard_cards_needed = max_retrieve
			main.trainer_discard_selection_active = true
			
			main.show_enlarged_array_selection_mode(basic_energies)
			main.header_label.text = "ENERGY RETRIEVAL"
			main.hint_label.text = "Select up to " + str(max_retrieve) + " Basic Energy to retrieve (0/" + str(max_retrieve) + " selected)"
			main.action_button.text = str(max_retrieve) + " MORE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = false
			
			await main.trainer_discard_selection_done
			if main._should_bail(): return
			main.trainer_discard_selection_active = false
			main.hide_selection_mode_display_main()
			
			for card in main.trainer_discard_selected:
				discard.erase(card)
				card.current_location = "hand"
				hand.append(card)
				# Animate each retrieved energy from discard to hand
				var discard_node = main.player_discard_icon
				var energy_texture = main.get_card_texture(card)
				await main.animate_card_a_to_b(discard_node, main.player_hand_container, 0.3, energy_texture, main.card_scales[10])
				if main._should_bail(): return
			main.trainer_discard_selected.clear()
		
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)

# base1-82 — Full Heal: Remove all status conditions from active
func effect_full_heal(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null:
		return
	var had_status = active.special_condition != "" or active.is_poisoned
	main.clear_all_statuses(active, is_opponent)
	if had_status:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		await main.show_message(active.metadata.get("name", "") + " was fully healed of all conditions!")
		if main._should_bail(): return
	else:
		await main.show_message(active.metadata.get("name", "") + " had no conditions to heal.")
		if main._should_bail(): return

# base1-83 — Maintenance: Shuffle 2 cards back, draw 1
func effect_maintenance(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	if hand.size() < 2:
		await main.show_message("Not enough cards in hand!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# ISSUE #41 FIX: announce first, then fly each hidden card (card back) from hand to the deck
		# ONE AT A TIME, play the shuffle animation, then the draw animates in — instead of the two
		# cards vanishing instantly and the message appearing after the draw.
		var to_shuffle = cpu_get_discard_priority(hand, 2, played_card)
		await main.show_message("Opponent shuffled 2 cards into their deck!")
		if main._should_bail(): return
		for card in to_shuffle:
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
			await main.animate_card_a_to_b(main.opponent_hand_container, main.opponent_deck_icon, 0.3, main.opponent_card_back_texture, main.card_scales[12])
			if main._should_bail(): return
			main.refresh_hand_display(true)
			main.update_deck_icon(true)
		deck.shuffle()
		await main.animate_deck_shuffle(true)
		if main._should_bail(): return
		await main.card_ops.draw_n(true, 1)
		if main._should_bail(): return
	else:
		await player_select_cards_to_discard(hand, 2, "MAINTENANCE", "Select 2 cards to shuffle into your deck")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
		main.trainer_discard_selected.clear()
		deck.shuffle()
		await main.card_ops.draw_n(false, 1)
		if main._should_bail(): return

# base1-85 — Pokemon Center: Heal all damage, discard energy from healed pokemon
func effect_pokemon_center(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
	
	var all_pokemon = build_field_pokemon_array(is_opponent)
	
	var healed_any = false
	for pokemon in all_pokemon:
		var max_hp = int(pokemon.metadata.get("hp", "0"))
		var damage = max_hp - pokemon.current_hp
		if damage <= 0:
			continue
		
		healed_any = true
		pokemon.current_hp = max_hp
		
		# Show floating heal label at pokemon location
		var loc = main.get_pokemon_screen_location(pokemon)
		if not loc.is_empty():
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
			main.show_floating_label("+" + str(damage) + " HP", loc["position"] + Vector2(0, -20), Color.GREEN, true)
		
		# Animate energy cards going to discard
		for energy in pokemon.attached_energies:
			energy.current_location = "discard"
			discard.append(energy)
			var from_node = main.find_card_ui_for_object(pokemon)
			if from_node == null:
				from_node = (main.opponent_active_container if is_opponent else main.player_active_container) if pokemon == active else (main.opponent_bench_container if is_opponent else main.player_bench_container)
			var energy_texture = main.get_card_texture(energy)
			main.animate_card_a_to_b(from_node, discard_node, 0.15, energy_texture, main.card_scales[12])
		pokemon.attached_energies.clear()
		
		await get_tree().create_timer(GameState.match_time(0.3)).timeout
		if main._should_bail(): return
	
	if not healed_any:
		await main.show_message("No Pokemon with damage to heal!")
		if main._should_bail(): return
	
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.display_hp_circles_above_align(active, is_opponent)
	main.update_discard_pile_display(is_opponent)

# base1-86 — Pokemon Flute: Put Basic from opponent's discard onto their bench
func effect_pokemon_flute(is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	var target_is_opponent = not is_opponent
	
	if target_bench.size() >= main.get_max_bench_size():
		await main.show_message("Opponent's bench is full!")
		if main._should_bail(): return
		return
	
	var basics_in_discard = []
	for card in target_discard:
		if main.is_basic_pokemon(card):
			basics_in_discard.append(card)
	
	if basics_in_discard.size() == 0:
		await main.show_message("No Basic Pokemon in opponent's discard pile!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# CPU never plays this (scored -100)
		return
	else:
		var chosen = await main.card_ops.prompt_select_card(basics_in_discard, "POKEMON FLUTE", "Choose a Basic Pokemon to place on opponent's bench", "PLACE", false, true)
		if main._should_bail(): return
		
		if chosen != null:
			target_discard.erase(chosen)
			chosen.current_location = "bench"
			chosen.current_hp = chosen.get_max_hp()
			chosen.placed_on_field_this_turn = true
			target_bench.append(chosen)
			# Animate from discard to bench
			var discard_node = main.opponent_discard_icon if target_is_opponent else main.player_discard_icon
			var bench_node = main.opponent_bench_container if target_is_opponent else main.player_bench_container
			var card_texture = main.get_card_texture(chosen)
			await main.animate_card_a_to_b(discard_node, bench_node, 0.3, card_texture, main.card_scales[10])
			if main._should_bail(): return
			main.update_discard_pile_display(target_is_opponent)
			main.display_pokemon(target_is_opponent)
			await main.show_message(chosen.metadata.get("name", "") + " was placed on opponent's bench!")
			if main._should_bail(): return

# base1-87 — Pokedex: Look at top 5 cards and rearrange
func effect_pokedex(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	var count = min(5, deck.size())
	if count == 0:
		await main.show_message("Deck is empty!")
		if main._should_bail(): return
		return
	
	var top_cards = []
	for i in range(count):
		top_cards.append(deck[i])
	
	if is_opponent:
		# CPU reorder using priority
		top_cards.sort_custom(func(a, b): return _cpu_pokedex_priority(a) > _cpu_pokedex_priority(b))
		for i in range(count):
			deck[i] = top_cards[i]
		await main.show_message("Opponent rearranged the top " + str(count) + " cards of their deck!")
		if main._should_bail(): return
	else:
		# Player: show all cards at once, click in order to assign position numbers
		main.pokedex_cards = top_cards.duplicate()
		main.pokedex_reorder_result.clear()
		main.trainer_reorder_active = true
		
		main.show_enlarged_array_selection_mode(main.pokedex_cards)
		main.header_label.text = "POKEDEX - CLICK CARDS IN ORDER"
		main.hint_label.text = "Click cards in the order you want them (top of deck first)"
		main.action_button.text = "0/" + str(count) + " SELECTED"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		
		await main.trainer_reorder_done
		if main._should_bail(): return
		main.trainer_reorder_active = false
		main.hide_selection_mode_display_main()
		
		# Apply the new order
		for i in range(main.pokedex_reorder_result.size()):
			deck[i] = main.pokedex_reorder_result[i]
		main.pokedex_cards.clear()
		main.pokedex_reorder_result.clear()

# CPU Pokedex priority helper
func effect_revive(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("Bench is full!")
		if main._should_bail(): return
		return
	
	var basics_in_discard = []
	for card in discard:
		if main.is_basic_pokemon(card):
			basics_in_discard.append(card)
	
	if basics_in_discard.size() == 0:
		await main.show_message("No Basic Pokemon in discard pile!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# CPU: pick highest scoring basic
		var best: card_object = null
		var best_score = -999.0
		for card in basics_in_discard:
			var result = main.cpu_ai.evaluate_opponents_start_setup_pokemon_choices(card, main.opponent_hand)
			var score = result.get("total_score", 0)
			if score > best_score:
				best_score = score
				best = card
		if best != null:
			discard.erase(best)
			best.current_location = "bench"
			var max_hp = int(best.metadata.get("hp", "0"))
			best.current_hp = max(10, max_hp / 2)
			best.placed_on_field_this_turn = true
			bench.append(best)
			main.display_pokemon(true)
			await main.show_message("Opponent revived " + best.metadata.get("name", "") + " at half HP!")
			if main._should_bail(): return
	else:
		var chosen = await main.card_ops.prompt_select_card(basics_in_discard, "REVIVE", "Select a Basic Pokemon to revive at half HP", "REVIVE", false, true)
		if main._should_bail(): return
		
		if chosen != null:
			discard.erase(chosen)
			chosen.current_location = "bench"
			var max_hp = int(chosen.metadata.get("hp", "0"))
			chosen.current_hp = max(10, (max_hp / 20) * 10) # Half HP rounded down to nearest 10
			chosen.placed_on_field_this_turn = true
			bench.append(chosen)
			main.display_pokemon(false)
			await main.show_message(chosen.metadata.get("name", "") + " revived at " + str(chosen.current_hp) + " HP!")
			if main._should_bail(): return

# base1-90 — Super Potion: Discard 1 energy from pokemon, remove up to 4 damage counters
func effect_super_potion(card: card_object, is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	# Find pokemon with both damage and energy
	var valid_targets = []
	var all_pokemon = build_field_pokemon_array(is_opponent)
	for p in all_pokemon:
		if p.current_hp < int(p.metadata.get("hp", "0")) and p.attached_energies.size() > 0:
			valid_targets.append(p)

	if valid_targets.size() == 0:
		await main.show_message("No Pokemon with both damage and energy!")
		if main._should_bail(): return
		return

	if is_opponent:
		var best_target: card_object = null
		var most_damage = 0
		for pokemon in valid_targets:
			var dmg = int(pokemon.metadata.get("hp", "0")) - pokemon.current_hp
			if dmg > most_damage:
				most_damage = dmg
				best_target = pokemon
		if best_target != null:
			var energy = best_target.attached_energies.pop_back()
			energy.current_location = "discard"
			discard.append(energy)
			main.display_active_pokemon_energies(true)
			await main.card_ops.heal_pokemon(best_target, 40, true)
			if main._should_bail(): return
			main.update_discard_pile_display(true)
	else:
		# ISSUE #25 FIX: let the player pick the target AND which energy to discard, and allow them
		# to cancel out at either step (the card is refunded to hand, mirroring the tax-refund path).
		print("ISSUE #25 FIX ACTIVE: Super Potion now prompts for energy choice + allows cancel")
		var target = await main.card_ops.prompt_select_card(valid_targets, "SUPER POTION", "Select a Pokemon to heal (will discard 1 energy)", "HEAL", true)
		if main._should_bail(): return
		if target == null:
			_refund_trainer_to_hand(card, is_opponent)
			return
		# Choose which energy to discard (cancelable). remove_one_energy handles the pick UI,
		# the fly-to-discard animation and Recycle Energy, returning null if the player cancels.
		var removed = await main.card_ops.remove_one_energy(target, false, false, null, true)
		if main._should_bail(): return
		if removed == null:
			_refund_trainer_to_hand(card, is_opponent)
			return
		main.update_discard_pile_display(false)
		await main.card_ops.heal_pokemon(target, 40, false)
		if main._should_bail(): return

# Refund a standard trainer card that the player cancelled mid-effect back to their hand.
# (play_trainer_card has already moved it to the discard pile before resolving the effect.)
func _refund_trainer_to_hand(card: card_object, is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if card in discard:
		discard.erase(card)
	card.current_location = "hand"
	if card not in hand:
		hand.append(card)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)

# base1-92 — Energy Removal: Discard 1 energy from opponent's pokemon
func effect_energy_removal(is_opponent: bool) -> void:
	var target_is_opp = not is_opponent
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile

	# Build combined array with energy, active last
	var all_targets = build_field_pokemon_array(target_is_opp)
	# GYM2 Brock's Protection (gym2-101): exclude protected pokemon from opp's Trainer-card energy removal
	var targets_with_energy = all_targets.filter(func(p): return p.attached_energies.size() > 0 and not p.gym2_brocks_protection_attached)

	if targets_with_energy.size() == 0:
		await main.show_message("Opponent has no energy to remove!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		var target_active = main.player_active_pokemon
		var target = target_active if target_active != null and target_active.attached_energies.size() > 0 else targets_with_energy[0]
		var energy = target.attached_energies.pop_back()
		energy.current_location = "discard"
		target_discard.append(energy)
		var from_node = main.find_card_ui_for_object(target)
		if from_node == null:
			from_node = main.player_active_container
		var energy_texture = main.get_card_texture(energy)
		await main.animate_card_a_to_b(from_node, main.player_discard_icon, 0.2, energy_texture, main.card_scales[10])
		if main._should_bail(): return
		main.display_active_pokemon_energies(false)
		main.update_discard_pile_display(false)
		await main.show_message("Opponent removed energy from " + target.metadata.get("name", "") + "!")
		if main._should_bail(): return
	else:
		var target = await main.card_ops.prompt_select_card(targets_with_energy, "ENERGY REMOVAL", "Select opponent's Pokemon to remove energy from", "SELECT", false)
		if main._should_bail(): return

		if target != null and target.attached_energies.size() > 0:
			main.defender_energy_discard_active = true
			main.show_enlarged_array_selection_mode(target.attached_energies)
			main.cancel_button.visible = false
			main.header_label.text = "CHOOSE ENERGY TO REMOVE"
			main.hint_label.text = "Select an energy card to discard"
			main.action_button.text = "DISCARD"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.defender_energy_chosen
			if main._should_bail(): return
			var energy = main.selected_card_for_action
			main.defender_energy_discard_active = false
			main.hide_selection_mode_display_main()
			
			if energy != null:
				target.attached_energies.erase(energy)
				energy.current_location = "discard"
				target_discard.append(energy)
				var from_node = main.find_card_ui_for_object(target)
				if from_node == null:
					from_node = main.opponent_active_container if target == main.opponent_active_pokemon else main.opponent_bench_container
				var energy_texture = main.get_card_texture(energy)
				await main.animate_card_a_to_b(from_node, main.opponent_discard_icon, 0.2, energy_texture, main.card_scales[10])
				if main._should_bail(): return
				main.display_active_pokemon_energies(true)
				main.update_discard_pile_display(true)

# base1-93 — Gust of Wind: Switch opponent's active with a bench pokemon
func effect_gust_of_wind(is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var target_is_opp = not is_opponent
	
	if target_bench.size() == 0:
		await main.show_message("Opponent has no bench Pokemon!")
		if main._should_bail(): return
		return
	
	var new_active: card_object = null
	
	if is_opponent:
		# CPU: pull in easiest to KO target
		var best: card_object = null
		var best_score = -999.0
		for bp in target_bench:
			var score = 0.0
			# Low HP = easy KO
			score += (200.0 - bp.current_hp)
			# No energy = can't fight back
			if bp.attached_energies.size() == 0:
				score += 100.0
			if score > best_score:
				best_score = score
				best = bp
		new_active = best
	else:
		new_active = await main.card_ops.prompt_select_card(target_bench, "GUST OF WIND", "Select opponent's bench Pokemon to pull forward", "SWITCH", false)
		if main._should_bail(): return
	
	if new_active != null:
		var old_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		var bench = target_bench
		
		bench.erase(new_active)
		bench.append(old_active)
		old_active.current_location = "bench"
		new_active.current_location = "active"
		
		if is_opponent:
			main.player_active_pokemon = new_active
		else:
			main.opponent_active_pokemon = new_active
		
		await main.animate_retreat(old_active, new_active, [], target_is_opp, true)
		if main._should_bail(): return
		main.clear_all_statuses(old_active, target_is_opp)
		main.display_pokemon(target_is_opp)
		main.display_active_pokemon_energies(target_is_opp)
		await main.show_message(new_active.metadata.get("name", "") + " was pulled to the active spot!")
		if main._should_bail(): return

# base1-94 — Potion: Remove up to 2 damage counters from 1 pokemon
func effect_potion(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	
	var damaged = build_field_pokemon_array(is_opponent).filter(func(p): return p.current_hp < int(p.metadata.get("hp", "0")))
	
	if damaged.size() == 0:
		await main.show_message("No Pokemon with damage!")
		if main._should_bail(): return
		return
	
	if is_opponent:
		# ISSUE #164: NOT damaged[0], which is the first BENCH Pokemon. The CPU
		# healed a benched 30/70 while its 30/60 Active was one attack from being
		# knocked out. cpu_pick_heal_target weighs saving the Active above the
		# damage fraction — see cpu_rank_heal_target.
		var target = main.cpu_ai.cpu_pick_heal_target(damaged, 20)
		if target == null:
			target = damaged[0]
		print("ISSUE #164 FIX ACTIVE: CPU Potion targets ", target.metadata.get("name", ""),
			" (active=", target == main.opponent_active_pokemon, ")")
		await main.card_ops.heal_pokemon(target, 20, true)
		if main._should_bail(): return
	else:
		var target = await main.card_ops.prompt_select_card(damaged, "POTION", "Select a Pokemon to heal (up to 20 HP)", "HEAL", false)
		if main._should_bail(): return

		if target != null:
			await main.card_ops.heal_pokemon(target, 20, false)
			if main._should_bail(): return

# base1-95 — Switch: Free retreat (swap active with bench)
func effect_switch(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	
	if bench.size() == 0:
		await main.show_message("No bench Pokemon to switch with!")
		if main._should_bail(): return
		return
	
	if active == null:
		return
	
	if is_opponent:
		var cpu_eval = main.cpu_ai.get_cpu_evaluation()
		var replacement = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, cpu_eval)
		if replacement == null:
			replacement = bench[0]
		
		bench.erase(replacement)
		bench.append(active)
		active.current_location = "bench"
		replacement.current_location = "active"
		main.opponent_active_pokemon = replacement
		await main.animate_retreat(active, replacement, [], true, true)
		if main._should_bail(): return
		main.clear_all_statuses(active, true)
		main.display_pokemon(true)
		main.display_active_pokemon_energies(true)
		await main.show_message("Opponent switched to " + replacement.metadata.get("name", "") + "!")
		if main._should_bail(): return
	else:
		var replacement = await main.card_ops.prompt_select_card(bench, "SWITCH", "Select a bench Pokemon to switch with your active", "SWITCH", false)
		if main._should_bail(): return
		
		if replacement != null:
			bench.erase(replacement)
			bench.append(active)
			active.current_location = "bench"
			replacement.current_location = "active"
			main.player_active_pokemon = replacement
			await main.animate_retreat(active, replacement, [], false, true)
			if main._should_bail(): return
			main.clear_all_statuses(active, false)
			main.display_pokemon(false)
			main.display_active_pokemon_energies(false)

############################################### Section E: PLAYER TRAINER UI HELPERS ################################################################

# Shows hand cards for player to select N cards to discard



# base2-64 — Poké Ball: Flip coin, heads = search deck for any Basic or Evolution
func effect_poke_ball(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	await main.show_message("POKE BALL: FLIPPING COIN...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	
	if not coin:
		await main.show_message("TAILS! POKE BALL FAILED!")
		if main._should_bail(): return
		return
	
	await main.show_message("HEADS! SEARCH YOUR DECK!")
	if main._should_bail(): return
	
	# Find all Basic and Evolution pokemon in deck
	var matching = []
	for card in deck:
		var supertype = card.metadata.get("supertype", "")
		var subtypes = card.metadata.get("subtypes", [])
		if supertype == "Pokémon":
			if "Basic" in subtypes or "Stage 1" in subtypes or "Stage 2" in subtypes:
				matching.append(card)
	
	if matching.size() == 0:
		await main.show_message("NO POKEMON FOUND IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	
	var chosen: card_object = null
	
	if is_opponent:
		# CPU picks the best pokemon
		# Prefer evolutions that match bench/active, then basics
		var best: card_object = null
		var best_score = -1
		for card in matching:
			var score = 0
			var subtypes = card.metadata.get("subtypes", [])
			var evolves_from = card.metadata.get("evolvesFrom", "")
			
			# Check if this evolution matches something on field
			if "Stage 1" in subtypes or "Stage 2" in subtypes:
				var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
				for p in all_cpu:
					if p.metadata.get("name", "") == evolves_from:
						score += 50
						break
			
			# Basics score lower
			if "Basic" in subtypes:
				score += 10
			
			var hp = int(card.metadata.get("hp", "0"))
			score += hp / 10
			
			if score > best_score:
				best_score = score
				best = card
		
		chosen = best
	else:
		# Player selects from matching cards
		chosen = await main.card_ops.prompt_select_card(matching, "POKE BALL: CHOOSE A POKEMON", "Select a Basic or Evolution Pokemon", "TAKE", true, true)
		if main._should_bail(): return
	
	if chosen != null:
		var hand = main.opponent_hand if is_opponent else main.player_hand
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		await main.show_message(chosen.metadata.get("name", "").to_upper() + " ADDED TO HAND!")
		if main._should_bail(): return
	
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	print("TRAINER APPLIED: Poke Ball complete")


######################################################################################################################################################
############################################## BASE3 (FOSSIL) TRAINER EFFECTS ########################################################################
######################################################################################################################################################

# base3-58 — Mr. Fuji: Choose a bench Pokemon, shuffle it and all attached cards into deck
func effect_mr_fuji(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	if bench.size() == 0:
		await main.show_message("NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	
	var chosen: card_object = null
	
	if is_opponent:
		# CPU picks the most damaged pokemon (save it by shuffling back)
		var most_damaged: card_object = null
		var most_damage = 0
		for bp in bench:
			var dmg = int(bp.metadata.get("hp", "0")) - bp.current_hp
			if dmg > most_damage:
				most_damage = dmg
				most_damaged = bp
		# Only use if there's a significantly damaged pokemon
		if most_damaged != null and most_damage >= 30:
			chosen = most_damaged
		elif bench.size() > 0:
			# Pick worst pokemon on bench
			var worst_hp = 9999
			for bp in bench:
				var hp = int(bp.metadata.get("hp", "0"))
				if hp < worst_hp:
					worst_hp = hp
					chosen = bp
	else:
		# Player selects
		chosen = await main.card_ops.prompt_select_card(bench, "MR. FUJI: CHOOSE A BENCHED POKEMON", "This Pokemon and all attached cards will be shuffled into your deck", "SHUFFLE BACK", false)
		if main._should_bail(): return
	
	if chosen == null:
		return
	
	var pokemon_name = chosen.metadata.get("name", "").to_upper()
	
	# Shuffle all attached energies into deck
	for e in chosen.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	chosen.attached_energies.clear()
	
	# Shuffle all pre-evolutions into deck
	for pre in chosen.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	chosen.attached_pre_evolutions.clear()
	
	# Shuffle all attached cards into deck
	for ac in chosen.attached_cards:
		ac.current_location = "deck"
		deck.append(ac)
	chosen.attached_cards.clear()
	
	# Shuffle the pokemon itself into deck
	bench.erase(chosen)
	chosen.current_location = "deck"
	main.clear_all_statuses(chosen, is_opponent)
	deck.append(chosen)
	
	# Shuffle the deck
	deck.shuffle()
	
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("MR. FUJI: " + pokemon_name + " SHUFFLED BACK INTO DECK!")
	if main._should_bail(): return
	print("MR. FUJI: Shuffled ", pokemon_name, " and attached cards into deck")

# base3-59 — Energy Search: Search deck for a basic Energy card, add to hand
func effect_energy_search(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	
	# Find basic energy cards in deck
	var basic_energies: Array = []
	for card in deck:
		if card.metadata.get("supertype", "") == "Energy":
			var subtypes = card.metadata.get("subtypes", [])
			# Basic energies don't have "Special" subtype
			if "Special" not in subtypes:
				basic_energies.append(card)
	
	if basic_energies.size() == 0:
		await main.show_message("NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	
	var chosen: card_object = null
	
	if is_opponent:
		# CPU picks the energy type it needs most
		var active = main.opponent_active_pokemon
		if active != null:
			var needed_types: Array = []
			for attack in active.metadata.get("attacks", []):
				for cost in attack.get("cost", []):
					if cost != "Colorless" and cost not in needed_types:
						needed_types.append(cost)
			# Pick matching energy
			for e in basic_energies:
				var e_name = e.metadata.get("name", "")
				for nt in needed_types:
					if nt in e_name:
						chosen = e
						break
				if chosen != null:
					break
		if chosen == null:
			chosen = basic_energies[0]
	else:
		# Player selects
		chosen = await main.card_ops.prompt_select_card(basic_energies, "ENERGY SEARCH: CHOOSE A BASIC ENERGY", "Select a basic Energy card to add to your hand", "SELECT", false, true)
		if main._should_bail(): return
	
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		# ISSUE #86 FIX: Energy Search has no "Show this card to your opponent" clause, so naming the
		# card the CPU took leaked hidden information. The "ADDED <NAME> TO HAND" message is gone; a card
		# gliding from the deck to the hand conveys the same thing without revealing anything. The
		# opponent's card flies FACE DOWN (its sleeve); the player already chose theirs, so it flies
		# face up.
		var search_texture = main.opponent_card_back_texture if is_opponent else main.get_card_texture(chosen)
		var deck_icon = main.opponent_deck_icon if is_opponent else main.player_deck_icon
		var hand_container = main.opponent_hand_container if is_opponent else main.player_hand_container
		print("ISSUE #86 FIX ACTIVE: Energy Search animates deck->hand with no reveal message")
		await main.animate_card_a_to_b(deck_icon, hand_container, 0.3, search_texture, main.card_scales[12])
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
		main.update_deck_icon(is_opponent)

	deck.shuffle()

# base3-60 — Gambler: Shuffle hand into deck, flip coin, heads=draw 8, tails=draw 1
func effect_gambler(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	# Shuffle entire hand into deck (Gambler itself is already in discard)
	var hand_copy = hand.duplicate()
	for card in hand_copy:
		card.current_location = "deck"
		deck.append(card)
	hand.clear()
	main.refresh_hand_display(is_opponent)
	
	deck.shuffle()
	
	await main.show_message("GAMBLER: HAND SHUFFLED INTO DECK! FLIPPING COIN...")
	if main._should_bail(): return

	var coin = await main.flip_coin(false, is_opponent)
	var draw_count = 8 if coin else 1
	
	if coin:
		await main.show_message("HEADS! DRAWING 8 CARDS!")
	else:
		await main.show_message("TAILS! DRAWING 1 CARD!")
	if main._should_bail(): return
	
	await main.card_ops.draw_n(is_opponent, draw_count)
	if main._should_bail(): return
	print("GAMBLER: ", "Heads" if coin else "Tails", " -> Drew ", draw_count, " cards")

# base3-61 — Recycle: Flip coin, if heads put a card from discard on top of deck
func effect_recycle(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	if discard.size() == 0:
		await main.show_message("DISCARD PILE IS EMPTY!")
		if main._should_bail(): return
		return
	
	await main.show_message("RECYCLE: FLIPPING COIN...")
	if main._should_bail(): return

	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! RECYCLE FAILED!")
		if main._should_bail(): return
		return
	
	await main.show_message("HEADS! CHOOSE A CARD FROM DISCARD!")
	if main._should_bail(): return
	
	var chosen: card_object = null
	
	if is_opponent:
		# CPU picks the most useful card
		# Priority: evolution needed > energy needed > trainer > other
		var best_card: card_object = null
		var best_score = -999.0
		for card in discard:
			var score = 0.0
			var st = card.metadata.get("supertype", "")
			if st == "Pokémon":
				var subtypes = card.metadata.get("subtypes", [])
				if "Stage 1" in subtypes or "Stage 2" in subtypes:
					# Check if evolution target exists on field
					var targets = main.get_valid_evolution_targets(card, true)
					if targets.size() > 0:
						score = 80.0
					else:
						score = 20.0
				else:
					score = 15.0
			elif st == "Energy":
				score = 30.0
			elif st == "Trainer":
				score = main.cpu_ai.cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				best_card = card
		chosen = best_card
	else:
		# Player selects
		chosen = await main.card_ops.prompt_select_card(discard, "RECYCLE: CHOOSE A CARD", "This card will be placed on top of your deck", "RECYCLE", false)
		if main._should_bail(): return
	
	if chosen != null:
		discard.erase(chosen)
		chosen.current_location = "deck"
		deck.insert(0, chosen)  # Put on TOP of deck
		main.update_discard_pile_display(is_opponent)
		await main.show_message("RECYCLE: " + chosen.metadata.get("name", "").to_upper() + " PUT ON TOP OF DECK!")
		if main._should_bail(): return
		print("RECYCLE: ", chosen.metadata.get("name", ""), " placed on top of deck")

# Helper: Reset trainer lock at start of turn
func reset_trainer_lock(is_opponent: bool) -> void:
	if is_opponent:
		opponent_trainer_locked = false
	else:
		player_trainer_locked = false

######################################################################################################################################################
################################################### BASE5 (TEAM ROCKET) TRAINER EFFECTS ##############################################################
######################################################################################################################################################

# Here Comes Team Rocket!: Both players' prizes face up
func effect_here_comes_team_rocket(is_opponent: bool) -> void:
	main.player_prizes_face_up = true
	main.opponent_prizes_face_up = true
	main.display_prize_cards(false)
	main.display_prize_cards(true)
	await main.show_message("ALL PRIZE CARDS ARE NOW FACE UP!")
	if main._should_bail(): return
	print("TRAINER: Here Comes Team Rocket! - prizes face up")

# Rocket's Sneak Attack: Look at opponent's hand, shuffle 1 Trainer into deck
func effect_rockets_sneak_attack(is_opponent: bool) -> void:
	var target_hand = main.player_hand if is_opponent else main.opponent_hand
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	
	# Find trainer cards in opponent's hand
	var trainer_cards: Array = []
	for card in target_hand:
		if card.metadata.get("supertype", "") == "Trainer":
			trainer_cards.append(card)
	
	if trainer_cards.size() == 0:
		await main.show_message("NO TRAINER CARDS IN OPPONENT'S HAND!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		# Player sees opponent's hand and picks a trainer
		selected = await main.card_ops.prompt_select_card(trainer_cards, "CHOOSE A TRAINER TO SHUFFLE INTO DECK", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks the most impactful trainer (highest discard priority = keep, so pick lowest)
		var best: card_object = null
		var best_score = 999.0
		for card in trainer_cards:
			var score = _score_card_for_discard(card)
			if score < best_score:
				best_score = score
				best = card
		selected = best if best != null else trainer_cards[0]
	
	if selected == null:
		return
	
	target_hand.erase(selected)
	selected.current_location = "deck"
	target_deck.append(selected)
	target_deck.shuffle()
	
	main.refresh_hand_display(!is_opponent)
	main.update_deck_icon(!is_opponent)
	await main.show_message(selected.metadata.get("name", "").to_upper() + " SHUFFLED INTO DECK!")
	if main._should_bail(): return
	print("TRAINER: Rocket's Sneak Attack - shuffled ", selected.metadata.get("name", ""))

# The Boss's Way: Search deck for a Dark evolution card
func effect_the_boss_way(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	var dark_evolutions: Array = []
	for card in deck:
		var name = card.metadata.get("name", "")
		var subtypes = card.metadata.get("subtypes", [])
		if name.begins_with("Dark ") and card.metadata.get("supertype", "") == "Pokémon":
			if "Stage 1" in subtypes or "Stage 2" in subtypes:
				dark_evolutions.append(card)
	
	if dark_evolutions.size() == 0:
		await main.show_message("NO DARK EVOLUTION CARDS IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		selected = await main.card_ops.prompt_select_card(dark_evolutions, "CHOOSE A DARK EVOLUTION CARD", "", "SELECT", false, true)
		if main._should_bail(): return
	else:
		selected = main.cpu_ai.cpu_search_deck_for_best_pokemon(dark_evolutions)
		if selected == null:
			selected = dark_evolutions[0]
	
	if selected == null:
		return
	
	var hand = main.opponent_hand if is_opponent else main.player_hand
	deck.erase(selected)
	selected.current_location = "hand"
	hand.append(selected)
	deck.shuffle()
	
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ADDED " + selected.metadata.get("name", "").to_upper() + " TO HAND!")
	if main._should_bail(): return
	print("TRAINER: The Boss's Way - found ", selected.metadata.get("name", ""))

# Challenge!: Opponent accepts (both search for basics) or declines (you draw 2)
func effect_challenge(is_opponent: bool) -> void:
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	
	# For CPU: accept if bench has space and deck has basics, otherwise decline
	var accepted = false
	
	if is_opponent:
		# CPU played Challenge - player decides
		# For simplicity, auto-decline (player draws 2 for CPU, CPU draws 2 for player)
		# Actually the rule is: if opponent declines OR both benches full, the player who played it draws 2
		if own_bench.size() >= main.get_max_bench_size() and opp_bench.size() >= main.get_max_bench_size():
			# Both benches full
			await main.card_ops.draw_n(is_opponent, 2)
			if main._should_bail(): return
			await main.show_message("BOTH BENCHES FULL! DREW 2 CARDS!")
			if main._should_bail(): return
			return
		# CPU played it - player can accept or decline
		# Simplify: player declines, CPU draws 2
		await main.card_ops.draw_n(is_opponent, 2)
		if main._should_bail(): return
		await main.show_message("CHALLENGE DECLINED! DREW 2 CARDS!")
		if main._should_bail(): return
	else:
		# Player played Challenge - CPU decides
		# CPU accepts if it has basics in deck and bench space
		var cpu_deck = main.opponent_deck
		var cpu_has_basics = false
		for card in cpu_deck:
			if main.is_basic_pokemon(card):
				cpu_has_basics = true
				break
		
		if cpu_has_basics and opp_bench.size() < 5:
			accepted = true
		
		if not accepted or (own_bench.size() >= main.get_max_bench_size() and opp_bench.size() >= main.get_max_bench_size()):
			# Declined or both full
			await main.card_ops.draw_n(is_opponent, 2)
			if main._should_bail(): return
			await main.show_message("CHALLENGE DECLINED! DREW 2 CARDS!")
			if main._should_bail(): return
		else:
			await main.show_message("CHALLENGE ACCEPTED!")
			if main._should_bail(): return
			
			# Both search for basics
			# Player searches
			var player_deck = main.player_deck
			var player_basics: Array = []
			for card in player_deck:
				if main.is_basic_pokemon(card):
					player_basics.append(card)
			
			if player_basics.size() > 0 and main.player_bench.size() < 5:
				var player_pick = await main.card_ops.prompt_select_card(player_basics, "CHOOSE BASIC POKÉMON FOR BENCH", "", "SELECT", false, true)
				if main._should_bail(): return
				
				if player_pick != null:
					player_deck.erase(player_pick)
					player_pick.current_location = "bench"
					player_pick.placed_on_field_this_turn = true
					main.player_bench.append(player_pick)
			
			# CPU searches
			var cpu_basics: Array = []
			for card in cpu_deck:
				if main.is_basic_pokemon(card):
					cpu_basics.append(card)
			
			if cpu_basics.size() > 0 and main.opponent_bench.size() < 5:
				var cpu_pick = main.cpu_ai.cpu_search_deck_for_best_pokemon(cpu_basics)
				if cpu_pick != null:
					cpu_deck.erase(cpu_pick)
					cpu_pick.current_location = "bench"
					cpu_pick.placed_on_field_this_turn = true
					main.opponent_bench.append(cpu_pick)
			
			player_deck.shuffle()
			cpu_deck.shuffle()
			main.display_pokemon(false)
			main.display_pokemon(true)
			main.update_deck_icon(false)
			main.update_deck_icon(true)
			await main.show_message("BOTH PLAYERS SEARCHED FOR BASICS!")
			if main._should_bail(): return
	
	print("TRAINER: Challenge!")

# Digger: Recursive coin flip damage
func effect_digger(is_opponent: bool) -> void:
	var current_side_is_player = !is_opponent  # Starts with the person who played the card
	# Actually the card says: flip. tails = 10 to YOUR active. heads = opponent flips...
	# "If tails, do 10 damage to your Active Pokémon. If heads, your opponent flips..."
	
	var active_self = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var active_opp = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	
	var my_turn = true  # Player who played card goes first
	var rounds = 0
	var max_rounds = 20  # Safety limit
	
	while rounds < max_rounds:
		# Digger alternates: cardholder flips first, then opponent, then cardholder, etc.
		# my_turn=true means the cardholder flips (= is_opponent), else the other side.
		var flipper_is_opp: bool = is_opponent if my_turn else not is_opponent
		var coin = await main.flip_coin(false, flipper_is_opp)
		rounds += 1
		
		if not coin:
			# Tails - damage current flipper's active
			var target: card_object
			var target_is_opp: bool
			if my_turn:
				target = active_self
				target_is_opp = is_opponent
			else:
				target = active_opp
				target_is_opp = !is_opponent
			
			if target != null:
				target.current_hp = max(0, target.current_hp - 10)
				main.display_hp_circles_above_align(target, target_is_opp)
				var owner = "YOUR" if my_turn else "OPPONENT'S"
				await main.show_message("TAILS! 10 DAMAGE TO " + owner + " ACTIVE!")
				if main._should_bail(): return
			break
		else:
			await main.show_message("HEADS! OTHER PLAYER FLIPS!")
			if main._should_bail(): return
			my_turn = !my_turn
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("TRAINER: Digger - ", rounds, " flips")

# Imposter Oak's Revenge: Discard 1 from hand, opponent shuffles hand into deck + draws 4
func effect_imposter_oaks_revenge(played_card: card_object, is_opponent: bool) -> void:
	var own_hand = main.opponent_hand if is_opponent else main.player_hand
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	
	# Discard 1 card from own hand (not counting the played card which was already removed)
	if own_hand.size() == 0:
		await main.show_message("NO CARDS TO DISCARD!")
		if main._should_bail(): return
		return
	
	if not is_opponent:
		# Player discards 1
		await player_select_cards_to_discard(own_hand, 1, "DISCARD 1 CARD", "Choose a card to discard")
		if main._should_bail(): return
	else:
		# CPU discards lowest priority
		var to_discard = cpu_get_discard_priority(own_hand, 1)
		var discard_pile = main.opponent_discard_pile
		for card in to_discard:
			own_hand.erase(card)
			card.current_location = "discard"
			discard_pile.append(card)
		main.refresh_hand_display(true)
	
	# Opponent shuffles hand into deck and draws 4
	for card in opp_hand.duplicate():
		opp_hand.erase(card)
		card.current_location = "deck"
		opp_deck.append(card)
	opp_deck.shuffle()
	main.refresh_hand_display(!is_opponent)
	
	await main.show_message("OPPONENT SHUFFLED HAND INTO DECK!")
	if main._should_bail(): return
	
	var draw_count = min(4, opp_deck.size())
	await main.card_ops.draw_n(!is_opponent, draw_count)
	if main._should_bail(): return
	await main.show_message("OPPONENT DREW " + str(draw_count) + " CARDS!")
	if main._should_bail(): return
	print("TRAINER: Imposter Oak's Revenge")

# Nightly Garbage Run: Choose up to 3 Basic Pokemon/Evolution/basic Energy from discard, shuffle into deck
func effect_nightly_garbage_run(is_opponent: bool) -> void:
	if check_pokemon_tower_blocks_recovery():
		await main.show_message("POKEMON TOWER! CANNOT RECOVER CARDS FROM DISCARD!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	var valid_cards: Array = []
	for card in discard:
		var supertype = card.metadata.get("supertype", "")
		if supertype == "Pokémon":
			valid_cards.append(card)
		elif main.is_basic_energy_card(card):
			valid_cards.append(card)
	
	if valid_cards.size() == 0:
		await main.show_message("NO VALID CARDS IN DISCARD PILE!")
		if main._should_bail(): return
		return
	
	var chosen: Array = []
	var max_picks = min(3, valid_cards.size())
	
	if not is_opponent:
		# Player selects up to 3
		for i in range(max_picks):
			var remaining: Array = []
			for card in valid_cards:
				if card not in chosen:
					remaining.append(card)
			if remaining.size() == 0:
				break
			
			var pick = await main.card_ops.prompt_select_card(remaining, "CHOOSE CARD " + str(i + 1) + "/" + str(max_picks) + " (OR DONE)", "", "SELECT", true)
			if main._should_bail(): return
			
			if pick != null:
				chosen.append(pick)
			else:
				break
	else:
		# CPU picks best cards: prioritize evolution cards, then basics, then energy
		valid_cards.sort_custom(func(a, b):
			var a_score = 3 if "Stage" in str(a.metadata.get("subtypes", [])) else (2 if a.metadata.get("supertype", "") == "Pokémon" else 1)
			var b_score = 3 if "Stage" in str(b.metadata.get("subtypes", [])) else (2 if b.metadata.get("supertype", "") == "Pokémon" else 1)
			return a_score > b_score
		)
		for i in range(max_picks):
			chosen.append(valid_cards[i])
	
	# Shuffle chosen cards into deck
	for card in chosen:
		discard.erase(card)
		card.current_location = "deck"
		deck.append(card)
	deck.shuffle()
	
	main.update_discard_pile_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SHUFFLED " + str(chosen.size()) + " CARD(S) INTO DECK!")
	if main._should_bail(): return
	print("TRAINER: Nightly Garbage Run - ", chosen.size(), " cards")

# Goop Gas Attack: All Pokemon Powers stop working until end of opponent's next turn
func effect_goop_gas_attack(is_opponent: bool) -> void:
	main.goop_gas_active = true
	main.goop_gas_owner_is_opponent = is_opponent
	await main.show_message("ALL POKÉMON POWERS STOP WORKING!")
	if main._should_bail(): return
	print("TRAINER: Goop Gas Attack - powers disabled")

# Sleep!: Flip heads, defending Pokemon is Asleep
func effect_sleep_trainer(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		if defender != null:
			main.card_ops.apply_status(defender, "Asleep", not is_opponent)
			await main.show_message(defender.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! SLEEP FAILED!")
		if main._should_bail(): return
	print("TRAINER: Sleep!")

######################################################################################################################################################
######################################################## GYM1 (GYM HEROES) TRAINER EFFECTS ##########################################################
######################################################################################################################################################

# Looks at the other side's hand (read-only reveal) and waits for the player to dismiss it.
# Used by gym1-110 Erika's Perfume, gym1-118 Secret Mission. CPU just snapshots the data internally.
func gym1_reveal_hand(reveal_to_opponent: bool, header_text: String, hint_text: String) -> void:
	# reveal_to_opponent: true means the CPU is looking at the player's hand (no UI needed; this is a no-op for CPU)
	# false means the player is looking at the CPU's hand (show face-up via lass-style display).
	if reveal_to_opponent:
		return
	var opp_hand = main.opponent_hand
	if opp_hand.size() == 0:
		return
	# ISSUE #75 FIX: same blocker problem as Lass — this reveal can run while the full-screen
	# opponent_blocker is up (CPU turn / after the player commits to an attack), which eats the
	# clicks on the revealed hand and the DONE button.
	var restore_blocker_reveal = main.suspend_opponent_blocker("gym1_reveal_hand")
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(opp_hand)
	var display_container = main.large_selection_container if opp_hand.size() > 7 else main.small_selection_container
	var display_size = main.card_scales[5] if opp_hand.size() > 7 else main.card_scales[opp_hand.size()]
	main.display_hand_cards_array(opp_hand, display_container, display_size, false)
	main.header_label.text = header_text
	main.hint_label.text = hint_text
	main.action_button.visible = false
	main.cancel_button.visible = true
	main.cancel_button.text = "DONE"
	main.cancel_button.theme = main.theme_green
	main.cancel_button.offset_left = -219.0
	main.cancel_button.offset_right = 219.0
	await main.trainer_target_selected
	main.trainer_pokemon_selection_active = false
	main.action_button.visible = true
	main.cancel_button.text = "Cancel"
	main.cancel_button.theme = main.theme_red
	main.hide_selection_mode_display_main()
	main.restore_opponent_blocker(restore_blocker_reveal, "gym1_reveal_hand")

# Called by Main_Match_Core_Gameplay_Script.display_and_apply_attack_damage when the attacker has Charity attached.
# Returns the reduced damage. CPU never reduces. Player gets a YES/NO prompt to spare the defender at 10 HP.
func gym1_charity_choose_reduction(attacker: card_object, defender: card_object, damage: int, is_opponent: bool) -> int:
	if is_opponent:
		return damage  # CPU never reduces its own damage
	if damage <= 0:
		return damage
	if defender == null:
		return damage
	# Only meaningful when the attack would KO the defender.
	if damage < defender.current_hp:
		return damage
	# Compute the reduction needed to leave the defender at 10 HP (the standard Charity use case).
	var target_hp = 10
	var reduction = damage - (defender.current_hp - target_hp)
	# Round reduction UP to the nearest 10 per card text
	reduction = int(ceil(reduction / 10.0)) * 10
	if reduction <= 0 or reduction > damage:
		return damage
	# Yes/No prompt anchored on the attacker card so the player has a visible target
	var pick = await gym1_prompt_yes_no(
		attacker,
		"CHARITY",
		"Reduce damage by %d to leave %s at %d HP?" % [reduction, defender.metadata.get("name", ""), defender.current_hp - (damage - reduction)],
		"REDUCE",
		"FULL DAMAGE"
	)
	if pick:
		return damage - reduction
	return damage

# Generic two-option (yes/no) prompt that re-uses the existing trainer_pokemon_selection UI.
# Returns true if the player confirmed (action_button), false if cancelled (cancel_button).
func gym1_prompt_yes_no(anchor_card: card_object, header_text: String, hint_text: String, yes_text: String, no_text: String) -> bool:
	main.trainer_pokemon_selection_active = true
	# Lets Space/Enter answer YES and Escape answer NO while this is on screen.
	# Cleared the moment the await below resumes, which covers both answers (the
	# cancel path emits the same signal) — the flag must not outlive the question
	# or it would keep those keys bound for the rest of the match.
	main.yes_no_prompt_active = true
	main.show_enlarged_array_selection_mode([anchor_card])
	main.header_label.text = header_text
	main.hint_label.text = hint_text
	main.action_button.text = yes_text
	main.action_button.disabled = false
	main.action_button.theme = main.theme_green
	main.cancel_button.visible = true
	main.cancel_button.text = no_text
	main.cancel_button.theme = main.theme_red
	main.selected_card_for_action = anchor_card  # pre-arm action_button so YES is clickable without selecting
	await main.trainer_target_selected
	main.yes_no_prompt_active = false
	var pressed_yes = (main.selected_card_for_action == anchor_card)
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	main.cancel_button.text = "Cancel"
	main.cancel_button.theme = main.theme_red
	return pressed_yes

# Called from inbetween_turn_checks at end of the side's own turn. Handles Charity return-to-hand, Sabrina's ESP discard,
# Recall expiry, Misty boost expiry, and Tickling Machine restoration for the side whose turn just ended.
func gym1_end_of_turn_cleanup(side_is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if side_is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if side_is_opponent else main.player_bench
	var hand = main.opponent_hand if side_is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if side_is_opponent else main.player_discard_pile

	# Clear Misty boost for this side (one-shot — clears whether used or not)
	if side_is_opponent:
		main.opponent_misty_boost_active = false
	else:
		main.player_misty_boost_active = false

	# ECARD1 Burning Energy: clears at end of the turn it was activated on
	if side_is_opponent:
		main.opponent_ecard1_burning_energy_active = false
	else:
		main.player_ecard1_burning_energy_active = false

	# ECARD2 Addictive Pollen: locked side's Supporter-lock clears at the end of that side's own
	# turn (i.e. after they've had exactly one turn unable to play a Supporter)
	if side_is_opponent:
		opponent_supporter_locked = false
	else:
		player_supporter_locked = false

	# EX8 Disconnect (Manectric ex): non-Supporter Trainer lock clears at the end of the locked side's turn
	if side_is_opponent:
		opponent_trainer_except_supporter_locked = false
	else:
		player_trainer_except_supporter_locked = false

	# GYM2: clear per-turn match flags for the side whose turn just ended
	if side_is_opponent:
		main.opponent_blaine_double_attach_used = false
		main.opponent_koga_poison_active = false
	else:
		main.player_blaine_double_attach_used = false
		main.player_koga_poison_active = false

	# Process all pokemon owned by this side
	var all_pokemon: Array = []
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)

	for pokemon in all_pokemon:
		# Recall expires at end of own turn
		if pokemon.gym1_recall_active:
			pokemon.gym1_recall_active = false
		# GYM2 Giovanni evolve-anywhere expires at end of own turn
		if pokemon.gym2_giovanni_evolve_anywhere:
			pokemon.gym2_giovanni_evolve_anywhere = false

		# Charity: returns to hand at end of own turn UNLESS pokemon got KO'd (KO handling clears via send_card_to_discard)
		if pokemon.gym1_charity_attached and pokemon.current_hp > 0:
			var charity_card: card_object = null
			for ac in pokemon.attached_cards:
				if ac.uid.to_lower() == "gym1-99":
					charity_card = ac
					break
			if charity_card != null:
				pokemon.attached_cards.erase(charity_card)
				charity_card.current_location = "hand"
				hand.append(charity_card)
				pokemon.gym1_charity_attached = false
				var attached_node = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
				var hand_node = main.opponent_hand_container if side_is_opponent else main.player_hand_container
				var tex = main.get_card_texture(charity_card)
				main.animate_card_a_to_b(attached_node, hand_node, 0.25, tex, main.card_scales[10])
				display_attached_trainer_cards(side_is_opponent)
				main.refresh_hand_display(side_is_opponent)
				print("CHARITY: returned to hand from ", pokemon.metadata.get("name", ""))

		# Sabrina's ESP: discarded at end of own turn
		if pokemon.gym1_sabrina_esp_attached:
			var esp_card: card_object = null
			for ac in pokemon.attached_cards:
				if ac.uid.to_lower() == "gym1-117":
					esp_card = ac
					break
			if esp_card != null:
				pokemon.attached_cards.erase(esp_card)
				esp_card.current_location = "discard"
				discard.append(esp_card)
				pokemon.gym1_sabrina_esp_attached = false
				pokemon.gym1_sabrina_esp_credit_active = false
				var attached_node = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
				var discard_node = main.opponent_discard_icon if side_is_opponent else main.player_discard_icon
				var tex = main.get_card_texture(esp_card)
				main.animate_card_a_to_b(attached_node, discard_node, 0.25, tex, main.card_scales[10])
				display_attached_trainer_cards(side_is_opponent)
				main.update_discard_pile_display(side_is_opponent)
				print("SABRINA'S ESP: discarded from ", pokemon.metadata.get("name", ""))

		# ECARD1 Strength Charm: discarded at end of the turn its +10 bonus was applied
		if pokemon.has_effect("ecard1_strength_charm_triggered"):
			var charm_card: card_object = null
			for ac in pokemon.attached_cards:
				if ac.uid.to_lower() in ["ecard1-150", "ex4-74", "ex8-92", "ex15-81"]:
					charm_card = ac
					break
			if charm_card != null:
				pokemon.attached_cards.erase(charm_card)
				charm_card.current_location = "discard"
				discard.append(charm_card)
				var attached_node2 = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
				var discard_node2 = main.opponent_discard_icon if side_is_opponent else main.player_discard_icon
				var tex2 = main.get_card_texture(charm_card)
				main.animate_card_a_to_b(attached_node2, discard_node2, 0.25, tex2, main.card_scales[10])
				display_attached_trainer_cards(side_is_opponent)
				main.update_discard_pile_display(side_is_opponent)
				print("STRENGTH CHARM: discarded from ", pokemon.metadata.get("name", ""))

		# Any Technical Machine card (ecard1-144, ecard2's 8 Cubes, etc.): discarded at end of
		# every turn, regardless of use.
		#
		# ISSUE #159: ALL OF THEM, NOT JUST THE FIRST. This used to find one TM with
		# a `break` and discard that — so with two or three attached the rest stayed
		# on the Pokemon and kept granting their attacks turn after turn. Nothing
		# limits a Pokemon to one TM (they have no tool slot; see the attach code,
		# which deliberately has no "already has a TM" filter), so the list has to be
		# collected first and then discarded.
		#
		# Collected into its own array BEFORE erasing: mutating attached_cards while
		# iterating it skips entries.
		var tm_cards: Array = []
		for ac in pokemon.attached_cards:
			if "Technical Machine" in ac.metadata.get("subtypes", []):
				tm_cards.append(ac)
		# ISSUE #271: OFF THE POKEMON FIRST, THEN THE FLIGHT.
		#
		# A Technical Machine's whole point is that it adds an attack, and that
		# attack is a row on the action panel. The panel is only rebuilt by
		# display_pokemon(), which nothing here calls, so the row sat there through
		# the discard animation and until the next board change - describing an
		# attack the Pokemon no longer had.
		#
		# The erase loop is split from the animate loop so that every TM is out of
		# attached_cards BEFORE _refresh_action_panels() reads it. Doing both in one
		# pass would rebuild the panel from a half-emptied list, the same trap #172
		# fixed for the peek-stack.
		for tm_card in tm_cards:
			pokemon.attached_cards.erase(tm_card)
			tm_card.current_location = "discard"
			discard.append(tm_card)
		if not tm_cards.is_empty():
			main._refresh_action_panels()
		for tm_card in tm_cards:
			var attached_node3 = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
			var discard_node3 = main.opponent_discard_icon if side_is_opponent else main.player_discard_icon
			var tex3 = main.get_card_texture(tm_card)
			main.animate_card_a_to_b(attached_node3, discard_node3, 0.25, tex3, main.card_scales[10])
		if not tm_cards.is_empty():
			# ISSUE #172: the board is refreshed ONCE, after every card has actually
			# left attached_cards. Refreshing inside the loop redrew the peek-stack
			# from a half-emptied list, which is how a discard could leave the wrong
			# number of cards showing and then "discard two" on the following turn.
			display_attached_trainer_cards(side_is_opponent)
			main.update_discard_pile_display(side_is_opponent)

		# ECARD2 Memory Berry (ecard2-128): discarded at the end of any turn its holder attacked
		var attacked_this_turn = main.opponent_attacked_this_turn if side_is_opponent else main.player_attacked_this_turn
		if attacked_this_turn:
			var mb_card: card_object = null
			for ac in pokemon.attached_cards:
				if ac.uid.to_lower() in ["ecard2-128", "ex14-80"]:
					mb_card = ac
					break
			if mb_card != null:
				pokemon.attached_cards.erase(mb_card)
				mb_card.current_location = "discard"
				discard.append(mb_card)
				var attached_node5 = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
				var discard_node5 = main.opponent_discard_icon if side_is_opponent else main.player_discard_icon
				var tex5 = main.get_card_texture(mb_card)
				# ISSUE #271: Memory Berry is the OTHER end-of-turn discard that
				# changes what the Pokemon can attack with (it grants the
				# pre-evolution's attacks), so its rows go at the same instant the
				# TMs' do rather than lingering until the next board refresh.
				main._refresh_action_panels()
				main.animate_card_a_to_b(attached_node5, discard_node5, 0.25, tex5, main.card_scales[10])
				display_attached_trainer_cards(side_is_opponent)
				main.update_discard_pile_display(side_is_opponent)
				print("MEMORY BERRY: discarded from ", pokemon.metadata.get("name", ""))

		# ECARD3 Crystal Shard (ecard3-122) / ex8-85: discarded at the end of any turn its holder attacked
		if attacked_this_turn:
			var cs_card: card_object = null
			for ac in pokemon.attached_cards:
				if ac.uid.to_lower() in ["ecard3-122", "ex8-85", "ex14-76"]:
					cs_card = ac
					break
			if cs_card != null:
				pokemon.attached_cards.erase(cs_card)
				cs_card.current_location = "discard"
				discard.append(cs_card)
				var attached_node6 = main.opponent_attached_cards_container if side_is_opponent else main.player_attached_cards_container
				var discard_node6 = main.opponent_discard_icon if side_is_opponent else main.player_discard_icon
				var tex6 = main.get_card_texture(cs_card)
				main.animate_card_a_to_b(attached_node6, discard_node6, 0.25, tex6, main.card_scales[10])
				display_attached_trainer_cards(side_is_opponent)
				main.update_discard_pile_display(side_is_opponent)
				print("CRYSTAL SHARD: discarded from ", pokemon.metadata.get("name", ""))

		# EX4 Aqua Energy / Magma Energy: "At the end of your turn, discard" — one-turn burst Energy,
		# removed at the end of the owner's turn.
		var ex4_temp_energy: Array = []
		for e in pokemon.attached_energies:
			if e.metadata.get("name","") in ["Aqua Energy", "Magma Energy"]:
				ex4_temp_energy.append(e)
		if not ex4_temp_energy.is_empty():
			for e in ex4_temp_energy:
				pokemon.attached_energies.erase(e)
				e.current_location = "discard"
				discard.append(e)
			main.display_active_pokemon_energies(side_is_opponent)
			main.update_discard_pile_display(side_is_opponent)
			await main.show_message(str(ex4_temp_energy.size()) + " TEAM ENERGY WAS DISCARDED AT END OF TURN!")
			if main._should_bail(): return

		# EX4 delayed status (Aqua Trance / Slow-Acting Poison): resolves the first time the
		# afflicted Pokemon's OWN side ends a turn — i.e. "the end of your opponent's next turn"
		# from the attacker's perspective. Tagged until_leaves_play so the generic end-of-turn
		# clears never fire it early; handled explicitly here.
		if pokemon.has_effect("ex4_delayed_status"):
			var ds = pokemon.get_effect_data("ex4_delayed_status")
			pokemon.clear_effect("ex4_delayed_status")
			if typeof(ds) == TYPE_DICTIONARY and pokemon.current_hp > 0:
				var st = ds.get("status", "")
				if st != "":
					main.card_ops.apply_status(pokemon, st, side_is_opponent)
					print("EX4 DELAYED STATUS applied: ", st, " to ", pokemon.metadata.get("name",""))

		# EX7 Dark Seed (Dark Raticate ex7-17): put 5 damage counters at the end of the afflicted
		# Pokemon's OWN side turn — i.e. "the end of your opponent's next turn" from the attacker's view.
		if pokemon.has_effect("ex7_dark_seed"):
			pokemon.clear_effect("ex7_dark_seed")
			if pokemon.current_hp > 0:
				pokemon.current_hp = max(0, pokemon.current_hp - 50)
				main.display_hp_circles_above_align(pokemon, side_is_opponent)
				await main.show_message("DARK SEED! 5 DAMAGE COUNTERS ON " + pokemon.metadata.get("name","").to_upper() + "!")
				if main._should_bail(): return
				await main.check_all_knockouts()
				if main._should_bail(): return

		# ex10 Spiky Shell (Forretress ex10-6): put N damage counters at the end of the afflicted
		# Pokemon's OWN side turn — i.e. "the end of your opponent's next turn" from the attacker's view.
		if pokemon.has_effect("ex10_spiky_shell"):
			var ss = pokemon.get_effect_data("ex10_spiky_shell")
			pokemon.clear_effect("ex10_spiky_shell")
			if pokemon.current_hp > 0:
				var n = (ss.get("counters", 3) if typeof(ss) == TYPE_DICTIONARY else 3)
				pokemon.current_hp = max(0, pokemon.current_hp - n * 10)
				main.display_hp_circles_above_align(pokemon, side_is_opponent)
				await main.show_message("SPIKY SHELL! " + str(n) + " DAMAGE COUNTERS ON " + pokemon.metadata.get("name","").to_upper() + "!")
				if main._should_bail(): return
				await main.check_all_knockouts()
				if main._should_bail(): return

		# EX5 Extra Comet Punch (Metagross ex ex5-95): the +50 boost only holds while the attack is
		# used on consecutive own turns. The arm carries a "used_this_turn" marker set when the
		# attack fires. At the end of the owner's turn, if it was NOT used this turn the arm expires;
		# if it was, reset the marker so it survives into (only) the next turn.
		if pokemon.has_effect("ex5_extra_comet"):
			var ecd = pokemon.get_effect_data("ex5_extra_comet")
			if typeof(ecd) == TYPE_DICTIONARY and ecd.get("used_this_turn", false):
				pokemon.set_effect("ex5_extra_comet", "until_leaves_play", {"used_this_turn": false})
			else:
				pokemon.clear_effect("ex5_extra_comet")

		# Generic expiring-effects: clear everything tagged end_of_own_turn for this side.
		# Must run LAST in this loop body — effects like Strength Charm's trigger flag are
		# read above (to decide whether to discard the tool) before being cleared here.
		pokemon.clear_effects_with_duration("end_of_own_turn")

	# EX14 Mysterious Shard (ex14-81 Pokémon Tool): "Discard this card at the end of your opponent's next
	# turn." Armed at the end of the turn it was played (its holder's own turn) and discarded at the
	# following turn-end (the opponent's turn) — so we scan BOTH sides every turn-end.
	for ms_is_opp in [false, true]:
		var ms_active = main.opponent_active_pokemon if ms_is_opp else main.player_active_pokemon
		var ms_field: Array = []
		if ms_active != null: ms_field.append(ms_active)
		ms_field.append_array(main.opponent_bench if ms_is_opp else main.player_bench)
		var ms_discard = main.opponent_discard_pile if ms_is_opp else main.player_discard_pile
		for p in ms_field:
			var shard: card_object = null
			for ac in p.attached_cards:
				if ac.uid.to_lower() == "ex14-81":
					shard = ac
					break
			if shard == null:
				continue
			if shard.has_effect("ex14_shard_armed"):
				p.attached_cards.erase(shard)
				shard.clear_effect("ex14_shard_armed")
				shard.current_location = "discard"
				ms_discard.append(shard)
				var ms_attached_node = main.opponent_attached_cards_container if ms_is_opp else main.player_attached_cards_container
				var ms_discard_node = main.opponent_discard_icon if ms_is_opp else main.player_discard_icon
				var ms_tex = main.get_card_texture(shard)
				main.animate_card_a_to_b(ms_attached_node, ms_discard_node, 0.25, ms_tex, main.card_scales[10])
				display_attached_trainer_cards(ms_is_opp)
				main.update_discard_pile_display(ms_is_opp)
				print("MYSTERIOUS SHARD: discarded from ", p.metadata.get("name", ""))
			else:
				shard.set_effect("ex14_shard_armed", "until_leaves_play")

	# Generic expiring-effects: effects on the OTHER side tagged to expire when THIS side's turn ends
	var other_active = main.player_active_pokemon if side_is_opponent else main.opponent_active_pokemon
	var other_bench = main.player_bench if side_is_opponent else main.opponent_bench
	var other_is_opponent = not side_is_opponent
	var other_pokemon: Array = []
	if other_active != null:
		other_pokemon.append(other_active)
	other_pokemon.append_array(other_bench)
	for op in other_pokemon:
		# ECARD2 Weakness Guard: discard the physical Tool card + clear "no Weakness" when its
		# end_of_opponent_turn tag expires (read the flag BEFORE the generic clear below erases it)
		if op.has_effect("ecard2_weakness_guard"):
			var wg_card: card_object = null
			for ac in op.attached_cards:
				if ac.uid.to_lower() == "ecard2-141":
					wg_card = ac
					break
			if wg_card != null:
				var other_discard = main.opponent_discard_pile if other_is_opponent else main.player_discard_pile
				op.attached_cards.erase(wg_card)
				wg_card.current_location = "discard"
				other_discard.append(wg_card)
				op.temporary_weakness = ""
				var attached_node4 = main.opponent_attached_cards_container if other_is_opponent else main.player_attached_cards_container
				var discard_node4 = main.opponent_discard_icon if other_is_opponent else main.player_discard_icon
				var tex4 = main.get_card_texture(wg_card)
				main.animate_card_a_to_b(attached_node4, discard_node4, 0.25, tex4, main.card_scales[10])
				display_attached_trainer_cards(other_is_opponent)
				main.update_discard_pile_display(other_is_opponent)
				print("WEAKNESS GUARD: discarded from ", op.metadata.get("name", ""))
		op.clear_effects_with_duration("end_of_opponent_turn")

# Restores cards held aside by Tickling Machine when the tickled side's own next turn ends.
func gym1_restore_tickled_hand(target_is_opponent: bool) -> void:
	var aside = main.opponent_tickled_set_aside if target_is_opponent else main.player_tickled_set_aside
	var hand = main.opponent_hand if target_is_opponent else main.player_hand
	if aside.size() == 0:
		if target_is_opponent:
			main.opponent_hand_tickled = false
		else:
			main.player_hand_tickled = false
		return
	for card in aside:
		card.current_location = "hand"
		hand.append(card)
	aside.clear()
	if target_is_opponent:
		main.opponent_hand_tickled = false
	else:
		main.player_hand_tickled = false
	main.refresh_hand_display(target_is_opponent)
	print("TICKLING MACHINE: restored ", "opponent" if target_is_opponent else "player", "'s set-aside cards")

# ============================ Heal helper ============================
func gym1_heal_pokemon(pokemon: card_object, amount: int, is_opp: bool) -> void:
	# MATCH EFFECTS: no_healing / healing_multiplier gate
	amount = main.match_effects.modify_heal_amount(amount, is_opp)
	if amount <= 0:
		return
	var max_hp = int(pokemon.metadata.get("hp", "0"))
	if pokemon.max_hp_override > 0:
		max_hp = pokemon.max_hp_override
	var new_hp = min(max_hp, pokemon.current_hp + amount)
	if new_hp > pokemon.current_hp:
		pokemon.current_hp = new_hp
		main.display_hp_circles_above_align(pokemon, is_opp)

# ============================ gym1-15 / gym1-98 — Brock ============================
# Heal 1 damage counter (10) from each of your Pokemon that has any damage.
func gym1_effect_brock(is_opponent: bool) -> void:
	var healed_any = false
	for p in build_field_pokemon_array(is_opponent):
		var max_hp = int(p.metadata.get("hp", "0"))
		if p.current_hp < max_hp:
			gym1_heal_pokemon(p, 10, is_opponent)
			healed_any = true
	if healed_any:
		await main.show_message("BROCK: REMOVED 1 DAMAGE COUNTER FROM EACH DAMAGED POKEMON!")
	else:
		await main.show_message("BROCK: NOTHING TO HEAL!")
	if main._should_bail(): return

# ============================ gym1-16 / gym1-100 — Erika ============================
# You may draw up to 3, then your opponent may draw up to 3. We collapse "up to" to a simple yes/no per side
# (drawing more is almost always optimal — only skipped when the hand is already very large).
func gym1_effect_erika(is_opponent: bool) -> void:
	var draw_count_self = await gym1_choose_draw_count(3, is_opponent, "ERIKA — DRAW 3 CARDS?")
	await main.card_ops.draw_n(is_opponent, draw_count_self)
	if main._should_bail(): return
	var other_is_opp = not is_opponent
	var draw_count_other = await gym1_choose_draw_count(3, other_is_opp, "ERIKA — OPPONENT MAY DRAW 3")
	await main.card_ops.draw_n(other_is_opp, draw_count_other)
	if main._should_bail(): return

# CPU draws max unless its hand is full; player gets a YES/NO prompt (draw max or skip).
func gym1_choose_draw_count(max_n: int, side_is_opp: bool, header_text: String) -> int:
	if side_is_opp:
		var hand = main.opponent_hand
		if hand.size() >= 7:
			return 0
		return min(max_n, 7 - hand.size())
	# Use the played Erika card (already in discard at this point) — instead anchor on player's active
	var anchor: card_object = main.player_active_pokemon
	if anchor == null:
		# Fallback: just draw the max if there's no card to anchor on
		return max_n
	var hint = "Draw %d cards? (NO to skip)" % max_n
	var yes = await gym1_prompt_yes_no(anchor, header_text, hint, "DRAW %d" % max_n, "SKIP")
	return max_n if yes else 0

# ============================ gym1-17 / gym1-101 — Lt. Surge ============================
# Put a Basic from hand as your new Active; the old Active goes to the bench.
func gym1_effect_lt_surge(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active == null or bench.size() >= main.get_max_bench_size():
		return

	var basics_in_hand: Array = []
	for c in hand:
		if main.is_basic_pokemon(c):
			basics_in_hand.append(c)
	if basics_in_hand.size() == 0:
		return

	var chosen: card_object = null
	if is_opponent:
		# CPU: pick the strongest basic (highest HP) — naive heuristic
		var best = -1
		for c in basics_in_hand:
			var hp = int(c.metadata.get("hp", "0"))
			if hp > best:
				best = hp
				chosen = c
	else:
		chosen = await main.card_ops.prompt_select_card(basics_in_hand, "LT. SURGE — PROMOTE A BASIC", "Choose a Basic to swap into Active", "PROMOTE", false)
		if main._should_bail(): return

	if chosen == null:
		return

	# Move the chosen basic from hand → active, push old active to bench
	hand.erase(chosen)
	chosen.current_hp = chosen.get_max_hp()
	chosen.current_location = "active"
	chosen.placed_on_field_this_turn = true
	# Clear statuses on the demoted active
	main.clear_all_statuses(active, is_opponent)
	active.current_location = "bench"
	bench.append(active)
	if is_opponent:
		main.opponent_active_pokemon = chosen
	else:
		main.player_active_pokemon = chosen

	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("LT. SURGE: " + chosen.metadata.get("name", "").to_upper() + " IS NOW ACTIVE!")
	if main._should_bail(): return

# ============================ gym1-18 / gym1-102 — Misty ============================
# Discard 2 other cards; this turn, if a Misty-named attacker damages the defender, +20 damage.
func gym1_effect_misty(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.refresh_hand_display(true)
		main.update_discard_pile_display(true)
	else:
		await player_select_cards_to_discard(hand, 2, "MISTY", "Discard 2 cards")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)

	if is_opponent:
		main.opponent_misty_boost_active = true
	else:
		main.player_misty_boost_active = true
	await main.show_message("MISTY: NEXT MISTY ATTACK +20 DAMAGE!")
	if main._should_bail(): return

# ============================ gym1-19 — The Rocket's Trap ============================
# Flip a coin. If heads, pick up to 3 cards at random from opp's hand (don't look) and shuffle into their deck.
func gym1_effect_rockets_trap(is_opponent: bool) -> void:
	await main.show_message("THE ROCKET'S TRAP! FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NOTHING HAPPENS!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_hand.size() == 0:
		return
	var picks: Array = []
	var pool = opp_hand.duplicate()
	pool.shuffle()
	var n = min(3, pool.size())
	for i in range(n):
		picks.append(pool[i])
	for c in picks:
		opp_hand.erase(c)
		c.current_location = "deck"
		opp_deck.append(c)
	opp_deck.shuffle()
	main.refresh_hand_display(not is_opponent)
	main.update_deck_icon(not is_opponent)
	await main.show_message("HEADS! SHUFFLED " + str(n) + " CARD(S) FROM OPPONENT'S HAND INTO DECK!")
	if main._should_bail(): return

# ============================ gym1-97 — Blaine's Quiz #1 ============================
# Adapted: coin flip (we can't run a real interactive guess). Heads = opponent guessed right (opp draws 2). Tails = opp wrong (you draw 2).
func gym1_effect_blaines_quiz(is_opponent: bool) -> void:
	await main.show_message("BLAINE'S QUIZ! FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		# Opponent guessed right
		var other = not is_opponent
		await main.card_ops.draw_n(other, 2)
		if main._should_bail(): return
		await main.show_message("HEADS! OPPONENT GUESSED RIGHT AND DREW 2 CARDS!")
	else:
		await main.card_ops.draw_n(is_opponent, 2)
		if main._should_bail(): return
		await main.show_message("TAILS! OPPONENT GUESSED WRONG — YOU DREW 2 CARDS!")
	if main._should_bail(): return

# ============================ gym1-105 — Blaine's Last Resort ============================
# Show hand to opp (it's empty here, since validation requires no other cards) then draw 5.
func gym1_effect_blaines_last_resort(is_opponent: bool) -> void:
	# Hand is already empty (validation guaranteed no other cards). Just draw 5.
	await main.card_ops.draw_n(is_opponent, 5)
	if main._should_bail(): return
	await main.show_message("BLAINE'S LAST RESORT — DREW 5 CARDS!")
	if main._should_bail(): return

# ============================ gym1-106 — Brock's Training Method ============================
# Search deck for any Pokemon with "Brock" in its name; add to hand.
func gym1_effect_brocks_training_method(is_opponent: bool) -> void:
	await gym1_search_deck_by_name_substring(is_opponent, "Brock", "BROCK'S TRAINING METHOD", 1)

# ============================ gym1-109 — Erika's Maids ============================
# Discard 2 other cards; search deck for up to 2 Pokemon with "Erika" in name.
func gym1_effect_erikas_maids(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.refresh_hand_display(true)
		main.update_discard_pile_display(true)
	else:
		await player_select_cards_to_discard(hand, 2, "ERIKA'S MAIDS", "Discard 2 cards")
		if main._should_bail(): return
		for card in main.trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)

	await gym1_search_deck_by_name_substring(is_opponent, "Erika", "ERIKA'S MAIDS", 2)

# Generic helper: pick up to max_n Pokemon from deck whose names contain substr; add to hand.
func gym1_search_deck_by_name_substring(is_opponent: bool, substr: String, header_text: String, max_n: int) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand

	var candidates: Array = []
	for c in deck:
		if c.metadata.get("supertype", "") == "Pokémon" and substr in c.metadata.get("name", ""):
			candidates.append(c)

	if candidates.size() == 0:
		await main.show_message("NO MATCHING POKEMON IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return

	var picks: Array = []
	if is_opponent:
		# CPU: prefer evolutions whose pre-stage is in play; otherwise basics for setup
		candidates.sort_custom(func(a, b):
			var a_useful = main.get_valid_evolution_targets(a, true).size() > 0 if not main.is_basic_pokemon(a) else 0
			var b_useful = main.get_valid_evolution_targets(b, true).size() > 0 if not main.is_basic_pokemon(b) else 0
			return int(a_useful) > int(b_useful))
		for i in range(min(max_n, candidates.size())):
			picks.append(candidates[i])
	else:
		for i in range(min(max_n, candidates.size())):
			var remaining: Array = []
			for c in candidates:
				if c not in picks:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var pick = await main.card_ops.prompt_select_card(remaining, header_text + " — CHOOSE " + str(i + 1) + "/" + str(min(max_n, candidates.size())), "Pick a Pokemon to add to your hand (cancel to stop)", "TAKE", true, true)
			if main._should_bail(): return
			if pick == null:
				break
			picks.append(pick)

	for c in picks:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ADDED " + str(picks.size()) + " POKEMON TO HAND!")
	if main._should_bail(): return

# ============================ gym1-110 — Erika's Perfume ============================
# Look at opp's hand; you may put any number of opp's Basics from their hand onto their bench.
func gym1_effect_erikas_perfume(is_opponent: bool) -> void:
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_is_player = is_opponent  # the SIDE being looked at
	var basics_in_opp_hand: Array = []
	for c in opp_hand:
		if main.is_basic_pokemon(c):
			basics_in_opp_hand.append(c)

	if is_opponent:
		# CPU plays the card: chooses nothing (no tactical benefit to gifting bench setup). Just reveals + ends.
		await main.show_message("OPPONENT LOOKED AT YOUR HAND — NOTHING WAS BENCHED")
		if main._should_bail(): return
		return

	# Player plays the card: shows opp hand face-up, then picks basics to bench
	await gym1_reveal_hand(false, "ERIKA'S PERFUME — OPPONENT'S HAND", "Review, then choose Basics to bench")

	if basics_in_opp_hand.size() == 0:
		await main.show_message("NO BASIC POKEMON IN OPPONENT'S HAND!")
		if main._should_bail(): return
		return
	if opp_bench.size() >= main.get_max_bench_size():
		await main.show_message("OPPONENT'S BENCH IS FULL!")
		if main._should_bail(): return
		return

	var to_bench: Array = []
	while to_bench.size() < basics_in_opp_hand.size() and opp_bench.size() + to_bench.size() < 5:
		var remaining: Array = []
		for c in basics_in_opp_hand:
			if c not in to_bench:
				remaining.append(c)
		if remaining.size() == 0:
			break
		var pick = await main.card_ops.prompt_select_card(remaining, "ERIKA'S PERFUME — BENCH WHICH BASIC?", "Pick a Basic to put on opponent's bench (or DONE)", "BENCH", true)
		if main._should_bail(): return
		if pick == null:
			break
		to_bench.append(pick)

	# Move the picks from opp's hand to opp's bench
	for c in to_bench:
		opp_hand.erase(c)
		c.current_hp = c.get_max_hp()
		c.current_location = "bench"
		c.placed_on_field_this_turn = true
		opp_bench.append(c)

	main.refresh_hand_display(opp_is_player)
	main.display_pokemon(opp_is_player)
	await main.show_message("ERIKA'S PERFUME — " + str(to_bench.size()) + " BASIC(S) BENCHED!")
	if main._should_bail(): return

	# GYM2-119 Rocket's Minefield Gym — coin flip per pokemon benched from hand
	for c in to_bench:
		await gym2_minefield_gym_trigger(c, opp_is_player)
		if main._should_bail(): return

# ============================ gym1-111 — Good Manners ============================
# Show your hand to opp, then search deck for a Basic Pokemon and add to hand.
func gym1_effect_good_manners(is_opponent: bool) -> void:
	# Hand reveal is a flavor effect; we skip the UI for CPU and just message the player.
	if is_opponent:
		await main.show_message("OPPONENT SHOWED THEIR HAND!")
	else:
		await main.show_message("YOUR HAND IS SHOWN!")
	if main._should_bail(): return

	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics: Array = []
	for c in deck:
		if main.is_basic_pokemon(c):
			basics.append(c)
	if basics.size() == 0:
		await main.show_message("NO BASICS IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return

	var chosen: card_object = null
	if is_opponent:
		chosen = main.cpu_ai.cpu_search_deck_for_best_pokemon(basics)
		if chosen == null:
			chosen = basics[0]
	else:
		chosen = await main.card_ops.prompt_select_card(basics, "GOOD MANNERS — CHOOSE A BASIC", "Add a Basic Pokemon to your hand", "TAKE", false, true)
		if main._should_bail(): return

	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if chosen != null:
		await main.show_message("ADDED " + chosen.metadata.get("name", "").to_upper() + " TO HAND!")
	if main._should_bail(): return

# ============================ gym1-112 — Lt. Surge's Treaty ============================
# The OPPONENT (other side) chooses: both players take a prize, OR the card player draws 1.
# Cross-player choice is auto-resolved (see effect_challenge precedent).
func gym1_effect_lt_surges_treaty(is_opponent: bool) -> void:
	# The chooser is the OTHER side
	var chooser_is_opp = not is_opponent
	var chooser_prizes_left = (main.opponent_prize_cards.size() if chooser_is_opp else main.player_prize_cards.size())
	var card_player_prizes_left = (main.opponent_prize_cards.size() if is_opponent else main.player_prize_cards.size())

	# Choice heuristic: take a prize if chooser is behind or tied on prizes (more aggressive recovery)
	# else hand the card player just 1 draw (denies a free prize advancement).
	var take_prizes = chooser_prizes_left >= card_player_prizes_left

	var chooser_label = "OPPONENT" if chooser_is_opp else "PLAYER"
	if take_prizes:
		await main.show_message("LT. SURGE'S TREATY — " + chooser_label + " CHOOSES: EACH PLAYER TAKES A PRIZE!")
		if main._should_bail(): return
		# Card-player picks own prize (player) / CPU random (opponent)
		if is_opponent:
			# Card player = CPU
			await main.cpu_ai.opponent_take_prize_card()
			# Other side = real player picks
			await gym1_player_take_own_prize()
		else:
			await gym1_player_take_own_prize()
			await main.cpu_ai.opponent_take_prize_card()
	else:
		await main.show_message("LT. SURGE'S TREATY — " + chooser_label + " CHOOSES: CARD PLAYER DRAWS 1!")
		await main.card_ops.draw_n(is_opponent, 1)
		if main._should_bail(): return

# Helper: let the player pick one of their own prize cards to take.
func gym1_player_take_own_prize() -> void:
	if main.player_prize_cards.size() == 0:
		return
	var pick = await main.card_ops.prompt_select_card(main.player_prize_cards, "CHOOSE A PRIZE CARD", "Pick a prize to take into your hand", "TAKE", false)
	if main._should_bail(): return
	if pick != null:
		await main.take_prize_card(pick, false)

# ============================ gym1-113 — Minion of Team Rocket ============================
# Flip 2 coins. Both heads = return one of opp's bench pokemon (and attached cards) to opp's hand. Any tails = your turn ends.
func gym1_effect_minion_of_team_rocket(is_opponent: bool) -> void:
	await main.show_message("MINION OF TEAM ROCKET — FLIPPING 2 COINS!")
	if main._should_bail(): return
	var c1 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var c2 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return

	if not (c1 and c2):
		await main.show_message("TAILS! YOUR TURN ENDS!")
		if main._should_bail(): return
		if is_opponent:
			main.opponent_turn_force_end = true
		else:
			main.player_turn_force_end = true
		return

	# Both heads — return an opp bench pokemon (and all attached) to opp's hand
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	if opp_bench.size() == 0:
		await main.show_message("HEADS-HEADS! BUT OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return

	var target: card_object = null
	if is_opponent:
		# CPU picks: prefer high-HP or evolved targets to maximally disrupt
		var best = -1
		for bp in opp_bench:
			var hp = int(bp.metadata.get("hp", "0"))
			var bonus = bp.attached_pre_evolutions.size() * 50 + bp.attached_energies.size() * 20
			var score = hp + bonus
			if score > best:
				best = score
				target = bp
	else:
		target = await main.card_ops.prompt_select_card(opp_bench, "MINION — RETURN WHICH BENCHED POKEMON?", "All attached cards return to opponent's hand with it", "RETURN", false)
		if main._should_bail(): return

	if target == null:
		return

	# Per rules: pokemon AND all attached cards go to opp's HAND (not deck, not discard)
	var name = target.metadata.get("name", "")
	for e in target.attached_energies:
		e.current_location = "hand"
		opp_hand.append(e)
	target.attached_energies.clear()
	for pre in target.attached_pre_evolutions:
		pre.current_location = "hand"
		opp_hand.append(pre)
	target.attached_pre_evolutions.clear()
	for ac in target.attached_cards:
		ac.current_location = "hand"
		opp_hand.append(ac)
	target.attached_cards.clear()
	main.clear_all_statuses(target, not is_opponent)
	opp_bench.erase(target)
	target.current_location = "hand"
	target.current_hp = target.get_max_hp()
	opp_hand.append(target)

	main.refresh_hand_display(not is_opponent)
	main.display_pokemon(not is_opponent)
	await main.show_message("HEADS-HEADS! " + name.to_upper() + " AND ATTACHED CARDS RETURNED TO HAND!")
	if main._should_bail(): return

# ============================ gym1-114 — Misty's Wrath ============================
# Reveal top 7 of deck. Pick 2 to add to hand. Discard the rest.
func gym1_effect_mistys_wrath(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	var n = min(7, deck.size())
	if n == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return

	var top_n: Array = []
	for i in range(n):
		top_n.append(deck[i])
	# Remove from deck
	for c in top_n:
		deck.erase(c)

	var picks: Array = []
	var pick_count = min(2, top_n.size())
	if is_opponent:
		# CPU: prefer evolutions whose target is in play, then energy, then trainers, then basics
		var scored = top_n.duplicate()
		scored.sort_custom(func(a, b):
			return _gym1_search_card_priority(a) > _gym1_search_card_priority(b))
		for i in range(pick_count):
			picks.append(scored[i])
	else:
		for i in range(pick_count):
			var remaining: Array = []
			for c in top_n:
				if c not in picks:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var pick = await main.card_ops.prompt_select_card(remaining, "MISTY'S WRATH — PICK CARD " + str(i + 1) + "/" + str(pick_count), "Choose a card to add to your hand", "TAKE", false)
			if main._should_bail(): return
			if pick == null:
				break
			picks.append(pick)

	# Resolve: picks → hand, rest → discard
	for c in picks:
		c.current_location = "hand"
		hand.append(c)
	for c in top_n:
		if c in picks:
			continue
		c.current_location = "discard"
		discard.append(c)

	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("MISTY'S WRATH — KEPT " + str(picks.size()) + ", DISCARDED " + str(top_n.size() - picks.size()) + "!")
	if main._should_bail(): return

func _gym1_search_card_priority(card: card_object) -> int:
	var st = card.metadata.get("supertype", "")
	if st == "Pokémon":
		if not main.is_basic_pokemon(card):
			var t = main.get_valid_evolution_targets(card, true)
			if t.size() > 0:
				return 5
			return 2
		return 3
	if st == "Energy":
		return 4
	if st == "Trainer":
		return 4
	return 1

# ============================ gym1-116 — Recall ============================
func gym1_effect_recall(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null:
		return
	active.gym1_recall_active = true
	await main.show_message("RECALL — ACTIVE CAN USE ANY ATTACK FROM ITS EVOLUTION CHAIN THIS TURN!")
	if main._should_bail(): return

# ============================ gym1-118 — Secret Mission ============================
# Look at opp's hand; you may discard any number of cards from your hand; draw that many.
func gym1_effect_secret_mission(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	if not is_opponent:
		await gym1_reveal_hand(false, "SECRET MISSION — OPPONENT'S HAND", "Look at the hand, then choose cards to discard")

	# Choose how many to discard
	if hand.size() == 0:
		await main.show_message("YOUR HAND IS EMPTY!")
		if main._should_bail(): return
		return

	var discards: Array = []
	if is_opponent:
		# CPU: discards low-priority cards aggressively to refresh hand (up to half of hand)
		var n = max(0, hand.size() - 4)  # keep top 4-ish cards, discard the rest if low-priority
		var to_discard = cpu_get_discard_priority(hand, n)
		discards = to_discard
	else:
		# Player chooses any subset to discard
		# We'll re-use a "discard any number" UI: pick one at a time, DONE to finish
		var remaining = hand.duplicate()
		while remaining.size() > 0:
			var pick = await main.card_ops.prompt_select_card(remaining, "SECRET MISSION — DISCARD WHICH? (DONE TO STOP)", "Selected so far: " + str(discards.size()), "DISCARD", true)
			if main._should_bail(): return
			main.cancel_button.text = "Cancel"
			main.cancel_button.theme = main.theme_red
			if pick == null:
				break
			discards.append(pick)
			remaining.erase(pick)

	# Apply discards and draw same number
	for c in discards:
		hand.erase(c)
		c.current_location = "discard"
		discard.append(c)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.card_ops.draw_n(is_opponent, discards.size())
	if main._should_bail(): return
	await main.show_message("SECRET MISSION — DISCARDED " + str(discards.size()) + ", DREW " + str(discards.size()) + "!")
	if main._should_bail(): return

# ============================ gym1-119 — Tickling Machine ============================
# Flip a coin. Heads = opp's hand is set aside face down until end of their next turn. Tails = your turn ends.
func gym1_effect_tickling_machine(is_opponent: bool) -> void:
	await main.show_message("TICKLING MACHINE — FLIPPING!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! YOUR TURN ENDS!")
		if main._should_bail(): return
		if is_opponent:
			main.opponent_turn_force_end = true
		else:
			main.player_turn_force_end = true
		return

	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	if opp_hand.size() == 0:
		await main.show_message("HEADS! BUT OPPONENT HAS NO CARDS IN HAND!")
		if main._should_bail(): return
		return

	# Move opp_hand into set_aside zone
	var target_is_opp = not is_opponent
	var aside = main.opponent_tickled_set_aside if target_is_opp else main.player_tickled_set_aside
	for c in opp_hand.duplicate():
		c.current_location = "set_aside"
		aside.append(c)
	opp_hand.clear()
	if target_is_opp:
		main.opponent_hand_tickled = true
	else:
		main.player_hand_tickled = true
	main.refresh_hand_display(target_is_opp)
	await main.show_message("HEADS! OPPONENT'S HAND IS SET ASIDE UNTIL END OF THEIR NEXT TURN!")
	if main._should_bail(): return

# ============================ gym1-121 — Blaine's Gamble ============================
# Discard any number of cards; flip a coin; heads = draw twice that many.
func gym1_effect_blaines_gamble(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	if hand.size() == 0:
		return

	var discards: Array = []
	if is_opponent:
		# CPU: discard low-priority cards (skip if hand is decent)
		var n = max(1, hand.size() / 2)
		var to_discard = cpu_get_discard_priority(hand, n, played_card)
		discards = to_discard
	else:
		# Player picks any number
		var remaining = hand.duplicate()
		while remaining.size() > 0:
			var pick = await main.card_ops.prompt_select_card(remaining, "BLAINE'S GAMBLE — DISCARD HOW MANY?", "Selected: " + str(discards.size()) + " (DONE to flip)", "DISCARD", true)
			if main._should_bail(): return
			main.cancel_button.text = "Cancel"
			main.cancel_button.theme = main.theme_red
			if pick == null:
				break
			discards.append(pick)
			remaining.erase(pick)

	for c in discards:
		hand.erase(c)
		c.current_location = "discard"
		discard.append(c)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)

	await main.show_message("BLAINE'S GAMBLE — FLIPPING!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var blaine_draw = discards.size() * 2
		await main.card_ops.draw_n(is_opponent, blaine_draw)
		if main._should_bail(): return
		await main.show_message("HEADS! DREW " + str(blaine_draw) + " CARDS!")
	else:
		await main.show_message("TAILS! NOTHING.")
	if main._should_bail(): return

# ============================ gym1-122 — Energy Flow ============================
# For each of your Pokemon, you may return any number of attached Energy cards to your hand.
func gym1_effect_energy_flow(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var pokemon_list = build_field_pokemon_array(is_opponent)

	var any_returned = false
	for pokemon in pokemon_list:
		if pokemon.attached_energies.size() == 0:
			continue

		var to_return: Array = []
		if is_opponent:
			# CPU heuristic: only return energy from a heavily-damaged bench pokemon, or surplus energy on the active
			var max_hp = int(pokemon.metadata.get("hp", "0"))
			var heavily_damaged = pokemon.current_hp <= max_hp / 2
			if heavily_damaged:
				to_return = pokemon.attached_energies.duplicate()
			# else: skip
		else:
			# Player picks any number for this pokemon
			var remaining = pokemon.attached_energies.duplicate()
			while remaining.size() > 0:
				var pick = await main.card_ops.prompt_select_card(remaining, "ENERGY FLOW — " + pokemon.metadata.get("name", "").to_upper(), "Return energies to hand (DONE to move on)", "RETURN", true)
				if main._should_bail(): return
				if pick == null:
					break
				to_return.append(pick)
				remaining.erase(pick)

		if to_return.size() == 0:
			continue
		for e in to_return:
			pokemon.attached_energies.erase(e)
			e.current_location = "hand"
			hand.append(e)
		any_returned = true

	main.refresh_hand_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	if any_returned:
		await main.show_message("ENERGY FLOW — ENERGIES RETURNED TO HAND!")
	else:
		await main.show_message("ENERGY FLOW — NOTHING RETURNED.")
	if main._should_bail(): return

# ============================ gym1-123 — Misty's Duel ============================
# Card says: rock-paper-scissors; if you don't know, flip a coin. Winner shuffles hand and draws 5.
func gym1_effect_mistys_duel(is_opponent: bool) -> void:
	await main.show_message("MISTY'S DUEL — FLIPPING COIN!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	# Heads = card player wins; tails = other side wins
	var winner_is_opp = is_opponent if coin else not is_opponent

	var hand = main.opponent_hand if winner_is_opp else main.player_hand
	var deck = main.opponent_deck if winner_is_opp else main.player_deck
	# Shuffle winner's hand into deck
	for c in hand.duplicate():
		c.current_location = "deck"
		deck.append(c)
	hand.clear()
	deck.shuffle()
	main.refresh_hand_display(winner_is_opp)
	# Draw 5
	await main.card_ops.draw_n(winner_is_opp, 5)
	if main._should_bail(): return
	var who = "OPPONENT" if winner_is_opp else "YOU"
	await main.show_message("MISTY'S DUEL — " + who + " WON AND DREW A NEW HAND OF 5!")
	if main._should_bail(): return

# ============================ gym1-125 — Sabrina's Gaze ============================
# Each player shuffles hand into deck and draws same number of cards.
func gym1_effect_sabrinas_gaze(_is_opponent: bool) -> void:
	for side_is_opp in [false, true]:
		var hand = main.opponent_hand if side_is_opp else main.player_hand
		var deck = main.opponent_deck if side_is_opp else main.player_deck
		var prev_count = hand.size()
		for c in hand.duplicate():
			c.current_location = "deck"
			deck.append(c)
		hand.clear()
		deck.shuffle()
		main.refresh_hand_display(side_is_opp)
		await main.card_ops.draw_n(side_is_opp, prev_count)
		if main._should_bail(): return
	await main.show_message("SABRINA'S GAZE — BOTH PLAYERS REDREW THEIR HANDS!")
	if main._should_bail(): return

# ============================ gym1-126 — Trash Exchange ============================
# Shuffle your discard pile into your deck. Then discard top X cards (X = original discard count).
func gym1_effect_trash_exchange(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var count = discard.size()
	if count == 0:
		return
	# Shuffle discard into deck
	for c in discard.duplicate():
		c.current_location = "deck"
		deck.append(c)
	discard.clear()
	deck.shuffle()
	main.update_discard_pile_display(is_opponent)
	main.update_deck_icon(is_opponent)
	# Discard top X from deck
	var to_discard = min(count, deck.size())
	for i in range(to_discard):
		var c = deck.pop_front()
		c.current_location = "discard"
		discard.append(c)
	main.update_discard_pile_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("TRASH EXCHANGE — SHUFFLED " + str(count) + " INTO DECK, DISCARDED TOP " + str(to_discard) + "!")
	if main._should_bail(): return

######################################################################################################################################################
######################################################## STADIUM CARD INFRASTRUCTURE ################################################################
######################################################################################################################################################

# Main entry point for playing any Stadium card. Discards any existing stadium to its owner's pile,
# installs the new card in the stadium zone, refreshes the display, and runs any on-play effect.
func resolve_stadium_trainer(card: card_object, is_opponent: bool) -> void:
	# Discard the existing stadium to its OWNER's discard pile (not the new player's pile)
	if main.current_stadium_card != null:
		var prev = main.current_stadium_card
		var prev_owner_discard = main.opponent_discard_pile if main.current_stadium_owner_is_opponent else main.player_discard_pile
		var prev_owner_discard_node = main.opponent_discard_icon if main.current_stadium_owner_is_opponent else main.player_discard_icon
		prev.current_location = "discard"
		prev_owner_discard.append(prev)
		var prev_texture = main.get_card_texture(prev)
		await main.animate_card_a_to_b(main.stadium_card_container, prev_owner_discard_node, 0.25, prev_texture, main.card_scales[10])
		if main._should_bail(): return
		await main.show_message(prev.metadata.get("name", "") + " WAS DISCARDED!")
		if main._should_bail(): return
		main.current_stadium_card = null
		main.update_discard_pile_display(main.current_stadium_owner_is_opponent)

	# Install new stadium
	card.current_location = "stadium"
	main.current_stadium_card = card
	main.current_stadium_owner_is_opponent = is_opponent
	display_stadium_card()
	await main.show_message(card.metadata.get("name", "").to_upper() + " IS NOW IN PLAY!")
	if main._should_bail(): return

	# Rocket's Hideout (neo3): +20 max HP for Dark-named pokemon while in play
	main.powers_and_bodies.refresh_rockets_hideout_hp()

	# Run on-play effect (only Narrow Gym and Giant Stump need one)
	var uid = card.uid.to_lower()
	if uid == "gym1-124":
		await gym1_narrow_gym_on_play()
	elif uid == "ex12-75":
		await ex12_giant_stump_on_play(is_opponent)

# Renders the current stadium card image inside the stadium_card_container node
func display_stadium_card() -> void:
	# Clear any existing child card display
	for child in main.stadium_card_container.get_children():
		if child.name == "stadium_card_image":
			# Reuse the existing TextureRect node
			if main.current_stadium_card == null:
				child.visible = false
				child.texture = null
			else:
				var tex = main.get_card_texture(main.current_stadium_card)
				child.texture = tex
				child.visible = true

# ---------- Stadium discard-to-owner helper (used when a stadium is removed by other effects) ----------
func remove_current_stadium(reason: String = "") -> void:
	if main.current_stadium_card == null:
		return
	var stadium = main.current_stadium_card
	var owner_discard = main.opponent_discard_pile if main.current_stadium_owner_is_opponent else main.player_discard_pile
	stadium.current_location = "discard"
	owner_discard.append(stadium)
	main.current_stadium_card = null
	display_stadium_card()
	main.update_discard_pile_display(main.current_stadium_owner_is_opponent)
	# Rocket's Hideout (neo3): clear the +20 max HP bonus now that the stadium is gone
	main.powers_and_bodies.refresh_rockets_hideout_hp()
	if reason != "":
		print("STADIUM REMOVED (" + reason + "): " + stadium.metadata.get("name", ""))

######################################################################################################################################################
######################################################## GYM1 STADIUM EFFECTS #######################################################################
######################################################################################################################################################

# gym1-124 Narrow Gym on-play: if either player has 5 benched Pokemon, return one to their hand.
# Per card text: opponent (relative to the player who played it) chooses theirs FIRST if both must return.
func gym1_narrow_gym_on_play() -> void:
	# Determine "you" and "opponent" relative to who played the card
	var player_played = not main.current_stadium_owner_is_opponent
	# If both have 5 bench, opponent (relative to the player who played) goes first
	# "opponent" relative to the stadium player is the OTHER side
	var stadium_player_is_opp = main.current_stadium_owner_is_opponent
	# Force-relative resolution
	var first_side_is_opp = not stadium_player_is_opp   # the opponent of the player who played
	var second_side_is_opp = stadium_player_is_opp

	await gym1_narrow_gym_force_return_to_hand(first_side_is_opp)
	if main._should_bail(): return
	await gym1_narrow_gym_force_return_to_hand(second_side_is_opp)
	if main._should_bail(): return

# Returns one of the side's benched pokemon (their choice) to their hand if their bench has 5
func gym1_narrow_gym_force_return_to_hand(side_is_opponent: bool) -> void:
	var bench = main.opponent_bench if side_is_opponent else main.player_bench
	if bench.size() < 5:
		return
	var hand = main.opponent_hand if side_is_opponent else main.player_hand
	var who = "OPPONENT" if side_is_opponent else "YOU"

	var chosen: card_object = null
	if side_is_opponent:
		# CPU picks the bench pokemon with the lowest strategic value (fewest energies, lowest HP %)
		var best_score = 99999.0
		for bp in bench:
			var max_hp = int(bp.metadata.get("hp", "0"))
			var hp_pct = float(bp.current_hp) / max(1, max_hp)
			var energy_count = bp.attached_energies.size()
			var s = energy_count * 100.0 + hp_pct * 50.0  # lower = worse, choose worst
			if s < best_score:
				best_score = s
				chosen = bp
	else:
		# Player chooses
		chosen = await main.card_ops.prompt_select_card(bench, "NARROW GYM", "Bench is full — choose a Pokemon to return to your hand", "SELECT", false)
		if main._should_bail(): return
	if chosen == null:
		return

	# Return chosen + all its attached cards/energies to the hand
	var to_return: Array = [chosen]
	to_return.append_array(chosen.attached_energies)
	to_return.append_array(chosen.attached_cards)
	to_return.append_array(chosen.attached_pre_evolutions)

	chosen.attached_energies.clear()
	chosen.attached_cards.clear()
	chosen.attached_pre_evolutions.clear()
	chosen.current_hp = chosen.get_max_hp()
	main.clear_all_statuses(chosen, side_is_opponent)
	chosen.pluspower_count = 0
	# ISSUE #90: clear defender_count alongside the turn counter — a stale count made the NEXT
	# Defender attached to this card stack on a phantom one.
	chosen.defender_count = 0
	chosen.defender_turns_remaining = -1

	bench.erase(chosen)
	for c in to_return:
		c.current_location = "hand"
		hand.append(c)

	main.display_pokemon(side_is_opponent)
	main.refresh_hand_display(side_is_opponent)
	await main.show_message(who + " RETURNED " + chosen.metadata.get("name", "").to_upper() + " TO HAND!")
	if main._should_bail(): return

# gym1-107 Celadon City Gym activation — discard 1 energy from an Erika-named Pokemon to clear its status conditions.
# Triggered from the power button (player) or cpu_phase_activate_powers (CPU).
func gym1_celadon_activate(is_opponent: bool) -> void:
	# Build list of eligible pokemon (Erika in name, has at least 1 energy, has any status condition)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var all_p: Array = []
	if active != null:
		all_p.append(active)
	all_p.append_array(bench)

	var eligible: Array = []
	for p in all_p:
		if not ("Erika" in p.metadata.get("name", "")):
			continue
		if p.attached_energies.size() == 0:
			continue
		if p.special_condition == "" and not p.is_poisoned and not p.is_burned:
			continue
		eligible.append(p)

	if eligible.size() == 0:
		if not is_opponent:
			await main.show_message("NO ELIGIBLE ERIKA POKEMON!")
		return

	var target: card_object = null
	var energy_to_discard: card_object = null
	if is_opponent:
		# CPU: pick the eligible pokemon with the most "value" to keep status-free (highest HP %)
		var best_score = -1.0
		for p in eligible:
			var max_hp = int(p.metadata.get("hp", "0"))
			var hp_pct = float(p.current_hp) / max(1, max_hp)
			if hp_pct > best_score:
				best_score = hp_pct
				target = p
		if target == null:
			return
		# CPU picks the LOWEST-priority energy to discard (last attached / non-special)
		energy_to_discard = target.attached_energies[target.attached_energies.size() - 1]
	else:
		# Player chooses Erika pokemon
		target = await main.card_ops.prompt_select_card(eligible, "CELADON CITY GYM", "Choose an Erika Pokemon to cure (discards 1 energy)", "SELECT", true)
		if main._should_bail(): return
		if target == null:
			return

		# Player chooses which energy to discard
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(target.attached_energies)
		main.header_label.text = "CHOOSE ENERGY TO DISCARD"
		main.hint_label.text = "Select an energy to discard from " + target.metadata.get("name", "")
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_discard = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		if energy_to_discard == null:
			return

	# Discard energy
	target.attached_energies.erase(energy_to_discard)
	var owner_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var owner_discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
	energy_to_discard.current_location = "discard"
	owner_discard.append(energy_to_discard)
	var from_node = main.find_card_ui_for_object(target)
	if from_node == null:
		from_node = main.opponent_active_container if is_opponent else main.player_active_container
	var energy_texture = main.get_card_texture(energy_to_discard)
	await main.animate_card_a_to_b(from_node, owner_discard_node, 0.2, energy_texture, main.card_scales[10])
	if main._should_bail(): return

	# Clear status conditions
	main.clear_all_statuses(target, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("CELADON CITY GYM: " + target.metadata.get("name", "").to_upper() + " IS CURED!")
	if main._should_bail(): return

	# Mark used for this turn
	if is_opponent:
		main.opponent_celadon_used_this_turn = true
	else:
		main.player_celadon_used_this_turn = true

# Checks if the side has a valid target for the Celadon activation. Used by power menu + CPU AI.
func gym1_celadon_has_target(is_opponent: bool) -> bool:
	if not main.is_stadium_in_play(StadiumIds.CELADON_CITY_GYM):
		return false
	if is_opponent and main.opponent_celadon_used_this_turn:
		return false
	if not is_opponent and main.player_celadon_used_this_turn:
		return false
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var all_p: Array = []
	if active != null:
		all_p.append(active)
	all_p.append_array(bench)
	for p in all_p:
		if not ("Erika" in p.metadata.get("name", "")):
			continue
		if p.attached_energies.size() == 0:
			continue
		if p.special_condition == "" and not p.is_poisoned and not p.is_burned:
			continue
		return true
	return false

# Centralized "No Removal Gym (gym1-103) tax" — discards 2 cards from the side's hand
# before an Energy Removal / Super Energy Removal resolves. Returns false if the play should be aborted.
func gym1_no_removal_gym_pay_tax(card: card_object, is_opponent: bool) -> bool:
	if not main.is_stadium_in_play(StadiumIds.NO_REMOVAL_GYM):
		return true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
	var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container

	var available: Array = []
	for c in hand:
		if c != card:
			available.append(c)
	if available.size() < 2:
		await main.show_message("NO REMOVAL GYM: NOT ENOUGH CARDS TO DISCARD!")
		return false

	var to_discard: Array = []
	if is_opponent:
		# CPU picks the lowest-priority 2 cards (uses existing helper)
		to_discard = cpu_get_discard_priority(hand, 2, card)
	else:
		# Player picks 2 cards
		await main.show_message("NO REMOVAL GYM: DISCARD 2 CARDS FROM YOUR HAND")
		if main._should_bail(): return false
		main.trainer_discard_selection_active = true
		main.trainer_discard_cards_needed = 2
		main.trainer_discard_selected = []
		main.header_label.text = "NO REMOVAL GYM"
		main.hint_label.text = "Choose 2 cards to discard"
		main.action_button.text = "DISCARD (0/2)"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		main.show_enlarged_array_selection_mode(available)
		await main.trainer_discard_selection_done
		if main._should_bail(): return false
		to_discard = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selection_active = false
		main.trainer_discard_selected = []
		main.hide_selection_mode_display_main()

	# Discard chosen cards
	for c in to_discard:
		hand.erase(c)
		c.current_location = "discard"
		discard.append(c)
		var ctex = main.get_card_texture(c)
		await main.animate_card_a_to_b(hand_node, discard_node, 0.2, ctex, main.card_scales[10])
		if main._should_bail(): return false
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	return true

######################################################################################################################################################
###################################################### GYM2 (GYM CHALLENGE) TRAINER EFFECTS #########################################################
######################################################################################################################################################

# Switch prompt for Koga's Ninja Trick (gym2-115). Returns true if a switch happened.
func gym2_koga_ninja_trick_offer_switch(defender: card_object, defender_is_opp: bool) -> bool:
	var bench = main.opponent_bench if defender_is_opp else main.player_bench
	if bench.size() == 0:
		return false
	var chosen: card_object = null
	if defender_is_opp:
		# CPU side: switch in the bench pokemon with the highest HP if our active is in worse shape
		var def_max = int(defender.metadata.get("hp", "0"))
		var def_pct = float(defender.current_hp) / max(1, def_max)
		var best_pct = def_pct
		for bp in bench:
			var max_hp = int(bp.metadata.get("hp", "0"))
			var pct = float(bp.current_hp) / max(1, max_hp)
			if pct > best_pct + 0.15:
				best_pct = pct
				chosen = bp
		if chosen == null:
			return false
	else:
		# Player chooses — YES/NO prompt anchored on the defender card
		var yes = await gym1_prompt_yes_no(defender, "KOGA'S NINJA TRICK", "Switch " + defender.metadata.get("name", "") + " with a Benched Pokemon?", "SWITCH", "STAY")
		if not yes:
			return false
		chosen = await main.card_ops.prompt_select_card(bench, "KOGA'S NINJA TRICK — SWITCH WITH WHICH?", "Choose a Benched Pokemon to swap in", "SWITCH", false)
		if main._should_bail(): return false
	if chosen == null:
		return false

	# Perform the swap: defender → bench, chosen → active. The Koga tool stays attached to defender
	# but the rules say "If this Pokémon goes to your Bench, discard this card." — so discard it.
	var discard = main.opponent_discard_pile if defender_is_opp else main.player_discard_pile
	var to_discard_tool: card_object = null
	for ac in defender.attached_cards:
		if ac.uid.to_lower() == "gym2-115":
			to_discard_tool = ac
			break
	if to_discard_tool != null:
		defender.attached_cards.erase(to_discard_tool)
		to_discard_tool.current_location = "discard"
		discard.append(to_discard_tool)
		defender.gym2_koga_ninja_trick_attached = false
	# Move chosen to active slot
	bench.erase(chosen)
	chosen.current_location = "active"
	defender.current_location = "bench"
	bench.append(defender)
	if defender_is_opp:
		main.opponent_active_pokemon = chosen
	else:
		main.player_active_pokemon = chosen
	main.display_pokemon(defender_is_opp)
	main.display_active_pokemon_energies(defender_is_opp)
	main.update_discard_pile_display(defender_is_opp)
	display_attached_trainer_cards(defender_is_opp)
	await main.show_message("KOGA'S NINJA TRICK — SWITCHED IN " + chosen.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return false
	return true

# ============================ gym2-17 / gym2-100 — Blaine ============================
# Instead of this turn's free Energy attach, attach 2 Fire Energy from hand to a Blaine-named Pokemon.
func gym2_effect_blaine(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	# Collect 2 Fire Energies
	var fires: Array = []
	for c in hand:
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Fire Energy":
			fires.append(c)
			if fires.size() >= 2:
				break
	if fires.size() < 2:
		return
	# Choose a Blaine pokemon
	var blaine_targets: Array = []
	for p in build_field_pokemon_array(is_opponent):
		if "Blaine" in p.metadata.get("name", ""):
			blaine_targets.append(p)
	if blaine_targets.size() == 0:
		return
	var target: card_object = null
	if is_opponent:
		# CPU: pick the active if it's Blaine, else first Blaine bench
		if main.opponent_active_pokemon != null and "Blaine" in main.opponent_active_pokemon.metadata.get("name", ""):
			target = main.opponent_active_pokemon
		else:
			target = blaine_targets[0]
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(blaine_targets, "BLAINE — ATTACH 2 FIRE ENERGY", "Choose a Blaine Pokemon", "ATTACH", false)
		if main._should_bail(): return
	if target == null:
		return
	# Move the 2 Fire Energies onto the target
	for fire in fires:
		hand.erase(fire)
		fire.current_location = "active" if target == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon) else "bench"
		target.attached_energies.append(fire)
	# Consume the energy-played-this-turn slot and mark Blaine as used
	# MATCH EFFECT: extra_energy_per_turn — flag only set once the per-turn limit is reached
	if is_opponent:
		main.opponent_energy_attach_count += 1
		main.opponent_energy_played_this_turn = main.opponent_energy_attach_count >= main.match_effects.energy_attach_limit(true)
		main.opponent_blaine_double_attach_used = true
	else:
		main.player_energy_attach_count += 1
		main.player_energy_played_this_turn = main.player_energy_attach_count >= main.match_effects.energy_attach_limit(false)
		main.player_blaine_double_attach_used = true
	main.refresh_hand_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("BLAINE — 2 FIRE ENERGY ATTACHED TO " + target.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# ============================ gym2-18 / gym2-104 — Giovanni ============================
# Choose a Giovanni-named pokemon; for the rest of the turn it can evolve free of restrictions (and the buff carries through evolution).
func gym2_effect_giovanni(is_opponent: bool) -> void:
	var giovannis: Array = []
	for p in build_field_pokemon_array(is_opponent):
		if "Giovanni" in p.metadata.get("name", ""):
			giovannis.append(p)
	if giovannis.size() == 0:
		return
	var target: card_object = null
	if is_opponent:
		# CPU: pick the lowest-stage Giovanni first (more evolution headroom)
		var best_stage = 999
		for p in giovannis:
			var subs = p.metadata.get("subtypes", [])
			var stage = 0
			if "Stage 1" in subs:
				stage = 1
			elif "Stage 2" in subs:
				stage = 2
			if stage < best_stage:
				best_stage = stage
				target = p
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(giovannis, "GIOVANNI — CHOOSE A POKEMON", "It can evolve freely this turn", "SELECT", false)
		if main._should_bail(): return
	if target == null:
		return
	target.gym2_giovanni_evolve_anywhere = true
	await main.show_message("GIOVANNI — " + target.metadata.get("name", "").to_upper() + " CAN EVOLVE FREELY THIS TURN!")
	if main._should_bail(): return

# ============================ gym2-19 / gym2-106 — Koga ============================
# This turn, any damage attack from a Koga-named pokemon poisons the defender.
func gym2_effect_koga(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_koga_poison_active = true
	else:
		main.player_koga_poison_active = true
	await main.show_message("KOGA — KOGA POKEMON WILL POISON DEFENDERS THIS TURN!")
	if main._should_bail(): return

# ============================ gym2-20 / gym2-110 — Sabrina ============================
# Move all energies from one Sabrina-named pokemon to another Sabrina-named pokemon.
func gym2_effect_sabrina(is_opponent: bool) -> void:
	var sabrinas: Array = []
	for p in build_field_pokemon_array(is_opponent):
		if "Sabrina" in p.metadata.get("name", ""):
			sabrinas.append(p)
	if sabrinas.size() < 2:
		return
	var sources: Array = []
	for s in sabrinas:
		if s.attached_energies.size() > 0:
			sources.append(s)
	if sources.size() == 0:
		return

	var source: card_object = null
	var dest: card_object = null

	if is_opponent:
		# CPU: pick the most-energy-laden Sabrina with the FEWEST attack uses (heuristic: bench candidate)
		var best_e = 0
		for s in sources:
			if s.attached_energies.size() > best_e:
				best_e = s.attached_energies.size()
				source = s
		# Destination: any other Sabrina (prefer active)
		if main.opponent_active_pokemon != null and "Sabrina" in main.opponent_active_pokemon.metadata.get("name", "") and main.opponent_active_pokemon != source:
			dest = main.opponent_active_pokemon
		else:
			for s in sabrinas:
				if s != source:
					dest = s
					break
	else:
		# Player picks source then destination
		source = await main.card_ops.prompt_select_card(sources, "SABRINA — PICK ENERGY SOURCE", "Move all its energies", "SELECT", false)
		if main._should_bail(): return
		if source == null:
			return
		var dest_candidates: Array = []
		for s in sabrinas:
			if s != source:
				dest_candidates.append(s)
		if dest_candidates.size() == 0:
			return
		dest = await main.card_ops.prompt_select_card(dest_candidates, "SABRINA — PICK DESTINATION", "Energy from " + source.metadata.get("name", "") + " moves here", "SELECT", false)
		if main._should_bail(): return

	if source == null or dest == null:
		return

	# Determine destination's location category
	var dest_loc = "active" if dest == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon) else "bench"
	for e in source.attached_energies:
		e.current_location = dest_loc
		dest.attached_energies.append(e)
	source.attached_energies.clear()
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("SABRINA — ENERGIES MOVED FROM " + source.metadata.get("name", "").to_upper() + " TO " + dest.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# ============================ gym2-103 — Erika's Kindness ============================
# Heal 20 from every damaged pokemon on both sides (or 10 if it had just 1 damage counter).
func gym2_effect_erikas_kindness(_is_opponent: bool) -> void:
	for side in [false, true]:
		for p in build_field_pokemon_array(side):
			var max_hp = p.get_max_hp()
			if p.current_hp >= max_hp:
				continue
			var damage = max_hp - p.current_hp
			var heal = 20 if damage > 10 else 10
			await main.card_ops.heal_pokemon(p, heal, side)
			if main._should_bail(): return
	await main.show_message("ERIKA'S KINDNESS — REMOVED 2 DAMAGE COUNTERS FROM EVERY DAMAGED POKEMON!")
	if main._should_bail(): return

# ============================ gym2-105 — Giovanni's Last Resort ============================
# Remove all damage counters from a Giovanni-named pokemon; then discard your hand.
func gym2_effect_giovannis_last_resort(is_opponent: bool) -> void:
	var giovannis: Array = []
	for p in build_field_pokemon_array(is_opponent):
		if "Giovanni" in p.metadata.get("name", "") and p.current_hp < int(p.metadata.get("hp", "0")):
			giovannis.append(p)
	if giovannis.size() == 0:
		return
	var target: card_object = null
	if is_opponent:
		# Pick the most-damaged
		var most = 0
		for p in giovannis:
			var d = int(p.metadata.get("hp", "0")) - p.current_hp
			if d > most:
				most = d
				target = p
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(giovannis, "GIOVANNI'S LAST RESORT", "Choose a Giovanni Pokemon to fully heal (will discard your hand)", "HEAL", false)
		if main._should_bail(): return
	if target == null:
		return
	await main.card_ops.heal_pokemon(target, target.get_max_hp(), is_opponent)
	if main._should_bail(): return
	# Discard hand
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for c in hand.duplicate():
		c.current_location = "discard"
		discard.append(c)
	hand.clear()
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("GIOVANNI'S LAST RESORT — " + target.metadata.get("name", "").to_upper() + " FULLY HEALED. HAND DISCARDED!")
	if main._should_bail(): return

# ============================ gym2-107 — Lt. Surge's Secret Plan ============================
# SIMPLIFIED: player picks a Basic Pokemon from hand to bench. (Face-down bluff mechanic NOT implemented in this version.)
# If a non-Basic is somehow picked, the card is discarded.
func gym2_effect_lt_surges_secret_plan(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	if bench.size() >= main.get_max_bench_size() or hand.size() == 0:
		return
	# Build candidates: any card from hand can be picked. Basics → bench normally; non-basics → discard.
	if is_opponent:
		# CPU doesn't play this card (returns early via -100 score), but for safety pick a basic if available.
		var basics: Array = []
		for c in hand:
			if main.is_basic_pokemon(c):
				basics.append(c)
		if basics.size() == 0:
			return
		var pick = main.cpu_ai.cpu_pick_best_keep(basics)
		hand.erase(pick)
		pick.current_hp = pick.get_max_hp()
		pick.current_location = "bench"
		pick.placed_on_field_this_turn = true
		bench.append(pick)
		main.refresh_hand_display(true)
		main.display_pokemon(true)
		return
	# Player path
	var pick_c = await main.card_ops.prompt_select_card(hand, "LT. SURGE'S SECRET PLAN", "Pick a card to put on bench (must be a Basic Pokemon, or it's discarded)", "BENCH", false)
	if main._should_bail(): return
	if pick_c == null:
		return
	hand.erase(pick_c)
	if main.is_basic_pokemon(pick_c):
		pick_c.current_hp = pick_c.get_max_hp()
		pick_c.current_location = "bench"
		pick_c.placed_on_field_this_turn = true
		bench.append(pick_c)
		main.refresh_hand_display(false)
		main.display_pokemon(false)
		await main.show_message("LT. SURGE'S SECRET PLAN — " + pick_c.metadata.get("name", "").to_upper() + " BENCHED!")
	else:
		pick_c.current_location = "discard"
		discard.append(pick_c)
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)
		await main.show_message("LT. SURGE'S SECRET PLAN — NOT A BASIC POKEMON! DISCARDED!")
	if main._should_bail(): return

# ============================ gym2-108 — Misty's Wish ============================
# Look at a prize. The opponent decides: swap with one of your hand cards, or you draw 1.
func gym2_effect_mistys_wish(is_opponent: bool) -> void:
	var prizes = main.opponent_prize_cards if is_opponent else main.player_prize_cards
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if prizes.size() == 0:
		return
	# Card player looks at a prize
	var chosen_prize: card_object = null
	if is_opponent:
		chosen_prize = prizes[randi() % prizes.size()]
	else:
		chosen_prize = await main.card_ops.prompt_select_card(prizes, "MISTY'S WISH — LOOK AT A PRIZE", "Pick a Prize card to examine", "LOOK", false)
		if main._should_bail(): return
	if chosen_prize == null:
		return

	# The OTHER side decides: accept the swap (player gets prize → hand; their picked card → prize stack) or decline (player draws 1).
	# CPU decision: accept the swap if the prize is a key card type (any Pokémon or any Trainer) — denies player a free key card.
	# Player as decider: auto-decline by default (TODO: prompt UI later). Same fallback as effect_challenge.
	# Simplified: ALWAYS decline (other side blocks the swap; card player draws 1).
	if hand.size() == 0:
		# Can't swap anyway; draw 1
		await main.card_ops.draw_n(is_opponent, 1)
		if main._should_bail(): return
		await main.show_message("MISTY'S WISH — DREW A CARD!")
		return
	# Decision logic: accept if prize is a Pokemon (deny the card player the setup advantage)
	var prize_is_pokemon = chosen_prize.metadata.get("supertype", "") == "Pokémon"
	var accept = prize_is_pokemon
	if accept:
		# Card player picks a hand card to swap
		var swap_card: card_object = null
		if is_opponent:
			# CPU swap: pick lowest-value hand card
			var to_swap = cpu_get_discard_priority(hand, 1)
			if to_swap.size() > 0:
				swap_card = to_swap[0]
		else:
			swap_card = await main.card_ops.prompt_select_card(hand, "MISTY'S WISH — SWAP WITH WHICH CARD?", "This card replaces the chosen Prize card", "SWAP", false)
			if main._should_bail(): return
		if swap_card != null:
			# Swap prize ↔ hand card
			var prize_idx = prizes.find(chosen_prize)
			hand.erase(swap_card)
			chosen_prize.current_location = "hand"
			hand.append(chosen_prize)
			swap_card.current_location = "prize"
			prizes[prize_idx] = swap_card
			main.refresh_hand_display(is_opponent)
			main.display_prize_cards(is_opponent)
			await main.show_message("MISTY'S WISH — SWAPPED PRIZE WITH " + swap_card.metadata.get("name", "").to_upper() + "!")
			if main._should_bail(): return
		return
	# Declined → draw 1
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	await main.show_message("MISTY'S WISH — OPPONENT DECLINED. DREW A CARD!")
	if main._should_bail(): return

# ============================ gym2-111 — Blaine's Quiz #2 ============================
# Coin-flip approximation of category guess.
func gym2_effect_blaines_quiz_2(is_opponent: bool) -> void:
	await main.show_message("BLAINE'S QUIZ #2 — FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var other = not is_opponent
		await main.card_ops.draw_n(other, 2)
		if main._should_bail(): return
		await main.show_message("OPPONENT GUESSED RIGHT! THEY DREW 2 CARDS!")
	else:
		await main.card_ops.draw_n(is_opponent, 2)
		if main._should_bail(): return
		await main.show_message("OPPONENT GUESSED WRONG! YOU DREW 2 CARDS!")
	if main._should_bail(): return

# ============================ gym2-112 — Blaine's Quiz #3 ============================
# Coin-flip approximation of card-name guess (rewards are 3 cards).
func gym2_effect_blaines_quiz_3(is_opponent: bool) -> void:
	await main.show_message("BLAINE'S QUIZ #3 — FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var other = not is_opponent
		await main.card_ops.draw_n(other, 3)
		if main._should_bail(): return
		await main.show_message("OPPONENT GUESSED RIGHT! THEY DREW 3 CARDS!")
	else:
		await main.card_ops.draw_n(is_opponent, 3)
		if main._should_bail(): return
		await main.show_message("OPPONENT GUESSED WRONG! YOU DREW 3 CARDS!")
	if main._should_bail(): return

# ============================ gym2-116 — Master Ball ============================
# Look at top 7 of deck; choose one Pokemon (Basic or Evolution) to add to hand; shuffle the rest back.
func gym2_effect_master_ball(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.size() == 0:
		return
	var n = min(7, deck.size())
	var top: Array = []
	for i in range(n):
		top.append(deck[i])
	for c in top:
		deck.erase(c)
	var pokemon_candidates: Array = []
	for c in top:
		if c.metadata.get("supertype", "") == "Pokémon":
			pokemon_candidates.append(c)
	var chosen: card_object = null
	if is_opponent:
		# CPU: use existing search heuristic
		chosen = main.cpu_ai.cpu_search_deck_for_best_pokemon(pokemon_candidates)
		if chosen == null and pokemon_candidates.size() > 0:
			chosen = pokemon_candidates[0]
	else:
		if pokemon_candidates.size() == 0:
			await main.show_message("MASTER BALL — NO POKEMON IN TOP 7!")
		else:
			chosen = await main.card_ops.prompt_select_card(pokemon_candidates, "MASTER BALL — CHOOSE A POKEMON", "Add a Basic or Evolution to your hand", "TAKE", true, true)
			if main._should_bail(): return
			main.cancel_button.text = "Cancel"
	if chosen != null:
		top.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
	# Shuffle the rest back
	for c in top:
		c.current_location = "deck"
		deck.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if chosen != null:
		await main.show_message("MASTER BALL — ADDED " + chosen.metadata.get("name", "").to_upper() + " TO HAND!")
	else:
		await main.show_message("MASTER BALL — SHUFFLED CARDS BACK!")
	if main._should_bail(): return

# ============================ gym2-117 — Max Revive ============================
# Discard 2 Energy from hand. Put 1 Basic Pokemon from discard onto bench.
func gym2_effect_max_revive(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var bench = main.opponent_bench if is_opponent else main.player_bench

	# Step 1: discard 2 Energy cards
	var energy_in_hand: Array = []
	for c in hand:
		if c.metadata.get("supertype", "") == "Energy":
			energy_in_hand.append(c)
	if energy_in_hand.size() < 2:
		return
	var to_discard: Array = []
	if is_opponent:
		to_discard.append(energy_in_hand[0])
		to_discard.append(energy_in_hand[1])
	else:
		# Player picks 2 energies
		for i in range(2):
			var remaining: Array = []
			for c in energy_in_hand:
				if c not in to_discard:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var pick = await main.card_ops.prompt_select_card(remaining, "MAX REVIVE — DISCARD ENERGY " + str(i + 1) + "/2", "Discard an Energy card", "DISCARD", false)
			if main._should_bail(): return
			if pick == null:
				return
			to_discard.append(pick)
	if to_discard.size() < 2:
		return
	for e in to_discard:
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)

	# Step 2: pick a Basic Pokemon from discard
	var basics_in_disc: Array = []
	for c in discard:
		if c == played_card:
			continue
		if main.is_basic_pokemon(c):
			basics_in_disc.append(c)
	if basics_in_disc.size() == 0:
		return
	var revive_pick: card_object = null
	if is_opponent:
		revive_pick = main.cpu_ai.cpu_search_deck_for_best_pokemon(basics_in_disc)
		if revive_pick == null:
			revive_pick = basics_in_disc[0]
	else:
		revive_pick = await main.card_ops.prompt_select_card(basics_in_disc, "MAX REVIVE — PICK A BASIC", "Place it on your bench", "REVIVE", false)
		if main._should_bail(): return
	if revive_pick == null:
		return
	discard.erase(revive_pick)
	revive_pick.current_hp = revive_pick.get_max_hp()
	revive_pick.current_location = "bench"
	revive_pick.placed_on_field_this_turn = true
	bench.append(revive_pick)
	main.update_discard_pile_display(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("MAX REVIVE — " + revive_pick.metadata.get("name", "").to_upper() + " BENCHED!")
	if main._should_bail(): return

# ============================ gym2-118 — Misty's Tears ============================
# Discard 1 other card; search deck for up to 2 Water Energy.
func gym2_effect_mistys_tears(played_card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	# Step 1: discard 1
	if is_opponent:
		var to_disc = cpu_get_discard_priority(hand, 1, played_card)
		for c in to_disc:
			hand.erase(c)
			c.current_location = "discard"
			discard.append(c)
		main.refresh_hand_display(true)
	else:
		await player_select_cards_to_discard(hand, 1, "MISTY'S TEARS", "Discard 1 card")
		if main._should_bail(): return
		for c in main.trainer_discard_selected:
			hand.erase(c)
			c.current_location = "discard"
			discard.append(c)
		main.trainer_discard_selected.clear()
		main.refresh_hand_display(false)
		main.update_discard_pile_display(false)

	# Step 2: pick up to 2 Water Energy
	var waters: Array = []
	for c in deck:
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Water Energy":
			waters.append(c)
	if waters.size() == 0:
		deck.shuffle()
		return
	var picks: Array = []
	var max_n = min(2, waters.size())
	if is_opponent:
		for i in range(max_n):
			picks.append(waters[i])
	else:
		for i in range(max_n):
			var remaining: Array = []
			for c in waters:
				if c not in picks:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var pick = await main.card_ops.prompt_select_card(remaining, "MISTY'S TEARS — PICK WATER ENERGY " + str(i + 1) + "/" + str(max_n), "Add a Water Energy to your hand", "TAKE", true, true)
			if main._should_bail(): return
			main.cancel_button.theme = main.theme_red
			if pick == null:
				break
			picks.append(pick)
	for c in picks:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("MISTY'S TEARS — TOOK " + str(picks.size()) + " WATER ENERGY!")
	if main._should_bail(): return

# ============================ gym2-120 — Rocket's Secret Experiment ============================
# Coin. Heads = search deck for any card. Tails = trainer lock until end of opp's next turn.
func gym2_effect_rockets_secret_experiment(is_opponent: bool) -> void:
	await main.show_message("ROCKET'S SECRET EXPERIMENT — FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var deck = main.opponent_deck if is_opponent else main.player_deck
		var hand = main.opponent_hand if is_opponent else main.player_hand
		if deck.size() == 0:
			return
		var chosen: card_object = null
		if is_opponent:
			chosen = main.cpu_ai.cpu_search_deck_for_best_card(deck)
		else:
			chosen = await main.card_ops.prompt_select_card(deck, "ROCKET'S SECRET EXPERIMENT — CHOOSE ANY CARD", "Add it to your hand", "TAKE", false, true)
			if main._should_bail(): return
		if chosen != null:
			deck.erase(chosen)
			chosen.current_location = "hand"
			hand.append(chosen)
		deck.shuffle()
		main.refresh_hand_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("HEADS! ADDED " + (chosen.metadata.get("name", "").to_upper() if chosen != null else "...") + " TO HAND!")
	else:
		# Tails: trainer lock on the card player until end of opp's next turn
		if is_opponent:
			opponent_trainer_locked = true
		else:
			player_trainer_locked = true
		await main.show_message("TAILS! TRAINER CARDS LOCKED UNTIL END OF OPPONENT'S NEXT TURN!")
	if main._should_bail(): return

# ============================ gym2-121 — Sabrina's Psychic Control ============================
# Coin. Heads = use any non-attached Trainer card from opp's discard as your own.
func gym2_effect_sabrinas_psychic_control(is_opponent: bool) -> void:
	await main.show_message("SABRINA'S PSYCHIC CONTROL — FLIPPING COIN…")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NOTHING HAPPENS!")
		if main._should_bail(): return
		return
	var opp_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	# Filter eligible trainers
	var eligible: Array = []
	for c in opp_discard:
		if is_trainer_card(c) and not is_attached_trainer(c) and not is_bench_token_trainer(c) and not is_stadium_trainer(c):
			eligible.append(c)
	if eligible.size() == 0:
		await main.show_message("HEADS! BUT NO ELIGIBLE TRAINERS IN OPPONENT'S DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		var best = -999.0
		for c in eligible:
			var score = main.cpu_ai.cpu_score_trainer_card(c)
			if score > best:
				best = score
				chosen = c
	else:
		chosen = await main.card_ops.prompt_select_card(eligible, "SABRINA'S PSYCHIC CONTROL — CHOOSE A TRAINER", "Use it as if it were in your hand", "USE", false)
		if main._should_bail(): return
	if chosen == null:
		return
	# Resolve the chosen trainer's effect using the standard dispatcher with is_opponent = current side.
	# The card stays in the opp's discard (we don't move it).
	await main.show_message("HEADS! USING " + chosen.metadata.get("name", "").to_upper() + " FROM OPPONENT'S DISCARD!")
	if main._should_bail(): return
	await resolve_standard_trainer(chosen, is_opponent)
	if main._should_bail(): return

# ============================ gym2-124 — Fervor ============================
# Show top 3 to all; Fire Energy goes to hand; rest goes to discard.
func gym2_effect_fervor(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var n = min(3, deck.size())
	if n == 0:
		return
	var top: Array = []
	for i in range(n):
		top.append(deck[i])
	for c in top:
		deck.erase(c)
	var taken = 0
	for c in top:
		if c.metadata.get("supertype", "") == "Energy" and c.metadata.get("name", "") == "Fire Energy":
			c.current_location = "hand"
			hand.append(c)
			taken += 1
		else:
			c.current_location = "discard"
			discard.append(c)
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("FERVOR — TOOK " + str(taken) + " FIRE ENERGY; DISCARDED " + str(n - taken) + "!")
	if main._should_bail(): return

# ============================ gym2-125 — Transparent Walls ============================
# Until end of opp's next turn, prevent all damage from attacks to your benched pokemon.
func gym2_effect_transparent_walls(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_transparent_walls_active = true
	else:
		main.player_transparent_walls_active = true
	await main.show_message("TRANSPARENT WALLS — BENCH IS PROTECTED!")
	if main._should_bail(): return

# ============================ gym2-126 — Warp Point ============================
# If opp has bench, opp chooses one of their bench to switch with their active. Then you switch one of your bench with your active.
func gym2_effect_warp_point(is_opponent: bool) -> void:
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_active_ref = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	# Step 1: opp side switches
	if opp_bench.size() > 0 and opp_active_ref != null:
		var opp_pick: card_object = null
		var opp_chooses_is_opp = not is_opponent  # the OTHER side chooses
		if opp_chooses_is_opp:
			# CPU is the chooser — pick the worst bench candidate (least useful frontline) to swap in
			var worst_hp = 9999
			for bp in opp_bench:
				var hp = int(bp.metadata.get("hp", "0"))
				if hp < worst_hp:
					worst_hp = hp
					opp_pick = bp
		else:
			# Player is the chooser — but it's the opponent's bench they're switching (this is unusual UX)
			opp_pick = await main.card_ops.prompt_select_card(opp_bench, "WARP POINT — OPPONENT MUST CHOOSE", "(you decide for them) Pick which of their bench switches in", "SWITCH", false)
			if main._should_bail(): return
		if opp_pick != null:
			opp_bench.erase(opp_pick)
			opp_pick.current_location = "active"
			opp_active_ref.current_location = "bench"
			opp_bench.append(opp_active_ref)
			if is_opponent:
				main.player_active_pokemon = opp_pick
			else:
				main.opponent_active_pokemon = opp_pick
			main.display_pokemon(not is_opponent)
			main.display_active_pokemon_energies(not is_opponent)
			await main.show_message("WARP POINT — OPPONENT'S " + opp_pick.metadata.get("name", "").to_upper() + " IS NOW ACTIVE!")
			if main._should_bail(): return

	# Step 2: card player switches one of their bench
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_bench.size() == 0 or own_active == null:
		return
	var own_pick: card_object = null
	if is_opponent:
		# CPU picks best bench to swap in (highest HP%)
		var best_pct = -1.0
		for bp in own_bench:
			var max_hp = int(bp.metadata.get("hp", "0"))
			var pct = float(bp.current_hp) / max(1, max_hp)
			if pct > best_pct:
				best_pct = pct
				own_pick = bp
	else:
		own_pick = await main.card_ops.prompt_select_card(own_bench, "WARP POINT — CHOOSE A BENCHED POKEMON", "Switch them with your Active", "SWITCH", false)
		if main._should_bail(): return
	if own_pick == null:
		return
	own_bench.erase(own_pick)
	own_pick.current_location = "active"
	own_active.current_location = "bench"
	own_bench.append(own_active)
	if is_opponent:
		main.opponent_active_pokemon = own_pick
	else:
		main.player_active_pokemon = own_pick
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("WARP POINT — YOUR " + own_pick.metadata.get("name", "").to_upper() + " IS NOW ACTIVE!")
	if main._should_bail(): return

######################################################################################################################################################
######################################################## GYM2 STADIUM EFFECTS #######################################################################
######################################################################################################################################################

# GYM2-119 Rocket's Minefield Gym trigger — call after a Basic Pokemon is benched from hand.
# Flip a coin; tails puts MINEFIELD_DAMAGE (20) on the pokemon.
const MINEFIELD_TAILS_DAMAGE: int = 20

func gym2_minefield_gym_trigger(pokemon: card_object, is_opponent: bool) -> void:
	if not main.is_stadium_in_play(StadiumIds.ROCKETS_MINEFIELD_GYM):
		return
	if pokemon == null:
		return
	# Only triggers for actual Basic Pokemon (not bench tokens like Mysterious Fossil / Clefairy Doll)
	if not main.is_basic_pokemon(pokemon):
		return
	if pokemon.is_bench_token:
		return

	await main.show_message("ROCKET'S MINEFIELD GYM: FLIPPING FOR " + pokemon.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	var heads = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if heads:
		await main.show_message("HEADS! " + pokemon.metadata.get("name", "").to_upper() + " IS SAFE!")
		if main._should_bail(): return
		return
	# Tails: apply damage
	pokemon.current_hp = max(0, pokemon.current_hp - MINEFIELD_TAILS_DAMAGE)
	main.display_hp_circles_above_align(pokemon, not is_opponent)
	await main.show_message("TAILS! " + pokemon.metadata.get("name", "").to_upper() + " TAKES " + str(MINEFIELD_TAILS_DAMAGE) + " DAMAGE!")
	if main._should_bail(): return
	# Knockouts from Minefield are handled by the normal KO check next time check_all_knockouts runs.
	await main.check_and_handle_knockout(pokemon, is_opponent)

# ============================ gym2-114 Fuchsia City Gym ============================
# Activatable: once per player's turn, may flip a coin. Heads shuffles a chosen Koga pokemon
# (and all attached cards/energies/pre-evolutions) into its owner's deck.

func gym2_fuchsia_has_target(is_opponent: bool) -> bool:
	if not main.is_stadium_in_play(StadiumIds.FUCHSIA_CITY_GYM):
		return false
	if is_opponent and main.opponent_fuchsia_used_this_turn:
		return false
	if not is_opponent and main.player_fuchsia_used_this_turn:
		return false
	# Eligibility: any Koga-named pokemon in play (active or bench)
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null and "Koga" in active.metadata.get("name", ""):
		return true
	for bp in bench:
		if "Koga" in bp.metadata.get("name", ""):
			return true
	return false

func gym2_fuchsia_activate(is_opponent: bool) -> void:
	# Mark used immediately (regardless of flip outcome, per "once during each player's turn")
	if is_opponent:
		main.opponent_fuchsia_used_this_turn = true
	else:
		main.player_fuchsia_used_this_turn = true

	# Build list of Koga-named pokemon
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var eligible: Array = []
	if active != null and "Koga" in active.metadata.get("name", ""):
		eligible.append(active)
	for bp in bench:
		if "Koga" in bp.metadata.get("name", ""):
			eligible.append(bp)
	if eligible.size() == 0:
		return

	# Flip first
	await main.show_message("FUCHSIA CITY GYM: FLIPPING COIN...")
	if main._should_bail(): return
	var heads = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not heads:
		await main.show_message("TAILS! NO EFFECT.")
		return

	# Pick which Koga to shuffle in
	var chosen: card_object = null
	if is_opponent:
		# CPU: pick the most-damaged Koga pokemon (recovery is most valuable for hurt ones)
		var most_damaged = 0
		for p in eligible:
			var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
			if dmg > most_damaged:
				most_damaged = dmg
				chosen = p
		if chosen == null:
			chosen = eligible[0]  # fallback
	else:
		# Player chooses
		chosen = await main.card_ops.prompt_select_card(eligible, "FUCHSIA CITY GYM", "Choose a Koga Pokemon to shuffle into your deck (with all attached)", "SELECT", true)
		if main._should_bail(): return
		if chosen == null:
			return

	# Special case: if chosen is the active and bench is empty, we'd lose the match — disallow
	if chosen == active and bench.size() == 0:
		await main.show_message("CAN'T SHUFFLE YOUR ONLY POKEMON!")
		return

	# Gather all the cards that go back to the deck with this pokemon
	var to_shuffle: Array = [chosen]
	to_shuffle.append_array(chosen.attached_energies)
	to_shuffle.append_array(chosen.attached_cards)
	to_shuffle.append_array(chosen.attached_pre_evolutions)

	chosen.attached_energies.clear()
	chosen.attached_cards.clear()
	chosen.attached_pre_evolutions.clear()
	chosen.current_hp = chosen.get_max_hp()
	main.clear_all_statuses(chosen, is_opponent)
	chosen.pluspower_count = 0
	# ISSUE #90: clear defender_count alongside the turn counter — a stale count made the NEXT
	# Defender attached to this card stack on a phantom one.
	chosen.defender_count = 0
	chosen.defender_turns_remaining = -1

	# If chosen was active, promote a bench pokemon to active first
	if chosen == active:
		var promoted: card_object = bench[0]
		if is_opponent:
			var cpu_eval = main.cpu_ai.get_cpu_evaluation()
			var best_promote = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, cpu_eval)
			if best_promote != null: promoted = best_promote
		bench.erase(promoted)
		promoted.current_location = "active"
		if is_opponent:
			main.opponent_active_pokemon = promoted
		else:
			main.player_active_pokemon = promoted
	else:
		bench.erase(chosen)

	# Move cards to deck and shuffle
	for c in to_shuffle:
		c.current_location = "deck"
		deck.append(c)
	deck.shuffle()

	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("FUCHSIA CITY GYM: " + chosen.metadata.get("name", "").to_upper() + " SHUFFLED INTO DECK!")
	if main._should_bail(): return

# ============================ gym2-122 Saffron City Gym ============================
# Activatable (as often as you like during your turn): return 1 basic Energy from a Sabrina-named pokemon to hand.

func gym2_saffron_has_target(is_opponent: bool) -> bool:
	if not main.is_stadium_in_play(StadiumIds.SAFFRON_CITY_GYM):
		return false
	if is_opponent and main.opponent_saffron_used_this_turn: return false
	if not is_opponent and main.player_saffron_used_this_turn: return false
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_p: Array = []
	if active != null:
		all_p.append(active)
	all_p.append_array(bench)
	for p in all_p:
		if not ("Sabrina" in p.metadata.get("name", "")):
			continue
		for e in p.attached_energies:
			if main.is_basic_energy_card(e):
				return true
	return false

func gym2_saffron_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_saffron_used_this_turn = true
	else:
		main.player_saffron_used_this_turn = true
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var all_p: Array = []
	if active != null:
		all_p.append(active)
	all_p.append_array(bench)

	var eligible: Array = []
	for p in all_p:
		if not ("Sabrina" in p.metadata.get("name", "")):
			continue
		for e in p.attached_energies:
			if main.is_basic_energy_card(e):
				eligible.append(p)
				break

	if eligible.size() == 0:
		if not is_opponent:
			await main.show_message("NO SABRINA POKEMON WITH BASIC ENERGY!")
		return

	var target: card_object = null
	var energy_to_return: card_object = null
	if is_opponent:
		# CPU: pick the pokemon with the most excess energy (least likely to need it)
		var most_excess = -1
		for p in eligible:
			var basics = 0
			for e in p.attached_energies:
				if main.is_basic_energy_card(e):
					basics += 1
			if basics > most_excess:
				most_excess = basics
				target = p
		if target == null:
			return
		# Pick first basic energy
		for e in target.attached_energies:
			if main.is_basic_energy_card(e):
				energy_to_return = e
				break
	else:
		target = await main.card_ops.prompt_select_card(eligible, "SAFFRON CITY GYM", "Choose a Sabrina Pokemon to return 1 basic Energy from", "SELECT", true)
		if main._should_bail(): return
		if target == null:
			return

		# Player picks which basic energy to return
		var basic_energies: Array = []
		for e in target.attached_energies:
			if main.is_basic_energy_card(e):
				basic_energies.append(e)
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(basic_energies)
		main.header_label.text = "CHOOSE ENERGY TO RETURN"
		main.hint_label.text = "Select a basic Energy to return to your hand"
		main.action_button.text = "RETURN"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_return = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		if energy_to_return == null:
			return

	# Move energy from attached_energies back to hand
	target.attached_energies.erase(energy_to_return)
	energy_to_return.current_location = "hand"
	hand.append(energy_to_return)
	main.display_active_pokemon_energies(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("SAFFRON CITY GYM: RETURNED 1 ENERGY FROM " + target.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

######################################################################################################################################################
############################################################## BASEP TRAINER EFFECTS ###############################################################
######################################################################################################################################################

# basep-16 Computer Error (Rocket's Secret Machine): both players may draw up to 5 cards; turn ends
func effect_computer_error(is_opponent: bool) -> void:
	# Playing player draws up to 5
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var draw_count = min(5, own_deck.size())
	if draw_count > 0:
		await main.card_ops.draw_n(is_opponent, draw_count)
		if main._should_bail(): return
		await main.show_message(("OPPONENT" if is_opponent else "YOU") + " DREW " + str(draw_count) + " CARD(S)!")
		if main._should_bail(): return
	# Opponent draws up to 5
	var opp_is = not is_opponent
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	var opp_draw = min(5, opp_deck.size())
	if opp_draw > 0:
		await main.card_ops.draw_n(opp_is, opp_draw)
		if main._should_bail(): return
		await main.show_message(("YOU" if is_opponent else "OPPONENT") + " DREW " + str(opp_draw) + " CARD(S)!")
		if main._should_bail(): return
	await main.show_message("COMPUTER ERROR! TURN ENDS!")
	if main._should_bail(): return
	# Signal turn-end: playing side cannot attack this turn
	if is_opponent:
		main.opponent_turn_force_end = true
	else:
		main.player_turn_force_end = true
	print("TRAINER EFFECT: Computer Error - turn force-ended")

######################################################################################################################################################
############################################################## BASEP STADIUM EFFECTS ###############################################################
######################################################################################################################################################

# LUCKY STADIUM (basep-41): per-turn flip — heads draws 1 card (offered via power menu as synthetic entry)
func basep_lucky_stadium_has_target(is_opponent: bool) -> bool:
	if main.current_stadium_card == null:
		return false
	if is_opponent and main.opponent_lucky_stadium_used_this_turn: return false
	if not is_opponent and main.player_lucky_stadium_used_this_turn: return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.LUCKY_STADIUM

func basep_lucky_stadium_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_lucky_stadium_used_this_turn = true
	else:
		main.player_lucky_stadium_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.card_ops.draw_n(is_opponent, 1)
		if main._should_bail(): return
		await main.show_message("LUCKY STADIUM! HEADS — DREW 1 CARD!")
	else:
		await main.show_message("LUCKY STADIUM! TAILS — NO DRAW!")
	if main._should_bail(): return
	print("STADIUM: Lucky Stadium - ", "heads" if coin else "tails")

# POKEMON TOWER (basep-42): block recovery from discard pile to hand
# Returns true if recovery should be blocked
func check_pokemon_tower_blocks_recovery() -> bool:
	if main.current_stadium_card == null:
		return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.POKEMON_TOWER

######################################################################################################################################################
############################################################## NEO1 (NEO GENESIS) TRAINER EFFECTS ###################################################
######################################################################################################################################################

# HELPER: Attach a Pokemon Tool to a chosen Pokemon (checks for existing tool)
func neo1_attach_tool(card: card_object, is_opponent: bool, eligibility_filter: Callable = Callable()) -> void:
	var targets = build_field_pokemon_array(is_opponent)
	# Filter out pokemon that already have a tool attached
	var valid_targets: Array = []
	for p in targets:
		if eligibility_filter.is_valid() and not eligibility_filter.call(p):
			continue
		var has_tool = false
		for ac in p.attached_cards:
			if is_attached_trainer(ac) and (ac.uid.to_lower() in ["neo1-86","neo1-93","neo1-94","neo1-99","neo3-60","neo4-93","neo4-97","neo4-101","gym1-99","gym1-117","gym2-101","gym2-115","ecard1-150"] or "Pokémon Tool" in ac.metadata.get("subtypes", [])):
				has_tool = true
				break
		if not has_tool:
			valid_targets.append(p)
	if valid_targets.size() == 0:
		await main.show_message("ALL POKEMON ALREADY HAVE A TOOL ATTACHED!")
		if main._should_bail(): return
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard.append(card)
		return
	var target: card_object = null
	if is_opponent:
		# CPU: attach to active if no tool, otherwise bench
		target = valid_targets[0]
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(valid_targets, "ATTACH " + card.metadata.get("name",""), "Choose a Pokemon to attach " + card.metadata.get("name","") + " to", "ATTACH", false)
		if main._should_bail(): return
	if target == null:
		var discard2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard2.append(card)
		return
	target.attached_cards.append(card)
	# ISSUE #236: this is the generic tool attach - Focus Band, Berry, Gold Berry,
	# Strength Charm, Cessation Crystal, every ecard2/ex Pokemon Tool - and it flew
	# every one of them to the ACTIVE Pokemon's tool container regardless of what
	# they had been attached to. main.animate_attach_to_pokemon aims at whichever
	# Pokemon actually received it.
	var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	await main.animate_attach_to_pokemon(card, target, is_opponent, hand_node)
	display_attached_trainer_cards(is_opponent)
	# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
	# display_attached_trainer_cards (which only rebuilds the Active's stack).
	main.display_pokemon(is_opponent)
	# ISSUE #249: the board shows the attachment BEFORE the line describing it.
	main.display_pokemon(is_opponent)
	await main.show_message(card.metadata.get("name","").to_upper() + " ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("TRAINER: ", card.metadata.get("name",""), " attached to ", target.metadata.get("name",""))

# ARCADE GAME (neo1-83): Shuffle deck, reveal top 3 — if 2+ share name, take matching; otherwise shuffle all back
func effect_neo1_arcade_game(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	if deck.size() < 2:
		await main.show_message("ARCADE GAME: NOT ENOUGH CARDS IN DECK!")
		if main._should_bail(): return
		return
	var reveal_count = min(3, deck.size())
	var revealed: Array = []
	for i in range(reveal_count):
		revealed.append(deck[i])
	await main.show_message("ARCADE GAME: REVEALED " + str(reveal_count) + " CARDS!")
	if main._should_bail(): return
	# Check if 2+ share the same name
	var name_counts: Dictionary = {}
	for c in revealed:
		var n = c.metadata.get("name","")
		name_counts[n] = name_counts.get(n, 0) + 1
	var match_name = ""
	for n in name_counts:
		if name_counts[n] >= 2:
			match_name = n
			break
	if match_name != "":
		# Take all cards with matching name, shuffle rest back
		var taken: Array = []
		var shuffle_back: Array = []
		for c in revealed:
			if c.metadata.get("name","") == match_name:
				taken.append(c)
			else:
				shuffle_back.append(c)
		for c in taken:
			deck.erase(c)
			c.current_location = "hand"
			hand.append(c)
		for c in shuffle_back:
			pass  # still in deck
		deck.shuffle()
		main.refresh_hand_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("ARCADE GAME: MATCH! TOOK " + str(taken.size()) + " " + match_name.to_upper() + "(S)!")
		if main._should_bail(): return
	else:
		deck.shuffle()
		main.update_deck_icon(is_opponent)
		await main.show_message("ARCADE GAME: NO MATCH! SHUFFLED ALL BACK!")
		if main._should_bail(): return
	print("TRAINER: Arcade Game")

# ENERGY CHARGE (neo1-85): flip coin, heads → shuffle up to 2 energy from discard into deck
func effect_neo1_energy_charge(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY CHARGE: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var energy_cards: Array = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if energy_cards.size() == 0:
		await main.show_message("ENERGY CHARGE: HEADS! BUT NO ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	var picks = min(2, energy_cards.size())
	if is_opponent:
		for i in range(picks):
			var e = energy_cards[i]
			discard.erase(e)
			e.current_location = "deck"
			deck.append(e)
	else:
		for i in range(picks):
			var remaining = energy_cards.filter(func(c): return c in discard)
			if remaining.size() == 0: break
			var pick = await main.card_ops.prompt_select_card(remaining, "ENERGY CHARGE: PICK " + str(i+1) + "/" + str(picks), "Choose an Energy to shuffle into your deck", "SELECT", false)
			if main._should_bail(): return
			if pick != null:
				discard.erase(pick)
				pick.current_location = "deck"
				deck.append(pick)
	deck.shuffle()
	main.update_discard_pile_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ENERGY CHARGE: HEADS! SHUFFLED ENERGY INTO DECK!")
	if main._should_bail(): return
	print("TRAINER: Energy Charge")

# MARY (neo1-87): draw 2 cards, then shuffle 2 cards from hand back into deck
func effect_neo1_mary(is_opponent: bool) -> void:
	await main.card_ops.draw_n(is_opponent, 2)
	if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if hand.size() <= 2:
		for c in hand.duplicate():
			hand.erase(c)
			c.current_location = "deck"
			deck.append(c)
	else:
		var to_return = 2
		for i in range(to_return):
			var remaining = hand.duplicate()
			if remaining.size() == 0: break
			if is_opponent:
				var pick = remaining[remaining.size() - 1]
				hand.erase(pick)
				pick.current_location = "deck"
				deck.append(pick)
			else:
				var pick = await main.card_ops.prompt_select_card(remaining, "MARY: SHUFFLE BACK " + str(i+1) + "/" + str(to_return), "Choose a card to shuffle back into your deck", "SELECT", false)
				if main._should_bail(): return
				if pick != null:
					hand.erase(pick)
					pick.current_location = "deck"
					deck.append(pick)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("MARY: DREW 2 CARDS, SHUFFLED 2 BACK!")
	if main._should_bail(): return
	print("TRAINER: Mary")

# POKEGEAR (neo1-88): look at top 7 — if trainer found, may take 1; can't play more trainers this turn
func effect_neo1_pokegear(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var reveal_count = min(7, deck.size())
	if reveal_count == 0:
		await main.show_message("POKEGEAR: DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var revealed: Array = []
	for i in range(reveal_count):
		revealed.append(deck[i])
	var trainers: Array = revealed.filter(func(c): return c.metadata.get("supertype","") == "Trainer")
	if trainers.size() == 0:
		await main.show_message("POKEGEAR: NO TRAINERS IN TOP " + str(reveal_count) + " CARDS!")
		if main._should_bail(): return
		# Lock trainers
		if is_opponent: opponent_trainer_locked = true
		else: player_trainer_locked = true
		return
	var pick: card_object = null
	if is_opponent:
		pick = main.cpu_ai.cpu_pick_best_keep(trainers)
	else:
		# ISSUE #156: always ask, even with one legal target.
		pick = await main.card_ops.prompt_select_card(trainers, "POKEGEAR: CHOOSE TRAINER", "Choose a Trainer card to take from top 7", "TAKE", true)
		if main._should_bail(): return
	if pick != null:
		deck.erase(pick)
		pick.current_location = "hand"
		hand.append(pick)
		await main.show_message("POKEGEAR: TOOK " + pick.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if is_opponent: opponent_trainer_locked = true
	else: player_trainer_locked = true
	print("TRAINER: PokéGear")

# SUPER ENERGY RETRIEVAL (neo1-89): discard 2 from hand, take up to 4 basic energy from discard
func effect_neo1_super_energy_retrieval(card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var others = hand.filter(func(c): return c != card)
	if others.size() < 2:
		await main.show_message("SUPER ENERGY RETRIEVAL: NEED 2 OTHER CARDS IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	var discarded_count = 0
	if is_opponent:
		var priority = cpu_get_discard_priority(others, 2)
		for c in priority:
			hand.erase(c)
			c.current_location = "discard"
			discard.append(c)
			discarded_count += 1
	else:
		var discarded: Array = await main.card_ops.discard_from_hand(is_opponent, 2, card)
		discarded_count = discarded.size()
	if discarded_count < 2:
		return
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	var basic_energy: Array = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]))
	if basic_energy.size() == 0:
		await main.show_message("SUPER ENERGY RETRIEVAL: NO BASIC ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	var takes = min(4, basic_energy.size())
	if is_opponent:
		for i in range(takes):
			var e = basic_energy[i]
			discard.erase(e)
			e.current_location = "hand"
			hand.append(e)
	else:
		for i in range(takes):
			var remaining = basic_energy.filter(func(c): return c in discard)
			if remaining.size() == 0: break
			var pick = await main.card_ops.prompt_select_card(remaining, "SUPER ENERGY RETRIEVAL: PICK " + str(i+1) + "/" + str(takes), "Choose a basic Energy to take", "SELECT", false)
			if main._should_bail(): return
			if pick != null:
				discard.erase(pick)
				pick.current_location = "hand"
				hand.append(pick)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("SUPER ENERGY RETRIEVAL: TOOK UP TO 4 BASIC ENERGY FROM DISCARD!")
	if main._should_bail(): return
	print("TRAINER: Super Energy Retrieval")

# TIME CAPSULE (neo1-90): both players may recover up to 5 cards from discard to deck; trainer locked
func effect_neo1_time_capsule(is_opponent: bool) -> void:
	# Opponent acts first (if CPU played it) or second (if player played it)
	var sides = [true, false] if is_opponent else [false, true]
	for side in sides:
		var discard = main.opponent_discard_pile if side else main.player_discard_pile
		var deck = main.opponent_deck if side else main.player_deck
		var valid: Array = []
		for c in discard:
			var st = c.metadata.get("supertype","")
			var sub = c.metadata.get("subtypes",[])
			if st == "Pokémon" and ("Basic" in sub or "Stage 1" in sub or "Stage 2" in sub):
				valid.append(c)
			elif st == "Energy" and "Basic" in sub:
				valid.append(c)
		if valid.size() == 0:
			if side == is_opponent:
				await main.show_message("TIME CAPSULE: OPPONENT HAS NO VALID CARDS IN DISCARD!")
			else:
				await main.show_message("TIME CAPSULE: YOU HAVE NO VALID CARDS IN DISCARD!")
			if main._should_bail(): return
			continue
		var picks = min(5, valid.size())
		var chosen: Array = []
		if side == is_opponent:
			# CPU or opponent: pick top cards
			if side:
				for i in range(picks):
					chosen.append(valid[i])
			else:
				chosen = valid.slice(0, picks)
		else:
			if side:
				for i in range(picks):
					chosen.append(valid[i])
			else:
				for i in range(picks):
					var remaining = valid.filter(func(c): return c not in chosen)
					if remaining.size() == 0: break
					var pick = await main.card_ops.prompt_select_card(remaining, "TIME CAPSULE: PICK " + str(i+1) + "/" + str(picks), "Choose a card to shuffle into your deck", "SELECT", true)
					if main._should_bail(): return
					if pick != null:
						chosen.append(pick)
					else:
						break
		for c in chosen:
			discard.erase(c)
			c.current_location = "deck"
			deck.append(c)
		deck.shuffle()
		main.update_discard_pile_display(side)
		main.update_deck_icon(side)
		if chosen.size() > 0:
			await main.show_message("TIME CAPSULE: SHUFFLED " + str(chosen.size()) + " CARD(S) INTO " + ("OPPONENT'S" if side else "YOUR") + " DECK!")
			if main._should_bail(): return
	if is_opponent: opponent_trainer_locked = true
	else: player_trainer_locked = true
	print("TRAINER: Time Capsule")

# BILL'S TELEPORTER (neo1-91): flip — heads draw 4 cards
func effect_neo1_bills_teleporter(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.card_ops.draw_n(is_opponent, 4)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
		await main.show_message("BILL'S TELEPORTER: HEADS! DREW 4 CARDS!")
	else:
		await main.show_message("BILL'S TELEPORTER: TAILS!")
	if main._should_bail(): return
	print("TRAINER: Bill's Teleporter")

# CARD-FLIP GAME (neo1-92): guess a face-down prize type, reveal it, if right draw 2
func effect_neo1_card_flip_game(is_opponent: bool) -> void:
	var prizes = main.opponent_prize_cards if is_opponent else main.player_prize_cards
	if prizes.size() == 0:
		await main.show_message("CARD-FLIP GAME: NO PRIZE CARDS!")
		if main._should_bail(): return
		return
	var types = ["Energy", "Trainer", "Pokemon"]
	var guess_str: String = ""
	if is_opponent:
		guess_str = types[randi() % types.size()]
	else:
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button": child.visible = false; continue
			child.queue_free()
		for i in range(types.size()):
			var btn = Button.new()
			btn.text = types[i]
			btn.custom_minimum_size = Vector2(200, 50)
			btn.theme = main.theme_blue
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		var selected = await main.special_attack_selected
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button": child.visible = true; continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
		guess_str = types[selected]
	# Pick a random face-down prize
	var prize_idx = randi() % prizes.size()
	var prize = prizes[prize_idx]
	var actual_super = prize.metadata.get("supertype", "Pokémon")
	var actual_type: String = "Pokemon"
	if actual_super == "Energy": actual_type = "Energy"
	elif actual_super == "Trainer": actual_type = "Trainer"
	await main.show_message("CARD-FLIP GAME: YOU GUESSED " + guess_str.to_upper() + "! THE PRIZE IS... " + actual_type.to_upper() + "!")
	if main._should_bail(): return
	if guess_str == actual_type:
		await main.card_ops.draw_n(is_opponent, 2)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
		await main.show_message("CORRECT! DREW 2 CARDS!")
	else:
		await main.show_message("WRONG! NO DRAW!")
	if main._should_bail(): return
	print("TRAINER: Card-Flip Game - guess:", guess_str, " actual:", actual_type)

# NEW POKEDEX (neo1-95): shuffle deck, then look at top 5 and rearrange
func effect_neo1_new_pokedex(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	var reveal_count = min(5, deck.size())
	if reveal_count == 0:
		await main.show_message("NEW POKEDEX: DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top_cards: Array = []
	for i in range(reveal_count):
		top_cards.append(deck[i])
	if is_opponent:
		# CPU: sort energy first if needed
		pass  # simple: keep as-is
		await main.show_message("OPPONENT USED NEW POKEDEX TO REARRANGE DECK!")
		if main._should_bail(): return
	else:
		var reordered: Array = []
		var remaining = top_cards.duplicate()
		for pick in range(reveal_count):
			if remaining.size() == 1:
				reordered.append(remaining[0])
				break
			var chosen = await main.card_ops.prompt_select_card(remaining, "NEW POKEDEX: POSITION " + str(pick + 1) + " FROM TOP", "", "PLACE", false)
			if main._should_bail(): return
			if chosen != null:
				reordered.append(chosen)
				remaining.erase(chosen)
		for i in range(reordered.size()):
			deck[i] = reordered[i]
		await main.show_message("NEW POKEDEX: REARRANGED TOP " + str(reveal_count) + " CARDS!")
		if main._should_bail(): return
	print("TRAINER: New Pokédex")

# PROFESSOR ELM (neo1-96): shuffle hand into deck, draw 7, trainer locked
func effect_neo1_professor_elm(card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	for c in hand.duplicate():
		if c == card: continue  # already discarded
		c.current_location = "deck"
		deck.append(c)
	hand.clear()
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("PROFESSOR ELM: SHUFFLED HAND INTO DECK!")
	if main._should_bail(): return
	await main.card_ops.draw_n(is_opponent, 7)
	if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	if is_opponent: opponent_trainer_locked = true
	else: player_trainer_locked = true
	await main.show_message("PROFESSOR ELM: DREW 7 CARDS!")
	if main._should_bail(): return
	print("TRAINER: Professor Elm")

# SUPER SCOOP UP (neo1-98): flip — heads return 1 pokemon + attached to hand
func effect_neo1_super_scoop_up(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("SUPER SCOOP UP: TAILS!")
		if main._should_bail(): return
		return
	var all_poke: Array = []
	if main.opponent_active_pokemon != null and is_opponent: all_poke.append(main.opponent_active_pokemon)
	if main.player_active_pokemon != null and not is_opponent: all_poke.append(main.player_active_pokemon)
	all_poke.append_array(main.opponent_bench if is_opponent else main.player_bench)
	if all_poke.size() == 0:
		await main.show_message("SUPER SCOOP UP: NO POKEMON TO RETURN!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		# CPU: scoop the most-damaged non-active, or active if nothing better
		var bench = main.opponent_bench
		if bench.size() > 0:
			bench.sort_custom(func(a,b): return (a.get_max_hp()-a.current_hp) > (b.get_max_hp()-b.current_hp))
			target = bench[0]
		else:
			target = main.opponent_active_pokemon
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(all_poke, "SUPER SCOOP UP: CHOOSE POKEMON", "Choose a Pokemon to return to hand", "SELECT", false)
		if main._should_bail(): return
	if target == null:
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var bench_ref = main.opponent_bench if is_opponent else main.player_bench
	var is_active = (target == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon))
	# Discard attached energies and pre-evos, return target to hand
	for e in target.attached_energies.duplicate():
		target.attached_energies.erase(e)
		e.current_location = "discard"
		discard.append(e)
	for pre in target.attached_pre_evolutions.duplicate():
		target.attached_pre_evolutions.erase(pre)
		pre.current_location = "discard"
		discard.append(pre)
	for ac in target.attached_cards.duplicate():
		target.attached_cards.erase(ac)
		ac.current_location = "discard"
		discard.append(ac)
	target.current_hp = target.get_max_hp()
	main.clear_all_statuses(target, is_opponent)
	target.pluspower_count = 0
	target.current_location = "hand"
	hand.append(target)
	if is_active:
		if is_opponent: main.opponent_active_pokemon = null
		else: main.player_active_pokemon = null
	else:
		bench_ref.erase(target)
	main.display_pokemon(is_opponent)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("SUPER SCOOP UP! HEADS! " + target.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	if is_active:
		await main.handle_post_knockout(is_opponent)
	print("TRAINER: Super Scoop Up - returned ", target.metadata.get("name",""))

# DOUBLE GUST (neo1-100): opponent switches player's chosen bench with player's active; player switches opponent's chosen bench with opponent's active
func effect_neo1_double_gust(is_opponent: bool) -> void:
	# Step 1: The player who played Double Gust forces the opponent to switch
	var opp_bench_for_gust = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench_for_gust.size() > 0:
		var gust_target: card_object = null
		if is_opponent:
			# CPU chose a bench pokemon from player's side to bring up
			opp_bench_for_gust.sort_custom(func(a,b): return a.current_hp < b.current_hp)
			gust_target = opp_bench_for_gust[0]
		else:
			gust_target = await main.card_ops.prompt_select_card(opp_bench_for_gust, "DOUBLE GUST: CHOOSE OPPONENT'S BENCH", "Choose which opponent bench Pokemon to bring up", "SELECT", false)
			if main._should_bail(): return
		if gust_target != null:
			var old_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
			if is_opponent:
				main.player_bench.erase(gust_target)
				if old_active != null: main.player_bench.append(old_active)
				main.player_active_pokemon = gust_target
			else:
				main.opponent_bench.erase(gust_target)
				if old_active != null: main.opponent_bench.append(old_active)
				main.opponent_active_pokemon = gust_target
			if old_active != null: old_active.current_location = "bench"
			gust_target.current_location = "active"
			main.clear_all_statuses(old_active, not is_opponent)
			main.display_pokemon(not is_opponent)
			await main.show_message("DOUBLE GUST! " + gust_target.metadata.get("name","").to_upper() + " WAS DRAGGED OUT!")
			if main._should_bail(): return
	# Step 2: Now the opponent forces the other player to switch
	var own_bench_for_gust = main.opponent_bench if is_opponent else main.player_bench
	if own_bench_for_gust.size() > 0:
		var gust_target2: card_object = null
		if is_opponent:
			gust_target2 = await main.card_ops.prompt_select_card(own_bench_for_gust, "DOUBLE GUST: OPPONENT CHOOSES YOUR BENCH", "Opponent is choosing which of your bench Pokemon to bring up", "SELECT", false)
			if main._should_bail(): return
		else:
			own_bench_for_gust.sort_custom(func(a,b): return a.current_hp < b.current_hp)
			gust_target2 = own_bench_for_gust[0]
		if gust_target2 != null:
			var old_active2 = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
			if is_opponent:
				main.opponent_bench.erase(gust_target2)
				if old_active2 != null: main.opponent_bench.append(old_active2)
				main.opponent_active_pokemon = gust_target2
			else:
				main.player_bench.erase(gust_target2)
				if old_active2 != null: main.player_bench.append(old_active2)
				main.player_active_pokemon = gust_target2
			if old_active2 != null: old_active2.current_location = "bench"
			gust_target2.current_location = "active"
			main.clear_all_statuses(old_active2, is_opponent)
			main.display_pokemon(is_opponent)
			await main.show_message("DOUBLE GUST! " + gust_target2.metadata.get("name","").to_upper() + " WAS BROUGHT OUT!")
			if main._should_bail(): return
	print("TRAINER: Double Gust")

# MOO-MOO MILK (neo1-101): choose 1 pokemon, flip 2, remove 2 damage counters × heads
func effect_neo1_moo_moo_milk(is_opponent: bool) -> void:
	var all_poke: Array = []
	if main.opponent_active_pokemon != null and is_opponent: all_poke.append(main.opponent_active_pokemon)
	if main.player_active_pokemon != null and not is_opponent: all_poke.append(main.player_active_pokemon)
	all_poke.append_array(main.opponent_bench if is_opponent else main.player_bench)
	var damaged: Array = all_poke.filter(func(p): return p.current_hp < p.get_max_hp())
	if damaged.size() == 0:
		await main.show_message("MOO-MOO MILK: NO DAMAGED POKEMON!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		damaged.sort_custom(func(a,b): return (a.get_max_hp()-a.current_hp) > (b.get_max_hp()-b.current_hp))
		target = damaged[0]
	else:
		if damaged.size() == 1: target = damaged[0]
		else:
			target = await main.card_ops.prompt_select_card(damaged, "MOO-MOO MILK: CHOOSE POKEMON", "Choose a Pokemon to heal", "SELECT", false)
			if main._should_bail(): return
	if target == null: return
	var c1 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var c2 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var heads = (1 if c1 else 0) + (1 if c2 else 0)
	# MATCH EFFECTS: no_healing / healing_multiplier gate
	var heal = main.match_effects.modify_heal_amount(heads * 20, is_opponent)
	if heal > 0:
		target.current_hp = min(target.get_max_hp(), target.current_hp + heal)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(target, is_opponent)
		await main.show_message("MOO-MOO MILK: " + str(heads) + " HEADS — HEALED " + str(heal) + " HP FROM " + target.metadata.get("name","").to_upper() + "!")
	else:
		await main.show_message("MOO-MOO MILK: 0 HEADS — NO HEALING!")
	if main._should_bail(): return
	print("TRAINER: Moo-Moo Milk - healed ", heal)

# POKEMON MARCH (neo1-102): opponent may bench 1 basic, then player may bench 1 basic
func effect_neo1_pokemon_march(is_opponent: bool) -> void:
	var sides = [not is_opponent, is_opponent]  # opponent's side acts first, then player's side
	for side in sides:
		var deck = main.opponent_deck if side else main.player_deck
		var bench = main.opponent_bench if side else main.player_bench
		if bench.size() >= main.get_max_bench_size():
			continue
		var basics: Array = []
		for c in deck:
			if main.is_basic_pokemon(c):
				basics.append(c)
		if basics.size() == 0:
			continue
		var pick: card_object = null
		if side:
			# CPU's side
			pick = main.cpu_ai.cpu_search_deck_for_best_pokemon(basics)
			if pick == null: pick = basics[0]
		else:
			# Player's side
			pick = await main.card_ops.prompt_select_card(basics, "POKEMON MARCH: BENCH A BASIC", "Choose a Basic Pokemon to put on your bench", "SELECT", true, true)
			if main._should_bail(): return
		if pick != null:
			deck.erase(pick)
			pick.current_location = "bench"
			pick.placed_on_field_this_turn = true
			bench.append(pick)
			deck.shuffle()
			main.display_pokemon(side)
			main.update_deck_icon(side)
			await main.show_message("POKEMON MARCH: " + pick.metadata.get("name","").to_upper() + " PLACED ON " + ("OPPONENT'S" if side else "YOUR") + " BENCH!")
			if main._should_bail(): return
	print("TRAINER: Pokémon March")

# SUPER ROD (neo1-103): flip — heads: evolution from discard to hand; tails: basic from discard to hand
func effect_neo1_super_rod(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		var evolutions: Array = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and ("Stage 1" in c.metadata.get("subtypes",[]) or "Stage 2" in c.metadata.get("subtypes",[])))
		if evolutions.size() == 0:
			await main.show_message("SUPER ROD: HEADS! BUT NO EVOLUTION IN DISCARD!")
			if main._should_bail(): return
			return
		var pick: card_object = null
		if is_opponent:
			pick = main.cpu_ai.cpu_pick_best_keep(evolutions)
		else:
			if evolutions.size() == 1: pick = evolutions[0]
			else:
				pick = await main.card_ops.prompt_select_card(evolutions, "SUPER ROD: CHOOSE EVOLUTION", "Choose an Evolution card to take from discard", "SELECT", false)
				if main._should_bail(): return
		if pick != null:
			discard.erase(pick)
			pick.current_location = "hand"
			hand.append(pick)
			main.refresh_hand_display(is_opponent)
			main.update_discard_pile_display(is_opponent)
			await main.show_message("SUPER ROD: HEADS! TOOK " + pick.metadata.get("name","").to_upper() + " FROM DISCARD!")
			if main._should_bail(): return
	else:
		var basics: Array = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]))
		if basics.size() == 0:
			await main.show_message("SUPER ROD: TAILS! BUT NO BASIC IN DISCARD!")
			if main._should_bail(): return
			return
		var pick: card_object = null
		if is_opponent:
			pick = main.cpu_ai.cpu_pick_best_keep(basics)
		else:
			if basics.size() == 1: pick = basics[0]
			else:
				pick = await main.card_ops.prompt_select_card(basics, "SUPER ROD: CHOOSE BASIC", "Choose a Basic Pokemon to take from discard", "SELECT", false)
				if main._should_bail(): return
		if pick != null:
			discard.erase(pick)
			pick.current_location = "hand"
			hand.append(pick)
			main.refresh_hand_display(is_opponent)
			main.update_discard_pile_display(is_opponent)
			await main.show_message("SUPER ROD: TAILS! TOOK " + pick.metadata.get("name","").to_upper() + " FROM DISCARD!")
			if main._should_bail(): return
	print("TRAINER: Super Rod")

######################################################################################################################################################
##################################################### NEO2 (NEO DISCOVERY) TRAINER EFFECTS ##########################################################
######################################################################################################################################################

func _register_neo2_trainers() -> void:
	_trainer_dispatch["neo2-72"] = func(c, opp): await effect_neo2_fossil_egg(opp)
	_trainer_dispatch["neo2-73"] = func(c, opp): await effect_neo2_hyper_devolution_spray(opp)
	_trainer_dispatch["neo2-74"] = func(c, opp): await effect_neo2_ruin_wall(opp)
	_trainer_dispatch["neo2-75"] = func(c, opp): await effect_neo2_energy_ark(opp)

# FOSSIL EGG (neo2-72): flip — if heads, bench a fossil evolution from deck or hand (treated as Basic)
func effect_neo2_fossil_egg(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL! FOSSIL EGG FAILS!")
		if main._should_bail(): return
		return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! FOSSIL EGG FAILS!")
		if main._should_bail(): return
		return
	# Check hand first
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var fossil_filter = func(c: card_object) -> bool:
		return "Mysterious Fossil" in c.metadata.get("evolvesFrom","")
	var hand_fossils = hand.filter(fossil_filter)
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var deck_fossils = deck.filter(fossil_filter)
	if hand_fossils.is_empty() and deck_fossils.is_empty():
		await main.show_message("FOSSIL EGG: NO FOSSIL POKEMON FOUND!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	var from_deck = false
	if not hand_fossils.is_empty():
		if is_opponent:
			chosen = hand_fossils[0]
		else:
			chosen = await main.card_ops.prompt_select_card(hand_fossils, "FOSSIL EGG: FROM HAND", "Choose fossil from hand to bench", "SELECT", false)
			if main._should_bail(): return
	if chosen == null and not deck_fossils.is_empty():
		if is_opponent:
			chosen = deck_fossils[0]
		else:
			chosen = await main.card_ops.prompt_select_card(deck_fossils, "FOSSIL EGG: FROM DECK", "Choose fossil from deck to bench", "SELECT", false)
			if main._should_bail(): return
		from_deck = true
	if chosen == null: return
	if from_deck:
		deck.erase(chosen)
		deck.shuffle()
		main.update_deck_icon(is_opponent)
	else:
		hand.erase(chosen)
	chosen.placed_on_field_this_turn = true
	chosen.current_location = "bench"
	chosen.current_hp = chosen.get_max_hp()
	bench.append(chosen)
	main.display_pokemon(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("FOSSIL EGG! " + chosen.metadata.get("name","").to_upper() + " PLACED ON BENCH AS BASIC!")
	if main._should_bail(): return
	print("TRAINER: Fossil Egg — ", chosen.metadata.get("name",""))

# HYPER DEVOLUTION SPRAY (neo2-73): return highest-stage evolution card from chosen evolved pokemon to hand
func effect_neo2_hyper_devolution_spray(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var evolved: Array = []
	if active != null and active.attached_pre_evolutions.size() > 0:
		evolved.append(active)
	for bp in bench:
		if bp.attached_pre_evolutions.size() > 0:
			evolved.append(bp)
	if evolved.is_empty():
		await main.show_message("NO EVOLVED POKEMON TO USE HYPER DEVOLUTION SPRAY ON!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		target = evolved[0]
	else:
		target = await main.card_ops.prompt_select_card(evolved, "HYPER DEVOLUTION SPRAY", "Choose an evolved Pokemon to devolve", "SELECT", false)
		if main._should_bail(): return
	if target == null: return
	# The card itself IS the top stage — put it in hand, restore the pre-evo
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var pre_evo = target.attached_pre_evolutions.back()
	# Move energy and attached cards to the pre-evo
	for e in target.attached_energies.duplicate():
		target.attached_energies.erase(e)
		pre_evo.attached_energies.append(e)
	for c in target.attached_cards.duplicate():
		target.attached_cards.erase(c)
		pre_evo.attached_cards.append(c)
	pre_evo.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	pre_evo.attached_pre_evolutions.erase(pre_evo)
	target.attached_pre_evolutions.clear()
	target.attached_energies.clear()
	target.attached_cards.clear()
	pre_evo.placed_on_field_this_turn = true
	pre_evo.current_location = target.current_location
	if target.current_location == "active":
		if is_opponent:
			main.opponent_active_pokemon = pre_evo
		else:
			main.player_active_pokemon = pre_evo
	else:
		bench.erase(target)
		bench.append(pre_evo)
	target.current_location = "hand"
	hand.append(target)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("HYPER DEVOLUTION SPRAY! " + target.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Hyper Devolution Spray — devolved ", target.metadata.get("name",""))

# RUIN WALL (neo2-74): search deck for an Unown, put it on bench
func effect_neo2_ruin_wall(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("RUIN WALL: BENCH IS FULL!")
		if main._should_bail(): return
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Unown" in c.metadata.get("name","") and main.is_basic_pokemon(c), "RUIN WALL: CHOOSE AN UNOWN FROM DECK", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("RUIN WALL: NO UNOWN FOUND IN DECK!")
		if main._should_bail(): return
		return
	var unown = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(unown)
	var placed = main.card_ops.place_on_bench(unown, is_opponent)
	if placed:
		await main.show_message("RUIN WALL! " + unown.metadata.get("name","").to_upper() + " PLACED ON BENCH!")
		if main._should_bail(): return
	print("TRAINER: Ruin Wall — ", unown.metadata.get("name",""))

# ENERGY ARK (neo2-75): flip 2 — for each heads, search deck for a Basic Energy card to hand
func effect_neo2_energy_ark(is_opponent: bool) -> void:
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent):
			heads += 1
	if main._should_bail(): return
	if heads == 0:
		await main.show_message("ENERGY ARK: 0 HEADS — NO ENERGY!")
		if main._should_bail(): return
		return
	await main.show_message("ENERGY ARK: " + str(heads) + " HEADS — SEARCHING FOR " + str(heads) + " BASIC ENERGY!")
	if main._should_bail(): return
	for i in range(heads):
		var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]), "ENERGY ARK: CHOOSE BASIC ENERGY " + str(i+1), 1)
		if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	await main.show_message("ENERGY ARK! " + str(heads) + " BASIC ENERGY ADDED TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Energy Ark — ", heads, " energy retrieved")

######################################################################################################################################################
######################################################## NEO3 (NEO REVELATION) TRAINER EFFECTS #######################################################
######################################################################################################################################################

func _register_neo3_trainers() -> void:
	# neo3-60 Balloon Berry is a Tool — handled by resolve_attached_trainer
	# neo3-61 Healing Field is a Stadium — handled by resolve_stadium_trainer + neo3_healing_field_activate
	# neo3-62 Pokemon Breeder Fields
	_trainer_dispatch["neo3-62"] = func(c, opp): await effect_neo3_pokemon_breeder_fields(c, opp)
	# neo3-63 Rocket's Hideout is a Stadium — handled by resolve_stadium_trainer
	# neo3-64 Old Rod
	_trainer_dispatch["neo3-64"] = func(c, opp): await effect_neo3_old_rod(c, opp)

# ── Tool attachment helper shared with neo3 tools ────────────────────────────

# Attach a neo3 Pokemon Tool to a chosen Pokemon (one tool per pokemon; same as neo1_attach_tool)
func neo3_attach_tool(card: card_object, is_opponent: bool) -> void:
	var targets = build_field_pokemon_array(is_opponent)
	var valid_targets: Array = []
	for p in targets:
		var has_tool = false
		for ac in p.attached_cards:
			if is_attached_trainer(ac) and (ac.uid.to_lower() in ["neo1-86","neo1-93","neo1-94","neo1-99","neo3-60","neo4-93","neo4-97","neo4-101","gym1-99","gym1-117","gym2-101","gym2-115","ecard1-150"] or "Pokémon Tool" in ac.metadata.get("subtypes", [])):
				has_tool = true
				break
		if not has_tool:
			valid_targets.append(p)
	if valid_targets.size() == 0:
		await main.show_message("ALL POKEMON ALREADY HAVE A TOOL ATTACHED!")
		if main._should_bail(): return
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard.append(card)
		return
	var target: card_object = null
	if is_opponent:
		target = valid_targets[0]
	else:
		# ISSUE #156: always ask, even with one legal target.
		target = await main.card_ops.prompt_select_card(valid_targets, "ATTACH " + card.metadata.get("name",""), "Choose a Pokemon to attach " + card.metadata.get("name","") + " to", "ATTACH", false)
		if main._should_bail(): return
	if target == null:
		var discard2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		card.current_location = "discard"
		discard2.append(card)
		return
	target.attached_cards.append(card)
	var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
	# ISSUE #236 (retest): this was one of SIX more sites still flying the card to
	# the ACTIVE Pokemon's tool container whatever it had been attached to.
	# main.animate_attach_to_pokemon aims at the Pokemon that received it.
	await main.animate_attach_to_pokemon(card, target, is_opponent, hand_node)
	display_attached_trainer_cards(is_opponent)
	# ISSUE #236: a BENCH Pokemon's tools are drawn by display_pokemon, not by
	# display_attached_trainer_cards (which only rebuilds the Active's stack).
	main.display_pokemon(is_opponent)
	await main.show_message(card.metadata.get("name","").to_upper() + " ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("TRAINER: ", card.metadata.get("name",""), " attached to ", target.metadata.get("name",""))

# BALLOON BERRY (neo3-60): check if the pokemon with Balloon Berry attached wants to retreat.
# Called from get_retreat_cost() — if this pokemon has a Balloon Berry, its retreat cost is 0.
# The berry is discarded when the pokemon actually retreats (hooked in handle_action_retreat_bench).
func check_balloon_berry_retreat_free(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	for ac in pokemon.attached_cards:
		if ac.uid.to_lower() == "neo3-60" or ac.uid.to_lower() == "ex3-82" or ac.uid.to_lower() == "ex8-84":
			return true
	return false

# Discard Balloon Berry from the given pokemon after a free retreat is used.
func consume_balloon_berry(pokemon: card_object, is_opponent: bool) -> void:
	for ac in pokemon.attached_cards.duplicate():
		if ac.uid.to_lower() == "neo3-60" or ac.uid.to_lower() == "ex3-82" or ac.uid.to_lower() == "ex8-84":
			pokemon.attached_cards.erase(ac)
			var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			ac.current_location = "discard"
			discard.append(ac)
			display_attached_trainer_cards(is_opponent)
			main.update_discard_pile_display(is_opponent)
			print("BALLOON BERRY: consumed for free retreat")
			break

# ── HEALING FIELD (neo3-61) ───────────────────────────────────────────────────

func neo3_healing_field_active(is_opponent: bool = false) -> bool:
	if main.current_stadium_card == null:
		return false
	if is_opponent and main.opponent_healing_field_used_this_turn: return false
	if not is_opponent and main.player_healing_field_used_this_turn: return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.HEALING_FIELD

func neo3_healing_field_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_healing_field_used_this_turn = true
	else:
		main.player_healing_field_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		if active != null:
			var healed = min(20, active.get_max_hp() - active.current_hp)
			active.current_hp = min(active.get_max_hp(), active.current_hp + 20)
			main.display_hp_circles_above_align(active, is_opponent)
			await main.show_message("HEALING FIELD! HEADS! REMOVED 2 DAMAGE COUNTERS FROM " + active.metadata.get("name","").to_upper() + "!")
		else:
			await main.show_message("HEALING FIELD! HEADS! BUT NO ACTIVE POKEMON!")
	else:
		await main.show_message("HEALING FIELD! TAILS — NO HEALING!")
	if main._should_bail(): return
	print("STADIUM: Healing Field - ", "heads" if coin else "tails")

# ── POKEMON BREEDER FIELDS (neo3-62) ─────────────────────────────────────────

# For each Basic Pokemon on your bench, flip; heads = search deck for its Evolution and put in hand
func effect_neo3_pokemon_breeder_fields(card: card_object, is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	card.current_location = "discard"
	discard.append(card)
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var own_hand = main.opponent_hand if is_opponent else main.player_hand
	var basic_bench: Array = []
	for bp in own_bench:
		if "Basic" in bp.metadata.get("subtypes",[]):
			basic_bench.append(bp)
	if basic_bench.is_empty():
		await main.show_message("POKEMON BREEDER FIELDS: NO BASIC POKEMON ON BENCH!")
		if main._should_bail(): return
		return
	var searched = 0
	for bp in basic_bench:
		var coin = await main.flip_coin(true, is_opponent)
		if main._should_bail(): return
		if not coin:
			await main.show_message("TAILS FOR " + bp.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
			continue
		var evo_name = bp.metadata.get("evolvesTo", [])
		if evo_name.is_empty():
			await main.show_message("HEADS FOR " + bp.metadata.get("name","").to_upper() + " BUT NO EVOLUTION!")
			if main._should_bail(): return
			continue
		var first_evo = evo_name[0]
		var found_card: card_object = null
		for c in own_deck:
			if c.metadata.get("name","") == first_evo:
				found_card = c
				break
		if found_card == null:
			await main.show_message("HEADS! BUT " + first_evo.to_upper() + " NOT IN DECK!")
			if main._should_bail(): return
			continue
		own_deck.erase(found_card)
		found_card.current_location = "hand"
		own_hand.append(found_card)
		searched += 1
		await main.show_message("POKEMON BREEDER FIELDS! " + first_evo.to_upper() + " ADDED TO HAND!")
		if main._should_bail(): return
	own_deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.refresh_hand_display(is_opponent)
	if searched == 0:
		await main.show_message("POKEMON BREEDER FIELDS: NO EVOLUTIONS FOUND!")
	else:
		await main.show_message("POKEMON BREEDER FIELDS: " + str(searched) + " EVOLUTION(S) RETRIEVED!")
	if main._should_bail(): return
	print("TRAINER: Pokemon Breeder Fields — ", searched, " evolutions retrieved")

# ── ROCKET'S HIDEOUT (neo3-63) ────────────────────────────────────────────────

# Called from get_retreat_cost / calculate_final_damage hooks (if using StadiumIds.ROCKETS_HIDEOUT):
# Pokemon with "Dark" in name get +20 HP (handled via a max_hp_override or the calculate_final_damage hook).
# This function applies the +20 HP override to all "Dark"-named pokemon in play if Rocket's Hideout enters.
# Also called at start of check to see if a pokemon qualifies.
func rockets_hideout_bonus_hp(pokemon: card_object) -> int:
	var pname = pokemon.metadata.get("name","")
	# neo3-63 Rocket's Hideout: "Dark"-named only.
	if main.is_stadium_in_play(StadiumIds.ROCKETS_HIDEOUT) and "Dark" in pname:
		return 20
	# ex7-87 Rocket's Hideout: "Dark" OR "Rocket's" in name.
	if main.is_stadium_in_play(StadiumIds.ROCKETS_HIDEOUT_EX7) and ("Dark" in pname or "Rocket's" in pname):
		return 20
	return 0

# ── OLD ROD (neo3-64) ────────────────────────────────────────────────────────

# Flip 2 coins: both heads = choose 1 Pokemon from discard to hand; both tails = choose 1 Trainer from discard to hand
func effect_neo3_old_rod(card: card_object, is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	card.current_location = "discard"
	discard.append(card)
	var coin1 = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	var coin2 = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	var own_hand = main.opponent_hand if is_opponent else main.player_hand
	if coin1 and coin2:
		# Both heads: recover 1 Pokemon from discard to hand
		var pokemon_in_discard: Array = []
		for c in discard:
			if c.metadata.get("supertype","") == "Pokémon" and c != card:
				pokemon_in_discard.append(c)
		if pokemon_in_discard.is_empty():
			await main.show_message("OLD ROD: BOTH HEADS! BUT NO POKEMON IN DISCARD!")
			if main._should_bail(): return
			return
		var chosen: card_object = null
		if is_opponent:
			chosen = pokemon_in_discard[0]
		else:
			chosen = await main.card_ops.prompt_select_card(pokemon_in_discard, "OLD ROD!", "BOTH HEADS! Choose a Pokemon from your discard to put in your hand", "RETRIEVE", false)
			if main._should_bail(): return
			if chosen == null: chosen = pokemon_in_discard[0]
		discard.erase(chosen)
		chosen.current_location = "hand"
		own_hand.append(chosen)
		main.update_discard_pile_display(is_opponent)
		main.refresh_hand_display(is_opponent)
		await main.show_message("OLD ROD! BOTH HEADS! " + chosen.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
		if main._should_bail(): return
	elif not coin1 and not coin2:
		# Both tails: recover 1 Trainer from discard to hand
		var trainers_in_discard: Array = []
		for c in discard:
			if c.metadata.get("supertype","") == "Trainer" and c != card:
				trainers_in_discard.append(c)
		if trainers_in_discard.is_empty():
			await main.show_message("OLD ROD: BOTH TAILS! BUT NO TRAINER IN DISCARD!")
			if main._should_bail(): return
			return
		var chosen_t: card_object = null
		if is_opponent:
			chosen_t = trainers_in_discard[0]
		else:
			chosen_t = await main.card_ops.prompt_select_card(trainers_in_discard, "OLD ROD!", "BOTH TAILS! Choose a Trainer from your discard to put in your hand", "RETRIEVE", false)
			if main._should_bail(): return
			if chosen_t == null: chosen_t = trainers_in_discard[0]
		discard.erase(chosen_t)
		chosen_t.current_location = "hand"
		own_hand.append(chosen_t)
		main.update_discard_pile_display(is_opponent)
		main.refresh_hand_display(is_opponent)
		await main.show_message("OLD ROD! BOTH TAILS! " + chosen_t.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
		if main._should_bail(): return
	else:
		await main.show_message("OLD ROD: 1 HEAD, 1 TAIL — NO EFFECT!")
		if main._should_bail(): return
	print("TRAINER: Old Rod — coin1=", coin1, " coin2=", coin2)

######################################################################################################################################################
############################################################## NEO4 (NEO DESTINY) TRAINER EFFECTS ###################################################
######################################################################################################################################################

func _register_neo4_trainers() -> void:
	# Stadiums (neo4-92 Broken Ground Gym, neo4-95 Radio Tower, neo4-99 Energy Stadium, neo4-100 Lucky Stadium)
	#   are handled via resolve_stadium_trainer; per-turn effects via power menu (Radio Tower/Energy Stadium/Lucky Stadium).
	# Tools (neo4-93 EXP.ALL, neo4-97 Counterattack Claws, neo4-101 Magnifier) handled via resolve_attached_trainer.
	_trainer_dispatch["neo4-94"]  = func(c, opp): await effect_neo4_impostor_oaks_invention(opp)
	_trainer_dispatch["neo4-96"]  = func(c, opp): await effect_neo4_thought_wave_machine(opp)
	_trainer_dispatch["neo4-98"]  = func(c, opp): await effect_neo4_energy_amplifier(c, opp)
	_trainer_dispatch["neo4-102"] = func(c, opp): await effect_neo4_personality_test(opp)
	_trainer_dispatch["neo4-103"] = func(c, opp): await effect_neo4_evil_deeds(opp)
	_trainer_dispatch["neo4-104"] = func(c, opp): await effect_neo4_heal_powder(opp)
	_trainer_dispatch["neo4-105"] = func(c, opp): await effect_neo4_mail_from_bill(opp)

# IMPOSTOR PROFESSOR OAK'S INVENTION (neo4-94): look at opp prizes; may shuffle into deck and re-draw new prizes
func effect_neo4_impostor_oaks_invention(is_opponent: bool) -> void:
	var opp_prizes = main.player_prize_cards if is_opponent else main.opponent_prize_cards
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	var n = opp_prizes.size()
	if n == 0:
		await main.show_message("IMPOSTOR OAK'S INVENTION: OPPONENT HAS NO PRIZES!")
		if main._should_bail(): return
		return
	# Shuffle opponent's prizes into their deck
	for p in opp_prizes.duplicate():
		p.current_location = "deck"
		opp_deck.append(p)
	opp_prizes.clear()
	opp_deck.shuffle()
	# Re-draw the same number of new prizes off the top
	for i in range(n):
		if opp_deck.is_empty(): break
		var c = opp_deck.pop_front()
		c.current_location = "prize"
		opp_prizes.append(c)
	main.update_deck_icon(not is_opponent)
	if main.has_method("display_prize_cards"):
		main.display_prize_cards(not is_opponent)
	await main.show_message("IMPOSTOR OAK'S INVENTION! OPPONENT'S PRIZES WERE SHUFFLED AND RE-DEALT!")
	if main._should_bail(): return
	print("TRAINER: Impostor Professor Oak's Invention — ", n, " prizes re-dealt")

# THOUGHT WAVE MACHINE (neo4-96): flip until tails; per head return an Energy from opp Active to opp hand; turn ends
func effect_neo4_thought_wave_machine(is_opponent: bool) -> void:
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var heads = 0
	while true:
		var coin = await main.flip_coin(true, is_opponent)
		if main._should_bail(): return
		if coin:
			heads += 1
		else:
			break
	var returned = 0
	if opp_active != null:
		for i in range(heads):
			if opp_active.attached_energies.is_empty(): break
			var e = opp_active.attached_energies.pop_back()
			e.current_location = "hand"
			opp_hand.append(e)
			returned += 1
		main.display_active_pokemon_energies(not is_opponent)
		main.refresh_hand_display(not is_opponent)
	await main.show_message("THOUGHT WAVE MACHINE! " + str(heads) + " HEADS — RETURNED " + str(returned) + " ENERGY! YOUR TURN IS OVER!")
	if main._should_bail(): return
	# End turn (Rocket's Secret Machine: you don't get to attack)
	if is_opponent:
		main.opponent_attacked_this_turn = true
	else:
		main.player_attacked_this_turn = true
		main.player_end_turn_checks()
	print("TRAINER: Thought Wave Machine — ", returned, " energy returned")

# ENERGY AMPLIFIER (neo4-98): shuffle an Energy from hand into deck; flip heads search up to 3 basic Energy to hand
func effect_neo4_energy_amplifier(card: card_object, is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var energy_in_hand: Array = []
	for c in hand:
		if c.metadata.get("supertype","") == "Energy":
			energy_in_hand.append(c)
	if energy_in_hand.is_empty():
		await main.show_message("ENERGY AMPLIFIER: NO ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var to_shuffle: card_object = energy_in_hand[0]
	if not is_opponent:
		to_shuffle = await main.card_ops.prompt_select_card(energy_in_hand, "ENERGY AMPLIFIER", "Choose an Energy to shuffle into your deck", "SELECT", false)
		if main._should_bail(): return
		if to_shuffle == null: to_shuffle = energy_in_hand[0]
	hand.erase(to_shuffle)
	to_shuffle.current_location = "deck"
	deck.append(to_shuffle)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY AMPLIFIER: TAILS — NO SEARCH!")
		if main._should_bail(): return
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]), "ENERGY AMPLIFIER: choose up to 3 basic Energy", 3)
	if main._should_bail(): return
	await main.show_message("ENERGY AMPLIFIER! HEADS — FOUND " + str(found.size()) + " BASIC ENERGY!")
	if main._should_bail(): return
	print("TRAINER: Energy Amplifier — ", found.size(), " energy to hand")

# POKEMON PERSONALITY TEST (neo4-102): guessing game (simplified to a coin flip outcome)
func effect_neo4_personality_test(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var has_evo = false
	for c in hand:
		if c.metadata.get("supertype","") == "Pokémon" and ("Stage 1" in c.metadata.get("subtypes",[]) or "Stage 2" in c.metadata.get("subtypes",[])):
			has_evo = true
			break
	if not has_evo:
		await main.show_message("POKEMON PERSONALITY TEST: NO EVOLUTION CARD IN HAND!")
		if main._should_bail(): return
		return
	# Opponent guesses; simplified as a coin flip (heads = opponent guessed right → opponent draws 3; tails = you draw 3)
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.card_ops.draw_n(not is_opponent, 3)
		await main.show_message("POKEMON PERSONALITY TEST! OPPONENT GUESSED RIGHT — THEY DREW 3 CARDS!")
	else:
		await main.card_ops.draw_n(is_opponent, 3)
		await main.show_message("POKEMON PERSONALITY TEST! OPPONENT GUESSED WRONG — YOU DREW 3 CARDS!")
	if main._should_bail(): return
	print("TRAINER: Pokemon Personality Test — heads=", coin)

# TEAM ROCKET'S EVIL DEEDS (neo4-103): choose a card from opp hand, shuffle into deck; opp may draw up to 2
func effect_neo4_evil_deeds(is_opponent: bool) -> void:
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_hand.is_empty():
		await main.show_message("TEAM ROCKET'S EVIL DEEDS: OPPONENT'S HAND IS EMPTY!")
		if main._should_bail(): return
		return
	var chosen: card_object = opp_hand[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(opp_hand.duplicate(), "TEAM ROCKET'S EVIL DEEDS", "Choose a card from opponent's hand to shuffle into their deck", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = opp_hand[0]
	opp_hand.erase(chosen)
	chosen.current_location = "deck"
	opp_deck.append(chosen)
	opp_deck.shuffle()
	main.update_deck_icon(not is_opponent)
	main.refresh_hand_display(not is_opponent)
	await main.card_ops.draw_n(not is_opponent, 2)
	if main._should_bail(): return
	await main.show_message("TEAM ROCKET'S EVIL DEEDS! A CARD WAS SHUFFLED AWAY; OPPONENT DREW 2!")
	if main._should_bail(): return
	print("TRAINER: Team Rocket's Evil Deeds")

# HEAL POWDER (neo4-104): flip heads, Active no longer statused + remove 2 damage counters
func effect_neo4_heal_powder(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null:
		await main.show_message("HEAL POWDER: NO ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("HEAL POWDER: TAILS — NO EFFECT!")
		if main._should_bail(): return
		return
	main.clear_all_statuses(active, is_opponent)
	var heal = min(20, active.get_max_hp() - active.current_hp)
	active.current_hp += heal
	main.display_hp_circles_above_align(active, is_opponent)
	await main.show_message("HEAL POWDER! HEADS! " + active.metadata.get("name","").to_upper() + " HEALED AND CURED!")
	if main._should_bail(): return
	print("TRAINER: Heal Powder")

# MAIL FROM BILL (neo4-105): draw until you have 4 cards in hand (can't play with 5+)
func effect_neo4_mail_from_bill(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var needed = 4 - hand.size()
	if needed <= 0:
		await main.show_message("MAIL FROM BILL: HAND ALREADY HAS 4 OR MORE CARDS!")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, needed)
	if main._should_bail(): return
	await main.show_message("MAIL FROM BILL! DREW UP TO 4 CARDS!")
	if main._should_bail(): return
	print("TRAINER: Mail from Bill — drew ", needed)

# ── NEO4 STADIUM PER-TURN EFFECTS ─────────────────────────────────────────────

# RADIO TOWER (neo4-95): once per turn, look at top 2 of deck and put them back in the same order
func neo4_radio_tower_active() -> bool:
	if main.current_stadium_card == null:
		return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.RADIO_TOWER

func neo4_radio_tower_activate(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if deck.is_empty():
		await main.show_message("RADIO TOWER: DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var names: Array = []
	for i in range(min(2, deck.size())):
		names.append(deck[i].metadata.get("name",""))
	await main.show_message("RADIO TOWER! TOP CARDS: " + ", ".join(names).to_upper())
	if main._should_bail(): return
	print("STADIUM: Radio Tower — viewed top 2")

# ENERGY STADIUM (neo4-99): once per turn, flip; heads put a basic Energy from discard to hand
func neo4_energy_stadium_active() -> bool:
	if main.current_stadium_card == null:
		return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.ENERGY_STADIUM

func neo4_energy_stadium_activate(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY STADIUM! TAILS — NO ENERGY!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics: Array = []
	for c in discard:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basics.append(c)
	if basics.is_empty():
		await main.show_message("ENERGY STADIUM! HEADS — BUT NO BASIC ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = main.cpu_ai.cpu_pick_best_keep(basics) if is_opponent else basics[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(basics, "ENERGY STADIUM!", "Choose a basic Energy from your discard to put in your hand", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = basics[0]
	discard.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("ENERGY STADIUM! HEADS — " + chosen.metadata.get("name","").to_upper() + " ADDED TO HAND!")
	if main._should_bail(): return
	print("STADIUM: Energy Stadium — basic energy recovered")

# LUCKY STADIUM (neo4-100): once per turn, flip; heads draw a card
func neo4_lucky_stadium_active() -> bool:
	if main.current_stadium_card == null:
		return false
	return main.current_stadium_card.uid.to_lower() == StadiumIds.NEO4_LUCKY_STADIUM

func neo4_lucky_stadium_activate(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.card_ops.draw_n(is_opponent, 1)
		if main._should_bail(): return
		await main.show_message("LUCKY STADIUM! HEADS — DREW 1 CARD!")
	else:
		await main.show_message("LUCKY STADIUM! TAILS — NO DRAW!")
	if main._should_bail(): return
	print("STADIUM: Lucky Stadium (neo4) - ", "heads" if coin else "tails")

######################################################################################################################################################
######################################################## NP (NINTENDO PROMOS) TRAINER EFFECTS #########################################################
######################################################################################################################################################

func _register_np_trainers() -> void:
	_trainer_dispatch["np-26"]  = func(c, opp): await effect_np_tropical_wind(opp)
	_trainer_dispatch["np-27"]  = func(c, opp): await effect_np_tropical_tidal_wave(opp)
	_trainer_dispatch["np-36"]  = func(c, opp): await effect_np_tropical_tidal_wave(opp)
	# np-28 Championship Arena is a Stadium — handled via resolve_stadium_trainer

# TROPICAL WIND (np-26): flip; heads remove 2 damage counters from each Active (min 1 if only 1), tails each Active is now Asleep
func effect_np_tropical_wind(is_opponent: bool) -> void:
	await main.show_message("TROPICAL WIND!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		# Heal each Active pokemon by 2 damage counters (20 HP), but if they only have 1 counter heal only 1
		for side in [false, true]:
			var active = main.opponent_active_pokemon if side else main.player_active_pokemon
			if active == null: continue
			var max_hp = active.get_max_hp()
			var counters = active.get_damage_counters()
			var heal = min(2, counters) * 10
			if heal > 0:
				active.current_hp = min(max_hp, active.current_hp + heal)
				main.display_hp_circles_above_align(active, side)
		await main.show_message("TROPICAL WIND! HEADS — BOTH ACTIVE POKÉMON RECOVER UP TO 20 HP!")
		if main._should_bail(): return
	else:
		for side in [false, true]:
			var active = main.opponent_active_pokemon if side else main.player_active_pokemon
			if active == null: continue
			main.card_ops.apply_status(active, "Asleep", side)
		main.update_status_icons(main.player_active_pokemon, false)
		main.update_status_icons(main.opponent_active_pokemon, true)
		await main.show_message("TROPICAL WIND! TAILS — BOTH ACTIVE POKÉMON ARE NOW ASLEEP!")
		if main._should_bail(): return
	main.display_pokemon(false)
	main.display_pokemon(true)
	print("TRAINER: Tropical Wind - ", "heads (heal)" if coin else "tails (sleep)")

# TROPICAL TIDAL WAVE (np-27/np-36): flip; heads discard all opponent's Trainers in play,
# tails discard all your own (non-supporter) Trainers in play. Effectively targets the Stadium.
func effect_np_tropical_tidal_wave(is_opponent: bool) -> void:
	await main.show_message("TROPICAL TIDAL WAVE!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		if main.current_stadium_card != null and main.current_stadium_owner_is_opponent != is_opponent:
			var sname = main.current_stadium_card.metadata.get("name","").to_upper()
			remove_current_stadium("Tropical Tidal Wave (heads)")
			await main.show_message("TROPICAL TIDAL WAVE! HEADS — " + sname + " DISCARDED!")
		else:
			await main.show_message("TROPICAL TIDAL WAVE! HEADS — OPPONENT HAS NO TRAINERS IN PLAY!")
	else:
		if main.current_stadium_card != null and main.current_stadium_owner_is_opponent == is_opponent:
			var sname = main.current_stadium_card.metadata.get("name","").to_upper()
			remove_current_stadium("Tropical Tidal Wave (tails)")
			await main.show_message("TROPICAL TIDAL WAVE! TAILS — YOUR " + sname + " WAS DISCARDED!")
		else:
			await main.show_message("TROPICAL TIDAL WAVE! TAILS — YOU HAVE NO TRAINERS IN PLAY!")
	if main._should_bail(): return
	print("TRAINER: Tropical Tidal Wave - ", "heads" if coin else "tails")

# CHAMPIONSHIP ARENA (np-28 Stadium): at end of each player's turn, if that player has 8+ cards
# in hand, they discard down to 7.
func np_championship_arena_check(player_turn_just_ended: bool) -> void:
	if main.current_stadium_card == null: return
	if main.current_stadium_card.uid.to_lower() != StadiumIds.CHAMPIONSHIP_ARENA: return
	# The side whose turn just ended must discard if they have 8+ cards
	var is_opponent_side = not player_turn_just_ended  # opponent's turn just ended = true
	var hand = main.opponent_hand if is_opponent_side else main.player_hand
	if hand.size() < 8: return
	var excess = hand.size() - 7
	await main.show_message("CHAMPIONSHIP ARENA! " + ("OPPONENT HAS" if is_opponent_side else "YOU HAVE") + " " + str(hand.size()) + " CARDS — DISCARD " + str(excess) + "!")
	if main._should_bail(): return
	for i in range(excess):
		if hand.is_empty(): break
		if is_opponent_side:
			var discarded = hand[-1]
			hand.erase(discarded)
			discarded.current_location = "discard"
			main.opponent_discard_pile.append(discarded)
		else:
			var remaining = hand.size() - 7
			var chosen = await main.card_ops.prompt_select_card(hand.duplicate(), "CHAMPIONSHIP ARENA", "Discard a card (" + str(remaining) + " more to discard)", "DISCARD", false)
			if main._should_bail(): return
			if chosen == null:
				chosen = hand[-1]
			hand.erase(chosen)
			chosen.current_location = "discard"
			main.player_discard_pile.append(chosen)
		if main._should_bail(): return
	main.refresh_hand_display(is_opponent_side)
	main.update_discard_pile_display(is_opponent_side)

############################################### ECARD1 (EXPEDITION) TRAINERS #########################################################################

func _register_ecard1_trainers() -> void:
	_trainer_dispatch["ecard1-137"] = func(c, opp): await effect_ecard1_bills_maintenance(opp)
	_trainer_dispatch["ecard1-138"] = func(c, opp): await effect_ecard1_copycat(opp)
	_trainer_dispatch["ecard1-139"] = func(c, opp): await effect_ecard1_dual_ball(opp)
	_trainer_dispatch["ecard1-140"] = func(c, opp): await effect_ecard1_energy_removal_2(opp)
	_trainer_dispatch["ecard1-141"] = func(c, opp): await effect_ecard1_energy_restore(opp)
	_trainer_dispatch["ecard1-142"] = func(c, opp): await effect_ecard1_marys_impulse(opp)
	_trainer_dispatch["ecard1-143"] = func(c, opp): await effect_ecard1_master_ball(opp)
	_trainer_dispatch["ecard1-145"] = func(c, opp): await effect_ecard1_pokemon_nurse(opp)
	_trainer_dispatch["ecard1-146"] = func(c, opp): await effect_ecard1_pokemon_reversal(opp)
	_trainer_dispatch["ecard1-147"] = func(c, opp): await effect_ecard1_power_charge(opp)
	_trainer_dispatch["ecard1-148"] = func(c, opp): await effect_ecard1_professor_elms_training_method(opp)
	_trainer_dispatch["ecard1-149"] = func(c, opp): await effect_ecard1_professor_oaks_research(opp)
	_trainer_dispatch["ecard1-151"] = func(c, opp): await effect_neo1_super_scoop_up(opp)
	_trainer_dispatch["ecard1-152"] = func(c, opp): await effect_ecard1_warp_point(opp)
	_trainer_dispatch["ecard1-153"] = func(c, opp): await effect_energy_search(opp)
	_trainer_dispatch["ecard1-154"] = func(c, opp): await effect_full_heal(opp)
	_trainer_dispatch["ecard1-155"] = func(c, opp): await effect_neo1_moo_moo_milk(opp)
	_trainer_dispatch["ecard1-156"] = func(c, opp): await effect_potion(opp)
	_trainer_dispatch["ecard1-157"] = func(c, opp): await effect_switch(opp)
	# ecard1-144 Multi Technical Machine 01 and ecard1-150 Strength Charm are attached
	# trainers — routed via is_attached_trainer()/resolve_attached_trainer(), not this dispatch.

# BILL'S MAINTENANCE (ecard1-137): if you have cards in hand, shuffle 1 into deck, then draw 3
func effect_ecard1_bills_maintenance(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if hand.size() > 0:
		if is_opponent:
			var to_shuffle = cpu_get_discard_priority(hand, 1)
			for card in to_shuffle:
				hand.erase(card)
				card.current_location = "deck"
				deck.append(card)
			deck.shuffle()
		else:
			await player_select_cards_to_discard(hand, 1, "BILL'S MAINTENANCE", "Select 1 card to shuffle into your deck")
			if main._should_bail(): return
			for card in main.trainer_discard_selected:
				hand.erase(card)
				card.current_location = "deck"
				deck.append(card)
			main.trainer_discard_selected.clear()
			deck.shuffle()
		main.refresh_hand_display(is_opponent)
		main.update_deck_icon(is_opponent)
	await main.card_ops.draw_n(is_opponent, 3)
	if main._should_bail(): return
	print("TRAINER: Bill's Maintenance")

# COPYCAT (ecard1-138): shuffle hand into deck, draw = opponent's hand size
func effect_ecard1_copycat(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var opp_hand_size = (main.player_hand if is_opponent else main.opponent_hand).size()
	for card in hand.duplicate():
		hand.erase(card)
		card.current_location = "deck"
		deck.append(card)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if opp_hand_size > 0:
		await main.card_ops.draw_n(is_opponent, opp_hand_size)
		if main._should_bail(): return
	print("TRAINER: Copycat - drew ", opp_hand_size)

# DUAL BALL (ecard1-139): flip 2 coins; for each heads search deck for 1 Basic (non-Baby) Pokemon
func effect_ecard1_dual_ball(is_opponent: bool) -> void:
	await main.show_message("DUAL BALL: FLIPPING 2 COINS...")
	if main._should_bail(): return
	var heads_count = 0
	for i in range(2):
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			heads_count += 1
	if heads_count == 0:
		await main.show_message("DUAL BALL: NO HEADS — NO POKEMON FOUND!")
		if main._should_bail(): return
		return
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]) and "Baby" not in c.metadata.get("subtypes",[])
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "DUAL BALL: CHOOSE UP TO " + str(heads_count) + " BASIC POKEMON", heads_count)
	if main._should_bail(): return
	await main.show_message("DUAL BALL: ADDED " + str(found.size()) + " POKEMON TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Dual Ball - ", heads_count, " heads, found ", found.size())

# ENERGY REMOVAL 2 (ecard1-140): flip a coin; heads discard 1 Energy from opponent's Pokemon
func effect_ecard1_energy_removal_2(is_opponent: bool) -> void:
	await main.show_message("ENERGY REMOVAL 2: FLIPPING COIN...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENERGY REMOVAL 2 FAILED!")
		if main._should_bail(): return
		return
	await effect_energy_removal(is_opponent)
	if main._should_bail(): return
	print("TRAINER: Energy Removal 2 - heads")

# ENERGY RESTORE (ecard1-141): flip 3 coins; for each heads, put a basic Energy from discard into hand
func effect_ecard1_energy_restore(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	await main.show_message("ENERGY RESTORE: FLIPPING 3 COINS...")
	if main._should_bail(): return
	var heads_count = 0
	for i in range(3):
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			heads_count += 1
	if heads_count == 0:
		await main.show_message("ENERGY RESTORE: NO HEADS!")
		if main._should_bail(): return
		return
	var moved = 0
	for i in range(heads_count):
		var basic_energies = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
		if basic_energies.is_empty():
			break
		var chosen: card_object = null
		if is_opponent:
			chosen = basic_energies[0]
		else:
			chosen = await main.card_ops.prompt_select_card(basic_energies, "ENERGY RESTORE", "Select a basic Energy to return to hand (" + str(heads_count - moved) + " remaining)", "SELECT", false, true)
			if main._should_bail(): return
			if chosen == null:
				break
		await main.card_ops.recover_to_hand(chosen, is_opponent, true)
		if main._should_bail(): return
		moved += 1
	await main.show_message("ENERGY RESTORE: RETURNED " + str(moved) + " ENERGY TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Energy Restore - ", heads_count, " heads, moved ", moved)

# MARY'S IMPULSE (ecard1-142): flip until tails; draw 2 for each heads
func effect_ecard1_marys_impulse(is_opponent: bool) -> void:
	await main.show_message("MARY'S IMPULSE: FLIPPING COINS...")
	if main._should_bail(): return
	var heads_count = 0
	while true:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if not coin:
			break
		heads_count += 1
		if heads_count >= 20:  # safety cap against pathological RNG streaks
			break
	if heads_count == 0:
		await main.show_message("MARY'S IMPULSE: TAILS ON FIRST FLIP!")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, heads_count * 2)
	if main._should_bail(): return
	print("TRAINER: Mary's Impulse - ", heads_count, " heads, drew ", heads_count * 2)

# MASTER BALL (ecard1-143): look at top 7 of deck; may take 1 Basic or Evolution card; shuffle the rest back
func effect_ecard1_master_ball(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var look_count = min(7, deck.size())
	var top_cards: Array = []
	for i in range(look_count):
		top_cards.append(deck[i])
	var candidates = top_cards.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and ("Basic" in c.metadata.get("subtypes",[]) or "Stage 1" in c.metadata.get("subtypes",[]) or "Stage 2" in c.metadata.get("subtypes",[])))
	await main.show_message("MASTER BALL: LOOKING AT TOP " + str(look_count) + " CARDS!")
	if main._should_bail(): return
	var chosen: card_object = null
	if candidates.size() > 0:
		if is_opponent:
			chosen = main.cpu_ai.cpu_search_deck_for_best_card(candidates)
		else:
			chosen = await main.card_ops.prompt_select_card(candidates, "MASTER BALL", "Choose a Basic or Evolution card to add to your hand (optional)", "TAKE", true)
			if main._should_bail(): return
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		await main.show_message("MASTER BALL: ADDED " + chosen.metadata.get("name","").to_upper() + " TO HAND!")
		if main._should_bail(): return
	else:
		await main.show_message("MASTER BALL: NO CARD TAKEN!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	print("TRAINER: Master Ball - ", "took a card" if chosen != null else "took nothing")

# POKEMON NURSE (ecard1-145): heal all damage from 1 chosen Pokemon, then discard its Energy
func effect_ecard1_pokemon_nurse(is_opponent: bool) -> void:
	var all_pokemon = build_field_pokemon_array(is_opponent)
	var damaged = all_pokemon.filter(func(p): return p.current_hp < int(p.metadata.get("hp","0")))
	if damaged.size() == 0:
		await main.show_message("NO POKEMON WITH DAMAGE!")
		if main._should_bail(): return
		return
	var target: card_object = await main.card_ops.choose_card(damaged, is_opponent,
			"POKEMON NURSE", "Select a Pokemon to fully heal (its Energy will be discarded)", "HEAL", false,
			func(c): return float(int(c.metadata.get("hp","0")) - c.current_hp))
	if main._should_bail(): return
	if target == null:
		return
	var max_hp = int(target.metadata.get("hp","0"))
	await main.card_ops.heal_pokemon(target, max_hp - target.current_hp, is_opponent)
	if main._should_bail(): return
	if target.attached_energies.size() > 0:
		var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		for energy in target.attached_energies.duplicate():
			energy.current_location = "discard"
			discard.append(energy)
		target.attached_energies.clear()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("POKEMON NURSE: " + target.metadata.get("name","").to_upper() + " FULLY HEALED, ENERGY DISCARDED!")
	if main._should_bail(): return
	print("TRAINER: Pokemon Nurse - healed and discarded energy from ", target.metadata.get("name",""))

# POKEMON REVERSAL (ecard1-146): choose opponent's bench Pokemon, flip; heads swap it into the Defending spot
func effect_ecard1_pokemon_reversal(is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var target_is_opp = not is_opponent
	if target_bench.size() == 0:
		await main.show_message("OPPONENT HAS NO BENCH POKEMON!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		var best: card_object = null
		var best_score = -999.0
		for bp in target_bench:
			var score = (200.0 - bp.current_hp) + (100.0 if bp.attached_energies.size() == 0 else 0.0)
			if score > best_score:
				best_score = score
				best = bp
		chosen = best
	else:
		chosen = await main.card_ops.prompt_select_card(target_bench, "POKEMON REVERSAL", "Select opponent's bench Pokemon", "SELECT", false)
		if main._should_bail(): return
	if chosen == null:
		return
	await main.show_message("POKEMON REVERSAL: FLIPPING COIN...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! POKEMON REVERSAL FAILED!")
		if main._should_bail(): return
		return
	var old_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	target_bench.erase(chosen)
	target_bench.append(old_active)
	old_active.current_location = "bench"
	chosen.current_location = "active"
	if is_opponent:
		main.player_active_pokemon = chosen
	else:
		main.opponent_active_pokemon = chosen
	await main.animate_retreat(old_active, chosen, [], target_is_opp, true)
	if main._should_bail(): return
	main.clear_all_statuses(old_active, target_is_opp)
	main.display_pokemon(target_is_opp)
	main.display_active_pokemon_energies(target_is_opp)
	await main.show_message("HEADS! " + chosen.metadata.get("name","").to_upper() + " SWITCHED IN!")
	if main._should_bail(): return
	print("TRAINER: Pokemon Reversal - heads")

# POWER CHARGE (ecard1-147): flip; heads shuffle 2 Energy cards from discard into deck (1 if only 1)
func effect_ecard1_power_charge(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	await main.show_message("POWER CHARGE: FLIPPING COIN...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! POWER CHARGE FAILED!")
		if main._should_bail(): return
		return
	var energies_in_discard = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if energies_in_discard.is_empty():
		await main.show_message("NO ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
		return
	var want = min(2, energies_in_discard.size())
	var moved: Array = []
	for i in range(want):
		var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy")
		if pool.is_empty(): break
		var chosen: card_object = null
		if is_opponent:
			chosen = main.cpu_ai.cpu_pick_best_keep(pool)  # recycle the most useful Energy back into the deck
		else:
			chosen = await main.card_ops.prompt_select_card(pool, "POWER CHARGE", "Select an Energy to shuffle into your deck (" + str(want - moved.size()) + " remaining)", "SELECT", false, true)
			if main._should_bail(): return
			if chosen == null: break
		discard.erase(chosen)
		chosen.current_location = "deck"
		deck.append(chosen)
		moved.append(chosen)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("HEADS! SHUFFLED " + str(moved.size()) + " ENERGY INTO DECK!")
	if main._should_bail(): return
	print("TRAINER: Power Charge - moved ", moved.size())

# PROFESSOR ELM'S TRAINING METHOD (ecard1-148): search deck for 1 Evolution card
func effect_ecard1_professor_elms_training_method(is_opponent: bool) -> void:
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and ("Stage 1" in c.metadata.get("subtypes",[]) or "Stage 2" in c.metadata.get("subtypes",[]))
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "PROFESSOR ELM'S TRAINING METHOD: CHOOSE AN EVOLUTION CARD", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO EVOLUTION CARDS IN DECK!")
		if main._should_bail(): return
		return
	await main.show_message("ADDED " + found[0].metadata.get("name","").to_upper() + " TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Professor Elm's Training Method")

# PROFESSOR OAK'S RESEARCH (ecard1-149): shuffle hand into deck, draw 5
func effect_ecard1_professor_oaks_research(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	for card in hand.duplicate():
		hand.erase(card)
		card.current_location = "deck"
		deck.append(card)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.card_ops.draw_n(is_opponent, 5)
	if main._should_bail(): return
	print("TRAINER: Professor Oak's Research")

# WARP POINT (ecard1-152): opponent switches Defending with bench (their choice, if any); then you switch Active with bench (your choice, if any)
func effect_ecard1_warp_point(is_opponent: bool) -> void:
	var opp_target_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_target_is_opp = not is_opponent
	if opp_target_bench.size() > 0:
		var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		var new_opp_active: card_object = null
		if opp_target_is_opp:
			var cpu_eval = main.cpu_ai.get_cpu_evaluation()
			new_opp_active = main.cpu_ai.pick_best_bench_replacement(opp_target_bench, main.player_active_pokemon, cpu_eval)
			if new_opp_active == null:
				new_opp_active = opp_target_bench[0]
		else:
			new_opp_active = await main.card_ops.prompt_select_card(opp_target_bench, "WARP POINT", "Opponent switches: select a bench Pokemon", "SWITCH", false)
			if main._should_bail(): return
		if new_opp_active != null:
			opp_target_bench.erase(new_opp_active)
			opp_target_bench.append(opp_active)
			opp_active.current_location = "bench"
			new_opp_active.current_location = "active"
			if opp_target_is_opp:
				main.opponent_active_pokemon = new_opp_active
			else:
				main.player_active_pokemon = new_opp_active
			await main.animate_retreat(opp_active, new_opp_active, [], opp_target_is_opp, true)
			if main._should_bail(): return
			main.clear_all_statuses(opp_active, opp_target_is_opp)
			main.display_pokemon(opp_target_is_opp)
			main.display_active_pokemon_energies(opp_target_is_opp)

	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() > 0:
		var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		var new_own_active: card_object = null
		if is_opponent:
			var cpu_eval2 = main.cpu_ai.get_cpu_evaluation()
			new_own_active = main.cpu_ai.pick_best_bench_replacement(own_bench, main.player_active_pokemon, cpu_eval2)
			if new_own_active == null:
				new_own_active = own_bench[0]
		else:
			new_own_active = await main.card_ops.prompt_select_card(own_bench, "WARP POINT", "Select a bench Pokemon to switch in", "SWITCH", false)
			if main._should_bail(): return
		if new_own_active != null:
			own_bench.erase(new_own_active)
			own_bench.append(own_active)
			own_active.current_location = "bench"
			new_own_active.current_location = "active"
			if is_opponent:
				main.opponent_active_pokemon = new_own_active
			else:
				main.player_active_pokemon = new_own_active
			await main.animate_retreat(own_active, new_own_active, [], is_opponent, true)
			if main._should_bail(): return
			main.clear_all_statuses(own_active, is_opponent)
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
	print("TRAINER: Warp Point")

######################################################################################################################################################
######################################################### ECARD2 (AQUAPOLIS) STADIUMS ################################################################
######################################################################################################################################################

# APRICORN FOREST (ecard2-118): once per player's turn (before attacking), if that player's bench
# isn't full, flip; heads reveal a basic Energy from hand and search deck for a Basic Pokemon of
# the same type to put onto the bench
func apricorn_forest_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.APRICORN_FOREST: return false
	if is_opponent and main.opponent_apricorn_forest_used_this_turn: return false
	if not is_opponent and main.player_apricorn_forest_used_this_turn: return false
	var bench = main.opponent_bench if is_opponent else main.player_bench
	return bench.size() < main.get_max_bench_size()

func apricorn_forest_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_apricorn_forest_used_this_turn = true
	else:
		main.player_apricorn_forest_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("APRICORN FOREST! TAILS — NO EFFECT!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if basics.is_empty():
		await main.show_message("APRICORN FOREST! HEADS — BUT NO BASIC ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var energy: card_object = basics[0]
	if not is_opponent and basics.size() > 1:
		energy = await main.card_ops.prompt_select_card(basics, "APRICORN FOREST", "Choose a basic Energy card to reveal", "REVEAL", false, true)
		if main._should_bail(): return
		if energy == null: return
	var energy_type = main.get_energy_provided_by_card(energy)
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var candidates = deck.filter(func(c): return "Basic" in c.metadata.get("subtypes",[]) and "Baby" not in c.metadata.get("subtypes",[]) and not energy_type.filter(func(t): return t in c.metadata.get("types",[])).is_empty())
	if candidates.is_empty():
		await main.show_message("APRICORN FOREST! NO MATCHING BASIC POKEMON IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = main.cpu_ai.cpu_pick_best_keep(candidates) if is_opponent else candidates[0]
	if not is_opponent and candidates.size() > 1:
		chosen = await main.card_ops.prompt_select_card(candidates, "APRICORN FOREST", "Choose a Basic Pokemon to place on your bench", "BENCH", false)
		if main._should_bail(): return
		if chosen == null:
			deck.shuffle()
			return
	deck.erase(chosen)
	chosen.current_location = "bench"
	(main.opponent_bench if is_opponent else main.player_bench).append(chosen)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("APRICORN FOREST! " + chosen.metadata.get("name","").to_upper() + " ADDED TO BENCH!")
	if main._should_bail(): return
	print("STADIUM: Apricorn Forest — benched ", chosen.metadata.get("name",""))

# UNDERSEA RUINS (ecard2-138): once per player's turn, may flip; heads devolve one of your own
# Evolved Pokemon (discard its top Evolution card, revealing the pre-evolution underneath)
func undersea_ruins_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.UNDERSEA_RUINS: return false
	if is_opponent and main.opponent_undersea_ruins_used_this_turn: return false
	if not is_opponent and main.player_undersea_ruins_used_this_turn: return false
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if active != null: all_own.append(active)
	all_own.append_array(bench)
	for p in all_own:
		if p.attached_pre_evolutions.size() > 0: return true
	return false

func undersea_ruins_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_undersea_ruins_used_this_turn = true
	else:
		main.player_undersea_ruins_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("UNDERSEA RUINS! TAILS — NO EFFECT!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if active != null: all_own.append(active)
	all_own.append_array(bench)
	var candidates = all_own.filter(func(p): return p.attached_pre_evolutions.size() > 0)
	if candidates.is_empty():
		await main.show_message("HEADS! BUT NO EVOLVED POKEMON TO DEVOLVE!")
		if main._should_bail(): return
		return
	# Devolving costs US power — prefer a Bench candidate (keeps the Active's full strength) and, among
	# Bench candidates, the lowest-HP one (least invested).
	var target: card_object = candidates[0]
	if is_opponent:
		var bench_candidates = candidates.filter(func(c): return c != active)
		var pool_to_pick = bench_candidates if not bench_candidates.is_empty() else candidates
		target = pool_to_pick[0]
		for c in pool_to_pick:
			if c.current_hp < target.current_hp: target = c
	if not is_opponent and candidates.size() > 1:
		target = await main.card_ops.prompt_select_card(candidates, "UNDERSEA RUINS", "Choose a Pokemon to devolve", "DEVOLVE", false)
		if main._should_bail(): return
		if target == null: return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var pre_evo = target.attached_pre_evolutions.pop_back()
	pre_evo.current_hp = target.current_hp
	pre_evo.attached_energies = target.attached_energies.duplicate()
	target.attached_energies.clear()
	pre_evo.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	target.attached_pre_evolutions.clear()
	var is_active_slot = (target == active)
	pre_evo.current_location = target.current_location
	if is_active_slot:
		if is_opponent:
			main.opponent_active_pokemon = pre_evo
		else:
			main.player_active_pokemon = pre_evo
	else:
		var idx = bench.find(target)
		if idx >= 0: bench[idx] = pre_evo
	target.current_location = "discard"
	discard.append(target)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("HEADS! " + target.metadata.get("name","").to_upper() + " DEVOLVED INTO " + pre_evo.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("STADIUM: Undersea Ruins — devolved ", target.metadata.get("name",""))

# POWER PLANT (ecard2-139): once per turn, may discard a basic Energy from hand to search the
# discard pile for a basic Energy card and put it into hand
func power_plant_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.POWER_PLANT: return false
	if is_opponent and main.opponent_power_plant_used_this_turn: return false
	if not is_opponent and main.player_power_plant_used_this_turn: return false
	var hand = main.opponent_hand if is_opponent else main.player_hand
	return hand.any(func(c): return main.attack_effects.gym1_is_basic_energy(c))

func power_plant_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_power_plant_used_this_turn = true
	else:
		main.player_power_plant_used_this_turn = true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand_basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if hand_basics.is_empty(): return
	var to_discard: card_object = hand_basics[0]
	if not is_opponent and hand_basics.size() > 1:
		to_discard = await main.card_ops.prompt_select_card(hand_basics, "POWER PLANT", "Choose a basic Energy to discard", "DISCARD", false)
		if main._should_bail(): return
		if to_discard == null: return
	hand.erase(to_discard)
	to_discard.current_location = "discard"
	discard.append(to_discard)
	var discard_basics = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c) and c != to_discard)
	if discard_basics.is_empty():
		main.refresh_hand_display(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("POWER PLANT! DISCARDED BUT NO OTHER BASIC ENERGY TO RETRIEVE!")
		if main._should_bail(): return
		return
	var chosen: card_object = discard_basics[0]
	if not is_opponent and discard_basics.size() > 1:
		chosen = await main.card_ops.prompt_select_card(discard_basics, "POWER PLANT", "Choose a basic Energy to put into your hand", "SELECT", false, true)
		if main._should_bail(): return
		if chosen == null: chosen = discard_basics[0]
	discard.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("POWER PLANT! SWAPPED FOR " + chosen.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("STADIUM: Power Plant")

# POKEMON PARK (ecard2-131): passive/reactive — whenever a player attaches an Energy card from
# hand to one of their OWN Benched Pokemon, remove 1 damage counter from it. Called from the
# energy-attach code paths (Main + CPU_AI) right after a successful hand-to-bench attach.
func pokemon_park_on_bench_energy_attach(pokemon: card_object, is_opponent: bool) -> void:
	if not main.is_stadium_in_play(StadiumIds.POKEMON_PARK): return
	if pokemon.current_hp >= pokemon.get_max_hp(): return
	pokemon.current_hp = min(pokemon.get_max_hp(), pokemon.current_hp + 10)
	main.display_hp_circles_above_align(pokemon, is_opponent)
	print("STADIUM: Pokemon Park — healed 10 HP on ", pokemon.metadata.get("name",""))

######################################################################################################################################################
######################################################### ECARD2 (AQUAPOLIS) TOOLS ###################################################################
######################################################################################################################################################

# HEALING BERRY (ecard2-125): at the end of ANY turn (both sides), if the holder has 20 HP or
# less, remove 3 damage counters from it and discard this card. Called once per turn end from
# Main's inbetween_turn_checks (not gym1_end_of_turn_cleanup, since it must fire for BOTH sides
# regardless of whose turn just ended).
func ecard2_healing_berry_check() -> void:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		var bench = main.opponent_bench if side else main.player_bench
		var all_p: Array = []
		if active != null: all_p.append(active)
		all_p.append_array(bench)
		for p in all_p:
			if p.current_hp <= 0 or p.current_hp > 20: continue
			var berry: card_object = null
			for ac in p.attached_cards:
				if ac.uid.to_lower() == "ecard2-125":
					berry = ac
					break
			if berry == null: continue
			p.attached_cards.erase(berry)
			var discard = main.opponent_discard_pile if side else main.player_discard_pile
			berry.current_location = "discard"
			discard.append(berry)
			p.current_hp = min(p.get_max_hp(), p.current_hp + 30)
			main.display_hp_circles_above_align(p, side)
			display_attached_trainer_cards(side)
			main.update_discard_pile_display(side)
			await main.show_message("HEALING BERRY! " + p.metadata.get("name","").to_upper() + " HEALED AND THE BERRY WAS DISCARDED!")
			if main._should_bail(): return

# TIME SHARD (ecard2-135): if the holder is Knocked Out by the Defending Pokemon's attack during
# the opponent's turn, may return up to 2 basic Energy cards attached to it to hand before the
# normal KO discard sequence takes its attachments. Registered as a pre-KO hook.
func check_time_shard(pokemon: card_object, attacker: card_object, is_pokemon_opp: bool) -> void:
	if attacker == null: return
	var shard: card_object = null
	for ac in pokemon.attached_cards:
		if ac.uid.to_lower() == "ecard2-135":
			shard = ac
			break
	if shard == null: return
	var basics = pokemon.attached_energies.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if basics.is_empty(): return
	var hand = main.opponent_hand if is_pokemon_opp else main.player_hand
	var want = min(2, basics.size())
	var moved = 0
	for i in range(want):
		var pool = pokemon.attached_energies.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
		if pool.is_empty(): break
		var chosen: card_object = null
		if is_pokemon_opp:
			chosen = pool[0]
		else:
			chosen = await main.card_ops.prompt_select_card(pool, "TIME SHARD", "Select a basic Energy to return to hand (" + str(want - moved) + " remaining)", "SELECT", true)
			if main._should_bail(): return
			if chosen == null: break
		pokemon.attached_energies.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		moved += 1
	if moved > 0:
		main.refresh_hand_display(is_pokemon_opp)
		await main.show_message("TIME SHARD! RETURNED " + str(moved) + " ENERGY TO HAND!")
		if main._should_bail(): return
	print("TOOL: Time Shard — returned ", moved, " energy from ", pokemon.metadata.get("name",""))

######################################################################################################################################################
######################################################### ECARD2 (AQUAPOLIS) TRAINERS ################################################################
######################################################################################################################################################

func _register_ecard2_trainers() -> void:
	_trainer_dispatch["ecard2-120"] = func(c, opp): await effect_ecard2_energy_switch(opp)
	_trainer_dispatch["ecard2-123"] = func(c, opp): await effect_ecard2_forest_guardian(opp)
	_trainer_dispatch["ecard2-126"] = func(c, opp): await effect_ecard2_juggler(opp)
	_trainer_dispatch["ecard2-130"] = func(c, opp): await effect_ecard2_pokemon_fan_club(opp)
	_trainer_dispatch["ecard2-133"] = func(c, opp): await effect_ecard2_seer(opp)
	_trainer_dispatch["ecard2-134"] = func(c, opp): await effect_ecard2_super_energy_removal_2(opp)
	_trainer_dispatch["ecard2-136"] = func(c, opp): await effect_ecard2_town_volunteers(opp)
	_trainer_dispatch["ecard2-137"] = func(c, opp): await effect_ecard2_traveling_salesman(opp)
	# ecard2-118/131/138/139 (Stadiums) route via resolve_stadium_trainer.
	# ecard2-119/121/122/124/127/129/132/140 (Technical Machine Cubes), ecard2-125/128/135
	# (Pokemon Tools), and ecard2-141 (Weakness Guard) route via is_attached_trainer()/
	# resolve_attached_trainer() — none need a _trainer_dispatch entry.

# ENERGY SWITCH (ecard2-120): move a basic Energy card from 1 of your Pokemon to another
func effect_ecard2_energy_switch(is_opponent: bool) -> void:
	var all_p = build_field_pokemon_array(is_opponent)
	var sources = all_p.filter(func(p): return p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0)
	if sources.is_empty():
		await main.show_message("NO BASIC ENERGY TO MOVE!")
		if main._should_bail(): return
		return
	var source: card_object = null
	var energy: card_object = null
	if is_opponent:
		# Take from whichever source needs the Energy LEAST (safest to drain).
		source = sources[0]
		for s in sources:
			if main.cpu_ai.cpu_rank_benefit_recipient(s, "energy") < main.cpu_ai.cpu_rank_benefit_recipient(source, "energy"):
				source = s
		energy = source.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))[0]
	else:
		source = await main.card_ops.prompt_select_card(sources, "ENERGY SWITCH", "Select a Pokemon to move Energy from", "SELECT", false)
		if main._should_bail(): return
		if source == null: return
		var basics = source.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))
		energy = await main.card_ops.prompt_select_card(basics, "ENERGY SWITCH", "Select the Energy card to move", "SELECT", false)
		if main._should_bail(): return
	if energy == null: return
	var targets = all_p.filter(func(p): return p != source)
	if targets.is_empty(): return
	var target: card_object = null
	if is_opponent:
		target = main.cpu_ai.cpu_pick_benefit_recipient(targets, "energy", energy)
	else:
		target = await main.card_ops.prompt_select_card(targets, "ENERGY SWITCH", "Select a Pokemon to move the Energy to", "ATTACH", false)
		if main._should_bail(): return
	if target == null: return
	source.attached_energies.erase(energy)
	target.attached_energies.append(energy)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ENERGY SWITCH! MOVED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("TRAINER: Energy Switch")

# SUPER ENERGY REMOVAL 2 (ecard2-134): flip 2; both heads=discard all Defending Energy, both tails=discard all own Active Energy, mixed=nothing
func effect_ecard2_super_energy_removal_2(is_opponent: bool) -> void:
	var c1 = await main.flip_coin(true, is_opponent)
	var c2 = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	if c1 and c2:
		var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		if defender != null and defender.attached_energies.size() > 0:
			var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
			for e in defender.attached_energies.duplicate():
				defender.attached_energies.erase(e)
				e.current_location = "discard"
				target_discard.append(e)
			main.display_pokemon(not is_opponent)
			main.display_active_pokemon_energies(not is_opponent)
			main.update_discard_pile_display(not is_opponent)
			await main.show_message("BOTH HEADS! DISCARDED ALL ENERGY FROM THE DEFENDING POKEMON!")
			if main._should_bail(): return
		else:
			await main.show_message("BOTH HEADS! BUT THE DEFENDING POKEMON HAS NO ENERGY!")
			if main._should_bail(): return
	elif not c1 and not c2:
		var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
		if own_active != null and own_active.attached_energies.size() > 0:
			var own_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			for e in own_active.attached_energies.duplicate():
				own_active.attached_energies.erase(e)
				e.current_location = "discard"
				own_discard.append(e)
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
			main.update_discard_pile_display(is_opponent)
			await main.show_message("BOTH TAILS! DISCARDED ALL ENERGY FROM YOUR ACTIVE POKEMON!")
			if main._should_bail(): return
		else:
			await main.show_message("BOTH TAILS! BUT YOUR ACTIVE POKEMON HAS NO ENERGY!")
			if main._should_bail(): return
	else:
		await main.show_message("ONE HEADS, ONE TAILS! SUPER ENERGY REMOVAL 2 DID NOTHING!")
		if main._should_bail(): return
	print("TRAINER: Super Energy Removal 2")

# FOREST GUARDIAN (ecard2-123): shuffle deck, look at top 7, take 1, shuffle the rest back
func effect_ecard2_forest_guardian(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	if deck.is_empty():
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top_cards = main.card_ops.peek_top_n(is_opponent, 7)
	await main.show_message("FOREST GUARDIAN: LOOKING AT TOP " + str(top_cards.size()) + " CARDS!")
	if main._should_bail(): return
	var chosen: card_object = null
	if is_opponent:
		chosen = main.cpu_ai.cpu_search_deck_for_best_card(top_cards)
	else:
		chosen = await main.card_ops.prompt_select_card(top_cards, "FOREST GUARDIAN", "Choose a card to add to your hand", "TAKE", true)
		if main._should_bail(): return
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		(main.opponent_hand if is_opponent else main.player_hand).append(chosen)
		main.refresh_hand_display(is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	await main.show_message("ADDED " + (chosen.metadata.get("name","").to_upper() if chosen != null else "NOTHING") + " TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Forest Guardian")

# JUGGLER (ecard2-126): discard up to 2 basic Energy from hand; 1 discarded=draw 3, 2 discarded=draw 5
func effect_ecard2_juggler(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if basics.is_empty():
		await main.show_message("NO BASIC ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var want = min(2, basics.size())
	var discarded: Array = []
	if is_opponent:
		for i in range(want): discarded.append(basics[i])
	else:
		var confirm_2 = false
		if want >= 2:
			confirm_2 = await gym1_prompt_yes_no(basics[0], "JUGGLER", "Discard 2 basic Energy to draw 5 cards? (No = discard 1 to draw 3)", "DISCARD 2", "DISCARD 1")
			if main._should_bail(): return
		var pick_count = 2 if confirm_2 else 1
		for i in range(min(pick_count, basics.size())):
			var pool = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c) and c not in discarded)
			if pool.is_empty(): break
			var chosen = await main.card_ops.prompt_select_card(pool, "JUGGLER", "Select a basic Energy to discard", "DISCARD", false)
			if main._should_bail(): return
			if chosen == null: break
			discarded.append(chosen)
	if discarded.is_empty():
		await main.show_message("NO ENERGY DISCARDED!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for e in discarded:
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	var draw_count = 5 if discarded.size() >= 2 else 3
	await main.card_ops.draw_n(is_opponent, draw_count)
	if main._should_bail(): return
	print("TRAINER: Juggler — discarded ", discarded.size(), ", drew ", draw_count)

# POKEMON FAN CLUB (ecard2-130): search deck for up to 2 Baby/Basic Pokemon to bench
func effect_ecard2_pokemon_fan_club(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var space = main.get_max_bench_size() - bench.size()
	if space <= 0:
		await main.show_message("YOUR BENCH IS FULL!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var want = min(2, space)
	var filter_fn = func(c): return "Basic" in c.metadata.get("subtypes",[]) or "Baby" in c.metadata.get("subtypes",[])
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "POKEMON FAN CLUB: CHOOSE UP TO " + str(want) + " BASIC/BABY POKEMON", want)
	if main._should_bail(): return
	for p in found:
		var hand = main.opponent_hand if is_opponent else main.player_hand
		hand.erase(p)
		p.current_location = "bench"
		bench.append(p)
	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("POKEMON FAN CLUB! ADDED " + str(found.size()) + " POKEMON TO BENCH!")
	if main._should_bail(): return
	print("TRAINER: Pokemon Fan Club — benched ", found.size())

# SEER (ecard2-133): look at top 6, take ALL basic Energy cards found, shuffle the rest back
func effect_ecard2_seer(is_opponent: bool) -> void:
	var top_cards = main.card_ops.peek_top_n(is_opponent, 6)
	if top_cards.is_empty():
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var found = top_cards.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	await main.show_message("SEER: LOOKING AT TOP " + str(top_cards.size()) + " CARDS!")
	if main._should_bail(): return
	for c in found:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SEER! FOUND AND ADDED " + str(found.size()) + " BASIC ENERGY TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Seer — found ", found.size())

# TOWN VOLUNTEERS (ecard2-136): take up to 5 Baby/Basic/Evolution/basic-Energy cards from discard, shuffle them into deck
func effect_ecard2_town_volunteers(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var candidates = discard.filter(func(c):
		var st = c.metadata.get("supertype","")
		if st == "Pokémon": return true
		if st == "Energy" and main.attack_effects.gym1_is_basic_energy(c): return true
		return false)
	if candidates.is_empty():
		await main.show_message("NOTHING IN DISCARD PILE TO RECOVER!")
		if main._should_bail(): return
		return
	var want = min(5, candidates.size())
	var chosen: Array = []
	if is_opponent:
		for i in range(want): chosen.append(candidates[i])
	else:
		for i in range(want):
			var pool = discard.filter(func(c):
				var st = c.metadata.get("supertype","")
				if c in chosen: return false
				if st == "Pokémon": return true
				if st == "Energy" and main.attack_effects.gym1_is_basic_energy(c): return true
				return false)
			if pool.is_empty(): break
			var pick = await main.card_ops.prompt_select_card(pool, "TOWN VOLUNTEERS", "Choose a card to shuffle into your deck (" + str(want - chosen.size()) + " remaining, cancel to stop)", "SELECT", true)
			if main._should_bail(): return
			if pick == null: break
			chosen.append(pick)
	for c in chosen:
		discard.erase(c)
		c.current_location = "deck"
		deck.append(c)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("TOWN VOLUNTEERS! SHUFFLED " + str(chosen.size()) + " CARD(S) INTO YOUR DECK!")
	if main._should_bail(): return
	print("TRAINER: Town Volunteers — recovered ", chosen.size())

# TRAVELING SALESMAN (ecard2-137): search deck for up to 2 Technical Machine and/or Pokemon Tool cards to hand
func effect_ecard2_traveling_salesman(is_opponent: bool) -> void:
	var filter_fn = func(c):
		var st = c.metadata.get("subtypes", [])
		return "Technical Machine" in st or "Pokémon Tool" in st
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "TRAVELING SALESMAN: CHOOSE UP TO 2 TM/TOOL CARDS", 2)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO TECHNICAL MACHINE OR POKEMON TOOL CARDS IN DECK!")
		if main._should_bail(): return
		return
	await main.show_message("TRAVELING SALESMAN! ADDED " + str(found.size()) + " CARD(S) TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Traveling Salesman — found ", found.size())

######################################################################################################################################################
######################################################### ECARD3 (SKYRIDGE) STADIUMS ##################################################################
######################################################################################################################################################

# ANCIENT RUINS (ecard3-119): once per player's turn (before attacking), if that player hasn't
# played a Supporter this turn, may reveal hand; if no Supporter card is revealed, draw a card
func ancient_ruins_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.ANCIENT_RUINS: return false
	if is_opponent and main.opponent_ancient_ruins_used_this_turn: return false
	if not is_opponent and main.player_ancient_ruins_used_this_turn: return false
	return true

func ancient_ruins_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_ancient_ruins_used_this_turn = true
	else:
		main.player_ancient_ruins_used_this_turn = true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var has_supporter = hand.any(func(c): return "Supporter" in c.metadata.get("subtypes", []))
	await main.show_message("ANCIENT RUINS! REVEALING HAND!")
	if main._should_bail(): return
	if has_supporter:
		await main.show_message("A SUPPORTER CARD WAS REVEALED — NO EFFECT!")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	await main.show_message("NO SUPPORTER REVEALED! DREW A CARD!")
	if main._should_bail(): return
	print("STADIUM: Ancient Ruins")

# MIRAGE STADIUM (ecard3-132): whenever a player tries to retreat, flip a coin. Heads: retreat
# proceeds normally. Tails: the retreat does not happen (no Energy discarded). Called from both
# the player's handle_action_retreat_bench and CPU's execute_cpu_retreat, before any cost is paid.
func mirage_stadium_check(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return true
	if main.current_stadium_card.uid.to_lower() != StadiumIds.MIRAGE_STADIUM: return true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return false
	if coin:
		return true
	await main.show_message("MIRAGE STADIUM! TAILS — THE RETREAT DOES NOT HAPPEN!")
	if main._should_bail(): return false
	print("STADIUM: Mirage Stadium — retreat blocked")
	return false

# MYSTERY ZONE (ecard3-137): once per player's turn, if that player has an Evolution card in
# hand, may search deck for a basic Energy to hand, then must put an Evolution card from hand
# into the deck and shuffle
func mystery_zone_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.MYSTERY_ZONE: return false
	if is_opponent and main.opponent_mystery_zone_used_this_turn: return false
	if not is_opponent and main.player_mystery_zone_used_this_turn: return false
	var hand = main.opponent_hand if is_opponent else main.player_hand
	return hand.any(func(c): return c.metadata.get("supertype","") == "Pokémon" and not main.is_basic_pokemon(c))

func mystery_zone_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_mystery_zone_used_this_turn = true
	else:
		main.player_mystery_zone_used_this_turn = true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var evolutions = hand.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and not main.is_basic_pokemon(c))
	if evolutions.is_empty():
		return
	var filter_fn = func(c): return main.attack_effects.gym1_is_basic_energy(c)
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "MYSTERY ZONE: CHOOSE A BASIC ENERGY (OPTIONAL)", 1)
	if main._should_bail(): return
	if found.size() > 0:
		await main.show_message("MYSTERY ZONE! FOUND " + found[0].metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	evolutions = hand.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and not main.is_basic_pokemon(c))
	if evolutions.is_empty(): return
	var to_return: card_object = evolutions[0]
	if not is_opponent and evolutions.size() > 1:
		to_return = await main.card_ops.prompt_select_card(evolutions, "MYSTERY ZONE", "Choose an Evolution card to put into your deck", "RETURN", false)
		if main._should_bail(): return
		if to_return == null: to_return = evolutions[0]
	var deck = main.opponent_deck if is_opponent else main.player_deck
	hand.erase(to_return)
	to_return.current_location = "deck"
	deck.append(to_return)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("MYSTERY ZONE! RETURNED " + to_return.metadata.get("name","").to_upper() + " TO THE DECK!")
	if main._should_bail(): return
	print("STADIUM: Mystery Zone")

# UNDERGROUND LAKE (ecard3-141): once per player's turn, may put an Omanyte or Kabuto from the
# discard pile onto the Bench (counts as a Basic Pokemon)
func underground_lake_active(is_opponent: bool) -> bool:
	if main.current_stadium_card == null: return false
	if main.current_stadium_card.uid.to_lower() != StadiumIds.UNDERGROUND_LAKE: return false
	if is_opponent and main.opponent_underground_lake_used_this_turn: return false
	if not is_opponent and main.player_underground_lake_used_this_turn: return false
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size(): return false
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	return discard.any(func(c): return c.metadata.get("name","") in ["Omanyte","Kabuto"])

func underground_lake_activate(is_opponent: bool) -> void:
	if is_opponent:
		main.opponent_underground_lake_used_this_turn = true
	else:
		main.player_underground_lake_used_this_turn = true
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size(): return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var candidates = discard.filter(func(c): return c.metadata.get("name","") in ["Omanyte","Kabuto"])
	if candidates.is_empty(): return
	var chosen: card_object = main.cpu_ai.cpu_pick_best_keep(candidates) if is_opponent else candidates[0]
	if not is_opponent and candidates.size() > 1:
		chosen = await main.card_ops.prompt_select_card(candidates, "UNDERGROUND LAKE", "Choose Omanyte or Kabuto to put onto your Bench", "BENCH", false)
		if main._should_bail(): return
		if chosen == null: return
	discard.erase(chosen)
	chosen.current_location = "bench"
	chosen.current_hp = chosen.get_max_hp()
	bench.append(chosen)
	main.display_pokemon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("UNDERGROUND LAKE! " + chosen.metadata.get("name","").to_upper() + " ADDED TO BENCH!")
	if main._should_bail(): return
	print("STADIUM: Underground Lake")

######################################################################################################################################################
######################################################### ECARD3 (SKYRIDGE) TOOLS ####################################################################
######################################################################################################################################################

# STAR PIECE (ecard3-139): at any time between turns, if the holder is Benched with 2+ damage
# counters, may search the deck for an Evolution card it evolves into and auto-evolve it
# (counts as evolving), then discard Star Piece. Called once per turn-end from Main's
# inbetween_turn_checks, mirroring Healing Berry's both-sides check.
func ecard3_star_piece_check() -> void:
	for side in [false, true]:
		var bench = main.opponent_bench if side else main.player_bench
		for p in bench.duplicate():
			if p.get_damage_counters() < 2: continue
			var star: card_object = null
			for ac in p.attached_cards:
				if ac.uid.to_lower() == "ecard3-139":
					star = ac
					break
			if star == null: continue
			var deck = main.opponent_deck if side else main.player_deck
			var p_name = p.metadata.get("name","")
			var candidates = deck.filter(func(c): return c.metadata.get("evolvesFrom","") == p_name)
			if candidates.is_empty(): continue
			var do_it = side
			if not side:
				do_it = await gym1_prompt_yes_no(p, "STAR PIECE", "Search your deck for an Evolution card and evolve " + p_name.to_upper() + "?", "EVOLVE", "SKIP")
				if main._should_bail(): return
			if not do_it: continue
			var evo_card: card_object = main.cpu_ai.cpu_pick_best_keep(candidates) if side else candidates[0]
			if not side and candidates.size() > 1:
				evo_card = await main.card_ops.prompt_select_card(candidates, "STAR PIECE", "Choose an Evolution card", "EVOLVE", false)
				if main._should_bail(): return
				if evo_card == null: continue
			deck.erase(evo_card)
			var max_hp_old = p.get_max_hp()
			var damage_taken = max_hp_old - p.current_hp
			var max_hp_new = int(evo_card.metadata.get("hp", "0"))
			evo_card.current_hp = max(1, max_hp_new - damage_taken)
			evo_card.attached_energies = p.attached_energies.duplicate()
			p.attached_energies.clear()
			evo_card.attached_pre_evolutions = p.attached_pre_evolutions.duplicate()
			p.attached_pre_evolutions.clear()
			evo_card.attached_pre_evolutions.append(p)
			evo_card.placed_on_field_this_turn = true
			evo_card.current_location = "bench"
			var idx = bench.find(p)
			if idx >= 0: bench[idx] = evo_card
			p.attached_cards.erase(star)
			var discard = main.opponent_discard_pile if side else main.player_discard_pile
			star.current_location = "discard"
			discard.append(star)
			deck.shuffle()
			main.display_pokemon(side)
			main.display_active_pokemon_energies(side)
			main.update_deck_icon(side)
			main.update_discard_pile_display(side)
			await main.show_message("STAR PIECE! " + p_name.to_upper() + " EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
			print("TOOL: Star Piece — evolved ", p_name, " into ", evo_card.metadata.get("name",""))

######################################################################################################################################################
######################################################### ECARD3 (SKYRIDGE) TRAINERS ##################################################################
######################################################################################################################################################

func _register_ecard3_trainers() -> void:
	_trainer_dispatch["ecard3-120"] = func(c, opp): await effect_ecard3_relic_hunter(opp)
	_trainer_dispatch["ecard3-121"] = func(c, opp): await effect_ecard3_apricorn_maker(opp)
	_trainer_dispatch["ecard3-123"] = func(c, opp): await effect_ecard3_desert_shaman(opp)
	_trainer_dispatch["ecard3-124"] = func(c, opp): await effect_ecard3_fast_ball(opp)
	_trainer_dispatch["ecard3-125"] = func(c, opp): await effect_ecard3_fisherman(opp)
	_trainer_dispatch["ecard3-126"] = func(c, opp): await effect_ecard3_friend_ball(opp)
	_trainer_dispatch["ecard3-127"] = func(c, opp): await effect_ecard3_hyper_potion(opp)
	_trainer_dispatch["ecard3-128"] = func(c, opp): await effect_ecard3_lure_ball(opp)
	_trainer_dispatch["ecard3-138"] = func(c, opp): await effect_ecard3_oracle(opp)
	_trainer_dispatch["ecard3-140"] = func(c, opp): await effect_ecard3_underground_expedition(opp)
	# ecard3-119/132/137/141 (Stadiums) route via resolve_stadium_trainer.
	# ecard3-122/139 (Pokemon Tools) and ecard3-129/130/131/133/134/135/136 (Technical Machines)
	# route via is_attached_trainer()/resolve_attached_trainer() — none need a _trainer_dispatch entry.

# RELIC HUNTER (ecard3-120): search deck for up to 2 Supporter and/or Stadium cards to hand
func effect_ecard3_relic_hunter(is_opponent: bool) -> void:
	var filter_fn = func(c): return "Supporter" in c.metadata.get("subtypes",[]) or "Stadium" in c.metadata.get("subtypes",[])
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "RELIC HUNTER: CHOOSE UP TO 2 SUPPORTER/STADIUM CARDS", 2)
	if main._should_bail(): return
	await main.show_message("RELIC HUNTER! ADDED " + str(found.size()) + " CARD(S) TO HAND!" if found.size() > 0 else "NO MATCHING CARDS IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Relic Hunter — found ", found.size())

# APRICORN MAKER (ecard3-121): search deck for up to 2 Trainer cards with "Ball" in their name
func effect_ecard3_apricorn_maker(is_opponent: bool) -> void:
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Trainer" and "Ball" in c.metadata.get("name","")
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "APRICORN MAKER: CHOOSE UP TO 2 BALL CARDS", 2)
	if main._should_bail(): return
	await main.show_message("APRICORN MAKER! ADDED " + str(found.size()) + " CARD(S) TO HAND!" if found.size() > 0 else "NO BALL CARDS IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Apricorn Maker — found ", found.size())

# DESERT SHAMAN (ecard3-123): shuffle your hand into your deck and draw 4; opponent does the same
func effect_ecard3_desert_shaman(is_opponent: bool) -> void:
	for side in [is_opponent, not is_opponent]:
		var hand = main.opponent_hand if side else main.player_hand
		var deck = main.opponent_deck if side else main.player_deck
		for c in hand.duplicate():
			hand.erase(c)
			c.current_location = "deck"
			deck.append(c)
		deck.shuffle()
		main.refresh_hand_display(side)
		main.update_deck_icon(side)
		await main.card_ops.draw_n(side, 4)
		if main._should_bail(): return
	await main.show_message("DESERT SHAMAN! BOTH PLAYERS SHUFFLED THEIR HAND AND DREW 4!")
	if main._should_bail(): return
	print("TRAINER: Desert Shaman")

# FAST BALL (ecard3-124): search deck for an Evolution card to hand
func effect_ecard3_fast_ball(is_opponent: bool) -> void:
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and not main.is_basic_pokemon(c)
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "FAST BALL: CHOOSE AN EVOLUTION CARD", 1)
	if main._should_bail(): return
	await main.show_message("FAST BALL! FOUND " + found[0].metadata.get("name","").to_upper() + "!" if found.size() > 0 else "NO EVOLUTION CARDS IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Fast Ball — found ", found.size())

# FISHERMAN (ecard3-125): choose up to 4 basic Energy cards from discard pile to hand
func effect_ecard3_fisherman(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var candidates = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if candidates.is_empty():
		await main.show_message("NO BASIC ENERGY IN YOUR DISCARD PILE!")
		if main._should_bail(): return
		return
	var want = min(4, candidates.size())
	var chosen: Array = []
	if is_opponent:
		for i in range(want): chosen.append(candidates[i])
	else:
		main.trainer_discard_selected.clear()
		main.trainer_discard_cards_needed = want
		main.trainer_discard_selection_active = true
		main.show_enlarged_array_selection_mode(candidates)
		main.header_label.text = "FISHERMAN: CHOOSE UP TO " + str(want) + " BASIC ENERGY"
		main.hint_label.text = "SELECT " + str(want) + " CARD(S)"
		main.action_button.text = str(want) + " MORE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_discard_selection_done
		main.trainer_discard_selection_active = false
		main.hide_selection_mode_display_main()
		if main._should_bail(): return
		chosen = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selected.clear()
	for c in chosen:
		discard.erase(c)
		c.current_location = "hand"
		hand.append(c)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("FISHERMAN! ADDED " + str(chosen.size()) + " ENERGY TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Fisherman — recovered ", chosen.size())

# FRIEND BALL (ecard3-126): choose 1 opponent Pokemon, search deck for a Baby/Basic/Evolution
# card of the same type to hand
func effect_ecard3_friend_ball(is_opponent: bool) -> void:
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_all: Array = []
	if opp_active != null: opp_all.append(opp_active)
	opp_all.append_array(opp_bench)
	if opp_all.is_empty():
		await main.show_message("OPPONENT HAS NO POKEMON!")
		if main._should_bail(): return
		return
	var target: card_object = opp_all[0]
	if not is_opponent and opp_all.size() > 1:
		target = await main.card_ops.prompt_select_card(opp_all, "FRIEND BALL", "Choose 1 of your opponent's Pokemon", "SELECT", false)
		if main._should_bail(): return
		if target == null: return
	var target_types = target.metadata.get("types", [])
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and not c.metadata.get("types",[]).filter(func(t): return t in target_types).is_empty()
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "FRIEND BALL: CHOOSE A MATCHING-TYPE POKEMON", 1)
	if main._should_bail(): return
	await main.show_message("FRIEND BALL! FOUND " + found[0].metadata.get("name","").to_upper() + "!" if found.size() > 0 else "NO MATCHING POKEMON IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Friend Ball — found ", found.size())

# HYPER POTION (ecard3-127): choose 1 own Pokemon, discard 1 or 2 basic Energy from it —
# 1 discarded heals up to 3 counters, 2 discarded heals up to 5 counters
func effect_ecard3_hyper_potion(is_opponent: bool) -> void:
	var all_own = build_field_pokemon_array(is_opponent)
	var candidates = all_own.filter(func(p): return p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0)
	if candidates.is_empty():
		await main.show_message("NO POKEMON WITH BASIC ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	var target: card_object = main.cpu_ai.cpu_pick_benefit_recipient(candidates, "heal")
	if target == null: target = candidates[0]
	if not is_opponent and candidates.size() > 1:
		target = await main.card_ops.prompt_select_card(candidates, "HYPER POTION", "Select a Pokemon to heal", "SELECT", false)
		if main._should_bail(): return
		if target == null: return
	var basics = target.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))
	var want = min(2, basics.size())
	if not is_opponent and want >= 2:
		var confirm_2 = await gym1_prompt_yes_no(target, "HYPER POTION", "Discard 2 basic Energy to heal up to 5? (No = discard 1 to heal up to 3)", "DISCARD 2", "DISCARD 1")
		if main._should_bail(): return
		want = 2 if confirm_2 else 1
	var discarded: Array = []
	for i in range(want):
		var pool = target.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e) and e not in discarded)
		if pool.is_empty(): break
		var chosen: card_object = pool[0]
		if is_opponent:
			for e in pool:
				if main.cpu_ai.cpu_rank_keep_value(e) < main.cpu_ai.cpu_rank_keep_value(chosen): chosen = e
		elif pool.size() > 1:
			chosen = await main.card_ops.prompt_select_card(pool, "HYPER POTION", "Select a basic Energy to discard", "DISCARD", false)
			if main._should_bail(): return
			if chosen == null: break
		discarded.append(chosen)
	if discarded.is_empty(): return
	for e in discarded:
		target.attached_energies.erase(e)
		main.card_ops.discard_energy_from_pokemon(e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	var heal_amount = 50 if discarded.size() >= 2 else 30
	await main.card_ops.heal_pokemon(target, heal_amount, is_opponent)
	if main._should_bail(): return
	await main.show_message("HYPER POTION! " + target.metadata.get("name","").to_upper() + " HEALED!")
	if main._should_bail(): return
	print("TRAINER: Hyper Potion — discarded ", discarded.size(), " healed up to ", heal_amount)

# LURE BALL (ecard3-128): flip 3 coins, for each heads recover an Evolution card from discard to hand
func effect_ecard3_lure_ball(is_opponent: bool) -> void:
	var heads = 0
	for i in range(3):
		if await main.flip_coin(true, is_opponent): heads += 1
	if main._should_bail(): return
	if heads == 0:
		await main.show_message("NO HEADS — NO EFFECT!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var recovered = 0
	for i in range(heads):
		var candidates = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and not main.is_basic_pokemon(c))
		if candidates.is_empty(): break
		var chosen: card_object = main.cpu_ai.cpu_pick_best_keep(candidates) if is_opponent else candidates[0]
		if not is_opponent and candidates.size() > 1:
			chosen = await main.card_ops.prompt_select_card(candidates, "LURE BALL", "Choose an Evolution card to recover (" + str(heads - recovered) + " remaining)", "RECOVER", false)
			if main._should_bail(): return
			if chosen == null: break
		await main.card_ops.recover_to_hand(chosen, is_opponent)
		if main._should_bail(): return
		recovered += 1
	await main.show_message(str(heads) + " HEADS! RECOVERED " + str(recovered) + " EVOLUTION CARD(S)!")
	if main._should_bail(): return
	print("TRAINER: Lure Ball — recovered ", recovered)

# ORACLE (ecard3-138): choose 2 cards from your deck, shuffle the rest, put the 2 chosen on top in any order
func effect_ecard3_oracle(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if deck.is_empty():
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var want = min(2, deck.size())
	var chosen: Array = []
	if is_opponent:
		var ranked = deck.duplicate()
		ranked.sort_custom(func(a, b): return _cpu_pokedex_priority(a) > _cpu_pokedex_priority(b))
		for i in range(want): chosen.append(ranked[i])
	else:
		main.trainer_discard_selected.clear()
		main.trainer_discard_cards_needed = want
		main.trainer_discard_selection_active = true
		main.show_enlarged_array_selection_mode(deck)
		main.header_label.text = "ORACLE: CHOOSE " + str(want) + " CARDS (SELECTION ORDER = TOP OF DECK ORDER)"
		main.hint_label.text = "SELECT " + str(want) + " CARD(S)"
		main.action_button.text = str(want) + " MORE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_discard_selection_done
		main.trainer_discard_selection_active = false
		main.hide_selection_mode_display_main()
		if main._should_bail(): return
		chosen = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selected.clear()
	for c in chosen:
		deck.erase(c)
	deck.shuffle()
	for i in range(chosen.size() - 1, -1, -1):
		deck.push_front(chosen[i])
	main.update_deck_icon(is_opponent)
	await main.show_message("ORACLE! PLACED " + str(chosen.size()) + " CARD(S) ON TOP OF THE DECK!")
	if main._should_bail(): return
	print("TRAINER: Oracle — stacked ", chosen.size())

# UNDERGROUND EXPEDITION (ecard3-140): look at bottom 4 cards, put 2 into hand, return the rest
# to the bottom in any order
func effect_ecard3_underground_expedition(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.is_empty():
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var count = min(4, deck.size())
	var bottom_cards: Array = []
	for i in range(deck.size() - count, deck.size()):
		bottom_cards.append(deck[i])
	await main.show_message("UNDERGROUND EXPEDITION: LOOKING AT BOTTOM " + str(count) + " CARDS!")
	if main._should_bail(): return
	var want = min(2, bottom_cards.size())
	var chosen: Array = []
	if is_opponent:
		var ranked = bottom_cards.duplicate()
		ranked.sort_custom(func(a, b): return _cpu_pokedex_priority(a) > _cpu_pokedex_priority(b))
		for i in range(want): chosen.append(ranked[i])
	else:
		main.trainer_discard_selected.clear()
		main.trainer_discard_cards_needed = want
		main.trainer_discard_selection_active = true
		main.show_enlarged_array_selection_mode(bottom_cards)
		main.header_label.text = "UNDERGROUND EXPEDITION: CHOOSE " + str(want) + " CARDS FOR YOUR HAND"
		main.hint_label.text = "SELECT " + str(want) + " CARD(S)"
		main.action_button.text = str(want) + " MORE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_discard_selection_done
		main.trainer_discard_selection_active = false
		main.hide_selection_mode_display_main()
		if main._should_bail(): return
		chosen = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selected.clear()
	for c in chosen:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("UNDERGROUND EXPEDITION! ADDED " + str(chosen.size()) + " CARD(S) TO HAND!")
	if main._should_bail(): return
	print("TRAINER: Underground Expedition — took ", chosen.size())

######################################################################################################################################################
######################################################### EX1 (RUBY & SAPPHIRE) TRAINERS ###############################################################
######################################################################################################################################################

func _register_ex1_trainers() -> void:
	_trainer_dispatch["ex1-80"] = func(c, opp): await effect_ecard1_energy_removal_2(opp)
	_trainer_dispatch["ex1-81"] = func(c, opp): await effect_ecard1_energy_restore(opp)
	_trainer_dispatch["ex1-82"] = func(c, opp): await effect_ecard2_energy_switch(opp)
	_trainer_dispatch["ex1-83"] = func(c, opp): await effect_ex1_lady_outing(opp)
	_trainer_dispatch["ex1-86"] = func(c, opp): await effect_poke_ball(opp)
	_trainer_dispatch["ex1-87"] = func(c, opp): await effect_ecard1_pokemon_reversal(opp)
	_trainer_dispatch["ex1-88"] = func(c, opp): await effect_ex1_pokenav(opp)
	_trainer_dispatch["ex1-89"] = func(c, opp): await effect_ex1_professor_birch(opp)
	_trainer_dispatch["ex1-90"] = func(c, opp): await effect_energy_search(opp)
	_trainer_dispatch["ex1-91"] = func(c, opp): await effect_potion(opp)
	_trainer_dispatch["ex1-92"] = func(c, opp): await effect_switch(opp)
	# ex1-84 (Lum Berry) / ex1-85 (Oran Berry) are Pokemon Tools — the attach itself is already
	# generic (is_attached_trainer() matches on the "Pokémon Tool" subtype). Their between-turns
	# effects are ex1_lum_berry_check() / ex1_oran_berry_check() below, called from Main's
	# inbetween_turn_checks alongside Healing Berry / Star Piece.

# LADY OUTING (ex1-83, Supporter): search deck for up to 3 DIFFERENT TYPES of basic Energy to
# hand. Enforced by pre-filtering the search pool to at most 1 card per Energy type, so any subset
# the player/CPU picks automatically satisfies "different types."
func effect_ex1_lady_outing(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var seen_types: Array = []
	var candidates: Array = []
	for c in deck:
		if c.metadata.get("supertype","") != "Energy" or "Basic" not in c.metadata.get("subtypes", []):
			continue
		var provided = main.get_energy_provided_by_card(c)
		if provided.is_empty(): continue
		var t = provided[0]
		if t in seen_types: continue
		seen_types.append(t)
		candidates.append(c)
	if candidates.is_empty():
		await main.show_message("LADY OUTING: NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		return
	var filter_fn = func(c): return c in candidates
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "LADY OUTING: CHOOSE UP TO 3 DIFFERENT BASIC ENERGY TYPES", 3)
	if main._should_bail(): return
	await main.show_message("LADY OUTING! ADDED " + str(found.size()) + " ENERGY CARD(S) TO HAND!" if found.size() > 0 else "NO MATCHING ENERGY FOUND!")
	if main._should_bail(): return
	print("TRAINER: Lady Outing — found ", found.size())

# POKENAV (ex1-88): look at the top 3 cards of the deck; choose a Basic Pokemon, Evolution card,
# or Energy card (i.e. anything but a Trainer) to hand; put the other 2 back on top in any order.
func effect_ex1_pokenav(is_opponent: bool) -> void:
	var top3 = main.card_ops.peek_top_n(is_opponent, 3)
	if top3.is_empty():
		await main.show_message("POKENAV: NO CARDS LEFT IN DECK!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var candidates = top3.filter(func(c): return c.metadata.get("supertype","") != "Trainer")
	var chosen: card_object = null
	if not candidates.is_empty():
		chosen = await main.card_ops.choose_card(candidates, is_opponent, "POKENAV", "Choose a Pokemon or Energy card from the top 3", "TAKE", false)
		if main._should_bail(): return
	var remaining = top3.duplicate()
	if chosen != null:
		remaining.erase(chosen)
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
	# Put the other cards back on top, preserving their original relative order
	for c in remaining:
		deck.erase(c)
	for i in range(remaining.size() - 1, -1, -1):
		deck.insert(0, remaining[i])
	main.update_deck_icon(is_opponent)
	if chosen != null:
		await main.show_message("POKENAV! ADDED " + chosen.metadata.get("name","").to_upper() + " TO HAND!")
	else:
		await main.show_message("POKENAV: NO MATCHING CARD FOUND!")
	if main._should_bail(): return
	print("TRAINER: PokeNav")

# PROFESSOR BIRCH (ex1-89, Supporter): draw cards from your deck until you have 6 in hand.
func effect_ex1_professor_birch(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var need = 6 - hand.size()
	if need <= 0:
		await main.show_message("PROFESSOR BIRCH: ALREADY HAVE 6 OR MORE CARDS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	need = min(need, deck.size())
	await main.card_ops.draw_n(is_opponent, need)
	if main._should_bail(): return
	await main.show_message("PROFESSOR BIRCH! DREW " + str(need) + " CARD(S)!")
	if main._should_bail(): return
	print("TRAINER: Professor Birch — drew ", need)

# LUM BERRY (ex1-84, Pokemon Tool): at any time between turns, both sides, if the holder is
# affected by any Special Condition, remove all of them and discard this Berry. Iterates
# get_all_pokemon_in_play() (Active + Bench) for both sides, matching Healing Berry's timing.
func ex1_lum_berry_check() -> void:
	for side in [false, true]:
		for p in main.card_ops.get_all_pokemon_in_play(side):
			if p.current_hp <= 0: continue
			var berry: card_object = null
			for ac in p.attached_cards:
				if ac.uid.to_lower() in ["ex1-84", "ex9-78"]:
					berry = ac
					break
			if berry == null: continue
			var has_condition = p.special_condition != "" or p.is_poisoned or p.is_burned
			if not has_condition: continue
			p.attached_cards.erase(berry)
			var discard = main.opponent_discard_pile if side else main.player_discard_pile
			berry.current_location = "discard"
			discard.append(berry)
			main.clear_all_statuses(p, side)
			display_attached_trainer_cards(side)
			main.update_discard_pile_display(side)
			await main.show_message("LUM BERRY! " + p.metadata.get("name","").to_upper() + " CURED AND THE BERRY WAS DISCARDED!")
			if main._should_bail(): return

# ORAN BERRY (ex1-85, Pokemon Tool): at any time between turns, both sides, if the holder has at
# least 2 damage counters, remove 2 and discard this Berry. Same iteration/timing as Lum Berry.
func ex1_oran_berry_check() -> void:
	for side in [false, true]:
		for p in main.card_ops.get_all_pokemon_in_play(side):
			if p.current_hp <= 0: continue
			if p.get_damage_counters() < 2: continue
			var berry: card_object = null
			for ac in p.attached_cards:
				if ac.uid.to_lower() in ["ex1-85", "ex9-80"]:
					berry = ac
					break
			if berry == null: continue
			p.attached_cards.erase(berry)
			var discard = main.opponent_discard_pile if side else main.player_discard_pile
			berry.current_location = "discard"
			discard.append(berry)
			p.current_hp = min(p.get_max_hp(), p.current_hp + 20)
			main.display_hp_circles_above_align(p, side)
			display_attached_trainer_cards(side)
			main.update_discard_pile_display(side)
			await main.show_message("ORAN BERRY! " + p.metadata.get("name","").to_upper() + " HEALED AND THE BERRY WAS DISCARDED!")
			if main._should_bail(): return

######################################################################################################################################################
############################################################ EX2 (SANDSTORM) TRAINERS ################################################################
######################################################################################################################################################
# Claw Fossil (ex2-90) / Mysterious Fossil (ex2-91) / Root Fossil (ex2-92) need no dispatch entry —
# they carry an HP field + "as if it were a Basic" rule, so is_bench_token_trainer() auto-detects
# them and resolve_bench_token_trainer() places them on the Bench. Their Poké-Bodies live in
# Powers_And_Bodies_Effects.gd.
func _register_ex2_trainers() -> void:
	_trainer_dispatch["ex2-86"] = func(c, opp): await effect_ex2_double_full_heal(opp)
	_trainer_dispatch["ex2-87"] = func(c, opp): await effect_ex2_lanettes_net_search(opp)
	_trainer_dispatch["ex2-88"] = func(c, opp): await effect_ex2_rare_candy(opp)
	_trainer_dispatch["ex2-89"] = func(c, opp): await effect_ex2_wallys_training(opp)

# DOUBLE FULL HEAL (ex2-86, Item): remove all Special Conditions from each of your Active Pokemon.
func effect_ex2_double_full_heal(is_opponent: bool) -> void:
	for p in main.card_ops.get_active_pokemon(is_opponent):
		main.clear_all_statuses(p, is_opponent)
	await main.show_message("DOUBLE FULL HEAL! ALL SPECIAL CONDITIONS REMOVED!")
	if main._should_bail(): return
	print("TRAINER: Double Full Heal")

# LANETTE'S NET SEARCH (ex2-87, Supporter): search deck for up to 3 different types of Basic
# Pokemon (excluding Baby Pokemon), to hand. Pre-filters the pool to 1 card per type so any subset
# picked satisfies "different types" (same technique as Lady Outing).
func effect_ex2_lanettes_net_search(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var seen_types: Array = []
	var candidates: Array = []
	for c in deck:
		if not main.is_basic_pokemon(c):
			continue
		if "Baby" in c.metadata.get("subtypes", []):
			continue
		var types = c.metadata.get("types", [])
		if types.is_empty():
			continue
		var t = types[0]
		if t in seen_types:
			continue
		seen_types.append(t)
		candidates.append(c)
	if candidates.is_empty():
		await main.show_message("LANETTE'S NET SEARCH: NO BASIC POKEMON IN DECK!")
		if main._should_bail(): return
		return
	var filter_fn = func(c): return c in candidates
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "LANETTE'S NET SEARCH: CHOOSE UP TO 3 DIFFERENT-TYPE BASICS", 3)
	if main._should_bail(): return
	await main.show_message("LANETTE'S NET SEARCH! ADDED " + str(found.size()) + " POKEMON TO HAND!" if found.size() > 0 else "NO MATCHING POKEMON FOUND!")
	if main._should_bail(): return
	print("TRAINER: Lanette's Net Search — found ", found.size())

# Shared evolution: put evo_card (from source_array) onto target, carrying damage/energy/pre-evolution
# chain. Mirrors Main.perform_evolution's core so it works from hand (Rare Candy) or deck (Wally's).
func _ex2_do_evolution(evo_card: card_object, target: card_object, is_opponent: bool, source_array: Array) -> void:
	var max_hp_old = int(target.metadata.get("hp", "0"))
	var damage_taken = max_hp_old - target.current_hp
	var max_hp_new = int(evo_card.metadata.get("hp", "0"))
	evo_card.current_hp = max(1, max_hp_new - damage_taken)
	evo_card.attached_energies = target.attached_energies.duplicate()
	target.attached_energies.clear()
	evo_card.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	target.attached_pre_evolutions.clear()
	evo_card.attached_pre_evolutions.append(target)
	evo_card.placed_on_field_this_turn = true
	source_array.erase(evo_card)
	evo_card.current_location = target.current_location
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if target == active:
		if is_opponent:
			main.opponent_active_pokemon = evo_card
		else:
			main.player_active_pokemon = evo_card
	else:
		var idx = bench.find(target)
		if idx != -1:
			bench[idx] = evo_card
	main.clear_all_statuses(target, is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.refresh_hand_display(is_opponent)

# RARE CANDY (ex2-88, Item): choose 1 of your Basic Pokemon in play; if you have a card that
# evolves from it in hand, evolve it (counts as evolving that Pokemon).
func effect_ex2_rare_candy(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var valid_basics: Array = []
	for p in main.card_ops.get_all_pokemon_in_play(is_opponent):
		if not main.is_basic_pokemon(p) or p.placed_on_field_this_turn:
			continue
		for h in hand:
			if h.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(h, p):
				valid_basics.append(p)
				break
	if valid_basics.is_empty():
		await main.show_message("RARE CANDY: NO BASIC POKEMON HAS A MATCHING EVOLUTION IN HAND!")
		if main._should_bail(): return
		return
	var target = await main.card_ops.choose_card(valid_basics, is_opponent, "RARE CANDY", "Choose a Basic Pokemon to evolve", "SELECT", false)
	if main._should_bail(): return
	if target == null:
		return
	var evos = hand.filter(func(h): return h.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(h, target))
	if evos.is_empty():
		return
	var rank = func(c): return float(int(c.metadata.get("hp","0")))
	var evo_card = await main.card_ops.choose_card(evos, is_opponent, "RARE CANDY", "Choose an Evolution card from your hand", "EVOLVE", false, rank)
	if main._should_bail(): return
	if evo_card == null:
		return
	await _ex2_do_evolution(evo_card, target, is_opponent, hand)
	await main.show_message("RARE CANDY! " + target.metadata.get("name","").to_upper() + " EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("TRAINER: Rare Candy")

# WALLY'S TRAINING (ex2-89, Supporter): search your deck for a card that evolves from your Active
# Pokemon and put it on your Active (counts as evolving that Pokemon).
func effect_ex2_wallys_training(is_opponent: bool) -> void:
	var actives = main.card_ops.get_active_pokemon(is_opponent)
	if actives.is_empty():
		await main.show_message("WALLY'S TRAINING: NO ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	var active = actives[0]
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var evos = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(c, active))
	if evos.is_empty():
		await main.show_message("WALLY'S TRAINING: NO EVOLUTION FOR " + active.metadata.get("name","").to_upper() + " IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var rank = func(c): return float(int(c.metadata.get("hp","0")))
	var evo_card = await main.card_ops.choose_card(evos, is_opponent, "WALLY'S TRAINING", "Choose an Evolution for your Active Pokemon", "EVOLVE", false, rank, true)
	if main._should_bail(): return
	if evo_card != null:
		await _ex2_do_evolution(evo_card, active, is_opponent, deck)
		await main.show_message("WALLY'S TRAINING! " + active.metadata.get("name","").to_upper() + " EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	print("TRAINER: Wally's Training")

######################################################################################################################################################
############################################################ EX3 (EX DRAGON) TRAINERS ################################################################
######################################################################################################################################################
# Balloon Berry (ex3-82) / Buffer Piece (ex3-83) are Pokémon Tools — the attach itself is generic
# (is_attached_trainer() matches the "Pokémon Tool" subtype). Balloon Berry reuses the existing
# neo3 Balloon Berry free-retreat machinery (check_balloon_berry_retreat_free / consume_balloon_berry,
# both extended to ex3-82). Buffer Piece's -20 damage is a damage-modifier hook (_hook_ex3_buffer_piece)
# and its expiry is ex3_buffer_piece_check() below. High/Low Pressure System (ex3-85/86) are Stadiums,
# installed generically by resolve_stadium_trainer; their passive effects live in get_retreat_cost
# (High Pressure) and the stadium HP refresh (Low Pressure). So only the two Supporters and the Item
# need dispatch entries here.
func _register_ex3_trainers() -> void:
	_trainer_dispatch["ex3-84"] = func(c, opp): await effect_ex3_energy_recycle_system(opp)
	_trainer_dispatch["ex3-87"] = func(c, opp): await effect_ex3_mr_brineys_compassion(opp)
	_trainer_dispatch["ex3-88"] = func(c, opp): await effect_ex3_tv_reporter(opp)

# ENERGY RECYCLE SYSTEM (ex3-84, Item): either take 1 basic Energy from your discard to your hand,
# or shuffle 3 basic Energy from your discard into your deck.
func effect_ex3_energy_recycle_system(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		await main.show_message("ENERGY RECYCLE SYSTEM: NO BASIC ENERGY IN YOUR DISCARD PILE!")
		if main._should_bail(): return
		return
	# CPU always takes the higher-value option (1 Energy to hand). Player may choose to shuffle 3 back.
	var take_to_hand = true
	if not is_opponent and basics.size() >= 3:
		var anchor = main.player_active_pokemon
		take_to_hand = await gym1_prompt_yes_no(anchor, "ENERGY RECYCLE SYSTEM", "Take 1 Energy to your hand? (No = shuffle 3 into your deck)", "TAKE 1", "SHUFFLE 3")
		if main._should_bail(): return
	if take_to_hand:
		var chosen: card_object = null
		if is_opponent:
			chosen = main.cpu_ai.cpu_pick_best_keep(basics)
		else:
			chosen = await main.card_ops.choose_card(basics, is_opponent, "ENERGY RECYCLE SYSTEM", "Choose a basic Energy to put into your hand", "TAKE", false)
			if main._should_bail(): return
			if chosen == null: chosen = basics[0]
		await main.card_ops.recover_to_hand(chosen, is_opponent)
		if main._should_bail(): return
		await main.show_message("ENERGY RECYCLE SYSTEM! TOOK 1 BASIC ENERGY TO HAND!")
		if main._should_bail(): return
	else:
		var deck = main.opponent_deck if is_opponent else main.player_deck
		var moved = 0
		for i in range(3):
			var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
			if pool.is_empty(): break
			var chosen2: card_object = null
			if is_opponent:
				chosen2 = pool[0]
				for e in pool:
					if main.cpu_ai.cpu_rank_keep_value(e) < main.cpu_ai.cpu_rank_keep_value(chosen2): chosen2 = e
			else:
				chosen2 = await main.card_ops.choose_card(pool, is_opponent, "ENERGY RECYCLE SYSTEM", "Choose a basic Energy to shuffle into your deck (" + str(3 - moved) + " left)", "SHUFFLE", moved >= 1)
				if main._should_bail(): return
				if chosen2 == null: break
			discard.erase(chosen2)
			chosen2.current_location = "deck"
			deck.append(chosen2)
			moved += 1
		deck.shuffle()
		main.update_discard_pile_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("ENERGY RECYCLE SYSTEM! SHUFFLED " + str(moved) + " BASIC ENERGY INTO YOUR DECK!")
		if main._should_bail(): return
	print("TRAINER: Energy Recycle System")

# MR. BRINEY'S COMPASSION (ex3-87, Supporter): return 1 of your Pokemon in play (excluding
# Pokemon-ex) and all cards attached to it to your hand.
func effect_ex3_mr_brineys_compassion(is_opponent: bool) -> void:
	var pool = main.card_ops.get_all_pokemon_in_play(is_opponent).filter(func(c): return not main.is_ex_pokemon(c))
	if pool.is_empty():
		await main.show_message("MR. BRINEY'S COMPASSION: NO ELIGIBLE POKEMON!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		# CPU: prefer returning a heavily-damaged non-ex Pokemon to save it (most damage counters).
		chosen = pool[0]
		for c in pool:
			if c.get_damage_counters() > chosen.get_damage_counters():
				chosen = c
		# Don't bother if nothing is damaged and it's the lone Active with no bench.
		if chosen.get_damage_counters() == 0:
			var own_bench = main.opponent_bench if is_opponent else main.player_bench
			if own_bench.is_empty():
				await main.show_message("MR. BRINEY'S COMPASSION: NOTHING WORTH RETURNING!")
				if main._should_bail(): return
				return
	else:
		chosen = await main.card_ops.choose_card(pool, is_opponent, "MR. BRINEY'S COMPASSION", "Choose 1 of your Pokemon (not an ex) to return to your hand", "RETURN", true)
		if main._should_bail(): return
		if chosen == null:
			return
	var was_active = (chosen == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon))
	await main.attack_effects.gym1_return_pokemon_to_hand(chosen, is_opponent)
	if main._should_bail(): return
	await main.show_message("MR. BRINEY'S COMPASSION! RETURNED " + chosen.metadata.get("name","").to_upper() + " AND ITS CARDS TO HAND!")
	if main._should_bail(): return
	# If we returned the Active Pokemon, promote a Benched Pokemon into the empty Active spot.
	if was_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return
	print("TRAINER: Mr. Briney's Compassion")

# TV REPORTER (ex3-88, Supporter): draw 3 cards, then discard any 1 card from your hand.
func effect_ex3_tv_reporter(is_opponent: bool) -> void:
	await main.card_ops.draw_n(is_opponent, 3)
	if main._should_bail(): return
	await main.card_ops.discard_from_hand(is_opponent, 1)
	if main._should_bail(): return
	await main.show_message("TV REPORTER! DREW 3 CARDS AND DISCARDED 1!")
	if main._should_bail(): return
	print("TRAINER: TV Reporter")

# LOW PRESSURE SYSTEM (ex3-86, Stadium): each Grass/Lightning Pokemon in play gets +10 HP. Applied
# via max_hp_override in the shared stadium HP refresh (refresh_rockets_hideout_hp).
func low_pressure_bonus_hp(pokemon: card_object) -> int:
	if pokemon == null:
		return 0
	if not main.is_stadium_in_play(StadiumIds.LOW_PRESSURE_SYSTEM):
		return 0
	var eff_types = pokemon.get_effective_types()
	if "Grass" in eff_types or "Lightning" in eff_types:
		return 10
	return 0

# BUFFER PIECE (ex3-83) expiry: called at the end of every turn. The tool is played during your turn
# (first end-of-turn tick = 1) and discarded at the end of your opponent's following turn (tick = 2).
func ex3_buffer_piece_check() -> void:
	for side in [false, true]:
		for p in main.card_ops.get_all_pokemon_in_play(side):
			for ac in p.attached_cards.duplicate():
				if ac.uid.to_lower() not in ["ex3-83", "ex15-72"]:
					continue
				ac.ex3_buffer_piece_turns += 1
				if ac.ex3_buffer_piece_turns >= 2:
					p.attached_cards.erase(ac)
					var discard = main.opponent_discard_pile if side else main.player_discard_pile
					ac.current_location = "discard"
					discard.append(ac)
					display_attached_trainer_cards(side)
					main.update_discard_pile_display(side)
					await main.show_message("BUFFER PIECE WAS DISCARDED!")
					if main._should_bail(): return

######################################################################################################################################################
###################################### EX4 (TEAM MAGMA VS TEAM AQUA) TRAINERS ########################################################################
######################################################################################################################################################
# Tools: Strength Charm (ex4-74) reuses the ecard1-150 damage hook + discard. Team Aqua/Magma Belt
# (ex4-76 / ex4-81) attach generically ("Pokémon Tool" subtype); their between-turn auto-evolve is
# ex4_belt_check(). TMs (ex4-79 / ex4-84) attach generically; their attacks are in Attack_Effects.gd.
# Stadiums (ex4-78 / ex4-83) route via resolve_stadium_trainer; their effects are the get_retreat_cost
# hook (Main) and ex4_team_magma_hideout_trigger() below.
func _register_ex4_trainers() -> void:
	_trainer_dispatch["ex4-69"] = func(c, opp): await effect_ex4_schemer(opp, "Team Aqua")
	_trainer_dispatch["ex4-70"] = func(c, opp): await effect_ex4_schemer(opp, "Team Magma")
	_trainer_dispatch["ex4-71"] = func(c, opp): await effect_ex4_archie(opp)
	_trainer_dispatch["ex4-72"] = func(c, opp): await effect_ex4_dual_ball(opp)
	_trainer_dispatch["ex4-73"] = func(c, opp): await effect_ex4_maxie(opp)
	_trainer_dispatch["ex4-75"] = func(c, opp): await effect_ex4_team_ball(opp, "Team Aqua")
	_trainer_dispatch["ex4-77"] = func(c, opp): await effect_ex4_conspirator(opp, "Team Aqua")
	_trainer_dispatch["ex4-80"] = func(c, opp): await effect_ex4_team_ball(opp, "Team Magma")
	_trainer_dispatch["ex4-82"] = func(c, opp): await effect_ex4_conspirator(opp, "Team Magma")
	_trainer_dispatch["ex4-85"] = func(c, opp): await effect_ex4_warp_point(opp)

# SCHEMER (ex4-69 Aqua / ex4-70 Magma, Supporter): discard 1 Pokemon from hand, then draw 3 (4 if
# the discarded Pokemon has this Team's name).
func effect_ex4_schemer(is_opponent: bool, team: String) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var pokes = hand.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
	var bonus = false
	if not pokes.is_empty():
		var chosen: card_object = null
		if is_opponent:
			for c in pokes:
				if team in c.metadata.get("name",""):
					chosen = c
					break
			if chosen == null:
				# No bonus-team Pokemon in hand — discard the least valuable Pokemon, not just the first.
				var priority = cpu_get_discard_priority(pokes, 1)
				chosen = priority[0] if not priority.is_empty() else pokes[0]
		else:
			chosen = await main.card_ops.choose_card(pokes, is_opponent, team.to_upper() + " SCHEMER", "Discard 1 Pokemon from your hand", "DISCARD", false)
			if main._should_bail(): return
			if chosen == null: chosen = pokes[0]
		bonus = team in chosen.metadata.get("name","")
		await main.card_ops.send_to_discard(chosen, is_opponent, true)
		if main._should_bail(): return
	var draw = 4 if bonus else 3
	await main.card_ops.draw_n(is_opponent, draw)
	if main._should_bail(): return
	await main.show_message(team.to_upper() + " SCHEMER! DREW " + str(draw) + " CARDS!")
	if main._should_bail(): return
	print("TRAINER: ", team, " Schemer — drew ", draw)

# Shared: place a chosen Team-named Pokemon from `candidates` onto the Bench, treating it as a Basic.
# If it is a Stage 2 Pokemon, it comes in with 2 damage counters. Removes the card from whichever of
# the side's deck/hand/discard it lives in.
func _ex4_bench_team_pokemon(is_opponent: bool, candidates: Array, header: String) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	if candidates.is_empty():
		await main.show_message(header + ": NO MATCHING POKEMON FOUND!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = candidates[0]
		for c in candidates:
			if int(c.metadata.get("hp","0")) > int(chosen.metadata.get("hp","0")): chosen = c
	else:
		chosen = await main.card_ops.choose_card(candidates, is_opponent, header, "Choose a Pokemon to put on your Bench", "SELECT", true)
		if main._should_bail(): return
		if chosen == null: return
	for arr in [main.opponent_deck if is_opponent else main.player_deck, main.opponent_hand if is_opponent else main.player_hand, main.opponent_discard_pile if is_opponent else main.player_discard_pile]:
		if chosen in arr:
			arr.erase(chosen)
			break
	chosen.current_hp = chosen.get_max_hp()
	if "Stage 2" in chosen.metadata.get("subtypes", []):
		chosen.current_hp = max(1, chosen.current_hp - 20)
	main.card_ops.place_on_bench(chosen, is_opponent)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message(header + "! " + chosen.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
	if main._should_bail(): return

# ARCHIE (ex4-71, Supporter): search deck for a Team Aqua Pokemon, put it on the Bench (as a Basic).
func effect_ex4_archie(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Team Aqua" in c.metadata.get("name",""))
	await _ex4_bench_team_pokemon(is_opponent, pool, "ARCHIE")
	if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	print("TRAINER: Archie")

# MAXIE (ex4-73, Supporter): search hand or discard for a Team Magma Pokemon, put it on the Bench.
func effect_ex4_maxie(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var pool: Array = []
	for c in hand + discard:
		if c.metadata.get("supertype","") == "Pokémon" and "Team Magma" in c.metadata.get("name",""):
			pool.append(c)
	await _ex4_bench_team_pokemon(is_opponent, pool, "MAXIE")
	if main._should_bail(): return
	print("TRAINER: Maxie")

# DUAL BALL (ex4-72, Item): flip 2 coins; for each heads, search deck for a Basic Pokemon to hand.
func effect_ex4_dual_ball(is_opponent: bool) -> void:
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent): heads += 1
		if main._should_bail(): return
	await main.show_message("DUAL BALL! GOT " + str(heads) + " HEADS!")
	if main._should_bail(): return
	if heads > 0:
		var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]), "DUAL BALL: CHOOSE UP TO " + str(heads) + " BASIC POKEMON", heads)
		if main._should_bail(): return
		await main.show_message("DUAL BALL! ADDED " + str(found.size()) + " BASIC POKEMON TO HAND!")
		if main._should_bail(): return
	print("TRAINER: Dual Ball — heads ", heads)

# TEAM AQUA/MAGMA BALL (ex4-75 / ex4-80, Item): flip a coin — heads search any Team X Pokemon,
# tails search a Basic Team X Pokemon — put it into your hand.
func effect_ex4_team_ball(is_opponent: bool, team: String) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var basic_only = not coin
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and team in c.metadata.get("name","") and (not basic_only or "Basic" in c.metadata.get("subtypes",[]))
	var label = "HEADS! SEARCH ANY " + team.to_upper() + " POKEMON" if coin else "TAILS! SEARCH A BASIC " + team.to_upper() + " POKEMON"
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, team.to_upper() + " BALL: " + label, 1)
	if main._should_bail(): return
	await main.show_message(team.to_upper() + " BALL! ADDED " + str(found.size()) + " POKEMON TO HAND!")
	if main._should_bail(): return
	print("TRAINER: ", team, " Ball — heads=", coin)

# TEAM AQUA/MAGMA CONSPIRATOR (ex4-77 / ex4-82, Supporter): search deck for up to 2 in any
# combination of Basic Team X Pokemon and basic Energy, put them into your hand.
func effect_ex4_conspirator(is_opponent: bool, team: String) -> void:
	var filter_fn = func(c): return (c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]) and team in c.metadata.get("name","")) or (c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]))
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, team.to_upper() + " CONSPIRATOR: CHOOSE UP TO 2", 2)
	if main._should_bail(): return
	await main.show_message(team.to_upper() + " CONSPIRATOR! ADDED " + str(found.size()) + " CARD(S) TO HAND!")
	if main._should_bail(): return
	print("TRAINER: ", team, " Conspirator — found ", found.size())

# WARP POINT (ex4-85, Item): the opponent switches their Active with a Benched Pokemon (they choose);
# then you switch your Active with a Benched Pokemon (you choose).
func effect_ex4_warp_point(is_opponent: bool) -> void:
	await main.attack_effects.apply_force_switch({"chooser": "defender"}, is_opponent)
	if main._should_bail(): return
	await effect_switch(is_opponent)
	if main._should_bail(): return
	print("TRAINER: Warp Point")

# EX4-83 Team Magma Hideout: when a player plays a Basic (non-Team-Magma) Pokemon from hand, put 1
# damage counter on it. Called from the bench-from-hand play sites (Main + CPU_AI), like Minefield Gym.
func ex4_team_magma_hideout_trigger(pokemon: card_object, is_opponent: bool) -> void:
	if not main.is_stadium_in_play(StadiumIds.TEAM_MAGMA_HIDEOUT):
		return
	if pokemon == null or not main.is_basic_pokemon(pokemon) or pokemon.is_bench_token:
		return
	if "Team Magma" in pokemon.metadata.get("name",""):
		return
	pokemon.current_hp = max(0, pokemon.current_hp - 10)
	main.display_hp_circles_above_align(pokemon, is_opponent)
	await main.show_message("TEAM MAGMA HIDEOUT! 1 DAMAGE COUNTER ON " + pokemon.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# TEAM AQUA/MAGMA BELT (ex4-76 / ex4-81, Pokemon Tool): between turns, if the Active holder can
# evolve, search the deck for a card that evolves from it, evolve it (counts as evolving), then
# discard the Belt. Modeled on ecard3_star_piece_check.
func ex4_belt_check() -> void:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active == null or active.current_hp <= 0:
			continue
		var belt: card_object = null
		for ac in active.attached_cards:
			if ac.uid.to_lower() in ["ex4-76", "ex4-81"]:
				belt = ac
				break
		if belt == null:
			continue
		var deck = main.opponent_deck if side else main.player_deck
		var candidates = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and main.can_evolve_from(c, active))
		if candidates.is_empty():
			continue
		var do_it = side
		if not side:
			do_it = await gym1_prompt_yes_no(active, "POKEMON BELT", "Search your deck to evolve " + active.metadata.get("name","").to_upper() + "?", "EVOLVE", "SKIP")
			if main._should_bail(): return
		if not do_it:
			continue
		var evo_card: card_object = main.cpu_ai.cpu_pick_best_keep(candidates) if side else candidates[0]
		if not side and candidates.size() > 1:
			evo_card = await main.card_ops.prompt_select_card(candidates, "POKEMON BELT", "Choose an Evolution card", "EVOLVE", false)
			if main._should_bail(): return
			if evo_card == null: continue
		await _ex2_do_evolution(evo_card, active, side, deck)
		active.attached_cards.erase(belt)
		var discard = main.opponent_discard_pile if side else main.player_discard_pile
		belt.current_location = "discard"
		discard.append(belt)
		deck.shuffle()
		main.update_deck_icon(side)
		main.update_discard_pile_display(side)
		display_attached_trainer_cards(side)
		await main.show_message("POKEMON BELT! " + active.metadata.get("name","").to_upper() + " EVOLVED AND THE BELT WAS DISCARDED!")
		if main._should_bail(): return
		print("TOOL: Team Belt — evolved via deck search")

# ══════════════════════════════════════════════════════════════════════════════
#  EX5 (EX Hidden Legends) — Trainers
#  Stadiums (Ancient Tomb ex5-87 / Desert Ruins ex5-88 / Island Cave ex5-89 /
#  Magnetic Storm ex5-91) resolve via the generic Stadium path; their passive effects are wired into
#  StadiumIds + the relevant core hooks (weakness/resistance/between-turns/energy-attach). The three
#  Ancient Technical Machines (ex5-84/85/86) attach via the generic Technical Machine subtype path;
#  their attacks (Ice/Stone/Steel Generator) are dispatched in Attack_Effects.gd.
# ══════════════════════════════════════════════════════════════════════════════
func _register_ex6_trainers() -> void:
	# Reprints routed to existing effect functions
	_trainer_dispatch["ex6-87"] = func(c, opp): await effect_ecard1_bills_maintenance(opp)          # Bill's Maintenance
	_trainer_dispatch["ex6-89"] = func(c, opp): await effect_ecard1_energy_removal_2(opp)            # Energy Removal 2
	_trainer_dispatch["ex6-90"] = func(c, opp): await effect_ecard2_energy_switch(opp)               # Energy Switch
	_trainer_dispatch["ex6-93"] = func(c, opp): await effect_ex5_life_herb(opp)                       # Life Herb
	_trainer_dispatch["ex6-95"] = func(c, opp): await effect_poke_ball(opp)                           # Poké Ball
	_trainer_dispatch["ex6-97"] = func(c, opp): await effect_ecard1_pokemon_reversal(opp)             # Pokémon Reversal
	_trainer_dispatch["ex6-98"] = func(c, opp): await effect_ecard1_professor_oaks_research(opp)      # Prof. Oak's Research
	_trainer_dispatch["ex6-99"] = func(c, opp): await effect_neo1_super_scoop_up(opp)                 # Super Scoop Up
	_trainer_dispatch["ex6-101"] = func(c, opp): await effect_potion(opp)                             # Potion
	_trainer_dispatch["ex6-102"] = func(c, opp): await effect_switch(opp)                             # Switch
	# New ex6 Trainers
	_trainer_dispatch["ex6-88"] = func(c, opp): await effect_ex6_celios_network(opp)                  # Celio's Network
	_trainer_dispatch["ex6-92"] = func(c, opp): await effect_ex6_great_ball(opp)                      # Great Ball
	_trainer_dispatch["ex6-96"] = func(c, opp): await effect_ex6_handy909(opp)                        # PokéDex HANDY909
	_trainer_dispatch["ex6-100"] = func(c, opp): await effect_ex6_vs_seeker(opp)                      # VS Seeker
	# ex6-91 EXP.ALL (Pokémon Tool), ex6-94 Mt. Moon (Stadium), ex6-103 Multi Energy resolve via their
	# own paths (attached-trainer / stadium / special-energy) — no _trainer_dispatch entry needed.

# CELIO'S NETWORK (ex6-88, Supporter): search your deck for a Basic Pokemon or Evolution card
# (excluding Pokemon-ex) and put it into your hand. Shuffle afterward.
func effect_ex6_celios_network(is_opponent: bool) -> void:
	var filter_fn = func(c):
		if c.metadata.get("supertype","") != "Pokémon": return false
		if main.is_ex_pokemon(c): return false
		var st = c.metadata.get("subtypes", [])
		return "Basic" in st or "Stage 1" in st or "Stage 2" in st
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "CELIO'S NETWORK: CHOOSE A POKEMON", 1)
	if main._should_bail(): return
	await main.show_message("CELIO'S NETWORK! ADDED " + str(found.size()) + " CARD TO HAND!" if found.size() > 0 else "NO ELIGIBLE POKEMON IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Celio's Network")

# GREAT BALL (ex6-92, Item): search your deck for a Basic Pokemon (excluding Pokemon-ex) and put it
# onto your Bench. Shuffle afterward.
func effect_ex6_great_ball(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("GREAT BALL: BENCH IS FULL!")
		if main._should_bail(): return
		return
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes", []) and not main.is_ex_pokemon(c))
	if pool.is_empty():
		await main.show_message("GREAT BALL: NO ELIGIBLE BASIC POKEMON!")
		deck.shuffle()
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		var best = -1
		for c in pool:
			var hp = int(c.metadata.get("hp","0"))
			if hp > best:
				best = hp
				chosen = c
	else:
		chosen = await main.card_ops.prompt_select_card(pool, "GREAT BALL: CHOOSE A POKEMON", "Select a Basic Pokemon to put on your Bench", "SELECT", true, true)
		if main._should_bail(): return
	if chosen != null and bench.size() < main.get_max_bench_size():
		deck.erase(chosen)
		chosen.current_hp = chosen.get_max_hp()
		main.card_ops.place_on_bench(chosen, is_opponent)
		await main.show_message("GREAT BALL! " + chosen.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	print("TRAINER: Great Ball")

# POKEDEX HANDY909 (ex6-96, Item): shuffle your deck, look at the top 6 cards, then put them back on
# top of your deck in any order. Reuses the base Pokedex reorder UI mechanism.
func effect_ex6_handy909(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	var look_count = min(6, deck.size())
	if look_count == 0:
		await main.show_message("HANDY909: DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top_cards: Array = []
	for i in range(look_count):
		top_cards.append(deck[i])
	if is_opponent:
		# CPU: order best cards to the top for its next draws.
		top_cards.sort_custom(func(a, b): return _cpu_pokedex_priority(a) > _cpu_pokedex_priority(b))
		for i in range(top_cards.size()):
			deck[i] = top_cards[i]
		await main.show_message("HANDY909: OPPONENT REARRANGED THE TOP OF ITS DECK.")
		if main._should_bail(): return
	else:
		main.pokedex_cards = top_cards.duplicate()
		main.pokedex_reorder_result.clear()
		main.trainer_reorder_active = true
		main.show_enlarged_array_selection_mode(main.pokedex_cards)
		main.header_label.text = "HANDY909 - CLICK CARDS IN ORDER"
		main.hint_label.text = "Click cards in the order you want them (top of deck first)"
		main.action_button.text = "0/" + str(look_count) + " SELECTED"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_reorder_done
		if main._should_bail(): return
		main.trainer_reorder_active = false
		main.hide_selection_mode_display_main()
		for i in range(main.pokedex_reorder_result.size()):
			deck[i] = main.pokedex_reorder_result[i]
		main.pokedex_cards.clear()
		main.pokedex_reorder_result.clear()
	print("TRAINER: HANDY909")

# VS SEEKER (ex6-100, Item): search your discard pile for a Supporter card and put it into your hand.
func effect_ex6_vs_seeker(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Trainer" and "Supporter" in c.metadata.get("subtypes", []))
	if pool.is_empty():
		await main.show_message("VS SEEKER: NO SUPPORTER IN THE DISCARD PILE!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = main.cpu_ai.cpu_pick_best_keep(pool)
	else:
		chosen = await main.card_ops.prompt_select_card(pool, "VS SEEKER: CHOOSE A SUPPORTER", "Select a Supporter card to return to your hand", "TAKE", true, true)
		if main._should_bail(): return
	if chosen != null:
		await main.card_ops.recover_to_hand(chosen, is_opponent)
		if main._should_bail(): return
		await main.show_message("VS SEEKER! RETURNED " + chosen.metadata.get("name","").to_upper() + " TO YOUR HAND!")
		if main._should_bail(): return
	print("TRAINER: VS Seeker")

func _register_ex5_trainers() -> void:
	_trainer_dispatch["ex5-90"] = func(c, opp): await effect_ex5_life_herb(opp)
	_trainer_dispatch["ex5-92"] = func(c, opp): await effect_ex5_stevens_advice(opp)

func _register_ex5_validations() -> void:
	# STEVEN'S ADVICE (ex5-92): can't be played if you have more than 7 cards in hand (including it).
	_validator_dispatch["ex5-92"] = func(c, opp):
		var hand = main.opponent_hand if opp else main.player_hand
		return "You have too many cards in hand to play Steven's Advice!" if hand.size() > 7 else ""

# LIFE HERB (ex5-90, Item): flip a coin. If heads, choose 1 of your Pokemon (excluding Pokemon-ex) and
# remove all Special Conditions and up to 6 damage counters from it.
func effect_ex5_life_herb(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("LIFE HERB — TAILS! NOTHING HAPPENS.")
		if main._should_bail(): return
		return
	var pool = main.card_ops.get_all_pokemon_in_play(is_opponent).filter(func(p): return not main.is_ex_pokemon(p))
	if pool.is_empty():
		await main.show_message("LIFE HERB: NO ELIGIBLE POKEMON!")
		if main._should_bail(): return
		return
	var target: card_object
	if is_opponent:
		target = pool[0]
		for p in pool:
			if (p.get_max_hp() - p.current_hp) > (target.get_max_hp() - target.current_hp): target = p
	else:
		target = await main.card_ops.choose_card(pool, false, "LIFE HERB", "Choose a Pokemon to heal and cure", "SELECT", false)
		if main._should_bail(): return
		if target == null: return
	main.card_ops.clear_statuses(target, is_opponent)
	await main.card_ops.heal_pokemon(target, 60, is_opponent)
	if main._should_bail(): return
	await main.show_message("LIFE HERB! REMOVED ALL SPECIAL CONDITIONS AND 6 DAMAGE COUNTERS!")
	if main._should_bail(): return
	print("TRAINER: Life Herb")

# STEVEN'S ADVICE (ex5-92, Supporter): draw a number of cards up to the number of the opponent's
# Pokemon in play.
func effect_ex5_stevens_advice(is_opponent: bool) -> void:
	var n = main.card_ops.get_all_pokemon_in_play(not is_opponent).size()
	if n > 0:
		await main.card_ops.draw_n(is_opponent, n)
		if main._should_bail(): return
	await main.show_message("STEVEN'S ADVICE! DREW " + str(n) + " CARDS!")
	if main._should_bail(): return
	print("TRAINER: Steven's Advice — drew ", n)

# EX5 Island Cave (ex5-89 Stadium): whenever any player attaches an Energy card from hand to a Water,
# Fighting, or Metal Pokemon, remove any Special Conditions from that Pokemon. Called from both energy
# attach paths (Main player path + CPU_AI).
func ex5_island_cave_on_attach(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return
	if not main.is_stadium_in_play(StadiumIds.ISLAND_CAVE):
		return
	var types = pokemon.metadata.get("types", [])
	if "Water" in types or "Fighting" in types or "Metal" in types:
		main.clear_all_statuses(pokemon, is_opponent)

# ════════════════════════════════════════════════════════════════════════════════
# EX7 — EX TEAM ROCKET RETURNS  (Trainers)
# ════════════════════════════════════════════════════════════════════════════════

func _register_ex7_trainers() -> void:
	_trainer_dispatch["ex7-83"]  = func(c, opp): await effect_ecard1_copycat(opp)               # Copycat (reprint)
	_trainer_dispatch["ex7-84"]  = func(c, opp): await effect_ex7_pokemon_retriever(opp)        # Pokémon Retriever (RSM)
	_trainer_dispatch["ex7-85"]  = func(c, opp): await effect_ex7_pow_hand_extension(opp)       # Pow! Hand Extension (RSM)
	_trainer_dispatch["ex7-86"]  = func(c, opp): await effect_ex7_rockets_admin(opp)            # Rocket's Admin. (Supporter)
	_trainer_dispatch["ex7-88"]  = func(c, opp): await effect_ex7_rockets_mission(opp)          # Rocket's Mission (Supporter)
	_trainer_dispatch["ex7-89"]  = func(c, opp): await effect_ex7_rockets_poke_ball(opp)        # Rocket's Poké Ball (Item)
	_trainer_dispatch["ex7-91"]  = func(c, opp): await effect_ex7_surprise_time_machine(opp)    # Surprise! Time Machine (RSM)
	_trainer_dispatch["ex7-92"]  = func(c, opp): await effect_ex7_swoop_teleporter(opp)         # Swoop! Teleporter (RSM)
	_trainer_dispatch["ex7-93"]  = func(c, opp): await effect_ex7_venture_bomb(opp)             # Venture Bomb (RSM)
	_trainer_dispatch["ex7-111"] = func(c, opp): await effect_here_comes_team_rocket(opp)       # Here Comes Team Rocket! (reprint)
	# ex7-87 Rocket's Hideout & ex7-90 Rocket's Tricky Gym are Stadiums (resolve via resolve_stadium_trainer;
	# HP bonus / granted Feint Attack handled by rockets_hideout_bonus_hp and get_attacks_for_card).
	# ex7-94 Dark Metal Energy & ex7-95 R Energy resolve via the special-energy path.

# POKÉMON RETRIEVER (ex7-84, Rocket's Secret Machine): search your discard for Basic/Evolution cards;
# either put 1 into your hand, or shuffle a combination of 3 back into your deck.
func effect_ex7_pokemon_retriever(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
	if pool.is_empty():
		await main.show_message("POKÉMON RETRIEVER: NO POKÉMON IN THE DISCARD PILE!")
		if main._should_bail(): return
		return
	var take_to_hand = true
	if not is_opponent and pool.size() >= 3:
		take_to_hand = await gym1_prompt_yes_no(main.player_active_pokemon, "POKÉMON RETRIEVER", "Put 1 Pokémon into your hand? (No = shuffle 3 into your deck.)", "TAKE 1", "SHUFFLE 3")
		if main._should_bail(): return
	if take_to_hand:
		var pick: card_object = null
		if is_opponent:
			pick = main.cpu_ai.cpu_pick_best_keep(pool)
		else:
			pick = await main.card_ops.choose_card(pool, false, "POKÉMON RETRIEVER", "Take a Pokémon to your hand", "TAKE", false, Callable(), true)
			if main._should_bail(): return
			if pick == null: pick = pool[0]
		discard.erase(pick)
		await main.card_ops.recover_to_hand(pick, is_opponent)
		if main._should_bail(): return
	else:
		var shuffled = 0
		while shuffled < 3 and not pool.is_empty():
			var pick2: card_object = null
			if is_opponent:
				pick2 = pool[0]
			else:
				pick2 = await main.card_ops.choose_card(pool, false, "POKÉMON RETRIEVER", "Shuffle into deck (" + str(shuffled + 1) + " of 3)", "SHUFFLE", false, Callable(), true)
				if main._should_bail(): return
				if pick2 == null: pick2 = pool[0]
			discard.erase(pick2)
			pool.erase(pick2)
			pick2.current_location = "deck"
			deck.append(pick2)
			shuffled += 1
		deck.shuffle()
		main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("POKÉMON RETRIEVER RESOLVED!")
	if main._should_bail(): return
	print("TRAINER: Pokémon Retriever")

# POW! HAND EXTENSION (ex7-85, Rocket's Secret Machine): usable only if you have more Prize cards left
# than your opponent. Either move 1 Energy from the Defending Pokémon to another of the opponent's
# Pokémon, or switch 1 of the opponent's Benched Pokémon with the Defending Pokémon (opponent chooses).
func effect_ex7_pow_hand_extension(is_opponent: bool) -> void:
	var my_prizes = main.opponent_prize_cards.size() if is_opponent else main.player_prize_cards.size()
	var their_prizes = main.player_prize_cards.size() if is_opponent else main.opponent_prize_cards.size()
	if my_prizes <= their_prizes:
		await main.show_message("POW! HAND EXTENSION: YOU NEED MORE PRIZES LEFT THAN YOUR OPPONENT!")
		if main._should_bail(): return
		return
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	# Decide which mode. CPU prefers the disruptive gust when the opponent has a bench.
	var do_move_energy = true
	var can_move = defender != null and not defender.attached_energies.is_empty() and not opp_bench.is_empty()
	var can_gust = not opp_bench.is_empty()
	if is_opponent:
		do_move_energy = can_move and opp_bench.is_empty()
	elif can_move and can_gust:
		do_move_energy = await gym1_prompt_yes_no(main.player_active_pokemon, "POW! HAND EXTENSION", "Move an Energy on the Defender? (No = drag up a Benched Pokémon.)", "MOVE ENERGY", "SWITCH")
		if main._should_bail(): return
	elif can_move:
		do_move_energy = true
	else:
		do_move_energy = false
	if do_move_energy and can_move:
		var energy: card_object = defender.attached_energies[0]
		var dest: card_object = null
		if is_opponent:
			dest = opp_bench[0]
		else:
			dest = await main.card_ops.choose_card(opp_bench, is_opponent, "POW! HAND EXTENSION", "Move an Energy to which Benched Pokémon?", "SELECT", false, Callable(), true)
			if main._should_bail(): return
			if dest == null: dest = opp_bench[0]
		defender.attached_energies.erase(energy)
		dest.attached_energies.append(energy)
		main.display_active_pokemon_energies(not is_opponent)
		main.display_pokemon(not is_opponent)
		await main.show_message("POW! HAND EXTENSION! MOVED AN ENERGY!")
		if main._should_bail(): return
	elif can_gust:
		# The player using the card chooses which Benched Pokémon is dragged up (attacker chooser).
		var eff = {"type": "force_switch", "target": "defender", "chooser": "attacker", "flip": "none"}
		await main.attack_effects.apply_force_switch(eff, is_opponent)
		if main._should_bail(): return
	else:
		await main.show_message("POW! HAND EXTENSION: NOTHING TO DO!")
		if main._should_bail(): return
	print("TRAINER: Pow! Hand Extension")

# ROCKET'S ADMIN. (ex7-86, Supporter): each player shuffles his or her hand into the deck, then draws
# up to the number of his or her remaining Prize cards. You draw first.
func effect_ex7_rockets_admin(is_opponent: bool) -> void:
	for who in [is_opponent, not is_opponent]:
		var hand = main.opponent_hand if who else main.player_hand
		var deck = main.opponent_deck if who else main.player_deck
		for card in hand.duplicate():
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
		deck.shuffle()
		main.refresh_hand_display(who)
		main.update_deck_icon(who)
		var prizes = (main.opponent_prize_cards if who else main.player_prize_cards).size()
		var to_draw = min(prizes, deck.size())
		if to_draw > 0:
			await main.card_ops.draw_n(who, to_draw)
			if main._should_bail(): return
	await main.show_message("ROCKET'S ADMIN.! BOTH PLAYERS REFRESHED THEIR HANDS!")
	if main._should_bail(): return
	print("TRAINER: Rocket's Admin.")

# ROCKET'S MISSION (ex7-88, Supporter): discard a card from your hand, then draw 3 cards. If you
# discarded a Pokémon that has "Dark" or "Rocket's" in its name, draw 4 cards instead.
func effect_ex7_rockets_mission(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.is_empty():
		await main.show_message("ROCKET'S MISSION: NO CARD TO DISCARD!")
		if main._should_bail(): return
		return
	var pick: card_object = null
	if is_opponent:
		# CPU discards the least useful card (prefer a non-Dark/non-Rocket's Energy or duplicate); simplest:
		# discard the first card, but prefer a Dark/Rocket's Pokémon if that yields the +1 bonus.
		for c in hand:
			if c.metadata.get("supertype","") == "Pokémon" and ("Dark" in c.metadata.get("name","") or "Rocket's" in c.metadata.get("name","")):
				pick = c
				break
		if pick == null: pick = hand[0]
	else:
		pick = await main.card_ops.choose_card(hand, false, "ROCKET'S MISSION", "Discard a card (a Dark/Rocket's Pokémon draws 4)", "DISCARD", false, Callable(), true)
		if main._should_bail(): return
		if pick == null: pick = hand[0]
	var is_bonus = pick.metadata.get("supertype","") == "Pokémon" and ("Dark" in pick.metadata.get("name","") or "Rocket's" in pick.metadata.get("name",""))
	await main.card_ops.send_to_discard(pick, is_opponent, false)
	if main._should_bail(): return
	var n = 4 if is_bonus else 3
	await main.card_ops.draw_n(is_opponent, n)
	if main._should_bail(): return
	await main.show_message("ROCKET'S MISSION! DREW " + str(n) + " CARDS!")
	if main._should_bail(): return
	print("TRAINER: Rocket's Mission")

# ROCKET'S POKÉ BALL (ex7-89, Item): search your deck for a Pokémon that has "Dark" in its name and
# put it into your hand. Shuffle.
func effect_ex7_rockets_poke_ball(is_opponent: bool) -> void:
	var filter_fn = func(c): return c.metadata.get("supertype","") == "Pokémon" and "Dark" in c.metadata.get("name","")
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "ROCKET'S POKÉ BALL: CHOOSE A 'DARK' POKÉMON", 1)
	if main._should_bail(): return
	await main.show_message("ROCKET'S POKÉ BALL! ADDED " + str(found.size()) + " CARD TO HAND!" if found.size() > 0 else "NO 'DARK' POKÉMON IN DECK!")
	if main._should_bail(): return
	print("TRAINER: Rocket's Poké Ball")

# VENTURE BOMB (ex7-93, Rocket's Secret Machine): flip a coin. If heads, put 1 damage counter on 1 of
# the opponent's Pokémon; if tails, put 1 damage counter on 1 of your Pokémon.
func effect_ex7_venture_bomb(is_opponent: bool) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var target_is_opp = (coin != is_opponent)  # heads → opponent's side; tails → your side
	var pool = main.card_ops.get_all_pokemon_in_play(target_is_opp)
	if pool.is_empty():
		return
	var target: card_object = null
	# The player who used the card chooses their side's target; on the opponent's side the affected
	# player chooses. Simplify: CPU auto-picks; player picks whenever the target is on the player side.
	if target_is_opp:
		# Heads for player use → target opponent; CPU (opp use) tails → target player. Chooser is the card user.
		if is_opponent:
			target = pool[0]
			for c in pool:
				if c.current_hp < target.current_hp: target = c
		else:
			target = await main.card_ops.choose_card(pool, is_opponent, "VENTURE BOMB", "Put 1 damage counter on which Pokémon?", "SELECT", false, Callable(), true)
			if main._should_bail(): return
			if target == null: target = pool[0]
	else:
		# Target is the card-user's own side.
		if is_opponent:
			target = pool[0]
			for c in pool:
				if c.current_hp > target.current_hp: target = c
		else:
			target = await main.card_ops.choose_card(pool, false, "VENTURE BOMB", "Put 1 damage counter on which of your Pokémon?", "SELECT", false, Callable(), true)
			if main._should_bail(): return
			if target == null: target = pool[0]
	target.current_hp = max(0, target.current_hp - 10)
	main.display_hp_circles_above_align(target, target_is_opp)
	await main.show_message(("HEADS" if coin else "TAILS") + "! 1 DAMAGE COUNTER PLACED!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("TRAINER: Venture Bomb")

# SURPRISE! TIME MACHINE (ex7-91, Rocket's Secret Machine): choose 1 of your Evolved Pokémon, remove
# its highest Stage Evolution card and shuffle it into your deck (devolve by 1 stage). If it remains in
# play, search your deck for a card that evolves from it and evolve it. Shuffle.
func effect_ex7_surprise_time_machine(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var evolved = main.card_ops.get_all_pokemon_in_play(is_opponent).filter(func(c): return not c.attached_pre_evolutions.is_empty())
	if evolved.is_empty():
		await main.show_message("SURPRISE! TIME MACHINE: NO EVOLVED POKÉMON!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		target = evolved[0]
	else:
		target = await main.card_ops.choose_card(evolved, false, "SURPRISE! TIME MACHINE", "Choose an Evolved Pokémon to devolve by 1 stage", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if target == null: return
	# Devolve one stage: the immediate pre-evolution becomes the field Pokémon; the removed top card is
	# shuffled into the deck.
	var devolve_to: card_object = target.attached_pre_evolutions.back()
	target.attached_pre_evolutions.erase(devolve_to)
	# Carry over attachments and remaining chain onto the pre-evolution.
	devolve_to.attached_energies = target.attached_energies.duplicate()
	devolve_to.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	devolve_to.attached_cards = target.attached_cards.duplicate()
	var max_hp_old = int(target.metadata.get("hp", "0"))
	var damage_taken = max_hp_old - target.current_hp
	var new_max = int(devolve_to.metadata.get("hp", "0"))
	devolve_to.current_hp = max(10, new_max - damage_taken)
	devolve_to.current_location = target.current_location
	# Clear the top card's carried state and shuffle it into the deck.
	target.attached_energies.clear()
	target.attached_pre_evolutions.clear()
	target.attached_cards.clear()
	target.current_location = "deck"
	deck.append(target)
	main.clear_all_statuses(devolve_to, is_opponent)
	# Replace in the correct slot.
	var active_ref = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if target == active_ref:
		if is_opponent: main.opponent_active_pokemon = devolve_to
		else: main.player_active_pokemon = devolve_to
	else:
		var b = main.opponent_bench if is_opponent else main.player_bench
		var idx = b.find(target)
		if idx != -1: b[idx] = devolve_to
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SURPRISE! TIME MACHINE! " + target.metadata.get("name","").to_upper() + " DEVOLVED!")
	if main._should_bail(): return
	# Re-evolve from the deck: find a card that evolves from the new form.
	var evo_pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and c.metadata.get("evolvesFrom","") == devolve_to.metadata.get("name",""))
	if evo_pool.is_empty():
		return
	var evo_pick: card_object = null
	if is_opponent:
		evo_pick = evo_pool[0]
	else:
		evo_pick = await main.card_ops.choose_card(evo_pool, false, "SURPRISE! TIME MACHINE", "Choose an Evolution to put on " + devolve_to.metadata.get("name",""), "EVOLVE", true, Callable(), true)
		if main._should_bail(): return
	if evo_pick != null:
		await _ex2_do_evolution(evo_pick, devolve_to, is_opponent, deck)
		deck.shuffle()
		main.update_deck_icon(is_opponent)
		await main.show_message("EVOLVED INTO " + evo_pick.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	print("TRAINER: Surprise! Time Machine")

# SWOOP! TELEPORTER (ex7-92, Rocket's Secret Machine): search your deck for a Basic Pokémon (excluding
# ex) and switch it with 1 of your Basic Pokémon (excluding ex) in play, carrying over all attachments,
# damage, Special Conditions, and effects. Discard the replaced Basic. Shuffle.
func effect_ex7_swoop_teleporter(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var in_play_basics = main.card_ops.get_all_pokemon_in_play(is_opponent).filter(func(c): return c.attached_pre_evolutions.is_empty() and "Basic" in c.metadata.get("subtypes", []) and not main.is_ex_pokemon(c))
	if in_play_basics.is_empty():
		await main.show_message("SWOOP! TELEPORTER: NO BASIC POKÉMON IN PLAY!")
		if main._should_bail(): return
		return
	var deck_basics = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes", []) and not main.is_ex_pokemon(c))
	if deck_basics.is_empty():
		await main.show_message("SWOOP! TELEPORTER: NO BASIC POKÉMON IN DECK!")
		if main._should_bail(): return
		return
	var target: card_object = null
	var new_basic: card_object = null
	if is_opponent:
		target = in_play_basics[0]
		new_basic = deck_basics[0]
	else:
		target = await main.card_ops.choose_card(in_play_basics, false, "SWOOP! TELEPORTER", "Choose a Basic Pokémon in play to switch out", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if target == null: return
		new_basic = await main.card_ops.choose_card(deck_basics, false, "SWOOP! TELEPORTER", "Choose a Basic Pokémon from your deck to switch in", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if new_basic == null: return
	# Carry over state onto the new Basic.
	new_basic.attached_energies = target.attached_energies.duplicate()
	new_basic.attached_cards = target.attached_cards.duplicate()
	var max_hp_old = int(target.metadata.get("hp", "0"))
	var damage_taken = max_hp_old - target.current_hp
	var new_max = int(new_basic.metadata.get("hp", "0"))
	new_basic.current_hp = max(10, new_max - damage_taken)
	new_basic.special_condition = target.special_condition
	new_basic.is_poisoned = target.is_poisoned
	new_basic.poison_damage = target.poison_damage
	new_basic.is_burned = target.is_burned
	new_basic.current_location = target.current_location
	new_basic.placed_on_field_this_turn = target.placed_on_field_this_turn
	# Replace in the slot.
	var active_ref = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if target == active_ref:
		if is_opponent: main.opponent_active_pokemon = new_basic
		else: main.player_active_pokemon = new_basic
	else:
		var b = main.opponent_bench if is_opponent else main.player_bench
		var idx = b.find(target)
		if idx != -1: b[idx] = new_basic
	# The replaced Basic goes to the discard; the new one leaves the deck.
	deck.erase(new_basic)
	target.attached_energies.clear()
	target.attached_cards.clear()
	target.current_location = "discard"
	discard.append(target)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	main.update_status_icons(new_basic, is_opponent)
	await main.show_message("SWOOP! TELEPORTER! SWITCHED IN " + new_basic.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("TRAINER: Swoop! Teleporter")

# DETOUR (Magby ex7-24 attack support): re-resolve the effect of a Supporter you played this turn.
func ex7_detour_reuse_supporter(is_opponent: bool) -> void:
	var played = opponent_played_supporter_this_turn if is_opponent else player_played_supporter_this_turn
	if not played:
		await main.show_message("DETOUR: NO SUPPORTER IN PLAY!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var sup: card_object = null
	for i in range(discard.size() - 1, -1, -1):
		if "Supporter" in discard[i].metadata.get("subtypes", []):
			sup = discard[i]
			break
	if sup == null:
		await main.show_message("DETOUR: NO SUPPORTER IN PLAY!")
		if main._should_bail(): return
		return
	await main.show_message("DETOUR! RE-USING " + sup.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await resolve_standard_trainer(sup, is_opponent)
	if main._should_bail(): return
	print("TRAINER: Detour re-used " + sup.metadata.get("name",""))

# ════════════════════════════════════════════════════════════════════════════════════════════════
# ex10 (EX Unseen Forces) trainers. Most are reprints — reuse existing effect functions with the ex10
# UID. The 6 Pokémon Tools (Curse Powder/Energy Root/Fluffy Berry/Protective Orb/Sitrus Berry/Solid
# Rage) attach generically; their passive effects live in Powers_And_Bodies (pre-KO / body hooks /
# between-turns) and in get_max_hp / get_retreat_cost / has_no_weakness_body / is_power_blocked.
# ════════════════════════════════════════════════════════════════════════════════════════════════
func _register_ex10_trainers() -> void:
	_trainer_dispatch["ex10-81"] = func(c, opp): await effect_ex10_energy_recycle_system(opp)   # Energy Recycle System (Item)
	_trainer_dispatch["ex10-82"] = func(c, opp): await effect_ecard1_energy_removal_2(opp)       # Energy Removal 2 (Item)
	_trainer_dispatch["ex10-84"] = func(c, opp): await effect_ecard2_energy_switch(opp)          # Energy Switch (Item)
	_trainer_dispatch["ex10-86"] = func(c, opp): await effect_ex10_marys_request(opp)            # Mary's Request (Supporter)
	_trainer_dispatch["ex10-87"] = func(c, opp): await effect_poke_ball(opp)                     # Poké Ball (Item)
	_trainer_dispatch["ex10-88"] = func(c, opp): await effect_ecard1_pokemon_reversal(opp)       # Pokémon Reversal (Item)
	_trainer_dispatch["ex10-89"] = func(c, opp): await effect_ecard1_professor_elms_training_method(opp)  # Professor Elm's Training Method (Supporter)
	_trainer_dispatch["ex10-93"] = func(c, opp): await effect_ecard1_warp_point(opp)             # Warp Point (Item)
	_trainer_dispatch["ex10-94"] = func(c, opp): await effect_energy_search(opp)                 # Energy Search (Item)
	_trainer_dispatch["ex10-95"] = func(c, opp): await effect_potion(opp)                        # Potion (Item)

# ENERGY RECYCLE SYSTEM (ex10-81, Item): search your discard pile for basic Energy cards. Either put 1
# into your hand, OR shuffle 3 back into your deck.
func effect_ex10_energy_recycle_system(is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]))
	if basics.is_empty():
		await main.show_message("ENERGY RECYCLE SYSTEM: NO BASIC ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
		return
	# Choose the mode: 1 → hand, or 3 → shuffle into deck.
	var take_to_hand := true
	if is_opponent:
		take_to_hand = true   # CPU keeps the Energy accessible.
	elif basics.size() >= 3:
		take_to_hand = await gym1_prompt_yes_no(main.player_active_pokemon, "ENERGY RECYCLE SYSTEM", "Put 1 basic Energy into your HAND, or shuffle 3 into your DECK?", "1 → HAND", "3 → DECK")
		if main._should_bail(): return
	if take_to_hand:
		var pick: card_object = main.cpu_ai.cpu_pick_best_keep(basics) if is_opponent else await main.card_ops.choose_card(basics, false, "ENERGY RECYCLE SYSTEM", "Put which basic Energy into your hand?", "TAKE", false, Callable(), true)
		if main._should_bail(): return
		if pick == null: pick = basics[0]
		await main.card_ops.recover_to_hand(pick, is_opponent)
		if main._should_bail(): return
		await main.show_message("ENERGY RECYCLE SYSTEM! PUT A BASIC ENERGY INTO YOUR HAND!")
		if main._should_bail(): return
	else:
		var deck = main.opponent_deck if is_opponent else main.player_deck
		var moved = 0
		for i in range(3):
			var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]))
			if pool.is_empty(): break
			var pick2: card_object
			if is_opponent:
				pick2 = pool[0]
				for e in pool:
					if main.cpu_ai.cpu_rank_keep_value(e) < main.cpu_ai.cpu_rank_keep_value(pick2): pick2 = e
			else:
				pick2 = await main.card_ops.choose_card(pool, false, "ENERGY RECYCLE SYSTEM", "Shuffle which basic Energy into your deck? (" + str(i+1) + " of 3)", "SELECT", i > 0, Callable(), true)
			if main._should_bail(): return
			if pick2 == null: break
			discard.erase(pick2); pick2.current_location = "deck"; deck.append(pick2); moved += 1
		deck.shuffle()
		main.update_deck_icon(is_opponent); main.update_discard_pile_display(is_opponent)
		await main.show_message("ENERGY RECYCLE SYSTEM! SHUFFLED " + str(moved) + " BASIC ENERGY INTO YOUR DECK!")
		if main._should_bail(): return

# MARY'S REQUEST (ex10-86, Supporter): draw a card; if you have no Stage 2 Evolved Pokémon in play,
# draw 2 more cards.
func effect_ex10_marys_request(is_opponent: bool) -> void:
	var has_stage2 = main.card_ops.get_all_pokemon_in_play(is_opponent).any(func(p): return "Stage 2" in p.metadata.get("subtypes", []))
	var count = 1 if has_stage2 else 3
	await main.card_ops.draw_n(is_opponent, count)
	if main._should_bail(): return
	await main.show_message("MARY'S REQUEST! DREW " + str(count) + " CARD(S)!")
	if main._should_bail(): return

# ════════════════════════════════════════════════════════════════════════════════════════════════
# EX11 (EX Delta Species) trainers. Holon Research Tower (ex11-94) and Holon Ruins (ex11-96) are
# Stadiums that auto-route to resolve_stadium_trainer; their passive effects live in
# get_energy_provided_by_card / holon_ruins_offer_draw. Master Ball / Super Scoop Up / Potion /
# Switch reuse existing reprint effects.
# ════════════════════════════════════════════════════════════════════════════════════════════════
func _register_ex11_trainers() -> void:
	_trainer_dispatch["ex11-89"] = func(c, opp): await effect_ex11_dual_ball(opp)            # Dual Ball (Item)
	_trainer_dispatch["ex11-90"] = func(c, opp): await effect_ex11_great_ball(opp)           # Great Ball (Item)
	_trainer_dispatch["ex11-91"] = func(c, opp): await effect_ex11_holon_farmer(opp)         # Holon Farmer (Supporter)
	_trainer_dispatch["ex11-92"] = func(c, opp): await effect_ex11_holon_lass(opp)           # Holon Lass (Supporter)
	_trainer_dispatch["ex11-93"] = func(c, opp): await effect_ex11_holon_mentor(opp)         # Holon Mentor (Supporter)
	_trainer_dispatch["ex11-95"] = func(c, opp): await effect_ex11_holon_researcher(opp)     # Holon Researcher (Supporter)
	_trainer_dispatch["ex11-97"] = func(c, opp): await effect_ex11_holon_scientist(opp)      # Holon Scientist (Supporter)
	_trainer_dispatch["ex11-98"] = func(c, opp): await effect_ex11_holon_transceiver(opp)    # Holon Transceiver (Item)
	_trainer_dispatch["ex11-99"] = func(c, opp): await effect_ex8_master_ball(opp)           # Master Ball (Item)
	_trainer_dispatch["ex11-100"] = func(c, opp): await effect_neo1_super_scoop_up(opp)      # Super Scoop Up (Item)
	_trainer_dispatch["ex11-101"] = func(c, opp): await effect_potion(opp)                   # Potion (Item)
	_trainer_dispatch["ex11-102"] = func(c, opp): await effect_switch(opp)                   # Switch (Item)

func _register_ex11_validations() -> void:
	# Holon supporters cost "discard a card from your hand" — need at least 1 other card in hand.
	for uid in ["ex11-91", "ex11-92", "ex11-93", "ex11-95", "ex11-97"]:
		_validator_dispatch[uid] = func(c, opp):
			var hand = main.opponent_hand if opp else main.player_hand
			return "" if hand.any(func(x): return x != c) else "You must discard a card to play this Supporter!"

# Pay the Holon supporter cost: discard 1 card from hand (the Supporter itself is already discarded).
func _ex11_pay_discard_cost(is_opponent: bool) -> bool:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.is_empty():
		return false
	if not is_opponent:
		await main.show_message("DISCARD A CARD FROM YOUR HAND TO PLAY THIS SUPPORTER.")
		if main._should_bail(): return true
	var paid = await main.card_ops.discard_from_hand(is_opponent, 1)
	return paid.size() >= 1

# DUAL BALL (ex11-89, Item): flip 2 coins. For each heads, search your deck for a Basic Pokemon → hand.
func effect_ex11_dual_ball(is_opponent: bool) -> void:
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent): heads += 1
		if main._should_bail(): return
	await main.show_message("DUAL BALL! " + str(heads) + " HEADS!")
	if main._should_bail(): return
	if heads == 0:
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return main.is_basic_pokemon(c), "DUAL BALL: CHOOSE A BASIC POKEMON", heads)
	if main._should_bail(): return
	await main.show_message("DUAL BALL! ADDED " + str(found.size()) + " BASIC POKEMON TO HAND!")
	if main._should_bail(): return

# GREAT BALL (ex11-90, Item): search your deck for a Basic Pokemon (excluding Pokemon-ex) onto your Bench.
func effect_ex11_great_ball(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("YOUR BENCH IS FULL!")
		if main._should_bail(): return
		return
	var pool = deck.filter(func(c): return main.is_basic_pokemon(c) and not main.is_ex_pokemon(c))
	if pool.is_empty():
		await main.show_message("NO BASIC POKEMON IN YOUR DECK!")
		deck.shuffle(); main.update_deck_icon(is_opponent)
		if main._should_bail(): return
		return
	var chosen: card_object = main.cpu_ai.cpu_pick_best_keep(pool) if is_opponent else await main.card_ops.choose_card(pool, false, "GREAT BALL", "Choose a Basic Pokemon to put on your Bench", "SELECT", false, Callable(), true)
	if main._should_bail(): return
	if chosen == null: chosen = pool[0]
	deck.erase(chosen)
	main.card_ops.place_on_bench(chosen, is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("GREAT BALL! PUT " + chosen.metadata.get("name","").to_upper() + " ON YOUR BENCH!")
	if main._should_bail(): return

# HOLON FARMER (ex11-91, Supporter): discard a card; then put up to 3 basic Energy and any combination
# of up to 3 Basic Pokemon / Evolution cards from your discard pile on top of your deck, then shuffle.
func effect_ex11_holon_farmer(is_opponent: bool) -> void:
	if not await _ex11_pay_discard_cost(is_opponent):
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var moved = 0
	# Up to 3 basic Energy.
	for i in range(3):
		var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
		if pool.is_empty(): break
		var pick: card_object = main.cpu_ai.cpu_pick_best_keep(pool) if is_opponent else await main.card_ops.choose_card(pool, false, "HOLON FARMER", "Return a basic Energy to your deck (" + str(i+1) + " of up to 3, cancel to stop)", "SELECT", true, Callable(), true)
		if main._should_bail(): return
		if pick == null: break
		discard.erase(pick); pick.current_location = "deck"; deck.append(pick); moved += 1
	# Up to 3 Basic Pokemon or Evolution cards.
	for i in range(3):
		var pool2 = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
		if pool2.is_empty(): break
		var pick2: card_object = main.cpu_ai.cpu_pick_best_keep(pool2) if is_opponent else await main.card_ops.choose_card(pool2, false, "HOLON FARMER", "Return a Pokemon to your deck (" + str(i+1) + " of up to 3, cancel to stop)", "SELECT", true, Callable(), true)
		if main._should_bail(): return
		if pick2 == null: break
		discard.erase(pick2); pick2.current_location = "deck"; deck.append(pick2); moved += 1
	deck.shuffle()
	main.update_deck_icon(is_opponent); main.update_discard_pile_display(is_opponent)
	await main.show_message("HOLON FARMER! RETURNED " + str(moved) + " CARD(S) TO YOUR DECK!")
	if main._should_bail(): return

# HOLON LASS (ex11-92, Supporter): discard a card; count the total Prize cards left (both players), look
# at that many cards from the top of your deck, put any number of Energy into your hand, the rest back on top.
func effect_ex11_holon_lass(is_opponent: bool) -> void:
	if not await _ex11_pay_discard_cost(is_opponent):
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var total_prizes = main.player_prize_cards.size() + main.opponent_prize_cards.size()
	var look = min(total_prizes, deck.size())
	if look <= 0:
		await main.show_message("HOLON LASS: NO CARDS TO LOOK AT!")
		if main._should_bail(): return
		return
	var top = main.card_ops.peek_top_n(is_opponent, look)
	var energies = top.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var taken = 0
	if is_opponent:
		for e in energies:
			deck.erase(e); e.current_location = "hand"; hand.append(e); taken += 1
	else:
		if not energies.is_empty():
			for e in energies:
				var yes = await gym1_prompt_yes_no(main.player_active_pokemon, "HOLON LASS", "Put " + e.metadata.get("name","").to_upper() + " into your hand?", "YES", "NO")
				if main._should_bail(): return
				if yes:
					deck.erase(e); e.current_location = "hand"; hand.append(e); taken += 1
	deck.shuffle()
	main.update_deck_icon(is_opponent); main.refresh_hand_display(is_opponent)
	await main.show_message("HOLON LASS! PUT " + str(taken) + " ENERGY INTO YOUR HAND!")
	if main._should_bail(): return

# HOLON MENTOR (ex11-93, Supporter): discard a card; search your deck for up to 3 Basic Pokemon that each
# have 100 HP or less → hand.
func effect_ex11_holon_mentor(is_opponent: bool) -> void:
	if not await _ex11_pay_discard_cost(is_opponent):
		if main._should_bail(): return
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return main.is_basic_pokemon(c) and int(c.metadata.get("hp","0")) <= 100, "HOLON MENTOR: CHOOSE UP TO 3 BASIC POKEMON (100 HP OR LESS)", 3)
	if main._should_bail(): return
	await main.show_message("HOLON MENTOR! ADDED " + str(found.size()) + " BASIC POKEMON TO HAND!")
	if main._should_bail(): return

# HOLON RESEARCHER (ex11-95, Supporter): discard a card; search your deck for a Metal Energy OR a Basic
# Pokemon / Evolution card that has δ on its card → hand.
func effect_ex11_holon_researcher(is_opponent: bool) -> void:
	if not await _ex11_pay_discard_cost(is_opponent):
		if main._should_bail(): return
		return
	var filter_fn = func(c):
		if c.metadata.get("supertype","") == "Energy" and "Metal" in main.get_energy_provided_by_card(c):
			return true
		return c.metadata.get("supertype","") == "Pokémon" and c.is_delta()
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter_fn, "HOLON RESEARCHER: CHOOSE A METAL ENERGY OR δ POKEMON", 1)
	if main._should_bail(): return
	await main.show_message("HOLON RESEARCHER! ADDED A CARD TO HAND!" if found.size() > 0 else "NO MATCHING CARD IN DECK!")
	if main._should_bail(): return

# HOLON SCIENTIST (ex11-97, Supporter): discard a card; if you have fewer cards in hand than your
# opponent, draw cards until you have the same number.
func effect_ex11_holon_scientist(is_opponent: bool) -> void:
	if not await _ex11_pay_discard_cost(is_opponent):
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var diff = opp_hand.size() - hand.size()
	if diff <= 0:
		await main.show_message("HOLON SCIENTIST: YOU DON'T HAVE FEWER CARDS THAN YOUR OPPONENT.")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, diff)
	if main._should_bail(): return
	await main.show_message("HOLON SCIENTIST! DREW " + str(diff) + " CARD(S)!")
	if main._should_bail(): return

# HOLON TRANSCEIVER (ex11-98, Item): search your deck OR discard pile for a Supporter card that has
# "Holon" in its name → hand.
func effect_ex11_holon_transceiver(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var deck_pool = deck.filter(func(c): return "Supporter" in c.metadata.get("subtypes", []) and "Holon" in c.metadata.get("name",""))
	var discard_pool = discard.filter(func(c): return "Supporter" in c.metadata.get("subtypes", []) and "Holon" in c.metadata.get("name",""))
	if deck_pool.is_empty() and discard_pool.is_empty():
		await main.show_message("NO HOLON SUPPORTER IN YOUR DECK OR DISCARD PILE!")
		deck.shuffle(); main.update_deck_icon(is_opponent)
		if main._should_bail(): return
		return
	# Choose source: prefer deck if available, else discard. Player picks if both exist.
	var use_discard = deck_pool.is_empty()
	if not is_opponent and not deck_pool.is_empty() and not discard_pool.is_empty():
		use_discard = not await gym1_prompt_yes_no(main.player_active_pokemon, "HOLON TRANSCEIVER", "Search your DECK or your DISCARD PILE?", "DECK", "DISCARD")
		if main._should_bail(): return
	if use_discard:
		var pick_d: card_object = discard_pool[0] if is_opponent else await main.card_ops.choose_card(discard_pool, false, "HOLON TRANSCEIVER", "Choose a Holon Supporter", "TAKE", false, Callable(), true)
		if main._should_bail(): return
		if pick_d == null: pick_d = discard_pool[0]
		await main.card_ops.recover_to_hand(pick_d, is_opponent)
		if main._should_bail(): return
	else:
		var pick: card_object = deck_pool[0] if is_opponent else await main.card_ops.choose_card(deck_pool, false, "HOLON TRANSCEIVER", "Choose a Holon Supporter", "TAKE", false, Callable(), true)
		if main._should_bail(): return
		if pick == null: pick = deck_pool[0]
		deck.erase(pick); pick.current_location = "hand"
		var hand = main.opponent_hand if is_opponent else main.player_hand
		hand.append(pick)
		deck.shuffle()
		main.update_deck_icon(is_opponent); main.refresh_hand_display(is_opponent)
	await main.show_message("HOLON TRANSCEIVER! ADDED A HOLON SUPPORTER TO YOUR HAND!")
	if main._should_bail(): return

# HOLON RUINS (ex11-96 Stadium): once during his or her turn, a player with any δ Pokemon in play may
# draw a card; if the player does, he or she discards a card. Offered at the start of the turn.
func holon_ruins_offer_draw(is_opponent: bool) -> void:
	if not main.is_stadium_in_play("ex11-96"):
		return
	if not main.card_ops.get_all_pokemon_in_play(is_opponent).any(func(p): return p.is_delta()):
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.is_empty():
		return
	var do_it = false
	if is_opponent:
		do_it = true
	else:
		var anchor = main.player_active_pokemon
		if anchor == null: return
		do_it = await gym1_prompt_yes_no(anchor, "HOLON RUINS", "Draw a card, then discard a card?", "YES", "NO")
		if main._should_bail(): return
	if not do_it:
		return
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	if not hand.is_empty():
		await main.card_ops.discard_from_hand(is_opponent, 1)
		if main._should_bail(): return
	await main.show_message("HOLON RUINS! DREW A CARD AND DISCARDED A CARD!")
	if main._should_bail(): return

######################################################################################################################################################
######################################################## EX12 (EX LEGEND MAKER) TRAINERS ############################################################
######################################################################################################################################################
# Fieldworker (Supporter) is the only dispatched trainer. The 3 Fossils (Claw/Mysterious/Root) auto-work
# as bench tokens (is_bench_token_trainer via their "as if it were a Basic" rule + HP), with Spongy Stone
# (Root) in apply_np_between_turn_bodies and Jagged Stone (Claw) via check_ex2_jagged_stone. All 5
# Stadiums auto-route through resolve_stadium_trainer; their passive effects live in get_max_bench_size
# (Giant Stump), process_status_between_turns (Full Flame), apply_np_between_turn_bodies (Cursed Stone),
# ex12_giant_stump_on_play, and the ex12_power_tree_offer / ex12_strange_cave_offer turn-start hooks.
func _register_ex12_trainers() -> void:
	_trainer_dispatch["ex12-73"] = func(c, opp): await effect_ex12_fieldworker(opp)   # Fieldworker (Supporter)

# FIELDWORKER (ex12-73, Supporter): draw 3 cards; your opponent may also draw a card.
func effect_ex12_fieldworker(is_opponent: bool) -> void:
	await main.card_ops.draw_n(is_opponent, 3)
	if main._should_bail(): return
	await main.show_message("FIELDWORKER! DREW 3 CARDS!")
	if main._should_bail(): return
	var opp = not is_opponent
	var opp_deck = main.opponent_deck if opp else main.player_deck
	if opp_deck.is_empty():
		return
	var do_it = false
	if opp:
		# The opponent here is the CPU — it always takes the free card.
		do_it = true
	else:
		# The opponent here is the human player — they may choose to draw.
		var anchor = main.player_active_pokemon
		if anchor != null:
			do_it = await gym1_prompt_yes_no(anchor, "FIELDWORKER", "Your opponent played Fieldworker. Draw a card?", "YES", "NO")
			if main._should_bail(): return
	if do_it:
		await main.card_ops.draw_n(opp, 1)
		if main._should_bail(): return
		await main.show_message("THE OPPONENT DREW A CARD!")
		if main._should_bail(): return

######################################################################################################################################################
######################################################## EX13 (EX HOLON PHANTOMS) TRAINERS ##########################################################
######################################################################################################################################################
# Delta (δ) set. Reprints reuse existing effects: Mr. Stone's Project (ex13-88 → effect_ex9_mr_stones_project),
# Professor Cozmo's Discovery (ex13-89 → effect_ex8_professor_cozmos_discovery), Rare Candy (ex13-90 →
# effect_ex2_rare_candy). The 3 Fossils (Claw ex13-91 / Mysterious ex13-92 / Root ex13-93) auto-work as
# bench tokens (is_bench_token_trainer via their "as if it were a Basic" rule + HP); Jagged Stone (Claw)
# via check_ex2_jagged_stone (has_ability, uid-agnostic), Spongy Stone (Root) via apply_np_between_turn_bodies
# (ability-name loop, uid-agnostic) — all three auto-work with no ex13-specific code.
# Holon Lake (ex13-87, Stadium) auto-routes through resolve_stadium_trainer; its "Holon" name satisfies the
# Holon-stadium bodies, and its Delta Call attack is granted to δ Pokémon in get_attacks_for_card +
# dispatched as execute_ex13_delta_call. Only Holon Adventurer and Holon Fossil need dedicated code.
func _register_ex13_trainers() -> void:
	_trainer_dispatch["ex13-85"] = func(c, opp): await effect_ex13_holon_adventurer(opp)         # Holon Adventurer (Supporter)
	_trainer_dispatch["ex13-86"] = func(c, opp): await effect_ex13_holon_fossil(opp)             # Holon Fossil (Item)
	_trainer_dispatch["ex13-88"] = func(c, opp): await effect_ex9_mr_stones_project(opp)         # Mr. Stone's Project (Supporter)
	_trainer_dispatch["ex13-89"] = func(c, opp): await effect_ex8_professor_cozmos_discovery(opp) # Professor Cozmo's Discovery (Supporter)
	_trainer_dispatch["ex13-90"] = func(c, opp): await effect_ex2_rare_candy(opp)                # Rare Candy (Item)

func _register_ex13_validations() -> void:
	# Holon Adventurer costs "discard a card from your hand" — need at least 1 other card in hand.
	_validator_dispatch["ex13-85"] = func(c, opp):
		var hand = main.opponent_hand if opp else main.player_hand
		return "" if hand.any(func(x): return x != c) else "You must discard a card to play this Supporter!"

# HOLON ADVENTURER (ex13-85, Supporter): discard a card from your hand (cost). Draw 3 cards, or draw 4
# cards instead if the discarded card was a Pokémon that has δ on its card.
func effect_ex13_holon_adventurer(is_opponent: bool) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.is_empty():
		return
	if not is_opponent:
		await main.show_message("DISCARD A CARD FROM YOUR HAND TO PLAY HOLON ADVENTURER.")
		if main._should_bail(): return
	var discarded = await main.card_ops.discard_from_hand(is_opponent, 1)
	if main._should_bail(): return
	if discarded.is_empty():
		return
	var discarded_delta = discarded.any(func(c): return c.metadata.get("supertype","") == "Pokémon" and c.is_delta())
	var draw_count = 4 if discarded_delta else 3
	await main.card_ops.draw_n(is_opponent, draw_count)
	if main._should_bail(): return
	await main.show_message("HOLON ADVENTURER! DREW " + str(draw_count) + " CARDS!" + (" (δ POKÉMON DISCARDED!)" if discarded_delta else ""))
	if main._should_bail(): return
	print("TRAINER: Holon Adventurer — drew ", draw_count)

# HOLON FOSSIL (ex13-86, Item): flip a coin. If heads, search your deck for an Omanyte, Kabuto, Aerodactyl,
# Aerodactyl ex, Lileep, or Anorith and put it onto your Bench. If tails, put one of those from your hand
# onto your Bench. Treat the new Benched Pokémon as a Basic Pokémon.
func effect_ex13_holon_fossil(is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("YOUR BENCH IS FULL!")
		if main._should_bail(): return
		return
	var names = ["Omanyte", "Kabuto", "Aerodactyl", "Lileep", "Anorith"]
	var match_fn = func(c):
		if c.metadata.get("supertype","") != "Pokémon": return false
		var cn = c.metadata.get("name","")
		for base in names:
			if base in cn: return true
		return false
	var heads = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var chosen: card_object = null
	if heads:
		await main.show_message("HOLON FOSSIL! HEADS — SEARCH YOUR DECK!")
		if main._should_bail(): return
		var pool = deck.filter(match_fn)
		if pool.is_empty():
			await main.show_message("NO OMANYTE/KABUTO/AERODACTYL/LILEEP/ANORITH IN YOUR DECK!")
			deck.shuffle(); main.update_deck_icon(is_opponent)
			if main._should_bail(): return
			return
		chosen = main.cpu_ai.cpu_pick_best_keep(pool) if is_opponent else await main.card_ops.choose_card(pool, false, "HOLON FOSSIL", "Choose a Pokémon to put on your Bench", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if chosen == null: chosen = pool[0]
		deck.erase(chosen)
		deck.shuffle()
		main.update_deck_icon(is_opponent)
	else:
		await main.show_message("HOLON FOSSIL! TAILS — PUT ONE FROM YOUR HAND!")
		if main._should_bail(): return
		var hpool = (main.opponent_hand if is_opponent else main.player_hand).filter(match_fn)
		if hpool.is_empty():
			await main.show_message("NO MATCHING POKÉMON IN YOUR HAND!")
			if main._should_bail(): return
			return
		chosen = hpool[0] if is_opponent else await main.card_ops.choose_card(hpool, false, "HOLON FOSSIL", "Choose a Pokémon from your hand to put on your Bench", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if chosen == null: chosen = hpool[0]
		(main.opponent_hand if is_opponent else main.player_hand).erase(chosen)
		main.refresh_hand_display(is_opponent)
	# Treat the Pokémon as a Basic while in play (place it directly on the Bench).
	main.card_ops.place_on_bench(chosen, is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HOLON FOSSIL! PUT " + chosen.metadata.get("name","").to_upper() + " ON YOUR BENCH!")
	if main._should_bail(): return
	print("TRAINER: Holon Fossil")

# GIANT STUMP (ex12-75, Stadium) on-play: each player discards Benched Pokemon (and attached cards)
# until they have 3 Benched Pokemon. The player who played it discards first.
func ex12_giant_stump_on_play(playing_is_opponent: bool) -> void:
	await _ex12_stump_trim(playing_is_opponent)
	if main._should_bail(): return
	await _ex12_stump_trim(not playing_is_opponent)
	if main._should_bail(): return

func _ex12_stump_trim(side_is_opp: bool) -> void:
	var bench = main.opponent_bench if side_is_opp else main.player_bench
	while bench.size() > 3:
		var victim: card_object = null
		if side_is_opp:
			victim = bench[0]
			for b in bench:
				if b.attached_energies.size() < victim.attached_energies.size():
					victim = b
		else:
			victim = await main.card_ops.choose_card(bench, false, "GIANT STUMP", "Choose a Benched Pokemon to discard (down to 3)", "DISCARD", false)
			if main._should_bail(): return
			if victim == null: victim = bench[0]
		bench.erase(victim)
		main.card_ops.discard_all_attachments(victim, side_is_opp)
		await main.card_ops.send_to_discard(victim, side_is_opp, false)
		if main._should_bail(): return
	main.display_pokemon(side_is_opp)

# POWER TREE (ex12-76, Stadium): once during each player's turn, if that player has NO Special Energy
# cards in their discard pile, they may search the discard for a basic Energy card and put it into hand.
func ex12_power_tree_offer(is_opponent: bool) -> void:
	if not main.is_stadium_in_play("ex12-76"):
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for c in discard:
		if c.metadata.get("supertype","") == "Energy" and "Special" in c.metadata.get("subtypes", []):
			return
	var pool = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if pool.is_empty():
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = main.cpu_ai.cpu_pick_best_keep(pool)
	else:
		var anchor = main.player_active_pokemon
		if anchor == null: return
		var do_it = await gym1_prompt_yes_no(anchor, "POWER TREE", "Take a basic Energy from your discard pile into your hand?", "YES", "NO")
		if main._should_bail(): return
		if not do_it: return
		chosen = await main.card_ops.choose_card(pool, false, "POWER TREE", "Choose a basic Energy to put into your hand", "SELECT", false, Callable(), true)
		if main._should_bail(): return
		if chosen == null: return
	await main.card_ops.recover_to_hand(chosen, is_opponent)
	if main._should_bail(): return
	await main.show_message("POWER TREE! PUT " + chosen.metadata.get("name","").to_upper() + " INTO HAND!")
	if main._should_bail(): return

# STRANGE CAVE (ex12-77, Stadium): once during each player's turn, that player may put an Omanyte, Kabuto,
# Aerodactyl, Aerodactyl ex, Lileep, or Anorith onto their Bench from their hand (treated as a Basic).
func ex12_strange_cave_offer(is_opponent: bool) -> void:
	if not main.is_stadium_in_play("ex12-77"):
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var names = ["Omanyte", "Kabuto", "Aerodactyl", "Aerodactyl ex", "Lileep", "Anorith"]
	var pool = hand.filter(func(c): return c.metadata.get("name","") in names)
	if pool.is_empty():
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = main.cpu_ai.cpu_pick_best_keep(pool)
	else:
		var anchor = main.player_active_pokemon
		if anchor == null: return
		var do_it = await gym1_prompt_yes_no(anchor, "STRANGE CAVE", "Put a fossil-line Pokemon from your hand onto your Bench?", "YES", "NO")
		if main._should_bail(): return
		if not do_it: return
		chosen = await main.card_ops.choose_card(pool, false, "STRANGE CAVE", "Choose a Pokemon to put on your Bench", "SELECT", true)
		if main._should_bail(): return
		if chosen == null: return
	hand.erase(chosen)
	chosen.placed_on_field_this_turn = true
	chosen.current_location = "bench"
	chosen.current_hp = chosen.get_max_hp()
	bench.append(chosen)
	main.display_pokemon(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("STRANGE CAVE! " + chosen.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
	if main._should_bail(): return

######################################################################################################################################################
##################################################### EX14 (CRYSTAL GUARDIANS) TRAINER EFFECTS #######################################################
######################################################################################################################################################
# Reprints reuse existing effect functions. Pokémon Tools (Cessation Crystal, Crystal Shard, Memory Berry,
# Mysterious Shard) and Stadiums (Crystal Beach, Holon Circle) route through resolve_attached_trainer /
# resolve_stadium_trainer respectively — their passive effects are wired at their check sites.

func _register_ex14_trainers() -> void:
	_trainer_dispatch["ex14-71"] = func(c, opp): await effect_ecard1_bills_maintenance(opp)   # Bill's Maintenance (Supporter)
	_trainer_dispatch["ex14-72"] = func(c, opp): await effect_ex14_castaway(opp)               # Castaway (Supporter)
	_trainer_dispatch["ex14-73"] = func(c, opp): await effect_ex6_celios_network(opp)          # Celio's Network (Supporter)
	_trainer_dispatch["ex14-77"] = func(c, opp): await effect_ex2_double_full_heal(opp)        # Double Full Heal (Item)
	_trainer_dispatch["ex14-78"] = func(c, opp): await effect_ecard1_dual_ball(opp)            # Dual Ball (Item)
	_trainer_dispatch["ex14-82"] = func(c, opp): await effect_poke_ball(opp)                   # Poké Ball (Item)
	_trainer_dispatch["ex14-83"] = func(c, opp): await effect_ex14_pokenav(opp)                # PokéNav (Item)
	_trainer_dispatch["ex14-84"] = func(c, opp): await effect_ecard1_warp_point(opp)           # Warp Point (Item)
	_trainer_dispatch["ex14-85"] = func(c, opp): await effect_ex14_windstorm(opp)              # Windstorm (Item)
	_trainer_dispatch["ex14-86"] = func(c, opp): await effect_energy_search(opp)               # Energy Search (Item)
	_trainer_dispatch["ex14-87"] = func(c, opp): await effect_potion(opp)                      # Potion (Item)

func _register_ex14_validations() -> void:
	# Cessation Crystal (ex14-74) / Mysterious Shard (ex14-81): attach only to a Pokémon that is NOT a
	# Pokémon-ex and does not already have a Tool.
	var non_ex_tool_target = func(c, opp):
		var field = build_field_pokemon_array(opp)
		for p in field:
			if main.is_ex_pokemon(p):
				continue
			var has_tool = false
			for ac in p.attached_cards:
				if "Pokémon Tool" in ac.metadata.get("subtypes", []):
					has_tool = true
					break
			if not has_tool:
				return ""
		return "No eligible Pokémon (must be a non-ex Pokémon without a Tool)!"
	_validator_dispatch["ex14-74"] = non_ex_tool_target
	_validator_dispatch["ex14-81"] = non_ex_tool_target

# CASTAWAY (ex14-72, Supporter): search your deck for a Supporter card, a Pokémon Tool card, and a basic
# Energy card, and put them into your hand.
func effect_ex14_castaway(is_opponent: bool) -> void:
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Trainer" and "Supporter" in c.metadata.get("subtypes", []), "CASTAWAY: CHOOSE A SUPPORTER", 1)
	if main._should_bail(): return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Trainer" and "Pokémon Tool" in c.metadata.get("subtypes", []), "CASTAWAY: CHOOSE A POKÉMON TOOL", 1)
	if main._should_bail(): return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []), "CASTAWAY: CHOOSE A BASIC ENERGY", 1)
	if main._should_bail(): return
	await main.show_message("CASTAWAY!")
	if main._should_bail(): return

# POKÉNAV (ex14-83, Item): look at the top 3 cards of your deck; choose a Basic Pokémon, Evolution card,
# or Energy card and put it into your hand. Put the other 2 back on top of your deck in any order.
func effect_ex14_pokenav(is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.is_empty():
		await main.show_message("YOUR DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top: Array = []
	for i in range(min(3, deck.size())):
		top.append(deck[deck.size() - 1 - i])
	var is_eligible = func(c):
		var st = c.metadata.get("supertype","")
		if st == "Energy": return true
		if st == "Pokémon":
			var subs = c.metadata.get("subtypes", [])
			return "Basic" in subs or "Stage 1" in subs or "Stage 2" in subs
		return false
	var eligible = top.filter(is_eligible)
	var chosen: card_object = null
	if eligible.is_empty():
		await main.show_message("POKÉNAV: NO BASIC POKÉMON, EVOLUTION, OR ENERGY IN THE TOP 3!")
		if main._should_bail(): return
	else:
		chosen = eligible[0] if is_opponent else await main.card_ops.choose_card(eligible, false, "POKÉNAV", "Choose a card to put into your hand", "TAKE", false)
		if main._should_bail(): return
		if chosen == null: chosen = eligible[0]
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("POKÉNAV! PUT " + chosen.metadata.get("name","").to_upper() + " INTO YOUR HAND!")
		if main._should_bail(): return
	# The other 2 stay on top of the deck (already there); order is irrelevant vs. no reshuffle.

# WINDSTORM (ex14-85, Item): choose up to 2 Pokémon Tool cards and/or Stadium cards in play (both players)
# and discard them.
func effect_ex14_windstorm(is_opponent: bool) -> void:
	# Gather all discardable targets: every attached Pokémon Tool (both sides) + the Stadium in play.
	var tool_entries: Array = []   # [{pokemon, card, owner_is_opp}]
	for owner_is_opp in [false, true]:
		for p in build_field_pokemon_array(owner_is_opp):
			for ac in p.attached_cards:
				if "Pokémon Tool" in ac.metadata.get("subtypes", []):
					tool_entries.append({"pokemon": p, "card": ac, "owner_is_opp": owner_is_opp})
	var has_stadium = main.current_stadium_card != null
	if tool_entries.is_empty() and not has_stadium:
		await main.show_message("WINDSTORM: NO POKÉMON TOOLS OR STADIUMS IN PLAY!")
		if main._should_bail(): return
		return
	# Build a selectable pool of card_objects (tools + stadium), pick up to 2.
	var pool: Array = []
	for e in tool_entries:
		pool.append(e["card"])
	if has_stadium:
		pool.append(main.current_stadium_card)
	var picks: Array = []
	var max_picks = min(2, pool.size())
	for i in range(max_picks):
		if pool.is_empty(): break
		var pick: card_object = null
		if is_opponent:
			# CPU: prefer discarding the opponent's (player's) tools/stadium first.
			pick = pool[0]
			for c in pool:
				var owner_opp = _ex14_card_owner_is_opp(c, tool_entries)
				if not owner_opp:
					pick = c
					break
		else:
			var cancelable = i > 0
			pick = await main.card_ops.choose_card(pool, false, "WINDSTORM", "Choose a Tool or Stadium to discard (" + str(max_picks - i) + " left)", "DISCARD", cancelable)
			if main._should_bail(): return
			if pick == null: break
		pool.erase(pick)
		picks.append(pick)
	for pick in picks:
		if pick == main.current_stadium_card:
			await remove_current_stadium("Windstorm")
			if main._should_bail(): return
		else:
			for e in tool_entries:
				if e["card"] == pick:
					var owner_opp = e["owner_is_opp"]
					e["pokemon"].attached_cards.erase(pick)
					pick.current_location = "discard"
					var disc = main.opponent_discard_pile if owner_opp else main.player_discard_pile
					disc.append(pick)
					display_attached_trainer_cards(owner_opp)
					main.update_discard_pile_display(owner_opp)
					main.display_pokemon(owner_opp)
					break
	await main.show_message("WINDSTORM! DISCARDED " + str(picks.size()) + " CARD(S)!")
	if main._should_bail(): return

# Helper: given a card and the tool-entry list, return whether its owner is the opponent (stadium uses
# its own owner flag).
func _ex14_card_owner_is_opp(c: card_object, tool_entries: Array) -> bool:
	if c == main.current_stadium_card:
		return main.current_stadium_owner_is_opponent
	for e in tool_entries:
		if e["card"] == c:
			return e["owner_is_opp"]
	return false

######################################################################################################################################################
######################################################### EX15 (EX DRAGON FRONTIERS) TRAINERS ########################################################
######################################################################################################################################################
# Reprints reuse existing effect functions by UID. Buffer Piece (ex15-72) & Strength Charm (ex15-81) are
# Pokémon Tools — their attach is generic and their bonuses reuse the ex3/ecard1 hooks (their UIDs were
# added to those hooks' UID lists). Holon Legacy (ex15-74) is a Stadium installed generically by
# resolve_stadium_trainer; its passive δ effects live in is_ex15_holon_legacy_active() checks inside
# is_power_blocked and has_no_weakness_body. Only the Items/Supporters need dispatch entries.
func _register_ex15_trainers() -> void:
	_trainer_dispatch["ex15-73"] = func(c, opp): await effect_ecard1_copycat(opp)                    # Copycat (Supporter)
	_trainer_dispatch["ex15-75"] = func(c, opp): await effect_ex15_holon_mentor(opp)                 # Holon Mentor (Supporter)
	_trainer_dispatch["ex15-76"] = func(c, opp): await effect_ex15_island_hermit(opp)                # Island Hermit (Supporter)
	_trainer_dispatch["ex15-77"] = func(c, opp): await effect_ex9_mr_stones_project(opp)             # Mr. Stone's Project (Supporter)
	_trainer_dispatch["ex15-78"] = func(c, opp): await effect_neo3_old_rod(c, opp)                   # Old Rod (Item)
	_trainer_dispatch["ex15-79"] = func(c, opp): await effect_ex15_professor_elms_training_method(opp)  # Professor Elm's Training Method (Supporter)
	_trainer_dispatch["ex15-80"] = func(c, opp): await effect_ecard1_professor_oaks_research(opp)    # Professor Oak's Research (Supporter)
	_trainer_dispatch["ex15-82"] = func(c, opp): await effect_ex3_tv_reporter(opp)                   # TV Reporter (Supporter)
	_trainer_dispatch["ex15-83"] = func(c, opp): await effect_switch(opp)                            # Switch (Item)

# HOLON MENTOR (ex15-75, Supporter): search your deck for up to 3 Basic Pokémon that each have 100 HP or
# less and put them into your hand. (No discard cost — unlike the ex11 Holon Supporters.)
func effect_ex15_holon_mentor(is_opponent: bool) -> void:
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return main.is_basic_pokemon(c) and int(c.metadata.get("hp","0")) <= 100, "HOLON MENTOR: CHOOSE UP TO 3 BASIC POKÉMON (100 HP OR LESS)", 3)
	if main._should_bail(): return
	await main.show_message("HOLON MENTOR! ADDED " + str(found.size()) + " BASIC POKÉMON TO YOUR HAND!")
	if main._should_bail(): return

# ISLAND HERMIT (ex15-76, Supporter): choose up to 2 of your Prize cards and put them face up, then draw 2
# cards. (Per-prize face-up state isn't modelled by this engine — it has only a single all-prizes flag — so
# the mechanically meaningful "draw 2" is applied; see the same documented limitation on ex11 Prize Shift.)
func effect_ex15_island_hermit(is_opponent: bool) -> void:
	await main.card_ops.draw_n(is_opponent, 2)
	if main._should_bail(): return
	await main.show_message("ISLAND HERMIT! REVEALED UP TO 2 PRIZE CARDS AND DREW 2 CARDS!")
	if main._should_bail(): return

# PROFESSOR ELM'S TRAINING METHOD (ex15-79, Supporter): search your deck for an Evolution card, show it to
# your opponent, and put it into your hand.
func effect_ex15_professor_elms_training_method(is_opponent: bool) -> void:
	var is_evolution = func(c):
		if c.metadata.get("supertype","") != "Pokémon": return false
		var st = c.metadata.get("subtypes", [])
		return "Stage 1" in st or "Stage 2" in st
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if not deck.any(is_evolution):
		await main.show_message("NO EVOLUTION CARD IN YOUR DECK!")
		if main._should_bail(): return
		return
	await main.card_ops.search_deck_to_hand(is_opponent, is_evolution, "PROFESSOR ELM'S TRAINING METHOD: CHOOSE AN EVOLUTION CARD", 1)
	if main._should_bail(): return
	await main.show_message("PROFESSOR ELM'S TRAINING METHOD!")
	if main._should_bail(): return

# EX16 (EX POWER KEEPERS) trainers — the final set. Every Item/Supporter is a reprint routed to an
# existing effect by UID. The five Stadiums (Battle Frontier 71, Drake's 72, Glacia's 76, Phoebe's 79,
# Sidney's 82) install generically via resolve_stadium_trainer and expose only passive effects (wired in
# Powers_And_Bodies / Main). The three Fossils (Claw 84, Mysterious 85, Root 86) are bench-token trainers
# detected by is_bench_token_trainer. So only the non-Stadium Items/Supporters need dispatch routing here.
func _register_ex16_trainers() -> void:
	_trainer_dispatch["ex16-73"] = func(c, opp): await effect_ex3_energy_recycle_system(opp)   # Energy Recycle System (Item)
	_trainer_dispatch["ex16-74"] = func(c, opp): await effect_ecard1_energy_removal_2(opp)      # Energy Removal 2 (Item)
	_trainer_dispatch["ex16-75"] = func(c, opp): await effect_ecard2_energy_switch(opp)         # Energy Switch (Item)
	_trainer_dispatch["ex16-77"] = func(c, opp): await effect_ex6_great_ball(opp)               # Great Ball (Item)
	_trainer_dispatch["ex16-78"] = func(c, opp): await effect_ex8_master_ball(opp)              # Master Ball (Item)
	_trainer_dispatch["ex16-80"] = func(c, opp): await effect_ex1_professor_birch(opp)          # Professor Birch (Supporter)
	_trainer_dispatch["ex16-81"] = func(c, opp): await effect_ex9_scott(opp)                    # Scott (Supporter)
	_trainer_dispatch["ex16-83"] = func(c, opp): await effect_ex5_stevens_advice(opp)           # Steven's Advice (Supporter)

# POP SERIES (pop1–pop5) trainers. Every one is a reprint of an existing card — reuse the existing
# effect functions with the pop UID. Stadiums (Pokémon Park pop2-10, High/Low Pressure System
# pop3-10/11) route through resolve_stadium_trainer and are recognized via STADIUM_UID_ALIASES.
# Multi Technical Machine 01 (pop2-9) auto-routes via is_attached_trainer() (Technical Machine subtype).
func _register_pop_trainers() -> void:
	_trainer_dispatch["pop2-8"]  = func(c, opp): await effect_ex3_mr_brineys_compassion(opp)  # Mr. Briney's Compassion (Supporter)
	_trainer_dispatch["pop2-11"] = func(c, opp): await effect_ex3_tv_reporter(opp)            # TV Reporter (Supporter)
	_trainer_dispatch["pop4-9"]  = func(c, opp): await effect_ecard2_pokemon_fan_club(opp)    # Pokémon Fan Club (Supporter)
	_trainer_dispatch["pop5-6"]  = func(c, opp): await effect_ecard1_bills_maintenance(opp)   # Bill's Maintenance (Supporter)
	_trainer_dispatch["pop5-7"]  = func(c, opp): await effect_ex2_rare_candy(opp)             # Rare Candy (Item)

func _register_ex16_validations() -> void:
	# STEVEN'S ADVICE (ex16-83): can't be played if you have more than 7 cards in hand (including it).
	_validator_dispatch["ex16-83"] = func(c, opp):
		var hand = main.opponent_hand if opp else main.player_hand
		return "You have too many cards in hand to play Steven's Advice!" if hand.size() > 7 else ""
