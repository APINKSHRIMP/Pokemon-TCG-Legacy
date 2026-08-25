class_name CharacterSchedule
extends RefCounted

## Resolves a map's character file into the cast for one (day, time-of-day) slot.
##
## Character files live in NPC_and_Opponent_Data/Characters/ -- one per map, each
## character defined once with a `when` rule list. See that folder's README.md.
##
## The entries handed back are in the same shape MapManager has always spawned, so
## everything downstream (constants merge, condition evaluation, actor setup) is
## untouched by the format change.

const DIR := "res://NPC_and_Opponent_Data/Characters/"

const TIME_LETTERS := {
	"M": "Morning", "A": "Afternoon", "E": "Evening", "N": "Night",
}

## Keys that describe the schedule itself rather than the character.
const SCHEDULE_KEYS := ["when", "days", "times", "loop", "kind"]

static var _cache: Dictionary = {}


## Load and cache one map's character file. Returns {} when the map has none.
static func load_map(map_name: String) -> Dictionary:
	if _cache.has(map_name):
		return _cache[map_name]
	var path := DIR + map_name + ".json"
	var doc: Dictionary = {}
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				doc = parsed
			else:
				push_error("CharacterSchedule: %s is not a JSON object" % path)
	_cache[map_name] = doc
	return doc


## Drop the cache so an edited file is picked up without restarting. Used by the
## in-game placement tool after it saves.
static func invalidate(map_name: String = "") -> void:
	if map_name == "":
		_cache.clear()
	else:
		_cache.erase(map_name)


## Map a real date onto the authored day it repeats. Days before the loop starts
## are authored literally; from there on the block repeats forever, so the player
## can reach day 900 without running out of content.
static func resolve_day(calendar: Dictionary, day: int) -> int:
	var loop: Dictionary = calendar.get("loop", {})
	if loop.is_empty():
		return day
	var from: int = int(loop.get("from", 1))
	var period: int = int(loop.get("period", 1))
	if period <= 0 or day < from:
		return day
	return from + ((day - from) % period)


## "3-6" | "1,3,5" | "2-8/2" | "4". An empty spec matches every day.
static func days_match(spec: Variant, day: int) -> bool:
	if spec == null:
		return true
	var text := str(spec).strip_edges()
	if text == "" or text == "*":
		return true
	for raw in text.split(","):
		var part := raw.strip_edges()
		if part == "":
			continue
		var step := 1
		var slash := part.find("/")
		if slash != -1:
			step = maxi(1, int(part.substr(slash + 1)))
			part = part.substr(0, slash)
		var dash := part.find("-", 1)   # from index 1, so a negative day survives
		if dash == -1:
			if int(part) == day:
				return true
			continue
		var lo := int(part.substr(0, dash))
		var hi := int(part.substr(dash + 1))
		if day >= lo and day <= hi and (day - lo) % step == 0:
			return true
	return false


## "M,A" | "MAEN" | "E". An empty spec matches every time of day.
static func times_match(spec: Variant, time_of_day: String) -> bool:
	if spec == null:
		return true
	var text := str(spec).strip_edges()
	if text == "" or text == "*":
		return true
	for i in text.length():
		var ch := text[i]
		if TIME_LETTERS.has(ch) and TIME_LETTERS[ch] == time_of_day:
			return true
	return false


## `condition_eval` is an optional Callable(Dictionary) -> bool, supplied by
## MapManager so rule selection can take progress into account.
##
## Without it a rule is chosen on days/times alone, and two rules covering the same
## slot but gated on opposite states -- "spread across the forest until you beat
## me" / "clustered by the gate once you have" -- could never both work: the first
## would always win and the second would never be reachable. The same applies to
## the three gym-leader phases, which are gated on progress rather than the date.
## `inherited_requires` is the character's own gate. A rule that states no
## `requires` of its own inherits it, exactly as it inherits `at`, `move` and
## `says` -- otherwise a character whose default is gated would have every rule
## match unconditionally, and the first would swallow the rest.
static func _rule_matches(rule: Dictionary, day: int, time_of_day: String,
		condition_eval: Callable = Callable(), inherited_requires: Variant = null) -> bool:
	if not days_match(rule.get("days"), day):
		return false
	if not times_match(rule.get("times"), time_of_day):
		return false
	var req = rule.get("requires")
	if req == null:
		req = inherited_requires
	if req != null and condition_eval.is_valid():
		var cond := to_condition(req)
		if not cond.is_empty() and not condition_eval.call(cond):
			return false
	return true


