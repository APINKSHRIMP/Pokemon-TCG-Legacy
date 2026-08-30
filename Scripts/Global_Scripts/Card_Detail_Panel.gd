class_name CardDetailPanel
extends Control

# ============================================================
# CARD DETAIL PANEL — the hold-Shift card preview
# ============================================================
# One Control that fills a 1920x1080 reference screen and draws:
#
#   +--------------------+  +--------------------------------+
#   |                    |  | NAME                  120HP (R)|  <- header
#   |                    |  +--------------------------------+
#   |   the card, at a   |  | rules (small)                  |  <- 0..n rule boxes
#   |   FIXED size, in   |  +--------------------------------+
#   |   the left half    |  | (POWER) NAME                   |  <- 0..n ability boxes
#   |                    |  | body text                      |
#   |                    |  +--------------------------------+
#   |                    |  | (R)(C)  ATTACK NAME        120 |  <- 0..n attack boxes
#   |                    |  | body text                      |
#   |                    |  +--------------------------------+
#   |                    |  | WEAKNESS RESISTANCE   RETREAT  |  <- Pokemon only
#   |                    |  +--------------------------------+
#   |                    |  | (set) SET NAME                 |  <- meta
#   |                    |  | (rar) RARITY / Illus. ARTIST   |
#   +--------------------+  +--------------------------------+
#
# Used by the deck builder and by a match. The sleeve, coin and costume
# previews are deliberately NOT routed through here — they show one image and
# have no card data behind them.
#
# USAGE
#   var panel := CardDetailPanel.new()
#   overlay_canvas_layer.add_child(panel)
#   panel.show_card("ex14-4")     # call again on every hover change
#
# Everything is mouse_filter IGNORE. Both call sites find the hovered card with
# gui_get_hovered_control() / a rect hit-test against the board, so this panel
# must never eat a hover or the preview would freeze on its first card.
#
# ── WHY THE BOXES ARE MEASURED BY HAND ───────────────────────
# Body text can carry inline energy icons, so RichTextLabel's own wrapping
# can't be predicted from Font.get_multiline_string_size(). Instead the text is
# tokenised, wrapped here, and handed to the label as explicit lines with
# autowrap OFF — so the line count used to size the box is exactly the line
# count that gets drawn. Kenney has no kerning or GPOS table, so per-word
# widths are purely additive and the measurement is exact rather than close.
# ============================================================

const SHADER_PATH := "res://Scripts/Shaders/Rounded_Message_Panel.gdshader"
const FONT_PATH   := "res://UI_Themes/ChakraPetch-Medium.ttf"

const ENERGY_ICON_DIR  := "res://Image_Assets/Icons/Energy_Icons/"
const SUBTYPE_ICON_DIR := "res://Image_Assets/Icons/Subtype_Icons/"
const SET_ICON_DIR     := "res://Image_Assets/Icons/Set_Icons/"
const RARITY_ICON_DIR  := "res://Image_Assets/Icons/Rarity_Icons/"
const CARD_IMAGE_DIR   := "res://Image_Assets/Card_Image_Library/"
const CARD_DATA_DIR    := "res://Card_Set_Data/"
const SET_NAMES_PATH   := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"

# ══════════════════════════════════════════════════════════════════════════
# TWEAKABLE LAYOUT — every number the design depends on lives in this block
# ══════════════════════════════════════════════════════════════════════════

const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# The card sits down the LEFT, as tall as it can be with this much clear above
# and below it. Every card is drawn at the SAME size and shape — the source art
# ranges from 0.717 to 0.727 w/h, so it is stretched to CARD_ASPECT rather than
# fitted, which keeps the preview from resizing as the mouse moves card to card.
const MARGIN_TOP    : float = 20.0
const MARGIN_BOTTOM : float = 20.0
const CARD_ASPECT   : float = 600.0 / 825.0   # the most common source ratio

# ── Horizontal placement ─────────────────────────────────────
# The card is NOT centred in the left half. Centring left a ~124px gutter down
# the screen edge against a ~25px gap to the boxes, which read as lopsided and
# wasted the width the boxes wanted. These three numbers plus the card's width
# account for the full 1920, so changing one moves everything predictably.
const CARD_MARGIN_LEFT    : float = 36.0   # screen edge -> card
const CARD_TO_PANEL_GAP   : float = 26.0   # card -> first box
const PANEL_MARGIN_RIGHT  : float = 22.0   # last box -> screen edge

const BOX_GAP    : float = 9.0    # vertical gap between one box and the next
const BOX_PAD_X  : float = 44.0   # box edge -> content; must clear the edge glow
const BOX_PAD_Y  : float = 17.0   # white space above and below a box's content
const CORNER_R   : float = 34.0

# Border glow, matching DynamicMessageBox: a wide band down the sides, a
# hairline along the top and bottom.
const EDGE_SOLID : Vector2 = Vector2(26.0, 2.0)
const EDGE_FADE  : Vector2 = Vector2(12.0, 4.0)

# Font sizes. NAME/SUBTYPE are one line each and never shrink; the rest come
# down together if a card somehow can't fit (see SHRINK_FLOOR).
const FONT_NAME    : int = 46
const FONT_SUBTYPE : int = 30
const FONT_SECTION : int = 30   # ability and attack names
const FONT_BODY    : int = 24   # effect text
const FONT_RULE    : int = 19   # the ex / Star / Supporter / Stadium boilerplate
const FONT_META    : int = 26   # set name, rarity, illustrator
const FONT_HP      : int = 46   # ceiling only — the HP is drawn at the fitted name size
const FONT_DAMAGE  : int = 34
const FONT_WRR     : int = 26   # WEAKNESS / RESISTANCE / RETREAT COST captions
const SHRINK_FLOOR : int = 8    # most steps the body/section/rule sizes may drop

# Floors for the three pieces of text that are fitted to their own row rather
# than to the height of the whole stack: the card's name, its subtype line, and
# an ability/attack name centred between the cost icons and the damage.
const FONT_NAME_MIN    : int = 26
const FONT_SUBTYPE_MIN : int = 18
const FONT_TITLE_MIN   : int = 16

# Icon sizes
const TYPE_ICON   : float = 54.0   # the Pokemon's type, top right of the header
const COST_ICON   : float = 46.0   # an attack's energy cost
const WRR_ICON    : float = 46.0   # weakness / resistance / retreat cost
const BADGE_H     : float = 34.0   # the Poke-POWER / Poke-BODY pill
const SET_ICON    : float = 46.0
const RARITY_ICON : float = 40.0
const ICON_GAP    : float = 8.0    # between two icons in a row
const INLINE_ICON_RATIO : float = 1.0   # inline energy icon height, x body font size

# Row spacing inside a box
const TITLE_TO_BODY : float = 12.0  # ability/attack name row -> its body text
const LINE_SEPARATION : int = 3     # extra px between two lines of body text
const WRR_LABEL_GAP : float = 8.0   # caption -> the icons under it
const META_ROW_GAP  : float = 6.0

