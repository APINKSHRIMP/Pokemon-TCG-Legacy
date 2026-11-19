# batch 5: base2-16, base3-53, basep-20, base1-2, base1-13, base1-59, base2-12, base2-35, base2-42, base2-45, base2-50, base2-51, base3-31, base5-40, basep-30, basep-31, ecard1-13, ecard2-85, gym1-22, gym2-9, gym2-73, neo3-27, neo4-32, gym1-51


=========== base2-16 Wigglytuff (Stage 1) score 5

--- attack:Do the Wave
TEXT: dmg=10+ cost=CCC | Does 10 damage plus 10 more damage for each of your Benched Pokémon.
FLAG b_wrap_no_match: name has handlers but none matches this text (falls to generic copy): Does 10 damage plus 10 more damage for each of your Benched Pokémon.
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



=========== base3-53 Psyduck (Basic) score 5

--- attack:Headache
TEXT: dmg= cost=P | Your opponent can't play Trainer cards during his or her next turn.
FLAG b_wrap_no_match: name has handlers but none matches this text (falls to generic copy): Your opponent can't play Trainer cards during his or her next turn.
HANDLER Attack_Effects.gd:34208  _r3_wrap("headache", "can't play a trainer card from his or her hand", func(atk, a, d, opp):
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



=========== basep-20 Psyduck (Basic) score 5

--- attack:Headache
TEXT: dmg= cost=P | Your opponent can't play Trainer cards during his or her next turn.
FLAG b_wrap_no_match: name has handlers but none matches this text (falls to generic copy): Your opponent can't play Trainer cards during his or her next turn.
HANDLER Attack_Effects.gd:34208  _r3_wrap("headache", "can't play a trainer card from his or her hand", func(atk, a, d, opp):
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



=========== base1-2 Blastoise (Stage 2) score 4

--- attack:Hydro Pump
TEXT: dmg=40+ cost=WWW | Does 40 damage plus 10 more damage for each Water Energy attached to Blastoise but not used to pay for this attack's Energy cost. Extra Water Energy after the 2nd doesn't count.
FLAG d_undispatched_uncovered: generic parser has no phrase for: extra water energy after the 2nd doesn't count.


=========== base1-13 Poliwrath (Stage 2) score 4

--- attack:Water Gun
TEXT: dmg=30+ cost=WWC | Does 30 damage plus 10 more damage for each Water Energy attached to Poliwrath but not used to pay for this attack's Energy cost. Extra Water Energy after the 2nd doesn't count.
FLAG d_undispatched_uncovered: generic parser has no phrase for: extra water energy after the 2nd doesn't count.


=========== base1-59 Poliwag (Basic) score 4

--- attack:Water Gun
TEXT: dmg=10+ cost=W | Does 10 damage plus 10 more damage for each Water Energy attached to Poliwag but not used to pay for this attack's Energy cost. Extra Water Energy after the 2nd don't count.
FLAG d_undispatched_uncovered: generic parser has no phrase for: extra water energy after the 2nd don't count.


=========== base2-12 Vaporeon (Stage 1) score 4

--- attack:Water Gun
TEXT: dmg=30+ cost=WWC | Does 30 damage plus 10 more damage for each Water Energy attached to Vaporeon but not used to pay for this attack's Energy cost. Extra Water Energy after the 2nd doesn't count.
FLAG d_undispatched_uncovered: generic parser has no phrase for: extra water energy after the 2nd doesn't count.


=========== base2-35 Exeggutor (Stage 1) score 4

--- attack:Teleport
TEXT: dmg= cost=P | Switch Exeggutor with 1 of your Benched Pokémon.
FLAG d_undispatched_uncovered: generic parser has no phrase for: switch {self} with 1 of your benched pokémon.


=========== base2-42 Persian (Stage 1) score 4

--- attack:Pounce
TEXT: dmg=30 cost=CCC | If the Defending Pokémon attacks Persian during your next turn, any damage done by the attack is reduced by 10 (after applying Weakness and Resistance). (Benching either Pokémon ends this effect.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (benching either pokémon ends this effect.)


=========== base2-45 Rhydon (Stage 1) score 4

--- attack:Ram
TEXT: dmg=50 cost=FFFF | Rhydon does 20 damage to itself. If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon. Switch the Pokémon even if Rhydon is knocked out.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (do the damage before switching the pokémon. | switch the pokémon even if {self} is knocked out.)


=========== base2-50 Cubone (Basic) score 4

--- attack:Snivel
TEXT: dmg= cost=C | If the Defending Pokémon attacks Cubone during your opponent's next turn, any damage done by the attack is reduced by 20 (after applying Weakness and Resistance). (Benching either Pokémon ends this effect.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (benching either pokémon ends this effect.)


=========== base2-51 Eevee (Basic) score 4

--- attack:Tail Wag
TEXT: dmg= cost=C | Flip a coin. If heads, the Defending Pokémon can't attack Eevee during your opponent's next turn. (Benching either Pokémon ends this effect.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (benching either pokémon ends this effect.)


=========== base3-31 Arbok (Stage 1) score 4

--- attack:Terror Strike
TEXT: dmg=10 cost=G | Flip a coin. If heads and if your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (do the damage before switching the pokémon.)


=========== base5-40 Dark Machoke (Stage 1) score 4

--- attack:Knock Back
TEXT: dmg=30 cost=FFC | If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (do the damage before switching the pokémon.)


=========== basep-30 Togepi (Basic) score 4

--- attack:Snivel
TEXT: dmg= cost=C | If the Defending Pokémon attacks Togepi during your opponent's next turn, any damage done to Togepi is reduced by 20 (before applying Weakness and Resistance). (Benching either Pokémon ends this effect.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (benching either pokémon ends this effect.)


=========== basep-31 Cleffa (Baby) score 4

--- attack:Eek
TEXT: dmg= cost=C | Draw 2 cards.
FLAG d_undispatched_uncovered: generic parser has no phrase for: draw 2 cards.


=========== ecard1-13 Gengar (Stage 2) score 4

--- attack:Hide in Shadows
TEXT: dmg=40 cost=PPC | Switch Gengar with 1 of your Benched Pokémon, if any.
FLAG d_undispatched_uncovered: generic parser has no phrase for: switch {self} with 1 of your benched pokémon, if any.


=========== ecard2-85 Horsea (Basic) score 4

--- attack:Reverse Thrust
TEXT: dmg=20 cost=CC | Switch Horsea with 1 of your Benched Pokémon, if any.
FLAG d_undispatched_uncovered: generic parser has no phrase for: switch {self} with 1 of your benched pokémon, if any.


=========== gym1-22 Brock's Rhyhorn (Basic) score 4

--- attack:Horn Toss
TEXT: dmg=20 cost=CC | If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (do the damage before switching the pokémon.)


=========== gym2-9 Koga's Beedrill (Stage 2) score 4

--- attack:Hyper Needle
TEXT: dmg=70 cost=CCC | Flip a coin. If tails, this attack does nothing. Either way, you can't use this attack again as long as Koga's Beedrill stays in play (even putting Koga's Beedrill on the Bench won't let you use it again).
FLAG d_undispatched_uncovered: generic parser has no phrase for: either way, you can't use this attack again as long as {self} stays in


=========== gym2-73 Giovanni's Magikarp (Basic) score 4

--- attack:Ancestral Memory
TEXT: dmg=40 cost=W | Flip a coin. If tails, this attack does nothing. Either way, you can't use this attack again as long as Giovanni's Magikarp stays in play (even putting Giovanni's Magikarp on the Bench won't let you use it again).
FLAG d_undispatched_uncovered: generic parser has no phrase for: either way, you can't use this attack again as long as {self} stays in


=========== neo3-27 Suicune (Basic) score 4

--- attack:Crystal Wave
TEXT: dmg=30+ cost=WWW | Flip a coin. If heads, this attack does 30 damage plus 10 more damage. If tails, this attack does 30 damage and, if your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (do the damage before switching the pokémon.)


=========== neo4-32 Dark Croconaw (Stage 1) score 4

--- attack:Clamping Jaw
TEXT: dmg=20 cost=WW | The Defending Pokémon can't retreat during your opponent's next turn. If the Defending Pokémon tries to attack during your opponent's next turn, your opponent flips a coin. If tails, that attack does nothing. (Benching either Pokémon ends this effect.)
FLAG d_undispatched_uncovered: generic parser has no phrase for: (benching either pokémon ends this effect.)


=========== gym1-51 Lt. Surge's Raticate (Stage 1) score 2

--- attack:Super Fang
TEXT: dmg=? cost=C | Does damage to the Defending Pokémon equal to half the Defending Pokémon's remaining HP (rounded up to the nearest 10).
FLAG f_data_damage: odd damage field '?'
HANDLER Attack_Effects.gd:383  _attack_dispatch["super fang"]   = func(atk, a, d, opp): await execute_super_fang(a, d, opp);          await _attack_finish(true,  0,   atk, a.metadata.get("types",["Colorless"]), opp)
[Attack_Effects.gd]
func execute_super_fang(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender == null or defender.current_hp <= 0:
		return
	# OLD ISSUE 294: the half-HP figure is the attack's BASE damage — Weakness, Resistance, PlusPower and
	# Defender then apply as normal (it used to be applied raw, ignoring all of them).
	var base = int(ceil(defender.current_hp / 2.0 / 10.0)) * 10
	await gym1_hit_active(attacker, defender, is_opponent, base)
	if main._should_bail(): return

# MIND SHOCK (Dark Alakazam, Dark Kadabra, Sabrina's Drowzee): damage ignoring W/R
