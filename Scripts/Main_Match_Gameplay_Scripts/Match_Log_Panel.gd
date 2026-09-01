class_name MatchLogPanel
extends Control

# ============================================================
# MATCH LOG PANEL — the Caps Lock message history
# ============================================================
# Every message the match has shown this round, in one scrollable panel.
#
# The design idea is that the message box GROWS UPWARD into its own history:
# this panel uses the same shader, the same side margins and the same bottom
# edge as the in-match DynamicMessageBox, so the newest entry lands almost
# exactly where the box you were just reading sat. Opening the log reads as the
# box getting taller rather than as a modal appearing from nowhere.
#
#   ┌─────────────────────────────────────────────────────────┐  <- panel top
#   │  (MISTY)  (TURN 6)                    CAPS LOCK to close│  <- header pills
#   │ ─────────────────────────────────────────────────────── │
#   │   ── TURN 4 · YOU ────────────────────────────────────  │  <- turn divider
#   │     You attached Water Energy to Staryu.                │
#   │     Staryu used Slap! 20 damage.                        │
#   │   ── TURN 5 · MISTY ──────────────────────────────────  │
#   │   ▌ Misty played Bill.                                  │  <- stripe = their turn
#   │   ▌ Starmie used Star Freeze! 20 damage.                │
#   │   ── TURN 6 · YOU ────────────────────────────────────  │
#   │     You drew a card.                                    │  <- newest, at the bottom
#   └─────────────────────────────────────────────────────────┘  <- 1068, same as the box
#
# ── THE THREE DELIBERATE DEPARTURES FROM THE LIVE BOX ────────
# 1. Text is LEFT aligned. show_message() centres its one short line, which is
#    right for one line and wrong for forty — a column of ragged centred lines
#    is genuinely hard to scan.
# 2. The font drops from the match's 40 to MATCH_LOG_FONT_SIZE. Kenney is a
#    display face; a screen of it at 40 is unreadable.
# 3. Only the OPPONENT's turn gets a colour stripe. Striping both sides would
#    be decoration — when you scroll back you are looking for what THEY did.
#
# ── WHY THERE IS NO CHIP ROW ─────────────────────────────────
# DynamicMessageBox's chips are laid out by a private _rebuild_chips() pinned
# to its own panel geometry, and chips are designed to perch on top of a SHORT
# box at the screen bottom — floating them above a full-height panel looks
# wrong. The header pills below are the same shader with the same pill settings
# (CHIP_EDGE_SOLID / CHIP_EDGE_FADE), so the visual language carries over
# without duplicating the layout code.
#
# ── SCROLLING IS DRIVEN BY HAND, NOT BY THE ScrollContainer ──
# The match's _input() swallows everything while the log is open, and _input()
# runs BEFORE GUI input — so a consumed wheel event never reaches the
# ScrollContainer. handle_scroll_input() therefore moves scroll_vertical
# itself. That is also what makes the wheel work with the cursor anywhere on
# screen rather than only over the panel, and it gives the arrow keys and
# Page Up/Down the same path for free (and a controller stick later).
# ============================================================

const SHADER_PATH := "res://Scripts/Shaders/Rounded_Message_Panel.gdshader"
const FONT_PATH   := "res://UI_Themes/ChakraPetch-Medium.ttf"

# Reference screen, same space every offset below is written in.
const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# ══════════════════════════════════════════════════════════════════════════
# TWEAKABLE LAYOUT — every number the design depends on lives in this block
# ══════════════════════════════════════════════════════════════════════════

# Panel geometry. MARGIN_X and BOTTOM_Y are deliberately copied from
# DynamicMessageBox.PANEL_MARGIN_X / PANEL_BOTTOM_NO_BUTTONS so the log lines up
# with the live box exactly. If you move the message box, move these too.
const PANEL_MARGIN_X : float = 12.0
const PANEL_BOTTOM_Y : float = 1068.0
# DERIVED, not a free number: the panel is inset from the top of the screen by
# exactly as much as it is from the bottom, so the gap reads the same above and
# below. PANEL_BOTTOM_Y leaves 12px under the panel, which is also PANEL_MARGIN_X,
# so the log ends up with a uniform 12px margin on all four sides. Move the bottom
# edge and the top follows on its own — do not replace this with a literal.
const PANEL_TOP_Y    : float = SCREEN_H - PANEL_BOTTOM_Y
const PANEL_CORNER_R : float = 34.0
const PANEL_EDGE_SOLID : Vector2 = Vector2(26.0, 2.0)
const PANEL_EDGE_FADE  : Vector2 = Vector2(12.0, 4.0)

