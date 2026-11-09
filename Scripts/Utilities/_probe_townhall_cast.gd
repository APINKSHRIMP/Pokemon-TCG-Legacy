extends Node
# Temporary probe: compiles every script touched by the Town Hall crowd work. Delete when done.

const PATHS := [
	"res://Scripts/Map_Scripts/Town_Hall.gd",
	"res://Scripts/Map_Scripts/Town_Hall_Crowd.gd",
	"res://Scripts/Map_Scripts/Gym_Challenge_Reception.gd",
	"res://Scripts/Map_Scripts/Base_Map_Scene.gd",
	"res://Scripts/Global_Scripts/World_Map.gd",
	"res://Scripts/Main_Match_Gameplay_Scripts/Match_End_Outro_Script.gd",
	"res://Scripts/Main_Match_Gameplay_Scripts/Best_Of_3_Transition_Script.gd",
	"res://Scripts/Menu_Scripts/Bag_Script.gd",
]

func _ready() -> void:
	await get_tree().process_frame
	for p in PATHS:
		var s = load(p)
		print("COMPILE ", p.get_file(), ": ", "ok" if s is GDScript and s.can_instantiate() else "FAILED")
	get_tree().quit()
