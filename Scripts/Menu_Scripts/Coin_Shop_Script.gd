extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const INVENTORY_PATH   := "res://NPC_and_Opponent_Data/coin_shop_inventory.json"
const COIN_FOLDER      := "res://Image_Assets/Coins"
const COINBACK_PATH    := "res://Image_Assets/Coins/Back Basic.png"
const CELESTE_HARBOUR  := "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
## TWEAKABLE — grid shape. Grown from 200/100 when the "Your money / Coin cost" label block
## was replaced by the wallet chip and per-coin price pills (see ShopChrome): the freed band
## across the bottom of the screen let the coins go up without crowding anything. Native coin
## art is ~315px square, so 250 is still a downscale. The scene positions the container to
## match — change these and move coin_grid_container's offsets in Coin_Shop.tscn to suit.
const COIN_SIZE        := Vector2(250, 250)
const COIN_SEPARATION  := 90
const COLUMNS          := 5
const GIFT_COIN_SIZE   := Vector2(250, 250)
const GIFT_FLIP_TOTAL  := 1.5

# ISSUE #92: fallback price for an inventory entry with no "cost" field. TWEAKABLE, but the real
# prices live in coin_shop_inventory.json — keep this in step with them so a malformed entry can't
# quietly sell a coin at an out-of-date price.
const DEFAULT_COIN_COST := 100   # ISSUE #167: coins are $100, not $500

## TWEAKABLE — how far the coin ART is knocked back in each resting state. Both are applied
## with self_modulate so the price pill, which is a child, keeps its own colour. OWNED_DIM was
## 0.2 alongside the old centred "OWNED" stamp; with the grey pill carrying that message the
## coin no longer has to be blacked out to read as unavailable.
const OWNED_DIM      := Color(0.45, 0.45, 0.45)
const UNSELECTED_DIM := Color(0.8, 0.8, 0.8)

# ─── State ───────────────────────────────────────────────────────────────────

var inventory        : Array = []
var player_cash      : int   = 0
var _owned_coins     : Dictionary = {}

var selected_coin_rect : TextureRect = null
var _active_tween      : Tween       = null
var _active_particles  : CPUParticles2D = null
var _in_purchase_seq   : bool        = false
# ISSUE #116 sibling: the reveal's OK button, held so _input() can press it from the keyboard.
var _reveal_ok_btn     : Button      = null

# ─── Theme references ─────────────────────────────────────────────────────────


# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid             : GridContainer = $coin_grid_container
@onready var buy_btn          : Button        = $coin_buy_button
@onready var cancel_btn       : Button        = $buy_cancel_button

## The top-right cash pill, built at runtime by ShopChrome. Replaces the four font-61
## "Your money / Coin cost" Labels that used to sit bottom-right; the per-coin price is now
## a pill on the coin itself.
var wallet_chip : Control = null

## The flat layer every price pill is drawn on. Pills are NOT children of the coins: the
## selection tween scales a coin, and the sparkle emitter sits at z 50 — a nested pill would
## be scaled by the first and drawn under the second.
var pill_layer  : Control = null

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_SHOP_2, true)

	_load_inventory()
	_load_player_data()

	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", COIN_SEPARATION)
	grid.add_theme_constant_override("v_separation", COIN_SEPARATION)

	_build_chrome()
	wallet_chip = ShopChrome.add_wallet_chip(self, player_cash)
	pill_layer  = ShopChrome.add_pill_layer(self)

	buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	await get_tree().process_frame
	_build_coin_grid()


## Swaps the old bordered chrome for the Spectrum Night bars and moves this
## screen's controls into them. ShopChrome's wallet chip stays pinned top-right
## on its own layer (z 1000) so it draws over the header bar, which is exactly
## where the design wants the balance.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "Coin shop")
	var old_title := get_node_or_null("large_header_text_label")
	if old_title != null:
		old_title.queue_free()

	# Cancel first: the footer slot is an HBox, so insertion order is left-to-right.
	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")
	UIKit.adopt_button(buy_btn, bars["footer"].centre, "primary")



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

		# EVERY dim and pulse on a coin uses self_modulate, never modulate: modulate would
		# propagate into the price pill hanging off the corner and dim or brighten that too.
		if is_owned:
			rect.self_modulate = OWNED_DIM
			rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		else:
			rect.self_modulate = UNSELECTED_DIM
			rect.gui_input.connect(_on_coin_clicked.bind(rect))

		grid.add_child(rect)
		UIKit.add_drop_shadow(rect)

	_refresh_pills()


