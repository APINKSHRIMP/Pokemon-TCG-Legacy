class_name FishingMinigame
extends Node2D

## The whole fishing sequence: pulling the rod out, the cast, a silhouette fish creeping
## up on the bobber, the bite window, the tug-of-war, and the catch.
##
## Built and owned by MapManager.start_fishing(); it frees itself and calls
## MapManager.finish_fishing() when it is done.
##
## Style note: like the overworld Pokémon templates this uses NO tweens. Every motion is
## hand-integrated against a per-state `_time` accumulator, with sin(PI*t) for hops and
## linear ramps for deceleration, so it moves the same way the rest of the overworld does.
##
## The player is locked for the whole sequence with BOTH _player.lock_movement() and
## MapManager.cutscene_active. That pair is load-bearing: _hide_message() restores
## can_move as `not cutscene_active`, which is what lets a "the line snapped" box be
## dismissed WITHOUT handing movement back while the rod is still reeling in.

# ---- tweakables -------------------------------------------------------------
## The user thinks in on-screen pixels; the camera is at 2.5x, so world = screen * 0.4.
const SCREEN_TO_WORLD := 0.4

## Rod pull-out. Every beat below is multiplied by PULL_OUT_TIME_SCALE, so the whole
## sequence can be sped up or slowed down with one number. 1.0 was the original pace;
## 4.0 quartered the speed to inspect it frame by frame; 0.8 is 5x faster than that.
## The three turns and the flick come to about 0.43s in total at 0.8.
const PULL_OUT_TIME_SCALE := 0.8
const SHAKE_TIME := 0.2 * PULL_OUT_TIME_SCALE   ## facing away from the water, shaking
const SHAKE_STEPS := [-1.0, 1.0, 0.0]           ## sprite x offsets: left 1, right 2, left 1
const TURN_TIME := 0.12 * PULL_OUT_TIME_SCALE   ## per counterclockwise quarter turn
## 0 = the rod starts launching the instant the player lands on the water's direction.
const FLICK_PAUSE := 0.0 * PULL_OUT_TIME_SCALE
const FLICK_TIME := 0.1 * PULL_OUT_TIME_SCALE

## Sprite scales. The art is pixel-for-pixel world px at 1.0; the rod reads far too big
## against a 32px player at that size.
const ROD_SCALE := 0.5
const BOBBER_SCALE := 1.0
const FISH_SCALE := 1.0

## Where the rod handle sits relative to the player origin, per facing, in world px.
## Right hand for every direction.
##
## Measured off 1pokemontrainer_playerm.png: a 64px cell drawn centred at 0.5 scale, art
## from cell y=14 to y=59, so the sprite spans -9 (top of the head) to +13.5 (feet) in
## world px.
##
## These sprites are CHIBI, so the widest row of the silhouette is the HEAD, not the
## shoulders -- taking the widest row put the handle on the player's chin. The arms are a
## SECOND bulge further down: the front frame widens back out to 34px over world y +6 to
## +9.5, and both side frames bulge over +7 to +10.5. So the hand is at y=+8.5, roughly
## hip height, and x just inside the outer edge of that bulge.
const HAND_OFFSET := {
	"down": Vector2(-7.5, 8.5),
	"up": Vector2(7.5, 8.5),
	"left": Vector2(-3.0, 8.5),
	"right": Vector2(3.0, 8.5),
}

## Rod angles in DEGREES, Godot convention: clockwise-positive, 0 = the rod as drawn
## (vertical rod points straight up, horizontal rod points up-and-out at ~19 degrees).
## "raised" is the over-the-shoulder pose it is pulled out in and yanked back to;
## "rest" is where it flicks to for the cast.
## NOTE the sign on "left": the rod is MIRRORED for that facing (scale.x < 0), which
## reverses which way a positive rotation tips the tip. -45 there pointed it at the floor.
const ROD_RAISED_ANGLE := {"up": 40.0, "down": -40.0, "left": 45.0, "right": -45.0}
const ROD_REST_ANGLE := {"up": 0.0, "down": 180.0, "left": 0.0, "right": 0.0}
## Facings where the rod is held on the far side of the body, so the rig draws behind the
## player rather than in front of them.
const ROD_BEHIND_FACINGS := ["up", "left"]

## The line and the hauled-up Pokémon draw ABOVE the map's scenery -- the harbour's
## fences and railings are z 9-11 and the tallest thing on the map is z 20, so a line
## cast out over a railing was disappearing behind it. The ROD deliberately stays at the
## default z with the player: they are standing behind the fence, so the rod in their
## hand belongs behind it too.
const LINE_Z := 22
const CAUGHT_Z := 23

## Cast.
const CAST_DISTANCE := 400.0 * SCREEN_TO_WORLD
const CAST_TIME := 0.55
## Sideways casts arc downwards as well as outwards.
const CAST_DROP := 0.4
const SPLASH_COUNT := 18
const SPLASH_SPEED := 0.8

## Water thrown up at the hooked fish's mouth, by what is happening to it. `interval` is
## seconds between bursts; 0 means it is only ever fired as a one-off.
##   big     it takes the bait under
##   wrong   the player is pulling the wrong way -- it is winning, and thrashing
##   correct the player has it under control, so it barely breaks the surface
##   tired   out of energy / being reeled in: almost nothing
##   huge    the moment it comes out of the water
const FIGHT_SPLASH := {
	"big": {"interval": 0.0, "count": 34, "speed": 1.6, "width": 10.0},
	"wrong": {"interval": 0.12, "count": 16, "speed": 1.3, "width": 8.0},
	"correct": {"interval": 0.35, "count": 5, "speed": 0.55, "width": 3.0},
	"tired": {"interval": 1.2, "count": 2, "speed": 0.25, "width": 1.5},
	"huge": {"interval": 0.0, "count": 60, "speed": 2.2, "width": 16.0},
}
## Same height as the line, so a splash out past a railing isn't swallowed by it.
const SPLASH_Z := 22

