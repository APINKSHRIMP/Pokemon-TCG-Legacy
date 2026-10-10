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
#   --real              the CPU plays every REAL opponent in turn (deck, sprite, Prize count, match_effects from
#                       NPC_and_Opponent_Data); the bot plays decks from user://Player_Decks. Writes balance_report.txt.
#   --bot=smart         the bot plays a sensible plan (evolve, attach to what needs it, best attack) instead of randomly
#   --stress            the bot's deck is an extreme recipe (1 Basic + 59 Energy, Trainer flood, 60 Basics, ...)
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
const CpuWeights = preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_Weights.gd")
var opt_tune := false              # --tune: one self-play tuning job (Tools/cpu_tuner.py) — quiet, no coverage/log writes
var opt_weights_path := ""         # --weights=<abs path>: CPU weight multipliers for this job
var opt_result_path := ""          # --result=<abs path>: one JSON line per match, then {"done": true}
var opt_synergy_path := ""        # --synergy=<abs path>: learned synergy table for this job ("" = none)
var opt_learned_path := ""        # --learned=<abs path>: learned matchup table for this job
var _ex_open := {}                 # tune mode: the CPU turn exchange being measured (see _ex_begin)
var _ex_list: Array = []           # tune mode: finished exchanges this match
var opt_explore := 0.0             # --explore=<0..1>: random free fetch choices (synergy exploration jobs)
var opt_worker := "0"              # --worker=<id>: keeps parallel jobs' scratch files apart
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
var _cpu_turn_open := false
var _cpu_ko_attacks: Array = []        # attacks this CPU turn that were a guaranteed Knock Out
var _cpu_had_energy := false
var _cpu_attempted := false            # the CPU began an attack (even one that then failed to Confusion)           # CPU held Energy at the start of its turn
var _cpu_needed_energy := false        # ...and something in play still needed Energy  # activatable Power names (from _power_dispatch)

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
	if opt_tune:
		run_dir = OUT_DIR + "tuner/work/w" + opt_worker + "/"
		var wm := {}
		if opt_weights_path != "" and FileAccess.file_exists(opt_weights_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(opt_weights_path))
			if parsed is Dictionary:
				wm = parsed
		CpuWeights.set_multipliers(wm)
		var syn := {}
		if opt_synergy_path != "" and FileAccess.file_exists(opt_synergy_path):
			var ps = JSON.parse_string(FileAccess.get_file_as_string(opt_synergy_path))
			if ps is Dictionary:
				syn = ps
		CpuWeights.set_synergy(syn)   # tune jobs never read the shipped table: the tuner decides
		CpuWeights.explore_rate = opt_explore
		var lt := {}
		if opt_learned_path != "" and FileAccess.file_exists(opt_learned_path):
			var pl = JSON.parse_string(FileAccess.get_file_as_string(opt_learned_path))
			if pl is Dictionary:
				lt = pl
		CpuWeights.set_learned(lt)
	DirAccess.make_dir_recursive_absolute(run_dir)
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "decks")
	_load_cards()
	if opt_real:
		_load_real_entries()
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
	elif not opt_tune:
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
			"tune":
				opt_tune = true
				opt_real = true
				opt_bot_smart = true
			"weights": opt_weights_path = v
			"result": opt_result_path = v
			"worker": opt_worker = v
			"synergy": opt_synergy_path = v
			"explore": opt_explore = float(v)
			"learned": opt_learned_path = v
			"real": opt_real = true
			"bot": opt_bot_smart = (v == "smart")
			"stress": opt_stress = true
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
	if opt_tune:
		_append_line(opt_result_path, JSON.stringify({"done": true}))
		OS.remove_logger(_logger)
		GameState.autotest = null
		get_tree().quit()
		return
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
	CpuWeights.seed_explore(match_seed * 7919 + 13)
	_ex_open = {}
	_ex_list = []
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

	var p_deck: Array = []
	var o_deck: Array = []
	var opp_data: Dictionary = {}
	if not replay_record.is_empty():
		p_deck = replay_record["player_deck"]
		o_deck = replay_record["opponent_deck"]
		opp_data = replay_record.get("opponent_data", {})
	else:
		if opt_real and not real_entries.is_empty():
			var entry: Dictionary = real_entries[(match_seed if opt_tune else i) % real_entries.size()]
			o_deck = _read_deck_file(AssetLookup.deck_path(entry["deck"]))
			opp_data = real_opponent_data_for(entry)
			p_deck = _read_deck_file(player_deck_files[rng.randi() % player_deck_files.size()]) if not player_deck_files.is_empty() else _build_deck(rng)
		else:
			p_deck = _build_deck(rng)
			o_deck = _build_deck(rng)
		if opt_stress:
			p_deck = _stress_deck(i, rng)
	current_opponent_label = String(opp_data.get("name", "TEST OPPONENT"))
	current_match_effects = opp_data.get("match_effects", [])
	GameState.autotest_opponent_data = opp_data
	var p_path := (run_dir if opt_tune else OUT_DIR + "decks/") + "player.json"
	var o_path := (run_dir if opt_tune else OUT_DIR + "decks/") + "opponent.json"
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
		"events": match_events, "opponent": current_opponent_label, "opponent_data": GameState.autotest_opponent_data}
	if opt_real:
		if not balance.has(current_opponent_label):
			balance[current_opponent_label] = {"games": 0, "cpu_wins": 0, "bot_wins": 0, "turns": 0}
		var bl: Dictionary = balance[current_opponent_label]
		bl["games"] += 1
		bl["turns"] += maxi(0, turns)
		if match_result == "loss": bl["cpu_wins"] += 1
		elif match_result == "win": bl["bot_wins"] += 1
	if opt_tune:
		var m = current_main
		var tr := {"seed": match_seed, "result": match_result, "turns": turns,
			"cpu_prizes_left": m.opponent_prize_cards.size() if is_instance_valid(m) else -1,
			"bot_prizes_left": m.player_prize_cards.size() if is_instance_valid(m) else -1,
			"opponent": current_opponent_label,
			"problems": match_problems.map(func(p): return String(p["kind"])),
			"cpu_cards": _cpu_cards_used(m) if is_instance_valid(m) else [],
			"ex": _ex_finish(m)}
		_append_line(opt_result_path, JSON.stringify(tr))
	else:
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
	if not opt_tune:
		_save_coverage()
	for _f in 3:
		await get_tree().process_frame


