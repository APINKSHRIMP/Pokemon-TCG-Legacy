class_name PokemonFlyer
extends OverworldPokemon

## FLYER template -- Pidgey, Wingull, Swellow... Spawned by OverworldPokemonSpawner
## just off the left or right edge of the camera, flies straight across above
## everything (no collision), and despawns once it passes the far edge of the map.
## A flyer whose table row has `"spin": true` cycles its facings as it goes, so it
## turns round and round while drifting across -- faster the faster it flies.

# ---- tweakables -------------------------------------------------------------
## World pixels per second. The map is ~7500px wide, so a full crossing is minutes.
const SPEED := 40.0
## Each FLOCK gets one speed within +/- this fraction of SPEED (the spawner rolls it
## once and hands it to every member, so a flock stays together).
const SPEED_VARIANCE := 0.12
## Drawn above tree canopies (z 10-20) and everything else on the map.
const Z := 60
## Seconds per facing while spinning, for a flyer moving at SPEED. Scaled by
## SPEED / speed, so one flying twice as fast spins twice as fast.
const SPIN_STEP := 0.3
## The walk/flap cycle speeds up and slows down with the flyer's travelling speed
## (SPEED = normal), but never by more than this fraction either way: 0.5 = between
## half speed and one-and-a-half speed.
const ANIM_SPEED_RANGE := 0.5
## A flyer this far from the player (world pixels) is removed outright, freeing its
## slot under OverworldPokemonSpawner.MAX_LIVE_FLYERS for a new flock. 600 world px =
## 1500 px on screen at the default (and widest) 2.5x camera zoom.
const DESPAWN_DISTANCE := 600.0
const SPIN_ORDER := ["down", "left", "up", "right"]
## Ground shadow: a black copy of the current frame, offset down-right (sun from the
## top left). World pixels -- the overworld camera is zoomed 2.5x, so on screen it
## is 2.5x further.
const SHADOW_OFFSET := Vector2(30, 180)
const SHADOW_ALPHA := 0.2
## Just under tree canopies (z 10-20), so the shadow passes beneath them.
const SHADOW_Z := 9
## Up-and-down bob of the bird itself (the shadow stays level, which is what sells
## the height). World pixels of travel above/below the flight line, and seconds per
## full bob. Each bird starts at a random point so a flock doesn't bob in step.
const BOB_PIXELS := 3.0
const BOB_PERIOD := 1.2
## Erratic flyers (Zubat, Golbat): a much bigger bob made of a slow swoop plus a fast
## flutter at an unrelated period, so it never settles into a smooth wave -- the
## jerky up-and-down of a bat. ERRATIC_FLUTTER_SHARE is how much of the height is
## the flutter (0 = one smooth big wave, 1 = all flutter).
const ERRATIC_BOB_PIXELS := 14.0
const ERRATIC_BOB_PERIOD := 0.9
const ERRATIC_FLUTTER_PERIOD := 0.33
const ERRATIC_FLUTTER_SHARE := 0.35
## Bug flyers (butterflies, Ledyba, Cutiefly): the erratic bob made a little smaller
## and smoother -- a lower peak, a slower flutter that is less of the height -- plus a
## smooth surge forward / hang back as they go. BUG_SPEED_WOBBLE is the fraction of
## forward speed either way (0.4 = 40% faster to 40% slower), one full smooth cycle
## every BUG_SPEED_PERIOD seconds.
const BUG_BOB_PIXELS := 10.0
const BUG_BOB_PERIOD := 1.1
const BUG_FLUTTER_PERIOD := 0.45
const BUG_FLUTTER_SHARE := 0.25
const BUG_SPEED_WOBBLE := 0.4
const BUG_SPEED_PERIOD := 2.5
## Ghost flyers (Shedinja, Gastly): the bug's forward surge made wider and far slower,
## a slow float instead of a flutter, and they fade out and back in. Shown for
## GHOST_VISIBLE_MIN..MAX seconds, fade out over GHOST_FADE_TIME, hidden for
## GHOST_HIDDEN_MIN..MAX, fade back in, repeat.
const GHOST_SPEED_WOBBLE := 0.6
const GHOST_SPEED_PERIOD := 9.0
const GHOST_BOB_PIXELS := 6.0
const GHOST_BOB_PERIOD := 3.5
const GHOST_VISIBLE_MIN := 5.0
const GHOST_VISIBLE_MAX := 15.0
const GHOST_HIDDEN_MIN := 5.0
const GHOST_HIDDEN_MAX := 15.0
const GHOST_FADE_TIME := 2.0
## Erratic forward speed -- jagged where bug's is smooth. Every ERRATIC_SPEED_STEP_MIN..MAX
## seconds it picks a new speed up to ERRATIC_SPEED_WOBBLE either way and lurches to it
## (ERRATIC_SPEED_SNAP: higher = more sudden). Each pick leans back towards where the
## bird would be at its steady speed, so it never drifts more than about
## ERRATIC_DRIFT_LIMIT world pixels ahead of or behind its flock.
const ERRATIC_SPEED_WOBBLE := 0.5
const ERRATIC_SPEED_STEP_MIN := 0.2
const ERRATIC_SPEED_STEP_MAX := 0.6
const ERRATIC_SPEED_SNAP := 14.0
const ERRATIC_DRIFT_LIMIT := 24.0
# -----------------------------------------------------------------------------

