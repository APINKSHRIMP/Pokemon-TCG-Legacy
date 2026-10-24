class_name DebugCutscenes
extends RefCounted

## The debug menu's CUTSCENES page: every cutscene in the game, every variation, one
## button each. A button resets the story state that cutscene reads (so it plays as if it
## had never been triggered), sets the date, time and intro answers it needs, and loads
## its map with the player where it starts. Cutscenes that begin when the player talks to
## someone (the café table) are started for them once the map is up.
##
## THIS REWRITES THE OPEN SAVE'S STORY STATE (intro answers, story flags, the date) --
## use a throwaway save slot.
##
## Adding a cutscene: an entry in entries() and a match branch in launch().

const HARBOUR := "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
const HOUSE_DOWN := "res://Scenes/Map_Scenes/Player_House_Downstairs.tscn"
const CARD_MART := "res://Scenes/Map_Scenes/Card_Mart.tscn"
const FISH_SHOP := "res://Scenes/Map_Scenes/Fish_Shop.tscn"
const WINDMILL := "res://Scenes/Map_Scenes/Windmill.tscn"

## TWEAKABLE — where the player stands for the Mewtwo vanish (Windmill root-local: just
## below Mewtwo at [229, 10] in the NPCS container).
const WINDMILL_PLAYER_POS := Vector2(350.0, 115.0)
## Seconds after the new map appears before a talk-started cutscene is kicked off.
const AUTO_START_DELAY := 0.7

## Every story key a cutscene reads. Wiped before each launch so nothing from an earlier
## run (or the real playthrough) leaks in; each launcher then sets only what it needs.
const STORY_KEYS := [
	"taxi_intro_pending", "show_intro_house_message", GameState.ARRIVAL_NIGHT_KEY,
	OllyIntroCutscene.STAGE_KEY, OllyIntroCutscene.MEET_KEY, OllyIntroCutscene.GIFT_DONE_KEY,
	GameState.INTRO_RESTART_KEY, "tutorial_tips_armed", GameState.TUTORIAL_TIPS_KEY,
	CafeBreakfastCutscene.STAGE_KEY, CafeBreakfastCutscene.OLLY_RESULT_KEY,
	CafeBreakfastCutscene.ELLIE_RESULT_KEY, CafeBreakfastCutscene.ALEX_RESULT_KEY,
	CafeBreakfastCutscene.OLLY_GONE_FLAG, CafeBreakfastCutscene.CALL_DONE_FLAG,
	CafeBreakfastCutscene.REMINDER_TALKS_KEY, CafeBreakfastCutscene.REMINDER_EXITS_KEY,
	CafeBreakfastCutscene.REMINDER_STEP_KEY, CafeBreakfastCutscene.REMINDER_FISH_KEY,
	CafeBreakfastCutscene.FISH_CALL_DONE_FLAG,
	CardMartDuoCutscene.BOUGHT_FLAG, CardMartDuoCutscene.BONUS_FLAG, CardMartDuoCutscene.GONE_FLAG,
	GameState.FISH_SHOP_INTRO_FLAG, "mewtwo_vanished",
]


