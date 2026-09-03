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
## Down 20% from the original 300x416, and FAN_X_STEP with it so the overlap keeps its
## proportions. At the old size a rotated card's corners reached about 20px past its box
## and the outer cards of neighbouring groups just clipped each other; the 148px of clear
## air between groups at this size absorbs that with room to spare.
const FAN_CARD_SIZE  := Vector2(240, 333)
const FAN_X_STEP     := 116.0     # horizontal gap between one card's left edge and the next
## 220, down 30 from the original 190, with the price labels and all four sell buttons
## moved 30 the other way in the scene. Shrinking the cards left ~94px of dead air in the
## middle of the screen; closing it from both sides puts the whole cluster — fans at
## 211..566 once the outer cards' rotation is counted, labels at 600, buttons ending at
## 870 — centred on y 541. The content band it is centred against used to end at the money
## row's 985; that row is now the wallet chip up on the header border, so the band runs to
## the bottom border at 977 and the centre barely moved (533). Left as is.
const FAN_TOP_Y      := 220.0
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
## HALF the deck viewer's 183x254 — this screen routinely shows hundreds or thousands of
## cards where the viewer shows sixty, so it does not follow the viewer's card size.
## Halving each SIDE quarters the area, so about four times as many cards fit on screen
## (9 columns x ~3.8 rows = ~34 visible, now 18 x ~7.6 = ~136), not double. If double was
## the target, 129x179 at 12 columns is the size that gives it.
## COLUMNS is derived, not guessed: 18*91 + 17*2 separation = 1672, just inside the
## 1676-wide scroller. Change one and the other has to follow.
const LIST_CARD_SIZE   := Vector2(91, 126)
## ISSUE #209: 18 -> 17. At 18 the grid was 1672px wide from x=5, so its last
## column ended at 1681 and ran under the sale panel at PANEL_X 1652 — which only
## became visible once that panel grew to 248px to fix its text padding. 17
## columns are 1547 + 32 separation = 1579, ending at 1584, a clear 68px short of
## the panel. Derived rather than guessed: LIST_SCROLL_SIZE follows it below.
const LIST_COLUMNS     := 17
const LIST_H_SEP       := 2
const LIST_V_SEP       := 2
## ISSUE #194: the confirm grid runs the full band BETWEEN the two chrome bars,
## exactly like the deck builder's. It used to start 18px late (a black strip above
## the first row) and run to y=1079, which hid the bottom rows behind the footer.
const LIST_SCROLL_POS  := Vector2(5, UIKit.CONTENT_TOP)
const LIST_SCROLL_SIZE := Vector2(
	LIST_CARD_SIZE.x * float(LIST_COLUMNS) + float(LIST_H_SEP) * float(LIST_COLUMNS - 1) + 5.0,
	UIKit.CONTENT_H)
## The side list stops higher than the deck viewer's 990 because this screen stacks TWO
## buttons under it (sell + cancel) where the viewer has only Close.
const LIST_SIDE_BOTTOM := 930.0
## Cards added to the grid between frames. The deck viewer adds one per frame, which is
## fine for 60 cards and hopeless for the thousands this screen can be asked for. Three
## rows a frame: the fill happens behind the loading overlay now, so there is no
## progressive reveal to preserve and only throughput matters. At 3,000 cards this is
## about a second where one-per-frame would be nearly a minute.
const LIST_BUILD_BATCH := 54

# ── Confirm screen's sale panel ──────────────────────────────────────────────
# TWEAKABLE. Sits to the right of the card grid, above the two footer buttons.
## ISSUE #209: WIDER, AND WITH REAL PADDING. At 200px every row's text ran into
## the panel border on both sides, because a PanelContainer has no padding of its
## own and the rows were parented straight into it. The inset is a MarginContainer
## now (see _build_sale_panel) and the box grew to pay for it.
## ISSUE #209 (retest 2): 10px wider again, and PANEL_X is DERIVED so the gap to
## the right of the box (box -> screen edge) is exactly the gap to its left (last
## card column -> box). Hardcoding x meant every change to LIST_COLUMNS or PANEL_W
## silently unbalanced it; now the two gaps cannot drift apart.
const PANEL_W       := 258.0
const LIST_RIGHT_EDGE := LIST_SCROLL_POS.x + LIST_SCROLL_SIZE.x
const PANEL_X       := LIST_RIGHT_EDGE + (UIKit.SCREEN_W - LIST_RIGHT_EDGE - PANEL_W) * 0.5
const PANEL_Y       := 140.0
const PANEL_PAD     := 18.0
const PANEL_ROW_GAP := 14

