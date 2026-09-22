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
const SPRITE_DIR := "res://Image_Assets/Pokemon_Sprites/Overworld_Sprites/"
const FIELD_GUIDE_DIR := "res://Image_Assets/Pokemon_Sprites/Field_Guide_Sprites/"

## Every template, in the order the editor lists them. A template is a behaviour
## script; adding one means a script, an entry here, and a line in
## OverworldPokemonSpawner.TEMPLATE_SCRIPTS.
const TEMPLATES := ["flyer", "bug_tree", "swinging_bug", "skittish", "burying", "surfacing", "static", "fish_tank", "fishing_spot"]

const TEMPLATE_LABELS := {
	"flyer": "Flying (overhead, map-wide)",
	"bug_tree": "Bug in tree",
	"swinging_bug": "Swinging bug",
	"skittish": "Skittish",
	"burying": "Burying",
	"surfacing": "Surfacing",
	"static": "Static / patrol",
	"fish_tank": "Fish tank",
	"fishing_spot": "Fishing spot (water to cast into)",
}

const TEMPLATE_DESCRIPTIONS := {
	"flyer": "No spawn point. The map has one table per time of day; the current time's table rolls every INTERVAL seconds with CHANCE% to send a flock of one species (flock size set per species) across the screen from just off one edge to the end of the map. No collision.",
	"bug_tree": "Rolled once per map load. Random facings, shuffles a few pixels every few seconds. No collision, drawn above tree canopies.",
	"swinging_bug": "Rolled once per map load. Hangs on a short silk strand facing one way and sways in a slow U arc. No collision.",
	"skittish": "Rolled once per map load. Wanders around its spawn point at its species' Wander speed. When the player gets close it bolts away from the player, in whichever of the four directions its spawn point allows (Runs away), passing behind trees, and fades out. Tick Jumps into water (Krabby, Psyduck) and instead of fading it stops at the first thing it runs into, pauses, leaps -- shadow and all -- and drops under the surface with a splash.",
	"burying": "Every INTERVAL seconds, CHANCE% to pop out of the ground with a dirt burst, stay UP TIME seconds, then burrow back down.",
	"surfacing": "Every INTERVAL seconds, CHANCE% to surface out of the water (blue depth tint, splash), drift a couple dozen pixels, then submerge. Give it a water area with V (4 corners) and it surfaces anywhere inside, swims towards the furthest edge, then submerges.",
	"static": "Rolled once per map load. Collision, stands still or walks an existing pattern (idle cycle, patrol line, patrol square). Space to talk.",
	"fish_tank": "An aquarium. Unlike every other template this one spawns EVERY species in its table (Count each) at once, inside the swim area you draw with V, and it ignores the time of day -- one table per tank. They cruise left and right at their own Swim speed, spinning round at the glass, drifting very slowly up and down, and turning round when two of them bump nose to nose. Bubbles rise from their mouths to the surface every few seconds.",
	"fishing_spot": "A patch of water that can be fished. It spawns nothing at all: what it holds is the water rectangle a hooked fish fights inside (draw it with V, 4 corners) and one table per time of day of what bites there. A cast always rolls exactly ONE fish from the table of the spot NEAREST the player, so two spots on the same map fish differently. An empty table means nothing bites at that time and the bait is stolen. The six numbers after Scale are the fight, and they belong to the SPECIES -- the same on every spot, map and time of day.",
}

## A template that puts NOTHING on the map. A fishing spot is a rectangle of water and a
## table of what bites in it -- it is only a spawn point so that it can be placed, drawn,
## selected and edited with everything else. The spawner skips these outright.
const NON_SPAWNING_TEMPLATES := ["fishing_spot"]

## Templates whose Pokémon cry while on screen (OverworldPokemon.CRY_CHANCE): all the
## ones that actually put a Pokémon out -- anything the player can see, flying overhead
## or sitting in a tree, has the same small chance of calling out. Take a name out of
## this list to silence that template; nothing else needs to change.
const CRY_TEMPLATES := ["flyer", "bug_tree", "swinging_bug", "skittish", "burying", "surfacing", "static", "fish_tank"]

## Rolled once when the map loads. Everything else rolls on a repeating timer.
const ONE_SHOT_TEMPLATES := ["bug_tree", "swinging_bug", "skittish", "static"]
const TIMED_TEMPLATES := ["burying", "surfacing"]

## Which knobs the editor shows per template.
const TEMPLATE_USES_INTERVAL := ["flyer", "burying", "surfacing"]

