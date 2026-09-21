class_name PokemonSpawnEditor
extends CanvasLayer

## In-game form for overworld Pokémon spawns. Debug builds only -- reached from the
## placement tool, which the DEL debug menu opens: NEW NPC / OPPONENT / POKÉMON ->
## POKÉMON for a new spawn point, FLYER TABLES for the map's four time-of-day flyer
## tables, or EDIT CURRENT NPCS -> EDIT NPC (M) on a selected spawn-point marker.
##
## Like the character editor it writes nothing itself. Confirm hands a draft back to
## PlacementTool, which places a new point at the player, lets you grab it, and
## writes NPC_and_Opponent_Data/Pokemon/Spawns/<Map>.json on Enter.
##
##   Escape   cancel

signal confirmed(draft: Dictionary)
signal cancelled
## Flyer tables only: SAVE. The placement tool writes the file and answers with
## notify_saved(); the form stays open.
signal save_requested(draft: Dictionary)

# ---- tweakables -------------------------------------------------------------
const DEFAULT_TEMPLATE := "skittish"

const FORM_FONT_SIZE := 18
const TITLE_FONT_SIZE := 28
const LABEL_WIDTH := 170
const FORM_MARGIN := 40
## The left column only holds a handful of settings; the species table on the right
## needs the room (a flyer row's second line runs to ~1000px). Together with the gap
## and the scrollbar they fill the 1840px between the margins.
const LEFT_COLUMN_WIDTH := 520
const RIGHT_COLUMN_WIDTH := 1270
const COLUMN_GAP := 36
const ROW_GAP := 6
const ICON_SIZE := Vector2(40, 40)
## A species row is one line: icon, name, Rate, Scale, (flyers: Flock, Speed, Spin,
## Erratic), REMOVE. Every piece has a fixed width so the columns line up row to row.
const NAME_WIDTH := 150
const ROW_ITEM_GAP := 8
## Width of the Rate (%) box.
const PERCENT_SPIN_WIDTH := 84
## The square bin button that removes a species row.
const REMOVE_BUTTON_SIZE := 34
## Width of a spin box's up / down arrow strip (DebugFormTheme's default is 34).
const SPIN_BUTTONS_WIDTH := 18
## Left/right padding inside a number box (DebugFormTheme's default is 8).
const SPIN_FIELD_PADDING := 6
## Widths of the flock and speed min / max boxes on a flyer row.
const FLOCK_SPIN_WIDTH := 58
const SPEED_SPIN_WIDTH := 70
## Width of the Scale box on every species row.
const SCALE_SPIN_WIDTH := 90
## FISH TABLE mode hangs six more number boxes off the end of the species row, so the
## whole row -- name, Rate, Scale, all six fight stats and the bin -- has to fit inside
## RIGHT_COLUMN_WIDTH on ONE line. Everything about a fish row is therefore tighter than
## the others: shorter captions (FISH_STAT_LABELS), narrower boxes and a smaller gap.
## _add_fish_controls is measured by probe; go over RIGHT_COLUMN_WIDTH and the bin falls off.
const FISH_STAT_SPIN_WIDTH := 66
const FISH_STAT_GAP := 3
## Rate and Scale shrink too on a fish row; Scale loses its "x" suffix for the room.
const FISH_NAME_WIDTH := 126
const FISH_PERCENT_SPIN_WIDTH := 66
const FISH_SCALE_SPIN_WIDTH := 66
## What each of the six fish boxes does, as its tooltip -- the captions are too short to say.
const FISH_STAT_TIPS := {
	"energy": "Stamina. Pulling the right way drains it at 40 a second; at 0 the fish is blown and can be reeled in. Higher = a longer fight.",
	"line_strength": "How hard the line can be loaded either way before it breaks -- one number for both ends, so 100 means -100 (gone slack) to +100 (snapped). Lower = less room for mistakes.",
	"recharge_time": "Seconds the blown fish rests before it is back to full energy. This IS the reel-in window, so higher = more presses land per run.",
	"reel_step": "World pixels the fish is dragged in by each reel press during that window. It is landed at 80 out. Higher = a shorter fight.",
	"initial_distance": "World pixels the strike runs it out PAST THE BOBBER -- added to wherever the cast landed. 0 is no run at all; the more, the further it bolts for open water the moment it is hooked.",
	"lateral_speed": "World pixels a second it runs left and right across the cast. Higher = faster dashes to read and counter.",
}
const SCROLL_TOP := 92
const SCROLL_HEIGHT := 900
const FOOTER_TOP := 1010
const FOOTER_HEIGHT := 48
# -----------------------------------------------------------------------------

var _map_data: String = ""
var _doc: Dictionary = {}
var _original: Dictionary = {}
var _is_new: bool = true
## species -> [templates] the placement tool is already holding from earlier drafts,
## so a species added with ADD ANY is offered under ADD FROM TEMPLATE next time too.
var _known_additions: Dictionary = {}

var _template: String = DEFAULT_TEMPLATE
## [{species, percent}] (+ min, max for flyers) of the time of day on screen. This IS
## the array inside the active tables dictionary, so edits land there directly.
var _table: Array = []
## Working copies of the four time-of-day tables: the map's flyers, and this point's
## own. Kept apart so switching template between the two never mixes them.
var _flyer_tables: Dictionary = {}
var _fish_tables: Dictionary = {}
## FISH TABLE mode: the map's four fishing tables instead of a template's. Saves in
## place like the flyer tables, and has no chance, interval or point settings at all.
var _fish_mode: bool = false
## FISH TANK mode: the one point template with a single table instead of four (an
## aquarium indoors has no time of day) and no chance at all -- every row in it is put
## out, `count` of each. Kept in its own array for the same reason the flyer and fish
## tables are: switching template away and back must not mix them up.
var _tank_table: Array = []
var _point_tables: Dictionary = {}
## species -> {speed_min, speed_max, scale}: the species-wide settings being edited.
## Seeded from the registry (and any unsaved edits the placement tool is holding), so a
## speed set on the Morning table is already there on the Night table. Only the ones
## that differ from the registry go into the draft.
var _species_settings: Dictionary = {}
## Which time of day's table is on screen.
var _table_time: String = ""
var _time_opt: OptionButton = null
var _title: Label = null
var _scope: Label = null
var _cancel_btn: Button = null
## Flyer tables as last saved (JSON), so CLOSE can tell whether it would lose edits.
var _flyer_saved_json: String = ""
## CLOSE was clicked once over unsaved flyer edits; the next click discards them.
var _close_armed: bool = false

