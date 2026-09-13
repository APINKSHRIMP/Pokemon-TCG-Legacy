class_name CutsceneActor
extends WorldObjectBase

# ============================================================
# CUTSCENE ACTOR
# ============================================================
# A character that exists only for the duration of a cutscene. It is deliberately
# NOT in the "npcs" or "opponents" groups, so the player can never walk up to it
# and open a message box -- everything it says is said by the cutscene script.
#
# It reuses WorldObjectBase for sprite loading, facing and the standard collision
# body, and adds the one thing a cutscene needs that an NPC never does: walking a
# scripted path.
#
# TWO WAYS TO MOVE, and they are not interchangeable:
#
#   walk_path()   physics movement. Honours walls, and (with shove_player on) the
#                 player. Use it for anything the player can interfere with --
#                 the race down the pier is the whole reason this exists.
#   glide_path()  a plain position tween, no collision at all. Use it for close
#                 staging: stopping a few pixels from the player, the hug, the
#                 step back. Those distances are SMALLER than the two collision
#                 boxes, so physics movement would jam against the player instead
#                 of finishing the move.
#
# Both are awaitable:  await actor.walk_path([...], 180.0)
# ============================================================

signal path_finished

# The walk animation is authored for roughly this speed. Anything faster or slower
# scales the animation to match, so a sprinting character's legs keep up.
const ANIM_REFERENCE_SPEED: float = 80.0
const ANIM_SCALE_RANGE := Vector2(0.5, 3.0)

# ------------------------------------------------------------
# NO SLIDING — the short-move rule
# ------------------------------------------------------------
# A scripted move of a few pixels finishes in a fraction of a frame cycle, so the
# sprite holds one pose and the character appears to slide rather than walk. Every
# staged move (glide_to here, player_walk_to in Cutscene.gd) is therefore given
# BOTH a floor on how long it may take and a boost to the animation rate, so at
# least WALK_MIN_FRAMES poses are actually seen. Walk sheets are 4 frames at 6fps
# (Sprite_Sheet_Loader_Script.gd), so 3 frames reads clearly as a step or two.
#
# Use step_timing() for any new scripted movement rather than dividing distance by
# speed yourself -- that is the whole point of it being static and shared.
const WALK_MIN_FRAMES  : float = 3.0
const WALK_MIN_DURATION: float = 0.35
# The boost is capped well below ANIM_SCALE_RANGE's ceiling: a very short move
# spun up to 3x reads as a twitch, which is the opposite of the problem being fixed.
const WALK_BOOST_CAP   : float = 2.5


## Duration and animation rate for one staged move.
## Returns { "duration": float, "scale": float }.
static func step_timing(sprite: AnimatedSprite2D, anim: String, distance: float,
		speed: float, reference_speed: float = ANIM_REFERENCE_SPEED) -> Dictionary:
	var duration: float = maxf(distance / maxf(speed, 0.01), WALK_MIN_DURATION)
	var natural: float = speed / maxf(reference_speed, 0.01)

	var fps: float = 6.0
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		fps = maxf(sprite.sprite_frames.get_animation_speed(anim), 0.01)
	# What the rate would have to be for WALK_MIN_FRAMES poses to fit in `duration`.
	var needed: float = WALK_MIN_FRAMES / (duration * fps)

	return {
		"duration": duration,
		"scale": clampf(maxf(natural, needed), ANIM_SCALE_RANGE.x, WALK_BOOST_CAP),
	}

# How hard the actor pushes a player standing in its way, in px/sec. High enough
# to slide someone clear in a fraction of a second, low enough to read as a shove
# rather than a teleport.
const SHOVE_SPEED: float = 170.0

# Below this, the player is considered to be dead in front of the actor rather
# than off to one side, so a side is picked and committed to.
const SHOVE_LATERAL_DEADZONE: float = 1.5