# A boilerplate rule reads better on one line even at a smaller size, so a rule
# box steps its font down looking for a size that fits on one line, then two.
# The Supporter and Stadium reminders are far too long for one line at any
# sensible size and settle on two, which is what the design asks for.
const FONT_RULE_MIN : int = 15

# ── Border colour per card ───────────────────────────────────
# Pokemon and basic energy take their type's colour. Everything else lands on
# one of five greys: Colorless is the lightest, then Trainers, then the special
# energies with no type in their name; Metal is a grey nudged toward gold and
# Darkness is very nearly black.
const TYPE_COLORS : Dictionary = {
	"Grass":     Color("#5fbb4a"),
	"Fire":      Color("#e8412d"),
	"Water":     Color("#3b93e8"),
	"Lightning": Color("#f2c31c"),
	"Psychic":   Color("#9b52c9"),
	"Fighting":  Color("#c4622a"),
	"Colorless": Color("#dcdce2"),   # grey 1 — lightest
	"Metal":     Color("#8d8674"),   # grey 4 — faintly gold
	"Darkness":  Color("#2b2b31"),   # grey 5 — near black
}
const COLOR_TRAINER        : Color = Color("#9a9aa6")   # grey 2
const COLOR_SPECIAL_ENERGY : Color = Color("#5c5c66")   # grey 3

# Name fragments that give a special energy a colour, tried IN THIS ORDER so
# the FIRST type mentioned wins ("Dark Metal Energy" reads as Darkness).
# Anything that matches nothing here (Rainbow, Multi, Crystal, Boost, React,
# Scramble, Holon...) falls through to COLOR_SPECIAL_ENERGY.
const ENERGY_NAME_COLORS : Array = [
	["colorless", "Colorless"],
	["darkness",  "Darkness"],
	["dark",      "Darkness"],
	["lightning", "Lightning"],
	["fighting",  "Fighting"],
	["psychic",   "Psychic"],
	["metal",     "Metal"],
	["water",     "Water"],
	["aqua",      "Water"],
	["grass",     "Grass"],
	["fire",      "Fire"],
	["magma",     "Fire"],
]

# ── Rarity ───────────────────────────────────────────────────
# Icon stem + the label shown beside it. Anything rarer than Rare Holo shares
# the COLOUR holo icon, which reads as "rarer than the plain holo symbol".
# A card with no rarity key at all is either a Southern Islands card or a basic
# energy (which never reaches here — it has no meta box at all).
const RARITY_TABLE : Dictionary = {
	"Common":         { "icon": "icon_common",        "label": "Common" },
	"Uncommon":       { "icon": "icon_uncommon",      "label": "Uncommon" },
	"Rare":           { "icon": "icon_rare",          "label": "Rare" },
	"Rare Holo":      { "icon": "icon_holorare",      "label": "Holo Rare" },
	"Rare Holo EX":   { "icon": "color_icon_holorare","label": "Holo Rare EX" },
	"Rare Holo Star": { "icon": "color_icon_holorare","label": "Holo Rare Star" },
	"Rare Shining":   { "icon": "color_icon_holorare","label": "Shining Rare" },
	"Rare Secret":    { "icon": "color_icon_holorare","label": "Secret Rare" },
	"Promo":          { "icon": "icon_promo",         "label": "Promo" },
}
const RARITY_FALLBACK : Dictionary = { "icon": "icon_special", "label": "Special" }

# ── Energy types, for the text -> icon substitution ──────────
# Longest first so the alternation in the regex can't stop early inside a
# glued run like "MetalColorless".
const ENERGY_TYPES : Array = [
	"Colorless", "Lightning", "Fighting", "Darkness", "Psychic",
	"Water", "Grass", "Metal", "Fire",
]

# A type word becomes an icon when the word AFTER it is one of these. Anything
# else and it is left as text, because a capitalised word following a type is
# almost always part of a card or attack NAME — "Water Cube 01", "Lightning
# Rod", "Psychic Force", "Metal Gravity".
const ICONISE_FOLLOWERS : Array = [
	"Energy", "energy", "Pokémon", "Pokemon", "pokémon", "pokemon",
	"basic", "Basic", "less", "more",
]

# Separators allowed between two members of a type LIST. "Fire, Water, or
# Psychic Pokémon" iconises all three because the LAST one qualifies above and
# everything between them is nothing but these.
const LIST_SEPARATORS := ",/ orand"   # char set: , / space o r a n d

# Rules text that is boilerplate rather than card effect, so it renders in the
# small single-line rule style. Matched as a prefix, case sensitive.
const BOILERPLATE_PREFIXES : Array = [
	"When Pokémon-ex has been Knocked Out",
	"You can't have more than 1 Pokémon Star",
	"You can't have more than 1 Shining",
	"You may have up to 4 Basic Pokémon cards in your deck with Unown",
	"You can play only one Supporter card each turn",
	"You can play only 1 Supporter card each turn",
	"This card stays in play",
	"If your Active Pokémon is a Baby Pokémon",
	"If this Baby Pokémon is your Active Pokémon",
]

# The dual-type reminder is dropped entirely — the two energy icons in the
# header already say it, and the sentence is pure noise next to them.
const DUAL_TYPE_PREFIX := "This Pokémon is both "

# The card data spells the Pokemon Star symbol out as the word "Star" in its
# deck-limit rule, while the card's NAME already carries the real glyph
# ("Flareon ★"). Swapped here so the rule matches the name it refers to.
const STAR_RULE_WORD   := "Pokémon Star"
const STAR_RULE_SYMBOL := "Pokémon ★"

# System fonts tried, in order, for the glyphs Kenney simply does not have:
# delta, star, the Nidoran genders and the e-card Greek letters. Segoe UI
# Symbol is the only one of the three that carries all of them.
const FALLBACK_FONT_PATHS : Array = [
	"C:/Windows/Fonts/seguisym.ttf",
	"C:/Windows/Fonts/arial.ttf",
	"C:/Windows/Fonts/segoeui.ttf",
]


# ══════════════════════════════════════════════════════════════════════════
# Static caches — shared by the deck builder and the match
# ══════════════════════════════════════════════════════════════════════════

static var _set_cache      : Dictionary = {}   # set_id -> Array of card dicts
static var _card_cache     : Dictionary = {}   # card_uid -> card dict
static var _tex_cache      : Dictionary = {}   # res path -> Texture2D (or null)
static var _set_names      : Dictionary = {}   # set_id -> display name
static var _base_font      : FontFile   = null
static var _font           : FontVariation = null
static var _font_warned    : bool = false
static var _type_run_regex : RegEx = null


# ══════════════════════════════════════════════════════════════════════════
# Instance state
# ══════════════════════════════════════════════════════════════════════════

var _card_image : TextureRect = null
var _box_root   : Control = null
var _current_uid : String = ""


func _init() -> void:
	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = SCREEN_W
	offset_bottom = SCREEN_H
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	_card_image = TextureRect.new()
	_card_image.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.stretch_mode = TextureRect.STRETCH_SCALE
	_card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_image.size     = Vector2(card_width(), card_height())
	_card_image.position = Vector2(card_left(), MARGIN_TOP)
	add_child(_card_image)

	_box_root = Control.new()
	_box_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box_root)


