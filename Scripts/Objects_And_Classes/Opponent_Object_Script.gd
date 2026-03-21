extends CharacterBody2D

# ============================================================
# OPPONENT NPC
# ============================================================
# Supports 4 movement patterns:
#   "idle_random"   - stands still, looks random directions
#   "idle_cycle"    - stands still, cycles walk frames (swimmers)
#   "patrol_line"   - walks back and forth on one axis
#   "patrol_square" - walks in a square loop
# ============================================================

# --- Opponent identity (set by WorldMap before adding to tree) ---
var opponent_name: String = ""
var overworld_sprite: String = ""
var battle_sprite: String = ""
var music: String = ""
var deck: String = ""
var meet_text: String = ""
var rematch_text: String = ""
var first_win_text: String = ""
var rematch_win_text: String = ""
var loss_text: String = ""
var coin_reward: String = ""
var cash_reward: String = ""

# --- Movement config (set by WorldMap before adding to tree) ---
var movement_pattern: String = "idle_random"
var patrol_distance: float = 100.0
var patrol_speed: float = 60.0
var patrol_axis: String = "horizontal"  # for patrol_line

# --- Internal movement state ---
var patrol_direction_vec: Vector2 = Vector2.ZERO
var patrol_step: int = 0
var distance_walked: float = 0.0
var current_facing: String = "down"

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
	collision_layer = 3   # Opponent IS on layer 3
	collision_mask = 1     # Opponent only collides with walls (1)
	add_to_group("opponents")
	
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(overworld_sprite)
	animated_sprite.scale = Vector2(2.5, 2.5)
	animated_sprite.play("idle_down")
	
	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()
		"idle_cycle":
			animated_sprite.play("walk_down")
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

func _on_direction_timer_timeout():
	var new_dir = DIRECTIONS[randi() % DIRECTIONS.size()]
	current_facing = new_dir
	animated_sprite.play("idle_" + new_dir)
	direction_timer.wait_time = randf_range(2.0, 5.0)
	direction_timer.start()

func pause_and_face(target_position: Vector2):
	# Stop movement
	velocity = Vector2.ZERO
	set_physics_process(false)
	direction_timer.stop()
	
	# Face toward the target (the player)
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
			# Recalculate facing from the current movement direction
			# so it doesn't stay stuck facing the player
			if patrol_direction_vec.x > 0: current_facing = "right"
			elif patrol_direction_vec.x < 0: current_facing = "left"
			elif patrol_direction_vec.y > 0: current_facing = "down"
			else: current_facing = "up"

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