## Templates whose spawn point is an AREA rather than a spot: the placement tool sends a
## new one straight into corner capture (V), the point's `at` becomes the centre of what
## you draw, and the marker draws the rectangle.
const REGION_TEMPLATES := ["surfacing", "fish_tank", "fishing_spot"]

## FISH TANK. The odd one out in every way: its table is not rolled, it is not a time of
## day and it is not a chance -- a tank puts out EVERY row in it, `count` of each, the
## moment the map loads, and they stay. The rows live on the point as `fish_table`
## ([{species, count}]) rather than in `tables`, because a tank indoors has no morning.
const TANK_TEMPLATE := "fish_tank"

## FISHING SPOT. Not a spawn point at all in the end: the rectangle it draws is the water
## a hooked fish fights in, and its four tables are what bites there. Which spot a cast
## uses is worked out from where the player is standing (fishing_spot_at), so the
## Fish_* rectangles in the map scene name nothing and stay as they are.
const FISHING_TEMPLATE := "fishing_spot"
## The water a spot falls back on when its region was never drawn (world px, half
## extents around `at`), so a half-finished spot is still castable.
const DEFAULT_FISHING_SIZE := Vector2(120, 80)
const DEFAULT_TANK_COUNT := 1
const TANK_COUNT_LIMIT := 12
## A tank fish's cruising speed in world px/s (registry `tank_speed`). Slow: 14 world px
## is 35 on screen at the default 2.5x zoom, so it crosses a 300px tank in ten seconds.
const DEFAULT_TANK_SPEED := 14
const TANK_SPEED_LIMIT := 120
## The swim area a tank falls back on when its region was never drawn (world px, half
## extents around `at`), so a half-finished tank still shows something.
const DEFAULT_TANK_SIZE := Vector2(60, 26)
## Speed and size are the SPECIES' own, as everywhere else -- but a row of identical
## fish looks like a row of identical fish, so a tank fish's size is nudged up to this
## much either way. Not with randf(): the wobble is worked out from the species name and
## the fish's place in its row, so the five Magikarp in one tank come out five slightly
## different sizes AND the five in the tank next door come out exactly the same five.
const TANK_SIZE_VARIATION := 0.1

const STATIC_PATTERNS := ["idle_cycle", "idle_random", "idle_down", "patrol_line", "patrol_square"]

## The ways a skittish Pokémon may bolt when the player gets close. The spawn point's
## `flee` is the list of the ones it is ALLOWED to take; out of those it runs whichever
## heads away from the player (see PokemonSkittish._flee_direction). Tick all four and
## it always has somewhere to go; tick only "left" and it always bolts left, player or
## no player.
const SKITTISH_FLEE_DIRECTIONS := ["left", "right", "up", "down"]


## A spawn point's allowed run-away directions, cleaned up: known names only, no
## duplicates, and an empty or missing list (or a hand-edited one that is not a list at
## all) means all four are allowed.
static func flee_directions(point: Dictionary) -> Array:
	var raw = point.get("flee", [])
	var allowed: Array = []
	if raw is Array:
		for entry in raw:
			var name := str(entry)
			if SKITTISH_FLEE_DIRECTIONS.has(name) and not allowed.has(name):
				allowed.append(name)
	return allowed if not allowed.is_empty() else SKITTISH_FLEE_DIRECTIONS.duplicate()

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

