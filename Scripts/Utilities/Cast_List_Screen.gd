extends Control

## L in the F placement tool: everyone on this map, against every day and time they
## are on it, and a CASH tab for the whole game. Debug tooling, preloaded (not a
## class_name).
##
## CAST: one row per character -- kind, deck, cash, stars, beaten -- then a cell per day
## and time slot, lit where they appear. Click a lit cell to preview that day / time in
## the tool with that character selected.
## CASH: for every day, the opponents the player can battle for the FIRST time that day
## (across every map) and what their first wins pay -- cash_reward x3, the first-win
## multiplier -- with a running total.
##
## Presence ignores story gates (`requires`): it shows where a character CAN be, so a
## rule gated on progress may light a cell the player only sees later.

signal closed
signal slot_chosen(day: int, time_of_day: String, character: String)

const OpponentRatings := preload("res://Scripts/Global_Scripts/Opponent_Ratings.gd")
const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"

# TWEAKABLE: layout (screen px) and the first-win multiplier the CASH tab uses.
const FIRST_WIN_MULTIPLIER := 3
const MARGIN := 40.0
const ROW_H := 26.0
const HEADER_H := 46.0
const CELL_W := 14.0
const DAY_GAP := 6.0
const FONT_SIZE := 17
const SMALL_FONT := 14
const COLUMNS := [["Name", 300.0], ["Kind", 56.0], ["Deck", 230.0], ["$", 64.0], ["Stars", 64.0], ["Beaten", 70.0]]
const LIT := Color(0.35, 0.85, 1.0)
const LIT_OPP := Color(1.0, 0.6, 0.3)
const UNLIT := Color(1, 1, 1, 0.07)
const TEXT := Color(0.92, 0.92, 0.92)
const DIM := Color(0.6, 0.6, 0.6)

var map_name: String = ""
var _times: Array = []
var _days: int = 8
var _rows: Array = []          # [{name, kind, deck, cash, stars, beaten, slots: {"d|t": true}}]
var _cash_days: Array = []     # [{day, opponents: [[name, cash, map]], total, running}]
var _tab := "cast"
var _grid: Control = null
var _scroll: ScrollContainer = null
var _tab_buttons: Dictionary = {}


func setup(map_data: String) -> void:
	map_name = map_data
	_times = []
	for t in GameState.TIMES_OF_DAY:
		_times.append(str(t))
	_build_cast()
	_build_cash()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := HBoxContainer.new()
	top.theme = DebugFormTheme.build()
	top.position = Vector2(MARGIN, 16)
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	var title := Label.new()
	title.text = "CAST LIST — %s" % map_name
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top.add_child(title)
	for tab in [["cast", "THIS MAP"], ["cash", "CASH (whole game, first wins x%d)" % FIRST_WIN_MULTIPLIER]]:
		var b := Button.new()
		b.text = tab[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_show_tab.bind(tab[0]))
		top.add_child(b)
		_tab_buttons[tab[0]] = b
	var close := Button.new()
	close.text = "CLOSE (Esc / L)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(MARGIN, 76)
	_scroll.size = Vector2(UIKit.screen_w() - MARGIN * 2.0, UIKit.screen_h() - 76 - MARGIN)
	_scroll.focus_mode = Control.FOCUS_NONE
	add_child(_scroll)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	_scroll.add_child(_grid)
	_show_tab("cast")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() \
			and event.keycode in [KEY_ESCAPE, KEY_L]:
		get_viewport().set_input_as_handled()
		closed.emit()


func _show_tab(tab: String) -> void:
	_tab = tab
	for k in _tab_buttons:
		_tab_buttons[k].modulate = Color.WHITE if k == tab else Color(1, 1, 1, 0.55)
	if tab == "cast":
		_grid.custom_minimum_size = Vector2(_grid_width(), HEADER_H + ROW_H * _rows.size() + 20)
	else:
		var lines := 0
		for d in _cash_days:
			lines += 1 + int(ceil(d["opponents"].size() / 3.0))
		_grid.custom_minimum_size = Vector2(1500, HEADER_H + ROW_H * (lines + 2))
	_grid.queue_redraw()


