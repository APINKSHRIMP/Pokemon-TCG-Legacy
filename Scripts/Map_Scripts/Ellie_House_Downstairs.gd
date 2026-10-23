extends BaseMapScene

## Downstairs in Ellie's house. The cast lives in
## NPC_and_Opponent_Data/Characters/Ellie_House_Downstairs.json.

const SCENE_PATH = "res://Scenes/Map_Scenes/Ellie_House_Downstairs.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME
func get_map_data_name() -> String:   return "Ellie_House_Downstairs"

func _scene_setup():
	_apply_moved_in_state()

# The scene (copied from the player's house) still holds the old "Moving In" layer and
# its box collisions; only the furnished "Post Move In" set is ever shown. The unused
# collision set is REMOVED (hiding a StaticBody2D doesn't stop it colliding).
# SceneCache re-instantiates the scene fresh on every visit, so queue_free() is safe.
func _apply_moved_in_state() -> void:
	var moving_in_layer := $DOWNSTAIRS.get_node_or_null("Moving In")
	if moving_in_layer != null:
		moving_in_layer.visible = false
	var post_move_in_visual := $DOWNSTAIRS.get_node_or_null("Post Move In")
	if post_move_in_visual != null:
		post_move_in_visual.visible = true

	var col := get_node_or_null("Collision Objects")
	if col != null:
		var col_moving := col.get_node_or_null("Moving In")
		if col_moving != null:
			col_moving.queue_free()
