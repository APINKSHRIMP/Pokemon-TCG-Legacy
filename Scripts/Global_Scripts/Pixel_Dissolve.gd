class_name PixelDissolve
extends RefCounted

# ============================================================
# PIXEL DISSOLVE — the overworld breaks into pixels on the way into a match
# ============================================================
#   await PixelDissolve.out_to_scene(MATCH_INTRO_SCENE)
#       reads the live screen (no snapshot -- a GPU read-back stalled a frame and showed as
#       a pause), coarsens it into big pixels, pops them out (each swells a touch then shrinks to nothing) into black, then changes scene. Every battle start in MapManager goes through this.
#   var mask := PixelDissolve.make_mask(parent)  +  PixelDissolve.play_in(mask)
#       a black sheet whose blocks pop away in the same way -- the match intro
#       uses it to bring its background in.
# The look itself is Scripts/Shaders/Pixel_Dissolve.gdshader.

const SHADER := preload("res://Scripts/Shaders/Pixel_Dissolve.gdshader")

## TWEAKABLE -- seconds, before the Animation speed preset scales them.
const OUT_TIME := 0.55
const IN_TIME := 0.235   # the match intro's background; halved 2026-10-21 (was 0.47)
## Size of the pixels the screen breaks into (screen px).
const CELL_PX := 32.0


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _material(use_screen: bool, pixelate_share: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var size: Vector2 = _tree().root.get_visible_rect().size
	mat.set_shader_parameter("screen_px", size)
	mat.set_shader_parameter("max_cell", CELL_PX)
	mat.set_shader_parameter("pixelate_share", pixelate_share)
	mat.set_shader_parameter("use_screen", use_screen)
	mat.set_shader_parameter("progress", 0.0)
	return mat


## The overworld -> match exit. Returns once the new scene has been asked for.
static func out_to_scene(scene_path: String) -> void:
	var tree := _tree()
	var time: float = GameState.transition_time(OUT_TIME)
	var host := tree.current_scene
	if time <= 0.0 or host == null:
		SceneCache.change_scene(scene_path)
		return

	# One opaque rect over everything that draws the screen beneath it through the shader
	# (hint_screen_texture), so it starts the instant it is added -- no waiting frames.
	var layer := CanvasLayer.new()
	layer.layer = 120
	host.add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing can be clicked mid-transition
	rect.material = _material(true, 0.35)
	layer.add_child(rect)

	var tween := host.create_tween()
	tween.tween_property(rect.material, "shader_parameter/progress", 1.0, time) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	SceneCache.change_scene(scene_path)


## A full-screen black sheet that will dissolve away (play_in). Added to `parent`;
## the caller puts it in the draw order it needs.
static func make_mask(parent: Node) -> ColorRect:
	var mask := ColorRect.new()
	mask.color = Color.BLACK
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.material = _material(false, 0.0)
	parent.add_child(mask)
	return mask


## Dissolves a make_mask() sheet away. Returns when it is gone (and frees it).
static func play_in(mask: ColorRect) -> void:
	var time: float = GameState.transition_time(IN_TIME)
	if time > 0.0:
		var tween := mask.create_tween()
		tween.tween_property(mask.material, "shader_parameter/progress", 1.0, time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	if is_instance_valid(mask):
		mask.queue_free()
