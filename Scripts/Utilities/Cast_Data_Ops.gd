extends RefCounted

## Whole-character file operations for the F placement tool: clone, delete, move to
## another map, rename everywhere, and random filler NPCs. Debug tooling, preloaded by
## PlacementTool (not a class_name).
##
## Everything here works on the files on disk and writes through the tool's own JSON
## writer (`writer`), so a write never churns the rest of a file -- numbers stay ints,
## `at` pairs stay on one line, route steps one per line.

const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"
const RATINGS_PATH := "res://NPC_and_Opponent_Data/Opponent_Ratings.json"
const SPRITE_DIR := "res://Image_Assets/Character_Sprites/Overworld_Sprites/"
const SECTIONS := ["npcs", "opponents"]
## `requires` shorthand prefixes that name a character.
const GATE_PREFIXES := ["not beaten: ", "beaten: ", "not met: ", "met: "]

## TWEAKABLE: what a random filler NPC is called (a number is added to keep it unique)
## and the lines it may say. [TIME] becomes "morning" / "afternoon" / ...
const FILLER_NAMES := [
	"Tourist", "Local", "Hiker", "Sailor", "Fisher", "Jogger", "Shopper", "Student",
	"Traveller", "Dock Worker", "Painter", "Birdwatcher", "Gardener", "Collector",
	"Day Tripper", "Card Fan", "Backpacker", "Commuter",
]
const FILLER_MEET := [
	"Lovely [TIME], isn't it?",
	"I come here every chance I get. It's so peaceful.",
	"Have you seen any rare Pokémon around here?",
	"I'm just waiting for a friend. They're always late!",
	"I heard there are strong trainers around here.",
	"I used to battle a lot when I was younger.",
	"The sea air does wonders for you.",
	"I can never decide which pack to open first.",
	"Do you play the card game too? Everyone seems to these days.",
	"I'm just taking it easy today.",
	"Have you tried the café? I hear the breakfasts are amazing.",
	"I think I'm lost... no, wait, this is the right way.",
]
const FILLER_REPEAT := [
	"Enjoy your [TIME]!",
	"Good luck out there!",
	"I think I'll stay here a while longer.",
	"See you around!",
	"Don't let me keep you.",
	"Take care now.",
]
const FILLER_PATTERNS := ["idle_random", "idle_random", "idle_down_random", "random_wander"]

var writer: Callable


func _init(json_writer: Callable) -> void:
	writer = json_writer


# ── reading ───────────────────────────────────────────────────────────────────

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func map_names() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CharacterSchedule.DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


## Every character key in use, lowercased: every map file and the constants file.
static func taken_names() -> Dictionary:
	var out: Dictionary = {}
	for map_name in map_names():
		var doc := read_json(CharacterSchedule.DIR + map_name + ".json")
		for section in SECTIONS:
			for name in doc.get(section, {}):
				out[str(name).to_lower()] = true
	var consts := read_json(CONSTANTS_PATH)
	for section in SECTIONS:
		for name in consts.get(section, {}):
			out[str(name).to_lower()] = true
	return out


## The maps whose files hold this character.
static func maps_with(name: String) -> Array:
	var out: Array = []
	for map_name in map_names():
		var doc := read_json(CharacterSchedule.DIR + map_name + ".json")
		for section in SECTIONS:
			if doc.get(section, {}).has(name):
				out.append(map_name)
				break
	return out


static func unique_name(base: String, also_taken: Array = []) -> String:
	var taken := taken_names()
	for extra in also_taken:
		taken[str(extra).to_lower()] = true
	if not taken.has(base.to_lower()):
		return base
	var n := 2
	while taken.has(("%s %d" % [base, n]).to_lower()):
		n += 1
	return "%s %d" % [base, n]


# ── clone ─────────────────────────────────────────────────────────────────────

## A draft for PlacementTool that copies a character -- every rule, line, schedule and
## constant -- under a new name. Coins must stay one-per-giver, so a coin reward or a
## coin gift is left off the copy (`dropped` lists what was).
static func clone_draft(map_name: String, section: String, constants_section: String,
		name: String, new_name: String) -> Dictionary:
	var doc := read_json(CharacterSchedule.DIR + map_name + ".json")
	var body = doc.get(section, {}).get(name)
	if not (body is Dictionary):
		return {}
	var consts := read_json(CONSTANTS_PATH)
	var const_body = consts.get(constants_section, {}).get(name, {})
	var copy: Dictionary = (body as Dictionary).duplicate(true)
	var const_copy: Dictionary = (const_body as Dictionary).duplicate(true) if const_body is Dictionary else {}
	var dropped: Array = []
	for target in [copy, const_copy]:
		_drop_unique_rewards(target, dropped)
	for rule in copy.get("when", []) if copy.get("when") is Array else []:
		if rule is Dictionary:
			_drop_unique_rewards(rule, dropped)
	return {
		"kind": "clone", "section": section, "constants_section": constants_section,
		"name": new_name, "is_new": true, "body": copy, "constants": const_copy,
		"dropped": dropped,
	}


