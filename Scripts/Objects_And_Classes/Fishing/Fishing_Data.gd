class_name FishingData
extends RefCounted

## Which Pokémon can be hooked where, and at what time of day.
##
## A fishing SPOT is a spawn point like any other -- template `fishing_spot`, placed and
## given its water rectangle with V in the placement tool (DEL -> NEW NPC / OPPONENT /
## POKÉMON -> Fishing spot). It spawns nothing: what it carries is the water and the
## four tables.
##
##   { "id": "fishing_spot_1", "template": "fishing_spot", "at": [-715, 3009],
##     "region": [-1056, 2799, -374, 3218],
##     "tables": { "Morning": { "table": [ {"species": "129_Magikarp", "percent": 60} ] },
##                 "Afternoon": { "table": [] }, "Evening": {...}, "Night": {...} } }
##
## A map may have as many as it likes and they fish differently: a cast uses the spot
## whose water the player is standing in, or failing that the nearest one
## (OverworldPokemonData.nearest_fishing_spot). The Fish_* rects in the map scene still
## say only which way the player faces to cast -- they name no spot and need no edits.
##
## Percentages are WEIGHTS, not probabilities -- the same convention as every other
## table in the spawn file. A cast always rolls exactly one fish, so unlike a spawn point
## there is no `chance` and no `interval`. An empty table means nothing bites at that
## time of day and the player has to reel in by hand.
##
## The six numbers that make up a fish's fight (energy, line strength, recharge time,
## reel step, initial distance, lateral speed) are NOT here: they belong to the species,
## in Overworld_Pokemon.json, so a species fights the same way at every spot and time of
## day. They are edited on the same form and read through OverworldPokemonData.fish_stats().

const FLAG := "has_fishing_rod"

static var _cache: Dictionary = {}


## True when the player owns a rod. Seeded true for new games in
## Player_Data/Player_Game_Progress.json until the rod becomes purchasable.
static func player_has_rod() -> bool:
	return GameState.has_flag(FLAG)


## Every fishing spot on a map, in file order.
static func spots_for(map_data: String) -> Array:
	if _cache.has(map_data):
		return _cache[map_data]
	var spots := OverworldPokemonData.fishing_spots(OverworldPokemonData.load_spawns(map_data))
	_cache[map_data] = spots
	return spots


## The spot a cast from `world_pos` fishes: the one the player is stood in, else the
## nearest. {} when the map has no fishing spots at all.
static func spot_at(map_data: String, world_pos: Vector2) -> Dictionary:
	return OverworldPokemonData.nearest_fishing_spot(spots_for(map_data), world_pos)


## The water a spot's hooked fish fights inside, in world coordinates. An empty Rect2
## for no spot at all, which is what puts the minigame on its own fixed distances.
static func region_of(spot: Dictionary) -> Rect2:
	return OverworldPokemonData.fishing_region(spot) if not spot.is_empty() else Rect2()


## One spot's species rows for the time it is right now.
static func current_table(spot: Dictionary) -> Array:
	var table := OverworldPokemonData.time_table(spot.get("tables"), GameState.get_time())
	var rows = table.get("table", [])
	return rows if rows is Array else []


## One species key rolled off a spot's current table, or "" when nothing is listed. How
## that fish FIGHTS is not here: it belongs to the species, in the registry -- see
## OverworldPokemonData.fish_stats().
static func pick_fish(spot: Dictionary) -> String:
	return str(OverworldPokemonData.pick_row(current_table(spot)).get("species", ""))


## Dropped after the placement tool writes, so the next cast reads the new spots.
static func invalidate() -> void:
	_cache.clear()
