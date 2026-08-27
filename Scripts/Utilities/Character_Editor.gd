class_name CharacterEditor
extends CanvasLayer

## In-game NPC / opponent authoring form. Debug builds only -- PlacementTool only
## ever constructs this, and PlacementTool is itself gated behind
## DebugMode.is_enabled().
##
## Creating a character used to mean hand-writing an entry into the map's character
## file AND a matching entry into All_NPC_Constant_Data.json, spelling the key
## identically in both, naming a sprite that exists on disk, and picking a coin no
## other character already grants. Every one of those is a silent failure if you get
## it wrong. This asks for the same information with pickers over the real assets and
## writes both files itself.
##
## The form does not touch disk. Confirm hands a draft back to PlacementTool, which
## holds it until you press Enter -- so F still discards cleanly.
##
##   N (in the placement tool)   create a new character
##   M (in the placement tool)   edit the selected one
##   Escape                      cancel

signal confirmed(draft: Dictionary)
signal cancelled

enum Mode { NEW, EDIT }

# ---- tweakables -------------------------------------------------------------
## Sprite a brand new character starts on. Any name in Overworld_Sprites/ works.
const DEFAULT_SPRITE := "Roughneck"
## Preselected battle track for a new opponent. Most existing opponents still say
## "REPLACEMUSIC" or "TEST", neither of which resolves to a file, so they play nothing.
## Must be a name the picker offers -- i.e. a file in Audio/BGM with "battle" in it.
const DEFAULT_MUSIC := "normal_battle (PTCG)"
const DEFAULT_PRIZE_CARDS := 6
const DEFAULT_MESSAGE_COLOUR := "grey"
const DEFAULT_CASH_REWARD := "100"
const DEFAULT_DAYS := "1-20"

const FORM_FONT_SIZE := 21
const TITLE_FONT_SIZE := 32
const LABEL_WIDTH := 200
## The form is two fixed columns. They have to add up to less than the scroll's
## inner width -- horizontal scrolling is off, so anything wider is simply lost off
## the right of the screen.
const COLUMN_WIDTH := 880
const COLUMN_GAP := 46
const ROW_GAP := 6
const TEXT_ROWS := 2
const TEXT_ROW_HEIGHT := 30
## The stylebox's own padding, on top of the rows. Without it the last row is cut
## through the middle, which reads as a rendering fault rather than as "scroll me".
const TEXT_AREA_PADDING := 14
const ASSET_PREVIEW := Vector2(60, 60)

const FORM_MARGIN := 40
const SCROLL_TOP := 92
const SCROLL_HEIGHT := 924
## The status line and the two buttons, pinned below the scroll. Everything from
## here to the bottom of a 1080 screen is theirs.
const FOOTER_TOP := 1024
const FOOTER_HEIGHT := 48
# -----------------------------------------------------------------------------

const DECK_DIR := "res://NPC_and_Opponent_Data/Opponent_Deck_Data/"
const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"
const COIN_SHOP_PATH := "res://NPC_and_Opponent_Data/coin_shop_inventory.json"

## Gift types the form offers. `cash` and `energy_style` are deliberately left out
## -- cash gifts were dropped, and the five energy styles are years from being
## reachable. `pack_of_cards` is out because MapManager only push_warning()s it.
const GIFT_TYPES := ["none", "card", "coin", "costume", "sleeve", "pack", "available_pack"]
const GIFT_HINTS := {
	"none": "",
	"card": "card ids, comma-separated:  base1-4, base2-5",
	"coin": "one coin, picked below",
	"costume": "one costume, picked below",
	"sleeve": "one sleeve, picked below",
	"pack": "pack ART codes to open now:  base5_a, base5_b",
	"available_pack": "pack to unlock for purchase:  base4",
}

## Which file each field belongs in. Anything in CONSTANT_FIELDS_* goes to
## All_NPC_Constant_Data.json unless the character file already overrides it;
## everything else is character-file only.
const CONSTANT_FIELDS_NPC := ["friendly_name", "sprite", "message_colour",
		"gift_type", "gift_value"]
const CONSTANT_FIELDS_OPP := ["sprite", "message_colour", "deck", "music",
		"prize_cards", "cash_reward", "coin_reward", "card_reward", "pack_reward",
		"costume_reward", "match_format"]

## Optional fields that can legitimately be emptied. An empty box writes nothing
## rather than an empty string, so without this list clearing a reward in edit mode
## would look like it worked and leave the old value in the file.
const CLEARABLE_FIELDS_NPC := ["gift_type", "gift_value"]
const CLEARABLE_FIELDS_OPP := ["coin_reward", "card_reward", "pack_reward",
		"costume_reward", "match_format", "sleeve_reward"]

var _map_data: String = ""
var _mode: int = Mode.NEW
var _section: String = "npcs"
var _actor: Node2D = null

## The raw character body from the map file, and which `when` rule produced the
## actor today. -1 means the character's own top-level fields matched.
var _character_raw: Dictionary = {}
var _rule_index: int = -1
var _existing_name: String = ""

## Lowercased name -> true, across the constants file and every character file.
var _taken_names: Dictionary = {}
## Coin basename -> true for every coin already granted by anybody.
var _taken_coins: Dictionary = {}

var _root: Control = null
var _status: Label = null
var _confirm_btn: Button = null
var _scope_label: Label = null

# Widgets, looked up by field name so reading the form back is one loop.
var _w: Dictionary = {}
var _time_boxes: Dictionary = {}
var _gift_group: ButtonGroup = null
var _gift_type: String = "none"

var _picker: AssetPickerOverlay = null
## BGM that was playing before an audition, restored on the way out.
var _bgm_before_audition: String = ""
var _auditioning: bool = false


# ============================================================
# SETUP
# ============================================================

