extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
const SET_DICT_PATH        := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
const PACK_PRICES_PATH     := "res://Card_Set_Data/pack_prices.json"
const PACK_IMAGES_FOLDER   := "res://Image_Assets/Packs/"
const CARD_MART_SCENE      := "res://Scenes/Map_Scenes/Card_Mart.tscn"
const ROCKET_MART_SCENE    := "res://Scenes/Map_Scenes/Rocket_Mart.tscn"
const GYM_RECEPTION_SCENE  := "res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn"

# ─── Weighted mode ───────────────────────────────────────────────────────────
# The Gym Plaza Weighed Pack Seller runs this same screen with GameState.current_shop_id set to
# WEIGHTED_SHOP_ID. His packs are the ones carrying a "weighted_cost" in pack_prices.json: same
# 10 cards for roughly a third less, but the rare slot is a fourth uncommon (see
# PackOpeningManager._generate_pack_cards). Everything else about the screen is unchanged.

const WEIGHTED_SHOP_ID     := "weighted_mart"
const HEADER_NORMAL        := "Select pack to purchase"
const HEADER_WEIGHTED      := "Select WEIGHTED pack to purchase"

## THE DISCOUNT DISPLAY LIVES ON THE PACKS NOW. It used to be a centred row above them —
## the full price struck through in red at font 42, the payable price beside it, plus a
## DISCOUNT_ROW_SHIFT that slid the whole "pack cost:" pair left to make room. All of that
## is gone with the rest of the money labels. Each pack carries its own pill instead: gold
## with the price actually charged, and a smaller grey pill stacked above it holding the
## struck-out original. See ShopChrome.add_price_pill's `old_price`.

# ─── State ───────────────────────────────────────────────────────────────────

var set_list       : Array = []
var unlocked_packs : Array = []
var current_pack_idx : int = 0
var pack_prices    : Dictionary = {}
var player_cash    : float = 0.0

# ─── Weighted-mode state ─────────────────────────────────────────────────────

var is_weighted_shop  : bool       = false
var weighted_prices   : Dictionary = {}   # pack id -> discounted cost
var weighted_flags    : Dictionary = {}   # pack id -> story flag that must be raised to stock it

# ─── Selection state ─────────────────────────────────────────────────────────

var selected_pack_rect   : TextureRect = null
var selected_pack_letter : String = ""
var selected_pack_tween  : Tween = null
var purchased_pack_art   : String = ""

# ─── Opening sequence flag ───────────────────────────────────────────────────

var _in_opening_sequence : bool = false

# ─── Theme references ────────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")

# ─── Node references ─────────────────────────────────────────────────────────

@onready var pack_hbox         : HBoxContainer = $pack_hbox
@onready var set_name_label    : Label         = $"SET NAVIGATION"/set_name_label
@onready var buy_button        : Button        = $pack_purchase_button
@onready var cancel_button     : Button        = $buy_cancel_button
@onready var next_btn          : Button        = $"SET NAVIGATION"/next_set
@onready var prev_btn          : Button        = $"SET NAVIGATION"/previous_set
@onready var header_label      : Label         = $large_header_text_label

## The top-right cash pill, built at runtime by ShopChrome. Replaces the "Cash:" pair that
## used to sit up here as two loose Labels, and the "pack cost:" row that sat above the
## packs — the price is on each pack now. There is no OWNED state in this shop: packs are
## bought over and over.
var wallet_chip : Control = null

## The flat layer every price pill is drawn on. Pills are NOT children of the pack rects: the
## selection tween scales the chosen pack, and a nested pill would ride along instead of the
## pack growing and shrinking behind a price that stays put.
var pill_layer  : Control = null


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_SHOP_2, true)

	is_weighted_shop = GameState.current_shop_id == WEIGHTED_SHOP_ID
	header_label.text = HEADER_WEIGHTED if is_weighted_shop else HEADER_NORMAL

	_load_set_dictionary()
	_load_pack_prices()
	_load_player_data()

	wallet_chip = ShopChrome.add_wallet_chip(self, int(player_cash))
	pill_layer  = ShopChrome.add_pill_layer(self)

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
			var pack_id : String = entry["pack"]
			pack_prices[pack_id] = int(entry["cost"])
			# A "weighted_cost" is what makes a pack part of the Weighed Pack Seller's stock;
			# "weighted_requires_flag" holds it back until that story flag is raised.
			if entry.has("weighted_cost"):
				weighted_prices[pack_id] = int(entry["weighted_cost"])
				var gate : String = entry.get("weighted_requires_flag", "")
				if gate != "":
					weighted_flags[pack_id] = gate


