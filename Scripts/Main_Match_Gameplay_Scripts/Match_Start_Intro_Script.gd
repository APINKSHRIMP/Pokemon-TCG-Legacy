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
	print("DEBUG INTRO json path from GameState: ", GameState.current_opponent_map)
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

	# Step 5 (early): stop any existing BGM (map music) before the intro plays
	SoundManagerScript.stop_bgm()

	# ISSUE #34: Options "Play Match Intro / Outro Animation?" = skip animations. Hand straight to the match
	# without ever showing (or sounding) the intro. The scene still has to run this far because it
	# owns main_match_instance, but nothing here is seen or heard: no battle-start SFX, no fade in,
	# no drift, no fade out. The player clicks "yes" and is in the match.
	if GameState.is_transition_skipped():
		# Yield one frame first: transition_to_main_match() reparents main_match_instance onto the
		# tree root and frees this scene, which must not happen while _ready() is still running.
		await get_tree().process_frame
		transition_to_main_match()
		return

	# Step 4: Play battle start SFX through SoundManager
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start)

	# Step 6: Fade in from black then run animations
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, GameState.transition_time(0.5))
	await fade_in.finished
	
	# Scene is now visible — allow clicking to skip
	click_enabled = true
	
	# Start the intro animation (runs in background, click can interrupt)
	animate_intro()

func _input(event: InputEvent) -> void:
	# Space / Enter / Escape skip the intro, the same as a click. Escape used to call
	# get_tree().quit() here, so one stray press on the way into a match closed the game.
	if UIInput.is_advance(event) and click_enabled and not transitioning:
		get_viewport().set_input_as_handled()
		transition_to_main_match()
		return

	# Any mouse click while the scene is showing skips to the match.
	# ISSUE #135 FIX: the wheel is not a click -- scrolling used to skip the intro.
	if UIInput.is_click(event) and click_enabled and not transitioning:
		transition_to_main_match()

# ============================================================
# DATA LOADING
# ============================================================

func load_opponent_data(trainer_name: String) -> void:
	# TEMP TESTING: T-key TEST match synthesizes opponent data instead of reading NPC JSON.
	if GameState.test_match_mode:
		opponent_data = GameState.build_test_opponent_data()
		GameDataManager.opponent_data = opponent_data
		return

	# CharacterSchedule resolves today's cast from the map's character file and
	# layers All_NPC_Constant_Data.json underneath, which is what the day-file
	# search plus manual constants merge used to do by hand here.
	opponent_data = CharacterSchedule.find_opponent(
		GameState.current_opponent_map, trainer_name,
		GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if opponent_data.is_empty():
		print("Opponent with name ", trainer_name, " not found on map ",
			GameState.current_opponent_map)
		return

	GameDataManager.opponent_data = opponent_data

func load_player_data() -> void:
	var file = FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
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
	
	if opponent_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + opponent_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			opponent_sprite.texture = tex
			_normalize_sprite_scale(opponent_sprite, tex)
		else:
			print("Could not load opponent sprite: ", path)
	
	if player_data.has("name"):
		player_name_label.text = player_data["name"].replace("_", " ")
	if player_data.has("deck"):
		player_deck_label.text = player_data["deck"].replace("_", " ")
	
	if player_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + player_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			player_sprite.texture = tex
			player_sprite.flip_h = true
			_normalize_sprite_scale(player_sprite, tex)
		else:
			print("Could not load player sprite: ", path)

func _normalize_sprite_scale(sprite: Sprite2D, tex: Texture2D) -> void:
	const TARGET: float = 480.0
	var tex_size := tex.get_size()
	var s := minf(TARGET / tex_size.x, TARGET / tex_size.y)
	sprite.scale = Vector2(s, s)

# ============================================================
# ANIMATION
# ============================================================

func animate_intro() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(true)

	# The intro is click-to-skip. There is no speed multiplier: Options offers only play-or-skip,
	# and skip never reaches here (see _ready).
	#
	# Reduce motion is a THIRD state and is not the same as skip. At zero duration every property
	# lands on its final value immediately, and the hold after `await` keeps the screen up for the
	# beat the drift would have taken — the player still sees who they are fighting, the picture
	# just does not move. Removing the screen is what the intro/outro row is for.
	var reduced := GameState.is_motion_reduced()
	var dur: float = 0.0 if reduced else animation_duration
	tween.tween_property(player_sprite, "position:x", player_sprite.position.x - 100, dur)
	tween.tween_property(opponent_sprite, "position:x", opponent_sprite.position.x + 100, dur)
	tween.tween_property(player_name_label, "position:y", player_name_label.position.y - 50, dur)
	tween.tween_property(player_deck_label, "position:y", player_deck_label.position.y - 50, dur)
	tween.tween_property(opponent_name_label, "position:y", opponent_name_label.position.y + 50, dur)
	tween.tween_property(opponent_deck_label, "position:y", opponent_deck_label.position.y + 50, dur)
	tween.tween_property(background, "scale", Vector2(1.15, 1.15), dur)
	
	# If the animation finishes naturally (not skipped), transition automatically
	await tween.finished
	if reduced:
		await get_tree().create_timer(animation_duration).timeout
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

	# ISSUE #34: on "skip" the scene was never made visible (modulate.a is still 0), so there is
	# nothing to fade out — go straight to the match rather than awaiting a tween on an invisible node.
	if not GameState.is_transition_skipped():
		# Fade out to black
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, GameState.transition_time(0.5))
		await tween.finished

	get_tree().root.add_child(main_match_instance)
	get_tree().set_current_scene(main_match_instance)
	queue_free()
