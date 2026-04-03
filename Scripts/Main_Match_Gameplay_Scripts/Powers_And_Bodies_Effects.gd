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
	if pokemon.special_condition in ["Paralyzed", "Asleep", "Confused"]:
		return true
	if pokemon.is_poisoned:
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
			if ability_name in ["Strikes Back", "Energy Burn", "Invisible Wall", "Thick Skinned", "Retreat Aid", "Prehistoric Power", "Toxic Gas", "Transparency", "Kabuto Armor", "Clairvoyance", "Transform"]:
				continue
			# Toxic Gas blocks all other powers
			if toxic_gas_active:
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
	var coin = await main.flip_coin()
	
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
		var coin = await main.flip_coin()
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
			# Flip coin
			var coin = await main.flip_coin()
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
