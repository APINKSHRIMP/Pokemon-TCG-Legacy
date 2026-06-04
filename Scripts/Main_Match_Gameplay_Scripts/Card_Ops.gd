extends Node

######################################################################################################################################################
########################################################## CARD OPS — SHARED CARD OPERATIONS ########################################################
######################################################################################################################################################
#
# Canonical implementations of every repeated card-movement and state-change operation.
# All effect scripts (Attack_Effects, Trainer_Effects, Powers_And_Bodies_Effects) call these
# instead of copy-pasting the same logic with subtle per-copy variations.
#
# Access via main.card_ops (set in Main_Match_Core_Gameplay_Script._ready).
# All async functions check main._should_bail() after every await.
#

var main: Node

# ── Drawing ───────────────────────────────────────────────────────────────────────────────

# Draw N cards from deck to hand one at a time, updating the hand display after each card.
func draw_n(is_opponent: bool, count: int) -> void:
	for i in range(count):
		await main.draw_card_from_deck(is_opponent)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)

# ── Discard ───────────────────────────────────────────────────────────────────────────────

# Routes an energy card removed from a Pokemon to the correct pile:
# Recycle Energy and Ecogym (non-Colorless) return to owner's hand; others go to discard.
# Pass is_ko_discard=true for KO sequences so Ecogym protection is skipped.
func discard_energy_from_pokemon(energy: card_object, is_owner_opp: bool, is_ko_discard: bool = false) -> void:
	var card_name = energy.metadata.get("name", "")
	if card_name == "Recycle Energy":
		var hand = main.opponent_hand if is_owner_opp else main.player_hand
		energy.current_location = "hand"
		if not hand.has(energy):
			hand.append(energy)
		main.refresh_hand_display(is_owner_opp)
		return
	# Ecogym (neo1-84): non-Colorless energies discarded by attack/power/trainer return to owner's hand
	if not is_ko_discard and main.is_stadium_in_play(StadiumIds.ECOGYM):
		var provided = main.get_energy_provided_by_card(energy)
		var is_colorless = provided.is_empty() or (provided.size() == 1 and provided[0] == "Colorless")
		if not is_colorless:
			var hand = main.opponent_hand if is_owner_opp else main.player_hand
			energy.current_location = "hand"
			if not hand.has(energy):
				hand.append(energy)
			main.refresh_hand_display(is_owner_opp)
			return
	var discard = main.opponent_discard_pile if is_owner_opp else main.player_discard_pile
	energy.current_location = "discard"
	discard.append(energy)

# Move a single card to the given side's discard pile. Optionally animate it.
func send_to_discard(card: card_object, is_opponent: bool, animate: bool = false, anim_from: Control = null) -> void:
	if animate:
		var from_node = anim_from if anim_from != null else main.find_card_ui_for_object(card)
		if from_node == null:
			from_node = main.opponent_active_container if is_opponent else main.player_active_container
		var discard_node = main.opponent_discard_icon if is_opponent else main.player_discard_icon
		var tex = main.get_card_texture(card)
		await main.animate_card_a_to_b(from_node, discard_node, 0.2, tex, main.card_scales[10])
		if main._should_bail(): return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	if not discard.has(card):
		discard.append(card)
	card.current_location = "discard"
	main.update_discard_pile_display(is_opponent)

# Move every card in an array to the given side's discard pile.
func send_array_to_discard(cards: Array, is_opponent: bool, animate: bool = false) -> void:
	for card in cards.duplicate():
		await send_to_discard(card, is_opponent, animate)
		if main._should_bail(): return

# Discard all energies and pre-evolutions attached to a pokemon.
func discard_all_attachments(pokemon: card_object, is_opponent: bool) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for card in pokemon.attached_energies.duplicate():
		discard_energy_from_pokemon(card, is_opponent)
	pokemon.attached_energies.clear()
	for card in pokemon.attached_pre_evolutions.duplicate():
		card.current_location = "discard"
		discard.append(card)
	pokemon.attached_pre_evolutions.clear()
	for card in pokemon.attached_cards.duplicate():
		card.current_location = "discard"
		discard.append(card)
	pokemon.attached_cards.clear()
	main.update_discard_pile_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)

# ── Hand Discard (multi-select) ───────────────────────────────────────────────────────────

