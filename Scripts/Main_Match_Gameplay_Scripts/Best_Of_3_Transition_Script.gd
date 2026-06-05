extends Control

var opponent_data: Dictionary = {}
var player_data: Dictionary = {}
var _transitioning: bool = false
var _click_enabled: bool = false
var _decided: bool = false

const ANIMATION_DURATION := 2.5
# Same timing as the gift coin spin in Match_End_Outro
const SPIN_DURATIONS := [0.01, 0.02, 0.04, 0.06, 0.08, 0.1, 0.11, 0.12, 0.2]

@onready var win_background: TextureRect = $win_background
@onready var loss_background: TextureRect = $loss_background
@onready var player_sprite: Sprite2D = $PLAYER/player_sprite
@onready var opponent_sprite: Sprite2D = $OPPONENT/opponent_sprite
@onready var round_win_label: Label = $round_win
@onready var round_loss_label: Label = $round_loss
@onready var win1: TextureRect = $win1
@onready var win2: TextureRect = $win2
@onready var win3: TextureRect = $win3
@onready var loss1: TextureRect = $loss1
@onready var loss2: TextureRect = $loss2
@onready var loss3: TextureRect = $loss3

func _ready() -> void:
	modulate.a = 0.0

	var round_results: Array = GameState.series_round_results
	var current_round: int = round_results.size()
	var current_result: String = round_results.back() if not round_results.is_empty() else "loss"
	var battle_won: bool = (current_result == "win")
	_decided = (
		GameState.series_wins >= GameState.series_required_to_win
		or GameState.series_losses >= GameState.series_required_to_win
	)

	# Label announces the upcoming round (or the decisive final round if series ends here)
	var label_round: int = min(current_round + 1, 3)
	round_win_label.text = "ROUND " + str(label_round)
	round_loss_label.text = "ROUND " + str(label_round)

	win_background.visible = battle_won
	loss_background.visible = not battle_won
	round_win_label.visible = battle_won
	round_loss_label.visible = not battle_won

	win1.visible = false; win2.visible = false; win3.visible = false
	loss1.visible = false; loss2.visible = false; loss3.visible = false

	var win_counters: Array = [win1, win2, win3]
	var loss_counters: Array = [loss1, loss2, loss3]

	# Show static counters for all previously completed rounds
	for i in range(round_results.size() - 1):
		if round_results[i] == "win":
			win_counters[i].visible = true
		else:
			loss_counters[i].visible = true

	_load_data()
	_update_sprites()

	SoundManagerScript.stop_bgm()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start)

	var fade_in := create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.5)
	await fade_in.finished

	_click_enabled = true

	# Make the current round's counter visible and prepare its spin pivot
	var current_counter: TextureRect = win_counters[current_round - 1] if battle_won else loss_counters[current_round - 1]
	current_counter.visible = true
	current_counter.pivot_offset = current_counter.size / 2.0

	var active_label: Label = round_win_label if battle_won else round_loss_label

	# All animations fire simultaneously
	var main_tween := create_tween()
	main_tween.set_parallel(true)
	main_tween.set_trans(Tween.TRANS_LINEAR)
	main_tween.tween_property(player_sprite, "position:x", player_sprite.position.x - 100, ANIMATION_DURATION)
	main_tween.tween_property(opponent_sprite, "position:x", opponent_sprite.position.x + 100, ANIMATION_DURATION)
	main_tween.tween_property(active_label, "position:y", active_label.position.y - 50, ANIMATION_DURATION)

	# Spin tween runs its own sequential squish cycles (same feel as gift coin flip)
	var spin_tween := create_tween()
	for dur in SPIN_DURATIONS:
		spin_tween.tween_property(current_counter, "scale:x", 0.0, dur)
		spin_tween.tween_property(current_counter, "scale:x", 1.0, dur)

	await main_tween.finished
	await get_tree().create_timer(0.25).timeout
	_do_transition()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	if event is InputEventMouseButton and event.pressed and _click_enabled and not _transitioning:
		_do_transition()

func _do_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	_click_enabled = false
	if _decided:
		GameState.clear_match_series()
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn")
	else:
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn")

func _load_data() -> void:
	# GameDataManager is already populated by Match_Start_Intro (including
	# the All_NPC_Constant_Data merge), so reuse it rather than re-loading.
	opponent_data = GameDataManager.opponent_data
	player_data   = GameDataManager.player_data

func _normalize_sprite_scale(sprite: Sprite2D, tex: Texture2D) -> void:
	const TARGET := 480.0
	var sz := tex.get_size()
	sprite.scale = Vector2.ONE * minf(TARGET / sz.x, TARGET / sz.y)

func _update_sprites() -> void:
	if opponent_data.has("sprite"):
		var path: String = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + opponent_data["sprite"].to_lower() + ".png"
		var tex: Texture2D = load(path)
		if tex:
			opponent_sprite.texture = tex
			_normalize_sprite_scale(opponent_sprite, tex)

	if player_data.has("sprite"):
		var path: String = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + player_data["sprite"].to_lower() + ".png"
		var tex: Texture2D = load(path)
		if tex:
			player_sprite.texture = tex
			player_sprite.flip_h = true
			_normalize_sprite_scale(player_sprite, tex)
