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

# ─── Opening sequence flag ───────────────────────────────────────────────────

var _in_opening_sequence : bool = false

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
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop2.ogg", true)

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
	player_cash = float(GameState.get_cash())

	var shop_id := GameState.current_shop_id
	if shop_id == "rocket_mart":
		unlocked_packs = ["base5"]
	elif shop_id == "gym_mart":
		unlocked_packs = ["gym1", "gym2"]
	elif GameState.get_date() <= 2:
		unlocked_packs = ["base1"]
	else:
		unlocked_packs = ["base1", "base2", "base3"]


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
	var id_lower := set_id.to_lower()
	for entry in set_list:
		if entry["set_id"].to_lower() == id_lower:
			return entry["set_name"]
	return set_id


func _load_pack_images(pack_id: String) -> void:
	for child in pack_hbox.get_children():
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
	if pack_hbox.get_child_count() >= 4:
		pack_hbox.add_theme_constant_override("separation", 30)
		pack_hbox.offset_left  = 50.0
		pack_hbox.offset_right = 1682.0
	else:
		pack_hbox.remove_theme_constant_override("separation")
		pack_hbox.offset_left  = 155.0
		pack_hbox.offset_right = 1787.0


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
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _get_return_scene() -> String:
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
	nodes.append(your_money_amount)
	nodes.append(pack_cost_amount)
	nodes.append(buy_button)
	nodes.append(cancel_button)
	nodes.append(next_btn)
	nodes.append(prev_btn)
	var money_labels = get_node_or_null("MONEY LABELS")
	var set_nav      = get_node_or_null("SET NAVIGATION")
	if money_labels != null:
		nodes.append(money_labels)
	if set_nav != null:
		nodes.append(set_nav)
	return nodes


## Fades out UI, animates the chosen pack to screen centre, then hands off
## to PackOpeningManager for the full rip/flip/summary sequence.
func _begin_opening_sequence() -> void:
	_in_opening_sequence = true

	_remove_selection_animation(selected_pack_rect)

	var ui_nodes := _get_ui_nodes_to_toggle()
	buy_button.disabled    = true
	cancel_button.disabled = true
	next_btn.disabled      = true
	prev_btn.disabled      = true

	# Fade out other UI elements
	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			fade_tw.tween_property(node, "modulate:a", 0.0, 0.5)
	await fade_tw.finished

	for node in ui_nodes:
		if node != null and is_instance_valid(node):
			node.visible   = false
			node.modulate.a = 1.0

	# Move selected pack to screen centre via a temporary canvas layer
	var viewport_size   : Vector2   = get_viewport_rect().size
	var target_global_x : float     = viewport_size.x / 2.0
	var target_global_y : float     = viewport_size.y / 2.0

	var temp_overlay := CanvasLayer.new()
	temp_overlay.layer = 10
	add_child(temp_overlay)

	var pack_global_pos : Vector2   = selected_pack_rect.get_global_rect().position
	var pack_size       : Vector2   = selected_pack_rect.get_global_rect().size
	var pack_tex        : Texture2D = selected_pack_rect.texture

	var anim_pack := TextureRect.new()
	anim_pack.texture      = pack_tex
	anim_pack.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	anim_pack.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	anim_pack.size         = pack_size
	anim_pack.position     = pack_global_pos
	anim_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	temp_overlay.add_child(anim_pack)

	selected_pack_rect.visible = false

	var target_pos := Vector2(target_global_x - pack_size.x / 2.0, target_global_y - pack_size.y / 2.0)

	var move_tw := create_tween()
	move_tw.tween_property(anim_pack, "position", target_pos, 0.75).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await move_tw.finished

	# Hand off to PackOpeningManager — pack is now at centre, no intro fade needed
	temp_overlay.queue_free()
	PackOpeningManager.all_packs_opened.connect(_on_pack_opening_finished, CONNECT_ONE_SHOT)
	PackOpeningManager.open_packs([purchased_pack_art], 0.0)


## Called by PackOpeningManager.all_packs_opened to restore the shop UI.
func _on_pack_opening_finished() -> void:
	_in_opening_sequence = false

	if selected_pack_rect != null and is_instance_valid(selected_pack_rect):
		selected_pack_rect.visible = true
	_clear_selection()

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
	your_money_amount.text = str(int(player_cash))
	_update_buy_button()
