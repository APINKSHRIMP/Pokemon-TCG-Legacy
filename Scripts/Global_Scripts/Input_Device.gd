extends Node

# ============================================================
# INPUT DEVICE (autoload "InputDevice")
# ============================================================
# Three jobs, all about "is the player on the mouse, the keyboard or a pad":
#
#   1. LAST DEVICE. `last` is whichever of MOUSE / KEYBOARD / PAD produced the most
#      recent real input. Cursor rings (the match board cursor, the menu focus ring)
#      only show while it is not the mouse - a mouse player sees the game exactly as
#      before, and the first arrow / D-pad press brings the cursor back.
#      Read off Window.window_input, which fires for EVERY event before any node sees
#      it, so a screen consuming an event cannot hide it from this.
#
#   2. PAD FAMILY. pad_family() says "playstation" or "xbox" from the connected pad's
#      name, for the Controls screen's button labels.
#
#   3. MENU FOCUS. Godot's own focus navigation already moves between Buttons with
#      the arrows / D-pad / stick (ui_left etc. include the pad by default) and presses
#      the focused one on ui_accept. Two gaps are filled here:
#        - Godot's default ui_accept / ui_cancel have NO pad buttons; A and B are
#          added at startup.
#        - Nothing has focus until something grabs it, so the first direction press
#          on a menu did nothing. With no focus owner, that press now focuses the
#          top-left button of the top-most menu layer.
#      A gradient ring follows the focused button while the player is on keys/pad.
#
# The match board has its own cursor (Board_Nav.gd) and consumes direction presses
# itself, so none of the menu-focus behaviour reaches it.
# ============================================================

signal device_changed(device: int)

enum { MOUSE, KEYBOARD, PAD }

var last: int = MOUSE

## The pad family last seen: "xbox" or "playstation". Re-read on connect/disconnect.
var _pad_family: String = "xbox"

# Mouse jitter (a desk knock, a trackpad brush) should not yank the cursor ring
# away from a keyboard player. TWEAKABLE: px of travel in one event that counts.
const MOUSE_WAKE_PX := 3.0

# The ring that follows the focused menu button.
var _ring_layer: CanvasLayer = null
var _ring: Control = null
## Above every menu and the pause/options overlays (100/101), below the card zoom (150).
const RING_LAYER := 140


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_pad_buttons_to_ui_actions()
	get_tree().root.window_input.connect(_on_window_input)
	Input.joy_connection_changed.connect(func(_id, _connected): _refresh_pad_family())
	_refresh_pad_family()
	# A pad already plugged in at boot: start on it, so the first screen shows its cursor.
	if not Input.get_connected_joypads().is_empty():
		last = PAD

	_ring_layer = CanvasLayer.new()
	_ring_layer.layer = RING_LAYER
	add_child(_ring_layer)
	# The ring's gradient is the theme's, read when it is built - rebuild on a theme change.
	UITheme.theme_changed.connect(func():
		if _ring != null and is_instance_valid(_ring):
			_ring.queue_free()
		_ring = null)


## True while the player is driving with the keyboard or a pad (any cursor ring shows).
func using_nav() -> bool:
	return last != MOUSE


func using_pad() -> bool:
	return last == PAD


func pad_family() -> String:
	return _pad_family


func _refresh_pad_family() -> void:
	_pad_family = "xbox"
	for id in Input.get_connected_joypads():
		var n := Input.get_joy_name(id).to_lower()
		if "ps" in n.split(" ") or "playstation" in n or "dualsense" in n or "dualshock" in n \
				or "sony" in n or n == "wireless controller" or "ps4" in n or "ps5" in n:
			_pad_family = "playstation"
		break


func _add_pad_buttons_to_ui_actions() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		var already := false
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton and e.button_index == pair[1]:
				already = true
		if not already:
			var ev := InputEventJoypadButton.new()
			ev.button_index = pair[1]
			InputMap.action_add_event(action, ev)


func _on_window_input(event: InputEvent) -> void:
	var now := last
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_WAKE_PX:
			now = MOUSE
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			now = MOUSE
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			now = KEYBOARD
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			now = PAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > UIInput.STICK_PRESS:
			now = PAD
	if now != last:
		last = now
		device_changed.emit(last)


# ── Menu focus ───────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if UIInput.nav_direction(event) == Vector2i.ZERO:
		return
	var vp := get_viewport()
	if vp.gui_get_focus_owner() != null:
		return
	var btn := _first_menu_button()
	if btn == null:
		return
	btn.grab_focus()
	vp.set_input_as_handled()


## The top-left focusable button of the top-most layer that has any. Returns null
## when there is no menu up - the overworld's own controls are left alone unless its
## pause menu overlay is open.
func _first_menu_button() -> BaseButton:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var root: Node = scene
	if not (scene is Control):
		var overlay = scene.get("_menu_canvas_layer")
		if overlay == null or not is_instance_valid(overlay):
			return null
		root = overlay
	var buttons: Array = []
	_collect_buttons(root, buttons)
	if buttons.is_empty():
		return null
	var top_layer := -100000
	for b in buttons:
		top_layer = maxi(top_layer, _layer_of(b))
	var best: BaseButton = null
	for b in buttons:
		if _layer_of(b) != top_layer:
			continue
		if best == null:
			best = b
			continue
		var p: Vector2 = (b as Control).global_position
		var q: Vector2 = best.global_position
		if p.y < q.y - 4.0 or (absf(p.y - q.y) <= 4.0 and p.x < q.x):
			best = b
	return best


func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var b := child as BaseButton
			if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
				out.append(b)
		_collect_buttons(child, out)


func _layer_of(c: CanvasItem) -> int:
	var layer := c.get_canvas_layer_node()
	return layer.layer if layer != null else 0


func _process(_delta: float) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	var show := using_nav() and focus is BaseButton and focus.is_visible_in_tree()
	if not show:
		if _ring != null:
			_ring.visible = false
		return
	var r := focus.get_global_rect()
	# The ring layer is screen space; a button inside a scaled / scrolled canvas reports
	# canvas coordinates, so map it through its canvas transform first.
	var xf := focus.get_global_transform_with_canvas()
	r = Rect2(xf.origin, r.size * xf.get_scale())
	if _ring == null or not is_instance_valid(_ring):
		_ring = UIKit.add_selection_ring_rect(_ring_layer, r)
	_ring.visible = true
	UIKit.place_selection_ring(_ring, r)
