class_name OllyIntroCutscene
extends Cutscene

# ============================================================
# OLLY — THE FIRST MORNING
# ============================================================
# The first time the player steps out of their front door after the arrival night,
# Olly runs up the street, hands over a deck and challenges them on the spot. What he
# hands over, the deck he plays, the rewards and the lines all follow the save's
# intro profile (GameState.INTRO_PROFILES):
#
#   "new"     Basic Starter Deck. Scripted tutorial match (retries until won), then a
#             fixed bonus pack (starter1_a), the energy cards and the coin talk.
#   "rules"   arrives home on EVENING 1 and Olly comes straight round to the taxi (no night,
#             no house). Pick a Starter Deck. Guided tutorial match (retries until won), then the
#             pair's bonus pack (bonus1_a/b/c), the energy cards and the coin talk.
#   "played"  pick a full Deck, Olly plays the weaker one. One chance, then the energy.
#   "expert"  pick a full Deck, Olly plays the stronger one. One chance, then the energy.
#   Hard Mode nine draft packs, the energy, the deck builder (no way out but saving),
#             then "Let me test ya" with 6 prizes. One chance.
#
# Crossing a scene boundary (the deck builder, the match) frees this object, so the
# stage lives in the save and the map routes back in on reload (Celeste_Harbour._ready).
# ============================================================

const STAGE_KEY    := "olly_intro_stage"
const STAGE_NONE   := ""
const STAGE_BUILD  := "build"    # Hard Mode: away in the deck builder
const STAGE_BATTLE := "battle"   # sent into the match; waiting on the result
const STAGE_DONE   := "done"
# Where the two of them stand, so a resume can put Olly back opposite the player.
const MEET_KEY     := "olly_intro_meet"

const OLLY_NAME := "Olly"
const MAP_NAME  := "Celeste_Harbour"
const DECK_BUILDER_SCENE := "res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn"

# ------------------------------------------------------------
# TWEAKABLE — the arrival
# ------------------------------------------------------------
# He comes in along the upper path outside the house, from the east, starting this far
# along (comfortably off camera at 2.5x zoom).
const ARRIVAL_PATH_Y   : float = 1685.0
const ARRIVAL_START_DX : float = 560.0
# The player steps this far down off the doorstep first, so the camera can see him coming.
const PLAYER_STEP_OUT       : float = 30.0
const PLAYER_STEP_OUT_SPEED : float = 55.0
const STEP_OUT_DELAY        : float = 0.5
# How far below the player he pulls up (leave daylight between the collision boxes).
const MEET_GAP : float = 25.0
# His speed by how far he still has to go: a run (20% slower than Ellie's old 190),
# easing off over the last few hundred px, slowing right down, then walking into place.
const RUN_SPEED     : float = 152.0
const EASE_DISTANCE : float = 260.0   # inside this: EASE_SPEED
const EASE_SPEED    : float = 115.0
const SLOW_DISTANCE : float = 110.0   # inside this: SLOW_SPEED
const SLOW_SPEED    : float = 70.0
const WALK_DISTANCE : float = 35.0    # inside this: WALK_SPEED
const WALK_SPEED    : float = 42.0

# ------------------------------------------------------------
# TWEAKABLE — the exit (down, then off left towards FISH)
# ------------------------------------------------------------
const EXIT_SPEED     : float = 150.0
const EXIT_DOWN      : float = 60.0
const EXIT_LEFT      : float = 700.0
const OFFSCREEN_MARGIN_X : float = 430.0
const OFFSCREEN_MARGIN_Y : float = 234.0
const POST_BATTLE_PAUSE  : float = 0.6

# The cards flipped up for each gift. Basic energy is never granted (it is unlimited);
# the "load of energy cards" is shown, not given.
const BASIC_DECK_SHOWCASE := ["base1-67", "base1-52", "base1-60", "base1-65"]
const ENERGY_SHOWCASE := ["base1-98", "base1-99", "base1-102", "base1-101", "base1-97", "base1-100"]

