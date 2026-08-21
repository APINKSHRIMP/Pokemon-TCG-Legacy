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
#     type) auto-select their implied Card Type and lock out the opposite supertype. See _apply_lock.

signal search_confirmed(criteria: Dictionary)
signal search_cancelled()
## RESET was pressed. The screen has already blanked its own selections; the listener is expected to
## drop any search currently applied to the grid behind, so the two can't disagree.
signal search_reset()


# ══════════════════════════════════════════════════════════════════════════════
# TWEAKABLE VALUES — all screen geometry lives here
# ══════════════════════════════════════════════════════════════════════════════

# Header / footer bands and the vertical strip the filter rows flow down
const HEADER_H      := 96.0
const CONTENT_TOP   := 112.0
const FOOTER_TOP    := 992.0

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

# Left-hand label column, and the x the controls start at
const LABEL_X     := 52.0
const LABEL_W     := 250.0
const LABEL_FONT  := 24
const LABEL_COLOR := Color(0.05, 0.05, 0.05, 1.0)
const CTRL_X      := 312.0

# Vertical gap left between one filter row and the next
const ROW_GAP := 16.0

# Pokemon type icon row (single line, 9 icons)
const TYPE_ICON  := 54.0
const TYPE_PITCH := 66.0

# Set icon rows. Icons are drawn into a square cell with the aspect preserved, because the source
# art ranges from 41x21 (Base) to 128x128 (Southern Islands).
const SET_ICON      := 54.0
const SET_PITCH     := 74.0
const SET_LINE_GAP  := 8.0
# Up to this many unlocked sets renders as ONE line; more than this splits over two balanced lines.
const SET_SINGLE_LINE_MAX := 12

# Pokemon sub type icons (ex / shining-star / delta / dual type) — bigger, they read as glyphs
# rather than badges
const SUB_ICON  := 62.0
const SUB_PITCH := 104.0

# Rarity symbol icons
const RARITY_ICON  := 54.0
const RARITY_PITCH := 90.0

# Effect icon rows (reserved — see EFFECT_FILTERS)
const EFFECT_ICON     := 54.0
const EFFECT_PITCH    := 74.0
const EFFECT_LINE_GAP := 8.0
const EFFECT_SINGLE_LINE_MAX := 12

# Kenney text buttons
const BTN_H            := 52.0
const BTN_GAP          := 22.0
const CARD_TYPE_BTN_W  := 220.0
const STAGE_BTN_W      := 190.0
const TRAINER_BTN_W    := 230.0
const SORT_BTN_W       := 190.0
const BTN_FONT         := 22
const BTN_FONT_SMALL   := 15    # "TECHNICAL MACHINE" only

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
var _effect_icons  : Dictionary = {}
var _card_type_btn : Dictionary = {}
var _stage_btn     : Dictionary = {}
var _trainer_btn   : Dictionary = {}
var _sort_btn      : Dictionary = {}

var _name_edit    : LineEdit = null
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
	title.z_index  = 55
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var reset := Button.new()
	reset.theme = _theme_red
	reset.text  = "RESET"
	reset.add_theme_font_size_override("font_size", BTN_FONT)
	reset.position = Vector2(RESET_X, RESET_Y)
	reset.size     = Vector2(RESET_W, RESET_H)
	reset.custom_minimum_size = Vector2(RESET_W, RESET_H)
	reset.z_index  = 55
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
	_confirm_btn.z_index  = 55
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_btn)

	var cancel := Button.new()
	cancel.theme = _theme_red
	cancel.text  = "CANCEL"
	cancel.add_theme_font_size_override("font_size", BTN_FONT)
	cancel.position = Vector2(CANCEL_X, FOOT_BTN_Y)
	cancel.size     = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	cancel.custom_minimum_size = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	cancel.z_index  = 55
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
	y = _build_rarity_row(y)
	y = _build_effect_row(y)
	y = _build_sort_row(y)


func _build_name_row(y: float) -> float:
	var h := 72.0
	_add_row_label("NAME", y, h)

	_name_edit = LineEdit.new()
	_name_edit.theme = _theme_white
	_name_edit.position = Vector2(CTRL_X, y)
	_name_edit.size     = Vector2(1110.0, h)
	_name_edit.custom_minimum_size = Vector2(1110.0, h)
	_name_edit.add_theme_font_size_override("font_size", 30)
	_name_edit.add_theme_color_override("font_color", Color.BLACK)
	_name_edit.placeholder_text = "Card name....."
	_name_edit.max_length = 30
	_name_edit.z_index = 55
	_name_edit.text_changed.connect(_on_name_changed)
	# Enter in the name box runs the search, as long as something is actually filled in
	_name_edit.text_submitted.connect(func(_t: String): _on_confirm_pressed())
	add_child(_name_edit)

	return y + h + ROW_GAP


