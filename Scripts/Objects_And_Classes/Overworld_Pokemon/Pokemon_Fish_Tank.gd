class_name PokemonFishTank
extends OverworldPokemon

## FISH TANK template -- the aquariums in the Fish Shop. One spawn point is one tank,
## and unlike every other template it does not roll: it puts out EVERY species in its
## `fish_table`, `count` of each, inside the swim area drawn with V, and they stay there.
## There is no time of day indoors, so a tank has one table rather than four.
##
## What a fish does:
##   left and right   cruises at its species' Swim speed (registry `tank_speed`) until it
##                    reaches the glass, then turns on the spot -- instantly, no flourish
##                    (the user asked for the spin animation to go) -- and cruises back
##   up and down      very slowly drifts to a height picked anywhere in the swim area,
##                    pauses, then picks another, so given a minute it has wandered the
##                    whole rectangle rather than one line
##   bumping          two fish that come nose to nose both spin round and go back the
##                    way they came (they only see fish in their OWN tank)
##   bubbles          every few seconds a little string of bubbles leaves its mouth and
##                    rises to the surface of the tank, where it pops
##
## Drawing: a tank is indoors, where nothing has a z_index -- the glass front, the sand
## and the walls are all z 0 and the order they are drawn in is the order they sit in the
## scene tree. So a fish is NOT a child of the spawner (that would put it over the glass):
## OverworldPokemonSpawner parents it as a SIBLING of the tank's front layer, one place
## before it. That is the point's `front`, which ANY template may now set -- a bug in a
## tree or an idle Pokemon can be put inside a tank the same way. Everything a fish emits
## (its bubbles) goes in at the fish's own index for the same reason.

# ---- tweakables -------------------------------------------------------------
## Up and down. The fish picks a HEIGHT ANYWHERE IN ITS SWIM AREA and drifts to it at
## DRIFT_SPEED world px/s, pauses now and then, and picks another -- so given a minute it
## has been everywhere in the rectangle, which is the whole point of drawing one.
##
## Two earlier goes at this both read as "they only go left and right": short alternating
## legs (first 2-7 px, then 5-16 px) leave the fish bobbing in a band around wherever it
## spawned and it never crosses the tank. Do not go back to fixed-length legs -- if the
## rise and fall wants toning down, lower the SPEED, which only makes a long journey
## take longer.
const DRIFT_SPEED_MIN := 2.5
const DRIFT_SPEED_MAX := 6.0
## A new target is always at least this much of the swim area's height from where the
## fish is now, so every leg is a real journey rather than a nudge. Tries this many
## random heights and takes the furthest if none of them clears the bar (which is what
## happens in a tank barely taller than the fish).
const DRIFT_MIN_TRAVEL_FRACTION := 0.45
const DRIFT_TARGET_ATTEMPTS := 8
## Chance a finished leg is followed by a pause instead of turning straight round, and
## how long that pause is.
const DRIFT_PAUSE_CHANCE := 0.25
const DRIFT_PAUSE_MIN := 0.4
const DRIFT_PAUSE_MAX := 1.8
## How much of a cell counts as the fish for keeping it inside the glass: 0.5 would be
## the whole cell (most of which is empty space around the art), 0.3 lets it get its
## nose closer to the glass. In a tank too small to give that much away the margin is
## cut down instead (see _swim_bounds) -- an aquarium only 30 px deep would otherwise
## leave the fish no room to drift up and down at all.
const EDGE_MARGIN_FRACTION := 0.3
## The most of a swim area, either way, that the margin above may eat. 0.4 leaves at
## least a fifth of the tank to move in on both axes.
const EDGE_MARGIN_LIMIT := 0.4
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

## Seconds before this fish may turn again, so a nose-to-nose pair cannot jam.
var _bump_cooldown: float = 0.0

## Vertical drift: the height being swum to, how fast, and the pause before setting off.
var _drift_target: float = 0.0
var _drift_speed: float = 0.0
var _drift_pause: float = 0.0

var _bubble_timer: float = 0.0


func _template_ready() -> void:
	# No z of its own: the spawner has already put this node in the right place in the
	# scene tree, between the tank's sand and its glass (see _place_pokemon, which also
	# owns the fallback for a tank whose front object could not be found).
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
## half size, so its art stops at the glass rather than swimming through it.
##
## The margin is never allowed to eat more than EDGE_MARGIN_LIMIT of the area: a big
## Pokemon in a shallow tank would otherwise be left a box of zero height, pinned to the
## middle, which is what "they only move left and right" looked like.
func _swim_bounds() -> Rect2:
	var margin := Vector2(cell.x, cell.y) * draw_scale() * EDGE_MARGIN_FRACTION
	margin.x = minf(margin.x, tank_region.size.x * EDGE_MARGIN_LIMIT)
	margin.y = minf(margin.y, tank_region.size.y * EDGE_MARGIN_LIMIT)
	return Rect2(tank_region.position + margin, tank_region.size - margin * 2.0)


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, _bounds.position.x, _bounds.end.x),
			clampf(pos.y, _bounds.position.y, _bounds.end.y))