static func _drop_unique_rewards(body: Dictionary, dropped: Array) -> void:
	if body.has("coin_reward"):
		body.erase("coin_reward")
		if not dropped.has("coin reward"):
			dropped.append("coin reward")
	if str(body.get("gift_type", "")) == "coin":
		body.erase("gift_type")
		body.erase("gift_value")
		if not dropped.has("coin gift"):
			dropped.append("coin gift")


# ── delete ────────────────────────────────────────────────────────────────────

## Remove a character from this map's file. Their constants go too unless another map
## still has someone by that name; their deck file is always kept. Returns a summary.
func delete_character(map_name: String, section: String, name: String) -> Dictionary:
	var path: String = CharacterSchedule.DIR + map_name + ".json"
	var doc := read_json(path)
	if not (doc.get(section) is Dictionary) or not doc[section].has(name):
		return {"error": "%s is not in %s.json" % [name, map_name]}
	doc[section].erase(name)
	if not writer.call(path, doc):
		return {"error": "could not write %s" % path}
	var elsewhere := maps_with(name)
	var constants_removed := false
	if elsewhere.is_empty():
		var consts := read_json(CONSTANTS_PATH)
		for s in SECTIONS:
			if consts.get(s) is Dictionary and consts[s].has(name):
				consts[s].erase(name)
				constants_removed = true
		if constants_removed and not writer.call(CONSTANTS_PATH, consts):
			return {"error": "could not write All_NPC_Constant_Data.json"}
		var ratings := read_json(RATINGS_PATH)
		if ratings.has(name):
			ratings.erase(name)
			writer.call(RATINGS_PATH, ratings)
	CharacterSchedule.invalidate()
	return {"constants_removed": constants_removed, "elsewhere": elsewhere,
			"gates": gate_references(name)}


# ── move to another map ───────────────────────────────────────────────────────

## Take a character out of one map file and put them in another, schedule, lines and
## position untouched (walk there and place them). Refuses a name the target already has.
func move_to_map(from_map: String, to_map: String, section: String, name: String) -> String:
	if from_map == to_map:
		return "they are already on %s" % to_map
	var from_path := CharacterSchedule.DIR + from_map + ".json"
	var to_path := CharacterSchedule.DIR + to_map + ".json"
	var from_doc := read_json(from_path)
	var to_doc := read_json(to_path)
	if to_doc.is_empty():
		return "cannot read %s.json" % to_map
	var body = from_doc.get(section, {}).get(name)
	if not (body is Dictionary):
		return "%s is not in %s.json" % [name, from_map]
	for s in SECTIONS:
		if to_doc.get(s, {}).has(name):
			return "%s already has someone called %s" % [to_map, name]
	if not (to_doc.get(section) is Dictionary):
		to_doc[section] = {}
	to_doc[section][name] = body
	from_doc[section].erase(name)
	# Target first: if that write fails, nothing has been lost from the source.
	if not writer.call(to_path, to_doc):
		return "could not write %s" % to_path
	if not writer.call(from_path, from_doc):
		return "could not write %s (they are now on BOTH maps -- fix by hand)" % from_path
	CharacterSchedule.invalidate()
	return ""


# ── rename everywhere ─────────────────────────────────────────────────────────

## Rename a character key in every map file, the constants file and the ratings file,
## and in every `requires` gate that names them. Scripts that mention the old name are
## LISTED in `code_hits`, never edited. Returns {error} or {files: [...], code_hits: [...]}.
func rename_everywhere(old_name: String, new_name: String) -> Dictionary:
	if new_name.strip_edges() == "" or old_name == new_name:
		return {"error": "no new name"}
	if taken_names().has(new_name.to_lower()):
		return {"error": "\"%s\" is already taken" % new_name}
	var files: Array = []
	for map_name in map_names():
		var path: String = CharacterSchedule.DIR + map_name + ".json"
		var doc := read_json(path)
		var changed := false
		for s in SECTIONS:
			if doc.get(s) is Dictionary and doc[s].has(old_name):
				doc[s] = _rename_key(doc[s], old_name, new_name)
				changed = true
			for who in doc.get(s, {}):
				if doc[s][who] is Dictionary and _rename_gates(doc[s][who], old_name, new_name):
					changed = true
		if changed:
			if not writer.call(path, doc):
				return {"error": "could not write %s" % path, "files": files}
			files.append(map_name + ".json")
	var consts := read_json(CONSTANTS_PATH)
	var consts_changed := false
	for s in SECTIONS:
		if consts.get(s) is Dictionary and consts[s].has(old_name):
			consts[s] = _rename_key(consts[s], old_name, new_name)
			consts_changed = true
	if consts_changed:
		if not writer.call(CONSTANTS_PATH, consts):
			return {"error": "could not write All_NPC_Constant_Data.json", "files": files}
		files.append("All_NPC_Constant_Data.json")
	var ratings := read_json(RATINGS_PATH)
	if ratings.has(old_name):
		writer.call(RATINGS_PATH, _rename_key(ratings, old_name, new_name))
		files.append("Opponent_Ratings.json")
	CharacterSchedule.invalidate()
	return {"files": files, "code_hits": code_references(old_name)}


