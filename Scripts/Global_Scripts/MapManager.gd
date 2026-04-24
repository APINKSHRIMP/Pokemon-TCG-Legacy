extends Node

# ============================================================
# MAP MANAGER - Autoload singleton
# ============================================================

var opponent_scene   = preload("res://Scenes/Objects/Opponent_Object_Scene.tscn")
var npc_scene        = preload("res://Scenes/Objects/NPC_Object_Scene.tscn")
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
# INITIALISE
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
	_load_and_spawn_opponents(json_path)
	_load_and_spawn_npcs(npc_json_path)

	_player.interact_pressed.connect(_on_player_interact)
	_player.npc_interact_pressed.connect(_on_player_npc_interact)

	if GameState.returning_from_battle:
		_handle_battle_return()

# ============================================================
# OPPONENT SPAWNING
# ============================================================

func _load_and_spawn_opponents(json_path: String):
	if json_path == "":
		return
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open JSON: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for entry in data["opponents"]:
		if not entry.has("position"):
			push_error("MapManager: Opponent missing position: " + entry.get("name", "unknown"))
			continue
		var opp = opponent_scene.instantiate()
		opp.opponent_name    = entry["name"]
		opp.sprite           = entry["sprite"]
		opp.music            = entry["music"]
		opp.deck             = entry["deck"]
		opp.meet_text        = entry["meet_text"]
		opp.repeat_text      = entry["repeat_text"]
		opp.first_win_text   = entry["first_win_text"]
		opp.rematch_win_text = entry["rematch_win_text"]
		opp.loss_text        = entry["loss_text"]
		opp.coin_reward      = entry["coin_reward"]
		opp.cash_reward      = entry["cash_reward"]
		opp.position         = Vector2(entry["position"]["x"], entry["position"]["y"])
		opp.movement_pattern = entry.get("pattern", "idle_random")
		opp.patrol_distance  = entry.get("patrol_distance", 100.0)
		opp.patrol_speed     = entry.get("patrol_speed", 60.0)
		opp.patrol_axis      = entry.get("patrol_axis", "horizontal")
		opp.wander_radius    = entry.get("wander_radius", 200.0)
		_opponents_container.add_child(opp)

# ============================================================
# NPC SPAWNING
# ============================================================

func _load_and_spawn_npcs(json_path: String):
	if json_path == "":
		return
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open NPC JSON: " + json_path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for entry in data["npcs"]:
		if not entry.has("position"):
			push_error("MapManager: NPC missing position: " + entry.get("name", "unknown"))
			continue

		# Use shopkeeper scene when npc_type == "shop", NPC scene for everything else
		var is_shop = entry.get("npc_type", "") == "shop"
		var npc = shopkeeper_scene.instantiate() if is_shop else npc_scene.instantiate()

		npc.npc_name         = entry["name"]
		npc.sprite           = entry["sprite"]
		npc.npc_type         = entry.get("npc_type", "text_only")
		npc.meet_text        = entry.get("meet_text", "")
		npc.repeat_text      = entry.get("repeat_text", "")
		npc.gift_type        = entry.get("gift_type", "")
		npc.gift_value       = entry.get("gift_value", "")
		npc.position         = Vector2(entry["position"]["x"], entry["position"]["y"])
		npc.movement_pattern = entry.get("pattern", "idle_down")
		npc.patrol_distance  = entry.get("patrol_distance", 100.0)
		npc.patrol_speed     = entry.get("patrol_speed", 60.0)
		npc.patrol_axis      = entry.get("patrol_axis", "horizontal")
		npc.wander_radius    = entry.get("wander_radius", 200.0)

		# Shop-specific fields
		if is_shop and npc.has_method("on_interact"):
			npc.shop_id = entry.get("shop_id", npc.npc_name.to_lower().replace(" ", "_"))

		_opponents_container.add_child(npc)
		print("Spawned NPC: ", npc.npc_name, " at ", npc.position)

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
	no_button.visible  = true
	ok_button.visible  = false
	message_panel.visible = true
	_player.can_move = false

