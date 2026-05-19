extends Node

######################################################################################################################################################
############################################################## TRAINER EFFECTS #####################################################################
######################################################################################################################################################
#
# This file contains trainer card effects, Pokémon Powers, and related helpers.
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

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

# Returns true if a card is an attached trainer (PlusPower, Defender)
func is_attached_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	var card_name = card.metadata.get("name", "").to_lower()
	return card_name in ["pluspower", "defender"]

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

# Plays a healing animation: restores red HP circles to green with delay, shows floating +HP label
func play_heal_animation(pokemon: card_object, heal_amount: int, is_opponent: bool) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	if heal_amount <= 0:
		return
	var loc = main.get_pokemon_screen_location(pokemon)
	if not loc.is_empty():
		main.show_floating_label("+" + str(heal_amount) + " HP", loc["position"] + Vector2(0, -20), Color.GREEN, true)
	
	# Animate HP circles restoring one by one with delay
	var circles_to_restore = heal_amount / 10
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var display_pokemon_ref = pokemon if pokemon == active else active
	for i in range(circles_to_restore):
		# Temporarily set HP partway through the heal for incremental circle display
		var partial_hp = (pokemon.current_hp - heal_amount) + ((i + 1) * 10)
		var saved_hp = pokemon.current_hp
		pokemon.current_hp = min(partial_hp, saved_hp)
		main.display_hp_circles_above_align(display_pokemon_ref if display_pokemon_ref != null else pokemon, is_opponent)
		pokemon.current_hp = saved_hp
		await get_tree().create_timer(0.2).timeout
	main.display_hp_circles_above_align(display_pokemon_ref if display_pokemon_ref != null else pokemon, is_opponent)
	main.display_pokemon(is_opponent)

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
	
	# Check Goop Gas doesn't block trainers (it only blocks powers)
	
	var card_id = card.uid.to_lower()
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	
	match card_id:
		"base1-76": # Pokemon Breeder
			# Check for Stage 2 in hand AND a matching Basic in play
			var stage2_cards = []
			for c in hand:
				if c == card:
					continue
				var subtypes = c.metadata.get("subtypes", [])
				if "Stage 2" in subtypes:
					stage2_cards.append(c)
			if stage2_cards.size() == 0:
				return "No Stage 2 Pokemon in hand to play!"
			# Check if any Stage 2 has a matching Basic on field
			var has_valid_target = false
			var all_in_play = []
			if active != null:
				all_in_play.append(active)
			all_in_play.append_array(bench)
			for s2 in stage2_cards:
				for pokemon in all_in_play:
					if pokemon.placed_on_field_this_turn:
						continue
					if not main.is_basic_pokemon(pokemon):
						continue
					if _basic_matches_stage2(pokemon, s2):
						has_valid_target = true
						break
				if has_valid_target:
					break
			if not has_valid_target:
				return "No valid Basic Pokemon to evolve with Breeder!"
		
		"base1-72": # Devolution Spray
			var has_evolved = false
			if active != null and active.attached_pre_evolutions.size() > 0:
				has_evolved = true
			for bp in bench:
				if bp.attached_pre_evolutions.size() > 0:
					has_evolved = true
					break
			if not has_evolved:
				return "No evolved Pokemon to devolve!"
		
		"base1-94": # Potion
			var damaged = build_field_pokemon_array(is_opponent).filter(func(p): return p.current_hp < int(p.metadata.get("hp", "0")))
			if damaged.size() == 0:
				return "No Pokemon with damage to heal!"
		
		"base1-90": # Super Potion
			var valid_targets = []
			var all_pokemon = build_field_pokemon_array(is_opponent)
			for p in all_pokemon:
				if p.current_hp < int(p.metadata.get("hp", "0")) and p.attached_energies.size() > 0:
					valid_targets.append(p)
			if valid_targets.size() == 0:
				return "No Pokemon with both damage and energy for Super Potion!"
		
		"base1-92": # Energy Removal
			var opp_all = build_field_pokemon_array(not is_opponent)
			var has_energy = false
			for p in opp_all:
				if p.attached_energies.size() > 0:
					has_energy = true
					break
			if not has_energy:
				return "Opponent has no energy to remove!"
		
		"base1-79": # Super Energy Removal
			# Check own pokemon have energy
			var own_all = build_field_pokemon_array(is_opponent)
			var own_has_energy = false
			for p in own_all:
				if p.attached_energies.size() > 0:
					own_has_energy = true
					break
			if not own_has_energy:
				return "You have no energy to discard for Super Energy Removal!"
			# Check opponent pokemon have energy
			var target_all = build_field_pokemon_array(not is_opponent)
			var target_has_energy = false
			for p in target_all:
				if p.attached_energies.size() > 0:
					target_has_energy = true
					break
			if not target_has_energy:
				return "Opponent has no energy to remove!"
		
		"base1-70": # Clefairy Doll
			if bench.size() >= 5:
				return "Bench is full! Cannot place Clefairy Doll!"
		
		"base1-71": # Computer Search
			if hand.size() < 3: # Need at least 2 cards to discard + the computer search itself is already removed
				# hand still contains the card at this point for player validation
				var cards_available = 0
				for c in hand:
					if c != card:
						cards_available += 1
				if cards_available < 2:
					return "Need at least 2 other cards in hand to discard!"
		
		"base1-74": # Item Finder
			var cards_available = 0
			for c in hand:
				if c != card:
					cards_available += 1
			if cards_available < 2:
				return "Need at least 2 other cards in hand to discard!"
			var trainers_in_discard = []
			for c in discard:
				if is_trainer_card(c):
					trainers_in_discard.append(c)
			if trainers_in_discard.size() == 0:
				return "No Trainer cards in the discard pile!"
		
		"base1-81": # Energy Retrieval
			var basic_energies_in_discard = []
			for c in discard:
				if main.is_basic_energy_card(c):
					basic_energies_in_discard.append(c)
			if basic_energies_in_discard.size() == 0:
				return "No Basic Energy in discard pile!"
			var cards_available_er = 0
			for c in hand:
				if c != card:
					cards_available_er += 1
			if cards_available_er < 1:
				return "Need at least 1 other card in hand to discard!"
		
		"base1-83": # Maintenance
			var cards_available_m = 0
			for c in hand:
				if c != card:
					cards_available_m += 1
			if cards_available_m < 2:
				return "Need at least 2 other cards in hand!"
		
		"base1-89": # Revive
			if bench.size() >= 5:
				return "Bench is full!"
			var basics_in_discard = []
			for c in discard:
				if main.is_basic_pokemon(c):
					basics_in_discard.append(c)
			if basics_in_discard.size() == 0:
				return "No Basic Pokemon in discard pile!"
		
		"base1-93": # Gust of Wind
			var opp_bench_gust = main.player_bench if is_opponent else main.opponent_bench
			if opp_bench_gust.size() == 0:
				return "Opponent has no bench Pokemon!"
		
		"base1-95": # Switch
			if bench.size() == 0:
				return "No bench Pokemon to switch with!"
		
		"base1-86": # Pokemon Flute
			var target_bench_flute = main.player_bench if is_opponent else main.opponent_bench
			if target_bench_flute.size() >= 5:
				return "Opponent's bench is full!"
			var target_discard_flute = main.player_discard_pile if is_opponent else main.opponent_discard_pile
			var has_basic = false
			for c in target_discard_flute:
				if main.is_basic_pokemon(c):
					has_basic = true
					break
			if not has_basic:
				return "No Basic Pokemon in opponent's discard pile!"
		
		"base1-82": # Full Heal
			if active == null:
				return "No active Pokemon!"
			if active.special_condition == "" and not active.is_poisoned and not active.is_burned:
				return "Active Pokemon has no conditions to heal!"
		
		"base1-77": # Pokemon Trader
			var pokemon_in_hand = []
			for c in hand:
				if c != card and c.metadata.get("supertype", "").to_lower() == "pokémon":
					pokemon_in_hand.append(c)
			if pokemon_in_hand.size() == 0:
				return "No Pokemon in hand to trade!"
			var pokemon_in_deck = []
			for c in deck:
				if c.metadata.get("supertype", "").to_lower() == "pokémon":
					pokemon_in_deck.append(c)
			if pokemon_in_deck.size() == 0:
				return "No Pokemon in deck to trade for!"
	
		"base5-16", "base5-72": # Rocket's Sneak Attack
			var target = main.player_hand if is_opponent else main.opponent_hand
			var has_trainer = false
			for c in target:
				if c.metadata.get("supertype", "") == "Trainer":
					has_trainer = true
					break
			if not has_trainer:
				return "Opponent has no Trainer cards in hand!"
		
		"base5-73": # The Boss's Way
			var has_dark = false
			for c in deck:
				var name = c.metadata.get("name", "")
				var st = c.metadata.get("subtypes", [])
				if name.begins_with("Dark ") and c.metadata.get("supertype", "") == "Pokémon" and ("Stage 1" in st or "Stage 2" in st):
					has_dark = true
					break
			if not has_dark:
				return "No Dark evolution cards in deck!"
		
		"base5-76": # Imposter Oak's Revenge
			var cards_available_ior = 0
			for c in hand:
				if c != card:
					cards_available_ior += 1
			if cards_available_ior < 1:
				return "Need at least 1 other card in hand to discard!"
		
		"base5-77": # Nightly Garbage Run
			var valid_ngr = false
			for c in discard:
				if c.metadata.get("supertype", "") == "Pokémon" or main.is_basic_energy_card(c):
					valid_ngr = true
					break
			if not valid_ngr:
				return "No valid cards in discard pile!"
	
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
	
	# Step 1: Show trainer card animation
	await show_trainer_card_played_animation(card, is_opponent)
	
	# Step 2: Route to the correct handler based on card type
	if is_bench_token_trainer(card):
		await resolve_bench_token_trainer(card, is_opponent)
	elif is_attached_trainer(card):
		await resolve_attached_trainer(card, is_opponent)
	elif is_stadium_trainer(card):
		# Future-proofing: route to stadium handler
		print("Stadium cards not yet implemented")
		card.current_location = "discard"
		discard.append(card)
	else:
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
	else:
		# Standard trainers animate to the discard pile
		var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
		await main.animate_card_a_to_b(hand_container_node, discard_node, 0.3, card_texture, main.card_scales[10])

