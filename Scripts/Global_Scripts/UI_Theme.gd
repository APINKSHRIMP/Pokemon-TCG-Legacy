extends Node

# ============================================================
# UITheme — the single source of truth for UI colour, type and metrics
# ============================================================
# Autoload. Every screen reads its colours, fonts, sizes and spacing from here
# so a theme change is a data change rather than a hunt through 40 scripts.
#
# WHAT LIVES HERE
#   * THEMES        — one dictionary per look. Only "spectrum_night" is
#                     reachable today; the other three are parked so adding a
#                     theme picker later is a UI job, not a data job.
#   * TYPE          — the type scale (size / face / tracking / casing).
#   * METRICS       — bar heights, radii, paddings, animation timings.
#   * ENERGY_COLOUR — the one place hue carries data rather than decoration.
#
# WHAT DELIBERATELY DOES **NOT** LIVE HERE
#   Sparkle particle palettes, per-NPC message-box colours and the deck
#   builder's per-card-type breakdown colours. Those are content, not chrome;
#   sweeping them into a theme would flatten distinctions the game relies on.
#
# ── HOW TO READ A VALUE ──────────────────────────────────────
#   UITheme.col("accent")            -> Color
#   UITheme.font("button")           -> Font   (the face that role is set in)
#   UITheme.size("button")           -> int    (already scaled by ui_scale)
#   UITheme.tracking_px("button")    -> int    (letter-spacing, whole px)
#   UITheme.m("header_h")            -> float  (a metric, already scaled)
#
# ── THE ONE KNOB WORTH TURNING FIRST ─────────────────────────
# `ui_scale` multiplies every type size and every metric. The type scale below
# is taken verbatim from the design spec, which is noticeably smaller than the
# Kenney-era sizes it replaces (a screen title goes 61 -> 29). If the whole UI
# reads too small on a real screen, raise ui_scale rather than editing 40
# numbers. 1.0 is the authored design.
# ============================================================

signal theme_changed

# ─── Fonts ───────────────────────────────────────────────────────────────────
# Chakra Petch is the display/UI face; IBM Plex Mono carries anything where
# digits must line up in a column (counts, HP, prices, small caps labels).
#
# NEITHER FACE HAS  δ ★ ♀ ♂ α β γ  — verified with fontTools, and they are the
# same seven glyphs kenvector_future was missing. Card text containing them
# still needs the system-font fallback chain; see font_card().
const FONT_DIR := "res://UI_Themes/"

const FONT_UI_MEDIUM   := FONT_DIR + "ChakraPetch-Medium.ttf"     # weight 500
const FONT_UI_SEMIBOLD := FONT_DIR + "ChakraPetch-SemiBold.ttf"   # weight 600
const FONT_UI_BOLD     := FONT_DIR + "ChakraPetch-Bold.ttf"       # weight 700
const FONT_MONO        := FONT_DIR + "IBMPlexMono-Regular.ttf"    # weight 400
const FONT_MONO_MEDIUM := FONT_DIR + "IBMPlexMono-Medium.ttf"     # weight 500

# The only font on a stock Windows install carrying all seven missing glyphs.
# Chained as a FontVariation fallback rather than used directly. If this is ever
# swapped for a bundled face, font_card() is the single place to change.
const FONT_SYMBOL_FALLBACK := "C:/Windows/Fonts/seguisym.ttf"

