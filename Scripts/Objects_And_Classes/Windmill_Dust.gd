extends Node2D

# ============================================================
# WINDMILL DUST -- soot and dirt shaken out of the old roof
# ============================================================
# Every few seconds a short row of single brown pixels falls from the ceiling, swaying
# side to side on the draught, and is gone when it reaches the floor. Added by Windmill.gd;
# all positions are in the map root's local space, snapped to whole world pixels.
# ============================================================

# TWEAKABLE -- how often a group falls, and how many pixels are in it.
const SPAWN_MIN := 5.0
const SPAWN_MAX := 10.0
const FIRST_SPAWN_MAX := 3.0   # the first one comes sooner, so the room is not still on arrival
const GROUP_MIN := 1
const GROUP_MAX := 5

# TWEAKABLE -- the shape of a group: each pixel sits this far behind the one before it,
# and this far left or right of the group's line.
const ROW_GAP_MIN := 2
const ROW_GAP_MAX := 5
const ROW_OFFSET_X := 2

# TWEAKABLE -- the fall, in world px (a world px is 2.5 on screen at the default zoom).
const FALL_SPEED_MIN := 22.0
const FALL_SPEED_MAX := 34.0
const SWAY_MIN := 1.0          # how far it drifts each way as it falls
const SWAY_MAX := 2.0
const SWAY_RATE_MIN := 0.7     # radians per second: slow, it is drifting rather than shaking
const SWAY_RATE_MAX := 1.4
const FADE_PX := 10.0          # fades over this distance just above the floor

# TWEAKABLE -- where it falls: the ceiling line, the room's width between its walls, and
# how far down the floor a group may land.
const CEILING_Y := -192.0
const ROOM_LEFT := 88.0
const ROOM_RIGHT := 584.0
const LAND_Y_MIN := 16.0
const LAND_Y_MAX := 372.0

const COLOURS: Array[Color] = [
	Color(0.40, 0.28, 0.16),
	Color(0.50, 0.35, 0.20),
	Color(0.33, 0.23, 0.14),
]

var _grains: Array[Dictionary] = []
var _until_spawn: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	z_index = 10   # falls in front of the player, not behind
	_until_spawn = randf_range(0.5, FIRST_SPAWN_MAX)


func _process(delta: float) -> void:
	# Frozen with the rest of the overworld while the menu is open.
	if MapManager.overworld_paused:
		return
	_time += delta
	_until_spawn -= delta
	if _until_spawn <= 0.0:
		_until_spawn = randf_range(SPAWN_MIN, SPAWN_MAX)
		_spawn_group()
	if _grains.is_empty():
		return
	for grain in _grains:
		grain["y"] += float(grain["speed"]) * delta
	_grains = _grains.filter(func(grain: Dictionary) -> bool: return grain["y"] < grain["land_y"])
	queue_redraw()


func _spawn_group() -> void:
	var line_x: float = randf_range(ROOM_LEFT, ROOM_RIGHT)
	var speed: float = randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX)
	var land_y: float = randf_range(LAND_Y_MIN, LAND_Y_MAX)
	var sway: float = randf_range(SWAY_MIN, SWAY_MAX)
	var sway_rate: float = randf_range(SWAY_RATE_MIN, SWAY_RATE_MAX)
	var phase: float = randf() * TAU
	var y: float = CEILING_Y
	for i in randi_range(GROUP_MIN, GROUP_MAX):
		_grains.append({
			"x": line_x + randi_range(-ROW_OFFSET_X, ROW_OFFSET_X),
			"y": y,
			"speed": speed,
			"land_y": land_y,
			"sway": sway,
			"sway_rate": sway_rate,
			"phase": phase,
			"colour": COLOURS.pick_random(),
		})
		y -= randi_range(ROW_GAP_MIN, ROW_GAP_MAX)


func _draw() -> void:
	for grain in _grains:
		var x: float = float(grain["x"]) \
				+ sin(_time * float(grain["sway_rate"]) + float(grain["phase"])) * float(grain["sway"])
		var colour: Color = grain["colour"]
		colour.a = clampf((float(grain["land_y"]) - float(grain["y"])) / FADE_PX, 0.0, 1.0)
		draw_rect(Rect2(Vector2(roundf(x), roundf(float(grain["y"]))), Vector2.ONE), colour)
