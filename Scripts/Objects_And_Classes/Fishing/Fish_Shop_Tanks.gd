class_name FishShopTanks
extends RefCounted

## How many fish FISH can take, and which of its interiors are open -- everything about
## the shop growing that does NOT need the shop's scene to be loaded, so a catch at the
## harbour can ask "is there room for this?".
##
## Two sources, kept in step on purpose (see Fish_Shop_Tanks.json's _help):
##   * NPC_and_Opponent_Data/Pokemon/Fish_Shop_Tanks.json -- per floor, per stage, which
##     species live in which tank and how many of each. That gives every species its CAP.
##   * The floors' scenes -- every node named Interior_<N> is an expansion that opens at
##     N fish sent. The numbers are READ OFF THE SCENE FILES (their PackedScene state, no
##     instancing), which is what makes them the milestones FishShopCalls rings for:
##     rename Interior_100 to Interior_150 and the expansion and its call both move.
##
## Everything counts fish SENT TO FISH (GameState.fish_sent_total), never fish landed.

const DATA_PATH := "res://NPC_and_Opponent_Data/Pokemon/Fish_Shop_Tanks.json"

## Map data name -> scene. The floors FISH is made of.
const FLOOR_SCENES := {
	"Fish_Shop": "res://Scenes/Map_Scenes/Fish_Shop.tscn",
	"Fish_Shop_Downstairs": "res://Scenes/Map_Scenes/Fish_Shop_Downstairs.tscn",
}
const DOWNSTAIRS := "Fish_Shop_Downstairs"

## "Interior_25" -> 25. Anything after a space is ignored ("Interior_0 (START)").
const INTERIOR_PATTERN := "^Interior_(\\d+)(\\s.*)?$"

static var _data: Dictionary = {}
static var _scene_interiors: Dictionary = {}   # floor -> Array of int, sorted
static var _regex: RegEx = null


# ============================================================
# DATA
# ============================================================

static func _load() -> Dictionary:
	if not _data.is_empty():
		return _data
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("FishShopTanks: cannot open " + DATA_PATH)
		_data = {"floors": {}}
		return _data
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or not parsed.get("floors") is Dictionary:
		push_error("FishShopTanks: %s is malformed" % DATA_PATH)
		_data = {"floors": {}}
		return _data
	_data = parsed
	return _data


static func floors() -> Array:
	return FLOOR_SCENES.keys()


static func floor_config(floor_name: String) -> Dictionary:
	var cfg = _load()["floors"].get(floor_name, {})
	return cfg if cfg is Dictionary else {}


## The downstairs is closed until Verdant Forest opens (the same real-date gate the
## stairs' DownstairsBlock uses). A closed floor holds no fish.
static func floor_open(floor_name: String) -> bool:
	if floor_name == DOWNSTAIRS:
		return GameState.get_date() >= FishShopDialogue.VERDANT_OPEN_DATE
	return true


## The stage numbers a floor has tank lists for, lowest first.
static func stage_numbers(floor_name: String) -> Array:
	var out: Array = []
	var stages = floor_config(floor_name).get("stages", {})
	if stages is Dictionary:
		for key in stages:
			if String(key).is_valid_int():
				out.append(int(key))
	out.sort()
	return out


## The stage in force on a floor: the highest one the player has sent enough fish for.
## -1 when the floor is closed or has no stage that low.
static func active_stage(floor_name: String, sent: int = -1) -> int:
	if not floor_open(floor_name):
		return -1
	if sent < 0:
		sent = GameState.fish_sent_total()
	var best := -1
	for n in stage_numbers(floor_name):
		if n <= sent:
			best = n
	return best


## tank name -> rows [{species, pattern, max}] for the stage in force ({} if none).
static func tanks_in_force(floor_name: String, sent: int = -1) -> Dictionary:
	var stage := active_stage(floor_name, sent)
	if stage < 0:
		return {}
	var tanks = floor_config(floor_name)["stages"].get(str(stage), {})
	return tanks if tanks is Dictionary else {}


