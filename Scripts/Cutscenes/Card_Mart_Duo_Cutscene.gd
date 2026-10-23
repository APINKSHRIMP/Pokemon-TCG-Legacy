class_name CardMartDuoCutscene
extends Cutscene

# ============================================================
# CARD MART DUO — Ellie 2 + Alexander 2, day 2 afternoon
# ============================================================
# The pair ripping packs in the Card Mart after the café breakfast. They are
# ordinary NPCs (Characters/Card_Mart.json); this script adds the one beat on top:
#
#   Buy a pack while they're in -> back on the mart floor Ellie turns round with
#   a [!] and they chat about pulls. Afterwards each repeats their last line.
#
# WHEN THEY LEAVE. They stand there all afternoon and are gone at Evening as the
# schedule says. Once the player has engaged with them -- talked to either, or had
# the pack chat -- they stay until the player's next card match, then GONE_FLAG
# hides them for good, whether or not the clock moved (on_match_played()).
# ============================================================

const ELLIE_NAME := "Ellie 2"
const ALEX_NAME  := "Alexander 2"
const DUO_DATE   := 2
const DUO_TIME   := "Afternoon"

## A pack was bought in the Card Mart while they were in; the chat is owed.
const BOUGHT_FLAG := "mart_duo_pack_bought"
## The pack chat has played. Card_Mart.json swaps their lines to the LAST lines below.
const BONUS_FLAG  := "mart_duo_bonus_done"
## Engaged, then a match was played: they've left the mart.
const GONE_FLAG   := "mart_duo_gone"

const ELLIE_LINES := [
	"Did you get anything good?",
	"I've got quite a few holos already",
]
const ALEX_LINES := [
	"Did you know sometimes you get a bonus rare for free in a pack?",
	"I've heard people claim they got a 'god pack' just full of holos but I don't believe it at all.",
]

## TWEAKABLE — the pause after Ellie's [!] before she speaks.
const TURN_PAUSE := 0.25


static func in_mart() -> bool:
	return GameState.get_date() == DUO_DATE and GameState.get_time() == DUO_TIME \
		and not GameState.has_flag(GONE_FLAG)


## Pack_Purchase calls this on every Card Mart buy.
static func note_pack_bought() -> void:
	if in_mart() and not GameState.has_flag(BONUS_FLAG):
		GameState.set_flag(BOUGHT_FLAG)


static func bonus_due() -> bool:
	return in_mart() and GameState.has_flag(BOUGHT_FLAG) and not GameState.has_flag(BONUS_FLAG)


## GameState.record_match_result calls this after every real match.
static func on_match_played() -> void:
	if GameState.has_flag(GONE_FLAG):
		return
	if GameState.has_flag(BONUS_FLAG) or GameState.has_met_npc(ELLIE_NAME) \
			or GameState.has_met_npc(ALEX_NAME):
		GameState.set_flag(GONE_FLAG)


func run() -> void:
	var ellie := _find_npc(ELLIE_NAME)
	var alex := _find_npc(ALEX_NAME)
	if ellie == null or alex == null:
		finish()
		return

	var ellie_speaker := speaker_for(ELLIE_NAME, "npcs")
	ellie_speaker["node"] = ellie
	var alex_speaker := speaker_for(ALEX_NAME, "npcs")
	alex_speaker["node"] = alex

	await SpeechEmote.play(ellie, "!")
	ellie.pause_and_face(player.global_position)
	player_face_position(ellie.global_position)
	await wait(TURN_PAUSE)
	await say_all(ellie_speaker, ELLIE_LINES)

	alex.pause_and_face(player.global_position)
	await say_all(alex_speaker, ALEX_LINES)
	close_box()

	GameState.set_flag(BONUS_FLAG)
	# The schedule only swaps their lines on the next load; these two are already spawned.
	_set_lines(ellie, ELLIE_LINES[-1])
	_set_lines(alex, ALEX_LINES[-1])
	ellie.resume_movement()
	alex.resume_movement()
	finish()


func _find_npc(npc_name: String) -> Node2D:
	for n in map.get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(n) and str(n.get("npc_name")) == npc_name:
			return n as Node2D
	return null


func _set_lines(npc: Node, line: String) -> void:
	npc.set("meet_text", line)
	npc.set("repeat_text", line)
