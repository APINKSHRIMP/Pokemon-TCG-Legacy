extends Node

# ============================================================
# GIF DIRECTOR — scripted screen recordings for the README gifs
# ============================================================
# Drives the REAL game through one scripted shot and writes every rendered frame
# to a folder as PNG; Scripts/Utilities/gif_build.py turns that folder into a gif.
#
#   "C:\Godot\Godot_v4.6.1-stable_win64_console.exe" --path "C:\Pokemon TCG Legacy" \
#       --fixed-fps 20 --audio-driver Dummy --script Scripts/Utilities/Gif_Director_Boot.gd \
#       -- --shot=coins --out=C:/somewhere/frames --window=1920x1080
#
# NOT --headless (nothing renders without a window). --fixed-fps makes every frame
# advance game time by exactly 1/20 s however long the PNG save takes, so the
# recording plays back at true speed whatever the machine does.
#
# The shots play on save slot GIF_SLOT, which each shot rebuilds as it needs
# (cheats for a full collection, story flags so nothing first-time pops up).
# THAT SLOT IS OVERWRITTEN — back it up first if it holds a game you care about.
# ============================================================

const GIF_SLOT := 3
const FPS := 20.0
## Frames are shrunk to this before saving: the gif is 800 wide, and saving a
## 1920x1080 PNG every frame is what makes a recording slow.
const SAVE_SIZE := Vector2i(960, 540)

var _out := ""
var _shot := ""
var _recording := false
var _frame := 0
var _args := {}
var _jpg := false
var _taxi_presses := 0   # long shots (whole matches): JPEG frames, a tenth the disk and save time


func _ready() -> void:
	process_priority = 1000   # after everything else has moved this frame
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--") and s.contains("="):
			_args[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	_shot = _args.get("shot", "")
	_out = _args.get("out", "")
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _recording:
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.resize(SAVE_SIZE.x, SAVE_SIZE.y, Image.INTERPOLATE_LANCZOS)
			if _jpg:
				img.save_jpg("%s/f_%05d.jpg" % [_out, _frame], 0.93)
			else:
				img.save_png("%s/f_%05d.png" % [_out, _frame])
			_frame += 1


# ============================================================
# HELPERS
# ============================================================

func rec(on: bool) -> void:
	_recording = on
	print("GIF: recording ", "ON" if on else "OFF", " at frame ", _frame)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func scene() -> Node:
	return get_tree().current_scene


## Change scene and wait until the new one is current (and has had a moment).
func go(path: String, settle: float = 0.5) -> Node:
	var old := get_tree().current_scene
	SceneCache.change_scene(path)
	while get_tree().current_scene == old or get_tree().current_scene == null:
		await get_tree().process_frame
	await wait(settle)
	return get_tree().current_scene


func find_first(from: Node, cls: String) -> Node:
	if from.is_class(cls):
		return from
	for c in from.get_children():
		var r := find_first(c, cls)
		if r != null:
			return r
	return null


func tween_prop(obj: Object, prop: String, to, dur: float, trans := Tween.TRANS_SINE) -> void:
	var t := get_tree().create_tween()
	t.tween_property(obj, prop, to, dur).set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	await t.finished


func key(code: Key, pressed_for: float = 0.0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	if pressed_for > 0.0:
		await wait(pressed_for)
	else:
		await get_tree().process_frame
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame


func action(nm: String, held: float = 0.0) -> void:
	Input.action_press(nm)
	if held > 0.0:
		await wait(held)
	else:
		await get_tree().process_frame
	Input.action_release(nm)
	await get_tree().process_frame


## A drawn arrow cursor: the OS cursor is not part of the rendered frame.
var _cursor_layer: CanvasLayer = null
var _cursor: Polygon2D = null
var _mouse := Vector2(960, 540)

func show_cursor(on: bool = true) -> void:
	if _cursor_layer == null:
		_cursor_layer = CanvasLayer.new()
		_cursor_layer.layer = 1000
		add_child(_cursor_layer)
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 26), Vector2(7, 20),
			Vector2(12, 31), Vector2(17, 29), Vector2(12, 18), Vector2(20, 18)])
		var outline := Polygon2D.new()
		var big := PackedVector2Array()
		for q in pts:
			big.append(q * 1.18 + Vector2(-1.6, -2.2))
		outline.polygon = big
		outline.color = Color.BLACK
		_cursor = Polygon2D.new()
		_cursor.polygon = pts
		_cursor.color = Color.WHITE
		_cursor.add_child(outline)
		outline.show_behind_parent = true
		_cursor_layer.add_child(_cursor)
	_cursor_layer.visible = on
	_cursor.position = _mouse


