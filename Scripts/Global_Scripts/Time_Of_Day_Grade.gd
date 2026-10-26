extends RefCounted

## TIME-OF-DAY COLOUR GRADE
## Outdoor maps are drawn once, in Afternoon colours. Morning / Evening / Night / Bedtime are a colour
## grade (World_Time_Grade.gdshader) worn by every world CanvasItem, driven by four shader
## globals this script writes. BaseMapScene wires it up: maps that return true from
## uses_time_of_day() are graded, everything else (interiors, menus, battles) is left alone.
##
## Lights: a sheet "X.png" may have "X_Open_Lights.png" beside it -- same
## size and layout, transparent except lit windows / lamps. Every TileMapLayer drawing from
## that sheet shows those pixels ungraded, at LIGHTS[time] strength. At Bedtime the shops
## are shut, so "X_Closed_Lights.png" is drawn instead (same layout, fewer lit pixels:
## street lights on, shop windows off); a sheet without one keeps its open lights.
##
## Opting a node out: add it to the "no_time_grade" group BEFORE it enters the tree (talk
## bubbles and SpeechEmotes do). Nodes that already have a material are skipped too.
##
## Used via preload (no class_name):
##   const TimeOfDayGrade = preload("res://Scripts/Global_Scripts/Time_Of_Day_Grade.gd")

const WORLD_SHADER := preload("res://Scripts/Shaders/World_Time_Grade.gdshader")
const NO_GRADE_GROUP := "no_time_grade"

## TWEAKABLE -- the grade per time of day. Each row is the weights of input (r, g, b) in
## that output channel, then an offset; "curve" is a luma-squared term per output channel
## (bends highlights). Fitted from the hand-made Celeste Harbour sheets (average error
## ~2-3 / 255). Afternoon is the identity.
const GRADES := {
	"Morning": {
		"red":   Vector4(0.859, 0.001, 0.001, 0.022),
		"green": Vector4(0.002, 0.931, 0.003, 0.023),
		"blue":  Vector4(0.075, 0.165, 0.980, 0.018),
		"curve": Vector3(0.008, 0.002, -0.185),
	},
	"Afternoon": {
		"red":   Vector4(1.0, 0.0, 0.0, 0.0),
		"green": Vector4(0.0, 1.0, 0.0, 0.0),
		"blue":  Vector4(0.0, 0.0, 1.0, 0.0),
		"curve": Vector3(0.0, 0.0, 0.0),
	},
	"Evening": {
		# ISSUE #386: warmer - fitted red row x1.10 (was x1.05) and blue row x0.95, so the
		# dusk leans red/orange. Brightness is back to 1.0 in BRIGHTNESS below.
		"red":   Vector4(0.844, 0.530, 0.156, 0.026),
		"green": Vector4(0.005, 0.759, 0.000, 0.051),
		"blue":  Vector4(-0.025, -0.007, 0.701, 0.053),
		"curve": Vector3(-0.575, 0.072, 0.122),
	},
	"Night": {
		# ISSUE #387: a deeper, bluer night - fitted red row x0.90 and green row x0.94, blue
		# row untouched, so everything darkens except the blue channel.
		"red":   Vector4(0.636, -0.140, -0.016, -0.086),
		"green": Vector4(-0.128, 0.592, -0.062, -0.082),
		"blue":  Vector4(0.016, 0.290, 0.554, -0.101),
		"curve": Vector3(0.277, 0.342, 0.225),
	},
	"Bedtime": {
		# The late hours after Night: Night's grade with the blue row x1.21 (x1.10, then
		# another x1.10); the extra darkness is BRIGHTNESS below.
		"red":   Vector4(0.636, -0.140, -0.016, -0.086),
		"green": Vector4(-0.128, 0.592, -0.062, -0.082),
		"blue":  Vector4(0.020, 0.351, 0.670, -0.101),
		"curve": Vector3(0.277, 0.342, 0.225),
	},
}

## TWEAKABLE -- how far each grade is pushed from Afternoon. 1.0 = as fitted; 1.4 = 40%
## further (Morning, so it reads clearly different from Afternoon); 0.5 = halfway back.
const STRENGTH := {"Morning": 1.4, "Afternoon": 1.0, "Evening": 1.0, "Night": 1.0, "Bedtime": 1.0}

## TWEAKABLE -- overall brightness multiplier on top of the grade (0.85 = 15% darker).
## ISSUE #386: Evening back to 1.0 (it had been darkened to 0.85).
## Bedtime is 25% darker than Night (0.85 x 0.75 = 0.64), then another 20% (x 0.8).
## ISSUE #506: Night 10% lighter (0.85 x 1.1 = 0.935), Bedtime 10% darker (0.51 x 0.9 = 0.459).
const BRIGHTNESS := {"Morning": 1.0, "Afternoon": 1.0, "Evening": 1.0, "Night": 0.935, "Bedtime": 0.459}

## TWEAKABLE -- how strongly the lights overlays show (0 = off, 1 = full). Above 1 the lit
## pixels are fully shown AND brightened by that much (Bedtime 1.1 = 10% brighter).
const LIGHTS := {"Morning": 0.0, "Afternoon": 0.0, "Evening": 0.5, "Night": 1.0, "Bedtime": 1.1}

