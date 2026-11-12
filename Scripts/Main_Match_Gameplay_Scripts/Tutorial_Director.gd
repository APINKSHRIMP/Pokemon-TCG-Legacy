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
#             _newby_followup set (ISSUE #359 -- it used to be a "tips" mode with only the key
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
#
# TWO CONTROL SCHEMES. When the tutorial starts (setup()) it looks at the device the
# player last used (InputDevice.last) and locks itself into one of them for the match:
#   "km"   mouse + keyboard. Cards are DRAGGED straight off the hand bar (Hand_Drag.gd),
#          so nothing waits for the hand to be opened: every line says what to drag
#          where. Alt + click still opens the large hand view.
#   "pad"  a controller. The hand is one cursor stop that A opens (Board_Nav.gd), so the
#          old "open your hand first" steps and blocks stay.
# Every line that differs is a *_KM / *_PAD pair picked by _cm(). Pad button names are
# written as [PAD_A], [PAD_LB]... and become "[A]" / "[CROSS]" etc. for the connected
# pad's family when the line is shown (_keys()).

const ControllerDiagram := preload("res://Scripts/Menu_Scripts/Controller_Diagram.gd")

var main: Node = null
var mode: String = ""
## "km" or "pad" -- locked in setup() for the whole match. See TWO CONTROL SCHEMES above.
var controls: String = "km"
var _newby_followup: bool = false   # ISSUE #359: the newby's second match

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
var _player_ever_retreated: bool = false   # the at-risk / retreat line is never needed after this
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
	# The control scheme the whole tutorial speaks in (a pad user gets the pad lines).
	controls = "pad" if InputDevice.last == InputDevice.PAD else "km"
	if mode != "":
		print("TUTORIAL: mode ", mode, " (controls: ", controls, ")")
	# ISSUE #344: Options shows the tutorial row locked On while a must-finish tutorial runs.
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
	GameState.mandatory_tutorial_running = false   # ISSUE #344
	_clear_callouts()
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
	if mode == "newby":
		# The bench-setup screen comes up next: nothing left to bench, so press Done.
		_deferred_once("n_bench_setup", _cm(NEWBY_BENCH_SETUP_KM, NEWBY_BENCH_SETUP_PAD))
		return
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

## The control scheme's version of a line / set of lines.
func _cm(km, pad):
	return pad if controls == "pad" else km


func _is_pad() -> bool:
	return controls == "pad"


# [PAD_*] tokens -> the pad's own button names (Controller_Diagram's table), in capitals
# and brackets like the keyboard's [SHIFT]: "[PAD_A]" -> "[A]" on Xbox, "[CROSS]" on PlayStation.
const PAD_TOKENS := {
	"[PAD_A]": "a", "[PAD_B]": "b", "[PAD_X]": "x", "[PAD_Y]": "y",
	"[PAD_LB]": "lb", "[PAD_RB]": "rb", "[PAD_LSTICK]": "lstick", "[PAD_RSTICK]": "rstick",
	"[PAD_DPAD]": "dpad", "[PAD_VIEW]": "view", "[PAD_MENU]": "menu",
}


func _keys(text: String) -> String:
	if not "[PAD_" in text:
		return text
	var family: String = InputDevice.pad_family()
	for token in PAD_TOKENS:
		text = text.replace(token, "[" + ControllerDiagram.button_name(PAD_TOKENS[token], family).to_upper() + "]")
	return text


func _say(lines: Array, fills: Dictionary = {}) -> void:
	_busy = true
	for line in lines:
		var text := String(line)
		for k in fills:
			text = text.replace(k, str(fills[k]))
		await main.show_message(_keys(text), true, "tutorial")
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
	print("TUTORIAL BLOCK (step '", _step, "'): ", text)
	_block_showing = true
	await main.show_message(_keys(text), true, "tutorial")
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

