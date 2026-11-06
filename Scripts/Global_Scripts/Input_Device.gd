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

## ISSUE #447: the blip only sounds for a focus change that follows a direction press this recently.
const NAV_BLIP_WINDOW_MS := 250
var _last_nav_press_ms: int = -100000
var _last_focus_blip: Control = null
## ISSUE #451: the menu ring sits this many px OUTSIDE the item's edge, so it frames it
## rather than covering its border. TWEAKABLE.
const NAV_RING_GAP := 4.0


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

	# Long press = preview, two-finger tap = back (Touch_Gestures.gd). A root child of its
	# own (not ours) so it can keep itself LAST and see every event first.
	var touch := Node.new()
	touch.name = "TouchGestures"
	touch.set_script(load("res://Scripts/Global_Scripts/Touch_Gestures.gd"))
	get_tree().root.add_child.call_deferred(touch)
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
			if e is InputEventJoypadButton and e.button_index == pair[1] and e.device == -1:
				already = true
		if not already:
			var ev := InputEventJoypadButton.new()
			ev.button_index = pair[1]
			# -1 = ANY controller. A new event defaults to device 0, so only the FIRST pad
			# Windows listed pressed ui_accept / ui_cancel - a second or virtual one (a
			# Moonlight / Sunshine stream pad) got no A in the overworld or on focused
			# buttons, while the match (UIInput.is_accept, any device) still worked.
			ev.device = -1
			InputMap.action_add_event(action, ev)


func _on_window_input(event: InputEvent) -> void:
	if UIInput.nav_direction(event) != Vector2i.ZERO:
		_last_nav_press_ms = Time.get_ticks_msec()
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

## ISSUE #452: inside a grid (deck builder cards, coins, sleeves, costumes...) the arrows / D-pad
## move exactly one cell: left / right along the row, up / down a whole row, by the grid's own
## index order. Godot's geometric search drifted diagonally and jumped over gaps. At the grid's
## edge (no cell that way) the press falls through to the normal geometric search, which is
## how the cursor leaves the grid for the buttons around it.
func _input(event: InputEvent) -> void:
	if _menu_shortcut(event):
		return
	var dir := UIInput.nav_direction(event)
	if dir == Vector2i.ZERO:
		return
	var f: Control = get_viewport().gui_get_focus_owner()
	if f == null or not f.is_visible_in_tree():
		return
	var target := _grid_step(f, dir)
	if target != null:
		print("ISSUE #452 FIX ACTIVE: grid step ", dir, " -> ", target.name)
		target.grab_focus()
		get_viewport().set_input_as_handled()
		return
	_human_step_input(f, dir)


# ── Human-expected menu movement ─────────────────────────────────────────────
# Godot's own focus search picks oddly in real screens: it counts cards scrolled out of
# sight, jumps rows on a left/right press, and from a side button dives into a grid instead
# of going to the next button. Every menu (not the match board, which has Board_Nav) moves
# by this instead:
#   - LEFT / RIGHT only move within the row (the target must share height with the focus);
#   - UP / DOWN go to the next row first (NAV_ROW_WEIGHT), ties to the left-aligned item;
#   - a target must be genuinely past that edge (NAV_EDGE_TOL), and mostly in view
#     (NAV_MIN_VISIBLE) - a card peeking out under the footer is not "below";
#   - hopping DIAGONALLY between a scrolling list and the panels round it costs extra
#     (NAV_GROUP_PENALTY), and inside one grid only the cell in line counts;
#   - nothing that way = the cursor stays where it is (no wrap-around surprises);
#   - controls clipped out of a scroll box don't count (a grid cell is reached by the grid
#     step above, which scrolls as it goes).
# Left alone: hand-wired neighbours (focus_neighbor_* set - the pause menu's two columns),
# text fields, and left / right on a slider (that changes its value).
## TWEAKABLE: on an up / down press, how much each px down the screen costs against each px
## sideways (higher = the next row wins more readily).
const NAV_ROW_WEIGHT := 3.0
## TWEAKABLE: on a left / right press the target must share at least this much of the shorter
## one's height with the focus to count as "in the same row".
const NAV_ROW_OVERLAP := 0.3
## TWEAKABLE: extra "distance" for leaving / entering a scrolling list (see _human_step).
const NAV_GROUP_PENALTY := 1000.0
## TWEAKABLE: px a target may overlap the focus's edge and still count as "that way".
const NAV_EDGE_TOL := 10.0