func _motion(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.relative = pos - _mouse
	_mouse = pos
	Input.parse_input_event(m)
	if _cursor != null:
		_cursor.position = pos


## Glide the mouse to `to` over `dur` seconds, a motion event every frame.
func move_mouse(to: Vector2, dur: float = 0.4) -> void:
	var from := _mouse
	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k := clampf(t / dur, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		_motion(from.lerp(to, k))
		await get_tree().process_frame
	_motion(to)
	await get_tree().process_frame


func click(pos: Vector2, button := MOUSE_BUTTON_LEFT, glide: float = 0.0) -> void:
	if glide > 0.0:
		await move_mouse(pos, glide)
	else:
		_motion(pos)
		await get_tree().process_frame
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = pos
	e.global_position = pos
	e.pressed = true
	Input.parse_input_event(e)
	if _cursor != null:
		_cursor.scale = Vector2(0.85, 0.85)
	await wait(0.08)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	if _cursor != null:
		_cursor.scale = Vector2.ONE
	await get_tree().process_frame


func done() -> void:
	rec(false)
	print("GIF: wrote ", _frame, " frames to ", _out)
	get_tree().quit()


# ============================================================
# SLOT SET-UP
# ============================================================

## A fully stocked save on GIF_SLOT: every card, coin, sleeve, costume, cash.
func stock_slot() -> void:
	GameState.load_slot(GIF_SLOT)
	if not GameState.progress.get("first_launch_complete", false):
		GameState.progress["first_launch_complete"] = true
	for code in ["CHT.All_Cards_1", "CHT.All_Cards_2", "CHT.All_Cards_3", "CHT.All_Cards_4",
			"CHT.All_Coins", "CHT.All_Costumes", "CHT.All_Sleeves", "CHT.All_Energy_Styles",
			"CHT.Gimme_Cash"]:
		CheatManager.apply_code(code)
	for f in ["help_cosmetics_seen", "help_deck_builder_seen"]:
		GameState.set_flag(f)
	GameState.save_progress()
	write_current_data({})
	# Recording pace: animations at medium, text fast. Not written to Settings.json.
	GameState.set_animation_speed(_args.get("anim", "medium"), false)
	GameState.set_text_speed(_args.get("text", "fast"), false)


## Player_Current_Data.json for the gif slot: a name, costume, sleeve and coin, plus `extra`.
func write_current_data(extra: Dictionary) -> void:
	var data := {
		"coin": "Charizard Red", "date_of_birth": "27/02", "deck": "", "energy_style": "Base1",
		"last_pack_loaded": "base1", "last_set_loaded": "base1", "name": "Red",
		"sleeve": "151_ETB", "sprite": "1Hilbert",
	}
	data.merge(extra, true)
	var f := FileAccess.open(GameState.PLAYER_CURRENT_DATA_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "	"))
	f.close()


# ============================================================
# SHOTS
# ============================================================

func _run() -> void:
	if _out == "" or _shot == "":
		printerr("GifDirector: pass --shot=<name> --out=<folder>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await get_tree().process_frame
	if not has_method("shot_" + _shot):
		printerr("GifDirector: no shot ", _shot)
		get_tree().quit(1)
		return
	await call("shot_" + _shot)


## Waits for a menu's loading overlay to go (grids build a few tiles per frame).
func wait_loaded(s: Node, min_secs: float = 1.0) -> void:
	await wait(min_secs)
	var ov = s.get("_loading_overlay")
	var guard := 0
	while ov != null and ov.is_showing() and guard < 4000:
		await get_tree().process_frame
		guard += 1
	await wait(0.5)


## Mouse-wheel style: a short glide of `step` px, then a hold. Small gifs come from
## still frames, and a real scroll looks like this anyway.
func wheel_scroll(sc: ScrollContainer, step: int, hold: float, max_steps: int = 99, up := false) -> void:
	for _i in max_steps:
		var bottom := int(sc.get_v_scroll_bar().max_value - sc.size.y)
		var target := clampi(sc.scroll_vertical + (-step if up else step), 0, bottom)
		if target == sc.scroll_vertical:
			return
		await tween_prop(sc, "scroll_vertical", target, 0.3)
		await wait(hold)


## Click the middle of a Control (a real mouse click at its on-screen centre).
func click_node(c: Control, glide: float = 0.0) -> void:
	await click(c.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, glide)


## The grid tile nearest `point` on screen.
func tile_near(sc: ScrollContainer, point: Vector2) -> Control:
	var grid := find_first(sc, "GridContainer")
	if grid == null:
		return null
	var best: Control = null
	var best_d := INF
	for c in grid.get_children():
		if c is Control and c.visible:
			var d := (c as Control).get_global_rect().get_center().distance_to(point)
			if d < best_d:
				best_d = d
				best = c
	return best


## A cosmetic grid: open, settle, wheel down through the collection, back up a bit,
## and pick a tile.
func _grid_shot(scene_path: String, step: int, steps: int, pick := Vector2(1000, 470)) -> void:
	stock_slot()
	var s := await go(scene_path, 0.2)
	await wait_loaded(s)
	var sc := find_first(s, "ScrollContainer") as ScrollContainer
	rec(true)
	await wait(1.5)
	if sc != null:
		await wheel_scroll(sc, step, 0.6, steps)
		await wait(0.4)
		await wheel_scroll(sc, step, 0.5, 3, true)
		var t := tile_near(sc, pick)
		if t != null:
			await click_node(t)
	await wait(2.5)
	await done()


func shot_coins() -> void:
	await _grid_shot("res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn", 260, 5)


func shot_sleeves() -> void:
	await _grid_shot("res://Scenes/Main_Menu_Scenes/Sleeves_Scene.tscn", 260, 6)


func shot_trainers() -> void:
	await _grid_shot("res://Scenes/Main_Menu_Scenes/Costume_Scene.tscn", 260, 6)


## The trainer card, re-opened in a few costumes (as the old gif did).
func shot_trainercard() -> void:
	stock_slot()
	var looks := [["1Hilbert", "151_ETB", "Charizard Red"], ["1MayEmerald", "1_Default_English", "Pikachu Silver"],
		["1Olly", "151_ETB", "Eevee Gold"], ["1Rosa", "1_Default_English", "Blastoise Blue"]]
	for i in looks.size():
		var l: Array = looks[i]
		write_current_data({"sprite": l[0], "sleeve": l[1], "coin": l[2],
			"name": ["Red", "May", "Olly", "Rosa"][i]})
		rec(false)
		var s := await go("res://Scenes/Main_Menu_Scenes/Info_Scene.tscn", 0.2)
		await wait(1.5)
		rec(true)
		await wait(2.2)
	await done()


## The deck builder: hover a few cards (the big preview follows), add some, flip sets.
func shot_cards() -> void:
	stock_slot()
	var s := await go("res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn", 0.2)
	await wait_loaded(s, 2.0)
	show_cursor()
	_motion(Vector2(700, 900))
	rec(true)
	await wait(0.8)
	var grid: GridContainer = s.grid
	for page in 4:
		var cards: Array = []
		for c in grid.get_children():
			if c is Control and c.visible and c.has_meta("card_id"):
				cards.append(c)
		for k in [0, 9, 12]:
			if k < cards.size():
				await move_mouse((cards[k] as Control).get_global_rect().get_center(), 0.35)
				await wait(0.45)
				if page < 2 and k != 9:
					await click_node(cards[k])
					await wait(0.25)
		if page == 1:
			# Hold Shift over a card: the full card detail panel.
			await move_mouse((cards[3] as Control).get_global_rect().get_center(), 0.35)
			var e := InputEventKey.new()
			e.keycode = KEY_SHIFT
			e.physical_keycode = KEY_SHIFT
			e.pressed = true
			Input.parse_input_event(e)
			await wait(1.4)
			await move_mouse((cards[5] as Control).get_global_rect().get_center(), 0.35)
			await wait(1.4)
			var u := e.duplicate()
			u.pressed = false
			Input.parse_input_event(u)
			await wait(0.5)
		if page < 3:
			await click_node(s.next_btn, 0.45)
			await wait(1.0)
	await wait(1.0)
	await done()


## Buy a pack and open it: every card revealed, the summary, back to the shop.
func _pack_shot(shop_id: String, pack_id: String, pick: int) -> void:
	stock_slot()
	CheatManager._set_cards_in_set(pack_id, 0)   # so the reveals carry their NEW labels
	write_current_data({"last_pack_loaded": pack_id})
	GameState.current_shop_id = shop_id
	var s := await go("res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn", 0.2)
	await wait(1.5)
	show_cursor()
	_motion(Vector2(960, 900))
	rec(true)
	await wait(0.8)
	var packs: Array = []
	for c in s.pack_hbox.get_children():
		if c is Control and c.visible:
			packs.append(c)
	var target: Control = packs[min(pick, packs.size() - 1)]
	var tr := find_first(target, "TextureRect") as Control
	await click_node(tr if tr != null else target, 0.5)
	await wait(0.7)
	await click_node(s.buy_button, 0.45)
	await wait(0.3)
	show_cursor(false)
	var pom = PackOpeningManager
	var guard := 0
	while not pom.is_active() and guard < 200:
		await get_tree().process_frame
		guard += 1
	guard = 0
	while pom.is_active() and guard < 3000:
		guard += 1
		if pom._showing_summary:
			await wait(3.0)
			await click(Vector2(960, 540))
			await wait(0.3)
		elif pom._waiting_for_advance:
			await wait(0.75)
			await click(Vector2(960, 540))
		else:
			await get_tree().process_frame
	await wait(1.5)
	await done()


func shot_packopening() -> void:
	await _pack_shot("rocket_mart", "base5", 1)


func shot_packopening2() -> void:
	await _pack_shot("gym_mart", "gym2", 2)


# ============================================================
# OVERWORLD
# ============================================================

## A mid-game day: every story beat done (no cutscene or phone call can take over),
## on `date` at `time`.
func story_state(date: int, time: String) -> void:
	DebugCutscenes._reset_story()
	DebugCutscenes._post_intro(GameState.FAMILIARITY_PLAYED, date, time)
	var p := GameState.progress
	p[CafeBreakfastCutscene.STAGE_KEY] = CafeBreakfastCutscene.STAGE_DONE
	p[TownHallTrioCutscene.STAGE_KEY] = TownHallTrioCutscene.STAGE_DONE
	for f in [CafeBreakfastCutscene.OLLY_GONE_FLAG, CafeBreakfastCutscene.CALL_DONE_FLAG,
			CafeBreakfastCutscene.FISH_CALL_DONE_FLAG, CardMartDuoCutscene.BOUGHT_FLAG,
			CardMartDuoCutscene.BONUS_FLAG, CardMartDuoCutscene.GONE_FLAG,
			GameState.FISH_SHOP_INTRO_FLAG, RegistrationReminders.TRIO_DONE_FLAG,
			RegistrationReminders.FIRST_CALL_FLAG, OllyIntroCutscene.WALK_DONE_KEY]:
		p[f] = true
	var items: Array = p.get("items", [])
	if not items.has(MapManager.TRACKER_ITEM):
		items.append(MapManager.TRACKER_ITEM)
	p["items"] = items
	p["time_points"] = 0
	GameState.save_progress()


## Load a map with the player at `pos` (map-root local) facing `facing`.
func go_map(scene_path: String, pos: Vector2, facing: String = "down", settle: float = 2.5) -> Node:
	GameState.save_menu_return_state(scene_path, pos, facing)
	GameState.save_progress()
	return await go(scene_path, settle)


func player() -> Node:
	return MapManager._player


func npc_named(nm: String) -> Node:
	for n in get_tree().get_nodes_in_group("npcs"):
		if str(n.get("npc_name")) == nm:
			return n
	for n in get_tree().get_nodes_in_group("opponents"):
		if str(n.get("opponent_name")) == nm:
			return n
	return null


func walk(dir: String, secs: float) -> void:
	Input.action_press("ui_" + dir)
	await wait(secs)
	Input.action_release("ui_" + dir)
	await get_tree().process_frame


## Space, the accept key (talk / next message).
func accept() -> void:
	await key(KEY_SPACE)


## Keep pressing Space, `gap` seconds apart, until the player can move again.
func talk_through(gap: float = 2.2, limit: int = 30) -> void:
	await wait(gap)
	for _i in limit:
		if player().can_move and not MapManager.message_panel.visible:
			return
		await accept()
		await wait(gap)


## Stand `below` px under an NPC, walk up into them and press Space (the real talk
## path); if that did not start a conversation, talk the debug way.
func approach_and_talk(npc: Node, walk_secs: float = 0.35) -> void:
	await walk("up", walk_secs)
	await wait(0.25)
	await accept()
	await wait(0.3)
	if player().can_move and not MapManager.message_panel.visible:
		print("GIF: Space missed the NPC, talking directly")
		MapManager._on_player_npc_interact(npc)


## Walk up to an NPC and talk to them: the gift sequence.
func shot_gift() -> void:
	stock_slot()
	story_state(5, "Afternoon")
	var s := await go_map("res://Scenes/Map_Scenes/Celeste_Harbour.tscn", Vector2(290, 1700), "up", 1.0)
	var kid := npc_named("Kid Opening Packs")
	kid.set("move_pattern", "idle")
	player().global_position = kid.global_position + Vector2(0, 46)
	await wait(3.5)
	rec(true)
	await wait(0.8)
	await approach_and_talk(kid, 0.3)
	await talk_through(2.4)
	await wait(1.0)
	await done()


## The gym hall at three times of day: the crowd changes and the interior darkens.
func shot_gymhall() -> void:
	stock_slot()
	var first := true
	for t in ["Afternoon", "Evening", "Night"]:
		story_state(13, t)
		rec(false)
		GameState.entering_from = "Gym_Challenge_Reception"
		GameState.save_progress()
		await go("res://Scenes/Map_Scenes/Gym_Challenge_Hall.tscn", 3.5)
		rec(true)
		await wait(0.4)
		await walk("up", 1.6)
		await wait(1.0)
	await done()


## The arrival: the taxi drives in at night while Olly's call plays over it.
func shot_taxi() -> void:
	stock_slot()
	story_state(1, "Bedtime")
	rec(true)
	DebugCutscenes.launch("taxi_played")
	var sc: Node = null
	while sc == null or sc.get("_taxi_intro_phase") != true:
		await get_tree().process_frame
		sc = get_tree().current_scene
	# The drive is DRIVE_TIME + STOP_TIME from here; the call's lines are paced to finish
	# as the taxi pulls up, each held once it has finished typing.
	var t := 0.0
	var end_at := 22.0 - 0.6
	while t < 60.0:
		var call = sc.get("_intro_call")
		var live: bool = call != null and is_instance_valid(call) and not call.is_finished()
		if live and call._box != null and call._box.visible and not call._box.is_typing():
			var left := maxi(1, call._lines.size() - _taxi_presses)
			var hold := maxf(1.3, (end_at - t) / float(left))
			await wait(hold)
			t += hold
			if is_instance_valid(call) and not call.is_finished():
				await accept()
				_taxi_presses += 1
			await wait(0.2)
			t += 0.2
			continue
		if not live and t > 5.0 and sc.get("_taxi_intro_phase") == false:
			break
		await wait(0.1)
		t += 0.1
	# The player steps out of the cab: end there.
	await wait(float(_args.get("tail", "1.4")))
	await done()


## 8am -> 3am in one shot, stood between the Celestite and the windmills.
func shot_times() -> void:
	stock_slot()
	# Loaded at Evening: in the day the harbour frees its lamps ($LIGHTS) on load, and they
	# could never come on. The clock is wound back to 8am below (lamps fade with the hour).
	story_state(6, "Evening")
	var s := await go_map("res://Scenes/Map_Scenes/Celeste_Harbour.tscn", Vector2(0, 0), "down", 1.0)
	GameState.progress["time"] = "Morning"
	GameState.progress["time_points"] = 0
	s.refresh_time_visuals()
	var cel := s.get_node_or_null("TILE_MAPS/WINDYHILL/Collision/celestite") as Node2D
	var off := Vector2(float(_args.get("dx", "-190")), float(_args.get("dy", "90")))
	if cel != null:
		player().global_position = cel.global_position + off
	await wait(4.0)
	var clock = s.get("_clock")
	var tpa := GameState.time_points_to_advance()
	var h_from := 8.0
	var h_to := 27.0
	var secs := float(_args.get("secs", "14"))
	rec(true)
	if clock != null:
		clock.peek()
	await wait(1.0)
	var t := 0.0
	var slots := ["Morning", "Afternoon", "Evening", "Night", "Bedtime"]
	while t <= secs:
		var h := lerpf(h_from, h_to, clampf(t / secs, 0.0, 1.0))
		var slot_i := clampi(int((h - 8.0) / 4.0), 0, 4)
		var pts := int(round((h - (8.0 + 4.0 * slot_i)) / 4.0 * tpa))
		GameState.progress["time"] = slots[slot_i]
		GameState.progress["time_points"] = pts
		# Houses and shops turn in at Bedtime; the street lights stay on (set_time_of_day).
		var late := s.get_node_or_null("LIGHTS/LATENIGHTOFF")
		if late != null:
			late.visible = slots[slot_i] != "Bedtime"
		s.refresh_time_visuals()
		if clock != null:
			clock.peek()
		await get_tree().process_frame
		t += get_process_delta_time()
	await wait(2.0)
	await done()


# ============================================================
# MATCHES
# ============================================================

const FIRE_FIGHT := {
	"base1-68": 4, "base1-12": 3, "base1-46": 3, "base1-24": 2, "base1-4": 2,
	"base1-52": 2, "base1-34": 1, "base1-8": 1,
	"base1-84": 3, "base1-80": 2, "base1-91": 3, "base1-88": 1, "base1-81": 2, "base1-76": 2,
	"base1-93": 1, "base1-90": 1, "base1-71": 1,
	"base1-96": 3, "base1-98": 13, "base1-97": 10,
}
const WATER_GRASS := {
	"base1-63": 3, "base1-42": 2, "base1-2": 2, "base1-44": 3, "base1-30": 2, "base1-15": 1,
	"base1-3": 2, "base3-10": 1, "base2-11": 1,
	"base1-84": 3, "base1-80": 2, "base1-91": 3, "base1-88": 1, "base1-76": 2, "base1-90": 1,
	"base1-81": 1, "base1-93": 1, "base1-71": 1,
	"base1-96": 2, "base5-82": 2, "base5-81": 2, "base5-17": 1, "base1-102": 12, "base1-99": 9,
}

func deck_array(d: Dictionary) -> Array:
	var out: Array = []
	var total := 0
	for k in d:
		out.append({"id": k, "count": d[k]})
		total += int(d[k])
	if total != 60:
		printerr("GIF: deck has ", total, " cards")
	return out


## A whole CPU-vs-bot match (the autotester's runner, watched at real speed) with two
## hand-built base-era decks. Every frame is kept; pick the stretch for the gif after.
func shot_battle() -> void:
	stock_slot()
	_jpg = true
	var runner = load("res://Scripts/Autotest/Autotest_Runner.gd").new()
	runner.opt_watch = true
	runner.opt_timescale = 1.0
	runner.opt_bot_smart = true
	runner.opt_matches = 1
	runner.replay_run = "gif"
	runner.replay_record = {"player_deck": deck_array(FIRE_FIGHT), "opponent_deck": deck_array(WATER_GRASS),
		"seed": int(_args.get("seed", "4242")),
		"opponent_data": {"name": "Ellie", "deck": "TEST", "sprite": "1Ellie_Hoodie", "music": "",
			"prize_cards": 6, "coin_reward": "", "sleeve": "", "match_effects": [], "restrictions": {}}}
	get_tree().root.add_child(runner)
	runner.opt_seed = int(_args.get("seed", "4242"))
	await wait(0.5)
	# Roll from turn `from` (the late game, board full) - or from the start.
	var from_turn := int(_args.get("from", "0"))
	var last_turn := -1
	var t := 0.0
	var cap := float(_args.get("cap", "1500"))
	while t < cap and not runner.match_done:
		if not _recording and runner.current_main != null and is_instance_valid(runner.current_main) 				and int(runner.current_main.turn_number) >= from_turn:
			print("GIF: rolling at turn ", runner.current_main.turn_number)
			rec(true)
		if runner.current_main != null and is_instance_valid(runner.current_main) 				and int(runner.current_main.turn_number) != last_turn:
			last_turn = int(runner.current_main.turn_number)
			print("GIF: turn ", last_turn, " at frame ", _frame)
		await wait(0.1)
		t += 0.1
	await wait(2.0)
	await done()


## Headless seed scouting for shot_battle: many fast matches with the same two decks.
## matches.jsonl in the run folder says how long each went and what was played.
func shot_scout() -> void:
	stock_slot()
	var runner = load("res://Scripts/Autotest/Autotest_Runner.gd").new()
	runner.opt_bot_smart = true
	runner.replay_run = "gif"
	runner.replay_record = {"player_deck": deck_array(FIRE_FIGHT), "opponent_deck": deck_array(WATER_GRASS),
		"seed": 0, "opponent_data": {}}
	get_tree().root.add_child(runner)
	runner.opt_matches = int(_args.get("n", "40"))
	runner.opt_seed = int(_args.get("seed", "5000"))


## Give the gif slot a playable deck and make it the active one.
func equip_deck(nm: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GameState.PLAYER_DECKS_FOLDER)
	var f := FileAccess.open(GameState.PLAYER_DECKS_FOLDER + nm + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(deck_array(d), "\t"))
	f.close()
	write_current_data({"deck": nm})


## From talking to an overworld opponent to the opening hand being dealt: the zoom in,
## the VS badge, sprites and names sliding in, the decks, the shuffle and the deal.
func shot_matchstart() -> void:
	stock_slot()
	equip_deck("Fire Fight", FIRE_FIGHT)
	story_state(6, "Afternoon")
	var s := await go_map("res://Scenes/Map_Scenes/Celeste_Harbour.tscn", Vector2(950, 1350), "up", 1.0)
	var want := String(_args.get("opp", "Hiker Ben"))
	var opp: Node = npc_named(want)
	if opp == null:
		for n in get_tree().get_nodes_in_group("opponents"):
			print("GIF: opponent on map: ", n.get("opponent_name"))
		opp = get_tree().get_nodes_in_group("opponents")[0]
	print("GIF: challenging ", opp.get("opponent_name"))
	opp.set("move_pattern", "idle")
	player().global_position = opp.global_position + Vector2(0, 46)
	await wait(3.5)
	rec(true)
	await wait(0.6)
	await approach_and_talk(opp, 0.3)
	var guard := 0
	while not MatchTransition.is_active() and guard < 25:
		await wait(2.0)
		if not MatchTransition.is_active():
			await accept()
		guard += 1
	guard = 0
	while MatchTransition.is_active() and guard < 600:
		await wait(0.1)
		guard += 1
	await wait(2.5)
	await done()


## A Pokémon in play for the staged board: `energies` by uid, `damage` taken.
func _staged_mon(m: Node, uid: String, energies: Array, damage: int, where: String) -> card_object:
	var p := card_object.new(uid, m.get_card_metadata(uid))
	p.current_hp = p.get_max_hp() - damage
	p.current_location = where
	p.placed_on_field_this_turn = false
	for e in energies:
		var ec := card_object.new(e, m.get_card_metadata(e))
		ec.current_location = "attached"
		p.attached_energies.append(ec)
	return p


func _staged_cards(m: Node, uids: Array, where: String) -> Array:
	var out: Array = []
	for u in uids:
		var k := card_object.new(u, m.get_card_metadata(u))
		k.current_hp = k.get_max_hp()
		k.current_location = where
		out.append(k)
	return out


## Swap in a late-game board: both benches full of evolved, damaged, powered-up
## Pokémon, three Prizes each, PlusPower / Defender / Gust in both hands.
func _stage_board(m: Node) -> void:
	for side in ["player_", "opponent_"]:
		var disc: Array = m.get(side + "discard_pile")
		if m.get(side + "active_pokemon") != null:
			disc.append(m.get(side + "active_pokemon"))
		disc.append_array(m.get(side + "bench"))
		var prizes: Array = m.get(side + "prize_cards")
		while prizes.size() > 3:
			disc.append(prizes.pop_back())
		for k in disc:
			k.current_location = "discard"
	var F := "base1-98"; var W := "base1-102"; var G := "base1-99"; var FI := "base1-97"; var DCE := "base1-96"
	m.player_active_pokemon = _staged_mon(m, "base1-12", [F, F, F, F], 20, "active")          # Ninetales: Fire Blast
	m.player_bench = [
		_staged_mon(m, "base1-4", [F, F, F, F], 50, "bench"),                                # Charizard: Fire Spin
		_staged_mon(m, "base1-8", [FI, FI, FI, DCE], 30, "bench"),                           # Machamp: Seismic Toss
		_staged_mon(m, "base1-24", [F, F], 10, "bench"),                                      # Charmeleon
		_staged_mon(m, "base1-34", [FI, FI], 20, "bench"),                                    # Machoke
	]
	m.opponent_active_pokemon = _staged_mon(m, "base1-2", [W, W, W, W, W, "base5-82"], 0, "active")   # Blastoise: Hydro Pump
	m.opponent_bench = [
		_staged_mon(m, "base1-15", [G, G, G, G], 30, "bench"),                               # Venusaur: Solarbeam
		_staged_mon(m, "base1-3", [DCE, DCE], 40, "bench"),                                   # Chansey: Double-edge
		_staged_mon(m, "base3-10", ["base5-17", W], 10, "bench"),                             # Lapras
		_staged_mon(m, "base1-30", [G, "base5-81"], 0, "bench"),                              # Ivysaur
	]
	m.player_hand = _staged_cards(m, ["base1-84", "base1-80", F, "base1-93", "base1-90"], "hand")
	m.opponent_hand = _staged_cards(m, ["base1-84", "base1-80", W, "base1-90"], "hand")
	for o in [false, true]:
		m.display_pokemon(o)
		m.display_active_pokemon_energies(o)
		m.display_prize_cards(o)
		m.update_discard_pile_display(o)
		m.update_deck_icon(o)
		m.refresh_pokemon_hp_display(m.opponent_active_pokemon if o else m.player_active_pokemon, o)
	m.refresh_both_hands()
	m.refresh_board_labels()
	if m.cpu_ai != null and m.cpu_ai.has_method("invalidate_cpu_evaluation"):
		m.cpu_ai.invalidate_cpu_evaluation()


## The battle gif: a real match (CPU vs the autotester's smart bot) switched onto a staged
## late-game board on the bot's turn, then played out with nothing scripted.
func shot_staged() -> void:
	stock_slot()
	_jpg = true
	var runner = load("res://Scripts/Autotest/Autotest_Runner.gd").new()
	runner.opt_watch = true
	runner.opt_timescale = 1.0
	runner.opt_bot_smart = true
	runner.opt_matches = 1
	runner.replay_run = "gif"
	runner.replay_record = {"player_deck": deck_array(FIRE_FIGHT), "opponent_deck": deck_array(WATER_GRASS),
		"seed": int(_args.get("seed", "7001")),
		"opponent_data": {"name": "Ellie", "deck": "TEST", "sprite": "1Ellie_Hoodie", "music": "",
			"prize_cards": 6, "coin_reward": "", "sleeve": "", "match_effects": [], "restrictions": {}}}
	get_tree().root.add_child(runner)
	runner.opt_seed = int(_args.get("seed", "7001"))
	var at_turn := int(_args.get("at", "3"))
	var m: Node = null
	var bot: Node = null
	while true:
		await get_tree().process_frame
		m = runner.current_main
		bot = runner.current_bot
		if m != null and is_instance_valid(m) and bot != null and int(m.turn_number) >= at_turn \
				and not m.opponents_turn_active:
			break
	bot.set_process(false)
	while not bot._board_idle():
		await get_tree().process_frame
	# Test mode shows the CPU's hand and both Prize rows face up; a real match does not.
	m.hide_hidden_cards = true
	_stage_board(m)
	print("GIF: staged board at turn ", m.turn_number)
	await wait(0.4)
	rec(true)
	await wait(1.5)
	bot.set_process(true)
	var last_turn := -1
	var t := 0.0
	var cap := float(_args.get("cap", "240"))
	while t < cap and not runner.match_done:
		if is_instance_valid(m) and int(m.turn_number) != last_turn:
			last_turn = int(m.turn_number)
			print("GIF: turn ", last_turn, " at frame ", _frame)
		await wait(0.1)
		t += 0.1
	await wait(1.0)
	await done()
