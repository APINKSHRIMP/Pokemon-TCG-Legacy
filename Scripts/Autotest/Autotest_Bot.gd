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
	if _async_busy:
		return
	if _answer_cooldown > 0:
		_answer_cooldown -= 1
		return
	# AUDIT 2026-11-17: --input=mix|mouse|keys|pad answers prompts with REAL input events.
	if _real_enabled() and _real_prompt_kind() != "":
		_async_busy = true
		var handled: bool = await _real_answer()
		_async_busy = false
		if handled:
			_idle_frames = 0
			_answer_cooldown = 1
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
	# 2. AUDIT 2026-11-17: an option pick (yes / no, "how many", a condition...) in the action panel rows.
	# 2026-11-21: answered BEFORE the coin check - Sabrina's ESP asks "re-flip this coin?" with the tails coin
	# still on screen (a person can click the rows: the action panel sits above the coin overlay). The bot
	# used to wait for the coin forever (221 SOFT-LOCKs in the overnight sim).
	if main.option_pick_active():
		var labels: Array = main.option_pick_labels
		if not _count_attempt("option:" + str(main.option_pick_caption) + str(labels)):
			return true
		var oi: int = rng.randi() % labels.size()
		if _smart() and main.option_pick_back_index == 1 and labels.size() == 2:
			oi = 0   # smart: "may" effects are almost always worth taking
		if cpu_option != "" and cpu_option in labels:
			oi = labels.find(cpu_option)   # CPU vs CPU: the answer the mirror CPU chose for this action
		_log("option '%s' on '%s'" % [labels[oi], str(main.option_pick_caption).left(60)])
		main.special_attack_selected.emit(oi)
		return true
	# 2a. A coin is mid-flip — nothing to answer, just wait.
	if main.coin_container.visible:
		return false
	# 2b. A copy attack (Metronome...) choosing from its rows in the action panel.
	if main.copy_pick_active and not main.copy_pick_pool.is_empty():
		var i: int = rng.randi() % main.copy_pick_pool.size()
		_log("copy pick '" + str(main.copy_pick_pool[i].get("name", "")) + "'")
		main.special_attack_selected.emit(i)
		return true
	# 3. A row of buttons (option prompts, attack copy menus, the Power menu).
	if main.attack_buttons_container.visible:
		_check_input_blocked("button row")
		return _answer_buttons()
	# 4. The card selection screen.
	if main.card_selection_mode_enabled:
		_check_input_blocked("selection screen")
		return _answer_selection()
	_prompt_key = ""
	_prompt_attempts = 0
	return false


## 2026-11-16: the bot answers by emitting signals, so a prompt a PERSON couldn't click was invisible to it (Dark
## Bind's yes/no sat under the full-screen opponent_blocker that perform_attack raises). Any prompt waiting for an
## answer while that blocker is up is reported - one report per prompt header per match.
func _check_input_blocked(kind: String) -> void:
	if runner == null or not main.opponent_blocker.visible:
		return
	var header: String = str(main.header_label.text) if kind == "selection screen" else "buttons: " + ", ".join(PackedStringArray(
		main.attack_buttons_container.get_children().filter(func(c): return c is Button and c.visible).map(func(c): return c.text)))
	runner._problem("INPUT BLOCKED", "a %s was waiting for the player but opponent_blocker covered it — %s" % [kind, header],
		"blocked" + kind + header.left(60))


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
	if cancel_btn != null and (live.is_empty() or (rng.randf() < 0.1 and not _smart())):
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
		if _smart():
			basics.sort_custom(func(a, c): return _opening_value(a) > _opening_value(c))
			_click(basics[0])
		else:
			_click(basics[rng.randi() % basics.size()])
		return _press_action()

	# Opening: bench some Basics, then "Done".
	if m.bench_setup_phase_active:
		var basics: Array = m.player_hand.filter(func(c): return m.is_basic_pokemon(c))
		if not basics.is_empty() and m.player_bench.size() < m.get_max_bench_size() and (rng.randf() < 0.75 or (_smart() and m.player_bench.size() < 4)):
			_click(basics[rng.randi() % basics.size()])
			if _press_action():
				return true
		_log("bench setup DONE")
		m.cancel_button.pressed.emit()
		return true

	# Yes / no.
	if m.yes_no_prompt_active:
		if _smart() or rng.randf() < 0.5:   # smart: "may" effects are almost always worth taking
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
	if m.trainer_discard_selection_active and _smart() and _smart_multi_pick(pool):
		return true
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

	# --bot=smart: Energy goes where it gets an attack closest to usable.
	if _smart() and m.card_attach_mode_active:
		var best_t = _smart_attach_target(pool)
		if best_t != null:
			_click(best_t)
			if _press_action():
				_log("smart: attach to " + _name(best_t))
				return true

	# --stack: Energy and evolutions go onto the target's line, like a player with a plan.
	if _stacking() and (m.card_attach_mode_active or m.evolution_mode_active):
		for c in pool:
			if c is Object and "metadata" in c and c.metadata.get("name", "") in runner.stack_line_names:
				_click(c)
				if _press_action():
					_log("stack: put it on " + _name(c))
					return true

	# --bot=smart: a reasoned single pick (new Active, targets, searches, discards).
	if _smart():
		# Repeatable Powers ("as often as you like": Energy Trans, Damage Swap) would loop forever moving the same
		# thing back and forth - after 6 picks on one prompt in a turn, stop.
		if m.turn_number != _pick_turn:
			_pick_turn = m.turn_number
			_pick_counts = {}
		var hk: String = str(m.header_label.text)
		_pick_counts[hk] = int(_pick_counts.get(hk, 0)) + 1
		if _pick_counts[hk] > 6 and _press_cancel():
			return true
		var pick = _smart_single_pick(pool)
		if pick != null:
			_click(pick)
			if _press_action():
				_log("smart pick %s on '%s'" % [_name(pick), m.header_label.text])
				return true

	# Single pick. Sometimes back out, to exercise every cancel path.
	if m.cancel_button.visible and rng.randf() < 0.12 and not _smart():
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
	if m.msgbox_container.visible or m.coin_container.visible or m.attack_buttons_container.visible or m.copy_pick_active:
		return false
	if m.card_selection_mode_enabled:
		return false
	if m.get("_anim_in_flight"):
		return false
	# 2026-11-21: a person can do nothing while a full-screen blocker is up (mouse is stopped by it, Board_Nav and
	# Hand_Drag both refuse) - perform_attack raises opponent_blocker the moment an attack starts. The bot's driver
	# used to act in the gap before the attack ended the turn: Teleport Blast was attacked with twice and a retreat
	# opened under the blocker (INPUT BLOCKED "RETREAT - SELECT ENERGY TO DISCARD").
	if m.opponent_blocker.visible or m.animation_blocker.visible:
		return false
	return m._player_can_act_now()


