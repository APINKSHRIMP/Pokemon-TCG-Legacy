extends RefCounted
## ISSUE #375 — CPU MULTI-TURN PLANNER (lookahead phase 3).
##
## A fast abstract model of the match (Pokémon, HP, attached Energy types, status, hands, decks, Prizes) that whole turns
## are applied to, searched N turns deep: CPU turn → player's best reply → CPU turn → … The plan's FIRST turn steers the
## real CPU's choices (Energy target, retreat / stay, Gust target, attack); the existing card logic carries them out.
##
## Knowledge — two CPUs, one switch (CpuWeights.cheat_cards):
##   FAIR    : knows its own deck CONTENTS (not order, not which are Prizes), its hand, the board, the player's public
##             cards. Its future draws are averaged over several shuffles of its unseen cards; the player's hand is
##             unknown apart from the chance they can attach an Energy.
##   CHEATER : knows both decks' order (next draws), both sides' Prize cards and the player's hand — it plays out what the
##             player CAN do with the cards they really have.
## Coin results are never assumed (expected values), unless the separate coin dial is on.
##
## Modelled: draw, evolve, bench, Energy attach, retreat, attack (damage incl. coin maths, Weakness/Resistance, PlusPower,
## Defender, status, recoil, bench damage), KOs + Prizes + promotion, poison/burn/sleep/paralysis, and the common
## Base–Gym Trainers. Unmodelled cards are simply not played in the model.

const CpuWeights = preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_Weights.gd")

var ai
var main
var _atk_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var nodes := 0
var last_ms := 0.0


func _init(cpu_ai) -> void:
	ai = cpu_ai
	main = cpu_ai.main


# ═════════════════════════ model construction ═════════════════════════

func _energy_types(card) -> Array:
	return main.get_energy_provided_by_card(card)


func _mon_from(card) -> Dictionary:
	var types: Array = []
	for e in card.attached_energies:
		types.append_array(_energy_types(e))
	var st := ""
	if card.special_condition in ["Paralyzed", "Asleep", "Confused"]:
		st = card.special_condition
	return {"card": card, "meta": card.metadata, "hp": card.current_hp, "max": card.get_max_hp(),
		"energy": types, "status": st, "poison": (card.poison_damage if card.is_poisoned else 0) + (10 if card.is_burned else 0),
		"defender": 20 * int(card.defender_count), "plus": 10 * int(card.pluspower_count), "new": bool(card.placed_on_field_this_turn),
		"ex": bool(main.is_ex_pokemon(card))}


func _mon_from_hand(card) -> Dictionary:
	return {"card": card, "meta": card.metadata, "hp": int(card.metadata.get("hp", "0")) if str(card.metadata.get("hp", "0")).is_valid_int() else 50,
		"max": int(card.metadata.get("hp", "0")) if str(card.metadata.get("hp", "0")).is_valid_int() else 50,
		"energy": [], "status": "", "poison": 0, "defender": 0, "plus": 0, "new": true, "ex": bool(main.is_ex_pokemon(card))}


## The current real board as a model state. `cpu_side_draws` / `op_draws`: ordered future draws (known or sampled).
func snapshot(cheater: bool) -> Dictionary:
	var me := {"active": _mon_from(main.opponent_active_pokemon) if main.opponent_active_pokemon != null else null,
		"bench": main.opponent_bench.map(func(c): return _mon_from(c)),
		"hand": main.opponent_hand.duplicate(), "draws": [], "prizes": main.opponent_prize_cards.size(),
		"prize_cards": main.opponent_prize_cards.duplicate() if cheater else [], "taken": 0,
		"energy_left": not main.opponent_energy_played_this_turn, "unknown_hand": 0, "p_energy": 1.0}
	var op := {"active": _mon_from(main.player_active_pokemon) if main.player_active_pokemon != null else null,
		"bench": main.player_bench.map(func(c): return _mon_from(c)),
		"hand": main.player_hand.duplicate() if cheater else [], "draws": [], "prizes": main.player_prize_cards.size(),
		"prize_cards": [], "taken": 0, "energy_left": true, "unknown_hand": 0 if cheater else main.player_hand.size(),
		"p_energy": 1.0}
	if cheater:
		me["draws"] = main.opponent_deck.slice(0, 6)
		op["draws"] = main.player_deck.slice(0, 6)
	else:
		# Fair: the CPU's unseen cards (deck + face-down Prizes) in a random order; the player's draws are unknown.
		var pool: Array = main.opponent_deck.duplicate()
		pool.append_array(main.opponent_prize_cards)
		_shuffle(pool)
		me["draws"] = pool.slice(0, 6)
		op["p_energy"] = CpuWeights.g("look.player_energy_chance", 0.75) if main.player_hand.size() >= 3 else 0.5
	return {"me": me, "op": op, "winner": "", "turn_index": 0}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _copy_side(s: Dictionary) -> Dictionary:
	var c := s.duplicate()
	c["active"] = s["active"].duplicate() if s["active"] != null else null
	if c["active"] != null:
		c["active"]["energy"] = s["active"]["energy"].duplicate()
	var b: Array = []
	for m in s["bench"]:
		var mm: Dictionary = m.duplicate()
		mm["energy"] = m["energy"].duplicate()
		b.append(mm)
	c["bench"] = b
	c["hand"] = s["hand"].duplicate()
	c["draws"] = s["draws"].duplicate()
	return c


