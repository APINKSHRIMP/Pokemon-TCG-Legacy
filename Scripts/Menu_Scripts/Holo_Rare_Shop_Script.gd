extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const CARD_SETS       := ["base1", "base2", "base3"]
const TARGET_TYPES    := ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Colorless"]
const CARD_COST       := 400
const CARD_SIZE       := Vector2(265, 364)
const CARD_SEPARATION := 3
# ISSUE #115: the bought card was too small on screen. Up 50% (318x437 -> 477x655.5), which
# lands it in the same ballpark as the 430x600 a single card gets when handed over as a gift
# (MapManager.GIFT_CARD_SIZES). Aspect ratio is unchanged.
const REVEAL_SIZE     := Vector2(477, 655.5)
const CELESTE_HARBOUR := "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const CARD_BACK_PATH  := "res://Image_Assets/Sleeves/1_Default_English.png"  # ISSUE #50 sibling: cardback.png doesn't exist -> null texture

# ─── State ───────────────────────────────────────────────────────────────────

var _all_holo_rares  : Dictionary = {}
var _active_cards    : Array      = []
var _card_rects      : Array      = []
var _sparkles        : Array      = []
var _selected_idx    : int        = -1
var _active_tween    : Tween      = null
var player_cash      : int        = 0
var _in_purchase_seq : bool       = false
# ISSUE #116: the reveal's OK button, held so _input() can press it from the keyboard.
var _reveal_ok_btn   : Button     = null

# ─── Theme references ────────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")

# ─── Node references ─────────────────────────────────────────────────────────

@onready var card_hbox         : HBoxContainer = $card_hbox
@onready var buy_btn           : Button         = $card_buy_button
@onready var cancel_btn        : Button         = $buy_cancel_button
@onready var your_money_amount : Label          = $"MONEY LABELS"/your_money_amount
@onready var card_cost_amount  : Label          = $"MONEY LABELS"/card_cost_amount

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop2.ogg", true)

	_load_holo_rares()

	player_cash = GameState.get_cash()
	your_money_amount.text = str(player_cash)
	card_cost_amount.text  = str(CARD_COST)

	card_hbox.add_theme_constant_override("separation", CARD_SEPARATION)

	buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	await get_tree().process_frame
	_build_display()


# ─── Data loading ────────────────────────────────────────────────────────────

func _load_holo_rares() -> void:
	for set_id in CARD_SETS:
		var path : String = "res://Card_Set_Data/" + set_id + ".json"
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("HoloRareShop: cannot open " + path)
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if not data is Array:
			push_warning("HoloRareShop: unexpected format in " + path)
			continue
		for card in data:
			if card.get("rarity", "") != "Rare Holo":
				continue
			if card.get("supertype", "") != "Pokemon" and card.get("supertype", "") != "Pokémon":
				continue
			var types : Array = card.get("types", [])
			if types.is_empty():
				continue
			var type_name : String = types[0]
			if not _all_holo_rares.has(type_name):
				_all_holo_rares[type_name] = []
			_all_holo_rares[type_name].append({
				"id":        card.get("id", ""),
				"name":      card.get("name", ""),
				"types":     types,
				"supertype": card.get("supertype", ""),
			})


# ─── Display building ────────────────────────────────────────────────────────

func _build_display() -> void:
	for child in card_hbox.get_children():
		child.queue_free()
	for p in _sparkles:
		if is_instance_valid(p):
			p.queue_free()
	_sparkles.clear()
	_card_rects.clear()
	_active_cards.clear()
	_selected_idx = -1
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	buy_btn.disabled = true
	buy_btn.theme    = theme_kenney

	var slot_idx : int = 0
	for type_name in TARGET_TYPES:
		if not _all_holo_rares.has(type_name):
			continue
		var pool : Array = _all_holo_rares[type_name]
		if pool.is_empty():
			continue

		var card : Dictionary = pool[randi() % pool.size()]
		_active_cards.append(card)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		card_hbox.add_child(vbox)

		var set_id   : String   = card["id"].split("-")[0]
		var tex_path : String   = "res://Image_Assets/Card_Image_Library/" + set_id + "/Large/" + card["id"] + ".png"
		var tex      : Texture2D = load(tex_path) as Texture2D

		var rect := TextureRect.new()
		rect.texture             = tex
		rect.custom_minimum_size = CARD_SIZE
		rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.modulate            = Color(0.0, 0.0, 0.0, 1.0)
		rect.pivot_offset        = CARD_SIZE / 2.0
		rect.mouse_filter        = Control.MOUSE_FILTER_STOP
		vbox.add_child(rect)
		rect.gui_input.connect(_on_card_clicked.bind(slot_idx))
		_card_rects.append(rect)

		slot_idx += 1

	await get_tree().process_frame

	for i in _card_rects.size():
		var rect : TextureRect  = _card_rects[i]
		var cd   : Dictionary   = _active_cards[i]
		var p    : CPUParticles2D = _start_holo_sparkle(rect, cd)
		_sparkles.append(p)


