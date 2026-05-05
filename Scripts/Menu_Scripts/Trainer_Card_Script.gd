extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const SPRITE_SIZE        := Vector2(100, 200)
const SPRITE_SEPARATION  := -4
# At 250px + 10px gap = 260px per cell across 1920px usable width → 7 columns
const COLUMNS            := 9
const MAX_NAME_LENGTH    := 15

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
var PLAYER_PROGRESS_PATH: String:
	get: return GameState.PROGRESS_PATH

# ─── State ───────────────────────────────────────────────────────────────────

var selected_character_path : String = ""
var selected_character_rect : TextureRect = null

# The sprite name stored in player_data.json on load — used to detect unsaved changes
var saved_sprite_name       : String = ""
# The player name loaded from json — tracked to detect unsaved name changes too
var saved_player_name       : String = ""

var _active_tween           : Tween = null
var _last_clicked_rect      : TextureRect = null

# Flat set of owned costume filenames e.g. {"1dawn_platinum.png": true}
# Using a Dictionary as a set gives O(1) lookups vs iterating an Array
var _owned_costumes         : Dictionary = {}

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"trainer_grid_container"
@onready var save_btn    : Button        = $"trainer_save_button"
@onready var cancel_btn  : Button        = $"trainer_cancel_button"
@onready var name_box    : LineEdit      = $"player_name"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)

	var audio_stream = load("res://Audio/BGM/coin_mode.ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	audio_player.stream.loop = true
	audio_player.play()

	_load_owned_costumes_list()
	_load_player_data()

	# LineEdit natively supports max_length and single-line input
	name_box.text = saved_player_name
	name_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_box.max_length = MAX_NAME_LENGTH
	name_box.text_changed.connect(_on_name_changed)

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_wrap_grid_in_scroll_container()
	await get_tree().process_frame
	await _load_characters()

	if saved_sprite_name != "":
		_auto_select_saved_character()


# No _process needed — sparkle effect removed, no per-frame updates required


# ─── Data loading ────────────────────────────────────────────────────────────

# Reads the "Costumes" array from Player_Game_Progress.json into _owned_costumes dictionary.
# Each entry is a costume filename, e.g. "1dawnplatinum.png"
func _load_owned_costumes_list() -> void:
	print("DEBUG TrainerCard: opening ", PLAYER_PROGRESS_PATH)
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("TrainerCard: cannot open " + PLAYER_PROGRESS_PATH + " | error: " + str(FileAccess.get_open_error()))
		return
	var raw_text := file.get_as_text()
	file.close()
	print("DEBUG TrainerCard: raw JSON length=", raw_text.length(), " preview=", raw_text.left(100))

	var data = JSON.parse_string(raw_text)
	print("DEBUG TrainerCard: parsed type=", typeof(data), " value=", data)

	if not data is Dictionary:
		push_error("TrainerCard: JSON did not parse to Dictionary, got: " + str(data))
		return
	if not data.has("costumes"):
		push_error("TrainerCard: 'Costumes' key missing. Keys found: " + str(data.keys()))
		return

	print("DEBUG TrainerCard: Costumes array=", data["costumes"])
	for costume_name in data["costumes"]:
		_owned_costumes[costume_name] = true
	print("DEBUG TrainerCard: _owned_costumes populated=", _owned_costumes)


func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("TrainerCard: cannot open " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("TrainerCard: player_data.json is malformed")
		return

	if data.has("overworld_sprite"):
		var raw : String = data["sprite"]
		if not raw.ends_with(".png"):
			raw = raw + ".png"
		saved_sprite_name = raw

	if data.has("name"):
		saved_player_name = data["name"]


# ─── Name box ────────────────────────────────────────────────────────────────

func _on_name_changed(_new_text: String) -> void:
	# max_length on LineEdit already blocks characters over the limit,
	# so we just need to check whether the save button state needs updating
	_refresh_save_button_state()


# ─── Scroll container setup ──────────────────────────────────────────────────

func _wrap_grid_in_scroll_container() -> void:
	var parent = grid.get_parent()

	var scroll := ScrollContainer.new()
	scroll.name = "character_scroll_container"
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
	grid.add_theme_constant_override("h_separation", SPRITE_SEPARATION)
	grid.add_theme_constant_override("v_separation", SPRITE_SEPARATION)


# ─── Character loading ───────────────────────────────────────────────────────

func _load_characters() -> void:
	var dir := DirAccess.open(SPRITE_FOLDER)
	if dir == null:
		push_error("TrainerCard: cannot open folder " + SPRITE_FOLDER)
		return

	var files : Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()

	for fname in files:
		_add_character_to_grid(fname)
		await get_tree().process_frame


func _add_character_to_grid(file_name: String) -> void:
	var texture := load(SPRITE_FOLDER + "/" + file_name) as Texture2D
	if texture == null:
		return

	var rect := TextureRect.new()
	rect.texture = texture

	rect.custom_minimum_size = SPRITE_SIZE
	rect.size                = SPRITE_SIZE
	rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL

	var is_owned : bool = _owned_costumes.has(file_name)
	print("DEBUG TrainerCard: grid file=", file_name, " is_owned=", is_owned)

	rect.set_meta("sprite_name", file_name)
	rect.set_meta("is_owned",    is_owned)

	if is_owned:
		rect.modulate = Color(0.8, 0.8, 0.8)
		rect.gui_input.connect(_on_character_clicked.bind(rect))
	else:
		# Keep the real texture but zero out all RGB channels via modulate.
		# modulate multiplies every pixel's colour — black makes the sprite appear
		# as a solid black silhouette with no texture swap needed.
		# MOUSE_FILTER_IGNORE tells Godot to pass all input events straight through
		# this node as if it doesn't exist, so it can never be clicked or hovered.
		rect.modulate     = Color(0, 0, 0, 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	grid.add_child(rect)


func _auto_select_saved_character() -> void:
	for child in grid.get_children():
		if child is TextureRect and child.get_meta("sprite_name", "") == saved_sprite_name:
			_select_character(child)
			return


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_character_clicked(event: InputEvent, rect: TextureRect) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return
	_last_clicked_rect = rect
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

	if selected_character_rect and selected_character_rect != rect:
		_deselect_character(selected_character_rect)

	_select_character(rect)
	_refresh_save_button_state()


func _select_character(rect: TextureRect) -> void:
	selected_character_rect = rect
	selected_character_path = SPRITE_FOLDER + "/" + rect.get_meta("sprite_name", "")
	_apply_selected_animation(rect)


func _deselect_character(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	rect.modulate     = Color(0.8, 0.8, 0.8)
	rect.scale        = Vector2(1.0, 1.0)
	rect.pivot_offset = rect.size / 2.0


func _apply_selected_animation(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()

	rect.pivot_offset = rect.size / 2.0
	rect.modulate     = Color.WHITE

	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween

	tween.tween_property(rect, "modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.1, 1.1), 0.2)
	tween.tween_property(rect, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Save button state ───────────────────────────────────────────────────────

# Called whenever the sprite selection or name box changes.
# The save button is enabled if either the chosen sprite OR the typed name
# differs from what is currently stored in player_data.json.
func _refresh_save_button_state() -> void:
	var sprite_changed := false
	if selected_character_rect != null:
		sprite_changed = selected_character_rect.get_meta("sprite_name", "") != saved_sprite_name

	var name_changed := name_box.text.strip_edges() != saved_player_name

	if sprite_changed or name_changed:
		save_btn.disabled = false
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		save_btn.disabled = true
		save_btn.theme    = load("res://UI_Themes/kenneyUI.tres")


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("TrainerCard: cannot read " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("TrainerCard: player_data.json is malformed")
		return

	# Save sprite — strip .png to stay consistent with existing json format
	if selected_character_rect != null:
		var new_sprite : String = selected_character_rect.get_meta("sprite_name", "")
		if new_sprite != "":
			data["sprite"]    = new_sprite.trim_suffix(".png")
			saved_sprite_name = new_sprite

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	# Save name — trim whitespace before storing
	var new_name := name_box.text.strip_edges()
	if new_name != "":
		data["name"]      = new_name
		saved_player_name = new_name

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("TrainerCard: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

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
	if _last_clicked_rect == null:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_last_clicked_rect = null
