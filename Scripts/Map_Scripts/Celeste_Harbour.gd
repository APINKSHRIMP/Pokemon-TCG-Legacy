extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"

const TILESET_MORNING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Morning.tres")
const TILESET_AFTERNOON = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Afternoon.tres")
const TILESET_EVENING   = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Evening.tres")
const TILESET_NIGHT     = preload("res://Image_Assets/Map_Sheets/Tile_Sets/Celeste_Harbour_Night.tres")

const DEFAULT_SPAWN_POSITION             = Vector2(-600, 1500)
const SPAWN_FROM_VERDANT_FOREST          = Vector2(918, 900)
const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(-597, 1473)
const SPAWN_FROM_CARD_MART               = Vector2(431, 1474)
# On the porch under the Fish Shop door (the building art runs x -1135..-906, bottom y 1164).
const SPAWN_FROM_FISH_SHOP               = Vector2(-1020, 1185)

const TAXI_START_POS := Vector2(2573.0, 1816.0)
const TAXI_END_POS   := Vector2(-742.0, 1828.0)

# The intro phone call. Ellie rings while the taxi is still driving in, so the two play together and
# the drive-by is what she is talking about ("I'll see you drive right on by in a sec").
#
# It is an ORDINARY call - the player clicks through her lines at their own pace - so the cutscene
# cannot assume any particular length for it. It waits once, on the doorstep; see the doorstep wait
# in _run_taxi_intro().
#
# TWEAKABLE. The delay is measured from the first frame of the cutscene: long enough for the 3s fade
# from black to be well under way, early enough that the whole call lands before the taxi stops. The
# call is roughly 17.5s at the default text speed and the drive is 20s, so there is room either way -
# and if a slow text speed overruns it, _run_taxi_intro() waits for it rather than talking over the
# player's first steps. See Phone_Call.gd for the call itself and Phone_Calls.json for the script.
const INTRO_CALL_ID    := "ellie_intro"
const INTRO_CALL_DELAY := 1.2

# TWEAKABLE - the drive itself.
#   DRIVE_TIME  the long constant-speed run in. Raising it slows the taxi down; the distance is
#               fixed, so time and speed are the same dial.
#   STOP_TIME   the deceleration to a halt.
#   DRIVE_SPEED_MATCH keeps the two joined smoothly: it is the fraction of the way along at which
#               phase one hands over, chosen so the EASE_OUT of phase two BEGINS at exactly phase
#               one's speed. It falls out of the two times as f / DRIVE_TIME = 2(1 - f) / STOP_TIME,
#               so scaling BOTH times together (as the 10% slow-down did) leaves it correct - but
#               changing only one of them means re-deriving it, or the taxi visibly jerks.
const DRIVE_TIME         := 18.7
const STOP_TIME          := 3.3
const DRIVE_SPEED_MATCH  := 34.0 / 37.0
# The fade up from black at the top of the cutscene.
const INTRO_FADE_TIME    := 2.4

# Taxi intro state
var _cutscene_active: bool  = false
var _taxi_intro_phase: bool = false
var _taxi_exit_phase: bool  = false
var _taxi_base_pos: Vector2 = Vector2.ZERO
var _taxi_bob_timer: float  = 0.0
var _taxi_current_bob: float = 0.0
var _intro_call: PhoneCall = null

func _allow_menu_open(_is_enter: bool) -> bool:
	return not _cutscene_active

func get_scene_path() -> String:    return SCENE_PATH
func get_bgm_path() -> String:      return SoundManagerScript.BGM_CELESTE_HARBOUR
func get_default_spawn() -> Vector2: return DEFAULT_SPAWN_POSITION
func get_entry_positions() -> Dictionary:
	return {
		"Verdant_Forest":           SPAWN_FROM_VERDANT_FOREST,
		"Player_House_Downstairs":  SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS,
		"Card_Mart":                SPAWN_FROM_CARD_MART,
		"Fish_Shop":                SPAWN_FROM_FISH_SHOP,
	}
func get_map_data_name() -> String: return "Celeste_Harbour"

# ============================================================
# FIRST-LAUNCH TAXI INTRO
# ============================================================

