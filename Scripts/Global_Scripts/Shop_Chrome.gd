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
## The UI face. Read through UITheme so the pills match every other chip.
##
## NOTE THIS FORKS FROM THE OVERWORLD MESSAGE BOX. The pills and DynamicMessageBox's
## chip row used to be deliberately identical — same shader, same font, same palette — so
## the cash chip a shopkeeper shows you is the object you then see inside the shop. The UI
## overhaul kept the OVERWORLD box on its per-NPC colours (each speaker carries its own
## `message_colour`) while the shops moved to the theme, so the two now differ on purpose.
## Restyling one no longer obliges you to restyle the other.
static func _font_path() -> String:
	return UITheme.FONT_UI_BOLD
const CASH_ICON   := "res://Image_Assets/Icons/Reward_Icons/pokedollar_icon.png"
const FISH_COIN_ICON := "res://Image_Assets/Icons/Reward_Icons/FishCoin.png"

const SCREEN_W : float = 1920.0

## Pill states. `old_price` is passed separately and stacks a struck-out pill above
## the main one regardless of which of these is in play.
enum { AFFORDABLE, UNAFFORDABLE, OWNED, DISCOUNTED }


# ─── TWEAKABLE: wallet chip (top right, on the header border) ─────────────────

const WALLET_H          : float = 54.0    # pill height
const WALLET_CENTRE_Y   : float = 46.0    # pill's vertical centre = the 92px header's midline
const WALLET_MARGIN_R   : float = 30.0    # pill's right edge, in from the screen edge
const WALLET_FONT_SIZE  : int   = 30
const WALLET_PAD_L      : float = 12.0    # pill's left edge -> icon
const WALLET_GAP        : float = 6.0     # icon -> digits
const WALLET_PAD_R      : float = 24.0    # digits -> pill's right edge
const WALLET_ICON_H     : float = 42.0    # icon is drawn at this height, aspect kept
const WALLET_Z          : int   = 1000    # above the header label (999) and border (200)
## Translucent white, matching UIKit.make_chip("on_chrome") — the wallet sits ON the
## header gradient, where a solid fill would fight it.
const WALLET_COL_L      := Color(1.0, 1.0, 1.0, 0.14)
const WALLET_COL_R      := Color(1.0, 1.0, 1.0, 0.18)
const WALLET_TEXT_COL   := Color(1, 1, 1, 1)
## Seconds the figure takes to count from the old balance to the new one after a
## purchase. 0.0 snaps instantly. Slowed 25% from 0.45 so the decrement is easier to watch.
const WALLET_COUNT_TIME : float = 0.56
## Gap between the cash chip and a second chip (the Fish Shop's Fish Coins) to its left.
const WALLET_PAIR_GAP   : float = 14.0


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
const PILL_ICON_RATIO   : float = 0.72   # Fish Coin icon height on a two-currency pill
const PILL_ICON_GAP_RATIO : float = 0.18 # gap either side of that icon

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

## The four pill states, from the theme. Affordability must never lose to the sale
## colour — see add_price_pill, where `old_price` stacks a struck-out pill ABOVE whatever
## colour the main one is.
static func _col_affordable() -> Color:   return UITheme.col("good")
static func _col_unaffordable() -> Color: return UITheme.col("danger")
static func _col_owned() -> Color:        return UITheme.col("field_mute").darkened(0.45)
static func _col_discount() -> Color:     return UITheme.col("warn")
static func _col_old_price() -> Color:    return UITheme.col("field_mute").darkened(0.45)

## The line through the old price. Thickness is a ratio of the "was" pill's height.
static func _strike_col() -> Color: return UITheme.col("danger")
const STRIKE_THICK_RATIO  : float = 0.11
const STRIKE_OVERHANG     : float = 5.0

const PILL_LAYER_NAME := "ShopChromePills"


# ============================================================
# WALLET CHIP
# ============================================================

