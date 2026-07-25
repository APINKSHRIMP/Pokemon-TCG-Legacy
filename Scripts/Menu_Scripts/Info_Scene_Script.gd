extends Node


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
