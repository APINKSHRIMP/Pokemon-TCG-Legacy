extends SceneTree

# ============================================================
# BUILD_UI_THEMES — regenerates UI_Themes/ui/ from the UITheme tokens
# ============================================================
# A build tool, not runtime code. Run it after changing any colour, radius or
# type size in UI_Theme.gd:
#
#   "C:\Godot\Godot_v4.6.1-stable_win64_console.exe" --headless \
#       --path "C:\Pokemon TCG Legacy" --script Scripts/Utilities/Build_UI_Themes.gd
#
# It writes:
#   UI_Themes/ui/btn_*.png          — 9-patch button faces, 3 per variant
#   UI_Themes/ui/slider_grabber.png — the volume slider's grabber disc
#   UI_Themes/ui/ui_base.tres       — default font and colours for every Control
#   UI_Themes/ui/ui_<variant>.tres  — one per button semantic
#
# ── WHY THEMES PER VARIANT ───────────────────────────────────
# The project already assigns a whole Theme to a Button to colour it (the five
# kenneyUI*.tres). Keeping that shape means the ~130 existing references are a
# mechanical path swap rather than a rewrite of every screen. The mapping is:
#
#   kenneyUI.tres         (white, "this option is selected")  -> ui_selected
#   kenneyUI-blue.tres    (the other, pickable options)       -> ui_secondary
#   kenneyUI-green.tres   (save button with a pending change) -> ui_good
#   kenneyUI-red.tres     (destructive / cancel)              -> ui_danger
#   kenneyUI-yellow.tres  (a toggle that is currently on)     -> ui_warn
#   (new)                 the screen's one confirm action     -> ui_primary
#
# ── WHY EVERY VARIANT IS BAKED ART ───────────────────────────
# The first build used StyleBoxFlat for the five flat variants and baked art
# only for primary's gradient. StyleBoxFlat's rounded corners came out FACETED
# — visible straight segments and hard stair-steps on the top corners — while
# the baked primary next to it was perfectly smooth. Two causes, both fatal:
# corner_detail defaults to 8 segments across a 90 degree turn, and the project
# sets `2d/snap/snap_2d_vertices_to_pixel = true`, which snaps every one of
# those corner vertices onto a whole pixel and throws the antialiasing away.
#
# That snap setting exists for the pixel-art overworld and must not be touched,
# so the buttons stop being polygons instead. A baked face is a quad: nothing
# to snap, and the antialiasing is in the texture where nothing can round it
# off. Nineteen 64x64 PNGs, about 600 bytes each.
#
# ── A THEME THAT LACKS AN ITEM FALLS THROUGH ─────────────────
# Godot resolves a theme item by walking UP the tree from the node. A variant
# theme therefore only needs to state what makes it different; anything it
# omits is answered by ui_base on the screen root. That is why the variants
# carry Button entries and nothing else.
# ============================================================

const OUT_DIR := "res://UI_Themes/ui/"

# Button face texture. The patch margin has to clear the corner radius (and the
# 5px bottom edge), and the two margins together must not exceed the shortest
# button the game draws — a 9-patch whose top+bottom slices are taller than the
# control squashes its own corners. Buttons are ~48px tall (btn_pad_v 13 x 2
# plus a 17px line), so a 24px margin is the ceiling and it is derived from
# btn_radius rather than hand-set. ISSUE #184.
var TEX_MARGIN: int = 24
var TEX_SIZE: int = 56

# Filled from METRICS / the token block in _init(). Vars, not consts, precisely
# so they cannot be edited here and drift from UI_Theme.gd.
var RADIUS: float = 11.0
var EDGE_H: float = 5.0
var BTN_EDGE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.30)
var PAD_H: float = 29.0
var PAD_V: float = 13.0
var FONT_UI_BOLD: String = ""
var FONT_UI_MEDIUM: String = ""
var FONT_MONO: String = ""
var SIZE_BUTTON: int = 17
var SIZE_BODY: int = 22

