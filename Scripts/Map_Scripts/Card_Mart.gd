extends Node2D

const NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Card_Mart_NPCs.json"
const PROGRESS_PATH = "user://player_game_progress.json"
const STARTER_SET_COST = 500

var progress_data: Dictionary = {}
var cash_label: Label = null

func _ready():
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop1.ogg", true)

	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask = 2
	$"Door Areas".monitoring = true
	$"Door Areas".monitorable = true
	$Player.set_direction(GameState.get_player_direction())
	$"Door Areas".body_entered.connect(_on_door_entered)

	if GameState.use_spawn_position:
		$Player.position = GameState.spawn_position
		GameState.use_spawn_position = false
	else:
		$Player.position = Vector2(208, 172)

	# Load progress data
	_load_progress()

	# Hide starter set if already collected
	if progress_data.get("player_collected_shop_starter_set", false):
		_remove_starter_set()

	# Set up cash display
	_create_cash_label()
	_update_cash_label()

	# Register shop callback so MapManager defers to us for shop NPC logic
	MapManager.shop_callback = _on_shop_interact

	MapManager.initialise($Player, $NPCS, $UILAYER, "", [], "", NPC_JSON_PATH, [])

	_apply_moving_in_visibility()

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _exit_tree():
	# Clean up callback so other maps don't use our shop logic
	MapManager.shop_callback = Callable()
	if cash_label != null and is_instance_valid(cash_label):
		cash_label.queue_free()
		cash_label = null

# ============================================================
# PROGRESS FILE
# ============================================================

func _load_progress():
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("Card_Mart: Cannot open progress file: " + PROGRESS_PATH)
		progress_data = {}
		return
	progress_data = JSON.parse_string(file.get_as_text())
	file.close()
	if progress_data == null:
		progress_data = {}

func _save_progress():
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Card_Mart: Cannot write progress file: " + PROGRESS_PATH)
		return
	file.store_string(JSON.stringify(progress_data, "\t"))
	file.close()

# ============================================================
# CASH LABEL (bottom-right of screen on UILAYER)
# ============================================================

func _create_cash_label():
	cash_label = Label.new()
	cash_label.name = "CashLabel"
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cash_label.add_theme_font_size_override("font_size", 18)
	cash_label.add_theme_color_override("font_color", Color.WHITE)
	cash_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	cash_label.add_theme_constant_override("shadow_offset_x", 1)
	cash_label.add_theme_constant_override("shadow_offset_y", 1)
	cash_label.anchor_left = 1.0
	cash_label.anchor_top = 1.0
	cash_label.anchor_right = 1.0
	cash_label.anchor_bottom = 1.0
	cash_label.offset_left = -160
	cash_label.offset_top = -40
	cash_label.offset_right = -10
	cash_label.offset_bottom = -10
	$UILAYER.add_child(cash_label)

func _update_cash_label():
	if cash_label == null:
		return
	var cash_val = progress_data.get("cash", 0)
	cash_label.text = "Cash: $" + str(int(cash_val))

# ============================================================
# STARTER SET
# ============================================================

func _remove_starter_set():
	var starter = $MART.get_node_or_null("Starter_Set")
	if starter != null:
		starter.queue_free()

# ============================================================
# SHOP INTERACTION CALLBACK
# ============================================================
# MapManager calls this instead of its default shop flow.
# Return true = we handled it, false = let MapManager do default.

func _on_shop_interact(npc: Node) -> bool:
	# Reload progress each interaction to stay current
	_load_progress()
	_update_cash_label()

	var collected_starter = progress_data.get("player_collected_shop_starter_set", false)
	var packs_unlocked = progress_data.get("packs_unlocked", [])

	# Case 1: Starter set not yet collected — offer to buy it
	if not collected_starter:
		var player_cash = progress_data.get("cash", 0)
		if player_cash < STARTER_SET_COST:
			MapManager._show_message_with_ok("You need $" + str(STARTER_SET_COST) + " for this box. You don't have enough cash!")
			return true
		# Show yes/no prompt for starter set purchase
		MapManager._show_message_with_choices("I need $" + str(STARTER_SET_COST) + " for this box")
		# Override yes button to our starter purchase logic
		_connect_starter_purchase()
		return true

	# Case 2: Starter collected but no packs unlocked
	if packs_unlocked.is_empty():
		MapManager._show_message_with_ok("I have no packs")
		return true

	# Case 3: Starter collected and packs exist — default shop flow
	return false

