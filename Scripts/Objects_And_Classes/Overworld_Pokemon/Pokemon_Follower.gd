class_name PokemonFollower
extends OverworldPokemon

## FOLLOWER template (2026-11-24) -- your befriended Pokémon, walking behind you.
## It walks the exact path the player walked (a breadcrumb trail), FOLLOW_DISTANCE
## behind, so it goes round corners and through doors the way you did and never needs
## collision with the walls. Spawned on every map by MapManager.initialise() through
## spawn_for(); the rules (foods, befriending, sending home) are FollowingPokemon.
##
## Space while FACING it (turn round) asks whether to send it home. It never shows a
## talk bubble and always loses to an NPC/opponent/wild Pokémon in range
## (Player_Object_Script._update_active_candidate), so it cannot get in the way.

const GROUP := "follower"

# ---- tweakables -------------------------------------------------------------
## How far behind the player it walks, measured along the path (world px).
const FOLLOW_DISTANCE := 22.0
## A new breadcrumb is dropped every this many world px of player movement.
const CRUMB_SPACING := 2.0
## The player jumping further than this in one frame (a door, a warp, a cutscene
## placing them) drops the trail and puts the follower straight behind them.
const SNAP_DISTANCE := 120.0
## Facing check for Space: how squarely the player must face it (1 = dead on).
const FACE_DOT := 0.6
## ...and how close it must be (world px).
const TALK_DISTANCE := 40.0
## The 4-frame cycle ALWAYS runs (user 2026-11-24: idle cycle while following, like a
## Pokémon standing in the wild). Standing: IDLE_ANIM_SPEED (0.75 = 25% slower than a wild
## Pokémon's idle). Walking: the PLAYER's own walk-cycle speed (_player_anim_speed), so the two
## step in time -- faster with the Options walking speed, faster again running (Shift).
## WALK_ANIM_SPEED multiplies that (1 = exactly the player's rate).
const WALK_ANIM_SPEED := 1.0
const IDLE_ANIM_SPEED := 0.75
## FLYERS (any species whose templates include "flyer") hover just off the ground behind
## you: the art is lifted this many world px, bobbing, over a close shadow at its feet.
const HOVER_HEIGHT := 9.0
const HOVER_BOB_PIXELS := 2.0
const HOVER_BOB_PERIOD := 1.6
## The shadow: a flat translucent black copy of the frame, squashed, at the feet.
const SHADOW_ALPHA := 0.22
const SHADOW_SQUASH := 0.45
const SHADOW_OFFSET := Vector2(0, 6)
const COLLISION_SIZE := Vector2(12, 8)
# -----------------------------------------------------------------------------

var _trail: Array = []          # global points, oldest first, the player's newest last
var _player: Node2D = null
var _flying: bool = false
var _shadow: Sprite2D = null
var _hover_time: float = 0.0


## Puts the saved follower (GameState.get_follower()) on `map_root` behind `player`,
## replacing any follower already there. Null when there is no follower or no art.
static func spawn_for(map_root: Node, player: Node2D, at_global: Variant = null) -> PokemonFollower:
	if map_root == null or player == null:
		return null
	for old in player.get_tree().get_nodes_in_group(GROUP):
		(old as OverworldPokemon).despawn()
	var key := GameState.get_follower()
	if key == "" or not ResourceLoader.exists(OverworldPokemonData.sheet_path(key)):
		return null
	var follower := PokemonFollower.new()
	follower.name = "FOLLOWER"
	follower.configure(key)
	follower.display_name = PokemonHome.name_of(key)   # its nickname, if it has one
	follower.shiny = PokemonHome.is_shiny(key)
	follower._player = player
	map_root.add_child(follower)
	# Before the player in the tree, so at the same z it draws behind them.
	if player.get_parent() == map_root:
		map_root.move_child(follower, player.get_index())
	follower.global_position = at_global if at_global is Vector2 else follower._behind_player()
	follower._reset_trail()
	return follower


func _template_ready() -> void:
	add_to_group(GROUP)
	add_to_group("pokemon")   # the player's interaction area finds it (layer 4)
	z_as_relative = false
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = COLLISION_SIZE * size_scale
	shape.shape = rect
	add_child(shape)
	if _player == null:
		_player = player_node()
	if _player is PhysicsBody2D:
		(_player as PhysicsBody2D).add_collision_exception_with(self)
		add_collision_exception_with(_player)
	animating = true
	anim_speed = IDLE_ANIM_SPEED
	_flying = "flyer" in (species_data.get("templates", []) as Array)
	if _flying:
		_make_shadow()
	if _player != null and "current_direction" in _player:
		set_facing(str(_player.current_direction))
	_update_depth()


