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
var quit_dialog: ConfirmationDialog = null
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


func _show_quit_dialog() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		return
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Quit Game"
	quit_dialog.dialog_text = "Are you sure you want to quit?"
	quit_dialog.ok_button_text = "Yes"
	quit_dialog.cancel_button_text = "No"
	add_child(quit_dialog)
	quit_dialog.confirmed.connect(func(): get_tree().quit())
	quit_dialog.canceled.connect(_on_quit_cancelled)
	quit_dialog.popup_centered()


func _on_quit_cancelled() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		quit_dialog.queue_free()
	quit_dialog = null
