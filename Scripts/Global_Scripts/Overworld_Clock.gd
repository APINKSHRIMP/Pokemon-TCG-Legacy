extends Control

## THE OVERWORLD CLOCK -- analogue hand and digital time in the top-left corner.
##
## Art: Image_Assets/Clock/, built by Scripts/Utilities/clock_art_build.py. Every layer is
## drawn here at whole art pixels, so the art stays crisp at DISPLAY_SCALE.
##
## It reads GameState.clock_hours() every frame and needs no calls to stay right. The FACE and
## ICON change sharply at the slot boundary, on purpose: the world's colour is gradual now, so
## this is the player's clear sign of which time SLOT they are in.
##
## BaseMapScene adds one to the map's UI layer on load. It hides itself for menus, fishing,
## cutscenes and match transitions by sliding up off the top of the screen as it fades, which
## also gives cutscenes a visible start and end. Shops are separate scenes, so they have no clock.
##
## Used via preload (no class_name):
##   const OverworldClock = preload("res://Scripts/Global_Scripts/Overworld_Clock.gd")

## TWEAKABLE -- size on screen: art pixels x this. Whole numbers keep every pixel the same size.
const DISPLAY_SCALE := 3.0
## TWEAKABLE -- how far down from the top of the screen it rests. Across, it centres above the
## time-slot signs (TimeOfDayBanner.centre_x; move them all with that script's REST_POS.x).
const REST_Y := 16.0
## TWEAKABLE -- slide + fade timings (seconds).
const SLIDE_IN_TIME := 0.45
const SLIDE_OUT_TIME := 0.3
## TWEAKABLE -- how fast the hand sweeps forward to a new time, in clock hours per second.
const SWEEP_HOURS_PER_SECOND := 1.5
## TWEAKABLE -- a big jump speeds the hand up so the sweep never drags on much past this (seconds).
const SWEEP_MAX_SECONDS := 1.0
## TWEAKABLE -- the little pop when the face changes colour at a slot boundary.
const POP_SCALE := 1.18
const POP_TIME := 0.3
## TWEAKABLE -- gap between the clock and the time-slot banner dropping out from under it.
const BANNER_GAP := 8.0
## TWEAKABLE -- how far below the centre the digital time starts, in art pixels.
const TEXT_DROP := 5

const ART_DIR := "res://Image_Assets/Clock/"
const ART_PX := 52
const HAND_COLS := 12
const HAND_FRAMES := 120
const GLYPH_ORDER := "0123456789apm"
const GLYPH_CELL := 9
## Lit width of each glyph, matching GLYPHS in clock_art_build.py.
const GLYPH_WIDTH := {"1": 3, "m": 7}
const GLYPH_DEFAULT_WIDTH := 5
const SIZE_PX := ART_PX * DISPLAY_SCALE

## Set before add_child. Hidden starts slide in once `start_delay` has passed; a door keeps the
## clock in place so it just stays on screen across the fade.
var start_hidden: bool = false
var start_delay: float = 0.0

var _textures := {}
var _hours: float = 8.0
var _slot: String = ""
var _frame: int = -1
var _label: String = ""
var _showing: bool = false
var _tween: Tween = null


## How far down the time-slot banner rests: just below the clock, when the clock is switched on.
static func banner_rest_y(default_y: float) -> float:
	if not GameState.overworld_clock_on():
		return default_y
	return REST_Y + SIZE_PX + BANNER_GAP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 60   # above the banner, so the banner comes out from underneath
	size = Vector2(SIZE_PX, SIZE_PX)
	pivot_offset = size * 0.5
	for slot in GameState.TIMES_OF_DAY:
		_textures["face_" + slot] = load(ART_DIR + "Clock_Face_%s.png" % slot)
		_textures["icon_" + slot] = load(ART_DIR + "Clock_Icon_%s.png" % slot)
	for part in ["Dots", "Hand", "Glyphs", "Frame"]:
		_textures[part] = load(ART_DIR + "Clock_%s.png" % part)

	var now: float = GameState.clock_hours()
	var last: float = GameState.last_seen_clock_hours
	# Carries on from where the player last saw it, so the hand sweeps forward after a match.
	_set_hours(last if last >= 0.0 and last <= now else now, false)

	_showing = not start_hidden and _should_show()
	position.x = TimeOfDayBanner.centre_x(get_parent()) - SIZE_PX * 0.5
	position.y = REST_Y if _showing else _hidden_y()
	modulate.a = 1.0 if _showing else 0.0


