class_name IntroDeckChoice
extends Control

# ============================================================
# OLLY'S DECK CHOICE — three decks fanned out over the map
# ============================================================
# Each deck's box at the front of four of its headline cards spread like a hand, with the deck's name under
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
# The boxed deck, the front card of each fan (Image_Assets/Packs/<id>.png).
const DECK_ART := {"Fire Shock": "starterdeck1_a", "Grass Psy": "starterdeck1_b", "Water Fight": "starterdeck1_c"}

# ── TWEAKABLE layout (1920x1080 reference px) ─────────────────────────────
const CARD_SIZE      := Vector2(170.0, 237.0)   # one card in a fan
const FAN_STEP       := Vector2(78.0, 10.0)     # each card sits this far right/down of the last
const GROUP_CENTRES  := [320.0, 960.0, 1600.0]  # x centre of each deck group (box included)
const CARDS_MID_Y    := 540.0                   # the middle of the fan sits here (screen middle)
const NAME_GAP       := 34.0                    # fan bottom -> deck name
# The deck box is the front card of the fan (left, over the other four), centred on a
# card's height.
const BOX_HEIGHT     := 250.0
const NAME_SIZE      := 44
const PULSE_SCALE    := 1.07                    # hovered group grows to this...
const PULSE_TIME     := 0.45                    # ...and back, every PULSE_TIME * 2 seconds
const PROMPT_HEIGHT  := 138.0

# ── TWEAKABLE entrance ──────────────────────────────────────────────────────
# The screen dims and the prompt appears, then each deck flies up from below while
# fading in from transparent, one after another. Played again after a "No".
const DIM_ALPHA       := 0.8    # how dark the screen goes (the gift screen's darkness)
const DIM_FADE_TIME   := 0.4    # the dim and the prompt fade up FIRST; the decks follow
const DECK_FLY_TIME   := 1.0    # one deck's flight + fade
const DECK_FLY_STAGGER := 0.5   # from one deck setting off to the next
const DECK_FLY_FROM_Y := 520.0  # how far below its resting place a deck starts
# Once the third deck has landed, each fan's cards fade in sliding out from behind the
# box to their spots, left to right, CARD_DEAL_STAGGER apart (all three decks together).
const CARD_DEAL_TIME    := 0.45
const CARD_DEAL_STAGGER := 0.12

var _suffix: String = ""
var _groups: Array[Control] = []
var _pairs: Array = []
var _hovered: int = -1
var _pulse: Tween = null
var _armed: bool = false
var _dim: ColorRect = null
var _prompt: Control = null
var _rest_y: Array = []          # each group's resting y, for the entrance
var _cards: Array = []           # per group: its fan cards, front to back
var _entrance: Tween = null


static func show_on(parent: Node, suffix: String) -> IntroDeckChoice:
	var choice := IntroDeckChoice.new()
	choice._suffix = suffix
	parent.add_child(choice)
	return choice


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pairs = GameState.STARTER_DECK_PAIRS.duplicate()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, DIM_ALPHA)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind the decks is clickable
	add_child(_dim)
	for i in _pairs.size():
		_cards.append([])
		_groups.append(_build_group(_pairs[i], GROUP_CENTRES[i]))
		_rest_y.append(_groups[i].position.y)
	_build_prompt()
	_play_entrance()


