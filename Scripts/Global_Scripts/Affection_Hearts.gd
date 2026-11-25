extends Control

# ============================================================
# AFFECTION HEARTS (2026-11-25) -- your Pokémon's affection on its message box
# ============================================================
# Seven hearts straddling the box's top edge, each a touch bigger than the last, like the
# opponents' rank stars (Difficulty_Stars.gd). One heart = one affection level
# (PokemonAffection.LEVEL_SIZE points), and each fills from the left like a bar, so half way
# to the next level shows that heart half full. Right-aligned at the box's right end - or,
# while the action menu is docked there, just left of the menu.
# When it was built with a "from" value (a pet, a meal), the fill slides up to the new one.
# A child of the message box, so it goes when the box goes. MapManager.show_affection_hearts().
# ============================================================

# TWEAKABLE
## Width of each heart, 1st to 7th (screen px).
const HEART_SIZES := [28.0, 30.0, 32.0, 34.0, 36.0, 38.0, 40.0]
const GAP := 5.0
## Distance in from the box's right edge (no menu), and the gap left of the menu.
const INSET_RIGHT := 28.0
const MENU_GAP := 4.0
const FILL := Color(1.0, 0.33, 0.52)
const EMPTY := Color(1.0, 1.0, 1.0, 0.28)
const OUTLINE := Color(0.08, 0.06, 0.1, 0.9)
const OUTLINE_WIDTH := 2.5
const FADE_IN := 0.15
## The slide from the old fill to the new one.
const FILL_DELAY := 0.25
const FILL_TIME := 0.7

var _box: Control = null
var _value: float = 0.0     ## hearts filled, 0..7 (fractions = part-filled)
var _target: float = 0.0
var _placed_at: Vector2 = Vector2(-1, -1)
static var _unit: PackedVector2Array = PackedVector2Array()


func setup(message_box: Control, points: int, from_points: int = -1) -> void:
	_box = message_box
	var per := float(PokemonAffection.LEVEL_SIZE)
	_target = clampf(float(points) / per, 0.0, float(HEART_SIZES.size()))
	_value = clampf(float(from_points) / per, 0.0, float(HEART_SIZES.size())) if from_points >= 0 else _target
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_place()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_IN)
	if not is_equal_approx(_value, _target):
		tw.tween_interval(FILL_DELAY)
		tw.tween_method(_set_value, _value, _target, FILL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_value(v: float) -> void:
	_value = v
	queue_redraw()


func _process(_delta: float) -> void:
	if _box == null or not is_instance_valid(_box):
		return
	visible = _box.visible
	var spot := Vector2(_right_edge(), (_box.call("panel_top_right") as Vector2).y)
	if spot != _placed_at:
		_place()


## Where the row's right end goes: the box's right end, or short of the action menu.
func _right_edge() -> float:
	var right: float = (_box.call("panel_top_right") as Vector2).x - INSET_RIGHT
	var menu = MapManager._action_menu
	if menu != null and is_instance_valid(menu) and menu.has_method("panel_left"):
		right = minf(right, float(menu.call("panel_left")) - MENU_GAP)
	return right


func _place() -> void:
	var w := 0.0
	var h := 0.0
	for d in HEART_SIZES:
		w += d + GAP
		h = maxf(h, d)
	w -= GAP
	size = Vector2(w, h)
	var right := _right_edge()
	var top: float = (_box.call("panel_top_right") as Vector2).y
	_placed_at = Vector2(right, top)
	# Bottoms line up; the row's middle sits on the box's top edge.
	position = Vector2(right - w, top - h * 0.5)
	queue_redraw()


func _draw() -> void:
	var x := 0.0
	for n in HEART_SIZES.size():
		var d: float = HEART_SIZES[n]
		var origin := Vector2(x, size.y - d)
		var pts := heart_points(origin, d)
		draw_colored_polygon(pts, EMPTY)
		var fill := clampf(_value - float(n), 0.0, 1.0)
		if fill > 0.0:
			var clip := PackedVector2Array([origin, origin + Vector2(d * fill, 0.0),
					origin + Vector2(d * fill, d), origin + Vector2(0.0, d)])
			for part in Geometry2D.intersect_polygons(pts, clip):
				draw_colored_polygon(part, FILL)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, OUTLINE, OUTLINE_WIDTH, true)
		x += d + GAP


## A heart filling the square `size` x `size` at `origin` (top-left).
static func heart_points(origin: Vector2, heart_size: float) -> PackedVector2Array:
	if _unit.is_empty():
		var raw := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var steps := 40
		for k in steps:
			var t := TAU * float(k) / float(steps)
			var p := Vector2(16.0 * pow(sin(t), 3.0),
					-(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)))
			raw.append(p)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var span := maxf(hi.x - lo.x, hi.y - lo.y)
		var pad := (Vector2(span, span) - (hi - lo)) * 0.5
		for p in raw:
			_unit.append((p - lo + pad) / span)
	var out := PackedVector2Array()
	for p in _unit:
		out.append(origin + p * heart_size)
	return out
