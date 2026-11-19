extends "res://Scripts/Autotest/Autotest_Runner.gd"
## AUDIT STEP 2 - run-the-code harness. Plays ONE real match scene headlessly, but instead of letting the bot play, puts a
## chosen card into play on the player's side against a standard defender, runs each attack / activated Power / Trainer once,
## and logs what happened. Output: audit_out/run_log.jsonl (one line per job), audit_out/run_progress.json (resume).
## Run (project folder, Git Bash):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --fixed-fps 60 --path . res://Scripts/Utilities/audit/Card_Probe.tscn -- --probe-set=ex10 [--all] [--probe-cards=uid,uid] [--probe-max=N]
## Default job list = cards of the set(s) that appear in audit_out/triage_cards.csv; --all = every card with an effect.

const ProbeBotScript := preload("res://Scripts/Utilities/audit/Probe_Bot.gd")
const PROBE_OUT := "res://audit_out/"
const JOB_TIMEOUT_FRAMES := 1500
const READY_TIMEOUT_FRAMES := 3000

var p_sets: Array = []
var p_cards: Array = []
var p_all := false
var p_max := 0
var p_reset := false
var p_kind := ""
var done_keys: Dictionary = {}
var jobs: Array = []
var job: Dictionary = {}
var job_finished := false
var job_post: Dictionary = {}
var job_msgs: Array = []
var def_card = null
var basic_uid := ""
var def_uid := ""
var pbot = null
var job_extra: Dictionary = {}
var stage1_uid := ""
var trainer_uids: Array = []
var inert_tool_uid := ""
const ATTACKER_UID := "ex11-80"   # Porygon: Basic, Colorless, one plain 30-damage attack for CC, no text
const TYPES := ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Colorless"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"probe-set": p_sets = Array(v.to_lower().split(",", false))
			"probe-cards": p_cards = Array(v.to_lower().split(",", false))
			"all": p_all = true
			"probe-max": p_max = int(v)
			"probe-reset": p_reset = true
			"kind": p_kind = v
	super._ready()


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func _flagged_uids() -> Dictionary:
	var out := {}
	var path := _abs(PROBE_OUT + "triage_cards.csv")
	if not FileAccess.file_exists(path):
		return out
	var first := true
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		if first:
			first = false
			continue
		out[line.get_slice(",", 0).to_lower()] = true
	return out


func _build_jobs() -> void:
	var flagged := _flagged_uids()
	var uids: Array = cards.keys()
	uids.sort()
	for uid in uids:
		var low: String = String(uid).to_lower()
		var set_id := low.get_slice("-", 0)
		if not p_cards.is_empty():
			if not (low in p_cards): continue
		else:
			if not (set_id in p_sets): continue
			if not p_all and not flagged.has(low): continue
		var md: Dictionary = cards[uid]
		var st := String(md.get("supertype", ""))
		if st == "Pokémon":
			var attacks: Array = md.get("attacks", [])
			for i in attacks.size():
				jobs.append({"uid": uid, "kind": "attack", "index": i, "name": attacks[i].get("name", "")})
			for ab in md.get("abilities", []):
				var t := String(ab.get("type", ""))
				var tx := String(ab.get("text", "")).to_lower()
				if "Body" in t: continue
				if "once during your turn" in tx or "as often as you like" in tx:
					jobs.append({"uid": uid, "kind": "power", "name": ab.get("name", ""), "ability": ab})
		elif st == "Trainer" and not ("Stadium" in md.get("subtypes", []) or "Pokémon Tool" in md.get("subtypes", [])):
			jobs.append({"uid": uid, "kind": "trainer", "name": md.get("name", "")})
	_build_ext_jobs(uids)
	var keep: Array = []
	for j in jobs:
		if p_kind != "" and j["kind"] != p_kind:
			continue
		if not done_keys.has(_key(j)):
			keep.append(j)
	jobs = keep
	if p_max > 0 and jobs.size() > p_max:
		jobs = jobs.slice(0, p_max)


## EXTENDED AUDIT (2026-11-19): Tools, Stadiums, Special Energy and conditional boards. Not limited to triage-flagged cards.
func _build_ext_jobs(uids: Array) -> void:
	for uid in uids:
		var low: String = String(uid).to_lower()
		var set_id := low.get_slice("-", 0)
		if not p_cards.is_empty():
			if not (low in p_cards): continue
		elif not (set_id in p_sets): continue
		var md: Dictionary = cards[uid]
		var st := String(md.get("supertype", ""))
		var subs: Array = md.get("subtypes", [])
		var rules := " ".join(md.get("rules", [])).to_lower()
		if st == "Trainer" and "Pokémon Tool" in subs:
			var scs := ["play_me", "play_foe", "atk_tool", "def_tool", "def_tool_ko", "def_tool_dmg"]
			for t in TYPES:
				if t != "Colorless" and rules.contains(t.to_lower()): scs.append("atk_tool_type_" + t)
			if rules.contains("between turns") or rules.contains("end of any turn") or rules.contains("start of each turn"):
				scs.append("between_me2"); scs.append("between_foe")
			if rules.contains("prize"): scs.append("atk_tool_prize")
			for sc in scs: jobs.append({"uid": uid, "kind": "tool", "name": md.get("name", ""), "scen": sc})
		elif st == "Trainer" and "Stadium" in subs:
			var scs3 := ["play", "replace_foe", "same_name", "actions", "atk", "stats", "play_bench5"]
			for t in TYPES:
				if t != "Colorless" and rules.contains(t.to_lower()): scs3.append("stats_type_" + t)
			var rx := RegEx.new()
			rx.compile("with ([^.]*?) in (?:its|their) name")
			for mt in rx.search_all(String(" ".join(md.get("rules", [])))):
				for nm in mt.get_string(1).split(" or "): scs3.append("stats_name_" + nm.strip_edges())
			for sc in scs3: jobs.append({"uid": uid, "kind": "stadium", "name": md.get("name", ""), "scen": sc})
		elif st == "Energy" and "Special" in subs:
			var scs2 := ["provides", "attach_hurt", "atk_alone", "atk_plus", "def_hit", "provides_ok", "atk_ok", "def_ok", "attach_ok"]
			for t in TYPES:
				if t != "Colorless" and rules.contains(t.to_lower()): scs2.append("atk_type_" + t)
			for sc in scs2: jobs.append({"uid": uid, "kind": "senergy", "name": md.get("name", ""), "scen": sc})
		elif st == "Pokémon":
			var attacks: Array = md.get("attacks", [])
			for i in attacks.size():
				var tl := String(attacks[i].get("text", "")).to_lower()
				if tl == "": continue
				for v in _cond_variants(tl, String(md.get("name", "")).to_lower()):
					jobs.append({"uid": uid, "kind": "cond", "index": i, "name": attacks[i].get("name", ""), "scen": v})