# ─── Card interaction ────────────────────────────────────────────────────────

func _on_card_clicked(event: InputEvent, idx: int) -> void:
	if _in_purchase_seq:
		return
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return

	if idx == _selected_idx:
		return

	if _selected_idx >= 0 and _selected_idx < _card_rects.size():
		if _active_tween:
			_active_tween.kill()
			_active_tween = null
		_card_rects[_selected_idx].scale = Vector2.ONE

	_selected_idx = idx
	_apply_selected_animation(_card_rects[idx])
	_update_buy_button()


func _apply_selected_animation(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
	rect.pivot_offset = rect.size / 2.0
	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	tween.tween_property(rect, "scale", Vector2(1.1, 1.1), 0.2)
	tween.tween_property(rect, "scale", Vector2(1.0,  1.0),  0.2)


func _update_buy_button() -> void:
	var can_buy : bool = _selected_idx >= 0 and player_cash >= CARD_COST
	buy_btn.disabled = not can_buy
	buy_btn.theme    = theme_kenney_green if can_buy else theme_kenney


# ─── Purchase ────────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	if _in_purchase_seq or _selected_idx < 0:
		return
	var card : Dictionary = _active_cards[_selected_idx]
	player_cash -= CARD_COST
	GameState.add_cash(-CARD_COST)
	GameState.give_cards(card["id"])
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	await _show_card_reveal(card)
	your_money_amount.text = str(player_cash)
	await _build_display()


func _show_card_reveal(card: Dictionary) -> void:
	_in_purchase_seq    = true
	buy_btn.disabled    = true
	cancel_btn.disabled = true

	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)

	var dim := ColorRect.new()
	dim.color         = Color(0.0, 0.0, 0.0, 0.8)
	dim.anchor_right  = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(dim)

	var vp_size : Vector2 = get_viewport_rect().size

	var rev_set_id : String   = card["id"].split("-")[0]
	var rev_path   : String   = "res://Image_Assets/Card_Image_Library/" + rev_set_id + "/Large/" + card["id"] + ".png"
	var face_tex   : Texture2D = load(rev_path) as Texture2D

	var reveal_rect := TextureRect.new()
	reveal_rect.texture             = face_tex
	reveal_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	reveal_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reveal_rect.custom_minimum_size = REVEAL_SIZE
	reveal_rect.size                = REVEAL_SIZE
	reveal_rect.position            = Vector2(
		vp_size.x / 2.0 - REVEAL_SIZE.x / 2.0,
		vp_size.y / 2.0 - REVEAL_SIZE.y / 2.0 - 60.0
	)
	reveal_rect.pivot_offset = REVEAL_SIZE / 2.0
	reveal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(reveal_rect)

	# ISSUE #101 FIX ACTIVE: the sparkle used to start here, before the flip — so the card was still
	# spinning through its card-back frames while already glittering, which gave the reveal away and
	# looked wrong. Start it only once the flip has fully settled on the card face.
	var cd : Dictionary = {"id": card["id"], "supertype": card["supertype"], "types": card["types"]}

	var back_tex : Texture2D = load(CARD_BACK_PATH)
	await _play_flip_animation(reveal_rect, back_tex, face_tex)

	_start_holo_sparkle_on_layer(reveal_rect, cd, overlay_layer)

	var got_label := Label.new()
	got_label.text                 = "You got " + card["name"] + "!"
	got_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	got_label.position             = Vector2(160.0, reveal_rect.position.y + REVEAL_SIZE.y + 20.0)
	got_label.size                 = Vector2(1600.0, 80.0)
	got_label.add_theme_font_size_override("font_size", 50)
	got_label.add_theme_color_override("font_color", Color.WHITE)
	got_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(got_label)

	var ok_btn := Button.new()
	ok_btn.text     = "OK"
	ok_btn.size     = Vector2(400.0, 60.0)
	ok_btn.position = Vector2(vp_size.x / 2.0 - 200.0, got_label.position.y + 90.0)
	ok_btn.theme    = theme_kenney_green
	overlay_layer.add_child(ok_btn)
	_reveal_ok_btn = ok_btn   # ISSUE #116: _input() presses this from the keyboard

	await ok_btn.pressed

	_reveal_ok_btn = null
	overlay_layer.queue_free()
	cancel_btn.disabled = false
	_in_purchase_seq    = false


