extends BaseMapScene

## Upstairs in the Celeste Harbour Town Hall. Its stairs from the ground floor stay
## roped off until the Gym Challenge is complete (BaseMapScene._locked_door_text). The
## cast lives in NPC_and_Opponent_Data/Characters/TownHall_Upstairs.json.

const SCENE_PATH = "res://Scenes/Map_Scenes/TownHall_Upstairs.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_2
func get_map_data_name() -> String:   return "TownHall_Upstairs"
