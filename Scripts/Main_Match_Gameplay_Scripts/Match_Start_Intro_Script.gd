extends Control

# ============================================================
# MATCH INTRO SCENE SCRIPT
# ============================================================
# Plays the pre-battle intro animation: loads opponent/player
# data, shows sprites sliding in, plays the battle start SFX
# via SoundManager, then transitions to the main match scene.
# Click at any time to skip the animation and go straight to
# the match.
# ============================================================

# Variables to store data
var opponent_data: Dictionary
var player_data: Dictionary
var animation_duration: float = 5
var main_match_scene: PackedScene
var main_match_instance: Node

# Click-to-skip tracking
var click_enabled: bool = false
var transitioning: bool = false

# References to nodes (these get populated when the scene loads)
@onready var background = $match_intro_background
@onready var player_sprite = $PLAYER/player_sprite
@onready var player_name_label = $PLAYER/player_name
@onready var player_deck_label = $PLAYER/player_deck_name
@onready var opponent_sprite = $OPPONENT/opponent_sprite
@onready var opponent_name_label = $OPPONENT/opponent_name
@onready var opponent_deck_label = $OPPONENT/opponent_deck_name

# Called when the scene enters the scene tree
func _ready() -> void:
	print("DEBUG INTRO opponent name from GameState: ", GameState.current_opponent_name)
	print("DEBUG INTRO json path from GameState: ", GameState.current_opponent_json_path)
	# Start fully black so we can fade in
	modulate.a = 0.0
	
	var opponent_name = GameState.current_opponent_name
	
	# Step 1: Load opponent and player data
	load_opponent_data(opponent_name)
	load_player_data()
	
	# Step 2: Preload the main match scene
	main_match_scene = load("res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn")
	main_match_instance = main_match_scene.instantiate()
	
	# Step 3: Update UI with loaded data
	update_ui_with_data()
	
	# Step 4: Play battle start SFX through SoundManager
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start)
	
	# Step 5: Stop any existing BGM (map music) before the intro plays
	SoundManagerScript.stop_bgm()
	
	# Step 6: Fade in from black then run animations
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.5)
	await fade_in.finished
	
	# Scene is now visible — allow clicking to skip
	click_enabled = true
	
	# Start the intro animation (runs in background, click can interrupt)
	animate_intro()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	
	# Any mouse click while the scene is showing skips to the match
	if event is InputEventMouseButton and event.pressed and click_enabled and not transitioning:
		transition_to_main_match()

# ============================================================
# DATA LOADING
# ============================================================

func load_opponent_data(trainer_name: String) -> void:
	var file = FileAccess.open(GameState.current_opponent_json_path, FileAccess.READ)
	if file == null:
		print("Error loading opponent file")
		return
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error")
		return
	
	var opponents = json.data["opponents"]
	for opponent in opponents:
		if opponent.get("name") == trainer_name:
			opponent_data = opponent
			GameDataManager.opponent_data = opponent_data
			return
	
	print("Opponent with deck ", trainer_name, " not found")

func load_player_data() -> void:
	var file = FileAccess.open("res://Player_Data/Player_Current_Data.json", FileAccess.READ)
	if file == null:
		print("Error loading player file")
		return
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error for player data")
		return
	
	player_data = json.data
	GameDataManager.player_data = player_data

# ============================================================
# UI UPDATE
# ============================================================

func update_ui_with_data() -> void:
	if opponent_data.has("name"):
		opponent_name_label.text = opponent_data["name"].replace("_", " ")
	if opponent_data.has("deck"):
		opponent_deck_label.text = opponent_data["deck"].replace("_", " ")
	
	if opponent_data.has("battle_sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + opponent_data["battle_sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			opponent_sprite.texture = tex
		else:
			print("Could not load opponent sprite: ", path)
	
	if player_data.has("name"):
		player_name_label.text = player_data["name"].replace("_", " ")
	if player_data.has("deck"):
		player_deck_label.text = player_data["deck"].replace("_", " ")
	
	if player_data.has("battle_sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + player_data["battle_sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			player_sprite.texture = tex
			player_sprite.flip_h = true
		else:
			print("Could not load player sprite: ", path)

# ============================================================
# ANIMATION
# ============================================================

func animate_intro() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(true)
	
	tween.tween_property(player_sprite, "position:x", player_sprite.position.x - 100, animation_duration)
	tween.tween_property(opponent_sprite, "position:x", opponent_sprite.position.x + 100, animation_duration)
	tween.tween_property(player_name_label, "position:y", player_name_label.position.y - 50, animation_duration)
	tween.tween_property(player_deck_label, "position:y", player_deck_label.position.y - 50, animation_duration)
	tween.tween_property(opponent_name_label, "position:y", opponent_name_label.position.y + 50, animation_duration)
	tween.tween_property(opponent_deck_label, "position:y", opponent_deck_label.position.y + 50, animation_duration)
	tween.tween_property(background, "scale", Vector2(1.15, 1.15), animation_duration)
	
	# If the animation finishes naturally (not skipped), transition automatically
	await tween.finished
	if not transitioning:
		transition_to_main_match()

func transition_to_main_match() -> void:
	# Prevent multiple triggers
	transitioning = true
	click_enabled = false
	
	# Stop any battle start SFX that may still be playing
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.queue_free()
	
	# Fade out to black
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	
	get_tree().root.add_child(main_match_instance)
	get_tree().set_current_scene(main_match_instance)
	queue_free()