var _root: Control = null
var _template_opt: OptionButton = null
var _desc: Label = null
var _chance_label: Label = null
var _chance: SpinBox = null
var _interval: SpinBox = null
var _up_time: SpinBox = null
var _pattern_opt: OptionButton = null
var _distance: SpinBox = null
var _speed: SpinBox = null
var _axis_opt: OptionButton = null
## Direction name -> its "Runs away" tick box.
var _flee_boxes: Dictionary = {}
var _into_water: CheckBox = null
var _in_tank: CheckBox = null
var _rows: Dictionary = {}
var _table_box: VBoxContainer = null
var _total_label: Label = null
var _status: Label = null
var _confirm_btn: Button = null

var _picker: AssetPickerOverlay = null


# ============================================================
# SETUP
# ============================================================

## `point` is the spawn point being edited, or {} for a new one. `open_flyers` opens
## straight onto the map's flyer tables (N -> FLYER TABLES).
func setup(map_data: String, working_doc: Dictionary, point: Dictionary,
		known_additions: Dictionary = {}, open_flyers: bool = false,
		species_settings: Dictionary = {}, open_fish: bool = false) -> void:
	_map_data = map_data
	_species_settings = species_settings.duplicate(true)
	_doc = working_doc
	_original = point
	_is_new = point.is_empty()
	_known_additions = known_additions
	layer = 129
	if not _is_new:
		_template = str(point.get("template", DEFAULT_TEMPLATE))
	elif open_flyers:
		_template = "flyer"
	if open_fish:
		_fish_mode = true
		# Not a real template -- it only seeds ADD FROM TEMPLATE with the water Pokémon,
		# which is the list a fishing table almost always wants.
		_template = "surfacing"
	_build()
	if _is_new:
		_up_time.value = 0
	else:
		_load_point(point)
	_enter_time_tables()
	_on_template_changed()


## Point-wide settings, plus the point's four tables (shown by _enter_time_tables).
func _load_point(point: Dictionary) -> void:
	_up_time.value = float(point.get("up_time", 0))
	_select_option(_pattern_opt, str(point.get("pattern", "idle_cycle")))
	_distance.value = float(point.get("distance", PokemonStatic.DEFAULT_DISTANCE))
	_speed.value = float(point.get("speed", PokemonStatic.DEFAULT_SPEED))
	_select_option(_axis_opt, str(point.get("axis", "horizontal")))
	var allowed := OverworldPokemonData.flee_directions(point)
	for direction in _flee_boxes:
		(_flee_boxes[direction] as CheckBox).button_pressed = allowed.has(direction)
	_into_water.button_pressed = bool(point.get("into_water", false))
	_in_tank.button_pressed = bool(point.get("in_tank", false))
	# A tank's species sit on the point as `fish_table`, not in the four time tables.
	var tank_rows = point.get("fish_table", [])
	_tank_table = (tank_rows as Array).duplicate(true) if tank_rows is Array else []
	_point_tables = OverworldPokemonData.normalise_point_tables(point.get("tables")).duplicate(true)


# ============================================================
# BUILD
# ============================================================