## How many of `species` FISH can hold right now, over every floor.
static func cap(species: String) -> int:
	var total := 0
	for floor_name in floors():
		var tanks := tanks_in_force(floor_name)
		for tank in tanks:
			for row in tanks[tank]:
				if row is Dictionary and str(row.get("species", "")) == species:
					total += int(row.get("max", 0))
	return total


static func has_room(species: String) -> bool:
	return GameState.fish_sent_count(species) < cap(species)


## How many of each row to actually put in the tanks: the species' sent count poured
## into its rows in order (floor order, then the file's tank order), each row taking up
## to its max. Returns floor -> tank -> [{species, pattern, count}] with count > 0 only.
static func shown_counts() -> Dictionary:
	var left: Dictionary = {}
	var out: Dictionary = {}
	for floor_name in floors():
		var tanks := tanks_in_force(floor_name)
		var floor_out: Dictionary = {}
		for tank in tanks:
			var rows: Array = []
			for row in tanks[tank]:
				if not row is Dictionary:
					continue
				var species := str(row.get("species", ""))
				if not left.has(species):
					left[species] = GameState.fish_sent_count(species)
				var count := mini(int(left[species]), int(row.get("max", 0)))
				left[species] = int(left[species]) - count
				if count > 0:
					rows.append({"species": species,
							"pattern": str(row.get("pattern", "fish")), "count": count})
			floor_out[tank] = rows
		out[floor_name] = floor_out
	return out


# ============================================================
# INTERIORS (read off the scene files)
# ============================================================

## "Interior_25" -> 25, anything else -> -1.
static func interior_number(node_name: String) -> int:
	if _regex == null:
		_regex = RegEx.new()
		_regex.compile(INTERIOR_PATTERN)
	var m := _regex.search(node_name)
	return int(m.get_string(1)) if m != null else -1


## Every Interior_<N> number in a floor's scene file, sorted. Read from the PackedScene's
## state, so the scene is never instanced (and it is usually already in SceneCache).
static func scene_interiors(floor_name: String) -> Array:
	if _scene_interiors.has(floor_name):
		return _scene_interiors[floor_name]
	var out: Array = []
	var path: String = FLOOR_SCENES.get(floor_name, "")
	var packed: PackedScene = load(path) if path != "" and ResourceLoader.exists(path) else null
	if packed != null:
		var state := packed.get_state()
		for i in state.get_node_count():
			var n := interior_number(String(state.get_node_name(i)))
			if n >= 0 and n not in out:
				out.append(n)
	out.sort()
	_scene_interiors[floor_name] = out
	return out


## Every expansion number on any floor above 0, lowest first -- the milestones that
## grow the shop.
static func expansion_milestones() -> Array:
	var out: Array = []
	for floor_name in floors():
		for n in scene_interiors(floor_name):
			if n > 0 and n not in out:
				out.append(n)
	out.sort()
	return out


## Which of `numbers` (a floor's Interior_<N>s) should exist with `sent` fish sent. Each
## one reached is added on top of the ones below it -- unless it is in the floor's
## replace_at, in which case everything below it goes. A closed floor shows its lowest.
static func interiors_to_keep(floor_name: String, numbers: Array, sent: int = -1) -> Array:
	if sent < 0:
		sent = GameState.fish_sent_total()
	var reached: Array = []
	for n in numbers:
		if int(n) <= sent:
			reached.append(int(n))
	if not floor_open(floor_name):
		reached = [numbers.min()] if not numbers.is_empty() else []
	var replace_at: Array = floor_config(floor_name).get("replace_at", [])
	var floor_from := -1
	for n in reached:
		if replace_at.has(n) or replace_at.has(float(n)):
			floor_from = maxi(floor_from, n)
	var keep: Array = []
	for n in reached:
		if n >= floor_from:
			keep.append(n)
	return keep


## Dropped by the debug tools so the next read sees edited files.
static func invalidate() -> void:
	_data = {}
	_scene_interiors = {}
