extends CharacterBody2D

# ============================================================
# OPPONENT NPC
# ============================================================
# Supports movement patterns:
#   "idle_random"   - stands still, looks random directions
#   "idle_cycle"    - stands still, cycles walk frames (swimmers)
#   "patrol_line"   - walks back and forth on one axis
#   "patrol_square" - walks in a square loop
#   "random_wander" - takes short walks in random directions within a radius
# ============================================================

# --- Opponent identity (set by MapManager before adding to tree) ---
var opponent_name: String = ""
var sprite: String = ""
var music: String = ""
var deck: String = ""
var meet_text: String = ""
var rematch_text: String = ""
var first_win_text: String = ""
var rematch_win_text: String = ""
var loss_text: String = ""
var coin_reward: String = ""
var cash_reward: String = ""

# --- Movement config (set by MapManager before adding to tree) ---
var movement_pattern: String = "idle_random"
var patrol_distance: float = 100.0
var patrol_speed: float = 60.0
var patrol_axis: String = "horizontal"
var wander_radius: float = 200.0

# --- Internal movement state ---
var patrol_direction_vec: Vector2 = Vector2.ZERO
var patrol_step: int = 0
var distance_walked: float = 0.0
var current_facing: String = "down"
var _restore_timer: SceneTreeTimer = null

# --- random_wander state ---
var _wander_origin: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _is_wandering: bool = false

# --- Interaction bubble ---
var _bubble_sprite: Sprite2D = null

const BUBBLE_Y_OFFSET: float = -19.0
const BUBBLE_Z_INDEX: int = 100

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var direction_timer: Timer = $DirectionTimer

const DIRECTIONS = ["up", "down", "left", "right"]
const DIR_VECTORS = {
	"up": Vector2.UP, "down": Vector2.DOWN,
	"left": Vector2.LEFT, "right": Vector2.RIGHT,
}
const SQUARE_ORDER = ["down", "right", "up", "left"]

func _is_player_blocking() -> bool:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	return position.distance_to(players[0].position) < 70.0

func _ready():
	add_to_group("opponents")

	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite)
	animated_sprite.scale = Vector2(0.5, 0.5)
	animated_sprite.play("idle_down")

	_setup_bubble()

	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(1.0, 4.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()
		"idle_cycle":
			animated_sprite.play("walk_down")
		"idle_left":
			animated_sprite.play("idle_left")
		"idle_right":
			animated_sprite.play("idle_right")
		"idle_up":
			animated_sprite.play("idle_up")
		"idle_down":
			animated_sprite.play("idle_down")
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
# INTERACTION BUBBLE
# ============================================================

func _setup_bubble():
	_bubble_sprite = Sprite2D.new()
	_bubble_sprite.position = Vector2(0, BUBBLE_Y_OFFSET)
	_bubble_sprite.z_index = BUBBLE_Z_INDEX
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

func _get_bubble_texture() -> Texture2D:
	if GameState.has_beaten_opponent(opponent_name):
		return load("res://image_assets/misc/old_battle.png")
	else:
		return load("res://image_assets/misc/new_battle.png")

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
# MOVEMENT
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
			_process_random_wander(delta)
		_:
			velocity = Vector2.ZERO
			return
	move_and_slide()

func _process_patrol_line(delta):
	velocity = patrol_direction_vec * patrol_speed
	distance_walked += patrol_speed * delta
	animated_sprite.play("walk_" + current_facing)

	if distance_walked >= patrol_distance:
		distance_walked = 0.0
		patrol_direction_vec = -patrol_direction_vec
		if patrol_direction_vec.x > 0: current_facing = "right"
		elif patrol_direction_vec.x < 0: current_facing = "left"
		elif patrol_direction_vec.y > 0: current_facing = "down"
		else: current_facing = "up"

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

func _pick_wander_target():
	var step = randf_range(30.0, 80.0)
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	dirs.shuffle()
	for dir in dirs:
		var candidate = position + dir * step
		if candidate.distance_to(_wander_origin) <= wander_radius:
			_wander_target = candidate
			_is_wandering = true
			return
	var to_origin = (_wander_origin - position)
	if to_origin.length() > 1.0:
		_wander_target = position + to_origin.normalized() * step
	else:
		_wander_target = _wander_origin
	_is_wandering = true

func _on_direction_timer_timeout():
	match movement_pattern:
		"idle_random":
			var new_dir = DIRECTIONS[randi() % DIRECTIONS.size()]
			current_facing = new_dir
			animated_sprite.play("idle_" + new_dir)
		"random_wander":
			if not _is_wandering:
				_pick_wander_target()
	direction_timer.wait_time = randf_range(2.0, 5.0)
	direction_timer.start()

func pause_and_face(target_position: Vector2):
	velocity = Vector2.ZERO
	set_physics_process(false)
	direction_timer.stop()
	_is_wandering = false

	if _restore_timer != null and is_instance_valid(_restore_timer):
		_restore_timer.timeout.disconnect(_on_restore_facing)
		_restore_timer = null

	var diff = target_position - position
	if abs(diff.x) > abs(diff.y):
		current_facing = "right" if diff.x > 0 else "left"
	else:
		current_facing = "down" if diff.y > 0 else "up"
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
			if patrol_direction_vec.x > 0: current_facing = "right"
			elif patrol_direction_vec.x < 0: current_facing = "left"
			elif patrol_direction_vec.y > 0: current_facing = "down"
			else: current_facing = "up"
		"random_wander":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.start()
		"idle_down", "idle_up", "idle_left", "idle_right":
			_restore_timer = get_tree().create_timer(1.0)
			_restore_timer.timeout.connect(_on_restore_facing)

func _on_restore_facing():
	_restore_timer = null
	if not is_instance_valid(self):
		return
	match movement_pattern:
		"idle_down":  animated_sprite.play("idle_down");  current_facing = "down"
		"idle_up":    animated_sprite.play("idle_up");    current_facing = "up"
		"idle_left":  animated_sprite.play("idle_left");  current_facing = "left"
		"idle_right": animated_sprite.play("idle_right"); current_facing = "right"

func get_greeting_text() -> String:
	if GameState.has_beaten_opponent(opponent_name):
		return rematch_text
	return meet_text

func get_result_text(player_won: bool) -> String:
	if player_won:
		if not GameState.has_beaten_opponent(opponent_name):
			return first_win_text
		return rematch_win_text
	return loss_text
