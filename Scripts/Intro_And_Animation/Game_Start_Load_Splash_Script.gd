extends Control

# ============================================================
# BOOT SPLASH — the logo, the six-second load, and the menu
# ============================================================
# Built to res://../PKMTCG/legacy-splash-spec.md. Every number below comes from
# that document; the ones that look arbitrary are deliberate, so change them
# there first.
#
# ── THIS SCREEN IS THE LOADER ────────────────────────────────
# The six seconds is not a wait. SceneCache.preload_all_async() is kicked off on
# the FIRST frame and runs underneath the whole animation, which is why the rest
# of the game changes scene without hitching. The splash hands over when BOTH
# are true: six seconds have passed AND every scene is in memory. Finishing the
# load early does not shorten the animation, and overrunning it does not freeze
# the screen — see _hold_until_loaded().
#
# ── NO BANDS ─────────────────────────────────────────────────
# The intro and outro screens carry a header and a footer. This one carries
# NEITHER, on purpose. Do not reach for UIKit.add_header/add_footer here.
#
# ── THE THREE STATES ─────────────────────────────────────────
#   title        the logo, the drifting cards and a slow-blinking "Press any
#                key to continue" ("...any button..." while a pad is connected)
#   save select  every title element fades away and SaveSelectScreen fades in
#                (Save_Select_Screen.gd) — three save slots, Cancel, and New Game
#                or Continue Game. Cancel fades it out and the title back in.
#   hand-off     fade to black, then the saved scene or the first-boot setup
# Which slot is live is decided ONLY here: GameState.load_slot() on Continue,
# GameState.start_new_game() on New Game.
#
# ── WHAT IS DRAWN, AND IN WHAT ORDER ─────────────────────────
#   field  ->  [title layer: cards -> mark -> rule -> text -> prompt]  ->  save select
# The title layer is one Control so the whole title fades as one. Nothing sets
# z_index except the field (UIKit anchors it at Z_FIELD) and the card layer.
#
# The mark, the rule and the button faces are SHADERS, not sprites and not
# StyleBoxFlat. The mark grows through a 2x scale change and has to stay crisp;
# the rule and the buttons have small corner radii, and the project's
# snap_2d_vertices_to_pixel setting facets those in StyleBoxFlat (the reasoning
# is written out at the top of Build_UI_Themes.gd).
# ============================================================

const SHADER_MARK   := "res://Scripts/Shaders/Splash_Mark.gdshader"
const SHADER_RULE   := "res://Scripts/Shaders/Splash_Rule.gdshader"
const SHADER_BUTTON := "res://Scripts/Shaders/Splash_Button.gdshader"

const FIRST_BOOT_SCENE := "res://Scenes/Intro_And_Animation_Scenes/First_Boot_Setup_Scene.tscn"
# Preloaded rather than named by class_name, so a stale class cache cannot break the title screen.
const SAVE_SELECT_SCRIPT := preload("res://Scripts/Intro_And_Animation/Save_Select_Screen.gd")

# ─── Reference space ─────────────────────────────────────────────────────────
# The project stretches canvas_items from a 1920x1080 viewport, so absolute
# coordinates land in the same place on every display.

const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const CENTRE_X := SCREEN_W * 0.5
const CENTRE_Y := SCREEN_H * 0.5

# ─── The mark ────────────────────────────────────────────────────────────────
# Offset RIGHT of screen centre. The text block is centred on the screen, not on
# the mark, and the offset is what stops the two fighting for the same axis.

# The centre is the spec's: vertically centred, 211px right of screen centre.
#
# The WIDTH is not. It is exactly twice that 211px offset, which puts the mark's
# left edge precisely on the screen's vertical centre line — the arms now start
# where the screen's midline is rather than 38px right of it, which is what was
# making the lockup read as slightly off-centre. Height follows the design space's
# 1:2 ratio from there.
const MARK_HALF_W := 211.0
const MARK_SIZE   := Vector2(MARK_HALF_W * 2.0, MARK_HALF_W * 4.0)
const MARK_CENTRE := Vector2(CENTRE_X + MARK_HALF_W, CENTRE_Y)

# ─── The wordmark ────────────────────────────────────────────────────────────
# Cap heights read out of the font files themselves (OS/2 sCapHeight / unitsPerEm):
# Chakra Petch is 0.700 em, IBM Plex Mono 0.698. They are here because the spec
# positions the type by its CAPS, and Godot positions a Label by its baseline —
# these two ratios are the conversion, and every word on this screen is caps.
const CAP_RATIO_UI   := 0.700
const CAP_RATIO_MONO := 0.698

const POKEMON_SIZE  := 108
const POKEMON_TRACK := 0.19        # em
const LEGACY_SIZE   := 131
const LEGACY_TRACK  := 0.05
const TCG_SIZE      := 31
const TCG_TRACK     := 0.42

# The gap between the two words, centred on the mark's gap. POKEMON's baseline
# sits half of it above centre, LEGACY's cap-top half of it below.
const WORD_GAP := 65.0

# ─── The rule ────────────────────────────────────────────────────────────────

const RULE_TOTAL_W  := SCREEN_W * 0.80    # 1536 — it must NOT reach either edge
const RULE_THICK    := 6.5
const RULE_RADIUS   := 2.0
const RULE_TCG_CLEAR := 29.0              # clear space between a rule end and the TCG cap
const RULE_MID_STOP := 0.45

