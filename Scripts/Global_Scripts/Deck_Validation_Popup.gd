class_name DeckValidationPopup

# ============================================================
# DECK VALIDATION POPUP — static utility
# ============================================================
# Builds the full-screen overlay shown when an opponent rejects
# the player's currently-selected deck.
#
# Two display flavours, picked by the caller via `title`:
#   "Banned cards"             — shows the NPC's banlist
#   "Cards in your deck that aren't allowed"  — shows player's offending cards
#
# Layout (matches Deck_Build_And_Card_View's deck-viewer overlay):
#   - 55% black backdrop
#   - title label at top
#   - rule description label under title (multi-line)
#   - ScrollContainer → MarginContainer → GridContainer (9 columns)
#   - "close" button bottom-right
#
# Usage:
#   DeckValidationPopup.show_popup(parent_node, "Banned cards",
#       ["base1-88", "base1-89"], ["Banned by gym rules:"], func(): print("closed"))
# ============================================================

const CARD_SIZE  := Vector2(183, 254)
const CARD_H_SEP := 2
const CARD_V_SEP := 2
const COLUMNS    := 9

const KENNEY_THEME     := "res://UI_Themes/kenneyUI.tres"
const KENNEY_RED_THEME := "res://UI_Themes/kenneyUI-red.tres"

# Builds and attaches the overlay to `parent`. `on_closed` is invoked
# (with no args) when the player clicks the close button.
static func show_popup(parent: Node,
		title: String,
		card_ids: Array,
		body_lines: Array,
		on_closed: Callable) -> Control:
	var overlay := Control.new()
	overlay.z_index = 200
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.z_index = 0
	overlay.add_child(backdrop)

	var kenney: Theme = load(KENNEY_THEME)

	var title_lbl := Label.new()
	if kenney:
		title_lbl.theme = kenney
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 44)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.position = Vector2(200, 25)
	title_lbl.size     = Vector2(1520, 60)
	title_lbl.z_index  = 10
	overlay.add_child(title_lbl)

	# Rule description — optional. Sits between the title and the grid.
	var body_text := ""
	for line in body_lines:
		if String(line).strip_edges() == "":
			continue
		body_text += String(line) + "\n"
	body_text = body_text.strip_edges()

	var body_height := 0.0
	if body_text != "":
		var body_lbl := Label.new()
		if kenney:
			body_lbl.theme = kenney
		body_lbl.text = body_text
		body_lbl.add_theme_font_size_override("font_size", 26)
		body_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_lbl.position = Vector2(200, 90)
		body_lbl.size     = Vector2(1520, 130)
		body_lbl.z_index  = 10
		overlay.add_child(body_lbl)
		body_height = 130.0

	var grid_top := 95.0 + body_height + 15.0
	var grid_bottom_margin := 110.0
	var grid_height := 1080.0 - grid_top - grid_bottom_margin

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(5, grid_top)
	scroll.size = Vector2(1910, grid_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	scroll.z_index = 5
	overlay.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", CARD_H_SEP)
	grid.add_theme_constant_override("v_separation", CARD_V_SEP)
	margin.add_child(grid)

	for cid in card_ids:
		var card_rect := TextureRect.new()
		var tex_path := DeckValidationHelper.card_image_path(String(cid))
		var card_texture = null
		if tex_path != "" and ResourceLoader.exists(tex_path):
			card_texture = load(tex_path)
		if card_texture != null:
			card_rect.texture = card_texture
		card_rect.custom_minimum_size = CARD_SIZE
		card_rect.size = CARD_SIZE
		card_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card_rect.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
		card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(card_rect)

	var close_btn := Button.new()
	close_btn.text = "close"
	close_btn.custom_minimum_size = Vector2(226, 63)
	close_btn.position = Vector2(1689, 1003)
	close_btn.z_index = 20
	var red_theme = load(KENNEY_RED_THEME)
	if red_theme:
		close_btn.theme = red_theme
	close_btn.add_theme_font_size_override("font_size", 23)
	close_btn.pressed.connect(func ():
		overlay.queue_free()
		if on_closed.is_valid():
			on_closed.call()
	)
	overlay.add_child(close_btn)

	return overlay
