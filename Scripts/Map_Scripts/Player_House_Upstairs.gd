extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

# The bedroom. The player has always lived here, so the house is fully moved in; the
# only thing up here that does anything is the bed. What it asks tonight (and what
# the arrival night wakes up to) lives in GameState's ARRIVAL NIGHT section.

var _player_in_bed_area: bool = true  # starts true to suppress any load-time trigger
const SLEEP_FADE_DURATION := 2.5
# ISSUE #457: what the bed says before Night, by time slot (Evening is also the fallback).
const BED_TOO_EARLY_TEXT := {
	"Morning":   "I've only just woken up, I'm not getting back in bed now!",
	"Afternoon": "I'd love an afternoon nap... but I'd end up sleeping for hours...",
	"Evening":   "Nothing wrong with an early night but it's far too early to go to sleep now!",
}
const NEXT_MORNING_FONT := "res://UI_Themes/ChakraPetch-Bold.ttf"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME

func _scene_setup():
	_apply_moved_in_state()

	var interactables := $Interactables as Area2D
	interactables.collision_mask = 2
	interactables.monitoring     = true
	interactables.monitorable    = true
	interactables.body_entered.connect(_on_bed_body_entered)
	interactables.body_exited.connect(_on_bed_body_exited)
	_init_bed_overlap_state()

# The scene still holds the old "Moving In" layer and its box collisions; the player
# lives here already, so only the furnished "Post Move In" set is ever shown. The
# unused collision set is REMOVED, not hidden: hiding a StaticBody2D via a parent
# Control does not stop it colliding. SceneCache re-instantiates the scene fresh on
# every visit, so queue_free() here is safe.
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

func _init_bed_overlap_state() -> void:
	# Wait a few physics frames for overlap detection to settle, then check
	# whether the player is actually inside. If not, clear the suppression flag
	# so normal entry works. If they are inside, they must exit and re-enter.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var player_inside := false
	for body in ($Interactables as Area2D).get_overlapping_bodies():
		if body.is_in_group("player"):
			player_inside = true
			break
	if not player_inside:
		_player_in_bed_area = false

func _on_bed_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_bed_area = false

func _on_bed_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _player_in_bed_area:
		return
	if MapManager.message_panel != null and MapManager.message_panel.visible:
		return
	if GameState.is_night_time():
		MapManager.show_interactable_confirm(GameState.sleep_prompt_text(), _do_sleep)
	else:
		MapManager.show_interactable_message(BED_TOO_EARLY_TEXT.get(GameState.get_time(), BED_TOO_EARLY_TEXT["Evening"]))

func _do_sleep() -> void:
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()
	var scene_path := get_scene_path()
	GameState.save_menu_return_state(scene_path, _player.position, "left")
	GameState.sleep_until_next_day()
	GameState.sleep_wakeup_fade = true
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.BLACK, SLEEP_FADE_DURATION)
	tween.tween_callback(_show_next_morning_label.bind(scene_path))

func _show_next_morning_label(scene_path: String) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var label := Label.new()
	# The arrival night of "I know the rules a bit" sleeps in to the afternoon.
	label.text = "The next afternoon..." if GameState.get_time() == "Afternoon" else "The next morning..."
	label.add_theme_font_override("font", load(NEXT_MORNING_FONT))
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = vp_size
	label.position = Vector2.ZERO
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ui_layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 0.5)
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.5)
	tween.tween_callback(func(): SceneCache.change_scene(scene_path))
