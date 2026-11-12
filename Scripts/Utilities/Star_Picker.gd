extends Control

## A row of 10 clickable stars for the F placement tool's side panel: click the Nth star to
## give an opponent N stars. 1-7 are the normal gold scale; 8 (orange), 9 (red) and 10 (purple)
## are the secret ones. Hovering previews the pick. Same star shape and colours as the
## challenge box (Difficulty_Stars.gd). Preloaded, no class_name.

const DifficultyStars := preload("res://Scripts/Global_Scripts/Difficulty_Stars.gd")

## TWEAKABLE: star size and spacing in the panel (screen px).
const STAR_SIZE := 34.0
const SECRET_STAR_SIZE := 38.0
const GAP := 5.0
## A thin divider between the normal 7 and the secret 3, so the split reads at a glance.
const DIVIDER_GAP := 12.0

signal picked(stars: int)

## The value shown filled in. 0 = none.
var value: int = 0
## True when `value` is the automatic rating (drawn paler, as it is not set by hand yet).
var automatic: bool = false
var _hover: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(_total_width(), SECRET_STAR_SIZE + 4.0)
	tooltip_text = "Click a star to set the difficulty.\n1-7 = normal.  8 / 9 / 10 = secret (Elders / gym leaders / Mewtwo)."
	mouse_exited.connect(func():
		_hover = 0
		queue_redraw())


func _size_of(nth: int) -> float:
	return STAR_SIZE if nth <= DifficultyStars.NORMAL_STARS else SECRET_STAR_SIZE


func _total_width() -> float:
	var w := 0.0
	for n in range(1, 11):
		w += _size_of(n) + GAP
	return w + DIVIDER_GAP


## The left edge of the Nth star (1-based).
func _left_of(nth: int) -> float:
	var x := 0.0
	for n in range(1, nth):
		x += _size_of(n) + GAP
	if nth > DifficultyStars.NORMAL_STARS:
		x += DIVIDER_GAP
	return x


func _star_at(x: float) -> int:
	for n in range(1, 11):
		var left := _left_of(n)
		if x >= left - GAP * 0.5 and x < left + _size_of(n) + GAP * 0.5:
			return n
	return 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _star_at(event.position.x)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var n := _star_at(event.position.x)
		if n > 0:
			accept_event()
			picked.emit.call_deferred(n)


func _draw() -> void:
	var shown: int = _hover if _hover > 0 else value
	var bottom: float = size.y - 2.0
	for n in range(1, 11):
		var d := _size_of(n)
		var centre := Vector2(_left_of(n) + d * 0.5, bottom - d * 0.5)
		var colour: Color = DifficultyStars.EMPTY
		if n <= shown:
			colour = DifficultyStars.colour_for(n)
			if automatic and _hover == 0:
				colour.a = 0.55
		var points := DifficultyStars.star_points(centre, d * 0.5)
		draw_colored_polygon(points, colour)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, DifficultyStars.OUTLINE, 2.0, true)
	# The divider between the normal and the secret stars.
	var div_x: float = _left_of(DifficultyStars.NORMAL_STARS + 1) - (DIVIDER_GAP + GAP) * 0.5
	draw_line(Vector2(div_x, 4.0), Vector2(div_x, size.y - 4.0), Color(1, 1, 1, 0.25), 1.0)
