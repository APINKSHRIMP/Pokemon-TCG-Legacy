class_name PokemonSkittish
extends OverworldPokemon

## SKITTISH template -- Rattata, Sentret, Zigzagoon, Ekans... Wanders around its spawn
## point with real collision, bouncing off anything it runs into, at its species' own
## wander speed (registry `wander_speed`).
##
## When the player comes within SCARE_DISTANCE it bolts away from the player, taking
## whichever of the four directions its spawn point allows (`flee`) -- very
## fast and straight through anything in the way, then fades out within a quarter of a
## second and is gone for the rest of this map load. It is drawn under every tree layer, so it can vanish behind
## the trees as it runs.
##
## A spawn point that ticks "Jumps into water" (`into_water`) escapes differently, for the
## Krabby and Psyduck sitting by the sea: it keeps its collision as it bolts, stops dead
## at the first thing it runs into (every water edge has a collider), waits a beat, leaps
## out over the water in an arc, and sinks under the surface with a splash instead of
## fading away. A shadow under it while it is in the air sells the height, and the water
## closing over it is the surfacing template's shader, so the blue matches.

# ---- tweakables -------------------------------------------------------------
## Absolute z. The map's ground tiles and tree trunks are 0 and every tree top / tree
## wall is 1 or higher, and the spawner is added after the tile maps, so 0 draws it
## over the ground but behind the trees (Celeste Harbour and Verdant Forest).
const Z := 0
const WANDER_RADIUS := 140.0
const STEP_MIN := 24.0
const STEP_MAX := 70.0
## The walk cycle follows the wander speed (the default speed = normal), within these.
const WANDER_ANIM_MIN := 0.25
const WANDER_ANIM_MAX := 1.5
## Seconds it stands still between dashes.
const PAUSE_MIN := 0.5
const PAUSE_MAX := 2.2
## Bounces off obstacles allowed in one dash before it gives up and pauses.
const MAX_BOUNCES := 3
## The player this close (world px) sends it running. 100 world px = 250 px on screen at
## the default 2.5x zoom.
const SCARE_DISTANCE := 100.0
## The same for every species, and always faster than the player: the fastest normal
## player is 160 px/s x 1.6 (Fast walking option) x 2 (Shift) = 512 px/s.
const FLEE_SPEED := 640.0
const FLEE_ANIM_SPEED := 3.0
## Seconds of running before it starts to fade, and how long the fade takes. The two
## together are how long it is on screen after being scared -- a quarter of a second, so
## it is a bolt and a blink rather than something the player watches leave. At
## FLEE_SPEED that is still 160 world px (400 on screen) of running before it goes.
const FLEE_FADE_DELAY := 0.05
const FLEE_FADE_TIME := 0.2
## --- "Jumps into water" (spawn point `into_water`) ---
## Nothing to jump into: if it gets this far (world px) without running into anything it
## has long since left the screen, so it just goes rather than leaping at dry land.
const WATER_MAX_RUN := 600.0
## The beat at the water's edge between stopping and jumping.
const WATER_PAUSE_TIME := 0.2
## The leap itself: an arc, whichever way it is running. It carries on that way at
## WATER_LEAP_SPEED, slowing to a stop, while WATER_HOP_HEIGHT lifts it and sets it back
## down -- coming back down is landing in the water. WATER_LEAP_SPEED * WATER_JUMP_TIME
## / 2 is how far it gets: 130 * 0.45 / 2 = 29 world px, about 73 on screen.
const WATER_JUMP_TIME := 0.45
const WATER_HOP_HEIGHT := 14.0
const WATER_LEAP_SPEED := 130.0
## Going under. It sinks straight down through a waterline fixed where it landed, and the
## same shader a surfacing Pokemon uses colours it: a row turns solid blue the moment it
## passes under, stays that way until it is WATER_CLEAR_ROWS deep, then fades out over
## the WATER_FADE_ROWS below that -- so it is watched sinking into the depths rather than
## just switching off. It has to fall its own height plus those two before it is gone,
## and WATER_SINK_TIME is how long all of that takes.
const WATER_SINK_TIME := 0.5
const WATER_CLEAR_ROWS := 5.0
const WATER_FADE_ROWS := 8.0
## How blue the rows just ABOVE the surface turn. 0 leaves them their own colours; the
## surfacing template uses 0.5 over 8 rows (PokemonSurfacer.ABOVE_TINT) if that reads
## better once it is on screen.
const WATER_ABOVE_TINT := 0.0
const WATER_TINT_ROWS := 8.0
## A bigger, faster burst than a surfacing Pokemon's -- this one lands in the water.
const WATER_SPLASH_COUNT := 30
const WATER_SPLASH_SPEED := 1.3
## The shadow under it in mid-air: half-width and half-height in world px (before the
## species' scale), and how black it is.
const WATER_SHADOW_RADII := Vector2(9.0, 3.0)
const WATER_SHADOW_ALPHA := 0.3
const COLLISION_SIZE := Vector2(14, 10)
const COLLISION_OFFSET := Vector2(0, 5)
# -----------------------------------------------------------------------------

