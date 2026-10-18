extends Control

# ============================================================
# SAVE SELECT — the three save slots behind the title screen
# ============================================================
# Built by the boot splash (Game_Start_Load_Splash_Script.gd) after "Press any
# key", and freed again when the player backs out. The splash owns the fades and
# the hand-off into the game; this screen only draws the slots, tracks which one
# is selected, and reports the choice through its three signals.
#
# One slot is always selected, and it wears the rotating selection ring. A slot
# with a save offers CONTINUE GAME (positive green), an empty one NEW GAME
# (neutral blue). The bin top-right deletes the selected save, behind a yes/no,
# and is dead while an empty slot is selected.
#
# Nothing here LOADS a slot. Each one is read through GameState.get_slot_summary(),
# which reads its files without touching the live save; the splash calls
# GameState.load_slot() / start_new_game() once the player commits.
#
# Controls: click a slot to select it, double-click to play it. Left / Right
# (arrows or d-pad) move the selection, Space / Enter / pad A press the main
# button, Escape / pad B cancel, Delete / pad X open the bin.
# ============================================================

signal cancelled
signal continue_chosen(slot: int)
signal new_game_chosen(slot: int)

const SPRITE_FOLDER := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"

# ─── Layout (1920x1080 reference space) — ALL TWEAKABLE ──────────────────────
const SLOT_W    := 460.0   # width of one slot column
const SLOT_GAP  := 60.0    # gap between columns; the three are centred as a block
const SLOT_TOP  := 96.0    # top of the upper panel
const TOP_H     := 600.0   # upper panel: sprite, then sleeve + coin (the plus when empty)
const PANEL_GAP := 14.0    # gap between the upper and lower panel
const BOT_H     := 196.0   # lower panel: name + deck, or EMPTY
const PAD       := 18.0    # inner padding of both panels

const NAME_BOX_H := 58.0   # empty slot: the dark box holding "Save Slot N"
const NAME_FONT  := 56     # the player's name — EMPTY's size and face
const NAME_H     := 72.0
const DECK_FONT  := 26     # "Deck: X", smaller, under the name
const DECK_H     := 36.0
const DECK_GAP   := 4.0    # name -> "Deck:" line
const SPRITE_GAP := 12.0   # sprite's feet -> the sleeve and coin

const EQUIP_SIZE := Vector2(96.0, 132.0)   # sleeve / coin thumbnail, as on the trainer card
const EQUIP_GAP  := 60.0   # space between the sleeve and the coin

const PLUS_LEN    := 220.0  # empty slot: length of each arm of the plus
const PLUS_THICK  := 34.0
const PLUS_ALPHA  := 0.35
const SLOT_LABEL_FONT := 34
const SLOT_LABEL_LIFT := 40.0   # empty slot: "Save Slot N" box sits this far above the panel's bottom padding
const EMPTY_FONT  := 56

const BIN_SIZE   := 80.0
const BIN_MARGIN := 34.0       # from the top and right screen edges
const BIN_DEAD_ALPHA := 0.35   # the bin while an empty slot is selected
const RING_RADIUS := 18.0

const BTN_LABELS := ["Cancel", "New Game", "Continue Game"]

# ─── State ───────────────────────────────────────────────────────────────────

## False while the splash is fading this screen in or out, so a key cannot fire
## a choice mid-fade. The splash flips it.
var active: bool = false

var _host: Node = null
var _selected: int = 1
var _summaries: Dictionary = {}    # slot -> GameState.get_slot_summary() ({} = empty)
var _holders: Dictionary = {}      # slot -> Control
var _slot_root: Control
var _ring_layer: Control
var _ring: Control = null

var _bin: Button
var _cancel_holder: Control
var _primary_holder: Control
var _cancel_btn: Button
var _primary_btn: Button

var _confirm_box: DynamicMessageBox = null
var _chose: bool = false


