class_name TownHallTrioCutscene
extends Cutscene

# ============================================================
# TOWN HALL - REGISTRATION MORNING WITH ELLIE AND ALEXANDER (day 3)
# ============================================================
# 2026-11-12 (user spec). Registration opens on the morning of day 3 and Ellie and Alexander
# are queuing for it (the "Ellie" / "Alexander" placeholders in TownHall.json, day 3 M).
# The morning is LOCKED until the player registers (morning_locked(), read by GameState): the
# clock stops at MORNING_POINTS_CAP (10am) and only the Young Twins are out to battle.
#
#   1. Talk to either of them: their line, then the one you talked to scoots to the middle
#      of the line (behind the Challenger at the counter) and the player is walked in next
#      to them, everyone facing the desk.
#   2. The queue chat, the Challenger at the front leaves, Alexander and Ellie take their
#      turns at the counter, then the player's.
#   3. The receptionist: Yes pays; No or no cash brings Ellie over (and she pays).
#   4. The gift (the phone map). Registering adds REGISTERED_POINTS (+20) to the clock.
#   5. Back with the two of them: a FORCED match with Ellie, then one with Alexander while she
#      stays to watch. Each is +MATCH_POINTS (+10) won or lost ("time_points" override, read by
#      the outro), so the player always leaves in the afternoon: 0 + 20 + 10 + 10 = 12pm, or
#      later with the Twins' 20 carried over. The matches are against the overworld entries
#      (Ellie 4 in Celeste Harbour, Alexander 4 in the Fish Shop), so beating them here counts there.
#   6. Ellie's comment on Alexander's match, then they say goodbye and walk out of the door.
#
# STAGE_KEY carries the scene across the matches (the map is unloaded). Town_Hall.gd asks
# should_resume() on EVERY load and calls run_resume(): back from a match it carries on, and a
# quit (mid-match or between them) replays the lines leading into the match that is owed.
#
# ALL POSITIONS are in the NPC container's space - the same numbers as TownHall.json - and
# converted with _g(). The queue placeholders are swapped for cutscene actors while it runs.
# ============================================================

const DAY := 3
const MORNING := "Morning"
const MAP_NAME := "TownHall"

## TWEAKABLE -- the clock can't pass this many points on morning 3 until the player has the
## TCG Tracker App. 20 of 40 = 10am (the two Young Twins' first wins).
const MORNING_POINTS_CAP := 20
## TWEAKABLE -- added to the clock on registering, and per Town Hall match (won or lost).
const REGISTERED_POINTS := 20
const MATCH_POINTS := 10

const STAGE_KEY          := "town_hall_trio_stage"
const STAGE_NONE         := ""
const STAGE_ELLIE_NEXT   := "ellie_next"     # registered; Ellie's match is owed
const STAGE_ELLIE_BATTLE := "ellie_battle"
const STAGE_ALEX_BATTLE  := "alex_battle"
const STAGE_DONE         := "done"
const SIDE_KEY           := "town_hall_trio_side"   # which side Ellie and Alexander stood (+1 right)
const ELLIE_RESULT_KEY   := "town_hall_trio_ellie_result"
const ALEX_RESULT_KEY    := "town_hall_trio_alex_result"

# The queue (names in TownHall.json / All_NPC_Constant_Data.json).
const ELLIE_NAME := "Ellie"
const ALEX_NAME  := "Alexander"
const FRONT_NAME := "Challenger"
const QUEUE_BEHIND := ["Challenger 2", "Challenger 3", "Challenger 4"]
const RECEPTIONIST := "Town Hall Receptionist"

# The overworld opponents the two matches count as (the user's day 3 Afternoon entries --
# looked up in the afternoon, since the matches themselves are played in the morning).
const ELLIE_BATTLE := {"map": "Celeste_Harbour", "name": "Ellie 4", "time": "Afternoon"}
const ALEX_BATTLE  := {"map": "Fish_Shop", "name": "Alexander 4", "time": "Afternoon"}

