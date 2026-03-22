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
	
	for pokemon in all_pokemon:
		var abilities = pokemon.metadata.get("abilities", [])
		for ability in abilities:
			var ability_type = ability.get("type", "")
			if ability_type != "Pokémon Power" and ability_type != "Pokemon Power":
				continue
			var ability_name = ability.get("name", "")
			# Skip passive powers (they don't go in menu)
			if ability_name in ["Strikes Back", "Energy Burn"]:
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

############################################### Section H: CPU POWER ACTIVATION ######################################################################

# CPU activates beneficial powers at start of turn

func cpu_phase_activate_powers() -> void:
	# Rain Dance: attach all Water Energy to Water Pokemon
	var blastoise = _find_cpu_pokemon_with_power("Rain Dance")
	if blastoise != null and not is_power_blocked_by_status(blastoise):
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
	if venusaur != null and not is_power_blocked_by_status(venusaur):
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
	
	# Damage Swap: move damage off active to bench with most buffer
	var alakazam = _find_cpu_pokemon_with_power("Damage Swap")
	if alakazam != null and not is_power_blocked_by_status(alakazam):
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

# Helper to find a CPU pokemon with a specific power name

func _find_cpu_pokemon_with_power(power_name: String) -> card_object:
	var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
	for p in all_pokemon:
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
