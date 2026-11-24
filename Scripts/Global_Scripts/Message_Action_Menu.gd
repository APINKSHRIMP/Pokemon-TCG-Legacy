class_name MessageActionMenu
extends Control

# ============================================================
# MESSAGE ACTION MENU - a short list docked to the message box
# ============================================================
# A vertical list of actions that sits on the message box's TOP-RIGHT corner while the
# box says who you are talking to - the classic "what will you do?" list. First user:
# talking to your own Pokémon (Pet / Feed / Rename / Send home / Dismiss / Cancel).
#
#     +-----------+
#     | > PET     |   <- the highlighted row wears the speaker's colour (the name
#     |   FEED    |      pill's capsule) plus the selection ring, like the Yes/No
#     |   RENAME  |      buttons do
#     |   CANCEL  |
#     +-----------+
#   [portrait NAME]                            <- the box's own pill row
#   +----------------------------------------------------------+
#   |  Forretress looks happy to be with you!                  |
#   +----------------------------------------------------------+
#
# The panel IS the box's panel (DynamicMessageBox.make_side_panel): same fill, hairline,
# spine and glow, in the speaker's colour, so it reads as part of the box.
#
# INPUT. It never reads keys itself - the overworld's message-box routing does, so there
# is still ONE place a press is decided (MapManager.handle_message_*):
#   Up / Down    move()        (wraps)
#   Accept       accept()      Space / Enter / pad A
#   Cancel       cancel()      Escape / Backspace / pad B
#   Mouse/touch  hover a row to highlight it, click it to choose it.
#
# Usage:
#     var menu := MessageActionMenu.open(box, [{"id": "pet", "label": "Pet"}, ...])
#     menu.chosen.connect(func(id): ...)
#     menu.cancelled.connect(func(): ...)
# The menu frees itself when it emits either signal.
# ============================================================

signal chosen(id: String)
signal cancelled

# -- TWEAKABLES (px at 1920x1080) --
const ROW_H        : float = 44.0    # one row (the highlight capsule's height)
const ROW_GAP      : float = 2.0
const PAD_L        : float = 20.0    # panel's left edge -> rows (clears the 8px spine)
const PAD_R        : float = 12.0
const PAD_Y        : float = 12.0
const LABEL_PAD_X  : float = 22.0    # capsule edge -> its text
const MIN_W        : float = 220.0   # panel's narrowest
const DOCK_GAP     : float = 14.0    # menu's bottom -> the box's top
const FONT_SIZE    : int   = 21
const TRACK_EM     : float = 0.11    # letter spacing, the name pill's
const IN_TIME      : float = 0.12    # fade/rise in
const IN_RISE      : float = 8.0

var _box: DynamicMessageBox = null
var _items: Array = []
var _cursor: int = 0
var _panel: ColorRect = null
var _pill: ColorRect = null
var _ring: Control = null
var _labels: Array = []
var _hits: Array = []
var _inner: Rect2 = Rect2()
var _docked_at: Vector2 = Vector2(-1, -1)
var _done: bool = false


## Opens the menu on `box` (which must be in the tree and showing). `items` are
## {"id": String, "label": String}; labels are cased by the theme (buttons are caps).
static func open(box: DynamicMessageBox, items: Array, start_index: int = 0) -> MessageActionMenu:
	var m := MessageActionMenu.new()
	m.name = "MessageActionMenu"
	m._box = box
	m._items = items.duplicate(true)
	m._cursor = clampi(start_index, 0, maxi(items.size() - 1, 0))
	var parent := box.get_parent()
	parent.add_child(m)
	parent.move_child(m, box.get_index() + 1)   # right above the box, under anything newer
	return m


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = UIKit.screen_size()
	_build()
	_dock()
	_set_cursor(_cursor, false)
	if not _ui().motion_reduced():
		modulate.a = 0.0
		var rest := position.y
		position.y = rest + IN_RISE
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 1.0, IN_TIME)
		tw.tween_property(self, "position:y", rest, IN_TIME)


## The box can grow or move (window resized, longer line): stay docked to it.
func _process(_delta: float) -> void:
	if _box == null or not is_instance_valid(_box):
		return
	visible = _box.visible
	if _box.panel_top_right() != _docked_at:
		_dock()


# ---- public: driven by the message-box routing ------------------------------

func move(step: int) -> void:
	if _items.is_empty() or step == 0:
		return
	_set_cursor(posmod(_cursor + (1 if step > 0 else -1), _items.size()))
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func accept() -> void:
	if _done or _items.is_empty():
		return
	_finish(true, String(_items[_cursor].get("id", "")))