# ─── Themes ──────────────────────────────────────────────────────────────────
# Adding a theme means adding a block here with EVERY key present. Values are
# deliberately not derived from one another: Spectrum has a light field, where
# the alpha-white panel/line/slot/chip tokens would vanish and locked-item
# silhouettes must not be inverted, so each theme states its own.
const THEMES := {
	"spectrum_night": {
		# Chrome — the header and footer bars
		"chrome_grad_a":     Color("7B3FD4"),   # 0%
		"chrome_grad_b":     Color("E8459B"),   # 52%
		"chrome_grad_c":     Color("F5793B"),   # 100%
		"chrome_fg":         Color("FFFFFF"),
		"chrome_pattern":    Color(1.0, 1.0, 1.0, 0.06),

		# Field — the play area / content background
		"field":             Color("171126"),
		"field_glow_top":    Color(0.910, 0.271, 0.608, 0.18),   # E8459B @18%
		"field_glow_bottom": Color(0.961, 0.475, 0.231, 0.16),   # F5793B @16%
		"field_glow_left":   Color("241740"),
		"field_glow_right":  Color("3A1533"),
		"field_texture":     Color(1.0, 1.0, 1.0, 0.026),
		"field_fg":          Color("F4EDFA"),
		"field_mute":        Color("C9BBE0"),

		# Surfaces and lines
		"panel":             Color(1.0, 1.0, 1.0, 0.065),
		"line":              Color(1.0, 1.0, 1.0, 0.14),
		"slot":              Color(1.0, 1.0, 1.0, 0.16),
		"slot_fill":         Color(1.0, 1.0, 1.0, 0.03),
		"chip_bg":           Color(0.078, 0.047, 0.133, 0.62),   # 140C22 @62%
		"chip_line":         Color(1.0, 1.0, 1.0, 0.18),
		"chip_fg":           Color("E7DCF5"),

		# Accents and semantics
		"accent":            Color("FF7FC4"),   # player side, payable, selection, active
		"accent_2":          Color("FFA45C"),   # opponent side, powers, damage blocks
		"good":              Color("67D79B"),   # remaining HP, prices, confirm
		"danger":            Color("E5484D"),   # destructive actions (was kenneyUI-red)
		"warn":              Color("EFC44F"),   # toggle-on state (was kenneyUI-yellow)

		# Status conditions. PSN and CNF come from the spec; the other three are
		# added because the match engine has five conditions, not two.
		"status_psn":        Color("C93A9B"),
		"status_cnf":        Color("E07A2E"),
		"status_par":        Color("D8A82A"),
		"status_asl":        Color("6E7BC4"),
		"status_brn":        Color("E2603A"),

		# Buttons
		"btn_primary_top":   Color("B4459B"),
		"btn_primary_bot":   Color("7B3FD4"),
		"btn_primary_fg":    Color("FFFFFF"),
		"btn_secondary":     Color(1.0, 1.0, 1.0, 0.16),
		"btn_secondary_fg":  Color("FFFFFF"),
		"btn_edge":          Color(0.0, 0.0, 0.0, 0.30),

		# Locked collection tiles. False means "draw the silhouette as-is";
		# a light field would need it inverted so it stays visible.
		"silhouette_invert": false,
		"silhouette_alpha":  0.34,
	},

	# ── Parked. Present so the dictionary shape is proven, not reachable. ──
	"spectrum": {
		"chrome_grad_a": Color("7B3FD4"), "chrome_grad_b": Color("E8459B"), "chrome_grad_c": Color("F5793B"),
		"chrome_fg": Color("FFFFFF"), "chrome_pattern": Color(1.0, 1.0, 1.0, 0.06),
		"field": Color("F4F1F8"),
		"field_glow_top": Color(0.953, 0.894, 0.984, 1.0), "field_glow_bottom": Color(1.0, 0.906, 0.863, 1.0),
		"field_glow_left": Color("F3E4FB"), "field_glow_right": Color("FFE7DC"),
		"field_texture": Color(0.0, 0.0, 0.0, 0.030),
		"field_fg": Color("1E1729"), "field_mute": Color("6B6180"),
		"panel": Color(0.0, 0.0, 0.0, 0.045), "line": Color(0.0, 0.0, 0.0, 0.12),
		"slot": Color(0.0, 0.0, 0.0, 0.16), "slot_fill": Color(0.0, 0.0, 0.0, 0.03),
		"chip_bg": Color(1.0, 1.0, 1.0, 0.72), "chip_line": Color(0.0, 0.0, 0.0, 0.14),
		"chip_fg": Color("2A2136"),
		"accent": Color("D63C8F"), "accent_2": Color("E07A2E"), "good": Color("2F9E68"),
		"danger": Color("D03439"), "warn": Color("C79A1E"),
		"status_psn": Color("C93A9B"), "status_cnf": Color("E07A2E"), "status_par": Color("D8A82A"),
		"status_asl": Color("6E7BC4"), "status_brn": Color("E2603A"),
		"btn_primary_top": Color("B4459B"), "btn_primary_bot": Color("7B3FD4"), "btn_primary_fg": Color("FFFFFF"),
		"btn_secondary": Color(0.0, 0.0, 0.0, 0.07), "btn_secondary_fg": Color("3A3048"),
		"btn_edge": Color(0.0, 0.0, 0.0, 0.22),
		"silhouette_invert": true, "silhouette_alpha": 0.30,
	},
	"dusk": {
		"chrome_grad_a": Color("241B3A"), "chrome_grad_b": Color("2F1F45"), "chrome_grad_c": Color("3A2450"),
		"chrome_fg": Color("FFFFFF"), "chrome_pattern": Color(1.0, 1.0, 1.0, 0.06),
		"field": Color("1A1630"),
		"field_glow_top": Color(0.941, 0.627, 0.235, 0.06), "field_glow_bottom": Color(0.941, 0.627, 0.235, 0.13),
		"field_glow_left": Color("241740"), "field_glow_right": Color("2A1E3C"),
		"field_texture": Color(1.0, 1.0, 1.0, 0.026),
		"field_fg": Color("EFEAF7"), "field_mute": Color("9C90B8"),
		"panel": Color(1.0, 1.0, 1.0, 0.065), "line": Color(1.0, 1.0, 1.0, 0.14),
		"slot": Color(1.0, 1.0, 1.0, 0.16), "slot_fill": Color(1.0, 1.0, 1.0, 0.03),
		"chip_bg": Color(0.078, 0.047, 0.133, 0.62), "chip_line": Color(1.0, 1.0, 1.0, 0.18),
		"chip_fg": Color("E7DCF5"),
		"accent": Color("F0A03C"), "accent_2": Color("D98A5A"), "good": Color("67D79B"),
		"danger": Color("E5484D"), "warn": Color("EFC44F"),
		"status_psn": Color("C93A9B"), "status_cnf": Color("E07A2E"), "status_par": Color("D8A82A"),
		"status_asl": Color("6E7BC4"), "status_brn": Color("E2603A"),
		"btn_primary_top": Color("C0803A"), "btn_primary_bot": Color("8A5A2A"), "btn_primary_fg": Color("FFFFFF"),
		"btn_secondary": Color(1.0, 1.0, 1.0, 0.08), "btn_secondary_fg": Color("D9CBEC"),
		"btn_edge": Color(0.0, 0.0, 0.0, 0.30),
		"silhouette_invert": false, "silhouette_alpha": 0.34,
	},
	"circuit": {
		"chrome_grad_a": Color("05070C"), "chrome_grad_b": Color("05070C"), "chrome_grad_c": Color("05070C"),
		"chrome_fg": Color("DFF7F5"), "chrome_pattern": Color(0.0, 0.898, 0.831, 0.10),
		"field": Color("06090F"),
		"field_glow_top": Color(0.0, 0.898, 0.831, 0.05), "field_glow_bottom": Color(0.0, 0.898, 0.831, 0.05),
		"field_glow_left": Color("06090F"), "field_glow_right": Color("06090F"),
		"field_texture": Color(0.0, 0.898, 0.831, 0.055),
		"field_fg": Color("DFF7F5"), "field_mute": Color("7FA6B2"),
		"panel": Color(0.0, 0.898, 0.831, 0.05), "line": Color(0.0, 0.898, 0.831, 0.20),
		"slot": Color(0.0, 0.898, 0.831, 0.22), "slot_fill": Color(0.0, 0.898, 0.831, 0.03),
		"chip_bg": Color(0.02, 0.03, 0.05, 0.72), "chip_line": Color(0.0, 0.898, 0.831, 0.26),
		"chip_fg": Color("DFF7F5"),
		"accent": Color("00E5D4"), "accent_2": Color("4FD0E5"), "good": Color("3FD98A"),
		"danger": Color("FF5A63"), "warn": Color("E5C14F"),
		"status_psn": Color("C93A9B"), "status_cnf": Color("E07A2E"), "status_par": Color("D8A82A"),
		"status_asl": Color("6E7BC4"), "status_brn": Color("E2603A"),
		"btn_primary_top": Color("0C8E86"), "btn_primary_bot": Color("065550"), "btn_primary_fg": Color("DFF7F5"),
		"btn_secondary": Color(0.0, 0.898, 0.831, 0.07), "btn_secondary_fg": Color("A9D9D5"),
		"btn_edge": Color(0.0, 0.0, 0.0, 0.35),
		"silhouette_invert": false, "silhouette_alpha": 0.34,
	},
}

