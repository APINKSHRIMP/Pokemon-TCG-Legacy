class_name OverworldPokemonSpawner
extends Node2D

## One per loaded map (BaseMapScene attaches it). Reads that map's
## Pokemon/Spawns/<Map>.json and puts Pokémon into the world:
##
##   bug_tree, swinging_bug, rodent, static   rolled ONCE, when the map loads
##   burying, surfacing                       rolled every `interval` seconds while
##                                            nothing from that point is out
##   flyers                                   map-wide: every `interval` seconds,
##                                            `chance`% to send 1-4 of one species
##                                            across the screen
##
## A roll first checks the point's `chance`, then picks the species from its table.
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
		"rodent":       return PokemonRodent.new()
		"burying":      return PokemonBurrower.new()
		"surfacing":    return PokemonSurfacer.new()
		"static":       return PokemonStatic.new()
	return null

# ---- tweakables -------------------------------------------------------------
## Flyers already in the air past which a tick spawns nothing.
const MAX_LIVE_FLYERS := 12
## How far outside the camera's edge a flock starts.
const FLYER_EDGE_MARGIN := 32.0
## A flock is scattered inside this box, trailing behind its leader.
const FLYER_GROUP_SPREAD := Vector2(48, 36)
## Keeps flocks from spawning right against the top/bottom of the screen.
const FLYER_VERTICAL_PADDING := 24.0
## How far past the camera limit a flyer carries on before it despawns.
const FLYER_END_MARGIN := 64.0
## Seconds before a burying/surfacing point first rolls: random within 1..interval,
## so every point on the map does not pop on the same frame.
const FIRST_ROLL_MIN := 1.0
# -----------------------------------------------------------------------------

var map_data: String = ""
var doc: Dictionary = {}

var _player: Node2D = null
## point id -> the Pokémon it currently has out
var _live: Dictionary = {}
## point id -> seconds until the next roll
var _timers: Dictionary = {}
var _flyer_timer: float = 0.0
var _flyers: Array = []
var _markers: Array = []


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
		if OverworldPokemonData.ONE_SHOT_TEMPLATES.has(template):
			if OverworldPokemonData.time_allowed(str(point.get("times", "")), time_name) \
					and OverworldPokemonData.roll(float(point.get("chance", 0))):
				_spawn_at(point)
		elif OverworldPokemonData.TIMED_TEMPLATES.has(template):
			_timers[str(point.get("id", ""))] = randf_range(FIRST_ROLL_MIN, maxf(FIRST_ROLL_MIN, _interval(point)))
	_flyer_timer = _interval(doc.get("flyers", {}))


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
		_timers[id] = float(_timers.get(id, _interval(point))) - delta
		if _timers[id] > 0.0:
			continue
		_timers[id] = _interval(point)
		if OverworldPokemonData.time_allowed(str(point.get("times", "")), time_name) \
				and OverworldPokemonData.roll(float(point.get("chance", 0))):
			_spawn_at(point)
	_process_flyers(delta, time_name)


func _interval(config: Dictionary) -> float:
	return maxf(0.5, float(config.get("interval", 10)))


# ============================================================
# SPAWN POINTS
# ============================================================

func _spawn_at(point: Dictionary) -> OverworldPokemon:
	var species := OverworldPokemonData.pick_species(point.get("table", []))
	if species == "":
		return null
	var pokemon := make_pokemon(str(point.get("template", "")))
	if pokemon == null:
		return null
	pokemon.configure(species, point)
	var at = point.get("at", [0, 0])
	# Position before add_child(): the templates read their home in _ready().
	pokemon.position = to_local(Vector2(float(at[0]), float(at[1])))
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
			_timers[id] = _interval(point)


# ============================================================
# FLYERS
# ============================================================

func _process_flyers(delta: float, time_name: String) -> void:
	var config = doc.get("flyers", {})
	if not (config is Dictionary) or (config.get("table", []) as Array).is_empty():
		return
	_flyer_timer -= delta
	if _flyer_timer > 0.0:
		return
	_flyer_timer = _interval(config)
	_flyers = _flyers.filter(func(f): return is_instance_valid(f))
	if _flyers.size() >= MAX_LIVE_FLYERS:
		return
	if not OverworldPokemonData.time_allowed(str(config.get("times", "")), time_name):
		return
	if not OverworldPokemonData.roll(float(config.get("chance", 0))):
		return
	spawn_flyer_group(config)


func spawn_flyer_group(config: Dictionary) -> void:
	var species := OverworldPokemonData.pick_species(config.get("table", []))
	if species == "":
		return
	var low: int = maxi(1, int(config.get("min", 1)))
	var high: int = maxi(low, int(config.get("max", low)))
	var count := randi_range(low, high)
	var view := _view_rect()
	var from_left := randf() < 0.5
	var direction := 1.0 if from_left else -1.0
	var start_x := view.position.x - FLYER_EDGE_MARGIN if from_left else view.end.x + FLYER_EDGE_MARGIN
	var top := view.position.y + FLYER_VERTICAL_PADDING
	var bottom := maxf(top, view.end.y - FLYER_VERTICAL_PADDING)
	var start := Vector2(start_x, randf_range(top, bottom))
	var end_x := _map_edge(direction)
	for i in count:
		var flyer := PokemonFlyer.new()
		flyer.configure(species)
		flyer.direction = direction
		flyer.end_x = end_x
		# Trail behind the leader (further off screen), never ahead of it.
		var offset := Vector2(-direction * randf_range(0.0, FLYER_GROUP_SPREAD.x),
				randf_range(-FLYER_GROUP_SPREAD.y, FLYER_GROUP_SPREAD.y) * 0.5)
		flyer.position = to_local(start + offset)
		add_child(flyer)
		_flyers.append(flyer)


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