## Which lights sheet each time draws: "_Open_Lights.png" normally, "_Closed_Lights.png"
## once the shops have shut. A time not listed here uses the open sheet.
const OPEN_LIGHTS_SUFFIX := "_Open_Lights.png"
const CLOSED_LIGHTS_SUFFIX := "_Closed_Lights.png"
const CLOSED_LIGHTS_TIMES := ["Bedtime"]

## TWEAKABLE -- atlas cell size in px, used to undo Godot's tile-atlas padding.
const TILE_PX := 16.0

## ---- PointLight2D styling (style_lights) ------------------------------------------
## TWEAKABLE -- light strength per time. Lights are only switched on (by each map's
## set_time_of_day) at Evening, Night and Bedtime; Evening is the dusk "just came on" level,
## Bedtime 10% up on Night.
const LIGHT_ENERGY := {"Morning": 0.0, "Afternoon": 0.0, "Evening": 0.45, "Night": 1.0, "Bedtime": 1.1}

## TWEAKABLE -- the round street / garden / harbour / prom glows (additive, radial
## gradient) are redrawn as a warm pool: a bright core easing smoothly out to nothing,
## instead of a hard-edged saturated-orange blob that went pink over the
## blue night. Window beams, the lighthouse and MIX-mode lamps keep their own look.
const POOL_COLOUR := Color(1.0, 0.88, 0.55)
## Falloff curve: points along the radius (fraction of the old glow's radius) and the
## brightness at each, blended smoothly between. Eases out like a real lamp: bright
## centre, long soft tail, no visible edge.
const POOL_STOPS := [0.0, 0.2, 0.45, 0.7, 1.0]
const POOL_ALPHAS := [0.95, 0.65, 0.35, 0.12, 0.0]
## Converts the old per-light brightness (colour x alpha x energy) to the new energy, so
## lights authored brighter or dimmer keep their relative strength.
const POOL_ENERGY_SCALE := 0.55
## Pool radius relative to the light as placed in the scene (1.0 = the authored size).
const POOL_SIZE := 1.4
## Resolution of the pool texture (higher = smoother gradient).
const POOL_TEXTURE_PX := 256

static var _pool_textures := {}   # old glow texture -> its pool replacement

static var _world_material: ShaderMaterial = null
static var _sheet_materials := {}   # sheet path + lights suffix -> ShaderMaterial (with or without lights)
static var _lights_suffix := OPEN_LIGHTS_SUFFIX   # set by apply_time, read when a tilemap is graded


## Writes the four globals. Unknown / empty time (interiors) = identity, lights off.
static func apply_time(time: String) -> void:
	print("ISSUE #386 FIX ACTIVE: grade '", time, "' brightness ", BRIGHTNESS.get(time, 1.0))
	print("ISSUE #387 FIX ACTIVE: night red row ", GRADES["Night"]["red"])
	print("ISSUE #506 FIX ACTIVE: grade '", time, "' brightness ", BRIGHTNESS.get(time, 1.0))
	var g: Dictionary = GRADES.get(time, GRADES["Afternoon"])
	var id: Dictionary = GRADES["Afternoon"]
	var k: float = STRENGTH.get(time, 1.0)
	var b: float = BRIGHTNESS.get(time, 1.0)
	# Push away from identity by STRENGTH, then scale the whole output by BRIGHTNESS.
	var rows := {}
	for key in ["red", "green", "blue"]:
		rows[key] = (id[key] + (g[key] - id[key]) * k) * b
	var c: Vector3 = g["curve"] * k * b
	_lights_suffix = CLOSED_LIGHTS_SUFFIX if CLOSED_LIGHTS_TIMES.has(time) else OPEN_LIGHTS_SUFFIX
	RenderingServer.global_shader_parameter_set("tod_red", rows["red"])
	RenderingServer.global_shader_parameter_set("tod_green", rows["green"])
	RenderingServer.global_shader_parameter_set("tod_blue", rows["blue"])
	RenderingServer.global_shader_parameter_set("tod_curve", Vector4(c.x, c.y, c.z, LIGHTS.get(time, 0.0)))


## Grades `root` and everything under it.
static func grade_tree(root: Node, map_root: Node) -> void:
	grade_node(root, map_root)
	for child in root.get_children():
		grade_tree(child, map_root)


## Gives one node the grade material, unless it is UI (under a CanvasLayer inside the map),
## opted out, a light, or already has a material of its own.
static func grade_node(node: Node, map_root: Node) -> void:
	if not (node is CanvasItem) or node is Light2D or node is LightOccluder2D:
		return
	var item := node as CanvasItem
	if item.material != null:
		return
	# "Use Parent Material" is ticked on many TileMapLayers under the empty TileMap group
	# nodes. Only honour it when the parent really has a shader of its own to share.
	if item.use_parent_material:
		var parent := item.get_parent() as CanvasItem
		if parent != null and parent.material != null and not _is_grade_material(parent.material):
			return
	var n: Node = node
	while n != null and n != map_root:
		if n is CanvasLayer or n.is_in_group(NO_GRADE_GROUP):
			return
		n = n.get_parent()
	item.use_parent_material = false
	if node is TileMapLayer:
		item.material = _material_for_tilemap(node as TileMapLayer)
	else:
		item.material = _shared_world_material()


