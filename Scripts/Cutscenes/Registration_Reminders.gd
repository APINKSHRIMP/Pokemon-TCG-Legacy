class_name RegistrationReminders
extends RefCounted

# ============================================================
# REGISTRATION REMINDER CALLS - the morning of day 3
# ============================================================
# 2026-11-12 (user). Registration opens at the Town Hall on the morning of day 3
# (MapManager.REGISTRATION_OPEN_DAY), where Ellie and Alexander are queuing. The morning is
# held still until the player goes there (TownHallTrioCutscene.morning_locked).
#
#   FIRST CALL  Alexander, "we're at the Town Hall now waiting in line..." - rung a few steps
#               into the living room (Player_House_Downstairs) for every start that did NOT
#               meet Olly this morning (new / rules / played: Olly told them on day 1 or 2).
#               Expert / Hard Mode meet Olly on morning 3 and he tells them himself instead.
#   Then, like the café breakfast reminders (CafeBreakfastCutscene REMINDERS): matches,
#   conversations, trips back outside and packs opened are counted and MapManager rings the
#   next call the moment the player is free:
#     2nd: Ellie      "we're right at the front of the line..."         after 1 match
#     3rd: Alexander  "we had to queue for HOURS this morning..."      after 2 matches
#   (or the talks / exits / packs below, whichever comes first).
# Counting starts once the player has been told (the first call, or Olly's goodbye), stops for
# good once they hold the TCG Tracker (registered) or TRIO_DONE_FLAG is set (the Town Hall
# scene, TownHallTrioCutscene), and nothing rings inside the Town Hall itself.
# ============================================================

const DATE_TIME := "Morning"
## Set by TownHallTrioCutscene once the player has registered with Ellie and Alexander.
const TRIO_DONE_FLAG := "town_hall_trio_done"
const TOWN_HALL_SCENE := "TownHall"

## The first call (Alexander, in the living room) and the flag it raises once taken.
const FIRST_CALL_ID := "registration_call_alexander"
const FIRST_CALL_FLAG := "registration_call_done"
## Scenes the first call never rings in from MapManager's reminder check: the living room rings
## it itself after a few steps (Player_House_Downstairs), and upstairs is where they wake.
const HOME_SCENES := ["Player_House_Downstairs", "Player_House_Upstairs"]

## TWEAKABLE - each call rings at whichever comes first: this many matches finished (won, lost
## or forfeited), conversations (any NPC or opponent, repeats count), trips from an interior back
## outside, or packs opened.
const REMINDERS := [
	{"battles": 1, "talks": 10, "exits": 2, "packs": 3, "call": "registration_reminder_ellie"},
	{"battles": 2, "talks": 25, "exits": 5, "packs": 6, "call": "registration_reminder_alexander"},
]
const BATTLES_KEY := "registration_reminder_battles"
const TALKS_KEY := "registration_reminder_talks"
const EXITS_KEY := "registration_reminder_exits"
const PACKS_KEY := "registration_reminder_packs"
const STEP_KEY  := "registration_reminder_step"


## Registration morning, Olly's intro done, not registered, not met in the hall yet.
static func _morning_open() -> bool:
	if GameState.get_date() != MapManager.REGISTRATION_OPEN_DAY or GameState.get_time() != DATE_TIME:
		return false
	if not GameState.has_flag(GameState.INTRO_DONE_FLAG):
		return false
	return not GameState.has_item(MapManager.TRACKER_ITEM) and not GameState.has_flag(TRIO_DONE_FLAG)


## Expert (and Hard Mode, which is always Expert) meet Olly on morning 3 and he sends them.
static func _olly_told_them() -> bool:
	return GameState.get_familiarity() == GameState.FAMILIARITY_EXPERT


## Alexander's first call is owed (it rings a few steps into the living room).
static func first_call_due() -> bool:
	return _morning_open() and not _olly_told_them() and not GameState.has_flag(FIRST_CALL_FLAG)


## Counting toward the 2nd / 3rd calls: told about the queue (Olly or the first call).
static func _counting() -> bool:
	return _morning_open() and (_olly_told_them() or GameState.has_flag(FIRST_CALL_FLAG))


static func _bump(key: String) -> void:
	if _counting():
		GameState.progress[key] = int(GameState.progress.get(key, 0)) + 1
		GameState.save_progress()


static func note_npc_talk() -> void:
	_bump(TALKS_KEY)


static func note_exterior_return() -> void:
	_bump(EXITS_KEY)


## Pack_Opening_Manager calls this for every pack opened.
static func note_pack_opened() -> void:
	_bump(PACKS_KEY)


## GameState.record_match_result calls this for every match finished.
static func note_battle() -> void:
	_bump(BATTLES_KEY)


## The Phone_Calls.json id of the call owed right now, or "".
static func reminder_due() -> String:
	if _in_scene([TOWN_HALL_SCENE]):
		return ""
	# The first call, if it somehow wasn't rung at home (a quit mid-call, say): anywhere else.
	if first_call_due():
		return "" if _in_scene(HOME_SCENES) else FIRST_CALL_ID
	if not _counting():
		return ""
	var step := int(GameState.progress.get(STEP_KEY, 0))
	if step >= REMINDERS.size():
		return ""
	var need: Dictionary = REMINDERS[step]
	if int(GameState.progress.get(BATTLES_KEY, 0)) < int(need["battles"]) \
			and int(GameState.progress.get(TALKS_KEY, 0)) < int(need["talks"]) \
			and int(GameState.progress.get(EXITS_KEY, 0)) < int(need["exits"]) \
			and int(GameState.progress.get(PACKS_KEY, 0)) < int(need["packs"]):
		return ""
	return String(need["call"])


static func is_reminder(call_id: String) -> bool:
	if call_id == FIRST_CALL_ID:
		return true
	for r: Dictionary in REMINDERS:
		if String(r["call"]) == call_id:
			return true
	return false


## Called once `call_id` has hung up (a quit mid-call rings it again).
static func reminder_played(call_id: String) -> void:
	if call_id == FIRST_CALL_ID:
		GameState.set_flag(FIRST_CALL_FLAG)
		return
	GameState.progress[STEP_KEY] = int(GameState.progress.get(STEP_KEY, 0)) + 1
	GameState.save_progress()


static func _in_scene(names: Array) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	return tree.current_scene.scene_file_path.get_file().get_basename() in names
