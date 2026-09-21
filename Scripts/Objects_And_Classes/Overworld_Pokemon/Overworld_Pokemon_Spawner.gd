class_name OverworldPokemonSpawner
extends Node2D

## One per loaded map (BaseMapScene attaches it). Reads that map's
## Pokemon/Spawns/<Map>.json and puts Pokémon into the world:
##
##   bug_tree, swinging_bug, skittish, static rolled ONCE, when the map loads
##   burying, surfacing                       rolled every `interval` seconds while
##                                            nothing from that point is out
##   flyers                                   map-wide, one table per time of day:
##                                            every `interval` seconds the current
##                                            time's table has `chance`% to send a
##                                            flock of one species
##                                            (size from that species' table row)
##                                            across the screen
##
## Every point (and the flyers) has one table per time of day. A roll uses the table
## for the current time: its `chance` first, then a species from its rows. An empty
## table spawns nothing at that time.
## Nothing is saved: a battle, a door or a debug reload rebuilds the map and rolls
## again, which is what "every time the scene is reloaded" means.
##
## The placement tool asks this for spawn-point MARKERS (show_markers / hide_markers)
## so spawn points can be selected, grabbed and edited like characters.

const GROUP := "pokemon_spawner"

## Template name -> a fresh node of its behaviour script, or null for an unknown
## name. (A match, not a const Dictionary: class names are not constant expressions.)
static func make_pokemon(template: String) -> OverworldPokemon:
	match template:
		"flyer":        return PokemonFlyer.new()
		"bug_tree":     return PokemonTreeBug.new()
		"swinging_bug": return PokemonSwingingBug.new()
		"skittish":     return PokemonSkittish.new()
		"burying":      return PokemonBurrower.new()
		"surfacing":    return PokemonSurfacer.new()
		"static":       return PokemonStatic.new()
		"fish_tank":    return PokemonFishTank.new()
	return null