# ─── Holo sparkle (adapted from Pack_Opening_Manager.gd) ─────────────────────

func _start_holo_sparkle(card_rect: TextureRect, card_data: Dictionary) -> CPUParticles2D:
	return _start_holo_sparkle_on_layer(card_rect, card_data, self)


func _start_holo_sparkle_on_layer(card_rect: TextureRect, card_data: Dictionary, parent: Node) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	parent.add_child(particles)

	var card_size : Vector2 = card_rect.size
	particles.global_position       = card_rect.global_position + card_size / 2.0
	particles.z_index               = 5
	particles.amount                = 150
	particles.lifetime              = 2
	particles.one_shot              = false
	particles.explosiveness         = 0.1
	particles.emitting              = true
	particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = card_size / 2.0
	particles.direction             = Vector2(0, 0)
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.gravity               = Vector2(0, 0)
	particles.scale_amount_min      = 3.0
	particles.scale_amount_max      = 8.0

	var sparkle_colour : Color = _get_holo_sparkle_colour(card_data)
	var bright         : Color = sparkle_colour.lightened(0.5)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient

	return particles


func _get_holo_sparkle_colour(card_data: Dictionary) -> Color:
	var supertype : String = card_data.get("supertype", "")
	if supertype == "Pokemon" or supertype == "Pokémon":
		var types : Array = card_data.get("types", [])
		if types.size() > 0:
			return _get_type_colour(types[0])
	return Color(0.85, 0.85, 0.9)


func _get_type_colour(type_name: String) -> Color:
	match type_name.to_lower():
		"fire":      return Color(1.0, 0.2, 0.1)
		"water":     return Color(0.2, 0.5, 1.0)
		"grass":     return Color(0.2, 0.8, 0.3)
		"lightning": return Color(1.0, 0.9, 0.1)
		"darkness":  return Color(0.15, 0.1, 0.2)
		"psychic":   return Color(0.55, 0.1, 1.0)
		"metal":     return Color(0.6, 0.6, 0.65)
		"fighting":  return Color(0.5, 0.3, 0.2)
		"dragon":    return Color(0.9, 0.7, 0.2)
		"fairy":     return Color(1.0, 0.4, 0.7)
		_:           return Color(1.0, 1.0, 1.0)


# ─── Flip animation (mirrored from Coin_Shop_Script.gd) ──────────────────────

func _play_flip_animation(rect: TextureRect, back_tex: Texture2D, target_tex: Texture2D) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	if back_tex == null or target_tex == null:
		return

	rect.texture      = back_tex
	rect.pivot_offset = rect.size / 2.0
	rect.scale        = Vector2(1.0, 1.0)

	var shrink_durations := [0.01, 0.02, 0.04, 0.06, 0.08, 0.1, 0.11, 0.12, 0.2]
	var swaps := [target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex]

	var tween := create_tween()
	for i in shrink_durations.size():
		var d : float = shrink_durations[i]
		tween.tween_property(rect, "scale:x", 0.0, d)
		tween.tween_callback(rect.set.bind("texture", swaps[i]))
		tween.tween_property(rect, "scale:x", 1.0, d)

	await tween.finished


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	if _in_purchase_seq:
		return
	SoundManagerScript.stop_bgm()
	SceneCache.change_scene(CELESTE_HARBOUR)


func _input(event: InputEvent) -> void:
	# ISSUE #116 FIX ACTIVE: Space / Enter / Escape press the reveal's OK button, the same as
	# every other dialog in the game. Keys are classified by UIInput, never by keycode, and the
	# event is consumed so it cannot ALSO fire ui_accept on whichever button holds focus.
	if _reveal_ok_btn != null and is_instance_valid(_reveal_ok_btn):
		if UIInput.is_advance(event):
			get_viewport().set_input_as_handled()
			_reveal_ok_btn.pressed.emit()
		return
	if _in_purchase_seq:
		return
	# ISSUE #116 sibling: was a raw KEY_ESCAPE test; routed through UIInput like the rest.
	if UIInput.is_cancel(event):
		_on_cancel_pressed()
