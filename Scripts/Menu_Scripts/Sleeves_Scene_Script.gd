extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SLEEVE_FOLDER  := "res://Image_Assets/Sleeves"
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

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"sleeves_grid_container"
@onready var save_btn    : Button        = $"sleeves_save_button"
@onready var cancel_btn  : Button        = $"sleeves_cancel_button"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)
	var audio_stream = load("res://Audio/BGM/coin_mode.ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	audio_player.stream.loop = true
	audio_player.play()

	_load_owned_sleeves_list()
	_load_player_data()

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_wrap_grid_in_scroll_container()
	await get_tree().process_frame
	await _load_sleeves()

	if saved_sleeve_name != "":
		_auto_select_saved_sleeve()


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
	var dir := DirAccess.open(SLEEVE_FOLDER)
	if dir == null:
		push_error("Sleeves: cannot open folder " + SLEEVE_FOLDER)
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
		_add_sleeve_to_grid(fname)
		await get_tree().process_frame


func _add_sleeve_to_grid(file_name: String) -> void:
	var base_name : String = file_name.get_basename()
	var is_owned  : bool   = _owned_sleeves.has(base_name)

	var texture := load(SLEEVE_FOLDER + "/" + file_name) as Texture2D
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


func _auto_select_saved_sleeve() -> void:
	for child in grid.get_children():
		if child is Control and child.get_meta("sleeve_name", "") == saved_sleeve_name:
			_select_sleeve(child)
			return


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

	var chosen_name : String = wrapper.get_meta("sleeve_name", "")
	if chosen_name != saved_sleeve_name:
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
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape key ──────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		call_deferred("_check_click_miss")


func _check_click_miss() -> void:
	if _last_clicked == null:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_last_clicked = null
