extends SceneTree

## Headless cross-check of the GDScript schedule resolver against the character
## files, run with:
##
##   Godot --headless --script res://Scripts/Utilities/verify_schedule.gd
##
## Python's migrate_npc_data.py verify proves the FILES are a lossless rewrite of
## the old day files. This proves the GAME reads them the same way -- the two
## resolvers are independent implementations of the same rules, so agreeing on
## every slot is a real check rather than a tautology.

const MAPS := {
	"Celeste_Harbour": [1, 20],
	"Verdant_Forest": [5, 20],
	"Gym_Challenge_Hall": [13, 24],
	"Gym_Challenge_Reception": [9, 24],
	"Card_Mart": [1, 3],
	"Rocket_Mart": [1, 3],
	"Windmill": [1, 3],
	"Gym_Plaza": [9, 24],
}
const TIMES := ["Morning", "Afternoon", "Evening", "Night"]


var _exit_code := 0

## Schedule gaps found while checking condition branching. Reported, not failed
## -- they are missing content rather than a broken resolver.
var _gaps: Array = []


## SceneTree keeps spinning after _initialize() returns, so the run has to end from
## _process -- returning true tears the loop down after a single frame.
func _process(_delta: float) -> bool:
	return true


func _finalize() -> void:
	if _exit_code != 0:
		printerr("schedule verification FAILED")


func _initialize() -> void:
	var failures := 0
	var slots := 0
	var total_spawns := 0
	print("map                        day-range  slots  npcs  opponents")

	for map_name in MAPS:
		var lo: int = MAPS[map_name][0]
		var hi: int = MAPS[map_name][1]
		var doc := CharacterSchedule.load_map(map_name)
		if doc.is_empty():
			print("%-26s MISSING CHARACTER FILE" % map_name)
			failures += 1
			continue
		var npc_total := 0
		var opp_total := 0
		var map_slots := 0
		for day in range(lo, hi + 1):
			for time in TIMES:
				var cast := CharacterSchedule.cast_for(map_name, day, time)
				map_slots += 1
				npc_total += cast["npcs"].size()
				opp_total += cast["opponents"].size()
				failures += _check_entries(map_name, day, time, cast)
		slots += map_slots
		total_spawns += npc_total + opp_total
		print("%-26s %2d-%-6d %5d %6d %10d" % [map_name, lo, hi, map_slots, npc_total, opp_total])

	print("")
	failures += _check_condition_variants()
	failures += _check_constants()
	failures += _check_loop_identity()
	failures += _check_story_characters()
	failures += _check_closed_before_opening()
	print("")
	print("slots resolved : %d" % slots)
	print("entries built  : %d" % total_spawns)
	print("FAILURES       : %d" % failures)
	_exit_code = 1 if failures > 0 else 0


## Every spawnable entry needs a name and a position, or MapManager drops it with
## a push_error at load time. The RIVAL placeholders have no position by design.
func _check_entries(map_name: String, day: int, time: String, cast: Dictionary) -> int:
	var bad := 0
	for section in ["npcs", "opponents"]:
		var seen := {}
		for entry in cast[section]:
			var name: String = entry.get("name", "")
			if name == "":
				printerr("  %s d%d %s: entry with no name" % [map_name, day, time])
				bad += 1
				continue
			if seen.has(name):
				printerr("  %s d%d %s: %s spawns twice in one slot" % [map_name, day, time, name])
				bad += 1
			seen[name] = true
			if not entry.has("position") and not name.begins_with("RIVAL"):
				printerr("  %s d%d %s: %s has no position" % [map_name, day, time, name])
				bad += 1
	return bad


