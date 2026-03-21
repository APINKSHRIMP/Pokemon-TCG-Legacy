extends Node2D

@onready var black_splash: TextureRect = $black_splash
@onready var white_splash: TextureRect = $white_splash
@onready var black_text: TextureRect = $black_text
@onready var white_text: TextureRect = $white_text

var audio_player := AudioStreamPlayer.new()

const GROW_DURATION := 0.1 # 7.0
const BLACK_FADE_DURATION := 0.1 # 7
const SCENE_FADE_DURATION := 0.1 # 3
const NEXT_SCENE := "res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

func _ready() -> void:
	# Set pivot to centre of each TextureRect so scaling grows outward from middle
	black_splash.pivot_offset = black_splash.size / 2
	white_splash.pivot_offset = white_splash.size / 2
	
	black_text.pivot_offset = black_text.size / 2
	white_text.pivot_offset = white_text.size / 2

	# Audio
	var audio_path = "res://Audio/SFX/fatsynth.ogg"
	var audio_stream = load(audio_path)
	if audio_stream:
		audio_player.stream = audio_stream
		add_child(audio_player)
		audio_player.play()
	else:
		print("Could not load audio: ", audio_path)

	_run_sequence()


func _run_sequence() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	# Scale both splashes from 1.0 to 1.2 over 5.5 seconds
	tween.tween_property(black_splash, "scale", Vector2(1.8, 1.8), GROW_DURATION)
	tween.tween_property(white_splash, "scale", Vector2(1.8, 1.8), GROW_DURATION)

	# Fade black splash alpha to 0 over 3.5 seconds
	#tween.tween_property(black_splash, "modulate:a", 0.0, BLACK_FADE_DURATION)
	
	# Scale both splashes from 1.0 to 1.2 over 5.5 seconds
	#tween.tween_property(black_text, "scale", Vector2(1.1, 1.1), GROW_DURATION)
	#tween.tween_property(white_text, "scale", Vector2(1.1, 1.1), GROW_DURATION)

	# Fade black splash alpha to 0 over 3.5 seconds
	#tween.tween_property(white_text, "modulate:a", 0.0, BLACK_FADE_DURATION)
	
	# After all parallel tweens finish (5.5s), trigger scene fade
	tween.chain().tween_callback(_fade_to_next_scene)


func _fade_to_next_scene() -> void:
	# Create a CanvasLayer to ensure the overlay renders on top
	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)
	
	# Create a ColorRect on the canvas layer
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 1, SCENE_FADE_DURATION)
	tween.tween_callback(func(): get_tree().change_scene_to_file(NEXT_SCENE))
