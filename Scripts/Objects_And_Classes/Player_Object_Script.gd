extends CharacterBody2D

# ============================================================
# PLAYER CHARACTER
# ============================================================
# Handles WASD/arrow movement, sprite animation, and
# detecting nearby opponents for interaction.
# ============================================================

signal interact_pressed(opponent)

@export var move_speed: float = 900.0

var current_direction: String = "down"
var is_moving: bool = false
var nearby_opponent: Node = null
var can_move: bool = true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var camera: Camera2D = $Camera2D

func _ready():
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1     # Walls only - no longer physically collides with opponents
	
	var file = FileAccess.open("res://Player_Data/Player_Current_Data.json", FileAccess.READ)
	var player_data = JSON.parse_string(file.get_as_text())
	file.close()
	
	var sprite_name = player_data["overworld_sprite"]
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite_name)
	animated_sprite.play("idle_down")
	animated_sprite.scale = Vector2(1, 1)
	
	interaction_area.body_entered.connect(_on_interaction_area_body_entered)
	interaction_area.body_exited.connect(_on_interaction_area_body_exited)
	
	if GameState.returning_from_battle:
		position = GameState.player_position

func _physics_process(_delta):
	if not can_move:
		velocity = Vector2.ZERO
		if is_moving:
			animated_sprite.play("idle_" + current_direction)
			is_moving = false
		return
	
	var input_direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_direction.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_direction.x += 1
	
	input_direction = input_direction.normalized()
	
	if input_direction != Vector2.ZERO:
		velocity = input_direction * move_speed
		is_moving = true
		_update_direction(input_direction)
		animated_sprite.play("walk_" + current_direction)
		
		# Block movement toward nearby opponent
		if nearby_opponent:
			var diff = nearby_opponent.position - position
			if diff.length() < 45.0:
				var toward = diff.normalized()
				var dot = velocity.dot(toward)
				if dot > 0:
					velocity -= toward * dot
	else:
		velocity = Vector2.ZERO
		if is_moving:
			animated_sprite.play("idle_" + current_direction)
			is_moving = false
	
	move_and_slide()

func _update_direction(direction: Vector2):
	if abs(direction.x) > abs(direction.y):
		current_direction = "right" if direction.x > 0 else "left"
	else:
		current_direction = "down" if direction.y > 0 else "up"

func _unhandled_input(event):
	if nearby_opponent and event.is_action_pressed("ui_accept"):
		interact_pressed.emit(nearby_opponent)
	
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom + Vector2(0.2, 0.2)).clamp(Vector2(1, 1), Vector2(4, 4))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom - Vector2(0.2, 0.2)).clamp(Vector2(1, 1), Vector2(4, 4))

func _on_interaction_area_body_entered(body: Node2D):
	if body.is_in_group("opponents"):
		nearby_opponent = body

func _on_interaction_area_body_exited(body: Node2D):
	if body == nearby_opponent:
		nearby_opponent = null
