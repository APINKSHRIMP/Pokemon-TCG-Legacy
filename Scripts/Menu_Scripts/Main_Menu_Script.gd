extends Node

@onready var audio_player = AudioStreamPlayer.new()

# Map each TextureRect node name to its scene file path
const SCENE_MAP = {
	"deck_mode_background": "res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn",
	"map_mode_background": "res://Scenes/Map_Scenes/Celeste_Harbour.tscn",
	"player_mode_background": "res://Scenes/Main_Menu_Scenes/Trainer_Card_Scene.tscn",
	"options_mode_background": "res://Scenes/Main_Menu_Scenes/Options_Scene.tscn",
	"coin_case_mode_background": "res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn",
}

# Stores active tweens per node so we can kill them cleanly
var tweens: Dictionary = {}


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _ready() -> void:
	add_child(audio_player)

	var audio_stream = load("res://Audio/BGM/main_menu_music.ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	audio_player.stream.loop = true
	audio_player.play()

	# Check if deck mode should be locked
	var deck_locked = not GameState.progress.get("player_collected_starter_box", false)

	# Wait one frame so Godot finishes layout and rect.size is correct
	await get_tree().process_frame

	# Wire up all mode images
	for node_name in SCENE_MAP.keys():
		var rect = get_node(node_name) as TextureRect
		if rect:
			# Set pivot to centre so scaling grows from the middle, not top-left
			rect.pivot_offset = rect.size / 2.0

			if node_name == "deck_mode_background" and deck_locked:
				rect.modulate = Color(0.4, 0.4, 0.4, 1.0)
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				rect.mouse_entered.connect(_on_mode_hover.bind(rect, true))
				rect.mouse_exited.connect(_on_mode_hover.bind(rect, false))
				rect.gui_input.connect(_on_mode_clicked.bind(node_name))

	# Grey out the deck label too if locked
	if deck_locked:
		var deck_label = get_node("deck_mode_label") as Label
		if deck_label:
			deck_label.modulate = Color(0.4, 0.4, 0.4, 1.0)

	# Make all labels pass mouse events through so they don't block hover/click
	var label_names = [
		"deck_mode_label",
		"map_mode_label",
		"options_mode_label",
		"player_mode_label",
		"coin_case_label"
	]
	for label_name in label_names:
		var label = get_node(label_name) as Label
		if label:
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mode_hover(rect: TextureRect, hovered: bool) -> void:
	var node_name = rect.name

	# Kill any running tween for this rect before starting a new one
	if tweens.has(node_name) and tweens[node_name]:
		tweens[node_name].kill()

	if hovered:
		var tween = create_tween()
		tween.set_loops()
		tweens[node_name] = tween

		tween.tween_property(rect, "modulate", Color.WHITE * 1.2, 0.2)
		tween.parallel().tween_property(rect, "scale", Vector2(1.02, 1.02), 0.2)
		tween.tween_property(rect, "modulate", Color.WHITE * 1.0, 0.3)
		tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)
	else:
		tweens.erase(node_name)
		rect.modulate = Color.WHITE
		rect.scale = Vector2(1.0, 1.0)


func _on_mode_clicked(event: InputEvent, node_name: String) -> void:
	# Guard: only fire on a left mouse button press, not release or other events
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
		get_tree().change_scene_to_file(SCENE_MAP[node_name])