## WATER_* are the three beats of the "Jumps into water" escape, after FLEE has run it
## into the bank: the pause at the edge, the leap, and sinking under.
enum State { IDLE, WANDER, FLEE, WATER_PAUSE, WATER_JUMP, WATER_SINK, TALKING }

var _state: int = State.IDLE
var _home: Vector2
var _target: Vector2
var _pause: float = 0.0
var _bounces: int = 0
var _flee_dir: Vector2 = Vector2.RIGHT
var _flee_time: float = 0.0
var _wander_speed: float = OverworldPokemonData.DEFAULT_SKITTISH_WANDER_SPEED
## This spawn point's "Jumps into water" tick.
var _into_water: bool = false
## Seconds into the current WATER_ beat, and how far this escape has run so far.
var _water_time: float = 0.0
var _run_distance: float = 0.0
var _shadow: AirShadow = null
## Sinking: the world y of the surface it went in at (fixed, the sprite falls past it),
## where the fall started and how far it has to go to be out of sight.
var _water_y: float = 0.0
var _sink_from: float = 0.0
var _sink_distance: float = 0.0
var _water_material: ShaderMaterial = null


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Layer 4 is the NPC layer: the player collides with it (mask 5) and the player's
	# InteractionArea (mask 4) sees it. Mask 1 = the world, 4 = other actors.
	collision_layer = 4
	collision_mask = 1 | 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# A scaled-up Pokémon gets a body to match.
	rect.size = COLLISION_SIZE * size_scale
	shape.shape = rect
	shape.position = COLLISION_OFFSET * size_scale
	add_child(shape)
	add_to_group("pokemon")
	animating = false
	_wander_speed = OverworldPokemonData.species_wander_speed(species)
	_into_water = bool(spawn_point.get("into_water", false))
	_home = global_position
	_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
	set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])


func is_interactable() -> bool:
	return not _escaping() and not _is_gone


## Running away, or already on its way into the water: past talking to either way.
func _escaping() -> bool:
	return _state == State.FLEE or _state == State.WATER_PAUSE \
			or _state == State.WATER_JUMP or _state == State.WATER_SINK


func _physics_process(delta: float) -> void:
	if _is_gone or sprite == null:
		return
	match _state:
		State.TALKING:
			velocity = Vector2.ZERO
			return
		State.FLEE:
			_process_flee(delta)
			return
		State.WATER_PAUSE, State.WATER_JUMP, State.WATER_SINK:
			_process_water(delta)
			return

	if _should_flee():
		_start_flee()
		return

	if _state == State.IDLE:
		_pause -= delta
		if _pause <= 0.0:
			if _wander_speed > 0.0:
				_pick_target()
			else:
				# Wander speed 0 (Sudowoodo, Bonsly): stands its ground, glancing about.
				_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
				set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])
		return

	# WANDER
	var to_target := _target - global_position
	if to_target.length() < 2.0:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
		return
	var heading := to_target.normalized()
	velocity = heading * _wander_speed
	face_vector(heading)
	move_and_slide()
	if get_slide_collision_count() > 0 and get_real_velocity().length() < _wander_speed * 0.5:
		_bounces += 1
		if _bounces > MAX_BOUNCES:
			_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
			return
		# Bounce: carry on the remaining distance along the reflected heading.
		var normal := get_slide_collision(0).get_normal()
		var bounced := heading.bounce(normal).normalized()
		if bounced.length() < 0.001:
			bounced = normal
		_target = global_position + bounced * maxf(to_target.length(), STEP_MIN)
		if _target.distance_to(_home) > WANDER_RADIUS:
			_target = global_position + (_home - global_position).normalized() * STEP_MIN


func _pick_target() -> void:
	var angle := randf() * TAU
	var candidate := global_position + Vector2.from_angle(angle) * randf_range(STEP_MIN, STEP_MAX)
	if candidate.distance_to(_home) > WANDER_RADIUS:
		candidate = global_position + (_home - global_position).normalized() * randf_range(STEP_MIN, STEP_MAX)
	_target = candidate
	_bounces = 0
	_state = State.WANDER
	animating = true
	# A slow Ekans shuffles, a quick Sentret scurries: the walk cycle keeps pace.
	anim_speed = clampf(_wander_speed / OverworldPokemonData.DEFAULT_SKITTISH_WANDER_SPEED,
			WANDER_ANIM_MIN, WANDER_ANIM_MAX)
	_apply_region()