# ------------------------------------------------------------
# TWEAKABLE -- where everyone stands (NPC container space, world px)
# ------------------------------------------------------------
const CENTRE_X : float = 112.0     # straight behind the counter spot
const COUNTER  := Vector2(112.0, 75.0)   # in front of the desk, facing the receptionist
const ROW_Y    : float = 103.0     # the line the three of them stand in
const GAP      : float = 20.0      # side by side in the line
const ROUND_X  : float = 26.0      # how far out to the side someone walks to get round another
const TALK_Y   : float = 86.0      # stepping back from the counter to face the line
const ASIDE_SIDE : float = -1.0    # which side Ellie and Alexander step aside to: -1 left (less crowded)
const ASIDE_Y  : float = 96.0      # Ellie and Alexander stood aside chatting (between the line and the counter)
const ASIDE_NEAR : float = 44.0    # Alexander, from the centre line
const ASIDE_FAR  : float = 66.0    # Ellie, from the centre line (clear of the desk's left edge)
const GROUP_Y  : float = 126.0    # the player stood with them afterwards
const STEP_OUT : float = 20.0      # the player steps this far out from the counter on the way back
const EXIT_OUT : float = 84.0      # out past everyone, from the centre line, before heading for the door
const QUEUE_NUDGE : float = 8.0    # the rest of the queue shuffling up as the player goes to the desk
const QUEUE_STEP  : float = 40.0   # ...and stepping up again once the player has finished
const SPARE_SPOT := Vector2(225.0, 95.0)    # where the Challenger goes to stand after registering
const DOOR      := Vector2(111.0, 210.0)    # on the door mat (the floor ends at about y 216); they fade out here
const EXIT_Y    : float = 196.0    # the row they walk along to the mat

const WALK_SPEED  : float = 55.0
const SCOOT_SPEED : float = 40.0
const EXIT_SPEED  : float = 70.0
const DOOR_FADE   : float = 0.35
const LOOK_PAUSE  : float = 0.5    # Ellie looks at the player this long before turning to Alexander
const BEAT        : float = 0.35
const AWKWARD_PAUSE : float = 1.0  # after each of Alexander's "Soooo......." / "Seen any good films" lines
## The Town Hall draws its people in tree order (no y-sort), so while the scene runs the cast
## and the player are layered by height instead: higher up the screen = further back. Kept
## below the map's z 10 overlay layers (plant tops, fossil tops).
const DEPTH_Z_BASE : int = 1

# ------------------------------------------------------------
# DIALOGUE
# ------------------------------------------------------------
const Q_ELLIE_1 := "I'm so excited, I've just built my first deck too and I'm so ready to use it!"
const Q_ALEX_1  := "Yep me too, I got some really cool cards this morning so I'm so ready to try them."
const Q_ELLIE_2 := "I don't think I'll be good enough to enter the Elder Challenge but I'll try anyway"
const Q_ALEX_2  := "It's okay because I'm going to win it all anyway."
const Q_ELLIE_3 := "........."
const Q_ELLIE_4 := [
	"I don't know why I'm kind of nervous to take part.",
	"I don't even care about winning that much, just as long as I can beat Alexander at least once I'll be happy",
]
const Q_ELLIE_5 := "If I can't beat him, I hope you at least win!!!!"
const Q_ALEX_3  := "I asked if they had a different league for pro players like me but apparently not."
const Q_ALEX_4  := "Soooo......."
const Q_ALEX_5  := "Seen any good films lately?..."
const Q_ELLIE_6 := "Okay your turn, hope you remembered to bring your registration fee!"

## The receptionist's usual first meeting (MapManager.REGISTRAR_MEET), reworded for a player
## who has just queued up with everyone else.
const DESK_MEET := [
	"Good [TIME]! Are you here for the registration too? I've been so busy running non stop registrations and you look like you know how to play!",
	"It's only a one off registration fee of $50 and all proceeds go right back into making the town better!",
	"By registering you will also gain access to the TCG Tracker App, making it easier for you to find like minded opponents to play against.",
	"Be warned though, without registering you won't be able to enter the Gym Hero Challenge! To be granted access you'll also need to defeat all 3 of our Card Elders and earn the Medal of Elders.",
]
const DESK_ASK_AGAIN := "Have you changed your mind, are you registering now for $50?"

const ELLIE_NO := [
	"What??? Have you changed your mind or something? You were the one who wanted to play the most out of all of us!",
	"Don't be silly now, we've both signed up and it's not even that much",
]
const ELLIE_NO_AGAIN_1 := "........."
const ELLIE_NO_AGAIN_2 := "Look if you're worried about the cost of registering, I'll just pay your fee, it's really not that much"
const ELLIE_PAYS       := "I'll get this, here's [NAME]'s entrance fee."
const ELLIE_BROKE_1    := "Oh you should have said if you didn't have any cash on you."
const ELLIE_BROKE_2    := "Here."
const ELLIE_BROKE_3    := "I know you'll pay me back don't worry about it"

