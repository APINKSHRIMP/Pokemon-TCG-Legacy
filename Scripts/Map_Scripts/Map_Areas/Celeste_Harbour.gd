extends Node2D

const JSON_PATH = "res://Opponent_Data/Area_Opponents/Celeste_Harbour_Opponents.json"
const NPC_JSON_PATH = "res://Opponent_Data/Area_NPCs/Celeste_Harbour_NPCs.json"
const SCENE_PATH = "res://Scenes/Map_Scenes/Map_Areas/Celeste_Harbour.tscn"
const BGM_PATH = "res://Audio/BGM/Celeste_Harbour_BGM.ogg"

func _ready():
	SoundManagerScript.play_bgm(BGM_PATH, true)

	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)

	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask  = 2
	$"Door Areas".monitoring      = true
	$"Door Areas".monitorable     = true
	$Player.set_direction(GameState.get_player_direction())
	$"Door Areas".body_entered.connect(_on_door_entered)

	if GameState.return_to_scene == "Celeste Harbour":
		$Player.position = GameState.interior_entry_position
		GameState.return_to_scene = ""

	MapManager.initialise(
		$Player,
		$OPPONENTS,
		$UILAYER,
		JSON_PATH,
		[],
		SCENE_PATH,
		NPC_JSON_PATH,
		[]
	)

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SoundManagerScript.stop_bgm()
		get_tree().change_scene_to_file("res://Scenes/Map_Scenes/World_Maps/World_Map_Base_Scene.tscn")

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

	var save_pos = body.position
	save_pos.y += 5
	GameState.interior_entry_position = save_pos
	GameState.return_to_scene = "Celeste Harbour"
	GameState.use_spawn_position = false

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
