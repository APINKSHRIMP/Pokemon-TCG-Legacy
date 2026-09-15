class_name OverworldPokemonData

## Everything about overworld Pokémon that is DATA rather than behaviour: which
## templates exist, which species belong to each, the per-map spawn files, and the
## dice rolls. Deliberately autoload-free (no GameState / MapManager) so it can be
## loaded by a headless --script check, the same rule CharacterSchedule follows.
##
## Two files:
##   NPC_and_Opponent_Data/Pokemon/Overworld_Pokemon.json   species -> templates + per-species tweaks
##   NPC_and_Opponent_Data/Pokemon/Spawns/<Map>.json        that map's flyer table and spawn points

const REGISTRY_PATH := "res://NPC_and_Opponent_Data/Pokemon/Overworld_Pokemon.json"
const SPAWN_DIR := "res://NPC_and_Opponent_Data/Pokemon/Spawns/"
const SPRITE_DIR := "res://Image_Assets/Pokemon_Sprites/"

## Every template, in the order the editor lists them. A template is a behaviour
## script; adding one means a script, an entry here, and a line in
## OverworldPokemonSpawner.TEMPLATE_SCRIPTS.
const TEMPLATES := ["flyer", "bug_tree", "swinging_bug", "skittish", "burying", "surfacing", "static"]

const TEMPLATE_LABELS := {
	"flyer": "Flying (overhead, map-wide)",
	"bug_tree": "Bug in tree",
	"swinging_bug": "Swinging bug",
	"skittish": "Skittish",
	"burying": "Burying",
	"surfacing": "Surfacing",
	"static": "Static / patrol",
}

const TEMPLATE_DESCRIPTIONS := {
	"flyer": "No spawn point. The map has one table per time of day; the current time's table rolls every INTERVAL seconds with CHANCE% to send a flock of one species (flock size set per species) across the screen from just off one edge to the end of the map. No collision.",
	"bug_tree": "Rolled once per map load. Random facings, shuffles a few pixels every few seconds. No collision, drawn above tree canopies.",
	"swinging_bug": "Rolled once per map load. Hangs on a short silk strand facing one way and sways in a slow U arc. No collision.",
	"skittish": "Rolled once per map load. Wanders around its spawn point at its species' Wander speed. When the player gets close it bolts left, right, randomly or away from the player (Runs away), passing behind trees, and fades out.",
	"burying": "Every INTERVAL seconds, CHANCE% to pop out of the ground with a dirt burst, stay UP TIME seconds, then burrow back down.",
	"surfacing": "Every INTERVAL seconds, CHANCE% to surface out of the water (blue depth tint, splash), drift a couple dozen pixels, then submerge. Give it a water area with V (4 corners) and it surfaces anywhere inside, swims towards the furthest edge, then submerges.",
	"static": "Rolled once per map load. Collision, stands still or walks an existing pattern (idle cycle, patrol line, patrol square). Space to talk.",
}

## Templates whose Pokémon cry while on screen (OverworldPokemon.CRY_CHANCE). Add a
## template name here to give it cries -- nothing else needs to change.
const CRY_TEMPLATES := ["flyer"]

## Rolled once when the map loads. Everything else rolls on a repeating timer.
const ONE_SHOT_TEMPLATES := ["bug_tree", "swinging_bug", "skittish", "static"]
const TIMED_TEMPLATES := ["burying", "surfacing"]

## Which knobs the editor shows per template.
const TEMPLATE_USES_INTERVAL := ["flyer", "burying", "surfacing"]

const STATIC_PATTERNS := ["idle_cycle", "idle_random", "idle_down", "patrol_line", "patrol_square"]

## Which way a skittish Pokémon bolts when the player gets close (spawn point `flee`).
const SKITTISH_FLEE_DIRECTIONS := ["random", "left", "right", "away_from_player"]

## A skittish species' wandering speed in world px/s (registry `wander_speed`). Running
## away is one fixed speed for all of them (PokemonSkittish.FLEE_SPEED).
const DEFAULT_SKITTISH_WANDER_SPEED := 85
const WANDER_SPEED_LIMIT := 300

## A surfacing species' swimming speed while it is up, in world px/s (registry
## `swim_speed`). 0 surfaces, stays put and submerges.
const DEFAULT_SURFACING_SWIM_SPEED := 7
const SWIM_SPEED_LIMIT := 100

## A map's flyers and every spawn point have exactly one table per time of day, keyed
## by the names GameState.get_time() returns. A Pokémon seen at two times is listed in
## both tables; an empty table means nothing spawns at that time.
const TIMES_OF_DAY := ["Morning", "Afternoon", "Evening", "Night"]

