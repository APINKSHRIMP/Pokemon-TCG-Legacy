extends Control

# ============================================================
# CARD BUYER — BULK SELL SHOP
# ============================================================
# The Gym Plaza Card Buyer's full screen. Buys every copy of a card the player owns
# BEYOND the fourth, which is the most any legal deck can hold — so nothing sellable
# here can ever be a card the player still needs.
#
# TWO SCREENS in one Control, toggled by _show_home() / _show_list():
#
#   HOME  — three fanned card groups (commons / uncommons / rares), the per-card price
#           under each, a button per rarity plus a "sell all", and the player's cash.
#           Chrome is the standard shop look: horizontal top and bottom borders over a
#           scrolling background.
#
#   LIST  — every spare copy the chosen button covers, laid out exactly as the deck
#           builder's "view deck" screen lays out a deck: same 9-column grid, same card
#           size, same right-hand INDIVIDUAL / CATEGORIES bar, same top-and-right border
#           chrome. The ordering and the bar both come from CardViewerList, which the
#           deck viewer also uses, so the two screens cannot drift apart.
#
# THE ECONOMY, for context (the user's figures): a base1 pack costs $150 and contains
# 6 commons + 3 uncommons + 1 rare, which sells back for 6*5 + 3*10 + 25 = $85. Even a
# pack that rolls its 25% bonus rare only returns $110. Selling bulk is always a loss
# against buying packs, which is the point — it is a way to turn dead duplicates into
# some cash, not an income source.
# ============================================================


# ─── Constants ───────────────────────────────────────────────────────────────

const GYM_PLAZA := "res://Scenes/Map_Scenes/Gym_Plaza.tscn"
const CARD_SET_FOLDER := "res://Card_Set_Data/"
const CARD_IMAGE_FOLDER := "res://Image_Assets/Card_Image_Library/"

## Copies of any one card the player always keeps. Four is the deck-building cap, so
## everything above it is genuinely spare.
const KEEP_PER_CARD := 4

## TWEAKABLE — what the Card Buyer pays per card, by rarity band.
const PRICE_COMMON   := 5
const PRICE_UNCOMMON := 10
const PRICE_RARE     := 25

# Rarity bands. BAND_NONE is "he won't buy it" — see _band_for_card().
const BAND_NONE      := -1
const BAND_COMMON    := 0
const BAND_UNCOMMON  := 1
const BAND_RARE      := 2
const BAND_ALL       := 3   # the "sell all spare bulk" button, not a real band

const BAND_PRICE := {
	BAND_COMMON:   PRICE_COMMON,
	BAND_UNCOMMON: PRICE_UNCOMMON,
	BAND_RARE:     PRICE_RARE,
}

## Word used in the sell screen's header, per band. BAND_ALL has none by design —
## "Selling 96 Cards For $640" reads better than inventing a word for "everything".
const BAND_WORD := {
	BAND_COMMON:   "Common",
	BAND_UNCOMMON: "Uncommon",
	BAND_RARE:     "Rare",
	BAND_ALL:      "",
}

# ── Home screen card fans ────────────────────────────────────────────────────
# TWEAKABLE. Three groups of three overlapping cards, one group per rarity band, in a
# fixed Fire / Grass / Water order left to right so all three read the same way. The
# left card is tilted anticlockwise, the right one clockwise, the middle one square,
# and the stacking runs left-over-middle-over-right in every group.
const FAN_CARD_SIZE  := Vector2(300, 416)
const FAN_X_STEP     := 145.0     # horizontal gap between one card's left edge and the next
const FAN_TOP_Y      := 190.0
const FAN_CENTERS    := [340.0, 960.0, 1580.0]   # x centre of each group
const FAN_TILT_DEG   := 7.0       # left card gets -this, right card +this, middle 0

## Fire / Grass / Water, in band order. Base Set starters only — the whole point of
## the picture is that they read instantly as "commons / uncommons / rares".
const FAN_CARDS := [
	["base1-46", "base1-44", "base1-63"],   # Charmander  Bulbasaur  Squirtle
	["base1-24", "base1-30", "base1-42"],   # Charmeleon  Ivysaur    Wartortle
	["base1-4",  "base1-15", "base1-2"],    # Charizard   Venusaur   Blastoise
]

