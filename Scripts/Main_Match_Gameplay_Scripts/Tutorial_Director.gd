extends Node

# ============================================================
# TUTORIAL DIRECTOR — every tutorial message, block and stacked deck in one place
# ============================================================
# Created by the match core in _ready() like the other helpers (main.tutorial). With
# no tutorial running every call here is a no-op, so the core calls it freely.
#
# THREE MODES
#   "newby"   Olly's match for "I'm completely new". Both decks are stacked, the coin
#             goes to the opponent, and the player is walked through the match step by
#             step: actions that are not the next step are BLOCKED with a message.
#             (NewbyTutorialMatch.txt)
#   "rules"   Olly's match for "I know the rules a bit". Both decks are stacked, the
#             coin goes to the opponent, the CPU's Active is swapped to one that is weak
#             to the player's, and the CPU cannot retreat for its first 3 turns. The
#             GENERIC messages play; nothing is blocked except End Turn before the hand
#             is first opened. (KnowRulesTutorialMatch.txt)
#   "generic" Options > "Tutorial messages for next match". The generic messages in any
#             match, no stacking, no overrides. The option switches itself off when the
#             match ends. (Board labels are their own Options row now - see labels_on().)
#   The newby player's SECOND match (after Olly's scripted one) is "generic" too, with
#             _newby_followup set (ISSUE #485 -- it used to be a "tips" mode with only the key
#             tips). Armed by GameState.TUTORIAL_TIPS_KEY, cleared when the match ends. Its
#             first turn opens on the Shift tip, then Caps Lock on the next quiet turn (#475).
#
# WHERE THE TEXT LIVES: the GENERIC_* and NEWBY_* consts below. [POKEMON], [ATTACK] and
# friends are filled in when the message plays.
#
# HOW A MESSAGE TRIGGERS: the core calls an on_*() hook at the moment in question, and
# an awaited hook returns once the player has clicked through. Blocks are gate(): the
# core asks before End Turn / an action row / playing a card / attaching an Energy,
# and a non-empty answer is shown instead of doing it.

var main: Node = null
var mode: String = ""
var _newby_followup: bool = false   # ISSUE #485: the newby's second match

# Message keys already played this match ("once" messages).
var _seen: Dictionary = {}
var _busy: bool = false          # a message sequence is on screen
var _block_showing: bool = false # a block message is on screen

# Player turns started so far (1 = the player's first turn), and CPU turns likewise.
var _player_turns: int = 0
var _cpu_turns: int = 0
# The generic start-of-turn tips, played one per turn from the player's 2nd turn on,
# each pushed back a turn whenever another message already played at that turn start.
var _tip_index: int = 0
var _turn_start_spoke: bool = false
var _hand_opened: bool = false
var _player_ever_benched: bool = false
var _last_player_ko_name: String = ""

# NEWBY: where in the script the player is.
var _step: String = ""
var _potions_played: int = 0


# ============================================================
# SETUP
# ============================================================

func setup(main_node: Node) -> void:
	main = main_node
	mode = ""
	_olly_stack = bool(main.opponent_data.get("olly_stack", false))
	var t: String = str(main.opponent_data.get("tutorial", ""))
	# The autotester never gets a tutorial, unless it is testing one (--tutorial).
	if GameState.autotest != null and t == "":
		return
	if t in ["newby", "rules"]:
		mode = t
	elif GameState.tutorial_next_match_setting == "on":
		mode = "generic"
	elif GameState.progress.get(GameState.TUTORIAL_TIPS_KEY, false):
		mode = "generic"
		_newby_followup = true
	if mode != "":
		print("TUTORIAL: mode ", mode)
	# ISSUE #470: Options shows the tutorial row locked On while a must-finish tutorial runs.
	GameState.mandatory_tutorial_running = mode in ["newby", "rules"] or _newby_followup


## A full tutorial (messages, blocks, labels).
func active() -> bool:
	return mode in ["newby", "rules", "generic"]


## Board labels ("Your hand", "Attacks", the bench captions, Energy/Tools, Stadium) are
## NOT tied to the tutorial any more: they are their own Options row, "Board labels",
## which a new game defaults from the intro profile. Kept so a tutorial line can ask.
func labels_on() -> bool:
	return GameState.board_labels_on()


func _stacked() -> bool:
	return mode == "newby" or mode == "rules"


## The match is over: a one-shot "next match" tutorial has been spent.
func on_match_end() -> void:
	GameState.mandatory_tutorial_running = false   # ISSUE #470
	if mode == "generic" and GameState.tutorial_next_match_setting == "on":
		GameState.set_tutorial_next_match("off")
	if _newby_followup:
		GameState.progress.erase(GameState.TUTORIAL_TIPS_KEY)
		GameState.save_progress()


# ============================================================
# STACKED DECKS
# ============================================================
# Each order is: the 7-card opening hand, then the cards drawn in order. The Prize
# cards are pulled out separately and dealt straight after the hand, which is where
# draw_prize_cards() takes them from. Whatever the lists do not name follows in the
# order Energy, then Pokemon, then Trainers -- so the Trainers are hopefully never
# drawn. A card the deck has run out of is skipped (with a warning), never invented.
#
# Names are matched loosely: case, spaces and punctuation are ignored, and a bare
# type ("Fighting") means that basic Energy.

const NEWBY_PLAYER := {
	"hand":   ["Voltorb", "Fighting", "Fighting", "Fighting", "Fighting", "Fighting", "Fighting"],
	"prizes": ["Water", "Water", "Water", "Water"],
	# T1 Fighting | T2 Bill (-> Voltorb, Fighting) | T3 Professor Oak (-> Ponyta, Fire, Fire,
	# Fighting x4) | T4 Machop | T5 Fighting | T6 PlusPower (the turn after the opponent's
	# Defender) | T7 Machoke | T8 Bill (-> Potion, Potion)
	"draws":  ["Fighting", "Bill", "Voltorb", "Fighting", "Professor Oak",
		"Ponyta", "Fire", "Fire", "Fighting", "Fighting", "Fighting", "Fighting",
		"Machop", "Fighting", "PlusPower", "Machoke", "Bill", "Potion", "Potion"],
}
const NEWBY_OPPONENT := {
	"hand":   ["Magikarp", "Water", "Water", "Water", "Water", "Water", "Water"],
	"prizes": ["Water", "Water", "Water", "Water"],
	# T1 Diglett | T2 Bill (-> Fighting x2) | T3 Professor Oak (-> Fighting x5, Rattata,
	# Energy Removal) | T4 Rattata | T5 Rattata | T6 Defender | T7 Dratini | T8 Dratini.
	# The Energy Removal (in place of one of the deck's Water) is played on turn 7, before
	# Dratini's Pound, taking an Energy off Machop: so Machoke still needs another next turn.
	"draws":  ["Diglett", "Bill", "Fighting", "Fighting", "Professor Oak",
		"Fighting", "Fighting", "Fighting", "Fighting", "Fighting", "Rattata", "Energy Removal",
		"Rattata", "Rattata", "Defender", "Dratini", "Dratini"],
}

