extends Control

# ============================================================
# OPTIONS
# ============================================================
# Eight rows, each a label on the left and its control group on the right.
#
# ── BUILT IN CODE, NOT IN THE SCENE ──────────────────────────
# This screen used to be ~55 hand-placed nodes at absolute offsets, and every
# time a row was added the WHOLE page had to be re-spaced by hand — adding the
# volume sliders moved every `offset_top` on the screen and squeezed the
# inter-section gaps from 19/28px down to 12/18px to make room.
#
# It is a VBoxContainer now. Adding a row is one entry in _build_rows() and one
# entry in each of the three dictionaries; nothing else moves, and nothing has
# to be measured. Options_Scene.tscn is a bare Control carrying this script.
#
# ── THE THREE DICTIONARIES ───────────────────────────────────
# Every row, slider included, flows through the same pending/saved model:
#
#   section_buttons  section name -> { option value : Button }
#   section_sliders  section name -> { "slider": HSlider, "value_label": Label }
#   section_setters  section name -> the GameState call that persists it
#
# `pending` is what the player has clicked, `saved` is what is on disk. Save
# walks the difference. A new row needs an entry in all three plus one in
# _current_values() and nothing else.
#
# ── SLIDERS BEHAVE DIFFERENTLY, ON PURPOSE ───────────────────
#   * They apply LIVE while you drag, so you can hear what you are choosing.
#     Every other row on this screen does nothing until Save.
#   * Save still owns persistence — dragging never touches the save file.
#   * Because they apply live, Cancel and Escape have to put the volume back
#     (_revert_live_volume). A button row needs no such undo.
# Values are held here as whole percents 0-100 so change detection stays an
# exact integer comparison; GameState stores 0.0-1.0.
#
# ── WHAT CHANGED IN THE UI OVERHAUL ──────────────────────────
# The three animation-speed rows (match / item reveal / pack opening) became
# ONE "Animation speed" row at slow / medium / fast. Their three multiplier
# tables still exist and still differ — see GameState.
#
# The per-ladder "skip" presets became "Reduce motion", which collapses all
# three at once AND stops the chevron scroll and the selection-ring spin.
#
# "Match intro & outro" stays its own row. It is not the same control as reduce
# motion: this one removes the screen, reduce motion keeps the screen and
# collapses its movement.
#
# Message box colour is not here and should not come back: each NPC and
# opponent carries its own `message_colour` and the box is themed per speaker.
# ============================================================

# ─── Layout ──────────────────────────────────────────────────────────────────
# TWEAKABLE. All in px at 1920x1080; the block is centred in whatever height is
# left between the header and the footer.
const BLOCK_W      := 1330.0   # the rows' total width, centred horizontally
const LABEL_W      := 370.0    # the label column
const LABEL_GAP    := 40.0     # label column -> first control
const ROW_GAP      := 34.0     # between rows
const OPTION_GAP   := 18.0     # between the buttons inside one row
const SLIDER_W     := 690.0
const VALUE_W      := 90.0     # the "80%" readout, wide enough for "100%"
const ROW_MIN_H    := 62.0     # so a slider row and a button row match

# The row labels keep small_label's mono caps — it reads as a form label rather
# than a heading — but at a larger size than the role's own 13.5, which left the
# screen looking sparse against eight widely spaced rows.
const ROW_LABEL_SIZE := 19

## ISSUE #275: the sub-caption under a row label. Small enough to read as a note
## on the row above rather than as a row of its own. TWEAKABLE.
const ROW_SUB_SIZE := 13
const ROW_SUB_GAP  := 2

# ─── State ───────────────────────────────────────────────────────────────────

var pending : Dictionary = {}
var saved   : Dictionary = {}

var section_buttons : Dictionary = {}
var section_sliders : Dictionary = {}
var section_setters : Dictionary = {}

var save_btn   : Button
var cancel_btn : Button

@onready var audio_player := AudioStreamPlayer.new()

