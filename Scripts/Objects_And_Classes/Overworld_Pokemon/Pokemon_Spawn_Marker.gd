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
	"static": Color(0.9, 0.45, 0.9),
}

var point: Dictionary = {}
## Corners picked so far while the placement tool is capturing this point's water area
## (world positions), drawn as dots. Not saved.
var pending_corners: Array = []


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
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		var table := OverworldPokemonData.time_table(point.get("tables"), str(time_name))
		var rows = table.get("table", [])
		var shown: String = "-" if not (rows is Array) or (rows as Array).is_empty() else str(table.get("chance", 0))
		parts.append(str(time_name).left(1) + shown)
	var text := "  ".join(parts)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-TEXT_WIDTH * 0.5, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, Vector2(-TEXT_WIDTH * 0.5, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, FONT_SIZE, colour)