# ── Sale animation ───────────────────────────────────────────────────────────
# TWEAKABLE. Cards vanish one at a time from the bottom-right of the grid, walking right
# to left and bottom to top, each one throwing a floating price label as it goes.
const VANISH_STAGGER   := 0.02    # delay between one card starting to vanish and the next
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

## ISSUE #208: HALF SIZE, AND IT FALLS FROM THE WALLET CHIP.
## The cash readout used to live in the bottom right of the screen, so the payout
## rose out of it. The new UI puts the balance in a pill in the top-right corner of
## the header, so the figure now drops DOWNWARD out of that pill instead — a
## negative rise in _spawn_float_label — and 96px was a shout next to a 54px pill.
## ISSUE #208 (retest): -20% again (48 -> 38).
const TOTAL_LABEL_FONT      := 38
const TOTAL_LABEL_OUTLINE   := 6
const TOTAL_LABEL_SIZE      := Vector2(700, 90)
const TOTAL_LABEL_RISE_PX   := -120.0
const TOTAL_LABEL_RISE_TIME := 2.0
const TOTAL_LABEL_FADE_TIME := 1.8
## ISSUE #208 (retest): the anchor is MEASURED off the wallet chip at spawn time
## rather than guessed. 1560 was ~200px left of the pill, because the pill's width
## depends on how many digits the balance has — there is no fixed x to hardcode.
## _wallet_drop_anchor() reads the chip's live rect; this is only the fallback for
## the frame before the chip exists.
const TOTAL_LABEL_ANCHOR := Vector2(1780, 132)
## Clearance between the bottom of the wallet pill and the top of the falling
## label, so the two never overlap on the first frame. TWEAKABLE.
const TOTAL_LABEL_PILL_GAP := 10.0
## ISSUE #208 (retest 3): 10 -> 30. The figure sits 30px right of the pill's own
## centre. TWEAKABLE.
## ISSUE #208 (retest 3): back to 0. It was walked out to 30 chasing a label that
## was never moving for an unrelated reason (see _wallet_drop_anchor); now the
## anchor is genuinely the pill's centre, a nudge would only push it back off it.
const TOTAL_LABEL_X_NUDGE := 0.0


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

## Dim + spinner shown while the sell grid builds. The deck-screen geometry is exactly
## right here: it stops 237px short of the right edge, which is precisely the side banner,
## so the sell and cancel buttons stay visible and clickable while the middle is blocked.
## The sell BUTTON is disabled separately — see _open_sell_list — because the overlay
## deliberately leaves that corner of the screen live for cancel.
var _loading : MenuLoadingOverlay = MenuLoadingOverlay.new()

# Hold-Shift card preview, mirrored from the deck builder so this grid behaves like that
# one. See _refresh_hover_preview().
var _zoom_held    : bool            = false
var _is_zoomed    : bool            = false
var _zoom_overlay : CanvasLayer     = null
var _zoomed_card  : TextureRect     = null
var _detail_panel : CardDetailPanel = null


# ─── Node references ─────────────────────────────────────────────────────────


# Footer button band: the 92px footer runs 988..1080, so a 64px button centred in
# it starts at 1002. TWEAKABLE.
const FOOTER_BTN_Y := 1002.0
const FOOTER_BTN_H := 64.0

## Header slot holding the confirm screen's "214 cards" chip. Empty on the home
## screen, which has no count to show.
var _count_chip_holder : Control = null

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

## The top-right cash pill, built at runtime by ShopChrome. Replaces the font-61 "Your money"
## pair that used to sit bottom-right, on top of the bottom border. Nothing on this screen is
## priced per item — the three bands are sell rates, not purchases — so there are no price
## pills here, only the wallet.
var wallet_chip : Control = null

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

	_build_chrome()
	wallet_chip = ShopChrome.add_wallet_chip(self, GameState.get_cash())

	_scan_spares()
	_build_card_fans()
	_show_home()


