class_name DebugFormTheme
extends RefCounted

## The look shared by every debug tool: the DEL menu, the F placement tool and its side
## panel, the character / Pokemon editors, the pickers and the cast list. Debug builds only.
##
## 2026-11-12 redesign: a calm dark "dev tool" look instead of glaring white widgets.
##   - Everything sits on a solid PANEL card (or the full-screen BACKDROP), never straight
##     on the map, so text always has a dark, even surface behind it.
##   - Widgets are slate (PAPER) with a thin border; text is near-white (INK).
##   - Colour means something: ACCENT blue = the main action / selection, DANGER red =
##     destroys something, SUCCESS green = saved / on, WARN amber = unsaved / attention,
##     HEADING gold = section titles.
##   - Variations, set with `control.theme_type_variation = "..."`:
##       Buttons: "PrimaryButton", "DangerButton", "ToggleOnButton" (a switch that is on)
##       Labels:  "Heading" (section title), "Hint" (small grey help), "KeyCap" (a key badge)
##   - Helpers: card_style(), heading(), hint(), key_cap(), button(), key_row().
##
## Applied once to each overlay's root Control -- a Theme set on a Control is inherited by
## its whole subtree, including an OptionButton's popup.

# ---- tweakables -------------------------------------------------------------
## Text on widgets and on the backdrop.
const INK := Color(0.93, 0.94, 0.97)
## Secondary text: hints, uneditable fields, disabled menu items.
const INK_DIM := Color(0.64, 0.67, 0.75)
## Placeholder text. Darker than INK_DIM so an empty box still reads as empty.
const INK_FAINT := Color(0.46, 0.49, 0.57)
## Every interactive widget's resting background, and its hover / pressed / disabled.
const PAPER := Color(0.17, 0.19, 0.26)
const PAPER_HOVER := Color(0.23, 0.26, 0.35)
const PAPER_PRESSED := Color(0.27, 0.34, 0.52)
const PAPER_DISABLED := Color(0.12, 0.13, 0.17)
## The thin border round widgets, and text fields' darker well.
const EDGE := Color(0.31, 0.34, 0.44)
const FIELD := Color(0.09, 0.10, 0.14)
const FOCUS_BORDER := Color(0.40, 0.64, 1.0)
const SELECTION := Color(0.30, 0.52, 0.95, 0.55)
## Meaningful colours.
const ACCENT := Color(0.30, 0.55, 0.98)
const ACCENT_HOVER := Color(0.38, 0.63, 1.0)
const DANGER := Color(0.78, 0.26, 0.28)
const DANGER_HOVER := Color(0.88, 0.33, 0.35)
const SUCCESS := Color(0.38, 0.82, 0.52)
const WARN := Color(1.0, 0.70, 0.30)
const HEADING := Color(1.0, 0.80, 0.40)
## Labels and checkbox captions, which sit directly on the dark backdrop.
const ON_BACKDROP := INK
## The full-screen backdrop behind a form. Fully opaque so nothing bleeds through.
const BACKDROP := Color(0.05, 0.06, 0.09, 1.0)
## A floating card over the map (HUD, side panel, toasts).
const PANEL := Color(0.07, 0.08, 0.12, 0.94)
const PANEL_EDGE := Color(0.26, 0.29, 0.38, 0.9)

const CORNER_RADIUS := 6
## Check box / radio indicator, in pixels.
const ICON_SIZE := 20
const ICON_BORDER := 2.0
const ICON_TICK_WIDTH := 2.6
const ICON_LINE := Color(0.93, 0.94, 0.97, 1)
const ICON_WELL := Color(0.09, 0.10, 0.14, 1.0)
## Width of a vertical scrollbar. Anything that scrolls has to reserve this much.
const SCROLLBAR_THICKNESS := 12
## Font sizes the helpers use.
const HEADING_SIZE := 17
const HINT_SIZE := 15
const KEYCAP_SIZE := 15
# -----------------------------------------------------------------------------


static func build() -> Theme:
	var t := Theme.new()
	_apply_text_fields(t)
	_apply_buttons(t)
	_apply_variations(t)
	_apply_check_boxes(t)
	_apply_spin_box(t)
	_apply_popups(t)
	_apply_scrollbars(t)
	t.set_color("font_color", "Label", ON_BACKDROP)
	t.set_color("default_color", "RichTextLabel", ON_BACKDROP)
	t.set_stylebox("panel", "TooltipPanel", _flat(Color(0.10, 0.11, 0.16), EDGE, 1))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("separator", "HSeparator", _line(Color(1, 1, 1, 0.10)))
	t.set_constant("separation", "HSeparator", 6)
	return t


## The floating card every overlay sits on: dark, slightly see-through, thin edge.
static func card_style(padding: int = 14) -> StyleBoxFlat:
	var sb := _flat(PANEL, PANEL_EDGE, 1)
	sb.set_content_margin_all(padding)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb


## Text fields are a darker well than buttons, so "type here" and "click me" never look alike.
static func _apply_text_fields(t: Theme) -> void:
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _flat(FIELD, EDGE, 1))
		t.set_stylebox("focus", type, _flat(FIELD, FOCUS_BORDER, 2))
		t.set_stylebox("read_only", type, _flat(PAPER_DISABLED, EDGE, 1))
		t.set_color("font_color", type, INK)
		t.set_color("font_readonly_color", type, INK_DIM)
		t.set_color("font_uneditable_color", type, INK_DIM)
		t.set_color("font_placeholder_color", type, INK_FAINT)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, SELECTION)
	# TextEdit paints this behind the `normal` stylebox; it has to match the well.
	t.set_color("background_color", "TextEdit", FIELD)
	t.set_color("current_line_color", "TextEdit", Color(1, 1, 1, 0.04))


