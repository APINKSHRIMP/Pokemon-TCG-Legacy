class_name NoteOverlay
extends Control

# ============================================================
# THE NOTE — a hand-written note flown up over a darkened screen
# ============================================================
# Exactly the way the phone arrives in a call (Phone_Call.gd): it sails a little past
# its resting place and settles back, then dips upward before dropping away on the
# click that dismisses it. Used for Mum's note through the front door on the arrival
# night (Player_House_Downstairs).
#
#   var note := NoteOverlay.show_on(_ui_layer)
#   await note.closed
#
# While it is up it owns every click and key (_input runs before GUI picking and
# before the map's own _input, so Escape cannot open the pause menu behind it).

signal closed

const NOTE_TEXTURE       := "res://Image_Assets/Assorted_Extras/Note.png"
# TWEAKABLE
const NOTE_DIM_ALPHA     := 0.75   # darkness of the translucent blocker behind the note
const NOTE_HEIGHT        := 0.92   # note height as a fraction of the screen's height
const NOTE_RISE_TIME     := 0.45   # note flies in from the bottom
const NOTE_DROP_TIME     := 0.38   # note flies off the bottom
const NOTE_OVERSHOOT     := 18.0   # px past the resting place at each end of the flight
const NOTE_OFFSCREEN_PAD := 40.0   # how far below the screen edge it waits and lands

var _image: TextureRect = null
var _dim: ColorRect = null
var _dismissable: bool = false


static func show_on(parent: Node) -> NoteOverlay:
	var note := NoteOverlay.new()
	parent.add_child(note)
	return note


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size

	# STOP so nothing behind the dim can be clicked through it.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, NOTE_DIM_ALPHA)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.modulate.a = 0.0
	add_child(_dim)

	# EXPAND_IGNORE_SIZE is load-bearing: without it a TextureRect's minimum size is its TEXTURE's
	# size and a Control can never be smaller than its minimum.
	var tex: Texture2D = load(NOTE_TEXTURE)
	var src := Vector2(float(tex.get_width()), float(tex.get_height()))
	_image = TextureRect.new()
	_image.texture = tex
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fit: float = vp.y * NOTE_HEIGHT / maxf(1.0, src.y)
	_image.size = src * fit
	_image.position = Vector2((vp.x - _image.size.x) * 0.5, vp.y + NOTE_OFFSCREEN_PAD)
	_image.modulate.a = 0.0
	add_child(_image)

	var rest_y: float = (vp.y - _image.size.y) * 0.5

	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_dim, "modulate:a", 1.0, NOTE_RISE_TIME * 0.8)
	fade.tween_property(_image, "modulate:a", 1.0, NOTE_RISE_TIME * 0.6)

	var rise := create_tween()
	rise.tween_property(_image, "position:y", rest_y - NOTE_OVERSHOOT, NOTE_RISE_TIME * 0.78) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	rise.tween_property(_image, "position:y", rest_y, NOTE_RISE_TIME * 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Only dismissable once it has landed, so the click that closed the message before it
	# cannot carry through and skip the note the instant it appears.
	rise.tween_callback(func() -> void: _dismissable = true)


func _input(event: InputEvent) -> void:
	# UIInput, not raw keycodes: is_click ignores a mouse-wheel notch and is_advance covers
	# Space, Enter and Escape alike. Every other key and button is swallowed too.
	if _dismissable and (UIInput.is_click(event) or UIInput.is_advance(event)):
		_dismissable = false
		_hide()
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _hide() -> void:
	var vp := get_viewport().get_visible_rect().size
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_image, "modulate:a", 0.0, NOTE_DROP_TIME)
	fade.tween_property(_dim, "modulate:a", 0.0, NOTE_DROP_TIME)

	var leave := create_tween()
	leave.tween_property(_image, "position:y", _image.position.y - NOTE_OVERSHOOT, NOTE_DROP_TIME * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	leave.tween_property(_image, "position:y", vp.y + NOTE_OFFSCREEN_PAD, NOTE_DROP_TIME * 0.75) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	leave.tween_callback(func() -> void:
		closed.emit()
		queue_free())
