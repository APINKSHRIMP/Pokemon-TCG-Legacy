extends BaseMapScene

## The Celeste Harbour Café interior.

const SCENE_PATH = "res://Scenes/Map_Scenes/Cafe.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String:   return "Cafe"
