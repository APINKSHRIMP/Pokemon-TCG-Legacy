class_name PokemonHomeWanderer
extends OverworldPokemon

## HOME template (2026-11-24) -- a Pokémon living in your house, not following you.
## It potters about near where it was put: walk a short way, stand a while, walk again,
## bumping off walls and furniture (it collides like a route walker). Space to talk:
## MapManager offers to take it out with you (PokemonHome has the rules).
## RESTING (spawn_resting): it stays put on its bed in the bedroom instead -- asleep at night
## (still, with a floating "z"), or swimming in a water tank by day.
## Spawned by PokemonHome.refresh_house() from MapManager.initialise() in the house.

const GROUP := "home_pokemon"

# ---- tweakables -------------------------------------------------------------
const Z := 1
## How far from its home spot it wanders (world px).
const WANDER_RADIUS := 40.0
const WANDER_SPEED := 28.0
## Seconds it stands between walks (random in this range).
const PAUSE_MIN := 1.5
const PAUSE_MAX := 4.5
## A walk longer than this many seconds gives up (stuck on furniture).
const MAX_WALK_TIME := 3.0
const COLLISION_SIZE := Vector2(12, 8)
const COLLISION_OFFSET := Vector2(0, 5)
## Resting on a bed: drawn above the bed (PokemonBedSpot.Z) and below the player.
const RESTING_Z := 1
## Asleep at the foot of YOUR bed: over the bed sprite (the bedroom's own hop uses 2 too).
const ON_PLAYER_BED_Z := 2
## The sleeping "z": seconds per float, how far it rises (world px), its size.
const SLEEP_Z_PERIOD := 1.8
const SLEEP_Z_RISE := 10.0
const SLEEP_Z_FONT_SIZE := 9

## MEETINGS (user 2026-11-26): two wanderers that bump into each other turn to face each
## other and take turns doing a little move (MEET_MOVES), MEET_TURNS_MIN..MAX turns in all,
## then go separate ways: each walks AWAY from the other for its next AVOID_MOVES walks and
## can't meet anyone again for MEET_COOLDOWN_MIN..MAX seconds.
## How close (world px, centre to centre) counts as bumping.
const BUMP_DISTANCE := 18.0
const MEET_TURNS_MIN := 2
const MEET_TURNS_MAX := 10
const MEET_COOLDOWN_MIN := 60.0
const MEET_COOLDOWN_MAX := 120.0
## No meetings for this long after it appears (so two placed close don't meet at once).
const SPAWN_COOLDOWN_MIN := 5.0
const SPAWN_COOLDOWN_MAX := 20.0
const AVOID_MOVES := 3
## How far either side of "straight away from it" an avoiding walk may head (degrees).
const AVOID_SPREAD_DEG := 60.0
## Pauses: before the first move (facing each other), between moves, after the last.
const MEET_FACE_PAUSE := 0.3
const MEET_GAP := 0.12
const MEET_END_PAUSE := 0.35
## The moves. HOP: height (its own drawn px) and time per half-hop.
const MEET_HOP_PX := 4.0
const MEET_HOP_HALF := 0.12
## WIGGLE: side px, swings, seconds per swing.
const MEET_WIGGLE_PX := 2.0
const MEET_WIGGLE_SWINGS := 8
const MEET_WIGGLE_TIME := 0.06
## LOOK AROUND / LOOK AWAY: seconds held per look.
const MEET_LOOK_TIME := 0.25
const MEET_LOOK_AWAY_TIME := 0.45
## The meeting cry (user 2026-11-26): as each one does its move it gives the first
## MEET_CRY_FRACTION of its cry at MEET_CRY_PITCH (pitch AND speed: 1.25 = 25% higher and
## faster). MEET_CRY_EVERY_TURN false = only on each one's first move.
const MEET_CRY_FRACTION := 1.0 / 3.0
const MEET_CRY_PITCH := 1.25
const MEET_CRY_LEVEL := 0.85
const MEET_CRY_EVERY_TURN := true
## A = hop a couple of times, B = wiggle, C = look one way, the other, back,
## D = look away then back, E = one hop.
const MEET_MOVES := ["hops", "wiggle", "look_around", "look_away", "hop"]
# -----------------------------------------------------------------------------

