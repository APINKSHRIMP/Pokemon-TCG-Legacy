extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Verdant_Forest.tscn"

# Default spawn used when arriving here for the first time (no door state,
# no menu-return state). Matches the placement set in the .tscn.
const DEFAULT_SPAWN_POSITION = Vector2(474, 990)

func _ready():
	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.use_spawn_position:
		$Player.position = GameState.spawn_position
		GameState.use_spawn_position = false
		$Player.set_direction(GameState.get_player_direction())
	else:
		$Player.position = DEFAULT_SPAWN_POSITION
		$Player.set_direction(GameState.get_player_direction())

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
		SoundManagerScript.stop_bgm()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
