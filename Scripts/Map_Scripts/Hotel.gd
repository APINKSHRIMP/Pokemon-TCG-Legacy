extends BaseMapScene

## The Celeste Harbour Hotel interior, reached from the harbour's east side.

const SCENE_PATH = "res://Scenes/Map_Scenes/Hotel.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME_ALT
func get_map_data_name() -> String:   return "Hotel"

# Bedtime: the Hotel stays open but nobody is on the desk, so a sign stands in.
# The zone is the strip in front of the long desk (Collision/Bar spans x 256..400,
# y -51..35). Its text is "Hotel" / "Sign_Desk" in Interactables_Data.json.
const DESK_SIGN_ZONE := Rect2(256, 35, 144, 22)   # TWEAKABLE

func _scene_setup() -> void:
	if GameState.get_time() != "Bedtime":
		return
	var area := Area2D.new()
	area.name = "Interactables"
	area.set_script(load("res://Scripts/Map_Scripts/Interactables_Script.gd"))
	var zone := CollisionShape2D.new()
	zone.name = "Sign_Desk"
	var rect := RectangleShape2D.new()
	rect.size = DESK_SIGN_ZONE.size
	zone.shape = rect
	zone.position = DESK_SIGN_ZONE.get_center()
	area.add_child(zone)
	add_child(area)