## Straight into Ellie's match - no Yes/No (2026-11-12, user: both matches are forced).
const ELLIE_FIRST_MATCH := "This will be my first official match after registering!"
## Alexander, straight after Ellie's match, then his (forced) match.
const ALEX_AFTER_ELLIE_PLAYER_LOST := "Wow [NAME] you must be bad! You won't beat me then haha"
const ALEX_AFTER_ELLIE_PLAYER_WON  := "Well of course you can beat Ellie but you'll never beat me!"
## Ellie watched Alexander's match: her comment, to him.
const ELLIE_ALEX_WON  := "Ugh... I wish you'd just stop winning for once!!!"
const ELLIE_ALEX_LOST := "Finally! See you're not as good as you think you are!!!"
const ELLIE_BYE       := ["Well I'm going to use this new app to go out and find some other people to play against then!", "Byeeeee"]
const ALEX_BYE        := ["I'm gonna go help Olly in the shop actually, I promised I would go earlier for my shift.", "See yuh."]

## The receptionist's line while the morning is locked and someone talks to him directly.
const DESK_QUEUE_LINE := "Ho ho, hold your horses! There's a queue for registration I'm afraid, you'll have to wait your turn in line with everyone else."

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------
var _c: Node2D = null                 # the NPC container
var _ellie: CutsceneActor = null
var _alex: CutsceneActor = null
var _front: CutsceneActor = null
var _behind: Array = []               # CutsceneActors standing in for QUEUE_BEHIND
var _hidden: Array = []               # world nodes hidden while their actors stand in
var _sp_ellie: Dictionary = {}
var _sp_alex: Dictionary = {}
var _sp_desk: Dictionary = {}
var _side: float = 1.0                # +1: Ellie and Alexander stand aside to the right


# ============================================================
# STATIC -- what the map and GameState ask
# ============================================================

static func stage() -> String:
	return str(GameState.progress.get(STAGE_KEY, STAGE_NONE))


static func _set_stage(new_stage: String) -> void:
	GameState.progress[STAGE_KEY] = new_stage
	GameState.save_progress()


static func _result(key: String) -> String:
	return str(GameState.progress.get(key, ""))


## Morning 3 before the TCG Tracker App: the clock is held (GameState.add_time_points /
## time_slot_change_due) and the receptionist sends people to the back of the queue.
static func morning_locked() -> bool:
	return GameState.get_date() == DAY and GameState.get_time() == MORNING \
		and not GameState.has_item(MapManager.TRACKER_ITEM)


## The queue scene is still to play.
static func is_pending() -> bool:
	return morning_locked() and not GameState.has_flag(RegistrationReminders.TRIO_DONE_FLAG)


## Talking to Ellie or Alexander in the queue starts the scene. Call after the map's _ready().
static func register(map_scene: Node2D) -> void:
	if not is_pending():
		return
	for npc_name in [ELLIE_NAME, ALEX_NAME]:
		MapManager.npc_interact_overrides[npc_name] = func(npc: Node) -> void:
			var cs := TownHallTrioCutscene.new()
			cs.install(map_scene)
			cs.run_from_talk(npc)


## Registered but the two matches aren't over: any load of the Town Hall (back from a match, or
## a quit part-way) hands straight over to run_resume().
static func should_resume() -> bool:
	return stage() in [STAGE_ELLIE_NEXT, STAGE_ELLIE_BATTLE, STAGE_ALEX_BATTLE]


# ============================================================
# ENTRY POINTS
# ============================================================

## The player talked to Ellie or Alexander in the queue.
func run_from_talk(npc: Node) -> void:
	_setup()
	var talked_alex: bool = str(npc.npc_name) == ALEX_NAME
	var sp: Dictionary = (_sp_alex if talked_alex else _sp_ellie).duplicate()
	sp["node"] = npc
	var line: String = str(npc.meet_text)
	if line != "":
		await say(sp, line)
	close_box()
	_swap_in_cast()

	# The one they talked to moves to the middle of the line, the other keeps beside them,
	# and the player is walked in on the far side of whoever they talked to.
	#   talked to Alexander:  Ellie | Alexander | player   (the two of them step left)
	#   talked to Ellie:      player | Ellie | Alexander   (the two of them step right)
	var ellie_x: float = CENTRE_X - GAP if talked_alex else CENTRE_X
	var alex_x: float = CENTRE_X if talked_alex else CENTRE_X + GAP
	var player_x: float = CENTRE_X + GAP if talked_alex else CENTRE_X - GAP
	_side = -1.0 if talked_alex else 1.0     # Ellie's side of the line, where they go aside later
	GameState.progress[SIDE_KEY] = _side
	var target := _g(Vector2(player_x, ROW_Y))
	var walk_in: Array = [Vector2(target.x, player.global_position.y), target]
	await _together([
		func(): await _ellie.glide_to(_g(Vector2(ellie_x, ROW_Y)), SCOOT_SPEED),
		func(): await _alex.glide_to(_g(Vector2(alex_x, ROW_Y)), SCOOT_SPEED),
		func(): await player_walk_path(walk_in, WALK_SPEED),
	])
	_all_face_up()
	await wait(BEAT)
	await _queue_chat()


