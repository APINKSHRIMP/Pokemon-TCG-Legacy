extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const BGM_PATH = "res://Audio/BGM/Celeste_Harbour_BGM (HGSS National Park).ogg"

const TILESET_MORNING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Morning.tres")
const TILESET_AFTERNOON = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Afternoon.tres")
const TILESET_EVENING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Evening.tres")
const TILESET_NIGHT     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Night.tres")

const DEFAULT_SPAWN_POSITION             = Vector2(-600, 1500)
const SPAWN_FROM_VERDANT_FOREST          = Vector2(918, 900)
const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(-597, 1473)
const SPAWN_FROM_CARD_MART               = Vector2(431, 1474)

const TAXI_START_POS := Vector2(2573.0, 1816.0)
const TAXI_END_POS   := Vector2(-742.0, 1828.0)

var _npc_json_path: String = ""

# Taxi intro state
var _cutscene_active: bool  = false
var _taxi_intro_phase: bool = false
var _taxi_exit_phase: bool  = false
var _taxi_base_pos: Vector2 = Vector2.ZERO
var _taxi_bob_timer: float  = 0.0
var _taxi_current_bob: float = 0.0

func _allow_menu_open(_is_enter: bool) -> bool:
	return not _cutscene_active

func get_scene_path() -> String:    return SCENE_PATH
func get_bgm_path() -> String:      return BGM_PATH
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_entry_positions() -> Dictionary:
	return {
		"Verdant_Forest":           SPAWN_FROM_VERDANT_FOREST,
		"Player_House_Downstairs":  SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS,
		"Card_Mart":                SPAWN_FROM_CARD_MART,
	}
func get_opponent_json_path() -> String: return _npc_json_path
func get_npc_json_path() -> String:      return _npc_json_path

# ============================================================
# FIRST-LAUNCH TAXI INTRO
# ============================================================

func _ready() -> void:
	if not GameState.progress.get("taxi_intro_pending", false):
		$Taxi.visible = false
		super._ready()
		return

	# Taxi intro path: skip normal startup, run the cutscene instead
	modulate = Color.BLACK
	_setup_doors()
	_scene_setup()

	_player.position = TAXI_END_POS
	_player.lock_movement()

	GameState.save_current_location(get_scene_path(), _player.position)
	MapManager.initialise(
		_player, _get_opponents_container(), _ui_layer,
		get_opponent_json_path(), [], get_scene_path(),
		get_npc_json_path(), []
	)

	# Block door triggers for the duration of the cutscene
	$"Door Areas".body_entered.disconnect(_on_door_entered)

	await get_tree().process_frame
	_run_taxi_intro()


func _process(delta: float) -> void:
	if not (_taxi_intro_phase or _taxi_exit_phase):
		return
	_taxi_bob_timer -= delta
	if _taxi_bob_timer <= 0.0:
		_taxi_bob_timer = 0.08 + randf() * 0.05
		_taxi_current_bob = randf_range(0.5, 1.0) * (1.0 if randf() > 0.5 else -1.0)
	$Taxi.position = Vector2(_taxi_base_pos.x, _taxi_base_pos.y + _taxi_current_bob)
	if _taxi_intro_phase:
		_player.position = _taxi_base_pos + Vector2(29.0, 21.0)