func _human_step_input(f: Control, dir: Vector2i) -> void:
	var root: Node = _trap_root()
	if root == null:
		root = _search_root()
	if root == null or _is_match(root) or not root.is_ancestor_of(f):
		return
	if f is LineEdit or f is TextEdit:
		return
	if f is Range and dir.x != 0:
		return
	var side := ""
	if dir.x > 0: side = "focus_neighbor_right"
	elif dir.x < 0: side = "focus_neighbor_left"
	elif dir.y > 0: side = "focus_neighbor_bottom"
	else: side = "focus_neighbor_top"
	if not String(f.get(side)).is_empty():
		return   # hand-wired: Godot follows it
	var target := _human_step(f, Vector2(dir), root)
	get_viewport().set_input_as_handled()
	if target != null:
		target.grab_focus()


func _human_step(f: Control, v: Vector2, root: Node) -> Control:
	var all: Array = []
	_collect_buttons(root, all)
	var a := _visible_rect(f)
	if a.size == Vector2.ZERO:
		a = f.get_global_rect()
	var f_group: Node = _scroll_group(f)
	var f_grid: Node = _grid_of(f)
	var best: Control = null
	var best_s := INF
	for c in all:
		if c == f or not _on_screen(c):
			continue
		var b: Rect2 = _visible_rect(c)   # measured from what the player can SEE of it
		var dc: Vector2 = b.get_center() - a.get_center()
		if dc.dot(v) <= 4.0:
			continue
		# It has to be genuinely PAST that edge of the focus (a little overlap allowed) - the
		# button diagonally below-left is not "to the left".
		if (v.x < 0.0 and b.end.x > a.position.x + NAV_EDGE_TOL) \
				or (v.x > 0.0 and b.position.x < a.end.x - NAV_EDGE_TOL) \
				or (v.y < 0.0 and b.end.y > a.position.y + NAV_EDGE_TOL) \
				or (v.y > 0.0 and b.position.y < a.end.y - NAV_EDGE_TOL):
			continue
		var s: float
		if v.x != 0.0:
			# LEFT / RIGHT stay in the row: the target must share some height with the focus.
			# Off the end of a row the cursor stays put rather than hopping up or down a row.
			var overlap: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
			if overlap < minf(a.size.y, b.size.y) * NAV_ROW_OVERLAP:
				continue
			var prim_x: float = maxf(0.0, (b.position.x - a.end.x) if v.x > 0.0 else (a.position.x - b.end.x))
			# Ties go to the one whose TOP edge lines up (the first of a stack beside it).
			s = prim_x + absf(b.position.y - a.position.y) * 0.05
		else:
			# UP / DOWN go to the NEXT row first: distance down the screen counts more than a
			# sideways offset, so a row whose buttons sit a little to one side still wins over a
			# button directly underneath three rows further on.
			var prim_y: float = maxf(0.0, (b.position.y - a.end.y) if v.y > 0.0 else (a.position.y - b.end.y))
			var perp_x: float = maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
			# Ties (several things straight below) go to the one whose LEFT edge lines up - menu rows
			# are left-aligned, so down from a wide slider lands on the next row's first option.
			s = prim_y * NAV_ROW_WEIGHT + perp_x + absf(b.position.x - a.position.x) * 0.05
			# Inside one grid the grid step already took the cell straight below/above; a cell
			# that is NOT in line (the lone coin at the far end of a short last row) is not "down".
			if perp_x > 0.0 and f_grid != null and _grid_of(c) == f_grid:
				continue
			# Crossing DIAGONALLY between a scrolling list (the card grid, the coin grid...) and the
			# panels round it costs extra, so the cursor keeps to the area it is in while there is
			# something there: up from View Deck goes up the side panel, not into the card beside
			# it. Straight up / down into the list (Cancel -> the coin above it) is not penalised.
			if perp_x > 0.0 and _scroll_group(c) != f_group:
				s += NAV_GROUP_PENALTY
		if s < best_s:
			best_s = s
			best = c
	return best


## The part of `c` actually on screen: clipped by every scroll box / clipping ancestor and by
## the window. Empty when it is out of sight.
func _visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p: Node = c.get_parent()
	while p != null and p is Control:
		var pc := p as Control
		if pc is ScrollContainer or pc.clip_contents:
			r = r.intersection(pc.get_global_rect())
			if r.size.x < 1.0 or r.size.y < 1.0:
				return Rect2()
		p = p.get_parent()
	return r.intersection(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))


## TWEAKABLE: share of a control (each way) that must be showing for the cursor to go to it -
## a card row peeking out under the footer is not "the thing below".
const NAV_MIN_VISIBLE := 0.4