func _load_player_data() -> void:
	player_cash = float(GameState.get_cash())

	var shop_id := GameState.current_shop_id
	if shop_id == WEIGHTED_SHOP_ID:
		unlocked_packs = _weighted_stock()
	elif shop_id == "rocket_mart":
		unlocked_packs = ["base5"]
	elif shop_id == "gym_mart":
		unlocked_packs = ["gym1", "gym2"]
	elif GameState.get_date() <= 2:
		unlocked_packs = ["base1"]
	else:
		unlocked_packs = ["base1", "base2", "base3"]


## Every pack with a weighted price, in pack_prices.json order, minus any still behind an
## unraised story flag. The base-set packs are always stocked — the Gym ones only appear once
## the Gym Challenge is complete.
func _weighted_stock() -> Array:
	var stock : Array = []
	for pack_id in weighted_prices.keys():
		var gate : String = weighted_flags.get(pack_id, "")
		if gate != "" and not GameState.has_flag(gate):
			continue
		stock.append(pack_id)
	return stock


## Price the current shop actually charges for a pack.
func _cost_for(pack_id: String) -> int:
	if is_weighted_shop:
		return int(weighted_prices.get(pack_id, pack_prices.get(pack_id, 0)))
	return int(pack_prices.get(pack_id, 0))


## Key the browsed-to pack is remembered under. The weighted seller keeps his own so the two
## shops don't drag each other's selection around — their stock lists barely overlap.
func _last_pack_key() -> String:
	return "last_weighted_pack_loaded" if is_weighted_shop else "last_pack_loaded"


func _get_last_pack_loaded() -> String:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return "base1"
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		return data.get(_last_pack_key(), "base1")
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
	ShopChrome.set_wallet_cash(wallet_chip, int(player_cash), false)
	_refresh_pills()
	_update_buy_button()
	_update_nav_buttons()
	_save_last_pack_loaded(pack_id)


func _update_nav_buttons() -> void:
	var multi := unlocked_packs.size() > 1
	next_btn.visible = multi
	prev_btn.visible = multi


func _get_set_name(set_id: String) -> String:
	var id_lower := set_id.to_lower()
	for entry in set_list:
		if entry["set_id"].to_lower() == id_lower:
			return entry["set_name"]
	return set_id


func _load_pack_images(pack_id: String) -> void:
	for child in pack_hbox.get_children():
		pack_hbox.remove_child(child)
		child.queue_free()
	var letters : Array[String] = ["a", "b", "c", "d"]
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
	# TWEAKABLE — the four-pack row was 50..1682, an asymmetric 1632 wide that left 238px of
	# dead margin on the right. Widened and centred now the money labels no longer need the
	# room: 1800 wide takes each pack from ~385 to ~427, still under the 455px native art.
	if pack_hbox.get_child_count() >= 4:
		pack_hbox.add_theme_constant_override("separation", 30)
		pack_hbox.offset_left  = 60.0
		pack_hbox.offset_right = 1860.0
	else:
		pack_hbox.remove_theme_constant_override("separation")
		pack_hbox.offset_left  = 155.0
		pack_hbox.offset_right = 1787.0


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# ─── Price pills ─────────────────────────────────────────────────────────────

