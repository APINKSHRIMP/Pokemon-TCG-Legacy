extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"
const BGM_PATH   = "res://Audio/BGM/Player Home (003 File Select PMD Blue Rescue Team OST).ogg"

const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(50, 20)

const STARTER_BOX_CARDS = "base1-47,base1-47,base1-47,base1-47, base1-27,base1-27, base1-52,base1-52,base1-52,base1-52, base1-61,base1-61,base1-61,base1-61, base1-65,base1-65,base1-65,base1-65, base1-67,base1-67,base1-67,base1-67, base1-94,base1-94, base1-90,base1-90"

const NOTE_TEXT = "\"Hi Sweetie, we found these tucked away in a cupboard when we were packing our things up. They must have been your's from when you were just a kid! Oh my - how time flies. Everyone in the harbour seems to play the game too but me and your father never got the hang of it so you might as well keep hold of them to see if you're still any good. Don't forget to catch the train and come visit us at our new place as soon as you can. Love you lots, See you soon x\""

var _box_sparkle: CPUParticles2D = null
var _box_triggered: bool = false
var _player_in_bed_area: bool = true  # starts true to suppress any load-time trigger
const SLEEP_FADE_DURATION := 2.5
const BED_TOO_EARLY_TEXT := "Nothing wrong with an early night but it's far too early to go to sleep now!"
const BED_SLEEP_PROMPT_DEFAULT := "Should I go to sleep now?"
const BED_SLEEP_PROMPT_NIGHT_EXTRAS: Dictionary = {
	1: "I'll finish unpacking and moving in everything tomorrow before I head out. The beach should be open too.",
	2: "The SS Anne docks tomorrow. I've never seen it with my own eyes!",
	3: "Hopefully the forest will be open again in the morning.",
	7: "The Gym Hero Challenge registration opens in the morning.",
	8: "The Gym Hero Challenge starts tomorrow!"
}
const NEXT_MORNING_FONT := "res://UI_Themes/kenvector_future.ttf"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return BGM_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS
func get_entry_positions() -> Dictionary:
	return {"Player_House_Downstairs": SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS}

func _scene_setup():
	_apply_moving_in_visibility($UPSTAIRS)
	if GameState.progress.get("player_collected_starter_box", false):
		$Interactables/Starter_Box.visible = false
	else:
		_start_box_sparkle()
		var box_area := $Interactables/Starter_Box/box_area
		box_area.collision_mask = 2
		box_area.monitoring     = true
		box_area.monitorable    = true
		box_area.body_entered.connect(_on_box_body_entered)

	var interactables := $Interactables as Area2D
	interactables.collision_mask = 2
	interactables.monitoring     = true
	interactables.monitorable    = true
	interactables.body_entered.connect(_on_bed_body_entered)
	interactables.body_exited.connect(_on_bed_body_exited)
	_init_bed_overlap_state()

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

func _start_box_sparkle() -> void:
	_box_sparkle = CPUParticles2D.new()
	add_child(_box_sparkle)

	var box := $Interactables/Starter_Box
	var box_size := Vector2(box.offset_right - box.offset_left, box.offset_bottom - box.offset_top)
	var box_center := Vector2(box.offset_left, box.offset_top) + box_size / 2.0

	_box_sparkle.global_position       = box_center
	_box_sparkle.z_index               = 10
	_box_sparkle.amount                = 30
	_box_sparkle.lifetime              = 1.2
	_box_sparkle.one_shot              = false
	_box_sparkle.explosiveness         = 0.0
	_box_sparkle.emitting              = true
	_box_sparkle.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_box_sparkle.emission_rect_extents = box_size / 2.0
	_box_sparkle.direction             = Vector2(0, 0)
	_box_sparkle.initial_velocity_min  = 0.0
	_box_sparkle.initial_velocity_max  = 0.0
	_box_sparkle.gravity               = Vector2(0, 0)
	_box_sparkle.scale_amount_min      = 0.6
	_box_sparkle.scale_amount_max      = 1.4

	var blue := Color(0.3, 0.55, 1.0)
	var bright := blue.lightened(0.8)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, blue)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(blue.r, blue.g, blue.b, 0.0))
	_box_sparkle.color_ramp = gradient

func _on_box_body_entered(body: Node2D) -> void:
	if _box_triggered:
		return
	if not body.is_in_group("player"):
		return
	if GameState.progress.get("player_collected_starter_box", false):
		return
	_box_triggered = true
	MapManager.show_message_then(
		"Huh? A box of Pokemon Cards have been left here? I definitely didn't bring these with me...... Oh There's a note on top....",
		_on_box_step2
	)

func _on_box_step2() -> void:
	MapManager.show_message_then(NOTE_TEXT, _on_box_step3)

func _get_sleep_prompt() -> String:
	var day := GameState.get_date()
	var extra: String = BED_SLEEP_PROMPT_NIGHT_EXTRAS.get(day, "")
	if extra != "":
		return BED_SLEEP_PROMPT_DEFAULT + " " + extra
	return BED_SLEEP_PROMPT_DEFAULT

func _on_bed_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _player_in_bed_area:
		return
	if MapManager.message_panel != null and MapManager.message_panel.visible:
		return
	if GameState.get_time() == "Night":
		MapManager.show_interactable_confirm(_get_sleep_prompt(), _do_sleep)
	else:
		MapManager.show_interactable_message(BED_TOO_EARLY_TEXT)

func _do_sleep() -> void:
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()
	var scene_path := get_scene_path()
	GameState.save_menu_return_state(scene_path, _player.position, "left")
	if GameState.get_date() == 1:
		GameState.progress["moving_in_completed"] = true
	GameState.advance_time("Morning")
	GameState.sleep_wakeup_fade = true
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.BLACK, SLEEP_FADE_DURATION)
	tween.tween_callback(_show_next_morning_label.bind(scene_path))

func _show_next_morning_label(scene_path: String) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var label := Label.new()
	label.text = "The next morning..."
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

func _on_box_step3() -> void:
	if _box_sparkle != null:
		_box_sparkle.emitting = false
		_box_sparkle.queue_free()
		_box_sparkle = null
	$Interactables/Starter_Box.visible = false
	GameState.progress["player_collected_starter_box"] = true
	if not GameState.progress.has("packs_unlocked"):
		GameState.progress["packs_unlocked"] = []
	if "base1" not in GameState.progress["packs_unlocked"]:
		GameState.progress["packs_unlocked"].append("base1")
	GameState.save_progress()
	GameState.give_cards(STARTER_BOX_CARDS)
	MapManager._show_message_with_ok("Pokemon Starter Deck Acquired!")
