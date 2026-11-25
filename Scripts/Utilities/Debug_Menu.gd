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
	"CHT.All_Medals": ["Earn every medal", "Top grade on all of them. One medal's reveal plays after you close this menu."],
	"CHT.Real_Medals": ["Medals: back to the real ones", "Undoes Earn every medal, with no notices"],
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
	# REPORT BUG (Bug_Report.gd) sits top right, in the space the header leaves free.
	BugReport.register_menu(self, func(): MapManager.close_debug_menu(), "overworld DEL menu")


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
	header.custom_minimum_size = Vector2(screen.x - MARGIN * 2 - BugReport.BUTTON_RESERVE, 0)
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

	_heading(col, "Following Pokémon")
	var follow_row := _row(col)
	_add_expanded(follow_row, _button("Give test foods", _give_test_foods))
	_add_expanded(follow_row, _button("Release follower (to the wild)", _debug_send_follower_home))
	col.add_child(_button("Add SUPER FOOD (capture any Pokémon)", _give_super_food))
	col.add_child(_button("Befriend another of your follower's species", _befriend_duplicate))
	col.add_child(_button("Shiny odds: 1 in %d / back to 1 in %d" % [DEBUG_SHINY_ODDS, OverworldPokemonData.SHINY_ODDS], _toggle_shiny_odds))
	var home_row := _row(col)
	_add_expanded(home_row, _button("Give one of each bed", _give_test_beds))
	_add_expanded(home_row, _button("Empty the house", _empty_house))
	col.add_child(_button("Move bed spots (bedroom)", _move_bed_spots))
	col.add_child(_note("Beds: in the bedroom, Space at a bed space cycles EVERY bed (debug: beds from nowhere; empty spaces are pink dots). 'Give one of each bed' puts one of each in your spares for the real cycle. Who likes which food / bed: Pokemon_Food_And_Beds.csv."))
	col.add_child(_note("3 of every food (the CSV's Food column + Pokemon_Foods.json). Talk to a Pokémon that likes one (Ctrl to sneak up on a skittish one), or fish with it in the bag."))

	_heading(col, "Affection + evolution (your follower)")
	var aff_row := _row(col)
	_add_expanded(aff_row, _button("Affection -1 level", func() -> void: _bump_affection(-PokemonAffection.LEVEL_SIZE)))
	_add_expanded(aff_row, _button("Affection +1 level", func() -> void: _bump_affection(PokemonAffection.LEVEL_SIZE)))
	var aff_row2 := _row(col)
	_add_expanded(aff_row2, _button("Affection to 0", func() -> void: _set_affection(0)))
	_add_expanded(aff_row2, _button("Affection to max", func() -> void: _set_affection(PokemonAffection.MAX)))
	col.add_child(_button("Show affection + evolutions", _show_affection))
	var care_row := _row(col)
	_add_expanded(care_row, _button("Follower hungry", func() -> void: _debug_hunger(1.0)))
	_add_expanded(care_row, _button("Very hungry", func() -> void: _debug_hunger(1.0 + (PokemonCare.STARVING_FACTOR - 1.0) * PokemonCare.VERY_HUNGRY_FRACTION)))
	_add_expanded(care_row, _button("Starving (free hour)", func() -> void: _debug_hunger(PokemonCare.STARVING_FACTOR)))
	var care_row2 := _row(col)
	_add_expanded(care_row2, _button("Starved (sad, -20)", func() -> void: _debug_hunger(PokemonCare.STARVING_FACTOR, float(PokemonCare.STARVE_GRACE_HOURS) + 0.05)))
	_add_expanded(care_row2, _button("Follower fed", func() -> void: _debug_hunger(0.0)))
	_add_expanded(care_row2, _button("Ignored 6h (-10)", _debug_ignored))
	_add_expanded(care_row2, _button("Next pet works", _debug_free_pet))
	var evo_row := _row(col)
	_add_expanded(evo_row, _button("Evolve follower now", _evolve_follower_now))
	_add_expanded(evo_row, _button("Evolve after next win", _toggle_evolve_after_win))
	col.add_child(_button("Show a test medal (checks the input lock)", _show_test_medal))
	col.add_child(_note("Affection: 0-700, a new level (0-7) every 100. Talk to your follower to see its level's reaction and line. Evolve now plays the full animation on this map; 'after next win' evolves it once you win a match (a T test match counts), after any medal."))


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
	var force := _button("FORCE ALL SPAWNS (this map)", _force_all_spawns)
	force.alignment = HORIZONTAL_ALIGNMENT_LEFT
	force.tooltip_text = "Every spawn point and flyer table on this map at 100%, until the map reloads\n(a battle, a door, a day/time change)."
	col.add_child(force)
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


