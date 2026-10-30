class_name CafeBreakfastCutscene
extends Cutscene

# ============================================================
# CAFÉ MIEUX — BREAKFAST ON MORNING 2 (the second cutscene)
# ============================================================
# Morning 2 (a bank holiday, no other opponents out). Ellie and Alexander are sat at
# the middle table on the bottom row of the café patio, and Olly too unless the
# player has already played him this morning:
#
#   "new" / "rules"  started on day 1: Ellie rings on the way through the living room
#                    (Player_House_Downstairs) and Olly is at the café.
#   "played"         started on day 2: Olly was beaten (or not) outside the house and
#                    mentions the café in his goodbye (OllyIntroCutscene), so he is NOT
#                    here -- OLLY_GONE_FLAG is already raised.
#
# Ellie 3, Alexander 3 and Olly 2 are ordinary OPPONENT entries (card icon, a dot on
# any future map) in Celeste_Harbour.json. Talking to any of them hands over to this
# script (MapManager.opponent_interact_overrides) instead of their challenge box:
# their meet line as a plain box, a fade, the player sat at the table, the chat, and
# one forced match after another -- Olly (if here), Ellie, Alexander. Every match is
# played once, won or lost, and the clock is held still for them (no_time_advance);
# once Alexander's is played the map comes back up in the afternoon (settle_after_load)
# and the closing scene plays there.
# Saying No to anyone stands the player up below the table; talking to any of the
# table again reads their repeat line and sits them back down at the same question.
#
# STAGE_KEY in the save says where the morning is. A match crosses a scene boundary,
# so on the way back the map asks should_resume() and calls run_after_battle(); a
# quit mid-match is settled by settle_after_load() before the map builds its cast.
#   quit in Olly's match       -> the whole scene again (Olly still there)
#   quit in Ellie's match      -> the whole scene again (Olly gone if he was played)
#   quit in Alexander's match  -> as if they had said No to him (the "chicken" stage)
#   quit after Alexander's     -> it is the afternoon, the morning is over
# ============================================================

const STAGE_KEY          := "cafe_stage"
const STAGE_NONE         := ""              # not sat down yet: the whole chat plays
const STAGE_OLLY_ASK     := "olly_ask"      # said No to Olly
const STAGE_OLLY_BATTLE  := "olly_battle"
const STAGE_OLLY_DONE    := "olly_done"     # Olly played and gone; Ellie's turn is next
const STAGE_ELLIE_ASK    := "ellie_ask"     # said No to Ellie
const STAGE_ELLIE_BATTLE := "ellie_battle"
const STAGE_ELLIE_DONE   := "ellie_done"    # Ellie played; her reaction + Alexander's ask next
const STAGE_ALEX_ASK     := "alex_ask"      # said No to Alexander ("chicken")
const STAGE_ALEX_BATTLE  := "alex_battle"   # stays set through the closing scene
const STAGE_DONE         := "done"

# The outro writes "won"/"lost" (from the PLAYER's side) under these keys.
const OLLY_RESULT_KEY  := "cafe_olly_result"
const ELLIE_RESULT_KEY := "cafe_ellie_result"
const ALEX_RESULT_KEY  := "cafe_alex_result"
## Raised once Olly has nothing more to do at the café: his match here is played, or he
## was played outside the house that morning ("played"). Gates the Olly 2 entry.
const OLLY_GONE_FLAG := "cafe_olly_gone"
## Ellie's breakfast call in the living room has been taken.
const CALL_DONE_FLAG := "cafe_call_done"

const OLLY_NAME  := "Olly 2"
const ELLIE_NAME := "Ellie 3"
const ALEX_NAME  := "Alexander 3"
const MAP_NAME   := "Celeste_Harbour"
const CAFE_DATE  := 2
const CAFE_TIME  := "Morning"
const PROTO_ROD  := "Proto_Rod"

# ------------------------------------------------------------
# TWEAKABLE — the table (GLOBAL positions; the seats match the character file)
# ------------------------------------------------------------
const SEAT_PLAYER := Vector2(1982.0, 1117.0)   # bottom left chair, facing right
const SEAT_ALEX   := Vector2(1981.0, 1094.0)   # top left, facing right
const SEAT_ELLIE  := Vector2(2031.0, 1094.0)   # top right, facing left
const SEAT_OLLY   := Vector2(2032.0, 1116.0)   # bottom right, facing left
const SEAT_FACING := {OLLY_NAME: "left", ELLIE_NAME: "left", ALEX_NAME: "right"}
# Where a player who says No is stood, below the table with their back to it.
const STAND_SPOT  := Vector2(2007.0, 1152.0)
# A loaded save this close to the player's chair is moved to STAND_SPOT (a quit while sat).
const SEAT_SNAP_RADIUS : float = 30.0
const POST_BATTLE_PAUSE : float = 0.6
# Ellie turns to look down at Olly for this long before turning back.
const ELLIE_LOOK_BACK : float = 1.0