## Bobber idle bob: frames 1 2 3 2 repeating (art frames 2 3 4 3).
const BOBBER_IDLE_FRAMES := [1, 2, 3, 2]
const BOBBER_IDLE_FPS := 3.0
const BOBBER_SINK_TIME := 0.2

## Fish approach. Distances are measured out from the BOBBER, away from the player.
const FISH_SPAWN_DISTANCE := 200.0 * SCREEN_TO_WORLD
const FISH_SPAWN_LATERAL := 100.0 * SCREEN_TO_WORLD
## Underwater silhouettes read better slightly see-through. This is the alpha a fully
## faded-in fish sits at; _fish_alpha stays a 0-1 fade PROGRESS and is scaled by it, so
## the fade still takes FISH_FADE_IN seconds however transparent the fish ends up.
const FISH_ALPHA := 0.8
const FISH_FADE_IN := 1.0
const FISH_SPEED_MIN := 8.0
const FISH_SPEED_MAX := 16.0
## How much faster it swims as it closes the last of the gap.
const FISH_CLOSING_BOOST := 0.2
const FISH_ANIM_FPS := 4.0
## Tail speed relative to the calm approach: it thrashes once hooked, and idles while it
## is out of energy and getting its breath back.
const FISH_ANIM_FIGHT_SCALE := 2.0
const FISH_ANIM_TIRED_SCALE := 0.5
## Straight swim cycle, then the same with the darting frames mixed in.
const FISH_CALM_FRAMES := [0, 1, 0, 2]
const FISH_FAST_FRAMES := [0, 1, 3, 1, 0, 2, 4, 2]
const FISH_FLEE_SPEED := 90.0
const FISH_FLEE_FADE := 0.6

const BITE_DELAY_MIN := 0.1
const BITE_DELAY_MAX := 1.0
const BITE_WINDOW := 1.0
const EXCLAMATION_OFFSET := 10.0 * SCREEN_TO_WORLD

## Tug-of-war. Line strength runs -100 (slack, about to be dropped) to +100 (snapped).
## Only MISTAKES load the line now: countering correctly holds it wherever it is and just
## tires the fish out, so the fight is about reading the fish's run rather than rationing
## a pull. A wrong hold snaps it in under a second and letting go goes slack in one, so
## there is no resting -- the right key has to be held nearly all of the time.
const TENSION_DECAY := 100.0     ## per second with no input
const TENSION_CORRECT := 0.0     ## countering the right way costs the line nothing
const TENSION_WRONG := 120.0     ## per second pulling the wrong way
## One hit per REEL press made while the fish still has fight in it. Three of them snap
## the line, so panic-mashing early is punished hard.
const TENSION_WRONG_PRESS := 35.0
## While the fish is blown, the line settles back to neutral from EITHER side at this rate
## per second -- that is what the mashing window is for: it hands you a clean line for the
## next run.
const TENSION_REST_RECOVER := 120.0
const TENSION_LIMIT := 100.0
const ENERGY_START := 100.0
const ENERGY_DRAIN := 40.0       ## per second of correct input
const TIRED_SPEED_FACTOR := 0.5
## The run across the cast is the visible half of the fight -- long, fast dashes the
## player has to read and counter.
const FIGHT_LATERAL_SPEED := 110.0
## The fish is on a LEASH at whatever range it has been reeled to. It surges out to
## FIGHT_SURGE beyond that and comes back to it, over and over, but can never get further
## in than the leash -- so ground won by reeling is never given back, and the only thing
## that shortens the fight is mashing during a rest.
const FIGHT_SURGE := 55.0        ## world px it can run out beyond the leash
const FIGHT_SURGE_SPEED_MIN := 30.0
const FIGHT_SURGE_SPEED_MAX := 70.0
const FIGHT_SWITCH_MIN := 0.9    ## seconds before the fish turns and dashes back
const FIGHT_SWITCH_MAX := 2.2
## The fish runs inside a CONE opening out from the player: metres of sideways room grow
## with how far out it is, so it thrashes right across the screen while it is still out
## at sea and is pinned almost dead ahead by the time it is nearly landed. Hitting the
## edge of the cone turns it round, same as running out the switch timer.
const FIGHT_CONE_MIN := 20.0     ## world px of sideways room at the catch line
const FIGHT_CONE_SLOPE := 2.5    ## extra sideways room per world px further out
## Reeling is a MASH, not a hold: every Space/Enter press drags the leash in by
## REEL_STEP. How much ground a rest wins is down to how fast the player can hit it.
const REEL_STEP := 6.0           ## world px per press
## How long the fish stays blown once its energy runs out -- the mashing window.
const REST_TIME_MIN := 1.5
const REST_TIME_MAX := 2.5
## It only has to be brought HALF as close as it used to be.
const CATCH_DISTANCE := 200.0 * SCREEN_TO_WORLD
const CATCH_PAUSE := 0.1

## Retract (a miss, a break-off, or Escape).
const RETRACT_SPEED := 360.0
const RETRACT_HOLD := 0.2

## The caught Pokémon's hop back into the water, mirroring PokemonSkittish.
const HOP_TIME := 0.45
const HOP_HEIGHT := 14.0
const HOP_SPEED := 130.0
const SINK_TIME := 0.5
const WATER_CLEAR_ROWS := 5.0
const WATER_FADE_ROWS := 8.0

## Line.
const LINE_WIDTH := 0.8
const LINE_SLACK_FAR := Color8(18, 38, 110)    ## -100
const LINE_SLACK_NEAR := Color8(90, 200, 230)  ## -50
const LINE_NEUTRAL := Color.WHITE              ## 0
const LINE_TIGHT_NEAR := Color8(240, 120, 120) ## +50
const LINE_TIGHT_FAR := Color8(130, 10, 10)    ## +100

## Camera follow on the bobber.
const CAMERA_LERP := 6.0

## Sound. Filled in as the files arrive -- _sfx() checks before it loads, so a missing
## one is silent rather than a crash. Move these to preloaded constants in
## Sound_Manager_Script.gd once they all exist (a preload of a missing file won't compile).
const SFX := {
	"equip": "res://Audio/SFX/FishingRodEquip.ogg",
	"cast": "res://Audio/SFX/FishingCast.ogg",
	"splash": "res://Audio/SFX/FishingSplash.ogg",
	"fight": "res://Audio/SFX/FishingFight.ogg",
}

