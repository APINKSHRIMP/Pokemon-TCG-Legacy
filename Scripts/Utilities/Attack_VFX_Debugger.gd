extends CanvasLayer

## The in-match ATTACK ANIMATION TESTER. DEL during a match (debug builds only -- the match's own
## _input opens it behind DebugMode.is_enabled()).
##
## Pick any attack in the game (or a raw effect recipe, or a Special Condition overlay) and press PLAY:
## the tester hides, the animation plays from your Active to the opponent's, then back the other way,
## and the tester comes back with the same row selected. Nothing in the match changes.
##
##   type to search    Enter / double-click = PLAY    DEL / Escape = close

# ---- tweakables -------------------------------------------------------------
const LAYER := 130
const MARGIN := 60
const TITLE_FONT_SIZE := 34
const FONT_SIZE := 22
const LIST_FONT_SIZE := 20
const NOTE_FONT_SIZE := 18
const BUTTON_HEIGHT := 50
const LIST_WIDTH := 1060
const PANEL_TOP := 120
const PANEL_HEIGHT := 860
const PAUSE_BETWEEN := 0.45      # seconds between the two directions
const HEADING_COLOUR := Color(1.0, 0.85, 0.4)
const INFO_COLOUR := Color(0.45, 0.85, 1.0)
const NOTE_COLOUR := Color(0.8, 0.84, 0.92)
const BAD_COLOUR := Color(1.0, 0.55, 0.45)
# -----------------------------------------------------------------------------

enum Mode { ATTACKS, EFFECTS, STATUS, SOUNDS }

var main   # Main_Match_Core_Gameplay_Script
var _mode: int = Mode.ATTACKS
var _search: LineEdit
var _list: ItemList
var _info: Label
var _status: Label
var _both_ways: CheckBox
var _mode_buttons: Array = []
var _rows: Array = []        # the key behind each visible row
var _playing := false
var _last_key := {}          # mode -> last played key, so reopening lands on it


func _ready() -> void:
	layer = LAYER
	_build()
	_fill()
	_search.call_deferred("grab_focus")


func _build() -> void:
	var root := ColorRect.new()
	root.color = DebugFormTheme.BACKDROP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = DebugFormTheme.build()
	add_child(root)

	var title := _label("ATTACK ANIMATION TESTER", TITLE_FONT_SIZE)
	title.position = Vector2(MARGIN, 24)
	root.add_child(title)
	var hint := _label("Type to search  ·  Enter / double-click = PLAY  ·  DEL or Esc to close", NOTE_FONT_SIZE, NOTE_COLOUR)
	hint.position = Vector2(1920 - MARGIN - 900, 36)
	hint.size = Vector2(900, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	# Left: mode, search, list.
	var left := VBoxContainer.new()
	left.position = Vector2(MARGIN, PANEL_TOP - 40)
	left.size = Vector2(LIST_WIDTH, PANEL_HEIGHT + 40)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	left.add_child(modes)
	for m in [[Mode.ATTACKS, "ATTACKS"], [Mode.EFFECTS, "EFFECT RECIPES"], [Mode.STATUS, "CONDITIONS"], [Mode.SOUNDS, "SOUND CLIPS"]]:
		var b := _button(m[1], _set_mode.bind(m[0]))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
		_mode_buttons.append(b)
	_search = LineEdit.new()
	_search.placeholder_text = "Search attacks, recipes or effects..."
	_search.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_search.add_theme_font_size_override("font_size", FONT_SIZE)
	_search.text_changed.connect(func(_t): _fill())
	_search.text_submitted.connect(func(_t): _play_selected())
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_list.item_selected.connect(func(_i): _show_info())
	_list.item_activated.connect(func(_i): _play_selected())
	left.add_child(_list)

	# Right: details and buttons.
	var right := VBoxContainer.new()
	right.position = Vector2(MARGIN + LIST_WIDTH + 40, PANEL_TOP)
	right.size = Vector2(1920 - MARGIN * 2 - LIST_WIDTH - 40, PANEL_HEIGHT)
	right.add_theme_constant_override("separation", 12)
	root.add_child(right)
	right.add_child(_label("SELECTED", FONT_SIZE, HEADING_COLOUR))
	_info = _label("", NOTE_FONT_SIZE, NOTE_COLOUR)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 470)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_info)
	_both_ways = CheckBox.new()
	_both_ways.text = "Play both ways (you -> opponent, then back)"
	_both_ways.button_pressed = true
	_both_ways.focus_mode = Control.FOCUS_NONE
	_both_ways.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	right.add_child(_both_ways)
	right.add_child(_button("PLAY", _play_selected))
	right.add_child(_button("PLAY NEXT IN LIST", _play_next))
	right.add_child(_button("CLOSE", close))
	_status = _label("", NOTE_FONT_SIZE, INFO_COLOUR)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	_set_mode(Mode.ATTACKS)