var home: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _walking: bool = false
var _timer: float = 0.0
var _talking: bool = false
## On a bed: never moves. `seat` = where its feet go (global).
var resting: bool = false
var asleep: bool = false
var seat: Vector2 = Vector2.ZERO
var _sleep_z: Label = null
## MEETINGS: in one now / seconds until it can meet again / walks left heading away from
## `_avoid_from` (where the other one was).
var meeting: bool = false
var _meet_cooldown: float = 0.0
var _avoid_moves: int = 0
var _avoid_from: Vector2 = Vector2.ZERO


static func spawn(map_root: Node, species_key: String, at: Vector2) -> PokemonHomeWanderer:
	var w := PokemonHomeWanderer.new()
	w.configure(PokemonHome.species_of(species_key))   # species_key is its ID ("..#2")
	w.pokemon_id = species_key
	w.display_name = PokemonHome.name_of(species_key)   # its nickname, if it has one
	w.shiny = PokemonHome.is_shiny(species_key)
	w.position = at - (map_root as Node2D).global_position if map_root is Node2D else at
	map_root.add_child(w)
	return w


## On a bed (or in a tank): feet on `seat_global`, asleep or not.
static func spawn_resting(map_root: Node, species_key: String, seat_global: Vector2, is_asleep: bool) -> PokemonHomeWanderer:
	var w := PokemonHomeWanderer.new()
	w.configure(PokemonHome.species_of(species_key))   # species_key is its ID ("..#2")
	w.pokemon_id = species_key
	w.display_name = PokemonHome.name_of(species_key)   # its nickname, if it has one
	w.shiny = PokemonHome.is_shiny(species_key)
	w.resting = true
	w.asleep = is_asleep
	w.seat = seat_global
	w.position = seat_global - (map_root as Node2D).global_position if map_root is Node2D else seat_global
	map_root.add_child(w)
	return w


## Where the node goes so the art's lowest row sits on `feet_global`.
func node_pos_for_feet(feet_global: Vector2) -> Vector2:
	return feet_global - Vector2(0, (art_bottom + 1 - cell.y * 0.5) * draw_scale())


## Lie down where it is now: still, facing down, with the floating z.
func fall_asleep() -> void:
	asleep = true
	resting = true
	_walking = false
	velocity = Vector2.ZERO
	animating = false
	set_facing("down")
	_frame = 0
	_apply_region()
	if _sleep_z == null:
		_start_sleep_z()


## Talked to while asleep (user 2026-11-25): it wakes up, but stays on its bed.
func wake_up() -> void:
	if not asleep:
		return
	asleep = false
	animating = true
	if _sleep_z != null:
		_sleep_z.free()   # now, not at frame end: its looping tween's callbacks use _sleep_z
		_sleep_z = null


func _template_ready() -> void:
	add_to_group(GROUP)
	add_to_group("pokemon")
	z_as_relative = false
	z_index = Z
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = COLLISION_SIZE * size_scale
	shape.shape = rect
	shape.position = COLLISION_OFFSET * size_scale
	add_child(shape)
	home = global_position
	animating = true   # the idle cycle runs standing too, like every follower
	_timer = randf_range(0.3, PAUSE_MAX)
	_meet_cooldown = randf_range(SPAWN_COOLDOWN_MIN, SPAWN_COOLDOWN_MAX)
	if resting:
		z_index = RESTING_Z
		global_position = node_pos_for_feet(seat)
		home = global_position
		set_facing("down")
		if asleep:
			fall_asleep()


