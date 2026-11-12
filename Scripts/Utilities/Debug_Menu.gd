class_name DebugMenu
extends CanvasLayer

## The DEL-key developer menu: one screen of buttons for everything that used to be a
## separate overworld debug key, plus the name cheats. Debug builds only -- MapManager
## only opens it behind DebugMode.is_enabled(), on overworld map scenes.
##
## Nothing from inside matches lives here (draw, shuffle, instant win / loss); those
## stay on their keys in the match itself.
##
## Buttons that leave the map as it is (cash, defeated count, cheats) keep the menu
## open and update the status lines. Buttons that reload the map or hand over to
## another tool (time, date, TEST match, placement) close it first, via MapManager.
##
##   DEL / Escape   close (DEL still deletes text while a text box has focus)

# ---- tweakables -------------------------------------------------------------
const TITLE_FONT_SIZE := 32
const HEADING_FONT_SIZE := 19
const FONT_SIZE := 19
const NOTE_FONT_SIZE := 16
const MARGIN := 48
const COLUMN_WIDTH := 500
const COLUMN_GAP := 28
const ROW_GAP := 8
const BUTTON_HEIGHT := 44
const SCROLL_TOP := 112
const STATUS_HEIGHT := 48
## Highest day the date picker offers. Day 0 is the match-effects test day.
const MAX_DATE := 99
## Above the placement tool (128) and its forms (129).
const LAYER := 130
const HEADING_COLOUR := DebugFormTheme.HEADING
const INFO_COLOUR := DebugFormTheme.INK
const NOTE_COLOUR := DebugFormTheme.INK_DIM
const GOOD_COLOUR := DebugFormTheme.SUCCESS
const WARN_COLOUR := DebugFormTheme.WARN
const BAD_COLOUR := Color(1.0, 0.45, 0.45)
## Each name cheat as a readable button: [label, what it does]. Codes missing here fall
## back to a tidied version of the code itself.
const CHEAT_NAMES := {
	"CHT.All_Cards_1": ["Own every Base, Gym and promo card", "base1-5, gym1-2, basep, si1"],
	"CHT.All_Cards_2": ["Own every Neo and e-Card card", "neo1-4, ecard1-3, np"],
	"CHT.All_Cards_3": ["Own every early EX card", "ex1 to ex8"],
	"CHT.All_Cards_4": ["Own every later EX and POP card", "ex9 to ex16, pop1-5"],
	"CHT.Gimme_Cash": ["Max out cash", ""],
	"CHT.Add_Starter_Set": ["Add the starter card set", ""],
	"CHT.Add_Shop_Set": ["Add the shop card set", ""],
	"CHT.Remove_All_Cards": ["Remove every card", "Can't be undone. Asks twice."],
	"CHT.All_Coins": ["Unlock every coin", ""],
	"CHT.All_Costumes": ["Unlock every costume", ""],
	"CHT.All_Sleeves": ["Unlock every sleeve", ""],
	"CHT.All_Energy_Styles": ["Unlock every Energy style", ""],
	"CHT_Retreat.Confused": ["Confusion: fairer retreat rule", "Retreating while Confused always works"],
	"CHT_Vanilla.Confusion": ["Confusion: original rule", "Undoes the fairer retreat rule"],
}
## Cheats that throw progress away need a second click.
const CONFIRM_CODES := ["CHT.Remove_All_Cards"]
# -----------------------------------------------------------------------------

var _state_label: Label = null
var _status: Label = null
var _date_spin: SpinBox = null
var _cash_edit: LineEdit = null
var _fish_coin_edit: LineEdit = null
var _fish_sent_edit: LineEdit = null
var _clock_edit: LineEdit = null
var _points_edit: LineEdit = null
## The main page of columns, and the CUTSCENES sub-page that replaces it while open.
var _main_page: ScrollContainer = null
var _cutscene_page: ScrollContainer = null
## The confirm-first cheat that has had its first click.
var _armed_code: String = ""
var _column_width: float = COLUMN_WIDTH


func _ready() -> void:
	layer = LAYER
	_build()
	_refresh_state()


# ============================================================
# BUILD
# ============================================================

