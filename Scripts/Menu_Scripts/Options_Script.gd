extends Control

# ISSUE #34: the Options screen. Seven sections, laid out as vertically stacked rows — each is a
# centred header with its options in a horizontal button row beneath it. A wider gap after Burn
# Rules and after Walking Speed splits them into three visual groups without needing sub-headers:
#   Confusion Rules / Burn Rules   — match rule variants
#   Walking Speed                  — overworld movement
#   Match Animation Speed          — in-match animations
#   Coin, Costume and Rewards …    — gift reveals only (no "skip": they ARE the payoff, and every
#                                    one is already click-skippable)
#   Pack Opening Animation Speed   — the pack sequence, with its own skip
#   Play Match Intro / Outro …     — a plain on/off, not a speed. The intro/outro is click-to-skip
#                                    already, so the only meaningful choice is whether it plays.

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

# section name -> the GameState setter that applies and persists it. Adding a section means adding
# one entry here, one to section_buttons, and one to _current_values() — nothing else.
var section_setters : Dictionary = {}

# ─── Node references ─────────────────────────────────────────────────────────

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

@onready var pack_very_slow_btn : Button = $"PACK/pack_very_slow_button"
@onready var pack_slow_btn      : Button = $"PACK/pack_slow_button"
@onready var pack_normal_btn    : Button = $"PACK/pack_normal_button"
@onready var pack_fast_btn      : Button = $"PACK/pack_fast_button"
@onready var pack_skip_btn      : Button = $"PACK/pack_skip_button"

@onready var intro_play_btn : Button = $"INTROOUTRO/intro_play_button"
@onready var intro_skip_btn : Button = $"INTROOUTRO/intro_skip_button"

@onready var save_btn   : Button = $"MAIN/options_save_button"
@onready var cancel_btn : Button = $"MAIN/options_cancel_button"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
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
			"very_slow": pack_very_slow_btn,
			"slow":      pack_slow_btn,
			"normal":    pack_normal_btn,
			"fast":      pack_fast_btn,
			"skip":      pack_skip_btn,
		},
		"intro_outro": {
			"play": intro_play_btn,
			"skip": intro_skip_btn,
		},
	}

	# GameState owns both the live values and the writes to Player_Current_Data.json.
	section_setters = {
		"confusion":   GameState.set_confusion_rule,
		"burn":        GameState.set_burn_rule,
		"walking":     GameState.set_walking_speed,
		"speed":       GameState.set_animation_speed,
		"item":        GameState.set_item_speed,
		"pack":        GameState.set_pack_speed,
		"intro_outro": GameState.set_intro_outro,
	}

	saved = _current_values()
	pending = saved.duplicate()

	for section in section_buttons:
		for option in section_buttons[section]:
			section_buttons[section][option].pressed.connect(_on_option_pressed.bind(section, option))
		_refresh_section(section)

	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	_refresh_save_button()


# The persisted value of every section, read straight off GameState.
func _current_values() -> Dictionary:
	return {
		"confusion":   GameState.confusion_rule_setting,
		"burn":        GameState.burn_rule_setting,
		"walking":     GameState.walking_speed_setting,
		"speed":       GameState.animation_speed_setting,
		"item":        GameState.item_speed_setting,
		"pack":        GameState.pack_speed_setting,
		"intro_outro": GameState.intro_outro_setting,
	}


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
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