func _start_sleep_z() -> void:
	_sleep_z = Label.new()
	_sleep_z.text = "z"
	_sleep_z.add_theme_font_size_override("font_size", SLEEP_Z_FONT_SIZE)
	_sleep_z.add_theme_color_override("font_color", Color(1, 1, 1))
	_sleep_z.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	_sleep_z.add_theme_constant_override("outline_size", 3)
	_sleep_z.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_z.z_index = 5
	add_child(_sleep_z)
	var top := (art_top - cell.y * 0.5) * draw_scale()
	var start := Vector2(4, top - 10)
	var tween := _sleep_z.create_tween().set_loops()
	tween.tween_callback(func():
		_sleep_z.position = start
		_sleep_z.modulate.a = 0.0)
	tween.tween_property(_sleep_z, "modulate:a", 1.0, SLEEP_Z_PERIOD * 0.3)
	tween.parallel().tween_property(_sleep_z, "position", start + Vector2(4, -SLEEP_Z_RISE), SLEEP_Z_PERIOD)
	tween.tween_property(_sleep_z, "modulate:a", 0.0, SLEEP_Z_PERIOD * 0.3)


func is_interactable() -> bool:
	return not _is_gone


func cry_text() -> String:
	if asleep:
		return "%s is fast asleep." % display_name
	return "%s is happy to be at home!" % display_name


func pause_and_face(target_global: Vector2) -> void:
	_talking = true
	_walking = false
	velocity = Vector2.ZERO
	if not asleep:
		face_vector(target_global - global_position)


func resume_movement() -> void:
	_talking = false
	_timer = randf_range(PAUSE_MIN, PAUSE_MAX)


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null or _talking or resting or meeting:
		return
	_meet_cooldown -= delta
	if _walking and _meet_cooldown <= 0.0:
		var other := _bumped_into()
		if other != null:
			_meet(self, other)
			return
	_timer -= delta
	if not _walking:
		if _timer <= 0.0:
			if _avoid_moves > 0:
				# Separate ways after a meeting: a walk from HERE, heading away from it, and
				# its wander centre moves with it.
				_avoid_moves -= 1
				var away := global_position - _avoid_from
				var heading := (away.angle() if away.length() > 0.5 else randf() * TAU) \
						+ deg_to_rad(randf_range(-AVOID_SPREAD_DEG, AVOID_SPREAD_DEG))
				_target = global_position + Vector2.from_angle(heading) * randf_range(WANDER_RADIUS * 0.5, WANDER_RADIUS)
				home = _target
			else:
				var angle := randf() * TAU
				_target = home + Vector2.from_angle(angle) * randf_range(WANDER_RADIUS * 0.3, WANDER_RADIUS)
			_walking = true
			_timer = MAX_WALK_TIME
		return
	var to := _target - global_position
	if to.length() < 2.0 or _timer <= 0.0:
		_walking = false
		_timer = randf_range(PAUSE_MIN, PAUSE_MAX)
		if _avoid_moves > 0:
			home = global_position   # (stopped short by furniture: wander from where it got to)
		return
	velocity = to.normalized() * WANDER_SPEED
	face_vector(velocity)
	move_and_slide()


# ---- meetings -------------------------------------------------------------------

func _can_meet() -> bool:
	return not (_is_gone or sprite == null or _talking or resting or asleep or meeting) \
			and _meet_cooldown <= 0.0 and is_inside_tree()


## Another wanderer it has just walked into (and that's free to meet), null for none.
func _bumped_into() -> PokemonHomeWanderer:
	for node in get_tree().get_nodes_in_group(GROUP):
		var other := node as PokemonHomeWanderer
		if other == null or other == self or not other._can_meet():
			continue
		if global_position.distance_to(other.global_position) <= BUMP_DISTANCE:
			return other
	return null