func _build() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var root := ColorRect.new()
	root.color = DebugFormTheme.BACKDROP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = DebugFormTheme.build()
	add_child(root)

	# Header: title, the save's live numbers, and a close button.
	var header := HBoxContainer.new()
	header.position = Vector2(MARGIN, 24)
	header.custom_minimum_size = Vector2(screen.x - MARGIN * 2, 0)
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	var title := _label("Debug menu", TITLE_FONT_SIZE)
	header.add_child(title)
	_state_label = _label("", FONT_SIZE, INFO_COLOUR)
	_state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_state_label)
	var close := DebugFormTheme.button("Close", func(): MapManager.close_debug_menu(), "Del or Esc", "", FONT_SIZE)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size = Vector2(130, BUTTON_HEIGHT)
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(MARGIN, SCROLL_TOP)
	scroll.size = Vector2(screen.x - MARGIN * 2, screen.y - SCROLL_TOP - STATUS_HEIGHT - 40)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_main_page = scroll
	_cutscene_page = _build_cutscene_page(root, scroll.size)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	scroll.add_child(columns)
	# Three columns share the screen's width (cards add 32 px of padding each).
	_column_width = clampf((scroll.size.x - COLUMN_GAP * 2 - 32 * 3 - 16) / 3.0, 420.0, 640.0)

	_build_placement_column(_column(columns))
	_build_world_column(_column(columns))
	_build_cheat_column(_column(columns))

	var status_card := PanelContainer.new()
	status_card.add_theme_stylebox_override("panel", DebugFormTheme.card_style(10))
	status_card.position = Vector2(MARGIN, screen.y - STATUS_HEIGHT - 20)
	status_card.size = Vector2(screen.x - MARGIN * 2, STATUS_HEIGHT)
	root.add_child(status_card)
	_status = _label("Pick anything above. Changes happen straight away.", FONT_SIZE - 1, NOTE_COLOUR)
	_status.clip_text = true
	status_card.add_child(_status)


func _build_world_column(col: VBoxContainer) -> void:
	_heading(col, "Time")
	var row: HBoxContainer = null
	for i in GameState.TIMES_OF_DAY.size():
		if i % 3 == 0:
			row = _row(col)
		var time_name := str(GameState.TIMES_OF_DAY[i])
		_add_expanded(row, _button(time_name, func(): MapManager.debug_set_time(time_name)))
	var date_row := _row(col)
	date_row.add_child(_label("Day", FONT_SIZE))
	_date_spin = SpinBox.new()
	_date_spin.min_value = 0
	_date_spin.max_value = MAX_DATE
	_date_spin.step = 1
	_date_spin.value = GameState.get_date()
	_date_spin.custom_minimum_size = Vector2(140, BUTTON_HEIGHT)
	_date_spin.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
	date_row.add_child(_date_spin)
	_add_expanded(date_row, _button("Go to this day", _jump_to_day))
	col.add_child(_button("Day 0: the match-effects test day", func(): MapManager.debug_set_date(0)))
	col.add_child(_note("Changing the day or time reloads the map where you stand, and resets this period's wins."))
	_clock_edit = _number_row(col, "Clock", "10:59pm", "Set", _set_clock)
	_points_edit = _number_row(col, "Points", "0", "Set", _set_points)
	col.add_child(_button("Add %d points (like a first win)" % GameState.TIME_POINTS_FIRST_WIN, _add_time_points))
	col.add_child(_note("Clock: type 10:59pm, 22:59 or 1am. A day runs from 8am to 8am. Points: how far through this time of day you are; a full set moves time on."))

	_heading(col, "Money")
	_cash_edit = _number_row(col, "Cash", "Amount", "Set", _set_cash)
	_fish_coin_edit = _number_row(col, "Fish Coins", "Amount", "Set", _set_fish_coins)

	_heading(col, "Fish shop")
	_fish_sent_edit = _number_row(col, "Fish sent", "Amount", "Set", _set_fish_sent)
	col.add_child(_button("Fill every tank", _fill_fish_tanks))
	col.add_child(_note("Every milestone up to this number counts as reached. Leave and re-enter the Fish Shop to see it."))


