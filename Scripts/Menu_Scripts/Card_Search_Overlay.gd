class_name CardSearchOverlay
extends Control

# Full-screen card search / filter screen for the deck builder.
#
# Built entirely in code (like the energy style picker) and parented under the deck build Control,
# so it renders above the right-hand banner but inside the same scene. The deck builder hides its
# own UI while this is up, then does the actual filtering itself — this screen only collects the
# player's choices and hands them back as a criteria Dictionary.
#
# Usage:
#   var overlay := CardSearchOverlay.new()
#   add_child(overlay)
#   overlay.setup(unlocked_set_ids, set_list)
#   overlay.search_confirmed.connect(_on_search_confirmed)
#   overlay.search_cancelled.connect(_on_search_cancelled)
#
# Filter semantics (decided with the player):
#   - OR *within* a category, AND *between* categories.
#   - The name box is always an AND, matched as a case-insensitive substring.
#   - Pokemon-only rows (type / stage / Pokemon sub type) and the Trainer-only row (trainer sub
#     type) auto-select their implied Card Type and lock out the opposite supertype. It also works
#     the other way now: picking a Card Type greys out the rows that supertype can never have.
#     See _apply_lock.

signal search_confirmed(criteria: Dictionary)
signal search_cancelled()
## RESET was pressed. The screen has already blanked its own selections; the listener is expected to
## drop any search currently applied to the grid behind, so the two can't disagree.
signal search_reset()


# ══════════════════════════════════════════════════════════════════════════════
# TWEAKABLE VALUES — all screen geometry lives here
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# LAYOUT, rebuilt 2026-08-24 for ISSUES #142 / #145 / #146 / #147. Read this before tuning
# anything below it.
#
# #141 hides the deck screen's ~300px right-hand card banner while this screen is up, so the
# rows own the FULL 1920 rather than stopping short of it (#142). Every row is laid out
# left-aligned from CTRL_X; icon rows spread across CTRL_W via _row_pitch(), button rows step by a
# fixed BTN_W + BTN_GAP.
#
# RETEST PASS 2026-08-24 (#145 / #146 follow-ups). Two icon rows are sized by HEIGHT now, not by a
# square cell: icon_power/icon_body are ~4.15:1 strips, so drawing them KEEP_ASPECT_CENTERED in a
# 124x124 box rendered them 124x30 with ~47px of dead air above AND below — "almost an entire row
# of space". _make_icon_h() fixes the rendered HEIGHT and derives the width from the art's aspect,
# so the row box is exactly as tall as what is drawn in it. The same helper gives the POKEMON SUB
# TYPE row a uniform icon height (the four glyphs range from 0.96:1 to 1.42:1, so in a square cell
# they came out visibly different heights). Reclaiming the power row's dead 94px is what let
# ROW_GAP go back up from 8 to 16.
#
# #146 then shrank almost everything to buy back the vertical space #147's five set rows need:
#   name / illustrator boxes   -25% (height and font)
#   card type / stage / trainer sub / sort buttons  -25% (height and font; the width was later
#                              unified at BTN_W = 250 for all four rows, see #146's retest)
#   pokemon type icons         -10%
#   set icons                  -10%
#   pokemon sub type icons     -10%
#   rarity icons               -40%
# ...against #145, which DOUBLED the Has Power / Has Body icons. With every set unlocked the rows
# finish at y = 984 against a FOOTER_TOP of 996, so there is about 12px of slack and no more.
#
# CONSEQUENCE WORTH KNOWING: the ~180px of headroom that used to be reserved for the EFFECT row
# (see EFFECT_FILTERS) is gone. Populating that row now needs vertical space found elsewhere. The
# SET block is far and away the biggest thing on the screen at 269px with all five generation
# lines showing, so an EFFECT row most likely means shrinking SET_ICON or reclaiming ROW_GAP.
# ══════════════════════════════════════════════════════════════════════════════

# Header / footer bands and the vertical strip the filter rows flow down
const HEADER_H      := 96.0
# ISSUE #146 (retest): +4px so the NAME box does not sit hard against the bottom of the top border.
const CONTENT_TOP   := 108.0
const FOOTER_TOP    := 996.0

# ISSUE #142: how much clear space is left at the right-hand edge of the screen.
const RIGHT_MARGIN := 40.0

# Backdrop dim behind the header / footer bands. 1.0 = solid black; the deck background shows
# faintly through at 0.88.
const BACKDROP_ALPHA := 0.88

# The filter rows can sit on a light panel spanning HEADER_H..FOOTER_TOP, which is what the original
# mock-up had: black row labels and greyed-out "icon_" art both read properly against it.
#
# SHOW_FILTER_PANEL turns that panel on and off, and it is OFF at the moment. Note the row labels
# stay BLACK either way (LABEL_COLOR) — that was a deliberate call after seeing both on screen, so
# don't "fix" it to a light colour when the panel is hidden.
const SHOW_FILTER_PANEL := false
const PANEL_COLOR := Color(0.93, 0.93, 0.94, 1.0)

# Left-hand label column, and the x the controls start at.
# ISSUE #142: every row label is ONE line now (they used to break "POKEMON\nSUB TYPE" and friends
# over two). LABEL_W is sized off the longest of them — "HAS POWER OR BODY", ~304px in the Kenney
# font at 24pt — so none of them wrap or clip. Widening this pushes CTRL_X right; keep the two in
# step or the labels will run under the controls.
const LABEL_X     := 24.0
const LABEL_W     := 312.0
const LABEL_FONT  := 24
const LABEL_COLOR := Color(0.05, 0.05, 0.05, 1.0)
const CTRL_X      := 350.0

# ISSUE #142: the width every row has to play with — CTRL_X across to the right margin. 1530px.
const CTRL_W := 1920.0 - RIGHT_MARGIN - CTRL_X

# Vertical gap left between one filter row and the next.
# ISSUE #145 (retest): back up to 16 (it had been cut to 8) — killing the power row's dead 94px
# paid for it. This is the value to raise first if more breathing room is ever wanted; every 1px
# here costs 11px of screen.
const ROW_GAP := 16.0

# ISSUE #142 spreading, for the ICON rows only — the button rows use the fixed BTN_W/BTN_GAP pair
# below (ISSUE #146 retest asked for consistent button sizing and spacing, which a fill-the-width
# spread cannot give). An icon row fills CTRL_W when it has enough cells to, and otherwise falls
# back to "cell + this much gap": a two-icon row flung to opposite ends of a 1530px strip is not
# using the width, it is just broken. Raise this to spread the sparse icon rows further apart.
const MAX_ICON_GAP := 56.0

# Pokemon type icon row (single line, 9 icons). ISSUE #146: -10%.
const TYPE_ICON  := 49.0

# Set icon rows. Icons are drawn into a square cell with the aspect preserved, because the source
# art ranges from 41x21 (Base) to 128x128 (Southern Islands).
# ISSUE #146: -10%. ISSUE #147: the rows are the fixed generation groups in SET_ROW_GROUPS now,
# not an automatic one-or-two-line split, so SET_SINGLE_LINE_MAX is gone.
const SET_ICON      := 49.0
const SET_LINE_GAP  := 6.0

# Pokemon sub type icons (ex / shining-star / delta / dual type) — bigger, they read as glyphs
# rather than badges. ISSUE #146: -10%.
# ISSUE #146 (retest): this is now a RENDERED HEIGHT, not a square cell. The four source images
# run from 0.96:1 (delta) to 1.42:1 (ex), so a square cell drew them at four different heights and
# dual type looked taller than the rest. _make_icon_h() pins the height and lets the width follow
# the art, so the row reads as one set of glyphs.
const SUB_ICON  := 56.0