# ── Card rect, exposed so a caller can line anything else up with it ──
static func card_height() -> float:
	return SCREEN_H - MARGIN_TOP - MARGIN_BOTTOM

static func card_width() -> float:
	return card_height() * CARD_ASPECT

static func card_left() -> float:
	return CARD_MARGIN_LEFT

## Left edge of the info column: hard against the card, not against the screen's
## middle, so every pixel the card doesn't use goes to the text.
static func panel_x0() -> float:
	return CARD_MARGIN_LEFT + card_width() + CARD_TO_PANEL_GAP

static func panel_x1() -> float:
	return SCREEN_W - PANEL_MARGIN_RIGHT


# ══════════════════════════════════════════════════════════════════════════
# PUBLIC
# ══════════════════════════════════════════════════════════════════════════

## Shows a card. Safe to call every frame — a repeat of the card already on
## screen is ignored, so the hover-tracking in both call sites can just fire.
func show_card(card_uid: String) -> void:
	var uid := card_uid.strip_edges()
	if uid == "" or uid == _current_uid:
		return
	_current_uid = uid

	var tex := _load_texture(_card_image_path(uid))
	if tex == null:
		push_error("CardDetailPanel: missing large card image for " + uid)
	_card_image.texture = tex

	for child in _box_root.get_children():
		_box_root.remove_child(child)
		child.queue_free()

	var card := card_metadata(uid)
	if card.is_empty():
		push_error("CardDetailPanel: no card data for " + uid)
		return

	_build(card)


## Loads (and caches) one card's JSON. Public so callers can ask questions
## about the card they are previewing without a second file read.
static func card_metadata(card_uid: String) -> Dictionary:
	var uid := card_uid.strip_edges().to_lower()
	if _card_cache.has(uid):
		return _card_cache[uid]

	var parts := uid.split("-")
	if parts.size() < 2:
		return {}
	var set_id := parts[0]

	if not _set_cache.has(set_id):
		var loaded: Array = []
		var path := CARD_DATA_DIR + set_id + ".json"
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Array:
				loaded = parsed
		_set_cache[set_id] = loaded
		for entry in loaded:
			if entry is Dictionary:
				_card_cache[String(entry.get("id", "")).to_lower()] = entry

	return _card_cache.get(uid, {})


# ══════════════════════════════════════════════════════════════════════════
# BUILD — measure everything, shrink if it somehow doesn't fit, then draw
# ══════════════════════════════════════════════════════════════════════════

func _build(card: Dictionary) -> void:
	var fit := measure_stack(card)
	var border := _border_color(card)
	var y := MARGIN_TOP
	for m in fit["boxes"]:
		var h := float(m["height"])
		var box := _make_box(Vector2(panel_x0(), y), Vector2(panel_x1() - panel_x0(), h), border)
		_render_section(m, box)
		y += h + BOX_GAP


## Measures a card's whole box stack, stepping the body / section / rule sizes
## down together until it fits the screen. Returns the measured boxes, the
## shrink that was needed and the resulting height — the shrink is the
## guarantee behind "every card fits on one screen", and at the sizes above it
## only ever engages for a handful of the wordiest Pokemon in the game.
##
## Public so a test harness can ask what a card measures without drawing it.
func measure_stack(card: Dictionary) -> Dictionary:
	var avail := SCREEN_H - MARGIN_TOP - MARGIN_BOTTOM
	var sections := _describe(card)
	var shrink := 0
	var measured: Array = []
	var total := 0.0
	while true:
		measured = _measure_all(sections, shrink)
		total = BOX_GAP * float(maxi(measured.size() - 1, 0))
		for m in measured:
			total += float(m["height"])
		if total <= avail or shrink >= SHRINK_FLOOR:
			break
		shrink += 1
	return { "boxes": measured, "shrink": shrink, "height": total, "available": avail }


## Turns a card into an ordered list of section descriptors. This is the only
## place that decides WHAT gets its own box; _measure_all / _render_section
## only decide how big it is and how it is drawn.
func _describe(card: Dictionary) -> Array:
	var out: Array = []
	var supertype := String(card.get("supertype", ""))
	var subtypes  := _string_array(card.get("subtypes", []))
	var is_basic_energy := supertype == "Energy" and subtypes.has("Basic")

	out.append({ "kind": "header", "card": card })

	# rules[] does double duty in this data: on a Pokemon it is always
	# boilerplate, on a Trainer or Energy it is usually the card's actual
	# effect text with the boilerplate (if any) sitting in front of it.
	for entry in _string_array(card.get("rules", [])):
		if entry.begins_with(DUAL_TYPE_PREFIX):
			continue                                   # said by the header icons
		# Classify on the RAW text — BOILERPLATE_PREFIXES matches the wording in
		# the data — then swap the star word in for display only.
		var kind := "rule" if _is_boilerplate(entry) else "effect"
		out.append({ "kind": kind, "text": entry.replace(STAR_RULE_WORD, STAR_RULE_SYMBOL) })

	for ability in _dict_array(card.get("abilities", [])):
		out.append({ "kind": "ability", "ability": ability, "card": card })

	for attack in _dict_array(card.get("attacks", [])):
		out.append({ "kind": "attack", "attack": attack, "card": card })

	if supertype == "Pokémon":
		out.append({ "kind": "wrr", "card": card })

	# Basic energy is handed out by the game rather than pulled from a pack, so
	# it has no rarity and its set is meaningless — the name box is the whole
	# card.
	if not is_basic_energy:
		out.append({ "kind": "meta", "card": card })

	return out


## True for a rules entry that is a printed reminder rather than the card
## doing something. These render small, on as few lines as they will go.
func _is_boilerplate(text: String) -> bool:
	for prefix in BOILERPLATE_PREFIXES:
		if text.begins_with(prefix):
			return true
	# Every Pokemon Tool opens with the same "attach me to something that
	# hasn't already got a Tool" sentence; the line after it is the real effect.
	if text.begins_with("Attach ") and text.contains("Pokémon Tool"):
		return true
	return false


# ══════════════════════════════════════════════════════════════════════════
# MEASURE
# ══════════════════════════════════════════════════════════════════════════

func _measure_all(sections: Array, shrink: int) -> Array:
	var out: Array = []
	for section in sections:
		out.append(_measure(section, shrink))
	return out


