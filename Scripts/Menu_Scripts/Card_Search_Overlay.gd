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
# ISSUE #178: the label column gives up 20px and the controls start 20px further
# left, which is where the extra room for the wrapped chip rows comes from.
const LABEL_X     := 20.0
const LABEL_W     := 300.0
const LABEL_FONT  := 24
# ISSUE #177: white, not black. The light filter panel these were authored against
# (SHOW_FILTER_PANEL) has been off since the overhaul, so a near-black label was
# sitting on the dark field.
const LABEL_COLOR := Color(0.957, 0.929, 0.980, 1.0)
const CTRL_X      := 330.0

# ISSUE #142: the width every row has to play with — CTRL_X across to the right margin. 1530px.
const CTRL_W := 1920.0 - RIGHT_MARGIN - CTRL_X

# Vertical gap left between one filter row and the next.
# ISSUE #145 (retest): back up to 16 (it had been cut to 8) — killing the power row's dead 94px
# paid for it. This is the value to raise first if more breathing room is ever wanted; every 1px
# here costs 11px of screen.
## Cut from 16 when the icon rows became wrapping chips: the SET block alone grew
## from 5 fixed lines to 7, and at 16 the SORT BY row ran under the footer. Every
## 1px here costs ~12px of screen across the twelve rows.
const ROW_GAP := 9.0

# ISSUE #142 spreading, for the ICON rows only — the button rows use the fixed BTN_W/BTN_GAP pair
# below (ISSUE #146 retest asked for consistent button sizing and spacing, which a fill-the-width
# spread cannot give). An icon row fills CTRL_W when it has enough cells to, and otherwise falls
# back to "cell + this much gap": a two-icon row flung to opposite ends of a 1530px strip is not
# using the width, it is just broken. Raise this to spread the sparse icon rows further apart.
const MAX_ICON_GAP := 56.0

# -- Filter chips (UI overhaul) ----------------------------------------------
# TWEAKABLE. Chips are sized to their own text and the rows WRAP, so a long row
# grows downward instead of squeezing its pitch.
const CHIP_H      := 38.0
const CHIP_FONT   := 15
const CHIP_PAD_X  := 13.0
const CHIP_MIN_W  := 58.0
const CHIP_GAP_X  := 10.0
const CHIP_GAP_Y  := 10.0

# ISSUE #178: THE ROWS OVERLAPPED BECAUSE A CHIP IS NOT CHIP_H TALL.
# Every chip and text button on this screen is a themed Button, and the shared
# button face carries btn_pad_v (13px) top AND bottom as CONTENT MARGINS. That is
# a MINIMUM size Godot enforces, so a "38px" chip actually drew at ~48px and every
# row ran into the one below it. _tighten() re-margins the button's four state
# boxes so the authored height is the real height. Re-apply it after ANY
# UIKit.style_button() call, because that swaps the theme back.
const CHIP_PAD_Y  := 4.0
const BTN_PAD_Y   := 5.0

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
const BTN_H     := 40.0
const BTN_W     := 236.0
const BTN_GAP   := 60.0
const BTN_FONT  := 15

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
	# ISSUE #179: the chip is labelled with its `tip`, so these are the button
	# labels now, not tooltips — "Has a Pokemon Power / Poke-Power" was a sentence
	# sitting in a chip row.
	# ISSUE #179 (retest): "there should be a SECOND button for Poke-Body". There
	# always was one - it was GATED on owning ecard1 (Expedition), the set that
	# introduced Poke-Bodies, so on a save without that set the row drew a single
	# chip and the two searches looked merged into one. The two are separate
	# filters keyed on separate booleans (_card_matches_power) and always were;
	# what was wrong is that only one of them was ever on screen. UNGATED now, so
	# the pair is always offered - a search that returns nothing is a clearer
	# answer than a missing control.
	{"key": "power", "icon": "power", "tip": "Poke-Power", "gate": ""},
	{"key": "body",  "icon": "body",  "tip": "Poke-Body",  "gate": ""},
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