## Turn the readable `requires` shorthand back into the condition dictionary
## MapManager._evaluate_condition already understands. A dictionary that isn't one
## of the list forms passes straight through, so compound all/any still work.
static func to_condition(req: Variant) -> Dictionary:
	if req == null:
		return {}
	if req is Dictionary:
		var listy := {
			"all_beaten": "all_opponents_defeated",
			"any_beaten": "any_opponent_defeated",
			"not_all_beaten": "not_all_opponents_defeated",
		}
		for key in listy:
			if req.has(key):
				return {"type": listy[key], "targets": req[key]}
		return req
	var text := str(req).strip_edges()
	var negated := text.begins_with("not ")
	if negated:
		text = text.substr(4).strip_edges()
	var colon := text.find(":")
	if colon == -1:
		push_warning("CharacterSchedule: unparsable requires: " + str(req))
		return {}
	var head := text.substr(0, colon).strip_edges()
	var arg := text.substr(colon + 1).strip_edges()
	match head:
		"beaten":
			return {"type": "opponent_not_defeated" if negated else "opponent_defeated",
					"target": arg}
		"met":
			return {"type": "npc_not_met" if negated else "npc_met", "target": arg}
		"flag":
			return {"type": "flag_not_set" if negated else "flag_set", "flag": arg}
	push_warning("CharacterSchedule: unknown requires head: " + head)
	return {}


## Did the rule at `rule_index` state `field` itself, rather than inheriting it?
static func _rule_sets(character: Dictionary, rule_index: int, field: String) -> bool:
	if rule_index < 0:
		return false
	var rules = character.get("when")
	if not (rules is Array) or rule_index >= rules.size():
		return false
	var rule = rules[rule_index]
	return rule is Dictionary and rule.get(field) != null


## Expand one character body into the legacy entry shape the spawner consumes.
static func _to_entry(name: String, body: Dictionary) -> Dictionary:
	var entry: Dictionary = {"name": name}

	var at = body.get("at")
	if at is Array and at.size() >= 2:
		entry["position"] = {"x": at[0], "y": at[1]}

	var move = body.get("move")
	if move is String:
		entry["pattern"] = move
	elif move is Dictionary:
		if move.has("pattern"):
			entry["pattern"] = move["pattern"]
		if move.has("speed"):
			entry["patrol_speed"] = move["speed"]
		if move.has("distance"):
			entry["patrol_distance"] = move["distance"]
		if move.has("axis"):
			entry["patrol_axis"] = move["axis"]
		if move.has("radius"):
			entry["wander_radius"] = move["radius"]

	var says = body.get("says")
	if says is Dictionary:
		if says.has("meet"):        entry["meet_text"] = says["meet"]
		if says.has("repeat"):      entry["repeat_text"] = says["repeat"]
		if says.has("first_win"):   entry["first_win_text"] = says["first_win"]
		if says.has("rematch_win"): entry["rematch_win_text"] = says["rematch_win"]
		if says.has("loss"):        entry["loss_text"] = says["loss"]

	if body.get("requires") != null:
		var cond := to_condition(body["requires"])
		if not cond.is_empty():
			entry["condition"] = cond

	for key in body:
		if key in SCHEDULE_KEYS or key in ["at", "move", "says", "requires"]:
			continue
		entry[key] = body[key]
	return entry


