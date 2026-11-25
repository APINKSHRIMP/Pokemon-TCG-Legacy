class_name PokemonHomeWanderer
extends OverworldPokemon

## HOME template (2026-11-24) -- a Pokémon living in your house, not following you.
## It potters about near where it was put: walk a short way, stand a while, walk again,
## bumping off walls and furniture (it collides like a route walker). Space to talk:
## MapManager offers to take it out with you (PokemonHome has the rules).
## RESTING (spawn_resting): it stays put on its bed in the bedroom instead -- asleep at night
## (still, with a floating "z"), or swimming in a water tank by day.
## Spawned by PokemonHome.refresh_house() from MapManager.initialise() in the house.

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
## Resting on a bed: drawn above the bed (PokemonBedSpot.Z) and below the player.
const RESTING_Z := 1
## The sleeping "z": seconds per float, how far it rises (world px), its size.
const SLEEP_Z_PERIOD := 1.8
const SLEEP_Z_RISE := 10.0
const SLEEP_Z_FONT_SIZE := 9
# -----------------------------------------------------------------------------

var home: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _walking: bool = false
var _timer: float = 0.0
var _talking: bool = false
## On a bed: never moves. `seat` = where its feet go (global).
var resting: bool = false
var asleep: bool = false
var seat: Vector2 = Vector2.ZERO
var _sleep_z: Label = null


static func spawn(map_root: Node, species_key: String, at: Vector2) -> PokemonHomeWanderer:
	var w := PokemonHomeWanderer.new()
	w.configure(PokemonHome.species_of(species_key))   # species_key is its ID ("..#2")
	w.pokemon_id = species_key
	w.display_name = PokemonHome.name_of(species_key)   # its nickname, if it has one
	w.shiny = PokemonHome.is_shiny(species_key)
	w.position = at - (map_root as Node2D).global_position if map_root is Node2D else at
	map_root.add_child(w)
	return w


## On a bed (or in a tank): feet on `seat_global`, asleep or not.
static func spawn_resting(map_root: Node, species_key: String, seat_global: Vector2, is_asleep: bool) -> PokemonHomeWanderer:
	var w := PokemonHomeWanderer.new()
	w.configure(PokemonHome.species_of(species_key))   # species_key is its ID ("..#2")
	w.pokemon_id = species_key
	w.display_name = PokemonHome.name_of(species_key)   # its nickname, if it has one
	w.shiny = PokemonHome.is_shiny(species_key)
	w.resting = true
	w.asleep = is_asleep
	w.seat = seat_global
	w.position = seat_global - (map_root as Node2D).global_position if map_root is Node2D else seat_global
	map_root.add_child(w)
	return w


## Where the node goes so the art's lowest row sits on `feet_global`.
func node_pos_for_feet(feet_global: Vector2) -> Vector2:
	return feet_global - Vector2(0, (art_bottom + 1 - cell.y * 0.5) * draw_scale())


## Lie down where it is now: still, facing down, with the floating z.
func fall_asleep() -> void:
	asleep = true
	resting = true
	_walking = false
	velocity = Vector2.ZERO
	animating = false
	set_facing("down")
	_frame = 0
	_apply_region()
	if _sleep_z == null:
		_start_sleep_z()


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
	if resting:
		z_index = RESTING_Z
		global_position = node_pos_for_feet(seat)
		home = global_position
		set_facing("down")
		if asleep:
			fall_asleep()


func _start_sleep_z() -> void:
	_sleep_z = Label.new()
	_sleep_z.text = "z"
	_sleep_z.add_theme_font_size_override("font_size", SLEEP_Z_FONT_SIZE)
	_sleep_z.add_theme_color_override("font_color", Color(1, 1, 1))
	_sleep_z.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	_sleep_z.add_theme_constant_override("outline_size", 3)
	_sleep_z.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_z.z_index = 5
	add_child(_sleep_z)
	var top := (art_top - cell.y * 0.5) * draw_scale()
	var start := Vector2(4, top - 10)
	var tween := _sleep_z.create_tween().set_loops()
	tween.tween_callback(func():
		_sleep_z.position = start
		_sleep_z.modulate.a = 0.0)
	tween.tween_property(_sleep_z, "modulate:a", 1.0, SLEEP_Z_PERIOD * 0.3)
	tween.parallel().tween_property(_sleep_z, "position", start + Vector2(4, -SLEEP_Z_RISE), SLEEP_Z_PERIOD)
	tween.tween_property(_sleep_z, "modulate:a", 0.0, SLEEP_Z_PERIOD * 0.3)


func is_interactable() -> bool:
	return not _is_gone


func cry_text() -> String:
	if asleep:
		return "%s is fast asleep." % display_name
	return "%s is happy to be at home!" % display_name


func pause_and_face(target_global: Vector2) -> void:
	_talking = true
	_walking = false
	velocity = Vector2.ZERO
	if not asleep:
		face_vector(target_global - global_position)


func resume_movement() -> void:
	_talking = false
	_timer = randf_range(PAUSE_MIN, PAUSE_MAX)


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null or _talking or resting:
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
