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
#
# ── THE BUTTON RULE ──────────────────────────────────────────
# Written down because the first pass invented button colours per theme and the
# result did not line up: Spectrum Night's primary was a dull magenta belonging
# to no other element, and its secondary was twice the strength of the same
# button on the boot splash. A NEW THEME MUST FOLLOW THIS.
#
#   primary    A gradient from the theme's SIGNATURE stop down to its DEEP stop.
#              Where the chrome bar carries real colour, those are literally
#              chrome_grad_b over chrome_grad_a — Spectrum Night's confirm
#              button is now the header bar's own pink over its own purple.
#              Where the chrome bar is deliberately unsaturated (dusk's near
#              black, circuit's flat panel) there is no signature stop to borrow,
#              so primary derives from `accent` instead: a mid-strength version
#              of the accent over a darkened one. Never a colour that appears
#              nowhere else.
#
#   secondary  A flat 10% tint of the FIELD's own polarity — white at 0.10 on a
#              dark field, black at 0.10 on a light one — with a label that is
#              NOT pure white. A secondary whose label matches primary's exactly
#              stops reading as the lesser of the two choices. The boot splash's
#              New Game button takes this same face, so the pair the player sees
#              first is the pair they see everywhere after.
#
#   The gradient-versus-flat difference is what keeps primary apart from the
#   `selected` variant, which is flat chrome_grad_b. Do not give primary a flat
#   fill or the two collapse into each other.
const THEMES := {
	# Eight looks, each in a Dark and a Light variant. Every block is 39 keys in
	# the order Docs/THEME_TEMPLATE_SPEC.md lays out, and every one is checked by
	# Scripts/Utilities/Theme_Audit.gd. Add a theme here, re-run the builder, then
	# re-run the audit; nothing else enumerates theme names.
	#
	# Four of the eight bars are FLAT — grad_a == grad_b == grad_c. That is not an
	# oversight: those designs have no gradient, and setting the three stops equal
	# expresses it without needing a key to say so.

	"sunset_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("7B3FD4"),
		"chrome_grad_b":      Color("DE1C82"),
		"chrome_grad_c":      Color("CD4B0A"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("171126"),
		"field_glow_top":     Color(0.910, 0.271, 0.608, 0.180),
		"field_glow_bottom":  Color(0.961, 0.475, 0.231, 0.160),
		"field_glow_left":    Color("241740"),
		"field_glow_right":   Color("3A1533"),
		"field_texture":      Color(1.000, 1.000, 1.000, 0.026),
		"field_fg":           Color("F4EDFA"),
		"field_mute":         Color("A493C4"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.078, 0.047, 0.133, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("E7DCF5"),

		# Accents and semantics
		"accent":             Color("FF7FC4"),
		"accent_2":           Color("FFA45C"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("E8459B"),
		"btn_primary_bot":    Color("7B3FD4"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("D9CBEC"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"sunset_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("7B3FD4"),
		"chrome_grad_b":      Color("DE1C82"),
		"chrome_grad_c":      Color("CD4B0A"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("F4F1F8"),
		"field_glow_top":     Color(0.910, 0.271, 0.608, 0.100),
		"field_glow_bottom":  Color(0.961, 0.475, 0.231, 0.090),
		"field_glow_left":    Color("F3E4FB"),
		"field_glow_right":   Color("FFE7DC"),
		"field_texture":      Color(0.471, 0.353, 0.627, 0.040),
		"field_fg":           Color("1E1729"),
		"field_mute":         Color("6B6180"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("4A3866"),

		# Accents and semantics
		"accent":             Color("B4327A"),
		"accent_2":           Color("C4531B"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("E8459B"),
		"btn_primary_bot":    Color("7B3FD4"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("4A3866"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"tide_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("4B4BDD"),
		"chrome_grad_b":      Color("16828C"),
		"chrome_grad_c":      Color("248724"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("152728"),
		"field_glow_top":     Color(0.294, 0.294, 0.867, 0.180),
		"field_glow_bottom":  Color(0.208, 0.761, 0.208, 0.160),
		"field_glow_left":    Color("182042"),
		"field_glow_right":   Color("162A16"),
		"field_texture":      Color(1.000, 1.000, 1.000, 0.026),
		"field_fg":           Color("F1F8F8"),
		"field_mute":         Color("A2C1C3"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.055, 0.102, 0.106, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("D7E9EA"),

		# Accents and semantics
		"accent":             Color("7BE0EA"),
		"accent_2":           Color("86DF86"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("16838C"),
		"btn_primary_bot":    Color("4B4BDD"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("CCDFE0"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"tide_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("4B4BDD"),
		"chrome_grad_b":      Color("16828C"),
		"chrome_grad_c":      Color("248724"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("F0F9F9"),
		"field_glow_top":     Color(0.294, 0.294, 0.867, 0.090),
		"field_glow_bottom":  Color(0.208, 0.761, 0.208, 0.080),
		"field_glow_left":    Color("E2E4FB"),
		"field_glow_right":   Color("E6F7E6"),
		"field_texture":      Color(0.212, 0.467, 0.490, 0.050),
		"field_fg":           Color("112527"),
		"field_mute":         Color("4E7174"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("366063"),

		# Accents and semantics
		"accent":             Color("1DA3AF"),
		"accent_2":           Color("29A329"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("16838C"),
		"btn_primary_bot":    Color("4B4BDD"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("366063"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"canopy_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("2DA99F"),
		"chrome_grad_b":      Color("4BAE37"),
		"chrome_grad_c":      Color("EDBA21"),
		"chrome_fg":          Color("10131A"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("182815"),
		"field_glow_top":     Color(0.176, 0.663, 0.624, 0.180),
		"field_glow_bottom":  Color(0.929, 0.729, 0.129, 0.160),
		"field_glow_left":    Color("0F2A28"),
		"field_glow_right":   Color("2A2210"),
		"field_texture":      Color(1.000, 1.000, 1.000, 0.026),
		"field_fg":           Color("F2F8F1"),
		"field_mute":         Color("A7C3A2"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.063, 0.106, 0.055, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("DAEAD7"),

		# Accents and semantics
		"accent":             Color("98DA8B"),
		"accent_2":           Color("F4D371"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("3A862B"),
		"btn_primary_bot":    Color("23837C"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("CFE0CC"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"canopy_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("2DA99F"),
		"chrome_grad_b":      Color("4BAE37"),
		"chrome_grad_c":      Color("EDBA21"),
		"chrome_fg":          Color("10131A"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color(0.0, 0.0, 0.0, 0.0),
		# Field — the play area / content background
		"field":              Color("F2F9F0"),
		"field_glow_top":     Color(0.176, 0.663, 0.624, 0.090),
		"field_glow_bottom":  Color(0.929, 0.729, 0.129, 0.090),
		"field_glow_left":    Color("DEF4F2"),
		"field_glow_right":   Color("FBF2D8"),
		"field_texture":      Color(0.255, 0.490, 0.212, 0.050),
		"field_fg":           Color("152711"),
		"field_mute":         Color("54744E"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("3D6336"),

		# Accents and semantics
		"accent":             Color("3DA329"),
		"accent_2":           Color("BD910F"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("3A862B"),
		"btn_primary_bot":    Color("23837C"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("3D6336"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"gengar_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("241B3A"),
		"chrome_grad_b":      Color("2F2045"),
		"chrome_grad_c":      Color("3A2450"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.045),
		"chrome_line":        Color(1.0, 1.0, 1.0, 0.10),
		# Field — the play area / content background
		"field":              Color("1A1630"),
		"field_glow_top":     Color(0.878, 0.439, 0.604, 0.140),
		"field_glow_bottom":  Color(0.941, 0.627, 0.235, 0.160),
		"field_glow_left":    Color("2E2148"),
		"field_glow_right":   Color("3A1F3C"),
		"field_texture":      Color(1.000, 1.000, 1.000, 0.022),
		"field_fg":           Color("EFEAF7"),
		"field_mute":         Color("9C90B8"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.071, 0.063, 0.133, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("DDD4EC"),

		# Accents and semantics
		"accent":             Color("F0A03C"),
		"accent_2":           Color("E0709A"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("F0A03C"),
		"btn_primary_bot":    Color("B86C0E"),
		"btn_primary_fg":     Color("0D0D12"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("CDC2E0"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"gengar_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("241B3A"),
		"chrome_grad_b":      Color("2F2045"),
		"chrome_grad_c":      Color("3A2450"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.045),
		"chrome_line":        Color(1.0, 1.0, 1.0, 0.10),
		# Field — the play area / content background
		"field":              Color("F6F2FB"),
		"field_glow_top":     Color(0.878, 0.439, 0.604, 0.090),
		"field_glow_bottom":  Color(0.941, 0.627, 0.235, 0.090),
		"field_glow_left":    Color("F2E6FA"),
		"field_glow_right":   Color("FFEEDC"),
		"field_texture":      Color(0.471, 0.353, 0.627, 0.040),
		"field_fg":           Color("1F1830"),
		"field_mute":         Color("665A80"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("4B3D66"),

		# Accents and semantics
		"accent":             Color("8A5600"),
		"accent_2":           Color("B03462"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("8A5600"),
		"btn_primary_bot":    Color("241600"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("4B3D66"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"shuppet_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("0C0F15"),
		"chrome_grad_b":      Color("0C0F15"),
		"chrome_grad_c":      Color("0C0F15"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.050),
		"chrome_line":        Color(1.0, 1.0, 1.0, 0.08),
		# Field — the play area / content background
		"field":              Color("0F1219"),
		"field_glow_top":     Color(0.941, 0.451, 0.420, 0.180),
		"field_glow_bottom":  Color(0.302, 0.639, 0.961, 0.180),
		"field_glow_left":    Color("1A202B"),
		"field_glow_right":   Color("141B26"),
		"field_texture":      Color(1.000, 1.000, 1.000, 0.025),
		"field_fg":           Color("E9ECF1"),
		"field_mute":         Color("8A93A6"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.031, 0.035, 0.051, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("D9DFE9"),

		# Accents and semantics
		"accent":             Color("4DA3F5"),
		"accent_2":           Color("F0736B"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("4DA3F5"),
		"btn_primary_bot":    Color("0C70D0"),
		"btn_primary_fg":     Color("0D0D12"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("AEB7C6"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"shuppet_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("4C4F54"),
		"chrome_grad_b":      Color("4C4F54"),
		"chrome_grad_c":      Color("4C4F54"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.050),
		"chrome_line":        Color(1.0, 1.0, 1.0, 0.08),
		# Field — the play area / content background
		"field":              Color("F2F5FA"),
		"field_glow_top":     Color(0.941, 0.451, 0.420, 0.090),
		"field_glow_bottom":  Color(0.302, 0.639, 0.961, 0.090),
		"field_glow_left":    Color("E2EEFC"),
		"field_glow_right":   Color("FDE7E3"),
		"field_texture":      Color(0.157, 0.275, 0.471, 0.045),
		"field_fg":           Color("121924"),
		"field_mute":         Color("59667A"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("33404F"),

		# Accents and semantics
		"accent":             Color("1668C4"),
		"accent_2":           Color("B8402F"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("1668C4"),
		"btn_primary_bot":    Color("0C3768"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("33404F"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"code_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("05070C"),
		"chrome_grad_b":      Color("05070C"),
		"chrome_grad_c":      Color("05070C"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(0.000, 0.898, 0.831, 0.070),
		"chrome_line":        Color(0.0, 0.898, 0.831, 0.35),
		# Field — the play area / content background
		"field":              Color("06090F"),
		"field_glow_top":     Color(1.000, 0.239, 0.541, 0.150),
		"field_glow_bottom":  Color(0.000, 0.898, 0.831, 0.160),
		"field_glow_left":    Color("0A1A1C"),
		"field_glow_right":   Color("14101A"),
		"field_texture":      Color(0.000, 0.898, 0.831, 0.050),
		"field_fg":           Color("DFF7F5"),
		"field_mute":         Color("7FA6B2"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.024, 0.035, 0.059, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("9BEDE6"),

		# Accents and semantics
		"accent":             Color("00E5D4"),
		"accent_2":           Color("FF3D8A"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("00E5D4"),
		"btn_primary_bot":    Color("007F76"),
		"btn_primary_fg":     Color("0D0D12"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("9BEDE6"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"code_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("05070C"),
		"chrome_grad_b":      Color("05070C"),
		"chrome_grad_c":      Color("05070C"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(0.000, 0.898, 0.831, 0.070),
		"chrome_line":        Color(0.0, 0.898, 0.831, 0.35),
		# Field — the play area / content background
		"field":              Color("EFF7F6"),
		"field_glow_top":     Color(1.000, 0.239, 0.541, 0.080),
		"field_glow_bottom":  Color(0.000, 0.898, 0.831, 0.080),
		"field_glow_left":    Color("DCF6F2"),
		"field_glow_right":   Color("FFE2EC"),
		"field_texture":      Color(0.000, 0.471, 0.431, 0.050),
		"field_fg":           Color("0B1A1C"),
		"field_mute":         Color("4C6467"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("17494A"),

		# Accents and semantics
		"accent":             Color("00706A"),
		"accent_2":           Color("C4005A"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("00706A"),
		"btn_primary_bot":    Color("001413"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("17494A"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"umbreon_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("1B1F2A"),
		"chrome_grad_b":      Color("1B1F2A"),
		"chrome_grad_c":      Color("1B1F2A"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(0.941, 0.906, 0.831, 0.050),
		"chrome_line":        Color("C8A24A"),
		# Field — the play area / content background
		"field":              Color("141821"),
		"field_glow_top":     Color(0.498, 0.659, 0.722, 0.150),
		"field_glow_bottom":  Color(0.784, 0.635, 0.290, 0.150),
		"field_glow_left":    Color("1D2432"),
		"field_glow_right":   Color("221E1A"),
		"field_texture":      Color(0.941, 0.906, 0.831, 0.030),
		"field_fg":           Color("F1EADB"),
		"field_mute":         Color("9A9382"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.047, 0.059, 0.078, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("E8DCC0"),

		# Accents and semantics
		"accent":             Color("C8A24A"),
		"accent_2":           Color("7FA8B8"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("C8A24A"),
		"btn_primary_bot":    Color("846828"),
		"btn_primary_fg":     Color("0D0D12"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("D8CDB4"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"umbreon_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("1B1F2A"),
		"chrome_grad_b":      Color("1B1F2A"),
		"chrome_grad_c":      Color("1B1F2A"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(0.941, 0.906, 0.831, 0.050),
		"chrome_line":        Color("C8A24A"),
		# Field — the play area / content background
		"field":              Color("F7F3E9"),
		"field_glow_top":     Color(0.498, 0.659, 0.722, 0.080),
		"field_glow_bottom":  Color(0.784, 0.635, 0.290, 0.090),
		"field_glow_left":    Color("FBF0DC"),
		"field_glow_right":   Color("ECF2F2"),
		"field_texture":      Color(0.471, 0.392, 0.196, 0.050),
		"field_fg":           Color("171A21"),
		"field_mute":         Color("6A6355"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("4A4230"),

		# Accents and semantics
		"accent":             Color("8A6A12"),
		"accent_2":           Color("2F6E82"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("8A6A12"),
		"btn_primary_bot":    Color("302506"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("4A4230"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},

	"sharpedo_dark": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("16233F"),
		"chrome_grad_b":      Color("2E4A7A"),
		"chrome_grad_c":      Color("16233F"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color("C77F45"),
		# Field — the play area / content background
		"field":              Color("151A23"),
		"field_glow_top":     Color(0.498, 0.659, 0.878, 0.150),
		"field_glow_bottom":  Color(0.780, 0.498, 0.271, 0.170),
		"field_glow_left":    Color("121B2E"),
		"field_glow_right":   Color("241A16"),
		"field_texture":      Color(0.824, 0.902, 1.000, 0.030),
		"field_fg":           Color("F2F4F7"),
		"field_mute":         Color("A3AEC2"),

		# Surfaces and lines
		"panel":              Color(1.000, 1.000, 1.000, 0.065),
		"line":               Color(1.000, 1.000, 1.000, 0.140),
		"slot":               Color(1.000, 1.000, 1.000, 0.160),
		"slot_fill":          Color(1.000, 1.000, 1.000, 0.030),
		"chip_bg":            Color(0.051, 0.067, 0.086, 0.620),
		"chip_line":          Color(1.000, 1.000, 1.000, 0.180),
		"chip_fg":            Color("D8DEE8"),

		# Accents and semantics
		"accent":             Color("C77F45"),
		"accent_2":           Color("7FA8E0"),
		"good":               Color("67D79B"),
		"danger":             Color("EF6065"),
		"warn":               Color("EFC44F"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("C77F45"),
		"btn_primary_bot":    Color("804E26"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(1.000, 1.000, 1.000, 0.100),
		"btn_secondary_fg":   Color("CED4DE"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  false,
		"silhouette_alpha":   0.34,
	},

	"sharpedo_light": {

		# Chrome — the header and footer bars
		"chrome_grad_a":      Color("16233F"),
		"chrome_grad_b":      Color("2E4A7A"),
		"chrome_grad_c":      Color("16233F"),
		"chrome_fg":          Color("FFFFFF"),
		"chrome_pattern":     Color(1.000, 1.000, 1.000, 0.060),
		"chrome_line":        Color("C77F45"),
		# Field — the play area / content background
		"field":              Color("F3F4F7"),
		"field_glow_top":     Color(0.498, 0.659, 0.878, 0.080),
		"field_glow_bottom":  Color(0.780, 0.498, 0.271, 0.090),
		"field_glow_left":    Color("E2EAF7"),
		"field_glow_right":   Color("F8E9DC"),
		"field_texture":      Color(0.118, 0.235, 0.431, 0.050),
		"field_fg":           Color("131820"),
		"field_mute":         Color("4F5C72"),

		# Surfaces and lines
		"panel":              Color(0.000, 0.000, 0.000, 0.055),
		"line":               Color(0.000, 0.000, 0.000, 0.150),
		"slot":               Color(0.000, 0.000, 0.000, 0.180),
		"slot_fill":          Color(0.000, 0.000, 0.000, 0.040),
		"chip_bg":            Color(1.000, 1.000, 1.000, 0.850),
		"chip_line":          Color(0.000, 0.000, 0.000, 0.200),
		"chip_fg":            Color("37455D"),

		# Accents and semantics
		"accent":             Color("8A4E14"),
		"accent_2":           Color("26507F"),
		"good":               Color("16744A"),
		"danger":             Color("BC2126"),
		"warn":               Color("856208"),

		# Status conditions
		"status_psn":         Color("C93A9B"),
		"status_cnf":         Color("E07A2E"),
		"status_par":         Color("D8A82A"),
		"status_asl":         Color("6E7BC4"),
		"status_brn":         Color("E2603A"),

		# Buttons
		"btn_primary_top":    Color("8A4E14"),
		"btn_primary_bot":    Color("311C07"),
		"btn_primary_fg":     Color("FFFFFF"),
		"btn_secondary":      Color(0.000, 0.000, 0.000, 0.100),
		"btn_secondary_fg":   Color("37455D"),
		"btn_edge":           Color(0.000, 0.000, 0.000, 0.300),

		# Locked collection tiles
		"silhouette_invert":  true,
		"silhouette_alpha":   0.32,
	},
}

# sunset_dark is the look the game shipped in, under its old name spectrum_night.
const DEFAULT_THEME := "sunset_dark"

# ─── Display names ───────────────────────────────────────────────────────────
# DELIBERATELY EMPTY. theme_display_name() title-cases an id, so every current
# theme already reads correctly on the Options screen — "sunset_dark" shows as
# "Sunset Dark", "shuppet_light" as "Shuppet Light". Adding sixteen entries that
# each restate the id is sixteen more things to drift out of step.
#
# Add an entry ONLY when title-casing an id would read badly, which today is
# nothing. The Options row is built by walking THEMES, never from a list here,
# so a theme appears as a button the moment it is added and re-baked.
const THEME_NAMES := {}

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

# ─── Battle framing and dialogue chrome ──────────────────────────────────────
# The intro / win / loss / best-of-three screens and the message box.
#
# These sit OUTSIDE the theme dictionary for the same reason ENERGY_COLOUR does:
# hue carries meaning here rather than decoration. Win green and loss red must
# never become the accent purple, or the screen stops being able to say which
# way the match went before the word does.
#
# A "*_grad" entry is always THREE stops read left to right, and the same three
# feed both a band and the badge ring beside it — that pairing is what makes the
# ring read as part of the frame rather than an ornament dropped on top of it.
const BATTLE := {
	# Band + ring gradients, one set per screen.
	"band_intro_grad": [Color("7B3FD4"), Color("E8459B"), Color("F5793B")],
	"band_win_grad":   [Color("0FB8A6"), Color("2FCB63"), Color("C3E62E")],
	"band_loss_grad":  [Color("FF3D7F"), Color("DC1F32"), Color("FF6B2C")],

	# The word inside the badge, filled left to right with its own three stops.
	# Deliberately lighter than the band behind it — the badge sits on the dark
	# ground, not on the band, so it needs its own contrast.
	"vs_text_grad":   [Color("C79BFF"), Color("FF9BD6"), Color("FFC08A")],
	"win_text_grad":  [Color("3FE0C4"), Color("6BE87A"), Color("D8F04A")],
	"loss_text_grad": [Color("FF74A6"), Color("F2495A"), Color("FF9350")],

	# Best-of-three filled chips: the disc under the "Win" / "Loss" label.
	"disc_win_grad":  [Color("17A793"), Color("209F4C"), Color("6E9E12")],
	"disc_loss_grad": [Color("D02F68"), Color("B3182A"), Color("D1541F")],
	"disc_sheen":     Color(1.0, 1.0, 1.0, 0.22),

	# Per-side accents. The floor glow under each trainer and the rule under
	# their name both take these, so a side reads as one colour.
	"side_player":   Color("C79BFF"),
	"side_opponent": Color("FFA45C"),

	# Prize count under the intro badge, and the currency glyph in the rewards.
	"prize_gold": Color("FFD98A"),

	# Badge well — the dark disc the ring is drawn around.
	"badge_well": Color(0.047, 0.031, 0.078, 0.55),   # 0C0814 @55%

	# Sprite drop shadow, and the empty best-of-three ring's opacity.
	"sprite_shadow": Color(0.0, 0.0, 0.0, 0.55),
	"empty_ring_alpha": 0.45,
}

# The message box's own chrome. Shared by both variants; only the spine, the
# glow and the border treatment differ between them (see Dynamic_Message_Box).
const MSGBOX := {
	"bg":     Color(0.082, 0.055, 0.137, 0.94),   # 150E23 @94%
	"border": Color(1.0, 1.0, 1.0, 0.15),
	"shadow": Color(0.0, 0.0, 0.0, 0.60),
}

# The shop cash pill. Gold rather than a theme colour on purpose — money is the
# one thing on that box that is neither the speaker nor the UI.
const CASH_PILL := {
	"top": Color("F7C455"),
	"bot": Color("E8952F"),
	"fg":  Color("3A2410"),
}

# ─── Boot splash ─────────────────────────────────────────────────────────────
# The splash is the one screen with no chrome bars, no panels and its own type
# scale, so its handful of colours live here rather than being invented at the
# call site. Everything it can share it already does: the field comes from the
# theme block above, and Continue Game is the btn_primary_* gradient the rest of
# the game's confirm buttons use.
#
# The only things genuinely its own are the mark's four gradient stops and the
# rule's near colour. Both buttons now take the game's own faces: New Game is
# btn_secondary, Continue Game is the btn_primary_* gradient.
const SPLASH := {
	# The mark. Upper arm runs top-left to bottom-right, lower arm top-right to
	# bottom-left, so the pink is shared and lands in the middle of the lockup.
	"mark_upper_a": Color("7B3FD4"),
	"mark_upper_b": Color("E8459B"),
	"mark_lower_a": Color("E8459B"),
	"mark_lower_b": Color("F5793B"),

	# The rule. One near colour at the TCG cap, then each segment fades out
	# through its own side's accent at 35%.
	"rule_near":  Color("FF6FBE"),
	"rule_mid_l": Color(0.910, 0.271, 0.608, 0.35),   # E8459B @35%
	"rule_mid_r": Color(0.961, 0.475, 0.231, 0.35),   # F5793B @35%

	# The wordmark. TCG is a shade off white so it sits behind the two big words
	# rather than competing with them.
	"wordmark": Color("FFFFFF"),
	"tcg":      Color("F0E4FA"),

	# New Game's face and label. Continue Game takes btn_primary_top/bot/fg.
	#
	# These are now EXACTLY btn_secondary and btn_secondary_fg. They used to be
	# half-strength on the theory that a full secondary beside the primary read as
	# two equal choices — but the in-game secondary was 16% at the time, so the
	# very first pair of buttons the player ever sees did not match the pair on
	# every screen after it. Secondary came down to 10% instead, which gives the
	# hierarchy without splitting the token in two.
	"new_game_top": Color(1.0, 1.0, 1.0, 0.10),
	"new_game_bot": Color(1.0, 1.0, 1.0, 0.10),
	"new_game_fg":  Color("D9CBEC"),

	# Hover and press, composited OVER a face. Same values the baked button art
	# uses, so the splash buttons react like every other button in the game.
	"btn_hover": Color(1.0, 1.0, 1.0, 0.10),
	"btn_press": Color(0.0, 0.0, 0.0, 0.18),

	# The hand-off fade.
	"fade": Color("000000"),
}

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
	# 11, matching the chip radius. It was raised to 22 by ISSUE #184 to make
	# buttons read as pills; the theme mocks are all authored at 11 and that now
	# wins. Changing this changes every button face in every theme — re-run
	# Build_UI_Themes.gd after touching it.
	"btn_radius":        11.0,
	"panel_radius":      15.0,
	"slot_radius":       7.0,

	# Button
	# 10% off the BUTTON, not off the padding: a button is pad_v twice plus a
	# ~22px line box, so ~48px, and 10% of that is 4.8px split between the two
	# pads. Global, so every button in the game is a little shorter.
	"btn_pad_v":         10.6,
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
	# ISSUE #267: the active row is sized to MATCH THE ATTACK BUTTONS under it.
	# A 120HP Pokemon shows all 12 blocks, so 12*w + 11*gap has to come to
	# Main_Match_Core_Gameplay_Script.ACTION_PANEL_W (284): 12*20 + 11*4 = 284.
	# Width only — the height is what reads as a damage counter and it is unchanged.
	"dmg_active_w":      20.0,
	"dmg_active_h":      27.0,
	"dmg_active_gap":    4.0,
	# ISSUE #234: bench counters -10% across the board (blocks and gap alike).
	# ISSUE #268: -20% again, blocks and gap alike (8.64x14.4/2.7 -> 6.91x11.52/2.16).
	"dmg_bench_w":       6.912,
	"dmg_bench_h":       11.52,
	"dmg_bench_gap":     2.16,
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

# ─── Chevrons ────────────────────────────────────────────────────────────────
# Thin diagonal stripes crossing both chrome bars and the field, counter-
# scrolling. Shared by every theme — a theme changes their COLOUR
# (chrome_pattern, field_texture), never their geometry.
#
# They are a fine TEXTURE, not broad bands of light: 3px of ink every 17px on the
# bars, 18px every 74px on the field, hard-edged with a single pixel of
# antialiasing. Roughly 113 cross a bar and 26 cross the screen.
#
# IF THEY EVER READ AS TOO BUSY, LOWER THE ALPHA. Widening them and spacing them
# further apart was tried and reverted — it turns the texture into slow sweeping
# bands and loses the design.
#
# ── THE SPEEDS LOOK ODD, AND THEY ARE CORRECT ────────────────
# _TIME is how often a stripe passes a fixed point, which is the thing the eye
# actually reads. But the pattern is translated along +X while the stripes lie at
# 115 degrees, so a horizontal shift of d only advances the pattern by
# d * sin(115°) = d * 0.9063 across the stripes. The loop distances below are
# therefore the period DIVIDED by that factor — 17 / 0.9063 = 18.76, and
# 74 / 0.9063 = 81.65 — which is what makes a stripe arrive every 3.4s and 14s
# rather than every 3.75s and 15.4s.
#
# The pattern is generated by mod() against the period, so it is periodic by
# construction and there is no wrap seam at any offset.
const CHEVRON_ANGLE_DEG    := 115.0
const CHEVRON_BAR_STRIPE   := 3.0
const CHEVRON_BAR_PERIOD   := 17.0
const CHEVRON_BAR_LOOP     := 18.76   # 1 period, corrected for the 115 degree angle
const CHEVRON_BAR_TIME     := 3.4     # a stripe every 3.4s -> 5.52 px/s in x, scrolls RIGHT
const CHEVRON_FIELD_STRIPE := 18.0
const CHEVRON_FIELD_PERIOD := 74.0
const CHEVRON_FIELD_LOOP   := 81.65   # 1 period, corrected for the 115 degree angle
const CHEVRON_FIELD_TIME   := 14.0    # a stripe every 14s -> 5.83 px/s in x, scrolls LEFT

# ─── The chrome keyline ──────────────────────────────────────────────────────
# A 1px rule along the bar edge that faces the content. Its colour is the
# per-theme `chrome_line`; transparent means no rule, which is what the vivid
# gradient bars use. Five of the eight themes need it — on a flat near-black bar
# over a near-black field it is the only thing separating the two.
const CHROME_LINE_PX := 1.0

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


# ─── Derived colours ─────────────────────────────────────────────────────────
# These two are STATIC so Build_UI_Themes.gd can call them on the loaded script
# object. Autoloads do not exist in a `--script` run, but static functions on a
# loaded class do, and the baked button art has to agree with the runtime about
# these exactly or a selected button will not match a selected chip beside it.

## Relative luminance, the WCAG definition. Used to decide whether a fill wants
## light ink or dark ink on top of it.
static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## THE selection colour for a theme block — the one "this is on" fill.
##
## Normally chrome_grad_b, the header gradient's middle stop, so a selected
## button matches the bar above it. But that stop is only a good selection colour
## when the chrome bar is genuinely colourful. A theme whose header is near black
## or deliberately desaturated (dusk, circuit, and any incoming theme built the
## same way) would produce a selected state you cannot see, so those fall back to
## `accent`, which every theme guarantees is its lead colour.
##
## This is why a theme does not need a 39th token for selection. Do not add one
## without also updating Docs/THEME_TEMPLATE_SPEC.md, which promises 38.
static func selection_for(block: Dictionary) -> Color:
	var b: Color = block["chrome_grad_b"]
	return b if luminance(b) >= 0.22 else block["accent"]


## ISSUE #379: THE THREE ACTION COLOURS.
##
## Every button that answers a question is one of three things, and each has
## its own solid colour so none of them can be mistaken for a disabled one:
##   positive  Yes / OK / Save / Buy / Confirm  -> the theme's `good` green
##             (the baked "primary" variant IS this now, as is "good")
##   negative  No / Cancel / Close / Back       -> negative_fill(): `danger`
##             pulled NEGATIVE_SOFTEN of the way toward the field, so it reads
##             as "back out" and not as the destructive red ("danger" keeps that)
##   neutral   tools, steppers, view / load     -> neutral_fill(): the accent
## The translucent "secondary" face is kept ONLY for an unselected option in a
## picker row, where "quiet until chosen" is exactly the meaning wanted.
## Static so Build_UI_Themes.gd bakes from the same call. TWEAKABLE.
const NEGATIVE_SOFTEN := 0.3

static func positive_fill(block: Dictionary) -> Color:
	return block["good"]

static func negative_fill(block: Dictionary) -> Color:
	var d: Color = block["danger"]
	var field: Color = block["field"]
	# Toward a DARK field it mutes nicely; toward a PALE one it washes the red
	# out under its white label (3.8:1). On a light theme it is muted by
	# darkening instead, which keeps the label above 4.5:1.
	if luminance(field) >= 0.5:
		return d.lerp(Color.BLACK, NEGATIVE_SOFTEN * 0.5)
	return d.lerp(field, NEGATIVE_SOFTEN)

static func neutral_fill(block: Dictionary) -> Color:
	return block["accent"]


## The fill for a secondary button sitting ON A CHROME BAR.
##
## `btn_secondary` is the one translucent variant, so it has no colour of its
## own — it is whatever it sits on, lifted or shaded. The theme keys it to the
## FIELD, which is right in the content area and wrong on a bar.
##
## ── THE DIRECTION IS DECIDED BY THE LABEL, NOT BY THE BAR ────
## The obvious rule — lift a dark bar, shade a light one — is wrong, and got
## this backwards on the vivid themes. A hot pink bar measures as "dark" by
## luminance, so the obvious rule LIFTED it, and the white label on the lightened
## pink came out at 3:1. The bar being dark is not the question.
##
## Two things have to be true at once: the label must read on the button face,
## and the face must be distinguishable from the bar behind it. On a near-black
## bar a white lift satisfies both, because white text has enormous headroom
## there. Everywhere else, lifting eats the label, so the face is shaded instead
## — and shaded hard enough to matter, because a light shade on a saturated
## colour barely moves it.
##
## So: try the lift, keep it only if the label still clears AA, otherwise shade.
##
## Build_UI_Themes.gd bakes the face from this and Theme_Audit.gd measures it
## from this, so the art and the check can never drift apart.
static func chrome_button_tint(block: Dictionary) -> Color:
	var mid: Color = block["chrome_grad_b"]
	var fg: Color = block["chrome_fg"]
	var lift := Color(1.0, 1.0, 1.0, 0.18)
	if contrast_ratio(fg, composite(lift, mid)) >= 4.5:
		return lift
	return Color(0.0, 0.0, 0.0, 0.30)


## Alpha-composites `over` onto an opaque `under`.
static func composite(over: Color, under: Color) -> Color:
	return Color(
		over.r * over.a + under.r * (1.0 - over.a),
		over.g * over.a + under.g * (1.0 - over.a),
		over.b * over.a + under.b * (1.0 - over.a))


## WCAG contrast ratio between two OPAQUE colours. This linearises each channel,
## unlike luminance() above, which is the cheap gamma-space approximation used
## only for the light-ink/dark-ink decision. Contrast maths needs the real one.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _rel_luminance(a)
	var lb := _rel_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _rel_luminance(c: Color) -> float:
	return 0.2126 * _to_linear(c.r) + 0.7152 * _to_linear(c.g) + 0.0722 * _to_linear(c.b)


static func _to_linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


## The text colour that reads on `fill`. White on a dark fill; on a light one, a
## heavily darkened version of the fill's OWN hue rather than flat black, which
## keeps a green button's label looking like it belongs to the green button.
##
## Replaces the two hand-tuned constants that used to live in Build_UI_Themes.gd
## for good and warn. Those only worked because someone eyeballed them against
## Spectrum Night's specific mint and amber; an incoming theme picking a pale
## `danger` would have got unreadable white text with no warning.
static func ink_on(fill: Color) -> Color:
	if luminance(fill) < 0.5:
		return Color.WHITE
	var ink := Color(fill.r, fill.g, fill.b)
	ink.v = 0.13
	ink.s = minf(fill.s * 0.8, 0.65)
	return ink


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


## One of the BATTLE dictionary's three-stop gradients, as [Color, Color, Color].
## Call it with "band_win_grad", "vs_text_grad", "disc_loss_grad" and so on. An
## unknown key returns the intro stops rather than crashing a match transition.
## ── WHICH BATTLE COLOURS FOLLOW THE THEME, AND WHICH DO NOT ──
## The VS screen is BRANDING: it is the game's own lockup, so its band and its
## word follow the chrome gradient and change with the theme.
##
## Win and loss are SEMANTIC. Green means you won and red means you lost in every
## theme, for the same reason the five status conditions and the eleven energy
## types do not move — the player learns the colour, and a theme that made a loss
## green would be actively misleading. Those ramps stay fixed.
func battle_grad(key: String) -> Array:
	match key:
		# The chrome bar's own ramp, on the intro band.
		"band_intro_grad":
			return [col("chrome_grad_a"), col("chrome_grad_b"), col("chrome_grad_c")]
		# The word inside the badge. Deliberately LIGHTER than the band behind it
		# — the badge sits on the dark ground, not on the band, so it needs its
		# own contrast. Each stop is the band's stop lifted toward white.
		"vs_text_grad":
			return [col("chrome_grad_a").lightened(0.45),
				col("chrome_grad_b").lightened(0.40),
				col("chrome_grad_c").lightened(0.35)]
	if not BATTLE.has(key):
		push_warning("UITheme: no battle gradient '%s'" % key)
		return battle_grad("band_intro_grad")
	return BATTLE[key]


## A single colour out of the BATTLE dictionary — the side accents, the prize
## gold, the badge well.
func battle_col(key: String) -> Color:
	match key:
		# The two sides. These ARE `accent` and `accent_2`: the theme block already
		# documents those as "player side" and "opponent side", and every incoming
		# theme is required to make them differ in hue, which is what lets the
		# player tell their half of the board from the opponent's.
		"side_player":   return col("accent")
		"side_opponent": return col("accent_2")
		# The dark disc the badge ring is drawn around — the field, deepened.
		"badge_well":
			var well := col("field").darkened(0.45)
			well.a = 0.55
			return well
	if not BATTLE.has(key) or not (BATTLE[key] is Color):
		push_warning("UITheme: no battle colour '%s'" % key)
		return Color.MAGENTA
	return BATTLE[key]


## The band / ring stops for an outcome. `kind` is "intro", "win" or "loss" —
## the one word the intro, outro and best-of-three screens all pass around.
func outcome_grad(kind: String) -> Array:
	return battle_grad("band_%s_grad" % kind)


## The stops for the WORD inside the badge, for the same three kinds. Separate
## from outcome_grad() because the text sits on the dark ground, not the band,
## and needs the lighter ramp.
func outcome_text_grad(kind: String) -> Array:
	return battle_grad("%s_text_grad" % ("vs" if kind == "intro" else kind))


## Message-box chrome — "bg", "border", "shadow".
##
## DERIVED, not looked up. The box appears on every screen in the game, so
## leaving it on a fixed dark purple would have made it the one thing that did
## not follow a theme change. The MSGBOX constant is kept as the record of what
## Spectrum Night's values were; these derivations reproduce them to within a
## couple of points and follow every other theme automatically.
func msgbox_col(key: String) -> Color:
	match key:
		"bg":
			# The field, a shade deeper, so the box reads as a panel cut out of the
			# screen it sits on rather than as a separate object.
			var bg := col("field").darkened(0.08)
			bg.a = 0.94
			return bg
		"border":
			return col_a("line", 0.15)
		"shadow":
			# A cast shadow is an absence of light, not a colour. It stays black on
			# a light theme too — a "light shadow" is not a thing.
			return Color(0.0, 0.0, 0.0, 0.60)
	push_warning("UITheme: no msgbox colour '%s'" % key)
	return Color.MAGENTA


## Shop cash pill — "top", "bot", "fg".
func cash_pill_col(key: String) -> Color:
	return CASH_PILL.get(key, Color.MAGENTA)


## Boot splash chrome — see the SPLASH block for the key list.
##
## Mostly DERIVED. The mark's four stops and the rule are the chrome gradient
## read straight off the current theme, so the first screen the player sees is
## already in their chosen theme rather than permanently in Spectrum Night. The
## SPLASH constant stays as the record of the authored values; every derivation
## below reproduces its Spectrum Night colour exactly unless noted.
func splash_col(key: String) -> Color:
	match key:
		# The mark. Upper arm runs top-left to bottom-right, lower arm top-right
		# to bottom-left, so stop B is shared and lands in the middle of the
		# lockup. That is exactly the chrome bar's own three-stop ramp.
		# ISSUE #379: ...unless a stop would vanish into the field. The flat dark-chrome
		# themes (Gengar, Code, Umbreon, Sharpedo) have three near-black stops, which
		# drew the whole mark black on black - see _splash_stop().
		"mark_upper_a": return _splash_stop("chrome_grad_a")
		"mark_upper_b": return _splash_stop("chrome_grad_b")
		"mark_lower_a": return _splash_stop("chrome_grad_b")
		"mark_lower_b": return _splash_stop("chrome_grad_c")

		# The rule. One near colour at the TCG cap, then each segment fades out
		# through its own side's stop at 35%.
		# NOTE: `accent` is a shade off the authored FF6FBE. Imperceptible, and
		# worth it to have the rule follow the theme.
		"rule_near":  return col("accent")
		"rule_mid_l": return _with_alpha(_splash_stop("chrome_grad_b"), 0.35)
		"rule_mid_r": return _with_alpha(_splash_stop("chrome_grad_c"), 0.35)

		# The wordmark. TCG is a shade off the two big words so it sits behind
		# them rather than competing.
		"wordmark": return _splash_readable("chrome_fg", "field_fg")   # ISSUE #379: Canopy's chrome_fg is dark ink
		"tcg":      return col("field_fg")

		# Both buttons take the game's own faces. ISSUE #379: New Game is the
		# NEUTRAL face now (it was the translucent secondary and looked disabled);
		# Continue is the positive one - see continue_* below.
		"new_game_top": return neutral_fill(THEMES[current])
		"new_game_bot": return neutral_fill(THEMES[current])
		"new_game_fg":  return ink_on(neutral_fill(THEMES[current]))
		"continue_top": return positive_fill(THEMES[current])
		"continue_bot": return positive_fill(THEMES[current])
		"continue_fg":  return ink_on(positive_fill(THEMES[current]))
	# btn_hover, btn_press and fade are genuinely theme-independent: two neutral
	# state tints and a fade to black. They stay in the constant.
	return SPLASH.get(key, Color.MAGENTA)


## ISSUE #379: THE SPLASH MARK MUST READ AGAINST THE FIELD IT SITS ON.
##
## The mark is the chrome ramp, which on a vivid bar is perfect and on a flat
## near-black bar is three shades of black. Any stop that does not clear
## SPLASH_MIN_CONTRAST against the field is swapped for the theme's own accents
## - grad_a -> accent, grad_b -> halfway between, grad_c -> accent_2 - so the
## lockup keeps a three-colour ramp in that theme's colours. TWEAKABLE.
const SPLASH_MIN_CONTRAST := 2.0

func _splash_stop(stop_key: String) -> Color:
	var c: Color = col(stop_key)
	if contrast_ratio(c, col("field")) >= SPLASH_MIN_CONTRAST:
		return c
	var fallback: Color
	match stop_key:
		"chrome_grad_a": fallback = col("accent")
		"chrome_grad_c": fallback = col("accent_2")
		_:               fallback = col("accent").lerp(col("accent_2"), 0.5)
	print("ISSUE #379 FIX ACTIVE: splash ", stop_key, " too dark on the field - using ", fallback.to_html(false))
	return fallback


## `key` if it reads on the field, otherwise `fallback_key`.
func _splash_readable(key: String, fallback_key: String) -> Color:
	var c: Color = col(key)
	if contrast_ratio(c, col("field")) >= SPLASH_MIN_CONTRAST:
		return c
	return col(fallback_key)


static func _with_alpha(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)

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


## Whether the header and footer bars should be drawn.
##
## This hides the BAR'S OWN PAINT ONLY — the gradient and its light bands. Every
## title, chip and button inside a bar keeps drawing, in the same place, at the
## same size, in the same colour, so the contents appear to float over the field.
## The bar also keeps its height, so nothing on any screen moves.
func bars_hidden() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if not ("hide_bars_setting" in gs):
		return false
	return String(gs.get("hide_bars_setting")) == "yes"

# ─── Theme switching ─────────────────────────────────────────────────────────

## The player-facing name for a theme id. Falls back to title-casing the id, so
## a theme added to THEMES without a THEME_NAMES entry still reads properly on
## the Options screen instead of showing as "midnight_reef".
func theme_display_name(theme_id: String) -> String:
	if THEME_NAMES.has(theme_id):
		return String(THEME_NAMES[theme_id])
	var words: PackedStringArray = []
	for part in theme_id.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)


## Every theme id, in declaration order.
func theme_ids() -> Array:
	return THEMES.keys()


# ─── Look and mode ───────────────────────────────────────────────────────────
# Every theme id is `<look>_<mode>` — "umbreon_dark", "sunset_light". The Options
# picker offers those as TWO rows rather than one, because sixteen buttons each
# reading "Umbreon Dark" is a wall of long labels where eight short ones plus a
# Dark/Light pair says the same thing.
#
# Both halves are derived by walking THEMES. Adding a look, or a third mode, is
# still a data change with no edit to the picker.

## The look half of an id. "umbreon_dark" -> "umbreon".
func theme_look_of(theme_id: String) -> String:
	var cut := theme_id.rfind("_")
	return theme_id.substr(0, cut) if cut > 0 else theme_id


## The mode half of an id. "umbreon_dark" -> "dark".
func theme_mode_of(theme_id: String) -> String:
	var cut := theme_id.rfind("_")
	return theme_id.substr(cut + 1) if cut > 0 else ""


## Every look, once each, in declaration order.
func theme_looks() -> Array:
	var out: Array = []
	for theme_id in THEMES.keys():
		var look := theme_look_of(String(theme_id))
		if not (look in out):
			out.append(look)
	return out


## Every mode, once each, in the order they first appear.
func theme_modes() -> Array:
	var out: Array = []
	for theme_id in THEMES.keys():
		var mode := theme_mode_of(String(theme_id))
		if mode != "" and not (mode in out):
			out.append(mode)
	return out


## Puts a look and a mode back together. If that pairing does not exist — a look
## that ships in only one mode — the first id with the right look wins, so the
## picker can never land on a theme that is not there.
func compose_theme(look: String, mode: String) -> String:
	var wanted := "%s_%s" % [look, mode]
	if THEMES.has(wanted):
		return wanted
	for theme_id in THEMES.keys():
		if theme_look_of(String(theme_id)) == look:
			return String(theme_id)
	return DEFAULT_THEME


## Title-cased name for one half of an id, for the two picker rows.
func theme_part_name(part: String) -> String:
	return part.capitalize()


## Switch theme. Prefer GameState.set_ui_theme(), which also persists the choice
## — this is the raw setter and does not touch the save file.
func set_theme(theme_name: String) -> void:
	if not THEMES.has(theme_name):
		push_warning("UITheme: unknown theme '%s'" % theme_name)
		return
	if theme_name == current:
		return
	current = theme_name
	theme_changed.emit()
