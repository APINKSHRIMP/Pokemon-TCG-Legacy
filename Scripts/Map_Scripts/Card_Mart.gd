extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Card_Mart.tscn"
const NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Card_Mart_NPCs.json"

var cash_label: Label = null

func _ready():
	SoundManagerScript.play_bgm("res://Audio/BGM/Shop1.ogg", true)

	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask  = 2
	$"Door Areas".monitoring      = true
	$"Door Areas".monitorable     = true
	$"Door Areas".body_entered.connect(_on_door_entered)

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.use_spawn_position:
		$Player.position = GameState.spawn_position
		GameState.use_spawn_position = false
		$Player.set_direction(GameState.get_player_direction())
	else:
		$Player.position = Vector2(208, 172)
		$Player.set_direction(GameState.get_player_direction())

	# Hide starter set if already collected
	if GameState.progress.get("player_collected_shop_starter_set", false):
		_remove_starter_set()

	_create_cash_label()
	_update_cash_label()

	MapManager.initialise($Player, $NPCS, $UILAYER, "", [], "", NPC_JSON_PATH, [])

	_apply_moving_in_visibility()

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _exit_tree():
	if cash_label != null and is_instance_valid(cash_label):
		cash_label.queue_free()
		cash_label = null

# ============================================================
# CASH LABEL
# ============================================================

func _create_cash_label():
	cash_label = Label.new()
	cash_label.name = "CashLabel"
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	cash_label.add_theme_font_size_override("font_size", 18)
	cash_label.add_theme_color_override("font_color", Color.WHITE)
	cash_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	cash_label.add_theme_constant_override("shadow_offset_x", 1)
	cash_label.add_theme_constant_override("shadow_offset_y", 1)
	cash_label.anchor_left   = 1.0
	cash_label.anchor_top    = 1.0
	cash_label.anchor_right  = 1.0
	cash_label.anchor_bottom = 1.0
	cash_label.offset_left   = -160
	cash_label.offset_top    = -40
	cash_label.offset_right  = -10
	cash_label.offset_bottom = -10
	$UILAYER.add_child(cash_label)

func _update_cash_label():
	if cash_label == null:
		return
	cash_label.text = "Cash: $" + str(GameState.get_cash())

# ============================================================
# STARTER SET VISUAL
# Called by Shopkeeper_Script after purchase to remove the node
# ============================================================

func _remove_starter_set():
	var starter = $MART.get_node_or_null("Starter_Set")
	if starter != null:
		starter.queue_free()

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
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
		var is_escape: bool = event.keycode == KEY_ESCAPE
		if not (is_enter or is_escape):
			return
		if is_enter and MapManager.message_panel != null and MapManager.message_panel.visible:
			return
		get_viewport().set_input_as_handled()
		GameState.save_menu_return_state(SCENE_PATH, $Player.position, $Player.get_current_direction())
		SoundManagerScript.stop_bgm()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")

# ============================================================
# DOOR LOGIC
# ============================================================

func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var door_area = $"Door Areas"
	var nearest_shape = null
	var nearest_dist  = INF
	for child in door_area.get_children():
		if child is CollisionShape2D:
			var dist = child.global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist  = dist
				nearest_shape = child

	if nearest_shape == null:
		return

	var target = nearest_shape.get_meta("target_scene")
	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	if target.contains("Upstairs"):
		GameState.spawn_position    = Vector2(55, 25)
		GameState.use_spawn_position = true
	else:
		GameState.use_spawn_position = false

	var fade_tween = create_tween()
	fade_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	fade_tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