# ------------------------------------------------------------
# TWEAKABLE — the walks
# ------------------------------------------------------------
# The brick path below the café runs left-right at about y 1246-1321.
const PATH_Y : float = 1283.0
# Olly: down to the path, left to the path going up into the town hall plaza
# (its arch is at about x 1396), then up it. Freed the moment he leaves the camera.
const OLLY_EXIT_SPEED : float = 95.0
const OLLY_EXIT_X     : float = 1396.0
const OLLY_EXIT_UP    : float = 300.0
# The closing scene. Alexander and the player stand a few steps below the table facing
# each other; Ellie comes out of the café door, steps down, sidesteps right to the aisle
# between the two tables' chairs, walks down past them, then left to stand between them.
const ALEX_END_SPOT   := Vector2(1985.0, 1162.0)
const PLAYER_END_SPOT := Vector2(2029.0, 1162.0)
const ELLIE_DOOR_SPOT := Vector2(2047.0, 982.0)
const ELLIE_STEP_Y    : float = 1004.0     # "walks down a bit"
const ELLIE_AISLE_X   : float = 2063.0     # halfway between the chairs either side
const ELLIE_STOP      := Vector2(2007.0, 1182.0)
const ELLIE_WALK_SPEED : float = 70.0
# ISSUE #498: the walk from the table to those spots (no fade). Alexander goes round the
# left of the table, the player steps down below it then across.
const ALEX_STAND_X       : float = 1958.0
const PLAYER_STEP_DOWN_Y : float = 1140.0
const ELLIE_DOOR_FADE    : float = 0.3     # going through the café door, and back out
const ELLIE_INSIDE_TIME  : float = 1.5
# Leaving: both walk down to the path and off to the left. Ellie turns a little past
# its centre line, Alexander (half a step to her left) a little before it.
const LEAVE_SPEED       : float = 75.0
const ELLIE_TURN_Y      : float = PATH_Y + 10.0
const ALEX_TURN_Y       : float = PATH_Y - 14.0
const ALEX_LEAVE_X      : float = 1990.0
const LEAVE_RUN_LEFT    : float = 900.0
# Off camera at 2.5x zoom (the player sees roughly 768x432 world px).
const OFFSCREEN_MARGIN_X : float = 430.0
const OFFSCREEN_MARGIN_Y : float = 250.0

# ------------------------------------------------------------
# DIALOGUE
# ------------------------------------------------------------
const OPEN_ELLIE_1 := "So how was the tournament then? I watched some of the live highlights and it looked really good."
const OPEN_ALEX_1  := "Yeah, didn't you basically get front row seats too so you could see the whole thing?"
const OPEN_ELLIE_2 := [
	"I can't wait for the Gym Challenge to start, that'll be really good to watch... At least I know the rules now so I can actually follow a match along.",
	"There's not much to do today, given it's the bank holiday nearly everything is shut so we're just sitting here practicing this all morning.",
]
const OPEN_OLLY_1  := "Yeah nearly everything is shut but some of us still have things to do and can't just sit here playing cards all day..."
const OPEN_ELLIE_3 := "I still don't know how to play very well at all. I don't know if I'm just no good or if Alexander is cheating."
const OPEN_ALEX_2  := "Yeah I'm absolutely not cheating, I've just been destroying El all morning, I'm obviously just way better."
const OPEN_OLLY_2  := "And obviously I'm not going to lose to you either!"
const OPEN_ELLIE_PLEASE := "...... Can you help me practice instead? Pleeeeeaase?"
const OLLY_BEFORE_ASK := "I've got to open the shop like now, let me have a quick match first."
const OLLY_ASK        := "Are you ready?"
const OLLY_NO         := "Well I can't hang about much longer, if you've got something to do first make it quick."
const OLLY_ASK_AGAIN  := "You all good now champ?"
const OLLY_BYE        := "Well as fun as that was, some of us have places to be. I'll catch you all later!"
const OLLY_ROD        := "[NAME], make sure you come by the shop ASAP right? I've still got a rod for you and a favour to ask."

const ELLIE_MY_TURN   := "Well, now Ol has gone, it's my turn!"
# ISSUE #488: as Olly walks off. TWEAKABLE: ELLIE_SIGH_AT -- how far along his walk off screen (0-1)
# she looks down after him; ELLIE_SIGH_AFTER -- the pause once he's gone before she carries on.
const ELLIE_SIGH       := "Sigh… Don't worry then I'll pay..."
const ELLIE_SIGH_AT    : float = 0.5
const ELLIE_SIGH_AFTER : float = 0.5
const ELLIE_NO        := ["What?? Do you need the toilet or something?", "Alright fine but I'm not leaving until I win!!!"]
const ELLIE_ASK_AGAIN := "So you ARE going to play against me?"
const ELLIE_NO_AGAIN  := "Stop rage baiting me."

