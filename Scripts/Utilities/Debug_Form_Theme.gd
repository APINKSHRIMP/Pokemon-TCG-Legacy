class_name DebugFormTheme
extends RefCounted

## The look shared by the debug authoring overlays (CharacterEditor and
## AssetPickerOverlay). Debug builds only.
##
## Godot's built-in theme is dark grey on dark grey, which is fine inside the editor
## and unreadable on top of a night-time overworld -- a LineEdit and the map behind
## it were the same colour, so the form looked like a list of headings with nothing
## after them. Everything the eye has to land on is inverted here: widgets are white
## with near-black text, and only the full-screen backdrop stays dark.
##
## Applied once to each overlay's root Control -- a Theme set on a Control is
## inherited by its whole subtree, including an OptionButton's popup, so nothing
## inside either overlay needs a per-widget colour override.

# ---- tweakables -------------------------------------------------------------
## Text drawn on a white widget.
const INK := Color(0.07, 0.07, 0.10)
## Secondary text on white: uneditable fields, disabled menu items.
const INK_DIM := Color(0.38, 0.38, 0.44)
## Placeholder text. Lighter than INK_DIM so an empty box still reads as empty.
const INK_FAINT := Color(0.48, 0.48, 0.54)
## Every interactive widget's resting background.
const PAPER := Color(1, 1, 1)
const PAPER_HOVER := Color(0.88, 0.92, 1.0)
const PAPER_PRESSED := Color(0.74, 0.82, 0.98)
## Disabled widgets. Dark enough to read as "off", light enough to still read.
const PAPER_DISABLED := Color(0.60, 0.60, 0.65)
const FOCUS_BORDER := Color(0.16, 0.52, 1.0)
const SELECTION := Color(0.20, 0.45, 0.85, 0.55)
## Labels and checkbox captions, which sit directly on the dark backdrop.
const ON_BACKDROP := Color(1, 1, 1)
## The backdrop itself. Fully opaque -- at 0.94 the debug HUD and the map behind it
## bled through every heading.
const BACKDROP := Color(0.05, 0.06, 0.09, 1.0)

const CORNER_RADIUS := 4
## Check box / radio indicator, in pixels. Godot draws these at their native size,
## so this is how big they actually appear beside 21px text.
const ICON_SIZE := 20
const ICON_BORDER := 2.0
const ICON_TICK_WIDTH := 2.6
## The indicator outline and tick.
const ICON_LINE := Color(1, 1, 1, 1)
## Inside an unticked box. Dark enough to read as a well, not so dark it disappears
## into the backdrop.
const ICON_WELL := Color(0.16, 0.17, 0.22, 0.85)
## Width of a vertical scrollbar. Anything that scrolls has to reserve this much,
## so it is a constant rather than a number buried in a stylebox.
const SCROLLBAR_THICKNESS := 14
# -----------------------------------------------------------------------------


static func build() -> Theme:
	var t := Theme.new()
	_apply_text_fields(t)
	_apply_buttons(t)
	_apply_check_boxes(t)
	_apply_spin_box(t)
	_apply_popups(t)
	_apply_scrollbars(t)
	t.set_color("font_color", "Label", ON_BACKDROP)
	t.set_color("font_color", "RichTextLabel", ON_BACKDROP)
	return t


## A white field is only legible if the caret, the selection and the placeholder are
## all repainted too -- the defaults for all three are near-white.
static func _apply_text_fields(t: Theme) -> void:
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _flat(PAPER))
		t.set_stylebox("focus", type, _flat(PAPER, FOCUS_BORDER, 2))
		t.set_stylebox("read_only", type, _flat(PAPER_DISABLED))
		t.set_color("font_color", type, INK)
		t.set_color("font_readonly_color", type, INK_DIM)
		t.set_color("font_uneditable_color", type, INK_DIM)
		t.set_color("font_placeholder_color", type, INK_FAINT)
		t.set_color("font_selected_color", type, PAPER)
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, SELECTION)
	# TextEdit paints this behind the `normal` stylebox and it defaults to near-black,
	# so the stylebox alone leaves a dark frame around a white box.
	t.set_color("background_color", "TextEdit", PAPER)
	t.set_color("current_line_color", "TextEdit", Color(0.20, 0.45, 0.85, 0.08))