## A caption, a number box and a button: Cash [ 4780 ] [ Set ]. Enter in the box works too.
func _number_row(col: VBoxContainer, caption: String, placeholder: String, button_text: String,
		action: Callable) -> LineEdit:
	var row := _row(col)
	var label := _label(caption, FONT_SIZE)
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(200, BUTTON_HEIGHT)
	edit.add_theme_font_size_override("font_size", FONT_SIZE)
	edit.text_submitted.connect(func(_text: String): action.call())
	_add_expanded(row, edit)
	var b := _button(button_text, action)
	b.custom_minimum_size = Vector2(90, BUTTON_HEIGHT)
	row.add_child(b)
	return edit


func _build_placement_column(col: VBoxContainer) -> void:
	_heading(col, "Edit this map")
	col.add_child(_big_button("Move and edit people", "Walk around, pick anyone on this map (or a Pokémon spawn), move them, change their details.",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.EDIT), "F"))
	col.add_child(_big_button("Add someone new", "A new person, opponent or Pokémon spawn. After you save one, it asks for the next.",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.NEW), "N"))
	col.add_child(_big_button("Flying Pokémon", "The flocks that fly over this map, for each time of day.",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.FLYERS)))
	col.add_child(_big_button("Fish you can catch", "What bites at the nearest fishing spot, for each time of day.",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.FISH)))

	_heading(col, "Story")
	col.add_child(_big_button("Play a cutscene", "Every cutscene and its variations, ready to play from the start.",
			func(): _show_cutscene_page(true)))

	_heading(col, "Battles")
	col.add_child(_big_button("Start a test match", "You and the CPU both use the deck saved as \"TEST\".",
			func(): MapManager.debug_start_test_match()))
	col.add_child(_big_button("Rate every opponent", "Plays each opponent's real CPU and deck %d times against the test bot, in the background, to set their stars. About 3 seconds a game." % RATE_ALL_GAMES,
			_rate_all_opponents))


