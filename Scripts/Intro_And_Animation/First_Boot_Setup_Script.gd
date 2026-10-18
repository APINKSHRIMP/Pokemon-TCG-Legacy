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

# The three pages: 0 name/birthday/look, 1 familiarity, 2 Hard Mode (only after
# the two harder familiarity answers).
var _pages      : Array[Control] = []
var _page       : int = 0
var _switching  : bool = false   # a page fade is running; buttons and keys wait
var _leaving    : bool = false   # Start New Game pressed; the scene is fading out
var _familiarity: int = 0        # index into FAMILIARITY_ORDER
var _hard_mode  : bool = false

# ─── UI references (built programmatically) ──────────────────────────────────

var _name_box   : LineEdit
var _dob_box    : LineEdit
var _save_btn   : Button          # the forward button: "Next" or "Start New Game"
var _back_btn   : Button
var _grid       : GridContainer
var _chip_slot  : Control
var _fam_holders: Array[Control] = []
var _fam_ring_layer: Control
var _fam_ring   : Control = null
var _mode_holders: Array[Control] = []
var _mode_ring_layer: Control
var _mode_ring  : Control = null
var _mode_context_chip: Control = null

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_play_bgm()
	_fade_in()
	await get_tree().process_frame
	await _load_sprites()


# ISSUE #210: the PTCG main-menu theme that used to play in the Gym Plaza. The two
# swapped: the plaza now shares the Gym Challenge Hall track it adjoins.
#
# Routed through SoundManagerScript rather than a local player ON PURPOSE. The
# splash starts this same track the moment its menu buttons appear, and play_bgm()
# no-ops when the requested path is already playing — so pressing New Game there
# carries the music across the scene change unbroken. A local AudioStreamPlayer
# would restart it from the top and make the transition audible.
func _play_bgm() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_STARTING_MENU)


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

	# A CHIP, not a bare label. The header's right slot sits over the warm end of
	# the chrome gradient, which on the brighter themes does not carry plain white
	# text at this size — and this was the only bare non-title label on a chrome
	# bar anywhere in the game; every other side slot already uses a chip. The
	# chip brings its own background, so it reads on any theme's bar.
	_chip_slot = bars["header"].right
	_set_header_chip(CHIP_TEXT[0])

	# Page 0 — everything below lives in one Control so the page fades as one.
	_pages.append(_new_page("setup"))

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
	_pages[0].add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", H_SEP)
	_grid.add_theme_constant_override("v_separation", V_SEP)
	scroll.add_child(_grid)

	# ── Footer buttons ───────────────────────────────────────
	# On the footer bar, and CHILDREN of it: a sibling floated over a chrome bar is
	# one z-order slip from invisible. Back is hidden on the first page; Next reads
	# "Start New Game" on whichever page is the last for the answers given.
	_back_btn = UIKit.make_footer_button("Back", "negative")
	_back_btn.custom_minimum_size.x = SAVE_BTN_W
	_back_btn.pressed.connect(_on_back_pressed)
	_back_btn.visible = false
	bars["footer"].centre.add_child(_back_btn)

	_save_btn = UIKit.make_footer_button("Next", "secondary")
	_save_btn.custom_minimum_size.x = SAVE_BTN_W
	_save_btn.disabled = true
	_save_btn.pressed.connect(_on_next_pressed)
	bars["footer"].centre.add_child(_save_btn)

	_build_familiarity_page()
	_build_hard_mode_page()


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
	# field_fg, not white: on a light theme white text in the name box is invisible.
	box.add_theme_color_override("font_color", UITheme.col("field_fg"))
	box.add_theme_color_override("font_placeholder_color", UITheme.col("field_mute"))
	box.text_changed.connect(_on_input_changed)
	_pages[0].add_child(box)
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

	# ISSUE #380: FIT THE CHARACTER, NOT THE CANVAS.
	# Fitting the whole image made every canvas the same size, but the canvases are
	# not padded alike: the Black/White sprites (Hilda, Hilbert, Rosa, Nate) are
	# 128px squares with the character in barely half of it, so they came out at
	# about half the height of everyone else. The sprite is cropped to its visible
	# (non-transparent) pixels first, and THAT is what gets fitted to the cell.
	# ISSUE #399: the crop moved to UIKit.visible_sprite so the trainer info and
	# costume screens share it.
	texture = UIKit.visible_sprite(texture)
	print("ISSUE #380 FIX ACTIVE: ", file_name, " fitted by its visible area ", texture.get_size())
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

