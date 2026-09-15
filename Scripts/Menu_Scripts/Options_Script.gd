extends Control

# ============================================================
# OPTIONS
# ============================================================
# Twelve rows, each a label on the left and its control group on the right.
# Everything fits between the bars with nothing to scroll — see _build_rows().
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
# THE TWO THEME ROWS ARE THE EXCEPTION. "Colour theme" and "Mode" are two rows
# on screen but one stored value: both read and write `pending["ui_theme"]`,
# recomposing `<look>_<mode>`. They have no section_setters entry of their own
# and they never appear in `pending`. See THEME_LOOK / THEME_MODE.
#
# ── THE ROWS THAT PREVIEW THEMSELVES ─────────────────────────
# Five rows apply the moment you touch them, because their effect is visible on
# THIS screen and waiting for Save would mean choosing blind:
#
#   the two volume sliders   you hear it
#   reduce motion            the chevrons stop
#   colour theme / mode      every colour on the page changes
#   hide header/footer       the banners go
#
# All five follow the same contract: applied live, written to disk only by Save,
# and put back by Cancel and Escape (_revert_live_changes). Live and saved are
# separate things — dragging a slider or previewing a theme never touches the
# save file. Every other row does nothing until Save.
#
# The three colour rows rebuild the whole screen when touched, because every
# colour was read at build time and the button faces are baked art. See
# _rebuild().
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
# Widened from 1330 so the eight theme buttons fit on ONE line. That single
# change buys back more vertical space than any amount of gap-tightening, and
# the screen has the width to spare — 110px of margin each side at 1920.
const BLOCK_W      := 1700.0   # the rows' total width, centred horizontally
const LABEL_W      := 370.0    # the label column
const LABEL_GAP    := 40.0     # label column -> first control
# 10% tighter was 30.6 and left the last row clipped. Trimmed further until the
# whole page fits between the bars with nothing to scroll.
# 20 -> 16 when the Cries slider made it thirteen rows: 13 * 53 + 12 * 16 = 881 of 896.
const ROW_GAP      := 16.0     # between rows
const OPTION_GAP   := 18.0     # between the buttons inside one row
const SLIDER_W     := 690.0
const VALUE_W      := 90.0     # the "80%" readout, wide enough for "100%"
const ROW_MIN_H    := 53.0     # so a slider row and a button row match

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

# ─── HOSTED IN A MATCH (the ESC pause menu) ──────────────────
# Main_Match_Core_Gameplay_Script opens this screen as an overlay on top of the
# live board. Both are set on the instance BEFORE it is added to the tree, so
# _ready() and _build_rows() already see them.
#
#   in_match_mode          drops the two rows that decide how the match in
#                          progress is played - Confusion rules and Burn rules -
#                          so nothing on screen implies they can be changed
#                          mid-match. Every other row stays live. It also keeps
#                          this screen's own music off, so the battle theme
#                          carries on underneath instead of two tracks at once.
#   close_overlay_callback the host's "put the pause menu back" call. When it is
#                          set, _leave() calls it instead of taking the map /
#                          main-menu return path, which would tear the match down.
var in_match_mode: bool = false
var close_overlay_callback: Callable = Callable()

@onready var audio_player := AudioStreamPlayer.new()

# Keep this in step with the `step` set on both HSliders below. Without the snap
# an off-step saved value (only reachable by hand-editing the save) would be
# nudged onto the nearest notch the moment the slider loaded it, and the screen
# would open already claiming an unsaved change.
const VOLUME_STEP := 5

# The cry played when the Cries slider is released. TWEAKABLE.
const CRY_PREVIEW_SPECIES := "025_Pikachu"

