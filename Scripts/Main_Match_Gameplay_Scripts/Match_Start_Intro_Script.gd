extends Control

# ============================================================
# MATCH INTRO SCENE SCRIPT - the VS screen
# ============================================================
# Plays the pre-battle screen: loads opponent and player data, builds the shared
# BattleFrame, runs its one-shot entrance, then hands over to the main match.
# A click or Space / Enter / Escape skips straight to the match at any point.
#
# The scene file is deliberately almost empty. Everything on screen is built here
# through BattleFrame, so the intro, the outro and the best-of-three tracker
# cannot drift apart - and there are no baked colours in a .tscn to go stale when
# the theme changes.
# ============================================================

const BATTLE_SPRITE_DIR := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"
# The prize count's icon. There is no separate trophy asset; this is the same
# prize-card icon the message box's prize chip uses, which is what makes the two
# read as the same piece of information in two places.
const PRIZE_ICON := "res://Image_Assets/Icons/Message_Icons/prizes.png"

# -- TWEAKABLE ------------------------------------------------
const VS_FONT_SIZE   : int   = 56
const PRIZE_FONT     : int   = 26
const PRIZE_ICON_PX  : float = 30.0
const PRIZE_ICON_GAP : float = 10.0
# How long the settled screen sits there before it hands over on its own. Scaled
# by the Animation speed preset, and NOT collapsed by reduce motion - the screen
# is the information, the movement is the decoration.
const HOLD_AFTER     : float = 1.6
const FADE_TIME      : float = 0.5

var opponent_data: Dictionary
var player_data: Dictionary
var main_match_scene: PackedScene
var main_match_instance: Node

var frame: BattleFrame = null

# Click-to-skip tracking
var click_enabled: bool = false
var transitioning: bool = false


func _ready() -> void:
	# Start fully black so the frame can fade in.
	modulate.a = 0.0

	load_opponent_data(GameState.current_opponent_name)
	load_player_data()

	# Preloaded here rather than at hand-over: the match scene is heavy, and this
	# is the one moment in the flow where the player is watching something else.
	main_match_scene = load("res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn")
	main_match_instance = main_match_scene.instantiate()

	SoundManagerScript.stop_bgm()

	# Options "Play Match Intro / Outro Animation?" = skip. Hand straight to the match
	# without ever showing (or sounding) the intro. The scene still has to run this far
	# because it owns main_match_instance, but nothing here is seen or heard.
	if GameState.is_transition_skipped():
		# Yield one frame first: transition_to_main_match() reparents main_match_instance
		# onto the tree root and frees this scene, which must not happen while _ready()
		# is still running.
		await get_tree().process_frame
		transition_to_main_match()
		return

	_build_frame()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start)

	# The fade and the entrance run TOGETHER. Awaiting the fade first is what made the
	# screen sit finished-but-still for half a second and then jump into motion: the
	# elements are parked at their start offsets from the moment the frame is built,
	# so the fade should be revealing movement that is already under way.
	var fade_in := create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, GameState.transition_time(FADE_TIME))
	# A click only counts once the screen is actually up, so this is armed on the
	# fade's completion rather than immediately - a stray click carried in from the
	# overworld must not skip an intro the player has not seen yet.
	fade_in.tween_callback(func() -> void: click_enabled = true)

	await frame.play_entrance()
	await get_tree().create_timer(frame.hold_time(HOLD_AFTER)).timeout
	if not transitioning:
		transition_to_main_match()


func _input(event: InputEvent) -> void:
	# Space / Enter / Escape skip the intro, the same as a click. Escape used to call
	# get_tree().quit() here, so one stray press on the way into a match closed the game.
	if UIInput.is_advance(event) and click_enabled and not transitioning:
		get_viewport().set_input_as_handled()
		transition_to_main_match()
		return

	# Any mouse click while the scene is showing skips to the match. The wheel is
	# not a click -- scrolling used to skip the intro.
	if UIInput.is_click(event) and click_enabled and not transitioning:
		transition_to_main_match()


# ============================================================
# THE SCREEN
# ============================================================

func _build_frame() -> void:
	frame = BattleFrame.new()
	add_child(frame)
	frame.setup("intro")

	frame.set_trainer(frame.player, _sprite_for(player_data),
			str(player_data.get("name", "")), str(player_data.get("deck", "")))
	frame.set_trainer(frame.opponent, _sprite_for(opponent_data),
			str(opponent_data.get("name", "")), str(opponent_data.get("deck", "")))

	frame.badge_slot.add_child(frame.make_badge("VS", "intro", VS_FONT_SIZE))
	_build_prize_count()


# The prize count under the wheel: an icon and a number, nothing else. No square,
# no pill, no chip background - and nothing beside it. A "first meeting" pill and
# a second trophy next to the opponent were both tried and rejected.
#
# It is CENTRED BY LAYOUT (an HBox centred inside the below-badge column) and
# ANIMATED BY TRANSFORM (the column's own wrapper). Doing both on one node is what
# lands it off-centre once the entrance finishes.
func _build_prize_count() -> void:
	var prizes: int = int(opponent_data.get("prize_cards", 6))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(PRIZE_ICON_GAP))
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if ResourceLoader.exists(PRIZE_ICON):
		var tex: Texture2D = load(PRIZE_ICON)
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(PRIZE_ICON_PX, PRIZE_ICON_PX)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)

	var num := Label.new()
	num.text = str(prizes)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_override("font", UITheme.font("title"))
	num.add_theme_font_size_override("font_size", PRIZE_FONT)
	num.add_theme_color_override("font_color", UITheme.battle_col("prize_gold"))
	row.add_child(num)

	frame.below_badge.add_child(row)


func _sprite_for(data: Dictionary) -> Texture2D:
	var key := str(data.get("sprite", ""))
	if key == "":
		return null
	var path := BATTLE_SPRITE_DIR + key.to_lower() + ".png"
	if not ResourceLoader.exists(path):
		print("Could not load battle sprite: ", path)
		return null
	return load(path)


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
# HAND-OVER
# ============================================================

func transition_to_main_match() -> void:
	# Prevent multiple triggers
	transitioning = true
	click_enabled = false

	# Stop any battle start SFX that may still be playing
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.queue_free()

	# On "skip" the scene was never made visible (modulate.a is still 0), so there is
	# nothing to fade out - go straight to the match rather than awaiting a tween on
	# an invisible node.
	if not GameState.is_transition_skipped():
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, GameState.transition_time(FADE_TIME))
		await tween.finished

	get_tree().root.add_child(main_match_instance)
	get_tree().set_current_scene(main_match_instance)
	queue_free()
