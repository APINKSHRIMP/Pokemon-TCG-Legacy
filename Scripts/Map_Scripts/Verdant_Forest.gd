extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Verdant_Forest.tscn"
const BGM_PATH = "res://Audio/BGM/Verdant_Forest_BGM.ogg"

# Default spawn used when arriving here for the first time (no door state,
# no menu-return state). Matches the placement set in the .tscn.
const DEFAULT_SPAWN_POSITION = Vector2(1770, 1850)

# --- Door-return spawn points -------------------------------------------------
# Each value is the horizontal centre of the matching DoorArea collider in
# THIS scene, pushed ~20px below the collider's bottom edge so the player
# always lands clear of the trigger (no immediate re-entry loop) and exits
# from the centre of the door regardless of how they walked into it.
const SPAWN_FROM_CELESTE_HARBOUR = Vector2(1775, 1909)  # Celeste Harbour door
const SPAWN_FROM_GYM_PLAZA       = Vector2(1773, -280)  # Gym Plaza door
const SPAWN_FROM_ROCKET_MART     = Vector2(278, 1064)   # Rocket Mart door
# ------------------------------------------------------------------------------

const TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest.tres")
const TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Evening.tres")
const TILESET_NIGHT   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Verdant_Forest_Night.tres")

const TRACKS_TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas.tres")
const TRACKS_TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Evening.tres")
const TRACKS_TILESET_NIGHT   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Night.tres")

const TREE_HORIZ_DAY     = preload("res://Image_Assets/Map_Objects/TreeLineThird.png")
const TREE_HORIZ_EVENING = preload("res://Image_Assets/Map_Objects/TreeLineThirdEvening.png")
const TREE_HORIZ_NIGHT   = preload("res://Image_Assets/Map_Objects/TreeLineThirdNight.png")

const TREE_VERT_DAY     = preload("res://Image_Assets/Map_Objects/TreeLineVertical.png")
const TREE_VERT_EVENING = preload("res://Image_Assets/Map_Objects/TreeLineVerticalEvening.png")
const TREE_VERT_NIGHT   = preload("res://Image_Assets/Map_Objects/TreeLineVerticalNight.png")

var NPC_JSON_PATH: String = ""

func _ready():
	# Read time and date from player progress
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()

	# Build NPC JSON path: e.g. "Verdant_Forest_4_Day.json"
	NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Verdant_Forest_" + str(date) + "_" + time_of_day + ".json"

	# Fall back to Day 4 if the specific time/date file doesn't exist
	if not ResourceLoader.exists(NPC_JSON_PATH):
		NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Verdant_Forest_4_Day.json"

	SoundManagerScript.play_bgm(BGM_PATH, true)
	set_time_of_day(time_of_day)

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
		"Celeste_Harbour": SPAWN_FROM_CELESTE_HARBOUR,
		"Rocket_Mart":     SPAWN_FROM_ROCKET_MART,
		"Gym_Plaza":       SPAWN_FROM_GYM_PLAZA,
	}

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == SCENE_PATH:
		# Returning from main menu (or splash-screen resume)
		$Player.position = GameState.menu_return_position
		$Player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.returning_from_battle:
		# Returning from battle
		$Player.position = GameState.player_position
		$Player.set_direction(GameState.get_player_direction())
		GameState.returning_from_battle = false
	elif entry_positions.has(GameState.entering_from):
		# Returning from another scene through one of this scene's doors
		$Player.position = entry_positions[GameState.entering_from]
		$Player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
	else:
		# First load or other cases
		$Player.position = DEFAULT_SPAWN_POSITION
		$Player.set_direction(GameState.get_player_direction())

	# Persist current location so the splash screen can resume here on next launch
	GameState.save_current_location(SCENE_PATH, $Player.position)

	MapManager.initialise(
		$Player,
		$OPPONENTS,
		$UILAYER,
		NPC_JSON_PATH,
		[],
		SCENE_PATH,
		NPC_JSON_PATH,
		[]
	)

	await get_tree().process_frame
	tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)


func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	var tracks_tileset: TileSet
	match time:
		"Day":
			tileset = TILESET_DAY
			tracks_tileset = TRACKS_TILESET_DAY
		"Evening":
			tileset = TILESET_EVENING
			tracks_tileset = TRACKS_TILESET_EVENING
		"Night":
			tileset = TILESET_NIGHT
			tracks_tileset = TRACKS_TILESET_NIGHT
	_apply_tileset($TILE_MAPS, tileset)
	var train_tracks = $TILE_MAPS.find_child("TRAIN TRACKS")
	if train_tracks:
		_apply_tileset(train_tracks, tracks_tileset)

	var horiz_tex: Texture2D
	var vert_tex: Texture2D
	var is_night := time == "Night"
	match time:
		"Day":
			horiz_tex = TREE_HORIZ_DAY
			vert_tex  = TREE_VERT_DAY
		"Evening":
			horiz_tex = TREE_HORIZ_EVENING
			vert_tex  = TREE_VERT_EVENING
		"Night":
			horiz_tex = TREE_HORIZ_NIGHT
			vert_tex  = TREE_VERT_NIGHT

	# North wall
	var north = $TREE_WALL_NORTH_GROUP
	north.get_node("Shadow").visible  = not is_night
	north.get_node("Shadow2").visible = not is_night
	for name in ["Tree_wall_north", "Tree_wall_north2", "Tree_wall_north3", "Tree_wall_north4"]:
		north.get_node(name).texture = horiz_tex

	# South wall
	var south = $TREE_WALL_SOUTH_GROUP
	south.get_node("Shadow").visible  = not is_night
	south.get_node("Shadow2").visible = not is_night
	for name in ["Tree_wall_South", "Tree_wall_South2", "Tree_wall_South3", "Tree_wall_South4"]:
		south.get_node(name).texture = horiz_tex

	# West wall
	var west = $TREE_WALL_WEST_GROUP
	west.get_node("SHADOW_VERTICAL2").visible = not is_night
	west.get_node("TREE_WALL_WEST").texture = vert_tex

	# East wall
	var east = $TREE_WALL_EAST_GROUP
	east.get_node("SHADOW_VERTICAL").visible = not is_night
	for name in ["TREE_WALL_EAST", "TREE_WALL_EAST2"]:
		east.get_node(name).texture = vert_tex

	if not is_night:
		for lamp in find_children("ForestLamp*"):
			lamp.get_node("PointLight2D2").visible = false


func _apply_tileset(node: Node, tileset: TileSet) -> void:
	if node is TileMapLayer:
		node.tile_set = tileset
	for child in node.get_children():
		if child.name == "TRAIN TRACKS":
			continue
		_apply_tileset(child, tileset)


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

	# Every scene resolves its own spawn from a hard-coded table keyed on
	# entering_from, so this door only has to announce where we came from.
	GameState.entering_from = "Verdant_Forest"

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
