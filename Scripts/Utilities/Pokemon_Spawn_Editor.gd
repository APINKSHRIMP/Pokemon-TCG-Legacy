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
const DEFAULT_TEMPLATE := "rodent"

const FORM_FONT_SIZE := 21
const TITLE_FONT_SIZE := 32
const LABEL_WIDTH := 250
const FORM_MARGIN := 40
const COLUMN_WIDTH := 880
const COLUMN_GAP := 46
const ROW_GAP := 8
const ICON_SIZE := Vector2(56, 56)
## Widths of the flock and speed min / max boxes on a flyer row's second line.
const FLOCK_SPIN_WIDTH := 95
const SPEED_SPIN_WIDTH := 110
## How far the second line sits in from the left edge.
const FLYER_LINE_INDENT := 24
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
var _point_tables: Dictionary = {}
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
		known_additions: Dictionary = {}, open_flyers: bool = false) -> void:
	_map_data = map_data
	_doc = working_doc
	_original = point
	_is_new = point.is_empty()
	_known_additions = known_additions
	layer = 129
	if not _is_new:
		_template = str(point.get("template", DEFAULT_TEMPLATE))
	elif open_flyers:
		_template = "flyer"
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

	var left := _column(columns)
	var right := _column(columns)

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
	_add_row(left, "Template", _template_opt)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
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
	_add_row(left, "Table for", _time_opt)

	_chance = _spin(0, 100, 1, OverworldPokemonData.POINT_DEFAULT_CHANCE, " %")
	_chance.value_changed.connect(func(_v: float): _revalidate())
	var chance_row := _add_row(left, "Chance", _chance)
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
	_table_box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
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


func _column(parent: Control) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
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
	spin.get_line_edit().add_theme_font_size_override("font_size", FORM_FONT_SIZE)
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
	if (previous == "flyer") != (_template == "flyer"):
		_enter_time_tables()
	_on_template_changed()


func _on_template_changed() -> void:
	var is_flyer := _template == "flyer"
	var is_static := _template == "static"
	if is_flyer:
		_title.text = "FLYER TABLES  —  %s" % _map_data
	elif _is_new:
		_title.text = "NEW POKÉMON SPAWN  —  %s" % _map_data
	else:
		_title.text = "EDIT POKÉMON SPAWN  —  %s" % str(_original.get("id", "?"))
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
	_rebuild_table()


# ============================================================
# TIME-OF-DAY TABLES
# ============================================================

## Flyers edit the map's four tables; spawn points edit their own four.
func _tables_for(template: String) -> Dictionary:
	return _flyer_tables if template == "flyer" else _point_tables


## Fill in whichever set of tables the template uses (once -- edits survive switching
## template away and back) and show the same time of day as before, or the game's
## current time the first time round.
func _enter_time_tables() -> void:
	if _template == "flyer":
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
	if _template == "flyer" and _flyer_saved_json == "":
		_flyer_saved_json = _flyer_json()


## Put the on-screen chance, interval and rows back into their time's table.
func _store_time_table(tables: Dictionary) -> void:
	if _table_time == "":
		return
	tables[_table_time] = {
		"interval": _interval.value,
		"chance": _chance.value,
		"table": _table,
	}


func _show_time_table(time_name: String) -> void:
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
	var out: Array = []
	for time_name in OverworldPokemonData.TIMES_OF_DAY:
		out.append_array(_time_rows(str(time_name)))
	return out


## The four tables as the file stores them. `interval` is only kept where the
## template rolls on a timer.
func _draft_tables() -> Dictionary:
	var tables := _tables_for(_template)
	_store_time_table(tables)
	var uses_interval := OverworldPokemonData.TEMPLATE_USES_INTERVAL.has(_template)
	var out: Dictionary = {}
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
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var icon := TextureRect.new()
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = AssetPickerOverlay.pokemon_frame(species)
		row.add_child(icon)

		var name_label := Label.new()
		name_label.text = OverworldPokemonData.display_name(species)
		if not known.has(species):
			name_label.text += "   (new to template)"
			name_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		name_label.tooltip_text = species
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		row.add_child(name_label)

		var percent := _spin(0, 100, 1, float(entry.get("percent", 0)), " %")
		percent.custom_minimum_size = Vector2(150, 0)
		percent.value_changed.connect(func(v: float):
			entry["percent"] = v
			_revalidate())
		row.add_child(percent)

		var remove := Button.new()
		remove.text = "REMOVE"
		remove.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		remove.pressed.connect(func():
			_table.erase(entry)
			_rebuild_table())
		row.add_child(remove)

		_table_box.add_child(row)
		# Flyers only: a second line with this species' flock size, speed and spin.
		if is_flyer:
			_table_box.add_child(_flyer_line(entry))
	_revalidate()


