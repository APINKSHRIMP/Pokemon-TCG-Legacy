extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

# The bedroom. The player has always lived here, so the house is fully moved in. The
# player's bed is the sleep trigger; what it asks tonight (and what the arrival night
# wakes up to) lives in GameState's ARRIVAL NIGHT section.
# POKÉMON BEDS: PokemonHome.home_slots() bed spaces (PokemonBedSpot) are built here; the
# Pokémon on them are placed by MapManager.initialise -> PokemonHome.refresh_house.

var _player_in_bed_area: bool = true  # starts true to suppress any load-time trigger
const SLEEP_FADE_DURATION := 2.5
## TWEAKABLE -- seconds between the duvet going over and the fade to black starting.
const LIGHTS_OFF_PAUSE := 0.5
## TWEAKABLE -- the sound that plays as the bedroom fades to black. A missing file is skipped.
const BEDTIME_SFX_PATH := "res://Audio/SFX/Goodnight.ogg"
# ISSUE #331: what the bed says before Night, by time slot (Evening is also the fallback).
const BED_TOO_EARLY_TEXT := {
	"Morning":   "I've only just woken up, I'm not getting back in bed now!",
	"Afternoon": "I'd love an afternoon nap... but I'd end up sleeping for hours...",
	"Evening":   "Nothing wrong with an early night but it's far too early to go to sleep now!",
}
const NEXT_MORNING_FONT := "res://UI_Themes/ChakraPetch-Bold.ttf"
## TWEAKABLE -- seconds the follower takes to walk onto its bed when you go to sleep.
const FOLLOWER_TO_BED_TIME := 0.8

# ---- GOING TO BED / WAKING UP (user 2026-11-25) ------------------------------------------
# Lights off -> the player walks to the side of the bed, faces down, hops up onto it in an
# arc, bounces, pauses -> the duvet (bedsheet.png) pops over them up to the neck -> a
# PokemonHome.PLAYER_BED_LEVEL follower hops onto the foot of the bed (no duvet) -> fade.
# Next morning: in bed under the duvet (and the Pokémon at the foot) -> a second after the
# fade-in the duvet goes -> the player shuffles left to the edge, hops off up-and-left
# (turning left at the top of the arc) -> the Pokémon hops off after them and follows again.
# The bed is a Sprite2D now (UPSTAIRS/Bed, Image_Assets/Map_Objects/Player_Bed/bed.png) instead
# of tiles; bedsheet.png is the same picture with only the duvet (rows 30 down).
const BEDSHEET_PATH := "res://Image_Assets/Map_Objects/Player_Bed/bedsheet.png"
## TWEAKABLE -- where the player lies (their centre, map px): head on the pillow, the duvet's
## fold just under the chin.
const IN_BED_POS := Vector2(337, 148)
## TWEAKABLE -- where they stand beside the bed before hopping in (the side nearer them), and
## where they land getting out (always the left).
const BEDSIDE_LEFT := Vector2(309, 150)
const BEDSIDE_RIGHT := Vector2(365, 150)
const GET_OUT_LAND := Vector2(309, 152)
## TWEAKABLE -- the walk to the bedside (px per second).
const BED_WALK_SPEED := 70.0
## TWEAKABLE -- hopping in / out: arc height (px) and time (s).
const BED_HOP_HEIGHT := 7.0
const BED_HOP_TIME := 0.28
## TWEAKABLE -- the bounce on landing in bed: heights (px) and time per half-bounce.
const BED_BOUNCES := [2.0, 1.0]
const BED_BOUNCE_TIME := 0.07
## TWEAKABLE -- the pause in bed before the duvet goes over, and after it before the fade.
const BED_PAUSE := 1.0
const DUVET_TO_FADE_PAUSE := 0.6
## TWEAKABLE -- morning: wait after the fade-in has finished, then the shuffle to the edge
## (steps, px per step, bob px, s per step).
const WAKE_WAIT := 1.0
const SHUFFLE_STEPS := 3
const SHUFFLE_STEP_PX := 3.0
const SHUFFLE_BOB_PX := 1.5
const SHUFFLE_STEP_TIME := 0.16
## TWEAKABLE -- where a PLAYER_BED_LEVEL Pokémon sleeps: the bed's foot (its feet, map px),
## its hop height and time.
const BED_FOOT := Vector2(337, 182)
const POKEMON_BED_HOP_HEIGHT := 9.0
const POKEMON_BED_HOP_TIME := 0.32
## The overlay fade BaseMapScene plays when you wake (keep in step with its 1.5s tween).
const WAKE_OVERLAY_FADE := 1.5