# "rules": the player's deck by pair, and Olly's (the pair the player's deck beats).
const RULES_PLAYER := {
	"Water Fight": {
		"hand": ["Squirtle", "Squirtle", "Machop", "Fighting", "Water", "Water", "Water"],
		"prizes": ["Water", "Water", "Fighting", "Fighting"],
		"draws": ["Potion", "Bill", "Water", "Rattata", "Switch", "Gust of Wind", "Professor Oak",
			"Wartortle", "Water", "Water", "Water", "Super Potion", "Full Heal", "Defender",
			"Water", "Water", "Water", "Fighting", "Water", "Water", "Fighting", "Fighting"],
	},
	"Grass Psy": {
		"hand": ["Bulbasaur", "Bulbasaur", "Drowzee", "Psychic", "Psychic", "Grass", "Grass"],
		"prizes": ["Grass", "Grass", "Psychic", "Psychic"],
		"draws": ["Potion", "Bill", "Grass", "Rattata", "Switch", "Gust of Wind", "Professor Oak",
			"Ivysaur", "Grass", "Grass", "Grass", "Super Potion", "Full Heal", "Defender",
			"Grass", "Grass", "Grass", "Psychic", "Grass", "Grass", "Grass", "Grass", "Grass",
			"Psychic", "Psychic"],
	},
	"Fire Shock": {
		"hand": ["Charmander", "Charmander", "Pikachu", "Lightning", "Lightning", "Fire", "Fire"],
		"prizes": ["Fire", "Fire", "Lightning", "Lightning"],
		"draws": ["Potion", "Bill", "Fire", "Rattata", "Switch", "Gust of Wind", "Professor Oak",
			"Charmeleon", "Fire", "Fire", "Fire", "Super Potion", "Full Heal", "Defender",
			"Fire", "Fire", "Fire", "Lightning", "Fire", "Fire", "Fire", "Fire", "Lightning"],
	},
}
const RULES_OPPONENT := {
	"Water Fight": {
		"hand": ["Poliwag", "Poliwag", "Machop", "Machop", "Water", "Water", "Water"],
		"prizes": ["Water", "Water", "Fighting", "Fighting"],
		"draws": ["Bill", "Fighting", "Fighting", "Professor Oak", "Magikarp", "Magikarp",
			"Diglett", "Diglett", "Water", "Water", "Fighting", "Fighting", "Water", "Water",
			"Fighting", "Fighting"],
	},
	"Grass Psy": {
		"hand": ["Bulbasaur", "Bulbasaur", "Doduo", "Doduo", "Grass", "Grass", "Grass"],
		"prizes": ["Grass", "Grass", "Psychic", "Psychic"],
		"draws": ["Bill", "Grass", "Grass", "Professor Oak", "Drowzee", "Drowzee", "Weedle",
			"Weedle", "Psychic", "Psychic", "Grass", "Grass", "Grass", "Psychic", "Psychic",
			"Grass", "Grass", "Psychic", "Psychic"],
	},
	"Fire Shock": {
		"hand": ["Ponyta", "Ponyta", "Voltorb", "Voltorb", "Fire", "Fire", "Lightning"],
		"prizes": ["Fire", "Fire", "Lightning", "Lightning"],
		"draws": ["Bill", "Fire", "Fire", "Professor Oak", "Growlithe", "Growlithe", "Doduo",
			"Doduo", "Lightning", "Fire", "Fire", "Fire", "Fire", "Fire", "Fire", "Lightning"],
	},
}


## Reorders `deck` in place (it is the freshly loaded, shuffled deck) before the
## opening hand is drawn. Only the two stacked modes touch it.
func stack_deck(deck: Array, is_opponent: bool) -> void:
	if is_opponent and _olly_stack:
		_stack_olly_opening(deck)
		return
	if not _stacked():
		return
	var order: Dictionary = _order_for(is_opponent)
	if order.is_empty():
		push_warning("TUTORIAL: no stacked order for %s" % ("opponent" if is_opponent else "player"))
		return
	var pool: Array = deck.duplicate()
	var stacked: Array = []
	for list_key in ["hand", "prizes", "draws"]:
		for wanted in order.get(list_key, []):
			var card = _take(pool, wanted)
			if card != null:
				stacked.append(card)
			else:
				push_warning("TUTORIAL: %s deck has no '%s' left for its %s" % [
					"opponent" if is_opponent else "player", wanted, list_key])
	# The rest: Energy, then Pokemon, then Trainers.
	for supertype in ["Energy", "Pokémon", "Trainer"]:
		for c in pool.duplicate():
			if String(c.metadata.get("supertype", "")) == supertype:
				stacked.append(c)
				pool.erase(c)
	stacked.append_array(pool)
	deck.clear()
	deck.append_array(stacked)


# ------------------------------------------------------------
# OLLY'S OPENING ("played" / "experienced", not Hard Mode)
# ------------------------------------------------------------
# No tutorial, but Olly's opening is fixed (profile key "olly_stack"): his hand holds
# exactly 2 Basic Pokemon, a Stage 1 that evolves from one of them and a Bill, the rest
# filled with non-Pokemon cards. Every Professor Oak goes to the bottom of the deck and one
# is put on top at the start of his OLLY_OAK_TURN-th turn, so he draws it then (Bill on
# turn 1, then three turns). Everything else stays in its shuffled order.
const OLLY_OAK_TURN := 4
var _olly_stack: bool = false


func _stack_olly_opening(deck: Array) -> void:
	var pool: Array = deck.duplicate()
	var stage1 = null
	var base = null
	for c in pool:
		if not "Stage 1" in c.metadata.get("subtypes", []):
			continue
		var from := _norm(String(c.metadata.get("evolvesFrom", "")))
		for b in pool:
			if main.is_basic_pokemon(b) and _norm(String(b.metadata.get("name", ""))) == from:
				stage1 = c
				base = b
				break
		if stage1 != null:
			break
	if stage1 == null:
		push_warning("OLLY STACK: no Stage 1 with its Basic in the deck -- left shuffled")
		return
	pool.erase(stage1)
	pool.erase(base)
	var other = null
	for b in pool:
		if main.is_basic_pokemon(b):
			other = b
			break
	var bill = _take(pool, "Bill")
	var oaks: Array = []
	var oak = _take(pool, "Professor Oak")
	while oak != null:
		oaks.append(oak)
		oak = _take(pool, "Professor Oak")
	var hand: Array = [base, stage1]
	if other != null:
		pool.erase(other)
		hand.append(other)
	if bill != null:
		hand.append(bill)
	# Fill the hand from the shuffled pool with anything that is not a Pokemon.
	for c in pool.duplicate():
		if hand.size() >= 7:
			break
		if String(c.metadata.get("supertype", "")) != "Pokémon":
			hand.append(c)
			pool.erase(c)
	if other == null or bill == null:
		push_warning("OLLY STACK: deck is missing a second Basic or a Bill")
	deck.clear()
	deck.append_array(hand)
	deck.append_array(pool)
	deck.append_array(oaks)
	print("OLLY STACK: hand ", hand.map(func(c): return c.metadata.get("name", "")), ", ", oaks.size(), " Oak at the bottom")


## Start of Olly's OLLY_OAK_TURN-th turn, before his draw: a Professor Oak on top.
func _olly_oak_to_top() -> void:
	var deck: Array = main.opponent_deck
	for i in range(deck.size() - 1, -1, -1):
		if _norm(String(deck[i].metadata.get("name", ""))) == "professoroak":
			var oak = deck[i]
			deck.remove_at(i)
			deck.push_front(oak)
			print("OLLY STACK: Professor Oak put on top for CPU turn ", _cpu_turns)
			return


func _order_for(is_opponent: bool) -> Dictionary:
	if mode == "newby":
		return NEWBY_OPPONENT if is_opponent else NEWBY_PLAYER
	var pair: String = GameState.progress.get(GameState.INTRO_PAIR_KEY, "")
	if is_opponent:
		pair = GameState.OLLY_DECK_WEAK.get(pair, "")
		return RULES_OPPONENT.get(pair, {})
	return RULES_PLAYER.get(pair, {})


func _take(pool: Array, wanted: String):
	var key := _norm(wanted)
	for c in pool:
		var n := _norm(String(c.metadata.get("name", "")))
		if n == key or n == key + "energy":
			pool.erase(c)
			return c
	return null


func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


