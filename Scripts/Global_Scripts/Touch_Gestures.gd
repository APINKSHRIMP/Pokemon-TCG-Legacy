extends Node

# ============================================================
# TOUCH GESTURES - play by finger (a phone streaming the game, or a touch screen)
# ============================================================
# Made by InputDevice at startup and kept as the LAST child of the tree root, so its
# _input sees every event before any scene does. Godot turns the first finger into the
# mouse by itself (emulate_mouse_from_touch), so taps are clicks and drags are drags
# already - this adds the two things a finger cannot do with a mouse's buttons:
#
#   LONG PRESS = PREVIEW (on the open overworld map: the MENU - the touch Escape). Hold a finger (or the left button) still on something for
#     LONG_PRESS_TIME: it is enlarged exactly as holding Shift does (a virtual Shift is
#     held down, so every screen's existing preview opens - match cards, the deck
#     builder, coins, sleeves, costumes, the field guide). Lift the finger to close it.
#     That release never counts as a click: Hand_Drag forgets the press and the release
#     is moved off-screen, so buttons and cards under the finger do not fire.
#
#   TWO-FINGER TAP = CANCEL / BACK. A second finger down and both up quickly without
#     sliding sends Escape - the same as the back key everywhere (in a match with nothing
#     to back out of, that opens the pause menu). Needs real touch: a streaming app that
#     passes touches through (Moonlight ZWM does), or a touch screen.
#
# Escape and Shift are "mouse companion" keys (UIInput), so neither flips the game into
# keyboard mode and no cursor rings appear.
# ============================================================

# -- TWEAKABLE ------------------------------------------------
const LONG_PRESS_TIME := 0.45      # seconds held still before the preview opens
const LONG_PRESS_MOVE := 14.0      # px the finger may drift and still count as "still"
const TWO_FINGER_TIME := 0.35      # seconds from second finger down to both up
const TWO_FINGER_MOVE := 30.0      # px either finger may slide and still be a tap

var _press_at: Vector2 = Vector2.ZERO
var _press_ms: int = -1            # -1 = no left press being timed
var _long_fired := false
var _long_menu := false            # the hold opened the overworld menu: swallow the lift

var _touch_down: Dictionary = {}   # finger index -> start position
var _two_ms: int = -1              # when the second finger landed (-1 = none)
var _two_cancelled := false
var _two_fired := false            # the tap went through: swallow the first finger's release


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_stay_last()
	# The finger is up but its release never reached here (the match intro overlay swallows
	# every input while it runs, a scene change, an alt-tab): disarm, and let go of the virtual
	# Shift if it was holding a preview open - otherwise the preview sticks and follows the
	# finger round the hand.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _long_fired:
			print("TOUCH: release missed - closing the preview")
			_send_key(KEY_SHIFT, false)
			_long_fired = false
		_press_ms = -1
		return
	if _press_ms >= 0 and not _long_fired and _two_ms < 0 \
			and Time.get_ticks_msec() - _press_ms >= int(LONG_PRESS_TIME * 1000.0):
		_fire_long_press()


## _input runs last-child-first: stay at the end of the root so this sees events before
## any scene. The match transition overlay also wants to be last while it runs (it swallows
## everything anyway), so it is left there.
func _stay_last() -> void:
	var root := get_parent()
	if root == null:
		return
	var last := root.get_child(root.get_child_count() - 1)
	if last != self and not (last is MatchTransition):
		root.move_child(self, -1)


func _input(event: InputEvent) -> void:
	_track_pointer_visibility(event)
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touch_down.has(d.index) and d.position.distance_to(_touch_down[d.index]) > TWO_FINGER_MOVE:
			_two_cancelled = true
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_ms >= 0 and not _long_fired and mm.position.distance_to(_press_at) > LONG_PRESS_MOVE:
			_press_ms = -1   # it moved: a drag, not a long press
			if _scroll_box != null and not _scrolling and _two_ms < 0:
				_scrolling = true
				_scroll_rest = Vector2.ZERO
				# Whatever the press started (a card pick-up in the match) is a scroll now.
				var hd = _hand_drag()
				if hd != null:
					hd.cancel_press()
				print("TOUCH: drag -> scroll ", _scroll_box.name)
		if _scrolling and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_scroll_by(mm.relative)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		# Never start a new gesture with the last one's virtual Shift still down.
		if _long_fired:
			_send_key(KEY_SHIFT, false)
		_press_at = mb.position
		_press_ms = Time.get_ticks_msec()
		_long_fired = false
		_scrolling = false
		_scroll_box = _scroll_box_under(mb.position)
		return
	# Left release. Godot sends the first finger's mouse release BEFORE its touch release, so a
	# two-finger gesture still in progress (_two_ms set) must swallow it too, or the tap lands as
	# a click under the first finger. A drag that scrolled is not a click either.
	var swallow := _long_fired or _long_menu or _two_fired or _two_ms >= 0 or _scrolling
	_scrolling = false
	_scroll_box = null
	_long_menu = false
	if _long_fired:
		_send_key(KEY_SHIFT, false)   # closes the preview
	_press_ms = -1
	_long_fired = false
	_two_fired = false
	if swallow:
		_forget_click(mb)