## Set while the going-to-bed / getting-up scene runs (it blocks the bed trigger).
var _going_to_bed := false
## Across the scene reload: the morning starts in bed.
static var _wake_in_bed := false
var _bedsheet: Sprite2D = null

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_PLAYER_HOME_DAY
func get_evening_bgm_path() -> String: return SoundManagerScript.BGM_PLAYER_HOME_NIGHT

func _scene_setup():
	_apply_moved_in_state()
	PokemonBedSpot.build_all(self)
	_make_bedsheet()
	if _wake_in_bed:
		_wake_in_bed = false
		if _bedsheet != null:
			_bedsheet.visible = true
		_wake_up.call_deferred()

	var interactables := $Interactables as Area2D
	interactables.collision_mask = 2
	interactables.monitoring     = true
	interactables.monitorable    = true
	interactables.body_entered.connect(_on_bed_body_entered)
	interactables.body_exited.connect(_on_bed_body_exited)
	_init_bed_overlap_state()

# The scene still holds the old "Moving In" layer and its box collisions; the player
# lives here already, so only the furnished "Post Move In" set is ever shown. The
# unused collision set is REMOVED, not hidden: hiding a StaticBody2D via a parent
# Control does not stop it colliding. SceneCache re-instantiates the scene fresh on
# every visit, so queue_free() here is safe.
func _apply_moved_in_state() -> void:
	var moving_in_layer := $UPSTAIRS.get_node_or_null("Moving In")
	if moving_in_layer != null:
		moving_in_layer.visible = false
	var post_move_in_visual := $UPSTAIRS.get_node_or_null("Post Move In")
	if post_move_in_visual != null:
		post_move_in_visual.visible = true

	var col := get_node_or_null("Collision Objects")
	if col != null:
		var col_moving := col.get_node_or_null("Moving In")
		if col_moving != null:
			col_moving.queue_free()

func _init_bed_overlap_state() -> void:
	# Wait a few physics frames for overlap detection to settle, then check
	# whether the player is actually inside. If not, clear the suppression flag
	# so normal entry works. If they are inside, they must exit and re-enter.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var player_inside := false
	for body in ($Interactables as Area2D).get_overlapping_bodies():
		if body.is_in_group("player"):
			player_inside = true
			break
	if not player_inside:
		_player_in_bed_area = false

func _on_bed_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_bed_area = false

func _on_bed_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _player_in_bed_area or _going_to_bed:
		return
	if MapManager.message_panel != null and MapManager.message_panel.visible:
		return
	if GameState.is_night_time():
		# POKÉMON AT HOME: a follower with no bed blocks this until it is settled.
		MapManager.confirm_sleep(_do_sleep)
	else:
		MapManager.show_interactable_message(BED_TOO_EARLY_TEXT.get(GameState.get_time(), BED_TOO_EARLY_TEXT["Evening"]))