## A character with rules gated on opposite sides of a condition must resolve to a
## DIFFERENT entry depending on that condition, and must be present either way.
##
## Rule selection originally looked only at days/times, so the first rule covering
## a slot always won and its condition then filtered the character out entirely --
## the Pikachu Fans vanished on defeat instead of relocating, and the three
## gym-leader phases could never have worked. This drives the resolver with a
## stubbed evaluator forced true and forced false, and checks both.
func _check_condition_variants() -> int:
	var bad := 0
	var checked := 0
	# A stub that answers false to both a condition and its negation is not a world
	# state that can exist. These two model coherent ones -- nothing done yet, and
	# everything done -- by answering each condition according to its polarity.
	var nothing_done := func(c: Dictionary) -> bool: return _world_says(c, false)
	var all_done := func(c: Dictionary) -> bool: return _world_says(c, true)

	for map_name in MAPS:
		var doc := CharacterSchedule.load_map(map_name)
		var calendar: Dictionary = doc.get("calendar", {})
		for section in ["npcs", "opponents"]:
			for name in doc.get(section, {}):
				var character: Dictionary = doc[section][name]
				var rules = character.get("when")
				if not (rules is Array):
					continue
				# Only characters that actually branch on a condition.
				var gated := 0
				for rule in rules:
					if rule is Dictionary and rule.has("requires"):
						gated += 1
				if gated == 0 or gated == rules.size():
					continue
				checked += 1
				var day: int = int(calendar.get("loop", {}).get("from", 1))
				for time in TIMES:
					var yes := _entry_for(map_name, name, day, time, all_done)
					var no := _entry_for(map_name, name, day, time, nothing_done)
					if yes.is_empty() and no.is_empty():
						continue
					if yes.is_empty() or no.is_empty():
						# One side has no rule covering this slot at all -- a gap in the
						# authored schedule rather than the resolver choosing wrongly.
						# Surfaced as a note, because filling it is a content call.
						_gaps.append("%s / %s, day %d %s: only present %s the gate"
							% [map_name, name, day, time,
							   "after" if no.is_empty() else "before"])
					elif yes == no and (yes.has("condition") or no.has("condition")):
						# Same GATED entry either side of the gate means one of the two rules
						# is unreachable. An ungated rule matching both times is correct --
						# a character may branch on some days and not others.
						printerr("  %s/%s d%d %s: gate changes nothing; a rule is unreachable"
							% [map_name, name, day, time])
						bad += 1
	print("condition branching: %d character(s) resolve differently either side of their gate"
		% checked)
	for gap in _gaps:
		print("  note: %s" % gap)
	return bad


## Answer one condition as a consistent world would: `done` is whether the player
## has finished everything, and each condition type resolves with or against it.
static func _world_says(condition: Dictionary, done: bool) -> bool:
	var positive := ["opponent_defeated", "all_opponents_defeated",
		"any_opponent_defeated", "npc_met", "flag_set", "all", "any"]
	var negative := ["opponent_not_defeated", "not_all_opponents_defeated",
		"npc_not_met", "flag_not_set"]
	var kind: String = str(condition.get("type", ""))
	if kind in positive:
		return done
	if kind in negative:
		return not done
	return true


func _entry_for(map_name: String, name: String, day: int, time: String,
		evaluator: Callable) -> Dictionary:
	var cast := CharacterSchedule.cast_for(map_name, day, time, evaluator)
	for section in ["npcs", "opponents"]:
		for entry in cast[section]:
			if entry.get("name", "") == name:
				return entry
	return {}


