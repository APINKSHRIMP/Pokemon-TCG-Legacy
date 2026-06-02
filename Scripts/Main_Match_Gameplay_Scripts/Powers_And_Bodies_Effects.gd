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
		active.power_used_this_turn = false
	for bp in bench:
		bp.power_used_this_turn = false
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
			if ability_name in ["Strikes Back", "Energy Burn", "Invisible Wall", "Thick Skinned", "Retreat Aid", "Prehistoric Power", "Toxic Gas", "Transparency", "Kabuto Armor", "Clairvoyance", "Transform", "Sinkhole", "Hay Fever", "Sticky Goo", "Frenzy", "Final Beam", "Sneak Attack", "Summon Minions", "Reel In", "Bench Guard", "Pollen Defense", "Flee", "Rebirth", "Shell Armor", "Restless Sleep", "Strange Barrier", "Photosynthesis", "Fortitude", "Call the Boss", "Rebellion", "Psylink", "Healing Fire", "Energy Drain", "Scram", "Relaxing Scent", "Shock Blast", "Gaseous Form"]:
				continue
			# Toxic Gas blocks all other powers
			if toxic_gas_active:
				continue
			# Dark Arbok Stare: power disabled temporarily
			if pokemon.power_disabled_until_end_of_next_turn:
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
	var ability_name = ability.get("name", "")

	match ability_name:
		"Damage Swap": await power_damage_swap(pokemon)
		"Rain Dance": await power_rain_dance(pokemon)
		"Energy Trans": await power_energy_trans(pokemon)
		"Buzzap": await power_buzzap(pokemon)
		"Discard": await power_bench_token_discard(pokemon)
		"Shift": await power_shift(pokemon)
		"Heal": await power_heal_vileplume(pokemon)
		"Peek": await power_peek(pokemon)
		"Step In": await power_step_in(pokemon)
		"Curse": await power_curse(pokemon)
		"Strange Behavior": await power_strange_behavior(pokemon)
		"Cowardice": await power_cowardice(pokemon)
		"Evolutionary Light": await power_evolutionary_light(pokemon)
		"Pollen Stench": await power_pollen_stench(pokemon)
		"Matter Exchange": await power_matter_exchange(pokemon)
		"Gather Fire": await power_gather_fire(pokemon)
		"Long-Distance Hypnosis": await power_long_distance_hypnosis(pokemon)
		"Trickery": await power_trickery(pokemon)
		"Celadon City Gym": await main.trainer_effects.gym1_celadon_activate(false)
		"Fuchsia City Gym": await main.trainer_effects.gym2_fuchsia_activate(false)
		"Saffron City Gym": await main.trainer_effects.gym2_saffron_activate(false)
		"Energy Charge": await power_energy_charge(pokemon)
		"Fragrance Trap": await power_fragrance_trap(pokemon)
		"Natural Healing": await power_natural_healing(pokemon)
		"Shapeshift": await power_shapeshift(pokemon)
		"Discard Form": await power_shapeshift_discard(pokemon)
		"Soak Up": await power_soak_up(pokemon)
		"Emerge": await power_emerge(pokemon)
		_: await main.show_message("Power not implemented: " + ability_name)

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
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(sources)
		main.header_label.text = "DAMAGE SWAP - SOURCE"
		main.hint_label.text = "Select a Pokemon to take damage FROM (or cancel to stop)"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		var source = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
		if source == null:
			break
		
		# Select destination (pokemon that can take 1 more without KO)
		var destinations = []
		for p in all_pokemon:
			if p == source: continue
			if p.current_hp > 10: # Can take 10 damage without KO
				destinations.append(p)
		
		if destinations.size() == 0:
			await main.show_message("No Pokemon can receive the damage counter!")
			if main._should_bail(): return
			break
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(destinations)
		main.header_label.text = "DAMAGE SWAP - DESTINATION"
		main.hint_label.text = "Select a Pokemon to move damage TO"
		main.action_button.text = "MOVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		var dest = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(water_pokemon)
		main.header_label.text = "RAIN DANCE"
		main.hint_label.text = "Select a Water Pokemon to attach energy to (cancel to stop)"
		main.action_button.text = "ATTACH"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		var target = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(sources)
		main.header_label.text = "ENERGY TRANS - SOURCE"
		main.hint_label.text = "Select Pokemon to take Grass Energy from (cancel to stop)"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		var source = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(destinations)
		main.header_label.text = "ENERGY TRANS - DESTINATION"
		main.hint_label.text = "Select Pokemon to move Grass Energy to"
		main.action_button.text = "MOVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		var dest = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
	
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(targets)
	main.header_label.text = "BUZZAP - ATTACH TO"
	main.hint_label.text = "Select a Pokemon to attach Electrode-Energy to"
	main.action_button.text = "ATTACH"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = false
	await main.trainer_target_selected
	if main._should_bail(): return
	var target = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
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
	
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(damaged)
	main.header_label.text = "HEAL: CHOOSE POKEMON"
	main.hint_label.text = "Select a Pokemon to remove 1 damage counter from"
	main.action_button.text = "HEAL"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = false
	await main.trainer_target_selected
	if main._should_bail(): return
	var target = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
	if target != null:
		target.current_hp = min(int(target.metadata.get("hp", "0")), target.current_hp + 10)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(target, false)
		await main.show_message("HEALED 10 HP FROM " + target.metadata.get("name", "").to_upper() + "!")
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
	main.opponent_blocker.visible = false
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(sources)
	main.cancel_button.visible = true
	main.header_label.text = "CURSE: SELECT SOURCE"
	main.hint_label.text = "Remove 1 damage counter from this Pokemon"
	main.action_button.text = "SELECT"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	await main.trainer_target_selected
	if main._should_bail(): return
	var source = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	main.opponent_blocker.visible = true
	
	if source == null:
		return
	
	# Select destination (move damage TO) — can KO
	var destinations: Array = []
	for p in opponent_pokemon:
		if p != source:
			destinations.append(p)
	
	if destinations.size() == 0:
		return
	
	main.opponent_blocker.visible = false
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(destinations)
	main.cancel_button.visible = true
	main.header_label.text = "CURSE: SELECT TARGET"
	main.hint_label.text = "Move the damage counter TO this Pokemon (can KO)"
	main.action_button.text = "CURSE"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	await main.trainer_target_selected
	if main._should_bail(): return
	var dest = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	main.opponent_blocker.visible = true
	
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
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(sources)
		main.cancel_button.visible = true
		main.header_label.text = "STRANGE BEHAVIOR"
		main.hint_label.text = "Move 1 damage counter TO Slowbro from this Pokemon (cancel to stop)"
		main.action_button.text = "MOVE DAMAGE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		var source = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		if not saffron_used:
			break
	
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
				
				var is_active = (tentacool == main.opponent_active_pokemon)
				if is_active:
					main.opponent_active_pokemon = null
				else:
					main.opponent_bench.erase(tentacool)
				tentacool.current_location = "hand"
				main.opponent_hand.append(tentacool)
				main.clear_all_statuses(tentacool, true)
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
					main.player_active_pokemon.special_condition = "Confused"
					main.update_status_icons(main.player_active_pokemon, false)
					await main.show_message("Pollen Stench: Defending Pokemon is Confused!")
					if main._should_bail(): return
				else:
					# Tails: own active confused
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						cpu_active.special_condition = "Confused"
						main.update_status_icons(cpu_active, true)
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
					main.player_active_pokemon.special_condition = "Asleep"
					main.update_status_icons(main.player_active_pokemon, false)
					await main.show_message("Long-Distance Hypnosis: Defending Pokemon is Asleep!")
					if main._should_bail(): return
				else:
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						cpu_active.special_condition = "Asleep"
						main.update_status_icons(cpu_active, true)
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(all_targets)
		main.header_label.text = "CHOOSE POKÉMON FOR SNEAK ATTACK"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(remaining_basics)
			main.header_label.text = "CHOOSE BASIC " + str(i + 1) + "/" + str(picks_remaining)
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			await main.trainer_target_selected
			if main._should_bail(): return
			pick = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
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
			
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(remaining)
			main.header_label.text = "CHOOSE CARD " + str(i + 1) + "/" + str(max_picks)
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			await main.trainer_target_selected
			if main._should_bail(): return
			var pick = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
			
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
	
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(evolutions)
	main.header_label.text = "CHOOSE AN EVOLUTION CARD"
	main.action_button.text = "SELECT"
	main.action_button.disabled = true
	await main.trainer_target_selected
	if main._should_bail(): return
	var selected = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
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
			defender.special_condition = "Confused"
			main.update_status_icons(defender, true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			active.special_condition = "Confused"
			main.update_status_icons(active, false)
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
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(main.player_hand)
	main.header_label.text = "CHOOSE A CARD TO DISCARD"
	main.action_button.text = "DISCARD"
	main.action_button.disabled = true
	await main.trainer_target_selected
	if main._should_bail(): return
	var selected = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
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
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(sources)
	main.header_label.text = "CHOOSE POKÉMON TO TAKE FIRE ENERGY FROM"
	main.action_button.text = "SELECT"
	main.action_button.disabled = true
	await main.trainer_target_selected
	if main._should_bail(): return
	var source = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
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
			defender.special_condition = "Asleep"
			main.update_status_icons(defender, true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			active.special_condition = "Asleep"
			main.update_status_icons(active, false)
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
	main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(main.player_prize_cards)
	main.header_label.text = "CHOOSE A PRIZE CARD TO SWAP"
	main.action_button.text = "SWAP"
	main.action_button.disabled = true
	await main.trainer_target_selected
	if main._should_bail(): return
	var selected_prize = main.selected_card_for_action
	main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	
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
	attacker.special_condition = "Confused"
	main.update_status_icons(attacker, not is_damaged_opp)
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
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(sources)
			main.header_label.text = "ENERGY CHARGE"
			main.hint_label.text = "Choose a Pokemon to take Lightning Energy from"
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = true
			await main.trainer_target_selected
			if main._should_bail(): return
			source = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
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
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(bench)
			main.header_label.text = "FLEE"
			main.hint_label.text = "Choose a bench Pokemon to switch to"
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = false
			await main.trainer_target_selected
			if main._should_bail(): return false
			replacement = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
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
	pokemon.current_hp = int(pokemon.metadata.get("hp", "0"))
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(opp_bench)
		main.header_label.text = "FRAGRANCE TRAP"
		main.hint_label.text = "Choose an opponent bench Pokemon to bring up"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		target = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
	vulpix.power_used_this_turn = true
	var is_opp: bool = (vulpix == main.opponent_active_pokemon or vulpix in main.opponent_bench)
	vulpix.current_hp = min(max_hp, vulpix.current_hp + 10)
	main.display_hp_circles_above_align(vulpix, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("NATURAL HEALING: " + vulpix.metadata.get("name", "").to_upper() + " HEALED 10 HP!")
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
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(evolutions)
			main.header_label.text = "SHAPESHIFT"
			main.hint_label.text = "Choose an Evolution card to attach as a form"
			main.action_button.text = "SELECT"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = true
			await main.trainer_target_selected
			if main._should_bail(): return
			chosen = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(giovanni_cards)
		main.header_label.text = "CALL THE BOSS"
		main.hint_label.text = "Choose a Giovanni card to take"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = true
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
	attacker.current_hp = int(attacker.metadata.get("hp", "0"))
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
	pokemon.current_hp = min(max_hp, pokemon.current_hp + 10)
	main.display_hp_circles_above_align(pokemon, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("HEALING FIRE: " + pokemon.metadata.get("name", "").to_upper() + " HEALED 10 HP!")
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(attacker.attached_energies)
		main.header_label.text = "ENERGY DRAIN"
		main.hint_label.text = "Choose 1 energy on the attacker to discard"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen_energy = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
	pokemon.current_hp = int(pokemon.metadata.get("hp", "0"))
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
				main.trainer_pokemon_selection_active = true
				main.show_enlarged_array_selection_mode(sources)
				main.header_label.text = "SOAK UP (" + str(moved_count) + "/2)"
				main.hint_label.text = "Choose a Pokemon to take Grass Energy from (or cancel to stop)"
				main.action_button.text = "SELECT"
				main.action_button.disabled = true
				main.action_button.theme = main.theme_disabled
				main.cancel_button.visible = true
				await main.trainer_target_selected
				if main._should_bail(): return
				source = main.selected_card_for_action
				main.trainer_pokemon_selection_active = false
				main.hide_selection_mode_display_main()
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
	beedrill.current_hp = int(beedrill.metadata.get("hp", "0"))
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