# Inside the panel: how far the content sits in from the panel edge. The x pad
# must clear the shader's colour band (26 + 12) or rows would sit on colour.
const CONTENT_PAD_X : float = 48.0
const CONTENT_PAD_T : float = 18.0
const CONTENT_PAD_B : float = 22.0

# Backdrop dim over the board.
const BACKDROP_ALPHA : float = 0.55

# Header
const HEADER_H          : float = 54.0
const HEADER_PILL_H     : float = 44.0
const HEADER_PILL_PAD_X : float = 20.0
const HEADER_PILL_GAP   : float = 10.0
const HEADER_FONT_SIZE  : int   = 24
const HEADER_HINT_SIZE  : int   = 19
const HEADER_RULE_H     : float = 2.0
## ISSUE #161: the opponent sprite drawn inside their header pill. TWEAKABLE — the
## height is fixed and the width follows the trimmed art's aspect.
const HEADER_ICON_H     : float = 38.0
const HEADER_ICON_GAP   : float = 10.0
const HEADER_RULE_GAP   : float = 12.0
# Pill labels are black like the message box's chips, but the dark themes would
# swallow them — same threshold and same flip to white.
const PILL_TEXT_LIGHT_THRESHOLD : float = 0.55

# Entries
const ROW_FONT_SIZE   : int   = 22
const ROW_LINE_SPACING: int   = 6
const ROW_PAD_X       : float = 14.0
const ROW_PAD_Y       : float = 5.0
const ROW_SEPARATION  : int   = 2
const ROW_STRIPE_W    : int   = 5      # left border on opponent-turn rows
const ROW_TINT_ALPHA  : float = 0.045  # alternating row wash, helps track wrapped lines

# Turn dividers
const DIVIDER_FONT_SIZE : int   = 19
const DIVIDER_RULE_H    : float = 2.0
const DIVIDER_TOP_GAP   : int   = 16   # space above a divider
const DIVIDER_BOTTOM_GAP: int   = 6    # space below it

# Scrolling. STEP is one wheel notch / arrow press; PAGE_FRACTION is how much of
# the visible height Page Up/Down moves.
const SCROLL_STEP     : int   = 90
const PAGE_FRACTION   : float = 0.85

# ══════════════════════════════════════════════════════════════════════════

var _theme_key: String = MessageBoxTheme.DEFAULT_THEME
var _opponent_label: String = "OPPONENT"

var _panel: ColorRect = null
var _header: Control = null
var _scroller: ScrollContainer = null
var _rows: VBoxContainer = null

var _font: Font = null
var _font_bold: FontVariation = null


# ============================================================
# CONSTRUCTION
# ============================================================
# theme_key       — the opponent's `message_colour`, so the log wears the same
#                   colour as the message box and the outro screen.
# opponent_label  — shown on a header pill and on every one of their turn
#                   dividers. Falls back to "OPPONENT" when empty.
func configure(theme_key: String, opponent_label: String) -> void:
	_theme_key = theme_key if MessageBoxTheme.has_theme(theme_key) else MessageBoxTheme.DEFAULT_THEME
	_opponent_label = opponent_label.strip_edges().to_upper()
	if _opponent_label == "":
		_opponent_label = "OPPONENT"

	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = SCREEN_W
	offset_bottom = SCREEN_H
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	_font = load(FONT_PATH)
	_font_bold = FontVariation.new()
	_font_bold.base_font = _font
	_font_bold.variation_embolden = 1.0

	# ── Backdrop ─────────────────────────────────────────────
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, BACKDROP_ALPHA)
	backdrop.offset_right  = SCREEN_W
	backdrop.offset_bottom = SCREEN_H
	backdrop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# ── Panel ────────────────────────────────────────────────
	var panel_h := PANEL_BOTTOM_Y - PANEL_TOP_Y
	_panel = _make_shader_rect()
	_panel.position = Vector2(PANEL_MARGIN_X, PANEL_TOP_Y)
	_panel.size     = Vector2(SCREEN_W - PANEL_MARGIN_X * 2.0, panel_h)
	var edge := MessageBoxTheme.panel_edge_color(_theme_key)
	_apply_shader(_panel, edge, edge, Color.WHITE,
				  PANEL_CORNER_R, PANEL_EDGE_SOLID, PANEL_EDGE_FADE)
	add_child(_panel)

	var content_l := PANEL_MARGIN_X + CONTENT_PAD_X
	var content_r := SCREEN_W - PANEL_MARGIN_X - CONTENT_PAD_X

	# ── Header ───────────────────────────────────────────────
	_header = Control.new()
	_header.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_header.offset_left   = content_l
	_header.offset_top    = PANEL_TOP_Y + CONTENT_PAD_T
	_header.offset_right  = content_r
	_header.offset_bottom = PANEL_TOP_Y + CONTENT_PAD_T + HEADER_H
	add_child(_header)
	_build_header(content_r - content_l)

	# ── Scrolling list ───────────────────────────────────────
	var list_top := PANEL_TOP_Y + CONTENT_PAD_T + HEADER_H + HEADER_RULE_GAP

	_scroller = ScrollContainer.new()
	_scroller.offset_left   = content_l
	_scroller.offset_top    = list_top
	_scroller.offset_right  = content_r
	_scroller.offset_bottom = PANEL_BOTTOM_Y - CONTENT_PAD_B
	_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The wheel is driven by hand (see the header note), so the container never
	# needs to be hovered — and it must not eat clicks meant for the match.
	_scroller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroller)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", ROW_SEPARATION)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroller.add_child(_rows)


