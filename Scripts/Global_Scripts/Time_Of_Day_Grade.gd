extends RefCounted

## TIME-OF-DAY COLOUR GRADE
## Outdoor maps are drawn once, in Afternoon colours. Morning / Evening / Night / Bedtime are a colour
## grade (World_Time_Grade.gdshader) worn by every world CanvasItem, driven by four shader
## globals this script writes. The colour follows the clock's hour, blending gradually between
## each slot's peak (GRADE_PEAK_HOURS). BaseMapScene wires it up: maps that return true from
## uses_time_of_day() get the full grade; interiors (uses_interior_grade()) get the much
## softer INTERIOR_* version; menus and battles are left alone.
##
## Lights: a sheet "X.png" may have "X_Open_Lights.png" beside it -- same
## size and layout, transparent except lit windows / lamps. Every TileMapLayer drawing from
## that sheet shows those pixels ungraded, at lights_strength() strength. At Bedtime the shops
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
		# Cooler: fitted red row x0.96 (was 0.859, 0.001, 0.001, 0.022) and blue row x1.03
		# (was 0.075, 0.165, 0.980, 0.018). The darkening is BRIGHTNESS below.
		"red":   Vector4(0.825, 0.001, 0.001, 0.021),
		"green": Vector4(0.002, 0.931, 0.003, 0.023),
		"blue":  Vector4(0.077, 0.170, 1.009, 0.019),
		"curve": Vector3(0.008, 0.002, -0.185),
	},
	"Afternoon": {
		"red":   Vector4(1.0, 0.0, 0.0, 0.0),
		"green": Vector4(0.0, 1.0, 0.0, 0.0),
		"blue":  Vector4(0.0, 0.0, 1.0, 0.0),
		"curve": Vector3(0.0, 0.0, 0.0),
	},
	"Evening": {
		# ISSUE #299: warmer - fitted red row x1.10 (was x1.05) and blue row x0.95, so the
		# dusk leans red/orange. Brightness is back to 1.0 in BRIGHTNESS below.
		"red":   Vector4(0.844, 0.530, 0.156, 0.026),
		"green": Vector4(0.005, 0.759, 0.000, 0.051),
		"blue":  Vector4(-0.025, -0.007, 0.701, 0.053),
		"curve": Vector3(-0.575, 0.072, 0.122),
	},
	"Night": {
		# ISSUE #300: a deeper, bluer night - fitted red row x0.90 and green row x0.94, blue
		# row untouched, so everything darkens except the blue channel.
		"red":   Vector4(0.636, -0.140, -0.016, -0.086),
		"green": Vector4(-0.128, 0.592, -0.062, -0.082),
		"blue":  Vector4(0.016, 0.290, 0.554, -0.101),
		"curve": Vector3(0.277, 0.342, 0.225),
	},
	"Bedtime": {
		# The late hours after Night: Night's grade with the blue row x1.33 (x1.10 three times);
		# the extra darkness is BRIGHTNESS below.
		"red":   Vector4(0.636, -0.140, -0.016, -0.086),
		"green": Vector4(-0.128, 0.592, -0.062, -0.082),
		"blue":  Vector4(0.022, 0.386, 0.737, -0.101),
		"curve": Vector3(0.277, 0.342, 0.225),
	},
}

## TWEAKABLE -- how far each grade is pushed from Afternoon. 1.0 = as fitted; 1.4 = 40%
## further; 0.5 = halfway back. Morning is 1.6 (was 1.4): peak morning is more tinted now that
## it is only that strong at 8am.
const STRENGTH := {"Morning": 1.6, "Afternoon": 1.0, "Evening": 1.0, "Night": 1.0, "Bedtime": 1.0}

## TWEAKABLE -- overall brightness multiplier on top of the grade (0.85 = 15% darker).
## ISSUE #299: Evening back to 1.0 (it had been darkened to 0.85).
## Bedtime is 25% darker than Night (0.85 x 0.75 = 0.64), then another 20% (x 0.8).
## ISSUE #380: Night 10% lighter (0.85 x 1.1 = 0.935), Bedtime 10% darker (0.51 x 0.9 = 0.459).
## 2026-11-01: Morning 5% darker (0.95); Evening 15% darker (0.85); Night down to the old
## Bedtime level (0.459); Bedtime way darker (0.459 -> 0.25, ~45% down).
## 2026-11-09: peak Morning darker (0.95 -> 0.90), peak Bedtime darker (0.25 -> 0.20).
const BRIGHTNESS := {"Morning": 0.90, "Afternoon": 1.0, "Evening": 0.85, "Night": 0.459, "Bedtime": 0.20}