## A button with a line of grey explanation under it, kept together as one block.
func _big_button(title: String, explain: String, action: Callable, key: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var b := _button(title, action)
	if key != "":
		b.tooltip_text = "Shortcut key on the map: %s" % key
	box.add_child(b)
	box.add_child(_note(explain))
	return box


## The CUTSCENES sub-page: DebugCutscenes.entries(), one button each, grouped, in
## CUTSCENE_COLUMNS columns. A button jumps to that cutscene's day, time and place.
const CUTSCENE_COLUMNS := 3

func _build_cutscene_page(root: Control, page_size: Vector2) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.position = Vector2(MARGIN, SCROLL_TOP)
	page.size = page_size
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.visible = false
	root.add_child(page)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", ROW_GAP)
	page.add_child(outer)
	var top := _row(outer)
	var back := _button("<  Back", func(): _show_cutscene_page(false))
	back.custom_minimum_size.x = 160
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(back)
	var warn := _label("Careful: this changes the save's story (intro answers, flags, date). Best done on a spare save slot.",
			NOTE_FONT_SIZE, WARN_COLOUR)
	warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(warn)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	outer.add_child(columns)
	var cols: Array = []
	for i in CUTSCENE_COLUMNS:
		cols.append(_column(columns))
	# Groups dealt into the shortest column so the page stays balanced.
	var heights: Array = []
	heights.resize(CUTSCENE_COLUMNS)
	heights.fill(0)
	for group in DebugCutscenes.entries():
		var target := heights.find(heights.min())
		var col: VBoxContainer = cols[target]
		_heading(col, String(group[0]))
		for item in group[1]:
			var cut_id := String(item[1])
			var b := _button(String(item[0]), func(): DebugCutscenes.launch(cut_id))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.tooltip_text = String(item[0])
			col.add_child(b)
		heights[target] += 1 + (group[1] as Array).size()
	return page


func _show_cutscene_page(show: bool) -> void:
	_cutscene_page.visible = show
	_main_page.visible = not show


func _build_cheat_column(col: VBoxContainer) -> void:
	_heading(col, "Cheats")
	col.add_child(_note("The same as typing the code as your trainer name. Hover a button to see its code."))
	for code in CheatManager.codes():
		var cheat_code := str(code)
		var button := _button(_cheat_label(cheat_code), func(): _apply_cheat(cheat_code))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var extra: String = str(CHEAT_NAMES.get(cheat_code, ["", ""])[1])
		button.tooltip_text = ("%s\nCode: %s" % [extra, cheat_code]) if extra != "" else "Code: %s" % cheat_code
		if CONFIRM_CODES.has(cheat_code):
			button.theme_type_variation = "DangerButton"
		col.add_child(button)


# ============================================================
# ACTIONS
# ============================================================

func _jump_to_day() -> void:
	# The step buttons never take focus, so a typed number is still sitting in the
	# field un-applied when JUMP is clicked.
	_date_spin.apply()
	MapManager.debug_set_date(int(_date_spin.value))


func _set_cash() -> void:
	var text := _cash_edit.text.strip_edges()
	if not text.is_valid_int() or int(text) < 0:
		_say("Cash has to be a whole number, 0 or more.", BAD_COLOUR)
		return
	MapManager.debug_set_cash(int(text))
	_cash_edit.release_focus()
	_say("Cash set to %d." % GameState.get_cash())


func _set_fish_coins() -> void:
	var text := _fish_coin_edit.text.strip_edges()
	if not text.is_valid_int() or int(text) < 0:
		_say("Fish Coins have to be a whole number, 0 or more.", BAD_COLOUR)
		return
	MapManager.debug_set_fish_coins(int(text))
	_fish_coin_edit.release_focus()
	_say("Fish Coins set to %d." % GameState.get_fish_coins())


func _set_fish_sent() -> void:
	var text := _fish_sent_edit.text.strip_edges()
	if not text.is_valid_int() or int(text) < 0:
		_say("Fish sent has to be a whole number, 0 or more.", BAD_COLOUR)
		return
	FishShopCalls.debug_set_sent(int(text))
	_fish_sent_edit.release_focus()
	_say("Fish sent to FISH set to %d. Re-enter FISH to see it." % GameState.fish_sent_total())


func _fill_fish_tanks() -> void:
	FishShopCalls.debug_fill_tanks()
	_say("Every FISH tank filled for %d fish sent. Re-enter FISH to see it." % GameState.fish_sent_total())


func _set_clock() -> void:
	var hours := _parse_clock(_clock_edit.text)
	if hours < 0.0:
		_say("Clock: type a time like 10:59pm, 22:59 or 1am.", BAD_COLOUR)
		return
	_clock_edit.release_focus()
	if not MapManager.debug_set_clock(hours):
		_say("Clock: 8am to 7:54am (the next morning) only.", BAD_COLOUR)
		return
	_say("Clock set: %s (%s, %d of %d points)." % [_clock_text(GameState.clock_hours()), GameState.get_time(),
			GameState.get_time_points(), GameState.time_points_to_advance()])


func _set_points() -> void:
	var text := _points_edit.text.strip_edges()
	if not text.is_valid_int() or int(text) < 0:
		_say("Points have to be a whole number, 0 or more.", BAD_COLOUR)
		return
	_points_edit.release_focus()
	MapManager.debug_set_time_points(int(text))
	_say("Time points this period: %d of %d (%s)." % [GameState.get_time_points(),
			GameState.time_points_to_advance(), _clock_text(GameState.clock_hours())])


## "10:59pm" / "10:59 pm" / "22:59" / "1am" / "23" -> hours on the game's clock, where after midnight
## counts on from 24 (1am = 25) and the day starts at 8am. -1 if it can't be read.
func _parse_clock(raw: String) -> float:
	var t := raw.strip_edges().to_lower().replace(" ", "").replace(".", "")
	var suffix := ""
	if t.ends_with("am") or t.ends_with("pm"):
		suffix = t.right(2)
		t = t.left(t.length() - 2)
	var parts := t.split(":")
	if parts.size() > 2 or not parts[0].is_valid_int():
		return -1.0
	var hour := int(parts[0])
	var minute := 0
	if parts.size() == 2:
		if not parts[1].is_valid_int():
			return -1.0
		minute = int(parts[1])
	if minute < 0 or minute > 59:
		return -1.0
	if suffix != "":
		if hour < 1 or hour > 12:
			return -1.0
		hour = hour % 12 + (12 if suffix == "pm" else 0)
	elif hour < 0 or hour > 23:
		return -1.0
	var hours := float(hour) + float(minute) / 60.0
	if hours < 8.0:
		hours += 24.0   # after midnight: still the same game day
	return hours


## 22.9 -> "10:54pm", 25.0 -> "1:00am" (the debug readout shows minutes; the real clock shows whole hours).
func _clock_text(hours: float) -> String:
	var total := int(round(hours * 60.0))
	var hour := (total / 60) % 24
	var minute := total % 60
	var shown := hour % 12
	return "%d:%02d%s" % [12 if shown == 0 else shown, minute, "am" if hour < 12 else "pm"]


func _add_time_points() -> void:
	MapManager.debug_add_time_points()
	_say("Time points this period: %d of %d." % [GameState.get_time_points(), GameState.time_points_to_advance()])


func _apply_cheat(code: String) -> void:
	if CONFIRM_CODES.has(code) and _armed_code != code:
		_armed_code = code
		_say("Click \"%s\" again to confirm. It can't be undone." % _cheat_label(code), WARN_COLOUR)
		return
	_armed_code = ""
	var message := CheatManager.apply_code(code)
	_say(message + "." if message != "" else "%s did nothing." % _cheat_label(code))


## TWEAKABLE: games per opponent for RATE ALL OPPONENTS.
const RATE_ALL_GAMES := 10
const DeckTestRunner := preload("res://Scripts/Utilities/Deck_Test_Runner.gd")

func _rate_all_opponents() -> void:
	var runner = DeckTestRunner.instance()
	var problem: String = runner.rate_all(RATE_ALL_GAMES)
	if problem != "":
		_say(problem, WARN_COLOUR)
	else:
		_say("Rating every opponent in the background. Progress shows bottom-right.")


# ============================================================
# HELPERS
# ============================================================

func _say(text: String, colour: Color = GOOD_COLOUR) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)
	_refresh_state()


