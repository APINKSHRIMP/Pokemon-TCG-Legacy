extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const PLAYER_DATA_PATH     := "res://Player_Data/Player_Current_Data.json"
const PLAYER_PROGRESS_PATH := "res://Player_Data/Player_Game_Progress.json"
const SET_DICT_PATH        := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
const PACK_PRICES_PATH     := "res://Card_Set_Data/pack_prices.json"
const PACK_IMAGES_FOLDER   := "res://Image_Assets/Packs/"
const CARD_MART_SCENE      := "res://Scenes/map_scenes/map_areas/Card_Mart.tscn"

# ─── State ───────────────────────────────────────────────────────────────────

# Full set dictionary: [{set_id, set_name}, ...]
var set_list       : Array = []
# The player's unlocked pack IDs in order: ["base1", "base2", "base3"]
var unlocked_packs : Array = []
# Current index into unlocked_packs
var current_pack_idx : int = 0
# Pack prices: { "base1": 100, "base2": 150, ... }
var pack_prices    : Dictionary = {}
# Player's current cash
var player_cash    : float = 0.0

# ─── Selection state ─────────────────────────────────────────────────────────

# The currently selected pack TextureRect (null = nothing selected)
var selected_pack_rect : TextureRect = null
# The letter key of the selected pack ("a", "b", or "c")
var selected_pack_letter : String = ""
# Active glow/grow tween for the selected pack
var selected_pack_tween : Tween = null
# The purchased pack art ID for the pack opening scene (e.g. "base2_b")
var purchased_pack_art : String = ""

# ─── Theme references ───────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")

# ─── Node references ────────────────────────────────────────────────────────

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
	
	# Load all data
	_load_set_dictionary()
	_load_pack_prices()
	_load_player_data()
	
	# Find starting pack
	var last_pack := _get_last_pack_loaded()
	_find_starting_pack(last_pack)
	
	# Wire signals
	buy_button.pressed.connect(_on_buy_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	next_btn.pressed.connect(_on_next_set)
	prev_btn.pressed.connect(_on_prev_set)
	
	# Display initial pack
	_refresh_display()


# ─── Data loading ────────────────────────────────────────────────────────────

## Reads the set dictionary JSON so we can map set_id → set_name.
func _load_set_dictionary() -> void:
	var file := FileAccess.open(SET_DICT_PATH, FileAccess.READ)
	if file == null:
		push_error("PackPurchase: cannot open " + SET_DICT_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("set_list"):
		set_list = data["set_list"]


## Reads pack_prices.json into a dictionary keyed by pack ID.
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


## Reads player progress to get unlocked packs and cash.
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
	player_cash = data.get("cash", 0.0)


## Returns the last_pack_loaded from current data.
func _get_last_pack_loaded() -> String:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return "base1"
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		return data.get("last_pack_loaded", "base1")
	return "base1"


## Sets current_pack_idx to match the given pack_id, or 0 if not found.
func _find_starting_pack(pack_id: String) -> void:
	for i in range(unlocked_packs.size()):
		if unlocked_packs[i] == pack_id:
			current_pack_idx = i
			return
	current_pack_idx = 0


# ─── Display ─────────────────────────────────────────────────────────────────

## Refreshes all UI elements for the currently selected pack.
func _refresh_display() -> void:
	if unlocked_packs.is_empty():
		return
	
	var pack_id : String = unlocked_packs[current_pack_idx]
	
	# Clear selection when refreshing (set change, initial load)
	_clear_selection()
	
	# Update set name label
	set_name_label.text = _get_set_name(pack_id)
	
	# Load pack images into hbox
	_load_pack_images(pack_id)
	
	# Update cost label
	var cost : int = pack_prices.get(pack_id, 0)
	pack_cost_amount.text = str(cost)
	
	# Update money label
	your_money_amount.text = str(int(player_cash))
	
	# Update buy button state (no pack selected yet so always disabled)
	_update_buy_button()
	
	# Save last_pack_loaded to current data
	_save_last_pack_loaded(pack_id)


## Returns the display name for a set_id by looking it up in set_list.
func _get_set_name(set_id: String) -> String:
	for entry in set_list:
		if entry["set_id"] == set_id:
			return entry["set_name"]
	# Fallback: return the ID itself capitalised
	return set_id.to_upper()


## Clears the pack_hbox and loads 3 pack images (a, b, c) for the set.
func _load_pack_images(pack_id: String) -> void:
	# Clear existing images
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


## Loads a texture from the given path, returns null if not found.
func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex : Texture2D = load(path)
	return tex


# ─── Pack selection ──────────────────────────────────────────────────────────

## Called when any pack image is clicked.
func _on_pack_clicked(event: InputEvent, rect: TextureRect, letter: String) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	
	# Clicking the already-selected pack deselects it
	if selected_pack_rect == rect:
		_clear_selection()
		_update_buy_button()
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return
	
	# Deselect previous pack if any
	_clear_selection()
	
	# Select the new pack
	selected_pack_rect = rect
	selected_pack_letter = letter
	_apply_selection_animation(rect)
	_update_buy_button()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


## Clears the current selection — stops animation and resets state.
func _clear_selection() -> void:
	if selected_pack_rect != null and is_instance_valid(selected_pack_rect):
		_remove_selection_animation(selected_pack_rect)
	selected_pack_rect = null
	selected_pack_letter = ""
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null


## Starts the glow + grow looping animation on a selected pack.
## Sets pivot_offset to centre so the scale originates from the middle.
func _apply_selection_animation(rect: TextureRect) -> void:
	# Kill any existing tween
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


## Stops animation and resets a pack rect to its normal state.
func _remove_selection_animation(rect: TextureRect) -> void:
	if selected_pack_tween != null:
		selected_pack_tween.kill()
		selected_pack_tween = null
	rect.modulate = Color.WHITE
	rect.scale = Vector2(1.0, 1.0)


## Enables/disables buy button based on selection AND affordability.
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
	
	# Store the purchased pack art ID (e.g. "base2_b") for the opening animation
	purchased_pack_art = pack_id + "_" + selected_pack_letter
	
	# Deduct cost
	player_cash -= cost
	
	# Save updated cash to player progress
	_save_player_cash()
	
	# Clear selection
	_clear_selection()
	
	# Refresh labels and button state
	your_money_amount.text = str(int(player_cash))
	_update_buy_button()
	
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	
	# TODO: Transition to pack opening animation using purchased_pack_art


## Writes updated cash back to Player_Game_Progress.json.
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


## Saves last_pack_loaded to Player_Current_Data.json.
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
	if unlocked_packs.is_empty():
		return
	current_pack_idx = (current_pack_idx + 1) % unlocked_packs.size()
	_refresh_display()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _on_prev_set() -> void:
	if unlocked_packs.is_empty():
		return
	current_pack_idx -= 1
	if current_pack_idx < 0:
		current_pack_idx = unlocked_packs.size() - 1
	_refresh_display()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	SoundManagerScript.stop_bgm()
	get_tree().change_scene_to_file(CARD_MART_SCENE)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
