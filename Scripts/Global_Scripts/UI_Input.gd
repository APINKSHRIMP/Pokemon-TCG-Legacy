class_name UIInput

# ============================================================
# UI INPUT — static utility
# ============================================================
# The single place that answers two questions about an InputEvent:
#
#   is_accept(event)   "yes / confirm / advance this message"
#   is_cancel(event)   "no / back out"
#   is_advance(event)  either of the above — used by plain OK messages,
#                      where both keys just dismiss the box
#   is_zoom_*(event)   "hold to enlarge whatever the mouse is over"
#   is_log_toggle(e)   "show / hide the in-match message history"
#
# Every message box, dialogue and yes/no prompt in the game routes its key
# handling through here rather than testing keycodes itself. Adding controller
# support later is then a change to these three functions and nothing else —
# the pad buttons are already wired below, so a connected pad works today.
#
# Bindings (the keyboard emulates every pad button, so the game plays the same
# on either - Options > Controls lists them for the player):
#   accept — Space, Enter, numpad Enter, pad A (cross)
#   cancel — Escape, Backspace, pad B (circle)
#   pause  — pad Start/Menu (Escape doubles as pause where nothing is left to cancel)
#   zoom   — Shift (held), pad L1  (the same button is RUN in the overworld)
#   log    — Caps Lock (toggle), pad Back/View (the phone map in the overworld)
#   move   — arrow keys, pad D-pad, pad left stick (nav_direction)
#   hand   — Tab, pad X   (in a match: jump the cursor to your hand)
#   end    — Q, pad Y     (in a match: jump the cursor to End Turn)
#   expand — Alt held + click on the hand opens the large hand view
#
# Two deliberate rules:
#   - Key repeat (is_echo) is ignored. Holding Space must not tear through a
#     queue of messages the player hasn't read.
#   - Only *pressed* events count, so a key released over a newly-opened box
#     can't dismiss it.
#
# NOTE: Space and Enter are also Godot's built-in "ui_accept" action, which
# presses whatever Control currently has focus. Callers that act on an accept
# must consume the event (get_viewport().set_input_as_handled()) or a focused
# button will fire a second time off the same keypress.
# ============================================================