## Which condition-true boards an attack's text asks for.
func _cond_variants(tl: String, nm: String) -> Array:
	var v: Array = []
	if "pokémon-ex" in tl or "pokémon ex" in tl or "-ex" in tl: v.append("def_ex")
	if "evolved" in tl or "evolution" in tl or "stage 1" in tl or "stage 2" in tl: v.append("def_evolved")
	if "stage 2" in tl: v.append("def_stage2")
	var dmg_rx := RegEx.new()
	dmg_rx.compile("damage counters? on ([^.,;]+)")
	var dmg_hits := dmg_rx.search_all(tl)
	for mt in dmg_hits:
		var tgt := mt.get_string(1)
		if "defending" in tgt or "opponent" in tgt or "that pok" in tgt: v.append("def_damaged")
		elif nm in tgt or "this pok" in tgt or "itself" in tgt or "it " in tgt + " ": v.append("me_damaged")
		else: v.append("def_damaged"); v.append("me_damaged")
	if dmg_hits.is_empty() and ("damaged" in tl or "any damage" in tl or "has damage" in tl or "has no damage" in tl):
		v.append("def_damaged"); v.append("me_damaged")
	if "prize" in tl: v.append("my_prize1"); v.append("foe_prize1")
	for w in ["asleep", "confused", "paralyzed", "poisoned", "burned"]:
		if tl.contains("defending pokémon is " + w): v.append("def_" + w)
	if "special condition" in tl: v.append("def_asleep"); v.append("def_poisoned")
	if "bench" in tl and ("for each" in tl or "if " in tl or "number" in tl):
		if "opponent's bench" in tl or "opponent's benched" in tl: v.append("foe_bench0"); v.append("foe_bench5")
		if "your bench" in tl or "your benched" in tl or "each of your benched" in tl: v.append("own_bench0"); v.append("own_bench5")
	if "discard pile" in tl:
		if "opponent's discard" in tl: v.append("foe_disc_rich")
		else: v.append("my_disc_rich"); v.append("my_disc_empty")
	if "energy attached to the defending" in tl or "defending pokémon has any energy" in tl or "defending pokémon has no energy" in tl or "energy cards attached to the defending" in tl:
		var et := ""
		for t in TYPES:
			if t != "Colorless" and (t.to_lower() + " energy attached to the defending") in tl: et = t
		v.append("def_energy3" + ("_" + et if et != "" else ""))
	if "cards in your hand" in tl or "your hand" in tl: v.append("hand8"); v.append("hand0")
	if "opponent's hand" in tl: v.append("foe_hand8"); v.append("foe_hand0")
	if "pokémon tool" in tl or "a tool" in tl: v.append("me_tool"); v.append("def_tool")
	if "energy attached to" in tl and "attached to the defending" not in tl and ("for each" in tl or "more damage" in tl or "plus" in tl):
		var mt2 := ""
		for t in TYPES:
			if t != "Colorless" and (t.to_lower() + " energy attached to") in tl: mt2 = t
		v.append("me_energy6" + ("_" + mt2 if mt2 != "" else ""))
	if "defending" in tl:
		for t in TYPES:
			if t != "Colorless" and (tl.contains("defending pokémon is a " + t.to_lower()) or tl.contains("defending pokémon is " + t.to_lower()) or tl.contains(t.to_lower() + " pokémon")):
				v.append("def_type_" + t)
	return v


func _key(j: Dictionary) -> String:
	var k := "%s|%s|%s" % [String(j["uid"]).to_lower(), j["kind"], j["name"]]
	if j.has("scen"): k += "|" + String(j["scen"])
	return k