## Swaps the old bordered chrome for the Spectrum Night bars.
##
## This screen used to carry TWO sets of border art — the shop look for the home
## screen and the deck-viewer look for the sell list — shown and hidden as the
## player moved between them. Both are gone: the new chrome is the same on both
## screens, so only the header title and which footer buttons are visible change.
##
## The sell/cancel buttons DELIBERATELY stay inside their HOME BUTTONS and LIST
## BUTTONS parents rather than being reparented into the footer slot. Those two
## containers are what the existing screen switching shows and hides, and moving
## the buttons out would mean rewriting that; only their geometry moves here.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "")
	UIKit.adopt_label(header_label, bars["header"].centre)

	_count_chip_holder = bars["header"].left

	_place_footer_button(home_cancel_btn, "secondary", 0)
	_place_footer_button(list_cancel_btn, "secondary", -1)
	_place_footer_button(list_sell_btn, "primary", 1)

	# The four tier buttons and the grand total sit IN the content, not on the
	# footer, and take their theme from the scene rather than from this script —
	# so they need restyling by hand or they stay Kenney blue.
	#
	# ISSUE #255: ALL FOUR ARE PRIMARY. Three of them were "secondary" (the
	# transparent skin) and only "sell all spare bulk" was filled, which read as
	# one real button and three labels — but they are four equal choices doing the
	# same job at four different scopes, so they get the same weight.
	#
	# The wording is set here rather than in the scene so the four read as a set:
	# only the commons button said "only", which made the other two look like they
	# might sell something else as well. style_button applies the role's CASING, so
	# the text must be set BEFORE it.
	sell_common_btn.text   = "sell commons only"
	sell_uncommon_btn.text = "sell uncommons only"
	sell_rare_btn.text     = "sell rares only"
	for b in [sell_common_btn, sell_uncommon_btn, sell_rare_btn, sell_all_btn]:
		b.theme = null
		UIKit.style_button(b, "primary")

	# Same for the per-tier rate labels.
	for l in [common_price_label, uncommon_price_label, rare_price_label]:
		l.theme = null
		UIKit.style_label(l, "name", "field_mute")


## Positions a button on the footer's centre line. `slot` is -1 left of centre,
## 0 dead centre, 1 right of centre.
func _place_footer_button(btn: Button, variant: String, slot: int) -> void:
	UIKit.style_button(btn, variant)
	var w := UIKit.FOOTER_BTN_W
	var gap := float(UIKit.FOOTER_BTN_GAP)
	var centre_x := UIKit.SCREEN_W * 0.5
	var x := centre_x - w * 0.5
	if slot < 0:
		x = centre_x - w - gap * 0.5
	elif slot > 0:
		x = centre_x + gap * 0.5
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left   = x
	btn.offset_right  = x + w
	btn.offset_top    = FOOTER_BTN_Y
	btn.offset_bottom = FOOTER_BTN_Y + FOOTER_BTN_H


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
			UIKit.add_drop_shadow(rect)