const DEFAULT_THEME := "spectrum_night"

# ─── Energy type colours ─────────────────────────────────────────────────────
# Used for attack cost pips, the deck builder's energy tiles and the card
# search type chips. This is the ONE place in the UI where hue carries data,
# so these sit outside the theme dictionary — they must not shift when the
# theme does. Colorless and Metal are light enough to need dark text; the rest
# take white. energy_fg() answers that.
const ENERGY_COLOUR := {
	"Grass":     Color("4E9B4E"),
	"Fire":      Color("D2453B"),
	"Water":     Color("3B7FBE"),
	"Lightning": Color("D8A82A"),
	"Psychic":   Color("8B5AA8"),
	"Fighting":  Color("C4622F"),
	"Colorless": Color("D5CFC2"),
	"Darkness":  Color("3A3F4A"),
	"Metal":     Color("9AA5B2"),
}
const ENERGY_FG_DARK := ["Colorless", "Metal"]

# ─── Type scale ──────────────────────────────────────────────────────────────
# Sizes are px at 1920x1080 before ui_scale. "face" picks the file; "track" is
# letter-spacing in em; "upper" records whether the role is authored in caps.
#
# THE CASING RULE: uppercase is for labels, buttons, titles and Pokemon names
# only. Anything the player has to READ — dialogue, attack text, card effects —
# is sentence case. That is the whole point of leaving Kenney behind, so do not
# reintroduce to_upper() on body text. Use cased() and let the role decide.
const TYPE := {
	"title":         { "size": 29.0,  "face": FONT_UI_BOLD,     "track": 0.11, "upper": true  },
	"subtitle":      { "size": 18.0,  "face": FONT_UI_SEMIBOLD, "track": 0.09, "upper": true  },
	"name":          { "size": 19.0,  "face": FONT_UI_BOLD,     "track": 0.09, "upper": true  },
	"button":        { "size": 17.0,  "face": FONT_UI_BOLD,     "track": 0.12, "upper": true  },
	"chip":          { "size": 17.0,  "face": FONT_UI_SEMIBOLD, "track": 0.07, "upper": false },
	"attack_name":   { "size": 16.0,  "face": FONT_UI_SEMIBOLD, "track": 0.03, "upper": false },
	"attack_damage": { "size": 19.0,  "face": FONT_MONO_MEDIUM, "track": 0.0,  "upper": false },
	"hp":            { "size": 17.0,  "face": FONT_MONO_MEDIUM, "track": 0.0,  "upper": false },
	# ISSUE #232: the caption face was IBM Plex Mono REGULAR (weight 400) at 13.5px
	# with heavy tracking - the thinnest type on the board, and every label the
	# fix named ("YOU", "OPPONENT", "YOUR PRIZES", the turn label) is this role.
	# MEDIUM (weight 500) at 14 is the "make it bold" half; font_at() is the
	# native half.
	"small_label":   { "size": 14.0,  "face": FONT_MONO_MEDIUM, "track": 0.19, "upper": true  },
	"body":          { "size": 22.0,  "face": FONT_UI_MEDIUM,   "track": 0.0,  "upper": false },
}

