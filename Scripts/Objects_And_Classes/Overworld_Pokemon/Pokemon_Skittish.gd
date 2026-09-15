class_name PokemonSkittish
extends OverworldPokemon

## SKITTISH template -- Rattata, Sentret, Zigzagoon, Ekans... Wanders around its spawn
## point with real collision, bouncing off anything it runs into, at its species' own
## wander speed (registry `wander_speed`).
##
## When the player comes within SCARE_DISTANCE it bolts sideways -- left, right, a
## random one of the two, or away from the player, per the spawn point's `flee` -- very
## fast and straight through anything in the way, then fades out and is gone for the
## rest of this map load. It is drawn under every tree layer, so it can vanish behind
## the trees as it runs.

# ---- tweakables -------------------------------------------------------------
## Absolute z. The map's ground tiles and tree trunks are 0 and every tree top / tree
## wall is 1 or higher, and the spawner is added after the tile maps, so 0 draws it
## over the ground but behind the trees (Celeste Harbour and Verdant Forest).
const Z := 0
const WANDER_RADIUS := 140.0
const STEP_MIN := 24.0
const STEP_MAX := 70.0
## The walk cycle follows the wander speed (the default speed = normal), within these.
const WANDER_ANIM_MIN := 0.25
const WANDER_ANIM_MAX := 1.5
## Seconds it stands still between dashes.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 2.2
## Bounces off obstacles allowed in one dash before it gives up and pauses.
const MAX_BOUNCES := 3
## The player this close (world px) sends it running. 100 world px = 250 px on screen at
## the default 2.5x zoom.
const SCARE_DISTANCE := 100.0
## The same for every species, and always faster than the player: the fastest normal
## player is 160 px/s x 1.6 (Fast walking option) x 2 (Shift) = 512 px/s.
const FLEE_SPEED := 640.0
const FLEE_ANIM_SPEED := 3.0
## Seconds of running before it starts to fade, and how long the fade takes.
const FLEE_FADE_DELAY := 0.2
const FLEE_FADE_TIME := 1.0
const COLLISION_SIZE := Vector2(14, 10)
const COLLISION_OFFSET := Vector2(0, 5)
# -----------------------------------------------------------------------------

enum State { IDLE, WANDER, FLEE, TALKING }

var _state: int = State.IDLE
var _home: Vector2
var _target: Vector2
var _pause: float = 0.0
var _bounces: int = 0
var _flee_dir: Vector2 = Vector2.RIGHT
var _flee_time: float = 0.0
var _wander_speed: float = OverworldPokemonData.DEFAULT_SKITTISH_WANDER_SPEED


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Layer 4 is the NPC layer: the player collides with it (mask 5) and the player's
	# InteractionArea (mask 4) sees it. Mask 1 = the world, 4 = other actors.
	collision_layer = 4
	collision_mask = 1 | 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# A scaled-up Pokémon gets a body to match.
	rect.size = COLLISION_SIZE * size_scale
	shape.shape = rect
	shape.position = COLLISION_OFFSET * size_scale
	add_child(shape)
	add_to_group("pokemon")
	animating = false
	_wander_speed = OverworldPokemonData.species_wander_speed(species)
	_home = global_position
	_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
	set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])


func is_interactable() -> bool:
	return _state != State.FLEE and not _is_gone


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null:
		return
	match _state:
		State.TALKING:
			velocity = Vector2.ZERO
			return
		State.FLEE:
			_process_flee(delta)
			return

	if _should_flee():
		_start_flee()
		return

	if _state == State.IDLE:
		_pause -= delta
		if _pause <= 0.0:
			_pick_target()
		return

	# WANDER
	var to_target := _target - global_position
	if to_target.length() < 2.0:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
		return
	var heading := to_target.normalized()
	velocity = heading * _wander_speed
	face_vector(heading)
	move_and_slide()
	if get_slide_collision_count() > 0 and get_real_velocity().length() < _wander_speed * 0.5:
		_bounces += 1
		if _bounces > MAX_BOUNCES:
			_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
			return
		# Bounce: carry on the remaining distance along the reflected heading.
		var normal := get_slide_collision(0).get_normal()
		var bounced := heading.bounce(normal).normalized()
		if bounced.length() < 0.001:
			bounced = normal
		_target = global_position + bounced * maxf(to_target.length(), STEP_MIN)
		if _target.distance_to(_home) > WANDER_RADIUS:
			_target = global_position + (_home - global_position).normalized() * STEP_MIN


func _pick_target() -> void:
	var angle := randf() * TAU
	var candidate := global_position + Vector2.from_angle(angle) * randf_range(STEP_MIN, STEP_MAX)
	if candidate.distance_to(_home) > WANDER_RADIUS:
		candidate = global_position + (_home - global_position).normalized() * randf_range(STEP_MIN, STEP_MAX)
	_target = candidate
	_bounces = 0
	_state = State.WANDER
	animating = true
	# A slow Ekans shuffles, a quick Sentret scurries: the walk cycle keeps pace.
	anim_speed = clampf(_wander_speed / OverworldPokemonData.DEFAULT_SKITTISH_WANDER_SPEED,
			WANDER_ANIM_MIN, WANDER_ANIM_MAX)
	_apply_region()


func _go_idle(pause: float) -> void:
	velocity = Vector2.ZERO
	_state = State.IDLE
	_pause = pause
	animating = false
	_apply_region()


# ---- running away -----------------------------------------------------------

## Close enough, whatever the player is doing -- unless a message box or cutscene has
## the player held still.
func _should_flee() -> bool:
	var player := player_node()
	if player == null:
		return false
	if "can_move" in player and not player.can_move:
		return false
	return global_position.distance_to(player.global_position) <= SCARE_DISTANCE


func _start_flee() -> void:
	_state = State.FLEE
	_flee_time = 0.0
	_flee_dir = Vector2.LEFT if randf() < 0.5 else Vector2.RIGHT
	match str(spawn_point.get("flee", "random")):
		"left":
			_flee_dir = Vector2.LEFT
		"right":
			_flee_dir = Vector2.RIGHT
		"away_from_player":
			# Sideways only: whichever way takes it further from the player. Level with
			# the player (or no player) keeps the random pick above.
			var player := player_node()
			if player != null and not is_equal_approx(player.global_position.x, global_position.x):
				_flee_dir = Vector2.RIGHT if player.global_position.x < global_position.x else Vector2.LEFT
	# Off the NPC layer so the player's InteractionArea lets go of it (no bubble, no
	# Space), and no mask so it runs straight through fences and behind trees.
	collision_layer = 0
	collision_mask = 0
	hide_bubble()
	remove_from_group("pokemon")
	animating = true
	anim_speed = FLEE_ANIM_SPEED
	face_vector(_flee_dir)
	_apply_region()


func _process_flee(delta: float) -> void:
	_flee_time += delta
	global_position += _flee_dir * FLEE_SPEED * delta
	var fade_t := (_flee_time - FLEE_FADE_DELAY) / FLEE_FADE_TIME
	if fade_t > 0.0:
		modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)
	if fade_t >= 1.0:
		despawn()


# ---- talking ----------------------------------------------------------------

func pause_and_face(target_global: Vector2) -> void:
	if _state == State.FLEE:
		return
	_state = State.TALKING
	velocity = Vector2.ZERO
	animating = false
	face_vector(target_global - global_position)
	_apply_region()


func resume_movement() -> void:
	if _state == State.TALKING:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