## `host` is the splash. Its shader buttons are reused so this screen's buttons
## match the title screen's exactly.
func setup(host: Node) -> void:
	_host = host


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(UIKit.SCREEN_W, UIKit.SCREEN_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_slot_root = Control.new()
	_slot_root.name = "slots"
	_slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_root)

	_ring_layer = Control.new()
	_ring_layer.name = "ring_layer"
	_ring_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring_layer)

	_build_buttons()
	_build_bin()

	_selected = _default_slot()
	_refresh_slots()


## The last slot played if it still holds a save, else the first save there is,
## else slot 1.
func _default_slot() -> int:
	if GameState.slot_has_save(GameState.current_slot):
		return GameState.current_slot
	for s in range(1, GameState.SAVE_SLOT_COUNT + 1):
		if GameState.slot_has_save(s):
			return s
	return 1


# ============================================================
# SLOTS
# ============================================================

## Re-reads every slot off disk and rebuilds the three columns. Called on open and
## after a delete.
func _refresh_slots() -> void:
	for child in _slot_root.get_children():
		_slot_root.remove_child(child)
		child.queue_free()
	_holders.clear()

	var count: int = GameState.SAVE_SLOT_COUNT
	var total_w: float = SLOT_W * count + SLOT_GAP * (count - 1)
	var left: float = (UIKit.SCREEN_W - total_w) * 0.5

	for s in range(1, count + 1):
		_summaries[s] = GameState.get_slot_summary(s)
		var holder := _build_slot(s, _summaries[s])
		holder.position = Vector2(left + (s - 1) * (SLOT_W + SLOT_GAP), SLOT_TOP)
		_slot_root.add_child(holder)
		_holders[s] = holder

	_select(_selected, false)


func _build_slot(slot: int, summary: Dictionary) -> Control:
	var holder := Control.new()
	holder.name = "slot_%d" % slot
	holder.size = Vector2(SLOT_W, TOP_H + PANEL_GAP + BOT_H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := UIKit.make_panel()
	top.position = Vector2.ZERO
	top.size = Vector2(SLOT_W, TOP_H)
	top.custom_minimum_size = top.size
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(top)

	var bot := UIKit.make_panel()
	bot.position = Vector2(0.0, TOP_H + PANEL_GAP)
	bot.size = Vector2(SLOT_W, BOT_H)
	bot.custom_minimum_size = bot.size
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bot)

	if summary.is_empty():
		_fill_empty_slot(holder, slot)
	else:
		_fill_saved_slot(holder, summary)

	# The click catcher is LAST so it is the thing that receives the click — a
	# catcher that is not last catches nothing.
	var catcher := Button.new()
	catcher.name = "catcher"
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		catcher.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	catcher.position = Vector2.ZERO
	catcher.size = holder.size
	catcher.pressed.connect(_on_slot_clicked.bind(slot))
	catcher.gui_input.connect(_on_slot_gui_input.bind(slot))
	holder.add_child(catcher)
	return holder


