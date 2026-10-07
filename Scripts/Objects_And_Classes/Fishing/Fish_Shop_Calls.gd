class_name FishShopCalls
extends RefCounted

## The phone calls FISH makes as the player sends fish back -- "25 fish! I'm expanding,
## you can send me more of each now!" -- and the shop items they unlock.
##
## A MILESTONE is a number of fish SENT TO FISH (GameState.fish_sent_total). They are:
##   * every Interior_<N> above 0 in either floor's scene (FishShopTanks reads them off
##     the scene files), so an expansion and its call always share one number;
##   * CALL_ONLY -- calls with no expansion behind them;
##   * ITEM_UNLOCKS -- a call whose end puts an item on the FISH shelf.
## Change one of the code numbers here, or rename an Interior, and rename the matching
## calls in Phone_Calls.json: fish_shop_<N>_olly and fish_shop_<N>_alexander. Whoever is
## behind the counter today (Characters/Fish_Shop.json) is who rings.
##
## A call's lines may include the line "[UNLOCK]" where an item reveal should play; with
## no marker the reveal plays after the last line. MapManager.ring_fish_shop_calls() is
## what rings them, as soon as the fishing that crossed the number has finished.

const CALL_ONLY := [10, 200]
## Milestone -> the item its call reveals in the shop.
const ITEM_UNLOCKS := {
	50: "Deep_Ocean_Fishing_Permit",
	200: "Gold_Rod",
}
const CALL_ID := "fish_shop_%d_%s"
const UNLOCK_MARKER := "[UNLOCK]"
const SHOP_MAP := "Fish_Shop"


## Every milestone, lowest first.
static func milestones() -> Array:
	var out: Array = FishShopTanks.expansion_milestones().duplicate()
	for n in CALL_ONLY + ITEM_UNLOCKS.keys():
		if int(n) not in out:
			out.append(int(n))
	out.sort()
	return out


## Milestones reached whose call has not rung yet, lowest first.
static func pending() -> Array:
	var sent := GameState.fish_sent_total()
	var out: Array = []
	for n in milestones():
		if n <= sent and not GameState.fish_shop_call_rung(n):
			out.append(n)
	return out


## The shop-reveal id for a milestone's item -- the same ids GameState.fish_shop_revealed
## has always used ("fish_50").
static func reveal_id(milestone: int) -> String:
	return "fish_%d" % milestone


## The milestone that unlocks `item_name`, or -1.
static func milestone_for_item(item_name: String) -> int:
	for n in ITEM_UNLOCKS:
		if ITEM_UNLOCKS[n] == item_name:
			return int(n)
	return -1


## "olly" or "alexander": whoever the schedule has behind the FISH counter right now.
static func keeper_on_shift() -> String:
	var cast := CharacterSchedule.cast_for(SHOP_MAP, GameState.get_date(), GameState.get_time(),
			Callable(MapManager, "evaluate_condition"))
	for entry in cast.get("npcs", []):
		var npc_name := str(entry.get("name", ""))
		if FishShopDialogue.is_keeper(npc_name):
			return FishShopDialogue.KEEPERS[npc_name]
	return "olly"


static func has_call(milestone: int) -> bool:
	return not PhoneCall.load_call_data(CALL_ID % [milestone, "olly"]).is_empty() \
			or not PhoneCall.load_call_data(CALL_ID % [milestone, "alexander"]).is_empty()


## The call to play for a milestone, ready for PhoneCall.play_call -- the on-shift
## keeper's, falling back to the other's -- with its item reveal spliced in. {} when
## there is no call at all.
static func build_config(milestone: int) -> Dictionary:
	var keeper := keeper_on_shift()
	var config := PhoneCall.load_call_data(CALL_ID % [milestone, keeper])
	if config.is_empty():
		var other := "alexander" if keeper == "olly" else "olly"
		config = PhoneCall.load_call_data(CALL_ID % [milestone, other])
	if config.is_empty():
		return {}
	config = config.duplicate(true)
	var lines: Array = []
	var reveal := _reveal_step(milestone)
	var placed := false
	for line in config.get("lines", []):
		if str(line).strip_edges() == UNLOCK_MARKER:
			if not reveal.is_empty() and not placed:
				lines.append(reveal)
				placed = true
			continue
		lines.append(line)
	if not reveal.is_empty() and not placed:
		lines.append(reveal)
	config["lines"] = lines
	return config


## The mid-call reveal for a milestone's item, or {} if it unlocks nothing (or already
## has). Marks the item revealed as it shows -- that is what puts it on the shelf.
static func _reveal_step(milestone: int) -> Dictionary:
	if not ITEM_UNLOCKS.has(milestone):
		return {}
	var id := reveal_id(milestone)
	if GameState.fish_shop_revealed(id):
		return {}
	var item: String = ITEM_UNLOCKS[milestone]
	return {
		"reveal_text": FishShopDialogue.UNLOCK_NOTICE % FishingRods.label(item),
		"reveal_image": FishShopDialogue.item_image(item),
		"on_shown": GameState.mark_fish_shop_revealed.bind(id),
	}


## DEBUG (DEL menu): pretend `total` fish have been sent. Every milestone at or below it
## counts as rung, with its item on the shelf; every one above is reset so the next real
## catch past it rings its call. Species counts are left alone (see debug_fill_tanks).
static func debug_set_sent(total: int) -> void:
	var rung: Array = []
	var reveal_on: Array = []
	var reveal_off: Array = []
	for n in milestones():
		if n <= total:
			rung.append(n)
			if ITEM_UNLOCKS.has(n):
				reveal_on.append(reveal_id(n))
		elif ITEM_UNLOCKS.has(n):
			reveal_off.append(reveal_id(n))
	GameState.debug_set_fish_sent(total, null, rung, reveal_on, reveal_off)


## DEBUG (DEL menu): every species sent up to its cap for the stages in force now, so the
## tanks show full. The total and the milestones are untouched.
static func debug_fill_tanks() -> void:
	var per: Dictionary = {}
	for floor_name in FishShopTanks.floors():
		var tanks := FishShopTanks.tanks_in_force(floor_name)
		for tank in tanks:
			for row in tanks[tank]:
				var species := str(row.get("species", ""))
				per[species] = int(per.get(species, 0)) + int(row.get("max", 0))
	var rung: Array = []
	for n in milestones():
		if GameState.fish_shop_call_rung(n):
			rung.append(n)
	GameState.debug_set_fish_sent(GameState.fish_sent_total(), per, rung)


## A milestone with no call written: still unlock its item, so a missing call never
## leaves something unbuyable.
static func unlock_without_call(milestone: int) -> void:
	push_warning("FishShopCalls: no fish_shop_%d_* call in Phone_Calls.json" % milestone)
	if ITEM_UNLOCKS.has(milestone):
		GameState.mark_fish_shop_revealed(reveal_id(milestone))
