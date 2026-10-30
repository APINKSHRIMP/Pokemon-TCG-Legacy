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
# Down onto the path he arrived along, west (left) along it to EXIT_PATH_X -- the brick
# path running north, between its two lampposts (Lamp132/133 at x -1209/-1305) -- then
# straight up it towards FISH. Glided, not walked: physics walking snagged him on the
# garden wall.
const EXIT_SPEED     : float = 150.0
const EXIT_PATH_X    : float = -1257.0
const EXIT_RUN_UP    : float = 1100.0
const OFFSCREEN_MARGIN_X : float = 430.0
const OFFSCREEN_MARGIN_Y : float = 234.0
const POST_BATTLE_PAUSE  : float = 0.6

# The cards flipped up for each gift. Basic energy is never granted (it is unlimited);
# the "load of energy cards" is shown, not given.
# The boxed-deck art shown when a deck is handed over (Image_Assets/Packs/<id>.png).
const DECK_ART_BASIC := "starterdeck1_d"
const DECK_ART_FOR_PAIR := {"Fire Shock": "starterdeck1_a", "Grass Psy": "starterdeck1_b", "Water Fight": "starterdeck1_c"}
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
const LINE_HARD_AFTER_PACKS := "Wow!! We both got some really good cards there. I got a load of each energy card too so we'll never run out. Here."
# After the energy cards have been shown and put away.
const LINES_HARD_BUILD := [
	"Hey, let's try building a deck right now! I bet we could put something together.",
	"Let's both each build a deck with these cards now and then have a match.",
]
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
# ISSUE #476: the deck walkthrough's lines. LINES_AFTER_BONUS[0] opens it; the binder line is
# dropped there (the walkthrough builds the deck instead) and the energy line follows it.
const LINE_ENERGY_AFTER_BONUS := "He also gave me a load of each energy card so we'll never run out. Here."
const NEWBY_BETTER_DECK := "Better Deck"
const TEXT_WALK_BUILDER := "You can look at your owned cards, edit your deck, remove any cards in it and add any new cards on this screen"
const LINES_WALK_BETTER := [
	"With those cards you got in your bonus pack, I would have a deck that looks a little more like this.",
	"It'll have a much stronger selection of cards and you should be able to do a lot better with it!",
	"Don't forget to tweak your deck to your own liking, don't just take my advice!!",
]
const TEXT_WALK_LOAD := "It's a good idea to write down all your different deck ideas so you can quickly switch from one deck to another. You can go back to using your first deck if you want by pressing Load Deck."
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
# "played" only (it wakes up on morning 2, the café breakfast -- CafeBreakfastCutscene): said
# after the energy, before the goodbye. He is not at the café himself for this save.
const LINES_CAFE_MORNING := [
	"El and Alexander have just gone for breakfast at Café Mieux. I got them each a deck too.",
	"I gave Alexander the day off because it's a bank holiday. A lot of stuff's closed today but I've got stuff to do so I'll be open.",
	# ISSUE #482: the Card Mart nudge. Olly isn't at the café himself, so "get there" not "get here".
	"Before you get there, call in at the Card Mart and get yourself some new packs!",
	"Make sure your deck is the best it can be, they'll want to battle when you get there!",
	"El told me to tell you to meet them at the café ASAP, she said they'll be waiting for you.",
	"There isn't much to do around here this morning so you might as well at least stop by the Cafe for a drink if nothing else.",
]
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
			# Restored to the intro checkpoint (GameState INTRO CHECKPOINT): he runs up again.
			if GameState.progress.get(GameState.INTRO_RESTART_KEY, false):
				return true
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
			# CHECKPOINT: the player has just stepped outside. Quitting any time before the
			# match is decided comes back to here, with nothing Olly gave them.
			GameState.progress.erase(GameState.INTRO_RESTART_KEY)
			GameState.save_current_location(map.get_scene_path(), player.position)
			GameState.save_intro_checkpoint(true)
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
			await _reveal_art(TEXT_NEW_GOT, DECK_ART_BASIC)
			await say_all(_speaker, LINES_NEW_BEFORE_MATCH)
		"starter", "advanced":
			var starter: bool = _profile.get("deck_kind") == "starter"
			await say_all(_speaker, LINES_PICK_STARTER if starter else LINES_PICK_DECK)
			close_box()
			var deck_name := await _pick_deck()
			GameState.grant_starter_deck(deck_name)
			await _reveal_art(TEXT_GOT_DECK % deck_name,
					DECK_ART_FOR_PAIR.get(GameState.progress[GameState.INTRO_PAIR_KEY], DECK_ART_BASIC))
			await say_all(_speaker, LINES_PICKED_BEFORE_MATCH)
		"packs":
			await say_all(_speaker, LINES_HARD_PACKS)
			close_box()
			# The draft has its own music from the first pack to the last, then the harbour's
			# own track comes back up under the conversation.
			SoundManagerScript.crossfade_bgm(SoundManagerScript.BGM_DRAFT_TIME, 0.4, 0.4)
			PackOpeningManager.open_packs(GameState.HARD_MODE_DRAFT_PACKS)
			await PackOpeningManager.all_packs_opened
			SoundManagerScript.crossfade_bgm(map.get_bgm_path())
			await say(_speaker, LINE_HARD_AFTER_PACKS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await say_all(_speaker, LINES_HARD_BUILD)
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
## The energy cards fly up one after another (fly = true) rather than flipping.
func _reveal_cards(text: String, card_ids: Array, with_sound: bool = true, fly: bool = true) -> void:
	if with_sound:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager.show_card_reveal(text, card_ids, func(): line_advanced.emit(), fly)
	await line_advanced
	close_box()


## A deck box or pack fading up on the gift overlay with the big notice.
func _reveal_art(text: String, art_id: String) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager.show_pack_reveal(text, "res://Image_Assets/Packs/" + art_id + ".png",
			func(): line_advanced.emit())
	await line_advanced
	close_box()


## A gifted pack: shown on the gift overlay, then opened like any booster. Once only:
## after the match is decided there is no checkpoint, so a quit during the closing
## conversation replays it -- without a second pack.
const GIFT_DONE_KEY := "olly_intro_pack_given"

func _gift_pack(text: String, art_id: String) -> void:
	if GameState.progress.get(GIFT_DONE_KEY, false):
		return
	# ISSUE #487: the pack on the reveal glides into the opening's rect and opens from there.
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_item_acquired)
	MapManager.show_pack_reveal(text, "res://Image_Assets/Packs/" + art_id + ".png",
			func(): line_advanced.emit())
	await line_advanced
	var shown: TextureRect = MapManager._single_gift_pack_rect()
	if shown != null:
		MapManager.message_panel.visible = false
		await MapManager._glide_rect_to_pack_rect(shown)
		PackOpeningManager.open_packs([art_id], 0.0)
		await get_tree().process_frame
		close_box()
	else:
		close_box()
		PackOpeningManager.open_packs([art_id])
	await PackOpeningManager.all_packs_opened
	GameState.progress[GIFT_DONE_KEY] = true
	GameState.save_progress()


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
	# CHECKPOINT (Hard Mode): the drafted deck is saved. Quitting the match from here
	# comes back to this line and the match, with the same packs and deck.
	GameState.save_current_location(map.get_scene_path(), player.position)
	GameState.save_intro_checkpoint(false)
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
		"olly_stack":    bool(_profile.get("olly_stack", false)),
		"tutorial":      str(_profile.get("tutorial", "")),
	})