# ============================================================
# MATCH START — coin, the CPU's Active, the CPU's retreats
# ============================================================

## Both stacked tutorials have the opponent go first.
func forces_opponent_first() -> bool:
	return _stacked()


## "rules": once the player has chosen their Active, the CPU's Active becomes one that is
## WEAK to it (from its bench or hand), if it has one and is not already.
func on_player_active_set() -> void:
	if mode != "rules":
		return
	var mine = main.player_active_pokemon
	var theirs = main.opponent_active_pokemon
	if mine == null or theirs == null:
		return
	var my_type: String = main.get_pokemon_type(mine)
	if _weak_to(theirs, my_type):
		return
	var candidate = null
	for c in main.opponent_bench:
		if _weak_to(c, my_type):
			candidate = c
			break
	if candidate == null:
		for c in main.opponent_hand:
			if main.is_basic_pokemon(c) and _weak_to(c, my_type):
				candidate = c
				break
	if candidate == null:
		return
	if candidate in main.opponent_bench:
		var i: int = main.opponent_bench.find(candidate)
		main.opponent_bench[i] = theirs
		theirs.current_location = "bench"
	else:
		main.opponent_hand.erase(candidate)
		main.opponent_hand.append(theirs)
		theirs.current_location = "hand"
		main.display_hand_cards_array(main.opponent_hand, main.opponent_hand_container,
			main.card_scales[11.55], main.hide_hidden_cards, 1300.0, 12, main.opponent_sleeve_small)
	candidate.current_location = "active"
	main.opponent_active_pokemon = candidate
	main.display_pokemon(true)
	print("TUTORIAL: CPU Active swapped to ", candidate.metadata.get("name", ""), " (weak to ", my_type, ")")


func _weak_to(card, type: String) -> bool:
	for w in card.metadata.get("weaknesses", []):
		if String(w.get("type", "")) == type:
			return true
	return false


func on_cpu_turn_start() -> void:
	_cpu_turns += 1
	if _olly_stack and _cpu_turns == OLLY_OAK_TURN:
		_olly_oak_to_top()
	_cpu_plan =(NEWBY_CPU_PLAN.get(_cpu_turns, {}) as Dictionary).duplicate(true) if mode == "newby" else {}


# ============================================================
# NEWBY — THE CPU'S SCRIPTED TURNS
# ============================================================
# Tested with the autotester (--tutorial=newby): left to its own AI the CPU does NOT play
# the turns NewbyTutorialMatch.txt needs (it retreated Magikarp on its 2nd turn and used
# Dig Under instead of Flail), so for its first 8 turns it is told what to do. The CPU
# still carries every action out through its own code -- messages, animations, triggers
# -- it only takes its CHOICES from here (CPU_AI asks cpu_plan()).
#   bench      Basics to bench, in order        trainers  Trainers to play, in order
#   attach     [energy name, target]             retreat   bench Pokemon to retreat to
#   attack     attack name, "" for none
# An energy name of "any" takes whatever basic Energy the hand holds (none = no attach).
# A target is "active", a name, or "bench_bare:<name>" (a benched one with no Energy).
const NEWBY_CPU_PLAN := {
	1: {"bench": ["Diglett"], "attach": ["Water Energy", "active"], "attack": ""},
	2: {"trainers": ["Bill"], "attach": ["Fighting Energy", "Diglett"], "attack": "Flail"},
	3: {"trainers": ["Professor Oak"], "bench": ["Rattata"],
		"attach": ["Fighting Energy", "active"], "attack": "Scratch"},
	4: {"bench": ["Rattata"], "attach": ["Fighting Energy", "bench_bare:Rattata"], "attack": "Scratch"},
	5: {"bench": ["Rattata"], "attach": ["Fighting Energy", "bench_bare:Rattata"], "attack": "Scratch"},
	6: {"trainers": ["Defender"], "attach": ["Fighting Energy", "active"], "attack": "Bite"},
	7: {"trainers": ["Energy Removal"], "removal_target": "active", "bench": ["Dratini"],
		"retreat": "Dratini", "attach": ["Fighting Energy", "active"], "attack": "Pound"},
	# By now its Fighting Energy is spent: whatever basic Energy it holds, if any.
	8: {"bench": ["Dratini"], "attach": ["any", "active"], "attack": "Pound"},
}
var _cpu_plan: Dictionary = {}


## True while the CPU's choices come from the script (CPU_AI checks this in every phase).
func cpu_scripted() -> bool:
	return not _cpu_plan.is_empty()


## The next scripted card of `kind` ("bench" / "trainers") still in the CPU's hand, or null.
func cpu_next_card(kind: String):
	var names: Array = _cpu_plan.get(kind, [])
	while not names.is_empty():
		var wanted: String = names.pop_front()
		for c in main.opponent_hand:
			if _name(c) == wanted:
				return c
		push_warning("TUTORIAL: CPU script wants to play %s but has none" % wanted)
	return null


## [energy card, target] for this turn's scripted attach, or [] for none.
func cpu_attach_choice() -> Array:
	var a: Array = _cpu_plan.get("attach", [])
	if a.size() < 2:
		return []
	var energy = null
	for c in main.opponent_hand:
		if _name(c) == String(a[0]) or (String(a[0]) == "any" and main.is_basic_energy_card(c)):
			energy = c
			break
	if energy == null and String(a[0]) == "any":
		return []
	var target = null
	var spec: String = String(a[1])
	if spec == "active":
		target = main.opponent_active_pokemon
	elif spec.begins_with("bench_bare:"):
		for b in main.opponent_bench:
			if _name(b) == spec.trim_prefix("bench_bare:") and b.attached_energies.is_empty():
				target = b
				break
	else:
		for b in [main.opponent_active_pokemon] + main.opponent_bench:
			if b != null and _name(b) == spec:
				target = b
				break
	if energy == null or target == null:
		push_warning("TUTORIAL: CPU script attach %s -> %s not possible" % [a[0], a[1]])
		return []
	return [energy, target]


## The benched Pokemon this turn's script retreats to, or null for no retreat.
func cpu_retreat_choice():
	var wanted: String = String(_cpu_plan.get("retreat", ""))
	if wanted == "":
		return null
	for b in main.opponent_bench:
		if _name(b) == wanted:
			return b
	return null


## The player's Pokemon this turn's Energy Removal hits, or null for the CPU's own choice.
func cpu_removal_target(candidates: Array):
	if String(_cpu_plan.get("removal_target", "")) == "active" and main.player_active_pokemon in candidates:
		return main.player_active_pokemon
	return null


## The attack this turn's script uses ("" = none).
func cpu_attack_choice() -> String:
	return String(_cpu_plan.get("attack", ""))


## "rules": the CPU may not retreat during its first 3 turns.
func cpu_retreat_blocked() -> bool:
	return mode == "rules" and _cpu_turns <= 3


# ============================================================
# MESSAGES
# ============================================================

func _say(lines: Array, fills: Dictionary = {}) -> void:
	_busy = true
	for line in lines:
		var text := String(line)
		for k in fills:
			text = text.replace(k, String(fills[k]))
		await main.show_message(text, true, "tutorial")
	_busy = false


## Plays `lines` once per match under `key`. Returns true if it played.
func _once(key: String, lines: Array, fills: Dictionary = {}) -> bool:
	if _seen.has(key):
		return false
	_seen[key] = true
	await _say(lines, fills)
	return true


## A block's explanation. One at a time: a second press while it is up is ignored.
func show_block(text: String) -> void:
	if _block_showing:
		return
	_block_showing = true
	await main.show_message(text, true, "tutorial")
	_block_showing = false