## ---- fishing --------------------------------------------------------------
## The six numbers below are the whole of a fish's fight. They belong to the SPECIES, in
## the registry beside `scale` and `speed_min` -- a Magikarp fights a Magikarp's fight on
## every map and at every time of day, so there is one place to tune it. (A fish table
## may list a species the registry has no entry for; saving one of these creates the
## entry with an empty `templates` list, which spawns it nowhere.)
##
## Every default is exactly what the fight used before these were tunable, so a species
## without them behaves as it always did. Distances and speeds are WORLD pixels
## (on-screen pixels / 2.5); FISH_STAT_LIMITS bounds each one for the editor's boxes.
##
##   energy            stamina bar. Countering correctly drains it; at 0 the fish is
##                     blown and the reeling window opens.
##   line_strength     how far the line can be loaded either way before it snaps
##                     (a single number: 80 means -80 slack .. +80 snapped).
##   recharge_time     seconds the blown fish rests -- the length of the reel-in window,
##                     after which it is back to full energy.
##   reel_step         world px the fish is dragged in per reel press.
##   initial_distance  world px the strike runs it out BEYOND THE BOBBER -- added to
##                     wherever the bobber landed, not measured from the player. 0 is no
##                     run at all; it was an absolute distance from the player while the
##                     cast was a fixed 160, which it no longer is (the throw is half the
##                     fishing spot's water now, so it differs per spot).
##   lateral_speed     world px/s it runs left and right across the cast.
##   fish_size         multiplier on the SILHOUETTE the minigame draws, 1 = as drawn.
##                     This is what the Scale box edits on a FISH row -- the shared
##                     `scale` key is left alone there, because the silhouettes are
##                     already drawn at the right size and `scale` belongs to the
##                     overworld spawns. 0.8 is a fifth smaller, 1.2 a fifth bigger.
const FISH_STAT_DEFAULTS := {
	"energy": 100.0,
	"line_strength": 100.0,
	"recharge_time": 2.0,
	"reel_step": 6.0,
	"initial_distance": 50.0,
	"lateral_speed": 110.0,
	"fish_size": 1.0,
}
## key -> [min, max, step] for the FISH TABLE editor's number boxes.
const FISH_STAT_LIMITS := {
	"energy": [1.0, 1000.0, 1.0],
	"line_strength": [1.0, 1000.0, 1.0],
	"recharge_time": [0.1, 30.0, 0.1],
	"reel_step": [0.5, 200.0, 0.5],
	"initial_distance": [0.0, 500.0, 5.0],
	"lateral_speed": [0.0, 1000.0, 5.0],
	"fish_size": [0.3, 3.0, 0.1],
}
## The order the boxes appear in, and the caption on each. Kept to one short word each:
## all six share a single line with the name, rate and scale, so there is no room for
## prose -- the tooltip is where the explanation lives.
const FISH_STAT_LABELS := {
	"energy": "Energy",
	"line_strength": "Line",
	"recharge_time": "Rest",
	"reel_step": "Reel",
	"initial_distance": "Dist",
	"lateral_speed": "Speed",
}

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


## Every non-shiny sprite sheet in Pokemon_Sprites/Overworld_Sprites/, as bare basenames.
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
# FIELD GUIDE ART
# ============================================================
# A SECOND sprite per species, in Field_Guide_Sprites/, keyed by exactly the same
# basename as the overworld sheet. The overworld sheet is a 4x4 walk cycle; this
# one is a single front-facing portrait, and it is what the Field Guide screen
# shows large. Both live under Pokemon_Sprites/ so a species is one name in two
# folders and nothing has to map between them.
#
# Not every species has a Shiny portrait (four are missing from the art dump), so
# always test the path before loading one.

static func field_guide_path(species: String, shiny: bool = false) -> String:
	return FIELD_GUIDE_DIR + species + ("_Shiny" if shiny else "") + ".png"


static func has_field_guide_art(species: String, shiny: bool = false) -> bool:
	return ResourceLoader.exists(field_guide_path(species, shiny))


## "019_Rattata_Alolan" -> 19. 0 when the basename does not start with a number.
static func dex_number(species: String) -> int:
	var parts := species.split("_")
	return int(parts[0]) if parts.size() >= 1 and parts[0].is_valid_int() else 0


## "019_Rattata_Alolan" -> "019 Rattata (Alolan)". The Field Guide's caption.
static func guide_label(species: String) -> String:
	var parts := species.split("_")
	var number := str(parts[0]) if parts.size() >= 1 else ""
	var form := ""
	if parts.size() > 2:
		form = " (" + " ".join(Array(parts).slice(2)).replace("_", " ") + ")"
	return "%s %s%s" % [number, display_name(species), form]


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


## A fishing spot's table is the odd one out: a cast always rolls exactly one fish, so
## there is no spawn chance, no roll interval and no flock size -- just the species rows.
static func default_fish_table() -> Dictionary:
	return {"table": []}


static func normalise_fishing_tables(tables) -> Dictionary:
	return normalise_time_tables(tables, default_fish_table())


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
			# A fishing spot has the same four tables as any other point, but they carry
			# only species rows: a cast is not a chance and not on a timer.
			if str(point.get("template", "")) == FISHING_TEMPLATE:
				point["tables"] = normalise_fishing_tables(point.get("tables"))
			else:
				point["tables"] = normalise_point_tables(point.get("tables"))
			# A fish tank's species live on the point as `fish_table`, not in the four
			# time-of-day tables: an aquarium indoors has no morning or night.
			if str(point.get("template", "")) == TANK_TEMPLATE and not (point.get("fish_table") is Array):
				point["fish_table"] = []
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


