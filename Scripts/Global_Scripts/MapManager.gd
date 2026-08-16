extends Node

# ============================================================
# MAP MANAGER - Autoload singleton
# ============================================================

var opponent_scene   = preload("res://Scenes/Objects/Opponent_Object_Scene.tscn")
var npc_scene        = preload("res://Scenes/Objects/NPC_Object_Scene.tscn")
var shopkeeper_scene = preload("res://Scenes/Objects/Shopkeeper_Object_Scene.tscn")

const CONSTANT_DATA_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"
const SHOP_CONFIG_PATH   := "res://NPC_and_Opponent_Data/Shop_Config/shops.json"

# TWEAKABLE — body-text size for the "big announcement" messagebox style (the starter box upstairs,
# and since ISSUE #104 every "You received the X" gift/purchase notice). Normal dialogue is 28.
# This is a CEILING: set_body_text() shrinks past it if the text wouldn't otherwise fit the panel.
const LARGE_MESSAGE_FONT_SIZE := 40

var _shop_configs: Dictionary = {}
var _shop_configs_loaded: bool = false

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

# True while the deck-validation popup is open. Blocks the regular
# opponent/NPC interact handlers so the player can't re-trigger a
# battle dialog by pressing space while the overlay is up.
var _validation_popup_active: bool = false
var _validation_popup_node: Control = null

var message_panel: DynamicMessageBox
var message_label: RichTextLabel
var yes_button: Button
var no_button: Button
var ok_button: Button

# Callback fired when the player presses Yes on a generic interactable
# confirm dialog (e.g. the bed). Empty Callable when none is active.
var _pending_confirm_yes: Callable = Callable()

# One-shot callback fired on the next OK press, before the default
# dismiss logic. Used by scene interactables to chain message sequences.
var _pending_ok_action: Callable = Callable()

# ============================================================
# GIFT DISPLAY STATE
# ============================================================

# When non-empty, the next OK press triggers the gift card/coin reveal
# instead of dismissing the message panel. Keys: text, image_paths, kind.
var _pending_gift_display: Dictionary = {}

# When non-empty, the next OK press launches PackOpeningManager for gifted packs.
var _pending_pack_opening: Array = []

# ── Juice vendor state ─────────────────────────────────────────────
# When non-empty, the next OK press shows the "delicious..." result message and
# (if reward_coin is set) queues the gift display for the OK after that.
# Keys: {text, reward_coin}
var _pending_juice_result: Dictionary = {}

# Temporary cash overlay (label) shown while talking to the juice vendor.
# Mirrors Card_Mart's _create_cash_label position/style.
var _cash_overlay: Label = null

# Per-tier roll chances (%) and pity thresholds — the tier each cup falls into
# is determined by which coins the player has already won.
const JUICE_COST: int             = 50
const JUICE_COST_DISCOUNT: int    = 25                # after all 3 coins won
const JUICE_COIN_SILVER: String   = "Munchlax Silver"
const JUICE_COIN_GOLD: String     = "Munchlax Gold"
const JUICE_COIN_BLUE: String     = "Zz Munchlax Blue"
const JUICE_SILVER_CHANCE: int    = 40                # cups while silver is the active tier
const JUICE_SILVER_PITY: int      = 3
const JUICE_GOLD_CHANCE: int      = 30                # cups while gold is the active tier
const JUICE_GOLD_PITY: int        = 3
const JUICE_BLUE_CHANCE: int      = 25                # cups while blue is the active tier
const JUICE_BLUE_PITY: int        = 5
const JUICE_BROKE_MSG: String     = "Sorry, you don't have enough cash!"
const JUICE_NORMAL_MSG: String    = "Mmmmm, that juice was delicious."
const JUICE_COIN_MSG: String      = "Mmmmm, that juice was delicious...... Hey, there was a coin in the bottom of the cup!"

# Container holding the displayed card/coin TextureRects during gift reveal
var _gift_display_container: Control = null

# Full-screen dim overlay shown behind the gift display
var _gift_dim_overlay: ColorRect = null

# ISSUE #33: click-to-skip state for the gift reveal animation.
var _gift_reveal_active: bool = false            # true while the coin/card/costume reveal plays
var _gift_reveal_skip: bool = false              # set when the player clicks to skip
var _gift_reveal_tweens: Array = []              # running reveal tweens (killed on skip)
var _gift_reveal_finals: Array = []              # [{rect, texture, modulate}] final states to snap to

# ── Card / set name lookup caches (populated lazily) ─────────────
var _set_name_cache: Dictionary = {}
# Stores full card dicts (name, rarity, supertype, types, etc.) keyed by uid
var _card_data_cache: Dictionary = {}
var _loaded_card_sets: Dictionary = {}

# ISSUE #56: overworld actor position tracker. Every NPC/opponent's live position is captured when
# the map unloads (battle, sub-menu, door), keyed by "<source_json_path>::<actor_name>". On the next
# spawn from that same day file we restore the captured position instead of the data-file default, so
# actors don't visibly teleport back to their spawn when the map reloads. Keying on the source json
# path means a different time-of-day (a different day file) naturally falls back to fresh positions.
var _actor_positions: Dictionary = {}

# ISSUE #56 (retest): captured facing direction ("up"/"down"/"left"/"right") per actor, keyed the
# same way as _actor_positions. Restored on the next spawn so an NPC/opponent that turned to face the
# player before a battle/menu resumes facing that way instead of snapping back to its pattern default.
var _actor_facings: Dictionary = {}

# Preloaded back textures used during the gift reveal animation
const _CARDBACK_PATH := "res://Image_Assets/Sleeves/1_Default_English.png"
const _COINBACK_PATH := "res://Image_Assets/Coins/Back Basic.png"
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

