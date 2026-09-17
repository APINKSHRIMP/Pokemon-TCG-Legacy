class_name PokemonSurfacer
extends OverworldPokemon

## SURFACING template -- Magikarp, Tentacool, Mantine... The spawn point (or water area)
## is on the water, and the Pokémon is always drawn in full with a waterline through it:
##
##   above the waterline   its own colours, tinted towards the sea's blue near the water
##                         (ABOVE_TINT at the waterline, none TINT_ROWS rows up)
##   below the waterline   a solid dark-blue silhouette (DEEP_COLOUR), the bottom
##                         FADE_ROWS rows fading out, so it reads as seen through water
##
## SURFACING: the dark shape fades in from its top down; halfway through that fade it
## starts rising through the waterline (with a splash). As soon as it is up it swims
## (DRIFT). SUBMERGING is the same in reverse: it sinks at once (with a splash) and,
## part-way down, fades out from its bottom up.

# ---- tweakables -------------------------------------------------------------
const Z := 1
## The sea blue (sampled from the reference swatch: 54, 108, 158). Used for the tint on
## the part above the water and for the splash.
const WATER_COLOUR := Color8(54, 108, 158)
## How blue the row touching the water gets (0 = none, 1 = fully the sea colour).
const ABOVE_TINT := 0.5
## Rows above the waterline over which that tint fades away.
const TINT_ROWS := 8.0
## The underwater silhouette's colour -- a darker blue than the sea so it stays visible.
const DEEP_COLOUR := Color8(24, 56, 102)
## Sprite rows at the very bottom of the art that fade from visible to gone (8 rows is
## about 10 px on screen at normal scale and the default zoom).
const FADE_ROWS := 8.0
## Fraction of the art (from the top) that ever comes above water. 0.75 = the original
## half, +25%, then +20% again.
const SHOWN_FRACTION := 0.75
## Seconds for the top-down fade-in (and the bottom-up fade-out), and how soft its
## moving edge is, in sprite rows.
const REVEAL_TIME := 0.6
const REVEAL_SOFT_ROWS := 4.0
## How far through the fade-in it starts rising (0.5 = halfway). The same share of the
## fade-out is left when it finishes sinking.
const RISE_START := 0.5
## Seconds to fully surface / submerge.
const RISE_TIME := 0.7
const SINK_TIME := 0.7
## World pixels drifted while surfaced, and how fast.
const DRIFT_MIN := 20.0
const DRIFT_MAX := 32.0
## The default swimming speed; each species can have its own (registry `swim_speed`).
const DRIFT_SPEED := 7.0
## The paddling animation follows the swim speed (DRIFT_SPEED = normal), within these.
const SWIM_ANIM_MIN := 0.25
const SWIM_ANIM_MAX := 2.0
const DRIFT_ANIM_SPEED := 0.5
## With a water area: it swims towards one of the two edges with the most room --
## picked at random -- covering a random REGION_DRIFT_FRACTION_MIN..1 of the way there,
## so no two swims are the same length. Rolling near 1 takes it right up to the water's
## edge, where it submerges like anywhere else. There is deliberately no fixed ceiling
## on the distance: capping it made every swim in a pond bigger than the cap exactly
## the cap long, which is what "they all travel the same distance" was.
const REGION_DRIFT_FRACTION_MIN := 0.5
const SPLASH_COLOURS := [Color8(54, 108, 158), Color8(120, 170, 214), Color8(220, 236, 248)]
const SPLASH_COUNT := 18
const SPLASH_SPEED := 0.8
# -----------------------------------------------------------------------------