# Has Power / Has Body icons (ISSUE #140).
# ISSUE #145: DOUBLED — the two ability glyphs are the hardest icons on the screen to read at a
# glance, and unlike the sub type row above them there are only two, so the width is free.
# ISSUE #145 (retest): expressed as a RENDERED HEIGHT now. icon_power is 288x70 and icon_body
# 302x72 — ~4.15:1 strips — so 30px tall works out at ~124px wide, exactly the doubled size, but
# the row box is 30px instead of 124px. That removed ~94px of dead air above and below the icons.
# Raising this grows the icons in BOTH directions; the width follows the art.
const POWER_ICON  := 30.0

# Illustrator free-text row (ISSUE #143). Height matches the NAME box so the screen's two text
# fields read as a pair. ISSUE #146: height and font -25%. ISSUE #142: full width.
const ILLUS_H    := 54.0
const ILLUS_W    := CTRL_W
const ILLUS_FONT := 22

# Name free-text row. ISSUE #146: height and font -25%. ISSUE #142: full width.
const NAME_H    := 54.0
const NAME_W    := CTRL_W
const NAME_FONT := 22

# Rarity symbol icons. ISSUE #146: -40%, the biggest cut on the screen — they are pure symbols
# with no fine detail to lose.
const RARITY_ICON  := 32.0

# Effect icon rows (reserved — see EFFECT_FILTERS)
const EFFECT_ICON     := 49.0
const EFFECT_LINE_GAP := 6.0
const EFFECT_SINGLE_LINE_MAX := 12

# Kenney text buttons. ISSUE #146: height and font -25%.
# ISSUE #146 (retest): ONE width and ONE gap for all four button rows (card type / pokemon stage /
# trainer sub type / sort by) rather than four different widths. 250 is set by the longest label,
# "TECHNICAL MACHINE" (~205px at 16pt plus ~21px of Kenney stylebox margin), which also means it
# fits on one line at the same font size as everything else — the old BTN_FONT_SMALL special case
# is gone. The busiest row is 4 buttons: 4*250 + 3*80 = 1240 of the 1530 available.
const BTN_H     := 39.0
const BTN_W     := 250.0
const BTN_GAP   := 80.0
const BTN_FONT  := 16

# Header controls
const TITLE_FONT  := 46
const RESET_X     := 1560.0
const RESET_Y     := 21.0
const RESET_W     := 300.0
const RESET_H     := 54.0

# Footer controls
const FOOT_BTN_Y := 1004.0
const FOOT_BTN_W := 320.0
const FOOT_BTN_H := 56.0
const SEARCH_X   := 600.0
const CANCEL_X   := 1100.0

# ISSUE #141 (retest): z for everything the player interacts with. The deck scene's
# `filter_border` — the patterned strip this screen now shows across the top — is an OPAQUE
# TextureRect at z_index 200, and z accumulates down the tree, so the header's RESET button and
# the "CARD SEARCH" title (overlay z 10 + their old z 55 = 60) were being painted over by it.
# 250 puts them at an effective 260, safely in front. The backdrop and panel deliberately stay
# BELOW 200 so the border still draws over them and remains visible — that was the whole point of
# showing it.
const CONTENT_Z := 250

# Selected-icon pulse (matches the card / energy icon animation used elsewhere)
const PULSE_SCALE   := 1.12
const PULSE_SECONDS := 0.5
const PULSE_BRIGHT  := 1.4

# How far a blocked-out icon is dimmed
const BLOCKED_ICON_ALPHA := 0.30


# ══════════════════════════════════════════════════════════════════════════════
# Filter option tables
# ══════════════════════════════════════════════════════════════════════════════

const ENERGY_ICON_PATH  := "res://Image_Assets/Icons/Energy_Icons/"
const SET_ICON_PATH     := "res://Image_Assets/Icons/Set_Icons/"
const SUBTYPE_ICON_PATH := "res://Image_Assets/Icons/Subtype_Icons/"
const RARITY_ICON_PATH  := "res://Image_Assets/Icons/Rarity_Icons/"
const EFFECT_ICON_PATH  := "res://Image_Assets/Icons/Effect_Icons/"

# Pokemon types, in the order they appear on screen. The value is the icon file stem, so the
# unselected art is "icon_<stem>.png" and the selected art is "color_icon_<stem>.png".
const POKEMON_TYPES : Array = [
	{"key": "Grass",     "icon": "grass"},
	{"key": "Fire",      "icon": "fire"},
	{"key": "Water",     "icon": "water"},
	{"key": "Lightning", "icon": "lightning"},
	{"key": "Psychic",   "icon": "psychic"},
	{"key": "Fighting",  "icon": "fighting"},
	{"key": "Colorless", "icon": "colorless"},
	{"key": "Darkness",  "icon": "darkness"},
	{"key": "Metal",     "icon": "metal"},
]

# Card supertypes. The keys are the exact strings used in the card JSON.
const CARD_TYPES : Array = [
	{"key": "Pokémon", "label": "POKEMON"},
	{"key": "Trainer", "label": "TRAINER"},
	{"key": "Energy",  "label": "ENERGY"},
]

# Pokemon stages. Keys are exact subtype strings. Baby cards carry ONLY "Baby" (never "Basic"),
# so the four stages are genuinely exclusive buckets.
const STAGES : Array = [
	{"key": "Baby",    "label": "BABY",    "gate": "neo1"},
	{"key": "Basic",   "label": "BASIC",   "gate": ""},
	{"key": "Stage 1", "label": "STAGE 1", "gate": ""},
	{"key": "Stage 2", "label": "STAGE 2", "gate": ""},
]

# Trainer sub types. Keys are exact subtype strings.
# Gates are the first NON-PROMO set that contains one — promo cards (basep/np) are handed out at
# scripted story points, so a player never holds one before the matching main set is unlocked.
const TRAINER_SUBS : Array = [
	{"key": "Pokémon Tool",      "label": "TOOL",              "gate": "neo1"},
	{"key": "Supporter",         "label": "SUPPORTER",         "gate": "ecard1"},
	{"key": "Stadium",           "label": "STADIUM",           "gate": "gym1"},
	{"key": "Technical Machine", "label": "TECHNICAL MACHINE", "gate": "ecard1"},
]

# Pokemon sub types. These are NOT plain subtype lookups — see Deck_Build_And_Card_View_Script's
# _card_matches_search for how each one is actually tested.
#   ex       -> "ex" in subtypes
#   shining  -> name starts with "Shining ", or "Star" in subtypes (the gold star cards)
#   delta    -> name ends with the delta symbol, matching card_object.is_delta()
#   dualtype -> more than one entry in the card's "types" array (e.g. Psychic/Metal Metagross).
#               First appears in ex4 (Team Aqua's Cacturne, Grass/Darkness).
const POKEMON_SUBS : Array = [
	{"key": "ex",       "icon": "ex",       "tip": "Pokemon ex",      "gate": "ex1"},
	{"key": "shining",  "icon": "shining",  "tip": "Shining / Star",  "gate": "neo1"},
	{"key": "delta",    "icon": "delta",    "tip": "Delta Species",   "gate": "ex11"},
	{"key": "dualtype", "icon": "dualtype", "tip": "Dual Type",       "gate": "ex4"},
]

