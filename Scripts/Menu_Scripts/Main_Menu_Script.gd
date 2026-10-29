extends Node

@onready var audio_player = AudioStreamPlayer.new()

const DEFAULT_MAP_SCENE = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const TITLE_SCENE = "res://Scenes/Intro_And_Animation_Scenes/Game_Start_Load_Splash_Scene.tscn"

# Quit dialog — tweakable.
const QUIT_PANEL_SIZE := Vector2(520, 380)
const QUIT_BTN_W := 360.0       # all three buttons share one width
const QUIT_BTN_GAP := 14
const QUIT_FADE := 0.8          # Quit to Main Menu: the game fading to black
const QUIT_FADE_REDUCED := 0.2

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
var _quitting: bool = false     # Quit to Main Menu is fading out; ignore everything


func _input(event: InputEvent) -> void:
	if _quitting:
		get_viewport().set_input_as_handled()
		return

	# The quit confirmation owns the keys while it is up: accept says Quit to
	# Desktop, cancel is Return. Without this, Escape/Enter closed the whole menu
	# out from under the dialog instead of answering it.
	if quit_dialog != null and is_instance_valid(quit_dialog):
		if UIInput.is_cancel(event):
			get_viewport().set_input_as_handled()
			_on_quit_cancelled()
		elif UIInput.is_accept(event):
			get_viewport().set_input_as_handled()
			get_tree().quit()
		return

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


# ============================================================
# MUSIC (ISSUE #128)
# ============================================================
# Since sub-menus became overlays (ISSUE #52) the main menu is merely HIDDEN behind one, not
# unloaded -- so its AudioStreamPlayer carried on playing underneath the sub-menu's own track
# and the two overlapped. BaseMapScene pauses us on the way into a sub-menu and resumes on the
# way back. Paused rather than stopped so the theme picks up where it left off.
func pause_music() -> void:
	if audio_player != null and is_instance_valid(audio_player) and audio_player.playing:
		audio_player.stream_paused = true


func resume_music() -> void:
	if audio_player != null and is_instance_valid(audio_player):
		audio_player.stream_paused = false


## ANY SCREEN SHAPE: the tile mosaic is authored at 1920x1080 and fills it. On another
## canvas each tile BACKGROUND stretches to the same fraction of the screen, so the
## mosaic still fills it edge to edge; the icons and labels on the tiles keep their
## place on the tile (centre scaled) and only grow when both directions grew, so they
## never distort. The dim behind it covers the whole canvas.
func _fit_tiles_to_screen() -> void:
	var bg := get_node_or_null("black_background") as Control
	if bg != null:
		bg.offset_right = UIKit.screen_w() + 1.0
		bg.offset_bottom = UIKit.screen_h()
	var extra: Vector2 = UIKit.screen_extra()
	if extra == Vector2.ZERO:
		return
	var spread := UIKit.screen_size() / Vector2(UIKit.SCREEN_W, UIKit.SCREEN_H)
	var grow: float = minf(spread.x, spread.y)
	for group in get_children():
		if not (group is Control) or group == bg:
			continue
		var origin: Vector2 = (group as Control).position
		# The small Close / Exit buttons (icon + label, no big tile) move as ONE unit,
		# unstretched, so the label stays beside its icon.
		var bbox := Rect2()
		var first := true
		for child in group.get_children():
			if child is Control:
				var r := Rect2((child as Control).position, (child as Control).size)
				bbox = r if first else bbox.merge(r)
				first = false
		if not first and bbox.size.y < 100.0:
			var centre_g: Vector2 = origin + bbox.get_center()
			var shift: Vector2 = centre_g * spread - centre_g
			for child in group.get_children():
				if child is Control:
					(child as Control).position += shift
			continue
		for child in group.get_children():
			if not (child is Control):
				continue
			var c := child as Control
			var centre: Vector2 = origin + c.position + c.size * 0.5
			var is_tile: bool = String(c.name).ends_with("_background") or c.name == "exit_game_button"
			var new_size: Vector2 = c.size * (spread if is_tile else Vector2(grow, grow))
			if is_tile and c is TextureRect:
				(c as TextureRect).stretch_mode = TextureRect.STRETCH_SCALE
			c.size = new_size
			c.position = centre * spread - new_size * 0.5 - origin
	print("SCREEN LAYOUT: pause menu tiles spread ", spread, ", grown ", snappedf(grow, 0.01))