func _run_driver_step() -> void:
	var m = main
	if m.turn_number != _turn_seen:
		_turn_seen = m.turn_number
		_actions_this_turn = 0
		_powers_this_turn = 0
		_retreated_this_turn = false
		_smart_trainers = 0
		_cpu_tried = {}
		_cpu_trainers = 0
		cpu_target = null
		cpu_option = ""
	_actions_this_turn += 1
	if _cpu_bot():
		_driver_busy = true
		await _cpu_step()   # cpu_target / cpu_option stay set: the prompts that action opens come after it returns
		_driver_busy = false
		return
	if _smart():
		_driver_busy = true
		await _smart_step()
		_driver_busy = false
		return

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


# ───────────────────────────── --bot=smart: a sensible plan ─────────────────────────────

var _smart_trainers := 0
var _pick_turn := -1
var _pick_counts := {}

func _smart() -> bool:
	return runner != null and bool(runner.get("opt_bot_smart"))


func _smart_step() -> void:
	# OLD ISSUE 375 (smart bot v2, 2026-10-10): a sparring partner that plays like a sensible person, so the CPU's
	# self-play tuning learns from a real opponent. Order: evolve, bench, Energy, Powers, Trainers (only when they help),
	# retreat when it pays, then the best attack (a KO first, never a suicidal recoil).
	var m = main
	if _actions_this_turn > MAX_ACTIONS_PER_TURN:
		_end_turn()
		return
	var foe = m.opponent_active_pokemon
	# 1. Evolve — the Active first (the answerer picks the target).
	for card in m.player_hand:
		if m.get_card_action(card).get("action", "") == "EVOLVE" and not m.get_valid_evolution_targets(card, false).is_empty():
			_log("SMART: evolve " + _name(card))
			await _play_hand_card(card)
			return
	# 2. Bench up to four, Basics with an evolution in hand first.
	if m.player_bench.size() < mini(4, m.get_max_bench_size()):
		var best_b = null
		var best_bv := -INF
		for card in m.player_hand:
			if m.get_card_action(card).get("action", "") == "SET_POKEMON":
				var bv := _opening_value(card)
				if bv > best_bv:
					best_bv = bv
					best_b = card
		if best_b != null:
			_log("SMART: bench " + _name(best_b))
			await _play_hand_card(best_b)
			return
	# 3. One Energy, onto whatever it helps most.
	if not m.player_energy_played_this_turn:
		for card in m.player_hand:
			if m.get_card_action(card).get("action", "") == "ATTACH_ENERGY" and _energy_has_target(card):
				_log("SMART: attach " + _name(card))
				await _play_hand_card(card)
				return
	# 4. Pokémon Powers (Rain Dance, Damage Swap, Energy Trans...) — a few uses a turn.
	if _powers_this_turn < 3 and _has_power_option():
		_log("SMART: power menu")
		await _use_power()
		return
	# 5. Trainers that help right now (up to six a turn).
	if _smart_trainers < 6:
		for card in m.player_hand:
			if m.get_card_action(card).get("action", "") == "PLAY_TRAINER" and m.trainer_effects.validate_trainer_can_be_played(card, false) == "" \
					and _trainer_worth_it(card):
				_smart_trainers += 1
				_log("SMART: trainer " + _name(card))
				await _play_hand_card(card)
				return
	# 6. Retreat when it pays: the Active can't attack (or is about to be KO'd) and a Benched Pokémon does better.
	var attacks := _usable_attacks()
	var me = m.player_active_pokemon
	if me != null and not _retreated_this_turn and not m.player_bench.is_empty() and bool(m.can_retreat(false).get("can_retreat", false)):
		var stay := _attacker_value(me, foe)
		var best_bp = null
		var best_v := stay + 60.0
		for bp in m.player_bench:
			var v := _attacker_value(bp, foe)
			if v > best_v:
				best_v = v
				best_bp = bp
		if best_bp != null and (attacks.is_empty() or (foe != null and _threat(foe, me) >= me.current_hp)):
			_retreated_this_turn = true
			_log("SMART: retreat (better: " + _name(best_bp) + ")")
			_retreat()
			return
	# 7. The best attack.
	if not attacks.is_empty():
		var all_attacks: Array = m.get_attacks_for_card(me)
		var best_i: int = attacks[0]
		var best_av := -INF
		for i in attacks:
			var av := _attack_value(all_attacks[i], me, foe)
			if av > best_av:
				best_av = av
				best_i = i
		_log("SMART: attack " + str(all_attacks[best_i].get("name", "")))
		await _attack(best_i)
		return
	_log("SMART: end turn")
	_end_turn()


# ── smart v2 evaluation helpers (player's side) ──

func _dmg_vs(a: Dictionary, p, target, which: String = "expected") -> int:
	if target == null:
		return 0
	var d := int(main.attack_effects.estimate_attack_damage_range(a, p, target).get(which, 0))
	if d > 0:
		d = int(main.calculate_final_damage(d, p.get_effective_types(), target, p).get("damage", d))
	return d


## Best damage p can do to target with attacks it can pay for now.
func _best_dmg(p, target, which: String = "expected") -> int:
	var best := 0
	if p == null or target == null:
		return 0
	for a in main.get_attacks_for_card(p):
		if main.check_attack_requirements(a, p):
			best = maxi(best, _dmg_vs(a, p, target, which))
	return best


## What attacker could do to target soon (attacks at most 1 Energy short) — the threat it poses.
func _threat(attacker, target) -> int:
	var best := 0
	if attacker == null or target == null:
		return 0
	for a in attacker.metadata.get("attacks", []):
		if main.cpu_ai.get_unmet_energy_count(a, attacker) <= 1:
			best = maxi(best, _dmg_vs(a, attacker, target, "max"))
	return best