func _give_test_foods() -> void:
	FollowingPokemon.reload()
	var names := FollowingPokemon.food_names()
	for food_name in names:
		GameState.add_food(str(food_name), 3)
	_say("Gave 3 of each food: %s." % ", ".join(PackedStringArray(names)) if not names.is_empty()
			else "No foods in Pokemon_Foods.json.", GOOD_COLOUR if not names.is_empty() else BAD_COLOUR)


## The placement tool's FORCED preview, minus the tool: every point and every flyer table at
## 100%, from the SAVED spawn file. Lasts until the map reloads -- the spawner is rebuilt
## fresh (preview off) on every load, so nothing is saved.
func _force_all_spawns() -> void:
	var spawner := get_tree().get_first_node_in_group(OverworldPokemonSpawner.GROUP) as OverworldPokemonSpawner
	if spawner == null:
		_say("This map has no Pokémon spawner.", BAD_COLOUR)
		return
	spawner.set_preview(true)
	_say("FORCE ALL SPAWNS on: every spawn point on this map is at 100% until the map reloads.")


func _give_test_beds() -> void:
	PokemonHome.reload()
	for bed_name in PokemonHome.bed_names():
		PokemonHome.add_bed(str(bed_name))
	_refresh_bed_spots()
	_say("One of each of the %d beds added to your spare beds (see the bag). Space at a bed space in your room to place them." % PokemonHome.bed_names().size())


func _empty_house() -> void:
	GameState.set_bed_slots([])
	# Released properly, flags and all: left-over flags would make the next one of that species
	# a "#2" for no reason (PokemonHome.new_id skips any ID that still has flags).
	for id in PokemonHome.home_pokemon():
		PokemonHome.release(str(id))
	for bed_name in GameState.get_spare_beds().keys():
		GameState.add_spare_bed(str(bed_name), -int(GameState.get_spare_beds()[bed_name]))
	_refresh_bed_spots()
	_say("Every bed, spare bed and Pokémon at home removed. Your follower (if any) is still following you.")


func _refresh_bed_spots() -> void:
	var map_root: Node = MapManager._player.get_parent() if MapManager._player != null and is_instance_valid(MapManager._player) else null
	if map_root != null and PokemonHome.in_house(MapManager._map_scene_path):
		PokemonHome.refresh_house(map_root)


func _move_bed_spots() -> void:
	if not (PokemonHome.BEDROOM_SCENE in MapManager._map_scene_path):
		_say("Go up to your bedroom first -- the bed spaces are there.", BAD_COLOUR)
		return
	var map_root: Node = MapManager._player.get_parent()
	MapManager.close_debug_menu()
	BedSpotMover.open(map_root)


func _give_super_food() -> void:
	if not FollowingPokemon.has_super_food():
		GameState.add_food(FollowingPokemon.SUPER_FOOD, 1)
	_say("SUPER FOOD is in the bag. Stand on any Pokémon and press Space / click / A, or fish one up.")


## TWEAKABLE: the shiny odds the DEL button switches to.
const DEBUG_SHINY_ODDS := 4

func _toggle_shiny_odds() -> void:
	var on := OverworldPokemonData.debug_shiny_odds != DEBUG_SHINY_ODDS
	OverworldPokemonData.debug_shiny_odds = DEBUG_SHINY_ODDS if on else 0
	if on:
		_say("Shiny odds are now 1 in %d for every spawn and fishing bite (until you press this again or close the game). Re-enter a map to respawn." % DEBUG_SHINY_ODDS)
	else:
		_say("Shiny odds back to 1 in %d." % OverworldPokemonData.SHINY_ODDS)


## The follower, or "" with a red note.
func _debug_follower() -> String:
	var f := GameState.get_follower()
	if f == "":
		_say("No Pokémon is following you.", BAD_COLOUR)
	return f


func _affection_text(f: String) -> String:
	var p := PokemonAffection.points(f)
	return "%s: affection %d / %d (level %d), pet chance %d%%" % [PokemonHome.name_of(f), p, PokemonAffection.MAX,
			PokemonAffection.level_of_points(p), roundi(PokemonAffection.pet_chance(f) * 100.0)]


func _bump_affection(amount: int) -> void:
	var f := _debug_follower()
	if f == "":
		return
	PokemonAffection.add(f, amount)
	_say(_affection_text(f))


