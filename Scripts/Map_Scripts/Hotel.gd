extends BaseMapScene

## The Celeste Harbour Hotel interior, reached from the harbour's east side.

const SCENE_PATH = "res://Scenes/Map_Scenes/Hotel.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_HOTEL
func get_map_data_name() -> String:   return "Hotel"
