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
	# When adding Neo1/Neo2/etc., append: _register_neo1_trainers()

func _register_base_trainers() -> void:
	_trainer_dispatch["base1-88"] = func(c, opp): await effect_professor_oak(c, opp)
	_trainer_dispatch["base1-89"] = func(c, opp): await effect_revive(opp)
	_trainer_dispatch["base1-90"] = func(c, opp): await effect_super_potion(opp)
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
			main.update_discard_pile_display(is_opponent)
			display_attached_trainer_cards(is_opponent)
			print("DEFENDER EXPIRED on ", pokemon.metadata.get("name", ""))

# Displays attached trainer cards (PlusPower, Defender) next to active pokemon
func display_attached_trainer_cards(is_opponent: bool) -> void:
	var container = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	
	for child in container.get_children():
		child.queue_free()
	
	if active == null:
		return
	
	var card_size = main.card_scales[11]  # Same size as energy cards
	var overlap_offset = 80
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
		var priority = _score_card_for_discard(card)
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
		return "Hay Fever: No Trainer cards can be played!"

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
	
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var who = "Opponent" if is_opponent else "You"
	var card_name = card.metadata.get("name", "Unknown")
	
	# Remove from hand first
	hand.erase(card)
	main.refresh_hand_display(is_opponent)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_trainer_sound)

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
	
	# Hide hand, decks, discards while trainer card is shown
	main.player_hand_container.visible = false
	main.player_deck_icon.visible = false
	main.opponent_deck_icon.visible = false
	main.player_discard_icon.visible = false
	main.opponent_discard_icon.visible = false
	
	# Show the overlay
	main.trainer_block_container.visible = true
	
	# Display the card in the container
	var card_display = TextureRect.new()
	card_display.set_script(main.card_display_script)
	main.played_trainer_container.add_child(card_display)
	card_display.load_card_image(card.uid, main.card_scales[1], card)
	
	# Show message
	await main.show_message(who + " played " + card_name + "!")
	
	# Clean up overlay and restore hidden elements
	main.trainer_block_container.visible = false
	for child in main.played_trainer_container.get_children():
		child.queue_free()
	main.player_hand_container.visible = true
	main.player_deck_icon.visible = true
	main.opponent_deck_icon.visible = true
	main.player_discard_icon.visible = true
	main.opponent_discard_icon.visible = true
	
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
		# Animate PlusPower to attached cards container
		var hand_node = main.opponent_hand_container if is_opponent else main.player_hand_container
		var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
		var card_texture = main.get_card_texture(card)
		await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
		display_attached_trainer_cards(is_opponent)
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
			# Animate to active
			var hand_node = main.opponent_hand_container
			var attached_node = main.opponent_attached_cards_container
			var card_texture = main.get_card_texture(card)
			await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
			display_attached_trainer_cards(true)
			await main.show_message("Defender attached to " + active.metadata.get("name", "") + "! (-20 damage)")
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
				# Animate to the target pokemon's location
				var hand_node = main.player_hand_container
				var target_node = main.player_active_container if target == main.player_active_pokemon else main.player_bench_container
				var card_texture = main.get_card_texture(card)
				await main.animate_card_a_to_b(hand_node, target_node, 0.3, card_texture, main.card_scales[10])
				display_attached_trainer_cards(false)
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
		var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
		var card_texture = main.get_card_texture(card)
		await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
		display_attached_trainer_cards(is_opponent)
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
			if sabrina_targets.size() == 1:
				target = sabrina_targets[0]
			else:
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
		var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
		var card_texture = main.get_card_texture(card)
		await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
		display_attached_trainer_cards(is_opponent)
		await main.show_message("SABRINA'S ESP ATTACHED TO " + target.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("SABRINA'S ESP: Attached to ", target.metadata.get("name", ""))

	# GYM2 Brock's Protection (gym2-101) — attach to a Brock-named pokemon
	elif card.uid.to_lower() == "gym2-101":
		await gym2_attach_named_tool(card, is_opponent, "Brock", "gym2_brocks_protection_attached", "BROCK'S PROTECTION")

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
		var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
		var card_texture = main.get_card_texture(card)
		await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
		display_attached_trainer_cards(is_opponent)
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
		if targets.size() == 1:
			target = targets[0]
		else:
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
	var attached_node = main.opponent_attached_cards_container if is_opponent else main.player_attached_cards_container
	var card_texture = main.get_card_texture(card)
	await main.animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, main.card_scales[10])
	display_attached_trainer_cards(is_opponent)
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
		await get_tree().create_timer(0.1).timeout
		if main._should_bail(): return
	hand.clear()
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await get_tree().create_timer(0.3).timeout
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
	
	if is_opponent:
		return
	else:
		# Step 1: Player selects which pokemon to devolve
		var target = await main.card_ops.prompt_select_card(evolved_pokemon, "DEVOLUTION SPRAY", "Choose an evolved Pokemon to devolve", "SELECT", false)
		if main._should_bail(): return
		
		if target == null:
			return
		
		# Step 2: If multiple pre-evolutions exist (Stage 2), let player choose which to devolve to
		var devolve_to: card_object = null
		if target.attached_pre_evolutions.size() == 1:
			# Only one option (Stage 1 → Basic)
			devolve_to = target.attached_pre_evolutions[0]
		else:
			# Multiple options (Stage 2 → show Basic and Stage 1)
			devolve_to = await main.card_ops.prompt_select_card(target.attached_pre_evolutions, "DEVOLVE TO WHICH STAGE?", "Select which card to devolve " + target.metadata.get("name", "") + " into", "DEVOLVE", false)
			if main._should_bail(): return
		
		if devolve_to == null:
			return
		
		# Save the field position BEFORE discarding
		var field_location = target.current_location
		
		# Find the index of the chosen card in the pre-evolution chain
		var devolve_index = target.attached_pre_evolutions.find(devolve_to)
		
		# Discard the current top card (the evolved form) to the discard pile
		var evo_card = target
		evo_card.current_location = "discard"
		discard.append(evo_card)
		
		# Discard all pre-evolutions ABOVE the chosen devolve target
		# Pre-evolutions are stored [Basic, Stage1] - discard everything after devolve_index
		var cards_to_discard_from_chain = []
		for i in range(devolve_index + 1, target.attached_pre_evolutions.size()):
			cards_to_discard_from_chain.append(target.attached_pre_evolutions[i])
		for card in cards_to_discard_from_chain:
			card.current_location = "discard"
			discard.append(card)
			target.attached_pre_evolutions.erase(card)
		
		# Remove the devolve_to card from the chain (it becomes the new pokemon)
		target.attached_pre_evolutions.erase(devolve_to)
		
		# Transfer attachments from the old top card to the new form
		devolve_to.attached_energies = evo_card.attached_energies.duplicate()
		evo_card.attached_energies.clear()
		# Keep only pre-evolutions below the devolve target
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
		
		# Clear statuses
		main.clear_all_statuses(devolve_to, is_opponent)
		
		# Replace in the appropriate slot
		if evo_card == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon):
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
		await get_tree().create_timer(0.1).timeout
		if main._should_bail(): return
	target_hand.clear()
	target_deck.shuffle()
	main.refresh_hand_display(target_is_opponent)
	main.update_deck_icon(target_is_opponent)
	
	await get_tree().create_timer(0.3).timeout
	if main._should_bail(): return
	
	# Draw 7 cards with per-card animation
	await main.card_ops.draw_n(target_is_opponent, 7)
	if main._should_bail(): return
	await main.show_message("Hand was shuffled into deck and drew 7 cards!")
	if main._should_bail(): return