# ── TOKENS COME FROM UI_Theme.gd, NOT FROM COPIES HERE ───────
# Autoloads do not exist in a `--script` run, so `UITheme` is not reachable.
# GDScript class CONSTANTS are though: loading the script gives an object whose
# `.THEMES` / `.METRICS` / `.TYPE` can be read directly, no instance needed.
#
# The first build hand-copied the palette into this file and it had already
# drifted within a day. Never reintroduce a colour literal here that exists as
# a token — change UI_Theme.gd and re-run.
const UI_THEME_SCRIPT := "res://Scripts/Global_Scripts/UI_Theme.gd"

var TOK: Dictionary   # the shipped theme's colour block
var MET: Dictionary   # METRICS
var TYP: Dictionary   # TYPE

# Every button variant. `top`/`bot` equal means a flat fill; only primary uses
# a gradient. Built in _init() once the tokens are loaded.
var VARIANTS: Dictionary = {}

# Text colours for the three light fills. These are contrast picks against a
# specific button colour, NOT palette entries — good, warn and selected are all
# light enough that white text on them is unreadable, and nothing else in the
# game wants "the colour that reads on mint green".
const FG_ON_GOOD := Color("0E2418")
const FG_ON_WARN := Color("2A2010")

# Hover and press are composited OVER the fill rather than applied to its rgb.
# The secondary button is white at 8% alpha, so "lighten the rgb by 6%" did
# nothing at all to it — white is already white. Laying a translucent white or
# black over the fill moves both rgb AND alpha, so one rule works for an opaque
# pink and a barely-there white alike.
const HOVER_LIFT := Color(1.0, 1.0, 1.0, 0.10)
const PRESS_SINK := Color(0.0, 0.0, 0.0, 0.18)

# Disabled is one shared face, not one per variant — a disabled button carries
# no semantic colour, it is simply unavailable.
const DISABLED_FILL := Color(0.0, 0.0, 0.0, 0.22)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var ui_theme = load(UI_THEME_SCRIPT)
	if ui_theme == null:
		printerr("Build_UI_Themes: cannot load ", UI_THEME_SCRIPT)
		quit(1)
		return
	TOK = ui_theme.THEMES[ui_theme.DEFAULT_THEME]
	MET = ui_theme.METRICS
	TYP = ui_theme.TYPE

	# ISSUE #184: buttons take btn_radius (the pill), not the chip radius.
	RADIUS         = float(MET["btn_radius"])
	TEX_MARGIN     = int(ceil(RADIUS)) + 2
	TEX_SIZE       = TEX_MARGIN * 2 + 8
	EDGE_H         = float(MET["btn_edge_h"])
	PAD_H          = float(MET["btn_pad_h"])
	PAD_V          = float(MET["btn_pad_v"])
	BTN_EDGE_COLOR = TOK["btn_edge"]
	FONT_UI_BOLD   = ui_theme.FONT_UI_BOLD
	FONT_UI_MEDIUM = ui_theme.FONT_UI_MEDIUM
	FONT_MONO      = ui_theme.FONT_MONO
	SIZE_BUTTON    = int(round(float(TYP["button"]["size"])))
	SIZE_BODY      = int(round(float(TYP["body"]["size"])))

	VARIANTS = {
		"primary": {
			"top": TOK["btn_primary_top"], "bot": TOK["btn_primary_bot"],
			"fg": TOK["btn_primary_fg"],
		},
		"secondary": {
			"top": TOK["btn_secondary"], "bot": TOK["btn_secondary"],
			"fg": TOK["btn_secondary_fg"],
		},
		"selected": {
			# The header gradient's pink rather than the lighter `accent`, which
			# is too pale to carry white text at 17px.
			"top": TOK["chrome_grad_b"], "bot": TOK["chrome_grad_b"],
			"fg": Color.WHITE,
		},
		"good":   { "top": TOK["good"],   "bot": TOK["good"],   "fg": FG_ON_GOOD },
		"danger": { "top": TOK["danger"], "bot": TOK["danger"], "fg": Color.WHITE },
		"warn":   { "top": TOK["warn"],   "bot": TOK["warn"],   "fg": FG_ON_WARN },
	}

	var ok := true
	ok = _write_button_textures() and ok
	ok = _write_grabber_texture() and ok
	ok = _write_base_theme() and ok
	for variant_name in VARIANTS.keys():
		ok = _write_variant_theme(String(variant_name)) and ok

	if ok:
		print("Build_UI_Themes: wrote ", OUT_DIR)
	else:
		printerr("Build_UI_Themes: FINISHED WITH ERRORS")
	quit(0 if ok else 1)


