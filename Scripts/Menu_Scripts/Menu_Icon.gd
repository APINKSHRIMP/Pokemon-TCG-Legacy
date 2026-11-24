class_name MenuIcon
extends Control

# ============================================================
# MENU ICON — the main menu's icons, drawn rather than imported
# ============================================================
# Eight icons, every one drawn from primitives in _draw(). They replace eight
# PNGs of screenshotted game art (a real trainer card, real coin renders, real
# sleeve photos) which could not take a colour from the theme and sat at
# whatever resolution they happened to be.
#
# ── WHY DRAWN, NOT BAKED ─────────────────────────────────────
# These are the only art on the menu that has to RECOLOUR. Each tile carries its
# own hue and its own computed label colour, so the icon on it must be that
# colour too — and that colour is not known until the theme is read. A drawn
# icon takes `ink` as a parameter and is correct on every tile of every theme;
# a baked one would need 8 icons x 8 looks of pre-tinted PNGs.
#
# They also stay sharp at any size, which matters because the hero tile's icon
# is ~340px and the footer's are 78px.
#
# ── HOW TO DRAW ONE ──────────────────────────────────────────
# Every icon is authored in a 0..1 UNIT SQUARE and scaled to fit whatever rect
# the node is given, centred on the short axis. `_u(x, y)` maps a unit point into
# local pixels and `_s(n)` scales a unit length. Nothing in here should contain a
# raw pixel number — that is what keeps one icon legible at 78px and at 340px.
#
# Keep them simple. At a glance, on a saturated tile, a silhouette reads and a
# detailed illustration does not.
# ============================================================

enum Kind { CARDS, ID, COSTUME, COIN, SLEEVES, GEAR, CLOSE, POWER }

var kind: int = Kind.CARDS
var ink: Color = Color.WHITE

# Set once at build time by the menu. Kept so a theme change can repaint the
# icon without rebuilding the node.
var _origin := Vector2.ZERO
var _scale := 1.0


func _init(icon_kind: int = Kind.CARDS, icon_ink: Color = Color.WHITE) -> void:
	kind = icon_kind
	ink = icon_ink
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	# Fit the unit square into the rect, centred. Icons are square by design; a
	# non-square rect simply leaves margin on the long axis.
	_scale = minf(size.x, size.y)
	_origin = (size - Vector2(_scale, _scale)) * 0.5

	match kind:
		Kind.CARDS:   _draw_cards()
		Kind.ID:      _draw_id()
		Kind.COSTUME: _draw_costume()
		Kind.COIN:    _draw_coin()
		Kind.SLEEVES: _draw_sleeves()
		Kind.GEAR:    _draw_gear()
		Kind.CLOSE:   _draw_close()
		Kind.POWER:   _draw_power()


# ─── Unit-space helpers ──────────────────────────────────────────────────────

func _u(x: float, y: float) -> Vector2:
	return _origin + Vector2(x, y) * _scale


func _s(n: float) -> float:
	return n * _scale


## A rounded rectangle in unit space, as a filled polygon. draw_rect has no
## corner radius and StyleBoxes cannot be used inside _draw().
func _round_rect(centre: Vector2, half: Vector2, r: float, col: Color,
		rotation: float = 0.0) -> void:
	var pts := PackedVector2Array()
	var steps := 5
	# Four corner arcs, clockwise from bottom-right. Typed, or `corner` comes out
	# as Variant and every expression built from it loses its type too.
	var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for corner in corners:
		var pivot: Vector2 = Vector2(half.x - r, half.y - r) * corner
		var base := atan2(corner.y, corner.x) - PI * 0.25
		for i in steps + 1:
			var a: float = base + PI * 0.5 * (float(i) / float(steps))
			pts.append(pivot + Vector2(cos(a), sin(a)) * r)
	# Rotate about the shape's own centre, then translate.
	var out := PackedVector2Array()
	for pt in pts:
		out.append(centre + (pt as Vector2).rotated(rotation))
	draw_colored_polygon(out, col)


func _ring(centre: Vector2, radius: float, width: float, col: Color) -> void:
	draw_arc(centre, radius, 0.0, TAU, 64, col, width, true)


# ─── The icons ───────────────────────────────────────────────────────────────

## CARDS — three cards fanned from a shared bottom pivot. The hero tile.
func _draw_cards() -> void:
	var pivot := _u(0.5, 0.78)
	var half := Vector2(_s(0.185), _s(0.27))
	var r := _s(0.035)
	# Back two cards dimmed so the fan reads as depth rather than as one shape.
	var angles: Array[float] = [-0.42, 0.0, 0.42]
	var alphas: Array[float] = [0.55, 1.0, 0.55]
	# Outer cards first so the middle one sits on top.
	var order: Array[int] = [0, 2, 1]
	for i in order:
		var a: float = angles[i]
		var c := ink
		c.a = ink.a * alphas[i]
		# Each card leans out from the pivot, so its centre swings with it.
		var centre: Vector2 = pivot + Vector2(0, -half.y * 0.92).rotated(a)
		_round_rect(centre, half, r, c, a)


