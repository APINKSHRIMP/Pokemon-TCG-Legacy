extends "res://Scripts/Autotest/Autotest_Bot.gd"

# ============================================================
# AUTOTEST TUTORIAL BOT — plays the newby tutorial's player side BY THE SCRIPT
# ============================================================
# Run with Autotest_Runner --tutorial=newby. The decks are stacked by the real
# Tutorial_Director, the CPU plays with its normal AI, and this bot makes exactly the
# moves NewbyTutorialMatch.txt asks of the player, turn by turn. The point is to see
# whether the CPU, left to itself, does what the script expects of it -- the runner
# writes the board at the start of every player turn to tutorial_newby.txt.
#
# Each turn is a list of steps: ["attach", energy name, target name], ["bench", name],
# ["trainer", name], ["evolve", name], ["retreat"], ["attack", attack name], ["end"].
# A step that cannot be done is logged as a DEVIATION and skipped.

const SCRIPT := {
	1: [["attach", "Fighting Energy", "Voltorb"], ["attack", "Tackle"]],
	2: [["trainer", "Bill"], ["bench", "Voltorb"], ["attach", "Fighting Energy", "bench:Voltorb"], ["attack", "Tackle"]],
	3: [["trainer", "Professor Oak"], ["bench", "Ponyta"], ["attach", "Fire Energy", "Ponyta"], ["attack", "Tackle"]],
	4: [["bench", "Machop"], ["attach", "Fire Energy", "Ponyta"], ["attack", "Flame Tail"]],
	5: [["retreat"], ["attach", "Fighting Energy", "Machop"], ["attack", "Low Kick"]],
	6: [["trainer", "PlusPower"], ["attach", "Fighting Energy", "Machop"], ["attack", "Low Kick"]],
	7: [["evolve", "Machoke"], ["attach", "Fighting Energy", "Machoke"], ["end"]],
	8: [["attach", "Fighting Energy", "Machoke"], ["trainer", "Bill"], ["trainer", "Potion"], ["trainer", "Potion"], ["attack", "Karate Chop"]],
}

var _player_turn := 0
var _step_index := 0
var _last_turn_number := -1
# The target the current attach / retreat step wants, read by the selection answerer.
var _want_target := ""


func _run_driver_step() -> void:
	var m = main
	if m.turn_number != _last_turn_number:
		_last_turn_number = m.turn_number
		_player_turn += 1
		_step_index = 0
		runner.tutorial_turn_report(_player_turn, m)
	var steps: Array = SCRIPT.get(_player_turn, [["end"]])
	if _step_index >= steps.size():
		_driver_busy = true
		_log("SCRIPT: turn %d done, end turn" % _player_turn)
		await _end_turn()
		_driver_busy = false
		return
	var step: Array = steps[_step_index]
	_step_index += 1
	_driver_busy = true
	await _do_step(step)
	_driver_busy = false


func _do_step(step: Array) -> void:
	var m = main
	match String(step[0]):
		"attach":
			var card = _hand_card(step[1])
			if card == null:
				_deviation("no %s in hand to attach" % step[1])
				return
			_want_target = String(step[2])
			_log("SCRIPT: attach %s -> %s" % [step[1], step[2]])
			await _play_hand_card(card)
		"bench", "trainer", "evolve":
			var card = _hand_card(step[1])
			if card == null:
				_deviation("no %s in hand to %s" % [step[1], step[0]])
				return
			_want_target = "Machop" if step[0] == "evolve" else ("Machoke" if step[1] == "Potion" else "")
			_log("SCRIPT: %s %s" % [step[0], step[1]])
			await _play_hand_card(card)
		"retreat":
			_want_target = "bench:Machop"
			_log("SCRIPT: retreat")
			_retreat()
		"attack":
			var attacks: Array = m.get_attacks_for_card(m.player_active_pokemon)
			for i in attacks.size():
				if String(attacks[i].get("name", "")) == String(step[1]):
					if not m.check_attack_requirements(attacks[i], m.player_active_pokemon):
						_deviation("%s can't pay for %s" % [m.player_active_pokemon.metadata.get("name", ""), step[1]])
						await _end_turn()
						return
					_log("SCRIPT: attack " + String(step[1]))
					await _attack(i)
					return
			_deviation("active has no attack " + String(step[1]))
			await _end_turn()
		"end":
			_log("SCRIPT: end turn")
			await _end_turn()


## The selection answerer: the scripted target wherever there is one.
func _answer_selection() -> bool:
	var m = main
	if _want_target != "" and (m.card_attach_mode_active or m.evolution_mode_active \
			or m.retreat_bench_selection_active or m.trainer_pokemon_selection_active):
		var bench_only := _want_target.begins_with("bench:")
		var want_name := _want_target.trim_prefix("bench:")
		for c in m.shown_selection_pool:
			if c is Object and "metadata" in c and String(c.metadata.get("name", "")) == want_name:
				if bench_only and c == m.player_active_pokemon:
					continue
				_click(c)
				if _press_action():
					_want_target = ""
					return true
	return super._answer_selection()


func _hand_card(card_name: String):
	for c in main.player_hand:
		if String(c.metadata.get("name", "")) == card_name:
			return c
	return null


func _deviation(text: String) -> void:
	_log("DEVIATION: " + text)
	runner.tutorial_note("  PLAYER SCRIPT DEVIATION (turn %d): %s" % [_player_turn, text])