func _template_process(delta: float) -> void:
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	_process_swim(delta)
	_process_bumps()
	_process_drift(delta)
	_process_bubbles(delta)


# ---- left and right ---------------------------------------------------------

func _process_swim(delta: float) -> void:
	if _speed <= 0.0:
		return
	global_position.x += _dir * _speed * delta
	# At the glass: pull back to it and turn round.
	if _dir > 0.0 and global_position.x >= _bounds.end.x:
		global_position.x = _bounds.end.x
		_turn_round()
	elif _dir < 0.0 and global_position.x <= _bounds.position.x:
		global_position.x = _bounds.position.x
		_turn_round()


## Turning round is instant: the facing row swaps and it swims back the other way on the
## same frame. (There WAS a squash-through-nothing spin here; the user had it taken out.)
## The only thing left of it is the cooldown, which stops a nose-to-nose pair flipping
## back and forth every frame.
func _turn_round() -> void:
	_dir = -_dir
	set_facing("right" if _dir > 0.0 else "left")
	_bump_cooldown = BUMP_COOLDOWN
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
		if fish.tank_id != tank_id or fish._bump_cooldown > 0.0:
			continue
		var offset := fish.global_position - global_position
		if absf(offset.y) > BUMP_HEIGHT:
			continue
		# In front of me, and close enough that our noses meet.
		if signf(offset.x) != signf(_dir) or absf(offset.x) > reach + fish.cell.x * fish.draw_scale() * BUMP_GAP_FRACTION:
			continue
		_turn_round()
		fish._turn_round()
		return


# ---- up and down ------------------------------------------------------------

func _process_drift(delta: float) -> void:
	if _drift_pause > 0.0:
		_drift_pause -= delta
		return
	var gap := _drift_target - global_position.y
	var step := _drift_speed * delta
	if absf(gap) <= step:
		# Arrived: settle exactly on it and choose somewhere else to be.
		global_position.y = _drift_target
		_start_drift_leg()
		return
	global_position.y += signf(gap) * step


## The next leg: a new height somewhere else in the swim area, a new speed, and
## sometimes a pause before setting off.
func _start_drift_leg() -> void:
	_drift_speed = randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX)
	_drift_target = _pick_drift_target()
	_drift_pause = randf_range(DRIFT_PAUSE_MIN, DRIFT_PAUSE_MAX) if randf() < DRIFT_PAUSE_CHANCE else 0.0


## A height inside the swim area that is a decent distance from the one the fish is at.
## Random rather than "the other half", so the pattern never looks like a metronome.
func _pick_drift_target() -> float:
	var top := _bounds.position.y
	var bottom := _bounds.end.y
	if bottom - top <= 0.5:
		return global_position.y
	var min_travel := (bottom - top) * DRIFT_MIN_TRAVEL_FRACTION
	var best := top
	var best_gap := -1.0
	for attempt in DRIFT_TARGET_ATTEMPTS:
		var candidate := randf_range(top, bottom)
		var gap := absf(candidate - global_position.y)
		if gap >= min_travel:
			return candidate
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


# ---- bubbles ----------------------------------------------------------------

func _process_bubbles(delta: float) -> void:
	_bubble_timer -= delta
	if _bubble_timer > 0.0:
		return
	_bubble_timer = randf_range(BUBBLE_INTERVAL_MIN, BUBBLE_INTERVAL_MAX)
	# The bubbles go in at the FISH'S OWN PLACE IN THE TREE, as a sibling immediately
	# before it. Indoors that position is the draw order, so this is what keeps them
	# behind the tank's glass with the fish instead of rising over the front of it.
	# (A child of the fish would be dragged along by it; a top_level node escapes the
	# tree's ordering altogether and draws over everything -- both were tried.)
	var host := get_parent()
	if host == null:
		return
	var bubbles := FishBubbles.fire(host, _mouth_position(),
			tank_region.position.y + SURFACE_INSET,
			randi_range(BUBBLE_COUNT_MIN, BUBBLE_COUNT_MAX), size_scale)
	# Only matters in the fallback case, where no tank front was found and the fish is
	# drawing at an absolute z of its own.
	bubbles.z_as_relative = z_as_relative
	bubbles.z_index = z_index
	host.move_child(bubbles, get_index())


func _mouth_position() -> Vector2:
	var forward := _facing_dir() * cell.x * draw_scale() * MOUTH_FORWARD
	return global_position + Vector2(forward, -cell.y * draw_scale() * MOUTH_RISE)
