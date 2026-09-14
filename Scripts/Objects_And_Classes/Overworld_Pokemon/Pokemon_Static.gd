class_name PokemonStatic
extends OverworldPokemon

## STATIC template -- a Pokémon that stands its ground with collision, either on the
## spot or walking one of the NPC patterns. The spawn point's `pattern` picks which:
##   idle_cycle     plays its walk cycle facing down, on the spot (like swimmers)
##   idle_random    stands still, looks a random way every few seconds
##   idle_down      stands still facing down
##   patrol_line    walks `distance` back and forth on `axis` at `speed`
##   patrol_square  walks a `distance`-sided square at `speed`
## Space makes it say its name.

# ---- tweakables -------------------------------------------------------------
const Z := 1
const DEFAULT_SPEED := 40.0
const DEFAULT_DISTANCE := 48.0
const LOOK_MIN := 1.0
const LOOK_MAX := 4.0
## Patrols stop while the player stands this close.
const PLAYER_BLOCK_DISTANCE := 30.0
const COLLISION_SIZE := Vector2(14, 10)
const COLLISION_OFFSET := Vector2(0, 5)
# -----------------------------------------------------------------------------

const SQUARE_ORDER := ["down", "right", "up", "left"]

var pattern: String = "idle_cycle"
var _speed: float = DEFAULT_SPEED
var _distance: float = DEFAULT_DISTANCE
var _axis: String = "horizontal"
var _dir: Vector2 = Vector2.RIGHT
var _walked: float = 0.0
var _step: int = 0
var _look_timer: float = 0.0
var _talking: bool = false


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = COLLISION_SIZE
	shape.shape = rect
	shape.position = COLLISION_OFFSET
	add_child(shape)
	add_to_group("pokemon")

	pattern = str(spawn_point.get("pattern", "idle_cycle"))
	_speed = float(spawn_point.get("speed", DEFAULT_SPEED))
	_distance = float(spawn_point.get("distance", DEFAULT_DISTANCE))
	_axis = str(spawn_point.get("axis", "horizontal"))
	_reset_pattern()


func is_interactable() -> bool:
	return not _is_gone


func _reset_pattern() -> void:
	match pattern:
		"idle_cycle":
			animating = true
			set_facing("down")
		"idle_random":
			animating = false
			_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
		"patrol_line":
			animating = true
			_dir = Vector2.RIGHT if _axis == "horizontal" else Vector2.DOWN
			face_vector(_dir)
		"patrol_square":
			animating = true
			_dir = DIR_VECTORS[SQUARE_ORDER[_step]]
			face_vector(_dir)
		_:
			animating = false
			set_facing("down")
	_apply_region()


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null or _talking:
		return
	match pattern:
		"idle_random":
			_look_timer -= delta
			if _look_timer <= 0.0:
				_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
				set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])
		"patrol_line", "patrol_square":
			var player := player_node()
			if player != null and global_position.distance_to(player.global_position) < PLAYER_BLOCK_DISTANCE:
				if animating:
					animating = false
					_apply_region()
				return
			if not animating:
				animating = true
				_apply_region()
			velocity = _dir * _speed
			move_and_slide()
			_walked += _speed * delta
			if _walked >= _distance:
				_walked = 0.0
				if pattern == "patrol_line":
					_dir = -_dir
				else:
					_step = (_step + 1) % SQUARE_ORDER.size()
					_dir = DIR_VECTORS[SQUARE_ORDER[_step]]
				face_vector(_dir)


func pause_and_face(target_global: Vector2) -> void:
	_talking = true
	velocity = Vector2.ZERO
	animating = false
	face_vector(target_global - global_position)
	_apply_region()


func resume_movement() -> void:
	_talking = false
	if pattern == "patrol_line" or pattern == "patrol_square":
		face_vector(_dir)
		animating = true
		_apply_region()
	elif pattern != "idle_random":
		_reset_pattern()
