# batch 3: ex15-60, ex16-20, ex16-43, ex1-99, ex2-19, ex2-50, ex2-7, ex2-74, ex3-65, ex3-92, ex4-95, ex5-101, ex5-17, ex5-33, ex6-26, ex6-7, ex8-107, ex8-44, ex8-8, ex9-15, ex10-13, ex10-41


=========== ex15-60 Ralts (Basic) score 5

--- attack:Psychic Boom
TEXT: dmg=10× cost=P | Does 10 damage times the amount of Energy attached to the Defending Pokémon.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the amount of Energy attached to the Defending Po)
HANDLER Attack_Effects.gd:19267  _attack_dispatch["psychic boom"]       = func(atk, a, d, opp): var dmg = await execute_ex2_psychic_boom(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:20236  _attack_dispatch["psychic boom"] = func(atk, a, d, opp):


=========== ex16-20 Omastar (Stage 2) score 5

--- attack:Hydrocannon
TEXT: dmg=30+ cost=CC | Does 30 damage plus 20 more damage for each Water Energy attached to Omastar but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [70] (text: Does 30 damage plus 20 more damage for each Water Energy attached to O)


=========== ex16-43 Bagon (Basic) score 5

--- attack:Retaliate
TEXT: dmg=10× cost=C | Does 10 damage times the number of damage counters on Bagon.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the number of damage counters on Bagon.)
HANDLER Attack_Effects.gd:18509  _attack_dispatch["retaliate"]          = func(atk, a, d, opp): var dmg = await execute_ex1_retaliate(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30802  _attack_dispatch["retaliate"] = func(atk, a, d, opp):


=========== ex1-99 Lapras ex (Basic/ex) score 5

--- attack:Energy Ball
TEXT: dmg=10+ cost=W | Does 10 damage plus 10 more damage for each Energy attached to Lapras ex but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [30] (text: Does 10 damage plus 10 more damage for each Energy attached to Lapras )


=========== ex2-19 Omastar (Stage 2) score 5

--- attack:Hydrocannon
TEXT: dmg=30+ cost=CC | Does 30 damage plus 20 more damage for each Water Energy attached to Omastar but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [70] (text: Does 30 damage plus 20 more damage for each Water Energy attached to O)


=========== ex2-50 Pelipper (Stage 1) score 5

--- attack:Water Gun
TEXT: dmg=30+ cost=CC | This attack does 30 damage plus 10 more damage for each Water Energy attached to Pelipper but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [50] (text: This attack does 30 damage plus 10 more damage for each Water Energy a)


=========== ex2-7 Ludicolo (Stage 2) score 5

--- attack:Hydro Punch
TEXT: dmg=50+ cost=WCC | Does 50 damage plus 10 more damage for each Water Energy attached to Ludicolo but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [70] (text: Does 50 damage plus 10 more damage for each Water Energy attached to L)


=========== ex2-74 Ralts (Basic) score 5

--- attack:Psychic Boom
TEXT: dmg=10× cost=P | Does 10 damage times the amount of Energy attached to the Defending Pokémon.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the amount of Energy attached to the Defending Po)
HANDLER Attack_Effects.gd:19267  _attack_dispatch["psychic boom"]       = func(atk, a, d, opp): var dmg = await execute_ex2_psychic_boom(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:20236  _attack_dispatch["psychic boom"] = func(atk, a, d, opp):


=========== ex3-65 Mudkip (Basic) score 5

--- attack:Water Gun
TEXT: dmg=10+ cost=C | Does 10 damage plus 10 more damage for each Water Energy attached to Mudkip but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [30] (text: Does 10 damage plus 10 more damage for each Water Energy attached to M)


=========== ex3-92 Kingdra ex (Stage 2/ex) score 5

--- attack:Hydrocannon
TEXT: dmg=50+ cost=CCC | Does 50 damage plus 20 more damage for each Water Energy attached to Kingdra ex but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [90] (text: Does 50 damage plus 20 more damage for each Water Energy attached to K)


=========== ex4-95 Swampert ex (Stage 2/ex) score 5

--- attack:Hyper Pump
TEXT: dmg=20+ cost=C | Does 20 damage plus 20 more damage for each basic Energy attached to Swampert ex but not used to pay for this attack's Energy cost. You can't add more than 80 damage in this way.
FLAG run_stated_damage_not_seen: text says 80 damage; observed hp changes [100] (text: Does 20 damage plus 20 more damage for each basic Energy attached to S)


=========== ex5-101 Wigglytuff ex (Stage 1/ex) score 5

--- attack:Do the Wave
TEXT: dmg=30+ cost=CCC | Does 30 damage plus 10 more damage for each of your Benched Pokémon.
FLAG b_wrap_no_match: name has handlers but none matches this text (falls to generic copy): Does 30 damage plus 10 more damage for each of your Benched Pokémon.
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



=========== ex5-17 Chimecho (Basic) score 5

--- attack:Psychic Boom
TEXT: dmg=10× cost=P | Does 10 damage times the amount of Energy attached to the Defending Pokémon.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the amount of Energy attached to the Defending Po)
HANDLER Attack_Effects.gd:19267  _attack_dispatch["psychic boom"]       = func(atk, a, d, opp): var dmg = await execute_ex2_psychic_boom(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:20236  _attack_dispatch["psychic boom"] = func(atk, a, d, opp):


=========== ex5-33 Dodrio (Stage 1) score 5

--- attack:Retaliate
TEXT: dmg=10× cost=CC | Does 10 damage times the number of damage counters on Dodrio.
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the number of damage counters on Dodrio.)
HANDLER Attack_Effects.gd:18509  _attack_dispatch["retaliate"]          = func(atk, a, d, opp): var dmg = await execute_ex1_retaliate(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30802  _attack_dispatch["retaliate"] = func(atk, a, d, opp):


=========== ex6-26 Kingler (Stage 1) score 5

--- attack:Hyper Pump
TEXT: dmg=30+ cost=WC | Does 30 damage plus 20 more damage for each basic Energy attached to Kingler but not used to pay for this attack's Energy cost. You can't add more than 40 damage in this way.
FLAG run_stated_damage_not_seen: text says 40 damage; observed hp changes [70] (text: Does 30 damage plus 20 more damage for each basic Energy attached to K)


=========== ex6-7 Marowak (Stage 1) score 5

--- attack:Vengeance
TEXT: dmg=30+ cost=FCC | Does 30 damage plus 10 more damage for each Basic Pokémon and each Evolution card in your discard pile. You can't add more than 60 damage in this way.
FLAG run_stated_damage_not_seen: text says 60 damage; observed hp changes [40] (text: Does 30 damage plus 10 more damage for each Basic Pokémon and each Evo)
HANDLER Attack_Effects.gd:23809  _attack_dispatch["vengeance"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); var dmg=await execute_ex6_vengeance(a, d, opp, b); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex6_vengeance(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> int:
	if await handle_attack_confusion(attacker, is_opponent): return 0
	if await handle_attack_blind(attacker, is_opponent): return 0
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var count = 0
	for c in discard:
		if c.metadata.get("supertype","") != "Pokémon": continue
		var st = c.metadata.get("subtypes", [])
		if "Basic" in st or "Stage 1" in st or "Stage 2" in st:
			count += 1
	var bonus = min(60, 10 * count)
	var dmg = base_damage + bonus
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return dmg
	await main.check_all_knockouts()
	return dmg

# POWER LARIAT (ex6 Nidoqueen): base + `per` for each Evolved Pokemon you have in play.


=========== ex8-107 Rayquaza ★ (Basic/Star) score 5

--- attack:Holy Star
TEXT: dmg= cost=FFLL | Discard all Energy cards attached to Rayquaza Star. This attack does 100 damage to each of your opponent's Pokémon-ex. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_stated_damage_not_seen: text says 100 damage; observed hp changes [] (text: Discard all Energy cards attached to Rayquaza Star. This attack does 1)
HANDLER Attack_Effects.gd:25815  _attack_dispatch["holy star"]        = func(atk, a, d, opp): await execute_ex8_holy_star(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex8_holy_star(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	for e in attacker.attached_energies.duplicate():
		main.card_ops.discard_energy_from_pokemon(e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	for p in main.card_ops.get_all_pokemon_in_play(not is_opponent):
		if main.is_ex_pokemon(p):
			if p == opp_active:
				await gym1_hit_active(attacker, p, is_opponent, 100)
			else:
				await main.card_ops.apply_bench_damage(p, 100, not is_opponent)
			if main._should_bail(): return
	await main.show_message("HOLY STAR! 100 DAMAGE TO EACH OF THE OPPONENT'S POKEMON-EX!")
	if main._should_bail(): return
	await main.check_all_knockouts()

# THUNDEROUS BLOW (ex8-108 Rocket's Raikou ex): base + `per` for each Energy of `energy_type` on self.


=========== ex8-44 Plusle (Basic) score 5

--- attack:Positive Spark
TEXT: dmg= cost=L | Does 20 damage to each of your opponent's Pokémon that has any Poké-Powers. Don't apply Weakness and Resistance.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [] (text: Does 20 damage to each of your opponent's Pokémon that has any Poké-Po)
HANDLER Attack_Effects.gd:25781  _attack_dispatch["positive spark"]   = func(atk, a, d, opp): await execute_ex8_spark_ability(a, opp, 20, "Poké-Power"); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex8_spark_ability(attacker: card_object, is_opponent: bool, dmg: int, ability_type: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var hit_any = false
	for p in main.card_ops.get_all_pokemon_in_play(not is_opponent):
		if _ex8_has_ability_type(p, ability_type):
			await gym1_hit_raw(p, dmg, not is_opponent)
			hit_any = true
	main.display_pokemon(not is_opponent)
	if hit_any:
		await main.show_message("HIT EACH POKEMON WITH A " + ability_type.to_upper() + " FOR " + str(dmg) + "!")
	else:
		await main.show_message("NO TARGET POKEMON HAD A " + ability_type.to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()

# REFLECTED BEAM (ex8-47 Solrock): choose 1 of the opponent's Benched Pokemon; 10 per Lunatone you have in play.


=========== ex8-8 Gyarados (Stage 1) score 5

--- attack:Full Retaliation
TEXT: dmg=20× cost=CC | Does 20 damage times the number of damage counters on all of your Magikarp.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [] (text: Does 20 damage times the number of damage counters on all of your Magi)
HANDLER Attack_Effects.gd:25768  _attack_dispatch["full retaliation"] = func(atk, a, d, opp): var dmg=await execute_ex8_full_retaliation(a, d, opp); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex8_full_retaliation(attacker: card_object, defender: card_object, is_opponent: bool) -> int:
	if await handle_attack_confusion(attacker, is_opponent): return 0
	if await handle_attack_blind(attacker, is_opponent): return 0
	var counters = 0
	for p in main.card_ops.get_all_pokemon_in_play(is_opponent):
		if p.metadata.get("name","") == "Magikarp":
			counters += p.get_damage_counters()
	var dmg = 20 * counters
	await main.show_message("FULL RETALIATION! " + str(counters) + " COUNTERS ON YOUR MAGIKARP — " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return dmg
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return dmg
	await main.check_all_knockouts()
	return dmg

# METALLIC BLOW (ex8-9 Jirachi): base + `more` if the Defending Pokemon has any Poké-Bodies.


=========== ex9-15 Kyogre (Basic) score 5

--- attack:Hydro Pump
TEXT: dmg=40+ cost=WWC | Does 40 damage plus 10 more damage for each Water Energy attached to Kyogre but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [60] (text: Does 40 damage plus 10 more damage for each Water Energy attached to K)


=========== ex10-13 Slowbro (Stage 1) score 4

--- body:Dual Armor
TEXT: As long as Slowbro has any Psychic Energy attached to it, Slowbro is both Water and Psychic type.
FLAG d_body_unreferenced: Poke-Body name never referenced in battle scripts


=========== ex10-41 Magcargo (Stage 1) score 4

--- body:Dual Armor
TEXT: As long as Magcargo has any Fighting Energy attached to it, Magcargo is both Fire and Fighting type.
FLAG d_body_unreferenced: Poke-Body name never referenced in battle scripts
