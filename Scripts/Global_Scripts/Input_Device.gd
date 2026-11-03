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
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	# A popup is a new CanvasLayer: once its children are in (end of frame), pull the
	# cursor into it - see _enter_trap().
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is CanvasLayer and n != _ring_layer:
			_enter_trap.call_deferred())
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
		# ISSUE #418: Shift / Ctrl / Alt / Caps / Escape / Delete are pressed alongside the mouse -
		# they leave the device as it is (a keyboard player stays on the keyboard too).
		if (event as InputEventKey).pressed and not UIInput.is_mouse_companion_key(event as InputEventKey):
			now = KEYBOARD
		elif (event as InputEventKey).pressed and not (event as InputEventKey).echo and last == MOUSE:
			print("ISSUE #418 FIX ACTIVE: ", OS.get_keycode_string((event as InputEventKey).keycode), " kept mouse mode")
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
	# Pad Y / Q: jump the cursor to the screen's main action (Buy, Save, Sell...) - the menu twin of
	# the match's "Y jumps to End Turn". Long grids (400+ coins) would otherwise take dozens of presses.
	if UIInput.is_end_turn_jump(event):
		var main_btn := _primary_action_button()
		if main_btn != null:
			main_btn.grab_focus()
			get_viewport().set_input_as_handled()
		return
	if UIInput.nav_direction(event) == Vector2i.ZERO:
		return
	var vp := get_viewport()
	if vp.gui_get_focus_owner() != null:
		return
	# A popup just closed: back onto whatever the cursor was on before it opened.
	var btn: Control = null
	if _pre_trap_focus != null and is_instance_valid(_pre_trap_focus) \
			and _pre_trap_focus.is_visible_in_tree() and _trap_root() == null:
		btn = _pre_trap_focus
	_pre_trap_focus = null
	if btn == null:
		btn = _first_menu_button()
	if btn == null:
		return
	btn.grab_focus()
	vp.set_input_as_handled()


## The top-left focusable control (a button or a UIKit nav tile) of the top-most
## layer that has any - or of the active focus scope, when a popup has pushed one.
## Returns null when there is no menu up - the overworld's own controls are left
## alone unless its pause menu overlay is open.
func _first_menu_button() -> Control:
	var root: Node = _search_root()
	if root == null:
		return null
	var scope := _trap_root()
	if scope != null:
		root = scope
	return first_focusable_in(root)


## The enabled, visible button styled as the screen's go-ahead action (variant good / primary /
## selected - see UIKit.style_button), lowest on the screen (the footer). Inside a popup, its own.
func _primary_action_button() -> Control:
	var root: Node = _search_root()
	if root == null:
		return null
	var trap := _trap_root()
	if trap != null:
		root = trap
	var found: Array = []
	_collect_buttons(root, found)
	var best: Control = null
	for b in found:
		if not (b is Button):
			continue
		var v := String((b as Button).get_meta("ui_variant", ""))
		if not v in ["good", "primary", "selected"]:
			continue
		if best == null or (b as Control).global_position.y > best.global_position.y:
			best = b
	return best


## The node the menu-focus search starts from: the current scene when it is a menu
## (a Control), or the map's pause-menu overlay when one is open.
func _search_root() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	if scene is Control:
		return scene
	var overlay = scene.get("_menu_canvas_layer")
	if overlay == null or not is_instance_valid(overlay):
		return null
	return overlay


## The top-left focusable control under `root`, on the highest layer that has one.
func first_focusable_in(root: Node) -> Control:
	var buttons: Array = []
	_collect_buttons(root, buttons)
	if buttons.is_empty():
		return null
	var top_layer := -100000
	for b in buttons:
		top_layer = maxi(top_layer, _layer_of(b))
	var best: Control = null
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


## Buttons and UIKit nav tiles - everything the menu cursor can land on.
func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var b := child as BaseButton
			if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
				out.append(b)
		elif child is Control and child.has_meta(UIKit.NAV_TILE_META):
			var c := child as Control
			if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
				out.append(c)
		_collect_buttons(child, out)


