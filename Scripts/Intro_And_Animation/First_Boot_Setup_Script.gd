extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const CELL_SIZE     := Vector2(260, 260)  # SQUARE cell — makes minf constrain all sprites to same height
const COLUMNS       := 6
const H_SEP         := 15
const V_SEP         := 15

# ─── State ───────────────────────────────────────────────────────────────────

var _selected_cell : Control = null
var _active_tween  : Tween = null

# ─── UI references (built programmatically) ──────────────────────────────────

var _name_box   : LineEdit
var _dob_box    : LineEdit
var _save_btn   : Button
var _grid       : GridContainer
var _bgm_player : AudioStreamPlayer

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_play_bgm()
	_fade_in()
	await get_tree().process_frame
	await _load_sprites()


func _play_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	add_child(_bgm_player)
	var stream = load("res://Audio/BGM/coin_mode.ogg")
	if stream:
		_bgm_player.stream = stream
		_bgm_player.bus = "Master"
		stream.loop = true
		_bgm_player.play()


func _fade_in() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.5)
	tween.tween_callback(func(): canvas.queue_free())


# ─── UI construction ─────────────────────────────────────────────────────────
#
# Layout (1920×1080, all centred on x=960):
#   Name box  x=660  w=600   y=108
#   DoB box   x=780  w=360   y=172   (centre: 780+180=960)
#   Grid      x=142  w=1636  y=290   (6 × 260 + 5 × 15 = 1635)
#   Save btn  x=688  w=544   y=894

func _build_ui() -> void:
	var theme = load("res://UI_Themes/kenneyUI.tres")

	# ── Name box ─────────────────────────────────────────────
	_name_box = LineEdit.new()
	_name_box.position = Vector2(660, 108)
	_name_box.size = Vector2(600, 54)
	_name_box.max_length = 15
	_name_box.placeholder_text = "Enter your name..."
	_name_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if theme:
		_name_box.theme = theme
	_name_box.add_theme_font_size_override("font_size", 30)
	_name_box.add_theme_color_override("font_color", Color.BLACK)
	_name_box.add_theme_color_override("font_placeholder_color", Color(0.25, 0.25, 0.25, 0.6))
	_name_box.text_changed.connect(_on_input_changed)
	add_child(_name_box)

	# ── DoB box ──────────────────────────────────────────────
	_dob_box = LineEdit.new()
	_dob_box.position = Vector2(780, 172)
	_dob_box.size = Vector2(360, 54)
	_dob_box.max_length = 5
	_dob_box.placeholder_text = "Birthday (DD/MM)"
	_dob_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if theme:
		_dob_box.theme = theme
	_dob_box.add_theme_font_size_override("font_size", 28)
	_dob_box.add_theme_color_override("font_color", Color.BLACK)
	_dob_box.add_theme_color_override("font_placeholder_color", Color(0.25, 0.25, 0.25, 0.6))
	_dob_box.text_changed.connect(_on_input_changed)
	add_child(_dob_box)

	# ── Sprite grid ──────────────────────────────────────────
	# Width = 6 × 260 + 5 × 15 = 1635 → start x = (1920 − 1635) / 2 = 142
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(142, 290)
	scroll.size = Vector2(1636, 590)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", H_SEP)
	_grid.add_theme_constant_override("v_separation", V_SEP)
	scroll.add_child(_grid)

	# ── Save button ──────────────────────────────────────────
	_save_btn = Button.new()
	_save_btn.text = "Begin Your Journey"
	_save_btn.position = Vector2(688, 894)
	_save_btn.size = Vector2(544, 63)
	_save_btn.z_index = 300
	if theme:
		_save_btn.theme = theme
	_save_btn.disabled = true
	_save_btn.pressed.connect(_on_save_pressed)
	add_child(_save_btn)


# ─── Sprite loading ───────────────────────────────────────────────────────────

func _load_sprites() -> void:
	var dir := DirAccess.open(SPRITE_FOLDER)
	if dir == null:
		push_error("FirstBootSetup: cannot open sprite folder " + SPRITE_FOLDER)
		return

	var files: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and not fname.ends_with(".import"):
			if fname.to_lower().begins_with("1") and fname.ends_with(".png"):
				files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	files.sort()

	for f in files:
		_add_sprite_to_grid(f)
		await get_tree().process_frame