# ─── Metrics ─────────────────────────────────────────────────────────────────
# Every value is px at 1920x1080 before ui_scale. Read them through m() / mi().
const METRICS := {
	# Chrome bars
	"header_h":          92.0,    # standard, every screen
	"header_tall_h":     140.0,   # title + subtitle; target-selection screens only
	"footer_slim_h":     92.0,    # every screen EXCEPT the match board
	"footer_match_h":    162.0,   # the match board only — it holds the hand

	# Radii
	"corner_radius":     11.0,    # chips, small styleboxes
	# ISSUE #184: buttons are pills, not rounded rectangles. 22 against the 48px
	# button height reads as a full pill without the 9-patch corners meeting.
	# Build_UI_Themes derives its TEX_MARGIN from this — re-run it after a change.
	"btn_radius":        22.0,
	"panel_radius":      15.0,
	"slot_radius":       7.0,

	# Button
	"btn_pad_v":         13.0,
	"btn_pad_h":         29.0,
	"btn_edge_h":        5.0,     # the single inset bottom edge
	"btn_hover_lift":    0.06,    # fill lightened by this much on hover

	# Chip
	"chip_pad_v":        6.0,
	"chip_pad_h":        14.0,

	# Empty slot
	"slot_outline":      3.0,

	# Meter — fractional progress only. Whole numbers get a box.
	"meter_h":           12.0,
	"meter_radius":      6.0,

	# Damage counters — ONE block per 10 HP, never a continuous bar, because
	# attacks and effects key off counter counts.
	"dmg_active_w":      16.0,
	"dmg_active_h":      27.0,
	"dmg_active_gap":    4.0,
	# ISSUE #234: bench counters -10% across the board (blocks and gap alike).
	"dmg_bench_w":       8.64,
	"dmg_bench_h":       14.4,
	"dmg_bench_gap":     2.7,
	"dmg_bench_drop":    22.0,    # below the card, centred

	# Layout
	"field_pad_v":       21.0,
	"field_pad_h":       29.0,
}

