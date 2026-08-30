class_name UIKit
extends RefCounted

# ============================================================
# UIKit — the reusable UI components, skinned from UITheme
# ============================================================
# Static helpers on a RefCounted, the same shape as ShopChrome, which this sits
# alongside. Every screen is assembled from these; none of them should be
# hand-rolled a second time in a screen script.
#
#   Chrome      add_field() · add_header() · add_footer()
#   Content     make_panel() · make_chip() · make_slot() · make_meter()
#               make_damage_counters()
#   Feedback    add_selection_ring() · pulse()
#   Text        style_label() · set_label() · style_button()
#
# ── THE THREE THINGS CARRYING THE THEME ──────────────────────
# The gradient bars, the darkened field, and the chevrons scrolling across both
# in opposite directions. add_field() and add_header()/add_footer() are what
# put those on a screen; a screen that skips them will not look like the rest
# of the game however well it uses the rest of this file.
#
# ── REDUCED MOTION ───────────────────────────────────────────
# Every animated component asks UITheme.motion_reduced() at build time and
# re-checks it when the theme changes. Motion stops; nothing disappears. A
# frozen chevron field still reads as the design, an absent one does not.
# ============================================================

const SHADER_CHROME := "res://Scripts/Shaders/UI_Chrome_Bar.gdshader"
const SHADER_FIELD  := "res://Scripts/Shaders/UI_Field.gdshader"
const SHADER_RING   := "res://Scripts/Shaders/UI_Selection_Ring.gdshader"
const SHADER_SLOT   := "res://Scripts/Shaders/UI_Slot.gdshader"

# Reference screen. Every absolute number in this file is a pixel in this
# space, matching DynamicMessageBox.SCREEN_W and CardDetailPanel.SCREEN_W.
const SCREEN_W := 1920.0
const SCREEN_H := 1080.0

# z bands. Chrome sits above content but below the selection ring, which must
# be visible over a card that overlaps its neighbour, and below anything modal.
const Z_FIELD  := -100
const Z_CHROME := 200
const Z_RING   := 60

# Minimum width of a footer action button, so Cancel and Save match. TWEAKABLE.
const FOOTER_BTN_W := 230.0
# Gap between the footer's action buttons.
const FOOTER_BTN_GAP := 20

# Shop-item drop shadow. TWEAKABLE — the illusion is that every item is a
# physical thing floating just above the screen, so keep the offset small and the
# alpha well under half or it reads as a second, dirtier copy of the item.
const SHADOW_OFFSET := Vector2(11.0, 14.0)
const SHADOW_ALPHA  := 0.38

# The content band left between the two 92px bars on a standard screen. Every
# converted screen lays its grid out inside this rather than re-deriving it.
const CONTENT_TOP    := 92.0
const CONTENT_BOTTOM := 988.0
const CONTENT_H      := CONTENT_BOTTOM - CONTENT_TOP


# ============================================================
# ShaderRect — a ColorRect that keeps its shader honest
# ============================================================
# The chrome and field shaders measure in real pixels so a 92px header and a
# 162px footer show the same stripe width. That only works if `rect_size` on
# the material tracks the node's actual size, which nothing does for free.
#
# It also owns the reduced-motion switch: `base_speed` is the authored scroll
# rate and `scroll_speed` on the material is either that or zero. Keeping the
# authored value here means turning motion back on does not need to know what
# the speed was.
class ShaderRect extends ColorRect:
	var base_speed: float = 0.0
	# False for the shapes that merely borrow this class for its rect_size
	# syncing — a slot outline has no scroll_speed uniform and nothing to stop.
	var tracks_motion: bool = true

	func _ready() -> void:
		resized.connect(_sync_size)
		_sync_size()
		refresh_motion()
		var ui := get_node_or_null("/root/UITheme")
		if ui != null and not ui.theme_changed.is_connected(refresh_motion):
			ui.theme_changed.connect(refresh_motion)

	func _sync_size() -> void:
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("rect_size", size)

	func refresh_motion() -> void:
		if not tracks_motion or not (material is ShaderMaterial):
			return
		var ui := get_node_or_null("/root/UITheme")
		var stopped: bool = ui != null and ui.motion_reduced()
		(material as ShaderMaterial).set_shader_parameter(
			"scroll_speed", 0.0 if stopped else base_speed)