# base1-74 — Item Finder: Discard 2, retrieve 1 Trainer from discard
func effect_item_finder(played_card: card_object, is_opponent: bool) -> void:
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
		if main._should_bail(): return
		main.trainer_pokemon_selection_active = false
		main.cancel_button.text = "Cancel"
		main.cancel_button.theme = main.theme_red
		main.hide_selection_mode_display_main()
	
	# Animate player trainers going to deck
	for card in p_trainers:
		main.player_hand.erase(card)
		card.current_location = "deck"
		main.player_deck.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(main.player_hand_container, main.player_deck_icon, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(0.1).timeout
		if main._should_bail(): return
		main.update_deck_icon(false)
	
	# Animate opponent trainers going to deck
	for card in o_trainers:
		main.opponent_hand.erase(card)
		card.current_location = "deck"
		main.opponent_deck.append(card)
		var card_texture = main.get_card_texture(card)
		main.animate_card_a_to_b(main.opponent_hand_container, main.opponent_deck_icon, 0.15, card_texture, main.card_scales[12])
		await get_tree().create_timer(0.1).timeout
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
		# CPU: trade a duplicate or unneeded pokemon for a needed one
		var trade_away = cpu_get_discard_priority(pokemon_in_hand, 1, played_card)
		if trade_away.size() == 0:
			return
		var card_to_trade = trade_away[0]
		var search_card = main.cpu_ai.cpu_search_deck_for_best_pokemon(pokemon_in_deck)
		if search_card != null:
			hand.erase(card_to_trade)
			card_to_trade.current_location = "deck"
			deck.append(card_to_trade)
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			deck.shuffle()
			await main.show_message("Opponent traded " + card_to_trade.metadata.get("name", "") + " for " + search_card.metadata.get("name", "") + "!")
			if main._should_bail(): return
			main.refresh_hand_display(true)
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
			await get_tree().create_timer(0.2).timeout
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
	
	# Discard all attachments (energies, evolutions, attached cards)
	main.card_ops.discard_all_attachments(target, is_opponent)
	
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
	basic_card.current_hp = int(basic_card.metadata.get("hp", "0"))
	basic_card.pluspower_count = 0
	basic_card.defender_turns_remaining = -1
	main.clear_all_statuses(basic_card, is_opponent)
	hand.append(basic_card)
	
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	
	await main.show_message(basic_card.metadata.get("name", "") + " was scooped up and returned to hand!")
	if main._should_bail(): return
	
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
		var to_shuffle = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_shuffle:
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
		deck.shuffle()
		await main.card_ops.draw_n(true, 1)
		if main._should_bail(): return
		await main.show_message("Opponent shuffled 2 cards into deck and drew 1!")
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
		
		await get_tree().create_timer(0.3).timeout
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
			chosen.current_hp = int(chosen.metadata.get("hp", "0"))
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
func effect_super_potion(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
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
		var target = await main.card_ops.prompt_select_card(valid_targets, "SUPER POTION", "Select a Pokemon to heal (will discard 1 energy)", "HEAL", false)
		if main._should_bail(): return
		
		if target != null:
			# Animate energy discard
			var energy = target.attached_energies.pop_back()
			energy.current_location = "discard"
			discard.append(energy)
			var from_node = main.find_card_ui_for_object(target)
			if from_node == null:
				from_node = main.player_active_container if target == main.player_active_pokemon else main.player_bench_container
			var energy_texture = main.get_card_texture(energy)
			await main.animate_card_a_to_b(from_node, main.player_discard_icon, 0.2, energy_texture, main.card_scales[10])
			if main._should_bail(): return
			main.display_active_pokemon_energies(false)
			main.update_discard_pile_display(false)
			await main.card_ops.heal_pokemon(target, 40, false)
			if main._should_bail(): return

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
		
		await main.animate_retreat(old_active, new_active, [], target_is_opp)
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
		var target = damaged[0]
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
		await main.animate_retreat(active, replacement, [], true)
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
			await main.animate_retreat(active, replacement, [], false)
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
		main.refresh_hand_display(is_opponent)
		await main.show_message("ENERGY SEARCH: ADDED " + chosen.metadata.get("name", "").to_upper() + " TO HAND!")
		if main._should_bail(): return
		print("ENERGY SEARCH: Retrieved ", chosen.metadata.get("name", ""))
	
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
	chosen.current_hp = int(chosen.metadata.get("hp", "0"))
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
		c.current_hp = int(c.metadata.get("hp", "0"))
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
	target.current_hp = int(target.metadata.get("hp", "0"))
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

	# Run on-play effect (only Narrow Gym needs one)
	var uid = card.uid.to_lower()
	if uid == "gym1-124":
		await gym1_narrow_gym_on_play()

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
	chosen.current_hp = int(chosen.metadata.get("hp", "0"))
	chosen.special_condition = ""
	chosen.is_poisoned = false
	chosen.is_burned = false
	chosen.pluspower_count = 0
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
	target.special_condition = ""
	target.is_poisoned = false
	target.poison_damage = 0
	target.is_burned = false
	target.burn_damage = 0
	main.update_status_icons(target, !is_opponent)
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
		if blaine_targets.size() == 1:
			target = blaine_targets[0]
		else:
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
	if is_opponent:
		main.opponent_energy_played_this_turn = true
		main.opponent_blaine_double_attach_used = true
	else:
		main.player_energy_played_this_turn = true
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
		if giovannis.size() == 1:
			target = giovannis[0]
		else:
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
		if giovannis.size() == 1:
			target = giovannis[0]
		else:
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
		var pick = basics[0]
		hand.erase(pick)
		pick.current_hp = int(pick.metadata.get("hp", "0"))
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
		pick_c.current_hp = int(pick_c.metadata.get("hp", "0"))
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
	revive_pick.current_hp = int(revive_pick.metadata.get("hp", "0"))
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
	chosen.current_hp = int(chosen.metadata.get("hp", "0"))
	chosen.special_condition = ""
	chosen.is_poisoned = false
	chosen.is_burned = false
	chosen.pluspower_count = 0
	chosen.defender_turns_remaining = -1

	# If chosen was active, promote a bench pokemon to active first
	if chosen == active:
		var promoted: card_object = bench[0]
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
