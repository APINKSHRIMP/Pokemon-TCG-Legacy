class_name PokemonEvolution
extends Node2D

## EVOLUTION (2026-11-24): your follower evolving, on the map, the way the handheld games do it.
##
##   "What? Spike is evolving!"                      (its name pill, OK to go on)
##   it flashes to white and a glow builds around it - the glow slowly breathes (grows and
##     shrinks) and shifts from white to a pale blue and back as it does
##   it flickers between its own white silhouette and the evolution's, faster and faster
##   it settles as the evolution's silhouette, the glow swells and BURSTS like energy
##     (blue pixels thrown outward from all around it, a white screen flash), the colour
##     comes back
##   "Congratulations! Your Spike evolved into Metapod!"   (the new species' cry)
##
## WHEN: after a match you WIN, AFTER any medal earned with it (user rule: the medal first - it
## takes the screen - then the evolution on the map). GameState.record_match_result asks
## check_after_win(); a hit is held in _pending until the map loads (BaseMapScene._ready calls
## run_pending, which waits for the battle-return fade and BaseMapScene.medals_waiting()). The
## whole time it holds MapManager.hard_lock("evolution") - nothing can be pressed but the
## lines' OK. A medal earned WHILE it plays waits for it (is_playing()).
##
## WHAT IT EVOLVES INTO: evolutions_of() reads the card data (a card's evolvesFrom), so every
## species knows its next stage(s) with no table to keep. The RULES for when are the CSV's
## Evolution column (PokemonPrefs.evolution_of) - NOT implemented yet: the user fills the
## column in first. Until then only the DEL menu evolves anything ("Evolve follower now" /
## "Evolve after the next win").
##
## The data side is PokemonHome.evolve(): it gets a new ID for its new species everywhere
## (follower, home list, flags - nickname, shiny, affection and counts carry over).
##
## SPEED (user 2026-11-24): every time below was halved from the first version - twice as quick.

# ---- TWEAKABLES -------------------------------------------------------------
## The first line ("" = no line, straight into the animation). %s = its name.
const EVOLVING_LINE := "What? %s is evolving!"
## The last line. %s = its name before, %s = the new species.
const EVOLVED_LINE := "Congratulations! Your %s evolved into %s!"
## Seconds: the beat after the battle-return fade before it starts; the flash to white.
const START_BEAT := 0.2
const FLASH_IN_TIME := 0.4
## The flicker between the two silhouettes: seconds per silhouette at the start and at the
## end (it speeds up between them), and how long the flicker lasts in all.
const SWAP_START := 0.21
const SWAP_END := 0.0225
const SWAP_TOTAL := 1.7
## The glow: its colour, its size (world px across) at rest, how much it swells before the burst.
const GLOW_COLOUR := Color(1.0, 0.96, 0.78)
const GLOW_SIZE := 56.0
const GLOW_SWELL := 2.0
const SWELL_TIME := 0.275
## The glow's breathing the whole time it is up: one grow-and-shrink takes GLOW_PULSE_PERIOD
## seconds and changes its size by +/- GLOW_PULSE_AMOUNT (0.1 = 10%). As it grows it shifts
## from GLOW_COLOUR to GLOW_PULSE_COLOUR, and back as it shrinks. The glow is ADDED onto the
## map, so this is bluer than it looks: on screen it reads as a very pale, washed-out light
## blue (a paler value barely shows over the warm floors).
const GLOW_PULSE_PERIOD := 1.1
const GLOW_PULSE_AMOUNT := 0.1
const GLOW_PULSE_COLOUR := Color(0.45, 0.68, 1.0)
## After the burst the glow blows out to this many times its swelled size while it fades.
const POP_SCALE := 2.6
const POP_TIME := 0.175
## THE BLUE PIXELS at the burst: how many, where they start (a ring round the Pokémon, as a
## fraction of its frame size: 0.5 = its edge), their speed outward (world px/s), how quickly
## they slow (per second), how long they last (a random life in this range, fading out), and
## their size (world px; some come out BURST_BIG_SIZE). One colour per pixel from the list.
const BURST_PIXELS := 160
const BURST_RING_MIN := 0.25
const BURST_RING_MAX := 0.55
const BURST_SPEED_MIN := 45.0
const BURST_SPEED_MAX := 150.0
const BURST_DRAG := 2.2
const BURST_LIFE_MIN := 0.45
const BURST_LIFE_MAX := 0.9
const BURST_PIXEL_SIZE := 1.5
const BURST_BIG_SIZE := 2.5
const BURST_BIG_CHANCE := 0.3
const BURST_COLOURS := [
	Color(0.86, 0.93, 1.0),    # near-white blue
	Color(0.68, 0.84, 1.0),    # light
	Color(0.50, 0.76, 1.0),
	Color(0.42, 0.86, 1.0),    # light cyan-blue
	Color(0.27, 0.60, 1.0),    # saturated
	Color(0.15, 0.45, 0.98),
	Color(0.10, 0.32, 0.90),   # deep
]
const SCREEN_FLASH_ALPHA := 0.85
const SCREEN_FLASH_TIME := 0.275
## Seconds after the burst before its colour starts coming back, how long that takes, then a
## beat before the last line.
const COLOUR_BACK_DELAY := 0.075
const COLOUR_BACK_TIME := 0.35
const END_BEAT := 0.175
## Drawn over the map's Pokémon and people.
const FX_Z := 60
# -----------------------------------------------------------------------------