static func copy_state(st: Dictionary) -> Dictionary:
	return {"me": _copy_side(st["me"]), "op": _copy_side(st["op"]), "winner": st["winner"], "turn_index": st["turn_index"]}


# ═════════════════════════ rules model ═════════════════════════

static func _name(m: Dictionary) -> String:
	return m["meta"].get("name", "")


func can_pay(energy: Array, attack: Dictionary) -> bool:
	return unmet(energy, attack) == 0


func unmet(energy: Array, attack: Dictionary) -> int:
	var pool: Array = energy.duplicate()
	var short := 0
	var colorless := 0
	for req in attack.get("cost", []):
		if req == "Colorless":
			colorless += 1
			continue
		var i := pool.find(req)
		if i == -1:
			i = pool.find("Any")
		if i == -1:
			short += 1
		else:
			pool.remove_at(i)
	return short + maxi(0, colorless - pool.size())


## Cached text analysis of an attack: base damage, coin maths, per-Energy bonus, recoil, bench damage, status.
func _atk_info(attack: Dictionary, attacker_name: String) -> Dictionary:
	var key := attacker_name + "|" + String(attack.get("name", "")) + "|" + String(attack.get("text", ""))
	if _atk_cache.has(key):
		return _atk_cache[key]
	var tl := String(attack.get("text", "")).to_lower()
	var base: int = main.attack_effects.parse_attack_base_damage(attack)
	var dstr := String(attack.get("damage", ""))
	var info := {"base": base, "mode": "fixed", "coins": 0, "per": 0, "recoil": 0, "bench": 0, "status": "", "status_flip": false,
		"per_energy": 0, "discard_energy": 0}
	var n: int = main.attack_effects.parse_coin_flip_count(tl)
	if "×" in dstr or "x" in dstr:
		if "until you get tails" in tl:
			info["mode"] = "until_tails"
		elif n > 0:
			info["mode"] = "coins_x"
			info["coins"] = n
		elif "flip a coin" in tl:
			info["mode"] = "coins_x"
			info["coins"] = 1
	elif "+" in dstr:
		if "flip a coin" in tl and "more damage" in tl:
			info["mode"] = "coin_plus"
			info["per"] = main.attack_effects.extract_number_before(tl, " more damage")
		elif "for each" in tl and "energy" in tl:
			info["mode"] = "per_energy"
			info["per"] = main.attack_effects.extract_number_before(tl, " more damage")
	if "if tails, this attack does nothing" in tl:
		info["mode"] = "coin_or_nothing"
	if "damage to itself" in tl:
		info["recoil"] = main.attack_effects.extract_number_before(tl, " damage to itself")
	if "benched" in tl and ("each" in tl or "all" in tl) and "damage to each of your opponent" in tl:
		info["bench"] = main.attack_effects.extract_number_before(tl, " damage to each")
	for e in main.attack_effects.parse_card_text_effects(String(attack.get("text", "")), attacker_name):
		if e.get("type", "") == "status" and e.get("target", "") == "defender":
			info["status"] = e.get("status", "")
			info["status_flip"] = e.get("flip", "none") != "none"
	if "discard" in tl and "energy" in tl and "attached to " + attacker_name.to_lower() in tl:
		info["discard_energy"] = 1 if not "all" in tl else 9
	_atk_cache[key] = info
	return info


