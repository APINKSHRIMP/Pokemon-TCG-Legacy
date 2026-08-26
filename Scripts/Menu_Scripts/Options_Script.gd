extends Control

# ISSUE #34: the Options screen. Seven sections, laid out as vertically stacked rows — each is a
# centred header with its options in a horizontal button row beneath it. A wider gap after Burn
# Rules and after Walking Speed splits them into three visual groups without needing sub-headers:
#   Confusion Rules + Burn Rules   — match rule variants. ISSUE #150: these SHARE ONE LINE now,
#                                    five buttons across, with a 100px group gap between the
#                                    third and fourth so the two settings still read as separate.
#   Walking Speed                  — overworld movement
#   Match Animation Speed          — in-match animations
#   Coin, Costume and Rewards …    — gift reveals only (no "skip": they ARE the payoff, and every
#                                    one is already click-skippable)
#   Pack Opening Animation Speed   — the pack sequence, with its own skip
#   Play Match Intro / Outro …     — a plain on/off, not a speed. The intro/outro is click-to-skip
#                                    already, so the only meaningful choice is whether it plays.
#   Music / Sound Effects Volume   — ISSUE #150: also ONE line now, both sliders halved in width
#                                    (880 -> 350) with a 140px gap between the music percentage
#                                    and the "Sound Effects Volume" label. See SLIDER SECTIONS.
#
# SLIDER SECTIONS. The two volume rows are the only controls here that are not a row of preset
# buttons, and they behave differently on purpose:
#   * They apply LIVE while you drag, so you can hear what you are choosing. Every other row on this
#     screen does nothing until Save.
#   * Save still owns persistence — dragging never touches Player_Current_Data.json.
#   * Because they apply live, Cancel and Escape have to put the volume back to the saved level on
#     the way out (_revert_live_volume). A button row needs no such undo.
# They share the pending/saved dictionaries and the Save button with everything else; only the
# refresh (move the grabber, rewrite the percentage) differs. Values are held here as whole percents
# 0-100 so the change detection stays an exact integer comparison — GameState stores 0.0-1.0.
#
# Message box colour used to be an eighth section here. It is no longer a player setting: each NPC
# and opponent carries its own `message_colour` in All_NPC_Constant_Data.json and the box is themed
# per speaker. See MessageBoxTheme.

# ─── Constants ───────────────────────────────────────────────────────────────

const THEME_SELECTED   := "res://UI_Themes/kenneyUI.tres"        # the option currently in effect
const THEME_UNSELECTED := "res://UI_Themes/kenneyUI-blue.tres"   # the other, pickable options
const THEME_SAVE_READY := "res://UI_Themes/kenneyUI-green.tres"  # save button with a pending change

# ─── State ───────────────────────────────────────────────────────────────────

# What the player has clicked but not yet saved, and what is currently persisted. One entry per
# section, keyed by section name.
var pending : Dictionary = {}
var saved   : Dictionary = {}

# section name -> { option value : Button }. Built in _ready() so every section refreshes and saves
# through the same code.
var section_buttons : Dictionary = {}

# section name -> { "slider": HSlider, "value_label": Label }. Kept apart from section_buttons
# because a slider row has no set of buttons to re-theme.
var section_sliders : Dictionary = {}

# section name -> the GameState setter that applies and persists it. Adding a section means adding
# one entry here, one to section_buttons (or section_sliders), and one to _current_values() —
# nothing else.
var section_setters : Dictionary = {}

# ─── Node references ─────────────────────────────────────────────────────────

@onready var audio_player = AudioStreamPlayer.new()

@onready var confusion_base_btn   : Button = $"CONFUSION/confusion_base_button"
@onready var confusion_fairer_btn : Button = $"CONFUSION/confusion_allowretreat_button"
@onready var confusion_ex_btn     : Button = $"CONFUSION/confusion_ex_button"

@onready var burn_base_btn : Button = $"BURN/burn_base_button"
@onready var burn_ex_btn   : Button = $"BURN/burn_ex_button"

@onready var walk_very_slow_btn : Button = $"WALKING/walking_very_slow_button"
@onready var walk_slow_btn      : Button = $"WALKING/walking_slow_button"
@onready var walk_normal_btn    : Button = $"WALKING/walking_normal_button"
@onready var walk_fast_btn      : Button = $"WALKING/walking_fast_button"

@onready var very_slow_btn : Button = $"SPEED/very_slow_button"
@onready var slow_btn      : Button = $"SPEED/slow_button"
@onready var normal_btn    : Button = $"SPEED/normal_button"
@onready var fast_btn      : Button = $"SPEED/fast_button"
@onready var skip_btn      : Button = $"SPEED/skip_button"

@onready var item_very_slow_btn : Button = $"ITEM/item_very_slow_button"
@onready var item_slow_btn      : Button = $"ITEM/item_slow_button"
@onready var item_normal_btn    : Button = $"ITEM/item_normal_button"
@onready var item_fast_btn      : Button = $"ITEM/item_fast_button"

# ISSUE #94: the pack row is deliberately one label out of step with the Match/Item rows above it —
# every preset was renamed one notch faster (the old "very slow" is this row's "slow", and so on), so
# there is no pack_very_slow_button and there IS a pack_very_fast_button. The multipliers behind them
# did not move; see PACK_SPEED_PRESETS in Game_State_Script.gd.
@onready var pack_slow_btn      : Button = $"PACK/pack_slow_button"
@onready var pack_normal_btn    : Button = $"PACK/pack_normal_button"
@onready var pack_fast_btn      : Button = $"PACK/pack_fast_button"
@onready var pack_very_fast_btn : Button = $"PACK/pack_very_fast_button"
@onready var pack_skip_btn      : Button = $"PACK/pack_skip_button"