## +1 flies right, -1 flies left. Set by the spawner before add_child().
var direction: float = 1.0
## Global x past which the flyer is gone. Set by the spawner.
var end_x: float = 0.0
## World pixels per second. The spawner sets one value for the whole flock; <= 0
## rolls a speed of its own.
var speed: float = 0.0
## Turns round and round as it flies. Set by the spawner from the table row.
var spins: bool = false
## Big jerky bob instead of the gentle one. Set by the spawner from the table row.
var erratic: bool = false
## The smaller, smoother bug wobble with butterfly speed changes. Set by the spawner;
## wins over `erratic` if both are somehow on.
var bug: bool = false
var _speed_phase: float = 0.0
## Slow wide drift that fades out and back in. Set by the spawner; wins over bug and
## erratic if more than one is somehow on.
var ghost: bool = false
enum GhostPhase { SHOWN, FADING_OUT, HIDDEN, FADING_IN }
var _ghost_phase: int = GhostPhase.SHOWN
var _ghost_timer: float = 0.0
var _erratic_factor: float = 1.0
var _erratic_target: float = 1.0
var _erratic_timer: float = 0.0
## World pixels ahead (+) or behind (-) of where a steady-speed flight would have put it.
var _erratic_drift: float = 0.0

var _spin_step: float = SPIN_STEP
var _spin_time: float = 0.0
var _spin_index: int = 0
var _shadow: Sprite2D = null
var _bob_time: float = 0.0


static func roll_speed() -> float:
	return SPEED * randf_range(1.0 - SPEED_VARIANCE, 1.0 + SPEED_VARIANCE)


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	if speed <= 0.0:
		speed = roll_speed()
	_make_shadow()
	_bob_time = randf() * BOB_PERIOD
	# Each bug starts somewhere different on its speed wave, so a flock doesn't pulse as one.
	_speed_phase = randf() * TAU
	_ghost_timer = randf_range(GHOST_VISIBLE_MIN, GHOST_VISIBLE_MAX)
	_spin_step = SPIN_STEP * SPEED / maxf(speed, 1.0)
	anim_speed = clampf(speed / SPEED, 1.0 - ANIM_SPEED_RANGE, 1.0 + ANIM_SPEED_RANGE)
	if spins:
		_spin_index = randi() % SPIN_ORDER.size()
		set_facing(SPIN_ORDER[_spin_index])
	else:
		set_facing("right" if direction > 0.0 else "left")


func _template_process(delta: float) -> void:
	global_position.x += direction * speed * _speed_factor(delta) * delta
	if spins:
		_spin_time += delta
		if _spin_time >= _spin_step:
			_spin_time -= _spin_step
			_spin_index = (_spin_index + 1) % SPIN_ORDER.size()
			set_facing(SPIN_ORDER[_spin_index])
	_bob(delta)
	_sync_shadow()
	_update_ghost(delta)
	var player := player_node()
	if player != null and global_position.distance_to(player.global_position) >= DESPAWN_DISTANCE:
		despawn()
		return
	if (direction > 0.0 and global_position.x > end_x) \
			or (direction < 0.0 and global_position.x < end_x):
		despawn()


