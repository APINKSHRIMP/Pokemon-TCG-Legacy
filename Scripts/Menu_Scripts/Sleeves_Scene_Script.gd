extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SLEEVE_FOLDER  := "res://Image_Assets/Sleeves"          # full-size originals (.jpg or .png)
const SLEEVE_SMALL_FOLDER := "res://Image_Assets/Sleeves/small" # 412px-tall .jpg copies used for the grid
const COLUMNS        := 8
const CELL_SIZE      := Vector2(234, 327)
const H_SEP          := 2
const V_SEP          := 2

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
var PLAYER_PROGRESS_PATH: String:
	get: return GameState.PROGRESS_PATH

# ─── State ───────────────────────────────────────────────────────────────────

# The selected/saved items are the wrapper Controls, not TextureRects directly
var selected_sleeve  : Control = null
var saved_sleeve_name : String = ""

var _active_tween     : Tween = null
var _last_clicked     : Control = null

# Flat set of owned sleeve base names (no extension), e.g. {"Ditto": true}
var _owned_sleeves    : Dictionary = {}

# ─── Owned-only filter ───────────────────────────────────────────────────────
# The scene always opens with unowned sleeves hidden so the grid only builds the handful
# the player actually owns rather than ~593 black placeholders. Deliberately NOT persisted
# or cached — every visit starts hidden and the player presses Show if they want the lot.
var _hide_unowned     : bool = true
var _is_rebuilding    : bool = false

# ─── Zoom state ──────────────────────────────────────────────────────────────
var zoom_overlay       : CanvasLayer = null
var is_zoomed          : bool = false
var last_zoomed_sleeve : Control = null
# ISSUE #98: hold-to-preview, matching the deck builder. While Space is held _process re-reads the
# hovered sleeve every frame; the preview is sticky over the gaps between sleeves so sliding across
# the grid never flashes the UI back on. Only releasing Space closes it.
var space_held         : bool = false
var zoomed_sleeve      : Control = null
var zoom_image         : TextureRect = null

