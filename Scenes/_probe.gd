extends Node
func _ready() -> void:
	for p in ["res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd","res://Scripts/Main_Match_Gameplay_Scripts/Card_Ops.gd","res://Scripts/Main_Match_Gameplay_Scripts/Powers_And_Bodies_Effects.gd","res://Scripts/Main_Match_Gameplay_Scripts/Main_Match_Core_Gameplay_Script.gd","res://Scripts/Main_Match_Gameplay_Scripts/CPU_AI.gd","res://Scripts/Main_Match_Gameplay_Scripts/Trainer_Effects.gd","res://Scripts/Objects_And_Classes/Card_Class_Object_Script.gd"]:
		var s = load(p)
		print("PROBE ", p.get_file(), " -> ", "OK" if s != null and s.can_instantiate() else "FAILED")
	get_tree().quit()
