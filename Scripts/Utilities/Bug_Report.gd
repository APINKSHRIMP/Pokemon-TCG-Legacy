extends Node

## Autoload "BugReport" -- the REPORT BUG button on every DEL debug menu. Debug builds only.
##
## Every DEL debug menu shows REPORT BUG in the same spot, top right. It hides the menu,
## pauses the game and shows only a white text box with SAVE / CANCEL over the screen DEL
## was pressed on. SAVE adds the text as a new row at the bottom of the Game_Issues tab of
## Spreadsheets/Issue_Log.xlsx: next free number, the text as the Issue, Status "New Issue",
## today as Logged, and a snapshot of the game in the hidden column K "Report Context"
## (screen, menus, player position, last inputs, match log file + turn, end of the Godot log).
## Category / Sub Cat stay blank: "fix issues" fills them in.
##
## Screens with no debug menu of their own (deck builder, the Esc menu, shops, cutscenes...)
## get a bare one from here holding just REPORT BUG, so DEL works everywhere.
##
## A debug menu joins by calling register_menu(self, close_action, kind) when it opens.
##
## Writing the .xlsx: each report is appended to Spreadsheets/_pending_bug_reports.jsonl,
## then Scripts/Utilities/bug_report_import.py (openpyxl) moves everything in that file
## into the sheet. If Excel has the workbook open the save fails and the report waits in
## the pending file until the next report, or until "fix issues" runs the script.
##
##   Ctrl + Enter = SAVE    Esc = CANCEL    (the bare menu: Del / Esc closes)

# ---- tweakables -------------------------------------------------------------
## Above every debug menu (they sit on 130).
const BUTTON_LAYER := 135
const BOX_LAYER := 140
const TOAST_LAYER := 141
const MENU_LAYER := 130
const MARGIN_RIGHT := 48
const MARGIN_TOP := 24
const BUTTON_SIZE := Vector2(190, 44)
## Width the debug menus leave free at the top right for the button (its width + a gap).
const BUTTON_RESERVE := 208.0
const BOX_SIZE := Vector2(1000, 220)   # half height (2026-11-23), so more of the screen shows around it
const BOX_FONT_SIZE := 24
const BUTTON_FONT_SIZE := 19
const INPUT_HISTORY := 30
const LOG_TAIL_LINES := 60
const LOG_TAIL_BYTES := 16000
const TOAST_SECONDS := 4.0
## Excel's cell limit is 32,767 characters.
const CONTEXT_MAX_CHARS := 30000
# -----------------------------------------------------------------------------

const PENDING_FILE := "res://Spreadsheets/_pending_bug_reports.jsonl"
const IMPORT_SCRIPT := "res://Scripts/Utilities/bug_report_import.py"

## [{menu: Node, close: Callable, kind: String}], newest last.
var _menus: Array = []
var _built := false
var _button_layer: CanvasLayer = null
var _box_layer: CanvasLayer = null
var _toast_layer: CanvasLayer = null
var _text: TextEdit = null
var _save_button: Button = null
var _toast: Label = null
var _toast_tween: Tween = null
var _fallback: CanvasLayer = null
var _fallback_was_paused := false
var _fallback_focus: Control = null
var _box_open := false
var _box_was_paused := false
var _box_menu: Dictionary = {}
var _context := ""
## [ticks_msec, text] for the last INPUT_HISTORY presses / clicks.
var _inputs: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not DebugMode.is_enabled():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	# window_input fires before any node sees the event, so presses a screen swallows
	# in its own _input are still recorded.
	var root := get_tree().root
	if root.has_signal("window_input"):
		root.window_input.connect(_record_input)


# ============================================================
# PUBLIC
# ============================================================

## A debug menu calls this when it opens. `close_action` closes it (used after SAVE);
## `kind` names it in the report.
func register_menu(menu: Node, close_action: Callable, kind: String) -> void:
	if not DebugMode.is_enabled():
		return
	_build()
	_menus.append({"menu": menu, "close": close_action, "kind": kind})


