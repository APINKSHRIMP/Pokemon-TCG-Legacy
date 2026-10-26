extends Node

# ============================================================
# CARD FX — small "body language" animations for cards on the board
# ============================================================
# ISSUE #471 (Special Conditions), #474 (attack / power gestures), #486 (Knock Out fade).
#
# Every effect plays on a GHOST: a stand-in TextureRect of the card's own image, the same
# trick play_attack_hit uses, so the board's layout is never touched. Unlike the attack
# hit, a ghost here FOLLOWS its card every frame (_process): it re-finds the card's node
# (find_card_ui_for_object), keeps that node transparent and sits on top of it plus the
# effect's offset / rotation / tint. A board refresh mid-effect just hands it a new node.
# When the last effect on a card ends, the ghost goes and the real card shows again.
#
# Fire-and-forget is the normal use: the effect starts, the message box opens over it
# straight away. `await` one when the next step should wait for it.
#
# All times go through GameState.match_time() like every other in-match beat.

var main   # Main_Match_Core_Gameplay_Script

const GHOST_Z := 140

# ── TWEAKABLE: Special Conditions (ISSUE #471) ─────────────────────────────────────────
# Poison: a slow, smooth sway (sine: speeds up through the middle, slows to a stop at
# each end, turns round) while the card fades to purple and back.
const POISON_TINT := Color(0.78, 0.45, 1.0)
const POISON_SWAY_PX := 12.0
const POISON_SWAY_PERIOD := 0.9     # seconds for one full left-right-left
const POISON_SWAY_CYCLES := 3
# Paralysis: a quick yellow flash and a fast, jagged, even shake (no easing).
const PARALYSIS_TINT := Color(1.0, 0.95, 0.35)
const PARALYSIS_SHAKE_PX := 6.0
const PARALYSIS_SHAKE_STEP := 0.035 # seconds per jolt
const PARALYSIS_SHAKES := 16
# Burn: between the two - a medium-speed sway with a red glow.
const BURN_TINT := Color(1.0, 0.45, 0.35)
const BURN_SWAY_PX := 9.0
const BURN_SWAY_PERIOD := 0.4
const BURN_SWAY_CYCLES := 4
# Confusion: the poison sway plus a small teeter, and two stars circling over the card.
const CONFUSE_TEETER := 0.07        # radians
const CONFUSE_STAR_PERIOD := 0.8    # seconds per lap
const CONFUSE_STAR_COLOUR := Color(1.0, 0.92, 0.3)
const CONFUSE_STAR_SIZE := 9.0
# Sleep: a slow bob and three black Zs drifting up and out from the top corner.
const SLEEP_BOB_PX := 6.0
const SLEEP_BOB_PERIOD := 1.2
const SLEEP_BOB_CYCLES := 2
const SLEEP_Z_COUNT := 3
const SLEEP_Z_GAP := 0.35           # seconds between Zs
const SLEEP_Z_LIFE := 0.5           # seconds before a Z starts to fade
const SLEEP_Z_FADE := 0.35
const SLEEP_Z_RISE := Vector2(34.0, -46.0)   # x is mirrored for the player's side
const SLEEP_Z_FONT := 20
const SLEEP_Z_GROW := 2.0

# ── TWEAKABLE: attack / power gestures (ISSUE #474) ────────────────────────────────────
const DECLARE_SHAKE_PX := 6.0       # every attack, as "X used Y!" opens
const DECLARE_SHAKE_STEP := 0.045
const DECLARE_SHAKES := 3           # left-right pairs
const INFLICT_DELAY := 0.5          # attacker sways, then the defender joins in after this
const INFLICT_SWAYS := 1            # side-to-side sways each card makes (was 2)
const HOP_PX := 16.0
const HOP_TIME := 0.16              # up, and the same back down
const SELF_HOPS := 3
const SELF_SHAKES := 2
const COUNTER_PAUSE := 0.2          # damage-counter attacks: a beat, then one hop
const POWER_SHAKE_PX := 3.5
const POWER_SHAKE_STEP := 0.04
const POWER_SHAKES := 5
const TEETER_ANGLE := 0.12
const TEETER_PERIOD := 0.3
const TEETER_CYCLES := 3

