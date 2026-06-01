extends Node2D

# ============================================================
# GYM CHALLENGE RECEPTION — interior
# Reached from Gym Plaza; leads onward to the Gym Challenge Hall.
# Hosts a shopkeeper and supports opponent/NPC spawning via the
# shared MapManager pipeline.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn"

# --- Tweakable -------------------------------------------------
# Placeholder interior BGM (shared shop track). Swap for a gym
# reception theme if one is added later.
const BGM_PATH = "res://Audio/BGM/Shop1.ogg"

# NPC_JSON_PATH is built dynamically in _ready() from the current game day
# and time-of-day. Naming convention: Gym_Challenge_Reception_{Time}_{Day}.json
var NPC_JSON_PATH: String = ""

# --- Door-return spawn points -------------------------------------------------
# Spawn point per scene the player can arrive from. The key is the value the
# source scene writes to GameState.entering_from.
#   from Gym Plaza — just inside the south door (DoorArea_Gym_Plaza).
#   from the Hall  — just inside the hall door (DoorArea_Gym_Plaza2).
const SPAWN_FROM_GYM_PLAZA          = Vector2(350, 450)
const SPAWN_FROM_GYM_CHALLENGE_HALL = Vector2(220, 45)
# ---------------------------------------------------------------

var cash_label: Label = null

func _ready():
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Gym_Challenge_Reception_" + time_of_day + "_" + str(date) + ".json"

	SoundManagerScript.play_bgm(BGM_PATH, true)

	var tween = create_tween()
	tween.tween_property(get_tree().root, "modulate", Color(1, 1, 1, 0), 0.0)

	$"Door Areas".collision_layer = 3
	$"Door Areas".collision_mask  = 2
	$"Door Areas".monitoring      = true
	$"Door Areas".monitorable     = true
	$"Door Areas".body_entered.connect(_on_door_entered)

	# Hard-coded spawn point per scene the player can arrive from. The key is
	# the value the source scene writes to GameState.entering_from.
	var entry_positions = {
		"Gym_Plaza":          SPAWN_FROM_GYM_PLAZA,
		"Gym_Challenge_Hall": SPAWN_FROM_GYM_CHALLENGE_HALL,
	}

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		# Returning from main menu (or splash-screen resume)
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.returning_from_battle:
		# Returning from a battle triggered by a reception opponent
		$Player.position = GameState.player_position
		$Player.set_direction(GameState.get_player_direction())
		GameState.returning_from_battle = false
	elif entry_positions.has(GameState.entering_from):
		# Returning from another scene through one of this scene's doors
		$Player.position = entry_positions[GameState.entering_from]
		$Player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
	else:
		# First load / fallback — treat as a cold arrival from the Gym Plaza
		$Player.position = SPAWN_FROM_GYM_PLAZA
		$Player.set_direction(GameState.get_player_direction())

	# Persist current location so the splash screen can resume here on next launch
	GameState.save_current_location(SCENE_PATH, $Player.position)

	# This interior has no opponent/NPC container in the .tscn — create one at
	# runtime so MapManager has somewhere to parent the shopkeeper and any
	# opponents/NPCs it spawns.
	var npc_container := Node2D.new()
	npc_container.name = "OPPONENTS"
	npc_container.z_index = 1
	add_child(npc_container)

	_create_cash_label()
	_update_cash_label()

	# A missing JSON is fine — MapManager spawns nothing until the file exists.
	# The same path feeds both the opponent and NPC loaders (one file, two arrays).
	var json := NPC_JSON_PATH if ResourceLoader.exists(NPC_JSON_PATH) else ""
	MapManager.initialise($Player, npc_container, $UILAYER, json, [], SCENE_PATH, json, [])

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

func _exit_tree():
	if cash_label != null and is_instance_valid(cash_label):
		cash_label.queue_free()
		cash_label = null

# ============================================================
# CASH LABEL
# Mirrors Card_Mart / Rocket_Mart — a persistent "Cash: $X"
# readout, useful next to the shopkeeper.
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
		GameState.save_current_location(SCENE_PATH, $Player.position)
		SoundManagerScript.stop_bgm()
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")

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

	# Both doors (out to the Gym Plaza, on to the Gym Challenge Hall) resolve
	# their spawn from a hard-coded table keyed on entering_from, so we just
	# announce our origin scene.
	GameState.entering_from = "Gym_Challenge_Reception"

	var fade_tween = create_tween()
	fade_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	fade_tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