## The Town Hall loaded part-way through the matches: back from one, or a quit. The three of
## them stand where they were, and the scene carries on from whatever is owed - a quit replays
## the line leading into the match it interrupted, then the match starts again.
func run_resume() -> void:
	_setup()
	_side = float(GameState.progress.get(SIDE_KEY, 1.0))
	_ellie = _spawn_as(ELLIE_NAME, _aside_ellie(), "")
	_alex = _spawn_as(ALEX_NAME, _aside_alex(), "")
	player.global_position = _g(_group_spot())
	_face_group()
	_queue_as_left()
	await wait(BEAT * 2.0)
	match stage():
		STAGE_ELLIE_BATTLE when _result(ELLIE_RESULT_KEY) != "":
			await _alex_match()
		STAGE_ALEX_BATTLE when _result(ALEX_RESULT_KEY) != "":
			await _after_alex_match()
		STAGE_ALEX_BATTLE:
			await _alex_match()
		_:
			await _ellie_match()


# ============================================================
# THE QUEUE
# ============================================================

func _queue_chat() -> void:
	# Ellie (to the player), Alexander (to the player), Ellie, Alexander (to Ellie), Ellie (to him).
	await _line_to(_ellie, _sp_ellie, Q_ELLIE_1, player)
	await _line_to(_alex, _sp_alex, Q_ALEX_1, player)
	await say(_sp_ellie, Q_ELLIE_2)
	await _line_to(_alex, _sp_alex, Q_ALEX_2, _ellie)
	await _line_to(_ellie, _sp_ellie, Q_ELLIE_3, _alex)
	close_box()

	# The Challenger at the front is done: out to the side and off to a spare spot in the room.
	var out_x: float = COUNTER.x + ROUND_X * 2.0
	_walk_free(_front, [_g(Vector2(out_x, COUNTER.y)), _g(Vector2(out_x, SPARE_SPOT.y)), _g(SPARE_SPOT)],
		WALK_SPEED, "down")
	await wait(0.6)

	# Alexander up to the counter; Ellie and the player close the gap behind him.
	var ellie_slot: float = CENTRE_X + GAP * 0.5 * _ellie_side_now()   # Ellie keeps her side
	var player_slot: float = CENTRE_X - GAP * 0.5 * _ellie_side_now()
	var alex_route: Array = []
	if absf(_alex.global_position.x - _g(Vector2(CENTRE_X, 0)).x) > 1.0:
		alex_route.append(_g(Vector2(_c.to_local(_alex.global_position).x, TALK_Y)))
	alex_route.append(_g(COUNTER))
	await _together([
		func(): await _alex.glide_path(alex_route, WALK_SPEED, "up"),
		func():
			await wait(0.4)
			await _ellie.glide_to(_g(Vector2(ellie_slot, ROW_Y)), SCOOT_SPEED, "", true),
		func():
			await wait(0.4)
			await player_walk_to(_g(Vector2(player_slot, ROW_Y)), SCOOT_SPEED),
	])
	_all_face_up()
	await wait(BEAT)

	await say_all(_sp_ellie, Q_ELLIE_4)
	await _line_to(_ellie, _sp_ellie, Q_ELLIE_5, player)
	close_box()

	# Alexander done: back from the counter to stand in front of the two of them, looking down.
	await _alex.glide_to(_g(Vector2(CENTRE_X, TALK_Y)), SCOOT_SPEED, "up", true)
	_alex.face("down")
	await say(_sp_alex, Q_ALEX_3)
	close_box()

	# Ellie looks at the player, a beat, at Alexander, then goes round him to the counter
	# while he steps back into her place.
	_ellie.face_position(player.global_position)
	await wait(LOOK_PAUSE)
	_ellie.face_position(_alex.global_position)
	await wait(BEAT)
	var e_side: float = _ellie_side_now()
	var ellie_place := _ellie.global_position
	var round_x: float = CENTRE_X + ROUND_X * e_side
	await _together([
		func(): await _ellie.glide_path([_g(Vector2(round_x, ROW_Y)), _g(Vector2(round_x, COUNTER.y)), _g(COUNTER)], WALK_SPEED),
		func():
			await wait(0.5)
			await _alex.glide_path([ellie_place], SCOOT_SPEED),
	])
	_ellie.face("up")
	_alex.face("up")
	player_face("up")
	await wait(BEAT)

	# User: a one second pause after each of these two, with the box cleared.
	await say(_sp_alex, Q_ALEX_4)
	close_box()
	await wait(AWKWARD_PAUSE)
	await _line_to(_alex, _sp_alex, Q_ALEX_5, player)
	close_box()
	await wait(AWKWARD_PAUSE)

	# Ellie done: she comes back towards the two of them.
	await _ellie.glide_to(_g(Vector2(CENTRE_X, TALK_Y)), SCOOT_SPEED, "", true)
	_ellie.face("down")
	await say(_sp_ellie, Q_ELLIE_6)
	close_box()

	await _to_the_desk()