## How good p would be as the Active against foe.
func _attacker_value(p, foe) -> float:
	if p == null:
		return -INF
	var v := 0.0
	var short := 9
	for a in main.get_attacks_for_card(p):
		short = mini(short, main.cpu_ai.get_unmet_energy_count(a, p))
	if _payable_attack(p):
		v += 100.0
	v -= short * 15.0
	if foe != null:
		var d := _best_dmg(p, foe)
		v += d
		if _best_dmg(p, foe, "min") >= foe.current_hp:
			v += 200.0
		if _threat(foe, p) >= p.current_hp:
			v -= 90.0
	v += p.current_hp * 0.2
	return v


func _attack_value(a: Dictionary, me, foe) -> float:
	var tl := String(a.get("text", "")).to_lower()
	var ex := float(_dmg_vs(a, me, foe))
	var mn := _dmg_vs(a, me, foe, "min")
	var v := ex
	if foe != null and mn >= foe.current_hp:
		v += 1000.0 + (500.0 if main.is_ex_pokemon(foe) else 0.0)
	elif foe != null and ex >= foe.current_hp:
		v += 300.0
	# Recoil that would Knock Out our own Pokémon (unless it wins the game).
	if "damage to itself" in tl:
		var self_d: int = main.attack_effects.extract_number_before(tl, " damage to itself")
		if self_d >= me.current_hp and not (foe != null and mn >= foe.current_hp and main.player_prize_cards.size() <= 1):
			v -= 800.0
	if foe != null and mn < foe.current_hp:
		if "paralyz" in tl: v += 25.0 * (0.5 if "flip" in tl else 1.0)
		if "confus" in tl or "asleep" in tl: v += 12.0 * (0.5 if "flip" in tl else 1.0)
		if "poison" in tl and not foe.is_poisoned: v += 10.0
	return v


## Opening / bench choice: attack soon, HP, an evolution waiting in hand.
func _opening_value(c) -> float:
	var v: float = float(main.get_pokemon_hp(c))
	var cheapest := 9
	for a in c.metadata.get("attacks", []):
		cheapest = mini(cheapest, a.get("cost", []).size())
	v -= cheapest * 20.0
	var nm: String = c.metadata.get("name", "")
	if main.player_hand.any(func(h): return h.metadata.get("evolvesFrom", "") == nm):
		v += 60.0
	return v


## How much a card in a search / discard pool is worth to us.
func _card_value(c) -> float:
	var m = main
	if not (c is Object) or not ("metadata" in c):
		return 0.0
	var st: String = c.metadata.get("supertype", "")
	if st.begins_with("Pok"):
		var from: String = c.metadata.get("evolvesFrom", "")
		if from != "":
			var mine: Array = m.player_bench.duplicate()
			if m.player_active_pokemon != null:
				mine.append(m.player_active_pokemon)
			return 90.0 if mine.any(func(p): return p.metadata.get("name", "") == from) else 25.0
		return 65.0 if m.player_bench.size() < 4 else 30.0
	if st == "Energy":
		var mine2: Array = m.player_bench.duplicate()
		if m.player_active_pokemon != null:
			mine2.append(m.player_active_pokemon)
		for p in mine2:
			for a in m.get_attacks_for_card(p):
				if m.cpu_ai.get_unmet_energy_count(a, p) > 0:
					return 60.0
		return 35.0
	return 45.0


func _in_play_mine(c) -> bool:
	return c == main.player_active_pokemon or c in main.player_bench


func _in_play_theirs(c) -> bool:
	return c == main.opponent_active_pokemon or c in main.opponent_bench


## A reasoned pick for a single-choice prompt, or null to fall back to the default behaviour.
func _smart_single_pick(pool: Array):
	var m = main
	var cards: Array = pool.filter(func(c): return c is Object and "metadata" in c)
	if cards.is_empty():
		return null
	if cpu_target != null and cpu_target in cards:
		return cpu_target   # CPU vs CPU: the target the mirror CPU chose (Energy / evolution / retreat replacement)
	var h: String = (str(m.header_label.text) + " " + str(m.hint_label.text)).to_upper()
	var negative: bool = "DISCARD" in h or "RETURN" in h or "SHUFFLE" in h or "REMOVE" in h and "YOUR" in h
	var foe = m.opponent_active_pokemon
	var me = m.player_active_pokemon
	if cards.all(func(c): return _in_play_mine(c)):
		if m.evolution_mode_active and me in cards:
			return me
		var best = null
		var best_v := -INF
		for c in cards:
			var v := _attacker_value(c, foe)
			if negative:
				v = -v
			if v > best_v:
				best_v = v
				best = c
		return best
	if cards.all(func(c): return _in_play_theirs(c)):
		var best2 = null
		var best_v2 := -INF
		for c in cards:
			var v2 := 0.0
			if "ENERGY" in h:
				v2 = c.attached_energies.size() * 10.0 + (20.0 if c == foe else 0.0)
			else:
				if me != null and _best_dmg(me, c, "min") >= c.current_hp:
					v2 += 500.0 + (300.0 if m.is_ex_pokemon(c) else 0.0)
				v2 -= c.current_hp
				if not _payable_attack(c):
					v2 += 40.0 + 15.0 * m.get_retreat_cost(c)
			if v2 > best_v2:
				best_v2 = v2
				best2 = c
		return best2
	# Cards from a deck / discard pile / hand.
	var best3 = null
	var best_v3 := -INF
	for c in cards:
		var v3 := _card_value(c)
		if negative:
			v3 = -v3
		if v3 > best_v3:
			best_v3 = v3
			best3 = c
	return best3


## Multi-pick: take as many good cards as allowed, or as few (and the least useful) when it costs us.
func _smart_multi_pick(pool: Array) -> bool:
	var m = main
	var h: String = (str(m.header_label.text) + " " + str(m.hint_label.text)).to_upper()
	var negative: bool = "DISCARD" in h or "RETURN" in h or "SHUFFLE" in h
	var max_n: int = m.trainer_discard_cards_needed
	var min_n: int = max(0, m.multi_select_min())
	var want: int = min_n if negative else max_n
	var order: Array = pool.duplicate()
	order.sort_custom(func(a, c): return (_card_value(a) < _card_value(c)) if negative else (_card_value(a) > _card_value(c)))
	for c in order:
		if m.trainer_discard_selected.size() >= want:
			break
		if c not in m.trainer_discard_selected:
			# Only one click per frame counts, so never spend it on a card the prompt's own rule refuses.
			if m.trainer_discard_validator.is_valid() and not m.trainer_discard_validator.call(c, m.trainer_discard_selected.duplicate()):
				continue
			_click(c)
			break
	if _press_action():
		_log("smart multi-pick %d on '%s'" % [m.trainer_discard_selected.size(), m.header_label.text])
		return true
	return false


