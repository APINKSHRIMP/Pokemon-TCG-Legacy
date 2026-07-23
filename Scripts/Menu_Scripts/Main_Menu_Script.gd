extends Node

@onready var audio_player = AudioStreamPlayer.new()

const DEFAULT_MAP_SCENE = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"

# Full node paths (relative to scene root) → scene to load.
# "close/map_mode_background" is handled specially to return to the saved map.
const SCENE_MAP = {
	"deck/deck_mode_background":       "res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn",
	"close/map_mode_background":       DEFAULT_MAP_SCENE,
	"info/info_mode_background":       "res://Scenes/Main_Menu_Scenes/Info_Scene.tscn",
	"costume/costume_mode_background": "res://Scenes/Main_Menu_Scenes/Costume_Scene.tscn",
	"options/options_mode_background": "res://Scenes/Main_Menu_Scenes/Options_Scene.tscn",
	"coin/coin_case_mode_background":  "res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn",
	"sleeves/sleeves_mode_background": "res://Scenes/Main_Menu_Scenes/Sleeves_Scene.tscn",
}

# Icons overlaid on panel backgrounds — must pass mouse events through so the background receives them.
const OVERLAY_ICONS = [
	"deck/deck_icon",
	"info/info_icon",
	"costume/costumes_icon",
	"coin/coin_icon",
	"sleeves/sleeves_icon",
	"options/options_icon",
]

var tweens: Dictionary = {}
var quit_dialog: CanvasLayer = null
var is_overlay: bool = false
var close_overlay_callback: Callable = Callable()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			if is_overlay:
				_close_overlay()
			else:
				_return_to_world_map()


func _return_to_world_map() -> void:
	var target: String = GameState.menu_return_scene_path if GameState.has_menu_return_state else DEFAULT_MAP_SCENE
	SceneCache.change_scene(target)


func _close_overlay() -> void:
	if close_overlay_callback.is_valid():
		close_overlay_callback.call()