## Sprite on top with the sleeve and coin under its feet; the name (in EMPTY's
## style) and "Deck: X" in the lower panel.
func _fill_saved_slot(holder: Control, summary: Dictionary) -> void:
	var inner_w: float = SLOT_W - PAD * 2.0
	var y: float = PAD

	# Sleeve and coin along the bottom of the upper panel.
	var thumb_y: float = TOP_H - PAD - EQUIP_SIZE.y
	var x: float = SLOT_W * 0.5 - (EQUIP_SIZE.x * 2.0 + EQUIP_GAP) * 0.5

	var sleeve: String = summary["sleeve"]
	if sleeve != "":
		_add_thumb(holder, GameState.SLEEVE_SMALL_FOLDER + "/" + sleeve + ".jpg", Vector2(x, thumb_y))
	x += EQUIP_SIZE.x + EQUIP_GAP

	var coin: String = summary["coin"]
	if coin != "":
		if not coin.ends_with(".png"):
			coin += ".png"
		_add_thumb(holder, GameState.COIN_ASSET_FOLDER + "/" + coin, Vector2(x, thumb_y))

	# Name and deck, centred as one block in the lower panel.
	var block_h: float = NAME_H + DECK_GAP + DECK_H
	var name_y: float = TOP_H + PANEL_GAP + (BOT_H - block_h) * 0.5

	var player_name: String = summary["name"]
	var name_lbl := _make_label(player_name if player_name != "" else "Trainer",
		UITheme.FONT_UI_BOLD, NAME_FONT, UITheme.col("field_fg"))
	name_lbl.position = Vector2(PAD, name_y)
	name_lbl.size = Vector2(inner_w, NAME_H)
	holder.add_child(name_lbl)

	var deck_name: String = summary["deck"]
	var deck_lbl := _make_label("Deck: " + (deck_name if deck_name != "" else "--"),
		UITheme.FONT_UI_MEDIUM, DECK_FONT, UITheme.col("field_mute"))
	deck_lbl.position = Vector2(PAD, name_y + NAME_H + DECK_GAP)
	deck_lbl.size = Vector2(inner_w, DECK_H)
	holder.add_child(deck_lbl)

	# The sprite takes the rest of the upper panel, above the sleeve and coin.
	var fit := Vector2(inner_w, thumb_y - SPRITE_GAP - y)
	var sprite_name: String = summary["sprite"]
	if sprite_name != "":
		if not sprite_name.ends_with(".png"):
			sprite_name += ".png"
		var path := SPRITE_FOLDER + sprite_name
		if ResourceLoader.exists(path):
			# Fit the CHARACTER, not its padded canvas (same as the trainer card, #399).
			var tex: Texture2D = UIKit.visible_sprite(load(path))
			if tex != null:
				var rect := TextureRect.new()
				rect.texture = tex
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_SCALE
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var tex_size := tex.get_size()
				var s := minf(fit.x / tex_size.x, fit.y / tex_size.y)
				rect.size = tex_size * s
				# Centred across, sitting on the bottom of its box so the feet meet the
				# sleeve and coin.
				rect.position = Vector2(PAD + (fit.x - rect.size.x) * 0.5, y + fit.y - rect.size.y)
				holder.add_child(rect)


## A big plus, "Save Slot N", and EMPTY in the lower panel.
func _fill_empty_slot(holder: Control, slot: int) -> void:
	var label_y: float = TOP_H - PAD - NAME_BOX_H - SLOT_LABEL_LIFT
	_add_name_box(holder, "Save Slot %d" % slot, label_y)

	# ONE twelve-point outline, not two crossed bars: the plus is translucent, and
	# two overlapping rectangles double up into a darker square in the middle.
	var plus_col: Color = UITheme.col("field_fg")
	plus_col.a = PLUS_ALPHA
	var c := Vector2(SLOT_W * 0.5, label_y * 0.5)
	var a: float = PLUS_LEN * 0.5
	var t: float = PLUS_THICK * 0.5
	var points := PackedVector2Array([
		c + Vector2(-t, -a), c + Vector2(t, -a), c + Vector2(t, -t),
		c + Vector2(a, -t), c + Vector2(a, t), c + Vector2(t, t),
		c + Vector2(t, a), c + Vector2(-t, a), c + Vector2(-t, t),
		c + Vector2(-a, t), c + Vector2(-a, -t), c + Vector2(-t, -t),
	])
	var plus := Control.new()
	plus.name = "plus"
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plus.size = holder.size
	plus.draw.connect(func() -> void: plus.draw_colored_polygon(points, plus_col))
	holder.add_child(plus)

	var empty := _make_label("EMPTY", UITheme.FONT_UI_BOLD, EMPTY_FONT, UITheme.col("field_fg"))
	empty.position = Vector2(0.0, TOP_H + PANEL_GAP)
	empty.size = Vector2(SLOT_W, BOT_H)
	holder.add_child(empty)