func _measure(section: Dictionary, shrink: int) -> Dictionary:
	var kind := String(section["kind"])
	var m := section.duplicate()
	m["shrink"] = shrink
	var content_w := panel_x1() - panel_x0() - BOX_PAD_X * 2.0

	match kind:
		"header":
			var card: Dictionary = section["card"]
			# The name shares its row with the HP and the type icons, and a few
			# Trainer names are very long ("Impostor Professor Oak's Invention"
			# is 34 characters), so the name is fitted to whatever the right
			# side leaves it rather than being allowed to run underneath it.
			var right_w := _header_right_width(card)
			var name_size := _fit_text(String(card.get("name", "")),
									   content_w - right_w - ICON_GAP * 2.0,
									   FONT_NAME, FONT_NAME_MIN)
			var subtype := _subtype_line(card)
			var sub_size := _fit_text(subtype, content_w, FONT_SUBTYPE, FONT_SUBTYPE_MIN)
			var name_h := _line_height(String(card.get("name", "")), name_size)
			var right_h: float = TYPE_ICON if not _header_types(card).is_empty() else name_h
			var sub_h := _line_height(subtype, sub_size)
			m["name_size"] = name_size
			m["sub_size"]  = sub_size
			m["right_w"]   = right_w
			m["name_h"] = name_h
			m["sub_h"]  = sub_h
			m["height"] = BOX_PAD_Y + maxf(name_h, right_h) + sub_h + BOX_PAD_Y

		"rule":
			var size := _fit_rule_size(String(section["text"]), content_w, shrink)
			var lines := _wrap(_tokenise(String(section["text"]), size), content_w, size)
			m["size"]  = size
			m["lines"] = lines
			m["height"] = BOX_PAD_Y + _lines_height(lines, size) + BOX_PAD_Y

		"effect":
			var size2 := maxi(FONT_BODY - shrink, 12)
			var lines2 := _wrap(_tokenise(String(section["text"]), size2), content_w, size2)
			m["size"]  = size2
			m["lines"] = lines2
			m["height"] = BOX_PAD_Y + _lines_height(lines2, size2) + BOX_PAD_Y

		"ability":
			var ability: Dictionary = section["ability"]
			var body := maxi(FONT_BODY - shrink, 12)
			# The name is centred on the box's true middle, so the room it has
			# is whatever is left after mirroring the widest side — here, the
			# Poke-POWER / Poke-BODY pill on the left.
			var title := _fit_text(String(ability.get("name", "")),
								   _centred_room(content_w, _badge_width(ability), 0.0),
								   maxi(FONT_SECTION - shrink, 14), FONT_TITLE_MIN)
			var title_h := maxf(BADGE_H, _line_height(String(ability.get("name", "")), title))
			var h := BOX_PAD_Y + title_h
			var text := String(ability.get("text", ""))
			var lines3: Array = []
			if text != "":
				lines3 = _wrap(_tokenise(text, body), content_w, body)
				h += TITLE_TO_BODY + _lines_height(lines3, body)
			m["body_size"]  = body
			m["title_size"] = title
			m["title_h"]    = title_h
			m["lines"]      = lines3
			m["height"]     = h + BOX_PAD_Y

		"attack":
			var attack: Dictionary = section["attack"]
			var body2 := maxi(FONT_BODY - shrink, 12)
			var damage_size := maxi(FONT_DAMAGE - shrink, 14)
			var cost := _string_array(attack.get("cost", []))
			var cost_w := 0.0
			if not cost.is_empty():
				cost_w = float(cost.size()) * (COST_ICON + ICON_GAP)
			var damage_w := _text_width(String(attack.get("damage", "")), damage_size)
			var title2 := _fit_text(String(attack.get("name", "")),
									_centred_room(content_w, cost_w, damage_w),
									maxi(FONT_SECTION - shrink, 14), FONT_TITLE_MIN)
			var title_h2 := maxf(COST_ICON if not cost.is_empty() else 0.0,
								 _line_height(String(attack.get("name", "")), title2))
			title_h2 = maxf(title_h2, _line_height("0", damage_size))
			var h2 := BOX_PAD_Y + title_h2
			var text2 := String(attack.get("text", ""))
			var lines4: Array = []
			if text2 != "":
				lines4 = _wrap(_tokenise(text2, body2), content_w, body2)
				h2 += TITLE_TO_BODY + _lines_height(lines4, body2)
			m["body_size"]   = body2
			m["title_size"]  = title2
			m["damage_size"] = damage_size
			m["title_h"]     = title_h2
			m["lines"]       = lines4
			m["height"]      = h2 + BOX_PAD_Y

		"wrr":
			var cap := maxi(FONT_WRR - shrink, 14)
			m["cap_size"] = cap
			m["height"] = BOX_PAD_Y + _line_height("X", cap) + WRR_LABEL_GAP + WRR_ICON + BOX_PAD_Y

		"meta":
			# Three icon+text rows: the set, the rarity, then the illustrator.
			var meta := maxi(FONT_META - shrink, 14)
			var card2: Dictionary = section["card"]
			var row_h := maxf(SET_ICON, _line_height("X", meta))
			var rarity_row_h := maxf(RARITY_ICON, _line_height("X", meta))
			var h3 := BOX_PAD_Y + row_h + META_ROW_GAP + rarity_row_h
			if String(card2.get("artist", "")) != "":
				h3 += META_ROW_GAP + rarity_row_h
			m["meta_size"]     = meta
			m["row_h"]         = row_h
			m["rarity_row_h"]  = rarity_row_h
			m["height"]        = h3 + BOX_PAD_Y

	return m


# ══════════════════════════════════════════════════════════════════════════
# RENDER
# ══════════════════════════════════════════════════════════════════════════

func _render_section(m: Dictionary, box: ColorRect) -> void:
	match String(m["kind"]):
		"header":  _render_header(m, box)
		"rule":    _render_text_only(m, box, int(m["size"]))
		"effect":  _render_text_only(m, box, int(m["size"]))
		"ability": _render_ability(m, box)
		"attack":  _render_attack(m, box)
		"wrr":     _render_wrr(m, box)
		"meta":    _render_meta(m, box)


func _render_header(m: Dictionary, box: ColorRect) -> void:
	var card: Dictionary = m["card"]
	var x0 := BOX_PAD_X
	var x1 := box.size.x - BOX_PAD_X
	var name_size := int(m["name_size"])
	var name_h := float(m["name_h"])
	var right_h: float = maxf(name_h, TYPE_ICON)
	var top_row_h := maxf(name_h, right_h)

	# Type icons hug the right edge; the HP is pushed left of them. With no
	# types at all (Clefairy Doll, the Fossils) the HP ends flush right instead.
	var right_x := x1
	for type_name in _header_types(card):
		var tex := _load_texture(ENERGY_ICON_DIR + "color_icon_" + type_name.to_lower() + ".png")
		if tex == null:
			continue
		right_x -= TYPE_ICON
		_add_icon(box, tex, Vector2(right_x, BOX_PAD_Y + (top_row_h - TYPE_ICON) * 0.5),
				  Vector2(TYPE_ICON, TYPE_ICON))
		right_x -= ICON_GAP
	if right_x < x1:
		right_x += ICON_GAP        # undo the trailing gap after the last icon

	# HP is drawn at the same size as the name, as on a real card.
	var hp := String(card.get("hp", ""))
	if hp != "":
		var hp_text := hp + "HP"
		var hp_w := _text_width(hp_text, name_size)
		_add_label(box, hp_text, Vector2(right_x - ICON_GAP - hp_w, BOX_PAD_Y),
				   Vector2(hp_w, top_row_h), name_size, HORIZONTAL_ALIGNMENT_RIGHT)

	_add_label(box, String(card.get("name", "")), Vector2(x0, BOX_PAD_Y),
			   Vector2(x1 - x0, top_row_h), name_size, HORIZONTAL_ALIGNMENT_LEFT)

	_add_label(box, _subtype_line(card), Vector2(x0, BOX_PAD_Y + top_row_h),
			   Vector2(x1 - x0, float(m["sub_h"])), int(m["sub_size"]),
			   HORIZONTAL_ALIGNMENT_LEFT)