# ─── The prompt ──────────────────────────────────────────────────────────────
# TWEAKABLE — the "Press any key" line under the logo. It breathes: the alpha
# dips to PROMPT_ALPHA_MIN and back once every PROMPT_FADE_PERIOD seconds, and it
# grows to PROMPT_SCALE_MAX and back once every PROMPT_SCALE_PERIOD seconds.
const PROMPT_KEYS := "Press any key to continue"
const PROMPT_PAD  := "Press any button to continue"
const PROMPT_SIZE := 44
const PROMPT_CENTRE_Y := SCREEN_H - 92.0    # 988 — where the button row used to sit
const PROMPT_ALPHA_MIN := 0.4
const PROMPT_FADE_PERIOD := 3.2
const PROMPT_SCALE_MAX := 1.05
const PROMPT_SCALE_PERIOD := 6.4
const PROMPT_APPEAR_SECONDS := 0.8

# TWEAKABLE — the crossfades between the title and the save select.
const TITLE_FADE_OUT := 0.7
const TITLE_FADE_IN  := 0.7
const TITLE_RETURN_FADE := 0.8   # pause menu's Quit to Main Menu: black -> title
const SLOTS_FADE_IN  := 0.5
const SLOTS_FADE_OUT := 0.4
const FADE_REDUCED   := 0.15     # every crossfade, under Reduce motion

# ─── The buttons ─────────────────────────────────────────────────────────────
# The save select's Cancel / New Game / Continue Game are built with these, by
# _make_button() — see SaveSelectScreen._build_buttons().

const BTN_TEXT_SIZE := 29
const BTN_TRACK     := 0.13
const BTN_PAD_V     := 22.0
const BTN_PAD_H     := 65.0
const BTN_RADIUS    := 12.0
const BTN_EDGE_H    := 4.6
const BTN_GAP       := 38.0
const BTN_BOTTOM_INSET := SCREEN_H * 0.055   # 59px

# ─── Timing ──────────────────────────────────────────────────────────────────
# TWEAKABLE — GROW_SECONDS is set to how long the game actually takes to load on
# the dev machine. It is a floor, not a budget: raising it makes the splash
# longer, lowering it does not make the game start sooner, because the hand-off
# still waits for SceneCache.

const GROW_SECONDS := 6.0

const MARK_SCALE_FROM := 0.52
const TEXT_SCALE_FROM := 0.90
const RULE_SCALE_FROM := 0.07

# Two cubic-bezier curves, as [x1, y1, x2, y2]. The mark and text share one; the
# rule leads slightly so the line is already threading the gap while the mark is
# still travelling.
const EASE_GROW := [0.30, 0.50, 0.40, 1.0]
const EASE_RULE := [0.25, 0.55, 0.35, 1.0]

# The hold. Only ever seen if loading overruns the six seconds — a frozen screen
# reads as a crash, so the mark keeps breathing until SceneCache is done.
const HOLD_SCALE  := 1.015
const HOLD_PERIOD := 5.0

# The hand-off. Reduce motion shortens it rather than removing it — a hard cut
# into the overworld is jarring.
const FADE_SECONDS      := 2.0
const FADE_SECONDS_FAST := 0.4

# ============================================================
# DRIFTING CARDS — an experiment, behind one switch
# ============================================================
# Random card faces slide across the screen behind the lockup once the menu is
# up. Cards enter from both edges, travel at their own speed and free themselves
# on the way out.
#
# ── HOW TO TURN IT OFF, AND HOW TO REMOVE IT ─────────────────
# Set CARD_DRIFT_ENABLED to false and the layer is never built; nothing else on
# the splash reads it. To delete the idea outright, remove this const block, the
# DriftCard class, _start_card_drift / _build_card_pool / _spawn_drift_card, the
# three _drift_* / _card_pool vars, and the one call in _show_menu(). Nothing
# else in the project touches any of it.
const CARD_DRIFT_ENABLED := true

const CARD_LIBRARY_DIR := "res://Image_Assets/Card_Image_Library/"

# TWEAKABLE — the whole look of the layer is these six numbers.
const DRIFT_SPEED_MIN := 51.0     # px/s, the slowest a card crosses at
const DRIFT_SPEED_MAX := 144.0    # px/s
const DRIFT_SCALE_MIN := 0.185    # of the 240x330 Small art, so about 44 x 61px
const DRIFT_SCALE_MAX := 0.423    # about 102 x 140px, so the biggest is 2.3x the smallest
const DRIFT_GAP_MIN   := 0.35     # seconds between spawns
const DRIFT_GAP_MAX   := 1.15
# Full strength. The cards are small enough at this size not to compete with the
# wordmark sitting over them, so there is nothing for a dimming pass to fix.
const DRIFT_ALPHA     := 1.0
# A ceiling on how many can be alive at once, so a long wait on the menu cannot
# fill the screen.
const DRIFT_MAX       := 16


