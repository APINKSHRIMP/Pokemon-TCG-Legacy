class_name SchedulePickerOverlay
extends CanvasLayer

## The day / time-of-day grid behind the character editor's SCHEDULE button. Debug
## tooling: CharacterEditor is the only thing that opens it.
##
## The map files describe a schedule as a days spec plus a times string --
## `"days": "2-8/2", "times": "M,A"` -- which is compact to store and genuinely hard
## to read. This is the same information as a grid: one row per day, one column per
## time of day, tick the slots the character is there for.
##
## A character can be present in slots that no single days/times pair describes
## ("day 2 mornings, day 3 evenings"), which is exactly why 247 of the 344 when-rules
## in the data carry nothing but days and times. So the grid does not hand back one
## pair -- it hands back a LIST of them, grouped so that every day sharing a set of
## times becomes one slot. CharacterEditor writes each slot as a when-rule.
##
##   click a cell          toggle one day / time
##   click a column head   toggle that time on every day
##   click a day number    toggle that day's four times
##   Enter                 done
##   Escape                cancel

signal picked(slots: Array)
signal cancelled

const TIME_ORDER := ["M", "A", "E", "N"]
const TIME_NAMES := {"M": "MORNING", "A": "AFTERNOON", "E": "EVENING", "N": "NIGHT"}

# ---- tweakables -------------------------------------------------------------
## One pale colour per column, so a row of ticks is read as a shape rather than as
## four identical boxes. Saturated when ticked, greyed when it belongs elsewhere.
const COLUMN_COLOURS := {
	"M": Color(0.76, 0.88, 0.96),
	"A": Color(0.99, 0.95, 0.74),
	"E": Color(0.99, 0.85, 0.69),
	"N": Color(0.94, 0.84, 0.95),
}
## How much darker a ticked cell is than an empty one.
const TICKED_DARKEN := 0.30
const HOVER_DARKEN := 0.10
## Cells owned by another variant of the same character. Shown, not editable here.
const OTHER_VARIANT := Color(0.55, 0.55, 0.60)
## Days before the map opens. Darker than every live plate, so a closed stretch
## reads as absent rather than as an empty but usable row.
const CLOSED_DAY := Color(0.26, 0.26, 0.30)

const DAY_COL_W := 230
const TIME_COL_W := 200
const ROW_H := 38
const HEAD_H := 44
const GRID_LINE := Color(0.10, 0.10, 0.13)
## Left padding on the day column, so a day number is not against the grid line.
const DAY_PAD := 16
## The cell tick, in pixels: box outline thickness and stroke width included.
const TICK_SIZE := 22
const TICK_BORDER := 2
const TICK_WIDTH := 2.6

const FONT_SIZE := 20
const TITLE_FONT_SIZE := 30
const MARGIN := 40
const GRID_TOP := 150
## Everything below this belongs to the legend, the status line and the buttons.
const GRID_BOTTOM := 892
# -----------------------------------------------------------------------------

## Row key for "every day", which is what an absent or empty `days` spec means.
## Well outside any real day so it can share one marks dictionary with them.
const EVERY_DAY := -1000

static var _tick_on: Texture2D = null

## "day|letter" -> true, for the slots this variant owns. The only editable state.
var _marks: Dictionary = {}
## "day|letter" -> rule index, for slots owned by another variant of the character.
var _others: Dictionary = {}
## "day|letter" -> Button.
var _cells: Dictionary = {}
var _day_rows: Array = []
var _max_day: int = 12
var _authored_through: int = 0
## The first day this map is reachable. Days before it are shown but locked --
## a character authored there stands in an area the player cannot walk into.
var _opens: int = 1
var _scope: String = ""
var _heading: String = "SCHEDULE"

var _grid: GridContainer = null
var _status: Label = null
var _done_btn: Button = null
var _closing: bool = false


# ============================================================
# SETUP
# ============================================================

