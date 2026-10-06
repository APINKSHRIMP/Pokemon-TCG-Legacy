class_name FishTeleport
extends Node2D

## A caught Pokémon being sent off to its fish tank, Poké Ball style. Three beats:
##
##   1. WHITEN   the Pokémon floods white from its own colours, its edge picking up a
##               blue gradient (blue at the outline, white EDGE_DEPTH texels in) and a
##               soft blue glow just outside the silhouette.
##   2. HOLD     a moment lit up like that.
##   3. DISSOLVE the silhouette comes apart one texel at a time, TOP ROW FIRST, each
##               texel rising away as a white/blue speck -- data being beamed up -- under
##               a faint column of light.
##
## Everything is drawn by hand from the sprite's own pixels (the same approach PixelBurst
## and DripLayer take), so beat 1 and beat 3 are the same texels and the hand-over is
## seamless: the real sprite is hidden the frame this starts.
##
##   var fx := FishTeleport.fire(parent, sprite, z)
##   fx.finished.connect(...)
##
## The sprite must be an upright Sprite2D (rotation 0) showing an AtlasTexture frame or a
## plain texture, with a uniform scale. It is hidden, never freed -- that is the caller's.

signal finished

# -----------------------------------------------------------------------------
# TWEAKABLE -- times are seconds, distances WORLD px (screen = world x 2.5)
# -----------------------------------------------------------------------------
const WHITEN_TIME := 0.45
const HOLD_TIME := 0.25
## Seconds from the first texel leaving (top row) to the last one (bottom row).
const DISSOLVE_TIME := 1.1
## Random extra delay per texel on top of its row's turn, so the rows break up raggedly
## rather than as a clean wipe.
const RELEASE_JITTER := 0.25

## Blue at the silhouette's edge, white at the core.
const EDGE_COLOUR := Color(0.30, 0.62, 1.0)
const CORE_COLOUR := Color(1.0, 1.0, 1.0)
## Texels in from the edge before the blue has become white.
const EDGE_DEPTH := 3.0
## Texels the outside glow reaches past the silhouette, and how strong it starts.
const GLOW_WIDTH := 3
const GLOW_ALPHA := 0.55

## Specks once they let go.
const RISE_SPEED_MIN := 25.0
const RISE_SPEED_MAX := 60.0
const RISE_ACCEL := 140.0
const DRIFT := 6.0          ## max sideways speed
const LIFE_MIN := 0.45
const LIFE_MAX := 0.85
## A speck grows from one texel to this many world px as it rises, so it reads as the
## same chunky grain as PixelBurst rather than as dust.
const SPECK_SIZE := 1.0
## How far a speck's colour slides from its own white/blue to EDGE_COLOUR over its life.
const SPECK_BLUE_SHIFT := 0.7

## The light column over the Pokémon while it dissolves. Peak alpha and height in world px.
const BEAM_ALPHA := 0.22
const BEAM_HEIGHT := 90.0

## Big sprites are sampled in CHUNKS of texels so a Wailord does not become 20,000 specks.
const MAX_SPECKS := 4000

# -----------------------------------------------------------------------------

var _texel: float = 0.5        ## world px per drawn chunk
var _size: Vector2 = Vector2.ZERO  ## the frame in world px
var _t: float = 0.0

# Solid texels (become specks).
var _pos := PackedVector2Array()
var _orig := PackedColorArray()
var _lit := PackedColorArray()
var _release := PackedFloat32Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
# Glow texels (just outside the silhouette; fade, never fly).
var _glow_pos := PackedVector2Array()
var _glow_alpha := PackedFloat32Array()

var _done: bool = false


## Builds the effect over `sprite`, hides the sprite and returns the effect. Returns null
## (and leaves the sprite alone) if its pixels cannot be read.
static func fire(parent: Node, sprite: Sprite2D, z: int) -> FishTeleport:
	if parent == null or sprite == null or sprite.texture == null:
		return null
	var fx := FishTeleport.new()
	if not fx._build(sprite):
		fx.free()
		return null
	fx.z_as_relative = false
	fx.z_index = z
	parent.add_child(fx)
	sprite.visible = false
	return fx


