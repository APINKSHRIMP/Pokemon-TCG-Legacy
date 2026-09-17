class_name PokemonGlow
extends PointLight2D

## The light the handful of Pokémon that carry one give off.
##
##   Chinchou / Lanturn    a low yellow light, from the middle of the sprite (the bulbs
##                         on their antennae). Lit as they break the surface.
##   Finneon / Lumineon    a smaller, fainter blue one, same place (their fins).
##   Volbeat / Illumise    the yellow light again, but hanging low and BEHIND them --
##                         it is their tail that glows, so it sits down and to whichever
##                         side is behind whichever way they happen to be facing.
##   Morelull / Shiinotic  the small faint light again, purple: their caps.
##   Tynamo / Eelektrik /  the yellow, at the small light's size: the electric organs
##   Eelektross            down their sides.
##
## Nothing else in the game glows, so this is deliberately a short table rather than
## another registry field -- there is no Pokémon-wide "has a light" concept to hang it
## off, and inventing one would put an unused key on two thousand species.
##
## Written as a FOLLOWER rather than an ordinary child: `top_level` is on, so the light
## never inherits the host sprite's scale (a caught Pokémon hangs at half scale) or its
## rotation (it is turned a quarter turn on the rod). It frees itself when whatever it is
## following goes away.

# ---- tweakables -------------------------------------------------------------
## `radius` is in WORLD px and `energy` is the PointLight2D energy at the TOP of the
## breath. `offset` is where the light sits relative to the sprite's origin, also in
## world px; its x is "BEHIND", and is mirrored for whichever way the Pokémon faces.
const CENTRED := Vector2.ZERO
## Down and behind: a firefly's tail, not its head.
const TAIL := Vector2(3.5, 4.0)

const YELLOW := {"colour": Color8(255, 224, 130), "energy": 0.95, "radius": 28.0, "offset": CENTRED}
const YELLOW_TAIL := {"colour": Color8(255, 224, 130), "energy": 0.95, "radius": 28.0, "offset": TAIL}
const YELLOW_SMALL := {"colour": Color8(255, 224, 130), "energy": 0.7, "radius": 17.0, "offset": CENTRED}
const BLUE := {"colour": Color8(126, 198, 255), "energy": 0.55, "radius": 17.0, "offset": CENTRED}
const PURPLE := {"colour": Color8(186, 130, 255), "energy": 0.55, "radius": 17.0, "offset": CENTRED}

const GLOWS := {
	"170_Chinchou": YELLOW,
	"171_Lanturn": YELLOW,
	"456_Finneon": BLUE,
	"457_Lumineon": BLUE,
	"313_Volbeat": YELLOW_TAIL,
	"314_Illumise": YELLOW_TAIL,
	"755_Morelull": PURPLE,
	"756_Shiinotic": PURPLE,
	"602_Tynamo": YELLOW_SMALL,
	"603_Eelektrik": YELLOW_SMALL,
	"604_Eelektross": YELLOW_SMALL,
}

## The breath: it sinks to PULSE_DEPTH below full over half a period and comes back up
## over the other half, so 5.0 here is "dimmest 2.5 seconds after brightest".
const PULSE_PERIOD := 5.0
const PULSE_DEPTH := 0.2

## The light texture is built once and shared: a plain radial white-to-nothing gradient,
## the same shape the harbour's street lamps use. LIGHT_TEXTURE_SIZE only sets its
## resolution -- how far the light actually falls is texture_scale, off `radius`.
const LIGHT_TEXTURE_SIZE := 64
# -----------------------------------------------------------------------------

static var _light_texture_cache: GradientTexture2D = null

## What this light is stuck to, and where on it. Gone -> the light frees itself.
var follow: Node2D = null
var follow_offset: Vector2 = Vector2.ZERO
## When set, follow_offset.x is read as "behind" and flipped to match this Pokémon's
## facing. Left null the offset is taken literally.
var face_source: OverworldPokemon = null