static func _apply_buttons(t: Theme) -> void:
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, _flat(PAPER))
		t.set_stylebox("hover", type, _flat(PAPER_HOVER))
		t.set_stylebox("pressed", type, _flat(PAPER_PRESSED))
		t.set_stylebox("hover_pressed", type, _flat(PAPER_PRESSED))
		t.set_stylebox("disabled", type, _flat(PAPER_DISABLED))
		t.set_stylebox("focus", type, _flat(Color(0, 0, 0, 0), FOCUS_BORDER, 2))
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			t.set_color(state, type, INK)
		t.set_color("font_disabled_color", type, Color(0.26, 0.26, 0.30))
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		t.set_color(state, "Button", INK)
	# The dropdown arrow is drawn from a near-white icon and is only tinted when this
	# constant is on -- without it every OptionButton ends in an invisible arrow.
	t.set_constant("modulate_arrow", "OptionButton", 1)


## Check boxes keep a transparent background: their indicator is a light shape, so a
## white plate behind it would erase the only thing that says whether the box is on.
##
## The indicators themselves are redrawn. Godot's stock unchecked box and unchecked
## radio are a 10%-grey plate at half alpha with no outline at all -- they only read
## against the editor's mid-grey panels, and on this backdrop they vanish. The
## checked_color / unchecked_color modulates cannot rescue them either, since
## modulation multiplies and a dark pixel stays dark whatever it is multiplied by.
static func _apply_check_boxes(t: Theme) -> void:
	var icons := {
		"unchecked": _box_icon(false, false),
		"checked": _box_icon(true, false),
		"radio_unchecked": _box_icon(false, true),
		"radio_checked": _box_icon(true, true),
	}
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(state, type, StyleBoxEmpty.new())
		t.set_stylebox("focus", type, _flat(Color(0, 0, 0, 0), FOCUS_BORDER, 2))
		t.set_color("font_color", type, ON_BACKDROP)
		t.set_color("font_pressed_color", type, ON_BACKDROP)
		t.set_color("font_focus_color", type, ON_BACKDROP)
		t.set_color("font_hover_color", type, Color(1.0, 0.92, 0.6))
		t.set_color("font_hover_pressed_color", type, Color(1.0, 0.92, 0.6))
		t.set_color("font_disabled_color", type, Color(0.55, 0.55, 0.60))
		t.set_color("checkbox_checked_color", type, ON_BACKDROP)
		t.set_color("checkbox_unchecked_color", type, ON_BACKDROP)
		for icon_name in icons:
			t.set_icon(icon_name, type, icons[icon_name])
			# Nothing in either overlay disables a check box, but a theme that
			# defines three of the four states and leaves the fourth on the stock
			# invisible plate is a trap for whoever adds the first one.
			t.set_icon(icon_name + "_disabled", type, icons[icon_name])


## The SpinBox field is a real LineEdit and inherits the look above. Its two step
## buttons are not -- they are drawn in a strip beside the field with their own
## backgrounds, which default to nothing at all, so darkening the chevrons without
## also giving them a plate would leave them invisible against the backdrop.
static func _apply_spin_box(t: Theme) -> void:
	for side in ["up", "down"]:
		t.set_color(side + "_icon_modulate", "SpinBox", INK)
		t.set_color(side + "_hover_icon_modulate", "SpinBox", INK)
		t.set_color(side + "_pressed_icon_modulate", "SpinBox", INK)
		t.set_color(side + "_disabled_icon_modulate", "SpinBox", INK_DIM)
		t.set_stylebox(side + "_background", "SpinBox", _plate(PAPER))
		t.set_stylebox(side + "_background_hovered", "SpinBox", _plate(PAPER_HOVER))
		t.set_stylebox(side + "_background_pressed", "SpinBox", _plate(PAPER_PRESSED))
		t.set_stylebox(side + "_background_disabled", "SpinBox", _plate(PAPER_DISABLED))
	# Butt the strip against the field so the two read as one white control.
	t.set_constant("field_and_buttons_separation", "SpinBox", 0)
	t.set_constant("buttons_vertical_separation", "SpinBox", 0)
	t.set_constant("buttons_width", "SpinBox", 34)


