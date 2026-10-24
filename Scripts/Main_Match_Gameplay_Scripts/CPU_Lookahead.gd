extends RefCounted
## ISSUE #375 — CPU LOOKAHEAD (phase 1).
##
## The CPU's priority code scores each option on its own, one move at a time. This module plays out the next EXCHANGE
## for an option — my move → the player's best reply → my next turn — and values the result in Prizes, using the same
## damage / threat helpers the CPU already trusts (no game-state cloning). Used by:
##   • attack choice   — set up a guaranteed KO next turn, avoid being KO'd back (Paralysis / Sleep / Confusion that stop
##                       the reply, recoil that leaves us in KO range), and who the player promotes after our KO;
##   • retreat         — stay vs each Benched Pokémon over the same exchange, minus the Energy the retreat costs.
## Everything is switchable (CpuWeights.on("rule.lookahead")) and scaled by tunables (look.*).

const CpuWeights = preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_Weights.gd")

var ai   # CPU_AI
var main # Main_Match_Core_Gameplay_Script


func _init(cpu_ai) -> void:
	ai = cpu_ai
	main = cpu_ai.main


# ───────────────────────── building blocks ─────────────────────────

## Best {min, exp, max} damage `attacker` can do to `defender` with attacks at most `extra` Energy short.
func dmg(attacker, defender, extra: int) -> Dictionary:
	var best := {"min": 0, "exp": 0, "max": 0}
	if attacker == null or defender == null:
		return best
	var types: Array = attacker.get_effective_types()
	for a in main.get_attacks_for_card(attacker):
		if ai.get_unmet_energy_count(a, attacker) > extra:
			continue
		var r: Dictionary = main.attack_effects.estimate_attack_damage_range(a, attacker, defender)
		for k in ["min", "exp", "max"]:
			var raw := int(r.get("expected" if k == "exp" else k, 0))
			var d := 0
			if raw > 0:
				d = int(main.calculate_final_damage(raw, types, defender, attacker).get("damage", raw))
			best[k] = maxi(int(best[k]), d)
	return best


## Rough chance a damage spread knocks out `hp`.
static func p_ko(d: Dictionary, hp: int) -> float:
	if hp <= 0:
		return 1.0
	if int(d.get("min", 0)) >= hp:
		return 1.0
	if int(d.get("exp", 0)) >= hp:
		return 0.65
	if int(d.get("max", 0)) >= hp:
		return 0.3
	return 0.0


## Chance the player attaches an Energy next turn (known exactly with card foresight).
func player_energy_next() -> float:
	var known: Array = main.player_hand.duplicate()
	if CpuWeights.cheating_cards():
		if not main.player_deck.is_empty():
			known.append(main.player_deck[0])
		return 1.0 if known.any(func(c): return c.metadata.get("supertype", "") == "Energy") else 0.0
	return CpuWeights.g("look.player_energy_chance", 0.75) if main.player_hand.size() >= 3 else 0.5


## ISSUE #375 FORESIGHT: the cards the player will hold at the start of their next turn (hand + normal turn-start draw).
## Empty without card foresight. Their coin flips and anything their own searches / shuffles bring are NOT known.
func player_known_next() -> Array:
	if not CpuWeights.cheating_cards():
		return []
	var known: Array = main.player_hand.duplicate()
	if not main.player_deck.is_empty():
		known.append(main.player_deck[0])
	return known


## Best {min, exp, max} for `form`'s attacks paid with `holder`'s Energy (an evolution card in hand uses the Energy
## already on the Pokémon it would evolve from).
func dmg_as(form, holder, defender, extra: int) -> Dictionary:
	var best := {"min": 0, "exp": 0, "max": 0}
	if form == null or holder == null or defender == null:
		return best
	var types: Array = form.metadata.get("types", ["Colorless"])
	for a in form.metadata.get("attacks", []):
		if ai.get_unmet_energy_count(a, holder) > extra:
			continue
		var r: Dictionary = main.attack_effects.estimate_attack_damage_range(a, holder, defender)
		for k in ["min", "exp", "max"]:
			var raw := int(r.get("expected" if k == "exp" else k, 0))
			var d := 0
			if raw > 0:
				d = int(main.calculate_final_damage(raw, types, defender, holder).get("damage", raw))
			best[k] = maxi(int(best[k]), d)
	return best


## Chance `foe` KOs `target` (with `target_hp` left) on its next turn. With card foresight this includes evolving
## `foe` with a card the player holds or is about to draw.
func reply_ko(foe, target, target_hp: int, p_energy: float) -> float:
	if foe == null or target == null:
		return 0.0
	var best := p_energy * p_ko(dmg(foe, target, 1), target_hp) + (1.0 - p_energy) * p_ko(dmg(foe, target, 0), target_hp)
	var fname: String = foe.metadata.get("name", "")
	for c in player_known_next():
		if c.metadata.get("evolvesFrom", "") == fname and c.metadata.get("supertype", "") == "Pokémon":
			var ev := p_energy * p_ko(dmg_as(c, foe, target, 1), target_hp) + (1.0 - p_energy) * p_ko(dmg_as(c, foe, target, 0), target_hp)
			best = maxf(best, ev)
	return best