# ============================================================
# ChromeBar — a header or footer with three layout slots
# ============================================================
# `left`, `centre` and `right` are Controls the caller fills. The title stays
# optically centred whatever goes in the side slots, because left and right are
# equal-stretch expanders and the centre shrinks to its content — a plain
# "centre the label in the bar" would drift the moment one side got a button.
class ChromeBar extends ShaderRect:
	var left: Control
	var centre: Control
	var right: Control


# ─── Chrome ──────────────────────────────────────────────────────────────────

## The dark ground a screen sits on. Add it FIRST — it anchors to the full rect
## and sits at Z_FIELD, so anything added afterwards draws over it.
static func add_field(parent: Control) -> ShaderRect:
	var rect := ShaderRect.new()
	rect.name = "ui_field"
	rect.color = Color.WHITE          # the shader replaces this entirely
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = Z_FIELD

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_FIELD)
	var ui := _ui()
	mat.set_shader_parameter("base_color", ui.col("field"))
	mat.set_shader_parameter("wash_left", ui.col("field_glow_left"))
	mat.set_shader_parameter("wash_right", ui.col("field_glow_right"))
	mat.set_shader_parameter("tint_top", ui.col("field_glow_top"))
	mat.set_shader_parameter("tint_bottom", ui.col("field_glow_bottom"))
	mat.set_shader_parameter("stripe_color", ui.col("field_texture"))
	mat.set_shader_parameter("angle_deg", ui.CHEVRON_ANGLE_DEG)
	mat.set_shader_parameter("stripe_width", ui.CHEVRON_FIELD_STRIPE)
	mat.set_shader_parameter("period", ui.CHEVRON_FIELD_PERIOD)
	rect.material = mat

	# Negative: the field scrolls LEFT while the bars scroll RIGHT. The
	# counter-motion is the point — it is what stops a static board feeling dead.
	rect.base_speed = -(ui.CHEVRON_FIELD_LOOP / ui.CHEVRON_FIELD_TIME)

	parent.add_child(rect)
	parent.move_child(rect, 0)
	return rect


## The top bar. `tall` gives the 140px variant, which exists only for screens
## needing a title AND a subtitle — the target-selection screens.
static func add_header(parent: Control, tall: bool = false) -> ChromeBar:
	var h: float = _ui().m("header_tall_h" if tall else "header_h")
	return _add_bar(parent, h, true)


## The bottom bar. `match_bar` gives the 162px variant, which is for the match
## board and NOTHING else — it exists to hold the hand. Every other screen takes
## the 92px slim footer, which is worth about two extra rows of content.
static func add_footer(parent: Control, match_bar: bool = false) -> ChromeBar:
	var h: float = _ui().m("footer_match_h" if match_bar else "footer_slim_h")
	return _add_bar(parent, h, false)


static func _add_bar(parent: Control, bar_h: float, at_top: bool) -> ChromeBar:
	var ui := _ui()

	var bar := ChromeBar.new()
	bar.name = "ui_header" if at_top else "ui_footer"
	bar.color = Color.WHITE
	bar.z_index = Z_CHROME
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE if at_top else Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	if at_top:
		bar.offset_top = 0.0
		bar.offset_bottom = bar_h
	else:
		bar.offset_top = -bar_h
		bar.offset_bottom = 0.0

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_CHROME)
	mat.set_shader_parameter("grad_a", ui.col("chrome_grad_a"))
	mat.set_shader_parameter("grad_b", ui.col("chrome_grad_b"))
	mat.set_shader_parameter("grad_c", ui.col("chrome_grad_c"))
	mat.set_shader_parameter("stripe_color", ui.col("chrome_pattern"))
	mat.set_shader_parameter("angle_deg", ui.CHEVRON_ANGLE_DEG)
	mat.set_shader_parameter("stripe_width", ui.CHEVRON_BAR_STRIPE)
	mat.set_shader_parameter("period", ui.CHEVRON_BAR_PERIOD)
	bar.material = mat
	bar.base_speed = ui.CHEVRON_BAR_LOOP / ui.CHEVRON_BAR_TIME   # positive: RIGHT

	# Three columns: left (1fr) | centre (auto) | right (1fr).
	#
	# The row is inset from both screen edges rather than padded per slot: an
	# HBoxContainer has no margin constants (margin_* belongs to MarginContainer),
	# so a per-slot override is silently ignored and the first chip ends up flush
	# against x = 0.
	var pad: float = ui.m("field_pad_h")
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = pad
	row.offset_right = -pad
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	bar.left = _bar_slot(row, HORIZONTAL_ALIGNMENT_LEFT)
	bar.centre = _bar_slot(row, HORIZONTAL_ALIGNMENT_CENTER)
	bar.right = _bar_slot(row, HORIZONTAL_ALIGNMENT_RIGHT)
	if not at_top:
		bar.centre.add_theme_constant_override("separation", FOOTER_BTN_GAP)

	parent.add_child(bar)
	return bar


