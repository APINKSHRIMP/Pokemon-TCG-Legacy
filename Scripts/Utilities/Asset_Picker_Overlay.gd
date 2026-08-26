class_name AssetPickerOverlay
extends CanvasLayer

## Full-screen grid picker for one asset kind -- overworld sprite, coin, sleeve or
## costume. Debug tooling: the character editor uses it for every "pick an asset"
## field, so choosing a sprite or a coin is looking at the art rather than typing a
## filename and finding out later that it does not exist.
##
## The three menu pickers (Coin_Case_Script, Sleeves_Scene_Script, Costume_Script)
## each build their own grid bound to a menu .tscn and cannot be dropped into a map
## scene, so this is separate code -- but it is the same proven shape: a
## ScrollContainer wrap, a batched build loop, set_meta() as the selection key, and
## a dark unclickable silhouette for anything that cannot be chosen.
##
##   click       select (double-click confirms)
##   Enter       confirm the selection
##   Escape      cancel
##   type        filter by name

signal picked(value: String)
signal cancelled

enum Kind { SPRITE, COIN, SLEEVE, COSTUME }

const SPRITE_DIR   := "res://Image_Assets/Character_Sprites/Overworld_Sprites/"
const COIN_DIR     := "res://Image_Assets/Coins/"
const SLEEVE_DIR   := "res://Image_Assets/Sleeves/small/"
const COSTUME_DIR  := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"
const PORTRAIT_DIR := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"

# Grid geometry per kind. The usable width is 1826px (1920 less a 40px margin each
# side, less the scrollbar), so columns * cell + (columns - 1) * separation has to
# land under that or the last column is clipped.
const CELL_SIZE_SPRITE  := Vector2(96, 96)
const CELL_SIZE_COIN    := Vector2(104, 104)
const CELL_SIZE_SLEEVE  := Vector2(150, 210)
const CELL_SIZE_COSTUME := Vector2(100, 200)

const COLUMNS_SPRITE  := 17
const COLUMNS_COIN    := 16
const COLUMNS_SLEEVE  := 11
const COLUMNS_COSTUME := 16

const SEPARATION := 8

## Cells built per frame. One-at-a-time is what makes the sleeve menu take ten
## seconds; a batch keeps 600 items under a second while still yielding often
## enough that the frame never locks up.
const BUILD_BATCH := 24

const FONT_SIZE := 22
const TITLE_FONT_SIZE := 30

const MARGIN := 40
const HEADER_H := 118
const FOOTER_H := 84

var _kind: int = Kind.SPRITE
var _selected_value: String = ""
## value -> true. Rendered as a dark unclickable silhouette.
var _unavailable: Dictionary = {}
## Only meaningful for Kind.SPRITE: flags sprites with no in-battle portrait.
var _warn_missing_portrait: bool = false

var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _filter_edit: LineEdit = null
var _status: Label = null
var _confirm_btn: Button = null
var _selected_cell: Control = null
var _outline: Panel = null
var _closing: bool = false

static var _sprite_frame_cache: Dictionary = {}


# ============================================================
# SETUP
# ============================================================