# The two header pills plus the hint text and the rule under them. Same shader
# and same pill settings the message box's chips use, so they read as the same
# component family without borrowing its private layout code.
func _build_header(header_w: float) -> void:
	var x := 0.0
	# ISSUE #161: the opponent's overworld sprite sits in their name pill, exactly
	# as it does on the message boxes outside a match. The sprite name is carried
	# in GameState.last_battled_opponent_entry, written when the battle starts.
	x = _add_header_pill(_opponent_label, 0, x, _opponent_sprite_name())
	_add_header_pill("MATCH LOG", 1, x)

	# Right-aligned hint. Grey rather than themed — it is instruction, not content.
	var hint := Label.new()
	hint.text = "CAPS LOCK to close"
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", HEADER_HINT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.42, 0.42, 0.46, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.offset_left   = header_w - 420.0
	hint.offset_right  = header_w
	hint.offset_top    = 0.0
	hint.offset_bottom = HEADER_PILL_H
	_header.add_child(hint)

	var rule := ColorRect.new()
	rule.color = MessageBoxTheme.chip_color(_theme_key, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.offset_left   = 0.0
	rule.offset_right  = header_w
	rule.offset_top    = HEADER_H - HEADER_RULE_H
	rule.offset_bottom = HEADER_H
	_header.add_child(rule)


# Draws one pill at `x` and returns the x the next pill should start at.
# `ramp_index` walks MessageBoxTheme's chip ramp exactly like a real chip row.
## ISSUE #161: the overworld sprite-sheet name for the opponent being fought, or
## "" when there is none (the T-key TEST match leaves it blank on purpose).
func _opponent_sprite_name() -> String:
	var entry = GameState.last_battled_opponent_entry
	if not (entry is Dictionary):
		return ""
	return String(entry.get("sprite", ""))


func _add_header_pill(text: String, ramp_index: int, x: float,
		sprite_name: String = "") -> float:
	var col := MessageBoxTheme.chip_color(_theme_key, ramp_index)
	var text_w := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE).x

	# ISSUE #161: DynamicMessageBox.sprite_icon() crops the idle-down frame of the
	# 4x4 sheet to its opaque pixels and caches it, so this is the same picture the
	# overworld chip row draws and costs nothing after the first call.
	var icon_tex: Texture2D = null
	var icon_size := Vector2.ZERO
	if sprite_name != "":
		icon_tex = DynamicMessageBox.sprite_icon(sprite_name)
		if icon_tex != null:
			var t := icon_tex.get_size()
			var fit: float = HEADER_ICON_H / maxf(t.y, 1.0)
			icon_size = Vector2(t.x * fit, t.y * fit)

	var icon_slot: float = (icon_size.x + HEADER_ICON_GAP) if icon_tex != null else 0.0
	var pill_w: float = text_w + icon_slot + HEADER_PILL_PAD_X * 2.0

	var pill := _make_shader_rect()
	pill.position = Vector2(x, 0.0)
	pill.size     = Vector2(pill_w, HEADER_PILL_H)
	_apply_shader(pill, col, col, col, HEADER_PILL_H * 0.5,
				  Vector2(9999.0, 9999.0), Vector2(1.0, 1.0))
	_header.add_child(pill)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	lbl.add_theme_color_override("font_color", _pill_text_color(col))
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ISSUE #161: with a sprite in the pill the label is left-aligned after it;
	# without one it keeps the centred look every other pill has.
	if icon_tex != null:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.offset_left = x + HEADER_PILL_PAD_X + icon_slot
	else:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.offset_left = x
	lbl.offset_right  = x + pill_w
	lbl.offset_top    = 0.0
	lbl.offset_bottom = HEADER_PILL_H
	_header.add_child(lbl)

	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture        = icon_tex
		icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode   = TextureRect.STRETCH_SCALE
		# NEAREST: these are pixel-art sheets and bilinear turns them to mush.
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		icon.size     = icon_size
		icon.position = Vector2(x + HEADER_PILL_PAD_X,
			(HEADER_PILL_H - icon_size.y) * 0.5)
		_header.add_child(icon)

	return x + pill_w + HEADER_PILL_GAP