## True when the player can have NO Pokémon left to promote after their Active is Knocked Out next turn: empty Bench and
## (known via card foresight) no Basic in hand or in their next draw to put down first.
func player_out_of_backups() -> bool:
	if not main.player_bench.is_empty():
		return false
	if not CpuWeights.cheating_cards():
		return false
	return not player_known_next().any(func(c): return main.is_basic_pokemon(c))


## The Benched Pokémon the player is most likely to promote against `target` (their best hitter).
func likely_promotion(target):
	var best = null
	var best_d := -1
	for b in main.player_bench:
		var d := int(dmg(b, target, 1).get("exp", 0))
		if d > best_d:
			best_d = d
			best = b
	return best


static func prizes_for(card, is_ex: bool) -> int:
	return 2 if is_ex else 1


## How likely an attack's Special Conditions stop the Defending Pokémon's NEXT attack.
func stop_chance(attack: Dictionary, me) -> float:
	var stop := 0.0
	var effects: Array = main.attack_effects.parse_card_text_effects(String(attack.get("text", "")), me.metadata.get("name", ""))
	for e in effects:
		if e.get("type", "") != "status" or e.get("target", "") != "defender":
			continue
		var flip := 0.5 if e.get("flip", "none") != "none" else 1.0
		match String(e.get("status", "")):
			"Paralyzed": stop = maxf(stop, 1.0 * flip)
			"Asleep": stop = maxf(stop, 0.5 * flip)
			"Confused": stop = maxf(stop, 0.5 * flip)
	return stop


# ───────────────────────── attack choice ─────────────────────────

## Lookahead value (score points) of using `attack` now: the next exchange's Prize swing beyond this turn.
func attack_value(attack: Dictionary, me, foe) -> float:
	if me == null or foe == null:
		return 0.0
	var pv := CpuWeights.g("look.prize", 200.0)
	var gamma := CpuWeights.g("look.future", 0.8)
	var types: Array = me.get_effective_types()
	var r: Dictionary = main.attack_effects.estimate_attack_damage_range(attack, me, foe)
	var d := {}
	for k in ["min", "exp", "max"]:
		var raw := int(r.get("expected" if k == "exp" else k, 0))
		d[k] = int(main.calculate_final_damage(raw, types, foe, me).get("damage", raw)) if raw > 0 else 0
	var pk := p_ko(d, foe.current_hp)
	var p_stop := stop_chance(attack, me)
	var tl := String(attack.get("text", "")).to_lower()
	# Recoil and our own status tick both come off our HP before their reply.
	var my_hp: int = me.current_hp - ai.status_damage_before_next_attack(me, true)
	if "damage to itself" in tl:
		my_hp -= main.attack_effects.extract_number_before(tl, " damage to itself")
	var pe := player_energy_next()
	# Branch A — they survive: their reply, then our follow-up on what is left of them.
	var foe_left: int = foe.current_hp - int(d["exp"]) - ai.status_damage_before_next_attack(foe, false)
	if "poison" in tl and not foe.is_poisoned:
		foe_left -= 10
	var die_a := (1.0 - p_stop) * reply_ko(foe, me, my_hp, pe)
	var my_extra := 1 if main.opponent_hand.any(func(c): return c.metadata.get("supertype", "") == "Energy") else 0
	var pk_next := p_ko(dmg(me, foe, my_extra), foe_left) if my_hp > 0 else 0.0
	# Branch B — we KO them: whoever they promote hits back.
	var die_b := 0.0
	if pk > 0.0:
		var promo = likely_promotion(me)
		if promo != null:
			die_b = reply_ko(promo, me, my_hp, pe)
	var foe_prizes := prizes_for(foe, main.is_ex_pokemon(foe))
	var my_prizes := prizes_for(me, main.is_ex_pokemon(me))
	if my_hp <= 0:
		die_a = 1.0
		die_b = 1.0
	# ISSUE #375 FORESIGHT: no Bench and nothing to bench next turn — Knocking Out their Active next turn wins the game.
	if player_out_of_backups():
		gamma *= CpuWeights.g("look.win_next", 4.0)
	# ISSUE #460: the Prize taken NOW counts too. Without it a KO-now attack scored 0 here while a
	# chip attack that only sets up next turn's KO scored pk_next * pv * gamma (+160) -- so "KO
	# later" outranked "KO now" and the CPU passed up guaranteed Knock Outs.
	var v := pk * foe_prizes * pv \
		+ (1.0 - pk) * (1.0 - die_a) * pk_next * foe_prizes * pv * gamma \
		- ((1.0 - pk) * die_a + pk * die_b) * my_prizes * pv
	return v * CpuWeights.g("look.attack", 1.0)


# ───────────────────────── retreat ─────────────────────────

## Value of `cand` being our Active for the coming exchange (it attacks this turn, then takes their reply).
func active_value(cand, foe, is_current: bool) -> float:
	var can_attach: bool = not main.opponent_energy_played_this_turn and main.opponent_hand.any(func(c): return c.metadata.get("supertype", "") == "Energy")
	return exchange(cand, foe, is_current, 1 if can_attach else 0)


