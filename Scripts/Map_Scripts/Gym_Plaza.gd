extends BaseMapScene

# ============================================================
# GYM PLAZA — outdoor map
# Structurally similar to Verdant Forest: reuses its tilesets
# and tree-wall art. Connects back to Verdant Forest and inward
# to the Gym Challenge Reception interior.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Plaza.tscn"

const DEFAULT_SPAWN_POSITION             = Vector2(1763, 1810)

func get_scene_path() -> String:     return SCENE_PATH
## ISSUE #210: the plaza and the hall behind it are one place, so they share a
## track. BGM_STARTING_MENU (the PTCG main-menu theme) moved to the boot splash and
## the first-launch setup
## screen, which is the only other place a menu theme belongs.
func get_bgm_path() -> String:       return SoundManagerScript.BGM_GYM_CHALLENGE_HALL
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_map_data_name() -> String: return "Gym_Plaza"
func uses_time_of_day() -> bool: return true

func _scene_setup():
	var time_of_day: String = GameState.get_time()
	set_time_of_day(time_of_day)

# Colours come from the time-of-day grade (BaseMapScene); this only handles what the time
# switches on or off.
func set_time_of_day(time: String) -> void:
	var is_night := GameState.is_night_time(time)

	var north = $TREE_WALL_NORTH_GROUP
	north.get_node("Shadow").visible  = not is_night
	north.get_node("Shadow2").visible = not is_night

	# Gym Plaza has two south tree-wall groups
	for south_path in ["TREE_WALL_SOUTH_GROUP", "TREE_WALL_SOUTH_GROUP2"]:
		var south = get_node(south_path)
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