func _start_game() -> void:
	_leaving = true
	_save_btn.disabled = true
	_back_btn.disabled = true
	SoundManagerScript.stop_bgm()
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

	# Familiarity + Hard Mode, and the start day/time they imply (hidden from the
	# player — see GameState.INTRO_PROFILES).
	GameState.apply_new_game_answers(FAMILIARITY_ORDER[_familiarity],
		_hard_mode and _offers_hard_mode())
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


# ============================================================
# NEW-GAME QUESTIONS — familiarity, then Hard Mode
# ============================================================
# Two question pages after the name/birthday/look page, in the same chrome. Each
# answer is a column built from the translucent panel the save slots use; the
# selected one wears the rotating ring and the rest dim. The rows inside the
# columns are the SAME rows in the SAME order, so they read straight across like
# a table without needing its grid lines.
#
# What each answer changes behind the scenes (start day/time, call, deck,
# cutscene) lives in GameState.INTRO_PROFILES. The start time is a hidden mechanic
# and is deliberately never shown here.
#
# Keys on the question pages: Left / Right pick, Enter / Space / pad A go forward,
# Escape / pad B go back. Double-click an answer to pick it and go forward.

const CHIP_TEXT := [
	"Choose your name, birthday and look",
	"Choose your experience",
	"Choose your challenge",
]

# Must match GameState.FAMILIARITY_* (an autoload's consts are not constant
# expressions, so they cannot be referenced here).
const FAMILIARITY_ORDER := ["new", "rules", "played", "expert"]
const FAMILIARITY_ANSWERS := [
	"I'm completely new",
	"I know the rules a bit",
	"I've played a Pokémon TCG game before",
	"I'm an experienced player",
]
# Row icons: "deck" a card outline, "on" a tick, "off" a cross, "warn" a "!".
const FAMILIARITY_ROWS := [
	[["deck", "Starter Deck"], ["on", "Mandatory tutorial match"], ["on", "Match help hints"],
		["on", "Gameplay hints"], ["off", "Hard Mode option"], ["off", "Harder matches straight away"]],
	[["deck", "Starter Deck"], ["on", "Natural tutorial matches"], ["on", "Match help hints"],
		["on", "Gameplay hints"], ["off", "Hard Mode option"], ["off", "Harder matches straight away"]],
	[["deck", "Advanced Deck"], ["off", "Tutorial matches"], ["off", "Match help hints"],
		["on", "Gameplay hints"], ["on", "Hard Mode option"], ["off", "Harder matches straight away"]],
	[["deck", "Advanced Deck"], ["off", "Tutorial matches"], ["off", "Match help hints"],
		["off", "Gameplay hints"], ["on", "Hard Mode option"], ["on", "Harder matches straight away"]],
]

const MODE_TITLES := ["Normal Mode", "Hard Mode"]
const MODE_ROWS := [
	[["on", "Start with the Advanced Deck"], ["on", "3x bonus for each new win"],
		["on", "Rematches allowed"], ["on", "Rule and bonus modifier matches at the usual pace"]],
	[["off", "Draft start, no guaranteed cards"], ["off", "No 3x bonus for new wins"],
		["off", "No rematches"], ["warn", "Rule and bonus modifier matches come earlier"]],
]
const MODE_NOTE := "Hard Mode is locked in once the game starts and can't be changed later."

# ─── Question page layout — ALL TWEAKABLE ────────────────────────────────────
const PAGE_FADE     := 0.25    # each half of a page change (out, then in)
const HEADING_Y     := 112.0
const HEADING_H     := 56.0
const HEADING_FONT  := 38
const DIM           := 0.78    # brightness of the answers that are NOT selected

const FAM_TOP       := 226.0
const FAM_BOTTOM    := 950.0
const FAM_SIDE      := 60.0    # screen edge -> first column
const FAM_GAP       := 30.0    # between columns

const MODE_W        := 760.0
const MODE_GAP      := 48.0
const MODE_CHIP_Y   := 190.0   # the "your answer" chip under the heading
const MODE_TOP      := 272.0
const MODE_BOTTOM   := 880.0
const MODE_NOTE_Y   := 902.0
const MODE_TITLE_FONT := 40

