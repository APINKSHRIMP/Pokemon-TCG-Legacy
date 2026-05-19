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
const KENNEY_THEME = "res://UI_Themes/kenneyUI.tres"

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
				  extra_padding: float = 0.0) -> Dictionary:

	var kenney: Theme = load(KENNEY_THEME)

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
	# extra_padding pushes text further in from the left, right, and top.
	var margin := 18.0
	var vbox := VBoxContainer.new()
	vbox.offset_left   = img_x + margin + extra_padding
	vbox.offset_top    = img_y + margin + extra_padding
	vbox.offset_right  = img_x + BOX_HALF_WIDTH * 2.0 - margin - extra_padding
	vbox.offset_bottom = SCREEN_H - margin
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	# ── Text label ────────────────────────────────────────────
	var label := Label.new()
	label.theme = kenney
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	label.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)

	# ── Optional buttons ─────────────────────────────────────
	var yes_btn: Button = null
	var no_btn:  Button = null
	var ok_btn:  Button = null

	if include_buttons:
		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 30)
		vbox.add_child(btn_row)

		yes_btn = Button.new()
		yes_btn.text = "  Yes  "
		yes_btn.theme = kenney
		yes_btn.add_theme_font_size_override("font_size", 20)
		yes_btn.visible = false
		btn_row.add_child(yes_btn)

		no_btn = Button.new()
		no_btn.text = "  No  "
		no_btn.theme = kenney
		no_btn.add_theme_font_size_override("font_size", 20)
		no_btn.visible = false
		btn_row.add_child(no_btn)

		ok_btn = Button.new()
		ok_btn.text = "  OK  "
		ok_btn.theme = kenney
		ok_btn.add_theme_font_size_override("font_size", 20)
		ok_btn.visible = false
		btn_row.add_child(ok_btn)

	return {
		"root":    root,
		"label":   label,
		"yes_btn": yes_btn,
		"no_btn":  no_btn,
		"ok_btn":  ok_btn,
	}
