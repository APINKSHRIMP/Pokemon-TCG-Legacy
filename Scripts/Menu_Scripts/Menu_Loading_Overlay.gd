class_name MenuLoadingOverlay
extends RefCounted

# ISSUE #32: shared input-blocking loading overlay for the large library menus (Sleeves, Costume,
# Coin Case, Deck/Card builder). Shows a semi-transparent dim that eats all mouse input plus a small
# box with a spinning square and "Loading…" while a grid builds. Extracted from the original inline
# Sleeves implementation so every menu that suffers the multi-second grid build can reuse it verbatim.
#
# Usage:
#   var _loading := MenuLoadingOverlay.new()
#   _loading.show(self)          # self = the scene Node the overlay is parented under
#   await get_tree().process_frame
#   await _build_the_grid()
#   _loading.hide()
#
# Escape-to-cancel is handled by each scene's own _input (it sets its cancel flag and frees the scene);
# hide() is null-safe so it can be called from those cancel paths too.

var _overlay: CanvasLayer = null
var _spinner_tween: Tween = null

# ══════════════════════════════════════════════════════════════════════════════
# TWEAKABLE VALUES (ISSUE #32 retest) — all overlay geometry lives here
# ══════════════════════════════════════════════════════════════════════════════
# Dim opacity of the input blocker. 0.0 = invisible, 1.0 = solid black.
# (Was 0.55; halved to 0.275 so it's easier to see through and flashes less when switching sets.)
const DIM_ALPHA: float = 0.275

# Deck / Card builder layout — the banner runs down the RIGHT-HAND side, so the blocker
# stops short of it and the loading box is nudged left of centre.
const DECK_ICON_OFFSET_X: float = -150.0
const DECK_ICON_OFFSET_Y: float = 11.0    # ISSUE #32 retest: box nudged 11px DOWN
const DECK_TOP_INSET:     float = 96.0    # unblocked strip at the top    (was 142)
const DECK_BOTTOM_INSET:  float = -45.0   # negative = runs past the screen bottom (was 134)
# ISSUE #32 retest (26/07): the 78px widening belongs on the RIGHT, not the left. The right inset
# drops 315 -> 237, so the blocker now reaches 78px further right; the left inset goes back to 0.
const DECK_RIGHT_INSET:   float = 237.0   # unblocked strip on the right  (was 315, before that 0)
const DECK_LEFT_INSET:    float = 0.0     # back to the screen edge (was -78, which widened LEFT by mistake)

# Coin Case / Costume / Sleeves layout — full width, smaller top/bottom banners.
const LIBRARY_ICON_OFFSET_X: float = 0.0
const LIBRARY_ICON_OFFSET_Y: float = 0.0
const LIBRARY_TOP_INSET:     float = 97.0   # was 142
const LIBRARY_BOTTOM_INSET:  float = 92.0   # was 134
const LIBRARY_RIGHT_INSET:   float = 0.0
const LIBRARY_LEFT_INSET:    float = 0.0

func is_showing() -> bool:
	return _overlay != null and is_instance_valid(_overlay)

# Convenience wrappers so every menu uses the tuned geometry above rather than its own magic numbers.
func show_for_deck(host: Node) -> void:
	show(host, DECK_ICON_OFFSET_X, DECK_TOP_INSET, DECK_BOTTOM_INSET, DECK_RIGHT_INSET, DECK_LEFT_INSET, DECK_ICON_OFFSET_Y)

func show_for_library(host: Node) -> void:
	show(host, LIBRARY_ICON_OFFSET_X, LIBRARY_TOP_INSET, LIBRARY_BOTTOM_INSET, LIBRARY_RIGHT_INSET, LIBRARY_LEFT_INSET, LIBRARY_ICON_OFFSET_Y)

# ISSUE #32 (retest): `icon_offset_x` shifts the loading box horizontally (deck screen passes -150 to
# offset the ~300px right-hand banner). `blocker_top_inset` / `blocker_bottom_inset` /
# `blocker_right_inset` leave that many pixels UNBLOCKED at the top/bottom/right of the screen so
# banner buttons (Cancel, set switch) stay clickable while the grid loads — the dim only covers the
# middle band. A negative inset simply extends the blocker past that screen edge.
func show(host: Node, icon_offset_x: float = 0.0, blocker_top_inset: float = 0.0, blocker_bottom_inset: float = 0.0, blocker_right_inset: float = 0.0, blocker_left_inset: float = 0.0, icon_offset_y: float = 0.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	hide()  # never stack two overlays
	print("ISSUE #32 FIX ACTIVE: loading overlay shown (", host.name, ") icon_x/y=", icon_offset_x, "/", icon_offset_y, " insets top/bottom/right/left=", blocker_top_inset, "/", blocker_bottom_inset, "/", blocker_right_inset, "/", blocker_left_inset)
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	host.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, DIM_ALPHA)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.offset_left = blocker_left_inset        # negative extends the blocker past the left screen edge (wider)
	dim.offset_top = blocker_top_inset          # leave the top banner clickable
	dim.offset_bottom = -blocker_bottom_inset   # leave the bottom banner clickable
	dim.offset_right = -blocker_right_inset     # leave the right-hand banner clickable
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks only within the dimmed band
	_overlay.add_child(dim)

	var box := PanelContainer.new()
	var kenney_theme = load("res://UI_Themes/ui/ui_secondary.tres")
	if kenney_theme:
		box.theme = kenney_theme
	box.custom_minimum_size = Vector2(280, 160)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -140 + icon_offset_x
	box.offset_top = -80 + icon_offset_y
	box.offset_right = 140 + icon_offset_x
	box.offset_bottom = 80 + icon_offset_y
	_overlay.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	box.add_child(vbox)

	# Spinning square acts as the loading indicator.
	var spinner := ColorRect.new()
	spinner.color = Color(1, 1, 1, 0.9)
	spinner.custom_minimum_size = Vector2(48, 48)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner.pivot_offset = Vector2(24, 24)
	vbox.add_child(spinner)

	var lbl := Label.new()
	lbl.text = "Loading…"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(lbl)

	# Continuous rotation — driven by the host so the tween lives in the tree.
	_spinner_tween = host.create_tween().set_loops()
	_spinner_tween.tween_property(spinner, "rotation_degrees", 360.0, 1.0).from(0.0)

func hide() -> void:
	if _spinner_tween != null and _spinner_tween.is_valid():
		_spinner_tween.kill()
	_spinner_tween = null
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
