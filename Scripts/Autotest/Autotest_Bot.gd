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
		_smart_trainers = 0
	_actions_this_turn += 1
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
	# ISSUE #375 (smart bot v2, 2026-10-10): a sparring partner that plays like a sensible person, so the CPU's
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
			_click(c)
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