## The exchange `cand` (as our Active, able to add `extra` Energy first) has against `foe`: Prizes we take minus Prizes
## we give up, in score points.
func exchange(cand, foe, is_current: bool, extra: int) -> float:
	if cand == null or foe == null:
		return 0.0
	var pv := CpuWeights.g("look.prize", 200.0)
	var dnow := dmg(cand, foe, extra)
	var pk := p_ko(dnow, foe.current_hp)
	var hp: int = cand.current_hp - (ai.status_damage_before_next_attack(cand, true) if is_current else 0)
	if is_current and cand.special_condition in ["Paralyzed", "Asleep"]:
		pk = 0.0
	elif is_current and cand.special_condition == "Confused":
		pk *= 0.5
	var pe := player_energy_next()
	var die := (1.0 - pk) * reply_ko(foe, cand, hp, pe)
	if pk > 0.0:
		var promo = likely_promotion(cand)
		if promo != null:
			die += pk * reply_ko(promo, cand, hp, pe)
	var foe_prizes := prizes_for(foe, main.is_ex_pokemon(foe))
	var my_prizes := prizes_for(cand, main.is_ex_pokemon(cand))
	return pk * foe_prizes * pv - die * my_prizes * pv


## {"delta": best Bench value − retreat cost − staying value, "best": that Benched Pokémon}.
func retreat_choice() -> Dictionary:
	var me = main.opponent_active_pokemon
	var foe = main.player_active_pokemon
	if me == null or foe == null or main.opponent_bench.is_empty():
		return {"delta": 0.0, "best": null}
	var stay := active_value(me, foe, true)
	var cost := float(main.get_retreat_cost(me)) * CpuWeights.g("look.energy", 25.0)
	var best = null
	var best_v := -INF
	for b in main.opponent_bench:
		var v := active_value(b, foe, false)
		if v > best_v:
			best_v = v
			best = b
	return {"delta": best_v - cost - stay, "best": best, "stay": stay}


# ───────────────────────── phase 2: Energy, Gust, healing ─────────────────────────

func _attach_left() -> int:
	return 1 if (not main.opponent_energy_played_this_turn and main.opponent_hand.any(func(c): return c.metadata.get("supertype", "") == "Energy")) else 0


## What attaching `energy` to `pokemon` does to the next exchange. On the Active: the exchange with vs without it. On a
## Benched Pokémon: how much readier it is to take over, weighted by the chance the Active falls this exchange.
func energy_value(pokemon, energy) -> float:
	var me = main.opponent_active_pokemon
	var foe = main.player_active_pokemon
	if me == null or foe == null or pokemon == null or energy == null:
		return 0.0
	var w := CpuWeights.g("look.energy_attach", 1.0)
	if w == 0.0:
		return 0.0
	if pokemon == me:
		var before := exchange(me, foe, true, 0)
		pokemon.attached_energies.append(energy)
		var after := exchange(me, foe, true, 0)
		pokemon.attached_energies.erase(energy)
		return (after - before) * w
	var tick: int = ai.status_damage_before_next_attack(me, true)
	var p_fall := reply_ko(foe, me, me.current_hp - tick, player_energy_next())
	if p_fall <= 0.0:
		return 0.0
	var b_before := exchange(pokemon, foe, false, 1)
	pokemon.attached_energies.append(energy)
	var b_after := exchange(pokemon, foe, false, 1)
	pokemon.attached_energies.erase(energy)
	return p_fall * (b_after - b_before) * CpuWeights.g("look.future", 0.8) * w


## Best Gust target by the exchange our Active would have against it, vs the current Defending Pokémon.
## {"v": gain in score points, "target": Pokémon or null}
func gust_value() -> Dictionary:
	var me = main.opponent_active_pokemon
	var foe = main.player_active_pokemon
	if me == null or foe == null or main.player_bench.is_empty():
		return {"v": 0.0, "target": null}
	var extra := _attach_left()
	var now := exchange(me, foe, true, extra)
	var best = null
	var best_v := -INF
	for t in main.player_bench:
		var v := exchange(me, t, true, extra)
		if v > best_v:
			best_v = v
			best = t
	return {"v": best_v - now, "target": best}


## How much a heal of `amount` on our Active improves its chance of surviving their reply (score points).
func heal_value(amount: int) -> float:
	var me = main.opponent_active_pokemon
	var foe = main.player_active_pokemon
	if me == null or foe == null or amount <= 0:
		return 0.0
	var pe := player_energy_next()
	var hp: int = me.current_hp - ai.status_damage_before_next_attack(me, true)
	var healed: int = mini(me.get_max_hp(), me.current_hp + amount) - ai.status_damage_before_next_attack(me, true)
	var gain := reply_ko(foe, me, hp, pe) - reply_ko(foe, me, healed, pe)
	return gain * prizes_for(me, main.is_ex_pokemon(me)) * CpuWeights.g("look.prize", 200.0)
