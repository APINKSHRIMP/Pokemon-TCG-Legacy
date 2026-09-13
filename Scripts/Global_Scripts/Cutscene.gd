class_name Cutscene
extends Node

# ============================================================
# CUTSCENE — shared engine
# ============================================================
# The reusable half of a cutscene: locking the player, spawning throwaway actors,
# walking the player about, and running dialogue one line at a time. A specific
# cutscene subclasses this and writes only its own content -- see
# Scripts/Cutscenes/Ellie_Intro_Cutscene.gd for the worked example.
#
# WRITING A NEW CUTSCENE
# ----------------------
#   1. class MyCutscene extends Cutscene, in Scripts/Cutscenes/.
#   2. Give it an async run() that reads top-to-bottom as the scene plays:
#
#        func run() -> void:
#            var rival := spawn("Ellie", "0Ellie", Vector2(120, 400))
#            await rival.walk_path([Vector2(-40, 400)], 180.0)
#            await player_face("left")
#            await say_all(speaker_for("Ellie"), ["Hey!!!", "Long time no see."])
#            finish()
#
#   3. Start it from the map script:
#
#        var cs := MyCutscene.new()
#        cs.install(self)
#        cs.run()
#
# Everything that takes time is awaitable, so the sequence is the code.
#
# INPUT is blocked from install() until finish(). A cutscene that hands control
# back in the middle (a race, a chase) calls release_player() and later
# reclaim_player(); the object stays alive in between, which is what lets it keep
# watching for the trigger that resumes it.
#
# CROSSING A SCENE BOUNDARY (a forced battle) ends the object -- the map is
# unloaded. Persist a stage key in GameState.progress before the battle and have
# the map script route back into the right part of the cutscene on reload. Again,
# the Ellie cutscene is the worked example.
# ============================================================

const ACTOR_SCENE := preload("res://Scenes/Objects/Cutscene_Actor_Scene.tscn")

# TWEAKABLE — the default speeds a scripted player walk uses when the caller
# doesn't name one. WALK is an ordinary stroll; SLOW is the deliberate,
# "we're being cinematic now" pace used for walking into position.
const PLAYER_WALK_SPEED: float = 80.0
const PLAYER_SLOW_WALK_SPEED: float = 45.0

# The player sprite's walk animation is authored for its own move_speed; a
# scripted walk at a different speed scales it to match, as CutsceneActor does.
const PLAYER_ANIM_REFERENCE_SPEED: float = 160.0

signal line_advanced

var map: Node2D = null
var player: CharacterBody2D = null

var _actors: Array = []


# ============================================================
# LIFECYCLE
# ============================================================

## Attach to a map scene and take control. Call before run().
func install(map_scene: Node2D) -> void:
	map = map_scene
	player = map_scene.get_node_or_null("Player") as CharacterBody2D
	if not is_inside_tree():
		map_scene.add_child(self)
	reclaim_player()


## Give the player back their legs but keep this object alive and watching.
func release_player() -> void:
	MapManager.cutscene_active = false
	if player != null and is_instance_valid(player):
		player.unlock_movement()


## Take control again mid-cutscene.
func reclaim_player() -> void:
	MapManager.cutscene_active = true
	if player != null and is_instance_valid(player):
		player.lock_movement()


## End the cutscene: control returns, spawned actors are removed, this frees itself.
## `keep_actors` leaves the spawned cast standing (rare -- only when something else
## has taken ownership of them).
func finish(keep_actors: bool = false) -> void:
	MapManager.cutscene_active = false
	MapManager.cutscene_speaker = {}
	if player != null and is_instance_valid(player):
		player.unlock_movement()
	if not keep_actors:
		for actor in _actors:
			if is_instance_valid(actor):
				actor.queue_free()
	_actors.clear()
	queue_free()


# ============================================================
# ACTORS
# ============================================================

## Spawn a cutscene-only character. `at` is a GLOBAL position.
func spawn(actor_name: String, sprite: String, at: Vector2,
		facing: String = "down") -> CutsceneActor:
	var actor := ACTOR_SCENE.instantiate() as CutsceneActor
	actor.name = actor_name.replace(" ", "_")
	actor.sprite = sprite
	# Into the same container the map's own actors live in, so this character sits
	# in the same draw layer as everyone else rather than under the scenery.
	var parent: Node = map.get_node_or_null("OPPONENTS")
	if parent == null:
		parent = map
	parent.add_child(actor)
	actor.global_position = at
	actor.face(facing)
	_actors.append(actor)
	return actor


## The speaker block a message box needs, read from All_NPC_Constant_Data.json so
## a cutscene never restates a character's colour or sprite. Pass `section`
## "npcs" for a character defined there instead.
func speaker_for(character_name: String, section: String = "opponents") -> Dictionary:
	var entry := CharacterSchedule.merge_constants({}, section, character_name)
	return {
		"name":   character_name,
		"sprite": str(entry.get("sprite", "")),
		"colour": str(entry.get("message_colour", "")),
	}


# ============================================================
# DIALOGUE
# ============================================================