## The dark rounded box "Save Slot N" sits in — the trainer card's name field, as
## a read-only label.
func _add_name_box(holder: Control, text: String, y: float) -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_border_width_all(1)
	sb.border_color = UITheme.col("line")
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(PAD, y)
	box.size = Vector2(SLOT_W - PAD * 2.0, NAME_BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)

	var lbl := _make_label(text, UITheme.FONT_UI_MEDIUM, SLOT_LABEL_FONT, UITheme.col("field_fg"))
	lbl.position = box.position
	lbl.size = box.size
	holder.add_child(lbl)


func _add_thumb(holder: Control, path: String, pos: Vector2) -> void:
	if not ResourceLoader.exists(path):
		return
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Sleeve and coin art are painted, not pixel art — nearest filtering shimmers.
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.position = pos
	rect.size = EQUIP_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rect)


## A centred, single-line, ellipsised label.
func _make_label(text: String, font_path: String, font_size: int, colour: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UITheme.font_at(font_path))
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", colour)
	return lbl


# ============================================================
# SELECTION
# ============================================================

func _select(slot: int, with_sound: bool = true) -> void:
	_selected = slot
	if with_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)

	if _ring != null and is_instance_valid(_ring):
		_ring_layer.remove_child(_ring)
		_ring.queue_free()
	_ring = UIKit.add_selection_ring(_ring_layer, _holders[slot], RING_RADIUS)

	var has_save: bool = not (_summaries[slot] as Dictionary).is_empty()
	_set_primary(has_save)
	_bin.disabled = not has_save
	_bin.modulate.a = 1.0 if has_save else BIN_DEAD_ALPHA
	_bin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if has_save else Control.CURSOR_ARROW


func _on_slot_clicked(slot: int) -> void:
	if not active or _confirm_box != null:
		return
	if slot != _selected:
		_select(slot)


## Double-click a slot to play it straight away.
func _on_slot_gui_input(event: InputEvent, slot: int) -> void:
	if not active or _confirm_box != null:
		return
	if event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if slot != _selected:
			_select(slot)
		_on_primary_pressed()


func _step(direction: int) -> void:
	var count: int = GameState.SAVE_SLOT_COUNT
	_select(wrapi(_selected - 1 + direction, 0, count) + 1)


# ============================================================
# BUTTONS
# ============================================================

func _build_buttons() -> void:
	var w: float = 0.0
	for t in BTN_LABELS:
		w = maxf(w, _host._button_width(t))
	var y: float = _host.button_row_y()
	var gap: float = _host.button_gap()

	# Cancel left of the centre line, the main button right of it — the same
	# positions New Game and Continue Game used to hold on the title screen.
	_cancel_holder = _host._make_button("Cancel", w,
		UITheme.splash_col("cancel_top"), UITheme.splash_col("cancel_bot"),
		UITheme.splash_col("cancel_fg"))
	_cancel_holder.position = Vector2(UIKit.SCREEN_W * 0.5 - gap * 0.5 - w, y)
	_cancel_btn = _cancel_holder.get_node("btn")
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	add_child(_cancel_holder)

	_primary_holder = _host._make_button("New Game", w,
		UITheme.splash_col("new_game_top"), UITheme.splash_col("new_game_bot"),
		UITheme.splash_col("new_game_fg"))
	_primary_holder.position = Vector2(UIKit.SCREEN_W * 0.5 + gap * 0.5, y)
	_primary_btn = _primary_holder.get_node("btn")
	_primary_btn.pressed.connect(_on_primary_pressed)
	add_child(_primary_holder)


## CONTINUE GAME in the positive green for a save, NEW GAME in the neutral blue
## for an empty slot. Same button, repainted.
func _set_primary(has_save: bool) -> void:
	var prefix := "continue" if has_save else "new_game"
	_primary_btn.text = ("Continue Game" if has_save else "New Game").to_upper()
	var mat: ShaderMaterial = (_primary_holder.get_node("face") as CanvasItem).material
	mat.set_shader_parameter("fill_top", UITheme.splash_col(prefix + "_top"))
	mat.set_shader_parameter("fill_bot", UITheme.splash_col(prefix + "_bot"))
	var fg: Color = UITheme.splash_col(prefix + "_fg")
	for colour_state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		_primary_btn.add_theme_color_override(colour_state, fg)


