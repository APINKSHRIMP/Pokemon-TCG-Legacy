class_name DynamicMessageBox
extends Control

# ============================================================
# DYNAMIC MESSAGE BOX
# ============================================================
# Every message box in the game - overworld dialogue, in-match messages, the
# outro's closing line and gift notices. Built entirely in code so it can
# resize, recolour and grow extra info chips at runtime.
#
# -- TWO VARIANTS, ONE COMPONENT ------------------------------
# set_system_variant() is the speaker flag. Everything else - insets, fill,
# radius, shadow, padding, the caret, the buttons - is shared.
#
#   CHARACTER (the default) - someone is speaking.
#       An 8px spine down the LEFT EDGE ONLY in the speaker's colour, a name
#       pill straddling the top edge with their portrait in it, the deck and
#       prize chips to its right, and a very faint outer glow in the same
#       colour. A full coloured border round a dark box reads as a warning
#       dialog, which is why the colour lives on one edge.
#
#   SYSTEM - the game is speaking. Every in-match message uses this.
#       No pill, no portrait, no chips, no spine. The theme gradient runs round
#       all four edges with a thicker hairline along the top, and the text is
#       centred and larger.
#
# Structure (bottom of a 1920x1080 reference screen):
#
#     [portrait NAME] [deck]DECK  [cup]6            [$ 1200]    <- pill row
#   +----------------------------------------------------------+
#   |  body text                                               |  <- 8px spine
#   |                    [ YES ]   [ NO ]                    v |
#   +----------------------------------------------------------+
#
# -- ADDING A NEW CHIP ----------------------------------------
# Nothing here is hardcoded to a chip count. Call set_chips() with as many
# entries as you like and the row lays itself out, auto-sizing each chip to its
# own icon + text and stepping the colour ramp one notch per chip:
#
#     box.set_chips([
#         { "text": "RAIN DANCE", "icon_path": ICON_DIR + "deck.png" },
#         { "text": "6",          "icon_path": ICON_DIR + "prizes.png" },
#     ])
#
# Each entry accepts:
#   "text"        String  - label drawn to the right of the icon (may be "")
#   "icon"        Texture2D - pre-loaded icon, wins over icon_path
#   "icon_path"   String  - res:// path, loaded on demand
#   "sprite"      String  - overworld sprite-sheet NAME; the idle-down frame is
#                           cropped to its opaque pixels and used as the icon
#
# THE NAME IS NOT A CHIP any more. set_name_pill() owns it - it carries the
# portrait and the speaker's own colour, and the chips step the ramp from index
# 1 so their colouring is exactly what it always was.
# ============================================================

const PANEL_SHADER  := "res://Scripts/Shaders/UI_Dialogue_Panel.gdshader"
const CHIP_SHADER   := "res://Scripts/Shaders/Rounded_Message_Panel.gdshader"
const ICON_DIR      := "res://Image_Assets/Icons/Message_Icons/"
const SPRITE_DIR    := "res://Image_Assets/Character_Sprites/Overworld_Sprites/"

# Reference screen. Every offset below is an absolute pixel in this space.
const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# -- TWEAKABLE LAYOUT -----------------------------------------
# The box
const PANEL_MARGIN_X   : float = 46.0    # gap to the screen edge, both sides
const PANEL_BOTTOM_INSET : float = 46.0  # gap from the box's bottom to the screen's
const PANEL_BOTTOM_Y   : float = SCREEN_H - PANEL_BOTTOM_INSET
# Kept for the callers that still read them (Match_Log_Panel lines itself up with
# the box). Both positions are the same now - the buttons moved INSIDE the box, so
# there is nothing below it to make room for.
const PANEL_BOTTOM_NO_BUTTONS : float = PANEL_BOTTOM_Y
const PANEL_CORNER_R   : float = 18.0
const PANEL_SPINE_W    : float = 8.0     # left edge only, in the speaker's colour
# Border weight, per variant. The system variant's gradient is the SAME weight on
# all four edges - a heavier top with hairline sides read as a mistake rather than
# as emphasis.
const PANEL_BORDER_W   : float = 1.0     # character variant, white at 15%
const PANEL_SYS_BORDER : float = 5.0     # system variant, the theme gradient
# The shader draws the shadow and glow OUTSIDE the panel, so its ColorRect is
# inflated by this on all four sides. Must clear shadow_dy + shadow_blur/2.
const PANEL_SHADOW_PAD : float = 60.0
const PANEL_SHADOW_DY  : float = 11.0
const PANEL_SHADOW_BLUR: float = 36.0
# Outer glow in the speaker's colour. GLOW_SPREAD shrinks the glow shape before
# blurring, which is what keeps it from reading as a halo. Raise GLOW_ALPHA if it
# is invisible on your screen; if you can see a distinct ring, it is too strong.
const PANEL_GLOW_BLUR  : float = 42.0
const PANEL_GLOW_SPREAD: float = 13.0
const PANEL_GLOW_ALPHA : float = 0.55

# Text padding, per variant
const PAD_TOP          : float = 29.0
const PAD_X            : float = 35.0
const PAD_BOTTOM       : float = 27.0
const SYS_PAD_Y        : float = 40.0
const SYS_PAD_X        : float = 42.0