# ── TWEAKABLE: Knock Out (ISSUE #486) ──────────────────────────────────────────────────
const KO_DARK := Color(0.5, 0.5, 0.5)     # 50% towards black - twice as dark as the old 0.75 (25%)
const KO_DARK_TIME := 2.0
const KO_SWAY_PX := 10.0
const KO_SWAY_PERIOD := 1.0
const KO_SWAY_CYCLES := 2                   # back-and-forth sways, then it holds still (was endless)
const KO_UNFADE_TIME := 0.5

# card instance id -> {"card", "ghost", "offset", "rot", "tint", "users", "ko", "extras"}
var _entries: Dictionary = {}


func _process(_delta: float) -> void:
	for id in _entries.keys():
		_sync(_entries[id])


# ============================================================
# ENTRY POINTS
# ============================================================

## ISSUE #471: a Special Condition has just landed (or ticked) on `card`.
## kind: "Poisoned" / "Toxic" / "Burned" / "Paralyzed" / "Confused" / "Asleep".
func status(card: card_object, kind: String) -> void:
	print("ISSUE #471 FIX ACTIVE: status fx '", kind, "' on ", _name(card))
	# Attack VFX: the condition's own effect (poison bubbles, flames, sparks...) plays over the card too.
	if main != null and main.attack_vfx != null:
		main.attack_vfx.play_status(card, kind)
	match kind:
		"Poisoned", "Toxic":
			await _sway(card, POISON_SWAY_PX, POISON_SWAY_PERIOD, POISON_SWAY_CYCLES, POISON_TINT, 0.0)
		"Paralyzed":
			await _jolt(card, PARALYSIS_SHAKE_PX, PARALYSIS_SHAKE_STEP, PARALYSIS_SHAKES, PARALYSIS_TINT)
		"Burned":
			await _sway(card, BURN_SWAY_PX, BURN_SWAY_PERIOD, BURN_SWAY_CYCLES, BURN_TINT, 0.0)
		"Confused":
			await _confused(card)
		"Asleep":
			await _asleep(card)


## ISSUE #474: "X used Y!" -- three quick shakes, damaging or not.
func attack_declared(card: card_object) -> void:
	print("ISSUE #474 FIX ACTIVE: declare shake on ", _name(card))
	await _jolt(card, DECLARE_SHAKE_PX, DECLARE_SHAKE_STEP, DECLARE_SHAKES * 2, Color.WHITE)


## ISSUE #474: the gesture a NON-damaging attack makes instead of the lunge.
func attack_intent(attacker: card_object, defender: card_object, attack: Dictionary) -> void:
	var kind := classify_attack(attacker, attack)
	print("ISSUE #474 FIX ACTIVE: no-damage attack '", attack.get("name", ""), "' -> ", kind)
	match kind:
		"inflict":
			# 1) the attacker sways; half a second in, the defender sways too.
			_sway(attacker, POISON_SWAY_PX, POISON_SWAY_PERIOD, INFLICT_SWAYS, Color.WHITE, 0.0)
			await _wait(INFLICT_DELAY)
			if defender != null:
				await _sway(defender, POISON_SWAY_PX, POISON_SWAY_PERIOD, INFLICT_SWAYS, Color.WHITE, 0.0)
		"self":
			# 2) three hops on the spot, then two quick shakes.
			await _hops(attacker, SELF_HOPS)
			await _jolt(attacker, DECLARE_SHAKE_PX, DECLARE_SHAKE_STEP, SELF_SHAKES * 2, Color.WHITE)
		"counters":
			# 3) a beat, then one hop.
			await _wait(COUNTER_PAUSE)
			await _hops(attacker, 1)
		_:
			# 5) anything else: a teeter.
			await _teeter(attacker, TEETER_ANGLE, TEETER_PERIOD, TEETER_CYCLES)