func _build(sprite: Sprite2D) -> bool:
	var tex: Texture2D = sprite.texture
	var region := Rect2i(Vector2i.ZERO, Vector2i(tex.get_size()))
	var source: Texture2D = tex
	if tex is AtlasTexture:
		source = (tex as AtlasTexture).atlas
		region = Rect2i((tex as AtlasTexture).region)
	if source == null:
		return false
	var img := source.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		return false

	# Chunk size: 1 texel unless the frame has more solid pixels than MAX_SPECKS allows.
	var solid := 0
	for y in region.size.y:
		for x in region.size.x:
			if img.get_pixel(region.position.x + x, region.position.y + y).a > 0.1:
				solid += 1
	if solid == 0:
		return false
	var chunk := maxi(1, int(ceil(sqrt(float(solid) / float(MAX_SPECKS)))))

	# Down-sampled grid, padded by GLOW_WIDTH all round for the outside glow.
	var gw := int(ceil(float(region.size.x) / chunk))
	var gh := int(ceil(float(region.size.y) / chunk))
	var pad := GLOW_WIDTH
	var w := gw + pad * 2
	var h := gh + pad * 2
	var colours: Array = []
	colours.resize(w * h)
	var inside := PackedFloat32Array()
	var outside := PackedFloat32Array()
	inside.resize(w * h)
	outside.resize(w * h)
	for gy in h:
		for gx in w:
			var c := _sample(img, region, gx - pad, gy - pad, chunk)
			colours[gy * w + gx] = c
			var on := c.a > 0.1
			inside[gy * w + gx] = 1.0e6 if on else 0.0
			outside[gy * w + gx] = 0.0 if on else 1.0e6
	_chamfer(inside, w, h)
	_chamfer(outside, w, h)

	var scale_x := absf(sprite.scale.x)
	_texel = scale_x * chunk
	_size = Vector2(region.size) * scale_x
	# Top-left of the drawn frame in world space. Sprite2D draws `centered` frames about
	# their middle, then shifts them by `offset`, all in texture px.
	var top_left := sprite.offset
	if sprite.centered:
		top_left -= Vector2(region.size) * 0.5
	global_position = sprite.global_position + top_left * scale_x

	for gy in h:
		for gx in w:
			var i := gy * w + gx
			var local := Vector2(gx - pad, gy - pad) * _texel
			var c: Color = colours[i]
			if c.a > 0.1:
				var k := clampf((inside[i] - 1.0) / EDGE_DEPTH, 0.0, 1.0)
				var lit := EDGE_COLOUR.lerp(CORE_COLOUR, k)
				_pos.append(local)
				_orig.append(Color(c.r, c.g, c.b, 1.0))
				_lit.append(lit)
				# Top row first; gy runs from the top of the frame.
				var row := float(gy - pad) / maxf(1.0, float(gh - 1))
				_release.append(row * DISSOLVE_TIME + randf() * RELEASE_JITTER)
				_vel.append(Vector2(randf_range(-DRIFT, DRIFT),
						-randf_range(RISE_SPEED_MIN, RISE_SPEED_MAX)))
				_life.append(randf_range(LIFE_MIN, LIFE_MAX))
			elif outside[i] <= float(GLOW_WIDTH):
				_glow_pos.append(local)
				_glow_alpha.append(GLOW_ALPHA * (1.0 - (outside[i] - 1.0) / float(GLOW_WIDTH)))
	return true


## One chunk's colour: the first solid texel in it, or transparent. A chunk of 1 is just
## that texel. Coordinates outside the region read as transparent (the glow padding).
static func _sample(img: Image, region: Rect2i, gx: int, gy: int, chunk: int) -> Color:
	if gx < 0 or gy < 0:
		return Color(0, 0, 0, 0)
	for dy in chunk:
		for dx in chunk:
			var x := gx * chunk + dx
			var y := gy * chunk + dy
			if x >= region.size.x or y >= region.size.y:
				continue
			var c := img.get_pixel(region.position.x + x, region.position.y + y)
			if c.a > 0.1:
				return c
	return Color(0, 0, 0, 0)