# Body text
const BODY_FONT_SIZE   : int   = 22      # character variant
const SYS_FONT_SIZE    : int   = 31      # system variant
const BODY_LINE_HEIGHT : float = 1.50    # character variant
const SYS_LINE_HEIGHT  : float = 1.42    # system variant
# The longest lines in the data (the Gym receptionist's 333-character spiel) would
# make an unreasonably tall box, so the panel grows only this far and then the font
# steps down instead.
const BODY_MIN_FONT    : int   = 17
const PANEL_MAX_H      : float = 430.0

# Buttons - horizontally centred, STRADDLING the box's bottom edge exactly as the
# name pill straddles its top. That symmetry is the point: the buttons take no
# height inside the box, so a Yes/No box and a plain one have the same text area,
# the same font size and the same amount of screen under them.
const BUTTON_SEPARATION: int   = 19
const BUTTON_MIN_W     : float = 150.0
const BUTTON_H         : float = 48.0

# The pill row - straddles the box's top edge. NAME, DECK and PRIZE COUNT are all
# the SAME pill: a dark circular well holding an icon, then a label. One height,
# one font, one colour, one padding; only the fill steps along the speaker's ramp.
const PILL_RISE        : float = 28.0    # pill's top, above the box's top edge
const PILL_INSET_L     : float = 23.0    # first pill's left, in from the box's left
const PILL_INSET_R     : float = 23.0    # cash pill's right, in from the box's right
const PILL_GAP         : float = 8.0     # between pills
const PILL_PAD         : float = 5.0
const PILL_PAD_R       : float = 19.0
const PORTRAIT_D       : float = 38.0    # the round well every icon sits in
const PORTRAIT_WELL_BG : Color = Color(0.0, 0.0, 0.0, 0.42)
# Fraction of the well an icon is fitted into, as a SQUARE, so a tall card icon
# and a square trophy both stay clear of the circle's edge.
const ICON_FIT         : float = 0.80
const PILL_FONT_SIZE   : int   = 22
const PILL_MIN_FONT    : int   = 16      # shrink floor when a row would overflow
const PILL_TRACK_EM    : float = 0.11

# Cash pill - top right, same row as the name pill
const CASH_FONT_SIZE   : int   = 17
const CASH_PAD_H       : float = 20.0

# How far each pill shades toward its neighbours, so the row reads as one
# continuous ramp rather than three unrelated blocks.
const CHIP_NEIGHBOUR_MIX: float = 0.18

# A chip is the chip shader with the falloff pushed past the far edge, so the
# whole pill stays solid colour.
const CHIP_EDGE_SOLID : Vector2 = Vector2(9999.0, 9999.0)
const CHIP_EDGE_FADE  : Vector2 = Vector2(1.0, 1.0)

# Advance caret - bottom right, "press to continue"
const CARET_W          : float = 18.0
const CARET_H          : float = 12.0
const CARET_INSET      : float = 22.0    # from the box's right and bottom edges
const CARET_BOB_PX     : float = 5.0
const CARET_BOB_TIME   : float = 0.55    # one full up-and-down

# -- Public nodes ---------------------------------------------
var label: RichTextLabel = null
var yes_button: Button = null
var no_button:  Button = null
var ok_button:  Button = null

# -- Internal nodes -------------------------------------------
var _panel: ColorRect = null
var _text_box: Control = null
var _chip_row: Control = null
var _button_row: HBoxContainer = null
var _caret: Control = null
var _caret_tween: Tween = null

var _theme_key: String = MessageBoxTheme.DEFAULT_THEME
var _chips: Array = []
# Chips pinned to the RIGHT end of the same row - the vendor cash readout. Same
# entry format; it is drawn as the gold pill rather than from the colour ramp.
var _right_chips: Array = []
var _name_text: String = ""
var _name_sprite: String = ""
var _system_variant: bool = false

var _panel_min_height: float = 138.0   # the height configure() asked for
var _panel_height: float = 138.0       # what it actually came out as, after fitting
var _panel_bottom: float = PANEL_BOTTOM_Y
# -1 means "the variant decides" (22 for character, 31 for system). A caller that
# passes a real size to configure() keeps it in BOTH variants - the outro's gift
# notice is the system variant at 45pt, which is not the system default.
var _body_font_size: int = -1

# Extra text padding handed in by configure(), kept so the panel can be re-laid out.
var _pad_l: float = 0.0
var _pad_t: float = 0.0
var _pad_r: float = 0.0

# Last body text + ceiling, so a re-layout can re-fit it without the caller re-sending it.
var _body_text: String = ""
var _body_ceiling: int = -1

# Which kind of box this currently is - "ok" (dismiss only), "choices" (Yes/No)
# or "none". THERE IS NO OK BUTTON: a plain message is dismissed by clicking
# anywhere or by Space/Enter/Escape, so callers ask is_ok_mode() rather than
# testing a button's visibility.
var _mode: String = "none"
# For OK boxes that must ignore a dismiss for a while (the gift reveal animates first).
var ok_armed: bool = true

# sprite name -> cropped idle-down AtlasTexture. Built once per sprite sheet;
# the opaque-bounds scan is cheap but there is no reason to redo it every time
# the player talks to the same person.
static var _sprite_icon_cache: Dictionary = {}


