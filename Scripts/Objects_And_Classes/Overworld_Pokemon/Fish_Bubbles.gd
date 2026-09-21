class_name FishBubbles
extends Node2D

## The string of bubbles a fish tank's Pokémon breathes out: a few little rings that
## leave its mouth one after another, wobble their way up to the surface of the tank
## and pop there.
##
## Drawn with _draw() for the same reason PixelBurst is -- the look is a handful of
## crisp circles a pixel or two across, and "stop at this exact height and pop" is not
## something a particle system says nicely. Fired at the mouth's GLOBAL position with
## the water's surface height, so the bubbles rise in the world rather than following
## the fish that let them go.

# ---- tweakables -------------------------------------------------------------
## World pixels a second a bubble rises. Slow: they are meant to drift, not shoot up.
const RISE_SPEED_MIN := 9.0
const RISE_SPEED_MAX := 16.0
## Side-to-side wander on the way up (world px either way, and how fast it weaves).
const WOBBLE_PIXELS := 1.2
const WOBBLE_SPEED := 2.6
## Bubble radii in world px, and how much wider they are spread at the mouth.
const RADIUS_MIN := 0.5
const RADIUS_MAX := 1.3
const MOUTH_SPREAD := 1.2
## Seconds between one bubble and the next of the same breath -- the string.
const STAGGER_MIN := 0.10
const STAGGER_MAX := 0.22
## Seconds a bubble takes to pop at the surface: it swells a little and fades out.
const POP_TIME := 0.22
const POP_GROWTH := 1.6
## Bubbles that somehow never reach the surface still go after this long.
const MAX_LIFE := 20.0
const COLOUR := Color(0.88, 0.96, 1.0, 0.8)
const LINE_WIDTH := 0.6
# -----------------------------------------------------------------------------

## Local y the bubbles pop at (the surface of the water, in this node's space).
var _surface_y: float = 0.0
var _size_scale: float = 1.0
var _time: float = 0.0
var _bubbles: Array = []


## `global_pos` is the mouth, `surface_y` the GLOBAL y of the top of the water.
## `size` scales the bubbles with the fish that blew them. The node is parented to that
## fish (so it draws where the fish does) but is top_level, so it stays put in the world.
static func fire(parent: Node, global_pos: Vector2, surface_y: float, count: int = 3,
		size: float = 1.0) -> FishBubbles:
	var node := FishBubbles.new()
	# Kept in world space rather than towed along by whatever let it go, while still
	# drawing where its parent does -- indoors that tree position IS the draw order.
	node.top_level = true
	node._size_scale = maxf(0.2, size)
	parent.add_child(node)
	node.global_position = global_pos
	node._surface_y = surface_y - global_pos.y
	var delay := 0.0
	for i in maxi(1, count):
		node._bubbles.append({
			"delay": delay,
			"pos": Vector2(randf_range(-MOUTH_SPREAD, MOUTH_SPREAD) * node._size_scale, 0.0),
			"radius": randf_range(RADIUS_MIN, RADIUS_MAX) * node._size_scale,
			"speed": randf_range(RISE_SPEED_MIN, RISE_SPEED_MAX),
			"phase": randf() * TAU,
			# -1 until it reaches the surface, then counts up to POP_TIME.
			"pop": -1.0,
			"life": 0.0,
		})
		delay += randf_range(STAGGER_MIN, STAGGER_MAX)
	return node


func _process(delta: float) -> void:
	_time += delta
	var alive: Array = []
	for bubble in _bubbles:
		if bubble["delay"] > 0.0:
			bubble["delay"] -= delta
			alive.append(bubble)
			continue
		bubble["life"] += delta
		if bubble["pop"] >= 0.0:
			bubble["pop"] += delta
			if bubble["pop"] < POP_TIME:
				alive.append(bubble)
			continue
		bubble["pos"].y -= bubble["speed"] * delta
		bubble["pos"].x += sin(_time * WOBBLE_SPEED + bubble["phase"]) * WOBBLE_PIXELS * delta
		if bubble["pos"].y <= _surface_y or bubble["life"] >= MAX_LIFE:
			bubble["pop"] = 0.0
		alive.append(bubble)
	_bubbles = alive
	if _bubbles.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for bubble in _bubbles:
		if bubble["delay"] > 0.0:
			continue
		var radius: float = bubble["radius"]
		var colour := COLOUR
		if bubble["pop"] >= 0.0:
			# Popping: a quick swell as it thins away to nothing.
			var t: float = clampf(bubble["pop"] / POP_TIME, 0.0, 1.0)
			radius *= 1.0 + (POP_GROWTH - 1.0) * t
			colour.a *= 1.0 - t
		draw_arc(bubble["pos"], radius, 0.0, TAU, 10, colour, LINE_WIDTH, true)
