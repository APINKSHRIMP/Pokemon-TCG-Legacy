extends Control

# ============================================================
# COSMETIC SHOP — SLEEVE SELLERS AND COSTUME SALESMEN
# ============================================================
# One screen for every NPC who sells a cosmetic. Structurally the Coin Shop's twin: a
# grid of buyable items, a cost/cash readout, buy + cancel, an "OWNED" stamp on anything
# the player already has, and a full-screen reveal after a purchase.
#
# THREE DIFFERENCES from the Coin Shop:
#   1. There is no "back" texture to flip from — a sleeve IS a card back and a costume is
#      a character sprite — so the reveal uses the COSTUME FADE-IN instead of the coin
#      flip: the image starts fully black and fades up over the dim overlay (mirrors
#      MapManager._play_costume_fadein).
#   2. The stock is per-NPC rather than global. GameState.current_shop_id picks the block
#      in cosmetic_shop_inventory.json, so another seller elsewhere in the world runs this
#      exact screen with different wares — no code changes, just a new block in the JSON
#      and a shop_id on the NPC.
#   3. NO SPARKLE PARTICLES on the selected cell. The glitter is reserved for things that
#      actually shine — holo cards and coins (Coin_Shop, Holo_Rare_Shop, Coin_Case,
#      Pack_Opening, and the coinflip/holo-gift reveals in MapManager). Selection here is
#      the pulse tween alone. Do not re-add it.
#
# WHAT the block sells is the block's own "kind" field, which is the only thing that
# differs between a Sleeve Seller and a Costume Salesman: where the art comes from, the
# shape of a grid cell, and which GameState collection the purchase is banked into. Both
# store bare basenames ("Oricorio_Pink", "Pokemaniac_Red") — that is how they sit in the
# player's progress arrays and how GameState's has_/add_ calls expect them.
#
# There is deliberately NO sold-out gate. A seller's shelf is finite and never restocks,
# so once the player owns the lot the shop simply opens with everything stamped OWNED
# rather than being replaced by a "come back later" line that would never come true.
# ============================================================


# ─── Constants ───────────────────────────────────────────────────────────────

const INVENTORY_PATH  := "res://NPC_and_Opponent_Data/cosmetic_shop_inventory.json"
const SLEEVE_FOLDER   := "res://Image_Assets/Sleeves"
const SLEEVE_SMALL    := "res://Image_Assets/Sleeves/small"
const COSTUME_FOLDER  := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const GYM_PLAZA       := "res://Scenes/Map_Scenes/Gym_Plaza.tscn"

const KIND_SLEEVE  := "sleeve"
const KIND_COSTUME := "costume"

## TWEAKABLE — fallback price for an inventory entry with no "cost" field. The real
## prices live in cosmetic_shop_inventory.json; keep this high enough that a malformed
## entry cannot quietly sell something at an out-of-date price.
const DEFAULT_ITEM_COST := 400

## TWEAKABLE — how far an item's ART is knocked back in each resting state. Both are applied
## with self_modulate on the art rect so the price pill, a sibling under the same wrapper,
## keeps its own colour. OWNED_DIM was 0.2 alongside the old centred "OWNED" stamp; with the
## grey pill carrying that message the item no longer has to be blacked out.
const OWNED_DIM      := Color(0.45, 0.45, 0.45)
const UNSELECTED_DIM := Color(0.8, 0.8, 0.8)

## The box the grid is laid out inside, in screen pixels. Grown from (260,190)/(1400,610)
## when the "Your money / Sleeve cost" label block was replaced by the wallet chip and
## per-item price pills (see ShopChrome) — that block used to reserve a 190px band across
## the bottom of the screen. Bottom edge is kept clear of the bottom border at y977 so the
## pills, which hang below their cells, still have somewhere to go.
const GRID_AREA_POS  := Vector2(160.0, 140.0)
const GRID_AREA_SIZE := Vector2(1600.0, 780.0)

## TWEAKABLE — grid shape. Cells are sized to fit GRID_AREA_SIZE, so a seller stocking
## more items gets smaller cells rather than an overflowing grid. A block may override
## the column count with its own "columns" field (10 items at columns 5 = 2 rows of 5).
const MAX_COLUMNS  := 4
const CELL_SEP     := 60

## TWEAKABLE — per-kind cell shape. ASPECT is width/height; MAX_CELL_H caps the cell so a
## small stock list never upscales the source past its native size.
##   sleeve : the card-back box (432 x 594), thumbnails are 300 x 412
##   costume: the battle sprites are square, and are drawn at their native 160px
const SLEEVE_ASPECT   := 432.0 / 594.0
const SLEEVE_MAX_CELL := 412.0
const COSTUME_ASPECT  := 1.0
const COSTUME_MAX_CELL := 320.0

## TWEAKABLE — the purchase reveal. A costume shares the sleeve's box: the aspect-fit
## below letterboxes a square sprite inside it, exactly as the overworld gift reveal does.
const REVEAL_SIZE      := Vector2(432.0, 594.0)
const REVEAL_FADE      := 1.0   # seconds to fade from black to full colour


# ─── State ───────────────────────────────────────────────────────────────────

var inventory       : Array = []
var shop_kind       : String = KIND_SLEEVE
var shop_title      : String = "Sleeve Shop"
var shop_columns    : int = 0        # 0 = let the grid pick; set from the block's "columns"
var player_cash     : int = 0
var _owned_items    : Dictionary = {}

var selected_cell   : Control = null
var _active_tween   : Tween = null
var _in_purchase_seq : bool = false
## The reveal's OK button, held so _input() can press it from the keyboard.
var _reveal_ok_btn  : Button = null


# ─── Theme references ────────────────────────────────────────────────────────



# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid              : GridContainer = $item_grid_container
@onready var buy_btn           : Button        = $item_buy_button
@onready var cancel_btn        : Button        = $buy_cancel_button
@onready var header_label      : Label         = $large_header_text_label

## The top-right cash pill, built at runtime by ShopChrome. Replaces the four font-61
## "Your money / Sleeve cost" Labels that used to sit bottom-right; each item now carries
## its own price on a pill in its bottom-right corner.
var wallet_chip : Control = null

## The flat layer every price pill is drawn on. Pills are NOT children of the cells: the
## selection tween scales a cell, and a nested pill would be scaled along with it instead of
## the item growing and shrinking behind a price that stays put.
var pill_layer  : Control = null


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_SHOP_2, true)

	_load_inventory()
	_load_player_data()

	header_label.text = shop_title

	grid.add_theme_constant_override("h_separation", CELL_SEP)
	grid.add_theme_constant_override("v_separation", CELL_SEP)

	_build_chrome()
	wallet_chip = ShopChrome.add_wallet_chip(self, player_cash)
	pill_layer  = ShopChrome.add_pill_layer(self)

	buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	await get_tree().process_frame
	_build_item_grid()


## Swaps the old bordered chrome for the Spectrum Night bars and moves this
## screen's controls into them. ShopChrome's wallet chip stays pinned top-right
## on its own layer (z 1000) so it draws over the header bar, which is exactly
## where the design wants the balance.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "")
	# The title names the seller and is written at runtime, so the existing Label
	# moves into the header rather than being replaced.
	UIKit.adopt_label(header_label, bars["header"].centre)

	# Cancel first: the footer slot is an HBox, so insertion order is left-to-right.
	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")
	UIKit.adopt_button(buy_btn, bars["footer"].centre, "primary")



# ─── Data loading ────────────────────────────────────────────────────────────

## Stock is chosen by GameState.current_shop_id, which the seller NPC sets on its way in
## (MapManager._open_cosmetic_shop). An id with no block falls back to the first one in
## the file so a mistyped shop_id shows a working shop rather than an empty screen.
func _load_inventory() -> void:
	var file := FileAccess.open(INVENTORY_PATH, FileAccess.READ)
	if file == null:
		push_error("CosmeticShop: cannot open " + INVENTORY_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("CosmeticShop: inventory JSON did not parse to Dictionary")
		return

	var block = data.get(GameState.current_shop_id, null)
	if not block is Dictionary:
		push_warning("CosmeticShop: no stock block for shop_id '" + GameState.current_shop_id
				+ "' — falling back to the first block in the file")
		for key in data.keys():
			if data[key] is Dictionary and data[key].has("items"):
				block = data[key]
				break
	if not block is Dictionary:
		return

	inventory    = block.get("items", [])
	shop_kind    = String(block.get("kind", KIND_SLEEVE))
	shop_title   = block.get("title", "Costume Shop" if shop_kind == KIND_COSTUME else "Sleeve Shop")
	shop_columns = int(block.get("columns", 0))


func _load_player_data() -> void:
	player_cash = GameState.get_cash()
	# Costume filenames are stored lower-cased and with the .png suffix; sleeves are stored
	# as bare basenames. _is_owned() does the per-kind lookup, so nothing is cached here for
	# costumes — GameState is already the single source of truth for both.
	if shop_kind == KIND_SLEEVE:
		for item_name in GameState.get_sleeves():
			_owned_items[String(item_name)] = true


## True when the player already has this item. Sleeves and costumes live in different
## progress arrays with different key formats, so the lookup goes through GameState rather
## than being open-coded here.
func _is_owned(item_name: String) -> bool:
	if shop_kind == KIND_COSTUME:
		return GameState.has_costume(item_name)
	return _owned_items.has(item_name)


# ─── Texture resolution ──────────────────────────────────────────────────────

## Grid art. Sleeves use the small/ copy — the full-size originals are a mix of .jpg and
## .png and are far bigger than a grid cell needs. Costume sprites are already small
## (160px square), so there is only ever one file to find.
func _load_item_texture(item_name: String) -> Texture2D:
	if shop_kind == KIND_COSTUME:
		return _load_costume_texture(item_name)

	var small_path := SLEEVE_SMALL + "/" + item_name + ".jpg"
	if ResourceLoader.exists(small_path):
		var small_tex := load(small_path) as Texture2D
		if small_tex != null:
			return small_tex
	return _load_item_texture_full(item_name)


## Same lookup at full size, for the purchase reveal. The reveal box is 432x594 and the
## sleeve thumbnails are only 300x412, so showing one there would upscale it by 1.44x. One
## full-size texture in a menu is cheap; a whole grid of them would not be, which is why
## the grid still uses small/. Costumes have no second copy — same file both times.
func _load_item_texture_full(item_name: String) -> Texture2D:
	if shop_kind == KIND_COSTUME:
		return _load_costume_texture(item_name)

	for ext in [".png", ".jpg"]:
		var full_path : String = SLEEVE_FOLDER + "/" + item_name + String(ext)
		if ResourceLoader.exists(full_path):
			var full_tex := load(full_path) as Texture2D
			if full_tex != null:
				return full_tex
	push_warning("CosmeticShop: no texture found for sleeve " + item_name)
	return null


func _load_costume_texture(item_name: String) -> Texture2D:
	var path := COSTUME_FOLDER + "/" + item_name + ".png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	push_warning("CosmeticShop: no texture found for costume " + item_name)
	return null


# ─── Grid building ───────────────────────────────────────────────────────────

## Cells are sized from the stock count rather than fixed, so a seller with three items
## gets big ones and a seller with ten still fits inside GRID_AREA_SIZE. The whole block
## is then re-centred inside that area — a GridContainer only lays out from its top-left.
func _build_item_grid() -> void:
	var count := inventory.size()
	if count == 0:
		return

	var columns : int = shop_columns if shop_columns > 0 else MAX_COLUMNS
	columns = min(count, columns)
	var rows    : int = int(ceil(float(count) / float(columns)))
	grid.columns = columns

	var aspect   : float = COSTUME_ASPECT if shop_kind == KIND_COSTUME else SLEEVE_ASPECT
	var max_cell : float = COSTUME_MAX_CELL if shop_kind == KIND_COSTUME else SLEEVE_MAX_CELL

	var fit_w : float = (GRID_AREA_SIZE.x - float(columns - 1) * CELL_SEP) / float(columns)
	var fit_h : float = (GRID_AREA_SIZE.y - float(rows - 1) * CELL_SEP) / float(rows)
	# Height is the binding dimension: pick whichever of the two limits is tighter once
	# the item's aspect is applied, and never upscale past the source's native height.
	var cell_h : float = min(fit_h, fit_w / aspect, max_cell)
	var cell_size := Vector2(cell_h * aspect, cell_h)

	for entry in inventory:
		var item_name : String = String(entry.get("name", ""))
		var cost      : int    = int(entry.get("cost", DEFAULT_ITEM_COST))
		if item_name == "":
			continue

		var tex := _load_item_texture(item_name)
		if tex == null:
			continue

		var is_owned : bool = _is_owned(item_name)

		# Wrapper carries the cell geometry and the metadata; the TextureRect inside is
		# aspect-fitted so an item whose source is off-aspect is letterboxed, not squashed.
		var wrapper := Control.new()
		wrapper.custom_minimum_size = cell_size
		wrapper.size                = cell_size
		# NOT clipped: the price pill deliberately overhangs the cell's bottom-right corner
		# and a clipping wrapper would slice it in half. The art below is aspect-fitted to
		# the cell, so nothing else can spill out.
		wrapper.clip_contents       = false
		wrapper.set_meta("item_name", item_name)
		wrapper.set_meta("item_cost", cost)
		wrapper.set_meta("is_owned",  is_owned)

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
			# self_modulate on the ART, never modulate on the wrapper: modulate propagates
			# into the price pill and would dim that along with the item.
			rect.self_modulate = UNSELECTED_DIM
			wrapper.gui_input.connect(_on_item_clicked.bind(wrapper))

		grid.add_child(wrapper)
		UIKit.add_drop_shadow(rect)

	# Re-centre the block inside the grid area. The content size is computed from the cells
	# rather than read back off the container: a GridContainer only lays out from its own
	# top-left, and its size is not settled on the frame the children are added. Rows are
	# recomputed from what actually went in, in case an item's texture failed to load.
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

	# After the re-centre, never before: pills anchor to each cell's global rect and the whole
	# block has just moved.
	_refresh_pills()


## Knocks the item back and lets its pill carry the OWNED message. The centred font-40
## "OWNED" stamp this used to add is gone — the grey pill says it now, in the same corner
## every other shop puts a price. Dimming is done with self_modulate on the ART rect so the
## pill, which is also a child of the wrapper, keeps its own colour.
func _mark_cell_owned(wrapper: Control) -> void:
	wrapper.set_meta("is_owned", true)
	wrapper.modulate     = Color(1, 1, 1, 1)
	wrapper.scale        = Vector2(1.0, 1.0)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var art := _art_rect(wrapper)
	if art != null:
		art.self_modulate = OWNED_DIM


# ─── Price pills ─────────────────────────────────────────────────────────────

## The art rect inside a cell wrapper — the thing that gets dimmed and pulsed.
func _art_rect(wrapper: Control) -> TextureRect:
	for child in wrapper.get_children():
		if child is TextureRect:
			return child
	return null


## Rebuilds the whole set of pills. Called after the grid is laid out and after any purchase —
## not just for the item bought: spending puts the rest of the shelf out of reach, and those
## pills have to turn red to say so. An item's pill reads grey OWNED once it is in the
## collection, replacing the centred font-40 stamp.
##
## Deferred a frame so the GridContainer has actually placed its children; each pill anchors to
## its cell's global rect. Every caller reaches this with selection cleared and scales back at
## 1, which is what keeps those rects the resting ones.
func _refresh_pills() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

	ShopChrome.clear_pills(pill_layer)
	for child in grid.get_children():
		if not (child is Control) or not is_instance_valid(child):
			continue
		var cost : int = int(child.get_meta("item_cost", DEFAULT_ITEM_COST))
		var state : int
		if child.get_meta("is_owned", false):
			state = ShopChrome.OWNED
		elif player_cash >= cost:
			state = ShopChrome.AFFORDABLE
		else:
			state = ShopChrome.UNAFFORDABLE
		ShopChrome.add_price_pill(pill_layer, child.get_global_rect(), state, cost)


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_item_clicked(event: InputEvent, cell: Control) -> void:
	if _in_purchase_seq:
		return
	# UIInput.is_click() rather than a raw button test — a mouse wheel notch is also an
	# InputEventMouseButton and would otherwise register as a click.
	if not UIInput.is_click(event):
		return

	if selected_cell and selected_cell != cell:
		_deselect_item(selected_cell)

	if selected_cell == cell:
		_deselect_item(cell)
		selected_cell = null
		_update_buy_button()
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return

	_select_item(cell)
	_update_buy_button()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)


## Selection is the pulse tween alone. There are deliberately NO sparkle particles here:
## the glitter is reserved for the holo-rare and coin shops, where the shine is the point.
func _select_item(cell: Control) -> void:
	selected_cell = cell
	_apply_selected_animation(cell)


func _deselect_item(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if is_instance_valid(cell) and not cell.get_meta("is_owned", false):
		var art := _art_rect(cell)
		if art != null:
			art.self_modulate = UNSELECTED_DIM
		cell.scale        = Vector2(1.0, 1.0)
		cell.pivot_offset = cell.size / 2.0


func _apply_selected_animation(cell: Control) -> void:
	if _active_tween:
		_active_tween.kill()
	cell.pivot_offset = cell.size / 2.0
	var art := _art_rect(cell)
	if art == null:
		return
	art.self_modulate = Color.WHITE
	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween
	# The brightness pulse runs on the ART's self_modulate so it cannot reach the price pill;
	# the scale pulse stays on the wrapper on purpose, so the pill grows with its item.
	tween.tween_property(art, "self_modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(cell, "scale", Vector2(1.02, 1.02), 0.2)
	tween.tween_property(art, "self_modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(cell, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Buy button ──────────────────────────────────────────────────────────────

func _update_buy_button() -> void:
	var can_buy := false
	if selected_cell != null and is_instance_valid(selected_cell):
		var is_owned : bool = selected_cell.get_meta("is_owned", true)
		var cost     : int  = int(selected_cell.get_meta("item_cost", DEFAULT_ITEM_COST))
		can_buy = not is_owned and player_cash >= cost
	buy_btn.disabled = not can_buy
	UIKit.style_button(buy_btn, "good" if can_buy else "primary")


# ─── Purchase ────────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	if selected_cell == null or not is_instance_valid(selected_cell):
		return
	var item_name : String = String(selected_cell.get_meta("item_name", ""))
	var cost      : int    = int(selected_cell.get_meta("item_cost", DEFAULT_ITEM_COST))
	if item_name == "" or player_cash < cost:
		return

	player_cash -= cost
	GameState.add_cash(-cost)
	if shop_kind == KIND_COSTUME:
		GameState.add_costume_to_collection(item_name)
	else:
		GameState.add_sleeve_to_collection(item_name)
		_owned_items[item_name] = true
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	_show_purchase_display(item_name)


## The reveal. Same overlay furniture as the Coin Shop's, but the item fades up from black
## instead of flipping — neither a card back nor a costume has a back to flip from.
func _show_purchase_display(item_name: String) -> void:
	_in_purchase_seq = true
	buy_btn.disabled    = true
	cancel_btn.disabled = true

	var item_tex := _load_item_texture_full(item_name)

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

	# Item aspect-fitted into the reveal box and centred on screen
	var vp_size : Vector2 = get_viewport_rect().size
	var disp_size := REVEAL_SIZE
	if item_tex != null:
		var t_size := item_tex.get_size()
		if t_size.x > 0.0 and t_size.y > 0.0:
			var s : float = minf(REVEAL_SIZE.x / t_size.x, REVEAL_SIZE.y / t_size.y)
			disp_size = Vector2(t_size.x * s, t_size.y * s)

	# Centre the art inside the full REVEAL_SIZE box rather than on its own size, so a
	# square costume sits where a portrait sleeve does and the caption never jumps up.
	var item_pos := Vector2(
		vp_size.x / 2.0 - disp_size.x / 2.0,
		vp_size.y / 2.0 - REVEAL_SIZE.y / 2.0 - 80.0 + (REVEAL_SIZE.y - disp_size.y) / 2.0
	)
	var caption_y : float = vp_size.y / 2.0 + REVEAL_SIZE.y / 2.0 - 80.0 + 20.0

	var item_rect := TextureRect.new()
	item_rect.texture             = item_tex
	item_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	item_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	item_rect.custom_minimum_size = disp_size
	item_rect.size                = disp_size
	item_rect.position            = item_pos
	item_rect.pivot_offset        = disp_size / 2.0
	item_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(item_rect)

	# Text label below the item
	var label := Label.new()
	label.text                 = _purchase_caption(item_name)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position             = Vector2(160.0, caption_y)
	label.size                 = Vector2(1600.0, 80.0)
	label.add_theme_font_size_override("font_size", 50)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.modulate             = Color(1, 1, 1, 0)   # fades up with the item
	overlay_layer.add_child(label)

	# OK button — hidden until the fade finishes
	var ok_btn := Button.new()
	ok_btn.text     = "OK"
	ok_btn.size     = Vector2(400.0, 60.0)
	ok_btn.position = Vector2(vp_size.x / 2.0 - 200.0, label.position.y + 90.0)
	ok_btn.visible  = false
	UIKit.style_button(ok_btn, "good")
	overlay_layer.add_child(ok_btn)

	await _play_fadein(item_rect, label)
	ok_btn.visible = true
	_reveal_ok_btn = ok_btn   # _input() presses this from the keyboard

	# Wait for the player to dismiss
	await ok_btn.pressed
	_reveal_ok_btn = null
	overlay_layer.queue_free()

	# Stamp the purchased item as owned in the grid
	var purchased_cell := selected_cell
	if purchased_cell != null and is_instance_valid(purchased_cell):
		if _active_tween:
			_active_tween.kill()
			_active_tween = null
		_mark_cell_owned(purchased_cell)

	selected_cell = null
	ShopChrome.set_wallet_cash(wallet_chip, player_cash)
	# Every pill, not just the one bought: the item just purchased flips to grey OWNED and
	# anything the remaining balance no longer covers flips green -> red.
	_refresh_pills()
	cancel_btn.disabled    = false
	_in_purchase_seq       = false
	_update_buy_button()


## Costume-style reveal, from MapManager._play_costume_fadein: black up to full colour over
## the dim overlay. Duration runs through GameState.item_time so the Options screen's
## item-animation speed applies here too.
##
## The overworld version holds fully black for half a second before starting, which on a
## black dim overlay is just half a second of nothing — the item is invisible until the
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


func _purchase_caption(item_name: String) -> String:
	if shop_kind == KIND_COSTUME:
		return "You got the " + _format_item_name(item_name) + " Costume"
	return "You got the " + _format_item_name(item_name) + " Sleeve"


## Basename -> readable name. Same rule as MapManager._format_sleeve_name: swap
## underscores for spaces and keep the file's own capitalisation, so the name reads as it
## does in the sleeve/costume menu ("Oricorio_Pink" -> "Oricorio Pink").
func _format_item_name(raw: String) -> String:
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