## ISSUE #225: "type" sorts Pokemon by energy type first (in the ENERGY_ORDER
## below), then Trainers, then Energy cards. The ordering itself lives in the deck
## builder's _sort_cards — this table only names the modes.
const SORT_MODES : Array = [
	{"key": "set",  "label": "SET"},
	{"key": "name", "label": "NAME"},
	{"key": "type", "label": "TYPE"},
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

	_theme_white = load("res://UI_Themes/ui/ui_secondary.tres")
	# "green" is the SELECTED state for every filter chip on this screen, and
	# selection is pink everywhere else in the game — so it points at ui_selected.
	_theme_green = load("res://UI_Themes/ui/ui_selected.tres")
	_theme_blue  = load("res://UI_Themes/ui/ui_selected.tres")
	# Reset and Cancel back out; they do not destroy anything.
	_theme_red   = load("res://UI_Themes/ui/ui_secondary.tres")

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
	# ISSUE #226: fire on press like every other button in the game.
	reset.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	reset.pressed.connect(_on_reset_pressed)
	add_child(reset)


func _build_footer() -> void:
	_confirm_btn = Button.new()
	UIKit.style_button(_confirm_btn, "primary")
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
	cancel.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # ISSUE #226
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
	# ISSUE #181: pure white. Black was left over from the light filter panel.
	_name_edit.add_theme_color_override("font_color", Color.WHITE)
	_name_edit.placeholder_text = "Card name..... (comma-separate for several)"
	# ISSUE #149: no length cap — a comma-separated list of card names runs well past 30 characters.
	_name_edit.z_index = CONTENT_Z
	_name_edit.text_changed.connect(_on_name_changed)
	# Enter in the name box runs the search, as long as something is actually filled in
	_name_edit.text_submitted.connect(func(_t: String): _on_confirm_pressed())
	add_child(_name_edit)

	return y + h + ROW_GAP


func _build_type_row(y: float) -> float:
	_add_row_label("POKEMON TYPE", y, CHIP_H)

	# The type chips are the one row that carries COLOUR, because here hue is data
	# rather than decoration - see UITheme.ENERGY_COLOUR. Everything else on this
	# screen is a neutral chip that only goes pink when selected.
	var rows : Array = []
	for entry in POKEMON_TYPES:
		rows.append({ "key": entry["key"], "tip": entry["key"] })
	var end_y := _flow_chips(rows, y, "type", _type_icons)
	for key in _type_icons:
		_tint_type_chip(_type_icons[key], String(key), _sel_types.has(key))

	return end_y + ROW_GAP


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

	# One generation per BLOCK, but each block flows and wraps on its own, so the
	# ex era spilling onto extra lines pushes the rows below it down instead of
	# squeezing every set into one pitch.
	var line_y := y
	for r in range(rows.size()):
		var line3 : Array = rows[r]
		var chip_rows : Array = []
		for entry3 in line3:
			chip_rows.append({ "key": entry3["set_id"], "tip": entry3["set_name"] })
		line_y = _flow_chips(chip_rows, line_y, "set", _set_icons) + CHIP_GAP_Y

	# The label is added AFTER the flow, because only now is the block's real
	# height known — with everything unlocked the ex era alone wraps three times.
	_add_row_label("SET", y, line_y - CHIP_GAP_Y - y)

	return line_y - CHIP_GAP_Y + ROW_GAP


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

	_add_row_label("POKEMON SUB TYPE", y, CHIP_H)
	return _flow_chips(shown, y, "pokemon_sub", _sub_icons) + ROW_GAP


## ISSUE #140: "HAS POWER / BODY". Built exactly like the sub type row above it — same _make_icon
## call, so the greyed icon_ art, the color_icon_ swap and the grow-and-glow pulse all come for free.
## Like RARITY (and unlike the sub type row it sits under) it takes no part in the supertype lock;
## see POWER_FILTERS for why.
func _build_power_row(y: float) -> float:
	var shown := _visible_options(POWER_FILTERS)
	if shown.is_empty():
		return y

	_add_row_label("HAS POWER OR BODY", y, CHIP_H)
	return _flow_chips(shown, y, "power", _power_icons) + ROW_GAP


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
	# ISSUE #181
	_illus_edit.add_theme_color_override("font_color", Color.WHITE)
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
	_add_row_label("RARITY", y, CHIP_H)
	return _flow_chips(RARITIES, y, "rarity", _rarity_icons) + ROW_GAP


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
func _make_icon(folder: String, stem: String, cell: float, pos: Vector2, tip: String) -> Control:
	# `folder`, `stem` and `cell` stay in the signature and in the metas so every
	# call site reads the way it did, but no art is loaded any more. The rows this
	# feeds were grids of icon art; they are text chips now, because a 49px set
	# symbol is not readable and a player hunting "Team Rocket" was being asked to
	# recognise a logo.
	var chip := Button.new()
	chip.text = tip
	chip.position = pos
	chip.custom_minimum_size = Vector2(0, CHIP_H)
	chip.size = Vector2(_chip_width(tip), CHIP_H)
	chip.z_index = CONTENT_Z
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.focus_mode = Control.FOCUS_NONE
	chip.tooltip_text = tip
	# Centre pivot so the selected pulse grows from the middle.
	chip.pivot_offset = chip.size / 2.0
	chip.set_meta("folder", folder)
	chip.set_meta("stem", stem)
	chip.set_meta("selected", false)
	chip.set_meta("blocked", false)
	_apply_chip_style(chip, "secondary")
	add_child(chip)
	return chip


## ISSUE #178: style a chip AND put its real height back where the layout thinks
## it is. UIKit.style_button() points the button at a variant theme whose face
## carries btn_pad_v as a content margin — 13px top and bottom, which forces a
## ~48px minimum on a 38px chip. Duplicating the four state boxes and re-margining
## them is the only way to shrink it without giving up the baked pill art.
##
## ALWAYS use this instead of style_button() on this screen, including on re-style
## (selection swaps the theme back and the overrides would then draw the wrong
## variant's texture).
func _apply_chip_style(btn: Button, variant: String) -> void:
	UIKit.style_button(btn, variant)
	btn.add_theme_font_size_override("font_size", CHIP_FONT)
	_tighten(btn, CHIP_PAD_X, CHIP_PAD_Y)


## Re-margins a themed button's normal/hover/pressed/disabled faces in place.
func _tighten(btn: Button, pad_x: float, pad_y: float) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBox = btn.get_theme_stylebox(state, "Button")
		if box == null:
			continue
		var dup: StyleBox = box.duplicate()
		dup.content_margin_left = pad_x
		dup.content_margin_right = pad_x
		dup.content_margin_top = pad_y
		dup.content_margin_bottom = pad_y
		btn.add_theme_stylebox_override(state, dup)


func _make_icon_h(folder: String, stem: String, height: float, pos: Vector2, tip: String) -> Control:
	# Identical to _make_icon now - a chip is sized by its text, not by art aspect.
	# Kept as its own name so the rows that used the height-fitted variant read the
	# way they always did.
	return _make_icon(folder, stem, height, pos, tip)


## Width a chip needs for its label, floored so the short ones do not look starved.
func _chip_width(text: String) -> float:
	var f: Font = UITheme.font("button")
	var w: float = f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
		CHIP_FONT).x + CHIP_PAD_X * 2.0
	return maxf(w, CHIP_MIN_W)


