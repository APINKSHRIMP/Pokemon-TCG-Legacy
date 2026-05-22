extends Node2D

const SCENE_PATH = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const BGM_PATH = "res://Audio/BGM/Celeste_Harbour_BGM.ogg"

const TILESET_DAY     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas.tres")
const TILESET_EVENING = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Evening.tres")
const TILESET_NIGHT = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Starting_Areas_Night.tres")

# Default spawn used when arriving here for the first time (no door state,
# no menu-return state). Update this to match the intended harbour entrance position.
const DEFAULT_SPAWN_POSITION = Vector2(-600, 1500)

# --- Door-return spawn points -------------------------------------------------
# Each value is the horizontal centre of the matching DoorArea collider in
# THIS scene, pushed ~20px below the collider's bottom edge so the player
# always lands clear of the trigger (no immediate re-entry loop) and exits
# from the centre of the door regardless of how they walked into it.
const SPAWN_FROM_VERDANT_FOREST         = Vector2(918, 900)    # Verdant Forest door
const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(-597, 1473) # Player House door
const SPAWN_FROM_CARD_MART              = Vector2(431, 1474)   # Card Mart door
# ------------------------------------------------------------------------------

var NPC_JSON_PATH: String = ""

func _ready():
	# Read time and date from player progress
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()

	# Build NPC JSON path: e.g. "Celeste_Harbour_2_Evening.json"
	NPC_JSON_PATH = "res://NPC_and_Opponent_Data/Celeste_Harbour_" + str(date) + "_" + time_of_day + ".json"

	set_time_of_day(time_of_day)

	apply_date_events(date)

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
		"Verdant_Forest":         SPAWN_FROM_VERDANT_FOREST,
		"Player_House_Downstairs": SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS,
		"Card_Mart":              SPAWN_FROM_CARD_MART,
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
	
	# In the day turn off lights
	match time:
		"Day":
			tileset = TILESET_DAY
			$LIGHTS.queue_free()
		"Evening":
			tileset = TILESET_EVENING
			$LIGHTS.queue_free()
		"Night":
			# At night turn on lights and hide the cars in the car park
			tileset = TILESET_NIGHT
			$LIGHTS.visible = true
			$"TILE_MAPS/OBJECTS/CAR PARK CARS".visible = false

	_apply_tileset($TILE_MAPS, tileset)

func apply_date_events(date: int) -> void:
	if date == 1:
		# Player is blocked from the beach on day 1 and bikers are in car park.
		# Day 1 boats aren't really visible but show them anyway and they're reused on day 6 because of this.
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = true
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible=true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = false
		$"Collision Objects/BLOCKS/BEACH CONES".queue_free()
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible=false
	
	if date == 2:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible=true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible=true
	else:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible=false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible=false
		
	# Train station is shut on day 2, SS Anne arrives on day 3
	if date <= 2:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = false
		$"Collision Objects/BLOCKS/STATION GATE".queue_free()
		$"TILE_MAPS/JETTY2/SSANNE".visible = true
		

	if date == 3:
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible=true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible=true
	else:
		$"TILE_MAPS/JETTY2/SSANNE".visible = false
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible=false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible=false
	
	# Forest is closed until day 4
	if date < 4:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = false
		$"Collision Objects/BLOCKS/FOREST GATE".queue_free()
		
			
	if date == 4:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible=true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible=true
	else:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible=false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible=false
	
	if date == 5:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible=true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible=true
	else:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible=false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible=false
	

func _apply_tileset(node: Node, tileset: TileSet) -> void:
	if node is TileMapLayer:
		node.tile_set = tileset
	for child in node.get_children():
		_apply_tileset(child, tileset)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
		var is_escape: bool = event.keycode == KEY_ESCAPE
		if not (is_enter or is_escape):
			return
		# Enter doubles as ui_accept — when a dialog is open let it dismiss the dialog
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
	GameState.entering_from = "Celeste_Harbour"

	var tween = create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		SceneCache.change_scene(target)
	)