func _do_sleep() -> void:
	if _going_to_bed:
		return
	_going_to_bed = true
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()
	var scene_path := get_scene_path()
	GameState.going_to_bed = true   # no clock until the player wakes up
	# AFFECTION: everyone is paid their hours up to bedtime; the night they sleep through does
	# not count, but a night in a bed is worth GAIN_PER_NIGHT_IN_BED.
	PokemonAffection.credit_hours()
	PokemonCare.credit_hunger()   # HUNGER (and being ignored) stop for the night too
	PokemonAffection.credit_night_in_bed()
	var on_my_bed := PokemonHome.sleeps_on_player_bed(GameState.get_follower())
	# ISSUE #489: the bedroom music stops DEAD (no fade) and the goodnight sound plays on its own; the
	# new day's track starts once "The next morning..." has gone (BaseMapScene._ready, WAKE_BGM_FADE_IN).
	print("ISSUE #489 FIX ACTIVE: bedroom BGM stopped at once for the goodnight sound")
	SoundManagerScript.stop_bgm()
	if ResourceLoader.exists(BEDTIME_SFX_PATH):
		SoundManagerScript.play_sfx_from_path(BEDTIME_SFX_PATH)
	# Lights out first: every lamp in the room goes off.
	for light in find_children("*", "PointLight2D", true, false):
		(light as PointLight2D).visible = false
	# Your follower goes to its bed space (everyone without one left at confirm_sleep) - unless
	# it sleeps on yours, when it hops up after you.
	PokemonHome.tuck_in_follower(self, FOLLOWER_TO_BED_TIME)
	await _get_into_bed()
	if on_my_bed:
		var follower := _follower_node()
		if follower != null:
			follower.set_physics_process(false)
			await _pokemon_hop(follower, _bed_foot_target(follower), true)
	await get_tree().create_timer(DUVET_TO_FADE_PAUSE).timeout
	if not is_inside_tree():
		return
	GameState.save_menu_return_state(scene_path, IN_BED_POS, "down")
	GameState.sleep_until_next_day()
	PokemonAffection.start_all_clocks()
	PokemonCare.restart_hunger_clocks()
	GameState.sleep_wakeup_fade = true
	_wake_in_bed = true
	var tween := create_tween()
	tween.tween_interval(LIGHTS_OFF_PAUSE)
	tween.tween_property(self, "modulate", Color.BLACK, SLEEP_FADE_DURATION)
	tween.tween_callback(SoundManagerScript.stop_bgm)
	tween.tween_callback(_show_next_morning_label.bind(scene_path))


# ---- going to bed / waking up ---------------------------------------------------------

func _make_bedsheet() -> void:
	var bed := get_node_or_null("UPSTAIRS/Bed") as Sprite2D
	if bed == null or not ResourceLoader.exists(BEDSHEET_PATH):
		return
	_bedsheet = Sprite2D.new()
	_bedsheet.name = "Bedsheet"
	_bedsheet.texture = load(BEDSHEET_PATH)
	_bedsheet.centered = false
	_bedsheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bedsheet.z_index = 1          # over the player (z 0)
	_bedsheet.visible = false
	add_child(_bedsheet)
	_bedsheet.global_position = bed.global_position


func _follower_node() -> PokemonFollower:
	return get_tree().get_first_node_in_group(PokemonFollower.GROUP) as PokemonFollower


## The bed's foot (feet go here), global: PokemonHome.refresh_house puts a PLAYER_BED_LEVEL
## Pokémon living at home here while it sleeps.
func bed_foot_global() -> Vector2:
	return to_global(BED_FOOT)


## Where a Pokémon's centre goes so its feet sit on the bed's foot.
func _bed_foot_target(pokemon: OverworldPokemon) -> Vector2:
	return to_global(BED_FOOT) - Vector2(0, (pokemon.art_bottom + 1 - pokemon.cell.y * 0.5) * pokemon.draw_scale())


func _walk_player_to(target: Vector2) -> void:
	var offset: Vector2 = target - _player.position
	if offset.length() < 0.5:
		return
	var dir := ""
	if absf(offset.x) > absf(offset.y):
		dir = "right" if offset.x > 0.0 else "left"
	else:
		dir = "down" if offset.y > 0.0 else "up"
	_player.current_direction = dir
	_player.animated_sprite.play("walk_" + dir)
	var tw := create_tween()
	tw.tween_property(_player, "position", target, offset.length() / BED_WALK_SPEED)
	await tw.finished
	if is_instance_valid(_player):
		_player.animated_sprite.play("idle_" + dir)


## An arc from where `node` is to `to` (its parent's space), `height` px up at the middle.
## `face_at_top` (the player only): turns them that way at the top of the arc.
func _arc(node: Node2D, to: Vector2, height: float, time: float, face_at_top: String = "") -> void:
	var from := node.position
	var turned := [false]
	var step := func(t: float) -> void:
		if not is_instance_valid(node):
			return
		node.position = from.lerp(to, t) + Vector2(0, -sin(PI * t) * height)
		if face_at_top != "" and t >= 0.5 and not turned[0]:
			turned[0] = true
			_player.set_direction(face_at_top)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, time)
	await tw.finished