## For hooks the core cannot await (a selection screen opening): plays once the board
## is free of other messages, and only then marks the key as seen.
func _deferred_once(key: String, lines: Array, fills: Dictionary = {}) -> void:
	if _seen.has(key) or _busy:
		return
	_seen[key] = true
	await _deferred_say(lines, fills)


## As _deferred_once, but every time it is asked (nothing is marked as seen here).
func _deferred_say(lines: Array, fills: Dictionary = {}) -> void:
	if _busy:
		return   # one at a time: a click while a pile message is up does not queue another
	for _i in 120:
		if not _busy and not main.msgbox_container.visible:
			break
		await get_tree().process_frame
	await _say(lines, fills)


func _name(card) -> String:
	return String(card.metadata.get("name", "")) if card != null else ""


# ============================================================
# GENERIC MESSAGES (KnowRulesTutorialMatch.txt) — "rules" and "generic"
# ============================================================

const G_CLICK_HAND := ["Click your hand to see every card you're holding there and to play them."]
const G_BLOCK_END_BEFORE_HAND := "You don't want to end your turn yet. Click your hand first to start playing cards."
const G_HAND_OPENED := ["You can select any cards in here by clicking them and play them by pressing the action button below..."]
const G_CAN_ATTACK := [
	"[POKEMON] has enough energy and can now attack using [ATTACK]...",
	"Press the [ATTACK] button next to your [POKEMON] to attack your opponent's [DEFENDER]!",
]
const G_WEAKNESS_DEALT := ["[DEFENDER] is weak to your [POKEMON]'s [TYPE] type so it takes double damage!"]
const G_AT_RISK := [
	"Your [POKEMON] is at risk of being knocked out...",
	"If you have no Bench Pokemon and your Active Pokemon is knocked out then you instantly lose the match!",
	"You can retreat your [POKEMON] and make one of your Benched Pokemon active instead.",
]
const G_PRIZE := [
	"You have knocked out your opponent's Pokemon! You can now take one of your 'Prize cards'!",
	"Prize cards are taken from the top of your deck and placed here when the match first starts...",
	"If you take all of your prize cards in a match, you win!",
	"The prize card you take from here is added to your hand.",
]
const G_WEAKNESS_TAKEN := ["Oh no! Your [POKEMON] was weak to your opponent's [ATTACKER]'s [TYPE] type so it took double damage"]
const G_KO_WITH_BENCH := ["Your [POKEMON] was knocked out. You will now need to set one of your Bench Pokemon as your new active Pokemon..."]
const G_KO_NO_BENCH := [
	"Your [POKEMON] was knocked out and you don't have any Pokemon on your bench to set as your new active Pokemon...",
	"Even if you have prize cards left, if your active Pokemon is knocked out with no Benched Pokemon left you lose!",
]
const G_RESISTANCE := [
	"Just like having a Weakness to a type, some Pokemon have a Resistance to a type...",
	"[DEFENDER] has a [TYPE] resistance so [ATTACKER] did no damage!",
	"All resistances reduce damage dealt by 30.",
]
const G_RESISTANCE_SOME := [
	"Just like having a Weakness to a type, some Pokemon have a Resistance to a type...",
	"[DEFENDER] has a [TYPE] resistance so [ATTACKER] did less damage!",
	"All resistances reduce damage dealt by 30.",
]
const G_EVOLUTION := [
	"Some Pokemon can evolve to unlock better attacks and more HP!",
	"You can't evolve a Pokemon on the same turn it has been put onto the field or evolved already",
]
const G_END_TURN_HINT := ["If you can't attack and have no other cards to play, you can finish your turn with the End Turn button."]
# One per player turn from the 2nd, in this order, each pushed back a turn whenever
# another message already played at that turn's start.
const G_TURN_TIPS := [
	["Hover over a card and hold the [SHIFT] key to make it larger and examine it in greater detail...",
		"You can keep hold of the [SHIFT] key and move around the screen to hover over other cards."],
	["You can often double click a card to play it right away, and most often can right click to cancel...",
		"This saves you from pressing the actual button and works for cards in your hand and most card effect choices...",
		"Try double clicking the next card you want to play and right clicking to cancel."],
	["Press the [CAPS LOCK] key to look at the match log and look at the historical data of your current match...",
		"It will show you a summary of your entire match so far."],
	["You can forfeit and lose any match on your turn by pressing the [ESCAPE] key and choosing Forfeit."],
]

# Viewing a pile for the first time (both NewbyTutorialMatch.txt and the generic set).
const PILE_LINES := {
	"opponent_hand":    "You are viewing your opponent's hand. You cannot see what cards they have",
	"player_discard":   "You are viewing your own discard pile. Any of your trainer cards, discarded energy or knocked out pokemon go in here",
	"opponent_discard": "You are viewing your opponent's discard pile. Any of the opponent's trainer cards, discarded energy or knocked out pokemon go in here",
	"player_bench":     "You are viewing your bench. All of your benched pokemon will be shown here",
	"opponent_bench":   "You are viewing your opponent's bench. All of their benched pokemon will be shown here",
	"player_prizes":    "You are viewing your prize cards. You take one every time you knock out one of your opponent's Pokemon",
	"opponent_prizes":  "You are viewing your opponent's prize cards. They take one every time they knock out one of your Pokemon",
}


func _generic() -> bool:
	return mode == "rules" or mode == "generic"


# ============================================================
# HOOKS — called by the match core
# ============================================================

## The opening screen: the hand, waiting for an Active to be chosen.
const CAPS_HINT := "Press [CAPS LOCK] To read back any of these help messages"

func on_setup_screen() -> void:
	# First thing in any match with tutorial help.
	# ISSUE #475: not the Caps Lock hint for the newby (it comes after "click your hand" now) nor
	# for their second match (Caps Lock is one of its turn tips).
	if mode == "":
		return
	var lines: Array = []
	if mode != "newby" and not _newby_followup:
		lines.append(CAPS_HINT)
	if mode == "newby":
		lines.append_array(NEWBY_SETUP)
	if not lines.is_empty():
		_deferred_once("n_setup", lines)


## Just before the heads/tails choice.
func on_coin_choice() -> void:
	if mode == "newby":
		await _once("n_coin", NEWBY_COIN)


## The player's turn, before the draw.
func on_player_turn_pre_draw() -> void:
	_player_turns += 1
	_turn_start_spoke = false
	if mode == "newby" and _player_turns == 1:
		await _once("n_draw", NEWBY_AUTO_DRAW)


## The player's turn, after the draw and every turn-start effect.
## ISSUE #475: the newby's second match takes the tips in this order -- Shift on the very first
## turn (as the first card is drawn), then Caps Lock on the next turn nothing else is said.
const FOLLOWUP_TIP_ORDER := [0, 2, 1, 3]
const CAPS_REMINDER := ["Remember you can press [CAPS LOCK] to see the match log and all messages."]
const SHIFT_HINT := ["You can press [SHIFT] to see a card's details."]


func on_player_turn_start() -> void:
	if not active():
		return
	if _newby_followup:
		await _followup_turn_start()
		return
	if mode == "newby":
		await _newby_turn_start()
		return
	# "rules" gets the newby's first-turn spiel on the aim of the game too.
	if mode == "rules" and _player_turns == 1:
		await _once("n_t1_aim", NEWBY_T1_AIM, {"[POKEMON]": _name(main.player_active_pokemon)})
	var spoke: bool = await _once("g_click_hand", G_CLICK_HAND)
	if spoke:
		_turn_start_spoke = true
	if _player_at_risk():
		spoke = await _once("g_risk", G_AT_RISK, {"[POKEMON]": _name(main.player_active_pokemon)})
		if spoke:
			_turn_start_spoke = true
	spoke = await _maybe_evolution_message()
	if spoke:
		_turn_start_spoke = true
	if _player_turns >= 2 and not _turn_start_spoke and _tip_index < G_TURN_TIPS.size():
		await _say(G_TURN_TIPS[_tip_index])
		_tip_index += 1


