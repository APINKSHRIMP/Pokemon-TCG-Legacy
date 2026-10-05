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

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_CALM_BATTLE_2

# Both getters point at the same file — it carries an "npcs" and an
# "opponents" block, the same shape every other area data file uses.
func get_map_data_name() -> String: return "Windmill"

func _scene_setup():
	var time_of_day: String = GameState.get_time()
