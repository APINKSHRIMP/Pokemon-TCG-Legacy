extends BaseMapScene

## The Celeste Harbour Train Station interior. The street door leads back to the
## harbour. The two platform doors are the endgame trains -- Platform 1 to Aurum Town,
## Platform 2 to the third town. Their target scenes do not exist yet, so
## BaseMapScene._on_door_entered leaves them inert until those maps are built.

const SCENE_PATH = "res://Scenes/Map_Scenes/TrainStation.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String:   return "TrainStation"
