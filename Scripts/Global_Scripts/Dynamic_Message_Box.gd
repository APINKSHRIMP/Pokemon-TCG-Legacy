class_name DynamicMessageBox
extends Control

# ============================================================
# DYNAMIC MESSAGE BOX
# ============================================================
# The overworld / outro message box, built entirely in code so it can resize,
# recolour and grow extra info chips at runtime. Replaces the old approach of
# stretching a single baked PNG.
#
# Structure (bottom of a 1920x1080 reference screen):
#
#     [sprite]NAME  [deck]DECK NAME  [cup]2          <- chip row, auto-sized
#   +---------------------------------------------+
#   |  body text, left aligned, vertically centred |  <- main panel
#   +---------------------------------------------+
#            [ YES ]   [ NO ]                         <- buttons, OUTSIDE the panel
#
# The panel and every chip are the same ColorRect + Rounded_Message_Panel
# shader; a chip is just the panel with its edge falloff pushed off the end so
# the whole rect stays solid colour.
#
# ── ADDING A NEW CHIP ────────────────────────────────────────
# Nothing in here is hardcoded to three chips. Call set_chips() with as many
# entries as you like and the row lays itself out, auto-sizing each chip to
# its own icon + text and stepping the colour ramp one notch per chip:
#
#     box.set_chips([
#         { "text": "MISTY",        "icon": some_texture },
#         { "text": "RAIN DANCE",   "icon_path": ICON_DIR + "deck.png" },
#         { "text": "6",            "icon_path": ICON_DIR + "prizes.png" },
#         { "text": "x3",           "icon_path": ICON_DIR + "trophy.png" },
#     ])
#
# Each entry accepts:
#   "text"        String  — label drawn to the right of the icon (may be "")
#   "icon"        Texture2D — pre-loaded icon, wins over icon_path
#   "icon_path"   String  — res:// path, loaded on demand
#   "sprite"      String  — overworld sprite-sheet NAME; the idle-down frame is
#                           cropped to its opaque pixels and used as the icon
# ============================================================

const SHADER_PATH   := "res://Scripts/Shaders/Rounded_Message_Panel.gdshader"
# The Kenney font the kenneyUI themes are built on, so the box matches the
# buttons sitting under it. Noticeably wider than the old Lupinademo face —
# the font sizes below were retuned for it, don't raise them without checking
# the longest opponent + deck name still fit on one chip row.
const MSG_FONT_PATH := "res://UI_Themes/kenvector_future.ttf"
const ICON_DIR      := "res://Image_Assets/Icons/Message_Icons/"
const SPRITE_DIR    := "res://Image_Assets/Character_Sprites/Overworld_Sprites/"

const KENNEY_THEME_GREEN := "res://UI_Themes/kenneyUI-green.tres"
const KENNEY_THEME_RED   := "res://UI_Themes/kenneyUI-red.tres"
const KENNEY_THEME_BLUE  := "res://UI_Themes/kenneyUI-blue.tres"

# Reference screen. Every offset below is an absolute pixel in this space.
const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# ── TWEAKABLE LAYOUT ─────────────────────────────────────────
# Main panel
const PANEL_MARGIN_X   : float = 12.0    # gap to the screen edge, both sides
const PANEL_BOTTOM_Y   : float = 1004.0  # panel's bottom edge, with a button row below it
const PANEL_BOTTOM_NO_BUTTONS : float = 1068.0  # buttonless boxes drop to the screen edge
const PANEL_CORNER_R   : float = 34.0
# Border glow, per axis: x = left/right edges, y = top/bottom. Deliberately
# lopsided — the design has a wide band down the sides and a hairline along
# the top and bottom, so a short wide panel keeps plenty of white in the middle.
const PANEL_EDGE_SOLID : Vector2 = Vector2(26.0, 2.0)   # px of pure colour
const PANEL_EDGE_FADE  : Vector2 = Vector2(12.0, 4.0)   # px it takes to reach white
const PANEL_TEXT_PAD_X : float = 48.0    # panel edge -> text; must clear the glow
const PANEL_TEXT_PAD_Y : float = 10.0
# The panel is deliberately short, so the longest lines in the data (the Gym
# receptionist's 333-character spiel) would spill out of it at full size.
# set_body_text() steps the size down until the wrapped text fits, no lower
# than this.
const BODY_MIN_FONT : int = 17

