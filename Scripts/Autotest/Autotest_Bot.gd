extends Node

# ============================================================
# AUTOTEST BOT — plays the PLAYER side of a match with no human
# ============================================================
# Two jobs, both done the way a person would do them — by clicking cards and pressing the action / cancel
# buttons through the same handlers the mouse reaches — so every effect's real player path is exercised:
#
#   1. ANSWERER (every frame): whatever the game is waiting on — a message box, a card pick, a multi-pick,
#      a reorder, a yes/no, a row of option buttons — gets a random LEGAL answer. This covers prompts on the
#      CPU's turn too (Cyclone Energy, Cat Punch, "your opponent chooses"...).
#   2. DRIVER (player's turn, board idle): picks a random legal action — bench, evolve, attach, play a
#      Trainer, use a Power, retreat, attack, end turn — and waits for the board to settle again.
#
# Random answers are the point: they reach combinations a real player never would. The CPU side is left
# completely alone and plays with its normal AI.

var main: Node = null            # the Main_Match_Core_Gameplay_Script instance
var runner: Node = null          # Autotest_Runner, for reporting
var rng := RandomNumberGenerator.new()

# The board must look idle for this many frames before the driver acts again. A match runs with
# Engine.time_scale raised, so this is generous in game time while costing almost nothing.
const SETTLE_FRAMES := 12
# A prompt that has been answered this many times without closing is reported as unsatisfiable.
const STUCK_ATTEMPTS := 40
const MAX_ACTIONS_PER_TURN := 30
const MAX_POWER_USES_PER_TURN := 6

var _idle_frames := 0
var _driver_busy := false
var _answer_cooldown := 0
var _prompt_key := ""
var _prompt_attempts := 0
var _turn_seen := -1
var _actions_this_turn := 0
var _powers_this_turn := 0
var _retreated_this_turn := false
var last_action := ""            # read by the runner for error context


func setup(m: Node, r: Node, seed_value: int) -> void:
	main = m
	runner = r
	rng.seed = seed_value


func _process(_delta: float) -> void:
	if main == null or not is_instance_valid(main) or not main.is_inside_tree():
		return
	if _answer_cooldown > 0:
		_answer_cooldown -= 1
		return
	if _answer_prompts():
		_idle_frames = 0
		_answer_cooldown = 1
		return
	if main.game_is_over:
		return
	if _driver_busy:
		return
	if not _board_idle():
		_idle_frames = 0
		return
	_idle_frames += 1
	if _idle_frames < SETTLE_FRAMES:
		return
	_idle_frames = 0
	_run_driver_step()


# ───────────────────────────── ANSWERER ─────────────────────────────

## Returns true if it pressed/clicked something this frame.
func _answer_prompts() -> bool:
	# 1. Message box — acknowledge it (this includes the game-over message).
	if main.msgbox_container.visible:
		main.message_acknowledged.emit()
		return true
	# 2. A coin is mid-flip — nothing to answer, just wait.
	if main.coin_container.visible:
		return false
	# 3. A row of buttons (option prompts, attack copy menus, the Power menu).
	if main.attack_buttons_container.visible:
		return _answer_buttons()
	# 4. The card selection screen.
	if main.card_selection_mode_enabled:
		return _answer_selection()
	_prompt_key = ""
	_prompt_attempts = 0
	return false


func _answer_buttons() -> bool:
	var live: Array = []
	var cancel_btn: Button = null
	for child in main.attack_buttons_container.get_children():
		if not (child is Button) or not child.visible or child.is_queued_for_deletion():
			continue
		if child.name == "cancel_attack_mode_button":
			cancel_btn = child
			continue
		if not child.disabled:
			live.append(child)
	if not _count_attempt("buttons:" + str(live.size())):
		return true
	if cancel_btn != null and (live.is_empty() or rng.randf() < 0.1):
		_log("press CANCEL on button menu")
		cancel_btn.pressed.emit()
		return true
	if live.is_empty():
		return false
	var b: Button = live[rng.randi() % live.size()]
	_log("press button '" + b.text + "'")
	b.pressed.emit()
	return true