@onready var intro_play_btn : Button = $"INTROOUTRO/intro_play_button"
@onready var intro_skip_btn : Button = $"INTROOUTRO/intro_skip_button"

@onready var music_slider     : HSlider = $"VOLUME/music_volume_slider"
@onready var music_value_lbl  : Label   = $"VOLUME/music_volume_value"
@onready var sfx_slider       : HSlider = $"VOLUME/sfx_volume_slider"
@onready var sfx_value_lbl    : Label   = $"VOLUME/sfx_volume_value"

@onready var save_btn   : Button = $"MAIN/options_save_button"
@onready var cancel_btn : Button = $"MAIN/options_cancel_button"

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

	section_buttons = {
		"confusion": {
			"base_set_confusion_rules":   confusion_base_btn,
			"fairer_confusion_rules":     confusion_fairer_btn,
			"modern_era_confusion_rules": confusion_ex_btn,
		},
		"burn": {
			"base_set_burn_rules":   burn_base_btn,
			"modern_era_burn_rules": burn_ex_btn,
		},
		"walking": {
			"very_slow": walk_very_slow_btn,
			"slow":      walk_slow_btn,
			"normal":    walk_normal_btn,
			"fast":      walk_fast_btn,
		},
		"speed": {
			"very_slow": very_slow_btn,
			"slow":      slow_btn,
			"normal":    normal_btn,
			"fast":      fast_btn,
			"skip":      skip_btn,
		},
		"item": {
			"very_slow": item_very_slow_btn,
			"slow":      item_slow_btn,
			"normal":    item_normal_btn,
			"fast":      item_fast_btn,
		},
		"pack": {
			"slow":      pack_slow_btn,
			"normal":    pack_normal_btn,
			"fast":      pack_fast_btn,
			"very_fast": pack_very_fast_btn,
			"skip":      pack_skip_btn,
		},
		"intro_outro": {
			"play": intro_play_btn,
			"skip": intro_skip_btn,
		},
	}

	section_sliders = {
		"music_volume": { "slider": music_slider, "value_label": music_value_lbl },
		"sfx_volume":   { "slider": sfx_slider,   "value_label": sfx_value_lbl },
	}

	# GameState owns both the live values and the writes to Player_Current_Data.json. The two volume
	# entries wrap their setter because this screen counts in whole percents while GameState (and the
	# audio bus behind it) works in 0.0 - 1.0.
	section_setters = {
		"confusion":    GameState.set_confusion_rule,
		"burn":         GameState.set_burn_rule,
		"walking":      GameState.set_walking_speed,
		"speed":        GameState.set_animation_speed,
		"item":         GameState.set_item_speed,
		"pack":         GameState.set_pack_speed,
		"intro_outro":  GameState.set_intro_outro,
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

	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	_refresh_save_button()


# ISSUE #138: a Button's real width is max(offset width, minimum size), so text that does not fit
# grows the Control past its right offset. "fairer retreat rules" needs ~306px (text + Kenney
# stylebox margin), which is how it ended up sliding under "ex era rules" in a 268px slot. Every
# button on the confusion/burn line is 320px wide now — check the text fits before narrowing them.
#
# ISSUE #150: Confusion+Burn share one line and Music+SFX share another, which freed two rows;
# that space went into the gaps, so every row has 44px of clear air below it instead of ~18.
# The content has to stay between the top border (ends y=107) and the bottom border (starts y=977).
# Row tops are 116 / 249 / 382 / 515 / 648 / 781 with the volume line at 914..956.

# The persisted value of every section, read straight off GameState.
func _current_values() -> Dictionary:
	return {
		"confusion":    GameState.confusion_rule_setting,
		"burn":         GameState.burn_rule_setting,
		"walking":      GameState.walking_speed_setting,
		"speed":        GameState.animation_speed_setting,
		"item":         GameState.item_speed_setting,
		"pack":         GameState.pack_speed_setting,
		"intro_outro":  GameState.intro_outro_setting,
		"music_volume": _to_percent(GameState.music_volume_setting),
		"sfx_volume":   _to_percent(GameState.sfx_volume_setting),
	}


# GameState's 0.0 - 1.0 level as a whole percent, snapped to the notch size the sliders use. Without
# the snap an off-step saved value (only reachable by hand-editing the save) would be nudged onto the
# nearest notch the moment the slider loaded it, and the screen would open already claiming a change.
# Keep this in step with `step` on both HSliders in Options_Scene.tscn.
const VOLUME_STEP := 5

func _to_percent(linear: float) -> int:
	return int(round(linear * 100.0 / VOLUME_STEP)) * VOLUME_STEP


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_leave()

# ─── Option selection ────────────────────────────────────────────────────────

func _on_option_pressed(section: String, option: String) -> void:
	if option == pending[section]:
		return
	pending[section] = option
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_section(section)
	_refresh_save_button()


# Highlights whichever button in a section matches the pending selection.
func _refresh_section(section: String) -> void:
	var selected   := load(THEME_SELECTED)
	var unselected := load(THEME_UNSELECTED)
	for option in section_buttons[section]:
		section_buttons[section][option].theme = selected if pending[section] == option else unselected

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


# Puts the audio buses back to the last saved levels. Called when leaving without saving — without
# this, a cancelled drag would keep its volume until the next boot re-read the save file.
func _revert_live_volume() -> void:
	for section in section_sliders:
		_apply_live_volume(section, saved[section])


# The save button only lights up (green, enabled) while there is an unsaved change in any section.
func _refresh_save_button() -> void:
	var has_change := false
	for section in pending:
		if pending[section] != saved[section]:
			has_change = true
			break
	save_btn.disabled = not has_change
	save_btn.theme = load(THEME_SAVE_READY) if has_change else load(THEME_SELECTED)

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
	_revert_live_volume()
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