const BREAK_MESSAGE := "The line snapped!"
const ESCAPED_MESSAGE := "It got away..."
# -----------------------------------------------------------------------------

enum State {
	SHAKE, TURN_AWAY, TURN_BACK, FLICK, CAST, WAIT, SINK, BITE, FIGHT,
	CATCH_PAUSE_STATE, CATCH_YANK, CATCH_MESSAGE, CATCH_HOP, CATCH_SINK, RETRACT, DONE
}

var map_data: String = ""
## Which way the WATER is: the direction the player ends up facing.
var water_dir: String = "down"

var _player: CharacterBody2D = null
var _rod: Sprite2D = null
var _bobber: Sprite2D = null
var _line: Line2D = null
var _fish: Sprite2D = null
var _exclamation: Sprite2D = null
var _caught: Sprite2D = null

var _state: int = State.SHAKE
var _time: float = 0.0
var _facing: String = "down"
var _vertical_rod: bool = true

var _rod_angle: float = 0.0

var _bobber_frame: int = 0
var _bobber_anim: float = 0.0
var _bobber_pos: Vector2 = Vector2.ZERO
var _cast_dir: Vector2 = Vector2.DOWN
var _cast_speed: float = 0.0
var _sink_from_frame: int = 1

var _fish_species: String = ""
var _fish_frame: int = 0
var _fish_anim: float = 0.0
var _fish_speed: float = 0.0
var _fish_start_gap: float = 1.0
var _fish_fleeing: bool = false
var _fish_alpha: float = 0.0
var _fish_aim: Vector2 = Vector2.UP

var _bite_delay: float = 0.0

var _tension: float = 0.0
var _energy: float = ENERGY_START
var _fight_side: float = 1.0
var _fight_switch: float = 0.0
## Seconds of "blown" left. Above zero the fish is resting, the line is recovering and
## mashing reels it in; it is the only window in which reeling does anything.
var _rest_left: float = 0.0
## Radial distance from the player the fish is tethered at -- the closest it has been
## reeled. It never gets back inside this.
var _leash: float = 0.0
## Which way along the cast axis it is currently surging, and how fast on this leg.
var _surge_dir: float = 1.0
var _surge_speed: float = 0.0
var _perp: Vector2 = Vector2.RIGHT

var _hop_dir: Vector2 = Vector2.DOWN
var _water_y: float = 0.0
var _sink_from: float = 0.0
var _sink_distance: float = 0.0
var _water_material: ShaderMaterial = null
var _caught_cell: Vector2 = Vector2.ONE
var _caught_scale: float = 0.5

## A failure retract runs its animation and its message box at the same time; control
## comes back only once BOTH are finished.
var _splash_timer: float = 0.0

var _message_open: bool = false
var _retract_done: bool = false
var _finished: bool = false


# ============================================================
# SETUP
# ============================================================

func setup(player: CharacterBody2D, direction: String, map_key: String) -> void:
	_player = player
	water_dir = direction
	map_data = map_key


func _ready() -> void:
	_facing = _opposite(water_dir)
	_vertical_rod = _facing == "up" or _facing == "down"
	_perp = Vector2.RIGHT if (water_dir == "up" or water_dir == "down") else Vector2.DOWN

	_build_rod()
	_build_line()
	_build_bobber()

	# _face() applies the depth order too.
	_face(_facing)
	_rod_angle = _raised_angle()
	_apply_rod()
	_snap_bobber_to_tip()
	_sfx("equip")
	_set_state(State.SHAKE)


func _build_rod() -> void:
	_rod = Sprite2D.new()
	_rod.texture = FishingArt.rod_texture(_vertical_rod)
	_rod.centered = false
	_rod.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The node origin becomes the handle, so rotation pivots there.
	_rod.offset = -FishingArt.rod_pivot(_vertical_rod)
	add_child(_rod)


func _build_bobber() -> void:
	_bobber = Sprite2D.new()
	_bobber.centered = false
	_bobber.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bobber.scale = Vector2(BOBBER_SCALE, BOBBER_SCALE)
	add_child(_bobber)
	_set_bobber_frame(0)


func _build_line() -> void:
	_line = Line2D.new()
	_line.width = LINE_WIDTH
	_line.default_color = LINE_NEUTRAL
	_line.texture_mode = Line2D.LINE_TEXTURE_NONE
	_line.joint_mode = Line2D.LINE_JOINT_SHARP
	# Over the map scenery, so a cast out across a railing is not cut in half by it.
	_line.z_as_relative = false
	_line.z_index = LINE_Z
	add_child(_line)


## Whenever the player is facing AWAY from us the rod and bobber go BEHIND them; every
## other facing they go in front. Re-applied on every turn rather than once from
## water_dir, because the pull-out spins the player through all four directions and the
## rod has to sit correctly in each of them.
##
## Done by sibling order, not z_index: equal z_index draws in tree order, and the rig
## stays after the tilemaps either way, so it can never sink under the ground the way a
## negative z_index would.
func _apply_depth() -> void:
	# Facing up OR left: the rod is in the right hand, which is the far side of the body
	# in both of those, so the whole rig sits behind the player.
	var behind := _facing in ROD_BEHIND_FACINGS
	# The fish is under water and always stays at the bottom.
	var order: Array = []
	if _fish != null and is_instance_valid(_fish):
		order.append(_fish)
	if behind:
		order.append_array([_bobber, _line, _rod])
	else:
		order.append_array([_rod, _line, _bobber])
	for i in order.size():
		move_child(order[i], i)
	var parent := get_parent()
	if parent == null or _player == null or not is_instance_valid(_player):
		return
	# Only move when we are on the wrong side of the player. Moving unconditionally is
	# NOT idempotent: once the rig sits before the player, the player's index is the
	# rig's + 1, so "move to the player's index" pushes the rig back in front of them --
	# which is why two "behind" beats in a row ended up facing the wrong way round.
	var player_index := _player.get_index()
	if behind and get_index() > player_index:
		parent.move_child(self, player_index)
	elif not behind and get_index() < player_index:
		parent.move_child(self, parent.get_child_count() - 1)