# ANTI-SOFT-LOCK. A cutscene waits on path_finished, and half the time it is the
# ONLY thing that moves the story on -- so an actor wedged on a bit of scenery
# that the route clips by a couple of pixels does not look like a bug, it looks
# like the game has hung. After this long making no real progress the actor stops
# asking the physics engine's permission and walks through whatever it is stuck
# on. It is a last resort, not a movement mode: if you ever SEE it happen, the
# path has a bad corner in it and that is what wants fixing.
const STUCK_GRACE: float = 1.2
# What counts as "making progress", as a fraction of the speed it asked for.
const STUCK_SPEED_FRACTION: float = 0.15
# How long shoving a player counts as progress before it is treated as a jam.
# Comfortably longer than barging past someone, far shorter than a stand-off.
const SHOVE_GRACE: float = 1.0

## When true, a player caught in this actor's way is pushed aside instead of
## blocking it. Off by default: a staged walk should never jostle the player.
var shove_player: bool = false

var _path: Array = []
var _path_index: int = 0
var _path_speed: float = 0.0
var _walking: bool = false
# Which way the current shove is going. Kept between frames so a dead-on collision
# doesn't jitter the player left and right on alternate frames.
var _shove_side: float = 0.0
# How long we have been going nowhere. See STUCK_GRACE.
var _stuck_time: float = 0.0
# How long we have been pushing at a player who is not getting out of the way.
var _shove_time: float = 0.0


func _ready() -> void:
	# "cutscene" matches no branch in WorldObjectBase's pattern handling, which is
	# exactly what is wanted: no patrol, no wander, no direction timer. The cutscene
	# script is the only thing that ever moves this actor.
	movement_pattern = "cutscene"
	super._ready()
	hide_bubble()


# ============================================================
# PATH WALKING
# ============================================================

## Walk the given GLOBAL points in order, using physics. Awaitable.
func walk_path(points: Array, speed: float) -> void:
	if points.is_empty():
		return
	_path = points.duplicate()
	_path_index = 0
	_path_speed = speed
	_walking = true
	_stuck_time = 0.0
	set_physics_process(true)
	await path_finished


## Change speed mid-walk without interrupting the path -- the "slow right down as
## she reaches the end of the pier" beat.
func set_walk_speed(speed: float) -> void:
	_path_speed = speed


## Stop where we stand. Emits path_finished so anything awaiting the walk resumes.
func stop_walking() -> void:
	if not _walking:
		return
	_walking = false
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = 1.0
	animated_sprite.play("idle_" + current_facing)
	path_finished.emit()


func is_walking() -> bool:
	return _walking


## The corners of the current path not yet reached. Lets a caller take over the
## rest of a walk -- typically to finish it as a glide once it no longer matters
## whether the route is walkable.
func remaining_path() -> Array:
	if not _walking:
		return []
	return _path.slice(_path_index)


func _physics_process(delta: float) -> void:
	if movement_pattern != "cutscene":
		super._physics_process(delta)
		return
	if not _walking:
		velocity = Vector2.ZERO
		return

	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position

	# Arrive. The tolerance is one frame of travel, so a fast actor cannot
	# overshoot a corner and spend the next frame walking back to it.
	if to_target.length() <= maxf(2.0, _path_speed * delta):
		global_position = target
		_path_index += 1
		if _path_index >= _path.size():
			_walking = false
			velocity = Vector2.ZERO
			animated_sprite.speed_scale = 1.0
			animated_sprite.play("idle_" + current_facing)
			path_finished.emit()
			return
		to_target = _path[_path_index] - global_position

	var heading: Vector2 = to_target.normalized()
	velocity = heading * _path_speed
	face_along(heading)
	animated_sprite.speed_scale = clampf(
		_path_speed / ANIM_REFERENCE_SPEED, ANIM_SCALE_RANGE.x, ANIM_SCALE_RANGE.y)
	animated_sprite.play("walk_" + current_facing)

	move_and_slide()

	var shoving: bool = false
	if shove_player:
		shoving = _shove_blocking_player(heading)
	_shove_time = _shove_time + delta if shoving else 0.0

	# Being briefly stopped by the player mid-shove is progress, not a jam -- but
	# only briefly. A player barged aside in the open is clear in a fraction of a
	# second; a player wedged against a railing never moves at all, and treating
	# that as progress meant she pushed at them for ever and the cutscene never
	# resumed. Past SHOVE_GRACE the shove stops counting and the stuck timer runs.
	if get_real_velocity().length() > _path_speed * STUCK_SPEED_FRACTION \
			or (shoving and _shove_time < SHOVE_GRACE):
		_stuck_time = 0.0
	else:
		_stuck_time += delta
		if _stuck_time > STUCK_GRACE:
			global_position += heading * _path_speed * delta