## One drifting card. It owns its own travel and its own disposal, so the splash
## script never has to keep a list of them or tidy up after itself.
class DriftCard extends TextureRect:
	var speed: float = 60.0        # px/s; the SIGN is the direction of travel
	var left_bound: float = -40.0
	var right_bound: float = 1960.0

	func _process(delta: float) -> void:
		position.x += speed * delta
		if speed > 0.0 and position.x > right_bound:
			queue_free()
		elif speed < 0.0 and position.x + size.x < left_bound:
			queue_free()

# ─── Nodes ───────────────────────────────────────────────────────────────────

var _title_layer: Control
## The centred lockup (mark, rule, wordmark, prompt), authored at 1920x1080 and offset by
## half the extra canvas so it stays centred on any screen shape. The drifting cards sit
## beside it in _title_layer and span the whole screen.
var _lockup: Control
var _mark: Control
var _text_block: Control
var _rule_left: Control
var _rule_right: Control
var _prompt: TextureRect
var _prompt_label: Label
var _prompt_vp: SubViewport
var _prompt_tweens: Array[Tween] = []
var _save_select: SAVE_SELECT_SCRIPT = null

var _boot_sfx: AudioStreamPlayer

var _hold_tween: Tween
# "growing" -> "title" <-> "to_slots" -> "slots" -> "to_title" -> "title" ... -> "handoff"
var _state: String = "growing"

var _drift_layer: Control = null
var _drift_timer: Timer = null
var _card_pool: PackedStringArray = PackedStringArray()


# ============================================================
# LIFECYCLE
# ============================================================

func _ready() -> void:
	# FIRST, before any UI work: the six seconds is time the loader is already
	# using, not time spent waiting for it to start.
	SceneCache.preload_all_async()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

	# Back from the pause menu's Quit to Main Menu: everything is loaded already,
	# so no growth and no boot sting — the finished title fades up out of black.
	if GameState.skip_title_intro:
		GameState.skip_title_intro = false
		_apply_growth(1.0)
		_fade_from_black()
		_show_menu()
		return

	_play_boot_sfx()
	_run_phase_one()


## The title screen's input only. The save select reads its own keys, and while it
## is up (or fading) this does nothing.
func _input(event: InputEvent) -> void:
	if _state != "title":
		return

	# Escape still quits from the title screen; it is the one key that is not "any key".
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return

	if _is_any_press(event):
		get_viewport().set_input_as_handled()
		_go_to_save_select()


## A fresh press of any key, pad button or mouse button. Key repeat and the wheel
## do not count.
func _is_any_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return UIInput.is_click(event)


# ============================================================
# BUILD
# ============================================================

func _build() -> void:
	# Field first — the Spectrum Night ground, no bands. UIKit anchors it to the
	# full rect at Z_FIELD, so everything added after this draws over it.
	UIKit.add_field(self)

	# Everything that belongs to the title — cards, mark, rule, wordmark, prompt —
	# goes under this one Control, so leaving for the save select is one fade.
	_title_layer = Control.new()
	_title_layer.name = "title"
	_title_layer.position = Vector2.ZERO
	_title_layer.size = UIKit.screen_size()
	_title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_layer)

	# In FRONT of the field, BEHIND everything else. The field is anchored at
	# UIKit.Z_FIELD and the lockup sits at the default 0, so one negative z_index
	# puts the whole layer in the gap between them.
	if CARD_DRIFT_ENABLED:
		_drift_layer = Control.new()
		_drift_layer.name = "card_drift"
		_drift_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_drift_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drift_layer.z_index = -50
		_title_layer.add_child(_drift_layer)
		# Scanned during the six seconds rather than at the moment the first card
		# is wanted, so the directory walk cannot land on the prompt appearing.
		_build_card_pool.call_deferred()

	_lockup = Control.new()
	_lockup.name = "lockup"
	_lockup.position = UIKit.screen_extra() * 0.5
	_lockup.size = Vector2(SCREEN_W, SCREEN_H)
	_lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(_lockup)

	_build_mark()
	_build_rule()
	_build_text()
	_build_prompt()


func _build_mark() -> void:
	_mark = _shader_rect(SHADER_MARK, MARK_SIZE)
	_mark.position = MARK_CENTRE - MARK_SIZE * 0.5
	_mark.pivot_offset = MARK_SIZE * 0.5

	var mat: ShaderMaterial = _mark.material
	mat.set_shader_parameter("upper_a", UITheme.splash_col("mark_upper_a"))
	mat.set_shader_parameter("upper_b", UITheme.splash_col("mark_upper_b"))
	mat.set_shader_parameter("lower_a", UITheme.splash_col("mark_lower_a"))
	mat.set_shader_parameter("lower_b", UITheme.splash_col("mark_lower_b"))

	_lockup.add_child(_mark)