func _ready() -> void:
	# ISSUE #52 FIX: a standalone Main Menu (entered by closing a sub-menu) has no world map behind its
	# transparent background, so it renders black. Redirect to the saved map scene and reopen the menu
	# as an overlay on top of it — this also reloads the map so any world-changing options take effect.
	if not is_overlay and GameState.has_menu_return_state:
		print("ISSUE #52 FIX ACTIVE: reloading world map behind the main menu")
		GameState.reopen_menu_overlay = true
		SceneCache.change_scene(GameState.menu_return_scene_path)
		return

	add_child(audio_player)
	var audio_stream = load("res://Audio/BGM/main_menu_music (TCG GB Menu Theme).ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	if audio_stream != null:
		audio_stream.loop = true
		audio_player.play()

	var starter_collected = GameState.progress.get("player_collected_starter_box", false)
	var locked_modes := {}
	if not starter_collected:
		locked_modes["deck/deck_mode_background"]      = "deck/deck_mode_label"
		locked_modes["coin/coin_case_mode_background"] = "coin/coin_case_label"
		# ISSUE #29 FIX: sleeves is also unavailable until the starter box is collected.
		locked_modes["sleeves/sleeves_mode_background"] = "sleeves/sleeves_label"
		print("ISSUE #29 FIX ACTIVE: sleeves menu locked pre-starter-box")

	await get_tree().process_frame

	# Overlay icons must not intercept mouse events so the background TextureRect receives them
	for icon_path in OVERLAY_ICONS:
		var icon = get_node_or_null(icon_path)
		if icon is Control:
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Wire up all main panel backgrounds.
	# Hover/click signals go on the background rect (the large hover target), but the
	# tween is applied to the parent container so the icon scales with the box.
	for node_path in SCENE_MAP.keys():
		var rect = get_node_or_null(node_path) as TextureRect
		if rect == null:
			continue
		var container := rect.get_parent() as Control
		# Pivot = visual centre of the background box in the container's local space
		container.pivot_offset = rect.position + rect.size * 0.5

		if locked_modes.has(node_path):
			rect.modulate = Color(0.4, 0.4, 0.4, 1.0)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			rect.mouse_entered.connect(_on_mode_hover.bind(container, true))
			rect.mouse_exited.connect(_on_mode_hover.bind(container, false))
			rect.gui_input.connect(_on_mode_clicked.bind(node_path))

	# Exit button: same pattern — hover on the icon rect, tween the container
	var exit_rect = get_node_or_null("exit/exit_game_button") as TextureRect
	if exit_rect:
		var exit_container := exit_rect.get_parent() as Control
		exit_container.pivot_offset = exit_rect.position + exit_rect.size * 0.5
		exit_rect.mouse_entered.connect(_on_mode_hover.bind(exit_container, true))
		exit_rect.mouse_exited.connect(_on_mode_hover.bind(exit_container, false))
		exit_rect.gui_input.connect(_on_exit_clicked)

	# Grey out labels for locked modes
	for bg_path in locked_modes.keys():
		var lbl = get_node_or_null(locked_modes[bg_path]) as Label
		if lbl:
			lbl.modulate = Color(0.4, 0.4, 0.4, 1.0)

	# All labels pass mouse events through so they never block hover/click on the background
	var label_paths = [
		"deck/deck_mode_label",
		"close/map_mode_label",
		"options/options_mode_label",
		"info/info_label",
		"costume/costumes_label",
		"coin/coin_case_label",
		"sleeves/sleeves_label",
		"exit/exit_game_label",
	]
	for lp in label_paths:
		var lbl = get_node_or_null(lp) as Label
		if lbl:
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mode_hover(container: Control, hovered: bool) -> void:
	var key = container.name
	if tweens.has(key) and tweens[key]:
		tweens[key].kill()

	if hovered:
		var tween = create_tween()
		tween.set_loops()
		tweens[key] = tween
		tween.tween_property(container, "modulate", Color.WHITE * 1.2, 0.2)
		tween.parallel().tween_property(container, "scale", Vector2(1.02, 1.02), 0.2)
		tween.tween_property(container, "modulate", Color.WHITE * 1.0, 0.3)
		tween.parallel().tween_property(container, "scale", Vector2(1.0, 1.0), 0.2)
	else:
		tweens.erase(key)
		container.modulate = Color.WHITE
		container.scale = Vector2(1.0, 1.0)


func _on_mode_clicked(event: InputEvent, node_path: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
		if node_path == "close/map_mode_background":
			if is_overlay:
				_close_overlay()
			else:
				_return_to_world_map()
			return
		SceneCache.change_scene(SCENE_MAP[node_path])


func _on_exit_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
		_show_quit_dialog()


# ISSUE #30 FIX: build the quit confirmation with the same styled popup as the deck builder's
# "Empty deck?" confirm (kenney-themed centred panel, red confirm + green cancel) instead of the
# default engine ConfirmationDialog.
func _show_quit_dialog() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		return
	print("ISSUE #30 FIX ACTIVE: styled quit confirmation")
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")

	quit_dialog = CanvasLayer.new()
	quit_dialog.layer = 100
	add_child(quit_dialog)

	# Dim the screen behind the popup
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	quit_dialog.add_child(overlay)

	# Centered panel
	var panel := PanelContainer.new()
	if kenney_theme:
		panel.theme = kenney_theme
	panel.custom_minimum_size = Vector2(460, 220)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -230
	panel.offset_top    = -110
	panel.offset_right  = 230
	panel.offset_bottom = 110
	quit_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = "Quit the game?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 24)
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = "Quit"
	yes_btn.custom_minimum_size = Vector2(130, 45)
	var red_theme = load("res://UI_Themes/kenneyUI-red.tres")
	if red_theme:
		yes_btn.theme = red_theme
	yes_btn.pressed.connect(func(): get_tree().quit())
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.custom_minimum_size = Vector2(130, 45)
	var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
	if green_theme:
		no_btn.theme = green_theme
	no_btn.pressed.connect(_on_quit_cancelled)
	btn_row.add_child(no_btn)


func _on_quit_cancelled() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		quit_dialog.queue_free()
	quit_dialog = null