## Starting chance / interval of a brand new table. A new spawn point starts at 100%
## so it shows up the first time you look; flyers are meant to be rare.
const POINT_DEFAULT_CHANCE := 100.0
const POINT_DEFAULT_INTERVAL := 10.0
const FLYER_DEFAULT_CHANCE := 15.0
const FLYER_DEFAULT_INTERVAL := 30.0

## Flyer table rows carry only their rate and flock size: {species, percent, min, max}.
## Speed, scale, spin and erratic are NOT per row: they belong to the species (registry
## `speed_min`, `speed_max`, `scale`, `spin`, `erratic`, `bug`, `ghost`), so a species flies the same
## way on every table and every map.
const DEFAULT_FLOCK_MIN := 1
const DEFAULT_FLOCK_MAX := 3
const FLOCK_LIMIT := 12
## World pixels per second. A flock flies at one speed picked from its row's range.
const DEFAULT_FLYER_SPEED_MIN := 35
const DEFAULT_FLYER_SPEED_MAX := 45
const FLYER_SPEED_LIMIT := 400

## A species' size multiplier (registry `scale`), used by every template.
const MIN_SCALE := 0.1
const MAX_SCALE := 20.0

static var _registry: Dictionary = {}
static var _registry_loaded: bool = false
static var _all_species_cache: Array = []


# ============================================================
# REGISTRY
# ============================================================

static func registry() -> Dictionary:
	if not _registry_loaded:
		_registry_loaded = true
		_registry = _read_json(REGISTRY_PATH)
		if not (_registry.get("species") is Dictionary):
			_registry["species"] = {}
	return _registry


static func invalidate() -> void:
	_registry_loaded = false
	_registry = {}


static func species_info(species: String) -> Dictionary:
	var info = registry()["species"].get(species, {})
	return info if info is Dictionary else {}


## "019_Rattata_Alolan" -> "Rattata". The registry can override with `name`.
static func display_name(species: String) -> String:
	var override := str(species_info(species).get("name", ""))
	if override != "":
		return override
	var parts := species.split("_")
	if parts.size() >= 2:
		return parts[1]
	return species


static func species_for_template(template: String) -> Array:
	var out: Array = []
	var all: Dictionary = registry()["species"]
	for key in all:
		var info = all[key]
		if info is Dictionary and (info.get("templates", []) as Array).has(template):
			out.append(str(key))
	out.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


## Every non-shiny sprite sheet in Pokemon_Sprites/, as bare basenames.
static func all_species() -> Array:
	if not _all_species_cache.is_empty():
		return _all_species_cache
	var names: Dictionary = {}
	var dir := DirAccess.open(SPRITE_DIR)
	if dir == null:
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname.trim_suffix(".import").trim_suffix(".remap")
			if clean.ends_with(".png"):
				var base := clean.get_basename()
				if not base.ends_with("_Shiny"):
					names[base] = true
		fname = dir.get_next()
	dir.list_dir_end()
	_all_species_cache = names.keys()
	_all_species_cache.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return _all_species_cache


static func sheet_path(species: String) -> String:
	return SPRITE_DIR + species + ".png"


# ============================================================
# SPAWN FILES
# ============================================================

static func spawn_path(map_data: String) -> String:
	return SPAWN_DIR + map_data + ".json"


## One time-of-day table: its own chance, roll interval and species rows.
static func default_flyer_table() -> Dictionary:
	return {"interval": FLYER_DEFAULT_INTERVAL, "chance": FLYER_DEFAULT_CHANCE, "table": []}


static func default_point_table() -> Dictionary:
	return {"interval": POINT_DEFAULT_INTERVAL, "chance": POINT_DEFAULT_CHANCE, "table": []}


