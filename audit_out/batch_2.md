# batch 2: ex6-4, ex12-19, ex10-12, ex10-19, ex11-45, ex12-21, ex14-24, ex4-26, ex8-3, ex9-53, ex10-61, ex10-68, ex10-v, ex11-86, ex12-33, ex12-17, ex12-24, ex12-6, ex13-15, ex14-14, ex14-48, ex14-8


=========== ex6-4 Ditto (Basic) score 14

--- attack:Energy Ball
TEXT: dmg=10+ cost=C | Does 10 damage plus 10 more damage for each Energy attached to Ditto but not used to pay for this attack's Energy cost. You can't add more then 20 damage in this way.
FLAG d_undispatched_uncovered: generic parser has no phrase for: you can't add more then 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [30] (text: Does 10 damage plus 10 more damage for each Energy attached to Ditto b)


=========== ex12-19 Lanturn (Stage 1) score 8

--- attack:Water Gun
TEXT: dmg=40+ cost=CCC | Does 40 damage plus 20 more damage for each Water Energy attached to Lanturn but not used to pay for this attack's Energy cost. You can't add more then 40 damage in this way.
FLAG d_undispatched_uncovered: generic parser has no phrase for: you can't add more then 40 damage in this way.

--- body:Dual Armor
TEXT: As long as Lanturn has any Water Energy attached to it, Lanturn is both Water and Lightning type.
FLAG d_body_unreferenced: Poke-Body name never referenced in battle scripts


=========== ex10-12 Porygon2 (Stage 1) score 7

