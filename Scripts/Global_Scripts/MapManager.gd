extends Node

# ============================================================
# MAP MANAGER - Autoload singleton
# Handles opponent/NPC spawning, message box UI, and battle flow
# for any world map. Each map calls initialise() in _ready().
# ============================================================

var opponent_scene = preload("res://Scenes/Objects/Opponent_Object_Scene.tscn")
var npc_scene = preload("res://Scenes/Objects/NPC_Object_Scene.tscn")
var shopkeeper_scene = preload("res://Scenes/Objects/Shopkeeper_Object_Scene.tscn")

var _player: CharacterBody2D
var _opponents_container: Node2D
var _ui_layer: CanvasLayer
var _map_scene_path: String
var _json_path: String

var current_opponent: Node = null
var current_npc: Node = null

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
	map_scene_path: String,
	npc_json_path: String = "",
	npc_placements: Array = []
):
	_player = player
	_opponents_container = opponents_container
	_ui_layer = ui_layer
	_map_scene_path = map_scene_path
	_json_path = json_path

	_build_message_box()
	_load_and_spawn_opponents(json_path, placements)

	if npc_json_path != "" and npc_placements.size() > 0:
		_load_and_spawn_npcs(npc_json_path, npc_placements)

	_player.interact_pressed.connect(_on_player_interact)
	_player.npc_interact_pressed.connect(_on_player_npc_interact)

	if GameState.returning_from_battle:
		_handle_battle_return()

# ============================================================
# OPPONENT SPAWNING
# ============================================================

func _load_and_spawn_opponents(json_path: String, placements: Array):
	if json_path == "" or placements.is_empty():
		return
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open JSON: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for placement in placements:
		var opp_data = _find_by_name_in_array(data["opponents"], placement["name"])
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

# ============================================================
# NPC SPAWNING
# ============================================================

func _load_and_spawn_npcs(json_path: String, placements: Array):
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open NPC JSON: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for placement in placements:
		var npc_data = _find_by_name_in_array(data["npcs"], placement["name"])
		if npc_data == null:
			push_error("MapManager: NPC not found in JSON: " + placement["name"])
			continue

		var npc_type = npc_data.get("npc_type", "text_only")
		var npc = shopkeeper_scene.instantiate() if npc_type == "shop" else npc_scene.instantiate()

		npc.npc_name         = npc_data["name"]
		npc.overworld_sprite = npc_data["overworld_sprite"]
		npc.npc_type         = npc_type
		npc.text             = npc_data.get("text", "")
		npc.gift_type        = npc_data.get("gift_type", "")
		npc.gift_value       = npc_data.get("gift_value", "")
		npc.position         = placement["position"]
		npc.movement_pattern = placement.get("pattern", "idle_random")
		npc.patrol_distance  = placement.get("patrol_distance", 100.0)
		npc.patrol_speed     = placement.get("patrol_speed", 60.0)
		npc.patrol_axis      = placement.get("patrol_axis", "horizontal")

		_opponents_container.add_child(npc)
		
		print("NPC added to: ", _opponents_container, " in tree: ", _opponents_container.is_inside_tree())
		print("NPC in tree: ", npc.is_inside_tree(), " visible: ", npc.visible)
		
		print("Spawned NPC: ", npc.npc_name, " at ", npc.position, " parent: ", npc.get_parent())
		

func _find_by_name_in_array(arr: Array, search_name: String):
	for item in arr:
		if item["name"] == search_name:
			return item
	return null

# ============================================================
# MESSAGE BOX
# ============================================================

func _build_message_box():
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
	if current_npc != null:
		current_npc.resume_movement()
	current_opponent = null
	current_npc = null

func handle_message_spacebar():
	if not message_panel.visible:
		return
	if ok_button.visible:
		_on_ok_pressed()
	elif yes_button.visible:
		_on_yes_pressed()

# ============================================================
# INTERACTION FLOW - OPPONENTS
# ============================================================

func _on_player_interact(opponent: Node):
	if message_panel.visible:
		return
	current_opponent = opponent
	opponent.pause_and_face(_player.position)
	_show_message_with_choices(opponent.get_greeting_text())

