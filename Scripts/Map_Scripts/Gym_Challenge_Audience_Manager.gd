class_name GymChallengeAudienceManager

# ============================================================
# GYM CHALLENGE AUDIENCE MANAGER
# Static helper — generates and partially regenerates the
# spectator audience for the Gym Challenge Hall.
# Call update_audience_state() from Hall._scene_setup() before
# MapManager runs, then spawn entries from get_audience_npc_entries()
# after MapManager.initialise() completes.
# ============================================================

# ============================================================
# TWEAKABLE: AUDIENCE COUNTS  [left_count, top_count, right_count]
# Left and right stands hold 36 max; top stand holds 40 max.
# ============================================================
# ============================================================
# TWEAKABLE: ATTENDANCE
# Fraction of each stand's seats filled, by time of day, on the day the challenge
# opens. Interest then decays by DAILY_DECAY per day: afternoon runs 100%, 90%,
# 81%, 73%, 66% ... so the stands thin out as the tournament drags on.
#
# This replaced a hardcoded table that only covered days 9-14, which left the
# stands completely empty on day 8 (the day the challenge opens) and again from
# day 15 on. The challenge has no end date any more -- it runs until all eight
# leaders are beaten -- so the curve has to hold for any day.
# ============================================================
const CHALLENGE_START_DAY := 8
const BASE_ATTENDANCE: Dictionary = {
	"Morning": 0.80, "Afternoon": 1.00, "Evening": 0.50, "Night": 0.20,
}
const DAILY_DECAY := 0.9

# ============================================================
# TWEAKABLE: REGENERATION PERCENTAGES
# Fraction of the audience that is randomly replaced per event type.
# ============================================================
const REGEN_PCT_PLAZA        := 0.4  # 40% change when player visited the plaza
const REGEN_PCT_DEFEAT       := 0.6  # 60% change after defeating an opponent
const REGEN_PCT_TIME_ADVANCE := 0.9  # 90% change after a time-zone transition

# ============================================================
# TWEAKABLE: ANIMATION VARIETY
# Chance that any individual NPC uses the _random pattern variant
# instead of the plain facing direction.
# ============================================================
const RANDOM_PATTERN_CHANCE := 0.3

# ============================================================
# TWEAKABLE: NPC SPRITE POOL
# Add or remove sprite names here to control which characters
# appear in the stands. One name per line for easy editing.
# ============================================================
const NPC_SPRITE_POOL: Array = [
	"NPC01", "NPC02", "NPC03", "NPC04", "NPC05", "NPC07",
	"NPC09", "NPC10", "NPC11", "NPC12", "NPC16",
	"NPC21", "NPC22", "NPC23", "NPC24", "NPC25",
	"NPC28", "NPC29", "NPC30", 
	"NPC40", "NPC 02", "NPC 03", "NPC 04", "NPC 05", "NPC 06",
	"NPC 07", "NPC 08", "NPC 10", "NPC 13", "NPC 14", "NPC 15", "NPC 17",
	"NPC 26", "NPC 30", "NPC 31", "NPC 32", "NPC 18", "NPC 33", "NPC 34",
	"NPC 85", "NPC 86", "NPC 87", "NPC 88",
	"Aromalady", "Artist", "Artist2",
	"Backers_F", "Backers_F2", "Backers_M", "Backers_M2", "Bakushin_Clerk", "Bakushin_Sailor", "Battlegirl", "Battlegirl2", "Beauty",
	"Birdkeeper_F", "Birdkeeper_M",
	"Gambler", "Scientist_M3", "Scientist_F",
	"Pokemaniac_Red", "Pokemaniac_Blue", "Pokemaniac_Green", "Pokemaniac_Purple",
	"Cooltrainer_F2", "Blackbelt2", "Burglar", "Clerk_F", "Clerk_M0", "Clerk_M1",
	"Gentleman", "Gentleman2", "Gentleman3",
	"Lady", "Lady2", "Youngster", "Youngster2", "Youngster3",
	"Cooltrainer_M", "Cooltrainer_F", "Cooltrainer_M2",
	"Cooltrainer_M3", "Cooltrainer_M4", "Cooltrainer_F3", "Cooltrainer_F4",
	"Hiker", "Collector", "Richboy", "RichBoy2", "Socialite2", "Medium_1", "Rancher",
	"Lass", "Lass2", "Lass3", "Pokefan_F", "Pokefan_F2",
	"Pokemonbreeder_M", "Pokemonbreeder_M2", "Pokemonbreeder_F", "Pokemonbreeder_F2",
	"Pokemonranger_M", "Pokemonranger_M2", "Pokemonranger_F", "Pokemonranger_F2",
	"Psychic_F", "Psychic_F2", "Psychic_M", "Psychic_M2", 
	"Bugcatcher", "Bugcatcher2", "Roughneck", "Roughneck2", "Sage",
	"Beauty2", "Beauty3", "Sailor", "Camper", "Picnicker",
	"Fisherman2", "Fisherman", "Juggler", "Supernerd", "Guitarist", "Guitarist2",
	"Pokefan_M", "Pokefan_M2", "Dancer", "Elder", "Fisher", "Hoopster", "Idol", "NurseryAide",
	"Schoolkid_F", "Schoolkid_F2", "Schoolkid_M", "Schoolkid_M2", "Schoolkid_M3", "Smasher",
	"Socialite", "Striker", "Teacher", "Twin1", "Twin3", "Twin5",
	"Veteran_M", "Veteran_M2", "Veteran_F", "Waiter2", "Waiter",
	"Youngcouple", "Youngcouple_2", "Youngcouple2", "Youngcouple2_2",   
]

