extends PanelContainer

# ============================================================
# MATCH MODIFIERS BOX -- the rules of a match, before saying yes to it
# ============================================================
# Sits just above the Yes/No message box, against its right edge, laid out like the phone
# map's legend. A child of the message box, so it goes when the box goes.
# MapManager builds one per challenge (_show_modifiers_box).
# ============================================================

# TWEAKABLE
const MIN_WIDTH := 620.0
const PAD := 22
const ROW_GAP := 8
const TITLE_SIZE := 18      # the phone map legend's sizes
const TEXT_SIZE := 17
const FADE_IN := 0.15
## Clear of the pills that straddle the message box's top edge (DynamicMessageBox.PILL_RISE),
## plus a small gap, so a long row of pills can never run underneath this box.
const GAP_ABOVE_BOX := 36.0

var _message_box: Control = null


func setup(message_box: Control, lines: Array) -> void:
	_message_box = message_box
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Opaque: unlike the phone map's legend, this one sits over the bright map, not a dimmed one.
	var skin := UIKit.make_modal_panel()
	add_theme_stylebox_override("panel", skin.get_theme_stylebox("panel"))
	skin.free()
	custom_minimum_size.x = MIN_WIDTH

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", ROW_GAP)
	margin.add_child(column)

	column.add_child(_row("subtitle", "Modifiers:", TITLE_SIZE))
	for line in lines:
		column.add_child(_row("chip", String(line), TEXT_SIZE))


func _ready() -> void:
	minimum_size_changed.connect(_place)
	UIKit.on_screen_resized(_place)
	_place()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_IN)


func _row(style: String, text: String, font_size: int) -> Label:
	var label := Label.new()
	UIKit.set_label(label, style, text, "field_fg", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _place() -> void:
	size = get_combined_minimum_size()
	var corner: Vector2 = _message_box.call("panel_top_right")
	position = Vector2(corner.x - size.x, corner.y - GAP_ABOVE_BOX - size.y)
