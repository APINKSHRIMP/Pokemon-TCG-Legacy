extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Verdant_Forest.tscn"

const DEFAULT_SPAWN_POSITION    = Vector2(1770, 1850)

func get_scene_path() -> String:     return SCENE_PATH
func get_bgm_path() -> String:       return SoundManagerScript.BGM_VERDANT_FOREST
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_map_data_name() -> String: return "Verdant_Forest"
func uses_time_of_day() -> bool: return true

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	set_time_of_day(time_of_day)

# Colours come from the time-of-day grade (BaseMapScene); this only handles what the time
# switches on or off.
func set_time_of_day(time: String) -> void:
	var is_night := time == "Night"

	var north1 = $TREE_WALL_NORTH/TREE_WALL_NORTH_GROUP
	north1.get_node("Shadow").visible  = not is_night
	north1.get_node("Shadow2").visible = not is_night

	var north2 = $TREE_WALL_NORTH/TREE_WALL_NORTH_GROUP2
	north2.get_node("Shadow").visible  = not is_night
	north2.get_node("Shadow2").visible = not is_night

	var south = $TREE_WALL_SOUTH_GROUP
	south.get_node("Shadow").visible  = not is_night
	south.get_node("Shadow2").visible = not is_night

	var west = $TREE_WALL_WEST_GROUP
	west.get_node("SHADOW_VERTICAL2").visible = not is_night

	var east = $TREE_WALL_EAST_GROUP
	east.get_node("SHADOW_VERTICAL").visible = not is_night

	# Lamps come on at dusk; Time_Of_Day_Grade.LIGHT_ENERGY runs them dimmer at Evening.
	if not (is_night or time == "Evening"):
		for lamp in find_children("ForestLamp*"):
			lamp.get_node("PointLight2D2").visible = false

