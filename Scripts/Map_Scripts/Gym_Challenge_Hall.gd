extends BaseMapScene

# ============================================================
# GYM CHALLENGE HALL — interior
# Reached from the Gym Challenge Reception. The base class
# auto-creates the OPPONENTS container at runtime since no
# such node exists in the .tscn.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Hall.tscn"

const SPAWN_FROM_GYM_CHALLENGE_RECEPTION = Vector2(361, 467)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_GYM_CHALLENGE_HALL
func get_default_spawn() -> Vector2:  return SPAWN_FROM_GYM_CHALLENGE_RECEPTION
func get_entry_positions() -> Dictionary:
	return {"Gym_Challenge_Reception": SPAWN_FROM_GYM_CHALLENGE_RECEPTION}
func get_map_data_name() -> String: return "Gym_Challenge_Hall"

func _ready():
	super._ready()
	for entry in GymChallengeAudienceManager.get_audience_npc_entries():
		MapManager.spawn_npc_entry(entry)

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	var from_plaza: bool = GameState.progress.get("gym_challenge_audience_from_plaza", false)
	GameState.progress["gym_challenge_audience_from_plaza"] = false
	GymChallengeAudienceManager.update_audience_state(
		date, time_of_day, from_plaza, GameState.returning_from_battle
	)