# ISSUE #140: "does this card have an ability, and of which kind".
#   power -> a "Poké-Power" OR the older "Pokémon Power". Base Set through Neo printed every
#            ability as "Pokémon Power"; e-Card split it into the activated Poké-Power and the
#            passive Poké-Body, so the old name belongs with Power, not Body. 463 cards.
#   body  -> a "Poké-Body". 385 cards. First printed in ecard1, hence the gate — basep has one
#            promo with a Body, but promos are handed out at scripted story points and so are
#            deliberately ignored for gating (same rule as TRAINER_SUBS above).
#
# NOT part of the Pokemon/Trainer supertype lock, unlike the rows above it. Eight Trainers
# (Claw Fossil and Root Fossil in ex2/ex12/ex13/ex16) carry a real Poké-Body, so forcing
# Card Type = Pokemon here would hide cards that genuinely match. It behaves like RARITY: a
# whole-card property that simply ANDs with whatever else is selected.
const POWER_FILTERS : Array = [
	{"key": "power", "icon": "power", "tip": "Has a Pokemon Power / Poke-Power", "gate": ""},
	{"key": "body",  "icon": "body",  "tip": "Has a Poke-Body",                  "gate": "ecard1"},
]

# Card rarity, in the order the player asked for: common -> uncommon -> rare -> holo rare.
# "holorare" deliberately swallows every other Rare variant in the data — Rare Holo, Rare Holo EX,
# Rare Holo Star, Rare Shining and Rare Secret (the secret rares are all holofoil cards).
# No unlock gates: all four rarities exist from Base Set onwards.
const RARITIES : Array = [
	{"key": "common",   "icon": "common",   "tip": "Common"},
	{"key": "uncommon", "icon": "uncommon", "tip": "Uncommon"},
	{"key": "rare",     "icon": "rare",     "tip": "Rare"},
	{"key": "holorare", "icon": "holorare", "tip": "Holo Rare"},
]

# RESERVED: the card-effect filter row. Populate this and the row builds itself — icons, tooltips,
# two-line flow and the reset/lock handling all come for free. Each entry is:
#   {"key": "bench_damage", "icon": "bench_damage", "tip": "Deals damage to Bench Pokemon"}
# with art at EFFECT_ICON_PATH + "icon_<icon>.png" / "color_icon_<icon>.png".
# The matching side lives in Deck_Build_And_Card_View_Script._card_matches_effect().
const EFFECT_FILTERS : Array = []

# ISSUE #147: which line of the SET row each set sits on, one entry per line, in the order the
# player asked for. Only sets the player has UNLOCKED are drawn, and a line whose sets are all
# still locked is skipped entirely — so a new save shows one short line and the rows below it
# close the gap, exactly like a fully gated-off filter row.
#
# Order WITHIN a line comes from _set_list (release order), not from this table, so listing a set
# in the wrong place here changes its line but never its position among its neighbours. "np" is
# EX Promos, hence its place at the end of the EX line. Any set missing from this table is drawn
# on a trailing line of its own with a warning rather than silently disappearing.
const SET_ROW_GROUPS : Array = [
	["base1", "base2", "base3", "base5", "basep", "gym1", "gym2"],
	["neo1", "neo2", "neo3", "neo4", "si1"],
	["ecard1", "ecard2", "ecard3"],
	["ex1", "ex2", "ex3", "ex4", "ex5", "ex6", "ex7", "ex8", "ex9", "ex10",
	 "ex11", "ex12", "ex13", "ex14", "ex15", "ex16", "np"],
	["pop1", "pop2", "pop3", "pop4", "pop5"],
]

const SORT_MODES : Array = [
	{"key": "set",  "label": "SET"},
	{"key": "name", "label": "NAME"},
]


# ══════════════════════════════════════════════════════════════════════════════
# State
# ══════════════════════════════════════════════════════════════════════════════

var _set_list : Array = []      # [{set_id, set_name}, ...] in release order
var _unlocked : Array = []      # set_ids the player has unlocked

# Current selections. Each is a set-like Dictionary of key -> true.
var _sel_types        : Dictionary = {}
var _sel_sets         : Dictionary = {}
var _sel_card_types   : Dictionary = {}
var _sel_stages       : Dictionary = {}
var _sel_trainer_subs : Dictionary = {}
var _sel_pokemon_subs : Dictionary = {}
var _sel_rarities     : Dictionary = {}
var _sel_powers       : Dictionary = {}   # ISSUE #140
var _sel_effects      : Dictionary = {}
var _sort_mode        : String     = "set"

# Card types the player picked by hand. A card type that was only auto-selected by a Pokemon-only
# or Trainer-only row gets cleared again when that row empties; a hand-picked one never does.
var _manual_card_types : Dictionary = {}

# Node lookups, keyed by the same keys as the selection dictionaries
var _type_icons    : Dictionary = {}
var _set_icons     : Dictionary = {}
var _sub_icons     : Dictionary = {}
var _rarity_icons  : Dictionary = {}
var _power_icons   : Dictionary = {}   # ISSUE #140
var _effect_icons  : Dictionary = {}
var _card_type_btn : Dictionary = {}
var _stage_btn     : Dictionary = {}
var _trainer_btn   : Dictionary = {}
var _sort_btn      : Dictionary = {}

var _name_edit    : LineEdit = null
var _illus_edit   : LineEdit = null   # ISSUE #143
var _confirm_btn  : Button   = null

var _theme_white : Theme = null
var _theme_green : Theme = null
var _theme_blue  : Theme = null
var _theme_red   : Theme = null


# ══════════════════════════════════════════════════════════════════════════════
# Build
# ══════════════════════════════════════════════════════════════════════════════

## Builds the whole screen. Call once, immediately after add_child().
## unlocked_set_ids drives both which set icons appear and which gated options are shown.
func setup(unlocked_set_ids: Array, set_list: Array) -> void:
	_unlocked = unlocked_set_ids
	_set_list = set_list

	_theme_white = load("res://UI_Themes/kenneyUI.tres")
	_theme_green = load("res://UI_Themes/kenneyUI-green.tres")
	_theme_blue  = load("res://UI_Themes/kenneyUI-blue.tres")
	_theme_red   = load("res://UI_Themes/kenneyUI-red.tres")

	# A plain Control (not a CanvasLayer) so it sits in the normal z order: above the deck screen's
	# right-hand border (z 50) but still inside this scene, exactly like the energy style picker.
	z_index = 10
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_backdrop()
	_build_header()
	_build_rows()
	_build_footer()

	_refresh_confirm_button()


func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, BACKDROP_ALPHA)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.z_index = 50
	# STOP so nothing behind the search screen can be clicked through it
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Light panel behind the filter rows only — the header and footer bands keep the dark backdrop,
	# so the white title and the coloured action buttons still read against them. Currently switched
	# off (SHOW_FILTER_PANEL), which makes it TRANSPARENT rather than hidden: a hidden Control is
	# dropped from input picking entirely, so it would stop swallowing clicks over the filter rows.
	var panel := ColorRect.new()
	panel.color = PANEL_COLOR if SHOW_FILTER_PANEL else Color(0.0, 0.0, 0.0, 0.0)
	panel.position = Vector2(0.0, HEADER_H)
	panel.size     = Vector2(1920.0, FOOTER_TOP - HEADER_H)
	panel.z_index  = 51
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)