## One of the header's three slots. An HBoxContainer so a slot can hold several
## things (a name field AND a count chip) without the caller building a box.
static func _bar_slot(row: HBoxContainer, align: int) -> HBoxContainer:
	var slot := HBoxContainer.new()
	# The two side slots expand equally and the centre takes only its content,
	# which is what keeps a title optically centred however lopsided the sides
	# are. Making all three expand would centre the title in the LEFTOVER space
	# instead, and it would drift the moment one side gained a button.
	slot.size_flags_horizontal = (Control.SIZE_SHRINK_CENTER
		if align == HORIZONTAL_ALIGNMENT_CENTER else Control.SIZE_EXPAND_FILL)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.alignment = (BoxContainer.ALIGNMENT_BEGIN if align == HORIZONTAL_ALIGNMENT_LEFT
		else (BoxContainer.ALIGNMENT_END if align == HORIZONTAL_ALIGNMENT_RIGHT
		else BoxContainer.ALIGNMENT_CENTER))
	slot.add_theme_constant_override("separation", 12)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(slot)
	return slot


## Swaps a legacy screen's chrome for the new one, in place.
##
## Every pre-overhaul menu is built the same way: a `BACKGROUND` Control holding
## a scrolling texture plus top and bottom border PNGs, a centred title Label,
## and its action buttons floating below the bottom border. This frees that
## BACKGROUND wholesale and lays in the field and the two bars, then hands the
## bars back so the caller can move its own controls into them.
##
## The old borders ate down to y=108 at the top and started again at y=977; the
## new bars are 92 each, so a converted screen gains ~27px of content height and
## a clean 92..988 band to lay out in — see CONTENT_TOP / CONTENT_BOTTOM.
##
## Returns { "header": ChromeBar, "footer": ChromeBar }.
static func convert_legacy_screen(root: Control, title: String) -> Dictionary:
	# THE ROOT IS USUALLY 40x40. Every legacy menu scene was authored with a
	# default-sized root Control and children pinned at absolute 1920x1080
	# offsets — which drew correctly only because a Control does not clip its
	# children. The new chrome is ANCHORED, so it would size itself to that 40x40
	# stub and put the footer at y = -52. Nothing else depends on the root's rect,
	# and the children keep their offsets from an unchanged top-left corner, so
	# widening it to the full screen is safe and fixes every converted screen.
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = 0.0
	root.offset_bottom = 0.0

	# The screen root carries ui_base, so every Label, LineEdit and Button below it
	# picks up the new face without a per-node override. Anything that still
	# assigns its own Theme in the scene keeps winning, which is what the button
	# variants rely on.
	root.theme = load("res://UI_Themes/ui/ui_base.tres")

	var old_bg := root.get_node_or_null("BACKGROUND")
	if old_bg != null:
		# free(), not queue_free(): the new field is added on this same frame and
		# deferred deletion would leave the old scrolling border drawing over it
		# until idle.
		root.remove_child(old_bg)
		old_bg.free()

	add_field(root)
	var header := add_header(root)
	var footer := add_footer(root)

	if title != "":
		var label := Label.new()
		set_label(label, "title", title, "chrome_fg")
		header.centre.add_child(label)

	return { "header": header, "footer": footer }


