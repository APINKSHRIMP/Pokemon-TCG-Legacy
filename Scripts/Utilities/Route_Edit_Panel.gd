extends PanelContainer

## Right-hand panel of the F placement tool for movement: a route's steps (pauses, idle
## patterns, leg speeds, loop / ping-pong / random) and a wanderer's radius and speed. Every
## button calls straight back into PlacementTool, which applies the change to the live
## character so it can be seen at once, and records it for the save.
##
## Every control is FOCUS_NONE: a focused control eats the arrow keys the player walks
## with, and Enter would press it again instead of saving. Nothing here takes typing.

## TWEAKABLE: panel width, step list height, and how much each -/+ press changes
## (Shift held = the fine step).
const WIDTH := 460
const LIST_HEIGHT := 360
const FONT_SIZE := 17
const SECONDS_STEP := 0.5
const SECONDS_FINE := 0.1
const SPEED_STEP := 10.0
const SPEED_FINE := 1.0
const RADIUS_STEP := 10.0
const RADIUS_FINE := 1.0

const IDLE_LABELS := {
	"": "keep facing",
	"idle_down": "face down", "idle_up": "face up",
	"idle_left": "face left", "idle_right": "face right",
	"idle_down_random": "down + glances", "idle_up_random": "up + glances",
	"idle_left_random": "left + glances", "idle_right_random": "right + glances",
	"idle_random": "look around", "idle_cycle": "walk on the spot",
}

const OpponentRatings := preload("res://Scripts/Global_Scripts/Opponent_Ratings.gd")
const DeckTestRunner := preload("res://Scripts/Utilities/Deck_Test_Runner.gd")
const CastDataOps := preload("res://Scripts/Utilities/Cast_Data_Ops.gd")
const OPPONENT_DECK_DIR := "res://NPC_and_Opponent_Data/Opponent_Deck_Data/"
## TWEAKABLE: the games-per-test choices the DECK TEST's GAMES button cycles through.
const DECK_TEST_GAMES := [10, 20, 30, 50, 100]

var tool: Node = null
var _signature: String = ""
var _box: VBoxContainer = null


func _ready() -> void:
	theme = DebugFormTheme.build()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	# Pinned to the top-right corner at any resolution, growing leftwards and down.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -WIDTH - 24
	offset_right = -24
	offset_top = 24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.78)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	visible = false


## Rebuild only when something it shows has changed: the tool calls this every frame
## while an actor is carried, and a rebuild mid-click would free the button pressed.
func refresh() -> void:
	var actor: Node = tool._route_actor if tool._route_valid() else tool._selected()
	var sig := _signature_for(actor)
	if sig == _signature:
		return
	_signature = sig
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var walker: bool = actor is PokemonSpawnMarker and actor.is_walker()
	if not (actor is WorldObjectBase) and not walker:
		visible = false
		return
	visible = true
	if tool._route_valid():
		_build_route_editor(actor)
		return
	if walker:
		_title("WALKER — %s" % str(actor.point.get("id", "?")))
		_label("%d point(s), %s, speed %d" % [actor._route_nodes.size(),
				_mode_name(actor.route_mode).to_lower(), roundi(actor.patrol_speed)])
		_row([_button("DRAW / EDIT ROUTE (E)", tool._route_edit_toggle)])
		return
	if actor.movement_pattern == "random_wander":
		_build_wander(actor)
	elif actor.movement_pattern == "route":
		_title("ROUTE — %s" % tool._name_of(actor))
		_label("%d point(s), %s, speed %d" % [actor._route_nodes.size(),
				_mode_name(actor.route_mode).to_lower(), roundi(actor.patrol_speed)])
		_row([_button("EDIT ROUTE (E)", tool._route_edit_toggle)])
	else:
		_title("MOVEMENT — %s" % tool._name_of(actor))
		_label("pattern: %s   (R cycles, Alt+arrows face)" % actor.movement_pattern)
		_row([_button("DRAW A ROUTE (E)", tool._route_edit_toggle)])
	_build_character(actor)
	if "opponent_name" in actor and str(actor.opponent_name) != "":
		_build_deck_test(actor)


