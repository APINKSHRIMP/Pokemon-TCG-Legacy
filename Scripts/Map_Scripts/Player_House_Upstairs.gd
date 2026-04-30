extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

# ── PLACEHOLDER: Replace with actual 60 card IDs ──
const STARTER_BOX_CARDS = "base1-43, base1-43, base1-43, base1-43, base1-47, base1-47, base1-47, base1-47, base1-27, base1-27, base1-52, base1-52, base1-52, base1-52, base1-61, base1-61,base1-61,base1-61,base1-67,base1-67,base1-67,base1-67,base1-88,base1-91,base1-94,base1-94"

var player_near_box: bool = false

func _ready():
	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)
	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask = 2
	$"Door Areas".monitoring = true
	$"Door Areas".monitorable = true
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
		$Player.position = Vector2(50, 25)
		$Player.set_direction(GameState.get_player_direction())

	MapManager.initialise($Player, Node2D.new(), $UILAYER, "", [], "")
	_apply_moving_in_visibility()

	if GameState.progress.get("player_collected_starter_box", false):
		$Starter_Box.visible = false

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _apply_moving_in_visibility():
	var moving_in_done = GameState.progress.get("moving_in_completed", false)
	if moving_in_done:
		for layer in $UPSTAIRS.get_children():
			if layer is TileMapLayer:
				layer.visible = layer.name != "Moving In"

func _physics_process(_delta):
	if $Starter_Box.visible and not GameState.progress.get("player_collected_starter_box", false):
		player_near_box = $Player.global_position.distance_to($Starter_Box.global_position) < 40.0
	else:
		player_near_box = false

func _process(_delta):
	if player_near_box and not MapManager.message_panel.visible and Input.is_action_just_pressed("ui_accept"):
		$Starter_Box.visible = false
		GameState.progress["player_collected_starter_box"] = true
		GameState.save_progress()
		GameState.give_cards(STARTER_BOX_CARDS)
		MapManager._show_message_with_ok("Pokemon Starter deck acquired!")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
		var is_escape: bool = event.keycode == KEY_ESCAPE
		if not (is_enter or is_escape):
			return
		if is_enter and MapManager.message_panel != null and MapManager.message_panel.visible:
			return
		# Don't open the menu when the player is opening the starter box —
		# Enter / Space near the box is reserved for that interaction
		if is_enter and player_near_box and not GameState.progress.get("player_collected_starter_box", false):
			return
		get_viewport().set_input_as_handled()
		GameState.save_menu_return_state(SCENE_PATH, $Player.position, $Player.get_current_direction())
		SoundManagerScript.stop_bgm()
		get_tree().change_scene_to_file("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var shape_node = $"Door Areas".get_child(0)
	var target = shape_node.get_meta("target_scene")

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()

	GameState.spawn_position = Vector2(360, 15)
	GameState.use_spawn_position = true

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target)
	)