## Back on the map after the match. A "new"/"rules" loss never gets here -- the outro
## restarts the match until it is won -- so a loss here is played/expert/Hard Mode.
func _play_after_battle() -> void:
	_spawn_opposite_player()
	GameState.set_flag(GameState.INTRO_DONE_FLAG)
	await wait(POST_BATTLE_PAUSE)

	var won: bool = GameState.has_beaten_opponent(OLLY_NAME)
	# The newby player's next match plays the key tips (Tutorial_Director "tips"). Armed once:
	# a quit during this conversation replays it, but must not re-arm spent tips.
	if _profile.get("tutorial", "") == "newby" and not GameState.progress.get("tutorial_tips_armed", false):
		GameState.progress["tutorial_tips_armed"] = true
		GameState.progress[GameState.TUTORIAL_TIPS_KEY] = true
		GameState.save_progress()
	await say(_speaker, LINE_WON if won else LINE_LOST)

	match str(_profile.get("deck_kind", "basic")):
		"basic":
			await say_all(_speaker, LINES_NEW_BONUS)
			await _gift_pack(TEXT_NEW_BONUS, "starter1_a")
			# ISSUE #476: the deck builder walkthrough, Basic Starter Deck -> Better Deck.
			await _deck_walkthrough("starter1_a", GameState.STARTER_DECK_BASIC, NEWBY_BETTER_DECK)
			await say(_speaker, LINE_ENERGY_AFTER_BONUS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await _say_coin_lines()
			await say_all(_speaker, LINES_NEW_GOODBYE)
		"starter":
			await say_all(_speaker, LINES_RULES_BONUS)
			var pair: String = GameState.progress.get(GameState.INTRO_PAIR_KEY, "Fire Shock")
			var bonus_art: String = GameState.BONUS_PACK_FOR_PAIR.get(pair, "bonus1_a")
			await _gift_pack(TEXT_RULES_BONUS, bonus_art)
			# ISSUE #476: "<pair> Starter Deck" -> "<pair> Deck", from the bonus pack's cards.
			await _deck_walkthrough(bonus_art, pair + " Starter Deck", pair + " Deck")
			await say(_speaker, LINE_ENERGY_AFTER_BONUS)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			await _say_coin_lines()
			await say_all(_speaker, LINES_RULES_GOODBYE)
		"advanced":
			await say(_speaker, LINE_GET_PACKS)
			await say(_speaker, LINE_ENERGY_ADVANCED)
			await _reveal_cards(TEXT_ENERGY, ENERGY_SHOWCASE, false)
			if GameState.get_familiarity() == GameState.FAMILIARITY_PLAYED:
				await say_all(_speaker, LINES_CAFE_MORNING)
			await say_all(_speaker, LINES_ADVANCED_GOODBYE)
		"packs":
			# The energy came before the deck builder.
			await say(_speaker, LINE_GET_PACKS)
			await say_all(_speaker, LINES_ADVANCED_GOODBYE)
	close_box()

	_set_stage(STAGE_DONE)
	GameState.progress.erase(MEET_KEY)
	# "played": he has been played this morning, so he is not at the café breakfast.
	if GameState.get_familiarity() == GameState.FAMILIARITY_PLAYED:
		GameState.progress[CafeBreakfastCutscene.OLLY_GONE_FLAG] = true
	GameState.save_progress()

	# He jogs down to the path, along it and up towards FISH; the player watches him go.
	var start: Vector2 = _olly.global_position
	var on_path := Vector2(start.x, maxf(start.y, ARRIVAL_PATH_Y))
	_watching_exit = true
	_olly.glide_path([
		on_path,
		Vector2(EXIT_PATH_X, on_path.y),
		Vector2(EXIT_PATH_X, on_path.y - EXIT_RUN_UP),
	], EXIT_SPEED)


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
	if absf(offset.x) < OFFSCREEN_MARGIN_X and absf(offset.y) < OFFSCREEN_MARGIN_Y:
		# Follow him with the eyes: down while he is below, then the way he heads off.
		if absf(offset.x) > absf(offset.y):
			player_face("left" if offset.x < 0.0 else "right")
		else:
			player_face("down" if offset.y > 0.0 else "up")
		return
	_watching_exit = false
	finish()

# ============================================================
# ISSUE #476 — THE MENU WALKTHROUGHS (deck builder, coin case)
# ============================================================
# Olly's "your deck can only keep 60 cards" line stays on screen (it can't be cleared yet, no caret)
# while the escape menu opens with the Cards & Deck tile glowing and everything else dimmed, then the
# deck builder opens on its own: the bonus pack's cards fly into their slots. The line can be cleared
# once both screens have been up for WALK_MIN_VIEW seconds. Then the deck is rebuilt into the better
# one while Olly talks, renamed, saved, and the menu closes back to the map. The coin case gets the
# same treatment for "Put the coin I just gave you in there". TWEAKABLE below.
const WALK_MIN_VIEW    := 2.0     # seconds each screen is up before the line can be cleared
const WALK_PULSE_SCALE := 1.06    # the highlighted tile's grow
const WALK_PULSE_TIME  := 0.5     # one grow-and-shrink
const WALK_DIM         := Color(0.3, 0.3, 0.3, 1.0)
const WALK_CONVERT_SECONDS := 5.0
const WALK_UI_LAYER    := 12      # the message box above the menu (10) and sub-menu (11) layers
const DECK_MENU_TILE   := "deck/deck_mode_background"
const COIN_MENU_TILE   := "coin/coin_case_mode_background"
const DECK_SCENE       := "res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn"
const COIN_SCENE       := "res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn"
const WALK_DONE_KEY    := "olly_intro_walkthrough_done"

var _walk_ui_layer_was: int = 1
var _walk_ring: Control = null
var _walk_pulse: Tween = null


func _deck_walkthrough(pack_art: String, from_deck: String, to_deck: String) -> void:
	if GameState.progress.get(WALK_DONE_KEY, false):
		await say_all(_speaker, LINES_AFTER_BONUS.slice(0, 2))
		return
	var started := Time.get_ticks_msec()
	_hold_line(_speaker, LINES_AFTER_BONUS[0])
	var menu: Node = await _open_menu_on(DECK_MENU_TILE)
	await wait(WALK_MIN_VIEW)
	var builder: Node = await _open_sub_menu(DECK_SCENE)
	if builder == null or not builder.has_method("walkthrough_begin"):
		await _release_line()
		await _close_walk_menu()
		return
	builder.walkthrough_begin()
	var shown := Time.get_ticks_msec()
	await builder.walkthrough_reveal_new_cards("base1", _count_ids(GameState.FIXED_PACKS.get(pack_art, [])))
	var left: float = WALK_MIN_VIEW - float(Time.get_ticks_msec() - shown) / 1000.0
	if left > 0.0:
		await wait(left)
	await _release_line()
	await _system_line(TEXT_WALK_BUILDER)

	# The better deck: anything it needs that the player doesn't own yet is given first.
	var target := _read_deck(GameState.STARTER_DECKS_FOLDER + to_deck + ".json")
	_grant_missing(target)
	var converting := [true]
	var run := func() -> void:
		await builder.walkthrough_convert_to(target, WALK_CONVERT_SECONDS)
		converting[0] = false
	run.call()
	await say_all(_speaker, LINES_WALK_BETTER)
	close_box()
	while converting[0] and is_inside_tree():
		await get_tree().process_frame
	await builder.walkthrough_save_as(to_deck)
	await wait(0.6)
	await _system_line(TEXT_WALK_LOAD)
	builder.walkthrough_end()
	GameState.progress[WALK_DONE_KEY] = true
	GameState.save_progress()
	await _close_walk_menu()


func _say_coin_lines() -> void:
	await say(_speaker, LINES_COIN[0])
	if GameState.progress.get(WALK_DONE_KEY + "_coin", false):
		await say(_speaker, LINES_COIN[1])
		return
	_hold_line(_speaker, LINES_COIN[1])
	await _open_menu_on(COIN_MENU_TILE)
	await wait(WALK_MIN_VIEW)
	var case: Node = await _open_sub_menu(COIN_SCENE)
	if case != null and case.has_method("walkthrough_place_coins"):
		if not case.is_node_ready() or case.grid.get_child_count() == 0:
			await case.coins_built
		var coins: Array = []
		for c in GameState.progress.get("coins", []):
			coins.append(String(c) if String(c).ends_with(".png") else String(c) + ".png")
		await case.walkthrough_place_coins(coins)
		await wait(WALK_MIN_VIEW * 0.5)
	await _release_line()
	GameState.progress[WALK_DONE_KEY + "_coin"] = true
	GameState.save_progress()
	await _close_walk_menu()


## A line that stays up and can't be cleared until _release_line().
func _hold_line(speaker: Dictionary, text: String) -> void:
	_walk_ui_layer_was = map._ui_layer.layer
	map._ui_layer.layer = WALK_UI_LAYER
	MapManager.show_cutscene_message(text, speaker, func(): line_advanced.emit())
	MapManager.message_panel.hold_advance(true)


func _release_line() -> void:
	MapManager.message_panel.hold_advance(false)
	await line_advanced
	close_box()


func _system_line(text: String) -> void:
	map._ui_layer.layer = WALK_UI_LAYER
	# No speaker and nobody being talked to: the plain system box.
	MapManager.current_opponent = null
	MapManager.current_npc = null
	await say({}, text)
	close_box()


## The escape menu, opened for the player, with `tile` glowing (the selection ring) and pulsing and
## every other tile dimmed. Its own keys are switched off.
func _open_menu_on(tile: String) -> Node:
	if map._menu_instance == null or not is_instance_valid(map._menu_instance):
		map._open_menu_overlay()
	player.lock_movement()
	var menu: Node = map._menu_instance
	menu.set_process_input(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var target := menu.get_node_or_null(tile) as Control
	if target == null:
		return menu
	var tile_box := target.get_parent() as Control
	for child in menu.get_children():
		if child is Control and child != tile_box and child.name != "black_background":
			(child as Control).modulate = WALK_DIM
		elif child == tile_box:
			(child as Control).modulate = Color.WHITE
	var ring_layer := Control.new()
	ring_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(ring_layer)
	_walk_ring = ring_layer
	UIKit.add_selection_ring(ring_layer, target, float(UITheme.mi("panel_radius")))
	tile_box.pivot_offset = target.position + target.size * 0.5
	_walk_pulse = tile_box.create_tween().set_loops()
	_walk_pulse.tween_property(tile_box, "scale", Vector2.ONE * WALK_PULSE_SCALE, WALK_PULSE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	_walk_pulse.tween_property(tile_box, "scale", Vector2.ONE, WALK_PULSE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	return menu


func _open_sub_menu(scene_path: String) -> Node:
	if _walk_pulse != null and _walk_pulse.is_valid():
		_walk_pulse.kill()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	map.open_submenu_overlay(scene_path)
	var layer: CanvasLayer = map._submenu_canvas_layer
	if layer == null or layer.get_child_count() == 0:
		return null
	var inst: Node = layer.get_child(0)
	if not inst.is_node_ready():
		await inst.ready
	return inst


func _close_walk_menu() -> void:
	if _walk_pulse != null and _walk_pulse.is_valid():
		_walk_pulse.kill()
	_walk_pulse = null
	if _walk_ring != null and is_instance_valid(_walk_ring):
		_walk_ring.queue_free()
	_walk_ring = null
	map._close_menu_overlay()
	map._ui_layer.layer = _walk_ui_layer_was
	# Closing the menu hands the player back; the cutscene still owns them.
	player.lock_movement()
	await wait(0.3)


func _count_ids(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = int(out.get(id, 0)) + 1
	return out


func _read_deck(path: String) -> Dictionary:
	var out := {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Array:
		for e in data:
			out[String(e.get("id", ""))] = int(e.get("count", 0))
	return out


## Gives the player whatever the target deck needs beyond what they own.
func _grant_missing(target: Dictionary) -> void:
	var missing: Array = []
	for cid in target:
		var set_id := String(cid).split("-")[0]
		var owned := 0
		var data = JSON.parse_string(FileAccess.get_file_as_string(GameState.OWNED_CARDS_FOLDER + set_id + "_player_owned_cards.json"))
		if data is Dictionary:
			for e in data.get("owned_cards", []):
				if String(e.get("card_id", "")) == cid:
					owned = int(e.get("owned", 0))
		for n in maxi(0, int(target[cid]) - owned):
			missing.append(cid)
	if not missing.is_empty():
		GameState.give_cards(",".join(missing))

