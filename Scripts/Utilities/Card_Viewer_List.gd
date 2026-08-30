class_name CardViewerList
extends RefCounted

# ============================================================
# SHARED CARD-COLLECTION VIEWER (extracted from Deck_Build_And_Card_View_Script.gd)
# ============================================================
# Everything the "view deck" screen uses to turn a {card_id: count} dictionary into
#   1. a display ORDER for the card grid, and
#   2. the right-hand INDIVIDUAL / CATEGORIES text list beside it.
#
# It lives here rather than in the deck builder because the Card Buyer's bulk-sell
# screen shows the exact same thing for a different set of cards, and the two must
# never drift apart. Nothing in here reads deck state or touches the tree beyond the
# parent it is handed.
#
# CARD METADATA is NOT owned here. Every entry point takes a `meta_fn` Callable of the
# shape `func(card_id: String) -> Variant` returning the card's metadata dictionary
# (name / supertype / subtypes / types / evolvesFrom / rarity) or null. The deck
# builder passes its own cache, which carries extra fields the search screen needs;
# the sell screen passes a smaller one. Neither has to know about the other.
# ============================================================


# Display order for Pokémon types in the card grid.
const POKEMON_TYPE_DISPLAY_ORDER : Array = [
	"Grass", "Fire", "Water", "Lightning", "Psychic",
	"Fighting", "Darkness", "Metal", "Colorless",
]


# ─── Sorting ─────────────────────────────────────────────────────────────────

