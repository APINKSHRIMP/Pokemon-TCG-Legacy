extends "res://Scripts/Autotest/Autotest_Bot.gd"
## AUDIT STEP 2: the autotest bot with its DRIVER replaced. It still answers every prompt like a random player
## (messages, option rows, card picks), but never plays a turn itself: it only tells Card_Probe "the player's board is idle".

var ready_for_job := false
var job_log: Array = []

func _run_driver_step() -> void:
	ready_for_job = true

func _log(s: String) -> void:
	job_log.append(s)
	super(s)
