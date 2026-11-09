class_name TownHallCrowd
extends RefCounted

## THE CARD ELDER CHALLENGE CROWD -- who is playing which Elder in the Town Hall this slot.
##
## The spectators themselves are hand-written in TownHall.json. This class reworks that
## slot's cast before it spawns (Town_Hall.adjust_cast, and World_Map for the phone dots):
##
##   1. Nobody spawns on top of the player (back from a match, the crowd has moved on
##      around them, never onto them).
##   2. Anyone standing on an Elder's challenger spot (FRONT_SPOTS) is playing that Elder,
##      so the Elder is busy: an NPC with BUSY_LINES instead of an opponent. That is how a
##      hand-placed Ellie / Olly / Alexander (or the day-4 Plaza Challengers) lock one out.
##   3. If the slot has at least one spectator, the rules below put ONE random
##      "Elder Challenger N" (All_NPC_Constant_Data.json) on an Elder's spot:
##        3 Elders left -> any of the three.
##        2 left        -> the slot the clock moved into while the player was in here having
##                         just beaten one: one of the two left (a rare forced pick).
##                         Every other slot: the Elder already beaten (both left are free).
##        1 left        -> just beaten the second: the FIRST one beaten. Otherwise either
##                         beaten Elder, 50/50. The last Elder is never taken.
##        0 left        -> any Elder (they are all NPCs by now anyway).
##      A challenger is never put on the spot the player is standing on, or on the Elder
##      just fought. If a hand-placed character already plays one of the Elders the rule
##      would pick from, no random challenger is added -- the other one stays free.
##
## The roll is made once per day + time slot and saved (progress STATE_KEY), so walking
## out and back in never re-rolls it. A slot with no spectators gets no random challenger,
## which is how the challenge winds down after day 10.

const MAP_NAME := "TownHall"
const STATE_KEY := "town_hall_crowd"

## Where a challenger stands to play each Elder (TownHall NPC-container coordinates).
const FRONT_SPOTS := {
	"Card Elder Hamish":  Vector2(399, 83.5),
	"Card Elder Rayne":   Vector2(271, 83.5),
	"Card Elder Waverly": Vector2(335, 83.5),
}
## TWEAKABLE: a character this close to a FRONT_SPOT is playing that Elder.
const SPOT_RADIUS := 12.0
## TWEAKABLE: nobody spawns this close to the player.
const PLAYER_CLEARANCE := 18.0
## The challenger pool: "Elder Challenger 1" .. CHALLENGER_COUNT in All_NPC_Constant_Data.
const CHALLENGER_PREFIX := "Elder Challenger "
const CHALLENGER_COUNT := 10
## Never counted as spectators.
const NOT_SPECTATORS := ["Town Hall Receptionist", "Town Hall Security"]

## A busy Elder's lines (meet, repeat), while still to be beaten.
const BUSY_LINES := {
	"Card Elder Hamish": [
		"Hoh Hoh, I'm right in the middle of a match! Try one of the others, or come back a little later.",
		"Still playing I'm afraid, give us a little while.",
	],
	"Card Elder Rayne": [
		"Shh, the storm is in full flow! I'm mid-match, come back once this one has blown over.",
		"Not long now, this challenger is putting up quite the fight.",
	],
	"Card Elder Waverly": [
		"Can't you see I've got a challenger? Wait your turn, or try one of the others.",
		"Patience! This match won't be much longer.",
	],
}
## A busy Elder's lines once the player has already beaten them.
const DEFEATED_BUSY_LINES := {
	"Card Elder Hamish": [
		"Hoh Hoh, another challenger! You've already earned my medal, so let me give this one my full attention.",
		"They're no match for you, but they're trying their best.",
	],
	"Card Elder Rayne": [
		"Another hopeful for the Gym Hero Challenge! You've weathered my storm already, now it's their turn.",
		"Watch closely, you might learn something.",
	],
	"Card Elder Waverly": [
		"Busy busy! You've got my medal already, let this one have a go.",
		"They remind me of you when you first walked in.",
	],
}


## The slot's cast, reworked. `player_pos` is the player in NPC-container coordinates, or
## null when there is no player in the room (the phone map asking).
static func apply(cast: Dictionary, date: int, time: String, player_pos) -> Dictionary:
	# Only the slot being played -- the saved roll is for now, and nothing else asks.
	if date != GameState.get_date() or time != GameState.get_time():
		return cast
	var npcs: Array = cast.get("npcs", [])
	if player_pos is Vector2:
		npcs = npcs.filter(func(e: Dictionary) -> bool:
			return not _near(_pos(e), player_pos, PLAYER_CLEARANCE))
	cast["npcs"] = npcs
	# After the Gym Challenge the Elders are upstairs: no challenge down here.
	if GameState.has_flag(GameState.GYM_CHALLENGE_COMPLETE_FLAG):
		return cast
	_add_extra_spectators(cast, date, time, player_pos)
	npcs = cast["npcs"]
	var state := _state_for(date, time, npcs, player_pos)
	var challengers: Dictionary = state.get("challengers", {})
	for elder in state.get("busy", []):
		_make_busy(cast, String(elder), String(challengers.get(elder, "")), player_pos)
	return cast