# ── Sell list screen ─────────────────────────────────────────────────────────
# Matched to the deck viewer's geometry on purpose (Deck_Build_And_Card_View_Script.gd,
# _on_view_deck_pressed) so the two screens are indistinguishable.
const LIST_CARD_SIZE   := Vector2(183, 254)
const LIST_COLUMNS     := 9
const LIST_H_SEP       := 2
const LIST_V_SEP       := 2
const LIST_SCROLL_POS  := Vector2(5, 110)
const LIST_SCROLL_SIZE := Vector2(1676, 969)
## The side list stops higher than the deck viewer's 990 because this screen stacks TWO
## buttons under it (sell + cancel) where the viewer has only Close.
const LIST_SIDE_BOTTOM := 930.0
## Cards added to the grid between frames. The deck viewer adds one per frame, which is
## fine for 60 cards and far too slow for a 400-card bulk sale — a row at a time keeps
## the progressive fill without the wait.
const LIST_BUILD_BATCH := 9

# ── Sale animation ───────────────────────────────────────────────────────────
# TWEAKABLE. Cards vanish one at a time from the bottom-right of the grid, walking right
# to left and bottom to top, each one throwing a floating price label as it goes.
const VANISH_STAGGER   := 0.05    # delay between one card starting to vanish and the next
const VANISH_TIME      := 0.28    # how long a single card takes to shrink away
const SCROLL_MARGIN    := 20.0    # px of clearance when scrolling the next card into view
const SALE_SFX_EVERY   := 4       # play the tick SFX on every Nth card, not all of them

# ── Floating rainbow labels ──────────────────────────────────────────────────
# Same trick as the pack opener's "Bonus!" label: a RichTextLabel purely for BBCode's
# [rainbow], which offsets the hue per character and advances it every frame.
const FLOAT_RAINBOW_FREQ := 1.0
const FLOAT_RAINBOW_SAT  := 0.9
const FLOAT_RAINBOW_VAL  := 1.0
const FLOAT_EMBOLDEN     := 0.6

const CARD_LABEL_FONT      := 40
const CARD_LABEL_OUTLINE   := 6
const CARD_LABEL_SIZE      := Vector2(240, 70)
const CARD_LABEL_RISE_PX   := 70.0
const CARD_LABEL_RISE_TIME := 0.85
const CARD_LABEL_FADE_TIME := 0.7

const TOTAL_LABEL_FONT      := 96
const TOTAL_LABEL_OUTLINE   := 10
const TOTAL_LABEL_SIZE      := Vector2(700, 150)
const TOTAL_LABEL_RISE_PX   := 120.0
const TOTAL_LABEL_RISE_TIME := 2.0
const TOTAL_LABEL_FADE_TIME := 1.8
## Where the payout label starts, as the centre of its box. Sits over the money readout
## in the bottom right so the figure and the number it changes are in the same place.
const TOTAL_LABEL_ANCHOR := Vector2(1520, 940)


# ─── State ───────────────────────────────────────────────────────────────────

## card_id -> { "count": int, "band": int } for every card the player owns more than
## KEEP_PER_CARD of and the buyer will take. Rebuilt from disk after every sale.
var _spares : Dictionary = {}

## Card metadata cache, card_id -> {name, supertype, subtypes, types, evolvesFrom, rarity}.
## Plus a "<set_id>-loaded" marker per set. Private to this screen; the deck builder keeps
## its own because it stores extra fields the search screen needs.
var _meta_cache : Dictionary = {}

## Texture cache for the sell grid — a 400-card sale is only ~100 distinct images.
var _texture_cache : Dictionary = {}

var _bold_font : FontVariation = null

# Sell list screen
var _list_band      : int        = BAND_ALL
var _selection      : Dictionary = {}   # card_id -> count being sold
var _selection_value: int        = 0
var _list_overlay   : Control       = null
var _list_scroll    : ScrollContainer = null
var _list_grid      : GridContainer   = null
var _float_layer    : Control         = null

var _on_list_screen : bool = false
var _selling        : bool = false      # a sale animation is running; all input is dead

# Hold-Shift card preview, mirrored from the deck builder so this grid behaves like that
# one. See _refresh_hover_preview().
var _zoom_held    : bool            = false
var _is_zoomed    : bool            = false
var _zoom_overlay : CanvasLayer     = null
var _zoomed_card  : TextureRect     = null
var _detail_panel : CardDetailPanel = null