const ACCENT_Y      := 16.0    # the coloured pill across the top of a column
const ACCENT_H      := 6.0
const ACCENT_INSET  := 28.0
const ANSWER_TOP    := 32.0
const ANSWER_H      := 112.0
const ANSWER_FONT   := 32
const ROWS_GAP      := 24.0    # divider -> first row
const ROW_H         := 84.0
const ROW_FONT      := 24
const ROW_PAD       := 26.0
const ICON          := 30.0
const ICON_GAP      := 14.0
const OFF_ALPHA     := 0.6     # text of a row that is off/crossed


func _new_page(page_name: String) -> Control:
	var page := Control.new()
	page.name = page_name
	page.position = Vector2.ZERO
	page.size = Vector2(UIKit.SCREEN_W, UIKit.SCREEN_H)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	return page


func _set_header_chip(text: String) -> void:
	for child in _chip_slot.get_children():
		_chip_slot.remove_child(child)
		child.queue_free()
	# A CHIP, not a bare label — see the note in _build_ui().
	_chip_slot.add_child(UIKit.make_chip(text, "on_chrome"))


## Page 1: "How familiar are you…" — four answers, easiest on the left.
func _build_familiarity_page() -> void:
	var page := _new_page("familiarity")
	page.visible = false
	_pages.append(page)
	_add_heading(page, "How familiar are you with the Pokémon Trading Card Game?")

	# Green through amber to red: the theme's own good / warn / danger.
	var good: Color = UITheme.col("good")
	var warn: Color = UITheme.col("warn")
	var accents := [good, good.lerp(warn, 0.5), warn, UITheme.col("danger")]

	var count: int = FAMILIARITY_ANSWERS.size()
	var w: float = (UIKit.SCREEN_W - FAM_SIDE * 2.0 - FAM_GAP * (count - 1)) / count
	for i in count:
		var holder := _build_answer_column(Vector2(w, FAM_BOTTOM - FAM_TOP), accents[i],
			FAMILIARITY_ANSWERS[i], ANSWER_FONT, FAMILIARITY_ROWS[i],
			_on_familiarity_clicked.bind(i))
		holder.position = Vector2(FAM_SIDE + i * (w + FAM_GAP), FAM_TOP)
		page.add_child(holder)
		_fam_holders.append(holder)

	_fam_ring_layer = _ring_layer_on(page)
	_select_familiarity(0, false)


