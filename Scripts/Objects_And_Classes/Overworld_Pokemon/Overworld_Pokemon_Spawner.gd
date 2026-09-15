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
## How far past the camera limit a flyer carries on before it despawns.
const FLYER_END_MARGIN := 64.0
## Guaranteed flocks: if this many seconds pass with no flock spawning at all, one is
## sent regardless of the table's chance (still capped by MAX_LIVE_FLYERS, and only if
## the current time of day has flyers). Any flock -- rolled or guaranteed -- restarts
## the wait, so lucky rolls can still add extras in between.
const FLYER_GUARANTEE_SECONDS := 20.0
const FLYER_GUARANTEE_SECONDS_NIGHT := 30.0
## Seconds before a burying/surfacing point first rolls: random within 1..interval,
## so every point on the map does not pop on the same frame.
const FIRST_ROLL_MIN := 1.0
## Placement-tool preview: seconds before a burying / surfacing Pokémon comes back up
## after going down.
const PREVIEW_RESPAWN_DELAY := 0.5
## Forced preview: seconds between flocks (ignoring chance and interval), still capped
## by MAX_LIVE_FLYERS. Species take turns in table order rather than by rate.
const PREVIEW_FLYER_INTERVAL := 1.5
# -----------------------------------------------------------------------------

var map_data: String = ""
var doc: Dictionary = {}

var _player: Node2D = null
## point id -> the Pokémon it currently has out
var _live: Dictionary = {}
## point id -> seconds until the next roll
var _timers: Dictionary = {}
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
	for point in doc.get("spawn_points", []):
		if not (point is Dictionary):
			continue
		var template := str(point.get("template", ""))
		if not OverworldPokemonData.TEMPLATES.has(template):
			push_warning("OverworldPokemonSpawner: unknown template '%s' on %s" % [template, point.get("id", "?")])
			continue
		var config := _config_for(point, time_name)
		if OverworldPokemonData.ONE_SHOT_TEMPLATES.has(template):
			if preview or OverworldPokemonData.roll(float(config.get("chance", 0))):
				_spawn_at(point, config)
		elif OverworldPokemonData.TIMED_TEMPLATES.has(template):
			if preview:
				_spawn_at(point, config)
			else:
				_timers[str(point.get("id", ""))] = randf_range(FIRST_ROLL_MIN, maxf(FIRST_ROLL_MIN, _interval(config)))
	# Forced preview sends the first flock almost at once rather than after a full interval.
	_flyer_timer = 0.2 if preview else _interval(_flyer_config(time_name))
	_since_last_flock = 0.0


func clear_pokemon() -> void:
	for child in get_children():
		if child is OverworldPokemon:
			child.despawn()
	_live.clear()
	_flyers.clear()


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
	var existing = _live.get(id)
	_live.erase(id)
	if existing != null and is_instance_valid(existing):
		existing.despawn()
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
	var pokemon := make_pokemon(str(point.get("template", "")))
	if pokemon == null:
		return null
	pokemon.configure(species, point)
	pokemon.size_scale = OverworldPokemonData.species_scale(species)
	pokemon.can_cry = OverworldPokemonData.CRY_TEMPLATES.has(str(point.get("template", "")))
	var at = point.get("at", [0, 0])
	var spawn_pos := Vector2(float(at[0]), float(at[1]))
	# A point with a water area (surfacing) comes up anywhere inside it.
	var region := OverworldPokemonData.point_region(point)
	if region.has_area():
		spawn_pos = Vector2(randf_range(region.position.x, region.end.x),
				randf_range(region.position.y, region.end.y)).round()
	# Position before add_child(): the templates read their home in _ready().
	pokemon.position = to_local(spawn_pos)
	var id := str(point.get("id", ""))
	pokemon.gone.connect(_on_pokemon_gone.bind(id))
	add_child(pokemon)
	_live[id] = pokemon
	return pokemon


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
	var start := Vector2(start_x, randf_range(top, bottom))
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