func _ready() -> void:
	# ISSUE #52 FIX: a standalone Main Menu (entered by closing a sub-menu) has no world map behind its
	# transparent background, so it renders black. Redirect to the saved map scene and reopen the menu
	# as an overlay on top of it — this also reloads the map so any world-changing options take effect.
	if not is_overlay and GameState.has_menu_return_state:
		GameState.reopen_menu_overlay = true
		SceneCache.change_scene(GameState.menu_return_scene_path)
		return

	# Predict the next screen: while the player reads the six tiles, the deck builder's,
	# coin case's, costumes' and sleeves' art loads on background threads, so whichever
	# one they pick opens from memory.
	SceneCache.predict_menu_screens.call_deferred()

	add_child(audio_player)
	var audio_stream = load(SoundManagerScript.BGM_MAIN_MENU)
	audio_player.stream = audio_stream
	audio_player.bus = SoundManagerScript.MUSIC_BUS
	if audio_stream != null:
		audio_stream.loop = true
		audio_player.play()

	_fit_tiles_to_screen()

	# Deck, coin case and sleeves open up once Olly's intro match is over.
	var locked_modes := {}
	if not GameState.has_flag(GameState.INTRO_DONE_FLAG):
		locked_modes["deck/deck_mode_background"]      = "deck/deck_mode_label"
		locked_modes["coin/coin_case_mode_background"] = "coin/coin_case_label"
		locked_modes["sleeves/sleeves_mode_background"] = "sleeves/sleeves_label"

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
		# ISSUE #52 FIX (retest): when the menu is an overlay over a live map, open the sub-menu as a
		# further overlay so the map is never unloaded — coming back is then instant.
		if is_overlay and GameState.open_sub_menu(SCENE_MAP[node_path]):
			return
		SceneCache.change_scene(SCENE_MAP[node_path])


func _on_exit_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
		_show_quit_dialog()


# ISSUE #30 FIX: build the quit confirmation with the same styled popup as the deck builder's
# "Empty deck?" confirm rather than the default engine ConfirmationDialog.
#
# ISSUE #205: IT IS THE SPECTRUM NIGHT DIALOG NOW. The main menu itself is still out
# of scope for the UI overhaul (A2), and the dialog was deliberately left on the
# Kenney theme so it would not be half-converted — but it is the one piece of that
# screen the player interacts with after the rest of the game changed, so it stood
# out as the odd one. The whole dialog is converted here in one go: the opaque
# modal panel, the button variants and the dim behind it all match the deck
# builder's confirm exactly. Quit to Desktop is DANGER, Quit to Main Menu the
# softer negative red, and Return the positive green.
func _show_quit_dialog() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		return

	quit_dialog = CanvasLayer.new()
	quit_dialog.layer = 100
	add_child(quit_dialog)

	# Dim the screen behind the popup. 0.78, matching every other modal in the game
	# — at 0.6 the menu behind competed with the question.
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	quit_dialog.add_child(overlay)

	# Centred panel. make_modal_panel, NOT make_panel: the translucent surface is
	# for grouping content on a screen, and over a dimmed menu it reads as a ghost.
	var panel := UIKit.make_modal_panel()
	panel.custom_minimum_size = QUIT_PANEL_SIZE
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -QUIT_PANEL_SIZE.x * 0.5
	panel.offset_top    = -QUIT_PANEL_SIZE.y * 0.5
	panel.offset_right  = QUIT_PANEL_SIZE.x * 0.5
	panel.offset_bottom = QUIT_PANEL_SIZE.y * 0.5
	quit_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var msg := Label.new()
	UIKit.set_label(msg, "body", "Quit the game?", "field_fg")
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	# One column, most final at the top. Return is the positive way out (green);
	# the two quits are red, Desktop the harder red as it closes the game.
	var btn_col := VBoxContainer.new()
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", QUIT_BTN_GAP)
	vbox.add_child(btn_col)

	var desktop_btn := UIKit.make_footer_button("Quit to Desktop", "danger")
	desktop_btn.pressed.connect(func(): get_tree().quit())
	var title_btn := UIKit.make_footer_button("Quit to Main Menu", "negative")
	title_btn.pressed.connect(_quit_to_title)
	var return_btn := UIKit.make_footer_button("Return", "primary")
	return_btn.pressed.connect(_on_quit_cancelled)
	for b in [desktop_btn, title_btn, return_btn]:
		b.custom_minimum_size.x = QUIT_BTN_W
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn_col.add_child(b)


## Back to the boot splash, already sitting on "Press any key". The game fades to
## black here and the splash fades in out of it. Everything worth keeping is on
## disk already — opening this menu saved the player's spot — so Continue Game
## puts them back exactly where they were.
func _quit_to_title() -> void:
	if _quitting:
		return
	_quitting = true
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	audio_player.stop()
	SoundManagerScript.stop_bgm()

	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under it takes a click mid-fade
	layer.add_child(black)

	var seconds: float = QUIT_FADE_REDUCED if UITheme.motion_reduced() else QUIT_FADE
	var tween := create_tween()
	tween.tween_property(black, "color:a", 1.0, seconds)
	await tween.finished

	# The overlay host and the paused world are session state about the map that is
	# about to go; the next map's initialise() would clear them, but the splash and
	# save select come first.
	GameState.clear_menu_return_state()
	GameState.menu_overlay_host = null
	MapManager.set_overworld_paused(false)
	GameState.skip_title_intro = true
	SceneCache.change_scene(TITLE_SCENE)


func _on_quit_cancelled() -> void:
	if quit_dialog != null and is_instance_valid(quit_dialog):
		quit_dialog.queue_free()
	quit_dialog = null