func _build() -> void:
	_root = ColorRect.new()
	_root.color = DebugFormTheme.BACKDROP
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = DebugFormTheme.build()
	add_child(_root)

	# Text is set by _on_template_changed(): it depends on the template.
	_title = Label.new()
	_title.position = Vector2(FORM_MARGIN, 12)
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_root.add_child(_title)

	# Text is set by _on_template_changed(): flyer tables save in place, points don't.
	_scope = Label.new()
	_scope.position = Vector2(FORM_MARGIN, 54)
	_scope.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_scope.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	_root.add_child(_scope)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(FORM_MARGIN, SCROLL_TOP)
	scroll.size = Vector2(1920 - FORM_MARGIN * 2, SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	scroll.add_child(columns)

	var left := _column(columns, LEFT_COLUMN_WIDTH)
	var right := _column(columns, RIGHT_COLUMN_WIDTH)

	# ---- left: template + spawn settings ----
	_heading(left, "TEMPLATE")
	_template_opt = OptionButton.new()
	_template_opt.fit_to_longest_item = false
	_template_opt.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	for key in OverworldPokemonData.TEMPLATES:
		# An existing spawn point can change template, but can't become the map-wide
		# flyer table -- that has no position.
		if key == "flyer" and not _is_new:
			continue
		_template_opt.add_item(OverworldPokemonData.TEMPLATE_LABELS[key])
		_template_opt.set_item_metadata(_template_opt.item_count - 1, key)
	_select_option(_template_opt, _template)
	_template_opt.item_selected.connect(func(idx: int):
		var previous := _template
		# Before _template changes: it decides which set of tables this goes back into.
		_store_time_table(_tables_for(previous))
		_template = str(_template_opt.get_item_metadata(idx))
		_on_template_switched(previous))
	_rows["template"] = _add_row(left, "Template", _template_opt)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(LEFT_COLUMN_WIDTH, 0)
	_desc.add_theme_font_size_override("font_size", FORM_FONT_SIZE - 2)
	_desc.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
	left.add_child(_desc)

	_heading(left, "SPAWNING")
	# Which of the four time-of-day tables the chance, interval and species list below
	# belong to. Every template has four.
	_time_opt = OptionButton.new()
	_time_opt.fit_to_longest_item = false
	_time_opt.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		_time_opt.add_item(time_name)
		_time_opt.set_item_metadata(_time_opt.item_count - 1, time_name)
	_time_opt.item_selected.connect(func(idx: int):
		_show_time_table(str(_time_opt.get_item_metadata(idx))))
	_rows["time"] = _add_row(left, "Table for", _time_opt)

	_chance = _spin(0, 100, 1, OverworldPokemonData.POINT_DEFAULT_CHANCE, " %")
	_chance.value_changed.connect(func(_v: float): _revalidate())
	var chance_row := _add_row(left, "Chance", _chance)
	_rows["chance"] = chance_row
	_chance_label = chance_row.get_child(0)

	_interval = _spin(0.5, 3600, 0.5, OverworldPokemonData.POINT_DEFAULT_INTERVAL, " s")
	_rows["interval"] = _add_row(left, "Roll every", _interval)

	_up_time = _spin(0, 120, 0.5, 0, " s")
	_rows["up_time"] = _add_row(left, "Up time (0 = species)", _up_time)

	_pattern_opt = OptionButton.new()
	_pattern_opt.fit_to_longest_item = false
	_pattern_opt.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	for pattern in OverworldPokemonData.STATIC_PATTERNS:
		_pattern_opt.add_item(pattern)
		_pattern_opt.set_item_metadata(_pattern_opt.item_count - 1, pattern)
	_pattern_opt.item_selected.connect(func(_i: int): _on_template_changed())
	_rows["pattern"] = _add_row(left, "Pattern", _pattern_opt)
	_distance = _spin(4, 1000, 1, PokemonStatic.DEFAULT_DISTANCE, " px")
	_rows["distance"] = _add_row(left, "Patrol distance", _distance)
	_speed = _spin(4, 400, 1, PokemonStatic.DEFAULT_SPEED, " px/s")
	_rows["speed"] = _add_row(left, "Patrol speed", _speed)
	_axis_opt = OptionButton.new()
	_axis_opt.fit_to_longest_item = false
	_axis_opt.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	for axis in ["horizontal", "vertical"]:
		_axis_opt.add_item(axis)
		_axis_opt.set_item_metadata(_axis_opt.item_count - 1, axis)
	_rows["axis"] = _add_row(left, "Patrol axis", _axis_opt)

	# Skittish only: which ways it is ALLOWED to bolt when the player gets close. Out of
	# the ticked ones it takes whichever heads away from the player.
	var flee_line := HBoxContainer.new()
	flee_line.add_theme_constant_override("separation", 12)
	for direction in OverworldPokemonData.SKITTISH_FLEE_DIRECTIONS:
		var box := CheckBox.new()
		box.text = str(direction).capitalize()
		box.button_pressed = true
		box.tooltip_text = "Let it run " + str(direction) + " to get away from the player."
		box.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		flee_line.add_child(box)
		_flee_boxes[str(direction)] = box
	_rows["flee"] = _add_row(left, "Runs away", flee_line)
	_into_water = CheckBox.new()
	_into_water.tooltip_text = "It runs until it hits something (water edges have collision), " \
			+ "pauses, leaps in with a splash and sinks, instead of fading out as it runs."
	_into_water.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_rows["into_water"] = _add_row(left, "Jumps into water", _into_water)

	# ANY template: put this point's Pokémon INSIDE the aquarium it stands in. Indoors
	# nothing has a z_index -- the glass, the sand and the player are all z 0 and the
	# scene tree's order is the draw order -- so a ticked point is parented one place
	# before that tank's glass at z 0 instead of over the whole map. Which tank is worked
	# out from where the point is (OverworldPokemonSpawner._tank_front_at). A fish tank
	# is always in one, so the box is hidden for that template.
	_in_tank = CheckBox.new()
	_in_tank.tooltip_text = "Draw this point's Pokémon behind the glass of the fish tank it stands " \
			+ "in, instead of over the map -- for putting a bug, an idle Pokémon or a patrol inside " \
			+ "an aquarium. The tank is found automatically; if the point is not inside one, the " \
			+ "nearest is used."
	_in_tank.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_rows["in_tank"] = _add_row(left, "In fish tank", _in_tank)

	# ---- right: species table ----
	_heading(right, "SPECIES TABLE")
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 12)
	var add_template := Button.new()
	add_template.text = "ADD FROM TEMPLATE"
	add_template.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	add_template.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_template.pressed.connect(func(): _open_picker(false))
	add_row.add_child(add_template)
	var add_any := Button.new()
	add_any.text = "ADD ANY POKÉMON"
	add_any.tooltip_text = "Any of the sprites. One not yet in this template is added to it in Overworld_Pokemon.json on save."
	add_any.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	add_any.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_any.pressed.connect(func(): _open_picker(true))
	add_row.add_child(add_any)
	right.add_child(add_row)

	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	right.add_child(_total_label)

	_table_box = VBoxContainer.new()
	_table_box.add_theme_constant_override("separation", 6)
	_table_box.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH, 0)
	right.add_child(_table_box)

	# ---- footer ----
	_status = Label.new()
	_status.position = Vector2(FORM_MARGIN, FOOTER_TOP)
	_status.size = Vector2(1060, FOOTER_HEIGHT)
	_status.clip_text = true
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_root.add_child(_status)

	if not _is_new:
		var delete_btn := Button.new()
		delete_btn.text = "DELETE POINT"
		delete_btn.position = Vector2(1140, FOOTER_TOP)
		delete_btn.size = Vector2(240, FOOTER_HEIGHT)
		delete_btn.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		delete_btn.add_theme_color_override("font_color", Color(0.75, 0.1, 0.1))
		delete_btn.pressed.connect(_delete)
		_root.add_child(delete_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "CONFIRM"
	_confirm_btn.position = Vector2(1400, FOOTER_TOP)
	_confirm_btn.size = Vector2(220, FOOTER_HEIGHT)
	_confirm_btn.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_confirm_btn.pressed.connect(_confirm)
	_root.add_child(_confirm_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "CANCEL"
	_cancel_btn.position = Vector2(1640, FOOTER_TOP)
	_cancel_btn.size = Vector2(220, FOOTER_HEIGHT)
	_cancel_btn.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_cancel_btn.pressed.connect(_cancel)
	_root.add_child(_cancel_btn)


func _column(parent: Control, width: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(col)
	return col


func _heading(col: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE + 3)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(label)


func _add_row(col: VBoxContainer, label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	col.add_child(row)
	return row


func _spin(min_value: float, max_value: float, step: float, value: float, suffix: String = "") -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.suffix = suffix
	spin.add_theme_constant_override("buttons_width", SPIN_BUTTONS_WIDTH)
	var field := spin.get_line_edit()
	field.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	# custom_minimum_size is only a floor: a LineEdit refuses to go narrower than
	# `minimum_character_width` (4 "M"s) plus its stylebox's side padding, so without
	# these the box widths above were silently ignored and every row ran off the right
	# edge, taking the bin button with it.
	field.add_theme_constant_override("minimum_character_width", 0)
	for state in ["normal", "focus", "read_only"]:
		var box := DebugFormTheme._flat(DebugFormTheme.PAPER_DISABLED if state == "read_only" else DebugFormTheme.PAPER,
				DebugFormTheme.FOCUS_BORDER if state == "focus" else Color(0, 0, 0, 0), 2 if state == "focus" else 0)
		box.content_margin_left = SPIN_FIELD_PADDING
		box.content_margin_right = SPIN_FIELD_PADDING
		field.add_theme_stylebox_override(state, box)
	return spin


func _select_option(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i)) == value:
			option.select(i)
			return


func _option_value(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


# ============================================================
# TEMPLATE SWITCHING
# ============================================================

## The flyer tables are the map's and a point's tables are its own, so crossing
## between flyer and a point template swaps which set is on screen (edits to both are
## kept). Point template to point template keeps the same tables.
func _on_template_switched(previous: String) -> void:
	# Crossing between the map's flyer tables, a point's four time tables and a tank's
	# single one swaps which table is on screen; the ones left behind keep their edits.
	var tank := OverworldPokemonData.TANK_TEMPLATE
	if (previous == "flyer") != (_template == "flyer") or (previous == tank) != (_template == tank):
		_enter_time_tables()
	_on_template_changed()


func _on_template_changed() -> void:
	var is_flyer := _template == "flyer"
	var is_static := _template == "static"
	if _fish_mode:
		_on_fish_mode_changed()
		return
	if is_flyer:
		_title.text = "FLYER TABLES  —  %s" % _map_data
	elif _is_new:
		_title.text = "NEW POKÉMON SPAWN  —  %s" % _map_data
	else:
		_title.text = "EDIT POKÉMON SPAWN  —  %s" % str(_original.get("id", "?"))
		var linked := _group_size()
		if linked > 1:
			_title.text += "   (linked: edits apply to all %d)" % linked
	# Flyer tables have no position to place, so SAVE writes straight away and the
	# screen stays up; a spawn point is still handed to the tool to be placed.
	_confirm_btn.text = "SAVE" if is_flyer else "CONFIRM"
	_cancel_btn.text = "CLOSE" if is_flyer else "CANCEL"
	if is_flyer:
		_scope.text = "SAVE writes Pokemon/Spawns/%s.json straight away and keeps this screen open" % _map_data
	else:
		_scope.text = "Confirm hands this to the placement tool — Enter there writes Pokemon/Spawns/%s.json" % _map_data
	_desc.text = OverworldPokemonData.TEMPLATE_DESCRIPTIONS.get(_template, "")
	if is_flyer:
		_chance_label.text = "Chance per roll"
	elif OverworldPokemonData.TIMED_TEMPLATES.has(_template):
		_chance_label.text = "Chance per roll"
	else:
		_chance_label.text = "Chance per map load"
	_rows["interval"].visible = OverworldPokemonData.TEMPLATE_USES_INTERVAL.has(_template)
	_rows["up_time"].visible = _template == "burying"
	_rows["pattern"].visible = is_static
	var patrols := is_static and _option_value(_pattern_opt).begins_with("patrol")
	_rows["distance"].visible = patrols
	_rows["speed"].visible = patrols
	_rows["axis"].visible = is_static and _option_value(_pattern_opt) == "patrol_line"
	_rows["flee"].visible = _template == "skittish"
	_rows["into_water"].visible = _template == "skittish"
	# A tank has one table and puts every row of it out: no time of day, no chance.
	# Any template can be put in a tank; a fish tank is in one by definition.
	_rows["in_tank"].visible = not is_flyer and not _is_tank()
	_rows["time"].visible = not _is_tank()
	_rows["chance"].visible = not _is_tank()
	_rebuild_table()


## FISH TABLE mode. A cast always hooks exactly one fish, so there is no spawn chance,
## no roll interval and no template to choose -- the whole left column collapses to the
## time-of-day picker.
func _on_fish_mode_changed() -> void:
	_title.text = "FISH TABLE  —  %s" % _map_data
	_confirm_btn.text = "SAVE"
	_cancel_btn.text = "CLOSE"
	_scope.text = "SAVE writes Pokemon/Spawns/%s.json straight away and keeps this screen open" % _map_data
	_desc.text = "Which Pokémon can be hooked here, by time of day. A cast always rolls " \
			+ "exactly one fish, so there is no spawn chance — an empty table just means " \
			+ "nothing bites then. The six boxes after Scale are that fish's fight, and like " 			+ "Scale they belong to the species: the same on every map and time of day."
	for key in _rows:
		(_rows[key] as Control).visible = false
	_rebuild_table()


## How many spawn points share the edited point's group, itself included. Confirming
## rewrites the rules of every one of them (PlacementTool._on_pokemon_editor_confirmed).
func _group_size() -> int:
	var group := str(_original.get("group", _original.get("id", "")))
	var count := 0
	for other in _doc.get("spawn_points", []):
		if other is Dictionary and str(other.get("group", other.get("id", ""))) == group:
			count += 1
	return count


# ============================================================
# TIME-OF-DAY TABLES
# ============================================================

## Flyers edit the map's four tables; spawn points edit their own four; the fish table
## is the map's too.
func _tables_for(template: String) -> Dictionary:
	if _fish_mode:
		return _fish_tables
	return _flyer_tables if template == "flyer" else _point_tables


## A fish tank: one table, no time of day, no chance -- everything in the table is put
## out at once. Enough of this form works differently for it to be worth asking.
func _is_tank() -> bool:
	return not _fish_mode and _template == OverworldPokemonData.TANK_TEMPLATE


## Flyer and fish tables belong to the map and have nowhere to be placed, so SAVE writes
## the file straight away and the form stays open. A spawn point is handed to the tool.
func _saves_in_place() -> bool:
	return _fish_mode or _template == "flyer"


## Fill in whichever set of tables the template uses (once -- edits survive switching
## template away and back) and show the same time of day as before, or the game's
## current time the first time round.
func _enter_time_tables() -> void:
	if _is_tank():
		# One table, and it is the point's own.
		_table = _tank_table
		_rebuild_table()
		return
	if _fish_mode:
		if _fish_tables.is_empty():
			_fish_tables = OverworldPokemonData.normalise_fishing(_doc.get("fishing")).duplicate(true)
	elif _template == "flyer":
		if _flyer_tables.is_empty():
			_flyer_tables = OverworldPokemonData.normalise_flyers(_doc.get("flyers")).duplicate(true)
	elif _point_tables.is_empty():
		_point_tables = OverworldPokemonData.normalise_point_tables({})
	var target := _table_time
	if target == "":
		var now := str(GameState.get_time())
		target = now if OverworldPokemonData.TIMES_OF_DAY.has(now) else str(OverworldPokemonData.TIMES_OF_DAY[0])
	# Cleared first: the outgoing table was already stored, and storing again here
	# would write the old template's values into the new set of tables.
	_table_time = ""
	_show_time_table(target)
	if _saves_in_place() and _flyer_saved_json == "":
		_flyer_saved_json = _flyer_json()


## Put the on-screen chance, interval and rows back into their time's table.
func _store_time_table(tables: Dictionary) -> void:
	# A tank's table is not one of a set of four: it is already _tank_table.
	if _is_tank() or _table_time == "":
		return
	tables[_table_time] = {
		"interval": _interval.value,
		"chance": _chance.value,
		"table": _table,
	}


func _show_time_table(time_name: String) -> void:
	if _is_tank():
		return
	var tables := _tables_for(_template)
	_store_time_table(tables)
	_table_time = time_name
	var config = tables.get(time_name)
	if not (config is Dictionary):
		config = OverworldPokemonData.default_flyer_table() if _template == "flyer" \
				else OverworldPokemonData.default_point_table()
		tables[time_name] = config
	if not (config.get("table") is Array):
		config["table"] = []
	_table = config["table"]
	_chance.value = float(config.get("chance", 0))
	_interval.value = float(config.get("interval", OverworldPokemonData.POINT_DEFAULT_INTERVAL))
	_select_option(_time_opt, time_name)
	_rebuild_table()


## A time's species rows; the table on screen is the live _table.
func _time_rows(time_name: String) -> Array:
	if time_name == _table_time:
		return _table
	var rows = OverworldPokemonData.time_table(_tables_for(_template), time_name).get("table", [])
	return rows if rows is Array else []


## Every row across all four tables.
func _all_rows() -> Array:
	if _is_tank():
		return _tank_table
	var out: Array = []
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		out.append_array(_time_rows(str(time_name)))
	return out


## The four tables as the file stores them. `interval` is only kept where the
## template rolls on a timer.
func _draft_tables() -> Dictionary:
	var tables := _tables_for(_template)
	_store_time_table(tables)
	var out: Dictionary = {}
	if _fish_mode:
		# Species rows and nothing else -- no chance, no interval.
		for time_name in OverworldPokemonData.TIMES_OF_DAY:
			out[time_name] = {"table": _clean_rows(_time_rows(str(time_name)))}
		return out
	var uses_interval := OverworldPokemonData.TEMPLATE_USES_INTERVAL.has(_template)
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		var config := OverworldPokemonData.time_table(tables, str(time_name))
		var clean: Dictionary = {"chance": snappedf(float(config.get("chance", 0)), 0.1)}
		if uses_interval:
			clean["interval"] = snappedf(float(config.get("interval", OverworldPokemonData.POINT_DEFAULT_INTERVAL)), 0.1)
		clean["table"] = _clean_rows(_time_rows(str(time_name)))
		out[time_name] = clean
	return out


# ============================================================
# SPECIES TABLE
# ============================================================

func _template_species() -> Array:
	var names: Dictionary = {}
	for species in OverworldPokemonData.species_for_template(_template):
		names[species] = true
	for species in _known_additions:
		if (_known_additions[species] as Array).has(_template):
			names[species] = true
	var out: Array = names.keys()
	out.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


func _open_picker(any: bool) -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	var only: Array = []
	if not any:
		only = _template_species()
		if only.is_empty():
			_status.text = "No Pokémon are assigned to this template yet — use ADD ANY POKÉMON."
			return
	var in_table: Dictionary = {}
	for row in _table:
		in_table[str(row.get("species", ""))] = true
	_picker = AssetPickerOverlay.new()
	get_tree().current_scene.add_child(_picker)
	_picker.picked.connect(_add_species)
	_picker.setup(AssetPickerOverlay.Kind.POKEMON, "", in_table, false, only)


func _add_species(species: String) -> void:
	var total := OverworldPokemonData.table_total(_table)
	var percent := 100.0 - total
	if percent <= 0.0:
		percent = 10.0
	var entry := {"species": species, "percent": roundf(percent)}
	if _is_tank():
		# A tank row is how MANY of that fish, not how often it is picked.
		entry = {"species": species, "count": OverworldPokemonData.DEFAULT_TANK_COUNT}
	if _template == "flyer":
		_fill_flyer_defaults(entry)
	_table.append(entry)
	_rebuild_table()


func _rebuild_table() -> void:
	for child in _table_box.get_children():
		_table_box.remove_child(child)
		child.queue_free()
	var known := _template_species()
	var is_flyer := _template == "flyer"
	for i in _table.size():
		var entry: Dictionary = _table[i]
		var species := str(entry.get("species", ""))
		# One line per species. Every piece before REMOVE has a fixed width, so each
		# box sits at the same x on every row.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FISH_STAT_GAP if _fish_mode else ROW_ITEM_GAP)

		var icon := TextureRect.new()
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = AssetPickerOverlay.pokemon_frame(species)
		row.add_child(icon)

		var name_label := _caption(row, OverworldPokemonData.display_name(species))
		name_label.custom_minimum_size = Vector2(FISH_NAME_WIDTH if _fish_mode else NAME_WIDTH, 0)
		name_label.clip_text = true
		name_label.tooltip_text = species
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		if not known.has(species) and not _fish_mode:
			# Orange + "*" rather than a long suffix, which would push the columns out.
			name_label.text += " *"
			name_label.tooltip_text = species + " -- new to this template, added to it on save"
			name_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))

		if _is_tank():
			# No rate: a tank puts out every row. The number is how many of them.
			_caption(row, "Count")
			var count := _spin(1, OverworldPokemonData.TANK_COUNT_LIMIT, 1,
					float(entry.get("count", OverworldPokemonData.DEFAULT_TANK_COUNT)))
			count.tooltip_text = "How many of this Pokémon swim in this tank. They are all the species' size, each nudged up to 10% either way — and the same tankful in another aquarium comes out the same."
			count.custom_minimum_size = Vector2(PERCENT_SPIN_WIDTH, 0)
			count.value_changed.connect(func(v: float):
				entry["count"] = int(v)
				_revalidate())
			row.add_child(count)
		else:
			_caption(row, "Rate")
			var percent := _spin(0, 100, 1, float(entry.get("percent", 0)), "" if _fish_mode else "%")
			percent.tooltip_text = "How often this species is picked, as a share of the table"
			percent.custom_minimum_size = Vector2(FISH_PERCENT_SPIN_WIDTH if _fish_mode else PERCENT_SPIN_WIDTH, 0)
			percent.value_changed.connect(func(v: float):
				entry["percent"] = v
				_revalidate())
			row.add_child(percent)

		# On a FISH row, Scale edits `fish_size` -- how big the hooked silhouette is
		# drawn -- and deliberately leaves the shared `scale` key alone: the fishing art
		# is already the right size, and `scale` is what the overworld spawns use.
		_caption(row, "Scale")
		var settings := _settings_for(species)
		var scale_key := "fish_size" if _fish_mode else "scale"
		var scale_low := OverworldPokemonData.MIN_SCALE
		var scale_high := OverworldPokemonData.MAX_SCALE
		if _fish_mode:
			var scale_limits: Array = OverworldPokemonData.FISH_STAT_LIMITS["fish_size"]
			scale_low = float(scale_limits[0])
			scale_high = float(scale_limits[1])
		var scale_box := _spin(scale_low, scale_high, 0.1,
				float(settings[scale_key]), "" if _fish_mode else "x")
		scale_box.tooltip_text = ("Multiplier on the hooked fish silhouette (1.0 = as drawn, 0.8 a fifth smaller). Belongs to the species."
				if _fish_mode
				else "Size on the map (1.0 = normal). Belongs to the species: the same on every table and map.")
		scale_box.custom_minimum_size = Vector2(FISH_SCALE_SPIN_WIDTH if _fish_mode else SCALE_SPIN_WIDTH, 0)
		scale_box.value_changed.connect(func(v: float): settings[scale_key] = snappedf(v, 0.1))
		row.add_child(scale_box)

		if is_flyer:
			_add_flyer_controls(row, entry)
		elif _template == "skittish":
			_add_wander_control(row, species)
		elif _fish_mode:
			_add_fish_controls(row, species)
		elif _template == "surfacing":
			_add_swim_control(row, species)
		elif _is_tank():
			_add_tank_control(row, species)

		# Pushes REMOVE to the right edge, so it lines up too.
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		# A bin, like the deck builder's delete-deck button, instead of the word REMOVE.
		var remove := Button.new()
		remove.tooltip_text = "Remove %s from this table" % OverworldPokemonData.display_name(species)
		remove.custom_minimum_size = Vector2(REMOVE_BUTTON_SIZE, REMOVE_BUTTON_SIZE)
		remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# MOUSE_FILTER_IGNORE so the glyph never eats the click meant for the button.
		var bin := Control.new()
		bin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bin.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Dark ink: the debug form's buttons are white.
		bin.draw.connect(func(): UIKit.draw_trash_icon(bin, DebugFormTheme.INK))
		remove.add_child(bin)
		remove.pressed.connect(func():
			_table.erase(entry)
			_rebuild_table())
		row.add_child(remove)

		_table_box.add_child(row)
	_revalidate()


## The fish-only part of a species row, added in place after Scale: one captioned number
## box per fight stat. Like Scale and a flyer's Speed these write the SPECIES' settings,
## not the row -- the same fight on every table, map and time of day. Distances and
## speeds are world pixels: on-screen pixels / 2.5, the overworld's zoom.
func _add_fish_controls(line: HBoxContainer, species: String) -> void:
	var settings := _settings_for(species)
	# Which of the two silhouette sets it is hooked as. Species-wide like the rest.
	_flag_box(line, settings, "big", "Big",
			"Hooks as one of the BIG fish silhouettes instead of the small ones. Same on every table and map.")
	for key in OverworldPokemonData.FISH_STAT_LABELS:
		var stat_key := str(key)
		var limits: Array = OverworldPokemonData.FISH_STAT_LIMITS[stat_key]
		_caption(line, str(OverworldPokemonData.FISH_STAT_LABELS[stat_key]))
		var box := _spin(float(limits[0]), float(limits[1]), float(limits[2]),
				float(settings[stat_key]))
		box.tooltip_text = str(FISH_STAT_TIPS[stat_key])
		box.custom_minimum_size = Vector2(FISH_STAT_SPIN_WIDTH, 0)
		box.value_changed.connect(func(v: float): settings[stat_key] = v)
		line.add_child(box)


## Flock size for a flyer row that doesn't have one yet. (Speed, scale, spin and
## erratic are species-wide -- see _settings_for.)
func _fill_flyer_defaults(entry: Dictionary) -> void:
	var defaults := {
		"min": OverworldPokemonData.DEFAULT_FLOCK_MIN,
		"max": OverworldPokemonData.DEFAULT_FLOCK_MAX,
	}
	for key in defaults:
		if not entry.has(key):
			entry[key] = defaults[key]


## The flyer-only part of a species row, added in place after Scale:
## Flock [min]–[max]  Speed [min]–[max]  [x] Spin  [x] Erratic   (speed in px/s)
func _add_flyer_controls(line: HBoxContainer, entry: Dictionary) -> void:
	_fill_flyer_defaults(entry)
	_range_pair(line, "Flock", entry, "min", "max", OverworldPokemonData.FLOCK_LIMIT,
			FLOCK_SPIN_WIDTH, "flock of this species")
	# Writes the species' settings, not the row: the same speed on every table and map.
	_range_pair(line, "Speed", _settings_for(str(entry.get("species", ""))), "speed_min", "speed_max",
			OverworldPokemonData.FLYER_SPEED_LIMIT, SPEED_SPIN_WIDTH,
			"speed (px/s) this species flies at, on every table and map")
	# Species-wide, like Speed: ticking Spin here makes it spin on every table and map.
	var settings := _settings_for(str(entry.get("species", "")))
	_flag_box(line, settings, "spin", "Spin",
			"Turns round and round as it flies, faster the faster it flies. Same on every table and map.")
	var styles: Array = [
		_flag_box(line, settings, "erratic", "Erratic",
				"A big, jerky up-and-down bob instead of the gentle one -- bat-like flight. Same on every table and map."),
		_flag_box(line, settings, "bug", "Bug",
				"A smaller, smoother wobble that speeds up and slows down as it goes -- butterfly flight. Same on every table and map."),
		_flag_box(line, settings, "ghost", "Ghost",
				"Slow, wide drifting that fades out and back in every 5-15 seconds. Same on every table and map."),
	]
	# Erratic, Bug and Ghost are alternative movement styles: ticking one clears the others.
	for box in styles:
		var this_box: CheckBox = box
		this_box.toggled.connect(func(on: bool):
			if not on:
				return
			for other in styles:
				if other != this_box:
					(other as CheckBox).button_pressed = false)


## The species-wide settings for `species`, filled in from the registry the first time
## it is asked for. The boxes write straight into this dictionary.
func _settings_for(species: String) -> Dictionary:
	var settings: Dictionary = _species_settings.get(species, {})
	var speed_range := OverworldPokemonData.species_speed_range(species)
	var saved := {
		"speed_min": speed_range.x,
		"speed_max": speed_range.y,
		"scale": OverworldPokemonData.species_scale(species),
		"wander_speed": int(OverworldPokemonData.species_wander_speed(species)),
		"swim_speed": int(OverworldPokemonData.species_swim_speed(species)),
		"tank_speed": int(OverworldPokemonData.species_tank_speed(species)),
		"spin": bool(OverworldPokemonData.species_info(species).get("spin", false)),
		"erratic": bool(OverworldPokemonData.species_info(species).get("erratic", false)),
		"bug": bool(OverworldPokemonData.species_info(species).get("bug", false)),
		"ghost": bool(OverworldPokemonData.species_info(species).get("ghost", false)),
		"big": OverworldPokemonData.species_big_fish(species),
	}
	# The six fishing numbers, already filled in and clamped by fish_stats().
	var fighting := OverworldPokemonData.fish_stats(species)
	for key in fighting:
		saved[key] = fighting[key]
	for key in saved:
		if not settings.has(key):
			settings[key] = saved[key]
	_species_settings[species] = settings
	return settings


## Species settings that differ from what the registry already says -> the draft.
func _changed_species_settings() -> Dictionary:
	var out: Dictionary = {}
	for species in _species_settings:
		var settings := _settings_for(str(species))
		var speed_range := OverworldPokemonData.species_speed_range(str(species))
		var changes: Dictionary = {}
		if int(settings["speed_min"]) != speed_range.x:
			changes["speed_min"] = int(settings["speed_min"])
		if int(settings["speed_max"]) != speed_range.y:
			changes["speed_max"] = int(settings["speed_max"])
		var scale_now := snappedf(float(settings["scale"]), 0.1)
		if not is_equal_approx(scale_now, OverworldPokemonData.species_scale(str(species))):
			changes["scale"] = scale_now
		if int(settings["wander_speed"]) != int(OverworldPokemonData.species_wander_speed(str(species))):
			changes["wander_speed"] = int(settings["wander_speed"])
		if int(settings["swim_speed"]) != int(OverworldPokemonData.species_swim_speed(str(species))):
			changes["swim_speed"] = int(settings["swim_speed"])
		if int(settings["tank_speed"]) != int(OverworldPokemonData.species_tank_speed(str(species))):
			changes["tank_speed"] = int(settings["tank_speed"])
		var info := OverworldPokemonData.species_info(str(species))
		for flag in ["spin", "erratic", "bug", "ghost", "big"]:
			if bool(settings[flag]) != bool(info.get(flag, false)):
				changes[flag] = bool(settings[flag])
		# Fishing. Written out whenever the species HAS an entry for them or the box has
		# been moved off the default, so a fish that was never edited stays absent from
		# the registry rather than gaining six keys it does not need.
		var fighting := OverworldPokemonData.fish_stats(str(species))
		for key in fighting:
			var now := snappedf(float(settings[key]), 0.1)
			if not is_equal_approx(now, float(fighting[key])):
				changes[key] = now
		if not changes.is_empty():
			out[species] = changes
	return out


## Skittish rows: the species' wandering speed (world px/s), the same on every table and
## map. Running away is always the fixed, faster-than-the-player FLEE_SPEED.
func _add_wander_control(line: HBoxContainer, species: String) -> void:
	var settings := _settings_for(species)
	_caption(line, "Wander")
	var box := _spin(0, OverworldPokemonData.WANDER_SPEED_LIMIT, 1, int(settings["wander_speed"]))
	box.tooltip_text = "Wandering speed (px/s) of this species, on every table and map. 0 stands still until scared. Running away is always fast."
	box.custom_minimum_size = Vector2(SPEED_SPIN_WIDTH, 0)
	box.value_changed.connect(func(v: float): settings["wander_speed"] = int(v))
	line.add_child(box)


## Fish tank rows: the species' cruising speed in the tank (world px/s), the same in
## every aquarium. Size is the Scale box, also species-wide -- the only thing that differs
## between two fish of a species is the small size wobble the spawner gives each one.
func _add_tank_control(line: HBoxContainer, species: String) -> void:
	var settings := _settings_for(species)
	_caption(line, "Swim")
	var box := _spin(0, OverworldPokemonData.TANK_SPEED_LIMIT, 1, int(settings["tank_speed"]))
	box.tooltip_text = "Cruising speed (px/s) of this species in any fish tank. 0 hovers on the spot."
	box.custom_minimum_size = Vector2(SPEED_SPIN_WIDTH, 0)
	box.value_changed.connect(func(v: float): settings["tank_speed"] = int(v))
	line.add_child(box)


## Surfacing rows: the species' swimming speed while it is up (world px/s), the same on
## every table and map. 0 surfaces, stays put and submerges.
func _add_swim_control(line: HBoxContainer, species: String) -> void:
	var settings := _settings_for(species)
	_caption(line, "Swim")
	var box := _spin(0, OverworldPokemonData.SWIM_SPEED_LIMIT, 1, int(settings["swim_speed"]))
	box.tooltip_text = "Swimming speed (px/s) of this species while surfaced, on every table and map. 0 stays put."
	box.custom_minimum_size = Vector2(SPEED_SPIN_WIDTH, 0)
	box.value_changed.connect(func(v: float): settings["swim_speed"] = int(v))
	line.add_child(box)


## A vertically-centred text label added to a row.
func _caption(line: HBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	line.add_child(label)
	return label


## The ticked "Runs away" directions, in SKITTISH_FLEE_DIRECTIONS order. None ticked is
## no constraint at all rather than "it cannot run", so it saves all four.
func _flee_selection() -> Array:
	var allowed: Array = []
	for direction in OverworldPokemonData.SKITTISH_FLEE_DIRECTIONS:
		var box: CheckBox = _flee_boxes.get(direction)
		if box != null and box.button_pressed:
			allowed.append(direction)
	return allowed if not allowed.is_empty() else OverworldPokemonData.SKITTISH_FLEE_DIRECTIONS.duplicate()


## A tick box writing true / false to `key` on `entry`.
func _flag_box(line: HBoxContainer, entry: Dictionary, key: String, text: String, tip: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.tooltip_text = tip
	box.button_pressed = bool(entry.get(key, false))
	box.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	box.toggled.connect(func(on: bool): entry[key] = on)
	line.add_child(box)
	return box


## "Caption [low] – [high]", each box writing its key on `entry`.
func _range_pair(line: HBoxContainer, caption: String, entry: Dictionary, low_key: String,
		high_key: String, limit: int, width: int, what: String) -> void:
	var label := Label.new()
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	line.add_child(label)
	for key in [low_key, high_key]:
		var field_key := str(key)
		if field_key == high_key:
			var dash := Label.new()
			dash.text = "–"
			dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dash.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
			line.add_child(dash)
		var box := _spin(1, limit, 1, int(entry[field_key]))
		box.tooltip_text = ("Lowest " if field_key == low_key else "Highest ") + what
		box.custom_minimum_size = Vector2(width, 0)
		box.value_changed.connect(func(v: float):
			entry[field_key] = int(v)
			_revalidate())
		line.add_child(box)


# ============================================================
# VALIDATION + DRAFT
# ============================================================

func _problems() -> Array:
	var out: Array = []
	if _is_tank():
		# No percentages to add up: a tank puts out everything in its table.
		if _tank_table.is_empty():
			out.append("add a Pokémon to the tank")
		return out
	var any_rows := false
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		var rows := _time_rows(str(time_name))
		# An empty table is fine -- nothing spawns at that time of day.
		if rows.is_empty():
			continue
		any_rows = true
		if OverworldPokemonData.table_total(rows) <= 0.0:
			out.append("%s: percentages are all 0" % time_name)
		if _template == "flyer":
			for row in rows:
				var bird := OverworldPokemonData.display_name(str(row.get("species", "")))
				if int(row.get("min", 1)) > int(row.get("max", 1)):
					out.append("%s: %s flock min is bigger than max" % [time_name, bird])
				var speeds := _settings_for(str(row.get("species", "")))
				if int(speeds["speed_min"]) > int(speeds["speed_max"]):
					out.append("%s: %s speed min is bigger than max" % [time_name, bird])
	# A map with no flyers and no fish is fine; a spawn point that can never spawn is not.
	if not any_rows and not _saves_in_place():
		out.append("add a Pokémon to at least one time of day")
	return out


func _revalidate() -> void:
	if _total_label != null and _is_tank():
		var heads := 0
		for row in _tank_table:
			heads += clampi(int(row.get("count", 1)), 1, OverworldPokemonData.TANK_COUNT_LIMIT)
		var caption := "This tank holds %d fish." % heads if heads > 0 else "The tank is empty — add a Pokémon."
		_total_label.text = caption
		_total_label.add_theme_color_override("font_color",
				Color(0.55, 0.95, 0.55) if heads > 0 else Color(0.8, 0.84, 0.92))
	elif _total_label != null:
		var total := OverworldPokemonData.table_total(_table)
		if _table.is_empty():
			_total_label.text = "%s table is empty — nothing spawns then." % _table_time
			_total_label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
		elif is_equal_approx(total, 100.0):
			_total_label.text = "%s table total: 100%%" % _table_time
			_total_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
		else:
			_total_label.text = "%s table total: %s%%  (scaled to 100%% when rolled)" % [_table_time, str(snappedf(total, 0.1))]
			_total_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	if _status == null:
		return
	var problems := _problems()
	if problems.is_empty():
		_status.text = "Ready."
		_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		_status.text = "; ".join(problems)
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	if _confirm_btn != null:
		_confirm_btn.disabled = not problems.is_empty()


## Species in the table that this template doesn't list yet -> [template]. The
## placement tool appends them to Overworld_Pokemon.json when it saves.
func _registry_additions() -> Dictionary:
	var known := _template_species()
	var out: Dictionary = {}
	for row in _all_rows():
		var species := str(row.get("species", ""))
		if species != "" and not known.has(species):
			out[species] = [_template]
	return out


## A tank's rows as the file stores them: species and count, nothing else. Speed and
## size belong to the species, so they go to the registry, not onto the point.
func _clean_tank_rows() -> Array:
	var out: Array = []
	for row in _tank_table:
		var species := str(row.get("species", ""))
		if species == "":
			continue
		out.append({
			"species": species,
			"count": clampi(int(row.get("count", OverworldPokemonData.DEFAULT_TANK_COUNT)),
					1, OverworldPokemonData.TANK_COUNT_LIMIT),
		})
	return out


func _clean_rows(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var clean := {"species": str(row.get("species", "")), "percent": snappedf(float(row.get("percent", 0)), 0.1)}
		if _template == "flyer":
			clean["min"] = int(row.get("min", OverworldPokemonData.DEFAULT_FLOCK_MIN))
			clean["max"] = int(row.get("max", OverworldPokemonData.DEFAULT_FLOCK_MAX))
		# A fish row is only {species, percent}: the fight numbers are the SPECIES' own
		# and go to the registry through _changed_species_settings(). Rebuilding the row
		# from scratch here is what drops any that an older save left on it.
		out.append(clean)
	return out


func _build_draft() -> Dictionary:
	# A tank has no time-of-day tables to gather up.
	var tables: Dictionary = {} if _is_tank() else _draft_tables()
	if _fish_mode:
		# No registry additions: a fish table may list any Pokémon, and writing them all
		# into the surfacing template would put them in the sea as well.
		return {
			"kind": "fishing",
			"fishing": tables,
			"registry_additions": {},
			"species_settings": _changed_species_settings(),
		}
	if _template == "flyer":
		return {
			"kind": "flyers",
			"flyers": tables,
			"registry_additions": _registry_additions(),
			"species_settings": _changed_species_settings(),
		}

	var id := str(_original.get("id", "")) if not _is_new \
			else OverworldPokemonData.next_point_id(_doc, _template)
	var point: Dictionary = {
		"id": id,
		"template": _template,
		"at": _original.get("at", [0, 0]),
		# The linked-clone group: kept on an edit, a brand new point starts its own.
		"group": str(_original.get("group", id)) if not _is_new else id,
	}
	# An area template's rectangle is set in the world (V), not in this form -- keep it.
	if OverworldPokemonData.REGION_TEMPLATES.has(_template) and _original.get("region") is Array:
		point["region"] = (_original["region"] as Array).duplicate()
	if _template == "burying" and _up_time.value > 0.0:
		point["up_time"] = snappedf(_up_time.value, 0.1)
	if _template == "skittish":
		point["flee"] = _flee_selection()
		point["into_water"] = _into_water.button_pressed
	if _template == "static":
		var pattern := _option_value(_pattern_opt)
		point["pattern"] = pattern
		if pattern.begins_with("patrol"):
			point["distance"] = int(_distance.value)
			point["speed"] = int(_speed.value)
		if pattern == "patrol_line":
			point["axis"] = _option_value(_axis_opt)
	if _is_tank():
		# The one point template with no time-of-day tables at all.
		point["fish_table"] = _clean_tank_rows()
	else:
		point["tables"] = tables
	# Any template may be put inside a tank. A fish tank always is, so it does not carry
	# the key, and an unticked point leaves it off altogether rather than writing false.
	if _in_tank.button_pressed and not _is_tank():
		point["in_tank"] = true
	return {
		"kind": "point",
		"is_new": _is_new,
		"original_id": str(_original.get("id", "")),
		"point": point,
		"delete": false,
		"registry_additions": _registry_additions(),
		"species_settings": _changed_species_settings(),
	}


# ============================================================
# EXIT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# The species picker sits on top and handles its own Escape.
	if _picker != null and is_instance_valid(_picker):
		return
	# ONLY Escape is consumed -- _input runs before GUI input, so consuming anything
	# else would stop the spin boxes being typed into (see CharacterEditor._input).
	if event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	if not _problems().is_empty():
		return
	if _saves_in_place():
		save_requested.emit(_build_draft())
		return
	confirmed.emit(_build_draft())
	queue_free()


## The placement tool's answer to save_requested.
func notify_saved(ok: bool) -> void:
	if not ok:
		_status.text = "Could not write Pokemon/Spawns/%s.json — see the output log." % _map_data
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		return
	_flyer_saved_json = _flyer_json()
	_close_armed = false
	# Species added with ADD ANY are in the registry now: drop their "(new to template)".
	# Before the status line, which the rebuild's revalidate would overwrite.
	_rebuild_table()
	_status.text = "Saved to Pokemon/Spawns/%s.json." % _map_data
	_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))


func _flyer_json() -> String:
	return JSON.stringify(_draft_tables())


func _delete() -> void:
	confirmed.emit({
		"kind": "point",
		"is_new": false,
		"original_id": str(_original.get("id", "")),
		"point": _original,
		"delete": true,
		"registry_additions": {},
	})
	queue_free()


func _cancel() -> void:
	# Flyer and fish tables: closing over edits made since the last SAVE asks once first.
	if _saves_in_place() and not _close_armed and _flyer_json() != _flyer_saved_json:
		_close_armed = true
		_status.text = "Unsaved changes — SAVE them, or CLOSE again to throw them away."
		_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		return
	cancelled.emit()
	queue_free()


## The picker is parented to the map scene, so it would outlive this form.
func _exit_tree() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null