## A pill on every pack on screen. All four are the same set at the same price, so they show
## the same figure — that is the point: the price belongs to the thing you click, and each
## pill can go red on its own when the balance runs out.
##
## In the weighted shop the pill is GOLD and carries a second, smaller grey pill above it
## with the full price struck through in red. If the discounted price is still out of reach
## the main pill goes red instead of gold and the struck-out pill stays put — affordability
## outranks the sale colour.
##
## Deferred a frame because the HBox has not sized its children yet on the frame they are
## added, and a pill anchors to the art's drawn box, which is derived from that size. Every
## caller reaches this with selection cleared and scales back at 1 — the anchor is read from
## a pack's live global rect, so refreshing mid-pulse would bake the pulsed position in.
func _refresh_pills() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	ShopChrome.clear_pills(pill_layer)
	if unlocked_packs.is_empty():
		return

	var pack_id : String = unlocked_packs[current_pack_idx]
	var cost    : int    = _cost_for(pack_id)
	var full    : int    = int(pack_prices.get(pack_id, cost))
	# Only a genuine saving gets the struck-out pill; a weighted pack priced at its full cost
	# would otherwise show "$200" crossed out above "$200".
	var old_price : int = full if (is_weighted_shop and full > cost) else 0

	var affordable : bool = player_cash >= float(cost)
	var state : int
	if not affordable:
		state = ShopChrome.UNAFFORDABLE
	elif old_price > 0:
		state = ShopChrome.DISCOUNTED
	else:
		state = ShopChrome.AFFORDABLE

	for child in pack_hbox.get_children():
		if not (child is TextureRect) or not is_instance_valid(child):
			continue
		# The GLOBAL drawn box, not the control rect: the pack rects are
		# STRETCH_KEEP_ASPECT_CENTERED inside HBox cells taller than the art, so the two
		# differ by a letterbox margin and a pill on the control rect floats below the pack.
		# _get_drawn_texture_rect() already does this maths for the fly-to-centre animation.
		ShopChrome.add_price_pill(pill_layer, _get_drawn_texture_rect(child),
								  state, cost, old_price)


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
	rect.pivot_offset  = rect.size / 2.0
	rect.self_modulate = Color.WHITE
	var tw := create_tween()
	tw.set_loops()
	selected_pack_tween = tw
	# self_modulate, not modulate — the brightness pulse must not reach the price pill child.
	# scale stays on the rect itself, so the pill grows and shrinks with its pack.
	tw.tween_property(rect, "self_modulate", Color.WHITE * 1.4, 0.5)
	tw.parallel().tween_property(rect, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(rect, "self_modulate", Color.WHITE * 1.0, 0.5)
	tw.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.5)


func _remove_selection_animation(rect: TextureRect) -> void:
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null
	rect.self_modulate = Color.WHITE
	rect.scale = Vector2(1.0, 1.0)


func _update_buy_button() -> void:
	var pack_id : String = unlocked_packs[current_pack_idx]
	var cost : int = _cost_for(pack_id)
	if selected_pack_rect != null and player_cash >= cost:
		buy_button.disabled = false
		buy_button.theme = theme_kenney_green
	else:
		buy_button.disabled = true
		buy_button.theme = theme_kenney


# ─── Buy logic ───────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	var pack_id : String = unlocked_packs[current_pack_idx]
	var cost    : int    = _cost_for(pack_id)
	if selected_pack_rect == null or player_cash < cost:
		return

	purchased_pack_art = pack_id + "_" + selected_pack_letter
	player_cash -= cost
	GameState.add_cash(-cost)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	_begin_opening_sequence()



func _save_last_pack_loaded(pack_id: String) -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return
	data[_last_pack_key()] = pack_id
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
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _get_return_scene() -> String:
	# The weighted seller is a character, not a world-object shop, so he saves a menu-return
	# state on the way in and the player lands back beside him on the map he was standing on.
	if is_weighted_shop and GameState.has_menu_return_state:
		return GameState.menu_return_scene_path
	if GameState.current_shop_id == "rocket_mart":
		return ROCKET_MART_SCENE
	elif GameState.current_shop_id == "gym_mart":
		return GYM_RECEPTION_SCENE
	return CARD_MART_SCENE


func _on_cancel_pressed() -> void:
	if _in_opening_sequence:
		return
	SoundManagerScript.stop_bgm()
	SceneCache.change_scene(_get_return_scene())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _in_opening_sequence and not PackOpeningManager.is_active():
			_on_cancel_pressed()


# ═══════════════════════════════════════════════════════════════════════════════
# PACK OPENING SEQUENCE
# ═══════════════════════════════════════════════════════════════════════════════

## Nodes hidden during the opening animation (everything except the chosen pack).
func _get_ui_nodes_to_toggle() -> Array:
	var nodes : Array = []
	for child in pack_hbox.get_children():
		if child != selected_pack_rect:
			nodes.append(child)
	nodes.append(set_name_label)
	if wallet_chip != null and is_instance_valid(wallet_chip):
		nodes.append(wallet_chip)
	# One entry fades every pill at once — they are all children of this layer now.
	if pill_layer != null and is_instance_valid(pill_layer):
		nodes.append(pill_layer)
	nodes.append(buy_button)
	nodes.append(cancel_button)
	nodes.append(next_btn)
	nodes.append(prev_btn)
	var set_nav = get_node_or_null("SET NAVIGATION")
	if set_nav != null:
		nodes.append(set_nav)
	return nodes


