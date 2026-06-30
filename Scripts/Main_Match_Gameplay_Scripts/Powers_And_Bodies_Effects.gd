extends Node

######################################################################################################################################################
########################################################## POWERS AND BODIES EFFECTS ###############################################################
######################################################################################################################################################
#
# This file contains Pokémon Powers, Pokémon Bodies, and related helpers.
# Powers are activated abilities (Rain Dance, Energy Trans, Damage Swap, etc.)
# Bodies are passive abilities (Energy Burn, Strikes Back, etc.)
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

# ── Power dispatch registry ────────────────────────────────────────────────────
# Maps ability name → async Callable(pokemon). Player path only; CPU path is separate.
# Add new set powers by calling _register_<set>_powers() from _ensure_power_dispatch_ready().
var _power_dispatch: Dictionary = {}
var _power_dispatch_ready := false

func _ensure_power_dispatch_ready() -> void:
	if _power_dispatch_ready:
		return
	_power_dispatch_ready = true
	_register_all_powers()
	# Neo1 and Neo2 powers are registered via _register_neo1_powers() / _register_neo2_powers() called from _register_all_powers()

func _register_all_powers() -> void:
	_power_dispatch["Damage Swap"]           = func(p): await power_damage_swap(p)
	_power_dispatch["Rain Dance"]            = func(p): await power_rain_dance(p)
	_power_dispatch["Energy Trans"]          = func(p): await power_energy_trans(p)
	_power_dispatch["Buzzap"]                = func(p): await power_buzzap(p)
	_power_dispatch["Discard"]               = func(p): await power_bench_token_discard(p)
	_power_dispatch["Shift"]                 = func(p): await power_shift(p)
	_power_dispatch["Heal"]                  = func(p): await power_heal_vileplume(p)
	_power_dispatch["Peek"]                  = func(p): await power_peek(p)
	_power_dispatch["Step In"]               = func(p): await power_step_in(p)
	_power_dispatch["Curse"]                 = func(p): await power_curse(p)
	_power_dispatch["Strange Behavior"]      = func(p): await power_strange_behavior(p)
	_power_dispatch["Cowardice"]             = func(p): await power_cowardice(p)
	_power_dispatch["Evolutionary Light"]    = func(p): await power_evolutionary_light(p)
	_power_dispatch["Pollen Stench"]         = func(p): await power_pollen_stench(p)
	_power_dispatch["Matter Exchange"]       = func(p): await power_matter_exchange(p)
	_power_dispatch["Gather Fire"]           = func(p): await power_gather_fire(p)
	_power_dispatch["Long-Distance Hypnosis"]= func(p): await power_long_distance_hypnosis(p)
	_power_dispatch["Trickery"]              = func(p): await power_trickery(p)
	_power_dispatch["Celadon City Gym"]      = func(p): await main.trainer_effects.gym1_celadon_activate(false)
	_power_dispatch["Fuchsia City Gym"]      = func(p): await main.trainer_effects.gym2_fuchsia_activate(false)
	_power_dispatch["Saffron City Gym"]      = func(p): await main.trainer_effects.gym2_saffron_activate(false)
	_power_dispatch["Energy Charge"]         = func(p): await power_energy_charge(p)
	_power_dispatch["Fragrance Trap"]        = func(p): await power_fragrance_trap(p)
	_power_dispatch["Natural Healing"]       = func(p): await power_natural_healing(p)
	_power_dispatch["Shapeshift"]            = func(p): await power_shapeshift(p)
	_power_dispatch["Discard Form"]          = func(p): await power_shapeshift_discard(p)
	_power_dispatch["Soak Up"]               = func(p): await power_soak_up(p)
	_power_dispatch["Emerge"]                = func(p): await power_emerge(p)
	_power_dispatch["Special Delivery"]     = func(p): await power_special_delivery(p)
	_power_dispatch["Solar Power"]          = func(p): await power_solar_power(p)
	_power_dispatch["[Join]"]               = func(p): await power_join_unown(p)
	_power_dispatch["Lucky Stadium"]        = func(p): await main.trainer_effects.basep_lucky_stadium_activate(false)
	_power_dispatch["Healing Field"]        = func(p): await main.trainer_effects.neo3_healing_field_activate(false)
	_power_dispatch["Chain Reaction"]      = func(p): await power_chain_reaction(p)
	_register_neo1_powers()
	_register_neo2_powers()
	_register_neo3_powers()
	_register_neo4_powers()

# ── On-damage and pre-KO event hooks ──────────────────────────────────────────
# Each Callable is fired after active-pokemon damage resolves (on_damage) or
# just before a KO'd pokemon's discard sequence begins (pre_ko).
# Signature: func(defender, attacker, damage: int, is_def_opp: bool) — for on_damage
# Signature: func(pokemon, attacker, is_pokemon_opp: bool)           — for pre_ko
# attack_effects registers its own hooks at startup via register_on_damage_hook.
var _on_damage_hooks: Array = []
var _pre_ko_hooks: Array = []

func register_on_damage_hook(fn: Callable) -> void:
	_on_damage_hooks.append(fn)

func register_pre_ko_hook(fn: Callable) -> void:
	_pre_ko_hooks.append(fn)