# Chip row
const CHIP_H            : float = 50.0
const CHIP_ROW_INSET    : float = 10.0   # first chip's left edge, in from the panel's
const CHIP_CORNER_R     : float = 25.0   # CHIP_H / 2 -> pill
const CHIP_ICON_H       : float = 66.0   # taller than the chip, so it breaks out the top
const CHIP_ICON_MAX_W   : float = 62.0
const CHIP_ICON_PAD_L   : float = 6.0
const CHIP_ICON_GAP     : float = 8.0    # icon -> text
const CHIP_TEXT_PAD_R   : float = 22.0
const CHIP_ICON_DROP    : float = 4.0    # icon's bottom sits this far above the chip's
const CHIP_FONT_SIZE    : int   = 27
const CHIP_MIN_FONT     : int   = 16     # shrink floor when a row would overflow
const CHIP_NEIGHBOUR_MIX: float = 0.18   # how far each chip shades toward its neighbours
# Chip labels are black, as designed — but the dark themes would swallow them,
# so anything below this perceived brightness flips its label to white. Set the
# threshold to 0.0 to force black everywhere.
const CHIP_TEXT_LIGHT_THRESHOLD : float = 0.55

# Buttons — deliberately below the panel, never inside it.
const BUTTON_ROW_TOP    : float = 1016.0
const BUTTON_ROW_BOTTOM : float = 1062.0
const BUTTON_SEPARATION : int   = 30
const BUTTON_MIN_W      : float = 144.0

# A chip is the same shader with the falloff pushed past the far edge, so the
# whole pill stays solid colour.
const CHIP_EDGE_SOLID : Vector2 = Vector2(9999.0, 9999.0)
const CHIP_EDGE_FADE  : Vector2 = Vector2(1.0, 1.0)

# ── Public nodes ─────────────────────────────────────────────
var label: RichTextLabel = null
var yes_button: Button = null
var no_button:  Button = null
var ok_button:  Button = null

# ── Internal nodes ───────────────────────────────────────────
var _panel: ColorRect = null
var _text_box: VBoxContainer = null
var _chip_row: Control = null
var _button_row: HBoxContainer = null

var _theme_key: String = MessageBoxTheme.DEFAULT_THEME
var _chips: Array = []
var _panel_height: float = 138.0
var _panel_bottom: float = PANEL_BOTTOM_Y
var _body_font_size: int = 28   # the size body text is shown at when it fits

var _msg_font: Font = null
var _msg_font_bold: FontVariation = null
var _msg_font_italic: FontVariation = null

# sprite name -> cropped idle-down AtlasTexture. Built once per sprite sheet;
# the opaque-bounds scan is cheap but there is no reason to redo it every time
# the player talks to the same person.
static var _sprite_icon_cache: Dictionary = {}


