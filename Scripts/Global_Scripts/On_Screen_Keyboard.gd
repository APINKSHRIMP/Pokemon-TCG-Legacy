class_name OnScreenKeyboard
extends CanvasLayer

# ============================================================
# ON-SCREEN KEYBOARD
# ============================================================
# The one way text is entered anywhere in the game: trainer name, birthday, deck
# name, deck rename, card search. Every input device drives the same panel:
#
#   KEYBOARD  type straight onto it - letters, digits, Space, Backspace. Enter is
#             Done, Escape closes it. Press an ARROW and the selection ring appears
#             on the keys: from then on Space / Enter press the ringed key, until a
#             letter is typed again (which hides the ring and goes back to typing).
#   MOUSE /   click or tap the keys.
#   TOUCH
#   PAD       D-pad / stick move the ring, A presses the key, B deletes the last
#             letter (and closes the keyboard once there is nothing left to delete),
#             X types a space, Y toggles capitals, Start is Done.
#
# Usage - a screen calls ONE of these per text field:
#   OnScreenKeyboard.attach(line_edit, opts)  makes the field open the keyboard when
#       it is clicked, or pressed with Space / Enter / A while the menu cursor is on
#       it. The LineEdit itself becomes a display: it no longer takes focus or keys,
#       a focusable proxy laid over it does (so the D-pad can move off it - a live
#       LineEdit keeps Left / Right for its caret and traps the cursor).
#   OnScreenKeyboard.open(line_edit, opts)    opens it straight away (the rename box).
#
# opts (all optional):
#   "title"    heading over the preview (default: the field's placeholder text)
#   "mode"     "text" (default) or "date" - a digit pad for DD/MM with the "/" built
#              in: the player only ever enters four digits.
#   "submit"   true (default): Done emits the field's text_submitted, exactly like
#              pressing Enter in a LineEdit did. false: Done just closes.
#   "replace"  true: the first key pressed replaces the existing text (the rename
#              box's old select-all behaviour).
#   "on_done"  Callable run after Done (after text_submitted).
#
# While open the text is written into the LineEdit LIVE, and text_changed is emitted
# for every edit, so screens that react to typing (save button, validity checks)
# keep working unchanged.
# ============================================================

signal finished(submitted: bool)

## Above every menu, popup and the menu focus ring (InputDevice 140); below the
## card zoom (150).
const LAYER := 145

# ── Layout — ALL TWEAKABLE ───────────────────────────────────────────────────
const KEY_W           := 112.0    # one key unit (text mode)
const KEY_H           := 80.0
const KEY_GAP         := 10.0
const KEY_FONT        := 32
const DATE_KEY_W      := 150.0    # one key unit (date mode)
const PANEL_PAD       := 28.0
const PANEL_MIN_W     := 640.0
const PANEL_BOTTOM    := 36.0     # screen bottom -> panel bottom
const TITLE_H         := 40.0
const TITLE_FONT      := 26
const PREVIEW_H       := 84.0
const PREVIEW_FONT    := 40
const HINT_H          := 30.0
const HINT_FONT       := 19
const SECTION_GAP     := 16.0
const DIM_ALPHA       := 0.6      # the screen behind the keyboard
const CARET_BLINK     := 0.5      # seconds per caret on/off

## Keys, one row per line. A plain string is a 1-unit character key; an
## [id, units] pair is a wider control key.
const TEXT_ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", "'"],
	["Z", "X", "C", "V", "B", "N", "M", "-", ".", "!"],
	[["CAPS", 2.0], ["SPACE", 4.0], ["DEL", 2.0], ["DONE", 2.0]],
]
const DATE_ROWS := [
	["1", "2", "3"],
	["4", "5", "6"],
	["7", "8", "9"],
	[["DEL", 1.0], "0", ["DONE", 1.0]],
]
const KEY_LABELS := {"SPACE": "Space", "DEL": "Delete", "DONE": "Done"}

static var _current: OnScreenKeyboard = null

var _field: LineEdit = null
var _mode: String = "text"
var _submit: bool = true
var _replace_pending: bool = false
var _on_done: Callable = Callable()
var _title: String = ""

var _upper: bool = false
var _one_shot: bool = false        # capitals for the next letter only
var _digits: String = ""           # date mode

