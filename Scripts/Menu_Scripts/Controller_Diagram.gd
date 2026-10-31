
extends Control

# ============================================================
# CONTROLLER DIAGRAM
# ============================================================
# A game pad drawn in code with a callout line from every button that does
# something to a label saying what it does - the "button map" diagram every pad
# game ships with. Drawn rather than an image so it follows the colour theme, has
# no artwork licence to worry about, and can switch between the Xbox and the
# PlayStation layout (sticks and D-pad swap places, the face buttons change from
# letters to shapes) with nothing but a redraw.
#
#   set_map(entries, family)
#     entries  Array of [button_id, action_text]; only these buttons get callouts.
#              Ids: a b x y lb rb lt rt lstick rstick dpad view menu
#     family   "xbox" or "playstation"
#
# Everything is laid out on a PAD_BOX design box, scaled by PAD_SCALE, with the
# label columns either side. The whole control is DESIGN_SIZE and centres its
# content in whatever size it is given.
# ============================================================

## TWEAKABLE. The pad outline is authored in this box (x from the centre line).
const PAD_BOX := Vector2(640.0, 420.0)
const PAD_SCALE := 1.15
## Gap between the pad's outer edge and the label columns.
const COLUMN_GAP := 70.0
## The label columns' width.
const LABEL_W := 300.0
## The least vertical distance between two labels in one column.
const LABEL_MIN_GAP := 62.0
## Overall size the diagram asks for.
const DESIGN_SIZE := Vector2(PAD_BOX.x * PAD_SCALE + (COLUMN_GAP + LABEL_W) * 2.0, 600.0)
const LINE_W := 2.0
const BUTTON_NAME_SIZE := 15
const ACTION_SIZE := 20

## Face-button colours. Xbox: A green, B red, X blue, Y yellow. PlayStation is the
## symbol colours on a dark button.
const XBOX_FACE := {"a": Color("5DBB4C"), "b": Color("E2463F"), "x": Color("3C7BE0"), "y": Color("F1C232")}
const PS_SYMBOL := {"a": Color("8AA9E8"), "b": Color("E86A72"), "x": Color("D88AC8"), "y": Color("5BC6A6")}

const NAMES := {
	"xbox": {
		"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT",
		"lstick": "Left stick", "rstick": "Right stick", "dpad": "D-pad", "view": "View", "menu": "Menu",
	},
	"playstation": {
		"a": "Cross", "b": "Circle", "x": "Square", "y": "Triangle", "lb": "L1", "rb": "R1",
		"lt": "L2", "rt": "R2", "lstick": "Left stick", "rstick": "Right stick", "dpad": "D-pad",
		"view": "Create", "menu": "Options",
	},
}

var _entries: Array = []
var _family: String = "xbox"
var _label_nodes: Array = []


func _init() -> void:
	custom_minimum_size = DESIGN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_map(entries: Array, family: String) -> void:
	_entries = entries
	_family = family if NAMES.has(family) else "xbox"
	_rebuild_labels()
	queue_redraw()


static func button_name(id: String, family: String) -> String:
	var table: Dictionary = NAMES.get(family, NAMES["xbox"])
	return String(table.get(id, id))


# ── Geometry ─────────────────────────────────────────────────────────────────

## The pad's top-left in this control's coordinates.
func _pad_origin() -> Vector2:
	var pad_size := PAD_BOX * PAD_SCALE
	return Vector2((size.x - pad_size.x) * 0.5, (size.y - pad_size.y) * 0.5 + 20.0)


## A point in PAD_BOX coordinates (x measured from the centre line) -> local.
func _p(x: float, y: float) -> Vector2:
	return _pad_origin() + Vector2(PAD_BOX.x * 0.5 + x, y) * PAD_SCALE


func _button_pos(id: String) -> Vector2:
	var ps := _family == "playstation"
	match id:
		"lstick": return _p(-85, 238) if ps else _p(-158, 150)
		"dpad":   return _p(-158, 150) if ps else _p(-88, 238)
		"rstick": return _p(85, 238)
		"y": return _p(158, 108)
		"x": return _p(120, 150)
		"b": return _p(196, 150)
		"a": return _p(158, 192)
		"view": return _p(-52, 132)
		"menu": return _p(52, 132)
		"lb": return _p(-205, 32)
		"rb": return _p(205, 32)
		"lt": return _p(-215, 6)
		"rt": return _p(215, 6)
	return _p(0, 0)


## The right half of the outline, clockwise from the top centre; mirrored for the left.
const _HALF := [
	Vector2(0, 52), Vector2(70, 50), Vector2(140, 40), Vector2(200, 30), Vector2(248, 34),
	Vector2(282, 52), Vector2(304, 86), Vector2(320, 135), Vector2(334, 200), Vector2(346, 268),
	Vector2(352, 330), Vector2(344, 372), Vector2(318, 398), Vector2(284, 402), Vector2(256, 384),
	Vector2(230, 350), Vector2(204, 316), Vector2(172, 298), Vector2(120, 292), Vector2(0, 292),
]


