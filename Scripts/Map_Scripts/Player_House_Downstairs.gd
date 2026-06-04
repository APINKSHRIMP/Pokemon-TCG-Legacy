extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Downstairs.tscn"
const BGM_PATH   = "res://Audio/BGM/Player Home (003 File Select PMD Blue Rescue Team OST).ogg"

const SPAWN_FROM_CELESTE_HARBOUR       = Vector2(200, 205)
const SPAWN_FROM_PLAYER_HOUSE_UPSTAIRS = Vector2(365, 10)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return BGM_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_CELESTE_HARBOUR
func get_entry_positions() -> Dictionary:
	return {
		"Celeste_Harbour":       SPAWN_FROM_CELESTE_HARBOUR,
		"Player_House_Upstairs": SPAWN_FROM_PLAYER_HOUSE_UPSTAIRS,
	}

func _scene_setup():
	_apply_moving_in_visibility($DOWNSTAIRS)

func _on_before_door_transition(body: Node2D, target: String) -> bool:
	if not target.contains("Upstairs") \
			and not GameState.progress.get("player_collected_starter_box", false):
		MapManager._show_message_with_ok("I should check upstairs before heading out.")
		return false
	return true
