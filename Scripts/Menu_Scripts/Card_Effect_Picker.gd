extends Control

# ══════════════════════════════════════════════════════════════════════════════
# CARD EFFECT PICKER — the full-screen "EFFECTS" sub-panel of the card search.
# ══════════════════════════════════════════════════════════════════════════════
# Opened from the EFFECTS row on CardSearchOverlay. There are ~60 effect categories, far too many
# for one row of a screen that was already full, so the row is a single button plus a summary of
# what is picked, and the picking happens here: every category as an icon + label chip, grouped
# under section headers (the modern Yu-Gi-Oh "Genre" list, laid out as a grid so it needs no
# scrolling at 1080p).
#
#   MATCH ANY / ALL      ANY = card has at least one picked effect (the screen-wide OR-within-a-row
#                        rule, so it is the default); ALL = card has every picked effect.
#   FOUND ON             which part of the card the effect must be on: attacks, Powers/Bodies,
#                        Trainer/Special Energy text. At least one always stays on.
#
# The picker edits the overlay's own selection Dictionary IN PLACE (Dictionaries are references),
# and emits `changed` after every click so the overlay's summary row and SEARCH button keep up.
# DONE, Escape and pad B all just close it — there is nothing to cancel, the row shows the result.
#
# No class_name: preloaded by Card_Search_Overlay.gd (see Card_Effect_Tags.gd for why).
# ══════════════════════════════════════════════════════════════════════════════

signal changed()
signal closed()

const EffectTags = preload("res://Scripts/Global_Scripts/Card_Effect_Tags.gd")

# ── TWEAKABLE layout (1920x1080 base; the width follows the live screen) ──────
const PICKER_Z      := 300      # above the overlay's CONTENT_Z (250) and the deck's filter_border (200)
# Transparent: the search overlay hides its rows while the picker is open, so its own dimmed view of the
# deck's animated background shows through unchanged (no solid colour jump going in / out).
const BACKDROP      := Color(0.0, 0.0, 0.0, 0.0)
const SIDE_X        := 60.0     # left / right margin of the chip area
const TITLE_FONT    := 46
const HEADER_H      := 96.0
const CTRL_Y        := 104.0    # MATCH / FOUND ON row
const CTRL_LABEL_FONT := 20
const SECTIONS_TOP  := 166.0
const SECTION_FONT  := 18
const SECTION_H     := 28.0     # section header line
const SECTION_GAP   := 10.0     # space under the last chip line of a section
const CHIP_H        := 40.0
const CHIP_FONT     := 15
const CHIP_PAD_X    := 12.0
const CHIP_GAP_X    := 10.0
const CHIP_GAP_Y    := 8.0
const ICON_PX       := 26       # the badge drawn on each chip (art is 64px)
const DESC_FONT     := 20
const BTN_H         := 40.0
const BTN_FONT      := 15
const FOOT_BTN_W    := 320.0
const FOOT_BTN_H    := 56.0

var host : Control = null                 # the CardSearchOverlay (for its chip styling helpers)
var _sel : Dictionary = {}                # key -> true, shared with the overlay
var _state : Dictionary = {}              # {"mode": "any"/"all", "scope": int}, shared with the overlay
var _present : Dictionary = {}            # category keys that exist in the player's unlocked sets
var _counts : Dictionary = {}             # key -> cards in unlocked sets (for the description line)

var _chips : Dictionary = {}              # key -> Button
var _mode_btn : Dictionary = {}           # "any"/"all" -> Button
var _scope_btn : Dictionary = {}          # SRC bit -> Button
var _desc : Label = null
var _done_btn : Button = null
var _theme_white : Theme = null
var _theme_sel : Theme = null


## sel / state are the overlay's own Dictionaries — edited in place.
func setup(overlay: Control, sel: Dictionary, state: Dictionary, unlocked_sets: Array) -> void:
	host = overlay
	_sel = sel
	_state = state
	_theme_white = UIKit.button_theme("secondary")
	_theme_sel = UIKit.button_theme("selected")
	_counts = EffectTags.counts_in_sets(unlocked_sets)
	_present = _counts

	z_index = PICKER_Z
	# An explicit screen rect, no anchors: the overlay it sits in is not always laid out yet.
	position = Vector2.ZERO
	size = Vector2(UIKit.screen_w(), UIKit.screen_h())
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_build_header()
	_build_controls()
	var bottom := _build_sections()
	_build_footer(bottom)
	_refresh_all()


func focus_first() -> void:
	for k in _chips:
		(_chips[k] as Control).grab_focus()
		return


# ══════════════════════════════════════════════════════════════════════════════
# Build
# ══════════════════════════════════════════════════════════════════════════════

