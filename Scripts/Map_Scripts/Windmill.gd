extends BaseMapScene

# ============================================================
# WINDMILL — secret interior
# ============================================================
# Reached through the hidden entrance in Verdant Forest. A single-room interior
# holding one secret opponent, Mewtwo, who is there whenever the player finds the
# way in (NPC_and_Opponent_Data/Characters/Windmill.json).
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Windmill.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_CALM_BATTLE_2
func get_map_data_name() -> String: return "Windmill"