func _render_text_only(m: Dictionary, box: ColorRect, size: int) -> void:
	_add_rich(box, m["lines"], size, Vector2(BOX_PAD_X, BOX_PAD_Y),
			  box.size.x - BOX_PAD_X * 2.0)


func _render_ability(m: Dictionary, box: ColorRect) -> void:
	var ability: Dictionary = m["ability"]
	var title_h := float(m["title_h"])
	var title_size := int(m["title_size"])

	# The Poke-POWER / Poke-BODY pill, top left. Base Set's "Pokémon Power"
	# predates the split and is shown as a Power, which is what it behaves as.
	var stem := "power"
	if String(ability.get("type", "")).to_lower().contains("body"):
		stem = "body"
	var badge := _load_texture(SUBTYPE_ICON_DIR + "color_icon_" + stem + ".png")
	if badge != null:
		var ratio := badge.get_size().x / maxf(badge.get_size().y, 1.0)
		_add_icon(box, badge, Vector2(BOX_PAD_X, BOX_PAD_Y + (title_h - BADGE_H) * 0.5),
				  Vector2(BADGE_H * ratio, BADGE_H))

	_add_centred_title(box, String(ability.get("name", "")), title_size,
					   BOX_PAD_Y, title_h)

	if not (m["lines"] as Array).is_empty():
		_add_rich(box, m["lines"], int(m["body_size"]),
				  Vector2(BOX_PAD_X, BOX_PAD_Y + title_h + TITLE_TO_BODY),
				  box.size.x - BOX_PAD_X * 2.0)


func _render_attack(m: Dictionary, box: ColorRect) -> void:
	var attack: Dictionary = m["attack"]
	var title_h := float(m["title_h"])

	var x := BOX_PAD_X
	for type_name in _string_array(attack.get("cost", [])):
		var tex := _load_texture(ENERGY_ICON_DIR + "color_icon_" + type_name.to_lower() + ".png")
		if tex == null:
			continue
		_add_icon(box, tex, Vector2(x, BOX_PAD_Y + (title_h - COST_ICON) * 0.5),
				  Vector2(COST_ICON, COST_ICON))
		x += COST_ICON + ICON_GAP

	var damage := String(attack.get("damage", ""))
	if damage != "":
		var dsize := int(m["damage_size"])
		var dw := _text_width(damage, dsize)
		_add_label(box, damage, Vector2(box.size.x - BOX_PAD_X - dw, BOX_PAD_Y),
				   Vector2(dw, title_h), dsize, HORIZONTAL_ALIGNMENT_RIGHT)

	_add_centred_title(box, String(attack.get("name", "")), int(m["title_size"]),
					   BOX_PAD_Y, title_h)

	if not (m["lines"] as Array).is_empty():
		_add_rich(box, m["lines"], int(m["body_size"]),
				  Vector2(BOX_PAD_X, BOX_PAD_Y + title_h + TITLE_TO_BODY),
				  box.size.x - BOX_PAD_X * 2.0)


func _render_wrr(m: Dictionary, box: ColorRect) -> void:
	var card: Dictionary = m["card"]
	var cap := int(m["cap_size"])
	var x0 := BOX_PAD_X
	var x1 := box.size.x - BOX_PAD_X
	var cap_h := _line_height("X", cap)
	var icon_y := BOX_PAD_Y + cap_h + WRR_LABEL_GAP

	var columns := [
		{ "label": "Weakness",    "types": _entry_types(card.get("weaknesses", [])),  "align": "left" },
		{ "label": "Resistance",  "types": _entry_types(card.get("resistances", [])), "align": "centre" },
		{ "label": "Retreat Cost","types": _string_array(card.get("retreatCost", [])),"align": "right" },
	]

	for column in columns:
		var label := String(column["label"])
		var w := _text_width(label, cap)
		var left := x0
		match String(column["align"]):
			"centre": left = (x0 + x1 - w) * 0.5
			"right":  left = x1 - w
		_add_label(box, label, Vector2(left, BOX_PAD_Y), Vector2(w, cap_h), cap,
				   HORIZONTAL_ALIGNMENT_LEFT)

		# The icons sit centred under the CAPTION, not under the column, so a
		# single icon lands on the caption's midpoint and a pair straddles it.
		var types := column["types"] as Array
		if types.is_empty():
			continue
		var group_w := float(types.size()) * WRR_ICON + float(types.size() - 1) * ICON_GAP
		var ix := left + w * 0.5 - group_w * 0.5
		for type_name in types:
			var tex := _load_texture(ENERGY_ICON_DIR + "color_icon_" + String(type_name).to_lower() + ".png")
			if tex != null:
				_add_icon(box, tex, Vector2(ix, icon_y), Vector2(WRR_ICON, WRR_ICON))
			ix += WRR_ICON + ICON_GAP


func _render_meta(m: Dictionary, box: ColorRect) -> void:
	var card: Dictionary = m["card"]
	var size := int(m["meta_size"])
	var row_h := float(m["row_h"])
	var rarity_row_h := float(m["rarity_row_h"])
	var text_x := BOX_PAD_X + SET_ICON + ICON_GAP + 6.0
	var y := BOX_PAD_Y

	var set_id := String(card.get("id", "")).split("-")[0]
	var set_icon := _load_texture(SET_ICON_DIR + "icon_" + set_id + ".png")
	if set_icon != null:
		# Set symbols range from 41x21 to 128x128, so each one is fitted into a
		# square cell with its aspect kept and centred in that cell.
		var fitted := _fit(set_icon.get_size(), Vector2(SET_ICON, SET_ICON))
		_add_icon(box, set_icon,
				  Vector2(BOX_PAD_X + (SET_ICON - fitted.x) * 0.5, y + (row_h - fitted.y) * 0.5),
				  fitted)
	_add_label(box, set_display_name(set_id), Vector2(text_x, y),
			   Vector2(box.size.x - text_x - BOX_PAD_X, row_h), size, HORIZONTAL_ALIGNMENT_LEFT)
	y += row_h + META_ROW_GAP

	var rarity: Dictionary = RARITY_TABLE.get(String(card.get("rarity", "")), RARITY_FALLBACK)
	var rar_icon := _load_texture(RARITY_ICON_DIR + String(rarity["icon"]) + ".png")
	if rar_icon != null:
		_add_icon(box, rar_icon,
				  Vector2(BOX_PAD_X + (SET_ICON - RARITY_ICON) * 0.5, y + (rarity_row_h - RARITY_ICON) * 0.5),
				  Vector2(RARITY_ICON, RARITY_ICON))
	_add_label(box, String(rarity["label"]), Vector2(text_x, y),
			   Vector2(box.size.x - text_x - BOX_PAD_X, rarity_row_h), size, HORIZONTAL_ALIGNMENT_LEFT)
	y += rarity_row_h + META_ROW_GAP

	var artist := String(card.get("artist", ""))
	if artist != "":
		var artist_row_h := maxf(RARITY_ICON, _line_height("X", size))
		# The icon says "illustrator", so the word doesn't need to as well.
		var illus_icon := _load_texture(SUBTYPE_ICON_DIR + "icon_illus.png")
		if illus_icon != null:
			var fitted_illus := _fit(illus_icon.get_size(), Vector2(RARITY_ICON, RARITY_ICON))
			_add_icon(box, illus_icon,
					  Vector2(BOX_PAD_X + (SET_ICON - fitted_illus.x) * 0.5,
							  y + (artist_row_h - fitted_illus.y) * 0.5),
					  fitted_illus)
		_add_label(box, artist, Vector2(text_x, y),
				   Vector2(box.size.x - text_x - BOX_PAD_X, artist_row_h), size,
				   HORIZONTAL_ALIGNMENT_LEFT)