--- attack:Scramble Trip
TEXT: dmg=40+ cost=CCC | If Porygon2 has a Scramble Energy card attached to it, this attack does 40 damage plus 20 more damage and the Defending Pokémon is now Confused.
FLAG run_status_missing: text says confused but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:27079  _attack_dispatch["scramble trip"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); var dmg=await execute_ex10_scramble_trip(a, d, opp, b, _ex5_more(atk)); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex10_scramble_trip(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, more: int) -> int:
	if await handle_attack_confusion(attacker, is_opponent): return 0
	if await handle_attack_blind(attacker, is_opponent): return 0
	var has_scramble = false
	for e in attacker.attached_energies:
		if e.metadata.get("name","") == "Scramble Energy": has_scramble = true
	var dmg = base_damage + (more if has_scramble else 0)
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return dmg
	if has_scramble and defender != null and defender.current_hp > 0 and not defender.is_invincible:
		main.card_ops.apply_status(defender, "Confused", not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW CONFUSED!")
		if main._should_bail(): return dmg
	await main.check_all_knockouts()
	return dmg

# Black Cry (Umbreon ex): base; the Defender can't retreat or use any Poke-Powers during the opponent's
# next turn.


=========== ex10-19 Vaporeon (Stage 1) score 7

--- attack:Multi Bubble
TEXT: dmg=40+ cost=CCC | If Vaporeon has 3 or more different types of basic Energy cards attached to it, this attack does 40 damage plus 20 more damage and the Defending Pokémon is now Asleep.
FLAG run_status_missing: text says asleep but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:27060  _attack_dispatch["multi bubble"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); var dmg=await execute_ex10_multi_type(a, d, opp, b, _ex5_more(atk), "Asleep"); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex10_multi_type(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, more: int, status: String) -> int:
	if await handle_attack_confusion(attacker, is_opponent): return 0
	if await handle_attack_blind(attacker, is_opponent): return 0
	var qualifies = _ex10_distinct_basic_types(attacker) >= 3
	var dmg = base_damage + (more if qualifies else 0)
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return dmg
	if qualifies and defender != null and defender.current_hp > 0 and not defender.is_invincible:
		main.card_ops.apply_status(defender, status, not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW " + status.to_upper() + "!")
		if main._should_bail(): return dmg
	await main.check_all_knockouts()
	return dmg

# Night Song (Murkrow): the opponent switches a Benched Pokemon with the Defender (they choose); the
# new Defending Pokemon is Asleep.


=========== ex11-45 Illumise (Basic) score 7

--- attack:Strange Rasping
TEXT: dmg=20 cost=GC | If the Defending Pokémon is an Evolved Pokémon, the Defending Pokémon is now Confused.
FLAG run_status_missing: text says confused but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:28588  _attack_dispatch["strange rasping"] = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex9_status_if_evolved(a, d, opp, b, "Confused"); await _attack_finish(b>0, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex9_status_if_evolved(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, status: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var st = defender.metadata.get("subtypes", []) if defender != null else []
	var is_evolved = "Stage 1" in st or "Stage 2" in st
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	if is_evolved and defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, status, not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW " + status.to_upper() + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()

# Tail Shock (ex9-7 Manectric): base to the Active, then `per` raw to each of the opponent's Benched Pokemon.


=========== ex12-21 Magmar (Basic) score 7

--- attack:Burning Sensation
TEXT: dmg=40 cost=FFF | If the Defending Pokémon already has any damage counters on it, the Defending Pokémon is now Burned.
FLAG run_status_missing: text says burned but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:29433  _attack_dispatch["burning sensation"] = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex4_status_if(a, d, opp, b, "has_counters", "Burned"); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex4_status_if(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, condition: String, status: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var cond := false
	match condition:
		"has_counters": cond = defender != null and defender.get_damage_counters() > 0
		"is_ex": cond = defender != null and main.is_ex_pokemon(defender)
		"name_aqua": cond = _ex4_name_has(defender, "Team Aqua")
		"name_magma": cond = _ex4_name_has(defender, "Team Magma")
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if cond and defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, status, not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW " + status.to_upper() + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# Deal base (+bonus if `condition` holds, evaluated BEFORE damage). Returns the damage dealt.


=========== ex14-24 Marshtomp (Stage 1) score 7

--- attack:Mud Splash
TEXT: dmg=30 cost=WCC | Does 30 damage to 1 of your opponent's Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_damage_mismatch: printed 30, dealt 0 (text: Does 30 damage to 1 of your opponent's Benched Pokémon. (Don't apply W)
HANDLER Attack_Effects.gd:268  _attack_dispatch["mud splash"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_mud_splash(a, d, opp, b);                                                 await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorles
HANDLER Attack_Effects.gd:30819  _attack_dispatch["mud splash"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:32450  _attack_dispatch["mud splash"] = func(atk, a, d, opp):


=========== ex4-26 Team Aqua's Corphish (Basic) score 7

--- attack:Dark Poison
TEXT: dmg=20 cost=DC | Discard a basic Energy card attached to Team Aqua's Corphish or this attack does nothing. The Defending Pokémon is now Poisoned.
FLAG run_damage_mismatch: printed 20, dealt 30 (text: Discard a basic Energy card attached to Team Aqua's Corphish or this a)
HANDLER Attack_Effects.gd:21502  _attack_dispatch["dark poison"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex4_dark_poison(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex4_dark_poison(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var basics = attacker.attached_energies.filter(func(e): return _ex2_is_basic_energy(e))
	if basics.is_empty():
		await main.show_message("NO BASIC ENERGY TO DISCARD — DARK POISON DID NOTHING!")
		if main._should_bail(): return
		return
	var dp_e = await r4_pick_own_energy(attacker, basics, is_opponent, "DARK POISON: DISCARD A BASIC ENERGY")   # OLD ISSUE 328
	if main._should_bail(): return
	main.card_ops.discard_energy_from_pokemon(dp_e, is_opponent)
	attacker.attached_energies.erase(dp_e)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, "Poisoned", not is_opponent)
		await main.show_message("DARK POISON! THE DEFENDING POKEMON IS NOW POISONED!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# Chaos Crush (ex4 Manectric): base damage; if the Defender was Confused, discard an Energy from it.


=========== ex8-3 Breloom (Stage 1) score 7

--- attack:Leaf Poison
TEXT: dmg=20 cost=C | If Breloom has any Grass Energy attached to it, the Defending Pokémon is now Poisoned.
FLAG run_status_missing: text says poisoned but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:25748  _attack_dispatch["leaf poison"]      = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex8_energy_conditional_status(a, d, opp, b, "Grass", 1, "Poisoned"); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:34153  _r4_wrap_if("leaf poison", func(t): return not t.contains("grass energy attached"), func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_ex8_energy_conditional_status(a, d, opp, b, "Grass", 0, "Poisoned"); return b)
[Attack_Effects.gd]
func _r4_wrap_if(name: String, pred: Callable, handler: Callable, self_finish: bool = false) -> void:
	var pv = _attack_dispatch.get(name)
	_attack_dispatch[name] = func(atk, a, d, opp):
		if pred.call(atk.get("text", "").to_lower()):
			if self_finish:
				await handler.call(atk, a, d, opp)
			else:
				var dmg = await handler.call(atk, a, d, opp)
				if main._should_bail(): return
				await _attack_finish(int(dmg) > 0, int(dmg), atk, a.metadata.get("types", ["Colorless"]), opp)
		elif pv != null:
			await pv.call(atk, a, d, opp)
		else:
			await execute_generic_copied_attack(atk, a, d, opp, true)



=========== ex9-53 Luvdisc (Basic) score 7

--- attack:Strange Scale
TEXT: dmg=20 cost=WC | If the Defending Pokémon is an Evolved Pokémon, the Defending Pokémon is now Confused.
FLAG run_status_missing: text says confused but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:26658  _attack_dispatch["strange scale"] = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex9_status_if_evolved(a, d, opp, b, "Confused"); await _attack_finish(b>0, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex9_status_if_evolved(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, status: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var st = defender.metadata.get("subtypes", []) if defender != null else []
	var is_evolved = "Stage 1" in st or "Stage 2" in st
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	if is_evolved and defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, status, not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW " + status.to_upper() + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()

# Tail Shock (ex9-7 Manectric): base to the Active, then `per` raw to each of the opponent's Benched Pokemon.


=========== ex10-61 Larvitar (Basic) score 5

--- attack:Retaliate
TEXT: dmg=10× cost=F | Does 10 damage times the number of damage counters on Larvitar.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the number of damage counters on Larvitar.)
HANDLER Attack_Effects.gd:18509  _attack_dispatch["retaliate"]          = func(atk, a, d, opp): var dmg = await execute_ex1_retaliate(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30802  _attack_dispatch["retaliate"] = func(atk, a, d, opp):


=========== ex10-68 Poliwhirl (Stage 1) score 5

--- attack:Energy Ball
TEXT: dmg=30+ cost=CC | Does 30 damage plus 10 more damage for each Energy attached to Poliwhirl but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [50] (text: Does 30 damage plus 10 more damage for each Energy attached to Poliwhi)


=========== ex10-v Unown (Basic) score 5

--- attack:Hidden Power
TEXT: dmg=20+ cost=PCC | Does 20 damage plus 10 more damage for each Basic Pokémon and each Evolution card in your discard pile. You can't add more than 60 damage in this way.
FLAG run_stated_damage_not_seen: text says 60 damage; observed hp changes [30] (text: Does 20 damage plus 10 more damage for each Basic Pokémon and each Evo)
HANDLER Attack_Effects.gd:10633  _attack_dispatch["hidden power"]    = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:27084  _attack_dispatch["hidden power"] = func(atk, a, d, opp):


=========== ex11-86 Taillow (Basic) score 5

--- attack:Skill Dive
TEXT: dmg= cost=C | Does 10 damage to 1 of your opponent's Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [30] (text: Does 10 damage to 1 of your opponent's Pokémon. (Don't apply Weakness )
HANDLER Attack_Effects.gd:24700  _attack_dispatch["skill dive"]         = func(atk, a, d, opp): await execute_ex3_choose_snipe(a, opp, 30, false); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:26618  _attack_dispatch["skill dive"] = func(atk, a, d, opp):


=========== ex12-33 Furret (Stage 1) score 5

--- attack:Do the Wave
TEXT: dmg=10+ cost=CCC | Does 10 damage plus 10 more for each of your Benched Pokémon.
FLAG b_wrap_no_match: name has handlers but none matches this text (falls to generic copy): Does 10 damage plus 10 more for each of your Benched Pokémon.
HANDLER Attack_Effects.gd:32873  _r3_wrap("do the wave", "times the number of pokémon you have in play", r3_do_the_wave)
[Attack_Effects.gd]
func _r3_wrap(name: String, needle: String, handler: Callable, self_finish: bool = false) -> void:
	var pv = _attack_dispatch.get(name)
	_attack_dispatch[name] = func(atk, a, d, opp):
		if needle in atk.get("text", "").to_lower():
			if self_finish:
				await handler.call(atk, a, d, opp)
			else:
				var dmg = await handler.call(atk, a, d, opp)
				if main._should_bail(): return
				await _attack_finish(int(dmg) > 0, int(dmg), atk, a.metadata.get("types", ["Colorless"]), opp)
		elif pv != null:
			await pv.call(atk, a, d, opp)
		else:
			await execute_generic_copied_attack(atk, a, d, opp, true)



=========== ex12-17 Gorebyss (Stage 1) score 5

--- attack:Hydro Pump
TEXT: dmg=30+ cost=WC | Does 30 damage plus 20 more damage for each Water Energy attached to Gorebyss but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [70] (text: Does 30 damage plus 20 more damage for each Water Energy attached to G)


=========== ex12-24 Pinsir (Basic) score 5

--- attack:Overhead Toss
TEXT: dmg=30 cost=GC | Does 20 damage to 1 of your Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [30] (text: Does 20 damage to 1 of your Benched Pokémon. (Don't apply Weakness and)
HANDLER Attack_Effects.gd:154  _attack_dispatch["overhead toss"]      = func(atk, a, d, opp): await execute_overhead_toss(a, d, opp, 40);   await _attack_finish(true,  40,  atk, a.metadata.get("types", ["Colorless"]), opp)
HANDLER Attack_Effects.gd:11552  _attack_dispatch["overhead toss"]         = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:29400  _attack_dispatch["overhead toss"] = func(atk, a, d, opp):


=========== ex12-6 Golem (Stage 2) score 5

--- attack:Enraged Linear Attack
TEXT: dmg= cost=FC | Choose 1 of your opponent's Pokémon. This attack does 10 damage for each damage counter on Golem to that Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Choose 1 of your opponent's Pokémon. This attack does 10 damage for ea)
HANDLER Attack_Effects.gd:29455  _attack_dispatch["enraged linear attack"] = func(atk, a, d, opp): await execute_ex12_enraged_linear(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex12_enraged_linear(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var dmg = 10 * attacker.get_damage_counters()
	var target = await _ex12_choose_opp_target(is_opponent, false, dmg)
	if main._should_bail(): return
	if target == null or dmg <= 0:
		await main.show_message("ENRAGED LINEAR ATTACK HAD NO EFFECT!")
		if main._should_bail(): return
		return
	await _ex3_hit_target(attacker, target, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()

# Entangling Vines (Tangela ex12-44): base; if the Defender is a Basic Pokemon, it can't attack next turn.


=========== ex13-15 Raichu δ (Stage 1) score 5

--- attack:Zzzap
TEXT: dmg= cost=C | Does 20 damage to each Pokémon that has any Poké-Powers or Poké-Bodies (both yours and your opponent's). Don't apply Weakness or Resistance.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [] (text: Does 20 damage to each Pokémon that has any Poké-Powers or Poké-Bodies)
HANDLER Attack_Effects.gd:9369  _attack_dispatch["zzzap"]              = func(atk, a, d, opp):


=========== ex14-14 Blastoise (Stage 2) score 5

--- attack:Hydro Pump
TEXT: dmg=50+ cost=WCC | Does 50 damage plus 20 more damage for each Water Energy attached to Blastoise but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [90] (text: Does 50 damage plus 20 more damage for each Water Energy attached to B)


=========== ex14-48 Charmander (Basic) score 5

--- attack:Retaliate
TEXT: dmg=10× cost=C | Does 10 damage times the number of damage counters on Charmander.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the number of damage counters on Charmander.)
HANDLER Attack_Effects.gd:18509  _attack_dispatch["retaliate"]          = func(atk, a, d, opp): var dmg = await execute_ex1_retaliate(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30802  _attack_dispatch["retaliate"] = func(atk, a, d, opp):


=========== ex14-8 Manectric (Stage 1) score 5

--- attack:Strong Current
TEXT: dmg=50 cost=LLC | If Manectric has a Pokémon Tool card attached to it, this attack does 20 damage to each of your opponent's Benched Pokémon-ex. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [50] (text: If Manectric has a Pokémon Tool card attached to it, this attack does )
HANDLER Attack_Effects.gd:30905  _attack_dispatch["strong current"] = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex14_strong_current(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex14_strong_current(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var has_tool = not attacker.attached_cards.filter(func(ac): return "Pokémon Tool" in ac.metadata.get("subtypes", [])).is_empty()
	if has_tool:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		for p in opp_bench:
			if main.is_ex_pokemon(p):
				await main.card_ops.apply_bench_damage(p, 20, not is_opponent)
				if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
		await main.show_message("STRONG CURRENT! 20 DAMAGE TO EACH BENCHED POKEMON-EX!")
		if main._should_bail(): return

# MINING (Mawile ex14-9): search your deck for a Trainer card → hand. If it is a Pokemon Tool, you may
# attach it to 1 of your Pokemon instead.