# ============================================================
# LIST
# ============================================================

func _set_mode(m: int) -> void:
	_mode = m
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == m)
	_fill()


func _fill() -> void:
	var vfx = main.attack_vfx
	if vfx == null:
		return
	var q := _search.text.strip_edges().to_lower()
	_list.clear()
	_rows.clear()
	var keys: Array = []
	match _mode:
		Mode.ATTACKS: keys = vfx.attack_names()
		Mode.EFFECTS: keys = vfx.recipe_ids()
		Mode.STATUS: keys = vfx.status_kinds()
		Mode.SOUNDS: keys = vfx.sound_clips()
	for k in keys:
		var text := str(k)
		if _mode == Mode.ATTACKS:
			var info: Dictionary = vfx.attack_info(text)
			var fx := str(info.get("fx", "?"))
			if fx == "@type":
				fx = "%s fallback" % info.get("type", "?")
			text = "%s   ->   %s" % [k, fx]
		if q != "" and not q in text.to_lower():
			continue
		_list.add_item(text)
		_rows.append(str(k))
	var want := str(_last_key.get(_mode, ""))
	var idx := _rows.find(want)
	if idx < 0 and not _rows.is_empty():
		idx = 0
	if idx >= 0:
		_list.select(idx)
		_list.ensure_current_is_visible()
	_status.text = "%d shown" % _rows.size()
	_show_info()


func _selected_key() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] >= _rows.size():
		return ""
	return _rows[sel[0]]


func _show_info() -> void:
	var key := _selected_key()
	var vfx = main.attack_vfx
	if key == "" or vfx == null:
		_info.text = ""
		return
	var lines: Array = []
	var recipe: Dictionary = {}
	match _mode:
		Mode.ATTACKS:
			var info: Dictionary = vfx.attack_info(key)
			recipe = vfx.recipe_by_name(key, str(info.get("type", "Colorless")), int(info.get("cost", 1)))
			lines.append(key)
			lines.append("Recipe: %s   (chosen by: %s)" % [recipe.get("_id", "?"), info.get("how", "?")])
			lines.append("Main type: %s   Usual cost: %s   Damaging: %s" % [info.get("type", "?"), info.get("cost", "?"), "yes" if info.get("dmg", false) else "no"])
			if info.has("by_type"):
				lines.append("Per-type: %s" % JSON.stringify(info["by_type"]))
			if info.has("status"):
				lines.append("Then plays: %s" % ", ".join(info["status"]))
			if info.get("bench", false):
				lines.append("(This attack also damages the Bench.)")
		Mode.EFFECTS:
			recipe = vfx.recipe_by_id(key)
			lines.append(key)
		Mode.STATUS:
			lines.append(key + "  (overlay played when the condition lands)")
		Mode.SOUNDS:
			var si: Dictionary = vfx.sound_info(key)
			lines.append(key)
			lines.append("Length %.2fs   main hit at %.2fs   onsets %s" % [float(si.get("dur", 0)), float(si.get("hit", 0)), str(si.get("onsets", []))])
			lines.append("PLAY auditions it without the animation.")
	if not recipe.is_empty():
		var snd := str(recipe.get("_sfx", recipe.get("sfx", "-")))
		lines.append("Sound: %s%s" % [snd, "   (its own game move)" if recipe.has("_sfx") else ""])
		lines.append("")
		lines.append("Element: %s   Body: %s   Reaction: %s%s%s" % [recipe.get("element", "normal"), recipe.get("body", "none"),
			recipe.get("react", "knock"), (" x%d" % int(recipe["hits"])) if recipe.has("hits") else "",
			"   HEAVY" if str(recipe.get("power", "")) == "heavy" else ""])
		if recipe.has("screen") or recipe.get("recoil", false):
			lines.append("Screen: %s%s" % [JSON.stringify(recipe.get("screen", {})), "   + recoil" if recipe.get("recoil", false) else ""])
		for s in recipe.get("steps", []):
			var bits: Array = ["%s %s" % [s.get("at", "?"), s.get("fx", "")]]
			for k in ["par", "count", "orient", "spin", "arc", "anchor", "hue", "hue_cycle", "tint", "loops", "delay"]:
				if s.has(k):
					bits.append("%s=%s" % [k, s[k]])
			lines.append("  - " + "  ".join(bits))
	_info.text = "\n".join(lines)