# ─── Node references ─────────────────────────────────────────────────────────

@onready var background_scroller      : TextureRect = $BACKGROUND/background_scroller
@onready var top_border               : TextureRect = $BACKGROUND/top_border
@onready var bottom_border            : TextureRect = $BACKGROUND/bottom_border
@onready var list_border              : TextureRect = $BACKGROUND/list_border
@onready var list_background_scroller : TextureRect = $BACKGROUND/list_background_scroller

@onready var header_label : Label   = $large_header_text_label
@onready var fan_root     : Control = $"CARD FANS"
@onready var price_root   : Control = $"PRICE LABELS"

@onready var common_price_label   : Label = $"PRICE LABELS"/common_price_label
@onready var uncommon_price_label : Label = $"PRICE LABELS"/uncommon_price_label
@onready var rare_price_label     : Label = $"PRICE LABELS"/rare_price_label

@onready var home_buttons        : Control = $"HOME BUTTONS"
@onready var sell_common_btn     : Button  = $"HOME BUTTONS"/sell_common_button
@onready var sell_uncommon_btn   : Button  = $"HOME BUTTONS"/sell_uncommon_button
@onready var sell_rare_btn       : Button  = $"HOME BUTTONS"/sell_rare_button
@onready var sell_all_btn        : Button  = $"HOME BUTTONS"/sell_all_button
@onready var home_cancel_btn     : Button  = $"HOME BUTTONS"/home_cancel_button

@onready var money_root        : Control = $"MONEY LABELS"
@onready var money_amount      : Label   = $"MONEY LABELS"/your_money_amount

@onready var list_buttons    : Control = $"LIST BUTTONS"
@onready var list_sell_btn   : Button  = $"LIST BUTTONS"/list_sell_button
@onready var list_cancel_btn : Button  = $"LIST BUTTONS"/list_cancel_button


# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_SHOP_2, true)

	common_price_label.text   = "$%d p/card" % PRICE_COMMON
	uncommon_price_label.text = "$%d p/card" % PRICE_UNCOMMON
	rare_price_label.text     = "$%d p/card" % PRICE_RARE

	sell_common_btn.pressed.connect(_on_band_pressed.bind(BAND_COMMON))
	sell_uncommon_btn.pressed.connect(_on_band_pressed.bind(BAND_UNCOMMON))
	sell_rare_btn.pressed.connect(_on_band_pressed.bind(BAND_RARE))
	sell_all_btn.pressed.connect(_on_band_pressed.bind(BAND_ALL))
	home_cancel_btn.pressed.connect(_on_leave_pressed)
	list_sell_btn.pressed.connect(_on_list_sell_pressed)
	list_cancel_btn.pressed.connect(_on_list_cancel_pressed)

	# Floating labels live above everything, including the borders at z 200, and must never
	# swallow a click meant for a button underneath.
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.z_index = 400
	add_child(_float_layer)

	_scan_spares()
	_build_card_fans()
	_show_home()


# ─── Card metadata ───────────────────────────────────────────────────────────

## Loads one set's card JSON into the cache. Only the fields the sort, the side list and
## the rarity banding actually read — keeping 3,340 whole card records in memory to look
## up six strings each would be wasteful.
func _ensure_set_loaded(set_id: String) -> void:
	if _meta_cache.has(set_id + "-loaded"):
		return

	var path := CARD_SET_FOLDER + set_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("BulkSell: cannot open card metadata " + path)
		_meta_cache[set_id + "-loaded"] = true
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data is Array:
		for card in data:
			var cid : String = card.get("id", "")
			if cid == "":
				continue
			_meta_cache[cid] = {
				"name":        card.get("name", ""),
				"supertype":   card.get("supertype", ""),
				"subtypes":    card.get("subtypes", []),
				"types":       card.get("types", []),
				"evolvesFrom": card.get("evolvesFrom", ""),
				"rarity":      card.get("rarity", ""),
			}

	_meta_cache[set_id + "-loaded"] = true


## Metadata for a card_id, or null. Handed to CardViewerList as a Callable, which is how
## the shared sorting and side-list code reaches this screen's cache without owning it.
func _get_card_meta(card_id: String) -> Variant:
	if _meta_cache.has(card_id):
		return _meta_cache[card_id]
	_ensure_set_loaded(card_id.split("-")[0])
	if _meta_cache.has(card_id):
		return _meta_cache[card_id]
	return null