## A species' six fight numbers, each taken from its registry entry, else
## FISH_STAT_DEFAULTS, and clamped to its FISH_STAT_LIMITS range. Every key is always
## present, so the result can be read without a .get. "" gives the defaults.
static func fish_stats(species: String) -> Dictionary:
	var info := species_info(species)
	var out: Dictionary = {}
	for key in FISH_STAT_DEFAULTS:
		var value := float(info.get(key, FISH_STAT_DEFAULTS[key]))
		var limits: Array = FISH_STAT_LIMITS[key]
		out[key] = clampf(value, float(limits[0]), float(limits[1]))
	return out


## True when this species is hooked as one of the BIG silhouettes rather than the small
## ones -- the `big` tick on its FISH TABLE row. Species-wide, like every fish stat.
static func species_big_fish(species: String) -> bool:
	return bool(species_info(species).get("big", false))


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


## A tank fish's cruising speed in world px/s: registry `tank_speed`, else 14. Species-
## wide, like every other speed -- a Goldeen swims a Goldeen's swim in every aquarium.
static func species_tank_speed(species: String) -> float:
	return clampf(float(species_info(species).get("tank_speed", DEFAULT_TANK_SPEED)),
			0.0, TANK_SPEED_LIMIT)


## A fish tank's rows, [{species, count}]. Cleaned up: a row with no species is dropped
## and a missing or silly count becomes 1.
static func tank_rows(point: Dictionary) -> Array:
	var out: Array = []
	var rows = point.get("fish_table", [])
	if not (rows is Array):
		return out
	for row in rows:
		if not (row is Dictionary):
			continue
		var species := str(row.get("species", ""))
		if species == "":
			continue
		out.append({
			"species": species,
			"count": clampi(int(row.get("count", DEFAULT_TANK_COUNT)), 1, TANK_COUNT_LIMIT),
		})
	return out


## How many fish a tank puts out in total -- what the spawn marker shows.
static func tank_total(point: Dictionary) -> int:
	var total := 0
	for row in tank_rows(point):
		total += int(row["count"])
	return total


## The water a tank's fish swim in: its `region`, else a default-sized box around `at`.
static func tank_region(point: Dictionary) -> Rect2:
	var region := point_region(point)
	if region.has_area():
		return region
	var at = point.get("at", [0, 0])
	var centre := Vector2(float(at[0]), float(at[1]))
	return Rect2(centre - DEFAULT_TANK_SIZE, DEFAULT_TANK_SIZE * 2.0)


## ---- fishing spots ---------------------------------------------------------

## Every fishing spot in a map's spawn document, in file order.
static func fishing_spots(doc: Dictionary) -> Array:
	var out: Array = []
	for point in doc.get("spawn_points", []):
		if point is Dictionary and str(point.get("template", "")) == FISHING_TEMPLATE:
			out.append(point)
	return out


## The water a spot's fish fights in: its `region`, else a default-sized box around `at`.
## Same shape as tank_region -- an undrawn area still gives the minigame something.
static func fishing_region(point: Dictionary) -> Rect2:
	var region := point_region(point)
	if region.has_area():
		return region
	var at = point.get("at", [0, 0])
	var centre := Vector2(float(at[0]), float(at[1]))
	return Rect2(centre - DEFAULT_FISHING_SIZE, DEFAULT_FISHING_SIZE * 2.0)


## The fishing spot a cast from `world_pos` belongs to, out of `spots`: the one whose
## water the player is stood in, else the one whose water is NEAREST them. Exactly how a
## point in a tank finds its glass (_tank_front_at) -- nothing names a node, so several
## spots on one map need no naming convention and no scene edits.
static func nearest_fishing_spot(spots: Array, world_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for point in spots:
		if not (point is Dictionary):
			continue
		var water := fishing_region(point)
		if water.has_point(world_pos):
			return point
		# Distance to the rectangle itself, not to its centre: a long pier's water would
		# otherwise lose to a small pond the player is further from but centred on.
		var nearest := Vector2(
				clampf(world_pos.x, water.position.x, water.end.x),
				clampf(world_pos.y, water.position.y, water.end.y))
		var distance := world_pos.distance_squared_to(nearest)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


## The size of the `index`-th fish of `species` in a tank: the species' scale with its
## deterministic TANK_SIZE_VARIATION wobble (see that constant).
static func tank_fish_scale(species: String, index: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [species, index])
	var wobble := rng.randf_range(-TANK_SIZE_VARIATION, TANK_SIZE_VARIATION)
	return clampf(species_scale(species) * (1.0 + wobble), MIN_SCALE, MAX_SCALE)



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