func _build_header() -> void:
	var title := Label.new()
	title.theme = _theme_white
	title.text = "CARD EFFECTS"
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.add_theme_color_override("font_color", UITheme.col("field_fg"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 0)
	title.size = Vector2(UIKit.screen_w(), HEADER_H)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var clear := Button.new()
	UIKit.style_button(clear, "negative")
	clear.text = "CLEAR EFFECTS"
	clear.add_theme_font_size_override("font_size", BTN_FONT)
	clear.position = Vector2(UIKit.screen_w() - 360.0, 21.0)
	clear.size = Vector2(300, 54)
	clear.custom_minimum_size = clear.size
	clear.pressed.connect(_on_clear_pressed)
	add_child(clear)


func _build_controls() -> void:
	var x := SIDE_X
	x = _ctrl_label("MATCH", x)
	for entry in [["any", "ANY OF THEM"], ["all", "ALL OF THEM"]]:
		var b := _make_btn(entry[1], x, CTRL_Y, 190.0)
		b.pressed.connect(_on_mode_pressed.bind(entry[0]))
		_mode_btn[entry[0]] = b
		x += 190.0 + 14.0
	x += 50.0
	x = _ctrl_label("FOUND ON", x)
	for entry in [[EffectTags.SRC_ATTACK, "ATTACKS"], [EffectTags.SRC_POWER, "POWERS & BODIES"],
			[EffectTags.SRC_CARD, "TRAINERS & ENERGY"]]:
		var b2 := _make_btn(entry[1], x, CTRL_Y, 230.0)
		b2.pressed.connect(_on_scope_pressed.bind(entry[0]))
		_scope_btn[entry[0]] = b2
		x += 230.0 + 14.0


func _ctrl_label(text: String, x: float) -> float:
	var l := Label.new()
	l.theme = _theme_white
	l.text = text
	l.add_theme_font_size_override("font_size", CTRL_LABEL_FONT)
	l.add_theme_color_override("font_color", UITheme.col("field_fg"))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(x, CTRL_Y)
	var w := UITheme.font("button").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CTRL_LABEL_FONT).x + 8.0
	l.size = Vector2(w, BTN_H)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return x + w + 14.0


## One section per group, in the order the categories come in. Returns the y under the last one.
func _build_sections() -> float:
	var groups : Array = []
	var by_group : Dictionary = {}
	for c in EffectTags.categories():
		var k := String(c["key"])
		if not _present.has(k):
			continue      # nothing in the player's unlocked sets has it — gated off like Baby / Tool
		var g := String(c["group"])
		if not by_group.has(g):
			by_group[g] = []
			groups.append(g)
		by_group[g].append(c)

	var y := SECTIONS_TOP
	var right := UIKit.screen_w() - SIDE_X
	for g in groups:
		_section_header(g, y)
		y += SECTION_H
		var x := SIDE_X
		for c in by_group[g]:
			var chip := _make_chip(c)
			var w := chip.size.x
			if x > SIDE_X and x + w > right:
				x = SIDE_X
				y += CHIP_H + CHIP_GAP_Y
			chip.position = Vector2(x, y)
			chip.pivot_offset = chip.size / 2.0
			x += w + CHIP_GAP_X
		y += CHIP_H + SECTION_GAP
	return y


func _section_header(group: String, y: float) -> void:
	var bar := ColorRect.new()
	bar.color = _group_colour(group)
	bar.position = Vector2(SIDE_X, y + 5)
	bar.size = Vector2(6, SECTION_H - 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var l := Label.new()
	l.theme = _theme_white
	l.text = String(EffectTags.GROUP_TITLES.get(group, group))
	l.add_theme_font_size_override("font_size", SECTION_FONT)
	l.add_theme_color_override("font_color", _group_colour(group).lightened(0.35))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(SIDE_X + 16, y - 2)
	l.size = Vector2(600, SECTION_H - 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


## Section accent colours — the same hues as the icon badges (effect_icon_build.py GROUP_COL).
func _group_colour(group: String) -> Color:
	match group:
		"DAMAGE":  return Color8(214, 72, 62)
		"DEFENCE": return Color8(52, 160, 92)
		"STATUS":  return Color8(138, 64, 180)
		"ENERGY":  return Color8(222, 150, 30)
		"CARDS":   return Color8(58, 118, 210)
		"BOARD":   return Color8(30, 150, 150)
		"RULES":   return Color8(122, 92, 196)
		"SYNERGY": return Color8(204, 86, 140)
		"VERSUS":  return Color8(132, 150, 44)
	return Color.GRAY


func _make_chip(c: Dictionary) -> Button:
	var key := String(c["key"])
	var label := String(c["label"])
	var chip := Button.new()
	chip.text = label
	chip.icon = EffectTags.icon(key, ICON_PX)
	chip.custom_minimum_size = Vector2(0, CHIP_H)
	chip.size = Vector2(_chip_width(label), CHIP_H)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.tooltip_text = String(c.get("desc", label))
	chip.set_meta("key", key)
	UIKit.make_nav_tile(chip, true)
	_style_chip(chip, false)
	chip.gui_input.connect(_on_chip_input.bind(key))
	chip.mouse_entered.connect(_show_desc.bind(key))
	chip.mouse_exited.connect(_show_desc.bind(""))
	add_child(chip)
	_chips[key] = chip
	return chip


func _chip_width(text: String) -> float:
	var f: Font = UITheme.font("button")
	return f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT).x \
		+ CHIP_PAD_X * 2.0 + ICON_PX + 8.0


func _style_chip(chip: Button, selected: bool) -> void:
	# The overlay's helper, so these chips are EXACTLY the search screen's chips (same faces, same
	# #179 padding fix, same pink selected state) — just with an icon on the left.
	if host != null and host.has_method("_apply_chip_style"):
		host._apply_chip_style(chip, "selected" if selected else "secondary")
	else:
		UIKit.style_button(chip, "selected" if selected else "secondary")
	chip.add_theme_font_size_override("font_size", CHIP_FONT)
	chip.add_theme_constant_override("h_separation", 8)
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT


func _make_btn(text: String, x: float, y: float, w: float) -> Button:
	var b := Button.new()
	b.theme = _theme_white
	b.text = text
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.add_theme_font_size_override("font_size", BTN_FONT)
	b.position = Vector2(x, y)
	b.size = Vector2(w, BTN_H)
	b.custom_minimum_size = Vector2(w, BTN_H)
	if host != null and host.has_method("_tighten"):
		host._tighten(b, 10.0, 5.0)
	add_child(b)
	return b


func _build_footer(sections_bottom: float) -> void:
	# Description strip: what the chip under the cursor does, and how many unlocked cards have it.
	var desc_y := maxf(sections_bottom + 6.0, UIKit.screen_h() - 150.0)
	_desc = Label.new()
	_desc.theme = _theme_white
	_desc.add_theme_font_size_override("font_size", DESC_FONT)
	_desc.add_theme_color_override("font_color", UITheme.col("field_fg"))
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_desc.position = Vector2(SIDE_X, desc_y)
	_desc.size = Vector2(UIKit.screen_w() - SIDE_X * 2.0, 40)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)

	_done_btn = Button.new()
	UIKit.style_button(_done_btn, "primary")
	_done_btn.text = "DONE"
	_done_btn.add_theme_font_size_override("font_size", BTN_FONT)
	_done_btn.size = Vector2(FOOT_BTN_W, FOOT_BTN_H)
	_done_btn.custom_minimum_size = _done_btn.size
	_done_btn.position = Vector2((UIKit.screen_w() - FOOT_BTN_W) * 0.5, UIKit.screen_h() - 76.0)
	_done_btn.pressed.connect(close)
	add_child(_done_btn)
	if sections_bottom > desc_y:
		push_warning("CardEffectPicker: chips overrun the description strip by %d px" % int(sections_bottom - desc_y))


# ══════════════════════════════════════════════════════════════════════════════
# Input
# ══════════════════════════════════════════════════════════════════════════════

func _on_chip_input(event: InputEvent, key: String) -> void:
	# Mouse WHEEL is also an InputEventMouseButton — check the button index (ISSUE #102 rule).
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var on := not _sel.has(key)
	if on:
		_sel[key] = true
	else:
		_sel.erase(key)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select if on else SoundManagerScript.SFX_minus_select)
	_style_chip(_chips[key], on)
	_show_desc(key)
	changed.emit()


func _on_mode_pressed(mode: String) -> void:
	if String(_state.get("mode", "any")) == mode:
		return
	_state["mode"] = mode
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_refresh_controls()
	changed.emit()


func _on_scope_pressed(bit: int) -> void:
	var scope := int(_state.get("scope", EffectTags.SRC_ALL))
	var next := scope ^ bit
	if next == 0:
		# The last one on stays on — an effect found on nothing is no search at all.
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return
	_state["scope"] = next
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select if (next & bit) else SoundManagerScript.SFX_minus_select)
	_refresh_controls()
	changed.emit()


func _on_clear_pressed() -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_sel.clear()
	_state["mode"] = "any"
	_state["scope"] = EffectTags.SRC_ALL
	_refresh_all()
	changed.emit()


func close() -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	closed.emit()


# ══════════════════════════════════════════════════════════════════════════════
# Visuals
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_all() -> void:
	for k in _chips:
		_style_chip(_chips[k], _sel.has(k))
	_refresh_controls()
	_show_desc("")


func _refresh_controls() -> void:
	var mode := String(_state.get("mode", "any"))
	for m in _mode_btn:
		_set_btn(_mode_btn[m], m == mode)
	var scope := int(_state.get("scope", EffectTags.SRC_ALL))
	for bit in _scope_btn:
		_set_btn(_scope_btn[bit], (scope & int(bit)) != 0)


func _set_btn(b: Button, on: bool) -> void:
	b.theme = _theme_sel if on else _theme_white
	if host != null and host.has_method("_tighten"):
		host._tighten(b, 10.0, 5.0)


func _show_desc(key: String) -> void:
	if _desc == null:
		return
	if key == "":
		var n := _sel.size()
		if n == 0:
			_desc.text = "Pick one or more effects.  Hover a chip to see what it covers."
		else:
			_desc.text = "%d effect%s picked  -  cards must have %s" % [n, "" if n == 1 else "s",
				"ALL of them" if String(_state.get("mode", "any")) == "all" else "ANY of them"]
		return
	var c := EffectTags.category(key)
	_desc.text = "%s  -  %s" % [String(c.get("label", key)).to_upper(), String(c.get("desc", ""))]
