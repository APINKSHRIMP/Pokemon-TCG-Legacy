extends Node

func _ready() -> void:
	var keeper := Node.new()
	keeper.name = "ProbeKeeper"
	keeper.set_script(load("res://Scenes/_Probe/_keeper.gd"))
	get_tree().root.add_child.call_deferred(keeper)
	get_tree().change_scene_to_file.call_deferred("res://Scenes/Map_Scenes/Verdant_Forest.tscn")
