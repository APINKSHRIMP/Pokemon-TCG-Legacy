extends BaseMapScene

## Deep Ocean Fishing -- the open-sea fishing area off Celeste Harbour. It is drawn
## with the harbour's own tilesets, so it swaps them by time of day the same way
## Celeste_Harbour.set_time_of_day() does. What bites where comes from
## NPC_and_Opponent_Data/Pokemon/Spawns/DeepOceanFishing.json (fishing_spot points);
## the casting rectangles are the FishingAreas children in the scene.

const SCENE_PATH = "res://Scenes/Map_Scenes/DeepOceanFishing.tscn"

const TILESET_MORNING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Morning.tres")
const TILESET_AFTERNOON = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Afternoon.tres")
const TILESET_EVENING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Evening.tres")
const TILESET_NIGHT     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Night.tres")

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SEA_SOUNDS
func get_map_data_name() -> String:   return "DeepOceanFishing"

func _scene_setup():
	var tileset: TileSet
	match GameState.get_time():
		"Morning":   tileset = TILESET_MORNING
		"Afternoon": tileset = TILESET_AFTERNOON
		"Evening":   tileset = TILESET_EVENING
		"Night":     tileset = TILESET_NIGHT
	if tileset != null:
		_apply_tileset($Tile_Map, tileset)
		_apply_tileset($EMPTY_Tile_GROUP, tileset)
