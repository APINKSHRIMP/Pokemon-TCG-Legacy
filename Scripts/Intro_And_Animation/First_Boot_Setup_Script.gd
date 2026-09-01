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
	# ISSUE #210: the PTCG main-menu theme that used to play in the Gym Plaza. The
	# two swapped: the plaza now shares the Gym Challenge Hall track it adjoins.
	var stream = load(SoundManagerScript.BGM_GYM_PLAZA)
	if stream:
		_bgm_player.stream = stream
		_bgm_player.bus = SoundManagerScript.MUSIC_BUS
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
# ISSUE #192: THIS SCREEN IS CONVERTED NOW. It had the new buttons, boxes and font
# but was still drawing the pre-overhaul chrome — the blue/black scrolling borders
# and the light background — because it was the one screen that never went through
# UIKit.convert_legacy_screen(). It does now, which frees the scene's BACKGROUND
# node and lays in the field plus both gradient bars.
#
# Layout (1920x1080, centred on x=960), inside the 92..988 content band:
#   Name box   x=660  w=600   y=132
#   DoB box    x=780  w=360   y=212
#   Grid       x=142  w=1636  y=306   (6 x 260 + 5 x 15 = 1635)
#   Save       on the footer bar
const FIELD_W       := 600.0
const DOB_W         := 360.0
const FIELD_H       := 58.0
const NAME_Y        := 132.0
const DOB_Y         := 212.0
const GRID_Y        := 306.0
const SAVE_BTN_W    := 420.0
const FIELD_FONT    := 30

func _build_ui() -> void:
	# ISSUE #192: the chrome. Must run FIRST — it frees BACKGROUND and forces the
	# 40x40 scene root to full-rect, which everything below is positioned against.
	var bars := UIKit.convert_legacy_screen(self, "New trainer")
	print("ISSUE #192 FIX ACTIVE: first-boot setup converted to the Spectrum Night chrome")

	var hint := Label.new()
	UIKit.set_label(hint, "subtitle", "Choose your name, birthday and look", "chrome_fg")
	bars["header"].right.add_child(hint)

	# ── Name box ─────────────────────────────────────────────
	_name_box = _make_field("Enter your name...", 15, FIELD_W, NAME_Y, FIELD_FONT)

	# ── DoB box ──────────────────────────────────────────────
	_dob_box = _make_field("Birthday (DD/MM)", 5, DOB_W, DOB_Y, FIELD_FONT - 2)

	# ── Sprite grid ──────────────────────────────────────────
	# Width = 6 x 260 + 5 x 15 = 1635 -> start x = (1920 - 1635) / 2 = 142
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(142, GRID_Y)
	scroll.size = Vector2(1636, UIKit.CONTENT_BOTTOM - GRID_Y - 18.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", H_SEP)
	_grid.add_theme_constant_override("v_separation", V_SEP)
	scroll.add_child(_grid)

	# ── Save button ──────────────────────────────────────────
	# On the footer bar, and a CHILD of it: a sibling floated over a chrome bar is
	# one z-order slip from invisible.
	_save_btn = UIKit.make_footer_button("Begin your journey", "secondary")
	_save_btn.custom_minimum_size.x = SAVE_BTN_W
	_save_btn.disabled = true
	_save_btn.pressed.connect(_on_save_pressed)
	bars["footer"].centre.add_child(_save_btn)


## One centred text field on the field background. ISSUE #192: white text, not the
## black these two carried from the light background they used to sit on.
func _make_field(placeholder: String, max_len: int, w: float, y: float,
		font_size: int) -> LineEdit:
	var box := LineEdit.new()
	box.position = Vector2(960.0 - w * 0.5, y)
	box.size = Vector2(w, FIELD_H)
	box.custom_minimum_size = box.size
	box.max_length = max_len
	box.placeholder_text = placeholder
	box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_theme_font_override("font", UITheme.font("name"))
	box.add_theme_font_size_override("font_size", font_size)
	box.add_theme_color_override("font_color", Color.WHITE)
	box.add_theme_color_override("font_placeholder_color", UITheme.col("field_mute"))
	box.text_changed.connect(_on_input_changed)
	add_child(box)
	return box


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
	# ISSUE #192: through UIKit so the button keeps press-to-fire and the casing.
	UIKit.style_button(_save_btn, "primary" if all_ok else "secondary")


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
	GameState.progress["time"] = "Morning"
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
