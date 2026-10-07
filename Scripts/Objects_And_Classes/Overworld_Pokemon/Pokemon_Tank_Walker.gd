class_name PokemonTankWalker
extends OverworldPokemon

## A land Pokémon in one of the FISH shop's tanks (FishShopFloor puts them out from
## Fish_Shop_Tanks.json). Two patterns:
##
##   idle_random  stands where it was put and looks a random way every few seconds.
##   wander       like an NPC's random wander but much smaller and lazier: now and then
##                (about as often as a bug in a tree shuffles) it takes a short, slow
##                walk up, down, left or right, then stands and glances about again.
##
## Both stay inside their tank's movement zone and never overlap another walker in the
## same tank: one that would walk into the zone's edge or into a neighbour turns round
## and walks back the other way instead. (Fish are PokemonFishTank and swim through
## each other; only walkers keep their distance.)
##
## Drawing is the tank's business: FishShopFloor parents this node one place before the
## tank's FishTankFront at relative z 0, exactly as the spawner does for any tanked
## Pokémon, so it is behind the glass and in front of the sand.

# ---- tweakables -------------------------------------------------------------
## Seconds between glances in a new random direction while standing.
const LOOK_MIN := 1.5
const LOOK_MAX := 4.0
## wander: seconds stood still between walks.
const WALK_PAUSE_MIN := 3.0
const WALK_PAUSE_MAX := 8.0
## wander: how far one walk goes, world px, and how fast (world px/s).
const WALK_DISTANCE_MIN := 3.0
const WALK_DISTANCE_MAX := 10.0
const WALK_SPEED := 6.0
## Walk-cycle speed while walking (1.0 = an NPC's).
const WALK_ANIM_SPEED := 0.6
## How much of this Pokémon's half-WIDTH (its widest opaque frame, measured off the
## sheet) counts as its body for not overlapping a neighbour: two walkers touch when
## their centres are closer than the sum of these. 1.0 = art edge to art edge; lower
## lets them stand a little closer.
const BODY_RADIUS_FRACTION := 0.8
## How much of a cell is kept inside the zone's edge -- the same idea and the same
## numbers as PokemonFishTank's EDGE_MARGIN_*, so a tank's art never pokes out of its
## zone, but a tiny zone still leaves at least a fifth of itself to walk in.
const EDGE_MARGIN_FRACTION := 0.3
const EDGE_MARGIN_LIMIT := 0.4
# -----------------------------------------------------------------------------

## Set by FishShopFloor before add_child().
var pattern: String = "wander"
var tank_id: String = ""
var zone: Rect2 = Rect2()

## The rectangle this walker's CENTRE stays inside.
var _bounds: Rect2 = Rect2()
var _look_timer: float = 0.0
var _walk_timer: float = 0.0
var _walking: bool = false
var _walk_dir: Vector2 = Vector2.ZERO
var _walk_left: float = 0.0
## A walk that has already turned round once and is blocked again just stops.
var _turned: bool = false


func _template_ready() -> void:
	animating = false
	anim_speed = WALK_ANIM_SPEED
	_bounds = walk_bounds(zone, cell, draw_scale())
	global_position = _clamp(global_position)
	set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])
	_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
	# Staggered so a tankful does not all set off on the same frame.
	_walk_timer = randf_range(0.0, WALK_PAUSE_MAX)


## The box a walker's centre may move in: `zone` pulled in by its own size, the margin
## never eating more than EDGE_MARGIN_LIMIT of the zone. Static so FishShopFloor can
## place walkers inside the same box before they exist.
static func walk_bounds(area: Rect2, cell_size: Vector2, art_scale: float) -> Rect2:
	var margin := cell_size * art_scale * EDGE_MARGIN_FRACTION
	margin.x = minf(margin.x, area.size.x * EDGE_MARGIN_LIMIT)
	margin.y = minf(margin.y, area.size.y * EDGE_MARGIN_LIMIT)
	return Rect2(area.position + margin, area.size - margin * 2.0)


func body_radius() -> float:
	return art_half_width(species) * draw_scale() * BODY_RADIUS_FRACTION


static var _half_width_cache: Dictionary = {}

## Half the width, in the sheet's own pixels, of the species' widest opaque frame --
## a Krabby is far narrower than its 64 px cell. Cached per species.
static func art_half_width(species_key: String) -> float:
	if _half_width_cache.has(species_key):
		return _half_width_cache[species_key]
	var half := 16.0
	var path := OverworldPokemonData.sheet_path(species_key)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var image := tex.get_image() if tex != null else null
	if image != null:
		if image.is_compressed():
			image.decompress()
		var cw := int(image.get_width() / 4.0)
		var ch := int(image.get_height() / 4.0)
		var widest := 0
		for r in 4:
			for c in 4:
				widest = maxi(widest, image.get_region(Rect2i(c * cw, r * ch, cw, ch)).get_used_rect().size.x)
		if widest > 0:
			half = widest * 0.5
	_half_width_cache[species_key] = half
	return half


func _clamp(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, _bounds.position.x, _bounds.end.x),
			clampf(pos.y, _bounds.position.y, _bounds.end.y))


func _template_process(delta: float) -> void:
	if _walking:
		_process_walk(delta)
		return

	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
		set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])

	if pattern != "wander":
		return
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		_walk_timer = randf_range(WALK_PAUSE_MIN, WALK_PAUSE_MAX)
		var dir: String = DIRECTIONS[randi() % DIRECTIONS.size()]
		_start_walk(DIR_VECTORS[dir], randf_range(WALK_DISTANCE_MIN, WALK_DISTANCE_MAX))


func _start_walk(dir: Vector2, distance: float) -> void:
	_walk_dir = dir
	_walk_left = distance
	_walking = true
	_turned = false
	animating = true
	face_vector(dir)
	_apply_region()


func _process_walk(delta: float) -> void:
	var step := minf(WALK_SPEED * delta, _walk_left)
	var next := global_position + _walk_dir * step
	if _blocked(next):
		if _turned:
			_stop_walk()
			return
		# Bumped the edge or a neighbour: turn round and walk back the same distance.
		_turned = true
		_walk_dir = -_walk_dir
		face_vector(_walk_dir)
		_apply_region()
		return
	global_position = next
	_walk_left -= step
	if _walk_left <= 0.0:
		_stop_walk()


func _stop_walk() -> void:
	_walking = false
	animating = false
	_apply_region()


## True when `pos` is outside the zone or would overlap another walker of this tank.
func _blocked(pos: Vector2) -> bool:
	if _clamp(pos) != pos:
		return true
	var parent := get_parent()
	if parent == null:
		return false
	for other in parent.get_children():
		if other == self or not (other is PokemonTankWalker):
			continue
		var walker: PokemonTankWalker = other
		if walker.tank_id != tank_id:
			continue
		var gap := body_radius() + walker.body_radius()
		# Only a move that brings them CLOSER counts, so two that start touching can
		# still walk apart.
		var now := global_position.distance_to(walker.global_position)
		var then := pos.distance_to(walker.global_position)
		if then < gap and then < now:
			return true
	return false
