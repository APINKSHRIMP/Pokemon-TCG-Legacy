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
const StarPicker := preload("res://Scripts/Utilities/Star_Picker.gd")
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
	add_theme_stylebox_override("panel", DebugFormTheme.card_style(14))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 7)
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
		_title("Walking Pokémon")
		_label(_route_summary(actor))
		_row([_button("Edit route", tool._route_edit_toggle, "E")])
		return
	if actor.movement_pattern == "random_wander":
		_build_wander(actor)
	elif actor.movement_pattern == "route":
		_title("Movement")
		_label("Walks a route. " + _route_summary(actor))
		_row([_button("Edit route", tool._route_edit_toggle, "E")])
	else:
		_title("Movement")
		var pw: String = tool._pattern_words(str(actor.movement_pattern))
		_label(pw.left(1).to_upper() + pw.substr(1) + ".")
		_label("R changes how they move.  Alt + arrows turns them.", true)
		_row([_button("Draw a route", tool._route_edit_toggle, "E")])
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
			JSON.stringify(rating), tool.deck_test_vs, DeckTestRunner.instance().is_running(), tool.deck_test_games] \
			+ "|%d" % tool.constants_revision


# ── wanderer ──────────────────────────────────────────────────────────────────

func _build_wander(actor: WorldObjectBase) -> void:
	_title("Wandering")
	var boxed: bool = actor.wander_box != Vector2.ZERO
	_row([_button("Area shape: %s" % ("box" if boxed else "circle"), tool.wander_toggle_shape)])
	if boxed:
		_stepper("Area", "%d x %d px" % [roundi(actor.wander_box.x * 2.0), roundi(actor.wander_box.y * 2.0)],
				func(): tool._wander_adjust_radius(-_amount(RADIUS_STEP, RADIUS_FINE)),
				func(): tool._wander_adjust_radius(_amount(RADIUS_STEP, RADIUS_FINE)))
		_row([_button("Stretch the box to where I stand", tool._wander_radius_to_player, "Q")])
	else:
		_stepper("Reach", "%d px" % roundi(actor.wander_radius),
				func(): tool._wander_adjust_radius(-_amount(RADIUS_STEP, RADIUS_FINE)),
				func(): tool._wander_adjust_radius(_amount(RADIUS_STEP, RADIUS_FINE)))
		_row([_button("Reach to where I stand", tool._wander_radius_to_player, "Q")])
	_stepper("Speed", "%d px/s" % roundi(actor.patrol_speed),
			func(): tool._adjust_speed(-_amount(SPEED_STEP, SPEED_FINE)),
			func(): tool._adjust_speed(_amount(SPEED_STEP, SPEED_FINE)))
	_label("The - and = keys change the size too. Hold Shift for small steps.", true)
	_row([_button("Draw a route instead", tool._route_edit_toggle, "E")])


# ── route editor ──────────────────────────────────────────────────────────────

## The panel's name for a route mode (the button cycles LOOP -> PING-PONG -> RANDOM).
static func _mode_name(mode: String) -> String:
	match mode:
		"pingpong":
			return "Walk back the same way"
		"random":
			return "Visit points in random order"
	return "Start again from the top"

