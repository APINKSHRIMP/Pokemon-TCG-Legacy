extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"

# ISSUE #199: SQUARE CELLS, EXPLICIT SIZES, NO EXPAND_FILL.
#
# The old cell was a 100x200 portrait TextureRect with SIZE_EXPAND_FILL and
# EXPAND_FIT_WIDTH_PROPORTIONAL, which is three separate ways of letting the
# layout engine decide the size: the columns shared the leftover width so the
# cell came out WIDE rather than square, and fit-width-proportional then grew the
# sprite height to match that width, which is what made the sprites burst out of
# their boxes and overlap.
#
# This follows the confirmed grid pattern instead - square cell, minf fit scale,
# STRETCH_SCALE, explicit size and position inside a clipping wrapper - and the
# columns are sized so nine of them plus their gaps fill the width exactly, so
# there is no leftover for EXPAND_FILL to hand out.
#   9 * 200 + 8 * 12 = 1896, inside the 1920 band with room for the scrollbar.
const COLUMNS            := 9
const CELL_SIZE          := Vector2(200.0, 200.0)
const SPRITE_SEPARATION  := 12
## ISSUE #199: the sprite is drawn at this much of the cell, so it sits INSIDE its
## box with a margin rather than filling it edge to edge.
const SPRITE_FIT         := 0.84
## ISSUE #162: TWEAKABLE - peak scale of the selected-costume pulse.
const SELECT_PULSE       := 1.2

# Inset of the grid inside the band between the two chrome bars, and the fixed
# width of the owned-only toggle so it does not resize between its two labels.
const GRID_INSET_X       := 0.0
const GRID_INSET_Y       := 18.0
const FILTER_BTN_W       := 340.0

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
var PLAYER_PROGRESS_PATH: String:
	get: return GameState.PROGRESS_PATH

# ─── State ───────────────────────────────────────────────────────────────────

var selected_character_path : String = ""
var selected_character_rect : Control = null

# The sprite name stored in player_data.json on load — used to detect unsaved changes
var saved_sprite_name       : String = ""

var _active_tween           : Tween = null
var _last_clicked_rect      : Control = null

# ISSUE #32: input-blocking loading overlay shown while the costume grid builds.
var _loading_overlay        : MenuLoadingOverlay = MenuLoadingOverlay.new()

# Flat set of owned costume filenames e.g. {"1dawn_platinum.png": true}
# Using a Dictionary as a set gives O(1) lookups vs iterating an Array
var _owned_costumes         : Dictionary = {}

# ─── Owned-only filter ───────────────────────────────────────────────────────
# The scene always opens with unowned costumes hidden so the grid only builds the handful
# the player actually owns rather than hundreds of black silhouettes. Deliberately NOT
# persisted or cached — every visit starts hidden and the player presses Show if they
# want the full wardrobe.
var _hide_unowned           : bool = true
var _is_rebuilding          : bool = false

# Header slot holding the "n / N" owned chip, and the size of the universe it
# counts against (filled while the sprite folder is scanned).
var _count_chip_holder      : Control = null
var _total_costumes         : int = 0

# ─── Zoom state ──────────────────────────────────────────────────────────────
var zoom_overlay        : CanvasLayer = null
var is_zoomed           : bool = false
var last_zoomed_costume : Control = null
# ISSUE #98: hold-to-preview, matching the deck builder. While Shift is held _process re-reads the
# hovered costume every frame; the preview is sticky over the gaps between cells so sliding across
# the grid never flashes the UI back on. Only releasing Space closes it.
var zoom_held          : bool = false
var zoomed_costume      : Control = null
var zoom_image          : TextureRect = null

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"trainer_grid_container"
@onready var save_btn    : Button        = $"trainer_save_button"
@onready var cancel_btn  : Button        = $"trainer_cancel_button"
@onready var hide_btn    : Button        = $"hide_button"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)

	var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
	audio_player.stream = audio_stream
	audio_player.bus = SoundManagerScript.MUSIC_BUS
	audio_player.stream.loop = true
	audio_player.play()

	_load_owned_costumes_list()
	_load_player_data()

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	hide_btn.pressed.connect(_on_hide_pressed)
	_refresh_hide_button()

	_build_chrome()
	_wrap_grid_in_scroll_container()
	# ISSUE #32: block input behind a loading overlay while the (potentially large) costume grid builds.
	# Retest: shrink the blocker 142px top / 134px bottom so the banner buttons (Cancel) stay clickable.
	# The hide button sits in that unblocked top strip, so disable it outright while a build runs.
	hide_btn.disabled = true
	_loading_overlay.show_for_library(self)
	await get_tree().process_frame
	await _load_characters()
	_loading_overlay.hide()
	if not is_inside_tree():
		return
	hide_btn.disabled = false

	if saved_sprite_name != "":
		_select_character_by_name(saved_sprite_name)


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
	# Costume filenames are stored lower-cased by GameState.add_costume_to_collection,
	# but the sprite folder uses mixed-case filenames. Key the set lower-cased (and
	# look up lower-cased in _add_character_to_grid) so matching is case-insensitive.
	for costume_name in data["costumes"]:
		_owned_costumes[String(costume_name).to_lower()] = true
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

	if data.has("sprite"):
		var raw : String = data["sprite"]
		if not raw.ends_with(".png"):
			raw = raw + ".png"
		saved_sprite_name = raw