## Same order, one key renamed.
static func _rename_key(dict: Dictionary, old_name: String, new_name: String) -> Dictionary:
	var out: Dictionary = {}
	for k in dict:
		out[new_name if k == old_name else k] = dict[k]
	return out


## Rewrite every `requires` in a character (its own and its rules') that names old_name.
static func _rename_gates(character: Dictionary, old_name: String, new_name: String) -> bool:
	var changed := false
	var holders: Array = [character]
	if character.get("when") is Array:
		holders.append_array(character["when"])
	for holder in holders:
		if not (holder is Dictionary) or not holder.has("requires"):
			continue
		var renamed = _rename_in_gate(holder["requires"], old_name, new_name)
		if JSON.stringify(renamed) != JSON.stringify(holder["requires"]):
			holder["requires"] = renamed
			changed = true
	return changed


static func _rename_in_gate(gate: Variant, old_name: String, new_name: String) -> Variant:
	if gate is String:
		for prefix in GATE_PREFIXES:
			if gate == prefix + old_name:
				return prefix + new_name
		return gate
	if gate is Array:
		var out: Array = []
		for g in gate:
			out.append(new_name if g is String and g == old_name else _rename_in_gate(g, old_name, new_name))
		return out
	if gate is Dictionary:
		var out: Dictionary = {}
		for k in gate:
			var v = gate[k]
			out[k] = new_name if v is String and v == old_name else _rename_in_gate(v, old_name, new_name)
		return out
	return gate


## "map: who" for every character whose `requires` names this one.
static func gate_references(name: String) -> Array:
	var out: Array = []
	for map_name in map_names():
		var doc := read_json(CharacterSchedule.DIR + map_name + ".json")
		for s in SECTIONS:
			for who in doc.get(s, {}):
				var body = doc[s][who]
				if body is Dictionary and _rename_gates(body.duplicate(true), name, name + "\u0001"):
					out.append("%s: %s" % [map_name, who])
	return out


## Script files that mention the name in quotes -- cutscenes, goodbyes, overrides.
static func code_references(name: String) -> Array:
	var out: Array = []
	var needle := "\"%s\"" % name
	_scan_code("res://Scripts", needle, out)
	return out


static func _scan_code(folder: String, needle: String, out: Array) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_code(folder + "/" + sub, needle, out)
	for f in dir.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(folder + "/" + f).contains(needle):
			out.append(f)


# ── random filler NPC ─────────────────────────────────────────────────────────

## A draft for a throwaway crowd NPC: a sprite nobody else uses, a generic name and
## generic lines, on this one day and time. Placed like any new character.
static func filler_draft(day: int, time_of_day: String, also_taken: Array = []) -> Dictionary:
	var sprite := _unused_sprite()
	var friendly: String = FILLER_NAMES[randi() % FILLER_NAMES.size()]
	var name := unique_name(friendly, also_taken)
	var letter := ""
	for l in CharacterSchedule.TIME_LETTERS:
		if CharacterSchedule.TIME_LETTERS[l] == time_of_day:
			letter = l
	var says := {
		"meet": FILLER_MEET[randi() % FILLER_MEET.size()],
		"repeat": FILLER_REPEAT[randi() % FILLER_REPEAT.size()],
	}
	var pattern: String = FILLER_PATTERNS[randi() % FILLER_PATTERNS.size()]
	var move: Variant = pattern
	if pattern == "random_wander":
		move = {"pattern": "random_wander", "radius": 40, "speed": 30}
	var constants := {"friendly_name": friendly, "sprite": sprite, "message_colour": "grey"}
	var character := {"move": move, "says": says}
	var entry_body: Dictionary = character.duplicate(true)
	entry_body.merge(constants)
	return {
		"section": "npcs", "constants_section": "npcs", "name": name, "is_new": true,
		"rule_index": -1, "constants": constants, "character": character, "rule": {},
		"remove": [], "filler": true,
		"schedule": {"slots": [{"days": str(day), "times": letter}], "group": []},
		"entry": CharacterSchedule.to_entry(name, entry_body),
	}


static func _unused_sprite() -> String:
	var used: Dictionary = {}
	var consts := read_json(CONSTANTS_PATH)
	for s in SECTIONS:
		for who in consts.get(s, {}):
			var body = consts[s][who]
			if body is Dictionary and body.has("sprite"):
				used[str(body["sprite"])] = true
	var free: Array = []
	var all: Array = []
	var dir := DirAccess.open(SPRITE_DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".png"):
				continue
			var base := f.trim_suffix(".png")
			all.append(base)
			if not used.has(base):
				free.append(base)
	var pool := free if not free.is_empty() else all
	return str(pool[randi() % pool.size()]) if not pool.is_empty() else "Roughneck"
