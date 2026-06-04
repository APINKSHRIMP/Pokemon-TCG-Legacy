extends BaseMapScene

# ============================================================
# GYM CHALLENGE HALL — interior
# Reached from the Gym Challenge Reception. The base class
# auto-creates the OPPONENTS container at runtime since no
# such node exists in the .tscn.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Hall.tscn"
const BGM_PATH   = "res://Audio/BGM/Gym Leader Challenge Hall (Pokmon Card GB2 - GRs Challenge Cup).ogg"

const SPAWN_FROM_GYM_CHALLENGE_RECEPTION = Vector2(361, 467)

var _npc_json_path: String = ""

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return BGM_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_GYM_CHALLENGE_RECEPTION
func get_entry_positions() -> Dictionary:
	return {"Gym_Challenge_Reception": SPAWN_FROM_GYM_CHALLENGE_RECEPTION}
func get_opponent_json_path() -> String: return _npc_json_path
func get_npc_json_path() -> String:      return _npc_json_path

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	var path := "res://NPC_and_Opponent_Data/Gym_Challenge_Hall_" + time_of_day + "_" + str(date) + ".json"
	_npc_json_path = path if ResourceLoader.exists(path) else ""
