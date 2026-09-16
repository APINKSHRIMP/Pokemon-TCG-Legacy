class_name FishingData
extends RefCounted

## Which Pokémon can be hooked on a given map at a given time of day.
##
## Stored as a `fishing` block in the map's existing spawn file rather than a file of its
## own, so the placement tool's writer round-trips it for free:
##
##   "fishing": {
##     "Morning": { "table": [ {"species": "129_Magikarp", "percent": 60}, ... ] },
##     "Afternoon": { "table": [] }, "Evening": { "table": [] }, "Night": { "table": [] }
##   }
##
## Percentages are WEIGHTS, not probabilities -- the same convention as every other
## table in the spawn file. A cast always rolls exactly one fish, so unlike a spawn point
## there is no `chance` and no `interval`. An empty table means nothing bites at that
## time of day and the player has to reel in by hand.

const FLAG := "has_fishing_rod"

static var _cache: Dictionary = {}


## True when the player owns a rod. Seeded true for new games in
## Player_Data/Player_Game_Progress.json until the rod becomes purchasable.
static func player_has_rod() -> bool:
	return GameState.has_flag(FLAG)


## The four time-of-day tables for a map.
static func tables_for(map_data: String) -> Dictionary:
	if _cache.has(map_data):
		return _cache[map_data]
	var doc := OverworldPokemonData.load_spawns(map_data)
	var tables: Dictionary = OverworldPokemonData.normalise_fishing(doc.get("fishing"))
	_cache[map_data] = tables
	return tables


## The species rows in play right now.
static func current_table(map_data: String) -> Array:
	var table := OverworldPokemonData.time_table(tables_for(map_data), GameState.get_time())
	var rows = table.get("table", [])
	return rows if rows is Array else []


## One species key rolled off the current table, or "" when nothing is listed.
static func pick_fish(map_data: String) -> String:
	return str(OverworldPokemonData.pick_row(current_table(map_data)).get("species", ""))


## Dropped after the placement tool writes, so the next cast reads the new table.
static func invalidate() -> void:
	_cache.clear()