# ============================================================
# MAIN LOOP
# ============================================================

func _process(delta: float) -> void:
	_time += delta
	match _state:
		State.SHAKE: _process_shake()
		State.TURN_AWAY, State.TURN_BACK: _process_turn()
		State.FLICK: _process_flick()
		State.CAST: _process_cast(delta)
		State.WAIT: _process_wait(delta)
		State.SINK: _process_sink()
		State.BITE: _process_bite(delta)
		State.FIGHT: _process_fight(delta)
		State.CATCH_PAUSE_STATE: _process_catch_pause()
		State.CATCH_YANK: _process_catch_yank(delta)
		State.CATCH_MESSAGE: pass
		State.CATCH_HOP: _process_catch_hop(delta)
		State.CATCH_SINK: _process_catch_sink()
		State.RETRACT: _process_retract(delta)
	_update_fish_anim(delta)
	_update_line()
	_update_camera(delta)


func _set_state(next: int) -> void:
	_state = next
	_time = 0.0


func _input(event: InputEvent) -> void:
	if _state == State.DONE:
		return
	# The catch / failure box owns Space and Escape while it is up.
	if MapManager.wants_message_input():
		return
	if UIInput.is_cancel(event):
		# Bail out any time before the fish is actually on the bank.
		if _state in [State.CAST, State.WAIT, State.SINK, State.BITE, State.FIGHT]:
			get_viewport().set_input_as_handled()
			_scare_fish()
			_begin_retract("")
		return
	if not UIInput.is_accept(event):
		return
	get_viewport().set_input_as_handled()
	match _state:
		State.CAST, State.WAIT, State.SINK:
			# Yanked too early: the fish bolts, nothing is lost but the cast.
			_scare_fish()
			_begin_retract("")
		State.BITE:
			_hook()
		State.FIGHT:
			# Reeling is a mash. A press lands a notch while the fish is blown, and is a
			# costly mistake at any other time -- the player can always try, and pays for
			# it if the fish still has fight in it.
			if _rest_left > 0.0:
				_reel_step()
			else:
				_tension += TENSION_WRONG_PRESS


# ============================================================
# 1 -- ROD PULL-OUT
# ============================================================

func _process_shake() -> void:
	var step := int(_time / (SHAKE_TIME / float(SHAKE_STEPS.size())))
	_set_shake(SHAKE_STEPS[clampi(step, 0, SHAKE_STEPS.size() - 1)])
	if _time >= SHAKE_TIME:
		_set_shake(0.0)
		_face(_counterclockwise(_facing))
		_set_state(State.TURN_AWAY)


func _process_turn() -> void:
	if _time < TURN_TIME:
		return
	if _state == State.TURN_AWAY:
		_face(_counterclockwise(_facing))
		_set_state(State.TURN_BACK)
	else:
		_set_state(State.FLICK)


func _process_flick() -> void:
	if _time < FLICK_PAUSE:
		return
	var t := clampf((_time - FLICK_PAUSE) / FLICK_TIME, 0.0, 1.0)
	_rod_angle = lerpf(_raised_angle(), _rest_angle(), t)
	_apply_rod()
	_snap_bobber_to_tip()
	if t >= 1.0:
		_start_cast()


func _set_shake(offset: float) -> void:
	if _player != null and _player.animated_sprite != null:
		_player.animated_sprite.position.x = offset


## Turns the player and moves the rod to whichever hand position that facing uses.
func _face(direction: String) -> void:
	_facing = direction
	if _player != null:
		_player.set_direction(direction)
	var want_vertical := direction == "up" or direction == "down"
	if want_vertical != _vertical_rod:
		_vertical_rod = want_vertical
		_rod.texture = FishingArt.rod_texture(_vertical_rod)
		_rod.offset = -FishingArt.rod_pivot(_vertical_rod)
	_rod_angle = _raised_angle()
	_apply_depth()
	_apply_rod()
	_snap_bobber_to_tip()


func _apply_rod() -> void:
	if _player == null:
		return
	_rod.global_position = _player.global_position + HAND_OFFSET.get(_facing, Vector2.ZERO)
	# A negative x scale mirrors the rod about its handle, which is what "flip it so the
	# red tip points left" means. Scale is applied before rotation, so the angle below
	# still reads clockwise on screen either way.
	_rod.scale = Vector2(-ROD_SCALE if _facing == "left" else ROD_SCALE, ROD_SCALE)
	_rod.rotation_degrees = _rod_angle


func _raised_angle() -> float:
	return float(ROD_RAISED_ANGLE.get(_facing, 0.0))


func _rest_angle() -> float:
	return float(ROD_REST_ANGLE.get(_facing, 0.0))


## Where the line leaves the rod: the red tip, in global space.
func _rod_tip() -> Vector2:
	return _rod.to_global(FishingArt.rod_tip(_vertical_rod) + _rod.offset)


# ============================================================
# 2 -- THE CAST
# ============================================================

func _start_cast() -> void:
	_cast_dir = _dir_vector(water_dir)
	if water_dir == "left" or water_dir == "right":
		_cast_dir = (_cast_dir + Vector2.DOWN * CAST_DROP).normalized()
	# Fast out of the rod, coasting to a stop: distance = speed * time / 2.
	_cast_speed = 2.0 * CAST_DISTANCE / CAST_TIME
	_bobber_pos = _rod_tip()
	_sfx("cast")
	_set_state(State.CAST)


func _process_cast(delta: float) -> void:
	var t := clampf(_time / CAST_TIME, 0.0, 1.0)
	_bobber_pos += _cast_dir * _cast_speed * (1.0 - t) * delta
	_place_bobber(_bobber_pos)
	if t >= 1.0:
		_land_bobber()


func _land_bobber() -> void:
	_splash(_bobber_pos)
	_sfx("splash")
	_set_bobber_frame(BOBBER_IDLE_FRAMES[0])
	_spawn_fish()
	_set_state(State.WAIT)