## `slots` and `others` are both arrays of {days, times} -- the first editable here,
## the second shown as context only. `others` entries may also carry "rule" for the
## tooltip. `calendar` is the map file's calendar block, used for the footnote about
## which days the loop generates.
func setup(slots: Array, others: Array, calendar: Dictionary, heading: String,
		scope: String) -> void:
	_heading = heading
	_scope = scope
	_authored_through = int(calendar.get("authored_through", 0))
	_opens = maxi(1, int(calendar.get("opens", 1)))

	# The grid has to be tall enough to hold every day anything already refers to.
	# Capping it at authored_through would silently drop a "5-12" spec on a map
	# authored through 8 the first time somebody opened this on that character.
	_max_day = maxi(12, _authored_through)
	for slot in slots + others:
		_max_day = maxi(_max_day, max_day_in_spec(str(slot.get("days", ""))))
	_max_day = clampi(_max_day, 4, 60)

	_day_rows = [EVERY_DAY]
	for day in range(0, _max_day + 1):
		_day_rows.append(day)

	for slot in slots:
		for key in _slot_keys(slot):
			_marks[key] = true
	for slot in others:
		var owner_rule := int(slot.get("rule", -1))
		for key in _slot_keys(slot):
			# A slot this variant owns wins the cell: it is the one you can edit.
			if not _marks.has(key):
				_others[key] = owner_rule

	layer = 130
	_build_ui()
	_refresh()


## What the EVERY DAY row writes. On a map that opens on day 1 that is no day list
## at all, the spelling every existing character already uses. On a map that opens
## later it has to be the live window instead: an empty spec means day 1, which
## would stand the character in the map before the player can reach it.
func _every_day_spec() -> String:
	if _opens <= 1:
		return ""
	var last: int = maxi(_authored_through, _opens)
	return str(_opens) if last == _opens else "%d-%d" % [_opens, last]


## Every "day|letter" key one {days, times} slot covers.
func _slot_keys(slot: Dictionary) -> Array:
	var days_spec := str(slot.get("days", "")).strip_edges()
	var letters := parse_times(str(slot.get("times", "")))
	var keys: Array = []
	if days_spec == "" or days_spec == "*" or days_spec == _every_day_spec():
		for letter in letters:
			keys.append(_key(EVERY_DAY, str(letter)))
		return keys
	for day in range(0, _max_day + 1):
		if CharacterSchedule.days_match(days_spec, day):
			for letter in letters:
				keys.append(_key(day, str(letter)))
	return keys


static func _key(day: int, letter: String) -> String:
	return "%d|%s" % [day, letter]


## The letters a times string names, in M A E N order. An empty spec means every
## time of day, exactly as CharacterSchedule.times_match reads it.
static func parse_times(spec: String) -> Array:
	var text := spec.strip_edges()
	if text == "" or text == "*":
		return TIME_ORDER.duplicate()
	var out: Array = []
	for letter in TIME_ORDER:
		if text.contains(str(letter)):
			out.append(str(letter))
	return out


