extends Node2D

const NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Card_Mart_NPCs.json"

func _ready():
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop1.ogg", true)

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
		$Player.position = Vector2(208, 172)

	MapManager.initialise($Player, $NPCS, $UILAYER, "", [], "", NPC_JSON_PATH, [])

	print("Children of self: ")
	for c in get_children():
		print("  ", c.name, " - ", c)

	_apply_moving_in_visibility()

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _apply_moving_in_visibility():
	var moving_in_done = GameState.progress.get("moving_in_completed", false)
	if moving_in_done:
		for layer in $DOWNSTAIRS.get_children():
			if layer is TileMapLayer:
				layer.visible = layer.name != "Moving In"

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

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	if target.contains("Upstairs"):
		GameState.spawn_position = Vector2(55, 25)
		GameState.use_spawn_position = true
	else:
		GameState.use_spawn_position = false

	var fade_tween = create_tween()
	fade_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	fade_tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