# ------------------------------------------------------------
# DIALOGUE
# ------------------------------------------------------------
const LINES_OPEN_MORNING := [
	"Morning! I can't believe how late you got back from the tournament last night, was it worth going in the end?",
	"I'll definitely go and see the Gym Hero Challenge when that starts next week, or who knows, we might all be so good that we end up taking part by then!",
]
# "rules": he meets the player as the taxi drops them home, early in the evening.
const LINES_OPEN_EVENING := [
	"Hey! I can't believe how early you got back from the tournament, was it worth going in the end?",
	"I'll definitely go and see the Gym Hero Challenge when that starts next week, or who knows, we might all be so good that we end up taking part by then!",
]
const LINES_NEW_GIVE := ["Speaking of... I managed to get one of each of the starter sets. Here's the one you wanted!"]
const TEXT_NEW_GOT := "You got the starter deck!"
const LINES_NEW_BEFORE_MATCH := [
	"I was just heading out to open up shop but what's 5 mins difference going to make?",
	"Let's have a match right now!",
]
const LINES_PICK_STARTER := [
	"Speaking of... I managed to get one of each of the starter sets and I really don't mind which one I have so I'll let you choose first.",
	"There's a Fire Lightning, a Water Fighting and a Grass Psychic deck... Which one sounds good to you?",
]
const LINES_PICK_DECK := [
	"Speaking of... I managed to get one of each of the decks and I really don't mind which one I have so I'll let you choose first.",
	"There's a Fire Lightning, a Water Fighting and a Grass Psychic deck... Which one sounds good to you?",
]
const TEXT_CONFIRM_PICK := "Are you sure it's the %s that you want?"
const TEXT_GOT_DECK := "You got the %s!"
const LINES_PICKED_BEFORE_MATCH := [
	"Alexander is covering the shop for me so I've got some time now if you do?",
	"Let's have a match right now!",
]
const LINES_HARD_PACKS := [
	"It's annoying that I couldn't get a hold of a deck in the end either, but it's kind of fun that we will just have to build one with what we have.",
	"Here, we'll split the packs 50/50, you take this half and I'll keep this half. Let's open them together now!",
]
const LINE_HARD_AFTER_PACKS := "Wow!! We both got some really good cards there. Let's try and build a deck now too. I got a load of each energy card so we'll never run out. Here."
const LINE_HARD_BEFORE_MATCH := "Okay, let me see how good your first deck is!"

const LINE_WON := "That was so much fun!! You're definitely better than me!"
const LINE_LOST := "I must be better at this than I thought I would be! I didn't think I would win that"
const LINES_NEW_BONUS := ["I got 2 special bonus pack of cards for buying all 3 decks at once so you can have one!"]
const TEXT_NEW_BONUS := "You got starter card pack!"
const LINES_RULES_BONUS := ["That deck came with a special bonus pack of cards for buying all 3 decks at once so you can have one!"]
const TEXT_RULES_BONUS := "You got bonus card pack!"
const LINES_AFTER_BONUS := [
	"Your deck can only keep 60 cards at a time so you will need to take some cards out of your deck first to put these ones in.",
	"Just put them all in your card binder for now and then you can change your deck whenever you want.",
	"He also gave me a load of each energy card so we'll never run out. Here.",
]
const TEXT_ENERGY := "You received a load of energy cards!"
const LINES_COIN := [
	"You can also play matches using whatever coin you want. Your starter deck came with a coin and a case to keep them all in.",
	"Put the coin I just gave you in there, for your next match you can use that instead if you prefer it!",
]
const LINES_NEW_GOODBYE := [
	"I've really gotta shoot off and get the shop open. El has gone out for the day and is back tonight, Alexander is covering the shop for me this evening but I don't know what he's doing otherwise.",
	"If you're still interested in fishing then you should swing by and I'll hook you up with a rod!",
	"Catch ya later.",
]
const LINES_RULES_GOODBYE := [
	"Alexander is covering the shop for me so if you still want to fish then you should swing by and pick up that rod from him.",
	"Catch ya later.",
]
const LINE_GET_PACKS := "I'm going to get some packs from the card mart later, I need to make my deck stronger! You should go and get some packs from the card mart too."
const LINE_ENERGY_ADVANCED := "I also got a load of each energy card so we'll never run out. Here."
const LINES_ADVANCED_GOODBYE := [
	"I've gotta go back to the shop for now, If you're still interested in fishing then you should swing by and I'll hook you up with a rod!",
	"Catch ya later.",
]

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------
var _olly: CutsceneActor = null
var _speaker: Dictionary = {}
var _profile: Dictionary = {}
var _arriving: bool = false
var _watching_exit: bool = false