## Dim + prompt fade up, then the decks fly in one by one. Clicks and keys are armed
## only once the last deck has landed.
func _play_entrance() -> void:
	_armed = false
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	_dim.modulate.a = 0.0
	_prompt.modulate.a = 0.0
	for i in _groups.size():
		_groups[i].scale = Vector2.ONE
		_groups[i].position.y = _rest_y[i] + DECK_FLY_FROM_Y
		_groups[i].modulate.a = 0.0
	_entrance = create_tween().set_parallel(true)
	_entrance.tween_property(_dim, "modulate:a", 1.0, DIM_FADE_TIME)
	_entrance.tween_property(_prompt, "modulate:a", 1.0, DIM_FADE_TIME)
	for i in _groups.size():
		var start: float = DIM_FADE_TIME + DECK_FLY_STAGGER * i
		var g: Control = _groups[i]
		# Up from below, slowing, a few px past its spot and back down onto it.
		UIKit.fly_in(g, Vector2(g.position.x, _rest_y[i] + DECK_FLY_FROM_Y),
				Vector2(g.position.x, _rest_y[i]), DECK_FLY_TIME, start)
	# Then the cards: out from behind each box, left to right, fading in as they go.
	var deal_start: float = DIM_FADE_TIME + DECK_FLY_STAGGER * (_groups.size() - 1) + DECK_FLY_TIME
	var most_cards: int = 0
	for fan in _cards:
		most_cards = maxi(most_cards, fan.size())
		for c in fan.size():
			var card: Control = fan[c]
			var spot: Vector2 = FAN_STEP * (c + 1)
			UIKit.fly_in(card, Vector2(0.0, spot.y), spot, CARD_DEAL_TIME,
					deal_start + CARD_DEAL_STAGGER * c)
	_entrance.tween_interval(deal_start + CARD_DEAL_STAGGER * maxi(0, most_cards - 1) + CARD_DEAL_TIME)
	_entrance.chain().tween_callback(func() -> void: _armed = true)


func _build_group(pair: String, centre_x: float) -> Control:
	var ids: Array = SHOWCASE.get(_suffix, SHOWCASE[" Deck"]).get(pair, [])
	# The deck box is the front (left) slot of the fan; the four cards follow behind it.
	var slots: int = ids.size() + 1
	var fan_w: float = CARD_SIZE.x + FAN_STEP.x * (slots - 1)
	var fan_h: float = CARD_SIZE.y + FAN_STEP.y * (slots - 1)

	# The deck box: in front of every card, sitting where the first card would.
	var box_tex: Texture2D = load("res://Image_Assets/Packs/" + str(DECK_ART.get(pair, "starterdeck1_d")) + ".png")
	var box_size := Vector2(BOX_HEIGHT * 0.623, BOX_HEIGHT)
	if box_tex != null and box_tex.get_height() > 0:
		box_size.x = BOX_HEIGHT * float(box_tex.get_width()) / float(box_tex.get_height())
	var box_pos := Vector2(0.0, (CARD_SIZE.y - box_size.y) * 0.5)
	# Everything the group draws spans x 0 .. content_w; that whole width is centred.
	var content_w: float = fan_w

	# The group is the hover target and the thing that pulses, so it is sized to cover
	# the fan and the name together and pivots on its middle.
	var group := Control.new()
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(group)

	if box_tex != null:
		var box := TextureRect.new()
		box.texture = box_tex
		box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.stretch_mode = TextureRect.STRETCH_SCALE
		box.size = box_size
		box.position = box_pos
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.z_index = slots   # over every card
		group.add_child(box)

	for i in ids.size():
		var rect := TextureRect.new()
		rect.texture = load(_card_path(ids[i]))
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = CARD_SIZE
		rect.position = FAN_STEP * (i + 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Later cards UNDER earlier ones, as in a hand held up: the box is the hero.
		rect.z_index = ids.size() - i
		group.add_child(rect)
		_cards[_cards.size() - 1].append(rect)

	var label := Label.new()
	# The dialogue font, in sentence case -- the same face as every message box.
	UIKit.set_label(label, "body", pair + _suffix, "field_fg", NAME_SIZE)
	label.add_theme_font_override("font", UITheme.font_card("body"))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(maxf(content_w, 440.0), NAME_SIZE * 2.6)
	label.position = Vector2((content_w - label.size.x) * 0.5, fan_h + NAME_GAP)
	group.add_child(label)

	group.size = Vector2(content_w, label.position.y + label.size.y)
	# The middle of the CARDS on the screen's middle -- not the middle of cards + name.
	group.position = Vector2(centre_x - content_w * 0.5, CARDS_MID_Y - fan_h * 0.5)
	group.pivot_offset = Vector2(content_w * 0.5, fan_h * 0.5)

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
	_prompt = box
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
	if not _armed and index >= 0:
		return   # still flying in
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
	_play_entrance()
