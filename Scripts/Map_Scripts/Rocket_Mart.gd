extends BaseMapScene

## The Rocket Mart interior, off Verdant Forest. Its one shopkeeper sells the special
## packs (shop_id "rocket_mart"); see NPC_and_Opponent_Data/Characters/Rocket_Mart.json.

const SCENE_PATH = "res://Scenes/Map_Scenes/Rocket_Mart.tscn"


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String: return "Rocket_Mart"