## Adds the cash pill to `parent` (normally the shop's root Control) and returns it.
## Call set_wallet_cash() on the returned node whenever the balance moves.
##
## `icon_path` / `prefix` make the same chip show another currency; see
## add_fish_coin_chip(), the only other caller.
static func add_wallet_chip(parent: Node, cash: int, icon_path: String = CASH_ICON,
		prefix: String = "$") -> Control:
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
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	# The Fish Coin art is 170 px drawn at 42: nearest filtering would shred it. The
	# pokédollar is pixel art at roughly its drawn size and keeps nearest.
	if icon_path != CASH_ICON:
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	holder.add_child(icon)

	var label := _make_label("", WALLET_FONT_SIZE, WALLET_TEXT_COL)
	label.name                 = "amount"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	holder.add_child(label)

	holder.set_meta("shown_cash", cash)
	holder.set_meta("prefix", prefix)
	_layout_wallet(holder, cash)
	return holder


## The Fish Shop's second chip: Fish Coins, sat immediately LEFT of `wallet` (the cash
## chip) and kept there as the cash figure grows and shrinks. Update it with
## set_wallet_cash() like any wallet chip.
static func add_fish_coin_chip(parent: Node, fish_coins: int, wallet: Control) -> Control:
	var chip := add_wallet_chip(parent, fish_coins, FISH_COIN_ICON, "")
	if wallet != null and is_instance_valid(wallet):
		chip.set_meta("follows", wallet)
		wallet.set_meta("follower", chip)
		_layout_wallet(chip, fish_coins)
	return chip


## ISSUE #208: THE CHIP'S OWN RECT IS EMPTY - ASK FOR THE PILL'S.
##
## add_wallet_chip returns a bare holder Control that is never sized or
## positioned: the pill, the icon and the figure are children placed at absolute
## coordinates inside it, so the holder's rect stays (0,0) 0x0 forever. Anything
## that called get_global_rect() on the chip - the bulk-sell payout label did, for
## three retests - got an empty rect, failed its own sanity check and silently
## fell back to a hardcoded number, which is exactly why moving the label "did
## nothing" every time. This returns the rect that is actually on screen.
##
## Returns an empty Rect2 if the pill has not been laid out yet.
static func wallet_pill_rect(chip: Control) -> Rect2:
	if chip == null or not is_instance_valid(chip):
		return Rect2()
	var pill: ColorRect = chip.get_node_or_null("pill")
	if pill == null or pill.size.x <= 1.0:
		return Rect2()
	return Rect2(pill.global_position, pill.size)


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

	chip.set_meta("laid_out", cash)
	label.text = String(chip.get_meta("prefix", "$")) + str(cash)
	var text_w := _text_width(label.text, WALLET_FONT_SIZE)

	var icon_w := 0.0
	if icon != null and icon.texture != null:
		var tex_size := icon.texture.get_size()
		if tex_size.y > 0.0:
			icon_w = tex_size.x * (WALLET_ICON_H / tex_size.y)

	var pill_w := WALLET_PAD_L + icon_w + WALLET_GAP + text_w + WALLET_PAD_R
	# A chip that follows another ends where that one's pill starts, less the gap.
	var right  := SCREEN_W - WALLET_MARGIN_R
	var leader = chip.get_meta("follows") if chip.has_meta("follows") else null
	if leader is Control and is_instance_valid(leader):
		var lead_rect := wallet_pill_rect(leader)
		if lead_rect.size.x > 1.0:
			right = lead_rect.position.x - WALLET_PAIR_GAP
	var left   := right - pill_w
	var top    := WALLET_CENTRE_Y - WALLET_H * 0.5

	pill.position = Vector2(left, top)
	_resize_pill(pill, Vector2(pill_w, WALLET_H))

	if icon != null:
		icon.size     = Vector2(icon_w, WALLET_ICON_H)
		icon.position = Vector2(left + WALLET_PAD_L, WALLET_CENTRE_Y - WALLET_ICON_H * 0.5)

	label.size     = Vector2(text_w, WALLET_H)
	label.position = Vector2(left + WALLET_PAD_L + icon_w + WALLET_GAP, top)

	# This chip moved or resized: drag the one pinned to its left along with it.
	var follower = chip.get_meta("follower") if chip.has_meta("follower") else null
	if follower is Control and is_instance_valid(follower):
		_layout_wallet(follower, int(follower.get_meta("laid_out", 0)))


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
##
## `fish_price` > 0 (the Fish Shop) makes the main pill carry both prices -- "$500" then
## the Fish Coin icon and "50" -- in the one state colour, which then means "can afford
## BOTH". OWNED ignores it.
static func add_price_pill(layer: Control, anchor: Rect2, state: int,
						   price: int, old_price: int = 0, fish_price: int = 0) -> void:
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
			main_col  = _col_owned()
			main_text = "OWNED"
		UNAFFORDABLE:
			main_col  = _col_unaffordable()
			main_text = "$" + str(price)
		DISCOUNTED:
			main_col  = _col_discount()
			main_text = "$" + str(price)
		_:
			main_col  = _col_affordable()
			main_text = "$" + str(price)

	# ── Main pill. Right edge overhangs the cell; bottom edge dips just below it.
	if fish_price > 0 and state != OWNED:
		var fish_text := str(fish_price)
		var icon_h    := h * PILL_ICON_RATIO
		var icon_w    := _fish_icon_width(icon_h)
		var gap       := h * PILL_ICON_GAP_RATIO
		var dual_w : float = _text_width(main_text, font_size) + gap * 2.0 + icon_w \
				+ _text_width(fish_text, font_size) + pad * 2.0
		var dual_x : float = cell_origin.x + cell_size.x + dual_w * PILL_OVERHANG_X - dual_w
		var dual_y : float = cell_origin.y + cell_size.y + h * PILL_OVERHANG_Y - h
		_add_dual_pill_row(holder, Vector2(dual_x, dual_y), Vector2(dual_w, h), main_col,
				main_text, fish_text, font_size, pad, gap, icon_h)
		return

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
					  _col_old_price(), old_text, old_font, true)