func _splash(at: Vector2) -> void:
	PixelBurst.fire(get_parent(), at, PokemonSurfacer.SPLASH_COLOURS,
			SPLASH_COUNT, SPLASH_SPEED, 6.0, 1)


## Moves the bobber so its TOP ORANGE PIXEL lands on `global_point`.
func _place_bobber(global_point: Vector2) -> void:
	_bobber_pos = global_point
	_bobber.global_position = global_point


func _set_bobber_frame(frame: int) -> void:
	_bobber_frame = clampi(frame, 0, FishingArt.BOBBER_FRAMES - 1)
	_bobber.texture = FishingArt.bobber_texture(_bobber_frame)
	# Origin = the top orange pixel, so the line always ties on in the same place.
	_bobber.offset = -FishingArt.bobber_top(_bobber_frame)


func _snap_bobber_to_tip() -> void:
	_place_bobber(_rod_tip())


## Where a fish aims: the bottom of the submerged part of the bobber.
func _bobber_bottom() -> Vector2:
	return _bobber.to_global(FishingArt.bobber_bottom(_bobber_frame) + _bobber.offset)


# ============================================================
# 3 -- THE FISH
# ============================================================

func _spawn_fish() -> void:
	_fish_species = FishingData.pick_fish(map_data)
	if _fish_species == "":
		return  # nothing lives here at this hour; the player reels in by hand
	_fish = Sprite2D.new()
	_fish.centered = false
	_fish.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fish.scale = Vector2(FISH_SCALE, FISH_SCALE)
	_fish.modulate.a = 0.0
	add_child(_fish)
	move_child(_fish, 0)  # always under the rod, the line and the bobber
	_set_fish_frame(0)
	var lateral := _perp * randf_range(-FISH_SPAWN_LATERAL, FISH_SPAWN_LATERAL)
	_fish.global_position = _bobber_pos + _cast_dir * FISH_SPAWN_DISTANCE + lateral
	_fish_speed = randf_range(FISH_SPEED_MIN, FISH_SPEED_MAX)
	_fish_start_gap = maxf(1.0, _fish.global_position.distance_to(_bobber_bottom()))
	_fish_alpha = 0.0
	_aim_fish(_bobber_bottom() - _fish.global_position)


func _set_fish_frame(frame: int) -> void:
	_fish_frame = frame
	_fish.texture = FishingArt.fish_texture(frame)
	# Origin = the head, so it swims and turns about its nose.
	_fish.offset = -FishingArt.fish_head(frame)


## Points the fish's head along `direction`. The art swims "up" at rotation 0.
func _aim_fish(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0001:
		return
	_fish_aim = direction.normalized()
	_fish.rotation = Vector2.UP.angle_to(_fish_aim)


func _update_fish_anim(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	# Calm on the way in, thrashing once it is hooked, idling while it is out of energy.
	var anim_scale := 1.0
	if _state == State.FIGHT or _state == State.CATCH_PAUSE_STATE:
		anim_scale = FISH_ANIM_TIRED_SCALE if _energy <= 0.0 else FISH_ANIM_FIGHT_SCALE
	_fish_anim += delta * FISH_ANIM_FPS * anim_scale
	var frames: Array = FISH_CALM_FRAMES
	if _fish_fleeing or (_state == State.FIGHT and _energy > 0.0):
		frames = FISH_FAST_FRAMES
	var want: int = frames[int(_fish_anim) % frames.size()]
	if want != _fish_frame:
		_set_fish_frame(want)


func _process_wait(delta: float) -> void:
	_bobber_anim += delta * BOBBER_IDLE_FPS
	_set_bobber_frame(BOBBER_IDLE_FRAMES[int(_bobber_anim) % BOBBER_IDLE_FRAMES.size()])
	if _fish == null or not is_instance_valid(_fish):
		return
	_fish_alpha = minf(1.0, _fish_alpha + delta / FISH_FADE_IN)
	_fish.modulate.a = _fish_alpha * FISH_ALPHA

	var target := _bobber_bottom()
	var to_target := target - _fish.global_position
	var gap := to_target.length()
	_aim_fish(to_target)
	# Speeds up a little as it closes -- 100% of its rolled speed at the far end,
	# FISH_CLOSING_BOOST faster by the time it arrives.
	var closed := clampf(1.0 - gap / _fish_start_gap, 0.0, 1.0)
	var speed := _fish_speed * (1.0 + FISH_CLOSING_BOOST * closed)
	if gap <= speed * delta:
		_fish.global_position = target
		_bite_delay = randf_range(BITE_DELAY_MIN, BITE_DELAY_MAX)
		_sink_from_frame = _bobber_frame
		_set_state(State.SINK)
		return
	_fish.global_position += to_target.normalized() * speed * delta


# ============================================================
# 4/5 -- THE BITE
# ============================================================

func _process_sink() -> void:
	if _time < _bite_delay:
		return
	var t := clampf((_time - _bite_delay) / BOBBER_SINK_TIME, 0.0, 1.0)
	var last := FishingArt.BOBBER_FRAMES - 1
	_set_bobber_frame(int(round(lerpf(float(_sink_from_frame), float(last), t))))
	# The line ties to the top pixel, which is sinking with it.
	_place_bobber(_bobber_pos)
	if t >= 1.0:
		# It has taken the bait under -- one big boil of water at its mouth.
		_fish_splash("big")
		_show_exclamation()
		_sfx("fight")
		_set_state(State.BITE)


func _show_exclamation() -> void:
	_exclamation = Sprite2D.new()
	_exclamation.texture = FishingArt.exclamation_texture()
	_exclamation.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_exclamation)
	if _fish != null and is_instance_valid(_fish):
		_exclamation.global_position = _fish.global_position + Vector2.UP * EXCLAMATION_OFFSET


func _hide_exclamation() -> void:
	if _exclamation != null and is_instance_valid(_exclamation):
		_exclamation.queue_free()
	_exclamation = null


func _process_bite(_delta: float) -> void:
	if _time < BITE_WINDOW:
		return
	# Too slow.
	_hide_exclamation()
	_scare_fish()
	_begin_retract(ESCAPED_MESSAGE)


## Hooked in time: the bobber goes away and the line runs straight to the fish.
func _hook() -> void:
	_hide_exclamation()
	_bobber.visible = false
	_tension = 0.0
	_energy = ENERGY_START
	_fight_side = 1.0 if randf() < 0.5 else -1.0
	_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)
	_rest_left = 0.0
	if _fish != null and is_instance_valid(_fish):
		# Where it is hooked is where the leash starts: it works in and out from here and
		# only ever gets closer by being reeled.
		_leash = (_fish.global_position - _player.global_position).dot(_cast_dir)
		_set_surge(1.0)
		# Turns on the spot about its head, which is what the hook is through.
		_fish.rotation += PI
		_fish_aim = -_fish_aim
	_set_state(State.FIGHT)


