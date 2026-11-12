extends RefCounted

## Walks a drawn route: the points, the pauses at them and the idle patterns during
## those pauses. Shared by NPCs / opponents (WorldObjectBase) and the walker Pokémon
## template, so both walk a route exactly the same way and the placement tool edits
## both with the same keys. Preloaded, not a class_name (see the class-cache trap).
##
## The host owns the body and the sprite. Each physics frame it calls tick() and gets a
## velocity back (ZERO = standing); `facing` and `walk_anim` say what to show. After
## move_and_slide() it calls check_stuck() with how fast it really moved.
##
## Route data, as in the character / spawn files:
##   steps: [{"to": [dx, dy]}            walk to this point (offset from the anchor)
##           {"to": [dx, dy], "speed": n} ...at its own speed for that leg
##           {"wait": s}                  pause, keep facing the way it walked in
##           {"wait": s, "idle": "idle_left"}  pause doing an idle pattern]
##   mode:  "loop" (back to the start after the last point), "pingpong", or "random"
##          (after each point's pauses, walk straight to any other point, start included)

## TWEAKABLE: seconds a leg may make no progress before the point is skipped.
const STUCK_TIME := 1.5
## TWEAKABLE: how often a look-around pause looks somewhere new, in seconds (min, max).
const LOOK_AROUND_TIME := Vector2(0.8, 2.0)
## TWEAKABLE: an idle_<dir>_random pause waits this long between glances, and glances for this long.
const GLANCE_GAP := Vector2(1.0, 3.0)
const GLANCE_LENGTH := Vector2(0.5, 1.2)
## A point counts as reached this close (px).
const ARRIVE_DISTANCE := 2.0

const DIRECTIONS := ["up", "down", "left", "right"]
const IDLES := [
	"", "idle_down", "idle_up", "idle_left", "idle_right",
	"idle_down_random", "idle_up_random", "idle_left_random", "idle_right_random",
	"idle_random", "idle_cycle",
]

var steps: Array = []
var mode: String = "loop"
## The route's start point (point 0), in the host's parent space.
var anchor: Vector2 = Vector2.ZERO
## [{pos (offset from anchor), speed (leg INTO this node, 0 = the host's speed),
##   pauses: [{wait, idle, step}], step (index in steps, -1 for the start)}]
var nodes: Array = []

var facing: String = "down"
## true = show the walk cycle (walking, or an idle_cycle pause); false = stand.
var walk_anim: bool = false
## Set by tick() when the host should put itself exactly on a point this frame.
var snap_to = null

var i: int = 0            # the node walked to / paused at
var dir: int = 1          # pingpong direction
var walking: bool = false
var from: int = 0         # the node the current leg started at
var pause_i: int = 0
var pause_t: float = 0.0
var _idle_t: float = 0.0
var _glancing: bool = false
var _stuck_t: float = 0.0


static func build_nodes(route_steps: Array) -> Array:
	var out: Array = [{"pos": Vector2.ZERO, "speed": 0.0, "pauses": [], "step": -1}]
	for n in route_steps.size():
		var s = route_steps[n]
		if not (s is Dictionary):
			continue
		var to = s.get("to")
		if to is Array and to.size() >= 2:
			out.append({"pos": Vector2(float(to[0]), float(to[1])),
					"speed": float(s.get("speed", 0.0)), "pauses": [], "step": n})
		elif s.has("wait"):
			(out[-1]["pauses"] as Array).append({"wait": maxf(float(s["wait"]), 0.0),
					"idle": str(s.get("idle", "")), "step": n})
	return out


func setup(route_steps: Array, route_mode: String, start: Vector2) -> void:
	steps = route_steps.duplicate(true)
	mode = route_mode
	anchor = start
	nodes = build_nodes(steps)
	restart()


func restart() -> void:
	i = 0
	dir = 1
	from = 0
	walking = false
	pause_i = 0
	pause_t = 0.0
	_stuck_t = 0.0
	_start_pause()


## Replace the steps and carry on. The node it was heading for is kept where it still
## exists, so an edit doesn't snap the walker back to the start.
func set_steps(route_steps: Array, route_mode: String) -> void:
	steps = route_steps.duplicate(true)
	mode = route_mode
	nodes = build_nodes(steps)
	if i >= nodes.size():
		i = nodes.size() - 1
	from = clampi(from, 0, nodes.size() - 1)
	if not walking:
		pause_i = 0
		_start_pause()


func node_position(n: int) -> Vector2:
	if n < 0 or n >= nodes.size():
		return anchor
	return anchor + (nodes[n]["pos"] as Vector2)


## One physics step. `blocked` = something (the player) is in the way: stand and wait.
## `speed` is the host's route speed; a leg may override it.
func tick(delta: float, pos: Vector2, blocked: bool, speed: float) -> Vector2:
	snap_to = null
	if nodes.is_empty():
		nodes = build_nodes(steps)
	if not walking:
		_tick_pause(delta)
		return Vector2.ZERO
	if blocked:
		_stuck_t = 0.0
		walk_anim = false
		return Vector2.ZERO
	var target := node_position(i)
	var to_target := target - pos
	if to_target.length() < ARRIVE_DISTANCE:
		snap_to = target
		_arrive()
		return Vector2.ZERO
	var d := to_target.normalized()
	_face(d)
	walk_anim = true
	# Never overshoot the point in one physics step.
	return d * minf(_leg_speed(speed), to_target.length() / maxf(delta, 0.0001))


