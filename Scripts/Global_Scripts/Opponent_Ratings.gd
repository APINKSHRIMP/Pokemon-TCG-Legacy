extends RefCounted

## Opponent difficulty: 1-7 stars, plus three secret ones: orange 8 for the Card Elders,
## red 9 for the gym leaders and purple 10 for Mewtwo alone. Preloaded, not a class_name.
##
## Where a rating comes from, first match wins:
##   1. `stars` on the opponent in All_NPC_Constant_Data.json (1-10) -- set by hand with the
##      star picker in the F placement tool's side panel. The only way to get an 8, 9 or 10.
##   2. The last benchmark DECK TEST in Opponent_Ratings.json -- the opponent's real CPU
##      with their deck against the autotester's smart bot playing every starter deck.
##      Its CPU win rate is turned into 1-7 by WIN_RATE_STARS.
##   3. A starting ESTIMATE in Opponent_Ratings.json ("vs": "estimate"), from the day they
##      first appear plus how strong their deck looks (written 2026-11-11; a benchmark
##      deck test replaces it).
##   4. Nothing: no stars are shown.
##
## Opponent_Ratings.json, written by the placement tool's deck test:
##   { "Bad Dude Paul": { "stars": 3, "win_rate": 0.52, "games": 30, "vs": "benchmark",
##                        "tested": "2026-11-11" }, ... }

const RATINGS_PATH := "res://NPC_and_Opponent_Data/Opponent_Ratings.json"
const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"
## The highest rating an auto test can give, and the highest anything can.
const MAX_AUTO := 7
const MAX_STARS := 10

## TWEAKABLE: the CPU's win rate against the benchmark at or above which an opponent gets
## that many stars (index 0 = 1 star). Below the first value is still 1 star.
const WIN_RATE_STARS := [0.0, 0.15, 0.30, 0.45, 0.60, 0.72, 0.85]

static var _cache: Dictionary = {}
static var _cache_loaded: bool = false


static func load_all() -> Dictionary:
	if not _cache_loaded:
		_cache_loaded = true
		_cache = {}
		if FileAccess.file_exists(RATINGS_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(RATINGS_PATH))
			if parsed is Dictionary:
				_cache = parsed
	return _cache


static func invalidate() -> void:
	_cache_loaded = false


## The stars to show for an opponent. `constants` is their All_NPC_Constant_Data entry
## (pass {} to have it read here).
static func stars_for(opponent_name: String, constants: Dictionary = {}) -> int:
	if constants.is_empty():
		constants = _constants_for(opponent_name)
	var manual := int(constants.get("stars", 0))
	if manual > 0:
		return clampi(manual, 1, MAX_STARS)
	var rating = load_all().get(opponent_name)
	if rating is Dictionary and str(rating.get("vs", "")) in ["benchmark", "estimate"]:
		return clampi(int(rating.get("stars", 0)), 0, MAX_AUTO)
	return 0


## The auto rating for a CPU win rate (0..1) against the benchmark.
static func stars_from_win_rate(rate: float) -> int:
	var stars := 1
	for n in WIN_RATE_STARS.size():
		if rate >= float(WIN_RATE_STARS[n]):
			stars = n + 1
	return clampi(stars, 1, MAX_AUTO)


## Store a finished test. Only a benchmark run sets the stars; a run against one chosen
## deck is kept under "vs_<deck>" so it never overwrites the rating.
static func record(opponent_name: String, wins: int, games: int, vs: String) -> Dictionary:
	var all := load_all().duplicate(true)
	var rate := float(wins) / float(maxi(games, 1))
	var result := {"win_rate": snappedf(rate, 0.001), "games": games, "wins": wins, "vs": vs,
			"tested": Time.get_date_string_from_system()}
	if vs == "benchmark":
		result["stars"] = stars_from_win_rate(rate)
		all[opponent_name] = result
	else:
		var entry: Dictionary = all.get(opponent_name, {}) if all.get(opponent_name) is Dictionary else {}
		var others: Dictionary = entry.get("other_tests", {}) if entry.get("other_tests") is Dictionary else {}
		others[vs] = result
		entry["other_tests"] = others
		all[opponent_name] = entry
	var keys: Array = all.keys()
	keys.sort()
	var ordered: Dictionary = {}
	for k in keys:
		ordered[k] = all[k]
	var out := FileAccess.open(RATINGS_PATH, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(ordered, "  ") + "\n")
		out.close()
	invalidate()
	return result


static func _constants_for(opponent_name: String) -> Dictionary:
	if not FileAccess.file_exists(CONSTANTS_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS_PATH))
	if not (parsed is Dictionary):
		return {}
	var body = parsed.get("opponents", {}).get(opponent_name)
	return body if body is Dictionary else {}