func _pill_text_color(col: Color) -> Color:
	# Same perceived-brightness test DynamicMessageBox uses on its chip labels.
	var brightness := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	return Color.WHITE if brightness < PILL_TEXT_LIGHT_THRESHOLD else Color.BLACK


# ============================================================
# CONTENT
# ============================================================
# entries — the match's own log array, oldest first. Each entry is
#           { "text": String, "turn": int, "opp": bool }.
#
# Rebuilt wholesale on every open rather than appended to live: a match can fire
# thousands of messages and none of that work is worth doing while the board is
# running. The list is short enough that a full rebuild is imperceptible.
func set_entries(entries: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()

	if entries.is_empty():
		_rows.add_child(_make_empty_state())
		return

	var last_turn: int = -1
	var last_opp: bool = false
	var have_last: bool = false
	var stripe_index: int = 0

	for entry in entries:
		var turn: int = int(entry.get("turn", 0))
		var opp: bool = bool(entry.get("opp", false))

		if not have_last or turn != last_turn or opp != last_opp:
			_rows.add_child(_make_divider(turn, opp, not have_last))
			last_turn = turn
			last_opp = opp
			have_last = true
			stripe_index = 0

		_rows.add_child(_make_row(str(entry.get("text", "")), opp, stripe_index))
		stripe_index += 1


func _make_empty_state() -> Control:
	var lbl := Label.new()
	lbl.text = "No messages yet this match."
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(0.42, 0.42, 0.46, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# "── TURN 4 · YOU ─────────" — the label sits left, a hairline rule fills the
# rest of the width. `first` drops the leading gap so the list doesn't open with
# a blank band above the very first divider.
func _make_divider(turn: int, opp: bool, first: bool) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not first:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, DIVIDER_TOP_GAP)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(gap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)

	var who: String = _opponent_label if opp else "YOU"
	var lbl := Label.new()
	# turn_number only increments at the PLAYER's turn start (see
	# player_start_turn_checks), so it reads as a round number and both sides of
	# a round share it — which is exactly what you want written on a divider.
	lbl.text = "TURN %d  ·  %s" % [turn, who]
	lbl.add_theme_font_override("font", _font_bold)
	lbl.add_theme_font_size_override("font_size", DIVIDER_FONT_SIZE)
	lbl.add_theme_color_override("font_color", _divider_color(opp))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var rule_col := _divider_color(opp)
	rule_col.a = 0.35
	var rule := ColorRect.new()
	rule.color = rule_col
	rule.custom_minimum_size = Vector2(0, DIVIDER_RULE_H)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)

	var gap_b := Control.new()
	gap_b.custom_minimum_size = Vector2(0, DIVIDER_BOTTOM_GAP)
	gap_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(gap_b)

	return wrap


# The opponent's turns are drawn in their own colour; yours in a neutral grey.
# Same asymmetry as the row stripe, and for the same reason.
func _divider_color(opp: bool) -> Color:
	if opp:
		return MessageBoxTheme.chip_color(_theme_key, 0).darkened(0.15)
	return Color(0.38, 0.38, 0.43, 1.0)