## One after another (user, 2026-11-12): the player goes round Ellie to the counter on their own
## side (left: out left, up, back right to the desk) while Ellie and Alexander wait; THEN the
## two of them step aside to chat - always to the LEFT, the less crowded side; THEN the rest of
## the queue shuffles up a little.
func _to_the_desk() -> void:
	var p_side: float = signf(_c.to_local(player.global_position).x - CENTRE_X)
	if p_side == 0.0:
		p_side = -1.0
	_side = ASIDE_SIDE
	GameState.progress[SIDE_KEY] = _side
	var p_round: float = CENTRE_X + ROUND_X * p_side
	await player_walk_path([_g(Vector2(p_round, ROW_Y)), _g(Vector2(p_round, COUNTER.y)), _g(COUNTER)], WALK_SPEED)
	player_face("up")
	await wait(BEAT)
	await _together([
		func():
			await _alex.glide_path([_g(Vector2(_c.to_local(_alex.global_position).x, ASIDE_Y)), _g(_aside_alex())], SCOOT_SPEED)
			_alex.face("left" if _side < 0.0 else "right"),
		func():
			await wait(0.3)
			# Left along her own row (above Alexander's), then into her spot.
			await _ellie.glide_path([_g(Vector2(_aside_ellie().x, _c.to_local(_ellie.global_position).y)), _g(_aside_ellie())], SCOOT_SPEED)
			_ellie.face("right" if _side < 0.0 else "left"),
	])
	var queue_jobs: Array = []
	for a in _behind:
		queue_jobs.append(func():
			await a.glide_to(a.global_position + Vector2(0, -QUEUE_NUDGE), SCOOT_SPEED, "up", true))
	await _together(queue_jobs)
	player_face("up")
	await wait(BEAT)
	await _registration()


# ============================================================
# THE DESK
# ============================================================

func _registration() -> void:
	var broke: bool = GameState.get_cash() < MapManager.REGISTRATION_FEE
	await say_all(_sp_desk, DESK_MEET)
	var yes := await ask(_sp_desk, MapManager.REGISTRAR_ASK)
	var ellie_came := false
	if broke:
		# No cash, whatever they answered: Ellie comes over and pays.
		await _ellie_comes_over()
		ellie_came = true
		await say(_sp_ellie, ELLIE_BROKE_1)
		_ellie.face("up")
		await say(_sp_ellie, ELLIE_BROKE_2)
		_ellie.face_position(player.global_position)
		await say(_sp_ellie, ELLIE_BROKE_3)
		await _gift(false)
	elif yes:
		await _gift(true)
	else:
		await _ellie_comes_over()
		ellie_came = true
		await say_all(_sp_ellie, ELLIE_NO)
		player_face("up")
		if await ask(_sp_desk, DESK_ASK_AGAIN):
			await _gift(true)
		else:
			player_face_position(_ellie.global_position)
			await say(_sp_ellie, ELLIE_NO_AGAIN_1)
			await say(_sp_ellie, ELLIE_NO_AGAIN_2)
			_ellie.face("up")
			await say(_sp_ellie, ELLIE_PAYS)
			await _gift(false)
	await _back_to_the_two(ellie_came)


## Ellie spots it ([!]), walks over beside the player at the counter, and they face each other.
func _ellie_comes_over() -> void:
	close_box()
	await SpeechEmote.play(_ellie, "!")
	var beside := _g(Vector2(COUNTER.x + GAP * _side, COUNTER.y))
	await _ellie.glide_path([Vector2(_ellie.global_position.x, beside.y), beside], WALK_SPEED)
	_ellie.face_position(player.global_position)
	player_face_position(_ellie.global_position)