func _make_shadow() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = sprite.texture
	_shadow.region_enabled = true
	_shadow.region_filter_clip_enabled = true
	_shadow.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	_shadow.scale = Vector2(sprite.scale.x, sprite.scale.y * SHADOW_SQUASH)
	_shadow.position = SHADOW_OFFSET * size_scale
	_shadow.show_behind_parent = true
	add_child(_shadow)
	move_child(_shadow, 0)


## Hover + shadow, every frame after the frame/facing changed (_apply_region resets
## sprite.position whenever the frame changes).
func _template_process(delta: float) -> void:
	if not _flying or sprite == null:
		return
	_hover_time += delta
	var bob := HOVER_BOB_PIXELS * sin(TAU * _hover_time / HOVER_BOB_PERIOD)
	sprite.position.y = roundf(-HOVER_HEIGHT * size_scale + bob)
	if _shadow != null:
		_shadow.region_rect = sprite.region_rect


func _behind_player() -> Vector2:
	if _player == null:
		return global_position
	var dir: Vector2 = DIR_VECTORS.get(str(_player.get("current_direction")), Vector2.DOWN)
	return _player.global_position - dir * FOLLOW_DISTANCE


func _reset_trail() -> void:
	_trail = [global_position]
	if _player != null:
		_trail.append(_player.global_position)


func _physics_process(_delta: float) -> void:
	if _is_gone or sprite == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = player_node()
		if _player == null:
			return
	var p: Vector2 = _player.global_position
	var last: Vector2 = _trail.back() if not _trail.is_empty() else p
	if p.distance_to(last) > SNAP_DISTANCE:
		global_position = _behind_player()
		_reset_trail()
		_update_depth()
		return
	if p.distance_to(last) >= CRUMB_SPACING:
		_trail.append(p)
	var target := _point_behind(FOLLOW_DISTANCE)
	var step := target - global_position
	if step.length() > 0.05:
		global_position = target
		face_vector(step)
		anim_speed = WALK_ANIM_SPEED * _player_anim_speed()
	else:
		anim_speed = IDLE_ANIM_SPEED
	_update_depth()


## The player's walk animation rate right now. Both play 4-frame cycles at 6 fps x this
## (SpriteSheetLoader / OverworldPokemon.ANIM_FPS), and the player script sets it to
## run x Options walking speed every frame it moves.
func _player_anim_speed() -> float:
	var anim = _player.get("animated_sprite")
	if anim is AnimatedSprite2D:
		return maxf(0.1, (anim as AnimatedSprite2D).speed_scale)
	return 1.0


## The point `distance` back along the trail from the player; trims crumbs behind it.
func _point_behind(distance: float) -> Vector2:
	var p: Vector2 = _player.global_position
	var remaining := distance
	var ahead := p
	var i := _trail.size() - 1
	while i >= 0:
		var crumb: Vector2 = _trail[i]
		var seg := ahead.distance_to(crumb)
		if seg >= remaining:
			# Keep this crumb and everything after it; older ones are walked past.
			if i > 0:
				_trail = _trail.slice(i)
			return ahead.lerp(crumb, remaining / seg) if seg > 0.0 else crumb
		remaining -= seg
		ahead = crumb
		i -= 1
	# Trail shorter than the follow distance (the player has only just moved): stay put.
	return global_position


## In front of the player (lower on screen) it draws over them, behind them under them.
func _update_depth() -> void:
	if _player == null:
		return
	z_index = 1 if global_position.y > _player.global_position.y else 0


# ---- talking ------------------------------------------------------------------

func is_interactable() -> bool:
	if _is_gone or _player == null or not is_instance_valid(_player):
		return false
	var to_me := global_position - _player.global_position
	if to_me.length() > TALK_DISTANCE or to_me.length() < 0.001:
		return false
	var dir: Vector2 = DIR_VECTORS.get(str(_player.get("current_direction")), Vector2.ZERO)
	return dir.dot(to_me.normalized()) >= FACE_DOT


## Never a bubble: it is always next to you, and a bubble on it would only hide the
## one over whoever you actually walked up to.
func show_bubble() -> void:
	pass


func pause_and_face(target_global: Vector2) -> void:
	face_vector(target_global - global_position)


func cry_text() -> String:
	return "%s looks happy to be with you!" % display_name