## [group, [[button label, id], ...]] in the order the page shows them.
static func entries() -> Array:
	return [
		["ARRIVAL — THE TAXI HOME", [
			["Taxi + call — New to Pokémon TCG", "taxi_new"],
			["Taxi + call — Know the rules (evening, Olly at the taxi)", "taxi_rules"],
			["Taxi + call — Played before", "taxi_played"],
			["Taxi + call — Experienced", "taxi_expert"],
			["Taxi + call — Hard Mode", "taxi_hard"],
			["Note through the door (arrival night)", "house_note"],
		]],
		["OLLY'S INTRO — ARRIVAL TO THE MATCH", [
			["Olly intro — New (basic deck, newby tutorial)", "olly_new"],
			["Olly intro — Know the rules (evening, pick a starter)", "olly_rules"],
			["Olly intro — Played before (pick a deck)", "olly_played"],
			["Olly intro — Experienced (pick a deck)", "olly_expert"],
			["Olly intro — Hard Mode (draft packs, deck builder)", "olly_hard"],
		]],
		["OLLY'S INTRO — AFTER THE MATCH", [
			["After match — New (won: bonus pack, energy, coin)", "olly_after_new"],
			["After match — Know the rules (won: pair bonus pack)", "olly_after_rules"],
			["After match — Played before, player WON", "olly_after_played_won"],
			["After match — Played before, player LOST", "olly_after_played_lost"],
			["After match — Experienced, player WON", "olly_after_expert_won"],
			["After match — Experienced, player LOST", "olly_after_expert_lost"],
			["After match — Hard Mode, player WON", "olly_after_hard_won"],
			["After match — Hard Mode, player LOST", "olly_after_hard_lost"],
		]],
		["MORNING 2 — CAFÉ BREAKFAST", [
			["Ellie's breakfast call (living room)", "cafe_call"],
			["Café — full scene, Olly at the table (New / Rules)", "cafe_with_olly"],
			["Café — full scene, no Olly (Played before)", "cafe_no_olly"],
			["Café — after Olly's match (his goodbye + exit)", "cafe_after_olly"],
			["Café — after Ellie's match, player WON", "cafe_after_ellie_won"],
			["Café — after Ellie's match, player LOST", "cafe_after_ellie_lost"],
			["Café ending — won vs Ellie, won vs Alexander", "cafe_end_w_w"],
			["Café ending — won vs Ellie, lost vs Alexander", "cafe_end_w_l"],
			["Café ending — lost vs Ellie, won vs Alexander", "cafe_end_l_w"],
			["Café ending — lost vs Ellie, lost vs Alexander", "cafe_end_l_l"],
		]],
		["MORNING 2 — CAFÉ REMINDER CALLS", [
			["Reminder 1 — Olly rings (Ellie invited you)", "remind_olly"],
			["Reminder 1 — Ellie rings (Olly invited you)", "remind_ellie"],
			["Reminder 2 — Alexander rings", "remind_alexander"],
			["Bonus — Olly: \"Are you fishing right now?\"", "remind_fishing"],
		]],
		["AFTERNOON 2 — CARD MART", [
			["Ellie + Alexander pack chat (after buying a pack)", "mart_duo"],
		]],
		["FISH SHOP", [
			["FISH intro — Olly behind the counter", "fish_intro_olly"],
			["FISH intro — Alexander behind the counter", "fish_intro_alexander"],
		]],
		["WINDMILL", [
			["Mewtwo — \"MEW\" and vanish (just beaten)", "mewtwo_vanish"],
		]],
	]


