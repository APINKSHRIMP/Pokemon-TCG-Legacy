class_name PokemonSurfacer
extends OverworldPokemon

## SURFACING template -- Magikarp, Tentacool, Mantine... The spawn point is on the
## water. The Pokémon rises out of it slowly, one row of pixels at a time, only ever
## showing its top half. Rows near the waterline are tinted towards the sea's own
## blue: the row touching the water is fully blue, and each row above it is less so,
## back to full colour TINT_ROWS rows up -- so as it rises its head clears the water
## and regains its colour while the rest stays murky. A splash of blue pixels goes
## up as it breaks the surface. It drifts a couple dozen pixels left or right, then
## sinks back the same way, bottom row first, with another splash.

# ---- tweakables -------------------------------------------------------------
const Z := 1
## The sea blue (sampled from the reference swatch: 54, 108, 158).
const WATER_COLOUR := Color8(54, 108, 158)
## Rows above the waterline over which the tint fades from full blue to none.
const TINT_ROWS := 8.0
## Fraction of the art (from the top) that ever comes above water.
const SHOWN_FRACTION := 0.5
## Seconds to fully surface / submerge. Deliberately slower than a Diglett.
const RISE_TIME := 1.4
const SINK_TIME := 1.4
const HOLD_BEFORE_DRIFT := 0.8
const HOLD_AFTER_DRIFT := 0.8
## World pixels drifted while surfaced, and how fast.
const DRIFT_MIN := 20.0
const DRIFT_MAX := 32.0
const DRIFT_SPEED := 7.0
const DRIFT_ANIM_SPEED := 0.5
const SPLASH_COLOURS := [Color8(54, 108, 158), Color8(120, 170, 214), Color8(220, 236, 248)]
const SPLASH_COUNT := 18
const SPLASH_SPEED := 0.8
# -----------------------------------------------------------------------------

const TINT_SHADER := """
shader_type canvas_item;
uniform vec4 water_colour : source_color = vec4(0.2118, 0.4235, 0.6196, 1.0);
// Absolute texture row just BELOW the lowest row being drawn, i.e. the waterline.
uniform float waterline_row = 0.0;
uniform float tint_rows = 8.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float row = floor(UV.y / TEXTURE_PIXEL_SIZE.y);
	float depth = waterline_row - 1.0 - row;
	float t = clamp(1.0 - depth / tint_rows, 0.0, 1.0);
	COLOR = vec4(mix(c.rgb, water_colour.rgb, t), c.a);
}
"""

enum Phase { RISING, HOLD_BEFORE, DRIFT, HOLD_AFTER, SINKING }

static var _shader: Shader = null

var _phase: int = Phase.RISING
var _time: float = 0.0
var _max_rows: int = 1
var _drift_dir: float = 1.0
var _drift_left: float = 0.0
var _material: ShaderMaterial = null


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	animating = false
	if _shader == null:
		_shader = Shader.new()
		_shader.code = TINT_SHADER
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.set_shader_parameter("water_colour", WATER_COLOUR)
	_material.set_shader_parameter("tint_rows", TINT_ROWS)
	sprite.material = _material
	_max_rows = maxi(1, ceili(art_height() * SHOWN_FRACTION))
	_drift_dir = -1.0 if randf() < 0.5 else 1.0
	_drift_left = randf_range(DRIFT_MIN, DRIFT_MAX)
	# Faces the way it is about to drift from the moment it breaks the surface.
	set_facing("right" if _drift_dir > 0.0 else "left")
	set_clip_rows(0)
	_splash()


func _on_region_applied(cell_origin: Vector2, rows_shown: int) -> void:
	if _material != null:
		_material.set_shader_parameter("waterline_row", cell_origin.y + art_top + rows_shown)


func _template_process(delta: float) -> void:
	_time += delta
	match _phase:
		Phase.RISING:
			var t := clampf(_time / RISE_TIME, 0.0, 1.0)
			set_clip_rows(ceili(_max_rows * t))
			if t >= 1.0:
				_next(Phase.HOLD_BEFORE)
		Phase.HOLD_BEFORE:
			if _time >= HOLD_BEFORE_DRIFT:
				_next(Phase.DRIFT)
				animating = true
				anim_speed = DRIFT_ANIM_SPEED
				_apply_region()
		Phase.DRIFT:
			var step := minf(DRIFT_SPEED * delta, _drift_left)
			global_position.x += _drift_dir * step
			_drift_left -= step
			if _drift_left <= 0.0:
				_next(Phase.HOLD_AFTER)
				animating = false
				_apply_region()
		Phase.HOLD_AFTER:
			if _time >= HOLD_AFTER_DRIFT:
				_next(Phase.SINKING)
				_splash()
		Phase.SINKING:
			var t := clampf(_time / SINK_TIME, 0.0, 1.0)
			set_clip_rows(ceili(_max_rows * (1.0 - t)))
			if t >= 1.0:
				despawn()


func _next(phase: int) -> void:
	_phase = phase
	_time = 0.0


func _splash() -> void:
	var width := cell.x * SPRITE_SCALE * 0.5
	PixelBurst.fire(get_parent(), global_position, SPLASH_COLOURS, SPLASH_COUNT, SPLASH_SPEED, width, Z + 1)
