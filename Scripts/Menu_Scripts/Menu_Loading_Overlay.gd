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

func is_showing() -> bool:
	return _overlay != null and is_instance_valid(_overlay)

# ISSUE #32 (retest): `icon_offset_x` shifts the loading box horizontally (deck screen passes -150 to
# offset the ~300px right-hand banner). `blocker_top_inset` / `blocker_bottom_inset` leave that many
# pixels UNBLOCKED at the top/bottom of the screen so banner buttons (Cancel, set switch) stay
# clickable while the grid loads — the dim only covers the middle band.
func show(host: Node, icon_offset_x: float = 0.0, blocker_top_inset: float = 0.0, blocker_bottom_inset: float = 0.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	hide()  # never stack two overlays
	print("ISSUE #32 FIX ACTIVE: loading overlay shown (", host.name, ") icon_x=", icon_offset_x, " insets=", blocker_top_inset, "/", blocker_bottom_inset)
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	host.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.offset_top = blocker_top_inset          # leave the top banner clickable
	dim.offset_bottom = -blocker_bottom_inset   # leave the bottom banner clickable
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks only within the dimmed band
	_overlay.add_child(dim)

	var box := PanelContainer.new()
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
	if kenney_theme:
		box.theme = kenney_theme
	box.custom_minimum_size = Vector2(280, 160)
	box.anchor_left = 0.5
	box.anchor_top = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -140 + icon_offset_x
	box.offset_top = -80
	box.offset_right = 140 + icon_offset_x
	box.offset_bottom = 80
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
