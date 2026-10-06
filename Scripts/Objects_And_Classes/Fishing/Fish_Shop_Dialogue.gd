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
##   * A block with an unlock ("verdant", "fish_50", "fish_200") is followed by the
##     "X can now be purchased in the FISH shop" notice -- ONCE EVER, from whichever
##     keeper gets there first. That notice is also what puts the item on the shelf
##     (GameState.fish_shop_revealed).
##   * The flavour-only blocks ("fish_10", "fish_25") are SKIPPED for good if an unlock
##     block is also waiting, and only the later of the two plays if both are -- the
##     player has moved on.
##   * Nothing waiting: the keeper's REGULAR line for how far the player has got.
##
## The last box asks Yes/No and Yes opens the shop -- unless the visit ended on an
## unlock notice, in which case the conversation simply ends (talk again to shop).
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

## Unlock blocks first in story order, then the flavour blocks (only one of which can
## ever play in a visit, and never alongside an unlock block).
const MILESTONE_ORDER := ["verdant", "fish_50", "fish_200", "fish_10", "fish_25"]
const FLAVOUR := ["fish_10", "fish_25"]

## Milestone -> the item its notice puts on the shelf.
const UNLOCKS := {
	"verdant": "Verdant_Forest_Fishing_Permit",
	"fish_50": "Deep_Ocean_Fishing_Permit",
	"fish_200": "Gold_Rod",
}
const UNLOCK_NOTICE := "%s can now be purchased in the FISH shop"

## Verdant Forest opens on this real date (the gate in Celeste_Harbour.gd uses the same).
const VERDANT_OPEN_DATE := 5

## Lines per keeper per milestone, WITHOUT the greeting (the first box gets it).
const LINES := {
	"olly": {
		"fish_10": [
			"You've already sent me back almost a dozen fish, it was looking a bit empty in here before. Thanks again for helping me with this! You could definitely use some new FISH gear!",
		],
		"verdant": [
			"I've finished clearing out downstairs so I've got way more room now. Have you tried your rod out over in Verdant forest yet?",
			"Make sure you buy a forest fishing permit from here if you haven't already and are wanting to fish there! You only need to buy the permit once but you can't fish in the forest without one.",
		],
		"fish_25": [
			"Research is going great thanks to you, the fish just keep flying on in! Thanks again to all your hard work fishing, I've not had that much time with research to actually fish!",
		],
		"fish_50": [
			"We've found an amazing fishing spot a few miles out of the harbour right in the middle of the ocean",
			"We've started offering trips out there a couple of times a day if you're interested in going to fish up some rare Pokemon!",
			"Just make sure you buy the permit to get there then show it to the boat captain at our fishing dock and he'll take you any time you want!",
			"You'll only need to buy the permit once and we'll take you out there whenever you want, free of charge!",
		],
		"fish_200": [
			"I've never seen such a dedicated true to heart fisher. I've got a special rod just for you and nobody else. It might cost you half an arm or a leg but you won't get any better than the Gold Rod!",
		],
	},
	"alexander": {
		"fish_10": [
			"you've been busy recently I see, these tanks were practically empty before you starting helping out. Olly is already starting to clear out the basement to make room for more down there. Do you need anything?",
		],
		"verdant": [
			"looks like they finally cleared out and reopened Verdant forest again.",
			"If you haven't fished there yet and don't have a fishing permit for it then you'll have to buy one from here",
		],
		"fish_25": [
			"you're keeping us in business, but thanks to you I have to clean out these tanks every day now... I need a raise... What can I get for you?",
		],
		"fish_50": [
			"did Olly tell you about the new fishing spot we found out in the middle of the ocean?",
			"If you buy the permit from us then all you have to do is show it to the captain on our fishing dock and sail you out",
			"He'll take you for free at any point you want to go and you might find some rare Pokemon so it's worth checking out.",
		],
		"fish_200": [
			"I've been told that you might be interested in our new Gold Rod. It's honestly the best rod I think has ever existed and makes fishing a breeze. It's just a bit pricey but we've got it if you want it.",
		],
	},
}

## The everyday line once nothing new is waiting, by total fish caught: the highest
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
	var fish := GameState.get_fish_caught()
	match milestone:
		"fish_10": return fish >= 10
		"fish_25": return fish >= 25
		"fish_50": return fish >= 50
		"fish_200": return fish >= 200
		"verdant": return GameState.get_date() >= VERDANT_OPEN_DATE
	return false


## True when the notice for `item_name` has played, i.e. it may be sold. Items that no
## milestone unlocks are always available.
static func item_unlocked(item_name: String) -> bool:
	for milestone in UNLOCKS:
		if UNLOCKS[milestone] == item_name:
			return GameState.fish_shop_revealed(milestone)
	return true


## This visit's boxes, in order. Each step is {text} with optional
## {reveal_id, reveal_text, reveal_image} (a notice to play after it) and, on the last
## one only, {ask: true} (Yes/No into the shop). Marks the blocks used as heard.
static func build(npc_name: String) -> Array:
	var keeper: String = KEEPERS.get(npc_name, "olly")
	var heard := GameState.fish_shop_heard(keeper)
	var pending: Array = []
	for milestone in MILESTONE_ORDER:
		if reached(milestone) and milestone not in heard:
			pending.append(milestone)

	var unlock_waiting := false
	for milestone in pending:
		if milestone not in FLAVOUR:
			unlock_waiting = true
	var play: Array = []
	if unlock_waiting:
		for milestone in pending:
			if milestone not in FLAVOUR:
				play.append(milestone)
	elif not pending.is_empty():
		play.append(pending[pending.size() - 1])  # the later flavour block only

	# Every pending block counts as heard, played or skipped.
	if not pending.is_empty():
		GameState.mark_fish_shop_heard(keeper, pending)

	if play.is_empty():
		return [{"text": regular_line(keeper), "ask": true}]

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
	var fish := GameState.get_fish_caught()
	for pair in REGULAR.get(keeper, REGULAR["olly"]):
		if fish >= int(pair[0]):
			return str(pair[1])
	return str(REGULAR["olly"][-1][1])


## The item's art, or "" when it has not been drawn yet (the notice then shows text only).
static func item_image(item_name: String) -> String:
	var path := "res://Image_Assets/Assorted_Extras/%s.png" % item_name
	return path if ResourceLoader.exists(path) else ""
