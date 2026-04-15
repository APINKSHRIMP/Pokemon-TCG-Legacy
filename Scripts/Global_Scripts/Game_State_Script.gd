extends Node

# ============================================================
# GAME STATE - Autoload Singleton
# ============================================================

var current_opponent_name: String = ""
var current_opponent_json_path: String = ""
var returning_from_battle: bool = false
var battle_result: String = ""  # "win" or "loss"
var player_position: Vector2 = Vector2.ZERO
var current_opponent_deck: String = ""
var return_to_scene: String = ""
var interior_entry_position: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var use_spawn_position: bool = false

var return_map_scene_path: String = ""
var last_interior_scene: String = ""

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
			progress = {"opponents_beaten": [], "cash": 1000, "coins": [], "costumes": []}
	else:
		progress = {"opponents_beaten": [], "cash": 1000, "coins": [], "costumes": []}
		save_progress()

	# Ensure all expected fields exist for saves created before this update
	if not progress.has("cash"):
		progress["cash"] = 1000
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
		progress["time"] = "Day"
	if not progress.has("date"):
		progress["date"] = 1

	# Migrate old met_npcs dict to npc_interactions array
	if not progress.has("npc_interactions"):
		var old = progress.get("met_npcs", {})
		progress["npc_interactions"] = old.keys()
		progress.erase("met_npcs")

	save_progress()

func save_progress():
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(progress, "\t"))
	file.close()

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

## Returns the current time of day string ("Day", "Evening", "Night")
func get_time() -> String:
	return progress.get("time", "Day")

## Returns the current date as an integer (1, 2, 3, ...)
func get_date() -> int:
	return int(progress.get("date", 1))

## Sets the time to a specific value. Pass an empty string to auto-step.
## Auto-step: Day -> Evening -> Night -> Day (and increment date).
## Resets opponents_beaten_count_current to 0 on every time change.
func advance_time(new_time: String = "") -> void:
	if new_time == "":
		# Auto-step to next time period
		match get_time():
			"Day":
				new_time = "Evening"
			"Evening":
				new_time = "Night"
			"Night":
				new_time = "Day"
				progress["date"] = get_date() + 1
			_:
				new_time = "Day"
	elif new_time == "Day" and get_time() == "Night":
		# If explicitly moving from Night to Day, also increment date
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
