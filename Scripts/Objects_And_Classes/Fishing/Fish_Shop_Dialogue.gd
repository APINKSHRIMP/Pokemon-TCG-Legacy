class_name FishShopDialogue
extends RefCounted

## What Olly and Alexander say when the player talks to them at the counter.
##
## Every visit opens with the keeper's greeting ("Hey [NAME]!" / "Hey [NAME],") as part of
## the FIRST box. Then:
##
##   * MILESTONES the keeper has not told the player about yet, in MILESTONE_ORDER, each
##     its own block of lines. Each keeper says each block once; the other keeper still
##     says theirs on the player's first talk with them.
##   * A block with an unlock is followed by the "X can now be purchased in the FISH
##     shop" notice -- ONCE EVER, from whichever keeper gets there first. That notice is
##     also what puts the item on the shelf (GameState.fish_shop_revealed).
##   * Nothing waiting: the keeper's REGULAR line for how far the player has got.
##
## The last box asks Yes/No and Yes opens the shop -- unless the visit ended on an
## unlock notice, in which case the conversation simply ends (talk again to shop).
##
## Only the Verdant Forest milestone is said over the counter now. The fish-count ones
## (10, 25, 50, 75, 100, 200 fish SENT TO FISH) are PHONE CALLS that ring the moment the
## number is reached -- see FishShopCalls and the fish_shop_* entries in Phone_Calls.json.
##
## [NAME] is substituted by the message box. "[!]" / "[?]" at the start or end of a line
## pop over the keeper's head (MapManager.split_emote_tags).

## npc_name in Characters/Fish_Shop.json -> keeper id.
const KEEPERS := {
	"Fish Shop Olly": "olly",
	"Fish Shop Alexander": "alexander",
}

const GREETING := {
	"olly": "Hey [NAME]! ",
	"alexander": "Hey [NAME], ",
}

const MILESTONE_ORDER := ["verdant"]

## Milestone -> the item its notice puts on the shelf. (The fish-count unlocks are
## FishShopCalls.ITEM_UNLOCKS.)
const UNLOCKS := {
	"verdant": "Verdant_Forest_Fishing_Permit",
}
const UNLOCK_NOTICE := "%s can now be purchased in the FISH shop"

## Verdant Forest opens on this real date (the gate in Celeste_Harbour.gd uses the same).
const VERDANT_OPEN_DATE := 5

## Lines per keeper per milestone, WITHOUT the greeting (the first box gets it).
const LINES := {
	"olly": {
		"verdant": [
			"I've finished clearing out downstairs so I've got way more room now. Have you tried your rod out over in Verdant forest yet?",
			"Make sure you buy a forest fishing permit from here if you haven't already and are wanting to fish there! You only need to buy the permit once but you can't fish in the forest without one.",
		],
	},
	"alexander": {
		"verdant": [
			"looks like they finally cleared out and reopened Verdant forest again.",
			"If you haven't fished there yet and don't have a fishing permit for it then you'll have to buy one from here",
		],
	},
}

## The everyday line once nothing new is waiting, by fish SENT TO FISH: the highest
## threshold reached wins. Full lines, greeting included.
const REGULAR := {
	"olly": [
		[200, "Hey [NAME]! Celeste Harbour's greatest fisher is back! What FISH gear can I get you today?"],
		[50, "Hey [NAME]! Have you been out to the deep ocean yet? The rarest fish are all out there! What FISH gear do you need?"],
		[25, "Hey [NAME], Don't forget FISH when you're a world famous Fisher! What FISH supplies do you need today?"],
		[10, "Hey [NAME], keeping up the killer casting! Do you need any FISH gear?"],
		[0, "Hey [NAME]! I hope the waters are treating you well! Do you need any FISH gear?"],
	],
	"alexander": [
		[200, "Hey [NAME], our best customer! What can I get for you?"],
		[50, "Hey [NAME], the captain's down on the dock whenever you want to head out. Need anything?"],
		[25, "Hey [NAME], Back again! What do you need?"],
		[10, "Hey [NAME], What are you looking for?"],
		[0, "Hey [NAME], do you need anything?"],
	],
}


static func is_keeper(npc_name: String) -> bool:
	return KEEPERS.has(npc_name)


static func reached(milestone: String) -> bool:
	match milestone:
		"verdant": return GameState.get_date() >= VERDANT_OPEN_DATE
	return false


## True when the notice for `item_name` has played, i.e. it may be sold. Items that no
## milestone unlocks are always available.
static func item_unlocked(item_name: String) -> bool:
	for milestone in UNLOCKS:
		if UNLOCKS[milestone] == item_name:
			return GameState.fish_shop_revealed(milestone)
	var fish_milestone := FishShopCalls.milestone_for_item(item_name)
	if fish_milestone >= 0:
		return GameState.fish_shop_revealed(FishShopCalls.reveal_id(fish_milestone))
	return true


## This visit's boxes, in order. Each step is {text} with optional
## {reveal_id, reveal_text, reveal_image} (a notice to play after it) and, on the last
## one only, {ask: true} (Yes/No into the shop). Marks the blocks used as heard.
static func build(npc_name: String) -> Array:
	var keeper: String = KEEPERS.get(npc_name, "olly")
	var heard := GameState.fish_shop_heard(keeper)
	var play: Array = []
	for milestone in MILESTONE_ORDER:
		if reached(milestone) and milestone not in heard:
			play.append(milestone)
	if not play.is_empty():
		GameState.mark_fish_shop_heard(keeper, play)

	var steps: Array = []
	for milestone in play:
		var lines: Array = LINES[keeper].get(milestone, [])
		for line in lines:
			steps.append({"text": str(line)})
		if UNLOCKS.has(milestone) and not GameState.fish_shop_revealed(milestone) and not steps.is_empty():
			var item: String = UNLOCKS[milestone]
			var last: Dictionary = steps[steps.size() - 1]
			last["reveal_id"] = milestone
			last["reveal_text"] = UNLOCK_NOTICE % FishingRods.label(item)
			last["reveal_image"] = item_image(item)
	if steps.is_empty():
		return [{"text": regular_line(keeper), "ask": true}]
	steps[0]["text"] = GREETING[keeper] + str(steps[0]["text"])
	var final: Dictionary = steps[steps.size() - 1]
	if not final.has("reveal_id"):
		final["ask"] = true
	return steps


static func regular_line(keeper: String) -> String:
	var fish := GameState.fish_sent_total()
	for pair in REGULAR.get(keeper, REGULAR["olly"]):
		if fish >= int(pair[0]):
			return str(pair[1])
	return str(REGULAR["olly"][-1][1])


## The item's art, or "" when it has not been drawn yet (the notice then shows text only).
static func item_image(item_name: String) -> String:
	var path := "res://Image_Assets/Assorted_Extras/%s.png" % item_name
	return path if ResourceLoader.exists(path) else ""
