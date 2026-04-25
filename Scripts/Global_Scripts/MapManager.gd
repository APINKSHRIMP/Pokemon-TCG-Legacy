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
# GIFT DISPLAY STATE
# ============================================================

# When non-empty, the next OK press triggers the gift card/coin reveal
# instead of dismissing the message panel. Keys: text, image_paths, kind.
var _pending_gift_display: Dictionary = {}

# Container holding the displayed card/coin TextureRects during gift reveal
var _gift_display_container: Control = null

# ── Card / set name lookup caches (populated lazily) ─────────────
var _set_name_cache: Dictionary = {}
var _card_name_cache: Dictionary = {}
var _loaded_card_sets: Dictionary = {}

# Set IDs that are promo sets — these use "<set_name> <card_name>"
# instead of the usual "<set_name> set <card_name>"
const PROMO_SET_IDS := ["basep", "np"]

# Card display dimensions copied from the main gameplay script's
# show_enlarged_array_selection_mode (card_scales dict).
const GIFT_CARD_SIZES := {
	1: Vector2(400, 550),
	2: Vector2(400, 550),
	3: Vector2(375, 515),
	4: Vector2(350, 481),
}

const GIFT_COIN_SIZE := Vector2(250, 250)
const GIFT_ITEM_SEPARATION := 20.0

# Vertical centre point on screen for the displayed gift items
const GIFT_DISPLAY_CENTER_Y := 400.0

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
		opp.prize_cards      = entry.get("prize_cards", 6)
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
	_clear_gift_display()
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
	# If a gift display is queued, show the card/coin reveal instead of dismissing
	if not _pending_gift_display.is_empty():
		var d = _pending_gift_display
		_pending_gift_display = {}
		_show_gift_display(d["text"], d["image_paths"], d["kind"])
		return

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
			_prepare_gift_display(npc.gift_type, npc.gift_value)
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
# GIFT DISPLAY (image(s) + name shown after gift dialogue)
# ============================================================

# Builds the pending gift display data based on the gift type.
# Only "card" and "coin" trigger a visual reveal; other types are silent.
func _prepare_gift_display(gift_type: String, gift_value: String) -> void:
	_pending_gift_display = {}

	match gift_type:
		"coin":
			# Coins are always single-value
			_pending_gift_display = {
				"text": "You received the " + _format_coin_name(gift_value),
				"image_paths": ["res://Image_Assets/Coins/" + gift_value + ".png"],
				"kind": "coin",
			}
		"card":
			# gift_value may be "base1-1" or "base1-1, base2-5, base3-1, base1-3"
			var card_ids: Array = []
			for raw_id in gift_value.split(","):
				var cid: String = raw_id.strip_edges()
				if cid != "":
					card_ids.append(cid)
			if card_ids.is_empty():
				return

			var name_parts: Array = []
			var paths: Array = []
			for cid in card_ids:
				name_parts.append(_get_card_display_name(cid) + " (" + cid + ")")
				paths.append(_get_card_image_path(cid))

			_pending_gift_display = {
				"text": "You received " + ", ".join(name_parts),
				"image_paths": paths,
				"kind": "card",
			}

# Spawns the gift display (cards/coin laid out horizontally on screen) and
# shows the message panel with the formatted text. Press OK to dismiss both.
func _show_gift_display(text: String, image_paths: Array, kind: String) -> void:
	_clear_gift_display()

	# Container parented to the UI layer so it sits above the world
	_gift_display_container = Control.new()
	_gift_display_container.position = Vector2.ZERO
	_gift_display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_gift_display_container)

	# Pick item dimensions based on kind and count
	var item_size: Vector2
	if kind == "coin":
		item_size = GIFT_COIN_SIZE
	else:
		var n_clamp: int = clamp(image_paths.size(), 1, 4)
		item_size = GIFT_CARD_SIZES.get(n_clamp, GIFT_CARD_SIZES[4])

	# Compute layout
	var n: int = image_paths.size()
	var total_width: float = n * item_size.x + (n - 1) * GIFT_ITEM_SEPARATION
	var start_x: float = 960.0 - total_width / 2.0
	var top_y: float = GIFT_DISPLAY_CENTER_Y - item_size.y / 2.0

	# Spawn one TextureRect per image
	for i in range(n):
		var path: String = image_paths[i]
		var tex: Texture2D = _load_card_image_with_fallback(path)
		if tex == null:
			push_warning("MapManager: gift image not found: " + path)
			continue

		var rect = TextureRect.new()
		rect.texture             = tex
		rect.custom_minimum_size = item_size
		rect.size                = item_size
		rect.position            = Vector2(start_x + i * (item_size.x + GIFT_ITEM_SEPARATION), top_y)
		rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_gift_display_container.add_child(rect)

	# Ensure the message panel renders above the gift container
	if message_panel.get_parent() == _ui_layer:
		_ui_layer.move_child(message_panel, _ui_layer.get_child_count() - 1)

	_show_message_with_ok(text)