## Expected damage `att` does to `dfn` with `attack` (after Weakness / Resistance / PlusPower / Defender).
func expected_damage(att: Dictionary, attack: Dictionary, dfn: Dictionary) -> float:
	var info := _atk_info(attack, _name(att))
	var d := float(info["base"])
	match String(info["mode"]):
		"coins_x": d = float(info["base"]) * float(info["coins"]) * 0.5
		"until_tails": d = float(info["base"])
		"coin_plus": d = float(info["base"]) + 0.5 * float(info["per"])
		"coin_or_nothing": d = 0.5 * float(info["base"])
		"per_energy":
			var extra := maxi(0, att["energy"].size() - attack.get("cost", []).size())
			d = float(info["base"]) + float(info["per"]) * extra
	if d <= 0.0:
		return 0.0
	d += float(att.get("plus", 0))
	var atypes: Array = att["meta"].get("types", ["Colorless"])
	for w in dfn["meta"].get("weaknesses", []):
		if w.get("type", "") in atypes:
			var v := String(w.get("value", "×2"))
			d = d * 2.0 if ("×" in v or "x" in v or v == "") else d + float(v.trim_prefix("+"))
	for r in dfn["meta"].get("resistances", []):
		if r.get("type", "") in atypes:
			d += float(String(r.get("value", "-30")))
	d -= float(dfn.get("defender", 0))
	if att.get("status", "") == "Confused":
		d *= 0.5
	return maxf(0.0, d)


func usable_attacks(m: Dictionary) -> Array:
	if m == null or m.get("status", "") in ["Paralyzed"]:
		return []
	var out: Array = []
	for a in m["meta"].get("attacks", []):
		if can_pay(m["energy"], a):
			out.append(a)
	return out


## Apply `attack` by side `s_key`'s Active to the other side's Active (expected values).
func apply_attack(st: Dictionary, s_key: String, attack: Dictionary) -> void:
	var o_key := "op" if s_key == "me" else "me"
	var s: Dictionary = st[s_key]
	var o: Dictionary = st[o_key]
	var att = s["active"]
	var dfn = o["active"]
	if att == null or dfn == null:
		return
	var info := _atk_info(attack, _name(att))
	var mult := 0.5 if att.get("status", "") == "Asleep" else 1.0
	var dmg := expected_damage(att, attack, dfn) * mult
	dfn["hp"] = float(dfn["hp"]) - dmg
	if att.get("status", "") == "Confused":
		att["hp"] = float(att["hp"]) - 10.0
	if int(info["recoil"]) > 0:
		att["hp"] = float(att["hp"]) - float(info["recoil"]) * mult
	if int(info["bench"]) > 0:
		for b in o["bench"]:
			b["hp"] = float(b["hp"]) - float(info["bench"]) * mult
	if String(info["status"]) != "" and dfn["hp"] > 0:
		if not bool(info["status_flip"]) or _rng.randf() < 0.5:
			match String(info["status"]):
				"Poisoned": dfn["poison"] = maxi(int(dfn["poison"]), 10)
				"Burned": dfn["poison"] = int(dfn["poison"]) + 10
				_: dfn["status"] = String(info["status"])
	for i in int(info["discard_energy"]):
		if not att["energy"].is_empty():
			att["energy"].pop_back()
	att["plus"] = 0
	_resolve_kos(st)


func _promote(side: Dictionary) -> void:
	if side["bench"].is_empty():
		side["active"] = null
		return
	var best := 0
	var best_v := -INF
	for i in side["bench"].size():
		var b: Dictionary = side["bench"][i]
		var v: float = float(b["hp"]) + (60.0 if not usable_attacks(b).is_empty() else 0.0) + 10.0 * b["energy"].size()
		if v > best_v:
			best_v = v
			best = i
	side["active"] = side["bench"][best]
	side["bench"].remove_at(best)