func _build_type_row(y: float) -> float:
	_add_row_label("POKEMON\nTYPE", y, TYPE_ICON)

	var x := CTRL_X
	for entry in POKEMON_TYPES:
		var key : String = entry["key"]
		var icon := _make_icon(ENERGY_ICON_PATH, entry["icon"], TYPE_ICON, Vector2(x, y), key)
		icon.gui_input.connect(_on_icon_input.bind(icon, "type", key))
		_type_icons[key] = icon
		x += TYPE_PITCH

	return y + TYPE_ICON + ROW_GAP


func _build_set_row(y: float) -> float:
	# Only sets the player has unlocked get an icon, in release order.
	var shown : Array = []
	for entry in _set_list:
		var sid : String = entry["set_id"]
		if sid in _unlocked:
			shown.append(entry)

	if shown.is_empty():
		return y

	var lines := 1 if shown.size() <= SET_SINGLE_LINE_MAX else 2
	var per_line : int = int(ceil(float(shown.size()) / float(lines)))
	var block_h := lines * SET_ICON + (lines - 1) * SET_LINE_GAP

	_add_row_label("SET", y, block_h)

	for i in range(shown.size()):
		var entry : Dictionary = shown[i]
		var sid   : String     = entry["set_id"]
		var line  : int        = i / per_line
		var col   : int        = i % per_line
		var pos := Vector2(
			CTRL_X + col * SET_PITCH,
			y + line * (SET_ICON + SET_LINE_GAP)
		)
		var icon := _make_icon(SET_ICON_PATH, sid, SET_ICON, pos, entry["set_name"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "set", sid))
		_set_icons[sid] = icon

	return y + block_h + ROW_GAP


func _build_card_type_row(y: float) -> float:
	_add_row_label("CARD\nTYPE", y, BTN_H)

	var x := CTRL_X
	for entry in CARD_TYPES:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, CARD_TYPE_BTN_W, BTN_FONT)
		btn.pressed.connect(_on_card_type_pressed.bind(key))
		_card_type_btn[key] = btn
		x += CARD_TYPE_BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_stage_row(y: float) -> float:
	var shown := _visible_options(STAGES)
	if shown.is_empty():
		return y

	_add_row_label("POKEMON\nSTAGE", y, BTN_H)

	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var btn := _make_button(entry["label"], x, y, STAGE_BTN_W, BTN_FONT)
		btn.pressed.connect(_on_simple_toggle.bind("stage", key))
		_stage_btn[key] = btn
		x += STAGE_BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_trainer_sub_row(y: float) -> float:
	var shown := _visible_options(TRAINER_SUBS)
	if shown.is_empty():
		return y

	_add_row_label("TRAINER\nSUB TYPE", y, BTN_H)

	var x := CTRL_X
	for entry in shown:
		var key   : String = entry["key"]
		var label : String = entry["label"]
		# "TECHNICAL MACHINE" is far longer than the others — drop it to two lines at a smaller size
		# rather than widening every button in the row.
		var font  : int    = BTN_FONT_SMALL if key == "Technical Machine" else BTN_FONT
		var text  : String = "TECHNICAL\nMACHINE" if key == "Technical Machine" else label
		var btn := _make_button(text, x, y, TRAINER_BTN_W, font)
		btn.pressed.connect(_on_simple_toggle.bind("trainer_sub", key))
		_trainer_btn[key] = btn
		x += TRAINER_BTN_W + BTN_GAP

	return y + BTN_H + ROW_GAP


func _build_pokemon_sub_row(y: float) -> float:
	var shown := _visible_options(POKEMON_SUBS)
	if shown.is_empty():
		return y

	_add_row_label("POKEMON\nSUB TYPE", y, SUB_ICON)

	var x := CTRL_X
	for entry in shown:
		var key : String = entry["key"]
		var icon := _make_icon(SUBTYPE_ICON_PATH, entry["icon"], SUB_ICON, Vector2(x, y), entry["tip"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "pokemon_sub", key))
		_sub_icons[key] = icon
		x += SUB_PITCH

	return y + SUB_ICON + ROW_GAP


