extends Node2D

## Debug-only drawing for the F placement tool: every character's route (a line through
## its numbered points, pauses written under them, arrows for the walking direction) and
## every wanderer's radius (a translucent circle). The selected character is drawn
## bright, everyone else faint. Owned by PlacementTool, which frees it on close.
##
## top_level, so it draws in global coordinates whatever the NPC container's offset is.

## TWEAKABLE: look of the guides (world px; the camera zooms them 2.5x on screen).
const LINE_WIDTH := 1.5
const POINT_RADIUS := 3.0
const SELECTED_POINT_RADIUS := 5.0
const FONT_SIZE := 8
const FAINT_ALPHA := 0.35
const ROUTE_COLOUR := Color(0.25, 0.9, 1.0)
const RETURN_COLOUR := Color(0.25, 0.9, 1.0, 0.55)
const SELECTED_STEP_COLOUR := Color(1.0, 0.85, 0.2)
const TARGET_COLOUR := Color(1.0, 0.3, 0.8)
const WANDER_COLOUR := Color(0.55, 1.0, 0.45)
const PENDING_COLOUR := Color(1.0, 1.0, 1.0, 0.7)
## TWEAKABLE: ghosts (H) -- other days' / times' spots.
const GHOST_ALPHA := 0.32
const GHOST_TINT := Color(0.6, 0.8, 1.0)
const GHOST_FONT_SIZE := 6
const GHOST_SPRITE_SCALE := 0.5

var tool: Node = null
## sprite name -> idle-down frame texture (or null), for ghosts.
var _ghost_frames: Dictionary = {}


func _init() -> void:
	# Before entering the tree: the time-of-day grade would tint the guides at night.
	add_to_group("no_time_grade")
	top_level = true
	z_as_relative = false
	z_index = 4000


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if tool == null or not is_instance_valid(tool):
		return
	var container: Node2D = tool._container
	if container == null or not is_instance_valid(container):
		return
	if tool._ghosts_on:
		_draw_ghosts(container)
	var selected: Node = tool._selected()
	for actor in tool._actors:
		if not is_instance_valid(actor):
			continue
		var walker: bool = actor is PokemonSpawnMarker and actor.is_walker()
		if not (actor is WorldObjectBase) and not walker:
			continue
		var alpha := 1.0 if actor == selected else FAINT_ALPHA
		var space := actor.get_parent() as Node2D
		match actor.movement_pattern:
			"route":
				_draw_route(actor, space, alpha, actor == tool._route_actor)
			"random_wander":
				_draw_wander(actor, container, alpha)


func _draw_wander(actor: WorldObjectBase, container: Node2D, alpha: float) -> void:
	var centre := container.to_global(actor.wander_origin())
	var r := actor.wander_radius
	if actor.wander_box != Vector2.ZERO:
		var rect := Rect2(centre - actor.wander_box, actor.wander_box * 2.0)
		draw_rect(rect, Color(WANDER_COLOUR, 0.12 * alpha), true)
		draw_rect(rect, Color(WANDER_COLOUR, alpha), false, LINE_WIDTH)
		draw_line(centre + Vector2(-4, 0), centre + Vector2(4, 0), Color(WANDER_COLOUR, alpha), 1.0)
		draw_line(centre + Vector2(0, -4), centre + Vector2(0, 4), Color(WANDER_COLOUR, alpha), 1.0)
		if alpha >= 1.0:
			_text(rect.end + Vector2(2, 0), "%d x %d  @%d" % [roundi(rect.size.x), roundi(rect.size.y),
					roundi(actor.patrol_speed)], Color(WANDER_COLOUR, alpha))
		return
	draw_circle(centre, r, Color(WANDER_COLOUR, 0.12 * alpha))
	draw_arc(centre, r, 0.0, TAU, 64, Color(WANDER_COLOUR, alpha), LINE_WIDTH)
	draw_line(centre + Vector2(-4, 0), centre + Vector2(4, 0), Color(WANDER_COLOUR, alpha), 1.0)
	draw_line(centre + Vector2(0, -4), centre + Vector2(0, 4), Color(WANDER_COLOUR, alpha), 1.0)
	if alpha >= 1.0:
		_text(centre + Vector2(r * 0.71 + 2, -r * 0.71), "r %d  @%d" % [roundi(r), roundi(actor.patrol_speed)],
				Color(WANDER_COLOUR, alpha))