## Page 2: "Would you like to enable Hard Mode?" — Normal and Hard side by side.
func _build_hard_mode_page() -> void:
	var page := _new_page("hard_mode")
	page.visible = false
	_pages.append(page)
	_add_heading(page, "Would you like to enable Hard Mode?")

	# The familiarity answer, repeated as a quiet chip so the player can see why
	# they are being asked. Filled in each time the page opens.
	var chip_row := CenterContainer.new()
	chip_row.position = Vector2(0.0, MODE_CHIP_Y)
	chip_row.size = Vector2(UIKit.SCREEN_W, 40.0)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(chip_row)
	_mode_context_chip = chip_row

	var accents := [UITheme.col("good"), UITheme.col("danger")]
	var left: float = (UIKit.SCREEN_W - MODE_W * 2.0 - MODE_GAP) * 0.5
	for i in 2:
		var holder := _build_answer_column(Vector2(MODE_W, MODE_BOTTOM - MODE_TOP), accents[i],
			MODE_TITLES[i], MODE_TITLE_FONT, MODE_ROWS[i], _on_mode_clicked.bind(i == 1))
		holder.position = Vector2(left + i * (MODE_W + MODE_GAP), MODE_TOP)
		page.add_child(holder)
		_mode_holders.append(holder)

	var note := Label.new()
	note.text = MODE_NOTE
	note.add_theme_font_override("font", UITheme.font_at(UITheme.FONT_UI_MEDIUM))
	note.add_theme_font_size_override("font_size", ROW_FONT - 2)
	note.add_theme_color_override("font_color", UITheme.col("field_mute"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(0.0, MODE_NOTE_Y)
	note.size = Vector2(UIKit.SCREEN_W, 40.0)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(note)

	_mode_ring_layer = _ring_layer_on(page)
	_select_mode(false, false)


func _refresh_mode_context() -> void:
	for child in _mode_context_chip.get_children():
		_mode_context_chip.remove_child(child)
		child.queue_free()
	_mode_context_chip.add_child(UIKit.make_chip(FAMILIARITY_ANSWERS[_familiarity], "on_field"))


## The question, centred under the header.
func _add_heading(page: Control, text: String) -> void:
	var heading := Label.new()
	UIKit.style_label(heading, "body", "field_fg", HEADING_FONT)
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.position = Vector2(0.0, HEADING_Y)
	heading.size = Vector2(UIKit.SCREEN_W, HEADING_H)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(heading)


## One answer: a translucent panel with a coloured pill along the top, the answer
## itself in bold, a divider, then its rows. A transparent catcher Button is added
## LAST so it is what receives the click.
func _build_answer_column(col_size: Vector2, accent: Color, title: String,
		title_size: int, rows: Array, on_click: Callable) -> Control:
	var holder := Control.new()
	holder.size = col_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := UIKit.make_panel()
	panel.size = col_size
	panel.custom_minimum_size = col_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)

	var pill := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.set_corner_radius_all(int(ACCENT_H))
	sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", sb)
	pill.position = Vector2(ACCENT_INSET, ACCENT_Y)
	pill.size = Vector2(col_size.x - ACCENT_INSET * 2.0, ACCENT_H)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pill)

	var inner_w: float = col_size.x - ROW_PAD * 2.0
	var answer := Label.new()
	answer.text = title
	answer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.add_theme_font_override("font", UITheme.font_at(UITheme.FONT_UI_BOLD))
	answer.add_theme_font_size_override("font_size", title_size)
	answer.add_theme_color_override("font_color", UITheme.col("field_fg"))
	answer.position = Vector2(ROW_PAD, ANSWER_TOP)
	answer.size = Vector2(inner_w, ANSWER_H)
	answer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(answer)

	var divider_y: float = ANSWER_TOP + ANSWER_H + 8.0
	var divider := ColorRect.new()
	divider.color = UITheme.col("line")
	divider.position = Vector2(ROW_PAD, divider_y)
	divider.size = Vector2(inner_w, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(divider)

	var y: float = divider_y + ROWS_GAP
	for row in rows:
		var kind: String = row[0]
		var icon := Control.new()
		icon.size = Vector2(ICON, ICON)
		icon.position = Vector2(ROW_PAD, y + (ROW_H - ICON) * 0.5)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_row_icon.bind(icon, kind))
		holder.add_child(icon)

		var lbl := Label.new()
		lbl.text = row[1]
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var bold: bool = kind == "deck"
		lbl.add_theme_font_override("font",
			UITheme.font_at(UITheme.FONT_UI_BOLD if bold else UITheme.FONT_UI_MEDIUM))
		lbl.add_theme_font_size_override("font_size", ROW_FONT)
		var ink: Color = UITheme.col("field_fg")
		if kind == "off":
			ink.a = OFF_ALPHA
		lbl.add_theme_color_override("font_color", ink)
		var text_x: float = ROW_PAD + ICON + ICON_GAP
		lbl.position = Vector2(text_x, y)
		lbl.size = Vector2(col_size.x - text_x - ROW_PAD, ROW_H)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lbl)
		y += ROW_H

	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		catcher.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	catcher.position = Vector2.ZERO
	catcher.size = col_size
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	catcher.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(event.double_click))
	holder.add_child(catcher)
	return holder


## Drawn, not typed: a tick or cross glyph is not guaranteed in the UI fonts.
func _draw_row_icon(c: Control, kind: String) -> void:
	var s: float = ICON
	var w: float = 4.0
	match kind:
		"on":
			c.draw_polyline(PackedVector2Array([Vector2(s * 0.14, s * 0.52),
				Vector2(s * 0.40, s * 0.78), Vector2(s * 0.88, s * 0.22)]),
				UITheme.col("good"), w, true)
		"off":
			var red: Color = UITheme.col("danger")
			c.draw_line(Vector2(s * 0.2, s * 0.2), Vector2(s * 0.8, s * 0.8), red, w, true)
			c.draw_line(Vector2(s * 0.8, s * 0.2), Vector2(s * 0.2, s * 0.8), red, w, true)
		"warn":
			var amber: Color = UITheme.col("warn")
			c.draw_line(Vector2(s * 0.5, s * 0.1), Vector2(s * 0.5, s * 0.6), amber, w, true)
			c.draw_circle(Vector2(s * 0.5, s * 0.84), w * 0.7, amber)
		"deck":
			c.draw_rect(Rect2(s * 0.22, s * 0.06, s * 0.56, s * 0.88),
				UITheme.col("field_fg"), false, 3.0, true)