func _show_message_with_ok(text: String):
	message_label.text = text
	yes_button.visible = false
	no_button.visible  = false
	ok_button.visible  = true
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
# INTERACTION — OPPONENTS
# ============================================================

func _on_player_interact(opponent: Node):
	if message_panel.visible:
		return
	current_opponent = opponent
	opponent.pause_and_face(_player.position)
	# Keep bubble visible during messagebox; refresh in case state changed
	opponent.refresh_bubble()
	_show_message_with_choices(opponent.get_greeting_text())

func _on_yes_pressed():
	# Shop NPC — delegate to npc.on_interact() which returns false when ready to open shop
	if current_npc != null and current_npc.npc_type == "shop":
		_hide_message()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn")
		return

	# Opponent battle
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
	if current_opponent != null:
		current_opponent.refresh_bubble()
	if current_npc != null:
		current_npc.refresh_bubble()
	_hide_message()

func _on_ok_pressed():
	if current_npc != null:
		current_npc.refresh_bubble()
	_hide_message()

# ============================================================
# INTERACTION — NPCs
# ============================================================

func _on_player_npc_interact(npc: Node):
	if message_panel.visible:
		return
	current_npc = npc

	if npc.npc_type == "shop":
		npc.animated_sprite.play("idle_down")
	else:
		npc.pause_and_face(_player.position)

	# Shop NPC: delegate entirely to its own state machine
	if npc.npc_type == "shop" and npc.has_method("on_interact"):
		npc.refresh_bubble()
		var handled = npc.on_interact()
		if handled:
			return
		# on_interact() returned false → open pack purchase
		_show_message_with_choices(npc.meet_text)
		return

	# Gift NPC: detected by gift_type field being non-empty
	if npc.is_gift_npc():
		if npc.has_gift_been_given():
			npc.refresh_bubble()
			_show_message_with_ok(npc.repeat_text if npc.repeat_text != "" else npc.meet_text)
		else:
			_give_gift(npc)
			npc.mark_as_met()
			npc.refresh_bubble()   # flips to old_talk now that gift is given
			_show_message_with_ok(npc.meet_text)
		return

	# Text-only NPC — mark as met BEFORE showing text so icon flips immediately
	var use_repeat = npc.has_been_met() and npc.repeat_text != ""
	npc.mark_as_met()
	npc.refresh_bubble()
	if use_repeat:
		_show_message_with_ok(npc.repeat_text)
	else:
		_show_message_with_ok(npc.meet_text)

# ============================================================
# GIFT GIVING
# ============================================================

func _give_gift(npc: Node):
	match npc.gift_type:
		"card":
			GameState.give_cards(npc.gift_value)
		"coin":
			GameState.add_coin_to_collection(npc.gift_value)
		"cash":
			GameState.add_cash(int(npc.gift_value))
		"energy_style":
			if not GameState.progress.has("energy_styles"):
				GameState.progress["energy_styles"] = []
			if not (npc.gift_value in GameState.progress["energy_styles"]):
				GameState.progress["energy_styles"].append(npc.gift_value)
			GameState.save_progress()
		"costume":
			GameState.add_costume_to_collection(npc.gift_value)
		"available_pack":
			if not GameState.progress.has("packs_unlocked"):
				GameState.progress["packs_unlocked"] = []
			if not (npc.gift_value in GameState.progress["packs_unlocked"]):
				GameState.progress["packs_unlocked"].append(npc.gift_value)
			GameState.save_progress()
		"pack_of_cards":
			push_warning("MapManager: pack_of_cards gift not yet implemented for: " + npc.gift_value)
		_:
			push_error("MapManager: Unknown gift_type '" + npc.gift_type + "' on NPC: " + npc.npc_name)
	GameState.mark_gift_received(npc.npc_name)

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
