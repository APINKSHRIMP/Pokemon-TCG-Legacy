extends Node2D

# ============================================================
# WORLD MAP CONTROLLER
# ============================================================

# --- Node references (set up in editor) ---
@onready var player_sprite: AnimatedSprite2D = $PlayerSprite
@onready var ui_layer: CanvasLayer = $UILAYER

# --- Audio ---
var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

# --- State ---
var buttons_locked: bool = false
var pending_scene: String = ""

# --- Message box nodes (built in code, like Shallow_Beach) ---
var message_panel: PanelContainer
var message_label: Label
var yes_button: Button
var no_button: Button

# --- Screen center (player starts here) ---
var screen_center: Vector2

# ============================================================
# INIT
# ============================================================

func _ready() -> void:
	screen_center = get_viewport().get_visible_rect().size / 2.0
	player_sprite.position = screen_center

	_setup_audio()
	_load_player_sprite()
	_build_message_box()
	_connect_buttons()

# ============================================================
# AUDIO
# ============================================================

func _setup_audio() -> void:
	# BGM — looping background music
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	var bgm = load("res://Audio/BGM/world_map_music.ogg") as AudioStream
	bgm_player.stream = bgm
	bgm_player.bus = "Master"
	bgm_player.stream.loop = true
	bgm_player.play()

	# SFX — one-shot sound effects
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)

func _play_sfx(path: String) -> void:
	var sfx = load(path) as AudioStream
	sfx_player.stream = sfx
	sfx_player.play()

# ============================================================
# PLAYER SPRITE
# ============================================================

func _load_player_sprite() -> void:
	var file = FileAccess.open("res://Player_Data/Player_Current_Data.json", FileAccess.READ)
	var player_data = JSON.parse_string(file.get_as_text())
	file.close()

	var sprite_name = player_data["overworld_sprite"]
	player_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite_name)
	player_sprite.scale = Vector2(2.5, 2.5)
	player_sprite.play("walk_down")

# ============================================================
# BUTTON CONNECTIONS
# ============================================================

func _connect_buttons() -> void:
	for child in get_children():
		if child is Button:
			child.pressed.connect(_on_location_button_pressed.bind(child))

# ============================================================
# MOVEMENT
# ============================================================

func _on_location_button_pressed(button: Button) -> void:
	if buttons_locked:
		return

	buttons_locked = true

	# Target is the center of the button, 30px above it
	var button_center = button.position + button.size / 2.0
	var target_pos = Vector2(button_center.x, button_center.y - 30.0)

	_walk_player_to(target_pos, button)

func _calc_travel_duration(from: Vector2, to: Vector2) -> float:
	# Duration scales linearly with distance:
	# 500px = 1.0s, 1000px = 2.0s, 1500px = 3.0s, 2000px = 4.0s
	# Formula: duration = distance / 500.0
	# Clamped between 0.3s (very close) and 6.0s (very far)
	var distance = from.distance_to(to)
	return clampf(distance / 500.0, 0.3, 6.0)

func _walk_player_to(target: Vector2, button: Button) -> void:
	var direction = (target - player_sprite.position).normalized()

	if abs(direction.x) > abs(direction.y):
		player_sprite.play("walk_right" if direction.x > 0 else "walk_left")
	else:
		player_sprite.play("walk_down" if direction.y > 0 else "walk_up")

	var duration = _calc_travel_duration(player_sprite.position, target)

	var tween = create_tween()
	tween.tween_property(player_sprite, "position", target, duration)\
		.set_trans(Tween.TRANS_LINEAR)\
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_player_arrived.bind(button))

func _on_player_arrived(button: Button) -> void:
	player_sprite.play("idle_down")

	var raw = button.name.replace("_button", "")
	var location_name = raw.replace("_", " ")

	_show_travel_prompt("Travel to " + location_name + "?", button)

# ============================================================
# MESSAGE BOX
# ============================================================

func _build_message_box() -> void:
	message_panel = PanelContainer.new()
	message_panel.visible = false
	message_panel.offset_left = 200
	message_panel.offset_top = 800
	message_panel.offset_right = 1720
	message_panel.offset_bottom = 1020

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.95)
	style.border_color = Color(0.8, 0.8, 1.0, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	message_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	message_panel.add_child(vbox)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(message_label)

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 40)
	vbox.add_child(button_container)

	yes_button = Button.new()
	yes_button.text = "  Yes  "
	yes_button.add_theme_font_size_override("font_size", 24)
	yes_button.pressed.connect(_on_yes_pressed)
	button_container.add_child(yes_button)

	no_button = Button.new()
	no_button.text = "  No  "
	no_button.add_theme_font_size_override("font_size", 24)
	no_button.pressed.connect(_on_no_pressed)
	button_container.add_child(no_button)

	ui_layer.add_child(message_panel)

func _show_travel_prompt(text: String, button: Button) -> void:
	var raw = button.name.replace("_button", "")
	pending_scene = "res://Scenes/Map_Scenes/Map_Areas/" + raw + "_Scene.tscn"

	message_label.text = text
	message_panel.visible = true

func _on_no_pressed() -> void:
	message_panel.visible = false
	pending_scene = ""
	# Player stays where they are — just unlock buttons and resume walk_down idle loop
	player_sprite.play("walk_down")
	buttons_locked = false

func _on_yes_pressed() -> void:
	message_panel.visible = false
	buttons_locked = true

	_play_sfx("res://Audio/SFX/enter_location_sound.ogg")

	# Full-screen black overlay fade
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)

	var tween = create_tween()
	tween.tween_property(overlay, "color", Color(0, 0, 0, 1), 0.8)\
		.set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(pending_scene)
	)

# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