# The rule is TWO segments, not one line with a hole in it: each grows outward
# from the TCG cap, so each needs its own scaling origin. Left segment scales
# about its right edge, right segment about its left.
func _build_rule() -> void:
	var half_gap: float = _tcg_ink_width() * 0.5 + RULE_TCG_CLEAR
	var far_left: float = CENTRE_X - RULE_TOTAL_W * 0.5
	var far_right: float = CENTRE_X + RULE_TOTAL_W * 0.5
	var seg_w: float = (CENTRE_X - half_gap) - far_left
	var top: float = CENTRE_Y - RULE_THICK * 0.5

	_rule_left = _shader_rect(SHADER_RULE, Vector2(seg_w, RULE_THICK))
	_rule_left.position = Vector2(far_left, top)
	_rule_left.pivot_offset = Vector2(seg_w, RULE_THICK * 0.5)
	var ml: ShaderMaterial = _rule_left.material
	ml.set_shader_parameter("col_near", UITheme.splash_col("rule_near"))
	ml.set_shader_parameter("col_mid", UITheme.splash_col("rule_mid_l"))
	ml.set_shader_parameter("mid_stop", RULE_MID_STOP)
	ml.set_shader_parameter("radius", RULE_RADIUS)
	ml.set_shader_parameter("from_right", true)
	_lockup.add_child(_rule_left)

	_rule_right = _shader_rect(SHADER_RULE, Vector2(seg_w, RULE_THICK))
	_rule_right.position = Vector2(far_right - seg_w, top)
	_rule_right.pivot_offset = Vector2(0.0, RULE_THICK * 0.5)
	var mr: ShaderMaterial = _rule_right.material
	mr.set_shader_parameter("col_near", UITheme.splash_col("rule_near"))
	mr.set_shader_parameter("col_mid", UITheme.splash_col("rule_mid_r"))
	mr.set_shader_parameter("mid_stop", RULE_MID_STOP)
	mr.set_shader_parameter("radius", RULE_RADIUS)
	mr.set_shader_parameter("from_right", false)
	_lockup.add_child(_rule_right)


# POKEMON above the mark's gap, TCG threading it, LEGACY below. The block is
# centred on the SCREEN, not on the mark — LEGACY crossing the lower arm is
# intended.
#
# ── THE TYPE IS RENDERED ONCE AND THEN SCALED AS A PICTURE ───
# The three words are drawn into a SubViewport at full size on the first frame,
# and what actually grows on screen is a TextureRect showing that render.
#
# Live Labels wobble when they are scaled. Godot rasterises a face at whole pixel
# sizes with hinting on and subpixel positioning off (see UITheme.font_at, which
# sets all three deliberately and must not be changed for this one screen), so a
# Label scaled continuously from 0.90 to 1.0 is re-rasterised every frame and each
# frame snaps its stems onto a different pixel. Letters visibly jitter against one
# another. Rendering once removes the re-rasterisation entirely: the growth is a
# plain image scale, and because it only ever scales DOWN from the size it was
# rendered at, the final resting frame is pixel-exact.
#
# The premultiplied blend mode is not optional. A transparent SubViewport hands
# back premultiplied pixels; drawn with normal blending the antialiased edge of
# every glyph is multiplied by its own alpha a second time and the type comes out
# with a dark fringe and thin strokes.
func _build_text() -> void:
	var vp := SubViewport.new()
	vp.name = "text_render"
	vp.size = Vector2i(int(SCREEN_W), int(SCREEN_H))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	var pokemon_cap: float = POKEMON_SIZE * CAP_RATIO_UI
	var legacy_cap: float = LEGACY_SIZE * CAP_RATIO_UI
	var tcg_cap: float = TCG_SIZE * CAP_RATIO_MONO

	var pokemon_baseline: float = CENTRE_Y - WORD_GAP * 0.5
	var legacy_baseline: float = CENTRE_Y + WORD_GAP * 0.5 + legacy_cap
	var tcg_baseline: float = CENTRE_Y + tcg_cap * 0.5

	vp.add_child(_word(
		"POKÉMON", UITheme.FONT_UI_MEDIUM, POKEMON_SIZE, POKEMON_TRACK,
		pokemon_baseline, UITheme.splash_col("wordmark")))
	vp.add_child(_word(
		"TCG", UITheme.FONT_MONO, TCG_SIZE, TCG_TRACK,
		tcg_baseline, UITheme.splash_col("tcg")))
	vp.add_child(_word(
		"LEGACY", UITheme.FONT_UI_BOLD, LEGACY_SIZE, LEGACY_TRACK,
		legacy_baseline, UITheme.splash_col("wordmark")))

	_text_block = TextureRect.new()
	_text_block.name = "text_block"
	_text_block.texture = vp.get_texture()
	_text_block.position = Vector2.ZERO
	_text_block.size = Vector2(SCREEN_W, SCREEN_H)
	_text_block.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_text_block.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_text_block.material = _premult_material()

	# Scales about the block's own centre, which is the midpoint of the ink it
	# actually contains rather than the middle of the screen.
	var ink_top: float = pokemon_baseline - pokemon_cap
	_text_block.pivot_offset = Vector2(CENTRE_X, (ink_top + legacy_baseline) * 0.5)

	_lockup.add_child(_text_block)