## Sets the follower's hunger to `times` its CSV Hunger hours (+ `extra` hours): 1 = hungry,
## 2 = starving, 0 = fed. The next watch tick charges whatever that costs.
func _debug_hunger(times: float, extra: float = 0.0) -> void:
	var f := _debug_follower()
	if f == "":
		return
	var limit := PokemonCare.hunger_limit(f)
	if limit <= 0.0:
		_say("%s has no Hunger hours in Pokemon_Food_And_Beds.csv, so it never gets hungry." % PokemonHome.name_of(f))
		return
	GameState.set_pokemon_flag_values(f, {"hunger": limit * times + extra, "starve_paid": 0,
			"hunger_clock": PokemonAffection.now_hours()})
	_say("%s: hunger %.1f h (hungry at %.0f, very hungry at %.0f, starving at %.0f, sad + -20 an hour from %.0f)." % [
			PokemonHome.name_of(f), limit * times + extra, limit,
			limit + limit * (PokemonCare.STARVING_FACTOR - 1.0) * PokemonCare.VERY_HUNGRY_FRACTION,
			limit * PokemonCare.STARVING_FACTOR, limit * PokemonCare.STARVING_FACTOR + PokemonCare.STARVE_GRACE_HOURS])


## The follower has gone NEGLECT_FOLLOW_HOURS without a talk: the next watch tick takes the
## affection, and the next talk says it felt forgotten.
func _debug_ignored() -> void:
	var f := _debug_follower()
	if f == "":
		return
	GameState.set_pokemon_flag(f, "lonely_follow", PokemonCare.NEGLECT_FOLLOW_HOURS + 0.01)
	_say("%s has been ignored for %.0f hours." % [PokemonHome.name_of(f), PokemonCare.NEGLECT_FOLLOW_HOURS])


func _debug_free_pet() -> void:
	var f := _debug_follower()
	if f == "":
		return
	GameState.set_pokemon_flag(f, "pet_free", true)
	_say(_affection_text(f))


func _set_affection(p: int) -> void:
	var f := _debug_follower()
	if f == "":
		return
	PokemonAffection.set_points(f, p)
	_say(_affection_text(f))


func _show_affection() -> void:
	var f := _debug_follower()
	if f == "":
		return
	PokemonAffection.credit_hours()
	var flags := GameState.get_pokemon_flags(f)
	var evos: Array = []
	for e in PokemonEvolution.evolutions_of(f):
		evos.append(OverworldPokemonData.display_name(str(e)))
	_say("%s | wins %d, pets %d, meals %d | evolves into: %s | CSV: '%s'" % [_affection_text(f),
			int(flags.get("wins", 0)), int(flags.get("pets", 0)), int(flags.get("meals", 0)),
			", ".join(evos) if not evos.is_empty() else "nothing", PokemonPrefs.evolution_of(PokemonHome.species_of(f))])


func _evolve_follower_now() -> void:
	var f := _debug_follower()
	if f == "":
		return
	var evos := PokemonEvolution.evolutions_of(f)
	if evos.is_empty():
		_say("%s has no evolution." % PokemonHome.name_of(f), BAD_COLOUR)
		return
	if not PokemonEvolution.queue(f, str(evos[0])):
		_say("Can't evolve into %s (it has no overworld art)." % OverworldPokemonData.display_name(str(evos[0])), BAD_COLOUR)
		return
	var map_root: Node = MapManager._player.get_parent()
	MapManager.close_debug_menu()
	PokemonEvolution.run_pending(map_root)


func _toggle_evolve_after_win() -> void:
	PokemonEvolution.debug_after_next_win = not PokemonEvolution.debug_after_next_win
	_say("Evolve after the next win: %s" % ("ON - win a match with your follower" if PokemonEvolution.debug_after_next_win else "off"))


## Queues one medal reveal without earning anything, through the same path a real one takes
## (the input lock goes on at once and lifts when the medal screen closes).
func _show_test_medal() -> void:
	var defs := MedalData.all()
	if defs.is_empty():
		_say("No medals defined.", BAD_COLOUR)
		return
	BaseMapScene._queued_medals.append({"def": defs[randi() % defs.size()], "tier": 0})
	MapManager.close_debug_menu()


## A second (third...) of the follower's species joins you, so owning several of one species can
## be tried without hunting for another. The old follower goes home as usual.
func _befriend_duplicate() -> void:
	var f := _debug_follower()
	if f == "":
		return
	var old := FollowingPokemon.befriend(PokemonHome.species_of(f), null, false)
	var copies := 0
	for id in PokemonHome.roster():
		if PokemonHome.species_of(str(id)) == PokemonHome.species_of(f):
			copies += 1
	_say("Another %s joined you (ID %s). You now have %d. %s" % [OverworldPokemonData.display_name(f),
			GameState.get_follower(), copies, PokemonHome.old_follower_note(old)])


func _debug_send_follower_home() -> void:
	if GameState.get_follower() == "":
		_say("No Pokémon is following you.", BAD_COLOUR)
		return
	var gone := PokemonHome.name_of(GameState.get_follower())
	FollowingPokemon.send_home()
	_say("%s went back to the wild." % gone)


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