## The cast for one slot: { "npcs": [entry, ...], "opponents": [entry, ...] }.
static func cast_for(map_name: String, day: int, time_of_day: String,
		condition_eval: Callable = Callable()) -> Dictionary:
	var doc := load_map(map_name)
	var out := {"npcs": [], "opponents": []}
	if doc.is_empty():
		return out

	var calendar: Dictionary = doc.get("calendar", {})
	var looped_day := resolve_day(calendar, day)

	for section in ["npcs", "opponents"]:
		var cast: Dictionary = doc.get(section, {})
		for name in cast:
			var character: Dictionary = cast[name]
			# Story characters opt out of the loop and are matched against the real
			# date, so they stop existing once their authored days run out instead of
			# reappearing every time the calendar comes back around.
			var day_for_match: int = looped_day if character.get("loop", true) else day

			var body: Dictionary = {}
			for key in character:
				if key not in SCHEDULE_KEYS:
					body[key] = character[key]

			# -1 means the character's own top-level fields matched with no rule.
			# The placement tool uses this to write an edited position back to the
			# exact rule it came from rather than guessing.
			var rule_index := -1
			var rules = character.get("when")
			if rules is Array:
				var hit: Dictionary = {}
				var matched := false
				for i in rules.size():
					var rule = rules[i]
					if rule is Dictionary and _rule_matches(rule, day_for_match, time_of_day,
							condition_eval, character.get("requires")):
						hit = rule
						rule_index = i
						matched = true
						break
				if not matched:
					continue
				for key in hit:
					if key in ["days", "times"]:
						continue
					# An explicit null clears a field the character sets above.
					if hit[key] == null:
						body.erase(key)
					else:
						body[key] = hit[key]
				if hit.has("kind"):
					body["kind"] = hit["kind"]
			elif not _rule_matches(character, day_for_match, time_of_day, condition_eval):
				continue

			var target: String = section
			match body.get("kind", ""):
				"npc":      target = "npcs"
				"opponent": target = "opponents"
			var built := _to_entry(name, body)
			# `at_owner` / `move_owner` record where the value actually came from: the
			# rule index if that rule overrode it, or -1 for the character's defaults.
			# The placement tool edits the field where it LIVES, so moving a character
			# whose rules only describe *when* they appear moves them everywhere,
			# instead of fragmenting one shared position into a per-rule copy.
			built["_source"] = {
				"section": section, "name": name, "rule": rule_index,
				"at_owner": rule_index if _rule_sets(character, rule_index, "at") else -1,
				"move_owner": rule_index if _rule_sets(character, rule_index, "move") else -1,
			}
			out[target].append(built)
	return out


## Today's entry for one opponent on one map, already merged with
## All_NPC_Constant_Data.json -- the shape the match scripts used to build by
## opening the day file and searching it by name.
## Day and time are passed in rather than read from GameState so this whole class
## stays a pure function of its data -- which is what lets verify_schedule.gd
## exercise it headlessly, with no autoloads and no save file.
static func find_opponent(map_name: String, opponent_name: String,
		day: int, time_of_day: String, condition_eval: Callable = Callable()) -> Dictionary:
	var cast := cast_for(map_name, day, time_of_day, condition_eval)
	var wanted := opponent_name.strip_edges().to_lower()
	for entry in cast.get("opponents", []):
		if str(entry.get("name", "")).strip_edges().to_lower() == wanted:
			return merge_constants(entry, "opponents", entry.get("name", ""))
	# The opponent may have been filtered out by its own condition after being
	# beaten -- fall back to the character's defaults so the outro can still find
	# its rewards and dialogue.
	var doc := load_map(map_name)
	var pool: Dictionary = doc.get("opponents", {})
	var matched := AssetLookup.match_key(pool, opponent_name)
	var character = pool.get(matched) if matched != "" else null
	if character is Dictionary:
		var body: Dictionary = {}
		for key in character:
			if key not in SCHEDULE_KEYS:
				body[key] = character[key]
		return merge_constants(_to_entry(matched, body), "opponents", matched)
	return {}


## Layer All_NPC_Constant_Data.json underneath an entry. Anything the entry
## already states wins, exactly as the old day-file merge did.
static func merge_constants(entry: Dictionary, section: String, name: String) -> Dictionary:
	var file := FileAccess.open("res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json",
			FileAccess.READ)
	if file == null:
		return entry
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return entry
	var pool: Dictionary = parsed.get(section, {})
	var matched := AssetLookup.match_key(pool, name)
	var consts: Dictionary = pool.get(matched, {}) if matched != "" else {}
	var merged := entry.duplicate(true)
	for key in consts:
		if not merged.has(key):
			merged[key] = consts[key]
	return merged


## Scene-relative node paths that should be visible today. Rotating scenery runs on
## its own cycle so it drifts against the cast cycle -- every day ends up a
## different combination, which hides the loop.
static func dressing_for(map_name: String, day: int) -> Dictionary:
	var doc := load_map(map_name)
	var dressing: Dictionary = doc.get("dressing", {})
	var result := {"show": [], "all": []}
	if dressing.is_empty():
		return result
	var days: Dictionary = dressing.get("days", {})
	for key in days:
		for node_path in days[key]:
			if not result["all"].has(node_path):
				result["all"].append(node_path)
	var resolved := resolve_day({"loop": dressing.get("cycle", {})}, day)
	result["show"] = days.get(str(resolved), [])
	return result