## Lays a run of chips left to right from CTRL_X, wrapping to a new line when the
## next one would pass the right margin. Returns the y AFTER the last line.
##
## This replaces the fixed-pitch maths every icon row used. A pitch only works
## when every cell is the same width; chips are as wide as their words, and the
## SET row in particular runs from "Base" to "EX Team Magma vs Team Aqua".
func _flow_chips(entries: Array, y: float, category: String, store: Dictionary) -> float:
	var x := CTRL_X
	var line_y := y
	for entry in entries:
		var key: String = String(entry["key"])
		var w := _chip_width(String(entry["tip"]))
		if x > CTRL_X and x + w > CTRL_X + CTRL_W:
			x = CTRL_X
			line_y += CHIP_H + CHIP_GAP_Y
		var chip := _make_icon("", key, CHIP_H, Vector2(x, line_y), String(entry["tip"]))
		chip.gui_input.connect(_on_icon_input.bind(chip, category, key))
		store[key] = chip
		x += w + CHIP_GAP_X
	return line_y + CHIP_H


func _make_button(text: String, x: float, y: float, w: float, font_size: int) -> Button:
	var btn := Button.new()
	btn.theme = _theme_white
	btn.text  = text
	# ISSUE #226: these are built by hand rather than through UIKit.style_button,
	# so they kept Godot's fire-on-RELEASE default while every other button in the
	# game fires on press.
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.add_theme_font_size_override("font_size", font_size)
	btn.position = Vector2(x, y)
	btn.size     = Vector2(w, BTN_H)
	btn.custom_minimum_size = Vector2(w, BTN_H)
	btn.z_index  = CONTENT_Z
	_tighten(btn, 10.0, BTN_PAD_Y)   # ISSUE #178
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
## Paints a type chip in its energy colour. The selected state keeps the colour
## and gains the accent border, so the row still reads as a colour key when a
## type is chosen.
func _tint_type_chip(chip: Control, type_key: String, selected: bool) -> void:
	if not (chip is Button):
		return
	var b := chip as Button
	var fill := UITheme.energy_colour(type_key.capitalize())
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill if selected else Color(fill.r, fill.g, fill.b, 0.45)
	sb.set_corner_radius_all(UITheme.mi("corner_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left = CHIP_PAD_X
	sb.content_margin_right = CHIP_PAD_X
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if selected:
		sb.set_border_width_all(2)
		sb.border_color = Color.WHITE
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", UITheme.energy_fg(type_key.capitalize()))
	b.add_theme_font_size_override("font_size", CHIP_FONT)


func _set_icon_selected(icon: Control, selected: bool, force: bool = false) -> void:
	if not force and bool(icon.get_meta("selected", false)) == selected:
		return
	icon.set_meta("selected", selected)

	if icon is Button:
		var type_key := String(icon.get_meta("stem", ""))
		if _type_icons.has(type_key):
			_tint_type_chip(icon, type_key, selected)
		else:
			# ISSUE #178: _apply_chip_style, not style_button — it re-tightens the
			# state boxes the theme swap just brought back at full padding.
			_apply_chip_style(icon as Button, "selected" if selected else "secondary")
		(icon as Button).add_theme_font_size_override("font_size", CHIP_FONT)

	var old = icon.get_meta("pulse", null)
	if old != null:
		old.kill()
	icon.set_meta("pulse", null)

	icon.scale = Vector2.ONE
	icon.modulate = Color.WHITE

	# ISSUE #254: NO PULSE. A chip that grows and shrinks forever is the only
	# control in the game that does, and it fights the thing it is trying to say -
	# a filter is either on or off, which is a STATE, and the rest of the game
	# spells a state out with the "selected" button skin. The chips already switch
	# to it above (and type chips to their own filled colour), so the animation was
	# doing nothing the colour was not doing better. Options buttons behave exactly
	# this way and always have.
	if selected:
		print("ISSUE #254 FIX ACTIVE: chip '", icon.get_meta("stem", "?"),
			"' selected - skin swap, no pulse")


func _set_icon_blocked(icon: Control, blocked: bool, selected: bool) -> void:
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
	_tighten(btn, 10.0, BTN_PAD_Y)   # ISSUE #178 — the theme swap restores full padding


## A card type button that is forced on by another row's selection: it stays green (so it still
## reads as selected) but can't be clicked, because it isn't the player's choice to make while the
## row that implied it still has something in it.
func _set_button_locked_on(btn: Button) -> void:
	btn.theme = _theme_green
	btn.disabled = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.29, 0.71, 0.24, 1.0)
	# ISSUE #184 / #178: match the pill radius and the tightened row height.
	sb.set_corner_radius_all(UITheme.mi("btn_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left   = 10.0
	sb.content_margin_right  = 10.0
	sb.content_margin_top    = BTN_PAD_Y
	sb.content_margin_bottom = BTN_PAD_Y
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color.WHITE)


## A button blocked out by the opposite supertype's lock — greyed exactly like the deck screen's
## disabled set-navigation arrows.
func _set_button_blocked(btn: Button) -> void:
	btn.theme = _theme_white
	btn.disabled = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.67, 0.67, 0.67, 1.0)
	# ISSUE #184 / #178: match the pill radius and the tightened row height.
	sb.set_corner_radius_all(UITheme.mi("btn_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left   = 10.0
	sb.content_margin_right  = 10.0
	sb.content_margin_top    = BTN_PAD_Y
	sb.content_margin_bottom = BTN_PAD_Y
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
func _on_icon_input(event: InputEvent, icon: Control, category: String, key: String) -> void:
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
		UIKit.style_button(_confirm_btn, "primary")
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