# ─── Rarity banding ──────────────────────────────────────────────────────────

## Which price band a card falls in, or BAND_NONE if the Card Buyer won't take it.
##
## The three bands between them cover every rarity the player can reach — they only ever
## get as far as the Gym packs, so no secret rares, ex rares or shining cards come into
## it — with two deliberate exclusions:
##
##   BASIC ENERGY has no rarity field at all in the card data (verified across every
##   gen-1 set: the only 18 cards game-wide without one are the six basic energies in
##   base1, gym1 and gym2), so it would fall out anyway. It is tested for explicitly
##   because the deck builder treats basic energy as unlimited and never spends the owned
##   count on it, which makes the owned figure meaningless — selling against it would be
##   selling nothing.
##
##   PROMOS (all 54 basep cards, rarity "Promo") are excluded by the user's decision.
##   They are gift-only — basep is not a purchasable pack — so a spare promo is a
##   keepsake, not bulk. base5's one "Rare Secret" DOES sell, at the rare price.
func _band_for_card(card_id: String) -> int:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return BAND_NONE

	if str(meta.get("supertype", "")) == "Energy" and "Basic" in meta.get("subtypes", []):
		return BAND_NONE

	var rarity := str(meta.get("rarity", ""))
	match rarity:
		"Common":   return BAND_COMMON
		"Uncommon": return BAND_UNCOMMON
		"Promo":    return BAND_NONE
		"":         return BAND_NONE
	# Rare, Rare Holo, Rare Secret and anything else above them.
	if "Rare" in rarity:
		return BAND_RARE
	return BAND_NONE


# ─── Spare scanning ──────────────────────────────────────────────────────────

## Rebuilds _spares from the owned-card files on disk. Called on entry and again after
## every sale, so the home screen's totals are never a stale copy of what was just sold.
func _scan_spares() -> void:
	_spares.clear()

	var dir := DirAccess.open(GameState.OWNED_CARDS_FOLDER)
	if dir == null:
		push_warning("BulkSell: cannot open " + GameState.OWNED_CARDS_FOLDER)
		return

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_player_owned_cards.json"):
			_scan_one_set_file(GameState.OWNED_CARDS_FOLDER + fname)
		fname = dir.get_next()
	dir.list_dir_end()

	print("BULK SELL: ", _spares.size(), " distinct cards with spare copies")


func _scan_one_set_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary and data.has("owned_cards")):
		return

	for entry in data["owned_cards"]:
		var owned : int = int(entry.get("owned", 0))
		if owned <= KEEP_PER_CARD:
			continue
		var cid : String = str(entry.get("card_id", ""))
		if cid == "":
			continue
		var band := _band_for_card(cid)
		if band == BAND_NONE:
			continue
		_spares[cid] = { "count": owned - KEEP_PER_CARD, "band": band }


## {card_id: count} for one band, or every band when `band` is BAND_ALL.
func _selection_for_band(band: int) -> Dictionary:
	var out : Dictionary = {}
	for cid in _spares:
		if band == BAND_ALL or int(_spares[cid]["band"]) == band:
			out[cid] = int(_spares[cid]["count"])
	return out


## Total cash a selection is worth, priced per card by its own band.
func _value_of(selection: Dictionary) -> int:
	var total := 0
	for cid in selection:
		var band : int = int(_spares[cid]["band"])
		total += int(BAND_PRICE.get(band, 0)) * int(selection[cid])
	return total


## Number of individual cards in a selection, not distinct card ids.
func _copies_in(selection: Dictionary) -> int:
	var n := 0
	for cid in selection:
		n += int(selection[cid])
	return n


# ─── Home screen ─────────────────────────────────────────────────────────────

