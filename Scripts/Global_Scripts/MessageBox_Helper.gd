class_name MessageBoxHelper

# ============================================================
# MESSAGEBOX HELPER — static utility
# ============================================================
# Thin factory over DynamicMessageBox, which is where the actual layout,
# theming and chip logic lives. Kept as a separate entry point because every
# existing call site (the outro scene, MapManager) already builds its box
# through build() and expects this return shape.
#
# The box is drawn procedurally — there is no messagebox PNG any more. To
# change its colours, edit MessageBoxTheme; to change its geometry, edit the
# TWEAKABLE LAYOUT block in Dynamic_Message_Box.gd.
#
# Uses ABSOLUTE pixel coordinates in a 1920x1080 reference space, so the box
# lands in the same place regardless of its parent's size.
# ============================================================

const SCREEN_W : float = DynamicMessageBox.SCREEN_W
const SCREEN_H : float = DynamicMessageBox.SCREEN_H

# ============================================================
# build()
# ============================================================
# Parameters:
#   box_height      — height of the main panel in reference px.
#   font_size       — body text size. Smaller = more lines.
#   include_buttons — false for click-to-advance screens (outro).
#   extra_padding   — extra horizontal inset on top of the standard text pad.
#   extra_padding_top / _right — as above per side; -1 inherits extra_padding,
#                     which is what the older single-value call sites rely on.
#
# Returns:
#   "root"    DynamicMessageBox — add_child this to your scene. Call
#             .set_chips([...]) on it to show the info chips above the panel.
#   "label"   RichTextLabel — set .text to display messages
#   "yes_btn" / "no_btn" / "ok_btn"  Button | null
# ============================================================
static func build(box_height: float = 138.0,
				  font_size:  int   = 28,
				  include_buttons: bool = true,
				  extra_padding: float = 0.0,
				  extra_padding_top: float = -1.0,
				  extra_padding_right: float = -1.0) -> Dictionary:

	var pad_top:   float = extra_padding_top   if extra_padding_top   >= 0.0 else extra_padding
	var pad_right: float = extra_padding_right if extra_padding_right >= 0.0 else extra_padding

	var box := DynamicMessageBox.new()
	box.configure(box_height, font_size, include_buttons, extra_padding, pad_top, pad_right)

	return {
		"root":    box,
		"label":   box.label,
		"yes_btn": box.yes_button,
		"no_btn":  box.no_button,
		"ok_btn":  box.ok_button,
	}