## TWEAKABLE -- the hour each colour is at its peak, counted from midnight (26 = 2am). The
## colour blends in a straight line between neighbours, and holds at the Bedtime peak after 2am.
const GRADE_PEAK_HOURS := [
	[8.0, "Morning"],
	[14.0, "Afternoon"],
	[18.0, "Evening"],
	[22.0, "Night"],
	[26.0, "Bedtime"],
]

## TWEAKABLE -- lights (sheets and PointLight2Ds, indoors and out) fade up between these hours,
## then stay at full until the bed. 6pm is half strength.
const LIGHTS_START_HOUR := 16.0
const LIGHTS_PEAK_HOUR := 20.0

## Which lights sheet each time draws: "_Open_Lights.png" normally, "_Closed_Lights.png"
## once the shops have shut. A time not listed here uses the open sheet.
const OPEN_LIGHTS_SUFFIX := "_Open_Lights.png"
const CLOSED_LIGHTS_SUFFIX := "_Closed_Lights.png"
const CLOSED_LIGHTS_TIMES := ["Bedtime"]

## ---- INTERIORS ------------------------------------------------------------------
## Indoors wears a much softer version of the same grade: a room has its own lighting, so
## dusk and night only take the edge off it instead of plunging it into blue. Interiors
## use the same lights sheets ("<sheet>_Open_Lights.png", "_Closed_Lights.png" at Bedtime)
## for curtains drawn / windows gone dark / lamps lit, on the same lights_strength() ramp.
##
## TWEAKABLE -- how much of the OUTDOOR colour tint reaches indoors (0 = none, 1 = the full
## outdoor tint). Only the hue shift; the darkening is INTERIOR_BRIGHTNESS below.
## ISSUE #488: tint and darkening both pushed ~25% stronger (tint was 0.25 / 0 / 0.3 / 0.3 / 0.35;
## brightness was 0.97 / 1.0 / 0.92 / 0.82 / 0.72 - the DARKENING, 1 - brightness, is what grew 25%).
## 2026-11-09: tint and darkening both another 20% stronger with the gradual clock (tint was
## 0.3125 / 0 / 0.375 / 0.375 / 0.4375; brightness was 0.9625 / 1.0 / 0.9 / 0.775 / 0.65).
const INTERIOR_TINT := {"Morning": 0.375, "Afternoon": 0.0, "Evening": 0.45, "Night": 0.45, "Bedtime": 0.525}
## TWEAKABLE -- indoor brightness multiplier (outdoors is 0.90 / 1.0 / 0.85 / 0.459 / 0.20).
const INTERIOR_BRIGHTNESS := {"Morning": 0.955, "Afternoon": 1.0, "Evening": 0.88, "Night": 0.73, "Bedtime": 0.58}

## TWEAKABLE -- atlas cell size in px, used to undo Godot's tile-atlas padding.
const TILE_PX := 16.0

## ---- PointLight2D styling (style_lights) ------------------------------------------
## Lights are only switched on (by each map's set_time_of_day) at Evening, Night and Bedtime;
## their strength is lights_strength() below, the same ramp as the lights sheets.

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

const LIGHT_WANTED_META := "tod_light_wanted"
const LIGHT_FULL_ENERGY_META := "tod_light_full_energy"

static var _pool_textures := {}   # old glow texture -> its pool replacement

static var _world_material: ShaderMaterial = null
static var _sheet_materials := {}   # sheet path + lights suffix -> ShaderMaterial (with or without lights)
static var _lights_suffix := OPEN_LIGHTS_SUFFIX   # set by apply_time, read when a tilemap is graded


