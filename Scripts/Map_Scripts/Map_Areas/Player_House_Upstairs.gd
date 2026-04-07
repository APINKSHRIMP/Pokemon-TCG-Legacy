extends Node2D

func _ready():
	
	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask = 2
	$"Door Areas".monitoring = true
	$"Door Areas".monitorable = true
	$Player.set_direction(GameState.get_player_direction())
	$"Door Areas".body_entered.connect(_on_door_entered)

	if GameState.use_spawn_position:
		$Player.position = GameState.spawn_position
		GameState.use_spawn_position = false
	else:
		$Player.position = Vector2(50, 25)

	await get_tree().process_frame

	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var shape_node = $"Door Areas".get_child(0)
	var target = shape_node.get_meta("target_scene")

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	GameState.spawn_position = Vector2(360, 15)
	GameState.use_spawn_position = true

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
