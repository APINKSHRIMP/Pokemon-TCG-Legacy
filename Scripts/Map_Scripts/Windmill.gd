extends BaseMapScene

# ============================================================
# WINDMILL — secret interior
# ============================================================
# Reached through the hidden entrance in Verdant Forest. A
# single-room interior holding one secret opponent, Mewtwo.
#
# Data lives in a single flat file (Windmill.json) rather than
# the usual per-date/per-time set, because the windmill's one
# opponent is meant to be there whenever the player finds the
# way in. _scene_setup still checks for a date/time variant
# first, so time-of-day files can be dropped in later without
# touching this script.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Windmill.tscn"


const SPAWN_FROM_VERDANT_FOREST = Vector2(208, 172)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_CALM_BATTLE_2
func get_default_spawn() -> Vector2:  return SPAWN_FROM_VERDANT_FOREST
func get_entry_positions() -> Dictionary:
	return {"Verdant_Forest": SPAWN_FROM_VERDANT_FOREST}

# Both getters point at the same file — it carries an "npcs" and an
# "opponents" block, the same shape every other area data file uses.
func get_map_data_name() -> String: return "Windmill"

func _scene_setup():
	var time_of_day: String = GameState.get_time()
