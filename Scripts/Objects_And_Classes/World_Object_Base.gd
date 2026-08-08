class_name WorldObjectBase
extends CharacterBody2D

# ============================================================
# WORLD OBJECT BASE
# ============================================================
# Shared movement and bubble logic for all in-world entities:
# NPCs, Opponents, and Shopkeepers.
#
# Supported movement patterns:
#   "idle_random"         - stands still, looks random directions
#   "idle_cycle"          - cycles walk frames (e.g. swimmers)
#   "idle_down/up/left/right" - locked facing direction
#   "idle_down/up/left/right_random" - primary dir with occasional glances
#   "patrol_line"         - walks back and forth on one axis
#   "patrol_square"       - walks in a square loop
#   "random_wander"       - short walks in random directions within a radius
# ============================================================

var sprite: String = ""

# Movement config — set by MapManager before add_child
var movement_pattern: String = "idle_random"
var patrol_distance: float = 100.0
var patrol_speed: float = 60.0
var patrol_axis: String = "horizontal"
var wander_radius: float = 200.0

# Internal movement state
var patrol_direction_vec: Vector2 = Vector2.ZERO
var patrol_step: int = 0
var distance_walked: float = 0.0
var current_facing: String = "down"
var _restore_timer: SceneTreeTimer = null
var _glance_timer: SceneTreeTimer = null

var lock_facing: bool = false

# Optional per-actor override for the direction the PLAYER turns to when interacting with this actor
# ("up"/"down"/"left"/"right"). Set from the `interact_facing` field in the NPC/opponent data entry.
# Empty (the default) means the direction is derived from the geometry, which is what almost every
# actor wants. Needed for shop counters, where the counter forces the player into a spot that is not
# square-on to the shopkeeper, so the geometry would point them sideways along the counter.
var interact_facing: String = ""

var _wander_origin: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _is_wandering: bool = false
# Escape direction parked here after a collision aborts a wander attempt;
# the next _pick_wander_target consumes it so the entity steps away from
# whatever it just walked into instead of grinding in place.
var _blocked_dir: Vector2 = Vector2.ZERO

# Bubble
var _bubble_sprite: Sprite2D = null
const BUBBLE_Y_OFFSET: float = -19.0
const BUBBLE_Z_INDEX: int = 100

# Distance at which a nearby player halts movement. Shopkeeper overrides
# to 70.0 (behind a counter) before calling super._ready().
var player_block_distance: float = 30.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var direction_timer: Timer = $DirectionTimer

const DIRECTIONS   = ["up", "down", "left", "right"]
const DIR_VECTORS  = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
const SQUARE_ORDER = ["down", "right", "up", "left"]
const WANDER_PROXIMITY_BUFFER: float = 30.0
# ISSUE #81: patterns whose facing is dictated by the pattern itself, so a captured facing must never
# override them on respawn.
const FIXED_FACING_PATTERNS = ["idle_cycle", "idle_left", "idle_right", "idle_up", "idle_down"]

func _ready():
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite)
	# ISSUE #100: a sprite name that doesn't match a file in Overworld_Sprites/ returns null here, and
	# the actor then spawns completely invisible with no other symptom — name it in the console so a
	# renamed/missing sheet is obvious rather than looking like a spawn-condition bug.
	if animated_sprite.sprite_frames == null:
		push_error("ISSUE #100: '" + name + "' has no sprite sheet for '" + sprite + "' — it will be INVISIBLE")
	animated_sprite.scale = Vector2(0.5, 0.5)
	animated_sprite.play("idle_down")
	_setup_bubble()
	_init_movement()
	# ISSUE #56 (retest): if MapManager captured a facing from before a battle/menu, restore it now
	# (after _init_movement's pattern default) so the actor resumes facing the same way — e.g. an
	# opponent that turned to face the player stays facing the player instead of snapping back.
	if has_meta("restore_facing"):
		var rf := str(get_meta("restore_facing"))
		remove_meta("restore_facing")
		# ISSUE #81 FIX: never let a captured facing override a pattern that fixes the facing by design.
		# The locked idle_* patterns exist precisely to pin a direction, and idle_cycle must keep playing
		# its walk animation (an idle_ animation would freeze it, since _physics_process never replays it).
		if movement_pattern in FIXED_FACING_PATTERNS:
			pass   # keep the pattern's own facing
		elif rf != "" and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle_" + rf):
			current_facing = rf
			animated_sprite.play("idle_" + rf)

# ============================================================
# MOVEMENT HELPERS
# ============================================================