const ACCEPT_KEYS: Array[int] = [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
const CANCEL_KEYS: Array[int] = [KEY_ESCAPE, KEY_BACKSPACE]
const ZOOM_KEYS: Array[int]   = [KEY_SHIFT]
const LOG_KEYS: Array[int]    = [KEY_CAPSLOCK]

static func is_accept(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in ACCEPT_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_A
	return false

static func is_cancel(event: InputEvent) -> bool:
	if event is InputEventKey:
		if not (_key_pressed(event) and event.keycode in CANCEL_KEYS):
			return false
		# Backspace deletes a letter while a text box (deck name, card search) is being
		# typed in - it only means "back" when nothing is being typed.
		if event.keycode == KEY_BACKSPACE and _text_field_focused():
			return false
		return true
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_B
	return false

# True for anything that should move a plain message along, whichever key it was.
static func is_advance(event: InputEvent) -> bool:
	return is_accept(event) or is_cancel(event)

# ── Message history ──────────────────────────────────────────────────────────
# Caps Lock opens and closes the in-match message log. It follows Shift (hold to
# preview a card) as the second "look at something without touching the board"
# key, and it is the only key on the board with no other job in the whole
# project — nothing anywhere reads KEY_CAPSLOCK.
#
# Two things to know about it. It is a TOGGLE key at the OS level, so pressing it
# also flips the machine's caps state; that is harmless here because a match has
# no text fields, but do not reuse this key on a screen that does. And it is
# edge-tested on the press only, exactly like accept/cancel, so holding it cannot
# strobe the panel open and shut.
static func is_log_toggle(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in LOG_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_BACK
	return false

# ── Mouse ────────────────────────────────────────────────────────────────────
# ISSUE #137: Godot delivers every mouse-wheel notch as an InputEventMouseButton with
# pressed == true, so the natural-looking test
#
#     if event is InputEventMouseButton and event.pressed:
#
# treats SCROLLING as a click. Anywhere a click dismisses a message box that meant a
# single flick of the wheel silently ate the message the player was still reading.
#
# is_click() is that test done properly and is the only form that should appear anywhere
# in the game: a real button went down, and it was not the wheel.
static func is_scroll(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	return (event as InputEventMouseButton).button_index in [
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
	]

# The middle button is excluded for the same reason as the wheel: it has no job
# anywhere in the game, and without this it falls through as a plain left-click —
# middle-clicking would acknowledge a message box or pick up a card. It is on the
# same physical control as the wheel, so a slightly heavy scroll press would fire
# an action the player never asked for.
static func is_inert_mouse_button(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		return true
	return is_scroll(event)

static func is_click(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	if not (event as InputEventMouseButton).pressed:
		return false
	return not is_inert_mouse_button(event)

# ── Hold-to-zoom ─────────────────────────────────────────────────────────────
# Every enlarge-a-card/coin/sleeve preview in the game is held on Shift, not Space.
# Space is the accept key above, so the two used to fight over the same press: holding
# it to preview a card also fired "ui_accept" on whichever button had focus, and in a
# match it would have advanced the message box you were trying to read the card for.
# Shift has no other job outside the overworld run key, so a preview can be opened at
# any moment — mid-message, mid-prompt — without disturbing what is on screen.
#
# Unlike accept/cancel these are edge tests on BOTH directions of one key, so they are
# deliberately not routed through _key_pressed: repeats (is_echo) are dropped on the
# press so a held key doesn't restart the preview every frame, while the release has
# no echo to worry about.
static func is_zoom_start(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.is_echo() and event.keycode in ZOOM_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER
	return false

static func is_zoom_end(event: InputEvent) -> bool:
	if event is InputEventKey:
		return not event.pressed and event.keycode in ZOOM_KEYS
	if event is InputEventJoypadButton:
		return not event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER
	return false

# Polled rather than event-driven, for the one case events can't cover: alt-tabbing
# away while the key is down eats the release, which would strand the preview overlay
# on screen. Callers check this each frame and close the preview if it comes back false.
static func is_zoom_held() -> bool:
	if Input.is_key_pressed(KEY_SHIFT):
		return true
	return Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)


static func _key_pressed(event: InputEventKey) -> bool:
	return event.pressed and not event.is_echo()


static func _text_field_focused() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var focus: Control = tree.root.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


# ── Pause / Start ────────────────────────────────────────────────────────────
# The pad's Start (Menu / Options) button. The keyboard has no key of its own for
# it: Escape is B, and each screen falls back to "pause" when B has nothing left to
# back out of.
static func is_pause(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_START
	return false


# ── Run ──────────────────────────────────────────────────────────────────────
# Hold-to-run in the overworld is the SAME button as hold-to-zoom everywhere else
# (Shift / pad L1): one binding, two contexts. Named for what the overworld does.
static func is_run_held() -> bool:
	return is_zoom_held()


# ── Phone map ────────────────────────────────────────────────────────────────
# M, or the pad's Back / View button (that button is the message log in a match).
const MAP_KEYS: Array[int] = [KEY_M]

static func is_world_map(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in MAP_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_BACK
	return false


# ── Match cursor shortcuts ───────────────────────────────────────────────────
# Pad X / Tab jumps the board cursor to your hand; pad Y / Q jumps it to End Turn
# (A then presses it - one button never ends a turn on its own). Neither key has
# another job in a match.
const HAND_JUMP_KEYS: Array[int] = [KEY_TAB, KEY_H]   # H added 2026-11-05 (H for Hand)
const END_TURN_JUMP_KEYS: Array[int] = [KEY_Q]

# 2026-11-05: three more match shortcuts on the pad's spare buttons.
#   F / pad RB       - jump the cursor to your Active's first action row (its attacks, Power,
#                      Retreat); A then opens / uses it. Falls back to your Active.
#   V / pad R3       - open YOUR Active's viewer (its Energy, tools, what it evolved from).
#   C                - open the OPPONENT's Active's viewer (keyboard only; on the pad the
#                      cursor + A already reaches it, and L3 is not worth the stretch).
const ATTACK_JUMP_KEYS: Array[int] = [KEY_F]
const VIEW_ACTIVE_KEYS: Array[int] = [KEY_V]
const VIEW_OPP_ACTIVE_KEYS: Array[int] = [KEY_C]

static func is_attack_jump(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in ATTACK_JUMP_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER
	return false

static func is_view_active(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in VIEW_ACTIVE_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK
	return false

static func is_view_opp_active(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in VIEW_OPP_ACTIVE_KEYS
	return false


# ── Menu button shortcuts ────────────────────────────────────────────────────
# A menu button tagged with UIKit.set_shortcut(button, pad, keys) is pressed by that pad
# button or any of those keys while its screen is up (InputDevice does the pressing). The pad
# buttons mean the same thing on every screen:
#   MENU_PAD_ALT  (Back / View / Create) - the screen's other view: Show all / owned, Search,
#                                          Controls, Field Guide
#   MENU_PAD_VIEW (RB / R1)              - "view": View Deck, View Bag
#   MENU_PAD_LOAD (R3)                   - "load": Load Deck, View Medals
const MENU_PAD_ALT := JOY_BUTTON_BACK
const MENU_PAD_VIEW := JOY_BUTTON_RIGHT_SHOULDER
const MENU_PAD_LOAD := JOY_BUTTON_RIGHT_STICK

static func is_hand_jump(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in HAND_JUMP_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_X
	return false

static func is_end_turn_jump(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in END_TURN_JUMP_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_Y
	return false


# ── Menu secondary action ────────────────────────────────────────────────────
# The pad / keyboard stand-in for a RIGHT click on a menu tile (the deck builder's
# "remove one copy"). Pad X, or X / Delete on the keyboard. Only tiles made with
# UIKit.make_nav_tile() listen for it, and only while they hold focus, so it never
# fights the match's X = "jump to hand" (the board has its own cursor).
const SECONDARY_KEYS: Array[int] = [KEY_X, KEY_DELETE]

static func is_secondary(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in SECONDARY_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_X
	return false


# ── Page step ────────────────────────────────────────────────────────────────
# "Previous / next page" on screens that page through something (the deck builder's
# card sets). Page Up / Page Down, or the pad's triggers (LT / RT, L2 / R2). The
# triggers are AXES in Godot, so they are edge-detected like the stick: one step per
# squeeze, re-armed once the trigger is let back out.
# Returns -1 (previous), +1 (next) or 0.
const TRIGGER_PRESS := 0.6
const TRIGGER_RELEASE := 0.3
static var _trigger_down := {JOY_AXIS_TRIGGER_LEFT: false, JOY_AXIS_TRIGGER_RIGHT: false}
static var _last_trigger_event: InputEvent = null
static var _last_trigger_result := 0

static func page_step(event: InputEvent) -> int:
	if event is InputEventKey:
		if not _key_pressed(event):
			return 0
		if event.keycode == KEY_PAGEUP:
			return -1
		if event.keycode == KEY_PAGEDOWN:
			return 1
		return 0
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if m.axis != JOY_AXIS_TRIGGER_LEFT and m.axis != JOY_AXIS_TRIGGER_RIGHT:
			return 0
		if event == _last_trigger_event:
			return _last_trigger_result
		_last_trigger_event = event
		_last_trigger_result = 0
		if m.axis_value < TRIGGER_RELEASE:
			_trigger_down[m.axis] = false
		elif m.axis_value >= TRIGGER_PRESS and not _trigger_down[m.axis]:
			_trigger_down[m.axis] = true
			_last_trigger_result = -1 if m.axis == JOY_AXIS_TRIGGER_LEFT else 1
		return _last_trigger_result
	return 0


# ── Alt + click: the old "open the hand large" click ─────────────────────────
# A plain click on a hand card picks it straight off the bar now (and a drag plays
# it). Holding Alt gives back the large hand view that click used to open.
static func is_hand_expand_held() -> bool:
	return Input.is_key_pressed(KEY_ALT)


# ── Keys that belong to the mouse ────────────────────────────────────────────
# ISSUE #418: keys a mouse player presses WITH the mouse - Shift (hold to zoom), Ctrl (debug
# reveal), Alt (Alt + click), the other modifiers, Caps Lock (log), Escape (pause) and Delete
# (debug menu). Pressing one never switches InputDevice to the keyboard, so no cursor ring
# appears and nothing gets "selected" by the keyboard cursor.
const MOUSE_COMPANION_KEYS: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_ESCAPE, KEY_DELETE]

static func is_mouse_companion_key(event: InputEventKey) -> bool:
	return event.keycode in MOUSE_COMPANION_KEYS or event.physical_keycode in MOUSE_COMPANION_KEYS


# ── Cursor movement ──────────────────────────────────────────────────────────
# One step of cursor movement from any device: an arrow key (key repeat allowed,
# so holding one keeps moving), the D-pad, or a flick of the left stick. Returns
# Vector2i.ZERO for anything else.
#
# The stick is edge-detected: one step when it crosses STICK_PRESS, re-armed once
# it falls back under STICK_RELEASE - so a flick is one step, not one per motion
# event. Several listeners may ask about the same motion event, so the answer is
# cached per event and the edge is only spent once.
const STICK_PRESS := 0.55
const STICK_RELEASE := 0.3

static var _stick_dir := Vector2i.ZERO
static var _last_motion: InputEvent = null
static var _last_motion_result := Vector2i.ZERO

static func nav_direction(event: InputEvent) -> Vector2i:
	if event is InputEventKey:
		if not event.pressed:
			return Vector2i.ZERO
		match event.keycode:
			KEY_LEFT:  return Vector2i.LEFT
			KEY_RIGHT: return Vector2i.RIGHT
			KEY_UP:    return Vector2i.UP
			KEY_DOWN:  return Vector2i.DOWN
		return Vector2i.ZERO
	if event is InputEventJoypadButton:
		if not event.pressed:
			return Vector2i.ZERO
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT:  return Vector2i.LEFT
			JOY_BUTTON_DPAD_RIGHT: return Vector2i.RIGHT
			JOY_BUTTON_DPAD_UP:    return Vector2i.UP
			JOY_BUTTON_DPAD_DOWN:  return Vector2i.DOWN
		return Vector2i.ZERO
	if event is InputEventJoypadMotion:
		if event == _last_motion:
			return _last_motion_result
		_last_motion = event
		_last_motion_result = _stick_step(event as InputEventJoypadMotion)
		return _last_motion_result
	return Vector2i.ZERO


static func _stick_step(event: InputEventJoypadMotion) -> Vector2i:
	if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
		return Vector2i.ZERO
	var horizontal: bool = event.axis == JOY_AXIS_LEFT_X
	var v: float = event.axis_value
	if absf(v) < STICK_RELEASE:
		if horizontal:
			_stick_dir.x = 0
		else:
			_stick_dir.y = 0
		return Vector2i.ZERO
	if absf(v) < STICK_PRESS:
		return Vector2i.ZERO
	var dir: int = 1 if v > 0.0 else -1
	if horizontal:
		if _stick_dir.x == dir:
			return Vector2i.ZERO
		_stick_dir.x = dir
		return Vector2i(dir, 0)
	if _stick_dir.y == dir:
		return Vector2i.ZERO
	_stick_dir.y = dir
	return Vector2i(0, dir)


# True for any event that is cursor movement, whether or not it stepped this time
# (a stick drifting under the threshold still belongs to the cursor, not the GUI).
static func is_nav_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	if event is InputEventJoypadButton:
		return event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]
	if event is InputEventJoypadMotion:
		return event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y
	return false