## "Press any key to continue", rendered once into a SubViewport and shown as a
## picture — for the same reason as the wordmark (see _build_text): it scales
## continuously, and a live Label re-rasterised every frame makes its letters
## jitter. It is rendered at PROMPT_SCALE_MAX and only ever scaled DOWN from there,
## so the largest frame of the breath is pixel-exact.
##
## Re-rendered whenever the wording changes (a pad plugged in or pulled out).
func _build_prompt() -> void:
	var render_size: int = int(round(PROMPT_SIZE * PROMPT_SCALE_MAX))
	var box_h: float = render_size * 2.0

	_prompt_vp = SubViewport.new()
	_prompt_vp.name = "prompt_render"
	_prompt_vp.size = Vector2i(int(SCREEN_W), int(box_h))
	_prompt_vp.transparent_bg = true
	_prompt_vp.disable_3d = true
	_prompt_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_prompt_vp)

	var cap: float = render_size * CAP_RATIO_UI
	_prompt_label = _word(_prompt_text(), UITheme.FONT_UI_MEDIUM, render_size, 0.0,
		box_h * 0.5 + cap * 0.5, UITheme.splash_col("tcg"))
	_prompt_vp.add_child(_prompt_label)

	_prompt = TextureRect.new()
	_prompt.name = "prompt"
	_prompt.texture = _prompt_vp.get_texture()
	_prompt.size = Vector2(SCREEN_W, box_h)
	_prompt.position = Vector2(0.0, PROMPT_CENTRE_Y + UIKit.screen_extra().y * 0.5 - box_h * 0.5)
	_prompt.pivot_offset = _prompt.size * 0.5
	_prompt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.material = _premult_material()
	_prompt.scale = Vector2.ONE / PROMPT_SCALE_MAX
	_prompt.modulate.a = 0.0
	_lockup.add_child(_prompt)

	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void:
		_refresh_prompt_text())


## Keyboard wording, or pad wording while any controller is connected.
func _prompt_text() -> String:
	return PROMPT_PAD if not Input.get_connected_joypads().is_empty() else PROMPT_KEYS


func _refresh_prompt_text() -> void:
	if _prompt_label == null or not is_instance_valid(_prompt_label):
		return
	var text := _prompt_text()
	if _prompt_label.text == text:
		return
	_prompt_label.text = text
	_prompt_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Fades the prompt in, then starts its slow breath: alpha and scale on two