## Situational Trainers only when they do something now; everything else is played.
func _trainer_worth_it(card) -> bool:
	var m = main
	var nm: String = card.metadata.get("name", "")
	var me = m.player_active_pokemon
	var foe = m.opponent_active_pokemon
	if nm in ["Gust of Wind", "Pokémon Reversal", "Double Gust", "Warp Point", "Pokémon Catcher"]:
		if me == null:
			return false
		var best_dmg := _best_dmg(me, foe, "min")
		for t in m.opponent_bench:
			if _best_dmg(me, t, "min") >= t.current_hp and (foe == null or best_dmg < foe.current_hp):
				return true
			if not _payable_attack(t) and m.get_retreat_cost(t) >= 2 and (foe == null or _payable_attack(foe)):
				return true
		return false
	if nm == "PlusPower":
		if me == null or foe == null:
			return false
		var bd := _best_dmg(me, foe, "min")
		return bd > 0 and bd < foe.current_hp and bd + 10 >= foe.current_hp
	if "Potion" in nm or nm in ["Pokémon Center", "Super Potion"]:
		return me != null and me.get_max_hp() - me.current_hp >= 20
	if nm in ["Switch", "Escape Rope"]:
		if me == null or m.player_bench.is_empty():
			return false
		return _usable_attacks().is_empty() and m.player_bench.any(func(p): return _payable_attack(p))
	if nm == "Defender":
		return me != null and foe != null and _threat(foe, me) >= me.current_hp
	if nm in ["Professor Oak", "Imposter Professor Oak", "Lass"]:
		return m.player_hand.size() <= 4
	if "Energy Removal" in nm:
		return foe != null and not foe.attached_energies.is_empty()
	if nm in ["Full Heal"]:
		return me != null and (me.special_condition != "" or me.is_poisoned or me.is_burned)
	return true


func _payable_attack(p) -> bool:
	for a in main.get_attacks_for_card(p):
		if main.check_attack_requirements(a, p):
			return true
	return false


## The Pokémon whose best attack is closest to (but not yet) payable — the Active first.
func _smart_attach_target(pool: Array):
	var best = null
	var best_short := 999
	for p in pool:
		if not (p is Object) or not ("attached_energies" in p):
			continue
		var short := 999
		for a in main.get_attacks_for_card(p):
			short = mini(short, main.cpu_ai.get_unmet_energy_count(a, p))
		if short <= 0:
			short = 50   # already has what it needs
		if p == main.player_active_pokemon:
			short -= 1
		if short < best_short:
			best_short = short
			best = p
	return best


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


# ───────────────────────────── --bot=cpu (2026-11-21): CPU vs CPU ─────────────────────────────
# The player's side is played by a second CPU_AI ("MirrorCPU"): each step it names the next action with the real CPU
# decision functions (CPU_AI.mirror_next_action) and this bot carries it out through the normal controls. Pokémon
# Powers still go through the smart bot's power menu (the CPU's power phase acts by itself and has no dry run).
var _mirror_ai = null
var _cpu_tried := {}
var _cpu_trainers := 0
var cpu_target = null      # the card the current action's prompt should get (read by _smart_single_pick)
var cpu_option := ""       # the option row the current action's prompt should get

func _cpu_bot() -> bool:
	return runner != null and bool(runner.get("opt_bot_cpu"))


func _mirror():
	if _mirror_ai == null or not is_instance_valid(_mirror_ai):
		_mirror_ai = load("res://Scripts/Main_Match_Gameplay_Scripts/CPU_AI.gd").new()
		_mirror_ai.name = "MirrorCPU"
		main.add_child(_mirror_ai)
		_mirror_ai.main = main
	return _mirror_ai


func _cpu_step() -> void:
	var m = main
	if _actions_this_turn > MAX_ACTIONS_PER_TURN:
		_end_turn()
		return
	if _powers_this_turn < 3 and _has_power_option():
		_log("CPU-BOT: power menu")
		await _use_power()
		return
	var playable := {}
	for c in m.player_hand:
		if m.get_card_action(c).get("action", "") == "PLAY_TRAINER" and m.trainer_effects.validate_trainer_can_be_played(c, false) == "":
			playable[c.get_instance_id()] = true
	var can_rt: bool = not _retreated_this_turn and not m.player_retreated_this_turn and not m.player_bench.is_empty() \
		and bool(m.can_retreat(false).get("can_retreat", false)) and not m.match_effects.retreat_blocked(false)
	var act: Dictionary = await _mirror().mirror_next_action(_cpu_tried, not can_rt, _cpu_trainers, playable, can_rt)
	if m._should_bail() or not is_instance_valid(m):
		return
	var card = act.get("card")
	cpu_target = act.get("target")
	cpu_option = ""
	var kind := String(act.get("kind", "end"))
	_log("CPU-BOT: %s %s%s (%s)" % [kind, _name(card) if card != null else "", (" -> " + _name(cpu_target)) if cpu_target != null else "", str(act.get("why", ""))])
	match kind:
		"trainer":
			_cpu_trainers += 1
			_cpu_tried[card.get_instance_id()] = true
			await _play_hand_card(card)
		"evolve":
			_cpu_tried[card.get_instance_id()] = true
			await m.drag_evolve(card, cpu_target)   # straight onto the chosen Pokémon (also a Basic onto its Baby)
		"bench":
			_cpu_tried[card.get_instance_id()] = true
			cpu_option = "PLACE ON BENCH"   # a Basic that could also evolve a Baby is asked which
			await _play_hand_card(card)
		"energy":
			_cpu_tried[card.get_instance_id()] = true
			await m.drag_attach_energy(card, cpu_target)
		"retreat":
			_retreated_this_turn = true
			_retreat()
		"attack":
			await _attack(int(act.get("index", 0)))
		_:
			_end_turn()


func _play_hand_card(card) -> void:
	main.selected_card_for_action = card
	await main.handle_action_normal_card()


