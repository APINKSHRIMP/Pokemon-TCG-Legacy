extends CharacterBody2D

# ============================================================
# PLAYER CHARACTER
# ============================================================

signal interact_pressed(opponent)
signal npc_interact_pressed(npc)

@export var move_speed: float = 160.0
@export var run_multiplier: float = 10.0  # Speed/animation multiplier while Shift is held

var current_direction: String = "down"
var is_moving: bool = false
var can_move: bool = true

# All interactables currently overlapping the InteractionArea (opponents + npcs)
var _nearby_candidates: Array = []
# The currently prioritised candidate (closest) — the only one showing a bubble
var _active_candidate: Node = null

# Back-compat accessors used by MapManager / other scripts
var nearby_opponent: Node:
	get:
		return _active_candidate if (_active_candidate != null and _active_candidate.is_in_group("opponents")) else null
var nearby_npc: Node:
	get:
		return _active_candidate if (_active_candidate != null and _active_candidate.is_in_group("npcs")) else null

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var camera: Camera2D = $Camera2D

func lock_movement():
	can_move = false
	velocity = Vector2.ZERO

func unlock_movement():
	can_move = true

func get_current_direction() -> String:
	return current_direction

func set_direction(direction: String):
	current_direction = direction
	animated_sprite.play("idle_" + current_direction)

# ISSUE #57: turn the player to face a target position (an NPC/opponent) when interacting, mirroring
# the way the NPC turns to face the player. Uses the dominant axis of the offset.
# The target must be a GLOBAL position: actors are children of the map's NPCS/OPPONENTS container,
# which is not always at the origin (the two marts offset theirs by 121,59), so their local positions
# are not comparable with the player's.
func face_toward(target_position: Vector2):
	var diff = target_position - global_position
	if abs(diff.x) > abs(diff.y):
		set_direction("right" if diff.x > 0 else "left")
	else:
		set_direction("down" if diff.y > 0 else "up")

func _ready():
	add_to_group("player")

	var file = FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
	var player_data = JSON.parse_string(file.get_as_text())
	file.close()

	var sprite_name = player_data["sprite"]
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite_name)
	animated_sprite.play("idle_down")
	animated_sprite.scale = Vector2(0.5, 0.5)

	# ISSUE #81 FIX: these four steps used to be orphaned INSIDE refresh_sprite() (that function was
	# accidentally inserted mid-_ready(), so everything below it silently became part of it). With the
	# signals never connected, no interaction bubble appeared and spacebar did nothing.
	interaction_area.body_entered.connect(_on_interaction_area_body_entered)
	interaction_area.body_exited.connect(_on_interaction_area_body_exited)

	if GameState.returning_from_battle:
		position = GameState.player_position

	# Seed candidates from bodies already overlapping on spawn (battle return case)
	call_deferred("_seed_existing_overlaps")

# ISSUE #52: the overworld map is no longer reloaded when a sub-menu closes, so a costume change made
# in the Costume menu has to be pushed onto the live player node instead of arriving via _ready().
func refresh_sprite() -> void:
	var file := FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
	if file == null:
		return
	var player_data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(player_data) != TYPE_DICTIONARY or not player_data.has("sprite"):
		return
	var new_frames = SpriteSheetLoader.load_sprite_frames(player_data["sprite"])
	if new_frames == null:
		return
	animated_sprite.sprite_frames = new_frames
	animated_sprite.play("idle_" + current_direction)

func _seed_existing_overlaps():
	if not is_instance_valid(interaction_area):
		return
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("opponents") or body.is_in_group("npcs"):
			if not _nearby_candidates.has(body):
				_nearby_candidates.append(body)
	_update_active_candidate()

func _physics_process(_delta):
	if not can_move:
		velocity = Vector2.ZERO
		if is_moving:
			animated_sprite.speed_scale = 1.0
			animated_sprite.play("idle_" + current_direction)
			is_moving = false
		# Still reconcile bubbles while frozen (e.g. during messagebox)
		_update_active_candidate()
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

	# Hold Shift to run: doubles movement speed and the walk animation cycle
	var is_running: bool = Input.is_key_pressed(KEY_SHIFT)
	var speed_scale: float = run_multiplier if is_running else 1.0
	# ISSUE #34: the global overworld walking-speed multiplier scales both walk and run (Options: slow
	# 0.8, standard 1.0, fast 1.2).
	var walk_mult: float = GameState.overworld_walking_speed

	if input_direction != Vector2.ZERO:
		velocity = input_direction * move_speed * speed_scale * walk_mult
		is_moving = true
		_update_direction(input_direction)
		animated_sprite.speed_scale = speed_scale * walk_mult
		animated_sprite.play("walk_" + current_direction)
	else:
		velocity = Vector2.ZERO
		if is_moving:
			animated_sprite.speed_scale = 1.0
			animated_sprite.play("idle_" + current_direction)
			is_moving = false

	move_and_slide()

	# Recompute closest candidate each frame so priority follows player movement
	_update_active_candidate()