# Keep this in step with the `step` set on both HSliders below. Without the snap
# an off-step saved value (only reachable by hand-editing the save) would be
# nudged onto the nearest notch the moment the slider loaded it, and the screen
# would open already claiming an unsaved change.
const VOLUME_STEP := 5


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ISSUE #128: every sub-menu plays the same track. This screen had none, so it ran on
	# whatever the main menu was still playing behind it -- and once that overlap was fixed
	# (Main_Menu_Script.pause_music) it would have been left silent instead.
	add_child(audio_player)
	var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
	audio_player.stream = audio_stream
	audio_player.bus = SoundManagerScript.MUSIC_BUS
	if audio_stream != null:
		audio_stream.loop = true
		audio_player.play()

	theme = load("res://UI_Themes/ui/ui_base.tres")

	_build_chrome()
	_build_rows()

	section_setters = {
		"confusion":    GameState.set_confusion_rule,
		"burn":         GameState.set_burn_rule,
		"walking":      GameState.set_walking_speed,
		"animation":    GameState.set_animation_speed,
		"reduce_motion": GameState.set_reduce_motion,
		"intro_outro":  GameState.set_intro_outro,
		# The two volume entries wrap their setter because this screen counts in whole percents
		# while GameState (and the audio bus behind it) works in 0.0 - 1.0.
		"music_volume": func(percent: int) -> void: GameState.set_music_volume(percent / 100.0),
		"sfx_volume":   func(percent: int) -> void: GameState.set_sfx_volume(percent / 100.0),
	}

	saved = _current_values()
	pending = saved.duplicate()

	for section in section_buttons:
		for option in section_buttons[section]:
			section_buttons[section][option].pressed.connect(_on_option_pressed.bind(section, option))
		_refresh_section(section)

	for section in section_sliders:
		var slider: HSlider = section_sliders[section]["slider"]
		slider.value = pending[section]
		slider.value_changed.connect(_on_slider_changed.bind(section))
		slider.drag_ended.connect(_on_slider_drag_ended.bind(section))
		_refresh_slider(section)

	_refresh_save_button()


# ─── Chrome ──────────────────────────────────────────────────────────────────

func _build_chrome() -> void:
	UIKit.add_field(self)

	var header := UIKit.add_header(self)
	var title := Label.new()
	UIKit.set_label(title, "title", "Options", "chrome_fg")
	header.centre.add_child(title)

	var footer := UIKit.add_footer(self)
	cancel_btn = UIKit.make_footer_button("Cancel", "secondary")
	cancel_btn.pressed.connect(_on_cancel_pressed)
	footer.centre.add_child(cancel_btn)

	save_btn = UIKit.make_footer_button("Save", "primary")
	save_btn.pressed.connect(_on_save_pressed)
	footer.centre.add_child(save_btn)


# ─── Rows ────────────────────────────────────────────────────────────────────

## Every row on the screen, in order. The option VALUES are the keys GameState
## persists; the labels beside them are display text only.
func _build_rows() -> void:
	var header_h: float = UITheme.m("header_h")
	var footer_h: float = UITheme.m("footer_slim_h")

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(ROW_GAP))
	# Centred in the space between the bars, so the block stays balanced however
	# many rows there are.
	body.set_anchors_preset(Control.PRESET_CENTER)
	body.anchor_left = 0.5
	body.anchor_right = 0.5
	body.anchor_top = 0.0
	body.anchor_bottom = 1.0
	body.offset_left = -BLOCK_W * 0.5
	body.offset_right = BLOCK_W * 0.5
	body.offset_top = header_h
	body.offset_bottom = -footer_h
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(body)

	_add_button_row(body, "confusion", "Confusion rules", [
		["base_set_confusion_rules",   "Base set"],
		["fairer_confusion_rules",     "Fairer retreat"],
		["modern_era_confusion_rules", "EX era"],
	])
	_add_button_row(body, "burn", "Burn rules", [
		["base_set_burn_rules",   "Base set"],
		["modern_era_burn_rules", "EX era"],
	])
	_add_button_row(body, "walking", "Walking speed", [
		["very_slow", "Very slow"],
		["slow",      "Slow"],
		["normal",    "Normal"],
		["fast",      "Fast"],
	])
	_add_button_row(body, "animation", "Animation speed", [
		["slow",   "Slow"],
		["medium", "Medium"],
		["fast",   "Fast"],
	])
	# The stored value stays "where_possible" — it is the key GameState persists and
	# the one UITheme.motion_reduced() compares against. Only the label is "On".
	# ISSUE #275: "Reduce motion" is the only row on this screen whose name does not
	# say what it does - it sounds like a comfort setting when it actually removes
	# every animation in the game. The sub-caption says so on the row itself.
	_add_button_row(body, "reduce_motion", "Reduce motion", [
		["off",            "Off"],
		["where_possible", "On"],
	], "(skips all animations)")
	_add_button_row(body, "intro_outro", "Match intro & outro", [
		["play", "Play"],
		["skip", "Skip"],
	])
	_add_slider_row(body, "music_volume", "Music")
	_add_slider_row(body, "sfx_volume", "Sound effects")