static func _apply_buttons(t: Theme) -> void:
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button_styles(t, type, PAPER, PAPER_HOVER, PAPER_PRESSED, EDGE)
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			t.set_color(state, type, INK)
		t.set_color("font_disabled_color", type, INK_FAINT)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		t.set_color(state, "Button", INK)
	# The dropdown arrow is only tinted when this constant is on.
	t.set_constant("modulate_arrow", "OptionButton", 1)


static func _button_styles(t: Theme, type: String, bg: Color, hover: Color, pressed: Color, edge: Color) -> void:
	t.set_stylebox("normal", type, _flat(bg, edge, 1))
	t.set_stylebox("hover", type, _flat(hover, edge.lightened(0.2), 1))
	t.set_stylebox("pressed", type, _flat(pressed, FOCUS_BORDER, 1))
	t.set_stylebox("hover_pressed", type, _flat(pressed, FOCUS_BORDER, 1))
	t.set_stylebox("disabled", type, _flat(PAPER_DISABLED, Color(1, 1, 1, 0.06), 1))
	t.set_stylebox("focus", type, _flat(Color(0, 0, 0, 0), FOCUS_BORDER, 2))


## Button and label variations. Each names its base type, so it inherits everything else.
static func _apply_variations(t: Theme) -> void:
	for v in [["PrimaryButton", ACCENT, ACCENT_HOVER], ["DangerButton", DANGER, DANGER_HOVER],
			["ToggleOnButton", Color(0.17, 0.42, 0.30), Color(0.21, 0.50, 0.36)]]:
		var name: String = v[0]
		var bg: Color = v[1]
		var hover: Color = v[2]
		t.set_type_variation(name, "Button")
		_button_styles(t, name, bg, hover, bg.darkened(0.2), bg.lightened(0.15))
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			t.set_color(state, name, Color.WHITE)
	t.set_type_variation("Heading", "Label")
	t.set_color("font_color", "Heading", HEADING)
	t.set_font_size("font_size", "Heading", HEADING_SIZE)
	t.set_type_variation("Hint", "Label")
	t.set_color("font_color", "Hint", INK_DIM)
	t.set_font_size("font_size", "Hint", HINT_SIZE)
	t.set_type_variation("KeyCap", "Label")
	t.set_color("font_color", "KeyCap", INK)
	t.set_font_size("font_size", "KeyCap", KEYCAP_SIZE)
	var cap := _flat(Color(0.22, 0.25, 0.33), Color(0.42, 0.46, 0.58), 1)
	cap.border_width_bottom = 3
	cap.content_margin_left = 7
	cap.content_margin_right = 7
	cap.content_margin_top = 1
	cap.content_margin_bottom = 1
	t.set_stylebox("normal", "KeyCap", cap)


# ---- building blocks ---------------------------------------------------------

## A section title: gold caps with a faint rule under it.
static func heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Heading"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


## Small grey help text that wraps.
static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Hint"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A keyboard key drawn as a little raised badge: "Tab", "Shift + J", "Del".
static func key_cap(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = "KeyCap"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A tool button that never takes focus (a focused button eats the arrow keys the player
## walks with). `key` puts the shortcut in the tooltip; `variation` is "", "PrimaryButton",
## "DangerButton" or "ToggleOnButton".
static func button(text: String, action: Callable, key: String = "", variation: String = "",
		font_size: int = 17) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = variation
	b.add_theme_font_size_override("font_size", font_size)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text = text
	if key != "":
		b.tooltip_text = "Shortcut key: %s" % key
	b.pressed.connect(action)
	return b


## One line of a key guide: the key badge(s) then what they do. Several keys are
## separated with " / " ("Tab / Shift + Tab").
static func key_row(keys: String, what: String, key_width: float = 150.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var keys_box := HBoxContainer.new()
	keys_box.custom_minimum_size = Vector2(key_width, 0)
	keys_box.add_theme_constant_override("separation", 4)
	keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in keys.split(" / "):
		keys_box.add_child(key_cap(k.strip_edges()))
	row.add_child(keys_box)
	var l := Label.new()
	l.text = what
	l.add_theme_font_size_override("font_size", HINT_SIZE + 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


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
	var panel := _flat(Color(0.12, 0.13, 0.18), EDGE, 1)
	panel.set_content_margin_all(4)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("hover", "PopupMenu", _flat(ACCENT))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_accelerator_color", "PopupMenu", INK_DIM)
	t.set_color("font_disabled_color", "PopupMenu", INK_FAINT)
	t.set_color("font_separator_color", "PopupMenu", INK_DIM)
	t.set_stylebox("panel", "PopupPanel", panel)


## Scrollbars ride the backdrop: a faint track and a clearly lighter grabber.
static func _apply_scrollbars(t: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _bar(Color(1, 1, 1, 0.06)))
		t.set_stylebox("scroll_focus", type, _bar(Color(1, 1, 1, 0.06)))
		t.set_stylebox("grabber", type, _bar(Color(1, 1, 1, 0.30)))
		t.set_stylebox("grabber_highlight", type, _bar(Color(1, 1, 1, 0.50)))
		t.set_stylebox("grabber_pressed", type, _bar(FOCUS_BORDER))


## A one-pixel horizontal rule for HSeparator.
static func _line(colour: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = colour
	sb.thickness = 1
	return sb


# ---- helpers ----------------------------------------------------------------

static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
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