func _run_all() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(PROBE_OUT))
	var pp := _abs(PROBE_OUT + "run_progress.json")
	if FileAccess.file_exists(pp) and not p_reset:
		var d = JSON.parse_string(FileAccess.get_file_as_string(pp))
		if d is Dictionary:
			for k in d.get("done", []): done_keys[k] = true
	_build_jobs()
	print("PROBE: %d jobs (%d already done) sets=%s" % [jobs.size(), done_keys.size(), str(p_sets)])
	basic_uid = ""
	for uid in cards:
		var md: Dictionary = cards[uid]
		if md.get("supertype", "") == "Pokémon" and "Basic" in md.get("subtypes", []) and md.get("abilities", []).is_empty() \
				and not md.get("attacks", []).is_empty() and int(md.get("hp", "0")) >= 40 and int(md.get("hp", "0")) <= 60:
			basic_uid = uid
			break
	def_uid = basic_uid
	for uid in cards:
		var md2: Dictionary = cards[uid]
		if stage1_uid == "" and md2.get("supertype", "") == "Pokémon" and "Stage 1" in md2.get("subtypes", []) and md2.get("abilities", []).is_empty():
			stage1_uid = uid
	inert_tool_uid = "ex6-91" if cards.has("ex6-91") else ""
	for k in ["Koga's", "Erika's", "Sabrina's", "Omanyte", "Kabuto"]:
		_named_basic(k)
	var n := 0
	while n < jobs.size():
		var ok := await _ensure_match()
		if not ok:
			print("PROBE: could not get a ready match - stopping")
			break
		await _run_job(jobs[n])
		done_keys[_key(jobs[n])] = true
		n += 1
		_write_json_abs(_abs(PROBE_OUT + "run_progress.json"), {"done": done_keys.keys(), "updated": Time.get_datetime_string_from_system()})
		if n % 25 == 0:
			print("PROBE: %d / %d" % [n, jobs.size()])
	_teardown_match()
	print("PROBE: finished %d jobs" % n)
	OS.remove_logger(_logger)
	GameState.autotest = null
	get_tree().quit()


