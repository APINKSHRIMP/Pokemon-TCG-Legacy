# batch 1: ex4-9, ex10-111, ex12-12, ex14-97, ex10-101, ex14-12, ex15-6, ex3-34, ex12-10, ex13-3, ex13-56, ex2-47, ex8-11, ex8-16, ex11-12, ex12-41, ex15-23, ex16-99, ex7-106, ex10-112


=========== ex4-9 Team Magma's Groudon (Basic) score 50

--- attack:Linear Attack
TEXT: dmg= cost=FC | Choose 1 of your opponent's Pokémon. This attack does 20 damage to that Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG a_number_missing: text numbers [20] not in handler (L31356) closure
FLAG c_choice_no_prompt: 'Choose' in text but no prompt/pick in handler L31356
FLAG b_name_collision: 4 different text/damage variants share handler L31356; e.g. dmg='' "choose 1 of your opponent's pokémon. this attack does 10 dam"
FLAG run_script_error: Main_Match_Core_Gameplay_Script.gd:9967 
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [] (text: Choose 1 of your opponent's Pokémon. This attack does 20 damage to tha)
FLAG run_choice_no_prompt: attack text has choice wording, bot was asked nothing; text: Choose 1 of your opponent's Pokémon. This attack does 20 damage to that Pokémon.
HANDLER Attack_Effects.gd:21483  _attack_dispatch["linear attack"] = func(atk, a, d, opp): await execute_ex3_choose_snipe(a, opp, 20, false); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:23718  _attack_dispatch["linear attack"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:31410  _attack_dispatch["linear attack"] = func(atk, a, d, opp):

--- attack:Pulverize
TEXT: dmg=50+ cost=FFC | If the Defending Pokémon already has at least 2 damage counters on it, this attack does 50 damage plus 20 more damage.
FLAG run_script_error: Main_Match_Core_Gameplay_Script.gd:9967 
FLAG run_damage_below_base: printed 50+, dealt 0 (text: If the Defending Pokémon already has at least 2 damage counters on it,)
FLAG run_stated_damage_not_seen: text says 50 damage; observed hp changes [] (text: If the Defending Pokémon already has at least 2 damage counters on it,)
HANDLER Attack_Effects.gd:21467  _attack_dispatch["pulverize"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); var dmg=await execute_ex4_bonus_if(a, d, opp, b, _ex4_more(atk), "counters_ge_2"); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp
[Attack_Effects.gd]
func execute_ex4_bonus_if(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, bonus: int, condition: String) -> int:
	if await handle_attack_confusion(attacker, is_opponent): return 0
	if await handle_attack_blind(attacker, is_opponent): return 0
	var cond := false
	match condition:
		"burned": cond = defender != null and defender.is_burned
		"asleep": cond = defender != null and defender.special_condition == "Asleep"
		"special_condition": cond = defender != null and (defender.special_condition != "" or defender.is_poisoned or defender.is_burned)
		"counters_ge_2": cond = defender != null and defender.get_damage_counters() >= 2
		"counters_ge_1": cond = defender != null and defender.get_damage_counters() >= 1
		"is_ex": cond = defender != null and main.is_ex_pokemon(defender)
		"attacker_has_tool": cond = not attacker.attached_cards.filter(func(ac): return "Pokémon Tool" in ac.metadata.get("subtypes", [])).is_empty()
		"hand_advantage":
			var my_hand = (main.opponent_hand if is_opponent else main.player_hand).size()
			var their_hand = (main.player_hand if is_opponent else main.opponent_hand).size()
			cond = my_hand > their_hand
	var dmg = base_damage + (bonus if cond else 0)
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return dmg
	await main.check_all_knockouts()
	if main._should_bail(): return dmg
	return dmg

# Deal base damage, then arm a status that resolves at the end of the opponent's next turn.
# The pending status is applied in gym1_end_of_turn_cleanup (Trainer_Effects.gd), the first time
# the Defender's OWN side ends a turn — i.e. "the end of your opponent's next turn".


=========== ex10-111 Tyranitar ex (Stage 2/ex) score 37

--- attack:Mix-Up
TEXT: dmg=70 cost=FDC | Your opponent discards the top card of his or her deck.
FLAG a_damage_not_in_handler: printed damage 70 neither parsed nor literal in handler L31990
FLAG b_name_collision: 2 different text/damage variants share handler L31990; e.g. dmg='30' 'flip a coin. if heads, your opponent discards the top card f'
FLAG run_damage_mismatch: printed 70, dealt 110 (text: Your opponent discards the top card of his or her deck.)
HANDLER Attack_Effects.gd:15439  _attack_dispatch["mix-up"]          = func(atk, a, d, opp): await execute_np_mix_up(a, d, opp);          await _attack_finish(true, 30, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:26946  _attack_dispatch["mix-up"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:32044  _attack_dispatch["mix-up"] = func(atk, a, d, opp):

--- attack:Shatter
TEXT: dmg=30 cost=F | Discard any Stadium card in play.
FLAG run_damage_mismatch: printed 30, dealt 70 (text: Discard any Stadium card in play.)
HANDLER Attack_Effects.gd:34227  _r3_wrap("shatter", "discard any stadium card in play", func(atk, a, d, opp):
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


--- attack:Derail
TEXT: dmg=30 cost=CC | Discard a Special Energy card, if any, attached to the Defending Pokémon.
FLAG run_damage_mismatch: printed 30, dealt 70 (text: Discard a Special Energy card, if any, attached to the Defending Pokém)
HANDLER Attack_Effects.gd:27042  _attack_dispatch["derail"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex10_derail(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex10_derail(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var specials = defender.attached_energies.filter(func(e): return "Special" in e.metadata.get("subtypes", []))
		if not specials.is_empty():
			var chosen: card_object = (await r3_pick_defender_energy(defender, true, "", specials)) if is_opponent else await main.card_ops.choose_card(specials, false, "DERAIL", "Discard which Special Energy?", "DISCARD", false)   # OLD ISSUE 334
			if main._should_bail(): return
			if chosen == null: chosen = specials[0]
			defender.attached_energies.erase(chosen)
			main.card_ops.discard_energy_from_pokemon(chosen, not is_opponent)
			main.display_active_pokemon_energies(not is_opponent)
			main.update_discard_pile_display(not is_opponent)
			await main.show_message("DERAIL! DISCARDED " + chosen.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
	await main.check_all_knockouts()

# Double Attack (Corsola): choose 2 of the opponent's Benched Pokemon, 10 damage to each (no W/R).

--- attack:Losing Control
TEXT: dmg=120 cost=FDDC | Discard the top 3 cards of your deck.
FLAG run_damage_mismatch: printed 120, dealt 160 (text: Discard the top 3 cards of your deck.)
HANDLER Attack_Effects.gd:27056  _attack_dispatch["losing control"]  = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex10_self_mill(a, d, opp, b, 3); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex10_self_mill(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, n: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var d = 0
	var milled: Array = []
	for i in range(n):
		if deck.is_empty(): break
		var top = deck.pop_front(); top.current_location = "discard"; discard.append(top); d += 1; milled.append(top)
	await main.card_ops.fly_lifted(main.card_ops.lift_cards(milled, "deck", is_opponent), "discard", is_opponent)   # AUDIT 2026-11-17: flight
	if main._should_bail(): return
	main.update_deck_icon(is_opponent); main.update_discard_pile_display(is_opponent)
	if d > 0:
		await main.show_message("DISCARDED " + str(d) + " CARDS FROM THE TOP OF YOUR DECK!")
		if main._should_bail(): return
	await main.check_all_knockouts()

# Mudslide (Steelix ex): discard 2 Fighting Energy from self, then choose 1 of the opponent's Pokemon
# and do 100 to it (no W/R for Bench).


=========== ex12-12 Shiftry (Stage 2) score 37

--- attack:Cross-Cut
TEXT: dmg=40+ cost=DCC | If the Defending Pokémon is an Evolved Pokémon, this attack does 40 damage plus 30 more damage.
FLAG a_number_missing: text numbers [30, 40] not in handler (L23743) closure
FLAG a_damage_not_in_handler: printed damage 40+ neither parsed nor literal in handler L23743
FLAG b_name_collision: 5 different text/damage variants share handler L23743; e.g. dmg='20+' 'if the defending pokémon is an evolved pokémon, this attack '
HANDLER Attack_Effects.gd:16693  _attack_dispatch["cross-cut"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:23796  _attack_dispatch["cross-cut"] = func(atk, a, d, opp):

--- attack:Reactive Beating
TEXT: dmg=30 cost=CC | If Shiftry has any React Energy cards attached to it, the Defending Pokémon is now Confused.
FLAG run_damage_mismatch: printed 30, dealt 60 (text: If Shiftry has any React Energy cards attached to it, the Defending Po)
FLAG run_status_missing: text says confused but defender shows cond='' pois=False burn=False
HANDLER Attack_Effects.gd:29441  _attack_dispatch["reactive beating"]  = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex12_status_if_react(a, d, opp, b, "Confused"); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex12_status_if_react(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, status: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if attacker.react_energy_count() > 0 and defender != null and defender.current_hp > 0 and not defender.is_invincible:
		main.card_ops.apply_status(defender, status, not is_opponent)
		main.update_status_icons(defender, not is_opponent)
		await main.show_message("THE DEFENDING POKEMON IS NOW " + status.to_upper() + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()

# Base damage, then apply `status` to the Defender only if it has any Special Energy (Girafarig Disorder).

--- power:Evolutionary Fan
TEXT: Once during your turn, when you play Shiftry from your hand to evolve 1 of your Pokémon, you may choose 1 of your Evolved Pokémon in play (excluding any Shiftry). Return that Pokémon and all cards attached to it to your hand.
FLAG run_not_implemented: Power not implemented: Evolutionary Fan
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you play Shiftry from your hand to evolve 1 of your 


=========== ex14-97 Shiftry ex (Stage 2/ex) score 30

--- attack:Target Attack
TEXT: dmg= cost=DC | Choose 1 of your opponent's Pokémon. This attack does 30 damage to that Pokémon. If that Pokémon already has any damage counters on it, this attack does 50 damage instead. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG a_number_missing: text numbers [30, 50] not in handler (L30780) closure
FLAG c_choice_no_prompt: 'Choose' in text but no prompt/pick in handler L30780
FLAG b_name_collision: 2 different text/damage variants share handler L30780; e.g. dmg='' "choose 1 of your opponent's pokémon. this attack does 40 dam"
FLAG run_stated_damage_not_seen: text says 50 damage; observed hp changes [60] (text: Choose 1 of your opponent's Pokémon. This attack does 30 damage to tha)
FLAG run_stated_damage_not_seen: text says 30 damage; observed hp changes [60] (text: Choose 1 of your opponent's Pokémon. This attack does 30 damage to tha)
HANDLER Attack_Effects.gd:28603  _attack_dispatch["target attack"]       = func(atk, a, d, opp): await execute_ex11_target_attack(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30834  _attack_dispatch["target attack"] = func(atk, a, d, opp):

--- attack:Blade Arms
TEXT: dmg=70 cost=DCC | 
FLAG run_damage_mismatch: printed 70, dealt 100 (text: )


=========== ex10-101 Blissey ex (Stage 1/ex) score 25

--- attack:Energy Absorption
TEXT: dmg= cost=C | Attach up to 3 Energy cards from your discard pile to Blissey ex.
FLAG a_number_missing: text numbers [3] not in handler (L30116) closure
FLAG c_choice_no_prompt: 'up to' in text but no prompt/pick in handler L30116
FLAG b_name_collision: 4 different text/damage variants share handler L30116; e.g. dmg='' 'choose up to 2 energy cards from your discard pile and attac'
HANDLER Attack_Effects.gd:85  _attack_dispatch["energy absorption"]   = func(atk, a, d, opp): await execute_energy_absorption(a, opp, 2);                                                                                   await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorle
HANDLER Attack_Effects.gd:26939  _attack_dispatch["energy absorption"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:30169  _attack_dispatch["energy absorption"] = func(atk, a, d, opp):

--- power:Blissful Support
TEXT: Once during your turn, when you play Blissey ex from your hand to evolve 1 of your Pokémon, you may discard all Energy cards attached to any number of your Pokémon and remove all damage counters from those Pokémon.
FLAG run_not_implemented: Power not implemented: Blissful Support
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you play Blissey ex from your hand to evolve 1 of yo


=========== ex14-12 Tauros (Basic) score 25

--- attack:Call for Family
TEXT: dmg= cost=C | Search your deck for up to 2 Basic Pokémon and put them onto your Bench. Shuffle your deck afterward.
FLAG a_number_missing: text numbers [2] not in handler (L30787) closure
FLAG c_choice_no_prompt: 'up to' in text but no prompt/pick in handler L30787
FLAG b_name_collision: 13 different text/damage variants share handler L30787; e.g. dmg='' 'search your deck for a basic pokémon named bellsprout and pu'
HANDLER Attack_Effects.gd:29409  _attack_dispatch["call for family"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:30841  _attack_dispatch["call for family"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:34176  _r3_wrap("call for family", "put as many of them as you like onto your bench", r4_call_as_many)
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


--- power:Crush Chance
TEXT: Once during your turn, when you put Tauros from your hand onto your Bench, you may discard a Stadium card in play.
FLAG run_not_implemented: Power not implemented: Crush Chance
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you put Tauros from your hand onto your Bench, you m


=========== ex15-6 Nidoking δ (Stage 2) score 25

--- attack:Linear Attack
TEXT: dmg= cost=CC | Choose 1 of your opponent's Pokémon. This attack does 30 damage to that Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG a_number_missing: text numbers [30] not in handler (L31356) closure
FLAG c_choice_no_prompt: 'Choose' in text but no prompt/pick in handler L31356
FLAG b_name_collision: 4 different text/damage variants share handler L31356; e.g. dmg='' "choose 1 of your opponent's pokémon. this attack does 20 dam"
HANDLER Attack_Effects.gd:21483  _attack_dispatch["linear attack"] = func(atk, a, d, opp): await execute_ex3_choose_snipe(a, opp, 20, false); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:23718  _attack_dispatch["linear attack"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:31410  _attack_dispatch["linear attack"] = func(atk, a, d, opp):

--- attack:Dark Horn
TEXT: dmg=60 cost=DCC | You may discard a Basic Pokémon or Evolution card from your hand. If you do, choose 1 of your opponent's Benched Pokémon and do 20 damage to that Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG run_damage_mismatch: printed 60, dealt 90 (text: You may discard a Basic Pokémon or Evolution card from your hand. If y)
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [90] (text: You may discard a Basic Pokémon or Evolution card from your hand. If y)
HANDLER Attack_Effects.gd:31427  _attack_dispatch["dark horn"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex15_dark_horn(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex15_dark_horn(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var pokemon_cards = hand.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if pokemon_cards.is_empty() or opp_bench.is_empty(): return
	var to_discard: card_object = null
	if is_opponent:
		# OLD ISSUE 339: the CPU always threw away its first Pokemon card. Now its least useful one, and only for a
		# Bench KO or when that card is dead weight.
		var dh_low: card_object = pokemon_cards[0]
		for c in pokemon_cards:
			if main.cpu_ai.cpu_rank_keep_value(c) < main.cpu_ai.cpu_rank_keep_value(dh_low): dh_low = c
		var dh_ko = opp_bench.any(func(p): return p.current_hp <= 20)
		if not (dh_ko or main.cpu_ai.cpu_rank_keep_value(dh_low) < ULTRA_PUMP_CPU_JUNK_VALUE): return
		to_discard = dh_low
	else:
		var yes = await main.trainer_effects.gym1_prompt_yes_no(attacker, "DARK HORN", "Discard a Basic/Evolution card to do 20 to a Benched Pokémon?", "YES", "NO")
		if main._should_bail(): return
		if not yes: return
		to_discard = pokemon_cards[0] if pokemon_cards.size() == 1 else await main.card_ops.choose_card(pokemon_cards, false, "DARK HORN", "Discard which card?", "DISCARD", true)
		if main._should_bail(): return
		if to_discard == null: return
	hand.erase(to_discard)
	await main.card_ops.send_to_discard(to_discard, is_opponent, true)
	if main._should_bail(): return
	await execute_ex3_choose_snipe(attacker, is_opponent, 20, true)
	if main._should_bail(): return

# TRICK TAIL (Ninetales δ ex15-8): base damage; search your discard pile for an Energy card and attach it
# to 1 of your Pokémon.


=========== ex3-34 Houndoom (Stage 1) score 25

--- attack:Feint Attack
TEXT: dmg= cost=DC | Choose 1 of your opponent's Pokémon. This attack does 20 damage to that Pokémon. This attack's damage isn't affected by Weakness, Resistance, Poké-Powers, Poké-Bodies, or any other effects on that Pokémon.
FLAG a_number_missing: text numbers [20] not in handler (L9362) closure
FLAG c_choice_no_prompt: 'Choose' in text but no prompt/pick in handler L9362
FLAG b_name_collision: 8 different text/damage variants share handler L9362; e.g. dmg='' "choose 1 of your opponent's pokémon. this attack does 30 dam"
FLAG run_stated_damage_not_seen: text says 20 damage; observed hp changes [40] (text: Choose 1 of your opponent's Pokémon. This attack does 20 damage to tha)
HANDLER Attack_Effects.gd:9382  _attack_dispatch["feint attack"]       = func(atk, a, d, opp):

--- attack:Flamethrower
TEXT: dmg=50 cost=FCC | Discard a Fire Energy card attached to Houndoom.
FLAG run_damage_mismatch: printed 50, dealt 70 (text: Discard a Fire Energy card attached to Houndoom.)
HANDLER Attack_Effects.gd:10640  _attack_dispatch["flamethrower"]    = func(atk, a, d, opp):


=========== ex12-10 Mew (Basic) score 24

--- attack:Link Blast
TEXT: dmg=50 cost=PC | If Mew and the Defending Pokémon have a different amount of Energy attached to them, this attack's base damage is 20 instead of 50.
FLAG a_number_missing: text numbers [20, 50] not in handler (L18488) closure
FLAG a_damage_not_in_handler: printed damage 50 neither parsed nor literal in handler L18488
FLAG b_name_collision: 5 different text/damage variants share handler L18488; e.g. dmg='40' 'if ralts and the defending pokémon have a different amount o'
FLAG run_damage_mismatch: printed 50, dealt 20 (text: If Mew and the Defending Pokémon have a different amount of Energy att)
HANDLER Attack_Effects.gd:18532  _attack_dispatch["link blast"]         = func(atk, a, d, opp):

--- power:Type Change
TEXT: Once during your turn (before your attack), you may choose 1 of the Defending Pokémon. Mew is the same type as that Pokémon (all if that Pokémon is more than 1 type) until the end of your turn. This power can't be used if Mew is affected by a Special Condition.
FLAG run_power_no_effect: state identical before/after; text: Once during your turn (before your attack), you may choose 1 of the Defending Pokémon. Mew
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn (before your attack), you may choose 1 of the Defending Po
HANDLER Powers_And_Bodies_Effects.gd:17779  _power_dispatch["Type Change"]        = func(p): await power_ex12_type_change(p)
[Powers_And_Bodies_Effects.gd]
func power_ex12_type_change(mew: card_object) -> void:
	var is_opp = mew.is_owner_opp(main)
	if is_opp:
		# ISSUE #430: the CPU uses it now (cpu_phase_human_powers decides WHEN, through
		# _cpu_type_change_helps); single battle, so the Defending Pokémon is the player's Active.
		var foe = main.player_active_pokemon
		if foe == null or mew.power_used_this_turn or is_power_blocked(mew):
			return
		var ft: Array = foe.get_effective_types()
		if ft.is_empty():
			return
		mew.power_used_this_turn = true
		mew.set_effect("ex2_type_override", "end_of_own_turn", ft.duplicate())
		print("ISSUE #430 FIX ACTIVE: CPU Type Change -> ", ft)
		await main.show_message("TYPE CHANGE! MEW IS NOW " + "/".join(ft).to_upper() + " TYPE!")
		return
	if not await _ex11_power_ready(mew, "Type Change"):
		if main._should_bail(): return
		return
	var defenders = main.card_ops.get_defending_pokemon(is_opp)
	if defenders.is_empty():
		await main.show_message("NO DEFENDING POKEMON!")
		if main._should_bail(): return
		return
	var chosen: card_object = defenders[0] if defenders.size() == 1 else await main.card_ops.choose_card(defenders, false, "TYPE CHANGE", "Copy the type of which Defending Pokemon?", "SELECT", false)
	if main._should_bail(): return
	if chosen == null: chosen = defenders[0]
	var t = chosen.get_effective_types()
	if t.is_empty(): return
	mew.power_used_this_turn = true
	# OLD ISSUE 371: "Mew is the same type as that Pokémon (ALL if that Pokémon is more than 1 type)" — only the first type
	# was copied.
	mew.set_effect("ex2_type_override", "end_of_own_turn", t.duplicate())
	await main.show_message("TYPE CHANGE! MEW IS NOW " + "/".join(t).to_upper() + " TYPE!")
	if main._should_bail(): return

# NECTAR POD (Victreebel ex12-13): switch 1 of your opponent's Benched Stage 2 Evolved Pokemon with the
# Defending Pokemon (your opponent chooses the Defending — moot in single battle).


=========== ex13-3 Deoxys δ (Basic) score 24

--- attack:Energy Loop
TEXT: dmg=60 cost=DCC | Return 2 Energy attached to Deoxys to your hand.
FLAG a_number_missing: text numbers [2] not in handler (L30079) closure
FLAG a_damage_not_in_handler: printed damage 60 neither parsed nor literal in handler L30079
FLAG b_name_collision: 3 different text/damage variants share handler L30079; e.g. dmg='30' 'return an energy card attached to starmie to your hand.'
FLAG run_damage_mismatch: printed 60, dealt 90 (text: Return 2 Energy attached to Deoxys to your hand.)
HANDLER Attack_Effects.gd:266  _attack_dispatch["energy loop"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_energy_loop(a, d, opp, b);                                                await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorles
HANDLER Attack_Effects.gd:28564  _attack_dispatch["energy loop"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:30132  _attack_dispatch["energy loop"] = func(atk, a, d, opp):

--- power:Form Change
TEXT: Once during your turn (before your attack), you may search your deck for another Deoxys and switch it with Deoxys. (Any cards attached to Deoxys, damage counters, Special Conditions, and effects on it are now on the new Pokémon.) If you do, put Deoxys on top of your deck. Shuffle your deck afterward. You can't use more than 1 Form Change Poké-Power each turn.
FLAG run_power_no_effect: state identical before/after; text: Once during your turn (before your attack), you may search your deck for another Deoxys an
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn (before your attack), you may search your deck for another
HANDLER Powers_And_Bodies_Effects.gd:15175  _power_dispatch["Form Change"]        = func(p): await power_ex8_form_change(p)
[Powers_And_Bodies_Effects.gd]
func power_ex8_form_change(deoxys: card_object) -> void:
	var is_opponent = deoxys.is_owner_opp(main)
	if is_power_blocked_by_status(deoxys):
		await main.show_message("FORM CHANGE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var flag_used = main.opponent_ex8_form_change_used if is_opponent else main.player_ex8_form_change_used
	if flag_used:
		await main.show_message("FORM CHANGE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var my_name = deoxys.metadata.get("name","")
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and c.metadata.get("name","") == my_name and c.uid != deoxys.uid)
	if pool.is_empty():
		await main.show_message("NO OTHER " + my_name.to_upper() + " IN YOUR DECK!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = _r4_cpu_best_form(deoxys, pool)   # OLD ISSUE 351: was the first Deoxys in the deck
		if chosen == null: return
	else:
		chosen = await main.card_ops.choose_card(pool, false, "FORM CHANGE", "Choose a " + my_name + " to switch in", "SELECT", true, Callable(), true)
		if main._should_bail(): return
		if chosen == null: return
	if is_opponent: main.opponent_ex8_form_change_used = true
	else: main.player_ex8_form_change_used = true
	chosen.attached_energies = deoxys.attached_energies.duplicate()
	chosen.attached_pre_evolutions = deoxys.attached_pre_evolutions.duplicate()
	chosen.attached_cards = deoxys.attached_cards.duplicate()
	var max_hp_new = chosen.get_max_hp()
	var damage_taken = deoxys.get_max_hp() - deoxys.current_hp
	chosen.current_hp = max(0, max_hp_new - damage_taken)   # OLD ISSUE 347: a form with less HP than the damage is Knocked Out (was floored at 1)
	chosen.special_condition = deoxys.special_condition
	chosen.is_poisoned = deoxys.is_poisoned
	chosen.poison_damage = deoxys.poison_damage
	chosen.is_burned = deoxys.is_burned
	chosen.placed_on_field_this_turn = deoxys.placed_on_field_this_turn
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	deck.erase(chosen)
	if deoxys == active:
		if is_opponent: main.opponent_active_pokemon = chosen
		else: main.player_active_pokemon = chosen


=========== ex13-56 Wobbuffet (Basic) score 24

--- attack:Call for Friends
TEXT: dmg= cost=C | Search your deck for up to 2 Basic Pokémon and put them onto your Bench. Shuffle your deck afterward.
FLAG a_number_missing: text numbers [2] not in handler (L30094) closure
FLAG c_choice_no_prompt: 'up to' in text but no prompt/pick in handler L30094
FLAG b_name_collision: 2 different text/damage variants share handler L30094; e.g. dmg='' 'search your deck for a baby pokémon or basic pokémon card an'
HANDLER Attack_Effects.gd:24665  _attack_dispatch["call for friends"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:30147  _attack_dispatch["call for friends"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:34175  _r3_wrap("call for friends", "put as many of them as you like onto your bench", r4_call_as_many)
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


--- attack:Retaliate
TEXT: dmg=10× cost=PC | Does 10 damage times the number of damage counters on Wobbuffet.
FLAG a_number_missing: text numbers [10] not in handler (L30748) closure
FLAG a_damage_not_in_handler: printed damage 10× neither parsed nor literal in handler L30748
FLAG b_name_collision: 10 different text/damage variants share handler L30748; e.g. dmg='10×' 'this attack does 10 damage times the number of damage counte'
FLAG run_stated_damage_not_seen: text says 10 damage; observed hp changes [] (text: Does 10 damage times the number of damage counters on Wobbuffet.)
HANDLER Attack_Effects.gd:18509  _attack_dispatch["retaliate"]          = func(atk, a, d, opp): var dmg = await execute_ex1_retaliate(a, d, opp);                          await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:30802  _attack_dispatch["retaliate"] = func(atk, a, d, opp):


=========== ex2-47 Murkrow (Basic) score 24

--- attack:Surprise
TEXT: dmg= cost=C | Choose 1 card from your opponent's hand without looking. Look at the card you chose, then have your opponent shuffle that card into his or her deck.
FLAG c_choice_no_prompt: 'Choose' in text but no prompt/pick in handler L26933
FLAG b_name_collision: 5 different text/damage variants share handler L26933; e.g. dmg='30' "choose 1 card from your opponent's hand without looking. loo"
HANDLER Attack_Effects.gd:174  _attack_dispatch["surprise"]           = func(atk, a, d, opp): await execute_surprise(a, opp);               await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
HANDLER Attack_Effects.gd:26986  _attack_dispatch["surprise"] = func(atk, a, d, opp):

--- attack:Dark Mind
TEXT: dmg=20 cost=DC | Does 10 damage to 1 of your opponent's Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)
FLAG a_number_missing: text numbers [10] not in handler (L32000) closure
FLAG a_damage_not_in_handler: printed damage 20 neither parsed nor literal in handler L32000
FLAG b_name_collision: 4 different text/damage variants share handler L32000; e.g. dmg='30' 'if your opponent has any benched pokémon, choose 1 of them a'
FLAG run_damage_mismatch: printed 20, dealt 50 (text: Does 10 damage to 1 of your opponent's Benched Pokémon. (Don't apply W)
HANDLER Attack_Effects.gd:19253  _attack_dispatch["dark mind"]          = func(atk, a, d, opp): await execute_ex2_dark_mind(a, opp);                                          await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:32054  _attack_dispatch["dark mind"] = func(atk, a, d, opp):


=========== ex8-11 Metagross (Stage 2) score 24

--- attack:Link Blast
TEXT: dmg=70 cost=PC | If Metagross and the Defending Pokémon have a different amount of Energy attached to them, this attack's base damage is 40 instead of 70.
FLAG a_number_missing: text numbers [40, 70] not in handler (L18488) closure
FLAG a_damage_not_in_handler: printed damage 70 neither parsed nor literal in handler L18488
FLAG b_name_collision: 5 different text/damage variants share handler L18488; e.g. dmg='40' 'if ralts and the defending pokémon have a different amount o'
FLAG run_damage_mismatch: printed 70, dealt 40 (text: If Metagross and the Defending Pokémon have a different amount of Ener)
HANDLER Attack_Effects.gd:18532  _attack_dispatch["link blast"]         = func(atk, a, d, opp):

--- power:Super Connectivity
TEXT: Once during your turn (before your attack), you may search your discard pile for a Psychic or Metal Energy card and attach it to your Active Pokémon. Then, put 1 damage counter on that Pokémon. This power can't be used if Metagross is affected by a Special Condition.
FLAG run_power_no_effect: state identical before/after; text: Once during your turn (before your attack), you may search your discard pile for a Psychic
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn (before your attack), you may search your discard pile for
HANDLER Powers_And_Bodies_Effects.gd:15174  _power_dispatch["Super Connectivity"] = func(p): await power_ex8_super_connectivity(p)
[Powers_And_Bodies_Effects.gd]
func power_ex8_super_connectivity(metagross: card_object) -> void:
	var is_opponent = metagross.is_owner_opp(main)
	if is_power_blocked_by_status(metagross):
		await main.show_message("SUPER CONNECTIVITY IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if metagross.power_used_this_turn:
		await main.show_message("SUPER CONNECTIVITY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var pool = discard.filter(func(c):
		if c.metadata.get("supertype","") != "Energy": return false
		var prov = main.get_energy_provided_by_card(c)
		return main.is_typed_energy_card(c, "Psychic") or main.is_typed_energy_card(c, "Metal"))
	if pool.is_empty():
		await main.show_message("NO PSYCHIC OR METAL ENERGY IN YOUR DISCARD!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	metagross.power_used_this_turn = true
	var chosen: card_object
	if is_opponent:
		chosen = main.attack_effects._r3_cpu_needed_energy(pool, active)   # OLD ISSUE 351: the one the Active needs
	else:
		chosen = await main.card_ops.choose_card(pool, false, "SUPER CONNECTIVITY", "Choose an Energy to attach to your Active", "ATTACH", false, Callable(), true)
		if main._should_bail(): return
		if chosen == null: chosen = pool[0]
	discard.erase(chosen)
	chosen.current_location = "attached"
	active.attached_energies.append(chosen)
	await main.card_ops.fly_attach(chosen, "discard", {})   # AUDIT 2026-11-17: flight
	if main._should_bail(): return
	main.play_energy_attach_sfx()
	active.current_hp = max(0, active.current_hp - 10)
	main.display_active_pokemon_energies(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_hp_circles_above_align(active, is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("SUPER CONNECTIVITY! ATTACHED " + chosen.metadata.get("name","").to_upper() + " (1 DAMAGE COUNTER)!")
	if main._should_bail(): return
	await main.check_all_knockouts()

# FORM CHANGE (Deoxys ex8-16/17/18 + Deoxys ex ex8-97/98/99): search your deck for another Deoxys of


=========== ex8-16 Deoxys (Basic) score 24

--- attack:Link Blast
TEXT: dmg=40 cost=PC | If Deoxys and the Defending Pokémon have a different amount of Energy attached to them, this attack's base damage is 20 instead of 40.
FLAG a_number_missing: text numbers [20, 40] not in handler (L18488) closure
FLAG a_damage_not_in_handler: printed damage 40 neither parsed nor literal in handler L18488
FLAG b_name_collision: 5 different text/damage variants share handler L18488; e.g. dmg='40' 'if ralts and the defending pokémon have a different amount o'
FLAG run_damage_mismatch: printed 40, dealt 20 (text: If Deoxys and the Defending Pokémon have a different amount of Energy )
HANDLER Attack_Effects.gd:18532  _attack_dispatch["link blast"]         = func(atk, a, d, opp):

--- power:Form Change
TEXT: Once during your turn (before your attack), you may search your deck for another Deoxys and switch it with Deoxys. (Any cards attached to Deoxys, damage counters, Special Conditions, and effects on it are now on the new Pokémon.) If you do, put Deoxys on top of your deck. Shuffle your deck afterward. You can't use more than 1 Form Change Poké-Power each turn.
FLAG run_power_no_effect: state identical before/after; text: Once during your turn (before your attack), you may search your deck for another Deoxys an
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn (before your attack), you may search your deck for another
HANDLER Powers_And_Bodies_Effects.gd:15175  _power_dispatch["Form Change"]        = func(p): await power_ex8_form_change(p)
[Powers_And_Bodies_Effects.gd]
func power_ex8_form_change(deoxys: card_object) -> void:
	var is_opponent = deoxys.is_owner_opp(main)
	if is_power_blocked_by_status(deoxys):
		await main.show_message("FORM CHANGE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var flag_used = main.opponent_ex8_form_change_used if is_opponent else main.player_ex8_form_change_used
	if flag_used:
		await main.show_message("FORM CHANGE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var my_name = deoxys.metadata.get("name","")
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and c.metadata.get("name","") == my_name and c.uid != deoxys.uid)
	if pool.is_empty():
		await main.show_message("NO OTHER " + my_name.to_upper() + " IN YOUR DECK!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = _r4_cpu_best_form(deoxys, pool)   # OLD ISSUE 351: was the first Deoxys in the deck
		if chosen == null: return
	else:
		chosen = await main.card_ops.choose_card(pool, false, "FORM CHANGE", "Choose a " + my_name + " to switch in", "SELECT", true, Callable(), true)
		if main._should_bail(): return
		if chosen == null: return
	if is_opponent: main.opponent_ex8_form_change_used = true
	else: main.player_ex8_form_change_used = true
	chosen.attached_energies = deoxys.attached_energies.duplicate()
	chosen.attached_pre_evolutions = deoxys.attached_pre_evolutions.duplicate()
	chosen.attached_cards = deoxys.attached_cards.duplicate()
	var max_hp_new = chosen.get_max_hp()
	var damage_taken = deoxys.get_max_hp() - deoxys.current_hp
	chosen.current_hp = max(0, max_hp_new - damage_taken)   # OLD ISSUE 347: a form with less HP than the damage is Knocked Out (was floored at 1)
	chosen.special_condition = deoxys.special_condition
	chosen.is_poisoned = deoxys.is_poisoned
	chosen.poison_damage = deoxys.poison_damage
	chosen.is_burned = deoxys.is_burned
	chosen.placed_on_field_this_turn = deoxys.placed_on_field_this_turn
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	deck.erase(chosen)
	if deoxys == active:
		if is_opponent: main.opponent_active_pokemon = chosen
		else: main.player_active_pokemon = chosen


=========== ex11-12 Mewtwo δ (Basic) score 23

--- attack:Energy Burst
TEXT: dmg=10× cost=FM | Does 10 damage times the total amount of Energy attached to Mewtwo and the Defending Pokémon.
FLAG a_number_missing: text numbers [10] not in handler (L25631) closure
FLAG a_damage_not_in_handler: printed damage 10× neither parsed nor literal in handler L25631
FLAG b_name_collision: 3 different text/damage variants share handler L25631; e.g. dmg='10×' 'does 10 damage times the total amount of energy attached to '
HANDLER Attack_Effects.gd:18515  _attack_dispatch["energy burst"]       = func(atk, a, d, opp): await execute_ex1_energy_burst(a, d, opp);                                 await _attack_finish(true, 0, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:25684  _attack_dispatch["energy burst"] = func(atk, a, d, opp):
HANDLER Attack_Effects.gd:32910  _r3_wrap("energy burst", "flip a coin. if heads, this attack does 10 damage times the number of energy", r3_energy_burst_flip)
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


--- power:Delta Switch
TEXT: Once during your turn, when you put Mewtwo from your hand onto your Bench, you may move any number of basic Energy cards attached to your Pokémon to your other Pokémon (excluding Mewtwo) in any way you like.
FLAG run_not_implemented: Power not implemented: Delta Switch
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you put Mewtwo from your hand onto your Bench, you m


=========== ex12-41 Nuzleaf (Stage 1) score 23

--- attack:Plunder
TEXT: dmg=30 cost=DC | Before doing damage, discard all Trainer cards attached to the Defending Pokémon.
FLAG a_damage_not_in_handler: printed damage 30 neither parsed nor literal in handler L21357
FLAG b_name_collision: 5 different text/damage variants share handler L21357; e.g. dmg='20' 'before doing damage, discard all trainer cards attached to t'
FLAG run_damage_mismatch: printed 30, dealt 60 (text: Before doing damage, discard all Trainer cards attached to the Defendi)
HANDLER Attack_Effects.gd:10627  _attack_dispatch["plunder"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo2_plunder(a, d, opp, b);  await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:15427  _attack_dispatch["plunder"]         = func(atk, a, d, opp): await _np_deal(a, d, 10, opp); await _attack_finish(true, 10, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:21409  _attack_dispatch["plunder"] = func(atk, a, d, opp):

--- attack:Pound
TEXT: dmg=20 cost=C | 
FLAG run_damage_mismatch: printed 20, dealt 50 (text: )


=========== ex15-23 Tropius δ (Basic) score 23

--- attack:Grind
TEXT: dmg=10× cost=M | Does 10 damage times the amount of Energy attached to Tropius.
FLAG a_number_missing: text numbers [10] not in handler (L31334) closure
FLAG a_damage_not_in_handler: printed damage 10× neither parsed nor literal in handler L31334
FLAG b_name_collision: 6 different text/damage variants share handler L31334; e.g. dmg='10×' 'does 10 damage times the amount of energy attached to wobbuf'
HANDLER Attack_Effects.gd:20275  _attack_dispatch["grind"]              = func(atk, a, d, opp): var dmg=await execute_ex3_grind(a, d, opp);                await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:31388  _attack_dispatch["grind"] = func(atk, a, d, opp):

--- power:Tropical Heal
TEXT: Once during your turn, when you put Tropius from your hand onto your Bench, you may remove all Special Conditions, Imprison markers, and Shock-wave markers from your Pokémon.
FLAG run_not_implemented: Power not implemented: Tropical Heal
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you put Tropius from your hand onto your Bench, you 


=========== ex16-99 Walrein ex (Stage 2/ex) score 23

--- attack:Wreck
TEXT: dmg=70+ cost=WWC | If there is any Stadium card in play, this attack does 70 damage plus 20 more damage. Discard that Stadium card.
FLAG a_number_missing: text numbers [20, 70] not in handler (L32010) closure
FLAG a_damage_not_in_handler: printed damage 70+ neither parsed nor literal in handler L32010
FLAG b_name_collision: 2 different text/damage variants share handler L32010; e.g. dmg='30+' 'if there is any stadium card in play, this attack does 30 da'
HANDLER Attack_Effects.gd:30193  _attack_dispatch["wreck"]          = func(atk, a, d, opp): var dmg=await execute_ex13_wreck(a, d, opp); await _attack_finish(true, dmg, atk, a.metadata.get("types",["Colorless"]), opp)
HANDLER Attack_Effects.gd:32064  _attack_dispatch["wreck"] = func(atk, a, d, opp):

--- power:Chilling Breath
TEXT: Once during your turn, when you play Walrein ex from your hand to evolve 1 of your Pokémon, you may use this power. Your opponent can't play any Trainer cards from his or her hand during your opponent's next turn.
FLAG run_not_implemented: Power not implemented: Chilling Breath
FLAG run_choice_no_prompt: text has choice wording, bot was asked nothing; text: Once during your turn, when you play Walrein ex from your hand to evolve 1 of yo


=========== ex7-106 Rocket's Zapdos ex (Basic/ex) score 23

--- attack:Plasma
TEXT: dmg=10 cost=C | Search your discard pile for a Lightning Energy card and attach it to Rocket's Zapdos ex.
FLAG a_damage_not_in_handler: printed damage 10 neither parsed nor literal in handler L148
FLAG b_name_collision: 11 different text/damage variants share handler L148; e.g. dmg='10' 'if there are any lightning energy cards in your discard pile'
FLAG run_damage_mismatch: printed 10, dealt 30 (text: Search your discard pile for a Lightning Energy card and attach it to )
HANDLER Attack_Effects.gd:148  _attack_dispatch["plasma"]             = func(atk, a, d, opp):

--- attack:Raging Thunder
TEXT: dmg=60 cost=LLC | This attack does 30 damage to 1 of your Pokémon.
FLAG run_damage_mismatch: printed 60, dealt 80 (text: This attack does 30 damage to 1 of your Pokémon.)
HANDLER Attack_Effects.gd:24732  _attack_dispatch["raging thunder"]     = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex7_raging_thunder(a, d, opp, b, 30); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex7_raging_thunder(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, self_dmg: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var mine = main.card_ops.get_all_pokemon_in_play(is_opponent)
	if not mine.is_empty():
		var target: card_object = null
		if is_opponent:
			# OLD ISSUE 331: a Pokémon that survives the hit and matters least (it took the first survivor in the list,
			# which could be its best Benched attacker).
			target = mine[0]
			var rt_best := -INF
			for c in mine:
				var s: float = (0.0 if c.current_hp > self_dmg else -1000.0) + float(c.current_hp) * 0.2 - main.cpu_ai.cpu_rank_keep_value(c) * 0.5 - (40.0 if c == attacker else 0.0)
				if s > rt_best:
					rt_best = s
					target = c
		else:
			target = await main.card_ops.choose_card(mine, false, "RAGING THUNDER", "Choose 1 of your Pokémon to take " + str(self_dmg) + " damage", "SELECT", false, Callable(), true)
			if main._should_bail(): return
			if target == null: target = attacker
		var t_is_active = target == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon)
		if t_is_active:
			target.current_hp = max(0, target.current_hp - self_dmg)
			main.display_hp_circles_above_align(target, is_opponent)
		else:
			await main.card_ops.apply_bench_damage(target, self_dmg, is_opponent)
	await main.check_all_knockouts()
	if main._should_bail(): return

# SPRING BACK (ex7-107/108/109 Pokémon Star): base; if the opponent has only 1 Prize card left, this
# attack does base + more and applies the Star's status (read from the card text).


=========== ex10-112 Umbreon ex (Stage 1/ex) score 22

--- power:Darker Ring
TEXT: Once during your turn (before your attack), when you play Umbreon ex from your hand to evolve 1 of your Pokémon, switch 1 of your opponent's Benched Pokémon with 1 of the Defending Pokémon. Your opponent chooses the Defending Pokémon to switch.
FLAG e_power_no_cpu: activated power never named in cpu_phase_activate_powers / CPU_AI
FLAG run_not_implemented: Power not implemented: Darker Ring

--- attack:Black Cry
TEXT: dmg=20 cost=C | The Defending Pokémon can't retreat or use any Poké-Powers during your opponent's next turn.
FLAG run_refused_setup: attack refused on the standard board (probe limit, not necessarily a bug): UMBREON EX USED BLACK CRY | CLEFAIRY CAN'T RETREAT! | THE DEFENDING POKEMON CAN'T USE POKE-POWERS NE
HANDLER Attack_Effects.gd:27080  _attack_dispatch["black cry"]       = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_ex10_black_cry(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_ex10_black_cry(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		await apply_retreat_lock(defender, is_opponent)
		if main._should_bail(): return
		defender.set_effect("ex10_power_lock", "end_of_own_turn", {})   # OLD ISSUE 296: was cleared as soon as the ATTACKER's turn ended
		await main.show_message("THE DEFENDING POKEMON CAN'T USE POKE-POWERS NEXT TURN!")
		if main._should_bail(): return
	await main.check_all_knockouts()

# ── Unown Hidden Power (ex10-A … ex10-Z, plus ex10-! and ex10-?) ──────────────────────────────
# Each letter's Hidden Power is a distinct effect keyed by UID. Self-finishing at the end.

--- attack:Darkness Fang
TEXT: dmg=60 cost=DCC | 
FLAG run_damage_mismatch: printed 60, dealt 90 (text: )
