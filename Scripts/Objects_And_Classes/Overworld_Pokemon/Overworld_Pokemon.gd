class_name OverworldPokemon
extends CharacterBody2D

## Base for every overworld Pokémon template. Owns the sprite sheet and nothing
## else: which cell is showing, which way it faces, the row-by-row clip the
## burying/surfacing templates rise through, and the talk bubble. Behaviour lives
## in the template subclasses, which override _template_ready / _template_process.
##
## Sheets are the same 4x4 layout as the NPC sheets -- rows down, left, right, up;
## four frames each -- so a 256px sheet is 64px cells, drawn at SPRITE_SCALE like
## every NPC. The cell size is derived from the sheet, never assumed (Caterpie is
## 192px, Palossand 512px).
##
## Extends CharacterBody2D so the skittish and static templates get move_and_slide()
## and the player's InteractionArea can see them. Templates without collision leave
## both layers at 0 and never move through physics.

signal gone(pokemon: OverworldPokemon)

# ---- tweakables -------------------------------------------------------------
## Same scale NPC sprites are drawn at (WorldObjectBase).
const SPRITE_SCALE := 0.5
## Walk-cycle frames per second at anim_speed 1.0 (SpriteSheetLoader uses 6).
const ANIM_FPS := 6.0
const BUBBLE_Y_OFFSET := -19.0
## Cries. Once a Pokémon has been on screen for CRY_INTERVAL seconds it rolls
## CRY_CHANCE% every CRY_INTERVAL seconds to cry; leaving the screen resets its timer.
## Each Pokémon rolls on its own, so five Wingull on screen are five times as likely to
## be heard. A cry that fires while another is playing is dropped, never queued (see
## SoundManagerScript.play_cry). Which templates cry: OverworldPokemonData.CRY_TEMPLATES
## -- all of them, so a Caterpie in a tree is as likely to be heard as a bird overhead.
const CRY_INTERVAL := 2.0
const CRY_CHANCE := 5.0
# -----------------------------------------------------------------------------

const ROWS := {"down": 0, "left": 1, "right": 2, "up": 3}
const DIRECTIONS := ["down", "left", "right", "up"]
const DIR_VECTORS := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}

var species: String = ""
var display_name: String = ""
## The registry entry for this species (spin, particle_colour, up_time, ...).
var species_data: Dictionary = {}
## The spawn point that produced this Pokémon; {} for flyers.
var spawn_point: Dictionary = {}
## Size multiplier on top of SPRITE_SCALE -- 1.0 is normal, 10 is a Wailord the size
## of a house. Set by the spawner from the table row before add_child(). (Not
## `scale`: that is Node2D's own transform.)
var size_scale: float = 1.0
## Set by the spawner from OverworldPokemonData.CRY_TEMPLATES before add_child().
var can_cry: bool = false
var _cry_time: float = 0.0

var sprite: Sprite2D = null
var facing: String = "down"
## false shows column 0 of the facing row and holds it.
var animating: bool = true
var anim_speed: float = 1.0
## -1 draws the whole cell centred on the origin. >= 0 draws only the top
## `clip_rows` rows of the opaque art, with the bottom of what is drawn sitting on
## local y = 0 -- the ground / waterline the burying and surfacing templates rise
## out of.
var clip_rows: int = -1

var cell: Vector2 = Vector2(64, 64)
## First and last opaque row of the art inside a cell, unioned over all 16 frames so
## the rise does not jitter as the walk cycle changes frame.
var art_top: int = 0
var art_bottom: int = 63

var _frame: int = 0
var _anim_time: float = 0.0
var _bubble: Sprite2D = null
var _is_gone: bool = false

static var _art_rows_cache: Dictionary = {}


## Called by the spawner before add_child().
func configure(species_key: String, point: Dictionary = {}) -> void:
	species = species_key
	spawn_point = point
	species_data = OverworldPokemonData.species_info(species_key)
	display_name = OverworldPokemonData.display_name(species_key)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	sprite = Sprite2D.new()
	sprite.scale = Vector2(draw_scale(), draw_scale())
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	var path := OverworldPokemonData.sheet_path(species)
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if texture == null:
		push_error("OverworldPokemon: no sprite sheet at " + path)
		sprite.free()
		sprite = null
		despawn()
		return
	sprite.texture = texture
	cell = Vector2(texture.get_width() / 4.0, texture.get_height() / 4.0)
	var rows := art_rows(texture, path)
	art_top = rows.x
	art_bottom = rows.y
	add_child(sprite)
	_template_ready()
	_apply_region()
	# The handful of species that carry a light get one here, so a firefly glows whatever
	# template it is spawned under. It follows the SPRITE, not the node, so a flyer's bob
	# and a swinging bug's swing carry it. PokemonGlow returns null for everything else.
	if glow_on_spawn():
		PokemonGlow.attach(self, sprite, species, self)


## False while a template wants to light its own Pokémon later than spawn -- the
## surfacing one, which is under water to start with and lights up as it breaks through.
func glow_on_spawn() -> bool:
	return true


func _process(delta: float) -> void:
	if _is_gone:
		return
	if animating:
		_anim_time += delta * ANIM_FPS * anim_speed
		var next := int(_anim_time) % 4
		if next != _frame:
			_frame = next
			_apply_region()
	_template_process(delta)
	_update_cry(delta)


