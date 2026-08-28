extends Control

# ============================================================
# SLEEVE SELLER — SLEEVE SHOP
# ============================================================
# A Sleeve Seller NPC's full screen. Structurally the Coin Shop's twin: a grid of
# buyable items, a cost/cash readout, buy + cancel, an "OWNED" stamp on anything the
# player already has, and a full-screen reveal after a purchase.
#
# TWO DIFFERENCES from the Coin Shop, both because a sleeve is a card back:
#   1. There is no sleeve "back" texture to flip from, so the reveal uses the COSTUME
#      FADE-IN instead of the coin flip — the image starts fully black and fades up
#      over the dim overlay (mirrors MapManager._play_costume_fadein).
#   2. The stock is per-NPC rather than global. GameState.current_shop_id picks the
#      block in sleeve_shop_inventory.json, so a second seller elsewhere in the world
#      runs this exact screen with different sleeves and prices — no code changes,
#      just a new block in the JSON and a shop_id on the NPC.
#
# Sleeve names are bare basenames ("Oricorio_Pink") throughout — that is how they are
# stored in the player's progress "sleeves" array and how GameState.has_sleeve() and
# add_sleeve_to_collection() expect them.
# ============================================================


# ─── Constants ───────────────────────────────────────────────────────────────

const INVENTORY_PATH  := "res://NPC_and_Opponent_Data/sleeve_shop_inventory.json"
const SLEEVE_FOLDER   := "res://Image_Assets/Sleeves"
const SLEEVE_SMALL    := "res://Image_Assets/Sleeves/small"
const GYM_PLAZA       := "res://Scenes/Map_Scenes/Gym_Plaza.tscn"

## TWEAKABLE — fallback price for an inventory entry with no "cost" field. The real
## prices live in sleeve_shop_inventory.json; keep this in step so a malformed entry
## cannot quietly sell a sleeve at an out-of-date price.
const DEFAULT_SLEEVE_COST := 400

## The box the grid is laid out inside, in screen pixels. Matches the empty space the
## scene leaves between the header and the money labels.
const GRID_AREA_POS  := Vector2(260.0, 190.0)
const GRID_AREA_SIZE := Vector2(1400.0, 610.0)

## TWEAKABLE — grid shape. Cells are sized to fit GRID_AREA_SIZE, so a seller stocking
## more sleeves gets smaller cells rather than an overflowing grid.
const MAX_COLUMNS  := 4
const CELL_SEP     := 60
const MAX_CELL_H   := 412.0   # the small/ thumbnails' native height — never upscale past it

## Card-back aspect (432 x 594, the same box the overworld gift reveal uses).
const SLEEVE_ASPECT := 432.0 / 594.0

## TWEAKABLE — the purchase reveal.
const REVEAL_SIZE      := Vector2(432.0, 594.0)
const REVEAL_FADE      := 1.0   # seconds to fade from black to full colour


# ─── State ───────────────────────────────────────────────────────────────────

var inventory       : Array = []
var shop_title      : String = "Sleeve Shop"
var player_cash     : int = 0
var _owned_sleeves  : Dictionary = {}

var selected_cell   : Control = null
var _active_tween   : Tween = null
var _active_particles : CPUParticles2D = null
var _in_purchase_seq : bool = false
## The reveal's OK button, held so _input() can press it from the keyboard.
var _reveal_ok_btn  : Button = null


# ─── Theme references ────────────────────────────────────────────────────────

var theme_kenney       : Theme = preload("res://UI_Themes/kenneyUI.tres")
var theme_kenney_green : Theme = preload("res://UI_Themes/kenneyUI-green.tres")


# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid              : GridContainer = $sleeve_grid_container
@onready var buy_btn           : Button        = $sleeve_buy_button
@onready var cancel_btn        : Button        = $buy_cancel_button
@onready var header_label      : Label         = $large_header_text_label
@onready var your_money_amount : Label         = $"MONEY LABELS"/your_money_amount
@onready var sleeve_cost_amount: Label         = $"MONEY LABELS"/sleeve_cost_amount


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_SHOP_2, true)

	_load_inventory()
	_load_player_data()

	header_label.text = shop_title

	grid.add_theme_constant_override("h_separation", CELL_SEP)
	grid.add_theme_constant_override("v_separation", CELL_SEP)

	your_money_amount.text = str(player_cash)
	sleeve_cost_amount.text = str(_lowest_cost())

	buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	await get_tree().process_frame
	_build_sleeve_grid()