## A flat layer for the selection ring, last on the page so it draws over the
## columns (rings are never parented to what they ring — see add_selection_ring).
func _ring_layer_on(page: Control) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.position = Vector2.ZERO
	layer.size = page.size
	page.add_child(layer)
	return layer


func _ring(layer: Control, old_ring: Control, target: Control) -> Control:
	if old_ring != null and is_instance_valid(old_ring):
		layer.remove_child(old_ring)
		old_ring.queue_free()
	return UIKit.add_selection_ring(layer, target, float(UITheme.mi("panel_radius")))


func _select_familiarity(index: int, with_sound: bool = true) -> void:
	_familiarity = index
	if with_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)
	for i in _fam_holders.size():
		_fam_holders[i].modulate = Color.WHITE if i == index else Color(DIM, DIM, DIM)
	_fam_ring = _ring(_fam_ring_layer, _fam_ring, _fam_holders[index])
	if _page == 1:
		_refresh_footer()


func _select_mode(hard: bool, with_sound: bool = true) -> void:
	_hard_mode = hard
	if with_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)
	var index: int = 1 if hard else 0
	for i in _mode_holders.size():
		_mode_holders[i].modulate = Color.WHITE if i == index else Color(DIM, DIM, DIM)
	_mode_ring = _ring(_mode_ring_layer, _mode_ring, _mode_holders[index])


func _on_familiarity_clicked(double: bool, index: int) -> void:
	if _switching or _leaving:
		return
	if index != _familiarity:
		_select_familiarity(index)
	if double:
		_on_next_pressed()


func _on_mode_clicked(double: bool, hard: bool) -> void:
	if _switching or _leaving:
		return
	if hard != _hard_mode:
		_select_mode(hard)
	if double:
		_on_next_pressed()


## Only the two harder answers are offered Hard Mode.
func _offers_hard_mode() -> bool:
	return _familiarity >= 2


# ─── Paging ──────────────────────────────────────────────────────────────────

func _on_next_pressed() -> void:
	if _switching or _leaving:
		return
	match _page:
		0:
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
			_show_page(1)
		1:
			if _offers_hard_mode():
				SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
				_show_page(2)
			else:
				_start_game()
		2:
			_start_game()


func _on_back_pressed() -> void:
	if _switching or _leaving or _page == 0:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_show_page(_page - 1)


func _show_page(index: int) -> void:
	_switching = true
	# The name and birthday boxes would otherwise keep the keyboard while hidden.
	get_viewport().gui_release_focus()

	var from: Control = _pages[_page]
	var out := create_tween()
	out.tween_property(from, "modulate:a", 0.0, PAGE_FADE)
	await out.finished
	from.visible = false

	_page = index
	_set_header_chip(CHIP_TEXT[index])
	if index == 2:
		_refresh_mode_context()
	_refresh_footer()

	var to: Control = _pages[index]
	to.modulate.a = 0.0
	to.visible = true
	var fade_in := create_tween()
	fade_in.tween_property(to, "modulate:a", 1.0, PAGE_FADE)
	await fade_in.finished
	_switching = false


## Back only after the first page. The forward button says "Start New Game" on
## whichever page is the last one for the answers given.
func _refresh_footer() -> void:
	_back_btn.visible = _page > 0
	if _page == 0:
		_save_btn.text = "Next"
		_refresh_save_btn()
		return
	var last: bool = _page == 2 or not _offers_hard_mode()
	_save_btn.text = "Start New Game" if last else "Next"
	_save_btn.disabled = false
	UIKit.style_button(_save_btn, "primary")


func _input(event: InputEvent) -> void:
	# The first page belongs to its text boxes and sprite grid.
	if _page == 0 or _switching or _leaving:
		return
	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif UIInput.is_accept(event):
		get_viewport().set_input_as_handled()
		_on_next_pressed()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		var step: int = -1 if event.is_action_pressed("ui_left") else 1
		if _page == 1:
			_select_familiarity(wrapi(_familiarity + step, 0, FAMILIARITY_ANSWERS.size()))
		else:
			_select_mode(not _hard_mode)