func _get_shop_config(shop_id: String) -> Dictionary:
	if not _shop_configs_loaded:
		_shop_configs_loaded = true
		var file = FileAccess.open(SHOP_CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				_shop_configs = parsed
	return _shop_configs.get(shop_id, {})

# ============================================================
# OPPONENT SPAWNING
# ============================================================

# ISSUE #56: assign a freshly-spawned actor its position — the captured live position from a previous
# visit to this same day file if one exists, otherwise the data-file default — and tag it with the
# key so capture_actor_positions() can find it again when the map unloads.
func _assign_actor_position(actor: Node2D, source_json: String, actor_name: String, default_pos: Vector2) -> void:
	var key := source_json + "::" + actor_name
	actor.position = _actor_positions.get(key, default_pos)
	actor.set_meta("pos_key", key)
	# ISSUE #56 (retest): stash the captured facing as a meta the actor applies at the END of its own
	# _ready() (after _init_movement sets a pattern default), so the restored direction wins.
	if _actor_facings.has(key):
		actor.set_meta("restore_facing", _actor_facings[key])

# ISSUE #56: snapshot every tagged actor's current position. Called from BaseMapScene._exit_tree(),
# which fires for every overworld unload (battle start, sub-menu, door transition).
func capture_actor_positions() -> void:
	if _opponents_container == null or not is_instance_valid(_opponents_container):
		return
	for child in _opponents_container.get_children():
		if child.has_meta("pos_key"):
			_actor_positions[child.get_meta("pos_key")] = child.position
			# ISSUE #56 (retest): capture the facing at the same instant as the position so the actor
			# resumes exactly as it was at the moment the map unloaded (e.g. still facing the player).
			if "current_facing" in child:
				_actor_facings[child.get_meta("pos_key")] = child.current_facing

# ISSUE #55: hard-stop every overworld actor (opponents + NPCs live in the opponents container) plus
# the player so nothing keeps wandering during the fade-out between accepting a battle and the intro.
func _freeze_overworld_actors() -> void:
	if _opponents_container != null and is_instance_valid(_opponents_container):
		for child in _opponents_container.get_children():
			if child.has_method("freeze"):
				child.freeze()
	if _player != null and is_instance_valid(_player):
		_player.lock_movement()

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
		# ISSUE #83 FIX: defaults on every optional field — one missing dialogue key in a day file used to
		# abort the whole map load with "Invalid access to key".
		opp.opponent_name    = entry.get("name", "")
		opp.sprite           = entry.get("sprite", "")
		opp.music            = entry.get("music", "")
		opp.deck             = entry.get("deck", "")
		opp.prize_cards      = entry.get("prize_cards", 6)
		opp.meet_text        = entry.get("meet_text", "")
		opp.repeat_text      = entry.get("repeat_text", "")
		opp.first_win_text   = entry.get("first_win_text", "")
		opp.rematch_win_text = entry.get("rematch_win_text", "")
		opp.loss_text        = entry.get("loss_text", "")
		opp.coin_reward      = entry.get("coin_reward", "")
		opp.cash_reward      = entry.get("cash_reward", 0)
		opp.message_colour   = entry.get("message_colour", "")
		_assign_actor_position(opp, json_path, entry.get("name", ""), Vector2(entry["position"]["x"], entry["position"]["y"]))
		opp.movement_pattern = entry.get("pattern", "idle_random")
		opp.interact_facing  = entry.get("interact_facing", "")
		opp.patrol_distance  = entry.get("patrol_distance", 100.0)
		opp.patrol_speed     = entry.get("patrol_speed", 60.0)
		opp.patrol_axis      = entry.get("patrol_axis", "horizontal")
		opp.wander_radius    = entry.get("wander_radius", 200.0)
		opp.restrictions     = entry.get("restrictions", {})
		opp.match_effects    = entry.get("match_effects", [])
		opp.match_format     = entry.get("match_format", "")
		opp.sleeve           = entry.get("sleeve", "")
		_opponents_container.add_child(opp)

	# ISSUE #83 FIX: the T-key TEST match has no opponent in the world at all — its entry is synthesized
	# by GameState.build_test_opponent_data(), which deliberately carries only the handful of fields the
	# match itself needs. Re-spawning it here crashed on the very first missing key ("meet_text"), and
	# would have gone on to fail on position/sprite too. Skip the respawn entirely for a TEST match.
	if GameState.returning_from_battle and GameState.test_match_mode:
		print("ISSUE #83 FIX ACTIVE: skipping last-battled-opponent respawn after a TEST match")
	elif GameState.returning_from_battle and not GameState.last_battled_opponent_entry.is_empty():
		var lbe = GameState.last_battled_opponent_entry
		var already_spawned = false
		for child in _opponents_container.get_children():
			if child.is_in_group("opponents") and child.opponent_name == lbe.get("name", ""):
				already_spawned = true
				break
		# ISSUE #83 FIX: every field below now has a default. A partial entry must never hard-crash the
		# whole map load — a missing dialogue line should just mean an empty string.
		if not already_spawned and lbe.has("position"):
			var opp = opponent_scene.instantiate()
			opp.opponent_name    = lbe.get("name", "")
			opp.sprite           = lbe.get("sprite", "")
			opp.music            = lbe.get("music", "")
			opp.deck             = lbe.get("deck", "")
			opp.prize_cards      = lbe.get("prize_cards", 6)
			opp.meet_text        = lbe.get("meet_text", "")
			opp.repeat_text      = lbe.get("repeat_text", "")
			opp.first_win_text   = lbe.get("first_win_text", "")
			opp.rematch_win_text = lbe.get("rematch_win_text", "")
			opp.loss_text        = lbe.get("loss_text", "")
			opp.coin_reward      = lbe.get("coin_reward", "")
			opp.cash_reward      = lbe.get("cash_reward", 0)
			opp.message_colour   = lbe.get("message_colour", "")
			_assign_actor_position(opp, _json_path, lbe.get("name", ""), lbe["position"])
			opp.movement_pattern = lbe.get("pattern", "idle_random")
			opp.interact_facing  = lbe.get("interact_facing", "")
			opp.patrol_distance  = lbe.get("patrol_distance", 100.0)
			opp.patrol_speed     = lbe.get("patrol_speed", 60.0)
			opp.patrol_axis      = lbe.get("patrol_axis", "horizontal")
			opp.wander_radius    = lbe.get("wander_radius", 200.0)
			opp.restrictions     = lbe.get("restrictions", {})
			opp.match_effects    = lbe.get("match_effects", [])
			opp.match_format     = lbe.get("match_format", "")
			opp.sleeve           = lbe.get("sleeve", "")
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

		print("Attempting to load NPC: ", entry.get("name", "UNKNOWN"))
		npc.npc_name         = entry["name"]
		# Message-box display name. Falls back to the tracking key so a data entry that
		# has not been given one still shows something rather than an empty header.
		npc.friendly_name    = entry.get("friendly_name", entry["name"])
		# Message box colour theme. Empty is fine — the box falls back to the default.
		npc.message_colour   = entry.get("message_colour", "")
		npc.sprite           = entry["sprite"]
		npc.npc_type         = entry.get("npc_type", "text_only")
		npc.meet_text        = entry.get("meet_text", "")
		npc.repeat_text      = entry.get("repeat_text", "")
		npc.gift_type        = entry.get("gift_type", "")
		npc.gift_value       = entry.get("gift_value", "")

		# Costume-gating fields live only on NPC_Object_Script, not the
		# shopkeeper script — assign them to non-shop NPCs only.
		if not is_shop:
			npc.required_costume   = entry.get("required_costume", "")
			npc.costume_match_text = entry.get("costume_match_text", "")
		_assign_actor_position(npc, json_path, entry["name"], Vector2(entry["position"]["x"], entry["position"]["y"]))
		npc.movement_pattern = entry.get("pattern", "idle_down")
		npc.patrol_distance  = entry.get("patrol_distance", 100.0)
		npc.patrol_speed     = entry.get("patrol_speed", 60.0)
		npc.patrol_axis      = entry.get("patrol_axis", "horizontal")
		npc.wander_radius    = entry.get("wander_radius", 200.0)
		npc.interact_facing  = entry.get("interact_facing", "")

		# Shop-specific fields
		if is_shop and npc.has_method("on_interact"):
			npc.shop_id = entry.get("shop_id", npc.npc_name.to_lower().replace(" ", "_"))

		_opponents_container.add_child(npc)
		print("Spawned NPC: ", npc.npc_name, " at ", npc.position)
		# ISSUE #93: local position is meaningless on its own — the container's own offset is what
		# went wrong, so print the global position that actually lands on screen.
		print("ISSUE #93 NPC PLACED: ", npc.npc_name, " local=", npc.position, " global=", npc.global_position, " container=", _opponents_container.get_path())

## Instantiate a single NPC entry dict into the current opponents container.
## Skips condition evaluation — intended for programmatically built entries
## such as dynamically generated audience members.
func spawn_npc_entry(entry: Dictionary) -> void:
	if not entry.has("position"):
		return
	var npc = npc_scene.instantiate()
	npc.npc_name         = entry.get("name", "")
	npc.friendly_name    = entry.get("friendly_name", "")
	npc.message_colour   = entry.get("message_colour", "")
	npc.sprite           = entry.get("sprite", "")
	npc.npc_type         = entry.get("npc_type", "text_only")
	npc.meet_text        = entry.get("meet_text", "")
	npc.repeat_text      = entry.get("repeat_text", "")
	npc.gift_type        = entry.get("gift_type", "")
	npc.gift_value       = entry.get("gift_value", "")
	npc.required_costume   = entry.get("required_costume", "")
	npc.costume_match_text = entry.get("costume_match_text", "")
	npc.position         = Vector2(entry["position"]["x"], entry["position"]["y"])
	npc.movement_pattern = entry.get("pattern", "idle_down")
	npc.patrol_distance  = entry.get("patrol_distance", 100.0)
	npc.patrol_speed     = entry.get("patrol_speed", 60.0)
	npc.patrol_axis      = entry.get("patrol_axis", "horizontal")
	npc.wander_radius    = entry.get("wander_radius", 200.0)
	npc.interact_facing  = entry.get("interact_facing", "")
	_opponents_container.add_child(npc)

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
		"all":
			# Compound AND — every sub-condition must pass. Sub-conditions live
			# in "conditions" and are evaluated recursively (so they honour the
			# returning_from_battle special-case individually).
			for sub in condition.get("conditions", []):
				if not _evaluate_condition(sub):
					return false
			return true
		"any":
			# Compound OR — at least one sub-condition must pass.
			for sub in condition.get("conditions", []):
				if _evaluate_condition(sub):
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

	var box     = MessageBoxHelper.build(138.0, 28, true)
	message_panel = box["root"]
	message_label = box["label"]
	yes_button    = box["yes_btn"]
	no_button     = box["no_btn"]
	ok_button     = box["ok_btn"]

	yes_button.pressed.connect(_on_yes_pressed)
	no_button.pressed.connect(_on_no_pressed)
	ok_button.pressed.connect(_on_ok_pressed)

	_ui_layer.add_child(message_panel)

# ------------------------------------------------------------
# INFO CHIPS
# ------------------------------------------------------------
# The little coloured boxes that sit on top of the message box. Built fresh
# for whoever the player is currently talking to, and cleared when nobody is
# (signs, the bed, the TV — those get a plain box).
#
# ADDING A NEW CHIP: append another dictionary to the array below. The box
# auto-sizes it, colours it from the next notch of the theme ramp and butts it
# up against the chip on its left — no layout work needed here. Icons live in
# Image_Assets/Icons/Message_Icons/. Two examples ready to drop in:
#
#   if current_opponent.match_format == "best_of_3":
#       chips.append({ "text": "x3", "icon_path": MSG_ICON_DIR + "trophy.png" })
#   if not current_opponent.match_effects.is_empty():
#       chips.append({ "text": str(current_opponent.match_effects.size()),
#                      "icon_path": MSG_ICON_DIR + "conditions.png" })
const MSG_ICON_DIR := "res://Image_Assets/Icons/Message_Icons/"

func _apply_actor_chips() -> void:
	if message_panel == null:
		return
	# Recolour first, THEN build the chips — the chip ramp is derived from the
	# theme, so setting them the other way round would leave the previous
	# speaker's colours on the row. The box is shared by everyone the player
	# talks to, so this runs on every show, not just when the box is built.

	if current_opponent != null:
		message_panel.apply_theme(current_opponent.message_colour)
		message_panel.set_chips([
			{ "text": current_opponent.opponent_name.to_upper(),
			  "sprite": current_opponent.sprite },
			{ "text": String(current_opponent.deck).to_upper(),
			  "icon_path": MSG_ICON_DIR + "deck.png" },
			{ "text": str(current_opponent.prize_cards),
			  "icon_path": MSG_ICON_DIR + "prizes.png" },
		])
		return

	# NPCs get their name and nothing else — no deck, no prizes. friendly_name
	# is the display name; npc_name is the unique tracking key and is never
	# shown (it encodes the days/times that NPC appears).
	if current_npc != null:
		var shown: String = current_npc.friendly_name if "friendly_name" in current_npc else ""
		if shown == "":
			shown = current_npc.npc_name
		# Guarded like friendly_name above — current_npc is typed Node, so a
		# future actor script without the field must not hard-crash dialogue.
		message_panel.apply_theme(current_npc.message_colour if "message_colour" in current_npc else "")
		message_panel.set_chips([
			{ "text": shown.to_upper(), "sprite": current_npc.sprite },
		])
		return

	# Nobody is speaking (a sign, the TV, the bed) — back to the interactables grey.
	message_panel.apply_theme()
	message_panel.clear_chips()


func _show_message_with_choices(text: String):
	_apply_actor_chips()
	message_panel.set_body_text(text)
	yes_button.visible = true
	no_button.visible  = true
	ok_button.visible  = false
	message_panel.visible = true
	_player.can_move = false

# font_size is a CEILING, not a fixed size — the box shrinks past it if the
# text would not otherwise fit the panel.
func _show_message_with_ok(text: String, font_size: int = 28):
	_apply_actor_chips()
	message_panel.set_body_text(text, font_size)
	yes_button.visible = false
	no_button.visible  = false
	ok_button.visible  = true
	message_panel.visible = true
	_player.can_move = false

# ISSUE #28 FIX: shows an OK dialog styled like the match's LARGE message — large size, centred
# horizontally AND vertically. Nothing needs restoring afterwards: set_body_text() re-derives the
# size on every show, and the box's font is the kenney one this used to swap in by hand.
func _show_large_message_with_ok(text: String) -> void:
	_apply_actor_chips()
	# The box already uses this font — only the size sets a large message apart
	# now. Horizontal centring via bbcode (RichTextLabel has no
	# horizontal_alignment); vertical centring is the box's default.
	message_panel.set_body_text("[center]" + text + "[/center]", LARGE_MESSAGE_FONT_SIZE)
	yes_button.visible = false
	no_button.visible  = false
	ok_button.visible  = true
	message_panel.visible = true
	_player.can_move = false

# ISSUE #104: as _show_large_message_with_ok, but fires `on_ok` once the player dismisses it. Used to
# chain a big "You received the X" notice into the follow-up dialogue.
func _show_large_message_then(text: String, on_ok: Callable) -> void:
	_pending_ok_action = on_ok
	_show_large_message_with_ok(text)

func _hide_message():
	message_panel.visible = false
	message_panel.clear_chips()
	_clear_gift_display()
	_hide_cash_overlay()
	_pending_confirm_yes = Callable()
	_player.can_move = true
	if current_opponent != null:
		current_opponent.resume_movement()
	if current_npc != null:
		current_npc.resume_movement()
	current_opponent = null
	current_npc = null

# ------------------------------------------------------------
# INTERACTABLES — public hooks for scene interactables (signs,
# the bed, the TV). Lets them reuse the shared messagebox
# without going through the opponent/NPC interaction paths.
# ------------------------------------------------------------

# Shows a simple OK dialog. Ignored if a dialog is already open.
func show_interactable_message(text: String, font_size: int = 24) -> void:
	if message_panel == null or message_panel.visible:
		return
	_show_message_with_ok(text, font_size)

# Shows an OK dialog then fires on_ok when the player dismisses it.
# If the panel is already visible (called from within a chain), just
# swaps the text in place — does NOT guard on message_panel.visible.
func show_message_then(text: String, on_ok: Callable) -> void:
	_pending_ok_action = on_ok
	_show_message_with_ok(text)

# Shows a Yes/No dialog. on_yes is called (after the dialog closes)
# only if the player chooses Yes. Ignored if a dialog is already open.
func show_interactable_confirm(text: String, on_yes: Callable) -> void:
	if message_panel == null or message_panel.visible:
		return
	_pending_confirm_yes = on_yes
	_show_message_with_choices(text)

func handle_message_spacebar():
	if _validation_popup_active:
		return
	if not message_panel.visible:
		return
	if ok_button.visible:
		_on_ok_pressed()
	elif yes_button.visible:
		_on_yes_pressed()

# ============================================================
# INTERACTION — OPPONENTS
# ============================================================

# ISSUE #57: turn the player toward whoever they just interacted with. Normally the direction is
# derived from the geometry, but an actor can pin it with an `interact_facing` field in its data
# entry. The three shopkeepers need that: a counter stops the player short of the shopkeeper and off
# to one side, so the dominant-axis rule would have them talking sideways along the counter rather
# than across it. Only actors that declare the field are affected — everyone else still turns to
# face the actor they are talking to.
func _face_player_toward_actor(actor: Node) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var forced: String = actor.interact_facing if "interact_facing" in actor else ""
	if forced != "":
		_player.set_direction(forced)
	else:
		_player.face_toward(actor.global_position)

func _on_player_interact(opponent: Node):
	if message_panel.visible or _validation_popup_active:
		return
	current_opponent = opponent
	opponent.pause_and_face(_player.global_position)
	# ISSUE #57: the player also turns to face the opponent, not just the opponent facing the player.
	_face_player_toward_actor(opponent)
	# Keep bubble visible during messagebox; refresh in case state changed
	opponent.refresh_bubble()
	_show_message_with_choices(opponent.get_greeting_text())

func _on_yes_pressed():
	# Generic interactable confirm (bed, etc.) — runs before opponent/NPC logic
	if _pending_confirm_yes.is_valid():
		var cb: Callable = _pending_confirm_yes
		_pending_confirm_yes = Callable()
		_hide_message()
		cb.call()
		return

	# Juice vendor — handle purchase inline, bypass the shop/battle paths below
	if current_npc != null and current_npc.npc_type == "juice_vendor":
		_handle_juice_purchase()
		return

	# Shop NPC — open the appropriate menu scene from shop config
	if current_npc != null and current_npc.npc_type == "shop":
		GameState.current_shop_id = current_npc.shop_id
		var shop_cfg := _get_shop_config(current_npc.shop_id)
		if shop_cfg.is_empty():
			push_error("MapManager: No shop config for shop_id: " + current_npc.shop_id)
			return
		_hide_message()
		if shop_cfg.get("return_mode", "spawn_position") == "menu_return":
			GameState.save_menu_return_state(
				shop_cfg.get("return_scene", _map_scene_path),
				_player.position,
				_player.get_current_direction()
			)
		else:
			GameState.save_player_direction(_player.get_current_direction())
			GameState.spawn_position = _player.position
			GameState.use_spawn_position = true
		SceneCache.change_scene(shop_cfg["menu_scene"])
		return

	# Opponent battle
	if current_opponent != null:
		# A normal battle is never a TEST match — clear any leftover debug flag.
		GameState.test_match_mode = false
		# Deck-restriction gate. If the opponent declares restrictions and the
		# player's current deck fails validation, surface the appropriate popup
		# / message and abort the battle. The check is deliberately placed
		# BEFORE any GameState writes so a failed validation leaves no
		# half-applied transition state behind.
		if DeckValidationHelper.opponent_has_restrictions(current_opponent.restrictions):
			var deck_path := _current_player_deck_path()
			var v_result := DeckValidationHelper.validate(deck_path, current_opponent.restrictions)
			if not v_result["passed"]:
				_handle_deck_validation_failure(v_result)
				return

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
			"restrictions":   current_opponent.restrictions,
			"match_effects":  current_opponent.match_effects,
			"match_format":   current_opponent.match_format,
			"sleeve":         current_opponent.sleeve,
		}

		# Best-of-N opponents: kick off a fresh series. Single-match opponents
		# clear any stale series state so the outro flows normally.
		if current_opponent.match_format != "":
			GameState.start_match_series(current_opponent.opponent_name, current_opponent.match_format)
		else:
			GameState.clear_match_series()

		_hide_message()
		SoundManagerScript.stop_bgm()

		# ISSUE #55: freeze the overworld the instant the battle is accepted, so NPCs/opponents can't
		# keep wandering (and drift away from the player) during the 0.5s fade before the intro loads.
		_freeze_overworld_actors()

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
	# Juice result chain: greeting → "delicious..." message → optional coin reveal
	if not _pending_juice_result.is_empty():
		var jr = _pending_juice_result
		_pending_juice_result = {}
		# If a coin was won, queue the gift reveal to fire on the NEXT OK press
		if jr["reward_coin"] != "":
			_prepare_gift_display("coin", jr["reward_coin"])
		_show_message_with_ok(jr["text"])
		return

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

	# One-shot interactable callback (e.g. multi-step starter box sequence)
	if _pending_ok_action.is_valid():
		var cb := _pending_ok_action
		_pending_ok_action = Callable()
		cb.call()
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
	if message_panel.visible or _validation_popup_active:
		return
	current_npc = npc

	npc.pause_and_face(_player.global_position)
	# ISSUE #57: the player also turns to face the NPC being talked to.
	_face_player_toward_actor(npc)

	# Shop NPC: delegate entirely to its own state machine
	if npc.npc_type == "shop" and npc.has_method("on_interact"):
		npc.refresh_bubble()
		var handled = npc.on_interact()
		if handled:
			return
		# on_interact() returned false → open pack purchase
		_show_message_with_choices(npc.meet_text)
		return

	# Juice vendor: tiered coin lottery, $50/cup ($25 after all 3 coins won)
	if npc.npc_type == "juice_vendor":
		npc.refresh_bubble()
		_show_cash_overlay()
		_show_message_with_choices(_juice_greeting_text())
		return

	# Costume-gated NPC: special greeting + gift only while the player wears
	# the required costume. Checked before the generic gift path because such
	# NPCs also carry a gift_type.
	if npc.required_costume != "":
		_handle_costume_gated_npc(npc)
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
# COSTUME-GATED NPCs
# ============================================================