## ISSUE #475 / #485: the newby's second match -- the generic messages, the Shift tip first thing.
func _followup_turn_start() -> void:
	if _player_turns == 1 and _tip_index == 0:
		await _say(G_TURN_TIPS[FOLLOWUP_TIP_ORDER[0]])
		_tip_index = 1
		_turn_start_spoke = true
	var spoke: bool = await _once("g_click_hand", G_CLICK_HAND)
	if spoke:
		_turn_start_spoke = true
	if _player_at_risk():
		spoke = await _once("g_risk", G_AT_RISK, {"[POKEMON]": _name(main.player_active_pokemon)})
		if spoke:
			_turn_start_spoke = true
	spoke = await _maybe_evolution_message()
	if spoke:
		_turn_start_spoke = true
	if not _turn_start_spoke and _tip_index < FOLLOWUP_TIP_ORDER.size():
		await _say(G_TURN_TIPS[FOLLOWUP_TIP_ORDER[_tip_index]])
		_tip_index += 1


## Any pile, hand or bench clicked open. Not awaited by the core.
func on_pile_viewed(card_array: Array) -> void:
	if not active():
		return
	if card_array == main.player_hand:
		on_hand_opened()
		return
	var key := ""
	if card_array == main.opponent_hand: key = "opponent_hand"
	elif card_array == main.player_discard_pile: key = "player_discard"
	elif card_array == main.opponent_discard_pile: key = "opponent_discard"
	elif card_array == main.player_bench: key = "player_bench"
	elif card_array == main.opponent_bench: key = "opponent_bench"
	elif card_array == main.player_prize_cards: key = "player_prizes"
	elif card_array == main.opponent_prize_cards: key = "opponent_prizes"
	if key == "":
		return
	# Until the player's first turn is over, every click explains the pile again. After
	# that, only a pile they have not had explained yet (once, then never again).
	var first_turn_over: bool = _player_turns > 1 or (_player_turns == 1 and main.opponents_turn_active)
	if not first_turn_over:
		_seen["pile_" + key] = true
		_deferred_say([PILE_LINES[key]])
	else:
		_deferred_once("pile_" + key, [PILE_LINES[key]])


func on_hand_opened() -> void:
	if not active() or main.opponents_turn_active:
		return
	_hand_opened = true
	if mode == "newby":
		_newby_hand_opened()
	else:
		_deferred_once("g_hand", G_HAND_OPENED)


## The Energy attach screen has just opened.
func on_attach_screen(energy) -> void:
	# Every time, until the Energy is attached: cancelling out and coming back must not
	# leave the player with no instructions.
	if mode == "newby" and _step == "t1_attach":
		_deferred_say(NEWBY_T1_ATTACH_SCREEN)


## An Energy finished landing on `target`.
func on_energy_attached(energy, target) -> void:
	if not active():
		return
	if mode == "newby":
		await _newby_energy_attached(energy, target)
		return
	if target != main.player_active_pokemon:
		return
	var usable = _first_usable_attack(target)
	if not usable.is_empty() and main._player_can_attack_now():
		await _once("g_can_attack", G_CAN_ATTACK, {
			"[POKEMON]": _name(target), "[ATTACK]": usable.get("name", ""),
			"[DEFENDER]": _name(main.opponent_active_pokemon)})
	elif not main._player_can_attack_now() or usable.is_empty():
		await _once("g_end_turn_hint", G_END_TURN_HINT)


## A card was benched from the hand (not during setup).
func on_benched(card) -> void:
	_player_ever_benched = true
	if mode == "newby":
		await _newby_benched(card)


## A Trainer card finished resolving.
func on_trainer_played(card) -> void:
	if not active():
		return
	if mode == "newby":
		await _newby_trainer(card)
	else:
		await _maybe_evolution_message()


func on_evolved(card) -> void:
	if mode == "newby":
		await _newby_evolved(card)


## After an attack's damage has landed (either side).
func on_attack_damage(attacker, defender, final_damage: int, modifiers: Array, attacker_is_opponent: bool) -> void:
	if not active() or attacker == null or defender == null:
		return
	var weak := false
	var resist := false
	for m in modifiers:
		if "WEAKNESS" in String(m) and not "NO WEAKNESS" in String(m):
			weak = true
		if "RESISTANCE" in String(m) and not "NO RESISTANCE" in String(m):
			resist = true
	var fills := {"[ATTACKER]": _name(attacker), "[DEFENDER]": _name(defender),
		"[POKEMON]": _name(attacker if not attacker_is_opponent else defender)}
	if mode == "newby":
		await _newby_attack(attacker, defender, weak, resist, fills, attacker_is_opponent)
		return
	if weak and not attacker_is_opponent:
		fills["[TYPE]"] = main.get_pokemon_type(attacker)
		await _once("g_weak_dealt", G_WEAKNESS_DEALT, fills)
	elif weak and attacker_is_opponent:
		fills["[TYPE]"] = main.get_pokemon_type(attacker)
		await _once("g_weak_taken", G_WEAKNESS_TAKEN, fills)
	if resist:
		fills["[TYPE]"] = main.get_pokemon_type(attacker)
		await _once("g_resist", G_RESISTANCE if final_damage <= 0 else G_RESISTANCE_SOME, fills)


## The prize selection screen has opened. Not awaited by the core.
func on_prize_shown() -> void:
	if active():
		_deferred_once("g_prize", G_PRIZE)


## Called when any Pokemon is knocked out, before it leaves the board.
func note_knockout(pokemon, owner_is_player: bool) -> void:
	if owner_is_player and pokemon == main.player_active_pokemon:
		_last_player_ko_name = _name(pokemon)


## The player's Active is gone. `has_bench` false means the match is about to be lost.
func on_player_active_ko(has_bench: bool) -> void:
	if not active():
		return
	var fills := {"[POKEMON]": _last_player_ko_name}
	if mode == "newby":
		if has_bench and _step == "t2_done":
			_step = "t3_wait"
			await _once("n_voltorb_ko", NEWBY_T3_VOLTORB_KO)
		return
	if not has_bench and not _player_ever_benched:
		await _once("g_ko_no_bench", G_KO_NO_BENCH, fills)
	elif has_bench:
		await _once("g_ko_bench", G_KO_WITH_BENCH, fills)


## Retreat's Energy is paid and the bench is up to pick the new Active. Not awaited.
func on_retreat_bench_shown() -> void:
	if mode == "newby" and _step == "t5_retreat":
		_step = "t5_pick"
		_deferred_once("n_retreat_pick", NEWBY_T5_PICK)


## The retreat swap has finished animating.
func on_retreat_done() -> void:
	if mode == "newby" and _step == "t5_pick":
		_step = "t5_machop"
		await _once("n_retreat_done", NEWBY_T5_RETREATED)


# ============================================================
# GATES — the core asks before acting; a non-empty answer blocks it
# ============================================================
# kind: "end_turn" | "attack" (data.attack) | "retreat" | "power" | "play" (data.card,
# data.action) | "attach" (data.energy, data.target) | "heal" (data.target --
# filters a heal effect's target list)

func gate(kind: String, data: Dictionary = {}) -> String:
	if not active() or main.opponents_turn_active:
		return ""
	if mode == "newby":
		return _newby_gate(kind, data)
	# The generic set blocks one thing: ending the first turn before the hand is opened.
	if kind == "end_turn" and not _hand_opened and _player_turns <= 1:
		return G_BLOCK_END_BEFORE_HAND
	return ""


# ============================================================
# GENERIC HELPERS
# ============================================================