# ============================================================
# STAGE HELPERS — the map script asks these before installing
# ============================================================

static func stage() -> String:
	return str(GameState.progress.get(STAGE_KEY, STAGE_NONE))


static func _set_stage(new_stage: String) -> void:
	GameState.progress[STAGE_KEY] = new_stage
	GameState.save_progress()


## True when this map load should hand over to the cutscene. Read `entering_from`
## before BaseMapScene._ready() clears it.
static func should_run(entering_from: String) -> bool:
	match stage():
		STAGE_DONE:
			return false
		STAGE_NONE:
			# "rules": he runs up as the taxi call ends (Celeste_Harbour hands over); a reload
			# before the match runs it again wherever the player is in the harbour.
			if GameState.get_intro_profile().get("olly_meets", "door") == "taxi":
				return not GameState.progress.get("taxi_intro_pending", false)
			# Everyone else: the first time out of the front door after the arrival night.
			return entering_from == "Player_House_Downstairs" and not GameState.is_arrival_night()
		_:
			return true


# ============================================================
# ENTRY POINT
# ============================================================

func run() -> void:
	_profile = GameState.get_intro_profile()
	_speaker = speaker_for(OLLY_NAME)
	match stage():
		STAGE_NONE:
			await _play_arrival()
			await _play_handover()
		STAGE_BUILD:
			await _resume_after_build()
		STAGE_BATTLE:
			await _play_after_battle()
		_:
			finish()


# ============================================================
# ARRIVAL
# ============================================================

func _play_arrival() -> void:
	# Out of the front door the player steps down off the doorstep to meet him; at the taxi
	# ("rules") they are already standing outside.
	var from_door: bool = _profile.get("olly_meets", "door") != "taxi"
	var meet: Vector2 = player.global_position + Vector2(0.0, PLAYER_STEP_OUT if from_door else 0.0)
	GameState.progress[MEET_KEY] = [meet.x, meet.y]
	GameState.save_progress()

	_olly = spawn(OLLY_NAME, _speaker.get("sprite", ""), Vector2(meet.x + ARRIVAL_START_DX, ARRIVAL_PATH_Y), "left")
	_speaker["node"] = _olly

	# Both at once: he comes up the street while the player steps out of the doorway.
	_olly.walk_path([
		Vector2(meet.x, ARRIVAL_PATH_Y),
		Vector2(meet.x, meet.y + MEET_GAP),
	], RUN_SPEED)
	_arriving = true

	if from_door:
		await wait(STEP_OUT_DELAY)
		await player_walk_to(meet, PLAYER_STEP_OUT_SPEED, "down")
	player_face("down")

	if _olly.is_walking():
		await _olly.path_finished
	_arriving = false
	_olly.face("up")


## Slows him by how much of the route is left. See the TWEAKABLE speeds.
func _process(_delta: float) -> void:
	if _arriving and _olly != null and is_instance_valid(_olly) and _olly.is_walking():
		var left: float = _path_left(_olly)
		var speed: float = RUN_SPEED
		if left < WALK_DISTANCE:
			speed = WALK_SPEED
		elif left < SLOW_DISTANCE:
			speed = SLOW_SPEED
		elif left < EASE_DISTANCE:
			speed = EASE_SPEED
		_olly.set_walk_speed(speed)
	if _watching_exit:
		_check_exit()


func _path_left(actor: CutsceneActor) -> float:
	var total := 0.0
	var from: Vector2 = actor.global_position
	for p in actor.remaining_path():
		total += from.distance_to(p)
		from = p
	return total