func _use_power() -> void:
	_powers_this_turn += 1
	# AUDIT 2026-11-17: in real-input mode, press an actual Power / Stadium row or Bench Power button.
	if _real_enabled():
		var live: Array = _live_power_buttons()
		if not live.is_empty():
			var b: BaseButton = live[rng.randi() % live.size()]
			_mode = _pick_mode()
			var hold_p: bool = _mode != "mouse"
			_real_hold(hold_p)
			_log("REAL power button '" + _btn_text(b) + "'")
			_input_waiting = true
			await _real_press(b, "power button '" + _btn_text(b) + "'")
			_input_waiting = false
			_real_release(hold_p)
			return
	await main.powers_and_bodies.open_power_menu()


func _retreat() -> void:
	_retreated_this_turn = true
	main.start_retreat()


func _attack(i: int) -> void:
	# AUDIT 2026-11-17: in real-input mode the attack row itself is pressed (mouse / keys / pad).
	if _real_enabled():
		var attacks: Array = main.get_attacks_for_card(main.player_active_pokemon)
		var want: String = String(attacks[i].get("name", "")) if i < attacks.size() else ""
		var b: BaseButton = _attack_row_button(i)
		if b != null and String(b.get_meta("row_text", "")) == want and not b.disabled:
			_mode = _pick_mode()
			var hold_a: bool = _mode != "mouse"
			_real_hold(hold_a)
			_log("REAL attack row '" + want + "'")
			_input_waiting = true
			await _real_press(b, "attack row '" + want + "'")
			_input_waiting = false
			_real_release(hold_a)
			return
		runner._problem("NO ATTACK ROW", "no live row for usable attack '%s' (index %d) on %s" % [want, i, _name(main.player_active_pokemon)], "noatkrow" + want)
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


# ═════════════════════════ AUDIT 2026-11-17: REAL INPUT ═════════════════════════
# With --input=mix|mouse|keys|pad the bot answers option rows (yes / no, "how many", copy picks...), card selection
# screens, messages, attack rows and Power buttons by sending REAL input events through Input.parse_input_event -
# a mouse click on the control's screen position, or the board cursor walked there with arrows / D-pad and accept
# pressed. When the input does nothing the bot says so (INPUT IGNORED, NAV UNREACHABLE) and answers by signal so the
# match goes on. On a FORCED prompt it first tries to get out of it (Backspace, Escape, pad B, right click, a click
# off the prompt) and reports FORCED PROMPT SKIPPED if any of those closed it.

const REAL_MODES := ["mouse", "keys", "pad"]
## TWEAKABLE. Chance a forced prompt is probed with "get me out" inputs before it is answered.
const SKIP_PROBE_CHANCE := 0.35
## TWEAKABLE. Share of plain messages acknowledged by real input (the rest by signal - there are thousands).
const REAL_MESSAGE_CHANCE := 0.15

var _async_busy := false
var _input_waiting := false        # the DRIVER is mid real-input press (the runner holds its clocks for both)
var _mode := "signal"
var input_stats := {"answers": 0, "ignored": 0, "unreachable": 0, "skipped": 0, "probes": 0}


## The cursor (Board_Nav) listens while ANY real key / pad driving is going on - the driver and the answerer can
## both be mid-press, so a count, not a flag (one finishing used to switch the cursor off under the other).
var _real_users := 0

func _real_hold(on: bool) -> void:
	if on:
		_real_users += 1
	runner.real_input_now = _real_users > 0


func _real_release(on: bool) -> void:
	if on:
		_real_users = maxi(0, _real_users - 1)
	runner.real_input_now = _real_users > 0


func _real_enabled() -> bool:
	if runner == null or _smart() or _stacking():
		return false
	var o := str(runner.get("opt_input"))
	return o != "" and o != "signal"


func _pick_mode() -> String:
	var o := str(runner.get("opt_input"))
	if o in REAL_MODES:
		return o
	return REAL_MODES[rng.randi() % REAL_MODES.size()]


## Which prompt real input will answer now ("" = leave it to the signal answerer).
func _real_prompt_kind() -> String:
	var m = main
	if m.msgbox_container.visible:
		return "message" if rng.randf() < REAL_MESSAGE_CHANCE else ""
	if m.coin_container.visible:
		return ""
	if m.copy_pick_active:
		return "option"
	if m.card_selection_mode_enabled:
		if m.match_just_started_basic_pokemon_required or m.bench_setup_phase_active:
			return ""
		if m.bench_view_active or m.pokemon_preview_active:
			return ""
		return "selection"
	return ""


func _real_answer() -> bool:
	var kind := _real_prompt_kind()
	if kind == "":
		return false
	_mode = _pick_mode()
	if OS.has_environment("AUTOTEST_NAV_TRACE"): print("REALTRACE answer ", kind, " ", _mode, " header=", main.header_label.text)
	_real_hold(_mode != "mouse")
	var ok := false
	match kind:
		"message": ok = await _real_message()
		"option": ok = await _real_option()
		"selection": ok = await _real_selection()
	_real_release(_mode != "mouse")
	if ok:
		input_stats["answers"] += 1
	return ok


# ── Messages ──

## Counts message_acknowledged emissions: a message followed at once by another never hides the box, so
## "the box went away" is not the test - "the box was acknowledged" is.
var _msg_acks := 0

func _on_msg_ack() -> void:
	_msg_acks += 1


func _real_message() -> bool:
	if not main.message_acknowledged.is_connected(_on_msg_ack):
		main.message_acknowledged.connect(_on_msg_ack)
	var acks0 := _msg_acks
	for attempt in 2:
		match _mode:
			"mouse": await _send_click(_screen_center())
			"keys": await _send_key(KEY_SPACE if rng.randf() < 0.5 else KEY_ENTER)
			"pad": await _send_pad(JOY_BUTTON_A)
		for _i in 8:
			if not main.msgbox_container.visible or _msg_acks > acks0:
				return true
			await get_tree().process_frame
	var last_msg: String = str(main._match_log[-1].get("text", "")) if not main._match_log.is_empty() else "?"
	_ignored("message (%s): '%s' [%s]" % [_mode, last_msg.left(70), _nav_block_reason()], "msg" + _mode + last_msg.left(30))
	main.message_acknowledged.emit()
	return true


# ── Option rows (yes / no, counts, conditions, copy picks) ──