func _resolve_kos(st: Dictionary) -> void:
	for pair in [["me", "op"], ["op", "me"]]:
		var s: Dictionary = st[pair[0]]
		var o: Dictionary = st[pair[1]]
		var ko_list: Array = []
		if s["active"] != null and float(s["active"]["hp"]) <= 0.0:
			ko_list.append(s["active"])
			s["active"] = null
		for b in s["bench"].duplicate():
			if float(b["hp"]) <= 0.0:
				ko_list.append(b)
				s["bench"].erase(b)
		for k in ko_list:
			o["taken"] = int(o["taken"]) + (2 if k["ex"] else 1)
		if s["active"] == null:
			_promote(s)
	for pair in [["me", "op"], ["op", "me"]]:
		var s2: Dictionary = st[pair[0]]
		var o2: Dictionary = st[pair[1]]
		if int(s2["taken"]) >= int(s2["prizes"]) and int(s2["prizes"]) > 0:
			st["winner"] = pair[0]
		elif o2["active"] == null and st["winner"] == "":
			st["winner"] = pair[0]


func _between_turns(st: Dictionary, s_key: String) -> void:
	# After side s_key's turn: its opponent's Paralysis from before wears off; poison/burn tick on both Actives.
	for k in ["me", "op"]:
		var a = st[k]["active"]
		if a == null:
			continue
		if int(a["poison"]) > 0:
			a["hp"] = float(a["hp"]) - float(a["poison"])
		if k == s_key and a.get("status", "") == "Paralyzed":
			a["status"] = ""
		if a.get("status", "") == "Asleep" and _rng.randf() < 0.5:
			a["status"] = ""
		a["defender"] = 0 if k != s_key else a["defender"]
	_resolve_kos(st)


# ═════════════════════════ a side's turn ═════════════════════════

func _draw(side: Dictionary) -> void:
	if not side["draws"].is_empty():
		side["hand"].append(side["draws"].pop_front())
	elif int(side["unknown_hand"]) >= 0:
		side["unknown_hand"] = int(side["unknown_hand"]) + 1


func _has_energy(side: Dictionary) -> bool:
	if side["hand"].any(func(c): return c.metadata.get("supertype", "") == "Energy"):
		return true
	if int(side.get("fetched_energy", 0)) > 0:
		return true
	return int(side["unknown_hand"]) > 0 and _rng.randf() < float(side["p_energy"])


func _take_energy(side: Dictionary) -> Array:
	for c in side["hand"]:
		if c.metadata.get("supertype", "") == "Energy":
			side["hand"].erase(c)
			return _energy_types(c)
	if int(side.get("fetched_energy", 0)) > 0:
		side["fetched_energy"] = int(side["fetched_energy"]) - 1
	elif int(side["unknown_hand"]) > 0:
		side["unknown_hand"] = int(side["unknown_hand"]) - 1
	# Unknown hand: an Energy of a type the Active needs.
	var a = side["active"]
	if a != null:
		for atk in a["meta"].get("attacks", []):
			for req in atk.get("cost", []):
				if req != "Colorless":
					return [req]
	return ["Colorless"]


func _prelude(st: Dictionary, s_key: String) -> void:
	var side: Dictionary = st[s_key]
	var hand: Array = side["hand"]
	# Draw-power Trainers first (Bill; Professor Oak with a thin hand).
	for c in hand.duplicate():
		var nm: String = c.metadata.get("name", "")
		if nm == "Bill":
			hand.erase(c)
			_draw(side)
			_draw(side)
	if hand.size() <= 3:
		for c in hand.duplicate():
			if c.metadata.get("name", "") == "Professor Oak":
				hand.clear()
				for i in 7:
					_draw(side)
				break
	# Evolve everything that can evolve (not a Pokémon put down this turn).
	var mons: Array = ([side["active"]] if side["active"] != null else []) + side["bench"]
	for c in hand.duplicate():
		var from: String = c.metadata.get("evolvesFrom", "")
		if from == "" or c.metadata.get("supertype", "") != "Pokémon":
			continue
		for m in mons:
			if _name(m) == from and not m["new"]:
				var dmg_taken: float = float(m["max"]) - float(m["hp"])
				m["card"] = c
				m["meta"] = c.metadata
				var mx := int(c.metadata.get("hp", "0")) if str(c.metadata.get("hp", "0")).is_valid_int() else int(m["max"])
				m["max"] = mx
				m["hp"] = float(mx) - dmg_taken
				m["status"] = ""
				m["new"] = true
				hand.erase(c)
				break
	# Bench Basics up to four.
	for c in hand.duplicate():
		if side["bench"].size() >= 4:
			break
		if c.metadata.get("supertype", "") == "Pokémon" and main.is_basic_pokemon(c):
			side["bench"].append(_mon_from_hand(c))
			hand.erase(c)
	# Heal / Energy fetch Trainers when they matter.
	var act = side["active"]
	for c in hand.duplicate():
		var nm2: String = c.metadata.get("name", "")
		if act != null and nm2 == "Potion" and float(act["max"]) - float(act["hp"]) >= 20.0:
			act["hp"] = minf(float(act["max"]), float(act["hp"]) + 20.0)
			hand.erase(c)
		elif act != null and nm2 == "Super Potion" and float(act["max"]) - float(act["hp"]) >= 40.0 and not act["energy"].is_empty():
			act["hp"] = minf(float(act["max"]), float(act["hp"]) + 40.0)
			act["energy"].pop_back()
			hand.erase(c)
		elif nm2 in ["Energy Search", "Energy Retrieval"] and not hand.any(func(x): return x.metadata.get("supertype", "") == "Energy"):
			hand.erase(c)
			side["fetched_energy"] = int(side.get("fetched_energy", 0)) + 1
		elif act != null and nm2 == "Full Heal" and act.get("status", "") != "":
			act["status"] = ""
			hand.erase(c)