## Moves an existing Label into a chrome bar slot, restyled to a type role.
##
## For the screens whose title is set at runtime — a cosmetic shop names its
## seller, the pack shop names the set — where rebuilding the Label would mean
## finding and re-pointing every `header_label.text = ...` in the script.
static func adopt_label(label: Label, slot: Control, role: String = "title",
		colour_key: String = "chrome_fg") -> void:
	if label.get_parent() != null:
		label.get_parent().remove_child(label)
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0
	label.custom_minimum_size = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Drop any Theme the legacy scene assigned, so the label falls through to the
	# screen root's ui_base rather than to a Kenney variant.
	label.theme = null
	style_label(label, role, colour_key)
	slot.add_child(label)


## Moves an existing Button into a chrome bar slot, restyled. Legacy screens
## already own their Save/Cancel buttons with their signals wired, so they are
## reparented rather than rebuilt — rebuilding would mean re-connecting every
## handler and losing whatever enabled/disabled state the screen had set.
static func adopt_button(button: Button, slot: Control, variant: String,
		footer_width: bool = true) -> void:
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	# A legacy button carries absolute offsets AND a custom_minimum_size from its
	# old position; inside a container both fight the layout. custom_minimum_size
	# is the one that bites — a stepper arrow authored 90px tall stayed 90px tall
	# and filled the whole header bar. Cleared here; callers that want a specific
	# width set it after.
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.offset_left = 0.0
	button.offset_top = 0.0
	button.offset_right = 0.0
	button.offset_bottom = 0.0
	button.custom_minimum_size = Vector2.ZERO
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_button(button, variant)
	if footer_width:
		button.custom_minimum_size.x = FOOTER_BTN_W
	slot.add_child(button)


# ─── Content components ──────────────────────────────────────────────────────

## The standard surface: panel fill, 1px line border, 15px radius, no drop
## shadow. Everything that groups content sits on one of these.
static func make_panel() -> PanelContainer:
	var ui := _ui()
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ui.col("panel")
	sb.set_border_width_all(1)
	sb.border_color = ui.col("line")
	sb.set_corner_radius_all(ui.mi("panel_radius"))
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	return p


