class_name MatchBackdrop
extends RefCounted

# ============================================================
# MATCH BACKDROP - the blurred overworld behind every match screen
# ============================================================
# When a battle is accepted, MatchTransition takes ONE screenshot of the overworld
# (capture()). Everything from then until the player is back on the map draws
# that screenshot through Match_Zoom_Blur.gdshader at progress 1.0 - zoomed in on
# the player, soft and dark - with the theme's chevron stripes over it:
#
#     the transition overlay  ->  the match board  ->  best-of-three  ->  the outro
#
# Every one of those screens builds the SAME two layers with the SAME numbers, so
# when one scene is swapped for the next under an identical picture, nothing on
# screen changes. The stripes line up across scenes because the field shader
# scrolls by the global shader TIME, not a per-node clock.
#
# With no screenshot (a match started some other way - the autotester, a debug
# launch) add_field() falls back to the theme's normal opaque field.
# ============================================================

const SHADER := preload("res://Scripts/Shaders/Match_Zoom_Blur.gdshader")
const LIVE_SHADER := preload("res://Scripts/Shaders/Match_Zoom_Blur_Live.gdshader")

# -- TWEAKABLE ------------------------------------------------
## How far in the zoom ends (1.0 = no zoom).
const ZOOM_MAX     : float = 1.7
## How long the radial "motion" streaks are, as a share of the way to the player.
const STREAK       : float = 0.35
## Mip level of the final soft blur. Higher = softer. 4.5 is roughly a 20px blur.
const SOFT_LOD     : float = 4.5
## Brightness left at the end (1.0 = not darkened at all).
const DARKEN       : float = 0.42
## Share of the colour taken out at the end.
const DESAT        : float = 0.15
## The theme's chevron alpha is multiplied by this over the backdrop.
const STRIPE_BOOST : float = 4.4    # 2026-11-05: 4.0 -> 4.4 (10% less transparent)
## The theme chevron width is multiplied by this over the backdrop (10% wider).
const STRIPE_WIDTH_MULT : float = 1.1

## The frozen overworld frame, with mipmaps (the soft blur reads them).
static var source: Texture2D = null
## Where the player stood on that frame, in UV (0..1) - the zoom heads here.
static var focus: Vector2 = Vector2(0.5, 0.5)


static func has() -> bool:
	return source != null


## Reads the CURRENT frame of `viewport` back from the GPU. The caller awaits
## RenderingServer.frame_post_draw first so the frame is complete (and so whatever
## it just hid - the message box - is gone from it). `focus_px` is the player's
## position in canvas pixels.
static func capture(viewport: Viewport, focus_px: Vector2) -> void:
	var img: Image = viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	source = ImageTexture.create_from_image(img)
	var vis: Vector2 = viewport.get_visible_rect().size
	if vis.x > 0.0 and vis.y > 0.0:
		focus = Vector2(clampf(focus_px.x / vis.x, 0.0, 1.0), clampf(focus_px.y / vis.y, 0.0, 1.0))
	else:
		focus = Vector2(0.5, 0.5)


## A full-screen rect drawing the screenshot at `progress` (0 = the overworld as it
## was, 1 = the finished backdrop). Tween "material:shader_parameter/progress".
static func make_rect(progress: float = 1.0) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "match_backdrop"
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("source", source)
	_set_blur_params(mat, progress)
	rect.material = mat
	return rect


static func _set_blur_params(mat: ShaderMaterial, progress: float) -> void:
	mat.set_shader_parameter("focus", focus)
	mat.set_shader_parameter("progress", progress)
	mat.set_shader_parameter("zoom_max", ZOOM_MAX)
	mat.set_shader_parameter("streak", STREAK)
	mat.set_shader_parameter("soft_lod", SOFT_LOD)
	mat.set_shader_parameter("darken", DARKEN)
	mat.set_shader_parameter("desat", DESAT)


## Turns a UIKit field into stripes only, over a transparent ground.
static func make_stripes_only(field: ColorRect) -> void:
	if field == null or not (field.material is ShaderMaterial):
		return
	_paint_stripes(field.material as ShaderMaterial)
	# A theme change re-runs the field's painter, which would put the theme's own
	# width and alpha back - so the painter is wrapped to re-apply the overrides.
	if "painter" in field:
		field.set("painter", func(mat: ShaderMaterial) -> void:
			UIKit.paint_field(mat)
			_paint_stripes(mat))
	# Scroll from the very first frame (not only once the rect has entered the tree).
	if field.has_method("refresh_motion"):
		field.call("refresh_motion")


static func _paint_stripes(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("stripes_only", true)
	mat.set_shader_parameter("stripe_boost", STRIPE_BOOST)
	mat.set_shader_parameter("stripe_width", UITheme.CHEVRON_FIELD_STRIPE * STRIPE_WIDTH_MULT)


## The LIVE screen underneath through the same zoom blur - the way back to the
## overworld blurs the real map with it so the old screenshot can cross-fade in.
static func make_live_rect(progress: float = 1.0) -> ColorRect:
	var rect := make_rect(progress)
	rect.name = "match_backdrop_live"
	(rect.material as ShaderMaterial).shader = LIVE_SHADER
	_set_blur_params(rect.material as ShaderMaterial, progress)
	return rect


## The match-screen stand-in for UIKit.add_field(): the backdrop at the very back,
## the stripes over it. Returns the stripes rect (the node add_field would have
## returned). Falls back to the plain theme field when there is no screenshot.
static func add_field(parent: Control) -> ColorRect:
	var stripes: ColorRect = UIKit.add_field(parent)
	if not has():
		return stripes
	make_stripes_only(stripes)
	var bd := make_rect(1.0)
	bd.z_index = stripes.z_index
	parent.add_child(bd)
	parent.move_child(bd, 0)   # behind the stripes (same z_index, so order decides)
	return stripes