## Moves only the sprite child, never the node, so the shadow child stays put. Runs
## every frame AFTER any set_facing(): _apply_region() resets sprite.position to zero
## whenever the frame changes. Rounded to whole pixels so the art stays crisp.
func _bob(delta: float) -> void:
	if sprite == null:
		return
	_bob_time += delta
	var height: float
	if ghost:
		height = GHOST_BOB_PIXELS * sin(TAU * _bob_time / GHOST_BOB_PERIOD)
	elif bug:
		height = BUG_BOB_PIXELS * (
				(1.0 - BUG_FLUTTER_SHARE) * sin(TAU * _bob_time / BUG_BOB_PERIOD)
				+ BUG_FLUTTER_SHARE * sin(TAU * _bob_time / BUG_FLUTTER_PERIOD))
	elif erratic:
		height = ERRATIC_BOB_PIXELS * (
				(1.0 - ERRATIC_FLUTTER_SHARE) * sin(TAU * _bob_time / ERRATIC_BOB_PERIOD)
				+ ERRATIC_FLUTTER_SHARE * sin(TAU * _bob_time / ERRATIC_FLUTTER_PERIOD))
	else:
		height = BOB_PIXELS * sin(TAU * _bob_time / BOB_PERIOD)
	sprite.position.y = roundf(height)


## Ghosts: shown for a while, fade out, stay gone for a while, fade back in, forever.
## The whole node fades, so the shadow goes with it (its own 20% black multiplies in).
func _update_ghost(delta: float) -> void:
	if not ghost:
		return
	_ghost_timer -= delta
	match _ghost_phase:
		GhostPhase.SHOWN:
			if _ghost_timer <= 0.0:
				_ghost_phase = GhostPhase.FADING_OUT
				_ghost_timer = GHOST_FADE_TIME
		GhostPhase.FADING_OUT:
			modulate.a = clampf(_ghost_timer / GHOST_FADE_TIME, 0.0, 1.0)
			if _ghost_timer <= 0.0:
				_ghost_phase = GhostPhase.HIDDEN
				_ghost_timer = randf_range(GHOST_HIDDEN_MIN, GHOST_HIDDEN_MAX)
		GhostPhase.HIDDEN:
			if _ghost_timer <= 0.0:
				_ghost_phase = GhostPhase.FADING_IN
				_ghost_timer = GHOST_FADE_TIME
		GhostPhase.FADING_IN:
			modulate.a = clampf(1.0 - _ghost_timer / GHOST_FADE_TIME, 0.0, 1.0)
			if _ghost_timer <= 0.0:
				_ghost_phase = GhostPhase.SHOWN
				_ghost_timer = randf_range(GHOST_VISIBLE_MIN, GHOST_VISIBLE_MAX)


## Multiplier on forward speed this frame. Bug: a smooth surge and hang-back, like a
## butterfly. Erratic: sudden lurches to random speeds, like a bat. Everything else
## flies at a steady speed. The flap and spin rates stay tied to the flock's base
## speed, so the wings don't flicker with it.
func _speed_factor(delta: float) -> float:
	if ghost:
		return 1.0 + GHOST_SPEED_WOBBLE * sin(TAU * _bob_time / GHOST_SPEED_PERIOD + _speed_phase)
	if bug:
		return 1.0 + BUG_SPEED_WOBBLE * sin(TAU * _bob_time / BUG_SPEED_PERIOD + _speed_phase)
	if not erratic:
		return 1.0
	_erratic_timer -= delta
	if _erratic_timer <= 0.0:
		_erratic_timer = randf_range(ERRATIC_SPEED_STEP_MIN, ERRATIC_SPEED_STEP_MAX)
		# Random, but leaning back towards its steady-speed position so the flock holds together.
		var pull := clampf(_erratic_drift / ERRATIC_DRIFT_LIMIT, -1.0, 1.0)
		_erratic_target = 1.0 + randf_range(-ERRATIC_SPEED_WOBBLE, ERRATIC_SPEED_WOBBLE) \
				- pull * ERRATIC_SPEED_WOBBLE
		_erratic_target = maxf(0.1, _erratic_target)
	_erratic_factor = lerpf(_erratic_factor, _erratic_target, minf(1.0, ERRATIC_SPEED_SNAP * delta))
	_erratic_drift += (_erratic_factor - 1.0) * speed * delta
	return _erratic_factor


## modulate multiplies, so black at SHADOW_ALPHA turns every opaque pixel into a flat
## translucent black and leaves transparent pixels transparent.
func _make_shadow() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = sprite.texture
	_shadow.scale = sprite.scale
	_shadow.region_enabled = true
	_shadow.region_filter_clip_enabled = true
	_shadow.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	_shadow.z_as_relative = false
	_shadow.z_index = SHADOW_Z
	_shadow.position = SHADOW_OFFSET
	add_child(_shadow)
	_sync_shadow()


## Mirrors whichever frame the sprite is showing (walk cycle and spin both change it).
func _sync_shadow() -> void:
	if _shadow != null and sprite != null:
		_shadow.region_rect = sprite.region_rect