func _bounce(node: Node2D, heights: Array, half_time: float) -> void:
	var base := node.position
	var tw := create_tween()
	for h in heights:
		tw.tween_property(node, "position:y", base.y - float(h), half_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "position:y", base.y, half_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _get_into_bed() -> void:
	if _player == null:
		return
	# Beside the bed, on the side nearer them; across first if they're standing on it.
	var side := BEDSIDE_LEFT if _player.position.x <= IN_BED_POS.x else BEDSIDE_RIGHT
	if absf(_player.position.x - side.x) > 1.0:
		await _walk_player_to(Vector2(side.x, _player.position.y))
	await _walk_player_to(side)
	_player.set_direction("down")
	await get_tree().create_timer(0.15).timeout
	await _arc(_player, IN_BED_POS, BED_HOP_HEIGHT, BED_HOP_TIME)
	await _bounce(_player, BED_BOUNCES, BED_BOUNCE_TIME)
	await get_tree().create_timer(BED_PAUSE).timeout
	if _bedsheet != null:
		_bedsheet.visible = true


## A Pokémon hops onto (on_bed) or off the bed, in its own arc.
func _pokemon_hop(pokemon: OverworldPokemon, to_global: Vector2, on_bed: bool) -> void:
	if pokemon == null or not is_instance_valid(pokemon):
		return
	pokemon.face_vector(to_global - pokemon.global_position)
	pokemon.z_as_relative = false
	pokemon.z_index = 2 if on_bed else 1
	var from := pokemon.global_position
	var step := func(t: float) -> void:
		if is_instance_valid(pokemon):
			pokemon.global_position = from.lerp(to_global, t) + Vector2(0, -sin(PI * t) * POKEMON_BED_HOP_HEIGHT)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, POKEMON_BED_HOP_TIME)
	await tw.finished
	if on_bed and is_instance_valid(pokemon):
		pokemon.set_facing("down")


## The morning: in bed under the duvet, a PLAYER_BED_LEVEL follower at the foot.
func _wake_up() -> void:
	if _player == null:
		return
	_going_to_bed = true   # the bed trigger stays quiet while they get out
	_player.lock_movement()
	_player.position = IN_BED_POS
	_player.set_direction("down")
	await get_tree().process_frame   # MapManager has placed the follower by now
	var follower := _follower_node()
	var on_bed := follower != null and PokemonHome.sleeps_on_player_bed(PokemonHome.id_of(follower))
	if follower != null:
		follower.set_physics_process(false)
		if on_bed:
			follower.z_as_relative = false
			follower.z_index = 2
			follower.global_position = _bed_foot_target(follower)
			follower.set_facing("down")
	await get_tree().create_timer(WAKE_OVERLAY_FADE + WAKE_WAIT).timeout
	if not is_inside_tree() or not is_instance_valid(_player):
		return
	if _bedsheet != null:
		_bedsheet.visible = false
	# Shuffle to the left edge, a little bob each step.
	_player.set_direction("left")
	for _k in SHUFFLE_STEPS:
		var base: Vector2 = _player.position
		var tw := create_tween()
		tw.tween_property(_player, "position", base + Vector2(-SHUFFLE_STEP_PX * 0.5, -SHUFFLE_BOB_PX), SHUFFLE_STEP_TIME * 0.5)
		tw.tween_property(_player, "position", base + Vector2(-SHUFFLE_STEP_PX, 0), SHUFFLE_STEP_TIME * 0.5)
		await tw.finished
	_player.set_direction("down")
	# Hop off, up and to the left, turning left at the top.
	await _arc(_player, GET_OUT_LAND, BED_HOP_HEIGHT, BED_HOP_TIME, "left")
	if not is_instance_valid(_player):
		return
	_player.set_direction("left")
	if follower != null and is_instance_valid(follower):
		if on_bed:
			await get_tree().create_timer(0.2).timeout
			await _pokemon_hop(follower, _player.global_position + Vector2(PokemonFollower.FOLLOW_DISTANCE, 0), false)
		follower._reset_trail()
		follower.set_physics_process(true)
	_going_to_bed = false
	if is_instance_valid(_player):
		_player.unlock_movement()


func _show_next_morning_label(scene_path: String) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var label := Label.new()
	# The arrival night of "I know the rules a bit" sleeps in to the afternoon.
	label.text = "The next afternoon..." if GameState.get_time() == "Afternoon" else "The next morning..."
	label.add_theme_font_override("font", load(NEXT_MORNING_FONT))
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = vp_size
	label.position = Vector2.ZERO
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_ui_layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 0.5)
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.5)
	tween.tween_callback(func(): SceneCache.change_scene(scene_path))