func _build_header() -> void:
	var title := Label.new()
	title.theme = _theme_white
	title.text = "CARD SEARCH"
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(360.0, 0.0)
	title.size     = Vector2(1200.0, HEADER_H)
	title.z_index  = CONTENT_Z
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var reset := Button.new()
	reset.theme = _theme_red
	reset.text  = "RESET"
	reset.add_theme_font_size_override("font_size", BTN_FONT)
	reset.position = Vector2(RESET_X, RESET_Y)
	reset.size     = Vector2(RESET_W, RESET_H)
	reset.custom_minimum_size = Vector2(RESET_W, RESET_H)
	reset.z_index  = CONTENT_Z
	reset.pressed.connect(_on_reset_pressed)
	add_child(reset)


func _build_footer() -> void:
	_confirm_btn = Button.new()
	_confirm_btn.theme = _theme_green
	_confirm_btn.text  = "SEARCH"
	_confirm_btn.add_theme_font_size_override("font_size", BTN_FONT)
	_confirm_btn.position = Vector2(SEARCH_X, FOOT_BTN_Y)
	_confirm_btn.size     = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	_confirm_btn.custom_minimum_size = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	_confirm_btn.z_index  = CONTENT_Z
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_btn)

	var cancel := Button.new()
	cancel.theme = _theme_red
	cancel.text  = "CANCEL"
	cancel.add_theme_font_size_override("font_size", BTN_FONT)
	cancel.position = Vector2(CANCEL_X, FOOT_BTN_Y)
	cancel.size     = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	cancel.custom_minimum_size = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	cancel.z_index  = CONTENT_Z
	cancel.pressed.connect(_on_cancel_pressed)
	add_child(cancel)


## Lays the filter rows out top to bottom with a running y cursor, so a row that is entirely
## gated off (no unlocked options) simply isn't drawn and the rows below close the gap.
func _build_rows() -> void:
	var y := CONTENT_TOP

	y = _build_name_row(y)
	y = _build_type_row(y)
	y = _build_set_row(y)
	y = _build_card_type_row(y)
	y = _build_stage_row(y)
	y = _build_trainer_sub_row(y)
	y = _build_pokemon_sub_row(y)
	y = _build_power_row(y)          # ISSUE #140 — sits directly under the sub type row
	y = _build_rarity_row(y)
	y = _build_effect_row(y)
	y = _build_illustrator_row(y)    # ISSUE #143 — last filter before the sort buttons
	y = _build_sort_row(y)

	# ISSUE #147 asked for the layout to be re-checked once the five set rows went in. With every
	# set unlocked (the tallest the screen ever gets) the rows finish at y=984 against a FOOTER_TOP
	# of 996 — about 12px of slack, so this screen is close to full. The guard below is the standing
	# tripwire: if it ever fires, shrink ROW_GAP, SET_ICON or the SET block rather than letting the
	# rows overlap the footer buttons.
	if y > FOOTER_TOP:
		push_warning("CardSearch: filter rows overflow the footer by %d px" % int(y - FOOTER_TOP))


func _build_name_row(y: float) -> float:
	var h := NAME_H
	_add_row_label("NAME", y, h)

	_name_edit = LineEdit.new()
	_name_edit.theme = _theme_white
	_name_edit.position = Vector2(CTRL_X, y)
	_name_edit.size     = Vector2(NAME_W, h)
	_name_edit.custom_minimum_size = Vector2(NAME_W, h)
	_name_edit.add_theme_font_size_override("font_size", NAME_FONT)
	_name_edit.add_theme_color_override("font_color", Color.BLACK)
	_name_edit.placeholder_text = "Card name..... (comma-separate for several)"
	# ISSUE #149: no length cap — a comma-separated list of card names runs well past 30 characters.
	_name_edit.z_index = CONTENT_Z
	_name_edit.text_changed.connect(_on_name_changed)
	# Enter in the name box runs the search, as long as something is actually filled in
	_name_edit.text_submitted.connect(func(_t: String): _on_confirm_pressed())
	add_child(_name_edit)

	return y + h + ROW_GAP


func _build_type_row(y: float) -> float:
	_add_row_label("POKEMON TYPE", y, TYPE_ICON)

	var pitch := _row_pitch(POKEMON_TYPES.size(), TYPE_ICON, MAX_ICON_GAP)
	var x := CTRL_X
	for entry in POKEMON_TYPES:
		var key : String = entry["key"]
		var icon := _make_icon(ENERGY_ICON_PATH, entry["icon"], TYPE_ICON, Vector2(x, y), key)
		icon.gui_input.connect(_on_icon_input.bind(icon, "type", key))
		_type_icons[key] = icon
		x += pitch

	return y + TYPE_ICON + ROW_GAP


## ISSUE #147: one line per card-set generation instead of the old "split everything over one or
## two balanced lines". Only unlocked sets are drawn and a line with nothing unlocked on it is not
## drawn at all, so the block grows with the player's collection: one short line on a new save,
## five once everything is open. See SET_ROW_GROUPS for the grouping and its ordering rules.
func _build_set_row(y: float) -> float:
	# Bucket the unlocked sets into their generation lines. Iterating _set_list (release order)
	# inside each group is what keeps the icons in release order along a line.
	var rows   : Array      = []
	var placed : Dictionary = {}
	for group in SET_ROW_GROUPS:
		var line : Array = []
		for entry in _set_list:
			var sid : String = entry["set_id"]
			if sid in _unlocked and sid in group:
				line.append(entry)
				placed[sid] = true
		if not line.is_empty():
			rows.append(line)

	# A set that SET_ROW_GROUPS doesn't name (a new set added later) gets a trailing line of its
	# own rather than quietly vanishing from the filter.
	var orphans : Array = []
	for entry2 in _set_list:
		var sid2 : String = entry2["set_id"]
		if sid2 in _unlocked and not placed.has(sid2):
			orphans.append(entry2)
	if not orphans.is_empty():
		var names : Array = []
		for o in orphans:
			names.append(o["set_id"])
		push_warning("CardSearch: sets missing from SET_ROW_GROUPS: " + str(names))
		rows.append(orphans)

	if rows.is_empty():
		return y

	# ISSUE #142: ONE pitch shared by every line, taken from the busiest one (17 icons on the EX
	# line with everything unlocked), so the icons sit in tidy columns and the busiest line is the
	# one that fills the full width.
	var widest := 0
	for line2 in rows:
		widest = maxi(widest, (line2 as Array).size())
	var pitch := _row_pitch(widest, SET_ICON, MAX_ICON_GAP)

	var block_h : float = rows.size() * SET_ICON + (rows.size() - 1) * SET_LINE_GAP
	_add_row_label("SET", y, block_h)

	for r in range(rows.size()):
		var line3 : Array = rows[r]
		var line_y : float = y + r * (SET_ICON + SET_LINE_GAP)
		for c in range(line3.size()):
			var entry3 : Dictionary = line3[c]
			var sid3   : String     = entry3["set_id"]
			var icon := _make_icon(SET_ICON_PATH, sid3, SET_ICON,
				Vector2(CTRL_X + c * pitch, line_y), entry3["set_name"])
			icon.gui_input.connect(_on_icon_input.bind(icon, "set", sid3))
			_set_icons[sid3] = icon

	return y + block_h + ROW_GAP


