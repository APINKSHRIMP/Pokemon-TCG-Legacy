extends BaseMapScene

# ============================================================
# GYM CHALLENGE RECEPTION — interior
# Reached from Gym Plaza; leads onward to the Gym Challenge Hall.
# The base class auto-creates the OPPONENTS container at runtime
# since no such node exists in the .tscn.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn"
const BGM_PATH   = "res://Audio/BGM/Gym Leader Challenge Hall (Pokmon Card GB2 - GRs Challenge Cup).ogg"

const SPAWN_FROM_GYM_PLAZA          = Vector2(350, 450)
const SPAWN_FROM_GYM_CHALLENGE_HALL = Vector2(220, 45)

var _npc_json_path: String = ""

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return BGM_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_GYM_PLAZA
func get_entry_positions() -> Dictionary:
	return {
		"Gym_Plaza":          SPAWN_FROM_GYM_PLAZA,
		"Gym_Challenge_Hall": SPAWN_FROM_GYM_CHALLENGE_HALL,
	}
func get_opponent_json_path() -> String: return _npc_json_path
func get_npc_json_path() -> String:      return _npc_json_path

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	var path := "res://NPC_and_Opponent_Data/Gym_Challenge_Reception_" + time_of_day + "_" + str(date) + ".json"
	_npc_json_path = path if ResourceLoader.exists(path) else ""
	_create_cash_label()
	_update_cash_label()
	# If arriving from the plaza (not from the hall), flag the audience for partial regen
	if GameState.entering_from != "Gym_Challenge_Hall":
		GameState.progress["gym_challenge_audience_from_plaza"] = true