############################################### Section D: STANDARD TRAINER CARD EFFECTS ############################################################

# Routes a standard trainer card to its specific effect function
func resolve_standard_trainer(card: card_object, is_opponent: bool) -> void:
	var card_id = card.uid.to_lower()
	var card_name = card.metadata.get("name", "").to_lower()
	
	match card_id:
		"base1-91": await effect_bill(is_opponent)
		"base1-88": await effect_professor_oak(card, is_opponent)
		"base1-71": await effect_computer_search(card, is_opponent)
		"base1-72": await effect_devolution_spray(is_opponent)
		"base1-73": await effect_impostor_professor_oak(is_opponent)
		"base1-74": await effect_item_finder(card, is_opponent)
		"base1-75": await effect_lass(is_opponent)
		"base1-76": await effect_pokemon_breeder(is_opponent)
		"base1-77": await effect_pokemon_trader(card, is_opponent)
		"base1-78": await effect_scoop_up(is_opponent)
		"base1-79": await effect_super_energy_removal(is_opponent)
		"base1-81": await effect_energy_retrieval(card, is_opponent)
		"base1-82": await effect_full_heal(is_opponent)
		"base1-83": await effect_maintenance(card, is_opponent)
		"base1-85": await effect_pokemon_center(is_opponent)
		"base1-86": await effect_pokemon_flute(is_opponent)
		"base1-87": await effect_pokedex(is_opponent)
		"base1-89": await effect_revive(is_opponent)
		"base1-90": await effect_super_potion(is_opponent)
		"base1-92": await effect_energy_removal(is_opponent)
		"base1-93": await effect_gust_of_wind(is_opponent)
		"base1-94": await effect_potion(is_opponent)
		"base1-95": await effect_switch(is_opponent)
		"base2-64": await effect_poke_ball(is_opponent)
		"base3-58": await effect_mr_fuji(is_opponent)
		"base3-59": await effect_energy_search(is_opponent)
		"base3-60": await effect_gambler(is_opponent)
		"base3-61": await effect_recycle(is_opponent)
		"base5-15", "base5-71": await effect_here_comes_team_rocket(is_opponent)
		"base5-16", "base5-72": await effect_rockets_sneak_attack(is_opponent)
		"base5-73": await effect_the_boss_way(is_opponent)
		"base5-74": await effect_challenge(is_opponent)
		"base5-75": await effect_digger(is_opponent)
		"base5-76": await effect_imposter_oaks_revenge(card, is_opponent)
		"base5-77": await effect_nightly_garbage_run(is_opponent)
		"base5-78": await effect_goop_gas_attack(is_opponent)
		"base5-79": await effect_sleep_trainer(is_opponent)
		_:
			print("Unknown trainer card: ", card_id, " (", card_name, ")")

