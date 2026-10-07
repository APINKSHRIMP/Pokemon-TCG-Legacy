class_name FishShopFloor
extends RefCounted

## The scene half of FISH growing, shared by both floors' map scripts (Fish_Shop.gd,
## Fish_Shop_Downstairs.gd). Call setup() from the map's _scene_setup(), which runs
## BEFORE MapManager spawns the NPCs -- that order matters, because the interiors hold
## the NPCS containers and the NPC lookup must only ever find the one that stays.
##
##   1. Interiors. Every node called Interior_<N> is an expansion that opens at N fish
##      sent (FishShopTanks.interiors_to_keep decides which). The rest are REMOVED from
##      the tree and freed, never hidden -- a hidden TileMap still collides.
##   2. CollisionToRemove. Wherever it is, it goes as soon as any interior above 0 is
##      open on this floor (it walls off the room the first expansion opens into).
##   3. Tanks. Every tank named in Fish_Shop_Tanks.json for the stage in force is filled
##      with the fish sent so far, inside its MOVEMENTZONE* ColorRect, which is hidden.
##   4. With DebugMode on, warnings for anything that does not line up.
##
## Nodes outside every Interior_<N> are permanent: they survive every stage, including
## the 100 overhaul.

const INTERIOR_COLLISION := "CollisionToRemove"
const ZONE_PREFIX := "MOVEMENTZONE"
const FRONT_NAME := "FishTankFront"
## Placement for walkers: tries per Pokémon to find a spot clear of every other walker
## in the tank, then takes the least crowded one.
const PLACE_ATTEMPTS := 24


static func setup(scene: Node, floor_name: String) -> void:
	var removed := _apply_interiors(scene, floor_name)
	_fill_tanks(scene, floor_name)
	if DebugMode.is_enabled():
		_validate(scene, floor_name, removed)


# ============================================================
# INTERIORS
# ============================================================

## Returns the numbers that were removed (for the validator).
static func _apply_interiors(scene: Node, floor_name: String) -> Array:
	var interiors: Dictionary = {}   # number -> Node
	for node in scene.find_children("Interior_*", "", true, false):
		var n := FishShopTanks.interior_number(node.name)
		if n >= 0:
			interiors[n] = node
	var keep := FishShopTanks.interiors_to_keep(floor_name, interiors.keys())
	var removed: Array = []
	for n in interiors:
		if n in keep:
			continue
		removed.append(n)
		_remove(interiors[n])
	var expanded := false
	for n in keep:
		expanded = expanded or int(n) > 0
	if expanded:
		for node in scene.find_children(INTERIOR_COLLISION, "", true, false):
			_remove(node)
	return removed


