class_name WaterRipples
extends Node2D

## Rings spreading out from a point on the water, drawn to sit underneath PixelBurst's
## splash pixels: the surface reacting to whatever just broke it, where the pixels are
## the water thrown into the air.
##
## Drawn with _draw() rather than a texture or a shader for the same reason PixelBurst
## is: the look is a handful of crisp pixels, and every point on a ring is SNAPPED to the
## world pixel grid before it is drawn, so a ring reads as the same chunky grain as the
## sprite art rather than as a smooth vector circle. Duplicate snapped points are dropped,
## which is also what gives a ring its uneven, hand-drawn dotting as it grows.
##
## The view is top-down-ish, so a ring is an ELLIPSE squashed vertically, not a circle.

# ---- tweakables -------------------------------------------------------------
## How flat a ring is: 1.0 would be a circle, 0.45 reads as water seen at this angle.
const SQUASH := 0.45
## World px per drawn dot. 1.0 matches PixelBurst's PIXEL_SIZE and the sprite grain.
const PIXEL_SIZE := 1.0
## A ring starts this far out rather than at nothing, so the first frame is a ring and
## not a single dot.
const START_RADIUS := 1.5
## Points sampled around a ring before snapping. Generous: snapping collapses most of
## them on a small ring and the survivors are what draw.
const SAMPLES := 64
## Rings per burst, and how long each one lasts, scaled by the burst's `strength`.
const RING_LIFE_MIN := 0.45
const RING_LIFE_MAX := 0.8
## Seconds between the rings of one burst -- they chase each other outwards.
const RING_STAGGER := 0.09
## Peak alpha of the outermost ring at its brightest, before it fades away.
const ALPHA := 0.55
## The three water tones, brightest first: a ring is drawn in the pale foam colour and
## the ones behind it in the darker blues, so a burst has depth to it.
const COLOURS := [Color8(220, 236, 248), Color8(120, 170, 214), Color8(54, 108, 158)]
# -----------------------------------------------------------------------------

var _rings: Array = []


## `radius` is how far the outermost ring reaches, in world px; `strength` (roughly
## 0.3 - 2.0) scales how many rings there are and how hard they are drawn, so it can be
## fed straight from whatever tier of splash is being fired.
static func fire(parent: Node, global_pos: Vector2, radius: float, strength: float = 1.0,
		z: int = 1) -> WaterRipples:
	var ripples := WaterRipples.new()
	ripples.z_as_relative = false
	ripples.z_index = z
	parent.add_child(ripples)
	ripples.global_position = global_pos
	var count := clampi(int(round(1.0 + strength * 1.6)), 1, 4)
	for i in count:
		ripples._rings.append({
			# Each ring behind the first is a little smaller and a little later, so they
			# read as one disturbance spreading rather than as three separate splashes.
			"radius": maxf(START_RADIUS + 1.0, radius * (1.0 - 0.22 * i)),
			"life": randf_range(RING_LIFE_MIN, RING_LIFE_MAX),
			"age": -RING_STAGGER * i,
			"alpha": clampf(ALPHA * strength, 0.1, 0.9),
			"colour": COLOURS[i % COLOURS.size()],
		})
	return ripples


func _process(delta: float) -> void:
	var alive: Array = []
	for ring in _rings:
		ring["age"] += delta
		if ring["age"] < ring["life"]:
			alive.append(ring)
	_rings = alive
	if _rings.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for ring in _rings:
		var age: float = ring["age"]
		if age < 0.0:
			continue  # still staggered behind the ring in front of it
		var t: float = clampf(age / maxf(0.01, float(ring["life"])), 0.0, 1.0)
		# Out fast and then easing to a stop, the way a real ring loses its push.
		var radius: float = lerpf(START_RADIUS, float(ring["radius"]), 1.0 - pow(1.0 - t, 2.2))
		var colour: Color = ring["colour"]
		# Up to full in the first fifth, then away to nothing: a ring appears, brightens
		# and thins out rather than switching on at its loudest.
		colour.a = float(ring["alpha"]) * minf(1.0, t * 5.0) * (1.0 - t)
		if colour.a <= 0.01:
			continue
		_draw_ring(radius, colour)


## One ellipse, sampled and SNAPPED to whole world pixels. Snapping is the whole point:
## it is what makes a ring look drawn by the same hand as the sprites, and what makes a
## small ring a few dots instead of a smooth curve.
func _draw_ring(radius: float, colour: Color) -> void:
	var drawn: Dictionary = {}
	for i in SAMPLES:
		var angle := TAU * float(i) / float(SAMPLES)
		var point := Vector2(cos(angle) * radius, sin(angle) * radius * SQUASH)
		var snapped_point := Vector2(
				snappedf(point.x, PIXEL_SIZE), snappedf(point.y, PIXEL_SIZE))
		var key := "%d,%d" % [int(snapped_point.x / PIXEL_SIZE), int(snapped_point.y / PIXEL_SIZE)]
		if drawn.has(key):
			continue
		drawn[key] = true
		draw_rect(Rect2(snapped_point - Vector2(PIXEL_SIZE, PIXEL_SIZE) * 0.5,
				Vector2(PIXEL_SIZE, PIXEL_SIZE)), colour)