# ============================================================
# THE ADVANCE CARET
# ============================================================
# Drawn rather than typed: neither Chakra Petch nor IBM Plex Mono carries U+25BC,
# the same class of missing glyph as the seven the card text needs a system
# fallback for. A triangle is three points; a font fallback is a dependency.
class AdvanceCaret extends Control:
	var colour: Color = Color.WHITE:
		set(value):
			colour = value
			queue_redraw()

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x * 0.5, size.y),
		]), colour)


# ============================================================
# THE PORTRAIT WELL
# ============================================================
# A filled circle behind the speaker's overworld sprite. A plain dark disc rather
# than a cut-out: the sprites are already trimmed to their opaque pixels and vary
# wildly in shape, so a mask would clip some of them and float others.
class PortraitWell extends Control:
	var fill: Color = Color(0.0, 0.0, 0.0, 0.42)

	func _draw() -> void:
		var r: float = min(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, fill)


# ============================================================
# CONSTRUCTION
# ============================================================
# box_height      - the panel's MINIMUM height in reference px. The box grows past
#                   it to fit the text, up to PANEL_MAX_H.
# font_size       - body text ceiling. -1 takes the variant's default.
# include_buttons - false for click-to-advance screens (the outro, the match).
# pad_l/t/r       - extra inset on top of the standard text padding, so the
#                   existing call sites keep their hand-tuned spacing.
func configure(box_height: float = 138.0,
			   font_size: int = -1,
			   include_buttons: bool = true,
			   pad_l: float = 0.0,
			   pad_t: float = 0.0,
			   pad_r: float = 0.0) -> void:

	_panel_min_height = box_height
	_panel_height = box_height
	_body_font_size = font_size
	_pad_l = pad_l
	_pad_t = pad_t
	_pad_r = pad_r
	_panel_bottom = PANEL_BOTTOM_Y

	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = SCREEN_W
	offset_bottom = SCREEN_H
	mouse_filter  = Control.MOUSE_FILTER_IGNORE
	visible       = false

	# -- Main panel -------------------------------------------
	# First child, so nothing added later can end up behind it.
	_panel = ColorRect.new()
	_panel.color = Color.WHITE          # the shader replaces this entirely
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(PANEL_SHADER)
	_panel.material = mat
	add_child(_panel)

	# -- Body text --------------------------------------------
	# A plain Control marking out the usable text area. The label inside it is given
	# an explicit rect by _place_body_label() on every set_body_text() - see the note
	# there for why this is not a fit_content label in a centred VBox.
	_text_box = Control.new()
	_text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_box)

	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active  = false
	label.fit_content    = false
	label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_text_box.add_child(label)

	# -- Advance caret ----------------------------------------
	_caret = AdvanceCaret.new()
	_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caret.size = Vector2(CARET_W, CARET_H)
	_caret.visible = false
	add_child(_caret)

	# -- Buttons, inside the panel ----------------------------
	if include_buttons:
		_button_row = HBoxContainer.new()
		_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_button_row.add_theme_constant_override("separation", BUTTON_SEPARATION)
		add_child(_button_row)

		yes_button = _make_button("Yes", "primary")
		no_button  = _make_button("No",  "secondary")
		# The OK button is gone as a control but kept as a node, so the handful of
		# callers that still connect to it do not have to guard. Never made visible.
		ok_button  = _make_button("OK",  "secondary")

	# -- Pill / chip row --------------------------------------
	# Added LAST so it draws over the panel's top edge, hiding the seam where the
	# name pill straddles it.
	_chip_row = Control.new()
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip_row)

	apply_theme()
	_layout_panel()


## The speaker flag. False (the default) is the character variant - spine, name
## pill, left-aligned. True is the system variant - gradient border all round,
## no pill, centred and larger. See the header.
func set_system_variant(is_system: bool) -> void:
	if _system_variant == is_system:
		return
	_system_variant = is_system
	if is_system:
		_chips = []
		_right_chips = []
		_name_text = ""
		_name_sprite = ""
	apply_theme(_theme_key)
	if _body_text != "":
		set_body_text(_body_text, _body_ceiling)
	else:
		_layout_panel()


func is_system_variant() -> bool:
	return _system_variant


# ============================================================
# LAYOUT
# ============================================================

func _pad_top() -> float:
	return (SYS_PAD_Y if _system_variant else PAD_TOP) + _pad_t


func _pad_bottom() -> float:
	return SYS_PAD_Y if _system_variant else PAD_BOTTOM


func _pad_side() -> float:
	return SYS_PAD_X if _system_variant else PAD_X


# The vertical space the Yes/No row takes INSIDE the box. Always zero: the buttons
# straddle the bottom edge, half in and half out, so a Yes/No box has exactly the
# same text area as a plain one and neither has to shrink its type to fit.
#
# Kept as a function rather than deleted because the text area, the panel height
# and the fitting loop all read it, and a box that DOES want to reserve room would
# only have to change this one line.
func _button_block_h() -> float:
	return 0.0


# Positions the panel, the text area, the buttons and the caret from the CURRENT
# _panel_bottom / _panel_height. Run whenever any of those change.
func _layout_panel() -> void:
	if _panel == null:
		return

	var panel_top := _panel_bottom - _panel_height
	var panel_w := SCREEN_W - PANEL_MARGIN_X * 2.0

	# The rect is inflated so the shader can draw the shadow and glow outside the box.
	_panel.position = Vector2(PANEL_MARGIN_X - PANEL_SHADOW_PAD, panel_top - PANEL_SHADOW_PAD)
	_panel.size     = Vector2(panel_w + PANEL_SHADOW_PAD * 2.0,
							  _panel_height + PANEL_SHADOW_PAD * 2.0)
	_apply_panel_shader()

	if _text_box != null:
		var side := _pad_side()
		_text_box.offset_left   = PANEL_MARGIN_X + side + _pad_l
		_text_box.offset_top    = panel_top + _pad_top()
		_text_box.offset_right  = SCREEN_W - PANEL_MARGIN_X - side - _pad_r
		_text_box.offset_bottom = _panel_bottom - _pad_bottom() - _button_block_h()

	if _button_row != null:
		_button_row.offset_left   = PANEL_MARGIN_X
		_button_row.offset_right  = SCREEN_W - PANEL_MARGIN_X
		# Centred ON the bottom edge, mirroring the name pill on the top edge.
		_button_row.offset_top    = _panel_bottom - BUTTON_H * 0.5
		_button_row.offset_bottom = _button_row.offset_top + BUTTON_H

	if _caret != null:
		_caret.position = Vector2(
			SCREEN_W - PANEL_MARGIN_X - CARET_INSET - CARET_W,
			_panel_bottom - CARET_INSET - CARET_H)
		_caret.set("colour", _caret_colour())

	_rebuild_chips()


func _apply_panel_shader() -> void:
	var mat: ShaderMaterial = _panel.material as ShaderMaterial
	if mat == null:
		return
	var ui := _ui()
	var speaker := MessageBoxTheme.chip_color(_theme_key, 0)

	mat.set_shader_parameter("rect_size", _panel.size)
	mat.set_shader_parameter("pad", PANEL_SHADOW_PAD)
	mat.set_shader_parameter("corner_radius", PANEL_CORNER_R)
	mat.set_shader_parameter("fill", ui.msgbox_col("bg"))
	mat.set_shader_parameter("border_col", ui.msgbox_col("border"))
	mat.set_shader_parameter("grad_a", ui.col("chrome_grad_a"))
	mat.set_shader_parameter("grad_b", ui.col("chrome_grad_b"))
	mat.set_shader_parameter("grad_c", ui.col("chrome_grad_c"))
	mat.set_shader_parameter("grad_b_pos", 0.52)
	mat.set_shader_parameter("shadow_col", ui.msgbox_col("shadow"))
	mat.set_shader_parameter("shadow_dy", PANEL_SHADOW_DY)
	mat.set_shader_parameter("shadow_blur", PANEL_SHADOW_BLUR)
	mat.set_shader_parameter("glow_blur", PANEL_GLOW_BLUR)
	mat.set_shader_parameter("glow_spread", PANEL_GLOW_SPREAD)

	if _system_variant:
		# The gradient IS the identity here, at ONE weight on all four edges.
		mat.set_shader_parameter("border_grad", 1.0)
		mat.set_shader_parameter("border_w", PANEL_SYS_BORDER)
		mat.set_shader_parameter("top_strip_w", 0.0)
		mat.set_shader_parameter("spine_w", 0.0)
		mat.set_shader_parameter("glow_col", Color(0.0, 0.0, 0.0, 0.0))
	else:
		# The speaker's colour appears in exactly three places and nowhere else:
		# the spine, the name pill's fill, and this glow.
		mat.set_shader_parameter("border_grad", 0.0)
		mat.set_shader_parameter("border_w", PANEL_BORDER_W)
		mat.set_shader_parameter("top_strip_w", 0.0)
		mat.set_shader_parameter("spine_w", PANEL_SPINE_W)
		mat.set_shader_parameter("spine_col", speaker)
		var glow := speaker
		glow.a = PANEL_GLOW_ALPHA
		mat.set_shader_parameter("glow_col", glow)


# Moves the whole box up or down and re-flows everything that depends on where it sits.
func set_panel_bottom(new_bottom: float) -> void:
	if is_equal_approx(_panel_bottom, new_bottom):
		return
	_panel_bottom = new_bottom
	if _body_text != "":
		set_body_text(_body_text, _body_ceiling)
	else:
		_layout_panel()


# ============================================================
# MODE
# ============================================================
# "choices" - Yes/No buttons inside the box, which therefore grows to hold them,
#             and NO caret: the caret means "press to continue" and would
#             contradict a question.
# "ok"      - no button at all. Dismissed by a click anywhere or by
#             Space / Enter / Escape, and the caret says so.
func set_mode(mode: String) -> void:
	_mode = mode
	ok_armed = true
	var wants_buttons := mode == "choices"
	if yes_button != null: yes_button.visible = wants_buttons
	if no_button  != null: no_button.visible  = wants_buttons
	if ok_button  != null: ok_button.visible  = false
	_set_caret_visible(not wants_buttons)


func is_ok_mode() -> bool:
	return _mode == "ok"


func is_choice_mode() -> bool:
	return _mode == "choices"


