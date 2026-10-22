extends SceneTree

# ============================================================
# THEME_AUDIT — validates every theme block against the contract
# ============================================================
# A check tool, not runtime code. Run it after adding or editing a theme:
#
#   "C:\Godot\Godot_v4.6.1-stable_win64_console.exe" --headless \
#       --path "C:\Pokemon TCG Legacy" --script Scripts/Utilities/Theme_Audit.gd
#
# Exit code 0 means every theme passed. Non-zero means at least one FAIL.
#
# It checks the things Docs/THEME_TEMPLATE_SPEC.md promises, which is exactly
# what an incoming theme has to satisfy:
#
#   1. Every key in the reference theme is present, and no extras.
#   2. Contrast, by the WCAG ratio, on the pairs the player actually reads.
#   3. The button rule: primary's stops appear elsewhere in the theme, and
#      secondary is a low-alpha tint with a non-white label.
#   4. silhouette_invert agrees with the field's own light/dark polarity.
#   5. The selection colour is usable, and which source it came from.
#   6. accent and accent_2 differ in HUE, not merely in lightness.
#
# ── WHY WARN AND FAIL ARE DIFFERENT ──────────────────────────
# FAIL is a broken theme: a missing key, unreadable text, an inverted
# silhouette. WARN is a judgement call the author may have made deliberately —
# a slightly low mute contrast, a selection colour that fell back to accent.
# Only FAIL sets the exit code, so this can run in a loop over incoming themes
# without a stylistic preference blocking the build.
# ============================================================

const UI_THEME_SCRIPT := "res://Scripts/Global_Scripts/UI_Theme.gd"

# Contrast floors. 4.5 is the WCAG AA threshold for body text; 3.0 is the
# large-text and non-text threshold, which is what de-emphasised labels and
# outlines are held to.
const AA_TEXT  := 4.5
const AA_LARGE := 3.0

var _fails := 0
var _warns := 0


func _init() -> void:
	var ui = load(UI_THEME_SCRIPT)
	if ui == null:
		printerr("Theme_Audit: cannot load ", UI_THEME_SCRIPT)
		quit(1)
		return

	var reference: String = ui.DEFAULT_THEME
	var required: Array = ui.THEMES[reference].keys()

	print("Theme audit — %d themes, %d keys each, reference '%s'"
		% [ui.THEMES.size(), required.size(), reference])

	for theme_id in ui.THEMES.keys():
		_audit(ui, String(theme_id), required)

	print("")
	if _fails == 0:
		print("PASS — %d themes, 0 failures, %d warnings" % [ui.THEMES.size(), _warns])
	else:
		printerr("FAIL — %d failures, %d warnings" % [_fails, _warns])
	quit(0 if _fails == 0 else 1)


func _audit(ui, theme_id: String, required: Array) -> void:
	var t: Dictionary = ui.THEMES[theme_id]
	print("\n── %s  (%s)" % [theme_id, ui.new().theme_display_name(theme_id)])

	# 1. Shape.
	var missing: Array = []
	for key in required:
		if not t.has(key):
			missing.append(key)
	var extra: Array = []
	for key in t.keys():
		if not (key in required):
			extra.append(key)
	if missing.is_empty() and extra.is_empty():
		_ok("keys", "all %d present" % required.size())
	else:
		if not missing.is_empty():
			_fail("keys", "MISSING: " + ", ".join(missing))
		if not extra.is_empty():
			_fail("keys", "UNKNOWN: " + ", ".join(extra))
		return   # every later check would just cascade

	# 2. Contrast. Alpha tints are composited over what sits behind them first,
	#    because a ratio against a 10%-white fill is meaningless on its own.
	var field: Color = t["field"]
	# Chrome text is held to the LARGE-text floor, not the body floor. What sits
	# bare on a chrome bar is the 29px bold screen title and the occasional 19px
	# bold name, both of which are "large" by the WCAG definition; every small
	# thing on a bar is a chip with its own background or a button with its own
	# baked face, and those are measured separately below.
	# Measured on the stops the bar is actually PAINTED with (UITheme.BAR_STOPS).
	var bar: Array = ui.bar_stops(theme_id)
	_contrast("chrome_fg on bar_a", t["chrome_fg"], bar[0], AA_LARGE)
	_contrast("chrome_fg on bar_b", t["chrome_fg"], bar[1], AA_LARGE)
	_contrast("chrome_fg on bar_c", t["chrome_fg"], bar[2], AA_LARGE)
	_contrast("field_fg on field", t["field_fg"], field, AA_TEXT)
	_contrast("field_mute on field", t["field_mute"], field, AA_LARGE)
	_contrast("chip_fg on chip_bg", t["chip_fg"], _over(t["chip_bg"], field), AA_TEXT)
	_contrast("btn_primary_fg on primary",
		t["btn_primary_fg"], t["btn_primary_top"].lerp(t["btn_primary_bot"], 0.5), AA_TEXT)
	_contrast("btn_secondary_fg on secondary",
		t["btn_secondary_fg"], _over(t["btn_secondary"], field), AA_TEXT)

	# The secondary button that sits on a chrome bar takes a separate baked face
	# keyed to the BAR's polarity, not the field's — see UIKit.on_chrome(). It is
	# measured against the bar's middle stop, which is where a footer button sits.
	# Without this check, a theme pairing a pale field with a near-black bar
	# scored a perfect secondary and still drew Cancel black on black.
	var mid: Color = bar[1]
	_contrast("chrome_fg on secondary_chrome",
		t["chrome_fg"], _over(ui.chrome_button_tint(theme_id), mid), AA_TEXT)

	# 3. The button rule.
	# A stop passes either by being an exact theme colour, or by sharing the
	# accent's hue — that second path is the documented exception for a theme
	# whose chrome bar is too unsaturated to lend a stop, where the rule says to
	# derive primary from `accent` instead. A darkened accent is not an equal
	# colour but it is unmistakably the theme's own.
	var elsewhere := _palette(t)
	for stop in [["btn_primary_top", t["btn_primary_top"]], ["btn_primary_bot", t["btn_primary_bot"]]]:
		var c: Color = stop[1]
		if _matches_any(c, elsewhere):
			_ok("button rule", "%s is a theme colour" % stop[0])
		elif _hue_gap(c, t["accent"]) < 0.045 and c.s > 0.15:
			_ok("button rule", "%s is derived from accent" % stop[0])
		else:
			_warn("button rule", "%s (%s) is neither a theme colour nor an accent shade"
				% [stop[0], c.to_html(false)])
	var sec: Color = t["btn_secondary"]
	if sec.a > 0.20:
		_warn("button rule", "btn_secondary alpha %.2f is high; the rule is a ~0.10 tint" % sec.a)
	else:
		_ok("button rule", "btn_secondary is a %.2f tint" % sec.a)
	if _is_pure_white(t["btn_secondary_fg"]):
		_fail("button rule", "btn_secondary_fg is pure white — it must read as the lesser choice")
	else:
		_ok("button rule", "btn_secondary_fg is not pure white")

	# 4. Silhouette polarity.
	var light_field: bool = ui.luminance(field) >= 0.5
	if bool(t["silhouette_invert"]) == light_field:
		_ok("silhouette", "invert=%s matches a %s field" % [t["silhouette_invert"],
			"light" if light_field else "dark"])
	else:
		_fail("silhouette", "invert=%s on a %s field — locked cards will be invisible"
			% [t["silhouette_invert"], "light" if light_field else "dark"])

	# 5. Selection colour, and which source won.
	var sel: Color = ui.selection_for(t)
	var from_chrome: bool = sel.is_equal_approx(t["chrome_grad_b"])
	var ink: Color = ui.ink_on(sel)
	_contrast("selection label on selection", ink, sel, AA_TEXT)
	if from_chrome:
		_ok("selection", "chrome_grad_b (%s)" % sel.to_html(false))
	else:
		_warn("selection", "chrome_grad_b is too dark; fell back to accent (%s)" % sel.to_html(false))

	# 6. Accents must differ in hue. Two accents that differ only in lightness
	#    cannot tell the player's side of the board from the opponent's.
	var dh: float = _hue_gap(t["accent"], t["accent_2"])
	if dh >= 0.055:
		_ok("accents", "accent and accent_2 are %.0f degrees apart" % (dh * 360.0))
	else:
		_warn("accents", "accent and accent_2 are only %.0f degrees apart" % (dh * 360.0))


