extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Verdant_Forest.tscn"
const BGM_PATH = "res://Audio/BGM/Verdant_Forest_BGM.ogg"

# Default spawn used when arriving here for the first time (no door state,
# no menu-return state). Matches the placement set in the .tscn.
const DEFAULT_SPAWN_POSITION = Vector2(1770, 1850)

var NPC_JSON_PATH: String = ""

func _ready():
	# Read time and date from player progress
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()

	# Build NPC JSON path: e.g. "Verdant_Forest_NPCs_Day_4.json"
	NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Verdant_Forest_NPCs_" + time_of_day + "_" + str(date) + ".json"

	# Fall back to Day 4 if the specific time/date file doesn't exist
	if not ResourceLoader.exists(NPC_JSON_PATH):
		NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Verdant_Forest_NPCs_Day_4.json"

	SoundManagerScript.play_bgm(BGM_PATH, true)

	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)

	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask  = 2
	$"Door Areas".monitoring      = true
	$"Door Areas".monitorable     = true
	$"Door Areas".body_entered.connect(_on_door_entered)

	# Entry positions from other maps
	var entry_positions = {
		"Celeste_Harbour": Vector2(1775, 1880),
		"Rocket_Mart": Vector2(278, 1080),
	}

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		# Returning from main menu (or splash-screen resume)
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.returning_from_battle:
		# Returning from battle
		$Player.position = GameState.player_position
		$Player.set_direction(GameState.get_player_direction())
		GameState.returning_from_battle = false
	elif entry_positions.has(GameState.entering_from):
		# Returning from another map
		$Player.position = entry_positions[GameState.entering_from]
		$Player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
		GameState.return_to_scene = ""
	elif GameState.return_to_scene == "Verdant Forest":
		# Returning from interior
		$Player.position = GameState.interior_entry_position
		$Player.set_direction(GameState.get_player_direction())
		GameState.return_to_scene = ""
	else:
		# First load or other cases
		$Player.position = DEFAULT_SPAWN_POSITION
		$Player.set_direction(GameState.get_player_direction())

	# Persist current location so the splash screen can resume here on next launch
	GameState.save_current_location(SCENE_PATH, $Player.position)

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

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	var save_pos = body.position
	save_pos.y += 5

	# Map scenes use entering_from for hardcoded spawn; everything else is an interior.
	var map_scenes = ["Celeste_Harbour", "Verdant_Forest"]
	var is_map_scene = false
	for map_name in map_scenes:
		if target.contains(map_name):
			is_map_scene = true
			break

	if is_map_scene:
		GameState.entering_from = "Verdant_Forest"
		GameState.return_to_scene = ""
	else:
		GameState.interior_entry_position = save_pos
		GameState.return_to_scene = "Verdant Forest"
		GameState.entering_from = ""

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