# ============================================================
# THE HANDOVER — which deck, then the match
# ============================================================

func _play_handover() -> void:
	var at_taxi: bool = _profile.get("olly_meets", "door") == "taxi"
	await say_all(_speaker, LINES_OPEN_EVENING if at_taxi else LINES_OPEN_MORNING)

	match str(_profile.get("deck_kind", "basic")):
		"basic":
			await say_all(_speaker, LINES_NEW_GIVE)
			GameState.grant_starter_deck(GameState.STARTER_DECK_BASIC)
			await _reveal_cards(TEXT_NEW_GOT, BASIC_DECK_SHOWCASE)
			await say_all(_speaker, LINES_NEW_BEFORE_MATCH)
		"starter", "advanced":
			var starter: bool = _profile.get("deck_kind") == "starter"
			await say_all(_speaker, LINES_PICK_STARTER if starter else LINES_PICK_DECK)
			close_box()
			var deck_name := await _pick_deck()
			GameState.grant_starter_deck(deck_name)
			await _reveal_cards(TEXT_GOT_DECK % deck_name,
					IntroDeckChoice.SHOWCASE[GameState.intro_deck_suffix()][GameState.progress[GameState.INTRO_PAIR_KEY]])
			await say_all(_speaker, LINES_PICKED_BEFORE_MATCH)
		"packs":
			await say_all(_speaker, LINES_HARD_PACKS)
			close_box()
			PackOpeningManager.open_packs(GameState.HARD_MODE_DRAFT_PACKS)
			await PackOpeningManager.all_packs_opened
			await say(_speaker, LINE_HARD_AFTER_PACKS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			_go_build_deck()
			return
	close_box()
	_start_battle()


## The three decks over the map, then "are you sure?". No puts the decks back up.
func _pick_deck() -> String:
	var suffix := GameState.intro_deck_suffix()
	var choice := IntroDeckChoice.show_on(map._ui_layer, suffix)
	while true:
		var pair: String = await choice.picked
		if await ask(_speaker, TEXT_CONFIRM_PICK % (pair + suffix)):
			choice.queue_free()
			GameState.progress[GameState.INTRO_PAIR_KEY] = pair
			GameState.save_progress()
			return pair + suffix
		choice.reoffer()
	return ""


## Cards flipped up with the big "You got..." notice. Returns once it is cleared.
func _reveal_cards(text: String, card_ids: Array, with_sound: bool = true) -> void:
	if with_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager.show_card_reveal(text, card_ids, func(): line_advanced.emit())
	await line_advanced
	close_box()


## A gifted pack: shown on the gift overlay, then opened like any booster.
func _gift_pack(text: String, art_id: String) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager.show_item_reveal(text, "res://Image_Assets/Packs/" + art_id + ".png",
			func(): line_advanced.emit())
	await line_advanced
	close_box()
	PackOpeningManager.open_packs([art_id])
	await PackOpeningManager.all_packs_opened


# ============================================================
# HARD MODE — the deck builder and back
# ============================================================

func _go_build_deck() -> void:
	close_box()
	_set_stage(STAGE_BUILD)
	_open_deck_builder()


func _open_deck_builder() -> void:
	var scene_path: String = map.get_scene_path()
	GameState.save_menu_return_state(scene_path, player.position, "down")
	GameState.draft_deck_return_scene = scene_path
	SoundManagerScript.stop_bgm()
	MapManager.cutscene_active = false
	SceneCache.change_scene(DECK_BUILDER_SCENE)


func _resume_after_build() -> void:
	# Quit out of the deck builder before saving: straight back in.
	if not GameState.has_saved_deck():
		_open_deck_builder()
		return
	_spawn_opposite_player()
	await wait(POST_BATTLE_PAUSE)
	await say(_speaker, LINE_HARD_BEFORE_MATCH)
	close_box()
	_start_battle()


# ============================================================
# THE BATTLE
# ============================================================

func _start_battle() -> void:
	var entry := CharacterSchedule.find_opponent(
		MAP_NAME, OLLY_NAME, GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if entry.is_empty():
		push_error("OllyIntroCutscene: no '%s' entry in %s's character file" % [OLLY_NAME, MAP_NAME])
		_set_stage(STAGE_DONE)
		finish()
		return
	_set_stage(STAGE_BATTLE)
	MapManager.start_forced_battle(entry, {
		"deck":          GameState.olly_intro_deck(),
		"prize_cards":   int(_profile.get("olly_prizes", 4)),
		"cash_reward":   str(_profile.get("olly_cash", 50)),
		"coin_reward":   str(_profile.get("olly_coin", "")),
		"retry_on_loss": bool(_profile.get("olly_retry", false)),
		"tutorial":      str(_profile.get("tutorial", "")),
	})


## Back on the map after the match. A "new"/"rules" loss never gets here -- the outro
## restarts the match until it is won -- so a loss here is played/expert/Hard Mode.
func _play_after_battle() -> void:
	_spawn_opposite_player()
	GameState.set_flag(GameState.INTRO_DONE_FLAG)
	await wait(POST_BATTLE_PAUSE)

	var won: bool = GameState.has_beaten_opponent(OLLY_NAME)
	await say(_speaker, LINE_WON if won else LINE_LOST)

	match str(_profile.get("deck_kind", "basic")):
		"basic":
			await say_all(_speaker, LINES_NEW_BONUS)
			await _gift_pack(TEXT_NEW_BONUS, "starter1_a")
			await say_all(_speaker, LINES_AFTER_BONUS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await say_all(_speaker, LINES_COIN + LINES_NEW_GOODBYE)
		"starter":
			await say_all(_speaker, LINES_RULES_BONUS)
			var pair: String = GameState.progress.get(GameState.INTRO_PAIR_KEY, "Fire Shock")
			await _gift_pack(TEXT_RULES_BONUS, GameState.BONUS_PACK_FOR_PAIR.get(pair, "bonus1_a"))
			await say_all(_speaker, LINES_AFTER_BONUS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await say_all(_speaker, LINES_COIN + LINES_RULES_GOODBYE)
		"advanced":
			await say(_speaker, LINE_GET_PACKS)
			await say(_speaker, LINE_ENERGY_ADVANCED)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await say_all(_speaker, LINES_ADVANCED_GOODBYE)
		"packs":
			# The energy came before the deck builder.
			await say(_speaker, LINE_GET_PACKS)
			await say_all(_speaker, LINES_ADVANCED_GOODBYE)
	close_box()

	_set_stage(STAGE_DONE)
	GameState.progress.erase(MEET_KEY)
	GameState.save_progress()

	# He jogs off down the path and away left towards FISH; the player watches him go.
	_olly.walk_path([
		_olly.global_position + Vector2(0.0, EXIT_DOWN),
		_olly.global_position + Vector2(-EXIT_LEFT, EXIT_DOWN),
	], EXIT_SPEED)
	_watching_exit = true


func _spawn_opposite_player() -> void:
	var meet_arr: Array = GameState.progress.get(MEET_KEY, [])
	var meet: Vector2 = player.global_position
	if meet_arr.size() == 2:
		meet = Vector2(float(meet_arr[0]), float(meet_arr[1]))
		player.global_position = meet
	_olly = spawn(OLLY_NAME, _speaker.get("sprite", ""), meet + Vector2(0.0, MEET_GAP), "up")
	_speaker["node"] = _olly
	player_face("down")


func _check_exit() -> void:
	if _olly == null or not is_instance_valid(_olly) or player == null:
		_watching_exit = false
		finish()
		return
	var offset: Vector2 = _olly.global_position - player.global_position
	if absf(offset.x) < OFFSCREEN_MARGIN_X and absf(offset.y) < OFFSCREEN_MARGIN_Y \
			and _olly.is_walking():
		# Turn to follow him with the eyes once he heads off sideways.
		if offset.y > 20.0 and absf(offset.x) > absf(offset.y):
			player_face("left")
		return
	_watching_exit = false
	finish()