func _primary_dir_for_pattern() -> String:
	match movement_pattern:
		"idle_down_random":  return "down"
		"idle_up_random":    return "up"
		"idle_left_random":  return "left"
		"idle_right_random": return "right"
	return "down"

func _glance_dirs_for_pattern() -> Array:
	match movement_pattern:
		"idle_down_random", "idle_up_random":    return ["left", "right"]
		"idle_left_random", "idle_right_random": return ["up", "down"]
	return ["left", "right"]

func _is_player_blocking() -> bool:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	return global_position.distance_to(players[0].global_position) < player_block_distance

# Returns the cardinal direction AWAY from the nearest entity within the
# proximity buffer, or Vector2.ZERO when there is nothing to avoid.
func _wander_proximity_escape() -> Vector2:
	var nearest_blocker: Node = null
	var nearest_d: float = WANDER_PROXIMITY_BUFFER
	for group_name in ["npcs", "opponents"]:
		for other in get_tree().get_nodes_in_group(group_name):
			if other == self or not is_instance_valid(other):
				continue
			var d: float = position.distance_to(other.position)
			if d < nearest_d:
				nearest_d = d
				nearest_blocker = other
	if nearest_blocker == null:
		return Vector2.ZERO
	var away: Vector2 = position - nearest_blocker.position
	if away.length() < 0.001:
		return Vector2.ZERO
	if abs(away.x) > abs(away.y):
		return Vector2(sign(away.x), 0.0)
	return Vector2(0.0, sign(away.y))

