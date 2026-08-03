extends Node

# ============================================================
# GAME STATE - Autoload Singleton
# ============================================================

var current_opponent_name: String = ""

# TEMP TESTING: synthetic opponent metadata used by the T-key TEST match so no
# NPC JSON needs to exist. Sprite is left blank (intro skips a missing sprite).
func build_test_opponent_data() -> Dictionary:
	return {
		"name": "TEST OPPONENT",
		"deck": "TEST",
		"sprite": "",
		"music": "fast_battle (TCG GB Ronalds Theme)",
		"prize_cards": 6,
		"coin_reward": "",
		"sleeve": "",
		"match_effects": [],
		"restrictions": {},
	}

var current_opponent_json_path: String = ""
var returning_from_battle: bool = false
var battle_result: String = ""  # "win" or "loss"
var player_position: Vector2 = Vector2.ZERO
var current_opponent_deck: String = ""

# TEMP TESTING: when true, both the player AND the opponent draw from the
# "TEST" deck in user://Player_Decks/, and opponent metadata is synthesized
# (no NPC JSON is read). Set by the overworld T-key debug launcher; cleared
# whenever a normal battle starts.
var test_match_mode: bool = false

var return_to_scene: String = ""
var interior_entry_position: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var use_spawn_position: bool = false
var entering_from: String = ""

var return_map_scene_path: String = ""
var last_battled_opponent_entry: Dictionary = {}
var last_interior_scene: String = ""
var current_shop_id: String = "card_mart"

# ISSUE #34: global game-speed multipliers, driven by the Options submenu. 1.0 plays an animation at
# exactly its authored duration (the "slow" preset); higher = faster. Read these wherever an
# animation/movement duration is computed so the whole game honours the player's preference. Each
# has its own Options section and its own saved key:
#   card_match_animation_speed  — in-match animations: card placement, energy, retreat, damage
#                                 labels, coin flips, KOs, CPU thinking pauses.  ("Match")
#   item_animation_speed        — reward reveals: gift coin/card flips and costume fade-ins.
#                                 Deliberately has no "skip" — these ARE the payoff, and every one
#                                 of them is already click-skippable.
#   pack_animation_speed        — the pack opening sequence only. Has its own "skip", which jumps
#                                 from the buy press straight to the finished row of cards.
#   overworld_walking_speed     — the player's default overworld walk/run speed multiplier.
#
# The match intro/outro has NO multiplier — see INTRO_OUTRO_OPTIONS below.
var card_match_animation_speed: float = 1.25
var item_animation_speed: float = 1.25
var pack_animation_speed: float = 1.25
var overworld_walking_speed: float = 1.1

# TWEAKABLE — raising a number speeds that preset up. These three dictionaries are deliberately
# separate: "normal" does NOT have to mean the same multiplier for a match, an item reveal and a
# pack opening, because those sequences are authored at different tempos. Tune each on its own.
# "skip" is a deliberately huge multiplier so scaled_duration() collapses every animation to ~1
# frame rather than skipping the await chains outright (which would desync the match engine); only
# the two presets that offer it can ever return true from is_transition_skipped().
const ANIMATION_SPEED_PRESETS := {
	"very_slow": 0.7,
	"slow": 1.0,
	"normal": 1.25,
	"fast": 2.2,
	"skip": 100.0,
}
const ITEM_SPEED_PRESETS := {
	"very_slow": 0.7,
	"slow": 1.0,
	"normal": 1.25,
	"fast": 2.2,
}
# Pack opening runs slower than the match/item presets on purpose — the tear is a set-piece, not a
# beat to get through. "normal" is a straight 1.0 passthrough, so the base durations written into
# Pack_Opening_Manager.gd are exactly what plays at the default setting.
const PACK_SPEED_PRESETS := {
	"very_slow": 0.5,
	"slow": 0.75,
	"normal": 1.0,
	"fast": 2.0,
	"skip": 100.0,
}

# The match intro/outro is a plain on/off, not a speed. Everything in those scenes is already
# click-to-skip and the only thing a multiplier changed was how long the screen sat there — so the
# choice that actually matters is "play it" or "don't".
const INTRO_OUTRO_OPTIONS := ["play", "skip"]

