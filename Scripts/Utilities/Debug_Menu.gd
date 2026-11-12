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
const TITLE_FONT_SIZE := 34
const HEADING_FONT_SIZE := 25
const FONT_SIZE := 22
const NOTE_FONT_SIZE := 18
const MARGIN := 60
const COLUMN_WIDTH := 540
const COLUMN_GAP := 50
const ROW_GAP := 10
const BUTTON_HEIGHT := 50
const SCROLL_TOP := 120
const SCROLL_HEIGHT := 860
const STATUS_TOP := 1000
## Highest day the date picker offers. Day 0 is the match-effects test day.
const MAX_DATE := 99
## Above the placement tool (128) and its forms (129).
const LAYER := 130
const HEADING_COLOUR := Color(1.0, 0.85, 0.4)
const INFO_COLOUR := Color(0.45, 0.85, 1.0)
const NOTE_COLOUR := Color(0.8, 0.84, 0.92)
const GOOD_COLOUR := Color(0.55, 0.95, 0.55)
const WARN_COLOUR := Color(1.0, 0.7, 0.35)
const BAD_COLOUR := Color(1.0, 0.55, 0.45)
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


func _ready() -> void:
	layer = LAYER
	_build()
	_refresh_state()


# ============================================================
# BUILD
# ============================================================

func _build() -> void:
	var root := ColorRect.new()
	root.color = DebugFormTheme.BACKDROP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = DebugFormTheme.build()
	add_child(root)

	var title := _label("DEBUG MENU", TITLE_FONT_SIZE)
	title.position = Vector2(MARGIN, 24)
	root.add_child(title)

	var hint := _label("DEL or Esc to close", FONT_SIZE, NOTE_COLOUR)
	hint.position = Vector2(1920 - MARGIN - 400, 34)
	hint.size = Vector2(400, 32)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	_state_label = _label("", FONT_SIZE, INFO_COLOUR)
	_state_label.position = Vector2(MARGIN, 74)
	root.add_child(_state_label)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(MARGIN, SCROLL_TOP)
	scroll.size = Vector2(1920 - MARGIN * 2, SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_main_page = scroll
	_cutscene_page = _build_cutscene_page(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	scroll.add_child(columns)

	_build_world_column(_column(columns))
	_build_placement_column(_column(columns))
	_build_cheat_column(_column(columns))

	_status = _label("", FONT_SIZE, GOOD_COLOUR)
	_status.position = Vector2(MARGIN, STATUS_TOP)
	_status.size = Vector2(1920 - MARGIN * 2, 40)
	_status.clip_text = true
	root.add_child(_status)


func _build_world_column(col: VBoxContainer) -> void:
	_heading(col, "CUTSCENES")
	col.add_child(_button("CUTSCENES…", func(): _show_cutscene_page(true)))
	col.add_child(_note("Every cutscene and variation, ready to play from the start."))

	_heading(col, "TIME OF DAY")
	var row: HBoxContainer = null
	for i in GameState.TIMES_OF_DAY.size():
		if i % 2 == 0:
			row = _row(col)
		var time_name := str(GameState.TIMES_OF_DAY[i])
		_add_expanded(row, _button(time_name.to_upper(), func(): MapManager.debug_set_time(time_name)))

	_heading(col, "DATE")
	var date_row := _row(col)
	_date_spin = SpinBox.new()
	_date_spin.min_value = 0
	_date_spin.max_value = MAX_DATE
	_date_spin.step = 1
	_date_spin.value = GameState.get_date()
	_date_spin.custom_minimum_size = Vector2(170, BUTTON_HEIGHT)
	_date_spin.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
	date_row.add_child(_date_spin)
	_add_expanded(date_row, _button("JUMP TO DAY", _jump_to_day))
	col.add_child(_button("DAY 0  —  MATCH EFFECTS TEST DAY", func(): MapManager.debug_set_date(0)))
	col.add_child(_note("Changing the day or time resets this period's defeated count and reloads the map where you stand."))

	_heading(col, "CASH")
	var cash_row := _row(col)
	_cash_edit = LineEdit.new()
	_cash_edit.placeholder_text = "Amount"
	_cash_edit.custom_minimum_size = Vector2(240, BUTTON_HEIGHT)
	_cash_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_cash_edit.text_submitted.connect(func(_text: String): _set_cash())
	cash_row.add_child(_cash_edit)
	_add_expanded(cash_row, _button("SET CASH", _set_cash))

	_heading(col, "FISH COINS")
	var fish_row := _row(col)
	_fish_coin_edit = LineEdit.new()
	_fish_coin_edit.placeholder_text = "Amount"
	_fish_coin_edit.custom_minimum_size = Vector2(240, BUTTON_HEIGHT)
	_fish_coin_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_fish_coin_edit.text_submitted.connect(func(_text: String): _set_fish_coins())
	fish_row.add_child(_fish_coin_edit)
	_add_expanded(fish_row, _button("SET FISH COINS", _set_fish_coins))

	_heading(col, "FISH SENT")
	var sent_row := _row(col)
	_fish_sent_edit = LineEdit.new()
	_fish_sent_edit.placeholder_text = "Amount"
	_fish_sent_edit.custom_minimum_size = Vector2(240, BUTTON_HEIGHT)
	_fish_sent_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_fish_sent_edit.text_submitted.connect(func(_text: String): _set_fish_sent())
	sent_row.add_child(_fish_sent_edit)
	_add_expanded(sent_row, _button("SET FISH SENT", _set_fish_sent))
	col.add_child(_button("FILL ALL TANKS", _fill_fish_tanks))
	col.add_child(_note("Milestones at or below the number count as rung (items unlocked); the next real catch past one rings it. Re-enter FISH to see the change."))

	_heading(col, "CLOCK")
	var clock_row := _row(col)
	_clock_edit = LineEdit.new()
	_clock_edit.placeholder_text = "10:59pm"
	_clock_edit.custom_minimum_size = Vector2(240, BUTTON_HEIGHT)
	_clock_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_clock_edit.text_submitted.connect(func(_text: String): _set_clock())
	clock_row.add_child(_clock_edit)
	_add_expanded(clock_row, _button("SET CLOCK", _set_clock))
	var points_row := _row(col)
	_points_edit = LineEdit.new()
	_points_edit.placeholder_text = "Points"
	_points_edit.custom_minimum_size = Vector2(240, BUTTON_HEIGHT)
	_points_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_points_edit.text_submitted.connect(func(_text: String): _set_points())
	points_row.add_child(_points_edit)
	_add_expanded(points_row, _button("SET POINTS", _set_points))
	col.add_child(_button("+%d TIME POINTS" % GameState.TIME_POINTS_FIRST_WIN, _add_time_points))
	col.add_child(_note("Clock: 10:59pm, 10:59 pm, 22:59, 1am (8am to 7:54am next morning). Points are whole, so it lands on the last point at or before that minute - the next point (a pack is +1 from day 3) tips it over. Points: the exact count in this period; a full period moves time on."))

	_heading(col, "BATTLE")
	col.add_child(_button("START TEST MATCH", func(): MapManager.debug_start_test_match()))
	col.add_child(_note("You and the opponent both use the deck saved as \"TEST\"."))
	col.add_child(_button("RATE ALL OPPONENTS (%d games each)" % RATE_ALL_GAMES, _rate_all_opponents))
	col.add_child(_note("Runs in the background: every opponent's real CPU and deck against the smart bot playing each starter deck. The win rate sets their difficulty stars (unless set by hand in the character editor). Progress shows bottom-right. Takes a while: about 3 seconds a game."))


func _build_placement_column(col: VBoxContainer) -> void:
	_heading(col, "PLACEMENT")
	col.add_child(_button("EDIT CURRENT NPCS",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.EDIT)))
	col.add_child(_note("Walk around, cycle through the NPCs, opponents and Pokémon spawn points on this map, then move or edit them."))
	col.add_child(_button("NEW NPC / OPPONENT / POKÉMON",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.NEW)))
	col.add_child(_note("Opens the create screen. After you place and save one, it opens again for the next."))
	col.add_child(_button("FLYER TABLES",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.FLYERS)))
	col.add_child(_note("This map's Morning / Afternoon / Evening / Night flying Pokémon."))
	col.add_child(_button("FISH TABLE",
			func(): MapManager.debug_open_placement_tool(PlacementTool.Mode.FISH)))
	col.add_child(_note("The nearest fishing spot's Morning / Afternoon / Evening / Night catchable fish. A map can have several and they fish differently — add one with NEW, template \"Fishing spot\"."))


