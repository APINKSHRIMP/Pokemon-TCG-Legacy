extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Verdant_Forest.tscn"
const BGM_PATH = "res://Audio/BGM/Verdant_Forest_BGM.ogg"

const DEFAULT_SPAWN_POSITION    = Vector2(1770, 1850)
const SPAWN_FROM_CELESTE_HARBOUR = Vector2(1775, 1909)
const SPAWN_FROM_GYM_PLAZA       = Vector2(1773, -280)
const SPAWN_FROM_ROCKET_MART     = Vector2(278, 1064)

const TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest.tres")
const TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Evening.tres")
const TILESET_NIGHT   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Night.tres")

const TRACKS_TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas.tres")
const TRACKS_TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Evening.tres")
const TRACKS_TILESET_NIGHT   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Night.tres")

const TREE_HORIZ_DAY     = preload("res://Image_Assets/Map_Objects/TreeLineThird.png")
const TREE_HORIZ_EVENING = preload("res://Image_Assets/Map_Objects/TreeLineThirdEvening.png")
const TREE_HORIZ_NIGHT   = preload("res://Image_Assets/Map_Objects/TreeLineThirdNight.png")

const TREE_VERT_DAY     = preload("res://Image_Assets/Map_Objects/TreeLineVertical.png")
const TREE_VERT_EVENING = preload("res://Image_Assets/Map_Objects/TreeLineVerticalEvening.png")
const TREE_VERT_NIGHT   = preload("res://Image_Assets/Map_Objects/TreeLineVerticalNight.png")

var _npc_json_path: String = ""

func get_scene_path() -> String:     return SCENE_PATH
func get_bgm_path() -> String:       return BGM_PATH
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_entry_positions() -> Dictionary:
	return {
		"Celeste_Harbour": SPAWN_FROM_CELESTE_HARBOUR,
		"Rocket_Mart":     SPAWN_FROM_ROCKET_MART,
		"Gym_Plaza":       SPAWN_FROM_GYM_PLAZA,
	}
func get_opponent_json_path() -> String: return _npc_json_path
func get_npc_json_path() -> String:      return _npc_json_path

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	_npc_json_path = "res://NPC_and_Opponent_Data/Verdant_Forest_" + str(date) + "_" + time_of_day + ".json"
	if not ResourceLoader.exists(_npc_json_path):
		_npc_json_path = "res://NPC_and_Opponent_Data/Verdant_Forest_4_Day.json"
	set_time_of_day(time_of_day)

func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	var tracks_tileset: TileSet
	match time:
		"Day":
			tileset = TILESET_DAY
			tracks_tileset = TRACKS_TILESET_DAY
		"Evening":
			tileset = TILESET_EVENING
			tracks_tileset = TRACKS_TILESET_EVENING
		"Night":
			tileset = TILESET_NIGHT
			tracks_tileset = TRACKS_TILESET_NIGHT
	_apply_tileset($TILE_MAPS, tileset)
	var train_tracks = $TILE_MAPS.find_child("TRAIN TRACKS")
	if train_tracks:
		_apply_tileset(train_tracks, tracks_tileset)

	var horiz_tex: Texture2D
	var vert_tex: Texture2D
	var is_night := time == "Night"
	match time:
		"Day":     horiz_tex = TREE_HORIZ_DAY;     vert_tex = TREE_VERT_DAY
		"Evening": horiz_tex = TREE_HORIZ_EVENING;  vert_tex = TREE_VERT_EVENING
		"Night":   horiz_tex = TREE_HORIZ_NIGHT;    vert_tex = TREE_VERT_NIGHT

	var north = $TREE_WALL_NORTH_GROUP
	north.get_node("Shadow").visible  = not is_night
	north.get_node("Shadow2").visible = not is_night
	for n in ["Tree_wall_north", "Tree_wall_north2", "Tree_wall_north3", "Tree_wall_north4"]:
		north.get_node(n).texture = horiz_tex

	var south = $TREE_WALL_SOUTH_GROUP
	south.get_node("Shadow").visible  = not is_night
	south.get_node("Shadow2").visible = not is_night
	for n in ["Tree_wall_South", "Tree_wall_South2", "Tree_wall_South3", "Tree_wall_South4"]:
		south.get_node(n).texture = horiz_tex

	var west = $TREE_WALL_WEST_GROUP
	west.get_node("SHADOW_VERTICAL2").visible = not is_night
	west.get_node("TREE_WALL_WEST").texture = vert_tex

	var east = $TREE_WALL_EAST_GROUP
	east.get_node("SHADOW_VERTICAL").visible = not is_night
	for n in ["TREE_WALL_EAST", "TREE_WALL_EAST2"]:
		east.get_node(n).texture = vert_tex

	if not is_night:
		for lamp in find_children("ForestLamp*"):
			lamp.get_node("PointLight2D2").visible = false

# Overrides base to skip the TRAIN TRACKS sub-tree (uses a different tileset)
func _apply_tileset(node: Node, tileset: TileSet) -> void:
	if node is TileMapLayer:
		node.tile_set = tileset
	for child in node.get_children():
		if child.name == "TRAIN TRACKS":
			continue
		_apply_tileset(child, tileset)
