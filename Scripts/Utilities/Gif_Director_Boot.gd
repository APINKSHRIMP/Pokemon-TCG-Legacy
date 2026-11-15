extends SceneTree

# Boots Gif_Director (see that file for the command line). The director is a Node so it
# can name the autoloads directly; a --script main loop is compiled before they exist.

func _init() -> void:
	_boot.call_deferred()


func _boot() -> void:
	root.add_child(load("res://Scripts/Utilities/Gif_Director.gd").new())