## Flock size, speed and spin for a row that doesn't have them yet. Spin starts from
## the species' registry `spin` (the Hoppip line), then belongs to the row.
func _fill_flyer_defaults(entry: Dictionary) -> void:
	var species_spin := bool(OverworldPokemonData.species_info(str(entry.get("species", ""))).get("spin", false))
	var defaults := {
		"min": OverworldPokemonData.DEFAULT_FLOCK_MIN,
		"max": OverworldPokemonData.DEFAULT_FLOCK_MAX,
		"speed_min": OverworldPokemonData.DEFAULT_FLYER_SPEED_MIN,
		"speed_max": OverworldPokemonData.DEFAULT_FLYER_SPEED_MAX,
		"spin": species_spin,
	}
	for key in defaults:
		if not entry.has(key):
			entry[key] = defaults[key]


## The line under a flyer's species row: Flock [min]–[max]  Speed px/s [min]–[max]  [x] Spin.
func _flyer_line(entry: Dictionary) -> HBoxContainer:
	_fill_flyer_defaults(entry)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(FLYER_LINE_INDENT, 0)
	line.add_child(indent)
	_range_pair(line, "Flock", entry, "min", "max", OverworldPokemonData.FLOCK_LIMIT,
			FLOCK_SPIN_WIDTH, "flock of this species")
	_range_pair(line, "Speed px/s", entry, "speed_min", "speed_max", OverworldPokemonData.FLYER_SPEED_LIMIT,
			SPEED_SPIN_WIDTH, "speed a flock of this species flies at")
	var spin := CheckBox.new()
	spin.text = "Spin"
	spin.tooltip_text = "Turns round and round as it flies; the faster it flies, the faster it spins"
	spin.button_pressed = bool(entry["spin"])
	spin.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	spin.toggled.connect(func(on: bool): entry["spin"] = on)
	line.add_child(spin)
	return line


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
				if int(row.get("speed_min", 1)) > int(row.get("speed_max", 1)):
					out.append("%s: %s speed min is bigger than max" % [time_name, bird])
	# The map having no flyers is fine; a spawn point that can never spawn isn't.
	if not any_rows and _template != "flyer":
		out.append("add a Pokémon to at least one time of day")
	return out


func _revalidate() -> void:
	if _total_label != null:
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


func _clean_rows(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var clean := {"species": str(row.get("species", "")), "percent": snappedf(float(row.get("percent", 0)), 0.1)}
		if _template == "flyer":
			clean["min"] = int(row.get("min", OverworldPokemonData.DEFAULT_FLOCK_MIN))
			clean["max"] = int(row.get("max", OverworldPokemonData.DEFAULT_FLOCK_MAX))
			clean["speed_min"] = int(row.get("speed_min", OverworldPokemonData.DEFAULT_FLYER_SPEED_MIN))
			clean["speed_max"] = int(row.get("speed_max", OverworldPokemonData.DEFAULT_FLYER_SPEED_MAX))
			clean["spin"] = bool(row.get("spin", false))
		out.append(clean)
	return out


func _build_draft() -> Dictionary:
	var tables := _draft_tables()
	if _template == "flyer":
		return {
			"kind": "flyers",
			"flyers": tables,
			"registry_additions": _registry_additions(),
		}

	var id := str(_original.get("id", "")) if not _is_new \
			else OverworldPokemonData.next_point_id(_doc, _template)
	var point: Dictionary = {
		"id": id,
		"template": _template,
		"at": _original.get("at", [0, 0]),
	}
	if _template == "burying" and _up_time.value > 0.0:
		point["up_time"] = snappedf(_up_time.value, 0.1)
	if _template == "static":
		var pattern := _option_value(_pattern_opt)
		point["pattern"] = pattern
		if pattern.begins_with("patrol"):
			point["distance"] = int(_distance.value)
			point["speed"] = int(_speed.value)
		if pattern == "patrol_line":
			point["axis"] = _option_value(_axis_opt)
	point["tables"] = tables
	return {
		"kind": "point",
		"is_new": _is_new,
		"original_id": str(_original.get("id", "")),
		"point": point,
		"delete": false,
		"registry_additions": _registry_additions(),
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
	if _template == "flyer":
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
	# Flyer tables: closing over edits made since the last SAVE asks once first.
	if _template == "flyer" and not _close_armed and _flyer_json() != _flyer_saved_json:
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