## One line, spoken by `speaker`. Returns when the player has clicked past it.
## The box stays on screen between lines, so a run of say() calls reads as one
## conversation rather than a box flickering in and out.
func say(speaker: Dictionary, text: String) -> void:
	MapManager.show_cutscene_message(text, speaker, func(): line_advanced.emit())
	await line_advanced


## A whole run of lines from one speaker.
func say_all(speaker: Dictionary, lines: Array) -> void:
	for line in lines:
		await say(speaker, str(line))


## Take the box down. Call it at the end of a conversation, or before any beat
## that should play with a clear screen.
func close_box() -> void:
	MapManager.end_cutscene_message()


# ============================================================
# THE PLAYER
# ============================================================

func player_face(direction: String) -> void:
	if player != null and is_instance_valid(player):
		player.set_direction(direction)


## Turn the player toward a GLOBAL position.
func player_face_position(target: Vector2) -> void:
	if player != null and is_instance_valid(player):
		player.face_toward(target)


## Walk the player to a GLOBAL position. A tween, not physics: the destination is
## authored, and a scripted walk that can be blocked by a stray NPC is a bug that
## only shows up on one save. Awaitable.
func player_walk_to(target: Vector2, speed: float = PLAYER_WALK_SPEED,
		facing: String = "") -> void:
	if player == null or not is_instance_valid(player):
		return
	var offset: Vector2 = target - player.global_position
	var distance: float = offset.length()
	if distance < 0.01:
		return

	var direction: String = facing
	if direction == "":
		if abs(offset.x) > abs(offset.y):
			direction = "right" if offset.x > 0.0 else "left"
		else:
			direction = "down" if offset.y > 0.0 else "up"

	# Same no-sliding rule the cutscene actors use: a forced walk of a few pixels
	# still plays a step or two rather than gliding the sprite into place.
	var timing := CutsceneActor.step_timing(player.animated_sprite, "walk_" + direction,
		distance, speed, PLAYER_ANIM_REFERENCE_SPEED)

	player.current_direction = direction
	player.animated_sprite.speed_scale = timing["scale"]
	player.animated_sprite.play("walk_" + direction)

	var tween := create_tween()
	tween.tween_property(player, "global_position", target, timing["duration"])

	# Re-assert the animation every frame rather than trusting one play() call to
	# stick. The player's own _physics_process reaches in and resets the sprite
	# under some conditions, and a scripted walk that silently loses its animation
	# looks exactly like the sliding this whole helper exists to prevent. play() on
	# the animation that is already running is a no-op, so this costs nothing.
	#
	# The completion flag is set from the signal and polled, rather than looping on
	# the tween and THEN awaiting `finished`: that ordering deadlocks, because the
	# loop only exits once the tween has already emitted, so the await that follows
	# waits for a signal that has been and gone. is_valid() is the second way out,
	# for a tween killed by a scene change before it ever finishes.
	var walk_done := false
	tween.finished.connect(func(): walk_done = true)
	while not walk_done and tween.is_valid():
		player.animated_sprite.speed_scale = timing["scale"]
		player.animated_sprite.play("walk_" + direction)
		await get_tree().process_frame

	player.animated_sprite.speed_scale = 1.0
	player.animated_sprite.play("idle_" + player.current_direction)


## Walk a series of GLOBAL points.
func player_walk_path(points: Array, speed: float = PLAYER_WALK_SPEED) -> void:
	for point in points:
		await player_walk_to(point, speed)


# ============================================================
# TIMING
# ============================================================

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ============================================================
# TRIGGER ZONES
# ============================================================
# A cutscene trigger is a RECTANGLE, tested against a point, not an Area2D
# subscription. Two reasons: the thing being tested is often an actor this script
# already owns (no signal plumbing, no collision-layer juggling), and the test has
# to answer "is X in the zone RIGHT NOW" -- an entered/exited pair cannot answer
# that for something that was already standing inside when the zone was armed.
#
# The rect is read from a node in the map scene when one exists, so the zone can be
# dragged around in the editor; `fallback` is used when it doesn't. Name an Area2D
# (with a RectangleShape2D child), a CollisionShape2D, or any Node2D -- a bare
# Node2D is treated as the centre of a `fallback`-sized box.

func zone_rect(node_name: String, fallback: Rect2) -> Rect2:
	if map == null:
		return fallback
	var node := map.find_child(node_name, true, false)
	if node == null:
		return fallback

	var shape_node: CollisionShape2D = node as CollisionShape2D
	if node is Area2D:
		for child in node.get_children():
			if child is CollisionShape2D:
				shape_node = child
				break

	if shape_node != null and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		return Rect2(shape_node.global_position - size * 0.5, size)

	if node is Node2D:
		return Rect2((node as Node2D).global_position - fallback.size * 0.5, fallback.size)

	return fallback


## Points of a Line2D in the map scene, in GLOBAL space, or `fallback` when the
## map has no such node. Lets a path be drawn in the editor instead of typed out.
func path_from_line(node_name: String, fallback: Array) -> Array:
	if map == null:
		return fallback
	var node := map.find_child(node_name, true, false)
	if not (node is Line2D):
		return fallback
	var line := node as Line2D
	if line.points.size() < 2:
		return fallback
	var points: Array = []
	for point in line.points:
		points.append(line.to_global(point))
	return points