func _init_movement():
	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(1.0, 4.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()
		"idle_cycle":
			current_facing = "down"
			animated_sprite.play("walk_down")
		# ISSUE #81 FIX: these four locked patterns played the right animation but never updated
		# current_facing, so it stayed at its "down" default. MapManager.capture_actor_positions()
		# then snapshotted "down" and restore_facing (ISSUE #56) forced them to face down on the next
		# spawn — which is why NPCs that should face left/right/up were looking downwards.
		"idle_left":   current_facing = "left";  animated_sprite.play("idle_left")
		"idle_right":  current_facing = "right"; animated_sprite.play("idle_right")
		"idle_up":     current_facing = "up";    animated_sprite.play("idle_up")
		"idle_down":   current_facing = "down";  animated_sprite.play("idle_down")
		"idle_down_random", "idle_up_random", "idle_left_random", "idle_right_random":
			var primary := _primary_dir_for_pattern()
			current_facing = primary
			animated_sprite.play("idle_" + primary)
			direction_timer.wait_time = randf_range(2.0, 15.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()
		"patrol_line":
			distance_walked = 0.0
			if patrol_axis == "horizontal":
				patrol_direction_vec = Vector2.RIGHT
				current_facing = "right"
			else:
				patrol_direction_vec = Vector2.DOWN
				current_facing = "down"
		"patrol_square":
			distance_walked = 0.0
			patrol_step = 0
			patrol_direction_vec = DIR_VECTORS[SQUARE_ORDER[0]]
			current_facing = SQUARE_ORDER[0]
		"random_wander":
			_wander_origin = position
			direction_timer.wait_time = randf_range(1.0, 4.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()

# ============================================================
# BUBBLE
# ============================================================

func _setup_bubble():
	_bubble_sprite = Sprite2D.new()
	_bubble_sprite.position = Vector2(0, BUBBLE_Y_OFFSET)
	_bubble_sprite.z_index = BUBBLE_Z_INDEX
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

func _get_bubble_texture() -> Texture2D:
	return load("res://Image_Assets/Icons/Message_Icons/new_talk.png")

func show_bubble():
	if _bubble_sprite == null:
		return
	_bubble_sprite.texture = _get_bubble_texture()
	_bubble_sprite.visible = true

func hide_bubble():
	if _bubble_sprite == null:
		return
	_bubble_sprite.visible = false

func refresh_bubble():
	if _bubble_sprite != null and _bubble_sprite.visible:
		_bubble_sprite.texture = _get_bubble_texture()

# ============================================================
# MOVEMENT — PHYSICS
# ============================================================

func _physics_process(delta):
	match movement_pattern:
		"patrol_line":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			_process_patrol_line(delta)
		"patrol_square":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			_process_patrol_square(delta)
		"random_wander":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			# Personal-space rule: only abort if our current heading is taking
			# us TOWARD the nearby entity. If we're already heading away (or
			# tangentially past them) the check would re-fire every frame and
			# trap us in place even though we are correctly escaping.
			if _is_wandering:
				var entity_escape: Vector2 = _wander_proximity_escape()
				if entity_escape != Vector2.ZERO:
					var to_target: Vector2 = _wander_target - position
					var heading_into_blocker: bool = (
						to_target.length() > 0.001
						and to_target.normalized().dot(entity_escape) < 0.0
					)
					if heading_into_blocker:
						_blocked_dir = entity_escape
						_is_wandering = false
						velocity = Vector2.ZERO
						animated_sprite.play("idle_" + current_facing)
						return
			_process_random_wander(delta)
		_:
			velocity = Vector2.ZERO
			return
	move_and_slide()
	# A blocked wander step would otherwise keep velocity pushing into the
	# obstacle and the walk animation locked on. Cancel the attempt so the
	# next direction-timer tick can pick a fresh path AWAY from the obstacle.
	if movement_pattern == "random_wander" and _is_wandering \
			and get_slide_collision_count() > 0 \
			and get_real_velocity().length() < patrol_speed * 0.3:
		_abort_blocked_wander()

func _process_patrol_line(delta):
	velocity = patrol_direction_vec * patrol_speed
	distance_walked += patrol_speed * delta
	animated_sprite.play("walk_" + current_facing)
	if distance_walked >= patrol_distance:
		distance_walked = 0.0
		patrol_direction_vec = -patrol_direction_vec
		if patrol_direction_vec.x > 0:   current_facing = "right"
		elif patrol_direction_vec.x < 0: current_facing = "left"
		elif patrol_direction_vec.y > 0: current_facing = "down"
		else:                            current_facing = "up"

func _process_patrol_square(delta):
	velocity = patrol_direction_vec * patrol_speed
	distance_walked += patrol_speed * delta
	animated_sprite.play("walk_" + current_facing)
	if distance_walked >= patrol_distance:
		distance_walked = 0.0
		patrol_step = (patrol_step + 1) % 4
		var dir_name = SQUARE_ORDER[patrol_step]
		patrol_direction_vec = DIR_VECTORS[dir_name]
		current_facing = dir_name

func _process_random_wander(delta):
	if not _is_wandering:
		velocity = Vector2.ZERO
		return
	var to_target = _wander_target - position
	if to_target.length() < 2.0:
		position = _wander_target
		velocity = Vector2.ZERO
		_is_wandering = false
		animated_sprite.play("idle_" + current_facing)
		return
	var move_dir = to_target.normalized()
	velocity = move_dir * patrol_speed
	if abs(move_dir.x) > abs(move_dir.y):
		current_facing = "right" if move_dir.x > 0 else "left"
	else:
		current_facing = "down" if move_dir.y > 0 else "up"
	animated_sprite.play("walk_" + current_facing)

func _abort_blocked_wander() -> void:
	# Cardinal opposite of the heading we just tried — used as a hint by the
	# next _pick_wander_target so the entity steps away from the obstacle.
	var attempted: Vector2 = _wander_target - position
	if attempted.length() < 0.001:
		_blocked_dir = Vector2.ZERO
	elif abs(attempted.x) > abs(attempted.y):
		_blocked_dir = Vector2(-sign(attempted.x), 0.0)
	else:
		_blocked_dir = Vector2(0.0, -sign(attempted.y))
	_is_wandering = false
	velocity = Vector2.ZERO
	animated_sprite.play("idle_" + current_facing)

func _pick_wander_target():
	var step = randf_range(30.0, 80.0)
	# Consume any pending escape hint from a previous blocked attempt first.
	if _blocked_dir != Vector2.ZERO:
		var escape: Vector2 = _blocked_dir
		_blocked_dir = Vector2.ZERO
		var escape_candidate: Vector2 = position + escape * step
		if escape_candidate.distance_to(_wander_origin) <= wander_radius:
			_wander_target = escape_candidate
			_is_wandering = true
			return
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	dirs.shuffle()
	for dir in dirs:
		var candidate = position + dir * step
		if candidate.distance_to(_wander_origin) <= wander_radius:
			_wander_target = candidate
			_is_wandering = true
			return
	var to_origin = _wander_origin - position
	_wander_target = position + (to_origin.normalized() if to_origin.length() > 1.0 else Vector2.ZERO) * step
	_is_wandering = true

func _on_direction_timer_timeout():
	var auto_restart := true
	match movement_pattern:
		"idle_random":
			var new_dir = DIRECTIONS[randi() % DIRECTIONS.size()]
			current_facing = new_dir
			animated_sprite.play("idle_" + new_dir)
		"random_wander":
			if not _is_wandering:
				_pick_wander_target()
		"idle_down_random", "idle_up_random", "idle_left_random", "idle_right_random":
			var dirs := _glance_dirs_for_pattern()
			var glance_dir: String = dirs[randi() % 2]
			current_facing = glance_dir
			animated_sprite.play("idle_" + glance_dir)
			if _glance_timer != null and is_instance_valid(_glance_timer) \
					and _glance_timer.timeout.is_connected(_on_glance_end):
				_glance_timer.timeout.disconnect(_on_glance_end)
			_glance_timer = get_tree().create_timer(randf_range(0.6, 1.8))
			_glance_timer.timeout.connect(_on_glance_end)
			auto_restart = false
	if auto_restart:
		direction_timer.wait_time = randf_range(2.0, 5.0)
		direction_timer.start()

func _on_glance_end():
	_glance_timer = null
	if not is_instance_valid(self):
		return
	var primary := _primary_dir_for_pattern()
	current_facing = primary
	animated_sprite.play("idle_" + primary)
	direction_timer.wait_time = randf_range(2.0, 15.0)
	direction_timer.start()

# `target_position` must be a GLOBAL position — this actor lives under the map's NPCS/OPPONENTS
# container, which is offset from the origin in some scenes, so local positions are not comparable.
func pause_and_face(target_position: Vector2):
	velocity = Vector2.ZERO
	set_physics_process(false)
	direction_timer.stop()
	_is_wandering = false
	if _restore_timer != null and is_instance_valid(_restore_timer):
		_restore_timer.timeout.disconnect(_on_restore_facing)
		_restore_timer = null
	if _glance_timer != null and is_instance_valid(_glance_timer) \
			and _glance_timer.timeout.is_connected(_on_glance_end):
		_glance_timer.timeout.disconnect(_on_glance_end)
		_glance_timer = null
	if lock_facing:
		return
	var diff = target_position - global_position
	if abs(diff.x) > abs(diff.y):
		current_facing = "right" if diff.x > 0 else "left"
	else:
		current_facing = "down" if diff.y > 0 else "up"
	animated_sprite.play("idle_" + current_facing)

# ISSUE #55: hard-stop this actor in place (no re-facing) so it can't keep wandering during the
# fade-out after a battle is accepted. Mirrors pause_and_face's freezing without turning the sprite.
func freeze():
	velocity = Vector2.ZERO
	set_physics_process(false)
	_is_wandering = false
	if direction_timer != null and is_instance_valid(direction_timer):
		direction_timer.stop()
	if _restore_timer != null and is_instance_valid(_restore_timer) \
			and _restore_timer.timeout.is_connected(_on_restore_facing):
		_restore_timer.timeout.disconnect(_on_restore_facing)
		_restore_timer = null
	if _glance_timer != null and is_instance_valid(_glance_timer) \
			and _glance_timer.timeout.is_connected(_on_glance_end):
		_glance_timer.timeout.disconnect(_on_glance_end)
		_glance_timer = null
	animated_sprite.play("idle_" + current_facing)

func resume_movement():
	set_physics_process(true)
	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.start()
		"idle_cycle":
			animated_sprite.play("walk_down")
		"patrol_line", "patrol_square":
			if patrol_direction_vec.x > 0:   current_facing = "right"
			elif patrol_direction_vec.x < 0: current_facing = "left"
			elif patrol_direction_vec.y > 0: current_facing = "down"
			else:                            current_facing = "up"
		"random_wander":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.start()
		"idle_down", "idle_up", "idle_left", "idle_right":
			_restore_timer = get_tree().create_timer(1.0)
			_restore_timer.timeout.connect(_on_restore_facing)
		"idle_down_random", "idle_up_random", "idle_left_random", "idle_right_random":
			var primary := _primary_dir_for_pattern()
			current_facing = primary
			animated_sprite.play("idle_" + primary)
			direction_timer.wait_time = randf_range(2.0, 15.0)
			direction_timer.start()

func _on_restore_facing():
	_restore_timer = null
	if not is_instance_valid(self):
		return
	match movement_pattern:
		"idle_down":  animated_sprite.play("idle_down");  current_facing = "down"
		"idle_up":    animated_sprite.play("idle_up");    current_facing = "up"
		"idle_left":  animated_sprite.play("idle_left");  current_facing = "left"
		"idle_right": animated_sprite.play("idle_right"); current_facing = "right"