# ============================================================
# STARTER SET PURCHASE FLOW
# ============================================================

var _yes_connection_active := false

func _connect_starter_purchase():
	# Temporarily disconnect MapManager's yes handler and connect ours
	if MapManager.yes_button.pressed.is_connected(MapManager._on_yes_pressed):
		MapManager.yes_button.pressed.disconnect(MapManager._on_yes_pressed)
	if not MapManager.yes_button.pressed.is_connected(_on_starter_yes):
		MapManager.yes_button.pressed.connect(_on_starter_yes)
	if not MapManager.no_button.pressed.is_connected(_on_starter_no):
		if MapManager.no_button.pressed.is_connected(MapManager._on_no_pressed):
			MapManager.no_button.pressed.disconnect(MapManager._on_no_pressed)
		MapManager.no_button.pressed.connect(_on_starter_no)
	_yes_connection_active = true

func _restore_yes_connection():
	if _yes_connection_active:
		if MapManager.yes_button.pressed.is_connected(_on_starter_yes):
			MapManager.yes_button.pressed.disconnect(_on_starter_yes)
		if MapManager.yes_button.pressed.is_connected(_on_starter_no):
			pass
		if MapManager.no_button.pressed.is_connected(_on_starter_no):
			MapManager.no_button.pressed.disconnect(_on_starter_no)
		if not MapManager.yes_button.pressed.is_connected(MapManager._on_yes_pressed):
			MapManager.yes_button.pressed.connect(MapManager._on_yes_pressed)
		if not MapManager.no_button.pressed.is_connected(MapManager._on_no_pressed):
			MapManager.no_button.pressed.connect(MapManager._on_no_pressed)
		_yes_connection_active = false

func _on_starter_yes():
	_restore_yes_connection()

	# Deduct cash
	var current_cash = progress_data.get("cash", 0)
	progress_data["cash"] = current_cash - STARTER_SET_COST

	# Mark starter as collected
	progress_data["player_collected_shop_starter_set"] = true

	# Save progress
	_save_progress()

	# Also update GameState.progress so it stays in sync
	GameState.progress["cash"] = progress_data["cash"]
	GameState.progress["player_collected_shop_starter_set"] = true

	# Remove the starter set visual
	_remove_starter_set()

	# Update cash display
	_update_cash_label()

	# Show confirmation message
	MapManager._hide_message()
	MapManager._show_message_with_ok("Thanks for buying the box!")

func _on_starter_no():
	_restore_yes_connection()
	MapManager._on_no_pressed()

# ============================================================
# MOVING IN VISIBILITY
# ============================================================

func _apply_moving_in_visibility():
	var moving_in_done = GameState.progress.get("moving_in_completed", false)
	if moving_in_done:
		for layer in $DOWNSTAIRS.get_children():
			if layer is TileMapLayer:
				layer.visible = layer.name != "Moving In"

# ============================================================
# DOOR LOGIC
# ============================================================

func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var door_area = $"Door Areas"
	var nearest_shape = null
	var nearest_dist = INF
	for child in door_area.get_children():
		if child is CollisionShape2D:
			var dist = child.global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_shape = child

	if nearest_shape == null:
		return

	var target = nearest_shape.get_meta("target_scene")

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	if target.contains("Upstairs"):
		GameState.spawn_position = Vector2(55, 25)
		GameState.use_spawn_position = true
	else:
		GameState.use_spawn_position = false

	var fade_tween = create_tween()
	fade_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	fade_tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
