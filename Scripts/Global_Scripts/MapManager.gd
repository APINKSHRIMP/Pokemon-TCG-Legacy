extends Node

# ============================================================
# MAP MANAGER - Autoload singleton
# ============================================================

var opponent_scene   = preload("res://Scenes/Objects/Opponent_Object_Scene.tscn")
var npc_scene        = preload("res://Scenes/Objects/NPC_Object_Scene.tscn")
var shopkeeper_scene = preload("res://Scenes/Objects/Shopkeeper_Object_Scene.tscn")

const CONSTANT_DATA_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"

var _player: CharacterBody2D
var _opponents_container: Node2D
var _ui_layer: CanvasLayer
var _map_scene_path: String
var _json_path: String

var _npc_constants: Dictionary = {}
var _opponent_constants: Dictionary = {}
var _constant_data_loaded: bool = false

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

# When non-empty, the next OK press launches PackOpeningManager for gifted packs.
var _pending_pack_opening: Array = []

# Container holding the displayed card/coin TextureRects during gift reveal
var _gift_display_container: Control = null

# Full-screen dim overlay shown behind the gift display
var _gift_dim_overlay: ColorRect = null

# ── Card / set name lookup caches (populated lazily) ─────────────
var _set_name_cache: Dictionary = {}
# Stores full card dicts (name, rarity, supertype, types, etc.) keyed by uid
var _card_data_cache: Dictionary = {}
var _loaded_card_sets: Dictionary = {}

# Preloaded back textures used during the gift reveal animation
const _CARDBACK_PATH := "res://Image_Assets/Card_Backs_And_Decks/cardback.png"
const _COINBACK_PATH := "res://Image_Assets/Coins/coin_back_basic.png"
var _cardback_texture: Texture2D = null
var _coinback_texture: Texture2D = null

# Total animation durations (kept as constants so the OK button can be
# re-shown after the animation completes).
# Flip: 5 flips, each shrink+expand of equal duration.
# Total = 2 * (0.1 + 0.2 + 0.4 + 0.8 + 1.6) = 6.2s
const GIFT_FLIP_TOTAL_DURATION := 1.5
# Costume: 0.5s blacked out, then 1.0s fade in
const GIFT_COSTUME_TOTAL_DURATION := 1.5

# Set IDs that are promo sets — these use "<set_name> <card_name>"
# instead of the usual "<set_name> set <card_name>"
const PROMO_SET_IDS := ["basep", "np"]

# Card display dimensions — Pokémon card aspect ~0.717 (W:H).
# Single card target ~600px tall; multi-card sizes scale down progressively.
const GIFT_CARD_SIZES := {
	1: Vector2(430, 600),
	2: Vector2(380, 530),
	3: Vector2(320, 446),
	4: Vector2(280, 390),
}

const GIFT_COIN_SIZE := Vector2(250, 250)

# Costume display size — 50% larger than the standard size
const GIFT_COSTUME_SIZE := Vector2(432, 594)

const GIFT_ITEM_SEPARATION := 20.0

# Vertical centre point on screen for the displayed gift items
const GIFT_DISPLAY_CENTER_Y_CARD    := 460.0
const GIFT_DISPLAY_CENTER_Y_COIN    := 570.0
const GIFT_DISPLAY_CENTER_Y_COSTUME := 570.0

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
	if not GameState.returning_from_battle:
		GameState.last_battled_opponent_entry = {}
	_load_and_spawn_opponents(json_path)
	_load_and_spawn_npcs(npc_json_path)

	_player.interact_pressed.connect(_on_player_interact)
	_player.npc_interact_pressed.connect(_on_player_npc_interact)

	if GameState.returning_from_battle:
		_handle_battle_return()

# ============================================================
# CONSTANT DATA
# ============================================================

