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
const TEMPLATE_COLOURS := {
	"bug_tree": Color(0.45, 0.9, 0.35),
	"swinging_bug": Color(0.75, 0.95, 0.4),
	"rodent": Color(0.95, 0.65, 0.3),
	"burying": Color(0.7, 0.5, 0.3),
	"surfacing": Color(0.35, 0.65, 1.0),
	"static": Color(0.9, 0.45, 0.9),
}

var point: Dictionary = {}


func _ready() -> void:
	z_as_relative = false
	z_index = 200


func _draw() -> void:
	var colour: Color = TEMPLATE_COLOURS.get(str(point.get("template", "")), Color.WHITE)
	draw_circle(Vector2.ZERO, RADIUS, Color(colour, 0.3))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, colour, 1.5)
	draw_line(Vector2(-3, 0), Vector2(3, 0), colour, 1.0)
	draw_line(Vector2(0, -3), Vector2(0, 3), colour, 1.0)
	var text := "%s  %s%%" % [str(point.get("id", "?")), str(point.get("chance", 0))]
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-60, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, 120, FONT_SIZE, 2, Color.BLACK)
	draw_string(font, Vector2(-60, -RADIUS - 3), text, HORIZONTAL_ALIGNMENT_CENTER, 120, FONT_SIZE, colour)