const DEFAULT_ANIMATION_SPEED  := "normal"
const DEFAULT_ITEM_SPEED       := "normal"
const DEFAULT_PACK_SPEED       := "normal"
const DEFAULT_INTRO_OUTRO      := "play"

# The player's currently selected preset keys. Persisted in Player_Current_Data.json.
var animation_speed_setting: String   = DEFAULT_ANIMATION_SPEED
var item_speed_setting: String        = DEFAULT_ITEM_SPEED
var pack_speed_setting: String        = DEFAULT_PACK_SPEED
var intro_outro_setting: String       = DEFAULT_INTRO_OUTRO

# Applies a preset key to the live multiplier. Pass save = false to set it without touching the
# save file (used on boot).
func set_animation_speed(preset: String, save: bool = true) -> void:
	if not ANIMATION_SPEED_PRESETS.has(preset):
		push_warning("GameState: unknown match animation speed preset '" + preset + "'")
		return
	animation_speed_setting = preset
	card_match_animation_speed = ANIMATION_SPEED_PRESETS[preset]
	if save:
		_save_current_data_field("animation_speed", animation_speed_setting)

func set_item_speed(preset: String, save: bool = true) -> void:
	if not ITEM_SPEED_PRESETS.has(preset):
		push_warning("GameState: unknown item animation speed preset '" + preset + "'")
		return
	item_speed_setting = preset
	item_animation_speed = ITEM_SPEED_PRESETS[preset]
	if save:
		_save_current_data_field("item_animation_speed", item_speed_setting)

func set_pack_speed(preset: String, save: bool = true) -> void:
	if not PACK_SPEED_PRESETS.has(preset):
		push_warning("GameState: unknown pack animation speed preset '" + preset + "'")
		return
	pack_speed_setting = preset
	pack_animation_speed = PACK_SPEED_PRESETS[preset]
	if save:
		_save_current_data_field("pack_animation_speed", pack_speed_setting)

func set_intro_outro(choice: String, save: bool = true) -> void:
	if not choice in INTRO_OUTRO_OPTIONS:
		push_warning("GameState: unknown intro/outro choice '" + choice + "'")
		return
	intro_outro_setting = choice
	if save:
		_save_current_data_field("intro_outro_animation", intro_outro_setting)

# Reads every saved animation preset out of Player_Current_Data.json and applies it. Called once on
# boot. An unknown value falls back to the default rather than erroring, so a wiped or hand-edited
# save still boots cleanly.
func _load_animation_speed() -> void:
	var data := _read_current_data()

	var preset: String = str(data.get("animation_speed", DEFAULT_ANIMATION_SPEED))
	if not ANIMATION_SPEED_PRESETS.has(preset):
		preset = DEFAULT_ANIMATION_SPEED
	set_animation_speed(preset, false)

	var item: String = str(data.get("item_animation_speed", DEFAULT_ITEM_SPEED))
	if not ITEM_SPEED_PRESETS.has(item):
		item = DEFAULT_ITEM_SPEED
	set_item_speed(item, false)

	var pack: String = str(data.get("pack_animation_speed", DEFAULT_PACK_SPEED))
	if not PACK_SPEED_PRESETS.has(pack):
		pack = DEFAULT_PACK_SPEED
	set_pack_speed(pack, false)

	var intro: String = str(data.get("intro_outro_animation", DEFAULT_INTRO_OUTRO))
	if not intro in INTRO_OUTRO_OPTIONS:
		intro = DEFAULT_INTRO_OUTRO
	set_intro_outro(intro, false)

# ISSUE #34: the overworld walking-speed presets offered by the Options screen, keyed by the value
# stored in Player_Current_Data.json under "walking_speed". TWEAKABLE — raising a number speeds that
# preset up. Shift-to-run stacks on top of this (run_multiplier in Player_Object_Script.gd), so the
# gap between slow and fast reads more clearly while walking than while sprinting.
const WALKING_SPEED_PRESETS := {
	"very_slow": 0.4,
	"slow": 0.6,
	"normal": 1.1,
	"fast": 1.6,
}
const DEFAULT_WALKING_SPEED := "normal"

# The player's currently selected preset key. Persisted in Player_Current_Data.json.
var walking_speed_setting: String = DEFAULT_WALKING_SPEED