func _real_option() -> bool:
	var m = main
	var is_opt: bool = m.option_pick_active()
	var caption: String = str(m.option_pick_caption) if is_opt else "copy pick"
	var labels: Array = (m.option_pick_labels as Array).duplicate() if is_opt else []
	if not is_opt:
		for a in m.copy_pick_pool:
			labels.append(str(a.get("name", "")))
	var back: int = int(m.option_pick_back_index) if is_opt else -1
	var rows: Array = _panel_buttons(true).filter(func(b): return String(b.get_meta("row_kind", "")) in ["option", "copy"])
	if rows.is_empty():
		runner._problem("OPTION ROWS MISSING", "an option pick is open ('%s': %s) but the action panel has no live rows for it" % [caption.left(60), ", ".join(PackedStringArray(labels))], "optmiss" + caption.left(40))
		return false
	var still_open := func() -> bool:
		if not m.copy_pick_active:
			return false
		return (m.option_pick_labels as Array) == labels if is_opt else true
	# Forced: try to get out of it first.
	if back < 0 and rng.randf() < SKIP_PROBE_CHANCE:
		if not await _skip_probes(still_open, "option pick '" + caption.left(60) + "'"):
			return true
	# Optional: sometimes answer with a back key.
	if back >= 0 and _mode != "mouse" and rng.randf() < 0.3:
		var keyname := "pad B"
		await _wait_nav_active()
		if _mode == "keys":
			keyname = "Backspace" if rng.randf() < 0.5 else "Escape"
			await _send_key(KEY_BACKSPACE if keyname == "Backspace" else KEY_ESCAPE)
		else:
			await _send_pad(JOY_BUTTON_B)
		for _i in 8:
			if not still_open.call():
				_log("REAL %s answered '%s' with %s" % [_mode, caption.left(50), keyname])
				return true
			await get_tree().process_frame
		_ignored("%s on optional option pick '%s'" % [keyname, caption.left(60)], "optback" + keyname)
		_close_pause_if_open()
	await _snap_option(caption)
	var b: BaseButton = rows[rng.randi() % rows.size()]
	_log("REAL %s option '%s' on '%s'" % [_mode, _btn_text(b), caption.left(50)])
	await _real_press(b, "option row '%s' ('%s')" % [_btn_text(b), caption.left(60)])
	return true


# ── Card selection screens ──

func _sel_state() -> String:
	var m = main
	var reorder_n: int = (m.pokedex_reorder_result as Array).size() if m.get("pokedex_reorder_result") != null else 0
	var ids: Array = []
	for c in m.trainer_discard_selected:
		ids.append(c.get_instance_id())
	return "%s|%d|%d|%s" % [str(m.selected_card_for_action.get_instance_id()) if m.selected_card_for_action != null else "-",
		m.trainer_discard_selected.size(), reorder_n, str(ids)]


func _real_selection() -> bool:
	var m = main
	var header: String = str(m.header_label.text)
	var pool: Array = (m.shown_selection_pool as Array).duplicate()
	var still_open := func() -> bool:
		return m.card_selection_mode_enabled and str(m.header_label.text) == header
	if not _count_attempt("real:" + header + "|" + str(pool.size())):
		return false
	var forced: bool = not m.cancel_button.is_visible_in_tree() and m.action_button.is_visible_in_tree()
	if forced and rng.randf() < SKIP_PROBE_CHANCE:
		if not await _skip_probes(still_open, "selection '" + header.left(60) + "'"):
			return true
	# View-only (DONE only).
	if not m.action_button.is_visible_in_tree():
		if m.cancel_button.is_visible_in_tree() and not m.cancel_button.disabled:
			await _real_press(m.cancel_button, "DONE on '%s'" % header.left(60))
			return true
		return false
	# Sometimes back out (exercises every cancel path) - by the back key on keys / pad.
	if m.cancel_button.is_visible_in_tree() and not m.cancel_button.disabled and rng.randf() < 0.12:
		if _mode == "mouse":
			await _real_press(m.cancel_button, "CANCEL on '%s'" % header.left(60))
			return true
		await _wait_nav_active()
		if _mode == "keys":
			await _send_key(KEY_BACKSPACE)
		else:
			await _send_pad(JOY_BUTTON_B)
		for _i in 8:
			if not still_open.call():
				return true
			await get_tree().process_frame
		_ignored("%s back on cancelable '%s'" % [_mode, header.left(60)], "selback" + _mode)
		if m.cancel_button.is_visible_in_tree():
			m.cancel_button.pressed.emit()
		return true
	var cards: Array = pool.filter(func(c): return c is Object and _card_node(c) != null)
	if cards.is_empty():
		return false
	cards.shuffle()
	if m.trainer_reorder_active:
		for c in cards:
			if not still_open.call():
				return true
			if c not in m.pokedex_reorder_result:
				await _real_click_card(c, true, header)
	elif m.trainer_discard_selection_active:
		var max_n: int = m.trainer_discard_cards_needed
		var min_n: int = max(0, m.multi_select_min())
		var want: int = rng.randi_range(min_n, max(min_n, max_n))
		for c in cards:
			if not still_open.call() or m.trainer_discard_selected.size() >= want:
				break
			if c not in m.trainer_discard_selected:
				await _real_click_card(c, true, header)
	else:
		# Single pick: a card that lights the action button.
		var picked := false
		for c in cards.slice(0, 6):
			if not still_open.call():
				return true
			if c == m.selected_card_for_action and not m.action_button.disabled:
				picked = true
				break
			await _real_click_card(c, false, header)
			if m.action_button.is_visible_in_tree() and not m.action_button.disabled:
				picked = true
				break
		if not picked:
			return false   # the signal answerer works it out
	if not still_open.call():
		return true
	if m.action_button.is_visible_in_tree() and not m.action_button.disabled:
		await _real_press(m.action_button, "'%s' on '%s'" % [str(m.action_button.text), header.left(60)])
		return true
	return false


