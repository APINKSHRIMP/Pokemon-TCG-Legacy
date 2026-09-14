class_name PokemonTreeBug
extends OverworldPokemon

## BUG IN TREE template -- Caterpie, Weedle, Combee... Sits at its spawn point in a
## tree canopy, glancing in random directions, and every few seconds shuffles a
## pixel or three before settling again. No collision.

# ---- tweakables -------------------------------------------------------------
## Above tree canopy tiles (z 10-20 on the maps).
const Z := 25
## Seconds between glances in a new random direction.
const LOOK_MIN := 1.0
const LOOK_MAX := 3.5
## Seconds between shuffles.
const SHUFFLE_MIN := 3.0
const SHUFFLE_MAX := 7.0
## How far one shuffle goes, in world pixels.
const SHUFFLE_PIXELS_MIN := 1.0
const SHUFFLE_PIXELS_MAX := 3.0
const SHUFFLE_SPEED := 6.0
## Never strays further than this from the spawn point.
const HOME_RADIUS := 6.0
# -----------------------------------------------------------------------------

var _home: Vector2
var _look_timer: float = 0.0
var _shuffle_timer: float = 0.0
var _target: Vector2
var _moving: bool = false


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	animating = false
	_home = global_position
	_target = _home
	set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])
	_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
	_shuffle_timer = randf_range(SHUFFLE_MIN, SHUFFLE_MAX)


func _template_process(delta: float) -> void:
	if _moving:
		global_position = global_position.move_toward(_target, SHUFFLE_SPEED * delta)
		if global_position.distance_to(_target) < 0.05:
			global_position = _target
			_moving = false
			animating = false
			_apply_region()
		return

	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
		set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])

	_shuffle_timer -= delta
	if _shuffle_timer <= 0.0:
		_shuffle_timer = randf_range(SHUFFLE_MIN, SHUFFLE_MAX)
		var dir: String = DIRECTIONS[randi() % DIRECTIONS.size()]
		var candidate: Vector2 = global_position \
				+ DIR_VECTORS[dir] * randf_range(SHUFFLE_PIXELS_MIN, SHUFFLE_PIXELS_MAX)
		if candidate.distance_to(_home) > HOME_RADIUS:
			candidate = global_position.move_toward(_home, SHUFFLE_PIXELS_MAX)
		_target = candidate
		_moving = true
		animating = true
		face_vector(_target - global_position)
		_apply_region()
