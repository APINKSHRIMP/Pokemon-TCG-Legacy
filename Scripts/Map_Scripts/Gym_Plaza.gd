extends BaseMapScene

# ============================================================
# GYM PLAZA — outdoor map
# Structurally similar to Verdant Forest: reuses its tilesets
# and tree-wall art. Connects back to Verdant Forest and inward
# to the Gym Challenge Reception interior.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Plaza.tscn"
const BGM_PATH = "res://Audio/BGM/Gym Leader Challenge Hall (Pokmon Card GB2 - GRs Challenge Cup).ogg"

const DEFAULT_SPAWN_POSITION             = Vector2(1763, 1810)
const SPAWN_FROM_VERDANT_FOREST          = Vector2(1760, 2130)
const SPAWN_FROM_GYM_CHALLENGE_RECEPTION = Vector2(1757, 1219)

# Gym Plaza shares Verdant Forest's tilesets
const TILESET_MORNING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Morning.tres")
const TILESET_AFTERNOON = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Afternoon.tres")
const TILESET_EVENING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Evening.tres")
const TILESET_NIGHT     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Night.tres")

const TREE_HORIZ_MORNING   = preload("res://Image_Assets/Map_Objects/Forest/TreeLineThirdMorning.png")
const TREE_HORIZ_AFTERNOON = preload("res://Image_Assets/Map_Objects/Forest/TreeLineThirdAfternoon.png")
const TREE_HORIZ_EVENING   = preload("res://Image_Assets/Map_Objects/Forest/TreeLineThirdEvening.png")
const TREE_HORIZ_NIGHT     = preload("res://Image_Assets/Map_Objects/Forest/TreeLineThirdNight.png")

const TREE_VERT_MORNING   = preload("res://Image_Assets/Map_Objects/Forest/TreeLineVerticalMorning.png")
const TREE_VERT_AFTERNOON = preload("res://Image_Assets/Map_Objects/Forest/TreeLineVerticalAfternoon.png")
const TREE_VERT_EVENING   = preload("res://Image_Assets/Map_Objects/Forest/TreeLineVerticalEvening.png")
const TREE_VERT_NIGHT     = preload("res://Image_Assets/Map_Objects/Forest/TreeLineVerticalNight.png")

func get_scene_path() -> String:     return SCENE_PATH
func get_bgm_path() -> String:       return BGM_PATH
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_entry_positions() -> Dictionary:
	return {
		"Verdant_Forest":          SPAWN_FROM_VERDANT_FOREST,
		"Gym_Challenge_Reception": SPAWN_FROM_GYM_CHALLENGE_RECEPTION,
	}
func get_map_data_name() -> String: return "Gym_Plaza"

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	set_time_of_day(time_of_day)

func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	match time:
		"Morning":   tileset = TILESET_MORNING
		"Afternoon": tileset = TILESET_AFTERNOON
		"Evening":   tileset = TILESET_EVENING
		"Night":     tileset = TILESET_NIGHT
	_apply_tileset($TILE_MAPS, tileset)

	var horiz_tex: Texture2D
	var vert_tex: Texture2D
	var is_night := time == "Night"
	match time:
		"Morning":   horiz_tex = TREE_HORIZ_MORNING;   vert_tex = TREE_VERT_MORNING
		"Afternoon": horiz_tex = TREE_HORIZ_AFTERNOON;  vert_tex = TREE_VERT_AFTERNOON
		"Evening":   horiz_tex = TREE_HORIZ_EVENING;    vert_tex = TREE_VERT_EVENING
		"Night":     horiz_tex = TREE_HORIZ_NIGHT;      vert_tex = TREE_VERT_NIGHT

	var north = $TREE_WALL_NORTH_GROUP
	north.get_node("Shadow").visible  = not is_night
	north.get_node("Shadow2").visible = not is_night
	for n in ["Tree_wall_north", "Tree_wall_north2", "Tree_wall_north3", "Tree_wall_north4"]:
		north.get_node(n).texture = horiz_tex

	# Gym Plaza has two south tree-wall groups
	for south_path in ["TREE_WALL_SOUTH_GROUP", "TREE_WALL_SOUTH_GROUP2"]:
		var south = get_node(south_path)
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
