class_name PokemonRodent
extends OverworldPokemon

## RODENT template -- Rattata, Sentret, Zigzagoon... Wanders quickly around its spawn
## point with real collision, bouncing off anything it runs into.
##
## Walk up to it at a sneaking pace and Space makes it say its name. Come at it
## running (Shift) or with the walking-speed option on a preset outside
## SNEAK_SPEED_PRESETS and it bolts directly away from you, very fast, until it is
## off screen, then despawns for the rest of this map load.

# ---- tweakables -------------------------------------------------------------
const Z := 1
const WANDER_SPEED := 85.0
const WANDER_RADIUS := 140.0
const STEP_MIN := 24.0
const STEP_MAX := 70.0
## Seconds it stands still between dashes.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 2.2
## Bounces off obstacles allowed in one dash before it gives up and pauses.
const MAX_BOUNCES := 3
## A moving player this close can scare it.
const SCARE_RADIUS := 72.0
const FLEE_SPEED := 320.0
const FLEE_ANIM_SPEED := 3.0
## Safety net: gone after this long even if it is somehow still on screen.
const FLEE_TIMEOUT := 6.0
## If it is pinned against something for this long while fleeing, it drops its
## collision and squeezes through rather than grinding in place on camera.
const STUCK_PHASE_TIME := 0.25
const OFFSCREEN_MARGIN := 24.0
## Stops wandering when the player stands this close (so it can be talked to).
const PLAYER_BLOCK_DISTANCE := 26.0
## Walking-speed presets (GameState.WALKING_SPEED_PRESETS keys) that let the player
## walk right up to one without scaring it. Shift always scares.
const SNEAK_SPEED_PRESETS := ["very_slow", "slow", "normal"]
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
var _stuck_time: float = 0.0


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
	rect.size = COLLISION_SIZE
	shape.shape = rect
	shape.position = COLLISION_OFFSET
	add_child(shape)
	add_to_group("pokemon")
	animating = false
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
	var player := player_node()
	if player != null and global_position.distance_to(player.global_position) < PLAYER_BLOCK_DISTANCE:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
		return
	var to_target := _target - global_position
	if to_target.length() < 2.0:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
		return
	var heading := to_target.normalized()
	velocity = heading * WANDER_SPEED
	face_vector(heading)
	move_and_slide()
	if get_slide_collision_count() > 0 and get_real_velocity().length() < WANDER_SPEED * 0.5:
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
	_apply_region()


func _go_idle(pause: float) -> void:
	velocity = Vector2.ZERO
	_state = State.IDLE
	_pause = pause
	animating = false
	_apply_region()


# ---- scaring ----------------------------------------------------------------

func _should_flee() -> bool:
	var player := player_node()
	if player == null:
		return false
	if "can_move" in player and not player.can_move:
		return false
	if not ("is_moving" in player and player.is_moving):
		return false
	if global_position.distance_to(player.global_position) > SCARE_RADIUS:
		return false
	if Input.is_key_pressed(KEY_SHIFT):
		return true
	return not SNEAK_SPEED_PRESETS.has(GameState.walking_speed_setting)


func _start_flee() -> void:
	var player := player_node()
	_state = State.FLEE
	_flee_time = 0.0
	_stuck_time = 0.0
	if player != null:
		_flee_dir = global_position - player.global_position
	if _flee_dir.length() < 0.001:
		_flee_dir = Vector2.from_angle(randf() * TAU)
	_flee_dir = _flee_dir.normalized()
	# Off the NPC layer so the player's InteractionArea lets go of it -- no bubble,
	# no Space, on something that is running away.
	collision_layer = 0
	hide_bubble()
	remove_from_group("pokemon")
	animating = true
	anim_speed = FLEE_ANIM_SPEED
	face_vector(_flee_dir)
	_apply_region()


func _process_flee(delta: float) -> void:
	_flee_time += delta
	velocity = _flee_dir * FLEE_SPEED
	move_and_slide()
	if get_real_velocity().length() < FLEE_SPEED * 0.3:
		_stuck_time += delta
		if _stuck_time >= STUCK_PHASE_TIME:
			collision_mask = 0
	else:
		_stuck_time = 0.0
	face_vector(get_real_velocity() if get_real_velocity().length() > 1.0 else _flee_dir)
	if _flee_time > FLEE_TIMEOUT or not view_rect().grow(OFFSCREEN_MARGIN).has_point(global_position):
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
