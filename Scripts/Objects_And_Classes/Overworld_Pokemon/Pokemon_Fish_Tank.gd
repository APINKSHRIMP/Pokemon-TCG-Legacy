class_name PokemonFishTank
extends OverworldPokemon

## FISH TANK template -- the aquariums in the Fish Shop. One spawn point is one tank,
## and unlike every other template it does not roll: it puts out EVERY species in its
## `fish_table`, `count` of each, inside the swim area drawn with V, and they stay there.
## There is no time of day indoors, so a tank has one table rather than four.
##
## What a fish does:
##   left and right   cruises at its species' Swim speed (registry `tank_speed`) until it
##                    reaches the glass, then SPINS round (the sprite squashes through
##                    nothing and comes back out facing the other way) and cruises back
##   up and down      very slowly drifts a few pixels up over a few seconds, then a few
##                    down, each leg a different length and speed, so over time it has
##                    wandered the whole rectangle rather than one line
##   bumping          two fish that come nose to nose both spin round and go back the
##                    way they came (they only see fish in their OWN tank)
##   bubbles          every few seconds a little string of bubbles leaves its mouth and
##                    rises to the surface of the tank, where it pops
##
## Drawing: a tank is indoors, where nothing has a z_index -- the glass front, the sand
## and the walls are all z 0 and the order they are drawn in is the order they sit in the
## scene tree. So a fish is NOT a child of the spawner (that would put it over the glass):
## OverworldPokemonSpawner parents it as a SIBLING of the tank's front layer, one place
## before it. Everything a fish emits (its bubbles) is a child of the fish for the same
## reason, kept in world space with `top_level` instead of its own z.

# ---- tweakables -------------------------------------------------------------
## Fallback drawing height, only used when the tank's front object cannot be found.
const FALLBACK_Z := 1
## Seconds the turn-round takes, and how much of the way through it the fish is facing
## the new way (halfway: the sprite is edge-on to us then).
const TURN_TIME := 0.5
## How thin the sprite gets at the middle of the spin. 0 is edge-on and invisible;
## a little more than that keeps a pixel of fish there throughout.
const TURN_MIN_SQUASH := 0.06
## Up-and-down drift. A leg is DRIFT_PIXELS world px taken over DRIFT_SECONDS -- both
## rolled per leg, so no two fish drift together. 4 px over 5 s is 10 on-screen px at
## a crawl, which is the "very very slowly and gently" this is meant to be.
const DRIFT_PIXELS_MIN := 2.0
const DRIFT_PIXELS_MAX := 7.0
const DRIFT_SECONDS_MIN := 2.5
const DRIFT_SECONDS_MAX := 6.0
## Chance a finished leg is followed by a pause instead of turning straight round, and
## how long that pause is.
const DRIFT_PAUSE_CHANCE := 0.35
const DRIFT_PAUSE_MIN := 0.5
const DRIFT_PAUSE_MAX := 2.5
## How much of a cell counts as the fish for keeping it inside the glass: 0.5 would be
## the whole cell (most of which is empty space around the art), 0.3 lets it get its
## nose closer to the glass.
const EDGE_MARGIN_FRACTION := 0.3
## Bumping. Two fish bump when they are within BUMP_GAP_FRACTION of their two half
## widths of each other AND within BUMP_HEIGHT world px of the same height -- one
## passing well under another does not count. After a bump neither can bump again for
## BUMP_COOLDOWN seconds, or a crowded tank would jam nose to nose.
const BUMP_GAP_FRACTION := 0.55
const BUMP_HEIGHT := 7.0
const BUMP_COOLDOWN := 1.5
## Bubbles: a breath every few seconds, of this many bubbles.
const BUBBLE_INTERVAL_MIN := 2.5
const BUBBLE_INTERVAL_MAX := 7.0
const BUBBLE_COUNT_MIN := 2
const BUBBLE_COUNT_MAX := 4
## Where the mouth is, as a fraction of a cell: forward from the centre (the way it is
## facing) and up from the middle.
const MOUTH_FORWARD := 0.26
const MOUTH_RISE := 0.04
## How far below the top of the swim area the bubbles pop.
const SURFACE_INSET := 1.0
## The swimming animation at DEFAULT_TANK_SPEED, and the range it is allowed to scale to.
const SWIM_ANIM_SPEED := 0.6
const SWIM_ANIM_MIN := 0.25
const SWIM_ANIM_MAX := 2.0
# -----------------------------------------------------------------------------