# ─── Loading state (ISSUE #32) ────────────────────────────────────────────────
var _loading_overlay   : MenuLoadingOverlay = MenuLoadingOverlay.new()
var _is_loading        : bool = false
var _load_cancelled    : bool = false

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"sleeves_grid_container"
@onready var save_btn    : Button        = $"sleeves_save_button"
@onready var cancel_btn  : Button        = $"sleeves_cancel_button"
@onready var hide_btn    : Button        = $"hide_button"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)
	var audio_stream = load("res://Audio/BGM/coin_mode (TCG GB Water Club).ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	audio_player.stream.loop = true
	audio_player.play()

	_load_owned_sleeves_list()
	_load_player_data()

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	hide_btn.pressed.connect(_on_hide_pressed)
	_refresh_hide_button()

	_wrap_grid_in_scroll_container()
	# ISSUE #32: block input behind a loading overlay while the (potentially large) sleeve grid builds.
	# The hide button sits in the overlay's unblocked top strip, so disable it while a build runs.
	hide_btn.disabled = true
	_show_loading_overlay()
	await get_tree().process_frame
	await _load_sleeves()
	_hide_loading_overlay()
	if not is_inside_tree():
		return
	hide_btn.disabled = false

	if saved_sleeve_name != "":
		_select_sleeve_by_name(saved_sleeve_name)


# ─── Loading overlay (ISSUE #32) ──────────────────────────────────────────────

# Semi-transparent black box with a spinning square, shown while the grid loads. Blocks mouse input
# (the dim ColorRect uses MOUSE_FILTER_STOP); Escape still cancels via _input.
# ISSUE #32 (retest): this was an inline copy of the overlay that the other three library menus got
# via MenuLoadingOverlay, so every geometry/opacity tweak had to be made twice and the two drifted.
# Sleeves now uses the shared class as well — all tuning lives in Menu_Loading_Overlay.gd.
func _show_loading_overlay() -> void:
	_is_loading = true
	_load_cancelled = false
	_loading_overlay.show_for_library(self)

func _hide_loading_overlay() -> void:
	_is_loading = false
	_loading_overlay.hide()


# ─── Data loading ────────────────────────────────────────────────────────────

func _load_owned_sleeves_list() -> void:
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("Sleeves: cannot open " + PLAYER_PROGRESS_PATH)
		return
	var raw_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(raw_text)
	if not data is Dictionary:
		push_error("Sleeves: progress JSON did not parse to Dictionary")
		return
	if not data.has("sleeves"):
		push_error("Sleeves: 'sleeves' key missing from progress")
		return

	for sleeve_name in data["sleeves"]:
		_owned_sleeves[String(sleeve_name)] = true


func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Sleeves: cannot open " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_text)
	if data is Dictionary and data.has("sleeve"):
		saved_sleeve_name = data["sleeve"]


# ─── Scroll container setup ──────────────────────────────────────────────────

func _wrap_grid_in_scroll_container() -> void:
	var parent = grid.get_parent()

	var scroll := ScrollContainer.new()
	scroll.name = "sleeve_scroll_container"
	scroll.position = grid.position
	scroll.size = grid.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

	parent.remove_child(grid)
	parent.add_child(scroll)
	scroll.add_child(grid)

	grid.position = Vector2.ZERO
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", H_SEP)
	grid.add_theme_constant_override("v_separation", V_SEP)


# ─── Sleeve loading ───────────────────────────────────────────────────────────

func _load_sleeves() -> void:
	# Grid is built from the small/ copies — 593 full-size sleeves is ~440 MB of texture,
	# the shrunken set is ~17 MB. The full-size original is only loaded on spacebar zoom.
	var dir := DirAccess.open(SLEEVE_SMALL_FOLDER)
	if dir == null:
		push_error("Sleeves: cannot open folder " + SLEEVE_SMALL_FOLDER)
		return

	var files : Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			if not file_name.begins_with("1_Default"):
				files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()

	for fname in files:
		# ISSUE #32 FIX: bail out cleanly if the player cancelled/escaped (the scene is being freed) —
		# calling get_tree() on a node that has left the tree is what crashed the game before.
		if _load_cancelled or not is_inside_tree():
			return
		# Owned-only mode skips unowned sleeves before the per-item frame yield below. That yield is
		# what makes a full build take seconds, so never queuing them is the entire speed-up.
		if _hide_unowned and not _owned_sleeves.has(String(fname).get_basename()):
			continue
		_add_sleeve_to_grid(fname)
		await get_tree().process_frame


func _add_sleeve_to_grid(file_name: String) -> void:
	var base_name : String = file_name.get_basename()
	var is_owned  : bool   = _owned_sleeves.has(base_name)

	var texture := load(SLEEVE_SMALL_FOLDER + "/" + file_name) as Texture2D
	if texture == null:
		return

	# Scale to fill (crop) the cell — maxf picks whichever axis needs to grow more
	var tex_size  := texture.get_size()
	var s         := maxf(CELL_SIZE.x / tex_size.x, CELL_SIZE.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	# Wrapper enforces the cell boundary and clips any overflow from the scaled image
	var wrapper := Control.new()
	wrapper.custom_minimum_size = CELL_SIZE
	wrapper.clip_contents       = true
	wrapper.set_meta("sleeve_name", base_name)
	wrapper.set_meta("is_owned",    is_owned)

	var rect := TextureRect.new()
	rect.texture      = texture
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size         = disp_size
	rect.position     = (CELL_SIZE - disp_size) / 2.0   # centre; overflow clipped by wrapper
	rect.mouse_filter = Control.MOUSE_FILTER_PASS

	wrapper.add_child(rect)

	if is_owned:
		wrapper.modulate = Color(0.8, 0.8, 0.8)
		wrapper.gui_input.connect(_on_sleeve_clicked.bind(wrapper))
	else:
		wrapper.modulate     = Color(0, 0, 0, 1)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	grid.add_child(wrapper)


func _select_sleeve_by_name(sleeve_name: String) -> void:
	for child in grid.get_children():
		if child is Control and child.get_meta("sleeve_name", "") == sleeve_name:
			_select_sleeve(child)
			return


# ─── Owned-only filter ───────────────────────────────────────────────────────

# Blue "Show" while the unowned placeholders are filtered out, yellow "Hide" while all are on show.
func _refresh_hide_button() -> void:
	if _hide_unowned:
		hide_btn.text  = "Show Unowned Sleeves"
		hide_btn.theme = load("res://UI_Themes/kenneyUI-blue.tres")
	else:
		hide_btn.text  = "Hide Unowned Sleeves"
		hide_btn.theme = load("res://UI_Themes/kenneyUI-yellow.tres")


func _on_hide_pressed() -> void:
	if _is_rebuilding:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_hide_unowned = not _hide_unowned
	_refresh_hide_button()
	await _rebuild_grid()


# Tears the grid down and rebuilds it under the current filter. The player's pending pick
# survives: only owned sleeves are selectable and hiding never removes an owned sleeve, so
# we just re-select it by name once the new wrappers exist.
func _rebuild_grid() -> void:
	_is_rebuilding    = true
	hide_btn.disabled = true

	var pending_name : String = ""
	if selected_sleeve != null and is_instance_valid(selected_sleeve):
		pending_name = String(selected_sleeve.get_meta("sleeve_name", ""))

	# The looping tween references a wrapper that is about to be freed.
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	selected_sleeve = null
	_last_clicked   = null

	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var scroll := grid.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0

	_show_loading_overlay()
	await get_tree().process_frame
	await _load_sleeves()
	_hide_loading_overlay()
	if not is_inside_tree():
		return

	if pending_name == "":
		pending_name = saved_sleeve_name
	if pending_name != "":
		_select_sleeve_by_name(pending_name)
	_refresh_save_button_state()

	hide_btn.disabled = false
	_is_rebuilding    = false


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_sleeve_clicked(event: InputEvent, wrapper: Control) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return
	_last_clicked = wrapper
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

	if selected_sleeve and selected_sleeve != wrapper:
		_deselect_sleeve(selected_sleeve)

	_select_sleeve(wrapper)
	_refresh_save_button_state()


# Enable save only when the chosen sleeve differs from what is already saved.
func _refresh_save_button_state() -> void:
	var chosen_name : String = ""
	if selected_sleeve != null and is_instance_valid(selected_sleeve):
		chosen_name = String(selected_sleeve.get_meta("sleeve_name", ""))

	if chosen_name != "" and chosen_name != saved_sleeve_name:
		save_btn.disabled = false
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		save_btn.disabled = true
		save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


func _select_sleeve(wrapper: Control) -> void:
	selected_sleeve = wrapper
	_apply_selected_animation(wrapper)


func _deselect_sleeve(wrapper: Control) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	wrapper.modulate     = Color(0.8, 0.8, 0.8)
	wrapper.scale        = Vector2(1.0, 1.0)
	wrapper.pivot_offset = wrapper.size / 2.0


func _apply_selected_animation(wrapper: Control) -> void:
	if _active_tween:
		_active_tween.kill()

	wrapper.pivot_offset = wrapper.size / 2.0
	wrapper.modulate     = Color.WHITE

	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween

	tween.tween_property(wrapper, "modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(wrapper, "scale", Vector2(1.1, 1.1), 0.2)
	tween.tween_property(wrapper, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(wrapper, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	if selected_sleeve == null:
		return

	var new_sleeve_name : String = selected_sleeve.get_meta("sleeve_name", "")
	if new_sleeve_name == "":
		return

	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Sleeves: cannot read " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	var data = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("Sleeves: player_data.json is malformed")
		return

	data["sleeve"] = new_sleeve_name

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("Sleeves: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	saved_sleeve_name = new_sleeve_name
	save_btn.disabled = true
	save_btn.theme    = load("res://UI_Themes/kenneyUI.tres")


func _on_cancel_pressed() -> void:
	_load_cancelled = true   # ISSUE #32: stop the load loop before the scene is freed
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape / Spacebar input ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if is_zoomed:
				space_held = false   # ISSUE #98: drop the hold too, or _process re-opens the preview
				_hide_zoom()
				return
			_load_cancelled = true   # ISSUE #32: stop the load loop before the scene is freed
			if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
			return

		if event.keycode == KEY_SPACE:
			# ISSUE #97 FIX ACTIVE: Space doubles as "ui_accept", so an unhandled event re-presses
			# whichever Button still has focus. Consume both edges.
			get_viewport().set_input_as_handled()
			if event.pressed and not event.is_echo():
				space_held = true
				_refresh_hover_preview()
			elif not event.pressed:
				space_held = false
				_hide_zoom()

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		call_deferred("_check_click_miss")


# ISSUE #98: while Space is held, keep the preview locked to whatever sleeve the mouse is over.
func _process(_delta: float) -> void:
	if space_held:
		_refresh_hover_preview()


func _refresh_hover_preview() -> void:
	var wrapper := _get_hovered_sleeve()
	if wrapper == zoomed_sleeve:
		return
	if wrapper == null:
		return   # gap between sleeves — hold the current preview rather than flashing it off
	_show_zoom(wrapper)


func _check_click_miss() -> void:
	if _last_clicked == null:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_last_clicked = null


# ─── Sleeve zoom ─────────────────────────────────────────────────────────────

func _get_hovered_sleeve() -> Control:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	var node = hovered
	for i in range(5):
		if node == null:
			return null
		if node.has_meta("sleeve_name") and node.get_meta("is_owned", false):
			return node as Control
		node = node.get_parent()
	return null


# Resolves a sleeve's full-size original. The grid images all live in small/ as .jpg, but the
# originals are a mix of .jpg and .png, so try both.
func _large_sleeve_texture(base_name: String) -> Texture2D:
	for ext: String in [".jpg", ".png"]:
		var path := SLEEVE_FOLDER + "/" + base_name + ext
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				return tex
	return null


func _show_zoom(wrapper: Control) -> void:
	var rect : TextureRect = null
	for child in wrapper.get_children():
		if child is TextureRect:
			rect = child
			break
	if rect == null or rect.texture == null:
		return

	# Zoom shows the full-size original, not the shrunken grid thumbnail.
	var zoom_texture := _large_sleeve_texture(String(wrapper.get_meta("sleeve_name", "")))
	if zoom_texture == null:
		zoom_texture = rect.texture

	last_zoomed_sleeve = wrapper
	zoomed_sleeve      = wrapper

	# ISSUE #98: overlay already up — swap the image in place rather than rebuilding the CanvasLayer,
	# which flashed the bright sleeve grid through for a frame on every hover change.
	if is_zoomed and zoom_image != null and is_instance_valid(zoom_image):
		_apply_zoom_texture(zoom_texture)
		return

	is_zoomed = true

	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 150
	add_child(zoom_overlay)

	var backdrop := ColorRect.new()
	backdrop.color         = Color(0, 0, 0, 0.95)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	# Must not absorb hover or gui_get_hovered_control() would report the backdrop, not the grid.
	backdrop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(backdrop)

	zoom_image = TextureRect.new()
	zoom_image.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	zoom_image.stretch_mode = TextureRect.STRETCH_SCALE
	zoom_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(zoom_image)
	_apply_zoom_texture(zoom_texture)


# Fit within 980px tall (50px margin top+bottom), up to 1000px wide
func _apply_zoom_texture(zoom_texture: Texture2D) -> void:
	var tex_size  := zoom_texture.get_size()
	var target    := Vector2(1000.0, 980.0)
	var s         := minf(target.x / tex_size.x, target.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	zoom_image.texture  = zoom_texture
	zoom_image.size     = disp_size
	zoom_image.position = Vector2((1920.0 - disp_size.x) / 2.0, (1080.0 - disp_size.y) / 2.0)


func _hide_zoom() -> void:
	if not is_zoomed:
		return
	is_zoomed      = false
	zoomed_sleeve  = null
	zoom_image     = null
	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null
