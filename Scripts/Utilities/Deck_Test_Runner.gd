extends CanvasLayer

## DECK TEST: runs the autotester in a second, headless copy of the game, in the
## background, and shows its progress in the bottom-right corner. Debug tooling,
## preloaded (not a class_name). Lives under MapManager, so it carries on across map
## changes and with the placement tool closed.
##
## The opponent's REAL CPU plays their deck (Prize count and match rules as in the game)
## against the autotester's smart bot. Against the BENCHMARK -- every starter deck in
## turn -- the CPU's win rate becomes their difficulty stars (Opponent_Ratings.gd).
## Against one chosen deck it is just reported, and kept apart from the rating.
##
## The save file is never touched: the autotester plays in test_match_mode.

signal finished(results: Dictionary)

const RUNNER_SCENE := "res://Scenes/Autotest/Autotest_Runner.tscn"
const PROGRESS_PATH := "user://autotest/deck_test_progress.json"
const OpponentRatings := preload("res://Scripts/Global_Scripts/Opponent_Ratings.gd")
const NODE_NAME := "DeckTestRunner"

## TWEAKABLE: how often progress is read, and how long the result stays on screen.
const POLL_SECONDS := 0.5
const RESULT_SECONDS := 12.0
const FONT_SIZE := 20

var _pid: int = -1
var _what: String = ""
var _poll_t: float = 0.0
var _hide_t: float = 0.0
var _label: RichTextLabel = null
var _panel: PanelContainer = null


## The one runner, made on first use.
static func instance() -> Node:
	var existing := MapManager.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var runner = load("res://Scripts/Utilities/Deck_Test_Runner.gd").new()
	runner.name = NODE_NAME
	MapManager.add_child(runner)
	return runner


func _ready() -> void:
	layer = 127
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(560, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_panel.add_child(_label)
	add_child(_panel)
	_panel.visible = false


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## Test one opponent. `vs` = "benchmark" or a deck file path.
func test_opponent(opponent: String, vs: String, matches: int) -> String:
	return _launch(["--opponent=" + opponent, "--matches=%d" % matches],
			vs, "%s vs %s" % [opponent, _vs_label(vs)])


## Rate every opponent in the game against the benchmark, `per` matches each.
func rate_all(per: int) -> String:
	return _launch(["--per=%d" % per], "benchmark", "rating EVERY opponent")


func _launch(extra: Array, vs: String, what: String) -> String:
	if is_running():
		return "a deck test is already running (%s)" % _what
	DirAccess.make_dir_recursive_absolute("user://autotest")
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(PROGRESS_PATH)
	var args: Array = ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
			RUNNER_SCENE, "--", "--real", "--bot=smart", "--rate", "--vs=" + vs,
			"--progress=" + ProjectSettings.globalize_path(PROGRESS_PATH)]
	args.append_array(extra)
	_pid = OS.create_process(OS.get_executable_path(), PackedStringArray(args))
	if _pid <= 0:
		return "could not start the autotester"
	_what = what
	_hide_t = 0.0
	_show("[color=aqua]DECK TEST[/color] %s — starting..." % what)
	print("DeckTestRunner: started pid %d: %s" % [_pid, " ".join(args)])
	return ""


func _vs_label(vs: String) -> String:
	return "the benchmark (every starter deck)" if vs == "benchmark" else vs.get_file().trim_suffix(".json")


func _process(delta: float) -> void:
	if _hide_t > 0.0:
		_hide_t -= delta
		if _hide_t <= 0.0:
			_panel.visible = false
	if _pid <= 0:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL_SECONDS
	var progress = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH)) \
			if FileAccess.file_exists(PROGRESS_PATH) else null
	if progress is Dictionary and bool(progress.get("finished", false)):
		_pid = -1
		_report(progress.get("results", {}))
		return
	if not OS.is_process_running(_pid):
		_pid = -1
		_show("[color=red]DECK TEST stopped without finishing[/color] — see the autotest run folder")
		_hide_t = RESULT_SECONDS
		return
	if progress is Dictionary:
		_show("[color=aqua]DECK TEST[/color] %s — match %d / %d  (%s)" % [_what, int(progress.get("done", 0)),
				int(progress.get("total", 0)), str(progress.get("opponent", ""))])


func _report(results: Dictionary) -> void:
	OpponentRatings.invalidate()
	var lines: Array = ["[color=lime]DECK TEST done[/color] — %s" % _what]
	var names: Array = results.keys()
	names.sort()
	for n in names.slice(0, 8):
		var r: Dictionary = results[n]
		var stars := ""
		if r.has("stars"):
			stars = "  ->  %d star%s" % [int(r["stars"]), "" if int(r["stars"]) == 1 else "s"]
		lines.append("%s: CPU won %d / %d (%d%%)%s" % [n, int(r.get("wins", 0)), int(r.get("games", 0)),
				roundi(float(r.get("win_rate", 0.0)) * 100.0), stars])
	if names.size() > 8:
		lines.append("...and %d more (Opponent_Ratings.json)" % (names.size() - 8))
	_show("\n".join(lines))
	_hide_t = RESULT_SECONDS
	finished.emit(results)


func _show(text: String) -> void:
	_label.text = text
	_panel.visible = true
	_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp.x - _panel.size.x - 24, vp.y - _panel.size.y - 110)


func _exit_tree() -> void:
	if is_running():
		OS.kill(_pid)