static func _apply_popups(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", _flat(PAPER, Color(0.35, 0.35, 0.42), 2))
	t.set_stylebox("hover", "PopupMenu", _flat(PAPER_HOVER))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_accelerator_color", "PopupMenu", INK_DIM)
	t.set_color("font_disabled_color", "PopupMenu", INK_DIM)
	t.set_color("font_separator_color", "PopupMenu", INK_DIM)
	t.set_stylebox("panel", "PopupPanel", _flat(PAPER, Color(0.35, 0.35, 0.42), 2))


## Scrollbars are the one thing that stays light-on-dark: they ride the backdrop,
## not a widget. The default grabber is nearly the same grey as the track, which is
## what made the overflowing opponent form look like it simply had no scrollbar.
static func _apply_scrollbars(t: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _bar(Color(1, 1, 1, 0.14)))
		t.set_stylebox("scroll_focus", type, _bar(Color(1, 1, 1, 0.14)))
		t.set_stylebox("grabber", type, _bar(Color(1, 1, 1, 0.55)))
		t.set_stylebox("grabber_highlight", type, _bar(Color(1, 1, 1, 0.80)))
		t.set_stylebox("grabber_pressed", type, _bar(FOCUS_BORDER))


# ---- helpers ----------------------------------------------------------------

static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	if width > 0:
		sb.set_border_width_all(width)
		sb.border_color = border
	return sb


## One check-box indicator, drawn at ICON_SIZE: a light outline round a translucent
## well, plus a tick or a dot when it is on. Square for a check box, circular for a
## radio (a check box in a ButtonGroup, which is how the gift-type row is built).
##
## Both states are generated together so they share an outline and a size -- a 16px
## stock "checked" next to a 20px custom "unchecked" would make the row twitch every
## time it was toggled.
static func _box_icon(on: bool, round_shape: bool) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centre := Vector2(ICON_SIZE - 1, ICON_SIZE - 1) / 2.0
	var radius := ICON_SIZE / 2.0 - 0.5

	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var p := Vector2(x, y)
			# Distance from the shape's edge: negative inside, positive outside. One
			# number drives both the outline and the antialiasing at the rim.
			var edge_distance: float
			if round_shape:
				edge_distance = p.distance_to(centre) - radius
			else:
				var d := (p - centre).abs() - Vector2(radius, radius)
				edge_distance = maxf(d.x, d.y)
			if edge_distance > 0.5:
				continue
			var colour := ICON_WELL
			if edge_distance >= -ICON_BORDER:
				colour = ICON_LINE
			# Feather the last half pixel so a 20px circle is not a staircase.
			colour.a *= clampf(0.5 - edge_distance, 0.0, 1.0)
			img.set_pixel(x, y, colour)

	if on:
		if round_shape:
			_stamp_dot(img, centre, ICON_SIZE * 0.22)
		else:
			# A tick, as two strokes down-right then up-right.
			_stamp_segment(img, Vector2(0.28, 0.52) * ICON_SIZE, Vector2(0.44, 0.70) * ICON_SIZE)
			_stamp_segment(img, Vector2(0.44, 0.70) * ICON_SIZE, Vector2(0.75, 0.30) * ICON_SIZE)
	return ImageTexture.create_from_image(img)


static func _stamp_dot(img: Image, centre: Vector2, radius: float) -> void:
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var d := Vector2(x, y).distance_to(centre) - radius
			if d < 0.5:
				_blend(img, x, y, clampf(0.5 - d, 0.0, 1.0))


static func _stamp_segment(img: Image, a: Vector2, b: Vector2) -> void:
	var ab := b - a
	var length_squared := ab.length_squared()
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var p := Vector2(x, y)
			var t := 0.0 if length_squared == 0.0 else clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
			var d := p.distance_to(a + ab * t) - ICON_TICK_WIDTH * 0.5
			if d < 0.5:
				_blend(img, x, y, clampf(0.5 - d, 0.0, 1.0))


## Paint ICON_LINE over whatever is already there at `alpha`. The indicator is drawn
## on top of the well, so it has to composite rather than overwrite -- a plain
## set_pixel would punch the well's transparency through the tick's soft edges.
static func _blend(img: Image, x: int, y: int, alpha: float) -> void:
	var under := img.get_pixel(x, y)
	var over := ICON_LINE
	var out_a: float = alpha + under.a * (1.0 - alpha)
	if out_a <= 0.0:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var rgb: Color = (over * alpha + under * under.a * (1.0 - alpha)) / out_a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, out_a))


## A flat plate with no padding of its own, for anything whose size is dictated by
## the widget rather than by its content.
static func _plate(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER_RADIUS)
	return sb


## A scrollbar stylebox's content margins ARE its thickness -- ScrollBar takes its
## minimum width straight off them -- so these are deliberately small and even
## rather than the roomy field padding above.
static func _bar(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.content_margin_left = SCROLLBAR_THICKNESS / 2.0
	sb.content_margin_right = SCROLLBAR_THICKNESS / 2.0
	sb.content_margin_top = SCROLLBAR_THICKNESS / 2.0
	sb.content_margin_bottom = SCROLLBAR_THICKNESS / 2.0
	return sb