## `unavailable` maps value -> true for anything that must be visible but not
## choosable. `current` is preselected and is always choosable even when it appears
## in `unavailable`, so re-opening the picker on an existing character does not grey
## out that character's own coin.
func setup(kind: int, current: String = "", unavailable: Dictionary = {},
		warn_missing_portrait: bool = false) -> void:
	_kind = kind
	_selected_value = current
	_unavailable = unavailable.duplicate()
	_unavailable.erase(current)
	_warn_missing_portrait = warn_missing_portrait
	layer = 130
	_build_ui()
	_populate()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = DebugFormTheme.BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so nothing behind the picker -- the form, or the map itself --
	# reacts to a click aimed at a cell.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Same white-on-dark treatment as the form this is opened from; a Theme set here
	# reaches the filter box, both footer buttons and the scrollbar.
	dim.theme = DebugFormTheme.build()
	add_child(dim)

	var title := Label.new()
	title.text = _title_text()
	title.position = Vector2(MARGIN, 24)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	dim.add_child(title)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter by name....."
	_filter_edit.position = Vector2(MARGIN, 66)
	_filter_edit.size = Vector2(560, 40)
	_filter_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_filter_edit.text_changed.connect(_on_filter_changed)
	_filter_edit.text_submitted.connect(func(_t: String): _confirm())
	dim.add_child(_filter_edit)

	_status = Label.new()
	_status.position = Vector2(MARGIN + 584, 70)
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_status.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	dim.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(MARGIN, HEADER_H)
	_scroll.size = Vector2(1920 - MARGIN * 2, 1080 - HEADER_H - FOOTER_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dim.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = _columns()
	_grid.add_theme_constant_override("h_separation", SEPARATION)
	_grid.add_theme_constant_override("v_separation", SEPARATION)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	# The selection outline is a child of the selected cell but sized to it and
	# MOUSE_FILTER_IGNORE, so it never changes the cell's minimum size and never
	# eats the click that selects it.
	_outline = Panel.new()
	_outline.visible = false
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color(0, 0, 0, 0)
	outline_style.border_color = Color(0.45, 1.0, 0.55)
	outline_style.set_border_width_all(4)
	outline_style.set_corner_radius_all(4)
	_outline.add_theme_stylebox_override("panel", outline_style)
	# Parked in the tree until something is selected. A Node built but never added
	# is an orphan that outlives the CanvasLayer it was meant to belong to.
	dim.add_child(_outline)

	_confirm_btn = Button.new()
	_confirm_btn.text = "CONFIRM"
	_confirm_btn.position = Vector2(1920 / 2 - 330, 1080 - FOOTER_H + 12)
	_confirm_btn.size = Vector2(320, 56)
	_confirm_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_confirm)
	dim.add_child(_confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.position = Vector2(1920 / 2 + 10, 1080 - FOOTER_H + 12)
	cancel_btn.size = Vector2(320, 56)
	cancel_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	cancel_btn.pressed.connect(_cancel)
	dim.add_child(cancel_btn)


func _title_text() -> String:
	match _kind:
		Kind.SPRITE:  return "CHOOSE AN OVERWORLD SPRITE"
		Kind.COIN:    return "CHOOSE A COIN"
		Kind.SLEEVE:  return "CHOOSE A SLEEVE"
		Kind.COSTUME: return "CHOOSE A COSTUME"
	return "CHOOSE"


func _columns() -> int:
	match _kind:
		Kind.SPRITE:  return COLUMNS_SPRITE
		Kind.COIN:    return COLUMNS_COIN
		Kind.SLEEVE:  return COLUMNS_SLEEVE
		Kind.COSTUME: return COLUMNS_COSTUME
	return 12


func _cell_size() -> Vector2:
	match _kind:
		Kind.SPRITE:  return CELL_SIZE_SPRITE
		Kind.COIN:    return CELL_SIZE_COIN
		Kind.SLEEVE:  return CELL_SIZE_SLEEVE
		Kind.COSTUME: return CELL_SIZE_COSTUME
	return Vector2(96, 96)


func _folder() -> String:
	match _kind:
		Kind.SPRITE:  return SPRITE_DIR
		Kind.COIN:    return COIN_DIR
		Kind.SLEEVE:  return SLEEVE_DIR
		Kind.COSTUME: return COSTUME_DIR
	return SPRITE_DIR


# ============================================================
# VALUES
# ============================================================

## The choosable values for this kind, sorted, in the exact spelling the JSON wants
## -- bare basenames, matching how sprite / coin_reward / sleeve / costume values
## are all written in the data.
func _values() -> Array:
	var names: Dictionary = {}
	var dir := DirAccess.open(_folder())
	if dir == null:
		push_error("AssetPickerOverlay: cannot open " + _folder())
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			# "Back Basic" is the unowned-coin placeholder art, not a collectible.
			if not (_kind == Kind.COIN and clean == "Back Basic.png"):
				names[clean.get_basename()] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var out: Array = names.keys()
	out.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


## Texture for one value. Sleeves are a mix of .jpg and .png, so both are tried.
func _texture_for(value: String) -> Texture2D:
	if _kind == Kind.SPRITE:
		return sprite_frame(value)
	for ext in [".png", ".jpg"]:
		var path: String = _folder() + value + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null


## The idle-down frame of a 4x4 overworld sheet, untrimmed.
##
## DynamicMessageBox.sprite_icon() trims to the opaque pixels, which is right for a
## chip sitting inline with text but wrong here: in a uniform grid the trim makes
## every character a different size and none of them share a ground line. It also
## costs 4096 get_pixel() calls per sprite, which across 431 sprites is a visible
## stall on the first open.
static func sprite_frame(sprite_name: String) -> Texture2D:
	if _sprite_frame_cache.has(sprite_name):
		return _sprite_frame_cache[sprite_name]
	var path := SPRITE_DIR + sprite_name + ".png"
	if not ResourceLoader.exists(path):
		_sprite_frame_cache[sprite_name] = null
		return null
	var sheet: Texture2D = load(path)
	if sheet == null:
		_sprite_frame_cache[sprite_name] = null
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	# Every sheet is sliced by quarters -- four of the 431 are not 256x256, so the
	# frame size has to be derived rather than hardcoded to 64.
	atlas.region = Rect2(0, 0, sheet.get_width() / 4.0, sheet.get_height() / 4.0)
	_sprite_frame_cache[sprite_name] = atlas
	return atlas


## True when this overworld sprite has a matching in-battle portrait. An opponent
## needs both -- Match_Start_Intro_Script builds the portrait path from the same
## string, lower-cased -- and there are 431 overworld sprites against 221 portraits.
static func has_battle_portrait(sprite_name: String) -> bool:
	for ext in [".png", ".jpg"]:
		var portrait: String = PORTRAIT_DIR + sprite_name.to_lower() + ext
		if ResourceLoader.exists(portrait):
			return true
	return false


# ============================================================
# GRID
# ============================================================

func _populate() -> void:
	var values := _values()
	var cell := _cell_size()
	var built := 0
	for value in values:
		if _closing or not is_inside_tree():
			return
		_add_cell(str(value), cell)
		built += 1
		if built % BUILD_BATCH == 0:
			await get_tree().process_frame
	# Re-apply the incoming selection once every cell exists.
	if _selected_value != "":
		_select_by_value(_selected_value, false)
	_refresh_status(values.size())


func _add_cell(value: String, cell: Vector2) -> void:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = cell
	# ISSUE #144 shape: without SIZE_EXPAND a GridContainer sizes each column to its
	# widest child's MINIMUM width and leaves the leftover width unused on the right.
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.clip_contents = true
	wrapper.set_meta("value", value)
	wrapper.tooltip_text = value

	var tex := _texture_for(value)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Letterbox: minf fits the whole frame inside the cell. maxf would crop, which
		# is right for sleeve art but wrong for a character who would lose their head.
		var tex_size: Vector2 = tex.get_size()
		var factor: float = 1.0
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			factor = minf(cell.x / tex_size.x, cell.y / tex_size.y)
		var shown: Vector2 = tex_size * factor
		rect.size = shown
		rect.position = (cell - shown) / 2.0
		wrapper.add_child(rect)

	if _unavailable.has(value):
		# Dark silhouette, unhoverable and unclickable -- the same treatment unowned
		# coins and sleeves get in the menus.
		wrapper.modulate = Color(0.22, 0.22, 0.26)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.tooltip_text = value + "  (already taken)"
	else:
		wrapper.mouse_filter = Control.MOUSE_FILTER_STOP
		wrapper.gui_input.connect(_on_cell_input.bind(wrapper))

	if _kind == Kind.SPRITE and _warn_missing_portrait and not has_battle_portrait(value):
		var badge := ColorRect.new()
		badge.color = Color(1.0, 0.62, 0.18)
		badge.size = Vector2(cell.x, 5)
		badge.position = Vector2(0, cell.y - 5)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(badge)
		wrapper.tooltip_text = value + "  (no in-battle portrait)"

	_grid.add_child(wrapper)


func _on_cell_input(event: InputEvent, wrapper: Control) -> void:
	# A mouse wheel arrives as an InputEventMouseButton with pressed = true, so
	# without the button check scrolling the grid would pick whatever is under the
	# cursor.
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	var was := _selected_cell
	_select_cell(wrapper)
	if event.double_click and was == wrapper:
		_confirm()


func _select_by_value(value: String, play_sound: bool = true) -> void:
	for child in _grid.get_children():
		if child is Control and str(child.get_meta("value", "")) == value:
			_select_cell(child, play_sound)
			return


func _select_cell(wrapper: Control, play_sound: bool = true) -> void:
	_selected_cell = wrapper
	_selected_value = str(wrapper.get_meta("value", ""))
	if _outline.get_parent() != null:
		_outline.get_parent().remove_child(_outline)
	wrapper.add_child(_outline)
	_outline.visible = true
	_outline.position = Vector2.ZERO
	_outline.size = wrapper.size
	_refresh_status(-1)
	if play_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _refresh_status(total: int) -> void:
	if _status == null:
		return
	var shown := 0
	for child in _grid.get_children():
		if child is Control and child.visible:
			shown += 1
	var text := "%d shown" % shown
	if total > 0 and total != shown:
		text = "%d of %d shown" % [shown, total]
	if _selected_value != "":
		text += "     selected: " + _selected_value
	_status.text = text
	if _confirm_btn != null:
		_confirm_btn.disabled = _selected_value == ""


func _on_filter_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	for child in _grid.get_children():
		if child is Control:
			child.visible = needle == "" or str(child.get_meta("value", "")).to_lower().contains(needle)
	# The outline rides on its cell, so a hidden cell hides it too -- nothing to
	# reposition. Only the count needs refreshing.
	_refresh_status(_grid.get_child_count())


# ============================================================
# INPUT / EXIT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# The picker sits above the character editor and the placement tool, both of
	# which take keys in _input(). Escape and Enter are consumed here so they cannot
	# also close the form behind, or save the map file.
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		_:
			# Anything else is typing: send it to the filter box so you can start
			# searching without clicking into the field first. Not consumed, so the
			# keystroke that moved focus still registers as a character.
			if not _filter_edit.has_focus():
				_filter_edit.grab_focus()
			return
	get_viewport().set_input_as_handled()


func _confirm() -> void:
	if _selected_value == "" or _closing:
		return
	_closing = true
	picked.emit(_selected_value)
	queue_free()


func _cancel() -> void:
	if _closing:
		return
	_closing = true
	cancelled.emit()
	queue_free()
