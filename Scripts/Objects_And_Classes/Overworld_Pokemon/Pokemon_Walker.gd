extends OverworldPokemon

## WALKER template -- a Pokémon that walks a drawn route, with pauses and idle patterns
## at its points, exactly like an NPC on a route (the walking is the same RouteRunner).
## The spawn point's `route` holds it:
##   "route": {"speed": 40, "mode": "loop" | "pingpong" | "random",
##             "steps": [{"to": [dx, dy]}, {"wait": 2, "idle": "idle_left"}, ...]}
## Offsets are from the spawn point's `at`. Draw it in-game: F tool, select the spawn
## point, E. Collision, stops while the player stands in its way, Space to talk.

const RouteRunner := preload("res://Scripts/Objects_And_Classes/Route_Runner.gd")

# ---- tweakables -------------------------------------------------------------
const Z := 1
## Route speed when the spawn point does not say (world px/s).
const DEFAULT_SPEED := 40.0
## It stands and waits while the player is this close.
const PLAYER_BLOCK_DISTANCE := 30.0
const COLLISION_SIZE := Vector2(14, 10)
const COLLISION_OFFSET := Vector2(0, 5)
# -----------------------------------------------------------------------------

var route = RouteRunner.new()
var speed: float = DEFAULT_SPEED
var _talking: bool = false


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = COLLISION_SIZE * size_scale
	shape.shape = rect
	shape.position = COLLISION_OFFSET * size_scale
	add_child(shape)
	add_to_group("pokemon")
	var data: Dictionary = spawn_point.get("route", {}) if spawn_point.get("route") is Dictionary else {}
	speed = float(data.get("speed", DEFAULT_SPEED))
	route.setup(data.get("steps", []) if data.get("steps") is Array else [], str(data.get("mode", "loop")), position)
	_show_frame()


func is_interactable() -> bool:
	return not _is_gone


## The node it is walking to or pausing at, for the placement tool's route overlay.
func route_current_node() -> int:
	return route.i


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null or _talking:
		return
	var player := player_node()
	var blocked := player != null and global_position.distance_to(player.global_position) < PLAYER_BLOCK_DISTANCE
	velocity = route.tick(delta, position, blocked, speed)
	if route.snap_to is Vector2:
		position = route.snap_to
	_show_frame()
	if velocity == Vector2.ZERO:
		return
	move_and_slide()
	var target: int = route.i
	if route.check_stuck(delta, get_real_velocity().length(), speed):
		push_warning("%s (walker %s): route point %d is blocked -- skipped it. Redraw that leg."
				% [display_name, str(spawn_point.get("id", "?")), target])


func _show_frame() -> void:
	set_facing(route.facing)
	if animating != route.walk_anim:
		animating = route.walk_anim
		_apply_region()


func pause_and_face(target_global: Vector2) -> void:
	_talking = true
	velocity = Vector2.ZERO
	animating = false
	face_vector(target_global - global_position)
	_apply_region()


func resume_movement() -> void:
	_talking = false
	var face: String = route.pause_facing()
	if face != "":
		route.facing = face
	_show_frame()