var _rows: Array = []              # rows of key Buttons
var _ids: Dictionary = {}          # Button -> key id
var _row: int = 0
var _col: int = 0
var _nav_mode: bool = false        # keyboard player moved the ring with the arrows
var _ring: Control = null
var _preview: Label = null
var _count: Label = null
var _hint: Label = null
var _caps_btn: Button = null
var _blink: float = 0.0
var _caret_on: bool = true
var _closed: bool = false


# ── Public API ───────────────────────────────────────────────────────────────

static func attach(field: LineEdit, opts: Dictionary = {}) -> Control:
	if field.has_meta("osk_proxy"):
		return field.get_meta("osk_proxy")
	field.editable = false
	field.focus_mode = Control.FOCUS_NONE
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.selecting_enabled = false
	field.context_menu_enabled = false
	field.virtual_keyboard_enabled = false
	# A non-editable LineEdit draws in its dimmed "uneditable" colour - it is only
	# non-editable because the keyboard does the editing, so keep the real colour.
	# Deferred: screens often style the field (font_color) AFTER attaching it.
	var sync_colour := func() -> void:
		if is_instance_valid(field):
			field.add_theme_color_override("font_uneditable_color", field.get_theme_color("font_color"))
	sync_colour.call()
	sync_colour.call_deferred()

	var proxy := Control.new()
	proxy.name = "OSKProxy"
	proxy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	proxy.mouse_filter = Control.MOUSE_FILTER_STOP
	proxy.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	field.add_child(proxy)
	field.set_meta("osk_proxy", proxy)
	UIKit.make_nav_tile(proxy, false)
	proxy.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open(field, opts))
	return proxy


static func open(field: LineEdit, opts: Dictionary = {}) -> OnScreenKeyboard:
	if field == null or not is_instance_valid(field) or not field.is_inside_tree():
		return null
	if is_open():
		_current._close(false)
	var k := OnScreenKeyboard.new()
	k._field = field
	k._mode = String(opts.get("mode", "text"))
	k._submit = bool(opts.get("submit", true))
	k._replace_pending = bool(opts.get("replace", false))
	k._on_done = opts.get("on_done", Callable())
	k._title = String(opts.get("title", field.placeholder_text))
	_current = k
	# Deferred: this usually runs from inside an input callback.
	field.get_tree().root.add_child.call_deferred(k)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	return k


static func is_open() -> bool:
	return _current != null and is_instance_valid(_current) and not _current._closed


## Closes the open keyboard, if any, without submitting (a screen being torn down).
static func dismiss() -> void:
	if is_open():
		_current._close(false)


