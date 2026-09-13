extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(50, 20)

# ISSUE #130 FIX: the box gift and Player_Data/Player_Decks/"Your First Deck".json had drifted --
# the deck ran 4 Doduo and 2 Poliwag the player was never given, and 2 Bill it did not contain,
# while the gift handed over 4 Voltorb against the deck's 2. Both are now the SAME 60-card list:
#   2 Farfetch'd, 4 Diglett, 4 Doduo, 4 Machop, 2 Poliwag, 4 Rattata, 4 Staryu, 2 Voltorb,
#   2 Potion, 2 Super Potion, 2 Bill, 16 Fighting Energy, 12 Water Energy   (all Base Set)
# The 28 basic Energy are deliberately NOT in this string: no set's *_player_owned_cards.json
# tracks basic Energy (it is unlimited and comes from the deck builder's energy section), so
# gifting them would append entries no other set has and put Energy cards in the base1 grid.
# CheatManager._STARTER_BOX_CARDS mirrors this constant -- change both together.
const STARTER_BOX_CARDS = "base1-27, base1-27, base1-47, base1-47, base1-47, base1-47, base1-48, base1-48, base1-48, base1-48, base1-52, base1-52, base1-52, base1-52, base1-59, base1-59, base1-61, base1-61, base1-61, base1-61, base1-65, base1-65, base1-65, base1-65, base1-67, base1-67, base1-90, base1-90, base1-91, base1-91, base1-94, base1-94"

# ── The note on top of the starter box ───────────────────────────────────────
# The letter used to be a wall of dialogue text; it is now the hand-written note ITSELF, flown up
# over a darkened screen exactly the way the phone arrives in a call (Phone_Call.gd) -- it sails a
# little past its resting place and settles back, then dips upward before dropping away on the
# click that dismisses it.
const NOTE_TEXTURE       := "res://Image_Assets/Assorted_Extras/Note.png"
const NOTE_DIM_ALPHA     := 0.75   # darkness of the translucent blocker behind the note
const NOTE_HEIGHT        := 0.92   # note height as a fraction of the screen's height
const NOTE_RISE_TIME     := 0.45   # note flies in from the bottom
const NOTE_DROP_TIME     := 0.38   # note flies off the bottom
const NOTE_OVERSHOOT     := 18.0   # px past the resting place at each end of the flight
const NOTE_OFFSCREEN_PAD := 40.0   # how far below the screen edge it waits and lands

var _box_sparkle: CPUParticles2D = null
var _note_root: Control = null
var _note_image: TextureRect = null
var _note_dim: ColorRect = null
var _note_dismissable: bool = false
var _note_done: Callable = Callable()
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
const NEXT_MORNING_FONT := "res://UI_Themes/ChakraPetch-Bold.ttf"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME
func get_default_spawn() -> Vector2:  return SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS
func get_entry_positions() -> Dictionary:
	return {"Player_House_Downstairs": SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS}

func _scene_setup():
	_apply_moving_in_state()
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

# ISSUE #26 FIX: drive both the visual layers AND the collision bodies from moving_in_completed.
# Before move-in: "Moving In" visible + its box collisions active, "Post Move In" hidden + removed.
# After move-in:  the reverse. Collision bodies are REMOVED (not just hidden) because hiding a
# StaticBody2D via a parent Control does NOT stop it colliding. SceneCache re-instantiates the
# scene fresh on every visit, so queue_free() here is safe.
func _apply_moving_in_state() -> void:
	var completed: bool = GameState.progress.get("moving_in_completed", false)

	# --- Visual tile layers under UPSTAIRS ---
	var moving_in_layer := $UPSTAIRS.get_node_or_null("Moving In")
	if moving_in_layer != null:
		moving_in_layer.visible = not completed
	var post_move_in_visual := $UPSTAIRS.get_node_or_null("Post Move In")
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
		"Huh? A box of Pokemon cards with a note on top",
		_on_box_step2
	)

func _on_box_step2() -> void:
	_show_note_then(_on_box_step3)


# ============================================================
# THE NOTE
# ============================================================