func _write_json_abs(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _append_abs(path: String, line: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()


# ── match lifecycle ────────────────────────────────────────────────────────────────────────────────────────────────
func _teardown_match() -> void:
	if is_instance_valid(pbot): pbot.queue_free()
	if is_instance_valid(current_main):
		current_main.game_is_over = true
		current_main.queue_free()
	current_main = null
	pbot = null


func _ensure_match() -> bool:
	if is_instance_valid(current_main) and is_instance_valid(pbot) and not current_main.game_is_over:
		if await _wait_ready():
			return true
		print("PROBE: board never became idle - restarting the match")
		_teardown_match()
		for _f in 3: await get_tree().process_frame
	match_index += 1
	match_seed = opt_seed + match_index
	seed(match_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	match_done = false
	match_events = []
	match_messages = []
	match_problems = []
	match_reported = {}
	originals = [{}, {}]
	_logger.take_errors()
	var p_deck: Array = _build_deck(rng)
	var o_deck: Array = _build_deck(rng)
	var p_path := OUT_DIR + "decks/probe_player.json"
	var o_path := OUT_DIR + "decks/probe_opponent.json"
	_write_json(p_path, p_deck)
	_write_json(o_path, o_deck)
	GameState.autotest = self
	GameState.autotest_player_deck_path = p_path
	GameState.autotest_opponent_deck_path = o_path
	GameState.autotest_opponent_data = {}
	GameState.test_match_mode = true
	GameState.current_opponent_name = "TEST OPPONENT"
	GameState.current_opponent_deck = "TEST"
	GameState.current_opponent_map = ""
	GameState.last_battled_opponent_entry = GameState.build_test_opponent_data()
	GameState.clear_match_series()
	current_main = match_scene.instantiate()
	add_child(current_main)
	pbot = ProbeBotScript.new()
	pbot.name = "ProbeBot"
	add_child(pbot)
	pbot.setup(current_main, self, match_seed)
	await get_tree().process_frame
	return await _wait_ready()


func _wait_ready() -> bool:
	pbot.ready_for_job = false
	var f := 0
	while not pbot.ready_for_job and f < READY_TIMEOUT_FRAMES:
		await get_tree().process_frame
		f += 1
		if not is_instance_valid(current_main) or current_main.game_is_over:
			return false
	return pbot.ready_for_job


# ── board building ─────────────────────────────────────────────────────────────────────────────────────────────────
var named_basics: Dictionary = {}

func _named_basic(prefix: String) -> void:
	var uids: Array = cards.keys()
	uids.sort()
	for uid in uids:
		var md: Dictionary = cards[uid]
		if md.get("supertype", "") == "Pokémon" and ("Basic" in md.get("subtypes", []) or prefix in ["Omanyte", "Kabuto"]) and String(md.get("name", "")).begins_with(prefix):
			named_basics[prefix] = uid
			return


func _mk(uid: String, hp_override: int = 0, plain: bool = false) -> card_object:
	var md = current_main.get_card_metadata(uid)
	if hp_override > 0 or plain:
		md = md.duplicate(true)
		if hp_override > 0: md["hp"] = str(hp_override)
		if plain:
			md["weaknesses"] = []
			md["resistances"] = []
			md["abilities"] = []
			md["types"] = ["Colorless"]
	var k := card_object.new(uid, md)
	k.current_hp = k.get_max_hp()
	return k


func _energy_for(t: String) -> String:
	if t == "Colorless" or not basic_energy_for.has(t):
		return String(basic_energy_for.get("Fighting", "base1-97"))
	return String(basic_energy_for[t])


func _attach(p: card_object, uid: String) -> void:
	var e := _mk(uid)
	e.current_location = "attached"
	p.attached_energies.append(e)


func _pile(uids: Array, loc: String) -> Array:
	var out: Array = []
	for u in uids:
		var k := _mk(u)
		k.current_location = loc
		out.append(k)
	return out


func _filler_deck(loc: String = "deck") -> Array:
	var e: Array = []
	for t in ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting"]:
		e.append(_energy_for(t)); e.append(_energy_for(t))
	for i in 12: e.append(basic_uid)
	e.append_array(["base1-97", "base1-98", "base1-99", "base1-100", "base1-97", "base1-98"])
	return _pile(e, loc)


func _setup_board(uid: String, extra_hand: Array, opt: Dictionary = {}) -> card_object:
	var m = current_main
	m.turn_number = 7
	var me := _mk(uid, 200, true) if opt.get("plain_me", false) else _mk(uid)
	me.current_location = "active"
	me.placed_on_field_this_turn = false
	var cost_types: Array = []
	for a in me.metadata.get("attacks", []):
		for c in a.get("cost", []):
			cost_types.append(c)
	var first_type := String(me.metadata.get("types", ["Colorless"])[0])
	var attached: Array = []
	for a in me.metadata.get("attacks", []):
		var need: Array = a.get("cost", [])
		var have: Array = []
		for c in need: have.append(_energy_for(c))
		if have.size() > attached.size(): attached = have
	for u in attached: _attach(me, u)
	for i in 2: _attach(me, _energy_for(first_type))   # slack for "+" / "per Energy" attacks
	def_card = _mk(def_uid, 900, true)
	def_card.current_location = "active"
	def_card.placed_on_field_this_turn = false
	m.player_active_pokemon = me
	m.opponent_active_pokemon = def_card
	m.player_bench = []
	m.opponent_bench = []
	for i in 2:
		var b := _mk(basic_uid); b.current_location = "bench"; b.placed_on_field_this_turn = false; m.player_bench.append(b)
		var ob := _mk(def_uid, 900, true); ob.current_location = "bench"; ob.placed_on_field_this_turn = false; m.opponent_bench.append(ob)
	m.player_hand = _pile(["base1-97", "base1-98", basic_uid, "base1-99"] + extra_hand, "hand")
	m.opponent_hand = _pile(["base1-97", "base1-98", basic_uid, "base1-99"], "hand")
	m.player_deck = _filler_deck("deck")
	m.opponent_deck = _filler_deck("deck")
	m.player_discard_pile = _pile(["base1-97", "base1-98", basic_uid], "discard")
	m.opponent_discard_pile = _pile(["base1-97", "base1-98", basic_uid], "discard")
	m.player_prize_cards = _pile(["base1-97", "base1-97", "base1-97", "base1-97", "base1-97", "base1-97"], "prize")
	m.opponent_prize_cards = _pile(["base1-97", "base1-97", "base1-97", "base1-97", "base1-97", "base1-97"], "prize")
	m.current_stadium_card = null
	m.trainer_effects.player_trainer_locked = false
	m.trainer_effects.opponent_trainer_locked = false
	m.trainer_effects.player_played_supporter_this_turn = false
	m.trainer_effects.opponent_played_supporter_this_turn = false
	m.player_energy_played_this_turn = false
	for pr in m.get_property_list():
		var pn := String(pr.get("name", ""))
		if "stadium" in pn and "this_turn" in pn and typeof(m.get(pn)) == TYPE_BOOL: m.set(pn, false)
	_apply_opts(opt, me)
	for side in [false, true]:
		m.display_pokemon(side)
		m.display_active_pokemon_energies(side)
	m.refresh_both_hands()
	return me


func _basics(n: int, loc: String, hp: int = 0, plain: bool = false) -> Array:
	var out: Array = []
	for i in n:
		var b := _mk(def_uid if plain else basic_uid, hp, plain)
		b.current_location = loc
		b.placed_on_field_this_turn = false
		out.append(b)
	return out


func _rich_discard() -> Array:
	var l: Array = []
	for t in ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting"]:
		l.append(_energy_for(t)); l.append(_energy_for(t))
	l.append_array([basic_uid, basic_uid, basic_uid, stage1_uid, "base1-92", "base1-79"])
	for k in ["Omanyte", "Kabuto"]:
		if named_basics.has(k): l.append(named_basics[k])
	return _pile(l, "discard")


func _attach_card(p: card_object, uid: String) -> void:
	var k := _mk(uid)
	k.current_location = "attached"
	p.attached_cards.append(k)


func _rep(u: String, n: int) -> Array:
	var a: Array = []
	for i in n: a.append(u)
	return a


func _names(arr: Array) -> Array:
	var out: Array = []
	for c in arr: out.append(String(c.metadata.get("name", "")))
	return out


func _tail_names(arr: Array, n: int) -> Array:
	var out: Array = []
	for i in range(maxi(0, arr.size() - n), arr.size()): out.append(String(arr[i].metadata.get("name", "")))
	return out


## Variant boards: every option turns one condition of the standard board on. See _cond_variants.
func _apply_opts(o: Dictionary, me: card_object) -> void:
	if o.is_empty(): return
	var m = current_main
	var d = def_card
	if o.has("me_energy_list"):
		me.attached_energies.clear()
		for u in o["me_energy_list"]: _attach(me, u)
	if o.has("def_energy_list"):
		d.attached_energies.clear()
		for u in o["def_energy_list"]: _attach(d, u)
	for i in int(o.get("def_energy", 0)): _attach(d, _energy_for(String(o.get("def_energy_type", "Fighting"))))
	for i in int(o.get("me_extra", 0)): _attach(me, _energy_for(String(o.get("me_extra_type", "Fighting"))))
	if o.get("me_evolved", false):
		me.metadata["subtypes"] = ["Stage 1"]
		var pre0 := _mk(basic_uid)
		pre0.current_location = "attached"
		me.attached_pre_evolutions.append(pre0)
	if o.has("me_name"): me.metadata["name"] = String(o["me_name"]) + " Porygon"
	if o.has("def_name"): d.metadata["name"] = String(o["def_name"]) + " Clefairy"
	if o.has("me_type"): me.metadata["types"] = [o["me_type"]]
	if o.has("def_type"): d.metadata["types"] = [o["def_type"]]
	if o.get("def_ex", false):
		d.metadata["subtypes"] = ["Basic", "ex"]
		d.metadata["name"] = "Probe ex"
	if o.get("def_evolved", false):
		d.metadata["subtypes"] = [String(o.get("def_stage", "Stage 1"))]
		var pre := _mk(basic_uid)
		pre.current_location = "attached"
		d.attached_pre_evolutions.append(pre)
	if o.has("def_hp"):
		d.metadata["hp"] = str(int(o["def_hp"]))
		d.current_hp = int(o["def_hp"])
	if o.has("me_cur_hp"): me.current_hp = int(o["me_cur_hp"])
	if o.has("def_cur_hp"): d.current_hp = int(o["def_cur_hp"])
	if o.has("def_dmg"): d.current_hp = d.get_max_hp() - int(o["def_dmg"])
	if o.has("me_dmg"): me.current_hp = maxi(10, me.get_max_hp() - int(o["me_dmg"]))
	if o.has("def_cond"): d.special_condition = String(o["def_cond"])
	if o.get("def_pois", false): d.is_poisoned = true
	if o.get("def_burn", false): d.is_burned = true
	if o.has("me_cond"): me.special_condition = String(o["me_cond"])
	if o.get("me_pois", false): me.is_poisoned = true
	if o.get("me_burn", false): me.is_burned = true
	if o.has("own_bench"): m.player_bench = _basics(int(o["own_bench"]), "bench")
	if o.has("foe_bench"): m.opponent_bench = _basics(int(o["foe_bench"]), "bench", 900, true)
	if o.has("my_prize"): m.player_prize_cards = _pile(_rep("base1-97", int(o["my_prize"])), "prize")
	if o.has("foe_prize"): m.opponent_prize_cards = _pile(_rep("base1-97", int(o["foe_prize"])), "prize")
	if o.has("my_disc"): m.player_discard_pile = _rich_discard() if o["my_disc"] == "rich" else []
	if o.has("foe_disc"): m.opponent_discard_pile = _rich_discard() if o["foe_disc"] == "rich" else []
	if o.has("my_hand"): m.player_hand = _pile(_rep(basic_uid, int(o["my_hand"])), "hand")
	if o.has("foe_hand"): m.opponent_hand = _pile(_rep(basic_uid, int(o["foe_hand"])), "hand")
	if o.has("me_tool"): _attach_card(me, String(o["me_tool"]))
	if o.has("def_tool"): _attach_card(d, String(o["def_tool"]))
	if o.has("hand_add"):
		for u in o["hand_add"]: m.player_hand.append_array(_pile([u], "hand"))
	if o.has("foe_hand_add"):
		for u in o["foe_hand_add"]: m.opponent_hand.append_array(_pile([u], "hand"))
	if o.has("stadium"):
		var sc := _mk(String(o["stadium"]))
		sc.current_location = "stadium"
		m.current_stadium_card = sc
		m.current_stadium_owner_is_opponent = bool(o.get("stadium_opp", false))
		m.powers_and_bodies.refresh_rockets_hideout_hp()
	if o.get("rich_board", false):   # what the Gym / ruins style Stadium actions need to have a target
		m.player_bench = _basics(1, "bench")
		for k in ["Koga's", "Erika's", "Sabrina's"]:
			if named_basics.has(k):
				var nb := _mk(named_basics[k])
				nb.current_location = "bench"
				nb.placed_on_field_this_turn = false
				m.player_bench.append(nb)
				_attach(nb, _energy_for("Fire"))
		var hand_extra: Array = []
		for k in ["Omanyte", "Kabuto"]:
			if named_basics.has(k): hand_extra.append(named_basics[k])
		m.player_hand.append_array(_pile(hand_extra, "hand"))
		m.player_discard_pile = _rich_discard()
		m.player_hand.append_array(_pile([stage1_uid], "hand"))
	if o.has("all_type") or o.has("name_all"):
		var everyone: Array = [me, d]
		everyone.append_array(m.player_bench)
		everyone.append_array(m.opponent_bench)
		for pk in everyone:
			pk.metadata = pk.metadata.duplicate(true)
			if o.has("all_type"): pk.metadata["types"] = [o["all_type"]]
			if o.has("name_all"): pk.metadata["name"] = String(o["name_all"]) + " " + String(pk.metadata.get("name", ""))
		if o.has("all_type"): m.display_pokemon(false)



func _snap() -> Dictionary:
	var m = current_main
	var d = def_card
	var me = m.player_active_pokemon
	var bench_hp: Array = []
	for b in m.opponent_bench: bench_hp.append(b.current_hp)
	var own_bench_hp: Array = []
	for b in m.player_bench: own_bench_hp.append(b.current_hp)
	return {
		"def_hp": d.current_hp, "def_cond": d.special_condition, "def_pois": d.is_poisoned, "def_burn": d.is_burned,
		"def_energy": d.attached_energies.size(), "def_in_play": d == m.opponent_active_pokemon or d in m.opponent_bench,
		"foe_bench_hp": bench_hp, "foe_bench_n": m.opponent_bench.size(),
		"me_hp": me.current_hp if me != null else -1, "me_energy": me.attached_energies.size() if me != null else -1,
		"me_cond": me.special_condition if me != null else "", "me_uid": me.uid if me != null else "",
		"own_bench_hp": own_bench_hp, "own_bench_n": m.player_bench.size(),
		"my_hand": m.player_hand.size(), "my_deck": m.player_deck.size(), "my_disc": m.player_discard_pile.size(), "my_prize": m.player_prize_cards.size(),
		"foe_hand": m.opponent_hand.size(), "foe_deck": m.opponent_deck.size(), "foe_disc": m.opponent_discard_pile.size(), "foe_prize": m.opponent_prize_cards.size(),
		"foe_active_swapped": m.opponent_active_pokemon != d,
		"me_cards": _names(me.attached_cards) if me != null else [], "def_cards": _names(d.attached_cards),
		"me_cond_now": me.special_condition if me != null else "", "me_pois_now": me.is_poisoned if me != null else false, "me_energy_names": _names(me.attached_energies) if me != null else [], "def_energy_names": _names(d.attached_energies),
		"stadium": m.current_stadium_card.uid if m.current_stadium_card != null else "", "stadium_opp": m.current_stadium_owner_is_opponent,
		"me_maxhp": me.get_max_hp() if me != null else -1, "def_maxhp": d.get_max_hp(),
		"bench_maxhp": m.player_bench[0].get_max_hp() if not m.player_bench.is_empty() else -1,
		"foe_bench_maxhp": m.opponent_bench[0].get_max_hp() if not m.opponent_bench.is_empty() else -1,
		"me_retreat": m.get_retreat_cost(me) if me != null else -1,
		"my_disc_tail": _tail_names(m.player_discard_pile, 3), "foe_disc_tail": _tail_names(m.opponent_discard_pile, 3),
		"bench_cards": _names(m.player_bench[0].attached_cards) if not m.player_bench.is_empty() else [],
		"my_hand_names": _tail_names(m.player_hand, 2), "foe_hand_names": _tail_names(m.opponent_hand, 2),
	}


func attack_end() -> void:
	if not job.is_empty() and (job.get("kind") in ["attack", "cond"] or job.get("do_attack", false)) and job_post.is_empty() and is_instance_valid(current_main):
		job_post = _snap()
	super.attack_end()


func log_message(text: String, turn: int, opp_turn: bool) -> void:
	if not job.is_empty():
		job_msgs.append(text)
	super.log_message(text, turn, opp_turn)


func _exec(j: Dictionary, me: card_object) -> void:
	var m = current_main
	match j["kind"]:
		"attack", "cond":
			await m.perform_attack(int(j["index"]))
		"power":
			await m.powers_and_bodies.activate_power(me, j["ability"])
		"trainer":
			var tc: card_object = m.player_hand[m.player_hand.size() - 1]
			await m.trainer_effects.play_trainer_card(tc, false)
		"tool":
			await _exec_tool(j)
		"stadium":
			await _exec_stadium(j)
		"senergy":
			await _exec_senergy(j, me)
	job_finished = true


func _play_last(foe: bool) -> void:
	var m = current_main
	var hand: Array = m.opponent_hand if foe else m.player_hand
	var tc: card_object = hand[hand.size() - 1]
	var why: String = String(m.trainer_effects.validate_trainer_can_be_played(tc, foe))   # the UI refuses before play_trainer_card is reached
	if why != "":
		job_extra["refused"] = why
		return
	await m.trainer_effects.play_trainer_card(tc, foe)


func _hit() -> void:
	job["do_attack"] = true
	await current_main.perform_attack(0)


func _exec_tool(j: Dictionary) -> void:
	var sc: String = j["scen"]
	match sc:
		"play_me": await _play_last(false)
		"play_foe": await _play_last(true)
		"between_me2":
			await current_main.inbetween_turn_checks(true)
		"between_foe":
			await _play_last(true)
			await current_main.inbetween_turn_checks(true)
		"atk_tool":
			await _play_last(false)
			await _hit()
			var t0: int = current_main.turn_number
			var wf := 0
			while current_main.turn_number < t0 + 2 and wf < 1200 and is_instance_valid(current_main) and not current_main.game_is_over:
				await get_tree().process_frame
				wf += 1
			job_extra["waited_frames"] = wf
			job_extra["turn_before_after"] = [t0, current_main.turn_number]
			var mm = current_main.player_active_pokemon
			var holder = mm if mm != null else null
			job_extra["after_turn"] = {"me_cards": _names(holder.attached_cards) if holder != null else [], "my_disc_tail": _tail_names(current_main.player_discard_pile, 3)}
			for pk in current_main.player_bench:
				job_extra["after_turn"]["me_cards"] += _names(pk.attached_cards)
		"atk_tool_prize":
			await _play_last(false)
			await _hit()
		_:
			if sc.begins_with("atk_tool_type_"):
				await _play_last(false)
				await _hit()
			else:   # def_tool*, the foe plays it (the CPU attaches to its Active)
				await _play_last(true)
				await _hit()
				var fa = current_main.opponent_active_pokemon
				job_extra["after_turn"] = {"def_cards": _names(fa.attached_cards) if fa != null else [], "def_alive": fa == def_card}


func _exec_stadium(j: Dictionary) -> void:
	var m = current_main
	if String(j["scen"]).begins_with("stats"):
		await _play_last(false)
		job_extra["me_types"] = m.player_active_pokemon.get_effective_types()
		job_extra["me_name"] = m.player_active_pokemon.metadata.get("name", "")
		return
	match j["scen"]:
		"play", "replace_foe", "same_name", "play_bench5":
			await _play_last(false)
		"atk":
			await _hit()
		"stats":
			await _play_last(false)
			job_extra["me_types"] = m.player_active_pokemon.get_effective_types()
			job_extra["me_name"] = m.player_active_pokemon.metadata.get("name", "")
		"actions":
			var acts: Array = []
			var names: Array = []
			for a in m.powers_and_bodies.stadium_actions_for_player(): names.append(a)
			job_extra["action_names"] = names.map(func(a): return a.get("name", ""))
			for a in names:
				var rec := {"name": a.get("name", "")}
				for rnd in 2:
					var before := _snap()
					pbot.job_log.clear()
					var ok_before: bool = m.powers_and_bodies.stadium_actions_for_player().any(func(x): return x.get("name", "") == a.get("name", ""))
					rec["listed_before_%d" % (rnd + 1)] = ok_before
					if ok_before or rnd == 0:
						await m.powers_and_bodies.activate_power(null, a)
						for _f in 10: await get_tree().process_frame
					var after := _snap()
					var ch: Array = []
					for k in after:
						if str(after[k]) != str(before.get(k)): ch.append(k)
					rec["changed_%d" % (rnd + 1)] = ch
					rec["prompts_%d" % (rnd + 1)] = pbot.job_log.size()
				acts.append(rec)
			job_extra["acts"] = acts


func _exec_senergy(j: Dictionary, me: card_object) -> void:
	var m = current_main
	var sc: String = j["scen"]
	var e: card_object = null
	if sc in ["provides", "atk_alone", "atk_plus", "def_hit", "provides_ok", "atk_ok", "def_ok"] or sc.begins_with("atk_type_"):
		for x in me.attached_energies + def_card.attached_energies:
			if String(x.uid).to_lower() == String(j["uid"]).to_lower(): e = x; break
	match sc:
		"provides", "provides_ok":
			job_extra["provided"] = m.get_energy_provided_by_card(e)
			job_extra["attach_check"] = m.special_energy_effects.can_attach_to(e, me)
		"attach_hurt", "attach_ok":
			e = _mk(String(j["uid"]))
			var chk: Dictionary = m.special_energy_effects.can_attach_to(e, me)
			job_extra["attach_check"] = chk
			if chk.get("allowed", true):
				e.current_location = "attached"
				me.attached_energies.append(e)
				await m.special_energy_effects.apply_on_attach_effects(e, me, false)
				job_extra["provided"] = m.get_energy_provided_by_card(e)
		_:
			await _hit()


func _scenario(j: Dictionary) -> Dictionary:
	## -> {"uid": the board's active, "extra": hand cards (last = the card played), "opt": board options}
	var uid := String(j["uid"])
	var sc := String(j.get("scen", ""))
	match String(j["kind"]):
		"tool":
			var o := {"plain_me": true, "own_bench": 0}
			var extra: Array = []
			if sc == "play_me" or sc == "atk_tool" or sc == "atk_tool_prize" or sc == "between_me" or sc.begins_with("atk_tool_type_"):
				extra = [uid]
			else:
				o["foe_hand_add"] = [uid]
			if sc.begins_with("atk_tool_type_"): o["me_type"] = sc.trim_prefix("atk_tool_type_")
			if sc == "def_tool_ko": o["def_hp"] = 30
			if sc == "atk_tool_prize": o["foe_prize"] = 4
			if sc == "between_me2":
				o["me_cur_hp"] = 20; o["me_cond"] = "Asleep"; o["me_pois"] = true; o["me_tool"] = uid; o["own_bench"] = 2
			if sc == "between_foe": o["def_cur_hp"] = 20; o["def_cond"] = "Asleep"; o["def_pois"] = true
			if sc == "def_tool_dmg": o["def_dmg"] = 50
			if sc == "play_foe": o["own_bench"] = 2
			return {"uid": ATTACKER_UID, "extra": extra, "opt": o}
		"stadium":
			var o2 := {"plain_me": true}
			var extra2: Array = []
			var other := "basep-41" if uid != "basep-41" else "neo3-61"
			if sc == "stats" or sc.begins_with("stats_"): extra2 = [uid]
			match sc:
				"play": extra2 = [uid]
				"replace_foe": extra2 = [uid]; o2["stadium"] = other; o2["stadium_opp"] = true
				"same_name": extra2 = [uid]; o2["stadium"] = uid
				"actions": o2["stadium"] = uid; o2["rich_board"] = true; o2["me_evolved"] = true
				"play_bench5": extra2 = [uid]; o2["own_bench"] = 5; o2["foe_bench"] = 5
				"atk": o2["stadium"] = uid
			if sc.begins_with("stats_type_"): o2["all_type"] = sc.trim_prefix("stats_type_")
			if sc.begins_with("stats_name_"): o2["name_all"] = sc.trim_prefix("stats_name_")
			return {"uid": ATTACKER_UID, "extra": extra2, "opt": o2}
		"senergy":
			var o3 := {"plain_me": true}
			var F := _energy_for("Fighting")
			if sc == "provides": o3["me_energy_list"] = [uid]
			elif sc == "attach_hurt":
				o3["me_energy_list"] = []
				o3["me_dmg"] = 40; o3["me_cond"] = "Asleep"; o3["me_pois"] = true; o3["me_burn"] = true
			elif sc == "atk_alone": o3["me_energy_list"] = [uid]
			elif sc == "atk_plus": o3["me_energy_list"] = [uid, F, F]
			elif sc.begins_with("atk_type_"):
				o3["me_energy_list"] = [uid, F, F]; o3["me_type"] = sc.trim_prefix("atk_type_")
			elif sc == "def_hit":
				o3["me_energy_list"] = [F, F, F, F]; o3["def_energy_list"] = [uid]
			elif sc.ends_with("_ok"):   # the holder meets the card's own attach rule: Evolved, named, behind on Prizes, a basic of every type
				var allb: Array = [uid, _energy_for("Fire"), _energy_for("Water"), _energy_for("Grass"), _energy_for("Lightning"), _energy_for("Psychic"), F]
				o3["me_evolved"] = true; o3["foe_prize"] = 4
				var rl := String(cards[uid].get("rules", [""])[0]).to_lower() if cards.has(uid) else ""
				for nm in ["team aqua", "team magma", "dark", "rocket's"]:
					if (" ".join(cards[uid].get("rules", []))).to_lower().contains(nm + " in its name") or (" ".join(cards[uid].get("rules", []))).to_lower().contains(nm + " or"):
						o3["me_name"] = nm.capitalize() if nm != "rocket's" else "Rocket's"; break
				if sc == "provides_ok": o3["me_energy_list"] = allb
				elif sc == "atk_ok": o3["me_energy_list"] = allb
				elif sc == "attach_ok":
					o3["me_energy_list"] = [F]; o3["me_dmg"] = 40; o3["me_cond"] = "Asleep"; o3["me_pois"] = true
				elif sc == "def_ok":
					o3["me_energy_list"] = [F, F, F, F]; o3["def_energy_list"] = [uid]; o3["def_evolved"] = true
					if o3.has("me_name"): o3["def_name"] = o3["me_name"]
					o3.erase("me_evolved"); o3.erase("me_name")
			return {"uid": ATTACKER_UID, "extra": [], "opt": o3}
		"cond":
			return {"uid": uid, "extra": [], "opt": _variant_opts(sc)}
	return {"uid": uid if j["kind"] != "trainer" else basic_uid, "extra": [uid] if j["kind"] == "trainer" else [], "opt": {}}


func _variant_opts(v: String) -> Dictionary:
	var tool := inert_tool_uid
	match v:
		"def_ex": return {"def_ex": true}
		"def_evolved": return {"def_evolved": true}
		"def_stage2": return {"def_evolved": true, "def_stage": "Stage 2"}
		"def_damaged": return {"def_dmg": 50}
		"me_damaged": return {"me_dmg": 50}
		"my_prize1": return {"my_prize": 1}
		"foe_prize1": return {"foe_prize": 1}
		"def_asleep": return {"def_cond": "Asleep"}
		"def_confused": return {"def_cond": "Confused"}
		"def_paralyzed": return {"def_cond": "Paralyzed"}
		"def_poisoned": return {"def_pois": true}
		"def_burned": return {"def_burn": true}
		"own_bench0": return {"own_bench": 0}
		"own_bench5": return {"own_bench": 5}
		"foe_bench0": return {"foe_bench": 0}
		"foe_bench5": return {"foe_bench": 5}
		"my_disc_rich": return {"my_disc": "rich"}
		"my_disc_empty": return {"my_disc": "empty"}
		"foe_disc_rich": return {"foe_disc": "rich"}
		"def_energy3": return {"def_energy": 3}
		"hand8": return {"my_hand": 8}
		"hand0": return {"my_hand": 0}
		"foe_hand8": return {"foe_hand": 8}
		"foe_hand0": return {"foe_hand": 0}
		"me_tool": return {"me_tool": tool}
		"def_tool": return {"def_tool": tool}
		"me_energy6": return {"me_extra": 4}
	if v.begins_with("def_type_"): return {"def_type": v.trim_prefix("def_type_")}
	if v.begins_with("me_energy6_"): return {"me_extra": 4, "me_extra_type": v.trim_prefix("me_energy6_")}
	if v.begins_with("def_energy3_"): return {"def_energy": 3, "def_energy_type": v.trim_prefix("def_energy3_")}
	return {}


func _run_job(j: Dictionary) -> void:
	job = j
	job_post = {}
	job_msgs = []
	job_extra = {}
	job_finished = false
	pbot.job_log = []
	pbot.ready_for_job = false
	_logger.take_errors()
	var scn := _scenario(j)
	var extra: Array = scn["extra"]
	var me: card_object = _setup_board(scn["uid"], extra, scn["opt"])
	if j["kind"] == "trainer":
		me = current_main.player_active_pokemon
	var pre := _snap()
	_exec(j, me)   # not awaited: a hang is caught by the frame timeout
	var f := 0
	while not job_finished and f < JOB_TIMEOUT_FRAMES:
		await get_tree().process_frame
		f += 1
		if not is_instance_valid(current_main) or current_main.game_is_over:
			break
	var timed_out := not job_finished
	var post: Dictionary = job_post if not job_post.is_empty() else (_snap() if is_instance_valid(current_main) and not current_main.game_is_over else {})
	var errs: Array = []
	for e in _logger.take_errors():
		errs.append("%s:%s %s" % [String(e.get("file", "")).get_file(), e.get("line", ""), String(e.get("rationale", e.get("code", ""))).left(160)])
	var rec := {"uid": j["uid"], "kind": j["kind"], "name": j["name"], "pre": pre, "post": post, "timed_out": timed_out,
		"errors": errs, "prompts": pbot.job_log.duplicate(), "msgs": job_msgs.slice(0, 14), "frames": f}
	if j.has("scen"): rec["scen"] = j["scen"]
	if not job_extra.is_empty(): rec["extra"] = job_extra.duplicate(true)
	_append_abs(_abs(PROBE_OUT + "run_log.jsonl"), JSON.stringify(rec))
	job = {}
	if timed_out:
		print("PROBE: TIMEOUT %s %s %s" % [j["uid"], j["name"], j.get("scen", "")])
		_teardown_match()   # a hung effect leaves the scene unusable
		for _f in 3: await get_tree().process_frame
	else:
		# let the turn pass / settle before the next job
		for _f in 20: await get_tree().process_frame