# ── data ──────────────────────────────────────────────────────────────────────

static func days_for(doc: Dictionary) -> int:
	var cal: Dictionary = doc.get("calendar", {})
	var days := int(cal.get("authored_through", 8))
	var loop: Dictionary = cal.get("loop", {})
	if not loop.is_empty():
		days = maxi(days, int(loop.get("from", 1)) + int(loop.get("period", 1)) - 1)
	return maxi(days, 1)


func _build_cast() -> void:
	var doc := CharacterSchedule.load_map(map_name)
	_days = days_for(doc)
	var consts = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS_PATH))
	if not (consts is Dictionary):
		consts = {}
	var by_name: Dictionary = {}
	var order: Array = []
	for section in ["opponents", "npcs"]:
		for name in doc.get(section, {}):
			order.append(name)
			by_name[name] = {"name": name, "kind": "opp" if section == "opponents" else "npc",
					"deck": "", "cash": "", "stars": 0, "beaten": "", "slots": {}}
	for d in range(1, _days + 1):
		for t in _times:
			var cast := CharacterSchedule.cast_for(map_name, d, t)
			for kind in ["opponents", "npcs"]:
				for entry in cast.get(kind, []):
					var name := str(entry.get("name", ""))
					if not by_name.has(name):
						continue
					var row: Dictionary = by_name[name]
					row["slots"]["%d|%s" % [d, t]] = kind
					if kind == "opponents":
						var merged: Dictionary = entry.duplicate()
						for k in consts.get("opponents", {}).get(name, {}):
							if not merged.has(k):
								merged[k] = consts["opponents"][name][k]
						row["deck"] = str(merged.get("deck", row["deck"]))
						row["cash"] = str(merged.get("cash_reward", row["cash"]))
	for name in order:
		var row: Dictionary = by_name[name]
		if row["kind"] == "opp" or row["deck"] != "":
			row["stars"] = OpponentRatings.stars_for(name, consts.get("opponents", {}).get(name, {}))
			row["beaten"] = "yes" if GameState.has_beaten_opponent(name) else "-"
		_rows.append(row)


func _build_cash() -> void:
	var consts = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS_PATH))
	if not (consts is Dictionary):
		consts = {}
	var opp_consts: Dictionary = consts.get("opponents", {})
	var first: Dictionary = {}      # name -> [day, cash, map]
	var max_days := 1
	var dir := DirAccess.open(CharacterSchedule.DIR)
	var maps: Array = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				maps.append(f.trim_suffix(".json"))
	for m in maps:
		max_days = maxi(max_days, days_for(CharacterSchedule.load_map(m)))
	for d in range(1, max_days + 1):
		for m in maps:
			for t in _times:
				for entry in CharacterSchedule.cast_for(m, d, t).get("opponents", []):
					var name := str(entry.get("name", ""))
					if name == "" or first.has(name):
						continue
					var cash := int(entry.get("cash_reward", opp_consts.get(name, {}).get("cash_reward", 0)))
					first[name] = [d, cash * FIRST_WIN_MULTIPLIER, m]
	var running := 0
	for d in range(1, max_days + 1):
		var list: Array = []
		var total := 0
		for name in first:
			if int(first[name][0]) == d:
				list.append([name, int(first[name][1]), str(first[name][2])])
				total += int(first[name][1])
		list.sort_custom(func(a, b): return a[1] > b[1])
		running += total
		_cash_days.append({"day": d, "opponents": list, "total": total, "running": running})


# ── drawing ───────────────────────────────────────────────────────────────────

func _grid_left() -> float:
	var x := 0.0
	for c in COLUMNS:
		x += float(c[1])
	return x + 10.0


func _grid_width() -> float:
	return _grid_left() + _days * (_times.size() * CELL_W + DAY_GAP) + 20.0


