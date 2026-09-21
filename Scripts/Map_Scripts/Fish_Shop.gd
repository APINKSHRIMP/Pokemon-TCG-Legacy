extends BaseMapScene

## The Fish Shop interior, off the Celeste Harbour road. A mart-shaped room: a counter
## with a shopkeeper behind it and two aquariums along the wall (their fish come from
## Pokemon/Spawns/Fish_Shop.json -- see the fish_tank spawn template).
##
## Who is behind the counter alternates day by day between Olly and Alexander. That is
## not done here: both are in NPC_and_Opponent_Data/Characters/Fish_Shop.json, one on the
## calendar's day 1 and one on day 2, and the file's two-day loop repeats them for ever.

const SCENE_PATH = "res://Scenes/Map_Scenes/Fish_Shop.tscn"

## Just inside the door at the bottom of the room, facing up -- the same relationship the
## other two marts have between their door area and their spawn.
const SPAWN_FROM_CELESTE_HARBOUR = Vector2(223, 277)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_FISH_SHOP
func get_default_spawn() -> Vector2:  return SPAWN_FROM_CELESTE_HARBOUR
func get_entry_positions() -> Dictionary:
	return {"Celeste_Harbour": SPAWN_FROM_CELESTE_HARBOUR}
func get_map_data_name() -> String: return "Fish_Shop"
