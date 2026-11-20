class_name MedalSparkle
extends RefCounted

# ============================================================
# MEDAL SPARKLE - the pixel glitter on a medal (same look as the coin case's sparkle: square pixels that fade
# in and out), in the medal's own colours, with more pixels the higher the grade.
#   slate     dark grey / black pixels, the fewest        silver    mid grey / light grey
#   bronze    copper / pale copper                         gold      gold / pale gold
#   platinum  light grey-blue / white, the most (platinum+ a few more again)
# RAMPS are the medal art's own ramps (+10% saturation / brightness, as in medal_art_build.py): [darkest .. lightest].
# ============================================================

const RAMPS := {
	"slate":    ["#2c3540", "#4b5765", "#6c7c8f", "#94a3b7", "#c6d3e2"],
	"bronze":   ["#45230b", "#804116", "#b66723", "#df8e40", "#ffc07f"],
	"silver":   ["#484e58", "#7e8591", "#b1b8c3", "#dce2ea", "#f8fcff"],
	"gold":     ["#513a02", "#866608", "#c29412", "#f2c827", "#ffec7d"],
	"platinum": ["#355c64", "#6897a1", "#9dcbd3", "#d2f5fa", "#f2feff"],
}
## TWEAKABLE: the two pixel colours per metal (picked at random per pixel), and how many pixels a 116px tile gets.
## The count climbs steeply from silver up (12 / 26 / 56 / 72), slate and bronze stay sparse.
const PIXELS := {
	"slate":     {"a": Color(0.17, 0.18, 0.21), "b": Color(0.03, 0.035, 0.05), "count": 4},
	"bronze":    {"a": Color(0.95, 0.58, 0.28), "b": Color(1.0, 0.8, 0.55), "count": 6},
	"silver":    {"a": Color(0.66, 0.69, 0.75), "b": Color(0.92, 0.94, 0.97), "count": 12},
	"gold":      {"a": Color(1.0, 0.84, 0.2), "b": Color(1.0, 0.95, 0.6), "count": 26},
	"platinum":  {"a": Color(0.78, 0.88, 0.9), "b": Color(1.0, 1.0, 1.0), "count": 56},
	"platinum+": {"a": Color(0.78, 0.88, 0.9), "b": Color(1.0, 1.0, 1.0), "count": 72},
}


static func ramp(metal: String) -> Array:
	var out: Array = []
	for h in RAMPS.get(metal.trim_suffix("+"), RAMPS["gold"]):
		out.append(Color(String(h)))
	return out


## Adds a glitter emitter over `holder` (a Control whose size is final). `scale` multiplies the COUNT (1.0 = a 116px
## tile's worth), `pixel_scale` the size of each pixel (1.0 on a tile). Returns the emitter, named "sparkle" - keep
## the reference and free it yourself before attaching another (a second one would be renamed and linger).
static func attach(holder: Control, metal: String, scale: float = 1.0, extents: Vector2 = Vector2.ZERO, pixel_scale: float = 1.0) -> CPUParticles2D:
	var spec: Dictionary = PIXELS.get(metal, PIXELS["gold"])
	var p := CPUParticles2D.new()
	p.name = "sparkle"
	p.position = holder.size / 2.0
	p.z_index = 5
	p.amount = maxi(2, int(round(float(spec["count"]) * scale)))
	p.lifetime = 1.1
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.emitting = true
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents if extents != Vector2.ZERO else holder.size * 0.36
	p.direction = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 2.0 * pixel_scale
	p.scale_amount_max = 4.0 * pixel_scale
	# two colours at random per pixel, each fading in and out like the coin sparkle
	var mix := Gradient.new()
	mix.set_color(0, spec["a"])
	mix.set_color(1, spec["b"])
	mix.set_offset(0, 0.0)
	mix.set_offset(1, 1.0)
	p.color_initial_ramp = mix
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.3, Color(1, 1, 1, 1.0))
	fade.add_point(0.6, Color(1.3, 1.3, 1.3, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	holder.add_child(p)
	return p
