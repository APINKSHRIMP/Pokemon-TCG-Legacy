extends Node

# ============================================================
# MAP MANAGER - Autoload singleton
# Handles opponent spawning, message box UI, and battle flow
# for any world map. Each map calls initialise() in _ready().
# ============================================================

var opponent_scene = preload("res://Scenes/Objects/Opponent_Object_Scene.tscn")

var _player: CharacterBody2D
var _opponents_container: Node2D
var _ui_layer: CanvasLayer
var _map_scene_path: String
var _json_path: String

var current_opponent: Node = null

var message_panel: PanelContainer
var message_label: Label
var yes_button: Button
var no_button: Button
var ok_button: Button

# ============================================================
# Called by each map in its _ready()
# ============================================================
func initialise(
	player: CharacterBody2D,
	opponents_container: Node2D,
	ui_layer: CanvasLayer,
	json_path: String,
	placements: Array,
	map_scene_path: String
):
	_player = player
	_opponents_container = opponents_container
	_ui_layer = ui_layer
	_map_scene_path = map_scene_path
	_json_path = json_path
		
	_build_message_box()
	_load_and_spawn_opponents(json_path, placements)

	_player.interact_pressed.connect(_on_player_interact)

	if GameState.returning_from_battle:
		_handle_battle_return()

# ============================================================
# OPPONENT SPAWNING
# ============================================================

func _load_and_spawn_opponents(json_path: String, placements: Array):
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open JSON: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for placement in placements:
		var opp_data = _find_opponent_in_json(data, placement["name"])
		if opp_data == null:
			push_error("MapManager: Opponent not found in JSON: " + placement["name"])
			continue

		var opp = opponent_scene.instantiate()
		opp.opponent_name    = opp_data["name"]
		opp.overworld_sprite = opp_data["overworld_sprite"]
		opp.music            = opp_data["music"]
		opp.deck             = opp_data["deck"]
		opp.meet_text        = opp_data["meet_text"]
		opp.rematch_text     = opp_data["rematch_text"]
		opp.first_win_text   = opp_data["first_win_text"]
		opp.rematch_win_text = opp_data["rematch_win_text"]
		opp.loss_text        = opp_data["loss_text"]
		opp.coin_reward      = opp_data["coin_reward"]
		opp.cash_reward      = opp_data["cash_reward"]

		opp.position         = placement["position"]
		opp.movement_pattern = placement.get("pattern", "idle_random")
		opp.patrol_distance  = placement.get("patrol_distance", 100.0)
		opp.patrol_speed     = placement.get("patrol_speed", 60.0)
		opp.patrol_axis      = placement.get("patrol_axis", "horizontal")

		_opponents_container.add_child(opp)

func _find_opponent_in_json(data: Dictionary, opp_name: String):
	for opp in data["opponents"]:
		if opp["name"] == opp_name:
			return opp
	return null

# ============================================================
# MESSAGE BOX
# ============================================================

func _build_message_box():
	# Remove old panel if reinitialising on a new map
	if message_panel != null and is_instance_valid(message_panel):
		message_panel.queue_free()

	message_panel = PanelContainer.new()
	message_panel.visible = false
	message_panel.offset_left   = 200
	message_panel.offset_top    = 800
	message_panel.offset_right  = 1720
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
	message_label.text = ""
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

	ok_button = Button.new()
	ok_button.text = "  OK  "
	ok_button.add_theme_font_size_override("font_size", 24)
	ok_button.pressed.connect(_on_ok_pressed)
	ok_button.visible = false
	button_container.add_child(ok_button)

	_ui_layer.add_child(message_panel)

func _show_message_with_choices(text: String):
	message_label.text = text
	yes_button.visible = true
	no_button.visible = false  # corrected: was showing both
	no_button.visible = true
	ok_button.visible = false
	message_panel.visible = true
	_player.can_move = false

func _show_message_with_ok(text: String):
	message_label.text = text
	yes_button.visible = false
	no_button.visible = false
	ok_button.visible = true
	message_panel.visible = true
	_player.can_move = false

func _hide_message():
	message_panel.visible = false
	_player.can_move = true
	if current_opponent != null:
		current_opponent.resume_movement()
	current_opponent = null

# ============================================================
# INTERACTION FLOW
# ============================================================

func _on_player_interact(opponent: Node):
	if message_panel.visible:
		return
	current_opponent = opponent
	opponent.pause_and_face(_player.position)
	_show_message_with_choices(opponent.get_greeting_text())

func _on_yes_pressed():
	if current_opponent == null:
		return
	print("DEBUG opponent name: ", current_opponent.opponent_name)
	print("DEBUG opponent deck: ", current_opponent.deck)
	print("DEBUG json path: ", _json_path)
	GameState.current_opponent_name = current_opponent.opponent_name
	GameState.current_opponent_deck = current_opponent.deck
	GameState.current_opponent_json_path = _json_path
	GameState.player_position           = _player.position
	GameState.returning_from_battle     = false
	GameState.return_map_scene_path     = _map_scene_path
	
	_hide_message()
	SoundManagerScript.stop_bgm()

	var overlay = ColorRect.new()
	overlay.color   = Color(0, 0, 0, 0)
	overlay.size    = Vector2(1920, 1080)
	overlay.z_index = 100
	# Add to the map scene root, not MapManager (which is a plain Node)
	get_tree().current_scene.add_child(overlay)

	var tween = get_tree().current_scene.create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.5)
	await tween.finished
	get_tree().change_scene_to_file("res://Scenes/Main_Match_Gameplay_Scenes/Match_Start_Intro_Scene.tscn")

func _on_no_pressed():
	_hide_message()

func _on_ok_pressed():
	_hide_message()

# ============================================================
# POST-BATTLE
# ============================================================

func _handle_battle_return():
	var fought_name = GameState.current_opponent_name
	var fought_opponent = null

	for opp in _opponents_container.get_children():
		if opp.opponent_name == fought_name:
			fought_opponent = opp
			break

	if fought_opponent == null:
		GameState.returning_from_battle = false
		return

	current_opponent = fought_opponent
	_show_message_with_ok(fought_opponent.get_result_text(GameState.battle_result == "win"))
	GameState.returning_from_battle = false
	GameState.battle_result = ""
