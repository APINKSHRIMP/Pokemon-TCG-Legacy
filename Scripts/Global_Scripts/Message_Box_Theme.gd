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
const THEMES := {
	"blue":       { "base": "#7598fb", "hue_step": -21.0 },
	"light_blue": { "base": "#6fc0f7", "hue_step": -18.0 },
	"aqua":       { "base": "#5fd5d8", "hue_step": -14.0 },
	"green":      { "base": "#7fd873", "hue_step": -16.0 },
	"dark_green": { "base": "#41a76d", "hue_step": -18.0 },
	"pink":       { "base": "#f887c2", "hue_step":  12.0 },
	"red":        { "base": "#f87a6e", "hue_step":  11.0 },
	"orange":     { "base": "#fba55a", "hue_step":   9.0 },
	"purple":     { "base": "#a98bf5", "hue_step": -14.0 },
	"black":      { "base": "#4c4c57", "hue_step":  -8.0 },
}

# Display order for the Options screen. Keep in sync with THEMES.
const THEME_ORDER := [
	"blue", "light_blue", "aqua", "green", "dark_green",
	"pink", "red", "orange", "purple", "black",
]

const DEFAULT_THEME := "blue"

# Human-readable labels for the Options buttons.
const THEME_LABELS := {
	"blue":       "blue",
	"light_blue": "light blue",
	"aqua":       "aqua",
	"green":      "green",
	"dark_green": "dark green",
	"pink":       "pink",
	"red":        "red",
	"orange":     "orange",
	"purple":     "purple",
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