# ─── Button face art ─────────────────────────────────────────────────────────

## Bakes normal / hover / pressed for every variant, plus the one shared
## disabled face.
##
## EVERY STATE KEEPS THE BOTTOM EDGE except disabled. The first build dropped it
## on press, which made the button appear to GROW downward into its own shadow
## the instant it was clicked — read as lag, not as a press. Nothing about the
## geometry changes between states now; only the fill colour does.
func _write_button_textures() -> bool:
	var ok := true
	for variant_name in VARIANTS.keys():
		var v: Dictionary = VARIANTS[variant_name]
		var top: Color = v["top"]
		var bot: Color = v["bot"]
		ok = _save_face("btn_%s.png" % variant_name, top, bot, true) and ok
		ok = _save_face("btn_%s_hover.png" % variant_name,
			_over(HOVER_LIFT, top), _over(HOVER_LIFT, bot), true) and ok
		ok = _save_face("btn_%s_pressed.png" % variant_name,
			_over(PRESS_SINK, top), _over(PRESS_SINK, bot), true) and ok
	ok = _save_face("btn_disabled.png", DISABLED_FILL, DISABLED_FILL, false) and ok
	return ok


## Alpha-composites `over` on top of `under` and returns the result. Used for
## hover, press and the bottom edge, so all three behave correctly on a
## translucent fill as well as an opaque one.
func _over(over: Color, under: Color) -> Color:
	var a := over.a + under.a * (1.0 - over.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var r := (over.r * over.a + under.r * under.a * (1.0 - over.a)) / a
	var g := (over.g * over.a + under.g * under.a * (1.0 - over.a)) / a
	var b := (over.b * over.a + under.b * under.a * (1.0 - over.a)) / a
	return Color(r, g, b, a)


## The slider grabber. An accent disc with a dark rim so it stays visible both
## against the filled half of the track and against the empty half.
##
## Godot has no procedural grabber — Slider takes a texture or falls back to the
## editor default, which is grey and would be the one un-themed thing on the
## Options screen.
func _write_grabber_texture() -> bool:
	var d := 26
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	var r := float(d) * 0.5 - 1.0

	for y in d:
		for x in d:
			var dist := (Vector2(x + 0.5, y + 0.5) - c).length()
			# One pixel of falloff at the rim, so the disc is not stair-stepped.
			var a: float = clampf(r - dist + 0.5, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# The outer 2.5px darken into a rim.
			var rim: float = clampf((dist - (r - 2.5)) / 2.5, 0.0, 1.0)
			var col: Color = TOK["accent"].lerp(Color("2A1633"), rim * 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))

	var path := OUT_DIR + "slider_grabber.png"
	var err := img.save_png(path)
	if err != OK:
		printerr("Build_UI_Themes: could not write ", path, " (", err, ")")
		return false
	return true


## One rounded-rect face with a vertical gradient and, optionally, the inset
## bottom edge. Antialiased against a rounded-rect SDF so the corners are clean
## at any scale the 9-patch is drawn at.
func _save_face(file_name: String, top: Color, bot: Color, with_edge: bool) -> bool:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := Vector2(TEX_SIZE, TEX_SIZE) * 0.5
	var box := half - Vector2(RADIUS, RADIUS)

	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var sd := _rounded_rect_sd(p - half, box, RADIUS)
			# 1 inside, 0 outside, one pixel of falloff across the border.
			var inside: float = clampf(0.5 - sd, 0.0, 1.0)
			if inside <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var t := float(y) / float(TEX_SIZE - 1)
			var col: Color = top.lerp(bot, t)

			# The edge occupies the last EDGE_H rows INSIDE the shape, so it
			# follows the bottom corners instead of cutting straight across.
			# Composited rather than lerped toward black, so it stays a solid
			# dark band on a translucent fill instead of fading out with it.
			# A flat band at full strength, not a ramp. Ramping it across the
			# whole 5px made the button read as a bevel, which is exactly the
			# Kenney look this replaces; only the top pixel is feathered, to
			# keep the boundary from crawling.
			if with_edge:
				var from_bottom := float(TEX_SIZE) - p.y
				if from_bottom <= EDGE_H and sd < 0.0:
					var k: float = clampf(EDGE_H - from_bottom, 0.0, 1.0)
					var edge := Color(BTN_EDGE_COLOR.r, BTN_EDGE_COLOR.g, BTN_EDGE_COLOR.b,
						BTN_EDGE_COLOR.a * k)
					col = _over(edge, col)

			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * inside))

	var path := OUT_DIR + file_name
	var err := img.save_png(path)
	if err != OK:
		printerr("Build_UI_Themes: could not write ", path, " (", err, ")")
		return false
	return true