# ── the growing crowd ─────────────────────────────────────────────────────────

## TWEAKABLE: each Elder beaten adds this much on top of the slot's authored crowd (2 beaten:
## x1.4). A multiplier, so a slot with a thin crowd stays thin and an empty one stays empty.
const ELDER_CROWD_BONUS := 0.2
## TWEAKABLE: two people are never placed closer together than this.
const CROWD_SPACING := 14.0
const SPECTATOR_PREFIX := "Town Hall Spectator "
## Any spot the file has ever stood one of these on is open floor, so the extras reuse them.
const CROWD_SPOT_PREFIXES := [SPECTATOR_PREFIX, "Plaza Challenger "]


## Brings in spectators who were not due this slot, each on a free authored spot. Seeded by the
## day, slot and Elders beaten, so a slot's crowd does not reshuffle every time the player walks
## out and back in.
static func _add_extra_spectators(cast: Dictionary, date: int, time: String, player_pos) -> void:
	var npcs: Array = cast.get("npcs", [])
	var present: Dictionary = {}
	var taken: Array = []
	for section in ["npcs", "opponents"]:
		for e: Dictionary in cast.get(section, []):
			present[String(e.get("name", ""))] = true
			var at = _pos(e)
			if at is Vector2:
				taken.append(at)
	var scheduled := 0
	for who: String in present:
		if who.begins_with(SPECTATOR_PREFIX):
			scheduled += 1
	var wanted := roundi(scheduled * ELDER_CROWD_BONUS * GameState.card_elders_beaten())
	if wanted <= 0:
		return
	for spot: Vector2 in FRONT_SPOTS.values():
		taken.append(spot)
	if player_pos is Vector2:
		taken.append(player_pos)

	var doc := CharacterSchedule.load_map(MAP_NAME)
	var all_npcs: Dictionary = doc.get("npcs", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([date, time, GameState.card_elders_beaten()])
	var free_names: Array = []
	for who: String in all_npcs:
		if who.begins_with(SPECTATOR_PREFIX) and not present.has(who):
			free_names.append(who)
	var spots := _shuffled(_crowd_spots(all_npcs), rng)
	free_names = _shuffled(free_names, rng)

	for spot: Dictionary in spots:
		if wanted <= 0 or free_names.is_empty():
			break
		var at: Vector2 = spot["at"]
		var clear := true
		for other: Vector2 in taken:
			if other.distance_to(at) < CROWD_SPACING:
				clear = false
				break
		if not clear:
			continue
		var who: String = free_names.pop_back()
		var entry := CharacterSchedule.to_entry(who, all_npcs[who])
		entry["position"] = {"x": at.x, "y": at.y}
		entry["pattern"] = spot["move"]
		npcs.append(entry)
		taken.append(at)
		wanted -= 1
	cast["npcs"] = npcs


## Every {at, move} authored for the crowd, across all their rules.
static func _crowd_spots(all_npcs: Dictionary) -> Array:
	var out: Array = []
	for who: String in all_npcs:
		var counts := false
		for prefix: String in CROWD_SPOT_PREFIXES:
			if who.begins_with(prefix):
				counts = true
		if not counts:
			continue
		var character: Dictionary = all_npcs[who]
		var rules: Array = [character]
		rules.append_array(character.get("when", []))
		for rule: Dictionary in rules:
			var at = rule.get("at", character.get("at"))
			var move = rule.get("move", character.get("move", "idle_up"))
			if at is Array and at.size() >= 2 and move is String:
				out.append({"at": Vector2(float(at[0]), float(at[1])), "move": move})
	return out


static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held = out[i]
		out[i] = out[j]
		out[j] = held
	return out


# ── the roll ──────────────────────────────────────────────────────────────────

static func _state_for(date: int, time: String, npcs: Array, player_pos) -> Dictionary:
	var saved: Dictionary = GameState.progress.get(STATE_KEY, {})
	if int(saved.get("day", -1)) == date and String(saved.get("time", "")) == time:
		# Hand-placed occupants are re-read every load (they can depend on progress).
		var busy: Array = saved.get("busy", []).duplicate()
		for elder in _occupied_by_cast(npcs):
			if elder not in busy:
				busy.append(elder)
		var out := saved.duplicate()
		out["busy"] = busy
		return out
	var rolled := _roll(date, time, npcs, player_pos)
	GameState.progress[STATE_KEY] = rolled
	GameState.save_progress()
	return rolled


static func _roll(date: int, time: String, npcs: Array, player_pos) -> Dictionary:
	var state := {"day": date, "time": time, "busy": [], "challengers": {}}
	var taken := _occupied_by_cast(npcs)
	state["busy"] = taken.duplicate()
	if _spectator_count(npcs) == 0:
		return state

	var left: Array = []
	var beaten: Array = []
	for elder in GameState.CARD_ELDERS:
		if GameState.has_beaten_opponent(elder):
			beaten.append(elder)
		else:
			left.append(elder)
	# Oldest win first: progress "opponents_beaten" is in the order they were beaten.
	var order: Array = GameState.progress.get("opponents_beaten", [])
	beaten.sort_custom(func(a, b) -> bool: return order.find(a) < order.find(b))

	# The clock has just moved on while the player stood here, having beaten an Elder.
	var fought: String = GameState.current_opponent_name if GameState.returning_from_battle else ""
	var just_beat_one: bool = fought in GameState.CARD_ELDERS and GameState.has_beaten_opponent(fought)

	var pool: Array
	match left.size():
		3:
			pool = left
		2:
			pool = left if just_beat_one else beaten
		1:
			pool = [beaten[0]] if just_beat_one else beaten
		_:
			pool = GameState.CARD_ELDERS.duplicate()

	for elder in pool:
		if elder in taken:
			return state   # a hand-placed character is already playing one of them

	var choices: Array = []
	for elder in pool:
		if elder == fought:
			continue
		if player_pos is Vector2 and _near(FRONT_SPOTS[elder], player_pos, PLAYER_CLEARANCE):
			continue
		choices.append(elder)
	if choices.is_empty():
		return state
	var pick: String = choices.pick_random()
	state["busy"].append(pick)
	state["challengers"][pick] = _pick_challenger(npcs)
	return state


## Elders whose challenger spot a cast character is already standing on.
static func _occupied_by_cast(npcs: Array) -> Array:
	var out: Array = []
	for e: Dictionary in npcs:
		if not MapManager.evaluate_condition(e.get("condition", {})):
			continue
		var n := String(e.get("name", ""))
		if n.begins_with("Card Elder") or n.begins_with(CHALLENGER_PREFIX):
			continue
		var at = _pos(e)
		for elder in FRONT_SPOTS:
			if _near(FRONT_SPOTS[elder], at, SPOT_RADIUS) and elder not in out:
				out.append(elder)
	return out


## Everyone watching (or playing) this slot.
static func _spectator_count(npcs: Array) -> int:
	var n := 0
	for e: Dictionary in npcs:
		var name := String(e.get("name", ""))
		if name in NOT_SPECTATORS or name.begins_with("Card Elder"):
			continue
		if not MapManager.evaluate_condition(e.get("condition", {})):
			continue
		n += 1
	return n


static func _pick_challenger(npcs: Array) -> String:
	var present: Array = []
	for e: Dictionary in npcs:
		present.append(String(e.get("name", "")))
	var free: Array = []
	for i in range(1, CHALLENGER_COUNT + 1):
		var n := CHALLENGER_PREFIX + str(i)
		if n not in present:
			free.append(n)
	return free.pick_random() if not free.is_empty() else ""


# ── applying it ───────────────────────────────────────────────────────────────

## The Elder becomes an NPC mid-match (or, already beaten, gets mid-match lines), and the
## challenger -- if this one has a random one -- stands on their spot facing them.
static func _make_busy(cast: Dictionary, elder: String, challenger: String, player_pos) -> void:
	var opponents: Array = cast.get("opponents", [])
	var npcs: Array = cast.get("npcs", [])
	for i in opponents.size():
		var entry: Dictionary = opponents[i]
		if String(entry.get("name", "")) != elder:
			continue
		var as_npc := entry.duplicate(true)
		var lines: Array = BUSY_LINES.get(elder, ["", ""])
		as_npc["meet_text"] = lines[0]
		as_npc["repeat_text"] = lines[1]
		opponents.remove_at(i)
		npcs.append(as_npc)
		break
	for entry: Dictionary in npcs:
		if String(entry.get("name", "")) == elder + " Defeated":
			var lines: Array = DEFEATED_BUSY_LINES.get(elder, ["", ""])
			entry["meet_text"] = lines[0]
			entry["repeat_text"] = lines[1]
	if challenger != "":
		var spot: Vector2 = FRONT_SPOTS[elder]
		if not (player_pos is Vector2 and _near(spot, player_pos, PLAYER_CLEARANCE)):
			npcs.append({"name": challenger, "position": {"x": spot.x, "y": spot.y},
				"pattern": "idle_up"})
	cast["opponents"] = opponents
	cast["npcs"] = npcs


static func _pos(entry: Dictionary):
	var p = entry.get("position", null)
	if p is Dictionary:
		return Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
	return null


static func _near(a, b, radius: float) -> bool:
	return a is Vector2 and b is Vector2 and (a as Vector2).distance_to(b) <= radius
