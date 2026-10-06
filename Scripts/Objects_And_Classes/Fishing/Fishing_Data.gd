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


## One row rolled off a spot's current table -- {species, percent} -- or {} when nothing
## is listed. The row and not just the species, because its `percent` is the fish's
## rarity on THIS table and feeds its Fish Coin reward. How the fish FIGHTS is not here:
## it belongs to the species, in the registry -- see OverworldPokemonData.fish_stats().
static func pick_fish_row(spot: Dictionary) -> Dictionary:
	var row = OverworldPokemonData.pick_row(current_table(spot))
	return row if row is Dictionary else {}


# ============================================================
# FISH COINS
# ============================================================
# Every landed fish pays out Fish Coins, scaled by how rare it is and how hard it is to
# land. The formula is the one in Spreadsheets/Fish_Export.xlsx (columns S..AC) -- keep
# the two in step. Every term reads a fish stat from the registry, plus the row's rate:
#
#   rarity      200 - rate * 4             commoner fish pay less (can go negative)
#   big         +150 if a big silhouette
#   size        100 * fish_size            the species' size, NOT the per-catch roll
#   line        200 / (line_strength/100)^2   a weak line is harder to keep
#   rest        200 / recharge_time        short rests = short reel windows
#   reel        20 / reel_step^2 * 100     small reel steps = more reeling
#   run         initial_distance / 2
#   speed       lateral_speed / 2
#   energy      energy / 2
#
#   coins = round(sum / FISH_COIN_DIVISOR * size_roll * multiplier), at least 1.
#
# `size_roll` is the same 0.8..1.2 the minigame drew the fish at, so a big one of its
# kind is worth more. Magikarp at rate 35 lands ~27-40, Wailord ~110-165.

## TWEAKABLE. The spreadsheet's AC column divides by 10.
const FISH_COIN_DIVISOR := 10.0
const FISH_COIN_BIG_BONUS := 150.0
## Per-catch size roll -- the fish is drawn this much bigger or smaller than its species'
## fish_size, and its reward scales by the same factor.
const FISH_SIZE_ROLL_MIN := 0.8
const FISH_SIZE_ROLL_MAX := 1.2
## Reward multiplier once that species' fish tank is full and the catch goes back in the
## water instead. Not wired up yet -- the tanks come next; pass tank_full when they do.
const FISH_COIN_TANK_FULL_MULT := 0.5


static func roll_fish_size() -> float:
	return randf_range(FISH_SIZE_ROLL_MIN, FISH_SIZE_ROLL_MAX)


## The un-rolled reward sum for a species caught off a row of rate `rate` -- the
## spreadsheet's CALCULATION column. Exposed on its own for tuning tools.
static func fish_coin_points(species: String, rate: float) -> float:
	var s := OverworldPokemonData.fish_stats(species)
	var line := float(s["line_strength"]) / 100.0
	var reel := float(s["reel_step"])
	var total := 200.0 - rate * 4.0
	if OverworldPokemonData.species_big_fish(species):
		total += FISH_COIN_BIG_BONUS
	total += 100.0 * float(s["fish_size"])
	total += 200.0 / (line * line)
	total += 200.0 / float(s["recharge_time"])
	total += 20.0 / (reel * reel) * 100.0
	total += float(s["initial_distance"]) / 2.0
	total += float(s["lateral_speed"]) / 2.0
	total += float(s["energy"]) / 2.0
	return total


## What one landed fish is worth. fish_stats() clamps every stat above zero, so none of
## the divisions can blow up.
static func fish_coin_reward(species: String, rate: float, size_roll: float,
		tank_full: bool = false) -> int:
	var coins := fish_coin_points(species, rate) / FISH_COIN_DIVISOR * size_roll
	if tank_full:
		coins *= FISH_COIN_TANK_FULL_MULT
	return maxi(1, int(round(coins)))


## Dropped after the placement tool writes, so the next cast reads the new spots.
static func invalidate() -> void:
	_cache.clear()