# ── THE TWO PSEUDO-SECTIONS ──────────────────────────────────
# The theme picker is two rows on screen but ONE stored value. These are the
# section names of those rows; neither has an entry in section_setters, and
# neither appears in `pending` — both read and write `pending["ui_theme"]`,
# recomposing the full id from whichever half was clicked.
const THEME_LOOK := "theme_look"
const THEME_MODE := "theme_mode"


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ISSUE #128: every sub-menu plays the same track. This screen had none, so it ran on
	# whatever the main menu was still playing behind it -- and once that overlap was fixed
	# (Main_Menu_Script.pause_music) it would have been left silent instead.
	# Not in a match: there the battle theme is still playing under the pause menu
	# and is the track that belongs to the screen the player is looking at.
	if not in_match_mode:
		add_child(audio_player)
		var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
		audio_player.stream = audio_stream
		audio_player.bus = SoundManagerScript.MUSIC_BUS
		if audio_stream != null:
			audio_stream.loop = true
			audio_player.play()

	theme = UIKit.base_theme()

	_build_chrome()
	_build_rows()

	section_setters = {
		"confusion":    GameState.set_confusion_rule,
		"burn":         GameState.set_burn_rule,
		"walking":      GameState.set_walking_speed,
		"animation":    GameState.set_animation_speed,
		"text_speed":   GameState.set_text_speed,
		"reduce_motion": GameState.set_reduce_motion,
		"intro_outro":  GameState.set_intro_outro,
		# The two volume entries wrap their setter because this screen counts in whole percents
		# while GameState (and the audio bus behind it) works in 0.0 - 1.0.
		"music_volume": func(percent: int) -> void: GameState.set_music_volume(percent / 100.0),
		"sfx_volume":   func(percent: int) -> void: GameState.set_sfx_volume(percent / 100.0),
		"cries_volume": func(percent: int) -> void: GameState.set_cries_volume(percent / 100.0),
		"ui_theme":     GameState.set_ui_theme,
		"hide_bars":    GameState.set_hide_bars,
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

	# ── WHY THIS SCROLLS NOW ─────────────────────────────────
	# The rows used to be a plain VBox centred in the band between the bars, which
	# worked while there were eight of them. The theme row alone is four wrapped
	# lines of buttons, and it grows every time a theme is added — the ten rows no
	# longer fit in the 896px band, and the last of them would simply have been
	# drawn past the footer.
	#
	# ROW_GAP and ROW_MIN_H are what keep the CURRENT thirteen rows on one screen with
	# nothing to scroll: 13 * 53 + 12 * 16 = 881 of the 896px available. A fourteenth
	# row means trimming one of those two again.
	#
	# A ScrollContainer takes the overflow. It only scrolls when there IS overflow,
	# so on a short list the block still sits centred exactly as before: the VBox
	# inside is SIZE_EXPAND_FILL with ALIGNMENT_CENTER, which centres it in the
	# viewport's height when the content is shorter than the band.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -BLOCK_W * 0.5
	scroll.offset_right = BLOCK_W * 0.5
	scroll.offset_top = header_h
	scroll.offset_bottom = -footer_h
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(ROW_GAP))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(body)

	# THE TWO MATCH-RULE ROWS ARE HIDDEN IN A MATCH. Both decide how the game
	# being played right now resolves a status condition, and the engine reads
	# them as it goes — a change part-way through would apply to the second half
	# of the match only. Rather than show them disabled, they are not built at
	# all, so the pause menu never implies they are on the table. Their entries in
	# pending/saved and section_setters stay exactly as they are: nothing touches
	# them, so Save sees no change and writes nothing.
	if not in_match_mode:
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
	# How fast a message box types its letters out. Its own row rather than a step on
	# the animation ladder above: reading pace and watching pace are different
	# preferences. Reduce motion still overrides it - the row below turns typing off
	# along with every other animation.
	_add_button_row(body, "text_speed", "Text speed", [
		["slow",   "Slow"],
		["medium", "Medium"],
		["fast",   "Fast"],
	], "(how fast messages type out)")
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
	_add_slider_row(body, "cries_volume", "Cries")
	_add_theme_row(body)
	# Stored as "no"/"yes" rather than off/on to match the question the row asks.
	_add_button_row(body, "hide_bars", "Hide header/footer", [
		["no",  "No"],
		["yes", "Yes"],
	], "(hides the banners only, nothing moves)")


## The colour picker, as TWO rows: the look, then Dark/Light.
##
## ── WHY IT IS SPLIT ──────────────────────────────────────────
## One row of sixteen buttons reading "Sunset Dark", "Sunset Light" and so on is
## a wall of long labels that wrapped to four lines. Eight short look names plus
## a Dark/Light pair says exactly the same thing in two rows, and the pair is a
## control the player already understands.
##
## Both rows write the same underlying value, `pending["ui_theme"]` — the full
## id, which is what GameState persists. Neither row is a setting of its own.
##
## Built from UITheme.theme_looks() / theme_modes(), so a look added to THEMES
## appears here with no edit to this file.
func _add_theme_row(parent: VBoxContainer) -> void:
	_add_picker_row(parent, THEME_LOOK, "Colour theme", UITheme.theme_looks(),
		"(changes every screen)")
	_add_picker_row(parent, THEME_MODE, "Mode", UITheme.theme_modes())


## One half of the theme picker. `section` is a pseudo-section: it has no entry
## in section_setters and is never saved on its own.
func _add_picker_row(parent: VBoxContainer, section: String, label_text: String,
		values: Array, sub_text: String = "") -> void:
	var row := _new_row(parent, label_text, sub_text)

	# A flow container, not an HBox: the look row holds eight buttons and will
	# hold more as themes are added, so it has to wrap rather than overflow.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(OPTION_GAP))
	flow.add_theme_constant_override("v_separation", int(OPTION_GAP * 0.5))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flow)

	var buttons: Dictionary = {}
	for value in values:
		var key := String(value)
		var btn := Button.new()
		btn.text = UITheme.theme_part_name(key)
		UIKit.style_button(btn, "secondary")   # _refresh_section repaints the chosen one
		flow.add_child(btn)
		buttons[key] = btn
	section_buttons[section] = buttons


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
		"text_speed":    GameState.text_speed_setting,
		"reduce_motion": GameState.reduce_motion_setting,
		"intro_outro":   GameState.intro_outro_setting,
		"music_volume":  _to_percent(GameState.music_volume_setting),
		"sfx_volume":    _to_percent(GameState.sfx_volume_setting),
		"cries_volume":  _to_percent(GameState.cries_volume_setting),
		"ui_theme":      GameState.ui_theme_setting,
		"hide_bars":     GameState.hide_bars_setting,
	}