# Reads the player's currently-equipped costume sprite from
# Player_Current_Data.json (the "sprite" field, no extension).
func _player_worn_sprite() -> String:
	var f := FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return String(parsed.get("sprite", ""))
	return ""

# Handles an NPC with a required_costume. The player gets the special
# greeting + gift only while wearing that costume; otherwise it's an
# ordinary text interaction with no gift (they can return later).
func _handle_costume_gated_npc(npc: Node) -> void:
	var was_met: bool = npc.has_been_met()
	var worn: String = _player_worn_sprite().strip_edges().to_lower()
	var required: String = String(npc.required_costume).strip_edges().to_lower()
	var matches: bool = worn != "" and worn == required

	npc.mark_as_met()
	npc.refresh_bubble()

	if matches and npc.is_gift_npc() and not npc.has_gift_been_given():
		# Right costume, gift not yet collected — hand it over.
		_give_gift(npc)
		npc.refresh_bubble()
		_prepare_gift_display(npc.gift_type, npc.gift_value)
		_show_message_with_ok(npc.costume_match_text)
		return

	if matches:
		# Right costume, but the gift was already collected (or none exists).
		var matched_txt: String = npc.costume_match_text if npc.costume_match_text != "" else npc.meet_text
		_show_message_with_ok(matched_txt)
		return

	# Wrong / no costume — ordinary chatter, no gift handed over.
	var plain_txt: String = npc.repeat_text if (was_met and npc.repeat_text != "") else npc.meet_text
	_show_message_with_ok(plain_txt)

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
		# ISSUE #104: gift notices use the big centred style, matching the starter box upstairs.
		_show_large_message_with_ok(text)
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

	# Show the message panel WITHOUT the OK button — animation must complete first.
	# ISSUE #104 FIX ACTIVE: "You received the X" now uses the same large centred style as the
	# starter box upstairs (_show_large_message_with_ok) instead of ordinary 28pt dialogue.
	print("ISSUE #104 FIX ACTIVE: gift notice shown at large size — ", text)
	_show_large_message_with_ok(text)
	ok_button.visible = false

	# ── PASS 4: Kick off reveal animations (parallel) ──
	# ISSUE #33: allow a click to skip the reveal. Reset skip state and let the dim overlay catch clicks.
	_gift_reveal_active = true
	_gift_reveal_skip = false
	_gift_reveal_tweens.clear()
	_gift_reveal_finals.clear()
	if _gift_dim_overlay != null and is_instance_valid(_gift_dim_overlay):
		_gift_dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		if not _gift_dim_overlay.gui_input.is_connected(_on_gift_reveal_input):
			_gift_dim_overlay.gui_input.connect(_on_gift_reveal_input)

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

	# Wait for the longest animation to complete (scaled by item animation speed) OR a skip click.
	var total_duration: float = 0.0
	if kind == "costume":
		total_duration = GIFT_COSTUME_TOTAL_DURATION
	elif kind == "card" or kind == "coin":
		total_duration = GIFT_FLIP_TOTAL_DURATION
	total_duration = GameState.item_time(total_duration)  # ISSUE #34
	if total_duration > 0.0:
		var elapsed: float = 0.0
		while elapsed < total_duration and not _gift_reveal_skip:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
	if _gift_reveal_skip:
		_finalize_gift_reveal()
	_gift_reveal_active = false
	# After awaiting, the player may have already dismissed (e.g. via cleanup).
	# Only reveal OK if the message is still on screen.
	if message_panel.visible and ok_button != null:
		ok_button.visible = true