func _signature_for(actor: Node) -> String:
	if actor is PokemonSpawnMarker and actor.is_walker():
		return "%d|walker|%s|%s|%s|%s|%d" % [actor.get_instance_id(), JSON.stringify(actor.route_steps),
				actor.route_mode, actor.patrol_speed, tool._route_valid(), tool._route_sel]
	if not (actor is WorldObjectBase):
		return "none"
	var rating = OpponentRatings.load_all().get(str(actor.opponent_name)) if "opponent_name" in actor else null
	return "%d|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%d" % [actor.get_instance_id(), actor.movement_pattern,
			JSON.stringify(actor.route_steps), actor.route_mode, actor.patrol_speed,
			actor.wander_radius, actor.wander_box, tool._route_valid(), tool._route_sel,
			JSON.stringify(rating), tool.deck_test_vs, DeckTestRunner.instance().is_running(), tool.deck_test_games]


# ── wanderer ──────────────────────────────────────────────────────────────────

func _build_wander(actor: WorldObjectBase) -> void:
	_title("WANDER — %s" % tool._name_of(actor))
	var boxed: bool = actor.wander_box != Vector2.ZERO
	_row([_button("SHAPE: %s  (switch)" % ("BOX" if boxed else "CIRCLE"), tool.wander_toggle_shape)])
	if boxed:
		_stepper("Box", "%d x %d px" % [roundi(actor.wander_box.x * 2.0), roundi(actor.wander_box.y * 2.0)],
				func(): tool._wander_adjust_radius(-_amount(RADIUS_STEP, RADIUS_FINE)),
				func(): tool._wander_adjust_radius(_amount(RADIUS_STEP, RADIUS_FINE)))
		_row([_button("CORNER = TO ME (Q)", tool._wander_radius_to_player)])
	else:
		_stepper("Radius", "%d px" % roundi(actor.wander_radius),
				func(): tool._wander_adjust_radius(-_amount(RADIUS_STEP, RADIUS_FINE)),
				func(): tool._wander_adjust_radius(_amount(RADIUS_STEP, RADIUS_FINE)))
		_row([_button("RADIUS = TO ME (Q)", tool._wander_radius_to_player)])
	_stepper("Speed", "%d px/s" % roundi(actor.patrol_speed),
			func(): tool._adjust_speed(-_amount(SPEED_STEP, SPEED_FINE)),
			func(): tool._adjust_speed(_amount(SPEED_STEP, SPEED_FINE)))
	_label("- / = keys change the size too. Shift = fine steps.", true)
	_row([_button("DRAW A ROUTE INSTEAD (E)", tool._route_edit_toggle)])


# ── route editor ──────────────────────────────────────────────────────────────

## The panel's name for a route mode (the button cycles LOOP -> PING-PONG -> RANDOM).
static func _mode_name(mode: String) -> String:
	match mode:
		"pingpong":
			return "PING-PONG"
		"random":
			return "RANDOM"
	return "LOOP"