var _base_energy: float = 1.0
var _pulse: float = 0.0


## True when this species carries a light at all.
static func glows(species: String) -> bool:
	return GLOWS.has(species)


## Lights `target` up, if its species is one of the few. `host` is where the light lives
## in the tree -- anything that outlives the beat; the light positions itself in global
## space regardless. `face_from` is the Pokémon whose facing mirrors a tail light; leave
## it null for a centred one or for anything that has no facing (a hooked fish on a rod).
## Returns null for every other species, which is the normal case.
static func attach(host: Node, target: Node2D, species: String,
		face_from: OverworldPokemon = null) -> PokemonGlow:
	if host == null or target == null or not GLOWS.has(species):
		return null
	var cfg: Dictionary = GLOWS[species]
	var glow := PokemonGlow.new()
	glow.follow = target
	glow.follow_offset = cfg["offset"]
	glow.face_source = face_from
	glow.texture = _light_texture()
	glow.color = cfg["colour"]
	glow._base_energy = float(cfg["energy"])
	glow.energy = glow._base_energy
	# The light reaches `radius` world px in every direction from where it sits.
	glow.texture_scale = 2.0 * float(cfg["radius"]) / float(LIGHT_TEXTURE_SIZE)
	# Its own transform, never the host's: a caught Pokémon hangs at half scale and a
	# quarter turn, and a light inheriting that would be half the size it should be.
	glow.top_level = true
	host.add_child(glow)
	glow.global_position = glow._follow_point() + glow._offset_now()
	# Somewhere in the middle of the breath, so two of them side by side are not in step.
	glow._pulse = randf() * PULSE_PERIOD
	return glow


func _process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		queue_free()
		return
	global_position = _follow_point() + _offset_now()
	visible = follow.visible
	# A slow breath between full and PULSE_DEPTH below it. cos() starts at the top, so a
	# light comes on at its brightest and eases down rather than fading up from nothing.
	_pulse = fmod(_pulse + delta, PULSE_PERIOD)
	var swing := 0.5 * (1.0 + cos(TAU * _pulse / PULSE_PERIOD))
	energy = _base_energy * (1.0 - PULSE_DEPTH + PULSE_DEPTH * swing)


## Where on the host the light actually sits: its origin, plus a Sprite2D's own `offset`
## put through that sprite's rotation and scale.
##
## The offset matters because a Sprite2D's offset moves what is DRAWN without moving the
## node -- which is exactly how the caught Pokémon's hop back into the sea is animated, so
## a light tracking global_position alone stayed on the ground while the Pokémon jumped.
## Every overworld Pokémon leaves its sprite offset at zero, so this changes nothing for
## them.
func _follow_point() -> Vector2:
	if follow == null or not is_instance_valid(follow):
		return global_position
	var sprite := follow as Sprite2D
	if sprite == null or sprite.offset == Vector2.ZERO:
		return follow.global_position
	return follow.global_position + follow.get_global_transform().basis_xform(sprite.offset)


## Where the light sits this frame. A tail light hangs behind the Pokémon, so its
## sideways part follows the facing: behind a right-facing one is to its left. Facing up
## or down there is no side to be on, so it just hangs low.
func _offset_now() -> Vector2:
	if face_source == null or not is_instance_valid(face_source):
		return follow_offset
	match face_source.facing:
		"right":
			return Vector2(-follow_offset.x, follow_offset.y)
		"left":
			return follow_offset
	return Vector2(0.0, follow_offset.y)


## A radial white-to-transparent gradient, built once and shared by every glow. The core
## is held reasonably solid part of the way out rather than falling off immediately, which
## is what makes a light read as a lit BODY rather than a haze around one -- but not so
## solid that it washes the Pokémon out.
static func _light_texture() -> GradientTexture2D:
	if _light_texture_cache != null:
		return _light_texture_cache
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.8),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = LIGHT_TEXTURE_SIZE
	texture.height = LIGHT_TEXTURE_SIZE
	_light_texture_cache = texture
	return texture
