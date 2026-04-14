extends Node2D

const NPC_DAY_1_JSON_PATH = "res://NPC_and_Opponent_Data/Celeste_Harbour_NPCs_Day_1.json"
const NPC_EVENING_1_JSON_PATH = "res://NPC_and_Opponent_Data/Celeste_Harbour_NPCs_Evening_1.json"
const NPC_NIGHT_1_JSON_PATH = "res://NPC_and_Opponent_Data/Celeste_Harbour_NPCs_Night_1.json"
const NPC_DAY_2_JSON_PATH = "res://NPC_and_Opponent_Data/Celeste_Harbour_NPCs_Day_2.json"

var NPC_JSON_PATH = NPC_DAY_1_JSON_PATH

const SCENE_PATH = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const BGM_PATH = "res://Audio/BGM/Celeste_Harbour_BGM.ogg"

const TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas.tres")
const TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Evening.tres")
const TILESET_NIGHT = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Night.tres")

func _ready():
	
	set_time_of_day("Day")
	
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
		NPC_JSON_PATH,
		[],
		SCENE_PATH,
		NPC_JSON_PATH,
		[]
	)

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	match time:
		"Day":     
			tileset = TILESET_DAY
			$LIGHTS.queue_free()
			NPC_JSON_PATH = NPC_DAY_1_JSON_PATH
		"Evening": 
			tileset = TILESET_EVENING
			$LIGHTS.visible = true
			NPC_JSON_PATH = NPC_EVENING_1_JSON_PATH
		"Night":   
			tileset = TILESET_NIGHT  	
			$LIGHTS.visible = true
			NPC_JSON_PATH = NPC_NIGHT_1_JSON_PATH
			
	for layer in get_tree().get_nodes_in_group(""):
		pass

	_apply_tileset($TILE_MAPS, tileset)

func _apply_tileset(node: Node, tileset: TileSet) -> void:
	if node is TileMapLayer:
		node.tile_set = tileset
	for child in node.get_children():
		_apply_tileset(child, tileset)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SoundManagerScript.stop_bgm()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")

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