## Darkens the screen, flies the note up from below and holds it there until the player clicks.
## `on_done` runs once the note has dropped back off the bottom and the dim has faded out.
func _show_note_then(on_done: Callable) -> void:
	_note_done = on_done
	# The box that asked for this does NOT close itself: MapManager's OK handler runs a pending
	# callback INSTEAD of dismissing the panel, so "there's a note on top" would still be sitting
	# there under the note. Close it by hand, then take movement back off the player -- _hide_message
	# hands it straight back.
	MapManager._hide_message()
	if _player != null:
		_player.can_move = false

	var vp := get_viewport().get_visible_rect().size

	_note_root = Control.new()
	_note_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_note_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_note_root)

	# STOP so nothing behind the dim can be clicked through it. The dismiss press itself is NOT read
	# here -- it is read in _input() below, which runs before GUI picking and so catches a click
	# anywhere on the screen and the keys equally.
	_note_dim = ColorRect.new()
	_note_dim.color = Color(0, 0, 0, NOTE_DIM_ALPHA)
	_note_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_note_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_note_dim.modulate.a = 0.0
	_note_root.add_child(_note_dim)

	# EXPAND_IGNORE_SIZE is load-bearing: without it a TextureRect's minimum size is its TEXTURE's
	# size and a Control can never be smaller than its minimum, so the fitted size below would be
	# clamped straight back up to the source image's full pixel height.
	var tex: Texture2D = load(NOTE_TEXTURE)
	var src := Vector2(float(tex.get_width()), float(tex.get_height()))
	_note_image = TextureRect.new()
	_note_image.texture = tex
	_note_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_note_image.stretch_mode = TextureRect.STRETCH_SCALE
	_note_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fit: float = vp.y * NOTE_HEIGHT / maxf(1.0, src.y)
	_note_image.size = src * fit
	_note_image.position = Vector2((vp.x - _note_image.size.x) * 0.5, vp.y + NOTE_OFFSCREEN_PAD)
	_note_image.modulate.a = 0.0
	_note_root.add_child(_note_image)

	var rest_y: float = (vp.y - _note_image.size.y) * 0.5

	# Two tweens, the way the phone does it: the flight is a SEQUENCE (sail past the resting place,
	# settle back onto it) while the fades run across the whole of it.
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_note_dim, "modulate:a", 1.0, NOTE_RISE_TIME * 0.8)
	fade.tween_property(_note_image, "modulate:a", 1.0, NOTE_RISE_TIME * 0.6)

	var rise := create_tween()
	rise.tween_property(_note_image, "position:y", rest_y - NOTE_OVERSHOOT, NOTE_RISE_TIME * 0.78) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	rise.tween_property(_note_image, "position:y", rest_y, NOTE_RISE_TIME * 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Only dismissable once it has landed, so the click that closed the message before it cannot
	# carry through and skip the note the instant it appears.
	rise.tween_callback(func() -> void: _note_dismissable = true)


## The note is dismissed from _input(), not from a gui_input on the dim: a Control only hears the
## clicks GUI picking hands it, while _input() runs before picking and sees the whole screen -- and
## Space/Enter/Escape never reach a ColorRect at all. Overriding the base scene's _input() also
## keeps Escape and Enter from opening the main menu behind the note; everything is passed back up
## to BaseMapScene once the note is gone.
func _input(event: InputEvent) -> void:
	if _note_root != null and is_instance_valid(_note_root):
		# UIInput, not raw keycodes: is_click ignores a mouse-wheel notch (which is a button press
		# too) and is_advance covers Space, Enter and Escape alike.
		if _note_dismissable and (UIInput.is_click(event) or UIInput.is_advance(event)):
			_note_dismissable = false
			get_viewport().set_input_as_handled()
			_hide_note()
		# While the note is on screen it owns every key and button, including the ones that would
		# otherwise open the menu or walk the player about.
		return
	super._input(event)


func _hide_note() -> void:
	var vp := get_viewport().get_visible_rect().size

	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_note_image, "modulate:a", 0.0, NOTE_DROP_TIME)
	fade.tween_property(_note_dim, "modulate:a", 0.0, NOTE_DROP_TIME)

	var leave := create_tween()
	leave.tween_property(_note_image, "position:y", _note_image.position.y - NOTE_OVERSHOOT, NOTE_DROP_TIME * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	leave.tween_property(_note_image, "position:y", vp.y + NOTE_OFFSCREEN_PAD, NOTE_DROP_TIME * 0.75) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	leave.tween_callback(_finish_note)


func _finish_note() -> void:
	if _note_root != null and is_instance_valid(_note_root):
		_note_root.queue_free()
	_note_root = null
	_note_image = null
	_note_dim = null
	var cb := _note_done
	_note_done = Callable()
	if cb.is_valid():
		cb.call()

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
	# ISSUE #28 FIX: large centred kenney-font message, matching the match's big messagebox style.
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager._show_large_message_with_ok("Pokemon Starter Deck Acquired!")
