class_name PokemonSpawnEditor
extends CanvasLayer

## In-game form for overworld Pokémon spawns. Debug builds only -- reached from the
## placement tool (F), via N -> POKÉMON for a new spawn point or the map's flyer
## table, or M on a selected spawn-point marker to edit it.
##
## Like the character editor it writes nothing itself. Confirm hands a draft back to
## PlacementTool, which places a new point at the player, lets you grab it, and
## writes NPC_and_Opponent_Data/Pokemon/Spawns/<Map>.json on Enter.
##
##   Escape   cancel

signal confirmed(draft: Dictionary)
signal cancelled

# ---- tweakables -------------------------------------------------------------
## A brand new spawn point starts at 100% so it shows up the first time you look.
const DEFAULT_CHANCE := 100.0
const DEFAULT_INTERVAL := 10.0
const DEFAULT_TEMPLATE := "rodent"

const FORM_FONT_SIZE := 21
const TITLE_FONT_SIZE := 32
const LABEL_WIDTH := 250
const FORM_MARGIN := 40
const COLUMN_WIDTH := 880
const COLUMN_GAP := 46
const ROW_GAP := 8
const ICON_SIZE := Vector2(56, 56)
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
## [{species, percent}]
var _table: Array = []

var _root: Control = null
var _template_opt: OptionButton = null
var _desc: Label = null
var _chance_label: Label = null
var _chance: SpinBox = null
var _interval: SpinBox = null
var _min_count: SpinBox = null
var _max_count: SpinBox = null
var _up_time: SpinBox = null
var _pattern_opt: OptionButton = null
var _distance: SpinBox = null
var _speed: SpinBox = null
var _axis_opt: OptionButton = null
var _times: Dictionary = {}
var _rows: Dictionary = {}
var _table_box: VBoxContainer = null
var _total_label: Label = null
var _status: Label = null
var _confirm_btn: Button = null

var _picker: AssetPickerOverlay = null


# ============================================================
# SETUP
# ============================================================

## `point` is the spawn point being edited, or {} for a new one.
func setup(map_data: String, working_doc: Dictionary, point: Dictionary,
		known_additions: Dictionary = {}) -> void:
	_map_data = map_data
	_doc = working_doc
	_original = point
	_is_new = point.is_empty()
	_known_additions = known_additions
	layer = 129
	if not _is_new:
		_template = str(point.get("template", DEFAULT_TEMPLATE))
	_build()
	if _is_new:
		_apply_point_defaults()
	else:
		_load_point(point)
	_on_template_changed()


func _apply_point_defaults() -> void:
	_chance.value = DEFAULT_CHANCE
	_interval.value = DEFAULT_INTERVAL
	_up_time.value = 0
	for key in _times:
		_times[key].button_pressed = true
	_table = []


func _load_point(point: Dictionary) -> void:
	_chance.value = float(point.get("chance", DEFAULT_CHANCE))
	_interval.value = float(point.get("interval", DEFAULT_INTERVAL))
	_up_time.value = float(point.get("up_time", 0))
	_min_count.value = int(point.get("min", 1))
	_max_count.value = int(point.get("max", 4))
	_set_times(str(point.get("times", "")))
	_select_option(_pattern_opt, str(point.get("pattern", "idle_cycle")))
	_distance.value = float(point.get("distance", PokemonStatic.DEFAULT_DISTANCE))
	_speed.value = float(point.get("speed", PokemonStatic.DEFAULT_SPEED))
	_select_option(_axis_opt, str(point.get("axis", "horizontal")))
	_table = (point.get("table", []) as Array).duplicate(true)


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

	var title := Label.new()
	title.text = ("NEW POKÉMON SPAWN  —  %s" % _map_data) if _is_new \
			else ("EDIT POKÉMON SPAWN  —  %s" % str(_original.get("id", "?")))
	title.position = Vector2(FORM_MARGIN, 12)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_root.add_child(title)

	var scope := Label.new()
	scope.text = "Confirm hands this to the placement tool — Enter there writes Pokemon/Spawns/%s.json" % _map_data
	scope.position = Vector2(FORM_MARGIN, 54)
	scope.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	scope.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	_root.add_child(scope)

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
	_chance = _spin(0, 100, 0.1, DEFAULT_CHANCE, " %")
	_chance.value_changed.connect(func(_v: float): _revalidate())
	var chance_row := _add_row(left, "Chance", _chance)
	_chance_label = chance_row.get_child(0)

	_interval = _spin(0.5, 3600, 0.5, DEFAULT_INTERVAL, " s")
	_rows["interval"] = _add_row(left, "Roll every", _interval)

	_min_count = _spin(1, 12, 1, 1)
	_rows["min"] = _add_row(left, "Flock size min", _min_count)
	_max_count = _spin(1, 12, 1, 4)
	_rows["max"] = _add_row(left, "Flock size max", _max_count)
	_min_count.value_changed.connect(func(_v: float): _revalidate())
	_max_count.value_changed.connect(func(_v: float): _revalidate())

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

	var times_row := HBoxContainer.new()
	times_row.add_theme_constant_override("separation", 18)
	for key in OverworldPokemonData.TIME_KEYS:
		var box := CheckBox.new()
		box.text = OverworldPokemonData.TIME_KEYS[key]
		box.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		box.button_pressed = true
		box.toggled.connect(func(_on: bool): _revalidate())
		times_row.add_child(box)
		_times[key] = box
	_add_row(left, "Times of day", times_row)

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

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.position = Vector2(1640, FOOTER_TOP)
	cancel_btn.size = Vector2(220, FOOTER_HEIGHT)
	cancel_btn.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	cancel_btn.pressed.connect(_cancel)
	_root.add_child(cancel_btn)


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