func _outline() -> PackedVector2Array:
	var ring: Array = []
	for v in _HALF:
		ring.append(v)
	for i in range(_HALF.size() - 2, 0, -1):
		var v: Vector2 = _HALF[i]
		ring.append(Vector2(-v.x, v.y))
	var smooth := _catmull_rom(ring, 6)
	var out := PackedVector2Array()
	for v in smooth:
		out.append(_p(v.x, v.y))
	return out


## A closed Catmull-Rom spline through `pts`, `steps` points per span.
func _catmull_rom(pts: Array, steps: int) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in range(n):
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		for s in range(steps):
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var body := Color(UITheme.col("field_fg"), 0.10)
	var edge := Color(UITheme.col("field_fg"), 0.55)
	var part := Color(UITheme.col("field_fg"), 0.16)
	var accent := UITheme.col("accent")
	var s := PAD_SCALE

	# Triggers and bumpers sit behind the body's top edge.
	for side in [-1.0, 1.0]:
		_draw_round_rect(Rect2(_p(side * 215 - 30, -8), Vector2(60, 26) * s), 9 * s, part, edge)
		_draw_round_rect(Rect2(_p(side * 205 - 52, 22), Vector2(104, 20) * s), 9 * s, part, edge)

	var outline := _outline()
	draw_colored_polygon(outline, body)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, edge, 3.0, true)

	# Centre (guide) button.
	draw_circle(_p(0, 100), 22 * s, part)
	draw_arc(_p(0, 100), 22 * s, 0, TAU, 40, edge, 2.0, true)

	# View / Menu.
	for id in ["view", "menu"]:
		var c := _button_pos(id)
		_draw_round_rect(Rect2(c - Vector2(15, 9) * s, Vector2(30, 18) * s), 8 * s, part, edge)

	# Sticks.
	for id in ["lstick", "rstick"]:
		var c := _button_pos(id)
		draw_circle(c, 40 * s, Color(0, 0, 0, 0.25))
		draw_arc(c, 40 * s, 0, TAU, 48, edge, 2.0, true)
		draw_circle(c, 26 * s, part)
		draw_arc(c, 26 * s, 0, TAU, 40, edge, 2.0, true)

	# D-pad.
	var d := _button_pos("dpad")
	var arm := 14.0 * s
	var reach := 36.0 * s
	draw_rect(Rect2(d - Vector2(reach, arm), Vector2(reach * 2, arm * 2)), part)
	draw_rect(Rect2(d - Vector2(arm, reach), Vector2(arm * 2, reach * 2)), part)
	var cross := PackedVector2Array([
		d + Vector2(-arm, -reach), d + Vector2(arm, -reach), d + Vector2(arm, -arm),
		d + Vector2(reach, -arm), d + Vector2(reach, arm), d + Vector2(arm, arm),
		d + Vector2(arm, reach), d + Vector2(-arm, reach), d + Vector2(-arm, arm),
		d + Vector2(-reach, arm), d + Vector2(-reach, -arm), d + Vector2(-arm, -arm),
		d + Vector2(-arm, -reach)])
	draw_polyline(cross, edge, 2.0, true)

	# Face buttons.
	var font: Font = UITheme.font("button")
	for id in ["a", "b", "x", "y"]:
		var c := _button_pos(id)
		var r := 18.0 * s
		if _family == "playstation":
			draw_circle(c, r, Color(0.08, 0.08, 0.1, 0.85))
			draw_arc(c, r, 0, TAU, 32, edge, 2.0, true)
			_draw_ps_symbol(id, c, r * 0.5, PS_SYMBOL[id])
		else:
			draw_circle(c, r, XBOX_FACE[id])
			draw_arc(c, r, 0, TAU, 32, Color(0, 0, 0, 0.35), 2.0, true)
			var letter := String(id).to_upper()
			var fs := int(20 * s)
			var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, c + Vector2(-w.x * 0.5, w.y * 0.32), letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.08))

	# Callout lines.
	for info in _callouts():
		draw_polyline(info["points"], accent, LINE_W, true)
		draw_circle(info["anchor"], 4.0, accent)


func _draw_ps_symbol(id: String, c: Vector2, r: float, col: Color) -> void:
	match id:
		"a":   # cross
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 3.0, true)
			draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 3.0, true)
		"b":   # circle
			draw_arc(c, r, 0, TAU, 28, col, 3.0, true)
		"x":   # square
			draw_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), col, false, 3.0)
		"y":   # triangle
			var tri := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.7),
				c + Vector2(-r * 0.95, r * 0.7), c + Vector2(0, -r)])
			draw_polyline(tri, col, 3.0, true)