## Builds the three fanned card groups. Done in code rather than the scene because the
## per-card rotation, pivot and draw order are all derived from the card's position in
## its group, and hand-writing nine rotated nodes into the .tscn invites them to drift.
func _build_card_fans() -> void:
	for group_idx in FAN_CARDS.size():
		var ids : Array = FAN_CARDS[group_idx]
		var group_w : float = FAN_CARD_SIZE.x + FAN_X_STEP * (ids.size() - 1)
		var left : float = FAN_CENTERS[group_idx] - group_w / 2.0

		for i in ids.size():
			var cid : String = ids[i]
			var rect := TextureRect.new()
			var tex := _card_texture(cid)
			if tex != null:
				rect.texture = tex
			# Forced size: EXPAND_IGNORE_SIZE plus an explicit size and custom_minimum_size,
			# so the card renders at exactly FAN_CARD_SIZE whatever the source dimensions are.
			rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.custom_minimum_size = FAN_CARD_SIZE
			rect.size                = FAN_CARD_SIZE
			rect.position            = Vector2(left + FAN_X_STEP * i, FAN_TOP_Y)
			rect.pivot_offset        = FAN_CARD_SIZE / 2.0
			# Left card leans anticlockwise, right card clockwise, middle stays square.
			if i == 0:
				rect.rotation_degrees = -FAN_TILT_DEG
			elif i == ids.size() - 1:
				rect.rotation_degrees = FAN_TILT_DEG
			# Left over middle over right, the same way in all three groups.
			rect.z_index      = ids.size() - i
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fan_root.add_child(rect)


func _show_home() -> void:
	_on_list_screen = false
	# The preview belongs to the grid that is about to go away — drop it before the chrome
	# swaps, or it would hang over the home screen with nothing behind it.
	_zoom_held = false
	_hide_zoom()

	header_label.text = "Sell Your Spare Bulk"

	background_scroller.visible      = true
	top_border.visible               = true
	bottom_border.visible            = true
	list_border.visible              = false
	list_background_scroller.visible = false

	fan_root.visible     = true
	price_root.visible   = true
	home_buttons.visible = true
	money_root.visible   = true
	list_buttons.visible = false

	if _list_overlay != null:
		_list_overlay.queue_free()
		_list_overlay = null
	_list_scroll = null
	_list_grid   = null

	_refresh_home_buttons()
	_update_money_label()


## Greys out any band the player has nothing spare in, so a button never opens an empty
## sell screen. "Sell all" is off only when all three are.
func _refresh_home_buttons() -> void:
	var has_common   := not _selection_for_band(BAND_COMMON).is_empty()
	var has_uncommon := not _selection_for_band(BAND_UNCOMMON).is_empty()
	var has_rare     := not _selection_for_band(BAND_RARE).is_empty()

	sell_common_btn.disabled   = not has_common
	sell_uncommon_btn.disabled = not has_uncommon
	sell_rare_btn.disabled     = not has_rare
	sell_all_btn.disabled      = not (has_common or has_uncommon or has_rare)


func _update_money_label() -> void:
	money_amount.text = str(GameState.get_cash())


# ─── Sell list screen ────────────────────────────────────────────────────────

func _on_band_pressed(band: int) -> void:
	if _selling or _on_list_screen:
		return
	var selection := _selection_for_band(band)
	if selection.is_empty():
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	_open_sell_list(band, selection)


