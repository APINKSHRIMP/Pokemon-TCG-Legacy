extends CanvasLayer

# ============================================================
# TUTORIAL GUIDE -- "this one": a gold glow + a small arrow on whatever the tutorial wants pressed
# ============================================================
# 2026-11-12 (user): every time Olly's newby tutorial tells the player to do something, the
# thing to press -- the hand card, the Pokémon it goes on, the attack row, Retreat, End Turn,
# Done -- glows gold and slowly grows and shrinks. Mouse, keyboard and pad alike (it is drawn
# whatever the device).
#
# 2026-11-12 (user): deliberately NOT the cursor's gradient ring -- the two were too alike to
# tell apart. The guide is a warm gold glow that breathes slowly, plus one small rounded
# chevron that bobs over the FIRST target (the thing to press first).
#
# Preloaded (no class_name). Tutorial_Director makes one in newby mode and this asks it,
# EVERY FRAME, what to show (director.guide_targets()). Nothing is cached, so a board redraw,
# a hand opening or a selection screen appearing is simply picked up on the next frame.
#
# Each target is {"node": Control, "kind": "card" | "button" | "zone", "pulse": float}.
# A "zone" (the empty Bench) glows but is not pulsed. A node something else is already
# pulsing (Board_Nav's cursor, a selected card) keeps that pulse and only gets the glow.
# ============================================================

# TWEAKABLE
const LAYER := 95                 # over the board, under Hand_Drag (96, the dragged card) and Board_Nav (97)
const PULSE_SCALE := 1.07         # how big a highlighted card / button grows (a selected card is 1.03)
const PULSE_PERIOD := 2.2         # seconds for one slow grow-and-shrink (glow and arrow ride the same beat)
const CORNER_CARD := 6.0          # glow corner radius round a card
const MIN_ZONE_PX := 40.0         # a zone smaller than this (not laid out yet) gets no glow
const FADE_IN := 0.35             # seconds for the glow / arrow to fade in when they appear

const GLOW_PAD := 30.0            # px of halo room outside the target's edge (was 22)
const GLOW_LINE_PX := 2.5         # the gold outline's thickness
const GLOW_LINE_ALPHA := 0.3      # 2026-11-12 (user): the outline is only a hint now (was ~1.0)...
const GLOW_HALO_ALPHA := 1.0      # ...and the halo itself carries the highlight (was 0.9, narrower)
const GLOW_SPREAD := 0.45         # halo falloff, as a share of GLOW_PAD (higher = wider, softer)
const GLOW_COLOR := Color(1.0, 0.74, 0.18)      # the halo: warm gold
const GLOW_CORE := Color(1.0, 0.93, 0.62)       # the outline: pale gold
const GLOW_MIN := 0.55            # halo strength at the dim end of the breath (1.0 at the bright end)

const ARROW_W := 24.0             # chevron width
const ARROW_H := 13.0             # chevron height
const ARROW_LINE := 5.0           # chevron stroke thickness (round caps)
const ARROW_GAP := 10.0           # px between the target's edge and the arrow's tip
const ARROW_BOB := 14.0           # px the arrow bobs towards the target and back (was 6)
const ARROW_COLOR := Color(1.0, 0.82, 0.30)
const ARROW_SHADOW := Color(0.0, 0.0, 0.0, 0.35)