func _ready() -> void:
	if not GameState.progress.get("taxi_intro_pending", false):
		$Taxi.visible = false
		# A cutscene that is about to take over must not give the player a frame or
		# two of free movement while the map fades in.
		var cutscene_due: bool = EllieIntroCutscene.should_run(GameState.entering_from)
		if cutscene_due:
			_player.lock_movement()
		await super._ready()
		if cutscene_due:
			_start_ellie_intro()
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
		get_map_data_name(), [], get_scene_path(), []
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
	# ISSUE #31 FIX: do NOT clear taxi_intro_pending here. If the player quits partway through the
	# cutscene the flag must stay set so the taxi animation replays in full on the next load (name/
	# sprite entry is already skipped via first_launch_complete). The flag is cleared only once the
	# cutscene finishes and the player is sent into their house (see below).

	$Taxi.visible = true
	_taxi_base_pos = TAXI_START_POS
	_taxi_intro_phase = true

	# Fade in from black over 3 seconds
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate", Color.WHITE, INTRO_FADE_TIME)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_taxi_intro)

	# Started, not awaited: the taxi keeps driving underneath the call.
	_start_intro_phone_call()

	# Phase 1 — constant speed. See DRIVE_SPEED_MATCH for why the hand-over sits where it does.
	var phase1_end := TAXI_START_POS.lerp(TAXI_END_POS, DRIVE_SPEED_MATCH)
	var move_tween := create_tween()
	move_tween.tween_property(self, "_taxi_base_pos", phase1_end, DRIVE_TIME) \
		.set_trans(Tween.TRANS_LINEAR)
	# Phase 2 — decelerate to a halt (EASE_OUT starts at phase 1's speed)
	move_tween.tween_property(self, "_taxi_base_pos", TAXI_END_POS, STOP_TIME) \
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

	# ── THE DOORSTEP WAIT ──────────────────────────────────────────────────────────────
	# The call advances on a click now, so the player decides how long it takes. They stop here, in
	# front of their house, until they have read Ellie out - and then until the phone has actually
	# flown off the screen, which is what `finished` waits for.
	#
	# THIS IS THE ONLY PLACE THE CUTSCENE WAITS. Everything before it - the drive, the taxi leaving,
	# the walk up the path - plays over the call exactly as it did, and a player who has already
	# clicked through every line walks straight into the look-around with no pause at all, because
	# is_finished() is already true.
	#
	# is_finished() before the await, never just is_instance_valid(): the call frees itself the
	# moment it emits, so awaiting one that has already ended would wait for ever.
	if _intro_call != null and is_instance_valid(_intro_call) and not _intro_call.is_finished():
		await _intro_call.finished

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
	# ISSUE #31 FIX: the cutscene has fully played and the player is now being forced into their
	# house — this is the point at which the taxi intro is genuinely "done", so clear the flag here.
	GameState.progress["taxi_intro_pending"] = false
	GameState.progress["show_intro_house_message"] = true
	GameState.save_progress()
	GameState.entering_from = "Celeste_Harbour"
	GameState.save_player_direction("up")

	var trans_tween := create_tween()
	trans_tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	trans_tween.tween_callback(func():
		SceneCache.change_scene("res://Scenes/Map_Scenes/Player_House_Downstairs.tscn")
	)


# ============================================================
# STORY CUTSCENES
# ============================================================
# Everything about the Ellie intro — where she runs, what she says, when it plays
# — lives in Scripts/Cutscenes/Ellie_Intro_Cutscene.gd. All the map has to do is
# ask whether it is due and hand the scene over; the cutscene object adds itself to
# this scene, takes the player's input, and frees itself when it is done. Add
# further cutscenes the same way.

func _start_ellie_intro() -> void:
	var cutscene := EllieIntroCutscene.new()
	cutscene.install(self)
	cutscene.run()


## Rings Ellie up a couple of seconds into the drive. Fire-and-forget: it returns as soon as the
## call has been started, and the cutscene carries on around it.
func _start_intro_phone_call() -> void:
	await get_tree().create_timer(INTRO_CALL_DELAY).timeout
	# The player can quit out of the cutscene; do not build a call into a scene that has gone.
	if not is_inside_tree():
		return
	_intro_call = PhoneCall.play_from_data(self, INTRO_CALL_ID)


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
	set_time_of_day(time_of_day)
	apply_permanent_unlocks(date)
	apply_daily_dressing(date)

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

# Gates and blocks that open once and stay open. These read the REAL date, never a
# looped one -- a loop that resolved day 12 back to day 3 would otherwise rebuild
# the forest gate long after the player walked through it.
func apply_permanent_unlocks(date: int) -> void:
	var beach_open := date > 1
	$"TILE_MAPS/PLAYER ROAD BLOCKS/Cone Blocks".visible = not beach_open
	if beach_open and has_node("Collision Objects/BLOCKS/BEACH CONES"):
		$"Collision Objects/BLOCKS/BEACH CONES".queue_free()

	var station_open := date > 2
	$"TILE_MAPS/PLAYER ROAD BLOCKS/Station Gate block".visible = not station_open
	if station_open and has_node("Collision Objects/BLOCKS/STATION GATE"):
		$"Collision Objects/BLOCKS/STATION GATE".queue_free()

	var forest_open := date >= 5
	$"TILE_MAPS/PLAYER ROAD BLOCKS/Forest Gate block".visible = not forest_open
	if forest_open and has_node("Collision Objects/BLOCKS/FOREST GATE"):
		$"Collision Objects/BLOCKS/FOREST GATE".queue_free()

	# The SS Anne is moored only on day 3, while the station is open.
	$"TILE_MAPS/JETTY2/SSANNE".visible = date == 3


# Rotating scenery -- boats on the jetty, cars in the car park. Driven by the
# `dressing` block in this map's character file so the rotation is a data edit, and
# resolved through its own cycle, which deliberately drifts against the cast cycle
# so no two days look like the same combination.
func apply_daily_dressing(date: int) -> void:
	var dressing := CharacterSchedule.dressing_for(get_map_data_name(), date)
	var show: Array = dressing.get("show", [])
	for node_path in dressing.get("all", []):
		if has_node(NodePath(node_path)):
			get_node(NodePath(node_path)).visible = show.has(node_path)
		else:
			push_warning("Celeste_Harbour: dressing node missing: " + str(node_path))