func _open_sell_list(band: int, selection: Dictionary) -> void:
	_on_list_screen  = true
	_list_band       = band
	_selection       = selection
	_selection_value = _value_of(selection)

	# ── Chrome swap: shop bars out, deck-viewer top-and-right border in ──
	background_scroller.visible      = false
	top_border.visible               = false
	bottom_border.visible            = false
	list_border.visible              = true
	list_background_scroller.visible = true

	fan_root.visible     = false
	price_root.visible   = false
	home_buttons.visible = false
	money_root.visible   = false
	list_buttons.visible = true
	list_sell_btn.disabled   = false
	list_cancel_btn.disabled = false

	# "Selling 24 Common Cards For $120" — the rarity word is dropped for a whole-collection
	# sale, where naming one rarity would be a lie.
	var word : String = String(BAND_WORD.get(band, ""))
	var copies := _copies_in(selection)
	if word == "":
		header_label.text = "Selling %d Cards for $%d" % [copies, _selection_value]
	else:
		header_label.text = "Selling %d %s Cards for $%d" % [copies, word, _selection_value]

	_list_overlay = Control.new()
	_list_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list_overlay)
	# Behind the LIST BUTTONS node, which is a later sibling, so a card can never be drawn
	# over the sell/cancel pair.
	move_child(_list_overlay, list_buttons.get_index())

	_list_scroll = ScrollContainer.new()
	_list_scroll.position               = LIST_SCROLL_POS
	_list_scroll.size                   = LIST_SCROLL_SIZE
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_list_scroll.clip_contents          = true
	_list_scroll.z_index                = 5
	_list_overlay.add_child(_list_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_list_scroll.add_child(margin)

	_list_grid = GridContainer.new()
	_list_grid.columns               = LIST_COLUMNS
	_list_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_grid.add_theme_constant_override("h_separation", LIST_H_SEP)
	_list_grid.add_theme_constant_override("v_separation", LIST_V_SEP)
	margin.add_child(_list_grid)

	var sorted_ids : Array = CardViewerList.sort_ids(selection.keys(), _get_card_meta)
	var lines : Array = CardViewerList.individual_lines(sorted_ids, selection, _get_card_meta)
	CardViewerList.build_side_list(_list_overlay, lines,
		CardViewerList.category_rows(selection, _get_card_meta), LIST_SIDE_BOTTOM)

	await _fill_sell_grid(sorted_ids)


## One TextureRect per COPY being sold, in the shared viewer order. Each carries the cash
## it is worth as metadata, so the sale animation does not have to look its band up again.
func _fill_sell_grid(sorted_ids: Array) -> void:
	var since_yield := 0
	for card_id in sorted_ids:
		if not _on_list_screen:
			return
		var cid   : String = card_id
		var count : int    = int(_selection.get(cid, 0))
		var value : int    = int(BAND_PRICE.get(int(_spares[cid]["band"]), 0))
		var tex := _card_texture(cid)

		for _i in range(count):
			if not _on_list_screen or _list_grid == null:
				return
			var card_rect := TextureRect.new()
			if tex != null:
				card_rect.texture = tex
			card_rect.custom_minimum_size   = LIST_CARD_SIZE
			card_rect.size                  = LIST_CARD_SIZE
			card_rect.expand_mode           = TextureRect.EXPAND_IGNORE_SIZE
			card_rect.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			card_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			card_rect.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
			# card_id metadata plus a hovering mouse_filter is what makes the hold-Shift card
			# preview work over these, exactly as it does in the deck viewer's grid.
			card_rect.set_meta("card_id", cid)
			card_rect.set_meta("sell_value", value)
			card_rect.mouse_filter          = Control.MOUSE_FILTER_STOP
			_list_grid.add_child(card_rect)

			since_yield += 1
			if since_yield >= LIST_BUILD_BATCH:
				since_yield = 0
				if not is_inside_tree():
					return
				await get_tree().process_frame


## Large card art, cached — a big sale repeats the same handful of images many times.
func _card_texture(card_id: String) -> Texture2D:
	if _texture_cache.has(card_id):
		return _texture_cache[card_id]
	var card_set : String = card_id.split("-")[0]
	var path : String = CARD_IMAGE_FOLDER + card_set + "/Large/" + card_id + ".png"
	var tex = load(path)
	_texture_cache[card_id] = tex
	return tex


func _on_list_cancel_pressed() -> void:
	if _selling:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_show_home()


# ─── The sale ────────────────────────────────────────────────────────────────

## Vanishes every card on screen from the bottom right, walking right to left and bottom
## to top, each throwing a floating rainbow price label as it goes. The cards are left in
## the grid at zero scale rather than freed — a GridContainer re-flows the moment a child
## leaves it, and every remaining card would jump a slot each time one went.
func _on_list_sell_pressed() -> void:
	if _selling or _list_grid == null:
		return

	_selling = true
	list_sell_btn.disabled   = true
	list_cancel_btn.disabled = true

	var rects : Array = []
	for child in _list_grid.get_children():
		if child is TextureRect:
			rects.append(child)
	rects.reverse()   # bottom-right first, then leftwards and upwards

	var ticks := 0
	for rect in rects:
		if not is_instance_valid(rect) or not is_inside_tree():
			break
		_scroll_into_view(rect)
		await get_tree().process_frame
		if not is_instance_valid(rect):
			break

		var value : int = int(rect.get_meta("sell_value", 0))
		_spawn_float_label("$" + str(value),
			rect.global_position + rect.size / 2.0,
			CARD_LABEL_FONT, CARD_LABEL_OUTLINE, CARD_LABEL_SIZE,
			CARD_LABEL_RISE_PX, CARD_LABEL_RISE_TIME, CARD_LABEL_FADE_TIME)
		_vanish_card(rect)

		ticks += 1
		if ticks % SALE_SFX_EVERY == 0:
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)

		await get_tree().create_timer(VANISH_STAGGER).timeout

	if not is_inside_tree():
		return

	# Let the last label finish rising and fading before the screen changes under it.
	await get_tree().create_timer(maxf(CARD_LABEL_RISE_TIME, CARD_LABEL_FADE_TIME)).timeout
	if not is_inside_tree():
		return

	var payout := _selection_value
	GameState.remove_cards(_selection)
	GameState.add_cash(payout)          # saves progress itself
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	_scan_spares()                      # re-read from disk; nothing sold can linger
	_show_home()
	_selling = false

	_spawn_float_label("+$" + str(payout), TOTAL_LABEL_ANCHOR,
		TOTAL_LABEL_FONT, TOTAL_LABEL_OUTLINE, TOTAL_LABEL_SIZE,
		TOTAL_LABEL_RISE_PX, TOTAL_LABEL_RISE_TIME, TOTAL_LABEL_FADE_TIME)

	print("BULK SELL: sold ", _copies_in(_selection), " cards for $", payout,
		" — balance now $", GameState.get_cash())


