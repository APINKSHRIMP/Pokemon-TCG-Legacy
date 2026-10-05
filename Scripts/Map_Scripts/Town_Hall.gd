extends BaseMapScene

## The Celeste Harbour Town Hall interior. Home of the three Card Elders, who stand in
## front of the three card mats along the top wall, with their spectators gathered
## round. Their days and times are unchanged from when they stood in the harbour plaza:
## gift-giving on day 3 while the queue is too long, battles from day 4. All of that
## lives in NPC_and_Opponent_Data/Characters/TownHall.json.

const SCENE_PATH = "res://Scenes/Map_Scenes/TownHall.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_2
func get_map_data_name() -> String:   return "TownHall"