## `reserved_names` and `reserved_coins` are the drafts the placement tool is
## already holding but has not written yet. Without them, creating two characters
## before pressing Enter would derive the same key for both and let them grant the
## same coin -- the files on disk say nothing about a draft.
func setup(map_data: String, mode: int, actor: Node2D = null,
		reserved_names: Array = [], reserved_coins: Array = []) -> void:
	_map_data = map_data
	_mode = mode
	_actor = actor
	layer = 129
	_collect_taken_names()
	_collect_taken_coins()
	for name in reserved_names:
		_taken_names[str(name).to_lower()] = true
	for coin in reserved_coins:
		_note_coin(coin)

	if _mode == Mode.EDIT:
		if not _load_existing():
			cancelled.emit()
			queue_free()
			return
		_build_form()
	else:
		_build_kind_choice()


## Pull the selected actor's real, resolved values out of the map file so the form
## opens showing exactly what is on screen right now.
func _load_existing() -> bool:
	if _actor == null or not is_instance_valid(_actor) or not _actor.has_meta("source"):
		return false
	var src: Dictionary = _actor.get_meta("source", {})
	_section = str(src.get("section", "npcs"))
	_existing_name = str(src.get("name", ""))
	_rule_index = int(src.get("rule", -1))
	var doc := CharacterSchedule.load_map(_map_data)
	var character = doc.get(_section, {}).get(_existing_name)
	if not (character is Dictionary):
		push_error("CharacterEditor: %s/%s not found in %s" % [_section, _existing_name, _map_data])
		return false
	_character_raw = character
	# The character's own name is not "taken" as far as it is concerned.
	_taken_names.erase(_existing_name.to_lower())
	return true


# ============================================================
# NAME AND COIN UNIQUENESS
# ============================================================

## Every character name in use anywhere. Uniqueness has to be global, not per-map:
## opponents_beaten, npc_interactions and gifts_received are all flat dictionaries
## keyed by this name, and so is the constants file.
func _collect_taken_names() -> void:
	var consts := _read_json(CONSTANTS_PATH)
	for section in ["npcs", "opponents"]:
		for name in consts.get(section, {}):
			_taken_names[str(name).to_lower()] = true
	for map_name in _character_files():
		var doc := _read_json(CharacterSchedule.DIR + map_name + ".json")
		for section in ["npcs", "opponents"]:
			for name in doc.get(section, {}):
				_taken_names[str(name).to_lower()] = true


## Every coin already handed out, so no two characters grant the same one. Covers
## opponent coin_reward, NPC coin gifts (including inside `when` rules), and the
## coin shop's stock.
func _collect_taken_coins() -> void:
	var consts := _read_json(CONSTANTS_PATH)
	for name in consts.get("opponents", {}):
		_note_coin(consts["opponents"][name].get("coin_reward", ""))
	for name in consts.get("npcs", {}):
		var body: Dictionary = consts["npcs"][name]
		if str(body.get("gift_type", "")) == "coin":
			_note_coin(body.get("gift_value", ""))

	for map_name in _character_files():
		var doc := _read_json(CharacterSchedule.DIR + map_name + ".json")
		for section in ["npcs", "opponents"]:
			for name in doc.get(section, {}):
				var body = doc[section][name]
				if not (body is Dictionary):
					continue
				_scan_body_for_coins(body)
				var rules = body.get("when")
				if rules is Array:
					for rule in rules:
						if rule is Dictionary:
							_scan_body_for_coins(rule)

	var shop := _read_json(COIN_SHOP_PATH)
	for entry in shop.get("coins", []):
		if entry is Dictionary:
			_note_coin(str(entry.get("filename", "")).get_basename())


func _scan_body_for_coins(body: Dictionary) -> void:
	_note_coin(body.get("coin_reward", ""))
	if str(body.get("gift_type", "")) == "coin":
		_note_coin(body.get("gift_value", ""))


func _note_coin(value: Variant) -> void:
	var text := str(value).strip_edges()
	# The data writes coins without an extension, but be forgiving either way --
	# a stray ".png" would otherwise let the same coin through twice.
	if text.ends_with(".png"):
		text = text.get_basename()
	if text != "":
		_taken_coins[text] = true


func _character_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CharacterSchedule.DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			out.append(fname.trim_suffix(".json"))
		fname = dir.get_next()
	dir.list_dir_end()
	return out


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## friendly -> a key nothing else uses. Follows the convention already in the data:
## Badman 1 / Badman 2, Gym Receptionist 1-4.
func _derive_unique_name(friendly: String) -> String:
	var base := friendly.strip_edges()
	if base == "":
		return ""
	if not _taken_names.has(base.to_lower()):
		return base
	var n := 2
	while _taken_names.has(("%s %d" % [base, n]).to_lower()):
		n += 1
	return "%s %d" % [base, n]


# ============================================================
# KIND CHOICE (new characters only)
# ============================================================

func _build_kind_choice() -> void:
	_root = _make_backdrop()
	var title := Label.new()
	title.text = "NEW CHARACTER"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.position = Vector2(0, 380)
	title.size = Vector2(1920, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var npc_btn := Button.new()
	npc_btn.text = "NPC"
	npc_btn.position = Vector2(1920 / 2 - 420, 470)
	npc_btn.size = Vector2(400, 120)
	npc_btn.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	npc_btn.pressed.connect(func(): _choose_kind("npcs"))
	_root.add_child(npc_btn)

	var opp_btn := Button.new()
	opp_btn.text = "OPPONENT"
	opp_btn.position = Vector2(1920 / 2 + 20, 470)
	opp_btn.size = Vector2(400, 120)
	opp_btn.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	opp_btn.pressed.connect(func(): _choose_kind("opponents"))
	_root.add_child(opp_btn)

	var hint := Label.new()
	hint.text = "Escape to cancel"
	hint.position = Vector2(0, 630)
	hint.size = Vector2(1920, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.86, 0.89, 0.96))
	_root.add_child(hint)


func _choose_kind(section: String) -> void:
	_section = section
	_root.queue_free()
	_root = null
	_build_form()


## Opaque, not translucent: at 0.94 the placement tool's HUD and the map itself
## showed through every heading, which is half of why the form was unreadable. The
## theme is set here so the whole form inherits it in one place.
func _make_backdrop() -> Control:
	var dim := ColorRect.new()
	dim.color = DebugFormTheme.BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.theme = DebugFormTheme.build()
	add_child(dim)
	return dim