## Shrinks one card away in place. Left in the tree at zero scale and zero alpha: a
## Container skips invisible children and re-lays out when one is freed, so either would
## make the whole grid jump every 0.05s.
func _vanish_card(rect: Control) -> void:
	rect.pivot_offset = rect.size / 2.0
	var tw := rect.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rect, "scale", Vector2.ZERO, VANISH_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "modulate:a", 0.0, VANISH_TIME)


## Keeps the card that is about to vanish inside the scroller, so a sale that starts at
## the bottom of a 400-card grid is actually visible. Walks upward with the animation.
func _scroll_into_view(rect: Control) -> void:
	if _list_scroll == null or not is_instance_valid(_list_scroll):
		return
	var content_y : float = rect.global_position.y - _list_scroll.global_position.y \
		+ float(_list_scroll.scroll_vertical)
	var view_h : float = _list_scroll.size.y
	var target : float = float(_list_scroll.scroll_vertical)

	if content_y + rect.size.y > target + view_h:
		target = content_y + rect.size.y - view_h + SCROLL_MARGIN
	elif content_y < target:
		target = content_y - SCROLL_MARGIN

	_list_scroll.scroll_vertical = maxi(int(target), 0)


# ─── Floating rainbow labels ─────────────────────────────────────────────────

## A drifting, fading, rainbow-cycling label centred on `centre`. RichTextLabel rather
## than Label purely for BBCode's [rainbow], which offsets the hue per character and
## advances it every frame — that is the colour wave running through the text.
## Adapted from Pack_Opening_Manager._show_bonus_label.
func _spawn_float_label(text: String, centre: Vector2, font_size: int, outline: int,
		box: Vector2, rise_px: float, rise_time: float, fade_time: float) -> void:
	if _float_layer == null or not is_instance_valid(_float_layer):
		return

	var label := RichTextLabel.new()
	label.bbcode_enabled      = true
	label.scroll_active       = false
	label.autowrap_mode       = TextServer.AUTOWRAP_OFF   # one line, never rewrapped
	label.custom_minimum_size = box
	label.size                = box
	label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	label.theme               = load(CardViewerList.KENNEY_THEME_PATH)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	var bold := _get_bold_font()
	if bold != null:
		label.add_theme_font_override("normal_font", bold)
	label.text = "[center][rainbow freq=%s sat=%s val=%s]%s[/rainbow][/center]" % [
		FLOAT_RAINBOW_FREQ, FLOAT_RAINBOW_SAT, FLOAT_RAINBOW_VAL, text]

	var spawn := centre - box / 2.0
	label.position = spawn
	_float_layer.add_child(label)

	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", spawn.y - rise_px, rise_time)
	tw.tween_property(label, "modulate:a", 0.0, fade_time)
	tw.finished.connect(label.queue_free)