# After Ellie's match. Each entry is [speaker, line]; "E" Ellie, "A" Alexander.
const AFTER_ELLIE_PLAYER_LOST := [
	["E", "Yesssssss! I knew I wasn't that terrible at it! Sorry, no offence..."],
	["E", "Alexander MUST be cheating I KNEW it!"],
	["A", "Right, just because you can't beat me doesn't mean I'm cheating. You just got lucky that time that's all."],
	["E", "Luck has nothing to do with it! I won absolutely fair and square there."],
	["A", "Look, I'll have a match with [NAME] right here right now and absolutely destroy their deck in front of you to prove it."],
]
const AFTER_ELLIE_PLAYER_WON := [
	["E", "Noooooo! I really am just that terrible. Unless you're cheating too..."],
	["A", "I'm telling you I'm NOT CHEATING. Just because you can't beat either of us doesn't mean we're cheating."],
	["E", "Well I still think you are, there's no way I lose so badly every time."],
	["A", "Look, I'll have a match with [NAME] right here right now and absolutely destroy their deck in front of you to prove it."],
]
const ALEX_ASK     := "Are you ready to lose now?"
const ALEX_CHICKEN := "Chicken, bwoock, bock, bock, bock bwwooooocck."

# After Alexander's match, by the player's two results: "<ellie>_<alex>", w = player won.
const AFTER_ALEX := {
	"l_w": [
		["E", "SEE!!! I KNEW YOU WERE CHEATING! YOU CAN'T WIN IF YOU CAN'T CHEAT, YOU'RE SUCH A LITTLE RATTATA!"],
		["A", "Ugh... I was NOT cheating I SWEAR down. I clearly just got really unlucky that time."],
		["A", "How did I lose against you but couldn't lose against El??"],
		["E", "Because you were cheating."],
		["A", "...I give up. It's already quite late, I'm going to swing by the card mart I think and get some more packs."],
		["A", "Are you staying here or going now?"],
		["E", "I'll head off too, we've been here ages already. I might come to the card mart with you too actually, not that I need any better cards clearly!"],
		["E", "...I suppose I'm taking care of the bill? ...Sigh... Of course. Okay I'll be back in a min."],
	],
	"w_l": [
		["A", "See I'm just too good at this. I was clearly just born more naturally gifted at it."],
		["E", "No you clearly must have still been cheating somehow. I don't know how but you were."],
		["A", "You just can't stand it when I'm naturally good at anything can you?"],
		["E", "But you think you're naturally good at everything."],
		["A", "Well I clearly am at this... I'm going to swing by the card mart I think and get some more packs."],
		["A", "Are you staying here or going now?"],
		["E", "I'll head off too, we've been here ages already. I might come to the card mart with you too actually. I need some better cards clearly!"],
		["E", "...I suppose I'm taking care of the bill? ...Sigh... Of course. Okay I'll be back in a min."],
	],
	"w_w": [
		["A", "See I wasn't cheating at all!"],
		["E", "Actually this proves you were cheating because you clearly couldn't cheat while I was watching and lost!"],
		["A", "You just can't stand it when I'm naturally good at anything can you?"],
		["E", "But you think you're naturally good at everything and clearly you're not because you just lost."],
		["A", "How did I lose against you but couldn't lose against El??"],
		["A", "...I give up. It's already quite late, I'm going to swing by the card mart I think and get some more packs."],
		["A", "Are you staying here or going now?"],
		["E", "I'll head off too, we've been here ages already. I might come to the card mart with you too actually. I need some better cards clearly!"],
		["E", "...I suppose I'm taking care of the bill? ...Sigh... Of course. Okay I'll be back in a min."],
	],
	"l_l": [
		["A", "Well I thought you were bad but [NAME] is clearly even worse!"],
		["A", "I'm only joking, you must have just got unlucky... twice in a row."],
		["E", "Don't be so tight, you clearly must have still been cheating somehow. I don't know how but you were."],
		["A", "You just can't stand it when I'm naturally good at anything can you?"],
		["E", "But you think you're naturally good at everything."],
		["A", "Well I clearly am at this... I'm going to swing by the card mart I think and get some more packs."],
		["A", "Are you staying here or going now?"],
		["E", "I'll head off too, we've been here ages already. I might come to the card mart with you too actually, not that I need any better cards clearly!"],
		["E", "...I suppose I'm taking care of the bill? ...Sigh... Of course. Okay I'll be back in a min."],
	],
}
# Ellie back from paying, stood between them.
const BILL_PAID := [
	["E", "Alright then, that's taken care of, I'm ready to go get some more packs."],
	["E", "Although my bank is looking a bit thin after paying for that..."],
	["A", "Calm down, I'll make up for it and get you a few packs don't worry."],
	["E", "THANKS. Alright [NAME], we'll see you later!"],
]

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------
var _olly: CutsceneActor = null
var _ellie: CutsceneActor = null
var _alex: CutsceneActor = null
var _sp_olly: Dictionary = {}
var _sp_ellie: Dictionary = {}
var _sp_alex: Dictionary = {}
var _hidden_nodes: Array = []


# ============================================================
# STATIC — what the map asks
# ============================================================

static func stage() -> String:
	return str(GameState.progress.get(STAGE_KEY, STAGE_NONE))


static func _set_stage(new_stage: String) -> void:
	GameState.progress[STAGE_KEY] = new_stage
	GameState.save_progress()


static func _result(key: String) -> String:
	return str(GameState.progress.get(key, ""))