func _build_bin() -> void:
	_bin = Button.new()
	_bin.name = "delete_save"
	_bin.tooltip_text = "Delete this save"
	UIKit.style_button(_bin, "danger")
	_bin.focus_mode = Control.FOCUS_NONE
	_bin.custom_minimum_size = Vector2(BIN_SIZE, BIN_SIZE)
	_bin.size = Vector2(BIN_SIZE, BIN_SIZE)
	_bin.position = Vector2(UIKit.SCREEN_W - BIN_MARGIN - BIN_SIZE, BIN_MARGIN)

	# MOUSE_FILTER_IGNORE so the glyph never eats the click meant for the button.
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.draw.connect(func() -> void: UIKit.draw_trash_icon(glyph, Color(1, 1, 1, 0.95)))
	_bin.add_child(glyph)

	_bin.pressed.connect(_on_bin_pressed)
	add_child(_bin)


func _on_cancel_pressed() -> void:
	if not active or _confirm_box != null or _chose:
		return
	_chose = true
	active = false
	UIKit.hold_buttons([_cancel_btn, _primary_btn, _bin], true)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	cancelled.emit()


func _on_primary_pressed() -> void:
	if not active or _confirm_box != null or _chose:
		return
	_chose = true
	active = false
	UIKit.hold_buttons([_cancel_btn, _primary_btn, _bin], true)
	if (_summaries[_selected] as Dictionary).is_empty():
		new_game_chosen.emit(_selected)
	else:
		continue_chosen.emit(_selected)


# ============================================================
# DELETE
# ============================================================

func _on_bin_pressed() -> void:
	if not active or _confirm_box != null or _chose:
		return
	var summary: Dictionary = _summaries[_selected]
	if summary.is_empty():
		return
	var who: String = summary["name"] if String(summary["name"]) != "" else "this save"
	_show_confirm("Delete Save Slot %d (%s)? Its progress, cards and decks will be gone for good."
		% [_selected, who])


## The game's standard system-variant yes/no box, as the old New Game confirm was.
func _show_confirm(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "confirm_layer"
	layer.layer = 100
	add_child(layer)

	var built := MessageBoxHelper.build(138.0, -1, true)
	_confirm_box = built["root"]
	_confirm_box.show_as_plain()
	_confirm_box.set_mode("choices")
	layer.add_child(_confirm_box)
	_confirm_box.set_body_text(text)
	_confirm_box.visible = true

	(built["yes_btn"] as Button).pressed.connect(_on_delete_confirmed)
	(built["no_btn"] as Button).pressed.connect(_dismiss_confirm)


func _on_delete_confirmed() -> void:
	if _confirm_box == null:
		return
	_dismiss_confirm()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	GameState.delete_slot(_selected)
	_refresh_slots()


func _dismiss_confirm() -> void:
	_confirm_box = null
	var layer := get_node_or_null("confirm_layer")
	if layer != null:
		remove_child(layer)
		layer.queue_free()


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not active:
		return

	# The confirm box owns the keyboard while it is up: Escape means "no".
	if _confirm_box != null and is_instance_valid(_confirm_box):
		if UIInput.is_accept(event):
			get_viewport().set_input_as_handled()
			_on_delete_confirmed()
		elif UIInput.is_cancel(event):
			get_viewport().set_input_as_handled()
			_dismiss_confirm()
		return

	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
	elif UIInput.is_accept(event):
		get_viewport().set_input_as_handled()
		_on_primary_pressed()
	elif event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_step(1)
	elif _is_delete(event):
		get_viewport().set_input_as_handled()
		_on_bin_pressed()


func _is_delete(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == KEY_DELETE
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_X
	return false
