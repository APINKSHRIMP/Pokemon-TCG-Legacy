class_name MenuHelp
extends CanvasLayer

# ============================================================
# MENU HELP - a darkened controls panel over a menu, and one-off first-visit notices
# ============================================================
# 2026-11-12 (user). Two shapes, both a CanvasLayer added to the MENU (its last child), so
# its _input runs before the menu's own and before InputDevice's shortcuts / cursor moves:
# while it is up, nothing behind it can be pressed.
#
#   open_controls(host, title, rows_km, rows_pad, first_time)
#       The controls panel: key chips and what they do, for the mouse & keyboard or the
#       pad - whichever the player is using, rebuilt live if they switch. Toggled by
#       UIInput.is_help_toggle (Caps Lock / pad left stick in). On the FIRST visit it
#       carries a message box ("Press [CAPS LOCK] to view and hide this help menu") and
#       only the help key closes it; later, Back / B / a click close it too.
#       Used by the deck builder (Deck_Build_And_Card_View_Script HELP_ROWS_*).
#
#   notice(host, text_km, text_pad)
#       One message box over a light dim, dismissed with a click / A / Space / B.
#       Used by the coin case, sleeves and costumes the first time one is opened.
#
#   first_time(host, flag, show)
#       Runs `show` once ever (a GameState story flag), a moment after the menu opens -
#       and never while a cutscene is driving the menu (walkthrough_active /
#       InputDevice.suspended: Olly's deck builder and coin case walkthroughs).
#
# Rows are [keys, action]. Keyboard keys: "|" separates alternatives, "+" joins a combo
# (as Controls_Screen). Pad keys: Controller_Diagram ids ("a", "lb", "view"...) plus
# "l3" / "r3" for the sticks pressed in, "|"-separated.
# ============================================================

const ControllerDiagram := preload("res://Scripts/Menu_Scripts/Controller_Diagram.gd")

# -- TWEAKABLE ---------------------------------------------------------------------
const LAYER := 120                 # over menus (100/101), under the cursor ring (140) and card zoom (150)
const DIM_CONTROLS := 0.84         # how dark the controls panel's backdrop is
const DIM_NOTICE := 0.55           # how dark a notice's backdrop is
const FADE := 0.18                 # fade in / out
const TITLE_TOP := 90.0            # title's top, px
const ROWS_TOP := 180.0            # first row's top, px
const KEY_COL_W := 300.0           # the chips column of one list column
const ACTION_COL_W := 420.0
const COL_GAP := 90.0
const ROW_GAP := 16.0
const ACTION_SIZE := 22
const BOX_H := 120.0               # the message box's minimum height
const BOX_FONT := 28

enum Kind { CONTROLS, NOTICE }

signal closed

static var _open: MenuHelp = null

var _kind: int = Kind.CONTROLS
var _title: String = ""
var _rows_km: Array = []
var _rows_pad: Array = []
var _strict: bool = false          # first visit: only the help key closes the panel
var _hint_km: String = ""
var _hint_pad: String = ""
var _pad: bool = false             # which rows / text are showing
var _root: Control
var _content: Control
var _box: DynamicMessageBox = null
var _opened_frame: int = 0
var _closing: bool = false
var _prev_focus: Control = null
var _prev_suspended: bool = false
var _restored: bool = false


# ============================================================
# ENTRY POINTS
# ============================================================

static func is_open() -> bool:
	return _open != null and is_instance_valid(_open) and not _open._closing


static func open_controls(host: Node, title: String, rows_km: Array, rows_pad: Array,
		first_time: bool = false) -> MenuHelp:
	if is_open():
		return _open
	var h := MenuHelp.new()
	h._kind = Kind.CONTROLS
	h._title = title
	h._rows_km = rows_km
	h._rows_pad = rows_pad
	h._strict = first_time
	if first_time:
		h._hint_km = "Press [CAPS LOCK] to view and hide this help menu"
		h._hint_pad = "Press [L3] (push the left stick in) to view and hide this help menu"
	h._attach(host)
	return h


static func notice(host: Node, text_km: String, text_pad: String) -> MenuHelp:
	if is_open():
		return _open
	var h := MenuHelp.new()
	h._kind = Kind.NOTICE
	h._hint_km = text_km
	h._hint_pad = text_pad
	h._attach(host)
	return h


## The coin case, sleeves and costumes: whichever is opened FIRST says this, once.
const COSMETIC_FLAG := "help_cosmetics_seen"
const COSMETIC_KM := "You can change your selected Coin, Costume and Sleeve by clicking on it with the left mouse button. Make sure you click Save to confirm your change."
const COSMETIC_PAD := "You can change your selected Coin, Costume and Sleeve by highlighting it and pressing [A]. Make sure you select Save to confirm your change."


static func cosmetic_first_time(host: Node) -> void:
	first_time(host, COSMETIC_FLAG, func(): notice(host, COSMETIC_KM, COSMETIC_PAD))