func _first_usable_attack(mon) -> Dictionary:
	if mon == null:
		return {}
	for a in main.get_attacks_for_card(mon):
		if main.check_attack_requirements(a, mon) and not main.is_attack_disabled(mon, a.get("name", "")):
			return a
	return {}


## The opponent could knock the player's Active out next turn, with what it has
## attached plus one more Energy.
func _player_at_risk() -> bool:
	var mine = main.player_active_pokemon
	var theirs = main.opponent_active_pokemon
	if mine == null or theirs == null:
		return false
	for a in main.get_attacks_for_card(theirs):
		var cost: int = a.get("cost", []).size()
		if cost > theirs.attached_energies.size() + 1:
			continue
		var base := int(String(a.get("damage", "0")).to_int())
		if base <= 0:
			continue
		var res: Dictionary = main.calculate_final_damage(base, theirs.metadata.get("types", ["Colorless"]), mine, theirs)
		if int(res.get("damage", 0)) >= mine.current_hp:
			return true
	return false


## The player holds an evolution for something they have in play.
func _maybe_evolution_message() -> bool:
	if _seen.has("g_evolution") or mode == "newby":
		return false
	var field: Array = main.player_bench.duplicate()
	if main.player_active_pokemon != null:
		field.append(main.player_active_pokemon)
	for c in main.player_hand:
		var subtypes: Array = c.metadata.get("subtypes", [])
		if not ("Stage 1" in subtypes or "Stage 2" in subtypes):
			continue
		for f in field:
			if main.can_evolve_from(c, f):
				return await _once("g_evolution", G_EVOLUTION)
	return false


# ============================================================
# NEWBY — the scripted match (NewbyTutorialMatch.txt)
# ============================================================
# Driven by the player's turn number: the decks are stacked, so every turn holds the
# same cards. _step names the beat inside a turn; _newby_gate() reads it to decide what
# is blocked and with which line.

const NEWBY_SETUP := [
	"When you start a match, you must choose a Pokémon card from your hand to play as your Active Pokémon...",
	"After setting your active pokemon, if you have more Pokémon in your hand, you can place up to 5 on your bench.",
]
const NEWBY_COIN := ["A coin is flipped at the start of every game to decide which player goes first. Choose heads or tails"]
const NEWBY_AUTO_DRAW := ["You automatically draw a card from your deck and add it to your hand at the start of every turn."]
# The very first thing on the player's first turn, before "Click your hand" ("newby" and "rules").
const NEWBY_T1_AIM := [
	"In the Pokemon TCG the general aim is to knock out your opponent's Pokemon...",
	"You will do this by attacking their active Pokemon with your active Pokemon...",
	"Knocking out an opponent's Pokemon wins you a 'Prize Card'...",
	"To win - take every prize card, or knockout all of your opponents Pokemon...",
	"Every Pokemon needs 'Energy' attached to it in order to use one of its attacks...",
	"You will first need to attach an energy card to your active [POKEMON]...",
]
const NEWBY_T1_CLICK_HAND := ["Click your hand to see every card you're holding there and to play them."]
const NEWBY_T1_HAND := [
	"You are now looking at all the cards in your hand...",
	"You can select any cards in here by clicking them and play them by pressing the action button below...",
	"Some cards can't always be played. Try attaching an energy card to your Voltorb first.",
]
const NEWBY_T1_ATTACH_SCREEN := [
	"Every attack has an Energy Requirement to use and you can only attach 1 energy card per turn...",
	"Attacking doesn't discard the attached energy and different attacks have different requirements...",
	"Voltorb's Tackle attack has a single white energy icon next to it. This icon means 'Colorless' Energy...",
	"A Colorless energy requirement can be met with any energy card of any type...",
	"Select Voltorb and attach the Fighting Energy to it",
]
const NEWBY_T1_ATTACHED := [
	"Voltorb can now attack using Tackle. Don't forget to attach an energy every turn when you can...",
	"Press the Tackle button to attack with Voltorb.",
]
const NEWBY_T1_WEAKNESS := [
	"Even though Voltorb's Tackle attack should do 10 damage, Magikarp lost 20hp...",
	"Pokemon may have a Weakness to a type, doubling the damage dealt...",
	"Because Voltorb is a lightning type and Magikarp has a Lightning Weakness, Magikarp takes double damage!",
	"Only the attacking Pokemon's type matters, not the energy required to attack.",
]
const NEWBY_T2_START := [
	"It is now your turn again. Voltorb only has 20hp left and is at risk of being knocked out...",
	"If you have no Bench Pokemon and your Active Pokemon is knocked out then you instantly lose the match!",
	"If you had a Pokemon on your bench you could swap Voltorb out by Retreating. Instead, open your hand to play a trainer card.",
]
const NEWBY_T2_BILL := [
	"Bill has added a new Pokemon to your hand. Your new Voltorb can be placed onto the bench...",
	"This will give you a backup ready for when your active Voltorb is knocked out...",
	"Open your hand and play Voltorb onto your bench.",
]
const NEWBY_T2_BENCHED := [
	"You now have another Pokemon as a backup for Voltorb. You can start to get Voltorb ready to attack while it is benched...",
	"Open your hand and attach an energy card to the Benched Voltorb.",
]
const NEWBY_T2_BENCH_ENERGY := [
	"Your benched Voltorb is now ready if your active Voltorb is knocked out...",
	"You can safely knockout Magikarp by attacking with Tackle again.",
]
const NEWBY_T3_VOLTORB_KO := [
	"Oh no! Your Voltorb was weak to Diglett so it took double damage and was knocked out...",
	"You will now need to set one of your Bench Pokemon as your new active Pokemon...",
	"You only have another Voltorb, set that as your active Pokemon for now...",
]
const NEWBY_T3_START := [
	"As you have no other bench pokemon, if Voltorb is knocked out you will lose...",
	"Professor Oak may help. Select it and play it from your hand.",
]
const NEWBY_T3_OAK := [
	"You now have a better matchup against Diglett. Ponyta isn't weak to Fighting type attacks...",
	"Place Ponyta on your bench and attach a Fire Energy to it.",
]
const NEWBY_T3_FIRE := ["Ponyta still needs another energy card in order to attack. To keep Ponyta at full HP before then, attack with Voltorb instead."]
const NEWBY_T3_RESIST := [
	"Just like having a Weakness to a type, some Pokemon have a Resistance to a type...",
	"Diglett has a Lightning resistance so Voltorb did no damage!",
	"All resistances reduce damage dealt by 30.",
]
const NEWBY_T4_START := [
	"You have another Pokemon in your hand now and Ponyta can't attack yet...",
	"Put Machop on your bench and attach another fire energy to Ponyta.",
]
const NEWBY_T5_START := [
	"Ponyta is at risk of being knocked out now, but Machop has full HP so it might be useful to retreat Ponyta to the bench...",
	"Most Pokemon have to discard energy cards to retreat but some Pokemon have a free retreat cost...",
	"You can only retreat when you have at least 1 Pokemon on your bench and can only retreat once per turn...",
	"Press the retreat button to retreat Ponyta and discard a Fire energy.",
]
const NEWBY_T5_PICK := [
	"You must replace your retreated Pokemon with a Pokemon from your bench, setting that Benched Pokemon as your new Active Pokemon...",
	"Select your Benched Machop and set it as your active Pokemon.",
]
const NEWBY_T5_RETREATED := [
	"Ponyta has now retreated to the bench and Machop is now your active Pokemon...",
	"Attach a fighting energy to Machop and attack with Low Kick to knock out your opponent's Diglett",
]
const NEWBY_T6_START := [
	"Your opponent has attached a Defender card to their active Rattata...",
	"Rattata is weak to fighting so Machop would deal double damage and knock out Rattata...",
	"However, Defender reduces the damage by 20, reducing the damage back to 20 leaving Rattata with 10hp...",
	"Luckily you have just drawn a Pluspower card and can play it now...",
	"Playing Pluspower allows your active Pokemon to deal an additional 10 damage!",
	"Play Pluspower now to attach it to Machop and knockout Rattata!",
]
const NEWBY_T7_START := [
	"Dratini has no weakness at all so Machop can only do 20 damage to it...",
	"Without another Fire Energy, Ponyta doesn't do more damage and you don't have any more Pluspowers either...",
	"Some Pokemon can evolve to unlock better attacks and more HP!",
	"You can't evolve a Pokemon on the same turn it has been put onto the field or evolved already",
	"Select Machoke in your hand and play it to Evolve your Machop",
]
const NEWBY_T7_EVOLVED := [
	"Machoke needs 3 Energies to attack and Machop only has 1...",
	"It is nearly always a good idea to evolve but there are often times you should wait...",
	"Attach another Fighting Energy to Machoke so it can attack next turn.",
]
# The opponent's Energy Removal (its turn 7) leaves Machop on 1 Energy, so after this attach
# Machoke has 2 of the 3 it needs and cannot attack until next turn.
const NEWBY_T7_ENERGY := ["If you can't attack and have no other cards to play, you can finish your turn with the End Turn button."]
const NEWBY_T8_START := [
	"Most Evolved Pokemon have higher HP and better attacks than their Basic stage Pokemon",
	"When a Pokemon evolves, it heals any status conditions but keeps its damage counters...",
	"Machoke's Karate Chop should do 50 damage but not while Machoke is damaged...",
	"Machoke can only do 10 damage now. Try playing Bill to draw more useful cards.",
]
const NEWBY_T8_BILL := [
	"Potion heals a Pokemon for 20hp. You have 2 potions in your hand now.",
	"Play both potions to fully heal Machoke",
]
const NEWBY_T8_HEALED := [
	"Your Machoke is back to full HP so Karate Chop will do the full 50 damage and knockout Dratini...",
	"Use Karate Chop to knockout Dratini, take your last Prize card and win the match!",
]