# Applies a preset key to the live walking multiplier. Pass save = true to also persist it.
func set_walking_speed(preset: String, save: bool = true) -> void:
	if not WALKING_SPEED_PRESETS.has(preset):
		push_warning("GameState: unknown walking speed preset '" + preset + "'")
		return
	walking_speed_setting = preset
	overworld_walking_speed = WALKING_SPEED_PRESETS[preset]
	if save:
		_save_walking_speed()

# Reads the saved preset out of Player_Current_Data.json and applies it. Called once on boot.
func _load_walking_speed() -> void:
	var data := _read_current_data()
	var preset: String = str(data.get("walking_speed", DEFAULT_WALKING_SPEED))
	if not WALKING_SPEED_PRESETS.has(preset):
		preset = DEFAULT_WALKING_SPEED
	set_walking_speed(preset, false)

func _save_walking_speed() -> void:
	_save_current_data_field("walking_speed", walking_speed_setting)

# ISSUE #34: the two match-rule variants offered by the Options screen. Each entry is the string
# stored in Player_Current_Data.json, and is copied into the match core's own burn_rules /
# confusion_rules at the start of every match.
#   Confusion — base_set:   retreat flip AFTER paying the energy; tails = energy still discarded
#                           and the Pokemon stays put.
#               fairer:     retreat flip BEFORE paying the energy; tails = 20 self-damage and the
#                           retreat is cancelled, but the energy is kept. (House rule.)
#               modern_era: confusion doesn't affect retreat at all (ex-era rules).
#   Burn      — base_set:   flip between turns; tails = 20 burn damage, and burn never self-cures.
#               modern_era: 20 burn damage every turn, then flip — heads cures the burn.
const CONFUSION_RULE_OPTIONS := ["base_set_confusion_rules", "fairer_confusion_rules", "modern_era_confusion_rules"]
const BURN_RULE_OPTIONS      := ["base_set_burn_rules", "modern_era_burn_rules"]
const DEFAULT_CONFUSION_RULE := "base_set_confusion_rules"
const DEFAULT_BURN_RULE      := "base_set_burn_rules"

var confusion_rule_setting: String = DEFAULT_CONFUSION_RULE
var burn_rule_setting: String = DEFAULT_BURN_RULE

# Applies a rule choice. Pass save = false to set it without touching the save file (used on boot).
func set_confusion_rule(rule: String, save: bool = true) -> void:
	if not rule in CONFUSION_RULE_OPTIONS:
		push_warning("GameState: unknown confusion rule '" + rule + "'")
		return
	confusion_rule_setting = rule
	if save:
		_save_current_data_field("confusion_rules", rule)

func set_burn_rule(rule: String, save: bool = true) -> void:
	if not rule in BURN_RULE_OPTIONS:
		push_warning("GameState: unknown burn rule '" + rule + "'")
		return
	burn_rule_setting = rule
	if save:
		_save_current_data_field("burn_rules", rule)

# Reads both saved rule choices out of Player_Current_Data.json. Called once on boot.
func _load_rule_settings() -> void:
	var data := _read_current_data()
	var confusion: String = str(data.get("confusion_rules", DEFAULT_CONFUSION_RULE))
	if not confusion in CONFUSION_RULE_OPTIONS:
		confusion = DEFAULT_CONFUSION_RULE
	set_confusion_rule(confusion, false)
	var burn: String = str(data.get("burn_rules", DEFAULT_BURN_RULE))
	if not burn in BURN_RULE_OPTIONS:
		burn = DEFAULT_BURN_RULE
	set_burn_rule(burn, false)

