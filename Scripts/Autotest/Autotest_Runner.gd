extends Node

# ============================================================
# AUTOTEST RUNNER — CPU vs bot matches, back to back
# ============================================================
# Run (from the project folder):
#   Godot_v4.6.1-stable_win64_console.exe --headless --fixed-fps 60 --path . res://Scenes/Autotest/Autotest_Runner.tscn -- --matches=20
# Watch it play instead: leave out --headless and --fixed-fps, and add --watch.
#
# Options (all after the lone "--"):
#   --matches=N         how many matches to play (default 10)
#   --seed=N            base RNG seed; match i uses seed+i, so any match can be replayed alone (default: time)
#   --sets=a,b          only build decks from these sets (default: every set)
#   --cards=uid,uid     force these cards into every deck (with their evolution lines) to test them directly
#   --turn-limit=N      abort a match that reaches this turn (default 120; it counts each player's turn) — catches stall loops
#   --timescale=N       Engine.time_scale (default 4; --watch uses 1)
#   --watch             normal-looking speed so a person can follow it
#   --stack=UID         stacked deck for the BOT: its opening hand is UID's whole evolution line plus the Energy its
#                       untested attack costs (the rest of that Energy is drawn next; the Prizes get filler). Use to
#                       reach expensive attacks a shuffled deck rarely powers up, e.g. --stack=ex15-100 --matches=10
#   --strict            also check for duplicated cards after EVERY in-game message, and name the message where a
#                       duplicate first appears (use with --replay to pin down a CARD DUPLICATED find)
#   --reset-coverage    start the cumulative coverage file from zero
#   --replay=RUN:N      replay match N of an earlier run exactly (same decks + seed), e.g.
#                       --replay=2026-10-09T11-17-10:16   (RUN is the folder name under autotest/runs/)
#
# Output: %APPDATA%/Godot/app_userdata/Pokemon_TCG_Legacy/autotest/
#   runs/<stamp>/summary.txt   — what broke, grouped, with the seed that reproduces each problem
#   runs/<stamp>/problems.txt  — every problem in full: context, recent log lines, script backtrace
#   runs/<stamp>/matches.jsonl — one line per match: decks, result, turns, events
#   coverage.json              — cumulative use counts across every run (drives deck building)
#   coverage_missing.txt       — every attack / Power / Trainer / Special Energy never used yet
#   cpu_usage.json / cpu_usage_report.txt — CUMULATIVE: for every Trainer, Special Energy, Power and attack the CPU
#                                COULD use on a turn, how often it DID. Flags always / rarely / never used.
#
# The save file is never touched: matches run in test_match_mode, which already skips every save write.

const MATCH_SCENE := "res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn"
const BotScript := preload("res://Scripts/Autotest/Autotest_Bot.gd")
const OUT_DIR := "user://autotest/"
const STALL_SECONDS := 240.0       # game-time seconds with no visible change = soft-lock
const MATCH_MAX_SECONDS := 7200.0  # game-time hard cap per match
const LOG_TAIL := 40

var opt_matches := 10
var opt_seed := 0
var opt_sets: Array = []
var opt_cards: Array = []
var opt_turn_limit := 120
var opt_timescale := 4.0
var opt_watch := false
var opt_stack := ""
var opt_strict := false
var replay_record: Dictionary = {}
var replay_run := ""
var replay_prior_events: Array = []   # events of the matches before the replayed one (to rebuild its coverage)

var cards: Dictionary = {}        # uid -> metadata
var by_name: Dictionary = {}      # card name -> [uid]
var basic_energy_for: Dictionary = {}  # type -> uid
var coverage: Dictionary = {}     # key -> count  (cumulative)
var run_dir := ""
var power_names: Dictionary = {}
var cpu_usage: Dictionary = {}         # key -> {"offered": turns it was available, "used": turns the CPU used it}
var _cpu_offered: Dictionary = {}      # this CPU turn
var _cpu_used: Dictionary = {}
var _cpu_turn_open := false  # activatable Power names (from _power_dispatch)

var match_scene: PackedScene
var current_main: Node = null
var current_bot: Node = null
var match_index := -1
var match_seed := 0
var match_done := false
var match_result := ""
var match_events: Array = []
var match_messages: Array = []
var match_problems: Array = []
var match_reported: Dictionary = {}   # de-dupe key -> true, per match
var originals: Array = [{}, {}]       # side -> {instance_id: card}
var _sig := ""
var _sig_time := 0.0
var _match_time := 0.0
var _last_checked_turn := -1

var all_problems: Array = []
var results := {"win": 0, "loss": 0, "draw": 0, "aborted": 0}

var _logger: _Capture = null
var _bot_tail: Array = []


# ───────────────────────────── log capture ─────────────────────────────
# Godot 4.5+ Logger: every engine/script error and every print line arrives here, so a runtime error in
# any effect script is caught with its backtrace and tied to the match, turn and bot action it happened in.
class _Capture extends Logger:
	var mutex := Mutex.new()
	var errors: Array = []
	var tail: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var bt := ""
		for b in script_backtraces:
			bt += b.format() + "\n"
		mutex.lock()
		errors.append({"function": function, "file": file, "line": line, "code": code,
			"rationale": rationale, "type": error_type, "backtrace": bt})
		mutex.unlock()

	func _log_message(message: String, _error: bool) -> void:
		mutex.lock()
		tail.append(message.strip_edges())
		if tail.size() > 60:
			tail.pop_front()
		mutex.unlock()

	func take_errors() -> Array:
		mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		mutex.unlock()
		return out

	func get_tail() -> Array:
		mutex.lock()
		var out := tail.duplicate()
		mutex.unlock()
		return out


# ───────────────────────────── entry ─────────────────────────────