## separate loops of different lengths, so the two never line up into one pulse.
func _start_prompt() -> void:
	_stop_prompt()
	var small := Vector2.ONE / PROMPT_SCALE_MAX
	if UITheme.motion_reduced():
		_prompt.modulate.a = 1.0
		_prompt.scale = small
		return

	var appear := create_tween()
	appear.tween_property(_prompt, "modulate:a", 1.0, PROMPT_APPEAR_SECONDS)
	appear.tween_callback(func() -> void:
		var fade := create_tween().set_loops()
		fade.tween_property(_prompt, "modulate:a", PROMPT_ALPHA_MIN, PROMPT_FADE_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fade.tween_property(_prompt, "modulate:a", 1.0, PROMPT_FADE_PERIOD * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_prompt_tweens.append(fade))
	_prompt_tweens.append(appear)

	var grow := create_tween().set_loops()
	grow.tween_property(_prompt, "scale", Vector2.ONE, PROMPT_SCALE_PERIOD * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	grow.tween_property(_prompt, "scale", small, PROMPT_SCALE_PERIOD * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_prompt_tweens.append(grow)


func _stop_prompt() -> void:
	for t in _prompt_tweens:
		if t != null and t.is_valid():
			t.kill()
	_prompt_tweens.clear()


# ============================================================
# PHASE 1 — growth while loading
# ============================================================

func _run_phase_one() -> void:
	if UITheme.motion_reduced():
		# Reduce motion: full size immediately, and the buttons the moment the
		# load reports done. No six-second floor — the floor exists to give the
		# animation room, and there is no animation.
		_apply_growth(1.0)
		await _await_loaded()
		_show_menu()
		return

	_apply_growth(0.0)

	var tween := create_tween()
	tween.tween_method(_apply_growth, 0.0, 1.0, GROW_SECONDS)
	await tween.finished

	await _hold_until_loaded()
	_show_menu()


## Drives all three growth animations off one 0..1 clock, so they cannot drift
## apart. `u` is linear; the easing is applied per element.
func _apply_growth(u: float) -> void:
	var g: float = _bezier(u, EASE_GROW)
	var r: float = _bezier(u, EASE_RULE)

	var mark_s: float = lerpf(MARK_SCALE_FROM, 1.0, g)
	_mark.scale = Vector2(mark_s, mark_s)

	var text_s: float = lerpf(TEXT_SCALE_FROM, 1.0, g)
	_text_block.scale = Vector2(text_s, text_s)

	var rule_s: float = lerpf(RULE_SCALE_FROM, 1.0, r)
	_rule_left.scale = Vector2(rule_s, 1.0)
	_rule_right.scale = Vector2(rule_s, 1.0)


## The hold state. Returns immediately in the normal case, where the load
## finished somewhere around four seconds and the animation has just caught up.
## If it has not, the mark drifts rather than sitting still — a frozen screen
## looks like a crash, and this is the one place the player could ever see one.
func _hold_until_loaded() -> void:
	if SceneCache.is_all_loaded():
		return

	_hold_tween = create_tween().set_loops()
	_hold_tween.tween_property(_mark, "scale", Vector2(HOLD_SCALE, HOLD_SCALE),
		HOLD_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hold_tween.tween_property(_mark, "scale", Vector2.ONE,
		HOLD_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await _await_loaded()

	_hold_tween.kill()
	_hold_tween = null
	_mark.scale = Vector2.ONE


func _await_loaded() -> void:
	while not SceneCache.is_all_loaded():
		await get_tree().process_frame


# ============================================================
# PHASE 2 — the menu
# ============================================================
# NOTHING MOVES. The logo stays exactly where it finished growing: no lift, no
# reposition, no fade of the lockup. The prompt is the only new thing on the
# screen, and input is ignored until it starts to appear.

func _show_menu() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_STARTING_MENU)
	_start_card_drift()
	_start_prompt()
	_state = "title"


# ============================================================
# TITLE <-> SAVE SELECT
# ============================================================

func _fade_time(normal: float) -> float:
	return FADE_REDUCED if UITheme.motion_reduced() else normal


## Everything on the title fades away together — cards, mark, wordmark, prompt —
## and the save select fades in over the bare field.
func _go_to_save_select() -> void:
	_state = "to_slots"
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	if _drift_timer != null:
		_drift_timer.paused = true

	var out := create_tween()
	out.tween_property(_title_layer, "modulate:a", 0.0, _fade_time(TITLE_FADE_OUT))
	await out.finished
	_title_layer.visible = false
	_stop_prompt()

	_save_select = SAVE_SELECT_SCRIPT.new()
	_save_select.name = "save_select"
	_save_select.setup(self)
	_save_select.modulate.a = 0.0
	add_child(_save_select)
	_save_select.cancelled.connect(_on_save_select_cancelled)
	_save_select.continue_chosen.connect(_on_continue_chosen)
	_save_select.new_game_chosen.connect(_on_new_game_chosen)

	var fade_in := create_tween()
	fade_in.tween_property(_save_select, "modulate:a", 1.0, _fade_time(SLOTS_FADE_IN))
	await fade_in.finished
	_save_select.active = true
	_state = "slots"


## Cancel: the save select fades out and the title — cards, logo, prompt — fades
## back in where it left off.
func _on_save_select_cancelled() -> void:
	_state = "to_title"
	var out := create_tween()
	out.tween_property(_save_select, "modulate:a", 0.0, _fade_time(SLOTS_FADE_OUT))
	await out.finished
	remove_child(_save_select)
	_save_select.queue_free()
	_save_select = null

	_title_layer.visible = true
	_prompt.modulate.a = 0.0
	if _drift_timer != null:
		_drift_timer.paused = false
	var fade_in := create_tween()
	fade_in.tween_property(_title_layer, "modulate:a", 1.0, _fade_time(TITLE_FADE_IN))
	_start_prompt()
	await fade_in.finished
	_state = "title"


# ============================================================
# DRIFTING CARDS
# ============================================================

## Every Small card face in the game, as res:// paths.
##
## Read off disk rather than out of the set JSON so a card whose art is missing
## can never be picked. An exported project serves these as .remap / .import
## stubs, hence the trimming; a Dictionary collects the results so the stub and
## the real name collapse to one entry instead of two.
func _build_card_pool() -> void:
	var found: Dictionary = {}
	var root := DirAccess.open(CARD_LIBRARY_DIR)
	if root == null:
		push_warning("Splash: no card library at " + CARD_LIBRARY_DIR)
		return

	for set_name in root.get_directories():
		var small_dir: String = CARD_LIBRARY_DIR + set_name + "/Small/"
		var set_dir := DirAccess.open(small_dir)
		if set_dir == null:
			continue
		for fname in set_dir.get_files():
			var clean: String = fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			if clean.ends_with(".png"):
				found[small_dir + clean] = true

	_card_pool = PackedStringArray(found.keys())


func _start_card_drift() -> void:
	if not CARD_DRIFT_ENABLED or _drift_layer == null:
		return

	_drift_timer = Timer.new()
	# One-shot and restarted by hand, so each gap is its own random length. A
	# repeating Timer would give a metronome, which is exactly what this must not
	# look like.
	_drift_timer.one_shot = true
	_drift_timer.timeout.connect(func() -> void:
		_spawn_drift_card()
		_drift_timer.start(randf_range(DRIFT_GAP_MIN, DRIFT_GAP_MAX)))
	add_child(_drift_timer)
	_drift_timer.start(0.05)


func _spawn_drift_card() -> void:
	if _card_pool.is_empty() or _drift_layer.get_child_count() >= DRIFT_MAX:
		return

	var tex: Texture2D = load(_card_pool[randi() % _card_pool.size()])
	if tex == null:
		return

	var card := DriftCard.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_SCALE
	# The project's default texture filter is NEAREST for the pixel-art overworld.
	# A card face drawn at 0.74 of its art size under nearest filtering shimmers,
	# so this layer asks for linear.
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = DRIFT_ALPHA

	# Size is picked per card rather than per lane, so a big card and a small one
	# can travel at the same speed. Nothing here fakes parallax: the layer is flat,
	# and tying size to speed would only half-suggest a depth the drawing does not
	# have.
	var scale_factor: float = randf_range(DRIFT_SCALE_MIN, DRIFT_SCALE_MAX)
	card.size = Vector2(tex.get_width(), tex.get_height()) * scale_factor

	var rightward: bool = randi() % 2 == 0
	var speed: float = randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX)
	card.speed = speed if rightward else -speed
	card.left_bound = -40.0
	card.right_bound = UIKit.screen_w() + 40.0

	# Started fully off the edge it enters from, and allowed to hang off the top
	# and bottom so the band of cards does not sit in a neat horizontal stripe.
	card.position = Vector2(
		-card.size.x - 20.0 if rightward else UIKit.screen_w() + 20.0,
		randf_range(-card.size.y * 0.35, UIKit.screen_h() - card.size.y * 0.65))

	_drift_layer.add_child(card)


# ============================================================
# PHASE 3 — hand-off
# ============================================================

## Continue Game on a slot with a save: that slot becomes the live save, then the
## saved scene at the saved position.
func _on_continue_chosen(slot: int) -> void:
	if _state == "handoff":
		return
	_state = "handoff"

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	SoundManagerScript.stop_bgm()
	GameState.load_slot(slot)

	await _fade_to_black()
	_change_to_saved_scene()


## New Game on an empty slot. Nothing is lost, so there is no confirm — the slot
## (empty, or abandoned during setup) is wiped and seeded fresh, decks included.
func _on_new_game_chosen(slot: int) -> void:
	if _state == "handoff":
		return
	_state = "handoff"

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	GameState.start_new_game(slot)

	# The music KEEPS PLAYING across this one. The first-launch setup screen
	# takes the same track through SoundManagerScript, so play_bgm() there is a
	# no-op and the player hears one continuous piece.
	await _fade_to_black()
	SceneCache.change_scene(FIRST_BOOT_SCENE)


## Fades a black overlay in over the whole screen. Linear, because anything
## eased reads as the game hesitating.
func _fade_to_black() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)

	var overlay := ColorRect.new()
	overlay.color = UITheme.splash_col("fade")
	overlay.color.a = 0.0
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var seconds: float = FADE_SECONDS_FAST if UITheme.motion_reduced() else FADE_SECONDS
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 1.0, seconds).set_trans(Tween.TRANS_LINEAR)
	await tween.finished


## The reverse of _fade_to_black, for arriving from the game. The overlay ignores
## the mouse; the title's own input gate is the prompt starting to appear.
func _fade_from_black() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)

	var overlay := ColorRect.new()
	overlay.color = UITheme.splash_col("fade")
	overlay.color.a = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var seconds: float = FADE_REDUCED if UITheme.motion_reduced() else TITLE_RETURN_FADE
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, seconds)
	await tween.finished
	remove_child(layer)
	layer.queue_free()