## Every candidate way this side could play its turn: [{"desc": {...}, "state": result}]. The side's own greedy plays
## (draw, evolve, bench, heal) happen first; the branch is over Energy target × retreat × Gust × attack.
func gen_turns(st: Dictionary, s_key: String, wide: bool) -> Array:
	var o_key := "op" if s_key == "me" else "me"
	var base := copy_state(st)
	var side: Dictionary = base[s_key]
	_draw(side)
	for m in ([side["active"]] if side["active"] != null else []) + side["bench"]:
		m["new"] = false
	_prelude(base, s_key)
	if side["active"] == null:
		return [{"desc": {}, "state": base}]
	# Energy options: none, the Active, the Bench Pokémon closest to attacking.
	var e_opts: Array = [null]
	var has_e := _has_energy(side)
	if has_e:
		e_opts.append(-1)
		var bench_order: Array = range(side["bench"].size())
		bench_order.sort_custom(func(a, b): return _short(side["bench"][a]) < _short(side["bench"][b]))
		for i in bench_order.slice(0, 2 if wide else 1):
			e_opts.append(i)
	# Retreat options: stay, or the best Bench Pokémon (if the cost can be paid and the Active isn't stuck).
	var r_opts: Array = [null]
	var act: Dictionary = side["active"]
	var cost := int(act["meta"].get("convertedRetreatCost", act["meta"].get("retreatCost", []).size()))
	var has_switch: bool = side["hand"].any(func(c): return c.metadata.get("name", "") == "Switch")
	if not side["bench"].is_empty() and not (act.get("status", "") in ["Paralyzed", "Asleep"]) and (act["energy"].size() >= cost or has_switch):
		var best_b := -1
		var best_v := -INF
		for i in side["bench"].size():
			var v := _mon_strength(side["bench"][i], base[o_key]["active"])
			if v > best_v:
				best_v = v
				best_b = i
		r_opts.append(best_b)
	# Gust options: none, or each Benched target (wide) / the weakest one.
	var g_opts: Array = [null]
	var gust_card = null
	for c in side["hand"]:
		if c.metadata.get("name", "") in ["Gust of Wind"]:
			gust_card = c
			break
	if gust_card != null and not base[o_key]["bench"].is_empty():
		var tgt_order: Array = range(base[o_key]["bench"].size())
		tgt_order.sort_custom(func(a, b): return float(base[o_key]["bench"][a]["hp"]) < float(base[o_key]["bench"][b]["hp"]))
		for i in tgt_order.slice(0, 2 if wide else 1):
			g_opts.append(i)
	var out: Array = []
	for e in e_opts:
		for r in r_opts:
			for g in g_opts:
				var s2 := copy_state(base)
				var sd: Dictionary = s2[s_key]
				var od: Dictionary = s2[o_key]
				var desc := {"energy": e, "retreat": r, "gust": g, "attack": "", "energy_card": null, "retreat_card": null, "gust_card": null}
				if e != null:
					var types := _take_energy(sd)
					var tgt = sd["active"] if e == -1 else sd["bench"][e]
					tgt["energy"].append_array(types)
					desc["energy_card"] = tgt["card"]
				if r != null:
					var a2: Dictionary = sd["active"]
					if sd["hand"].any(func(c): return c.metadata.get("name", "") == "Switch"):
						for c in sd["hand"]:
							if c.metadata.get("name", "") == "Switch":
								sd["hand"].erase(c)
								break
					else:
						for i in cost:
							if not a2["energy"].is_empty():
								a2["energy"].pop_back()
					a2["status"] = ""
					var nb: Dictionary = sd["bench"][r]
					desc["retreat_card"] = nb["card"]
					sd["bench"].remove_at(r)
					sd["bench"].append(a2)
					sd["active"] = nb
				if g != null:
					for c in sd["hand"]:
						if c.metadata.get("name", "") == "Gust of Wind":
							sd["hand"].erase(c)
							break
					var oa = od["active"]
					var nt: Dictionary = od["bench"][g]
					desc["gust_card"] = nt["card"]
					od["bench"].remove_at(g)
					od["bench"].append(oa)
					od["active"] = nt
				# PlusPower if it turns the attack into a KO; Defender on the Active if the reply can hit.
				var atks := usable_attacks(sd["active"])
				if atks.is_empty():
					_end_turn(s2, s_key, sd)
					out.append({"desc": desc, "state": s2})
					continue
				for atk in atks:
					var s3 := copy_state(s2)
					var sd3: Dictionary = s3[s_key]
					_maybe_pluspower(s3, s_key, atk)
					apply_attack(s3, s_key, atk)
					_end_turn(s3, s_key, sd3)
					var d2: Dictionary = desc.duplicate()
					d2["attack"] = atk.get("name", "")
					out.append({"desc": d2, "state": s3})
	return out