func _draw_route(actor: Node2D, container: Node2D, alpha: float, editing: bool) -> void:
	var nodes: Array = actor._route_nodes
	if nodes.is_empty():
		return
	var pts: Array = []
	for i in nodes.size():
		pts.append(container.to_global(actor.route_node_position(i)))
	var colour := Color(ROUTE_COLOUR, alpha)
	# Legs, with an arrow in the middle of each pointing the way it is walked. A random
	# route walks between ANY two points, so its drawn path is dashed with no arrows and
	# each point's speed (used by every leg into it) is shown at the point.
	var random: bool = actor.route_mode == "random"
	for i in range(1, pts.size()):
		if random:
			_leg(pts[i - 1], pts[i], colour, 0.0, false, true, false)
		else:
			_leg(pts[i - 1], pts[i], colour, nodes[i]["speed"], actor.route_mode == "pingpong")
	if pts.size() > 1 and not random and actor.route_mode != "pingpong":
		_leg(pts[-1], pts[0], Color(RETURN_COLOUR, RETURN_COLOUR.a * alpha), 0.0, false, true)

	var sel_node := -1
	if editing:
		sel_node = _node_for_step(nodes, int(tool._route_sel))
	for i in pts.size():
		var p: Vector2 = pts[i]
		var is_sel := i == sel_node
		draw_circle(p, SELECTED_POINT_RADIUS if is_sel else POINT_RADIUS,
				Color(SELECTED_STEP_COLOUR, alpha) if is_sel else colour)
		var label := "S" if i == 0 else str(i)
		if random and float(nodes[i]["speed"]) > 0.0:
			label += " @%d" % roundi(float(nodes[i]["speed"]))
		_text(p + Vector2(4, -4), label, Color(1, 1, 1, alpha))
		var y := 10.0
		for pause in nodes[i]["pauses"]:
			var idle := str(pause.get("idle", ""))
			var line := "%ss%s" % [_secs(float(pause.get("wait", 0.0))), "" if idle == "" else " " + idle.trim_prefix("idle_")]
			var step_sel := editing and int(pause.get("step", -2)) == int(tool._route_sel)
			_text(p + Vector2(4, y), line, Color(SELECTED_STEP_COLOUR, alpha) if step_sel else Color(1, 1, 1, 0.85 * alpha))
			y += FONT_SIZE + 1
	# Where it is heading right now.
	var target := clampi(actor.route_current_node(), 0, pts.size() - 1)
	draw_arc(pts[target], SELECTED_POINT_RADIUS + 2, 0.0, TAU, 16, Color(TARGET_COLOUR, alpha), 1.0)

	# Route editing: a dotted line from the selected point to the player, which is where
	# Q would put the next point.
	if editing and tool._player != null and is_instance_valid(tool._player):
		var from: Vector2 = pts[maxi(sel_node, 0)]
		var to: Vector2 = tool._player.global_position
		draw_dashed_line(from, to, PENDING_COLOUR, 1.0, 3.0)
		_text(to + Vector2(5, 10), "Q", PENDING_COLOUR)


func _leg(a: Vector2, b: Vector2, colour: Color, speed: float, both_ways: bool, dashed: bool = false,
		arrows: bool = true) -> void:
	if dashed:
		draw_dashed_line(a, b, colour, LINE_WIDTH, 4.0)
	else:
		draw_line(a, b, colour, LINE_WIDTH)
	var d := b - a
	if not arrows or d.length() < 12.0:
		return
	var mid := a + d * 0.5
	var dir := d.normalized()
	_arrow(mid, dir, colour)
	if both_ways:
		_arrow(mid - dir * 7.0, -dir, colour)
	if speed > 0.0:
		_text(mid + dir.orthogonal() * 6.0, "@%d" % roundi(speed), colour)


func _arrow(at: Vector2, dir: Vector2, colour: Color) -> void:
	var side := dir.orthogonal() * 3.0
	draw_colored_polygon(PackedVector2Array([at + dir * 4.0, at - dir * 2.0 + side, at - dir * 2.0 - side]), colour)


## The route node a step index belongs to: a walk step is its own node, a pause belongs
## to the point it is at, -1 is the start.
func _node_for_step(nodes: Array, step: int) -> int:
	if step < 0:
		return 0
	for i in nodes.size():
		if int(nodes[i]["step"]) == step:
			return i
		for pause in nodes[i]["pauses"]:
			if int(pause.get("step", -2)) == step:
				return i
	return 0


## H: faded figures where characters stand at other days / times, labelled with when.
func _draw_ghosts(container: Node2D) -> void:
	for g in tool.ghosts:
		var at := container.to_global(g["pos"])
		var tex = _ghost_frame(str(g["sprite"]))
		if tex is Texture2D:
			var size: Vector2 = (tex as Texture2D).get_size() * GHOST_SPRITE_SCALE
			draw_texture_rect(tex, Rect2(at - size * 0.5, size), false, Color(GHOST_TINT, GHOST_ALPHA))
		else:
			draw_circle(at, 4.0, Color(GHOST_TINT, GHOST_ALPHA))
		var font := ThemeDB.fallback_font
		var line1 := str(g["name"])
		var line2 := str(g["label"])
		draw_string_outline(font, at + Vector2(-60, 14), line1, HORIZONTAL_ALIGNMENT_CENTER, 120, GHOST_FONT_SIZE, 2, Color(0, 0, 0, 0.6))
		draw_string(font, at + Vector2(-60, 14), line1, HORIZONTAL_ALIGNMENT_CENTER, 120, GHOST_FONT_SIZE, Color(GHOST_TINT, 0.8))
		draw_string_outline(font, at + Vector2(-60, 21), line2, HORIZONTAL_ALIGNMENT_CENTER, 120, GHOST_FONT_SIZE, 2, Color(0, 0, 0, 0.6))
		draw_string(font, at + Vector2(-60, 21), line2, HORIZONTAL_ALIGNMENT_CENTER, 120, GHOST_FONT_SIZE, Color(1, 1, 1, 0.7))


func _ghost_frame(sprite: String):
	if not _ghost_frames.has(sprite):
		var tex = null
		if sprite != "":
			var frames: SpriteFrames = SpriteSheetLoader.load_sprite_frames(sprite)
			if frames != null and frames.has_animation("idle_down") and frames.get_frame_count("idle_down") > 0:
				tex = frames.get_frame_texture("idle_down", 0)
		_ghost_frames[sprite] = tex
	return _ghost_frames[sprite]


func _secs(s: float) -> String:
	return str(snappedf(s, 0.1)).trim_suffix(".0")


func _text(at: Vector2, text: String, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(0, 0, 0, colour.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
