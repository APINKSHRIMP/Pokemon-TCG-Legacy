extends Node

var fails := 0

func ok(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func clear_roster() -> void:
	for id in PokemonHome.roster():
		PokemonHome.release(str(id))
	for id in GameState.get_home_pokemon():
		PokemonHome.release(str(id))
	GameState.clear_follower()


func _ready() -> void:
	await get_tree().process_frame
	GameState.load_slot(1)
	clear_roster()
	GameState.set_bed_slots(["", "", ""])
	# ---- rules ----
	PokemonHome.recruit("010_Caterpie")
	var a := GameState.get_follower()
	ok(PokemonHome.cant_go_home_reason() == "lost", "fresh follower can't go home: lost")
	ok(PokemonHome.new_partner_warning() != "", "new partner warns (lost): " + PokemonHome.new_partner_warning())
	PokemonHome.note_in_house(a)
	ok(PokemonHome.cant_go_home_reason() == "no_bed", "visited, no beds: no_bed")
	GameState.set_bed_slots(["Hay Bale", "Hay Bale", "Hay Bale"])
	ok(PokemonHome.cant_go_home_reason() == "", "visited + bed: can go home")
	PokemonHome.recruit("019_Rattata")
	var b := GameState.get_follower()
	ok(a in GameState.get_home_pokemon() and GameState.get_follower() == b, "recruit B: A went home")
	PokemonHome.recruit("016_Pidgey")
	var c := GameState.get_follower()
	ok(b not in GameState.get_home_pokemon() and GameState.get_pokemon_flags(b).is_empty(), "recruit C: lost B released")
	ok(GameState.get_follower() == c, "C following")
	PokemonHome.note_in_house(c)
	PokemonHome.recruit("007_Squirtle")   # C home (bed 2)
	var d := GameState.get_follower()
	PokemonHome.note_in_house(d)
	PokemonHome.recruit("008_Wartortle")  # D home (bed 3)
	var e := GameState.get_follower()
	ok(GameState.get_home_pokemon().size() == 3, "3 at home: " + str(GameState.get_home_pokemon()))
	PokemonHome.note_in_house(e)
	ok(PokemonHome.cant_go_home_reason() == "no_bed", "4th follower: beds full -> no_bed")
	PokemonAffection.set_points(e, 650)
	ok(PokemonHome.sleeps_on_player_bed(e), "level 6 follower on your bed")
	ok(PokemonHome.cant_go_home_reason() == "", "level 6 follower can go home (your bed)")
	ok(PokemonHome.homeless_at_bedtime().is_empty(), "nobody homeless with lvl6 follower")
	PokemonHome.recruit("025_Pikachu")
	var f := GameState.get_follower()
	ok(e in GameState.get_home_pokemon() and GameState.get_follower() == f, "E (lvl6) went home -> 5 owned")
	ok(PokemonHome.player_bed_holder() == e, "home lvl6 holds your bed")
	ok(PokemonHome.homeless_at_bedtime() == [f], "only new follower homeless: " + str(PokemonHome.homeless_at_bedtime()))
	PokemonAffection.set_points(e, 550)
	ok(PokemonHome.player_bed_holder() == "", "E at level 5 loses your bed")
	ok(PokemonHome.homeless_at_bedtime().size() == 2, "E dropped -> 2 homeless: " + str(PokemonHome.homeless_at_bedtime()))
	# ---- cry part ----
	var started := SoundManagerScript.play_cry_part("010_Caterpie", 0.75, 0.5)
	var full := SoundManagerScript.cry_length("010_Caterpie")
	var t0 := Time.get_ticks_msec()
	while SoundManagerScript._warn_cry_tween.is_running() and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	var ran := (Time.get_ticks_msec() - t0) / 1000.0
	ok(started and absf(ran - full * 0.5 / 0.75) < 0.15, "cry part ran %.2fs (full %.2fs, expected %.2fs)" % [ran, full, full * 0.5 / 0.75])
	# ---- house ----
	clear_roster()
	PokemonHome.recruit("010_Caterpie")
	PokemonHome.note_in_house(GameState.get_follower())
	PokemonHome.recruit("019_Rattata")
	PokemonHome.note_in_house(GameState.get_follower())
	PokemonHome.recruit("016_Pidgey")
	PokemonHome.note_in_house(GameState.get_follower())
	PokemonHome.leave_at_home()
	pass
	print("home: ", GameState.get_home_pokemon(), " time ", GameState.get_time())
	for run in 2:
		MapManager._map_scene_path = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
		var map: Node = load("res://Scenes/Map_Scenes/Player_House_Downstairs.tscn").instantiate()
		add_child(map)
		for _i in 10:
			await get_tree().physics_frame
		var ws := get_tree().get_nodes_in_group(PokemonHomeWanderer.GROUP)
		var pos := []
		for w in ws:
			pos.append([w.pokemon_id, w.global_position.round()])
		print("entry %d downstairs: %s" % [run, pos])
		print("layout: ", PokemonHome._layout)
		map.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	# ---- meeting ----
	var map2: Node = load("res://Scenes/Map_Scenes/Player_House_Downstairs.tscn").instantiate()
	MapManager._map_scene_path = "res://Scenes/Map_Scenes/Celeste_Harbour.tscn"
	add_child(map2)
	for _i in 5:
		await get_tree().physics_frame
	for w in get_tree().get_nodes_in_group(PokemonHomeWanderer.GROUP):
		w.despawn()
	await get_tree().process_frame
	var w1 := PokemonHomeWanderer.spawn(map2, "010_Caterpie", Vector2(150, 150))
	var w2 := PokemonHomeWanderer.spawn(map2, "019_Rattata", Vector2(160, 150))
	await get_tree().physics_frame
	w1._meet_cooldown = 0.0
	w2._meet_cooldown = 0.0
	w1._walking = true
	w1._target = Vector2(170, 150)
	w1._timer = 3.0
	var saw_meet := false
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 20000:
		await get_tree().physics_frame
		if w1.meeting:
			saw_meet = true
		if saw_meet and not w1.meeting:
			break
	var dur := (Time.get_ticks_msec() - t1) / 1000.0
	ok(saw_meet and not w1.meeting, "meeting happened and ended after %.1fs" % dur)
	ok(w1._avoid_moves == AVOID() and w1._meet_cooldown >= 59.0, "avoid moves %d, cooldown %.0f" % [w1._avoid_moves, w1._meet_cooldown])
	var d0 := w1.global_position.distance_to(w2.global_position)
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 12000:
		await get_tree().physics_frame
	var d1 := w1.global_position.distance_to(w2.global_position)
	ok(d1 > d0, "walked apart: %.0f -> %.0f px" % [d0, d1])
	clear_roster()
	print("DONE fails=", fails)
	get_tree().quit()


func AVOID() -> int:
	return PokemonHomeWanderer.AVOID_MOVES - (0 if true else 0)