func _maybe_pluspower(st: Dictionary, s_key: String, atk: Dictionary) -> void:
	var o_key := "op" if s_key == "me" else "me"
	var sd: Dictionary = st[s_key]
	var od: Dictionary = st[o_key]
	if sd["active"] == null or od["active"] == null:
		return
	var d := expected_damage(sd["active"], atk, od["active"])
	var need := float(od["active"]["hp"]) - d
	if need <= 0.0:
		return
	for c in sd["hand"].duplicate():
		if c.metadata.get("name", "") == "PlusPower" and need > 0.0:
			sd["active"]["plus"] = int(sd["active"].get("plus", 0)) + 10
			sd["hand"].erase(c)
			need -= 10.0


func _end_turn(st: Dictionary, s_key: String, sd: Dictionary) -> void:
	# Defender before passing the turn, if their Active can hit ours.
	if sd["active"] != null:
		for c in sd["hand"].duplicate():
			if c.metadata.get("name", "") == "Defender":
				sd["active"]["defender"] = 20
				sd["hand"].erase(c)
				break
	_between_turns(st, s_key)
	st["turn_index"] = int(st["turn_index"]) + 1


func _short(m: Dictionary) -> int:
	var best := 9
	for a in m["meta"].get("attacks", []):
		best = mini(best, unmet(m["energy"], a))
	return best


func _mon_strength(m: Dictionary, foe) -> float:
	if m == null:
		return -200.0
	var v := float(m["hp"]) * 0.3
	var best_d := 0.0
	var ready := false
	for a in m["meta"].get("attacks", []):
		if can_pay(m["energy"], a):
			ready = true
			if foe != null:
				best_d = maxf(best_d, expected_damage(m, a, foe))
	v += 40.0 if ready else -12.0 * float(_short(m))
	if foe != null and float(foe["hp"]) > 0.0:
		v += 60.0 * minf(1.0, best_d / float(foe["hp"]))
	return v


# ═════════════════════════ evaluation + search ═════════════════════════

## Static value of a model state for the CPU (higher = better).
func evaluate(st: Dictionary) -> float:
	if st["winner"] == "me":
		return 100000.0
	if st["winner"] == "op":
		return -100000.0
	var me: Dictionary = st["me"]
	var op: Dictionary = st["op"]
	var pv := CpuWeights.g("plan.prize", 150.0)
	var v := pv * (float(me["taken"]) - float(op["taken"]))
	# Closer to winning counts more: the last Prizes are worth extra.
	v += 40.0 * (float(me["taken"]) / maxf(1.0, float(me["prizes"])) - float(op["taken"]) / maxf(1.0, float(op["prizes"])))
	v += _side_value(me, op["active"]) - _side_value(op, me["active"])
	return v