func _newby_turn_start() -> void:
	match _player_turns:
		1:
			_step = "t1_hand"
			await _once("n_t1_aim", NEWBY_T1_AIM, {"[POKEMON]": _name(main.player_active_pokemon)})
			await _once("n_t1", NEWBY_T1_CLICK_HAND)
			# ISSUE #475: the Caps Lock hint moved here from the very first screen.
			await _once("n_caps", [CAPS_HINT])
		2:
			_step = "t2_bill"
			await _once("n_t2", NEWBY_T2_START)
		3:
			_step = "t3_oak"
			await _once("n_t3", NEWBY_T3_START)
		4:
			_step = "t4"
			await _once("n_t4", NEWBY_T4_START)
		5:
			_step = "t5_retreat"
			await _once("n_t5", NEWBY_T5_START)
		6:
			_step = "t6_pluspower"
			await _once("n_t6", NEWBY_T6_START)
		7:
			_step = "t7_evolve"
			await _once("n_t7", NEWBY_T7_START)
		8:
			_step = "t8_bill"
			await _once("n_t8", NEWBY_T8_START)
		_:
			_step = "free"


# What to do next, said again when the player opens their hand a SECOND time in the same
# step -- they opened it, backed out (cancelled) without doing the thing, and came back.
const NEWBY_REMINDERS := {
	"t1_attach":       "Some cards can't always be played. Try attaching an energy card to your Voltorb first.",
	"t2_bill":         "Play Bill and draw more cards.",
	"t2_bench":        "Play Voltorb onto your bench.",
	"t2_bench_energy": "Attach an energy card to the Benched Voltorb.",
	"t3_oak":          "Professor Oak may help. Select it and play it from your hand.",
	"t3_ponyta":       "Place Ponyta on your bench and attach a Fire Energy to it.",
	"t3_fire":         "Attach a Fire Energy card to Ponyta.",
	"t4":              "Put Machop on your bench and attach another fire energy to Ponyta.",
	"t5_machop":       "Attach a fighting energy to Machop and attack with Low Kick to knock out your opponent's Diglett",
	"t6_pluspower":    "Play Pluspower now to attach it to Machop and knockout Rattata!",
	"t6_energy":       "Attach another Fighting Energy to Machop.",
	"t7_evolve":       "Select Machoke in your hand and play it to Evolve your Machop",
	"t7_energy":       "Attach another Fighting Energy to Machoke so it can attack next turn.",
	"t8_bill":         "Play Bill to draw more useful cards.",
	"t8_potions":      "Play both potions to fully heal Machoke",
}
var _last_hand_step: String = ""


func _newby_hand_opened() -> void:
	if _step == "t1_hand":
		_step = "t1_attach"
		_last_hand_step = _step
		_deferred_once("n_t1_hand", NEWBY_T1_HAND)
		return
	if _step == _last_hand_step and NEWBY_REMINDERS.has(_step):
		_deferred_say([NEWBY_REMINDERS[_step]])
	_last_hand_step = _step


func _newby_energy_attached(energy, target) -> void:
	var tname := _name(target)
	match _step:
		"t1_attach":
			_step = "t1_attack"
			await _once("n_t1_attached", NEWBY_T1_ATTACHED)
		"t2_bench_energy":
			if target != main.player_active_pokemon:
				_step = "t2_attack"
				await _once("n_t2_energy", NEWBY_T2_BENCH_ENERGY)
		"t3_fire":
			if tname == "Ponyta":
				_step = "t3_attack"
				await _once("n_t3_fire", NEWBY_T3_FIRE)
		"t5_machop":
			if target == main.player_active_pokemon:
				_step = "t5_attack"
		"t6_energy":
			if target == main.player_active_pokemon:
				_step = "t6_attack"
		"t7_energy":
			if target == main.player_active_pokemon:
				_step = "t7_done"
				await _once("n_t7_energy", NEWBY_T7_ENERGY)


func _newby_benched(card) -> void:
	match _step:
		"t2_bench":
			_step = "t2_bench_energy"
			await _once("n_t2_benched", NEWBY_T2_BENCHED)
		"t3_ponyta":
			if _name(card) == "Ponyta":
				_step = "t3_fire"


func _newby_trainer(card) -> void:
	var n := _name(card)
	match _step:
		"t2_bill":
			if n == "Bill":
				_step = "t2_bench"
				await _once("n_t2_bill", NEWBY_T2_BILL)
		"t3_oak":
			if n == "Professor Oak":
				_step = "t3_ponyta"
				await _once("n_t3_oak", NEWBY_T3_OAK)
				await _once("n_caps_again", CAPS_REMINDER)   # ISSUE #475: Ponyta has just been drawn
		"t6_pluspower":
			if n == "PlusPower":
				_step = "t6_energy"
				await _once("n_shift", SHIFT_HINT)   # ISSUE #475
		"t8_bill":
			if n == "Bill":
				_step = "t8_potions"
				_potions_played = 0
				await _once("n_t8_bill", NEWBY_T8_BILL)
		"t8_potions":
			if n == "Potion":
				_potions_played += 1
				# Done once Machoke is healed -- or once the Potions are gone, so a Potion spent on
				# Ponyta cannot leave the player stuck behind the "heal Machoke" block.
				var machoke = main.player_active_pokemon
				var healed: bool = machoke != null and machoke.current_hp >= machoke.get_max_hp()
				var potions_left: bool = main.player_hand.any(func(c): return _name(c) == "Potion")
				if healed:
					_step = "t8_attack"
					await _once("n_t8_healed", NEWBY_T8_HEALED)
				elif not potions_left:
					_step = "t8_attack"


