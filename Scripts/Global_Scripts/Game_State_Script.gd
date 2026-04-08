extends Node

# ============================================================
# GAME STATE - Autoload Singleton
# ============================================================
# This script persists between scene changes. It holds data
# that needs to survive when switching from WorldMap → Match
# and back. Register this as an Autoload in Project Settings.
# ============================================================

# Data passed between scenes during a match
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

# The res:// path of the map level the player was on when they entered a battle.
# After the match outro finishes we transition back to this scene.
var return_map_scene_path: String = ""

var last_interior_scene: String = ""

# Progress tracking
var progress: Dictionary = {}

const PROGRESS_PATH = "res://Player_Data/Player_Game_Progress.json"

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
	load_progress()

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
		save_progress()
	if not progress.has("player_collected_starter_box"):
		progress["player_collected_starter_box"] = false
	if not progress.has("moving_in_completed"):
		progress["moving_in_completed"] = false
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
		save_progress()

# ============================================================
# COIN COLLECTION
# ============================================================

func add_coin_to_collection(coin_name: String):
	var coins = progress.get("coins", [])
	
	# If coin_name doesn't have .png extension, add it
	var coin_filename = coin_name if coin_name.ends_with(".png") else coin_name + ".png"
	
	# Only add if not already in collection
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
	
	# Only add if not already in collection
	if costume_filename not in costumes:
		costumes.append(costume_filename)
		progress["costumes"] = costumes
		save_progress()

func get_costumes() -> Array:
	return progress.get("costumes", [])