## Global rect of the art a shop pack rect actually paints, not of its control rect. The pack rects
## are STRETCH_KEEP_ASPECT_CENTERED inside HBox cells that are taller than the art, so the two differ
## by a letterbox margin — animating from the control rect makes the pack jump.
func _get_drawn_texture_rect(rect: TextureRect) -> Rect2:
	var control_rect : Rect2 = rect.get_global_rect()
	if rect.texture == null:
		return control_rect
	var tex_size : Vector2 = rect.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return control_rect
	var fit   : float   = minf(control_rect.size.x / tex_size.x, control_rect.size.y / tex_size.y)
	var drawn : Vector2 = tex_size * fit
	return Rect2(control_rect.position + (control_rect.size - drawn) / 2.0, drawn)


## Fades out UI, animates the chosen pack to screen centre, then hands off
## to PackOpeningManager for the full rip/flip/summary sequence.
func _begin_opening_sequence() -> void:
	_in_opening_sequence = true

	_remove_selection_animation(selected_pack_rect)
	# Every pill goes now rather than fading with the row: the chosen pack flies to screen
	# centre and a pill left on the layer would just hang in the air where the pack was.
	# _on_pack_opening_finished() rebuilds them before the fade back in.
	ShopChrome.clear_pills(pill_layer)

	var ui_nodes := _get_ui_nodes_to_toggle()
	buy_button.disabled    = true
	cancel_button.disabled = true
	next_btn.disabled      = true
	prev_btn.disabled      = true

	# Fade out other UI elements. Scaled like the rest of the sequence, so "skip" collapses it to a
	# frame instead of leaving a half-second wait in front of an otherwise instant pack.
	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			fade_tw.tween_property(node, "modulate:a", 0.0, GameState.pack_time(0.2))
	await fade_tw.finished

	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			node.visible   = false
			node.modulate.a = 1.0

	# Move selected pack to screen centre via a temporary canvas layer.
	#
	# Two snaps used to bracket this move. On the way in, the shop rects draw their art
	# KEEP_ASPECT_CENTERED inside a taller HBox cell, but the flying copy was built at the *cell*
	# rect with KEEP_ASPECT (top-left aligned) — so the pack jumped up by the letterbox margin
	# before it started moving. On the way out, PackOpeningManager re-created the pack at its own
	# size, so it popped again at the handoff.
	#
	# Fix: start from the art's real on-screen rect, and tween position AND size straight into the
	# rect PackOpeningManager will open from. STRETCH_SCALE so the rect is what's drawn, exactly.
	var temp_overlay := CanvasLayer.new()
	temp_overlay.layer = 10
	add_child(temp_overlay)

	var source_rect : Rect2     = _get_drawn_texture_rect(selected_pack_rect)
	var target_rect : Rect2     = PackOpeningManager.get_pack_target_rect()
	var pack_tex    : Texture2D = selected_pack_rect.texture

	var anim_pack := TextureRect.new()
	anim_pack.texture      = pack_tex
	anim_pack.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	anim_pack.stretch_mode = TextureRect.STRETCH_SCALE
	anim_pack.size         = source_rect.size
	anim_pack.position     = source_rect.position
	anim_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	temp_overlay.add_child(anim_pack)

	selected_pack_rect.visible = false

	var move_time : float = GameState.pack_time(0.35)
	var move_tw := create_tween()
	move_tw.set_parallel(true)
	move_tw.tween_property(anim_pack, "position", target_rect.position, move_time) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	move_tw.tween_property(anim_pack, "size", target_rect.size, move_time) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await move_tw.finished

	# Hand off to PackOpeningManager — pack is now at centre, no intro fade needed
	temp_overlay.queue_free()
	PackOpeningManager.all_packs_opened.connect(_on_pack_opening_finished, CONNECT_ONE_SHOT)
	PackOpeningManager.open_packs([purchased_pack_art], 0.0, is_weighted_shop)


## Called by PackOpeningManager.all_packs_opened to restore the shop UI.
func _on_pack_opening_finished() -> void:
	_in_opening_sequence = false

	if selected_pack_rect != null and is_instance_valid(selected_pack_rect):
		selected_pack_rect.visible = true
	_clear_selection()

	# Rebuilt BEFORE the fade list is taken, so the pills fade back in with the packs they
	# belong to instead of popping in afterwards. Also re-colours the row red if the purchase
	# has taken the balance below the price.
	await _refresh_pills()

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

	cancel_button.disabled = false
	next_btn.disabled      = false
	prev_btn.disabled      = false
	_update_nav_buttons()
	ShopChrome.set_wallet_cash(wallet_chip, int(player_cash))
	_update_buy_button()