func _build_route_editor(actor: Node2D) -> void:
	_title("ROUTE — %s" % tool._name_of(actor))
	_row([
		_button(_mode_name(actor.route_mode), tool._route_toggle_mode),
	])
	_stepper("Speed", "%d px/s" % roundi(actor.patrol_speed),
			func(): tool._adjust_speed(-_amount(SPEED_STEP, SPEED_FINE)),
			func(): tool._adjust_speed(_amount(SPEED_STEP, SPEED_FINE)))
	var templates := OptionButton.new()
	templates.focus_mode = Control.FOCUS_NONE
	templates.add_theme_font_size_override("font_size", FONT_SIZE)
	templates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	templates.add_item("Template... (replaces the route)")
	for t in tool.ROUTE_TEMPLATES:
		templates.add_item(str(t))
	templates.item_selected.connect(func(index: int):
		if index > 0:
			tool.route_apply_template(templates.get_item_text(index)))
	_row([templates])

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_box.add_child(scroll)

	var steps: Array = actor.route_steps
	list.add_child(_step_button(-1, "S   start (where they stand)"))
	var point := 0
	for i in steps.size():
		var s = steps[i]
		var text := "?"
		if s is Dictionary and s.get("to") is Array:
			point += 1
			var to: Array = s["to"]
			text = "%d   walk to (%+d, %+d)%s" % [point, roundi(float(to[0])), roundi(float(to[1])),
					"   @%d" % roundi(float(s["speed"])) if float(s.get("speed", 0.0)) > 0.0 else ""]
		elif s is Dictionary:
			text = "      pause %ss   %s" % [_secs(float(s.get("wait", 0.0))),
					IDLE_LABELS.get(str(s.get("idle", "")), str(s.get("idle", "")))]
		list.add_child(_step_button(i, text))

	# The selected step's own settings.
	var sel: int = tool._route_sel
	var step = steps[sel] if sel >= 0 and sel < steps.size() else null
	if step is Dictionary and step.has("wait"):
		_stepper("Pause", "%ss" % _secs(float(step.get("wait", 0.0))),
				func(): tool._route_adjust_wait(-_amount(SECONDS_STEP, SECONDS_FINE)),
				func(): tool._route_adjust_wait(_amount(SECONDS_STEP, SECONDS_FINE)))
		var idle := OptionButton.new()
		idle.focus_mode = Control.FOCUS_NONE
		idle.add_theme_font_size_override("font_size", FONT_SIZE)
		var current := str(step.get("idle", ""))
		var keys: Array = WorldObjectBase.ROUTE_IDLES
		for k in keys.size():
			idle.add_item(IDLE_LABELS.get(keys[k], keys[k]), k)
			if keys[k] == current:
				idle.select(k)
		idle.item_selected.connect(func(index: int): tool._route_set_idle(str(keys[index])))
		_row([_label("Idle", false, false), idle])
	elif step is Dictionary:
		var leg := float(step.get("speed", 0.0))
		_stepper("Leg speed", ("%d px/s" % roundi(leg)) if leg > 0.0 else "route speed",
				func(): tool._route_adjust_leg_speed(-_amount(SPEED_STEP, SPEED_FINE)),
				func(): tool._route_adjust_leg_speed(_amount(SPEED_STEP, SPEED_FINE)))
	_row([_button("+ POINT HERE (Q)", tool._route_add_point), _button("MOVE HERE (X)", tool._route_move_point)])
	_row([_button("+ PAUSE", tool._route_add_pause), _button("GO TO (T)", tool._route_goto_point)])
	_row([_button("UP", func(): tool._route_move_step(-1)), _button("DOWN", func(): tool._route_move_step(1)),
			_button("DELETE (Del)", tool._route_delete_step)])
	_row([_button("DONE (E)", tool._route_edit_toggle)])
	_label("Hold Z and walk to record a path (stand still = pause). Tab / Shift+Tab pick a step. Alt+arrows face a pause. Ctrl+arrows nudge the picked point. G carries the whole route.", true)


func _step_button(index: int, text: String) -> Button:
	var b := _button(text, func(): tool._route_select(index))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if index == tool._route_sel:
		b.add_theme_color_override("font_color", Color(0.75, 0.45, 0.0))
		b.text = "> " + text
	return b


# ── the character itself ──────────────────────────────────────────────────────

func _build_character(actor: WorldObjectBase) -> void:
	_title("CHARACTER")
	_row([_button("CLONE (C)", tool._clone_selected), _button("DELETE (Del x2)", tool._delete_key)])
	var maps := OptionButton.new()
	maps.focus_mode = Control.FOCUS_NONE
	maps.add_theme_font_size_override("font_size", FONT_SIZE)
	maps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_item("Move to map...")
	for m in CastDataOps.map_names():
		if str(m) != str(tool._map_data):
			maps.add_item(str(m))
	maps.item_selected.connect(func(index: int):
		if index > 0:
			tool.move_selected_to_map(maps.get_item_text(index)))
	_row([maps])