func _build_card_type_row(y: float) -> float:
	_add_row_label("CARD TYPE", y, BTN_H)

	var x := CTRL_X
	for entry in CARD_TYPES:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, BTN_W, BTN_FONT)
		btn.pressed.connect(_on_card_type_pressed.bind(key))
		_card_type_btn[key] = btn
		x += BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_stage_row(y: float) -> float:
	var shown := _visible_options(STAGES)
	if shown.is_empty():
		return y

	_add_row_label("POKEMON STAGE", y, BTN_H)

	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, BTN_W, BTN_FONT)
		btn.pressed.connect(_on_simple_toggle.bind("stage", key))
		_stage_btn[key] = btn
		x += BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_trainer_sub_row(y: float) -> float:
	var shown := _visible_options(TRAINER_SUBS)
	if shown.is_empty():
		return y

	_add_row_label("TRAINER SUB TYPE", y, BTN_H)

	# ISSUE #142: "TECHNICAL MACHINE" is ONE line. ISSUE #146 (retest): BTN_W is sized off it, so it
	# now fits at the same font as every other button and needs no special case at all.
	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, BTN_W, BTN_FONT)
		btn.pressed.connect(_on_simple_toggle.bind("trainer_sub", key))
		_trainer_btn[key] = btn
		x += BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_pokemon_sub_row(y: float) -> float:
	var shown := _visible_options(POKEMON_SUBS)
	if shown.is_empty():
		return y

	_add_row_label("POKEMON SUB TYPE", y, SUB_ICON)

	# ISSUE #146 (retest): uniform HEIGHT, width from each icon's own aspect — see _make_icon_h().
	# The pitch is taken from the widest of them so the row never overlaps itself.
	var pitch := _row_pitch(shown.size(), _widest_icon(SUBTYPE_ICON_PATH, shown, SUB_ICON), MAX_ICON_GAP)
	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var icon := _make_icon_h(SUBTYPE_ICON_PATH, entry["icon"], SUB_ICON, Vector2(x, y), entry["tip"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "pokemon_sub", key))
		_sub_icons[key] = icon
		x += pitch

	return y + SUB_ICON + ROW_GAP


## ISSUE #140: "HAS POWER / BODY". Built exactly like the sub type row above it — same _make_icon
## call, so the greyed icon_ art, the color_icon_ swap and the grow-and-glow pulse all come for free.
## Like RARITY (and unlike the sub type row it sits under) it takes no part in the supertype lock;
## see POWER_FILTERS for why.
func _build_power_row(y: float) -> float:
	var shown := _visible_options(POWER_FILTERS)
	if shown.is_empty():
		return y

	_add_row_label("HAS POWER OR BODY", y, POWER_ICON)

	# ISSUE #145 (retest): sized by rendered HEIGHT — see _make_icon_h() and POWER_ICON.
	var widest := _widest_icon(SUBTYPE_ICON_PATH, shown, POWER_ICON)
	var pitch := _row_pitch(shown.size(), widest, MAX_ICON_GAP)
	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var icon := _make_icon_h(SUBTYPE_ICON_PATH, entry["icon"], POWER_ICON, Vector2(x, y), entry["tip"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "power", key))
		_power_icons[key] = icon
		x += pitch

	return y + POWER_ICON + ROW_GAP


## ISSUE #143: free-text illustrator box. Always an AND against every other filter, matched as a
## case-insensitive substring, so "sugimori" finds every Ken Sugimori card and "ken" finds his plus
## Ken Ikuji-Hirayama. Deliberately free text rather than a picker: there are 89 distinct artists in
## the card data, far too many for an icon or button row.
func _build_illustrator_row(y: float) -> float:
	_add_row_label("ILLUSTRATOR", y, ILLUS_H)

	_illus_edit = LineEdit.new()
	_illus_edit.theme = _theme_white
	_illus_edit.position = Vector2(CTRL_X, y)
	_illus_edit.size     = Vector2(ILLUS_W, ILLUS_H)
	_illus_edit.custom_minimum_size = Vector2(ILLUS_W, ILLUS_H)
	_illus_edit.add_theme_font_size_override("font_size", ILLUS_FONT)
	_illus_edit.add_theme_color_override("font_color", Color.BLACK)
	_illus_edit.placeholder_text = "Illustrator name..... (comma-separate for several)"
	# ISSUE #149: no length cap, same as the name box.
	_illus_edit.z_index = CONTENT_Z
	_illus_edit.text_changed.connect(_on_name_changed)
	_illus_edit.text_submitted.connect(func(_t: String): _on_confirm_pressed())
	add_child(_illus_edit)

	return y + ILLUS_H + ROW_GAP


## Rarity is a whole-card property (Pokemon, Trainer and Energy all carry one), so unlike the stage
## and sub type rows it takes no part in the Pokemon/Trainer supertype lock.
func _build_rarity_row(y: float) -> float:
	_add_row_label("RARITY", y, RARITY_ICON)

	var pitch := _row_pitch(RARITIES.size(), RARITY_ICON, MAX_ICON_GAP)
	var x := CTRL_X
	for entry in RARITIES:
		var key : String = entry["key"]
		var icon := _make_icon(RARITY_ICON_PATH, entry["icon"], RARITY_ICON, Vector2(x, y), entry["tip"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "rarity", key))
		_rarity_icons[key] = icon
		x += pitch

	return y + RARITY_ICON + ROW_GAP


## RESERVED row — draws nothing while EFFECT_FILTERS is empty, and lays itself out exactly like the
## SET row (two balanced lines of icons with hover tooltips) the moment entries are added.
func _build_effect_row(y: float) -> float:
	var shown := _visible_options(EFFECT_FILTERS)
	if shown.is_empty():
		return y

	var lines := 1 if shown.size() <= EFFECT_SINGLE_LINE_MAX else 2
	var per_line : int = int(ceil(float(shown.size()) / float(lines)))
	var block_h := lines * EFFECT_ICON + (lines - 1) * EFFECT_LINE_GAP
	var pitch := _row_pitch(per_line, EFFECT_ICON, MAX_ICON_GAP)

	_add_row_label("EFFECT", y, block_h)

	for i in range(shown.size()):
		var entry : Dictionary = shown[i]
		var key   : String     = entry["key"]
		var line  : int        = i / per_line
		var col   : int        = i % per_line
		var pos := Vector2(
			CTRL_X + col * pitch,
			y + line * (EFFECT_ICON + EFFECT_LINE_GAP)
		)
		var icon := _make_icon(EFFECT_ICON_PATH, entry["icon"], EFFECT_ICON, pos, entry.get("tip", key))
		icon.gui_input.connect(_on_icon_input.bind(icon, "effect", key))
		_effect_icons[key] = icon

	return y + block_h + ROW_GAP


func _build_sort_row(y: float) -> float:
	_add_row_label("SORT BY", y, BTN_H)

	var x := CTRL_X
	for entry in SORT_MODES:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, BTN_W, BTN_FONT)
		btn.pressed.connect(_on_sort_pressed.bind(key))
		_sort_btn[key] = btn
		x += BTN_W + BTN_GAP

	_refresh_sort_buttons()
	return y + BTN_H + ROW_GAP


# ══════════════════════════════════════════════════════════════════════════════
# Build helpers
# ══════════════════════════════════════════════════════════════════════════════

## ISSUE #142: pitch (cell-to-cell step) for a row of `count` equally sized cells laid out from
## CTRL_X. Fills the full CTRL_W when the row has enough cells to; otherwise falls back to
## "cell + max_gap" so a two- or three-cell row isn't flung across the whole screen.
func _row_pitch(count: int, cell: float, max_gap: float) -> float:
	if count <= 1:
		return cell
	return minf(CTRL_W / float(count), cell + max_gap)


