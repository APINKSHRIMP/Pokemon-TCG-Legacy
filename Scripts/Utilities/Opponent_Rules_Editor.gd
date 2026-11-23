extends VBoxContainer

## The opponent form's "Deck rules" and "Match effects" sections (CharacterEditor, N/M in the
## F placement tool). Built in code like the rest of the form, preloaded rather than given a
## class_name so it never needs the editor's class cache.
##
##   load_from(restrictions, match_effects)   fill from an opponent's resolved body
##   restrictions() -> Dictionary             {} when no rule is set
##   match_effects() -> Array                 [] when none
##   signal changed                           any edit (the form re-validates on it)
##
## Schemas: Deck_Validation_Helper.gd (restrictions) and Match_Effects.gd (match_effects).
## Restriction keys this form does not offer (required cards, allowed types, max_hp...) are
## carried through untouched, and listed under the tick boxes so nothing is lost silently.

signal changed

# ---- tweakables -------------------------------------------------------------
const FONT_SIZE := 21
const LABEL_WIDTH := 200
## The set tick boxes, in the order shown. Only Base -> Gym era for now (user, 2026-11-23).
const SETS := [
	["base1", "Base Set"], ["base2", "Jungle"], ["base3", "Fossil"], ["base4", "Base Set 2"],
	["base5", "Team Rocket"], ["gym1", "Gym Heroes"], ["gym2", "Gym Challenge"], ["basep", "Promos"],
]
const SET_COLUMNS := 4
## Where the standard Gym Challenge banned list is read from: the first opponent in this
## file whose restrictions ban cards. Read, not copied, so the two can never drift apart.
const GYM_LIST_SOURCE := "res://NPC_and_Opponent_Data/Characters/Gym_Challenge_Hall.json"
## Simple on/off restriction keys -> tick box caption.
const FLAGS := [
	["no_trainers", "No Trainer cards"], ["no_special_energies", "No Special Energy"],
	["basic_pokemon_only", "Basic Pokemon only"], ["no_ex_cards", "No ex cards"],
]
const POKEMON_TYPES := ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting",
		"Colorless", "Darkness", "Metal"]
## Every match effect the game knows (Match_Effects.KNOWN_TYPES), with a plain-English name
## and the parameters it takes: [key, kind, default, min, max, step]. kind: "type" (Pokemon
## type), "int", "float", "coin" (heads/tails).
const EFFECTS := {
	"type_damage_bonus": ["Type deals more damage", [["pokemon_type", "type", "Fire"], ["amount", "int", 10, 10, 200, 10]]],
	"type_damage_reduction": ["Type takes less damage", [["pokemon_type", "type", "Grass"], ["amount", "int", 10, 10, 200, 10]]],
	"evolved_damage_bonus": ["Evolved Pokemon deal more", [["amount", "int", 10, 10, 200, 10]]],
	"stage_damage_bonus": ["Damage bonus per stage", [["basic", "int", 0, 0, 200, 10], ["stage1", "int", 10, 0, 200, 10], ["stage2", "int", 20, 0, 200, 10]]],
	"zero_attack_damage": ["Attacks do no damage", []],
	"raw_damage_only": ["Attacks lose their effects", []],
	"ignore_weakness": ["No Weakness", []],
	"ignore_resistance": ["No Resistance", []],
	"ignore_weakness_and_resistance": ["No Weakness or Resistance", []],
	"no_retreat": ["No retreating", []],
	"free_retreat": ["Free retreat", []],
	"retreat_cost_modifier": ["Retreat cost +/-", [["amount", "int", 1, -4, 4, 1]]],
	"draw_count": ["Draw more each turn", [["count", "int", 2, 1, 7, 1]]],
	"opening_hand_size": ["Opening hand size", [["count", "int", 5, 1, 15, 1]]],
	"bench_size_limit": ["Bench size", [["size", "int", 3, 0, 5, 1]]],
	"extra_energy_per_turn": ["Energy attaches per turn", [["count", "int", 2, 1, 6, 1]]],
	"rainbow_energy": ["Every Energy is every type", []],
	"trainer_discard_cost": ["Trainers cost a discard", [["count", "int", 1, 1, 3, 1]]],
	"no_healing": ["No healing", []],
	"healing_multiplier": ["Healing multiplied", [["multiplier", "float", 2.0, 0.5, 5.0, 0.5]]],
	"end_of_turn_heal": ["Heal at end of each turn", [["amount", "int", 10, 10, 100, 10]]],
	"energy_attach_full_heal": ["Attaching Energy fully heals", []],
	"energy_attach_halve_hp": ["Attaching Energy halves HP", []],
	"evolve_full_heal": ["Evolving fully heals", []],
	"max_hp_modifier": ["Max HP +/-", [["amount", "int", 20, -100, 200, 10]]],
	"no_status_effects": ["No Special Conditions", []],
	"poison_damage_multiplier": ["Poison damage multiplied", [["multiplier", "float", 2.0, 0.5, 5.0, 0.5]]],
	"double_prizes": ["Double Prizes per Knock Out", []],
	"powers_blocked": ["No Pokemon Powers (both sides)", []],
	"coin_flip_override": ["Every coin flip is fixed", [["result", "coin", "heads"]]],
}
## Who an effect applies to. powers_blocked ignores it (always both sides) so has no picker.
const WHO := [["both", "Both sides"], ["player", "Player only"], ["opponent", "CPU only"]]
const NO_WHO := ["powers_blocked"]
# -----------------------------------------------------------------------------