# ─── Selection feedback ──────────────────────────────────────────────────────
# The grow/shrink is how selection reads everywhere in this game and does not
# change. The rotating gradient ring is added on top of it.
const SEL_SCALE_CARD  := 1.06
const SEL_SCALE_TILE  := 1.14
const SEL_SCALE_TIME  := 0.15    # seconds, ease-out
const SEL_RING_PX     := 4.0     # ring thickness
const SEL_RING_PERIOD := 3.0     # seconds per revolution

# ─── Chevron motion ──────────────────────────────────────────────────────────
# Diagonal stripes on both chrome bars and the field, counter-scrolling. The
# loop distance MUST be an exact multiple of the pattern period or the texture
# visibly jumps on wrap — these pairs are chosen so it does not.
const CHEVRON_ANGLE_DEG    := 115.0
const CHEVRON_BAR_STRIPE   := 3.0
const CHEVRON_BAR_PERIOD   := 17.0
const CHEVRON_BAR_LOOP     := 34.0    # 2 periods
const CHEVRON_BAR_TIME     := 6.8     # seconds for one loop -> 5 px/s, scrolls RIGHT
const CHEVRON_FIELD_STRIPE := 18.0
const CHEVRON_FIELD_PERIOD := 74.0
const CHEVRON_FIELD_LOOP   := 74.0    # 1 period
const CHEVRON_FIELD_TIME   := 14.0    # seconds for one loop -> 5.3 px/s, scrolls LEFT

# ─── State ───────────────────────────────────────────────────────────────────

var current: String = DEFAULT_THEME

# Multiplies every type size and every metric. See the header comment — this is
# the first knob to reach for if the whole UI reads too small or too large.
var ui_scale: float = 1.0

# Cache so a screen rebuilding 200 labels does not reload the same .ttf 200
# times. Keyed by resource path, plus "card|<role>" for the fallback chains.
var _font_cache: Dictionary = {}

# ─── Colour ──────────────────────────────────────────────────────────────────