# ---- tweakables -------------------------------------------------------------
## Flyers already in the air past which a tick spawns nothing.
const MAX_LIVE_FLYERS := 16
## How far outside the camera's edge a flock starts.
const FLYER_EDGE_MARGIN := 32.0
## A flock is scattered inside this box, trailing behind its leader.
const FLYER_GROUP_SPREAD := Vector2(96, 56)
## Minimum distance between the centres of two flock members, so none overlap.
const FLYER_MIN_SEPARATION := 36.0
## Random placements tried per member before taking the least-crowded one.
const FLYER_PLACE_ATTEMPTS := 12
## Keeps flocks from spawning right against the top/bottom of the screen.
const FLYER_VERTICAL_PADDING := 24.0
## Head-on misses: a flock never starts within this much of the height of a flyer
## already crossing the other way, or the two streams fly straight through each other.
## Too close and the start height moves FLYER_HEADON_SHIFT up or down -- whichever
## leaves the bigger gap, still inside the screen. 80 world px = 200 px on screen at
## the default (and widest) 2.5x camera zoom.
const FLYER_HEADON_GAP := 80.0
const FLYER_HEADON_SHIFT := 80.0
## How far past the camera limit a flyer carries on before it despawns.
const FLYER_END_MARGIN := 64.0
## Guaranteed flocks: if this many seconds pass with no flock spawning at all, one is
## sent regardless of the table's chance (still capped by MAX_LIVE_FLYERS, and only if
## the current time of day has flyers). Any flock -- rolled or guaranteed -- restarts
## the wait, so lucky rolls can still add extras in between.
const FLYER_GUARANTEE_SECONDS := 20.0
const FLYER_GUARANTEE_SECONDS_NIGHT := 30.0
## Elbow room for spawn points: a point does not put a Pokémon out if one of its own
## kind is already out within this box of where it would appear. These are HALF the
## box, so the whole of it is 900 x 500 px on screen -- about a screenful -- at the
## default 2.5x camera zoom (450 x 250 either side, / 2.5 for world px).
## Flyers passing overhead never count, and surfacing Pokémon are their own kind: a
## Magikarp out on a pond has nothing to do with a Caterpie on the bank, but two
## surfacing points still keep their distance from each other.
const GROUND_SPACING := Vector2(180.0, 100.0)
## Seconds before a burying/surfacing point first rolls: random within 1..interval,
## so every point on the map does not pop on the same frame.
const FIRST_ROLL_MIN := 1.0
## Placement-tool preview: seconds before a burying / surfacing Pokémon comes back up
## after going down.
const PREVIEW_RESPAWN_DELAY := 0.5
## Forced preview: seconds between flocks (ignoring chance and interval), still capped
## by MAX_LIVE_FLYERS. Species take turns in table order rather than by rate.
const PREVIEW_FLYER_INTERVAL := 1.5
## DRAWING BEHIND A MAP OBJECT -- any spawn point, any template.
##
## Indoors NOTHING has a z_index: the floor, the sand, the glass front of a tank, the
## player and the walls are all z 0, and what covers what is decided by the ORDER OF THE
## SCENE TREE. A Pokemon parented to the spawner (added last, after the tilemaps) always
## draws over the lot, which is wrong for anything meant to be inside a tank.
##
## So a point may carry `front`: the name -- or the path, on a map with two of them -- of
## a map object. Its Pokemon is then parented as a SIBLING of that object, one place
## before it, and dropped to relative z 0 so the tree is what decides. In the Fish Shop
## that is in front of the sand, behind the glass, and under the player, who is a later
## sibling of the whole tilemap.
##
## A point asks for this with one tick box, `in_tank` (a fish_tank template always does).
## Everything else is worked out here: every tank's glass in the map is a TileMapLayer
## called TANK_FRONT_NAME, and the one a Pokemon goes behind is simply the tank it is
## standing in -- or, if it is not inside any of them, the nearest. That is what lets a
## bug-in-tree or an idle Pokemon be dropped into any of the Fish Shop's five aquariums
## without naming one.
const TANK_FRONT_NAME := "FishTankFront"
## Random spots tried per fish before taking the least crowded, and how far apart two
## fish would rather start (world px).
const TANK_PLACE_ATTEMPTS := 12
const TANK_MIN_SEPARATION := 24.0
## Where a tank's fish draw when the map has no tank glass at all: above the ground,
## below most things. Only a tank placed on a map with no FishTankFront reaches this.
const TANK_FALLBACK_Z := 1
# -----------------------------------------------------------------------------

var map_data: String = ""
var doc: Dictionary = {}

var _player: Node2D = null
## point id -> the Pokémon it currently has out
var _live: Dictionary = {}
## point id -> seconds until the next roll
var _timers: Dictionary = {}
## tank point id -> the fish it put out. Kept apart from _live because a tank has many
## Pokémon out at once and they are not children of this node.
var _tanks: Dictionary = {}
var _flyer_timer: float = 0.0
## Seconds since the last flock spawned, for the guaranteed flock.
var _since_last_flock: float = 0.0
var _flyers: Array = []
var _markers: Array = []
## True while the placement tool is open. Every spawn point then shows a Pokémon
## whatever its chance (and, if this time of day's table is empty, from the first time
## of day that has one), and burying / surfacing points pop straight back up.
var preview: bool = false
## Forced preview's turn-taking through the flyer table.
var _preview_flyer_index: int = -1


static func attach(map_root: Node, map_name: String, player: Node2D) -> OverworldPokemonSpawner:
	var spawner := OverworldPokemonSpawner.new()
	spawner.name = "OVERWORLD_POKEMON"
	spawner.map_data = map_name
	spawner._player = player
	map_root.add_child(spawner)
	return spawner


func _ready() -> void:
	add_to_group(GROUP)
	apply_doc(OverworldPokemonData.load_spawns(map_data))