# ============================================================
# STAND SEAT POSITIONS — full grids
# Left:  4 cols × 9 rows = 36 seats  (pattern: idle_right)
# Top:  10 cols × 4 rows = 40 seats  (pattern: idle_down)
# Right: 4 cols × 9 rows = 36 seats  (pattern: idle_left)
# ============================================================
const LEFT_SEATS: Array = [
	# x = -14, 9 rows, y step 29
	Vector2(-14, 100), Vector2(-14, 129), Vector2(-14, 158), Vector2(-14, 187),
	Vector2(-14, 216), Vector2(-14, 245), Vector2(-14, 274), Vector2(-14, 303), Vector2(-14, 332),
	# x = 19, 9 rows
	Vector2(19, 116), Vector2(19, 145), Vector2(19, 174), Vector2(19, 203),
	Vector2(19, 232), Vector2(19, 261), Vector2(19, 290), Vector2(19, 319), Vector2(19, 348),
	# x = 51, 9 rows
	Vector2(51, 132), Vector2(51, 161), Vector2(51, 190), Vector2(51, 219),
	Vector2(51, 248), Vector2(51, 277), Vector2(51, 306), Vector2(51, 335), Vector2(51, 364),
	# x = 83, 9 rows
	Vector2(83, 152), Vector2(83, 181), Vector2(83, 210), Vector2(83, 239),
	Vector2(83, 268), Vector2(83, 297), Vector2(83, 326), Vector2(83, 355), Vector2(83, 384),
]

const RIGHT_SEATS: Array = [
	# x = 605, 9 rows, y step 29
	Vector2(605, 163), Vector2(605, 192), Vector2(605, 221), Vector2(605, 250),
	Vector2(605, 279), Vector2(605, 308), Vector2(605, 337), Vector2(605, 366), Vector2(605, 395),
	# x = 637, 9 rows
	Vector2(637, 144), Vector2(637, 173), Vector2(637, 202), Vector2(637, 231),
	Vector2(637, 260), Vector2(637, 289), Vector2(637, 318), Vector2(637, 347), Vector2(637, 376),
	# x = 669, 9 rows
	Vector2(669, 127), Vector2(669, 156), Vector2(669, 185), Vector2(669, 214),
	Vector2(669, 243), Vector2(669, 272), Vector2(669, 301), Vector2(669, 330), Vector2(669, 359),
	# x = 700, 9 rows
	Vector2(700, 109), Vector2(700, 138), Vector2(700, 167), Vector2(700, 196),
	Vector2(700, 225), Vector2(700, 254), Vector2(700, 283), Vector2(700, 312), Vector2(700, 341),
]

const TOP_SEATS: Array = [
	# y = -15, 10 cols, x step 35
	Vector2(210, -15), Vector2(245, -15), Vector2(280, -15), Vector2(315, -15), Vector2(350, -15),
	Vector2(385, -15), Vector2(420, -15), Vector2(455, -15), Vector2(490, -15), Vector2(525, -15),
	# y = 15
	Vector2(210, 15), Vector2(245, 15), Vector2(280, 15), Vector2(315, 15), Vector2(350, 15),
	Vector2(385, 15), Vector2(420, 15), Vector2(455, 15), Vector2(490, 15), Vector2(525, 15),
	# y = 47
	Vector2(210, 47), Vector2(245, 47), Vector2(280, 47), Vector2(315, 47), Vector2(350, 47),
	Vector2(385, 47), Vector2(420, 47), Vector2(455, 47), Vector2(490, 47), Vector2(525, 47),
	# y = 79
	Vector2(210, 79), Vector2(245, 79), Vector2(280, 79), Vector2(315, 79), Vector2(350, 79),
	Vector2(385, 79), Vector2(420, 79), Vector2(455, 79), Vector2(490, 79), Vector2(525, 79),
]

# ============================================================
# PUBLIC API
# ============================================================