## An OPAQUE panel, for modal dialogs — load deck, rename, the empty-deck confirm.
##
## make_panel() is a translucent surface for grouping content ON a screen, and it
## is the wrong thing for a dialog: at 6.5% white over a dimmed board the whole
## popup reads as a ghost and the screen behind it competes with the text. A
## dialog needs to sit ON TOP of the world, so this one is solid, with a thicker
## border and a bigger radius.
static func make_modal_panel() -> PanelContainer:
	var ui := _ui()
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Opaque, and a touch lighter than the field so it lifts off a dimmed screen.
	sb.bg_color = ui.col("field").lightened(0.10)
	sb.set_border_width_all(2)
	sb.border_color = ui.col_a("accent", 0.55)
	sb.set_corner_radius_all(ui.mi("panel_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


## The ONLY container for a count or a status. Three variants:
##   "on_chrome" — sits on a gradient bar, so it needs its own light fill
##   "on_field"  — sits on the dark field, so a border alone is enough
##   "status"    — a solid condition colour; pass the code as `status_code`
static func make_chip(text: String, variant: String = "on_field",
		status_code: String = "") -> PanelContainer:
	var ui := _ui()
	var chip := PanelContainer.new()

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(ui.mi("corner_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left = ui.m("chip_pad_h")
	sb.content_margin_right = ui.m("chip_pad_h")
	sb.content_margin_top = ui.m("chip_pad_v")
	sb.content_margin_bottom = ui.m("chip_pad_v")

	var fg: Color
	match variant:
		"on_chrome":
			sb.bg_color = Color(1.0, 1.0, 1.0, 0.10)
			fg = ui.col("chrome_fg")
		"status":
			sb.bg_color = ui.status_colour(status_code if status_code != "" else text)
			fg = Color.WHITE
		_:
			sb.bg_color = ui.col("chip_bg")
			sb.set_border_width_all(1)
			sb.border_color = ui.col("chip_line")
			fg = ui.col("chip_fg")
	chip.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	set_label(label, "chip", text)
	label.add_theme_color_override("font_color", fg)
	chip.add_child(label)
	return chip


## An empty position: 3px slot outline, 3% fill, 7px radius. Used for empty
## bench slots, empty deck-builder cells, empty discard piles and locked
## collection tiles.
##
## This is the replacement for the black voids the old screens drew. A slot the
## player can see is progress; a black rectangle is a bug they have to rule out.
## Drawn by UI_Slot.gdshader rather than a StyleBoxFlat — see that file for why.
## The short version: at the full-pill radius a circular slot needs, StyleBoxFlat's
## four corner arcs meet at the edge midpoints and double-blend their
## antialiasing, putting a white dot at north, east, south and west.
static func make_slot(slot_size: Vector2, circular: bool = false) -> ShaderRect:
	var ui := _ui()
	var s := ShaderRect.new()
	s.tracks_motion = false          # nothing here scrolls
	s.color = Color.WHITE            # the shader replaces this entirely
	s.custom_minimum_size = slot_size
	s.size = slot_size

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_SLOT)
	mat.set_shader_parameter("fill_color", ui.col("slot_fill"))
	mat.set_shader_parameter("outline_color", ui.col("slot"))
	mat.set_shader_parameter("outline_px", ui.m("slot_outline"))
	# The shader clamps to half the short edge, so a big number is a circle.
	mat.set_shader_parameter("corner_radius", 9999.0 if circular else ui.m("slot_radius"))
	mat.set_shader_parameter("rect_size", slot_size)
	s.material = mat
	return s


## A fractional-progress bar. 12px tall, slot track, accent fill.
##
## ONLY for fractions. A whole number with no ceiling gets a box, because a bar
## with nothing to fill against is a progress track that does not exist — the
## same reason the "next unlock" panels were cut.
static func make_meter(value: float, maximum: float, width: float) -> Control:
	var ui := _ui()
	var h: float = ui.m("meter_h")

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, h)

	var track := Panel.new()
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = ui.col("slot")
	track_sb.set_corner_radius_all(ui.mi("meter_radius"))
	track_sb.anti_aliasing = true
	track.add_theme_stylebox_override("panel", track_sb)
	holder.add_child(track)

	var frac: float = 0.0 if maximum <= 0.0 else clampf(value / maximum, 0.0, 1.0)
	if frac > 0.0:
		var fill := Panel.new()
		fill.position = Vector2.ZERO
		# A meter at 2/419 must still be visible, so the fill never draws
		# narrower than its own corner diameter.
		fill.size = Vector2(maxf(width * frac, h), h)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = ui.col("accent")
		fill_sb.set_corner_radius_all(ui.mi("meter_radius"))
		fill_sb.anti_aliasing = true
		fill.add_theme_stylebox_override("panel", fill_sb)
		holder.add_child(fill)

	return holder


## Damage counters: ONE block per 10 HP, count fixed by the card's printed HP.
##
## NEVER a continuous bar. Attacks and effects in this game key off the NUMBER
## of counters ("this attack does 10 more damage for each damage counter on the
## Defending Pokemon"), so the blocks are load-bearing information, not
## decoration. Always shown alongside a numeric current/max.
##
## `bench` picks the smaller block size used under a benched Pokemon.
static func make_damage_counters(current_hp: int, max_hp: int, bench: bool = false) -> HBoxContainer:
	var ui := _ui()
	var bw: float = ui.m("dmg_bench_w" if bench else "dmg_active_w")
	var bh: float = ui.m("dmg_bench_h" if bench else "dmg_active_h")
	var gap: int = ui.mi("dmg_bench_gap" if bench else "dmg_active_gap")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)

	var total: int = int(ceil(maxf(float(max_hp), 0.0) / 10.0))
	# Ceil the DAMAGE, not the remaining HP: a Pokemon on 5 of 50 has taken 45,
	# which is five counters' worth, and should read as one block left rather
	# than as an almost-full row.
	var damage: int = maxi(max_hp - current_hp, 0)
	var damaged: int = mini(int(ceil(float(damage) / 10.0)), total)

	for i in total:
		var block := Panel.new()
		block.custom_minimum_size = Vector2(bw, bh)
		var sb := StyleBoxFlat.new()
		sb.bg_color = ui.col("good") if i < (total - damaged) else ui.col_a("accent_2", 0.30)
		sb.set_corner_radius_all(2)
		sb.anti_aliasing = true
		block.add_theme_stylebox_override("panel", sb)
		row.add_child(block)

	return row


## Lifts a shop item off the screen with a drop shadow.
##
## The shadow is the item's OWN texture drawn black and semi-transparent, offset
## down and right — so it takes the item's exact silhouette. A coin casts a round
## shadow, a booster pack a rectangular one, and a card fan the shape of the fan.
## A generic blurred blob under everything would not.
##
## Mounted as a CHILD with show_behind_parent, deliberately, and this is the one
## place that differs from the price pills: a pill must NOT scale with the
## selection pulse, but a shadow must — an item that grows while its shadow stays
## put looks like the shadow came unstuck. Being a child also means it inherits
## any dim the screen applies to the item.
##
## Safe to call on an item other code walks: the shadow is a grandchild of the
## grid cell, so `for child in grid.get_children()` never sees it.
static func add_drop_shadow(item: TextureRect, offset: Vector2 = SHADOW_OFFSET,
		alpha: float = SHADOW_ALPHA) -> TextureRect:
	if item == null or item.texture == null:
		return null

	var shadow := TextureRect.new()
	shadow.name = "drop_shadow"
	shadow.texture = item.texture
	# Match the item's own fitting exactly, or the silhouette will not line up.
	shadow.expand_mode = item.expand_mode
	shadow.stretch_mode = item.stretch_mode
	shadow.flip_h = item.flip_h
	shadow.flip_v = item.flip_v
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = offset.x
	shadow.offset_top = offset.y
	shadow.offset_right = offset.x
	shadow.offset_bottom = offset.y
	shadow.size = item.size
	shadow.modulate = Color(0.0, 0.0, 0.0, alpha)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true

	item.add_child(shadow)
	return shadow


# ─── Selection feedback ──────────────────────────────────────────────────────

## The rotating gradient ring. Mount it as a SIBLING of `target`, never a child.
##
## The selection tween scales the item; a ring parented to it would scale too
## and thicken as the item pulses. This is the same reason the shop price pills
## live on their own flat layer — see ShopChrome's "PILLS ARE NOT CHILDREN"
## note. Returns the ring so the caller can free it on deselect.
##
## `layer` is the flat Control the ring is added to; pass the same one every
## time so rings cannot end up interleaved with content.
static func add_selection_ring(layer: Control, target: Control,
		corner_radius: float = -1.0) -> ShaderRect:
	var ui := _ui()
	var inset: float = ui.SEL_RING_PX + 2.0

	var ring := ShaderRect.new()
	ring.color = Color.WHITE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = Z_RING

	# Sized from the target's LIVE global rect, so this must be called with the
	# target at rest — mid-pulse it would bake the pulsed size in.
	var r := target.get_global_rect()
	ring.global_position = r.position - Vector2(inset, inset)
	ring.size = r.size + Vector2(inset, inset) * 2.0

	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_RING)
	mat.set_shader_parameter("grad_a", ui.col("chrome_grad_a"))
	mat.set_shader_parameter("grad_b", ui.col("chrome_grad_b"))
	mat.set_shader_parameter("grad_c", ui.col("chrome_grad_c"))
	mat.set_shader_parameter("ring_width", ui.SEL_RING_PX)
	mat.set_shader_parameter("inset", inset)
	mat.set_shader_parameter("corner_radius",
		ui.m("corner_radius") if corner_radius < 0.0 else corner_radius)
	ring.material = mat

	# Reduced motion freezes the gradient rather than removing the ring — the
	# outline is the selection cue, the spin is only flavour.
	var spin: float = TAU / ui.SEL_RING_PERIOD
	mat.set_shader_parameter("spin_speed", 0.0 if ui.motion_reduced() else spin)

	layer.add_child(ring)
	return ring