static func launch(id: String) -> void:
	MapManager.close_debug_menu()
	_reset_story()
	var fam := GameState.FAMILIARITY_NEW
	match id:
		# ---- arrival ----
		"taxi_new", "taxi_rules", "taxi_played", "taxi_expert", "taxi_hard":
			var answers := _answers(id.trim_prefix("taxi_"))
			GameState.apply_new_game_answers(answers[0], answers[1])   # start date/time + arrival night
			GameState.progress["taxi_intro_pending"] = true
			_go(HARBOUR)
		"house_note":
			GameState.apply_new_game_answers(GameState.FAMILIARITY_NEW, false)
			GameState.progress["show_intro_house_message"] = true
			_go(HOUSE_DOWN, "Celeste_Harbour")

		# ---- Olly's intro ----
		"olly_new", "olly_rules", "olly_played", "olly_expert", "olly_hard":
			_olly_morning(id.trim_prefix("olly_"))
			GameState.progress["opponents_beaten"].erase(OllyIntroCutscene.OLLY_NAME)
			_go(HARBOUR, "Player_House_Downstairs")
		"olly_after_new", "olly_after_rules", "olly_after_played_won", "olly_after_played_lost", \
				"olly_after_expert_won", "olly_after_expert_lost", "olly_after_hard_won", "olly_after_hard_lost":
			var rest := id.trim_prefix("olly_after_")
			_olly_morning(rest.get_slice("_", 0))
			GameState.progress[OllyIntroCutscene.STAGE_KEY] = OllyIntroCutscene.STAGE_BATTLE
			if not GameState.progress.has(GameState.INTRO_PAIR_KEY):
				GameState.progress[GameState.INTRO_PAIR_KEY] = "Fire Shock"
			_set_beaten(OllyIntroCutscene.OLLY_NAME, not rest.ends_with("_lost"))
			_go(HARBOUR, "Player_House_Downstairs")

		# ---- café breakfast ----
		"cafe_call":
			_cafe_morning(fam)
			GameState.progress.erase(CafeBreakfastCutscene.CALL_DONE_FLAG)   # the call is what's being tested
			_go(HOUSE_DOWN, "Player_House_Upstairs")
		"cafe_with_olly", "cafe_no_olly":
			if id == "cafe_no_olly":
				fam = GameState.FAMILIARITY_PLAYED
			_cafe_morning(fam)
			_go_at(HARBOUR, CafeBreakfastCutscene.STAND_SPOT, "up", _talk_to_table)
		"cafe_after_olly":
			_cafe_morning(fam)
			_cafe_back_from(CafeBreakfastCutscene.STAGE_OLLY_BATTLE, CafeBreakfastCutscene.OLLY_NAME,
				{CafeBreakfastCutscene.OLLY_RESULT_KEY: "won"})
		"cafe_after_ellie_won", "cafe_after_ellie_lost":
			_cafe_morning(fam)
			GameState.progress[CafeBreakfastCutscene.OLLY_GONE_FLAG] = true
			_cafe_back_from(CafeBreakfastCutscene.STAGE_ELLIE_BATTLE, CafeBreakfastCutscene.ELLIE_NAME,
				{CafeBreakfastCutscene.ELLIE_RESULT_KEY: "won" if id.ends_with("won") else "lost"})
		"cafe_end_w_w", "cafe_end_w_l", "cafe_end_l_w", "cafe_end_l_l":
			_cafe_morning(fam)
			GameState.progress[CafeBreakfastCutscene.OLLY_GONE_FLAG] = true
			var code := id.trim_prefix("cafe_end_")
			_cafe_back_from(CafeBreakfastCutscene.STAGE_ALEX_BATTLE, CafeBreakfastCutscene.ALEX_NAME, {
				CafeBreakfastCutscene.ELLIE_RESULT_KEY: "won" if code[0] == "w" else "lost",
				CafeBreakfastCutscene.ALEX_RESULT_KEY: "won" if code[2] == "w" else "lost",
			})

		# ---- café reminder calls (they ring a moment after the map loads) ----
		"remind_olly", "remind_ellie", "remind_alexander", "remind_fishing":
			if id == "remind_ellie":
				fam = GameState.FAMILIARITY_PLAYED
			_cafe_morning(fam)
			match id:
				"remind_alexander":
					GameState.progress[CafeBreakfastCutscene.REMINDER_STEP_KEY] = 1
					GameState.progress[CafeBreakfastCutscene.REMINDER_EXITS_KEY] = CafeBreakfastCutscene.REMINDERS[1]["exits"]
				"remind_fishing":
					GameState.progress[CafeBreakfastCutscene.REMINDER_FISH_KEY] = CafeBreakfastCutscene.FISH_CALL_AT
				_:
					GameState.progress[CafeBreakfastCutscene.REMINDER_EXITS_KEY] = CafeBreakfastCutscene.REMINDERS[0]["exits"]
			_go(HARBOUR, "Player_House_Downstairs")

		# ---- Card Mart ----
		"mart_duo":
			_post_intro(fam, CardMartDuoCutscene.DUO_DATE, CardMartDuoCutscene.DUO_TIME)
			GameState.progress[CafeBreakfastCutscene.STAGE_KEY] = CafeBreakfastCutscene.STAGE_DONE
			GameState.progress[CardMartDuoCutscene.BOUGHT_FLAG] = true
			_go(CARD_MART, "Celeste_Harbour")

		# ---- FISH ----
		"fish_intro_olly", "fish_intro_alexander":
			# Day 1's rota: Olly mornings/afternoons, Alexander evenings/nights.
			_post_intro(fam, 1, "Morning" if id == "fish_intro_olly" else "Evening")
			_go(FISH_SHOP, "Celeste_Harbour")

		# ---- Windmill ----
		"mewtwo_vanish":
			_post_intro(fam, maxi(GameState.get_date(), 3), "Afternoon")
			_set_beaten("Mewtwo", true)
			GameState.returning_from_battle = true
			GameState.battle_result = ""   # the outro already said its line
			GameState.current_opponent_name = "Mewtwo"
			GameState.player_position = WINDMILL_PLAYER_POS
			GameState.save_progress()
			SceneCache.change_scene(WINDMILL)
			return
		_:
			push_error("DebugCutscenes: no launcher for '%s'" % id)
			return
	print("DEBUG CUTSCENE: ", id)


# ============================================================
# STATE SET-UP
# ============================================================

static func _reset_story() -> void:
	for key in STORY_KEYS:
		GameState.progress.erase(key)
	GameState.progress["opponents_beaten_count_current"] = 0
	GameState.forced_opponent_overrides = {}
	GameState.clear_menu_return_state()
	GameState.use_spawn_position = false
	GameState.returning_from_battle = false
	GameState.battle_result = ""
	GameState.entering_from = ""
	if not (GameState.progress.get("opponents_beaten") is Array):
		GameState.progress["opponents_beaten"] = []


## "new" / "rules" / "played" / "expert" / "hard" -> [familiarity, hard_mode].
static func _answers(kind: String) -> Array:
	match kind:
		"rules":  return [GameState.FAMILIARITY_RULES, false]
		"played": return [GameState.FAMILIARITY_PLAYED, false]
		"expert": return [GameState.FAMILIARITY_EXPERT, false]
		"hard":   return [GameState.FAMILIARITY_EXPERT, true]
	return [GameState.FAMILIARITY_NEW, false]