const MatchEffectsScript := preload("res://Scripts/Main_Match_Gameplay_Scripts/Match_Effects.gd")

var _set_boxes: Dictionary = {}      # set id -> CheckBox
var _flag_boxes: Dictionary = {}     # restriction key -> CheckBox
var _gym_box: CheckBox = null
var _extra_banned: LineEdit = null
var _kept_note: Label = null
var _effect_rows: VBoxContainer = null
var _add_pick: OptionButton = null
var _preview: Label = null
## Restriction keys the form does not edit, carried through as they were.
var _passthrough: Dictionary = {}
## Set ids in allowed_set_ids that are not tick boxes (a later era), carried through.
var _other_sets: Array = []
var _gym_ids: Array = []
var _gym_names: Array = []
var _loading := false


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_read_gym_list()
	_build_rules()
	_build_effects()


# ============================================================
# BUILD
# ============================================================

func _heading(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	add_child(spacer)
	var heading := DebugFormTheme.heading(text)
	heading.get_child(0).add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(heading)


func _row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	add_child(row)


func _check(text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.add_theme_font_size_override("font_size", FONT_SIZE)
	box.toggled.connect(func(_p: bool): _emit())
	return box


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE - 3)
	label.add_theme_color_override("font_color", DebugFormTheme.INK_DIM)
	return label


func _build_rules() -> void:
	_heading("Deck rules (what the PLAYER's deck may use)")
	var grid := GridContainer.new()
	grid.columns = SET_COLUMNS
	grid.add_theme_constant_override("h_separation", 18)
	for pair in SETS:
		var box := _check(pair[1])
		_set_boxes[pair[0]] = box
		grid.add_child(box)
	_row("Allowed sets", grid)
	add_child(_note("Nothing ticked = every set allowed. Tick sets to allow ONLY those (untick Jungle with the rest ticked = no Jungle). Basic Energy from any set is always allowed."))

	_gym_box = _check("Gym Challenge banned list (%d cards)" % (_gym_ids.size() + _gym_names.size()))
	_gym_box.tooltip_text = ", ".join(_gym_names)
	_row("Banned", _gym_box)

	_extra_banned = LineEdit.new()
	_extra_banned.placeholder_text = "More banned cards: names or ids, comma separated (Bill, base1-91)"
	_extra_banned.add_theme_font_size_override("font_size", FONT_SIZE)
	_extra_banned.text_changed.connect(func(_t: String): _emit())
	_row("", _extra_banned)

	var flags := GridContainer.new()
	flags.columns = 2
	flags.add_theme_constant_override("h_separation", 18)
	for pair in FLAGS:
		var box := _check(pair[1])
		_flag_boxes[pair[0]] = box
		flags.add_child(box)
	_row("Other rules", flags)

	_kept_note = _note("")
	_kept_note.visible = false
	add_child(_kept_note)


func _build_effects() -> void:
	_heading("Match effects (rules for the whole match)")
	_effect_rows = VBoxContainer.new()
	_effect_rows.add_theme_constant_override("separation", 4)
	add_child(_effect_rows)

	_add_pick = OptionButton.new()
	_add_pick.add_theme_font_size_override("font_size", FONT_SIZE)
	_add_pick.add_item("Add an effect...")
	for type in EFFECTS:
		_add_pick.add_item(String(EFFECTS[type][0]))
		_add_pick.set_item_metadata(_add_pick.item_count - 1, type)
	_add_pick.item_selected.connect(func(idx: int):
		if idx > 0:
			_add_effect_row({"type": String(_add_pick.get_item_metadata(idx))})
			_add_pick.select(0)
			_emit())
	_row("", _add_pick)

	_preview = _note("")
	add_child(_preview)


## One effect: its name, its parameters, who it hits, and a remove button.
func _add_effect_row(effect: Dictionary) -> void:
	var type := String(effect.get("type", ""))
	if not EFFECTS.has(type):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_meta("type", type)
	var name := Label.new()
	name.text = String(EFFECTS[type][0])
	name.custom_minimum_size = Vector2(300, 0)
	name.clip_text = true
	name.add_theme_font_size_override("font_size", FONT_SIZE)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name)

	for spec in EFFECTS[type][1]:
		var key := String(spec[0])
		var ctl: Control
		match String(spec[1]):
			"type", "coin":
				var opt := OptionButton.new()
				opt.add_theme_font_size_override("font_size", FONT_SIZE)
				var choices: Array = POKEMON_TYPES if String(spec[1]) == "type" else ["heads", "tails"]
				for c in choices:
					opt.add_item(String(c))
				var want := String(effect.get(key, spec[2]))
				for i in opt.item_count:
					if opt.get_item_text(i) == want:
						opt.select(i)
				opt.item_selected.connect(func(_i: int): _emit())
				ctl = opt
			_:
				var spin := SpinBox.new()
				spin.min_value = float(spec[3])
				spin.max_value = float(spec[4])
				spin.step = float(spec[5])
				spin.value = float(effect.get(key, spec[2]))
				spin.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
				spin.custom_minimum_size = Vector2(120, 0)
				spin.tooltip_text = key
				spin.value_changed.connect(func(_v: float): _emit())
				ctl = spin
		ctl.set_meta("key", key)
		ctl.set_meta("kind", String(spec[1]))
		row.add_child(ctl)

	if type not in NO_WHO:
		var who := OptionButton.new()
		who.add_theme_font_size_override("font_size", FONT_SIZE)
		for pair in WHO:
			who.add_item(String(pair[1]))
			who.set_item_metadata(who.item_count - 1, pair[0])
			if String(pair[0]) == String(effect.get("applies_to", "both")):
				who.select(who.item_count - 1)
		who.set_meta("key", "applies_to")
		who.set_meta("kind", "who")
		who.item_selected.connect(func(_i: int): _emit())
		row.add_child(who)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var remove := Button.new()
	remove.text = "X"
	remove.tooltip_text = "Remove this effect"
	remove.add_theme_font_size_override("font_size", FONT_SIZE)
	remove.pressed.connect(func():
		_effect_rows.remove_child(row)
		row.queue_free()
		_emit())
	row.add_child(remove)
	_effect_rows.add_child(row)


