extends BaseMapScene

## FISH's basement, down the stairs from the shop floor (Fish_Shop.gd), open once Verdant
## Forest is -- the stairs' DownstairsBlock upstairs is what keeps the player out before
## then. Its tanks hold the forest's fish.
##
## FishShopFloor keeps the Interior_<N>s the player has reached: Interior_0 until 50 fish
## have been sent, then Interior_50 INSTEAD of it (replace_at in Fish_Shop_Tanks.json),
## and fills the tanks. The tanks outside both interiors are permanent.

const SCENE_PATH = "res://Scenes/Map_Scenes/Fish_Shop_Downstairs.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_FISH_SHOP
func get_map_data_name() -> String: return "Fish_Shop_Downstairs"


func _scene_setup() -> void:
	FishShopFloor.setup(self, get_map_data_name())