# CPU or player discards N cards from their hand.
# Player: shows all selectable cards at once; clicking toggles selection; confirm when N chosen.
# CPU: uses discard-priority ordering from Trainer_Effects.
# exclude_card is not offered for selection (e.g. the trainer card being played).
# Returns the list of discarded cards (empty if cancelled or nothing discarded).
func discard_from_hand(is_opponent: bool, count: int, exclude_card: card_object = null) -> Array:
	var hand   = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile

	if is_opponent:
		var to_remove = main.trainer_effects.cpu_get_discard_priority(hand, count, exclude_card)
		for card in to_remove:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		main.refresh_hand_display(true)
		main.update_discard_pile_display(true)
		return to_remove

	# Player multi-select
	var selectable = hand.filter(func(c): return c != exclude_card)
	if selectable.is_empty():
		return []

	main.trainer_discard_selected.clear()
	main.trainer_discard_cards_needed = count
	main.trainer_discard_selection_active = true
	main.show_enlarged_array_selection_mode(selectable)
	main.header_label.text = "DISCARD " + str(count) + " CARD(S)"
	main.hint_label.text = "0/" + str(count) + " selected"
	main.action_button.text = str(count) + " MORE"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = false

	await main.trainer_discard_selection_done
	main.trainer_discard_selection_active = false
	main.hide_selection_mode_display_main()
	if main._should_bail(): return []

	var discarded = main.trainer_discard_selected.duplicate()
	main.trainer_discard_selected.clear()
	for card in discarded:
		hand.erase(card)
		card.current_location = "discard"
		discard.append(card)
	main.refresh_hand_display(false)
	main.update_discard_pile_display(false)
	return discarded

# ── Deck Search (multi-select) ────────────────────────────────────────────────────────────

# Let the active side search their deck for up to `count` cards matching filter_fn,
# then move them to hand. Deck is shuffled after.
# Player sees a multi-select view; CPU receives the first N matches sorted by caller preference.
# Returns the list of cards moved to hand (empty on cancel or no matches).
func search_deck_to_hand(is_opponent: bool, filter_fn: Callable, prompt: String, count: int = 1) -> Array:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand

	var candidates = deck.filter(filter_fn)
	if candidates.is_empty():
		return []

	var chosen: Array = []

	if is_opponent:
		# CPU takes the first N matches (caller pre-sorts by preference if needed)
		for i in range(min(count, candidates.size())):
			chosen.append(candidates[i])
	else:
		# Player multi-select using discard-selection machinery
		main.trainer_discard_selected.clear()
		main.trainer_discard_cards_needed = count
		main.trainer_discard_selection_active = true
		main.show_enlarged_array_selection_mode(candidates)
		main.header_label.text = prompt.to_upper()
		var need_text = "SELECT " + str(count) + " CARD(S)" if count > 1 else "SELECT A CARD"
		main.hint_label.text = need_text
		main.action_button.text = str(count) + " MORE" if count > 1 else "TAKE CARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false

		await main.trainer_discard_selection_done
		main.trainer_discard_selection_active = false
		main.hide_selection_mode_display_main()
		if main._should_bail(): return []

		chosen = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selected.clear()

	for card in chosen:
		deck.erase(card)
		card.current_location = "hand"
		hand.append(card)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	return chosen

# ── Recover to Hand ───────────────────────────────────────────────────────────────────────

# Move a card from the discard pile back to hand with display refresh.
func recover_to_hand(card: card_object, is_opponent: bool, animate: bool = false) -> void:
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand    = main.opponent_hand if is_opponent else main.player_hand
	discard.erase(card)
	card.current_location = "hand"
	hand.append(card)
	if animate:
		var discard_icon = main.opponent_discard_icon if is_opponent else main.player_discard_icon
		var hand_node    = main.opponent_hand_container if is_opponent else main.player_hand_container
		var tex = main.get_card_texture(card)
		await main.animate_card_a_to_b(discard_icon, hand_node, 0.3, tex, main.card_scales[10])
		if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)

# ── Healing ───────────────────────────────────────────────────────────────────────────────

# Heal `amount` HP from a pokemon (clamped to max HP).
# Shows a green floating "+N HP" label above the pokemon's actual screen position,
# whether it is the active or a bench pokemon. Also animates HP circles restoring.
func heal_pokemon(pokemon: card_object, amount: int, is_opponent: bool) -> void:
	if amount <= 0:
		return
	var max_hp = pokemon.get_max_hp()
	var actual_heal = min(amount, max_hp - pokemon.current_hp)
	if actual_heal <= 0:
		return

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)

	# Show floating "+N HP" label above this pokemon's real screen position
	var loc = main.get_pokemon_screen_location(pokemon)
	if not loc.is_empty():
		main.show_floating_label("+" + str(actual_heal) + " HP", loc["position"] + Vector2(0, -20), Color.GREEN, true)

	# Animate HP circles restoring one counter at a time
	var circles_to_restore = actual_heal / 10
	var hp_before = pokemon.current_hp
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	for i in range(circles_to_restore):
		var partial_hp = hp_before + ((i + 1) * 10)
		pokemon.current_hp = min(partial_hp, hp_before + actual_heal)
		main.display_hp_circles_above_align(active if active != null else pokemon, is_opponent)
		await main.get_tree().create_timer(0.15).timeout
		if main._should_bail(): return
	pokemon.current_hp = min(hp_before + actual_heal, max_hp)
	main.display_hp_circles_above_align(active if active != null else pokemon, is_opponent)
	main.display_pokemon(is_opponent)

# ── Status Conditions ─────────────────────────────────────────────────────────────────────