# ============================================================
# CONSTRUCTION
# ============================================================
# box_height      — panel height in reference px.
# font_size       — body text size.
# include_buttons — false for click-to-advance screens (the outro).
# pad_l/t/r       — extra inset on top of the standard text padding, so the
#                   existing call sites keep their hand-tuned spacing.
func configure(box_height: float = 138.0,
			   font_size: int = 28,
			   include_buttons: bool = true,
			   pad_l: float = 0.0,
			   pad_t: float = 0.0,
			   pad_r: float = 0.0) -> void:

	_panel_height = box_height
	_body_font_size = font_size
	# With buttons the panel has to stop short so they land below it; without
	# them (the outro's panels) it can sit right down at the screen edge.
	_panel_bottom = PANEL_BOTTOM_Y if include_buttons else PANEL_BOTTOM_NO_BUTTONS

	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = SCREEN_W
	offset_bottom = SCREEN_H
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	visible       = false

	_msg_font = load(MSG_FONT_PATH)
	_msg_font_bold = FontVariation.new()
	_msg_font_bold.base_font = _msg_font
	_msg_font_bold.variation_embolden = 1.0
	_msg_font_italic = FontVariation.new()
	_msg_font_italic.base_font = _msg_font
	_msg_font_italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.25, 1.0), Vector2(0.0, 0.0))

	var panel_top := _panel_bottom - _panel_height
	var panel_w := SCREEN_W - PANEL_MARGIN_X * 2.0

	# ── Chip row ─────────────────────────────────────────────
	# Added before the panel so nothing here can cover the chips; chips draw
	# over the panel's top edge, hiding any seam where the two meet.
	_chip_row = Control.new()
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip_row)

	# ── Main panel ───────────────────────────────────────────
	_panel = _make_shader_rect()
	_panel.position = Vector2(PANEL_MARGIN_X, panel_top)
	_panel.size     = Vector2(panel_w, _panel_height)
	add_child(_panel)
	move_child(_panel, 0)   # behind the chip row

	# ── Body text ────────────────────────────────────────────
	# A centre-aligned VBox holding a fit_content label is what gives the
	# "one line sits dead centre, two lines straddle the centre" behaviour.
	_text_box = VBoxContainer.new()
	_text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_box.offset_left   = PANEL_MARGIN_X + PANEL_TEXT_PAD_X + pad_l
	_text_box.offset_top    = panel_top + PANEL_TEXT_PAD_Y + pad_t
	_text_box.offset_right  = SCREEN_W - PANEL_MARGIN_X - PANEL_TEXT_PAD_X - pad_r
	_text_box.offset_bottom = _panel_bottom - PANEL_TEXT_PAD_Y
	_text_box.add_theme_constant_override("separation", 6)
	add_child(_text_box)

	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active  = false
	label.fit_content    = true
	label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font",  _msg_font)
	label.add_theme_font_override("bold_font",    _msg_font_bold)
	label.add_theme_font_override("italics_font", _msg_font_italic)
	label.add_theme_font_size_override("normal_font_size",  font_size)
	label.add_theme_font_size_override("bold_font_size",    font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	label.add_theme_color_override("default_color", Color(0, 0, 0, 1))
	_text_box.add_child(label)

	# ── Buttons ──────────────────────────────────────────────
	if include_buttons:
		_button_row = HBoxContainer.new()
		_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_button_row.add_theme_constant_override("separation", BUTTON_SEPARATION)
		_button_row.offset_left   = PANEL_MARGIN_X
		_button_row.offset_top    = BUTTON_ROW_TOP
		_button_row.offset_right  = SCREEN_W - PANEL_MARGIN_X
		_button_row.offset_bottom = BUTTON_ROW_BOTTOM
		add_child(_button_row)

		yes_button = _make_button("  Yes  ", KENNEY_THEME_GREEN)
		no_button  = _make_button("  No  ",  KENNEY_THEME_RED)
		ok_button  = _make_button("  OK  ",  KENNEY_THEME_BLUE)

	apply_theme()


func _make_button(text: String, theme_path: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.theme = load(theme_path)
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(BUTTON_MIN_W, 0)
	btn.visible = false
	_button_row.add_child(btn)
	return btn


# A ColorRect carrying its own ShaderMaterial instance. Every rect needs its
# own material — the uniforms are per-rect (size, colours, falloff).
func _make_shader_rect() -> ColorRect:
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ============================================================
# THEMING
# ============================================================
# Re-read on every show(), so changing the colour in the Options overlay takes
# effect the next time a message appears without rebuilding the box.
func apply_theme(theme_key: String = "") -> void:
	if theme_key == "":
		theme_key = GameState.message_box_colour_setting
	if not MessageBoxTheme.has_theme(theme_key):
		theme_key = MessageBoxTheme.DEFAULT_THEME
	_theme_key = theme_key

	if _panel != null:
		var edge := MessageBoxTheme.panel_edge_color(_theme_key)
		_apply_shader(_panel, edge, edge, Color.WHITE,
					  PANEL_CORNER_R, PANEL_EDGE_SOLID, PANEL_EDGE_FADE)

	_rebuild_chips()


func _apply_shader(rect: ColorRect, col_l: Color, col_r: Color, fill: Color,
				   corner: float, solid: Vector2, fade: Vector2) -> void:
	var mat: ShaderMaterial = rect.material
	if mat == null:
		return
	mat.set_shader_parameter("color_left",    col_l)
	mat.set_shader_parameter("color_right",   col_r)
	mat.set_shader_parameter("fill_color",    fill)
	mat.set_shader_parameter("rect_size",     rect.size)
	mat.set_shader_parameter("corner_radius", corner)
	mat.set_shader_parameter("edge_solid",    solid)
	mat.set_shader_parameter("edge_fade",     fade)


# ============================================================
# CHIPS
# ============================================================

func set_chips(chips: Array) -> void:
	_chips = chips
	_rebuild_chips()


func clear_chips() -> void:
	set_chips([])


func _rebuild_chips() -> void:
	if _chip_row == null:
		return
	# remove_child as well as queue_free — queue_free is deferred, and two
	# rebuilds in one frame would otherwise draw the old chips over the new.
	for child in _chip_row.get_children():
		_chip_row.remove_child(child)
		child.queue_free()
	if _chips.is_empty():
		return

	var chip_bottom := _panel_bottom - _panel_height   # chips sit ON the panel's top edge
	var chip_top    := chip_bottom - CHIP_H

	# ── Pass 1: resolve icons and measure, shrinking the font if the row
	# would run off the right-hand edge of the panel.
	var font_size := CHIP_FONT_SIZE
	var measured: Array = []
	var max_row_w := SCREEN_W - PANEL_MARGIN_X * 2.0 - CHIP_ROW_INSET * 2.0
	while true:
		measured = _measure_chips(font_size)
		var total := 0.0
		for m in measured:
			total += m["width"]
		if total <= max_row_w or font_size <= CHIP_MIN_FONT:
			break
		font_size -= 1

	# ── Pass 2: place them left to right, each touching the last.
	var x := PANEL_MARGIN_X + CHIP_ROW_INSET
	for i in measured.size():
		var m: Dictionary = measured[i]
		var own := MessageBoxTheme.chip_color(_theme_key, i)
		# Shade a touch toward whoever sits either side, so the row reads as
		# one continuous ramp rather than three unrelated blocks.
		var left_neighbour  := MessageBoxTheme.chip_color(_theme_key, maxi(i - 1, 0))
		var right_neighbour := MessageBoxTheme.chip_color(_theme_key, mini(i + 1, measured.size() - 1))
		var col_l := own.lerp(left_neighbour,  CHIP_NEIGHBOUR_MIX)
		var col_r := own.lerp(right_neighbour, CHIP_NEIGHBOUR_MIX)

		var chip := _make_shader_rect()
		chip.position = Vector2(x, chip_top)
		chip.size     = Vector2(m["width"], CHIP_H)
		_chip_row.add_child(chip)
		_apply_shader(chip, col_l, col_r, col_l, CHIP_CORNER_R, CHIP_EDGE_SOLID, CHIP_EDGE_FADE)

		# Icon — breaks out above the chip so it reads against the overworld.
		var icon_tex: Texture2D = m["icon"]
		if icon_tex != null:
			var icon := TextureRect.new()
			icon.texture       = icon_tex
			icon.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode  = TextureRect.STRETCH_SCALE
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			icon.size     = m["icon_size"]
			icon.position = Vector2(
				x + CHIP_ICON_PAD_L,
				chip_bottom - CHIP_ICON_DROP - m["icon_size"].y
			)
			_chip_row.add_child(icon)

		# Text — black, bold, vertically centred in the chip.
		if String(m["text"]) != "":
			var text_label := Label.new()
			text_label.text = String(m["text"])
			text_label.add_theme_font_override("font", _msg_font_bold)
			text_label.add_theme_font_size_override("font_size", font_size)
			text_label.add_theme_color_override("font_color", _chip_text_color(own))
			text_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text_label.position = Vector2(
				x + CHIP_ICON_PAD_L + m["icon_slot_w"] + CHIP_ICON_GAP,
				chip_top
			)
			text_label.size = Vector2(m["text_width"], CHIP_H)
			_chip_row.add_child(text_label)

		x += m["width"]


# Rec. 601 luma — green carries most of the perceived brightness, so a mid
# green chip correctly keeps black text where a mid blue one would not.
func _chip_text_color(chip: Color) -> Color:
	var luma := chip.r * 0.299 + chip.g * 0.587 + chip.b * 0.114
	return Color(0, 0, 0, 1) if luma >= CHIP_TEXT_LIGHT_THRESHOLD else Color(1, 1, 1, 1)


# Works out every chip's pixel width at a given font size, without building
# any nodes — the shrink-to-fit loop above calls this repeatedly.
func _measure_chips(font_size: int) -> Array:
	var out: Array = []
	for entry in _chips:
		var icon_tex := _resolve_icon(entry)

		var icon_size := Vector2.ZERO
		var icon_slot_w := 0.0
		if icon_tex != null:
			var tex_size := icon_tex.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				var s: float = minf(CHIP_ICON_H / tex_size.y, CHIP_ICON_MAX_W / tex_size.x)
				icon_size = Vector2(tex_size.x * s, tex_size.y * s)
				icon_slot_w = icon_size.x

		var text := String(entry.get("text", ""))
		var text_width := 0.0
		if text != "":
			text_width = _msg_font_bold.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

		var width := CHIP_ICON_PAD_L + icon_slot_w + CHIP_TEXT_PAD_R
		if text != "":
			width += CHIP_ICON_GAP + text_width

		out.append({
			"text": text,
			"icon": icon_tex,
			"icon_size": icon_size,
			"icon_slot_w": icon_slot_w,
			"text_width": text_width,
			"width": width,
		})
	return out


func _resolve_icon(entry: Dictionary) -> Texture2D:
	if entry.has("icon") and entry["icon"] is Texture2D:
		return entry["icon"]
	var sprite_name := String(entry.get("sprite", ""))
	if sprite_name != "":
		return sprite_icon(sprite_name)
	var path := String(entry.get("icon_path", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null


# ============================================================
# OVERWORLD SPRITE -> CHIP ICON
# ============================================================
# Takes the idle-down frame (grid cell 0,0 of the 4x4 sheet — see
# SpriteSheetLoader.FRAME_MAP) and trims it to its opaque pixels, so a chip
# icon is the character and not the transparent padding around them. Without
# the trim every icon would render small and off-centre inside its 64x64 cell.
static func sprite_icon(sprite_name: String) -> Texture2D:
	if _sprite_icon_cache.has(sprite_name):
		return _sprite_icon_cache[sprite_name]

	var path := SPRITE_DIR + sprite_name + ".png"
	if not ResourceLoader.exists(path):
		_sprite_icon_cache[sprite_name] = null
		return null

	var sheet: Texture2D = load(path)
	if sheet == null:
		_sprite_icon_cache[sprite_name] = null
		return null

	var frame_w := sheet.get_width() / 4.0
	var frame_h := sheet.get_height() / 4.0
	var region := Rect2(0, 0, frame_w, frame_h)

	# Trim to the opaque bounds of that frame. get_image() can fail on some
	# import settings, in which case the untrimmed frame is a fine fallback.
	var img := sheet.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var min_x := int(frame_w)
		var max_x := -1
		var min_y := int(frame_h)
		var max_y := -1
		for y in int(frame_h):
			for x in int(frame_w):
				if img.get_pixel(x, y).a > 0.03:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
		if max_x >= min_x and max_y >= min_y:
			region = Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

	var atlas := AtlasTexture.new()
	atlas.atlas  = sheet
	atlas.region = region
	_sprite_icon_cache[sprite_name] = atlas
	return atlas


# ============================================================
# BODY TEXT
# ============================================================
# Always set body text through here rather than touching label.text — this is
# what keeps a long line inside the panel instead of spilling above and below
# it. max_font_size is a ceiling, not a fixed size: short text gets it in full,
# long text is stepped down until it fits.
func set_body_text(text: String, max_font_size: int = -1) -> void:
	label.text = text
	var ceiling: int = max_font_size if max_font_size > 0 else _body_font_size
	var size := _fitted_body_size(text, ceiling)
	label.add_theme_font_size_override("normal_font_size",  size)
	label.add_theme_font_size_override("bold_font_size",    size)
	label.add_theme_font_size_override("italics_font_size", size)


func _fitted_body_size(text: String, ceiling: int) -> int:
	if _text_box == null or _msg_font == null:
		return ceiling
	# BBCode tags are markup, not glyphs — measuring them would over-estimate
	# the width and shrink text that would actually have fitted.
	var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(text, "", true)
	var wrap_w  := _text_box.offset_right  - _text_box.offset_left
	var avail_h := _text_box.offset_bottom - _text_box.offset_top
	var size := ceiling
	while size > BODY_MIN_FONT:
		var h := _msg_font.get_multiline_string_size(
			plain, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, size).y
		if h <= avail_h:
			break
		size -= 1
	return size


# ============================================================
# SHOWING
# ============================================================

func show_choices(text: String) -> void:
	apply_theme()
	set_body_text(text)
	if yes_button != null: yes_button.visible = true
	if no_button  != null: no_button.visible  = true
	if ok_button  != null: ok_button.visible  = false
	visible = true


func show_ok(text: String) -> void:
	apply_theme()
	set_body_text(text)
	if yes_button != null: yes_button.visible = false
	if no_button  != null: no_button.visible  = false
	if ok_button  != null: ok_button.visible  = true
	visible = true