## The two answers that wake up on day 1 and so come to breakfast with Olly still about.
static func _started_day_one() -> bool:
	return GameState.get_familiarity() in [GameState.FAMILIARITY_NEW, GameState.FAMILIARITY_RULES]


## Is Olly sat at the table this morning?
static func olly_here() -> bool:
	return _started_day_one() and not GameState.has_flag(OLLY_GONE_FLAG)


## Day 2 is Olly's: the FISH shop stays shut until he has been played (outside for
## "played", at the café for "new"/"rules"). Read by BaseMapScene's door locks.
static func fish_shop_locked() -> bool:
	return GameState.get_date() == CAFE_DATE and not GameState.has_flag(OLLY_GONE_FLAG)


## True on the café morning until the scene has moved the day on.
static func is_active() -> bool:
	return GameState.get_date() == CAFE_DATE and GameState.get_time() == CAFE_TIME \
		and GameState.get_familiarity() != GameState.FAMILIARITY_EXPERT \
		and stage() != STAGE_DONE


## Ellie's breakfast call is due on the way through the living room.
static func call_due() -> bool:
	return is_active() and _started_day_one() and not GameState.has_flag(CALL_DONE_FLAG)


# ------------------------------------------------------------
# REMINDER CALLS — invited but not sat down yet
# ------------------------------------------------------------
# Counted from the invitation (Ellie's call for "new"/"rules", Olly's goodbye for "played")
# until the player first sits down. MapManager rings the call the moment they are free.
# TWEAKABLE — each reminder rings at whichever comes first: this many conversations (any
# NPC or opponent, repeats count) or this many trips from an interior back outside.
const REMINDERS := [
	{"talks": 10, "exits": 2},   # whoever didn't invite them
	{"talks": 25, "exits": 5},   # Alexander
]
## TWEAKABLE — the bonus call: Olly, still waiting at the table, rings once the player has
## landed this many fish since the invitation. Separate from the two reminders above.
const FISH_CALL_AT := 5
const FISH_CALL_ID := "cafe_reminder_fishing"
const REMINDER_FISH_KEY  := "cafe_reminder_fish"
const FISH_CALL_DONE_FLAG := "cafe_fish_call_done"
const REMINDER_TALKS_KEY := "cafe_reminder_talks"
const REMINDER_EXITS_KEY := "cafe_reminder_exits"
const REMINDER_STEP_KEY  := "cafe_reminder_step"


## Invited, not sat down yet, and still the café morning.
static func _counting_reminders() -> bool:
	if not is_active() or stage() != STAGE_NONE:
		return false
	return GameState.has_flag(CALL_DONE_FLAG) if _started_day_one() else GameState.has_flag(OLLY_GONE_FLAG)


static func note_npc_talk() -> void:
	if _counting_reminders():
		GameState.progress[REMINDER_TALKS_KEY] = int(GameState.progress.get(REMINDER_TALKS_KEY, 0)) + 1
		GameState.save_progress()


static func note_exterior_return() -> void:
	if _counting_reminders():
		GameState.progress[REMINDER_EXITS_KEY] = int(GameState.progress.get(REMINDER_EXITS_KEY, 0)) + 1
		GameState.save_progress()


## Fishing_Minigame calls this for every fish landed.
static func note_fish_caught() -> void:
	if _counting_reminders() and olly_here():
		GameState.progress[REMINDER_FISH_KEY] = int(GameState.progress.get(REMINDER_FISH_KEY, 0)) + 1
		GameState.save_progress()


## The Phone_Calls.json id of the reminder that is owed right now, or "".
static func reminder_due() -> String:
	if not _counting_reminders():
		return ""
	# The fishing call first: only while Olly is still sat at the table waiting.
	if olly_here() and not GameState.has_flag(FISH_CALL_DONE_FLAG) \
			and int(GameState.progress.get(REMINDER_FISH_KEY, 0)) >= FISH_CALL_AT:
		return FISH_CALL_ID
	var step := int(GameState.progress.get(REMINDER_STEP_KEY, 0))
	if step >= REMINDERS.size():
		return ""
	var need: Dictionary = REMINDERS[step]
	if int(GameState.progress.get(REMINDER_TALKS_KEY, 0)) < int(need["talks"]) \
			and int(GameState.progress.get(REMINDER_EXITS_KEY, 0)) < int(need["exits"]):
		return ""
	if step == 0:
		# Ellie rang them ("new"/"rules"), so Olly chases; Olly told them ("played"), so Ellie does.
		return "cafe_reminder_olly" if _started_day_one() else "cafe_reminder_ellie"
	return "cafe_reminder_alexander"


## Called once `call_id` has hung up (a quit mid-call rings it again).
static func reminder_played(call_id: String) -> void:
	if call_id == FISH_CALL_ID:
		GameState.set_flag(FISH_CALL_DONE_FLAG)
		return
	GameState.progress[REMINDER_STEP_KEY] = int(GameState.progress.get(REMINDER_STEP_KEY, 0)) + 1
	GameState.save_progress()


