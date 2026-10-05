extends BaseMapScene

# ============================================================
# GYM CHALLENGE RECEPTION — interior
# Reached from Gym Plaza; leads onward to the Gym Challenge Hall.
# The base class auto-creates the OPPONENTS container at runtime
# since no such node exists in the .tscn.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn"


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_GYM_CHALLENGE_HALL
func get_map_data_name() -> String: return "Gym_Challenge_Reception"

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	# ISSUE #127: cash is shown on the message box chip row while talking to the shopkeeper.
	# If arriving from the plaza (not from the hall), flag the audience for partial regen
	if GameState.entering_from != "Gym_Challenge_Hall":
		GameState.progress["gym_challenge_audience_from_plaza"] = true
