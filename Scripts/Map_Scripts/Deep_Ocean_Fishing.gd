extends BaseMapScene

## Deep Ocean Fishing -- the open-sea fishing area off Celeste Harbour. It is drawn
## with the harbour's own tileset and graded by time of day like every outdoor map
## (uses_time_of_day). What bites where comes from
## NPC_and_Opponent_Data/Pokemon/Spawns/DeepOceanFishing.json (fishing_spot points);
## the casting rectangles are the FishingAreas children in the scene.

const SCENE_PATH = "res://Scenes/Map_Scenes/DeepOceanFishing.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SEA_SOUNDS
func get_map_data_name() -> String:   return "DeepOceanFishing"
func uses_time_of_day() -> bool:      return true