func _to_percent(linear: float) -> int:
	return int(round(linear * 100.0 / VOLUME_STEP)) * VOLUME_STEP


func _input(event: InputEvent) -> void:
	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_leave()


# ─── Option selection ────────────────────────────────────────────────────────

func _on_option_pressed(section: String, option: String) -> void:
	# The two theme rows are halves of one value, so they take their own path.
	if section == THEME_LOOK or section == THEME_MODE:
		_on_theme_part_pressed(section, option)
		return

	if option == pending[section]:
		return
	pending[section] = option
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_section(section)
	_refresh_save_button()

	# ── THE ROWS THAT PREVIEW THEMSELVES ─────────────────────
	# Three rows change how THIS screen looks, so waiting for Save would mean
	# choosing blind. They apply live the way the volume sliders do, and Cancel
	# and Escape put them back (_revert_live_changes). Nothing is written to disk
	# until Save — live and saved are separate things.
	match section:
		"reduce_motion":
			GameState.set_reduce_motion(option, false)
			_refresh_chevrons()
		"hide_bars":
			GameState.set_hide_bars(option, false)
			# The bars' paint follows the signal, but the labels and the chrome
			# buttons are decided at build time, so the screen is rebuilt.
			_rebuild()


## Highlights whichever button in a section matches the pending selection.
## Applies half of a theme id. The other half is kept from what is already
## pending, so picking "Umbreon" keeps your Dark/Light choice and picking "Light"
## keeps your look.
func _on_theme_part_pressed(section: String, option: String) -> void:
	var current: String = pending["ui_theme"]
	var look := UITheme.theme_look_of(current)
	var mode := UITheme.theme_mode_of(current)
	if section == THEME_LOOK:
		look = option
	else:
		mode = option

	var composed := UITheme.compose_theme(look, mode)
	if composed == current:
		return
	pending["ui_theme"] = composed
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	# Live preview, same contract as the sliders: applied now, written on Save,
	# undone by Cancel. Every colour on this screen was read when it was built and
	# the button faces are baked art, so the only honest preview is a rebuild.
	GameState.set_ui_theme(composed, false)
	_rebuild()


func _refresh_section(section: String) -> void:
	# The two theme rows highlight against the halves of the composed id rather
	# than against a pending entry of their own.
	var chosen: String = ""
	match section:
		THEME_LOOK: chosen = UITheme.theme_look_of(pending["ui_theme"])
		THEME_MODE: chosen = UITheme.theme_mode_of(pending["ui_theme"])
		_:          chosen = String(pending[section])

	for option in section_buttons[section]:
		var btn: Button = section_buttons[section][option]
		UIKit.style_button(btn, "selected" if chosen == option else "secondary")


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
	# A sample cry, so the Cries row can be judged at its new level too.
	if value_changed and section == "cries_volume":
		SoundManagerScript.play_cry(CRY_PREVIEW_SPECIES)


func _apply_live_volume(section: String, percent: int) -> void:
	match section:
		"music_volume": GameState.set_music_volume(percent / 100.0, false)
		"sfx_volume":   GameState.set_sfx_volume(percent / 100.0, false)
		"cries_volume": GameState.set_cries_volume(percent / 100.0, false)


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
	# The two live-previewing rows. No rebuild here: every caller of this is on
	# its way off the screen, and rebuilding one that is about to be freed would
	# only flash the old theme back for a frame.
	if GameState.ui_theme_setting != saved["ui_theme"]:
		GameState.set_ui_theme(saved["ui_theme"], false)
	if GameState.hide_bars_setting != saved["hide_bars"]:
		GameState.set_hide_bars(saved["hide_bars"], false)


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

## Tears the screen down and builds it again under the current theme.
##
## Everything on this screen is built in code, which is what makes this safe —
## there is no scene layout to preserve. `audio_player` is the one child that is
## NOT UI and must survive, or the music stops when the player changes theme.
func _rebuild() -> void:
	for child in get_children():
		if child == audio_player:
			continue
		remove_child(child)      # before free: ISSUE #156's queue_free-without-remove_child trap
		child.queue_free()

	theme = UIKit.base_theme()
	section_buttons.clear()
	section_sliders.clear()

	_build_chrome()
	_build_rows()

	# Re-bind exactly as _ready does. `pending` and `saved` are untouched, so the
	# screen comes back showing the same selections it had.
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


func _on_cancel_pressed() -> void:
	_leave()


func _leave() -> void:
	_revert_live_changes()
	# Opened over a live match: the host owns this overlay and puts its own pause
	# menu back. Checked first — neither path below is survivable mid-match.
	if close_overlay_callback.is_valid():
		close_overlay_callback.call()
		return
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
