extends RefCounted
const CpuWeights = preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_Weights.gd")
## ISSUE #375 — DEV MATCH RECORDER (real matches only, DebugMode only).
##
## Writes user://match_logs/<date-time>_<opponent>.jsonl — one JSON object per line:
##   {"t":"start",  ...match info}
##   {"t":"turn",   "side": "player"|"cpu", "state": {full snapshot}, "shadow": {what the CPU would do in the player's seat}}
##   {"t":"msg",    "text": in-game message, "turn": n, "cpu_turn": bool, "state": {snapshot after it}}
##   {"t":"decision","kind": play_card|attack|retreat|power|end_turn, ..., "state": {...}, "shadow": {...}}   (player)
##   {"t":"end",    "result": "win"|"loss"|"draw"}
## The snapshot holds EVERYTHING (both hands, deck orders, Prizes) so a match can be analysed exactly afterwards.
## Read by Scripts/Autotest/cpu_match_analyse.py. Never touches the save files.

var main
var path := ""


func _init(m) -> void:
	main = m
	DirAccess.make_dir_recursive_absolute("user://match_logs")
	var opp := String(GameState.current_opponent_name).replace(" ", "_").replace("/", "_").replace(":", "")
	path = "user://match_logs/%s_%s.jsonl" % [Time.get_datetime_string_from_system().replace(":", "-"), opp]
	_write({"t": "start", "opponent": GameState.current_opponent_name, "map": GameState.current_opponent_map,
		"player_deck": main.player_deck_name, "time": Time.get_datetime_string_from_system(),
		"cpu_cheat_cards": CpuWeights.cheat_cards, "cpu_plan_turns": CpuWeights.plan_turns})


func _write(obj: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(obj))
	f.close()


static func _uid(c) -> String:
	return String(c.uid) if c != null and c is Object and "uid" in c else ""


func _mon(p) -> Dictionary:
	if p == null:
		return {}
	return {"uid": p.uid, "name": p.metadata.get("name", ""), "hp": p.current_hp, "max": p.get_max_hp(),
		"energy": p.attached_energies.map(func(e): return _uid(e)),
		"attached": p.attached_cards.map(func(e): return _uid(e)),
		"status": p.special_condition, "poisoned": p.is_poisoned, "burned": p.is_burned,
		"defender": p.defender_count, "pluspower": p.pluspower_count, "new": p.placed_on_field_this_turn}


func _side(is_cpu: bool) -> Dictionary:
	var pre := "opponent_" if is_cpu else "player_"
	return {"active": _mon(main.get(pre + "active_pokemon")),
		"bench": main.get(pre + "bench").map(func(p): return _mon(p)),
		"hand": main.get(pre + "hand").map(func(c): return _uid(c)),
		"deck": main.get(pre + "deck").map(func(c): return _uid(c)),
		"prizes": main.get(pre + "prize_cards").map(func(c): return _uid(c)),
		"discard": main.get(pre + "discard_pile").map(func(c): return _uid(c)),
		"energy_played": main.get(pre + "energy_played_this_turn"),
		"retreated": main.get(pre + "retreated_this_turn")}


func snapshot() -> Dictionary:
	return {"turn": main.turn_number, "cpu_turn": main.opponents_turn_active,
		"stadium": _uid(main.current_stadium_card), "player": _side(false), "cpu": _side(true)}


func turn_start(is_cpu: bool) -> void:
	var rec := {"t": "turn", "side": "cpu" if is_cpu else "player", "state": snapshot()}
	if not is_cpu:
		rec["shadow"] = main.cpu_ai.shadow_player_decisions()
	_write(rec)


func message(text: String, turn: int, cpu_turn: bool) -> void:
	_write({"t": "msg", "text": text, "turn": turn, "cpu_turn": cpu_turn, "state": snapshot()})


func decision(kind: String, detail: Dictionary) -> void:
	var rec := {"t": "decision", "kind": kind, "turn": main.turn_number, "state": snapshot(),
		"shadow": main.cpu_ai.shadow_player_decisions()}
	rec.merge(detail)
	_write(rec)


func finish(result: String) -> void:
	_write({"t": "end", "result": result, "turn": main.turn_number, "state": snapshot()})