## Signed distance to a rounded rect centred on the origin. Matches the GLSL
## rr() in UI_Selection_Ring.gdshader so baked art and shader art agree.
func _rounded_rect_sd(p: Vector2, b: Vector2, r: float) -> float:
	var d := Vector2(absf(p.x), absf(p.y)) - b
	var outside := Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	return outside + minf(maxf(d.x, d.y), 0.0) - r



# ─── Theme resources ─────────────────────────────────────────────────────────

## The screen-root theme: fonts, sizes and the neutral colours every Control
## inherits. Assign this to a screen's root Control and every Label, LineEdit
## and Button below it picks up the new face without a per-node override.
func _write_base_theme() -> bool:
	var t := Theme.new()

	var ui_medium: Font = load(FONT_UI_MEDIUM)
	var ui_bold: Font = load(FONT_UI_BOLD)
	var mono: Font = load(FONT_MONO)
	if ui_medium == null or ui_bold == null or mono == null:
		printerr("Build_UI_Themes: fonts not imported yet — open the project in the editor once, then re-run")
		return false

	t.default_font = ui_medium
	t.default_font_size = SIZE_BODY

	t.set_font("font", "Label", ui_medium)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_color("font_color", "Label", TOK["field_fg"])

	t.set_font("font", "RichTextLabel", ui_medium)
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_color("default_color", "RichTextLabel", TOK["field_fg"])

	t.set_font("font", "Button", ui_bold)
	t.set_font_size("font_size", "Button", SIZE_BUTTON)

	t.set_font("font", "LineEdit", ui_medium)
	t.set_font_size("font_size", "LineEdit", SIZE_BODY)
	t.set_color("font_color", "LineEdit", TOK["field_fg"])
	t.set_color("font_placeholder_color", "LineEdit", TOK["field_mute"])
	t.set_color("caret_color", "LineEdit", TOK["accent"])
	# ISSUE #180: a LineEdit with no content margins puts the caret and the first
	# glyph hard against the border. _text_box() insets both, and the inset has to
	# clear the corner radius or the text tucks into the curve.
	t.set_stylebox("normal", "LineEdit", _text_box(TOK["chip_bg"], TOK["line"]))
	t.set_stylebox("focus", "LineEdit", _text_box(TOK["chip_bg"], TOK["accent"]))

	t.set_stylebox("panel", "PanelContainer", _flat(TOK["panel"], TOK["line"], 1, 15.0))

	# Sliders. The track is the same 12px/6px-radius bar make_meter() draws, so a
	# volume slider and a progress meter read as the same object at rest.
	var track := _flat(TOK["slot"], Color(0, 0, 0, 0), 0, 6.0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _flat(TOK["accent"], Color(0, 0, 0, 0), 0, 6.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(TOK["accent"], Color(0, 0, 0, 0), 0, 6.0))
	var grabber: Texture2D = load(OUT_DIR + "slider_grabber.png")
	if grabber != null:
		t.set_icon("grabber", "HSlider", grabber)
		t.set_icon("grabber_highlight", "HSlider", grabber)
		t.set_icon("grabber_disabled", "HSlider", grabber)

	# The default Button look is the secondary one — a screen that assigns no
	# variant gets the quiet button, never an accidental primary.
	_apply_button(t, "secondary")

	return _save(t, OUT_DIR + "ui_base.tres")


## A variant theme states only what differs from ui_base: the four Button
## styleboxes and the font colour. Everything else falls through.
func _write_variant_theme(variant_name: String) -> bool:
	var t := Theme.new()
	_apply_button(t, variant_name)
	return _save(t, OUT_DIR + "ui_%s.tres" % variant_name)


func _apply_button(t: Theme, variant_name: String) -> void:
	var v: Dictionary = VARIANTS[variant_name]
	var fg: Color = v["fg"]

	t.set_stylebox("normal", "Button", _tex_box("btn_%s.png" % variant_name))
	t.set_stylebox("hover", "Button", _tex_box("btn_%s_hover.png" % variant_name))
	t.set_stylebox("pressed", "Button", _tex_box("btn_%s_pressed.png" % variant_name))

	# Disabled: no bottom edge, because the button has nothing to press into.
	#
	# DELIBERATE DEVIATION from "secondary at 40% opacity", which works out at
	# white 3.2% — invisible on a chrome bar. Save and Cancel live on the FOOTER,
	# so a disabled Save was a hole in the gradient with floating text over it.
	# A dark translucent fill recedes against both the dark field and the bright
	# bar, which is what disabled has to do.
	t.set_stylebox("disabled", "Button", _tex_box("btn_disabled.png"))

	# EMPTY, not a visible box. Godot draws the focus stylebox ON TOP of
	# normal/hover/pressed rather than instead of them, so pointing focus at the
	# hover face left every clicked button looking permanently hovered — which
	# reads as the button being stuck rather than as keyboard focus.
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_color("font_color", "Button", fg)
	t.set_color("font_hover_color", "Button", fg)
	t.set_color("font_pressed_color", "Button", fg)
	t.set_color("font_focus_color", "Button", fg)
	t.set_color("font_disabled_color", "Button", Color(fg.r, fg.g, fg.b, 0.40))



## A LineEdit face. Same fill as _flat() plus the text inset — ISSUE #180.
## TEXT_PAD_H is measured from the radius so the first glyph always clears the
## rounded corner however pill-like the boxes get.
func _text_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := _flat(fill, border, 1, RADIUS)
	var pad_h: float = maxf(14.0, RADIUS * 0.62)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _flat(fill: Color, border: Color, border_px: int, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if border_px > 0:
		sb.set_border_width_all(border_px)
		sb.border_color = border
	return sb


## Wraps a baked face in a 9-patch box with the same content margins as the
## flat variants, so swapping a button between primary and secondary never
## shifts its label.
func _tex_box(file_name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(OUT_DIR + file_name)
	sb.set_texture_margin_all(TEX_MARGIN)
	sb.content_margin_left = PAD_H
	sb.content_margin_right = PAD_H
	sb.content_margin_top = PAD_V
	sb.content_margin_bottom = PAD_V
	return sb


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("Build_UI_Themes: could not write ", path, " (", err, ")")
		return false
	return true