## Mostly in sight: scrolled, clipped or pushed off the window it does not count.
func _on_screen(c: Control) -> bool:
	var full := c.get_global_rect()
	var r := _visible_rect(c)
	if full.size.x <= 0.0 or full.size.y <= 0.0:
		return false
	return r.size.x >= full.size.x * NAV_MIN_VISIBLE and r.size.y >= full.size.y * NAV_MIN_VISIBLE


## Menu button shortcuts (UIKit.set_shortcut): presses the tagged button whose pad button or key
## this is, on the screen (or popup) that is up. Not in the match - it has its own (Board_Nav).
func _menu_shortcut(event: InputEvent) -> bool:
	var pad := -1
	var key := -1
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		pad = (event as InputEventJoypadButton).button_index
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
			return false
		# Typing wins: a focused text box or the on-screen keyboard takes letters as letters.
		var fo: Control = get_viewport().gui_get_focus_owner()
		if fo is LineEdit or fo is TextEdit or OnScreenKeyboard.is_open():
			return false
		key = k.keycode
	else:
		return false
	var root: Node = _trap_root()
	if root == null:
		root = _search_root()
	if root == null or _is_match(root):
		return false
	for b in root.find_children("*", "BaseButton", true, false):
		var btn := b as BaseButton
		if not btn.has_meta("sc_pad") or btn.disabled or not btn.is_visible_in_tree():
			continue
		var hit: bool = (pad != -1 and int(btn.get_meta("sc_pad")) == pad) \
			or (key != -1 and key in (btn.get_meta("sc_keys", []) as Array))
		if hit:
			print("MENU SHORTCUT: ", btn.name)
			get_viewport().set_input_as_handled()
			btn.pressed.emit()
			return true
	return false


func _grid_step(f: Control, dir: Vector2i) -> Control:
	# The grid cell holding the focus: the focus itself, or an ancestor a few levels up.
	var cell: Control = f
	var grid: GridContainer = null
	for _i in range(4):
		if cell == null:
			return null
		if cell.get_parent() is GridContainer:
			grid = cell.get_parent() as GridContainer
			break
		cell = cell.get_parent() as Control
	if grid == null:
		return null
	var cells: Array = []
	for ch in grid.get_children():
		if ch is Control and (ch as Control).visible and not ch.is_queued_for_deletion():
			cells.append(ch)
	var idx := cells.find(cell)
	var cols := maxi(grid.columns, 1)
	var n := cells.size()
	if idx < 0:
		return null
	var to := -1
	if dir.x > 0 and idx % cols < cols - 1 and idx + 1 < n:
		to = idx + 1
	elif dir.x < 0 and idx % cols > 0:
		to = idx - 1
	elif dir.y > 0:
		if idx + cols < n:
			to = idx + cols
		# (No cell directly below - a short last row, or the bottom: the human-expected step
		# decides, so a far-off last cell competes fairly with the buttons below the grid.)
	elif dir.y < 0 and idx - cols >= 0:
		to = idx - cols
	if to < 0:
		return null
	return _focusable_in_cell(cells[to])


func _focusable_in_cell(c: Control) -> Control:
	if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c.has_meta(UIKit.NAV_TILE_META)):
		return c
	var found: Array = []
	_collect_buttons(c, found)
	return found[0] if not found.is_empty() else null


func _unhandled_input(event: InputEvent) -> void:
	# Pad Start on a sub-menu (sleeves, coins, costumes, options...): the first press jumps the cursor
	# to the screen's Save / main action, the next press (or A) confirms it. The pause menu and the
	# match use Start themselves and consume it before it gets here; the overworld has no menu root.
	if UIInput.is_pause(event):
		var root := _search_root()
		if root != null and not _is_match(root):
			var main_btn := _primary_action_button()
			if main_btn != null:
				var f: Control = get_viewport().gui_get_focus_owner()
				if f == main_btn and main_btn is BaseButton and not (main_btn as BaseButton).disabled:
					print("PAD START: confirming ", main_btn.name)
					(main_btn as BaseButton).pressed.emit()
				else:
					main_btn.grab_focus()
				get_viewport().set_input_as_handled()
		return
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
	# ISSUE #449: a sub-menu (sleeves, coins, costumes, options, info...) opened from the pause
	# menu is its OWN layer over the map, and the pause menu's layer is merely hidden behind it.
	# The search used to start from that hidden layer, find nothing visible, and so the first
	# D-pad press on every sub-menu did nothing. The sub-menu's layer wins while it is up.
	var sub = scene.get("_submenu_canvas_layer")
	if sub != null and is_instance_valid(sub) and (sub as CanvasLayer).visible:
		return sub
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
		elif child is Control and (child.has_meta(UIKit.NAV_TILE_META) or child is Range):
			# Range: the Options volume sliders are cursor stops too.
			var c := child as Control
			if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE \
					and not (c is ScrollBar):
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
	# ISSUE #447: the quiet blip whenever the keyboard / pad cursor moves to something new.
	# Only on a REAL move: a screen focusing its own selected item on open (no input yet) is silent.
	if using_nav() and _last_focus_blip != c and Time.get_ticks_msec() - _last_nav_press_ms < NAV_BLIP_WINDOW_MS:
		# 2026-11-05 retest: the lower, softer plus_select blip (the menus' own click sound), not Select_Change.
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_last_focus_blip = c
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