# ISSUE #33: a click anywhere on the dim overlay during the reveal skips the animation.
func _on_gift_reveal_input(event: InputEvent) -> void:
	if not _gift_reveal_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_gift_reveal_skip = true

# Kills any running reveal tweens and snaps every rect to its finished state.
func _finalize_gift_reveal() -> void:
	for t in _gift_reveal_tweens:
		if t != null and t.is_valid():
			t.kill()
	_gift_reveal_tweens.clear()
	for f in _gift_reveal_finals:
		var rect = f["rect"]
		if rect != null and is_instance_valid(rect):
			if f["texture"] != null:
				rect.texture = f["texture"]
			rect.scale = Vector2(1.0, 1.0)
			rect.modulate = f["modulate"]
	_gift_reveal_finals.clear()

# Removes the gift display container and dim overlay if they exist.
func _clear_gift_display() -> void:
	# ISSUE #33: tear down any in-flight reveal-skip state.
	_gift_reveal_active = false
	_gift_reveal_skip = false
	_gift_reveal_tweens.clear()
	_gift_reveal_finals.clear()
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

	# ISSUE #33: register the final state so a skip can snap straight to the revealed face.
	_gift_reveal_finals.append({"rect": rect, "texture": target_tex, "modulate": Color(1, 1, 1, 1)})

	var shrink_durations := [0.01, 0.02, 0.04, 0.06, 0.08, 0.1, 0.11, 0.12, 0.2]
	# After each shrink, swap to the alternating texture
	var swaps := [target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex, back_tex, target_tex]

	# ISSUE #34: scale each flip step by the overworld animation-speed multiplier.
	var tween := create_tween()
	_gift_reveal_tweens.append(tween)   # ISSUE #33: killable on skip
	for i in shrink_durations.size():
		var d: float = GameState.item_time(shrink_durations[i])
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
	# ISSUE #33: register final state for skip.
	_gift_reveal_finals.append({"rect": rect, "texture": rect.texture, "modulate": Color(1, 1, 1, 1)})
	rect.modulate = Color(0, 0, 0, 1)  # fully black, opaque
	await get_tree().create_timer(GameState.item_time(0.5)).timeout
	if rect == null or not is_instance_valid(rect):
		return
	var tween := create_tween()
	_gift_reveal_tweens.append(tween)   # ISSUE #33: killable on skip
	tween.tween_property(rect, "modulate", Color(1, 1, 1, 1), GameState.item_time(1.0))

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
# Reorders colour to front and appends "Coin", number goes last.
#   "Arcanine Red"         -> "Red Arcanine Coin"
#   "Pikachu Silver 2"     -> "Silver Pikachu Coin 2"
#   "Team Plasma Silver 2" -> "Silver Team Plasma Coin 2"
# ============================================================