func _on_yes_pressed():
	# Shop flow
	if current_npc != null and current_npc.npc_type == "shop":
		_hide_message()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn")
		return

	# Opponent battle flow
	if current_opponent != null:
		GameState.current_opponent_name      = current_opponent.opponent_name
		GameState.current_opponent_deck      = current_opponent.deck
		GameState.current_opponent_json_path = _json_path
		GameState.player_position            = _player.position
		GameState.returning_from_battle      = false
		GameState.return_map_scene_path      = _map_scene_path

		_hide_message()
		SoundManagerScript.stop_bgm()

		var overlay = ColorRect.new()
		overlay.color   = Color(0, 0, 0, 0)
		overlay.size    = Vector2(1920, 1080)
		overlay.z_index = 100
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
# INTERACTION FLOW - NPCs
# ============================================================

func _on_player_npc_interact(npc: Node):
	if message_panel.visible:
		return
	current_npc = npc
	if npc.npc_type == "shop":
		npc.animated_sprite.play("idle_down")
	else:
		npc.pause_and_face(_player.position)

	match npc.npc_type:
		"text_only":
			_show_message_with_ok(npc.text)
		"gift":
			if npc.has_gift_been_given():
				_show_message_with_ok(npc.text)
			else:
				_give_gift(npc)
				_show_message_with_ok(npc.text)
		"shop":
			_show_message_with_choices(npc.text)

# ============================================================
# GIFT GIVING
# ============================================================

func _give_gift(npc: Node):
	match npc.gift_type:
		"card":
			_give_card(npc.gift_value)
		"coin":
			_give_coin(npc.gift_value)
		"cash":
			_give_cash(int(npc.gift_value))
		"energy_style":
			_give_energy_style(npc.gift_value)
		"costume":
			_give_costume(npc.gift_value)
		"available_pack":
			_give_available_pack(npc.gift_value)
		"pack_of_cards":
			_give_pack_of_cards(npc.gift_value)

	GameState.mark_gift_received(npc.npc_name)

func _give_card(card_id: String):
	var parts = card_id.split("-")
	if parts.size() < 2:
		push_error("MapManager: Invalid card_id format: " + card_id)
		return
	var set_name = parts[0]
	var json_path = "res://Player_Data/Player_Owned_Cards/" + set_name + "_player_owned_cards.json"

	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open card file: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	var found = false
	for entry in data["owned_cards"]:
		if entry["card_id"] == card_id:
			entry["owned"] = entry["owned"] + 1
			found = true
			break

	if not found:
		data["owned_cards"].append({"card_id": card_id, "owned": 1})

	var write_file = FileAccess.open(json_path, FileAccess.WRITE)
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

func _give_coin(coin_filename: String):
	GameState.add_coin_to_collection(coin_filename)

func _give_cash(amount: int):
	GameState.add_cash(amount)

func _give_energy_style(style_name: String):
	if not GameState.progress.has("energy_styles"):
		GameState.progress["energy_styles"] = []
	if not (style_name in GameState.progress["energy_styles"]):
		GameState.progress["energy_styles"].append(style_name)
	GameState.save_progress()

func _give_costume(costume_filename: String):
	GameState.add_costume_to_collection(costume_filename)

func _give_available_pack(pack_name: String):
	if not GameState.progress.has("packs_unlocked"):
		GameState.progress["packs_unlocked"] = []
	if not (pack_name in GameState.progress["packs_unlocked"]):
		GameState.progress["packs_unlocked"].append(pack_name)
	GameState.save_progress()

func _give_pack_of_cards(set_name: String):
	push_warning("MapManager: pack_of_cards gift not yet implemented for set: " + set_name)

# ============================================================
# POST-BATTLE
# ============================================================

func _handle_battle_return():
	var fought_name = GameState.current_opponent_name
	var fought_opponent = null

	for opp in _opponents_container.get_children():
		if opp.is_in_group("opponents") and opp.opponent_name == fought_name:
			fought_opponent = opp
			break

	if fought_opponent == null:
		GameState.returning_from_battle = false
		return

	current_opponent = fought_opponent
	_show_message_with_ok(fought_opponent.get_result_text(GameState.battle_result == "win"))
	GameState.returning_from_battle = false
	GameState.battle_result = ""
