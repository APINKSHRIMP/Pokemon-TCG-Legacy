extends Node


func _input(event: InputEvent) -> void:
	if UIInput.is_cancel(event):   # Escape, Backspace or pad B
		if GameState.close_sub_menu(): return   # ISSUE #53: map is still loaded behind us — just pop this overlay
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