func _process(_delta: float) -> void:
	if _active_particles and selected_cell:
		_active_particles.global_position = selected_cell.global_position + selected_cell.size / 2.0


# ─── Data loading ────────────────────────────────────────────────────────────

## Stock is chosen by GameState.current_shop_id, which the Sleeve Seller NPC sets on its
## way in (MapManager._open_sleeve_shop). An id with no block falls back to the first one
## in the file so a mistyped shop_id shows a working shop rather than an empty screen.
func _load_inventory() -> void:
	var file := FileAccess.open(INVENTORY_PATH, FileAccess.READ)
	if file == null:
		push_error("SleeveShop: cannot open " + INVENTORY_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("SleeveShop: inventory JSON did not parse to Dictionary")
		return

	var block = data.get(GameState.current_shop_id, null)
	if not block is Dictionary:
		push_warning("SleeveShop: no stock block for shop_id '" + GameState.current_shop_id
				+ "' — falling back to the first block in the file")
		for key in data.keys():
			if data[key] is Dictionary and data[key].has("sleeves"):
				block = data[key]
				break
	if not block is Dictionary:
		return

	inventory  = block.get("sleeves", [])
	shop_title = block.get("title", "Sleeve Shop")


func _load_player_data() -> void:
	player_cash = GameState.get_cash()
	for sleeve_name in GameState.get_sleeves():
		_owned_sleeves[String(sleeve_name)] = true


## The figure shown before anything is picked. Everything in stock is usually the same
## price, so the cheapest entry is the honest "from" number.
func _lowest_cost() -> int:
	var lowest := DEFAULT_SLEEVE_COST
	var found := false
	for entry in inventory:
		var cost : int = int(entry.get("cost", DEFAULT_SLEEVE_COST))
		if not found or cost < lowest:
			lowest = cost
			found = true
	return lowest


# ─── Texture resolution ──────────────────────────────────────────────────────

## Grid and reveal both use the small/ copy — the full-size originals are a mix of .jpg
## and .png and are far bigger than either use needs. Falls back to the original if a
## sleeve has no small/ copy, matching Sleeves_Scene's resolution order in reverse.
func _load_sleeve_texture(sleeve_name: String) -> Texture2D:
	var small_path := SLEEVE_SMALL + "/" + sleeve_name + ".jpg"
	if ResourceLoader.exists(small_path):
		var small_tex := load(small_path) as Texture2D
		if small_tex != null:
			return small_tex
	for ext in [".png", ".jpg"]:
		var full_path : String = SLEEVE_FOLDER + "/" + sleeve_name + String(ext)
		if ResourceLoader.exists(full_path):
			var full_tex := load(full_path) as Texture2D
			if full_tex != null:
				return full_tex
	push_warning("SleeveShop: no texture found for sleeve " + sleeve_name)
	return null


## Same lookup with the priority reversed, for the purchase reveal. The reveal box is
## 432x594 and the small/ copies are only 300x412, so showing the thumbnail there would
## upscale it by 1.44x. One full-size texture in a menu is cheap; a whole grid of them
## would not be, which is why the grid still uses small/.
func _load_sleeve_texture_full(sleeve_name: String) -> Texture2D:
	for ext in [".png", ".jpg"]:
		var full_path : String = SLEEVE_FOLDER + "/" + sleeve_name + String(ext)
		if ResourceLoader.exists(full_path):
			var full_tex := load(full_path) as Texture2D
			if full_tex != null:
				return full_tex
	return _load_sleeve_texture(sleeve_name)


# ─── Grid building ───────────────────────────────────────────────────────────

## Cells are sized from the stock count rather than fixed, so a seller with three sleeves
## gets big ones and a seller with eight still fits inside GRID_AREA_SIZE. The whole block
## is then re-centred inside that area — a GridContainer only lays out from its top-left.
func _build_sleeve_grid() -> void:
	var count := inventory.size()
	if count == 0:
		return

	var columns : int = min(count, MAX_COLUMNS)
	var rows    : int = int(ceil(float(count) / float(columns)))
	grid.columns = columns

	var fit_w : float = (GRID_AREA_SIZE.x - float(columns - 1) * CELL_SEP) / float(columns)
	var fit_h : float = (GRID_AREA_SIZE.y - float(rows - 1) * CELL_SEP) / float(rows)
	# Height is the binding dimension: pick whichever of the two limits is tighter once
	# the card-back aspect is applied, and never upscale past the source's native height.
	var cell_h : float = min(fit_h, fit_w / SLEEVE_ASPECT, MAX_CELL_H)
	var cell_size := Vector2(cell_h * SLEEVE_ASPECT, cell_h)

	for entry in inventory:
		var sleeve_name : String = String(entry.get("name", ""))
		var cost        : int    = int(entry.get("cost", DEFAULT_SLEEVE_COST))
		if sleeve_name == "":
			continue

		var tex := _load_sleeve_texture(sleeve_name)
		if tex == null:
			continue

		var is_owned : bool = _owned_sleeves.has(sleeve_name)

		# Wrapper carries the cell geometry and the metadata; the TextureRect inside is
		# aspect-fitted so a sleeve whose source is off-aspect is letterboxed, not squashed.
		var wrapper := Control.new()
		wrapper.custom_minimum_size = cell_size
		wrapper.size                = cell_size
		wrapper.clip_contents       = true
		wrapper.set_meta("sleeve_name", sleeve_name)
		wrapper.set_meta("sleeve_cost", cost)
		wrapper.set_meta("is_owned",    is_owned)

		var tex_size := tex.get_size()
		var s : float = minf(cell_size.x / tex_size.x, cell_size.y / tex_size.y)
		var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

		var rect := TextureRect.new()
		rect.texture             = tex
		rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode        = TextureRect.STRETCH_SCALE
		rect.custom_minimum_size = disp_size
		rect.size                = disp_size
		rect.position            = (cell_size - disp_size) / 2.0
		rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(rect)

		if is_owned:
			_mark_cell_owned(wrapper)
		else:
			wrapper.modulate = Color(0.8, 0.8, 0.8)
			wrapper.gui_input.connect(_on_sleeve_clicked.bind(wrapper))

		grid.add_child(wrapper)

	# Re-centre the block inside the grid area. The content size is computed from the cells
	# rather than read back off the container: a GridContainer only lays out from its own
	# top-left, and its size is not settled on the frame the children are added. Rows are
	# recomputed from what actually went in, in case a sleeve's texture failed to load.
	var placed : int = grid.get_child_count()
	if placed == 0:
		return
	var placed_cols : int = min(placed, columns)
	var placed_rows : int = int(ceil(float(placed) / float(placed_cols)))
	var content := Vector2(
		float(placed_cols) * cell_size.x + float(placed_cols - 1) * CELL_SEP,
		float(placed_rows) * cell_size.y + float(placed_rows - 1) * CELL_SEP
	)
	grid.size     = content
	grid.position = GRID_AREA_POS + (GRID_AREA_SIZE - content) / 2.0


## Dims the sleeve and stamps OWNED across it. self_modulate dims only the wrapper's own
## drawing, so it is applied to the image rect — the label added here stays readable.
func _mark_cell_owned(wrapper: Control) -> void:
	wrapper.set_meta("is_owned", true)
	wrapper.modulate     = Color(1, 1, 1, 1)
	wrapper.scale        = Vector2(1.0, 1.0)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in wrapper.get_children():
		if child is TextureRect:
			child.self_modulate = Color(0.2, 0.2, 0.2)

	var owned_label := Label.new()
	owned_label.text                 = "OWNED"
	owned_label.position             = Vector2.ZERO
	owned_label.size                 = wrapper.size
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	owned_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	owned_label.theme                = theme_kenney
	owned_label.add_theme_color_override("font_color", Color.WHITE)
	owned_label.add_theme_font_size_override("font_size", 40)
	wrapper.add_child(owned_label)


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_sleeve_clicked(event: InputEvent, cell: Control) -> void:
	if _in_purchase_seq:
		return
	# UIInput.is_click() rather than a raw button test — a mouse wheel notch is also an
	# InputEventMouseButton and would otherwise register as a click.
	if not UIInput.is_click(event):
		return

	if selected_cell and selected_cell != cell:
		_deselect_sleeve(selected_cell)

	if selected_cell == cell:
		_deselect_sleeve(cell)
		selected_cell = null
		sleeve_cost_amount.text = str(_lowest_cost())
		_update_buy_button()
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return

	_select_sleeve(cell)
	sleeve_cost_amount.text = str(int(cell.get_meta("sleeve_cost", DEFAULT_SLEEVE_COST)))
	_update_buy_button()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


func _select_sleeve(cell: Control) -> void:
	selected_cell = cell
	_apply_selected_animation(cell)
	_start_sparkle(cell)


func _deselect_sleeve(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_particles:
		_active_particles.queue_free()
		_active_particles = null
	if is_instance_valid(cell) and not cell.get_meta("is_owned", false):
		cell.modulate     = Color(0.8, 0.8, 0.8)
		cell.scale        = Vector2(1.0, 1.0)
		cell.pivot_offset = cell.size / 2.0


func _apply_selected_animation(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()
	cell.pivot_offset = cell.size / 2.0
	cell.modulate = Color.WHITE
	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	tween.tween_property(cell, "modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(cell, "scale", Vector2(1.02, 1.02), 0.2)
	tween.tween_property(cell, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(cell, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Buy button ──────────────────────────────────────────────────────────────

func _update_buy_button() -> void:
	var can_buy := false
	if selected_cell != null and is_instance_valid(selected_cell):
		var is_owned : bool = selected_cell.get_meta("is_owned", true)
		var cost     : int  = int(selected_cell.get_meta("sleeve_cost", DEFAULT_SLEEVE_COST))
		can_buy = not is_owned and player_cash >= cost
	buy_btn.disabled = not can_buy
	buy_btn.theme    = theme_kenney_green if can_buy else theme_kenney


# ─── Purchase ────────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	if selected_cell == null or not is_instance_valid(selected_cell):
		return
	var sleeve_name : String = String(selected_cell.get_meta("sleeve_name", ""))
	var cost        : int    = int(selected_cell.get_meta("sleeve_cost", DEFAULT_SLEEVE_COST))
	if sleeve_name == "" or player_cash < cost:
		return

	player_cash -= cost
	GameState.add_cash(-cost)
	GameState.add_sleeve_to_collection(sleeve_name)
	_owned_sleeves[sleeve_name] = true
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	_show_purchase_display(sleeve_name)


## The reveal. Same overlay furniture as the Coin Shop's, but the sleeve fades up from
## black instead of flipping — there is no card-back-of-a-card-back to flip from.
func _show_purchase_display(sleeve_name: String) -> void:
	_in_purchase_seq = true
	buy_btn.disabled    = true
	cancel_btn.disabled = true

	var sleeve_tex := _load_sleeve_texture_full(sleeve_name)

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

	# Sleeve aspect-fitted into the reveal box and centred on screen
	var vp_size : Vector2 = get_viewport_rect().size
	var disp_size := REVEAL_SIZE
	if sleeve_tex != null:
		var t_size := sleeve_tex.get_size()
		if t_size.x > 0.0 and t_size.y > 0.0:
			var s : float = minf(REVEAL_SIZE.x / t_size.x, REVEAL_SIZE.y / t_size.y)
			disp_size = Vector2(t_size.x * s, t_size.y * s)

	var sleeve_pos := Vector2(
		vp_size.x / 2.0 - disp_size.x / 2.0,
		vp_size.y / 2.0 - disp_size.y / 2.0 - 80.0
	)

	var sleeve_rect := TextureRect.new()
	sleeve_rect.texture             = sleeve_tex
	sleeve_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	sleeve_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	sleeve_rect.custom_minimum_size = disp_size
	sleeve_rect.size                = disp_size
	sleeve_rect.position            = sleeve_pos
	sleeve_rect.pivot_offset        = disp_size / 2.0
	sleeve_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(sleeve_rect)

	# Text label below the sleeve
	var label := Label.new()
	label.text                 = "You got the " + _format_sleeve_name(sleeve_name) + " Sleeve"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position             = Vector2(160.0, sleeve_pos.y + disp_size.y + 20.0)
	label.size                 = Vector2(1600.0, 80.0)
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.modulate             = Color(1, 1, 1, 0)   # fades up with the sleeve
	overlay_layer.add_child(label)

	# OK button — hidden until the fade finishes
	var ok_btn := Button.new()
	ok_btn.text     = "OK"
	ok_btn.size     = Vector2(400.0, 60.0)
	ok_btn.position = Vector2(vp_size.x / 2.0 - 200.0, label.position.y + 90.0)
	ok_btn.visible  = false
	ok_btn.theme    = theme_kenney_green
	overlay_layer.add_child(ok_btn)

	await _play_fadein(sleeve_rect, label)
	ok_btn.visible = true
	_reveal_ok_btn = ok_btn   # _input() presses this from the keyboard

	# Wait for the player to dismiss
	await ok_btn.pressed
	_reveal_ok_btn = null
	overlay_layer.queue_free()

	# Stamp the purchased sleeve as owned in the grid
	var purchased_cell := selected_cell
	if purchased_cell != null and is_instance_valid(purchased_cell):
		if _active_tween:
			_active_tween.kill()
			_active_tween = null
		if _active_particles:
			_active_particles.queue_free()
			_active_particles = null
		_mark_cell_owned(purchased_cell)

	selected_cell = null
	your_money_amount.text  = str(player_cash)
	sleeve_cost_amount.text = str(_lowest_cost())
	cancel_btn.disabled     = false
	_in_purchase_seq        = false
	_update_buy_button()


## Costume-style reveal, from MapManager._play_costume_fadein: black up to full colour over
## the dim overlay. Duration runs through GameState.item_time so the Options screen's
## item-animation speed applies here too.
##
## The overworld version holds fully black for half a second before starting, which on a
## black dim overlay is just half a second of nothing — the sleeve is invisible until the
## fade begins. Dropped here: the tween starts on the same frame the rect is spawned.
func _play_fadein(rect: TextureRect, label: Label) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	rect.modulate  = Color(0, 0, 0, 1)   # fully black, opaque
	label.modulate = Color(1, 1, 1, 0)

	var fade := GameState.item_time(REVEAL_FADE)
	var tween := create_tween()
	tween.tween_property(rect, "modulate", Color(1, 1, 1, 1), fade)
	if is_instance_valid(label):
		tween.parallel().tween_property(label, "modulate", Color(1, 1, 1, 1), fade)
	await tween.finished


## Sleeve basename -> readable name. Same rule as MapManager._format_sleeve_name: swap
## underscores for spaces and keep the file's own capitalisation, so the name reads as it
## does in the sleeve menu ("Oricorio_Pink" -> "Oricorio Pink").
func _format_sleeve_name(raw: String) -> String:
	return raw.get_basename().replace("_", " ").strip_edges()


# ─── Cancel / Escape ─────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	if _in_purchase_seq:
		return
	SoundManagerScript.stop_bgm()
	var target : String = GameState.menu_return_scene_path if GameState.has_menu_return_state \
		else GYM_PLAZA
	SceneCache.change_scene(target)


func _input(event: InputEvent) -> void:
	# The reveal takes the same keyboard handling as the Coin Shop's: Space / Enter /
	# Escape press OK. Consumed so the press cannot also fire ui_accept on a focused button.
	if _reveal_ok_btn != null and is_instance_valid(_reveal_ok_btn):
		if UIInput.is_advance(event):
			get_viewport().set_input_as_handled()
			_reveal_ok_btn.pressed.emit()
		return
	if _in_purchase_seq:
		return
	if UIInput.is_cancel(event):
		_on_cancel_pressed()


# ─── Sparkle particles ───────────────────────────────────────────────────────

func _start_sparkle(target: Control) -> void:
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

	var sparkle_colour := _get_sleeve_sparkle_colour(String(target.get_meta("sleeve_name", "")))
	var bright         := sparkle_colour.lightened(1.0)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient


## Colour word anywhere in the sleeve name tints its sparkle ("Oricorio_Pink" -> pink).
## Underscores are swapped for spaces first so the match works on either separator.
func _get_sleeve_sparkle_colour(sleeve_name: String) -> Color:
	var n := " " + sleeve_name.to_lower().replace("_", " ") + " "
	if " red"    in n: return Color(1.0,  0.2,  0.2)
	if " gold"   in n: return Color(1.0,  0.85, 0.2)
	if " silver" in n: return Color(0.85, 0.85, 0.9)
	if " blue"   in n: return Color(0.3,  0.5,  1.0)
	if " green"  in n: return Color(0.2,  0.9,  0.3)
	if " pink"   in n: return Color(1.0,  0.2,  0.7)
	if " purple" in n: return Color(0.55, 0.1,  1.0)
	if " yellow" in n: return Color(1.0,  0.9,  0.3)
	if " orange" in n: return Color(1.0,  0.55, 0.15)
	return Color(1.0, 1.0, 1.0)
