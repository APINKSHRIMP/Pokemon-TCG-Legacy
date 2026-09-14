class_name PixelBurst
extends Node2D

## A handful of square pixels fired up and outwards from a ground point, pulled
## back down by gravity, each vanishing as it falls back to (roughly) the height it
## started from -- as if it hit the floor. The dirt puff when a Diglett pops out,
## the sand for Sandygast, the splash for a surfacing Pokémon.
##
## Drawn with _draw() rather than CPUParticles2D: the look is a few crisp pixels,
## and "die when you land" is not something a particle system can express.

# ---- tweakables -------------------------------------------------------------
const GRAVITY := 260.0
## Size of one pixel in world units. Sprites draw at 0.5 scale, so 1.0 here is two
## art pixels -- about the grain of the sprite art itself.
const PIXEL_SIZE := 1.0
# -----------------------------------------------------------------------------

var _particles: Array = []


## `colours` is picked from at random per pixel. `speed` scales the launch.
static func fire(parent: Node, global_pos: Vector2, colours: Array, count: int = 14,
		speed: float = 1.0, width: float = 8.0, z: int = 1) -> PixelBurst:
	var burst := PixelBurst.new()
	burst.z_as_relative = false
	burst.z_index = z
	parent.add_child(burst)
	burst.global_position = global_pos
	for i in count:
		var dir := -1.0 if randf() < 0.5 else 1.0
		burst._particles.append({
			"pos": Vector2(randf_range(-width, width) * 0.5, 0.0),
			"vel": Vector2(dir * randf_range(12.0, 55.0), -randf_range(45.0, 95.0)) * speed,
			# Each lands at its own height, so they don't all blink out on one line.
			"floor": randf_range(-3.0, 1.0),
			"colour": colours[randi() % colours.size()] if not colours.is_empty() else Color.WHITE,
			"size": PIXEL_SIZE * (1.0 if randf() < 0.7 else 1.5),
		})
	return burst


func _process(delta: float) -> void:
	var alive: Array = []
	for p in _particles:
		p["vel"].y += GRAVITY * delta
		p["pos"] += p["vel"] * delta
		if p["vel"].y > 0.0 and p["pos"].y >= p["floor"]:
			continue
		alive.append(p)
	_particles = alive
	if _particles.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var s: float = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(s, s) * 0.5, Vector2(s, s)), p["colour"])