func _format_coin_name(raw: String) -> String:
	var base    := raw.trim_suffix(".png")
	var is_rare := false
	for prefix in ["Zzzz ", "Zzz ", "Zz "]:
		if base.begins_with(prefix):
			base = base.trim_prefix(prefix)
			is_rare = true
			break
	var words   := base.split(" ")
	var colours := ["red", "blue", "gold", "silver", "green", "black", "purple",
					"pink", "brown", "yellow", "orange", "white"]
	var colour     := ""
	var number     := ""
	var name_parts : Array = []
	var i := words.size() - 1
	if i >= 0 and words[i].is_valid_int():
		number = words[i]
		i -= 1
	if i >= 0 and words[i].to_lower() in colours:
		colour = words[i]
		i -= 1
	for j in range(i + 1):
		name_parts.append(words[j])
	var pieces : Array = []
	if is_rare:
		pieces.append("Rare")
	if colour != "":
		pieces.append(colour)
	pieces.append_array(name_parts)
	pieces.append("Coin")
	if number != "":
		pieces.append(number)
	return " ".join(pieces)

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
	# The outro scene clears battle_result before returning to signal that it
	# already showed the win/loss dialogue — skip it here to avoid a duplicate.
	if GameState.battle_result == "":
		GameState.returning_from_battle = false
		return

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