## The grow half of the grow/shrink that has always meant "selected" here.
## Cards take the gentler scale, grid tiles the larger one.
static func pulse(target: Control, selected: bool, tile: bool = false) -> Tween:
	var ui := _ui()
	var to: float = 1.0
	if selected:
		to = ui.SEL_SCALE_TILE if tile else ui.SEL_SCALE_CARD

	target.pivot_offset = target.size * 0.5
	var tween := target.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var time: float = 0.0 if ui.motion_reduced() else ui.SEL_SCALE_TIME
	tween.tween_property(target, "scale", Vector2(to, to), time)
	return tween


# ─── Text ────────────────────────────────────────────────────────────────────

## Applies a type role's face, size, tracking and colour to a Label.
##
## `colour_key` names a UITheme colour; the default suits the dark field.
## `size_px` overrides the role's size while keeping its face and casing — for
## the handful of places that want, say, a small_label's mono caps at a larger
## size. Leave it at -1 to take the role's own size, which is the normal case;
## a screen that overrides it everywhere is a screen that wants a different role.
static func style_label(label: Label, role: String, colour_key: String = "field_fg",
		size_px: int = -1) -> void:
	var ui := _ui()
	# Strip Kenney-era decoration. Legacy Labels carry outline and drop-shadow
	# overrides that were there to make a thin bevelled face readable on a busy
	# background; left in place they render the new font with a heavy black halo.
	for c in ["font_outline_color", "font_shadow_color"]:
		label.remove_theme_color_override(c)
	for k in ["outline_size", "shadow_offset_x", "shadow_offset_y", "shadow_outline_size"]:
		label.remove_theme_constant_override(k)

	label.add_theme_font_override("font", ui.font(role))
	label.add_theme_font_size_override("font_size", ui.size(role) if size_px < 0 else size_px)
	label.add_theme_color_override("font_color", ui.col(colour_key))
	var track: int = ui.tracking_px(role)
	if track != 0:
		label.add_theme_constant_override("font_spacing_glyph", track)