# ============================================================
# LOAD
# ============================================================

func load_from(restrictions: Variant, effects: Variant) -> void:
	_loading = true
	var r: Dictionary = (restrictions as Dictionary).duplicate(true) if restrictions is Dictionary else {}

	var sets: Array = r.get("allowed_set_ids", []) if r.get("allowed_set_ids") is Array else []
	r.erase("allowed_set_ids")
	_other_sets = []
	for id in sets:
		if _set_boxes.has(String(id)):
			_set_boxes[String(id)].button_pressed = true
		else:
			_other_sets.append(String(id))

	var ids: Array = r.get("banned_card_ids", []) if r.get("banned_card_ids") is Array else []
	var names: Array = r.get("banned_card_names", []) if r.get("banned_card_names") is Array else []
	r.erase("banned_card_ids")
	r.erase("banned_card_names")
	var has_gym := not (_gym_ids.is_empty() and _gym_names.is_empty())
	for x in _gym_ids:
		if x not in ids:
			has_gym = false
	for x in _gym_names:
		if x not in names:
			has_gym = false
	_gym_box.button_pressed = has_gym
	var extra: Array = []
	for x in names + ids:
		if not (has_gym and (x in _gym_ids or x in _gym_names)):
			extra.append(String(x))
	_extra_banned.text = ", ".join(extra)

	for key in _flag_boxes:
		_flag_boxes[key].button_pressed = bool(r.get(key, false))
		r.erase(key)

	_passthrough = r
	var kept: Array = _passthrough.keys()
	if not _other_sets.is_empty():
		kept.append("sets " + ", ".join(_other_sets))
	_kept_note.text = "Also kept as they are (edit the JSON for these): " + ", ".join(kept)
	_kept_note.visible = not kept.is_empty()

	for child in _effect_rows.get_children():
		_effect_rows.remove_child(child)
		child.queue_free()
	if effects is Array:
		for e in effects:
			if e is Dictionary:
				_add_effect_row(e)
	_loading = false
	_update_preview()