func _draw_round_rect(r: Rect2, radius: float, fill: Color, line: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(2)
	sb.border_color = line
	sb.anti_aliasing = true
	draw_style_box(sb, r)


# ── Callouts ─────────────────────────────────────────────────────────────────

## Which column each button's label goes in. View and Menu sit in the middle of the
## pad, where a line out to either side would cut across the face buttons or the
## sticks, so their labels go ABOVE the pad instead.
const SIDE := {
	"lb": "left", "lt": "left", "lstick": "left", "dpad": "left", "view": "top",
	"menu": "top", "y": "right", "x": "right", "b": "right", "a": "right",
	"rb": "right", "rt": "right", "rstick": "right",
}
## Buttons whose line climbs straight up first and then runs out sideways, because a
## straight run would cross a neighbour (X sits directly left of B). Their label is
## ordered as if the button were this high (PAD_BOX units).
const CLIMB_FIRST := {"x": 70.0}
## How far above the pad's top edge the View / Menu labels sit, and how far each
## leans out from its button.
const TOP_LABEL_RISE := 46.0
const TOP_LABEL_LEAN := 80.0


## For every entry: the polyline from its button to its label, and the label's rect.
## Labels in one column are kept LABEL_MIN_GAP apart, in the order of their buttons.
func _callouts() -> Array:
	var pad_left: float = _pad_origin().x
	var pad_right: float = pad_left + PAD_BOX.x * PAD_SCALE
	var sides := {"left": [], "right": [], "top": []}
	for e in _entries:
		var id: String = e[0]
		var pos := _button_pos(id)
		var side: String = SIDE.get(id, "left" if pos.x < size.x * 0.5 else "right")
		var order_y: float = pos.y
		if CLIMB_FIRST.has(id):
			order_y = _p(0, CLIMB_FIRST[id]).y
		sides[side].append({"id": id, "text": String(e[1]), "anchor": pos, "order_y": order_y})

	var out: Array = []
	# Above the pad: up from the button, then out (View to the left, Menu to the right).
	for item in sides["top"]:
		var a: Vector2 = item["anchor"]
		var y: float = _pad_origin().y - TOP_LABEL_RISE
		var lean: float = -TOP_LABEL_LEAN if a.x < size.x * 0.5 else TOP_LABEL_LEAN
		var end := Vector2(a.x + lean, y)
		item["points"] = PackedVector2Array([a, Vector2(a.x, y), end])
		item["side"] = "left" if lean < 0.0 else "right"
		var lx: float = end.x - LABEL_W - 8.0 if lean < 0.0 else end.x + 8.0
		item["label_rect"] = Rect2(Vector2(lx, y - 26.0), Vector2(LABEL_W, 52.0))
		out.append(item)

	for side in ["left", "right"]:
		var list: Array = sides[side]
		list.sort_custom(func(p, q): return p["order_y"] < q["order_y"])
		# Spread the labels: start at each button's height, push down to clear the one
		# above, then pull the whole column back up if it ran off the bottom.
		var ys: Array = []
		var prev := -INF
		for item in list:
			var y: float = maxf(item["order_y"], prev + LABEL_MIN_GAP)
			ys.append(y)
			prev = y
		var bottom_limit := size.y - 30.0
		if not ys.is_empty() and ys[-1] > bottom_limit:
			var shift: float = ys[-1] - bottom_limit
			for i in ys.size():
				ys[i] = maxf(30.0 + i * LABEL_MIN_GAP, ys[i] - shift)
		for i in list.size():
			var item: Dictionary = list[i]
			var y: float = ys[i]
			var end_x: float = pad_left - COLUMN_GAP + 10.0 if side == "left" else pad_right + COLUMN_GAP - 10.0
			var elbow_x: float = pad_left - 18.0 if side == "left" else pad_right + 18.0
			var label_x: float = end_x - LABEL_W - 8.0 if side == "left" else end_x + 8.0
			var a: Vector2 = item["anchor"]
			if CLIMB_FIRST.has(item["id"]):
				item["points"] = PackedVector2Array([a, Vector2(a.x, y), Vector2(end_x, y)])
			else:
				item["points"] = PackedVector2Array([a, Vector2(elbow_x, y), Vector2(end_x, y)])
			item["label_rect"] = Rect2(Vector2(label_x, y - 26.0), Vector2(LABEL_W, 52.0))
			item["side"] = side
			out.append(item)
	return out


func _rebuild_labels() -> void:
	for n in _label_nodes:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_label_nodes.clear()
	if not is_inside_tree() or size == Vector2.ZERO:
		return
	for info in _callouts():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r: Rect2 = info["label_rect"]
		box.position = r.position
		box.size = r.size
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var align := HORIZONTAL_ALIGNMENT_RIGHT if info["side"] == "left" else HORIZONTAL_ALIGNMENT_LEFT

		var name_label := Label.new()
		UIKit.set_label(name_label, "small_label", button_name(info["id"], _family), "accent", BUTTON_NAME_SIZE)
		name_label.horizontal_alignment = align
		box.add_child(name_label)

		var action := Label.new()
		UIKit.set_label(action, "body", info["text"], "field_fg", ACTION_SIZE)
		action.horizontal_alignment = align
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(action)

		add_child(box)
		_label_nodes.append(box)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_rebuild_labels.call_deferred()
		queue_redraw()