const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a * COLOR.a);
}
"""

static var _pending: Dictionary = {}
static var _running: bool = false
static var _playing: bool = false
## DEL menu: the next match you win evolves your follower into its first evolution.
static var debug_after_next_win: bool = false
static var _evo_map: Dictionary = {}
static var _evo_map_built: bool = false
static var _shader: Shader = null

var _old: Sprite2D = null
var _new: Sprite2D = null
var _glow: Sprite2D = null
## The glow's size and alpha WITHOUT the breathing (the tweens move these; _process adds the
## pulse and the white-to-blue shift on top).
var _glow_base: Vector2 = Vector2.ZERO
var _glow_alpha: float = 0.0
var _pulse_t: float = 0.0


# ============================================================
# DATA
# ============================================================

## The species this one evolves into (species keys, "010_Caterpie" -> ["011_Metapod"]). From the
## card data: every Pokémon card whose evolvesFrom is this species' name, keeping only names that
## are plain overworld species (no "Dark", "Brock's", "ex" ...). Built once.
static func evolutions_of(species_key: String) -> Array:
	if not _evo_map_built:
		_build_evo_map()
	return (_evo_map.get(OverworldPokemonData.display_name(OverworldPokemonData.species_of(species_key)), []) as Array).duplicate()


static func _build_evo_map() -> void:
	_evo_map_built = true
	# display name -> species key, plain sheets only ("019_Rattata", not "019_Rattata_Alolan").
	var by_name: Dictionary = {}
	for key in OverworldPokemonData.all_species():
		var parts := str(key).split("_")
		if parts.size() == 2 and not by_name.has(parts[1]):
			by_name[OverworldPokemonData.display_name(str(key))] = str(key)
	var dir := DirAccess.open("res://Card_Set_Data")
	if dir == null:
		return
	var paths: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json") and fname != "pack_prices.json":
			paths.append("res://Card_Set_Data/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var cards = JSON.parse_string(f.get_as_text())
		if not (cards is Array):
			continue
		for card in cards:
			if not (card is Dictionary):
				continue
			var from := str(card.get("evolvesFrom", ""))
			var to := str(card.get("name", ""))
			if from == "" or not by_name.has(from) or not by_name.has(to):
				continue
			var list: Array = _evo_map.get(from, [])
			if not (str(by_name[to]) in list):
				list.append(str(by_name[to]))
			_evo_map[from] = list


## Can your Pokémon `species_key` (an ID) become `into` right now? Not when `into` has no
## overworld art. Owning another `into` already is fine (each Pokémon has its own ID).
static func can_evolve_into(species_key: String, into: String) -> bool:
	if into == "" or into == PokemonHome.species_of(species_key):
		return false
	return ResourceLoader.exists(OverworldPokemonData.sheet_path(into))


## What `species_key` evolves into after a win, "" for nothing.
## REQUIREMENTS GO HERE once the CSV's Evolution column is filled in
## (PokemonPrefs.evolution_of(species_key) holds the cell's text; flags "wins", "pets",
## "meals" and PokemonAffection.level() are already kept for it).
static func due_after_win(species_key: String) -> String:
	if debug_after_next_win:
		var targets := evolutions_of(species_key)
		return str(targets[0]) if not targets.is_empty() else ""
	return ""


## GameState.record_match_result, on a win. Queues the follower's evolution if it is due.
static func check_after_win(_test_match: bool) -> void:
	var follower := GameState.get_follower()
	if follower == "" or not _pending.is_empty():
		return
	var into := due_after_win(follower)
	if not can_evolve_into(follower, into):
		return
	debug_after_next_win = false
	_pending = {"id": follower, "into": into}


static func queue(species_key: String, into: String) -> bool:
	if not can_evolve_into(species_key, into):
		return false
	_pending = {"id": species_key, "into": into}
	return true


static func has_pending() -> bool:
	return not _pending.is_empty()


## True from the moment one is queued until its last line is closed.
static func is_busy() -> bool:
	return _running or not _pending.is_empty()


## True only while it is actually on screen (past the wait for the fade and any medal).
static func is_playing() -> bool:
	return _playing


# ============================================================
# THE SEQUENCE
# ============================================================

## Plays the queued evolution on `map_root` (a BaseMapScene). Fire and forget.
static func run_pending(map_root: Node) -> void:
	if _running or _pending.is_empty() or map_root == null:
		return
	_running = true
	MapManager.hard_lock("evolution")
	var p := _pending.duplicate()
	var tree := map_root.get_tree()
	# The battle-return fade, any medal (earned or still being looked for), a line already up,
	# a cutscene: all go first.
	await tree.process_frame
	await tree.process_frame
	while is_instance_valid(map_root) and map_root.is_inside_tree() and _must_wait():
		await tree.process_frame
	await tree.create_timer(START_BEAT).timeout
	# Something may have come up during the beat (a medal found late): wait again.
	while is_instance_valid(map_root) and map_root.is_inside_tree() and _must_wait():
		await tree.process_frame
	_playing = true
	if is_instance_valid(map_root) and map_root.is_inside_tree():
		await _play(map_root, str(p["id"]), str(p["into"]))
	else:
		PokemonHome.evolve(str(p["id"]), str(p["into"]))   # the map went away: still evolve it
	_playing = false
	_pending = {}
	_running = false
	MapManager.hard_unlock("evolution")


static func _must_wait() -> bool:
	# The medal watch does not run in a T test match / the autotester, so medals_dirty would
	# never clear there: only wait on it when the watch is running.
	var medal_watch_runs: bool = not GameState.test_match_mode and GameState.autotest == null
	return MatchTransition.is_returning() or MapManager.cutscene_active \
			or (medal_watch_runs and GameState.medals_dirty) or BaseMapScene.medals_waiting() \
			or (MapManager.message_panel != null and MapManager.message_panel.visible)


## `old` is your Pokémon's ID, `into` the species it becomes.
static func _play(map_root: Node, old: String, into: String) -> void:
	var tree := map_root.get_tree()
	var name_before := PokemonHome.name_of(old)
	var shiny := PokemonHome.is_shiny(old)
	var follower: PokemonFollower = tree.get_first_node_in_group(PokemonFollower.GROUP) as PokemonFollower
	if follower != null and (not is_instance_valid(follower) or PokemonHome.id_of(follower) != old or follower.sprite == null):
		follower = null
	if follower != null:
		follower.set_facing("down")
	if EVOLVING_LINE != "":
		await _say(tree, old, name_before, EVOLVING_LINE % name_before)
	SoundManagerScript.play_cry(PokemonHome.species_of(old), 1.0, true)

	var at: Vector2 = Vector2.ZERO
	var fx: PokemonEvolution = null
	if follower != null and is_instance_valid(follower):
		at = follower.global_position
		fx = PokemonEvolution.new()
		map_root.add_child(fx)
		fx.global_position = follower.sprite.global_position
		fx._build(PokemonHome.species_of(old), into, shiny, follower.draw_scale())
		follower.visible = false
		follower.process_mode = Node.PROCESS_MODE_DISABLED
		await fx._run()

	# The data: it IS the new species from here on.
	var new_id := PokemonHome.evolve(old, into)
	if follower != null:
		var player := tree.get_first_node_in_group("player") as Node2D
		PokemonFollower.spawn_for(map_root, player, at)
	if fx != null and is_instance_valid(fx):
		var out := fx.create_tween()
		out.tween_property(fx, "modulate:a", 0.0, 0.1)
		out.tween_callback(fx.queue_free)
	await tree.create_timer(END_BEAT).timeout
	SoundManagerScript.play_cry(into, 1.0, true)
	await _say(tree, new_id, PokemonHome.name_of(new_id),
			EVOLVED_LINE % [name_before, OverworldPokemonData.display_name(into)])


## One line with its name pill; returns once the player has closed it.
static func _say(tree: SceneTree, species_key: String, poke_name: String, text: String) -> void:
	MapManager._pokemon_say(species_key, poke_name, text)
	await tree.process_frame
	while MapManager.message_panel != null and MapManager.message_panel.visible:
		await tree.process_frame


# ---- the visual ------------------------------------------------------------------

static func _flash_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = FLASH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


## The species' front-facing first frame (row 0 = down).
func _frame_sprite(species_key: String, shiny: bool, sc: float) -> Sprite2D:
	var s := Sprite2D.new()
	var tex: Texture2D = load(OverworldPokemonData.sheet_path(species_key, shiny))
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.region_enabled = true
	s.region_filter_clip_enabled = true
	if tex != null:
		s.region_rect = Rect2(0, 0, tex.get_width() / 4.0, tex.get_height() / 4.0)
	s.scale = Vector2(sc, sc)
	s.material = _flash_material()
	add_child(s)
	return s


func _build(old: String, into: String, shiny: bool, sc: float) -> void:
	z_as_relative = false
	z_index = FX_Z
	_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_glow.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow_base = Vector2.ONE * (GLOW_SIZE / 64.0) * 0.6
	_glow_alpha = 0.0
	_apply_glow()
	add_child(_glow)
	_old = _frame_sprite(old, shiny, sc)
	_new = _frame_sprite(into, shiny, sc)
	_new.visible = false
	(_new.material as ShaderMaterial).set_shader_parameter("flash", 1.0)


func _run() -> void:
	var rest := Vector2.ONE * (GLOW_SIZE / 64.0)
	# 1. white, and the glow builds
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: (_old.material as ShaderMaterial).set_shader_parameter("flash", v),
			0.0, 1.0, FLASH_IN_TIME)
	tw.tween_property(self, "_glow_alpha", 0.85, FLASH_IN_TIME)
	tw.tween_property(self, "_glow_base", rest, FLASH_IN_TIME).set_trans(Tween.TRANS_SINE)
	await tw.finished
	# 2. the flicker between the two silhouettes, speeding up
	var t := 0.0
	var show_new := false
	while t < SWAP_TOTAL:
		show_new = not show_new
		_old.visible = not show_new
		_new.visible = show_new
		var interval := lerpf(SWAP_START, SWAP_END, clampf(t / SWAP_TOTAL, 0.0, 1.0))
		await get_tree().create_timer(interval).timeout
		t += interval
	_old.visible = false
	_new.visible = true
	# 3. the glow swells...
	var swell := create_tween().set_parallel(true)
	swell.tween_property(self, "_glow_base", rest * GLOW_SWELL, SWELL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	swell.tween_property(self, "_glow_alpha", 1.0, SWELL_TIME)
	await swell.finished
	# 4. ...and bursts
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_evolve_sound)
	_burst()
	_screen_flash()
	var pop := create_tween().set_parallel(true)
	pop.tween_property(self, "_glow_base", rest * GLOW_SWELL * POP_SCALE, POP_TIME).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "_glow_alpha", 0.0, POP_TIME)
	# 5. its colour comes back
	var back := create_tween()
	back.tween_interval(COLOUR_BACK_DELAY)
	back.tween_method(func(v: float) -> void: (_new.material as ShaderMaterial).set_shader_parameter("flash", v),
			1.0, 0.0, COLOUR_BACK_TIME)
	await back.finished


## The glow's breathing, every frame: size pulses round _glow_base, colour swings from
## GLOW_COLOUR (smallest) to GLOW_PULSE_COLOUR (biggest). Starts small and white.
func _process(delta: float) -> void:
	if _glow == null:
		return
	_pulse_t += delta
	_apply_glow()


func _apply_glow() -> void:
	var s := -cos(TAU * _pulse_t / GLOW_PULSE_PERIOD)   # -1 smallest .. 1 biggest
	_glow.scale = _glow_base * (1.0 + GLOW_PULSE_AMOUNT * s)
	var c := GLOW_COLOUR.lerp(GLOW_PULSE_COLOUR, (s + 1.0) * 0.5)
	_glow.modulate = Color(c.r, c.g, c.b, _glow_alpha)


## The blue pixels, thrown outward from a ring all round the Pokémon. They live on the MAP (not
## this node, which fades out and goes right after), so they finish flying on their own.
func _burst() -> void:
	var size := Vector2(24, 24)
	if _new != null and _new.texture != null:
		size = _new.region_rect.size * _new.scale.abs()
	var reach := maxf(size.x, size.y)
	var pixels := _BluePixels.new()
	pixels.z_as_relative = false
	pixels.z_index = FX_Z + 1
	var parent := get_parent() if get_parent() != null else self
	parent.add_child(pixels)
	pixels.global_position = global_position
	for i in BURST_PIXELS:
		var angle := randf() * TAU
		var dir := Vector2.from_angle(angle)
		pixels.add(dir * reach * randf_range(BURST_RING_MIN, BURST_RING_MAX),
				dir * randf_range(BURST_SPEED_MIN, BURST_SPEED_MAX),
				randf_range(BURST_LIFE_MIN, BURST_LIFE_MAX),
				BURST_BIG_SIZE if randf() < BURST_BIG_CHANCE else BURST_PIXEL_SIZE,
				BURST_COLOURS[randi() % BURST_COLOURS.size()])


## Crisp square pixels flying straight out, slowing (BURST_DRAG) and fading over their life.
class _BluePixels extends Node2D:
	var _p: Array = []

	func add(pos: Vector2, vel: Vector2, life: float, size: float, colour: Color) -> void:
		_p.append({"pos": pos, "vel": vel, "life": life, "age": 0.0, "size": size, "colour": colour})

	func _process(delta: float) -> void:
		var alive: Array = []
		var slow := exp(-PokemonEvolution.BURST_DRAG * delta)
		for q in _p:
			q["age"] += delta
			if q["age"] >= q["life"]:
				continue
			q["vel"] *= slow
			q["pos"] += q["vel"] * delta
			alive.append(q)
		_p = alive
		if _p.is_empty():
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		for q in _p:
			var s: float = q["size"]
			var c: Color = q["colour"]
			c.a = 1.0 - pow(float(q["age"]) / float(q["life"]), 2.0)
			var at: Vector2 = (q["pos"] as Vector2).round()
			draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), c)


func _screen_flash() -> void:
	var ui: Node = MapManager._ui_layer
	if ui == null or not is_instance_valid(ui):
		return
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, SCREEN_FLASH_ALPHA)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, SCREEN_FLASH_TIME)
	tw.tween_callback(r.queue_free)