func _read_gym_list() -> void:
	var file := FileAccess.open(GYM_LIST_SOURCE, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return
	for body in (data.get("opponents", {}) as Dictionary).values():
		var r = body.get("restrictions") if body is Dictionary else null
		if r is Dictionary and (r.has("banned_card_ids") or r.has("banned_card_names")):
			_gym_ids = (r.get("banned_card_ids", []) as Array).duplicate()
			_gym_names = (r.get("banned_card_names", []) as Array).duplicate()
			return


# ============================================================
# READ BACK
# ============================================================

func restrictions() -> Dictionary:
	var r: Dictionary = _passthrough.duplicate(true)
	var sets: Array = []
	for pair in SETS:
		if _set_boxes[pair[0]].button_pressed:
			sets.append(String(pair[0]))
	if not sets.is_empty() or not _other_sets.is_empty():
		r["allowed_set_ids"] = sets + _other_sets

	var ids: Array = []
	var names: Array = []
	if _gym_box.button_pressed:
		ids.append_array(_gym_ids)
		names.append_array(_gym_names)
	for raw in _extra_banned.text.split(","):
		var x := raw.strip_edges()
		if x == "":
			continue
		# An id is "set-number" with no spaces (base1-91, gym2-17); anything else is a name.
		var is_id := not x.contains(" ") and x.contains("-") and x.to_lower() == x
		var target: Array = ids if is_id else names
		if x not in target:
			target.append(x)
	if not ids.is_empty():
		r["banned_card_ids"] = ids
	if not names.is_empty():
		r["banned_card_names"] = names

	for key in _flag_boxes:
		if _flag_boxes[key].button_pressed:
			r[key] = true
	return r


func match_effects() -> Array:
	var out: Array = []
	for row in _effect_rows.get_children():
		if row.is_queued_for_deletion() or not row.has_meta("type"):
			continue
		var e: Dictionary = {"type": String(row.get_meta("type"))}
		for ctl in row.get_children():
			if not ctl.has_meta("key"):
				continue
			var key := String(ctl.get_meta("key"))
			match String(ctl.get_meta("kind")):
				"type", "coin":
					e[key] = (ctl as OptionButton).get_item_text((ctl as OptionButton).selected)
				"who":
					var who := String((ctl as OptionButton).get_item_metadata((ctl as OptionButton).selected))
					if who != "both":
						e[key] = who   # "both" is the default, so it is not written
				"float":
					e[key] = (ctl as SpinBox).value
				_:
					e[key] = int((ctl as SpinBox).value)
		out.append(e)
	return out


func _emit() -> void:
	if _loading:
		return
	_update_preview()
	changed.emit()


## Exactly what the player is shown before accepting the match (Match_Modifiers_Box).
func _update_preview() -> void:
	if _preview == null:
		return
	var lines: Array = MatchEffectsScript.describe_entries(match_effects())
	_preview.text = "No match effects." if lines.is_empty() else "The player sees:  " + "  |  ".join(lines)