func _draw_grid() -> void:
	if _tab == "cash":
		_draw_cash()
		return
	var font := ThemeDB.fallback_font
	var x := 0.0
	for c in COLUMNS:
		_grid.draw_string(font, Vector2(x, 22), str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM)
		x += float(c[1])
	var gx := _grid_left()
	for d in range(1, _days + 1):
		var dx := gx + (d - 1) * (_times.size() * CELL_W + DAY_GAP)
		_grid.draw_string(font, Vector2(dx, 18), "D%d" % d, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT, DIM)
		for ti in _times.size():
			_grid.draw_string(font, Vector2(dx + ti * CELL_W + 2, 38), str(_times[ti]).left(1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT - 2, DIM)
	for r in _rows.size():
		var row: Dictionary = _rows[r]
		var y := HEADER_H + r * ROW_H
		if r % 2 == 0:
			_grid.draw_rect(Rect2(0, y, _grid_width(), ROW_H), Color(1, 1, 1, 0.03))
		var cells := [row["name"], row["kind"], row["deck"], ("$" + str(row["cash"])) if str(row["cash"]) != "" else "",
				"*".repeat(int(row["stars"])) if int(row["stars"]) > 0 else "", row["beaten"]]
		x = 0.0
		for c in COLUMNS.size():
			_grid.draw_string(font, Vector2(x, y + ROW_H - 7), str(cells[c]), HORIZONTAL_ALIGNMENT_LEFT,
					float(COLUMNS[c][1]) - 8.0, FONT_SIZE, TEXT)
			x += float(COLUMNS[c][1])
		for d in range(1, _days + 1):
			var dx := gx + (d - 1) * (_times.size() * CELL_W + DAY_GAP)
			for ti in _times.size():
				var kind = row["slots"].get("%d|%s" % [d, _times[ti]], "")
				var colour := UNLIT
				if kind == "opponents":
					colour = LIT_OPP
				elif kind == "npcs":
					colour = LIT
				_grid.draw_rect(Rect2(dx + ti * CELL_W, y + 4, CELL_W - 2, ROW_H - 8), colour)


func _draw_cash() -> void:
	var font := ThemeDB.fallback_font
	_grid.draw_string(font, Vector2(0, 22), "Day    New opponents    First-win cash (x%d)    Running total" % FIRST_WIN_MULTIPLIER,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM)
	var y := HEADER_H
	for d in _cash_days:
		_grid.draw_string(font, Vector2(0, y + ROW_H - 7), "Day %d" % d["day"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LIT)
		_grid.draw_string(font, Vector2(90, y + ROW_H - 7), str(d["opponents"].size()), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		_grid.draw_string(font, Vector2(260, y + ROW_H - 7), "$%d" % d["total"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LIT_OPP)
		_grid.draw_string(font, Vector2(520, y + ROW_H - 7), "$%d" % d["running"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		y += ROW_H
		var list: Array = d["opponents"]
		for i in range(0, list.size(), 3):
			var x := 90.0
			for j in range(i, mini(i + 3, list.size())):
				var o: Array = list[j]
				_grid.draw_string(font, Vector2(x, y + ROW_H - 8), "%s  $%d  (%s)" % [o[0], o[1], o[2]],
						HORIZONTAL_ALIGNMENT_LEFT, 460, SMALL_FONT, DIM)
				x += 470.0
			y += ROW_H


func _on_grid_input(event: InputEvent) -> void:
	if _tab != "cast" or not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = event.position
	var r := int(floor((p.y - HEADER_H) / ROW_H))
	if r < 0 or r >= _rows.size():
		return
	var gx := _grid_left()
	var span := _times.size() * CELL_W + DAY_GAP
	if p.x < gx:
		return
	var d := int(floor((p.x - gx) / span)) + 1
	var ti := int(floor(fmod(p.x - gx, span) / CELL_W))
	if d < 1 or d > _days or ti < 0 or ti >= _times.size():
		return
	var row: Dictionary = _rows[r]
	if not row["slots"].has("%d|%s" % [d, _times[ti]]):
		return
	_grid.accept_event()
	slot_chosen.emit(d, str(_times[ti]), str(row["name"]))