func _register_all_power_hooks() -> void:
	_on_damage_hooks.clear()
	_pre_ko_hooks.clear()
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_strikes_back(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_restless_sleep(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_pollen_defense(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_energy_drain(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_shock_blast(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_scram(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_flee(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_koga_poison(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_bolt(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo2_counter(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo2_secrete_poison(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo4_fluffy_wool(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo4_counters(def, atk, is_def_opp))
	_pre_ko_hooks.append(func(poke, atk, is_poke_opp): await check_final_beam(poke, atk, is_poke_opp))

# Fires all on-damage hooks in registration order. Called once from Main after active damage lands.
func dispatch_on_damage(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	for fn in _on_damage_hooks:
		if main._should_bail(): return
		await fn.call(defender, attacker, damage, is_def_opp)

# Fires all pre-KO hooks. Called once from Main before the KO'd pokemon is discarded.
func dispatch_pre_ko(pokemon: card_object, attacker: card_object, is_pokemon_opp: bool) -> void:
	for fn in _pre_ko_hooks:
		if main._should_bail(): return
		await fn.call(pokemon, attacker, is_pokemon_opp)

# GYM2 Koga (gym2-19/106) poison: a Koga-named attacker that dealt damage this turn poisons the defender.
func check_koga_poison(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if attacker == null or defender == null:
		return
	var attacker_owner_is_opp = (attacker == main.opponent_active_pokemon)
	var koga_on = main.opponent_koga_poison_active if attacker_owner_is_opp else main.player_koga_poison_active
	if not koga_on:
		return
	if not ("Koga" in attacker.metadata.get("name", "")):
		return
	if defender.is_poisoned or defender.special_condition == "Asleep":
		return
	main.card_ops.apply_status(defender, "Poisoned", is_def_opp)
	print("GYM2 KOGA: Poisoned ", defender.metadata.get("name", ""))

func is_power_blocked_by_status(pokemon: card_object) -> bool:
	if pokemon == null:
		return true
	return pokemon.is_status_blocked()

# Full power-blocker check: status conditions, Toxic Gas, Goop Gas, and temporary disable flag.
# Pass works_through_status=true for powers like Buzzap that still work while statused.
func is_power_blocked(pokemon: card_object, works_through_status: bool = false) -> bool:
	if pokemon == null:
		return true
	if not works_through_status and pokemon.is_status_blocked():
		return true
	if is_toxic_gas_active():
		return true
	if main.goop_gas_active:
		return true
	if pokemon.power_disabled_until_end_of_next_turn:
		return true
	return false

# Returns true if a card is a trainer card

func is_energy_burn_active(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	var name = pokemon.metadata.get("name", "")
	if name != "Charizard":
		return false
	# Check if it has the Energy Burn ability
	var abilities = pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") == "Energy Burn":
			# Blocked by status
			if is_power_blocked_by_status(pokemon):
				return false
			return true
	return false

# Resets power_used_this_turn for all pokemon on one side

func reset_power_used_flags(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		active.reset_power_used()
	for bp in bench:
		bp.reset_power_used()
	# Refresh Gaseous Form HP each turn in case Toxic Gas / Goop Gas state changed
	refresh_gaseous_form_hp()

# Discards PlusPower from a pokemon at end of turn

func open_power_menu() -> void:
	if main.opponents_turn_active:
		return
	
	# Scan for available powers
	var available_powers = []
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	# Check if Toxic Gas is active (blocks all non-Toxic-Gas powers)
	var toxic_gas_active = is_toxic_gas_active()
	
	for pokemon in all_pokemon:
		var abilities = pokemon.metadata.get("abilities", [])
		for ability in abilities:
			var ability_type = ability.get("type", "")
			if ability_type != "Pokémon Power" and ability_type != "Pokemon Power":
				continue
			var ability_name = ability.get("name", "")
			# Skip passive powers (they don't go in menu)
			if ability_name in ["Strikes Back", "Energy Burn", "Invisible Wall", "Thick Skinned", "Retreat Aid", "Prehistoric Power", "Toxic Gas", "Transparency", "Kabuto Armor", "Clairvoyance", "Transform", "Sinkhole", "Hay Fever", "Sticky Goo", "Frenzy", "Final Beam", "Sneak Attack", "Summon Minions", "Reel In", "Bench Guard", "Pollen Defense", "Flee", "Rebirth", "Shell Armor", "Restless Sleep", "Strange Barrier", "Photosynthesis", "Fortitude", "Call the Boss", "Rebellion", "Psylink", "Healing Fire", "Energy Drain", "Scram", "Relaxing Scent", "Shock Blast", "Gaseous Form", "Bolt", "Neutral Shield", "Aurora Veil", "Guard", "Pure Body", "Berserk", "Final Blow", "Herbal Scent", "Wild Growth", "Mind Games", "Fire Boost", "Hydroelectric Power", "Spikes", "Frog Song", "[Anger]", "[Darkness]", "[Metal]", "[Normal]", "Energy Evolution", "Conductivity", "Surprise Bite", "Scare", "Deep Sleep", "Hot Plate", "Fluffy Wool", "Gift", "Tag Team", "Miraculous Wind", "[Chase]", "[Perform]", "[XXXXX]", "[Zoom]", "[Vanish]"]:
				continue
			# Toxic Gas blocks all other powers
			if toxic_gas_active:
				continue
			# Dark Arbok Stare: power disabled temporarily
			if pokemon.power_disabled_until_end_of_next_turn:
				continue
			# NEO2 Gaze (Igglybuff): suppress this pokemon's power for the turn
			if pokemon.gaze_suppressed:
				continue
			# Check if usable
			if ability_name != "Buzzap" and is_power_blocked_by_status(pokemon):
				continue
			available_powers.append({"pokemon": pokemon, "ability": ability})
	
	if available_powers.size() == 0:
		# Also check for bench tokens with voluntary discard (their ability is in rules text, not abilities field)
		for bp in main.player_bench:
			if bp.is_bench_token:
				available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active pokemon too
		if main.player_active_pokemon != null and main.player_active_pokemon.is_bench_token:
			available_powers.append({"pokemon": main.player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	else:
		# Add bench token discards if they weren't already found via abilities
		for bp in main.player_bench:
			if bp.is_bench_token:
				var already_added = false
				for p in available_powers:
					if p["pokemon"] == bp:
						already_added = true
						break
				if not already_added:
					available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active too
		if main.player_active_pokemon != null and main.player_active_pokemon.is_bench_token:
			var already_added = false
			for p in available_powers:
				if p["pokemon"] == main.player_active_pokemon:
					already_added = true
					break
			if not already_added:
				available_powers.append({"pokemon": main.player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	
	# GYM1-107 Celadon City Gym (Stadium): treat as an activatable power. Add a synthetic entry that targets the stadium card itself.
	if main.trainer_effects.gym1_celadon_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Celadon City Gym", "type": "Stadium", "text": "Discard an Energy from one of your Erika Pokemon to cure it of all status conditions."}})

	# GYM2-114 Fuchsia City Gym (Stadium): once-per-turn flip → heads shuffles a Koga pokemon into deck
	if main.trainer_effects.gym2_fuchsia_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Fuchsia City Gym", "type": "Stadium", "text": "Flip a coin. Heads: shuffle 1 of your Koga Pokemon (with all attached cards) into your deck."}})

	# GYM2-122 Saffron City Gym (Stadium): return 1 basic Energy from a Sabrina pokemon to hand (unlimited)
	if main.trainer_effects.gym2_saffron_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Saffron City Gym", "type": "Stadium", "text": "Return 1 basic Energy from a Sabrina Pokemon to your hand."}})

	# basep-41 Lucky Stadium: per-turn flip to draw a card
	if main.trainer_effects.basep_lucky_stadium_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Lucky Stadium", "type": "Stadium", "text": "Flip a coin. If heads, draw 1 card."}})

	# neo3-61 Healing Field: once per turn, flip — heads removes 2 damage counters from your Active
	if main.trainer_effects.neo3_healing_field_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Healing Field", "type": "Stadium", "text": "Flip a coin. If heads, remove 2 damage counters from your Active Pokemon."}})

	# neo4-95 Radio Tower: once per turn, look at the top 2 cards of your deck
	if main.trainer_effects.neo4_radio_tower_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Radio Tower", "type": "Stadium", "text": "Look at the top 2 cards of your deck and put them back in the same order."}})

	# neo4-99 Energy Stadium: once per turn, flip — heads put a basic Energy from discard to hand
	if main.trainer_effects.neo4_energy_stadium_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Energy Stadium", "type": "Stadium", "text": "Flip a coin. If heads, put a basic Energy from your discard pile into your hand."}})

	# neo4-100 Lucky Stadium: once per turn, flip — heads draw a card (reuses the Lucky Stadium dispatch)
	if main.trainer_effects.neo4_lucky_stadium_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Lucky Stadium", "type": "Stadium", "text": "Flip a coin. If heads, draw 1 card."}})

	# Brock's Ninetales Shapeshift discard option — only when a form is attached
	for p_check in all_pokemon:
		if p_check.shapeshift_form_card != null:
			available_powers.append({"pokemon": p_check, "ability": {"name": "Discard Form", "type": "Pokémon Power", "text": "Discard the Evolution card attached as a Shapeshift form."}})

	if available_powers.size() == 0:
		await main.show_message("No Pokemon Powers available!")
		return

	# Create power buttons
	main.main_buttons_container.visible = false
	main.attack_buttons_container.visible = true

	for power_info in available_powers:
		var pokemon = power_info["pokemon"]
		var ability = power_info["ability"]
		var btn = Button.new()
		if pokemon == null:
			# Stadium activation entry
			btn.text = "STADIUM - " + ability.get("name", "")
		else:
			btn.text = pokemon.metadata.get("name", "") + " - " + ability.get("name", "")
		btn.custom_minimum_size = Vector2(450, 50)
		btn.theme = main.theme_blue
		main.attack_buttons_container.add_child(btn)
		btn.pressed.connect(activate_power.bind(pokemon, ability))

# Activates a specific Pokemon Power

func activate_power(pokemon: card_object, ability: Dictionary) -> void:
	main.hide_attack_buttons()
	_ensure_power_dispatch_ready()
	var ability_name = ability.get("name", "")
	if _power_dispatch.has(ability_name):
		await _power_dispatch[ability_name].call(pokemon)
		return
	await main.show_message("Power not implemented: " + ability_name)

# Damage Swap (Alakazam): Move 1 damage counter between your pokemon

func power_damage_swap(alakazam: card_object) -> void:
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	await main.show_message("DAMAGE SWAP: Move damage counters between your Pokemon")
	if main._should_bail(): return
	
	var keep_swapping = true
	while keep_swapping:
		# Select source (pokemon with damage)
		var sources = []
		for p in all_pokemon:
			if p.current_hp < int(p.metadata.get("hp", "0")):
				sources.append(p)
		if sources.size() == 0:
			await main.show_message("No Pokemon with damage!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "DAMAGE SWAP - SOURCE", "Select a Pokemon to take damage FROM (or cancel to stop)", "SELECT", true)
		if main._should_bail(): return

		if source == null:
			break

		# Select destination (pokemon that can take 1 more without KO)
		var destinations = []
		for p in all_pokemon:
			if p == source: continue
			if p.current_hp > 10:
				destinations.append(p)

		if destinations.size() == 0:
			await main.show_message("No Pokemon can receive the damage counter!")
			if main._should_bail(): return
			break

		var dest = await main.card_ops.prompt_select_card(destinations, "DAMAGE SWAP - DESTINATION", "Select a Pokemon to move damage TO", "MOVE", true)
		if main._should_bail(): return

		if dest == null:
			break
		
		# Move 1 damage counter
		source.current_hp += 10
		dest.current_hp -= 10
		main.display_hp_circles_above_align(main.player_active_pokemon, false)
		main.display_pokemon(false)
		await main.show_message("Moved 1 damage counter from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Rain Dance (Blastoise): Attach Water Energy from hand to Water Pokemon

func power_rain_dance(blastoise: card_object) -> void:
	await main.show_message("RAIN DANCE: Attach Water Energy to Water Pokemon!")
	if main._should_bail(): return
	
	var keep_going = true
	while keep_going:
		# Find Water Energy in hand
		var water_energies = []
		for card in main.player_hand:
			if card.metadata.get("supertype", "").to_lower() == "energy":
				if "Water" in card.metadata.get("name", ""):
					water_energies.append(card)
		
		if water_energies.size() == 0:
			await main.show_message("No Water Energy in hand!")
			if main._should_bail(): return
			break
		
		# Find Water Pokemon
		var water_pokemon = []
		if main.player_active_pokemon != null and "Water" in main.player_active_pokemon.metadata.get("types", []):
			water_pokemon.append(main.player_active_pokemon)
		for bp in main.player_bench:
			if "Water" in bp.metadata.get("types", []):
				water_pokemon.append(bp)
		
		if water_pokemon.size() == 0:
			await main.show_message("No Water Pokemon in play!")
			if main._should_bail(): return
			break
		
		# Select target
		var target = await main.card_ops.prompt_select_card(water_pokemon, "RAIN DANCE", "Select a Water Pokemon to attach energy to (cancel to stop)", "ATTACH", true)
		if main._should_bail(): return
		
		if target == null:
			break
		
		# Attach the first water energy
		var energy = water_energies[0]
		main.player_hand.erase(energy)
		target.attached_energies.append(energy)
		main.refresh_hand_display(false)
		main.display_active_pokemon_energies(false)
		await main.show_message("Attached Water Energy to " + target.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Energy Trans (Venusaur): Move Grass Energy between your Pokemon

func power_energy_trans(venusaur: card_object) -> void:
	await main.show_message("ENERGY TRANS: Move Grass Energy between your Pokemon!")
	if main._should_bail(): return
	
	var keep_going = true
	while keep_going:
		# Find pokemon with Grass Energy attached
		var all_pokemon = []
		if main.player_active_pokemon != null: all_pokemon.append(main.player_active_pokemon)
		all_pokemon.append_array(main.player_bench)
		
		var sources = []
		for p in all_pokemon:
			for e in p.attached_energies:
				if "Grass" in main.get_energy_provided_by_card(e):
					if p not in sources:
						sources.append(p)
		
		if sources.size() == 0:
			await main.show_message("No Pokemon with Grass Energy!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "ENERGY TRANS - SOURCE", "Select Pokemon to take Grass Energy from (cancel to stop)", "SELECT", true)
		if main._should_bail(): return

		if source == null:
			break

		# Find the grass energy to move
		var grass_energy: card_object = null
		for e in source.attached_energies:
			if "Grass" in main.get_energy_provided_by_card(e):
				grass_energy = e
				break
		if grass_energy == null:
			break

		# Select destination
		var destinations = all_pokemon.filter(func(p): return p != source)
		if destinations.size() == 0:
			break

		var dest = await main.card_ops.prompt_select_card(destinations, "ENERGY TRANS - DESTINATION", "Select Pokemon to move Grass Energy to", "MOVE", true)
		if main._should_bail(): return

		if dest == null:
			break
		
		source.attached_energies.erase(grass_energy)
		dest.attached_energies.append(grass_energy)
		main.display_active_pokemon_energies(false)
		await main.show_message("Moved Grass Energy from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Buzzap (Electrode): KO Electrode, attach as energy to another pokemon

func power_buzzap(electrode: card_object) -> void:
	# Cannot use if Electrode is the last pokemon
	var total_pokemon = (1 if main.player_active_pokemon != null else 0) + main.player_bench.size()
	if total_pokemon <= 1:
		await main.show_message("Cannot use Buzzap - Electrode is your last Pokemon!")
		if main._should_bail(): return
		return
	
	await main.show_message("BUZZAP: Electrode will be Knocked Out and become Energy!")
	if main._should_bail(): return
	
	# Select energy type
	var energy_types = ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Colorless"]
	# Use simple message-based selection for type
	# For simplicity, create a selection of fake energy cards
	var type_options = []
	for etype in energy_types:
		# Create a temporary card_object to represent each type
		var temp = card_object.new("base1-96", {"name": etype + " Energy", "supertype": "Energy"})
		type_options.append(temp)
	
	main.energy_type_selection_active = true
	main.show_enlarged_array_selection_mode(type_options)
	main.header_label.text = "BUZZAP - CHOOSE ENERGY TYPE"
	main.hint_label.text = "Select what type of Energy Electrode will become"
	main.action_button.text = "SELECT TYPE"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = true
	await main.energy_type_selected
	if main._should_bail(): return
	var chosen_type = ""
	if main.selected_card_for_action != null:
		chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "")
	main.energy_type_selection_active = false
	main.hide_selection_mode_display_main()
	
	# Temp type_options are RefCounted and will be freed automatically when out of scope
	
	if chosen_type == "":
		return
	
	# Select target pokemon
	var targets = main.player_bench.duplicate()
	if main.player_active_pokemon != null and main.player_active_pokemon != electrode:
		targets.append(main.player_active_pokemon)
	targets.erase(electrode)
	
	if targets.size() == 0:
		return
	
	var target = await main.card_ops.prompt_select_card(targets, "BUZZAP - ATTACH TO", "Select a Pokemon to attach Electrode-Energy to", "ATTACH", false)
	if main._should_bail(): return
	
	if target == null:
		return
	
	# KO Electrode (prize will be awarded via normal knockout flow)
	electrode.current_hp = 0
	
	# Create the electrode-as-energy token
	var electrode_energy = card_object.new(electrode.uid, electrode.metadata)
	electrode_energy.is_electrode_energy = true
	electrode_energy.electrode_energy_type = chosen_type
	target.attached_energies.append(electrode_energy)
	
	main.display_active_pokemon_energies(false)
	await main.show_message("Electrode became " + chosen_type + " Energy!")
	if main._should_bail(): return
	
	# Process the knockout
	await main.check_all_knockouts()
	if main._should_bail(): return

# Discard bench token (Clefairy Doll voluntary discard)

func power_bench_token_discard(token: card_object) -> void:
	var was_active = (token == main.player_active_pokemon)
	
	if was_active:
		# Remove from active slot
		main.player_active_pokemon = null
	else:
		main.player_bench.erase(token)
	
	main.send_card_to_discard(token, false)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	await main.show_message(token.metadata.get("name", "") + " was voluntarily discarded!")
	if main._should_bail(): return
	
	# If it was active, force a bench replacement (no prize awarded)
	if was_active:
		if main.player_bench.size() == 0:
			await main.show_message("No Pokemon remaining!")
			if main._should_bail(): return
			main.game_end_logic(true)  # true = player loses
			return
		main.knockout_bench_selection_active = true
		main.show_enlarged_array_selection_mode(main.player_bench)
		main.cancel_button.visible = false
		main.header_label.text = "CHOOSE NEW ACTIVE POKEMON"
		main.hint_label.text = "Your active was discarded - select a replacement"
		main.action_button.text = "SET ACTIVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.knockout_replacement_chosen
		if main._should_bail(): return
		main.display_active_pokemon_energies(false)



############################################### Section K: JUNGLE SET POWERS ###############################################################

# Get retreat cost reduction from Dodrio Retreat Aid
func get_retreat_cost_reduction(is_opponent: bool) -> int:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var reduction = 0
	for bp in bench:
		var abilities = bp.metadata.get("abilities", [])
		for ab in abilities:
			if ab.get("name", "") == "Retreat Aid":
				if not is_power_blocked_by_status(bp):
					reduction += 1
					print("RETREAT AID: Dodrio reduces retreat cost by 1")
	return reduction

# Shift (Venomoth): Change Venomoth's type to match another Pokemon in play
func power_shift(venomoth: card_object) -> void:
	if is_power_blocked_by_status(venomoth):
		await main.show_message("SHIFT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if venomoth.power_used_this_turn:
		await main.show_message("SHIFT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Find all unique types from pokemon in play (excluding Colorless)
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	var available_types: Array = []
	for p in all_pokemon:
		for ptype in p.metadata.get("types", []):
			if ptype != "Colorless" and ptype not in available_types:
				available_types.append(ptype)
	
	if available_types.size() == 0:
		await main.show_message("NO TYPES AVAILABLE TO SHIFT TO!")
		if main._should_bail(): return
		return
	
	# Create type selection using energy card representations
	var type_options = []
	for etype in available_types:
		var temp = card_object.new("base1-96", {"name": etype + " Energy", "supertype": "Energy"})
		type_options.append(temp)
	
	main.energy_type_selection_active = true
	main.show_enlarged_array_selection_mode(type_options)
	main.cancel_button.visible = true
	main.header_label.text = "SHIFT: CHOOSE NEW TYPE"
	main.hint_label.text = "Select the type Venomoth will become"
	main.action_button.text = "SHIFT"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	await main.energy_type_selected
	if main._should_bail(): return
	var chosen_type = ""
	if main.selected_card_for_action != null:
		chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "")
	main.energy_type_selection_active = false
	main.hide_selection_mode_display_main()
	
	if chosen_type == "":
		return
	
	venomoth.temporary_type = chosen_type
	venomoth.power_used_this_turn = true
	await main.show_message("VENOMOTH SHIFTED TO " + chosen_type.to_upper() + " TYPE!")
	if main._should_bail(): return
	print("POWER USED: Shift -> ", chosen_type)

# Heal (Vileplume): Flip coin, heads = remove 1 damage counter from 1 of your Pokemon
func power_heal_vileplume(vileplume: card_object) -> void:
	if is_power_blocked_by_status(vileplume):
		await main.show_message("HEAL IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if vileplume.power_used_this_turn:
		await main.show_message("HEAL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	vileplume.power_used_this_turn = true
	
	await main.show_message("HEAL: FLIPPING COIN...")
	if main._should_bail(): return
	# Activated only via the player's power menu — player flips.
	var coin = await main.flip_coin(false, false)
	
	if not coin:
		await main.show_message("TAILS! HEAL FAILED!")
		if main._should_bail(): return
		return
	
	# Find pokemon with damage
	var damaged = []
	if main.player_active_pokemon != null and main.player_active_pokemon.current_hp < int(main.player_active_pokemon.metadata.get("hp", "0")):
		damaged.append(main.player_active_pokemon)
	for bp in main.player_bench:
		if bp.current_hp < int(bp.metadata.get("hp", "0")):
			damaged.append(bp)
	
	if damaged.size() == 0:
		await main.show_message("NO POKEMON WITH DAMAGE!")
		if main._should_bail(): return
		return
	
	var target = await main.card_ops.prompt_select_card(damaged, "HEAL: CHOOSE POKEMON", "Select a Pokemon to remove 1 damage counter from", "HEAL", false)
	if main._should_bail(): return
	
	if target != null:
		# MATCH EFFECTS: no_healing / healing_multiplier gate
		var rule_heal = main.match_effects.modify_heal_amount(10, main.match_effects.is_card_on_opponent_side(target))
		if rule_heal <= 0:
			await main.show_message("SPECIAL MATCH RULE: HEALING IS BLOCKED!")
			if main._should_bail(): return
			return
		target.current_hp = min(int(target.metadata.get("hp", "0")), target.current_hp + rule_heal)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(target, false)
		await main.show_message("HEALED " + str(rule_heal) + " HP FROM " + target.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("POWER USED: Vileplume Heal on ", target.metadata.get("name", ""))

# Peek (Mankey): Look at top card of either deck, random card from opponent hand, or a prize card
func power_peek(mankey: card_object) -> void:
	if is_power_blocked_by_status(mankey):
		await main.show_message("PEEK IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if mankey.power_used_this_turn:
		await main.show_message("PEEK ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	mankey.power_used_this_turn = true
	
	# Create selection options
	main.special_attack_selection_active = true
	main.buttons_only_blocker.visible = true
	main.attack_buttons_container.visible = true
	main.main_buttons_container.visible = false
	for child in main.attack_buttons_container.get_children():
		if child.name == "cancel_attack_mode_button":
			child.visible = false
			continue
		child.queue_free()
	
	var options = ["Top of Your Deck", "Top of Opponent\'s Deck", "Random from Opponent\'s Hand", "One of Your Prizes", "One of Opponent\'s Prizes"]
	for i in range(options.size()):
		var btn = Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(400, 45)
		btn.theme = main.theme_blue
		main.attack_buttons_container.add_child(btn)
		btn.pressed.connect(func(): main.special_attack_selected.emit(i))
	
	var selected = await main.special_attack_selected
	
	for child in main.attack_buttons_container.get_children():
		if child.name == "cancel_attack_mode_button":
			child.visible = true
			continue
		child.queue_free()
	main.attack_buttons_container.visible = false
	main.main_buttons_container.visible = true
	main.special_attack_selection_active = false
	main.buttons_only_blocker.visible = false
	
	var peeked_card: card_object = null
	var peek_source = ""
	
	match selected:
		0: # Top of your deck
			if main.player_deck.size() > 0:
				peeked_card = main.player_deck[0]
				peek_source = "TOP OF YOUR DECK"
		1: # Top of opponent's deck
			if main.opponent_deck.size() > 0:
				peeked_card = main.opponent_deck[0]
				peek_source = "TOP OF OPPONENT\'S DECK"
		2: # Random from opponent's hand
			if main.opponent_hand.size() > 0:
				var rand_idx = randi() % main.opponent_hand.size()
				peeked_card = main.opponent_hand[rand_idx]
				peek_source = "OPPONENT\'S HAND"
		3: # One of your prizes
			if main.player_prize_cards.size() > 0:
				peeked_card = main.player_prize_cards[0]
				peek_source = "YOUR PRIZES"
		4: # One of opponent's prizes
			if main.opponent_prize_cards.size() > 0:
				peeked_card = main.opponent_prize_cards[0]
				peek_source = "OPPONENT\'S PRIZES"
	
	if peeked_card != null:
		# Show the card briefly
		main.show_enlarged_array_selection_mode([peeked_card])
		main.header_label.text = "PEEK: " + peek_source
		main.hint_label.text = peeked_card.metadata.get("name", "Unknown")
		main.action_button.text = "OK"
		main.action_button.disabled = false
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		main.hide_selection_mode_display_main()
		print("POWER USED: Peek at ", peek_source, " -> ", peeked_card.metadata.get("name", ""))
	else:
		await main.show_message("NOTHING TO PEEK AT!")
		if main._should_bail(): return

######################################################################################################################################################
############################################## BASE3 (FOSSIL) POWERS AND BODIES ######################################################################
######################################################################################################################################################

# STEP IN (Dragonite): Switch from bench to active. Once per turn. Must be on bench.
func power_step_in(dragonite: card_object) -> void:
	if dragonite.power_used_this_turn:
		await main.show_message("STEP IN ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if dragonite.current_location != "bench":
		await main.show_message("DRAGONITE MUST BE ON THE BENCH!")
		if main._should_bail(): return
		return
	
	if dragonite not in main.player_bench:
		await main.show_message("DRAGONITE MUST BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	
	dragonite.power_used_this_turn = true
	
	var old_active = main.player_active_pokemon
	
	await main.show_message("STEP IN: DRAGONITE SWITCHES IN!")
	if main._should_bail(): return
	
	await main.animate_retreat(old_active, dragonite, [], false)
	if main._should_bail(): return
	
	main.player_bench.erase(dragonite)
	main.player_bench.append(old_active)
	old_active.current_location = "bench"
	dragonite.current_location = "active"
	main.player_active_pokemon = dragonite
	main.clear_all_statuses(old_active, false)
	
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	print("STEP IN: Dragonite switched in, ", old_active.metadata.get("name", ""), " moved to bench")

# CURSE (Gengar): Move 1 damage counter from one opponent pokemon to another. Once per turn.
func power_curse(gengar: card_object) -> void:
	if gengar.power_used_this_turn:
		await main.show_message("CURSE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Get all opponent's pokemon with damage
	var opponent_pokemon: Array = []
	if main.opponent_active_pokemon != null:
		opponent_pokemon.append(main.opponent_active_pokemon)
	opponent_pokemon.append_array(main.opponent_bench)
	
	var sources: Array = []
	for p in opponent_pokemon:
		if p.current_hp < int(p.metadata.get("hp", "0")):
			sources.append(p)
	
	if sources.size() == 0:
		await main.show_message("NO OPPONENT POKEMON HAVE DAMAGE!")
		if main._should_bail(): return
		return
	
	if opponent_pokemon.size() < 2:
		await main.show_message("OPPONENT NEEDS 2+ POKEMON FOR CURSE!")
		if main._should_bail(): return
		return
	
	# Select source (take damage FROM)
	var source = await main.card_ops.prompt_select_card(sources, "CURSE: SELECT SOURCE", "Remove 1 damage counter from this Pokemon", "SELECT", true)
	if main._should_bail(): return

	if source == null:
		return

	# Select destination (move damage TO) — can KO
	var destinations: Array = []
	for p in opponent_pokemon:
		if p != source:
			destinations.append(p)

	if destinations.size() == 0:
		return

	var dest = await main.card_ops.prompt_select_card(destinations, "CURSE: SELECT TARGET", "Move the damage counter TO this Pokemon (can KO)", "CURSE", true)
	if main._should_bail(): return

	if dest == null:
		return
	
	gengar.power_used_this_turn = true
	source.current_hp = min(int(source.metadata.get("hp", "0")), source.current_hp + 10)
	dest.current_hp = max(0, dest.current_hp - 10)
	
	# Determine is_opponent for each pokemon for display
	var source_is_opp = (source == main.opponent_active_pokemon or source in main.opponent_bench)
	var dest_is_opp = (dest == main.opponent_active_pokemon or dest in main.opponent_bench)
	main.display_hp_circles_above_align(source, source_is_opp)
	main.display_hp_circles_above_align(dest, dest_is_opp)
	
	await main.show_message("CURSE: MOVED DAMAGE FROM " + source.metadata.get("name", "").to_upper() + " TO " + dest.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("CURSE: Moved 1 damage counter from ", source.metadata.get("name", ""), " to ", dest.metadata.get("name", ""))
	
	# Check if the curse KO'd the target
	if dest.current_hp <= 0:
		await main.check_all_knockouts()
		if main._should_bail(): return

# STRANGE BEHAVIOR (Slowbro): Move damage TO Slowbro from your other pokemon, as often as you like
func power_strange_behavior(slowbro: card_object) -> void:
	if is_power_blocked_by_status(slowbro):
		await main.show_message("STRANGE BEHAVIOR BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	await main.show_message("STRANGE BEHAVIOR: MOVE DAMAGE TO SLOWBRO")
	if main._should_bail(): return
	
	var keep_moving = true
	while keep_moving:
		# Find player pokemon with damage (excluding Slowbro)
		var all_pokemon: Array = []
		if main.player_active_pokemon != null:
			all_pokemon.append(main.player_active_pokemon)
		all_pokemon.append_array(main.player_bench)
		
		var sources: Array = []
		for p in all_pokemon:
			if p == slowbro:
				continue
			if p.current_hp < int(p.metadata.get("hp", "0")):
				sources.append(p)
		
		if sources.size() == 0:
			await main.show_message("NO OTHER POKEMON HAVE DAMAGE!")
			if main._should_bail(): return
			break
		
		# Check if Slowbro would be KO'd
		if slowbro.current_hp <= 10:
			await main.show_message("SLOWBRO CAN'T TAKE MORE DAMAGE WITHOUT BEING KO'D!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "STRANGE BEHAVIOR", "Move 1 damage counter TO Slowbro from this Pokemon (cancel to stop)", "MOVE DAMAGE", true)
		if main._should_bail(): return

		if source == null:
			break
		
		source.current_hp = min(int(source.metadata.get("hp", "0")), source.current_hp + 10)
		slowbro.current_hp = max(0, slowbro.current_hp - 10)
		
		var source_is_opp = (source == main.opponent_active_pokemon or source in main.opponent_bench)
		main.display_hp_circles_above_align(source, source_is_opp)
		var slowbro_is_opp = (slowbro == main.opponent_active_pokemon or slowbro in main.opponent_bench)
		main.display_hp_circles_above_align(slowbro, slowbro_is_opp)
		
		print("STRANGE BEHAVIOR: Moved damage from ", source.metadata.get("name", ""), " to Slowbro")

# COWARDICE (Tentacool): Return Tentacool to hand. Can't use on placement turn or with status.
func power_cowardice(tentacool: card_object) -> void:
	if is_power_blocked_by_status(tentacool):
		await main.show_message("COWARDICE BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if tentacool.placed_on_field_this_turn:
		await main.show_message("CAN'T USE COWARDICE ON THE TURN TENTACOOL WAS PLAYED!")
		if main._should_bail(): return
		return
	
	# Tentacool must be on bench or active
	var is_active = (tentacool == main.player_active_pokemon)
	
	if is_active and main.player_bench.size() == 0:
		await main.show_message("CAN'T RETURN ACTIVE WITH EMPTY BENCH!")
		if main._should_bail(): return
		return
	
	# Discard all attached cards
	var discard = main.player_discard_pile
	for e in tentacool.attached_energies:
		e.current_location = "discard"
		discard.append(e)
	tentacool.attached_energies.clear()
	for pre in tentacool.attached_pre_evolutions:
		pre.current_location = "discard"
		discard.append(pre)
	tentacool.attached_pre_evolutions.clear()
	for ac in tentacool.attached_cards:
		ac.current_location = "discard"
		discard.append(ac)
	tentacool.attached_cards.clear()
	
	# Return to hand
	if is_active:
		main.player_active_pokemon = null
		# Need to promote a bench pokemon
		tentacool.current_location = "hand"
		main.player_hand.append(tentacool)
		main.clear_all_statuses(tentacool, false)
		tentacool.pluspower_count = 0
		await main.show_message("COWARDICE: TENTACOOL RETURNED TO HAND!")
		if main._should_bail(): return
		# Handle post-knockout style replacement
		await main.handle_post_knockout(false)
		if main._should_bail(): return
	else:
		main.player_bench.erase(tentacool)
		tentacool.current_location = "hand"
		main.player_hand.append(tentacool)
		main.clear_all_statuses(tentacool, false)
		tentacool.pluspower_count = 0
		await main.show_message("COWARDICE: TENTACOOL RETURNED TO HAND!")
		if main._should_bail(): return
	
	main.display_pokemon(false)
	main.refresh_hand_display(false)
	main.display_active_pokemon_energies(false)
	main.update_discard_pile_display(false)
	print("COWARDICE: Tentacool returned to hand")

############################################### PASSIVE POWER/BODY HOOKS (called from main) #########################################################

# DITTO TRANSFORM: Apply/revert Transform based on active status
# Called after any switch, KO, or start of turn to keep Transform in sync
func update_ditto_transform(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var opposing_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	
	# Check if Toxic Gas shuts it down
	var toxic_gas = is_toxic_gas_active()
	
	# First: revert any benched Dittos that are still transformed
	for bp in bench:
		if bp != null and bp.is_ditto_transformed:
			bp.revert_ditto_transform()
			print("TRANSFORM: Reverted benched Ditto")
	
	# Second: handle active
	if active == null or opposing_active == null:
		return
	
	# Check if active is a Ditto with Transform
	var is_ditto = false
	var real_name = active.ditto_original_metadata.get("name", "") if active.is_ditto_transformed else active.metadata.get("name", "")
	if real_name == "Ditto":
		is_ditto = true
	if not active.is_ditto_transformed:
		# Check abilities on the current (untransformed) card
		for ability in active.metadata.get("abilities", []):
			if ability.get("name", "") == "Transform":
				is_ditto = true
				break
	
	if not is_ditto:
		return
	
	# Ditto is blocked by status (Asleep, Confused, Paralyzed)
	if active.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		if active.is_ditto_transformed:
			active.revert_ditto_transform()
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
			print("TRANSFORM: Reverted — Ditto has status condition")
		return
	
	# Toxic Gas blocks Transform
	if toxic_gas:
		if active.is_ditto_transformed:
			active.revert_ditto_transform()
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
			print("TRANSFORM: Reverted — Toxic Gas active")
		return
	
	# Check if already transformed into the current opposing active
	if active.is_ditto_transformed:
		if active.ditto_transform_uid == opposing_active.uid:
			# Already transformed into this exact card — no change needed
			return
		else:
			# Opposing active changed — revert and re-transform
			active.revert_ditto_transform()
	
	# Apply Transform: copy the opposing active's metadata
	active.apply_ditto_transform(opposing_active.metadata, opposing_active.uid)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	print("TRANSFORM: Ditto copied ", opposing_active.metadata.get("name", ""))

# Called when Ditto leaves play (KO, Scoop Up, Mr. Fuji, etc.) to ensure clean revert
func revert_ditto_if_needed(pokemon: card_object) -> void:
	if pokemon != null and pokemon.is_ditto_transformed:
		pokemon.revert_ditto_transform()
		print("TRANSFORM: Reverted Ditto leaving play")

# TRANSPARENCY (Haunter): When Haunter is attacked, flip coin. Heads = prevent all effects.
# Called BEFORE damage is applied. Returns true if attack is blocked.
func check_transparency(defender: card_object) -> bool:
	if defender == null:
		return false
	var abilities = defender.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Transparency":
			continue
		if is_power_blocked_by_status(defender):
			print("TRANSPARENCY: Blocked by status on ", defender.metadata.get("name", ""))
			return false
		# Check if Muk's Toxic Gas is active
		if is_toxic_gas_active():
			print("TRANSPARENCY: Blocked by Toxic Gas")
			return false
		# Defender (Haunter's controller) is the one flipping.
		var defender_is_opp: bool = defender == main.opponent_active_pokemon
		var coin = await main.flip_coin(false, defender_is_opp)
		if coin:
			await main.show_message("TRANSPARENCY: ATTACK BLOCKED!")
			if main._should_bail(): return true
			print("TRANSPARENCY: Blocked attack on Haunter (heads)")
			return true
		else:
			await main.show_message("TRANSPARENCY: TAILS! ATTACK HITS!")
			if main._should_bail(): return false
			print("TRANSPARENCY: Attack hits Haunter (tails)")
			return false
	return false

# KABUTO ARMOR (Kabuto): Halve incoming damage (rounded down to nearest 10)
# Called during damage calculation. Returns modified damage.
func apply_kabuto_armor(defender: card_object, damage: int) -> int:
	if defender == null:
		return damage
	var abilities = defender.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Kabuto Armor":
			continue
		if is_power_blocked_by_status(defender):
			print("KABUTO ARMOR: Blocked by status")
			return damage
		if is_toxic_gas_active():
			print("KABUTO ARMOR: Blocked by Toxic Gas")
			return damage
		var halved = int(floor(damage / 2.0 / 10.0)) * 10
		print("KABUTO ARMOR: Reduced ", damage, " -> ", halved)
		return halved
	return damage

# PREHISTORIC POWER (Aerodactyl): Block all evolution card plays
# Returns true if evolution should be blocked
func is_prehistoric_power_active() -> bool:
	# Check both sides for Aerodactyl with Prehistoric Power
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Prehistoric Power":
				continue
			if is_power_blocked_by_status(p):
				continue
			if is_toxic_gas_active():
				continue
			return true
	return false

# TOXIC GAS (Muk): Ignore all other Pokemon Powers
# Returns true if Toxic Gas is currently active
func is_toxic_gas_active() -> bool:
	# MATCH EFFECT: powers_blocked — all Powers/Bodies disabled for the whole match
	if main.match_effects.powers_blocked():
		return true
	# Goop Gas Attack trainer also disables all powers
	if main.goop_gas_active:
		return true
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Toxic Gas":
				continue
			# Toxic Gas is blocked by its own status conditions
			if p.special_condition in ["Paralyzed", "Asleep", "Confused"]:
				continue
			return true
	return false

# CLAIRVOYANCE (Omanyte): Opponent plays with hand face up
# Returns true if Clairvoyance is active (used for UI display)
func is_clairvoyance_active() -> bool:
	# Check player's side for Omanyte with Clairvoyance
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Clairvoyance":
				continue
			if is_power_blocked_by_status(p):
				continue
			if is_toxic_gas_active():
				continue
			return true
	return false

############################################### Section H: CPU POWER ACTIVATION ######################################################################

# CPU activates beneficial powers at start of turn

func cpu_phase_activate_powers() -> void:
	# Note: Toxic Gas blocks individual powers. Each power section checks is_toxic_gas_active()
	# or is_power_blocked_by_status() as appropriate. Rain Dance/Energy Trans/etc. are also
	# blocked by Toxic Gas since they are Pokemon Powers.
	var toxic_gas = is_toxic_gas_active()

	# basep-41 Lucky Stadium: CPU always flips for a free draw
	if main.trainer_effects.basep_lucky_stadium_has_target(true):
		await main.trainer_effects.basep_lucky_stadium_activate(true)
		if main._should_bail(): return

	# neo3-61 Healing Field: CPU uses if its Active pokemon has damage
	if main.trainer_effects.neo3_healing_field_active():
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.current_hp < main.opponent_active_pokemon.get_max_hp():
			await main.trainer_effects.neo3_healing_field_activate(true)
			if main._should_bail(): return

	# basep-5 Special Delivery (Dragonite): CPU draws if deck not empty
	if not toxic_gas:
		var dragonite = _find_cpu_pokemon_with_power("Special Delivery")
		if dragonite != null and not is_power_blocked_by_status(dragonite) and not dragonite.power_used_this_turn:
			if main.opponent_deck.size() > 0:
				await power_special_delivery(dragonite)
				if main._should_bail(): return

	# basep-11 Chain Reaction (Eevee): CPU evolves all Eevees if it has evolution cards in hand
	if not toxic_gas:
		var cr_eevee = _find_cpu_pokemon_with_power("Chain Reaction")
		if cr_eevee != null and not is_power_blocked_by_status(cr_eevee) and not cr_eevee.power_used_this_turn:
			var has_eevee_evo: bool = false
			for c in main.opponent_hand:
				if c.metadata.get("evolvesFrom", "") == "Eevee":
					has_eevee_evo = true
					break
			if has_eevee_evo:
				await power_chain_reaction(cr_eevee)
				if main._should_bail(): return

	# basep-13 Solar Power (Venusaur): CPU clears status if own active or opponent's active has status
	if not toxic_gas:
		var venusaur = _find_cpu_pokemon_with_power("Solar Power")
		if venusaur != null and not is_power_blocked_by_status(venusaur) and not venusaur.power_used_this_turn:
			var own_afflicted = main.opponent_active_pokemon != null and (main.opponent_active_pokemon.special_condition != "" or main.opponent_active_pokemon.is_poisoned)
			var opp_afflicted = main.player_active_pokemon != null and (main.player_active_pokemon.special_condition != "" or main.player_active_pokemon.is_poisoned)
			if own_afflicted or opp_afflicted:
				await power_solar_power(venusaur)
				if main._should_bail(): return

	# GYM1-107 Celadon City Gym (Stadium): activate if CPU has a status-afflicted Erika pokemon with energy.
	# Not affected by toxic_gas (Stadium card, not a Pokemon Power).
	if main.trainer_effects.gym1_celadon_has_target(true):
		await main.trainer_effects.gym1_celadon_activate(true)
		if main._should_bail(): return

	# GYM2-114 Fuchsia City Gym (Stadium): activate if CPU has a damaged Koga pokemon worth recovering.
	# Heuristic: only fire if a Koga pokemon has >= 40 damage (worth the deck recycle / coin flip risk).
	if main.trainer_effects.gym2_fuchsia_has_target(true):
		var fuchsia_should_use = false
		var fuchsia_candidates: Array = []
		if main.opponent_active_pokemon != null and "Koga" in main.opponent_active_pokemon.metadata.get("name", ""):
			fuchsia_candidates.append(main.opponent_active_pokemon)
		for bp in main.opponent_bench:
			if "Koga" in bp.metadata.get("name", ""):
				fuchsia_candidates.append(bp)
		for p in fuchsia_candidates:
			var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
			if dmg >= 40:
				fuchsia_should_use = true
				break
		if fuchsia_should_use:
			await main.trainer_effects.gym2_fuchsia_activate(true)
			if main._should_bail(): return

	# GYM2-122 Saffron City Gym (Stadium): return basic Energy to hand from Sabrina pokemon.
	# Heuristic: only use if CPU has an OVER-energized Sabrina pokemon (more attached than needed for any attack).
	while main.trainer_effects.gym2_saffron_has_target(true):
		var saffron_used = false
		var active = main.opponent_active_pokemon
		var sabrina_targets: Array = []
		if active != null and "Sabrina" in active.metadata.get("name", ""):
			sabrina_targets.append(active)
		for bp in main.opponent_bench:
			if "Sabrina" in bp.metadata.get("name", ""):
				sabrina_targets.append(bp)
		var any_excess = false
		for p in sabrina_targets:
			# Excess energy = more attached than the highest-cost attack
			var max_cost = 0
			for atk in p.metadata.get("attacks", []):
				var c = atk.get("cost", []).size()
				if c > max_cost:
					max_cost = c
			var basics = 0
			for e in p.attached_energies:
				if main.is_basic_energy_card(e):
					basics += 1
			if basics > max_cost:
				any_excess = true
				break
		if not any_excess:
			break
		await main.trainer_effects.gym2_saffron_activate(true)
		if main._should_bail(): return
		saffron_used = true

	# Rain Dance: attach all Water Energy to Water Pokemon
	var blastoise = _find_cpu_pokemon_with_power("Rain Dance")
	if blastoise != null and not is_power_blocked_by_status(blastoise) and not toxic_gas:
		var keep_going = true
		while keep_going:
			keep_going = false
			var water_energy: card_object = null
			for card in main.opponent_hand:
				if card.metadata.get("supertype", "").to_lower() == "energy" and "Water" in card.metadata.get("name", ""):
					water_energy = card
					break
			if water_energy == null:
				break
			# Find best Water Pokemon target
			var best_target: card_object = null
			var best_unmet = 999
			var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
			for p in all_pokemon:
				if "Water" not in p.metadata.get("types", []):
					continue
				for attack in p.metadata.get("attacks", []):
					var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
					if unmet > 0 and unmet < best_unmet:
						best_unmet = unmet
						best_target = p
			if best_target == null:
				break
			main.opponent_hand.erase(water_energy)
			best_target.attached_energies.append(water_energy)
			await main.show_message("Rain Dance: Attached Water Energy to " + best_target.metadata.get("name", "") + "!")
			if main._should_bail(): return
			main.refresh_hand_display(true)
			main.display_active_pokemon_energies(true)
			keep_going = true
	
	# Energy Trans: consolidate Grass Energy to the pokemon that needs it most
	var venusaur = _find_cpu_pokemon_with_power("Energy Trans")
	if venusaur != null and not is_power_blocked_by_status(venusaur) and not toxic_gas:
		# Find pokemon that needs Grass Energy most
		var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
		var best_target: card_object = null
		var best_unmet = 999
		for p in all_pokemon:
			for attack in p.metadata.get("attacks", []):
				var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
				if unmet > 0 and unmet < best_unmet:
					for req in attack.get("cost", []):
						if req == "Grass":
							best_unmet = unmet
							best_target = p
							break
		if best_target != null:
			# Find a source with spare Grass Energy
			for p in all_pokemon:
				if p == best_target:
					continue
				for e in p.attached_energies.duplicate():
					if "Grass" in main.get_energy_provided_by_card(e):
						p.attached_energies.erase(e)
						best_target.attached_energies.append(e)
						await main.show_message("Energy Trans: Moved Grass Energy to " + best_target.metadata.get("name", "") + "!")
						if main._should_bail(): return
						main.display_active_pokemon_energies(true)
						break
	
	# Vileplume Heal: CPU tries to heal damaged pokemon
	var vileplume = _find_cpu_pokemon_with_power("Heal")
	if vileplume != null and not is_power_blocked_by_status(vileplume) and not toxic_gas and not vileplume.power_used_this_turn:
		vileplume.power_used_this_turn = true
		# Only use if there's damage to heal
		var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
		var most_damaged: card_object = null
		var most_damage = 0
		for p in all_cpu:
			var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
			if dmg > most_damage:
				most_damage = dmg
				most_damaged = p
		if most_damaged != null and most_damage > 0:
			# CPU Vileplume Heal — opponent flips.
			var coin = await main.flip_coin(false, true)
			if coin:
				most_damaged.current_hp = min(int(most_damaged.metadata.get("hp", "0")), most_damaged.current_hp + 10)
				main.display_hp_circles_above_align(most_damaged, true)
				await main.show_message("Vileplume Heal: Healed 10 HP from " + most_damaged.metadata.get("name", "") + "!")
				if main._should_bail(): return
			else:
				await main.show_message("Vileplume Heal: Tails! Failed!")
				if main._should_bail(): return
	
	# Venomoth Shift: CPU shifts to the type that gives best coverage
	var venomoth = _find_cpu_pokemon_with_power("Shift")
	if venomoth != null and not is_power_blocked_by_status(venomoth) and not toxic_gas and not venomoth.power_used_this_turn:
		# Shift to the type that the player's active is weak to
		var player_weaknesses = main.player_active_pokemon.metadata.get("weaknesses", []) if main.player_active_pokemon != null else []
		if player_weaknesses.size() > 0:
			var weak_type = player_weaknesses[0].get("type", "")
			if weak_type != "" and weak_type != "Colorless":
				venomoth.temporary_type = weak_type
				venomoth.power_used_this_turn = true
				await main.show_message("Venomoth Shift: Changed to " + weak_type + " type!")
				if main._should_bail(): return
	
	
	# Damage Swap: move damage off active to bench with most buffer
	var alakazam = _find_cpu_pokemon_with_power("Damage Swap")
	if alakazam != null and not is_power_blocked_by_status(alakazam) and not toxic_gas:
		var active = main.opponent_active_pokemon
		if active != null:
			var active_damage = int(active.metadata.get("hp", "0")) - active.current_hp
			while active_damage >= 10:
				# Find bench pokemon with most HP buffer
				var best_buffer: card_object = null
				var best_hp = 0
				for bp in main.opponent_bench:
					var buffer = bp.current_hp - 10
					if buffer > best_hp:
						best_hp = buffer
						best_buffer = bp
				if best_buffer == null or best_hp <= 0:
					break
				active.current_hp += 10
				best_buffer.current_hp -= 10
				active_damage -= 10
			main.display_hp_circles_above_align(main.opponent_active_pokemon, true)
	
	# Buzzap (Electrode): KO Electrode to become 2 energy of chosen type on another pokemon
	# CPU uses Buzzap when: another pokemon is 2+ energy short of attacking, Electrode is on bench,
	# and there are enough total pokemon to survive the prize loss
	var electrode_buzzap = _find_cpu_pokemon_with_power("Buzzap")
	if electrode_buzzap != null and not toxic_gas:
		if not is_power_blocked_by_status(electrode_buzzap):
			var total_pokemon = (1 if main.opponent_active_pokemon != null else 0) + main.opponent_bench.size()
			if total_pokemon > 1 and electrode_buzzap != main.opponent_active_pokemon:
				# Find a pokemon that needs 2+ energy to attack
				var best_target: card_object = null
				var best_type: String = ""
				var best_unmet = 0
				var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
				for p in all_cpu:
					if p == electrode_buzzap:
						continue
					for attack in p.metadata.get("attacks", []):
						var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
						if unmet >= 2 and unmet > best_unmet:
							# Find what type is needed most
							var cost = attack.get("cost", [])
							var type_counts = {}
							for c in cost:
								if c != "Colorless":
									type_counts[c] = type_counts.get(c, 0) + 1
							if type_counts.size() > 0:
								var needed_type = ""
								var needed_count = 0
								for t in type_counts:
									if type_counts[t] > needed_count:
										needed_count = type_counts[t]
										needed_type = t
								best_target = p
								best_type = needed_type
								best_unmet = unmet
							else:
								# All colorless cost — provide Lightning (Electrode's type)
								best_target = p
								best_type = "Lightning"
								best_unmet = unmet
				
				if best_target != null and best_type != "":
					# Execute Buzzap
					electrode_buzzap.current_hp = 0
					var electrode_energy = card_object.new(electrode_buzzap.uid, electrode_buzzap.metadata)
					electrode_energy.is_electrode_energy = true
					electrode_energy.electrode_energy_type = best_type
					best_target.attached_energies.append(electrode_energy)
					main.display_active_pokemon_energies(true)
					await main.show_message("Buzzap: Electrode became " + best_type + " Energy for " + best_target.metadata.get("name", "") + "!")
					if main._should_bail(): return
					await main.check_all_knockouts()
					if main._should_bail(): return
	
	# --- BASE3 POWERS ---
	
	# Step In (Dragonite): Switch to active if better than current active
	var dragonite = _find_cpu_bench_pokemon_with_power("Step In")
	if dragonite != null and not dragonite.power_used_this_turn:
		if not is_power_blocked_by_status(dragonite) and not is_toxic_gas_active():
			var active = main.opponent_active_pokemon
			if active != null:
				# Switch in if Dragonite has better attack readiness
				var dragonite_ready = false
				for attack in dragonite.metadata.get("attacks", []):
					if main.cpu_ai.get_unmet_energy_count(attack, dragonite) == 0:
						dragonite_ready = true
						break
				var active_hp_pct = float(active.current_hp) / float(int(active.metadata.get("hp", "1")))
				if dragonite_ready and active_hp_pct < 0.4:
					# Active is low, Dragonite is ready — switch
					dragonite.power_used_this_turn = true
					var old_active = main.opponent_active_pokemon
					main.opponent_bench.erase(dragonite)
					main.opponent_bench.append(old_active)
					old_active.current_location = "bench"
					dragonite.current_location = "active"
					main.opponent_active_pokemon = dragonite
					main.clear_all_statuses(old_active, true)
					main.display_pokemon(true)
					main.display_active_pokemon_energies(true)
					await main.show_message("Step In: Dragonite switches in!")
					if main._should_bail(): return
	
	# Curse (Gengar): Move damage to opponent's active for KO potential
	var gengar = _find_cpu_pokemon_with_power("Curse")
	if gengar != null and not gengar.power_used_this_turn:
		if not is_power_blocked_by_status(gengar) and not is_toxic_gas_active():
			var player_pokemon: Array = []
			if main.player_active_pokemon != null:
				player_pokemon.append(main.player_active_pokemon)
			player_pokemon.append_array(main.player_bench)
			
			# Find a source with damage that isn't the active
			var best_source: card_object = null
			var best_dest: card_object = null
			
			# Strategy: move damage TO the player's active if it helps KO
			if main.player_active_pokemon != null and main.player_active_pokemon.current_hp <= 10:
				# Active already almost dead, skip
				pass
			elif main.player_active_pokemon != null:
				# Find source with damage on bench
				for bp in main.player_bench:
					if bp.current_hp < int(bp.metadata.get("hp", "0")):
						best_source = bp
						best_dest = main.player_active_pokemon
						break
			
			if best_source != null and best_dest != null:
				gengar.power_used_this_turn = true
				best_source.current_hp = min(int(best_source.metadata.get("hp", "0")), best_source.current_hp + 10)
				best_dest.current_hp = max(0, best_dest.current_hp - 10)
				main.display_hp_circles_above_align(best_source, false)
				main.display_hp_circles_above_align(best_dest, false)
				await main.show_message("Curse: Moved damage to " + best_dest.metadata.get("name", "") + "!")
				if main._should_bail(): return
				if best_dest.current_hp <= 0:
					await main.check_all_knockouts()
					if main._should_bail(): return
	
	# Strange Behavior (Slowbro): Move damage off CPU active to Slowbro
	var slowbro = _find_cpu_pokemon_with_power("Strange Behavior")
	if slowbro != null and not is_power_blocked_by_status(slowbro) and not is_toxic_gas_active():
		var active = main.opponent_active_pokemon
		if active != null and active != slowbro:
			var active_damage = int(active.metadata.get("hp", "0")) - active.current_hp
			while active_damage >= 10 and slowbro.current_hp > 10:
				active.current_hp += 10
				slowbro.current_hp -= 10
				active_damage -= 10
			main.display_hp_circles_above_align(active, true)
			var slowbro_is_active = (slowbro == main.opponent_active_pokemon)
			main.display_hp_circles_above_align(slowbro, true)
	
	# Cowardice (Tentacool): CPU returns Tentacool if badly damaged
	var tentacool = _find_cpu_pokemon_with_power("Cowardice")
	if tentacool != null and not is_power_blocked_by_status(tentacool) and not is_toxic_gas_active():
		if not tentacool.placed_on_field_this_turn:
			var max_hp = int(tentacool.metadata.get("hp", "0"))
			if tentacool.current_hp <= max_hp / 2:
				# Return to hand
				var discard = main.opponent_discard_pile
				for e in tentacool.attached_energies:
					e.current_location = "discard"
					discard.append(e)
				tentacool.attached_energies.clear()
				for pre in tentacool.attached_pre_evolutions:
					pre.current_location = "discard"
					discard.append(pre)
				tentacool.attached_pre_evolutions.clear()
				for ac in tentacool.attached_cards:
					ac.current_location = "discard"
					discard.append(ac)
				tentacool.attached_cards.clear()

				var is_active = (tentacool == main.opponent_active_pokemon)
				if is_active:
					main.opponent_active_pokemon = null
				else:
					main.opponent_bench.erase(tentacool)
				tentacool.current_location = "hand"
				main.opponent_hand.append(tentacool)
				main.clear_all_statuses(tentacool, true)
				tentacool.pluspower_count = 0
				main.update_discard_pile_display(true)
				main.display_pokemon(true)
				main.refresh_hand_display(true)
				await main.show_message("Cowardice: Tentacool returned to hand!")
				if main._should_bail(): return
				if is_active:
					await main.handle_post_knockout(true)
					if main._should_bail(): return
	
	# --- BASE5 CPU POWER ACTIVATIONS ---
	
	# Evolutionary Light (Dark Dragonair): Search deck for Evolution card
	var dragonair = _find_cpu_pokemon_with_power("Evolutionary Light")
	if dragonair != null and not dragonair.power_used_this_turn and not dragonair.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(dragonair) and not toxic_gas:
			var cpu_deck = main.opponent_deck
			var evolutions: Array = []
			for card in cpu_deck:
				var subtypes = card.metadata.get("subtypes", [])
				if "Stage 1" in subtypes or "Stage 2" in subtypes:
					evolutions.append(card)
			if evolutions.size() > 0:
				# Pick evolution that matches something on field
				var best: card_object = null
				var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
				for evo in evolutions:
					var evolves_from = evo.metadata.get("evolvesFrom", "")
					for p in all_cpu:
						if p.metadata.get("name", "") == evolves_from:
							best = evo
							break
					if best != null:
						break
				if best == null:
					best = evolutions[0]
				cpu_deck.erase(best)
				best.current_location = "hand"
				main.opponent_hand.append(best)
				cpu_deck.shuffle()
				dragonair.power_used_this_turn = true
				main.refresh_hand_display(true)
				await main.show_message("Evolutionary Light: Found " + best.metadata.get("name", "") + "!")
				if main._should_bail(): return
	
	# Matter Exchange (Dark Kadabra): Discard 1, draw 1
	var kadabra = _find_cpu_pokemon_with_power("Matter Exchange")
	if kadabra != null and not kadabra.power_used_this_turn and not kadabra.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(kadabra) and not toxic_gas:
			if main.opponent_hand.size() >= 2 and main.opponent_deck.size() > 0:
				var to_discard = main.trainer_effects.cpu_get_discard_priority(main.opponent_hand, 1)
				if to_discard.size() > 0:
					var card = to_discard[0]
					main.opponent_hand.erase(card)
					card.current_location = "discard"
					main.opponent_discard_pile.append(card)
					await main.card_ops.draw_n(true, 1)
					if main._should_bail(): return
					kadabra.power_used_this_turn = true
					await main.show_message("Matter Exchange: Swapped a card!")
					if main._should_bail(): return
	
	# Pollen Stench (Dark Gloom): Flip for confusion
	var gloom = _find_cpu_pokemon_with_power("Pollen Stench")
	if gloom != null and not gloom.power_used_this_turn and not gloom.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(gloom) and not toxic_gas:
			# Only use if player active isn't already confused
			if main.player_active_pokemon != null and main.player_active_pokemon.special_condition != "Confused":
				# CPU's Gloom — opponent flips.
				var coin = await main.flip_coin(false, true)
				gloom.power_used_this_turn = true
				if coin:
					main.card_ops.apply_status(main.player_active_pokemon, "Confused", false)
					await main.show_message("Pollen Stench: Defending Pokemon is Confused!")
					if main._should_bail(): return
				else:
					# Tails: own active confused
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						main.card_ops.apply_status(cpu_active, "Confused", true)
						await main.show_message("Pollen Stench: Tails! Own active is Confused!")
						if main._should_bail(): return
	
	# Gather Fire (Charmander): Move Fire Energy from another Pokemon
	var charmander = _find_cpu_pokemon_with_power("Gather Fire")
	if charmander != null and not charmander.power_used_this_turn and not charmander.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(charmander) and not toxic_gas:
			var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
			var best_source: card_object = null
			var best_energy: card_object = null
			for p in all_cpu:
				if p == charmander:
					continue
				for e in p.attached_energies:
					var provided = main.get_energy_provided_by_card(e)
					if "Fire" in provided:
						# Only take if source has spare energy
						if p.attached_energies.size() > 1:
							best_source = p
							best_energy = e
							break
				if best_energy != null:
					break
			if best_source != null and best_energy != null:
				best_source.attached_energies.erase(best_energy)
				charmander.attached_energies.append(best_energy)
				charmander.power_used_this_turn = true
				main.display_active_pokemon_energies(true)
				await main.show_message("Gather Fire: Moved Fire Energy to Charmander!")
				if main._should_bail(): return
	
	# Long-Distance Hypnosis (Drowzee): Flip for sleep
	var drowzee = _find_cpu_pokemon_with_power("Long-Distance Hypnosis")
	if drowzee != null and not drowzee.power_used_this_turn and not drowzee.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(drowzee) and not toxic_gas:
			if main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "":
				# CPU's Drowzee — opponent flips.
				var coin = await main.flip_coin(false, true)
				drowzee.power_used_this_turn = true
				if coin:
					main.card_ops.apply_status(main.player_active_pokemon, "Asleep", false)
					await main.show_message("Long-Distance Hypnosis: Defending Pokemon is Asleep!")
					if main._should_bail(): return
				else:
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						main.card_ops.apply_status(cpu_active, "Asleep", true)
						await main.show_message("Long-Distance Hypnosis: Tails! Own active is Asleep!")
						if main._should_bail(): return
	
	# Trickery (Rattata): Switch prize with top of deck — CPU uses if deck top might be better
	var rattata = _find_cpu_pokemon_with_power("Trickery")
	if rattata != null and not rattata.power_used_this_turn and not rattata.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(rattata) and not toxic_gas:
			if main.opponent_prize_cards.size() > 0 and main.opponent_deck.size() > 0:
				# Simple heuristic: use if prizes > 3 remaining (more chances to improve)
				if main.opponent_prize_cards.size() >= 3:
					var top_card = main.opponent_deck[0]
					var prize_idx = 0
					main.opponent_deck.erase(top_card)
					var prize_card = main.opponent_prize_cards[prize_idx]
					main.opponent_prize_cards[prize_idx] = top_card
					main.opponent_deck.insert(0, prize_card)
					rattata.power_used_this_turn = true
					await main.show_message("Trickery: Swapped a prize with top of deck!")
					if main._should_bail(): return

	# --- GYM1 + GYM2 POWERS ---
	await cpu_phase_gym_powers()
	if main._should_bail(): return

	# --- NEO1 POWERS ---
	await cpu_phase_neo1_powers()
	if main._should_bail(): return
	# --- NEO2 POWERS ---
	await cpu_phase_neo2_powers()
	if main._should_bail(): return
	# --- NEO3 POWERS ---
	await cpu_phase_neo3_powers()
	if main._should_bail(): return
	# --- NEO4 POWERS ---
	await cpu_phase_neo4_powers()
	if main._should_bail(): return


# Helper to find a CPU pokemon with a specific power name

func _find_cpu_pokemon_with_power(power_name: String) -> card_object:
	var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
	for p in all_pokemon:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == power_name:
				return p
	return null

# Helper to find a CPU bench pokemon with a specific power name
func _find_cpu_bench_pokemon_with_power(power_name: String) -> card_object:
	for p in main.opponent_bench:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == power_name:
				return p
	return null

############################################### Section I: MACHAMP STRIKES BACK HOOK #################################################################

# Called after damage is applied to a pokemon - checks for Machamp's Strikes Back

func check_strikes_back(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var abilities = damaged_pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Strikes Back":
			continue
		if is_power_blocked_by_status(damaged_pokemon):
			print("STRIKES BACK: Blocked by status on ", damaged_pokemon.metadata.get("name", ""))
			return
		# Deal 10 damage to the attacker, ignoring weakness/resistance
		attacker.current_hp = max(0, attacker.current_hp - 10)
		var attacker_is_opp = not is_damaged_opponent
		main.display_hp_circles_above_align(attacker, attacker_is_opp)
		# Show floating label for the -10HP on the attacker
		var attacker_label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
		main.show_floating_label("-10HP", attacker_label_pos, true)
		await main.show_message(damaged_pokemon.metadata.get("name", "") + "'s STRIKES BACK dealt 10 damage to " + attacker.metadata.get("name", "") + "!")
		print("STRIKES BACK: 10 damage to ", attacker.metadata.get("name", ""))

############################################### Section J: DOUBLE COLORLESS ENERGY HANDLING ##########################################################

# Check if a card is Double Colorless Energy (Special Energy)

######################################################################################################################################################
################################################### BASE5 (TEAM ROCKET) POWERS AND BODIES ############################################################
######################################################################################################################################################

# --- HAY FEVER CHECK ---
func is_hay_fever_active() -> bool:
	# Check if any Dark Vileplume in play has Hay Fever active
	# Goop Gas also disables this
	if main.goop_gas_active:
		return false
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	for p in all_pokemon:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == "Hay Fever":
				if not is_power_blocked_by_status(p):
					return true
	return false

# --- SINKHOLE: Called when opponent's active retreats ---
func check_sinkhole(retreating_pokemon: card_object, is_retreating_opponent: bool) -> void:
	# Sinkhole triggers on the OPPOSING side's retreat
	# Find Dark Dugtrio on the side that is NOT retreating
	var dugtrio: card_object = null
	if is_retreating_opponent:
		# Opponent is retreating, check player's side for Dugtrio
		var player_all: Array = []
		if main.player_active_pokemon != null:
			player_all.append(main.player_active_pokemon)
		player_all.append_array(main.player_bench)
		for p in player_all:
			for ability in p.metadata.get("abilities", []):
				if ability.get("name", "") == "Sinkhole":
					dugtrio = p
					break
			if dugtrio != null:
				break
	else:
		# Player is retreating, check opponent's side for Dugtrio
		var opp_all: Array = []
		if main.opponent_active_pokemon != null:
			opp_all.append(main.opponent_active_pokemon)
		opp_all.append_array(main.opponent_bench)
		for p in opp_all:
			for ability in p.metadata.get("abilities", []):
				if ability.get("name", "") == "Sinkhole":
					dugtrio = p
					break
			if dugtrio != null:
				break
	
	if dugtrio == null:
		return
	if is_power_blocked_by_status(dugtrio):
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return

	# Dugtrio's controller (Sinkhole owner) flips — opposite of retreating side.
	var coin = await main.flip_coin(false, not is_retreating_opponent)
	if not coin:
		# Tails: 20 damage to retreating pokemon (no W/R)
		retreating_pokemon.current_hp = max(0, retreating_pokemon.current_hp - 20)
		main.display_hp_circles_above_align(retreating_pokemon, is_retreating_opponent)
		await main.show_message("SINKHOLE! 20 DAMAGE TO " + retreating_pokemon.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("SINKHOLE: HEADS! NO DAMAGE!")
		if main._should_bail(): return
	print("POWER CHECK: Sinkhole - coin was ", "tails" if not coin else "heads")

# --- SNEAK ATTACK: When Dark Golbat played from hand, 10 damage to chosen opponent Pokemon ---
func trigger_sneak_attack(golbat: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var all_targets: Array = []
	if is_opponent:
		if main.player_active_pokemon != null:
			all_targets.append(main.player_active_pokemon)
		all_targets.append_array(main.player_bench)
	else:
		if main.opponent_active_pokemon != null:
			all_targets.append(main.opponent_active_pokemon)
		all_targets.append_array(main.opponent_bench)
	
	if all_targets.size() == 0:
		return
	
	await main.show_message("SNEAK ATTACK!")
	if main._should_bail(): return
	
	var selected: card_object = null
	
	if not is_opponent:
		# Player chooses target
		selected = await main.card_ops.prompt_select_card(all_targets, "CHOOSE POKÉMON FOR SNEAK ATTACK", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks lowest HP target
		all_targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = all_targets[0]
	
	if selected == null:
		return
	
	# 10 damage WITH Weakness and Resistance
	var golbat_types = golbat.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(10, golbat_types, selected)
	selected.current_hp = max(0, selected.current_hp - result["damage"])
	
	var is_target_opp = !is_opponent
	main.display_hp_circles_above_align(selected, is_target_opp)
	await main.show_message("SNEAK ATTACK: " + str(result["damage"]) + " DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER: Sneak Attack dealt ", result["damage"], " to ", selected.metadata.get("name", ""))

# --- FINAL BEAM: When Dark Gyarados is KO'd, flip heads = 20×Water Energy damage to attacker ---
func check_final_beam(gyarados: card_object, attacker: card_object, is_gyarados_opponent: bool) -> void:
	if gyarados == null or attacker == null:
		return
	
	var has_final_beam = false
	for ability in gyarados.metadata.get("abilities", []):
		if ability.get("name", "") == "Final Beam":
			has_final_beam = true
			break
	
	if not has_final_beam:
		return
	if is_power_blocked_by_status(gyarados):
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	# Count Water Energy
	var water_count = 0
	for e in gyarados.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Water" in provided:
			water_count += 1
	
	if water_count == 0:
		return

	# Gyarados (Final Beam) owner flips on its own KO.
	var coin = await main.flip_coin(false, is_gyarados_opponent)
	if coin:
		var damage = 20 * water_count
		# Apply with W/R
		var gyarados_types = gyarados.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(damage, gyarados_types, attacker)
		attacker.current_hp = max(0, attacker.current_hp - result["damage"])
		main.display_hp_circles_above_align(attacker, !is_gyarados_opponent)
		await main.show_message("FINAL BEAM! " + str(result["damage"]) + " DAMAGE TO " + attacker.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("POWER: Final Beam dealt ", result["damage"])
	else:
		await main.show_message("FINAL BEAM: TAILS! NO EFFECT!")
		if main._should_bail(): return

# --- SUMMON MINIONS: When Dark Dragonite played from hand, search deck for up to 2 basics ---
func trigger_summon_minions(dragonite: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var bench = main.opponent_bench if is_opponent else main.player_bench
	
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL! CAN'T SUMMON MINIONS!")
		if main._should_bail(): return
		return
	
	var basics: Array = []
	for card in deck:
		if main.is_basic_pokemon(card):
			basics.append(card)
	
	if basics.size() == 0:
		await main.show_message("NO BASIC POKÉMON IN DECK!")
		if main._should_bail(): return
		return
	
	await main.show_message("SUMMON MINIONS!")
	if main._should_bail(): return
	
	var picks_remaining = min(2, 5 - bench.size())
	
	for i in range(picks_remaining):
		var remaining_basics: Array = []
		for card in deck:
			if main.is_basic_pokemon(card):
				remaining_basics.append(card)
		if remaining_basics.size() == 0:
			break
		
		var pick: card_object = null
		
		if not is_opponent:
			pick = await main.card_ops.prompt_select_card(remaining_basics, "CHOOSE BASIC " + str(i + 1) + "/" + str(picks_remaining), "", "SELECT", false, true)
			if main._should_bail(): return
		else:
			pick = main.cpu_ai.cpu_search_deck_for_best_pokemon(remaining_basics)
			if pick == null:
				pick = remaining_basics[0]
		
		if pick != null:
			deck.erase(pick)
			pick.current_location = "bench"
			pick.placed_on_field_this_turn = true
			bench.append(pick)
		
		if bench.size() >= main.get_max_bench_size():
			break
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SUMMONED POKÉMON TO BENCH!")
	if main._should_bail(): return
	print("POWER: Summon Minions")

# --- REEL IN: When Dark Slowbro played from hand, retrieve up to 3 Pokemon/Evolution from discard ---
func trigger_reel_in(slowbro: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	var valid: Array = []
	for card in discard:
		var supertype = card.metadata.get("supertype", "")
		var subtypes = card.metadata.get("subtypes", [])
		if supertype == "Pokémon":
			valid.append(card)
	
	if valid.size() == 0:
		await main.show_message("NO POKÉMON IN DISCARD!")
		if main._should_bail(): return
		return
	
	await main.show_message("REEL IN!")
	if main._should_bail(): return
	
	var max_picks = min(3, valid.size())
	var chosen: Array = []
	
	if not is_opponent:
		for i in range(max_picks):
			var remaining: Array = []
			for c in valid:
				if c not in chosen:
					remaining.append(c)
			if remaining.size() == 0:
				break
			
			var pick = await main.card_ops.prompt_select_card(remaining, "CHOOSE CARD " + str(i + 1) + "/" + str(max_picks), "", "SELECT", true)
			if main._should_bail(): return
			
			if pick != null:
				chosen.append(pick)
			else:
				break
	else:
		# CPU picks evolution cards first
		valid.sort_custom(func(a, b):
			var a_is_evo = "Stage" in str(a.metadata.get("subtypes", []))
			var b_is_evo = "Stage" in str(b.metadata.get("subtypes", []))
			return a_is_evo and not b_is_evo
		)
		for i in range(max_picks):
			chosen.append(valid[i])
	
	for card in chosen:
		discard.erase(card)
		card.current_location = "hand"
		hand.append(card)
	
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("RETRIEVED " + str(chosen.size()) + " CARD(S) FROM DISCARD!")
	if main._should_bail(): return
	print("POWER: Reel In - retrieved ", chosen.size(), " cards")

# --- EVOLUTIONARY LIGHT (Dark Dragonair): Search deck for Evolution, put in hand ---
func power_evolutionary_light(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	var deck = main.player_deck
	var evolutions: Array = []
	for card in deck:
		var subtypes = card.metadata.get("subtypes", [])
		if card.metadata.get("supertype", "") == "Pokémon" and ("Stage 1" in subtypes or "Stage 2" in subtypes):
			evolutions.append(card)
	
	if evolutions.size() == 0:
		await main.show_message("NO EVOLUTION CARDS IN DECK!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	var selected = await main.card_ops.prompt_select_card(evolutions, "CHOOSE AN EVOLUTION CARD", "", "SELECT", false, true)
	if main._should_bail(): return
	
	if selected == null:
		pokemon.power_used_this_turn = false
		return
	
	deck.erase(selected)
	selected.current_location = "hand"
	main.player_hand.append(selected)
	deck.shuffle()
	
	main.refresh_hand_display(false)
	main.update_deck_icon(false)
	await main.show_message("ADDED " + selected.metadata.get("name", "").to_upper() + " TO HAND!")
	if main._should_bail(): return
	print("POWER: Evolutionary Light - found ", selected.metadata.get("name", ""))

# --- POLLEN STENCH (Dark Gloom): Flip, heads=defender confused, tails=self confused ---
func power_pollen_stench(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	# Player-activated Power — player flips.
	var coin = await main.flip_coin(false, false)

	if coin:
		var defender = main.opponent_active_pokemon
		if defender != null:
			main.card_ops.apply_status(defender, "Confused", true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			main.card_ops.apply_status(active, "Confused", false)
			await main.show_message("TAILS! " + active.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
			if main._should_bail(): return
	print("POWER: Pollen Stench")

# --- MATTER EXCHANGE (Dark Kadabra): Discard 1 from hand, draw 1 ---
func power_matter_exchange(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if main.player_hand.size() == 0:
		await main.show_message("NO CARDS IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	
	if main.player_deck.size() == 0:
		await main.show_message("NO CARDS IN DECK TO DRAW!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player selects card to discard
	var selected = await main.card_ops.prompt_select_card(main.player_hand, "CHOOSE A CARD TO DISCARD", "", "DISCARD", false)
	if main._should_bail(): return

	if selected == null:
		pokemon.power_used_this_turn = false
		return
	
	main.player_hand.erase(selected)
	selected.current_location = "discard"
	main.player_discard_pile.append(selected)
	main.update_discard_pile_display(false)
	
	await main.card_ops.draw_n(false, 1)
	if main._should_bail(): return
	await main.show_message("MATTER EXCHANGE: DISCARDED 1, DREW 1!")
	if main._should_bail(): return
	print("POWER: Matter Exchange")

# --- GATHER FIRE (Charmander): Move 1 Fire Energy from another Pokemon to self ---
func power_gather_fire(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Find other pokemon with Fire Energy
	var sources: Array = []
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	for p in all_pokemon:
		if p == pokemon:
			continue
		for e in p.attached_energies:
			var provided = main.get_energy_provided_by_card(e)
			if "Fire" in provided:
				sources.append(p)
				break
	
	if sources.size() == 0:
		await main.show_message("NO OTHER POKÉMON WITH FIRE ENERGY!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player chooses source
	var source = await main.card_ops.prompt_select_card(sources, "CHOOSE POKÉMON TO TAKE FIRE ENERGY FROM", "", "SELECT", false)
	if main._should_bail(): return

	if source == null:
		pokemon.power_used_this_turn = false
		return
	
	# Move 1 Fire Energy
	for e in source.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			source.attached_energies.erase(e)
			pokemon.attached_energies.append(e)
			break
	
	main.display_active_pokemon_energies(false)
	await main.show_message("GATHERED FIRE ENERGY FROM " + source.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("POWER: Gather Fire")

# --- LONG-DISTANCE HYPNOSIS (Drowzee): Flip, heads=defender asleep, tails=self asleep ---
func power_long_distance_hypnosis(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	# Player-activated Power — player flips.
	var coin = await main.flip_coin(false, false)

	if coin:
		var defender = main.opponent_active_pokemon
		if defender != null:
			main.card_ops.apply_status(defender, "Asleep", true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			main.card_ops.apply_status(active, "Asleep", false)
			await main.show_message("TAILS! " + active.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	print("POWER: Long-Distance Hypnosis")

# --- TRICKERY (Rattata): Switch 1 prize with top of deck ---
func power_trickery(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if main.player_deck.size() == 0:
		await main.show_message("NO CARDS IN DECK!")
		if main._should_bail(): return
		return
	
	if main.player_prize_cards.size() == 0:
		await main.show_message("NO PRIZE CARDS!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player chooses prize card
	var selected_prize = await main.card_ops.prompt_select_card(main.player_prize_cards, "CHOOSE A PRIZE CARD TO SWAP", "", "SWAP", false)
	if main._should_bail(): return

	if selected_prize == null:
		pokemon.power_used_this_turn = false
		return
	
	# Swap with top of deck
	var top_deck = main.player_deck[0]
	var prize_idx = main.player_prize_cards.find(selected_prize)
	
	main.player_prize_cards[prize_idx] = top_deck
	main.player_deck[0] = selected_prize
	
	main.display_prize_cards(false)
	main.update_deck_icon(false)
	await main.show_message("TRICKERY: SWAPPED PRIZE WITH TOP OF DECK!")
	if main._should_bail(): return
	print("POWER: Trickery")

# --- STICKY GOO (Dark Muk): Check for +2 retreat cost ---
func get_sticky_goo_cost(is_opponent: bool) -> int:
	# Sticky Goo: opponent pays 2 more to retreat if Dark Muk is their opponent's active
	# "As long as Dark Muk is your Active Pokémon"
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_active == null:
		return 0
	for ability in opp_active.metadata.get("abilities", []):
		if ability.get("name", "") == "Sticky Goo":
			if not is_power_blocked_by_status(opp_active) and not is_toxic_gas_active() and not main.goop_gas_active:
				return 2
	return 0

# --- FRENZY (Dark Primeape): +30 damage when confused ---
func check_frenzy_bonus(attacker: card_object) -> int:
	if attacker == null:
		return 0
	if attacker.special_condition != "Confused":
		return 0
	for ability in attacker.metadata.get("abilities", []):
		if ability.get("name", "") == "Frenzy":
			if not is_toxic_gas_active() and not main.goop_gas_active:
				return 30
	return 0

######################################################################################################################################################
######################################################## GYM1 (GYM HEROES) POWERS AND BODIES ########################################################
######################################################################################################################################################

# Returns true if `pokemon` carries the named ability AND the ability is currently usable.
# `works_through_status`: ability text contains "even while Asleep/Confused/Paralyzed".
# Always blocked by Toxic Gas / Goop Gas Attack.
func _power_active_on(pokemon: card_object, power_name: String, works_through_status: bool = false) -> bool:
	if pokemon == null or pokemon.current_hp <= 0:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	if pokemon.power_disabled_until_end_of_next_turn:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == power_name:
			has_it = true
			break
	if not has_it:
		return false
	if not works_through_status and is_power_blocked_by_status(pokemon):
		return false
	return true

# Helper: locate a Pokemon Power on a side by ability name. Returns the card_object or null.
func _find_pokemon_with_power_on_side(power_name: String, is_opponent: bool) -> card_object:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		for ab in active.metadata.get("abilities", []):
			if ab.get("name", "") == power_name:
				return active
	for bp in bench:
		for ab in bp.metadata.get("abilities", []):
			if ab.get("name", "") == power_name:
				return bp
	return null

# --- gym1-2 Brock's Rhydon — Bench Guard ---
# When a benched Pokemon on Rhydon's side takes damage, owner may redirect 10 of that damage to Rhydon.
# Called BEFORE damage is applied to a benched pokemon. Returns the damage that should actually land
# on the original target (caller applies the redirected 10 to Rhydon separately).
func check_bench_guard(damaged_pokemon: card_object, damage: int, owner_is_opp: bool) -> int:
	if damaged_pokemon == null or damage <= 0:
		return damage
	# Find a benched Brock's Rhydon on the SAME side as the damaged pokemon
	var bench = main.opponent_bench if owner_is_opp else main.player_bench
	if damaged_pokemon not in bench:
		return damage
	var rhydon: card_object = null
	for bp in bench:
		if bp == damaged_pokemon:
			continue
		if _power_active_on(bp, "Bench Guard", false):
			rhydon = bp
			break
	if rhydon == null:
		return damage
	# Player opt-in vs CPU automatic
	var redirect: bool = false
	if owner_is_opp:
		# CPU: redirect if Rhydon has enough HP buffer (more than 20) and the bench pokemon is more valuable
		if rhydon.current_hp > 20:
			redirect = true
	else:
		redirect = await main.trainer_effects.gym1_prompt_yes_no(rhydon, "BENCH GUARD", \
			rhydon.metadata.get("name", "") + " may take 10 damage instead?", "REDIRECT", "DECLINE")
		if main._should_bail(): return damage
	if not redirect:
		return damage
	# Redirect 10 to Rhydon (capped at the actual damage)
	var redirected: int = min(10, damage)
	rhydon.current_hp = max(0, rhydon.current_hp - redirected)
	main.display_hp_circles_above_align(rhydon, owner_is_opp)
	await main.show_message("BENCH GUARD: " + rhydon.metadata.get("name", "").to_upper() + " TOOK " + str(redirected) + " DAMAGE INSTEAD!")
	if main._should_bail(): return damage - redirected
	return damage - redirected

# --- gym1-5 Erika's Vileplume — Pollen Defense ---
# When an attack damages Vileplume (your Active), flip; heads -> opponent's Active becomes Confused.
# Works even while Vileplume is Asleep/Confused/Paralyzed.
func check_pollen_defense(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return
	if not _power_active_on(damaged_pokemon, "Pollen Defense", true):
		return
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if not coin:
		await main.show_message("POLLEN DEFENSE: TAILS!")
		return
	if attacker.special_condition == "Confused":
		await main.show_message("POLLEN DEFENSE: " + attacker.metadata.get("name", "").to_upper() + " IS ALREADY CONFUSED!")
		return
	if attacker.is_bench_token:
		return
	# Snorlax Thick Skinned check
	for ab in attacker.metadata.get("abilities", []):
		if ab.get("name", "") == "Thick Skinned" and not is_toxic_gas_active():
			await main.show_message("THICK SKINNED PREVENTS CONFUSION!")
			return
	main.card_ops.apply_status(attacker, "Confused", not is_damaged_opp)
	await main.show_message("POLLEN DEFENSE: " + attacker.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
	if main._should_bail(): return

# --- gym1-8 Lt. Surge's Magneton — Energy Charge ---
# As often as you like: take 1 Lightning Energy from one of your Pokemon, attach to active Magneton.
func power_energy_charge(magneton: card_object) -> void:
	if magneton == null:
		return
	var is_opp: bool = (magneton == main.opponent_active_pokemon)
	# Build list of sources (any of your other pokemon that has a Lightning energy)
	var sources: Array = []
	var bench = main.opponent_bench if is_opp else main.player_bench
	for bp in bench:
		if bp == magneton:
			continue
		for e in bp.attached_energies:
			if "Lightning" in main.get_energy_provided_by_card(e):
				sources.append(bp)
				break
	if sources.size() == 0:
		if not is_opp:
			await main.show_message("NO LIGHTNING ENERGY ON YOUR OTHER POKEMON!")
		return
	var source: card_object = null
	if is_opp:
		# CPU: pick any source with spare lightning
		source = sources[0]
	else:
		if sources.size() == 1:
			source = sources[0]
		else:
			source = await main.card_ops.prompt_select_card(sources, "ENERGY CHARGE", "Choose a Pokemon to take Lightning Energy from", "SELECT", true)
			if main._should_bail(): return
		if source == null:
			return
	# Move one Lightning energy
	var moved: card_object = null
	for e in source.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			moved = e
			break
	if moved == null:
		return
	source.attached_energies.erase(moved)
	magneton.attached_energies.append(moved)
	main.display_active_pokemon_energies(is_opp)
	main.display_pokemon(is_opp)
	await main.show_message("ENERGY CHARGE: MOVED LIGHTNING ENERGY TO " + magneton.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	# Energy Charge is multi-use per turn — DO NOT set power_used_this_turn

# --- gym1-10 Misty's Tentacruel — Flee ---
# After damage hits Tentacruel as Active, owner may switch with a bench pokemon to prevent other effects.
# Returns true if Tentacruel fled (caller should skip remaining attack effects on it).
func check_flee(damaged_pokemon: card_object, is_damaged_opp: bool) -> bool:
	if damaged_pokemon == null or damaged_pokemon.current_hp <= 0:
		return false
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return false
	if not _power_active_on(damaged_pokemon, "Flee", false):
		return false
	var bench = main.opponent_bench if is_damaged_opp else main.player_bench
	if bench.size() == 0:
		return false
	var do_flee: bool = false
	if is_damaged_opp:
		# CPU: flee if HP is critical or there's a healthier replacement
		var hp_pct = float(damaged_pokemon.current_hp) / max(1, int(damaged_pokemon.metadata.get("hp", "0")))
		if hp_pct <= 0.4:
			do_flee = true
	else:
		do_flee = await main.trainer_effects.gym1_prompt_yes_no(damaged_pokemon, "FLEE", \
			"Switch " + damaged_pokemon.metadata.get("name", "") + " with a bench Pokemon?", "FLEE", "STAY")
		if main._should_bail(): return false
	if not do_flee:
		return false
	# Choose replacement
	var replacement: card_object = null
	if is_damaged_opp:
		replacement = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, main.cpu_ai.get_cpu_evaluation())
		if replacement == null:
			replacement = bench[0]
	else:
		if bench.size() == 1:
			replacement = bench[0]
		else:
			replacement = await main.card_ops.prompt_select_card(bench, "FLEE", "Choose a bench Pokemon to switch to", "SELECT", false)
			if main._should_bail(): return false
		if replacement == null:
			return false
	# Perform swap (no retreat cost)
	if is_damaged_opp:
		main.opponent_bench.erase(replacement)
		main.opponent_bench.append(damaged_pokemon)
		damaged_pokemon.current_location = "bench"
		replacement.current_location = "active"
		main.opponent_active_pokemon = replacement
	else:
		main.player_bench.erase(replacement)
		main.player_bench.append(damaged_pokemon)
		damaged_pokemon.current_location = "bench"
		replacement.current_location = "active"
		main.player_active_pokemon = replacement
	main.clear_all_statuses(damaged_pokemon, is_damaged_opp)
	main.display_pokemon(is_damaged_opp)
	main.display_active_pokemon_energies(is_damaged_opp)
	await main.show_message("FLEE: " + damaged_pokemon.metadata.get("name", "").to_upper() + " SWITCHED OUT!")
	if main._should_bail(): return true
	return true

# --- gym1-12 Rocket's Moltres — Rebirth ---
# When Moltres is KO'd, owner may return it to hand instead of discarding.
# Blocked if Asleep/Confused/Paralyzed when KO'd.
# Returns true if rebirth was used (caller should skip the discard step).
func check_rebirth(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null:
		return false
	# Look for the Rebirth ability
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Rebirth":
			has_it = true
			break
	if not has_it:
		return false
	# Blocked by status / toxic gas
	if pokemon.special_condition in ["Paralyzed", "Asleep", "Confused"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	var do_rebirth: bool = false
	if is_opp:
		do_rebirth = true  # CPU always rebirths
	else:
		do_rebirth = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "REBIRTH", \
			"Return " + pokemon.metadata.get("name", "") + " to your hand instead of discarding?", "REBIRTH", "DISCARD")
		if main._should_bail(): return false
	if not do_rebirth:
		return false
	# Return Moltres to hand (attached cards/energies/pre-evos all go to discard)
	var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
	for e in pokemon.attached_energies:
		e.current_location = "discard"
		discard_pile.append(e)
	pokemon.attached_energies.clear()
	for c in pokemon.attached_cards:
		c.current_location = "discard"
		discard_pile.append(c)
	pokemon.attached_cards.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "discard"
		discard_pile.append(pre)
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.special_condition = ""
	pokemon.is_poisoned = false
	pokemon.is_burned = false
	pokemon.pluspower_count = 0
	pokemon.defender_turns_remaining = -1
	pokemon.current_location = "hand"
	var hand = main.opponent_hand if is_opp else main.player_hand
	hand.append(pokemon)
	main.refresh_hand_display(is_opp)
	main.update_discard_pile_display(is_opp)
	await main.show_message("REBIRTH: " + pokemon.metadata.get("name", "").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return true
	return true

# --- gym1-26 Erika's Victreebel — Fragrance Trap ---
# Once/turn: flip; heads, switch one of opponent's bench with their Active.
func power_fragrance_trap(victreebel: card_object) -> void:
	if victreebel == null or victreebel.power_used_this_turn:
		return
	var is_opp: bool = (victreebel == main.opponent_active_pokemon or victreebel in main.opponent_bench)
	var opp_bench = main.player_bench if is_opp else main.opponent_bench
	if opp_bench.size() == 0:
		if not is_opp:
			await main.show_message("OPPONENT HAS NO BENCHED POKEMON!")
		return
	victreebel.power_used_this_turn = true
	# Owner flips
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FRAGRANCE TRAP: TAILS!")
		return
	# Choose opponent's bench pokemon to bring up
	var target: card_object = null
	if is_opp:
		# CPU picks player's bench pokemon that helps the CPU most (e.g. lowest HP%, weakest, no energy)
		var best_score = 999999.0
		for bp in main.player_bench:
			var max_hp = int(bp.metadata.get("hp", "0"))
			var hp_pct = float(bp.current_hp) / max(1, max_hp)
			var e_count = bp.attached_energies.size()
			var s = hp_pct * 100.0 + e_count * 30.0
			if s < best_score:
				best_score = s
				target = bp
	else:
		target = await main.card_ops.prompt_select_card(opp_bench, "FRAGRANCE TRAP", "Choose an opponent bench Pokemon to bring up", "SELECT", false)
		if main._should_bail(): return
	if target == null:
		return
	# Swap target with opponent's Active
	var opp_active_var = "player_active_pokemon" if is_opp else "opponent_active_pokemon"
	var old_active = main.player_active_pokemon if is_opp else main.opponent_active_pokemon
	if is_opp:
		main.player_bench.erase(target)
		main.player_bench.append(old_active)
		main.player_active_pokemon = target
	else:
		main.opponent_bench.erase(target)
		main.opponent_bench.append(old_active)
		main.opponent_active_pokemon = target
	if old_active != null:
		old_active.current_location = "bench"
	target.current_location = "active"
	main.clear_all_statuses(old_active, not is_opp)
	main.display_pokemon(not is_opp)
	main.display_active_pokemon_energies(not is_opp)
	await main.show_message("FRAGRANCE TRAP: " + target.metadata.get("name", "").to_upper() + " WAS DRAGGED OUT!")
	if main._should_bail(): return

# --- gym1-29 Misty's Cloyster — Shell Armor ---
# Passive: -10 damage (after W/R). Blocked by status / Toxic Gas.
func apply_shell_armor(defender: card_object, damage: int) -> int:
	if defender == null or damage <= 0:
		return damage
	if not _power_active_on(defender, "Shell Armor", false):
		return damage
	var reduced: int = max(0, damage - 10)
	print("SHELL ARMOR: ", damage, " -> ", reduced)
	return reduced

# --- gym1-33 Rocket's Snorlax — Restless Sleep ---
# If opp's attack damages Snorlax while Snorlax is Asleep, deal 20 to attacker.
# Works through ALL status (the card text only excludes the case "if it's already Asleep" — flipped condition).
# Re-read: "if your opponent's attack does damage to Rocket's Snorlax and Rocket's Snorlax is already Asleep (even if it's Knocked Out), this power does 20 damage to the attacking Pokémon."
# So it triggers WHEN Snorlax is Asleep at time of damage.
func check_restless_sleep(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if damaged_pokemon.special_condition != "Asleep":
		return
	# Card-side check
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Restless Sleep":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	attacker.current_hp = max(0, attacker.current_hp - 20)
	var attacker_is_opp: bool = not is_damaged_opp
	main.display_hp_circles_above_align(attacker, attacker_is_opp)
	var label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
	main.show_floating_label("-20HP", label_pos, true)
	await main.show_message("RESTLESS SLEEP: " + attacker.metadata.get("name", "").to_upper() + " TOOK 20 DAMAGE!")
	if main._should_bail(): return

# --- gym1-42 Erika's Dratini — Strange Barrier ---
# When a Basic Pokemon attack (any side, including own) does ≥20 to Dratini (after W/R), reduce to 10.
func apply_strange_barrier(defender: card_object, attacker: card_object, damage: int) -> int:
	if defender == null or attacker == null or damage < 20:
		return damage
	if not _power_active_on(defender, "Strange Barrier", false):
		return damage
	# Attacker must be a Basic Pokemon (Stage 1/2 attackers are NOT capped)
	var subtypes = attacker.metadata.get("subtypes", [])
	if "Basic" not in subtypes:
		return damage
	print("STRANGE BARRIER: ", damage, " -> 10")
	return 10

# --- gym1-47 Erika's Oddish — Photosynthesis ---
# All attached energy provides Grass. Works through status.
func is_photosynthesis_active(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Photosynthesis":
			return true
	return false

# --- gym1-65 Blaine's Vulpix — Natural Healing ---
# Once/turn: remove 1 damage counter (10 HP).
func power_natural_healing(vulpix: card_object) -> void:
	if vulpix == null or vulpix.power_used_this_turn:
		return
	var max_hp = int(vulpix.metadata.get("hp", "0"))
	if vulpix.current_hp >= max_hp:
		if not (vulpix == main.opponent_active_pokemon or vulpix in main.opponent_bench):
			await main.show_message(vulpix.metadata.get("name", "").to_upper() + " HAS NO DAMAGE TO HEAL!")
		return
	var is_opp: bool = (vulpix == main.opponent_active_pokemon or vulpix in main.opponent_bench)
	# MATCH EFFECTS: no_healing / healing_multiplier gate (don't consume the power if blocked)
	var rule_heal = main.match_effects.modify_heal_amount(10, is_opp)
	if rule_heal <= 0:
		if not is_opp:
			await main.show_message("SPECIAL MATCH RULE: HEALING IS BLOCKED!")
		return
	vulpix.power_used_this_turn = true
	var actual_heal = min(rule_heal, max_hp - vulpix.current_hp)
	vulpix.current_hp = min(max_hp, vulpix.current_hp + rule_heal)
	main.display_hp_circles_above_align(vulpix, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("NATURAL HEALING: " + vulpix.metadata.get("name", "").to_upper() + " HEALED " + str(actual_heal) + " HP!")
	if main._should_bail(): return

######################################################################################################################################################
######################################################## GYM2 (GYM CHALLENGE) POWERS AND BODIES #####################################################
######################################################################################################################################################

# --- gym2-3 Brock's Ninetales — Shapeshift ---
# Active: attach Evolution card from hand; Ninetales uses that card's attacks instead of its own.
# Card's ability/HP/types stay as Ninetales. Discarding the form (also a free action) is a separate menu entry.
func power_shapeshift(ninetales: card_object) -> void:
	if ninetales == null:
		return
	# If form already attached, decline new attach (card says "attach an Evolution card" — implicit one form at a time per current setup)
	var is_opp: bool = (ninetales == main.opponent_active_pokemon or ninetales in main.opponent_bench)
	var hand = main.opponent_hand if is_opp else main.player_hand
	var evolutions: Array = []
	for c in hand:
		if c.metadata.get("supertype", "").to_lower() != "pokémon" and c.metadata.get("supertype", "").to_lower() != "pokemon":
			continue
		var sts = c.metadata.get("subtypes", [])
		if "Stage 1" in sts or "Stage 2" in sts:
			evolutions.append(c)
	if evolutions.size() == 0:
		if not is_opp:
			await main.show_message("NO EVOLUTION CARDS IN HAND!")
		return
	var chosen: card_object = null
	if is_opp:
		# CPU picks the evolution with strongest attack (highest base damage)
		var best_dmg = -1
		for ev in evolutions:
			for atk in ev.metadata.get("attacks", []):
				var d_raw = atk.get("damage", "0")
				var d = int(str(d_raw).replace("+", "").replace("×", "").replace("x", "")) if str(d_raw) != "" else 0
				if d > best_dmg:
					best_dmg = d
					chosen = ev
	else:
		if evolutions.size() == 1:
			chosen = evolutions[0]
		else:
			chosen = await main.card_ops.prompt_select_card(evolutions, "SHAPESHIFT", "Choose an Evolution card to attach as a form", "SELECT", true)
			if main._should_bail(): return
		if chosen == null:
			return
	# Discard previous form if any
	if ninetales.shapeshift_form_card != null:
		var prev_form = ninetales.shapeshift_form_card
		var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
		prev_form.current_location = "discard"
		discard_pile.append(prev_form)
		main.update_discard_pile_display(is_opp)
	# Attach new form
	hand.erase(chosen)
	chosen.current_location = "attached"
	ninetales.shapeshift_form_card = chosen
	ninetales.shapeshift_form_uid = chosen.uid
	ninetales.shapeshift_form_metadata = chosen.metadata.duplicate(true)
	# Mirror the form's attacks onto Ninetales (preserve original attacks for revert)
	if not ninetales.metadata.has("_original_attacks"):
		ninetales.metadata["_original_attacks"] = ninetales.metadata.get("attacks", [])
	ninetales.metadata["attacks"] = chosen.metadata.get("attacks", [])
	ninetales.power_used_this_turn = true
	main.refresh_hand_display(is_opp)
	await main.show_message("SHAPESHIFT: " + ninetales.metadata.get("name", "").to_upper() + " IS NOW " + chosen.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# Active: discard the attached Shapeshift form (counts as a free action per card text)
func power_shapeshift_discard(ninetales: card_object) -> void:
	if ninetales == null or ninetales.shapeshift_form_card == null:
		return
	var is_opp: bool = (ninetales == main.opponent_active_pokemon or ninetales in main.opponent_bench)
	var prev_form = ninetales.shapeshift_form_card
	var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
	prev_form.current_location = "discard"
	discard_pile.append(prev_form)
	# Restore original attacks
	if ninetales.metadata.has("_original_attacks"):
		ninetales.metadata["attacks"] = ninetales.metadata.get("_original_attacks", [])
		ninetales.metadata.erase("_original_attacks")
	ninetales.shapeshift_form_card = null
	ninetales.shapeshift_form_uid = ""
	ninetales.shapeshift_form_metadata = {}
	main.update_discard_pile_display(is_opp)
	await main.show_message("SHAPESHIFT FORM DISCARDED!")
	if main._should_bail(): return

# If Ninetales gets Asleep/Confused/Paralyzed, all attached forms are discarded.
func shapeshift_check_status_discard(pokemon: card_object) -> void:
	if pokemon == null or pokemon.shapeshift_form_card == null:
		return
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		var is_opp: bool = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
		var prev_form = pokemon.shapeshift_form_card
		var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
		prev_form.current_location = "discard"
		discard_pile.append(prev_form)
		if pokemon.metadata.has("_original_attacks"):
			pokemon.metadata["attacks"] = pokemon.metadata.get("_original_attacks", [])
			pokemon.metadata.erase("_original_attacks")
		pokemon.shapeshift_form_card = null
		pokemon.shapeshift_form_uid = ""
		pokemon.shapeshift_form_metadata = {}
		main.update_discard_pile_display(is_opp)
		await main.show_message("SHAPESHIFT FORM DISCARDED DUE TO STATUS!")

# --- gym2-6 Giovanni's Machamp — Fortitude ---
# When Machamp would be KO'd by an opponent's attack, flip; heads, survive with 10 HP.
# Blocked if already Asleep/Confused/Paralyzed.
# Returns true if survived.
func check_fortitude(pokemon: card_object) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Fortitude":
			has_it = true
			break
	if not has_it:
		return false
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Owner flips
	var is_opp: bool = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return false
	if not coin:
		await main.show_message("FORTITUDE: TAILS!")
		return false
	pokemon.current_hp = 10
	main.display_hp_circles_above_align(pokemon, is_opp)
	await main.show_message("FORTITUDE: " + pokemon.metadata.get("name", "").to_upper() + " SURVIVED WITH 10 HP!")
	if main._should_bail(): return true
	return true

# --- gym2-8 Giovanni's Persian — Call the Boss ---
# When Persian comes into play from hand, owner may search deck for a Giovanni trainer card.
func trigger_call_the_boss(persian: card_object, is_opp: bool) -> void:
	if persian == null:
		return
	var has_it: bool = false
	for ab in persian.metadata.get("abilities", []):
		if ab.get("name", "") == "Call the Boss":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	var deck = main.opponent_deck if is_opp else main.player_deck
	var hand = main.opponent_hand if is_opp else main.player_hand
	var giovanni_cards: Array = []
	for c in deck:
		if c.metadata.get("name", "") == "Giovanni":
			giovanni_cards.append(c)
	if giovanni_cards.size() == 0:
		return
	var do_search: bool = false
	if is_opp:
		do_search = true
	else:
		do_search = await main.trainer_effects.gym1_prompt_yes_no(persian, "CALL THE BOSS", \
			"Search deck for a Giovanni trainer card?", "SEARCH", "DECLINE")
		if main._should_bail(): return
	if not do_search:
		return
	# CPU + Player flow: pick the first Giovanni
	var chosen: card_object = giovanni_cards[0]
	if not is_opp and giovanni_cards.size() > 1:
		chosen = await main.card_ops.prompt_select_card(giovanni_cards, "CALL THE BOSS", "Choose a Giovanni card to take", "SELECT", true, true)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("CALL THE BOSS: TOOK GIOVANNI FROM DECK!")
	if main._should_bail(): return

# --- gym2-13 Misty's Gyarados — Rebellion ---
# When Gyarados attacks, flip 2 coins. Both tails: attack does nothing AND shuffle Gyarados+attached into deck.
# Works through Confusion.
# Returns true if attack was negated.
func check_rebellion(attacker: card_object, is_opp: bool) -> bool:
	if attacker == null:
		return false
	var has_it: bool = false
	for ab in attacker.metadata.get("abilities", []):
		if ab.get("name", "") == "Rebellion":
			has_it = true
			break
	if not has_it:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Owner flips
	var attacker_is_player: bool = not is_opp
	var c1 = await main.flip_coin(not attacker_is_player, attacker_is_player)
	if main._should_bail(): return false
	var c2 = await main.flip_coin(not attacker_is_player, attacker_is_player)
	if main._should_bail(): return false
	if c1 or c2:
		await main.show_message("REBELLION: AT LEAST ONE HEADS — ATTACK PROCEEDS!")
		return false
	await main.show_message("REBELLION: TWO TAILS — ATTACK FIZZLES!")
	if main._should_bail(): return true
	# Shuffle Gyarados + attached into deck
	var deck = main.opponent_deck if is_opp else main.player_deck
	for e in attacker.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	attacker.attached_energies.clear()
	for c in attacker.attached_cards:
		c.current_location = "deck"
		deck.append(c)
	attacker.attached_cards.clear()
	for pre in attacker.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	attacker.attached_pre_evolutions.clear()
	attacker.current_hp = attacker.get_max_hp()
	attacker.special_condition = ""
	attacker.is_poisoned = false
	attacker.is_burned = false
	attacker.pluspower_count = 0
	attacker.defender_turns_remaining = -1
	attacker.current_location = "deck"
	if attacker == main.opponent_active_pokemon:
		main.opponent_active_pokemon = null
	elif attacker == main.player_active_pokemon:
		main.player_active_pokemon = null
	elif attacker in main.opponent_bench:
		main.opponent_bench.erase(attacker)
	elif attacker in main.player_bench:
		main.player_bench.erase(attacker)
	deck.append(attacker)
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("MISTY'S GYARADOS WAS SHUFFLED INTO DECK!")
	if main._should_bail(): return true
	# If Gyarados was the active, post-KO logic triggers (must pick new active)
	if (is_opp and main.opponent_active_pokemon == null) or (not is_opp and main.player_active_pokemon == null):
		await main.handle_post_knockout(is_opp)
	return true

# --- gym2-16 Sabrina's Alakazam — Psylink ---
# Alakazam always has a copy of every attack of your Psychic Pokemon in play, with their original cost.
# Returns the merged attack list (Alakazam's own + every other Psychic-typed pokemon you control).
func get_psylink_attacks(alakazam: card_object, is_alakazam_opp: bool) -> Array:
	var attacks: Array = alakazam.metadata.get("attacks", []).duplicate()
	if not _power_active_on(alakazam, "Psylink", false):
		return attacks
	var own_field: Array = []
	var own_active = main.opponent_active_pokemon if is_alakazam_opp else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_alakazam_opp else main.player_bench
	if own_active != null:
		own_field.append(own_active)
	own_field.append_array(own_bench)
	for p in own_field:
		if p == alakazam:
			continue
		if "Psychic" not in p.metadata.get("types", []):
			continue
		for atk in p.metadata.get("attacks", []):
			attacks.append(atk)
	return attacks

# --- gym2-21 Blaine's Ninetales — Healing Fire ---
# When a Fire energy is attached to Ninetales from hand, remove 1 damage counter.
# Blocked if Asleep/Confused/Paralyzed.
func check_healing_fire(pokemon: card_object, energy: card_object, is_opp: bool) -> void:
	if pokemon == null or energy == null:
		return
	if not _power_active_on(pokemon, "Healing Fire", false):
		return
	# Energy must provide Fire
	var provided = main.get_energy_provided_by_card(energy)
	if "Fire" not in provided:
		return
	var max_hp = int(pokemon.metadata.get("hp", "0"))
	if pokemon.current_hp >= max_hp:
		return
	# MATCH EFFECTS: no_healing / healing_multiplier gate
	var rule_heal = main.match_effects.modify_heal_amount(10, is_opp)
	if rule_heal <= 0:
		return
	var actual_heal = min(rule_heal, max_hp - pokemon.current_hp)
	pokemon.current_hp = min(max_hp, pokemon.current_hp + rule_heal)
	main.display_hp_circles_above_align(pokemon, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("HEALING FIRE: " + pokemon.metadata.get("name", "").to_upper() + " HEALED " + str(actual_heal) + " HP!")
	if main._should_bail(): return

# --- gym2-26 Koga's Muk — Energy Drain ---
# When an opp attack damages Muk, flip; heads, discard 1 energy from the attacker.
# Works even if Muk KO'd. Blocked if Muk was Asleep/Confused/Paralyzed when attacked.
func check_energy_drain(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Energy Drain":
			has_it = true
			break
	if not has_it:
		return
	if damaged_pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	if attacker.attached_energies.size() == 0:
		return
	# Owner of Muk flips
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY DRAIN: TAILS!")
		return
	# Owner of Muk chooses which energy to discard
	var chosen_energy: card_object = null
	if defender_is_player:
		chosen_energy = await main.card_ops.prompt_select_card(attacker.attached_energies, "ENERGY DRAIN", "Choose 1 energy on the attacker to discard", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks first energy
		chosen_energy = attacker.attached_energies[0]
	if chosen_energy == null:
		return
	attacker.attached_energies.erase(chosen_energy)
	chosen_energy.current_location = "discard"
	var attacker_is_opp: bool = not is_damaged_opp
	var discard_pile = main.opponent_discard_pile if attacker_is_opp else main.player_discard_pile
	discard_pile.append(chosen_energy)
	main.display_active_pokemon_energies(attacker_is_opp)
	main.update_discard_pile_display(attacker_is_opp)
	await main.show_message("ENERGY DRAIN: DISCARDED " + chosen_energy.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# --- gym2-35 Brock's Primeape — Scram ---
# If Primeape ever has exactly 10 HP left, shuffle it (and attached cards) into deck.
# Blocked if Asleep/Confused/Paralyzed.
# Returns true if scrammed.
func check_scram(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null:
		return false
	if pokemon.current_hp != 10:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Scram":
			has_it = true
			break
	if not has_it:
		return false
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Shuffle into deck
	var deck = main.opponent_deck if is_opp else main.player_deck
	for e in pokemon.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	pokemon.attached_energies.clear()
	for c in pokemon.attached_cards:
		c.current_location = "deck"
		deck.append(c)
	pokemon.attached_cards.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.current_location = "deck"
	if pokemon == main.opponent_active_pokemon:
		main.opponent_active_pokemon = null
	elif pokemon == main.player_active_pokemon:
		main.player_active_pokemon = null
	elif pokemon in main.opponent_bench:
		main.opponent_bench.erase(pokemon)
	elif pokemon in main.player_bench:
		main.player_bench.erase(pokemon)
	deck.append(pokemon)
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("SCRAM: " + pokemon.metadata.get("name", "").to_upper() + " WAS SHUFFLED INTO DECK!")
	if main._should_bail(): return true
	return true

# --- gym2-38 Erika's Bellsprout — Soak Up ---
# Once/turn: move up to 2 Grass energy from your other pokemon to Bellsprout.
func power_soak_up(bellsprout: card_object) -> void:
	if bellsprout == null or bellsprout.power_used_this_turn:
		return
	var is_opp: bool = (bellsprout == main.opponent_active_pokemon or bellsprout in main.opponent_bench)
	# Build source pokemon list (any of your other pokemon with Grass energy)
	var moved_count := 0
	for _i in range(2):
		var sources: Array = []
		var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
		var bench = main.opponent_bench if is_opp else main.player_bench
		var all_p: Array = []
		if active != null:
			all_p.append(active)
		all_p.append_array(bench)
		for p in all_p:
			if p == bellsprout:
				continue
			for e in p.attached_energies:
				if "Grass" in main.get_energy_provided_by_card(e):
					sources.append(p)
					break
		if sources.size() == 0:
			break
		var source: card_object = null
		if is_opp:
			source = sources[0]
		else:
			if sources.size() == 1:
				source = sources[0]
			else:
				source = await main.card_ops.prompt_select_card(sources, "SOAK UP (" + str(moved_count) + "/2)", "Choose a Pokemon to take Grass Energy from (or cancel to stop)", "SELECT", true)
				if main._should_bail(): return
			if source == null:
				break
		var moved: card_object = null
		for e in source.attached_energies:
			if "Grass" in main.get_energy_provided_by_card(e):
				moved = e
				break
		if moved == null:
			break
		source.attached_energies.erase(moved)
		bellsprout.attached_energies.append(moved)
		moved_count += 1
		main.display_active_pokemon_energies(is_opp)
		main.display_pokemon(is_opp)
	bellsprout.power_used_this_turn = true
	if moved_count > 0:
		await main.show_message("SOAK UP: MOVED " + str(moved_count) + " GRASS ENERGY!")
		if main._should_bail(): return
	elif not is_opp:
		await main.show_message("NO GRASS ENERGY TO MOVE!")

# --- gym2-41 Erika's Ivysaur — Relaxing Scent ---
# While Ivysaur is your Active Pokemon, all damage (after W/R) to any pokemon is halved (round up to nearest 10).
func is_relaxing_scent_active_on_side(is_opp: bool) -> bool:
	var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
	if active == null:
		return false
	return _power_active_on(active, "Relaxing Scent", false)

func apply_relaxing_scent(damage: int) -> int:
	if damage <= 0:
		return damage
	if not (is_relaxing_scent_active_on_side(true) or is_relaxing_scent_active_on_side(false)):
		return damage
	# Round UP to nearest 10
	var half = int(ceil(damage / 2.0 / 10.0)) * 10
	print("RELAXING SCENT: ", damage, " -> ", half)
	return half

# --- gym2-47 Koga's Kakuna — Emerge ---
# Once/turn: flip heads, search deck for "Koga's Beedrill" and evolve Kakuna into it (free, bypasses placed-this-turn).
func power_emerge(kakuna: card_object) -> void:
	if kakuna == null or kakuna.power_used_this_turn:
		return
	var is_opp: bool = (kakuna == main.opponent_active_pokemon or kakuna in main.opponent_bench)
	var deck = main.opponent_deck if is_opp else main.player_deck
	# Find Koga's Beedrill in deck
	var beedrills: Array = []
	for c in deck:
		if c.metadata.get("name", "") == "Koga's Beedrill" and c.metadata.get("evolvesFrom", "") == "Koga's Kakuna":
			beedrills.append(c)
	if beedrills.size() == 0:
		if not is_opp:
			await main.show_message("NO KOGA'S BEEDRILL IN DECK!")
		return
	kakuna.power_used_this_turn = true
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("EMERGE: TAILS!")
		return
	# Evolve: move Kakuna to attached_pre_evolutions of Beedrill, replace card in active/bench
	var beedrill: card_object = beedrills[0]
	deck.erase(beedrill)
	beedrill.current_hp = beedrill.get_max_hp()
	beedrill.current_location = "active" if kakuna == (main.opponent_active_pokemon if is_opp else main.player_active_pokemon) else "bench"
	# Carry damage forward
	var kakuna_max = int(kakuna.metadata.get("hp", "0"))
	var damage_taken = kakuna_max - kakuna.current_hp
	beedrill.current_hp = max(10, int(beedrill.metadata.get("hp", "0")) - damage_taken)
	# Carry attachments
	beedrill.attached_energies = kakuna.attached_energies.duplicate()
	beedrill.attached_cards = kakuna.attached_cards.duplicate()
	beedrill.attached_pre_evolutions = kakuna.attached_pre_evolutions.duplicate()
	# Demote Kakuna into the pre-evolution chain
	kakuna.current_location = "attached_preevo"
	beedrill.attached_pre_evolutions.append(kakuna)
	# Replace in board
	if kakuna == main.opponent_active_pokemon:
		main.opponent_active_pokemon = beedrill
	elif kakuna == main.player_active_pokemon:
		main.player_active_pokemon = beedrill
	elif kakuna in main.opponent_bench:
		var idx = main.opponent_bench.find(kakuna)
		main.opponent_bench[idx] = beedrill
	elif kakuna in main.player_bench:
		var idx = main.player_bench.find(kakuna)
		main.player_bench[idx] = beedrill
	# Mark evolution sickness off (Koga's Beedrill should still get attack)
	beedrill.placed_on_field_this_turn = false
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.display_active_pokemon_energies(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("EMERGE: KAKUNA EVOLVED INTO KOGA'S BEEDRILL!")
	if main._should_bail(): return

# --- gym2-52 Lt. Surge's Electrode — Shock Blast ---
# If Active Electrode gets damaged (even if KO'd), flip; tails -> 20 damage to BOTH actives.
# Works through ALL status.
func check_shock_blast(damaged_pokemon: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null:
		return
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Shock Blast":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if coin:
		await main.show_message("SHOCK BLAST: HEADS — NO EFFECT!")
		return
	# Tails: 20 to BOTH actives
	var both: Array = []
	if main.player_active_pokemon != null:
		both.append({"p": main.player_active_pokemon, "is_opp": false})
	if main.opponent_active_pokemon != null:
		both.append({"p": main.opponent_active_pokemon, "is_opp": true})
	for info in both:
		var p = info["p"]
		p.current_hp = max(0, p.current_hp - 20)
		main.display_hp_circles_above_align(p, info["is_opp"])
		var lbl_pos = Vector2(1030, 300) if info["is_opp"] else Vector2(530, 300)
		main.show_floating_label("-20HP", lbl_pos, true)
	await main.show_message("SHOCK BLAST: TAILS — 20 DAMAGE TO BOTH ACTIVES!")
	if main._should_bail(): return

# --- gym2-97 Sabrina's Gastly — Gaseous Form ---
# +10 HP per Psychic energy attached. Works through status.
# Returns the effective max HP for any pokemon (call from get_max_hp path).
func compute_gaseous_form_bonus_hp(pokemon: card_object) -> int:
	if pokemon == null:
		return 0
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Gaseous Form":
			has_it = true
			break
	if not has_it:
		return 0
	if is_toxic_gas_active() or main.goop_gas_active:
		return 0
	var psy := 0
	for e in pokemon.attached_energies:
		if "Psychic" in main.get_energy_provided_by_card(e):
			psy += 1
	return psy * 10

# Recomputes max_hp_override for any pokemon with Gaseous Form when its energies change.
# Called after every energy attach / discard.
func refresh_gaseous_form_hp() -> void:
	var all_p: Array = []
	if main.player_active_pokemon != null:
		all_p.append(main.player_active_pokemon)
	all_p.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_p.append(main.opponent_active_pokemon)
	all_p.append_array(main.opponent_bench)
	for p in all_p:
		var bonus = compute_gaseous_form_bonus_hp(p)
		if bonus > 0:
			var base = int(p.metadata.get("hp", "0"))
			var new_max = base + bonus
			# Preserve damage taken when raising/lowering the cap
			var damage_taken = max(0, p.max_hp_override - p.current_hp) if p.max_hp_override > 0 else (base - p.current_hp)
			p.max_hp_override = new_max
			p.current_hp = max(0, new_max - damage_taken)
		else:
			# Only clear override if it was set BY Gaseous Form (use ability presence check)
			var has_it: bool = false
			for ab in p.metadata.get("abilities", []):
				if ab.get("name", "") == "Gaseous Form":
					has_it = true
					break
			if has_it and p.max_hp_override > 0:
				var base2 = int(p.metadata.get("hp", "0"))
				var damage_taken2 = max(0, p.max_hp_override - p.current_hp)
				p.max_hp_override = 0
				p.current_hp = max(0, base2 - damage_taken2)

######################################################################################################################################################
######################################################## GYM1 + GYM2 CPU POWER ACTIVATIONS ###########################################################
######################################################################################################################################################

# Called from cpu_phase_activate_powers() to activate gym1/gym2 active powers in CPU's turn.
func cpu_phase_gym_powers() -> void:
	# --- Energy Charge (gym1-8 Lt. Surge's Magneton) ---
	var magneton = _find_pokemon_with_power_on_side("Energy Charge", true)
	if magneton != null and magneton == main.opponent_active_pokemon and _power_active_on(magneton, "Energy Charge", false):
		var keep_going: bool = true
		while keep_going:
			keep_going = false
			# Find a bench source with Lightning energy
			var src: card_object = null
			for bp in main.opponent_bench:
				for e in bp.attached_energies:
					if "Lightning" in main.get_energy_provided_by_card(e):
						# Only steal if the source has spare energy
						if bp.attached_energies.size() > 1 or _cpu_unmet_energy(bp) > 0:
							src = bp
							break
				if src != null:
					break
			if src == null:
				break
			# Only consolidate if Magneton actually needs Lightning
			if _cpu_unmet_energy(magneton) == 0:
				break
			await power_energy_charge(magneton)
			if main._should_bail(): return
			keep_going = true

	# --- Fragrance Trap (gym1-26 Erika's Victreebel) ---
	var victreebel = _find_pokemon_with_power_on_side("Fragrance Trap", true)
	if victreebel != null and not victreebel.power_used_this_turn and _power_active_on(victreebel, "Fragrance Trap", false):
		# Only use if player has bench targets weaker than their active
		if main.player_bench.size() > 0 and main.player_active_pokemon != null:
			var pa_hp = float(main.player_active_pokemon.current_hp)
			var has_weaker: bool = false
			for bp in main.player_bench:
				if float(bp.current_hp) < pa_hp:
					has_weaker = true
					break
			if has_weaker:
				await power_fragrance_trap(victreebel)
				if main._should_bail(): return

	# --- Natural Healing (gym1-65 Blaine's Vulpix) ---
	var vulpix = _find_pokemon_with_power_on_side("Natural Healing", true)
	if vulpix != null and not vulpix.power_used_this_turn and _power_active_on(vulpix, "Natural Healing", false):
		if vulpix.current_hp < int(vulpix.metadata.get("hp", "0")):
			await power_natural_healing(vulpix)
			if main._should_bail(): return

	# --- Shapeshift (gym2-3 Brock's Ninetales) ---
	var ninetales = _find_pokemon_with_power_on_side("Shapeshift", true)
	if ninetales != null and not ninetales.power_used_this_turn and _power_active_on(ninetales, "Shapeshift", false):
		# Use if CPU has any evolution card in hand
		var has_evo: bool = false
		for c in main.opponent_hand:
			if c.metadata.get("supertype", "").to_lower() in ["pokémon", "pokemon"]:
				var sts = c.metadata.get("subtypes", [])
				if "Stage 1" in sts or "Stage 2" in sts:
					has_evo = true
					break
		if has_evo and ninetales.shapeshift_form_card == null:
			await power_shapeshift(ninetales)
			if main._should_bail(): return

	# --- Soak Up (gym2-38 Erika's Bellsprout) ---
	var bellsprout = _find_pokemon_with_power_on_side("Soak Up", true)
	if bellsprout != null and not bellsprout.power_used_this_turn and _power_active_on(bellsprout, "Soak Up", false):
		# Use if any other CPU pokemon has Grass energy and Bellsprout still needs energy
		if _cpu_unmet_energy(bellsprout) > 0:
			var has_grass: bool = false
			var all_p: Array = []
			if main.opponent_active_pokemon != null:
				all_p.append(main.opponent_active_pokemon)
			all_p.append_array(main.opponent_bench)
			for p in all_p:
				if p == bellsprout:
					continue
				for e in p.attached_energies:
					if "Grass" in main.get_energy_provided_by_card(e):
						has_grass = true
						break
				if has_grass:
					break
			if has_grass:
				await power_soak_up(bellsprout)
				if main._should_bail(): return

	# --- Emerge (gym2-47 Koga's Kakuna) ---
	var kakuna = _find_pokemon_with_power_on_side("Emerge", true)
	if kakuna != null and not kakuna.power_used_this_turn and _power_active_on(kakuna, "Emerge", false):
		# Use if Koga's Beedrill exists in deck
		var has_beedrill: bool = false
		for c in main.opponent_deck:
			if c.metadata.get("name", "") == "Koga's Beedrill" and c.metadata.get("evolvesFrom", "") == "Koga's Kakuna":
				has_beedrill = true
				break
		if has_beedrill:
			await power_emerge(kakuna)
			if main._should_bail(): return

# Helper: cumulative unmet energy across all of a pokemon's attacks (cheap CPU heuristic)
func _cpu_unmet_energy(p: card_object) -> int:
	var best := 9999
	for atk in p.metadata.get("attacks", []):
		var u = main.cpu_ai.get_unmet_energy_count(atk, p)
		if u < best:
			best = u
	return best if best < 9999 else 0

######################################################################################################################################################
############################################################## BASEP POWERS & BODIES ###############################################################
######################################################################################################################################################

# SPECIAL DELIVERY (basep-5 Dragonite): draw 1 card, then put 1 card from hand on top of deck
func power_special_delivery(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("SPECIAL DELIVERY IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SPECIAL DELIVERY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var is_opponent = pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench
	await main.show_message("SPECIAL DELIVERY: DRAWING A CARD...")
	if main._should_bail(): return
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if hand.size() == 0:
		return
	var chosen: card_object
	if is_opponent:
		# CPU: put the least-useful card back on top (lowest-priority card, e.g. excess energy)
		chosen = hand[hand.size() - 1]
	else:
		chosen = await main.card_ops.prompt_select_card(hand, "SPECIAL DELIVERY — PUT ON TOP OF DECK", "Choose a card to put on top of your deck", "PLACE", false)
		if main._should_bail(): return
		if chosen == null:
			chosen = hand[hand.size() - 1]
	hand.erase(chosen)
	chosen.current_location = "deck"
	deck.push_front(chosen)
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SPECIAL DELIVERY! CARD PLACED ON TOP OF DECK!")
	if main._should_bail(): return
	print("POWER USED: Special Delivery")

# SOLAR POWER (basep-13 Venusaur): clear all status from both Active Pokemon
func power_solar_power(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("SOLAR POWER IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SOLAR POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var player_active = main.player_active_pokemon
	var opp_active = main.opponent_active_pokemon
	if player_active != null:
		main.clear_all_statuses(player_active, false)
	if opp_active != null:
		main.clear_all_statuses(opp_active, true)
	await main.show_message("SOLAR POWER! ALL STATUS CONDITIONS CURED!")
	if main._should_bail(): return
	print("POWER USED: Solar Power")

# [JOIN] (basep-38 Unown J): if all 4 Unown (J, O, I, Dragon) are on bench, search deck for any card
func power_join_unown(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("[JOIN] IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[JOIN] ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var is_opponent = pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var required = ["Unown [J]", "Unown [O]", "Unown [I]", "Unown Dragon"]
	var found: Array = []
	for bp in bench:
		var bname = bp.metadata.get("name", "")
		if bname in required:
			found.append(bname)
	for req in required:
		if req not in found:
			await main.show_message("[JOIN] REQUIRES ALL 4 UNOWN (J, O, I, DRAGON) ON YOUR BENCH!")
			if main._should_bail(): return
			return
	pokemon.power_used_this_turn = true
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = deck[0]
	else:
		chosen = await main.card_ops.prompt_select_card(deck, "[JOIN] — SEARCH YOUR DECK", "Choose any card to put into your hand", "TAKE", false, true)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("[JOIN]! FOUND " + chosen.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Join] Unown")

# BOLT (basep-34 Entei): on-damage hook — if damaged but not KO'd, flip; heads = shuffle into deck
func check_bolt(damaged: card_object, attacker: card_object, damage: int, is_damaged_opp: bool) -> void:
	if damaged == null or damage <= 0:
		return
	if damaged.current_hp <= 0:
		return
	if not damaged.has_ability("Bolt"):
		return
	if is_power_blocked(damaged):
		return
	await main.show_message("BOLT! " + damaged.metadata.get("name","").to_upper() + " FLIPPING TO ESCAPE...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_damaged_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENTEI STAYS!")
		if main._should_bail(): return
		return
	# Heads — shuffle Entei and all attached cards into its deck
	var deck = main.opponent_deck if is_damaged_opp else main.player_deck
	var bench = main.opponent_bench if is_damaged_opp else main.player_bench
	var is_active = (damaged == (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon))
	for e in damaged.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	damaged.attached_energies.clear()
	for pre in damaged.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	damaged.attached_pre_evolutions.clear()
	for ac in damaged.attached_cards:
		ac.current_location = "deck"
		deck.append(ac)
	damaged.attached_cards.clear()
	main.clear_all_statuses(damaged, is_damaged_opp)
	damaged.current_hp = damaged.get_max_hp()
	damaged.current_location = "deck"
	deck.append(damaged)
	deck.shuffle()
	if is_active:
		if is_damaged_opp:
			main.opponent_active_pokemon = null
		else:
			main.player_active_pokemon = null
	else:
		bench.erase(damaged)
	main.display_pokemon(is_damaged_opp)
	main.update_deck_icon(is_damaged_opp)
	await main.show_message("BOLT! ENTEI SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	if is_active:
		await main.handle_post_knockout(is_damaged_opp)
	if main._should_bail(): return
	print("POWER TRIGGERED: Bolt - Entei shuffled into deck")

# NEUTRAL SHIELD (basep-47 Mew): prevent all effects from Evolved Pokemon
# Returns true if the attack should be blocked (caller must check this)
func check_neutral_shield(defender: card_object, attacker: card_object) -> bool:
	if defender == null or attacker == null:
		return false
	if not defender.has_ability("Neutral Shield"):
		return false
	if is_power_blocked(defender):
		return false
	var subtypes = attacker.metadata.get("subtypes", [])
	if "Stage 1" in subtypes or "Stage 2" in subtypes:
		print("NEUTRAL SHIELD: Blocked attack from evolved Pokemon ", attacker.metadata.get("name",""))
		return true
	return false

# AURORA VEIL (basep-48 Articuno): bench Pokemon immune to damage while Articuno is active
# Returns true if bench damage is blocked (caller must skip the damage)
func check_aurora_veil(bench_owner_is_opp: bool) -> bool:
	var active = main.opponent_active_pokemon if bench_owner_is_opp else main.player_active_pokemon
	if active == null:
		return false
	if not active.has_ability("Aurora Veil"):
		return false
	if is_power_blocked(active):
		return false
	print("AURORA VEIL: Bench damage blocked for ", "opponent" if bench_owner_is_opp else "player")
	return true

# CHAIN REACTION (basep-11 Eevee): evolve all Eevees in play using Evolution cards from hand
func power_chain_reaction(eevee: card_object) -> void:
	if is_power_blocked_by_status(eevee):
		await main.show_message("CHAIN REACTION BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if eevee.power_used_this_turn:
		await main.show_message("CHAIN REACTION ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var is_opp: bool = (eevee == main.opponent_active_pokemon or eevee in main.opponent_bench)
	var hand = main.opponent_hand if is_opp else main.player_hand
	var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
	var bench = main.opponent_bench if is_opp else main.player_bench
	# Collect all Eevees in play
	var eevees: Array = []
	if active != null and active.metadata.get("name", "") == "Eevee":
		eevees.append(active)
	for bp in bench:
		if bp.metadata.get("name", "") == "Eevee":
			eevees.append(bp)
	if eevees.size() == 0:
		await main.show_message("NO EEVEES IN PLAY!")
		if main._should_bail(): return
		return
	# Check for evolution cards in hand
	var has_evo: bool = false
	for c in hand:
		if c.metadata.get("evolvesFrom", "") == "Eevee":
			has_evo = true
			break
	if not has_evo:
		await main.show_message("NO EEVEE EVOLUTION CARDS IN HAND!")
		if main._should_bail(): return
		return
	eevee.power_used_this_turn = true
	await main.show_message("CHAIN REACTION! EVOLVING ALL EEVEES!")
	if main._should_bail(): return
	for target_eevee in eevees:
		var available_evo: Array = []
		for c in hand:
			if c.metadata.get("evolvesFrom", "") == "Eevee":
				available_evo.append(c)
		if available_evo.size() == 0:
			break
		var chosen_evo: card_object = null
		if is_opp:
			chosen_evo = available_evo[0]
			for c in available_evo:
				if int(c.metadata.get("hp", "0")) > int(chosen_evo.metadata.get("hp", "0")):
					chosen_evo = c
		else:
			if available_evo.size() == 1:
				chosen_evo = available_evo[0]
			else:
				chosen_evo = await main.card_ops.prompt_select_card(available_evo, "CHAIN REACTION: EVOLVE " + target_eevee.metadata.get("name", "").to_upper(), "Choose an Evolution for this Eevee (cancel to skip)", "EVOLVE", true)
				if main._should_bail(): return
			if chosen_evo == null:
				continue
		# Perform evolution (mirrors perform_evolution in Main)
		var max_hp_old = int(target_eevee.metadata.get("hp", "0"))
		var damage_taken = max_hp_old - target_eevee.current_hp
		var max_hp_new = int(chosen_evo.metadata.get("hp", "0"))
		chosen_evo.current_hp = max(1, max_hp_new - damage_taken)
		chosen_evo.attached_energies = target_eevee.attached_energies.duplicate()
		target_eevee.attached_energies.clear()
		chosen_evo.attached_pre_evolutions = target_eevee.attached_pre_evolutions.duplicate()
		target_eevee.attached_pre_evolutions.clear()
		chosen_evo.attached_pre_evolutions.append(target_eevee)
		chosen_evo.placed_on_field_this_turn = true
		hand.erase(chosen_evo)
		chosen_evo.current_location = target_eevee.current_location
		var is_active_slot = (target_eevee == (main.opponent_active_pokemon if is_opp else main.player_active_pokemon))
		if is_active_slot:
			if is_opp:
				main.opponent_active_pokemon = chosen_evo
			else:
				main.player_active_pokemon = chosen_evo
		else:
			var bench_idx = bench.find(target_eevee)
			if bench_idx >= 0:
				bench[bench_idx] = chosen_evo
		main.clear_all_statuses(target_eevee, is_opp)
		main.display_pokemon(is_opp)
		main.display_active_pokemon_energies(is_opp)
		main.refresh_hand_display(is_opp)
		await main.show_message("CHAIN REACTION: " + target_eevee.metadata.get("name", "").to_upper() + " EVOLVED INTO " + chosen_evo.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	print("POWER USED: Chain Reaction")

# PURE BODY (basep-53 Suicune): while Suicune is your Active, opponent can't attach Special Energy
# This is a passive body — checked in Special_Energy_Effects.can_attach_to() directly.

# GUARD (basep-49 Snorlax): defending Pokemon can't retreat while Snorlax is active
# Returns true if retreat should be blocked (called from can_retreat)
func check_guard_body(is_retreating_opp: bool) -> bool:
	# The OPPOSING active Pokémon is the one that might have Guard
	var blocking_active = main.player_active_pokemon if is_retreating_opp else main.opponent_active_pokemon
	if blocking_active == null:
		return false
	if not blocking_active.has_ability("Guard"):
		return false
	if is_power_blocked(blocking_active):
		return false
	print("GUARD: Retreat blocked by Snorlax Guard body")
	return true

######################################################################################################################################################
############################################################## NEO1 (NEO GENESIS) POWERS & BODIES ####################################################
######################################################################################################################################################

# ── Register neo1 powers in the dispatch ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
func _register_neo1_powers() -> void:
	_power_dispatch["Downpour"]           = func(p): await power_neo1_downpour(p)
	_power_dispatch["Fire Recharge"]      = func(p): await power_neo1_fire_recharge(p)
	_power_dispatch["Glaring Gaze"]       = func(p): await power_neo1_glaring_gaze(p)
	_power_dispatch["Playful Punch"]      = func(p): await power_neo1_playful_punch(p)

# Called from _register_all_powers at startup

# ── Passive checks (called directly from Main / Attack_Effects) ────────────────────────────────────────────────────────────────────────────────────────

# WILD GROWTH (neo1-11 Meganium): each Grass Energy on Grass Pokemon counts as 2 Grass
# Called from get_energy_provided_by_card when a Grass energy is on a Grass pokemon
func is_wild_growth_active() -> bool:
	var all_poke: Array = []
	if main.player_active_pokemon != null: all_poke.append(main.player_active_pokemon)
	if main.opponent_active_pokemon != null: all_poke.append(main.opponent_active_pokemon)
	all_poke.append_array(main.player_bench)
	all_poke.append_array(main.opponent_bench)
	for p in all_poke:
		if _power_active_on(p, "Wild Growth", false):
			return true
	return false

# FINAL BLOW (neo1-6 Heracross): if HP ≤ 20, Megahorn does 120 instead of 60
func get_final_blow_damage(attacker: card_object, attack_name: String, base_damage: int) -> int:
	if attack_name.to_lower() != "megahorn":
		return base_damage
	if not _power_active_on(attacker, "Final Blow", false):
		return base_damage
	if attacker.current_hp > 20:
		return base_damage
	return 120

# HYDROELECTRIC POWER (neo1-38 Lanturn): Floodlight does +10 per extra Water Energy
func get_hydroelectric_bonus(attacker: card_object, attack_name: String) -> int:
	if attack_name.to_lower() != "floodlight":
		return 0
	if not _power_active_on(attacker, "Hydroelectric Power", false):
		return 0
	var attack_cost_water = 0
	for ab in attacker.metadata.get("attacks", []):
		if ab.get("name", "").to_lower() == "floodlight":
			for c in ab.get("cost", []):
				if c == "Water":
					attack_cost_water += 1
			break
	var attached_water = 0
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			attached_water += 1
	var extra = max(0, attached_water - attack_cost_water)
	return extra * 10

# SPROUT TOWER (neo1-97 Stadium): Colorless Pokemon attacks reduced by 30
func apply_sprout_tower_reduction(attacker: card_object, damage: int) -> int:
	if not main.is_stadium_in_play(StadiumIds.SPROUT_TOWER):
		return damage
	var types = attacker.metadata.get("types", ["Colorless"])
	if types.is_empty() or types[0] != "Colorless":
		return damage
	return max(0, damage - 30)

# MIND GAMES (neo1-14 Slowking): when opponent plays Trainer, flip — heads: cancel it
# Returns true if the trainer is cancelled (caller must abort trainer effect)
func check_mind_games(is_opponent_playing_trainer: bool) -> bool:
	if is_power_blocked_by_status(null):
		return false
	var mind_games_side = main.opponent_active_pokemon if is_opponent_playing_trainer else main.player_active_pokemon
	var opp_side_bench = main.opponent_bench if is_opponent_playing_trainer else main.player_bench
	var mind_games_pokemon: card_object = null
	var check_bench = main.player_bench if is_opponent_playing_trainer else main.opponent_bench
	var check_active = main.player_active_pokemon if is_opponent_playing_trainer else main.opponent_active_pokemon
	if check_active != null and _power_active_on(check_active, "Mind Games", false):
		mind_games_pokemon = check_active
	if mind_games_pokemon == null:
		for bp in check_bench:
			if _power_active_on(bp, "Mind Games", false):
				mind_games_pokemon = bp
				break
	if mind_games_pokemon == null:
		return false
	var slowking_is_opp = (mind_games_pokemon == main.opponent_active_pokemon or mind_games_pokemon in main.opponent_bench)
	var coin = await main.flip_coin(is_opponent_playing_trainer, slowking_is_opp)
	if main._should_bail(): return false
	if coin:
		await main.show_message("MIND GAMES! " + mind_games_pokemon.metadata.get("name","").to_upper() + " CANCELLED THE TRAINER CARD! IT GOES BACK ON TOP OF DECK!")
		if main._should_bail(): return false
		return true
	await main.show_message("MIND GAMES: TAILS — TRAINER CARD PROCEEDS!")
	if main._should_bail(): return false
	return false

# Check Focus Band (neo1-86 Tool): when KO'd by opponent's attack, flip — heads: survive at 10 HP
func check_focus_band(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
		return false
	for card in pokemon.attached_cards:
		if card.metadata.get("name", "") == "Focus Band":
			var coin = await main.flip_coin(is_opp, not is_opp)
			if main._should_bail(): return false
			if coin:
				pokemon.current_hp = 10
				main.display_hp_circles_above_align(pokemon, is_opp)
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
				discard.append(card)
				main.update_discard_pile_display(is_opp)
				await main.show_message("FOCUS BAND! " + pokemon.metadata.get("name","").to_upper() + " SURVIVED WITH 10 HP!")
				if main._should_bail(): return false
				return true
			else:
				await main.show_message("FOCUS BAND: TAILS! " + pokemon.metadata.get("name","").to_upper() + " IS KNOCKED OUT!")
				if main._should_bail(): return false
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard2 = main.opponent_discard_pile if is_opp else main.player_discard_pile
				discard2.append(card)
			break
	return false

# Process Pokemon Tools at start of turn: Gold Berry, Miracle Berry, Berry, Char counter
func process_turn_start_tools_and_counters(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for pokemon in all_poke:
		if main._should_bail(): return
		var poke_is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
		# Char counter: owner must flip — tails = 20 damage
		if pokemon.has_char_counter:
			var coin = await main.flip_coin(false, poke_is_opp)
			if main._should_bail(): return
			if not coin:
				pokemon.current_hp = max(0, pokemon.current_hp - 20)
				main.display_hp_circles_above_align(pokemon, poke_is_opp)
				await main.show_message("CHAR COUNTER! " + pokemon.metadata.get("name","").to_upper() + " TOOK 20 DAMAGE!")
				if main._should_bail(): return
				await main.check_all_knockouts()
				if main._should_bail(): return
		# Tool processing for this side's pokemon only
		if poke_is_opp == is_opponent:
			for tool in pokemon.attached_cards.duplicate():
				if main._should_bail(): return
				var tool_name = tool.metadata.get("name", "")
				var max_hp = pokemon.get_max_hp()
				if tool_name == "Gold Berry":
					# MATCH EFFECTS: healing gate — berry is NOT consumed while healing is blocked
					if max_hp - pokemon.current_hp >= 40 and main.match_effects.modify_heal_amount(40, is_opponent) > 0:
						pokemon.current_hp = min(max_hp, pokemon.current_hp + main.match_effects.modify_heal_amount(40, is_opponent))
						SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
						main.display_hp_circles_above_align(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("GOLD BERRY! " + pokemon.metadata.get("name","").to_upper() + " HEALED 40 HP!")
						if main._should_bail(): return
				elif tool_name == "Berry":
					# MATCH EFFECTS: healing gate — berry is NOT consumed while healing is blocked
					if max_hp - pokemon.current_hp >= 20 and main.match_effects.modify_heal_amount(20, is_opponent) > 0:
						pokemon.current_hp = min(max_hp, pokemon.current_hp + main.match_effects.modify_heal_amount(20, is_opponent))
						SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
						main.display_hp_circles_above_align(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp2.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("BERRY! " + pokemon.metadata.get("name","").to_upper() + " HEALED 20 HP!")
						if main._should_bail(): return
				elif tool_name == "Miracle Berry":
					if pokemon.special_condition != "" or pokemon.is_poisoned or pokemon.is_burned:
						main.clear_all_statuses(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp3 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp3.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("MIRACLE BERRY! " + pokemon.metadata.get("name","").to_upper() + " CURED OF ALL STATUS CONDITIONS!")
						if main._should_bail(): return

# Clear jaw_clamp_locked at end of opponent's turn (called when clearing retreat flags)
func clear_neo1_flags_end_of_turn(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.jaw_clamp_locked = false
		p.screech_damage_bonus = 0
		p.endure_active = false
	if is_opponent:
		if main.opponent_retreat_disabled and not main.opponent_active_pokemon in []:
			main.opponent_retreat_disabled = false
	else:
		if main.player_retreat_disabled:
			main.player_retreat_disabled = false

# ── On-play triggers ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# BERSERK (neo1-4 Feraligatr): on-play flip — heads: discard top 5 opponent deck; tails: discard top 5 own deck
func trigger_neo1_berserk(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if coin:
		var deck = main.player_deck if is_opp else main.opponent_deck
		var discard = main.player_discard_pile if is_opp else main.opponent_discard_pile
		var target_is_opp = not is_opp
		var n = min(5, deck.size())
		for i in range(n):
			var c = deck[0]
			deck.remove_at(0)
			c.current_location = "discard"
			discard.append(c)
		main.update_discard_pile_display(target_is_opp)
		main.update_deck_icon(target_is_opp)
		await main.show_message("BERSERK! HEADS! DISCARDED TOP " + str(n) + " CARDS FROM OPPONENT'S DECK!")
	else:
		var deck = main.opponent_deck if is_opp else main.player_deck
		var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
		var n = min(5, deck.size())
		for i in range(n):
			var c = deck[0]
			deck.remove_at(0)
			c.current_location = "discard"
			discard.append(c)
		main.update_discard_pile_display(is_opp)
		main.update_deck_icon(is_opp)
		await main.show_message("BERSERK! TAILS! DISCARDED TOP " + str(n) + " CARDS FROM YOUR OWN DECK!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Berserk")

# HERBAL SCENT (neo1-10 Meganium): on-play flip — heads: remove all damage from all Grass Pokemon in play
func trigger_neo1_herbal_scent(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var do_flip: bool = false
	if is_opp:
		do_flip = true
	else:
		do_flip = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "HERBAL SCENT", "Flip a coin? Heads = heal all Grass Pokemon!", "FLIP", "SKIP")
		if main._should_bail(): return
	if not do_flip: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("HERBAL SCENT: TAILS!")
		if main._should_bail(): return
		return
	var all_poke: Array = []
	if main.player_active_pokemon != null: all_poke.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null: all_poke.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench: all_poke.append({"p": bp, "opp": false})
	for bp in main.opponent_bench: all_poke.append({"p": bp, "opp": true})
	var healed_count = 0
	for entry in all_poke:
		var p = entry["p"]
		if "Grass" in p.metadata.get("types", []):
			p.current_hp = p.get_max_hp()
			main.display_hp_circles_above_align(p, entry["opp"])
			healed_count += 1
	if healed_count > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("HERBAL SCENT! HEADS! FULLY HEALED " + str(healed_count) + " GRASS POKEMON!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Herbal Scent - healed ", healed_count)

# FIRE BOOST (neo1-18 Typhlosion): on-play flip — heads: search deck for up to 4 Fire Energy, attach to self
func trigger_neo1_fire_boost(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var do_flip: bool = false
	if is_opp:
		do_flip = true
	else:
		do_flip = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "FIRE BOOST", "Flip a coin? Heads = attach up to 4 Fire Energy from deck!", "FLIP", "SKIP")
		if main._should_bail(): return
	if not do_flip: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FIRE BOOST: TAILS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opp else main.player_deck
	var fire_in_deck: Array = []
	for c in deck:
		if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
			fire_in_deck.append(c)
	if fire_in_deck.size() == 0:
		await main.show_message("FIRE BOOST: HEADS! BUT NO FIRE ENERGY IN DECK!")
		if main._should_bail(): return
		return
	var picks = min(4, fire_in_deck.size())
	for i in range(picks):
		var e = fire_in_deck[i]
		deck.erase(e)
		e.current_location = "attached"
		pokemon.attached_energies.append(e)
	deck.shuffle()
	main.display_active_pokemon_energies(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("FIRE BOOST! HEADS! ATTACHED " + str(picks) + " FIRE ENERGY TO TYPHLOSION!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Fire Boost - attached ", picks, " fire energy")

# ── Active power implementations ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# DOWNPOUR (neo1-5 Feraligatr): discard a Water Energy from hand as often as you like
func power_neo1_downpour(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("DOWNPOUR BLOCKED BY STATUS!")
		return
	var hand = main.opponent_hand if is_opp else main.player_hand
	var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
	var water_in_hand: Array = []
	for c in hand:
		if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
			water_in_hand.append(c)
	if water_in_hand.size() == 0:
		if not is_opp: await main.show_message("NO WATER ENERGY IN HAND TO DISCARD!")
		return
	if is_opp:
		var e = water_in_hand[0]
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
		main.refresh_hand_display(is_opp)
		main.update_discard_pile_display(is_opp)
		await main.show_message("DOWNPOUR: DISCARDED A WATER ENERGY!")
		if main._should_bail(): return
	else:
		var e = await main.card_ops.prompt_select_card(water_in_hand, "DOWNPOUR: DISCARD WATER ENERGY", "Choose a Water Energy to discard (increases Riptide damage)", "DISCARD", true)
		if main._should_bail(): return
		if e == null: return
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
		main.refresh_hand_display(is_opp)
		main.update_discard_pile_display(is_opp)
		await main.show_message("DOWNPOUR: DISCARDED A WATER ENERGY!")
		if main._should_bail(): return
	print("POWER USED: Downpour")

# FIRE RECHARGE (neo1-17 Typhlosion): flip — heads: attach Fire Energy from discard to a Fire Pokemon
func power_neo1_fire_recharge(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("FIRE RECHARGE BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("FIRE RECHARGE ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FIRE RECHARGE: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
	var fire_in_discard: Array = []
	for c in discard:
		if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
			fire_in_discard.append(c)
	if fire_in_discard.size() == 0:
		await main.show_message("FIRE RECHARGE: HEADS! BUT NO FIRE ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	var fire_poke: Array = []
	var all_p: Array = []
	if main.opponent_active_pokemon != null and is_opp: all_p.append(main.opponent_active_pokemon)
	if main.player_active_pokemon != null and not is_opp: all_p.append(main.player_active_pokemon)
	all_p.append_array(main.opponent_bench if is_opp else main.player_bench)
	for p in all_p:
		if "Fire" in p.metadata.get("types", []):
			fire_poke.append(p)
	if fire_poke.size() == 0:
		await main.show_message("FIRE RECHARGE: HEADS! BUT NO FIRE POKEMON IN PLAY!")
		if main._should_bail(): return
		return
	var target: card_object = null
	var energy: card_object = null
	if is_opp:
		target = fire_poke[0]
		energy = fire_in_discard[0]
	else:
		if fire_poke.size() == 1: target = fire_poke[0]
		else:
			target = await main.card_ops.prompt_select_card(fire_poke, "FIRE RECHARGE: CHOOSE TARGET", "Choose a Fire Pokemon to attach energy to", "SELECT", false)
			if main._should_bail(): return
		if target == null: return
		if fire_in_discard.size() == 1: energy = fire_in_discard[0]
		else:
			energy = await main.card_ops.prompt_select_card(fire_in_discard, "FIRE RECHARGE: CHOOSE ENERGY", "Choose a Fire Energy from discard", "ATTACH", false)
			if main._should_bail(): return
		if energy == null: return
	discard.erase(energy)
	energy.current_location = "attached"
	target.attached_energies.append(energy)
	main.display_active_pokemon_energies(is_opp)
	main.update_discard_pile_display(is_opp)
	await main.show_message("FIRE RECHARGE! ATTACHED FIRE ENERGY TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Fire Recharge")

# GLARING GAZE (neo1-42 Noctowl): flip — heads: look at opp hand, remove 1 trainer to deck
func power_neo1_glaring_gaze(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("GLARING GAZE BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("GLARING GAZE ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("GLARING GAZE: TAILS!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opp else main.opponent_hand
	var opp_deck = main.player_deck if is_opp else main.opponent_deck
	var trainers: Array = []
	for c in opp_hand:
		if c.metadata.get("supertype","") == "Trainer":
			trainers.append(c)
	if trainers.size() == 0:
		await main.show_message("GLARING GAZE: HEADS! BUT OPPONENT HAS NO TRAINER CARDS!")
		if main._should_bail(): return
		return
	await main.show_message("GLARING GAZE: HEADS! LOOKING AT OPPONENT'S HAND...")
	if main._should_bail(): return
	var target: card_object = null
	if is_opp:
		target = trainers[0]
	else:
		target = await main.card_ops.prompt_select_card(trainers, "GLARING GAZE: CHOOSE TRAINER", "Choose a Trainer card to shuffle into opponent's deck", "SELECT", false)
		if main._should_bail(): return
	if target == null: return
	opp_hand.erase(target)
	target.current_location = "deck"
	opp_deck.append(target)
	opp_deck.shuffle()
	main.refresh_hand_display(not is_opp)
	main.update_deck_icon(not is_opp)
	await main.show_message("GLARING GAZE! SHUFFLED " + target.metadata.get("name","").to_upper() + " INTO OPPONENT'S DECK!")
	if main._should_bail(): return
	print("POWER USED: Glaring Gaze")

# PLAYFUL PUNCH (neo1-22 Elekid): flip — heads: 20 to each pokemon in play (except self)
func power_neo1_playful_punch(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("PLAYFUL PUNCH BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("PLAYFUL PUNCH ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("PLAYFUL PUNCH: TAILS!")
		if main._should_bail(): return
		return
	var all_targets: Array = []
	if main.player_active_pokemon != null and main.player_active_pokemon != pokemon: all_targets.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null and main.opponent_active_pokemon != pokemon: all_targets.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench:
		if bp != pokemon: all_targets.append({"p": bp, "opp": false})
	for bp in main.opponent_bench:
		if bp != pokemon: all_targets.append({"p": bp, "opp": true})
	for entry in all_targets:
		entry["p"].current_hp = max(0, entry["p"].current_hp - 20)
		main.display_hp_circles_above_align(entry["p"], entry["opp"])
	await main.show_message("PLAYFUL PUNCH! HEADS! 20 DAMAGE TO EACH POKEMON IN PLAY!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Playful Punch")

# ── CPU activations for neo1 powers ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
######################################################################################################################################################
##################################################### NEO2 (NEO DISCOVERY) POWERS & BODIES ##########################################################
######################################################################################################################################################

func _register_neo2_powers() -> void:
	# Active powers — player-activatable
	_power_dispatch["[Find]"]          = func(p): await power_neo2_unown_find(p)
	_power_dispatch["[Undo]"]          = func(p): await power_neo2_unown_undo(p)
	_power_dispatch["[Observe]"]       = func(p): await power_neo2_unown_observe(p)
	_power_dispatch["Gaze"]            = func(p): await power_neo2_gaze(p)
	_power_dispatch["Revive Friends"]  = func(p): await power_neo2_revive_friends(p)
	_power_dispatch["Revive Fossil"]   = func(p): await power_neo2_revive_fossil(p)

# ─── PASSIVE DAMAGE BONUSES ──────────────────────────────────────────────────

# [Anger] (Unown [A]): Hidden Power does +10 per damage counter on Unown [A] (one [A] max)
func get_unown_anger_bonus(attacker: card_object, is_opponent: bool) -> int:
	if "Unown" not in attacker.metadata.get("name",""):
		return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var all_poke: Array = []
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	var unown_a: card_object = null
	var count = 0
	for p in all_poke:
		if "Unown [A]" in p.metadata.get("name","") or "[Anger]" in str(p.metadata.get("abilities",[])):
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Anger]":
					if p.gaze_suppressed: continue
					count += 1
					if unown_a == null:
						unown_a = p
	if unown_a == null:
		return 0
	if is_power_blocked_by_status(unown_a):
		return 0
	var damage_counters = unown_a.get_damage_counters()
	return damage_counters * 10

# FROG SONG (Politoed neo2-8/27): if 4+ poliwag-line in play, Politoed's attacks do +40
func get_frog_song_bonus(attacker: card_object) -> int:
	if "Politoed" not in attacker.metadata.get("name",""):
		return 0
	if is_power_blocked_by_status(attacker): return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	if attacker.gaze_suppressed: return 0
	var names = ["Poliwag", "Poliwhirl", "Poliwrath", "Politoed"]
	var count = 0
	var all_poke: Array = []
	if main.player_active_pokemon: all_poke.append(main.player_active_pokemon)
	if main.opponent_active_pokemon: all_poke.append(main.opponent_active_pokemon)
	all_poke.append_array(main.player_bench)
	all_poke.append_array(main.opponent_bench)
	for p in all_poke:
		if p.metadata.get("name","") in names:
			count += 1
	if count > 3:
		return 40
	return 0

# UNOWN TYPE REDUCTIONS: [D]/[M]/[N] — reduce damage from Darkness/Metal/Colorless pokemon by 30
func apply_unown_type_reductions(attacker_pokemon: card_object, defending_pokemon: card_object, damage: int, modifiers: Array) -> int:
	if attacker_pokemon == null or damage <= 0:
		return damage
	if is_toxic_gas_active() or main.goop_gas_active:
		return damage
	var atk_types = attacker_pokemon.metadata.get("types", ["Colorless"])
	# Determine defender's side
	var def_is_player = (defending_pokemon == main.player_active_pokemon or defending_pokemon in main.player_bench)
	var def_bench = main.player_bench if def_is_player else main.opponent_bench
	var def_active = main.player_active_pokemon if def_is_player else main.opponent_active_pokemon
	var def_all: Array = []
	if def_active != null: def_all.append(def_active)
	def_all.append_array(def_bench)
	# [Darkness] — Unown [D]
	if "Darkness" in atk_types:
		var d_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Darkness]" and not p.gaze_suppressed:
					d_count += 1
		if d_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [D] -30")
	# [Metal] — Unown [M]
	if "Metal" in atk_types:
		var m_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Metal]" and not p.gaze_suppressed:
					m_count += 1
		if m_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [M] -30")
	# [Normal] — Unown [N]
	if "Colorless" in atk_types:
		var n_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Normal]" and not p.gaze_suppressed:
					n_count += 1
		if n_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [N] -30")
	return damage

# ─── ON-DAMAGE HOOKS ─────────────────────────────────────────────────────────

# COUNTER (Wobbuffet): if damaged and counter_active, flip — heads: deal equal damage back to attacker
func check_neo2_counter(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	if not defender.counter_active or damage <= 0 or attacker == null:
		return
	defender.counter_active = false
	if is_toxic_gas_active() or main.goop_gas_active: return
	if is_power_blocked_by_status(defender): return
	var coin = await main.flip_coin(false, is_def_opp)
	if main._should_bail(): return
	if coin:
		attacker.current_hp = max(0, attacker.current_hp - damage)
		var atk_is_opp = not is_def_opp
		main.display_hp_circles_above_align(attacker, atk_is_opp)
		main.show_floating_label("-" + str(damage) + "HP", Vector2(530 if atk_is_opp else 1030, 300), Color.ORANGE, true)
		await main.show_message("COUNTER! " + defender.metadata.get("name","").to_upper() + " DEALS " + str(damage) + " DAMAGE BACK!")
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! COUNTER FAILED!")
		if main._should_bail(): return
	print("EFFECT: Counter checked — ", "hit" if coin else "miss")

# SECRETE POISON (Kakuna): if damaged with secrete_poison_active, attacker poisoned + 10 to each opp bench
func check_neo2_secrete_poison(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	if not defender.secrete_poison_active or damage <= 0 or attacker == null:
		return
	defender.secrete_poison_active = false
	if is_toxic_gas_active() or main.goop_gas_active: return
	main.card_ops.apply_status(attacker, "Poisoned", not is_def_opp)
	await main.show_message("SECRETE POISON! " + attacker.metadata.get("name","").to_upper() + " IS POISONED!")
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_def_opp else main.opponent_bench
	for bp in opp_bench:
		if bp.current_hp > 0:
			main.card_ops.apply_bench_damage(bp, 10, not is_def_opp)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("EFFECT: Secrete Poison triggered")

# ─── SPIKES (Forretress neo2-2/21): 10 damage to bench→active switch target ─
func check_spikes(new_active: card_object, is_new_active_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var forretress_bench = main.opponent_bench if not is_new_active_opp else main.player_bench
	var forretress_active = main.opponent_active_pokemon if not is_new_active_opp else main.player_active_pokemon
	var forretress_side: Array = []
	if forretress_active != null: forretress_side.append(forretress_active)
	forretress_side.append_array(forretress_bench)
	for p in forretress_side:
		if "Forretress" not in p.metadata.get("name",""):
			continue
		if is_power_blocked_by_status(p):
			continue
		if p.gaze_suppressed:
			continue
		var has_spikes = false
		for ab in p.metadata.get("abilities",[]):
			if ab.get("name","") == "Spikes":
				has_spikes = true
				break
		if not has_spikes:
			continue
		if new_active.current_hp > 0:
			new_active.current_hp = max(0, new_active.current_hp - 10)
			main.display_hp_circles_above_align(new_active, is_new_active_opp)
			main.show_floating_label("-10HP", Vector2(530 if is_new_active_opp else 1030, 300), Color.WHITE, true)
			await main.show_message("SPIKES! " + p.metadata.get("name","").to_upper() + " DEALS 10 DAMAGE TO " + new_active.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
		break

# ─── ENERGY EVOLUTION (Eevee neo2-38): on energy attach, flip for matching evo
func check_energy_evolution(eevee: card_object, energy: card_object, is_opponent: bool) -> void:
	if "Eevee" not in eevee.metadata.get("name",""):
		return
	var has_ee = false
	for ab in eevee.metadata.get("abilities",[]):
		if ab.get("name","") == "Energy Evolution":
			has_ee = true
			break
	if not has_ee: return
	if is_power_blocked_by_status(eevee): return
	if is_toxic_gas_active() or main.goop_gas_active: return
	if eevee.gaze_suppressed: return
	var energy_types = main.get_energy_provided_by_card(energy)
	if energy_types.is_empty(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY EVOLUTION: TAILS! NO EVOLUTION!")
		if main._should_bail(): return
		return
	var energy_type = energy_types[0]
	await main.show_message("ENERGY EVOLUTION! SEARCHING FOR " + energy_type.to_upper() + "-TYPE EVO...")
	if main._should_bail(): return
	var evo_filter = func(c: card_object) -> bool:
		if "evolvesFrom" not in c.metadata or c.metadata["evolvesFrom"] != "Eevee":
			return false
		var evo_types = c.metadata.get("types",[])
		return energy_type in evo_types
	var found = await main.card_ops.search_deck_to_hand(is_opponent, evo_filter, "ENERGY EVOLUTION: CHOOSE EVO OF MATCHING TYPE", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO MATCHING EVOLUTION FOUND IN DECK!")
		if main._should_bail(): return
		return
	var evo_card: card_object = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(evo_card)
	evo_card.attached_pre_evolutions.append(eevee)
	var all_energy = eevee.attached_energies.duplicate()
	for e in all_energy:
		eevee.attached_energies.erase(e)
		evo_card.attached_energies.append(e)
	evo_card.current_hp = evo_card.get_max_hp()
	evo_card.placed_on_field_this_turn = true
	if eevee.current_location == "active":
		evo_card.current_location = "active"
		if is_opponent:
			main.opponent_active_pokemon = evo_card
		else:
			main.player_active_pokemon = evo_card
	else:
		evo_card.current_location = "bench"
		var bench = main.opponent_bench if is_opponent else main.player_bench
		bench.erase(eevee)
		bench.append(evo_card)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ENERGY EVOLUTION! EEVEE EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ENERGY EVOLUTION: Eevee evolved to ", evo_card.metadata.get("name",""))

# ─── ACTIVE POWERS ────────────────────────────────────────────────────────────

# [FIND] (Unown [F]): if F,I,N,D all on bench, search deck for a Trainer
func power_neo2_unown_find(unown_f: card_object) -> void:
	if unown_f.power_used_this_turn: return
	var bench = main.player_bench
	var names_on_bench = bench.map(func(p): return p.metadata.get("name",""))
	var has_i = names_on_bench.any(func(n): return "Unown [I]" in n)
	var has_n = names_on_bench.any(func(n): return "Unown [N]" in n)
	var has_d = names_on_bench.any(func(n): return "Unown [D]" in n)
	if not (has_i and has_n and has_d):
		await main.show_message("[FIND] REQUIRES UNOWN [F], [I], [N], AND [D] ON BENCH!")
		if main._should_bail(): return
		return
	unown_f.power_used_this_turn = true
	var found = await main.card_ops.search_deck_to_hand(false, func(c): return c.metadata.get("supertype","") == "Trainer", "[FIND]: CHOOSE A TRAINER CARD", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO TRAINER CARD FOUND IN DECK!")
		if main._should_bail(): return
		return
	await main.show_message("[FIND]! TRAINER CARD ADDED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Find] — Trainer card retrieved")

# [UNDO] (Unown [U]): if U,N,D,O all on bench, return active + attachments to hand
func power_neo2_unown_undo(unown_u: card_object) -> void:
	if unown_u.power_used_this_turn: return
	var bench = main.player_bench
	var names_on_bench = bench.map(func(p): return p.metadata.get("name",""))
	var has_n = names_on_bench.any(func(n): return "Unown [N]" in n)
	var has_d = names_on_bench.any(func(n): return "Unown [D]" in n)
	var has_o = names_on_bench.any(func(n): return "Unown [O]" in n)
	if not (has_n and has_d and has_o):
		await main.show_message("[UNDO] REQUIRES UNOWN [U], [N], [D], AND [O] ON BENCH!")
		if main._should_bail(): return
		return
	var active = main.player_active_pokemon
	if active == null:
		await main.show_message("NO ACTIVE POKEMON TO RETURN!")
		if main._should_bail(): return
		return
	unown_u.power_used_this_turn = true
	var to_return: Array = [active]
	for e in active.attached_energies.duplicate():
		to_return.append(e)
	for c in active.attached_cards.duplicate():
		to_return.append(c)
	for pre in active.attached_pre_evolutions.duplicate():
		to_return.append(pre)
	active.attached_energies.clear()
	active.attached_cards.clear()
	active.attached_pre_evolutions.clear()
	main.player_active_pokemon = null
	for card_item in to_return:
		card_item.current_location = "hand"
		card_item.placed_on_field_this_turn = false
		main.player_hand.append(card_item)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	main.refresh_hand_display(false)
	await main.show_message("[UNDO]! " + active.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Undo] — active returned to hand")

# [OBSERVE] (Unown [O]): look at top 5 of opponent's deck
func power_neo2_unown_observe(unown_o: card_object) -> void:
	if unown_o.power_used_this_turn: return
	unown_o.power_used_this_turn = true
	var deck = main.opponent_deck
	if deck.is_empty():
		await main.show_message("OPPONENT'S DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top5 = []
	for i in range(min(5, deck.size())):
		top5.append(deck[i])
	await main.show_message("[OBSERVE]! LOOKING AT TOP " + str(top5.size()) + " CARDS OF OPPONENT'S DECK...")
	if main._should_bail(): return
	var _viewed = await main.card_ops.prompt_select_card(top5, "[OBSERVE]: OPPONENT'S TOP " + str(top5.size()), "Look at these cards, then press Done", "DONE", true)
	if main._should_bail(): return
	print("POWER USED: [Observe] — viewed top 5 opponent deck")

# GAZE (Igglybuff neo2-40): choose 1 opponent bench pokemon with a power; suppress its power until EOT
func power_neo2_gaze(igglybuff: card_object) -> void:
	if igglybuff.power_used_this_turn: return
	var opp_bench = main.opponent_bench
	var valid_targets: Array = []
	for bp in opp_bench:
		for ab in bp.metadata.get("abilities",[]):
			if ab.get("type","") in ["Pokémon Power","Pokemon Power"]:
				valid_targets.append(bp)
				break
	if valid_targets.is_empty():
		await main.show_message("GAZE: NO OPPONENT BENCH POKEMON WITH A POWER!")
		if main._should_bail(): return
		return
	igglybuff.power_used_this_turn = true
	var target: card_object = null
	target = await main.card_ops.prompt_select_card(valid_targets, "GAZE", "Choose opponent bench pokemon to suppress", "SELECT", true)
	if main._should_bail(): return
	if target == null: return
	target.gaze_suppressed = true
	await main.show_message("GAZE! " + target.metadata.get("name","").to_upper() + "'S POWER IS SUPPRESSED THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Gaze — suppressed ", target.metadata.get("name",""))

# REVIVE FRIENDS (Kabuto neo2-56): flip — if heads, search deck for Kabuto and bench it
func power_neo2_revive_friends(kabuto: card_object) -> void:
	if kabuto.power_used_this_turn: return
	if is_power_blocked_by_status(kabuto): return
	var is_opponent = (kabuto == main.opponent_active_pokemon or kabuto in main.opponent_bench)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("REVIVE FRIENDS: BENCH IS FULL!")
		if main._should_bail(): return
		return
	kabuto.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! REVIVE FRIENDS FAILED!")
		if main._should_bail(): return
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Kabuto" in c.metadata.get("name","") and main.is_basic_pokemon(c), "REVIVE FRIENDS: CHOOSE KABUTO TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO KABUTO FOUND IN DECK!")
		if main._should_bail(): return
		return
	var new_kabuto = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(new_kabuto)
	var placed = main.card_ops.place_on_bench(new_kabuto, is_opponent)
	if placed:
		await main.show_message("REVIVE FRIENDS! KABUTO JOINED THE BENCH!")
		if main._should_bail(): return
	print("POWER USED: Revive Friends")

# REVIVE FOSSIL (Omanyte neo2-60): flip — if heads, search deck for any fossil evo, bench it as Basic
func power_neo2_revive_fossil(omanyte: card_object) -> void:
	if omanyte.power_used_this_turn: return
	if is_power_blocked_by_status(omanyte): return
	var is_opponent = (omanyte == main.opponent_active_pokemon or omanyte in main.opponent_bench)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("REVIVE FOSSIL: BENCH IS FULL!")
		if main._should_bail(): return
		return
	omanyte.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! REVIVE FOSSIL FAILED!")
		if main._should_bail(): return
		return
	var fossil_filter = func(c: card_object) -> bool:
		return "Mysterious Fossil" in c.metadata.get("evolvesFrom","") and "Stage 1" in c.metadata.get("subtypes",[])
	var found = await main.card_ops.search_deck_to_hand(is_opponent, fossil_filter, "REVIVE FOSSIL: CHOOSE FOSSIL POKEMON TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO FOSSIL POKEMON FOUND IN DECK!")
		if main._should_bail(): return
		return
	var fossil_poke = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(fossil_poke)
	fossil_poke.placed_on_field_this_turn = true
	fossil_poke.current_location = "bench"
	fossil_poke.current_hp = fossil_poke.get_max_hp()
	bench.append(fossil_poke)
	main.display_pokemon(is_opponent)
	await main.show_message("REVIVE FOSSIL! " + fossil_poke.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
	if main._should_bail(): return
	print("POWER USED: Revive Fossil")

# ─── ON-PLAY TRIGGERS ────────────────────────────────────────────────────────

# [ENGAGE] (Unown [E] neo2-67): when played, both sides may shuffle and draw 4
func trigger_neo2_unown_engage(unown_e: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var has_engage = false
	for ab in unown_e.metadata.get("abilities",[]):
		if ab.get("name","") == "[Engage]":
			has_engage = true
			break
	if not has_engage: return
	await main.show_message("[ENGAGE]! UNOWN [E] WAS PLAYED!")
	if main._should_bail(): return
	# Opponent of the player who played it can choose to draw
	var opp_of_player = not is_opponent
	var opp_hand = main.opponent_hand if opp_of_player else main.player_hand
	var opp_deck = main.opponent_deck if opp_of_player else main.player_deck
	var should_opp_draw = false
	if opp_of_player:  # CPU would be the one choosing
		should_opp_draw = (opp_hand.size() < 5)
	else:
		# Player chooses
		await main.show_message("[ENGAGE]: OPPONENT CAN SHUFFLE HAND AND DRAW 4. OPPONENT CHOOSES...")
		if main._should_bail(): return
		should_opp_draw = (opp_hand.size() < 4)
	if should_opp_draw and opp_deck.size() > 0:
		for c in opp_hand.duplicate():
			c.current_location = "deck"
			opp_deck.append(c)
		opp_hand.clear()
		opp_deck.shuffle()
		main.update_deck_icon(opp_of_player)
		await main.card_ops.draw_n(opp_of_player, 4)
		if main._should_bail(): return
		main.refresh_hand_display(opp_of_player)
		await main.show_message("[ENGAGE]: OPPONENT SHUFFLED AND DREW 4!")
		if main._should_bail(): return
	# Player who played it always gets the option
	var player_hand = main.opponent_hand if is_opponent else main.player_hand
	var player_deck = main.opponent_deck if is_opponent else main.player_deck
	var should_draw = false
	if is_opponent:
		should_draw = (player_hand.size() < 5)
	else:
		await main.show_message("[ENGAGE]: DO YOU WANT TO SHUFFLE AND DRAW 4? (OPPONENT CHOOSES FOR YOU)")
		should_draw = (player_hand.size() < 4)
	if should_draw and player_deck.size() > 0:
		for c in player_hand.duplicate():
			c.current_location = "deck"
			player_deck.append(c)
		player_hand.clear()
		player_deck.shuffle()
		main.update_deck_icon(is_opponent)
		await main.card_ops.draw_n(is_opponent, 4)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
		await main.show_message("[ENGAGE]: " + ("OPPONENT" if is_opponent else "YOU") + " SHUFFLED AND DREW 4!")
		if main._should_bail(): return
	print("TRIGGER: [Engage] — bench-play power triggered")

# [INCREASE] (Unown [I] neo2-68): when played, may search deck for any Unown and bench it
func trigger_neo2_unown_increase(unown_i: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var has_inc = false
	for ab in unown_i.metadata.get("abilities",[]):
		if ab.get("name","") == "[Increase]":
			has_inc = true
			break
	if not has_inc: return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Unown" in c.metadata.get("name","") and main.is_basic_pokemon(c), "[INCREASE]: CHOOSE AN UNOWN TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		return
	var new_unown = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(new_unown)
	var placed = main.card_ops.place_on_bench(new_unown, is_opponent)
	if placed:
		await main.show_message("[INCREASE]! " + new_unown.metadata.get("name","").to_upper() + " PLACED ON BENCH!")
		if main._should_bail(): return
	print("TRIGGER: [Increase] — Unown benched")

# ─── FLAG CLEARING ────────────────────────────────────────────────────────────

func clear_neo2_flags_end_of_turn(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.lock_on_active = false
		p.counter_active = false
		p.pursuit_active = false
		p.secrete_poison_active = false
		p.slime_active = false
		p.gaze_suppressed = false

# ─── CPU PHASE ────────────────────────────────────────────────────────────────

func cpu_phase_neo2_powers() -> void:
	var toxic = is_toxic_gas_active()
	if toxic: return
	# Revive Friends (Kabuto): use if bench not full and Kabuto in deck
	var kabuto = _find_cpu_pokemon_with_power("Revive Friends")
	if kabuto != null and not kabuto.power_used_this_turn and not is_power_blocked_by_status(kabuto):
		if main.opponent_bench.size() < main.get_max_bench_size():
			var has_kabuto_in_deck = false
			for c in main.opponent_deck:
				if "Kabuto" in c.metadata.get("name","") and main.is_basic_pokemon(c):
					has_kabuto_in_deck = true
					break
			if has_kabuto_in_deck:
				await power_neo2_revive_friends(kabuto)
				if main._should_bail(): return
	# Revive Fossil (Omanyte): use if bench not full and fossil in deck
	var omanyte = _find_cpu_pokemon_with_power("Revive Fossil")
	if omanyte != null and not omanyte.power_used_this_turn and not is_power_blocked_by_status(omanyte):
		if main.opponent_bench.size() < main.get_max_bench_size():
			var has_fossil = false
			for c in main.opponent_deck:
				if "Mysterious Fossil" in c.metadata.get("evolvesFrom",""):
					has_fossil = true
					break
			if has_fossil:
				await power_neo2_revive_fossil(omanyte)
				if main._should_bail(): return
	# [Find] (Unown [F]): use if FIND combo on bench and CPU needs a trainer
	var find_combo = _check_unown_combo_on_cpu_bench(["[F]","[I]","[N]","[D]"])
	if find_combo:
		var unown_f = _find_cpu_pokemon_with_power("[Find]")
		if unown_f != null and not unown_f.power_used_this_turn:
			await power_neo2_unown_find(unown_f)
			if main._should_bail(): return
	# Gaze (Igglybuff): use if opponent has a powerful bench power
	var igglybuff = _find_cpu_pokemon_with_power("Gaze")
	if igglybuff != null and not igglybuff.power_used_this_turn and not is_power_blocked_by_status(igglybuff):
		var opp_bench_powers: Array = []
		for bp in main.player_bench:
			for ab in bp.metadata.get("abilities",[]):
				if ab.get("type","") in ["Pokémon Power","Pokemon Power"] and not ab.get("name","") in ["Spikes", "Frog Song"]:
					opp_bench_powers.append(bp)
					break
		if not opp_bench_powers.is_empty():
			igglybuff.power_used_this_turn = true
			var target = opp_bench_powers[0]
			target.gaze_suppressed = true
			await main.show_message("GAZE! OPPONENT'S " + target.metadata.get("name","").to_upper() + "'S POWER IS SUPPRESSED!")
			if main._should_bail(): return

func _check_unown_combo_on_cpu_bench(letters: Array) -> bool:
	var all_opp: Array = []
	if main.opponent_active_pokemon: all_opp.append(main.opponent_active_pokemon)
	all_opp.append_array(main.opponent_bench)
	for letter in letters:
		var found = false
		for p in all_opp:
			if letter in p.metadata.get("name",""):
				found = true
				break
		if not found: return false
	return true

func cpu_phase_neo1_powers() -> void:
	var toxic = is_toxic_gas_active()
	if toxic: return
	# Fire Recharge (Typhlosion): flip to attach Fire from discard
	var typhlosion = _find_cpu_pokemon_with_power("Fire Recharge")
	if typhlosion != null and not typhlosion.power_used_this_turn and not is_power_blocked_by_status(typhlosion):
		var fire_in_discard = false
		for c in main.opponent_discard_pile:
			if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
				fire_in_discard = true
				break
		if fire_in_discard:
			await power_neo1_fire_recharge(typhlosion)
			if main._should_bail(): return
	# Glaring Gaze (Noctowl): use if player has trainers in hand
	var noctowl = _find_cpu_pokemon_with_power("Glaring Gaze")
	if noctowl != null and not noctowl.power_used_this_turn and not is_power_blocked_by_status(noctowl):
		var player_has_trainer = false
		for c in main.player_hand:
			if c.metadata.get("supertype","") == "Trainer":
				player_has_trainer = true
				break
		if player_has_trainer:
			await power_neo1_glaring_gaze(noctowl)
			if main._should_bail(): return
	# Downpour (Feraligatr): discard surplus water from hand to boost Riptide
	# Keeps at least 1 water in hand as a buffer; stops if Riptide already KOs the target
	var feraligtr = _find_cpu_pokemon_with_power("Downpour")
	if feraligtr != null and not is_power_blocked_by_status(feraligtr):
		var has_riptide = false
		for atk in feraligtr.metadata.get("attacks", []):
			if atk.get("name","").to_lower() == "riptide":
				has_riptide = true
				break
		if has_riptide:
			var water_in_discard = 0
			for c in main.opponent_discard_pile:
				if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
					water_in_discard += 1
			var opp_active_hp = main.player_active_pokemon.current_hp if main.player_active_pokemon != null else 999
			var discarded = 0
			while discarded < 3:
				var water_hand_count = 0
				for c in main.opponent_hand:
					if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
						water_hand_count += 1
				if water_hand_count <= 1:
					break
				if 10 + (water_in_discard + discarded) * 10 >= opp_active_hp:
					break
				await power_neo1_downpour(feraligtr)
				if main._should_bail(): return
				discarded += 1
	# Playful Punch (Elekid): use if all opponent pokemon have > 20 HP
	var elekid = _find_cpu_pokemon_with_power("Playful Punch")
	if elekid != null and not elekid.power_used_this_turn and not is_power_blocked_by_status(elekid):
		var all_opp_safe = true
		if main.player_active_pokemon != null and main.player_active_pokemon.current_hp <= 20:
			all_opp_safe = false
		if all_opp_safe:
			for bp in main.player_bench:
				if bp.current_hp <= 20:
					all_opp_safe = false
					break
		if all_opp_safe:
			await power_neo1_playful_punch(elekid)
			if main._should_bail(): return

######################################################################################################################################################
##################################################### NEO3 (NEO REVELATION) POWERS & BODIES ##########################################################
######################################################################################################################################################

func _register_neo3_powers() -> void:
	# Active powers
	_power_dispatch["Softboiled"]           = func(p): await power_neo3_softboiled(p)
	_power_dispatch["Howl"]                 = func(p): await power_neo3_howl(p)
	_power_dispatch["Electromagnetic Power"] = func(p): await power_neo3_electromagnetic_power(p)
	_power_dispatch["Energy Converter"]     = func(p): await power_neo3_energy_converter(p)
	_power_dispatch["Submerge"]             = func(p): await power_neo3_submerge(p)
	_power_dispatch["[Bear]"]               = func(p): await power_neo3_unown_bear(p)
	_power_dispatch["[Yield]"]              = func(p): await power_neo3_unown_yield(p)

# ── PASSIVE BODIES ──────────────────────────────────────────────────────────────

# CRYSTAL BODY (neo3-12 Porygon2): opponent's effects on Porygon2 are prevented (but damage still applies)
# This is queried from apply_attack_effects_on_target. Returns true if effects are blocked.
func has_crystal_body(pokemon: card_object) -> bool:
	if pokemon == null: return false
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Crystal Body":
			if not pokemon.gaze_suppressed and not is_power_blocked_by_status(pokemon):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# LEGENDARY BODY (neo3-17 Entei, neo3-22 Raikou, neo3-27 Suicune Rare): while Active, trainer effects ignored
# Called from play_trainer_card in Main_Match. Returns true if trainer should be blocked.
func check_legendary_body_blocks_trainer(is_opponent_playing_trainer: bool) -> bool:
	# The defender of the trainer effect is the opponent of the player playing it
	var target_active = main.player_active_pokemon if is_opponent_playing_trainer else main.opponent_active_pokemon
	if target_active == null: return false
	for ab in target_active.metadata.get("abilities",[]):
		if ab.get("name","") == "Legendary Body":
			if not target_active.gaze_suppressed and not is_power_blocked_by_status(target_active):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# LIGHTNING BURST (neo3-28 Flaaffy): when a Lightning Energy is attached to Flaaffy, deal 10 to each opp bench
# Called from perform_energy_attachment and CPU energy attach.
func check_lightning_burst(pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Lightning Burst":
			if not pokemon.gaze_suppressed and not is_power_blocked_by_status(pokemon):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if "Lightning" in main.get_energy_provided_by_card(energy_card):
						var opp_bench = main.player_bench if is_opponent else main.opponent_bench
						if not opp_bench.is_empty():
							for bp in opp_bench:
								main.card_ops.apply_damage_to_pokemon(bp, 10, not is_opponent)
							main.display_pokemon(not is_opponent)

# MAGMA POOL (neo3-33 Magcargo): when Magcargo retreats, both pokemon take 20 damage (no W/R)
# Called from handle_action_retreat_bench and execute_cpu_retreat after the swap completes.
func check_magma_pool(retreating: card_object, new_active: card_object, is_opponent: bool) -> void:
	for ab in retreating.metadata.get("abilities",[]):
		if ab.get("name","") == "Magma Pool":
			if not retreating.gaze_suppressed and not is_power_blocked_by_status(retreating):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					main.card_ops.apply_damage_to_pokemon(retreating, 20, is_opponent)
					main.card_ops.apply_damage_to_pokemon(new_active, 20, is_opponent)
					main.display_pokemon(is_opponent)
					return

# [KEEP] (neo3-46 Murkrow): once per turn, may prevent opponent from playing a trainer on Murkrow
# This is a passive blocking ability similar to Crystal Body but trainer-specific.
# Implemented as a check in play_trainer_card, same as Legendary Body.
func check_keep_blocks_trainer_on_murkrow(target: card_object, is_opponent_playing: bool) -> bool:
	if target == null: return false
	var target_name = target.metadata.get("name","")
	if "Murkrow" not in target_name: return false
	for ab in target.metadata.get("abilities",[]):
		if ab.get("name","") == "[Keep]":
			if not target.gaze_suppressed and not is_power_blocked_by_status(target):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# ALLERGIC POLLEN (neo3-9 Jumpluff): when Jumpluff is damaged by an attack, attacker becomes Poisoned
func check_allergic_pollen(jumpluff: card_object, attacker: card_object, is_jumpluff_opponent: bool) -> void:
	if jumpluff == null or attacker == null: return
	for ab in jumpluff.metadata.get("abilities",[]):
		if ab.get("name","") == "Allergic Pollen":
			if not jumpluff.gaze_suppressed and not is_power_blocked_by_status(jumpluff):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if not attacker.is_poisoned:
						attacker.is_poisoned = true
						attacker.poison_damage = 10
						main.update_status_icons(attacker, not is_jumpluff_opponent)

# HARD SHELL (neo3-51 Shuckle): if damage is ≤ 40, reduce it to 10
# Called from calculate_final_damage in Main_Match after all modifiers.
func apply_hard_shell(defender: card_object, damage: int, modifiers_applied: Array) -> int:
	if defender == null: return damage
	for ab in defender.metadata.get("abilities",[]):
		if ab.get("name","") == "Hard Shell":
			if not defender.gaze_suppressed and not is_power_blocked_by_status(defender):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if damage <= 40:
						modifiers_applied.append("Hard Shell (→10)")
						return 10
	return damage

# ── NEO3 FLAG CLEARING ─────────────────────────────────────────────────────────

func clear_neo3_flags_end_of_turn(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_poke: Array = []
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.triggered_poison_active = false
		p.neo3_high_speed_locked = false
		p.submerge_active = false
		# NEO4 per-turn protection flags (last until your next turn ends)
		p.neo4_prevent_high_damage = 0
		p.neo4_prevent_bench_damage = false
		p.neo4_cant_evolve_next_turn = false
		# night_eyes_used intentionally NOT cleared here (persists across turns for Perish Song)
		# legendary_body_active is metadata-based, not per-turn

# ── TRIGGERED POISON (neo3-4 Crobat) ─────────────────────────────────────────

func check_triggered_poison(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null: return
	if pokemon.triggered_poison_active and not pokemon.is_poisoned:
		pokemon.is_poisoned = true
		pokemon.poison_damage = 10
		pokemon.triggered_poison_active = false
		main.update_status_icons(pokemon, is_opponent)
		print("TRIGGERED POISON: ", pokemon.metadata.get("name",""), " poisoned from energy attachment")

# ── TIME TRAVEL (neo3-3 Celebi) ───────────────────────────────────────────────

# Called just before a KO in check_and_handle_knockout.
# If pokemon is Celebi with Time Travel ability: flip — heads = shuffle back into deck instead of KO.
# Returns true if KO was prevented.
func check_time_travel(pokemon: card_object, is_opponent: bool) -> bool:
	if pokemon == null: return false
	var has_tt = false
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Time Travel":
			has_tt = true
			break
	if not has_tt: return false
	if is_power_blocked_by_status(pokemon): return false
	if is_toxic_gas_active() or main.goop_gas_active: return false
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return false
	if not coin:
		await main.show_message("TIME TRAVEL: TAILS — " + pokemon.metadata.get("name","").to_upper() + " IS KNOCKED OUT!")
		if main._should_bail(): return false
		return false
	# Heads: shuffle Celebi + all attached cards into deck
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var all_attached: Array = []
	all_attached.append_array(pokemon.attached_energies)
	all_attached.append_array(pokemon.attached_cards)
	all_attached.append_array(pokemon.attached_pre_evolutions)
	for c in all_attached:
		c.current_location = "deck"
		own_deck.append(c)
	pokemon.attached_energies.clear()
	pokemon.attached_cards.clear()
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.current_location = "deck"
	own_deck.append(pokemon)
	own_deck.shuffle()
	# Remove from active/bench
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active == pokemon:
		if is_opponent:
			main.opponent_active_pokemon = null
		else:
			main.player_active_pokemon = null
	else:
		var own_bench = main.opponent_bench if is_opponent else main.player_bench
		own_bench.erase(pokemon)
	main.update_deck_icon(is_opponent)
	await main.show_message("TIME TRAVEL! HEADS! " + pokemon.metadata.get("name","").to_upper() + " WAS SHUFFLED BACK INTO THE DECK!")
	if main._should_bail(): return true
	print("TIME TRAVEL: ", pokemon.metadata.get("name",""), " avoided KO and shuffled into deck")
	return true

# ── ACTIVE POWERS ─────────────────────────────────────────────────────────────

# SOFTBOILED (neo3-15/16 Chansey): heal 4 damage counters from any of your pokemon; discard 1 energy
func power_neo3_softboiled(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("SOFTBOILED: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	# Must discard 1 energy from Chansey
	if pokemon.attached_energies.is_empty():
		await main.show_message("SOFTBOILED: NO ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	var targets: Array = []
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_active != null: targets.append(own_active)
	targets.append_array(own_bench)
	var heal_targets = targets.filter(func(p): return p.current_hp < p.get_max_hp())
	if heal_targets.is_empty():
		await main.show_message("SOFTBOILED: ALL POKEMON ARE AT FULL HP!")
		if main._should_bail(): return
		return
	# Discard 1 energy from Chansey
	var e_to_discard: card_object = null
	if is_opponent:
		e_to_discard = pokemon.attached_energies[0]
	else:
		if pokemon.attached_energies.size() == 1:
			e_to_discard = pokemon.attached_energies[0]
		else:
			e_to_discard = await main.card_ops.prompt_select_card(pokemon.attached_energies.duplicate(), "SOFTBOILED!", "Choose an energy to discard from Chansey", "DISCARD", false)
			if main._should_bail(): return
			if e_to_discard == null: e_to_discard = pokemon.attached_energies[0]
	main.card_ops.discard_energy_from_pokemon(e_to_discard, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	# Choose target to heal
	var target: card_object = null
	if is_opponent:
		var best_dmg = 0
		for p in heal_targets:
			var dmg = p.get_max_hp() - p.current_hp
			if dmg > best_dmg:
				best_dmg = dmg
				target = p
	else:
		target = await main.card_ops.prompt_select_card(heal_targets, "SOFTBOILED!", "Choose a Pokemon to heal 4 damage counters (40 HP)", "HEAL", false)
		if main._should_bail(): return
		if target == null: target = heal_targets[0]
	if target != null:
		target.current_hp = min(target.get_max_hp(), target.current_hp + 40)
		main.display_hp_circles_above_align(target, is_opponent)
		pokemon.power_used_this_turn = true
		await main.show_message("SOFTBOILED! HEALED 4 DAMAGE COUNTERS FROM " + target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	print("POWER USED: Softboiled — healed ", target.metadata.get("name","") if target != null else "none")

# HOWL (neo3-16 Chansey non-holo): +20 damage on all your attacks this turn
func power_neo3_howl(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("HOWL: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("HOWL: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	# Set a pluspower-like bonus on the attacker (use pluspower_count on the active, or screech_damage_bonus)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active != null:
		own_active.screech_damage_bonus += 20
	pokemon.power_used_this_turn = true
	await main.show_message("HOWL! ALL ATTACKS DO +20 DAMAGE THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Howl — +20 attack bonus")

# ELECTROMAGNETIC POWER (neo3-29 Golbat... wait, that's neo3-28 Ampharos? checking original spec)
# Actually Flaaffy (neo3-28) has "Lightning Burst" body. Let me check:
# The original task specified: Electromagnetic Power is Ampharos (neo3-1).
# Active: Discard 1 Lightning energy to deal 20 to any opponent's pokemon (no W/R)
func power_neo3_electromagnetic_power(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("ELECTROMAGNETIC POWER: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("ELECTROMAGNETIC POWER: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("ELECTROMAGNETIC POWER: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	# Find Lightning energy on this pokemon
	var lightning_e: Array = []
	for e in pokemon.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			lightning_e.append(e)
	if lightning_e.is_empty():
		await main.show_message("ELECTROMAGNETIC POWER: NO LIGHTNING ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	# Discard 1 Lightning
	var e_to_discard = lightning_e[0]
	if not is_opponent and lightning_e.size() > 1:
		e_to_discard = await main.card_ops.prompt_select_card(lightning_e, "ELECTROMAGNETIC POWER!", "Choose a Lightning Energy to discard", "DISCARD", false)
		if main._should_bail(): return
		if e_to_discard == null: e_to_discard = lightning_e[0]
	main.card_ops.discard_energy_from_pokemon(e_to_discard, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	# Choose target (any opponent pokemon)
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var all_opp: Array = []
	if opp_active != null: all_opp.append(opp_active)
	all_opp.append_array(opp_bench)
	if all_opp.is_empty():
		await main.show_message("ELECTROMAGNETIC POWER: NO TARGETS!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		var lowest = 999
		for p in all_opp:
			if p.current_hp < lowest:
				lowest = p.current_hp
				target = p
	else:
		target = await main.card_ops.prompt_select_card(all_opp, "ELECTROMAGNETIC POWER!", "Choose an opponent's Pokemon for 20 damage (no W/R)", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = opp_active
	if target != null:
		main.card_ops.apply_damage_to_pokemon(target, 20, not is_opponent)
		main.display_hp_circles_above_align(target, not is_opponent)
		pokemon.power_used_this_turn = true
		await main.show_message("ELECTROMAGNETIC POWER! 20 DAMAGE TO " + target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	print("POWER USED: Electromagnetic Power — 20 to chosen target")

# ENERGY CONVERTER (neo3-12 Porygon2): once per turn, discard 3 energy from hand, attach 1 of any type to Porygon2
func power_neo3_energy_converter(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("ENERGY CONVERTER: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("ENERGY CONVERTER: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("ENERGY CONVERTER: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_hand = main.opponent_hand if is_opponent else main.player_hand
	var own_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var energies_in_hand: Array = []
	for c in own_hand:
		if c.metadata.get("supertype","") == "Energy":
			energies_in_hand.append(c)
	if energies_in_hand.size() < 3:
		await main.show_message("ENERGY CONVERTER: NEED 3 ENERGY IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	# Discard 3 energy from hand
	var to_discard: Array = []
	if is_opponent:
		to_discard = energies_in_hand.slice(0, 3)
	else:
		to_discard = energies_in_hand.slice(0, 3)  # Simplified: first 3
	for e in to_discard:
		own_hand.erase(e)
		e.current_location = "discard"
		own_discard.append(e)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	# Search deck for any basic energy and attach to Porygon2
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var basic_energies_in_deck: Array = []
	for c in own_deck:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basic_energies_in_deck.append(c)
	if basic_energies_in_deck.is_empty():
		await main.show_message("ENERGY CONVERTER: NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		pokemon.power_used_this_turn = true
		return
	var chosen_energy: card_object = null
	if is_opponent:
		chosen_energy = basic_energies_in_deck[0]
	else:
		chosen_energy = await main.card_ops.prompt_select_card(basic_energies_in_deck, "ENERGY CONVERTER!", "Choose a Basic Energy from your deck to attach to Porygon2", "ATTACH", false)
		if main._should_bail(): return
		if chosen_energy == null: chosen_energy = basic_energies_in_deck[0]
	own_deck.erase(chosen_energy)
	chosen_energy.current_location = "active"
	pokemon.attached_energies.append(chosen_energy)
	own_deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	pokemon.power_used_this_turn = true
	await main.show_message("ENERGY CONVERTER! DISCARDED 3 ENERGY, ATTACHED " + chosen_energy.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Energy Converter — attached ", chosen_energy.metadata.get("name",""))

# SUBMERGE (neo3-32 Lanturn): type is Water this turn (prevents effects against Water); set flag
func power_neo3_submerge(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("SUBMERGE: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("SUBMERGE: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SUBMERGE: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.submerge_active = true
	pokemon.temporary_type = "Water"
	pokemon.power_used_this_turn = true
	await main.show_message("SUBMERGE! " + pokemon.metadata.get("name","").to_upper() + " IS NOW A WATER TYPE — EFFECTS CAN'T BE USED ON IT THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Submerge — Lanturn becomes Water type")

# [BEAR] (neo3-? Unown [B]): once per turn, search deck for 1 Trainer card and put in hand
func power_neo3_unown_bear(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("[BEAR]: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[BEAR]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Trainer", "[BEAR]! CHOOSE A TRAINER CARD", 1)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	main.refresh_hand_display(is_opponent)
	await main.show_message("[BEAR]! TRAINER CARD RETRIEVED!")
	if main._should_bail(): return
	print("POWER USED: [Bear] — trainer retrieved from deck")

# [YIELD] (neo3-? Unown [Y]): once per turn, search deck for 1 Basic Pokemon and put in hand
func power_neo3_unown_yield(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("[YIELD]: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[YIELD]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]), "[YIELD]! CHOOSE A BASIC POKEMON", 1)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	main.refresh_hand_display(is_opponent)
	await main.show_message("[YIELD]! BASIC POKEMON RETRIEVED!")
	if main._should_bail(): return
	print("POWER USED: [Yield] — basic pokemon retrieved from deck")

# ── CPU PHASE ─────────────────────────────────────────────────────────────────

func cpu_phase_neo3_powers() -> void:
	if is_toxic_gas_active(): return
	# Electromagnetic Power (Ampharos): use if there's a Lightning energy attached and a low-HP target
	var ampharos = _find_cpu_pokemon_with_power("Electromagnetic Power")
	if ampharos != null and not ampharos.power_used_this_turn and not is_power_blocked_by_status(ampharos):
		var has_lightning = false
		for e in ampharos.attached_energies:
			if "Lightning" in main.get_energy_provided_by_card(e):
				has_lightning = true
				break
		if has_lightning:
			var opp_active = main.player_active_pokemon
			if opp_active != null and opp_active.current_hp <= 30:
				await power_neo3_electromagnetic_power(ampharos)
				if main._should_bail(): return
	# Softboiled (Chansey): use if any pokemon has damage
	var chansey = _find_cpu_pokemon_with_power("Softboiled")
	if chansey != null and not chansey.power_used_this_turn and not is_power_blocked_by_status(chansey):
		if not chansey.attached_energies.is_empty():
			var has_damage = false
			var all_cpu = ([main.opponent_active_pokemon] if main.opponent_active_pokemon != null else []) + main.opponent_bench
			for p in all_cpu:
				if p.current_hp < p.get_max_hp():
					has_damage = true
					break
			if has_damage:
				await power_neo3_softboiled(chansey)
				if main._should_bail(): return
	# Energy Converter (Porygon2): use if deck is big enough
	var porygon2 = _find_cpu_pokemon_with_power("Energy Converter")
	if porygon2 != null and not porygon2.power_used_this_turn and not is_power_blocked_by_status(porygon2):
		var energy_in_hand = main.opponent_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy").size()
		if energy_in_hand >= 3:
			await power_neo3_energy_converter(porygon2)
			if main._should_bail(): return
	# [Bear] Unown: always search for a trainer
	var unown_bear = _find_cpu_pokemon_with_power("[Bear]")
	if unown_bear != null and not unown_bear.power_used_this_turn and not is_power_blocked_by_status(unown_bear):
		await power_neo3_unown_bear(unown_bear)
		if main._should_bail(): return
	# [Yield] Unown: search for a basic if bench not full
	var unown_yield = _find_cpu_pokemon_with_power("[Yield]")
	if unown_yield != null and not unown_yield.power_used_this_turn and not is_power_blocked_by_status(unown_yield):
		if main.opponent_bench.size() < main.get_max_bench_size():
			await power_neo3_unown_yield(unown_yield)
			if main._should_bail(): return

######################################################################################################################################################
############################################################## NEO4 (NEO DESTINY) POWERS ############################################################
######################################################################################################################################################

func _register_neo4_powers() -> void:
	# Active powers
	_power_dispatch["Spatial Distortion"] = func(p): await power_neo4_spatial_distortion(p)
	_power_dispatch["Cunning"]            = func(p): await power_neo4_cunning(p)
	_power_dispatch["Drive Off"]          = func(p): await power_neo4_drive_off(p)
	_power_dispatch["[Give]"]             = func(p): await power_neo4_give(p)
	_power_dispatch["[Want]"]             = func(p): await power_neo4_want(p)
	_power_dispatch["[Help]"]             = func(p): await power_neo4_help(p)
	_power_dispatch["[Quicken]"]          = func(p): await power_neo4_quicken(p)
	_power_dispatch["[Laugh]"]            = func(p): await power_neo4_laugh(p)
	_power_dispatch["[Search]"]           = func(p): await power_neo4_search(p)
	_power_dispatch["[Tell]"]             = func(p): await power_neo4_tell(p)
	# Stadium per-turn activatable entries
	_power_dispatch["Radio Tower"]        = func(p): await main.trainer_effects.neo4_radio_tower_activate(false)
	_power_dispatch["Energy Stadium"]     = func(p): await main.trainer_effects.neo4_energy_stadium_activate(false)

# Helper: standard once-per-turn power preamble. Returns false if the power can't be used.
func _neo4_power_ready(pokemon: card_object, label: String) -> bool:
	if is_power_blocked(pokemon):
		await main.show_message(label + ": BLOCKED!")
		return false
	if pokemon.power_used_this_turn:
		await main.show_message(label + ": ALREADY USED THIS TURN!")
		return false
	return true

# SPATIAL DISTORTION (neo4-8 Dark Porygon2): flip heads, put a Stadium from discard into play
func power_neo4_spatial_distortion(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "SPATIAL DISTORTION"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("SPATIAL DISTORTION: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var stadiums: Array = []
	for c in discard:
		if main.trainer_effects.is_stadium_trainer(c):
			stadiums.append(c)
	if stadiums.is_empty():
		await main.show_message("SPATIAL DISTORTION: NO STADIUM IN DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = stadiums[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(stadiums, "SPATIAL DISTORTION!", "Choose a Stadium from your discard to put into play", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = stadiums[0]
	discard.erase(chosen)
	await main.trainer_effects.resolve_stadium_trainer(chosen, is_opponent)
	if main._should_bail(): return
	await main.show_message("SPATIAL DISTORTION! HEADS! " + chosen.metadata.get("name","").to_upper() + " IS IN PLAY!")
	if main._should_bail(): return
	print("POWER USED: Spatial Distortion")

# CUNNING (neo4-20 Dark Slowking): flip heads, look at top of opp deck; may shuffle opp deck
func power_neo4_cunning(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "CUNNING"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("CUNNING: TAILS!")
		if main._should_bail(): return
		return
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_deck.is_empty():
		await main.show_message("CUNNING: OPPONENT'S DECK IS EMPTY!")
		if main._should_bail(): return
		return
	await main.show_message("CUNNING! TOP OF OPPONENT'S DECK: " + opp_deck[0].metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	if not is_opponent:
		opp_deck.shuffle()
		main.update_deck_icon(not is_opponent)
		await main.show_message("CUNNING! OPPONENT'S DECK WAS SHUFFLED!")
	if main._should_bail(): return
	print("POWER USED: Cunning")

# DRIVE OFF (neo4-12 Light Arcanine): while Active, opp chooses a benched and switches with Defending
func power_neo4_drive_off(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if pokemon != own_active:
		await main.show_message("DRIVE OFF: ONLY WORKS WHILE ACTIVE!")
		if main._should_bail(): return
		return
	if not await _neo4_power_ready(pokemon, "DRIVE OFF"): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.show_message("DRIVE OFF: OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	await main.attack_effects.apply_force_switch({"chooser": "defender"}, is_opponent)
	if main._should_bail(): return
	await main.show_message("DRIVE OFF! OPPONENT SWITCHED THEIR ACTIVE POKEMON!")
	if main._should_bail(): return
	print("POWER USED: Drive Off")

# [GIVE] (neo4-27 Unown [G]): flip heads, search deck for a basic Energy and attach to 1 of your Pokemon
func power_neo4_give(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[GIVE]"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("[GIVE]: TAILS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var basic_e: card_object = null
	for c in deck:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basic_e = c
			break
	if basic_e == null:
		await main.show_message("[GIVE]: NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		return
	var targets = main.attack_effects._neo4_opp_targets(not is_opponent)  # own side
	if targets.is_empty():
		return
	var target: card_object = targets[0]
	if not is_opponent:
		target = await main.card_ops.prompt_select_card(targets, "[GIVE]!", "Choose a Pokemon to attach a basic Energy to", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = targets[0]
	deck.erase(basic_e)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	basic_e.current_location = "active" if target == own_active else "bench"
	target.attached_energies.append(basic_e)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("[GIVE]! HEADS! ENERGY ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Give]")

# [WANT] (neo4-29 Unown [W]): flip heads, put a Trainer from discard into hand
func power_neo4_want(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[WANT]"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("[WANT]: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var trainers: Array = []
	for c in discard:
		if c.metadata.get("supertype","") == "Trainer":
			trainers.append(c)
	if trainers.is_empty():
		await main.show_message("[WANT]: NO TRAINER IN DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = trainers[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(trainers, "[WANT]!", "Choose a Trainer from your discard", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = trainers[0]
	discard.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("[WANT]! HEADS! " + chosen.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Want]")

# [HELP] (neo4-28 Unown [H]): shuffle hand into deck, draw a new hand of same size
func power_neo4_help(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[HELP]"): return
	pokemon.power_used_this_turn = true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var n = hand.size()
	for c in hand.duplicate():
		c.current_location = "deck"
		deck.append(c)
	hand.clear()
	deck.shuffle()
	await main.card_ops.draw_n(is_opponent, n)
	if main._should_bail(): return
	main.update_deck_icon(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("[HELP]! SHUFFLED HAND AND DREW " + str(n) + " NEW CARDS!")
	if main._should_bail(): return
	print("POWER USED: [Help]")

# [QUICKEN] (neo4-59 Unown [Q]): flip heads, prevent all effects to your Unown next turn (invincible)
func power_neo4_quicken(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	# usable even if statused — only check toxic gas / disable
	if is_toxic_gas_active() or main.goop_gas_active or pokemon.power_disabled_until_end_of_next_turn:
		await main.show_message("[QUICKEN]: BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[QUICKEN]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[QUICKEN]: TAILS!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if own_active != null: all_own.append(own_active)
	all_own.append_array(own_bench)
	for p in all_own:
		if "Unown" in p.metadata.get("name",""):
			p.is_invincible = true
			main.update_status_icons(p, is_opponent)
	await main.show_message("[QUICKEN]! HEADS! YOUR UNOWN ARE PROTECTED NEXT TURN!")
	if main._should_bail(): return
	print("POWER USED: [Quicken]")

# [LAUGH] (neo4-86 Unown [L]): flip heads, each player shuffles their deck
func power_neo4_laugh(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_toxic_gas_active() or main.goop_gas_active or pokemon.power_disabled_until_end_of_next_turn:
		await main.show_message("[LAUGH]: BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[LAUGH]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[LAUGH]: TAILS!")
		if main._should_bail(): return
		return
	main.player_deck.shuffle()
	main.opponent_deck.shuffle()
	main.update_deck_icon(false)
	main.update_deck_icon(true)
	await main.show_message("[LAUGH]! HEADS! BOTH DECKS SHUFFLED!")
	if main._should_bail(): return
	print("POWER USED: [Laugh]")

# [SEARCH] (neo4-87 Unown [S]): look at 1 of your Prize cards (flavor)
func power_neo4_search(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if pokemon.power_used_this_turn:
		await main.show_message("[SEARCH]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var prizes = main.opponent_prize_cards if is_opponent else main.player_prize_cards
	if prizes.is_empty():
		await main.show_message("[SEARCH]: NO PRIZE CARDS!")
		if main._should_bail(): return
		return
	await main.show_message("[SEARCH]! YOU PEEKED AT A PRIZE CARD: " + prizes[0].metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Search]")

# [TELL] (neo4-88 Unown [T]): flip heads, look at opp hand and show yours (flavor)
func power_neo4_tell(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if pokemon.power_used_this_turn:
		await main.show_message("[TELL]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[TELL]: TAILS!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	await main.show_message("[TELL]! HEADS! OPPONENT HAS " + str(opp_hand.size()) + " CARDS IN HAND!")
	if main._should_bail(): return
	print("POWER USED: [Tell]")

# ── NEO4 PLAY-FROM-HAND TRIGGERS ──────────────────────────────────────────────

# SURPRISE BITE (neo4-2 Dark Crobat): when played from hand, 20 to a chosen opp Pokemon (no W/R)
func trigger_neo4_surprise_bite(crobat: card_object, is_opponent: bool) -> void:
	if is_power_blocked(crobat):
		return
	var targets = main.attack_effects._neo4_opp_targets(is_opponent)
	if targets.is_empty():
		return
	var target: card_object = targets[0]
	if not is_opponent:
		target = await main.card_ops.prompt_select_card(targets, "SURPRISE BITE!", "Choose an opponent's Pokemon for 20 damage (no W/R)", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = targets[0]
	else:
		var lowest = 999
		for t in targets:
			if t.current_hp < lowest:
				lowest = t.current_hp
				target = t
	main.card_ops.apply_bench_damage(target, 20, not is_opponent)
	main.display_pokemon(not is_opponent)
	await main.show_message("SURPRISE BITE! 20 DAMAGE TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER: Surprise Bite")

# GIFT (neo4-15 Light Togetic): when played, each player may search deck for a Pokemon Tool to hand
func trigger_neo4_gift(togetic: card_object, is_opponent: bool) -> void:
	if is_power_blocked(togetic):
		return
	# Opponent searches first (auto)
	_neo4_search_tool_to_hand(not is_opponent, true)
	# You search
	await _neo4_search_tool_to_hand(is_opponent, is_opponent)
	if main._should_bail(): return
	await main.show_message("GIFT! EACH PLAYER MAY HAVE SEARCHED FOR A POKEMON TOOL!")
	if main._should_bail(): return
	print("POWER: Gift")

func _neo4_search_tool_to_hand(side_is_opponent: bool, auto: bool) -> void:
	var deck = main.opponent_deck if side_is_opponent else main.player_deck
	var hand = main.opponent_hand if side_is_opponent else main.player_hand
	var tools: Array = []
	for c in deck:
		if c.metadata.get("supertype","") == "Trainer" and "Pokémon Tool" in c.metadata.get("subtypes",[]):
			tools.append(c)
	if tools.is_empty():
		return
	var chosen: card_object = tools[0]
	if not auto:
		chosen = await main.card_ops.prompt_select_card(tools, "GIFT!", "Choose a Pokemon Tool from your deck", "SELECT", false)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.update_deck_icon(side_is_opponent)
	main.refresh_hand_display(side_is_opponent)

# TAG TEAM (neo4-25 Light Machamp): when played on bench, heal Active 30 and switch Machamp to Active
func trigger_neo4_tag_team(machamp: card_object, is_opponent: bool) -> void:
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if machamp not in own_bench:
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != null:
		var heal = min(30, active.get_max_hp() - active.current_hp)
		active.current_hp += heal
		main.display_hp_circles_above_align(active, is_opponent)
		active.current_location = "bench"
		own_bench.append(active)
	own_bench.erase(machamp)
	machamp.current_location = "active"
	if is_opponent:
		main.opponent_active_pokemon = machamp
	else:
		main.player_active_pokemon = machamp
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("TAG TEAM! " + machamp.metadata.get("name","").to_upper() + " SWITCHED IN, ACTIVE HEALED!")
	if main._should_bail(): return
	print("POWER: Tag Team")

# [VANISH] (neo4-89 Unown [V]): when played from hand, flip heads return another Unown to hand (discard attachments)
func trigger_neo4_vanish(unown_v: card_object, is_opponent: bool) -> void:
	if is_power_blocked(unown_v):
		return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[VANISH]: TAILS!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var unowns: Array = []
	if own_active != null and own_active != unown_v and "Unown" in own_active.metadata.get("name",""):
		unowns.append(own_active)
	for bp in own_bench:
		if bp != unown_v and "Unown" in bp.metadata.get("name",""):
			unowns.append(bp)
	if unowns.is_empty():
		await main.show_message("[VANISH]: NO OTHER UNOWN TO RETURN!")
		if main._should_bail(): return
		return
	var chosen: card_object = unowns[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(unowns, "[VANISH]!", "Choose an Unown to return to your hand", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = unowns[0]
	# Discard attachments, return the Unown to hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for c in chosen.attached_energies + chosen.attached_cards + chosen.attached_pre_evolutions:
		c.current_location = "discard"
		discard.append(c)
	chosen.attached_energies.clear()
	chosen.attached_cards.clear()
	chosen.attached_pre_evolutions.clear()
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if own_active == chosen:
		if is_opponent: main.opponent_active_pokemon = null
		else: main.player_active_pokemon = null
	else:
		own_bench.erase(chosen)
	chosen.current_hp = chosen.get_max_hp()
	chosen.current_location = "hand"
	hand.append(chosen)
	main.display_pokemon(is_opponent)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("[VANISH]! HEADS! " + chosen.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER: [Vanish]")

# ── NEO4 PASSIVE HOOKS ────────────────────────────────────────────────────────

# CONDUCTIVITY (neo4-1 Dark Ampharos): when opponent attaches Energy to a Pokemon, 10 to that Pokemon (no W/R)
# Called from energy-attachment sites. `target` received energy; `target_is_opponent` = target's side.
func check_neo4_conductivity(target: card_object, target_is_opponent: bool) -> void:
	if target == null: return
	# Dark Ampharos belongs to the side opposing the attacher (= opposing the target's owner)
	var amp_active = main.player_active_pokemon if target_is_opponent else main.opponent_active_pokemon
	var amp_bench = main.player_bench if target_is_opponent else main.opponent_bench
	var amphs: Array = []
	if amp_active != null and amp_active.has_ability("Conductivity"): amphs.append(amp_active)
	for bp in amp_bench:
		if bp.has_ability("Conductivity"): amphs.append(bp)
	if amphs.size() != 1:
		return  # stops working with more than 1 Dark Ampharos
	var amp = amphs[0]
	if is_power_blocked_by_status(amp) or is_toxic_gas_active() or main.goop_gas_active:
		return
	main.card_ops.apply_bench_damage(target, 10, target_is_opponent)
	main.display_pokemon(target_is_opponent)
	print("CONDUCTIVITY: 10 damage to ", target.metadata.get("name",""))

# HOT PLATE (neo4-18 Dark Magcargo): when a Basic/Baby is benched from hand, active Magcargo deals 10 to it
func check_neo4_hot_plate(benched: card_object, benched_is_opponent: bool) -> void:
	if benched == null: return
	for side_opp in [false, true]:
		var active = main.opponent_active_pokemon if side_opp else main.player_active_pokemon
		if active != null and active.has_ability("Hot Plate"):
			if not is_power_blocked_by_status(active) and not is_toxic_gas_active() and not main.goop_gas_active:
				main.card_ops.apply_bench_damage(benched, 10, benched_is_opponent)
				main.display_pokemon(benched_is_opponent)
				print("HOT PLATE: 10 damage to benched ", benched.metadata.get("name",""))
				return

# FLUFFY WOOL (neo4-26 Light Piloswine): if Active Piloswine damaged by attack, flip heads attacker Asleep
func check_neo4_fluffy_wool(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if defender == null or attacker == null: return
	if not defender.has_ability("Fluffy Wool"): return
	var own_active = main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon
	if defender != own_active: return
	if defender.is_status_blocked(): return
	var coin = await main.flip_coin(false, is_def_opp)
	if main._should_bail(): return
	if coin:
		main.card_ops.apply_status(attacker, "Asleep", not is_def_opp)
		await main.show_message("FLUFFY WOOL! " + attacker.metadata.get("name","").to_upper() + " FELL ASLEEP!")
		if main._should_bail(): return

# REFLECT SHIELD / COUNTERATTACK CLAWS: if Active was damaged, flip → 20/2-counters to attacker
func check_neo4_counters(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if defender == null or attacker == null: return
	# Reflect Shield (Shining Mewtwo)
	if defender.neo4_counter_flip_20:
		defender.neo4_counter_flip_20 = false
		var coin = await main.flip_coin(false, is_def_opp)
		if main._should_bail(): return
		if coin:
			main.card_ops.apply_bench_damage(attacker, 20, not is_def_opp)
			main.display_pokemon(not is_def_opp)
			await main.show_message("REFLECT SHIELD! 20 DAMAGE TO " + attacker.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
	# Counterattack Claws (neo4-97 Tool)
	var has_claws = false
	for ac in defender.attached_cards:
		if ac.uid.to_lower() == "neo4-97":
			has_claws = true
			break
	if has_claws:
		var own_active = main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon
		if defender == own_active:
			var coin2 = await main.flip_coin(false, is_def_opp)
			if main._should_bail(): return
			if coin2:
				main.card_ops.apply_bench_damage(attacker, 20, not is_def_opp)
				main.display_pokemon(not is_def_opp)
				await main.show_message("COUNTERATTACK CLAWS! 20 DAMAGE TO " + attacker.metadata.get("name","").to_upper() + "!")
			# Discard the claws
			for ac in defender.attached_cards.duplicate():
				if ac.uid.to_lower() == "neo4-97":
					defender.attached_cards.erase(ac)
					var discard = main.opponent_discard_pile if is_def_opp else main.player_discard_pile
					ac.current_location = "discard"
					discard.append(ac)
			main.trainer_effects.display_attached_trainer_cards(is_def_opp)
			main.update_discard_pile_display(is_def_opp)
			if main._should_bail(): return

# CPU activation of neo4 stadium effects (called from cpu_phase_activate_powers)
func cpu_phase_neo4_powers() -> void:
	if main.trainer_effects.neo4_lucky_stadium_active():
		await main.trainer_effects.neo4_lucky_stadium_activate(true)
		if main._should_bail(): return
	if main.trainer_effects.neo4_energy_stadium_active():
		await main.trainer_effects.neo4_energy_stadium_activate(true)
		if main._should_bail(): return
	if main.trainer_effects.neo4_radio_tower_active():
		await main.trainer_effects.neo4_radio_tower_activate(true)
		if main._should_bail(): return