## ISSUE #474 (4): a Pokémon Power is used -- a small fast shake.
func power_used(card: card_object) -> void:
	print("ISSUE #474 FIX ACTIVE: power shake on ", _name(card))
	await _jolt(card, POWER_SHAKE_PX, POWER_SHAKE_STEP, POWER_SHAKES * 2, Color.WHITE)


## Attack VFX body motions: a special attack hops / sways / shakes its attacker on the spot.
func hop(card: card_object, n: int) -> void:
	await _hops(card, n)

func sway(card: card_object, cycles: int) -> void:
	await _sway(card, POISON_SWAY_PX, POISON_SWAY_PERIOD, cycles, Color.WHITE, 0.0)

func shake(card: card_object) -> void:
	await _jolt(card, DECLARE_SHAKE_PX, DECLARE_SHAKE_STEP, DECLARE_SHAKES * 4, Color.WHITE)

func jolt(card: card_object, px: float, step: float, count: int) -> void:
	await _jolt(card, px, step, count, Color.WHITE)

## Attack VFX: drives fn(entry, 0..1) on `card`'s ghost for `dur` REAL seconds (the caller has already
## applied match_time). The entry's "offset" / "rot" / "scale" (Vector2) / "tint" / "alpha" / "z" are what
## fn may set; all go back to rest when it ends. Several can run on one card at once (last write wins).
func motion(card: card_object, dur: float, fn: Callable) -> void:
	await _run(card, dur, fn)

## The ghost currently standing in for `card` (afterimages copy it), or null.
func ghost_of(card: card_object) -> TextureRect:
	if card == null or not _entries.has(card.get_instance_id()):
		return null
	return _entries[card.get_instance_id()]["ghost"]


## True while one of these animations is standing in for `card` (its real node is hidden meanwhile).
func has_ghost(card: card_object) -> bool:
	return card != null and _entries.has(card.get_instance_id())


## ISSUE #474: a very simple reading of a 0-damage attack's text.
##   "counters"  moves / places damage counters, or hits the Bench  (animation 3)
##   "inflict"   does something to the Defending Pokémon            (animation 1)
##   "self"      only does something to the attacker                (animation 2)
##   "other"     anything else                                      (animation 5)
func classify_attack(attacker: card_object, attack: Dictionary) -> String:
	var t: String = String(attack.get("text", "")).to_lower().replace("é", "e")
	if "damage counter" in t or "bench" in t:
		return "counters"
	for w in ["defending pokemon", "opponent's active", "asleep", "confused", "paralyzed", "poisoned",
			"burned", "can't retreat", "can't attack", "your opponent"]:
		if w in t:
			return "inflict"
	var own: String = attacker.metadata.get("name", "").to_lower() if attacker != null else ""
	for w in ["this pokemon", "attach", "your deck", "your hand", "remove", "heal", "during your next turn"]:
		if w in t:
			return "self"
	if own != "" and own in t:
		return "self"
	return "other"


## ISSUE #486: `card` has just been Knocked Out -- it slowly darkens and sways KO_SWAY_CYCLES
## times, then stays dark and still until end_ko().
func start_ko(card: card_object) -> void:
	if card == null or (_entries.has(card.get_instance_id()) and _entries[card.get_instance_id()]["ko"]):
		return
	var e := _entry(card)
	if e.is_empty():
		return
	print("ISSUE #486 FIX ACTIVE: KO fade on ", _name(card))
	e["ko"] = true
	e["users"] += 1
	var start_t := Time.get_ticks_msec()
	var dark_time: float = maxf(GameState.match_time(KO_DARK_TIME), 0.01)
	var period: float = maxf(GameState.match_time(KO_SWAY_PERIOD), 0.01)
	e["ko_fn"] = func():
		var t: float = float(Time.get_ticks_msec() - start_t) / 1000.0
		e["tint"] = Color.WHITE.lerp(KO_DARK, clampf(t / dark_time, 0.0, 1.0))
		# KO_SWAY_CYCLES full sways, then still at centre (sin is 0 at a whole cycle).
		var cycles: float = minf(t / period, float(KO_SWAY_CYCLES))
		e["offset"] = Vector2(sin(TAU * cycles) * KO_SWAY_PX, 0.0)


