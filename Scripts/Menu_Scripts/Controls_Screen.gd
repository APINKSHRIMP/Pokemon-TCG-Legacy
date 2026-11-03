
extends Control

# ============================================================
# CONTROLS (a sub-screen of Options)
# ============================================================
# Opened by the "Controls" button in the top right of Options, drawn on top of it
# and closed back to it with Back / Escape / B. Built in code like Options itself.
#
# Two steppers pick the page, the same < name > shape the deck builder uses for sets:
#   device   Keyboard & Mouse  |  Controller
#   context  Overworld         |  In match
#
# Keyboard pages are a two-column list of key chips and what they do. Controller
# pages are a drawn pad with callout lines (ControllerDiagram), labelled for an Xbox
# or a PlayStation pad depending on which is plugged in (InputDevice.pad_family()).
#
# THE LISTS BELOW ARE DOCUMENTATION, NOT BINDINGS. The bindings live in UIInput
# (and the match cursor in Board_Nav.gd / Hand_Drag.gd); change one there and the
# matching line here by hand.
# ============================================================

signal closed

const ControllerDiagram := preload("res://Scripts/Menu_Scripts/Controller_Diagram.gd")

const DEVICES := ["keyboard", "controller"]
const DEVICE_NAMES := {"keyboard": "Keyboard & Mouse", "controller": "Controller"}
const CONTEXTS := ["overworld", "match", "menus"]
const CONTEXT_NAMES := {"overworld": "Overworld", "match": "In match", "menus": "Menus"}

## Keyboard rows: [keys, action]. In `keys`, "|" separates alternatives (shown with a
## slash between them) and "+" joins keys pressed together.
const KEYBOARD_ROWS := {
	"overworld": [
		["W A S D|Arrows", "Walk"],
		["Shift", "Run (hold)"],
		["Space|Enter", "Talk, interact, confirm, answer yes"],
		["Esc|Backspace", "Back, answer no"],
		["Enter|Esc", "Open the menu"],
		["M", "Phone map"],
		["Space", "Fishing: cast, hook and reel"],
		["Esc", "Fishing: reel the line back in"],
	],
	"match": [
		["Click", "Pick up a card in your hand"],
		["Double click", "Play a card from your hand"],
		["Drag", "Hand card onto a Pokemon: attach Energy or evolve"],
		["Drag", "Trainer or Basic up onto the board: play it"],
		["Drag", "Active onto the Bench (or back): retreat"],
		["Alt+Click", "Open your hand large"],
		["Right click", "Cancel, clear the selection"],
		["Arrows", "Move the cursor"],
		["Space|Enter", "Confirm, play, advance messages"],
		["Esc|Backspace", "Back, cancel (Esc pauses if nothing to cancel)"],
		["Shift", "Enlarge a card (hold)"],
		["Caps Lock", "Message log"],
		["Tab", "Jump the cursor to your hand"],
		["Q", "Jump the cursor to End Turn"],
		["Wheel", "Scroll a long hand or the log"],
	],
	"menus": [
		["Arrows", "Move the cursor"],
		["Space|Enter", "Press, pick, add a card to the deck"],
		["X|Delete", "Remove a card from the deck"],
		["Esc|Backspace", "Back, close"],
		["Shift", "Enlarge a card, coin or sleeve (hold)"],
		["PgUp|PgDn", "Deck builder: previous / next set"],
		["Space|Enter", "Text box: open the on-screen keyboard"],
		["Type", "Keyboard: type straight in, Enter done, Esc close"],
	],
}