func _go_idle(pause: float) -> void:
	velocity = Vector2.ZERO
	_state = State.IDLE
	_pause = pause
	animating = false
	_apply_region()


# ---- running away -----------------------------------------------------------

## Close enough, whatever the player is doing -- unless a message box or cutscene has
## the player held still.
func _should_flee() -> bool:
	var player := player_node()
	if player == null:
		return false
	if "can_move" in player and not player.can_move:
		return false
	return global_position.distance_to(player.global_position) <= SCARE_DISTANCE


func _start_flee() -> void:
	_state = State.FLEE
	_flee_time = 0.0
	_flee_dir = _flee_direction()
	_run_distance = 0.0
	# Off the NPC layer so the player's InteractionArea lets go of it (no bubble, no
	# Space), and no mask so it runs straight through fences and behind trees -- except
	# when it is heading for water, where running into something is the whole point. Mask
	# 1 is the world (the water's edge), not other actors: an NPC in the way is not a bank.
	collision_layer = 0
	collision_mask = 1 if _into_water else 0
	hide_bubble()
	remove_from_group("pokemon")
	animating = true
	anim_speed = FLEE_ANIM_SPEED
	face_vector(_flee_dir)
	_apply_region()


## Out of the directions its spawn point allows, the ones that take it further from the
## player -- picked at random when more than one does, so a Pokémon walked up on from
## the top left bolts right or down at random rather than always the same way. Nothing
## heads away when the player is dead level on both axes (or there is no player), and a
## point may allow only directions that run towards them; either way it falls back to a
## random pick of everything allowed.
func _flee_direction() -> Vector2:
	var allowed: Array[Vector2] = []
	for name in OverworldPokemonData.flee_directions(spawn_point):
		allowed.append(DIR_VECTORS[str(name)])
	var player := player_node()
	if player != null:
		var away := global_position - player.global_position
		var outward: Array[Vector2] = []
		for direction in allowed:
			if direction.dot(away) > 0.0:
				outward.append(direction)
		if not outward.is_empty():
			allowed = outward
	return allowed[randi() % allowed.size()]


func _process_flee(delta: float) -> void:
	_flee_time += delta
	if _into_water:
		var step := _flee_dir * FLEE_SPEED * delta
		_run_distance += step.length()
		if move_and_collide(step) != null:
			_start_water_jump()
		elif _run_distance >= WATER_MAX_RUN:
			# Nothing out there to jump into, and long off screen by now.
			despawn()
		return
	global_position += _flee_dir * FLEE_SPEED * delta
	var fade_t := (_flee_time - FLEE_FADE_DELAY) / FLEE_FADE_TIME
	if fade_t > 0.0:
		modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)
	if fade_t >= 1.0:
		despawn()


# ---- jumping in ("Jumps into water") ----------------------------------------

## It has run into the bank. Stop dead, drop the collision (it is about to be over the
## water) and hold the pose for a beat before it commits.
func _start_water_jump() -> void:
	_state = State.WATER_PAUSE
	_water_time = 0.0
	velocity = Vector2.ZERO
	collision_mask = 0
	animating = false
	_apply_region()


func _process_water(delta: float) -> void:
	_water_time += delta
	match _state:
		State.WATER_PAUSE:
			if _water_time >= WATER_PAUSE_TIME:
				_state = State.WATER_JUMP
				_water_time = 0.0
				_show_shadow()
		State.WATER_JUMP:
			var jump_t := clampf(_water_time / WATER_JUMP_TIME, 0.0, 1.0)
			# The hop: up fast, over the top, back down, ending exactly where it left --
			# coming back to that height is landing in the water.
			sprite.position.y = -WATER_HOP_HEIGHT * size_scale * sin(PI * jump_t)
			# ...and it keeps going the way it was running while it is up there, fast off
			# the bank and slowing to nothing. The two together are the arc out over the
			# water; the stop and the landing are the same moment.
			global_position += _flee_dir * WATER_LEAP_SPEED * (1.0 - jump_t) * delta
			if jump_t >= 1.0:
				_enter_water()
		State.WATER_SINK:
			var sink_t := clampf(_water_time / WATER_SINK_TIME, 0.0, 1.0)
			# Snapped to whole sprite rows, so the blue creeps up it a row at a time
			# instead of the whole thing sliding a fraction of a pixel.
			global_position.y = _sink_from + snappedf(_sink_distance * sink_t, draw_scale())
			_update_waterline()
			if sink_t >= 1.0:
				despawn()