## The theme colour for `key`. An unknown key returns magenta and pushes a
## warning rather than crashing — a wrong colour is findable on screen, a crash
## mid-match is not.
func col(key: String) -> Color:
	var block: Dictionary = THEMES[current]
	if not block.has(key):
		push_warning("UITheme: no colour '%s' in theme '%s'" % [key, current])
		return Color.MAGENTA
	return block[key]


## A theme colour with its alpha replaced. For the many places that want `line`
## at half strength without earning a second token.
func col_a(key: String, alpha: float) -> Color:
	var c := col(key)
	c.a = alpha
	return c


## Non-colour theme values (silhouette_invert, silhouette_alpha).
func flag(key: String) -> Variant:
	return THEMES[current].get(key, null)


## The fill for one energy type's cost pip / chip. An unknown type falls back to
## Colorless, which is what the card data means by an unlabelled cost anyway.
func energy_colour(type_name: String) -> Color:
	return ENERGY_COLOUR.get(type_name, ENERGY_COLOUR["Colorless"])


## Text colour to sit on top of energy_colour() for the same type.
func energy_fg(type_name: String) -> Color:
	if type_name in ENERGY_FG_DARK:
		return Color("1A1420")
	return Color.WHITE


## Solid fill for a status condition chip. Accepts the short codes the match
## engine uses ("PSN", "CNF", "PAR", "ASL", "BRN") in any case.
func status_colour(code: String) -> Color:
	var key := "status_" + code.to_lower()
	if THEMES[current].has(key):
		return col(key)
	return col("accent_2")

# ─── Type ────────────────────────────────────────────────────────────────────

## Point size for a type role, already multiplied by ui_scale and rounded to a
## whole pixel — Godot rasterises at integer sizes and a fractional request gets
## truncated inconsistently between labels.
func size(role: String) -> int:
	if not TYPE.has(role):
		push_warning("UITheme: no type role '%s'" % role)
		return int(round(17.0 * ui_scale))
	return int(round(float(TYPE[role]["size"]) * ui_scale))


## Letter-spacing for a role, in em. Multiply by size() to get pixels.
func tracking(role: String) -> float:
	if not TYPE.has(role):
		return 0.0
	return float(TYPE[role]["track"])


## Letter-spacing for a role in whole pixels, ready for
## `label.add_theme_constant_override("font_spacing_glyph", ...)`.
func tracking_px(role: String) -> int:
	return int(round(tracking(role) * float(size(role))))


## Whether a role is authored in uppercase. Call this instead of scattering
## to_upper() — it keeps the casing rule in one place and makes the roles that
## must stay sentence case impossible to get wrong by accident.
func is_upper(role: String) -> bool:
	if not TYPE.has(role):
		return false
	return bool(TYPE[role]["upper"])


## Applies a role's casing to a string. Body, attack and chip text passes
## through untouched; titles, buttons and names come back uppercased.
func cased(role: String, text: String) -> String:
	return text.to_upper() if is_upper(role) else text


## The font file a role is set in. Size is applied separately by the caller
## through `font_size`, so one FontFile serves every size of that face.
func font(role: String) -> Font:
	var path: String = FONT_UI_MEDIUM
	if TYPE.has(role):
		path = String(TYPE[role]["face"])
	return font_at(path)


## ISSUE #232: HOW EVERY FACE IN THE GAME IS RASTERISED. TWEAKABLE.
##
## The complaint was that thin strokes at small sizes wash out. That is not a
## colour problem and not a weight problem - it is what happens when a 1px stem
## lands across a pixel boundary and the antialiaser splits it into two half-lit
## pixels. Godot exposes the three knobs that decide it and defaults all three to
## the blurry end:
##
##   hinting NORMAL + force_autohinter - snaps stems onto whole pixels, so a
##     vertical stroke is one solid pixel instead of two grey ones.
##   subpixel_positioning DISABLED     - glyph origins land on integers, so the
##     same letter rasterises identically everywhere instead of being resampled
##     at a fractional offset.
##   antialiasing GRAY                 - plain greyscale. LCD subpixel is sharper
##     still but fringes colour, which is worse on a coloured field.
##
## Applied once per face on first load, so it costs nothing per label. Together
## with `small_label` moving up to the MEDIUM weight (see TYPE) this is the
## "anything native" half of the fix, before reaching for bold everywhere.
const FONT_HINTING      := TextServer.HINTING_NORMAL
const FONT_AUTOHINT     := true
const FONT_SUBPIXEL     := TextServer.SUBPIXEL_POSITIONING_DISABLED
const FONT_ANTIALIASING := TextServer.FONT_ANTIALIASING_GRAY

