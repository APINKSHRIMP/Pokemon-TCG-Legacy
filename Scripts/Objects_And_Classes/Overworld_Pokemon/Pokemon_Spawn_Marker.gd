class_name PokemonSpawnMarker
extends Node2D

## A spawn point drawn on the map while the placement tool is open: a coloured ring
## per template with the point's id and chance above it. The placement tool treats
## it like an actor -- Tab selects it, G grabs it, Ctrl+arrows nudge, M edits.
##
## `point` is a reference into the tool's working copy of the spawn file, so the
## tool writes the new position straight into it.

const RADIUS := 7.0
const FONT_SIZE := 8
## Width the label is centred in; wide enough for an id plus four per-time chances.
const TEXT_WIDTH := 220.0
const TEMPLATE_COLOURS := {
	"bug_tree": Color(0.45, 0.9, 0.35),
	"swinging_bug": Color(0.75, 0.95, 0.4),
	"skittish": Color(0.95, 0.65, 0.3),
	"burying": Color(0.7, 0.5, 0.3),
	"surfacing": Color(0.35, 0.65, 1.0),
	"fish_tank": Color(0.3, 0.95, 0.85),
	"fishing_spot": Color(0.2, 0.45, 0.95),
	"static": Color(0.9, 0.45, 0.9),
	"walker": Color(1.0, 0.55, 0.75),
}

var point: Dictionary = {}
## Corners picked so far while the placement tool is capturing this point's water area
## (world positions), drawn as dots. Not saved.
var pending_corners: Array = []

const RouteRunner := preload("res://Scripts/Objects_And_Classes/Route_Runner.gd")


# ── route host (walker template) ──────────────────────────────────────────────
# A walker's route is drawn on its MARKER with the same keys as an NPC's: the placement
# tool and its overlay talk to anything with this little API. Positions here are in the
# marker's parent space, the same space `at` is in. The route lives in the point's
# `route` block, so editing it edits the working copy of the spawn file directly, and
# the Pokémon out on the map is handed the new steps at once.

var movement_pattern: String:
	get: return "route" if is_walker() else ""

var route_anchor: Vector2:
	get: return position

var route_steps: Array:
	get: return _route_block().get("steps", []) if _route_block().get("steps") is Array else []

var route_mode: String:
	get: return str(_route_block().get("mode", "loop"))

var patrol_speed: float:
	get: return float(_route_block().get("speed", 40.0))
	set(value):
		_ensure_route_block()["speed"] = roundi(value)
		var walker := _live_walker()
		if walker != null:
			walker.speed = value

var _route_nodes: Array:
	get: return RouteRunner.build_nodes(route_steps)


func is_walker() -> bool:
	return str(point.get("template", "")) == "walker"


func route_node_position(i: int) -> Vector2:
	var nodes := _route_nodes
	if i < 0 or i >= nodes.size():
		return route_anchor
	return route_anchor + (nodes[i]["pos"] as Vector2)


func route_current_node() -> int:
	var walker := _live_walker()
	return walker.route_current_node() if walker != null else 0


func set_route(steps: Array, mode: String) -> void:
	var block := _ensure_route_block()
	block["steps"] = steps.duplicate(true)
	block["mode"] = mode
	var walker := _live_walker()
	if walker != null:
		walker.route.set_steps(steps, mode)
	queue_redraw()


func _route_block() -> Dictionary:
	return point.get("route", {}) if point.get("route") is Dictionary else {}


func _ensure_route_block() -> Dictionary:
	if not (point.get("route") is Dictionary):
		point["route"] = {"speed": 40, "mode": "loop", "steps": []}
	return point["route"]


func _live_walker() -> Node:
	var spawner := get_parent() as OverworldPokemonSpawner
	if spawner == null:
		return null
	var pokemon := spawner.live_pokemon(str(point.get("id", "")))
	return pokemon if pokemon != null and "route" in pokemon else null


func _ready() -> void:
	z_as_relative = false
	z_index = 200


func _draw() -> void:
	var colour: Color = TEMPLATE_COLOURS.get(str(point.get("template", "")), Color.WHITE)
	# The water area, relative to the point's saved spot so it moves with the marker
	# while it is being carried.
	var region := OverworldPokemonData.point_region(point)
	if region.has_area():
		var at = point.get("at", [0, 0])
		var offset := region.position - Vector2(float(at[0]), float(at[1]))
		draw_rect(Rect2(offset, region.size), Color(colour, 0.12), true)
		draw_rect(Rect2(offset, region.size), colour, false, 1.5)
	# Corners picked so far during capture, and the rectangle they already make.
	if not pending_corners.is_empty():
		var local_corners: Array = []
		for corner in pending_corners:
			local_corners.append(to_local(corner))
		if local_corners.size() >= 2:
			var preview := Rect2(local_corners[0], Vector2.ZERO)
			for c in local_corners:
				preview = preview.expand(c)
			draw_rect(preview, Color(1, 0.9, 0.2, 0.8), false, 1.0)
		for c in local_corners:
			draw_circle(c, 3.0, Color(1, 0.9, 0.2))
	draw_circle(Vector2.ZERO, RADIUS, Color(colour, 0.3))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, colour, 1.5)
	draw_line(Vector2(-3, 0), Vector2(3, 0), colour, 1.0)
	draw_line(Vector2(0, -3), Vector2(0, 3), colour, 1.0)
	# Chance per time of day, "-" where that time's table is empty: "skittish_1  M100 A- E- N40".
	var parts: Array = [str(point.get("id", "?"))]
	var template := str(point.get("template", ""))
	if template == OverworldPokemonData.TANK_TEMPLATE:
		# A tank has no times and no chance -- what it has is a headcount.
		parts.append("%d fish" % OverworldPokemonData.tank_total(point))
	else:
		# A fishing spot has the four times but no chance (a cast always hooks one fish),
		# so what its four numbers count is the SPECIES that bite at that time.
		var is_fishing := template == OverworldPokemonData.FISHING_TEMPLATE
		for time_name in OverworldPokemonData.TIMES_OF_DAY:
			var table := OverworldPokemonData.time_table(point.get("tables"), str(time_name))
			var rows = table.get("table", [])
			var empty: bool = not (rows is Array) or (rows as Array).is_empty()
			var shown: String = "-"
			if not empty:
				shown = str((rows as Array).size()) if is_fishing else str(table.get("chance", 0))
			parts.append(str(time_name).left(1) + shown)
	var text := "  ".join(parts)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-TEXT_WIDTH * 0.5, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, Vector2(-TEXT_WIDTH * 0.5, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, FONT_SIZE, colour)