## `show` runs once ever (story flag `flag`), DELAY seconds after the menu opened - unless
## a cutscene is driving the menu, in which case the flag is left unset for next time.
static func first_time(host: Node, flag: String, show: Callable, delay: float = 0.4) -> void:
	if host == null or GameState.has_flag(flag):
		return
	await host.get_tree().create_timer(delay).timeout
	if not is_instance_valid(host) or not host.is_inside_tree() or GameState.has_flag(flag):
		return
	if host.get("walkthrough_active") == true or InputDevice.suspended or is_open():
		return
	GameState.set_flag(flag)
	show.call()


# ============================================================
# BUILD
# ============================================================

func _attach(host: Node) -> void:
	layer = LAYER
	_open = self
	_opened_frame = Engine.get_process_frames()
	_pad = InputDevice.using_pad()
	# The cursor ring (layer 140) would sit on the focused tile behind the dim: the menu cursor
	# stands down while the panel is up (as for Olly's walkthroughs - no focus, no autofocus,
	# no shortcuts) and focus goes back to where it was on close.
	_prev_focus = host.get_viewport().gui_get_focus_owner()
	_prev_suspended = InputDevice.suspended
	InputDevice.set_suspended(true)
	host.add_child(self)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind takes a click
	_root.theme = UIKit.base_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, DIM_CONTROLS if _kind == Kind.CONTROLS else DIM_NOTICE)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_build()
	InputDevice.device_changed.connect(_on_device_changed)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)


func _build() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = null
	if _kind == Kind.CONTROLS:
		_build_controls()
	var hint: String = _hint_pad if _pad else _hint_km
	if hint != "":
		_build_box(_pad_tokens(hint))


func _build_controls() -> void:
	var title := Label.new()
	UIKit.set_label(title, "title", _title, "field_fg")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = TITLE_TOP
	_content.add_child(title)
	var sub := Label.new()
	UIKit.set_label(sub, "small_label", "Controller" if _pad else "Mouse & keyboard", "field_mute", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = TITLE_TOP + 52.0
	_content.add_child(sub)

	var rows: Array = _rows_pad if _pad else _rows_km
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", int(COL_GAP))
	cols.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	cols.offset_top = ROWS_TOP
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
			col.add_child(_row(String(r[0]), String(r[1])))


func _row(keys: String, action_text: String) -> HBoxContainer:
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
			var text: String = combo[j].strip_edges()
			if _pad:
				text = _pad_name(text)
			var chip := UIKit.make_chip(text)
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


func _build_box(text: String) -> void:
	_box = DynamicMessageBox.new()
	_box.configure(BOX_H, BOX_FONT, false)
	_box.show_as_plain()
	_box.apply_theme()
	_box.visible = true
	_root.add_child(_box)
	_box.set_body_text("[center]" + text + "[/center]", BOX_FONT)


## A pad id -> the name printed on the player's pad family ("a" -> "A" / "Cross").
func _pad_name(id: String) -> String:
	var ps: bool = InputDevice.pad_family() == "playstation"
	match id:
		"l3": return "L3" if ps else "LS"
		"r3": return "R3" if ps else "RS"
	return ControllerDiagram.button_name(id, InputDevice.pad_family())


## "[L3]" style tokens in a hint -> the pad's own name, in brackets.
func _pad_tokens(text: String) -> String:
	for id in ["l3", "r3", "a", "b", "x", "y", "lb", "rb", "view", "menu"]:
		text = text.replace("[" + id.to_upper() + "]", "[" + _pad_name(id).to_upper() + "]")
	return text


func _on_device_changed(_d: int) -> void:
	var now_pad: bool = InputDevice.using_pad()
	if now_pad != _pad and not _closing:
		_pad = now_pad
		_build()


# ============================================================
# INPUT - everything is swallowed while the panel is up
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or _closing:
		return
	get_viewport().set_input_as_handled()
	if Engine.get_process_frames() == _opened_frame:
		return   # the press that opened the panel must not also close it
	var click: bool = UIInput.is_click(event)
	if _kind == Kind.NOTICE:
		if not (UIInput.is_accept(event) or UIInput.is_cancel(event) or click):
			return
		if _box != null and _box.is_typing():
			_box.finish_typing()
			return
		close()
		return
	# The controls panel.
	if UIInput.is_help_toggle(event):
		close()
	elif not _strict and (UIInput.is_cancel(event) or click):
		close()
	elif _box != null and _box.is_typing() and (UIInput.is_accept(event) or click):
		_box.finish_typing()


func close() -> void:
	if _closing:
		return
	_closing = true
	if _open == self:
		_open = null
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE)
	await tw.finished
	_restore_cursor()
	if _prev_focus != null and is_instance_valid(_prev_focus) and _prev_focus.is_visible_in_tree() \
			and InputDevice.using_nav():
		_prev_focus.grab_focus()
	closed.emit()
	queue_free()


func _restore_cursor() -> void:
	if _restored:
		return
	_restored = true
	if not _prev_suspended:
		InputDevice.set_suspended(false)


func _exit_tree() -> void:
	if _open == self:
		_open = null
	_restore_cursor()   # the menu closed under the panel