## Controller rows: [button id, action]. Ids are ControllerDiagram's.
const PAD_ROWS := {
	"overworld": [
		["lstick", "Walk"],
		["dpad", "Walk"],
		["lb", "Run (hold)"],
		["view", "Phone map"],
		["menu", "Menu"],
		["a", "Talk, interact, confirm, fishing"],
		["b", "Back, answer no, reel in"],
	],
	"match": [
		["lstick", "Move the cursor"],
		["dpad", "Move the cursor"],
		["lb", "Enlarge a card (hold)"],
		["view", "Message log"],
		["menu", "Pause"],
		["y", "Jump to End Turn"],
		["x", "Jump to your hand"],
		["b", "Back, cancel"],
		["a", "Confirm, play, open"],
	],
	"menus": [
		["lstick", "Move the cursor"],
		["dpad", "Move the cursor"],
		["lb", "Enlarge a card, coin or sleeve (hold)"],
		["lt", "Deck builder: previous set"],
		["rt", "Deck builder: next set"],
		["a", "Press, pick, add a card / type a key"],
		["x", "Remove a card / keyboard: space"],
		["b", "Back / keyboard: delete a letter"],
		["y", "Keyboard: capitals"],
		["menu", "Keyboard: done"],
	],
}

# ── Layout (px at 1920x1080) - TWEAKABLE ─────────────────────────────────────
const STEPPER_ARROW_W := 44.0
const STEPPER_NAME_W := 380.0
const SUB_STEPPER_NAME_W := 260.0
const STEPPERS_TOP := 120.0          # first stepper's top, below the header
const STEPPER_GAP := 14.0
const CONTENT_TOP := 270.0           # where the list / diagram starts
const KEY_COL_W := 330.0             # the chips column of one keyboard list column
const ACTION_COL_W := 440.0
const LIST_COL_GAP := 90.0
const ROW_GAP := 14.0
const ACTION_SIZE := 21

var _device_i := 0
var _context_i := 0

var _device_label: Label
var _context_label: Label
var _content: Control
var _back_btn: Button
var _first_focus: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.base_theme()
	# Start on the device the player is holding.
	_device_i = 1 if InputDevice.using_pad() else 0
	_build()
	Input.joy_connection_changed.connect(_on_joy_changed)
	if InputDevice.using_nav() and _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func _build() -> void:
	UIKit.add_field(self)

	var header := UIKit.add_header(self)
	var title := Label.new()
	UIKit.set_label(title, "title", "Controls", "chrome_fg")
	header.centre.add_child(title)

	var footer := UIKit.add_footer(self)
	_back_btn = UIKit.make_footer_button("Back", "negative")
	_back_btn.pressed.connect(_close)
	footer.centre.add_child(_back_btn)

	var steppers := VBoxContainer.new()
	steppers.add_theme_constant_override("separation", int(STEPPER_GAP))
	steppers.set_anchors_preset(Control.PRESET_CENTER_TOP)
	steppers.anchor_left = 0.5
	steppers.anchor_right = 0.5
	steppers.offset_left = -400
	steppers.offset_right = 400
	steppers.offset_top = STEPPERS_TOP
	add_child(steppers)

	var device_row := _make_stepper(STEPPER_NAME_W, "title", -1, _on_device_step)
	_device_label = device_row["label"]
	_first_focus = device_row["next"]
	steppers.add_child(device_row["row"])

	var context_row := _make_stepper(SUB_STEPPER_NAME_W, "name", -1, _on_context_step)
	_context_label = context_row["label"]
	steppers.add_child(context_row["row"])

	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_top = CONTENT_TOP
	_content.offset_bottom = -UITheme.m("footer_slim_h") - 10.0
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	_refresh()


## One "<  name  >" stepper. `step` is called with -1 or +1.
func _make_stepper(name_w: float, role: String, size_px: int, step: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)

	var prev := Button.new()
	prev.text = "<"
	var next := Button.new()
	next.text = ">"
	for b in [prev, next]:
		UIKit.style_button(b, "neutral")
		b.custom_minimum_size = Vector2(STEPPER_ARROW_W, STEPPER_ARROW_W + 6.0)
		b.add_theme_font_override("font", UITheme.font_at(UITheme.FONT_UI_BOLD))
		b.add_theme_font_size_override("font_size", 22)
	prev.pressed.connect(func(): step.call(-1))
	next.pressed.connect(func(): step.call(1))

	var label := Label.new()
	UIKit.style_label(label, role, "field_fg", size_px)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(name_w, 0)

	row.add_child(prev)
	row.add_child(label)
	row.add_child(next)
	return {"row": row, "label": label, "prev": prev, "next": next}


