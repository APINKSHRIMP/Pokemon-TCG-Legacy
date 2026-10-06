class_name FishShopIntroCutscene
extends Cutscene

# ============================================================
# FISH SHOP -- OLLY'S OPENING SCENE
# ============================================================
# Plays the first time the player walks into the Fish Shop (story flag
# GameState.FISH_SHOP_INTRO_FLAG). Olly is at the back of the counter facing the wall,
# greets whoever came in without looking, turns, recognises the player [!], and the
# two meet across the counter. He gives the Proto Rod and the Celeste Harbour Fishing
# Permit, explains the Fish Coin deal, and the scene ends with the shop open as normal.
#
# Day 1 has Olly behind the counter all day and the day-1 opponents wait on this
# flag, so the player always meets OLLY here. The scheduled keeper (whoever it is) is
# hidden while a cutscene Olly plays the scene, then shown again where he stands.
#
# STAGING comes off the room's collision, so moving the counter moves the scene:
#   "DeskTop"    if the scene has one, Olly starts with his head at its BOTTOM edge;
#                otherwise the back wall "Wall H" stands in for it.
#   "DeskBottom" if the scene has one, else "Desk": Olly ends with his feet on its TOP
#                edge, the player with their head on its BOTTOM edge, both centred on it.

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
const LINE_GREETING := "Hello, welcome to FISH! Feel free to look around, I'll be with you in a second..."
const LINE_RECOGNISE := "[!]Oh, [NAME]!! Omg it's been so long, it's nice to have you back. Ellie hasn't stopped going on about you for the past few weeks, she's been so excited"
const LINES_PITCH := [
	"I took over FISH only a couple months back and I've been using the shop to help with my research into water type Pokémon endangerment preservation.",
	"I've been able to incorporate Pokeball technology directly into our fishing rods allowing you to catch them without a Pokeball!",
	"With some investment from Silph Co I'm developing better rods but they need testing before Silph will pick them up for the mass market.",
	"I know how much you used to love fishing so if you're still into it I could do with a huuuuuuuge favour with all this!",
	"If I give you one of my prototype rods for free, could you just test it works properly and send me any fish you catch back for analysis?",
]
const REVEAL_ROD := "You got the Proto Rod!"
const REVEAL_PERMIT := "You got the Celeste Harbour Fishing Permit!"
const LINES_AFTER := [
	"There's a couple fishing spots around the harbour, simply catch any fish like normal and they'll be sent directly back to me for my research.",
	"For every fish you catch and send, I'll pay you in FISHCOIN which you can then spend here to get even more FISH gear!",
	"You'll not only be doing me a massive favour but also we're really out here helping protect the local Pokemon so you'll be doing a good thing!",
	"Hope you're as good at fishing as you used to be! Between myself and Alexander, one of us will always be at the shop if you want to buy any better gear!",
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
	if keeper != null:
		keeper.visible = false

	var olly := spawn(OLLY_NAME, OLLY_SPRITE, olly_start, "up")
	var speaker := {"name": OLLY_NAME, "sprite": OLLY_SPRITE, "colour": OLLY_COLOUR, "node": olly}

	await wait(OPEN_PAUSE)
	await say(speaker, LINE_GREETING)
	close_box()
	await wait(TURN_PAUSE)
	olly.face("down")
	await wait(TURN_PAUSE)
	await say(speaker, LINE_RECOGNISE)
	close_box()

	# Both to the counter at once: Olly comes forward while the player walks up.
	olly.glide_to(olly_end, OLLY_WALK_SPEED, "down")
	if player != null:
		await player_walk_path([Vector2(centre_x, player.global_position.y), player_end],
				PLAYER_WALK_SPEED_HERE)
	player_face("up")
	while is_instance_valid(olly) and olly.global_position.distance_to(olly_end) > 0.5:
		await get_tree().process_frame

	await say_all(speaker, LINES_PITCH)
	GameState.add_item_to_collection(PROTO_ROD)
	await _reveal(REVEAL_ROD, PROTO_ROD)
	GameState.add_item_to_collection(CELESTE_PERMIT)
	await _reveal(REVEAL_PERMIT, CELESTE_PERMIT)
	await say_all(speaker, LINES_AFTER)
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


## Whichever keeper the schedule put behind the counter (normally Olly on day 1).
func _scheduled_keeper() -> Node2D:
	for node in get_tree().get_nodes_in_group("npcs"):
		if "npc_name" in node and FishShopDialogue.is_keeper(str(node.npc_name)):
			return node as Node2D
	return null