## On screen for CRY_INTERVAL seconds -> a CRY_CHANCE% roll, then another every
## CRY_INTERVAL seconds while it stays on screen. "On screen" is the camera's view.
func _update_cry(delta: float) -> void:
	if not can_cry or _is_gone:
		return
	# Underground or below the waterline: drawn but not showing, so not heard either.
	if sprite == null or not sprite.visible:
		_cry_time = 0.0
		return
	if not view_rect().has_point(global_position):
		_cry_time = 0.0
		return
	_cry_time += delta
	if _cry_time < CRY_INTERVAL:
		return
	_cry_time -= CRY_INTERVAL
	if randf() * 100.0 < CRY_CHANCE:
		SoundManagerScript.play_cry(species)


# ---- template hooks ---------------------------------------------------------

func _template_ready() -> void:
	pass


func _template_process(_delta: float) -> void:
	pass


# ---- drawing ----------------------------------------------------------------

func set_facing(dir: String) -> void:
	if not ROWS.has(dir) or dir == facing:
		return
	facing = dir
	_apply_region()


func set_clip_rows(rows: int) -> void:
	if rows == clip_rows:
		return
	clip_rows = rows
	_apply_region()


## World pixels per sheet pixel: the NPC scale times this Pokémon's size_scale.
## Everything that places art, particles or collision in world space goes through it.
func draw_scale() -> float:
	return SPRITE_SCALE * size_scale


func art_height() -> int:
	return art_bottom - art_top + 1


func _apply_region() -> void:
	if sprite == null:
		return
	var col := _frame if animating else 0
	var row: int = ROWS.get(facing, 0)
	var origin := Vector2(col * cell.x, row * cell.y)
	if clip_rows < 0:
		sprite.visible = true
		sprite.centered = true
		sprite.position = Vector2.ZERO
		sprite.region_rect = Rect2(origin, cell)
		return
	var k: int = clampi(clip_rows, 0, art_height())
	sprite.visible = k > 0
	sprite.centered = false
	sprite.region_rect = Rect2(origin.x, origin.y + art_top, cell.x, maxi(k, 1))
	sprite.position = Vector2(-cell.x * draw_scale() * 0.5, -k * draw_scale())
	_on_region_applied(origin, k)


## Surfacing hooks this to keep its tint shader's waterline on the current frame.
func _on_region_applied(_cell_origin: Vector2, _rows_shown: int) -> void:
	pass


## The opaque row span of a sheet's cells, cached per sheet.
static func art_rows(texture: Texture2D, key: String) -> Vector2i:
	if _art_rows_cache.has(key):
		return _art_rows_cache[key]
	var result := Vector2i(0, int(texture.get_height() / 4.0) - 1)
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var cw := int(image.get_width() / 4.0)
		var ch := int(image.get_height() / 4.0)
		var top := ch
		var bottom := -1
		for r in 4:
			for c in 4:
				var used := image.get_region(Rect2i(c * cw, r * ch, cw, ch)).get_used_rect()
				if used.size.y <= 0:
					continue
				top = mini(top, used.position.y)
				bottom = maxi(bottom, used.position.y + used.size.y - 1)
		if bottom >= top:
			result = Vector2i(top, bottom)
	_art_rows_cache[key] = result
	return result


# ---- helpers the templates share --------------------------------------------

func face_vector(v: Vector2) -> void:
	if v.length() < 0.001:
		return
	if absf(v.x) > absf(v.y):
		set_facing("right" if v.x > 0 else "left")
	else:
		set_facing("down" if v.y > 0 else "up")


func player_node() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## The part of the world the camera is showing right now, in global coordinates.
func view_rect() -> Rect2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	return vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, size)


func particle_colour(fallback: Color) -> Color:
	var hex := str(species_data.get("particle_colour", ""))
	if hex != "" and Color.html_is_valid(hex):
		return Color.html(hex)
	return fallback


## Leave the world. Safe to call twice.
func despawn() -> void:
	if _is_gone:
		return
	_is_gone = true
	hide_bubble()
	if is_in_group("pokemon"):
		remove_from_group("pokemon")
	gone.emit(self)
	queue_free()


# ---- interaction (skittish / static) ------------------------------------------

func is_interactable() -> bool:
	return false


## What the message box says when the player presses Space.
func cry_text() -> String:
	return display_name + "!"


func show_bubble() -> void:
	if not is_interactable():
		return
	if _bubble == null:
		_bubble = Sprite2D.new()
		_bubble.texture = load("res://Image_Assets/Icons/Message_Icons/new_talk.png")
		_bubble.position = Vector2(0, BUBBLE_Y_OFFSET * size_scale)
		_bubble.z_index = 100
		add_child(_bubble)
	_bubble.visible = true


func hide_bubble() -> void:
	if _bubble != null:
		_bubble.visible = false


func refresh_bubble() -> void:
	pass


## MapManager calls these around the "Rattata!" message, same names as WorldObjectBase.
func pause_and_face(target_global: Vector2) -> void:
	face_vector(target_global - global_position)


func resume_movement() -> void:
	pass