# Writes a single key back into Player_Current_Data.json, leaving every other key untouched.
func _save_current_data_field(key: String, value) -> void:
	var data := _read_current_data()
	if data.is_empty():
		return
	data[key] = value
	var write_file := FileAccess.open(PLAYER_CURRENT_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("GameState: cannot write " + PLAYER_CURRENT_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

func _read_current_data() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_CURRENT_DATA_PATH):
		return {}
	var file := FileAccess.open(PLAYER_CURRENT_DATA_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

# Scales an animation DURATION by a speed multiplier (duration / multiplier), clamped so a zero or
# negative multiplier can never divide by zero or invert the animation.
func scaled_duration(base_seconds: float, multiplier: float) -> float:
	if multiplier <= 0.05:
		multiplier = 0.05
	return base_seconds / multiplier

# ISSUE #34: shorthands for the three animation multipliers. Prefer these over calling
# scaled_duration() with an explicit multiplier — they keep call sites short enough that wrapping a
# hardcoded duration stays a drop-in edit:
#     await get_tree().create_timer(0.5).timeout
#     await get_tree().create_timer(GameState.match_time(0.5)).timeout
#   match_time() — anything inside a card match
#   item_time()  — gift coin/card flips and costume fade-ins
#   pack_time()  — the pack opening sequence
# The match intro/outro scenes use plain literal durations; they are governed by an on/off choice,
# not a multiplier. Do NOT use any of these for loading throttles or asset-streaming waits — at a
# "skip" preset they collapse to ~0 and would spin those loops.
func match_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, card_match_animation_speed)

func item_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, item_animation_speed)

func pack_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, pack_animation_speed)

# True when the player has turned the match intro/outro ceremony off. Callers bypass whole sequences
# (and their sound) rather than playing them fast — see Match_Start_Intro_Script.gd and
# Match_End_Outro_Script.gd. Note this never suppresses a REWARD reveal: those follow item speed.
func is_transition_skipped() -> bool:
	return intro_outro_setting == "skip"

# True when the pack opening animation should be bypassed entirely — the buy press jumps straight to
# the finished row of cards. See Pack_Opening_Manager._start_pack_opening().
func is_pack_skipped() -> bool:
	return pack_speed_setting == "skip"

var sleep_wakeup_fade: bool = false

# ISSUE #52: when a sub-menu (deck/costume/coin/sleeves/options/info) closes back to the standalone
# Main Menu, the menu redirects to the saved map scene with this flag set so the map is reloaded and
# the main menu is reopened as a transparent overlay on top of it (rather than showing black behind).
var reopen_menu_overlay: bool = false

# ISSUE #52 (retest): the live map scene registers itself here while its main-menu overlay is open.
# Sub-menus are then opened/closed as overlays on top of the still-loaded map, so returning to the
# main menu is instant instead of triggering a full world reload (the long black screen). Both
# helpers return false when there is no host (e.g. the menu was reached from a non-map scene), so
# every caller can fall back to the old change_scene behaviour.
var menu_overlay_host: Node = null

func open_sub_menu(scene_path: String) -> bool:
	if menu_overlay_host != null and is_instance_valid(menu_overlay_host) and menu_overlay_host.has_method("open_submenu_overlay"):
		menu_overlay_host.open_submenu_overlay(scene_path)
		return true
	return false

func close_sub_menu() -> bool:
	if menu_overlay_host != null and is_instance_valid(menu_overlay_host) and menu_overlay_host.has_method("close_submenu_overlay"):
		menu_overlay_host.close_submenu_overlay(true)
		return true
	return false

# ============================================================
# MATCH SERIES (best-of-N support)
# ============================================================
# Ephemeral — never saved to disk. Quitting the app mid-series
# resets the player to challenging the opponent fresh.
# Driven by an opponent's optional "match_format" field
# (e.g. "best_of_3"). Mid-series rematches bypass the outro and
# route straight to the intro; only the deciding game shows
# the outro/rewards.
var series_active: bool = false
var series_format: String = ""
var series_opponent_name: String = ""
var series_wins: int = 0
var series_losses: int = 0
var series_required_to_win: int = 0
var series_total_games: int = 0
var series_round_results: Array = []

func start_match_series(opponent_name: String, match_format: String) -> void:
	series_opponent_name = opponent_name
	series_format = match_format
	series_wins = 0
	series_losses = 0
	series_round_results = []
	match match_format:
		"best_of_3":
			series_total_games = 3
			series_required_to_win = 2
		_:
			# Unknown format — fall back to a single match.
			clear_match_series()
			return
	series_active = true

func clear_match_series() -> void:
	series_active = false
	series_format = ""
	series_opponent_name = ""
	series_wins = 0
	series_losses = 0
	series_total_games = 0
	series_required_to_win = 0
	series_round_results = []