# ============================================================
# PLAYING
# ============================================================

func _play_next() -> void:
	var sel := _list.get_selected_items()
	var i: int = (sel[0] + 1) if not sel.is_empty() else 0
	if i >= _rows.size():
		return
	_list.select(i)
	_list.ensure_current_is_visible()
	_show_info()
	_play_selected()


func _play_selected() -> void:
	if _playing:
		return
	var key := _selected_key()
	if key == "":
		return
	if _mode == Mode.SOUNDS:
		main.attack_vfx.audition(key)
		_status.text = "Playing: " + key
		return
	var a: card_object = main.player_active_pokemon
	var d: card_object = main.opponent_active_pokemon
	if a == null or d == null:
		_status.text = "Both players need an Active Pokémon on the board."
		_status.add_theme_color_override("font_color", BAD_COLOUR)
		return
	_status.add_theme_color_override("font_color", INFO_COLOUR)
	_last_key[_mode] = key
	_playing = true
	visible = false
	await _play_one_way(key, a, d)
	if _both_ways.button_pressed and is_inside_tree():
		await get_tree().create_timer(PAUSE_BETWEEN).timeout
		await _play_one_way(key, d, a)
	_playing = false
	if is_inside_tree():
		visible = true
		_status.text = "Played: " + key


func _play_one_way(key: String, attacker: card_object, defender: card_object) -> void:
	var vfx = main.attack_vfx
	match _mode:
		Mode.ATTACKS:
			await vfx.preview_attack(key, attacker, defender)
		Mode.EFFECTS:
			await vfx.play(attacker, defender, vfx.recipe_by_id(key), {"damage": vfx.PREVIEW_DAMAGE})
		Mode.STATUS:
			await vfx.preview_status(defender, key)


func close() -> void:
	if _playing:
		return
	main.close_vfx_debugger()


# ============================================================
# INPUT / HELPERS
# ============================================================

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if event.keycode == KEY_ESCAPE or (event.keycode == KEY_DELETE and _search.text == ""):
		get_viewport().set_input_as_handled()
		close()
	elif event.keycode in [KEY_UP, KEY_DOWN] and _rows.size() > 0:
		# Arrow keys move the list selection even while the search box has focus.
		get_viewport().set_input_as_handled()
		var sel := _list.get_selected_items()
		var i: int = sel[0] if not sel.is_empty() else 0
		i = clampi(i + (1 if event.keycode == KEY_DOWN else -1), 0, _rows.size() - 1)
		_list.select(i)
		_list.ensure_current_is_visible()
		_show_info()


func _label(text: String, font_size: int, colour: Color = DebugFormTheme.ON_BACKDROP) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


## FOCUS_NONE: Space / Enter would otherwise press the last-clicked button again.
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(action)
	return button