## Styles a Label AND sets its text with the role's casing applied.
##
## Use this rather than calling to_upper() at the call site. Titles, buttons,
## names and small labels come back uppercased; dialogue, attack text and card
## effects pass through untouched. Losing that distinction is losing the main
## win of leaving Kenney behind.
static func set_label(label: Label, role: String, text: String,
		colour_key: String = "field_fg", size_px: int = -1) -> void:
	style_label(label, role, colour_key, size_px)
	label.text = _ui().cased(role, text)


## Points a Button at one of the generated variant themes and applies the
## button role's casing to its text.
##
##   "primary"   the screen's one confirm action
##   "secondary" everything else, and the default
##   "selected"  the option currently in effect
##   "good"      a save with a pending change
##   "danger"    destructive
##   "warn"      a toggle that is currently on
##
## ── FIRES ON PRESS, NOT RELEASE ──────────────────────────────
## Godot's default is ACTION_MODE_BUTTON_RELEASE, which means nothing happens
## until the mouse comes back UP, and moving the pointer even slightly while
## held cancels the press outright. That reads as lag and as dropped clicks, and
## it is the single biggest thing making a menu feel sluggish. Every button
## styled through here fires the moment it is pressed.
##
## Anything destructive is behind a confirm dialog, so there is nothing here a
## press-to-fire button can do that a release-to-fire one could not.
static func style_button(button: Button, variant: String = "secondary") -> void:
	var path := "res://UI_Themes/ui/ui_%s.tres" % variant
	var t: Theme = load(path)
	if t == null:
		push_error("UIKit: no button theme '" + variant + "' — run Build_UI_Themes.gd")
		return
	button.theme = t
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.text = _ui().cased("button", button.text)


## A footer action button — Cancel, Save, Buy, Close, Confirm.
##
## Buttons autosize to their text, so "Save" came out visibly narrower than
## "Cancel" sitting next to it. Every footer action is at least FOOTER_BTN_W
## wide so a pair reads as a pair; longer labels still grow past it.
static func make_footer_button(text: String, variant: String = "secondary") -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, variant)
	b.custom_minimum_size.x = FOOTER_BTN_W
	return b


static func _ui() -> Node:
	return Engine.get_main_loop().get_root().get_node("/root/UITheme")