# ── Build ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _mode == "date":
		_digits = ""
		for ch in _field.text:
			if ch >= "0" and ch <= "9" and _digits.length() < 4:
				_digits += ch
	else:
		_upper = _field.text.is_empty() or _replace_pending
		_one_shot = _upper
	_build()
	_refresh_all()
	_nav_mode = false
	_place_ring()
	# The field's own focus ring sits under the keyboard - keep the player's place.
	if _field.has_meta("osk_proxy"):
		var proxy: Control = _field.get_meta("osk_proxy")
		if is_instance_valid(proxy) and proxy.is_visible_in_tree():
			proxy.grab_focus()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, DIM_ALPHA)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Clicking off the keyboard closes it, keeping what was typed.
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if UIInput.is_click(e):
			_close(false))
	add_child(dim)

	var rows: Array = DATE_ROWS if _mode == "date" else TEXT_ROWS
	var unit: float = DATE_KEY_W if _mode == "date" else KEY_W
	var units := 0.0
	for r in rows:
		units = maxf(units, _row_units(r))
	var keys_w: float = units * unit + (units - 1.0) * KEY_GAP
	var keys_h: float = rows.size() * KEY_H + (rows.size() - 1) * KEY_GAP
	var inner_w: float = maxf(keys_w, PANEL_MIN_W - PANEL_PAD * 2.0)
	var inner_h: float = TITLE_H + SECTION_GAP + PREVIEW_H + SECTION_GAP + keys_h \
		+ SECTION_GAP + HINT_H
	var panel_size := Vector2(inner_w + PANEL_PAD * 2.0, inner_h + PANEL_PAD * 2.0)

	var panel := UIKit.make_modal_panel()
	panel.position = Vector2((UIKit.screen_w() - panel_size.x) * 0.5,
		UIKit.screen_h() - PANEL_BOTTOM - panel_size.y)
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	# Plain Control inside the PanelContainer; everything below is placed by hand.
	var body := Control.new()
	body.custom_minimum_size = panel_size - Vector2(16, 16)   # the modal panel's 8px margins
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	var origin := Vector2(PANEL_PAD - 8.0, PANEL_PAD - 8.0)

	var title := Label.new()
	UIKit.style_label(title, "body", "field_mute", TITLE_FONT)
	title.text = _title if _title != "" else ("Birthday" if _mode == "date" else "Enter text")
	title.position = origin
	title.size = Vector2(inner_w, TITLE_H)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)

	var y: float = origin.y + TITLE_H + SECTION_GAP
	var slot := UIKit.make_slot(Vector2(inner_w, PREVIEW_H))
	slot.position = Vector2(origin.x, y)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(slot)

	_preview = Label.new()
	_preview.add_theme_font_override("font", UITheme.font("name"))
	_preview.add_theme_font_size_override("font_size", PREVIEW_FONT)
	_preview.add_theme_color_override("font_color", UITheme.col("field_fg"))
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview.clip_text = true
	_preview.position = Vector2(origin.x + 20.0, y)
	_preview.size = Vector2(inner_w - 40.0, PREVIEW_H)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_preview)

	_count = Label.new()
	UIKit.style_label(_count, "body", "field_mute", HINT_FONT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.position = Vector2(origin.x, y)
	_count.size = Vector2(inner_w - 14.0, PREVIEW_H - 6.0)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_count)

	y += PREVIEW_H + SECTION_GAP
	var left: float = origin.x + (inner_w - keys_w) * 0.5
	for r in rows:
		var row_btns: Array = []
		var row_w: float = _row_units(r) * unit + (_row_units(r) - 1.0) * KEY_GAP
		var x: float = left + (keys_w - row_w) * 0.5
		for entry in r:
			var id: String = entry if entry is String else String(entry[0])
			var w_units: float = 1.0 if entry is String else float(entry[1])
			var w: float = w_units * unit + (w_units - 1.0) * KEY_GAP
			var btn := Button.new()
			btn.text = KEY_LABELS.get(id, id)
			UIKit.style_button(btn, _key_variant(id))
			btn.text = KEY_LABELS.get(id, id)          # style_button re-cases; keep ours
			btn.focus_mode = Control.FOCUS_NONE         # the keyboard's own ring, not Godot focus
			btn.add_theme_font_size_override("font_size", KEY_FONT)
			btn.position = Vector2(x, y)
			btn.size = Vector2(w, KEY_H)
			btn.custom_minimum_size = btn.size
			btn.pressed.connect(_on_key_clicked.bind(btn))
			btn.mouse_entered.connect(func() -> void:
				if not UIKit.nav_active():
					_select_button(btn))
			body.add_child(btn)
			_ids[btn] = id
			row_btns.append(btn)
			if id == "CAPS":
				_caps_btn = btn
			x += w + KEY_GAP
		_rows.append(row_btns)
		y += KEY_H + KEY_GAP
	y += SECTION_GAP - KEY_GAP

	_hint = Label.new()
	UIKit.style_label(_hint, "body", "field_mute", HINT_FONT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.position = Vector2(origin.x, y)
	_hint.size = Vector2(inner_w, HINT_H)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_hint)

	# Start the ring on the first letter (text) or "1" (date).
	_row = 1 if _mode == "text" else 0
	_col = 0


func _row_units(r: Array) -> float:
	var u := 0.0
	for entry in r:
		u += 1.0 if entry is String else float(entry[1])
	return u