## Replace the spawn data and roll everything afresh. The placement tool calls this
## after a save so new spawn points show up without reloading the map.
func apply_doc(new_doc: Dictionary) -> void:
	clear_pokemon()
	doc = new_doc
	_timers.clear()
	var time_name: String = GameState.get_time()
	var one_shots: Array = []
	for point in doc.get("spawn_points", []):
		if not (point is Dictionary):
			continue
		var template := str(point.get("template", ""))
		if not OverworldPokemonData.TEMPLATES.has(template):
			push_warning("OverworldPokemonSpawner: unknown template '%s' on %s" % [template, point.get("id", "?")])
			continue
		if template == OverworldPokemonData.TANK_TEMPLATE:
			# A tank is not rolled and has no timer: its whole table goes in, now.
			_spawn_tank(point)
		elif OverworldPokemonData.ONE_SHOT_TEMPLATES.has(template):
			one_shots.append(point)
		elif OverworldPokemonData.TIMED_TEMPLATES.has(template):
			var config := _config_for(point, time_name)
			if preview:
				_spawn_at(point, config)
			else:
				_timers[str(point.get("id", ""))] = randf_range(FIRST_ROLL_MIN, maxf(FIRST_ROLL_MIN, _interval(config)))
	# Shuffled, because GROUND_SPACING lets whoever goes first through and crowds the
	# rest out: in file order a dense map would thin down to the same handful of points
	# every load. (Preview ignores the spacing, so the order makes no odds there.)
	one_shots.shuffle()
	for point in one_shots:
		var config := _config_for(point, time_name)
		if preview or OverworldPokemonData.roll(float(config.get("chance", 0))):
			_spawn_at(point, config)
	# Forced preview sends the first flock almost at once rather than after a full interval.
	_flyer_timer = 0.2 if preview else _interval(_flyer_config(time_name))
	_since_last_flock = 0.0


func clear_pokemon() -> void:
	for child in get_children():
		if child is OverworldPokemon:
			child.despawn()
	# Anything in a tank lives elsewhere in the scene tree -- beside the glass it draws
	# behind -- so the loop above never sees it. Without this a preview toggle
	# or a save would leave the old one there and spawn another beside it.
	# (values() is a copy, so despawn()'s `gone` erasing from _live is safe here.)
	for pokemon in _live.values():
		_remove_pokemon(pokemon)
	for id in _tanks.keys():
		_clear_tank(str(id))
	_tanks.clear()
	_live.clear()
	_flyers.clear()


## Take a Pokemon out of the world. remove_child BEFORE queue_free: it is not freed
## until the end of the frame, and until then it is still a child that the placement
## tool's actor refresh would pick back up.
func _remove_pokemon(pokemon) -> void:
	if pokemon == null or not is_instance_valid(pokemon):
		return
	var parent: Node = pokemon.get_parent()
	if parent != null:
		parent.remove_child(pokemon)
	pokemon.despawn()


func _process(delta: float) -> void:
	var time_name: String = GameState.get_time()
	for point in doc.get("spawn_points", []):
		if not (point is Dictionary):
			continue
		if not OverworldPokemonData.TIMED_TEMPLATES.has(str(point.get("template", ""))):
			continue
		var id := str(point.get("id", ""))
		if _live.has(id):
			continue
		# The table for right now, so a time-of-day change mid-map switches species and odds.
		var config := _config_for(point, time_name)
		_timers[id] = float(_timers.get(id, _interval(config))) - delta
		if _timers[id] > 0.0:
			continue
		_timers[id] = _interval(config)
		if preview or OverworldPokemonData.roll(float(config.get("chance", 0))):
			_spawn_at(point, config)
	_process_flyers(delta, time_name)


func _interval(config: Dictionary) -> float:
	return maxf(0.5, float(config.get("interval", 10)))


# ============================================================
# SPAWN POINTS
# ============================================================

