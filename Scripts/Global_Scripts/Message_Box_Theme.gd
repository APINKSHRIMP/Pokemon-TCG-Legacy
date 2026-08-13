class_name MessageBoxTheme

# ============================================================
# MESSAGE BOX THEME — static colour data
# ============================================================
# A theme is ONE base colour plus a hue step. Every other colour the message
# box needs is derived from those two numbers:
#
#   chip 0  = the base colour exactly (also the main panel's edge glow)
#   chip 1  = one step lighter / less saturated / hue-nudged
#   chip 2  = two steps, and so on
#
# That is what makes the chip row scalable: adding a fourth chip (best-of-3,
# special conditions, whatever comes next) needs no new colour data at all —
# chip_color() just keeps walking the ramp.
#
# The ramp was fitted to the blue reference design, where the three chips are
# #7598FB -> #8FD4FF -> #B3FBFF. Feeding the blue base + a -21 degree hue step
# into chip_color() reproduces those three to within a couple of RGB units.
#
# ── TWEAKABLE ────────────────────────────────────────────────
#   SAT_DECAY      lower = chips wash out faster along the row
#   VAL_APPROACH   lower = chips brighten toward white faster
#   hue_step       per theme; sign picks which way the hue drifts
# ============================================================

# Each step multiplies saturation by this.
const SAT_DECAY := 0.78

# Each step closes this fraction of the remaining gap to full brightness.
const VAL_APPROACH := 0.55

# Theme key -> base colour + hue drift per chip, in degrees.
# The key is what gets written into Player_Current_Data.json.
#
# The greys (white / grey / black) all sit on hue 240 with a sliver of
# saturation left in, so they read as neutral but still tint the same way every
# other theme does. "white" is a light grey rather than pure white — the panel's
# fill is already white, so a true-white base would leave no visible edge glow.
const THEMES := {
	"dark_blue":  { "base": "#5b80ee", "hue_step": -21.0 },
	"light_blue": { "base": "#6fc0f7", "hue_step": -18.0 },
	"aqua":       { "base": "#5fd5d8", "hue_step": -14.0 },
	"lime":       { "base": "#b6f13c", "hue_step": -10.0 },
	"green":      { "base": "#7fd873", "hue_step": -16.0 },
	"dark_green": { "base": "#41a76d", "hue_step": -18.0 },
	"light_pink": { "base": "#fba7d4", "hue_step":  12.0 },
	"dark_pink":  { "base": "#e05fa4", "hue_step":  12.0 },
	"light_red":  { "base": "#fb9b91", "hue_step":  11.0 },
	"dark_red":   { "base": "#e05348", "hue_step":  11.0 },
	"orange":     { "base": "#fba55a", "hue_step":   9.0 },
	"yellow":     { "base": "#f9de54", "hue_step":   5.0 },
	"purple":     { "base": "#8b63ec", "hue_step": -14.0 },
	"lilac":      { "base": "#c4a5f5", "hue_step": -12.0 },
	"white":      { "base": "#d2d2dc", "hue_step":  -8.0 },
	"grey":       { "base": "#666672", "hue_step":  -8.0 },
	"black":      { "base": "#2e2e36", "hue_step":  -8.0 },
}

# Display order for the Options screen. Keep in sync with THEMES.
const THEME_ORDER := [
	"dark_blue", "light_blue", "aqua", "lime", "green", "dark_green",
	"light_pink", "dark_pink", "light_red", "dark_red", "orange", "yellow",
	"purple", "lilac", "white", "grey", "black",
]

const DEFAULT_THEME := "dark_blue"

# Human-readable labels for the Options buttons.
const THEME_LABELS := {
	"dark_blue":  "dark blue",
	"light_blue": "light blue",
	"aqua":       "aqua",
	"lime":       "lime",
	"green":      "green",
	"dark_green": "dark green",
	"light_pink": "light pink",
	"dark_pink":  "dark pink",
	"light_red":  "light red",
	"dark_red":   "dark red",
	"orange":     "orange",
	"yellow":     "yellow",
	"purple":     "purple",
	"lilac":      "lilac",
	"white":      "white",
	"grey":       "grey",
	"black":      "black",
}


static func has_theme(key: String) -> bool:
	return THEMES.has(key)


static func base_color(theme_key: String) -> Color:
	var entry: Dictionary = THEMES.get(theme_key, THEMES[DEFAULT_THEME])
	return Color(entry["base"])


static func hue_step(theme_key: String) -> float:
	var entry: Dictionary = THEMES.get(theme_key, THEMES[DEFAULT_THEME])
	return float(entry["hue_step"])


# The colour for the chip at `index` (0 = leftmost / name chip).
# index 0 returns the base colour untouched — every power term is 1.0 there.
static func chip_color(theme_key: String, index: int) -> Color:
	var base := base_color(theme_key)
	var step := hue_step(theme_key)

	var h := fposmod(base.h * 360.0 + step * float(index), 360.0) / 360.0
	var s: float = base.s * pow(SAT_DECAY, float(index))
	var v: float = base.v + (1.0 - base.v) * (1.0 - pow(VAL_APPROACH, float(index)))

	return Color.from_hsv(h, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0), 1.0)


# The main panel's border glow — always the base colour, so the panel and the
# leftmost chip read as one piece.
static func panel_edge_color(theme_key: String) -> Color:
	return chip_color(theme_key, 0)
