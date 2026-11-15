extends Node
## CPU v2 (2026-11-14) SCENARIO TESTS: hand-built boards from the user's examples, checking what the CPU decides.
## Run (project folder, Git Bash):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path . res://Scenes/Autotest/CPU_Scenarios.tscn
## Prints PASS / FAIL per scenario and a summary line "SCENARIOS: n passed, m failed". The match scene is never
## opened: Main's script is loaded onto a bare Control (out of the tree, so _ready never runs) with its helper nodes,
## and only the CPU's synchronous scorers are called. Foresight is ON here unless --fair is passed (the game default is off).

const MAIN := "res://Scripts/Main_Match_Gameplay_Scripts/Main_Match_Core_Gameplay_Script.gd"
const HELPERS := {
	"attack_effects": "res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd",
	"trainer_effects": "res://Scripts/Main_Match_Gameplay_Scripts/Trainer_Effects.gd",
	"cpu_ai": "res://Scripts/Main_Match_Gameplay_Scripts/CPU_AI.gd",
	"powers_and_bodies": "res://Scripts/Main_Match_Gameplay_Scripts/Powers_And_Bodies_Effects.gd",
	"special_energy_effects": "res://Scripts/Main_Match_Gameplay_Scripts/Special_Energy_Effects.gd",
	"card_ops": "res://Scripts/Main_Match_Gameplay_Scripts/Card_Ops.gd",
	"match_effects": "res://Scripts/Main_Match_Gameplay_Scripts/Match_Effects.gd",
}
const CpuWeights = preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_Weights.gd")

var m
var ai
var passed := 0
var failed := 0
var fails: Array = []

func _ready() -> void:
	m = Control.new()
	m.set_script(load(MAIN))
	for k in HELPERS:
		var n = load(HELPERS[k]).new()
		m.add_child(n)
		n.main = m
		m.set(k, n)
	ai = m.cpu_ai
	CpuWeights.cheat_cards = 1.0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		if a == "--fair":
			CpuWeights.cheat_cards = 0.0   # the game's default: no foresight (scenarios marked [foresight] need it)
	for meth in get_method_list():
		var nm: String = meth["name"]
		if nm.begins_with("sc_") and (only == "" or only in nm):
			_reset()
			call(nm)
	print("SCENARIOS: ", passed, " passed, ", failed, " failed")
	for f in fails:
		print("  FAILED: ", f)
	get_tree().quit()

# ── board building ───────────────────────────────────────────────────────────────────────────────────────────────
func c(uid: String) -> card_object:
	var k := card_object.new(uid, m.get_card_metadata(uid))
	k.current_hp = k.get_max_hp()
	return k

func cards(uids: Array) -> Array:
	var out: Array = []
	for u in uids:
		out.append(c(u))
	return out

func _reset() -> void:
	m.turn_number = 7
	for side in ["player_", "opponent_"]:
		m.set(side + "active_pokemon", null)
		m.set(side + "bench", [])
		m.set(side + "hand", [])
		m.set(side + "deck", [])
		m.set(side + "discard_pile", [])
		m.set(side + "prize_cards", cards(["base1-97", "base1-97", "base1-97", "base1-97", "base1-97", "base1-97"]))
		m.set(side + "energy_played_this_turn", false)
		m.set(side + "retreated_this_turn", false)
	m.current_stadium_card = null
	m.trainer_effects.opponent_trainer_locked = false
	ai.cpu_trainer_phase = "early"
	ai.cpu_replacers_this_turn = 0
	ai.cpu_stale_turns = 0
	ai.cpu_undeveloped_draw = false
	ai._cpu_search_plan = {}
	ai._known_top = []
	ai.invalidate_cpu_evaluation()

## A Pokémon in play: energies by uid, damage taken.
func mon(uid: String, energies: Array = [], damage: int = 0) -> card_object:
	var p := c(uid)
	for e in energies:
		var ec := c(e)
		ec.current_location = "attached"
		p.attached_energies.append(ec)
	p.current_hp -= damage
	p.placed_on_field_this_turn = false
	return p