const GLOW_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 box_size = vec2(100.0);
uniform float pad = 22.0;
uniform float radius = 6.0;
uniform float line_px = 3.0;
uniform float strength = 1.0;
uniform float line_alpha = 0.3;
uniform float halo_alpha = 1.0;
uniform float spread = 0.45;
uniform vec4 glow_color : source_color = vec4(1.0, 0.74, 0.18, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.62, 1.0);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * box_size - box_size * 0.5;
	vec2 half_inner = max(box_size * 0.5 - vec2(pad), vec2(1.0));
	float d = sd_round_box(p, half_inner, min(radius, min(half_inner.x, half_inner.y)));
	float line = 1.0 - smoothstep(line_px * 0.5 - 0.8, line_px * 0.5 + 0.8, abs(d - line_px * 0.5));
	float halo = d > 0.0 ? exp(-d / (pad * spread)) * (1.0 - smoothstep(pad * 0.6, pad, d)) : exp(d / 3.0) * 0.5;
	float a = clamp(line * line_alpha + halo * halo_alpha * strength, 0.0, 1.0);
	vec3 col = mix(glow_color.rgb, core_color.rgb, line * 0.6 + halo * 0.25);
	COLOR = vec4(col, a * glow_color.a);
}
"""

var director: Node = null
var _glows: Array = []            # ColorRects with the glow shader, reused frame to frame
var _arrow: Control = null
var _scaled: Dictionary = {}      # node -> true: nodes this script scaled last frame
var _t: float = 0.0
var _shown_for: float = 0.0       # seconds the guide has been showing something (for the fade-in)
var _shader: Shader = null


func _init() -> void:
	layer = LAYER


func _process(delta: float) -> void:
	_t += delta
	var targets: Array = []
	if director != null and is_instance_valid(director) and director.has_method("guide_targets"):
		targets = director.guide_targets()

	var main: Node = director.main if director != null else null
	var still_scaled: Dictionary = {}
	var used := 0
	var msg_rect := _message_rect(main)
	var arrow_rect := Rect2()
	# 0..1..0 over one PULSE_PERIOD: the scale, the glow's breath and the arrow's bob share it.
	var beat: float = 0.5 - 0.5 * cos(TAU * _t / PULSE_PERIOD)
	for t in targets:
		var node = t.get("node", null)
		if not (node is Control) or not is_instance_valid(node) or not (node as Control).is_visible_in_tree():
			continue
		var c := node as Control
		var kind: String = String(t.get("kind", "card"))
		if kind != "zone" and _may_pulse(c, main):
			var amp: float = float(t.get("pulse", PULSE_SCALE)) - 1.0
			if not (c is CardDisplay):
				c.pivot_offset = c.size * 0.5
			c.scale = Vector2.ONE * (1.0 + amp * beat)
			still_scaled[c] = true
		var r := _rect_of(c)
		if kind == "zone" and (r.size.x < MIN_ZONE_PX or r.size.y < MIN_ZONE_PX):
			continue
		# This layer sits over the message box, so a glow under the box would draw across
		# its text. It waits until the box closes; the pulse carries on.
		if msg_rect.has_area() and r.intersects(msg_rect):
			continue
		var radius: float = float(UITheme.m("corner_radius")) if kind == "button" else CORNER_CARD
		_place_glow(_glow(used), r, radius, beat)
		used += 1
		if not arrow_rect.has_area():
			arrow_rect = r   # the first target is the thing to press first

	# Anything no longer highlighted goes back to its own size.
	for n in _scaled:
		if not still_scaled.has(n) and is_instance_valid(n):
			(n as Control).scale = Vector2.ONE
	_scaled = still_scaled
	for i in range(used, _glows.size()):
		(_glows[i] as Control).visible = false

	_shown_for = _shown_for + delta if used > 0 else 0.0
	var fade: float = clampf(_shown_for / FADE_IN, 0.0, 1.0)
	for i in range(used):
		(_glows[i] as Control).modulate.a = fade
	_place_arrow(arrow_rect, beat, fade)


# ── The glow ─────────────────────────────────────────────────────────────────

func _glow(i: int) -> ColorRect:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = GLOW_SHADER
	while _glows.size() <= i:
		var g := ColorRect.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("pad", GLOW_PAD)
		mat.set_shader_parameter("line_px", GLOW_LINE_PX)
		mat.set_shader_parameter("line_alpha", GLOW_LINE_ALPHA)
		mat.set_shader_parameter("halo_alpha", GLOW_HALO_ALPHA)
		mat.set_shader_parameter("spread", GLOW_SPREAD)
		mat.set_shader_parameter("glow_color", GLOW_COLOR)
		mat.set_shader_parameter("core_color", GLOW_CORE)
		g.material = mat
		add_child(g)
		_glows.append(g)
	return _glows[i]


func _place_glow(g: ColorRect, r: Rect2, radius: float, beat: float) -> void:
	var outer := r.grow(GLOW_PAD)
	g.position = outer.position
	g.size = outer.size
	g.visible = true
	var mat := g.material as ShaderMaterial
	mat.set_shader_parameter("box_size", outer.size)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("strength", lerpf(GLOW_MIN, 1.0, beat))


# ── The arrow ────────────────────────────────────────────────────────────────
# A small rounded chevron over the target, pointing at it (under it, pointing up, when there
# is no room above). It drifts a few px towards the target and back on the same slow beat.

func _place_arrow(r: Rect2, beat: float, fade: float) -> void:
	if not r.has_area():
		if _arrow != null:
			_arrow.visible = false
		return
	if _arrow == null or not is_instance_valid(_arrow):
		_arrow = Control.new()
		_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_arrow.size = Vector2(ARROW_W + ARROW_LINE * 2.0, ARROW_H + ARROW_LINE * 2.0 + 3.0)
		_arrow.draw.connect(_draw_arrow)
		add_child(_arrow)
	var bob: float = ARROW_BOB * beat
	var room_above: bool = r.position.y - ARROW_GAP - ARROW_BOB - _arrow.size.y > 4.0
	var x: float = r.get_center().x - _arrow.size.x * 0.5
	if room_above:
		_arrow.rotation = 0.0
		_arrow.position = Vector2(x, r.position.y - ARROW_GAP - _arrow.size.y - ARROW_BOB + bob)
	else:
		# Flipped: rotate half a turn about its centre so the tip points up at the target.
		_arrow.pivot_offset = _arrow.size * 0.5
		_arrow.rotation = PI
		_arrow.position = Vector2(x, r.end.y + ARROW_GAP + ARROW_BOB - bob)
	_arrow.modulate.a = fade
	_arrow.visible = true


func _draw_arrow() -> void:
	var w: float = ARROW_W
	var h: float = ARROW_H
	var o := Vector2(ARROW_LINE, ARROW_LINE)
	var pts := PackedVector2Array([o + Vector2(0, 0), o + Vector2(w * 0.5, h), o + Vector2(w, 0)])
	_chevron(pts, Vector2(0, 3), ARROW_SHADOW)
	_chevron(pts, Vector2.ZERO, ARROW_COLOR)


func _chevron(pts: PackedVector2Array, off: Vector2, col: Color) -> void:
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(p + off)
	_arrow.draw_polyline(moved, col, ARROW_LINE, true)
	for p in moved:   # round caps and a round tip
		_arrow.draw_circle(p, ARROW_LINE * 0.5, col, true, -1.0, true)


# ── Helpers ──────────────────────────────────────────────────────────────────

## The match message box's panel on screen while it is up, else an empty rect.
func _message_rect(main: Node) -> Rect2:
	if main == null or not main.msgbox_container.visible:
		return Rect2()
	var box = main.get("_match_msgbox")
	if box == null or not is_instance_valid(box):
		return Rect2()
	var panel = box.get("_panel")
	if not (panel is Control) or not is_instance_valid(panel) or not (panel as Control).is_visible_in_tree():
		return Rect2()
	return UIKit.transformed_rect(panel, Rect2(Vector2.ZERO, (panel as Control).size))


## Something else already pulses this node: leave its scale alone (two pulses would fight).
func _may_pulse(c: Control, main: Node) -> bool:
	if c is CardDisplay and (c as CardDisplay).is_selected:
		return false
	if main != null:
		var nav = main.get("board_nav")
		if nav != null and is_instance_valid(nav) and nav.get("_pulse_node") == c:
			return false
	return true


## Where the node is really drawn right now: a card by its ART (nodes can be taller than the
## picture), through its transform, so the glow rides the pulse.
func _rect_of(c: Control) -> Rect2:
	if c is TextureRect and (c as TextureRect).texture != null:
		return UIKit.drawn_texture_rect(c as TextureRect)
	return UIKit.transformed_rect(c, Rect2(Vector2.ZERO, c.size))


func clear() -> void:
	for n in _scaled:
		if is_instance_valid(n):
			(n as Control).scale = Vector2.ONE
	_scaled.clear()
	for g in _glows:
		if is_instance_valid(g):
			(g as Control).visible = false
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.visible = false
	_shown_for = 0.0


func _exit_tree() -> void:
	clear()