func _refresh_state() -> void:
	if _state_label == null:
		return
	_state_label.text = "Day %d  ·  %s, %s  ·  $%d  ·  %d Fish Coins  ·  %d of %d time points" % [
			GameState.get_date(), GameState.get_time(), _clock_text(GameState.clock_hours()), GameState.get_cash(),
			GameState.get_fish_coins(), GameState.get_time_points(), GameState.time_points_to_advance()]
	if _points_edit != null and not _points_edit.has_focus():
		_points_edit.text = str(GameState.get_time_points())
	if _cash_edit != null and not _cash_edit.has_focus():
		_cash_edit.text = str(GameState.get_cash())
	if _fish_coin_edit != null and not _fish_coin_edit.has_focus():
		_fish_coin_edit.text = str(GameState.get_fish_coins())
	if _fish_sent_edit != null and not _fish_sent_edit.has_focus():
		_fish_sent_edit.text = str(GameState.fish_sent_total())


## "CHT.All_Cards_1" -> "Own every Base, Gym and promo card" (CHEAT_NAMES), else a tidied code.
func _cheat_label(code: String) -> String:
	if CHEAT_NAMES.has(code):
		return str(CHEAT_NAMES[code][0])
	return code.trim_prefix("CHT.").trim_prefix("CHT_").replace("_", " ").replace(".", " ").capitalize()


## One column of the page: a card holding a stack of rows.
func _column(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", DebugFormTheme.card_style(16))
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(_column_width, 0)
	col.add_theme_constant_override("separation", ROW_GAP)
	card.add_child(col)
	return col


func _row(col: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	col.add_child(row)
	return row


## Add `control` to a row, stretched to fill whatever width is left.
func _add_expanded(row: HBoxContainer, control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _heading(col: VBoxContainer, text: String) -> void:
	if col.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		col.add_child(gap)
	var heading := DebugFormTheme.heading(text)
	heading.get_child(0).add_theme_font_size_override("font_size", HEADING_FONT_SIZE)
	col.add_child(heading)


func _note(text: String) -> Label:
	var note := _label(text, NOTE_FONT_SIZE, NOTE_COLOUR)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(_column_width, 0)
	return note


func _label(text: String, font_size: int, colour: Color = DebugFormTheme.ON_BACKDROP) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


## FOCUS_NONE: Space / Enter would otherwise press the last-clicked button again --
## which for a cheat means applying it twice.
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(action)
	return button


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# Only the close keys are consumed: _input runs before GUI input, so taking
	# anything else would stop the text boxes being typed into.
	if event.keycode == KEY_ESCAPE or (event.keycode == KEY_DELETE and not _is_typing()):
		get_viewport().set_input_as_handled()
		MapManager.close_debug_menu()


func _is_typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit
