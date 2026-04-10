extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const PLAYER_DATA_PATH     := "res://Player_Data/Player_Current_Data.json"
const PLAYER_PROGRESS_PATH := "res://Player_Data/Player_Game_Progress.json"
const SET_DICT_PATH        := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
const PACK_PRICES_PATH     := "res://Card_Set_Data/pack_prices.json"
const PACK_IMAGES_FOLDER   := "res://Image_Assets/Packs/"
const CARD_SET_DATA_PATH   := "res://Card_Set_Data/"
const CARDBACK_PATH        := "res://Image_Assets/Card_Backs_And_Decks/cardback.png"
const CARD_MART_SCENE      := "res://Scenes/map_scenes/map_areas/Card_Mart.tscn"

# Card display size used for the pack opening reveal
const CARD_DISPLAY_SIZE    := Vector2(250, 350)

# ─── State ───────────────────────────────────────────────────────────────────

var set_list       : Array = []
var unlocked_packs : Array = []
var current_pack_idx : int = 0
var pack_prices    : Dictionary = {}
var player_cash    : float = 0.0

# ─── Selection state ─────────────────────────────────────────────────────────

var selected_pack_rect   : TextureRect = null
var selected_pack_letter : String = ""
var selected_pack_tween  : Tween = null
var purchased_pack_art   : String = ""

# ─── Pack opening state ──────────────────────────────────────────────────────

# Whether we are currently in the pack opening animation sequence
var _in_opening_sequence : bool = false
# The 10 generated cards in order: commons, uncommons, rare
var _pack_cards          : Array = []
# Which card index is currently displayed (0 = first common, 9 = rare)
var _current_card_index  : int = 0
# The TextureRect showing the current face card
var _face_card_rect      : TextureRect = null
# The cardback rect used during flip-in
var _cardback_rect       : TextureRect = null
# Whether we are waiting for click/space to advance
var _waiting_for_advance : bool = false
# Remaining pack body rect after the top is cut
var _pack_body_rect      : TextureRect = null
# The cut top section of the pack
var _pack_top_rect       : TextureRect = null

# ─── Theme references ────────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")

# ─── Node references ─────────────────────────────────────────────────────────