## Stage of a Pokémon card: 2 / 1 / 0 (Basic) / -1 (Baby).
static func card_stage(card_id: String, meta_fn: Callable) -> int:
	var meta = meta_fn.call(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stage 2" in subtypes:
		return 2
	if "Stage 1" in subtypes:
		return 1
	if "Baby" in subtypes:
		return -1
	return 0


## Sort priority for a Trainer subtype: 0 = Normal, 1 = Stadium, 2 = Tool.
static func trainer_subtype_priority(card_id: String, meta_fn: Callable) -> int:
	var meta = meta_fn.call(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stadium" in subtypes:
		return 1
	if "Tool" in subtypes or "Pokémon Tool" in subtypes:
		return 2
	return 0


## Card name for sorting, falling back to the id when metadata is missing.
static func _sort_name(card_id: String, meta_fn: Callable) -> String:
	var meta = meta_fn.call(card_id)
	return str(meta.get("name", card_id)) if meta != null else card_id


## Sorts energy card_ids: Special Energy first, then Basic, alphabetically within each.
static func sort_energy(energy_ids: Array, meta_fn: Callable) -> Array:
	var special : Array = []
	var basic   : Array = []
	for cid in energy_ids:
		var meta = meta_fn.call(cid)
		if meta != null and "Special" in meta.get("subtypes", []):
			special.append(cid)
		else:
			basic.append(cid)
	var name_sort := func(a: String, b: String) -> bool:
		return _sort_name(a, meta_fn) < _sort_name(b, meta_fn)
	special.sort_custom(name_sort)
	basic.sort_custom(name_sort)
	return special + basic


## Sorts trainer card_ids: Normal → Stadium → Tool, alphabetically within each group.
static func sort_trainers(trainer_ids: Array, meta_fn: Callable) -> Array:
	trainer_ids.sort_custom(func(a: String, b: String) -> bool:
		var pa : int = trainer_subtype_priority(a, meta_fn)
		var pb : int = trainer_subtype_priority(b, meta_fn)
		if pa != pb:
			return pa < pb
		return _sort_name(a, meta_fn) < _sort_name(b, meta_fn)
	)
	return trainer_ids


## Groups Pokémon in one type bucket into evolution families, then sorts:
##   Segments ordered by max_stage DESC; standalones before families of same max_stage.
##   Within a family: Stage 2 → Stage 1 → Basic → Baby.
static func sort_type_group_pokemon(type_ids: Array, meta_fn: Callable) -> Array:
	if type_ids.is_empty():
		return type_ids

	# name → [card_ids] for cards in this group
	var name_to_ids : Dictionary = {}
	for cid in type_ids:
		var cname : String = _sort_name(cid, meta_fn)
		if not name_to_ids.has(cname):
			name_to_ids[cname] = []
		(name_to_ids[cname] as Array).append(cid)

	# Union-find: group_of[cid] = representative id
	var group_of : Dictionary = {}
	for cid in type_ids:
		group_of[cid] = cid

	# Three passes handles Stage 2 chains (Basic→Stage1→Stage2)
	for _pass in range(3):
		for cid in type_ids:
			var meta = meta_fn.call(cid)
			if meta == null:
				continue
			var from_name : String = meta.get("evolvesFrom", "")
			if from_name == "" or not name_to_ids.has(from_name):
				continue
			# Path-compress my root
			var my_root : String = group_of[cid]
			while group_of[my_root] != my_root:
				my_root = group_of[my_root]
			# Union with each "from" card's root
			for from_cid in (name_to_ids[from_name] as Array):
				var from_root : String = group_of[from_cid]
				while group_of[from_root] != from_root:
					from_root = group_of[from_root]
				if my_root != from_root:
					group_of[from_root] = my_root

	# Path-compress all
	for cid in type_ids:
		var root : String = group_of[cid]
		while group_of[root] != root:
			root = group_of[root]
		group_of[cid] = root

	# Build segments keyed by root
	var segments : Dictionary = {}
	for cid in type_ids:
		var root : String = group_of[cid]
		if not segments.has(root):
			segments[root] = []
		(segments[root] as Array).append(cid)

	# Build segment metadata and sort cards within each segment by stage DESC
	var segment_list : Array = []
	for root in segments:
		var seg_cards : Array = segments[root]
		var max_stage : int = -99
		for cid in seg_cards:
			var s : int = card_stage(cid, meta_fn)
			if s > max_stage:
				max_stage = s
		seg_cards.sort_custom(func(a: String, b: String) -> bool:
			return card_stage(a, meta_fn) > card_stage(b, meta_fn)
		)
		segment_list.append({
			"cards":       seg_cards,
			"max_stage":   max_stage,
			"standalone":  seg_cards.size() == 1,
			"first_name":  _sort_name(seg_cards[0], meta_fn),
		})

	# Sort segments: max_stage DESC → standalone first (true > false) → name ASC
	segment_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["max_stage"] != b["max_stage"]:
			return a["max_stage"] > b["max_stage"]
		if a["standalone"] != b["standalone"]:
			return a["standalone"]  # true sorts before false
		return a["first_name"] < b["first_name"]
	)

	var result : Array = []
	for seg in segment_list:
		result.append_array(seg["cards"])
	return result


## Returns the full sorted card_id list, ready for the viewer grid.
## Order: Pokémon by type → Trainers (Normal/Stadium/Tool) → Energy (Special/Basic).
static func sort_ids(card_ids: Array, meta_fn: Callable) -> Array:
	var pokemon_by_type : Dictionary = {}
	var trainer_ids     : Array      = []
	var energy_ids      : Array      = []

	for card_id in card_ids:
		var meta = meta_fn.call(card_id)
		if meta == null:
			continue
		var supertype : String = meta.get("supertype", "")
		if supertype == "Pokémon":
			var types  : Array  = meta.get("types", [])
			var ptype  : String = types[0] if types.size() > 0 else "Colorless"
			if not pokemon_by_type.has(ptype):
				pokemon_by_type[ptype] = []
			(pokemon_by_type[ptype] as Array).append(card_id)
		elif supertype == "Trainer":
			trainer_ids.append(card_id)
		elif supertype == "Energy":
			energy_ids.append(card_id)

	var result : Array = []
	for ptype in POKEMON_TYPE_DISPLAY_ORDER:
		if pokemon_by_type.has(ptype):
			result.append_array(sort_type_group_pokemon(pokemon_by_type[ptype], meta_fn))
	result.append_array(sort_trainers(trainer_ids, meta_fn))
	result.append_array(sort_energy(energy_ids, meta_fn))
	return result


# ─── Right-hand card list (ISSUE #152) ───────────────────────────────────────
# TWEAKABLE. A text list of the viewer's unique cards down the right-hand bar — the strip beside the
# card grid that is otherwise empty. One line per card: "<name> (xN)".
#
# GEOMETRY: the bar runs from the right edge of the viewer's card grid (x 1681) to the screen edge,
# and the list starts level with the top of the grid rather than at the top of the screen. It stops
# above the button(s) beneath it; callers that need more room at the bottom (the bulk-sell screen has
# two buttons stacked there, not one) pass their own `bottom`.
#
# FONT SIZING — read this before changing the width or putting the card id back. The bar is only
# ~226px wide, which is the whole constraint. Lines are "<name> (xN)" and nothing else: dropping the
# id was worth a lot here, because "ecard1-148 Professor Elm's Training Method (x4)" needed ~34px of
# width per point of font (font 6 to fit on one line, i.e. unreadable) while the name alone needs
# ~26px. Measured across all 1,308 distinct card names: 99.3% fit on one line at font 10 and 97.8%
# at font 11, and the 13-line starter deck comes out at font 15.
# The list still copes with the rest by:
#   1. picking the largest font in [MIN, MAX] at which THIS list's longest line and its line count
#      both fit — so a short list gets big text and a long one shrinks to suit,
#   2. word-wrapping anything still too long rather than clipping it (only ~9 of 1,308 names are
#      long enough to wrap at font 10),
#   3. sitting in a ScrollContainer, so even 60 unique long-named cards remain reachable.
# Widening the bar would need the card grid narrowed to 8 columns; that is a deliberate trade the
# user has not asked for.
const VIEWER_LIST_X          := 1689.0
const VIEWER_LIST_W          := 226.0
const VIEWER_LIST_TOP        := 110.0    # level with the card grid, just under the top border
const VIEWER_LIST_BOTTOM     := 990.0    # clear of the Close button at y 1003
const VIEWER_LIST_PAD        := 6.0      # breathing room so text never touches the scrollbar
# MEASURED, not guessed: the list label sits directly in the ScrollContainer with no
# margin container, so the only thing between VIEWER_LIST_W and the text is the
# vertical scrollbar. Built the real node arrangement headless to check — the label
# comes back 218px wide inside a 226px scroller, and the RichTextLabel's own
# stylebox contributes no margin at all.
const VIEWER_LIST_SCROLLBAR  := 8.0

# ── Type sizing ──────────────────────────────────────────────────────────────
# The individual list runs at roughly DOUBLE the old 10-18, and the fit rule
# changed with it. It used to demand that a WHOLE LINE fit the bar's width, which
# is what held the text down to 10-15pt. Wrapping is now accepted, so the only
# hard requirement is that the longest WORD fits — a wrapped name is fine, a word
# running off the bar is not.
#
# Measured over all 1,308 distinct card names: the longest single word in the
# game is "Counterattack" (Counterattack Claws) at 217px for a 214px bar, so it
# alone needs 19pt. It is one name in 1,308 and the fit is per-LIST, so only a
# list actually holding that card is affected — and AUTOWRAP_WORD_SMART breaks an
# over-long word rather than letting it overflow, so even that case is safe at
# the minimum. At 24pt, 1,303 of 1,308 names fit unbroken; at 20pt, 1,307.
#
# The HEIGHT is deliberately not part of the fit any more. Keeping it would drag
# a 20-unique-card deck straight back to the minimum and undo the whole change;
# the list sits in a ScrollContainer, so length costs a scroll rather than
# legibility.
const VIEWER_LIST_FONT_MAX   := 20
# 19, not 20, for exactly one reason: "Counterattack" measures 217px at 20 against a
# ~212px bar but 206px at 19. One point buys the only word in the game that would
# otherwise have to be broken mid-word.
const VIEWER_LIST_FONT_MIN   := 19
# The category rows must NEVER wrap — "Sp. Energy 4" split over two lines reads as
# two separate facts — so these fit on whole-line width. The MAX matches the list's
# so the two sections read at the same size; the worst possible row,
# "Sp. Energy  60", measures 189px at 20 and still fits.
const VIEWER_CAT_FONT_MAX    := 20
const VIEWER_CAT_FONT_MIN    := 11
# Header CEILING, not the header size — the header is fitted down from
# (list size + this) until it fits the bar. It used to be applied blind, which is
# what let "CATEGORIES" wrap to "CATEGORI / ES": the list could reach 32, taking the
# header to 34 and the word to ~265px in a 212px bar. "CATEGORIES" is the wider of
# the two headers despite being the same length as "INDIVIDUAL" (188px vs 164px at
# 24), so it is the one that decides the size.
#
# It is 4 rather than 2 because the headers are pinned at 24 while the body text
# came down to 20 — the gap absorbed the body's last reduction. If the body size
# changes again and the headers should follow it rather than stay put, this is the
# number to move.
const VIEWER_HEADER_EXTRA    := 4
const VIEWER_LINE_SPACING    := 2        # extra px between lines, per the brief
const VIEWER_HEADER_COLOUR   := "#ffd86b"  # pale gold; reads over the patterned border art

## The two section header strings. Kept in one place so the header fit below and the
## text actually rendered can never disagree about what is being measured.
const VIEWER_HEADERS := ["INDIVIDUAL", "CATEGORIES"]

const KENNEY_THEME_PATH := "res://UI_Themes/ui/ui_secondary.tres"


## Builds the "<name> (xN)" lines for the INDIVIDUAL section, in the order given.
## `counts` is {card_id: count}; ids with a count of 0 or less are skipped.
static func individual_lines(sorted_ids: Array, counts: Dictionary, meta_fn: Callable) -> Array:
	var lines : Array = []
	for card_id in sorted_ids:
		var count : int = int(counts.get(card_id, 0))
		if count <= 0:
			continue
		# Name and count only — no card id on any line. One entry per card ENTRY, not per name, so a
		# list holding two printings of the same card shows two lines with the same name and their
		# own counts.
		lines.append("%s (x%d)" % [_sort_name(card_id, meta_fn), count])
	return lines


## Per-copy counts for the CATEGORIES section, in display order.
##
## Counts COPIES, not unique cards, so the six numbers add up to the list total.
##
## Two classification notes, both taken from the card data rather than assumed:
##   - Energy splits cleanly on the "Basic" subtype: every one of the 124 Energy
##     cards in the game is subtyped either "Basic" (54) or "Special" (70).
##   - 19 Baby Pokemon carry ONLY the "Baby" subtype — no "Basic", no Stage. They
##     are Basic Pokemon by the rules (played straight from hand), so the Pokemon
##     branch falls through to Basic rather than testing for "Basic" explicitly,
##     which would have dropped all 19 out of every total.
static func category_rows(counts: Dictionary, meta_fn: Callable) -> Array:
	var basic := 0
	var stage1 := 0
	var stage2 := 0
	var trainer := 0
	var sp_energy := 0
	var basic_energy := 0

	for card_id in counts.keys():
		var count: int = int(counts[card_id])
		if count <= 0:
			continue
		var meta = meta_fn.call(card_id)
		if meta == null:
			continue
		var supertype := str(meta.get("supertype", ""))
		var subtypes: Array = meta.get("subtypes", [])

		if supertype == "Energy":
			if "Basic" in subtypes:
				basic_energy += count
			else:
				sp_energy += count
		elif supertype == "Trainer":
			trainer += count
		# Everything else is a Pokemon. Matched by elimination rather than on the
		# supertype string, which is the accented "Pokémon" in the data and is one
		# encoding slip away from silently counting nothing.
		elif "Stage 2" in subtypes:
			stage2 += count
		elif "Stage 1" in subtypes:
			stage1 += count
		else:
			basic += count

	# Labels are kept short on purpose: the bar is ~214px and a category row must
	# fit on ONE line (see VIEWER_CAT_FONT_*).
	return [
		{ "label": "Basic",      "count": basic },
		{ "label": "Stage 1",    "count": stage1 },
		{ "label": "Stage 2",    "count": stage2 },
		{ "label": "Trainer",    "count": trainer },
		{ "label": "Sp. Energy", "count": sp_energy },
		{ "label": "Energy",     "count": basic_energy },
	]


## Builds the right-hand INDIVIDUAL / CATEGORIES bar and parents it to `parent`.
## Returns the ScrollContainer, or null when there is nothing to show.
## `bottom` defaults to the deck viewer's single-Close-button geometry.
static func build_side_list(parent: Control, lines: Array, cat_rows: Array,
		bottom: float = VIEWER_LIST_BOTTOM) -> ScrollContainer:
	if parent == null or lines.is_empty():
		return null

	var font_size := fit_list_font(lines)
	var cat_size := fit_cat_font(cat_rows)
	var header_size := fit_header_font(font_size + VIEWER_HEADER_EXTRA)

	var list_scroll := ScrollContainer.new()
	list_scroll.position = Vector2(VIEWER_LIST_X, VIEWER_LIST_TOP)
	list_scroll.size     = Vector2(VIEWER_LIST_W, bottom - VIEWER_LIST_TOP)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.z_index = 55
	parent.add_child(list_scroll)

	# RichTextLabel rather than Label: fit_content reports the WRAPPED height to the ScrollContainer,
	# which is what lets a too-long list scroll instead of being silently cut off. Same pattern as
	# the set-breakdown label on the deck builder's main screen.
	var list_label := RichTextLabel.new()
	# bbcode is ON, for the two section headers and the per-section font sizes.
	# That makes card NAMES dangerous: "Ancient Technical Machine [Ice]" carries
	# square brackets, and anything that happened to read as a tag would vanish
	# from the list. bb_escape() below neutralises every bracket in a name.
	list_label.bbcode_enabled = true
	list_label.scroll_active  = false
	list_label.fit_content    = true
	list_label.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	var kenney_theme = load(KENNEY_THEME_PATH)
	if kenney_theme:
		list_label.theme = kenney_theme
	list_label.add_theme_font_size_override("normal_font_size", font_size)
	list_label.add_theme_color_override("default_color", Color.WHITE)
	# A thin, FULLY OPAQUE outline so the white text stays readable over the patterned border art.
	# It was 4px at 90% alpha, which at font 10-11 is nearly as thick as the glyph strokes themselves
	# — the haze bled into the letters and read as off-grey rather than white. 2px opaque gives a
	# crisp edge without touching the stroke colour. Raise it only if the font size goes up a lot.
	list_label.add_theme_constant_override("outline_size", 2)
	list_label.add_theme_color_override("font_outline_color", Color.BLACK)
	list_label.add_theme_constant_override("line_separation", VIEWER_LINE_SPACING)

	# ── Assemble the two sections ──
	var body: Array = []
	body.append(header_bb("INDIVIDUAL", header_size))
	body.append("[font_size=%d]" % font_size)
	for line in lines:
		body.append(bb_escape(String(line)))
	body.append("[/font_size]")

	if not cat_rows.is_empty():
		body.append("")   # a clear line between the two sections
		body.append(header_bb("CATEGORIES", header_size))
		body.append("[font_size=%d]" % cat_size)
		for row in cat_rows:
			body.append("%s  %d" % [row["label"], row["count"]])
		body.append("[/font_size]")

	list_label.text = "\n".join(body)
	list_scroll.add_child(list_label)

	print("ISSUE #152 FIX ACTIVE: card list built, ", lines.size(), " unique cards at font ",
		font_size, " (categories at ", cat_size, ") in a ", VIEWER_LIST_W, "x",
		bottom - VIEWER_LIST_TOP, " bar")
	return list_scroll


## One section header, coloured and a couple of points up on the body text.
static func header_bb(text: String, size: int) -> String:
	return "[font_size=%d][color=%s]%s[/color][/font_size]" % [size, VIEWER_HEADER_COLOUR, text]


## Neutralises bbcode in text that came from card data. Card names really do
## contain brackets — every Ancient Technical Machine is "[Ice]" / "[Rock]" /
## "[Steel]", and the ecard Cubes and Mystery Plates are similar — so without this
## the list would silently swallow part of a name the moment bbcode was enabled.
static func bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Width the list text actually has: the bar, less the vertical scrollbar the
## ScrollContainer draws over its right edge, less a little breathing room. Shared
## by all three fits so they cannot drift apart.
static func viewer_text_width() -> float:
	return VIEWER_LIST_W - VIEWER_LIST_SCROLLBAR - VIEWER_LIST_PAD


## Largest size at or below `ceiling` at which BOTH headers fit the bar on one line.
## A wrapped header reads as a broken word ("CATEGORI / ES"), which is worse than a
## slightly smaller one.
static func fit_header_font(ceiling: int) -> int:
	var theme_res = load(KENNEY_THEME_PATH)
	var font: Font = theme_res.default_font if theme_res != null else null
	if font == null:
		return VIEWER_LIST_FONT_MIN

	var avail := viewer_text_width()
	var size := ceiling
	while size > VIEWER_CAT_FONT_MIN:
		var widest := 0.0
		for text in VIEWER_HEADERS:
			widest = maxf(widest, font.get_string_size(
				String(text), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if widest <= avail:
			break
		size -= 1
	return size


## Largest size in [VIEWER_CAT_FONT_MIN, VIEWER_CAT_FONT_MAX] at which every
## category row fits the bar on one line. Whole-line fit, unlike the card list —
## these must not wrap.
static func fit_cat_font(rows: Array) -> int:
	var theme_res = load(KENNEY_THEME_PATH)
	var font: Font = theme_res.default_font if theme_res != null else null
	if font == null or rows.is_empty():
		return VIEWER_CAT_FONT_MIN

	var avail_w := viewer_text_width()
	var size := VIEWER_CAT_FONT_MAX
	while size > VIEWER_CAT_FONT_MIN:
		var widest := 0.0
		for row in rows:
			var text: String = "%s  %d" % [row["label"], row["count"]]
			widest = maxf(widest, font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if widest <= avail_w:
			break
		size -= 1
	return size


## Largest font size in [VIEWER_LIST_FONT_MIN, VIEWER_LIST_FONT_MAX] at which the longest WORD in
## this list still fits the bar's width. Measured with the real font rather than estimated, so it
## cannot drift from what actually renders.
##
## The test is per-WORD, not per-line: lines are expected to wrap now ("Ancient Technical Machine
## (x2)" over two or three lines is fine), and a whole-line test is what used to hold the size down
## to 10-15pt. Height is not tested at all — the list scrolls.
##
## Returns the MIN when even that is too wide. That is safe rather than broken: AUTOWRAP_WORD_SMART
## breaks a word that cannot fit instead of letting it run past the edge, which matters for exactly
## one card in the game ("Counterattack" needs 19pt in a 214px bar).
static func fit_list_font(lines: Array) -> int:
	var theme_res = load(KENNEY_THEME_PATH)
	var font : Font = theme_res.default_font if theme_res != null else null
	if font == null:
		return VIEWER_LIST_FONT_MIN

	var avail_w := viewer_text_width()

	# Split once, up front — this loop runs up to 13 times over every word otherwise.
	var words : Array = []
	for line in lines:
		for w in String(line).split(" ", false):
			words.append(String(w))
	if words.is_empty():
		return VIEWER_LIST_FONT_MIN

	var size := VIEWER_LIST_FONT_MAX
	while size > VIEWER_LIST_FONT_MIN:
		var widest := 0.0
		for w in words:
			widest = maxf(widest, font.get_string_size(
				w, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if widest <= avail_w:
			break
		size -= 1
	return size
