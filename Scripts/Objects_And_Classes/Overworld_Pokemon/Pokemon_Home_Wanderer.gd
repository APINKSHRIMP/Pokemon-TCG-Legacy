class_name PokemonHomeWanderer
extends OverworldPokemon

## HOME template (2026-11-24) -- a Pokémon living in your house, not following you.
## It potters about near where it was put: walk a short way, stand a while, walk again,
## bumping off walls and furniture (it collides like a route walker). Space to talk:
## MapManager offers to take it out with you (PokemonHome has the rules).
## Spawned by PokemonHome.spawn_wanderers() from MapManager.initialise() in the house.

const GROUP := "home_pokemon"

# ---- tweakables -------------------------------------------------------------
const Z := 1
## How far from its home spot it wanders (world px).
const WANDER_RADIUS := 40.0
const WANDER_SPEED := 28.0
## Seconds it stands between walks (random in this range).
const PAUSE_MIN := 1.5
const PAUSE_MAX := 4.5
## A walk longer than this many seconds gives up (stuck on furniture).
const MAX_WALK_TIME := 3.0
const COLLISION_SIZE := Vector2(12, 8)
const COLLISION_OFFSET := Vector2(0, 5)
# -----------------------------------------------------------------------------

var home: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _walking: bool = false
var _timer: float = 0.0
var _talking: bool = false


static func spawn(map_root: Node, species_key: String, at: Vector2) -> PokemonHomeWanderer:
	var w := PokemonHomeWanderer.new()
	w.configure(species_key)
	w.position = at - (map_root as Node2D).global_position if map_root is Node2D else at
	map_root.add_child(w)
	return w


func _template_ready() -> void:
	add_to_group(GROUP)
	add_to_group("pokemon")
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
	home = global_position
	animating = true   # the idle cycle runs standing too, like every follower
	_timer = randf_range(0.3, PAUSE_MAX)


func is_interactable() -> bool:
	return not _is_gone


func cry_text() -> String:
	return "%s is happy to be at home!" % display_name


func pause_and_face(target_global: Vector2) -> void:
	_talking = true
	_walking = false
	velocity = Vector2.ZERO
	face_vector(target_global - global_position)


func resume_movement() -> void:
	_talking = false
	_timer = randf_range(PAUSE_MIN, PAUSE_MAX)


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null or _talking:
		return
	_timer -= delta
	if not _walking:
		if _timer <= 0.0:
			var angle := randf() * TAU
			_target = home + Vector2.from_angle(angle) * randf_range(WANDER_RADIUS * 0.3, WANDER_RADIUS)
			_walking = true
			_timer = MAX_WALK_TIME
		return
	var to := _target - global_position
	if to.length() < 2.0 or _timer <= 0.0:
		_walking = false
		_timer = randf_range(PAUSE_MIN, PAUSE_MAX)
		return
	velocity = to.normalized() * WANDER_SPEED
	face_vector(velocity)
	move_and_slide()
