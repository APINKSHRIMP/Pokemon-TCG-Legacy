extends Control

# ============================================================
# DIFFICULTY STARS -- how hard an opponent is, on their Yes/No challenge box
# ============================================================
# A row of stars straddling the message box's top edge at its right-hand end, each one
# bigger than the last. 1-5 are gold, with the ones not earned drawn as dim outlines so
# the scale can be read. The 6th (orange), 7th (red) and 8th (purple) are secret: they
# only appear on the opponents that have them -- the Card Elders, the gym leaders, and
# Mewtwo alone.
# A child of the message box, so it goes when the box goes. MapManager builds one per
# challenge (_show_difficulty_stars); the rating is Opponent_Ratings.stars_for().
# ============================================================

# TWEAKABLE
## Outer diameter of each star, 1st to 8th (screen px). Each one grows.
const STAR_SIZES := [24.0, 28.0, 32.0, 36.0, 40.0, 46.0, 52.0, 60.0]
const GAP := 4.0
## Distance in from the box's right edge.
const INSET_RIGHT := 28.0
const GOLD := Color(1.0, 0.82, 0.25)
const ORANGE := Color(1.0, 0.55, 0.12)
const RED := Color(0.95, 0.18, 0.18)
const PURPLE := Color(0.7, 0.3, 1.0)
const EMPTY := Color(1.0, 1.0, 1.0, 0.28)
const OUTLINE := Color(0.08, 0.06, 0.1, 0.9)
const OUTLINE_WIDTH := 2.5
const FADE_IN := 0.15
## Inner radius of the star's points as a share of the outer.
const INNER_RATIO := 0.45

var stars: int = 0
var _message_box: Control = null


func setup(message_box: Control, star_count: int) -> void:
	_message_box = message_box
	stars = clampi(star_count, 0, STAR_SIZES.size())
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	UIKit.on_screen_resized(_place)
	_place()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_IN)


## How many stars are drawn: always the five, plus the secret ones that were earned.
func _shown() -> int:
	return maxi(5, stars)


func _place() -> void:
	var w := 0.0
	var h := 0.0
	for n in _shown():
		w += STAR_SIZES[n] + (GAP if n > 0 else 0.0)
		h = maxf(h, STAR_SIZES[n])
	size = Vector2(w, h)
	var corner: Vector2 = _message_box.call("panel_top_right")
	# Bottoms line up; the row's middle sits on the box's top edge.
	position = Vector2(corner.x - INSET_RIGHT - w, corner.y - h * 0.5)
	queue_redraw()


func _draw() -> void:
	var x := 0.0
	for n in _shown():
		var d: float = STAR_SIZES[n]
		var centre := Vector2(x + d * 0.5, size.y - d * 0.5)
		var colour := EMPTY
		if n < stars:
			colour = GOLD if n < 5 else [ORANGE, RED, PURPLE][n - 5]
		var points := _star(centre, d * 0.5)
		draw_colored_polygon(points, colour)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, OUTLINE, OUTLINE_WIDTH, true)
		x += d + GAP


func _star(centre: Vector2, outer: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var r := outer if k % 2 == 0 else outer * INNER_RATIO
		var a := -PI * 0.5 + k * PI / 5.0
		pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts
