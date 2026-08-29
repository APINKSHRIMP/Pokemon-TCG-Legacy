class_name ShopChrome
extends RefCounted

# ============================================================
# SHOP CHROME — THE WALLET CHIP AND THE ITEM PRICE PILLS
# ============================================================
# One place where every shop screen gets its money furniture, so the five of them
# (Coin, Cosmetic, Holo Rare, Pack Purchase, Bulk Sell) cannot drift apart again.
#
# WHAT IT REPLACES. Each shop used to hand-place four Labels at font size 61 — the
# same size as the screen's H1 — in an 850 x 146 block bottom-right:
#
#       Your money:   1250
#       Sleeve cost:   400
#
# The words were most of the pixels and none of the information, and the block
# reserved a 190px band across the bottom that the item grid could never use. Both
# rows are gone. Cash lives in a pill on the header border; the price lives ON the
# thing it is the price of.
#
# EVERYTHING HERE IS DRAWN WITH Rounded_Message_Panel.gdshader — the same shader the
# overworld message box draws its chip row with (Dynamic_Message_Box._build_chip).
# That is deliberate: the cash pill the player is looking at while the shopkeeper
# talks is the same object that greets them inside the shop. If you restyle chips
# there, restyle them here too.
#
# THE FOUR PILL STATES
#   AFFORDABLE   green   "$50"      player can buy it
#   UNAFFORDABLE red     "$100"     player cannot
#   OWNED        grey    "OWNED"    already in the collection
#   DISCOUNTED   gold    "$50"      sale price actually charged
#
# `old_price` is ORTHOGONAL to the state. Pass a non-zero one and a smaller grey pill
# with a red line through the old figure stacks directly above the main pill,
# whatever colour that main pill is. So a discounted pack the player cannot afford
# shows RED over the struck-out grey — the affordability signal is never traded away
# for the sale colour.
#
# SIZING. Pills scale off the cell's SHORT edge rather than being fixed, because the
# items differ enormously: a coin is 200x200 and numerous, a booster pack is nearly
# 400 wide. Font size, padding, corner radius and the stack gap are all ratios of the
# resulting pill height, so one number (PILL_HEIGHT_RATIO) moves the whole thing.
#
# PILLS ARE NOT CHILDREN OF THE ITEMS. They live on one flat layer per shop
# (add_pill_layer), so the selection tween can scale an item without dragging its price
# around with it, and so a pill outranks the sparkle emitters in draw order. See
# add_pill_layer for the full reasoning and the resting-state rule add_price_pill needs.
# ============================================================


const SHADER_PATH := "res://Scripts/Shaders/Rounded_Message_Panel.gdshader"
const FONT_PATH   := "res://UI_Themes/kenvector_future.ttf"
const CASH_ICON   := "res://Image_Assets/Icons/Reward_Icons/pokedollar_icon.png"

const SCREEN_W : float = 1920.0

## Pill states. `old_price` is passed separately and stacks a struck-out pill above
## the main one regardless of which of these is in play.
enum { AFFORDABLE, UNAFFORDABLE, OWNED, DISCOUNTED }


# ─── TWEAKABLE: wallet chip (top right, on the header border) ─────────────────

const WALLET_H          : float = 54.0    # pill height
const WALLET_CENTRE_Y   : float = 53.0    # pill's vertical centre, screen px
const WALLET_MARGIN_R   : float = 30.0    # pill's right edge, in from the screen edge
const WALLET_FONT_SIZE  : int   = 30
const WALLET_PAD_L      : float = 12.0    # pill's left edge -> icon
const WALLET_GAP        : float = 6.0     # icon -> digits
const WALLET_PAD_R      : float = 24.0    # digits -> pill's right edge
const WALLET_ICON_H     : float = 42.0    # icon is drawn at this height, aspect kept
const WALLET_Z          : int   = 1000    # above the header label (999) and border (200)
const WALLET_COL_L      := Color(0.15, 0.42, 0.85)
const WALLET_COL_R      := Color(0.24, 0.58, 0.96)
const WALLET_TEXT_COL   := Color(1, 1, 1, 1)
## Seconds the figure takes to count from the old balance to the new one after a
## purchase. 0.0 snaps instantly. Slowed 25% from 0.45 so the decrement is easier to watch.
const WALLET_COUNT_TIME : float = 0.56


# ─── TWEAKABLE: item price pills ─────────────────────────────────────────────

## Pill height as a fraction of the cell's SHORT edge, then clamped. This is the one
## number to reach for if pills feel too big or too small across the board.
const PILL_HEIGHT_RATIO : float = 0.17
const PILL_MIN_H        : float = 28.0
const PILL_MAX_H        : float = 60.0

## Everything below is a ratio OF THE PILL HEIGHT, so a pill stays in proportion at
## any size rather than needing a second set of numbers per shop.
const PILL_FONT_RATIO   : float = 0.52   # font size
const PILL_PAD_RATIO    : float = 0.46   # padding each side of the text
const PILL_STACK_GAP    : float = 0.10   # gap between the "was" pill and the main one
const PILL_OLD_SCALE    : float = 0.86   # the "was" pill is this much of the main one

## How far the pill breaks out of the cell it belongs to. X is a fraction of the pill's
## WIDTH past the cell's right edge; Y a fraction of its HEIGHT below the cell's bottom.
## Both small on purpose — the pill should read as sitting ON the item, not beside it.
const PILL_OVERHANG_X   : float = 0.25
const PILL_OVERHANG_Y   : float = 0.15

## z_index of the whole pill layer. Must clear every sparkle emitter in the shops, which is
## what sets the floor: the Coin Shop's selection sparkle sits at 50 and the Holo Rare
## shop's at 5. The stack the player sees, back to front, is
##     item  <  glitter  <  price pill
## Kept below the screen borders (200) and the wallet chip (1000), neither of which the
## pills ever reach.
const PILL_LAYER_Z      : int = 60

const PILL_TEXT_COL     := Color(1, 1, 1, 1)
const PILL_SHADOW_COL   := Color(0, 0, 0, 0.55)
const PILL_SHADOW_OFF   : int = 2
## How much lighter the right-hand end of a pill is than its left, matching the soft
## horizontal gradient the message box gives its chips.
const PILL_GRADIENT_LIFT : float = 0.10

const COL_AFFORDABLE   := Color(0.09, 0.66, 0.31)
const COL_UNAFFORDABLE := Color(0.87, 0.11, 0.11)
const COL_OWNED        := Color(0.42, 0.42, 0.44)
const COL_DISCOUNT     := Color(0.95, 0.68, 0.06)
const COL_OLD_PRICE    := Color(0.42, 0.42, 0.44)

## The line through the old price. Thickness is a ratio of the "was" pill's height.
const STRIKE_COL          := Color(0.90, 0.08, 0.08)
const STRIKE_THICK_RATIO  : float = 0.11
const STRIKE_OVERHANG     : float = 5.0

const PILL_LAYER_NAME := "ShopChromePills"


# ============================================================
# WALLET CHIP
# ============================================================

## Adds the cash pill to `parent` (normally the shop's root Control) and returns it.
## Call set_wallet_cash() on the returned node whenever the balance moves.
static func add_wallet_chip(parent: Node, cash: int) -> Control:
	var holder := Control.new()
	holder.name         = "WalletChip"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index      = WALLET_Z
	parent.add_child(holder)

	var pill := _make_pill(Vector2(WALLET_H, WALLET_H), WALLET_COL_L, WALLET_COL_R)
	pill.name = "pill"
	holder.add_child(pill)

	var icon := TextureRect.new()
	icon.name           = "icon"
	icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode   = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(CASH_ICON):
		icon.texture = load(CASH_ICON)
	holder.add_child(icon)

	var label := _make_label("", WALLET_FONT_SIZE, WALLET_TEXT_COL)
	label.name                 = "amount"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	holder.add_child(label)

	holder.set_meta("shown_cash", cash)
	_layout_wallet(holder, cash)
	return holder


## Updates the pill. With `animate` the figure counts up (or down) to the new balance
## over WALLET_COUNT_TIME rather than jumping, so a purchase reads as money leaving.
static func set_wallet_cash(chip: Control, cash: int, animate: bool = true) -> void:
	if chip == null or not is_instance_valid(chip):
		return
	var from : int = int(chip.get_meta("shown_cash", cash))
	chip.set_meta("shown_cash", cash)
	if not animate or WALLET_COUNT_TIME <= 0.0 or from == cash:
		_layout_wallet(chip, cash)
		return
	# Counting is done by re-laying out on every step, so the pill grows and shrinks
	# with the number instead of snapping to its final width at the end.
	var tw := chip.create_tween()
	tw.tween_method(
		func(v: float) -> void: _layout_wallet(chip, int(round(v))),
		float(from), float(cash), WALLET_COUNT_TIME
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Sizes the pill to whatever the figure currently is and pins its RIGHT edge, so the
## chip grows leftwards and never drifts away from the screen edge.
static func _layout_wallet(chip: Control, cash: int) -> void:
	var pill  : ColorRect   = chip.get_node_or_null("pill")
	var icon  : TextureRect = chip.get_node_or_null("icon")
	var label : Label       = chip.get_node_or_null("amount")
	if pill == null or label == null:
		return

	label.text = "$" + str(cash)
	var text_w := _text_width(label.text, WALLET_FONT_SIZE)

	var icon_w := 0.0
	if icon != null and icon.texture != null:
		var tex_size := icon.texture.get_size()
		if tex_size.y > 0.0:
			icon_w = tex_size.x * (WALLET_ICON_H / tex_size.y)

	var pill_w := WALLET_PAD_L + icon_w + WALLET_GAP + text_w + WALLET_PAD_R
	var left   := SCREEN_W - WALLET_MARGIN_R - pill_w
	var top    := WALLET_CENTRE_Y - WALLET_H * 0.5

	pill.position = Vector2(left, top)
	_resize_pill(pill, Vector2(pill_w, WALLET_H))

	if icon != null:
		icon.size     = Vector2(icon_w, WALLET_ICON_H)
		icon.position = Vector2(left + WALLET_PAD_L, WALLET_CENTRE_Y - WALLET_ICON_H * 0.5)

	label.size     = Vector2(text_w, WALLET_H)
	label.position = Vector2(left + WALLET_PAD_L + icon_w + WALLET_GAP, top)


# ============================================================
# ITEM PRICE PILLS
# ============================================================

## The layer every price pill is drawn on. Pills live HERE and not inside the item cells,
## for two reasons:
##
##   1. The selection tween scales the item. A pill parented to it would be scaled too —
##      the item has to grow and shrink BEHIND a price that stays put.
##   2. The sparkle emitters are added to the shop root at z 50 (Coin) and z 5 (Holo). A
##      pill nested inside a cell can only reach z 3-ish, so the glitter drew over it.
##
## Size is irrelevant: children of a Control draw outside its rect unless it clips, and
## nothing here clips. Add it once in _ready() and keep the reference.
static func add_pill_layer(parent: Node) -> Control:
	var layer := Control.new()
	layer.name         = PILL_LAYER_NAME
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index      = PILL_LAYER_Z
	layer.position     = Vector2.ZERO
	parent.add_child(layer)
	return layer


## Drops every pill on the layer. The shops rebuild the whole set at once, so this plus a
## loop of add_price_pill() is the entire refresh.
static func clear_pills(layer: Control) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	for child in layer.get_children():
		layer.remove_child(child)
		child.queue_free()


## Draws one price pill anchored to the bottom-right of `anchor`.
##
## `anchor` is the box the pill hangs off, in GLOBAL screen coordinates. Pass the box the
## ART actually paints, not the control's rect: an aspect-fitted TextureRect is letterboxed
## inside its control, and anchoring to the control would float the pill out in the margin.
##
## CALL THIS ONLY WHILE THE ITEM IS AT REST (scale 1). The anchor is read from the item's
## live global rect, so refreshing mid-pulse would bake the pulsed position in. Every shop's
## _refresh_pills() runs after selection has been cleared, which guarantees it.
##
## `old_price` > 0 stacks a smaller grey pill with a red line through it directly
## above the main pill. It is independent of `state`, so an unaffordable sale item
## still shows red on top of the struck-out original.
static func add_price_pill(layer: Control, anchor: Rect2, state: int,
						   price: int, old_price: int = 0) -> void:
	if layer == null or not is_instance_valid(layer):
		return

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)

	# Global -> layer-local. The layer is unscaled and normally sits at the origin, but going
	# through the transform keeps this honest if a shop ever parents it somewhere else.
	var origin : Vector2 = layer.get_global_transform().affine_inverse() * anchor.position
	var cell_origin : Vector2 = origin
	var cell_size   : Vector2 = anchor.size

	var h         : float = clampf(minf(cell_size.x, cell_size.y) * PILL_HEIGHT_RATIO,
								   PILL_MIN_H, PILL_MAX_H)
	var font_size : int   = maxi(int(round(h * PILL_FONT_RATIO)), 8)
	var pad       : float = h * PILL_PAD_RATIO

	var main_col  : Color
	var main_text : String
	match state:
		OWNED:
			main_col  = COL_OWNED
			main_text = "OWNED"
		UNAFFORDABLE:
			main_col  = COL_UNAFFORDABLE
			main_text = "$" + str(price)
		DISCOUNTED:
			main_col  = COL_DISCOUNT
			main_text = "$" + str(price)
		_:
			main_col  = COL_AFFORDABLE
			main_text = "$" + str(price)

	# ── Main pill. Right edge overhangs the cell; bottom edge dips just below it.
	var main_w : float = _text_width(main_text, font_size) + pad * 2.0
	var main_x : float = cell_origin.x + cell_size.x + main_w * PILL_OVERHANG_X - main_w
	var main_y : float = cell_origin.y + cell_size.y + h * PILL_OVERHANG_Y - h
	_add_pill_row(holder, Vector2(main_x, main_y), Vector2(main_w, h),
				  main_col, main_text, font_size, false)

	# ── "Was" pill, stacked directly above and right-aligned with the main one.
	if old_price > 0:
		var old_h    : float  = h * PILL_OLD_SCALE
		var old_font : int    = maxi(int(round(old_h * PILL_FONT_RATIO)), 8)
		var old_text : String = "$" + str(old_price)
		var old_w    : float  = _text_width(old_text, old_font) + old_h * PILL_PAD_RATIO * 2.0
		var old_x    : float  = main_x + main_w - old_w
		var old_y    : float  = main_y - h * PILL_STACK_GAP - old_h
		_add_pill_row(holder, Vector2(old_x, old_y), Vector2(old_w, old_h),
					  COL_OLD_PRICE, old_text, old_font, true)


## One pill: the rounded rect, its centred label, and — when `strike` — a red bar across
## the digits. The bar is sized to the TEXT, not the pill, so it crosses the number
## rather than running the full width of the padding.
static func _add_pill_row(holder: Control, pos: Vector2, size: Vector2, col: Color,
						  text: String, font_size: int, strike: bool) -> void:
	var pill := _make_pill(size, col, col.lerp(Color.WHITE, PILL_GRADIENT_LIFT))
	pill.position = pos
	holder.add_child(pill)

	var label := _make_label(text, font_size, PILL_TEXT_COL)
	label.position = pos
	label.size     = size
	holder.add_child(label)

	if strike:
		var text_w := _text_width(text, font_size)
		var thick  := maxf(size.y * STRIKE_THICK_RATIO, 2.0)
		var bar := ColorRect.new()
		bar.color        = STRIKE_COL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size     = Vector2(text_w + STRIKE_OVERHANG * 2.0, thick)
		bar.position = Vector2(
			pos.x + (size.x - text_w) * 0.5 - STRIKE_OVERHANG,
			pos.y + (size.y - thick) * 0.5
		)
		holder.add_child(bar)


# ============================================================
# SHARED DRAWING HELPERS
# ============================================================

## A pill is Rounded_Message_Panel.gdshader with its edge falloff pushed past the far
## edge, so the whole rect stays solid colour — exactly how the message box builds a
## chip. Every rect needs its OWN ShaderMaterial: the uniforms are per-rect.
static func _make_pill(size: Vector2, col_l: Color, col_r: Color) -> ColorRect:
	var rect := ColorRect.new()
	var mat  := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	rect.material     = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize_pill(rect, size)
	mat.set_shader_parameter("color_left",  col_l)
	mat.set_shader_parameter("color_right", col_r)
	mat.set_shader_parameter("fill_color",  col_l)
	mat.set_shader_parameter("edge_solid",  Vector2(9999.0, 9999.0))
	mat.set_shader_parameter("edge_fade",   Vector2(1.0, 1.0))
	return rect


## The shader works in pixels, so rect_size and the corner radius have to be pushed
## every time the rect changes size or the pill stretches instead of staying round.
static func _resize_pill(rect: ColorRect, size: Vector2) -> void:
	rect.size = size
	var mat: ShaderMaterial = rect.material
	if mat == null:
		return
	mat.set_shader_parameter("rect_size",     size)
	mat.set_shader_parameter("corner_radius", size.y * 0.5)


static func _make_label(text: String, font_size: int, col: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_shadow_color", PILL_SHADOW_COL)
	label.add_theme_constant_override("shadow_offset_x", PILL_SHADOW_OFF)
	label.add_theme_constant_override("shadow_offset_y", PILL_SHADOW_OFF)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	return label


static func _font() -> Font:
	return load(FONT_PATH) as Font


static func _text_width(text: String, font_size: int) -> float:
	var font := _font()
	if font == null:
		return float(text.length() * font_size)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