## ISSUE #486: the Knock Out message has been read -- the card lightens again as it leaves.
func end_ko(card: card_object) -> void:
	if card == null or not _entries.has(card.get_instance_id()):
		return
	var e: Dictionary = _entries[card.get_instance_id()]
	if not e["ko"]:
		return
	e["ko"] = false
	e.erase("ko_fn")
	var node := _node(card)
	_release(e)
	if node != null and _entries.get(card.get_instance_id(), {}).is_empty():
		node.modulate = Color(KO_DARK.r, KO_DARK.g, KO_DARK.b, node.modulate.a)
		var tw := node.create_tween()
		tw.tween_property(node, "modulate", Color(1, 1, 1, node.modulate.a), GameState.match_time(KO_UNFADE_TIME))


## Any card still fading (it survived -- Focus Band, Endure...) goes back to normal.
func end_all_ko() -> void:
	for id in _entries.keys():
		if _entries.has(id) and _entries[id]["ko"]:
			end_ko(_entries[id]["card"])


# ============================================================
# MOTIONS
# ============================================================

## A sine sway: fastest through the middle, easing to a stop at each end, then back.
func _sway(card: card_object, px: float, period: float, cycles: int, tint: Color, teeter: float) -> void:
	var dur: float = GameState.match_time(period * cycles)
	await _run(card, dur, func(e: Dictionary, f: float):
		var phase: float = f * float(cycles) * TAU
		e["offset"] = Vector2(sin(phase) * px, 0.0)
		e["rot"] = sin(phase * 2.0) * teeter
		e["tint"] = Color.WHITE.lerp(tint, sin(f * PI)))


## An even, jagged shake: straight lines between +px and -px, no easing.
func _jolt(card: card_object, px: float, step: float, count: int, tint: Color) -> void:
	var dur: float = GameState.match_time(step * count)
	await _run(card, dur, func(e: Dictionary, f: float):
		var pos: float = f * float(count)
		var i := int(pos)
		var frac: float = pos - float(i)
		var a: float = px if i % 2 == 0 else -px
		var b: float = -a
		e["offset"] = Vector2(lerpf(a, b, frac) if i < count - 1 else lerpf(a, 0.0, frac), 0.0)
		# A quick flash in, a slower fade out.
		e["tint"] = Color.WHITE.lerp(tint, clampf(f * 6.0, 0.0, 1.0) * clampf((1.0 - f) * 1.5, 0.0, 1.0)))


func _hops(card: card_object, n: int) -> void:
	var dur: float = GameState.match_time(HOP_TIME * 2.0 * n)
	await _run(card, dur, func(e: Dictionary, f: float):
		e["offset"] = Vector2(0.0, -absf(sin(f * float(n) * PI)) * HOP_PX))


func _teeter(card: card_object, angle: float, period: float, cycles: int) -> void:
	var dur: float = GameState.match_time(period * cycles)
	await _run(card, dur, func(e: Dictionary, f: float):
		e["rot"] = sin(f * float(cycles) * TAU) * angle * sin(f * PI))


