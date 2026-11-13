class_name TimeOfDayBanner
extends RefCounted

# ============================================================
# TIME OF DAY BANNER — "MORNING" / "AFTERNOON" / ... pop-down
# ============================================================
#   TimeOfDayBanner.play(ui_layer, GameState.get_time())
# A small rounded panel (the message box's shape) with a drawn icon and the slot's
# name. It fades in moving down from above the top-left corner, sits there, then
# fades out moving back up and frees itself. BaseMapScene plays it on any map load
# where the time slot has changed since the player last saw a map.
# ============================================================

## TWEAKABLE — the look, per slot: panel colour and what it says.
const STYLE := {
	"Morning":   {"text": "Morning",   "bg": Color("7cc4ee"), "icon": "sun"},
	"Afternoon": {"text": "Afternoon", "bg": Color("f2c53d"), "icon": "sun"},
	"Evening":   {"text": "Evening",   "bg": Color("d2461b"), "icon": "sunset"},
	"Night":     {"text": "Night",     "bg": Color("1f2f6e"), "icon": "moon"},
	"Bedtime":   {"text": "Midnight",  "bg": Color("161f4d"), "icon": "moon_stars"},
}

## TWEAKABLE — where it rests (screen px from the top-left), sizes and timings (seconds).
## REST_POS.x is the left edge of the WIDEST sign; shorter ones centre on the same column.
const REST_POS := Vector2(28.0, 28.0)
const DROP_FROM := 70.0          # starts this far above its resting spot
const DELAY := 0.6               # after the map loads, so the scene fade-in is done first
# ISSUE #379: fly-in and stay are 2.5x their old values (0.35 -> 0.875, 1.0 -> 2.5).
const IN_TIME := 0.875
const HOLD_TIME := 5.0   # ISSUE #478: doubled (was 2.5)
const OUT_TIME := 0.35
const FONT_SIZE := 30
const ICON_SIZE := 34.0
const CORNER_RADIUS := 14
const BORDER := 3
const LAYER_Z := 50


## Measured once: the width of the widest sign ("Afternoon").
static var _widest_width: float = -1.0


## The column the clock and every sign centre on: the middle of the widest sign when it sits
## REST_POS.x from the left edge of the screen.
static func centre_x(ui_layer: Node) -> float:
	if _widest_width < 0.0:
		_widest_width = 0.0
		for time_name in STYLE:
			var probe := _build_panel(time_name)
			ui_layer.add_child(probe)
			_widest_width = maxf(_widest_width, probe.get_combined_minimum_size().x)
			ui_layer.remove_child(probe)
			probe.queue_free()
	return REST_POS.x + _widest_width * 0.5


## `rest_y`: how far down the screen it settles. BaseMapScene passes a spot just below the clock.
## It always sits centred on centre_x(), whatever its own width.
## `clock`: the overworld clock, if it is switched on. The banner then hands itself to the clock
## once it has landed, and the two slide away TOGETHER: the clock stays up for at least HOLD_TIME
## and the banner stays as long as the clock does. Without one it leaves after HOLD_TIME.
static func play(ui_layer: Node, time_name: String, rest_y: float = REST_POS.y, clock: Node = null) -> void:
	if ui_layer == null or not is_instance_valid(ui_layer):
		return
	# 2026-11-12 (user): with the clock on, the clock OWNS the sign -- they slide in together, leave
	# together, and the sign is carried through doors with the clock (Overworld_Clock.show_banner).
	if clock != null and is_instance_valid(clock) and GameState.overworld_clock_on() and clock.has_method("show_banner"):
		clock.show_banner(time_name, HOLD_TIME)
		return
	var panel := build(ui_layer, time_name, rest_y)
	var tween := drop_in(panel, DELAY)
	tween.tween_interval(HOLD_TIME)
	tween.tween_callback(leave.bind(panel))