# ============================================================
# CURRENT SCENE PERSISTENCE
# Tracks the player's current map and position so that the
# splash-screen entry point can resume them at the right place
# after the game restarts. Updated whenever the player moves
# between map scenes.
# ============================================================

const DEFAULT_START_SCENE := "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

func save_current_location(scene_path: String, pos: Vector2) -> void:
	progress["current_scene_path"] = scene_path
	progress["current_player_position"] = {"x": pos.x, "y": pos.y}
	save_progress()

func get_saved_scene_path() -> String:
	return progress.get("current_scene_path", DEFAULT_START_SCENE)

func get_saved_player_position() -> Vector2:
	var data = progress.get("current_player_position", null)
	if data is Dictionary and data.has("x") and data.has("y"):
		return Vector2(float(data["x"]), float(data["y"]))
	return Vector2.ZERO

func has_saved_player_position() -> bool:
	return progress.has("current_player_position")

# Captures the live player position from whichever map scene is active and
# writes it to disk. Called on window close so a quit-mid-walk doesn't lose
# the player's actual position.
func _save_live_player_position_on_quit() -> void:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	var scene_path := String(current_scene.scene_file_path)
	var player = current_scene.get_node_or_null("Player")
	if player == null:
		return
	if not (player is Node2D):
		return
	save_current_location(scene_path, player.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_live_player_position_on_quit()
		get_tree().quit()

# ============================================================
# MENU RETURN STATE
# Set by a map scene before opening the main menu so the player
# can be restored to the exact spot when the menu closes.
# Survives navigation through sub-menus (deck builder, options,
# coin case, trainer card) and is consumed by the destination
# map scene's _ready.
# ============================================================

var has_menu_return_state: bool = false
var menu_return_scene_path: String = ""
var menu_return_position: Vector2 = Vector2.ZERO
var menu_return_direction: String = "down"

func save_menu_return_state(scene_path: String, pos: Vector2, direction: String) -> void:
	has_menu_return_state = true
	menu_return_scene_path = scene_path
	menu_return_position = pos
	menu_return_direction = direction

func clear_menu_return_state() -> void:
	has_menu_return_state = false
	menu_return_scene_path = ""

# Progress tracking
var progress: Dictionary = {}

# user:// is writable in both editor and exported builds.
# On first run, if the file doesn't exist, we copy from res://.
const PROGRESS_PATH = "user://Player_Game_Progress.json"
const PROGRESS_SEED_PATH = "res://Player_Data/Player_Game_Progress.json"

const PLAYER_CURRENT_DATA_PATH = "user://Player_Current_Data.json"
const PLAYER_CURRENT_DATA_SEED_PATH = "res://Player_Data/Player_Current_Data.json"

const OWNED_CARDS_FOLDER = "user://Player_Owned_Cards/"
const OWNED_CARDS_SEED_FOLDER = "res://Player_Data/Player_Owned_Cards/"

const PLAYER_DECKS_FOLDER = "user://Player_Decks/"
const PLAYER_DECKS_SEED_FOLDER = "res://Player_Data/Player_Decks/"

# ============================================================
# INTERIOR SCENE TRANSITIONS
# ============================================================

var last_player_direction: String = "down"

func save_player_direction(direction: String):
	last_player_direction = direction

func get_player_direction() -> String:
	return last_player_direction

func save_interior_player_position(pos: Vector2):
	player_position = pos
	print("Saved interior position: ", pos)

func get_interior_player_position() -> Vector2:
	return player_position

func set_last_interior_scene(scene_name: String):
	last_interior_scene = scene_name
	print("Set last interior scene: ", scene_name)

func get_last_interior_scene() -> String:
	return last_interior_scene

func _ready():
	_ensure_user_data_exists()
	load_progress()
	_load_animation_speed()   # ISSUE #34: apply the saved Options animation-speed preset
	_load_walking_speed()     # ISSUE #34: apply the saved Options overworld walking-speed preset
	_load_rule_settings()     # ISSUE #34: apply the saved Options confusion / burn rule choices

# ============================================================
# FIRST-RUN DATA MIGRATION (res:// → user://)
# ============================================================

func _ensure_user_data_exists():
	# Copy Player_Game_Progress.json
	_copy_seed_file(PROGRESS_SEED_PATH, PROGRESS_PATH)

	# Copy Player_Current_Data.json
	_copy_seed_file(PLAYER_CURRENT_DATA_SEED_PATH, PLAYER_CURRENT_DATA_PATH)

	# Copy Player_Owned_Cards folder
	_copy_seed_folder(OWNED_CARDS_SEED_FOLDER, OWNED_CARDS_FOLDER)

	# Copy Player_Decks folder
	_copy_seed_folder(PLAYER_DECKS_SEED_FOLDER, PLAYER_DECKS_FOLDER)


func _copy_seed_file(seed_path: String, dest_path: String):
	if FileAccess.file_exists(dest_path):
		return
	if not FileAccess.file_exists(seed_path):
		return
	var file = FileAccess.open(seed_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var write_file = FileAccess.open(dest_path, FileAccess.WRITE)
	write_file.store_string(content)
	write_file.close()
	print("Copied seed file: ", seed_path, " -> ", dest_path)


func _copy_seed_folder(seed_folder: String, dest_folder: String):
	if not DirAccess.dir_exists_absolute(seed_folder):
		return
	if not DirAccess.dir_exists_absolute(dest_folder):
		DirAccess.make_dir_recursive_absolute(dest_folder)
	var dir = DirAccess.open(seed_folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			var dest_file = dest_folder + file_name
			if not FileAccess.file_exists(dest_file):
				_copy_seed_file(seed_folder + file_name, dest_file)
		file_name = dir.get_next()
	dir.list_dir_end()

# ============================================================
# PROGRESS FILE I/O
# ============================================================

func load_progress():
	if FileAccess.file_exists(PROGRESS_PATH):
		var file = FileAccess.open(PROGRESS_PATH, FileAccess.READ)
		var text = file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(text)
		if parsed != null:
			progress = parsed
		else:
			progress = {"opponents_beaten": [], "cash": 0, "coins": [], "costumes": []}
	else:
		progress = {"opponents_beaten": [], "cash": 0, "coins": [], "costumes": []}
		save_progress()

	# Ensure all expected fields exist for saves created before this update
	if not progress.has("cash"):
		progress["cash"] = 0
	if not progress.has("coins"):
		progress["coins"] = []
	if not progress.has("costumes"):
		progress["costumes"] = []
	if not progress.has("player_collected_starter_box"):
		progress["player_collected_starter_box"] = false
	if not progress.has("moving_in_completed"):
		progress["moving_in_completed"] = false
	if not progress.has("gifts_received"):
		progress["gifts_received"] = []
	if not progress.has("opponents_beaten_count_current"):
		progress["opponents_beaten_count_current"] = 0
	if not progress.has("opponents_beaten_count_total"):
		progress["opponents_beaten_count_total"] = 0
	if not progress.has("time"):
		progress["time"] = "Morning"
	elif progress.get("time") == "Day":
		progress["time"] = "Morning"
	if not progress.has("date"):
		progress["date"] = 1

	if not progress.has("gym_challenge_audience"):
		progress["gym_challenge_audience"] = {}
	if not progress.has("gym_challenge_audience_time"):
		progress["gym_challenge_audience_time"] = ""
	if not progress.has("gym_challenge_audience_date"):
		progress["gym_challenge_audience_date"] = 0
	if not progress.has("gym_challenge_audience_from_plaza"):
		progress["gym_challenge_audience_from_plaza"] = false

	if not progress.has("shop_state"):
		progress["shop_state"] = "initial"
	if not progress.has("shop_free_packs_given"):
		progress["shop_free_packs_given"] = false
	if not progress.has("player_collected_shop_starter_set"):
		progress["player_collected_shop_starter_set"] = false
	# Existing saves predate this field — treat them as already launched.
	# New games get false from the seed file, so this migration never fires for them.
	if not progress.has("first_launch_complete"):
		progress["first_launch_complete"] = true

	# Migrate old met_npcs dict to npc_interactions array
	if not progress.has("npc_interactions"):
		var old = progress.get("met_npcs", {})
		progress["npc_interactions"] = old.keys()
		progress.erase("met_npcs")

	if not progress.has("sleeves"):
		progress["sleeves"] = ["default"]

	# Migrate old coin filenames from "coin_pikachu_gold.png" to "Pikachu Gold.png"
	var coins_arr : Array = progress.get("coins", [])
	var migrated_any := false
	for i in coins_arr.size():
		if (coins_arr[i] as String).begins_with("coin_"):
			coins_arr[i] = _migrate_old_coin_name(coins_arr[i])
			migrated_any = true
	if migrated_any:
		progress["coins"] = coins_arr

	save_progress()

func save_progress():
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(progress, "\t"))
	file.close()

func mark_first_launch_complete() -> void:
	progress["first_launch_complete"] = true
	# Safety reset: zero every owned card and lock all pack sets so a game
	# reset always starts clean regardless of leftover user:// data.
	_reset_all_owned_cards()
	progress["packs_unlocked"] = []
	save_progress()

func _reset_all_owned_cards() -> void:
	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_player_owned_cards.json"):
			var path := OWNED_CARDS_FOLDER + fname
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var data = JSON.parse_string(f.get_as_text())
				f.close()
				if data is Dictionary and data.has("owned_cards"):
					for entry in data["owned_cards"]:
						entry["owned"] = 0
					var wf := FileAccess.open(path, FileAccess.WRITE)
					if wf != null:
						wf.store_string(JSON.stringify(data, "\t"))
						wf.close()
		fname = dir.get_next()
	dir.list_dir_end()

# Converts old "coin_pikachu_gold_1.png" format to "Pikachu Gold 1.png".
# Handles teamXXX compound words (teamplasma → Team Plasma, etc.).
func _migrate_old_coin_name(old: String) -> String:
	var base := old.replace("coin_", "").replace(".png", "")
	for team in ["teamplasma", "teamrocket", "teamaqua", "teammagma"]:
		base = base.replace(team, team.substr(0, 4) + "_" + team.substr(4))
	var parts := base.split("_")
	var titled : Array = []
	for p in parts:
		if p.length() > 0:
			titled.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(titled) + ".png"

# ============================================================
# CASH
# ============================================================

func get_cash() -> int:
	return progress.get("cash", 1000)

func add_cash(amount: int) -> void:
	progress["cash"] = get_cash() + amount
	save_progress()

# ============================================================
# OPPONENT TRACKING
# ============================================================

func has_beaten_opponent(opponent_name: String) -> bool:
	return opponent_name in progress.get("opponents_beaten", [])

func mark_opponent_beaten(opponent_name: String):
	if not has_beaten_opponent(opponent_name):
		progress["opponents_beaten"].append(opponent_name)
		progress["opponents_beaten_count_current"] = progress.get("opponents_beaten_count_current", 0) + 1
		progress["opponents_beaten_count_total"] = progress.get("opponents_beaten_count_total", 0) + 1
		save_progress()

# ============================================================
# TIME / DATE SYSTEM
# ============================================================

## Returns the current time of day string ("Morning", "Afternoon", "Evening", "Night")
func get_time() -> String:
	return progress.get("time", "Morning")

## Returns the current date as an integer (1, 2, 3, ...)
func get_date() -> int:
	return int(progress.get("date", 1))

func get_current_defeated() -> int:
	return int(progress.get("opponents_beaten_count_current", 0))

## Sets the time to a specific value. Pass an empty string to auto-step.
## Auto-step: Morning -> Afternoon -> Evening -> Night -> Morning (and increment date).
## Resets opponents_beaten_count_current to 0 on every time change.
func advance_time(new_time: String = "") -> void:
	if new_time == "":
		# Auto-step to next time period
		match get_time():
			"Morning":
				new_time = "Afternoon"
			"Afternoon":
				new_time = "Evening"
			"Evening":
				new_time = "Night"
			"Night":
				new_time = "Morning"
				progress["date"] = get_date() + 1
			_:
				new_time = "Morning"
	elif new_time == "Morning" and get_time() == "Night":
		# If explicitly moving from Night to Morning, also increment date
		progress["date"] = get_date() + 1

	progress["time"] = new_time
	progress["opponents_beaten_count_current"] = 0
	save_progress()
	print("Time advanced to: ", new_time, " | Date: ", get_date())

# ============================================================
# NPC INTERACTION TRACKING
# ============================================================

func has_met_npc(npc_name: String) -> bool:
	return npc_name in progress.get("npc_interactions", [])

func mark_npc_met(npc_name: String) -> void:
	if not has_met_npc(npc_name):
		if not progress.has("npc_interactions"):
			progress["npc_interactions"] = []
		progress["npc_interactions"].append(npc_name)
		save_progress()

# ============================================================
# GIFT TRACKING
# ============================================================

func has_received_gift(npc_name: String) -> bool:
	return npc_name in progress.get("gifts_received", [])

func mark_gift_received(npc_name: String):
	if not has_received_gift(npc_name):
		progress["gifts_received"].append(npc_name)
		save_progress()

# ============================================================
# COIN COLLECTION
# ============================================================

func add_coin_to_collection(coin_name: String):
	var coins = progress.get("coins", [])
	var coin_filename = coin_name if coin_name.ends_with(".png") else coin_name + ".png"
	if coin_filename not in coins:
		coins.append(coin_filename)
		progress["coins"] = coins
		save_progress()

func has_coin(coin_name: String) -> bool:
	var coins = progress.get("coins", [])
	var coin_filename = coin_name if coin_name.ends_with(".png") else coin_name + ".png"
	return coin_filename in coins

func get_coins() -> Array:
	return progress.get("coins", [])

# ============================================================
# COSTUME COLLECTION
# ============================================================

func has_costume(battle_sprite: String) -> bool:
	var costumes = progress.get("costumes", [])
	var costume_filename = battle_sprite.to_lower() + ".png"
	return costume_filename in costumes

func add_costume_to_collection(battle_sprite: String) -> void:
	var costumes = progress.get("costumes", [])
	var costume_filename = battle_sprite.to_lower() + ".png"
	if costume_filename not in costumes:
		costumes.append(costume_filename)
		progress["costumes"] = costumes
		save_progress()

func get_costumes() -> Array:
	return progress.get("costumes", [])

# ============================================================
# SLEEVE COLLECTION
# ============================================================

func has_sleeve(sleeve_name: String) -> bool:
	return sleeve_name in progress.get("sleeves", [])

func add_sleeve_to_collection(sleeve_name: String) -> void:
	var sleeves = progress.get("sleeves", [])
	if sleeve_name not in sleeves:
		sleeves.append(sleeve_name)
		progress["sleeves"] = sleeves
		save_progress()

func get_sleeves() -> Array:
	return progress.get("sleeves", [])

# ============================================================
# CARD GIVING (Global)
# ============================================================
# Accepts a comma-separated string of card IDs, e.g.:
#   "base1-1, base2-5, base5-20"
# Duplicates are fine — each occurrence increments owned count by 1.
# Batches writes per set file so "base1-1, base1-1, base1-5" only
# opens/writes the base1 file once.

func give_cards(card_ids_csv: String) -> void:
	var ids: Array = []
	for raw in card_ids_csv.split(","):
		var trimmed = raw.strip_edges()
		if trimmed != "":
			ids.append(trimmed)

	if ids.is_empty():
		push_error("GameState.give_cards: No valid card IDs in: " + card_ids_csv)
		return

	# Group by set name so we only read/write each file once
	var by_set: Dictionary = {}
	for card_id in ids:
		var parts = card_id.split("-")
		if parts.size() < 2:
			push_error("GameState.give_cards: Invalid card_id format: " + card_id)
			continue
		var set_name = parts[0]
		if not by_set.has(set_name):
			by_set[set_name] = []
		by_set[set_name].append(card_id)

	for set_name in by_set.keys():
		var json_path = OWNED_CARDS_FOLDER + set_name + "_player_owned_cards.json"
		var file = FileAccess.open(json_path, FileAccess.READ)
		if file == null:
			push_error("GameState.give_cards: Cannot open: " + json_path)
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()

		for card_id in by_set[set_name]:
			var found = false
			for entry in data["owned_cards"]:
				if entry["card_id"] == card_id:
					entry["owned"] = entry["owned"] + 1
					found = true
					break
			if not found:
				data["owned_cards"].append({"card_id": card_id, "owned": 1})

		data["set_unlocked"] = true
		var write_file = FileAccess.open(json_path, FileAccess.WRITE)
		write_file.store_string(JSON.stringify(data, "\t"))
		write_file.close()

	print("GameState.give_cards: Gave ", ids.size(), " cards")
