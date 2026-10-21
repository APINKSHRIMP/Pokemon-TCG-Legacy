class_name IntroDeckChoice
extends Control

# ============================================================
# OLLY'S DECK CHOICE — three decks fanned out over the map
# ============================================================
# Four of each deck's headline cards spread like a hand, with the deck's name under
# them and a system box along the bottom ("Choose which deck you want to keep").
# Hovering a deck makes the whole group grow and shrink together; clicking it (or
# Left/Right + Enter) emits `picked` with the pair stem ("Water Fight", ...). The
# caller asks "are you sure?" and either frees this or calls reoffer().
#
#   var choice := IntroDeckChoice.show_on(_ui_layer, " Starter Deck")
#   var pair: String = await choice.picked

signal picked(pair: String)

# Each pair's four showcase cards, for the Starter Decks and the full Decks.
const SHOWCASE := {
	" Starter Deck": {
		"Water Fight": ["base1-63", "base1-65", "base1-52", "base1-47"],
		"Grass Psy":   ["base1-44", "base1-55", "base1-49", "base1-43"],
		"Fire Shock":  ["base1-46", "base1-60", "base1-58", "base1-53"],
	},
	" Deck": {
		"Water Fight": ["base1-42", "base1-64", "base1-34", "base1-19"],
		"Grass Psy":   ["base1-30", "base1-37", "base1-49", "base1-32"],
		"Fire Shock":  ["base1-24", "base1-23", "base1-14", "base1-9"],
	},
}
const PROMPT_TEXT := "Choose which deck you want to keep"

# ── TWEAKABLE layout (1920x1080 reference px) ─────────────────────────────
const CARD_SIZE      := Vector2(170.0, 237.0)   # one card in a fan
const FAN_STEP       := Vector2(78.0, 10.0)     # each card sits this far right/down of the last
const GROUP_CENTRES  := [380.0, 960.0, 1540.0]  # x centre of each deck group, left to right
const GROUP_TOP_Y    := 210.0                   # top of the first card in each fan
const NAME_GAP       := 34.0                    # fan bottom -> deck name
const NAME_SIZE      := 44
const NAME_OUTLINE   := 10
const PULSE_SCALE    := 1.07                    # hovered group grows to this...
const PULSE_TIME     := 0.45                    # ...and back, every PULSE_TIME * 2 seconds
const PROMPT_HEIGHT  := 138.0

var _suffix: String = ""
var _groups: Array[Control] = []
var _pairs: Array = []
var _hovered: int = -1
var _pulse: Tween = null
var _armed: bool = false


static func show_on(parent: Node, suffix: String) -> IntroDeckChoice:
	var choice := IntroDeckChoice.new()
	choice._suffix = suffix
	parent.add_child(choice)
	return choice


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pairs = GameState.STARTER_DECK_PAIRS.duplicate()
	for i in _pairs.size():
		_groups.append(_build_group(_pairs[i], GROUP_CENTRES[i]))
	_build_prompt()
	# One frame before clicks count, so the click that closed Olly's last line
	# cannot land on a deck.
	await get_tree().process_frame
	_armed = true


func _build_group(pair: String, centre_x: float) -> Control:
	var ids: Array = SHOWCASE.get(_suffix, SHOWCASE[" Deck"]).get(pair, [])
	var fan_w: float = CARD_SIZE.x + FAN_STEP.x * (ids.size() - 1)
	var fan_h: float = CARD_SIZE.y + FAN_STEP.y * (ids.size() - 1)

	# The group is the hover target and the thing that pulses, so it is sized to cover
	# the fan and the name together and pivots on its middle.
	var group := Control.new()
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(group)

	for i in ids.size():
		var rect := TextureRect.new()
		rect.texture = load(_card_path(ids[i]))
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = CARD_SIZE
		rect.position = FAN_STEP * i
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Later cards UNDER earlier ones, as in a hand held up: the first card is the hero.
		rect.z_index = ids.size() - i
		group.add_child(rect)

	var label := Label.new()
	UIKit.set_label(label, "title", pair + _suffix, "field_fg", NAME_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", NAME_OUTLINE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(maxf(fan_w, 420.0), NAME_SIZE * 2.6)
	label.position = Vector2((fan_w - label.size.x) * 0.5, fan_h + NAME_GAP)
	group.add_child(label)

	group.size = Vector2(fan_w, label.position.y + label.size.y)
	group.position = Vector2(centre_x - fan_w * 0.5, GROUP_TOP_Y)
	group.pivot_offset = group.size * 0.5

	var index := _groups.size()
	group.mouse_entered.connect(_set_hovered.bind(index))
	group.mouse_exited.connect(func() -> void:
		if _hovered == index:
			_set_hovered(-1))
	group.gui_input.connect(_on_group_input.bind(index))
	return group


func _build_prompt() -> void:
	var built := MessageBoxHelper.build(PROMPT_HEIGHT, -1, false)
	var box: DynamicMessageBox = built["root"]
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.set_system_variant(true)
	box.show_advance_caret(false)
	box.set_body_text(PROMPT_TEXT)


func _card_path(card_id: String) -> String:
	var set_code: String = card_id.split("-")[0]
	return "res://Image_Assets/Card_Image_Library/" + set_code + "/Large/" + AssetLookup.card_image_name(card_id) + ".png"


# ── Hover: the whole group breathes ─────────────────────────────────────────

func _set_hovered(index: int) -> void:
	if index == _hovered:
		return
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	if _hovered >= 0:
		var old := _groups[_hovered]
		var back := old.create_tween()
		back.tween_property(old, "scale", Vector2.ONE, PULSE_TIME * 0.5)
	_hovered = index
	if index < 0:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	var g := _groups[index]
	_pulse = g.create_tween().set_loops()
	_pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(g, "scale", Vector2(PULSE_SCALE, PULSE_SCALE), PULSE_TIME)
	_pulse.tween_property(g, "scale", Vector2.ONE, PULSE_TIME)


func _on_group_input(event: InputEvent, index: int) -> void:
	if _armed and UIInput.is_click(event):
		accept_event()
		_choose(index)


# Keys: Left/Right move the highlight, Enter/Space takes it. Every key is swallowed
# so nothing reaches the map behind the choice.
func _input(event: InputEvent) -> void:
	if not _armed or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_set_hovered(wrapi(_hovered - 1, 0, _groups.size()) if _hovered >= 0 else 0)
			KEY_RIGHT, KEY_D:
				_set_hovered(wrapi(_hovered + 1, 0, _groups.size()) if _hovered >= 0 else 0)
			_:
				if UIInput.is_accept(event) and _hovered >= 0:
					_choose(_hovered)
		get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	_armed = false
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	visible = false
	picked.emit(_pairs[index])


## The player answered No to "are you sure?": show the decks again.
func reoffer() -> void:
	_set_hovered(-1)
	visible = true
	await get_tree().process_frame
	_armed = true