## A sign for `time_name`, added to `ui_layer`, waiting invisible above its resting spot.
## drop_in() brings it down; leave() takes it away.
static func build(ui_layer: Node, time_name: String, rest_y: float) -> Control:
	var column: float = centre_x(ui_layer)
	var panel := _build_panel(time_name)
	ui_layer.add_child(panel)
	var rest_pos := Vector2(column - panel.get_combined_minimum_size().x * 0.5, rest_y)
	panel.set_meta("rest_y", rest_y)
	panel.position = rest_pos - Vector2(0.0, DROP_FROM)
	panel.modulate.a = 0.0
	return panel


## Drops a built sign onto its resting spot after `delay` (`instant`: put it there now). Returns the tween.
static func drop_in(panel: Control, delay: float = 0.0, instant: bool = false) -> Tween:
	var rest_y: float = float(panel.get_meta("rest_y", REST_POS.y))
	var tween := panel.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if instant:
		panel.position.y = rest_y
		panel.modulate.a = 1.0
		tween.tween_interval(0.0)
		return tween
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(panel, "position:y", rest_y, IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, IN_TIME)
	return tween


## Slide a banner back up and free it. The clock calls this as it slides away itself (which can
## be for the pause menu, so this runs while paused).
static func leave(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or panel.has_meta("leaving"):
		return
	panel.set_meta("leaving", true)
	var drop: Tween = panel.get_meta("drop_tween") if panel.has_meta("drop_tween") else null
	if drop != null and drop.is_valid():
		drop.kill()
	var tween := panel.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(panel, "position:y", panel.position.y - DROP_FROM, OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, OUT_TIME)
	tween.tween_callback(panel.queue_free)


static func _build_panel(time_name: String) -> PanelContainer:
	var style: Dictionary = STYLE.get(time_name, STYLE["Morning"])
	var bg: Color = style["bg"]
	var ink: Color = UIKit.ink_on(bg)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = LAYER_Z
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = bg.lightened(0.35)
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0.0, 3.0)
	sb.anti_aliasing = true
	sb.content_margin_left = 16
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var glyph := _Glyph.new()
	glyph.kind = String(style["icon"])
	glyph.ink = ink
	glyph.bg = bg
	glyph.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)

	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.set_label(label, "title", String(style["text"]), "field_fg", FONT_SIZE)
	label.add_theme_color_override("font_color", ink)
	row.add_child(label)
	return panel


## The little picture on the left: a sun, a sun on the horizon, a crescent moon, or a
## crescent with two stars. Drawn, so it needs no art and takes the panel's ink colour.
class _Glyph extends Control:
	var kind: String = "sun"
	var ink: Color = Color.WHITE
	var bg: Color = Color.BLACK

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5
		match kind:
			"sun":
				draw_circle(c, r * 0.42, ink)
				for i in 8:
					var a := TAU * float(i) / 8.0
					var dir := Vector2(cos(a), sin(a))
					draw_line(c + dir * r * 0.62, c + dir * r * 0.95, ink, 3.0, true)
			"sunset":
				var horizon := c.y + r * 0.25
				draw_circle(Vector2(c.x, horizon), r * 0.48, ink)
				# Everything below the horizon is hidden behind a strip of the panel colour.
				draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), bg)
				draw_line(Vector2(0.0, horizon), Vector2(size.x, horizon), ink, 3.0, true)
				for i in 5:
					var a := PI + PI * float(i + 1) / 6.0
					var dir := Vector2(cos(a), sin(a))
					draw_line(Vector2(c.x, horizon) + dir * r * 0.66, Vector2(c.x, horizon) + dir * r * 0.95, ink, 3.0, true)
			"moon", "moon_stars":
				var mc := c + Vector2(-r * 0.08, 0.0)
				draw_circle(mc, r * 0.62, ink)
				draw_circle(mc + Vector2(r * 0.34, -r * 0.2), r * 0.52, bg)
				if kind == "moon_stars":
					_star(c + Vector2(r * 0.62, r * 0.38), r * 0.16)
					_star(c + Vector2(r * 0.3, -r * 0.7), r * 0.11)

	func _star(at: Vector2, s: float) -> void:
		draw_line(at + Vector2(-s, 0.0), at + Vector2(s, 0.0), ink, 2.0, true)
		draw_line(at + Vector2(0.0, -s), at + Vector2(0.0, s), ink, 2.0, true)
