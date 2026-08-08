extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const INVENTORY_PATH   := "res://NPC_and_Opponent_Data/coin_shop_inventory.json"
const COIN_FOLDER      := "res://Image_Assets/Coins"
const COINBACK_PATH    := "res://Image_Assets/Coins/Back Basic.png"
const CELESTE_HARBOUR  := "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const COIN_SIZE        := Vector2(200, 200)
const COIN_SEPARATION  := 100
const COLUMNS          := 5
const GIFT_COIN_SIZE   := Vector2(250, 250)
const GIFT_FLIP_TOTAL  := 1.5

# ISSUE #92: fallback price for an inventory entry with no "cost" field. TWEAKABLE, but the real
# prices live in coin_shop_inventory.json — keep this in step with them so a malformed entry can't
# quietly sell a coin at an out-of-date price.
const DEFAULT_COIN_COST := 500

# ─── State ───────────────────────────────────────────────────────────────────

var inventory        : Array = []
var player_cash      : int   = 0
var _owned_coins     : Dictionary = {}

var selected_coin_rect : TextureRect = null
var _active_tween      : Tween       = null
var _active_particles  : CPUParticles2D = null
var _in_purchase_seq   : bool        = false

# ─── Theme references ─────────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid             : GridContainer = $coin_grid_container
@onready var buy_btn          : Button        = $coin_buy_button
@onready var cancel_btn       : Button        = $buy_cancel_button
@onready var your_money_amount: Label         = $"MONEY LABELS"/your_money_amount
@onready var coin_cost_amount : Label         = $"MONEY LABELS"/coin_cost_amount

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop2.ogg", true)

	_load_inventory()
	_load_player_data()

	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", COIN_SEPARATION)
	grid.add_theme_constant_override("v_separation", COIN_SEPARATION)

	your_money_amount.text = str(player_cash)
	if inventory.size() > 0:
		coin_cost_amount.text = str(int(inventory[0].get("cost", DEFAULT_COIN_COST)))

	buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	await get_tree().process_frame
	_build_coin_grid()


func _process(_delta: float) -> void:
	if _active_particles and selected_coin_rect:
		_active_particles.global_position = selected_coin_rect.global_position + selected_coin_rect.size / 2.0


# ─── Data loading ─────────────────────────────────────────────────────────────