# ─── Scroll container setup ──────────────────────────────────────────────────

## Swaps the old bordered chrome for the Spectrum Night bars and moves this
## screen's own controls into them. Runs BEFORE _wrap_grid_in_scroll_container(),
## which copies the grid's position and size onto the ScrollContainer it makes.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "Costumes")

	var old_title := get_node_or_null("large_header_text_label")
	if old_title != null:
		old_title.queue_free()

	_count_chip_holder = bars["header"].left
	_refresh_count_chip()

	UIKit.adopt_button(hide_btn, bars["header"].right, "secondary", false)
	hide_btn.custom_minimum_size.x = FILTER_BTN_W

	# Cancel first: the footer slot is an HBox, so insertion order is left-to-right.
	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")
	UIKit.adopt_button(save_btn, bars["footer"].centre, "primary")

	grid.position = Vector2(GRID_INSET_X, UIKit.CONTENT_TOP + GRID_INSET_Y)
	grid.size = Vector2(1920.0 - GRID_INSET_X * 2.0, UIKit.CONTENT_H - GRID_INSET_Y * 2.0)


## Rebuilds the "n / N" owned chip in the header.
func _refresh_count_chip() -> void:
	if _count_chip_holder == null or not is_instance_valid(_count_chip_holder):
		return
	for c in _count_chip_holder.get_children():
		c.queue_free()
	_count_chip_holder.add_child(
		UIKit.make_chip("%d / %d" % [_owned_costumes.size(), _total_costumes], "on_chrome"))


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
	# ISSUE #144 FIX: the scroll container spans the full 1920 and the columns share the leftover
	# width (see the EXPAND_FILL in _add_character_to_grid), so the last costume in a row finishes
	# against the scrollbar instead of ~120px short of it.
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

	# The folder listing IS the universe the header chip counts against.
	_total_costumes = files.size()
	_refresh_count_chip()

	for fname in files:
		# ISSUE #32 FIX: bail if the scene was cancelled/freed mid-load (get_tree() would be null).
		if not is_inside_tree():
			return
		# Owned-only mode skips unowned costumes before the per-item frame yield below. That yield is
		# what makes a full build take seconds, so never queuing them is the entire speed-up.
		if _hide_unowned and not _owned_costumes.has(String(fname).to_lower()):
			continue
		_add_character_to_grid(fname)
		await get_tree().process_frame