## The table a point rolls from right now: this time of day's. In preview, an empty one
## falls back to the first time of day that has Pokémon in it, so every point shows one.
func _config_for(point: Dictionary, time_name: String) -> Dictionary:
	var config := OverworldPokemonData.time_table(point.get("tables"), time_name)
	if not preview or not (config.get("table", []) as Array).is_empty():
		return config
	for other in OverworldPokemonData.TIMES_OF_DAY:
		var fallback := OverworldPokemonData.time_table(point.get("tables"), str(other))
		if not (fallback.get("table", []) as Array).is_empty():
			return fallback
	return config


## `on` forces everything out (spawn points and flyers); off uses the real chances.
## `working_doc` is the placement tool's working copy, held by reference so moves and
## edits are seen live -- the tool passes it for both FORCED and RANDOM. With no
## working doc (the tool closing) it goes back to the saved file.
func set_preview(on: bool, working_doc: Dictionary = {}) -> void:
	preview = on
	_preview_flyer_index = -1
	apply_doc(working_doc if not working_doc.is_empty() else OverworldPokemonData.load_spawns(map_data))


## Re-show one point after the placement tool placed, moved, edited or deleted it:
## whatever it has out goes, and (if the point still exists) a fresh Pokémon appears at
## its current spot straight away.
func respawn_point(id: String) -> void:
	# A tank: the whole tankful goes and comes back, whatever the chance says.
	var tank := OverworldPokemonData.find_point(doc, id)
	if _tanks.has(id) or str(tank.get("template", "")) == OverworldPokemonData.TANK_TEMPLATE:
		_clear_tank(id)
		if not tank.is_empty():
			_spawn_tank(tank)
		return
	var existing = _live.get(id)
	_live.erase(id)
	_remove_pokemon(existing)
	var point := OverworldPokemonData.find_point(doc, id)
	if point.is_empty():
		return
	var config := _config_for(point, GameState.get_time())
	if preview or OverworldPokemonData.roll(float(config.get("chance", 0))):
		_spawn_at(point, config)


## `config` is the point's table for the current time of day.
func _spawn_at(point: Dictionary, config: Dictionary) -> OverworldPokemon:
	var row := OverworldPokemonData.pick_row(config.get("table", []))
	var species := str(row.get("species", ""))
	if species == "":
		return null
	var template := str(point.get("template", ""))
	var at = point.get("at", [0, 0])
	var spawn_pos := Vector2(float(at[0]), float(at[1]))
	# A point with a water area (surfacing) comes up anywhere inside it.
	var region := OverworldPokemonData.point_region(point)
	if region.has_area():
		spawn_pos = Vector2(randf_range(region.position.x, region.end.x),
				randf_range(region.position.y, region.end.y)).round()
	# Elbow room: this roll is dropped if one of its own kind is already out too close.
	# The placement tool's preview shows every point whatever is around it.
	if not preview and _is_crowded(template, spawn_pos):
		return null
	var pokemon := make_pokemon(template)
	if pokemon == null:
		return null
	pokemon.configure(species, point)
	pokemon.size_scale = OverworldPokemonData.species_scale(species)
	pokemon.can_cry = OverworldPokemonData.CRY_TEMPLATES.has(template)
	var id := str(point.get("id", ""))
	pokemon.gone.connect(_on_pokemon_gone.bind(id))
	# A point with `in_tank` goes behind the glass of whichever tank it stands in,
	# instead of into the spawner -- a bug in a tree, or an idle Pokemon, in an aquarium.
	_place_pokemon(pokemon, point, spawn_pos)
	_live[id] = pokemon
	return pokemon


## True if a Pokémon of the same kind is already out within GROUND_SPACING of
## `spawn_pos` (a global position). "Kind" is only surfacing vs everything else on the
## ground: bugs, skittish, burrowers and static Pokémon all crowd each other out,
## while a surfacing Pokémon is blocked by other surfacing ones alone. Flyers are not
## in `_live` at all, so they never block anything.
func _is_crowded(template: String, spawn_pos: Vector2) -> bool:
	var surfacing := template == "surfacing"
	for pokemon in _live.values():
		if not is_instance_valid(pokemon):
			continue
		if (str(pokemon.spawn_point.get("template", "")) == "surfacing") != surfacing:
			continue
		var offset: Vector2 = (pokemon.global_position - spawn_pos).abs()
		if offset.x <= GROUND_SPACING.x and offset.y <= GROUND_SPACING.y:
			return true
	return false