func _show_home() -> void:
	_on_list_screen = false
	# The preview belongs to the grid that is about to go away — drop it before the chrome
	# swaps, or it would hang over the home screen with nothing behind it. Same for the
	# spinner: cancelling part-way through a build has to take it down immediately rather
	# than waiting for the fill loop to notice on its next batch.
	_zoom_held = false
	_hide_zoom()
	_loading.hide()

	header_label.text = "Sell Your Spare Bulk"
	_set_count_chip("")


	fan_root.visible     = true
	price_root.visible   = true
	home_buttons.visible = true
	wallet_chip.visible  = true
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
	ShopChrome.set_wallet_cash(wallet_chip, GameState.get_cash())


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

	# The two screens share ONE set of chrome now — the header title and the footer
	# buttons are all that change between them.

	fan_root.visible     = false
	price_root.visible   = false
	home_buttons.visible = false
	# The wallet STAYS on the confirm screen: the panel's "balance after" figure is
	# meaningless without the balance before it sitting in the header.
	wallet_chip.visible  = true
	list_buttons.visible = true
	# Sell stays dead until the last card is in the grid. Pressing it mid-build used to sell
	# only what had rendered so far while the rest kept appearing behind the animation.
	# Cancel stays live throughout — backing out of a slow build must always be possible.
	list_sell_btn.disabled   = true
	list_cancel_btn.disabled = false

	# "Selling 24 Common Cards For $120" — the rarity word is dropped for a whole-collection
	# sale, where naming one rarity would be a lie.
	# The header names the ACT and the count; the money maths moved to the side
	# panel, where "you receive" and "balance after" can sit next to each other.
	var word : String = String(BAND_WORD.get(band, ""))
	var copies := _copies_in(selection)
	header_label.text = "Confirm sale" if word == "" else "Confirm sale - %s" % word
	_set_count_chip("%d cards" % copies)

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
	# ISSUE #194: zero — the 10px inset was the black band above the first row.
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	_list_scroll.add_child(margin)

	_list_grid = GridContainer.new()
	_list_grid.columns               = LIST_COLUMNS
	_list_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_grid.add_theme_constant_override("h_separation", LIST_H_SEP)
	_list_grid.add_theme_constant_override("v_separation", LIST_V_SEP)
	margin.add_child(_list_grid)

	var sorted_ids : Array = CardViewerList.sort_ids(selection.keys(), _get_card_meta)
	_build_sale_panel(band, copies)

	# The spinner goes up before the fill and comes down after it, and needs one frame on
	# screen first or a fast build would never paint it.
	_loading.show_for_deck(self)
	await get_tree().process_frame
	await _fill_sell_grid(sorted_ids)
	_loading.hide()

	# Only arm Sell if the player is still here — cancel during a long build leaves this
	# await to unwind against a screen that has already gone back home.
	if _on_list_screen:
		list_sell_btn.disabled = false


## One TextureRect per COPY being sold, in the shared viewer order. Each carries the cash
## it is worth as metadata, so the sale animation does not have to look its band up again.
## Shows or clears the header count chip. Passing "" empties the slot, which is
## what the home screen wants.
func _set_count_chip(text: String) -> void:
	if _count_chip_holder == null or not is_instance_valid(_count_chip_holder):
		return
	for c in _count_chip_holder.get_children():
		c.queue_free()
	if text != "":
		_count_chip_holder.add_child(UIKit.make_chip(text, "on_chrome"))