## Back from one of the café matches: the map hands straight over to run_after_battle().
static func should_resume(from_battle: bool) -> bool:
	if not from_battle:
		return false
	match stage():
		STAGE_OLLY_BATTLE:  return _result(OLLY_RESULT_KEY) != ""
		STAGE_ELLIE_BATTLE: return _result(ELLIE_RESULT_KEY) != ""
		STAGE_ALEX_BATTLE:  return _result(ALEX_RESULT_KEY) != ""
	return false


## A quit part-way through a match leaves its battle stage set. Called by the map BEFORE
## it builds its cast, because the last case moves the clock on to the afternoon.
static func settle_after_load(from_battle: bool) -> void:
	# Alexander's match played: the map comes back up in the afternoon, closing scene and all.
	if stage() == STAGE_ALEX_BATTLE and _result(ALEX_RESULT_KEY) != "":
		_advance_to_afternoon()
	if should_resume(from_battle):
		return
	match stage():
		STAGE_OLLY_BATTLE:
			if _result(OLLY_RESULT_KEY) != "":
				GameState.set_flag(OLLY_GONE_FLAG)
				_set_stage(STAGE_OLLY_DONE)
			else:
				_set_stage(STAGE_NONE)
		STAGE_ELLIE_BATTLE:
			_set_stage(STAGE_ELLIE_DONE if _result(ELLIE_RESULT_KEY) != "" else STAGE_NONE)
		STAGE_ALEX_BATTLE:
			if _result(ALEX_RESULT_KEY) != "":
				_end_morning()
			else:
				_set_stage(STAGE_ALEX_ASK)


## Both matches are played: the morning is over. The clock has normally moved on already
## (settle_after_load, on the way back from Alexander's match).
static func _end_morning() -> void:
	GameState.progress[STAGE_KEY] = STAGE_DONE
	if not _advance_to_afternoon():
		GameState.save_progress()


## Moves the café morning on to the afternoon, once. True if it moved the clock (and saved).
static func _advance_to_afternoon() -> bool:
	if GameState.get_date() != CAFE_DATE or GameState.get_time() != CAFE_TIME:
		return false
	GameState.advance_time("Afternoon")   # saves
	return true


## Talking to anyone at the table starts the cutscene. Call after the map's _ready().
static func register(map_scene: Node2D) -> void:
	if not is_active():
		return
	for opponent_name in [OLLY_NAME, ELLIE_NAME, ALEX_NAME]:
		MapManager.opponent_interact_overrides[opponent_name] = func(opponent: Node) -> void:
			var cs := CafeBreakfastCutscene.new()
			cs.install(map_scene)
			cs.run_from_talk(opponent)


## A save made while sat at the table (a quit mid-chat, or the battle-return save) loads
## into the chair. Stand them up below the table instead.
static func unseat_after_load(map_scene: Node2D) -> void:
	var p := map_scene.get_node_or_null("Player") as Node2D
	if p != null and p.global_position.distance_to(SEAT_PLAYER) < SEAT_SNAP_RADIUS:
		p.global_position = STAND_SPOT
		if p.has_method("set_direction"):
			p.set_direction("down")
		GameState.save_current_location(map_scene.get_scene_path(), p.position)


## The decks the three of them play, from the decks this save's intro left unused.
##   new     player Basic Starter, Olly (intro) Basic Battle Deck
##           -> Ellie Fire Shock Starter, Alexander Grass Psy Starter, Olly Water Fight Starter
##   rules   player's pair Starter, Olly (intro) the pair it beats
##           -> Ellie Basic Starter, Alexander the pair that beats the player's (Starter),
##              Olly the same deck he played that evening
##   played  player's pair Deck (Olly is not here)
##           -> Ellie Basic Deck, Alexander the pair that beats the player's (Deck)
static func deck_for(opponent_name: String) -> String:
	var pair: String = GameState.progress.get(GameState.INTRO_PAIR_KEY, "Fire Shock")
	var strong: String = GameState.OLLY_DECK_STRONG.get(pair, "Water Fight")
	match GameState.get_familiarity():
		GameState.FAMILIARITY_NEW:
			match opponent_name:
				ELLIE_NAME: return "Fire Shock Starter Deck"
				ALEX_NAME:  return "Grass Psy Starter Deck"
				OLLY_NAME:  return "Water Fight Starter Deck"
		GameState.FAMILIARITY_RULES:
			match opponent_name:
				ELLIE_NAME: return GameState.STARTER_DECK_BASIC
				ALEX_NAME:  return strong + " Starter Deck"
				OLLY_NAME:  return GameState.olly_intro_deck()
		_:
			match opponent_name:
				ELLIE_NAME: return "Basic Deck"
				ALEX_NAME:  return strong + " Deck"
	return ""


# ============================================================
# ENTRY POINTS
# ============================================================