# ─── Price pills ─────────────────────────────────────────────────────────────

## Rebuilds the whole set of pills. Called on build and after any purchase — not just for the
## coin bought: spending puts the rest of the shelf out of reach, and those pills have to turn
## red to say so. A coin's pill is grey OWNED once it is in the collection; the centred font-28
## "OWNED" stamp this replaced is gone.
##
## Deferred a frame because the GridContainer has not placed its children yet on the frame they
## are added, and each pill anchors to its coin's global rect. Every caller reaches this with
## selection cleared and scales back at 1, which is what keeps those rects the resting ones.
func _refresh_pills() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

	ShopChrome.clear_pills(pill_layer)
	for child in grid.get_children():
		if not (child is TextureRect) or not is_instance_valid(child):
			continue
		var cost : int = child.get_meta("coin_cost", DEFAULT_COIN_COST)
		var state : int
		if child.get_meta("is_owned", false):
			state = ShopChrome.OWNED
		elif player_cash >= cost:
			state = ShopChrome.AFFORDABLE
		else:
			state = ShopChrome.UNAFFORDABLE
		ShopChrome.add_price_pill(pill_layer, child.get_global_rect(), state, cost)


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
		rect.self_modulate = UNSELECTED_DIM
		rect.scale         = Vector2(1.0, 1.0)
		rect.pivot_offset  = rect.size / 2.0


## ISSUE #263 (retest): 1.2 -> 1.08, i.e. 10% less. The user's original row was
## about the COIN CASE, not this screen - see Coin_Case_Script.SELECT_PULSE - and
## the shop only needed to come back down once the case was doing the shouting.
## TWEAKABLE - peak scale of the selected-coin pulse, matched to the
## costume grid's SELECT_PULSE. A 2% grow on a 100px coin is two pixels, which is
## not visible at all; the costumes were raised to 1.2 for the same reason (#162).
const SELECT_PULSE := 1.08

func _apply_selected_animation(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
	rect.pivot_offset  = rect.size / 2.0
	rect.self_modulate = Color.WHITE
	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	# self_modulate, not modulate — the pulse must not reach the price pill child. scale is
	# left on the node itself on purpose, so the pill grows and shrinks with its coin.
	tween.tween_property(rect, "self_modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(SELECT_PULSE, SELECT_PULSE), 0.2)
	tween.tween_property(rect, "self_modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Buy button ──────────────────────────────────────────────────────────────

func _update_buy_button() -> void:
	var can_buy := false
	if selected_coin_rect != null and is_instance_valid(selected_coin_rect):
		var is_owned : bool = selected_coin_rect.get_meta("is_owned", true)
		var cost     : int  = selected_coin_rect.get_meta("coin_cost", DEFAULT_COIN_COST)
		can_buy = not is_owned and player_cash >= cost
	buy_btn.disabled = not can_buy
	UIKit.style_button(buy_btn, "good" if can_buy else "primary")


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
	UIKit.style_button(ok_btn, "good")
	overlay_layer.add_child(ok_btn)

	# Play flip animation, then reveal OK
	await _play_flip_animation(coin_rect, back_tex, coin_tex)
	ok_btn.visible = true
	_reveal_ok_btn = ok_btn   # ISSUE #116 sibling: _input() presses this from the keyboard

	# Wait for player to dismiss
	await ok_btn.pressed
	_reveal_ok_btn = null
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
		purchased_rect.self_modulate = OWNED_DIM
		purchased_rect.scale         = Vector2(1.0, 1.0)
		purchased_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	selected_coin_rect = null
	ShopChrome.set_wallet_cash(wallet_chip, player_cash)
	# Every pill, not just the one bought: the coin just purchased flips to grey OWNED and
	# anything the remaining balance no longer covers flips green -> red.
	_refresh_pills()
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
	# ISSUE #116 FIX ACTIVE (sibling of the holo shop): the coin shop's purchase reveal has the
	# identical overlay + OK button, so it takes the identical keyboard handling -- Space / Enter
	# / Escape press OK. Consumed so the press can't also fire ui_accept on a focused button.
	if _reveal_ok_btn != null and is_instance_valid(_reveal_ok_btn):
		if UIInput.is_advance(event):
			get_viewport().set_input_as_handled()
			_reveal_ok_btn.pressed.emit()
		return
	if _in_purchase_seq:
		return
	# Was a raw KEY_ESCAPE test; routed through UIInput like every other dialog.
	if UIInput.is_cancel(event):
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