# ============================================================
# 6 -- TUG OF WAR
# ============================================================

func _process_fight(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish):
		_begin_retract(ESCAPED_MESSAGE)
		return

	var resting := _rest_left > 0.0
	if resting:
		_rest_left -= delta
		if _rest_left <= 0.0:
			# Second wind: back to full energy and off it goes again.
			_energy = ENERGY_START
			_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)

	_fight_switch -= delta
	if _fight_switch <= 0.0:
		_fight_side = -_fight_side
		_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)

	# The player counters the way the fish is TRAVELLING, not where it happens to be:
	# running left means pull right. _fight_side is its current direction along _perp.
	var pulled := _axis_input()
	var correct := pulled != 0.0 and pulled == -_fight_side
	if resting:
		# The whole point of the rest: the line settles back to neutral from either side
		# while the player mashes, so the next run starts from a clean slate.
		_tension = move_toward(_tension, 0.0, TENSION_REST_RECOVER * delta)
	elif pulled != 0.0 and not correct:
		_tension += TENSION_WRONG * delta
	elif correct:
		# Costs the line nothing; it just wears the fish down.
		_tension += TENSION_CORRECT * delta
		_energy -= ENERGY_DRAIN * delta
		if _energy <= 0.0:
			_rest_left = randf_range(REST_TIME_MIN, REST_TIME_MAX)
	else:
		_tension -= TENSION_DECAY * delta
	# Blown beats everything: a fish with nothing left barely ripples the surface.
	if resting:
		_tick_fight_splashes(delta, "tired")
	else:
		_tick_fight_splashes(delta, "wrong" if (pulled != 0.0 and not correct) else "correct")

	if absf(_tension) >= TENSION_LIMIT:
		_scare_fish()
		_begin_retract(BREAK_MESSAGE if _tension > 0.0 else ESCAPED_MESSAGE)
		return

	# Side to side across the cast, and in and out along it between the leash and
	# FIGHT_SURGE beyond it.
	var tired := TIRED_SPEED_FACTOR if resting else 1.0
	var run := _perp * _fight_side * FIGHT_LATERAL_SPEED \
			+ _cast_dir * _surge_dir * _surge_speed
	_fish.global_position += run * tired * delta
	_aim_fish(run)
	if _clamp_to_cone():
		# Ran into the wall of the cone: turn round and dash back the other way.
		_fight_side = -_fight_side
		_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)
	_clamp_to_leash()


## One Space/Enter press while the fish is blown: drags the leash in a notch and hauls the
## fish in with it. Pressing at any other time is a mistake, handled in _input().
func _reel_step() -> void:
	_leash = maxf(0.0, _leash - REEL_STEP)
	_fish.global_position -= _cast_dir * REEL_STEP
	_clamp_to_cone()
	_clamp_to_leash()
	if _leash <= CATCH_DISTANCE:
		_start_catch()


## Holds the fish between its leash and FIGHT_SURGE beyond it, turning it round at either
## end so it works in and out rather than drifting away for good.
func _clamp_to_leash() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var radial := (_fish.global_position - _player.global_position).dot(_cast_dir)
	if radial < _leash:
		_fish.global_position += _cast_dir * (_leash - radial)
		_set_surge(1.0)
	elif radial > _leash + FIGHT_SURGE:
		_fish.global_position -= _cast_dir * (radial - _leash - FIGHT_SURGE)
		_set_surge(-1.0)


func _set_surge(direction: float) -> void:
	_surge_dir = direction
	_surge_speed = randf_range(FIGHT_SURGE_SPEED_MIN, FIGHT_SURGE_SPEED_MAX)


## One burst of water at the hooked fish's mouth (its head is the sprite's origin).
func _fish_splash(tier: String) -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var cfg: Dictionary = FIGHT_SPLASH.get(tier, {})
	if cfg.is_empty():
		return
	PixelBurst.fire(get_parent(), _fish.global_position, PokemonSurfacer.SPLASH_COLOURS,
			int(cfg["count"]), float(cfg["speed"]), float(cfg["width"]), SPLASH_Z)


## Keeps the fish boiling the water while it is hooked, at whatever rate `tier` asks for.
func _tick_fight_splashes(delta: float, tier: String) -> void:
	var cfg: Dictionary = FIGHT_SPLASH.get(tier, {})
	var interval := float(cfg.get("interval", 0.0))
	if interval <= 0.0:
		return
	_splash_timer += delta
	if _splash_timer < interval:
		return
	_splash_timer = 0.0
	_fish_splash(tier)


## Keeps the fish inside the cone opening out from the player, and says whether it had to
## be pushed back in. Sideways room is FIGHT_CONE_MIN at the catch line and grows by
## FIGHT_CONE_SLOPE for every world px further out, so the run shortens as it is landed.
func _clamp_to_cone() -> bool:
	if _fish == null or not is_instance_valid(_fish):
		return false
	var from_player := _fish.global_position - _player.global_position
	var radial := from_player.dot(_cast_dir)
	var across := from_player.dot(_perp)
	var room := FIGHT_CONE_MIN + maxf(0.0, radial - CATCH_DISTANCE) * FIGHT_CONE_SLOPE
	if absf(across) <= room:
		return false
	_fish.global_position -= _perp * (across - signf(across) * room)
	return true