# ============================================================
# THE FORM
# ============================================================

func _is_opponent() -> bool:
	return _section == "opponents"


func _build_form() -> void:
	_root = _make_backdrop()

	var title := Label.new()
	title.text = "%s %s" % ["EDIT" if _mode == Mode.EDIT else "NEW",
			"OPPONENT" if _is_opponent() else "NPC"]
	title.position = Vector2(FORM_MARGIN, 12)
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_root.add_child(title)

	_scope_label = Label.new()
	_scope_label.position = Vector2(FORM_MARGIN, 54)
	_scope_label.size = Vector2(1920 - FORM_MARGIN * 2, 30)
	_scope_label.clip_text = true
	_scope_label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_scope_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	_scope_label.text = _scope_text()
	_root.add_child(_scope_label)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(FORM_MARGIN, SCROLL_TOP)
	scroll.size = Vector2(1920 - FORM_MARGIN * 2, SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	scroll.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	left.add_theme_constant_override("separation", ROW_GAP)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	right.add_theme_constant_override("separation", ROW_GAP)
	columns.add_child(right)

	_build_identity(left)
	if _is_opponent():
		_build_opponent_battle(left)
		_build_opponent_rewards(right)
	else:
		_build_npc_gift(left)
	_build_dialogue(right)
	_clamp_widths(columns)

	_status = Label.new()
	_status.position = Vector2(FORM_MARGIN, FOOTER_TOP)
	_status.size = Vector2(1320, FOOTER_HEIGHT)
	_status.clip_text = true
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_root.add_child(_status)

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

	if _mode == Mode.EDIT:
		_load_values_into_form()
	else:
		_apply_new_defaults()
	_revalidate()


## Which days and times a save would rewrite -- the same blast radius the placement
## tool spells out before Enter, for the same reason.
func _scope_text() -> String:
	if _mode == Mode.NEW:
		return "new character -- written to Characters/%s.json and All_NPC_Constant_Data.json" % _map_data
	if _rule_index < 0:
		var rules = _character_raw.get("when")
		if rules is Array and not rules.is_empty():
			return "editing this character's DEFAULTS -- feeds every rule that does not override the field"
		return "editing this character (it has no when-rules)"
	return "matched when-rule #%d -- a field this rule states is rewritten in the rule, one it inherits is rewritten on the defaults" % _rule_index


# ---- section builders --------------------------------------------------------

func _build_identity(col: VBoxContainer) -> void:
	_add_heading(col, "IDENTITY")

	_w["sprite"] = _add_asset_row(col, "Sprite", AssetPickerOverlay.Kind.SPRITE)

	if _is_opponent():
		# Opponents have no friendly_name -- MapManager upper-cases the unique key
		# straight into the message box, so this string is what the player reads.
		var name_edit := _make_line_edit("Opponent name (shown to the player).....", 60)
		name_edit.text_changed.connect(func(_t: String): _on_name_changed())
		_w["name"] = name_edit
		_add_row(col, "Name", name_edit)
	else:
		var friendly := _make_line_edit("Friendly name (shown in the message box).....", 40)
		friendly.text_changed.connect(func(_t: String): _on_name_changed())
		_w["friendly_name"] = friendly
		_add_row(col, "Friendly name", friendly)

	var key_label := Label.new()
	key_label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	key_label.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65))
	_w["unique_key"] = key_label
	_add_row(col, "Unique key", key_label)

	var colour := OptionButton.new()
	colour.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	for key in MessageBoxTheme.THEMES:
		# "white" is reserved for the rival, so it is not offered.
		if str(key) != "white":
			colour.add_item(str(key))
	colour.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_w["message_colour"] = colour
	_add_row(col, "Message colour", colour)

	_add_heading(col, "SCHEDULE")

	var days := _make_line_edit("3-6  |  1,3,5  |  2-8/2  |  4  |  blank = every day", 40)
	days.text_changed.connect(func(_t: String): _revalidate())
	_w["days"] = days
	_add_row(col, "Days", days)

	var times_box := HBoxContainer.new()
	times_box.add_theme_constant_override("separation", 24)
	for pair in [["M", "Morning"], ["A", "Afternoon"], ["E", "Evening"], ["N", "Night"]]:
		var cb := CheckBox.new()
		cb.text = str(pair[1])
		cb.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		cb.toggled.connect(func(_p: bool): _revalidate())
		_time_boxes[str(pair[0])] = cb
		times_box.add_child(cb)
	_add_row(col, "Times", times_box)

	var loop := CheckBox.new()
	loop.text = "repeats when the calendar loops (off for story characters)"
	loop.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	loop.button_pressed = true
	_w["loop"] = loop
	_add_row(col, "Loop", loop)