const WATER_SHADER := """
shader_type canvas_item;
uniform vec4 water_colour : source_color = vec4(0.2118, 0.4235, 0.6196, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.094, 0.2196, 0.4, 1.0);
// Absolute texture row of the first row BELOW the water.
uniform float waterline_row = 0.0;
// Absolute texture row just past the last row of art.
uniform float bottom_row = 0.0;
uniform float tint_rows = 8.0;
uniform float above_tint = 0.5;
uniform float fade_rows = 8.0;
// Absolute texture row the top-down reveal has reached; rows above it are shown, with a
// soft edge `reveal_soft` rows deep.
uniform float reveal_row = 0.0;
uniform float reveal_soft = 4.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float row = floor(UV.y / TEXTURE_PIXEL_SIZE.y);
	float shown = clamp((reveal_row - row) / reveal_soft, 0.0, 1.0);
	if (row >= waterline_row) {
		float fade = clamp((bottom_row - row) / fade_rows, 0.0, 1.0);
		COLOR = vec4(deep_colour.rgb, c.a * fade * shown);
	} else {
		float depth = waterline_row - 1.0 - row;
		float t = clamp(1.0 - depth / tint_rows, 0.0, 1.0) * above_tint;
		COLOR = vec4(mix(c.rgb, water_colour.rgb, t), c.a * shown);
	}
}
"""

enum Phase { SURFACING, DRIFT, SUBMERGING }

static var _shader: Shader = null


## The water shader, compiled once and shared. PokemonSkittish's "jumps into water"
## escape uses the same one, so a Pokemon going under looks the same wherever it happens
## -- same blue, same fade into the depths.
static func water_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = WATER_SHADER
	return _shader

var _phase: int = Phase.SURFACING
var _time: float = 0.0
var _max_rows: int = 1
var _drift_vec: Vector2 = Vector2.RIGHT
var _swim_speed: float = DRIFT_SPEED
var _drift_left: float = 0.0
var _material: ShaderMaterial = null
## 0 = nothing revealed, 1 = the whole sprite; the edge moves top to bottom.
var _reveal: float = 0.0
## Absolute texture row of the top of the art in the current frame's cell.
var _art_top_row: float = 0.0
var _splashed: bool = false


## Under water at spawn: it is lit in _template_process() as it surfaces instead.
func glow_on_spawn() -> bool:
	return false


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	animating = false
	_material = ShaderMaterial.new()
	_material.shader = water_shader()
	_material.set_shader_parameter("water_colour", WATER_COLOUR)
	_material.set_shader_parameter("deep_colour", DEEP_COLOUR)
	_material.set_shader_parameter("tint_rows", TINT_ROWS)
	_material.set_shader_parameter("above_tint", ABOVE_TINT)
	_material.set_shader_parameter("fade_rows", FADE_ROWS)
	_material.set_shader_parameter("reveal_soft", REVEAL_SOFT_ROWS)
	sprite.material = _material
	_max_rows = maxi(1, ceili(art_height() * SHOWN_FRACTION))
	_swim_speed = OverworldPokemonData.species_swim_speed(species)
	var region := OverworldPokemonData.point_region(spawn_point)
	if region.has_area():
		_aim_at_furthest_edge(region)
	else:
		_drift_vec = Vector2.LEFT if randf() < 0.5 else Vector2.RIGHT
		_drift_left = randf_range(DRIFT_MIN, DRIFT_MAX)
	# Faces the way it is about to drift from the moment it shows up under the water.
	face_vector(_drift_vec)
	set_clip_rows(0)
	_set_reveal(0.0)


## The base class clips the art to the rows above the waterline. A surfacer draws ALL of
## it -- the shader turns the rows below the waterline into the dark underwater shape --
## so the clip is widened back to the full art here, keeping the base's placement of the
## waterline on local y = 0.
func _on_region_applied(cell_origin: Vector2, rows_shown: int) -> void:
	sprite.visible = true
	sprite.region_rect = Rect2(cell_origin.x, cell_origin.y + art_top, cell.x, art_height())
	_art_top_row = cell_origin.y + art_top
	if _material != null:
		_material.set_shader_parameter("waterline_row", _art_top_row + rows_shown)
		# The lowest visible row stays put ON SCREEN: at full height the art ends where it
		# ends, and for every row it is below full height one more row is cut off the
		# bottom (the soft fade rides along with the cut), so sinking eats into it from
		# below rather than sliding the whole shape down.
		var rows_below_full := _max_rows - rows_shown
		_material.set_shader_parameter("bottom_row", cell_origin.y + art_bottom + 1 - rows_below_full)
		_set_reveal(_reveal)