## Set by the spawner before add_child(): which tank this fish belongs to (only fish of
## the same tank bump into each other) and the water it may swim in.
var tank_id: String = ""
var tank_region: Rect2 = Rect2()

var _speed: float = OverworldPokemonData.DEFAULT_TANK_SPEED
## +1 swimming right, -1 swimming left.
var _dir: float = 1.0
## The rectangle the fish's CENTRE stays inside (the region, pulled in by its own size).
var _bounds: Rect2 = Rect2()

## Turning: -1 when not turning, otherwise seconds into the spin.
var _turn_time: float = -1.0
var _bump_cooldown: float = 0.0

## Vertical drift: which way, how far is left of this leg, how fast, and the pause
## before the next one.
var _drift_dir: float = -1.0
var _drift_left: float = 0.0
var _drift_speed: float = 0.0
var _drift_pause: float = 0.0

var _bubble_timer: float = 0.0


func _template_ready() -> void:
	# No z of its own: the spawner has put this node in the right place in the scene
	# tree, between the tank's sand and its glass. Only a fish whose tank object could
	# not be found falls back to an absolute z.
	if z_as_relative == false:
		z_index = FALLBACK_Z
	_speed = OverworldPokemonData.species_tank_speed(species)
	if tank_region.size == Vector2.ZERO:
		tank_region = OverworldPokemonData.tank_region(spawn_point)
	_bounds = _swim_bounds()
	_dir = 1.0 if randf() < 0.5 else -1.0
	set_facing("right" if _dir > 0.0 else "left")
	animating = _speed > 0.0
	anim_speed = SWIM_ANIM_SPEED * clampf(_speed / float(OverworldPokemonData.DEFAULT_TANK_SPEED),
			SWIM_ANIM_MIN, SWIM_ANIM_MAX)
	_start_drift_leg()
	# Staggered, so a tankful does not all breathe out on the same frame.
	_bubble_timer = randf_range(0.0, BUBBLE_INTERVAL_MAX)
	global_position = _clamp_to_bounds(global_position)


## The box the fish's centre may move in: the tank's water pulled in by the fish's own
## half size, so its art stops at the glass rather than swimming through it. A tank too
## small for the fish in it collapses to its centre line instead of inverting.
func _swim_bounds() -> Rect2:
	var margin := Vector2(cell.x, cell.y) * draw_scale() * EDGE_MARGIN_FRACTION
	var size := tank_region.size - margin * 2.0
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2(tank_region.get_center(), Vector2(maxf(size.x, 0.0), maxf(size.y, 0.0)))
	return Rect2(tank_region.position + margin, size)


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, _bounds.position.x, _bounds.end.x),
			clampf(pos.y, _bounds.position.y, _bounds.end.y))


func _template_process(delta: float) -> void:
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	if _turn_time >= 0.0:
		_process_turn(delta)
	else:
		_process_swim(delta)
		_process_bumps()
	_process_drift(delta)
	_process_bubbles(delta)


# ---- left and right ---------------------------------------------------------

func _process_swim(delta: float) -> void:
	if _speed <= 0.0:
		return
	global_position.x += _dir * _speed * delta
	# At the glass: pull back to it and spin round.
	if _dir > 0.0 and global_position.x >= _bounds.end.x:
		global_position.x = _bounds.end.x
		_start_turn()
	elif _dir < 0.0 and global_position.x <= _bounds.position.x:
		global_position.x = _bounds.position.x
		_start_turn()


## The spin: the sprite is squashed horizontally through nothing and back out, swapping
## which way it faces at the thinnest point, so it reads as the fish turning on the spot.
func _start_turn() -> void:
	if _turn_time >= 0.0:
		return
	_turn_time = 0.0
	_bump_cooldown = BUMP_COOLDOWN