func _ready() -> void:
	_parse_args()
	_logger = _Capture.new()
	OS.add_logger(_logger)
	Engine.time_scale = opt_timescale
	if not opt_watch:
		GameState.card_match_animation_speed = GameState.SKIP_MULTIPLIER
		GameState.text_letter_delay = 0.0
	run_dir = OUT_DIR + "runs/" + Time.get_datetime_string_from_system().replace(":", "-") + "/"
	DirAccess.make_dir_recursive_absolute(run_dir)
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "decks")
	_load_cards()
	_load_coverage()
	if FileAccess.file_exists(OUT_DIR + "cpu_usage.json"):
		var cu = JSON.parse_string(FileAccess.get_file_as_string(OUT_DIR + "cpu_usage.json"))
		if cu is Dictionary:
			cpu_usage = cu
	if not replay_record.is_empty():
		# The bot weights its attacks by coverage, so a replay needs the coverage exactly as it was at that match:
		# the run's starting coverage plus every event of the matches before it.
		var start_path := OUT_DIR + "runs/" + replay_run + "/coverage_start.json"
		if FileAccess.file_exists(start_path):
			coverage = JSON.parse_string(FileAccess.get_file_as_string(start_path))
			for e in replay_prior_events:
				_count_event(String(e))
		else:
			push_error("AUTOTEST: no coverage_start.json for that run — the replay may drift from the original")
	else:
		_write_json(run_dir + "coverage_start.json", coverage)
	match_scene = load(MATCH_SCENE)
	print("AUTOTEST: %d cards loaded, %d matches, base seed %d, output %s" % [cards.size(), opt_matches, opt_seed, ProjectSettings.globalize_path(run_dir)])
	_run_all.call_deferred()


func _parse_args() -> void:
	opt_seed = int(Time.get_unix_time_from_system()) % 1000000
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var k := kv[0]
		var v := kv[1] if kv.size() > 1 else ""
		match k:
			"matches": opt_matches = int(v)
			"seed": opt_seed = int(v)
			"sets": opt_sets = Array(v.split(",", false))
			"cards": opt_cards = Array(v.to_lower().split(",", false))
			"turn-limit": opt_turn_limit = int(v)
			"timescale": opt_timescale = float(v)
			"watch":
				opt_watch = true
				opt_timescale = 1.0
			"strict": opt_strict = true
			"stack":
				opt_stack = v.to_lower()
				opt_cards = [opt_stack]
			"reset-coverage":
				DirAccess.remove_absolute(OUT_DIR + "coverage.json")
			"replay":
				var run := v.get_slice(":", 0)
				var n := int(v.get_slice(":", 1))
				var path := OUT_DIR + "runs/" + run + "/matches.jsonl"
				for line in FileAccess.get_file_as_string(path).split("\n", false):
					var rec = JSON.parse_string(line)
					if rec is Dictionary and int(rec.get("match", 0)) == n:
						replay_record = rec
					elif rec is Dictionary and int(rec.get("match", 0)) < n:
						replay_prior_events.append_array(rec.get("events", []))
					replay_run = run
				if replay_record.is_empty():
					push_error("AUTOTEST: no match %d in %s" % [n, path])
				else:
					opt_matches = 1
					opt_seed = int(replay_record["seed"])


func _run_all() -> void:
	for i in opt_matches:
		await _play_match(i)
	_write_summary()
	print("AUTOTEST: done — see ", ProjectSettings.globalize_path(run_dir + "summary.txt"))
	OS.remove_logger(_logger)
	GameState.autotest = null
	get_tree().quit()


# ───────────────────────────── one match ─────────────────────────────