## 0..1 of the sprite shown, from its top down. The soft edge starts above the art so 0
## really is nothing, and ends below it so 1 really is everything.
func _set_reveal(amount: float) -> void:
	_reveal = clampf(amount, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("reveal_row",
				_art_top_row + _reveal * (art_height() + REVEAL_SOFT_ROWS))


func _template_process(delta: float) -> void:
	_time += delta
	var rise_delay := REVEAL_TIME * RISE_START
	match _phase:
		Phase.SURFACING:
			# Fade in top-down from the start; rise from halfway through the fade.
			_set_reveal(_time / REVEAL_TIME)
			var rise_t := clampf((_time - rise_delay) / RISE_TIME, 0.0, 1.0)
			if _time >= rise_delay and not _splashed:
				_splashed = true
				_splash()   # breaking the surface
				# A Chinchou's lure lights up as it breaks the surface, not while it is
				# still a shape under the water -- which is why this template opts out of
				# the base class's spawn-time glow.
				PokemonGlow.attach(self, sprite, species, self)
			set_clip_rows(ceili(_max_rows * rise_t))
			if rise_t >= 1.0 and _reveal >= 1.0:
				_next(Phase.DRIFT)
				animating = true
				anim_speed = DRIFT_ANIM_SPEED * clampf(_swim_speed / DRIFT_SPEED, SWIM_ANIM_MIN, SWIM_ANIM_MAX)
				_apply_region()
		Phase.DRIFT:
			# A swim speed of 0 never gets anywhere, so it goes straight to submerging.
			if _swim_speed <= 0.0:
				_drift_left = 0.0
			var step := minf(_swim_speed * delta, _drift_left)
			global_position += _drift_vec * step
			_drift_left -= step
			if _drift_left <= 0.0:
				_next(Phase.SUBMERGING)
				animating = false
				_apply_region()
				_splash()
		Phase.SUBMERGING:
			# The reverse: sink from the start, and fade out bottom-up so that the fade
			# ends where the fade-in began -- rise_delay after the sink is complete.
			var sink_t := clampf(_time / SINK_TIME, 0.0, 1.0)
			set_clip_rows(ceili(_max_rows * (1.0 - sink_t)))
			var fade_start := SINK_TIME + rise_delay - REVEAL_TIME
			_set_reveal(1.0 - (_time - fade_start) / REVEAL_TIME)
			if sink_t >= 1.0 and _reveal <= 0.0:
				despawn()


## Surfaced somewhere inside its water area: head, in a straight line, towards one of the
## TWO edges with the most room -- picked at random, a coin flip between them. In the
## top-right of a pond that is down or left; in the bottom-left, up or right. (In a pond
## far wider than it is tall the two roomiest edges are nearly always left and right, so
## it will look horizontal unless it surfaces near one end.) How far it goes is rolled
## against the room it has that way, so it never swims out of the water.
func _aim_at_furthest_edge(region: Rect2) -> void:
	var pos := global_position
	var room := [
		[Vector2.LEFT, pos.x - region.position.x],
		[Vector2.RIGHT, region.end.x - pos.x],
		[Vector2.UP, pos.y - region.position.y],
		[Vector2.DOWN, region.end.y - pos.y],
	]
	room.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var choice: Array = room[randi() % 2]
	_drift_vec = choice[0]
	# How far it could go before running out of water this way, and how far it actually
	# does: at least REGION_DRIFT_FRACTION_MIN of it, at most all of it. The fraction
	# multiplies the room it HAS, so a big pond gives long swims and a puddle short ones;
	# clamping after the roll instead pinned every roomy pond to the same length.
	var available := maxf(float(choice[1]), 0.0)
	_drift_left = randf_range(REGION_DRIFT_FRACTION_MIN, 1.0) * available


func _next(phase: int) -> void:
	_phase = phase
	_time = 0.0


func _splash() -> void:
	var width := cell.x * draw_scale() * 0.5
	PixelBurst.fire(get_parent(), global_position, SPLASH_COLOURS, SPLASH_COUNT, SPLASH_SPEED, width, Z + 1)
