extends Node2D

@onready var black_splash: TextureRect = $black_splash
@onready var white_splash: TextureRect = $white_splash
@onready var black_text: TextureRect = $black_text
@onready var white_text: TextureRect = $white_text

var audio_player := AudioStreamPlayer.new()

const GROW_DURATION := 5 # 7.0
const BLACK_FADE_DURATION := 5 # 7
const SCENE_FADE_DURATION := 2 # 3

# Where to send the player after the splash. The actual destination is the
# scene they were last in (resumed from save). If no save exists, falls
# back to GameState.DEFAULT_START_SCENE.
var _animation_done: bool = false

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

	# Kick off threaded loading of every cached scene as early as
	# possible — this runs in parallel with the splash animation so
	# the scenes are ready by the time the animation completes.
	SceneCache.preload_all_async()

	_run_sequence()


func _run_sequence() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	# Scale both splashes from 1.0 to 1.2 over 5.5 seconds
	tween.tween_property(black_splash, "scale", Vector2(1.8, 1.8), GROW_DURATION)
	tween.tween_property(white_splash, "scale", Vector2(1.8, 1.8), GROW_DURATION)

	# After all parallel tweens finish, trigger scene fade
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
	tween.tween_callback(_change_to_saved_scene)


func _change_to_saved_scene() -> void:
	# If preloading is still finishing up, wait for it. The fade has
	# already completed so the screen is black — the player won't see
	# the wait. In practice this is almost always already finished by
	# the time the splash animation ends.
	while not SceneCache.is_all_loaded():
		await get_tree().process_frame

	# Determine where to send the player
	var target_scene: String = GameState.get_saved_scene_path()

	# If the player has a saved position, route through menu_return_state
	# so the destination scene's existing _ready logic picks it up
	# (every map checks menu_return_state first).
	if GameState.has_saved_player_position():
		var pos: Vector2 = GameState.get_saved_player_position()
		var direction: String = GameState.get_player_direction()
		GameState.save_menu_return_state(target_scene, pos, direction)

	SceneCache.change_scene(target_scene)