# ── Tune mode: EXCHANGES for the matchup learner (Scripts/Autotest/cpu_learner.py) ──
# One per CPU turn: from its start to the start of the CPU's next turn, the damage + Prizes swung each way.
func _ex_damage(m, side: bool) -> int:
	var d := 0
	for p in m.card_ops.get_all_pokemon_in_play(side):
		d += maxi(0, p.get_max_hp() - p.current_hp)
	return d


func _ex_begin(m) -> void:
	_ex_open = {}
	var me = m.opponent_active_pokemon
	var foe = m.player_active_pokemon
	if me == null or foe == null:
		return
	var ahead: int = m.player_prize_cards.size() - m.opponent_prize_cards.size()
	_ex_open = {"me": String(me.uid).to_lower(), "foe": String(foe.uid).to_lower(), "atk": "",
		"rel": m.cpu_ai.cpu_rel_features(me, foe),
		"foe_bench": m.player_bench.map(func(b): return String(b.uid).to_lower()),
		"state": ["ahead" if ahead > 0 else ("behind" if ahead < 0 else "even"), "early" if m.turn_number <= 6 else "late"],
		"dp": _ex_damage(m, false), "dc": _ex_damage(m, true),
		"pc": m.opponent_prize_cards.size(), "pp": m.player_prize_cards.size()}


