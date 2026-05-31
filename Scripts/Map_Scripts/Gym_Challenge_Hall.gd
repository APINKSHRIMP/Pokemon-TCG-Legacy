extends Node2D

# ============================================================
# GYM CHALLENGE HALL — interior
# Reached from the Gym Challenge Reception; this is the hall
# where the gym challenge opponents are battled. The single door
# leads back to the reception. Like every map script, this scene
# resolves its spawn from a hard-coded table keyed on the origin
# scene the player came from (GameState.entering_from).
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Hall.tscn"

# --- Tweakable -------------------------------------------------
# Interior BGM — the Makuhita Dojo theme suits a gym challenge
# hall. Swap for a dedicated track if one is added later.
const BGM_PATH = "res://Audio/BGM/024_Makuhita_Dojo_PMD_Blue_Rescue_Team_OST.ogg"

# Opponents + NPCs load from this file. It does not exist yet —
# a missing file is handled silently. When authored it must
# contain both an "opponents" and an "npcs" array (either may be
# empty) — that's the MapManager convention. The same path feeds
# both the opponent and NPC loaders (one file, two arrays).
const NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Gym_Challenge_Hall_Day_9.json"

# --- Door-return spawn point --------------------------------------------------
# The single door leads back to the Gym Challenge Reception, so the player
# only ever arrives here from one scene. Value matches the Player node in
# the .tscn — i.e. walking in from the reception.
const SPAWN_FROM_GYM_CHALLENGE_RECEPTION = Vector2(361, 467)
# ---------------------------------------------------------------

func _ready():
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
		"Gym_Challenge_Reception": SPAWN_FROM_GYM_CHALLENGE_RECEPTION,
	}

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		# Returning from main menu (or splash-screen resume)
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.returning_from_battle:
		# Returning from battle with a hall opponent
		$Player.position = GameState.player_position
		$Player.set_direction(GameState.get_player_direction())
		GameState.returning_from_battle = false
	elif entry_positions.has(GameState.entering_from):
		# Returning from another scene through one of this scene's doors
		$Player.position = entry_positions[GameState.entering_from]
		$Player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
	else:
		# First load / fallback — the only entrance is from the reception
		$Player.position = SPAWN_FROM_GYM_CHALLENGE_RECEPTION
		$Player.set_direction(GameState.get_player_direction())

	# Persist current location so the splash screen can resume here on next launch
	GameState.save_current_location(SCENE_PATH, $Player.position)

	# This interior has no opponent/NPC container in the .tscn — create one at
	# runtime so MapManager has somewhere to parent the opponents/NPCs it spawns.
	var npc_container := Node2D.new()
	npc_container.name = "OPPONENTS"
	npc_container.z_index = 1
	add_child(npc_container)

	# A missing JSON is fine — MapManager spawns nothing until the file exists.
	# The same path feeds both the opponent and NPC loaders (one file, two arrays).
	var json := NPC_JSON_PATH if ResourceLoader.exists(NPC_JSON_PATH) else ""
	MapManager.initialise($Player, npc_container, $UILAYER, json, [], SCENE_PATH, json, [])

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

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

	# The single door leads back to the Gym Challenge Reception — announce
	# our origin so it places us at its hard-coded hall-door spawn.
	GameState.entering_from = "Gym_Challenge_Hall"

	var fade_tween = create_tween()
	fade_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	fade_tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
