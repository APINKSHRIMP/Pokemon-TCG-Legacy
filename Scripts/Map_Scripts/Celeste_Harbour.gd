extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const BGM_PATH = "res://Audio/BGM/Celeste_Harbour_BGM.ogg"

const TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas.tres")
const TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Evening.tres")
const TILESET_NIGHT   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Night.tres")

const DEFAULT_SPAWN_POSITION         = Vector2(-600, 1500)
const SPAWN_FROM_VERDANT_FOREST      = Vector2(918, 900)
const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(-597, 1473)
const SPAWN_FROM_CARD_MART           = Vector2(431, 1474)

var _npc_json_path: String = ""

func get_scene_path() -> String:    return SCENE_PATH
func get_bgm_path() -> String:      return BGM_PATH
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_entry_positions() -> Dictionary:
	return {
		"Verdant_Forest":           SPAWN_FROM_VERDANT_FOREST,
		"Player_House_Downstairs":  SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS,
		"Card_Mart":                SPAWN_FROM_CARD_MART,
	}
func get_opponent_json_path() -> String: return _npc_json_path
func get_npc_json_path() -> String:      return _npc_json_path

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	_npc_json_path = "res://NPC_and_Opponent_Data/Celeste_Harbour_" + str(date) + "_" + time_of_day + ".json"
	set_time_of_day(time_of_day)
	apply_date_events(date)

func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	match time:
		"Day":
			tileset = TILESET_DAY
			$LIGHTS.queue_free()
		"Evening":
			tileset = TILESET_EVENING
			$LIGHTS.queue_free()
		"Night":
			tileset = TILESET_NIGHT
			$LIGHTS.visible = true
			$"TILE_MAPS/OBJECTS/CAR PARK CARS".visible = false
	_apply_tileset($TILE_MAPS, tileset)

func apply_date_events(date: int) -> void:
	if date == 1:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = true
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = false
		$"Collision Objects/BLOCKS/BEACH CONES".queue_free()
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible = false

	if date == 2:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible = false

	if date <= 2:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = false
		$"Collision Objects/BLOCKS/STATION GATE".queue_free()
		$"TILE_MAPS/JETTY2/SSANNE".visible = true

	if date == 3:
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible = true
	else:
		$"TILE_MAPS/JETTY2/SSANNE".visible = false
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible = false

	if date < 4:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = false
		$"Collision Objects/BLOCKS/FOREST GATE".queue_free()

	if date == 4:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible = false

	if date == 5:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible = false
