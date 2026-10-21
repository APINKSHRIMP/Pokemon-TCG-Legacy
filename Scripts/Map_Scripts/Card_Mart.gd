extends BaseMapScene

const SCENE_PATH    = "res://Scenes/Map_Scenes/Card_Mart.tscn"


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String: return "Card_Mart"

# ISSUE #127: cash is shown on the message box chip row while talking to the shopkeeper.