# Resolves bench token trainer placement (Clefairy Doll, Mysterious Fossil)
func resolve_bench_token_trainer(card: card_object, is_opponent: bool) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= 5:
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
			
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(targets)
			main.header_label.text = "ATTACH DEFENDER"
			main.hint_label.text = "Choose a Pokemon to attach Defender to"
			main.action_button.text = "ATTACH"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = false
			await main.trainer_target_selected
			var target = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
			
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
	for i in range(2):
		await main.draw_card_from_deck(is_opponent)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)

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
	for i in range(7):
		await main.draw_card_from_deck(is_opponent)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)

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
			main.trainer_deck_search_active = true
			main.show_enlarged_array_selection_mode(deck)
			main.header_label.text = "SEARCH YOUR DECK"
			main.hint_label.text = "Select any card to add to your hand"
			main.action_button.text = "TAKE CARD"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = false
			await main.trainer_target_selected
			if main._should_bail(): return
			var chosen = main.selected_card_for_action
			main.trainer_deck_search_active = false
			main.hide_selection_mode_display_main()
			
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(evolved_pokemon)
		main.header_label.text = "DEVOLUTION SPRAY"
		main.hint_label.text = "Choose an evolved Pokemon to devolve"
		main.action_button.text = "SELECT"
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
		
		# Step 2: If multiple pre-evolutions exist (Stage 2), let player choose which to devolve to
		var devolve_to: card_object = null
		if target.attached_pre_evolutions.size() == 1:
			# Only one option (Stage 1 → Basic)
			devolve_to = target.attached_pre_evolutions[0]
		else:
			# Multiple options (Stage 2 → show Basic and Stage 1)
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(target.attached_pre_evolutions)
			main.header_label.text = "DEVOLVE TO WHICH STAGE?"
			main.hint_label.text = "Select which card to devolve " + target.metadata.get("name", "") + " into"
			main.action_button.text = "DEVOLVE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = false
			await main.trainer_target_selected
			if main._should_bail(): return
			devolve_to = main.selected_card_for_action
			main.trainer_pokemon_selection_active = false
			main.hide_selection_mode_display_main()
		
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
	for i in range(7):
		await main.draw_card_from_deck(target_is_opponent)
		if main._should_bail(): return
		main.refresh_hand_display(target_is_opponent)
	main.update_deck_icon(target_is_opponent)
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
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(trainers_in_discard)
		main.header_label.text = "ITEM FINDER"
		main.hint_label.text = "Select a Trainer card from your discard pile"
		main.action_button.text = "RETRIEVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(stage2_cards)
		main.header_label.text = "POKEMON BREEDER"
		main.hint_label.text = "Select a Stage 2 Pokemon to play"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var s2_card = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
			# Put the Stage 2 back (it wasn't removed from hand yet by this function)
			return
		
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(targets)
		main.header_label.text = "POKEMON BREEDER"
		main.hint_label.text = "Select a Basic Pokemon to evolve into " + s2_card.metadata.get("name", "")
		main.action_button.text = "EVOLVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var target = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		# Player picks card to trade from hand
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(pokemon_in_hand)
		main.header_label.text = "POKEMON TRADER"
		main.hint_label.text = "Select a Pokemon from your hand to trade"
		main.action_button.text = "TRADE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var card_to_trade = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
		if card_to_trade == null:
			return
		
		# Player picks card from deck
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(pokemon_in_deck)
		main.header_label.text = "POKEMON TRADER"
		main.hint_label.text = "Select a Pokemon from your deck"
		main.action_button.text = "TAKE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var search_card = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(all_in_play)
		main.header_label.text = "SCOOP UP"
		main.hint_label.text = "Select a Pokemon to return its Basic card to your hand"
		main.action_button.text = "SCOOP UP"
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
	
	# Find the original Basic card (at the bottom of the pre-evolution chain)
	var basic_card = target
	if target.attached_pre_evolutions.size() > 0:
		basic_card = target.attached_pre_evolutions[0]
		target.attached_pre_evolutions.erase(basic_card)
	
	# Discard all attachments (energies, evolutions, attached cards)
	for energy in target.attached_energies:
		energy.current_location = "discard"
		discard.append(energy)
	target.attached_energies.clear()
	for evo in target.attached_pre_evolutions:
		evo.current_location = "discard"
		discard.append(evo)
	target.attached_pre_evolutions.clear()
	for att in target.attached_cards:
		att.current_location = "discard"
		discard.append(att)
	target.attached_cards.clear()
	
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
	var target_all = build_field_pokemon_array(not is_opponent)
	var target_with_energy = target_all.filter(func(p): return p.attached_energies.size() > 0)
	
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
		# Step 1: Player selects which of their own pokemon to discard energy from
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(own_with_energy)
		main.header_label.text = "SUPER ENERGY REMOVAL - YOUR POKEMON"
		main.hint_label.text = "Select your Pokemon to discard 1 energy from"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var source = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		
		# Step 3: Player selects opponent pokemon to remove energy from
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_with_energy)
		main.header_label.text = "SUPER ENERGY REMOVAL - OPPONENT"
		main.hint_label.text = "Select opponent's Pokemon to remove up to 2 energy"
		main.action_button.text = "SELECT"
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
		await main.draw_card_from_deck(true)
		if main._should_bail(): return
		main.refresh_hand_display(true)
		main.update_deck_icon(true)
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
		await main.draw_card_from_deck(false)
		if main._should_bail(): return
		main.refresh_hand_display(false)
		main.update_deck_icon(false)

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
	
	if target_bench.size() >= 5:
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
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(basics_in_discard)
		main.header_label.text = "POKEMON FLUTE"
		main.hint_label.text = "Choose a Basic Pokemon to place on opponent's bench"
		main.action_button.text = "PLACE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		
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
	
	if bench.size() >= 5:
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
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(basics_in_discard)
		main.header_label.text = "REVIVE"
		main.hint_label.text = "Select a Basic Pokemon to revive at half HP"
		main.action_button.text = "REVIVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		
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
			var max_hp = int(best_target.metadata.get("hp", "0"))
			var heal = min(40, max_hp - best_target.current_hp)
			best_target.current_hp = min(max_hp, best_target.current_hp + heal)
			main.display_active_pokemon_energies(true)
			await play_heal_animation(best_target, heal, true)
			if main._should_bail(): return
			main.update_discard_pile_display(true)
	else:
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(valid_targets)
		main.header_label.text = "SUPER POTION"
		main.hint_label.text = "Select a Pokemon to heal (will discard 1 energy)"
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
			var max_hp = int(target.metadata.get("hp", "0"))
			var heal = min(40, max_hp - target.current_hp)
			target.current_hp = min(max_hp, target.current_hp + heal)
			await play_heal_animation(target, heal, false)
			if main._should_bail(): return