## A two-currency pill: "$500  [fish coin] 50". One rect, two labels and the icon, laid
## left to right with `pad` at each end and `gap` either side of the icon.
static func _add_dual_pill_row(holder: Control, pos: Vector2, size: Vector2, col: Color,
							   cash_text: String, fish_text: String, font_size: int,
							   pad: float, gap: float, icon_h: float) -> void:
	var pill := _make_pill(size, col, col.lerp(Color.WHITE, PILL_GRADIENT_LIFT))
	pill.position = pos
	holder.add_child(pill)

	var x := pos.x + pad
	var cash_w := _text_width(cash_text, font_size)
	var cash := _make_label(cash_text, font_size, PILL_TEXT_COL)
	cash.position = Vector2(x, pos.y)
	cash.size     = Vector2(cash_w, size.y)
	holder.add_child(cash)
	x += cash_w + gap

	var icon_w := _fish_icon_width(icon_h)
	if icon_w > 0.0:
		var icon := TextureRect.new()
		icon.texture        = load(FISH_COIN_ICON)
		icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode   = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		icon.size     = Vector2(icon_w, icon_h)
		icon.position = Vector2(x, pos.y + (size.y - icon_h) * 0.5)
		holder.add_child(icon)
	x += icon_w + gap

	var fish := _make_label(fish_text, font_size, PILL_TEXT_COL)
	fish.position = Vector2(x, pos.y)
	fish.size     = Vector2(_text_width(fish_text, font_size), size.y)
	holder.add_child(fish)


static func _fish_icon_width(icon_h: float) -> float:
	if not ResourceLoader.exists(FISH_COIN_ICON):
		return 0.0
	var tex: Texture2D = load(FISH_COIN_ICON)
	if tex == null or tex.get_height() <= 0:
		return 0.0
	return icon_h * tex.get_width() / float(tex.get_height())


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
		bar.color        = _strike_col()
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
	return load(_font_path()) as Font


static func _text_width(text: String, font_size: int) -> float:
	var font := _font()
	if font == null:
		return float(text.length() * font_size)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