## The highest day number a days spec mentions, so the grid can be built tall enough
## to show it. 0 for an empty spec -- "every day" is its own row.
static func max_day_in_spec(spec: String) -> int:
	var top := 0
	for raw in spec.split(","):
		var part := str(raw).strip_edges()
		var slash := part.find("/")
		if slash != -1:
			part = part.substr(0, slash)
		var dash := part.find("-", 1)
		if dash != -1:
			part = part.substr(dash + 1)
		part = part.strip_edges()
		if part.is_valid_int():
			top = maxi(top, int(part))
	return top


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = DebugFormTheme.BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so nothing behind the picker -- the form, or the map itself --
	# reacts to a click aimed at a cell.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.theme = DebugFormTheme.build()
	add_child(dim)

	var grid_w: int = DAY_COL_W + TIME_COL_W * TIME_ORDER.size()
	# Room for the scrollbar on a long calendar, so the last column is never clipped.
	var total_w: int = grid_w + DebugFormTheme.SCROLLBAR_THICKNESS
	# Everything above the table lines up with its left edge, so the heading, the
	# quick buttons and the grid read as one column rather than three loose pieces.
	var left: int = int((1920 - total_w) / 2.0)
	# Only as tall as the days actually need. A twelve-day map otherwise left three
	# hundred pixels of empty backdrop between the table and the buttons, which reads
	# as a page that failed to finish drawing rather than as a short table.
	var grid_h: int = mini(HEAD_H + _day_rows.size() * ROW_H, GRID_BOTTOM - GRID_TOP)

	var title := Label.new()
	title.text = _heading
	title.position = Vector2(left, 24)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	dim.add_child(title)

	var scope := Label.new()
	scope.text = _scope
	scope.position = Vector2(left, 66)
	scope.size = Vector2(1920 - left - MARGIN, 30)
	scope.clip_text = true
	scope.add_theme_font_size_override("font_size", FONT_SIZE)
	scope.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0))
	dim.add_child(scope)

	var quick := HBoxContainer.new()
	quick.position = Vector2(left, 102)
	quick.add_theme_constant_override("separation", 12)
	dim.add_child(quick)
	quick.add_child(_quick_button("EVERY DAY, ALL TIMES", func(): _set_all(true)))
	quick.add_child(_quick_button("CLEAR ALL", func(): _set_all(false)))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(left, GRID_TOP)
	scroll.size = Vector2(total_w, grid_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dim.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 1 + TIME_ORDER.size()
	# No separation: the cells butt together and their own one-pixel borders draw the
	# grid lines, which is what makes a block of ticks read as a block.
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(_grid)
	_build_rows()

	var footer: int = GRID_TOP + grid_h + 18

	var legend := Label.new()
	legend.text = "coloured = this character is here     grey = another variant of this character, edited by opening the form on a day it appears     EVERY DAY covers a whole column"
	legend.position = Vector2(left, footer)
	legend.size = Vector2(1920 - left - MARGIN, 28)
	legend.clip_text = true
	legend.add_theme_font_size_override("font_size", FONT_SIZE - 2)
	legend.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
	dim.add_child(legend)

	if _authored_through > 0:
		var note := Label.new()
		note.text = "this map is authored through day %d -- later days repeat out of the calendar loop, so there is nothing to author past it" % _authored_through
		if _opens > 1:
			note.text = "this map opens on day %d and is authored through day %d -- earlier days are locked, and later ones repeat out of the calendar loop" 					% [_opens, _authored_through]
		note.position = Vector2(left, footer + 26)
		note.size = Vector2(1920 - left - MARGIN, 28)
		note.clip_text = true
		note.add_theme_font_size_override("font_size", FONT_SIZE - 2)
		note.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
		dim.add_child(note)

	_status = Label.new()
	_status.position = Vector2(MARGIN, 1080 - MARGIN - 48)
	_status.size = Vector2(1340 - MARGIN, 48)
	_status.clip_text = true
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	dim.add_child(_status)

	# The two buttons stay pinned to the bottom right of the screen whatever the
	# table's height, so they are always in the same place to reach for.
	_done_btn = Button.new()
	_done_btn.text = "DONE"
	_done_btn.position = Vector2(1400, 1080 - MARGIN - 48)
	_done_btn.size = Vector2(220, 48)
	_done_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_done_btn.pressed.connect(_confirm)
	dim.add_child(_done_btn)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.position = Vector2(1640, 1080 - MARGIN - 48)
	cancel.size = Vector2(220, 48)
	cancel.add_theme_font_size_override("font_size", FONT_SIZE)
	cancel.pressed.connect(_cancel)
	dim.add_child(cancel)


func _quick_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", FONT_SIZE - 2)
	button.pressed.connect(action)
	return button


func _build_rows() -> void:
	_grid.add_child(_header_cell("DAY", Vector2(DAY_COL_W, HEAD_H), Color(0.82, 0.82, 0.88)))
	for letter in TIME_ORDER:
		var head := _header_cell(str(TIME_NAMES[letter]), Vector2(TIME_COL_W, HEAD_H),
				COLUMN_COLOURS[letter])
		head.pressed.connect(_toggle_column.bind(str(letter)))
		head.tooltip_text = "tick or clear %s on every day" % str(TIME_NAMES[letter]).to_lower()
		_grid.add_child(head)

	for day in _day_rows:
		var label := _day_label(int(day))
		label.pressed.connect(_toggle_row.bind(int(day)))
		_grid.add_child(label)
		for letter in TIME_ORDER:
			var cell := _make_cell(int(day), str(letter))
			_cells[_key(int(day), str(letter))] = cell
			_grid.add_child(cell)


func _header_cell(text: String, size: Vector2, colour: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, DebugFormTheme.INK)
	_paint(button, colour.darkened(0.12), colour.darkened(0.24), colour.darkened(0.24))
	return button


func _day_label(day: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(DAY_COL_W, ROW_H)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	var ink := DebugFormTheme.INK
	if day == EVERY_DAY:
		button.text = "EVERY DAY"
		button.tooltip_text = "here every day at these times -- writes no day list at all" 				if _opens <= 1 else 				"here every day the map is open, at these times -- writes days %s" % _every_day_spec()
	elif day == 0:
		button.text = "0   (test day)"
		button.tooltip_text = "the debug test day, reached with the [ key"
	else:
		button.text = str(day)
		if day < _opens:
			ink = DebugFormTheme.INK_DIM
			button.tooltip_text = "this map does not open until day %d" % _opens
		elif _authored_through > 0 and day > _authored_through:
			# Authoring past authored_through is dead weight: resolve_day() folds those
			# days back into the loop block before the cast is ever read.
			ink = DebugFormTheme.INK_DIM
			button.tooltip_text = "past the map's authored days -- the calendar loop already covers day %d" % day
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	var plate := Color(0.80, 0.87, 0.80) if day == EVERY_DAY else Color(0.88, 0.88, 0.92)
	_paint(button, plate, plate.darkened(HOVER_DARKEN), plate.darkened(HOVER_DARKEN),
			Color(0, 0, 0, 0), DAY_PAD)
	return button


func _make_cell(day: int, letter: String) -> Button:
	var pale: Color = COLUMN_COLOURS[letter]
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(TIME_COL_W, ROW_H)
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The tick is already drawn in ink, so it must NOT be modulated. The theme tints
	# a Button's icon towards INK, which on an already-dark image is a black square.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color"]:
		button.add_theme_color_override(state, Color(1, 1, 1))
	# A tick that belongs to another variant, or to the EVERY DAY row, is faded --
	# it says "here, but not yours to change".
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.42))
	_paint(button, pale, pale.darkened(HOVER_DARKEN), pale.darkened(TICKED_DARKEN))
	button.toggled.connect(func(on: bool): _on_cell_toggled(day, letter, on))
	return button


