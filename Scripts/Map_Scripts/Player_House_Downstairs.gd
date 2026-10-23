extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Downstairs.tscn"

# ── The arrival night: a note through the door — TWEAKABLE ──────────────────
const NOTE_FOUND_TEXT := "Huh, a note was put through the door"
const NOTE_AFTER_TEXT := "I'll call mum tomorrow..."
const NOTE_LOOK_BACK_DELAY := 0.5   # after the fade in, before the player turns back to the door

# ── Morning 2: Ellie rings about breakfast at Café Mieux — TWEAKABLE ────────
# Only for saves that woke up on day 1 ("new" / "rules"; CafeBreakfastCutscene.call_due).
# It rings once the player has walked this far (world px) from where they came in, so
# not the instant they arrive downstairs.
const CAFE_CALL_ID := "cafe_call_ellie"
const CAFE_CALL_TRIGGER_DISTANCE := 32.0

var _cafe_call_from: Vector2 = Vector2.INF


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME

func _ready() -> void:
	super._ready()
	if GameState.progress.get("show_intro_house_message", false):
		GameState.progress.erase("show_intro_house_message")
		GameState.save_progress()
		_play_note_through_door()
	elif CafeBreakfastCutscene.call_due():
		_cafe_call_from = _player.global_position


func _process(_delta: float) -> void:
	if _cafe_call_from == Vector2.INF:
		return
	if _player.global_position.distance_to(_cafe_call_from) >= CAFE_CALL_TRIGGER_DISTANCE:
		_cafe_call_from = Vector2.INF
		_play_cafe_call()


## Ellie's call. The player stops where they are until it hangs up; only then is it
## marked as taken, so a quit mid-call rings again next time.
func _play_cafe_call() -> void:
	_player.lock_movement()
	MapManager.cutscene_active = true   # keeps the menu shut for the call
	var call := PhoneCall.play_from_data(self, CAFE_CALL_ID)
	if call != null and not call.is_finished():
		await call.finished
	if not is_inside_tree():
		return
	GameState.set_flag(CafeBreakfastCutscene.CALL_DONE_FLAG)
	MapManager.cutscene_active = false
	_player.unlock_movement()


## The taxi intro walks the player in through the front door. A beat, they look back
## down at the door, spot the note, look up and read it. Then the house is theirs.
func _play_note_through_door() -> void:
	_player.lock_movement()
	await get_tree().create_timer(NOTE_LOOK_BACK_DELAY).timeout
	if not is_inside_tree():
		return
	_player.set_direction("down")
	MapManager.show_message_then(NOTE_FOUND_TEXT, _read_note)


func _read_note() -> void:
	# MapManager's OK runs a pending callback INSTEAD of dismissing the panel, so the box
	# is closed by hand -- and that hands movement back, so it is taken away again.
	MapManager._hide_message()
	_player.lock_movement()
	_player.set_direction("up")
	var note := NoteOverlay.show_on(_ui_layer)
	await note.closed
	# Dismissing this hands movement back (MapManager._hide_message).
	MapManager._show_message_with_ok(NOTE_AFTER_TEXT)


func _scene_setup():
	_apply_moved_in_state()

# The scene still holds the old "Moving In" layer and its box collisions; the player
# lives here already, so only the furnished "Post Move In" set is ever shown. The
# unused collision set is REMOVED (hiding a StaticBody2D doesn't stop it colliding).
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

func _on_before_door_transition(_body: Node2D, target: String) -> bool:
	# The arrival night: the player has only just got home, and the bed is the way on.
	if not target.contains("Upstairs") and GameState.is_arrival_night():
		MapManager._show_message_with_ok(GameState.ARRIVAL_DOOR_TEXT)
		return false
	return true
