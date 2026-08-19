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
#
# Every message box, dialogue and yes/no prompt in the game routes its key
# handling through here rather than testing keycodes itself. Adding controller
# support later is then a change to these three functions and nothing else —
# the pad buttons are already wired below, so a connected pad works today.
#
# Bindings:
#   accept — Space, Enter, numpad Enter, pad A (cross)
#   cancel — Escape, pad B (circle)
#   zoom   — Shift (held), pad L1
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
const ZOOM_KEYS: Array[int]   = [KEY_SHIFT]

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