## Where the player actually goes. Unchanged from the pre-menu splash: the saved
## scene, resumed at the saved position, or the first-launch setup screen if this
## save has never been through it.
func _change_to_saved_scene() -> void:
	await _await_loaded()

	if not GameState.progress.get("first_launch_complete", true):
		SceneCache.change_scene(FIRST_BOOT_SCENE)
		return

	var target_scene: String = GameState.get_saved_scene_path()

	# Route through menu_return_state so the destination scene's own _ready logic
	# picks the position up — every map checks it first.
	if GameState.has_saved_player_position():
		GameState.save_menu_return_state(
			target_scene,
			GameState.get_saved_player_position(),
			GameState.get_player_direction())

	SceneCache.change_scene(target_scene)


# ============================================================
# BUILDING BLOCKS
# ============================================================

func _play_boot_sfx() -> void:
	var stream = load("res://Audio/SFX/fatsynth.ogg")
	if stream == null:
		return
	_boot_sfx = AudioStreamPlayer.new()
	_boot_sfx.stream = stream
	_boot_sfx.bus = SoundManagerScript.SFX_BUS
	add_child(_boot_sfx)
	_boot_sfx.play()


## A ColorRect carrying one of the splash shaders. UIKit.ShaderRect is used for
## the rect_size sync alone — none of these three scroll, hence tracks_motion.
## Premultiplied blending for a SubViewport render (see _build_text), that still
## FADES. A plain CanvasItemMaterial in premult mode multiplies only the alpha by
## modulate, so a fade leaves the colour channels at full strength and the type
## stays on screen, drawn additively. This scales all four channels by the
## inherited alpha instead, which is what a premultiplied fade means.
func _premult_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_premul_alpha;
varying float fade;
void vertex() { fade = COLOR.a; }
void fragment() { COLOR = texture(TEXTURE, UV) * fade; }
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _shader_rect(shader_path: String, rect_size: Vector2) -> Control:
	var rect := UIKit.ShaderRect.new()
	rect.tracks_motion = false
	rect.color = Color.WHITE            # the shader replaces this entirely
	rect.size = rect_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("rect_size", rect_size)
	rect.material = mat
	return rect


## One word of the lockup, placed by its BASELINE and centred on the screen.
##
## Two things worth knowing. Godot draws a Label's first baseline `ascent` below
## the top of its rect, so the caller's baseline is converted here rather than at
## the call site. And glyph spacing is added AFTER every glyph including the
## last, which drags the visible ink half a tracking step left of centre — the
## x offset puts it back.
func _word(text: String, font_path: String, size_px: int, track_em: float,
		baseline_y: float, colour: Color) -> Label:
	var track: int = int(round(size_px * track_em))
	var font := _tracked_font(font_path, track)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", colour)

	var ascent: float = font.get_ascent(size_px)
	label.size = Vector2(SCREEN_W, ascent + font.get_descent(size_px))
	label.position = Vector2(track * 0.5, baseline_y - ascent)
	return label