@onready var pack_hbox         : HBoxContainer = $pack_hbox
@onready var set_name_label    : Label         = $"SET NAVIGATION"/set_name_label
@onready var your_money_amount : Label         = $"MONEY LABELS"/your_money_amount
@onready var pack_cost_amount  : Label         = $"MONEY LABELS"/pack_cost_amount
@onready var buy_button        : Button        = $pack_purchase_button
@onready var cancel_button     : Button        = $buy_cancel_button
@onready var next_btn          : Button        = $"SET NAVIGATION"/next_set
@onready var prev_btn          : Button        = $"SET NAVIGATION"/previous_set


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm("res://Audio/BGM/coin_mode.ogg", true)
	
	_load_set_dictionary()
	_load_pack_prices()
	_load_player_data()
	
	var last_pack := _get_last_pack_loaded()
	_find_starting_pack(last_pack)
	
	buy_button.pressed.connect(_on_buy_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	next_btn.pressed.connect(_on_next_set)
	prev_btn.pressed.connect(_on_prev_set)
	
	_refresh_display()


# ─── Data loading ────────────────────────────────────────────────────────────

func _load_set_dictionary() -> void:
	var file := FileAccess.open(SET_DICT_PATH, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot open " + SET_DICT_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("set_list"):
		set_list = data["set_list"]


func _load_pack_prices() -> void:
	var file := FileAccess.open(PACK_PRICES_PATH, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot open " + PACK_PRICES_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Array:
		for entry in data:
			pack_prices[entry["pack"]] = int(entry["cost"])


func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot open " + PLAYER_PROGRESS_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	unlocked_packs = data.get("packs_unlocked", [])
	player_cash    = data.get("cash", 0.0)


func _get_last_pack_loaded() -> String:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return "base1"
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		return data.get("last_pack_loaded", "base1")
	return "base1"


func _find_starting_pack(pack_id: String) -> void:
	for i in range(unlocked_packs.size()):
		if unlocked_packs[i] == pack_id:
			current_pack_idx = i
			return
	current_pack_idx = 0


# ─── Display ─────────────────────────────────────────────────────────────────

func _refresh_display() -> void:
	if unlocked_packs.is_empty():
		return
	var pack_id : String = unlocked_packs[current_pack_idx]
	_clear_selection()
	set_name_label.text = _get_set_name(pack_id)
	_load_pack_images(pack_id)
	var cost : int = pack_prices.get(pack_id, 0)
	pack_cost_amount.text = str(cost)
	your_money_amount.text = str(int(player_cash))
	_update_buy_button()
	_save_last_pack_loaded(pack_id)


func _get_set_name(set_id: String) -> String:
	for entry in set_list:
		if entry["set_id"] == set_id:
			return entry["set_name"]
	return set_id.to_upper()


func _load_pack_images(pack_id: String) -> void:
	for child in pack_hbox.get_children():
		child.queue_free()
	var letters : Array[String] = ["a", "b", "c"]
	for letter in letters:
		var path : String = PACK_IMAGES_FOLDER + pack_id + "_" + letter + ".png"
		var tex : Texture2D = _load_texture(path)
		if tex == null:
			continue
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.gui_input.connect(_on_pack_clicked.bind(rect, letter))
		pack_hbox.add_child(rect)


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# ─── Pack selection ──────────────────────────────────────────────────────────

func _on_pack_clicked(event: InputEvent, rect: TextureRect, letter: String) -> void:
	if _in_opening_sequence:
		return
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if selected_pack_rect == rect:
		_clear_selection()
		_update_buy_button()
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return
	_clear_selection()
	selected_pack_rect = rect
	selected_pack_letter = letter
	_apply_selection_animation(rect)
	_update_buy_button()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _clear_selection() -> void:
	if selected_pack_rect != null and is_instance_valid(selected_pack_rect):
		_remove_selection_animation(selected_pack_rect)
	selected_pack_rect = null
	selected_pack_letter = ""
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null


func _apply_selection_animation(rect: TextureRect) -> void:
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null
	rect.pivot_offset = rect.size / 2.0
	rect.modulate = Color.WHITE
	var tw := create_tween()
	tw.set_loops()
	selected_pack_tween = tw
	tw.tween_property(rect, "modulate", Color.WHITE * 1.4, 0.5)
	tw.parallel().tween_property(rect, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(rect, "modulate", Color.WHITE * 1.0, 0.5)
	tw.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.5)


func _remove_selection_animation(rect: TextureRect) -> void:
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null
	rect.modulate = Color.WHITE
	rect.scale = Vector2(1.0, 1.0)


func _update_buy_button() -> void:
	var pack_id : String = unlocked_packs[current_pack_idx]
	var cost : int = pack_prices.get(pack_id, 0)
	if selected_pack_rect != null and player_cash >= cost:
		buy_button.disabled = false
		buy_button.theme = theme_kenney_green
	else:
		buy_button.disabled = true
		buy_button.theme = theme_kenney


# ─── Buy logic ───────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	var pack_id : String = unlocked_packs[current_pack_idx]
	var cost    : int    = pack_prices.get(pack_id, 0)
	if selected_pack_rect == null or player_cash < cost:
		return
	
	purchased_pack_art = pack_id + "_" + selected_pack_letter
	player_cash -= cost
	_save_player_cash()
	
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	
	_begin_opening_sequence(pack_id)


func _save_player_cash() -> void:
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot read " + PLAYER_PROGRESS_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	data["cash"] = player_cash
	var save_file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.WRITE)
	if save_file == null:
		push_error("PackPurchase: cannot write " + PLAYER_PROGRESS_PATH)
		return
	save_file.store_string(JSON.stringify(data, "\t"))
	save_file.close()


func _save_last_pack_loaded(pack_id: String) -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	data["last_pack_loaded"] = pack_id
	var save_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if save_file == null:
		return
	save_file.store_string(JSON.stringify(data, "\t"))
	save_file.close()


# ─── Set navigation ──────────────────────────────────────────────────────────

func _on_next_set() -> void:
	if _in_opening_sequence or unlocked_packs.is_empty():
		return
	current_pack_idx = (current_pack_idx + 1) % unlocked_packs.size()
	_refresh_display()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _on_prev_set() -> void:
	if _in_opening_sequence or unlocked_packs.is_empty():
		return
	current_pack_idx -= 1
	if current_pack_idx < 0:
		current_pack_idx = unlocked_packs.size() - 1
	_refresh_display()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	if _in_opening_sequence:
		return
	SoundManagerScript.stop_bgm()
	get_tree().change_scene_to_file(CARD_MART_SCENE)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _in_opening_sequence:
			_on_cancel_pressed()
		return
	
	# Advance card reveal on click or space
	if _waiting_for_advance and _in_opening_sequence:
		var is_space : bool = event is InputEventKey and event.pressed and event.keycode == KEY_SPACE
		var is_click : bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if is_space or is_click:
			_waiting_for_advance = false
			get_viewport().set_input_as_handled()
			_advance_card_reveal()


# ═══════════════════════════════════════════════════════════════════════════════
# PACK OPENING SEQUENCE
# ═══════════════════════════════════════════════════════════════════════════════

## Collect all UI nodes that should be hidden/shown during the opening sequence.
func _get_ui_nodes_to_toggle() -> Array:
	var nodes : Array = []
	# Add all pack rects except the selected one
	for child in pack_hbox.get_children():
		if child != selected_pack_rect:
			nodes.append(child)
	# Add the hbox itself? No — we keep the hbox but hide its children.
	# Add labels and buttons
	nodes.append(set_name_label)
	nodes.append(your_money_amount)
	nodes.append(pack_cost_amount)
	nodes.append(buy_button)
	nodes.append(cancel_button)
	nodes.append(next_btn)
	nodes.append(prev_btn)
	# Also hide the parent containers of labels if they exist
	var money_labels = get_node_or_null("MONEY LABELS")
	var set_nav      = get_node_or_null("SET NAVIGATION")
	if money_labels != null:
		nodes.append(money_labels)
	if set_nav != null:
		nodes.append(set_nav)
	return nodes


## Entry point called after the buy button is pressed.
func _begin_opening_sequence(pack_id: String) -> void:
	_in_opening_sequence = true
	_waiting_for_advance = false
	
	# Stop selection animation on the chosen pack
	_remove_selection_animation(selected_pack_rect)
	
	# ── Step 1: Fade out everything except background and chosen pack ──
	var ui_nodes := _get_ui_nodes_to_toggle()
	
	# Block all input during fade by disabling buttons explicitly
	buy_button.disabled    = true
	cancel_button.disabled = true
	next_btn.disabled      = true
	prev_btn.disabled      = true
	# Block pack clicks — already guarded by _in_opening_sequence
	
	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			fade_tw.tween_property(node, "modulate:a", 0.0, 1.5)
	await fade_tw.finished
	
	# Make them fully invisible now (so they don't block input)
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			node.visible = false
			node.modulate.a = 1.0  # reset alpha for later fade-in
	
	# ── Step 2: Move selected pack to centre (where pack_b would be) ──
	# Find centre of pack_hbox in global space — approximate to screen centre X
	var viewport_size : Vector2 = get_viewport_rect().size
	var target_global_x : float = viewport_size.x / 2.0
	var target_global_y : float = viewport_size.y / 2.0
	
	# Convert the selected rect to a standalone node in the scene root
	# so we can freely position it without being constrained by the HBox.
	# We'll reparent it to a CanvasLayer overlay for the animation.
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	
	# Snapshot the pack's current global position/size before reparenting
	var pack_global_pos  : Vector2 = selected_pack_rect.get_global_rect().position
	var pack_size        : Vector2 = selected_pack_rect.get_global_rect().size
	var pack_tex         : Texture2D = selected_pack_rect.texture
	
	# Create a fresh TextureRect on the overlay for the animation
	var anim_pack := TextureRect.new()
	anim_pack.texture      = pack_tex
	anim_pack.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	anim_pack.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	anim_pack.size         = pack_size
	anim_pack.position     = pack_global_pos
	anim_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(anim_pack)
	
	# Hide the original pack in the hbox
	selected_pack_rect.visible = false
	
	# Target centre position (top-left of the rect at screen centre)
	var target_pos := Vector2(target_global_x - pack_size.x / 2.0, target_global_y - pack_size.y / 2.0)
	
	var move_tw := create_tween()
	move_tw.tween_property(anim_pack, "position", target_pos, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await move_tw.finished
	
	# ── Step 3: Split the pack — top 100px cut and fly off ──
	var top_height   : float = 100.0
	var body_height  : float = pack_size.y - top_height
	
	# We split using two TextureRects with region_enabled and AtlasTexture.
	# AtlasTexture lets us crop the source texture to a region.
	
	# We need the actual texture dimensions to compute UV regions correctly.
	# The anim_pack is displaying at pack_size but the texture may differ.
	var tex_w : float = float(pack_tex.get_width())
	var tex_h : float = float(pack_tex.get_height())
	
	# Proportion of height that the top 100px of the displayed image represents
	var top_ratio   : float = top_height / pack_size.y
	var top_tex_h   : float = tex_h * top_ratio
	var body_tex_h  : float = tex_h - top_tex_h
	
	# Top section atlas
	var top_atlas := AtlasTexture.new()
	top_atlas.atlas  = pack_tex
	top_atlas.region = Rect2(0, 0, tex_w, top_tex_h)
	
	# Body section atlas
	var body_atlas := AtlasTexture.new()
	body_atlas.atlas  = pack_tex
	body_atlas.region = Rect2(0, top_tex_h, tex_w, body_tex_h)
	
	# Remove the combined anim_pack
	anim_pack.queue_free()
	
	# Top rect — positioned at the top of where the pack was
	_pack_top_rect = TextureRect.new()
	_pack_top_rect.texture      = top_atlas
	_pack_top_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_pack_top_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_pack_top_rect.size         = Vector2(pack_size.x, top_height)
	_pack_top_rect.position     = target_pos
	_pack_top_rect.pivot_offset = Vector2(pack_size.x / 2.0, top_height / 2.0)
	_pack_top_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_pack_top_rect)
	
	# Body rect — positioned immediately below the top section
	_pack_body_rect = TextureRect.new()
	_pack_body_rect.texture      = body_atlas
	_pack_body_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_pack_body_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_pack_body_rect.size         = Vector2(pack_size.x, body_height)
	_pack_body_rect.position     = target_pos + Vector2(0, top_height)
	_pack_body_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_pack_body_rect)
	
	# Separate: top goes up 20px, body goes down 20px
	var split_tw := create_tween()
	split_tw.set_parallel(true)
	split_tw.tween_property(_pack_top_rect,  "position:y", target_pos.y - 20.0, 0.5).set_ease(Tween.EASE_OUT)
	split_tw.tween_property(_pack_body_rect, "position:y", target_pos.y + top_height + 20.0, 0.5).set_ease(Tween.EASE_OUT)
	await split_tw.finished
	
	# Rotate top 10 degrees and fly it off screen upward
	var fly_tw := create_tween()
	fly_tw.set_parallel(true)
	fly_tw.tween_property(_pack_top_rect, "rotation_degrees", 10.0, 0.5)
	fly_tw.tween_property(_pack_top_rect, "position:y", -200.0, 0.5).set_ease(Tween.EASE_IN)
	await fly_tw.finished
	_pack_top_rect.queue_free()
	_pack_top_rect = null
	
	# ── Step 4: Spawn cardback behind the pack body ──
	var cardback_tex : Texture2D = _load_texture(CARDBACK_PATH)
	_cardback_rect = TextureRect.new()
	_cardback_rect.texture      = cardback_tex
	_cardback_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_cardback_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_cardback_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Size the cardback the same as the displayed pack body
	_cardback_rect.size     = Vector2(pack_size.x, body_height)
	_cardback_rect.position = _pack_body_rect.position
	_cardback_rect.pivot_offset = Vector2(pack_size.x / 2.0, body_height / 2.0)
	
	# Add behind the body (lower z-index)
	overlay.add_child(_cardback_rect)
	overlay.move_child(_cardback_rect, 0)  # move to back of overlay
	
	# ── Step 5: Slide pack body off screen downwards, revealing cardback ──
	var slide_tw := create_tween()
	slide_tw.tween_property(_pack_body_rect, "position:y", viewport_size.y + 50.0, 0.5).set_ease(Tween.EASE_IN)
	await slide_tw.finished
	_pack_body_rect.queue_free()
	_pack_body_rect = null
	
	# ── Steps 6–8: Generate the 10 pack cards ──
	var pack_id_for_set : String = purchased_pack_art.rsplit("_", true, 1)[0]  # e.g. "base2" from "base2_b"
	_pack_cards = _generate_pack_cards(pack_id_for_set)
	_save_cards_to_player(pack_id_for_set, _pack_cards)
	_current_card_index = 0
	
	# Reposition cardback to screen centre now that the pack body is gone
	var card_display_w : float = CARD_DISPLAY_SIZE.x
	var card_display_h : float = CARD_DISPLAY_SIZE.y
	_cardback_rect.size         = CARD_DISPLAY_SIZE
	_cardback_rect.position     = Vector2(target_global_x - card_display_w / 2.0, target_global_y - card_display_h / 2.0)
	_cardback_rect.pivot_offset = CARD_DISPLAY_SIZE / 2.0
	
	# ── Step 9: Flip cardback out (scale:x → 0) then flip first common in ──
	await _flip_out_and_reveal_card(_cardback_rect, overlay, target_global_x, target_global_y)


## Flips the given rect out (squish x to 0) then flips in the current card.
func _flip_out_and_reveal_card(back_rect: TextureRect, overlay: CanvasLayer, cx: float, cy: float) -> void:
	var card_display_w : float = CARD_DISPLAY_SIZE.x
	var card_display_h : float = CARD_DISPLAY_SIZE.y
	
	# ── Step 9: Cardback flips out ──
	var flip_out_tw := create_tween()
	flip_out_tw.tween_property(back_rect, "scale:x", 0.0, 0.25).set_ease(Tween.EASE_IN)
	await flip_out_tw.finished
	back_rect.queue_free()
	_cardback_rect = null
	
	# ── Step 10: Flip the current face card in ──
	var card_data : Dictionary = _pack_cards[_current_card_index]
	var card_id   : String     = card_data.get("id", "")
	
	var card_tex : Texture2D = _load_card_texture(card_id, CARD_DISPLAY_SIZE)
	
	_face_card_rect = TextureRect.new()
	_face_card_rect.texture      = card_tex
	_face_card_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_face_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_face_card_rect.size         = CARD_DISPLAY_SIZE
	_face_card_rect.position     = Vector2(cx - card_display_w / 2.0, cy - card_display_h / 2.0)
	_face_card_rect.pivot_offset = CARD_DISPLAY_SIZE / 2.0
	_face_card_rect.scale        = Vector2(0.0, 1.0)  # start squished
	_face_card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_face_card_rect)
	
	var flip_in_tw := create_tween()
	flip_in_tw.tween_property(_face_card_rect, "scale:x", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	await flip_in_tw.finished
	
	# ── Now wait for player input ──
	_waiting_for_advance = true


## Called by _input when the player clicks/spaces to advance.
func _advance_card_reveal() -> void:
	if _face_card_rect == null or not is_instance_valid(_face_card_rect):
		return
	
	var overlay : CanvasLayer = _face_card_rect.get_parent()
	var viewport_size : Vector2 = get_viewport_rect().size
	
	# Fly current card off screen upwards
	var fly_tw := create_tween()
	fly_tw.tween_property(_face_card_rect, "position:y", -viewport_size.y, 0.5).set_ease(Tween.EASE_IN)
	await fly_tw.finished
	_face_card_rect.queue_free()
	_face_card_rect = null
	
	_current_card_index += 1
	
	# ── Step 12: Last card has been dismissed ──
	if _current_card_index >= _pack_cards.size():
		_finish_opening_sequence(overlay)
		return
	
	# ── Steps 9–10 repeat: flip next card in ──
	var cx : float = viewport_size.x / 2.0
	var cy : float = viewport_size.y / 2.0
	
	var card_data : Dictionary = _pack_cards[_current_card_index]
	var card_id   : String     = card_data.get("id", "")
	var card_tex  : Texture2D  = _load_card_texture(card_id, CARD_DISPLAY_SIZE)
	
	var card_display_w : float = CARD_DISPLAY_SIZE.x
	var card_display_h : float = CARD_DISPLAY_SIZE.y
	
	_face_card_rect = TextureRect.new()
	_face_card_rect.texture      = card_tex
	_face_card_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_face_card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_face_card_rect.size         = CARD_DISPLAY_SIZE
	_face_card_rect.position     = Vector2(cx - card_display_w / 2.0, cy - card_display_h / 2.0)
	_face_card_rect.pivot_offset = CARD_DISPLAY_SIZE / 2.0
	_face_card_rect.scale        = Vector2(0.0, 1.0)
	_face_card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_face_card_rect)
	
	var flip_in_tw := create_tween()
	flip_in_tw.tween_property(_face_card_rect, "scale:x", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	await flip_in_tw.finished
	
	_waiting_for_advance = true


## Called when all cards have been revealed.
func _finish_opening_sequence(overlay: CanvasLayer) -> void:
	_in_opening_sequence = false
	_waiting_for_advance = false
	
	# Remove the overlay
	overlay.queue_free()
	
	# Restore original selected pack visibility and reset selection
	if selected_pack_rect != null and is_instance_valid(selected_pack_rect):
		selected_pack_rect.visible = true
	_clear_selection()
	
	# ── Step 12/13: Fade UI elements back in ──
	var ui_nodes := _get_ui_nodes_to_toggle()
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			node.visible   = true
			node.modulate.a = 0.0
	
	var fade_in_tw := create_tween()
	fade_in_tw.set_parallel(true)
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			fade_in_tw.tween_property(node, "modulate:a", 1.0, 0.5)
	await fade_in_tw.finished
	
	# Re-enable buttons
	cancel_button.disabled = false
	next_btn.disabled      = false
	prev_btn.disabled      = false
	
	# Update money label and buy button (buy stays disabled until a pack is selected again)
	your_money_amount.text = str(int(player_cash))
	_update_buy_button()


# ═══════════════════════════════════════════════════════════════════════════════
# CARD GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

## Loads the set JSON and generates 10 cards: 6 commons, 3 uncommons, 1 rare slot.
## 25% chance: one common is replaced by a second rare (can be Rare or Rare Holo).
## The guaranteed rare slot and the bonus slot both draw from the combined rare+holo pool.
## Only "Rare" and "Rare Holo" are included — no EX, Star, Secret, Shining etc.
## Returns an Array in order: commons → uncommons → rares.
func _generate_pack_cards(set_id: String) -> Array:
	var json_path := CARD_SET_DATA_PATH + set_id + ".json"
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot open card set: " + json_path)
		return []
	var all_cards = JSON.parse_string(file.get_as_text())
	file.close()
	if not all_cards is Array:
		push_error("PackPurchase: unexpected card set format in " + json_path)
		return []
	
	# Partition by rarity, filtering out Basic Energy.
	# Rare pool = exactly "Rare" + exactly "Rare Holo" only.
	var commons   : Array = []
	var uncommons : Array = []
	var rare_pool : Array = []  # "Rare" and "Rare Holo" combined
	
	for card in all_cards:
		if _is_basic_energy(card):
			continue
		var rarity : String = card.get("rarity", "")
		match rarity:
			"Common":
				commons.append(card)
			"Uncommon":
				uncommons.append(card)
			"Rare":
				rare_pool.append(card)
			"Rare Holo":
				rare_pool.append(card)
	
	var bonus_rare : bool = randf() < 0.25 and rare_pool.size() > 0
	
	var result : Array = []
	
	# Commons
	for _i in range(6):
		var pick := _pick_random(commons)
		if not pick.is_empty():
			result.append(pick)
	
	# Uncommons
	for _i in range(3):
		var pick := _pick_random(uncommons)
		if not pick.is_empty():
			result.append(pick)
	
	# Guaranteed rare (Rare or Rare Holo, equal weight by card count in set)
	if rare_pool.size() > 0:
		result.append(rare_pool[randi() % rare_pool.size()])
	
	# Bonus rare slot — draw from the full rare pool (Rare or Rare Holo).
	if bonus_rare:
		result.append(rare_pool[randi() % rare_pool.size()])
	
	return result


## Picks a random card from pool. Pool is already filtered (no Basic Energy).
func _pick_random(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


## Returns true if the card is a Basic Energy (supertype Energy + subtype Basic).
func _is_basic_energy(card: Dictionary) -> bool:
	var supertype : String = card.get("supertype", "")
	if supertype != "Energy":
		return false
	var subtypes = card.get("subtypes", [])
	for st in subtypes:
		if st == "Basic":
			return true
	return false


## Loads a card texture using the same path logic as Card_Image_Loader_Script.
## Uses large images since CARD_DISPLAY_SIZE is >= 250x350.
func _load_card_texture(card_id: String, target_size: Vector2) -> Texture2D:
	var parts := card_id.split("-")
	if parts.size() < 2:
		return _load_texture("res://Image_Assets/null.png")
	
	var card_set : String = parts[0]
	var path : String
	if target_size.x < 250 or target_size.y < 350:
		path = "res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card_id + ".png"
	else:
		path = "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
	
	var tex := _load_texture(path)
	if tex == null:
		tex = _load_texture("res://Image_Assets/null.png")
	return tex


# ═══════════════════════════════════════════════════════════════════════════════
# SAVE CARDS TO PLAYER
# ═══════════════════════════════════════════════════════════════════════════════

## Saves all generated pack cards to the player's owned cards JSON for the set.
## Uses the same logic as MapManager._give_card().
func _save_cards_to_player(set_id: String, cards: Array) -> void:
	if cards.is_empty():
		return
	
	var json_path := "res://Player_Data/Player_Owned_Cards/" + set_id + "_player_owned_cards.json"
	
	var file := FileAccess.open(json_path, FileAccess.READ)
	var data : Dictionary = {"owned_cards": []}
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			data = parsed
	
	for card in cards:
		var card_id : String = card.get("id", "")
		if card_id == "":
			continue
		var found := false
		for entry in data["owned_cards"]:
			if entry["card_id"] == card_id:
				entry["owned"] = entry["owned"] + 1
				found = true
				break
		if not found:
			data["owned_cards"].append({"card_id": card_id, "owned": 1})
	
	var write_file := FileAccess.open(json_path, FileAccess.WRITE)
	if write_file == null:
		push_error("PackPurchase: cannot write " + json_path)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()