## The player talked to `opponent` at the table.
func run_from_talk(opponent: Node) -> void:
	_load_speakers()
	var at_stage := stage()
	# SAVE: where they stand now. A quit in Olly's or Ellie's match comes back to here.
	GameState.save_current_location(map.get_scene_path(), player.position)

	# Their line first, as a plain box, as though they were anybody sat at a table.
	var talker: Dictionary = _speaker_by_name(str(opponent.opponent_name))
	var line: String = str(opponent.meet_text if at_stage == STAGE_NONE else opponent.repeat_text)
	if line != "":
		await say(talker, line)
	close_box()
	await _sit_down()

	match at_stage:
		STAGE_NONE:       await _play_opening()
		STAGE_OLLY_ASK:   await _ask_olly(OLLY_ASK_AGAIN)
		STAGE_OLLY_DONE:  await _ask_ellie(ELLIE_MY_TURN, false)
		STAGE_ELLIE_ASK:  await _ask_ellie(ELLIE_ASK_AGAIN, true)
		STAGE_ELLIE_DONE: await _play_after_ellie()
		STAGE_ALEX_ASK:   await _ask_alex()
		_:                await _stand_up()


## Back on the map after one of the matches, still sat at the table.
func run_after_battle() -> void:
	_load_speakers()
	player.global_position = SEAT_PLAYER
	player_face("right")
	_seat_cast()
	await wait(POST_BATTLE_PAUSE)
	match stage():
		STAGE_OLLY_BATTLE:  await _play_after_olly()
		STAGE_ELLIE_BATTLE: await _play_after_ellie()
		STAGE_ALEX_BATTLE:  await _play_after_alex()
		_:                  await _stand_up()


# ============================================================
# THE CHAT
# ============================================================

func _play_opening() -> void:
	var with_olly := olly_here()
	await say(_sp_ellie, OPEN_ELLIE_1)
	await say(_sp_alex, OPEN_ALEX_1)
	await say_all(_sp_ellie, OPEN_ELLIE_2)
	if with_olly:
		await say(_sp_olly, OPEN_OLLY_1)
	await say(_sp_ellie, OPEN_ELLIE_3)
	await say(_sp_alex, OPEN_ALEX_2)

	if not with_olly:
		# No Olly to go first: Ellie's plea is the question.
		await _ask_ellie(OPEN_ELLIE_PLEASE, false)
		return

	_olly.face("up")
	await say(_sp_olly, OPEN_OLLY_2)
	close_box()
	_ellie.face("down")
	await wait(ELLIE_LOOK_BACK)
	_ellie.face("left")
	await say(_sp_ellie, OPEN_ELLIE_PLEASE)
	_olly.face("left")
	await say(_sp_olly, OLLY_BEFORE_ASK)
	await _ask_olly(OLLY_ASK)


func _ask_olly(question: String) -> void:
	if await ask(_sp_olly, question):
		_start_battle(OLLY_NAME)
		return
	await say(_sp_olly, OLLY_NO)
	_set_stage(STAGE_OLLY_ASK)
	await _stand_up()


## `again`: they have already said No to her once, so a No now gets the short answer.
func _ask_ellie(question: String, again: bool) -> void:
	if await ask(_sp_ellie, question):
		_start_battle(ELLIE_NAME)
		return
	if again:
		await say(_sp_ellie, ELLIE_NO_AGAIN)
	else:
		await say_all(_sp_ellie, ELLIE_NO)
	_set_stage(STAGE_ELLIE_ASK)
	await _stand_up()


func _ask_alex() -> void:
	# ISSUE #494: he sits straight above the player -- they look at each other for the challenge.
	if _alex != null and is_instance_valid(_alex):
		_alex.face("down")
	player_face("up")
	if await ask(_sp_alex, ALEX_ASK):
		_start_battle(ALEX_NAME)
		return
	await say(_sp_alex, ALEX_CHICKEN)
	_set_stage(STAGE_ALEX_ASK)
	await _stand_up()


func _say_script(lines: Array) -> void:
	for pair in lines:
		await say(_sp_ellie if pair[0] == "E" else _sp_alex, str(pair[1]))


# ============================================================
# AFTER EACH MATCH
# ============================================================

func _play_after_olly() -> void:
	# Olly's part is over from here: a quit during his goodbye comes back to Ellie's turn.
	GameState.set_flag(OLLY_GONE_FLAG)
	_set_stage(STAGE_OLLY_DONE)

	await say(_sp_olly, OLLY_BYE)
	if not GameState.has_item(PROTO_ROD):
		await say(_sp_olly, OLLY_ROD)
	close_box()

	# Down off his chair to the path, left to the path into the plaza, and up it.
	# ISSUE #488: about halfway to the edge of the screen Ellie looks down after him, a beat, and
	# sighs that she'll pay, while he is still walking. Then she turns back to the player, and her
	# own lines wait until he is off screen (or ELLIE_SIGH_AFTER, whichever is later).
	var olly_gone := [false]
	var olly_from: Vector2 = _olly.global_position
	var go := func() -> void:
		await _walk_off(_olly, [
			Vector2(_olly.global_position.x, PATH_Y),
			Vector2(OLLY_EXIT_X, PATH_Y),
			Vector2(OLLY_EXIT_X, PATH_Y - OLLY_EXIT_UP),
		], OLLY_EXIT_SPEED)
		olly_gone[0] = true
	go.call()
	var walked := 0.0
	var last: Vector2 = olly_from
	while not olly_gone[0] and walked < OFFSCREEN_MARGIN_X * ELLIE_SIGH_AT:
		await get_tree().process_frame
		if _olly == null or not is_instance_valid(_olly):
			break
		walked += _olly.global_position.distance_to(last)
		last = _olly.global_position
	if _ellie != null:
		_ellie.face("down")
		await wait(ELLIE_LOOK_BACK)
		await say(_sp_ellie, ELLIE_SIGH)
		close_box()
		_ellie.face(SEAT_FACING[ELLIE_NAME])
	while not olly_gone[0] and is_inside_tree():
		await get_tree().process_frame
	await wait(ELLIE_SIGH_AFTER)
	_olly = null
	# His world node was hidden while he sat; the flag keeps him off every later load.
	for node in _hidden_nodes.duplicate():
		if is_instance_valid(node) and node.opponent_name == OLLY_NAME:
			_hidden_nodes.erase(node)
			node.queue_free()

	await _ask_ellie(ELLIE_MY_TURN, false)