func _play_match(i: int) -> void:
	match_index = i
	match_seed = opt_seed + i
	seed(match_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	match_done = false
	match_result = ""
	match_events = []
	match_messages = []
	match_problems = []
	match_reported = {}
	originals = [{}, {}]
	_bot_tail = []
	_match_time = 0.0
	_sig = ""
	_sig_time = 0.0
	_last_checked_turn = -1
	_logger.take_errors()

	var p_deck: Array = replay_record["player_deck"] if not replay_record.is_empty() else _build_deck(rng)
	var o_deck: Array = replay_record["opponent_deck"] if not replay_record.is_empty() else _build_deck(rng)
	var p_path := OUT_DIR + "decks/player.json"
	var o_path := OUT_DIR + "decks/opponent.json"
	_write_json(p_path, p_deck)
	_write_json(o_path, o_deck)

	GameState.autotest = self
	GameState.autotest_player_deck_path = p_path
	GameState.autotest_opponent_deck_path = o_path
	GameState.test_match_mode = true
	GameState.current_opponent_name = "TEST OPPONENT"
	GameState.current_opponent_deck = "TEST"
	GameState.current_opponent_map = ""
	GameState.last_battled_opponent_entry = GameState.build_test_opponent_data()
	GameState.clear_match_series()

	print("AUTOTEST: ===== match %d / %d (seed %d) =====" % [i + 1, opt_matches, match_seed])
	current_main = match_scene.instantiate()
	if not current_main.has_method("perform_attack"):
		# The match script failed to compile — every match would hang. Stop with the reason on screen.
		print("AUTOTEST FATAL: the match script did not load (a Parse Error above). Stopping.")
		_logger.take_errors()
		get_tree().quit(1)
		await get_tree().create_timer(3600).timeout
		return
	add_child(current_main)
	current_bot = BotScript.new()
	current_bot.name = "AutotestBot"
	add_child(current_bot)
	current_bot.setup(current_main, self, match_seed)
	await get_tree().process_frame
	_snapshot_originals()
	if power_names.is_empty():
		current_main.powers_and_bodies._ensure_power_dispatch_ready()
		for k in current_main.powers_and_bodies._power_dispatch.keys():
			power_names[k] = true

	while not match_done:
		await get_tree().process_frame
		_watch(get_process_delta_time())

	_drain_errors()
	_cpu_close_turn()
	var turns: int = current_main.turn_number if is_instance_valid(current_main) else -1
	if results.has(match_result):
		results[match_result] += 1
	var rec := {"match": i + 1, "seed": match_seed, "result": match_result, "turns": turns,
		"player_deck": p_deck, "opponent_deck": o_deck, "problems": match_problems.size(),
		"events": match_events}
	_append_line(run_dir + "matches.jsonl", JSON.stringify(rec))
	_write_match_log(i + 1, rec)
	print("AUTOTEST: match %d -> %s after %d turns, %d problem(s)" % [i + 1, match_result, turns, match_problems.size()])

	if is_instance_valid(current_bot):
		current_bot.queue_free()
	if is_instance_valid(current_main):
		current_main.game_is_over = true
		current_main.queue_free()
	current_main = null
	current_bot = null
	GameState.autotest = null
	_save_coverage()
	for _f in 3:
		await get_tree().process_frame


## A readable record of one match: both decks, then every in-game message (the Caps Lock match log) with whose
## turn it was, plus the BOT's own button presses and any problems — for reviewing card interactions and choices.
func _write_match_log(n: int, rec: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("MATCH %d  seed %d  result %s  turns %s" % [n, rec["seed"], rec["result"], rec["turns"]])
	for side in ["player_deck", "opponent_deck"]:
		var parts: Array = []
		for e in rec[side]:
			parts.append("%dx %s (%s)" % [e["count"], cards.get(e["id"], {}).get("name", "?"), e["id"]])
		lines.append(("BOT DECK: " if side == "player_deck" else "CPU DECK: ") + ", ".join(parts))
	lines.append("")
	var last_turn := -999
	for entry in match_messages:
		if entry[0] != last_turn:
			last_turn = entry[0]
			lines.append("---- turn %d ----" % last_turn)
		lines.append(("  CPU | " if entry[1] else "  BOT | ") + String(entry[2]))
	for p in match_problems:
		lines.append("!! PROBLEM [%s] turn %s: %s" % [p["kind"], p["turn"], String(p["detail"]).get_slice("\n", 0)])
	DirAccess.make_dir_recursive_absolute(run_dir + "logs")
	var f := FileAccess.open(run_dir + "logs/match_%03d.txt" % n, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


# ───────────────────────────── CPU usage (offered vs used) ─────────────────────────────

## Hook: start of every CPU turn, after its draw. Closes the previous turn, then records what the CPU could play now.
func cpu_turn_start(m) -> void:
	_cpu_close_turn()
	_cpu_turn_open = true
	for c in m.opponent_hand:
		var st: String = c.metadata.get("supertype", "")
		if st == "Trainer":
			if m.trainer_effects.validate_trainer_can_be_played(c, true) == "":
				_cpu_offered["trainer|" + c.uid] = true
		elif st == "Energy" and "Special" in c.metadata.get("subtypes", []):
			for p in m.card_ops.get_all_pokemon_in_play(true):
				if bool(m.special_energy_effects.can_attach_to(c, p).get("allowed", true)):
					_cpu_offered["energy|" + c.uid] = true
					break
	for p in m.card_ops.get_all_pokemon_in_play(true):
		for e in m.powers_and_bodies.usable_powers_for(p):
			_cpu_offered["power|" + p.uid + "|" + String(e["ability"].get("name", ""))] = true


## Hook: start of the CPU's attack phase — every attack its Active could legally use right now.
func cpu_attack_phase(m) -> void:
	var mon = m.opponent_active_pokemon
	if mon == null or m.turn_number <= 1 or mon.special_condition in ["Paralyzed", "Asleep"]:
		return
	for a in m.get_attacks_for_card(mon):
		var an: String = a.get("name", "")
		if m.is_attack_disabled(mon, an) or not m.check_attack_requirements(a, mon) or m.attack_effects.attack_unusable_reason(a, mon) != "":
			continue
		_cpu_offered["attack|" + mon.uid + "|" + an] = true


func _cpu_close_turn() -> void:
	if not _cpu_turn_open:
		return
	_cpu_turn_open = false
	var keys: Dictionary = _cpu_offered.duplicate()
	keys.merge(_cpu_used)   # drawn and played in the same turn = it was available
	var used_attack := "(no attack)"
	for k in _cpu_used:
		if k.begins_with("attack|"):
			used_attack = k.get_slice("|", 2)
	for k in keys:
		if not cpu_usage.has(k):
			cpu_usage[k] = {"offered": 0, "used": 0}
		cpu_usage[k]["offered"] = int(cpu_usage[k]["offered"]) + 1
		if _cpu_used.has(k):
			cpu_usage[k]["used"] = int(cpu_usage[k]["used"]) + 1
		elif k.begins_with("attack|"):
			# What the CPU did INSTEAD of this attack — the evidence for judging whether skipping it was right.
			if not cpu_usage[k].has("lost_to"):
				cpu_usage[k]["lost_to"] = {}
			cpu_usage[k]["lost_to"][used_attack] = int(cpu_usage[k]["lost_to"].get(used_attack, 0)) + 1
	_cpu_offered = {}
	_cpu_used = {}


func _write_cpu_usage_report() -> void:
	var by_kind := {"trainer": [], "energy": [], "power": [], "attack": []}
	for k in cpu_usage:
		var kind: String = k.get_slice("|", 0)
		if by_kind.has(kind):
			by_kind[kind].append(k)
	var s := PackedStringArray()
	s.append("CPU USAGE — cumulative over every autotest run. 'offered' = CPU turns it could have used it; 'used' = turns it did.")
	s.append("ALWAYS = used on 90%+ of chances (fine for Bill; suspicious for situational cards).  RARE = under 10%.  NEVER = 0.")
	s.append("Only cards offered at least 5 times are judged.")
	s.append("POWERS: 'offered' means the Power's button was usable — not that its own needs were met. Form changes need another")
	s.append("form in the deck, Baby Evolution needs the evolution in hand, Reactive Shift needs React Energy... A NEVER here can be")
	s.append("legit; confirm with --cards=<power card>,<partner cards> (verified 2026-10-09: Form Change, Temperamental Weather,")
	s.append("Baby Evolution, Reactive Shift all used by the CPU once their partners were in the deck).")
	for kind in ["trainer", "energy", "power", "attack"]:
		var always: Array = []
		var rare: Array = []
		var never: Array = []
		var tested := 0
		for k in by_kind[kind]:
			var o := int(cpu_usage[k]["offered"])
			var u := int(cpu_usage[k]["used"])
			if o < 5:
				continue
			tested += 1
			var r := float(u) / o
			var uid: String = k.get_slice("|", 1)
			var label := "%5.1f%%  %3d/%-3d  %s (%s)%s" % [r * 100.0, u, o, cards.get(uid, {}).get("name", "?"), uid,
				("  — " + k.get_slice("|", 2)) if kind in ["attack", "power"] else ""]
			if cpu_usage[k].has("lost_to"):
				var lt: Dictionary = cpu_usage[k]["lost_to"]
				var names := lt.keys()
				names.sort_custom(func(a, b): return lt[a] > lt[b])
				var bits: Array = []
				for nm in names.slice(0, 3):
					bits.append("%s x%d" % [nm, lt[nm]])
				label += "   [instead: " + ", ".join(bits) + "]"
			if u == 0:
				never.append([r, label])
			elif r >= 0.9:
				always.append([r, label])
			elif r < 0.1:
				rare.append([r, label])
		for grp in [always, rare]:
			grp.sort_custom(func(a, b): return a[0] > b[0])
		s.append("")
		s.append("==== %s — %d judged ====" % [kind.to_upper(), tested])
		for pair in [["ALWAYS USED", always], ["RARELY USED", rare], ["NEVER USED", never]]:
			s.append("-- %s (%d)" % [pair[0], pair[1].size()])
			for e in pair[1]:
				s.append("   " + e[1])
	var f := FileAccess.open(OUT_DIR + "cpu_usage_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(s))
	f.close()


## --stack: the names in the target's line (the bot steers Energy / evolutions onto them) and the target attack name.
var stack_line_names: Array = []
var stack_attack_name := ""


## --stack: called by Main.setup_player() on the bot's freshly shuffled deck (before the opening hand and Prizes are
## drawn, both from the FRONT). Order: [0..6] opening hand = the target's line + Energy for its untested attack,
## [7..12] filler for the Prizes, then the rest of that Energy, then everything else.
func stack_player_deck(deck: Array) -> void:
	if opt_stack == "" or not cards.has(opt_stack):
		return
	# The target's evolution line, Basic first, using the copies actually in this deck.
	var line_uids: Array = []
	var u := opt_stack
	var guard := 0
	while u != "" and guard < 4:
		line_uids.push_front(u)
		var from: String = cards[u].get("evolvesFrom", "")
		u = ""
		if from != "":
			for c in deck:
				if c.metadata.get("name", "") == from:
					u = c.uid.to_lower()
					break
		guard += 1
	# The untested attack (else the most expensive one) and the Energy it costs.
	var target_atk: Dictionary = {}
	for a in cards[opt_stack].get("attacks", []):
		if int(coverage.get("attack|" + opt_stack + "|" + a.get("name", ""), 0)) == 0:
			target_atk = a
			break
	if target_atk.is_empty():
		for a in cards[opt_stack].get("attacks", []):
			if a.get("cost", []).size() > target_atk.get("cost", []).size():
				target_atk = a
	stack_line_names = []
	for lu in line_uids:
		stack_line_names.append(cards[lu].get("name", ""))
	stack_attack_name = target_atk.get("name", "")
	var energy_uids: Array = []
	for cost in target_atk.get("cost", []):
		var want: String = basic_energy_for.get(cost, "") if cost != "Colorless" else ""
		energy_uids.append(want)   # "" = any Energy card
	var picked: Array = []
	var take = func(match_uid: String) -> void:
		for c in deck:
			if c in picked:
				continue
			if match_uid == "" and c.metadata.get("supertype", "") == "Energy":
				picked.append(c); return
			if match_uid != "" and c.uid.to_lower() == match_uid.to_lower():
				picked.append(c); return
	for lu in line_uids:
		take.call(lu)
	for eu in energy_uids:
		take.call(eu)
	var hand: Array = picked.slice(0, 7)
	var late: Array = picked.slice(7)
	var rest: Array = deck.filter(func(c): return c not in picked)
	var filler: Array = rest.slice(0, 7 - hand.size()) + rest.slice(7 - hand.size(), 13 - hand.size())
	var tail: Array = rest.slice(13 - hand.size())
	var ordered: Array = hand + filler.slice(0, 7 - hand.size()) + filler.slice(7 - hand.size()) + late + tail
	deck.clear()
	deck.append_array(ordered)
	print("AUTOTEST: stacked deck for ", cards[opt_stack].get("name", ""), " — attack '", target_atk.get("name", ""), "', hand ", hand.map(func(c): return c.metadata.get("name", "")), ", then ", late.size(), " more Energy after the Prizes")


## Called by game_end_logic() instead of moving to the outro.
func on_match_over(_m: Node, result: String, is_draw: bool) -> void:
	match_result = "draw" if is_draw else ("win" if result == "win" else "loss")
	match_done = true


func _abort(reason: String) -> void:
	if match_done:
		return
	match_result = "aborted"
	match_done = true
	print("AUTOTEST: match aborted — ", reason)


# ───────────────────────────── hooks from the game ─────────────────────────────

## Coverage + event log. kind: attack | trainer | power | energy.
func note(kind: String, uid: String, name: String, is_opponent: bool) -> void:
	var key := kind + "|" + uid + ("|" + name if kind in ["attack", "power"] else "")
	coverage[key] = int(coverage.get(key, 0)) + 1
	if is_opponent and _cpu_turn_open and (kind != "energy" or "Special" in cards.get(uid, {}).get("subtypes", [])):
		_cpu_used[key] = true
	var turn = current_main.turn_number if is_instance_valid(current_main) else -1
	match_events.append("T%s %s %s %s %s" % [turn, "CPU" if is_opponent else "BOT", kind, uid, name])


## Every in-game message, in full (the game's own log keeps only the last 250).
func log_message(text: String, turn: int, opp_turn: bool) -> void:
	match_messages.append([turn, opp_turn, text])
	if opt_strict and is_instance_valid(current_main) and not originals[0].is_empty():
		for side in [false, true]:
			var seen: Dictionary = {}
			for pair in _zones(current_main, side):
				if not (pair[0] is Object):
					continue
				var id: int = pair[0].get_instance_id()
				# Mid-retreat the Pokémon is briefly both Active and Benched — an in-play/in-play pair is that, not a bug.
				if seen.has(id) and not (_in_play_zone(seen[id]) and _in_play_zone(pair[1])):
					_problem("CARD DUPLICATED (strict)", "%s's %s in %s AND %s — first seen at message: \"%s\"" % ["CPU" if side else "BOT", _cname(pair[0]), seen[id], pair[1], text], "sdup" + str(id))
				seen[id] = pair[1]


func _in_play_zone(z: String) -> bool:
	return z.begins_with("active") or z.begins_with("bench")


func bot_log(s: String) -> void:
	_bot_tail.append(s)
	if _bot_tail.size() > 25:
		_bot_tail.pop_front()


func report_stuck(kind: String, detail: String) -> void:
	_problem(kind, detail + " — " + _state_flags(current_main) + " action_btn visible=%s disabled=%s text=%s" % [current_main.action_button.visible, current_main.action_button.disabled, current_main.action_button.text], kind + detail.left(80))
	_abort(kind)


# ───────────────────────────── watchdog + invariants ─────────────────────────────

func _watch(delta: float) -> void:
	if match_done or not is_instance_valid(current_main):
		return
	_drain_errors()
	var m = current_main
	_match_time += delta
	if _match_time > MATCH_MAX_SECONDS:
		_problem("MATCH TIME LIMIT", "Match ran %d game-seconds without ending" % int(_match_time), "timelimit")
		_abort("time limit")
		return
	if m.turn_number >= opt_turn_limit:
		_problem("TURN LIMIT", "Match reached turn %d — a stall loop, or two decks that can't finish each other" % m.turn_number, "turnlimit")
		_abort("turn limit")
		return
	var s := _signature(m)
	if s != _sig:
		_sig = s
		_sig_time = 0.0
	else:
		_sig_time += delta
		if _sig_time > STALL_SECONDS:
			_problem("SOFT-LOCK", "Nothing changed for %d game-seconds. State: %s" % [int(STALL_SECONDS), _state_flags(m)], "softlock" + _state_flags(m))
			_abort("soft-lock")
			return
	# Once per turn, while the player's turn is idle, check every card is where it should be.
	if not m.opponents_turn_active and m.turn_number != _last_checked_turn and current_bot._board_idle():
		_last_checked_turn = m.turn_number
		_check_cards(m)


func _signature(m) -> String:
	var hp := 0
	for side in [false, true]:
		for p in m.card_ops.get_all_pokemon_in_play(side):
			hp += p.current_hp
	return "%d|%s|%d|%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%s" % [m.turn_number, m.opponents_turn_active,
		m.player_hand.size(), m.opponent_hand.size(), m.player_deck.size(), m.opponent_deck.size(),
		m.player_discard_pile.size(), m.opponent_discard_pile.size(), m.player_prize_cards.size() + m.opponent_prize_cards.size(), hp,
		m.msgbox_container.visible, m.card_selection_mode_enabled, m.header_label.text, current_bot.last_action]


func _state_flags(m) -> String:
	var flags: Array = []
	for f in ["opponents_turn_active", "card_selection_mode_enabled", "trainer_pokemon_selection_active",
			"trainer_deck_search_active", "trainer_discard_selection_active", "yes_no_prompt_active",
			"trainer_reorder_active", "knockout_bench_selection_active", "prize_card_selection_active",
			"forced_switch_selection_active", "card_attach_mode_active", "evolution_mode_active",
			"retreat_mode_active", "retreat_bench_selection_active", "special_attack_selection_active",
			"power_menu_active", "_anim_in_flight", "game_is_over"]:
		if m.get(f):
			flags.append(f)
	if m.msgbox_container.visible: flags.append("msgbox")
	if m.coin_container.visible: flags.append("coin")
	if m.attack_buttons_container.visible: flags.append("button_row")
	return "turn %d, flags [%s], header '%s'" % [m.turn_number, ", ".join(flags), m.header_label.text]


## Every card a side owns, as [card, zone] pairs.
func _zones(m, side: bool) -> Array:
	var z: Array = []
	var pre := "opponent_" if side else "player_"
	for zone in ["deck", "hand", "discard_pile", "prize_cards", "tickled_set_aside"]:
		for c in m.get(pre + zone):
			z.append([c, zone])
	for p in m.card_ops.get_all_pokemon_in_play(side):
		_collect_pokemon(p, z, "active" if p == m.get(pre + "active_pokemon") else "bench")
	if m.current_stadium_card != null and m.current_stadium_owner_is_opponent == side:
		z.append([m.current_stadium_card, "stadium"])
	return z


func _collect_pokemon(p, z: Array, where: String) -> void:
	if p == null:
		return
	z.append([p, where])
	var holder := where + ":" + str(p.metadata.get("name", "?"))
	for field in ["attached_energies", "attached_pre_evolutions", "attached_cards"]:
		for c in p.get(field):
			if c is Object and "attached_energies" in c and c != p and field == "attached_cards" and c.current_location in ["active", "bench"]:
				_collect_pokemon(c, z, where)
			else:
				z.append([c, holder + "." + field])
	if p.secret_plan_card != null: z.append([p.secret_plan_card, holder + ".secret_plan_card"])
	if p.shapeshift_form_card != null: z.append([p.shapeshift_form_card, holder + ".shapeshift_form_card"])


func _snapshot_originals() -> void:
	for side in [false, true]:
		for pair in _zones(current_main, side):
			if pair[0] is Object:
				originals[int(side)][pair[0].get_instance_id()] = pair[0]


func _check_cards(m) -> void:
	var seen_any: Dictionary = {}
	for side in [false, true]:
		var where: Dictionary = {}
		for pair in _zones(m, side):
			var c = pair[0]
			if not (c is Object):
				continue
			var id: int = c.get_instance_id()
			if not where.has(id):
				where[id] = []
			where[id].append(pair[1])
			seen_any[id] = true
		var side_name := "CPU" if side else "BOT"
		for id in where:
			var c = instance_from_id(id)
			if where[id].size() > 1:
				_problem("CARD DUPLICATED", "%s's %s is in %d places at once: %s" % [side_name, _cname(c), where[id].size(), ", ".join(where[id])], "dup" + str(id))
			elif not originals[int(side)].has(id) and not originals[int(not side)].has(id) 					and not bool(c.get("is_bench_token")) and not bool(c.get("secret_plan_face_down")):
				_problem("UNKNOWN CARD", "%s has a card object that was never in either deck: %s (in %s)" % [side_name, _cname(c), where[id][0]], "unk" + _cname(c))
		for p in m.card_ops.get_all_pokemon_in_play(side):
			if p.current_hp > p.get_max_hp() or p.current_hp < 0:
				_problem("HP OUT OF RANGE", "%s's %s has %d / %d HP" % [side_name, _cname(p), p.current_hp, p.get_max_hp()], "hp" + str(p.get_instance_id()))
	for side in [false, true]:
		for id in originals[int(side)]:
			if not seen_any.has(id):
				var c = originals[int(side)][id]
				_problem("CARD MISSING", "%s's %s is in no zone (lost, or legitimately removed from the game?)" % ["CPU" if side else "BOT", _cname(c)], "miss" + str(id))


# ───────────────────────────── problems ─────────────────────────────

func _drain_errors() -> void:
	for e in _logger.take_errors():
		var kind := "SCRIPT ERROR" if e["type"] == Logger.ERROR_TYPE_SCRIPT else ("WARNING" if e["type"] == Logger.ERROR_TYPE_WARNING else "ENGINE ERROR")
		var where := "%s:%d (%s)" % [String(e["file"]).get_file(), e["line"], e["function"]]
		var msg := String(e["rationale"]) if String(e["rationale"]) != "" else String(e["code"])
		_problem(kind, where + " — " + msg + ("\n" + e["backtrace"] if e["backtrace"] != "" else ""), kind + where + msg)


# Problems already logged for the user as Manual Fix (Issue_Log #376 / #377) — not reported again.
const KNOWN_IGNORED := []

func _problem(kind: String, detail: String, dedupe: String) -> void:
	if match_reported.has(dedupe):
		return
	for k in KNOWN_IGNORED:
		if k in detail:
			return
	match_reported[dedupe] = true
	var m = current_main
	var ctx := {"kind": kind, "detail": detail, "match": match_index + 1, "seed": match_seed,
		"turn": m.turn_number if is_instance_valid(m) else -1,
		"whose_turn": ("CPU" if m.opponents_turn_active else "BOT") if is_instance_valid(m) else "?",
		"bot_recent": _bot_tail.duplicate(), "log_tail": _logger.get_tail().slice(-LOG_TAIL),
		"group": kind + " :: " + detail.get_slice("\n", 0).left(160)}
	match_problems.append(ctx)
	all_problems.append(ctx)
	print("AUTOTEST PROBLEM [%s] match %d turn %s: %s" % [kind, match_index + 1, ctx["turn"], detail.get_slice("\n", 0)])


# ───────────────────────────── decks ─────────────────────────────

func _load_cards() -> void:
	var d := DirAccess.open("res://Card_Set_Data/")
	for f in d.get_files():
		if not f.ends_with(".json") or f == "pack_prices.json":
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://Card_Set_Data/" + f))
		if not (data is Array):
			continue
		for c in data:
			if not (c is Dictionary) or not c.has("id"):
				continue
			cards[c["id"]] = c
			var n: String = c.get("name", "")
			if not by_name.has(n):
				by_name[n] = []
			by_name[n].append(c["id"])
			if c.get("supertype", "") == "Energy" and "Basic" in c.get("subtypes", []):
				var t := n.replace(" Energy", "")
				if not basic_energy_for.has(t):
					basic_energy_for[t] = c["id"]
	# Darkness / Metal were only ever Special Energy in these sets — use those as the "basic" source.
	for t in ["Darkness", "Metal"]:
		if not basic_energy_for.has(t) and by_name.has(t + " Energy"):
			basic_energy_for[t] = by_name[t + " Energy"][0]


func _in_sets(uid: String) -> bool:
	return opt_sets.is_empty() or uid.get_slice("-", 0) in opt_sets


func _keys_for(uid: String) -> Array:
	var c: Dictionary = cards[uid]
	var keys: Array = []
	match c.get("supertype", ""):
		"Pokémon":
			for a in c.get("attacks", []):
				if a.get("name", "") == "Genetic Memory":
					continue   # it never runs under its own name — it lists the pre-evolutions' attacks, which are counted
				keys.append("attack|" + uid + "|" + a.get("name", ""))
			for ab in c.get("abilities", []):
				# Only ACTIVATED powers can be "used" — a Poké-Body that shares a name with one (Submerge) isn't a Power.
				if power_names.has(ab.get("name", "")) and ab.get("type", "") not in ["Poké-Body", "Poke-Body"]:
					keys.append("power|" + uid + "|" + ab.get("name", ""))
		"Trainer":
			keys.append("trainer|" + uid)
		"Energy":
			if "Special" in c.get("subtypes", []):
				keys.append("energy|" + uid)
	return keys


## Average uses per testable key — lower means "test this next".
func _coverage_score(uid: String) -> float:
	var keys := _keys_for(uid)
	if keys.is_empty():
		return 999.0
	var total := 0
	for k in keys:
		total += int(coverage.get(k, 0))
	return float(total) / keys.size()


func _least_covered(pool: Array, rng: RandomNumberGenerator, take: int) -> Array:
	var scored: Array = []
	for uid in pool:
		scored.append([_coverage_score(uid) + rng.randf() * 0.9, uid])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for s in scored:
		if out.size() >= take:
			break
		out.append(s[1])
	return out


func _pre_evolution(uid: String, rng: RandomNumberGenerator) -> String:
	var from: String = cards[uid].get("evolvesFrom", "")
	if from == "" or not by_name.has(from):
		return ""
	var options: Array = by_name[from]
	var same_set := options.filter(func(u): return u.get_slice("-", 0) == uid.get_slice("-", 0))
	var pick_from: Array = same_set if not same_set.is_empty() else options
	return pick_from[rng.randi() % pick_from.size()]


func _add_line(deck: Dictionary, uid: String, rng: RandomNumberGenerator, copies: int) -> void:
	var u := uid
	var depth := 0
	while u != "" and depth < 4:
		deck[u] = mini(4, int(deck.get(u, 0)) + copies)
		var stage: Array = cards[u].get("subtypes", [])
		if "Basic" in stage or cards[u].get("supertype", "") != "Pokémon":
			break
		u = _pre_evolution(u, rng)
		copies += 1   # more of the lower stages, like a real deck
		depth += 1


## Non-Colorless Energy types this card's attacks ask for.
func _cost_types(uid: String) -> Dictionary:
	var t: Dictionary = {}
	for a in cards[uid].get("attacks", []):
		for e in a.get("cost", []):
			if e != "Colorless" and e != "Free":
				t[e] = true
	return t


## True when every attack's Energy can be paid from `allowed` (plus Colorless).
func _fits_types(uid: String, allowed: Dictionary) -> bool:
	for t in _cost_types(uid):
		if not allowed.has(t):
			return false
	return true


## A type-coherent 60-card deck built around the least-tested cards:
##   1. the least-tested Pokémon (with its evolution line) fixes the deck's Energy types (at most 2);
##   2. two more least-tested Pokémon lines whose attacks those types can pay for;
##   3. low-coverage Basics of those types, so the deck can open and keep benching;
##   4. 8 least-tested Trainers (2 each) and 2 least-tested Special Energies (2 each);
##   5. basic Energy of the deck's types to 60 (roughly 20+).
## --cards forces specific cards in first; their types then lead.
func _build_deck(rng: RandomNumberGenerator) -> Array:
	var deck: Dictionary = {}
	var pokemon: Array = []
	var trainers: Array = []
	var specials: Array = []
	for uid in cards:
		if not _in_sets(uid):
			continue
		var c: Dictionary = cards[uid]
		match c.get("supertype", ""):
			"Pokémon": pokemon.append(uid)
			"Trainer": trainers.append(uid)
			"Energy":
				if "Special" in c.get("subtypes", []):
					specials.append(uid)

	var allowed: Dictionary = {}
	var leads: Array = []
	for uid in opt_cards:
		if cards.has(uid):
			leads.append(uid)
	if leads.is_empty():
		leads = _least_covered(pokemon, rng, 1)
	for uid in leads:
		_add_line(deck, uid, rng, 2)
		for t in _cost_types(uid):
			if allowed.size() < 3 or allowed.has(t):   # up to 3 types: some attacks cost three different Energy
				allowed[t] = true
	if allowed.is_empty():
		var ts := basic_energy_for.keys()
		allowed[ts[rng.randi() % ts.size()]] = true

	var fitting := pokemon.filter(func(u): return _fits_types(u, allowed) and not deck.has(u))
	var extra_lines := 2 if opt_cards.is_empty() else 1
	for uid in _least_covered(fitting, rng, 10).slice(0, extra_lines):
		_add_line(deck, uid, rng, 2)
	var fitting_basics := fitting.filter(func(u): return "Basic" in cards[u].get("subtypes", []))
	for uid in _least_covered(fitting_basics, rng, 10):
		if _count(deck) >= 18:
			break
		deck[uid] = mini(4, int(deck.get(uid, 0)) + 2)
	# Every deck must be able to open: at least 8 Basic Pokémon (any type if none of the deck's types fit). A deck with
	# none made draw_opening_hand mulligan forever and froze the whole run.
	var all_basics := pokemon.filter(func(u): return "Basic" in cards[u].get("subtypes", []))
	var pool_b: Array = fitting_basics if not fitting_basics.is_empty() else all_basics
	var guard := 0
	while _basic_count(deck) < 8 and guard < 20:
		guard += 1
		var b: String = pool_b[rng.randi() % pool_b.size()]
		deck[b] = mini(4, int(deck.get(b, 0)) + 2)
	for uid in _least_covered(trainers, rng, 8):
		deck[uid] = mini(4, int(deck.get(uid, 0)) + 2)
	for uid in _least_covered(specials, rng, 2):
		deck[uid] = mini(4, int(deck.get(uid, 0)) + 2)

	var tlist: Array = allowed.keys().filter(func(t): return basic_energy_for.has(t))
	if tlist.is_empty():
		tlist = ["Fire"]
	while _count(deck) > 40:
		# Keep room for at least 20 Energy — trim the most-copied non-Energy card.
		var worst := ""
		for uid in deck:
			var keep_basic: bool = _basic_count(deck) <= 8 and "Basic" in cards[uid].get("subtypes", []) and cards[uid].get("supertype", "") == "Pokémon"
			if not keep_basic and cards[uid].get("supertype", "") != "Energy" and (worst == "" or deck[uid] > deck[worst]):
				worst = uid
		deck[worst] -= 1
		if deck[worst] <= 0:
			deck.erase(worst)
	var i := 0
	while _count(deck) < 60:
		var e: String = basic_energy_for[tlist[i % tlist.size()]]
		deck[e] = int(deck.get(e, 0)) + 1
		i += 1
	var out: Array = []
	for uid in deck:
		out.append({"id": uid, "count": deck[uid]})
	return out


func _basic_count(deck: Dictionary) -> int:
	var n := 0
	for uid in deck:
		if cards[uid].get("supertype", "") == "Pokémon" and "Basic" in cards[uid].get("subtypes", []):
			n += int(deck[uid])
	return n


func _count(deck: Dictionary) -> int:
	var n := 0
	for k in deck:
		n += int(deck[k])
	return n


# ───────────────────────────── files + reports ─────────────────────────────

func _load_coverage() -> void:
	var p := OUT_DIR + "coverage.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			coverage = d


## Re-counts one logged event line ("T<turn> <side> <kind> <uid> <name>") into coverage.
func _count_event(e: String) -> void:
	var parts := e.split(" ", true, 4)
	if parts.size() < 4:
		return
	var kind := parts[2]
	var key := kind + "|" + parts[3] + ("|" + (parts[4] if parts.size() > 4 else "") if kind in ["attack", "power"] else "")
	coverage[key] = int(coverage.get(key, 0)) + 1


func _save_coverage() -> void:
	if not replay_record.is_empty():
		return   # a replay never changes the cumulative coverage
	_write_json(OUT_DIR + "cpu_usage.json", cpu_usage)
	_write_json(OUT_DIR + "coverage.json", coverage)


func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _append_line(path: String, line: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()


func _cname(c) -> String:
	if c == null or not (c is Object) or not ("metadata" in c):
		return str(c)
	return "%s (%s)" % [c.metadata.get("name", "?"), c.uid]


func _write_summary() -> void:
	if replay_record.is_empty():
		_write_cpu_usage_report()
	var s := PackedStringArray()
	s.append("AUTOTEST SUMMARY — %s" % Time.get_datetime_string_from_system())
	s.append("Matches: %d   bot wins %d / CPU wins %d / draws %d / aborted %d   (base seed %d)" % [opt_matches,
		results["win"], results["loss"], results["draw"], results["aborted"], opt_seed])
	s.append("")
	# Problems grouped.
	var groups: Dictionary = {}
	for p in all_problems:
		var g: String = p["group"]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(p)
	var order := groups.keys()
	order.sort_custom(func(a, b): return groups[a].size() > groups[b].size())
	s.append("PROBLEMS: %d total, %d distinct" % [all_problems.size(), groups.size()])
	for g in order:
		var first: Dictionary = groups[g][0]
		s.append("  [%dx] %s" % [groups[g].size(), g])
		s.append("        first: match %d, seed %d, turn %s (%s's turn) — replay with --replay=%s:%d" % [first["match"], first["seed"], first["turn"], first["whose_turn"], run_dir.trim_suffix("/").get_file(), first["match"]])
	s.append("")
	# Coverage.
	var universe := {"attack": 0, "power": 0, "trainer": 0, "energy": 0}
	var used := {"attack": 0, "power": 0, "trainer": 0, "energy": 0}
	var missing := PackedStringArray()
	for uid in cards:
		for k in _keys_for(uid):
			var kind: String = k.get_slice("|", 0)
			universe[kind] += 1
			if int(coverage.get(k, 0)) > 0:
				used[kind] += 1
			else:
				missing.append(k + "   " + cards[uid].get("name", ""))
	s.append("COVERAGE (cumulative across all runs):")
	for kind in ["attack", "power", "trainer", "energy"]:
		var pct: float = 100.0 * used[kind] / max(1, universe[kind])
		s.append("  %-8s %5d / %5d used at least once  (%.1f%%)" % [kind, used[kind], universe[kind], pct])
	var f := FileAccess.open(run_dir + "summary.txt", FileAccess.WRITE)
	f.store_string("\n".join(s))
	f.close()
	var mf := FileAccess.open(OUT_DIR + "coverage_missing.txt", FileAccess.WRITE)
	mf.store_string("\n".join(missing))
	mf.close()
	# Full detail.
	var d := PackedStringArray()
	for p in all_problems:
		d.append("==================================================================")
		d.append("[%s] match %d  seed %d  turn %s  (%s's turn)" % [p["kind"], p["match"], p["seed"], p["turn"], p["whose_turn"]])
		d.append(p["detail"])
		d.append("--- bot's last actions:")
		for l in p["bot_recent"]:
			d.append("   " + l)
		d.append("--- last log lines:")
		for l in p["log_tail"]:
			d.append("   " + l)
	var pf := FileAccess.open(run_dir + "problems.txt", FileAccess.WRITE)
	pf.store_string("\n".join(d))
	pf.close()
	print("\n".join(s))