func _load_inventory() -> void:
	var file := FileAccess.open(INVENTORY_PATH, FileAccess.READ)
	if file == null:
		push_error("CoinShop: cannot open " + INVENTORY_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("coins"):
		inventory = data["coins"]


func _load_player_data() -> void:
	player_cash = GameState.get_cash()
	for coin_filename in GameState.get_coins():
		_owned_coins[coin_filename] = true


# ─── Grid building ────────────────────────────────────────────────────────────

func _build_coin_grid() -> void:
	for entry in inventory:
		var filename : String = entry.get("filename", "")
		var cost     : int    = entry.get("cost", DEFAULT_COIN_COST)
		if filename == "":
			continue

		var is_owned : bool = _owned_coins.has(filename)
		var tex_path : String = COIN_FOLDER + "/" + filename
		var tex : Texture2D = load(tex_path) as Texture2D
		if tex == null:
			push_warning("CoinShop: texture not found: " + tex_path)
			continue

		var rect := TextureRect.new()
		rect.texture             = tex
		rect.custom_minimum_size = COIN_SIZE
		rect.size                = COIN_SIZE
		rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		rect.set_meta("coin_filename", filename)
		rect.set_meta("coin_cost",     cost)
		rect.set_meta("is_owned",      is_owned)

		if is_owned:
			# self_modulate dims only the texture; children (the label) are unaffected
			rect.self_modulate = Color(0.2, 0.2, 0.2)
			rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE

			var owned_label := Label.new()
			owned_label.text                 = "OWNED"
			owned_label.position             = Vector2.ZERO
			owned_label.size                 = COIN_SIZE
			owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			owned_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			owned_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
			owned_label.theme                = theme_kenney
			owned_label.add_theme_color_override("font_color", Color.WHITE)
			owned_label.add_theme_font_size_override("font_size", 28)
			rect.add_child(owned_label)
		else:
			rect.modulate = Color(0.8, 0.8, 0.8)
			rect.gui_input.connect(_on_coin_clicked.bind(rect))

		grid.add_child(rect)


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_coin_clicked(event: InputEvent, rect: TextureRect) -> void:
	if _in_purchase_seq:
		return
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return

	if selected_coin_rect and selected_coin_rect != rect:
		_deselect_coin(selected_coin_rect)

	if selected_coin_rect == rect:
		_deselect_coin(rect)
		selected_coin_rect = null
		_update_buy_button()
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return

	_select_coin(rect)
	_update_buy_button()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _select_coin(rect: TextureRect) -> void:
	selected_coin_rect = rect
	_apply_selected_animation(rect)
	_start_sparkle(rect)


func _deselect_coin(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_particles:
		_active_particles.queue_free()
		_active_particles = null
	if is_instance_valid(rect) and not rect.get_meta("is_owned", false):
		rect.modulate     = Color(0.8, 0.8, 0.8)
		rect.scale        = Vector2(1.0, 1.0)
		rect.pivot_offset = rect.size / 2.0


func _apply_selected_animation(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
	rect.pivot_offset = rect.size / 2.0
	rect.modulate = Color.WHITE
	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	tween.tween_property(rect, "modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.02, 1.02), 0.2)
	tween.tween_property(rect, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Buy button ──────────────────────────────────────────────────────────────

func _update_buy_button() -> void:
	var can_buy := false
	if selected_coin_rect != null and is_instance_valid(selected_coin_rect):
		var is_owned : bool = selected_coin_rect.get_meta("is_owned", true)
		var cost     : int  = selected_coin_rect.get_meta("coin_cost", DEFAULT_COIN_COST)
		can_buy = not is_owned and player_cash >= cost
	buy_btn.disabled = not can_buy
	buy_btn.theme    = theme_kenney_green if can_buy else theme_kenney


# ─── Purchase ────────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	if selected_coin_rect == null or not is_instance_valid(selected_coin_rect):
		return
	var filename : String = selected_coin_rect.get_meta("coin_filename", "")
	var cost     : int    = selected_coin_rect.get_meta("coin_cost", DEFAULT_COIN_COST)
	if filename == "" or player_cash < cost:
		return

	player_cash -= cost
	GameState.add_cash(-cost)
	GameState.add_coin_to_collection(filename)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	_show_purchase_display(filename)


func _show_purchase_display(coin_filename: String) -> void:
	_in_purchase_seq = true
	buy_btn.disabled  = true
	cancel_btn.disabled = true

	var coin_tex  : Texture2D = load(COIN_FOLDER + "/" + coin_filename) as Texture2D
	var back_tex  : Texture2D = preload(COINBACK_PATH) as Texture2D

	# Full-screen overlay layer above everything
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)

	# Dim background
	var dim := ColorRect.new()
	dim.color         = Color(0, 0, 0, 0.8)
	dim.anchor_right  = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(dim)

	# Coin image centred on screen
	var vp_size  : Vector2 = get_viewport_rect().size
	var coin_pos : Vector2 = Vector2(
		vp_size.x / 2.0 - GIFT_COIN_SIZE.x / 2.0,
		vp_size.y / 2.0 - GIFT_COIN_SIZE.y / 2.0 - 60.0
	)

	var coin_rect := TextureRect.new()
	coin_rect.texture             = coin_tex
	coin_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	coin_rect.custom_minimum_size = GIFT_COIN_SIZE
	coin_rect.size                = GIFT_COIN_SIZE
	coin_rect.position            = coin_pos
	coin_rect.pivot_offset        = GIFT_COIN_SIZE / 2.0
	coin_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(coin_rect)

	# Text label below coin
	var label := Label.new()
	label.text                = "You received the " + _format_coin_name(coin_filename)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position            = Vector2(160.0, coin_pos.y + GIFT_COIN_SIZE.y + 20.0)
	label.size                = Vector2(1600.0, 80.0)
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", Color.WHITE)
	overlay_layer.add_child(label)

	# OK button — hidden until animation finishes
	var ok_btn := Button.new()
	ok_btn.text     = "OK"
	ok_btn.size     = Vector2(400.0, 60.0)
	ok_btn.position = Vector2(vp_size.x / 2.0 - 200.0, label.position.y + 90.0)
	ok_btn.visible  = false
	ok_btn.theme    = theme_kenney_green
	overlay_layer.add_child(ok_btn)

	# Play flip animation, then reveal OK
	await _play_flip_animation(coin_rect, back_tex, coin_tex)
	ok_btn.visible = true

	# Wait for player to dismiss
	await ok_btn.pressed
	overlay_layer.queue_free()

	# Mark the purchased coin as owned in the grid
	var purchased_rect := selected_coin_rect
	if purchased_rect != null and is_instance_valid(purchased_rect):
		if _active_tween:
			_active_tween.kill()
			_active_tween = null
		if _active_particles:
			_active_particles.queue_free()
			_active_particles = null
		purchased_rect.set_meta("is_owned", true)
		purchased_rect.self_modulate = Color(0.2, 0.2, 0.2)
		purchased_rect.scale         = Vector2(1.0, 1.0)
		purchased_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE

		var owned_label := Label.new()
		owned_label.text                 = "OWNED"
		owned_label.position             = Vector2.ZERO
		owned_label.size                 = COIN_SIZE
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		owned_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		owned_label.theme                = theme_kenney
		owned_label.add_theme_color_override("font_color", Color.WHITE)
		owned_label.add_theme_font_size_override("font_size", 28)
		purchased_rect.add_child(owned_label)

	selected_coin_rect = null
	your_money_amount.text = str(player_cash)
	cancel_btn.disabled = false
	_in_purchase_seq = false
	_update_buy_button()


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	if _in_purchase_seq:
		return
	SoundManagerScript.stop_bgm()
	SceneCache.change_scene(CELESTE_HARBOUR)


func _input(event: InputEvent) -> void:
	if _in_purchase_seq:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel_pressed()


# ─── Sparkle particles ───────────────────────────────────────────────────────

func _start_sparkle(target: TextureRect) -> void:
	if _active_particles:
		_active_particles.queue_free()

	var particles := CPUParticles2D.new()
	add_child(particles)
	_active_particles = particles

	particles.global_position       = target.global_position + target.size / 2.0
	particles.z_index               = 50
	particles.amount                = 20
	particles.lifetime              = 0.9
	particles.one_shot              = false
	particles.explosiveness         = 0.0
	particles.emitting              = true
	particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = target.size / 2.0
	particles.direction             = Vector2(0, 0)
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.gravity               = Vector2(0, 0)
	particles.scale_amount_min      = 3.0
	particles.scale_amount_max      = 6.0

	var sparkle_colour := _get_coin_sparkle_colour(target.get_meta("coin_filename", ""))
	var bright         := sparkle_colour.lightened(1.0)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient


func _get_coin_sparkle_colour(coin_filename: String) -> Color:
	var n := coin_filename.to_lower()
	if " red"    in n: return Color(1.0, 0.2,  0.2)
	if " gold"   in n: return Color(1.0, 0.85, 0.2)
	if " silver" in n: return Color(0.85, 0.85, 0.9)
	if " blue"   in n: return Color(0.3,  0.5,  1.0)
	if " green"  in n: return Color(0.2,  0.9,  0.3)
	if " pink"   in n: return Color(1.0,  0.2,  0.7)
	if " purple" in n: return Color(0.55, 0.1,  1.0)
	if " black"  in n: return Color(0.0,  0.0,  0.0)
	if " brown"  in n: return Color(0.5,  0.3,  0.2)
	return Color(1.0, 1.0, 1.0)


# ─── Flip animation (mirrored from MapManager._play_flip_animation) ───────────

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


# ─── Coin name formatting ────────────────────────────────────────────────────
# Reorders colour to front and appends "Coin", number goes last.
#   "Gyarados Blue"      -> "Blue Gyarados Coin"
#   "Pikachu Gold 1"     -> "Gold Pikachu Coin 1"
#   "Team Plasma Silver 2" -> "Silver Team Plasma Coin 2"

func _format_coin_name(raw: String) -> String:
	var base   := raw.trim_suffix(".png")
	var is_rare := false
	for prefix in ["Zzzz ", "Zzz ", "Zz "]:
		if base.begins_with(prefix):
			base = base.trim_prefix(prefix)
			is_rare = true
			break
	var words  := base.split(" ")
	var colours := ["red", "blue", "gold", "silver", "green", "black", "purple",
					"pink", "brown", "yellow", "orange", "white"]
	var colour     := ""
	var number     := ""
	var name_parts : Array = []
	var i := words.size() - 1
	if i >= 0 and words[i].is_valid_int():
		number = words[i]
		i -= 1
	if i >= 0 and words[i].to_lower() in colours:
		colour = words[i]
		i -= 1
	for j in range(i + 1):
		name_parts.append(words[j])
	var pieces : Array = []
	if is_rare:
		pieces.append("Rare")
	if colour != "":
		pieces.append(colour)
	pieces.append_array(name_parts)
	pieces.append("Coin")
	if number != "":
		pieces.append(number)
	return " ".join(pieces)