# ── Focus scopes (popups) ────────────────────────────────────────────────────
# Godot's focus navigation is purely geometric: from a popup's bottom button the
# next press down happily lands on a card in the grid BEHIND the dimmed popup, and
# A then presses something the player can't see. Two things keep the cursor inside
# whatever is on top:
#   - AUTOMATIC: the top-most visible CanvasLayer that holds a focusable control.
#     Every popup in the game (load deck, confirms, rename, shop reveals, the quit
#     dialog) is its own CanvasLayer above the screen, so they are all covered with
#     no per-popup code.
#   - MANUAL: push_scope(node) / pop_scope(node) for an overlay that is NOT its own
#     CanvasLayer. The newest valid, visible scope wins over the automatic one.
# Focus that tries to leave the trap is put back where it was (so the cursor stops
# at the popup's edge), or onto the popup's first control.
var _scopes: Array = []
var _last_in_trap: Control = null
## The control focused (behind the popup) when the last popup opened - the cursor
## goes back to it on the first direction press after the popup closes.
var _pre_trap_focus: Control = null


func push_scope(root: Node) -> void:
	if root == null or root in _scopes:
		return
	_scopes.append(root)
	_enter_trap.call_deferred()


func pop_scope(root: Node) -> void:
	_scopes.erase(root)


func _active_scope() -> Node:
	for i in range(_scopes.size() - 1, -1, -1):
		var s = _scopes[i]
		if not is_instance_valid(s) or not s.is_inside_tree():
			_scopes.remove_at(i)
			continue
		if _node_visible(s):
			return s
	return null


func _node_visible(n: Node) -> bool:
	if n is CanvasItem:
		return (n as CanvasItem).is_visible_in_tree()
	if n is CanvasLayer:
		return (n as CanvasLayer).visible
	return true


## Where focus must stay right now, or null when it may go anywhere.
func _trap_root() -> Node:
	var s := _active_scope()
	if s != null:
		return s
	var root := _search_root()
	if root == null or _is_match(root):
		return null
	var layers: Array = []
	_collect_layers(root, layers)
	var best: CanvasLayer = null
	for l in layers:
		var layer := l as CanvasLayer
		if not layer.visible or (best != null and layer.layer <= best.layer):
			continue
		var found: Array = []
		_collect_buttons(layer, found)
		if not found.is_empty():
			best = layer
	if best == null:
		return null
	# A screen whose own controls all live on that one layer is not a popup - nothing to trap.
	var outside: Array = []
	_collect_buttons_outside(root, best, outside)
	return best if not outside.is_empty() else null


## The match board drives its own cursor (Board_Nav.gd) and adds CanvasLayers for
## its card animations all the time - the automatic popup trap stays out of it.
func _is_match(root: Node) -> bool:
	var scr: Script = root.get_script()
	return scr != null and scr.resource_path.ends_with("Main_Match_Core_Gameplay_Script.gd")


func _collect_layers(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			out.append(child)
		_collect_layers(child, out)


func _collect_buttons_outside(node: Node, skip: Node, out: Array) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child is BaseButton:
			var b := child as BaseButton
			if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
				out.append(b)
				return
		elif child is Control and child.has_meta(UIKit.NAV_TILE_META):
			if (child as Control).is_visible_in_tree():
				out.append(child)
				return
		_collect_buttons_outside(child, skip, out)
		if not out.is_empty():
			return


## A popup just opened: a keyboard / pad player's cursor moves into it, and a mouse
## player's stale focus behind it is dropped (or A / Space would press it unseen).
func _enter_trap() -> void:
	var trap := _trap_root()
	if trap == null:
		return
	var f: Control = get_viewport().gui_get_focus_owner()
	if f != null and trap.is_ancestor_of(f):
		return
	if f != null:
		_pre_trap_focus = f
	if using_nav():
		var first := first_focusable_in(trap)
		if first != null:
			first.grab_focus()
			return
	if f != null:
		f.release_focus()


func _on_focus_changed(c: Control) -> void:
	if c == null:
		return
	var trap := _trap_root()
	if trap == null:
		_last_in_trap = null
		return
	if trap.is_ancestor_of(c):
		_last_in_trap = c
		return
	# Escaped the popup: back to where it was, or onto the popup's first control.
	var back: Control = _last_in_trap
	if back == null or not is_instance_valid(back) or not trap.is_ancestor_of(back) \
			or not back.is_visible_in_tree():
		back = first_focusable_in(trap)
	if back != null:
		back.grab_focus.call_deferred()
	else:
		c.release_focus.call_deferred()


func _layer_of(c: CanvasItem) -> int:
	var layer := c.get_canvas_layer_node()
	return layer.layer if layer != null else 0


func _process(_delta: float) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	var show := using_nav() and focus != null and focus.is_visible_in_tree() \
		and (focus is BaseButton or focus.has_meta(UIKit.NAV_TILE_META))
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