## The receptionist's usual closing lines, then the phone comes up. `pay`: the fee comes out of
## the player's cash (false: Ellie paid it).
func _gift(pay: bool) -> void:
	player_face("up")
	if pay:
		GameState.add_cash(-MapManager.REGISTRATION_FEE)   # saves
	# Registered, all in one go so a quit can't split it: the app, the scene's flag, the +20 on the
	# clock (no longer capped - the morning unlocks with the app) and Ellie's match owed next.
	# The slot itself moves at the end of a match (or the next map load), never mid-scene.
	GameState.add_item_to_collection(MapManager.TRACKER_ITEM)   # saves
	GameState.set_flag(RegistrationReminders.TRIO_DONE_FLAG)
	GameState.add_time_points(REGISTERED_POINTS)
	_set_stage(STAGE_ELLIE_NEXT)
	await say(_sp_desk, MapManager.REGISTRAR_THANKS)
	await say(_sp_desk, MapManager._card_elder_start_line())
	await say(_sp_desk, MapManager.REGISTRAR_LOGIN)
	close_box()
	if map.has_method("refresh_time_visuals"):
		map.refresh_time_visuals()
	await _show_tracker_app()


## MapManager._reveal_tracker_app, awaited: the phone map opens with the "You received" notice
## over it, and this returns once the player has closed the map again.
func _show_tracker_app() -> void:
	var phone := WorldMap.open(map, player)
	phone.hold_for_message()
	var ui: CanvasLayer = MapManager._ui_layer
	var old_layer: int = ui.layer
	ui.layer = WorldMap.LAYER + 1
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gift_received)
	MapManager.cutscene_speaker = _sp_desk
	MapManager._pending_ok_action = func(): line_advanced.emit()
	MapManager._show_large_message_with_ok(MapManager.REGISTRAR_RECEIVED)
	await line_advanced
	if is_instance_valid(ui):
		ui.layer = old_layer
	close_box()
	if is_instance_valid(phone):
		phone.release_hold()
	while WorldMap.is_open() and is_inside_tree():
		await get_tree().process_frame
	reclaim_player()   # closing the map handed movement back
	if "_clock" in map and map._clock != null and is_instance_valid(map._clock) and map._clock.has_method("peek"):
		map._clock.peek()


## Back over to Alexander (with Ellie, if she came to pay), the queue steps up, then the offers.
func _back_to_the_two(ellie_came: bool) -> void:
	# Ellie (if she came over) sets off first, out along the counter and back to her spot; the
	# player steps out a little, down past Alexander and across to stand with them.
	var group := _g(_group_spot())
	var step_x: float = CENTRE_X + STEP_OUT * _side
	var player_route: Array = [_g(Vector2(step_x, COUNTER.y)), _g(Vector2(step_x, GROUP_Y)), group]
	var jobs: Array = []
	if ellie_came:
		jobs.append(func():
			await _ellie.glide_path([_g(Vector2(CENTRE_X + ASIDE_FAR * _side, COUNTER.y)), _g(_aside_ellie())], WALK_SPEED))
		jobs.append(func():
			await wait(0.3)
			await player_walk_path(player_route, WALK_SPEED))
	else:
		jobs.append(func(): await player_walk_path(player_route, WALK_SPEED))
	await _together(jobs)
	_face_group()
	# The queue: the next one up to the counter, the rest step up behind.
	var queue_jobs: Array = []
	for i in _behind.size():
		var a: CutsceneActor = _behind[i]
		if i == 0:
			queue_jobs.append(func(): await a.glide_path([Vector2(a.global_position.x, _g(COUNTER).y + 0.0), _g(COUNTER)], WALK_SPEED, "up"))
		else:
			queue_jobs.append(func():
				await wait(0.5)
				await a.glide_to(a.global_position + Vector2(0, -QUEUE_STEP), WALK_SPEED, "up"))
	_together(queue_jobs)   # runs on under the conversation
	await wait(BEAT)
	await _ellie_match()


## Ellie's match, no question asked.
func _ellie_match() -> void:
	await say(_sp_ellie, ELLIE_FIRST_MATCH)
	_start_battle(ELLIE_BATTLE, ELLIE_RESULT_KEY, STAGE_ELLIE_BATTLE)


## Alexander chimes in on Ellie's result, then his match. Ellie stays to watch.
func _alex_match() -> void:
	var player_won := _result(ELLIE_RESULT_KEY) == "won"
	await say(_sp_alex, ALEX_AFTER_ELLIE_PLAYER_WON if player_won else ALEX_AFTER_ELLIE_PLAYER_LOST)
	_start_battle(ALEX_BATTLE, ALEX_RESULT_KEY, STAGE_ALEX_BATTLE)


