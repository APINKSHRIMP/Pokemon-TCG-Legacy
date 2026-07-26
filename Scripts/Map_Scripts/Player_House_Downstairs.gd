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

func _ready() -> void:
	super._ready()
	if GameState.progress.get("show_intro_house_message", false):
		GameState.progress.erase("show_intro_house_message")
		GameState.save_progress()
		MapManager._show_message_with_ok(
			"Home sweet home. Looks like the movers have already moved everything in for me, but I should check upstairs to make sure that everything has been delivered."
		)


func _scene_setup():
	_apply_moving_in_state()

# ISSUE #26 FIX (downstairs): mirrors Player_House_Upstairs._apply_moving_in_state.
# The old _apply_moving_in_visibility() did nothing pre-move-in (early return) and never
# touched collisions, so on game start the post-move-in furniture showed and its collision
# bodies stayed active while the "Moving In" boxes were hidden. Now BOTH the visual tile
# layers AND the collision bodies are driven from moving_in_completed, and the inactive
# collision set is REMOVED (hiding a StaticBody2D doesn't stop it colliding). SceneCache
# re-instantiates the scene fresh on every visit, so queue_free() here is safe.
func _apply_moving_in_state() -> void:
	var completed: bool = GameState.progress.get("moving_in_completed", false)

	# --- Visual tile layers under DOWNSTAIRS ---
	var moving_in_layer := $DOWNSTAIRS.get_node_or_null("Moving In")
	if moving_in_layer != null:
		moving_in_layer.visible = not completed
	var post_move_in_visual := $DOWNSTAIRS.get_node_or_null("Post Move In")
	if post_move_in_visual != null:
		post_move_in_visual.visible = completed

	# --- Collision bodies under "Collision Objects" (remove the inactive set) ---
	var col := get_node_or_null("Collision Objects")
	if col != null:
		var col_moving := col.get_node_or_null("Moving In")
		var col_post := col.get_node_or_null("Post Move In")
		if completed:
			if col_moving != null:
				col_moving.queue_free()
		else:
			if col_post != null:
				col_post.queue_free()

func _on_before_door_transition(body: Node2D, target: String) -> bool:
	if not target.contains("Upstairs") \
			and not GameState.progress.get("player_collected_starter_box", false):
		MapManager._show_message_with_ok("I should check upstairs before heading out.")
		return false
	return true