## One label + a row of mutually exclusive option buttons.
func _add_button_row(parent: VBoxContainer, section: String, label_text: String,
		options: Array, sub_text: String = "") -> void:
	var row := _new_row(parent, label_text, sub_text)

	var buttons: Dictionary = {}
	for entry in options:
		var value: String = entry[0]
		var btn := Button.new()
		btn.text = entry[1]
		UIKit.style_button(btn, "secondary")   # _refresh_section repaints the chosen one
		row.add_child(btn)
		buttons[value] = btn
	section_buttons[section] = buttons


## One label + a slider and its percentage readout.
func _add_slider_row(parent: VBoxContainer, section: String, label_text: String) -> void:
	var row := _new_row(parent, label_text)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(SLIDER_W, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0
	slider.max_value = 100
	slider.step = VOLUME_STEP
	row.add_child(slider)

	var value_label := Label.new()
	# Mono, so the readout does not jitter as the digits change width while dragging.
	UIKit.style_label(value_label, "hp", "field_mute")
	value_label.custom_minimum_size = Vector2(VALUE_W, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	section_sliders[section] = { "slider": slider, "value_label": value_label }


## The label column plus an HBox for whatever controls the row holds.
## ISSUE #275: `sub_text`, when given, is a smaller second line under the row
## label. It is centred on the LABEL'S OWN TEXT, not on the 370px label column -
## the column is a lot wider than any of these names, so centring in the column
## would leave the note floating well to the right of the words it belongs to.
## The width is measured off the rendered label, so it stays centred whatever the
## row is called.
##
## The label column becomes a VBox in that case. It is SHRINK_CENTER so the two
## lines stay vertically centred in the row, which is where the single label sat.
func _new_row(parent: VBoxContainer, label_text: String, sub_text: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(OPTION_GAP))
	row.custom_minimum_size.y = ROW_MIN_H
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(row)

	var label := Label.new()
	UIKit.set_label(label, "small_label", label_text, "field_mute", ROW_LABEL_SIZE)
	label.custom_minimum_size = Vector2(LABEL_W, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if sub_text == "":
		row.add_child(label)
	else:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", ROW_SUB_GAP)
		col.custom_minimum_size = Vector2(LABEL_W, 0)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)

		label.custom_minimum_size = Vector2(LABEL_W, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		col.add_child(label)

		var sub := Label.new()
		UIKit.set_label(sub, "small_label", sub_text, "field_mute", ROW_SUB_SIZE)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Centred under the WORDS, so the note is measured against the label's own
		# rendered width rather than the width of the column it sits in.
		var name_font: Font = label.get_theme_font("font")
		var name_w: float = LABEL_W
		if name_font != null:
			name_w = name_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, ROW_LABEL_SIZE).x
		sub.custom_minimum_size = Vector2(name_w, 0)
		sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(sub)
		print("ISSUE #275 FIX ACTIVE: sub-caption '", sub_text, "' centred on ",
			name_w, "px of '", label.text, "'")

	# A spacer rather than padding on the label, so the label can be left-aligned
	# and the controls still start on the same x in every row.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(LABEL_GAP, 0)
	row.add_child(gap)

	return row


# ─── Values ──────────────────────────────────────────────────────────────────

## The persisted value of every section, read straight off GameState.
func _current_values() -> Dictionary:
	return {
		"confusion":     GameState.confusion_rule_setting,
		"burn":          GameState.burn_rule_setting,
		"walking":       GameState.walking_speed_setting,
		"animation":     GameState.animation_speed_setting,
		"reduce_motion": GameState.reduce_motion_setting,
		"intro_outro":   GameState.intro_outro_setting,
		"music_volume":  _to_percent(GameState.music_volume_setting),
		"sfx_volume":    _to_percent(GameState.sfx_volume_setting),
	}


func _to_percent(linear: float) -> int:
	return int(round(linear * 100.0 / VOLUME_STEP)) * VOLUME_STEP


func _input(event: InputEvent) -> void:
	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_leave()


# ─── Option selection ────────────────────────────────────────────────────────

func _on_option_pressed(section: String, option: String) -> void:
	if option == pending[section]:
		return
	pending[section] = option
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_section(section)
	_refresh_save_button()

	# Reduce motion is the one row whose effect is visible on this very screen —
	# it stops the chevrons. Apply it live so the player can see what they picked
	# before committing, then let Cancel put it back the way the sliders do.
	if section == "reduce_motion":
		GameState.set_reduce_motion(option, false)
		_refresh_chevrons()


## Highlights whichever button in a section matches the pending selection.
func _refresh_section(section: String) -> void:
	for option in section_buttons[section]:
		var btn: Button = section_buttons[section][option]
		UIKit.style_button(btn, "selected" if pending[section] == option else "secondary")


## Pushes the current reduce-motion state into every scrolling/spinning node on
## screen. UIKit's ShaderRects listen for UITheme.theme_changed, so emitting it
## is enough — nothing here needs to know where the chevrons live.
func _refresh_chevrons() -> void:
	UITheme.theme_changed.emit()


# ─── Volume sliders ──────────────────────────────────────────────────────────

# Dragging applies straight away so the change is audible — but only to the live audio bus, never to
# the save file. Save commits it; Cancel and Escape roll it back.
func _on_slider_changed(value: float, section: String) -> void:
	var percent := int(round(value))
	if percent == pending[section]:
		return
	pending[section] = percent
	_apply_live_volume(section, percent)
	_refresh_slider(section)
	_refresh_save_button()


# A confirmation blip once the grabber is released, so the SFX row can be judged at its new level.
# The music row needs none — whatever BGM is playing behind this screen already changed as you moved.
func _on_slider_drag_ended(value_changed: bool, section: String) -> void:
	if value_changed and section == "sfx_volume":
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)


func _apply_live_volume(section: String, percent: int) -> void:
	if section == "music_volume":
		GameState.set_music_volume(percent / 100.0, false)
	else:
		GameState.set_sfx_volume(percent / 100.0, false)


func _refresh_slider(section: String) -> void:
	var percent: int = pending[section]
	section_sliders[section]["slider"].value = percent
	section_sliders[section]["value_label"].text = "%d%%" % percent


# Puts the audio buses AND reduce motion back to the last saved state. Called when leaving without
# saving — without this, a cancelled drag would keep its volume until the next boot re-read the save
# file, and a cancelled reduce-motion toggle would leave the chevrons stopped.
func _revert_live_changes() -> void:
	for section in section_sliders:
		_apply_live_volume(section, saved[section])
	if GameState.reduce_motion_setting != saved["reduce_motion"]:
		GameState.set_reduce_motion(saved["reduce_motion"], false)
		_refresh_chevrons()


# The save button only lights up while there is an unsaved change in any section.
func _refresh_save_button() -> void:
	var has_change := false
	for section in pending:
		if pending[section] != saved[section]:
			has_change = true
			break
	save_btn.disabled = not has_change
	UIKit.style_button(save_btn, "good" if has_change else "primary")


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var saved_anything := false

	for section in section_setters:
		if pending[section] != saved[section]:
			section_setters[section].call(pending[section])
			saved_anything = true

	if not saved_anything:
		return
	saved = pending.duplicate()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_save_button()


func _on_cancel_pressed() -> void:
	_leave()


func _leave() -> void:
	_revert_live_changes()
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
