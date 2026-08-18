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
#
# Every message box, dialogue and yes/no prompt in the game routes its key
# handling through here rather than testing keycodes itself. Adding controller
# support later is then a change to these three functions and nothing else —
# the pad buttons are already wired below, so a connected pad works today.
#
# Bindings:
#   accept — Space, Enter, numpad Enter, pad A (cross)
#   cancel — Escape, pad B (circle)
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
const CANCEL_KEYS: Array[int] = [KEY_ESCAPE]

static func is_accept(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in ACCEPT_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_A
	return false

static func is_cancel(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _key_pressed(event) and event.keycode in CANCEL_KEYS
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_B
	return false

# True for anything that should move a plain message along, whichever key it was.
static func is_advance(event: InputEvent) -> bool:
	return is_accept(event) or is_cancel(event)

static func _key_pressed(event: InputEventKey) -> bool:
	return event.pressed and not event.is_echo()