## True while the white text box is up. InputDevice checks it so its arrow-key focus
## moves leave the text box alone.
func is_box_open() -> bool:
	return _box_open


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var key := event as InputEventKey
	if _box_open:
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close_box(false)
		elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and key.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_save_box()
		return
	if _fallback != null and (key.keycode == KEY_ESCAPE or key.keycode == KEY_DELETE):
		get_viewport().set_input_as_handled()
		close_fallback()


## DEL nobody else used: open the bare debug menu -- one frame later, because the screen's
## own DEL handler (MapManager's overworld menu) may come after this one in the same event.
func _unhandled_input(event: InputEvent) -> void:
	if _box_open or _fallback != null:
		return
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if (event as InputEventKey).keycode != KEY_DELETE:
		return
	_on_free_delete.call_deferred(_menu_entry(false) != {})


func _on_free_delete(menu_was_open: bool) -> void:
	if menu_was_open or _menu_entry(false) != {} or _box_open or _fallback != null:
		return
	if get_tree().current_scene == null or MapManager.is_placement_tool_open():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	open_fallback()


func _process(_delta: float) -> void:
	if _button_layer == null:
		return
	var show := not _box_open and _menu_entry(true) != {}
	if _button_layer.visible != show:
		_button_layer.visible = show


func _record_input(event: InputEvent) -> void:
	var line := ""
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		line = "key " + OS.get_keycode_string(k.get_keycode_with_modifiers())
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if not m.pressed or m.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		var which := "left" if m.button_index == MOUSE_BUTTON_LEFT else ("right" if m.button_index == MOUSE_BUTTON_RIGHT else "button %d" % m.button_index)
		line = "%s click at window (%d, %d)%s%s" % [which, m.position.x, m.position.y,
				" double" if m.double_click else "", _hovered_text()]
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return
		line = "pad button %d" % (event as InputEventJoypadButton).button_index
	else:
		return
	_inputs.append([Time.get_ticks_msec(), line])
	if _inputs.size() > INPUT_HISTORY:
		_inputs.pop_front()


# ============================================================
# THE BARE DEBUG MENU (screens without one)
# ============================================================

func open_fallback() -> void:
	if _fallback != null:
		return
	_build()
	_fallback_focus = get_viewport().gui_get_focus_owner()
	_fallback = CanvasLayer.new()
	_fallback.layer = MENU_LAYER
	_fallback.name = "BareDebugMenu"
	var root := ColorRect.new()
	root.color = Color(DebugFormTheme.BACKDROP, 0.82)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = DebugFormTheme.build()
	_fallback.add_child(root)
	var title := _label("Debug menu", 32, DebugFormTheme.ON_BACKDROP)
	title.position = Vector2(48, MARGIN_TOP)
	root.add_child(title)
	var note := _label("This screen has no debug tools of its own. Del or Esc closes.", 17, DebugFormTheme.INK_DIM)
	note.position = Vector2(50, MARGIN_TOP + 52)
	root.add_child(note)
	var close := DebugFormTheme.button("Close", close_fallback, "Del or Esc", "", BUTTON_FONT_SIZE)
	_anchor_top_right(close, MARGIN_RIGHT + BUTTON_RESERVE, Vector2(130, BUTTON_SIZE.y))
	root.add_child(close)
	add_child(_fallback)
	_fallback_was_paused = get_tree().paused
	get_tree().paused = true
	get_viewport().gui_release_focus()
	register_menu(_fallback, close_fallback, "bare debug menu (this screen has none of its own)")


func close_fallback() -> void:
	if _fallback == null:
		return
	remove_child(_fallback)
	_fallback.queue_free()
	_fallback = null
	get_tree().paused = _fallback_was_paused
	if _fallback_focus != null and is_instance_valid(_fallback_focus) and _fallback_focus.is_visible_in_tree():
		_fallback_focus.grab_focus()
	_fallback_focus = null


# ============================================================
# THE TEXT BOX
# ============================================================

func _open_box() -> void:
	if _box_open:
		return
	_box_menu = _menu_entry(true)
	_context = _gather_context(_box_menu)
	_box_open = true
	_box_was_paused = get_tree().paused
	get_tree().paused = true
	if _box_menu != {}:
		(_box_menu["menu"] as Node).set("visible", false)
	_button_layer.visible = false
	_text.text = ""
	_save_button.disabled = false
	_save_button.text = "SAVE"
	_box_layer.visible = true
	_text.grab_focus()