## Any of the five faces by path, cached.
func font_at(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path]
	var f: Font = load(path)
	if f == null:
		push_error("UITheme: could not load font " + path)
		return ThemeDB.fallback_font
	# ISSUE #232: sharpen on the way in. FontFile is the only class carrying
	# these; a fallback Font or a FontVariation is left alone.
	if f is FontFile:
		var ff := f as FontFile
		ff.antialiasing = FONT_ANTIALIASING
		ff.hinting = FONT_HINTING
		ff.force_autohinter = FONT_AUTOHINT
		ff.subpixel_positioning = FONT_SUBPIXEL
		ff.multichannel_signed_distance_field = false
	_font_cache[path] = f
	return f


## The face to use for CARD TEXT specifically — attack names, ability text,
## Pokemon names, anything read out of the set JSON.
##
## Chakra Petch has no  δ ★ ♀ ♂ α β γ  (verified with fontTools), exactly like
## kenvector_future before it, and all seven appear in real card data: δ on
## every Delta Species card, ★ on every Pokemon Star, ♀/♂ on Nidoran. Godot's
## built-in fallback covers δ α β γ but not ★ ♀ ♂, so a system font is chained
## after it. A line containing a fallback glyph renders ~22% taller, which is
## why CardDetailPanel measures line heights per line rather than once.
func font_card(role: String = "body") -> Font:
	var cache_key := "card|" + role
	if _font_cache.has(cache_key):
		return _font_cache[cache_key]

	var variation := FontVariation.new()
	variation.base_font = font(role)

	var chain: Array[Font] = []
	if FileAccess.file_exists(FONT_SYMBOL_FALLBACK):
		var sym := FontFile.new()
		if sym.load_dynamic_font(FONT_SYMBOL_FALLBACK) == OK:
			chain.append(sym)
	variation.fallbacks = chain

	_font_cache[cache_key] = variation
	return variation

# ─── Metrics ─────────────────────────────────────────────────────────────────

## A layout metric in pixels, already multiplied by ui_scale.
func m(key: String) -> float:
	if not METRICS.has(key):
		push_warning("UITheme: no metric '%s'" % key)
		return 0.0
	return float(METRICS[key]) * ui_scale


## Metric rounded to a whole pixel — for anything fed to a container constant or
## a control size, where a fraction leaves a seam.
func mi(key: String) -> int:
	return int(round(m(key)))

# ─── Motion ──────────────────────────────────────────────────────────────────

## True when the player has asked for reduced motion. Gates the chevron scroll,
## the selection ring rotation and any purely decorative movement.
##
## Read through GameState rather than cached, and guarded so this autoload does
## not care whether it loaded before or after GameState. The setting itself
## arrives in stage 2 with the Options rebuild; until then this is always false,
## which is the correct default.
func motion_reduced() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if not ("reduce_motion_setting" in gs):
		return false
	return String(gs.get("reduce_motion_setting")) == "where_possible"

# ─── Theme switching ─────────────────────────────────────────────────────────

## Not reachable from any UI — there is no theme picker and the spec says not to
## build one yet. It exists so the parked themes are exercisable from the debug
## console, and so screens are written to listen for a change rather than to
## assume there will never be one.
func set_theme(theme_name: String) -> void:
	if not THEMES.has(theme_name):
		push_warning("UITheme: unknown theme '%s'" % theme_name)
		return
	if theme_name == current:
		return
	current = theme_name
	theme_changed.emit()
