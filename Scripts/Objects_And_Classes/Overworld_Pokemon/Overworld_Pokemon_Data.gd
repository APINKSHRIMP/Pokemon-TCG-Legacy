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
const TEMPLATES := ["flyer", "bug_tree", "swinging_bug", "rodent", "burying", "surfacing", "static"]

const TEMPLATE_LABELS := {
	"flyer": "Flying (overhead, map-wide)",
	"bug_tree": "Bug in tree",
	"swinging_bug": "Swinging bug",
	"rodent": "Rodent",
	"burying": "Burying",
	"surfacing": "Surfacing",
	"static": "Static / patrol",
}

const TEMPLATE_DESCRIPTIONS := {
	"flyer": "No spawn point. The map has one table per time of day; the current time's table rolls every INTERVAL seconds with CHANCE% to send a flock of one species (flock size set per species) across the screen from just off one edge to the end of the map. No collision.",
	"bug_tree": "Rolled once per map load. Random facings, shuffles a few pixels every few seconds. No collision, drawn above tree canopies.",
	"swinging_bug": "Rolled once per map load. Hangs still on silk, turns left-down-right-down about once a second and sways in a slow U arc. No collision.",
	"rodent": "Rolled once per map load. Fast wide wander with collision. Flees off-screen if approached running / at Fast speed; Space to talk otherwise.",
	"burying": "Every INTERVAL seconds, CHANCE% to pop out of the ground with a dirt burst, stay UP TIME seconds, then burrow back down.",
	"surfacing": "Every INTERVAL seconds, CHANCE% to surface out of the water (blue depth tint, splash), drift a couple dozen pixels, then submerge.",
	"static": "Rolled once per map load. Collision, stands still or walks an existing pattern (idle cycle, patrol line, patrol square). Space to talk.",
}

## Rolled once when the map loads. Everything else rolls on a repeating timer.
const ONE_SHOT_TEMPLATES := ["bug_tree", "swinging_bug", "rodent", "static"]
const TIMED_TEMPLATES := ["burying", "surfacing"]

## Which knobs the editor shows per template.
const TEMPLATE_USES_INTERVAL := ["flyer", "burying", "surfacing"]

const STATIC_PATTERNS := ["idle_cycle", "idle_random", "idle_down", "patrol_line", "patrol_square"]

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

## Flyer table rows carry their own flock size: {species, percent, min, max}.
const DEFAULT_FLOCK_MIN := 1
const DEFAULT_FLOCK_MAX := 3
const FLOCK_LIMIT := 12

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
	return doc


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