## Out of the tree NOW (so find_child and the physics server stop seeing it this frame),
## freed at the end of it.
static func _remove(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


# ============================================================
# TANKS
# ============================================================

static func _fill_tanks(scene: Node, floor_name: String) -> void:
	# Every zone is a visual aid for the editor only, whether or not its tank is used.
	for zone in scene.find_children(ZONE_PREFIX + "*", "ColorRect", true, false):
		(zone as CanvasItem).visible = false
	var shown: Dictionary = FishShopTanks.shown_counts().get(floor_name, {})
	for tank_name in shown:
		var rows: Array = shown[tank_name]
		if rows.is_empty():
			continue
		var tank := scene.find_child(tank_name, true, false)
		if tank == null:
			continue
		var zone := _zone_of(tank)
		if zone == null:
			continue
		var front := tank.get_node_or_null(FRONT_NAME) as CanvasItem
		var area := zone.get_global_rect()
		var walkers: Array = []
		var crowded := 0
		for row in rows:
			var species: String = row["species"]
			for i in int(row["count"]):
				var pokemon := _make(species, str(row["pattern"]), tank_name, area, i)
				var spot := area.get_center()
				if pokemon is PokemonTankWalker:
					var found: Array = _walker_spot(pokemon, area, walkers)
					spot = found[0]
					if float(found[1]) < 0.0:
						crowded += 1
					walkers.append({"pos": spot, "radius": _walker_radius(pokemon)})
				else:
					spot = Vector2(randf_range(area.position.x, area.end.x),
							randf_range(area.position.y, area.end.y))
				_place(pokemon, tank, front, spot)
		if crowded > 0 and DebugMode.is_enabled():
			push_warning("FISH (%s): %d of the walkers in %s had to overlap -- its MOVEMENTZONE is too small for that many (make it bigger or lower the max)."
					% [floor_name, crowded, tank_name])


static func _zone_of(tank: Node) -> Control:
	for child in tank.get_children():
		if child is ColorRect and String(child.name).begins_with(ZONE_PREFIX):
			return child
	return null


static func _make(species: String, pattern: String, tank_name: String, area: Rect2,
		index: int) -> OverworldPokemon:
	var pokemon: OverworldPokemon
	if pattern == "fish":
		var fish := PokemonFishTank.new()
		fish.tank_id = tank_name
		fish.tank_region = area
		fish.bumps = false
		pokemon = fish
		pokemon.can_cry = OverworldPokemonData.CRY_TEMPLATES.has(OverworldPokemonData.TANK_TEMPLATE)
	else:
		var walker := PokemonTankWalker.new()
		walker.pattern = pattern
		walker.tank_id = tank_name
		walker.zone = area
		pokemon = walker
		pokemon.can_cry = OverworldPokemonData.CRY_TEMPLATES.has("static")
	pokemon.configure(species)
	# Five Magikarp in a tank are five sizes -- the same five every visit.
	pokemon.size_scale = OverworldPokemonData.tank_fish_scale(species, index)
	return pokemon


## A walker's body radius before it is in the tree -- PokemonTankWalker.body_radius()
## worked out from the species rather than the (not yet ready) node.
static func _walker_radius(walker: PokemonTankWalker) -> float:
	return PokemonTankWalker.art_half_width(walker.species) * OverworldPokemon.SPRITE_SCALE \
			* walker.size_scale * PokemonTankWalker.BODY_RADIUS_FRACTION


static func _cell_of(species: String) -> Vector2:
	var path := OverworldPokemonData.sheet_path(species)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		return Vector2(64, 64)
	return Vector2(tex.get_width() / 4.0, tex.get_height() / 4.0)


## Somewhere in the walker's box that overlaps no walker already placed, else the least
## crowded of the tries -- a tank too small for its count still gets them all, as
## spread out as it can. Returns [spot, clearance]; clearance < 0 means it overlaps.
static func _walker_spot(walker: PokemonTankWalker, area: Rect2, placed: Array) -> Array:
	var bounds := PokemonTankWalker.walk_bounds(area, _cell_of(walker.species),
			OverworldPokemon.SPRITE_SCALE * walker.size_scale)
	var radius := _walker_radius(walker)
	var best := bounds.get_center()
	var best_clearance := -INF
	for attempt in PLACE_ATTEMPTS:
		var candidate := Vector2(randf_range(bounds.position.x, bounds.end.x),
				randf_range(bounds.position.y, bounds.end.y))
		var clearance := INF
		for other in placed:
			clearance = minf(clearance,
					candidate.distance_to(other["pos"]) - radius - float(other["radius"]))
		if clearance >= 0.0:
			return [candidate, clearance]
		if clearance > best_clearance:
			best_clearance = clearance
			best = candidate
	return [best, best_clearance]


## Into the tank: the sibling immediately before its glass, at relative z 0, so the
## scene tree's order puts it behind the glass and over the sand (the same rule
## OverworldPokemonSpawner._place_pokemon follows). Position is set BEFORE add_child --
## every template reads where it is in _template_ready().
static func _place(pokemon: OverworldPokemon, tank: Node, front: CanvasItem, spot: Vector2) -> void:
	var host: Node = front.get_parent() if front != null else tank
	var host_item := host as CanvasItem
	pokemon.position = host_item.get_global_transform().affine_inverse() * spot \
			if host_item != null else spot
	pokemon.z_as_relative = true
	pokemon.z_index = 0
	host.add_child(pokemon)
	if front != null:
		host.move_child(pokemon, front.get_index())


# ============================================================
# DEBUG CHECKS
# ============================================================

## Everything that would make the shop quietly do the wrong thing: a tank list naming a
## tank the scene has not got (or one with no movement zone), a stage list with no
## interior of that number, and an interior with no phone call.
static func _validate(scene: Node, floor_name: String, removed: Array) -> void:
	var interiors := FishShopTanks.scene_interiors(floor_name)
	for n in FishShopTanks.stage_numbers(floor_name):
		if n > 0 and n not in interiors:
			push_warning("FISH (%s): Fish_Shop_Tanks.json has a stage '%d' but the scene has no Interior_%d."
					% [floor_name, n, n])
	for n in interiors:
		if n > 0 and not FishShopCalls.has_call(n):
			push_warning("FISH (%s): Interior_%d opens at %d fish but Phone_Calls.json has no fish_shop_%d_olly / _alexander call."
					% [floor_name, n, n, n])
	var stage := FishShopTanks.active_stage(floor_name)
	if stage < 0:
		return
	var tanks := FishShopTanks.tanks_in_force(floor_name)
	for tank_name in tanks:
		var tank := scene.find_child(tank_name, true, false)
		if tank == null:
			push_warning("FISH (%s): stage %d lists tank %s but no node of that name is open (removed interiors: %s)."
					% [floor_name, stage, tank_name, str(removed)])
		elif _zone_of(tank) == null:
			push_warning("FISH (%s): tank %s has no %s* ColorRect, so nothing is shown in it."
					% [floor_name, tank_name, ZONE_PREFIX])
		elif tank.get_node_or_null(FRONT_NAME) == null:
			push_warning("FISH (%s): tank %s has no %s, so its Pokemon draw over the glass."
					% [floor_name, tank_name, FRONT_NAME])
