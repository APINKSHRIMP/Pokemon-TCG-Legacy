extends BaseMapScene

const SCENE_PATH    = "res://Scenes/Map_Scenes/Rocket_Mart.tscn"
const NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Rocket_Mart_NPCs.json"

const SPAWN_FROM_VERDANT_FOREST = Vector2(208, 172)

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return "res://Audio/BGM/Shop1.ogg"
func get_default_spawn() -> Vector2:  return SPAWN_FROM_VERDANT_FOREST
func get_entry_positions() -> Dictionary:
	return {"Verdant_Forest": SPAWN_FROM_VERDANT_FOREST}
func get_npc_json_path() -> String:   return NPC_JSON_PATH

func _scene_setup():
	if GameState.progress.get("player_collected_shop_starter_set", false):
		_remove_starter_set()
	_create_cash_label()
	_update_cash_label()
	_apply_moving_in_visibility($DOWNSTAIRS)

func _remove_starter_set():
	var starter = $MART.get_node_or_null("Starter_Set")
	if starter != null:
		starter.queue_free()