# base1-92 — Energy Removal: Discard 1 energy from opponent's pokemon
func effect_energy_removal(is_opponent: bool) -> void:
	var target_is_opp = not is_opponent
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	
	# Build combined array with energy, active last
	var all_targets = build_field_pokemon_array(target_is_opp)
	var targets_with_energy = all_targets.filter(func(p): return p.attached_energies.size() > 0)
	
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(targets_with_energy)
		main.header_label.text = "ENERGY REMOVAL"
		main.hint_label.text = "Select opponent's Pokemon to remove energy from"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var target = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(target_bench)
		main.header_label.text = "GUST OF WIND"
		main.hint_label.text = "Select opponent's bench Pokemon to pull forward"
		main.action_button.text = "SWITCH"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		new_active = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	
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
		var max_hp = int(target.metadata.get("hp", "0"))
		var heal = min(20, max_hp - target.current_hp)
		target.current_hp = min(max_hp, target.current_hp + heal)
		await play_heal_animation(target, heal, true)
		if main._should_bail(): return
	else:
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(damaged)
		main.header_label.text = "POTION"
		main.hint_label.text = "Select a Pokemon to heal (up to 20 HP)"
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
			var max_hp = int(target.metadata.get("hp", "0"))
			var heal = min(20, max_hp - target.current_hp)
			target.current_hp = min(max_hp, target.current_hp + heal)
			await play_heal_animation(target, heal, false)
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(bench)
		main.header_label.text = "SWITCH"
		main.hint_label.text = "Select a bench Pokemon to switch with your active"
		main.action_button.text = "SWITCH"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		var replacement = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
		
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
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(matching)
		main.cancel_button.visible = true
		main.header_label.text = "POKE BALL: CHOOSE A POKEMON"
		main.hint_label.text = "Select a Basic or Evolution Pokemon"
		main.action_button.text = "TAKE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
	
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(bench)
		main.cancel_button.visible = false
		main.header_label.text = "MR. FUJI: CHOOSE A BENCHED POKEMON"
		main.hint_label.text = "This Pokemon and all attached cards will be shuffled into your deck"
		main.action_button.text = "SHUFFLE BACK"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	
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
		main.opponent_blocker.visible = false
		main.trainer_deck_search_active = true
		main.show_enlarged_array_selection_mode(basic_energies)
		main.cancel_button.visible = false
		main.header_label.text = "ENERGY SEARCH: CHOOSE A BASIC ENERGY"
		main.hint_label.text = "Select a basic Energy card to add to your hand"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_deck_search_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
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
	
	for i in range(draw_count):
		await main.draw_card_from_deck(is_opponent)
		if main._should_bail(): return
	
	main.refresh_hand_display(is_opponent)
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(discard)
		main.cancel_button.visible = false
		main.header_label.text = "RECYCLE: CHOOSE A CARD"
		main.hint_label.text = "This card will be placed on top of your deck"
		main.action_button.text = "RECYCLE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.trainer_target_selected
		if main._should_bail(): return
		chosen = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
	
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(trainer_cards)
		main.header_label.text = "CHOOSE A TRAINER TO SHUFFLE INTO DECK"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
		main.trainer_pokemon_selection_active = true
		main.show_enlarged_array_selection_mode(dark_evolutions)
		main.header_label.text = "CHOOSE A DARK EVOLUTION CARD"
		main.action_button.text = "SELECT"
		main.action_button.disabled = true
		await main.trainer_target_selected
		if main._should_bail(): return
		selected = main.selected_card_for_action
		main.trainer_pokemon_selection_active = false
		main.hide_selection_mode_display_main()
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
		if own_bench.size() >= 5 and opp_bench.size() >= 5:
			# Both benches full
			for i in range(2):
				await main.draw_card_from_deck(is_opponent)
				if main._should_bail(): return
			main.refresh_hand_display(is_opponent)
			await main.show_message("BOTH BENCHES FULL! DREW 2 CARDS!")
			if main._should_bail(): return
			return
		# CPU played it - player can accept or decline
		# Simplify: player declines, CPU draws 2
		for i in range(2):
			await main.draw_card_from_deck(is_opponent)
			if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
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
		
		if not accepted or (own_bench.size() >= 5 and opp_bench.size() >= 5):
			# Declined or both full
			for i in range(2):
				await main.draw_card_from_deck(is_opponent)
				if main._should_bail(): return
			main.refresh_hand_display(is_opponent)
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
				main.trainer_pokemon_selection_active = true
				main.show_enlarged_array_selection_mode(player_basics)
				main.header_label.text = "CHOOSE BASIC POKÉMON FOR BENCH"
				main.action_button.text = "SELECT"
				main.action_button.disabled = true
				await main.trainer_target_selected
				if main._should_bail(): return
				var player_pick = main.selected_card_for_action
				main.trainer_pokemon_selection_active = false
				main.hide_selection_mode_display_main()
				
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
	for i in range(draw_count):
		await main.draw_card_from_deck(!is_opponent)
		if main._should_bail(): return
	main.refresh_hand_display(!is_opponent)
	
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
			
			main.trainer_pokemon_selection_active = true
			main.show_enlarged_array_selection_mode(remaining)
			main.header_label.text = "CHOOSE CARD " + str(i + 1) + "/" + str(max_picks) + " (OR DONE)"
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
			defender.special_condition = "Asleep"
			main.update_status_icons(defender, !is_opponent)
			await main.show_message(defender.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! SLEEP FAILED!")
		if main._should_bail(): return
	print("TRAINER: Sleep!")