func _load_constant_data() -> void:
	if _constant_data_loaded:
		return
	_constant_data_loaded = true
	var file = FileAccess.open(CONSTANT_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("MapManager: Cannot open constant data: " + CONSTANT_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		_npc_constants = data.get("npcs", {})
		_opponent_constants = data.get("opponents", {})

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

	_load_constant_data()
	for entry in data["opponents"]:
		var consts: Dictionary = _opponent_constants.get(entry.get("name", ""), {})
		for key in consts:
			if not entry.has(key):
				entry[key] = consts[key]
		if not _evaluate_condition(entry.get("condition", {})):
			continue
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

	if GameState.returning_from_battle and not GameState.last_battled_opponent_entry.is_empty():
		var lbe = GameState.last_battled_opponent_entry
		var already_spawned = false
		for child in _opponents_container.get_children():
			if child.is_in_group("opponents") and child.opponent_name == lbe["name"]:
				already_spawned = true
				break
		if not already_spawned:
			var opp = opponent_scene.instantiate()
			opp.opponent_name    = lbe["name"]
			opp.sprite           = lbe["sprite"]
			opp.music            = lbe["music"]
			opp.deck             = lbe["deck"]
			opp.prize_cards      = lbe.get("prize_cards", 6)
			opp.meet_text        = lbe["meet_text"]
			opp.repeat_text      = lbe["repeat_text"]
			opp.first_win_text   = lbe["first_win_text"]
			opp.rematch_win_text = lbe["rematch_win_text"]
			opp.loss_text        = lbe["loss_text"]
			opp.coin_reward      = lbe["coin_reward"]
			opp.cash_reward      = lbe["cash_reward"]
			opp.position         = lbe["position"]
			opp.movement_pattern = lbe.get("pattern", "idle_random")
			opp.patrol_distance  = lbe.get("patrol_distance", 100.0)
			opp.patrol_speed     = lbe.get("patrol_speed", 60.0)
			opp.patrol_axis      = lbe.get("patrol_axis", "horizontal")
			opp.wander_radius    = lbe.get("wander_radius", 200.0)
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

	_load_constant_data()
	for entry in data["npcs"]:
		var consts: Dictionary = _npc_constants.get(entry.get("name", ""), {})
		for key in consts:
			if not entry.has(key):
				entry[key] = consts[key]
		if not _evaluate_condition(entry.get("condition", {})):
			continue
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
# CONDITION EVALUATION
# ============================================================

func _evaluate_condition(condition: Dictionary) -> bool:
	if condition.is_empty():
		return true
	var ctype = condition.get("type", "")
	if GameState.returning_from_battle:
		var just_beaten = GameState.current_opponent_name
		if ctype == "opponent_not_defeated" and condition.get("target", "") == just_beaten:
			return true
		if ctype == "opponent_defeated" and condition.get("target", "") == just_beaten:
			return false
	match ctype:
		"opponent_defeated":
			return GameState.has_beaten_opponent(condition.get("target", ""))
		"opponent_not_defeated":
			return not GameState.has_beaten_opponent(condition.get("target", ""))
		"all_opponents_defeated":
			for t in condition.get("targets", []):
				if not GameState.has_beaten_opponent(t):
					return false
			return true
		"not_all_opponents_defeated":
			for t in condition.get("targets", []):
				if not GameState.has_beaten_opponent(t):
					return true
			return false
		"any_opponent_defeated":
			for t in condition.get("targets", []):
				if GameState.has_beaten_opponent(t):
					return true
			return false
		"npc_met":
			return GameState.has_met_npc(condition.get("target", ""))
		"npc_not_met":
			return not GameState.has_met_npc(condition.get("target", ""))
		"flag_set":
			return GameState.progress.get(condition.get("flag", ""), false)
		"flag_not_set":
			return not GameState.progress.get(condition.get("flag", ""), false)
	push_warning("MapManager: Unknown condition type: " + condition.get("type", ""))
	return true

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
		GameState.current_shop_id = current_npc.shop_id
		if current_npc.shop_id == "coin_mart":
			# Coin shop returns to Celeste_Harbour — use menu_return_state so
			# Celeste_Harbour._ready() restores position via has_menu_return_state
			GameState.save_menu_return_state(
				"res://Scenes/Map_Scenes/Celeste_Harbour.tscn",
				_player.position,
				_player.get_current_direction()
			)
			_hide_message()
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Coin_Shop.tscn")
		elif current_npc.shop_id == "holo_mart":
			GameState.save_menu_return_state(
				"res://Scenes/Map_Scenes/Celeste_Harbour.tscn",
				_player.position,
				_player.get_current_direction()
			)
			_hide_message()
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Holo_Rare_Shop.tscn")
		else:
			# All other shops (card_mart, rocket_mart) use spawn_position
			GameState.save_player_direction(_player.get_current_direction())
			GameState.spawn_position = _player.position
			GameState.use_spawn_position = true
			_hide_message()
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn")
		return

	# Opponent battle
	if current_opponent != null:
		GameState.current_opponent_name      = current_opponent.opponent_name
		GameState.current_opponent_deck      = current_opponent.deck
		GameState.current_opponent_json_path = _json_path
		GameState.player_position            = _player.position
		GameState.returning_from_battle      = false
		GameState.return_map_scene_path      = _map_scene_path
		GameState.last_battled_opponent_entry = {
			"name":           current_opponent.opponent_name,
			"sprite":         current_opponent.sprite,
			"music":          current_opponent.music,
			"deck":           current_opponent.deck,
			"prize_cards":    current_opponent.prize_cards,
			"meet_text":      current_opponent.meet_text,
			"repeat_text":    current_opponent.repeat_text,
			"first_win_text":    current_opponent.first_win_text,
			"rematch_win_text":  current_opponent.rematch_win_text,
			"loss_text":      current_opponent.loss_text,
			"coin_reward":    current_opponent.coin_reward,
			"cash_reward":    current_opponent.cash_reward,
			"position":       current_opponent.position,
			"pattern":        current_opponent.movement_pattern,
			"patrol_distance": current_opponent.patrol_distance,
			"patrol_speed":   current_opponent.patrol_speed,
			"patrol_axis":    current_opponent.patrol_axis,
			"wander_radius":  current_opponent.wander_radius,
		}

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
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Match_Start_Intro_Scene.tscn")

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

	# If pack opening is queued, launch it (player stays movement-locked)
	if not _pending_pack_opening.is_empty():
		var arts := _pending_pack_opening.duplicate()
		_pending_pack_opening.clear()
		message_panel.visible = false
		PackOpeningManager.all_packs_opened.connect(_on_pack_opening_finished, CONNECT_ONE_SHOT)
		PackOpeningManager.open_packs(arts)
		return

	if current_npc != null:
		current_npc.refresh_bubble()
	_hide_message()


func _on_pack_opening_finished() -> void:
	if _player != null:
		_player.can_move = true
	if current_npc != null:
		current_npc.resume_movement()
		current_npc = null

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
		"pack":
			var pack_arts: Array = []
			for raw in npc.gift_value.split(","):
				var art: String = raw.strip_edges()
				if art != "":
					pack_arts.append(art)
			queue_pack_gift(pack_arts)
		"pack_of_cards":
			push_warning("MapManager: pack_of_cards gift not yet implemented for: " + npc.gift_value)
		_:
			push_error("MapManager: Unknown gift_type '" + npc.gift_type + "' on NPC: " + npc.npc_name)
	GameState.mark_gift_received(npc.npc_name)


# Queues a pack opening sequence to trigger on the next OK press.
# Called by Shopkeeper_Script for Day-2 free packs.
func queue_pack_gift(pack_arts: Array) -> void:
	_pending_pack_opening = pack_arts.duplicate()

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
		"costume":
			# Costumes are always single-value
			_pending_gift_display = {
				"text": "You received the " + _format_costume_name(gift_value) + " costume",
				"image_paths": ["res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + gift_value + ".png"],
				"kind": "costume",
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
#
# Uses the same texture-fit pattern as Card_Image_Loader_Script.load_card_image
# and Pack_Purchase_Script._open_pack_animation:
#   1. Load texture, read its natural dimensions
#   2. Compute aspect-fit size against a target box
#   3. Apply EXPAND_IGNORE_SIZE + size/custom_minimum_size all set to the
#      computed values so the rect renders at exactly the size we want
func _show_gift_display(text: String, image_paths: Array, kind: String) -> void:
	_clear_gift_display()

	# Full-screen black 80%-alpha dim overlay sits behind everything gift-related
	_gift_dim_overlay = ColorRect.new()
	_gift_dim_overlay.color = Color(0, 0, 0, 0.8)
	_gift_dim_overlay.anchor_right  = 1.0
	_gift_dim_overlay.anchor_bottom = 1.0
	_gift_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_gift_dim_overlay)

	# Container parented to the UI layer so it sits above the world.
	# Anchors stretch full screen so child positions are screen-pixel accurate.
	_gift_display_container = Control.new()
	_gift_display_container.anchor_right  = 1.0
	_gift_display_container.anchor_bottom = 1.0
	_gift_display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_gift_display_container)

	# Pick target box (size budget per item) and Y centre based on kind
	var target_box: Vector2
	var center_y: float
	if kind == "coin":
		target_box = GIFT_COIN_SIZE
		center_y = GIFT_DISPLAY_CENTER_Y_COIN
	elif kind == "costume":
		target_box = GIFT_COSTUME_SIZE
		center_y = GIFT_DISPLAY_CENTER_Y_COSTUME
	else:
		var n_clamp: int = clamp(image_paths.size(), 1, 4)
		target_box = GIFT_CARD_SIZES.get(n_clamp, GIFT_CARD_SIZES[4])
		center_y = GIFT_DISPLAY_CENTER_Y_CARD

	# ── PASS 1: Load each texture and compute the actual rendered size ──
	# (mirrors Pack_Purchase_Script lines 526-532)
	var entries: Array = []
	for path in image_paths:
		var tex: Texture2D = _load_card_image_with_fallback(path)
		if tex == null:
			push_warning("MapManager: gift image not found: " + path)
			continue

		var actual_size: Vector2
		if kind == "coin":
			# Coins: force every coin to the same fixed box. STRETCH_SCALE
			# fills the box, so even sources with different aspect ratios
			# render at exactly the same on-screen size.
			actual_size = target_box
		else:
			# Cards/costumes: aspect-fit inside the target box so the rect's
			# width and height match the texture's true proportions.
			# This is the same pattern as Card_Image_Loader lines 60-67.
			var orig_w := float(tex.get_width())
			var orig_h := float(tex.get_height())
			if orig_w <= 0.0 or orig_h <= 0.0:
				actual_size = target_box
			else:
				var scale_x := target_box.x / orig_w
				var scale_y := target_box.y / orig_h
				var scale_factor: float = min(scale_x, scale_y)
				actual_size = Vector2(orig_w * scale_factor, orig_h * scale_factor)

		# Derive the card UID from the path so we can look up rarity/types
		# later for the holo sparkle effect (cards only — empty for others).
		var card_uid: String = ""
		if kind == "card":
			card_uid = String(path).get_file().trim_suffix(".png")

		entries.append({"texture": tex, "size": actual_size, "card_uid": card_uid})

	if entries.is_empty():
		_show_message_with_ok(text)
		return

	# ── PASS 2: Compute total layout width and start_x for centring ──
	# Centre the entire group horizontally on the actual viewport midpoint.
	var total_width: float = 0.0
	for e in entries:
		total_width += e["size"].x
	total_width += (entries.size() - 1) * GIFT_ITEM_SEPARATION

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_center_x: float = viewport_size.x / 2.0
	var start_x: float = viewport_center_x - total_width / 2.0

	# ── PASS 3: Spawn the rects ──
	# All kinds use STRETCH_SCALE — the rect is already aspect-fit so SCALE
	# fills it without distortion. For coins it forces a uniform render size.
	var stretch_mode_id: int = TextureRect.STRETCH_SCALE

	# Make sure back textures are loaded if we'll need them for the flip
	if kind == "card" or kind == "coin":
		_ensure_back_textures_loaded()

	var spawned_rects: Array = []  # rect, card_uid pairs for animation pass
	var cursor_x: float = start_x
	for e in entries:
		var sz: Vector2 = e["size"] as Vector2
		var top_y: float = center_y - sz.y / 2.0

		var rect = TextureRect.new()
		rect.texture             = e["texture"]
		rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode        = stretch_mode_id
		rect.custom_minimum_size = sz
		rect.size                = sz
		rect.position            = Vector2(cursor_x, top_y)
		rect.pivot_offset        = sz / 2.0
		rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_gift_display_container.add_child(rect)
		spawned_rects.append({"rect": rect, "card_uid": e["card_uid"]})

		cursor_x += sz.x + GIFT_ITEM_SEPARATION

	# Ensure the message panel renders above the gift container and overlay
	if message_panel.get_parent() == _ui_layer:
		_ui_layer.move_child(message_panel, _ui_layer.get_child_count() - 1)

	# Show the message panel WITHOUT the OK button — animation must complete first
	_show_message_with_ok(text)
	ok_button.visible = false

	# ── PASS 4: Kick off reveal animations (parallel) ──
	for sr in spawned_rects:
		var rect_ref: TextureRect = sr["rect"]
		var uid: String = sr["card_uid"]
		match kind:
			"coin":
				_play_flip_animation(rect_ref, _coinback_texture, rect_ref.texture)
			"card":
				_play_card_flip_with_holo(rect_ref, _cardback_texture, rect_ref.texture, uid)
			"costume":
				_play_costume_fadein(rect_ref)

	# Wait for the longest animation to complete, then re-enable OK
	var total_duration: float = 0.0
	if kind == "costume":
		total_duration = GIFT_COSTUME_TOTAL_DURATION
	elif kind == "card" or kind == "coin":
		total_duration = GIFT_FLIP_TOTAL_DURATION
	if total_duration > 0.0:
		await get_tree().create_timer(total_duration).timeout
	# After awaiting, the player may have already dismissed (e.g. via cleanup).
	# Only reveal OK if the message is still on screen.
	if message_panel.visible and ok_button != null:
		ok_button.visible = true

# Removes the gift display container and dim overlay if they exist.
func _clear_gift_display() -> void:
	if _gift_display_container != null and is_instance_valid(_gift_display_container):
		_gift_display_container.queue_free()
	_gift_display_container = null
	if _gift_dim_overlay != null and is_instance_valid(_gift_dim_overlay):
		_gift_dim_overlay.queue_free()
	_gift_dim_overlay = null

# ============================================================
# REVEAL ANIMATIONS
# ============================================================

# Spins a rect on its vertical (Y) axis by tweening scale.x to 0 and back,
# swapping the texture at each squash midpoint. Used for coins and cards.
# Mirrors the pattern from Main_Match_Core_Gameplay_Script.flip_coin (line 2175)
# but with progressively-longer durations and only one squash axis.
#
# Sequence:
func _play_flip_animation(rect: TextureRect, back_tex: Texture2D, target_tex: Texture2D) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	if back_tex == null or target_tex == null:
		return

	# Start with back face, full width
	rect.texture = back_tex
	rect.pivot_offset = rect.size / 2.0
	rect.scale = Vector2(1.0, 1.0)

	var shrink_durations := [0.01, 0.02, 0.04, 0.06, 0.08, 0.1, 0.11, 0.12, 0.2]
	# After each shrink, swap to the alternating texture
	var swaps := [target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex]

	var tween := create_tween()
	for i in shrink_durations.size():
		var d: float = shrink_durations[i]
		tween.tween_property(rect, "scale:x", 0.0, d)
		tween.tween_callback(rect.set.bind("texture", swaps[i]))
		tween.tween_property(rect, "scale:x", 1.0, d)

	await tween.finished

# Card-specific wrapper: runs the flip, then if the card is a Rare Holo,
# starts the holo sparkle particle effect (same one Pack_Purchase uses).
func _play_card_flip_with_holo(rect: TextureRect, back_tex: Texture2D, card_tex: Texture2D, card_uid: String) -> void:
	await _play_flip_animation(rect, back_tex, card_tex)
	if rect == null or not is_instance_valid(rect):
		return
	# Check rarity post-flip
	var card_data: Dictionary = _get_card_data(card_uid)
	if card_data.get("rarity", "") == "Rare Holo":
		_start_gift_holo_sparkle(rect, card_data)

# Fades a costume in: starts fully blacked-out for 0.5s, then over 1s
# tweens modulate back to white.
func _play_costume_fadein(rect: TextureRect) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	rect.modulate = Color(0, 0, 0, 1)  # fully black, opaque
	await get_tree().create_timer(0.5).timeout
	if rect == null or not is_instance_valid(rect):
		return
	var tween := create_tween()
	tween.tween_property(rect, "modulate", Color(1, 1, 1, 1), 1.0)

# Spawns a continuous sparkle particle system over a card rect. Adapted from
# Pack_Purchase_Script._start_holo_sparkle (line 731). Parented to the gift
# container so it's freed automatically when the gift display is dismissed.
func _start_gift_holo_sparkle(card_rect: TextureRect, card_data: Dictionary) -> CPUParticles2D:
	if _gift_display_container == null or not is_instance_valid(_gift_display_container):
		return null

	var particles := CPUParticles2D.new()
	_gift_display_container.add_child(particles)

	var card_size: Vector2 = card_rect.size
	particles.global_position       = card_rect.global_position + card_size / 2.0
	particles.z_index               = 5
	particles.amount                = 150
	particles.lifetime              = 1.5
	particles.one_shot              = false
	particles.explosiveness         = 0.4
	particles.emitting              = true
	particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = card_size / 2.0
	particles.direction             = Vector2(0, 0)
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.gravity               = Vector2(0, 0)
	particles.scale_amount_min      = 3.0
	particles.scale_amount_max      = 8.0

	var sparkle_colour: Color = _get_holo_sparkle_colour(card_data)
	var bright: Color = sparkle_colour.lightened(1)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient

	return particles

# Returns the sparkle colour for a holo card based on its primary type.
# Trainers / Energy with no type fall back to silver.
func _get_holo_sparkle_colour(card_data: Dictionary) -> Color:
	var supertype: String = card_data.get("supertype", "")
	if supertype == "Pokémon" or supertype == "Pokemon":
		var types = card_data.get("types", [])
		if types is Array and types.size() > 0:
			return _get_type_colour(types[0])
	return Color(0.85, 0.85, 0.9)

# Maps a Pokemon type string to a representative colour for sparkle effects.
func _get_type_colour(type_name: String) -> Color:
	match type_name.to_lower():
		"fire":      return Color(1.0, 0.2, 0.1)
		"water":     return Color(0.2, 0.5, 1.0)
		"grass":     return Color(0.2, 0.8, 0.3)
		"lightning": return Color(1.0, 0.9, 0.1)
		"darkness":  return Color(0.15, 0.1, 0.2)
		"psychic":   return Color(0.55, 0.1, 1.0)
		"metal":     return Color(0.6, 0.6, 0.65)
		"fighting":  return Color(0.5, 0.3, 0.2)
		"dragon":    return Color(0.9, 0.7, 0.2)
		"fairy":     return Color(1.0, 0.4, 0.7)
		_:           return Color(1.0, 1.0, 1.0)

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
# COSTUME NAME FORMATTING
# Underscore-separated filename → title-cased space-separated string.
#   "red_pikachu_outfit"  -> "Red Pikachu Outfit"
#   "trainer_red"         -> "Trainer Red"
# ============================================================

func _format_costume_name(raw: String) -> String:
	var name_str: String = raw.replace(".png", "")
	var parts = name_str.split("_")
	var result_parts: Array = []
	for p in parts:
		if p.length() > 0:
			result_parts.append(p.substr(0, 1).to_upper() + p.substr(1))
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

	var card_data = _card_data_cache.get(card_uid, null)
	var card_name: String = card_uid
	if card_data is Dictionary:
		card_name = card_data.get("name", card_uid)
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
				_card_data_cache[cid] = card

func _ensure_back_textures_loaded() -> void:
	if _cardback_texture == null:
		_cardback_texture = load(_CARDBACK_PATH)
	if _coinback_texture == null:
		_coinback_texture = load(_COINBACK_PATH)

# Returns the full cached card data dict (name, rarity, supertype, types, etc.)
# or an empty Dictionary if the card isn't found.
func _get_card_data(card_uid: String) -> Dictionary:
	var split = card_uid.split("-")
	if split.size() != 2:
		return {}
	_ensure_card_set_loaded(split[0])
	var data = _card_data_cache.get(card_uid, null)
	if data is Dictionary:
		return data
	return {}

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