func _get_bold_font() -> FontVariation:
	if _bold_font != null:
		return _bold_font
	var theme_res = load(CardViewerList.KENNEY_THEME_PATH)
	var base : Font = theme_res.default_font if theme_res != null else null
	if base == null:
		return null
	_bold_font = FontVariation.new()
	_bold_font.base_font          = base
	_bold_font.variation_embolden = FLOAT_EMBOLDEN
	return _bold_font


# ─── Leaving ─────────────────────────────────────────────────────────────────

func _on_leave_pressed() -> void:
	if _selling:
		return
	SoundManagerScript.stop_bgm()
	var target : String = GameState.menu_return_scene_path if GameState.has_menu_return_state \
		else GYM_PLAZA
	SceneCache.change_scene(target)


## Escape backs out one layer at a time — the card preview first, then the sell list, then
## the shop. Routed through UIInput rather than raw keycodes, like every other dialog in
## the game. Shift starts and ends the hold-to-preview.
func _input(event: InputEvent) -> void:
	if _selling:
		return

	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		if _is_zoomed:
			_zoom_held = false
			_hide_zoom()
		elif _on_list_screen:
			_on_list_cancel_pressed()
		else:
			_on_leave_pressed()
		return

	# The preview only exists over the sell list's grid — there is nothing to hover on the
	# home screen but decoration.
	if not _on_list_screen:
		return
	if UIInput.is_zoom_start(event):
		_zoom_held = true
		_refresh_hover_preview()
		return
	if UIInput.is_zoom_end(event):
		_zoom_held = false
		_hide_zoom()


# ─── Hold-Shift card preview ─────────────────────────────────────────────────
# Mirrored from Deck_Build_And_Card_View_Script.gd (ISSUE #13 / #98 / #151) so a card in
# the sell grid previews exactly as the same card does in the deck viewer. Worth having
# here in particular: the grid is the last look at cards that are about to be sold.

## While the zoom key is held, keeps the preview locked to whatever card the mouse is over.
## The is_zoom_held() re-check covers the one case the key events miss — alt-tabbing away
## with the key down eats the release, which would leave the preview stuck open.
func _process(_delta: float) -> void:
	if not _zoom_held:
		return
	if not UIInput.is_zoom_held():
		_zoom_held = false
		_hide_zoom()
		return
	_refresh_hover_preview()


## STICKY on purpose: the preview only ever changes to ANOTHER card, never to nothing.
## Sliding between two adjacent cards crosses the couple of pixels of grid separation, and
## tearing the overlay down there showed one frame of the bright screen underneath — read
## as a white flash between cards.
func _refresh_hover_preview() -> void:
	var card := _get_hovered_card()
	if card == _zoomed_card or card == null:
		return
	_show_zoom(card)


## The card TextureRect under the cursor, or null. The mouse may land on a child node
## rather than the card itself, so walk up looking for the "card_id" metadata every card
## in the grid carries.
func _get_hovered_card() -> TextureRect:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	var node = hovered
	for _i in range(5):
		if node == null:
			return null
		if node.has_meta("card_id"):
			return node as TextureRect
		node = node.get_parent()
	return null


func _show_zoom(card_rect: TextureRect) -> void:
	var card_id : String = card_rect.get_meta("card_id")
	_zoomed_card = card_rect

	# An overlay is already up (the player slid onto another card while holding the key) —
	# hand the new card to the live panel rather than rebuilding the CanvasLayer.
	if _is_zoomed and _detail_panel != null and is_instance_valid(_detail_panel):
		_detail_panel.show_card(card_id)
		return

	_is_zoomed = true

	_zoom_overlay = CanvasLayer.new()
	_zoom_overlay.layer = 150
	add_child(_zoom_overlay)

	var backdrop := ColorRect.new()
	backdrop.color         = Color(0, 0, 0, 0.95)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	# The overlay must never absorb hover, or gui_get_hovered_control() would report the
	# backdrop instead of the grid underneath and the live preview would flicker off.
	backdrop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_zoom_overlay.add_child(backdrop)

	_detail_panel = CardDetailPanel.new()
	_zoom_overlay.add_child(_detail_panel)
	_detail_panel.show_card(card_id)


func _hide_zoom() -> void:
	if not _is_zoomed:
		return
	_is_zoomed    = false
	_zoomed_card  = null
	_detail_panel = null
	if _zoom_overlay != null:
		_zoom_overlay.queue_free()
		_zoom_overlay = null
