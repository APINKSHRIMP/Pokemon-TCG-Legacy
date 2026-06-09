class_name MessageBoxHelper

# ============================================================
# MESSAGEBOX HELPER — static utility
# ============================================================
# Builds the standard image-backed messagebox used across the
# game (outro scene, NPC interactions, etc.).
#
# Uses ABSOLUTE pixel coordinates (layout_mode 0) so the box is
# always positioned correctly regardless of its parent's size.
# Anchors are intentionally left at 0 — the full 1920×1080
# coordinate space is baked into every position.
#
# To retheme every messagebox at once, change TEXTURE_PATH.
# ============================================================

# All messageboxes in the game share this image.
const TEXTURE_PATH = "res://Image_Assets/Messageboxes/bluesquaremessagebox.png"
const KENNEY_THEME       = "res://UI_Themes/kenneyUI.tres"
const KENNEY_THEME_GREEN = "res://UI_Themes/kenneyUI-green.tres"
const KENNEY_THEME_RED   = "res://UI_Themes/kenneyUI-red.tres"
const KENNEY_THEME_BLUE  = "res://UI_Themes/kenneyUI-blue.tres"
const MSG_FONT_PATH = "res://UI_Themes/LupinademoRegular-X3ovd.otf"

# Reference screen dimensions
const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# The image is 1910 px wide — 955 either side of screen centre
const BOX_HALF_WIDTH : float = 955.0

# ============================================================
# build()
# ============================================================
# Parameters:
#   box_height     — pixels the box occupies from the screen bottom.
#                    156 = compact single-line (match style).
#                    200 = multi-line NPC / outro style (default).
#   font_size      — point size. Smaller = more lines.
#   include_buttons — false for click-to-advance screens (outro).
#
# Returns:
#   "root"    Control  — add_child this to your scene
#   "label"   Label    — set .text to display messages
#   "yes_btn" Button | null
#   "no_btn"  Button | null
#   "ok_btn"  Button | null
# ============================================================
static func build(box_height: float = 200.0,
				  font_size:  int   = 24,
				  include_buttons: bool = true,
				  extra_padding: float = 0.0,
				  extra_padding_top: float = -1.0,
				  extra_padding_right: float = -1.0) -> Dictionary:

	var kenney: Theme = load(KENNEY_THEME)
	var msg_font: FontFile = load(MSG_FONT_PATH)
	var msg_font_bold := FontVariation.new()
	msg_font_bold.base_font = msg_font
	msg_font_bold.variation_embolden = 1.0
	var msg_font_italic := FontVariation.new()
	msg_font_italic.base_font = msg_font
	msg_font_italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.25, 1.0), Vector2(0.0, 0.0))

	# ── Root ─────────────────────────────────────────────────
	# Explicitly sized to the full reference screen so children
	# can use absolute pixel positions relative to its top-left.
	# All anchors stay at 0 so the size is determined purely by
	# the offset_right / offset_bottom values.
	var root := Control.new()
	root.offset_left   = 0.0
	root.offset_top    = 0.0
	root.offset_right  = SCREEN_W
	root.offset_bottom = SCREEN_H
	root.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.visible = false

	# ── Messagebox image ─────────────────────────────────────
	# Placed at the bottom of the reference screen.
	var img_x := SCREEN_W / 2.0 - BOX_HALF_WIDTH   # = 5.0
	var img_y := SCREEN_H - box_height

	var tex_rect := TextureRect.new()
	tex_rect.offset_left   = img_x
	tex_rect.offset_top    = img_y
	tex_rect.offset_right  = img_x + BOX_HALF_WIDTH * 2.0
	tex_rect.offset_bottom = SCREEN_H
	tex_rect.texture       = load(TEXTURE_PATH)
	tex_rect.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode  = TextureRect.STRETCH_SCALE
	tex_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(tex_rect)

	# ── Content VBox (label + optional buttons) ───────────────
	# extra_padding pushes text in from the LEFT and RIGHT (horizontal inset).
	# extra_padding_top pushes text DOWN from the top; if left as -1 it inherits
	# extra_padding so the old single-value calls still behave identically.
	var margin := 18.0
	var pad_top:   float = extra_padding_top   if extra_padding_top   >= 0.0 else extra_padding
	var pad_right: float = extra_padding_right if extra_padding_right >= 0.0 else extra_padding
	var vbox := VBoxContainer.new()
	vbox.offset_left   = img_x + margin + extra_padding
	vbox.offset_top    = img_y + margin + pad_top
	vbox.offset_right  = img_x + BOX_HALF_WIDTH * 2.0 - margin - pad_right
	vbox.offset_bottom = SCREEN_H - (65.0 if include_buttons else margin)
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	# ── Text label ────────────────────────────────────────────
	# RichTextLabel so [b]...[/b] tags can bold the speaker name and footer
	# while leaving body text in the regular weight.
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active  = false
	label.fit_content    = true
	label.add_theme_font_override("normal_font",   msg_font)
	label.add_theme_font_override("bold_font",     msg_font_bold)
	label.add_theme_font_override("italics_font",  msg_font_italic)
	label.add_theme_font_size_override("normal_font_size",   font_size)
	label.add_theme_font_size_override("bold_font_size",     font_size)
	label.add_theme_font_size_override("italics_font_size",  font_size)
	label.add_theme_color_override("default_color", Color(0, 0, 0, 1))
	# Natural height by default so optional buttons sit immediately under the
	# text with no trailing gap. Callers that want the label to fill the box
	# (e.g. the gift "You received…" panel) can set SIZE_EXPAND_FILL themselves
	# after build() returns.
	vbox.add_child(label)

	# ── Optional buttons ─────────────────────────────────────
	var yes_btn: Button = null
	var no_btn:  Button = null
	var ok_btn:  Button = null

	if include_buttons:
		var kenney_green: Theme = load(KENNEY_THEME_GREEN)
		var kenney_red:   Theme = load(KENNEY_THEME_RED)
		var kenney_blue:  Theme = load(KENNEY_THEME_BLUE)

		# Buttons are anchored to a fixed position at the bottom of the box,
		# independent of text length so they never shift around.
		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 30)
		btn_row.offset_left   = img_x + margin
		btn_row.offset_top    = SCREEN_H - 65.0
		btn_row.offset_right  = img_x + BOX_HALF_WIDTH * 2.0 - margin
		btn_row.offset_bottom = SCREEN_H - 20.0
		root.add_child(btn_row)

		yes_btn = Button.new()
		yes_btn.text = "  Yes  "
		yes_btn.theme = kenney_green
		yes_btn.add_theme_font_size_override("font_size", 20)
		yes_btn.custom_minimum_size = Vector2(144, 0)
		yes_btn.visible = false
		btn_row.add_child(yes_btn)

		no_btn = Button.new()
		no_btn.text = "  No  "
		no_btn.theme = kenney_red
		no_btn.add_theme_font_size_override("font_size", 20)
		no_btn.custom_minimum_size = Vector2(144, 0)
		no_btn.visible = false
		btn_row.add_child(no_btn)

		ok_btn = Button.new()
		ok_btn.text = "  OK  "
		ok_btn.theme = kenney_blue
		ok_btn.add_theme_font_size_override("font_size", 20)
		ok_btn.custom_minimum_size = Vector2(144, 0)
		ok_btn.visible = false
		btn_row.add_child(ok_btn)

	return {
		"root":    root,
		"label":   label,
		"yes_btn": yes_btn,
		"no_btn":  no_btn,
		"ok_btn":  ok_btn,
	}