func cancel() -> void:
	if _done:
		return
	_finish(false, "")


func selected_id() -> String:
	return String(_items[_cursor].get("id", "")) if not _items.is_empty() else ""


## Takes the menu down without a choice (the box is closing under it).
func close() -> void:
	_done = true
	queue_free()


# ---- build ------------------------------------------------------------------

func _font() -> Font:
	return _ui().font("name")


func _track() -> int:
	return int(round(TRACK_EM * float(FONT_SIZE)))


func _label_text(i: int) -> String:
	return _ui().cased("button", String(_items[i].get("label", "")))


func _build() -> void:
	var widest := 0.0
	for i in _items.size():
		var t := _label_text(i)
		widest = maxf(widest, _font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
				+ float(_track() * t.length()))
	var w := maxf(MIN_W, PAD_L + PAD_R + LABEL_PAD_X * 2.0 + widest)
	var n := _items.size()
	var h := PAD_Y * 2.0 + ROW_H * n + ROW_GAP * maxf(n - 1, 0)
	_inner = Rect2(Vector2.ZERO, Vector2(ceilf(w), ceilf(h)))

	_panel = _box.make_side_panel()
	add_child(_panel)

	_pill = _box.make_speaker_pill(Vector2(_inner.size.x - PAD_L - PAD_R, ROW_H))
	add_child(_pill)

	for i in n:
		var lbl := Label.new()
		lbl.text = _label_text(i)
		lbl.add_theme_font_override("font", _font())
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.add_theme_constant_override("font_spacing_glyph", _track())
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)
		_labels.append(lbl)

		# The click target: the whole row, not just the text.
		var hit := Control.new()
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.mouse_entered.connect(func() -> void:
			if not _done and _cursor != i:
				_set_cursor(i)
				SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select))
		hit.gui_input.connect(func(e: InputEvent) -> void:
			if UIInput.is_click(e) and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				if not _done:
					_set_cursor(i, false)
					accept())
		add_child(hit)
		_hits.append(hit)


func _row_rect(i: int) -> Rect2:
	return Rect2(_inner.position + Vector2(PAD_L, PAD_Y + (ROW_H + ROW_GAP) * i),
			Vector2(_inner.size.x - PAD_L - PAD_R, ROW_H))


## Bottom-right on the box's top-right corner, DOCK_GAP above it.
func _dock() -> void:
	_docked_at = _box.panel_top_right()
	_inner.position = _docked_at - Vector2(_inner.size.x, _inner.size.y + DOCK_GAP)
	var pad: float = DynamicMessageBox.SIDE_PANEL_PAD
	_panel.position = _inner.position - Vector2(pad, pad)
	_panel.size = _inner.size + Vector2(pad, pad) * 2.0
	_box.paint_side_panel(_panel)
	for i in _labels.size():
		var r := _row_rect(i)
		var lbl: Label = _labels[i]
		lbl.position = r.position + Vector2(LABEL_PAD_X, 0.0)
		lbl.size = Vector2(r.size.x - LABEL_PAD_X * 2.0, r.size.y)
		var hit: Control = _hits[i]
		hit.position = r.position
		hit.size = r.size
	_set_cursor(_cursor, false)


func _set_cursor(i: int, _animate: bool = true) -> void:
	if _items.is_empty():
		return
	_cursor = i
	var r := _row_rect(i)
	_pill.position = r.position
	for j in _labels.size():
		var lbl: Label = _labels[j]
		if j == i:
			# The name pill's type treatment: white with a soft drop shadow on the colour.
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
			lbl.add_theme_constant_override("shadow_offset_x", 1)
			lbl.add_theme_constant_override("shadow_offset_y", 1)
		else:
			lbl.add_theme_color_override("font_color", _ui().col("field_fg"))
			lbl.remove_theme_color_override("font_shadow_color")
	# The selection ring - the same cursor the box's Yes / No buttons wear.
	if _ring != null and is_instance_valid(_ring):
		remove_child(_ring)
		_ring.queue_free()
	# (It sets the ring's position before parenting it, so the rect is in OUR space.)
	_ring = UIKit.add_selection_ring_rect(self, r, ROW_H * 0.5)


func _finish(was_chosen: bool, id: String) -> void:
	_done = true
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select if was_chosen
			else SoundManagerScript.SFX_minus_select)
	queue_free()
	if was_chosen:
		chosen.emit(id)
	else:
		cancelled.emit()


func _ui() -> Node:
	return Engine.get_main_loop().get_root().get_node_or_null("/root/UITheme")