# ============================================================
# JUICE VENDOR
# Tiered coin lottery sold by the Juicebar Woman.
#   tier 1 (no silver yet) — Munchlax Silver,  40% per cup, pity at 3
#   tier 2 (silver only)   — Munchlax Gold,    30% per cup, pity at 3
#   tier 3 (silver+gold)   — Zz Munchlax Blue, 25% per cup, pity at 5
#   tier 4 (all 3 won)     — no rewards, juice is half price
# ============================================================

func _juice_current_tier() -> String:
	if not GameState.has_coin(JUICE_COIN_SILVER):
		return "silver"
	if not GameState.has_coin(JUICE_COIN_GOLD):
		return "gold"
	if not GameState.has_coin(JUICE_COIN_BLUE):
		return "blue"
	return "done"

func _juice_current_cost() -> int:
	return JUICE_COST_DISCOUNT if _juice_current_tier() == "done" else JUICE_COST

# Greeting text depends on which coins the player has already won.
func _juice_greeting_text() -> String:
	match _juice_current_tier():
		"silver":
			return "Welcome! Would you like a cup of juice? Just $" + str(JUICE_COST) + "!"
		"gold":
			return "You won a Silver Munchlax coin? Well done! Would you like a chance at another coin with another cup?"
		"blue":
			return "Wow you won both the silver and gold munchlax huh? You've only the Rare coin to find now! Would you like another cup?"
		_:
			return "Wow no way, you're so lucky, you've won all 3 juice coins! Congrats!!! Thanks for your ongoing support at our Juice bar! While we don't have any new coins for you to win, you do get 50% off all future juice!"

# Called when the player clicks Yes on the juice greeting.
# Runs the per-tier roll (with pity), deducts cash, awards the coin if any,
# and queues _pending_juice_result so the next OK press shows the result + reveal.
func _handle_juice_purchase() -> void:
	var cost: int = _juice_current_cost()
	if GameState.get_cash() < cost:
		_show_message_with_ok(JUICE_BROKE_MSG)
		return

	GameState.add_cash(-cost)

	var tier: String = _juice_current_tier()
	var reward: String = ""

	match tier:
		"silver":
			var attempts_s: int = int(GameState.progress.get("juice_silver_attempts", 0)) + 1
			GameState.progress["juice_silver_attempts"] = attempts_s
			if randi() % 100 < JUICE_SILVER_CHANCE or attempts_s >= JUICE_SILVER_PITY:
				reward = JUICE_COIN_SILVER
		"gold":
			var attempts_g: int = int(GameState.progress.get("juice_gold_attempts", 0)) + 1
			GameState.progress["juice_gold_attempts"] = attempts_g
			if randi() % 100 < JUICE_GOLD_CHANCE or attempts_g >= JUICE_GOLD_PITY:
				reward = JUICE_COIN_GOLD
		"blue":
			var attempts_b: int = int(GameState.progress.get("juice_blue_attempts", 0)) + 1
			GameState.progress["juice_blue_attempts"] = attempts_b
			if randi() % 100 < JUICE_BLUE_CHANCE or attempts_b >= JUICE_BLUE_PITY:
				reward = JUICE_COIN_BLUE
		_:
			# tier == "done" — no reward possible, just enjoy the cheap juice
			pass

	if reward != "":
		GameState.add_coin_to_collection(reward)
		_pending_juice_result = {"text": JUICE_COIN_MSG, "reward_coin": reward}
	else:
		_pending_juice_result = {"text": JUICE_NORMAL_MSG, "reward_coin": ""}

	_update_cash_overlay()
	GameState.save_progress()

	# Chain to the result message via the existing OK pipeline
	_on_ok_pressed()

# ============================================================
# CASH OVERLAY
# Mirrors Card_Mart._create_cash_label position/style. Created on demand when
# talking to the juice vendor; removed in _hide_message().
# ============================================================

func _show_cash_overlay() -> void:
	if _cash_overlay != null and is_instance_valid(_cash_overlay):
		_update_cash_overlay()
		return
	_cash_overlay = Label.new()
	_cash_overlay.name = "JuiceCashOverlay"
	_cash_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cash_overlay.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_cash_overlay.add_theme_font_size_override("font_size", 18)
	_cash_overlay.add_theme_color_override("font_color", Color.WHITE)
	_cash_overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cash_overlay.add_theme_constant_override("shadow_offset_x", 1)
	_cash_overlay.add_theme_constant_override("shadow_offset_y", 1)
	_cash_overlay.anchor_left   = 1.0
	_cash_overlay.anchor_top    = 1.0
	_cash_overlay.anchor_right  = 1.0
	_cash_overlay.anchor_bottom = 1.0
	_cash_overlay.offset_left   = -160
	_cash_overlay.offset_top    = -40
	_cash_overlay.offset_right  = -10
	_cash_overlay.offset_bottom = -10
	_ui_layer.add_child(_cash_overlay)
	_update_cash_overlay()

