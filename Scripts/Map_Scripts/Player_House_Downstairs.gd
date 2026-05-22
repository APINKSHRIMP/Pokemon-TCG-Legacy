extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Downstairs.tscn"

# --- Door-return spawn points -------------------------------------------------
# Spawn point per scene the player can arrive from. The key is the value the
# source scene writes to GameState.entering_from. Values match the placements
# previously used by each door.
const SPAWN_FROM_CELESTE_HARBOUR        = Vector2(200, 205)  # front door from the harbour
const SPAWN_FROM_PLAYER_HOUSE_UPSTAIRS  = Vector2(365, 10)   # foot of the stairs
# ------------------------------------------------------------------------------

func _ready():
	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask = 2
	$"Door Areas".monitoring = true
	$"Door Areas".monitorable = true
	$"Door Areas".body_entered.connect(_on_door_entered)

	# Hard-coded spawn point per scene the player can arrive from. The key is
	# the value the source scene writes to GameState.entering_from.
	var entry_positions = {
		"Celeste_Harbour":       SPAWN_FROM_CELESTE_HARBOUR,
		"Player_House_Upstairs": SPAWN_FROM_PLAYER_HOUSE_UPSTAIRS,
	}

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif entry_positions.has(GameState.entering_from):
		# Returning from another scene through one of this scene's doors
		$Player.position = entry_positions[GameState.entering_from]
		$Player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
	else:
		# First load / fallback — treat as arriving from the harbour
		$Player.position = SPAWN_FROM_CELESTE_HARBOUR
		$Player.set_direction(GameState.get_player_direction())

	# Persist current location so the splash screen can resume here on next launch
	GameState.save_current_location(SCENE_PATH, $Player.position)

	MapManager.initialise($Player, Node2D.new(), $UILAYER, "", [], "")
	_apply_moving_in_visibility()

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _apply_moving_in_visibility():
	var moving_in_done = GameState.progress.get("moving_in_completed", false)
	if moving_in_done:
		for layer in $DOWNSTAIRS.get_children():
			if layer is TileMapLayer:
				layer.visible = layer.name != "Moving In"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
		var is_escape: bool = event.keycode == KEY_ESCAPE
		if not (is_enter or is_escape):
			return
		if is_enter and MapManager.message_panel != null and MapManager.message_panel.visible:
			return
		get_viewport().set_input_as_handled()
		GameState.save_menu_return_state(SCENE_PATH, $Player.position, $Player.get_current_direction())
		GameState.save_current_location(SCENE_PATH, $Player.position)
		SoundManagerScript.stop_bgm()
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var door_area = $"Door Areas"
	var nearest_shape = null
	var nearest_dist = INF
	for child in door_area.get_children():
		if child is CollisionShape2D:
			var dist = child.global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_shape = child

	if nearest_shape == null:
		return

	var target = nearest_shape.get_meta("target_scene")

	if not target.contains("Upstairs"):
		if not GameState.progress.get("player_collected_starter_box", false):
			MapManager._show_message_with_ok("I should check upstairs before heading out.")
			return

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	# Both doors (out to Celeste Harbour, up to the upstairs) resolve their
	# spawn from a hard-coded table keyed on entering_from, so we just
	# announce our origin scene.
	GameState.entering_from = "Player_House_Downstairs"

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