func _side_value(s: Dictionary, foe) -> float:
	if s["active"] == null:
		return -300.0
	var v := _mon_strength(s["active"], foe)
	v += 20.0 * float(s["active"]["energy"].size()) * 0.5
	for b in s["bench"]:
		v += 12.0 + 0.4 * _mon_strength(b, foe) + 4.0 * float(b["energy"].size())
	v += 2.0 * float(mini(8, s["hand"].size() + int(s["unknown_hand"])))
	return v


func _search(st: Dictionary, ply: int, max_ply: int, beams: Array) -> float:
	nodes += 1
	if st["winner"] != "" or ply >= max_ply:
		return evaluate(st)
	var s_key := "me" if ply % 2 == 0 else "op"
	var cands := gen_turns(st, s_key, ply < 2)
	if cands.is_empty():
		return evaluate(st)
	# Order by the static value from the mover's point of view, keep the beam.
	for c in cands:
		c["v"] = evaluate(c["state"])
	if s_key == "me":
		cands.sort_custom(func(a, b): return a["v"] > b["v"])
	else:
		cands.sort_custom(func(a, b): return a["v"] < b["v"])
	var beam := int(beams[mini(ply, beams.size() - 1)])
	var best := -INF if s_key == "me" else INF
	for c in cands.slice(0, beam):
		var v := _search(c["state"], ply + 1, max_ply, beams)
		best = maxf(best, v) if s_key == "me" else minf(best, v)
	return best


## The CPU's best plan for THIS turn, looking `turns` full turns ahead (CPU + player each = 1 turn).
## Returns {"energy": target card_object | "none" | null, "retreat": card_object | "stay" | null,
##          "gust": card_object | null, "attack": name, "value": v, "ms": time}
func plan(turns: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	nodes = 0
	var cheater: bool = CpuWeights.cheating_cards()
	var samples := 1 if cheater else int(CpuWeights.g("plan.samples", 3.0))
	var max_ply := turns * 2
	var beams: Array = [int(CpuWeights.g("plan.beam_root", 6.0)), 3, 2, 2, 1]
	var totals := {}
	var descs := {}
	for s in samples:
		_rng.seed = int(main.turn_number) * 7919 + s * 104729 + 17
		var root := snapshot(cheater)
		var cands := gen_turns_root(root)
		for c in cands:
			c["v"] = evaluate(c["state"])
		cands.sort_custom(func(a, b): return a["v"] > b["v"])
		for c in cands.slice(0, int(beams[0])):
			var key := str(c["desc"])
			var v := _search(c["state"], 1, max_ply, beams)
			totals[key] = float(totals.get(key, 0.0)) + v
			descs[key] = c["desc"]
	var best_key := ""
	var best_v := -INF
	for k in totals:
		if float(totals[k]) > best_v:
			best_v = float(totals[k])
			best_key = k
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if best_key == "":
		return {}
	var d: Dictionary = descs[best_key]
	var opts: Array = []
	for k in totals:
		opts.append({"desc": descs[k], "value": float(totals[k]) / float(samples)})
	return {"desc": d, "value": best_v / float(samples), "ms": last_ms, "nodes": nodes, "options": totals.size(), "opts": opts}


## Best forecast value among the plan's options whose description satisfies `pred` (-INF if none).
static func best_where(pl: Dictionary, pred: Callable) -> float:
	var best := -INF
	for o in pl.get("opts", []):
		if pred.call(o["desc"]):
			best = maxf(best, float(o["value"]))
	return best


## Root turn: identical to gen_turns but without the turn-start draw (the CPU has drawn already).
func gen_turns_root(root: Dictionary) -> Array:
	var side: Dictionary = root["me"]
	var saved: Array = side["draws"]
	side["draws"] = []
	var keep_unknown := int(side["unknown_hand"])
	side["unknown_hand"] = -1   # _draw does nothing
	var out := gen_turns(root, "me", true)
	for c in out:
		c["state"]["me"]["draws"] = saved.duplicate()
		c["state"]["me"]["unknown_hand"] = keep_unknown
	return out
