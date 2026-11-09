extends Node

## ============================================================
## THE HARBOUR'S SEA -- two looped beds that follow the player
## ============================================================
## OceanFar is waves off in the distance, OceanClose is waves on the beach. Both play all the
## time on the Music bus (so the music slider covers them); only their levels move, and the
## levels come from how far the player is from the nearest VISIBLE water tile:
##
##   FAR_PX and beyond       OceanFar at its quiet level, no OceanClose
##   FAR_PX -> HANDOVER_PX   OceanFar climbs to its peak
##   HANDOVER_PX -> NEAR_PX  OceanClose takes over: it climbs to its max as OceanFar falls back
##
## While a cast is running the fishing minigame raises OceanClose to full, through the same
## set_ambience() / clear_ambience() calls FishingZone answers on every other map.
##
## "Visible" because the Sea layer is painted on under the shoreline: a cell with a land layer
## over it is not water anyone can see, and counting it would put the beach sound several tiles
## inland.
## ============================================================

const NODE_NAME := "OceanAmbience"
## BaseMapScene and MapManager fade this out with call_group() on the way off the map.
const GROUP := "map_ambience"

## Layers under TILE_MAPS/TERRAIN that hide the Sea layer where they overlap it.
const SEA_LAYER := "TILE_MAPS/TERRAIN/Sea"
const LAND_LAYERS := [
	"TILE_MAPS/TERRAIN/Background", "TILE_MAPS/TERRAIN/Background2",
	"TILE_MAPS/TERRAIN/Background3", "TILE_MAPS/TERRAIN/Grass", "TILE_MAPS/TERRAIN/Hill",
]

## TWEAKABLE: distances from the water, in world pixels (tiles are 16; the default camera shows
## about 24 tiles either side of the player).
const NEAR_PX := 32.0        ## "right next to the water": OceanClose at its max
const HANDOVER_PX := 160.0   ## OceanFar peaks here, and OceanClose starts to come in
const FAR_PX := 640.0        ## further than this is "nowhere near the water"

## TWEAKABLE: the levels, 0.0 - 1.0. far_quiet is both ends of OceanFar's curve.
const LEVELS_DAY := {"far_quiet": 0.10, "far_peak": 0.40, "close_max": 0.50}
const LEVELS_BEDTIME := {"far_quiet": 0.20, "far_peak": 0.80, "close_max": 0.90}

## TWEAKABLE: how fast a level may move, in level per second. Walking changes the target
## gradually anyway; this smooths arriving on the map and the start and end of a cast.
const LEVEL_RATE := 0.6
const PAUSE_FADE := 0.4    ## under the main menu
const SILENT_DB := -60.0
## Seconds between distance checks: the coast is ~2,000 cells, no need to walk it every frame.
const CHECK_EVERY := 0.1

var _player: Node2D = null
var _coast: PackedVector2Array = PackedVector2Array()
var _close: AudioStreamPlayer = null
var _far: AudioStreamPlayer = null
var _close_level: float = 0.0
var _far_level: float = 0.0
var _close_target: float = 0.0
var _far_target: float = 0.0
var _check_timer: float = 0.0
## >= 0 while the fishing minigame is driving OceanClose; -1 follows the player.
var _fishing_level: float = -1.0
var _fishing_rate: float = LEVEL_RATE
var _paused: bool = false
## Leaving the map: stays down until the node goes with the scene.
var _silenced: bool = false
var _silence_rate: float = 1.0


## Adds the sea to `map`. Does nothing if the map has no Sea layer.
static func attach(map: Node, player: Node2D) -> void:
	if map.get_node_or_null(NODE_NAME) != null or map.get_node_or_null(SEA_LAYER) == null:
		return
	var ambience := (load("res://Scripts/Objects_And_Classes/Ocean_Ambience.gd") as GDScript).new() as Node
	ambience.name = NODE_NAME
	ambience.set("_player", player)
	map.add_child(ambience)