func _build_opponent_battle(col: VBoxContainer) -> void:
	_add_heading(col, "BATTLE")

	var deck_row := HBoxContainer.new()
	deck_row.add_theme_constant_override("separation", 10)
	var deck_edit := _make_line_edit("Deck file name (no .json).....", 60)
	deck_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_edit.text_changed.connect(func(_t: String): _revalidate())
	_w["deck"] = deck_edit
	deck_row.add_child(deck_edit)
	var deck_pick := OptionButton.new()
	deck_pick.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	deck_pick.custom_minimum_size = Vector2(260, 0)
	deck_pick.add_item("-- existing decks --")
	for name in _list_basenames(DECK_DIR, ".json"):
		deck_pick.add_item(str(name))
	deck_pick.item_selected.connect(func(idx: int):
		if idx > 0:
			deck_edit.text = deck_pick.get_item_text(idx)
			_revalidate())
	deck_row.add_child(deck_pick)
	_add_row(col, "Deck", deck_row)

	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	var music := OptionButton.new()
	music.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	music.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Battle tracks only. Audio/BGM also holds the map, menu and shop music, and none of
	# that belongs on an opponent -- the Sound Manager tells the two apart by filename.
	for name in SoundManagerScript.list_battle_bgm():
		music.add_item(name)
	# Track names run to eighty characters and the box is half that wide, so the
	# whole name lives in the tooltip.
	music.item_selected.connect(func(idx: int): music.tooltip_text = music.get_item_text(idx))
	_w["music"] = music
	music_row.add_child(music)
	var audition := Button.new()
	audition.text = "PLAY"
	audition.custom_minimum_size = Vector2(110, 0)
	audition.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	audition.pressed.connect(_toggle_audition.bind(audition))
	music_row.add_child(audition)
	_add_row(col, "Music", music_row)

	var prizes := SpinBox.new()
	prizes.min_value = 1
	prizes.max_value = 6
	prizes.value = DEFAULT_PRIZE_CARDS
	prizes.get_line_edit().add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_w["prize_cards"] = prizes
	_add_row(col, "Prize cards", prizes)

	var bo3 := CheckBox.new()
	bo3.text = "best of 3 (first to two wins)"
	bo3.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	_w["match_format"] = bo3
	_add_row(col, "Match format", bo3)

	_w["sleeve"] = _add_asset_row(col, "Sleeve", AssetPickerOverlay.Kind.SLEEVE)

	var grant := CheckBox.new()
	grant.text = "grant this sleeve to the player on first win"
	grant.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	grant.toggled.connect(func(_p: bool): _revalidate())
	_w["sleeve_reward"] = grant
	_add_row(col, "Grant sleeve?", grant)


func _build_opponent_rewards(col: VBoxContainer) -> void:
	_add_heading(col, "REWARDS")

	var cash := _make_line_edit("100", 8)
	cash.text_changed.connect(func(_t: String): _revalidate())
	_w["cash_reward"] = cash
	_add_row(col, "Cash reward", cash)

	_w["coin_reward"] = _add_asset_row(col, "Coin reward", AssetPickerOverlay.Kind.COIN)

	var card := _make_line_edit("card ids, comma-separated:  base1-4, base2-5", 200)
	_w["card_reward"] = card
	_add_row(col, "Card reward", card)

	var pack := _make_line_edit("pack codes, comma-separated  (nothing reads this yet)", 120)
	_w["pack_reward"] = pack
	_add_row(col, "Pack reward", pack)

	_w["costume_reward"] = _add_asset_row(col, "Costume reward", AssetPickerOverlay.Kind.COSTUME, true)


func _build_npc_gift(col: VBoxContainer) -> void:
	_add_heading(col, "GIFT")

	_gift_group = ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	for gift in GIFT_TYPES:
		var cb := CheckBox.new()
		cb.text = str(gift)
		cb.button_group = _gift_group
		cb.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		cb.set_meta("gift", str(gift))
		if str(gift) == "none":
			cb.button_pressed = true
		grid.add_child(cb)
	_gift_group.pressed.connect(_on_gift_type_changed)
	_add_row(col, "Gift type", grid)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	hint.add_theme_color_override("font_color", Color(0.86, 0.89, 0.96))
	_w["gift_hint"] = hint
	_add_row(col, "", hint)

	var value := _make_line_edit("", 200)
	value.text_changed.connect(func(_t: String): _revalidate())
	_w["gift_value"] = value
	_add_row(col, "Gift value", value)

	_w["gift_asset"] = _add_asset_row(col, "Gift asset", AssetPickerOverlay.Kind.COIN)
	_set_gift_visibility()


func _build_dialogue(col: VBoxContainer) -> void:
	_add_heading(col, "DIALOGUE")
	_w["meet"] = _add_text_area(col, "Meet text  (first time they are spoken to)")
	_w["repeat"] = _add_text_area(col, "Repeat text  (every time after that)")
	if _is_opponent():
		_w["first_win"] = _add_text_area(col, "First win text  (you beat them the first time)")
		_w["rematch_win"] = _add_text_area(col, "Rematch win text  (you beat them again)")
		_w["loss"] = _add_text_area(col, "Loss text  (they beat you)")


# ---- widget helpers ----------------------------------------------------------

## Stop any single widget from widening the column it sits in.
##
## This is what pushed the opponent form's right-hand column off the screen: an
## OptionButton defaults to fit_to_longest_item, so the music picker -- whose longest
## entry is "Gym Leader Challenge Battle (Pokemon Card GB2 - Duel Vs Fortress Leader)"
## -- claimed a minimum width far past the column, and with horizontal scrolling disabled
## everything to its right went past 1920 and was clipped away. A Button or Label
## sized to its own text does the same thing more quietly.
##
## Clipping is a backstop, not the plan: every caption is written to fit. It only
## bites when a value on disk is longer than expected, and losing the tail of a
## costume name beats losing the CONFIRM button.
func _clamp_widths(node: Node) -> void:
	for child in node.get_children():
		if child is OptionButton:
			child.fit_to_longest_item = false
			child.clip_text = true
			child.alignment = HORIZONTAL_ALIGNMENT_LEFT
		elif child is CheckBox or child is CheckButton:
			# Deliberately not clipped. clip_text drops a Button's minimum width to
			# zero, which is harmless for a widget told to expand but collapses a
			# check box in a GridContainer down to its tick. Their captions are kept
			# short enough to fit instead.
			pass
		elif child is Button or child is Label:
			child.clip_text = true
		_clamp_widths(child)


func _add_heading(col: VBoxContainer, text: String) -> void:
	# No spacer above the first heading in a column -- it would be a gap under the
	# title, and the opponent form has no vertical room to spare.
	if col.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		col.add_child(spacer)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE + 4)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	col.add_child(label)