## Rarity is a whole-card property (Pokemon, Trainer and Energy all carry one), so unlike the stage
## and sub type rows it takes no part in the Pokemon/Trainer supertype lock.
func _build_rarity_row(y: float) -> float:
	_add_row_label("RARITY", y, RARITY_ICON)

	var x := CTRL_X
	for entry in RARITIES:
		var key : String = entry["key"]
		var icon := _make_icon(RARITY_ICON_PATH, entry["icon"], RARITY_ICON, Vector2(x, y), entry["tip"])
		icon.gui_input.connect(_on_icon_input.bind(icon, "rarity", key))
		_rarity_icons[key] = icon
		x += RARITY_PITCH

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

	_add_row_label("EFFECT", y, block_h)

	for i in range(shown.size()):
		var entry : Dictionary = shown[i]
		var key   : String     = entry["key"]
		var line  : int        = i / per_line
		var col   : int        = i % per_line
		var pos := Vector2(
			CTRL_X + col * EFFECT_PITCH,
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
		var btn := _make_button(entry["label"], x, y, SORT_BTN_W, BTN_FONT)
		btn.pressed.connect(_on_sort_pressed.bind(key))
		_sort_btn[key] = btn
		x += SORT_BTN_W + BTN_GAP

	_refresh_sort_buttons()
	return y + BTN_H + ROW_GAP


# ══════════════════════════════════════════════════════════════════════════════
# Build helpers
# ══════════════════════════════════════════════════════════════════════════════

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
	lbl.z_index  = 55
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
	icon.z_index = 55
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.tooltip_text = tip
	# Remembered so _set_icon_selected can swap between icon_ / color_icon_ art later
	icon.set_meta("folder", folder)
	icon.set_meta("stem", stem)
	icon.set_meta("selected", false)
	icon.set_meta("blocked", false)
	add_child(icon)
	return icon


func _make_button(text: String, x: float, y: float, w: float, font_size: int) -> Button:
	var btn := Button.new()
	btn.theme = _theme_white
	btn.text  = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.position = Vector2(x, y)
	btn.size     = Vector2(w, BTN_H)
	btn.custom_minimum_size = Vector2(w, BTN_H)
	btn.z_index  = 55
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
		"effect":      return _sel_effects
	return {}


# ══════════════════════════════════════════════════════════════════════════════
# Card type lock
# ══════════════════════════════════════════════════════════════════════════════

# Rows that can only ever describe a Pokemon, and rows that can only ever describe a Trainer.
# Selecting anything in either group locks the Card Type row to that supertype and blocks the
# opposite group, because the combination could never match a card.

func _pokemon_rows_selected() -> bool:
	return not _sel_types.is_empty() or not _sel_stages.is_empty() or not _sel_pokemon_subs.is_empty()


func _trainer_rows_selected() -> bool:
	return not _sel_trainer_subs.is_empty()


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
			# player picked by hand survives (this is the one-way rule — a sub type implies a card
			# type, but a card type never implies or clears a sub type).
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

	# ── Pokemon-only rows: blocked while a Trainer sub type is selected ──
	var block_pokemon := lock == "Trainer"
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

	# ── Trainer-only row: blocked while any Pokemon-only row is selected ──
	var block_trainer := lock == "Pokémon"
	for key in _trainer_btn:
		var tbtn : Button = _trainer_btn[key]
		_clear_button_overrides(tbtn)
		if block_trainer:
			_set_button_blocked(tbtn)
		else:
			_set_button_selected(tbtn, _sel_trainer_subs.has(key), _theme_green)


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
	return not (_sel_types.is_empty() and _sel_sets.is_empty() and _sel_card_types.is_empty()
		and _sel_stages.is_empty() and _sel_trainer_subs.is_empty()
		and _sel_pokemon_subs.is_empty() and _sel_rarities.is_empty()
		and _sel_effects.is_empty())


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
	return {
		"name":         _name_edit.text.strip_edges().to_lower() if _name_edit != null else "",
		"types":        _sel_types.keys(),
		"sets":         _sel_sets.keys(),
		"card_types":   _sel_card_types.keys(),
		"stages":       _sel_stages.keys(),
		"trainer_subs": _sel_trainer_subs.keys(),
		"pokemon_subs": _sel_pokemon_subs.keys(),
		"rarities":     _sel_rarities.keys(),
		"effects":      _sel_effects.keys(),
		"sort":         _sort_mode,
	}