func _ready() -> void:
	add_to_group(GROUP)
	_build_coast()
	_close = _make_player(SoundManagerScript.BGM_OCEAN_CLOSE)
	_far = _make_player(SoundManagerScript.BGM_OCEAN_FAR)


func _make_player(path: String) -> AudioStreamPlayer:
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	if "loop" in stream:
		stream.loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SoundManagerScript.MUSIC_BUS
	player.volume_db = SILENT_DB
	add_child(player)
	player.play()
	return player


## The world position of every visible water cell that touches something that is not water.
func _build_coast() -> void:
	var map := get_parent()
	var sea := map.get_node(SEA_LAYER) as TileMapLayer
	var land := {}
	for path: String in LAND_LAYERS:
		var layer := map.get_node_or_null(path) as TileMapLayer
		if layer == null:
			continue
		for cell in layer.get_used_cells():
			land[cell] = true
	var water := {}
	for cell in sea.get_used_cells():
		if not land.has(cell):
			water[cell] = true
	for cell: Vector2i in water:
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not water.has(cell + step):
				_coast.append(sea.to_global(sea.map_to_local(cell)))
				break


func _distance_to_water() -> float:
	var from := _player.global_position
	var best := INF
	for point: Vector2 in _coast:
		var d := from.distance_squared_to(point)
		if d < best:
			best = d
	return sqrt(best)


func _update_targets() -> void:
	if _player == null or not is_instance_valid(_player) or _coast.is_empty():
		_far_target = 0.0
		_close_target = 0.0
		return
	var distance := _distance_to_water()
	var levels: Dictionary = LEVELS_BEDTIME if GameState.get_time() == "Bedtime" else LEVELS_DAY
	var quiet: float = levels["far_quiet"]
	var peak: float = levels["far_peak"]
	if distance >= HANDOVER_PX:
		# 0 at FAR_PX, 1 at the handover.
		var towards := smoothstep(FAR_PX, HANDOVER_PX, distance)
		_far_target = lerpf(quiet, peak, towards)
		_close_target = 0.0
	else:
		# 0 at the handover, 1 right next to the water.
		var towards := smoothstep(HANDOVER_PX, NEAR_PX, distance)
		_far_target = lerpf(peak, quiet, towards)
		_close_target = lerpf(0.0, float(levels["close_max"]), towards)


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_EVERY
		_update_targets()

	var far_goal := _far_target
	var close_goal := _close_target
	var far_rate := LEVEL_RATE
	var close_rate := LEVEL_RATE
	if _fishing_level >= 0.0:
		close_goal = _fishing_level
		close_rate = _fishing_rate
	if _paused:
		far_goal = 0.0
		close_goal = 0.0
		far_rate = 1.0 / PAUSE_FADE
		close_rate = far_rate
	if _silenced:
		far_goal = 0.0
		close_goal = 0.0
		far_rate = _silence_rate
		close_rate = _silence_rate

	_far_level = move_toward(_far_level, far_goal, far_rate * delta)
	_close_level = move_toward(_close_level, close_goal, close_rate * delta)
	_apply(_far, _far_level)
	_apply(_close, _close_level)


func _apply(player: AudioStreamPlayer, level: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.volume_db = SILENT_DB if level <= 0.001 else linear_to_db(level)


## The fishing minigame takes OceanClose to `level` over `seconds` (FishingZone forwards this).
func set_ambience(level: float, seconds: float) -> void:
	_fishing_level = clampf(level, 0.0, 1.0)
	_fishing_rate = 1.0 / maxf(0.01, seconds)


## Back to wherever the player is standing.
func clear_ambience() -> void:
	_fishing_level = -1.0


## Called through FishingZone by MapManager.set_overworld_paused(): fades under the main menu.
func set_ambience_paused(paused: bool) -> void:
	_paused = paused


## Off the map (a door, a match): down over `seconds` and it stays down.
func silence(seconds: float) -> void:
	_silenced = true
	_silence_rate = 1.0 / maxf(0.01, seconds)