## Two-pass chamfer distance transform, in place: every cell ends up holding its distance
## (1 per step, 1.414 diagonally) to the nearest cell that started at 0.
static func _chamfer(d: PackedFloat32Array, w: int, h: int) -> void:
	const DIAG := 1.4142
	for y in h:
		for x in w:
			var i := y * w + x
			var v := d[i]
			if x > 0: v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - w] + 1.0)
				if x > 0: v = minf(v, d[i - w - 1] + DIAG)
				if x < w - 1: v = minf(v, d[i - w + 1] + DIAG)
			d[i] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var v := d[i]
			if x < w - 1: v = minf(v, d[i + 1] + 1.0)
			if y < h - 1:
				v = minf(v, d[i + w] + 1.0)
				if x < w - 1: v = minf(v, d[i + w + 1] + DIAG)
				if x > 0: v = minf(v, d[i + w - 1] + DIAG)
			d[i] = v


func _process(delta: float) -> void:
	_t += delta
	var dissolve_t := _t - WHITEN_TIME - HOLD_TIME
	if dissolve_t > 0.0:
		for i in _pos.size():
			var age := dissolve_t - _release[i]
			if age <= 0.0:
				continue
			var v := _vel[i]
			v.y -= RISE_ACCEL * delta
			_vel[i] = v
			_pos[i] += v * delta
	if not _done and dissolve_t > DISSOLVE_TIME + RELEASE_JITTER + LIFE_MAX:
		_done = true
		finished.emit()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var whiten := clampf(_t / WHITEN_TIME, 0.0, 1.0)
	whiten = whiten * whiten * (3.0 - 2.0 * whiten)  # smoothstep
	var dissolve_t := _t - WHITEN_TIME - HOLD_TIME
	var progress := clampf(dissolve_t / DISSOLVE_TIME, 0.0, 1.0)

	# The light column, rising out of the Pokémon while it goes.
	if dissolve_t > 0.0:
		var beam := BEAM_ALPHA * sin(PI * clampf(dissolve_t / (DISSOLVE_TIME + LIFE_MAX), 0.0, 1.0))
		var steps := 12
		for s in steps:
			var f := float(s) / float(steps)
			var c := EDGE_COLOUR.lerp(CORE_COLOUR, 0.5)
			c.a = beam * (1.0 - f)
			var y := _size.y - (_size.y + BEAM_HEIGHT) * (f + 1.0 / steps)
			draw_rect(Rect2(Vector2(0.0, y), Vector2(_size.x, (_size.y + BEAM_HEIGHT) / steps)), c)

	# Outside glow: up with the whiten, away with the dissolve.
	var glow_k := whiten * (1.0 - progress)
	if glow_k > 0.0:
		var tex := Vector2(_texel, _texel)
		for i in _glow_pos.size():
			var c := EDGE_COLOUR
			c.a = _glow_alpha[i] * glow_k
			draw_rect(Rect2(_glow_pos[i], tex), c)

	for i in _pos.size():
		var age := dissolve_t - _release[i]
		if age <= 0.0:
			draw_rect(Rect2(_pos[i], Vector2(_texel, _texel)), _orig[i].lerp(_lit[i], whiten))
			continue
		var f := clampf(age / _life[i], 0.0, 1.0)
		if f >= 1.0:
			continue
		var c := _lit[i].lerp(EDGE_COLOUR, f * SPECK_BLUE_SHIFT)
		c.a = 1.0 - f * f
		var s := lerpf(_texel, maxf(_texel, SPECK_SIZE), minf(1.0, f * 3.0))
		draw_rect(Rect2(_pos[i], Vector2(s, s)), c)