## Determine the appropriate regeneration level and update the
## persisted audience in GameState.  Call from Hall._scene_setup().
static func update_audience_state(
	date: int, time: String,
	from_plaza: bool, returning_from_battle: bool
) -> void:
	var existing: Dictionary = GameState.progress.get("gym_challenge_audience", {})
	var stored_time: String  = existing.get("saved_time", "")
	var stored_date: int     = int(existing.get("saved_date", 0))

	var counts: Array  = _get_counts(date, time)
	var left_count: int  = counts[0]
	var top_count: int   = counts[1]
	var right_count: int = counts[2]

	var time_advanced: bool = stored_time != "" and (stored_time != time or stored_date != date)

	var new_audience: Dictionary
	if existing.is_empty():
		new_audience = _generate_fresh(left_count, top_count, right_count)
	elif time_advanced:
		var keep := 1.0 - REGEN_PCT_TIME_ADVANCE
		new_audience = _partial_regen(existing, left_count, top_count, right_count, keep)
	elif returning_from_battle:
		var keep := 1.0 - REGEN_PCT_DEFEAT
		new_audience = _partial_regen(existing, left_count, top_count, right_count, keep)
	elif from_plaza:
		var keep := 1.0 - REGEN_PCT_PLAZA
		new_audience = _partial_regen(existing, left_count, top_count, right_count, keep)
	else:
		return  # Hall → Reception → Hall: audience unchanged

	new_audience["saved_date"] = date
	new_audience["saved_time"] = time
	GameState.progress["gym_challenge_audience"] = new_audience
	GameState.progress.erase("gym_challenge_audience_date")
	GameState.progress.erase("gym_challenge_audience_time")
	GameState.save_progress()


## Convert the persisted audience state into NPC entry dicts ready
## for MapManager.spawn_npc_entry().  Call after MapManager.initialise().
static func get_audience_npc_entries() -> Array:
	var audience: Dictionary = GameState.progress.get("gym_challenge_audience", {})
	var entries: Array = []

	var stand_defs: Array = [
		{"key": "left",  "seats": LEFT_SEATS,  "base": "idle_right", "rnd": "idle_right_random"},
		{"key": "top",   "seats": TOP_SEATS,   "base": "idle_down",  "rnd": "idle_down_random"},
		{"key": "right", "seats": RIGHT_SEATS, "base": "idle_left",  "rnd": "idle_left_random"},
	]

	for def in stand_defs:
		var seats: Array = def["seats"]
		for slot in audience.get(def["key"], []):
			var idx: int = int(slot["seat_index"])
			if idx < 0 or idx >= seats.size():
				continue
			var pos: Vector2 = seats[idx]
			var pattern: String = def["rnd"] if randf() < RANDOM_PATTERN_CHANCE else def["base"]
			entries.append({
				"name":        "Spec_%s_%d" % [def["key"].to_upper(), idx],
				"sprite":      slot["sprite"],
				"position":    {"x": pos.x, "y": pos.y},
				"pattern":     pattern,
				"meet_text":   "",
				"repeat_text": "",
			})
	return entries

# ============================================================
# PRIVATE HELPERS
# ============================================================

static func _get_counts(date: int, time: String) -> Array:
	var base: float = BASE_ATTENDANCE.get(time, 0.0)
	if base <= 0.0:
		return [0, 0, 0]
	var elapsed: int = maxi(0, date - CHALLENGE_START_DAY)
	var fill: float = base * pow(DAILY_DECAY, elapsed)
	return [
		int(round(LEFT_SEATS.size() * fill)),
		int(round(TOP_SEATS.size() * fill)),
		int(round(RIGHT_SEATS.size() * fill)),
	]


static func _generate_fresh(left_count: int, top_count: int, right_count: int) -> Dictionary:
	return {
		"left":  _fill_stand(LEFT_SEATS,  left_count,  {}),
		"top":   _fill_stand(TOP_SEATS,   top_count,   {}),
		"right": _fill_stand(RIGHT_SEATS, right_count, {}),
	}


static func _partial_regen(
	existing: Dictionary,
	new_left: int, new_top: int, new_right: int,
	keep_pct: float
) -> Dictionary:
	return {
		"left":  _regen_stand(existing.get("left",  []), LEFT_SEATS,  new_left,  keep_pct),
		"top":   _regen_stand(existing.get("top",   []), TOP_SEATS,   new_top,   keep_pct),
		"right": _regen_stand(existing.get("right", []), RIGHT_SEATS, new_right, keep_pct),
	}


static func _regen_stand(
	old_list: Array, seats: Array, new_target: int, keep_pct: float
) -> Array:
	# How many of the old audience members to retain
	var keep_count: int = mini(ceili(old_list.size() * keep_pct), new_target)

	var shuffled_old: Array = old_list.duplicate()
	shuffled_old.shuffle()
	var kept: Array = shuffled_old.slice(0, keep_count)

	# Mark kept seats as occupied so new fills don't overlap
	var occupied: Dictionary = {}
	for slot in kept:
		occupied[int(slot["seat_index"])] = true

	return kept + _fill_stand(seats, new_target - keep_count, occupied)


static func _fill_stand(seats: Array, count: int, occupied: Dictionary) -> Array:
	var available: Array = []
	for i in seats.size():
		if not occupied.has(i):
			available.append(i)
	available.shuffle()

	var result: Array = []
	var to_pick: int = mini(count, available.size())
	for i in to_pick:
		result.append({"seat_index": available[i], "sprite": _random_sprite()})
	return result


static func _random_sprite() -> String:
	return NPC_SPRITE_POOL[randi() % NPC_SPRITE_POOL.size()]