func _process(delta: float) -> void:
	start_delay = maxf(0.0, start_delay - delta)
	var want: bool = start_delay <= 0.0 and _should_show()
	if want != _showing:
		_slide(want)

	var target: float = GameState.clock_hours()
	if not GameState.overworld_clock_on() or target < _hours or _reduce_motion():
		if target != _hours:
			_set_hours(target, false)
	elif _hours < target and _showing and not _sliding():
		var speed: float = maxf(SWEEP_HOURS_PER_SECOND, (target - _hours) / SWEEP_MAX_SECONDS)
		_set_hours(move_toward(_hours, target, speed * delta), true)
	GameState.last_seen_clock_hours = _hours


func _should_show() -> bool:
	if not GameState.overworld_clock_on():
		return false
	if MapManager.cutscene_active or MapManager.is_fishing():
		return false
	# Both the pause menu and the phone map pause the overworld; only the menu hides the clock.
	if MapManager.overworld_paused and not WorldMap.is_open():
		return false
	if MatchTransition.is_active() or MatchTransition.is_returning():
		return false
	# Celeste Harbour's taxi arrival runs on its own flag rather than MapManager's.
	var map := get_tree().current_scene
	return map == null or map.get("_cutscene_active") != true


func _hidden_y() -> float:
	return REST_Y if _reduce_motion() else -SIZE_PX - 8.0


func _reduce_motion() -> bool:
	return GameState.reduce_motion_setting == "where_possible"


func _sliding() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func _slide(show_it: bool) -> void:
	_showing = show_it
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var time: float = SLIDE_IN_TIME if show_it else SLIDE_OUT_TIME
	_tween = create_tween()
	_tween.set_parallel(true)
	var move := _tween.tween_property(self, "position:y", REST_Y if show_it else _hidden_y(), time)
	move.set_trans(Tween.TRANS_BACK if show_it else Tween.TRANS_SINE)
	move.set_ease(Tween.EASE_OUT if show_it else Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 1.0 if show_it else 0.0, time)


func _set_hours(hours: float, pop_on_new_slot: bool) -> void:
	_hours = hours
	var slot: String = GameState.clock_slot_at(hours)
	var frame: int = int(round(fmod(hours, 12.0) / 12.0 * float(HAND_FRAMES))) % HAND_FRAMES
	var label: String = GameState.clock_label(hours)
	if slot == _slot and frame == _frame and label == _label:
		return
	var new_slot: bool = slot != _slot and _slot != ""
	_slot = slot
	_frame = frame
	_label = label
	queue_redraw()
	if new_slot and pop_on_new_slot and not _reduce_motion():
		var pop := create_tween()
		pop.tween_property(self, "scale", Vector2.ONE * POP_SCALE, POP_TIME * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "scale", Vector2.ONE, POP_TIME * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(DISPLAY_SCALE, DISPLAY_SCALE))
	draw_texture(_textures["face_" + _slot], Vector2.ZERO)
	draw_texture(_textures["Dots"], Vector2.ZERO)
	draw_texture(_textures["icon_" + _slot], Vector2.ZERO)
	var cell := Vector2(ART_PX, ART_PX)
	var from := Vector2(_frame % HAND_COLS, _frame / HAND_COLS) * float(ART_PX)
	draw_texture_rect_region(_textures["Hand"], Rect2(Vector2.ZERO, cell), Rect2(from, cell))
	_draw_label()
	draw_texture(_textures["Frame"], Vector2.ZERO)


## Centred, above the 6 o'clock dot. Each glyph cell carries its own 1px outline, so the first
## lit pixel sits one in from the cell's corner.
func _draw_label() -> void:
	var total: int = _label.length() - 1
	for ch in _label:
		total += int(GLYPH_WIDTH.get(ch, GLYPH_DEFAULT_WIDTH))
	var centre: float = (ART_PX - 1) / 2.0
	var x: int = int(centre - total / 2.0 + 0.5)
	var y: int = int(centre + TEXT_DROP)
	for ch in _label:
		var index: int = GLYPH_ORDER.find(ch)
		var region := Rect2(index * GLYPH_CELL, 0, GLYPH_CELL, GLYPH_CELL)
		draw_texture_rect_region(_textures["Glyphs"], Rect2(x - 1, y - 1, GLYPH_CELL, GLYPH_CELL), region)
		x += int(GLYPH_WIDTH.get(ch, GLYPH_DEFAULT_WIDTH)) + 1