func _ex_close(m) -> void:
	if _ex_open.is_empty() or not is_instance_valid(m):
		_ex_open = {}
		return
	var o := _ex_open
	_ex_open = {}
	var cpu_took: int = int(o["pc"]) - m.opponent_prize_cards.size()
	var bot_took: int = int(o["pp"]) - m.player_prize_cards.size()
	var y := (float(_ex_damage(m, false) - int(o["dp"])) + 80.0 * cpu_took) / 100.0 \
		- (float(_ex_damage(m, true) - int(o["dc"])) + 80.0 * bot_took) / 100.0
	o.erase("dp"); o.erase("dc"); o.erase("pc"); o.erase("pp")
	o["y"] = snappedf(y, 0.01)
	_ex_list.append(o)


func _ex_finish(m) -> Array:
	if is_instance_valid(m):
		_ex_close(m)
	return _ex_list


## Tune mode: every distinct CPU card that reached play this match (in play, attached, or in the discard pile) —
## the raw material for the tuner's synergy table.
func _cpu_cards_used(m) -> Array:
	var seen := {}
	for pair in _zones(m, true):
		if pair[1] in ["deck", "hand", "prize_cards"]:
			continue
		var c = pair[0]
		if c is Object and "uid" in c:
			seen[String(c.uid).to_lower()] = true
	return seen.keys()


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
	_cpu_close_turn()   # judge the PREVIOUS turn before its KO list / Energy snapshot are reset
	if opt_tune:
		_ex_close(m)
		_ex_begin(m)
	_cpu_ko_attacks = []
	# Only BASIC Energy counts: holding a situational Special Energy (Scramble while ahead, R Energy with no Rocket's Pokémon) is fine.
	_cpu_had_energy = m.opponent_hand.any(func(c): return c.metadata.get("supertype", "") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	_cpu_needed_energy = false
	for p in m.card_ops.get_all_pokemon_in_play(true):
		if m.powers_and_bodies._cpu_unmet_energy(p) > 0 and not p.has_effect("ex5_energy_lock"):   # Crystal Beam: no Energy may be attached
			_cpu_needed_energy = true
	cpu_turn_t0 = Time.get_ticks_usec()
	cpu_turn_ctx = "%s active, %d in hand, %d benched" % [m.opponent_active_pokemon.metadata.get("name", "?") if m.opponent_active_pokemon != null else "none", m.opponent_hand.size(), m.opponent_bench.size()]
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
	# Checked HERE (after the CPU's Energy step, same turn): held Energy, something needed it, attached none.
	var still_has_energy: bool = m.opponent_hand.any(func(c): return c.metadata.get("supertype", "") == "Energy" and "Basic" in c.metadata.get("subtypes", []) and m.card_ops.get_all_pokemon_in_play(true).any(func(p): return not p.has_effect("ex5_energy_lock") and m.powers_and_bodies._cpu_unmet_energy(p) > 0))
	if still_has_energy and _cpu_needed_energy and not m.opponent_energy_played_this_turn:
		_problem("CPU DECISION: NO ENERGY", "held Energy and had a Pokémon that needed it, but attached none", "noe" + str(match_index) + str(m.turn_number))
	_cpu_ko_attacks = []   # this attack phase only - never a stale list from an earlier turn
	var mon = m.opponent_active_pokemon
	if mon == null or m.turn_number <= 1 or mon.special_condition in ["Paralyzed", "Asleep"]:
		return
	for a in m.get_attacks_for_card(mon):
		var an: String = a.get("name", "")
		if m.is_attack_disabled(mon, an) or not m.check_attack_requirements(a, mon) or m.attack_effects.attack_unusable_reason(a, mon) != "":
			continue
		_cpu_offered["attack|" + mon.uid + "|" + an] = true
		var foe = m.player_active_pokemon
		if foe != null:
			var rng_d: Dictionary = m.attack_effects.estimate_attack_damage_range(a, mon, foe)
			var mn := int(rng_d.get("min", 0))
			if mn > 0:
				mn = int(m.calculate_final_damage(mn, mon.get_effective_types(), foe, mon).get("damage", mn))
			if mn >= foe.current_hp:
				_cpu_ko_attacks.append(an)


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
	# ISSUE #375 smartness checks — flagged as "CPU DECISION" for review, with the CPU's own reasoning in problems.txt.
	var offered_attacks: Array = _cpu_offered.keys().filter(func(k): return k.begins_with("attack|"))
	# The CPU won the game on this turn, or began an attack (Confusion, a "can't attack X" block): not a missed KO.
	var cpu_won: bool = match_done and match_result == "loss"
	if not _cpu_ko_attacks.is_empty() and used_attack not in _cpu_ko_attacks and not cpu_won and not (used_attack == "(no attack)" and _cpu_attempted):
		_problem("CPU DECISION: MISSED KO", "used %s when %s was a guaranteed Knock Out" % [used_attack, ", ".join(_cpu_ko_attacks)], "mko" + str(match_index) + str(_cpu_ko_attacks))
	elif not offered_attacks.is_empty() and used_attack == "(no attack)" and not _cpu_attempted and is_instance_valid(current_main) and not current_main.game_is_over:
		_problem("CPU DECISION: SKIPPED ATTACK", "could use %s but ended the turn without attacking" % ", ".join(offered_attacks.map(func(k): return k.get_slice("|", 2))), "skip" + str(match_index) + str(offered_attacks))

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
	_cpu_attempted = false


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


# ───────────────────────────── real opponents (--real) ─────────────────────────────

var opt_real := false
var opt_bot_smart := false
var opt_stress := false
var real_entries: Array = []          # every opponent entry in the game: {label, deck, sprite, prize_cards, match_effects}
var player_deck_files: Array = []     # user://Player_Decks/*.json — the editable copies + the player's own decks
var current_opponent_label := ""
var current_match_effects: Array = []
var balance: Dictionary = {}          # label -> {"games", "cpu_wins", "bot_wins", "turns"}

## Every opponent entry in NPC_and_Opponent_Data (Characters/*.json + All_NPC_Constant_Data.json): anything with a "deck".
func _load_real_entries() -> void:
	real_entries = []
	var files: Array = ["res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"]
	var d := DirAccess.open("res://NPC_and_Opponent_Data/Characters")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				files.append("res://NPC_and_Opponent_Data/Characters/" + f)
	for f in files:
		var data = JSON.parse_string(FileAccess.get_file_as_string(f))
		_walk_entries(data, "")
	var seen: Dictionary = {}
	var unique: Array = []
	for e in real_entries:
		var key: String = e["label"] + "|" + e["deck"] + "|" + JSON.stringify(e["match_effects"])
		if not seen.has(key):
			seen[key] = true
			unique.append(e)
	real_entries = unique
	var pd := DirAccess.open("user://Player_Decks")
	if pd != null:
		for f in pd.get_files():
			if f.ends_with(".json"):
				player_deck_files.append("user://Player_Decks/" + f)
	print("AUTOTEST: --real — ", real_entries.size(), " opponent entries, ", player_deck_files.size(), " player decks")


func _walk_entries(o, parent_key: String) -> void:
	if o is Dictionary:
		if o.has("deck") and o["deck"] is String and String(o["deck"]) != "":
			var label := String(o.get("name", parent_key))
			if label == "": label = String(o["deck"])
			real_entries.append({"label": label, "deck": o["deck"], "sprite": o.get("sprite", ""),
				"prize_cards": int(o.get("prize_cards", 6)), "match_effects": o.get("match_effects", [])})
		for k in o:
			_walk_entries(o[k], String(k) if not (o[k] is Array) else parent_key)
	elif o is Array:
		for v in o:
			_walk_entries(v, parent_key)


func _read_deck_file(path: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Array else []


## The opponent data the match should load (Main.load_opponent_data_by_name reads it). Empty = the plain test opponent.
func real_opponent_data_for(entry: Dictionary) -> Dictionary:
	return {"name": entry["label"], "deck": entry["deck"], "sprite": entry["sprite"], "music": "",
		"prize_cards": entry["prize_cards"], "coin_reward": "", "sleeve": "", "match_effects": entry["match_effects"], "restrictions": {}}


# ───────────────────────────── stress decks (--stress) ─────────────────────────────

## Extreme player decks that reach edge cases normal decks never do.
func _stress_deck(i: int, rng: RandomNumberGenerator) -> Array:
	var basics: Array = []
	var stage2: Array = []
	var trainers: Array = []
	for uid in cards:
		var c: Dictionary = cards[uid]
		match c.get("supertype", ""):
			"Pokémon":
				if "Basic" in c.get("subtypes", []): basics.append(uid)
				elif "Stage 2" in c.get("subtypes", []): stage2.append(uid)
			"Trainer": trainers.append(uid)
	var e: String = basic_energy_for.get(["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting"][rng.randi() % 6], "base1-98")
	var deck: Dictionary = {}
	var add = func(uid: String, n: int) -> void: deck[uid] = int(deck.get(uid, 0)) + n
	var recipe: int = i % 5
	match recipe:
		0:   # one Basic + 59 Energy — deck-out race, nothing to play
			add.call(basics[rng.randi() % basics.size()], 1); add.call(e, 59)
		1:   # Trainer flood — 4 Basics, 56 Trainers
			for _k in 4: add.call(basics[rng.randi() % basics.size()], 1)
			for _k in 56: add.call(trainers[rng.randi() % trainers.size()], 1)
		2:   # 60 Basic Pokémon — benches always full, no Energy
			for _k in 60: add.call(basics[rng.randi() % basics.size()], 1)
		3:   # Stage 2s with no Stage 1s — dead hands
			for _k in 4: add.call(basics[rng.randi() % basics.size()], 1)
			for _k in 24: add.call(stage2[rng.randi() % stage2.size()], 1)
			add.call(e, 32)
		4:   # a single Energy card
			for _k in 30: add.call(basics[rng.randi() % basics.size()], 1)
			for _k in 29: add.call(trainers[rng.randi() % trainers.size()], 1)
			add.call(e, 1)
	print("AUTOTEST: --stress recipe ", ["one Basic + 59 Energy", "Trainer flood", "60 Basics", "Stage 2s without Stage 1s", "one Energy"][recipe])
	var out: Array = []
	for uid in deck:
		out.append({"id": uid, "count": deck[uid]})
	return out


# ───────────────────────────── rule-check oracles ─────────────────────────────

var oracle_pending: Dictionary = {}
var oracle_stats := {"damage": [0, 0], "status": [0, 0], "draw": [0, 0]}   # [checked, failed]

## Hook: Attack_Effects.begin_attack — snapshot what the attack should change.
func attack_begin(attack: Dictionary, attacker, defender, is_opponent: bool) -> void:
	oracle_pending = {}
	if is_opponent:
		_cpu_attempted = true
		if not _ex_open.is_empty() and _ex_open["atk"] == "":
			_ex_open["atk"] = String(attacker.uid).to_lower() + "|" + String(attack.get("name", "")).to_lower()
		if _cpu_turn_open:
			_cpu_used["attack|" + attacker.uid + "|" + String(attack.get("name", ""))] = true
	if not is_instance_valid(current_main) or attacker == null or defender == null:
		return
	var m = current_main
	var text: String = String(attack.get("text", "")).strip_edges().to_lower()
	var dmg_str: String = String(attack.get("damage", "")).strip_edges()
	var kind := ""
	if text == "" and dmg_str.is_valid_int() and int(dmg_str) > 0:
		kind = "damage"
	elif RegEx.create_from_string("^the defending pok.mon is now (asleep|confused|paralyzed|poisoned|burned)\\.$").search(text) != null:
		kind = "status"
	elif RegEx.create_from_string("^draw ([0-9]+) cards?\\.$").search(text) != null:
		kind = "draw"
	if kind == "":
		return
	oracle_pending = {"kind": kind, "attack": attack, "attacker": attacker, "defender": defender, "is_opp": is_opponent,
		"hp_before": defender.current_hp, "clean": _oracle_clean(attacker, defender),
		"hand_before": (m.opponent_hand if is_opponent else m.player_hand).size(),
		"deck_before": (m.opponent_deck if is_opponent else m.player_deck).size(), "text": text}


## A board where nothing else can change the result: no Tools / attached Trainers, no Stadium, no match rules, no
## temporary effects, no Pokémon with any Power or Body anywhere, no Special Condition on the attacker.
func _oracle_clean(attacker, defender) -> bool:
	var m = current_main
	if m.current_stadium_card != null or not current_match_effects.is_empty():
		return false
	if attacker.special_condition != "" or attacker.is_blind:
		return false
	for p in [attacker, defender]:
		if not p.attached_cards.is_empty() or not p.active_effects.is_empty() or p.is_invincible \
				or p.shielded_damage_threshold > 0 or p.defender_count > 0 or p.pluspower_count > 0 or p.damage_reduction_next_turn > 0:
			return false
		# Any other set flag (Scrunch, Swords Dance, Focus Energy, Tail Wag, Giant Growth...) or a Special Energy
		# (Aqua / Magma Energy +10...) can change the damage — the oracle only judges plain board states.
		if _flags(p) not in ["none", p.special_condition]:
			return false
		for e in p.attached_energies:
			if "Special" in e.metadata.get("subtypes", []):
				return false
	for side in [false, true]:
		for p in m.card_ops.get_all_pokemon_in_play(side):
			if not p.metadata.get("abilities", []).is_empty():
				return false
	return true


## Hook: Attack_Effects.end_attack — compare what happened with what the card text says.
func attack_end() -> void:
	if oracle_pending.is_empty() or not is_instance_valid(current_main):
		oracle_pending = {}
		return
	var o := oracle_pending
	oracle_pending = {}
	var m = current_main
	var att = o["attacker"]
	var dfd = o["defender"]
	var in_play: bool = dfd in m.card_ops.get_all_pokemon_in_play(not o["is_opp"])
	match o["kind"]:
		"damage":
			if not o["clean"]:
				return
			var base := int(String(o["attack"].get("damage", "0")))
			var types: Array = att.get_effective_types()
			var exp := base
			for w in dfd.metadata.get("weaknesses", []):
				if w.get("type", "") in types:
					var v := String(w.get("value", "×2"))
					exp = exp * 2 if ("×" in v or "x" in v) else exp + int(v.replace("+", ""))
			for r in dfd.metadata.get("resistances", []):
				if r.get("type", "") in types:
					exp = maxi(0, exp + int(String(r.get("value", "-30"))))
			oracle_stats["damage"][0] += 1
			var dealt: int = (o["hp_before"] - dfd.current_hp) if in_play else o["hp_before"]
			var ok: bool = (dealt == mini(exp, o["hp_before"])) if in_play else (exp >= o["hp_before"])
			if not ok:
				oracle_stats["damage"][1] += 1
				_problem("ORACLE: DAMAGE", "%s's %s did %d to %s (%d HP before) — the card says %d (base %d, after Weakness/Resistance). Flags: %s / %s" % [
					_cname(att), o["attack"].get("name", ""), dealt, _cname(dfd), o["hp_before"], exp, base, _flags(att), _flags(dfd)],
					"oracle-dmg" + str(att.uid) + o["attack"].get("name", ""))
		"status":
			if not in_play or not dfd.metadata.get("abilities", []).is_empty():
				return
			var want: String = RegEx.create_from_string("is now (asleep|confused|paralyzed|poisoned|burned)").search(o["text"]).get_string(1).capitalize()
			oracle_stats["status"][0] += 1
			var has: bool = dfd.special_condition == want if want in ["Asleep", "Confused", "Paralyzed"] else (dfd.is_poisoned if want == "Poisoned" else dfd.is_burned)
			if not has and not o["clean"]:
				return   # something on the board may have stopped it — only judge clean boards
			if not has:
				oracle_stats["status"][1] += 1
				_problem("ORACLE: STATUS", "%s's %s should leave %s %s — it isn't. Flags: %s" % [_cname(att), o["attack"].get("name", ""), _cname(dfd), want, _flags(dfd)],
					"oracle-st" + str(att.uid) + o["attack"].get("name", ""))
		"draw":
			var n := int(RegEx.create_from_string("draw ([0-9]+)").search(o["text"]).get_string(1))
			var hand: Array = m.opponent_hand if o["is_opp"] else m.player_hand
			var got: int = hand.size() - int(o["hand_before"])
			var want_n: int = mini(n, int(o["deck_before"]))
			oracle_stats["draw"][0] += 1
			if got != want_n:
				oracle_stats["draw"][1] += 1
				_problem("ORACLE: DRAW", "%s's %s drew %d — the card says %d (deck had %d)" % [_cname(att), o["attack"].get("name", ""), got, n, o["deck_before"]],
					"oracle-dr" + str(att.uid) + o["attack"].get("name", ""))


## Every non-default flag on a card, for triaging an oracle mismatch.
func _flags(c) -> String:
	var out: Array = []
	for prop in c.get_property_list():
		var nm: String = prop["name"]
		if prop["type"] == TYPE_BOOL and c.get(nm) == true and nm not in ["placed_on_field_this_turn"]:
			out.append(nm)
	if not c.active_effects.is_empty():
		out.append("effects:" + str(c.active_effects.keys()))
	if c.special_condition != "":
		out.append(c.special_condition)
	return ", ".join(out) if not out.is_empty() else "none"


# ───────────────────────────── extra per-turn checks ─────────────────────────────

func _extra_checks(m) -> void:
	for side in [false, true]:
		var nm := "CPU" if side else "BOT"
		var bench: Array = m.opponent_bench if side else m.player_bench
		var active = m.opponent_active_pokemon if side else m.player_active_pokemon
		if bench.size() > m.get_max_bench_size():
			_problem("BENCH OVER LIMIT", "%s has %d Benched Pokémon (max %d)" % [nm, bench.size(), m.get_max_bench_size()], "bench" + nm)
		if active == null and not bench.is_empty():
			_problem("NO ACTIVE", "%s has no Active Pokémon but %d on the Bench" % [nm, bench.size()], "noact" + nm)
		# It is the BOT's turn now: the CPU's turn just ended (its "end_of_own_turn" effects must be gone), and the
		# player's "end_of_opponent_turn" effects must be gone too.
		for p in m.card_ops.get_all_pokemon_in_play(side):
			for k in p.active_effects:
				var dur: String = p.active_effects[k].get("duration", "")
				if (side and dur == "end_of_own_turn") or (not side and dur == "end_of_opponent_turn"):
					_problem("STALE EFFECT", "%s's %s still has '%s' (%s) after that turn ended" % [nm, _cname(p), k, dur], "stale" + k + str(p.get_instance_id()))
			for e in p.attached_energies:
				# "You can attach this card to your Pokémon that has..." (Bounce Energy) is checked only AT attach time —
				# Bounce itself then returns that basic Energy, so failing it later is legal.
				var attach_time_only: bool = "you can attach this card to" in str(e.metadata.get("rules", [])).to_lower()
				if "Special" in e.metadata.get("subtypes", []) and not attach_time_only and not bool(m.special_energy_effects.can_attach_to(e, p).get("allowed", true)):
					_problem("ILLEGAL ENERGY", "%s's %s holds %s, which can't be attached to it" % [nm, _cname(p), _cname(e)], "illeg" + str(e.get_instance_id()))


const BAD_LOG_TEXT := ["not implemented", "error: ", "[name]", "[time]", " null", "<null>", "todo"]   # not " error": card names have it (Computer Error, Terror Strike)

func _scan_log_text(text: String) -> void:
	var tl := text.to_lower().replace("computer error", "").replace("terror", "")   # card names, not error text
	for b in BAD_LOG_TEXT:
		if b in tl:
			_problem("LOG TEXT", "In-game message contains '%s': \"%s\"" % [b, text], "logtxt" + b + text.left(40))
			return


# ───────────────────────────── CPU turn timing ─────────────────────────────

var cpu_turn_t0 := 0
var cpu_turn_ctx := ""
var cpu_turn_times: Array = []   # [ms, "match/turn/context"]
var _was_cpu_turn := false

func _time_cpu_turns(m) -> void:
	var cpu_turn: bool = m.opponents_turn_active
	if _was_cpu_turn and not cpu_turn and cpu_turn_t0 > 0:
		var ms := (Time.get_ticks_usec() - cpu_turn_t0) / 1000.0
		cpu_turn_times.append([ms, "match %d turn %d: %s" % [match_index + 1, m.turn_number, cpu_turn_ctx]])
		cpu_turn_t0 = 0
	_was_cpu_turn = cpu_turn


func _timing_and_oracle_report() -> PackedStringArray:
	var s := PackedStringArray()
	s.append("")
	s.append("RULE-CHECK ORACLES (clean boards only): damage %d checked / %d wrong, status %d / %d, draw %d / %d" % [
		oracle_stats["damage"][0], oracle_stats["damage"][1], oracle_stats["status"][0], oracle_stats["status"][1], oracle_stats["draw"][0], oracle_stats["draw"][1]])
	if not cpu_turn_times.is_empty():
		var ms_list: Array = cpu_turn_times.map(func(x): return x[0])
		ms_list.sort()
		var total := 0.0
		for x in ms_list: total += x
		s.append("CPU TURN TIME: %d turns, average %.0f ms, 95th percentile %.0f ms, slowest %.0f ms" % [ms_list.size(), total / ms_list.size(), ms_list[int(ms_list.size() * 0.95)], ms_list[-1]])
		var slow := cpu_turn_times.duplicate()
		slow.sort_custom(func(a, b): return a[0] > b[0])
		for x in slow.slice(0, 10):
			s.append("   %6.0f ms  %s" % [x[0], x[1]])
	return s


func _write_balance_report() -> void:
	if balance.is_empty():
		return
	var rows: Array = []
	for label in balance:
		var b: Dictionary = balance[label]
		rows.append([float(b["cpu_wins"]) / maxf(1.0, float(b["games"])), label, b])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var s := PackedStringArray()
	s.append("OPPONENT BALANCE — CPU win rate vs the %s bot, per opponent (deck + match rules as in the game)" % ("SMART" if opt_bot_smart else "random"))
	for r in rows:
		var b: Dictionary = r[2]
		s.append("  %5.1f%%  %3d games  avg %4.1f turns  %s" % [r[0] * 100.0, b["games"], float(b["turns"]) / maxf(1.0, float(b["games"])), r[1]])
	var f := FileAccess.open(run_dir + "balance_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(s))
	f.close()


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
	if opp_turn and "CAN'T ATTACK" in text.to_upper():
		_cpu_attempted = true   # the CPU chose an attack and the game blocked it
	_scan_log_text(text)
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
	_time_cpu_turns(m)
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
		_extra_checks(m)


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
	s.append_array(_timing_and_oracle_report())
	_write_balance_report()
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
