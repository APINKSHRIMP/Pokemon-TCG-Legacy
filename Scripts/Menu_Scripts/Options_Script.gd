extends Control

# ISSUE #34: the Options screen. Three sections are wired up — "Animation speed", "Confusion Rules"
# and "Burn Rules". The "Message box style" section is laid out in the scene but has no backing
# setting yet, so its area is left inert on purpose.

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

# ─── Node references ─────────────────────────────────────────────────────────

# NOTE: in the scene the bottom two SPEED buttons are named the opposite way round to their labels
# — "skip_button" reads "fast" and "fast_button" reads "skip animations". Wired to match the
# on-screen text, which is what the player actually sees.
@onready var slow_btn   : Button = $"SPEED/slow_button"
@onready var fast_btn   : Button = $"SPEED/skip_button"
@onready var skip_btn   : Button = $"SPEED/fast_button"

@onready var confusion_base_btn   : Button = $"CONFUSION/confusion_base_button"
@onready var confusion_fairer_btn : Button = $"CONFUSION/confusion_allowretreat_button"
@onready var confusion_ex_btn     : Button = $"CONFUSION/confusion_ex_button"

@onready var burn_base_btn : Button = $"BURN/burn_base_button"
@onready var burn_ex_btn   : Button = $"BURN/burn_ex_button"

@onready var save_btn   : Button = $"MAIN/options_save_button"
@onready var cancel_btn : Button = $"MAIN/options_cancel_button"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	section_buttons = {
		"speed": {
			"slow": slow_btn,
			"fast": fast_btn,
			"skip": skip_btn,
		},
		"confusion": {
			"base_set_confusion_rules":   confusion_base_btn,
			"fairer_confusion_rules":     confusion_fairer_btn,
			"modern_era_confusion_rules": confusion_ex_btn,
		},
		"burn": {
			"base_set_burn_rules":   burn_base_btn,
			"modern_era_burn_rules": burn_ex_btn,
		},
	}

	saved["speed"]     = GameState.animation_speed_setting
	saved["confusion"] = GameState.confusion_rule_setting
	saved["burn"]      = GameState.burn_rule_setting
	pending = saved.duplicate()

	for section in section_buttons:
		for option in section_buttons[section]:
			section_buttons[section][option].pressed.connect(_on_option_pressed.bind(section, option))
		_refresh_section(section)

	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	_refresh_save_button()


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

	# GameState owns both the live values and the writes to Player_Current_Data.json.
	if pending["speed"] != saved["speed"]:
		GameState.set_animation_speed(pending["speed"])
		saved_anything = true
	if pending["confusion"] != saved["confusion"]:
		GameState.set_confusion_rule(pending["confusion"])
		saved_anything = true
	if pending["burn"] != saved["burn"]:
		GameState.set_burn_rule(pending["burn"])
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