## Ellie turns to Alexander for her comment on his match, then the goodbyes.
func _after_alex_match() -> void:
	var alex_won := _result(ALEX_RESULT_KEY) == "lost"   # the result is from the player's side
	_ellie.face_position(_alex.global_position)
	await say(_sp_ellie, ELLIE_ALEX_WON if alex_won else ELLIE_ALEX_LOST)
	_ellie.face_position(player.global_position)
	await _goodbyes(ELLIE_BYE)


## Ellie's goodbye and off out of the door, then Alexander's.
func _goodbyes(ellie_lines: Array) -> void:
	await say_all(_sp_ellie, ellie_lines)
	close_box()
	await _out_of_the_door(_ellie)
	_ellie = null
	_alex.face_position(player.global_position)
	await say_all(_sp_alex, ALEX_BYE)
	close_box()
	await _out_of_the_door(_alex)
	_alex = null
	_finish_scene()


func _out_of_the_door(actor: CutsceneActor) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var here := _c.to_local(actor.global_position)
	var x: float = CENTRE_X + EXIT_OUT * _side
	await actor.glide_path([
		_g(Vector2(x, here.y)),
		_g(Vector2(x, EXIT_Y)),
		_g(Vector2(DOOR.x, EXIT_Y)),
		_g(DOOR),
	], EXIT_SPEED)
	var fade := actor.create_tween()
	fade.tween_property(actor, "modulate:a", 0.0, DOOR_FADE)
	await fade.finished
	actor.queue_free()


func _finish_scene() -> void:
	_set_stage(STAGE_DONE)
	GameState.save_current_location(map.get_scene_path(), player.position)
	_release_cast()
	finish()


# ============================================================
# THE MATCHES
# ============================================================

func _start_battle(who: Dictionary, result_key: String, battle_stage: String) -> void:
	close_box()
	var entry := CharacterSchedule.find_opponent(str(who["map"]), str(who["name"]),
		DAY, str(who["time"]), MapManager.evaluate_condition)
	if entry.is_empty():
		push_error("TownHallTrioCutscene: no '%s' entry in %s's character file" % [who["name"], who["map"]])
		await _goodbyes(ELLIE_BYE)
		return
	GameState.progress.erase(result_key)
	GameState.progress[SIDE_KEY] = _side
	_set_stage(battle_stage)
	# Saved standing with the two of them, so a quit mid-match comes back to the lead-in line.
	GameState.save_current_location(map.get_scene_path(), player.position)
	MapManager.start_forced_battle(entry, {
		"retry_on_loss": false,
		"result_key":    result_key,
		"time_points":   MATCH_POINTS,   # won or lost (Match_End_Outro_Script)
		# Their own map, so the match reads the very same entry as the overworld one.
		"opponent_map":  str(who["map"]),
	})


# ============================================================
# THE CAST
# ============================================================

func _setup() -> void:
	_c = MapManager._opponents_container
	if _c == null or not is_instance_valid(_c):
		_c = map
	_sp_ellie = speaker_for(ELLIE_NAME, "npcs")
	_sp_alex = speaker_for(ALEX_NAME, "npcs")
	_sp_desk = speaker_for(RECEPTIONIST, "npcs")
	for node in _world_nodes([RECEPTIONIST]).values():
		_sp_desk["node"] = node


## The queue's world NPCs are hidden and cutscene actors stand in their places.
func _swap_in_cast() -> void:
	var nodes := _world_nodes([ELLIE_NAME, ALEX_NAME, FRONT_NAME] + QUEUE_BEHIND)
	for n in nodes:
		var node: Node2D = nodes[n]
		node.freeze()
		node.visible = false
		_hidden.append(node)
	_ellie = _spawn_from(nodes, ELLIE_NAME)
	_alex = _spawn_from(nodes, ALEX_NAME)
	_front = _spawn_from(nodes, FRONT_NAME)
	for n in QUEUE_BEHIND:
		var a := _spawn_from(nodes, n)
		if a != null:
			_behind.append(a)


func _spawn_from(nodes: Dictionary, npc_name: String) -> CutsceneActor:
	if not nodes.has(npc_name):
		return null
	var node: Node2D = nodes[npc_name]
	return _spawn_as(npc_name, _c.to_local(node.global_position), "up")


func _spawn_as(npc_name: String, local_pos: Vector2, facing: String) -> CutsceneActor:
	var sp := speaker_for(npc_name, "npcs")
	var a := spawn(npc_name, str(sp.get("sprite", "")), _g(local_pos), facing if facing != "" else "up")
	if npc_name == ELLIE_NAME:
		_sp_ellie["node"] = a
	elif npc_name == ALEX_NAME:
		_sp_alex["node"] = a
	return a