func _set_times(spec: String) -> void:
	var clean := spec.strip_edges()
	for key in _times:
		_times[key].button_pressed = clean == "" or clean.to_upper().split(",").has(key)


func _times_spec() -> String:
	var keys: Array = []
	for key in _times:
		if _times[key].button_pressed:
			keys.append(key)
	return ",".join(keys)


# ============================================================
# TEMPLATE SWITCHING
# ============================================================

## The flyer table is the map's, not a point's: switching TO it shows what the map
## already has, and switching away from it starts the point from blank again.
func _on_template_switched(previous: String) -> void:
	if _template == "flyer":
		var flyers: Dictionary = _doc.get("flyers", OverworldPokemonData.default_flyers())
		_chance.value = float(flyers.get("chance", 10))
		_interval.value = float(flyers.get("interval", 10))
		_min_count.value = int(flyers.get("min", 1))
		_max_count.value = int(flyers.get("max", 4))
		_set_times(str(flyers.get("times", "")))
		_table = (flyers.get("table", []) as Array).duplicate(true)
	elif previous == "flyer":
		_apply_point_defaults()
	_on_template_changed()


func _on_template_changed() -> void:
	var is_flyer := _template == "flyer"
	var is_static := _template == "static"
	_desc.text = OverworldPokemonData.TEMPLATE_DESCRIPTIONS.get(_template, "")
	if is_flyer:
		_chance_label.text = "Chance per roll"
	elif OverworldPokemonData.TIMED_TEMPLATES.has(_template):
		_chance_label.text = "Chance per roll"
	else:
		_chance_label.text = "Chance per map load"
	_rows["interval"].visible = OverworldPokemonData.TEMPLATE_USES_INTERVAL.has(_template)
	_rows["min"].visible = is_flyer
	_rows["max"].visible = is_flyer
	_rows["up_time"].visible = _template == "burying"
	_rows["pattern"].visible = is_static
	var patrols := is_static and _option_value(_pattern_opt).begins_with("patrol")
	_rows["distance"].visible = patrols
	_rows["speed"].visible = patrols
	_rows["axis"].visible = is_static and _option_value(_pattern_opt) == "patrol_line"
	_rebuild_table()


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
	_table.append({"species": species, "percent": snappedf(percent, 0.1)})
	_rebuild_table()


func _rebuild_table() -> void:
	for child in _table_box.get_children():
		_table_box.remove_child(child)
		child.queue_free()
	var known := _template_species()
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

		var percent := _spin(0, 100, 0.1, float(entry.get("percent", 0)), " %")
		percent.custom_minimum_size = Vector2(170, 0)
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
	_revalidate()


# ============================================================
# VALIDATION + DRAFT
# ============================================================

func _problems() -> Array:
	var out: Array = []
	if _table.is_empty():
		out.append("add at least one Pokémon to the table")
	elif OverworldPokemonData.table_total(_table) <= 0.0:
		out.append("the table's percentages are all 0")
	if _template == "flyer" and _min_count.value > _max_count.value:
		out.append("flock min is bigger than max")
	if _times_spec() == "":
		out.append("tick at least one time of day")
	return out


func _revalidate() -> void:
	if _total_label != null:
		var total := OverworldPokemonData.table_total(_table)
		if _table.is_empty():
			_total_label.text = "Table is empty."
			_total_label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
		elif is_equal_approx(total, 100.0):
			_total_label.text = "Table total: 100%"
			_total_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
		else:
			_total_label.text = "Table total: %s%%  (scaled to 100%% when rolled)" % str(snappedf(total, 0.1))
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
	for row in _table:
		var species := str(row.get("species", ""))
		if species != "" and not known.has(species):
			out[species] = [_template]
	return out


func _clean_table() -> Array:
	var out: Array = []
	for row in _table:
		out.append({"species": str(row.get("species", "")), "percent": snappedf(float(row.get("percent", 0)), 0.1)})
	return out


func _build_draft() -> Dictionary:
	if _template == "flyer":
		return {
			"kind": "flyers",
			"flyers": {
				"interval": snappedf(_interval.value, 0.1),
				"chance": snappedf(_chance.value, 0.1),
				"min": int(_min_count.value),
				"max": int(_max_count.value),
				"times": _times_spec(),
				"table": _clean_table(),
			},
			"registry_additions": _registry_additions(),
		}

	var id := str(_original.get("id", "")) if not _is_new \
			else OverworldPokemonData.next_point_id(_doc, _template)
	var point: Dictionary = {
		"id": id,
		"template": _template,
		"at": _original.get("at", [0, 0]),
		"chance": snappedf(_chance.value, 0.1),
		"times": _times_spec(),
	}
	if OverworldPokemonData.TIMED_TEMPLATES.has(_template):
		point["interval"] = snappedf(_interval.value, 0.1)
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
	point["table"] = _clean_table()
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
	confirmed.emit(_build_draft())
	queue_free()


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
	cancelled.emit()
	queue_free()


## The picker is parented to the map scene, so it would outlive this form.
func _exit_tree() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null