## Touchdown: the splash, and the water shader taking over so it can be watched sinking.
## The surface stays where its feet hit it and the sprite falls past it, far enough that
## even the top of its head ends up deep enough to have faded out.
func _enter_water() -> void:
	_state = State.WATER_SINK
	_water_time = 0.0
	sprite.position.y = 0.0
	_hide_shadow()
	_water_y = global_position.y + _feet_offset()
	_sink_from = global_position.y
	_sink_distance = (art_height() + WATER_CLEAR_ROWS + WATER_FADE_ROWS) * draw_scale()
	_water_material = ShaderMaterial.new()
	_water_material.shader = PokemonSurfacer.water_shader()
	_water_material.set_shader_parameter("water_colour", PokemonSurfacer.WATER_COLOUR)
	_water_material.set_shader_parameter("deep_colour", PokemonSurfacer.DEEP_COLOUR)
	_water_material.set_shader_parameter("tint_rows", WATER_TINT_ROWS)
	_water_material.set_shader_parameter("above_tint", WATER_ABOVE_TINT)
	_water_material.set_shader_parameter("fade_rows", WATER_FADE_ROWS)
	# The shader can also hide everything below a moving line (the surfacing template
	# fades in through it); nothing here needs that, so it is pushed past the whole sheet.
	_water_material.set_shader_parameter("reveal_row", cell.y * 4.0)
	_water_material.set_shader_parameter("reveal_soft", 1.0)
	sprite.material = _water_material
	_update_waterline()
	PixelBurst.fire(get_parent(), Vector2(global_position.x, _water_y),
			PokemonSurfacer.SPLASH_COLOURS, WATER_SPLASH_COUNT, WATER_SPLASH_SPEED,
			cell.x * draw_scale() * 0.5, Z + 1)


## Tell the shader which sprite row the surface is cutting through right now. The sprite
## is drawn centred on the node, so the top of its cell is half a cell above it; as the
## node falls, _water_y is further and further UP the art, and every row past it is under
## water. `bottom_row` is where a row has faded out completely -- WATER_CLEAR_ROWS of
## solid blue and then WATER_FADE_ROWS of fading, measured down from the surface.
func _update_waterline() -> void:
	if _water_material == null:
		return
	var rows_from_cell_top := (_water_y - global_position.y + cell.y * draw_scale() * 0.5) / draw_scale()
	var waterline: float = ROWS.get(facing, 0) * cell.y + rows_from_cell_top
	_water_material.set_shader_parameter("waterline_row", waterline)
	_water_material.set_shader_parameter("bottom_row", waterline + WATER_CLEAR_ROWS + WATER_FADE_ROWS)


## World pixels from the node's origin down to the bottom of the art while it is drawn
## centred (clip_rows < 0) -- its feet, and so where the shadow and the waterline go.
func _feet_offset() -> float:
	return (art_bottom + 1 - cell.y * 0.5) * draw_scale()


func _show_shadow() -> void:
	if _shadow != null:
		return
	_shadow = AirShadow.new()
	_shadow.radii = WATER_SHADOW_RADII * size_scale
	_shadow.alpha = WATER_SHADOW_ALPHA
	_shadow.position = Vector2(0.0, _feet_offset())
	add_child(_shadow)
	# Same z as the Pokemon, but an earlier sibling, so it draws underneath it.
	move_child(_shadow, 0)


func _hide_shadow() -> void:
	if _shadow == null:
		return
	# remove_child before queue_free, so nothing walks the children and finds the corpse.
	remove_child(_shadow)
	_shadow.queue_free()
	_shadow = null


## The little shadow under a Pokemon in mid-air: a flat translucent black ellipse on the
## ground it jumped from. Deliberately not a copy of the sprite -- it only has to say
## "this thing is off the ground".
class AirShadow extends Node2D:
	const POINTS := 16
	var radii: Vector2 = Vector2(9.0, 3.0)
	var alpha: float = 0.3

	func _draw() -> void:
		var ring := PackedVector2Array()
		for i in POINTS:
			var angle := TAU * i / float(POINTS)
			ring.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		draw_colored_polygon(ring, Color(0.0, 0.0, 0.0, alpha))


# ---- talking ----------------------------------------------------------------

func pause_and_face(target_global: Vector2) -> void:
	if _escaping():
		return
	_state = State.TALKING
	velocity = Vector2.ZERO
	animating = false
	face_vector(target_global - global_position)
	_apply_region()


func resume_movement() -> void:
	if _state == State.TALKING:
		_go_idle(randf_range(PAUSE_MIN, PAUSE_MAX))