func _update_cash_overlay() -> void:
	if _cash_overlay != null and is_instance_valid(_cash_overlay):
		_cash_overlay.text = "Cash: $" + str(GameState.get_cash())

func _hide_cash_overlay() -> void:
	if _cash_overlay != null and is_instance_valid(_cash_overlay):
		_cash_overlay.queue_free()
	_cash_overlay = null

# ============================================================
# DECK VALIDATION (opponent restrictions)
# ============================================================

func _current_player_deck_path() -> String:
	var f := FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return ""
	var deck_name := String(parsed.get("deck", ""))
	if deck_name == "":
		return ""
	return "user://Player_Decks/" + deck_name + ".json"

# Called when the player's deck fails validation against the opponent's
# restrictions. Picks the most useful display flavour and shows it,
# then releases all interaction state once the popup is closed.
#
# mode == "banned"  → grid of the NPC's banlist           (title: "Banned cards")
# mode == "invalid" → grid of player's offending cards    (title: "Cards in your deck that aren't allowed")
# mode == "missing" → text-only message via the messagebox (no grid)
func _handle_deck_validation_failure(v_result: Dictionary) -> void:
	var mode := String(v_result.get("mode", ""))

	# Missing-only failure: re-use the standard messagebox with OK.
	if mode == "missing":
		var lines: Array = v_result.get("missing_lines", [])
		var body := "You can't battle me yet:\n\n" + "\n".join(lines)
		_show_message_with_ok(body)
		return

	# Banned / invalid → hide the Yes/No box and open the card-grid popup.
	message_panel.visible = false
	_validation_popup_active = true

	var title := ""
	var card_ids: Array = []
	var rule_lines: Array = v_result.get("rule_lines", [])
	var body_lines: Array = []
	for ln in rule_lines:
		body_lines.append(String(ln))

	if mode == "banned":
		title = "Banned cards"
		card_ids = v_result.get("banned_cards", [])
		if body_lines.is_empty():
			body_lines = ["These cards aren't allowed in your deck for this battle."]
	else:
		title = "Cards in your deck that aren't allowed"
		card_ids = v_result.get("invalid_cards", [])

	# If there are also missing-requirement lines, append them so the player
	# sees the full picture in one popup.
	var missing_lines: Array = v_result.get("missing_lines", [])
	for ml in missing_lines:
		body_lines.append(String(ml))

	var on_closed := Callable(self, "_on_validation_popup_closed")
	_validation_popup_node = DeckValidationPopup.show_popup(
		_ui_layer, title, card_ids, body_lines, on_closed
	)

func _on_validation_popup_closed() -> void:
	_validation_popup_active = false
	_validation_popup_node = null
	# Roll the player and opponent back to free-roam — same cleanup as
	# pressing "No" on the original challenge dialog.
	_hide_message()

# ============================================================
# DEBUG / TESTING CHEATS (overworld only)
# ------------------------------------------------------------
# Number row 1-9 set the in-game date to that value; 0 sets date 10.
# M / A / E / N set the time of day to Morning / Afternoon / Evening / Night.
# Any of those date/time keys also resets the current-period defeated
# count to 0, then reloads the active map scene in place so its
# date/time NPC & opponent JSON is reloaded — handy for sweeping
# through all 30 day/time placements without restarting the game.
# The player is restored to the exact spot they were standing.
#
# C bumps the current-period defeated count (opponents_beaten_count_current)
# by 1 and flashes a large on-screen label for 2s. This is the same count
# the outro reads to auto-advance time at 3 wins, so pressing C to 2 then
# winning a real battle (→3) exercises the genuine time-advance path.
#
# Lives here in the MapManager autoload so it applies to every map
# scene without per-scene duplication. Guarded twice: it fires ONLY in
# overworld map scenes, so it never interferes with battles/menus, and
# ONLY while DebugMode.is_enabled() (Debug_Mode.gd), so a release build
# has no cheat keys at all.
# ============================================================

const _MAP_SCENES_PREFIX := "res://Scenes/Map_Scenes/"

var _debug_defeated_label: Label = null
var _debug_label_token: int = 0
var _debug_cash_label: Label = null
var _debug_cash_token: int = 0

func _unhandled_input(event: InputEvent) -> void:
	# Developer-only. Without this gate an exported build lets anyone press C to
	# advance the time-of-day loop, P/O to mint cash, T to launch a test match and
	# the number/letter rows to set the date and time. See Debug_Mode.gd for how
	# debug mode is switched on and off — in the editor it is always on.
	if not DebugMode.is_enabled():
		return

	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return

	var current := get_tree().current_scene
	if current == null:
		return
	if not String(current.scene_file_path).begins_with(_MAP_SCENES_PREFIX):
		return

	# C — bump the defeated count and flash the label. No reset, no reload.
	if event.keycode == KEY_C:
		GameState.progress["opponents_beaten_count_current"] = GameState.get_current_defeated() + 1
		GameState.save_progress()
		print("DEBUG: opponents defeated = ", GameState.get_current_defeated())
		get_viewport().set_input_as_handled()
		_debug_flash_defeated_count()
		return

	# P / O — adjust cash by ±200 and flash the delta.
	if event.keycode == KEY_P:
		GameState.add_cash(200)
		print("DEBUG: cash = ", GameState.get_cash())
		get_viewport().set_input_as_handled()
		_debug_flash_cash(200)
		return
	if event.keycode == KEY_O:
		GameState.add_cash(-200)
		print("DEBUG: cash = ", GameState.get_cash())
		get_viewport().set_input_as_handled()
		_debug_flash_cash(-200)
		return

	# T — jump straight into a TEST match: both player and opponent use the
	# "TEST" deck in user://Player_Decks/. No NPC data needed.
	if event.keycode == KEY_T:
		get_viewport().set_input_as_handled()
		_start_test_match(current)
		return

	var new_date: int = -1
	var new_time: String = ""

	match event.keycode:
		KEY_1, KEY_KP_1: new_date = 1
		KEY_2, KEY_KP_2: new_date = 2
		KEY_3, KEY_KP_3: new_date = 3
		KEY_4, KEY_KP_4: new_date = 4
		KEY_5, KEY_KP_5: new_date = 5
		KEY_6, KEY_KP_6: new_date = 6
		KEY_7, KEY_KP_7: new_date = 7
		KEY_8, KEY_KP_8: new_date = 8
		KEY_9, KEY_KP_9: new_date = 9
		KEY_0, KEY_KP_0: new_date = 10
		KEY_MINUS:       new_date = 11
		KEY_EQUAL:       new_date = 12
		KEY_BRACKETLEFT: new_date = 0  # Date 0 = match-effects test day (Celeste_Harbour_0_Morning.json)
		KEY_H: new_time = "Morning"
		KEY_J: new_time = "Afternoon"
		KEY_K: new_time = "Evening"
		KEY_L: new_time = "Night"
		_: return

	if new_date != -1:
		GameState.progress["date"] = new_date
		print("DEBUG: date set to ", new_date)
	else:
		GameState.progress["time"] = new_time
		print("DEBUG: time set to ", new_time)
	# Changing date/time wipes the current-period defeated count, mirroring
	# what advance_time() does so testing always starts from a clean slate.
	GameState.progress["opponents_beaten_count_current"] = 0
	GameState.save_progress()

	get_viewport().set_input_as_handled()
	_debug_reload_map_in_place(current)