func _add_sprite_to_grid(file_name: String) -> void:
	var texture := load(SPRITE_FOLDER + "/" + file_name) as Texture2D
	if texture == null:
		return

	# Replicate the _normalize_sprite_scale logic used in Match_Start_Intro_Script:
	#   s = minf(TARGET.x / tex.x, TARGET.y / tex.y)
	# This gives every sprite the same bounding box regardless of native resolution.
	var tex_size  := texture.get_size()
	var s         := minf(CELL_SIZE.x / tex_size.x, CELL_SIZE.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	# Fixed-size cell governs the GridContainer column width.
	var cell := Control.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.set_meta("sprite_name", file_name)
	cell.gui_input.connect(_on_sprite_clicked.bind(cell))

	# TextureRect is explicitly sized and centred — no anchors, no expand mode tricks.
	# STRETCH_SCALE fills exactly rect.size (which we already set to the correct proportion).
	var rect := TextureRect.new()
	rect.texture      = texture
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size         = disp_size
	rect.position     = (CELL_SIZE - disp_size) / 2.0  # centre within cell
	rect.modulate     = Color(0.8, 0.8, 0.8)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cell.add_child(rect)
	_grid.add_child(cell)


# ─── Sprite selection ─────────────────────────────────────────────────────────

func _on_sprite_clicked(event: InputEvent, cell: Control) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

	if _selected_cell != null and _selected_cell != cell:
		_deselect(_selected_cell)

	_selected_cell = cell
	_apply_selected_animation(cell)
	_refresh_save_btn()


func _get_inner_rect(cell: Control) -> TextureRect:
	for child in cell.get_children():
		if child is TextureRect:
			return child
	return null


func _deselect(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	cell.scale = Vector2.ONE
	cell.pivot_offset = cell.size / 2.0
	var r := _get_inner_rect(cell)
	if r:
		r.modulate = Color(0.8, 0.8, 0.8)


func _apply_selected_animation(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()

	cell.pivot_offset = cell.size / 2.0
	var r := _get_inner_rect(cell)
	if r:
		r.modulate = Color.WHITE

	if r == null:
		return

	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	tween.tween_property(cell, "scale", Vector2(1.1, 1.1), 0.2)
	tween.parallel().tween_property(r, "modulate", Color.WHITE * 1.1, 0.2)
	tween.tween_property(cell, "scale", Vector2(1.0, 1.0), 0.2)
	tween.parallel().tween_property(r, "modulate", Color.WHITE * 1.0, 0.2)


# ─── Input validation ─────────────────────────────────────────────────────────

func _on_input_changed(_text: String) -> void:
	_refresh_save_btn()


func _is_valid_dob(text: String) -> bool:
	if text.length() != 5 or text[2] != "/":
		return false
	var day_str   := text.substr(0, 2)
	var month_str := text.substr(3, 2)
	if not day_str.is_valid_int() or not month_str.is_valid_int():
		return false
	var day   := int(day_str)
	var month := int(month_str)
	return day >= 1 and day <= 31 and month >= 1 and month <= 12


func _refresh_save_btn() -> void:
	var name_ok   := _name_box.text.strip_edges().length() > 0
	var dob_ok    := _is_valid_dob(_dob_box.text)
	var sprite_ok := _selected_cell != null
	var all_ok    := name_ok and dob_ok and sprite_ok

	_save_btn.disabled = not all_ok
	if all_ok:
		var green := load("res://UI_Themes/kenneyUI-green.tres")
		if green:
			_save_btn.theme = green
	else:
		_save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


# ─── Save and transition ──────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	_save_btn.disabled = true
	_bgm_player.stop()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	var data_path := GameState.PLAYER_CURRENT_DATA_PATH
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		push_error("FirstBootSetup: cannot read " + data_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		data = {}

	data["name"]          = _name_box.text.strip_edges()
	data["sprite"]        = (_selected_cell.get_meta("sprite_name", "") as String).trim_suffix(".png")
	data["date_of_birth"] = _dob_box.text

	var write_file := FileAccess.open(data_path, FileAccess.WRITE)
	if write_file == null:
		push_error("FirstBootSetup: cannot write " + data_path)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	# Batch-add all "1"-prefixed sprites to owned costumes (single save at end)
	var costumes: Array = GameState.progress.get("costumes", [])
	var dir := DirAccess.open(SPRITE_FOLDER)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.to_lower().begins_with("1") and fname.ends_with(".png"):
				var key := fname.to_lower()
				if key not in costumes:
					costumes.append(key)
			fname = dir.get_next()
		dir.list_dir_end()
	GameState.progress["costumes"] = costumes

	GameState.progress["date"] = 1
	GameState.progress["time"] = "Day"
	GameState.progress["taxi_intro_pending"] = true
	GameState.mark_first_launch_complete()

	# Fade to black over 3 seconds then launch into the world
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 3.0)
	tween.tween_callback(func():
		SceneCache.change_scene("res://Scenes/Map_Scenes/Celeste_Harbour.tscn")
	)
