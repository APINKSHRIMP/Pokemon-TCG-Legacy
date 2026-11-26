extends Node
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	SoundManagerScript.cry_length("010_Caterpie")
	await get_tree().create_timer(0.5).timeout
	var started := SoundManagerScript.play_cry_part("010_Caterpie", 0.75, 0.5)
	var p: AudioStreamPlayer = SoundManagerScript._warn_cry_player
	print("started ", started, " len ", p.stream.get_length(), " driver ", AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?")
	var t0 := Time.get_ticks_msec()
	var last := true
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
		var tw: Tween = SoundManagerScript._warn_cry_tween
		var st := "tween %s playing %s vol %.1f" % [tw.is_running() if tw != null else false, p.playing, p.volume_db]
		if tw != null and tw.is_running() != last:
			print("%.3f %s" % [(Time.get_ticks_msec() - t0) / 1000.0, st])
			last = tw.is_running()
	print("end vol ", p.volume_db)
	get_tree().quit()