## An ability or attack name, centred on the TRUE middle of the box. That is
## deliberate: it means a one-energy attack sits nearer its damage and a
## five-energy attack sits nearer its cost, which reads as a real card. The
## only concession is a shrink if the name would actually collide with either.
func _add_centred_title(box: ColorRect, text: String, size: int, y: float, row_h: float) -> void:
	if text == "":
		return
	_add_label(box, text, Vector2(BOX_PAD_X, y),
			   Vector2(box.size.x - BOX_PAD_X * 2.0, row_h), size, HORIZONTAL_ALIGNMENT_CENTER)


# ══════════════════════════════════════════════════════════════════════════
# CARD -> DISPLAY STRINGS
# ══════════════════════════════════════════════════════════════════════════

## The stage / trainer class / energy class line under the card's name.
## Basic Pokemon deliberately do NOT show what they evolve from: a handful of
## them list a Baby, which is a rule about the Baby rather than about them.
func _subtype_line(card: Dictionary) -> String:
	var supertype := String(card.get("supertype", ""))
	var subtypes  := _string_array(card.get("subtypes", []))

	if supertype == "Pokémon":
		var stage := ""
		for candidate in ["Baby", "Stage 2", "Stage 1", "Basic"]:
			if subtypes.has(candidate):
				stage = candidate
				break
		if stage == "":
			stage = "Basic"

		# A Baby card prints what it grows INTO rather than what it came from,
		# and Tyrogue grows into three different Pokemon.
		if stage == "Baby":
			var into := _string_array(card.get("evolvesTo", []))
			if not into.is_empty():
				return stage + " — Evolves into " + _join_or(into)
			return stage

		var evolves := String(card.get("evolvesFrom", ""))
		if evolves != "" and (stage == "Stage 1" or stage == "Stage 2"):
			# Blissey ex and Scizor ex each print two legal pre-evolutions.
			var from_names := [evolves]
			from_names.append_array(_string_array(card.get("evolvesFromAlso", [])))
			return stage + " — Evolves from " + _join_or(from_names)
		return stage

	if supertype == "Energy":
		return "Special Energy" if subtypes.has("Special") else "Basic Energy"

	# Trainers show whatever class the data gives them — Item, Supporter,
	# Stadium, Pokémon Tool, Technical Machine, Rocket's Secret Machine — and
	# fall back to plain "Trainer" when there is no class at all.
	if subtypes.is_empty():
		return "Trainer"
	return ", ".join(subtypes)


## "A", "A or B", "A, B or C" — the way an evolution line reads on a card.
static func _join_or(names: Array) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return String(names[0])
	var head: Array = names.slice(0, names.size() - 1)
	return ", ".join(head) + " or " + String(names[names.size() - 1])


## The energy icons shown top right. Pokemon only — a Trainer with HP (the
## Fossils, Clefairy Doll) has no type at all, which is exactly why the HP is
## allowed to run flush to the right edge on those cards.
func _header_types(card: Dictionary) -> Array:
	if String(card.get("supertype", "")) != "Pokémon":
		return []
	return _string_array(card.get("types", []))


## The border colour. Pokemon take their type; a dual type takes the half that
## ISN'T Metal or Darkness, because those two are the greys and the other half
## is what the card actually reads as.
func _border_color(card: Dictionary) -> Color:
	var supertype := String(card.get("supertype", ""))

	if supertype == "Pokémon":
		var types := _string_array(card.get("types", []))
		if types.is_empty():
			return TYPE_COLORS["Colorless"]
		if types.size() > 1:
			for type_name in types:
				if type_name != "Metal" and type_name != "Darkness":
					return TYPE_COLORS.get(type_name, COLOR_TRAINER)
		return TYPE_COLORS.get(types[0], COLOR_TRAINER)

	if supertype == "Energy":
		# Basic energy has no types array at all, and a special energy's colour
		# is whatever type its NAME mentions first. Neither has a type field to
		# read, so both go through the name.
		var lower := String(card.get("name", "")).to_lower()
		for pair in ENERGY_NAME_COLORS:
			if lower.contains(String(pair[0])):
				return TYPE_COLORS.get(String(pair[1]), COLOR_SPECIAL_ENERGY)
		return COLOR_SPECIAL_ENERGY

	return COLOR_TRAINER