## Clicks / walks to a selection card. `toggle`: a pick-several screen (keys press accept on it).
func _real_click_card(card, toggle: bool, header: String) -> void:
	if OS.has_environment("AUTOTEST_NAV_TRACE"): print("REALTRACE click ", _name(card), " toggle=", toggle)
	var before := _sel_state()
	var node: Control = _card_node(card)
	if node == null:
		return
	if main.selection_scroller != null and main.selection_scroller.is_ancestor_of(node):
		main.selection_scroller.ensure_control_visible(node)
		await get_tree().process_frame
		await get_tree().process_frame
	if _mode == "mouse":
		await _send_click(_screen_pos(node))
	else:
		if not await _nav_to(card, "card %s on '%s'" % [_name(card), header.left(50)]):
			_click(card)
			return
		# Single-pick screens select on move (Board_Nav); pick-several screens toggle on accept. A cursor that
		# arrives already ON the card (no move) has not picked it - a player presses A there, which picks it.
		if toggle or _sel_state() == before:
			await _send_accept()
	for _i in 4:
		await get_tree().process_frame
	if _sel_state() != before:
		return
	# Nothing happened. Does a plain (signal) click do anything? If so the real input was lost.
	_click(card)
	if _sel_state() != before:
		_ignored("%s on card %s in '%s'" % ["click" if _mode == "mouse" else _mode + " select", _name(card), header.left(60)], "card" + _mode + header.left(30))


func _card_node(card) -> Control:
	for root in [main.large_selection_container, main.small_selection_container]:
		if root == null or not root.is_visible_in_tree():
			continue
		var found := _find_card_display(root, card)
		if found != null:
			return found
	return null


func _find_card_display(node: Node, card) -> Control:
	for child in node.get_children():
		if child is CardDisplay and (child as CardDisplay).card_ref == card and (child as CardDisplay).is_visible_in_tree() \
				and (child as CardDisplay).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return child
		var f := _find_card_display(child, card)
		if f != null:
			return f
	return null


# ── Pressing a button for real ──

func _real_press(b: BaseButton, what: String) -> void:
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree() or b.disabled:
		return
	var hit := [false]
	var cb := func(): hit[0] = true
	b.pressed.connect(cb)
	if _mode == "mouse":
		await _send_click(_screen_pos(b))
		for _i in 6:
			if hit[0]:
				break
			await get_tree().process_frame
	else:
		# Two tries: an accept inside Board_Nav's ACCEPT_GRACE_MS after the cursor came back is ignored on purpose.
		for _try in 2:
			if hit[0] or not is_instance_valid(b) or not b.is_visible_in_tree():
				break
			if not await _nav_to(b, what):
				break
			await _send_accept()
			for _i in 6:
				if hit[0]:
					break
				await get_tree().process_frame
	if is_instance_valid(b) and b.pressed.is_connected(cb):
		b.pressed.disconnect(cb)
	if not hit[0]:
		_ignored("%s on %s" % ["click" if _mode == "mouse" else _mode, what], "press" + _mode + what.left(40))
		_close_pause_if_open()
		if is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()


func _attack_row_button(i: int) -> BaseButton:
	var panel: Control = main._player_action_panel
	if panel == null or not is_instance_valid(panel):
		return null
	var n := 0
	for b in main._all_buttons_under(panel):
		if String(b.get_meta("row_kind", "")) != "attack":
			continue
		if n == i:
			return b
		n += 1
	return null


# ── Board cursor (keys / pad) ──

func _nav() -> Node:
	return main.board_nav


## Walks the cursor onto `key` (a card object or a node). False = it can't get there (reported).
func _nav_to(key, what: String) -> bool:
	var bn := _nav()
	if bn == null:
		return false
	# The cursor stands down for a moment after animations; wait for it.
	# Real milliseconds, not frames: the settle windows are real-time and headless frames are very fast.
	var t0 := Time.get_ticks_msec()
	if OS.has_environment("AUTOTEST_NAV_TRACE"): print("REALTRACE nav_to ", what.left(40), " active=", bn._active(), " reason=", _nav_block_reason())
	while not bn._active():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 4000:
			input_stats["unreachable"] += 1
			runner._problem("NAV INACTIVE", "the board cursor never came up for %s (%s) [%s]" % [what, _mode, _nav_block_reason()], "navinactive" + what.left(40))
			return false
	# The first press only shows the ring.
	if not bn._ring_showing():
		await _send_dir(Vector2i.DOWN)
		for _i in 3:
			await get_tree().process_frame
	for _step in 40:
		var mode: String = bn._mode_now()
		var targets: Array = bn._targets(mode)
		var ti: int = bn._find(targets, key)
		if ti < 0:
			input_stats["unreachable"] += 1
			runner._problem("NAV UNREACHABLE", "%s is not a cursor stop (%s, mode '%s')" % [what, _mode, mode], "navnot" + what.left(50))
			return false
		var cur: int = bn._current(mode, targets)
		if OS.has_environment("AUTOTEST_NAV_TRACE"):
			print("NAVTRACE ", what.left(50), " mode=", mode, " n=", targets.size(), " cur=", cur, " ti=", ti, " ring=", bn._ring_showing(), " dev=", InputDevice.last)
		if cur == ti:
			return true
		var path := _nav_path(bn, targets, cur, ti)
		if path.is_empty():
			input_stats["unreachable"] += 1
			runner._problem("NAV UNREACHABLE", "no arrow / D-pad path reaches %s (%s, mode '%s')" % [what, _mode, mode], "navpath" + what.left(50))
			return false
		await _send_dir(path[0])
		for _i in 2:
			await get_tree().process_frame
	input_stats["unreachable"] += 1
	runner._problem("NAV UNREACHABLE", "40 cursor moves never landed on %s (%s)" % [what, _mode], "navloop" + what.left(50))
	return false


func _nav_block_reason() -> String:
	var m = main
	var r: Array = []
	if not bool(runner.real_input_now): r.append("real_input_now off")
	if m.game_is_over: r.append("game over")
	if m.msgbox_container.visible: r.append("msgbox")
	if m.coin_container.visible: r.append("coin")
	if m.animation_blocker.visible: r.append("animation_blocker")
	if m.player_turn_start_running: r.append("turn start")
	if m._anim_in_flight: r.append("anim_in_flight")
	if Time.get_ticks_msec() - int(m._last_anim_busy_ms) < int(m.INPUT_SETTLE_MS): r.append("settle")
	if m.is_zoomed: r.append("zoomed")
	if m.match_log_open: r.append("log")
	if m.pause_menu != null and is_instance_valid(m.pause_menu): r.append("pause")
	if m.opponent_blocker.visible: r.append("opponent_blocker(mode %s)" % _nav()._mode_now())
	if m.vfx_debugger_open(): r.append("vfx debugger")
	return ", ".join(PackedStringArray(r)) if not r.is_empty() else "none?"