## Every character must still resolve against All_NPC_Constant_Data.json, which is
## keyed by name. The migration renamed characters ("CH 1 D Old Guy Neighbour" ->
## "Old Guy Neighbour"); when the constants file was not renamed to match, every
## NPC silently lost its sprite and the map load crashed on the first one. Nothing
## else in this file would have noticed, so it is checked explicitly.
func _check_constants() -> int:
	var bad := 0
	var checked := 0
	for map_name in MAPS:
		var doc := CharacterSchedule.load_map(map_name)
		for section in ["npcs", "opponents"]:
			for name in doc.get(section, {}):
				var character: Dictionary = doc[section][name]
				if character.get("placeholder", false):
					continue
				checked += 1
				# What the spawner actually sees: the character's own fields with
				# the constants layered underneath. A sprite may legitimately live
				# in either place -- what matters is that one of them supplies it.
				var body: Dictionary = {}
				for key in character:
					if key not in ["when", "days", "times", "loop", "kind"]:
						body[key] = character[key]
				for rule in character.get("when", []):
					if rule is Dictionary and rule.has("sprite"):
						body["sprite"] = rule["sprite"]
				var merged := CharacterSchedule.merge_constants(body, section, name)
				if str(merged.get("sprite", "")) == "":
					printerr("  %s/%s/%s resolves no sprite -- not in the character "
						% [map_name, section, name] + "entry and not in the constants file")
					bad += 1
	print("constants: %d characters resolve a sprite" % checked)
	return bad


## The whole point of the calendar: once the loop starts, day D and day D+period
## must produce exactly the same cast, forever.
func _check_loop_identity() -> int:
	var bad := 0
	for map_name in MAPS:
		var doc := CharacterSchedule.load_map(map_name)
		var loop: Dictionary = doc.get("calendar", {}).get("loop", {})
		if loop.is_empty():
			continue
		var from: int = int(loop["from"])
		var period: int = int(loop["period"])
		for day in range(from, from + period):
			for time in TIMES:
				var a := _names(CharacterSchedule.cast_for(map_name, day, time))
				for cycle in [1, 2, 7]:
					var later: int = day + period * cycle
					var b := _names(CharacterSchedule.cast_for(map_name, later, time))
					if a != b:
						printerr("  %s %s: day %d and day %d differ" % [map_name, time, day, later])
						bad += 1
		print("%-26s loop from %d every %d days: verified to day %d"
			% [map_name, from, period, from + period * 7])
	return bad


## loop:false characters must NOT come back when the calendar comes round again.
func _check_story_characters() -> int:
	var bad := 0
	for map_name in MAPS:
		var doc := CharacterSchedule.load_map(map_name)
		for section in ["npcs", "opponents"]:
			for name in doc.get(section, {}):
				var character: Dictionary = doc[section][name]
				if character.get("loop", true):
					continue
				var seen_late := false
				for day in range(30, 46):
					for time in TIMES:
						if _names(CharacterSchedule.cast_for(map_name, day, time)).has(name):
							seen_late = true
				if seen_late:
					printerr("  %s: story character %s reappears after day 30" % [map_name, name])
					bad += 1
	print("story characters (loop:false): checked they stay gone through day 45")
	return bad


## A map must be deserted on every day before it opens. This is what broke when the
## Gym Plaza kept an authored_through of 1: its shopkeepers carried no `days` at
## all, so they stood in an area the player cannot reach yet, and every dated rule
## in the file resolved back to day 1 and could never fire.
func _check_closed_before_opening() -> int:
	var bad := 0
	for map_name in MAPS:
		# The map file is the authority on when it opens; MAPS only says how far out
		# to resolve it.
		var calendar: Dictionary = CharacterSchedule.load_map(map_name).get("calendar", {})
		var opens: int = int(calendar.get("opens", MAPS[map_name][0]))
		if opens <= 1:
			continue
		for day in range(1, opens):
			for time in TIMES:
				var names := _names(CharacterSchedule.cast_for(map_name, day, time))
				if not names.is_empty():
					printerr("  %s: opens day %d but day %d %s has %d character(s): %s"
						% [map_name, opens, day, time, names.size(), str(names)])
					bad += 1
	print("closed maps: checked every map is deserted before it opens")
	return bad


func _names(cast: Dictionary) -> Array:
	var out: Array = []
	for section in ["npcs", "opponents"]:
		for entry in cast[section]:
			out.append(entry.get("name", ""))
	out.sort()
	return out