## MOUSE POINTER ON TOUCH. A finger has no pointer, so the arrow left sitting where the last
## tap landed is just clutter on a phone stream. A real touch (InputEventScreenTouch) hides the
## pointer; the real mouse moving shows it again. Godot's own touch-made mouse events carry
## DEVICE_ID_EMULATION, so they never count as "the mouse moved".
func _track_pointer_visibility(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_set_pointer_visible(false)
		return
	if event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION \
				and (event as InputEventMouseMotion).relative.length() > 0.0:
			_set_pointer_visible(true)


func _set_pointer_visible(show: bool) -> void:
	var want := Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touch_down[t.index] = t.position
		if _touch_down.size() == 2:
			_two_ms = Time.get_ticks_msec()
			_two_cancelled = false
			_press_ms = -1   # a second finger is never a long press
		elif _touch_down.size() > 2:
			_two_cancelled = true
		return
	_touch_down.erase(t.index)
	if _touch_down.is_empty() and _two_ms >= 0:
		var quick: bool = Time.get_ticks_msec() - _two_ms <= int(TWO_FINGER_TIME * 1000.0)
		if quick and not _two_cancelled:
			print("TOUCH: two-finger tap -> back")
			_two_fired = true
			# Deferred: the first finger's mouse release is still on its way and the match
			# ignores Escape mid-click - send it once that release has gone through.
			_send_back.call_deferred()
		_two_ms = -1


## PRESS AND DRAG = SCROLL (finger or mouse). A press inside a scrolling list or grid that
## slides past LONG_PRESS_MOVE drags it - up / down and left / right - the content following
## the finger like a phone. The release is swallowed, so a scroll never presses the card or
## button it started on. Holding still is still the long-press preview; tapping still clicks.
## Not started on sliders or text boxes (they drag / select themselves), and not where Godot
## already drag-scrolls a touchscreen by itself (it would scroll twice).
const SCROLL_SPEED := 1.0          # TWEAKABLE: content px moved per finger px

var _scrolling := false
var _scroll_box: ScrollContainer = null
var _scroll_rest := Vector2.ZERO   # sub-pixel remainder (scroll values are whole pixels)


## The ScrollContainer a press here would drag, or null: the nearest one round the control
## under the pointer, else the last-drawn visible one that holds the point (popups are added
## after the screen under them, so last = top-most). It must have something to scroll.
func _scroll_box_under(at: Vector2) -> ScrollContainer:
	if DisplayServer.is_touchscreen_available():
		return null
	# A finger's tap arrives with no motion before it, so the hovered control can still be the
	# one under the LAST tap - only trust it when it is really under this press.
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and not hovered.get_global_rect().has_point(at):
		hovered = null
	if hovered is Range or hovered is LineEdit or hovered is TextEdit:
		return null
	var box := _find_scroll_box(hovered, at)
	if box == null:
		return null
	var v := box.get_v_scroll_bar()
	var h := box.get_h_scroll_bar()
	var can_v: bool = v != null and v.max_value - v.page > 0.5
	var can_h: bool = h != null and h.max_value - h.page > 0.5
	return box if can_v or can_h else null


func _find_scroll_box(hovered: Control, at: Vector2) -> ScrollContainer:
	var n: Node = hovered
	while n != null:
		if n is ScrollContainer and (n as ScrollContainer).is_visible_in_tree():
			return n as ScrollContainer
		n = n.get_parent()
	var found: ScrollContainer = null
	for s in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var sc := s as ScrollContainer
		if sc.is_visible_in_tree() and sc.get_global_rect().has_point(at):
			found = sc
	return found


func _scroll_by(finger_move: Vector2) -> void:
	if _scroll_box == null or not is_instance_valid(_scroll_box) or not _scroll_box.is_visible_in_tree():
		return
	# Fingers up = content up = further down the list.
	_scroll_rest -= finger_move * SCROLL_SPEED
	var step := Vector2(roundf(_scroll_rest.x), roundf(_scroll_rest.y))
	_scroll_rest -= step
	if step.y != 0.0:
		_scroll_box.scroll_vertical += int(step.y)
	if step.x != 0.0:
		_scroll_box.scroll_horizontal += int(step.x)


func _fire_long_press() -> void:
	# The match intro (or the way back) owns the screen: this hold is not a gesture. Disarm
	# rather than wait - waiting is how a press from tapping "Yes" fired once the intro ended.
	if MatchTransition.is_active() or MatchTransition.is_returning():
		_press_ms = -1
		return
	# On the open overworld map (player free to walk) a still hold OPENS THE MENU - the touch
	# stand-in for Escape. (A preview means nothing there, and its virtual Shift would make the
	# player run.) The lift that follows is swallowed, so it cannot tap a menu tile.
	var pl = MapManager.get("_player")
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree() and pl.get("can_move") == true \
			and not MapManager.overworld_paused:
		_press_ms = -1
		_long_menu = true
		print("TOUCH: long press on the map -> menu")
		_send_key(KEY_ESCAPE, true)
		_send_key(KEY_ESCAPE, false)
		return
	_long_fired = true
	print("TOUCH: long press -> preview")
	# The press may have started a pick-up / drag in the match: it is a preview now.
	var hd = _hand_drag()
	if hd != null:
		hd.cancel_press()
	_send_key(KEY_SHIFT, true)


## The finger's release after a gesture must not land as a click: the match's hand handler
## forgets the press, and the release itself is moved far off-screen - a Button only fires
## when released over itself, and the deck builder only adds a copy then too.
func _forget_click(mb: InputEventMouseButton) -> void:
	var hd = _hand_drag()
	if hd != null:
		hd.cancel_press()
	mb.position = Vector2(-100000.0, -100000.0)
	mb.global_position = mb.position


func _hand_drag() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var hd = scene.get("hand_drag")
	return hd if hd != null and is_instance_valid(hd) and hd.has_method("cancel_press") else null


func _send_key(key: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = down
	Input.parse_input_event(e)


func _send_back() -> void:
	await get_tree().process_frame
	_send_key(KEY_ESCAPE, true)
	_send_key(KEY_ESCAPE, false)