static func _is_grade_material(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader == WORLD_SHADER


static func _shared_world_material() -> ShaderMaterial:
	if _world_material == null:
		_world_material = ShaderMaterial.new()
		_world_material.shader = WORLD_SHADER
	return _world_material


## One material per sheet (and lights sheet) so its lights overlay can ride along; sheets
## without one share the plain world material. Closed lights fall back to the open sheet.
static func _material_for_tilemap(layer: TileMapLayer) -> ShaderMaterial:
	var sheet := _sheet_path(layer.tile_set)
	if sheet == "":
		return _shared_world_material()
	var cache_key := sheet + "|" + _lights_suffix
	if _sheet_materials.has(cache_key):
		return _sheet_materials[cache_key]
	var mat := _shared_world_material()
	var lights_path := sheet.get_basename() + _lights_suffix
	if not ResourceLoader.exists(lights_path):
		lights_path = sheet.get_basename() + OPEN_LIGHTS_SUFFIX
	if ResourceLoader.exists(lights_path):
		mat = ShaderMaterial.new()
		mat.shader = WORLD_SHADER
		mat.set_shader_parameter("has_lights", true)
		mat.set_shader_parameter("lights_texture", load(lights_path))
		print("ISSUE #391 FIX ACTIVE: lights overlay for ", sheet, " now fades with modulate")
		mat.set_shader_parameter("tile_px", TILE_PX)
		var atlas := _first_atlas(layer.tile_set)
		mat.set_shader_parameter("atlas_padded", atlas != null and atlas.use_texture_padding)
	_sheet_materials[cache_key] = mat
	return mat


static func _first_atlas(tile_set: TileSet) -> TileSetAtlasSource:
	if tile_set == null:
		return null
	for i in tile_set.get_source_count():
		var src := tile_set.get_source(tile_set.get_source_id(i))
		if src is TileSetAtlasSource:
			return src
	return null


static func _sheet_path(tile_set: TileSet) -> String:
	var atlas := _first_atlas(tile_set)
	if atlas == null or atlas.texture == null:
		return ""
	return atlas.texture.resource_path


## Restyles and scales every PointLight2D under `root` for `time`. Called once per map load.
static func style_lights(root: Node, time: String) -> void:
	var k: float = LIGHT_ENERGY.get(time, 0.0)
	for node in root.find_children("*", "PointLight2D", true, false):
		var light := node as PointLight2D
		if _is_round_glow(light):
			var old := light.color
			var strength := maxf(old.r, maxf(old.g, old.b)) * old.a * light.energy
			var old_tex := light.texture as GradientTexture2D
			light.texture = _pool_for(old_tex)
			# A light's size is its texture's pixel size x texture_scale: keep the footprint.
			light.texture_scale *= float(old_tex.width) / float(POOL_TEXTURE_PX) * POOL_SIZE
			light.color = POOL_COLOUR
			light.energy = strength * POOL_ENERGY_SCALE
		light.energy *= k


static func _is_round_glow(light: PointLight2D) -> bool:
	var tex := light.texture as GradientTexture2D
	if tex == null or tex.fill != GradientTexture2D.FILL_RADIAL:
		return false
	return light.blend_mode == Light2D.BLEND_MODE_ADD


## Same size and centre as the glow it replaces, so every hand-placed light keeps its
## footprint; only the falloff and colour change. Shared by every light using that texture.
static func _pool_for(old: GradientTexture2D) -> GradientTexture2D:
	if _pool_textures.has(old):
		return _pool_textures[old]
	# Where the old gradient faded to nothing: its last stop with any alpha left.
	var edge := 1.0
	var g := old.gradient
	if g != null:
		for i in g.get_point_count():
			if g.get_color(i).a <= 0.001:
				edge = g.get_offset(i)
				break
	var pool := Gradient.new()
	pool.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	pool.offsets = PackedFloat32Array(POOL_STOPS.map(func(r): return r * edge))
	pool.colors = PackedColorArray(POOL_ALPHAS.map(func(a): return Color(1, 1, 1, a)))
	var tex := GradientTexture2D.new()
	tex.gradient = pool
	tex.fill = GradientTexture2D.FILL_RADIAL
	# Same radius as the old glow, but centred exactly: the old glows' fill_from was
	# (0.476, 0.482), which sat every pool ~5px up-left of its light's position.
	var radius := old.fill_from.distance_to(old.fill_to)
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5 + radius, 0.5)
	# Fine enough that each texel is ~1 world px at the usual light scale (the old 64px
	# glows stretched each texel to ~3px, which showed as steps in the falloff).
	tex.width = POOL_TEXTURE_PX
	tex.height = POOL_TEXTURE_PX
	_pool_textures[old] = tex
	return tex