## After the host has moved. Returns true when the leg was given up as blocked (so the
## host can warn once); the walker carries on to the next point.
func check_stuck(delta: float, real_speed: float, speed: float) -> bool:
	if not walking:
		_stuck_t = 0.0
		return false
	if real_speed < _leg_speed(speed) * 0.2:
		_stuck_t += delta
		if _stuck_t >= STUCK_TIME:
			_stuck_t = 0.0
			_arrive()
			return true
	else:
		_stuck_t = 0.0
	return false


## The idle direction the current pause pins, "" when walking or free.
func pause_facing() -> String:
	if walking or i >= nodes.size():
		return ""
	var pauses: Array = nodes[i]["pauses"]
	if pause_i >= pauses.size():
		return ""
	return idle_dir(str(pauses[pause_i].get("idle", "")))


func capture() -> Dictionary:
	return {"route_anchor": anchor, "route_i": i, "route_dir": dir, "route_walking": walking,
			"route_from": from, "route_pause_i": pause_i, "route_pause_t": pause_t}


func apply(state: Dictionary) -> void:
	if state.has("route_anchor"):
		anchor = state["route_anchor"]
	i = clampi(int(state.get("route_i", 0)), 0, maxi(nodes.size() - 1, 0))
	dir = int(state.get("route_dir", 1))
	walking = bool(state.get("route_walking", false))
	from = clampi(int(state.get("route_from", 0)), 0, maxi(nodes.size() - 1, 0))
	pause_i = int(state.get("route_pause_i", 0))
	pause_t = float(state.get("route_pause_t", 0.0))


static func idle_dir(idle: String) -> String:
	for d in DIRECTIONS:
		if idle.begins_with("idle_" + d):
			return d
	return ""


# ── internals ─────────────────────────────────────────────────────────────────

func _next_node() -> int:
	var n := nodes.size()
	if n <= 1:
		return 0
	if mode == "pingpong":
		var nxt := i + dir
		if nxt < 0 or nxt >= n:
			dir = -dir
			nxt = i + dir
		return nxt
	if mode == "random":
		# Any point but the one it is standing on.
		var pick := randi() % (n - 1)
		return pick if pick < i else pick + 1
	return (i + 1) % n


## A leg's speed is stored on the point the leg was DRAWN towards: walking forwards (or a
## loop's walk back to the start) that is the target; walking a pingpong route backwards
## it is the point being left. A random route uses the target's speed. 0 = the route's own speed.
func _leg_speed(speed: float) -> float:
	var forward := mode == "random" or i == from + 1 or (i == 0 and mode != "pingpong")
	var leg := i if forward else from
	var own := 0.0
	if leg >= 0 and leg < nodes.size():
		own = float(nodes[leg]["speed"])
	return own if own > 0.0 else speed


func _face(v: Vector2) -> void:
	if absf(v.x) > absf(v.y):
		facing = "right" if v.x > 0 else "left"
	else:
		facing = "down" if v.y > 0 else "up"


func _arrive() -> void:
	walking = false
	_stuck_t = 0.0
	pause_i = 0
	pause_t = 0.0
	_start_pause()


## Begin pause pause_i at the current node, or walk on if it has no more.
func _start_pause() -> void:
	var pauses: Array = nodes[i]["pauses"] if i < nodes.size() else []
	if pause_i >= pauses.size():
		_begin_leg()
		return
	pause_t = 0.0
	_glancing = false
	var idle := str(pauses[pause_i].get("idle", ""))
	var face := idle_dir(idle)
	if face != "":
		facing = face
	_idle_t = randf_range(GLANCE_GAP.x, GLANCE_GAP.y)
	walk_anim = idle == "idle_cycle"


func _begin_leg() -> void:
	if nodes.size() <= 1:
		# Only a start point (a route still being drawn): repeat its pauses, or just
		# stand there until a point is added.
		walking = false
		pause_i = 0
		walk_anim = false
		if not nodes.is_empty() and not (nodes[0]["pauses"] as Array).is_empty():
			_start_pause()
		return
	from = i
	i = _next_node()
	walking = true
	_stuck_t = 0.0


func _tick_pause(delta: float) -> void:
	var pauses: Array = nodes[i]["pauses"] if i < nodes.size() else []
	if pause_i >= pauses.size():
		_begin_leg()
		return
	var pause: Dictionary = pauses[pause_i]
	var idle := str(pause.get("idle", ""))
	pause_t += delta
	_idle_t -= delta
	match idle:
		"idle_random":
			if _idle_t <= 0.0:
				facing = DIRECTIONS[randi() % DIRECTIONS.size()]
				_idle_t = randf_range(LOOK_AROUND_TIME.x, LOOK_AROUND_TIME.y)
		"idle_down_random", "idle_up_random", "idle_left_random", "idle_right_random":
			if _idle_t <= 0.0:
				var home := idle_dir(idle)
				if _glancing:
					facing = home
					_idle_t = randf_range(GLANCE_GAP.x, GLANCE_GAP.y)
				else:
					var side: Array = ["left", "right"] if home == "up" or home == "down" else ["up", "down"]
					facing = side[randi() % 2]
					_idle_t = randf_range(GLANCE_LENGTH.x, GLANCE_LENGTH.y)
				_glancing = not _glancing
	if pause_t >= float(pause.get("wait", 0.0)):
		pause_i += 1
		_start_pause()