# Launches an instant TEST match from the overworld. Both the player and the
# opponent draw from user://Player_Decks/TEST.json, and the opponent's metadata
# is synthesized (no NPC JSON is consulted). Goes through the normal intro so
# all GameState transition fields are populated the same way a real battle sets
# them up.
func _start_test_match(current: Node) -> void:
	var deck_path := "user://Player_Decks/TEST.json"
	if not FileAccess.file_exists(deck_path):
		print("DEBUG: TEST match aborted — no deck at ", deck_path, " (create one in the deck builder named 'TEST')")
		_debug_flash_defeated_label_text("No TEST deck found!")
		return

	# Capture the player's current spot so returning from the match lands here.
	var pos: Vector2 = _player.position if _player != null else Vector2.ZERO
	var player := current.get_node_or_null("Player")
	if player is Node2D:
		pos = player.position

	GameState.test_match_mode            = true
	GameState.current_opponent_name      = "TEST OPPONENT"
	GameState.current_opponent_deck      = "TEST"
	GameState.current_opponent_json_path = ""
	GameState.player_position            = pos
	GameState.returning_from_battle      = false
	GameState.return_map_scene_path      = _map_scene_path
	GameState.last_battled_opponent_entry = GameState.build_test_opponent_data()
	GameState.clear_match_series()

	print("DEBUG: launching TEST match (player + opponent both use 'TEST' deck)")

	_hide_message()
	SoundManagerScript.stop_bgm()

	var overlay = ColorRect.new()
	overlay.color   = Color(0, 0, 0, 0)
	overlay.size    = Vector2(1920, 1080)
	overlay.z_index = 100
	current.add_child(overlay)

	var tween = current.create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.5)
	await tween.finished
	SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Match_Start_Intro_Scene.tscn")

# Reloads the supplied map scene, restoring the player to their current
# spot/direction via the same menu-return path every map scene honours
# in its _ready().
func _debug_reload_map_in_place(current: Node) -> void:
	var scene_path := String(current.scene_file_path)
	var pos: Vector2 = Vector2.ZERO
	var dir: String = "down"
	var player := current.get_node_or_null("Player")
	if player is Node2D:
		pos = player.position
		if player.has_method("get_current_direction"):
			dir = player.get_current_direction()

	GameState.save_menu_return_state(scene_path, pos, dir)
	SceneCache.change_scene(scene_path)

# Shows a big "Opponents defeated: N" label on the current scene's UI layer
# for 2 seconds. Re-pressing C refreshes the text and restarts the timer.
func _debug_flash_defeated_count() -> void:
	if _ui_layer == null or not is_instance_valid(_ui_layer):
		return

	if _debug_defeated_label == null or not is_instance_valid(_debug_defeated_label):
		_debug_defeated_label = Label.new()
		_debug_defeated_label.name = "DebugDefeatedLabel"
		_debug_defeated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_debug_defeated_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		_debug_defeated_label.add_theme_font_size_override("font_size", 72)
		_debug_defeated_label.add_theme_color_override("font_color", Color.WHITE)
		_debug_defeated_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_defeated_label.add_theme_constant_override("outline_size", 12)
		_debug_defeated_label.anchor_left   = 0.0
		_debug_defeated_label.anchor_right  = 1.0
		_debug_defeated_label.anchor_top    = 0.0
		_debug_defeated_label.anchor_bottom = 0.0
		_debug_defeated_label.offset_top    = 80
		_debug_defeated_label.offset_bottom = 200
		_debug_defeated_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		_ui_layer.add_child(_debug_defeated_label)

	_debug_defeated_label.text = "Opponents defeated: " + str(GameState.get_current_defeated())
	_debug_flash_defeated_label_finish()

# Flashes arbitrary text using the same big centred label as the defeated counter.
func _debug_flash_defeated_label_text(text: String) -> void:
	if _ui_layer == null or not is_instance_valid(_ui_layer):
		return
	if _debug_defeated_label == null or not is_instance_valid(_debug_defeated_label):
		_debug_flash_defeated_count()
	_debug_defeated_label.text = text
	_debug_flash_defeated_label_finish()

# Shared 2-second teardown timer (token pattern) for the defeated label.
func _debug_flash_defeated_label_finish() -> void:
	_debug_label_token += 1
	var my_token: int = _debug_label_token
	await get_tree().create_timer(2.0).timeout
	# Only the most recent C press tears the label down, so rapid presses
	# keep it visible and just reset the 2s countdown.
	if my_token == _debug_label_token and _debug_defeated_label != null and is_instance_valid(_debug_defeated_label):
		_debug_defeated_label.queue_free()
		_debug_defeated_label = null

# Shows a "+200 Cash" / "-200 Cash" label for 2 seconds. Same token pattern as above.
func _debug_flash_cash(delta: int) -> void:
	if _ui_layer == null or not is_instance_valid(_ui_layer):
		return

	if _debug_cash_label == null or not is_instance_valid(_debug_cash_label):
		_debug_cash_label = Label.new()
		_debug_cash_label.name = "DebugCashLabel"
		_debug_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_debug_cash_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		_debug_cash_label.add_theme_font_size_override("font_size", 72)
		_debug_cash_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_cash_label.add_theme_constant_override("outline_size", 12)
		_debug_cash_label.anchor_left   = 0.0
		_debug_cash_label.anchor_right  = 1.0
		_debug_cash_label.anchor_top    = 0.0
		_debug_cash_label.anchor_bottom = 0.0
		_debug_cash_label.offset_top    = 280
		_debug_cash_label.offset_bottom = 400
		_debug_cash_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		_ui_layer.add_child(_debug_cash_label)

	var prefix := "+" if delta > 0 else ""
	_debug_cash_label.text = prefix + str(delta) + " Cash  (Total: " + str(GameState.get_cash()) + ")"
	_debug_cash_label.add_theme_color_override("font_color", Color.GREEN if delta > 0 else Color.RED)

	_debug_cash_token += 1
	var my_token: int = _debug_cash_token
	await get_tree().create_timer(2.0).timeout
	if my_token == _debug_cash_token and _debug_cash_label != null and is_instance_valid(_debug_cash_label):
		_debug_cash_label.queue_free()
		_debug_cash_label = null
