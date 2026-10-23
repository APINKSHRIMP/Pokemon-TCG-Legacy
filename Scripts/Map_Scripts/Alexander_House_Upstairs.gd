extends BaseMapScene

## Upstairs in Alexander's house. The bed is only flavour text here (Interactables_Data.json);
## sleeping happens at home. The cast lives in
## NPC_and_Opponent_Data/Characters/Alexander_House_Upstairs.json.

const SCENE_PATH = "res://Scenes/Map_Scenes/Alexander_House_Upstairs.tscn"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME
func get_map_data_name() -> String:   return "Alexander_House_Upstairs"

func _scene_setup():
	_apply_moved_in_state()

# The scene (copied from the player's bedroom) still holds the old "Moving In" layer and
# its box collisions; only the furnished "Post Move In" set is ever shown. The unused
# collision set is REMOVED, not hidden: hiding a StaticBody2D via a parent Control does
# not stop it colliding. SceneCache re-instantiates the scene fresh on every visit.
func _apply_moved_in_state() -> void:
	var moving_in_layer := $UPSTAIRS.get_node_or_null("Moving In")
	if moving_in_layer != null:
		moving_in_layer.visible = false
	var post_move_in_visual := $UPSTAIRS.get_node_or_null("Post Move In")
	if post_move_in_visual != null:
		post_move_in_visual.visible = true

	var col := get_node_or_null("Collision Objects")
	if col != null:
		var col_moving := col.get_node_or_null("Moving In")
		if col_moving != null:
			col_moving.queue_free()