## The meeting: face each other, take turns doing a move, then go separate ways. Talking to
## either of them (or one leaving) ends it early.
static func _meet(a: PokemonHomeWanderer, b: PokemonHomeWanderer) -> void:
	for p in [a, b]:
		p.meeting = true
		p._walking = false
		p.velocity = Vector2.ZERO
	a.face_vector(b.global_position - a.global_position)
	b.face_vector(a.global_position - b.global_position)
	var tree := a.get_tree()
	await tree.create_timer(MEET_FACE_PAUSE).timeout
	var turns := randi_range(MEET_TURNS_MIN, MEET_TURNS_MAX)
	var first: PokemonHomeWanderer = a if randf() < 0.5 else b
	var second: PokemonHomeWanderer = b if first == a else a
	for k in turns:
		if not (_still_meeting(a) and _still_meeting(b)):
			break
		var actor: PokemonHomeWanderer = first if k % 2 == 0 else second
		var other: PokemonHomeWanderer = second if actor == first else first
		if MEET_CRY_EVERY_TURN or k < 2:
			SoundManagerScript.play_cry_part(PokemonHome.species_of(actor.pokemon_id),
					MEET_CRY_PITCH, MEET_CRY_FRACTION, MEET_CRY_LEVEL)
		await actor._do_meet_move(str(MEET_MOVES.pick_random()), other)
		if not (_still_meeting(a) and _still_meeting(b)):
			break
		await tree.create_timer(MEET_GAP).timeout
	if _still_meeting(a) and _still_meeting(b):
		await tree.create_timer(MEET_END_PAUSE).timeout
	for pair in [[a, b], [b, a]]:
		var p: PokemonHomeWanderer = pair[0]
		var o: PokemonHomeWanderer = pair[1]
		if not is_instance_valid(p):
			continue
		p.meeting = false
		p._meet_cooldown = randf_range(MEET_COOLDOWN_MIN, MEET_COOLDOWN_MAX)
		p._avoid_moves = AVOID_MOVES
		if is_instance_valid(o):
			p._avoid_from = o.global_position
		p._timer = randf_range(0.1, 0.5)   # off it goes almost at once
		if p.sprite != null:
			p.sprite.offset = Vector2.ZERO


static func _still_meeting(p: PokemonHomeWanderer) -> bool:
	return is_instance_valid(p) and p.is_inside_tree() and not p._is_gone and not p._talking and p.meeting


## One move, facing `other` again at the end. Each takes about 0.4-1.2 s.
func _do_meet_move(move: String, other: PokemonHomeWanderer) -> void:
	var toward := other.global_position - global_position
	match move:
		"hops":
			await PokemonAffection.hop(self, 2, MEET_HOP_PX, MEET_HOP_HALF)
		"hop":
			await PokemonAffection.hop(self, 1, MEET_HOP_PX, MEET_HOP_HALF * 1.25)
			await get_tree().create_timer(MEET_LOOK_TIME).timeout
		"wiggle":
			var side := MEET_WIGGLE_PX / maxf(draw_scale(), 0.01)
			var tw := sprite.create_tween()
			for k in MEET_WIGGLE_SWINGS:
				tw.tween_property(sprite, "offset:x", side if k % 2 == 0 else -side, MEET_WIGGLE_TIME)
			tw.tween_property(sprite, "offset:x", 0.0, MEET_WIGGLE_TIME)
			await tw.finished
		"look_around":
			# The two ways at right angles to it (facing sideways: up and down).
			var side := Vector2(-toward.y, toward.x)
			var order := [side, -side] if randf() < 0.5 else [-side, side]
			for v in order:
				if not _still_meeting(self):
					return
				face_vector(v)
				await get_tree().create_timer(MEET_LOOK_TIME).timeout
		"look_away":
			face_vector(-toward)
			await get_tree().create_timer(MEET_LOOK_AWAY_TIME).timeout
	if is_instance_valid(other) and _still_meeting(self):
		face_vector(other.global_position - global_position)
		if move.begins_with("look"):
			await get_tree().create_timer(MEET_LOOK_TIME).timeout