## ISSUE #199: one square cell. The grid child is a WRAPPER Control, not the
## TextureRect - the box, the sprite and the click target are three different
## things and only the wrapper is allowed to be the cell.
##
## EVERY costume gets a box now, owned or not. The boxes used to appear only on
## the silhouettes, so the default costumes - which are always owned - sat in
## empty space while everything around them was framed.
func _add_character_to_grid(file_name: String) -> void:
	var texture := load(SPRITE_FOLDER + "/" + file_name) as Texture2D
	if texture == null:
		return

	var is_owned : bool = _owned_costumes.has(file_name.to_lower())

	var cell := Control.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.size                = CELL_SIZE
	# NOT clipped: the fit maths above already keeps the sprite inside the cell,
	# and clipping would cut its edges off the moment the selection pulse grew it.
	cell.clip_contents       = false
	cell.pivot_offset        = CELL_SIZE / 2.0
	cell.set_meta("sprite_name", file_name)
	cell.set_meta("is_owned",    is_owned)
	# The zoom preview reads the art off the cell rather than reaching into it.
	cell.set_meta("costume_texture", texture)

	# The box. A child of the cell drawn behind everything else, sized to the cell
	# in real pixels - an anchored slot would still be 0x0 on this frame.
	var slot := UIKit.make_slot(CELL_SIZE)
	slot.position = Vector2.ZERO
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(slot)

	# The sprite: explicit fit maths, never the layout engine. minf, not maxf -
	# a costume must be wholly visible, not cropped to fill.
	var tex_size := texture.get_size()
	var fit : float = minf(CELL_SIZE.x / tex_size.x, CELL_SIZE.y / tex_size.y) * SPRITE_FIT
	var disp := Vector2(tex_size.x * fit, tex_size.y * fit)

	var rect := TextureRect.new()
	rect.texture      = texture
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size         = disp
	rect.custom_minimum_size = disp
	rect.position     = (CELL_SIZE - disp) / 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(rect)
	# Selection dims and brightens the SPRITE, never the cell: modulate propagates
	# and would drag the box outline up and down with it.
	cell.set_meta("art_node", rect)

	if is_owned:
		rect.modulate = Color(0.8, 0.8, 0.8)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_character_clicked.bind(cell))
	else:
		# Keep the real texture but zero out all RGB channels - that turns the
		# sprite into a solid silhouette with no texture swap needed. It is the
		# SPRITE that is blacked out, never the cell: modulate propagates to
		# children and would take the box outline with it.
		rect.self_modulate = Color(0, 0, 0, 1)
		cell.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	grid.add_child(cell)


func _select_character_by_name(sprite_name: String) -> void:
	for child in grid.get_children():
		if child.has_meta("sprite_name") and String(child.get_meta("sprite_name", "")).to_lower() == sprite_name.to_lower():
			_select_character(child)
			return


# ─── Owned-only filter ───────────────────────────────────────────────────────

# Blue "Show" while the unowned silhouettes are filtered out, yellow "Hide" while everything is on show.
func _refresh_hide_button() -> void:
	hide_btn.text = "Show all costumes" if _hide_unowned else "Show owned only"
	UIKit.style_button(hide_btn, "secondary")


func _on_hide_pressed() -> void:
	if _is_rebuilding:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_hide_unowned = not _hide_unowned
	_refresh_hide_button()
	await _rebuild_grid()


# Tears the grid down and rebuilds it under the current filter. The player's pending pick
# survives: only owned costumes are selectable and hiding never removes an owned costume, so
# we just re-select it by name once the new rects exist.
func _rebuild_grid() -> void:
	_is_rebuilding    = true
	hide_btn.disabled = true

	var pending_name : String = ""
	if selected_character_rect != null and is_instance_valid(selected_character_rect):
		pending_name = String(selected_character_rect.get_meta("sprite_name", ""))

	# The looping tween references a rect that is about to be freed.
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	selected_character_rect = null
	selected_character_path = ""
	_last_clicked_rect      = null

	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var scroll := grid.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0

	_loading_overlay.show_for_library(self)
	await get_tree().process_frame
	await _load_characters()
	_loading_overlay.hide()
	if not is_inside_tree():
		return

	if pending_name == "":
		pending_name = saved_sprite_name
	if pending_name != "":
		_select_character_by_name(pending_name)
	_refresh_save_button_state()

	hide_btn.disabled = false
	_is_rebuilding    = false


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_character_clicked(event: InputEvent, rect: Control) -> void:
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


func _select_character(rect: Control) -> void:
	selected_character_rect = rect
	selected_character_path = SPRITE_FOLDER + "/" + rect.get_meta("sprite_name", "")
	_apply_selected_animation(rect)


func _deselect_character(rect: Control) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	_costume_art(rect).modulate = Color(0.8, 0.8, 0.8)
	rect.scale        = Vector2(1.0, 1.0)
	rect.pivot_offset = rect.size / 2.0


## The TextureRect inside a costume cell. Falls back to the cell so a caller can
## never end up with null.
func _costume_art(cell: Control) -> Control:
	var art = cell.get_meta("art_node", null)
	return art if (art != null and is_instance_valid(art)) else cell