## Widest rendered icon in a row drawn by _make_icon_h(), used to pick a pitch that cannot overlap.
func _widest_icon(folder: String, entries: Array, height: float) -> float:
	var widest := height
	for entry in entries:
		widest = maxf(widest, height * _icon_aspect(folder, entry["icon"]))
	return widest


## Filters an option table down to the entries whose unlock gate has been met.
## An entry with no "gate" (or an empty one) is always shown.
func _visible_options(table: Array) -> Array:
	var out : Array = []
	for entry in table:
		var gate : String = entry.get("gate", "")
		if gate == "" or gate in _unlocked:
			out.append(entry)
	return out


func _add_row_label(text: String, y: float, h: float) -> void:
	var lbl := Label.new()
	lbl.theme = _theme_white
	lbl.text  = text
	lbl.add_theme_font_size_override("font_size", LABEL_FONT)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	lbl.position = Vector2(LABEL_X, y)
	lbl.size     = Vector2(LABEL_W, h)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index  = CONTENT_Z
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)


## Creates one unselected filter icon. The art is drawn into a SQUARE cell with its aspect ratio
## preserved — set icons range from 41x21 (Base) to 128x128 (Southern Islands), so a fixed cell plus
## KEEP_ASPECT_CENTERED is what keeps the row visually even.
func _make_icon(folder: String, stem: String, cell: float, pos: Vector2, tip: String) -> TextureRect:
	var icon := TextureRect.new()
	var tex = load(folder + "icon_" + stem + ".png")
	if tex != null:
		icon.texture = tex
	else:
		push_error("CardSearch: missing icon " + folder + "icon_" + stem + ".png")

	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = pos
	icon.size     = Vector2(cell, cell)
	icon.custom_minimum_size = Vector2(cell, cell)
	# Centre pivot so the selected pulse grows from the middle rather than the top-left
	icon.pivot_offset = Vector2(cell, cell) / 2.0
	icon.z_index = CONTENT_Z
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.tooltip_text = tip
	# Remembered so _set_icon_selected can swap between icon_ / color_icon_ art later
	icon.set_meta("folder", folder)
	icon.set_meta("stem", stem)
	icon.set_meta("selected", false)
	icon.set_meta("blocked", false)
	add_child(icon)
	return icon


## ISSUE #145/#146 (retest): an icon sized by its RENDERED HEIGHT, with the width taken from the
## art's own aspect ratio. _make_icon() above draws into a SQUARE cell, which is right for rows of
## same-shaped badges (types, sets, rarities) but wrong for two cases here:
##   * icon_power / icon_body are ~4.15:1 strips, so a square cell reserved 4x the height they
##     actually drew in and left a band of dead air above and below the row;
##   * the four POKEMON SUB TYPE glyphs range from 0.96:1 to 1.42:1, so a square cell drew them at
##     four different heights and dual type looked taller than its neighbours.
## Pinning the height makes a row of mismatched art read as one set. Use it for any future row
## whose icons are not all the same shape.
func _make_icon_h(folder: String, stem: String, height: float, pos: Vector2, tip: String) -> TextureRect:
	var icon := _make_icon(folder, stem, height, pos, tip)
	var w := height * _icon_aspect(folder, stem)
	icon.size     = Vector2(w, height)
	icon.custom_minimum_size = Vector2(w, height)
	icon.pivot_offset = Vector2(w, height) / 2.0
	return icon


## Width-to-height ratio of an icon's art, or 1.0 if it cannot be loaded. Godot caches the load, so
## calling this next to _make_icon_h() does not read the file twice.
func _icon_aspect(folder: String, stem: String) -> float:
	var tex = load(folder + "icon_" + stem + ".png")
	if tex == null or tex.get_height() <= 0:
		return 1.0
	return float(tex.get_width()) / float(tex.get_height())


func _make_button(text: String, x: float, y: float, w: float, font_size: int) -> Button:
	var btn := Button.new()
	btn.theme = _theme_white
	btn.text  = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.position = Vector2(x, y)
	btn.size     = Vector2(w, BTN_H)
	btn.custom_minimum_size = Vector2(w, BTN_H)
	btn.z_index  = CONTENT_Z
	add_child(btn)
	return btn


# ══════════════════════════════════════════════════════════════════════════════
# Selection visuals
# ══════════════════════════════════════════════════════════════════════════════

## Swaps an icon between its greyed "icon_" art and its "color_icon_" art, and starts / stops the
## same grow-and-glow pulse used for cards that are in the deck.
##
## _apply_lock re-asserts every icon's look after each click, so this early-outs when the icon is
## already in the requested state — otherwise every selected icon's pulse would restart (and visibly
## snap back to full size) each time the player touched any other icon on the screen.
func _set_icon_selected(icon: TextureRect, selected: bool, force: bool = false) -> void:
	if not force and bool(icon.get_meta("selected", false)) == selected:
		return
	icon.set_meta("selected", selected)

	var folder : String = icon.get_meta("folder")
	var stem   : String = icon.get_meta("stem")
	var prefix := "color_icon_" if selected else "icon_"
	var tex = load(folder + prefix + stem + ".png")
	if tex != null:
		icon.texture = tex

	var old = icon.get_meta("pulse", null)
	if old != null:
		old.kill()
	icon.set_meta("pulse", null)

	icon.scale = Vector2.ONE
	icon.modulate = Color.WHITE

	if not selected:
		return

	var tw := create_tween()
	tw.set_loops()
	icon.set_meta("pulse", tw)
	tw.tween_property(icon, "scale", Vector2(PULSE_SCALE, PULSE_SCALE), PULSE_SECONDS)
	tw.parallel().tween_property(icon, "modulate", Color.WHITE * PULSE_BRIGHT, PULSE_SECONDS)
	tw.tween_property(icon, "scale", Vector2.ONE, PULSE_SECONDS)
	tw.parallel().tween_property(icon, "modulate", Color.WHITE, PULSE_SECONDS)


## Blocks or unblocks an icon. A blocked icon is dimmed and stops taking clicks; unblocking forces a
## full restyle because the block overwrote whatever selected/unselected look it had.
func _set_icon_blocked(icon: TextureRect, blocked: bool, selected: bool) -> void:
	var was_blocked := bool(icon.get_meta("blocked", false))
	if blocked:
		icon.set_meta("blocked", true)
		if was_blocked:
			return
		var old = icon.get_meta("pulse", null)
		if old != null:
			old.kill()
		icon.set_meta("pulse", null)
		icon.scale = Vector2.ONE
		icon.modulate = Color(1.0, 1.0, 1.0, BLOCKED_ICON_ALPHA)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		icon.set_meta("blocked", false)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_icon_selected(icon, selected, was_blocked)


func _set_button_selected(btn: Button, selected: bool, selected_theme: Theme) -> void:
	btn.disabled = false
	btn.theme = selected_theme if selected else _theme_white


## A card type button that is forced on by another row's selection: it stays green (so it still
## reads as selected) but can't be clicked, because it isn't the player's choice to make while the
## row that implied it still has something in it.
func _set_button_locked_on(btn: Button) -> void:
	btn.theme = _theme_green
	btn.disabled = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.29, 0.71, 0.24, 1.0)
	sb.set_corner_radius_all(5)
	sb.content_margin_left   = 8.0
	sb.content_margin_right  = 8.0
	sb.content_margin_top    = 6.0
	sb.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color.WHITE)