static func set_display_name(set_id: String) -> String:
	if _set_names.is_empty():
		var file := FileAccess.open(SET_NAMES_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				for entry in parsed.get("set_list", []):
					_set_names[String(entry.get("set_id", ""))] = String(entry.get("set_name", ""))
		if _set_names.is_empty():
			_set_names["__loaded__"] = ""    # don't retry a missing file every card
	return _set_names.get(set_id, set_id)


func _card_image_path(uid: String) -> String:
	var parts := uid.split("-")
	if parts.size() < 2:
		return ""
	return CARD_IMAGE_DIR + parts[0] + "/Large/" + uid + ".png"


# ══════════════════════════════════════════════════════════════════════════
# TEXT -> TOKENS -> LINES
# ══════════════════════════════════════════════════════════════════════════
#
# A token is one of:
#     { "text": "..." }              a run of characters
#     { "icon": "res://...png" }     an inline energy symbol
#
# A WORD is an Array of tokens that must stay together (so "Fire," becomes the
# icon and the comma, with no space allowed between them). A LINE is an Array
# of { "word": Array, "space": bool } — space says whether a space precedes it.

## Splits card text into words, swapping energy type words for their symbol
## wherever the surrounding words say the word means an energy rather than
## being part of a name.
func _tokenise(text: String, _font_size: int) -> Array:
	var atoms := _substitute_energy(text)

	var words: Array = []
	var current: Array = []
	var pending_space := false
	var have_word := false

	for atom in atoms:
		if atom.has("icon"):
			current.append(atom)
			have_word = true
			continue
		for chunk in _split_keep_spaces(String(atom["text"])):
			if chunk == " ":
				if have_word:
					words.append({ "word": current, "space": pending_space })
					current = []
					have_word = false
				pending_space = true
			else:
				current.append({ "text": chunk })
				have_word = true
	if have_word:
		words.append({ "word": current, "space": pending_space })
	return words


## Breaks a string into runs of non-space text and single-space markers, so the
## tokeniser can tell "Fire, Water" (two words) from "Fire," (one).
func _split_keep_spaces(text: String) -> Array:
	var out: Array = []
	var buffer := ""
	for i in text.length():
		var c := text[i]
		if c == " " or c == "\n" or c == "\t":
			if buffer != "":
				out.append(buffer)
				buffer = ""
			out.append(" ")
		else:
			buffer += c
	if buffer != "":
		out.append(buffer)
	return out


## The energy-word substitution. Finds every run of type words, decides which
## runs are talking about energy, and replaces those with icon atoms.
##
## A run converts when:
##   - the word after it is Energy / Pokémon / basic / less / more, or
##   - the run is two or more type words glued together
##     (ColorlessColorlessColorless, GrassDarkness, MetalColorless), or
##   - it is an earlier member of a list whose LAST member converts
##     ("Fire, Water, or Psychic Pokémon" -> all three).
##
## Anything else stays as text, which is what keeps Water Cube 01, Lightning
## Rod, Psychic Force and Metal Gravity readable as the names they are.
func _substitute_energy(text: String) -> Array:
	var regex := _type_regex()
	var matches := regex.search_all(text)
	if matches.is_empty():
		return [{ "text": text }]

	# Pass 1, right to left: work out which runs convert.
	var convert: Array = []
	convert.resize(matches.size())
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var run := m.get_string(0)
		var count := _type_run_count(run)
		var decided := false

		if count >= 2:
			convert[i] = true
			decided = true
		else:
			var after := text.substr(m.get_end()).strip_edges(true, false)
			var next_word := after.split(" ")[0] if after != "" else ""
			next_word = next_word.rstrip(".,;:)")
			if ICONISE_FOLLOWERS.has(next_word):
				convert[i] = true
				decided = true

		if not decided and i < matches.size() - 1 and convert[i + 1]:
			# Only a list separator may sit between this run and the next one.
			var gap := text.substr(m.get_end(), matches[i + 1].get_start() - m.get_end())
			if _is_list_separator(gap):
				convert[i] = true
				decided = true
		if not decided:
			convert[i] = false

	# Pass 2: rebuild the string, swapping the converted runs for icon atoms.
	var out: Array = []
	var cursor := 0
	for i in matches.size():
		var m2: RegExMatch = matches[i]
		if not convert[i]:
			continue
		if m2.get_start() > cursor:
			out.append({ "text": text.substr(cursor, m2.get_start() - cursor) })
		for type_name in _split_type_run(m2.get_string(0)):
			out.append({ "icon": ENERGY_ICON_DIR + "color_icon_" + type_name.to_lower() + ".png" })
		cursor = m2.get_end()
	if cursor < text.length():
		out.append({ "text": text.substr(cursor) })
	return out


func _is_list_separator(gap: String) -> bool:
	if gap.strip_edges() == "":
		return true
	for i in gap.length():
		if not LIST_SEPARATORS.contains(gap[i]):
			return false
	# Guard against a stray word made only of those letters ("and", "or", "nor"
	# are fine; anything else built from o/r/a/n/d is not a separator).
	for piece in gap.split(" ", false):
		var word := piece.rstrip(",/")
		if word != "" and word != "or" and word != "and" and word != "nor":
			return false
	return true


func _split_type_run(run: String) -> Array:
	var out: Array = []
	var rest := run
	while rest != "":
		var matched := false
		for type_name in ENERGY_TYPES:
			if rest.begins_with(type_name):
				out.append(type_name)
				rest = rest.substr(type_name.length())
				matched = true
				break
		if not matched:
			break
	return out


func _type_run_count(run: String) -> int:
	return _split_type_run(run).size()


static func _type_regex() -> RegEx:
	if _type_run_regex == null:
		_type_run_regex = RegEx.new()
		# No letter either side, so "Waterfall" and "Firestorm" are left alone.
		_type_run_regex.compile("(?<![A-Za-z])(?:" + "|".join(ENERGY_TYPES) + ")+(?![a-z])")
	return _type_run_regex


## Greedy wrap. Returns an Array of lines; each line is an Array of the same
## { "word", "space" } entries the tokeniser produced.
func _wrap(words: Array, width: float, font_size: int) -> Array:
	var lines: Array = []
	var line: Array = []
	var line_w := 0.0
	var space_w := _text_width(" ", font_size)

	for entry in words:
		var w := _word_width(entry["word"], font_size)
		var lead: float = space_w if (bool(entry["space"]) and not line.is_empty()) else 0.0
		if not line.is_empty() and line_w + lead + w > width:
			lines.append(line)
			line = [{ "word": entry["word"], "space": false }]
			line_w = w
		else:
			line.append({ "word": entry["word"], "space": lead > 0.0 })
			line_w += lead + w
	if not line.is_empty():
		lines.append(line)
	if lines.is_empty():
		lines.append([])
	return lines


## An inline icon is drawn as an exact square and carries no padding of its own,
## so it costs exactly its own width here. The space between words already
## separates it from the text either side.
##
## Do NOT try to widen it for breathing room: add_image's `pad` argument only
## pads an image that is SMALLER than the box, and these icons are 100x100
## sources, so asking for a wider box stretches and enlarges the icon instead of
## padding it. Anything added at draw time and not counted here would also let a
## line render wider than the box it was measured for.
func _word_width(word: Array, font_size: int) -> float:
	var total := 0.0
	for token in word:
		if token.has("icon"):
			total += _inline_icon_size(font_size)
		else:
			total += _text_width(String(token["text"]), font_size)
	return total


func _lines_height(lines: Array, font_size: int) -> float:
	var total := 0.0
	for line in lines:
		total += _line_height(_line_plain_text(line), font_size)
	return total + float(LINE_SEPARATION * maxi(lines.size() - 1, 0))


func _line_plain_text(line: Array) -> String:
	var out := ""
	for entry in line:
		for token in entry["word"]:
			if token.has("text"):
				out += String(token["text"])
	return out


## A line is taller when it carries a glyph Kenney doesn't have, because the
## fallback face has deeper metrics. Only delta, star, the Nidoran genders and
## the e-card Greek letters do that, so most lines are the plain height.
func _line_height(text: String, font_size: int) -> float:
	var base := _get_base_font()
	if base != null and text != "":
		for i in text.length():
			if not base.has_char(text.unicode_at(i)):
				return _get_font().get_height(font_size)
	if base != null:
		return base.get_height(font_size)
	return float(font_size) * 1.2


## Picks a rule box's font size: the largest that gets the text onto ONE line,
## failing that the largest that gets it onto two, failing that the ceiling.
## Boilerplate is the same handful of sentences on hundreds of cards, so it is
## worth trading a couple of points of size for a box that stays out of the way.
func _fit_rule_size(text: String, width: float, shrink: int) -> int:
	var ceiling := maxi(FONT_RULE - shrink, 12)
	var floor_size := mini(FONT_RULE_MIN, ceiling)
	for target_lines in [1, 2]:
		var size := ceiling
		while size >= floor_size:
			if _wrap(_tokenise(text, size), width, size).size() <= target_lines:
				return size
			size -= 1
	return ceiling


## Largest size from `ceiling` down to `floor_size` at which `text` fits in
## `width`. Used for the three rows that have to share their line with
## something else, rather than for the whole stack's shrink-to-fit.
func _fit_text(text: String, width: float, ceiling: int, floor_size: int) -> int:
	if text == "" or width <= 0.0:
		return ceiling
	var size := ceiling
	while size > floor_size and _text_width(text, size) > width:
		size -= 1
	return size


## How much room a TRUE-centred label has when `left` px are used on the left
## of the box and `right` px on the right. Centring means the label can only
## use twice the SMALLER free side, so mirroring the wider one is the honest
## answer — which is what keeps the name centred instead of nudging it aside.
func _centred_room(content_w: float, left: float, right: float) -> float:
	return maxf(content_w - maxf(left, right) * 2.0 - ICON_GAP * 2.0, 1.0)


## Rendered width of the Poke-POWER / Poke-BODY pill, which is a wide badge
## rather than a square icon.
func _badge_width(ability: Dictionary) -> float:
	var stem := "power"
	if String(ability.get("type", "")).to_lower().contains("body"):
		stem = "body"
	var tex := _load_texture(SUBTYPE_ICON_DIR + "color_icon_" + stem + ".png")
	if tex == null:
		return 0.0
	return BADGE_H * (tex.get_size().x / maxf(tex.get_size().y, 1.0)) + ICON_GAP


## Width the header's right-hand side needs: the type icons plus the HP.
## Measured at the FULL name size so it is an upper bound — the HP is later
## drawn at the fitted name size, which can only be smaller.
func _header_right_width(card: Dictionary) -> float:
	var total := 0.0
	for _type_name in _header_types(card):
		total += TYPE_ICON + ICON_GAP
	var hp := String(card.get("hp", ""))
	if hp != "":
		total += _text_width(hp + "HP", FONT_HP) + ICON_GAP
	return total


func _inline_icon_size(font_size: int) -> float:
	# Kept under the line height on purpose, so an icon can never stretch the
	# line it sits on and break the measured box height.
	return floorf(float(font_size) * INLINE_ICON_RATIO)


func _text_width(text: String, font_size: int) -> float:
	if text == "":
		return 0.0
	return _get_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


# ══════════════════════════════════════════════════════════════════════════
# NODE FACTORIES
# ══════════════════════════════════════════════════════════════════════════

func _make_box(pos: Vector2, size: Vector2, border: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.clip_contents = false

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("color_left",    border)
	mat.set_shader_parameter("color_right",   border)
	mat.set_shader_parameter("fill_color",    Color.WHITE)
	mat.set_shader_parameter("rect_size",     size)
	mat.set_shader_parameter("corner_radius", CORNER_R)
	mat.set_shader_parameter("edge_solid",    EDGE_SOLID)
	mat.set_shader_parameter("edge_fade",     EDGE_FADE)
	rect.material = mat

	_box_root.add_child(rect)
	return rect


func _add_label(parent: Control, text: String, pos: Vector2, size: Vector2,
				font_size: int, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	parent.add_child(label)
	return label


func _add_icon(parent: Control, tex: Texture2D, pos: Vector2, size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = pos
	rect.size = size
	parent.add_child(rect)
	return rect


## Draws pre-wrapped lines into a RichTextLabel with autowrap OFF, so the label
## renders exactly the lines that were measured — no second, different wrap.
func _add_rich(parent: Control, lines: Array, font_size: int, pos: Vector2, width: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active  = false
	label.fit_content    = true
	label.autowrap_mode  = TextServer.AUTOWRAP_OFF
	label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.size = Vector2(width, _lines_height(lines, font_size))
	label.add_theme_font_override("normal_font", _get_font())
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("line_separation", LINE_SEPARATION)
	parent.add_child(label)

	var icon_px := _inline_icon_size(font_size)
	label.clear()
	for i in lines.size():
		if i > 0:
			label.newline()
		for entry in lines[i]:
			if bool(entry["space"]):
				label.add_text(" ")
			for token in entry["word"]:
				if token.has("icon"):
					var tex := _load_texture(String(token["icon"]))
					if tex != null:
						label.add_image(tex, int(icon_px), int(icon_px), Color.WHITE,
										INLINE_ALIGNMENT_CENTER)
				else:
					label.add_text(String(token["text"]))
	return label


# ══════════════════════════════════════════════════════════════════════════
# FONT / TEXTURE / ARRAY HELPERS
# ══════════════════════════════════════════════════════════════════════════

## The Kenney face on its own. Caps-only by design — lowercase letters share
## the uppercase outlines — which is why nothing here calls to_upper(): the
## text renders as capitals anyway, and forcing the case would turn a delta
## into a capital delta and an accented e into a glyph half the sets need.
static func _get_base_font() -> FontFile:
	if _base_font == null:
		_base_font = load(FONT_PATH)
	return _base_font


## Kenney, plus a system face behind it for the seven glyphs Kenney lacks:
## delta, star, the Nidoran genders and the e-card alpha/beta/gamma. Nothing in
## UI_Themes/ carries any of them, so this has to come from the OS.
static func _get_font() -> FontVariation:
	if _font != null:
		return _font
	_font = FontVariation.new()
	_font.base_font = _get_base_font()

	for path in FALLBACK_FONT_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var fallback := FontFile.new()
		if fallback.load_dynamic_font(path) != OK:
			continue
		_font.fallbacks = [fallback]
		return _font

	if not _font_warned:
		_font_warned = true
		push_warning("CardDetailPanel: no system fallback font found — δ ★ ♀ ♂ α β γ " +
					 "will not render. Tried: " + ", ".join(FALLBACK_FONT_PATHS))
	return _font


static func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex


## Scales `source` down to fit inside `cell`, keeping its aspect. Set symbols
## are anywhere from 41x21 to 128x128, so none of them can be drawn square.
static func _fit(source: Vector2, cell: Vector2) -> Vector2:
	if source.x <= 0.0 or source.y <= 0.0:
		return cell
	var scale: float = minf(cell.x / source.x, cell.y / source.y)
	return source * scale


static func _string_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			out.append(String(entry))
	return out


static func _dict_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				out.append(entry)
	return out


## Pulls the "type" out of a weaknesses / resistances array. Every value in the
## data is the standard x2 / -30, so only the type is worth drawing.
static func _entry_types(value) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				out.append(String(entry.get("type", "")))
	return out