func _build_route_editor(actor: Node2D) -> void:
	_title("Route for %s" % tool._name_of(actor))
	_row([_label("When it ends:", false, false),
		_button(_mode_name(actor.route_mode), tool._route_toggle_mode)])
	_stepper("Speed", "%d px/s" % roundi(actor.patrol_speed),
			func(): tool._adjust_speed(-_amount(SPEED_STEP, SPEED_FINE)),
			func(): tool._adjust_speed(_amount(SPEED_STEP, SPEED_FINE)))
	var templates := OptionButton.new()
	templates.focus_mode = Control.FOCUS_NONE
	templates.add_theme_font_size_override("font_size", FONT_SIZE)
	templates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	templates.add_item("Start from a ready-made route...")
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
	list.add_child(_step_button(-1, "Start  (where they stand)"))
	var point := 0
	for i in steps.size():
		var s = steps[i]
		var text := "?"
		if s is Dictionary and s.get("to") is Array:
			point += 1
			var to: Array = s["to"]
			text = "%d.  Walk to (%+d, %+d)%s" % [point, roundi(float(to[0])), roundi(float(to[1])),
					"  at %d px/s" % roundi(float(s["speed"])) if float(s.get("speed", 0.0)) > 0.0 else ""]
		elif s is Dictionary:
			text = "      Wait %s s, %s" % [_secs(float(s.get("wait", 0.0))),
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
		_row([_label("While waiting", false, false), idle])
	elif step is Dictionary:
		var leg := float(step.get("speed", 0.0))
		_stepper("This leg's speed", ("%d px/s" % roundi(leg)) if leg > 0.0 else "same as route",
				func(): tool._route_adjust_leg_speed(-_amount(SPEED_STEP, SPEED_FINE)),
				func(): tool._route_adjust_leg_speed(_amount(SPEED_STEP, SPEED_FINE)))
	_row([_button("+ Point where I stand", tool._route_add_point, "Q"), _button("+ Pause", tool._route_add_pause)])
	_row([_button("Move point here", tool._route_move_point, "X"), _button("Go to point", tool._route_goto_point, "T")])
	_row([_button("Move up", func(): tool._route_move_step(-1)), _button("Move down", func(): tool._route_move_step(1)),
			_button("Delete step", tool._route_delete_step, "Del", "DangerButton")])
	_row([_button("Done", tool._route_edit_toggle, "E", "PrimaryButton")])
	_label("Quick way: hold Z and walk the path. Standing still adds a pause.", true)
	_label("Tab picks a step.  Alt + arrows: which way a pause faces.  Ctrl + arrows: nudge the point.  G: carry the whole route.", true)


## "3 points, start again from the top, 40 px/s."
func _route_summary(actor: Node) -> String:
	var n: int = actor._route_nodes.size()
	return "%d point%s, %s, %d px/s." % [n, "" if n == 1 else "s", _mode_name(actor.route_mode).to_lower(),
			roundi(actor.patrol_speed)]


func _step_button(index: int, text: String) -> Button:
	var b := _button(text, func(): tool._route_select(index))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if index == tool._route_sel:
		b.theme_type_variation = "PrimaryButton"
	return b


# ── the character itself ──────────────────────────────────────────────────────

func _build_character(actor: WorldObjectBase) -> void:
	_title("Character")
	_row([_button("Copy", tool._clone_selected, "C"), _button("Edit details", func(): tool._open_editor(CharacterEditor.Mode.EDIT), "M"),
		_button("Delete", tool._delete_key, "Del, twice", "DangerButton")])
	var maps := OptionButton.new()
	maps.focus_mode = Control.FOCUS_NONE
	maps.add_theme_font_size_override("font_size", FONT_SIZE)
	maps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_item("Move them to another map...")
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
	var consts: Dictionary = OpponentRatings._constants_for(name)
	_title("Difficulty")
	var stars := OpponentRatings.stars_for(name, consts)
	var rating = OpponentRatings.load_all().get(name)
	var manual := int(consts.get("stars", 0))

	# Click a star to set it by hand. Saved straight away.
	var picker = StarPicker.new()
	picker.value = stars
	picker.automatic = manual <= 0
	picker.picked.connect(func(n: int): tool.set_opponent_constant(name, "stars", n))
	_box.add_child(picker)

	var origin := "Not rated yet. Click a star, or run a deck test below."
	if manual > 0:
		origin = "%s, set by you." % _stars_text(stars)
	elif stars > 0 and rating is Dictionary and str(rating.get("vs", "")) == "estimate":
		origin = "%s, a rough guess. Click a star to set it, or run a deck test." % _stars_text(stars)
	elif stars > 0:
		origin = "%s, from the deck test." % _stars_text(stars)
	_label(origin, true)
	if manual > 0:
		_row([_button("Go back to the automatic rating", func(): tool.set_opponent_constant(name, "stars", null))])

	if rating is Dictionary and rating.has("win_rate"):
		_label("Last deck test: they won %d of %d games (%d%%) on %s." % [int(rating.get("wins", 0)),
				int(rating.get("games", 0)), roundi(float(rating["win_rate"]) * 100.0), str(rating.get("tested", ""))], true)
	if rating is Dictionary and rating.get("other_tests") is Dictionary:
		for vs in rating["other_tests"]:
			var r: Dictionary = rating["other_tests"][vs]
			_label("vs %s: they won %d of %d (%d%%)." % [str(vs).get_file().trim_suffix(".json"),
					int(r.get("wins", 0)), int(r.get("games", 0)), roundi(float(r.get("win_rate", 0.0)) * 100.0)], true)

	# NO RETREAT: this opponent's CPU never chooses to retreat (it can still be forced to
	# switch, and can still play Switch). Uses the existing "cpu_retreat_rate" (0 = never).
	_title("Retreating")
	var rate := float(consts.get("cpu_retreat_rate", 1.0))
	var never: bool = consts.has("cpu_retreat_rate") and rate <= 0.0
	var how := "Retreats normally."
	if never:
		how = "Never retreats. Quicker, easier matches."
	elif rate < 1.0:
		how = "Retreats only %d%% of the times it wants to." % roundi(rate * 100.0)
	_label(how, true)
	var retreat_button := _button("Never retreats: ON" if never else "Never retreats: OFF", func():
		tool.set_opponent_constant(name, "cpu_retreat_rate", null if never else 0))
	retreat_button.theme_type_variation = "ToggleOnButton" if never else ""
	retreat_button.tooltip_text = "ON: their CPU never chooses to retreat, so early matches end quicker.\nThey can still play Switch, and still swap in after a knock out."
	_row([retreat_button])

	_title("Deck test")
	var vs_pick := OptionButton.new()
	vs_pick.focus_mode = Control.FOCUS_NONE
	vs_pick.add_theme_font_size_override("font_size", FONT_SIZE)
	vs_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choices: Array = [["Against every starter deck (sets the stars)", "benchmark"]]
	for f in _deck_files(GameState.PLAYER_DECKS_FOLDER):
		choices.append(["Against your deck: " + f.get_file().trim_suffix(".json"), f])
	for f in _deck_files(OPPONENT_DECK_DIR):
		choices.append(["Against opponent deck: " + f.get_file().trim_suffix(".json"), f])
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
		_button("%d games" % tool.deck_test_games, func():
			var at := DECK_TEST_GAMES.find(tool.deck_test_games)
			tool.deck_test_games = DECK_TEST_GAMES[(at + 1) % DECK_TEST_GAMES.size()]
			tool._update_hud()),
		_button("Running..." if running else "Run test", tool.run_deck_test, "", "" if running else "PrimaryButton"),
	])
	_label("Plays their real CPU and deck against the test bot, in the background. Click the games button to change how many.", true)


static func _stars_text(n: int) -> String:
	return "1 star" if n == 1 else "%d stars" % n


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
	if _box.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		_box.add_child(gap)
	_box.add_child(DebugFormTheme.heading(text))


func _label(text: String, small: bool = false, add: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FONT_SIZE - 2 if small else FONT_SIZE)
	if small:
		l.theme_type_variation = "Hint"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if add:
		_box.add_child(l)
	return l


func _button(text: String, action: Callable, key: String = "", variation: String = "") -> Button:
	return DebugFormTheme.button(text, action, key, variation, FONT_SIZE)


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
