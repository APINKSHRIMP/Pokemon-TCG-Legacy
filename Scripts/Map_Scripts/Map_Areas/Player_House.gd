extends Node2D

func _ready():
	$Player.set_direction(GameState.get_player_direction())
	for child in get_children():
		if child is Area2D:
			child.collision_layer = 3
			child.collision_mask = 2
			child.body_entered.connect(_on_door_entered.bindv([child]))
	
	# Wait one frame for scene to fully initialize
	await get_tree().process_frame
	
	# Only set position if entering from Celeste Harbour (first time)
	if GameState.last_interior_scene != "Player House":
		$Player.position = Vector2(200, 200)
	
	# Fade in
	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _on_door_entered(body: Node2D, door: Area2D):
	if body.is_in_group("player"):
		GameState.save_player_direction(body.get_current_direction())
		body.lock_movement()
		
		var save_pos = body.position
		save_pos.y -= 5
		GameState.save_interior_player_position(save_pos)
		GameState.last_interior_scene = "Celeste Harbour"
		
		var target = door.get_child(0).get_meta("target_scene")
		
		var tween = create_tween()
		tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 1.0)
		tween.tween_callback(func():
			get_tree().change_scene_to_file(target)
		)