# One message. A PanelContainer carries both the alternating wash and the left
# stripe — StyleBoxFlat's border_width_left IS the stripe, so no extra node.
func _make_row(text: String, opp: bool, index: int) -> Control:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, ROW_TINT_ALPHA if index % 2 == 1 else 0.0)
	box.content_margin_left   = ROW_PAD_X
	box.content_margin_right  = ROW_PAD_X
	box.content_margin_top    = ROW_PAD_Y
	box.content_margin_bottom = ROW_PAD_Y
	if opp:
		box.border_width_left = ROW_STRIPE_W
		box.border_color = MessageBoxTheme.chip_color(_theme_key, 0)
	else:
		# Keep the same left inset on your own rows so the text column doesn't
		# jog left and right as the turn changes.
		box.content_margin_left = ROW_PAD_X + float(ROW_STRIPE_W)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content    = true
	lbl.scroll_active  = false
	lbl.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_constant_override("line_separation", ROW_LINE_SPACING)
	lbl.add_theme_font_override("normal_font", _font)
	lbl.add_theme_font_override("bold_font",   _font_bold)
	lbl.add_theme_font_size_override("normal_font_size", ROW_FONT_SIZE)
	lbl.add_theme_font_size_override("bold_font_size",   ROW_FONT_SIZE)
	lbl.add_theme_color_override("default_color", Color(0, 0, 0, 1))
	lbl.text = text
	panel.add_child(lbl)

	return panel


# ============================================================
# SCROLLING
# ============================================================
# Opens on the newest entry. Two frames of settling are needed before the
# scroll maximum is known: one for the VBox to lay out its children, one for
# the ScrollContainer to pick up the new content height.
func scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_scroller):
		return
	_scroll_to_max()


# Returns true if the event was a scroll gesture and has been acted on, so the
# caller knows to consume it. Everything else is left alone.
func handle_scroll_input(event: InputEvent) -> bool:
	if not is_instance_valid(_scroller):
		return false

	var page: int = int(float(_scroller.size.y) * PAGE_FRACTION)

	if event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:   _scroll_by(-SCROLL_STEP); return true
			MOUSE_BUTTON_WHEEL_DOWN: _scroll_by(SCROLL_STEP);  return true

	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_UP:       _scroll_by(-SCROLL_STEP); return true
			KEY_DOWN:     _scroll_by(SCROLL_STEP);  return true
			KEY_PAGEUP:   _scroll_by(-page);        return true
			KEY_PAGEDOWN: _scroll_by(page);         return true
			KEY_HOME:     _scroller.scroll_vertical = 0; return true
			KEY_END:      _scroll_to_max();         return true

	return false


func _scroll_by(delta: int) -> void:
	_scroller.scroll_vertical = clampi(_scroller.scroll_vertical + delta, 0, _scroll_max())


func _scroll_to_max() -> void:
	_scroller.scroll_vertical = _scroll_max()


# A VScrollBar's max_value is the TOTAL content height, not the furthest the view
# can travel — the furthest is that minus one visible page. They are only the same
# thing when the content is exactly one page tall, so using max_value directly
# would let a short log scroll its own content off the top. ScrollContainer does
# clamp the assignment internally, but doing the sum here keeps _scroll_by()'s
# clamp honest rather than leaning on that.
func _scroll_max() -> int:
	var bar := _scroller.get_v_scroll_bar()
	if bar == null:
		return 0
	return maxi(0, int(bar.max_value - bar.page))


# ============================================================
# SHADER HELPERS
# ============================================================
# Same two helpers DynamicMessageBox uses. Duplicated rather than shared
# because they are four lines each and making them static on the box would put
# a panel-specific API on a class that has no business owning it.
func _make_shader_rect() -> ColorRect:
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _apply_shader(rect: ColorRect, col_l: Color, col_r: Color, fill: Color,
				   corner: float, solid: Vector2, fade: Vector2) -> void:
	var mat: ShaderMaterial = rect.material
	if mat == null:
		return
	mat.set_shader_parameter("color_left",    col_l)
	mat.set_shader_parameter("color_right",   col_r)
	mat.set_shader_parameter("fill_color",    fill)
	mat.set_shader_parameter("rect_size",     rect.size)
	mat.set_shader_parameter("corner_radius", corner)
	mat.set_shader_parameter("edge_solid",    solid)
	mat.set_shader_parameter("edge_fade",     fade)