# ============================================================
# FISH TANKS
# ============================================================

## Fill one tank. Every row of `fish_table` puts out `count` fish, spread around inside
## the swim area (`region`, drawn with V in the placement tool). Nothing here is rolled
## and nothing is timed: a tank looks the same every time you walk into the shop, at any
## hour. See TANK_FRONT_NAME for why the fish are parented where they are.
func _spawn_tank(point: Dictionary) -> void:
	var id := str(point.get("id", ""))
	_clear_tank(id)
	var region := OverworldPokemonData.tank_region(point)
	var fish: Array = []
	var placed: Array[Vector2] = []
	for row in OverworldPokemonData.tank_rows(point):
		var species := str(row["species"])
		for i in int(row["count"]):
			var pokemon := PokemonFishTank.new()
			pokemon.configure(species, point)
			pokemon.tank_id = id
			pokemon.tank_region = region
			# Speed is the species'. Size is too, wobbled by this fish's place in the
			# row -- the same set of sizes in every tank that holds this species.
			pokemon.size_scale = OverworldPokemonData.tank_fish_scale(species, i)
			pokemon.can_cry = OverworldPokemonData.CRY_TEMPLATES.has(OverworldPokemonData.TANK_TEMPLATE)
			var spot := _tank_spot(region, placed)
			placed.append(spot)
			if _place_pokemon(pokemon, point, spot) == null:
				# No tank glass anywhere on this map: fall back to an absolute z so the
				# fish are at least visible.
				pokemon.z_as_relative = false
				pokemon.z_index = TANK_FALLBACK_Z
			fish.append(pokemon)
	_tanks[id] = fish


## Somewhere inside the water for the next fish: the least crowded of a few tries, so a
## tankful does not start in a heap.
func _tank_spot(region: Rect2, placed: Array[Vector2]) -> Vector2:
	var best := region.get_center()
	var best_gap := -1.0
	for attempt in TANK_PLACE_ATTEMPTS:
		var candidate := Vector2(randf_range(region.position.x, region.end.x),
				randf_range(region.position.y, region.end.y))
		var gap := INF
		for other in placed:
			gap = minf(gap, candidate.distance_to(other))
		if gap >= TANK_MIN_SEPARATION:
			return candidate
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


## The glass this point's Pokemon are drawn behind, or null for the ordinary
## spawner-child placement. Every fish tank does it; any other point does it by ticking
## `in_tank`. Which of the map's tanks is decided by where the Pokemon actually is.
func _point_front(point: Dictionary, spawn_pos: Vector2) -> CanvasItem:
	var is_tank := str(point.get("template", "")) == OverworldPokemonData.TANK_TEMPLATE
	if not is_tank and not bool(point.get("in_tank", false)):
		return null
	return _tank_front_at(spawn_pos)


