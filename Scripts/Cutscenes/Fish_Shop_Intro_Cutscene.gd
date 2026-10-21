class_name FishShopIntroCutscene
extends Cutscene

# ============================================================
# FISH SHOP -- OLLY'S OPENING SCENE
# ============================================================
# Plays the first time the player walks into the Fish Shop (story flag
# GameState.FISH_SHOP_INTRO_FLAG). Whoever is behind the counter today -- Olly or
# Alexander, by the rota in Characters/Fish_Shop.json -- is at the back facing the wall,
# greets whoever came in without looking, turns, recognises the player [!], and the two
# meet across the counter. They give the Proto Rod and the Celeste Harbour Fishing Permit,
# explain the Fish Coin deal, and the scene ends with the shop open as normal.
#
# Olly tells it in the first person (it is his research and his rods). Alexander tells
# the same story about Olly -- LINES_*_ALEXANDER. The scheduled keeper is hidden while a
# cutscene copy of them plays the scene, then shown again where they stand.
#
# STAGING comes off the room's collision, so moving the counter moves the scene:
#   "DeskTop"    if the scene has one, Olly starts with his head at its BOTTOM edge;
#                otherwise the back wall "Wall H" stands in for it.
#   "DeskBottom" if the scene has one, else "Desk": Olly ends with his feet on its TOP
#                edge, the player with their head on its BOTTOM edge, both centred on it.

# Fallback when no keeper is scheduled (should not happen: one is in at every time slot).
const OLLY_NAME := "Olly"
const OLLY_SPRITE := "1Olly_Jeans_Bag"
const OLLY_COLOUR := "aqua"

const PROTO_ROD := "Proto_Rod"
const CELESTE_PERMIT := "Celeste_Harbour_Fishing_Permit"

## TWEAKABLE -- world px from a character's origin to the top of its head / its feet.
## The 64px chibi sheets at 0.5 scale span about -9 .. +13.5; the player's collision box
## top is at -9.5 (Player_Object_Scene: 16x23 at (0, 2)).
const OLLY_HEAD := 9.0
const OLLY_FEET := 13.5
const PLAYER_HEAD := 9.5

## TWEAKABLE -- pacing.
const OPEN_PAUSE := 0.6
const TURN_PAUSE := 0.4
const OLLY_WALK_SPEED := 40.0
const PLAYER_WALK_SPEED_HERE := 70.0

## Fallback geometry if the nodes are missing (Fish_Shop.tscn as of 2026-10-06).
const FALLBACK_TOP := Rect2(0.0, -22.0, 462.0, 20.0)   # Wall H
const FALLBACK_DESK := Rect2(146.0, 49.0, 165.0, 8.0)  # Desk

# --- DIALOGUE ------------------------------------------------
const LINE_GREETING := "Welcome to FISH! I'll be with you in a minute..."
# The player met Olly that morning (his intro cutscene), so this is a friend dropping in.
const LINES_RECOGNISE := [
	"[!]Oh it's you [NAME]!",
	"So looks like you are interested in a second hobby then?",
]
const LINES_RECOGNISE_ALEXANDER := [
	"[!]Oh it's you [NAME]!",
	"Olly said you might swing by. So looks like you are interested in a second hobby then?",
]
const LINES_PITCH := [
	"I've been able to incorporate Pokeball technology directly into our fishing rods allowing you to catch them without a Pokeball!",
	"With some investment from Silph Co I'm developing better rods but they need testing before Silph will pick them up for the mass market.",
	"I knew you'd come round to fishing eventually! I could do with a huuuuuuuge favour with all this!",
	"If I give you one of my prototype rods for free, could you just test it works properly and send me any fish you catch back for analysis?",
]
# Alexander, passing on Olly's favour.
const LINES_PITCH_ALEXANDER := [
	"Olly's been able to incorporate Pokeball technology directly into our fishing rods allowing you to catch them without a Pokeball!",
	"With some investment from Silph Co he's developing better rods but they need testing before Silph will pick them up for the mass market.",
	"Olly knew you'd come round to fishing eventually! He could do with a huuuuuuuge favour with all this!",
	"He asked if I could give you one of his prototype rods for free. Could you just test it works properly and send any fish you catch back to him for analysis?",
]
const REVEAL_ROD := "You got the Proto Rod!"
const REVEAL_PERMIT := "You got the Celeste Harbour Fishing Permit!"
const LINES_AFTER_ALEXANDER := [
	"There's a couple fishing spots around the harbour, simply catch any fish like normal and they'll be sent directly back here for Olly's research.",
	"For every fish you catch and send, Olly will pay you in FISHCOIN which you can then spend here to get even more FISH gear!",
	"You'll not only be doing Olly a massive favour but also we're really out here helping protect the local Pokemon so you'll be doing a good thing!",
	"You'll probably be really good at it, it's a lot easier than you think it is don't worry.",
	"Between myself and Olly, one of us will always be at the shop if you want to buy any better gear!",
	"Good luck!",
]
const LINES_AFTER := [
	"There's a couple fishing spots around the harbour, simply catch any fish like normal and they'll be sent directly back to me for my research.",
	"For every fish you catch and send, I'll pay you in FISHCOIN which you can then spend here to get even more FISH gear!",
	"You'll not only be doing me a massive favour but also we're really out here helping protect the local Pokemon so you'll be doing a good thing!",
	"You'll probably be really good at it, it's a lot easier than you think it is don't worry.",
	"Between myself and Alexander, one of us will always be at the shop if you want to buy any better gear!",
	"Good luck!",
]