# Apply a named status condition to a pokemon and refresh its status icons.
func apply_status(pokemon: card_object, status: String, is_opponent: bool) -> void:
	match status:
		"Poisoned":
			pokemon.is_poisoned = true
			pokemon.poison_damage = 10
		"Toxic":
			pokemon.is_poisoned = true
			pokemon.poison_damage = 20
		"Burned":
			pokemon.is_burned = true
		"Asleep", "Confused", "Paralyzed":
			pokemon.special_condition = status
		"Blind":
			pokemon.is_blind = true
	main.update_status_icons(pokemon, is_opponent)

# Remove all status conditions from a pokemon and refresh its icons.
func clear_statuses(pokemon: card_object, is_opponent: bool) -> void:
	main.clear_all_statuses(pokemon, is_opponent)

# ── Energy Removal ────────────────────────────────────────────────────────────────────────

# Remove one energy card from `target` pokemon's attached energies and send it to discard.
# `picker_is_opponent` determines whose side is making the choice (the attacker/effect owner).
# Pass `forced_card` to skip the selection UI and discard a specific energy directly.
# Returns the removed card, or null if none were available.
func remove_one_energy(target: card_object, target_owner_is_opponent: bool,
		picker_is_opponent: bool, forced_card: card_object = null) -> card_object:
	if target.attached_energies.is_empty():
		return null

	var chosen: card_object = null

	if forced_card != null:
		chosen = forced_card
	elif picker_is_opponent:
		# CPU picks first energy (caller can sort by preference before calling)
		chosen = target.attached_energies[0]
	else:
		# Player chooses which energy to discard
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(target.attached_energies)
		main.header_label.text = "DISCARD AN ENERGY"
		main.hint_label.text = "Choose which energy to discard"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_red
		main.cancel_button.visible = false
		await main.defender_energy_chosen
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		if main._should_bail(): return null
		chosen = main.selected_card_for_action

	if chosen == null:
		return null

	target.attached_energies.erase(chosen)
	if chosen.metadata.get("name", "") == "Recycle Energy":
		discard_energy_from_pokemon(chosen, target_owner_is_opponent)
		await main.show_message("RECYCLE ENERGY RETURNED TO HAND!")
		if main._should_bail(): return null
	else:
		await send_to_discard(chosen, target_owner_is_opponent, true,
			main.opponent_active_container if target_owner_is_opponent else main.player_active_container)
		if main._should_bail(): return null
	main.display_active_pokemon_energies(target_owner_is_opponent)
	return chosen

# ── Bench Placement ───────────────────────────────────────────────────────────────────────

# Place a pokemon card on the given side's bench.
# Returns false (without placing) if the bench is already at max capacity.
func place_on_bench(pokemon: card_object, is_opponent: bool) -> bool:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		return false
	pokemon.current_location = "bench"
	pokemon.placed_on_field_this_turn = true
	bench.append(pokemon)
	main.display_pokemon(is_opponent)
	return true

# ── Selection UI ──────────────────────────────────────────────────────────────────────────

# Show the enlarged card selection UI and wait for the player to pick one card from `pool`.
# Returns the chosen card_object (or null if cancelled). Pass search_mode=true when searching
# a deck (sets trainer_deck_search_active instead of trainer_pokemon_selection_active).
func prompt_select_card(pool: Array, header: String, hint: String, btn_text: String, cancelable: bool, search_mode: bool = false) -> card_object:
	main.opponent_blocker.visible = false
	if search_mode:
		main.trainer_deck_search_active = true
	else:
		main.trainer_pokemon_selection_active = true
	main.show_enlarged_array_selection_mode(pool)
	main.cancel_button.visible = cancelable
	main.header_label.text = header
	main.hint_label.text = hint
	main.action_button.text = btn_text
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	await main.trainer_target_selected
	var sel = main.selected_card_for_action
	if search_mode:
		main.trainer_deck_search_active = false
	else:
		main.trainer_pokemon_selection_active = false
	main.hide_selection_mode_display_main()
	main.opponent_blocker.visible = true
	return sel

# ── Bench Damage ──────────────────────────────────────────────────────────────────────────

# Apply `damage` to a bench pokemon and show a floating damage label above its bench position.
# Does not check KO — caller is responsible for running check_all_knockouts afterwards.
func apply_bench_damage(pokemon: card_object, damage: int, is_opponent: bool) -> void:
	if damage <= 0:
		return
	# Articuno Aurora Veil (basep-48): bench immune to attack damage
	if main.powers_and_bodies.check_aurora_veil(is_opponent):
		return
	# Protective Flame / invincible flag on bench pokemon
	if pokemon.is_invincible:
		return
	pokemon.current_hp = max(0, pokemon.current_hp - damage)
	var loc = main.get_pokemon_screen_location(pokemon)
	if not loc.is_empty():
		var label_pos = loc["position"] + Vector2(loc["size"].x / 2.0, -10)
		main.show_floating_label("-" + str(damage), label_pos, Color.RED, true)
	main.display_pokemon(is_opponent)