func _set_caret_visible(shown: bool) -> void:
	if _caret == null:
		return
	_caret.visible = shown
	if _caret_tween != null and _caret_tween.is_valid():
		_caret_tween.kill()
		_caret_tween = null
	if not shown:
		return
	# A Tween needs the node in the tree. The box is often configured before it is
	# added to a scene, so the bob is armed again by _enter_tree() below.
	if not is_inside_tree():
		return
	# The one loop in this component, and it is an affordance rather than
	# decoration - reduce motion leaves the caret in place and stops it moving.
	if _ui().motion_reduced():
		return
	var rest := _caret.position.y
	_caret_tween = create_tween()
	_caret_tween.set_loops()
	_caret_tween.set_trans(Tween.TRANS_SINE)
	_caret_tween.tween_property(_caret, "position:y", rest + CARET_BOB_PX, CARET_BOB_TIME * 0.5)
	_caret_tween.tween_property(_caret, "position:y", rest, CARET_BOB_TIME * 0.5)


func _make_button(text: String, variant: String) -> Button:
	var btn := Button.new()
	# style_button applies the button role's CASING and clears custom_minimum_size,
	# so the text goes on BEFORE and the width AFTER.
	btn.text = text
	UIKit.style_button(btn, variant)
	btn.custom_minimum_size = Vector2(BUTTON_MIN_W, BUTTON_H)
	btn.visible = false
	_button_row.add_child(btn)
	return btn


# A ColorRect carrying its own chip-shader instance. Every rect needs its own
# material - the uniforms are per-rect (size, colours, falloff).
func _make_chip_rect() -> ColorRect:
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(CHIP_SHADER)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _apply_chip_shader(rect: ColorRect, col_l: Color, col_r: Color, fill: Color,
						corner: float, vertical: bool = false) -> void:
	var mat: ShaderMaterial = rect.material
	if mat == null:
		return
	mat.set_shader_parameter("color_left",    col_l)
	mat.set_shader_parameter("color_right",   col_r)
	mat.set_shader_parameter("fill_color",    fill)
	mat.set_shader_parameter("rect_size",     rect.size)
	mat.set_shader_parameter("corner_radius", corner)
	mat.set_shader_parameter("edge_solid",    CHIP_EDGE_SOLID)
	mat.set_shader_parameter("edge_fade",     CHIP_EDGE_FADE)
	mat.set_shader_parameter("grad_vertical", 1.0 if vertical else 0.0)


# ============================================================
# THEMING
# ============================================================
# Called on every show() with the CURRENT speaker's colour, so one box can be
# recoloured for each actor in turn without being rebuilt. Pass the actor's
# message_colour; "" (nobody is speaking - an interactable) falls back to the
# default theme rather than leaving the last speaker's colour on screen.
func apply_theme(theme_key: String = "") -> void:
	if not MessageBoxTheme.has_theme(theme_key):
		# "" is the legitimate no-speaker case. Anything else is a typo in the
		# data - same visual fallback, but say so rather than swallowing it.
		if theme_key != "":
			push_warning("DynamicMessageBox: unknown message_colour '%s'" % theme_key)
		theme_key = MessageBoxTheme.DEFAULT_THEME
	_theme_key = theme_key

	if _panel != null:
		_apply_panel_shader()
	if _caret != null:
		_caret.set("colour", _caret_colour())
	_rebuild_chips()


# The no-speaker look. Used by any box that is the GAME talking rather than a
# person: the "You received X" gift notice, signs, the TV, the bed.
#
# That is the SYSTEM variant - the same box every in-match message uses. It used to
# be a grey character box, which said "somebody colourless is speaking" rather than
# "nobody is".
func show_as_plain() -> void:
	_chips = []
	_right_chips = []
	_name_text = ""
	_name_sprite = ""
	set_system_variant(true)
	apply_theme()


# ============================================================
# NAME PILL AND CHIPS
# ============================================================

## The speaker's name and portrait. `sprite` is an overworld sprite-sheet name;
## its idle-down frame is cropped to its opaque pixels and dropped in the well.
## Pass "" for both to remove the pill.
func set_name_pill(display_name: String, sprite: String = "") -> void:
	_name_text = display_name
	_name_sprite = sprite
	_rebuild_chips()


func set_chips(chips: Array) -> void:
	_chips = chips
	_rebuild_chips()


## The right-hand end of the same row. Same entry format as set_chips(); the last
## entry ends flush with the box's right inset. Currently one chip - the vendor's
## cash readout - which is drawn as the gold pill rather than from the colour ramp.
func set_right_chips(chips: Array) -> void:
	_right_chips = chips
	_rebuild_chips()


func clear_chips() -> void:
	_right_chips = []
	_name_text = ""
	_name_sprite = ""
	set_chips([])