func _key_variant(id: String) -> String:
	match id:
		"DONE":
			return "primary"
		"DEL":
			return "negative"
		"CAPS":
			return "neutral"
	return "secondary"


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event is InputEventMouse:
		if event is InputEventMouseMotion and _nav_mode:
			_nav_mode = false
		return
	if not (event is InputEventKey or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion):
		return
	# Everything that isn't the mouse is the keyboard's while it is open.
	get_viewport().set_input_as_handled()

	var dir := UIInput.nav_direction(event)
	if dir != Vector2i.ZERO:
		if event is InputEventKey:
			_nav_mode = true
		_move(dir)
		return

	if event is InputEventJoypadButton:
		if not event.pressed:
			return
		match event.button_index:
			JOY_BUTTON_A:
				_press(_selected_id())
			JOY_BUTTON_B:
				if _current_text().is_empty():
					_close(false)
				else:
					_press("DEL")
			JOY_BUTTON_X:
				_press("SPACE")
			JOY_BUTTON_Y:
				_press("CAPS")
			JOY_BUTTON_START:
				_press("DONE")
		return

	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_ESCAPE:
			if not k.echo:
				_close(false)
			return
		KEY_BACKSPACE, KEY_DELETE:
			_press("DEL")
			return
		KEY_ENTER, KEY_KP_ENTER:
			if k.echo:
				return
			_press(_selected_id() if _ring_showing() else "DONE")
			return
		KEY_SPACE:
			if _ring_showing():
				if not k.echo:
					_press(_selected_id())
			else:
				_insert(" ")
			return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if k.unicode >= 32:
		_nav_mode = false
		_insert(String.chr(k.unicode))


func _process(delta: float) -> void:
	if _closed:
		return
	# The keyboard lives on the root, not the screen - if the screen went away under
	# it, go with it.
	if not is_instance_valid(_field) or not _field.is_inside_tree():
		_close(false)
		return
	_blink += delta
	if _blink >= CARET_BLINK:
		_blink = 0.0
		_caret_on = not _caret_on
		_refresh_preview()
	_place_ring()
	_refresh_hint()


## Pad: always. Keyboard: after an arrow press, until a letter is typed. Mouse: never.
func _ring_showing() -> bool:
	var dev: Node = get_tree().root.get_node_or_null("/root/InputDevice")
	if dev == null:
		return false
	if dev.using_pad():
		return true
	return dev.using_nav() and _nav_mode


func _move(dir: Vector2i) -> void:
	if _rows.is_empty():
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)
	if dir.x != 0:
		var n: int = (_rows[_row] as Array).size()
		_col = wrapi(_col + dir.x, 0, n)
		return
	# Up / down: the key in the next row whose centre is nearest this one's.
	var from: Button = _rows[_row][_col]
	var cx: float = from.position.x + from.size.x * 0.5
	_row = wrapi(_row + dir.y, 0, _rows.size())
	var best := 0
	var best_d := INF
	var row: Array = _rows[_row]
	for i in row.size():
		var b: Button = row[i]
		var d: float = absf(b.position.x + b.size.x * 0.5 - cx)
		if d < best_d:
			best_d = d
			best = i
	_col = best


func _select_button(btn: Button) -> void:
	for r in _rows.size():
		var i: int = (_rows[r] as Array).find(btn)
		if i >= 0:
			_row = r
			_col = i
			return


func _selected_id() -> String:
	if _rows.is_empty():
		return ""
	return String(_ids.get(_rows[_row][_col], ""))


func _on_key_clicked(btn: Button) -> void:
	_select_button(btn)
	_press(String(_ids.get(btn, "")))


# ── Editing ──────────────────────────────────────────────────────────────────

func _press(id: String) -> void:
	if _closed or id == "":
		return
	match id:
		"DONE":
			_close(true)
		"DEL":
			_delete()
		"SPACE":
			_insert(" ")
		"CAPS":
			_upper = not _upper
			_one_shot = false
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)
			_refresh_all()
		_:
			var ch: String = id
			if _mode == "text" and ch.length() == 1 and ch.to_lower() != ch.to_upper():
				ch = ch.to_upper() if _upper else ch.to_lower()
			_insert(ch)


func _current_text() -> String:
	return _digits if _mode == "date" else _field.text


func _insert(s: String) -> void:
	if not is_instance_valid(_field):
		_close(false)
		return
	if _mode == "date":
		if s.length() != 1 or s < "0" or s > "9" or _digits.length() >= 4:
			return
		_digits += s
		_write(_format_date(_digits))
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
		return
	var base: String = "" if _replace_pending else _field.text
	_replace_pending = false
	if _field.max_length > 0 and base.length() + s.length() > _field.max_length:
		return
	_write(base + s)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	# Phone-keyboard capitals: the first letter of the text and of each new word.
	if s == " ":
		if not _upper:
			_upper = true
			_one_shot = true
	elif _one_shot and s.to_lower() != s.to_upper():
		_upper = false
		_one_shot = false
	_refresh_all()