## A menu that has just opened (a new scene, or a sub-menu layer over the map) starts with the
## cursor on its top-left control when the player is on keys / pad - nothing highlighted until
## the first press looked broken. Waits a few frames so a screen that focuses its own item (the
## coin / sleeve / costume pick, the deck builder's first card) gets there first.
var _last_nav_root: Node = null
var _autofocus_frames: int = 0
const AUTOFOCUS_DELAY_FRAMES := 4

func _autofocus_new_menu() -> void:
	var root: Node = _search_root()
	if root != _last_nav_root:
		_last_nav_root = root
		_autofocus_frames = AUTOFOCUS_DELAY_FRAMES
	if _autofocus_frames <= 0:
		return
	_autofocus_frames -= 1
	if _autofocus_frames > 0 or root == null or not is_instance_valid(root) or _is_match(root) or not using_nav():
		return
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo != null and fo.is_visible_in_tree():
		return
	var first := first_focusable_in(root)
	if first != null:
		first.grab_focus()


func _process(_delta: float) -> void:
	_autofocus_new_menu()
	var focus: Control = get_viewport().gui_get_focus_owner()
	var show := using_nav() and focus != null and focus.is_visible_in_tree() \
		and (focus is BaseButton or focus.has_meta(UIKit.NAV_TILE_META) or (focus is Range and not focus is ScrollBar)) \
		and not focus.has_meta("own_ring")   # ISSUE #447: the tile draws its own ring (pause menu)
	if not show:
		if _ring != null:
			_ring.visible = false
		return
	# The ring layer is screen space; a button inside a scaled / scrolled canvas reports
	# canvas coordinates, so map it through its canvas transform first. ISSUE #447: a picture
	# tile is framed round its ART (a keep-aspect texture is often smaller than its node).
	var local := Rect2(Vector2.ZERO, focus.size)
	if focus is TextureRect:
		var tr := focus as TextureRect
		var art: Rect2 = UIKit.drawn_texture_rect(tr)
		var gxf := tr.get_global_transform()
		local = Rect2(gxf.affine_inverse() * art.position, art.size / gxf.get_scale())
	var xf := focus.get_global_transform_with_canvas()
	var r := Rect2(xf * local.position, local.size * xf.get_scale()).grow(NAV_RING_GAP)
	if _ring == null or not is_instance_valid(_ring):
		_ring = UIKit.add_selection_ring_rect(_ring_layer, r)
		UIKit.strengthen_ring(_ring)   # ISSUE #451
	_ring.visible = true
	UIKit.place_selection_ring(_ring, r)
	# ISSUE #447: the ring's corners follow the item's own. A tile can say how round its art is
	# (ring_radius_frac, a share of its width - the pause menu's boxes); otherwise the theme radius.
	var radius: float = UITheme.m("corner_radius")
	if focus.has_meta("ring_radius_frac"):
		radius = minf(r.size.x, r.size.y) - NAV_RING_GAP * 2.0
		radius *= float(focus.get_meta("ring_radius_frac"))   # a share of the SHORTER side
	UIKit.set_ring_radius(_ring, radius + NAV_RING_GAP)


## The scroll box (or self-clipping list, like the deck builder's card grid) `c` sits in, or
## null - the "area" for NAV_GROUP_PENALTY.
func _scroll_group(c: Node) -> Node:
	var p: Node = c.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			return p
		p = p.get_parent()
	return null


## The GridContainer `c` is a cell of (itself or a few levels up), or null.
func _grid_of(c: Node) -> Node:
	var n: Node = c
	for _i in range(4):
		if n == null:
			return null
		if n.get_parent() is GridContainer:
			return n.get_parent()
		n = n.get_parent()
	return null