func _rebuild_chips() -> void:
	if _chip_row == null:
		return
	# remove_child as well as queue_free - queue_free is deferred, and two rebuilds
	# in one frame would otherwise draw the old pills over the new.
	for child in _chip_row.get_children():
		_chip_row.remove_child(child)
		child.queue_free()
	# The system variant has no pill row at all.
	if _system_variant:
		return
	if _name_text == "" and _chips.is_empty() and _right_chips.is_empty():
		return

	var panel_top := _panel_bottom - _panel_height
	var pill_top := panel_top - PILL_RISE
	var pill_h := PORTRAIT_D + PILL_PAD * 2.0

	# Everything on this row is the SAME PILL: a dark circular well holding an
	# icon, then a label. The name pill's icon is the speaker's overworld portrait,
	# the deck pill's is a card and the prize pill's is a trophy - but the shape,
	# the well, the type and the padding are identical, so the row reads as one
	# object rather than three unrelated widgets at three sizes.
	var entries: Array = []
	if _name_text != "":
		entries.append({ "text": _name_text.to_upper(), "sprite": _name_sprite })
	for c in _chips:
		entries.append(c)

	var cash_w := _measure_cash_pill()
	var right_limit := SCREEN_W - PANEL_MARGIN_X - PILL_INSET_R - cash_w
	if cash_w > 0.0:
		right_limit -= PILL_GAP

	# Shrink the shared font if the row would run into the cash pill. One size for
	# the whole row - a name that has to shrink takes its chips with it.
	var font_size := PILL_FONT_SIZE
	var measured: Array = []
	var x := PANEL_MARGIN_X + PILL_INSET_L
	while true:
		measured = _measure_pills(entries, font_size)
		var total := 0.0
		for m in measured:
			total += float(m["width"]) + PILL_GAP
		if x + total - PILL_GAP <= right_limit or font_size <= PILL_MIN_FONT:
			break
		font_size -= 1

	for i in measured.size():
		_build_pill(measured[i], i, measured.size(), x, pill_top, pill_h, font_size)
		x += float(measured[i]["width"]) + PILL_GAP

	# -- The cash pill, flush with the box's right inset --
	if cash_w > 0.0:
		_build_cash_pill(SCREEN_W - PANEL_MARGIN_X - PILL_INSET_R - cash_w, pill_top, pill_h)


# One pill: the coloured capsule, the dark well, the icon inside it and the label.
# `ramp_i` is its position along the speaker's colour ramp - 0 is the name, which
# is the speaker's own colour, and every chip after it steps one notch, exactly as
# the chips have always been coloured.
func _build_pill(m: Dictionary, ramp_i: int, ramp_len: int, x: float,
				 top: float, h: float, font_size: int) -> void:
	var own := MessageBoxTheme.chip_color(_theme_key, ramp_i)
	# Shade a touch toward whoever sits either side, so the row reads as one
	# continuous ramp rather than unrelated blocks.
	var left_neighbour  := MessageBoxTheme.chip_color(_theme_key, maxi(ramp_i - 1, 0))
	var right_neighbour := MessageBoxTheme.chip_color(_theme_key, mini(ramp_i + 1, ramp_len - 1))
	var col_l := own.lerp(left_neighbour,  CHIP_NEIGHBOUR_MIX)
	var col_r := own.lerp(right_neighbour, CHIP_NEIGHBOUR_MIX)

	var pill := _make_chip_rect()
	pill.position = Vector2(x, top)
	pill.size     = Vector2(m["width"], h)
	_chip_row.add_child(pill)
	_apply_chip_shader(pill, col_l, col_r, col_l, h * 0.5)

	# The well. A plain dark disc rather than a mask: the icons are trimmed to
	# their opaque pixels and vary wildly in shape, so a mask would clip some of
	# them and leave others floating.
	var well := PortraitWell.new()
	well.fill = PORTRAIT_WELL_BG
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.position = Vector2(x + PILL_PAD, top + PILL_PAD)
	well.size = Vector2(PORTRAIT_D, PORTRAIT_D)
	_chip_row.add_child(well)

	var tex: Texture2D = m["icon"]
	if tex != null:
		var tex_size := tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			# Fitted to a square inside the circle, so a tall card icon and a
			# square trophy both sit clear of the well's edge.
			var fit: float = PORTRAIT_D * ICON_FIT
			var s: float = minf(fit / tex_size.x, fit / tex_size.y)
			var icon := TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.size = Vector2(tex_size.x * s, tex_size.y * s)
			icon.position = well.position + (Vector2(PORTRAIT_D, PORTRAIT_D) - icon.size) * 0.5
			_chip_row.add_child(icon)

	if String(m["text"]) != "":
		var lbl := Label.new()
		lbl.text = String(m["text"])
		lbl.add_theme_font_override("font", _ui().font("name"))
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_constant_override("font_spacing_glyph",
				int(round(PILL_TRACK_EM * float(font_size))))
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.position = Vector2(x + PILL_PAD + PORTRAIT_D + PILL_PAD, top)
		lbl.size = Vector2(m["text_width"], h)
		_chip_row.add_child(lbl)


# Every pill's width at a given font size, without building any nodes - the
# shrink-to-fit loop above calls this repeatedly.
func _measure_pills(entries: Array, font_size: int) -> Array:
	var font: Font = _ui().font("name")
	var track: int = int(round(PILL_TRACK_EM * float(font_size)))
	var out: Array = []
	for entry in entries:
		var text := String(entry.get("text", ""))
		var text_width := 0.0
		if text != "":
			text_width = font.get_string_size(
					text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
					+ float(track * text.length())

		var width := PILL_PAD + PORTRAIT_D + PILL_PAD
		if text != "":
			width += text_width + PILL_PAD_R

		out.append({
			"text": text,
			"icon": _resolve_icon(entry),
			"text_width": text_width,
			"width": width,
		})
	return out


# The cash pill's text, or "" when there is no cash to show.
func _cash_text() -> String:
	if _right_chips.is_empty():
		return ""
	return String(_right_chips[0].get("text", ""))


# Measured separately from the build so the pill row knows where it has to stop.
func _measure_cash_pill() -> float:
	var text := _cash_text()
	if text == "":
		return 0.0
	var font: Font = _ui().font("name")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CASH_FONT_SIZE).x \
			+ CASH_PAD_H * 2.0