func _newby_evolved(card) -> void:
	if _step == "t7_evolve" and _name(card) == "Machoke":
		_step = "t7_energy"
		await _once("n_t7_evolved", NEWBY_T7_EVOLVED)


func _newby_attack(attacker, defender, weak: bool, resist: bool, fills: Dictionary, attacker_is_opponent: bool) -> void:
	if attacker_is_opponent:
		return
	if _step == "t1_attack" and weak:
		_step = "t1_done"
		await _once("n_t1_weak", NEWBY_T1_WEAKNESS)
	elif _step == "t2_attack":
		_step = "t2_done"
	elif _step == "t3_attack" and resist:
		_step = "t3_done"
		await _once("n_t3_resist", NEWBY_T3_RESIST)


const NEWBY_BLOCK_POTION_PONYTA := "Ponyta won't help much more now. Save your Potions for Machoke."


## What the newby player may not do right now, and why. "" = allowed.
func _newby_gate(kind: String, data: Dictionary) -> String:
	var card = data.get("card", null)
	var energy = data.get("energy", null)
	var target = data.get("target", null)
	var attack_name: String = String(data.get("attack", {}).get("name", "")) if data.get("attack") is Dictionary else ""
	var active = main.player_active_pokemon
	var energy_type: String = main.get_energy_type_from_card(energy) if energy != null else ""
	var is_energy_play: bool = kind == "play" and String(data.get("action", "")) == "ATTACH_ENERGY"
	# Potions are for Machoke: Ponyta is never a heal target, and a Potion can't be played
	# while Ponyta is the only damaged Pokemon (it would have nothing to heal).
	if kind == "heal" and _name(target) == "Ponyta":
		return NEWBY_BLOCK_POTION_PONYTA
	if kind == "play" and _name(card) == "Potion":
		var field: Array = [active] + main.player_bench
		var healable: bool = field.any(func(p): return p != null and _name(p) != "Ponyta" and p.current_hp < p.get_max_hp())
		if not healable:
			return NEWBY_BLOCK_POTION_PONYTA
	match _step:
		"t1_hand":
			if kind == "end_turn":
				return "You don't want to end your turn yet. Click your hand first to start playing cards."
		"t1_attach":
			if kind == "end_turn":
				return "Click your hand, select a Fighting Energy and click the Attach button."
		"t1_attack":
			if kind == "end_turn":
				return "You don't want to end your turn without attacking. Use Voltorb's Tackle attack"
		"t2_bill":
			if kind in ["end_turn", "attack"]:
				return "Voltorb only has 20hp left and you are at risk of losing the match. Open your hand to play Bill and draw more cards."
			if is_energy_play:
				return "Play Bill and draw more cards first. You may draw something more useful."
		"t2_bench":
			if kind in ["end_turn", "attack"] or is_energy_play:
				return "Voltorb only has 20hp left and you are at risk of losing the match. Open your hand to place Voltorb onto your bench first."
		"t2_bench_energy":
			if kind in ["end_turn", "attack", "retreat"] or (kind == "attach" and target == active):
				return "Your active Voltorb is at risk of being knocked out and has enough energy already. Attach Fighting Energy to the Benched Voltorb."
		"t2_attack":
			if kind == "end_turn":
				return "You should attack Magikarp with Voltorb's tackle by pressing the Tackle attack button."
		"t3_oak":
			if kind in ["end_turn", "attack"]:
				return "Try playing Professor Oak from your hand to draw more cards."
			if is_energy_play:
				return "Voltorb doesn't need any more energy, play Professor Oak to draw more useful cards first."
		"t3_ponyta":
			if kind == "attach" and target == active:
				return "Voltorb is about to be knocked out, attach a Fire Energy to Ponyta instead"
			if kind in ["end_turn", "attack", "retreat"] or is_energy_play:
				return "Place Ponyta on your bench and attach a Fire Energy to it"
		"t3_fire":
			if kind == "attach" and target == active:
				return "Voltorb is about to be knocked out, attach a Fire Energy to Ponyta instead"
			if kind == "attach" and _name(target) == "Ponyta" and energy_type != "Fire":
				return "Pay attention to energy types. With 2 Fire energy, Ponyta can use the stronger 'Flame Tail' attack."
			if kind in ["end_turn", "attack", "retreat"]:
				return "Attach a Fire Energy card to Ponyta"
		"t3_attack":
			if kind in ["end_turn", "retreat"]:
				return "Press the Tackle button to attack Diglett with Voltorb's Tackle"
		"t4":
			var machop_benched := false
			for b in main.player_bench:
				if _name(b) == "Machop":
					machop_benched = true
			if kind == "attach" and _name(target) == "Ponyta" and energy_type != "Fire":
				return "Your Ponyta can attack Diglett with Flame Tail doing more damage than Smash Kick if you attach another Fire Energy"
			if kind == "attach" and _name(target) == "Machop" and energy_type == "Fire":
				return "Machop doesn't have Colorless energy requirements so can't use a Fire Energy. Attach it to Ponyta instead."
			if kind == "retreat":
				return "Retreating isn't a great choice here. Attach a fire energy to Ponyta and attack with Flame Tail instead"
			if kind == "attack" and not machop_benched:
				return "Attacking will end your turn. Put Machop on your bench first before you attack."
			if kind == "attack" and attack_name == "Smash Kick":
				return "Flame Tail does more damage than Smash kick. Attack with Flame Tail instead."
			if kind == "end_turn":
				return "Put Machop on your bench and attach another Fire Energy to Ponyta."
		"t5_retreat":
			if kind in ["end_turn", "attack"] or is_energy_play:
				return "Ponyta is at risk of being knocked out. Use the Retreat button to Retreat Ponyta to your Bench."
		"t5_machop":
			if kind == "attach" and target != active:
				return "Ponyta has just retreated and Machop is now active. Attach Fighting Energy to Machop instead."
			if kind in ["end_turn", "attack"]:
				return "Attach a fighting energy to Machop and attack with Low Kick to knock out your opponent's Diglett"
		"t5_attack":
			if kind == "end_turn":
				return "You should attack with Low Kick to knockout your opponent's Pokemon!"
		"t6_pluspower":
			if kind in ["end_turn", "attack"] or is_energy_play:
				return "Play Pluspower now to attach it to Machop and knockout Rattata!"
		"t6_energy":
			if kind in ["end_turn", "attack"] or (kind == "attach" and target != active):
				return "Make sure to still attach your regular Energy Card too. Attach another Fighting Energy to Machop."
		"t6_attack":
			if kind == "end_turn":
				return "Knock out the Opponent's Rattata with Machop's Low Kick attack."
		"t7_evolve":
			var evolving: bool = kind == "play" and String(data.get("action", "")) == "EVOLVE" and _name(card) == "Machoke"
			if not evolving:
				return "Play Machoke from your hand to evolve Machop"
		"t7_energy":
			if kind == "end_turn" or (kind == "attach" and target != active):
				return "Attach another Fighting Energy to Machoke so it can attack next turn"
		"t8_bill":
			if kind == "end_turn":
				return "Attach one more fighting Energy to Machoke and play Bill to draw more useful cards."
			if kind == "attack":
				return "Karate Chop will only do 10 damage. Bill might give you something useful to help."
			if kind == "retreat":
				return "Ponyta won't help much more now. Bill might give you something useful to help."
		"t8_potions":
			if kind == "end_turn":
				return "Recover your Machoke's HP by playing the Potion cards in your hand"
			if kind == "attack":
				return "Karate Chop will only do 10 (or 30) damage due to Machoke being damaged. Use your Potion cards to recover Machoke's HP and increase the damage Karate Chop will do."
			if kind == "retreat":
				return "Ponyta won't help much more now. Recover your Machoke's HP by playing the Potion cards in your hand."
	return ""