# ─── Checks ──────────────────────────────────────────────────────────────────

func _contrast(what: String, fg: Color, bg: Color, floor_ratio: float) -> void:
	var ratio := _ratio(_over(fg, bg), bg)
	if ratio >= floor_ratio:
		_ok("contrast", "%s = %.1f:1" % [what, ratio])
	elif ratio >= floor_ratio - 1.0:
		_warn("contrast", "%s = %.1f:1 (wants %.1f)" % [what, ratio, floor_ratio])
	else:
		_fail("contrast", "%s = %.1f:1 (wants %.1f)" % [what, ratio, floor_ratio])


## WCAG contrast ratio. Both colours must already be opaque — composite first.
func _ratio(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	var hi: float = maxf(la, lb)
	var lo: float = minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


## WCAG relative luminance, which linearises each channel first. This is NOT the
## same as UITheme.luminance(), which is the cheap gamma-space approximation used
## for the light-ink/dark-ink decision. Contrast maths needs the real one.
func _relative_luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


## The cheap gamma-space luminance UITheme uses for its light-ink/dark-ink and
## chrome-polarity decisions. Mirrored here so the audit asks the same question
## the builder did, rather than a slightly different one.
func ui_luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


## Alpha-composites `over` onto an opaque `under`.
func _over(over: Color, under: Color) -> Color:
	return Color(
		over.r * over.a + under.r * (1.0 - over.a),
		over.g * over.a + under.g * (1.0 - over.a),
		over.b * over.a + under.b * (1.0 - over.a))


## Every opaque colour in the theme except the two primary stops themselves —
## what "appears elsewhere" is measured against.
func _palette(t: Dictionary) -> Array:
	var out: Array = []
	for key in t.keys():
		if key.begins_with("btn_primary") or not (t[key] is Color):
			continue
		var c: Color = t[key]
		if c.a >= 0.99:
			out.append(c)
	return out


func _matches_any(c: Color, others: Array) -> bool:
	for other in others:
		if absf(c.r - other.r) < 0.02 and absf(c.g - other.g) < 0.02 and absf(c.b - other.b) < 0.02:
			return true
	return false


func _is_pure_white(c: Color) -> bool:
	return c.r > 0.99 and c.g > 0.99 and c.b > 0.99


## Shortest distance between two hues on the colour wheel, 0.0-0.5.
func _hue_gap(a: Color, b: Color) -> float:
	var d: float = absf(a.h - b.h)
	return minf(d, 1.0 - d)


# ─── Reporting ───────────────────────────────────────────────────────────────

func _ok(group: String, message: String) -> void:
	print("   ok    %-12s %s" % [group, message])


func _warn(group: String, message: String) -> void:
	_warns += 1
	print("   WARN  %-12s %s" % [group, message])


func _fail(group: String, message: String) -> void:
	_fails += 1
	print("   FAIL  %-12s %s" % [group, message])