func _confused(card: card_object) -> void:
	var e := _entry(card)
	if e.is_empty():
		return
	var ring := _StarRing.new()
	ring.colour = CONFUSE_STAR_COLOUR
	ring.star_size = CONFUSE_STAR_SIZE
	ring.period = maxf(GameState.match_time(CONFUSE_STAR_PERIOD), 0.05)
	e["ghost"].add_child(ring)
	ring.size = e["ghost"].size
	await _sway(card, POISON_SWAY_PX, POISON_SWAY_PERIOD, POISON_SWAY_CYCLES, Color.WHITE, CONFUSE_TEETER)
	if is_instance_valid(ring):
		ring.queue_free()


func _asleep(card: card_object) -> void:
	var e := _entry(card)
	if e.is_empty():
		return
	var is_opp: bool = card.is_owner_opp(main)
	_spawn_zs(e, is_opp)
	var dur: float = GameState.match_time(SLEEP_BOB_PERIOD * SLEEP_BOB_CYCLES)
	await _run(card, dur, func(en: Dictionary, f: float):
		en["offset"] = Vector2(0.0, -sin(f * float(SLEEP_BOB_CYCLES) * TAU) * SLEEP_BOB_PX * sin(f * PI)))


## Three black Zs out of the top corner nearest the middle of the board: top-left for
## the player's cards (drifting up-left), top-right for the opponent's (up-right).
func _spawn_zs(e: Dictionary, is_opp: bool) -> void:
	var ghost: Control = e["ghost"]
	var dir_x: float = 1.0 if is_opp else -1.0
	for i in SLEEP_Z_COUNT:
		var z := Label.new()
		z.text = "Z"
		z.mouse_filter = Control.MOUSE_FILTER_IGNORE
		z.z_index = GHOST_Z + 1
		z.add_theme_font_size_override("font_size", SLEEP_Z_FONT)
		z.add_theme_color_override("font_color", Color.BLACK)
		z.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		z.add_theme_constant_override("outline_size", 3)
		z.modulate.a = 0.0
		main.add_child(z)
		var corner: Vector2 = ghost.global_position + (Vector2(ghost.size.x, 0.0) if is_opp else Vector2.ZERO)
		z.global_position = corner + Vector2(-8.0 if not is_opp else -12.0, -10.0)
		z.pivot_offset = Vector2(8, 12)
		z.rotation = 0.3 * dir_x
		var tw := z.create_tween()
		tw.tween_interval(GameState.match_time(SLEEP_Z_GAP * i))
		tw.tween_property(z, "modulate:a", 1.0, GameState.match_time(0.1))
		tw.parallel().tween_property(z, "position", z.position + Vector2(SLEEP_Z_RISE.x * dir_x, SLEEP_Z_RISE.y),
			GameState.match_time(SLEEP_Z_LIFE + SLEEP_Z_FADE)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(z, "scale", Vector2.ONE * SLEEP_Z_GROW, GameState.match_time(SLEEP_Z_LIFE + SLEEP_Z_FADE))
		tw.parallel().tween_property(z, "modulate:a", 0.0, GameState.match_time(SLEEP_Z_FADE)).set_delay(GameState.match_time(SLEEP_Z_LIFE))
		tw.tween_callback(z.queue_free)


func _wait(seconds: float) -> void:
	if GameState.is_motion_reduced():
		return
	var t: float = GameState.match_time(seconds)
	if t > 0.0:
		await get_tree().create_timer(t).timeout


## Drives fn(entry, 0..1) over `dur` seconds on `card`'s ghost, then lets go of it.
func _run(card: card_object, dur: float, fn: Callable) -> void:
	var e := _entry(card)
	if e.is_empty():
		return
	e["users"] += 1
	if dur > 0.0:
		var tw := create_tween()
		tw.tween_method(func(f: float): fn.call(e, f), 0.0, 1.0, dur)
		await tw.finished
	e["offset"] = Vector2.ZERO
	e["rot"] = 0.0
	e["tint"] = Color.WHITE
	e["scale"] = Vector2.ONE
	e["alpha"] = 1.0
	e["z"] = 0
	_release(e)


# ============================================================
# GHOSTS
# ============================================================

func _entry(card: card_object) -> Dictionary:
	if card == null or main == null:
		return {}
	var id := card.get_instance_id()
	if _entries.has(id):
		return _entries[id]
	var node := _node(card)
	if node == null:
		return {}
	var g := TextureRect.new()
	g.texture = node.texture
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = node.stretch_mode
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.z_index = GHOST_Z
	main.add_child(g)
	var e := {"card": card, "ghost": g, "offset": Vector2.ZERO, "rot": 0.0, "tint": Color.WHITE,
		"scale": Vector2.ONE, "alpha": 1.0, "z": 0, "users": 0, "ko": false}
	_entries[id] = e
	_sync(e)
	return e


func _node(card: card_object) -> TextureRect:
	var node: TextureRect = main.find_card_ui_for_object(card)
	if node == null or not is_instance_valid(node) or not node.is_visible_in_tree() or node.texture == null:
		return null
	return node


func _sync(e: Dictionary) -> void:
	var g: TextureRect = e["ghost"]
	if not is_instance_valid(g):
		return
	if e.has("ko_fn"):
		e["ko_fn"].call()
	var node := _node(e["card"])
	if node == null:
		g.visible = false
		return
	g.visible = true
	node.modulate.a = 0.0
	if g.texture != node.texture:
		g.texture = node.texture
	g.size = node.size * node.get_global_transform().get_scale()
	g.pivot_offset = g.size / 2.0
	# Set in the PARENT's space, not via global_position: Godot 4's Control global_position
	# setter subtracts the rotation/pivot transform, so with the ghost rotated it pinned the
	# rotated TOP-LEFT corner to the card's corner and the teeter swung about that corner
	# instead of the pivot. `position` is the un-rotated top-left, so pivot_offset (the
	# centre) is what the card turns about.
	g.rotation = e["rot"]
	g.scale = e["scale"]
	g.z_index = GHOST_Z + int(e["z"])
	g.position = main.get_global_transform().affine_inverse() * (node.global_position + e["offset"])
	var t: Color = e["tint"]
	g.modulate = Color(t.r, t.g, t.b, t.a * float(e["alpha"]))


func _release(e: Dictionary) -> void:
	e["users"] = maxi(0, int(e["users"]) - 1)
	if e["users"] > 0 or e["ko"]:
		return
	var card: card_object = e["card"]
	var node := _node(card)
	if node != null:
		node.modulate.a = 1.0
	if is_instance_valid(e["ghost"]):
		e["ghost"].queue_free()
	_entries.erase(card.get_instance_id())


func _name(card: card_object) -> String:
	return card.metadata.get("name", "?") if card != null else "?"


## Two stars chasing each other round a flat ellipse over the top of the card, each
## pulling a fading yellow trail that reaches back to the other.
class _StarRing extends Control:
	var colour: Color = Color.YELLOW
	var star_size: float = 9.0
	var period: float = 0.8
	var _t: float = 0.0
	const TRAIL_STEPS := 14

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _point(angle: float) -> Vector2:
		var c := Vector2(size.x * 0.5, size.y * 0.04)
		return c + Vector2(cos(angle) * size.x * 0.38, sin(angle) * size.y * 0.06)

	func _draw() -> void:
		var base: float = TAU * _t / period
		for s in 2:
			var a: float = base + PI * s
			# The trail: from the other star's position up to this one, fading in.
			for k in TRAIL_STEPS:
				var f: float = float(k) / float(TRAIL_STEPS)
				var ta: float = a - PI * (1.0 - f)
				draw_circle(_point(ta), 2.0 + 2.0 * f, Color(colour.r, colour.g, colour.b, 0.55 * f * f))
			_draw_star(_point(a), star_size)

	func _draw_star(at: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var rr: float = r if i % 2 == 0 else r * 0.45
			var ang: float = -PI / 2.0 + TAU * float(i) / 10.0
			pts.append(at + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(pts, colour)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.25, 0.0), 1.0)
