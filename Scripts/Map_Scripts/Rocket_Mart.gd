extends BaseMapScene

const SCENE_PATH    = "res://Scenes/Map_Scenes/Rocket_Mart.tscn"

const SPAWN_FROM_VERDANT_FOREST = Vector2(208, 172)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_default_spawn() -> Vector2:  return SPAWN_FROM_VERDANT_FOREST
func get_entry_positions() -> Dictionary:
	return {"Verdant_Forest": SPAWN_FROM_VERDANT_FOREST}
func get_map_data_name() -> String: return "Rocket_Mart"

func _scene_setup():
	if GameState.progress.get("player_collected_shop_starter_set", false):
		_remove_starter_set()
	# ISSUE #127: cash is shown on the message box chip row while talking to the shopkeeper.

func _remove_starter_set():
	var starter = $MART.get_node_or_null("Starter_Set")
	if starter != null:
		starter.queue_free()
