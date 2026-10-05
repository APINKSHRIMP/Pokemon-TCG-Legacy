extends BaseMapScene

const SCENE_PATH    = "res://Scenes/Map_Scenes/Card_Mart.tscn"


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String: return "Card_Mart"

func _scene_setup():
	if GameState.progress.get("player_collected_shop_starter_set", false):
		_remove_starter_set()
	# ISSUE #127: the permanent "Cash: $N" label is gone. Cash now appears as a chip on the
	# message box while you are actually talking to the shopkeeper -- see MapManager.

# ============================================================
# STARTER SET VISUAL
# Called by Shopkeeper_Script after purchase to remove the node
# ============================================================

func _remove_starter_set():
	var starter = $MART.get_node_or_null("Starter_Set")
	if starter != null:
		starter.queue_free()