# The first thing on the player's first turn: how to play cards at all.
const G_CLICK_HAND_KM := [
	"Your hand is along the bottom of the screen. Play cards straight from it by dragging them with the mouse...",
	"Drag an Energy onto one of your Pokemon to attach it, or an Evolution onto the Pokemon it evolves from...",
	"Drag a Basic Pokemon up onto your bench, and drag a Trainer card into the middle of the board to play it...",
	"Trainers that are used on one Pokemon, like a Potion, can be dropped straight onto that Pokemon instead.",
]
const G_CLICK_HAND_PAD := [
	"Use the [PAD_LSTICK] or [PAD_DPAD] to move the cursor between your hand, your Pokemon and attacks...",
	"Press [PAD_A] to open or use whatever the cursor is on...",
	"Your cursor starts on your hand every turn. Press [PAD_A] to open it and see every card you're holding.",
]
# The newby's SECOND match already knows dragging (Olly's match taught it): its first turn only
# adds the one thing it has not seen. One line each.
const FOLLOWUP_CLICK_HAND_KM := ["As well as dragging cards from your hand to play them, you can hold [ALT] and click your hand to open it and play cards from there."]
const FOLLOWUP_CLICK_HAND_PAD := ["[PAD_X] jumps the cursor to your hand, [PAD_Y] to End Turn and [PAD_RB] to your Active's attacks. [PAD_B] backs out of most screens."]
const G_BLOCK_END_BEFORE_HAND_KM := "You don't want to end your turn yet. Drag a card from your hand to play it first."
const G_BLOCK_END_BEFORE_HAND_PAD := "You don't want to end your turn yet. Press [PAD_A] on your hand first to start playing cards."
# The large hand view opened (pad: A on the hand; mouse: Alt + click).
const G_HAND_OPENED_KM := ["In here you can play a card by clicking it and pressing the action button below, or by double clicking it."]
const G_HAND_OPENED_PAD := ["Move the cursor onto a card to select it and press [PAD_A] to play it. [PAD_B] closes your hand again."]
const G_CAN_ATTACK_KM := ["[POKEMON] can now use [ATTACK]. Click the [ATTACK] button to attack your opponent's [DEFENDER]!"]
const G_CAN_ATTACK_PAD := ["[POKEMON] can now use [ATTACK]. Press [PAD_RB], then [PAD_A] on [ATTACK] to attack your opponent's [DEFENDER]!"]
const G_WEAKNESS_DEALT := ["[DEFENDER] is weak to your [POKEMON]'s [TYPE] type so it takes double damage!"]
# 2026-11-12: two lines, never on the first turn, never once the player has retreated by
# themselves, and never when the Pokemon at risk can evolve (the evolution line goes instead).
const G_AT_RISK_KM := [
	"Your [POKEMON] is at risk of being knocked out. If your Active Pokémon is knocked out with no Benched Pokémon, you instantly lose the match!",
	"If you have a Benched Pokémon, you can retreat [POKEMON] by dragging it onto your Bench, or by clicking Retreat.",
]
const G_AT_RISK_PAD := [
	"Your [POKEMON] is at risk of being knocked out. If your Active Pokémon is knocked out with no Benched Pokémon, you instantly lose the match!",
	"If you have a Benched Pokémon, you can retreat [POKEMON]: press [PAD_RB], move onto Retreat and press [PAD_A].",
]
const G_PRIZE := [
	"You have knocked out your opponent's Pokemon! You can now take one of your 'Prize cards'!",
	"Prize cards are taken from the top of your deck and placed here when the match first starts...",
	"If you take all of your prize cards in a match, you win!",
	"The prize card you take from here is added to your hand.",
]
const G_WEAKNESS_TAKEN := ["Oh no! Your [POKEMON] was weak to [ATTACKER]'s [TYPE] type so it took double damage!"]
const G_KO_WITH_BENCH := ["Your [POKEMON] was knocked out. You now need to set one of your Bench Pokemon as your new Active..."]
const G_KO_NO_BENCH := [
	"Your [POKEMON] was knocked out and you have no Pokemon on your bench to set as your new Active...",
	"Even with prize cards left, if your active Pokemon is knocked out with no Benched Pokemon left you lose!",
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
# 2026-11-12: only once the evolution is legal RIGHT NOW (never turn 1), naming the two cards.
const G_EVOLUTION_KM := [
	"[EVO] can evolve from your [BASIC]. Drag [EVO] onto your [BASIC] to evolve it.",
	"Pokémon can't evolve on the same turn they were played or already evolved.",
]
const G_EVOLUTION_PAD := [
	"[EVO] can evolve from your [BASIC]. Open your hand, select [EVO], then select your [BASIC] to evolve it.",
	"Pokémon can't evolve on the same turn they were played or already evolved.",
]
const G_END_TURN_HINT_KM := ["If you can't attack or play any more cards, finish your turn by clicking End Turn. [Q] jumps straight to it."]
const G_END_TURN_HINT_PAD := ["If you can't attack or play any more cards, press [PAD_Y] to jump to End Turn, then [PAD_A]."]

# One per player turn from the 2nd, each pushed back a turn whenever another message
# already played at that turn's start. Keyed so the two schemes can have their own
# lists and orders (the mouse has an extra "Alt + click" tip). "attached" and "alt"
# come before "log" (the Caps Lock / View tip) on purpose.
const G_TIPS_KM := {
	"preview": ["Hover over a card and hold the [SHIFT] key to make it larger and examine it in greater detail...",
		"You can keep hold of the [SHIFT] key and move around the screen to hover over other cards."],
	"quick": ["Instead of dragging, you can double click a card in your hand to play it, and right click to cancel...",
		"Double clicking also works for most card effect choices, so you don't need to press the actual button...",
		"Try double clicking the next card you want to play, and right clicking to cancel."],
	"alt": ["You can also hold [ALT] and click your hand to open it large and look at every card fully...",
		"In there you can play cards by clicking them twice and choosing a target instead of dragging them."],
	"attached": ["Click a Pokemon in play to see every card attached to it, like its Energy, Tools and what it evolved from...",
		"Click your bench first to do the same for a Benched Pokemon...",
		"[V] and [C] show your Active and your opponent's Active straight away."],
	"log": ["Press the [CAPS LOCK] key to look at the match log and look at the historical data of your current match...",
		"It will show you a summary of your entire match so far."],
	"forfeit": ["You can forfeit and lose any match on your turn by pressing the [ESCAPE] key and choosing Forfeit."],
}
const G_TIPS_PAD := {
	"preview": ["Move the cursor onto a card and hold [PAD_LB] to make it larger and examine it in greater detail...",
		"You can keep hold of [PAD_LB] and move the cursor around to look at other cards."],
	"quick": ["[PAD_X] jumps the cursor to your hand, [PAD_Y] to End Turn and [PAD_RB] to your Active's attacks...",
		"[PAD_B] cancels and backs out of most screens."],
	"attached": ["Press [PAD_A] on a Pokemon in play to see every card attached to it, like its Energy and Tools...",
		"Pressing in the [PAD_RSTICK] shows your Active Pokemon straight away, wherever the cursor is."],
	"log": ["Press [PAD_VIEW] to look at the match log and look at the historical data of your current match...",
		"It will show you a summary of your entire match so far."],
	"forfeit": ["You can forfeit and lose any match on your turn by pressing [PAD_MENU] and choosing Forfeit."],
}
const G_TIP_ORDER_KM := ["preview", "quick", "alt", "attached", "log", "forfeit"]
const G_TIP_ORDER_PAD := ["preview", "quick", "attached", "log", "forfeit"]
## ISSUE #349: the newby's second match starts on the preview tip (first turn), then the
## rest. The "alt" / "attached" tips now come before the log tip here too.
## 2026-11-12: the preview (Shift) tip is no longer said on turn 1 -- turn 1 is the hand line only
## (FOLLOWUP_CLICK_HAND_*, which now carries the Alt tip / the pad's jump keys). Tips start turn 2,
## one per quiet turn start.
const FOLLOWUP_TIP_ORDER_KM := ["preview", "attached", "log", "quick", "forfeit"]
const FOLLOWUP_TIP_ORDER_PAD := ["preview", "attached", "log", "forfeit"]

# Viewing a pile for the first time (both NewbyTutorialMatch.txt and the generic set).
const PILE_LINES := {
	"opponent_hand":    "You are viewing your opponent's hand. You cannot see what cards they have",
	"player_discard":   "You are viewing your discard pile. Your trainer cards, discarded energy or knocked out pokemon go here",
	"opponent_discard": "You are viewing your opponent's discard pile. Their trainers, energy or knocked out pokemon go here",
	"player_bench":     "You are viewing your bench. All of your benched pokemon will be shown here",
	"opponent_bench":   "You are viewing your opponent's bench. All of their benched pokemon will be shown here",
	"player_prizes":    "You are viewing your prize cards. You take one every time you knock out one of your opponent's Pokemon",
	"opponent_prizes":  "You are viewing your opponent's prize cards. They take one each time they knock out one of your Pokemon",
}


func _generic() -> bool:
	return mode == "rules" or mode == "generic"


# ============================================================
# HOOKS — called by the match core
# ============================================================

## The opening screen: the hand, waiting for an Active to be chosen.
const CAPS_HINT_KM := "Press [CAPS LOCK] to read back any of these help messages"
const CAPS_HINT_PAD := "Press [PAD_VIEW] to read back any of these help messages"


func _caps_hint() -> String:
	return _cm(CAPS_HINT_KM, CAPS_HINT_PAD)


func on_setup_screen() -> void:
	# First thing in any match with tutorial help.
	# ISSUE #349: not the Caps Lock hint for the newby (it comes after "click your hand" now) nor
	# for their second match (Caps Lock is one of its turn tips).
	if mode == "":
		return
	var lines: Array = []
	if mode != "newby" and not _newby_followup:
		lines.append(_caps_hint())
	if mode == "newby":
		lines.append_array(_cm(NEWBY_SETUP_KM, NEWBY_SETUP_PAD))
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
## ISSUE #349: the newby's second match takes the tips in this order -- Shift on the very first
## turn (as the first card is drawn), then Caps Lock on the next turn nothing else is said.


## The turn tip under `key` for this control scheme.
func _tip(key: String) -> Array:
	return (_cm(G_TIPS_KM, G_TIPS_PAD) as Dictionary).get(key, [])


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
		await _once("n_t1_aim", RULES_T1_AIM, {"[POKEMON]": _name(main.player_active_pokemon)})
	if _player_turns <= 1:
		await _once("g_click_hand", _cm(G_CLICK_HAND_KM, G_CLICK_HAND_PAD))
		return
	await _one_turn_start_message(_cm(G_TIP_ORDER_KM, G_TIP_ORDER_PAD))


## ISSUE #349 / #485: the newby's second match. 2026-11-12: turn 1 is ONE line (the Alt / pad jump
## tip); every later turn start says at most one thing (_one_turn_start_message).
func _followup_turn_start() -> void:
	if _player_turns <= 1:
		await _once("g_click_hand", _cm(FOLLOWUP_CLICK_HAND_KM, FOLLOWUP_CLICK_HAND_PAD))
		return
	await _one_turn_start_message(_cm(FOLLOWUP_TIP_ORDER_KM, FOLLOWUP_TIP_ORDER_PAD))


## 2026-11-12 (user: "don't play multiple messages at once"): a turn start says ONE thing, the most
## useful one, and anything else waits for a later turn start that is quiet:
##   1. the evolution line, when an evolution is legal right now (an Active that is at risk AND can
##      evolve gets this, not the retreat line -- evolving is the better answer);
##   2. the at-risk / retreat line (turn 2 on, never once the player has retreated by themselves);
##   3. the next turn tip.
func _one_turn_start_message(order: Array) -> void:
	var evo: Array = _evolution_pair()
	if not evo.is_empty() and not _seen.has("g_evolution"):
		await _evolution_message(evo)
		_turn_start_spoke = true
		return
	if _risk_message_due(evo):
		await _once("g_risk", _cm(G_AT_RISK_KM, G_AT_RISK_PAD), {"[POKEMON]": _name(main.player_active_pokemon)})
		_turn_start_spoke = true
		return
	if not _turn_start_spoke and _tip_index < order.size():
		await _say(_tip(order[_tip_index]))
		_tip_index += 1
		_turn_start_spoke = true


func _risk_message_due(evo: Array) -> bool:
	if _seen.has("g_risk") or _player_turns <= 1 or _player_ever_retreated:
		return false
	if not _player_at_risk():
		return false
	# The Active can evolve right now: the evolution line is the answer, not retreating.
	if not evo.is_empty() and evo[1] == main.player_active_pokemon:
		return false
	for c in main.player_hand:
		if main.get_valid_evolution_targets(c, false).has(main.player_active_pokemon):
			return false
	return true


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
		_deferred_once("g_hand", _cm(G_HAND_OPENED_KM, G_HAND_OPENED_PAD))


## Mouse play never opens the hand, so anything played from it counts as "used the hand"
## for the generic End Turn block.
func _note_hand_used() -> void:
	if not main.opponents_turn_active:
		_hand_opened = true


## The Energy attach screen has just opened.
## Nothing is said here any more: in the newby match the screen only lists the Pokemon the
## Energy may go on (filter_attach_targets), so it cannot go wrong. Kept as the core's hook.
func on_attach_screen(_energy) -> void:
	pass


## An Energy finished landing on `target`.
func on_energy_attached(energy, target) -> void:
	if not active():
		return
	_note_hand_used()
	if mode == "newby":
		await _newby_energy_attached(energy, target)
		return
	if target != main.player_active_pokemon:
		return
	var usable = _first_usable_attack(target)
	if not usable.is_empty() and main._player_can_attack_now():
		await _once("g_can_attack", _cm(G_CAN_ATTACK_KM, G_CAN_ATTACK_PAD), {
			"[POKEMON]": _name(target), "[ATTACK]": usable.get("name", ""),
			"[DEFENDER]": _name(main.opponent_active_pokemon)})
	elif not main._player_can_attack_now() or usable.is_empty():
		await _once("g_end_turn_hint", _cm(G_END_TURN_HINT_KM, G_END_TURN_HINT_PAD))


## A card was benched from the hand (not during setup).
func on_benched(card) -> void:
	_player_ever_benched = true
	if not active():
		return
	_note_hand_used()
	if mode == "newby":
		await _newby_benched(card)


## A Trainer card finished resolving.
func on_trainer_played(card) -> void:
	if not active():
		return
	_note_hand_used()
	if mode == "newby":
		await _newby_trainer(card)
	else:
		await _maybe_evolution_message()


func on_evolved(card) -> void:
	if not active():
		return
	_note_hand_used()
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
		_deferred_once("g_prize", NEWBY_PRIZE if mode == "newby" else G_PRIZE)


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


## The retreat's Energy-to-discard screen has opened. Not awaited.
func on_retreat_energy_shown() -> void:
	if mode == "newby" and _step == "t5_retreat":
		_deferred_once("n_retreat_cost", NEWBY_T5_COST)


## The retreat swap has finished animating.
## A mouse retreat by DRAGGING Ponyta onto Machop picks the new Active itself, so the
## bench screen (and "t5_pick") never comes: "t5_retreat" finishes the beat as well.
func on_retreat_done() -> void:
	if not main.opponents_turn_active:
		_player_ever_retreated = true
	if mode == "newby" and _step in ["t5_pick", "t5_retreat"]:
		_step = "t5_machop"
		await _once("n_retreat_done", _cm(NEWBY_T5_RETREATED_KM, NEWBY_T5_RETREATED_PAD),
			{"[DEFENDER]": _name(main.opponent_active_pokemon)})


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
		return _cm(G_BLOCK_END_BEFORE_HAND_KM, G_BLOCK_END_BEFORE_HAND_PAD)
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


## [evolution card, Pokemon it can evolve RIGHT NOW] (the Active first), or [] -- never on the
## player's first turn, nor onto something played this turn (get_valid_evolution_targets knows).
func _evolution_pair() -> Array:
	if _player_turns <= 1:
		return []
	for c in main.player_hand:
		var subtypes: Array = c.metadata.get("subtypes", [])
		if not ("Stage 1" in subtypes or "Stage 2" in subtypes):
			continue
		var targets: Array = main.get_valid_evolution_targets(c, false)
		if targets.has(main.player_active_pokemon):
			return [c, main.player_active_pokemon]
		if not targets.is_empty():
			return [c, targets[0]]
	return []


func _evolution_message(pair: Array) -> bool:
	return await _once("g_evolution", _cm(G_EVOLUTION_KM, G_EVOLUTION_PAD),
		{"[EVO]": _name(pair[0]), "[BASIC]": _name(pair[1])})


## Mid-turn (a Trainer just drew cards): the evolution line, if one is legal now and nothing is
## being said already.
func _maybe_evolution_message() -> bool:
	if _seen.has("g_evolution") or mode == "newby" or _busy:
		return false
	var pair: Array = _evolution_pair()
	if pair.is_empty():
		return false
	return await _evolution_message(pair)


# ============================================================
# NEWBY — the scripted match (NewbyTutorialMatch.txt)
# ============================================================
# Driven by the player's turn number: the decks are stacked, so every turn holds the
# same cards. _step names the beat inside a turn; _newby_gate() reads it to decide what
# is blocked and with which line.

# EVERY LINE IS ONE OR TWO LINES OF THE MESSAGE BOX AT MOST (user, 2026-11-12, after a play
# test: the old script was overwhelming). Keep new lines that short. [PAD_*] tokens: see _keys().
# Each beat locks the board to the ONE thing the player should do next (_newby_allows), for the
# mouse, the keys and the pad alike -- anything else shows that beat's hint (_step_hint) instead.

const NEWBY_SETUP_KM := ["At the start of a match, choose 1 Basic Pokémon in your hand to be your Active Pokémon. Double click Voltorb, or click it then the button below."]
const NEWBY_SETUP_PAD := ["At the start of a match, choose 1 Basic Pokémon in your hand to be your Active Pokémon. Select Voltorb and press [PAD_A]."]
# The bench-setup screen, straight after the Active is set.
const NEWBY_BENCH_SETUP_KM := ["You could also put up to 5 more Basic Pokémon on your Bench, but you have none left, so click Done."]
const NEWBY_BENCH_SETUP_PAD := ["You could also put up to 5 more Basic Pokémon on your Bench, but you have none left, so choose Done."]
const NEWBY_COIN := ["A coin flip decides who goes first. Choose heads or tails."]
const NEWBY_AUTO_DRAW := ["You draw a card from your deck at the start of every turn."]
# The very first thing on the player's first turn.
const NEWBY_T1_AIM := ["The aim of the game is to knock out your opponent's Pokémon by attacking with your own."]
# "rules" keeps the longer first-turn spiel it always had (it is not the newby script).
const RULES_T1_AIM := [
	"In the Pokemon TCG the general aim is to knock out your opponent's Pokemon...",
	"You will do this by attacking their active Pokemon with your active Pokemon...",
	"Knocking out an opponent's Pokemon wins you a 'Prize Card'...",
	"To win - take every prize card, or knockout all of your opponents Pokemon...",
	"Every Pokemon needs 'Energy' attached to it in order to use one of its attacks...",
	"You will first need to attach an energy card to your active [POKEMON]...",
]
const NEWBY_T1_ENERGY_KM := ["Voltorb's Tackle can be used once Voltorb has any Energy attached. Drag an Energy card from your hand at the bottom of the screen onto Voltorb."]
const NEWBY_T1_ENERGY_PAD := ["Voltorb's Tackle can be used once Voltorb has any Energy attached. Press [PAD_A] to open your hand, select an Energy card, then select Voltorb."]
const NEWBY_STUCK_KM := ["If you get stuck, press [CAPS LOCK] to read back any of these tutorial messages."]
const NEWBY_STUCK_PAD := ["If you get stuck, press [PAD_VIEW] to read back any of these tutorial messages."]
const NEWBY_T1_ATTACHED_KM := [
	"You can only attach 1 Energy card per turn, so remember to attach one every turn.",
	"Voltorb can now use Tackle. Click the Tackle button next to Voltorb to attack.",
]
const NEWBY_T1_ATTACHED_PAD := [
	"You can only attach 1 Energy card per turn, so remember to attach one every turn.",
	"Voltorb can now use Tackle. Press [PAD_RB] to jump to Voltorb's attacks, then [PAD_A] on Tackle.",
]
# Played by _newby_weakness(), which grows the Weakness / type callouts between the lines.
const NEWBY_T1_WEAK_1 := "Voltorb's Tackle should do 10 damage, but Magikarp took 20!"
const NEWBY_T1_WEAK_2 := "Pokémon can have a Weakness to a type, which doubles the damage they take."
const NEWBY_T1_WEAK_3 := "Voltorb is a Lightning type and Magikarp is weak to Lightning, so it took double damage!"
const NEWBY_T1_WEAK_4 := "Only the attacking Pokémon's type matters, not the Energy it used."
const NEWBY_T2_START_KM := [
	"Voltorb is at risk of being knocked out. If your Active Pokémon is knocked out with no Pokémon on your Bench, you instantly lose!",
	"Drag the Trainer card Bill from your hand into the middle of the board to play it.",
]
const NEWBY_T2_START_PAD := [
	"Voltorb is at risk of being knocked out. If your Active Pokémon is knocked out with no Pokémon on your Bench, you instantly lose!",
	"Open your hand, select the Trainer card Bill and press [PAD_A] to play it.",
]
const NEWBY_T2_BILL_KM := ["Bill has added a new Pokémon to your hand. Drag Voltorb from your hand onto your Bench."]
const NEWBY_T2_BILL_PAD := ["Bill has added a new Pokémon to your hand. Select Voltorb in your hand and press [PAD_A] to put it on your Bench."]
const NEWBY_T2_BENCHED_KM := ["You now have a backup for when your Active is knocked out. Drag a Fighting Energy onto your Benched Voltorb so it's ready to attack too."]
const NEWBY_T2_BENCHED_PAD := ["You now have a backup for when your Active is knocked out. Attach a Fighting Energy to your Benched Voltorb so it's ready to attack too."]
const NEWBY_T2_BENCH_ENERGY := ["Your Benched Voltorb is ready if your Active Voltorb is knocked out, so you can safely knock out Magikarp with Tackle again."]
# The newby's Prize lines (the prize talk moved here from the first turn).
const NEWBY_PRIZE := [
	"You knocked out your opponent's Pokémon, so you can take one of your Prize cards and add it to your hand.",
	"Prize cards are set aside from your deck at the start of a match. Take your last Prize card to win!",
]
const NEWBY_T3_VOLTORB_KO := ["Oh no! Voltorb was knocked out and your opponent takes a Prize card. Choose your Benched Voltorb as your new Active Pokémon."]
const NEWBY_T3_START_KM := ["You have no Benched Pokémon again, but Professor Oak might help. Drag Professor Oak into the middle of the board to play it."]
const NEWBY_T3_START_PAD := ["You have no Benched Pokémon again, but Professor Oak might help. Select Professor Oak in your hand and press [PAD_A] to play it."]
const NEWBY_T3_OAK_KM := [
	"Ponyta isn't weak to Diglett's Fighting type. Drag Ponyta onto your Bench, then drag a Fire Energy onto it.",
	"Remember, you can press [CAPS LOCK] to read back any of these messages.",
]
const NEWBY_T3_OAK_PAD := [
	"Ponyta isn't weak to Diglett's Fighting type. Put Ponyta on your Bench, then attach a Fire Energy to it.",
	"Remember, you can press [PAD_VIEW] to read back any of these messages.",
]
const NEWBY_T3_FIRE_KM := [
	"Ponyta can't attack with only one Energy card. For now, attack with Voltorb again instead.",
	"You can hover over any card and hold [SHIFT] to zoom in on its details.",
]
const NEWBY_T3_FIRE_PAD := [
	"Ponyta can't attack with only one Energy card. For now, attack with Voltorb again instead.",
	"You can move onto any card and hold [PAD_LB] to zoom in on its details.",
]
# Played with Diglett's Resistance grown beside it.
const NEWBY_T3_RESIST := [
	"Just like a Weakness, some Pokémon have a Resistance to a type.",
	"Diglett resists Lightning, which takes 30 off all damage it's dealt, so Voltorb did no damage!",
]
const NEWBY_T4_START_KM := ["You've drawn another Pokémon. Drag Machop onto your Bench, then drag another Fire Energy onto Ponyta."]
const NEWBY_T4_START_PAD := ["You've drawn another Pokémon. Put Machop on your Bench, then attach another Fire Energy to Ponyta."]
# The second Fire lands: _newby_colorless() grows Smash Kick, then Flame Tail, beside these.
const NEWBY_T4_COLORLESS := "Smash Kick's two white stars are 'Colorless' Energy. Just like Tackle, any type of Energy card can pay for them."
const NEWBY_T4_FLAME_TAIL := "Flame Tail needs 2 Fire Energy, but does more damage! Ponyta has 2 Fire Energy now, so attack with Flame Tail."
const NEWBY_T4_FLAME_TAIL_BENCH := "Flame Tail needs 2 Fire Energy, but does more damage! Ponyta has 2 now, so put Machop on your Bench, then attack with Flame Tail."
const NEWBY_T5_START_KM := [
	"Ponyta is at risk of being knocked out, but it can retreat to the Bench and let Machop, with full HP, take its place.",
	"You can only retreat once per turn, and only with a Pokémon on your Bench. Drag Ponyta onto Machop, or click Retreat.",
]
const NEWBY_T5_START_PAD := [
	"Ponyta is at risk of being knocked out, but it can retreat to the Bench and let Machop, with full HP, take its place.",
	"You can only retreat once per turn, and only with a Pokémon on your Bench. Press [PAD_RB], move onto Retreat and press [PAD_A].",
]
# The retreat's Energy-to-discard screen.
const NEWBY_T5_COST := ["Ponyta has a Retreat Cost of 1, so 1 Energy card must be discarded to retreat. Some Pokémon have no Retreat Cost at all!"]
const NEWBY_T5_PICK := ["Now Ponyta is retreating, choose Machop as your new Active Pokémon."]
const NEWBY_T5_RETREATED_KM := ["Drag a Fighting Energy onto Machop, then attack with Low Kick to knock out [DEFENDER]."]
const NEWBY_T5_RETREATED_PAD := ["Attach a Fighting Energy to Machop, then attack with Low Kick to knock out [DEFENDER]."]
const NEWBY_T6_START_KM := [
	"Rattata is weak to Machop's Fighting type, so Low Kick should do double damage and knock it out.",
	"But with Defender attached, Rattata takes 20 less damage, which would leave it on 10 HP.",
	"Luckily, the PlusPower you just drew makes Machop do 10 more damage! Drag it into the middle of the board, then knock out Rattata with Low Kick!",
]
const NEWBY_T6_START_PAD := [
	"Rattata is weak to Machop's Fighting type, so Low Kick should do double damage and knock it out.",
	"But with Defender attached, Rattata takes 20 less damage, which would leave it on 10 HP.",
	"Luckily, the PlusPower you just drew makes Machop do 10 more damage! Play it from your hand, then knock out Rattata with Low Kick!",
]
const NEWBY_T6_SHIFT_KM := ["Remember, you can hover over any card and hold [SHIFT] at any time to read its effects in full."]
const NEWBY_T6_SHIFT_PAD := ["Remember, you can move onto any card and hold [PAD_LB] at any time to read its effects in full."]
const NEWBY_T7_START_KM := [
	"Some Pokémon can evolve for better attacks and more HP, but not on the turn they were played or already evolved.",
	"Drag Machoke from your hand onto Machop to evolve it!",
]
const NEWBY_T7_START_PAD := [
	"Some Pokémon can evolve for better attacks and more HP, but not on the turn they were played or already evolved.",
	"Open your hand, select Machoke, then select Machop to evolve it!",
]
const NEWBY_T7_EVOLVED_KM := [
	"It's nearly always a good idea to evolve, but Machoke needs 3 Energy to attack and Machop only had 1.",
	"You can't undo an evolution, so drag another Fighting Energy onto Machoke so it can attack next turn.",
]
const NEWBY_T7_EVOLVED_PAD := [
	"It's nearly always a good idea to evolve, but Machoke needs 3 Energy to attack and Machop only had 1.",
	"You can't undo an evolution, so attach another Fighting Energy to Machoke so it can attack next turn.",
]
const NEWBY_T7_ENERGY_KM := ["If you can't attack or play any more cards, click End Turn or press [Q]."]
const NEWBY_T7_ENERGY_PAD := ["If you can't attack or play any more cards, press [PAD_Y], then [PAD_A] on End Turn."]
# [HP] / [MAX] / [COUNTERS] / [CHOP] are read off Machoke when the turn starts.
const NEWBY_T8_START := [
	"When a Pokémon evolves it recovers from Poison, Sleep, Confusion and Paralysis, but keeps its damage counters.",
	"A damage counter is the same as 10 damage. Machoke has [HP]/[MAX] HP, so it has [COUNTERS] damage counters.",
	"Karate Chop does 10 less damage for each damage counter, so it would only do [CHOP] to Dratini. Try playing your Bill card.",
]
const NEWBY_T8_BILL_KM := [
	"Potion removes 2 damage counters from one of your Pokémon, so it restores 20 HP to Machoke.",
	"Drag both Potion cards onto Machoke.",
]
const NEWBY_T8_BILL_PAD := [
	"Potion removes 2 damage counters from one of your Pokémon, so it restores 20 HP to Machoke.",
	"Open your hand and play both Potion cards on Machoke.",
]
const NEWBY_T8_HEALED_KM := ["Machoke is back to full HP! Click Karate Chop to knock out Dratini and take your last Prize card!"]
const NEWBY_T8_HEALED_PAD := ["Machoke is back to full HP! Press [PAD_RB], then [PAD_A] on Karate Chop to take your last Prize card!"]
const NEWBY_T8_HEALED_ENERGY_KM := ["Machoke is back to full HP! Drag your last Energy card onto Machoke, then use Karate Chop to take your last Prize card!"]
const NEWBY_T8_HEALED_ENERGY_PAD := ["Machoke is back to full HP! Attach your last Energy card to Machoke, then use Karate Chop to take your last Prize card!"]
const NEWBY_T8_ENERGY_KM := ["Click Karate Chop to knock out Dratini and take your last Prize card!"]
const NEWBY_T8_ENERGY_PAD := ["Press [PAD_RB], then [PAD_A] on Karate Chop to take your last Prize card!"]


# ------------------------------------------------------------
# CALLOUTS -- a piece of a card grown and ringed while a line talks about it
# ------------------------------------------------------------
# Regions are in the card art's pixels on a 600 x 825 card (every Base Set card lays its
# Weakness / Resistance / type symbol out in the same place). Attack boxes differ per card.
const Callout := preload("res://Scripts/Main_Match_Gameplay_Scripts/Tutorial_Callout.gd")
const REGION_WEAKNESS   := Rect2(35, 686, 130, 58)
const REGION_RESISTANCE := Rect2(245, 686, 135, 58)
const REGION_TYPE       := Rect2(498, 28, 64, 62)
const ATTACK_REGIONS := {
	"base1-35:Flail":      Rect2(28, 590, 548, 90),   # Magikarp
	"base1-60:Smash Kick": Rect2(28, 492, 548, 86),   # Ponyta
	"base1-60:Flame Tail": Rect2(28, 590, 548, 88),   # Ponyta
}
# TWEAKABLE: how many times bigger each callout grows.
const CALLOUT_GROW := 3.0
const CALLOUT_GROW_ATTACK := 2.0
var _callouts: Array = []


func _callout(card, region: Rect2, grow: float) -> void:
	if card == null:
		return
	var node = main.find_card_ui_for_object(card, true)
	if node == null:
		push_warning("TUTORIAL: no board node for %s's callout" % _name(card))
		return
	var c = Callout.new()
	main.add_child(c)
	c.start(node, String(card.metadata.get("id", "")), region, grow, UIKit.screen_h() - main.BOARD_BOT_H)
	_callouts.append(c)


func _attack_callout(card, attack_name: String) -> void:
	if card == null:
		return
	var key := String(card.metadata.get("id", "")) + ":" + attack_name
	if ATTACK_REGIONS.has(key):
		_callout(card, ATTACK_REGIONS[key], CALLOUT_GROW_ATTACK)


func _swap_attack_callout(card, attack_name: String) -> void:
	_clear_callouts()
	_attack_callout(card, attack_name)


func _weakness_callouts(a, b) -> void:
	_callout(a, REGION_WEAKNESS, CALLOUT_GROW)
	_callout(b, REGION_WEAKNESS, CALLOUT_GROW)


func _clear_callouts() -> void:
	for c in _callouts:
		if is_instance_valid(c):
			c.dismiss()
	_callouts.clear()


## Lines with actions between them: a String is said (and clicked through), a Callable is
## run on the spot. Once per match under `key`.
func _once_script(key: String, items: Array, fills: Dictionary = {}) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	_busy = true
	for it in items:
		if it is Callable:
			(it as Callable).call()
			continue
		var text := String(it)
		for k in fills:
			text = text.replace(k, str(fills[k]))
		await main.show_message(_keys(text), true, "tutorial")
	_busy = false


## The CPU has chosen its attack and is about to announce it (CPU_AI). Magikarp's Flail is
## grown while "used Flail!" is up.
func on_cpu_attack_declared(attacker, attack_name: String) -> void:
	if mode != "newby" or _seen.has("n_flail"):
		return
	if _name(attacker) == "Magikarp" and attack_name == "Flail":
		_seen["n_flail"] = true
		_attack_callout(attacker, attack_name)


## The CPU's attack animation is about to play: any callout goes.
func on_cpu_attack_start() -> void:
	_clear_callouts()


func _newby_turn_start() -> void:
	match _player_turns:
		1:
			_step = "t1_attach"
			await _once("n_t1_aim", NEWBY_T1_AIM)
			await _once("n_t1_energy", _cm(NEWBY_T1_ENERGY_KM, NEWBY_T1_ENERGY_PAD))
			await _once("n_caps", _cm(NEWBY_STUCK_KM, NEWBY_STUCK_PAD))
		2:
			_step = "t2_bill"
			await _once("n_t2", _cm(NEWBY_T2_START_KM, NEWBY_T2_START_PAD))
		3:
			_step = "t3_oak"
			await _once("n_t3", _cm(NEWBY_T3_START_KM, NEWBY_T3_START_PAD))
		4:
			_step = "t4"
			await _once("n_t4", _cm(NEWBY_T4_START_KM, NEWBY_T4_START_PAD))
		5:
			_step = "t5_retreat"
			await _once("n_t5", _cm(NEWBY_T5_START_KM, NEWBY_T5_START_PAD))
		6:
			_step = "t6_pluspower"
			await _once("n_t6", _cm(NEWBY_T6_START_KM, NEWBY_T6_START_PAD))
		7:
			_step = "t7_evolve"
			await _once("n_t7", _cm(NEWBY_T7_START_KM, NEWBY_T7_START_PAD))
		8:
			_step = "t8_bill"
			var m = main.player_active_pokemon
			var hp: int = m.current_hp if m != null else 40
			var mx: int = m.get_max_hp() if m != null else 80
			var counters: int = maxi(0, (mx - hp) / 10)
			await _once("n_t8", NEWBY_T8_START, {"[HP]": hp, "[MAX]": mx,
				"[COUNTERS]": counters, "[CHOP]": maxi(0, 50 - 10 * counters)})
		_:
			_step = "free"


## The hand view opened a SECOND time in the same beat (opened, backed out, came back):
## say what to do again.
var _last_hand_step: String = ""


func _newby_hand_opened() -> void:
	if _step == _last_hand_step and not _step in ["", "free"]:
		_deferred_say([_step_hint()])
	_last_hand_step = _step


func _newby_energy_attached(_energy, target) -> void:
	match _step:
		"t1_attach":
			_step = "t1_attack"
			await _once("n_t1_attached", _cm(NEWBY_T1_ATTACHED_KM, NEWBY_T1_ATTACHED_PAD))
		"t2_bench_energy":
			if target != main.player_active_pokemon:
				_step = "t2_attack"
				await _once("n_t2_energy", NEWBY_T2_BENCH_ENERGY)
		"t3_fire":
			if _name(target) == "Ponyta":
				_step = "t3_attack"
				await _once("n_t3_fire", _cm(NEWBY_T3_FIRE_KM, NEWBY_T3_FIRE_PAD))
		"t4":
			if _name(target) == "Ponyta":
				await _newby_colorless(target)
		"t5_machop":
			if target == main.player_active_pokemon:
				_step = "t5_attack"
		"t6_energy":
			if target == main.player_active_pokemon:
				_step = "t6_attack"
		"t7_energy":
			if target == main.player_active_pokemon:
				_step = "t7_done"
				await _once("n_t7_energy", _cm(NEWBY_T7_ENERGY_KM, NEWBY_T7_ENERGY_PAD))
		"t8_energy":
			if target == main.player_active_pokemon:
				_step = "t8_attack"
				await _once("n_t8_energy", _cm(NEWBY_T8_ENERGY_KM, NEWBY_T8_ENERGY_PAD))


## Ponyta's second Fire: Smash Kick grown for the Colorless line, then Flame Tail for the next.
func _newby_colorless(ponyta) -> void:
	var tail: String = NEWBY_T4_FLAME_TAIL if _machop_benched() else NEWBY_T4_FLAME_TAIL_BENCH
	await _once_script("n_t4_colorless", [
		func(): _attack_callout(ponyta, "Smash Kick"),
		NEWBY_T4_COLORLESS,
		func(): _swap_attack_callout(ponyta, "Flame Tail"),
		tail,
		func(): _clear_callouts(),
	])


func _machop_benched() -> bool:
	return main.player_bench.any(func(b): return _name(b) == "Machop")


func _newby_benched(card) -> void:
	match _step:
		"t2_bench":
			_step = "t2_bench_energy"
			await _once("n_t2_benched", _cm(NEWBY_T2_BENCHED_KM, NEWBY_T2_BENCHED_PAD))
		"t3_ponyta":
			if _name(card) == "Ponyta":
				_step = "t3_fire"


func _newby_trainer(card) -> void:
	var n := _name(card)
	match _step:
		"t2_bill":
			if n == "Bill":
				_step = "t2_bench"
				await _once("n_t2_bill", _cm(NEWBY_T2_BILL_KM, NEWBY_T2_BILL_PAD))
		"t3_oak":
			if n == "Professor Oak":
				_step = "t3_ponyta"
				await _once("n_t3_oak", _cm(NEWBY_T3_OAK_KM, NEWBY_T3_OAK_PAD))
		"t6_pluspower":
			if n == "PlusPower":
				# The Energy may already be on (attached before the PlusPower).
				_step = "t6_attack" if main.player_energy_played_this_turn else "t6_energy"
				await _once("n_shift", _cm(NEWBY_T6_SHIFT_KM, NEWBY_T6_SHIFT_PAD))
		"t8_bill":
			if n == "Bill":
				_step = "t8_potions"
				_potions_played = 0
				await _once("n_t8_bill", _cm(NEWBY_T8_BILL_KM, NEWBY_T8_BILL_PAD))
		"t8_potions":
			if n == "Potion":
				_potions_played += 1
				# Done once Machoke is healed -- or once the Potions are gone, so the player can
				# never be left behind a "heal Machoke" lock with nothing to heal it with.
				var machoke = main.player_active_pokemon
				var healed: bool = machoke != null and machoke.current_hp >= machoke.get_max_hp()
				var potions_left: bool = main.player_hand.any(func(c): return _name(c) == "Potion")
				if healed or not potions_left:
					if _machoke_can_attack():
						_step = "t8_attack"
						await _once("n_t8_healed", _cm(NEWBY_T8_HEALED_KM, NEWBY_T8_HEALED_PAD))
					else:
						_step = "t8_energy"
						await _once("n_t8_healed", _cm(NEWBY_T8_HEALED_ENERGY_KM, NEWBY_T8_HEALED_ENERGY_PAD))


func _machoke_can_attack() -> bool:
	var m = main.player_active_pokemon
	if m == null:
		return false
	for a in main.get_attacks_for_card(m):
		if String(a.get("name", "")) == "Karate Chop":
			return main.check_attack_requirements(a, m)
	return false


func _newby_evolved(card) -> void:
	if _step == "t7_evolve" and _name(card) == "Machoke":
		_step = "t7_energy"
		await _once("n_t7_evolved", _cm(NEWBY_T7_EVOLVED_KM, NEWBY_T7_EVOLVED_PAD))


func _newby_attack(attacker, defender, weak: bool, resist: bool, _fills: Dictionary, attacker_is_opponent: bool) -> void:
	if attacker_is_opponent:
		return
	if _step == "t1_attack" and weak:
		_step = "t1_done"
		await _newby_weakness(attacker, defender)
	elif _step == "t2_attack":
		_step = "t2_done"
	elif _step == "t3_attack" and resist:
		_step = "t3_done"
		await _once_script("n_t3_resist", [
			func(): _callout(defender, REGION_RESISTANCE, CALLOUT_GROW),
			NEWBY_T3_RESIST[0],
			NEWBY_T3_RESIST[1],
			func(): _clear_callouts(),
		])


## Voltorb's first Tackle: both Actives' Weaknesses grow for the Weakness line, Voltorb's
## type joins them for the type line, and everything shrinks back after the last line.
func _newby_weakness(attacker, defender) -> void:
	await _once_script("n_t1_weak", [
		NEWBY_T1_WEAK_1,
		func(): _weakness_callouts(attacker, defender),
		NEWBY_T1_WEAK_2,
		func(): _callout(attacker, REGION_TYPE, CALLOUT_GROW),
		NEWBY_T1_WEAK_3,
		NEWBY_T1_WEAK_4,
		func(): _clear_callouts(),
	])


const NEWBY_BLOCK_POTION_PONYTA := "Save your Potions for Machoke."


## What the newby player may not do right now, and why. "" = allowed.
## WHITELIST: each beat names the only things allowed; anything else is refused with the
## beat's hint. Every play path asks this -- drag, double click, the hand view, the pad --
## and the Energy target screen only lists the allowed Pokemon (filter_attach_targets).
func _newby_gate(kind: String, data: Dictionary) -> String:
	if kind == "heal":
		return NEWBY_BLOCK_POTION_PONYTA if _name(data.get("target", null)) == "Ponyta" else ""
	if _newby_allows(kind, data):
		return ""
	return _step_hint()


func _newby_allows(kind: String, data: Dictionary) -> bool:
	var card = data.get("card", null)
	var cname := _name(card)
	var action := String(data.get("action", ""))
	var attach_play: bool = kind == "play" and action == "ATTACH_ENERGY"
	var energy = data.get("energy", card if attach_play else null)
	var etype: String = main.get_energy_type_from_card(energy) if energy != null else ""
	var target = data.get("target", null)
	var active = main.player_active_pokemon
	var atk: String = String(data.get("attack", {}).get("name", "")) if data.get("attack") is Dictionary else ""
	var energy_done: bool = main.player_energy_played_this_turn
	var is_bench := func(n: String) -> bool: return kind == "play" and action == "SET_POKEMON" and cname == n
	var is_trainer := func(n: String) -> bool: return kind == "play" and action == "PLAY_TRAINER" and cname == n
	# An Energy of `type` ("" = any) onto a Pokemon `want` accepts. Picking the Energy itself
	# (the target is not known yet) only checks the type; the target screen is filtered.
	var attach_ok := func(type: String, want: Callable) -> bool:
		if attach_play:
			return type == "" or etype == type
		return kind == "attach" and (type == "" or etype == type) and target != null and want.call(target)
	var is_active := func(t) -> bool: return t == active
	match _step:
		"t1_attach":
			return attach_ok.call("", is_active)
		"t1_attack", "t2_attack", "t3_attack":
			return kind == "attack" and atk == "Tackle"
		"t2_bill":
			return is_trainer.call("Bill")
		"t2_bench":
			return is_bench.call("Voltorb")
		"t2_bench_energy":
			return attach_ok.call("Fighting", func(t): return t != active and _name(t) == "Voltorb")
		"t3_oak":
			return is_trainer.call("Professor Oak")
		"t3_ponyta":
			return is_bench.call("Ponyta")
		"t3_fire":
			return attach_ok.call("Fire", func(t): return _name(t) == "Ponyta")
		"t4":
			var benched := _machop_benched()
			if is_bench.call("Machop") and not benched:
				return true
			if not energy_done and attach_ok.call("Fire", func(t): return _name(t) == "Ponyta"):
				return true
			return kind == "attack" and atk == "Flame Tail" and benched
		"t5_retreat":
			return kind == "retreat"
		"t5_machop":
			return attach_ok.call("Fighting", is_active)
		"t5_attack", "t6_attack":
			return kind == "attack" and atk == "Low Kick"
		"t6_pluspower":
			if is_trainer.call("PlusPower"):
				return true
			return not energy_done and attach_ok.call("Fighting", is_active)
		"t6_energy":
			return attach_ok.call("Fighting", is_active)
		"t7_evolve":
			return kind == "play" and action == "EVOLVE" and cname == "Machoke"
		"t7_energy":
			return attach_ok.call("Fighting", is_active)
		"t7_done":
			return kind == "end_turn"
		"t8_bill", "t8_potions", "t8_energy":
			# Machoke's last Energy may go on at any point this turn, of any type.
			if not energy_done and attach_ok.call("", is_active):
				return true
			if _step == "t8_bill":
				return is_trainer.call("Bill")
			if _step == "t8_potions":
				return is_trainer.call("Potion")
			return false
		"t8_attack":
			return kind == "attack" and atk == "Karate Chop"
		"free":
			return true
	# A beat with nothing scripted (between turns, a screen of its own): only End Turn, so the
	# player can never be stuck.
	return kind == "end_turn"


## The line for whatever the player should be doing right now (a refused action shows it).
func _step_hint() -> String:
	var defender := _name(main.opponent_active_pokemon)
	match _step:
		"t1_attach":
			return _cm("Drag a Fighting Energy from your hand onto Voltorb.",
				"Open your hand, select a Fighting Energy, then select Voltorb.")
		"t1_attack", "t3_attack":
			return _cm("Click the Tackle button next to Voltorb to attack.",
				"Press [PAD_RB], then [PAD_A] on Tackle to attack.")
		"t2_bill":
			return _cm("Drag Bill from your hand into the middle of the board to play it.",
				"Open your hand, select Bill and press [PAD_A] to play it.")
		"t2_bench":
			return _cm("Drag Voltorb from your hand onto your Bench.",
				"Open your hand, select Voltorb and press [PAD_A] to put it on your Bench.")
		"t2_bench_energy":
			return _cm("Drag a Fighting Energy onto your Benched Voltorb.",
				"Attach a Fighting Energy to your Benched Voltorb.")
		"t2_attack":
			return _cm("Click Tackle to knock out Magikarp.",
				"Press [PAD_RB], then [PAD_A] on Tackle to knock out Magikarp.")
		"t3_oak":
			return _cm("Drag Professor Oak into the middle of the board to play it.",
				"Open your hand, select Professor Oak and press [PAD_A] to play it.")
		"t3_ponyta":
			return _cm("Drag Ponyta from your hand onto your Bench.",
				"Open your hand, select Ponyta and press [PAD_A] to put it on your Bench.")
		"t3_fire":
			return _cm("Drag a Fire Energy onto Ponyta.", "Attach a Fire Energy to Ponyta.")
		"t4":
			var benched := _machop_benched()
			var energy_done: bool = main.player_energy_played_this_turn
			if not benched and not energy_done:
				return _cm("Drag Machop onto your Bench, then drag a Fire Energy onto Ponyta.",
					"Put Machop on your Bench, then attach a Fire Energy to Ponyta.")
			if not benched:
				return _cm("Drag Machop from your hand onto your Bench.",
					"Open your hand, select Machop and press [PAD_A] to put it on your Bench.")
			if not energy_done:
				return _cm("Drag a Fire Energy onto Ponyta.", "Attach a Fire Energy to Ponyta.")
			return _cm("Click Flame Tail to attack.", "Press [PAD_RB], then [PAD_A] on Flame Tail to attack.")
		"t5_retreat":
			return _cm("Drag Ponyta onto Machop, or click Retreat, to retreat Ponyta.",
				"Press [PAD_RB], move onto Retreat and press [PAD_A] to retreat Ponyta.")
		"t5_machop":
			return _cm("Drag a Fighting Energy onto Machop.", "Attach a Fighting Energy to Machop.")
		"t5_attack":
			return _cm("Click Low Kick to knock out %s." % defender,
				"Press [PAD_RB], then [PAD_A] on Low Kick to knock out %s." % defender)
		"t6_pluspower":
			return _cm("Drag PlusPower into the middle of the board to play it.",
				"Open your hand, select PlusPower and press [PAD_A] to play it.")
		"t6_energy":
			return _cm("Remember to attach an Energy every turn. Drag a Fighting Energy onto Machop.",
				"Remember to attach an Energy every turn. Attach a Fighting Energy to Machop.")
		"t6_attack":
			return _cm("Click Low Kick to knock out Rattata.",
				"Press [PAD_RB], then [PAD_A] on Low Kick to knock out Rattata.")
		"t7_evolve":
			return _cm("Drag Machoke from your hand onto Machop to evolve it.",
				"Open your hand, select Machoke, then select Machop to evolve it.")
		"t7_energy":
			return _cm("Drag a Fighting Energy onto Machoke so it can attack next turn.",
				"Attach a Fighting Energy to Machoke so it can attack next turn.")
		"t7_done":
			return _cm(NEWBY_T7_ENERGY_KM[0], NEWBY_T7_ENERGY_PAD[0])
		"t8_bill":
			return _cm("Karate Chop would only do 10 damage. Drag Bill into the middle of the board to play it.",
				"Karate Chop would only do 10 damage. Open your hand and play Bill.")
		"t8_potions":
			return _cm("Drag both Potion cards onto Machoke.", "Open your hand and play both Potion cards on Machoke.")
		"t8_energy":
			return _cm("Drag your last Energy card onto Machoke.", "Attach your last Energy card to Machoke.")
		"t8_attack":
			return _cm(NEWBY_T8_ENERGY_KM[0], NEWBY_T8_ENERGY_PAD[0])
	return _cm("Not right now. Press [CAPS LOCK] to read the last tutorial message again.",
		"Not right now. Press [PAD_VIEW] to read the last tutorial message again.")


## The Energy target screen: only the Pokemon the tutorial allows this Energy onto.
func filter_attach_targets(energy, targets: Array) -> Array:
	if mode != "newby" or main.opponents_turn_active:
		return targets
	return targets.filter(func(p): return gate("attach", {"energy": energy, "target": p}) == "")
