class_name MedalCoin3D
extends Control

# ============================================================
# MEDAL COIN 3D - a medal drawn as a real spinning coin (the reveal and the medal screen's preview use this node).
# begin() starts the show: the coin grows from nothing (or from `grow_from` of full size) while spinning fast about
# its vertical axis; the spin bleeds off to a slow turn on the spot. It is a disc: a stack of flat-colour rim
# slices between the two faces, the visible face shaded by how face-on it is. Never stack slices of the FACE art -
# its lit-rim pixels flash white edge-on (the rim uses a flat silhouette, see _silhouette).
# ============================================================

## TWEAKABLES (the gift reveal's feel - the reveal's size is in Medal_Reveal.gd)
const GROW_TIME := 0.85             # seconds to full size (eased out)
const SPIN_START := 28.0            # rad/s at the start (about 4.5 turns a second)
const SPIN_TAU := 0.75              # seconds for the fast spin to bleed off (settles in half the time it used to)
const SPIN_REST := 0.9              # rad/s of the slow spin it settles into
const THICKNESS := 0.075            # rim thickness as a share of the diameter
const SLICES := 14                  # rim slices
const LOCKED_FACE := Color(0.13, 0.14, 0.18)
const LOCKED_RIM := Color(0.07, 0.075, 0.1)

## Full-size diameter in px; the control draws centred in its own rect, so size it a little bigger than this.
var full_diameter := 200.0
var grow_from := 0.0               # share of full size it starts at (0 = from nothing)
var time_scale := 1.0              # >1 plays the intro faster
var t := 0.0
var locked := false
## True = just a coin turning slowly in place (the medal screen's preview): no spin-in, full size at once, and the
## turn CARRIES OVER when the medal changes, so hovering the next medal never snaps back to a start angle.
var continuous := false

var _tex: Texture2D
var _rim_tex: Texture2D
var _rim := Color(0.5, 0.5, 0.5)
var _diameter := 1.0
var _angle := 0.0


func begin(art: Texture2D, metal: String, is_locked: bool) -> void:
	_tex = art
	locked = is_locked
	_rim = LOCKED_RIM if is_locked else MedalSparkle.ramp(metal)[2]
	_rim_tex = _silhouette(art, _rim)
	if not continuous:
		t = 0.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_step(0.0)


## The art in ONE flat colour (alpha kept).
func _silhouette(src: Texture2D, colour: Color) -> Texture2D:
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(colour.r, colour.g, colour.b, a))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _tex == null or not is_visible_in_tree():
		return
	_step(delta * time_scale)


func _step(dt: float) -> void:
	if continuous:
		_diameter = full_diameter
		_angle = fmod(_angle + SPIN_REST * dt, TAU)
		queue_redraw()
		return
	t += dt
	var g := clampf(t / GROW_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - g, 3.0)
	_diameter = full_diameter * lerpf(grow_from, 1.0, eased)
	_angle = SPIN_REST * t + (SPIN_START - SPIN_REST) * SPIN_TAU * (1.0 - exp(-t / SPIN_TAU))
	queue_redraw()


func _draw() -> void:
	if _tex == null or _diameter < 2.0:
		return
	var centre := size * 0.5
	var c := cos(_angle)
	var s := sin(_angle)
	var w := maxf(_diameter * absf(c), 1.0)
	var h := _diameter
	var thick := _diameter * THICKNESS
	var visible_dx := thick * 0.5 * s * (1.0 if c >= 0.0 else -1.0)
	var shade := 0.5 + 0.5 * pow(absf(c), 0.6)
	for i in range(SLICES):
		var f := float(i) / float(SLICES - 1)
		var dx := lerpf(-visible_dx, visible_dx, f)
		var col := _rim.lerp(_rim.darkened(0.35), 1.0 - f) * Color(shade, shade, shade, 1.0)
		col.a = 1.0
		draw_texture_rect(_rim_tex if _rim_tex != null else _tex,
				Rect2(centre.x - w * 0.5 + dx, centre.y - h * 0.5, w, h), false, col)
	var face_rect := Rect2(centre.x - w * 0.5 + visible_dx, centre.y - h * 0.5, w, h)
	if locked:
		var dark := LOCKED_FACE * Color(shade, shade, shade, 1.0)
		dark.a = 1.0
		draw_texture_rect(_rim_tex if _rim_tex != null else _tex, face_rect, false, dark)
		return
	draw_texture_rect(_tex, face_rect, false, Color(shade, shade, shade, 1.0))