## The hidden queue NPCs come back where their actors ended up (it is the afternoon by now and
## they go at the next load), and the actors go.
func _release_cast() -> void:
	var actors := {FRONT_NAME: _front}
	for i in _behind.size():
		if i < QUEUE_BEHIND.size():
			actors[QUEUE_BEHIND[i]] = _behind[i]
	for node in _hidden:
		if not is_instance_valid(node):
			continue
		var n: String = str(node.npc_name)
		if n == ELLIE_NAME or n == ALEX_NAME:
			node.queue_free()   # they walked out of the door
			continue
		var a: CutsceneActor = actors.get(n, null)
		if a != null and is_instance_valid(a):
			node.global_position = a.global_position
			node.current_facing = a.current_facing
			node.animated_sprite.play("idle_" + a.current_facing)
		node.visible = true
		node.resume_movement()
	_hidden.clear()


## Still the morning when the hall reloads mid-scene: its queue NPCs spawn back at their file
## spots, so stand them where the scene left them (the Challenger off at the spare spot, the
## next one at the counter, the other two stepped up behind).
func _queue_as_left() -> void:
	var nodes := _world_nodes([FRONT_NAME] + QUEUE_BEHIND)
	for n in nodes:
		var node: Node2D = nodes[n]
		var at: Vector2 = _c.to_local(node.global_position)
		match n:
			FRONT_NAME:
				at = SPARE_SPOT
			"Challenger 2":
				at = COUNTER
			_:
				at.y -= QUEUE_NUDGE + QUEUE_STEP
		node.global_position = _g(at)


func _world_nodes(names: Array) -> Dictionary:
	var out := {}
	if _c == null:
		return out
	for child in _c.get_children():
		if child.is_in_group("npcs") and "npc_name" in child and str(child.npc_name) in names:
			out[str(child.npc_name)] = child
	return out


# ============================================================
# HELPERS
# ============================================================

## Every frame: the actors and the player stacked by their y (see DEPTH_Z_BASE).
func _process(_delta: float) -> void:
	var people: Array = []
	for a in [_ellie, _alex, _front] + _behind:
		if a != null and is_instance_valid(a):
			people.append(a)
	if player != null and is_instance_valid(player):
		people.append(player)
	people.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	for i in people.size():
		people[i].z_index = DEPTH_Z_BASE + i


func _exit_tree() -> void:
	if player != null and is_instance_valid(player):
		player.z_index = 0


func _g(local_pos: Vector2) -> Vector2:
	return _c.to_global(local_pos)


func _aside_alex() -> Vector2:
	return Vector2(CENTRE_X + ASIDE_NEAR * _side, ASIDE_Y)


func _aside_ellie() -> Vector2:
	return Vector2(CENTRE_X + ASIDE_FAR * _side, ASIDE_Y)


func _group_spot() -> Vector2:
	return Vector2(CENTRE_X + (ASIDE_NEAR + ASIDE_FAR) * 0.5 * _side, GROUP_Y)


## -1 / +1: which side of the centre line Ellie is on right now.
func _ellie_side_now() -> float:
	var s := signf(_c.to_local(_ellie.global_position).x - CENTRE_X)
	return s if s != 0.0 else _side


func _all_face_up() -> void:
	for a in [_ellie, _alex]:
		if a != null and is_instance_valid(a):
			a.face("up")
	player_face("up")


## Afterwards the three of them stand in a little group: the two of them look at the player.
func _face_group() -> void:
	player_face("up")
	if _ellie != null:
		_ellie.face_position(player.global_position)
	if _alex != null:
		_alex.face_position(player.global_position)


## A line said turned toward `target` (the player or another actor), then back to the desk.
func _line_to(actor: CutsceneActor, sp: Dictionary, text: String, target: Node2D) -> void:
	actor.face_position(target.global_position)
	await say(sp, text)
	actor.face("up")


## Runs every callable at once and returns when they have all finished.
func _together(jobs: Array) -> void:
	var left := [jobs.size()]
	for job: Callable in jobs:
		var run := func() -> void:
			await job.call()
			left[0] -= 1
		run.call()
	while left[0] > 0 and is_inside_tree():
		await get_tree().process_frame


## Glide an actor along a route without waiting for it, facing `facing` at the end.
func _walk_free(actor: CutsceneActor, points: Array, speed: float, facing: String) -> void:
	if actor == null:
		return
	await actor.glide_path(points, speed)
	if is_instance_valid(actor):
		actor.face(facing)