## A face with letter-spacing baked in. FontVariation rather than the
## `font_spacing_glyph` theme constant because the same call has to serve a Label
## and a Button, and the spacing has to be visible to get_string_size() so the
## rule gap and the button widths can be measured before anything is drawn.
func _tracked_font(font_path: String, track_px: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = UITheme.font_at(font_path)
	v.set_spacing(TextServer.SPACING_GLYPH, track_px)
	return v


## Width of the drawn ink, i.e. the advance width less the trailing tracking step
## that FontVariation adds after the final glyph.
func _ink_width(font: FontVariation, text: String, size_px: int, track_px: int) -> float:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	return w - float(track_px)


func _tcg_ink_width() -> float:
	var track: int = int(round(TCG_SIZE * TCG_TRACK))
	return _ink_width(_tracked_font(UITheme.FONT_MONO, track), "TCG", TCG_SIZE, track)


## Top of the button row, for the save select.
func button_row_y() -> float:
	return UIKit.screen_h() - BTN_BOTTOM_INSET - _button_height()


## The gap between a pair of buttons. The GAP is centred on the screen, not
## either button, so the midline runs down the space between them.
func button_gap() -> float:
	return BTN_GAP


func _button_height() -> float:
	return BTN_TEXT_SIZE + BTN_PAD_V * 2.0


func _button_width(text: String) -> float:
	var track: int = int(round(BTN_TEXT_SIZE * BTN_TRACK))
	var font := _tracked_font(UITheme.FONT_UI_BOLD, track)
	return _ink_width(font, text.to_upper(), BTN_TEXT_SIZE, track) + BTN_PAD_H * 2.0


## A menu button: a shader-drawn face with a transparent Button on top of it.
##
## The Button is LAST in the child list, which is what makes it the thing that
## receives the click — a catcher that is not last catches nothing. Its own
## stylebox is emptied in every state so the face underneath is the only thing
## drawn, and hover/press reach that face through the shader's state_tint.
func _make_button(text: String, width: float, fill_top: Color, fill_bot: Color,
		fg: Color) -> Control:
	var size := Vector2(width, _button_height())

	var holder := Control.new()
	holder.name = "splash_button_" + text.to_lower().replace(" ", "_")
	holder.size = size
	holder.pivot_offset = size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var face := _shader_rect(SHADER_BUTTON, size)
	face.name = "face"
	var mat: ShaderMaterial = face.material
	mat.set_shader_parameter("fill_top", fill_top)
	mat.set_shader_parameter("fill_bot", fill_bot)
	mat.set_shader_parameter("edge_col", UITheme.col("btn_edge"))
	mat.set_shader_parameter("radius", BTN_RADIUS)
	mat.set_shader_parameter("edge_h", BTN_EDGE_H)
	holder.add_child(face)

	var track: int = int(round(BTN_TEXT_SIZE * BTN_TRACK))
	var btn := Button.new()
	btn.name = "btn"
	btn.text = text.to_upper()
	btn.size = size
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _tracked_font(UITheme.FONT_UI_BOLD, track))
	btn.add_theme_font_size_override("font_size", BTN_TEXT_SIZE)
	for colour_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		btn.add_theme_color_override(colour_state, fg)
	holder.add_child(btn)

	btn.mouse_entered.connect(func() -> void: _set_button_tint(mat, "btn_hover"))
	btn.mouse_exited.connect(func() -> void: _set_button_tint(mat, ""))
	btn.button_down.connect(func() -> void: _set_button_tint(mat, "btn_press"))
	btn.button_up.connect(func() -> void: _set_button_tint(mat, ""))

	return holder


func _set_button_tint(mat: ShaderMaterial, key: String) -> void:
	var tint := Color(0.0, 0.0, 0.0, 0.0)
	if key != "":
		tint = UITheme.splash_col(key)
	mat.set_shader_parameter("state_tint", tint)


# ─── Easing ──────────────────────────────────────────────────────────────────
# CSS cubic-bezier, evaluated properly rather than approximated with one of
# Godot's TRANS_* curves, so the growth matches the spec's curves exactly.

## y of the curve [x1, y1, x2, y2] at x, with the implicit end points (0,0) and
## (1,1). x is solved for t by Newton-Raphson, which converges in a handful of
## iterations for every curve on this screen.
func _bezier(x: float, curve: Array) -> float:
	var x1: float = curve[0]
	var y1: float = curve[1]
	var x2: float = curve[2]
	var y2: float = curve[3]

	x = clampf(x, 0.0, 1.0)
	var t: float = x
	for _i in 8:
		var dx: float = _bezier_axis(t, x1, x2) - x
		if absf(dx) < 0.000001:
			break
		var slope: float = _bezier_slope(t, x1, x2)
		if absf(slope) < 0.000001:
			break
		t = clampf(t - dx / slope, 0.0, 1.0)
	return _bezier_axis(t, y1, y2)


func _bezier_axis(t: float, a: float, b: float) -> float:
	var mt: float = 1.0 - t
	return 3.0 * mt * mt * t * a + 3.0 * mt * t * t * b + t * t * t


func _bezier_slope(t: float, a: float, b: float) -> float:
	var mt: float = 1.0 - t
	return 3.0 * mt * mt * a + 6.0 * mt * t * (b - a) + 3.0 * t * t * (1.0 - b)