func cpu_active(p: card_object) -> card_object:
	p.current_location = "active"
	m.opponent_active_pokemon = p
	return p

func cpu_bench(p: card_object) -> card_object:
	p.current_location = "bench"
	m.opponent_bench.append(p)
	return p

func foe(p: card_object) -> card_object:
	p.current_location = "active"
	m.player_active_pokemon = p
	return p

func hand(uids: Array) -> Array:
	var h := cards(uids)
	for k in h:
		k.current_location = "hand"
	m.opponent_hand.append_array(h)
	return h

## Deck top first; padded with filler so draw cards are legal.
func deck(uids: Array, filler: String = "base1-97", pad: int = 25) -> Array:
	var d := cards(uids)
	for i in pad:
		d.append(c(filler))
	m.opponent_deck = d
	return d

func find(pile: Array, card_name: String) -> card_object:
	for k in pile:
		if k.metadata.get("name", "") == card_name:
			return k
	return null

## A check that only means something with foresight on (skipped under --fair).
func check_fs(label: String, ok: bool, detail: String = "") -> void:
	if CpuWeights.cheat_cards < 1.0:
		print("SKIP  ", label, "  [needs foresight]")
		return
	check(label, ok, detail)

func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label, ("  [" + detail + "]") if detail != "" else "")
	else:
		failed += 1
		fails.append(label + "  [" + detail + "]")
		print("FAIL  ", label, "  [", detail, "]")

## The CPU's attach choice: {"pokemon", "energy", "score"} over every hand Energy × field Pokémon.
func best_attach() -> Dictionary:
	ai.invalidate_cpu_evaluation()
	var ev: Dictionary = ai.get_cpu_evaluation()
	var best := {"score": -INF}
	for p in ai.get_all_cpu_field_pokemon():
		var pd: Dictionary = ev["pokemon_data"].get(p.get_instance_id(), {})
		for e in m.opponent_hand:
			if e.metadata.get("supertype", "") != "Energy":
				continue
			var s: float = ai.score_energy_pair(p, e, ev, pd)
			if s > float(best["score"]):
				best = {"pokemon": p, "energy": e, "score": s}
	return best

func cs_plan() -> Dictionary:
	var cs := find(m.opponent_hand, "Computer Search")
	var s: float = ai.cpu_score_trainer_for_play(cs)
	var plan: Dictionary = ai._cpu_search_plan
	return {"score": s, "card": plan.get("card"), "discards": plan.get("discards", []), "played": s > ai.CPU_TRAINER_PLAY_THRESHOLD}

func nm(k) -> String:
	return "none" if k == null else String(k.metadata.get("name", ""))