func _answer_selection() -> bool:
	var m = main
	var pool: Array = m.shown_selection_pool.duplicate()
	var key := "%s|%s|%d" % [m.header_label.text, m.hint_label.text, pool.size()]
	if not _count_attempt(key):
		return true

	# Opening: choose the Active from the hand.
	if m.match_just_started_basic_pokemon_required:
		var basics: Array = m.player_hand.filter(func(c): return m.is_basic_pokemon(c))
		if basics.is_empty():
			return false
		_click(basics[rng.randi() % basics.size()])
		return _press_action()

	# Opening: bench some Basics, then "Done".
	if m.bench_setup_phase_active:
		var basics: Array = m.player_hand.filter(func(c): return m.is_basic_pokemon(c))
		if not basics.is_empty() and m.player_bench.size() < m.get_max_bench_size() and rng.randf() < 0.75:
			_click(basics[rng.randi() % basics.size()])
			if _press_action():
				return true
		_log("bench setup DONE")
		m.cancel_button.pressed.emit()
		return true

	# Yes / no.
	if m.yes_no_prompt_active:
		if rng.randf() < 0.5:
			_log("answer YES: " + m.header_label.text)
			m.action_button.pressed.emit()
		else:
			_log("answer NO: " + m.header_label.text)
			m.cancel_button.pressed.emit()
		return true

	# Reorder: click every card in a random order, then confirm.
	if m.trainer_reorder_active:
		var order: Array = m.pokedex_cards.duplicate()
		order.shuffle()
		for c in order:
			if c not in m.pokedex_reorder_result:
				_click(c)
		_log("reorder %d cards" % order.size())
		return _press_action() or _press_cancel()

	# Multi-pick: a random count between min and max, then confirm.
	if m.trainer_discard_selection_active:
		var max_n: int = m.trainer_discard_cards_needed
		var min_n: int = max(0, m.multi_select_min())
		var want: int = rng.randi_range(min_n, max(min_n, max_n))
		var order := pool.duplicate()
		order.shuffle()
		for c in order:
			if m.trainer_discard_selected.size() >= want:
				break
			if c not in m.trainer_discard_selected:
				_click(c)
		_log("multi-pick %d (min %d max %d) on '%s'" % [m.trainer_discard_selected.size(), min_n, max_n, m.header_label.text])
		if _press_action():
			return true
		# Couldn't reach a confirmable count with the cards picked — top up with everything legal.
		for c in order:
			if c not in m.trainer_discard_selected:
				_click(c)
				if _press_action():
					return true
		return _press_cancel()

	# A view-only reveal (DONE button only).
	if not m.action_button.visible:
		return _press_cancel()

	# --stack: Energy and evolutions go onto the target's line, like a player with a plan.
	if _stacking() and (m.card_attach_mode_active or m.evolution_mode_active):
		for c in pool:
			if c is Object and "metadata" in c and c.metadata.get("name", "") in runner.stack_line_names:
				_click(c)
				if _press_action():
					_log("stack: put it on " + _name(c))
					return true

	# Single pick. Sometimes back out, to exercise every cancel path.
	if m.cancel_button.visible and rng.randf() < 0.12:
		_log("CANCEL on '" + m.header_label.text + "'")
		m.cancel_button.pressed.emit()
		return true
	var order := pool.duplicate()
	order.shuffle()
	for c in order:
		_click(c)
		if not m.action_button.disabled and m.action_button.visible:
			_log("pick %s on '%s'" % [_name(c), m.header_label.text])
			m.action_button.pressed.emit()
			return true
	# Some screens (retreat Energy, Damage Swap...) need several clicks before the button lights up.
	for c in order:
		_click(c)
		if not m.action_button.disabled and m.action_button.visible:
			m.action_button.pressed.emit()
			return true
	return _press_cancel()


## Counts answers to the same prompt; returns false (and reports) once it is clearly stuck.
func _count_attempt(key: String) -> bool:
	if key == _prompt_key:
		_prompt_attempts += 1
	else:
		_prompt_key = key
		_prompt_attempts = 1
	if _prompt_attempts == STUCK_ATTEMPTS:
		runner.report_stuck("UNANSWERABLE PROMPT", "Answered %d times without closing: %s" % [STUCK_ATTEMPTS, key])
		return false
	return _prompt_attempts < STUCK_ATTEMPTS


func _click(card) -> void:
	if card == null:
		return
	main.this_card_clicked(card)


func _press_action() -> bool:
	if main.action_button.visible and not main.action_button.disabled:
		main.action_button.pressed.emit()
		return true
	return false


func _press_cancel() -> bool:
	if main.cancel_button.visible:
		_log("press CANCEL/DONE on '" + main.header_label.text + "'")
		main.cancel_button.pressed.emit()
		return true
	return false


# ───────────────────────────── DRIVER ─────────────────────────────

func _board_idle() -> bool:
	var m = main
	if m.opponents_turn_active or m.game_is_over:
		return false
	if m.msgbox_container.visible or m.coin_container.visible or m.attack_buttons_container.visible:
		return false
	if m.card_selection_mode_enabled:
		return false
	if m.get("_anim_in_flight"):
		return false
	return m._player_can_act_now()