## A button blocked out by the opposite supertype's lock — greyed exactly like the deck screen's
## disabled set-navigation arrows.
func _set_button_blocked(btn: Button) -> void:
	btn.theme = _theme_white
	btn.disabled = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.67, 0.67, 0.67, 1.0)
	sb.set_corner_radius_all(5)
	sb.content_margin_left   = 8.0
	sb.content_margin_right  = 8.0
	sb.content_margin_top    = 6.0
	sb.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.35, 1.0))


func _clear_button_overrides(btn: Button) -> void:
	btn.remove_theme_stylebox_override("disabled")
	btn.remove_theme_color_override("font_disabled_color")


# ══════════════════════════════════════════════════════════════════════════════
# Input handling
# ══════════════════════════════════════════════════════════════════════════════

## Shared click handler for every filter icon (type / set / pokemon sub / effect).
## ISSUE #98-style guard: a mouse WHEEL event is also an InputEventMouseButton, so the button index
## is checked explicitly rather than trusting `pressed` alone — scrolling over an icon must not
## toggle it.
func _on_icon_input(event: InputEvent, icon: TextureRect, category: String, key: String) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	var store := _selection_store(category)
	var now_on := not store.has(key)
	if now_on:
		store[key] = true
	else:
		store.erase(key)

	SoundManagerScript.play_sfx(
		SoundManagerScript.SFX_plus_select if now_on else SoundManagerScript.SFX_minus_select
	)

	_set_icon_selected(icon, now_on)
	_apply_lock()
	_refresh_confirm_button()


## Shared handler for the plain Kenney toggle rows (Pokemon stage / trainer sub type).
func _on_simple_toggle(category: String, key: String) -> void:
	var store := _selection_store(category)
	var now_on := not store.has(key)
	if now_on:
		store[key] = true
	else:
		store.erase(key)

	SoundManagerScript.play_sfx(
		SoundManagerScript.SFX_plus_select if now_on else SoundManagerScript.SFX_minus_select
	)

	# _apply_lock restyles every button in both rows from the selection dictionaries, so there's
	# nothing to repaint here — it is the single source of truth for how these buttons look.
	_apply_lock()
	_refresh_confirm_button()


func _on_card_type_pressed(key: String) -> void:
	var now_on := not _sel_card_types.has(key)
	if now_on:
		_sel_card_types[key] = true
		_manual_card_types[key] = true
	else:
		_sel_card_types.erase(key)
		_manual_card_types.erase(key)

	SoundManagerScript.play_sfx(
		SoundManagerScript.SFX_plus_select if now_on else SoundManagerScript.SFX_minus_select
	)

	_apply_lock()
	_refresh_confirm_button()


func _on_sort_pressed(key: String) -> void:
	if _sort_mode == key:
		return          # sort is a radio, not a toggle — there is always exactly one mode
	_sort_mode = key
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_refresh_sort_buttons()


func _on_name_changed(_new_text: String) -> void:
	_refresh_confirm_button()


func _on_reset_pressed() -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)

	_name_edit.text = ""
	if _illus_edit != null:
		_illus_edit.text = ""

	for key in _type_icons:
		_sel_types.erase(key)
		_set_icon_selected(_type_icons[key], false)
	for key in _set_icons:
		_sel_sets.erase(key)
		_set_icon_selected(_set_icons[key], false)
	for key in _sub_icons:
		_sel_pokemon_subs.erase(key)
		_set_icon_selected(_sub_icons[key], false)
	for key in _rarity_icons:
		_sel_rarities.erase(key)
		_set_icon_selected(_rarity_icons[key], false)
	for key in _power_icons:
		_sel_powers.erase(key)
		_set_icon_selected(_power_icons[key], false)
	for key in _effect_icons:
		_sel_effects.erase(key)
		_set_icon_selected(_effect_icons[key], false)

	_sel_card_types.clear()
	_manual_card_types.clear()
	_sel_stages.clear()
	_sel_trainer_subs.clear()

	for key in _card_type_btn:
		_clear_button_overrides(_card_type_btn[key])
		_set_button_selected(_card_type_btn[key], false, _theme_green)
	for key in _stage_btn:
		_clear_button_overrides(_stage_btn[key])
		_set_button_selected(_stage_btn[key], false, _theme_green)
	for key in _trainer_btn:
		_clear_button_overrides(_trainer_btn[key])
		_set_button_selected(_trainer_btn[key], false, _theme_green)

	# Sort mode is a view preference rather than a filter, so RESET leaves it on the default.
	_sort_mode = "set"
	_refresh_sort_buttons()

	_apply_lock()
	_refresh_confirm_button()

	# RESET means "no filter anywhere", so the search applied to the grid behind goes too. Without
	# this the screen would show nothing selected while the grid stayed filtered, and because an
	# empty filter also disables SEARCH, that left the player with no button back out.
	search_reset.emit()


func _on_confirm_pressed() -> void:
	if not _has_any_filter():
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	search_confirmed.emit(build_criteria())


func _on_cancel_pressed() -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	search_cancelled.emit()


## Returns the selection Dictionary a category writes into, so the toggle handlers stay generic.
func _selection_store(category: String) -> Dictionary:
	match category:
		"type":        return _sel_types
		"set":         return _sel_sets
		"stage":       return _sel_stages
		"trainer_sub": return _sel_trainer_subs
		"pokemon_sub": return _sel_pokemon_subs
		"rarity":      return _sel_rarities
		"power":       return _sel_powers
		"effect":      return _sel_effects
	return {}


# ══════════════════════════════════════════════════════════════════════════════
# Card type lock
# ══════════════════════════════════════════════════════════════════════════════

# Rows that can only ever describe a Pokemon, and rows that can only ever describe a Trainer.
# Selecting anything in either group locks the Card Type row to that supertype and blocks the
# opposite group, because the combination could never match a card.
#
# CHANGED 2026-08-24 — this now works in BOTH directions. It used to be deliberately one-way (a sub
# type implied a card type, but never the reverse), which left "Trainer" selectable alongside a live
# POKEMON SUB TYPE row: a combination that can match nothing, offered as though it were valid.
# Picking a Card Type by hand now greys out the rows that supertype can never have — Trainer or
# Energy greys the three Pokemon-only rows, Pokemon or Energy greys TRAINER SUB TYPE.
#
# The two directions stay distinct in the UI, and the difference is deliberate:
#   * a FORCED card type (implied by a sub-row) goes green-and-DISABLED — the player cannot undo it
#     without first clearing the row that implied it;
#   * a HAND-PICKED card type stays green and clickable, so it can always be toggled back off. Only
#     the rows it excludes go grey.
# Selecting BOTH Pokemon and Trainer blocks nothing: OR-within-a-category means a card may be either.
#
# Still NOT part of the lock, on purpose: RARITY (a whole-card property) and HAS POWER OR BODY
# (eight Trainers carry a real Poke-Body, so forcing Pokemon there would hide real matches).

func _pokemon_rows_selected() -> bool:
	return not _sel_types.is_empty() or not _sel_stages.is_empty() or not _sel_pokemon_subs.is_empty()


func _trainer_rows_selected() -> bool:
	return not _sel_trainer_subs.is_empty()


# Last [lock, block_pokemon, block_trainer] reported by _apply_lock(), so the console line below
# only fires when the lock state actually moves rather than on every click.
var _last_lock_state : Array = []


## Can a card of this supertype still be in the results? True when the player has picked no card
## type at all (no restriction yet) or has picked this one among their choices. Drives which rows
## are greyed out; see the note above for why both directions matter.
func _supertype_possible(key: String) -> bool:
	return _sel_card_types.is_empty() or _sel_card_types.has(key)