# Removes the gift display container if it exists.
func _clear_gift_display() -> void:
	if _gift_display_container != null and is_instance_valid(_gift_display_container):
		_gift_display_container.queue_free()
	_gift_display_container = null

# Loads a card image, falling back from /Large/ to /Small/ if the large
# version is missing (failsafe — large images should always exist).
func _load_card_image_with_fallback(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex != null:
			return tex
	if "/Large/" in path:
		var fallback: String = path.replace("/Large/", "/Small/")
		if ResourceLoader.exists(fallback):
			return load(fallback)
	return null

# ============================================================
# COIN NAME FORMATTING
# Title-cases all words and assembles the final coin display name.
#   "coin_arcanine_red"        -> "Red Arcanine Coin"
#   "coin_pikachu_silver_2"    -> "Silver Pikachu Coin 2"
#   "coin_lugia_silver_2"      -> "Silver Lugia Coin 2"
# ============================================================

func _format_coin_name(raw: String) -> String:
	var name_str: String = raw.replace("coin_", "").replace(".png", "")
	var colours = ["red", "blue", "gold", "silver", "green", "black", "purple", "pink", "brown", "yellow", "orange", "white"]
	var parts = name_str.split("_")
	var colour: String = ""
	var trailing_number: String = ""
	var pokemon_parts: Array = []

	for part in parts:
		if part in colours:
			colour = part
		elif part.is_valid_int():
			trailing_number = part
		else:
			pokemon_parts.append(part)

	# Assemble in display order: colour, pokemon, "coin", optional number
	var pieces: Array = []
	if colour != "":
		pieces.append(colour)
	pieces.append_array(pokemon_parts)
	pieces.append("coin")
	if trailing_number != "":
		pieces.append(trailing_number)

	# Title-case every piece
	var result_parts: Array = []
	for p in pieces:
		var s: String = p
		if s.length() > 0:
			result_parts.append(s.substr(0, 1).to_upper() + s.substr(1))
	return " ".join(result_parts)

# ============================================================
# CARD NAME / IMAGE LOOKUP
# Uses the same data sources as the deck builder:
#   set names: res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json
#   card data: res://Card_Set_Data/<set_id>.json
# ============================================================

func _get_card_image_path(card_uid: String) -> String:
	var split = card_uid.split("-")
	if split.size() != 2:
		return ""
	var set_code: String = split[0]
	return "res://Image_Assets/Card_Image_Library/" + set_code + "/Large/" + card_uid + ".png"

func _get_card_display_name(card_uid: String) -> String:
	var split = card_uid.split("-")
	if split.size() != 2:
		return card_uid
	var set_id: String = split[0]

	_ensure_card_set_loaded(set_id)

	var card_name: String = _card_name_cache.get(card_uid, card_uid)
	var set_name: String = _get_set_name(set_id)

	if set_name == "":
		return card_name

	# Promo sets use just "<set_name> <card_name>"; everything else uses
	# "<set_name> set <card_name>"
	if set_id in PROMO_SET_IDS:
		return set_name + " " + card_name
	return set_name + " set " + card_name

func _get_set_name(set_id: String) -> String:
	if _set_name_cache.is_empty():
		_load_set_dictionary()
	return _set_name_cache.get(set_id, "")

func _load_set_dictionary() -> void:
	var path := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapManager: cannot open " + path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("set_list"):
		for entry in data["set_list"]:
			_set_name_cache[entry.get("set_id", "")] = entry.get("set_name", "")

func _ensure_card_set_loaded(set_id: String) -> void:
	if _loaded_card_sets.has(set_id):
		return
	_loaded_card_sets[set_id] = true

	var path := "res://Card_Set_Data/" + set_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapManager: cannot open " + path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Array:
		for card in data:
			var cid: String = card.get("id", "")
			if cid != "":
				_card_name_cache[cid] = card.get("name", cid)

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