func _apply_selected_animation(rect: Control) -> void:
	if _active_tween:
		_active_tween.kill()

	rect.pivot_offset = rect.size / 2.0
	var art := _costume_art(rect)
	art.modulate = Color.WHITE

	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween

	tween.tween_property(art, "modulate", Color.WHITE * 1.1, 0.2)
	# ISSUE #162: grows to SELECT_PULSE, up from 1.1 - a 10% pulse was too subtle
	# to show which costume was picked.
	tween.parallel().tween_property(rect, "scale", Vector2(SELECT_PULSE, SELECT_PULSE), 0.2)
	tween.tween_property(art, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Save button state ───────────────────────────────────────────────────────

# Called whenever the sprite selection or name box changes.
# The save button is enabled if either the chosen sprite OR the typed name
# differs from what is currently stored in player_data.json.
func _refresh_save_button_state() -> void:
	var sprite_changed := false
	if selected_character_rect != null:
		sprite_changed = selected_character_rect.get_meta("sprite_name", "") != saved_sprite_name

	if sprite_changed:
		save_btn.disabled = false
		UIKit.style_button(save_btn, "good")
	else:
		save_btn.disabled = true
		UIKit.style_button(save_btn, "primary")


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

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("TrainerCard: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	save_btn.disabled = true
	UIKit.style_button(save_btn, "primary")


func _on_cancel_pressed() -> void:
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape / zoom-key input ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# ── Hold-to-preview ──
	# Shift, not Space. Space is the accept key (ISSUE #97: an unhandled press fell through to
	# "ui_accept" and re-pressed whichever button still had focus). Shift has no other job here,
	# so nothing needs consuming. Tested before the InputEventKey branch so a pad reaches it too.
	if UIInput.is_zoom_start(event):
		zoom_held = true
		_refresh_hover_preview()
		return
	if UIInput.is_zoom_end(event):
		zoom_held = false
		_hide_zoom()
		return

	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if is_zoomed:
				zoom_held = false   # ISSUE #98: drop the hold too, or _process re-opens the preview
				_hide_zoom()
				return
			if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
			return

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		call_deferred("_check_click_miss")


# ISSUE #98: while the zoom key is held, keep the preview locked to whatever costume the mouse is
# over. The is_zoom_held() re-check catches an alt-tab that swallowed the key release, which would
# otherwise leave the preview stuck open.
func _process(_delta: float) -> void:
	if not zoom_held:
		return
	if not UIInput.is_zoom_held():
		zoom_held = false
		_hide_zoom()
		return
	_refresh_hover_preview()


func _refresh_hover_preview() -> void:
	var rect := _get_hovered_costume()
	if rect == zoomed_costume:
		return
	if rect == null:
		return   # gap between costumes — hold the current preview rather than flashing it off
	_show_zoom(rect)


func _check_click_miss() -> void:
	if _last_clicked_rect == null:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_last_clicked_rect = null


# ─── Costume zoom ─────────────────────────────────────────────────────────────

func _get_hovered_costume() -> Control:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	var node = hovered
	for i in range(5):
		if node == null:
			return null
		if node.has_meta("sprite_name") and node.get_meta("is_owned", false):
			return node as Control
		node = node.get_parent()
	return null


func _show_zoom(rect: Control) -> void:
	# ISSUE #199: the grid child is a wrapper Control now, so the art comes off a
	# meta rather than off the node.
	var art: Texture2D = rect.get_meta("costume_texture", null)
	if art == null:
		return

	last_zoomed_costume = rect
	zoomed_costume      = rect

	# ISSUE #98: overlay already up — swap the image in place rather than rebuilding the CanvasLayer,
	# which flashed the bright costume grid through for a frame on every hover change.
	if is_zoomed and zoom_image != null and is_instance_valid(zoom_image):
		_apply_zoom_texture(art)
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
	_apply_zoom_texture(art)


# Scale to 9× the grid cell size (100×200), capped so it fits on screen
func _apply_zoom_texture(tex: Texture2D) -> void:
	var tex_size  := tex.get_size()
	var target    := Vector2(900.0, 1800.0)
	var s         := minf(target.x / tex_size.x, target.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	zoom_image.texture  = tex
	zoom_image.size     = disp_size
	zoom_image.position = Vector2((1920.0 - disp_size.x) / 2.0, (1080.0 - disp_size.y) / 2.0)


func _hide_zoom() -> void:
	if not is_zoomed:
		return
	is_zoomed      = false
	zoomed_costume = null
	zoom_image     = null
	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null