## The intro answers set and the clock on the moment Olly meets them: the morning after a
## bedtime arrival, or the "rules" arrival evening itself. The arrival night is over.
static func _olly_morning(kind: String) -> void:
	var answers := _answers(kind)
	GameState.apply_new_game_answers(answers[0], answers[1])
	var profile := GameState.get_intro_profile()
	if profile["start_time"] == "Bedtime":
		GameState.progress["date"] = int(profile["start_date"]) + 1
		GameState.progress["time"] = "Morning"
	GameState.progress.erase(GameState.ARRIVAL_NIGHT_KEY)
	GameState.progress.erase(GameState.INTRO_DONE_FLAG)
	GameState.progress[OllyIntroCutscene.STAGE_KEY] = OllyIntroCutscene.STAGE_NONE


## Past Olly's intro, on `date` at `time`, with the given intro answers.
static func _post_intro(familiarity: String, date: int, time: String) -> void:
	GameState.progress["familiarity"] = familiarity
	GameState.progress["hard_mode"] = false
	GameState.progress["date"] = date
	GameState.progress["time"] = time
	GameState.progress[OllyIntroCutscene.STAGE_KEY] = OllyIntroCutscene.STAGE_DONE
	GameState.progress[GameState.INTRO_DONE_FLAG] = true
	if not GameState.progress.has(GameState.INTRO_PAIR_KEY):
		GameState.progress[GameState.INTRO_PAIR_KEY] = "Fire Shock"


## The café morning, invited and not sat down: "new"/"rules" have had Ellie's call (except
## the call itself, which clears it again); "played" met Olly outside, so he isn't there.
static func _cafe_morning(familiarity: String) -> void:
	_post_intro(familiarity, CafeBreakfastCutscene.CAFE_DATE, CafeBreakfastCutscene.CAFE_TIME)
	if familiarity == GameState.FAMILIARITY_PLAYED:
		GameState.progress[CafeBreakfastCutscene.OLLY_GONE_FLAG] = true
	else:
		GameState.progress[CafeBreakfastCutscene.CALL_DONE_FLAG] = true


## As if just back from one of the café matches, still sat at the table.
static func _cafe_back_from(battle_stage: String, opponent: String, results: Dictionary) -> void:
	GameState.progress[CafeBreakfastCutscene.STAGE_KEY] = battle_stage
	for key in results:
		GameState.progress[key] = results[key]
	GameState.returning_from_battle = true
	GameState.battle_result = ""   # the outro already said its line
	GameState.current_opponent_name = opponent
	GameState.player_position = CafeBreakfastCutscene.SEAT_PLAYER
	GameState.save_progress()
	SceneCache.change_scene(HARBOUR)


static func _set_beaten(opponent: String, beaten: bool) -> void:
	var list: Array = GameState.progress["opponents_beaten"]
	if beaten and not list.has(opponent):
		list.append(opponent)
	elif not beaten:
		list.erase(opponent)


# ============================================================
# GOING THERE
# ============================================================

## Load `scene` as though arriving through its door from `from_map` ("" = default spawn).
static func _go(scene: String, from_map: String = "") -> void:
	GameState.entering_from = from_map
	GameState.save_progress()
	SceneCache.change_scene(scene)


## Load `scene` with the player at `pos` facing `facing`, then call `after(scene_root)`.
static func _go_at(scene: String, pos: Vector2, facing: String, after: Callable = Callable()) -> void:
	GameState.save_menu_return_state(scene, pos, facing)
	GameState.save_progress()
	var tree := Engine.get_main_loop() as SceneTree
	var old := tree.current_scene
	SceneCache.change_scene(scene)
	if not after.is_valid():
		return
	while tree.current_scene == old or tree.current_scene == null:
		await tree.process_frame
	await tree.create_timer(AUTO_START_DELAY).timeout
	if is_instance_valid(tree.current_scene):
		after.call(tree.current_scene)


## The café starts when the table is talked to: do that for the player.
static func _talk_to_table(map_scene: Node) -> void:
	var override: Callable = MapManager.opponent_interact_overrides.get(CafeBreakfastCutscene.ELLIE_NAME, Callable())
	if not override.is_valid():
		push_warning("DebugCutscenes: the café isn't active on this load")
		return
	for n in map_scene.get_tree().get_nodes_in_group("opponents"):
		if str(n.get("opponent_name")) == CafeBreakfastCutscene.ELLIE_NAME:
			override.call(n)
			return
