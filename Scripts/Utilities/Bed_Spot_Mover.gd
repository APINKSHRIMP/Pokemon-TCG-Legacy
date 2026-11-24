class_name BedSpotMover
extends CanvasLayer

## DEBUG: MOVE BED SPOTS (2026-11-24) -- DEL menu -> "Move bed spots", in the bedroom.
## Drag a bed space with the mouse, or pick one with Tab and nudge it with the arrows
## (Shift = 8 px). Enter saves every space's position to Pokemon_Beds.json "bedroom_spots"
## (PokemonHome.save_bedroom_spots); Esc closes (unsaved moves last until the room reloads).
## A spot's position is its bed's BOTTOM-CENTRE, so a Pokémon's sleeping seat moves with it.

const LAYER := 90
const NUDGE := 1.0
const NUDGE_FAST := 8.0
## How close (world px) a click has to be to a spot's body to grab it.
const GRAB_SLOP := 6.0

var _spots: Array = []
var _selected: int = 0
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _dirty: bool = false
var _card: PanelContainer = null
var _status: Label = null


static func open(map_root: Node) -> BedSpotMover:
	var m := BedSpotMover.new()
	map_root.add_child(m)
	return m


static func is_open(tree: SceneTree) -> bool:
	return tree.get_first_node_in_group("bed_spot_mover") != null


func _ready() -> void:
	layer = LAYER
	add_to_group("bed_spot_mover")
	_spots = get_tree().get_nodes_in_group(PokemonBedSpot.GROUP)
	_spots.sort_custom(func(a, b): return a.slot < b.slot)
	_build()
	_select(0)
	if MapManager._player != null and is_instance_valid(MapManager._player):
		MapManager._player.lock_movement()
	BugReport.register_menu(self, close, "bed spot mover")


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DebugFormTheme.build()
	add_child(root)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", DebugFormTheme.card_style(14))
	_card.position = Vector2(24, 24)
	_card.custom_minimum_size = Vector2(430, 0)
	root.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)
	col.add_child(DebugFormTheme.heading("Move bed spots"))
	col.add_child(DebugFormTheme.key_row("Mouse drag", "Move a bed space"))
	col.add_child(DebugFormTheme.key_row("Tab / Shift + Tab", "Pick the next / previous space"))
	col.add_child(DebugFormTheme.key_row("Arrows", "Nudge 1 px (Shift: 8 px)"))
	col.add_child(DebugFormTheme.key_row("Enter", "Save to Pokemon_Beds.json"))
	col.add_child(DebugFormTheme.key_row("Esc", "Close"))
	col.add_child(DebugFormTheme.hint("The position is the bed's bottom-centre. Empty spaces show as numbered dots."))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(DebugFormTheme.button("Save", _save, "Enter", "PrimaryButton"))
	row.add_child(DebugFormTheme.button("Close", close, "Esc"))


func _select(i: int) -> void:
	if _spots.is_empty():
		_say("No bed spaces on this map.", DebugFormTheme.WARN)
		return
	_selected = posmod(i, _spots.size())
	for s in _spots:
		(s as PokemonBedSpot).highlighted = s == _spots[_selected]
	_show_state()


func _show_state(extra: String = "") -> void:
	if _spots.is_empty():
		return
	var lines: Array = []
	for s in _spots:
		var spot := s as PokemonBedSpot
		lines.append("%s Space %d: (%d, %d)  %s" % [">" if spot == _spots[_selected] else "  ", spot.slot + 1,
				roundi(spot.position.x), roundi(spot.position.y), spot.bed if spot.bed != "" else "(empty)"])
	if _dirty:
		lines.append("UNSAVED -- Enter to save.")
	if extra != "":
		lines.append(extra)
	_say("\n".join(PackedStringArray(lines)), DebugFormTheme.WARN if _dirty else DebugFormTheme.INK)


func _say(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


func _move_selected(delta: Vector2) -> void:
	if _spots.is_empty():
		return
	var spot := _spots[_selected] as PokemonBedSpot
	spot.position = (spot.position + delta).round()
	_moved()


func _moved() -> void:
	_dirty = true
	PokemonHome.refresh_house(get_parent())
	_show_state()


func _save() -> void:
	var points: Array = []
	for s in _spots:
		points.append((s as PokemonBedSpot).position)
	var err := PokemonHome.save_bedroom_spots(points)
	if err != "":
		_say(err, DebugFormTheme.DANGER)
		return
	_dirty = false
	_show_state("Saved.")
	_status.add_theme_color_override("font_color", DebugFormTheme.SUCCESS)


func close() -> void:
	for s in _spots:
		if is_instance_valid(s):
			(s as PokemonBedSpot).highlighted = false
	if MapManager._player != null and is_instance_valid(MapManager._player):
		MapManager._player.unlock_movement()
	queue_free()


func _spot_at(world: Vector2) -> int:
	for i in _spots.size():
		var spot := _spots[i] as PokemonBedSpot
		var size: Vector2 = (spot._shape.shape as RectangleShape2D).size
		var r := Rect2(spot.global_position + Vector2(-size.x * 0.5, -size.y), size).grow(GRAB_SLOP)
		if r.has_point(world):
			return i
	return -1


func _input(event: InputEvent) -> void:
	if _spots.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		return
	var spot := _spots[_selected] as PokemonBedSpot
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _card.get_global_rect().has_point(event.position):
				return
			var world := spot.get_global_mouse_position()
			var hit := _spot_at(world)
			if hit >= 0:
				_select(hit)
				spot = _spots[_selected]
				_dragging = true
				_drag_offset = spot.global_position - world
			get_viewport().set_input_as_handled()
		elif _dragging:
			_dragging = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dragging:
		spot.global_position = (spot.get_global_mouse_position() + _drag_offset).round()
		_moved()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed):
		return
	var step := NUDGE_FAST if event.shift_pressed else NUDGE
	var handled := true
	match event.keycode:
		KEY_TAB: _select(_selected + (-1 if event.shift_pressed else 1))
		KEY_LEFT: _move_selected(Vector2(-step, 0))
		KEY_RIGHT: _move_selected(Vector2(step, 0))
		KEY_UP: _move_selected(Vector2(0, -step))
		KEY_DOWN: _move_selected(Vector2(0, step))
		KEY_ENTER, KEY_KP_ENTER: _save()
		KEY_ESCAPE: close()
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()