## -1 / 0 / +1 along the axis across the cast. Mirrors the player's own WASD + arrows.
func _axis_input() -> float:
	var low := "left" if _perp == Vector2.RIGHT else "up"
	var high := "right" if _perp == Vector2.RIGHT else "down"
	var value := 0.0
	if _held(high):
		value += 1.0
	if _held(low):
		value -= 1.0
	return value


func _held(direction: String) -> bool:
	match direction:
		"left":
			return Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A)
		"right":
			return Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)
		"up":
			return Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W)
		"down":
			return Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)
	return false


# ============================================================
# THE CATCH
# ============================================================

func _start_catch() -> void:
	_aim_fish(_player.global_position - _fish.global_position)
	_fish_fleeing = false
	# Hand the line over from the fish to the bobber HERE, at the spot it was landed.
	# _update_line() stops following the fish the moment the state leaves FIGHT, and the
	# bobber has been parked out at the original cast splashdown since the hook -- so
	# leaving this until after the pause snapped the line out to full cast range for a
	# tenth of a second.
	_place_bobber(_fish.global_position)
	_set_state(State.CATCH_PAUSE_STATE)


func _process_catch_pause() -> void:
	if _time < CATCH_PAUSE:
		return
	_rod_angle = _raised_angle()
	_apply_rod()
	_build_caught()
	# It comes out of the water where it was landed -- the bobber was already moved onto
	# the fish in _start_catch().
	if _fish != null and is_instance_valid(_fish):
		_fish_splash("huge")
		_place_bobber(_fish.global_position)
		_fish.visible = false
	_bobber.visible = true
	_set_bobber_frame(0)
	_carry_caught()
	_set_state(State.CATCH_YANK)


func _build_caught() -> void:
	_caught = Sprite2D.new()
	_caught.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Hauled up out of the water in front of everything.
	_caught.z_as_relative = false
	_caught.z_index = CAUGHT_Z
	_caught.centered = true
	var sheet: Texture2D = load(OverworldPokemonData.sheet_path(_fish_species))
	if sheet == null:
		return
	_caught_cell = Vector2(sheet.get_width() / 4.0, sheet.get_height() / 4.0)
	_caught_scale = 0.5 * OverworldPokemonData.species_scale(_fish_species)
	_caught.scale = Vector2(_caught_scale, _caught_scale)
	_set_caught_row(1)  # idle_left
	# Hauled out sideways: the left-facing frame turned a quarter turn clockwise.
	_caught.rotation_degrees = 90.0
	add_child(_caught)
	if _fish != null and is_instance_valid(_fish):
		_caught.global_position = _fish.global_position


func _set_caught_row(row: int) -> void:
	if _caught == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = load(OverworldPokemonData.sheet_path(_fish_species))
	atlas.region = Rect2(0.0, row * _caught_cell.y, _caught_cell.x, _caught_cell.y)
	_caught.texture = atlas


func _process_catch_yank(delta: float) -> void:
	# Bobber flies home; the Pokémon hangs off the bottom of it.
	var tip := _rod_tip()
	var to_tip := tip - _bobber_pos
	var step := RETRACT_SPEED * delta
	if to_tip.length() <= step:
		_place_bobber(tip)
		_carry_caught()
		_show_catch_message()
		return
	_place_bobber(_bobber_pos + to_tip.normalized() * step)
	_carry_caught()


func _carry_caught() -> void:
	if _caught == null or not is_instance_valid(_caught):
		return
	var half := _caught_cell.y * _caught_scale * 0.5
	_caught.global_position = _bobber_bottom() + Vector2(0.0, half)


func _show_catch_message() -> void:
	_message_open = true
	_set_state(State.CATCH_MESSAGE)
	var species_name := OverworldPokemonData.display_name(_fish_species)
	MapManager.show_message_then("You caught a %s!" % species_name,
			Callable(self, "_on_catch_message_ok"))


func _on_catch_message_ok() -> void:
	# _on_ok_pressed() hands a pending callback the press and returns WITHOUT closing the
	# box -- a chain is expected to put the next line up. This is the end of the chain, so
	# it closes it (the same thing Player_House_Upstairs does). can_move stays false:
	# _hide_message() restores it as `not cutscene_active`, which is still true here.
	MapManager._hide_message()
	_message_open = false
	if _caught == null or not is_instance_valid(_caught):
		_finish()
		return
	# Back to a normal standing sprite, facing the player, and it hops back in.
	_caught.rotation_degrees = 0.0
	_hop_dir = _dir_vector(water_dir)
	_set_caught_row(int(OverworldPokemon.ROWS.get(_opposite(water_dir), 0)))
	_line.visible = false
	_bobber.visible = false
	_set_state(State.CATCH_HOP)


func _process_catch_hop(delta: float) -> void:
	var t := clampf(_time / HOP_TIME, 0.0, 1.0)
	_caught.offset.y = -HOP_HEIGHT * sin(PI * t) / maxf(_caught_scale, 0.01)
	_caught.global_position += _hop_dir * HOP_SPEED * (1.0 - t) * delta
	if t >= 1.0:
		_enter_water()


## The same sink PokemonSkittish uses when it bolts into the sea -- shared shader, shared
## splash colours -- so a Pokémon going under looks the same wherever it happens.
func _enter_water() -> void:
	_caught.offset.y = 0.0
	var half := _caught_cell.y * _caught_scale * 0.5
	_water_y = _caught.global_position.y + half
	_sink_from = _caught.global_position.y
	_sink_distance = (_caught_cell.y + WATER_CLEAR_ROWS + WATER_FADE_ROWS) * _caught_scale
	_water_material = ShaderMaterial.new()
	_water_material.shader = PokemonSurfacer.water_shader()
	_water_material.set_shader_parameter("water_colour", PokemonSurfacer.WATER_COLOUR)
	_water_material.set_shader_parameter("deep_colour", PokemonSurfacer.DEEP_COLOUR)
	_water_material.set_shader_parameter("tint_rows", 8.0)
	_water_material.set_shader_parameter("above_tint", 0.0)
	_water_material.set_shader_parameter("fade_rows", WATER_FADE_ROWS)
	# The top-down reveal is the surfacing template's trick; push it past the sheet.
	_water_material.set_shader_parameter("reveal_row", _caught_cell.y * 4.0)
	_water_material.set_shader_parameter("reveal_soft", 1.0)
	_caught.material = _water_material
	_update_waterline()
	_splash(Vector2(_caught.global_position.x, _water_y))
	_sfx("splash")
	_set_state(State.CATCH_SINK)