# ============================================================
# GLIDING — tween movement, no collision
# ============================================================

## Tween through the given GLOBAL points. `facing` pins the direction the sprite
## looks the whole way ("" derives it from the heading, as walking does) -- that
## is how Ellie backs away from the hug still facing the player.
## `animate` false holds the idle frame, for a movement too small to read as a step.
func glide_path(points: Array, speed: float, facing: String = "", animate: bool = true) -> void:
	for point in points:
		await glide_to(point, speed, facing, animate)


func glide_to(target: Vector2, speed: float, facing: String = "", animate: bool = true) -> void:
	var offset: Vector2 = target - global_position
	var distance: float = offset.length()
	if distance < 0.01:
		return

	if facing != "":
		current_facing = facing
	else:
		face_along(offset.normalized())

	# Duration and rate together, so even a ten-pixel lean plays visible steps.
	var timing := step_timing(animated_sprite, "walk_" + current_facing, distance, speed)

	if animate:
		animated_sprite.speed_scale = timing["scale"]
		animated_sprite.play("walk_" + current_facing)
	else:
		animated_sprite.play("idle_" + current_facing)

	var tween := create_tween()
	tween.tween_property(self, "global_position", target, timing["duration"])
	await tween.finished

	animated_sprite.speed_scale = 1.0
	animated_sprite.play("idle_" + current_facing)


# ============================================================
# FACING
# ============================================================

## Face along a direction vector, dominant axis wins.
func face_along(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		current_facing = "right" if direction.x > 0.0 else "left"
	else:
		current_facing = "down" if direction.y > 0.0 else "up"


## Face a GLOBAL position and stand still.
func face_position(target: Vector2) -> void:
	face_along(target - global_position)
	animated_sprite.speed_scale = 1.0
	animated_sprite.play("idle_" + current_facing)


func face(direction: String) -> void:
	current_facing = direction
	animated_sprite.speed_scale = 1.0
	animated_sprite.play("idle_" + direction)


# ============================================================
# THE SHOVE
# ============================================================
# The ordinary NPC rule is the opposite of this one: an NPC stops dead rather than
# walk into the player (_is_player_blocking in WorldObjectBase). During a race that
# rule hands the win to anyone who simply stands in the way, so a cutscene actor
# keeps running and pushes instead.
#
# The push is SIDEWAYS, along whichever side of the actor's heading the player is
# already on, so it reads as being barged past rather than dragged along. Straight
# down the heading would shunt the player toward the finish line, which is both
# wrong-looking and a free ride.

## Returns true when a player was actually in the way and got pushed.
func _shove_blocking_player(heading: Vector2) -> bool:
	var shoved: bool = false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other = collision.get_collider()
		if other == null or not (other is Node2D) or not other.is_in_group("player"):
			continue
		shoved = true

		var offset: Vector2 = other.global_position - global_position
		# The component of the offset at right angles to where we are heading.
		var lateral: Vector2 = offset - heading * offset.dot(heading)

		if lateral.length() < SHOVE_LATERAL_DEADZONE:
			# Dead-on. Pick a side once and stay with it until they are clear,
			# or the player judders between left and right every frame.
			if _shove_side == 0.0:
				_shove_side = 1.0 if randf() < 0.5 else -1.0
			lateral = Vector2(-heading.y, heading.x) * _shove_side
		else:
			_shove_side = 0.0

		# move_and_collide, not a position write: the player must still be stopped
		# by walls and railings while being shoved along them.
		other.move_and_collide(lateral.normalized() * SHOVE_SPEED * get_physics_process_delta_time())
	return shoved