# ── the user's Computer Search examples ──────────────────────────────────────────────────────────────────────────
func sc_cs_two_energy_then_oak() -> void:
	cpu_active(mon("base1-46", ["base1-98"]))
	foe(mon("base1-52", ["base1-97"]))
	hand(["base1-71", "base1-98", "base1-102"])
	deck(["base1-99", "base1-91", "base1-88", "base1-99"])
	var r := cs_plan()
	check("CS + 2 Energy -> searches Professor Oak", r["played"] and nm(r["card"]) == "Professor Oak", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_wartortle_to_blastoise() -> void:
	cpu_active(mon("base1-42", ["base1-102", "base1-102", "base1-102", "base1-102"]))
	cpu_bench(mon("base1-63"))
	foe(mon("base1-56", ["base1-97"]))
	hand(["base1-71", "base1-102", "base1-102", "base1-102"])
	deck(["base1-91", "base1-88", "base1-2", "base1-63"])
	m.opponent_energy_played_this_turn = true
	var r := cs_plan()
	check("Wartortle with 4 Water -> searches Blastoise", r["played"] and nm(r["card"]) == "Blastoise", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_basic_for_stage1() -> void:
	cpu_active(mon("base1-63", ["base1-102"]))
	foe(mon("base1-61"))
	hand(["base1-71", "base1-30", "base1-99", "base1-99", "base1-99", "base1-102", "base1-102", "base1-102"])
	deck(["base1-91", "base1-44", "base1-88"])
	m.opponent_energy_played_this_turn = true   # (before the attach it waits - see sc_cs_waits_for_attach)
	var r := cs_plan()
	var kept: bool = not r["discards"].any(func(k): return k.metadata.get("name", "") == "Ivysaur")
	check("6 Energy + Ivysaur, no Bulbasaur -> searches Bulbasaur, keeps Ivysaur", r["played"] and nm(r["card"]) == "Bulbasaur" and kept, "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_status_evolution() -> void:
	var a := cpu_active(mon("base1-46", ["base1-98", "base1-98"]))
	a.special_condition = "Confused"
	a.is_poisoned = true
	cpu_bench(mon("base1-61"))
	foe(mon("base1-63", ["base1-102"]))
	hand(["base1-71", "base1-97", "base1-97", "base1-97"])
	deck(["base1-91", "base1-24", "base1-88"])
	m.opponent_energy_played_this_turn = true
	var r := cs_plan()
	check("Confused + Poisoned Charmander -> searches Charmeleon", r["played"] and nm(r["card"]) == "Charmeleon", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_dce_unlocks_ko() -> void:
	cpu_active(mon("base2-54"))
	cpu_bench(mon("base1-61"))
	foe(mon("base1-63", ["base1-102"], 20))
	hand(["base1-71", "base1-97", "base1-97", "base1-98"])
	deck(["base1-91", "base1-96", "base1-88"])
	var r := cs_plan()
	check("Jigglypuff with no Energy vs 20 HP foe -> searches DCE", r["played"] and nm(r["card"]) == "Double Colorless Energy", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_never_bill() -> void:
	cpu_active(mon("base1-46", ["base1-98"]))
	cpu_bench(mon("base1-61"))
	foe(mon("base1-52", ["base1-97"]))
	hand(["base1-71", "base1-98", "base1-61", "base1-94", "base1-84"])
	deck(["base1-91", "base1-91", "base1-99"])
	var r := cs_plan()
	check("Nothing needed -> Computer Search held, never Bill", not r["played"] and nm(r["card"]) != "Bill", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_pluspower_ko() -> void:
	cpu_active(mon("base1-46", ["base1-98", "base1-97"]))
	cpu_bench(mon("base1-61"))
	foe(mon("base1-52", ["base1-97"], 10))   # Machop 40 HP left, Ember does 30
	hand(["base1-71", "base1-97", "base1-97", "base1-97"])
	deck(["base1-91", "base1-84", "base1-88"])
	m.opponent_energy_played_this_turn = true
	var r := cs_plan()
	check("Ember 30 vs 40 HP -> searches PlusPower", r["played"] and nm(r["card"]) == "PlusPower", "score %d pick %s" % [r["score"], nm(r["card"])])

func sc_cs_charmeleon_to_charizard() -> void:
	cpu_active(mon("base1-24", ["base1-98", "base1-98", "base1-98", "base1-98"]))
	cpu_bench(mon("base1-61"))
	foe(mon("base1-63", ["base1-102"]))
	hand(["base1-71", "base1-97", "base1-97"])
	deck(["base1-91", "base1-4", "base1-88"])
	m.opponent_energy_played_this_turn = true   # the 4th Fire went on first; then the search
	var r := cs_plan()
	check("Charmeleon with 3 Fire -> searches Charizard", r["played"] and nm(r["card"]) == "Charizard", "score %d pick %s" % [r["score"], nm(r["card"])])

# ── Professor Oak discipline ─────────────────────────────────────────────────────────────────────────────────────
func sc_second_oak_held_with_potions() -> void:
	cpu_active(mon("base1-46", ["base1-98"]))
	cpu_bench(mon("base1-61"))
	foe(mon("base1-52", ["base1-97"]))
	hand(["base1-94", "base1-94", "base1-98", "base1-98", "base1-97", "base1-97", "base1-88"])
	deck(["base1-99"], "base1-99", 30)
	m.opponent_energy_played_this_turn = true
	ai.cpu_replacers_this_turn = 1
	ai.cpu_trainer_phase = "late"
	var s: float = ai.cpu_score_trainer_for_play(find(m.opponent_hand, "Professor Oak"))
	check("Second Oak with 2 Potions + 4 Energy -> held", s <= ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)

func sc_second_oak_dead_hand_ok() -> void:
	cpu_active(mon("base1-46", ["base1-98"]))
	for i in 5:
		cpu_bench(mon("base1-61"))
	foe(mon("base1-52", ["base1-97"]))
	hand(["base1-98", "base1-98", "base1-97", "base1-61", "base1-88"])
	deck(["base1-99"], "base1-99", 30)
	m.opponent_energy_played_this_turn = true
	ai.cpu_replacers_this_turn = 1
	ai.cpu_trainer_phase = "late"
	var s: float = ai.cpu_score_trainer_for_play(find(m.opponent_hand, "Professor Oak"))
	check("Second Oak into a dead hand (Energy used, bench full) -> played", s > ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)

func sc_oak_keeps_stage2_when_piece_coming() -> void:
	cpu_active(mon("base1-63", ["base1-102"]))
	foe(mon("base1-61"))
	hand(["base1-2", "base1-98", "base1-88"])
	deck(["base1-42", "base1-99"])
	m.opponent_energy_played_this_turn = true
	ai.cpu_trainer_phase = "late"
	var s: float = ai.cpu_score_trainer_card(find(m.opponent_hand, "Professor Oak"))
	check("Blastoise in hand, Wartortle is the next draw -> no Oak", s <= ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)

func sc_oak_dumps_stuck_stage2() -> void:
	cpu_active(mon("base1-63", ["base1-102"]))
	foe(mon("base1-61"))
	hand(["base1-2", "base1-98", "base1-88"])
	deck(["base1-99", "base1-99", "base1-99"])
	m.opponent_energy_played_this_turn = true
	ai.cpu_stale_turns = 2
	ai.cpu_trainer_phase = "late"
	var s: float = ai.cpu_score_trainer_card(find(m.opponent_hand, "Professor Oak"))
	check("Blastoise stuck (no Wartortle coming, hand stale) -> Oak allowed", s > ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)

func sc_oak_now_when_second_oak_coming() -> void:
	cpu_active(mon("base1-46", ["base1-98"]))
	foe(mon("base1-52"))
	hand(["base1-98", "base1-97", "base1-97", "base1-94", "base1-84", "base1-93", "base1-88"])
	deck(["base1-88", "base1-99"], "base1-99", 30)
	m.opponent_energy_played_this_turn = true
	ai.cpu_trainer_phase = "late"
	var with_next: float = ai.cpu_score_trainer_card(find(m.opponent_hand, "Professor Oak"))
	deck(["base1-99", "base1-99"], "base1-99", 30)
	var without: float = ai.cpu_score_trainer_card(find(m.opponent_hand, "Professor Oak"))
	check_fs("A second Oak is the next draw -> Oak now scores higher", with_next > without, "%d vs %d" % [with_next, without])

# ── Energy ──────────────────────────────────────────────────────────────────────────────────────────────────────────
func sc_rhyhorn_no_wasted_grass() -> void:
	cpu_active(mon("base2-61", ["base1-99", "base1-98"]))
	cpu_bench(mon("base2-59"))
	cpu_bench(mon("base1-46"))
	foe(mon("base1-61"))
	hand(["base1-99"])
	deck(["base1-97"])
	var b := best_attach()
	check("Rhyhorn (Grass+Fire, needs Fighting) -> Grass goes to the Bench", b["pokemon"] != m.opponent_active_pokemon, "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_rhyhorn_fighting_unlocks() -> void:
	cpu_active(mon("base2-61", ["base1-99", "base1-98"]))
	cpu_bench(mon("base2-59"))
	foe(mon("base1-61"))
	hand(["base1-99", "base1-97"])
	deck(["base1-97"])
	var b := best_attach()
	check("Rhyhorn + Fighting in hand -> Fighting to Rhyhorn", b["pokemon"] == m.opponent_active_pokemon and nm(b["energy"]) == "Fighting Energy", "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_rhyhorn_full_bench_gets_energy() -> void:
	cpu_active(mon("base2-61", ["base1-99", "base1-98", "base1-97"]))
	cpu_bench(mon("base2-61"))
	cpu_bench(mon("base1-46"))
	foe(mon("base1-61"))
	hand(["base1-97"])
	deck(["base1-99"])
	var b := best_attach()
	check("Fully powered Rhyhorn, spare Fighting -> Benched Pokémon", b["pokemon"] != m.opponent_active_pokemon, "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_energy_search_fetches_missing_type() -> void:
	cpu_active(mon("base2-61"))
	cpu_bench(mon("base2-59"))
	foe(mon("base1-61"))
	hand(["base1-99", "base3-59"])
	deck([])
	var f: float = ai.cpu_energy_fetch_value(c("base1-97"))
	var g: float = ai.cpu_energy_fetch_value(c("base1-99"))
	check("Rhyhorn + Paras, Grass in hand -> Fighting is the fetch", f > g, "fighting %d grass %d" % [f, g])

func sc_energy_retrieval_full_hand() -> void:
	cpu_active(mon("base2-4", ["base1-100"]))
	foe(mon("base1-61"))
	hand(["base1-81", "base1-100", "base1-100", "base1-100", "base1-102", "base1-102"])
	m.opponent_discard_pile = cards(["base1-100", "base1-100", "base1-102"])
	deck(["base1-99"])
	m.opponent_energy_played_this_turn = true
	var s: float = ai.cpu_score_trainer_card(find(m.opponent_hand, "Energy Retrieval"))
	check("Energy Retrieval into a hand of 5 Energy -> held", s <= ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)

# ── discards ────────────────────────────────────────────────────────────────────────────────────────────────────────
func sc_dce_kept_for_kangaskhan() -> void:
	cpu_active(mon("base1-52", ["base1-97"]))
	foe(mon("base1-61"))
	hand(["base1-96", "base1-97", "base1-97"])
	deck(["base2-5", "base1-99"])
	var v: float = m.trainer_effects._score_card_for_discard(find(m.opponent_hand, "Double Colorless Energy"))
	check("DCE with Kangaskhan still in the deck -> kept", v >= 60.0, "keep %d" % v)

func sc_dce_dumped_when_useless() -> void:
	cpu_active(mon("base1-52", ["base1-97"]))
	foe(mon("base1-61"))
	hand(["base1-96", "base1-97", "base1-97"])
	deck(["base1-97", "base1-97", "base1-97", "base1-97", "base1-97"])
	var v: float = m.trainer_effects._score_card_for_discard(find(m.opponent_hand, "Double Colorless Energy"))
	check("DCE that nothing can use -> first to go", v <= 20.0, "keep %d" % v)

func sc_bill_never_discarded() -> void:
	cpu_active(mon("base1-52", ["base1-97"]))
	foe(mon("base1-61"))
	hand(["base1-91", "base1-97", "base1-97", "base1-94"])
	deck(["base1-99"])
	var d: Array = m.trainer_effects.cpu_get_discard_priority(m.opponent_hand, 3)
	check("Bill is the last card discarded", not d.any(func(k): return k.metadata.get("name", "") == "Bill"), str(d.map(func(k): return k.metadata.get("name", ""))))

# ── Rainbow, lock pieces ────────────────────────────────────────────────────────────────────────────────────────────
func sc_rainbow_unlocks_active() -> void:
	cpu_active(mon("base1-46", ["base1-102"]))       # Charmander: Ember needs Fire + 1
	cpu_bench(mon("base1-44"))                        # Bulbasaur wants Grass
	foe(mon("base1-61"))
	hand(["base5-17", "base1-99"])
	deck(["base1-97"])
	var b := best_attach()
	check("Wrong basic in hand, Rainbow lets the Active attack -> Rainbow to Active", nm(b["energy"]) == "Rainbow Energy" and b["pokemon"] == m.opponent_active_pokemon, "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_rainbow_avoided_when_basic_fits() -> void:
	cpu_active(mon("base1-46"))
	foe(mon("base1-61"))
	hand(["base5-17", "base1-98"])
	deck(["base1-97"])
	var b := best_attach()
	check("Fire in hand fits -> Fire, not Rainbow", nm(b["energy"]) == "Fire Energy", "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_vileplume_after_trainers() -> void:
	cpu_active(mon("base5-36", ["base1-99"]))
	foe(mon("base1-61"))
	hand(["base5-13", "base1-91"])
	deck(["base1-97", "base1-97", "base1-97", "base1-97"])
	var vp := find(m.opponent_hand, "Dark Vileplume")
	var held: bool = ai.cpu_should_defer_lock(vp, [])
	m.opponent_hand.erase(find(m.opponent_hand, "Bill"))
	var free: bool = not ai.cpu_should_defer_lock(vp, [])
	check("Dark Vileplume waits while Bill is in hand, goes on once it isn't", held and free, "held %s free %s kind %s" % [held, free, ai.cpu_lock_kind(vp)])

func sc_aerodactyl_after_other_evolutions() -> void:
	var aero := c("base3-1")
	var other := {"evo_card": c("base1-24"), "score": 120.0}
	var held: bool = ai.cpu_should_defer_lock(aero, [{"evo_card": aero, "score": 100.0}, other])
	var free: bool = not ai.cpu_should_defer_lock(aero, [{"evo_card": aero, "score": 100.0}])
	check("Aerodactyl waits for the Charmeleon evolution, then goes on", held and free, "held %s free %s kind %s" % [held, free, ai.cpu_lock_kind(aero)])

func sc_rhyhorn_bench_before_deck_rhydon() -> void:
	cpu_active(mon("base2-61", ["base1-99", "base1-98", "base1-99", "base1-98", "base1-97", "base1-97"]))
	cpu_bench(mon("base2-61"))
	cpu_bench(mon("base2-41"))
	cpu_bench(mon("base1-46"))
	foe(mon("base1-65", ["base1-102"]))
	hand(["base1-97", "base1-84"])
	deck(["base1-99", "base1-91", "base2-45"])   # Rhydon somewhere in the deck
	var b := best_attach()
	check("Paid Rhyhorn, Rhydon only in the deck -> Fighting to the Bench", b["pokemon"] != m.opponent_active_pokemon, "%s -> %s (%d)" % [nm(b["energy"]), nm(b["pokemon"]), b["score"]])

func sc_no_energy_on_clefairy_doll() -> void:
	var doll := c("base1-70")
	doll.is_bench_token = true
	doll.current_hp = 10
	cpu_active(doll)
	foe(mon("base1-61"))
	hand(["base1-102"])
	deck(["base1-97"])
	var dead: bool = ai._cpu_energy_dead_target(doll, m.opponent_hand[0])
	check("Clefairy Doll is never an Energy target", dead, "dead %s" % dead)

func sc_cs_waits_for_attach() -> void:
	cpu_active(mon("base1-42", ["base1-102", "base1-102", "base1-102"]))
	cpu_bench(mon("base1-63"))
	foe(mon("base1-56", ["base1-97"]))
	hand(["base1-71", "base1-102", "base1-102", "base1-102"])
	deck(["base1-91", "base1-88", "base1-2", "base1-63"])
	ai.cpu_trainer_phase = "early"
	var s: float = ai.cpu_score_trainer_for_play(find(m.opponent_hand, "Computer Search"))
	check("CS + 3 Energy, Energy not attached yet -> waits for the attach", s <= ai.CPU_TRAINER_PLAY_THRESHOLD, "score %d" % s)