## Real time (headless frames are very fast): until the board cursor is listening, at most 4 s.
func _wait_nav_active() -> void:
	var bn := _nav()
	if bn == null:
		return
	var t0 := Time.get_ticks_msec()
	while not bn._active() and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	while Time.get_ticks_msec() - int(bn._active_since_msec) < int(bn.ACCEPT_GRACE_MS) + 20 and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


func _nav_path(bn: Node, targets: Array, from: int, to: int) -> Array:
	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var prev := {from: null}
	var queue := [from]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to:
			break
		for d in dirs:
			var nx: int = bn._step(targets, cur, d)
			if nx >= 0 and not prev.has(nx):
				prev[nx] = [cur, d]
				queue.append(nx)
	if not prev.has(to):
		return []
	var path: Array = []
	var at := to
	while prev[at] != null:
		path.push_front(prev[at][1])
		at = prev[at][0]
	return path


func _send_accept() -> void:
	# Board_Nav ignores an accept this soon after the board came back (ACCEPT_GRACE_MS) - a person is never that fast.
	var bn := _nav()
	if bn != null:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - int(bn._active_since_msec) < int(bn.ACCEPT_GRACE_MS) + 20 and Time.get_ticks_msec() - t0 < 2000:
			await get_tree().process_frame
	if _mode == "pad":
		await _send_pad(JOY_BUTTON_A)
	else:
		await _send_key(KEY_SPACE if rng.randf() < 0.5 else KEY_ENTER)


func _send_dir(d: Vector2i) -> void:
	if _mode == "pad":
		var b := JOY_BUTTON_DPAD_LEFT
		if d == Vector2i.RIGHT: b = JOY_BUTTON_DPAD_RIGHT
		elif d == Vector2i.UP: b = JOY_BUTTON_DPAD_UP
		elif d == Vector2i.DOWN: b = JOY_BUTTON_DPAD_DOWN
		await _send_pad(b)
	else:
		var k := KEY_LEFT
		if d == Vector2i.RIGHT: k = KEY_RIGHT
		elif d == Vector2i.UP: k = KEY_UP
		elif d == Vector2i.DOWN: k = KEY_DOWN
		await _send_key(k)


# ── Trying to skip a forced prompt ──

## Returns false if a probe closed the prompt (reported), true if it held.
func _skip_probes(still_open: Callable, what: String) -> bool:
	var probes := ["backspace", "escape", "pad_b", "right_click", "click_off"]
	probes.shuffle()
	for p in probes.slice(0, 3):
		input_stats["probes"] += 1
		_real_hold(true)
		await _wait_nav_active()
		match p:
			"backspace": await _send_key(KEY_BACKSPACE)
			"escape": await _send_key(KEY_ESCAPE)
			"pad_b": await _send_pad(JOY_BUTTON_B)
			"right_click": await _send_click(_screen_center(), MOUSE_BUTTON_RIGHT)
			"click_off": await _send_click(_off_prompt_point())
		_real_release(true)
		for _i in 4:
			await get_tree().process_frame
		_close_pause_if_open()
		if not still_open.call():
			input_stats["skipped"] += 1
			runner._problem("FORCED PROMPT SKIPPED", "%s closed the forced %s without an answer" % [p, what], "skip" + p + what.left(50))
			return false
	return true


func _close_pause_if_open() -> void:
	if main.pause_menu != null and is_instance_valid(main.pause_menu):
		main._close_pause_menu()
	if main.forfeit_dialog != null and is_instance_valid(main.forfeit_dialog):
		main._close_forfeit_dialog()


## A spot on the board away from the prompt: the opponent's discard pile (never a choice target).
func _off_prompt_point() -> Vector2:
	var n: Control = main.opponent_discard_icon
	if n != null and n.is_visible_in_tree():
		return _screen_pos(n)
	return _screen_center() + Vector2(0, -300)


# ── Raw events ──

func _screen_pos(c: Control) -> Vector2:
	var p: Vector2 = c.get_global_transform_with_canvas() * (c.size * 0.5)
	return get_tree().root.get_final_transform() * p


func _screen_center() -> Vector2:
	return get_tree().root.get_final_transform() * (get_viewport().get_visible_rect().size * 0.5)


func _send_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		if pressed:
			ev.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _send_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _send_pad(btn: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = btn
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


# ── Small helpers ──

func _ignored(what: String, dedupe: String) -> void:
	input_stats["ignored"] += 1
	runner._problem("INPUT IGNORED", what, "ign" + dedupe)


## Live buttons in the player's action panel (rows), top to bottom.
func _panel_buttons(include_options: bool) -> Array:
	var out: Array = []
	var panel: Control = main._player_action_panel
	if panel == null or not is_instance_valid(panel):
		return out
	for b in main._all_buttons_under(panel):
		if b.is_visible_in_tree() and not b.disabled and not b.is_queued_for_deletion():
			if include_options or String(b.get_meta("row_kind", "")) not in ["option", "copy"]:
				out.append(b)
	return out


func _live_power_buttons() -> Array:
	var out: Array = _panel_buttons(false).filter(func(b): return String(b.get_meta("row_kind", "")) in ["power", "stadium"])
	for b in main._all_buttons_under(main.player_bench_container):
		if b.is_visible_in_tree() and not b.disabled:
			out.append(b)
	return out


func _btn_text(b: BaseButton) -> String:
	if b.has_meta("row_text"):
		return String(b.get_meta("row_text"))
	return str((b as Button).text) if b is Button else str(b.name)


## AUDIT 2026-11-17 (dev): AUTOTEST_OPTION_SNAP=1 on a WINDOWED run saves the screen while an option pick is up,
## to check the rows' layout by eye. Up to 6 per run.
var _option_snaps := 0
func _snap_option(caption: String) -> void:
	if not OS.has_environment("AUTOTEST_OPTION_SNAP") or _option_snaps >= 6 or DisplayServer.get_name() == "headless":
		return
	for _i in 6:
		await get_tree().process_frame
	_option_snaps += 1
	var img: Image = get_viewport().get_texture().get_image()
	var path := "user://autotest/option_snap_%d.png" % _option_snaps
	img.save_png(path)
	print("OPTION SNAP: ", ProjectSettings.globalize_path(path), " - ", caption.left(60))