func _delete() -> void:
	if not is_instance_valid(_field):
		_close(false)
		return
	_replace_pending = false
	if _mode == "date":
		if _digits.is_empty():
			return
		_digits = _digits.substr(0, _digits.length() - 1)
		_write(_format_date(_digits))
	else:
		if _field.text.is_empty():
			return
		_write(_field.text.substr(0, _field.text.length() - 1))
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_refresh_all()


## "" for no digits, otherwise DD/MM with the slash always in place and the
## missing digits as underscores: "1" -> "1_/__", "120" -> "12/0_".
static func _format_date(digits: String) -> String:
	if digits.is_empty():
		return ""
	var dd: String = digits.substr(0, 2)
	var mm: String = digits.substr(2, 2)
	return dd.rpad(2, "_") + "/" + mm.rpad(2, "_")


func _write(t: String) -> void:
	_field.text = t
	_field.caret_column = t.length()
	_field.text_changed.emit(t)
	_blink = 0.0
	_caret_on = true
	_refresh_preview()


func _close(submitted: bool) -> void:
	if _closed:
		return
	_closed = true
	if _current == self:
		_current = null
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select if submitted
		else SoundManagerScript.SFX_minus_select)
	var field := _field
	var on_done := _on_done
	var submit := _submit
	queue_free()
	finished.emit(submitted)
	if submitted and is_instance_valid(field):
		if submit:
			field.text_submitted.emit(field.text)
		if on_done.is_valid():
			on_done.call()


# ── Display ──────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_preview()
	if _mode == "text":
		for r in _rows:
			for b in r:
				var id: String = String(_ids.get(b, ""))
				if id.length() == 1 and id.to_lower() != id.to_upper():
					(b as Button).text = id.to_upper() if _upper else id.to_lower()
		if _caps_btn != null:
			_caps_btn.text = "ABC" if _upper else "abc"
			UIKit.style_button(_caps_btn, "selected" if _upper and not _one_shot else "neutral")
			_caps_btn.text = "ABC" if _upper else "abc"
	_refresh_hint()


func _refresh_preview() -> void:
	if _preview == null or not is_instance_valid(_field):
		return
	var caret: String = "|" if _caret_on else " "
	if _mode == "date":
		var shown: String = _format_date(_digits)
		if shown == "":
			shown = "__/__"
		_preview.text = shown
		_count.text = "DD / MM"
		return
	_preview.text = _field.text + caret
	_count.text = "%d / %d" % [_field.text.length(), _field.max_length] \
		if _field.max_length > 0 else ""


func _refresh_hint() -> void:
	if _hint == null:
		return
	var dev: Node = get_tree().root.get_node_or_null("/root/InputDevice")
	var t: String
	if dev != null and dev.using_pad():
		var ps: bool = dev.pad_family() == "playstation"
		var a: String = "Cross" if ps else "A"
		var b: String = "Circle" if ps else "B"
		var x: String = "Square" if ps else "X"
		var yb: String = "Triangle" if ps else "Y"
		var st: String = "Options" if ps else "Menu"
		if _mode == "date":
			t = "%s type  ·  %s delete  ·  %s done" % [a, b, st]
		else:
			t = "%s type  ·  %s delete  ·  %s space  ·  %s capitals  ·  %s done" % [a, b, x, yb, st]
	elif _mode == "date":
		t = "Type the four digits  ·  Backspace delete  ·  Enter done  ·  Esc close"
	else:
		t = "Type, or use the arrows and Space  ·  Backspace delete  ·  Enter done  ·  Esc close"
	if _hint.text != t:
		_hint.text = t


func _place_ring() -> void:
	var show := _ring_showing() and not _rows.is_empty()
	if not show:
		if _ring != null:
			_ring.visible = false
		return
	var btn: Button = _rows[_row][_col]
	var r := btn.get_global_rect()
	if _ring == null or not is_instance_valid(_ring):
		_ring = UIKit.add_selection_ring_rect(self, r)
	_ring.visible = true
	UIKit.place_selection_ring(_ring, r)