static func should_run() -> bool:
	return not GameState.has_flag(GameState.FISH_SHOP_INTRO_FLAG)


func run() -> void:
	var desk := zone_rect("DeskBottom", Rect2())
	if desk.size == Vector2.ZERO:
		desk = zone_rect("Desk", FALLBACK_DESK)
	var back := zone_rect("DeskTop", Rect2())
	if back.size == Vector2.ZERO:
		back = zone_rect("Wall H", FALLBACK_TOP)
	var centre_x := desk.get_center().x
	var olly_start := Vector2(centre_x, back.end.y + OLLY_HEAD)
	var olly_end := Vector2(centre_x, desk.position.y - OLLY_FEET)
	var player_end := Vector2(centre_x, desk.end.y + PLAYER_HEAD)

	var keeper := _scheduled_keeper()
	var who := OLLY_NAME
	var sprite := OLLY_SPRITE
	var colour := OLLY_COLOUR
	if keeper != null:
		keeper.visible = false
		who = str(keeper.friendly_name) if str(keeper.friendly_name) != "" else OLLY_NAME
		sprite = str(keeper.sprite) if str(keeper.sprite) != "" else OLLY_SPRITE
		colour = str(keeper.message_colour) if str(keeper.message_colour) != "" else OLLY_COLOUR
	var is_alexander: bool = keeper != null and FishShopDialogue.KEEPERS.get(str(keeper.npc_name), "") == "alexander"

	var olly := spawn(who, sprite, olly_start, "up")
	var speaker := {"name": who, "sprite": sprite, "colour": colour, "node": olly}

	await wait(OPEN_PAUSE)
	await say(speaker, LINE_GREETING)
	close_box()
	await wait(TURN_PAUSE)
	olly.face("down")
	await wait(TURN_PAUSE)
	await say_all(speaker, LINES_RECOGNISE_ALEXANDER if is_alexander else LINES_RECOGNISE)
	close_box()

	# Both to the counter at once: Olly comes forward while the player walks up.
	olly.glide_to(olly_end, OLLY_WALK_SPEED, "down")
	if player != null:
		await player_walk_path([Vector2(centre_x, player.global_position.y), player_end],
				PLAYER_WALK_SPEED_HERE)
	player_face("up")
	while is_instance_valid(olly) and olly.global_position.distance_to(olly_end) > 0.5:
		await get_tree().process_frame

	await say_all(speaker, LINES_PITCH_ALEXANDER if is_alexander else LINES_PITCH)
	GameState.add_item_to_collection(PROTO_ROD)
	await _reveal(REVEAL_ROD, PROTO_ROD)
	GameState.add_item_to_collection(CELESTE_PERMIT)
	await _reveal(REVEAL_PERMIT, CELESTE_PERMIT)
	await say_all(speaker, LINES_AFTER_ALEXANDER if is_alexander else LINES_AFTER)
	close_box()

	GameState.set_flag(GameState.FISH_SHOP_INTRO_FLAG)
	if keeper != null and is_instance_valid(keeper):
		keeper.global_position = olly_end
		keeper.visible = true
	finish()


## The rod / permit fading up on the gift overlay, with the box under it. Returns once
## the player has cleared it, with the overlay taken down for the next line.
func _reveal(text: String, item_name: String) -> void:
	MapManager.show_item_reveal(text, FishShopDialogue.item_image(item_name),
			func(): line_advanced.emit())
	await line_advanced
	close_box()


## Whichever keeper the schedule put behind the counter.
func _scheduled_keeper() -> Node2D:
	for node in get_tree().get_nodes_in_group("npcs"):
		if "npc_name" in node and FishShopDialogue.is_keeper(str(node.npc_name)):
			return node as Node2D
	return null