## The CUTSCENES sub-page: DebugCutscenes.entries(), one button each, grouped, in
## CUTSCENE_COLUMNS columns. A button jumps to that cutscene's day, time and place.
const CUTSCENE_COLUMNS := 3

func _build_cutscene_page(root: Control) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.position = Vector2(MARGIN, SCROLL_TOP)
	page.size = Vector2(1920 - MARGIN * 2, SCROLL_HEIGHT)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.visible = false
	root.add_child(page)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", ROW_GAP)
	page.add_child(outer)
	var top := _row(outer)
	var back := _button("◀  BACK", func(): _show_cutscene_page(false))
	back.custom_minimum_size.x = 220
	top.add_child(back)
	var warn := _label("Rewrites this save's story state (intro answers, flags, date) — use a spare save slot.",
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
	_heading(col, "NAME CHEATS")
	col.add_child(_note("The same as typing the code as your trainer name."))
	for code in CheatManager.codes():
		var cheat_code := str(code)
		var button := _button(_cheat_label(cheat_code), func(): _apply_cheat(cheat_code))
		button.tooltip_text = cheat_code
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
		_say("Click %s again to confirm — it can't be undone." % _cheat_label(code), WARN_COLOUR)
		return
	_armed_code = ""
	var message := CheatManager.apply_code(code)
	_say(message if message != "" else "%s did nothing." % code)


## TWEAKABLE: games per opponent for RATE ALL OPPONENTS.
const RATE_ALL_GAMES := 10
const DeckTestRunner := preload("res://Scripts/Utilities/Deck_Test_Runner.gd")

func _rate_all_opponents() -> void:
	var runner = DeckTestRunner.instance()
	var problem: String = runner.rate_all(RATE_ALL_GAMES)
	if problem != "":
		_say(problem, WARN_COLOUR)
	else:
		_say("Rating every opponent in the background — progress bottom-right.")


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
	_state_label.text = "Day %d   |   %s %s   |   Cash %d   |   Fish Coins %d   |   Time points %d of %d" % [
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


## "CHT.All_Cards_1" -> "ALL CARDS 1".
func _cheat_label(code: String) -> String:
	return code.trim_prefix("CHT.").replace("_", " ").to_upper()


func _column(parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	col.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(col)
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
	col.add_child(_label(text, HEADING_FONT_SIZE, HEADING_COLOUR))


func _note(text: String) -> Label:
	var note := _label(text, NOTE_FONT_SIZE, NOTE_COLOUR)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
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