## The four states a cell can be drawn in. `disabled` doubles as the "belongs to
## something else" plate, so it is painted rather than left on the theme's grey.
func _paint(button: Button, normal: Color, hover: Color, pressed: Color,
		disabled: Color = Color(0, 0, 0, 0), pad_left: int = 0) -> void:
	button.add_theme_stylebox_override("normal", _plate(normal, pad_left))
	button.add_theme_stylebox_override("hover", _plate(hover, pad_left))
	button.add_theme_stylebox_override("pressed", _plate(pressed, pad_left))
	button.add_theme_stylebox_override("hover_pressed", _plate(pressed, pad_left))
	button.add_theme_stylebox_override("disabled",
			_plate(disabled if disabled.a > 0.0 else normal, pad_left))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _plate(bg: Color, pad_left: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = GRID_LINE
	sb.content_margin_left = pad_left
	return sb


## One shared tick -- a boxed check, drawn dark.
##
## DebugFormTheme's check box is deliberately the other way round: a white outline
## round a dark well, which is what reads on the near-black form backdrop. Tinting
## that for a pale cell turns it into a black square, because modulation multiplies
## and the well was already dark. So the grid draws its own.
##
## Drawn once and shared: sixty cells is sixty redundant images otherwise.
static func _tick() -> Texture2D:
	if _tick_on != null:
		return _tick_on
	var size := TICK_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			if x < TICK_BORDER or y < TICK_BORDER \
					or x >= size - TICK_BORDER or y >= size - TICK_BORDER:
				img.set_pixel(x, y, DebugFormTheme.INK)
	_stroke(img, Vector2(0.26, 0.50) * size, Vector2(0.44, 0.72) * size)
	_stroke(img, Vector2(0.44, 0.72) * size, Vector2(0.78, 0.28) * size)
	_tick_on = ImageTexture.create_from_image(img)
	return _tick_on


## One antialiased stroke of the tick. Box and tick are the same colour, so
## compositing is just "keep whichever alpha is higher".
static func _stroke(img: Image, a: Vector2, b: Vector2) -> void:
	var ab := b - a
	var length_squared := ab.length_squared()
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x, y)
			var t := 0.0 if length_squared == 0.0 else clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
			var d := p.distance_to(a + ab * t) - TICK_WIDTH * 0.5
			if d >= 0.5:
				continue
			var alpha := maxf(clampf(0.5 - d, 0.0, 1.0), img.get_pixel(x, y).a)
			img.set_pixel(x, y, Color(DebugFormTheme.INK.r, DebugFormTheme.INK.g,
					DebugFormTheme.INK.b, alpha))


# ============================================================
# EDITING
# ============================================================

func _on_cell_toggled(day: int, letter: String, on: bool) -> void:
	_set_mark(day, letter, on)
	_refresh()


## The column head and the day number are bulk toggles: they turn the whole line ON
## unless it is already fully on, in which case they clear it. One button, both jobs,
## and no state to remember.
func _toggle_column(letter: String) -> void:
	var all_on := true
	for day in _day_rows:
		if int(day) == EVERY_DAY:
			continue
		if _editable(int(day), letter) and not _marks.has(_key(int(day), letter)):
			all_on = false
			break
	for day in _day_rows:
		if int(day) != EVERY_DAY and _editable(int(day), letter):
			_set_mark(int(day), letter, not all_on)
	_refresh()


func _toggle_row(day: int) -> void:
	var all_on := true
	for letter in TIME_ORDER:
		if _editable(day, str(letter)) and not _marks.has(_key(day, str(letter))):
			all_on = false
			break
	for letter in TIME_ORDER:
		if _editable(day, str(letter)):
			_set_mark(day, str(letter), not all_on)
	_refresh()


func _set_all(on: bool) -> void:
	_marks.clear()
	if on:
		for letter in TIME_ORDER:
			if _editable(EVERY_DAY, str(letter)):
				_marks[_key(EVERY_DAY, str(letter))] = true
	_refresh()


func _set_mark(day: int, letter: String, on: bool) -> void:
	if on:
		_marks[_key(day, letter)] = true
	else:
		_marks.erase(_key(day, letter))


## A cell another variant owns is not editable here, for the same reason the rest of
## the form only edits the variant you are standing in front of: the other variant
## has its own dialogue and its own position, and this form is not showing them.
func _editable(day: int, letter: String) -> bool:
	if _others.has(_key(day, letter)):
		return false
	# Day 0 is the debug test day and belongs to no calendar, so it stays open.
	if day != EVERY_DAY and day > 0 and day < _opens:
		return false
	# A column the EVERY DAY row claims is already covered on every day. The marks
	# underneath are kept, not cleared, so unticking the EVERY DAY cell brings the
	# original days back rather than leaving an empty column.
	return day == EVERY_DAY or not _marks.has(_key(EVERY_DAY, letter))


# ============================================================
# RENDERING
# ============================================================

func _refresh() -> void:
	for day in _day_rows:
		for letter in TIME_ORDER:
			var key := _key(int(day), str(letter))
			var cell: Button = _cells[key]
			var covered: bool = int(day) != EVERY_DAY \
					and _marks.has(_key(EVERY_DAY, str(letter)))
			var other: bool = _others.has(key)
			var closed: bool = int(day) != EVERY_DAY and int(day) > 0 					and int(day) < _opens
			# A cell is ticked whether the slot is this variant's, another variant's,
			# or inherited from the EVERY DAY row -- the tick says "the character is
			# here", and the plate colour says whose it is to change.
			var on: bool = _marks.has(key) or covered or other
			# set_pressed_no_signal, or repainting the grid would re-enter
			# _on_cell_toggled for every cell it touched.
			cell.set_pressed_no_signal(on)
			cell.icon = _tick() if on else null
			cell.disabled = other or covered or closed
			if closed and not other:
				cell.set_pressed_no_signal(false)
				cell.icon = null
				cell.tooltip_text = "the map does not open until day %d" % _opens
				_paint(cell, CLOSED_DAY, CLOSED_DAY, CLOSED_DAY, CLOSED_DAY)
				continue
			if other:
				var rule: int = int(_others[key])
				cell.tooltip_text = "another variant of this character is here" \
						+ ("   (when-rule #%d)" % rule if rule >= 0 else "")
				_paint(cell, OTHER_VARIANT, OTHER_VARIANT, OTHER_VARIANT,
						OTHER_VARIANT.darkened(0.08))
			else:
				var pale: Color = COLUMN_COLOURS[str(letter)]
				cell.tooltip_text = "covered by the EVERY DAY row" if covered else ""
				_paint(cell, pale, pale.darkened(HOVER_DARKEN), pale.darkened(TICKED_DARKEN),
						pale.darkened(TICKED_DARKEN) if covered else pale)
	_refresh_status()


func _refresh_status() -> void:
	var slots := build_slots()
	if slots.is_empty():
		_status.text = "nothing ticked -- a character with no slots would never appear"
		_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
		_done_btn.disabled = true
		return
	_done_btn.disabled = false
	_status.text = "%d slot(s):   %s" % [slots.size(), summarise(slots)]
	_status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))


# ============================================================
# READING THE GRID BACK
# ============================================================

## The ticked cells as {days, times} slots: every day sharing a set of times becomes
## one slot, which is the shape the map file stores. Times ticked on the EVERY DAY row
## become a slot with no day list at all, and are left out of the numbered rows --
## "every day" already includes them.
func build_slots() -> Array:
	var every := ""
	for letter in TIME_ORDER:
		if _marks.has(_key(EVERY_DAY, str(letter))):
			every += str(letter)

	# Dictionaries keep insertion order, so the slots come out in day order.
	var by_mask: Dictionary = {}
	for day in _day_rows:
		if int(day) == EVERY_DAY:
			continue
		var mask := ""
		for letter in TIME_ORDER:
			if every.contains(str(letter)):
				continue
			if _marks.has(_key(int(day), str(letter))):
				mask += str(letter)
		if mask == "":
			continue
		if not by_mask.has(mask):
			by_mask[mask] = []
		by_mask[mask].append(int(day))

	var slots: Array = []
	for mask in by_mask:
		slots.append({"days": compress_days(by_mask[mask]), "times": spaced(str(mask))})
	if every != "":
		slots.append({"days": _every_day_spec(), "times": spaced(every)})
	return slots


## "MAE" -> "M,A,E", the spelling every times value in the data already uses.
static func spaced(mask: String) -> String:
	var out: Array = []
	for letter in TIME_ORDER:
		if mask.contains(str(letter)):
			out.append(str(letter))
	return ",".join(out)


## A day list as the shortest spec that means it: consecutive days collapse to
## "lo-hi", evenly spaced ones to "lo-hi/step", and anything else stays a number.
##
## Reproducing the existing spellings matters -- every days spec across the eight
## character files round-trips through here unchanged, so saving a character whose
## schedule you did not touch leaves no diff.
static func compress_days(days: Array) -> String:
	var sorted: Array = days.duplicate()
	sorted.sort()
	var parts: Array = []
	var i := 0
	while i < sorted.size():
		var best_step := 0
		var best_len := 1
		for step in [1, 2]:
			var run := 1
			while i + run < sorted.size() and int(sorted[i + run]) == int(sorted[i]) + int(step) * run:
				run += 1
			# A pair is worth writing as a range; a pair two apart is not -- "5,7" is
			# shorter than "5-7/2" and reads better.
			var needed: int = 2 if int(step) == 1 else 3
			if run >= needed and run > best_len:
				best_len = run
				best_step = int(step)
		if best_step == 0:
			parts.append(str(int(sorted[i])))
			i += 1
			continue
		var lo := int(sorted[i])
		var hi := int(sorted[i + best_len - 1])
		parts.append("%d-%d" % [lo, hi] if best_step == 1 else "%d-%d/%d" % [lo, hi, best_step])
		i += best_len
	return ",".join(parts)


## One line describing a slot list, for the button that opens this and for the status
## line inside it.
static func summarise(slots: Array) -> String:
	var parts: Array = []
	for slot in slots:
		var days := str(slot.get("days", "")).strip_edges()
		var times := str(slot.get("times", "")).replace(",", "")
		if times == "":
			times = "MAEN"
		parts.append("%s  %s" % ["every day" if days == "" else days, times])
	return "   +   ".join(parts)


## The same list spelled out, for a tooltip -- "days 3-8:  Morning, Afternoon".
static func summarise_long(slots: Array) -> String:
	var lines: Array = []
	for slot in slots:
		var days := str(slot.get("days", "")).strip_edges()
		var names: Array = []
		for letter in parse_times(str(slot.get("times", ""))):
			names.append(str(TIME_NAMES[letter]).capitalize())
		lines.append("%s:  %s" % ["every day" if days == "" else "days " + days,
				", ".join(names)])
	return "\n".join(lines)


# ============================================================
# INPUT / EXIT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# This sits above the character editor and the placement tool, both of which take
	# keys in _input(). Escape and Enter are consumed so they cannot also close the
	# form behind, or save the map file.
	match event.keycode:
		KEY_ESCAPE:
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		_:
			return
	get_viewport().set_input_as_handled()


func _confirm() -> void:
	if _closing:
		return
	var slots := build_slots()
	if slots.is_empty():
		return
	_closing = true
	picked.emit(slots)
	queue_free()


func _cancel() -> void:
	if _closing:
		return
	_closing = true
	cancelled.emit()
	queue_free()