# ── deck test (opponents) ─────────────────────────────────────────────────────

func _build_deck_test(actor: Node) -> void:
	var name := str(actor.opponent_name)
	_title("DIFFICULTY")
	var stars := OpponentRatings.stars_for(name)
	var rating = OpponentRatings.load_all().get(name)
	var manual := int(OpponentRatings._constants_for(name).get("stars", 0))
	var text := "no rating yet"
	if stars > 0:
		var origin := "set by hand (M)"
		if manual <= 0:
			origin = "estimated (run the benchmark to test)" if rating is Dictionary and str(rating.get("vs", "")) == "estimate" else "from the deck test"
		text = "%s  (%d)  %s" % ["*".repeat(stars), stars, origin]
	_label(text)
	if rating is Dictionary and rating.has("win_rate"):
		_label("benchmark: CPU won %d / %d (%d%%), %s" % [int(rating.get("wins", 0)), int(rating.get("games", 0)),
				roundi(float(rating["win_rate"]) * 100.0), str(rating.get("tested", ""))], true)
	if rating is Dictionary and rating.get("other_tests") is Dictionary:
		for vs in rating["other_tests"]:
			var r: Dictionary = rating["other_tests"][vs]
			_label("vs %s: CPU won %d / %d (%d%%)" % [vs, int(r.get("wins", 0)), int(r.get("games", 0)),
					roundi(float(r.get("win_rate", 0.0)) * 100.0)], true)
	var vs_pick := OptionButton.new()
	vs_pick.focus_mode = Control.FOCUS_NONE
	vs_pick.add_theme_font_size_override("font_size", FONT_SIZE)
	vs_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choices: Array = [["Benchmark: every starter deck (sets stars)", "benchmark"]]
	for f in _deck_files(GameState.PLAYER_DECKS_FOLDER):
		choices.append(["Your deck: " + f.get_file().trim_suffix(".json"), f])
	for f in _deck_files(OPPONENT_DECK_DIR):
		choices.append(["Opponent deck: " + f.get_file().trim_suffix(".json"), f])
	for i in choices.size():
		vs_pick.add_item(str(choices[i][0]), i)
		if str(choices[i][1]) == tool.deck_test_vs:
			vs_pick.select(i)
	vs_pick.item_selected.connect(func(index: int):
		tool.deck_test_vs = str(choices[index][1])
		tool._update_hud())
	_row([vs_pick])
	var running: bool = DeckTestRunner.instance().is_running()
	_row([
		_button("GAMES: %d" % tool.deck_test_games, func():
			var at := DECK_TEST_GAMES.find(tool.deck_test_games)
			tool.deck_test_games = DECK_TEST_GAMES[(at + 1) % DECK_TEST_GAMES.size()]
			tool._update_hud()),
		_button("RUNNING..." if running else "RUN DECK TEST", tool.run_deck_test),
	])
	_label("Their real CPU + deck vs the smart bot, in the background.", true)


func _deck_files(folder: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(folder + f)
	out.sort()
	return out


# ── widgets ───────────────────────────────────────────────────────────────────

func _title(text: String) -> void:
	var l := _label(text)
	l.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))


func _label(text: String, small: bool = false, add: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FONT_SIZE - 3 if small else FONT_SIZE)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8) if small else Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if add:
		_box.add_child(l)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _row(controls: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for c in controls:
		row.add_child(c)
	_box.add_child(row)


func _stepper(caption: String, value: String, minus: Callable, plus: Callable) -> void:
	var name_label := _label(caption, false, false)
	var value_label := _label(value, false, false)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var m := _button("-", minus)
	var p := _button("+", plus)
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.custom_minimum_size = Vector2(44, 0)
	p.custom_minimum_size = Vector2(44, 0)
	_row([name_label, m, value_label, p])


func _amount(normal: float, fine: float) -> float:
	return fine if Input.is_key_pressed(KEY_SHIFT) else normal


func _secs(s: float) -> String:
	return str(snappedf(s, 0.1)).trim_suffix(".0")