func _process_catch_sink() -> void:
	var t := clampf(_time / SINK_TIME, 0.0, 1.0)
	# Snapped to whole art rows so the blue creeps up a row at a time.
	_caught.global_position.y = _sink_from + snappedf(_sink_distance * t, _caught_scale)
	_update_waterline()
	if t >= 1.0:
		_finish()


func _update_waterline() -> void:
	if _water_material == null:
		return
	var rows_from_cell_top := (_water_y - _caught.global_position.y
			+ _caught_cell.y * _caught_scale * 0.5) / _caught_scale
	var waterline: float = OverworldPokemon.ROWS.get(_opposite(water_dir), 0) * _caught_cell.y \
			+ rows_from_cell_top
	_water_material.set_shader_parameter("waterline_row", waterline)
	_water_material.set_shader_parameter("bottom_row",
			waterline + WATER_CLEAR_ROWS + WATER_FADE_ROWS)


# ============================================================
# FAILURE / CANCEL
# ============================================================

## The fish bolts and fades out, on the darting frames.
func _scare_fish() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	_fish_fleeing = true
	_fish.visible = true
	var away := (_fish.global_position - _player.global_position)
	if away.length_squared() <= 0.0001:
		away = _cast_dir
	_aim_fish(away)


## Starts the retract. `message` is shown at the SAME TIME, over the running animation --
## control comes back once both have finished.
func _begin_retract(message: String) -> void:
	if _state == State.RETRACT or _state == State.DONE:
		return
	_hide_exclamation()
	_bobber.visible = true
	_retract_done = false
	_set_state(State.RETRACT)
	if message != "":
		_message_open = true
		MapManager.show_message_then(message, Callable(self, "_on_fail_message_ok"))


func _on_fail_message_ok() -> void:
	# End of the chain -- see _on_catch_message_ok().
	MapManager._hide_message()
	_message_open = false
	if _retract_done:
		_finish()


func _process_retract(delta: float) -> void:
	if _fish != null and is_instance_valid(_fish) and _fish_fleeing:
		_fish.global_position += _fish_aim * FISH_FLEE_SPEED * delta
		_fish.modulate.a = maxf(0.0, _fish.modulate.a - delta * FISH_ALPHA / FISH_FLEE_FADE)

	if _retract_done:
		if _time >= RETRACT_HOLD and not _message_open:
			_finish()
		return

	# Rod snaps back up as the line comes in.
	_rod_angle = _raised_angle()
	_apply_rod()
	var tip := _rod_tip()
	var to_tip := tip - _bobber_pos
	var step := RETRACT_SPEED * delta
	if to_tip.length() <= step:
		_place_bobber(tip)
		_retract_done = true
		_time = 0.0
		return
	_place_bobber(_bobber_pos + to_tip.normalized() * step)


# ============================================================
# LINE / CAMERA / SOUND
# ============================================================

func _update_line() -> void:
	if _line == null or not _line.visible:
		return
	var from := _rod_tip()
	var to := from
	if _state == State.FIGHT and _fish != null and is_instance_valid(_fish):
		to = _fish.global_position
	else:
		to = _bobber.global_position
	_line.points = PackedVector2Array([to_local(from), to_local(to)])
	_line.default_color = _line_colour()


## White at rest, cooling to a dark blue as the line goes slack and heating to a dark red
## as it is about to snap.
func _line_colour() -> Color:
	if _state != State.FIGHT:
		return LINE_NEUTRAL
	var t := clampf(_tension / TENSION_LIMIT, -1.0, 1.0)
	var near := LINE_TIGHT_NEAR
	var far := LINE_TIGHT_FAR
	if t < 0.0:
		t = -t
		near = LINE_SLACK_NEAR
		far = LINE_SLACK_FAR
	if t <= 0.5:
		return LINE_NEUTRAL.lerp(near, t * 2.0)
	return near.lerp(far, (t - 0.5) * 2.0)


## Frames whatever the player is watching -- the bobber, then the hooked fish -- by
## offsetting the player's own camera, the way the placement tool does.
func _update_camera(delta: float) -> void:
	if _player == null or _player.camera == null:
		return
	var focus := _player.global_position
	if _state == State.FIGHT and _fish != null and is_instance_valid(_fish):
		focus = _fish.global_position
	elif _state in [State.CAST, State.WAIT, State.SINK, State.BITE]:
		focus = _bobber.global_position
	var want := focus - _player.global_position
	_player.camera.offset = _player.camera.offset.lerp(want, clampf(CAMERA_LERP * delta, 0.0, 1.0))


func _sfx(key: String) -> void:
	var path: String = SFX.get(key, "")
	if path != "" and ResourceLoader.exists(path):
		SoundManagerScript.play_sfx_from_path(path)


# ============================================================
# HELPERS / TEARDOWN
# ============================================================

static func _opposite(direction: String) -> String:
	match direction:
		"up": return "down"
		"down": return "up"
		"left": return "right"
		"right": return "left"
	return "down"


## up -> left -> down -> right -> up, the way the player turns while pulling the rod out.
static func _counterclockwise(direction: String) -> String:
	match direction:
		"up": return "left"
		"left": return "down"
		"down": return "right"
		"right": return "up"
	return "down"


static func _dir_vector(direction: String) -> Vector2:
	return OverworldPokemon.DIR_VECTORS.get(direction, Vector2.DOWN)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_set_state(State.DONE)
	_set_shake(0.0)
	if _player != null and _player.camera != null:
		_player.camera.offset = Vector2.ZERO
	MapManager.finish_fishing()
	queue_free()