## The sale's arithmetic, down the right-hand side of the confirm screen.
##
## This REPLACES CardViewerList's INDIVIDUAL / CATEGORIES bar on this screen only.
## The deck viewer still uses it — the two screens were deliberately identical, and
## this is the one place they now diverge, because a sale wants the money laid out
## rather than a second listing of cards the grid is already showing.
func _build_sale_panel(band: int, copies: int) -> void:
	var rate : int = int(BAND_PRICE.get(band, 0))
	var balance := GameState.get_cash()

	var panel := UIKit.make_panel()
	panel.position = Vector2(PANEL_X, PANEL_Y)
	panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	panel.size = Vector2(PANEL_W, 0.0)
	_list_overlay.add_child(panel)

	# ISSUE #209: the inset every row sits inside.
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, int(PANEL_PAD))
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", PANEL_ROW_GAP)
	pad.add_child(col)

	# A mixed-band sale has no single rate, so the row is dropped rather than
	# printed as a lie — "sell all" spans three different prices.
	var rows : Array = [["Cards sold", str(copies), "field_fg"]]
	if rate > 0:
		rows.append(["Rate", "$%d" % rate, "field_fg"])
	rows.append(["You receive", "$%d" % _selection_value, "good"])
	rows.append(["Balance after", "$%d" % (balance + _selection_value), "field_fg"])

	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var key := Label.new()
		UIKit.set_label(key, "small_label", String(r[0]), "field_mute")
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var val := Label.new()
		UIKit.set_label(val, "hp", String(r[1]), String(r[2]))
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		col.add_child(row)

	var note := Label.new()
	UIKit.set_label(note, "attack_name",
		"Four of every card stay in your collection. Only true spares are listed here.",
		"field_mute")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PANEL_W - PANEL_PAD * 2.0
	col.add_child(note)


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

	# One frame, once, so the grid's final layout pass has run and the scroller knows its
	# real content height before _scroll_into_view starts doing arithmetic against it.
	await get_tree().process_frame

	var ticks := 0
	for rect in rects:
		if not is_instance_valid(rect) or not is_inside_tree():
			break

		var anchor := _scroll_into_view(rect)
		var value : int = int(rect.get_meta("sell_value", 0))
		_spawn_float_label("$" + str(value),
			anchor + rect.size / 2.0,
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

	_spawn_float_label("+$" + str(payout), _wallet_drop_anchor(),
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
## the bottom of a 4,000-card grid is actually visible. Walks upward with the animation.
##
## Returns where the card will BE on screen once that scroll takes effect, worked out
## arithmetically rather than by waiting a frame for the container to re-lay-out. That
## wait used to sit in the sale loop, and at the old 0.05s stagger it hid inside the
## timer; at 0.02s a frame is most of the gap again and would have made the real spacing
## nearly twice what the constant says.
func _scroll_into_view(rect: Control) -> Vector2:
	var here : Vector2 = rect.global_position
	if _list_scroll == null or not is_instance_valid(_list_scroll):
		return here

	var old_scroll : float = float(_list_scroll.scroll_vertical)
	var content_y  : float = here.y - _list_scroll.global_position.y + old_scroll
	var view_h : float = _list_scroll.size.y
	var target : float = old_scroll

	if content_y + rect.size.y > target + view_h:
		target = content_y + rect.size.y - view_h + SCROLL_MARGIN
	elif content_y < target:
		target = content_y - SCROLL_MARGIN

	_list_scroll.scroll_vertical = maxi(int(target), 0)
	# Read it back rather than trusting the request: a ScrollContainer clamps to its own
	# content range, so the value that stuck is not always the value asked for.
	var new_scroll : float = float(_list_scroll.scroll_vertical)
	return Vector2(here.x, _list_scroll.global_position.y + content_y - new_scroll)


# ─── Floating rainbow labels ─────────────────────────────────────────────────

## A drifting, fading, rainbow-cycling label centred on `centre`. RichTextLabel rather
## than Label purely for BBCode's [rainbow], which offsets the hue per character and
## advances it every frame — that is the colour wave running through the text.
## Adapted from Pack_Opening_Manager._show_bonus_label.
## ISSUE #208: where the payout figure starts — directly under the wallet pill,
## touching neither it nor the header border.
##
## Returns the CENTRE of the label's box, which is what _spawn_float_label wants:
## the pill's centre x so the figure falls straight out of the number it changes,
## and far enough down that the box's top edge clears the pill's bottom.
## ISSUE #208 (retest 3) - WHY THREE NUDGES CHANGED NOTHING.
##
## `wallet_chip` is the HOLDER add_wallet_chip returns, and that holder is never
## given a size: the pill is a child placed at absolute coordinates inside it, so
## the holder's rect is (0,0) 0x0. `wallet_chip.get_global_rect().size.x` was
## therefore always 0, the guard below always tripped, and the function returned
## the HARDCODED fallback every single time. The "measured off the wallet chip"
## description was never true in a running build, which is why the label sat in
## the same place through 1560 -> 1750 -> 1760 -> 1780. ShopChrome.wallet_pill_rect
## asks the pill itself, so the measurement finally works and the figure falls out
## of the centre of the number it changes whatever the balance is.
func _wallet_drop_anchor() -> Vector2:
	var pill := ShopChrome.wallet_pill_rect(wallet_chip)
	if pill.size.x <= 1.0:
		print("ISSUE #208: wallet pill not laid out yet - fallback anchor ", TOTAL_LABEL_ANCHOR)
		return TOTAL_LABEL_ANCHOR
	print("ISSUE #208 FIX ACTIVE: pill rect ", pill, " -> payout falls from x ",
		pill.position.x + pill.size.x * 0.5 + TOTAL_LABEL_X_NUDGE)
	return Vector2(pill.position.x + pill.size.x * 0.5 + TOTAL_LABEL_X_NUDGE,
		pill.position.y + pill.size.y + TOTAL_LABEL_PILL_GAP + TOTAL_LABEL_SIZE.y * 0.5)


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

	# No backdrop: CardDetailPanel paints its own scrolling field, and a black
	# rect added here would be a sibling at z 0 over the panel's field at z -100.
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