func _on_device_step(dir: int) -> void:
	_device_i = wrapi(_device_i + dir, 0, DEVICES.size())
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh()


func _on_context_step(dir: int) -> void:
	_context_i = wrapi(_context_i + dir, 0, CONTEXTS.size())
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_refresh()


func _on_joy_changed(_id: int, _connected: bool) -> void:
	if DEVICES[_device_i] == "controller":
		_refresh()


func _refresh() -> void:
	var device: String = DEVICES[_device_i]
	var context: String = CONTEXTS[_context_i]
	_device_label.text = UITheme.cased("title", DEVICE_NAMES[device])
	_context_label.text = UITheme.cased("name", CONTEXT_NAMES[context])

	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	if device == "keyboard":
		_build_keyboard_page(KEYBOARD_ROWS[context])
	else:
		_build_pad_page(PAD_ROWS[context])


# ── Keyboard page ────────────────────────────────────────────────────────────

func _build_keyboard_page(rows: Array) -> void:
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", int(LIST_COL_GAP))
	cols.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(cols)

	var half: int = int(ceil(rows.size() / 2.0))
	for chunk in [rows.slice(0, half), rows.slice(half)]:
		if chunk.is_empty():
			continue
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", int(ROW_GAP))
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_child(col)
		for r in chunk:
			col.add_child(_keyboard_row(String(r[0]), String(r[1])))


func _keyboard_row(keys: String, action_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", 6)
	chips.custom_minimum_size = Vector2(KEY_COL_W, 0)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var alternatives := keys.split("|")
	for i in alternatives.size():
		if i > 0:
			chips.add_child(_joiner("/"))
		var combo := alternatives[i].split("+")
		for j in combo.size():
			if j > 0:
				chips.add_child(_joiner("+"))
			var chip := UIKit.make_chip(combo[j].strip_edges())
			# Centred, not stretched, beside a description that wraps to two lines.
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chips.add_child(chip)
	row.add_child(chips)

	var action := Label.new()
	UIKit.set_label(action, "body", action_text, "field_fg", ACTION_SIZE)
	action.custom_minimum_size = Vector2(ACTION_COL_W, 0)
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(action)
	return row


func _joiner(text: String) -> Label:
	var l := Label.new()
	UIKit.set_label(l, "small_label", text, "field_mute", 18)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# ── Controller page ──────────────────────────────────────────────────────────

func _build_pad_page(rows: Array) -> void:
	var family: String = InputDevice.pad_family()
	var connected := not Input.get_connected_joypads().is_empty()

	var diagram: Control = ControllerDiagram.new()
	diagram.set_anchors_preset(Control.PRESET_CENTER_TOP)
	diagram.anchor_left = 0.5
	diagram.anchor_right = 0.5
	diagram.offset_left = -ControllerDiagram.DESIGN_SIZE.x * 0.5
	diagram.offset_right = ControllerDiagram.DESIGN_SIZE.x * 0.5
	diagram.offset_top = 0.0
	diagram.offset_bottom = ControllerDiagram.DESIGN_SIZE.y
	_content.add_child(diagram)
	diagram.set_map(rows, family)

	var note := Label.new()
	var family_name := "PlayStation" if family == "playstation" else "Xbox"
	var text := ("%s controller connected" % family_name) if connected \
		else "No controller connected - showing the Xbox layout"
	UIKit.set_label(note, "small_label", text, "field_mute", 15)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	note.offset_top = -30.0
	note.offset_bottom = 0.0
	_content.add_child(note)


# ── Leaving ──────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