func _add_row(col: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	col.add_child(row)


func _make_line_edit(placeholder: String, max_length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	return edit


## Caption and box are one group, tight together, with the column's normal gap only
## between groups -- five equally spaced captions read as if each one belonged to the
## box above it.
func _add_text_area(col: VBoxContainer, label_text: String) -> TextEdit:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	col.add_child(group)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	group.add_child(label)

	var edit := TextEdit.new()
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(0, TEXT_ROWS * TEXT_ROW_HEIGHT + TEXT_AREA_PADDING)
	edit.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	group.add_child(edit)
	return edit


## A picker button plus a live preview of what is currently chosen. `append` makes
## the picker add to a comma list rather than replace -- costume_reward supports
## several, and the data already uses that.
func _add_asset_row(col: VBoxContainer, label_text: String, kind: int,
		append: bool = false) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var preview := TextureRect.new()
	preview.custom_minimum_size = ASSET_PREVIEW
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(preview)

	var button := Button.new()
	button.text = "(none)"
	button.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
	# Left, not centred: costume_reward holds a comma list, and a centred clip would
	# eat the first name as well as the last.
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("kind", kind)
	button.set_meta("preview", preview)
	button.set_meta("append", append)
	button.set_meta("value", "")
	button.pressed.connect(_open_picker.bind(button))
	row.add_child(button)

	if append:
		var clear := Button.new()
		clear.text = "CLEAR"
		clear.custom_minimum_size = Vector2(110, 0)
		clear.add_theme_font_size_override("font_size", FORM_FONT_SIZE)
		clear.pressed.connect(func(): _set_asset(button, ""))
		row.add_child(clear)

	_add_row(col, label_text, row)
	return button


func _list_basenames(folder: String, suffix: String) -> Array:
	var names: Dictionary = {}
	var dir := DirAccess.open(folder)
	if dir == null:
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			if clean.ends_with(suffix):
				names[clean.trim_suffix(suffix)] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var out: Array = names.keys()
	out.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


# ============================================================
# PICKERS
# ============================================================

func _open_picker(button: Button) -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	var kind: int = int(button.get_meta("kind"))
	var current := str(button.get_meta("value", ""))
	var unavailable: Dictionary = {}
	if kind == AssetPickerOverlay.Kind.COIN:
		unavailable = _taken_coins
	# An appending field starts each pick fresh rather than preselecting the last
	# one, so the picker is not scrolled to a costume you already added.
	if bool(button.get_meta("append", false)):
		current = ""
	_picker = AssetPickerOverlay.new()
	get_tree().current_scene.add_child(_picker)
	_picker.picked.connect(func(value: String): _set_asset(button, value))
	_picker.setup(kind, current, unavailable, kind == AssetPickerOverlay.Kind.SPRITE and _is_opponent())


func _set_asset(button: Button, value: String) -> void:
	var final_value := value
	if bool(button.get_meta("append", false)) and value != "":
		var existing := str(button.get_meta("value", ""))
		if existing != "":
			# Do not add the same costume twice -- the outro would skip the duplicate
			# anyway, but it reads as a mistake in the file.
			var parts := existing.split(",")
			for part in parts:
				if part.strip_edges() == value:
					return
			final_value = existing + ", " + value
	button.set_meta("value", final_value)
	button.text = final_value if final_value != "" else "(none)"
	# The button is narrower than some asset names, so the full value has to be
	# readable somewhere.
	button.tooltip_text = final_value

	var preview: TextureRect = button.get_meta("preview")
	if preview != null and is_instance_valid(preview):
		# A comma list previews its first entry; there is one preview slot.
		var first: String = final_value.split(",")[0].strip_edges() if final_value != "" else ""
		preview.texture = _preview_texture(int(button.get_meta("kind")), first)
	_revalidate()


func _preview_texture(kind: int, value: String) -> Texture2D:
	if value == "":
		return null
	match kind:
		AssetPickerOverlay.Kind.SPRITE:
			return AssetPickerOverlay.sprite_frame(value)
		AssetPickerOverlay.Kind.COIN:
			return _load_first(AssetPickerOverlay.COIN_DIR, value)
		AssetPickerOverlay.Kind.SLEEVE:
			return _load_first(AssetPickerOverlay.SLEEVE_DIR, value)
		AssetPickerOverlay.Kind.COSTUME:
			return _load_first(AssetPickerOverlay.COSTUME_DIR, value)
	return null


func _load_first(folder: String, value: String) -> Texture2D:
	for ext in [".png", ".jpg"]:
		var path: String = folder + value + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _asset_value(key: String) -> String:
	var button = _w.get(key)
	if button == null:
		return ""
	return str(button.get_meta("value", ""))


# ============================================================
# GIFT TYPE
# ============================================================

func _on_gift_type_changed(button: BaseButton) -> void:
	_gift_type = str(button.get_meta("gift", "none"))
	_set_gift_visibility()
	_revalidate()


func _set_gift_visibility() -> void:
	var uses_picker := _gift_type in ["coin", "costume", "sleeve"]
	var uses_text := _gift_type in ["card", "pack", "available_pack"]
	_w["gift_value"].get_parent().visible = uses_text
	_w["gift_asset"].get_parent().get_parent().visible = uses_picker
	_w["gift_hint"].text = str(GIFT_HINTS.get(_gift_type, ""))
	if uses_picker:
		var kind: int = AssetPickerOverlay.Kind.COIN
		if _gift_type == "costume":
			kind = AssetPickerOverlay.Kind.COSTUME
		elif _gift_type == "sleeve":
			kind = AssetPickerOverlay.Kind.SLEEVE
		# Switching gift kind invalidates whatever was picked for the old one.
		if int(_w["gift_asset"].get_meta("kind")) != kind:
			_w["gift_asset"].set_meta("kind", kind)
			_set_asset(_w["gift_asset"], "")


# ============================================================
# MUSIC AUDITION
# ============================================================

func _toggle_audition(button: Button) -> void:
	if _auditioning:
		_stop_audition()
		button.text = "PLAY"
		return
	var music: OptionButton = _w.get("music")
	if music == null or music.selected < 0:
		return
	# Remember what the map was playing so closing the form puts it back. Re-read
	# each time: a second audition starts from the restored map track, not from the
	# first audition.
	_bgm_before_audition = SoundManagerScript._current_bgm_path
	_auditioning = true
	button.text = "STOP"
	# The preview runs on its own audio bus, so it stays audible with the music slider
	# muted — muting the overworld loop while assigning tracks is the normal way to work.
	# The map track is stopped anyway so the two never play over each other.
	SoundManagerScript.stop_bgm()
	SoundManagerScript.play_audition_bgm(music.get_item_text(music.selected))


func _stop_audition() -> void:
	if not _auditioning:
		return
	_auditioning = false
	SoundManagerScript.stop_audition_bgm()
	if _bgm_before_audition != "":
		SoundManagerScript.play_bgm(_bgm_before_audition, true)


# ============================================================
# LOADING EXISTING VALUES
# ============================================================

func _apply_new_defaults() -> void:
	_set_asset(_w["sprite"], DEFAULT_SPRITE)
	_select_option(_w["message_colour"], DEFAULT_MESSAGE_COLOUR)
	_w["days"].text = DEFAULT_DAYS
	for letter in ["M", "A", "E", "N"]:
		_time_boxes[letter].button_pressed = true
	if _is_opponent():
		_select_music(DEFAULT_MUSIC)
		_w["cash_reward"].text = DEFAULT_CASH_REWARD


## The character's values as they resolve right now: its own fields, with the
## matched `when` rule layered on top, with the constants file underneath.
func _resolved_body() -> Dictionary:
	var body: Dictionary = {}
	for key in _character_raw:
		if key not in CharacterSchedule.SCHEDULE_KEYS:
			body[key] = _character_raw[key]
	var rules = _character_raw.get("when")
	if rules is Array and _rule_index >= 0 and _rule_index < rules.size():
		var hit = rules[_rule_index]
		if hit is Dictionary:
			for key in hit:
				if key in ["days", "times"]:
					continue
				if hit[key] == null:
					body.erase(key)
				else:
					body[key] = hit[key]
	var consts = _read_json(CONSTANTS_PATH).get(_section, {}).get(_existing_name, {})
	if consts is Dictionary:
		for key in consts:
			if not body.has(key):
				body[key] = consts[key]
	return body


func _load_values_into_form() -> void:
	var body := _resolved_body()
	var says = body.get("says", {})
	if not (says is Dictionary):
		says = {}

	_set_asset(_w["sprite"], str(body.get("sprite", "")))
	_select_option(_w["message_colour"], str(body.get("message_colour", DEFAULT_MESSAGE_COLOUR)))

	if _is_opponent():
		_w["name"].text = _existing_name
	else:
		_w["friendly_name"].text = str(body.get("friendly_name", _existing_name))
	# Renaming is not offered: the name is the key in the map file, the key in the
	# constants file, the target of every `beaten:` / `met:` gate, and the key the
	# save file records progress under. Changing one side and not the others is how
	# the migration made every NPC lose its sprite.
	_w["unique_key"].text = _existing_name + "     (renaming is not supported here)"

	# days / times are schedule keys and are stripped before the entry is built, so
	# they come from the raw body -- from the matched rule when there is one.
	var schedule_owner := _character_raw
	var rules = _character_raw.get("when")
	if rules is Array and _rule_index >= 0 and _rule_index < rules.size() \
			and rules[_rule_index] is Dictionary:
		schedule_owner = rules[_rule_index]
	_w["days"].text = str(schedule_owner.get("days", _character_raw.get("days", "")))
	var times := str(schedule_owner.get("times", _character_raw.get("times", "")))
	for letter in ["M", "A", "E", "N"]:
		_time_boxes[letter].button_pressed = times == "" or times.contains(letter)
	_w["loop"].button_pressed = bool(_character_raw.get("loop", true))

	_w["meet"].text = str(says.get("meet", ""))
	_w["repeat"].text = str(says.get("repeat", ""))

	if _is_opponent():
		_w["deck"].text = str(body.get("deck", ""))
		_select_music(str(body.get("music", "")))
		_w["prize_cards"].value = int(body.get("prize_cards", DEFAULT_PRIZE_CARDS))
		_w["match_format"].button_pressed = str(body.get("match_format", "")) == "best_of_3"
		_set_asset(_w["sleeve"], str(body.get("sleeve", "")))
		var granted := str(body.get("sleeve_reward", ""))
		_w["sleeve_reward"].button_pressed = granted != ""
		_w["cash_reward"].text = str(body.get("cash_reward", ""))
		var own_coin := str(body.get("coin_reward", ""))
		# This character's own coin must stay choosable in its own picker.
		_taken_coins.erase(own_coin)
		_set_asset(_w["coin_reward"], own_coin)
		_w["card_reward"].text = str(body.get("card_reward", ""))
		_w["pack_reward"].text = str(body.get("pack_reward", ""))
		_set_asset(_w["costume_reward"], str(body.get("costume_reward", "")))
		_w["first_win"].text = str(says.get("first_win", ""))
		_w["rematch_win"].text = str(says.get("rematch_win", ""))
		_w["loss"].text = str(says.get("loss", ""))
	else:
		var gift := str(body.get("gift_type", "none"))
		if gift == "" or not (gift in GIFT_TYPES):
			gift = "none"
		for cb in _gift_group.get_buttons():
			cb.button_pressed = str(cb.get_meta("gift", "")) == gift
		_gift_type = gift
		_set_gift_visibility()
		var gift_value := str(body.get("gift_value", ""))
		if gift in ["coin", "costume", "sleeve"]:
			_set_asset(_w["gift_asset"], gift_value)
		else:
			_w["gift_value"].text = gift_value


## get_item_text(-1) is an error, and an OptionButton whose folder listing came back
## empty has nothing selected. Fall back rather than write a broken value.
func _option_value(option: OptionButton, fallback: String) -> String:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return fallback
	return option.get_item_text(option.selected)


## Point the music picker at a stored value.
##
## The list only offers battle tracks, so anything else a character is already carrying --
## a location track, or one of the "REPLACEMUSIC" / "TEST" placeholders still scattered
## through the data -- is appended as a one-off entry first. Without that _select_option
## would quietly fall back to item 0 and CONFIRM would rewrite the character's track to
## whatever happens to sort first.
func _select_music(value: String) -> void:
	var music: OptionButton = _w.get("music")
	if music == null:
		return
	value = value.strip_edges()
	if value != "" and not _has_option(music, value):
		music.add_item(value)
	_select_option(music, value)


func _has_option(option: OptionButton, value: String) -> bool:
	for i in option.item_count:
		if option.get_item_text(i) == value:
			return true
	return false


func _select_option(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == value:
			option.select(i)
			option.tooltip_text = value
			return
	if option.item_count > 0 and option.selected < 0:
		option.select(0)
		option.tooltip_text = option.get_item_text(0)


# ============================================================
# VALIDATION
# ============================================================

func _on_name_changed() -> void:
	if _mode == Mode.EDIT:
		return
	var typed := _typed_name()
	var derived := _derive_unique_name(typed)
	if derived == "":
		_w["unique_key"].text = "-"
	elif derived == typed:
		_w["unique_key"].text = derived
	else:
		_w["unique_key"].text = "%s     (\"%s\" is taken)" % [derived, typed]
	_revalidate()


func _typed_name() -> String:
	if _is_opponent():
		return _w["name"].text.strip_edges()
	return _w["friendly_name"].text.strip_edges()


func _selected_times() -> String:
	var out: Array = []
	for letter in ["M", "A", "E", "N"]:
		if _time_boxes[letter].button_pressed:
			out.append(letter)
	return ",".join(out)


## Reject a days spec that matches nothing at all. days_match() is forgiving --
## garbage parses to int() 0 and silently matches no day -- so a typo would create
## a character that never appears with no error anywhere.
func _days_valid(spec: String) -> bool:
	var text := spec.strip_edges()
	if text == "" or text == "*":
		return true
	for day in range(-1, 61):
		if CharacterSchedule.days_match(text, day):
			return true
	return false


func _problems() -> Array:
	var out: Array = []
	if _typed_name() == "":
		out.append("name")
	if _asset_value("sprite") == "":
		out.append("sprite")
	if not _days_valid(_w["days"].text):
		out.append("days (matches no day)")
	if _selected_times() == "":
		out.append("at least one time of day")
	if _is_opponent():
		if _w["deck"].text.strip_edges() == "":
			out.append("deck")
		if _asset_value("sleeve") == "":
			out.append("sleeve")
		var cash: String = _w["cash_reward"].text.strip_edges()
		if cash != "" and not cash.is_valid_int():
			out.append("cash reward (must be a whole number)")
	else:
		if _gift_type in ["coin", "costume", "sleeve"] and _asset_value("gift_asset") == "":
			out.append("gift asset")
		if _gift_type in ["card", "pack", "available_pack"] \
				and _w["gift_value"].text.strip_edges() == "":
			out.append("gift value")
	return out


func _revalidate() -> void:
	if _confirm_btn == null or _status == null:
		return
	var problems := _problems()
	_confirm_btn.disabled = not problems.is_empty()
	if problems.is_empty():
		_status.text = "ready -- Confirm places the character, then Enter in the placement tool saves"
		_status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	else:
		_status.text = "still needed:  " + ", ".join(problems)
		_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	# Opponents also need an in-battle portrait, which 210 overworld sprites lack.
	var sprite := _asset_value("sprite")
	if problems.is_empty() and _is_opponent() and sprite != "" \
			and not AssetPickerOverlay.has_battle_portrait(sprite):
		_status.text = "WARNING: \"%s\" has no in-battle portrait -- the match intro will show nothing" % sprite
		_status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.18))


# ============================================================
# BUILDING THE DRAFT
# ============================================================

## Everything the form knows, as flat field -> value. Empty values are dropped so a
## blank box never writes an empty string into the data.
func _collect_values() -> Dictionary:
	var v: Dictionary = {}
	v["sprite"] = _asset_value("sprite")
	v["message_colour"] = _option_value(_w["message_colour"], DEFAULT_MESSAGE_COLOUR)

	var says: Dictionary = {}
	for key in ["meet", "repeat", "first_win", "rematch_win", "loss"]:
		if _w.has(key):
			var text: String = _w[key].text.strip_edges()
			if text != "":
				says[key] = text
	if not says.is_empty():
		v["says"] = says

	if _is_opponent():
		v["deck"] = _w["deck"].text.strip_edges()
		v["music"] = _option_value(_w["music"], DEFAULT_MUSIC)
		v["prize_cards"] = int(_w["prize_cards"].value)
		# cash_reward is a String everywhere in the data and int()d on read.
		var cash: String = _w["cash_reward"].text.strip_edges()
		v["cash_reward"] = cash if cash != "" else "0"
		v["coin_reward"] = _asset_value("coin_reward")
		v["card_reward"] = _w["card_reward"].text.strip_edges()
		v["pack_reward"] = _w["pack_reward"].text.strip_edges()
		v["costume_reward"] = _asset_value("costume_reward")
		v["sleeve"] = _asset_value("sleeve")
		if _w["match_format"].button_pressed:
			v["match_format"] = "best_of_3"
		if _w["sleeve_reward"].button_pressed:
			v["sleeve_reward"] = _asset_value("sleeve")
	else:
		v["friendly_name"] = _typed_name()
		if _gift_type != "none":
			v["gift_type"] = _gift_type
			if _gift_type in ["coin", "costume", "sleeve"]:
				v["gift_value"] = _asset_value("gift_asset")
			else:
				v["gift_value"] = _w["gift_value"].text.strip_edges()

	for key in v.keys():
		if v[key] is String and str(v[key]) == "":
			v.erase(key)
	return v


## Split the form's values across the two files, and inside the map file across the
## character's defaults and the rule that matched.
func _build_draft() -> Dictionary:
	var name := _existing_name if _mode == Mode.EDIT else _derive_unique_name(_typed_name())
	var values := _collect_values()
	var constant_fields: Array = CONSTANT_FIELDS_OPP if _is_opponent() else CONSTANT_FIELDS_NPC

	var to_constants: Dictionary = {}
	var to_character: Dictionary = {}
	var to_rule: Dictionary = {}

	for field in values:
		var target := "character"
		if field in constant_fields:
			# A field the map file already overrides stays overridden there -- moving
			# it back to constants would silently change the character everywhere
			# else they appear.
			if _mode == Mode.EDIT and _overridden_in_rule(field):
				target = "rule"
			elif _mode == Mode.EDIT and _character_raw.has(field):
				target = "character"
			else:
				target = "constants"
		elif _mode == Mode.EDIT and _overridden_in_rule(field):
			target = "rule"
		match target:
			"constants": to_constants[field] = values[field]
			"rule":      to_rule[field] = values[field]
			_:           to_character[field] = values[field]

	# Schedule keys never live in constants.
	var times := _selected_times()
	var days: String = _w["days"].text.strip_edges()
	if _mode == Mode.EDIT and _rule_index >= 0:
		to_rule["days"] = days
		to_rule["times"] = times
	else:
		to_character["days"] = days
		to_character["times"] = times
	# `loop` defaults to true, so it is only written when it is false -- writing
	# `"loop": true` on every character would be noise in every file.
	if not _w["loop"].button_pressed:
		to_character["loop"] = false
	elif _mode == Mode.EDIT and _character_raw.has("loop"):
		to_character["loop"] = true

	# A new character needs a `move` in the file -- every one of the 249 existing
	# characters has one. The placement tool's R key rewrites it through the normal
	# path afterwards, which targets the same place.
	if _mode == Mode.NEW:
		to_character["move"] = "idle_random" if _is_opponent() else "idle_down"

	# Anything optional that used to have a value and no longer does is removed
	# outright, wherever it lives -- clearing a reward has to actually clear it.
	var to_remove: Array = []
	if _mode == Mode.EDIT:
		var before := _resolved_body()
		var clearable: Array = CLEARABLE_FIELDS_OPP if _is_opponent() else CLEARABLE_FIELDS_NPC
		for field in clearable:
			if before.has(field) and not values.has(field):
				to_remove.append(field)

	return {
		"section": _section,
		"name": name,
		"is_new": _mode == Mode.NEW,
		"rule_index": _rule_index if _mode == Mode.EDIT else -1,
		"constants": to_constants,
		"character": to_character,
		"rule": to_rule,
		"remove": to_remove,
		"entry": _build_entry(name, values, to_remove),
	}


## Did the matched rule state this field itself, rather than inherit it? Mirrors
## CharacterSchedule._rule_sets -- a field the rule owns is rewritten in the rule,
## keeping a Tuesday-evening override scoped to Tuesday evenings.
func _overridden_in_rule(field: String) -> bool:
	if _rule_index < 0:
		return false
	var rules = _character_raw.get("when")
	if not (rules is Array) or _rule_index >= rules.size():
		return false
	var rule = rules[_rule_index]
	return rule is Dictionary and rule.get(field) != null


## The spawn-shaped entry MapManager consumes, so the draft can be shown in the
## world before anything is written. Position is filled in by the placement tool.
##
## An edit starts from the character exactly as it resolves on disk right now,
## expanded by CharacterSchedule -- the same call the map itself spawned them
## through -- and only then layers the form's values on top. Building the entry out
## of the form alone silently dropped everything the form does not ask about: a
## patrol line's axis, distance and speed, a wanderer's radius, npc_type. The actor
## came back standing still, and the placement tool, reading the pattern off the
## respawned node, then believed that was the pattern the character had.
func _build_entry(name: String, values: Dictionary, removals: Array = []) -> Dictionary:
	var entry: Dictionary = {"name": name}
	if _mode == Mode.EDIT:
		entry = CharacterSchedule.to_entry(name, _resolved_body())
		entry["name"] = name
		# The placement tool owns where the actor stands -- it hands the position in
		# separately, and for an edit that is wherever they already are.
		entry.erase("position")
		# A field the save is about to clear has to be gone here too, or the actor in
		# front of you keeps a reward the file no longer grants.
		for field in removals:
			entry.erase(field)
		# `says` is rewritten wholesale whenever the form has any text at all, so the
		# old lines go with it. With every box emptied the file keeps what it had, and
		# so does the actor.
		if values.get("says") is Dictionary:
			for key in ["meet_text", "repeat_text", "first_win_text", "rematch_win_text", "loss_text"]:
				entry.erase(key)
	for key in values:
		if key == "says":
			continue
		entry[key] = values[key]
	var says = values.get("says", {})
	if says is Dictionary:
		if says.has("meet"):        entry["meet_text"] = says["meet"]
		if says.has("repeat"):      entry["repeat_text"] = says["repeat"]
		if says.has("first_win"):   entry["first_win_text"] = says["first_win"]
		if says.has("rematch_win"): entry["rematch_win_text"] = says["rematch_win"]
		if says.has("loss"):        entry["loss_text"] = says["loss"]
	if not _is_opponent() and not entry.has("npc_type"):
		entry["npc_type"] = "text_only"
	# Only a brand new character needs a pattern invented for it. An edited one keeps
	# whatever it was walking with -- the placement tool's R key is the only thing
	# that changes a movement pattern.
	if not entry.has("pattern"):
		entry["pattern"] = "idle_random" if _is_opponent() else "idle_down"
	return entry


# ============================================================
# EXIT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# ONLY Escape is consumed. _input() runs before GUI input, so marking an event
	# handled here stops it ever reaching the focused LineEdit -- consuming the whole
	# event stream would leave every text box in this form unable to be typed into.
	#
	# Nothing else needs consuming: PlacementTool._input() stands down entirely while
	# the form is open, MapManager's debug keys stand down while the tool is open, and
	# BaseMapScene already stands down for the tool. Enter is deliberately not bound --
	# a multiline dialogue box needs it for newlines, so Confirm is a button.
	if event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	if not _problems().is_empty():
		return
	var draft := _build_draft()
	_stop_audition()
	confirmed.emit(draft)
	queue_free()


func _cancel() -> void:
	_stop_audition()
	cancelled.emit()
	queue_free()