## Writes the four globals for a moment on the clock: the colour blended between the two
## neighbouring peaks in GRADE_PEAK_HOURS. `slot` only picks the lights sheet (shops shut at
## Bedtime). `interior` uses the softer INTERIOR_* tables. Cheap, and safe to call while a map
## is on screen: nothing needs regrading, every material reads these globals.
static func apply_clock(hours: float, slot: String, interior: bool = false) -> void:
	var low: Array = GRADE_PEAK_HOURS[0]
	var high: Array = GRADE_PEAK_HOURS[GRADE_PEAK_HOURS.size() - 1]
	for i in GRADE_PEAK_HOURS.size() - 1:
		if hours < float(GRADE_PEAK_HOURS[i + 1][0]):
			low = GRADE_PEAK_HOURS[i]
			high = GRADE_PEAK_HOURS[i + 1]
			break
	var t := clampf(inverse_lerp(float(low[0]), float(high[0]), hours), 0.0, 1.0)
	if interior:
		print("ISSUE #488 FIX ACTIVE: interior grade ", GameState.clock_label(hours), " between ", low[1], " and ", high[1])
	var a := _resolved_grade(String(low[1]), interior)
	var b := _resolved_grade(String(high[1]), interior)
	var c: Vector3 = (a["curve"] as Vector3).lerp(b["curve"], t)
	_lights_suffix = CLOSED_LIGHTS_SUFFIX if CLOSED_LIGHTS_TIMES.has(slot) else OPEN_LIGHTS_SUFFIX
	RenderingServer.global_shader_parameter_set("tod_red", (a["red"] as Vector4).lerp(b["red"], t))
	RenderingServer.global_shader_parameter_set("tod_green", (a["green"] as Vector4).lerp(b["green"], t))
	RenderingServer.global_shader_parameter_set("tod_blue", (a["blue"] as Vector4).lerp(b["blue"], t))
	RenderingServer.global_shader_parameter_set("tod_curve", Vector4(c.x, c.y, c.z, lights_strength(hours)))


## No grade at all, lights off: a room that opts out of time of day.
static func apply_identity() -> void:
	var id: Dictionary = GRADES["Afternoon"]
	_lights_suffix = OPEN_LIGHTS_SUFFIX
	RenderingServer.global_shader_parameter_set("tod_red", id["red"])
	RenderingServer.global_shader_parameter_set("tod_green", id["green"])
	RenderingServer.global_shader_parameter_set("tod_blue", id["blue"])
	RenderingServer.global_shader_parameter_set("tod_curve", Vector4(0.0, 0.0, 0.0, 0.0))


## 0 before LIGHTS_START_HOUR, rising to 1 at LIGHTS_PEAK_HOUR, 1 from then until the bed.
static func lights_strength(hours: float) -> float:
	return clampf(inverse_lerp(LIGHTS_START_HOUR, LIGHTS_PEAK_HOUR, hours), 0.0, 1.0)


## One slot's peak grade as final shader rows: pushed from identity by STRENGTH, then scaled
## by BRIGHTNESS.
static func _resolved_grade(time: String, interior: bool) -> Dictionary:
	var g: Dictionary = GRADES[time]
	var id: Dictionary = GRADES["Afternoon"]
	var k: float = STRENGTH.get(time, 1.0)
	var b: float = BRIGHTNESS.get(time, 1.0)
	if interior:
		k *= INTERIOR_TINT.get(time, 0.0)
		b = INTERIOR_BRIGHTNESS.get(time, 1.0)
	var rows := {"curve": (g["curve"] as Vector3) * k * b}
	for key in ["red", "green", "blue"]:
		rows[key] = (id[key] + (g[key] - id[key]) * k) * b
	return rows


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


## Restyles and scales every PointLight2D under `root` for the time on the clock. Runs on map
## load and again whenever the clock moves on a map that stays on screen (a fish), so each
## light remembers its full strength and whether its map wanted it on. Lights are hidden
## outright while the strength is 0.
static func style_lights(root: Node, hours: float) -> void:
	var k: float = lights_strength(hours)
	for node in root.find_children("*", "PointLight2D", true, false):
		var light := node as PointLight2D
		if not light.has_meta(LIGHT_WANTED_META):
			light.set_meta(LIGHT_WANTED_META, light.visible)
		if k <= 0.0:
			light.visible = false
			continue
		if not light.has_meta(LIGHT_FULL_ENERGY_META):
			if _is_round_glow(light):
				var old := light.color
				var strength := maxf(old.r, maxf(old.g, old.b)) * old.a * light.energy
				var old_tex := light.texture as GradientTexture2D
				light.texture = _pool_for(old_tex)
				# A light's size is its texture's pixel size x texture_scale: keep the footprint.
				light.texture_scale *= float(old_tex.width) / float(POOL_TEXTURE_PX) * POOL_SIZE
				light.color = POOL_COLOUR
				light.energy = strength * POOL_ENERGY_SCALE
			light.set_meta(LIGHT_FULL_ENERGY_META, light.energy)
		light.energy = float(light.get_meta(LIGHT_FULL_ENERGY_META)) * k
		light.visible = bool(light.get_meta(LIGHT_WANTED_META))


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