func _process_turn(delta: float) -> void:
	_turn_time += delta
	var t := clampf(_turn_time / TURN_TIME, 0.0, 1.0)
	# 1 -> TURN_MIN_SQUASH -> 1.
	var squash: float = lerpf(TURN_MIN_SQUASH, 1.0, absf(cos(PI * t)))
	sprite.scale.x = draw_scale() * squash
	if t >= 0.5 and _facing_dir() == _dir:
		# Halfway: it is edge-on, so this is the frame to swap round.
		_dir = -_dir
		set_facing("right" if _dir > 0.0 else "left")
	if t < 1.0:
		return
	_turn_time = -1.0
	sprite.scale.x = draw_scale()
	global_position = _clamp_to_bounds(global_position)


func _facing_dir() -> float:
	return 1.0 if facing == "right" else -1.0


# ---- bumping ----------------------------------------------------------------

## Nose to nose with another fish of the SAME tank: both turn round. Only the fish in
## front counts -- one catching another up from behind swims past it.
func _process_bumps() -> void:
	if _bump_cooldown > 0.0 or _speed <= 0.0:
		return
	var reach := cell.x * draw_scale() * BUMP_GAP_FRACTION
	for other in get_parent().get_children():
		if not (other is PokemonFishTank) or other == self:
			continue
		var fish: PokemonFishTank = other
		if fish.tank_id != tank_id or fish._bump_cooldown > 0.0 or fish._turn_time >= 0.0:
			continue
		var offset := fish.global_position - global_position
		if absf(offset.y) > BUMP_HEIGHT:
			continue
		# In front of me, and close enough that our noses meet.
		if signf(offset.x) != signf(_dir) or absf(offset.x) > reach + fish.cell.x * fish.draw_scale() * BUMP_GAP_FRACTION:
			continue
		_start_turn()
		fish._start_turn()
		return


# ---- up and down ------------------------------------------------------------

func _process_drift(delta: float) -> void:
	if _drift_pause > 0.0:
		_drift_pause -= delta
		return
	if _drift_left <= 0.0:
		_start_drift_leg()
		return
	var step := minf(_drift_speed * delta, _drift_left)
	var wanted := global_position.y + _drift_dir * step
	var clamped := clampf(wanted, _bounds.position.y, _bounds.end.y)
	global_position.y = clamped
	_drift_left -= step
	# Ran into the top or bottom of the tank: that leg is over, go the other way.
	if not is_equal_approx(wanted, clamped):
		_drift_left = 0.0
		_drift_dir = -_drift_dir


## The next up-or-down leg: the other way from the last one, a random few pixels over a
## random few seconds, sometimes after a pause. Alternating is what makes the fish's
## path over time fill the tank rather than trend one way.
func _start_drift_leg() -> void:
	_drift_dir = -_drift_dir
	var pixels := randf_range(DRIFT_PIXELS_MIN, DRIFT_PIXELS_MAX)
	var seconds := randf_range(DRIFT_SECONDS_MIN, DRIFT_SECONDS_MAX)
	_drift_left = pixels
	_drift_speed = pixels / seconds
	_drift_pause = randf_range(DRIFT_PAUSE_MIN, DRIFT_PAUSE_MAX) if randf() < DRIFT_PAUSE_CHANCE else 0.0


# ---- bubbles ----------------------------------------------------------------

func _process_bubbles(delta: float) -> void:
	_bubble_timer -= delta
	if _bubble_timer > 0.0:
		return
	_bubble_timer = randf_range(BUBBLE_INTERVAL_MIN, BUBBLE_INTERVAL_MAX)
	# Parented to the fish so it is drawn in the same place in the tree (behind the
	# glass), top_level so it stays where it was let go of instead of being towed along.
	FishBubbles.fire(self, _mouth_position(),
			tank_region.position.y + SURFACE_INSET,
			randi_range(BUBBLE_COUNT_MIN, BUBBLE_COUNT_MAX), size_scale)


func _mouth_position() -> Vector2:
	var forward := _facing_dir() * cell.x * draw_scale() * MOUTH_FORWARD
	return global_position + Vector2(forward, -cell.y * draw_scale() * MOUTH_RISE)