func _play_after_ellie() -> void:
	_set_stage(STAGE_ELLIE_DONE)
	var player_won := _result(ELLIE_RESULT_KEY) == "won"
	await _say_script(AFTER_ELLIE_PLAYER_WON if player_won else AFTER_ELLIE_PLAYER_LOST)
	await _ask_alex()


func _play_after_alex() -> void:
	var outcome := "%s_%s" % [
		"w" if _result(ELLIE_RESULT_KEY) == "won" else "l",
		"w" if _result(ALEX_RESULT_KEY) == "won" else "l",
	]
	await _say_script(AFTER_ALEX.get(outcome, AFTER_ALEX["l_l"]))
	close_box()

	# ISSUE #498: no fade, no cut. Ellie gets up and goes in to pay (out to the aisle, up to the
	# café door and through it) while Alexander and the player step down from the table to stand
	# facing each other. A beat later she comes back out of the door.
	var alex_down := [
		Vector2(ALEX_STAND_X, _alex.global_position.y),
		Vector2(ALEX_STAND_X, ALEX_END_SPOT.y),
		ALEX_END_SPOT,
	]
	var moving := [2]   # Alexander and Ellie still walking
	var glide := func(actor: CutsceneActor, pts: Array) -> void:
		await actor.glide_path(pts, ELLIE_WALK_SPEED)
		moving[0] -= 1
	glide.call(_alex, alex_down)
	var ellie_in := [
		Vector2(ELLIE_AISLE_X, _ellie.global_position.y),
		Vector2(ELLIE_AISLE_X, ELLIE_STEP_Y),
		Vector2(ELLIE_DOOR_SPOT.x, ELLIE_STEP_Y),
		ELLIE_DOOR_SPOT,
	]
	glide.call(_ellie, ellie_in)
	await player_walk_path([
		Vector2(player.global_position.x, PLAYER_STEP_DOWN_Y),
		Vector2(PLAYER_END_SPOT.x, PLAYER_STEP_DOWN_Y),
		PLAYER_END_SPOT,
	], ELLIE_WALK_SPEED)
	player_face("left")
	while moving[0] > 0 and is_inside_tree():
		await get_tree().process_frame
	_alex.face("right")
	# Through the door: she fades out on the step, waits inside, and fades back in.
	_ellie.face("up")
	var fade_in_door := create_tween()
	fade_in_door.tween_property(_ellie, "modulate:a", 0.0, ELLIE_DOOR_FADE)
	await fade_in_door.finished
	await wait(ELLIE_INSIDE_TIME)
	_ellie.face("down")
	var fade_out_door := create_tween()
	fade_out_door.tween_property(_ellie, "modulate:a", 1.0, ELLIE_DOOR_FADE)
	await fade_out_door.finished

	await _ellie.glide_path([
		Vector2(ELLIE_DOOR_SPOT.x, ELLIE_STEP_Y),
		Vector2(ELLIE_AISLE_X, ELLIE_STEP_Y),
		Vector2(ELLIE_AISLE_X, ELLIE_STOP.y),
		ELLIE_STOP,
	], ELLIE_WALK_SPEED)
	_ellie.face("up")
	_alex.face("down")
	player_face("down")

	await _say_script(BILL_PAID)
	close_box()

	# Off down to the path and away to the left together, Alexander half a step to her left.
	var ellie_route := [
		Vector2(ELLIE_STOP.x, ELLIE_TURN_Y),
		Vector2(ELLIE_STOP.x - LEAVE_RUN_LEFT, ELLIE_TURN_Y),
	]
	var alex_route := [
		Vector2(ALEX_LEAVE_X, ALEX_END_SPOT.y),
		Vector2(ALEX_LEAVE_X, ALEX_TURN_Y),
		Vector2(ALEX_LEAVE_X - LEAVE_RUN_LEFT, ALEX_TURN_Y),
	]
	_walk_off(_alex, alex_route, LEAVE_SPEED)
	await wait(0.05)
	await _walk_off(_ellie, ellie_route, LEAVE_SPEED)
	# Alexander is a step behind; give him the moment to clear the camera too.
	while _alex != null and is_instance_valid(_alex):
		await get_tree().process_frame

	# The morning is over. ISSUE #498: no fade and no reload -- the clock already moved on to the
	# afternoon on the way back from Alexander's match (settle_after_load), so the map came up with
	# the afternoon's cast (Ellie and Alexander are in the Card Mart) and the player just carries on.
	_end_morning()
	GameState.save_current_location(map.get_scene_path(), player.position)
	for node in _hidden_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_hidden_nodes.clear()
	finish()


