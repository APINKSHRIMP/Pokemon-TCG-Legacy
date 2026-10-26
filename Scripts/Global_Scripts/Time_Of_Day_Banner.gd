class_name TimeOfDayBanner
extends RefCounted

# ============================================================
# TIME OF DAY BANNER — "MORNING" / "AFTERNOON" / ... pop-down
# ============================================================
#   TimeOfDayBanner.play(ui_layer, GameState.get_time())
# A small rounded panel (the message box's shape) with a drawn icon and the slot's
# name. It fades in moving down from above the top-left corner, sits there, then
# fades out moving back up and frees itself. BaseMapScene plays it when the clock
# has moved since the player last saw it -- back from a match, or stepping outside.
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
const REST_POS := Vector2(28.0, 28.0)
const DROP_FROM := 70.0          # starts this far above its resting spot
const DELAY := 0.6               # after the map loads, so the scene fade-in is done first
# ISSUE #505: fly-in and stay are 2.5x their old values (0.35 -> 0.875, 1.0 -> 2.5).
const IN_TIME := 0.875
const HOLD_TIME := 2.5
const OUT_TIME := 0.35
const FONT_SIZE := 30
const ICON_SIZE := 34.0
const CORNER_RADIUS := 14
const BORDER := 3
const LAYER_Z := 50


static func play(ui_layer: Node, time_name: String) -> void:
	if ui_layer == null or not is_instance_valid(ui_layer):
		return
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

	ui_layer.add_child(panel)
	panel.position = REST_POS - Vector2(0.0, DROP_FROM)
	panel.modulate.a = 0.0

	print("ISSUE #505 FIX ACTIVE: time banner in ", IN_TIME, "s hold ", HOLD_TIME, "s")
	var tween := panel.create_tween()
	tween.tween_interval(DELAY)
	tween.tween_property(panel, "position:y", REST_POS.y, IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, IN_TIME)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(panel, "position:y", REST_POS.y - DROP_FROM, OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, OUT_TIME)
	tween.tween_callback(panel.queue_free)


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
