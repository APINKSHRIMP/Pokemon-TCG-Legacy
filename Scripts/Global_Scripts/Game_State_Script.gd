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

# ISSUE #34: global game-speed multipliers, to be exposed in the Options submenu later. 1.0 = the
# current "standard" (medium) speed. Higher = faster. Read these wherever an animation/movement
# duration is computed so the whole game honours the player's speed preference.
#   card_match_animation_speed  — regular card-match animations (place/attach/retreat/discard).
#                                 Options: slow 0.5, standard 1.0, fast 2.0.
#   overworld_walking_speed     — the player's default overworld walk/run speed multiplier.
#                                 Options: slow 0.8, standard 1.0, fast 1.2.
#   overworld_animation_speed   — overworld reward/gift animations (coin/card spins, fades, etc.).
#                                 Options: slow 0.5, standard 1.0, fast 2.0.
# ISSUE #34 (TEMPORARY TEST VALUE): the animation multipliers are set to the "fast" 2.0 so every
# card-match / overworld animation can be checked for a missing multiplier. Revert these two to 1.0
# once the Options submenu is wired up (walking speed left at standard 1.0).
var card_match_animation_speed: float = 2.0
var overworld_walking_speed: float = 1.0
var overworld_animation_speed: float = 2.0

# Scales an animation DURATION by a speed multiplier (duration / multiplier), clamped so a zero or
# negative multiplier can never divide by zero or invert the animation.
func scaled_duration(base_seconds: float, multiplier: float) -> float:
	if multiplier <= 0.05:
		multiplier = 0.05
	return base_seconds / multiplier

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