func _run_driver_step() -> void:
	var m = main
	if m.turn_number != _turn_seen:
		_turn_seen = m.turn_number
		_actions_this_turn = 0
		_powers_this_turn = 0
		_retreated_this_turn = false
	_actions_this_turn += 1

	var options: Array = []   # [weight, label, Callable]
	var forced_end := _actions_this_turn > MAX_ACTIONS_PER_TURN

	if not forced_end:
		for card in m.player_hand:
			var act: String = m.get_card_action(card).get("action", "NONE")
			match act:
				"SET_POKEMON":
					if m.player_bench.size() < m.get_max_bench_size():
						options.append([3.0, "bench " + _name(card), _play_hand_card.bind(card)])
				"EVOLVE":
					if not m.get_valid_evolution_targets(card, false).is_empty():
						var ew := 40.0 if _stacking() and card.metadata.get("name", "") in runner.stack_line_names else 4.0
						options.append([ew, "evolve " + _name(card), _play_hand_card.bind(card)])
				"ATTACH_ENERGY":
					if not m.player_energy_played_this_turn and _energy_has_target(card):
						options.append([30.0 if _stacking() else 3.0, "attach " + _name(card), _play_hand_card.bind(card)])
				"PLAY_TRAINER":
					if m.trainer_effects.validate_trainer_can_be_played(card, false) == "":
						options.append([2.5, "trainer " + _name(card), _play_hand_card.bind(card)])
		if _powers_this_turn < MAX_POWER_USES_PER_TURN and _has_power_option():
			options.append([2.0, "power menu", _use_power])
		if not _retreated_this_turn and m.player_active_pokemon != null and not m.player_bench.is_empty():
			if bool(m.can_retreat(false).get("can_retreat", false)):
				options.append([0.6, "retreat", _retreat])

	var attacks := _usable_attacks()
	if not attacks.is_empty():
		# Attacking is what most needs testing, so it gets likelier with every setup action, and an attack
		# that has never been used anywhere yet is strongly preferred over one already covered.
		var w := 1.5 + 0.8 * _actions_this_turn
		if forced_end:
			w = 100.0
		var mon = m.player_active_pokemon
		var all_attacks: Array = m.get_attacks_for_card(mon)
		var weights: Array = []
		var wsum := 0.0
		for i in attacks:
			var an: String = all_attacks[i].get("name", "")
			var used: int = int(runner.coverage.get("attack|" + mon.uid + "|" + an, 0)) if runner != null else 0
			var aw := 1.0 / (1.0 + used)
			weights.append(aw)
			wsum += aw
		for k in attacks.size():
			var i: int = attacks[k]
			var aw2: float = w * weights[k] / wsum
			if _stacking() and all_attacks[i].get("name", "") == runner.stack_attack_name:
				aw2 = 500.0   # --stack: the attack under test, as soon as it can be paid for
			options.append([aw2, "attack " + str(all_attacks[i].get("name", "")), _attack.bind(i)])
	options.append([100.0 if forced_end else (0.4 if attacks.is_empty() else 0.15), "end turn", _end_turn])

	var total := 0.0
	for o in options:
		total += o[0]
	var roll := rng.randf() * total
	var chosen = options[options.size() - 1]
	for o in options:
		roll -= o[0]
		if roll <= 0.0:
			chosen = o
			break
	_log("ACTION: " + chosen[1])
	_driver_busy = true
	await chosen[2].call()
	_driver_busy = false


func _stacking() -> bool:
	return runner != null and runner.get("stack_attack_name") != null and String(runner.stack_attack_name) != ""


func _usable_attacks() -> Array:
	var m = main
	var out: Array = []
	if not m._player_can_attack_now():
		return out
	var mon = m.player_active_pokemon
	var attacks: Array = m.get_attacks_for_card(mon)
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		var an: String = a.get("name", "")
		if m.is_attack_disabled(mon, an):
			continue
		if not m.check_attack_requirements(a, mon):
			continue
		if m.attack_effects.attack_unusable_reason(a, mon) != "":
			continue
		out.append(i)
	return out


## Special Energy with a printed restriction (Miracle, Aqua/Magma, Holon...) is only worth trying when some
## Pokémon in play can take it — otherwise the bot burns its turn on refusals.
func _energy_has_target(card) -> bool:
	var m = main
	var targets: Array = m.player_bench.duplicate()
	if m.player_active_pokemon != null:
		targets.append(m.player_active_pokemon)
	for t in targets:
		if bool(m.special_energy_effects.can_attach_to(card, t).get("allowed", true)):
			return true
	return false


func _has_power_option() -> bool:
	var m = main
	var mons: Array = []
	if m.player_active_pokemon != null:
		mons.append(m.player_active_pokemon)
	mons.append_array(m.player_bench)
	for p in mons:
		if not m.powers_and_bodies.usable_powers_for(p).is_empty():
			return true
	return m.current_stadium_card != null and _powers_this_turn < 2


func _play_hand_card(card) -> void:
	main.selected_card_for_action = card
	await main.handle_action_normal_card()


func _use_power() -> void:
	_powers_this_turn += 1
	await main.powers_and_bodies.open_power_menu()


func _retreat() -> void:
	_retreated_this_turn = true
	main.start_retreat()


func _attack(i: int) -> void:
	await main.perform_attack(i)


func _end_turn() -> void:
	main._on_end_turn_pressed()


# ───────────────────────────── helpers ─────────────────────────────

func _name(c) -> String:
	if c == null or not (c is Object) or not ("metadata" in c):
		return "?"
	return "%s (%s)" % [c.metadata.get("name", "?"), c.uid]


func _log(s: String) -> void:
	last_action = s
	if runner != null:
		runner.bot_log(s)