## `tables` reduced to exactly the four time-of-day tables; a missing one is a copy
## of `fallback`.
static func normalise_time_tables(tables, fallback: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for time_name in TIMES_OF_DAY:
		var table = tables.get(time_name) if tables is Dictionary else null
		out[time_name] = table if table is Dictionary else fallback.duplicate(true)
	return out


static func normalise_flyers(flyers) -> Dictionary:
	return normalise_time_tables(flyers, default_flyer_table())


static func normalise_point_tables(tables) -> Dictionary:
	return normalise_time_tables(tables, default_point_table())


## One time's table out of a four-table dictionary ({} if it isn't there).
static func time_table(tables, time_name: String) -> Dictionary:
	var table = tables.get(time_name) if tables is Dictionary else null
	return table if table is Dictionary else {}


## The map's spawn document with every top-level key present. A map with no file
## gets an empty one, so the editor can create the first spawn point anywhere.
static func load_spawns(map_data: String) -> Dictionary:
	var doc := _read_json(spawn_path(map_data))
	doc["flyers"] = normalise_flyers(doc.get("flyers"))
	if not (doc.get("spawn_points") is Array):
		doc["spawn_points"] = []
	for point in doc["spawn_points"]:
		if point is Dictionary:
			point["tables"] = normalise_point_tables(point.get("tables"))
			# A point with no group is a group of one. Clones share their source's group,
			# and editing any point in a group rewrites the rules of all of them.
			if str(point.get("group", "")) == "":
				point["group"] = str(point.get("id", ""))
	return doc


## A surfacing point's water area as a Rect2 in world coordinates, or an empty Rect2 if
## it has none (then it spawns at its `at` like any other point). Stored on the point as
## `region`: [min_x, min_y, max_x, max_y].
static func point_region(point: Dictionary) -> Rect2:
	var r = point.get("region")
	if not (r is Array) or (r as Array).size() != 4:
		return Rect2()
	var corner_a := Vector2(float(r[0]), float(r[1]))
	var corner_b := Vector2(float(r[2]), float(r[3]))
	return Rect2(corner_a, Vector2.ZERO).expand(corner_b)


## Any number of clicked corners snapped to the rectangle around them, as a `region` value.
static func region_from_corners(corners: Array) -> Array:
	if corners.is_empty():
		return []
	var rect := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		rect = rect.expand(corner)
	return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.end.x), roundi(rect.end.y)]


static func find_point(doc: Dictionary, id: String) -> Dictionary:
	for point in doc.get("spawn_points", []):
		if point is Dictionary and str(point.get("id", "")) == id:
			return point
	return {}


static func next_point_id(doc: Dictionary, template: String, reserved: Array = []) -> String:
	var taken: Dictionary = {}
	for point in doc.get("spawn_points", []):
		if point is Dictionary:
			taken[str(point.get("id", ""))] = true
	for id in reserved:
		taken[str(id)] = true
	var n := 1
	while taken.has("%s_%d" % [template, n]):
		n += 1
	return "%s_%d" % [template, n]


# ============================================================
# ROLLS
# ============================================================

static func roll(percent: float) -> bool:
	return randf() * 100.0 < percent


## Pick one species from a [{species, percent}] table. Percentages are weights:
## a table that adds to 100 picks with exactly those odds, and one that doesn't is
## scaled so SOMETHING is always picked -- the spawn chance already decided
## whether anything appears at all.
static func pick_species(table: Array) -> String:
	return str(pick_row(table).get("species", ""))


## Same roll as pick_species, but returns the whole table row ({} if nothing can be
## picked) -- the flyer spawner needs the row's flock size too.
static func pick_row(table: Array) -> Dictionary:
	var total := 0.0
	var last: Dictionary = {}
	for row in table:
		if row is Dictionary:
			total += maxf(0.0, float(row.get("percent", 0)))
			last = row
	if total <= 0.0:
		return {}
	var r := randf() * total
	for row in table:
		if not (row is Dictionary):
			continue
		r -= maxf(0.0, float(row.get("percent", 0)))
		if r < 0.0:
			return row
	return last


## A species' size multiplier: its registry `scale`, else 1.
static func species_scale(species: String) -> float:
	return clampf(float(species_info(species).get("scale", 1.0)), MIN_SCALE, MAX_SCALE)


## A skittish species' wandering speed in world px/s: registry `wander_speed`, else 85.
## 0 is allowed -- it stands its ground (turning now and then) until scared off.
static func species_wander_speed(species: String) -> float:
	return clampf(float(species_info(species).get("wander_speed", DEFAULT_SKITTISH_WANDER_SPEED)),
			0.0, WANDER_SPEED_LIMIT)


## A surfacing species' swimming speed in world px/s: registry `swim_speed`, else 7.
static func species_swim_speed(species: String) -> float:
	return clampf(float(species_info(species).get("swim_speed", DEFAULT_SURFACING_SWIM_SPEED)),
			0.0, SWIM_SPEED_LIMIT)


## A flyer species' speed range in px/s: registry `speed_min` / `speed_max`, else the
## defaults. A flock rolls one speed inside it.
static func species_speed_range(species: String) -> Vector2i:
	var info := species_info(species)
	var low := int(info.get("speed_min", DEFAULT_FLYER_SPEED_MIN))
	var high := int(info.get("speed_max", DEFAULT_FLYER_SPEED_MAX))
	return Vector2i(low, high)


static func table_total(table: Array) -> float:
	var total := 0.0
	for row in table:
		if row is Dictionary:
			total += float(row.get("percent", 0))
	return total


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