## The glass of the tank `spawn_pos` is inside, else the nearest one, else null when the
## map has no tanks at all. Every tank's front is a layer of the same name in its own
## group (MART/FISHTANK, MART/FISHTANK2, ...), so they are told apart by where they are,
## not by what they are called.
func _tank_front_at(spawn_pos: Vector2) -> CanvasItem:
	var root := get_parent()
	if root == null:
		return null
	var nearest: CanvasItem = null
	var nearest_distance := INF
	for node in root.find_children(TANK_FRONT_NAME, "", true, false):
		var glass := node as CanvasItem
		if glass == null:
			continue
		var rect := _front_rect(glass)
		if rect.has_point(spawn_pos):
			return glass
		var distance := rect.get_center().distance_to(spawn_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = glass
	return nearest


## Where a tank's glass is, in global coordinates. A TileMapLayer knows which cells it
## has drawn; anything else is treated as a point.
func _front_rect(glass: CanvasItem) -> Rect2:
	var layer := glass as TileMapLayer
	if layer != null and layer.tile_set != null:
		var cells := layer.get_used_rect()
		if cells.size != Vector2i.ZERO:
			var cell := layer.tile_set.tile_size
			var transform := layer.get_global_transform()
			var corner_a: Vector2 = transform * Vector2(cells.position * cell)
			var corner_b: Vector2 = transform * Vector2(cells.end * cell)
			return Rect2(corner_a, Vector2.ZERO).expand(corner_b)
	return Rect2(glass.get_global_transform().origin, Vector2.ZERO)


## Put a Pokemon into the world at `spawn_pos` (a global position). Not in a tank, that
## is the ordinary thing: a child of the spawner, drawing at whatever absolute z its
## template chose in _template_ready(). In one, it goes in as the sibling immediately
## before that tank's glass, and its z is dropped to a relative 0 so the scene tree's
## order is what decides -- z BEATS tree order, so a bug at its usual z 25 would
## otherwise sail straight back over the glass. Returns the glass it went behind, or null.
##
## Position is set BEFORE add_child(), which every template relies on: _template_ready()
## reads where it is (a fish works out the water it may swim in, a patrol its route).
func _place_pokemon(pokemon: OverworldPokemon, point: Dictionary, spawn_pos: Vector2) -> CanvasItem:
	var front := _point_front(point, spawn_pos)
	if front == null:
		pokemon.position = to_local(spawn_pos)
		add_child(pokemon)
		return null
	var host: Node = front.get_parent()
	# CanvasItem, not Node2D: a tank's layers can sit under a Control (Fish_Shop's
	# FISHTANK and FISHTANK2 are Controls), and a Control has a transform too.
	var host_item := host as CanvasItem
	if host_item != null:
		pokemon.position = host_item.get_global_transform().affine_inverse() * spawn_pos
	else:
		pokemon.position = spawn_pos
	host.add_child(pokemon)
	host.move_child(pokemon, front.get_index())
	pokemon.z_as_relative = true
	pokemon.z_index = 0
	return front


func _clear_tank(id: String) -> void:
	for fish in _tanks.get(id, []):
		_remove_pokemon(fish)
	_tanks.erase(id)


func _on_pokemon_gone(pokemon: OverworldPokemon, id: String) -> void:
	if _live.get(id) == pokemon:
		_live.erase(id)
		# A burrower that just went down waits a full interval before the next roll.
		var point := OverworldPokemonData.find_point(doc, id)
		if not point.is_empty():
			_timers[id] = PREVIEW_RESPAWN_DELAY if preview \
					else _interval(OverworldPokemonData.time_table(point.get("tables"), GameState.get_time()))


# ============================================================
# FLYERS
# ============================================================

func _process_flyers(delta: float, time_name: String) -> void:
	var config := _flyer_config(time_name)
	if (config.get("table", []) as Array).is_empty():
		return
	# Guaranteed flock after too long a quiet spell. (Forced preview already sends one
	# every PREVIEW_FLYER_INTERVAL, so this is for real play and RANDOM preview.)
	_since_last_flock += delta
	if not preview and _since_last_flock >= _guarantee_seconds(time_name):
		_flyers = _flyers.filter(func(f): return is_instance_valid(f))
		if _flyers.size() < MAX_LIVE_FLYERS:
			spawn_flyer_group(config)
			return
	_flyer_timer -= delta
	if _flyer_timer > 0.0:
		return
	_flyer_timer = PREVIEW_FLYER_INTERVAL if preview else _interval(config)
	_flyers = _flyers.filter(func(f): return is_instance_valid(f))
	if _flyers.size() >= MAX_LIVE_FLYERS:
		return
	if not preview and not OverworldPokemonData.roll(float(config.get("chance", 0))):
		return
	spawn_flyer_group(config)


## Longest quiet spell before a guaranteed flock: longer at night.
func _guarantee_seconds(time_name: String) -> float:
	return FLYER_GUARANTEE_SECONDS_NIGHT if time_name == "Night" else FLYER_GUARANTEE_SECONDS


## The flyer table for this time of day ({} if there isn't one). In forced preview an
## empty one falls back to the first time of day that has flyers.
func _flyer_config(time_name: String) -> Dictionary:
	var config := OverworldPokemonData.time_table(doc.get("flyers"), time_name)
	if not preview or not (config.get("table", []) as Array).is_empty():
		return config
	for other in OverworldPokemonData.TIMES_OF_DAY:
		var fallback := OverworldPokemonData.time_table(doc.get("flyers"), str(other))
		if not (fallback.get("table", []) as Array).is_empty():
			return fallback
	return config


## Forced preview: the next species in table order, so a 1% bird is seen as often as a
## 70% one when checking how it looks.
func _next_preview_row(config: Dictionary) -> Dictionary:
	var rows: Array = config.get("table", [])
	if rows.is_empty():
		return {}
	_preview_flyer_index = (_preview_flyer_index + 1) % rows.size()
	var row = rows[_preview_flyer_index]
	return row if row is Dictionary else {}


func spawn_flyer_group(config: Dictionary) -> void:
	var row := _next_preview_row(config) if preview else OverworldPokemonData.pick_row(config.get("table", []))
	var species := str(row.get("species", ""))
	if species == "":
		return
	# A flock is on its way: the guaranteed-flock wait starts again from here.
	_since_last_flock = 0.0
	# Flock size belongs to the species row, so Wingull and Pidgey can differ.
	var low: int = maxi(1, int(row.get("min", OverworldPokemonData.DEFAULT_FLOCK_MIN)))
	var high: int = maxi(low, int(row.get("max", OverworldPokemonData.DEFAULT_FLOCK_MAX)))
	var count := randi_range(low, high)
	var view := _view_rect()
	var from_left := randf() < 0.5
	var direction := 1.0 if from_left else -1.0
	var start_x := view.position.x - FLYER_EDGE_MARGIN if from_left else view.end.x + FLYER_EDGE_MARGIN
	var top := view.position.y + FLYER_VERTICAL_PADDING
	var bottom := maxf(top, view.end.y - FLYER_VERTICAL_PADDING)
	var start := Vector2(start_x, _headon_clear_y(randf_range(top, bottom), direction, start_x, top, bottom))
	var end_x := _map_edge(direction)
	# One speed for the whole flock, so it crosses the map together.
	# Speed and scale belong to the species (the registry), the same on every table and map.
	var speed_range := OverworldPokemonData.species_speed_range(species)
	var slowest := maxf(1.0, float(speed_range.x))
	var fastest := maxf(slowest, float(speed_range.y))
	var flock_speed := randf_range(slowest, fastest)
	# Spin and erratic belong to the species too, like speed and scale.
	var info := OverworldPokemonData.species_info(species)
	var spins := bool(info.get("spin", false))
	var erratic := bool(info.get("erratic", false))
	var bug := bool(info.get("bug", false))
	var ghost := bool(info.get("ghost", false))
	var placed: Array[Vector2] = []
	for i in count:
		var flyer := PokemonFlyer.new()
		flyer.configure(species)
		flyer.direction = direction
		flyer.end_x = end_x
		flyer.speed = flock_speed
		flyer.spins = spins
		flyer.erratic = erratic
		flyer.bug = bug
		flyer.ghost = ghost
		flyer.size_scale = OverworldPokemonData.species_scale(species)
		flyer.can_cry = OverworldPokemonData.CRY_TEMPLATES.has("flyer")
		var offset := Vector2.ZERO if i == 0 else _flock_offset(direction, placed)
		placed.append(offset)
		flyer.position = to_local(start + offset)
		add_child(flyer)
		_flyers.append(flyer)


## Keeps a new flock clear of oncoming traffic. Only flyers going the other way that
## have yet to reach `start_x` can meet it head on; if one of those is flying within
## FLYER_HEADON_GAP of `y`, the flock starts FLYER_HEADON_SHIFT above or below instead
## -- whichever leaves the bigger gap, clamped to the screen -- so the two streams pass
## over and under each other rather than through.
func _headon_clear_y(y: float, direction: float, start_x: float, top: float, bottom: float) -> float:
	var oncoming := _oncoming_flyer_heights(direction, start_x)
	var best_gap := _nearest_height(y, oncoming)
	if best_gap >= FLYER_HEADON_GAP:
		return y
	var best := y
	for shift: float in [FLYER_HEADON_SHIFT, -FLYER_HEADON_SHIFT]:
		var candidate := clampf(y + shift, top, bottom)
		var gap := _nearest_height(candidate, oncoming)
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


## The heights of the live flyers travelling the other way that `start_x` is still
## behind. One already past the starting edge is on its way out and cannot collide.
func _oncoming_flyer_heights(direction: float, start_x: float) -> Array:
	var heights: Array = []
	for flyer in _flyers:
		if not is_instance_valid(flyer) or not (flyer is PokemonFlyer):
			continue
		if flyer.direction * direction >= 0.0:
			continue
		if (flyer.global_position.x - start_x) * direction <= 0.0:
			continue
		heights.append(flyer.global_position.y)
	return heights


## How close `y` comes to the nearest of `heights` (INF if there are none).
func _nearest_height(y: float, heights: Array) -> float:
	var nearest := INF
	for other in heights:
		nearest = minf(nearest, absf(y - float(other)))
	return nearest


## A spot for the next flock member: trailing behind the leader (further off screen,
## never ahead of it) and at least FLYER_MIN_SEPARATION from everyone already placed.
## If the box is too crowded, the try furthest from its nearest neighbour wins.
func _flock_offset(direction: float, placed: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_gap := -1.0
	for attempt in FLYER_PLACE_ATTEMPTS:
		var candidate := Vector2(-direction * randf_range(0.0, FLYER_GROUP_SPREAD.x),
				randf_range(-FLYER_GROUP_SPREAD.y, FLYER_GROUP_SPREAD.y) * 0.5)
		var gap := INF
		for other in placed:
			gap = minf(gap, candidate.distance_to(other))
		if gap >= FLYER_MIN_SEPARATION:
			return candidate
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


## The far end of the map in the direction of travel: the player camera's limit.
func _map_edge(direction: float) -> float:
	if _player != null and is_instance_valid(_player) and "camera" in _player:
		var camera: Camera2D = _player.camera
		if camera != null:
			return float(camera.limit_right) + FLYER_END_MARGIN if direction > 0.0 \
					else float(camera.limit_left) - FLYER_END_MARGIN
	var view := _view_rect()
	return view.end.x + 2000.0 if direction > 0.0 else view.position.x - 2000.0


func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)


# ============================================================
# PLACEMENT-TOOL MARKERS
# ============================================================

## Draw a marker for every spawn point in `working_doc`. Each marker holds a
## REFERENCE to its point dictionary, so moving the marker edits that document.
func show_markers(working_doc: Dictionary) -> Array:
	hide_markers()
	for point in working_doc.get("spawn_points", []):
		if not (point is Dictionary):
			continue
		var marker := PokemonSpawnMarker.new()
		marker.point = point
		var at = point.get("at", [0, 0])
		marker.position = to_local(Vector2(float(at[0]), float(at[1])))
		add_child(marker)
		_markers.append(marker)
	return _markers


func hide_markers() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			# remove_child before queue_free, or the placement tool's actor refresh
			# picks the corpse back up before the end of the frame.
			remove_child(marker)
			marker.queue_free()
	_markers.clear()


func get_markers() -> Array:
	return _markers.filter(func(m): return is_instance_valid(m))


func find_marker(id: String) -> PokemonSpawnMarker:
	for marker in get_markers():
		if str(marker.point.get("id", "")) == id:
			return marker
	return null