## ID — a trainer card: plate, portrait window, three text lines.
func _draw_id() -> void:
	var centre := _u(0.5, 0.5)
	_round_rect(centre, Vector2(_s(0.38), _s(0.27)), _s(0.045), ink)

	# The window and the lines are punched out in the TILE colour behind, which
	# is what `hole` carries — drawing them in a darker ink would read as a
	# second colour on a two-colour icon.
	var hole := Color(0, 0, 0, 0.34)
	_round_rect(_u(0.33, 0.5), Vector2(_s(0.115), _s(0.16)), _s(0.03), hole)
	for i in 3:
		var y: float = 0.40 + float(i) * 0.10
		_round_rect(_u(0.63, y), Vector2(_s(0.13), _s(0.022)), _s(0.022), hole)


## COSTUME — a shirt silhouette: shoulders, sleeves, body, collar.
func _draw_costume() -> void:
	var body := PackedVector2Array([
		_u(0.32, 0.24), _u(0.42, 0.20), _u(0.58, 0.20), _u(0.68, 0.24),
		_u(0.86, 0.38), _u(0.76, 0.50), _u(0.70, 0.44),
		_u(0.70, 0.82), _u(0.30, 0.82), _u(0.30, 0.44),
		_u(0.24, 0.50), _u(0.14, 0.38),
	])
	draw_colored_polygon(body, ink)
	# The collar, punched out so the shirt reads as a garment not a cross.
	var collar := PackedVector2Array([
		_u(0.42, 0.20), _u(0.50, 0.32), _u(0.58, 0.20),
	])
	draw_colored_polygon(collar, Color(0, 0, 0, 0.34))


## COIN — a disc with a rim and a simple ball motif.
func _draw_coin() -> void:
	var centre := _u(0.5, 0.5)
	draw_circle(centre, _s(0.34), ink)
	_ring(centre, _s(0.34), _s(0.035), Color(0, 0, 0, 0.30))

	# A band across the middle with a hub on it — the Poke Ball read, without
	# borrowing the real mark.
	var band := Color(0, 0, 0, 0.30)
	_round_rect(centre, Vector2(_s(0.30), _s(0.028)), _s(0.028), band)
	draw_circle(centre, _s(0.10), band)
	draw_circle(centre, _s(0.055), ink)


## SLEEVES — three stacked sleeves, offset so the stack reads as depth.
func _draw_sleeves() -> void:
	var half := Vector2(_s(0.20), _s(0.28))
	var r := _s(0.035)
	var alphas: Array[float] = [0.45, 0.7, 1.0]
	for i in 3:
		var off: Vector2 = Vector2(_s(-0.13 + 0.13 * float(i)), _s(0.07 - 0.07 * float(i)))
		var c := ink
		c.a = ink.a * alphas[i]
		_round_rect(_u(0.5, 0.5) + off, half, r, c)
	# The front sleeve's mouth, so the top card reads as being inside something.
	_round_rect(_u(0.63, 0.29), Vector2(_s(0.20), _s(0.045)), _s(0.03),
		Color(0, 0, 0, 0.30))


## GEAR — a cog: toothed ring with a punched hub.
func _draw_gear() -> void:
	var centre := _u(0.5, 0.5)
	var teeth := 8
	var r_out := _s(0.40)
	var r_in := _s(0.29)

	# The toothed outline as one polygon: out, out, in, in, repeating.
	var pts := PackedVector2Array()
	var step := TAU / float(teeth)
	for i in teeth:
		var a := step * float(i)
		# A tooth occupies 45% of its step, the gap the rest.
		pts.append(centre + Vector2(cos(a - step * 0.22), sin(a - step * 0.22)) * r_out)
		pts.append(centre + Vector2(cos(a + step * 0.22), sin(a + step * 0.22)) * r_out)
		pts.append(centre + Vector2(cos(a + step * 0.28), sin(a + step * 0.28)) * r_in)
		pts.append(centre + Vector2(cos(a + step * 0.72), sin(a + step * 0.72)) * r_in)
	draw_colored_polygon(pts, ink)

	draw_circle(centre, _s(0.145), Color(0, 0, 0, 0.34))


## CLOSE — an X. Two bars crossed, with rounded ends.
func _draw_close() -> void:
	var centre := _u(0.5, 0.5)
	var half := Vector2(_s(0.34), _s(0.075))
	_round_rect(centre, half, _s(0.075), ink, PI * 0.25)
	_round_rect(centre, half, _s(0.075), ink, -PI * 0.25)


## POWER — a broken ring with a stroke through the gap at the top.
func _draw_power() -> void:
	var centre := _u(0.5, 0.54)
	var r := _s(0.30)
	var w := _s(0.115)
	# The gap sits at the top, so the arc runs from upper-right round to
	# upper-left the long way.
	draw_arc(centre, r, -PI * 0.35, PI * 1.35, 48, ink, w, true)
	_round_rect(_u(0.5, 0.30), Vector2(_s(0.055), _s(0.155)), _s(0.055), ink)