func _close_box(saved: bool) -> void:
	if not _box_open:
		return
	_box_open = false
	_box_layer.visible = false
	_text.release_focus()
	get_tree().paused = _box_was_paused
	var entry := _box_menu
	_box_menu = {}
	if entry == {} or not is_instance_valid(entry["menu"]):
		return
	if saved and (entry["close"] as Callable).is_valid():
		(entry["close"] as Callable).call()
	else:
		(entry["menu"] as Node).set("visible", true)


func _save_box() -> void:
	if not _box_open or _save_button.disabled:
		return
	var text := _text.text.strip_edges()
	if text == "":
		_show_toast("Type what went wrong first, or press CANCEL.", DebugFormTheme.WARN)
		return
	_save_button.disabled = true
	_save_button.text = "Saving..."
	# Let "Saving..." draw: the import below blocks for a second or two.
	await get_tree().process_frame
	await get_tree().process_frame
	var result: Array = _write_report(text, _context)
	_close_box(true)
	_show_toast(str(result[0]), DebugFormTheme.SUCCESS if bool(result[1]) else DebugFormTheme.WARN)


## Appends the report to the pending file, then runs the importer. [message, ok].
func _write_report(text: String, context: String) -> Array:
	var d := Time.get_date_dict_from_system()
	var entry := {
		"text": text,
		"context": context,
		"logged": "%02d/%02d/%04d" % [d["day"], d["month"], d["year"]],
	}
	var pending := ProjectSettings.globalize_path(PENDING_FILE)
	var f: FileAccess = null
	if FileAccess.file_exists(pending):
		f = FileAccess.open(pending, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(pending, FileAccess.WRITE)
	if f == null:
		push_error("BUG REPORT: can't write %s (error %d)" % [pending, FileAccess.get_open_error()])
		return ["Couldn't save the report: %s can't be written." % pending, false]
	f.store_line(JSON.stringify(entry))
	f.close()

	var output: Array = []
	var code := OS.execute("py", ["-3", ProjectSettings.globalize_path(IMPORT_SCRIPT)], output, true)
	var out := ""
	for chunk in output:
		out += str(chunk)
	out = out.strip_edges()
	print("BUG REPORT: importer exit ", code, ": ", out)
	if code == 0:
		var numbers := PackedStringArray()
		for line in out.split("\n"):
			if line.begins_with("ADDED #"):
				numbers.append(line.trim_prefix("ADDED ").strip_edges())
		return ["Bug %s added to the Issue Log." % ", ".join(numbers), true]
	if code == 3:
		return ["Issue_Log.xlsx is open in Excel. The bug is kept and goes in with the next report (or \"fix issues\").", false]
	return ["Couldn't add it to the Issue Log (error %d). It's kept in _pending_bug_reports.jsonl." % code, false]


# ============================================================
# CONTEXT SNAPSHOT (the hidden column)
# ============================================================

func _gather_context(menu_entry: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("reported: " + Time.get_datetime_string_from_system(false, true))
	lines.append("code: " + _git_commit())
	lines.append("debug menu: " + (str(menu_entry["kind"]) if menu_entry != {} else "?"))
	var scene := get_tree().current_scene
	if scene != null:
		lines.append("scene: %s (%s)" % [scene.scene_file_path, scene.name])
	lines.append("on screen: " + ", ".join(_visible_layers(scene)))
	var vp := get_viewport()
	lines.append("window %s, view %s, mouse %s" % [DisplayServer.window_get_size(), vp.get_visible_rect().size,
			vp.get_mouse_position().round()])
	lines.append("input device: %s" % str(InputDevice.get("last")))
	lines.append("save slot %d, day %d, %s, clock %.2f h, cash %d" % [GameState.current_slot, GameState.get_date(),
			GameState.get_time(), GameState.clock_hours(), GameState.get_cash()])

	var player = MapManager.get("_player")
	if player != null and is_instance_valid(player) and (player as Node).is_inside_tree():
		var where := "map %s, player at %s" % [str(MapManager.get("_map_scene_path")), (player as Node2D).global_position.round()]
		for prop in ["facing", "facing_direction", "last_direction", "can_move"]:
			if prop in player:
				where += ", %s %s" % [prop, str(player.get(prop))]
		lines.append(where)

	var main := _find_match(scene)
	if main != null:
		var opp = main.get("opponent_data")
		var opp_name := str(opp.get("name", "?")) if opp is Dictionary else str(opp)
		var log_path := "(no match log)"
		if main.has_method("_rec"):
			var rec = main.call("_rec")
			if rec != null and str(rec.get("path")) != "":
				log_path = ProjectSettings.globalize_path(str(rec.get("path")))
		lines.append("match vs %s, turn %s, %s turn, game over %s" % [opp_name, str(main.get("turn_number")),
				"CPU's" if bool(main.get("opponents_turn_active")) else "player's", str(main.get("game_is_over"))])
		lines.append("match log: " + log_path)

	var now := Time.get_ticks_msec()
	lines.append("last inputs (oldest first):")
	for item in _inputs:
		lines.append("  %.1fs ago  %s" % [(now - int(item[0])) / 1000.0, str(item[1])])
	var log_file := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	lines.append("godot log tail (%s):" % ProjectSettings.globalize_path(log_file))
	for line in _log_tail(log_file):
		lines.append("  " + line)
	var text := "\n".join(lines)
	if text.length() > CONTEXT_MAX_CHARS:
		text = text.left(CONTEXT_MAX_CHARS)
	return text


func _find_match(scene: Node) -> Node:
	if scene == null:
		return null
	if scene.has_method("open_vfx_debugger"):
		return scene
	for child in scene.get_children():
		if child.has_method("open_vfx_debugger"):
			return child
	return null


## The visible layers / panels at the top of the screen (the current scene's children and
## anything parked straight on the root), so the report says which menus were up.
func _visible_layers(scene: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var pool: Array = []
	if scene != null:
		pool.append_array(scene.get_children())
	for n in get_tree().root.get_children():
		if n != scene and n != self and not (n.name in ["GameDataManager", "SoundManagerScript", "GameState",
				"UITheme", "SceneCache", "MapManager", "PackOpeningManager", "InputDevice"]):
			pool.append(n)
	for n in pool:
		if n is CanvasLayer and (n as CanvasLayer).visible:
			out.append("%s [layer %d]" % [n.name, (n as CanvasLayer).layer])
		elif n is Control and (n as Control).visible:
			out.append(str(n.name))
		if out.size() >= 40:
			break
	return out


func _hovered_text() -> String:
	var vp := get_viewport()
	if vp != null and vp.has_method("gui_get_hovered_control"):
		var c = vp.call("gui_get_hovered_control")
		if c is Control:
			return " on " + _node_label(c as Control)
	return ""


## The last three parts of a node's path, plus a button's text.
func _node_label(n: Node) -> String:
	var parts := str(n.get_path()).split("/")
	var short := "/".join(parts.slice(maxi(parts.size() - 3, 0)))
	if n is Button and (n as Button).text != "":
		short += " \"%s\"" % (n as Button).text.left(40)
	return short


func _log_tail(path: String) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray(["(can't read the log)"])
	var length := f.get_length()
	var start := maxi(0, length - LOG_TAIL_BYTES)
	f.seek(start)
	var lines := f.get_buffer(length - start).get_string_from_utf8().split("\n")
	f.close()
	if start > 0 and lines.size() > 0:
		lines.remove_at(0)   # cut mid-line
	return lines.slice(maxi(0, lines.size() - LOG_TAIL_LINES))


func _git_commit() -> String:
	var head := _read_text("res://.git/HEAD").strip_edges()
	if not head.begins_with("ref: "):
		return head.left(10) if head != "" else "?"
	var ref := head.substr(5)
	var hash := _read_text("res://.git/" + ref).strip_edges()
	if hash == "":
		for line in _read_text("res://.git/packed-refs").split("\n"):
			if line.ends_with(" " + ref):
				hash = line.get_slice(" ", 0)
	return "%s %s (uncommitted edits not shown)" % [ref.get_file(), hash.left(10)]


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


# ============================================================
# BUILD
# ============================================================

func _build() -> void:
	if _built:
		return
	_built = true
	var theme := DebugFormTheme.build()

	# REPORT BUG, top right, over whichever debug menu is open.
	_button_layer = CanvasLayer.new()
	_button_layer.layer = BUTTON_LAYER
	_button_layer.visible = false
	add_child(_button_layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = theme
	_button_layer.add_child(holder)
	var report := DebugFormTheme.button("REPORT BUG", _open_box, "", "DangerButton", BUTTON_FONT_SIZE)
	_anchor_top_right(report, MARGIN_RIGHT, BUTTON_SIZE)
	holder.add_child(report)

	# The white box: nothing else on screen but it and its two buttons.
	_box_layer = CanvasLayer.new()
	_box_layer.layer = BOX_LAYER
	_box_layer.visible = false
	add_child(_box_layer)
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.theme = theme
	_box_layer.add_child(blocker)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)

	_text = TextEdit.new()
	_text.custom_minimum_size = BOX_SIZE
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "What went wrong?"
	var white := StyleBoxFlat.new()
	white.bg_color = Color.WHITE
	white.set_corner_radius_all(4)
	white.set_content_margin_all(16)
	for state in ["normal", "focus", "read_only"]:
		_text.add_theme_stylebox_override(state, white)
	# DebugFormTheme gives TextEdit a dark background_color, drawn over the stylebox.
	_text.add_theme_color_override("background_color", Color.WHITE)
	_text.add_theme_color_override("font_color", Color.BLACK)
	_text.add_theme_color_override("font_placeholder_color", Color(0, 0, 0, 0.35))
	_text.add_theme_color_override("caret_color", Color.BLACK)
	_text.add_theme_color_override("selection_color", Color(0.65, 0.78, 1.0))
	_text.add_theme_color_override("font_selected_color", Color.BLACK)
	_text.add_theme_color_override("current_line_color", Color(0, 0, 0, 0))
	# The game's font is capitals only; a plain system font reads better here.
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial", "Sans-Serif"])
	_text.add_theme_font_override("font", font)
	_text.add_theme_font_size_override("font_size", BOX_FONT_SIZE)
	column.add_child(_text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var cancel := DebugFormTheme.button("CANCEL", func(): _close_box(false), "Esc", "", BUTTON_FONT_SIZE)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel.custom_minimum_size = Vector2(160, 48)
	row.add_child(cancel)
	_save_button = DebugFormTheme.button("SAVE", _save_box, "Ctrl + Enter", "PrimaryButton", BUTTON_FONT_SIZE)
	_save_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_save_button.custom_minimum_size = Vector2(160, 48)
	row.add_child(_save_button)

	# Toast: what happened to the report, bottom centre, after the box closes.
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = TOAST_LAYER
	add_child(_toast_layer)
	var toast_holder := Control.new()
	toast_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(toast_holder)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	var plate := DebugFormTheme.card_style(14)
	_toast.add_theme_stylebox_override("normal", plate)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -560
	_toast.offset_right = 560
	_toast.offset_top = -130
	_toast.offset_bottom = -70
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.visible = false
	toast_holder.add_child(_toast)


func _show_toast(text: String, colour: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", colour)
	_toast.modulate.a = 1.0
	_toast.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast.visible = false)


# ============================================================
# HELPERS
# ============================================================

## The newest registered menu still on screen (`need_visible`) or still open at all.
func _menu_entry(need_visible: bool) -> Dictionary:
	for i in range(_menus.size() - 1, -1, -1):
		var entry: Dictionary = _menus[i]
		var menu = entry["menu"]
		if menu == null or not is_instance_valid(menu) or not (menu as Node).is_inside_tree():
			_menus.remove_at(i)
			continue
		if need_visible and not bool((menu as Node).get("visible")):
			continue
		return entry
	return {}


func _anchor_top_right(c: Control, right_gap: float, size: Vector2) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -right_gap - size.x
	c.offset_right = -right_gap
	c.offset_top = MARGIN_TOP
	c.offset_bottom = MARGIN_TOP + size.y


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label