# ============================================================
# THE BATTLES
# ============================================================

func _start_battle(opponent_name: String) -> void:
	close_box()
	var result_key := ALEX_RESULT_KEY
	var battle_stage := STAGE_ALEX_BATTLE
	match opponent_name:
		OLLY_NAME:
			result_key = OLLY_RESULT_KEY
			battle_stage = STAGE_OLLY_BATTLE
		ELLIE_NAME:
			result_key = ELLIE_RESULT_KEY
			battle_stage = STAGE_ELLIE_BATTLE
	var entry := CharacterSchedule.find_opponent(
		MAP_NAME, opponent_name, GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if entry.is_empty():
		push_error("CafeBreakfastCutscene: no '%s' entry in %s's character file" % [opponent_name, MAP_NAME])
		await _stand_up()
		return
	GameState.progress.erase(result_key)
	_set_stage(battle_stage)
	MapManager.start_forced_battle(entry, {
		"deck":            deck_for(opponent_name),
		"retry_on_loss":   false,
		"result_key":      result_key,
		"no_time_advance": true,
	})


# ============================================================
# SITTING DOWN / STANDING UP
# ============================================================

func _sit_down() -> void:
	await fade_out()
	_seat_cast()
	player.global_position = SEAT_PLAYER
	player_face("right")
	await fade_in()


## Back on their feet below the table, back to it, and the player has control again.
func _stand_up() -> void:
	close_box()
	await fade_out()
	_unseat_cast()
	player.global_position = STAND_SPOT
	player_face("down")
	GameState.save_current_location(map.get_scene_path(), player.position)
	await fade_in()
	finish()


## The table's world nodes are swapped for cutscene actors in the same chairs: actors can
## be turned and walked about, and the card icons are not wanted over a conversation.
func _seat_cast() -> void:
	if _ellie != null:
		return
	var nodes := _table_nodes()
	for node in nodes.values():
		node.freeze()
		node.visible = false
		_hidden_nodes.append(node)
	_alex = spawn(ALEX_NAME, _sp_alex.get("sprite", ""), SEAT_ALEX, SEAT_FACING[ALEX_NAME])
	_ellie = spawn(ELLIE_NAME, _sp_ellie.get("sprite", ""), SEAT_ELLIE, SEAT_FACING[ELLIE_NAME])
	_sp_alex["node"] = _alex
	_sp_ellie["node"] = _ellie
	if olly_here():
		_olly = spawn(OLLY_NAME, _sp_olly.get("sprite", ""), SEAT_OLLY, SEAT_FACING[OLLY_NAME])
		_sp_olly["node"] = _olly


func _unseat_cast() -> void:
	for actor in [_olly, _ellie, _alex]:
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	_olly = null
	_ellie = null
	_alex = null
	for node in _hidden_nodes:
		if not is_instance_valid(node):
			continue
		node.visible = true
		var facing: String = SEAT_FACING.get(node.opponent_name, "down")
		node.current_facing = facing
		node.animated_sprite.play("idle_" + facing)
		node.resume_movement()
	_hidden_nodes.clear()


## The table's opponent nodes in the world, by name.
func _table_nodes() -> Dictionary:
	var out := {}
	var container: Node = map.get_node_or_null("OPPONENTS")
	if container == null:
		return out
	for child in container.get_children():
		if child.is_in_group("opponents") and child.opponent_name in SEAT_FACING:
			out[child.opponent_name] = child
	return out


# ============================================================
# HELPERS
# ============================================================

func _load_speakers() -> void:
	_sp_olly = speaker_for(OLLY_NAME)
	_sp_ellie = speaker_for(ELLIE_NAME)
	_sp_alex = speaker_for(ALEX_NAME)


func _speaker_by_name(opponent_name: String) -> Dictionary:
	match opponent_name:
		OLLY_NAME: return _sp_olly
		ELLIE_NAME: return _sp_ellie
	return _sp_alex


## Glide `actor` along `points` and free them the moment they leave the camera (or the
## route runs out). Awaitable; returns once they are gone.
func _walk_off(actor: CutsceneActor, points: Array, speed: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var done := [false]
	var go := func() -> void:
		await actor.glide_path(points, speed)
		done[0] = true
	go.call()
	var was_alex := actor == _alex
	var was_ellie := actor == _ellie
	while not done[0] and is_instance_valid(actor) and _on_camera(actor):
		await get_tree().process_frame
	if is_instance_valid(actor):
		actor.queue_free()
	if was_alex:
		_alex = null
	elif was_ellie:
		_ellie = null


func _on_camera(actor: Node2D) -> bool:
	var offset: Vector2 = actor.global_position - player.global_position
	return absf(offset.x) < OFFSCREEN_MARGIN_X and absf(offset.y) < OFFSCREEN_MARGIN_Y