func _run_taxi_intro() -> void:
	_cutscene_active = true
	# Clear the flag immediately so a crash-restart doesn't replay the intro
	GameState.progress["taxi_intro_pending"] = false
	GameState.save_progress()

	$Taxi.visible = true
	_taxi_base_pos = TAXI_START_POS
	_taxi_intro_phase = true

	# Fade in from black over 3 seconds
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate", Color.WHITE, 3.0)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_taxi_intro)

	# Phase 1 — constant speed for 17 s
	# Fraction 34/37 ensures phase 2 EASE_OUT starts at exactly phase 1's speed
	var phase1_end := TAXI_START_POS.lerp(TAXI_END_POS, 34.0 / 37.0)
	var move_tween := create_tween()
	move_tween.tween_property(self, "_taxi_base_pos", phase1_end, 17.0) \
		.set_trans(Tween.TRANS_LINEAR)
	# Phase 2 — decelerate to a halt over 3 s (EASE_OUT starts at phase 1 speed)
	move_tween.tween_property(self, "_taxi_base_pos", TAXI_END_POS, 3.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await move_tween.finished

	_taxi_intro_phase = false

	# Player continues from tracked position — no jump
	_player.current_direction = "up"
	_player.animated_sprite.play("idle_up")

	await _scripted_walk("up", 50.0)

	_player.set_direction("down")
	await get_tree().create_timer(0.4).timeout

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_taxi_out)
	_drive_taxi_off()

	await get_tree().create_timer(2.0).timeout

	await _scripted_walk("up", 90.0)
	await _scripted_walk("right", 115.0)
	await _scripted_walk("up", 180.0)

	await get_tree().create_timer(0.5).timeout
	_player.set_direction("left")
	await get_tree().create_timer(0.5).timeout
	_player.set_direction("right")
	await get_tree().create_timer(0.5).timeout
	_player.set_direction("up")
	await get_tree().create_timer(0.5).timeout

	await _scripted_walk("up", 70.0)

	# Fade to black and enter the player house
	_player.lock_movement()
	GameState.progress["show_intro_house_message"] = true
	GameState.save_progress()
	GameState.entering_from = "Celeste_Harbour"
	GameState.save_player_direction("up")

	var trans_tween := create_tween()
	trans_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	trans_tween.tween_callback(func():
		SceneCache.change_scene("res://Scenes/Map_Scenes/Player_House_Downstairs.tscn")
	)


func _drive_taxi_off() -> void:
	var exit_end := Vector2(TAXI_END_POS.x - 800.0, TAXI_END_POS.y)
	_taxi_base_pos = TAXI_END_POS
	_taxi_exit_phase = true
	var exit_tween := create_tween()
	exit_tween.tween_property(self, "_taxi_base_pos", exit_end, 4.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	exit_tween.tween_callback(func():
		_taxi_exit_phase = false
		$Taxi.visible = false
	)


func _scripted_walk(direction: String, distance: float, speed: float = 80.0) -> void:
	var dir_vec := Vector2.ZERO
	match direction:
		"up":    dir_vec = Vector2(0.0, -1.0)
		"down":  dir_vec = Vector2(0.0,  1.0)
		"left":  dir_vec = Vector2(-1.0,  0.0)
		"right": dir_vec = Vector2(1.0,   0.0)

	var target   := _player.position + dir_vec * distance
	var duration := distance / speed

	_player.current_direction = direction
	_player.animated_sprite.play("walk_" + direction)

	var tween := create_tween()
	tween.tween_property(_player, "position", target, duration)
	await tween.finished

	_player.animated_sprite.play("idle_" + direction)


func _scene_setup():
	$Taxi.visible = false
	var time_of_day: String = GameState.get_time()
	var date: int = GameState.get_date()
	_npc_json_path = "res://NPC_and_Opponent_Data/Celeste_Harbour_" + str(date) + "_" + time_of_day + ".json"
	set_time_of_day(time_of_day)
	apply_date_events(date)

func set_time_of_day(time: String) -> void:
	var tileset: TileSet
	match time:
		"Morning":
			tileset = TILESET_MORNING
			$LIGHTS.queue_free()
		"Afternoon":
			tileset = TILESET_AFTERNOON
			$LIGHTS.queue_free()
		"Evening":
			tileset = TILESET_EVENING
			$LIGHTS.queue_free()
		"Night":
			tileset = TILESET_NIGHT
			$LIGHTS.visible = true
			$"TILE_MAPS/OBJECTS/CAR PARK CARS".visible = false
	_apply_tileset($TILE_MAPS, tileset)

func apply_date_events(date: int) -> void:
	if date == 1:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = true
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = false
		$"Collision Objects/BLOCKS/BEACH CONES".queue_free()
		$"TILE_MAPS/JETTY/DAY 1 Boats".visible = false

	if date == 2:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 2 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2".visible = false

	if date <= 2:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = false
		$"Collision Objects/BLOCKS/STATION GATE".queue_free()
		$"TILE_MAPS/JETTY2/SSANNE".visible = true

	if date == 3:
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible = true
	else:
		$"TILE_MAPS/JETTY2/SSANNE".visible = false
		$"TILE_MAPS/JETTY/DAY 3 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3".visible = false

	if date < 4:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = true
	else:
		$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = false
		$"Collision Objects/BLOCKS/FOREST GATE".queue_free()

	if date == 4:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 4 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4".visible = false

	if date == 5:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible = true
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible = true
	else:
		$"TILE_MAPS/JETTY/DAY 5 Boats".visible = false
		$"TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5".visible = false
