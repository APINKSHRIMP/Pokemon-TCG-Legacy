class_name PokemonBedSpot
extends CharacterBody2D
# NOT a StaticBody2D: the player's InteractionArea (Area2D) never reports a StaticBody2D
# overlap here, so Space never found the spot. A CharacterBody2D that never moves is
# picked up like the follower; the collision exceptions below stop it blocking the player.

## ONE BED SPACE in the bedroom (2026-11-24). Draws whatever bed is in its slot
## (GameState bed_slots, PokemonHome has the rules); the node's position is the bed's
## BOTTOM-CENTRE. Space while standing at it cycles the bed:
##   * debug mode: through EVERY bed in Pokemon_Beds.json, then empty (beds from nowhere).
##   * otherwise:  through this bed and your spare beds, then empty (the old bed goes back
##                 to your spares).
## If the change would leave an INACTIVE Pokémon with no bed, it asks first and Yes dismisses
## it. An empty space shows a dot (with its number) in debug mode only; outside debug an
## empty space with no spare beds to put there is not talkable at all.
## Built by build_all() from the bedroom's _scene_setup; moved with DEL -> "Move bed spots".

const GROUP := "bed_spots"

# ---- tweakables -------------------------------------------------------------
## Drawn above the floor and furniture, below sleepers (PokemonHomeWanderer.RESTING_Z).
const Z := 0
## The body the player's InteractionArea finds it by. It never blocks the player.
const MIN_BODY := Vector2(18, 14)
const DOT_COLOUR := Color(1.0, 0.35, 0.8)
const DOT_RADIUS := 3.0
const HIGHLIGHT_COLOUR := Color(0.3, 0.75, 1.0)
## The bed-name label after a change: seconds on screen, font size (world px).
const TOAST_TIME := 1.4
const TOAST_FONT_SIZE := 8
const PLACEHOLDER_COLOUR := Color(0.45, 0.47, 0.55, 0.85)
# -----------------------------------------------------------------------------

var slot: int = 0
var bed: String = ""
## The debug mover's selection outline.
var highlighted: bool = false:
	set(v):
		highlighted = v
		queue_redraw()

var _sprite: Sprite2D = null
var _shape: CollisionShape2D = null
var _anim_time: float = 0.0
var _frames: int = 1
var _fps: float = 8.0
var _toast: Label = null
var _toast_tween: Tween = null


## Makes the home_slots spots on `map_root`, drawn just under the Player node.
static func build_all(map_root: Node2D) -> Array:
	for old in map_root.get_tree().get_nodes_in_group(GROUP):
		old.queue_free()
	var out: Array = []
	var spots := PokemonHome.bedroom_spots()
	var player := map_root.get_node_or_null("Player")
	for i in spots.size():
		var s := PokemonBedSpot.new()
		s.slot = i
		s.name = "BedSpot%d" % (i + 1)
		s.position = spots[i]
		map_root.add_child(s)
		if player != null:
			map_root.move_child(s, player.get_index())
		out.append(s)
	return out


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 4
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_index = Z
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	add_child(_shape)
	var player := get_tree().get_first_node_in_group("player") as PhysicsBody2D
	if player != null:
		player.add_collision_exception_with(self)
		add_collision_exception_with(player)
	refresh()


## Re-reads this slot's bed and redraws it.
func refresh() -> void:
	bed = str(PokemonHome.slots()[slot]) if slot < PokemonHome.home_slots() else ""
	var size := MIN_BODY
	_frames = 1
	if bed != "":
		var art := PokemonHome.bed_art(bed)
		size = art["size"]
		_frames = int(art["frames"])
		_fps = float(art["fps"])
		_sprite.texture = art["texture"]
		_sprite.visible = _sprite.texture != null
		_sprite.region_enabled = _frames > 1
		_sprite.region_rect = Rect2(Vector2.ZERO, size)
		_sprite.position = Vector2(-floorf(size.x * 0.5), -size.y)
	else:
		_sprite.texture = null
		_sprite.visible = false
	var body := Vector2(maxf(size.x, MIN_BODY.x), maxf(size.y, MIN_BODY.y))
	(_shape.shape as RectangleShape2D).size = body
	_shape.position = Vector2(0, -body.y * 0.5)
	var talkable := bed != "" or DebugMode.is_enabled() or not GameState.get_spare_beds().is_empty()
	if talkable and not is_in_group("bed_spots_talkable"):
		add_to_group("bed_spots_talkable")
	elif not talkable and is_in_group("bed_spots_talkable"):
		remove_from_group("bed_spots_talkable")
	queue_redraw()


## Is this something Space can talk to right now? (Player_Object_Script asks.)
func is_talkable() -> bool:
	return is_in_group("bed_spots_talkable")


func _process(delta: float) -> void:
	if _frames <= 1 or not _sprite.visible:
		return
	_anim_time += delta * _fps
	var f := int(_anim_time) % _frames
	var w := _sprite.region_rect.size.x
	if int(_sprite.region_rect.position.x / maxf(w, 1.0)) != f:
		_sprite.region_rect.position.x = f * w


func _draw() -> void:
	if bed != "" and _sprite.texture == null:
		# No art yet (the tanks until their image is exported): a labelled grey box.
		var size: Vector2 = PokemonHome.bed_art(bed)["size"]
		var r := Rect2(Vector2(-size.x * 0.5, -size.y), size)
		draw_rect(r, PLACEHOLDER_COLOUR)
		draw_rect(r, Color(0.1, 0.1, 0.15), false, 1.0)
		draw_string(ThemeDB.fallback_font, r.position + Vector2(2, 9), bed, HORIZONTAL_ALIGNMENT_LEFT,
				size.x - 4, 7, Color.WHITE)
	if bed == "" and (DebugMode.is_enabled() or highlighted):
		draw_circle(Vector2(0, -DOT_RADIUS), DOT_RADIUS, DOT_COLOUR)
		draw_string(ThemeDB.fallback_font, Vector2(DOT_RADIUS + 1, -1), str(slot + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, DOT_COLOUR)
	if highlighted:
		var body := (_shape.shape as RectangleShape2D).size
		draw_rect(Rect2(Vector2(-body.x * 0.5, -body.y) - Vector2(2, 2), body + Vector2(4, 4)),
				HIGHLIGHT_COLOUR, false, 1.0)


## Where a Pokémon sleeping on this bed puts its feet (global).
func seat_global() -> Vector2:
	if bed == "":
		return global_position
	var size: Vector2 = PokemonHome.bed_art(bed)["size"]
	return global_position + Vector2(0, -size.y + PokemonHome.seat_from_top(bed))


# ---- Space ------------------------------------------------------------------

func interact() -> void:
	if MapManager.message_panel != null and MapManager.message_panel.visible:
		return
	var debug := DebugMode.is_enabled()
	var cycle := PokemonHome.bed_cycle(slot, debug)
	if cycle.size() <= 1 and bed == "":
		MapManager.show_interactable_message("A space for a Pokémon bed. You don't have any beds to put here yet.")
		return
	var i := cycle.find(bed)
	var next := str(cycle[(i + 1) % cycle.size()])
	var homeless := PokemonHome.homeless_after_change(slot, next)
	if homeless.is_empty():
		_apply(next, debug)
		return
	var names := PokemonHome.names_text(homeless)
	MapManager.show_interactable_confirm(("Removing this bed will leave %s without a place to stay so they'll have "
			+ "to leave. Are you sure you want to change this bed and dismiss %s?") % [names, names], func():
		for species_key in homeless:
			PokemonHome.release(str(species_key))
		_apply(next, debug)
		MapManager.show_interactable_message("%s went back to the wild." % names))


func _apply(next: String, debug: bool) -> void:
	PokemonHome.change_bed(slot, next, not debug)
	PokemonHome.refresh_house(get_parent())
	_show_toast(next if next != "" else "(empty)")


func _show_toast(text: String) -> void:
	if _toast == null:
		_toast = Label.new()
		_toast.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
		_toast.add_theme_color_override("font_color", Color.WHITE)
		_toast.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.12))
		_toast.add_theme_constant_override("outline_size", 3)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.z_as_relative = false
		_toast.z_index = 50
		add_child(_toast)
	_toast.text = text
	_toast.reset_size()
	var top := -(_shape.shape as RectangleShape2D).size.y
	_toast.position = Vector2(-_toast.size.x * 0.5, top - _toast.size.y - 2)
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