func _update_direction(direction: Vector2):
	if abs(direction.x) > abs(direction.y):
		current_direction = "right" if direction.x > 0 else "left"
	else:
		current_direction = "down" if direction.y > 0 else "up"

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		# If message panel is open, spacebar forwards to MapManager
		if MapManager.message_panel != null and MapManager.message_panel.visible:
			# ISSUE #51 FIX: consume the input BEFORE handling. Answering "yes"
			# (e.g. opening the shop) triggers a scene change that frees this
			# player node, after which get_viewport() returns null and
			# set_input_as_handled() crashes. Grab the viewport first and guard.
			var vp = get_viewport()
			if vp != null:
				# Consume so dismissing a dialog can't re-trigger an interactable
				# the player happens to be standing on this same frame.
				vp.set_input_as_handled()
			MapManager.handle_message_spacebar()
			return

		# ISSUE #81 FIX: gate the interact emit on can_move, for the same reason the mouse-wheel zoom
		# below is gated. Since ISSUE #52 the map stays loaded underneath menu/sub-menu overlays and the
		# player is merely lock_movement()'d, so an unconsumed Space/Enter inside the deck builder fell
		# through to here and could start a battle with whoever the player happened to be standing next
		# to. The message-panel branch above stays ungated — dialogue is handled while frozen by design.
		if not can_move:
			return

		if _active_candidate != null and is_instance_valid(_active_candidate):
			if _active_candidate.is_in_group("opponents"):
				interact_pressed.emit(_active_candidate)
			elif _active_candidate.is_in_group("npcs"):
				npc_interact_pressed.emit(_active_candidate)

	if event is InputEventMouseButton:
		if event.pressed:
			if MapManager.message_panel != null and MapManager.message_panel.visible:
				MapManager.handle_message_spacebar()
				return
			# ISSUE #81: don't let the mouse wheel zoom the overworld camera while the player is locked
			# — i.e. while a menu/sub-menu overlay (deck/card/coin/sleeves) is open on top of the still-
			# loaded map. Scroll events fall THROUGH those sub-menu Controls to this _unhandled_input, so
			# without this guard scrolling a card/deck list zoomed the map underneath, only visible on
			# return. Movement keys were already gated on can_move; the zoom was not.
			if not can_move:
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom + Vector2(0.05, 0.05)).clamp(Vector2(0.5, 0.5), Vector2(10, 10))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom - Vector2(0.05, 0.05)).clamp(Vector2(0.5, 0.5), Vector2(10, 10))

func _on_interaction_area_body_entered(body: Node2D):
	if body.is_in_group("opponents") or body.is_in_group("npcs"):
		if not _nearby_candidates.has(body):
			_nearby_candidates.append(body)
		_update_active_candidate()

func _on_interaction_area_body_exited(body: Node2D):
	_nearby_candidates.erase(body)
	if body.has_method("hide_bubble"):
		body.hide_bubble()
	if body == _active_candidate:
		_active_candidate = null
	_update_active_candidate()

# ------------------------------------------------------------
# Priority: closest candidate wins — only it shows a bubble
# ------------------------------------------------------------
func _update_active_candidate():
	# Purge invalid refs
	_nearby_candidates = _nearby_candidates.filter(func(n): return is_instance_valid(n))

	if _nearby_candidates.is_empty():
		_active_candidate = null
		return

	var closest: Node = null
	var closest_dist_sq: float = INF
	for n in _nearby_candidates:
		var d_sq: float = global_position.distance_squared_to(n.global_position)
		if d_sq < closest_dist_sq:
			closest_dist_sq = d_sq
			closest = n

	# Hide bubbles on everyone except the closest
	for n in _nearby_candidates:
		if n == closest:
			continue
		if n.has_method("hide_bubble"):
			n.hide_bubble()

	# Always show on the active one (handles re-entry after battle + re-prioritisation)
	if closest != null and closest.has_method("show_bubble"):
		closest.show_bubble()

	_active_candidate = closest
