extends Control

# ISSUE #34: the Options screen. Only the "Animation speed" section is wired up so far — the
# Confusion Rules / Burn Rules / Message box style sections are laid out in the scene but have no
# backing setting yet, so their buttons are left inert on purpose.

# ─── Constants ───────────────────────────────────────────────────────────────

const THEME_SELECTED   := "res://UI_Themes/kenneyUI.tres"        # the option currently in effect
const THEME_UNSELECTED := "res://UI_Themes/kenneyUI-blue.tres"   # the other, pickable options
const THEME_SAVE_READY := "res://UI_Themes/kenneyUI-green.tres"  # save button with a pending change

# ─── State ───────────────────────────────────────────────────────────────────

# The preset the player has clicked but not yet saved, and the one currently persisted.
var pending_speed : String = ""
var saved_speed   : String = ""

# ─── Node references ─────────────────────────────────────────────────────────

# NOTE: in the scene the bottom two SPEED buttons are named the opposite way round to their labels
# — "skip_button" reads "fast" and "fast_button" reads "skip animations". Wired to match the
# on-screen text, which is what the player actually sees.
@onready var slow_btn   : Button = $"SPEED/slow_button"
@onready var fast_btn   : Button = $"SPEED/skip_button"
@onready var skip_btn   : Button = $"SPEED/fast_button"
@onready var save_btn   : Button = $"MAIN/options_save_button"
@onready var cancel_btn : Button = $"MAIN/options_cancel_button"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	saved_speed   = GameState.animation_speed_setting
	pending_speed = saved_speed

	slow_btn.pressed.connect(_on_speed_pressed.bind("slow"))
	fast_btn.pressed.connect(_on_speed_pressed.bind("fast"))
	skip_btn.pressed.connect(_on_speed_pressed.bind("skip"))
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_refresh_speed_buttons()
	_refresh_save_button()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_leave()

# ─── Animation speed ─────────────────────────────────────────────────────────

func _on_speed_pressed(preset: String) -> void:
	if preset == pending_speed:
		return
	pending_speed = preset
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_speed_buttons()
	_refresh_save_button()


# Highlights whichever of the three buttons matches the pending selection.
func _refresh_speed_buttons() -> void:
	var selected   := load(THEME_SELECTED)
	var unselected := load(THEME_UNSELECTED)
	slow_btn.theme = selected if pending_speed == "slow" else unselected
	fast_btn.theme = selected if pending_speed == "fast" else unselected
	skip_btn.theme = selected if pending_speed == "skip" else unselected


# The save button only lights up (green, enabled) while there is an unsaved change.
func _refresh_save_button() -> void:
	var has_change := pending_speed != saved_speed
	save_btn.disabled = not has_change
	save_btn.theme = load(THEME_SAVE_READY) if has_change else load(THEME_SELECTED)

# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	if pending_speed == saved_speed:
		return
	# GameState owns both the live multipliers and the write to Player_Current_Data.json.
	GameState.set_animation_speed(pending_speed)
	saved_speed = pending_speed
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh_save_button()


func _on_cancel_pressed() -> void:
	_leave()


func _leave() -> void:
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