# The shop's money readout. Gold rather than a ramp colour on purpose - money is
# neither the speaker nor the UI, and it is the one figure on the box the player
# is looking for rather than reading.
func _build_cash_pill(x: float, top: float, h: float) -> void:
	var text := _cash_text()
	if text == "":
		return
	var ui := _ui()
	var w := _measure_cash_pill()

	var pill := _make_chip_rect()
	pill.position = Vector2(x, top)
	pill.size     = Vector2(w, h)
	_chip_row.add_child(pill)
	_apply_chip_shader(pill, ui.cash_pill_col("top"), ui.cash_pill_col("bot"),
			ui.cash_pill_col("top"), h * 0.5, true)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", ui.font("name"))
	lbl.add_theme_font_size_override("font_size", CASH_FONT_SIZE)
	lbl.add_theme_color_override("font_color", ui.cash_pill_col("fg"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(x, top)
	lbl.size = Vector2(w, h)
	_chip_row.add_child(lbl)


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
# OVERWORLD SPRITE -> PORTRAIT / CHIP ICON
# ============================================================
# Takes the idle-down frame (grid cell 0,0 of the 4x4 sheet - see
# SpriteSheetLoader.FRAME_MAP) and trims it to its opaque pixels, so a portrait is
# the character and not the transparent padding around them. Without the trim
# every icon would render small and off-centre inside its 64x64 cell.
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

	# Trim to the opaque bounds of that frame. get_image() can fail on some import
	# settings, in which case the untrimmed frame is a fine fallback.
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
# Always set body text through here rather than touching label.text - this is what
# grows the box to fit a long line, and steps the font down when even the tallest
# box would not hold it.
#
# Body text is SENTENCE CASE. Do not to_upper() it: uppercase is for labels,
# buttons, titles and names, and dialogue is the thing the player actually reads.
# ============================================================
# DIALOGUE TOKENS
# ============================================================
# Authored dialogue may carry tokens that only resolve at the moment the line is
# shown. They are substituted HERE, in the one funnel every message in the game
# passes through, so no caller and no map script has to know they exist:
#
#     "Good [TIME]! How's it going [NAME]?"  ->  "Good Morning! How's it going Olly?"
#
# Write them in the `says` blocks of NPC_and_Opponent_Data/Characters/*.json.
#
#   [TIME]  the time of day, capitalised   -> Morning / Afternoon / Evening / Night
#   [time]  the same, lowercase, for mid-sentence use ("see you in the [time]")
#   [NAME]  the player's trainer name
#
# TWO RULES THIS MUST KEEP:
#
#   1. Substitute BEFORE the RichTextLabel sees the string. A token is
#      syntactically a bbcode tag, so anything left unresolved is swallowed by
#      the parser and takes the rest of the line with it.
#   2. An UNKNOWN token is left exactly as written. A typo must show up as a
#      visible "[TIEM]" in game, never as a blanked-out line of dialogue.
#
# Adding a token is one entry in _resolve_tokens(). Keep the list short - every
# token is another thing the writer has to remember.
const TOKEN_TIME_UPPER := "[TIME]"
const TOKEN_TIME_LOWER := "[time]"
const TOKEN_NAME       := "[NAME]"

## Replaces every known dialogue token in `text`. Unknown tokens pass through
## untouched. Each lookup is skipped entirely unless its token is present, so a
## line with no tokens costs one `contains()` per token and no file I/O.
func _resolve_tokens(text: String) -> String:
	if not text.contains("["):
		return text

	var out := text
	if out.contains(TOKEN_TIME_UPPER) or out.contains(TOKEN_TIME_LOWER):
		# GameState.get_time() already returns "Morning"/"Afternoon"/"Evening"/"Night".
		var tod := GameState.get_time()
		out = out.replace(TOKEN_TIME_UPPER, tod)
		out = out.replace(TOKEN_TIME_LOWER, tod.to_lower())

	if out.contains(TOKEN_NAME):
		var pname := GameState.get_player_name()
		# A save with no name yet must not leave a hole mid-sentence.
		if pname == "":
			pname = "Trainer"
		out = out.replace(TOKEN_NAME, pname)

	return out


func set_body_text(text: String, max_font_size: int = -1) -> void:
	# Dialogue tokens ([TIME], [NAME]) resolve here, before anything measures or
	# parses the string - see _resolve_tokens() above. The RESOLVED text is what
	# gets cached, so a relayout never re-substitutes.
	text = _resolve_tokens(text)
	_body_text = text
	_body_ceiling = max_font_size

	var ceiling: int = max_font_size
	if ceiling <= 0:
		ceiling = _body_font_size
	if ceiling <= 0:
		ceiling = SYS_FONT_SIZE if _system_variant else BODY_FONT_SIZE
	var plain := _strip_bbcode(text)

	# Wrap width does not depend on the panel's height, so it can be worked out
	# before anything is laid out.
	var wrap_w := SCREEN_W - PANEL_MARGIN_X * 2.0 - _pad_side() * 2.0 - _pad_l - _pad_r
	var chrome_h := _pad_top() + _pad_bottom() + _button_block_h()

	# Grow the box to the text; if even PANEL_MAX_H will not hold it, shrink the font.
	var size := ceiling
	var text_h := _measured_text_height(plain, wrap_w, size)
	while size > BODY_MIN_FONT and chrome_h + text_h > PANEL_MAX_H:
		size -= 1
		text_h = _measured_text_height(plain, wrap_w, size)

	_panel_height = clampf(chrome_h + text_h, _panel_min_height, PANEL_MAX_H)
	_apply_body_font(size)

	# The system variant centres its text. Doing it here rather than asking the
	# callers keeps "which variant centres" in one place; an existing [center] tag
	# from a caller is harmless inside it.
	label.text = ("[center]%s[/center]" % text) if _system_variant else text

	_layout_panel()
	_place_body_label(plain, size)


func _apply_body_font(size: int) -> void:
	if label == null:
		return
	var ui := _ui()
	var font: Font = ui.font_card("body")
	label.add_theme_font_override("normal_font",  font)
	label.add_theme_font_override("bold_font",    font)
	label.add_theme_font_override("italics_font", font)
	label.add_theme_font_size_override("normal_font_size",  size)
	label.add_theme_font_size_override("bold_font_size",    size)
	label.add_theme_font_size_override("italics_font_size", size)
	label.add_theme_color_override("default_color", ui.col("field_fg"))
	label.add_theme_constant_override("line_separation", _line_gap(size))


# Extra leading needed to hit the variant's line-height ratio. Chakra Petch packs
# its lines tighter than 1.5, so this is the DIFFERENCE rather than the whole
# value - and _measured_text_height() adds the same figure per gap, which is what
# keeps the vertical centring honest.
func _line_gap(size: int) -> int:
	var ratio: float = SYS_LINE_HEIGHT if _system_variant else BODY_LINE_HEIGHT
	var natural: float = _ui().font_card("body").get_height(size)
	return maxi(0, int(round(float(size) * ratio - natural)))


# BBCode tags are markup, not glyphs - measuring them would over-estimate the width
# and shrink text that would actually have fitted.
func _strip_bbcode(text: String) -> String:
	return RegEx.create_from_string("\\[[^\\]]*\\]").sub(text, "", true)


# Centre the body text vertically by MEASURING it and placing the label, rather
# than leaving it to RichTextLabel.fit_content inside a centred VBox. fit_content's
# content height is recomputed lazily, so on the frame a box is shown it still
# reads ~0: a VBox then centres a zero-height label and the text hangs DOWN from
# the middle of the panel. One deterministic measurement avoids that.
func _place_body_label(plain: String, size: int) -> void:
	if _text_box == null or label == null:
		return
	var wrap_w  := _text_box.offset_right  - _text_box.offset_left
	var avail_h := _text_box.offset_bottom - _text_box.offset_top
	var h := _measured_text_height(plain, wrap_w, size)
	label.position = Vector2(0.0, maxf(0.0, (avail_h - h) * 0.5))
	label.size     = Vector2(wrap_w, minf(h, avail_h))


# Height of `plain` once wrapped to `wrap_w` at `size`, INCLUDING the line spacing.
# get_multiline_string_size() knows nothing about the line_separation theme
# constant, so a two-line message would otherwise measure short and centre high.
func _measured_text_height(plain: String, wrap_w: float, size: int) -> float:
	var font: Font = _ui().font_card("body")
	if font == null or plain == "":
		return 0.0
	var block: float = font.get_multiline_string_size(
		plain, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, size).y
	var line_h: float = font.get_height(size)
	var lines: int = 1 if line_h <= 0.0 else maxi(1, int(round(block / line_h)))
	return block + float(_line_gap(size) * (lines - 1))


# ============================================================
# SHOWING
# ============================================================

func show_choices(text: String, theme_key: String = "") -> void:
	apply_theme(theme_key)
	set_mode("choices")
	set_body_text(text)
	visible = true


# No OK button - set_mode("ok") hides the whole button row and shows the caret
# instead. Dismissed by a click anywhere, or Space / Enter / Escape, both of which
# the callers already route through UIInput.
func show_ok(text: String, theme_key: String = "") -> void:
	apply_theme(theme_key)
	set_mode("ok")
	set_body_text(text)
	visible = true


# NOT get_node("/root/UITheme"): configure() runs BEFORE the box is added to a
# scene, and a node outside the tree cannot resolve an absolute path. Reached
# through the main loop instead, exactly as UIKit does.
func _ui() -> Node:
	return Engine.get_main_loop().get_root().get_node_or_null("/root/UITheme")


# The caret's bob is a Tween, and a Tween needs the node in the tree. Boxes are
# routinely configured and put into "ok" mode before being added to a scene, so
# the bob is armed here rather than only at set_mode() time.
func _enter_tree() -> void:
	if _caret != null and _caret.visible:
		_set_caret_visible(true)


# The advance caret is the speaker's colour on a character box. On a system box
# there is no speaker, so it takes the UI accent - which is also exactly what the
# in-match "match" theme's base colour already is, so nothing in a match changes.
func _caret_colour() -> Color:
	if _system_variant:
		return _ui().col("accent")
	return MessageBoxTheme.chip_color(_theme_key, 0)