## "" when nothing is locked, otherwise the supertype that is being forced.
## Only one can ever be active, because whichever lock engages first blocks the other group's rows.
func _current_lock() -> String:
	if _trainer_rows_selected():
		return "Trainer"
	if _pokemon_rows_selected():
		return "Pokémon"
	return ""


## Re-applies the whole lock state from scratch. Called after every selection change so it never has
## to reason about what changed — it just reads the current selections and makes the UI agree.
func _apply_lock() -> void:
	var lock := _current_lock()

	# ── Card Type row ──
	for entry in CARD_TYPES:
		var key : String = entry["key"]
		var btn : Button = _card_type_btn[key]
		_clear_button_overrides(btn)

		if lock == "":
			# Nothing is forcing a card type. Drop any type that was only auto-selected; a type the
			# player picked by hand survives. SELECTION still flows one way only — a sub type
			# implies a card type, but a card type never implies or clears a sub type. What changed
			# in 2026-08-24 is BLOCKING, which now flows both ways: a hand-picked card type greys
			# out the rows it excludes without ever touching what is selected in them.
			if _sel_card_types.has(key) and not _manual_card_types.has(key):
				_sel_card_types.erase(key)
			_set_button_selected(btn, _sel_card_types.has(key), _theme_green)
		elif key == lock:
			_sel_card_types[key] = true
			_set_button_locked_on(btn)
		else:
			_sel_card_types.erase(key)
			_manual_card_types.erase(key)
			_set_button_blocked(btn)

	# Read AFTER the Card Type loop above, which is what settles _sel_card_types for this pass —
	# it force-selects a locked type and erases the ones a lock blocks out.
	#
	# The `lock` terms are strictly redundant (a Trainer lock has already forced _sel_card_types to
	# {"Trainer"}, so _supertype_possible("Pokémon") is false anyway) and are kept only so the
	# original one-way rule still reads plainly in the code.
	var block_pokemon := lock == "Trainer" or not _supertype_possible("Pokémon")
	var block_trainer := lock == "Pokémon" or not _supertype_possible("Trainer")

	# ── Pokemon-only rows: blocked by a Trainer sub type, or by picking Trainer/Energy by hand ──
	for key in _type_icons:
		_set_icon_blocked(_type_icons[key], block_pokemon, _sel_types.has(key))
	for key in _sub_icons:
		_set_icon_blocked(_sub_icons[key], block_pokemon, _sel_pokemon_subs.has(key))
	for key in _stage_btn:
		var sbtn : Button = _stage_btn[key]
		_clear_button_overrides(sbtn)
		if block_pokemon:
			_set_button_blocked(sbtn)
		else:
			_set_button_selected(sbtn, _sel_stages.has(key), _theme_green)

	# ── Trainer-only row: blocked by any Pokemon-only row, or by picking Pokemon/Energy by hand ──
	for key in _trainer_btn:
		var tbtn : Button = _trainer_btn[key]
		_clear_button_overrides(tbtn)
		if block_trainer:
			_set_button_blocked(tbtn)
		else:
			_set_button_selected(tbtn, _sel_trainer_subs.has(key), _theme_green)

	# Only on a CHANGE. _apply_lock() runs on every single click anywhere on this screen, so an
	# unconditional print would bury the console in identical lines.
	var state := [lock, block_pokemon, block_trainer]
	if state != _last_lock_state:
		_last_lock_state = state
		print("SUPERTYPE LOCK: card types ", _sel_card_types.keys(), " forced=\"", lock,
			"\" -> pokemon rows blocked=", block_pokemon, ", trainer sub type blocked=", block_trainer)


func _refresh_sort_buttons() -> void:
	for entry in SORT_MODES:
		var key : String = entry["key"]
		if _sort_btn.has(key):
			# Blue rather than green — sort is a view setting, not a filter, so it reads differently
			_set_button_selected(_sort_btn[key], _sort_mode == key, _theme_blue)


## True when at least one actual filter is set. The sort mode deliberately doesn't count — sorting
## nothing is still nothing.
func _has_any_filter() -> bool:
	if _name_edit != null and _name_edit.text.strip_edges() != "":
		return true
	if _illus_edit != null and _illus_edit.text.strip_edges() != "":
		return true
	return not (_sel_types.is_empty() and _sel_sets.is_empty() and _sel_card_types.is_empty()
		and _sel_stages.is_empty() and _sel_trainer_subs.is_empty()
		and _sel_pokemon_subs.is_empty() and _sel_rarities.is_empty()
		and _sel_powers.is_empty() and _sel_effects.is_empty())


func _refresh_confirm_button() -> void:
	if _confirm_btn == null:
		return
	var can_search := _has_any_filter()
	_clear_button_overrides(_confirm_btn)
	if can_search:
		_confirm_btn.disabled = false
		_confirm_btn.theme = _theme_green
	else:
		_set_button_blocked(_confirm_btn)


# ══════════════════════════════════════════════════════════════════════════════
# Output
# ══════════════════════════════════════════════════════════════════════════════

## Snapshots the current selections into the criteria Dictionary the deck builder filters with.
func build_criteria() -> Dictionary:
	var name_terms  := parse_search_terms(_name_edit.text if _name_edit != null else "")
	var illus_terms := parse_search_terms(_illus_edit.text if _illus_edit != null else "")
	return {
		"name_terms":   name_terms,
		"illus_terms":  illus_terms,
		"types":        _sel_types.keys(),
		"sets":         _sel_sets.keys(),
		"card_types":   _sel_card_types.keys(),
		"stages":       _sel_stages.keys(),
		"trainer_subs": _sel_trainer_subs.keys(),
		"pokemon_subs": _sel_pokemon_subs.keys(),
		"rarities":     _sel_rarities.keys(),
		"powers":       _sel_powers.keys(),
		"effects":      _sel_effects.keys(),
		"sort":         _sort_mode,
	}


## ISSUE #149: splits one free-text box into OR terms on a COMMA.
##
## The separator was " OR " originally, which needed a pile of failsafes: "or" is a substring of
## real card names (Voltorb, Porygon, Electrode), so the parser had to distinguish a separator from
## a search term and had to define what a box holding nothing but separators meant. A comma has
## none of that ambiguity — **not one of the ~2,000 cards in any of the 37 sets has a comma in its
## name** — so a comma is only ever a separator and every one of those failsafes is gone with it.
##
## Returns a plain Array of lower-cased, non-empty terms. The caller ORs them together and ANDs the
## result with every other filter, exactly as a single substring used to behave. An empty array
## means no filter on this box, which now also covers the degenerate ",,," case: nothing to search
## for, so nothing is excluded.
##
## Spacing around the comma is free — terms are stripped — so "Dratini,Dragonite" and
## "Dratini, Dragonite" are the same search, and a trailing "Dratini," just drops the empty tail.
##
## ONE KNOWN WRINKLE, in the illustrator box only: 24 cards in neo1-neo4 carry a collaborator
## credit of the form "K. Hoshiba, CR CG gangs", so their artist string does contain a comma.
## Searching "Hoshiba" or "CR CG gangs" still works (each is one term, matched as a substring);
## only pasting the full comma-containing string verbatim widens the search, and even then the
## result is a superset of what was wanted. Card names are unaffected.
static func parse_search_terms(raw: String) -> Array:
	var terms : Array = []
	for part in raw.to_lower().split(","):
		var t := String(part).strip_edges()
		if t != "":
			terms.append(t)
	return terms
