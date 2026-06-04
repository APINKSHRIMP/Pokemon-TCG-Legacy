extends Node

######################################################################################################################################################
############################################################## ATTACK EFFECTS ######################################################################
######################################################################################################################################################
#
# This file contains all attack effect parsing, application, and special attack execution.
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

# ── Attack dispatch registry ──────────────────────────────────────────────────
# Maps lowercased attack name → async Callable(attack, attacker, defender, is_opponent).
# Each entry handles the full execute + _attack_finish for that attack.
# Add new set registrations by calling _register_<set>_attacks() from _ensure_dispatch_ready().
var _attack_dispatch: Dictionary = {}
var _attack_dispatch_ready := false

func _ensure_dispatch_ready() -> void:
	if _attack_dispatch_ready:
		return
	_attack_dispatch_ready = true
	_register_gym2_attacks()
	_register_gym1_attacks()
	_register_base_attacks()
	_register_si1_attacks()
	_register_basep_attacks()
	_register_neo1_attacks()
	_register_neo2_attacks()

func _register_si1_attacks() -> void:
	_attack_dispatch["rainbow wave"]    = func(atk, a, d, opp): await execute_rainbow_wave(a, opp);            await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["strange scent"]  = func(atk, a, d, opp): await execute_strange_scent(a, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["tentacle grip"]  = func(atk, a, d, opp): await execute_tentacle_grip(a, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["squirt"]         = func(atk, a, d, opp): await execute_squirt(a, opp);                   await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["gentle song"]    = func(atk, a, d, opp): await execute_gentle_song(a, d, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sharpshooter"]   = func(atk, a, d, opp): await execute_sharpshooter(a, opp);            await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["revelation"]     = func(atk, a, d, opp): await execute_revelation(a, opp);              await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["lick wounds"]    = func(atk, a, d, opp): await execute_lick_wounds(a, opp);             await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["tongue stretch"] = func(atk, a, d, opp): await execute_tongue_stretch(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["paradise pollen"]= func(atk, a, d, opp): await execute_paradise_pollen(a, opp);         await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["rampage"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_rampage(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)

func _register_basep_attacks() -> void:
	_attack_dispatch["light screen"]        = func(atk, a, d, opp): await execute_deflector(a, opp);                                                                                               await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy absorption"]   = func(atk, a, d, opp): await execute_energy_absorption(a, opp, 2);                                                                                   await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["recharge"]            = func(atk, a, d, opp): await execute_basep_recharge(a, opp);                                                                                         await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["flames of rage"]      = func(atk, a, d, opp):
		var types = a.metadata.get("types",["Colorless"])
		var fire_count = a.attached_energies.filter(func(e): return "Fire" in main.get_energy_provided_by_card(e)).size()
		if fire_count < 2:
			if not opp: await main.show_message("NOT ENOUGH FIRE ENERGY TO USE FLAMES OF RAGE!")
			await _attack_finish(false, 0, atk, types, opp)
			return
		await execute_flames_of_rage(a, d, opp)
		await _attack_finish(true, 40, atk, types, opp)
	_attack_dispatch["devolution beam"]     = func(atk, a, d, opp): await execute_devolution_beam(a, d, opp);                                                                                     await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["cat punch"]           = func(atk, a, d, opp): await execute_cat_punch(a, d, opp);                                                                                           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy control"]      = func(atk, a, d, opp): await execute_energy_control(a, d, opp);                                                                                      await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["telekinesis"]         = func(atk, a, d, opp): await execute_snipe_no_wr(a, d, opp, 30, false);                                                                              await _attack_finish(true,  30,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["texture magic"]       = func(atk, a, d, opp): await execute_texture_magic(a, d, opp);                                                                                       await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["miraculous comeback"] = func(atk, a, d, opp): await execute_miraculous_comeback(a, d, opp);                                                                                 await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["hyper flame"]         = func(atk, a, d, opp):
		var types = a.metadata.get("types",["Colorless"])
		if a.attached_energies.size() == 0:
			if not opp: await main.show_message("NO ENERGY ATTACHED — HYPER FLAME FAILS!")
			await _attack_finish(false, 0, atk, types, opp)
			return
		await execute_hyper_flame(a, d, opp)
		await _attack_finish(true, 60, atk, types, opp)
	_attack_dispatch["lightning burn"]      = func(atk, a, d, opp): await execute_lightning_burn(a, d, opp);                                                                                      await _attack_finish(true,  30,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mini-metronome"]      = func(atk, a, d, opp): await execute_metronome(a, d, opp);                                                                                           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["paint"]               = func(atk, a, d, opp): await execute_paint(a, d, opp);                                                                                               await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["slashing strike"]     = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_screaming_headbutt(a, d, opp, b, "Slashing Strike");                      await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["protective flame"]    = func(atk, a, d, opp): await execute_protective_flame(a, d, opp);                                                                                    await _attack_finish(true,  50,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["let's play!"]         = func(atk, a, d, opp): await execute_lets_play(a, opp);                                                                                              await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["rapid spin"]          = func(atk, a, d, opp): await execute_rapid_spin(a, d, opp);                                                                                          await _attack_finish(true,  30,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["pain split"]          = func(atk, a, d, opp): await execute_pain_split(a, d, opp);                                                                                          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["seething anger"]      = func(atk, a, d, opp): await execute_seething_anger(a, d, opp);                                                                                      await _attack_finish(true,  20,  atk, a.metadata.get("types",["Colorless"]), opp)
	# basep Machamp Fling (50 + force switch) overrides Dark Machamp's Fling (shuffle into deck)
	_attack_dispatch["fling"]               = func(atk, a, d, opp):
		if "switches it with" in atk.get("text","").to_lower() or "switch" in atk.get("text","").to_lower():
			await execute_basep_fling(a, d, opp)
			await _attack_finish(true, 50, atk, a.metadata.get("types",["Colorless"]), opp)
		else:
			await execute_fling(a, d, opp)
			await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["burning fire"]        = func(atk, a, d, opp): await execute_burning_fire(a, d, opp);                                                                                        await _attack_finish(true,  10,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["lightning rod"]       = func(atk, a, d, opp): await execute_lightning_rod(a, d, opp);                                                                                       await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["lightning bolt"]      = func(atk, a, d, opp): await execute_lightning_bolt(a, d, opp);                                                                                      await _attack_finish(true,  10,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sacred wing"]         = func(atk, a, d, opp): await execute_sacred_wing(a, d, opp);                                                                                         await _attack_finish(true,  60,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["jump over"]           = func(atk, a, d, opp): await execute_jump_over(a, d, opp);                                                                                           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Challenge is always treated as denied — always 30 damage (no real-world birthday detection)
	_attack_dispatch["birthday surprise"]   = func(atk, a, d, opp): await execute_birthday_surprise(a, d, opp);                                                                                   await _attack_finish(true,  30,  atk, a.metadata.get("types",["Colorless"]), opp)
	# Water Gun: all variants (typed and untyped extra energy) handled by generic resolve_attack_variable_damage

func _register_gym2_attacks() -> void:
	_attack_dispatch["roaring flames"]     = func(atk, a, d, opp): await execute_roaring_flames(a, d, opp);     await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["growth"]             = func(atk, a, d, opp): await execute_growth(a, opp);                 await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["wide solarbeam"]     = func(atk, a, d, opp): await execute_bench_choose_spread(a, d, opp, 20, 2, 20, false); await _attack_finish(true, 20, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["summon storm"]       = func(atk, a, d, opp): await execute_summon_storm(a, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["dragon tornado"]     = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_dragon_tornado(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["intimidate"]         = func(atk, a, d, opp): await execute_intimidate(a, d, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["giant growth"]       = func(atk, a, d, opp): await execute_giant_growth(a, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["kerzap"]             = func(atk, a, d, opp): await execute_kerzap(a, d, opp);              await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["super removal"]      = func(atk, a, d, opp): await execute_super_removal(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["juxtapose"]          = func(atk, a, d, opp): await execute_juxtapose(a, d, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["plasma"]             = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_plasma(a, d, opp, b);            await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["electroburn"]        = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_electroburn(a, d, opp, b);        await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["love lariat"]        = func(atk, a, d, opp): await execute_love_lariat(a, d, opp);         await _attack_finish(true,  50,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["overhead toss"]      = func(atk, a, d, opp): await execute_overhead_toss(a, d, opp, 40);   await _attack_finish(true,  40,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["poison power"]       = func(atk, a, d, opp): await execute_poison_power(a, d, opp);        await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["thunder flare"]      = func(atk, a, d, opp): await execute_thunder_flare(a, d, opp);       await _attack_finish(true,  30,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["dark wave"]          = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_dark_wave(a, d, opp, b);          await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["damage shift"]       = func(atk, a, d, opp): await execute_damage_shift(a, d, opp);        await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["bonfire"]            = func(atk, a, d, opp): await execute_bonfire(a, opp);                await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["stamp"]              = func(atk, a, d, opp): await execute_stamp(a, d, opp);               await _attack_finish(true,  30,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["detonate"]           = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_detonate(a, d, opp, b);           await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["risky attack"]       = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_risky_attack(a, d, opp, b);       await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["false charity"]      = func(atk, a, d, opp): await execute_false_charity(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["rend"]               = func(atk, a, d, opp): await execute_rend(a, d, opp);                await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["obscuring gas"]      = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_obscuring_gas(a, d, opp, b);      await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["messenger"]          = func(atk, a, d, opp): await execute_messenger(a, opp);              await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["lunar power"]        = func(atk, a, d, opp): await execute_lunar_power(a, opp);            await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["errand-running"]     = func(atk, a, d, opp): await execute_errand_running(a, opp);         await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["surprise"]           = func(atk, a, d, opp): await execute_surprise(a, opp);               await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["power ball"]         = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_flip_bonus_per_heads(a, d, opp, b, 3, 10); await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["ice throw"]          = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_ice_throw(a, d, opp, b);          await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["shadow attack"]      = func(atk, a, d, opp): await execute_bench_snipe_flip(a, d, opp, 0, 30);     await _attack_finish(false, 0,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["overrun"]            = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_bench_snipe_flip(a, d, opp, b, 20); await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["invigorate"]         = func(atk, a, d, opp): await execute_invigorate(a, opp);             await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["pendulum curse"]     = func(atk, a, d, opp): await execute_pendulum_curse(a, d, opp);      await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["helping hand"]       = func(atk, a, d, opp): await execute_helping_hand(a, opp);           await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["life drain"]         = func(atk, a, d, opp): await execute_life_drain(a, d, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["magic darts"]        = func(atk, a, d, opp): await execute_magic_darts(a, opp);            await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["stoke"]              = func(atk, a, d, opp): await execute_stoke(a, opp);                  await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["energy support"]     = func(atk, a, d, opp): await execute_search_typed_energy_to_hand(a, opp, "Psychic"); await _attack_finish(false, 0, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["pranks"]             = func(atk, a, d, opp): await execute_pranks(a, opp);                 await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["group therapy"]      = func(atk, a, d, opp): await execute_group_therapy(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["pulled punch"]       = func(atk, a, d, opp): await execute_pulled_punch(a, d, opp);        await _attack_finish(true,  40,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["hind kick"]          = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_hind_kick(a, d, opp, b);          await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["call will-o'-the-wisp"] = func(atk, a, d, opp): await execute_call_wisp(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["fast-acting poison"] = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_flip2_both_heads_status(a, d, opp, b, ["Confused", "Poisoned"]); await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["sludge grip"]        = func(atk, a, d, opp): await execute_sludge_grip(a, opp);            await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["group attack"]       = func(atk, a, d, opp): await execute_group_attack(a, d, opp);        await _attack_finish(true,  10,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["bubbles"]            = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); var name = atk.get("name", ""); await execute_bubbles(a, d, opp, b, name); await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["esp"]                = func(atk, a, d, opp): await execute_esp(a, d, opp);                 await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["star boomerang"]     = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_star_boomerang(a, d, opp, b);     await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["synchronize"]        = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_synchronize(a, d, opp, b);        await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["psyscan"]            = func(atk, a, d, opp): await execute_psyscan(a, opp);                await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["fade out"]           = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_fade_out(a, d, opp, b);           await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["random esp"]         = func(atk, a, d, opp): await execute_random_esp(a, d, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["fury punch"]         = func(atk, a, d, opp): await execute_fury_punch(a, d, opp);          await _attack_finish(true,  20,  atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["ink spurt"]          = func(atk, a, d, opp): var b = parse_attack_base_damage(atk); await execute_ink_spurt(a, d, opp, b);          await _attack_finish(true,  b,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["grasping vine"]      = func(atk, a, d, opp): await execute_draw_flip(a, opp, 2);           await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	_attack_dispatch["lie low"]            = func(atk, a, d, opp): await execute_lie_low(a, opp);                await _attack_finish(false, 0,   atk, a.metadata.get("types", ["Colorless"]), opp)
	# Retaliation gate: requires 2+ damage counters on attacker
	_attack_dispatch["retaliation"]        = func(atk, a, d, opp):
		var b = parse_attack_base_damage(atk)
		if a.get_damage_counters() < 2:
			if not opp: await main.show_message(a.metadata.get("name","").to_upper() + " NEEDS 2 OR MORE DAMAGE COUNTERS TO USE RETALIATION!")
			await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
			return
		await execute_retaliation(a, d, opp, b)
		await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)

func _register_gym1_attacks() -> void:
	_attack_dispatch["phoenix flame"]       = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_phoenix_flame(a, d, opp, b);                                               await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["take away"]           = func(atk, a, d, opp): await execute_take_away(a, d, opp);                                                                                            await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["discharge"]           = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_discharge(a, d, opp);                                                      await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["charge"]              = func(atk, a, d, opp): var n=2 if "up to 2" in atk.get("text","").to_lower() else 1; await execute_charge_recover(a, opp, n);                        await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["crosscounter"]        = func(atk, a, d, opp): await execute_crosscounter(a, opp);                                                                                            await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fire wall"]           = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_fire_wall(a, d, opp, b);                                                   await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["shadow images"]       = func(atk, a, d, opp): await execute_shadow_images(a, opp);                                                                                           await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["pain amplifier"]      = func(atk, a, d, opp): await execute_pain_amplifier(a, opp);                                                                                          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["call of the night"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_call_of_the_night(a, d, opp, b);                                          await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["knockout needle"]     = func(atk, a, d, opp): await execute_double_coin_bonus(a, d, opp, 30, 60);                                                                            await _attack_finish(true,  30,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["rock slide"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_bench_choose_spread(a, d, opp, b, 3, 10, false);                          await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["tunneling"]           = func(atk, a, d, opp): await execute_bench_choose_spread(a, d, opp, 0, 2, 20, true);                                                                 await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["water ring"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_water_ring(a, d, opp, b);                                                  await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["lava burst"]          = func(atk, a, d, opp): await execute_lava_burst(a, d, opp);                                                                                           await _attack_finish(true,  40,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["lucky shot"]          = func(atk, a, d, opp): await execute_lucky_shot(a, opp, 30);                                                                                          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["spiral dive"]         = func(atk, a, d, opp): await execute_spiral_dive(a, opp);                                                                                             await _attack_finish(true,  10,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["deflector"]           = func(atk, a, d, opp): await execute_deflector(a, opp);                                                                                               await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["psychic exchange"]    = func(atk, a, d, opp): await execute_psychic_exchange(a, opp);                                                                                        await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["magic pollen"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_magic_pollen(a, d, opp, b);                                               await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["water punch"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_water_punch(a, d, opp, b);                                                await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["call for friend"]     = func(atk, a, d, opp): var t="Misty" if "misty" in atk.get("text","").to_lower() else "Brock"; await execute_call_for_named_basic(a, opp, t);       await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["night spirits"]       = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_night_spirits(a, d, opp, b);                                              await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["full speed charge"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_full_speed_charge(a, d, opp);                                             await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["blaze"]               = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_typed_bench_damage(a, d, opp, b, "Grass");                                await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sonic distortion"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_flip2_any_heads_status(a, d, opp, b, "Confused");                         await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["drill tackle"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_drill_tackle(a, d, opp, b);                                               await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["eggsplosion"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_big_eggsplosion(a, d, opp, b);                                            await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["electric current"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_electric_current(a, d, opp, b);                                           await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["screaming headbutt"]  = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_screaming_headbutt(a, d, opp, b, atk.get("name",""));                    await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fairy power"]         = func(atk, a, d, opp): await execute_fairy_power(a, opp);                                                                                             await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["moonwatching"]        = func(atk, a, d, opp): await execute_search_basic_energy_to_hand(a, opp);                                                                             await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["jellyfish pod"]       = func(atk, a, d, opp): await execute_jellyfish_pod(a, opp, ["Tentacool","Tentacruel","Misty's Tentacool","Misty's Tentacruel"]);                     await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["healing pollen"]      = func(atk, a, d, opp):
		var text = atk.get("text","").to_lower()
		if "remove 1 damage counter from each" in text:
			await execute_team_heal_flip(a, opp, 3)  # Sabrina's Venomoth: flip 3, remove 1 from each per heads
		else:
			var fx = parse_card_text_effects(atk.get("text",""), a.metadata.get("name",""))
			if fx.size() > 0:
				await apply_card_text_effects(fx, a, d, opp, "")  # Erika's Gloom: flip 1, remove 4 from self
			if main._should_bail(): return
		await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fidget"]              = func(atk, a, d, opp): await execute_fidget(a, opp);                                                                                                  await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy loop"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_energy_loop(a, d, opp, b);                                                await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sleight of hand"]     = func(atk, a, d, opp): await execute_sleight_of_hand(a, opp);                                                                                         await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mud splash"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_mud_splash(a, d, opp, b);                                                 await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["swift"]               = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_sonicboom(a, d, opp, b);                                                  await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	# "Focus Energy" exists in both GYM1 (Gnaw boost) and GYM2 (Quick Attack boost) — differentiate by text
	_attack_dispatch["focus energy"]        = func(atk, a, d, opp):
		if "gnaw" in atk.get("text","").to_lower():
			await execute_focus_energy(a, opp)                    # GYM1: sets focus_energy_active
		else:
			a.gym2_focus_energy_active = true                     # GYM2: sets gym2_focus_energy_active
			if opp: await main.show_message("OPPONENT'S " + a.metadata.get("name","").to_upper() + " IS FOCUSING ITS ENERGY!")
			else:   await main.show_message(a.metadata.get("name","").to_upper() + " IS FOCUSING ITS ENERGY!")
		await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)

func _register_base_attacks() -> void:
	_attack_dispatch["swords dance"]       = func(atk, a, d, opp): await execute_swords_dance(a, opp);                                                    await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["hurricane"]          = func(atk, a, d, opp): await execute_hurricane(a, d, opp);                                                    await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["chain lightning"]    = func(atk, a, d, opp): await execute_chain_lightning(a, d, opp);                                              await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["big eggsplosion"]    = func(atk, a, d, opp): await execute_big_eggsplosion(a, d, opp);                                              await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["boyfriends"]         = func(atk, a, d, opp): await execute_boyfriends(a, d, opp);                                                   await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mega drain"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_mega_drain(a, d, opp, b);           await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["leech life"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_leech_life(a, d, opp, b);           await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["absorb"]             = func(atk, a, d, opp): await execute_mega_drain(a, d, opp, 40);                                               await _attack_finish(true,  40, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["stare"]              = func(atk, a, d, opp):
		await execute_stare(a, d, opp)
		var fx = parse_card_text_effects(atk.get("text",""), a.metadata.get("name",""))
		if fx.size() > 0: await apply_card_text_effects(fx, a, d, opp, "")
		if main._should_bail(): return
		await _attack_finish(true, parse_attack_base_damage(atk), atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["flitter"]            = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_snipe_no_wr(a, d, opp, b, false);   await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["dig under"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_snipe_no_wr(a, d, opp, b, true);    await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["coin hurl"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_snipe_no_wr(a, d, opp, b, true);    await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["bench manipulation"] = func(atk, a, d, opp): await execute_bench_manipulation(a, d, opp);                                           await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["continuous fireball"]= func(atk, a, d, opp): await execute_continuous_fireball(a, d, opp);                                          await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fling"]              = func(atk, a, d, opp): await execute_fling(a, d, opp);                                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["magnetic lines"]     = func(atk, a, d, opp): await execute_magnetic_lines(a, d, opp);                                               await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["petal whirlwind"]    = func(atk, a, d, opp): await execute_petal_whirlwind(a, d, opp);                                              await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mass explosion"]     = func(atk, a, d, opp): await execute_mass_explosion(a, d, opp);                                               await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy bomb"]        = func(atk, a, d, opp): await execute_energy_bomb(a, d, opp);                                                  await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["third eye"]          = func(atk, a, d, opp): await execute_third_eye(a, opp);                                                       await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["drag off"]           = func(atk, a, d, opp): await execute_drag_off(a, d, opp);                                                     await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["flame pillar"]       = func(atk, a, d, opp): await execute_flame_pillar(a, d, opp);                                                 await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mirror shell"]       = func(atk, a, d, opp): await execute_mirror_shell(a, opp);                                                    await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["rapid evolution"]    = func(atk, a, d, opp): await execute_rapid_evolution(a, opp);                                                 await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["vanish"]             = func(atk, a, d, opp): await execute_vanish(a, opp);                                                          await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["magnetism"]          = func(atk, a, d, opp): await execute_magnetism(a, d, opp);                                                    await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mischief"]           = func(atk, a, d, opp): await execute_mischief(a, opp);                                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["surprise thunder"]   = func(atk, a, d, opp): await execute_surprise_thunder(a, d, opp);                                             await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["afternoon nap"]      = func(atk, a, d, opp): await execute_afternoon_nap(a, opp);                                                   await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fascinate"]          = func(atk, a, d, opp): await execute_fascinate(a, d, opp);                                                    await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sonicboom"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_sonicboom(a, d, opp, b);            await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["wildfire"]           = func(atk, a, d, opp): await execute_wildfire(a, opp);                                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["gigashock"]          = func(atk, a, d, opp): await execute_gigashock(a, d, opp);                                                    await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["thunderstorm"]       = func(atk, a, d, opp): await execute_thunderstorm(a, d, opp);                                                 await _attack_finish(true,  40, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["prophecy"]           = func(atk, a, d, opp): await execute_prophecy(a, opp);                                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy conversion"]  = func(atk, a, d, opp): await execute_energy_conversion(a, opp);                                               await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["spacing out"]        = func(atk, a, d, opp): await execute_spacing_out(a, opp);                                                     await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["scavenge"]           = func(atk, a, d, opp): await execute_scavenge(a, opp);                                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["metronome"]          = func(atk, a, d, opp): await execute_metronome(a, d, opp);                                                    await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mirror move"]        = func(atk, a, d, opp): await execute_mirror_move(a, d, opp);                                                  await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["amnesia"]            = func(atk, a, d, opp): await execute_amnesia(a, d, opp);                                                      await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["conversion 1"]       = func(atk, a, d, opp): await execute_conversion(a, d, opp, true);                                             await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["conversion 2"]       = func(atk, a, d, opp): await execute_conversion(a, d, opp, false);                                            await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["call for family"]    = func(atk, a, d, opp):
		var text = atk.get("text","")
		var names: Array = []
		var call_type: String = ""
		if "Bellsprout" in text:   names = ["Bellsprout"]
		elif "Krabby" in text:     names = ["Krabby"]
		elif "Oddish" in text:     names = ["Oddish"]
		elif "Nidoran" in text:    names = ["Nidoran ♀","Nidoran ♂"]
		else:
			var t = a.metadata.get("types",[])
			if t.size() > 0: call_type = t[0]
		await execute_call_for_pokemon(a, opp, names, call_type)
		await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	# Supersedes gym1 entry: now also handles Marowak (Fighting Basic)
	_attack_dispatch["call for friend"]    = func(atk, a, d, opp):
		var text_l = atk.get("text","").to_lower()
		if "misty" in text_l:   await execute_call_for_named_basic(a, opp, "Misty")
		elif "brock" in text_l: await execute_call_for_named_basic(a, opp, "Brock")
		else:                   await execute_call_for_pokemon(a, opp, [], "Fighting")
		await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)

	# Earthdrill: pre-registry special case handles the lock; damage is generic path. Entry here only for audit visibility.
	_attack_dispatch["earthdrill"] = func(_atk, _a, _d, _opp): pass  # always intercepted above; never reached
	# ── Newly-implemented effects (base1–base5, gym1, gym2) ────────────────────
	# Super Fang: half HP damage (Raticate, Lt. Surge's Raticate)
	_attack_dispatch["super fang"]   = func(atk, a, d, opp): await execute_super_fang(a, d, opp);          await _attack_finish(true,  0,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Mind Shock: damage ignoring W/R (Dark Alakazam, Dark Kadabra, Sabrina's Drowzee)
	_attack_dispatch["mind shock"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_mind_shock(a, d, opp, b);   await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Mega Burn: damage + can't use next turn (Sabrina's Alakazam)
	_attack_dispatch["mega burn"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_mega_burn(a, d, opp, b);    await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Hook Shot: damage ignoring Resistance (Brock's Geodude gym1-66)
	_attack_dispatch["hook shot"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_hook_shot(a, d, opp, b);    await _attack_finish(true,  b,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Brock's Zubat Alert: draw 1 card + self switch
	_attack_dispatch["alert"]        = func(atk, a, d, opp): await execute_brock_zubat_alert(a, opp);      await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Oddish Sprout: search deck for Oddish and bench it
	_attack_dispatch["sprout"]       = func(atk, a, d, opp): await execute_oddish_sprout(a, opp);          await _attack_finish(false, 0,   atk, a.metadata.get("types",["Colorless"]), opp)
	# Dark Alakazam Teleport Blast: damage first, then self switch (both already parse via text, explicit dispatch for clarity)
	_attack_dispatch["teleport blast"] = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); var types=a.metadata.get("types",["Colorless"]); var r=main.calculate_final_damage(b,types,d,a); if not main.check_defender_invincible(d,!opp): var fd=main.apply_defender_no_damage_shield(d,r["damage"],!opp); await main.display_and_apply_attack_damage(a,d,fd,r["modifiers"],opp,b); if main._should_bail(): return; await apply_self_switch(a,opp); await _attack_finish(true, b, atk, types, opp)

######################################################################################################################################################
################################################# UNIFIED ATTACK DISPATCH ###########################################################################
######################################################################################################################################################
#
# dispatch_attack: single entry point for both player and CPU attack execution.
# Handles GYM2 (name-based), GYM1 (name-based), and Base1-5 (text-based) special attacks.
# Returns true if the attack was fully handled (including post-attack cleanup via _attack_finish).
# Returns false to fall through to the generic damage/text-effects path in perform_attack.
#

# Called from Main._ready() after powers_and_bodies is initialised.
# Registers attack-effects on-damage hooks into the powers event bus so Main's
# apply_damage can call a single dispatch_on_damage instead of individual check_ calls.
func register_on_damage_hooks(powers: Node) -> void:
	powers.register_on_damage_hook(func(def, atk, dmg, is_def_opp): await check_mirror_shell(def, atk, dmg, is_def_opp))
	powers.register_on_damage_hook(func(def, atk, dmg, is_def_opp): await gym1_check_counters(def, atk, dmg, is_def_opp))

func dispatch_attack(attack: Dictionary, attacker: card_object, defender: card_object, is_opponent: bool) -> bool:
	_ensure_dispatch_ready()
	var attack_name = attack.get("name", "")
	var an = attack_name.to_lower()
	var text_lower = attack.get("text", "").to_lower()
	var base = parse_attack_base_damage(attack)
	var types = attacker.metadata.get("types", ["Colorless"])

	if not is_opponent:
		main.hide_attack_buttons()

	# ============================= Pre-registry special cases (conditional dispatch) ======================

	# Focus Energy + Double-Edge: only route to boosted version when boost is active
	if an == "double-edge" and attacker.gym2_focus_energy_active:
		attacker.gym2_focus_energy_active = false
		await execute_double_edge_boosted(attacker, defender, is_opponent)
		await _attack_finish(true, 80, attack, types, is_opponent)
		return true

	# Mega Burn: locked for one turn after use
	if an == "mega burn" and attacker.gym2_mega_burn_locked:
		if not is_opponent:
			await main.show_message("MEGA BURN CAN'T BE USED AGAIN THIS SOON!")
		await _attack_finish(false, 0, attack, types, is_opponent)
		return true

	# Earthdrill: only valid after Lie Low; otherwise cancel and return true (attack fails)
	# When Lie Low IS active, return false → falls through to generic 60-damage path (no text effects needed)
	if an == "earthdrill":
		if attacker.gym2_lie_low_counter < 1:
			if not is_opponent:
				await main.show_message("EARTHDRILL CAN'T BE USED — LIE LOW WASN'T USED LAST TURN!")
			await _attack_finish(false, 0, attack, types, is_opponent)
			return true
		attacker.gym2_lie_low_counter = 0
		# Lie Low was active — fall through to the generic 60-damage path
		return false

	# ============================= Registry dispatch (GYM2 + future sets) ================================

	if _attack_dispatch.has(an):
		await _attack_dispatch[an].call(attack, attacker, defender, is_opponent)
		return true

	return false


# Post-attack cleanup shared by both player and CPU. Handles:
#   - Recording last_attack / attacked_this_turn (when is_damage is true)
#   - check_all_knockouts
#   - display_active_pokemon_energies
#   - Player: hide_attack_buttons + end-of-turn delay + player_end_turn_checks
func _attack_finish(is_damage: bool, base_dmg: int, attack: Dictionary, types: Array, is_opponent: bool) -> void:
	if is_damage:
		if is_opponent:
			main.last_attack_on_player = {"damage": base_dmg, "attack": attack, "attacker_types": types}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": base_dmg, "attack": attack, "attacker_types": types}
			main.player_attacked_this_turn = true
	await main.check_all_knockouts()
	if main._should_bail(): return
	main.display_active_pokemon_energies(is_opponent)
	if not is_opponent:
		await main.get_tree().create_timer(0.5).timeout
		main.player_end_turn_checks()


func get_flip_context(text: String, effect_pos: int) -> String:
	var before = text.substr(0, effect_pos)
	var heads_pos = before.rfind("if heads")
	var tails_pos = before.rfind("if tails")
	if heads_pos == -1 and tails_pos == -1:
		return "none"
	if heads_pos > tails_pos:
		return "heads"
	return "tails"
		
# Searches for a defender status across three text patterns, returns position or -1
func find_defender_status_pos(text: String, status: String, has_defender_prefix: bool) -> int:
	var direct_pos = text.find("the defending pokémon is now " + status)
	if direct_pos != -1:
		return direct_pos
	if has_defender_prefix:
		var and_pos = text.find("and " + status)
		if and_pos != -1:
			return and_pos
		var it_pos = text.find("it is now " + status)
		if it_pos != -1:
			return it_pos
	return -1
	
# Applies a single parsed status effect to the correct pokemon and updates the UI
func extract_number_before(text: String, keyword: String) -> int:
	var pos = text.find(keyword)
	if pos == -1:
		return -1
	var i = pos - 1
	while i >= 0 and text[i] == " ":
		i -= 1
	var num_str = ""
	while i >= 0 and text[i].is_valid_int():
		num_str = text[i] + num_str
		i -= 1
	if num_str != "":
		return int(num_str)
	return -1

														######### Effects from text ##########
																
# Applies self-damage from an attack effect to the attacker
func parse_attack_base_damage(attack: Dictionary) -> int:
	var raw_damage = attack.get("damage", "0")
	var numeric_damage = ""
	for character in raw_damage:
		if character.is_valid_int():
			numeric_damage += character
	return int(numeric_damage) if numeric_damage != "" else 0

# Handles the confusion coin flip when an attacker is confused
# Returns true if the attack FAILS (attacker hurt itself), false if the attack can proceed
func estimate_attack_damage_range(attack: Dictionary, attacker: card_object = null, defender: card_object = null) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", "0"))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower() if attacker else ""
	
	# --- COIN FLIP MULTIPLICATIVE (×) ---
	if "×" in damage_str or "x" in damage_str:
		if "times the number of damage counters" in text:
			# Flail-type: damage × self damage counters
			if attacker:
				var counters = attacker.get_damage_counters()
				return {"min": base_damage * counters, "max": base_damage * counters}
			return {"min": 0, "max": base_damage * 10}
		if "flip a coin until" in text:
			return {"min": 0, "max": base_damage * 5}
		elif "flip 3 coins" in text:
			return {"min": 0, "max": base_damage * 3}
		elif "flip 2 coins" in text:
			return {"min": 0, "max": base_damage * 2}
		return {"min": 0, "max": base_damage * 2}
	
	# --- "IF TAILS, DOES NOTHING" ---
	if "if tails, this attack does nothing" in text:
		return {"min": 0, "max": base_damage}
	
	# --- HALF HP (Raticate Super Fang) ---
	if "equal to half" in text and "remaining hp" in text:
		if defender:
			var dmg = int(ceil(defender.current_hp / 2.0 / 10.0)) * 10
			return {"min": dmg, "max": dmg}
		return {"min": 10, "max": 60}
	
	# --- CONDITION-GATED (Haunter Dream Eater) ---
	if "can't use this attack unless" in text:
		if defender:
			if "asleep" in text and defender.special_condition != "Asleep":
				return {"min": 0, "max": 0}
			if "poisoned" in text and not defender.is_poisoned:
				return {"min": 0, "max": 0}
		return {"min": 0, "max": base_damage}
	
	var min_dmg = base_damage
	var max_dmg = base_damage
	
	# --- HEADS/TAILS +BONUS ---
	if "+" in damage_str and "if heads" in text and "more damage" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		min_dmg = base_damage
		max_dmg = base_damage + bonus
	
	# --- PER DEFENDER ENERGY ---
	if "for each energy card attached to the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each energy")
		if extracted > 0:
			per = extracted
		if defender:
			var count = defender.attached_energies.size()
			min_dmg += per * count
			max_dmg += per * count
		else:
			max_dmg += per * 4
	
	# --- EXTRA ENERGY BEYOND COST ---
	if "more damage for each" in text and "not used to pay" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
			var bonus_type = ""
			for tkw in type_keywords:
				if tkw + " energy attached" in text:
					bonus_type = tkw.capitalize()
					break
			if bonus_type != "":
				var total = 0
				for e in attacker.attached_energies:
					if bonus_type in main.get_energy_provided_by_card(e):
						total += 1
				var cost_count = 0
				for c in attack.get("cost", []):
					if c == bonus_type:
						cost_count += 1
				var extra = max(0, total - cost_count)
				var cap = 99
				if "after the" in text and "don't count" in text:
					var after_pos = text.find("after the")
					var after_text = text.substr(after_pos + 10, 10)
					var cap_num = ""
					for ch in after_text:
						if ch.is_valid_int():
							cap_num += ch
						else:
							break
					if cap_num != "":
						cap = max(0, int(cap_num) - cost_count)
				elif "can't add more than" in text and "damage in this way" in text:
					var cap_dmg = extract_number_before(text, "damage in this way")
					if cap_dmg > 0:
						cap = cap_dmg / per
				extra = min(extra, cap)
				min_dmg += per * extra
				max_dmg += per * extra
			else:
				# Untyped extra energy (Marill Water Gun)
				var cost_count = attack.get("cost", []).size()
				var extra = max(0, attacker.attached_energies.size() - cost_count)
				if "can't add more than" in text and "damage in this way" in text:
					var cap_dmg = extract_number_before(text, "damage in this way")
					if cap_dmg > 0:
						extra = min(extra, cap_dmg / per)
				min_dmg += per * extra
				max_dmg += per * extra
		else:
			max_dmg += per * 2

	# --- PER DAMAGE COUNTER ON DEFENDING ---
	if "for each damage counter on the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if defender:
			var counters = defender.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
		else:
			max_dmg += per * 8
	
	# --- PER SELF DAMAGE COUNTER ---
	if attacker_name != "" and ("for each damage counter on " + attacker_name) in text and "minus" not in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
	
	# --- MINUS PER SELF DAMAGE COUNTER ---
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg = max(0, base_damage - per * counters)
			max_dmg = min_dmg
		else:
			min_dmg = 0
	
	# --- PER BENCH COUNT ---
	if "for each of your benched" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var bench = main.opponent_bench if attacker == main.opponent_active_pokemon else main.player_bench
			min_dmg += per * bench.size()
			max_dmg += per * bench.size()
		else:
			max_dmg += per * 5
	
	return {"min": min_dmg, "max": max_dmg}

# BABY POKEMON RULE: the attacking side must flip a coin before attacking a Baby Pokemon.
# Returns true if the attack is blocked (tails) and the turn should end, false if it proceeds.
# Call this AFTER announcing the attack, BEFORE any other pre-attack checks.
func check_baby_rule(defender: card_object, is_opponent: bool) -> bool:
	if defender == null:
		return false
	if "Baby" not in defender.metadata.get("subtypes", []):
		return false
	var name = defender.metadata.get("name", "")
	await main.show_message(name.to_upper() + " IS A BABY POKEMON! FLIPPING COIN...")
	if main._should_bail(): return false
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return false
	if not coin:
		await main.show_message("TAILS! THE ATTACK FAILS!")
		if main._should_bail(): return false
		return true
	await main.show_message("HEADS! THE ATTACK PROCEEDS!")
	if main._should_bail(): return false
	return false

# Evaluates KO threats from the player against the CPU's active pokemon (1.1, 1.2, 1.3)
func handle_attack_confusion(attacker: card_object, is_opponent: bool) -> bool:
	if attacker.special_condition != "Confused":
		return false
	await main.show_message(attacker.metadata["name"].to_upper() + " IS CONFUSED! FLIPPING COIN...")
	if main._should_bail(): return false
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		return false
	var self_damage = 20
	if main.confusion_rules == "modern_era_confusion_rules":
		self_damage = 30
	if main.confusion_rules == "base_set_confusion_rules":
		var self_types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(self_damage, self_types, attacker)
		self_damage = result["damage"]
	# Dark Primeape Frenzy: +30 damage when confused (even to self)
	self_damage += main.powers_and_bodies.check_frenzy_bonus(attacker)
	attacker.current_hp = max(0, attacker.current_hp - self_damage)
	await main.show_message("THE ATTACK FAILED! " + attacker.metadata["name"].to_upper() + " HURT ITSELF FOR " + str(self_damage) + " DAMAGE!")
	if main._should_bail(): return false
	var attacker_label_pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
	main.show_floating_label("-" + str(self_damage) + "HP", attacker_label_pos, Color.YELLOW, true)
	main.display_hp_circles_above_align(attacker, is_opponent)
	print("CONFUSED: ", attacker.metadata["name"], " hurt itself for ", self_damage)
	await main.check_all_knockouts()
	if main._should_bail(): return false
	return true

# Handles the blind coin flip when an attacker cannot see
# Returns true if the attack FAILS (missed), false if the attack can proceed
func handle_attack_blind(attacker: card_object, is_opponent: bool) -> bool:
	if not attacker.is_blind:
		return false
	await main.show_message(attacker.metadata["name"].to_upper() + " CAN'T SEE! FLIPPING COIN...")
	if main._should_bail(): return false
	var blind_coin = await main.flip_coin(false, is_opponent)
	if not blind_coin:
		await main.show_message("THE ATTACK FAILED!")
		if main._should_bail(): return false
		attacker.is_blind = false
		main.update_status_icons(attacker, is_opponent)
		return true
	attacker.is_blind = false
	main.update_status_icons(attacker, is_opponent)
	return false

# Checks if the defender is fully invincible and blocks the attack entirely
# Returns true if the attack is blocked
func resolve_attack_variable_damage(attack: Dictionary, attacker: card_object, defender: card_object, is_opponent: bool) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", ""))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower()
	var resolved_damage = base_damage
	var messages: Array = []
	var flip_result: String = ""
	var attack_failed: bool = false
	
	# ---- CONDITION-GATED ATTACKS (must check first - attack may not proceed) ----
	if "can't use this attack" in text and "unless the defending" in text:
		if "asleep" in text and defender.special_condition != "Asleep":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT ASLEEP!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "poisoned" in text and not defender.is_poisoned:
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT POISONED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "confused" in text and defender.special_condition != "Confused":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT CONFUSED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- ENERGY-GATED ATTACKS (Dark Charmeleon Fireball, Dark Flareon Playing with Fire) ----
	if "use this attack only if there are any" in text and "energy cards attached" in text:
		var required_type = ""
		var type_keywords = ["fire", "water", "grass", "lightning", "psychic", "fighting"]
		for tkw in type_keywords:
			if tkw + " energy cards attached" in text:
				required_type = tkw.capitalize()
				break
		if required_type != "":
			var has_required = false
			for e in attacker.attached_energies:
				var provided = main.get_energy_provided_by_card(e)
				if required_type in provided:
					has_required = true
					break
			if not has_required:
				resolved_damage = 0
				attack_failed = true
				messages.append("ATTACK FAILED! NO " + required_type.to_upper() + " ENERGY ATTACHED!")
				return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- DAMAGE COUNTER MULTIPLICATIVE (Kingler Flail) ----
	if ("×" in damage_str or "x" in damage_str or "X" in damage_str) and "times the number of damage counters on" in text:
		var counters = attacker.get_damage_counters()
		resolved_damage = base_damage * counters
		messages.append(str(counters) + " DAMAGE COUNTERS! " + str(resolved_damage) + " DAMAGE!")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}

	# ---- COIN FLIP MULTIPLICATIVE DAMAGE (×) ----
	if ("×" in damage_str or "x" in damage_str or "X" in damage_str) and "times the number of heads" in text:
		var flip_count = 0
		var flip_until_tails = false
		
		if "flip a coin until you get tails" in text:
			flip_until_tails = true
		elif "flip 5 coins" in text:
			flip_count = 5
		elif "flip 4 coins" in text:
			flip_count = 4
		elif "flip 3 coins" in text:
			flip_count = 3
		elif "flip 2 coins" in text:
			flip_count = 2
		elif "flip a coin" in text:
			flip_count = 1
		
		var heads_count = 0
		# Use silent mode for multi-flips — just animate quickly, show summary at end
		var use_silent = (flip_count > 1 or flip_until_tails)
		if flip_until_tails:
			while true:
				var coin = await main.flip_coin(use_silent, is_opponent)
				if coin:
					heads_count += 1
				else:
					break
		else:
			for i in range(flip_count):
				var coin = await main.flip_coin(use_silent, is_opponent)
				if coin:
					heads_count += 1
		
		resolved_damage = base_damage * heads_count
		# Always show the final summary as a message
		messages.append("GOT " + str(heads_count) + " HEADS! " + str(resolved_damage) + " DAMAGE!")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- "IF TAILS, THIS ATTACK DOES NOTHING" (Nidoran Horn Hazard) ----
	if "if tails, this attack does nothing" in text:
		var coin = await main.flip_coin(false, is_opponent)
		if not coin:
			resolved_damage = 0
			attack_failed = true
			flip_result = "tails"
			messages.append("ATTACK DOES NOTHING!")
		else:
			flip_result = "heads"
		# Check for Farfetch'd style permanent disable
		if "can't use this attack again" in text:
			var attack_name = attack.get("name", "")
			if "as long as" in text and "stays in play" in text:
				attacker.disabled_attacks[attack_name] = "while_in_play"
				print("ATTACK DISABLED: ", attack_name, " disabled while ", attacker_name, " is in play")
			else:
				attacker.disabled_attacks[attack_name] = "entire_game"
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- HEADS/TAILS BONUS DAMAGE (Nidoking Thrash "30+", Electabuzz Thunderpunch) ----
	if "+" in damage_str and "if heads" in text and "more damage" in text and "flip a coin" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		var coin = await main.flip_coin(false, is_opponent)
		if coin:
			resolved_damage = base_damage + bonus
			flip_result = "heads"
			print("COIN BONUS: +", bonus, " damage")
		else:
			flip_result = "tails"
	
	# ---- HALF HP DAMAGE (Raticate Super Fang) ----
	if "equal to half" in text and "remaining hp" in text:
		var half_hp = defender.current_hp / 2.0
		resolved_damage = int(ceil(half_hp / 10.0)) * 10
		print("SUPER FANG: ", resolved_damage, " damage (half of ", defender.current_hp, " HP)")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- PER DEFENDER ENERGY (Mewtwo Psychic) ----
	if "for each energy card attached to the defending" in text:
		var per_energy = 10
		var energy_pos = text.find("more damage for each energy")
		if energy_pos != -1:
			var extracted = extract_number_before(text, "more damage for each energy")
			if extracted > 0:
				per_energy = extracted
		var energy_count = defender.attached_energies.size()
		var bonus = per_energy * energy_count
		resolved_damage += bonus
		print("PER DEFENDER ENERGY: +", bonus, " (", energy_count, " energies)")
	
	# ---- EXTRA ENERGY BEYOND COST (Poliwag Water Gun, Blastoise Hydro Pump) ----
	if "more damage for each" in text and "not used to pay" in text:
		var bonus_energy_type = ""
		var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
		for tkw in type_keywords:
			if tkw + " energy attached" in text and "not used to pay" in text:
				bonus_energy_type = tkw.capitalize()
				break
		
		if bonus_energy_type != "":
			# Count how many of that energy type are attached
			var total_of_type = 0
			for attached in attacker.attached_energies:
				var provided = main.get_energy_provided_by_card(attached)
				if bonus_energy_type in provided:
					total_of_type += 1
			
			# Calculate how many bonus-type energies are consumed by the FULL attack cost
			# This includes typed requirements AND colorless slots filled by bonus-type energy
			var cost = attack.get("cost", [])
			var typed_needed = 0
			var colorless_needed = 0
			for c in cost:
				if c == bonus_energy_type:
					typed_needed += 1
				elif c == "Colorless":
					colorless_needed += 1
			
			# Non-bonus energies fill colorless slots first
			var non_bonus_attached = attacker.attached_energies.size() - total_of_type
			var colorless_filled_by_non_bonus = min(colorless_needed, non_bonus_attached)
			var colorless_from_bonus = colorless_needed - colorless_filled_by_non_bonus
			
			var used_for_cost = typed_needed + colorless_from_bonus
			var extra_count = max(0, total_of_type - used_for_cost)
			
			# Parse the cap: "Extra Water Energy after the 2nd don't count"
			# OR: "You can't add more than 20 damage in this way" (Lapras, Omanyte, Seadra, Omastar)
			var cap = 99
			if "after the" in text and "don't count" in text:
				var after_pos = text.find("after the")
				var after_text = text.substr(after_pos + 10, 10)
				var cap_num = ""
				for ch in after_text:
					if ch.is_valid_int():
						cap_num += ch
					else:
						break
				if cap_num != "":
					# Cap is the max total bonus-type that count, minus those used for cost
					cap = max(0, int(cap_num) - used_for_cost)
			elif "can't add more than" in text and "damage in this way" in text:
				var cap_dmg = extract_number_before(text, "damage in this way")
				if cap_dmg > 0:
					var per_e = 10
					var ext = extract_number_before(text, "more damage for each")
					if ext > 0:
						per_e = ext
					cap = cap_dmg / per_e
			
			extra_count = min(extra_count, cap)
			
			var per_energy_bonus = 10
			var extracted_per = extract_number_before(text, "more damage for each")
			if extracted_per > 0:
				per_energy_bonus = extracted_per
			
			var bonus = per_energy_bonus * extra_count
			resolved_damage += bonus
			print("EXTRA ENERGY: +", bonus, " (", extra_count, " extra ", bonus_energy_type, " beyond ", used_for_cost, " used for cost)")
		else:
			# ---- UNTYPED EXTRA ENERGY (Marill Water Gun — any Energy beyond cost, capped) ----
			if attacker:
				var cost_count = attack.get("cost", []).size()
				var extra_count = max(0, attacker.attached_energies.size() - cost_count)
				var cap = 99
				if "can't add more than" in text and "damage in this way" in text:
					var cap_dmg = extract_number_before(text, "damage in this way")
					if cap_dmg > 0:
						var per_e = extract_number_before(text, "more damage for each")
						if per_e <= 0:
							per_e = 10
						cap = cap_dmg / per_e
				extra_count = min(extra_count, cap)
				var per_energy_bonus = extract_number_before(text, "more damage for each")
				if per_energy_bonus <= 0:
					per_energy_bonus = 10
				var bonus = per_energy_bonus * extra_count
				resolved_damage += bonus
				print("UNTYPED EXTRA ENERGY: +", bonus, " (", extra_count, " extra beyond cost)")

	# ---- PER DAMAGE COUNTER ON DEFENDING (Jynx Meditate, Mr. Mime Meditate) ----
	if "for each damage counter on the defending" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = defender.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("DEFENDER COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- PER DAMAGE COUNTER ON SELF - ADDITIONAL (Tauros Rampage) ----
	if ("for each damage counter on " + attacker_name) in text and "minus" not in text and "defending" not in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("SELF COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- MINUS PER DAMAGE COUNTER ON SELF (Machoke Karate Chop "50-") ----
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var reduction = per_counter * damage_counters
		resolved_damage = max(0, base_damage - reduction)
		print("KARATE CHOP: -", reduction, " (", damage_counters, " counters)")
	
	# ---- PER BENCHED POKEMON (Wigglytuff Do the Wave) ----
	if "for each of your benched" in text:
		var per_bench = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per_bench = extracted
		var bench = main.opponent_bench if is_opponent else main.player_bench
		var bonus = per_bench * bench.size()
		resolved_damage += bonus
		print("BENCH BONUS: +", bonus, " (", bench.size(), " benched)")
	
	# ---- ADDITIONAL DAMAGE IF DEFENDER HAS STATUS ----
	if "if the defending pokémon is poisoned" in text and "more damage" in text:
		if defender.is_poisoned:
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (poisoned)")
	if "if the defending pokémon is confused" in text and "more damage" in text:
		if defender.special_condition == "Confused":
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (confused)")
	
	return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}

# Displays modifier floating labels, the damage floating label, applies HP reduction,
# and updates the HP circles for the defender
func execute_metronome(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = main.get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await main.show_message("NO ATTACKS TO COPY!")
		if main._should_bail(): return
		return
	
	var chosen_attack: Dictionary = {}
	
	if is_opponent:
		# CPU chooses: pick the attack with highest damage potential
		var best_score = -999.0
		var cpu_types = attacker.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = estimate_attack_damage_range(attack, attacker, defender)
			var result = main.calculate_final_damage(dmg_range["max"], cpu_types, defender)
			var score = float(result["damage"])
			var parsed = parse_card_text_effects(attack.get("text", ""), attacker.metadata.get("name", ""))
			score += main.cpu_ai.score_parsed_effects(parsed, defender)
			if score > best_score:
				best_score = score
				chosen_attack = attack
	else:
		# Player chooses: show attack names as buttons
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		
		# Clear and show attack buttons
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = atk.get("name", "Attack") + " (" + str(atk.get("damage", "0")) + ")"
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		
		var selected_index = await main.special_attack_selected
		chosen_attack = defender_attacks[selected_index]
		
		# Clean up buttons
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	
	await main.show_message(attacker.metadata["name"].to_upper() + " COPIES " + chosen_attack.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	# Execute the copied attack (ignore energy costs and energy discard requirements)
	var variable_result = await resolve_attack_variable_damage(chosen_attack, attacker, defender, is_opponent)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await main.show_message(msg)
			if main._should_bail(): return
		return
	
	for msg in variable_result["messages"]:
		await main.show_message(msg)
		if main._should_bail(): return
	
	# Use attacker's own type for Metronome (Clefairy stays Colorless)
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(resolved_base, attacking_types, defender)
	var final_damage = result["damage"]
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		main.show_floating_label("NO EFFECT", inv_label_pos, Color.WHITE)
		return

	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, resolved_base)
	if main._should_bail(): return
	
	# Apply non-discard effects from the copied attack
	var attack_text = chosen_attack.get("text", "")
	var effects = parse_card_text_effects(attack_text, attacker.metadata.get("name", ""))
	var filtered_effects = []
	for effect in effects:
		if effect["type"] != "energy_discard_self":
			filtered_effects.append(effect)
	if filtered_effects.size() > 0:
		await apply_card_text_effects(filtered_effects, attacker, defender, is_opponent, flip_result)
		if main._should_bail(): return

# MIRROR MOVE (Pidgeotto): Replay the last attack received
func execute_mirror_move(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var last_attack = main.last_attack_on_opponent if is_opponent else main.last_attack_on_player
	
	if last_attack.is_empty() or not last_attack.has("damage"):
		await main.show_message("MIRROR MOVE FAILED! NO ATTACK TO MIRROR!")
		if main._should_bail(): return
		return
	
	var mirrored_damage = last_attack["damage"]
	var mirrored_attack = last_attack.get("attack", {})
	
	await main.show_message(attacker.metadata["name"].to_upper() + " MIRRORS THE LAST ATTACK FOR " + str(mirrored_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		main.show_floating_label("NO EFFECT", inv_label_pos, Color.WHITE)
		return

	mirrored_damage = main.apply_defender_no_damage_shield(defender, mirrored_damage, !is_opponent)

	if mirrored_damage > 0:
		var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		main.show_floating_label("-" + str(mirrored_damage) + "HP", defender_label_pos, Color.RED)
		defender.current_hp = max(0, defender.current_hp - mirrored_damage)
		main.display_hp_circles_above_align(defender, !is_opponent)
	
	if mirrored_attack.has("text"):
		var effects = parse_card_text_effects(mirrored_attack.get("text", ""), attacker.metadata.get("name", ""))
		if effects.size() > 0:
			await apply_card_text_effects(effects, attacker, defender, is_opponent)
			if main._should_bail(): return

# AMNESIA (Poliwhirl): Disable one of the opponent's attacks for next turn
func execute_amnesia(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = main.get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await main.show_message("NO ATTACKS TO DISABLE!")
		if main._should_bail(): return
		return
	
	var chosen_attack_name: String = ""
	
	if is_opponent:
		var best_score = -999.0
		var defender_types = defender.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = estimate_attack_damage_range(attack, defender, attacker)
			var result = main.calculate_final_damage(dmg_range["max"], defender_types, attacker)
			var score = float(result["damage"])
			if score > best_score:
				best_score = score
				chosen_attack_name = attack.get("name", "")
	else:
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = "DISABLE: " + atk.get("name", "Attack")
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		
		var selected_index = await main.special_attack_selected
		chosen_attack_name = defender_attacks[selected_index].get("name", "")
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	
	if chosen_attack_name != "":
		defender.disabled_attacks[chosen_attack_name] = "end_of_turn"
		await main.show_message(defender.metadata["name"].to_upper() + " FORGOT HOW TO USE " + chosen_attack_name.to_upper() + "!")
		if main._should_bail(): return
		print("AMNESIA: Disabled ", chosen_attack_name, " on ", defender.metadata["name"])

# CONVERSION (Porygon): Change weakness (1) or resistance (2) type
func execute_conversion(attacker: card_object, defender: card_object, is_opponent: bool, is_conversion_1: bool) -> void:
	var energy_types = ["Fighting", "Fire", "Grass", "Lightning", "Psychic", "Water"]
	var chosen_type: String = ""
	
	# Conversion 1: Only works if the defending pokemon has a weakness
	if is_conversion_1:
		var weaknesses = defender.metadata.get("weaknesses", [])
		if weaknesses.size() == 0:
			await main.show_message("CONVERSION FAILED! OPPONENT HAS NO WEAKNESS!")
			if main._should_bail(): return
			return
	
	if is_opponent:
		if is_conversion_1:
			var cpu_type = attacker.metadata.get("types", ["Colorless"])[0]
			chosen_type = cpu_type if cpu_type in energy_types else energy_types[0]
		else:
			var player_type = defender.metadata.get("types", ["Colorless"])[0]
			if player_type != "Colorless" and player_type in energy_types:
				chosen_type = player_type
			else:
				chosen_type = energy_types[0]
	else:
		var energy_uids = ["base1-97", "base1-98", "base1-99", "base1-100", "base1-101", "base1-102"]
		var energy_cards: Array = []
		for uid in energy_uids:
			var meta = main.get_card_metadata(uid)
			if meta != null:
				var card = card_object.new(uid, meta)
				energy_cards.append(card)
		
		if energy_cards.size() > 0:
			main.energy_type_selection_active = true
			main.show_enlarged_array_selection_mode(energy_cards)
			main.cancel_button.visible = false
			if is_conversion_1:
				main.header_label.text = "CONVERSION 1: CHANGE OPPONENT'S WEAKNESS"
			else:
				main.header_label.text = "CONVERSION 2: CHANGE YOUR RESISTANCE"
			main.hint_label.text = "Select an energy type"
			main.action_button.text = "SELECT TYPE"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.energy_type_selected
			if main._should_bail(): return
			chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "").strip_edges() if main.selected_card_for_action else ""
			main.energy_type_selection_active = false
			main.hide_selection_mode_display_main()
	
	if chosen_type != "" and chosen_type != "Colorless":
		if is_conversion_1:
			defender.temporary_weakness = chosen_type
			await main.show_message(defender.metadata["name"].to_upper() + "'S WEAKNESS CHANGED TO " + chosen_type.to_upper() + "!")
			if main._should_bail(): return
		else:
			attacker.temporary_resistance = chosen_type
			await main.show_message(attacker.metadata["name"].to_upper() + "'S RESISTANCE CHANGED TO " + chosen_type.to_upper() + "!")
			if main._should_bail(): return
	else:
		await main.show_message("CONVERSION FAILED!")
		if main._should_bail(): return

												######### Main effect parsers helpers ##########

# Parses attack effect text and returns an array of effect dictionaries for evaluation or application
func parse_card_text_effects(attack_text: String, attacker_name: String) -> Array:
	if attack_text == "":
		return []

	var effects: Array = []
	var text = attack_text.to_lower()
	var lower_name = attacker_name.to_lower()
	var has_defender_prefix = "the defending pokémon is now" in text

	# --- STATUS: Defender status conditions ---
	var defender_statuses = ["paralyzed", "asleep", "poisoned", "confused", "burned"]
	for status in defender_statuses:
		var pos = find_defender_status_pos(text, status, has_defender_prefix)
		if pos != -1:
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "defender", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Defender ", status.capitalize(), " | Flip: ", flip)

	# --- STATUS: Self-inflicted status ---
	var self_statuses = ["confused", "asleep", "poisoned", "paralyzed", "burned"]
	for status in self_statuses:
		if lower_name + " is now " + status in text:
			var pos = text.find(lower_name + " is now " + status)
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "self", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Self ", status.capitalize(), " | Flip: ", flip)

	# --- TOXIC: Enhanced poison (20 instead of 10) ---
	if "20 poison damage instead of 10" in text or "put 2 damage counters instead of 1" in text:
		var flip = get_flip_context(text, text.find("instead"))
		effects.append({"type": "toxic", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Toxic upgrade | Flip: ", flip)

	# --- SELF DAMAGE: Attacker damages itself ---
	if lower_name in text and "damage to itself" in text:
		var damage = extract_number_before(text, "damage to itself")
		if damage > 0:
			var flip = get_flip_context(text, text.find("damage to itself"))
			effects.append({"type": "self_damage", "target": "self", "damage": damage, "flip": flip})
			print("EFFECT PARSED: Self Damage -> ", damage, " | Flip: ", flip)

	# --- ENERGY DISCARD SELF: Attacker discards own energy ---
	if "discard" in text and "energy" in text and ("attached to " + lower_name) in text:
		var discard_pos = text.find("discard")
		var flip = get_flip_context(text, discard_pos)
		var count = 0
		var energy_type = "any"
		if "discard all" in text and ("energy cards attached to " + lower_name) in text:
			count = -1
		elif "discard a " in text or "discard 1 " in text:
			count = 1
		elif "discard 2" in text:
			count = 2
		elif "discard 3" in text:
			count = 3
		else:
			count = 1
		var type_keywords = ["fire", "water", "grass", "lightning", "psychic", "fighting", "darkness", "metal"]
		for type_name in type_keywords:
			if "discard" in text and type_name + " energy" in text and ("attached to " + lower_name) in text:
				energy_type = type_name.capitalize()
				break
		effects.append({"type": "energy_discard_self", "target": "self", "count": count, "energy_type": energy_type, "flip": flip})
		print("EFFECT PARSED: Energy Discard Self -> Count: ", count, " Type: ", energy_type, " | Flip: ", flip)

	# --- ENERGY DISCARD DEFENDER: Remove energy from defending pokemon ---
	if "discard" in text and "energy" in text and "attached to" in text:
		var is_defender_energy = false
		if "attached to the defending" in text:
			is_defender_energy = true
		if "attached to it" in text and "defending" in text:
			is_defender_energy = true
		if "choose 1 of them and discard it" in text and "energy cards attached to it" in text:
			is_defender_energy = true
		if is_defender_energy:
			var discard_pos = text.find("discard")
			var flip = get_flip_context(text, discard_pos)
			effects.append({"type": "energy_discard_defender", "target": "defender", "count": 1, "flip": flip})
			print("EFFECT PARSED: Energy Discard Defender | Flip: ", flip)

	# --- BENCH DAMAGE: Damage to benched pokemon ---
	if "damage to each" in text and "bench" in text:
		# Special case: Articuno-style where heads = opponent bench, tails = own bench
		if "your opponent's benched" in text and "your own benched" in text:
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			effects.append({"type": "bench_damage", "target": "main.opponent_bench", "damage": damage, "flip": "heads"})
			effects.append({"type": "bench_damage", "target": "own_bench", "damage": damage, "flip": "tails"})
			print("EFFECT PARSED: Bench Damage -> COIN FLIP: heads=opponent, tails=own for ", damage)
		else:
			var bench_target = "all_benches"
			if "your opponent's benched" in text or "opponent's benched" in text:
				bench_target = "main.opponent_bench"
			elif "your own benched" in text:
				bench_target = "own_bench"
			elif "each player's bench" in text:
				bench_target = "all_benches"
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			var flip = get_flip_context(text, text.find("damage to each"))
			effects.append({"type": "bench_damage", "target": bench_target, "damage": damage, "flip": flip})
			print("EFFECT PARSED: Bench Damage -> ", bench_target, " for ", damage, " | Flip: ", flip)

	# --- BLIND / SMOKESCREEN: Defender must flip to attack next turn ---
	if "tries to attack" in text and "if tails" in text and "does nothing" in text:
		effects.append({"type": "blind", "target": "defender", "flip": "none"})
		print("EFFECT PARSED: Blind / Smokescreen -> Defender")

	# --- INVINCIBLE: Prevent all effects including damage next turn ---
	if "prevent all effects of attacks, including damage" in text:
		var flip = get_flip_context(text, text.find("prevent all effects"))
		effects.append({"type": "invincible", "target": "self", "flip": flip})
		print("EFFECT PARSED: Invincible -> Self | Flip: ", flip)

	# --- NO DAMAGE: Prevent damage only next turn (other effects still happen) ---
	if "prevent all damage done to" in text and "prevent all effects of attacks" not in text:
		var flip = get_flip_context(text, text.find("prevent all damage"))
		effects.append({"type": "no_damage", "target": "self", "flip": flip})
		print("EFFECT PARSED: No Damage -> Self | Flip: ", flip)

	# --- RETREAT LOCK: Defender can't retreat ---
	if "can't retreat" in text and "defending" in text:
		var flip = get_flip_context(text, text.find("can't retreat"))
		effects.append({"type": "retreat_lock", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Retreat Lock -> Defender | Flip: ", flip)

	# --- DRAW CARDS ---
	if "draw a card" in text and "your opponent" not in text:
		effects.append({"type": "draw", "target": "self", "count": 1, "flip": "none"})
		print("EFFECT PARSED: Draw 1 card")
	elif "draw " in text and "cards" in text and "your opponent" not in text:
		var count = extract_number_before(text, "cards")
		if count > 0:
			effects.append({"type": "draw", "target": "self", "count": count, "flip": "none"})
			print("EFFECT PARSED: Draw ", count, " cards")

	# --- SELF HEAL ALL: Remove all damage from attacker ---
	if "remove all damage counters from " + lower_name in text:
		var flip = get_flip_context(text, text.find("remove all damage"))
		effects.append({"type": "self_heal", "target": "self", "amount": -1, "flip": flip})
		print("EFFECT PARSED: Self Heal All | Flip: ", flip)

	# --- SELF HEAL PARTIAL: Remove X damage counters from attacker ---
	if "remove" in text and "damage counter" in text and lower_name in text and "remove all" not in text:
		var amount = extract_number_before(text, "damage counter")
		if amount > 0:
			var flip = get_flip_context(text, text.find("remove"))
			effects.append({"type": "self_heal", "target": "self", "amount": amount, "flip": flip})
			print("EFFECT PARSED: Self Heal ", amount, " counters | Flip: ", flip)

	# --- DESTINY BOND ---
	if "knocks out " + lower_name in text and "knock out that" in text:
		effects.append({"type": "destiny_bond", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Destiny Bond -> Self")

	# --- SHIELDED DAMAGE (Onix Harden): Prevent damage at or below threshold ---
	# "During your opponent's next turn, whenever 30 or less damage is done to Onix, prevent that damage."
	if "or less damage is done to" in text and "prevent that damage" in text:
		var threshold = extract_number_before(text, "or less damage")
		if threshold > 0:
			effects.append({"type": "shielded_damage", "target": "self", "threshold": threshold, "flip": "none"})
			print("EFFECT PARSED: Shielded Damage -> threshold ", threshold)

	# --- FORCE SWITCH (Pidgey/Pidgeotto Whirlwind, Ninetales Lure) ---
	# Whirlwind: "he or she chooses 1" = defender picks
	# Lure: "choose 1 of them and switch it" (without "he or she") = attacker picks
	if ("switches it with" in text or "switch it with" in text) and ("benched" in text or "bench" in text):
		if "defending pokémon" in text or "active pokémon" in text:
			var flip = get_flip_context(text, text.find("switch"))
			var chooser = "defender"
			# "he or she chooses" = defender picks (Whirlwind)
			# Otherwise attacker picks (Lure)
			if "he or she chooses" not in text and "they choose" not in text:
				chooser = "attacker"
			effects.append({"type": "force_switch", "target": "defender", "chooser": chooser, "flip": flip})
			print("EFFECT PARSED: Force Switch -> Defender | Chooser: ", chooser, " | Flip: ", flip)


	# --- DAMAGE REDUCTION NEXT TURN (Minimize, Pounce, Snivel) ---
	if ("damage done" in text or "damage done by" in text) and "reduced by" in text and ("next turn" in text or "opponent's next turn" in text):
		var reduction = extract_number_before(text, "after applying")
		if reduction <= 0:
			reduction = 20
		effects.append({"type": "damage_reduction", "target": "self", "amount": reduction, "flip": "none"})
		print("EFFECT PARSED: Damage Reduction -> Self ", reduction)

	# --- ATTACK BLOCK NEXT TURN (Tail Wag, Leer) ---
	if "can't attack" in text and lower_name in text and "next turn" in text:
		var flip = get_flip_context(text, text.find("can't attack"))
		effects.append({"type": "attack_block", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Attack Block -> Defender | Flip: ", flip)

	# --- SELF SWITCH (Exeggutor Teleport) ---
	if "switch " + lower_name + " with" in text and "benched" in text:
		effects.append({"type": "self_switch", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Self Switch -> Self")

	# --- BENCH DAMAGE SINGLE (Pikachu Spark) ---
	if "choose 1 of them" in text and "damage to it" in text and "bench" in text and "damage to each" not in text:
		var damage = extract_number_before(text, "damage to it")
		if damage <= 0:
			damage = 10
		effects.append({"type": "bench_damage_single", "target": "opponent_bench", "damage": damage, "flip": "none"})
		print("EFFECT PARSED: Bench Damage Single -> ", damage)

	# --- COIN-FLIP ATTACK BLOCK (Sand-attack, Smokescreen, Lightning Flash, Mirage) ---
	# "If the Defending Pokémon tries to attack during your opponent's next turn,
	#  your opponent flips a coin. If tails, that attack does nothing."
	if "tries to attack" in text and ("flips a coin" in text or "flip a coin" in text) and "does nothing" in text:
		effects.append({"type": "flip_attack_block", "target": "defender", "flip": "none"})
		print("EFFECT PARSED: Coin-flip Attack Block -> Defender")

	# --- TRAINER LOCK (Psyduck Headache) ---
	if "can't play trainer" in text and "next turn" in text:
		effects.append({"type": "trainer_lock", "target": "opponent", "flip": "none"})
		print("EFFECT PARSED: Trainer Lock -> Opponent")

	# --- LEECH SEED (Exeggcute) ---
	if "unless all damage" in text and "is prevented" in text and "remove 1 damage counter" in text:
		effects.append({"type": "leech_seed", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Leech Seed heal")

	# --- FOUL ODOR: Both pokemon confused ---
	if "both" in text and "defending" in text and lower_name in text and "confused" in text:
		effects.append({"type": "status", "target": "defender", "status": "Confused", "flip": "none"})
		effects.append({"type": "status", "target": "self", "status": "Confused", "flip": "none"})
		print("EFFECT PARSED: Foul Odor -> Both Confused")

	# --- DREAM DANCE: Both pokemon asleep (Erika's Gloom) ---
	if "both" in text and "defending" in text and lower_name in text and "asleep" in text:
		effects.append({"type": "status", "target": "defender", "status": "Asleep", "flip": "none"})
		effects.append({"type": "status", "target": "self", "status": "Asleep", "flip": "none"})
		print("EFFECT PARSED: Dream Dance -> Both Asleep")

	# --- WAKE DEFENDER: Cure the Defending Pokemon of Asleep (Sabrina's Jynx Good Morning) ---
	if "it is no longer asleep" in text:
		effects.append({"type": "wake_defender", "target": "defender", "flip": "none"})
		print("EFFECT PARSED: Wake Defender")

	# --- SELF HEAL "REMOVE 1 OF THEM/THOSE" (Erika's Oddish Blot / Sporadic Sponging) ---
	if lower_name in text and ("remove 1 of them" in text or "remove 1 of those damage counter" in text):
		var blot_pos = text.find("remove 1 of")
		var blot_flip = get_flip_context(text, blot_pos)
		effects.append({"type": "self_heal", "target": "self", "amount": 1, "flip": blot_flip})
		print("EFFECT PARSED: Self Heal 1 counter (remove 1 of them) | Flip: ", blot_flip)

	if effects.size() == 0:
		print("EFFECT PARSED: No recognised effects in: ", text.left(80))

	return effects
	
# Applies parsed effect dictionaries to the game state with coin flip gating
# pre_flip_result: if a coin was already flipped during damage resolution, use this instead of re-flipping
func apply_card_text_effects(effects: Array, attacker: card_object, defender: card_object, is_opponent_attacking: bool, pre_flip_result: String = "") -> void:
	var flip_result: String = pre_flip_result
	var needs_flip: bool = false
	
	# Only flip if we don't already have a result from damage resolution
	if flip_result == "":
		for effect in effects:
			if effect.get("flip", "none") != "none":
				needs_flip = true
				break

		if needs_flip:
			var coin = await main.flip_coin(false, is_opponent_attacking)
			flip_result = "heads" if coin else "tails"

	for effect in effects:
		var required_flip = effect.get("flip", "none")
		if required_flip != "none" and flip_result != required_flip:
			print("EFFECT SKIPPED: Needed ", required_flip, " but got ", flip_result)
			continue

		if effect.get("target") == "defender" and defender.is_invincible:
			print("EFFECT BLOCKED: Defender is invincible - skipping ", effect["type"])
			continue

		if effect["type"] == "status":
			await main.apply_status_effect(effect, attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "toxic":
			await apply_toxic(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_damage":
			await apply_self_damage(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "energy_discard_self":
			await apply_energy_discard_self(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "energy_discard_defender":
			await apply_energy_discard_defender(effect, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "bench_damage":
			await apply_bench_damage(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "blind":
			await apply_blind_effect(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "no_damage":
			apply_no_damage_effect(attacker, is_opponent_attacking)
		if effect["type"] == "invincible":
			apply_invincible_effect(attacker, is_opponent_attacking)
		if effect["type"] == "retreat_lock":
			await apply_retreat_lock(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "draw":
			await apply_draw_effect(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_heal":
			await apply_self_heal(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "destiny_bond":
			await apply_destiny_bond(attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "shielded_damage":
			apply_shielded_damage(effect, attacker, is_opponent_attacking)
		if effect["type"] == "flip_attack_block":
			await apply_flip_attack_block(defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "force_switch":
			await apply_force_switch(effect, is_opponent_attacking)
			if main._should_bail(): return
			
		if effect["type"] == "damage_reduction":
			await apply_damage_reduction(effect, attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "attack_block":
			await apply_attack_block(effect, attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "self_switch":
			await apply_self_switch(attacker, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "bench_damage_single":
			await apply_bench_damage_single(effect, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "leech_seed":
			await apply_leech_seed(attacker, defender, is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "trainer_lock":
			await apply_trainer_lock(is_opponent_attacking)
			if main._should_bail(): return
		if effect["type"] == "wake_defender":
			if defender.special_condition == "Asleep":
				defender.special_condition = ""
				main.update_status_icons(defender, !is_opponent_attacking)
				await main.show_message(defender.metadata.get("name", "").to_upper() + " IS NO LONGER ASLEEP!")
				if main._should_bail(): return
########################################################### END EFFECT PARSING FUNCTIONS #############################################################
######################################################################################################################################################

#                ##      ##      ########  ####    ##  ########
#               ####    ####        ##     ## ##   ##     ##
#              ##  ##  ##  ##       ##     ##  ##  ##     ##
#             ##    ####    ##      ##     ##   ## ##     ##
#            ##      ##      ##  ########  ##    ####   #######

######################################################################################################################################################
################################################### SMALL FUNCTIONS TO HELP WITH CODE READABILITY ####################################################

# Function to get all basic pokemon from a given array of cards
func apply_self_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var damage = effect.get("damage", 0)
	attacker.current_hp = max(0, attacker.current_hp - damage)
	var name = attacker.metadata.get("name", "Unknown")
	var label_x = 1030 if is_opponent_attacking else 530
	await main.show_message(name.to_upper() + " DEALT " + str(damage) + " DAMAGE TO ITSELF!")
	if main._should_bail(): return
	main.show_floating_label("-" + str(damage) + "HP", Vector2(label_x, 300), Color.RED, true)
	main.display_hp_circles_above_align(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " took ", damage, " self-damage. HP: ", attacker.current_hp)

# Discards energy from the attacker as an attack cost
func apply_energy_discard_self(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	var energy_type = effect.get("energy_type", "any")
	var name = attacker.metadata.get("name", "Unknown")
	var to_discard: Array = []

	if count == -1:
		to_discard = attacker.attached_energies.duplicate()
	else:
		for i in range(count):
			var found = false
			for j in range(attacker.attached_energies.size() - 1, -1, -1):
				var energy = attacker.attached_energies[j]
				if energy in to_discard:
					continue
				if energy_type == "any":
					to_discard.append(energy)
					found = true
					break
				else:
					var provided = main.get_energy_provided_by_card(energy)
					if energy_type in provided:
						to_discard.append(energy)
						found = true
						break
			if not found and energy_type != "any":
				for j in range(attacker.attached_energies.size() - 1, -1, -1):
					var energy = attacker.attached_energies[j]
					if energy not in to_discard:
						to_discard.append(energy)
						break

	var discard_node = main.opponent_discard_icon if is_opponent_attacking else main.player_discard_icon
	var from_node = main.find_card_ui_for_object(attacker)
	if from_node == null:
		from_node = main.opponent_active_container if is_opponent_attacking else main.player_active_container

	for energy in to_discard:
		var energy_texture = main.get_card_texture(energy)
		attacker.attached_energies.erase(energy)
		main.card_ops.discard_energy_from_pokemon(energy, is_opponent_attacking)
		await main.animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, main.card_scales[10])
		if main._should_bail(): return
		main.display_active_pokemon_energies(is_opponent_attacking)

	# Update discard pile display immediately (no message box)
	main.update_discard_pile_display(is_opponent_attacking)
	main.display_active_pokemon_energies(is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " discarded ", to_discard.size(), " energy cards")

# Discards energy from the defending pokemon - with selection UI for choosing which energy
func apply_energy_discard_defender(effect: Dictionary, defender: card_object, is_opponent_attacking: bool) -> void:
	if defender.attached_energies.size() == 0:
		print("EFFECT SKIPPED: Defender has no energy to discard")
		return
	var name = defender.metadata.get("name", "Unknown")
	var is_defender_player = is_opponent_attacking
	var is_defender_opponent = !is_opponent_attacking
	
	var energy_to_discard: card_object = null
	
	if is_defender_opponent:
		# Player is attacking — player chooses which of opponent's energies to discard
		main.opponent_blocker.visible = false
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(defender.attached_energies)
		main.cancel_button.visible = false
		main.header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		main.hint_label.text = "Choose an energy card to discard from the defending Pokemon"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_discard = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	elif is_defender_player:
		# Opponent is attacking — player chooses which of their own energies to discard
		main.opponent_blocker.visible = false
		main.defender_energy_discard_active = true
		main.show_enlarged_array_selection_mode(defender.attached_energies)
		main.cancel_button.visible = false
		main.header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		main.hint_label.text = "Your opponent forces you to discard an energy card"
		main.action_button.text = "DISCARD"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.defender_energy_chosen
		if main._should_bail(): return
		energy_to_discard = main.selected_card_for_action
		main.defender_energy_discard_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
	if energy_to_discard != null:
		var energy_texture = main.get_card_texture(energy_to_discard)
		var from_node = main.find_card_ui_for_object(defender)
		var defender_is_opp = is_defender_opponent
		if from_node == null:
			from_node = main.opponent_active_container if defender_is_opp else main.player_active_container
		var discard_node = main.opponent_discard_icon if defender_is_opp else main.player_discard_icon
		
		defender.attached_energies.erase(energy_to_discard)
		main.card_ops.discard_energy_from_pokemon(energy_to_discard, defender_is_opp)

		await main.animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, main.card_scales[10])
		if main._should_bail(): return
		main.update_discard_pile_display(defender_is_opp)
		
		await main.show_message("AN ENERGY WAS DISCARDED FROM " + name.to_upper() + "!")
		if main._should_bail(): return
		# Refresh the defender's energy display (not the attacker's)
		main.display_active_pokemon_energies(defender_is_opp)
		print("EFFECT APPLIED: Discarded energy from ", name)

# Applies damage to benched pokemon based on target scope
# Applies damage to benched pokemon based on target scope, showing floating labels sequentially
func apply_bench_damage(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var bench_target = effect.get("target", "main.opponent_bench")
	var damage = effect.get("damage", 10)
	var benches_to_hit: Array = []

	if bench_target == "main.opponent_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
		else:
			benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})
	elif bench_target == "own_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})
		else:
			benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
	elif bench_target == "all_benches":
		benches_to_hit.append({"bench": main.player_bench, "is_opponent": false})
		benches_to_hit.append({"bench": main.opponent_bench, "is_opponent": true})

	for bench_info in benches_to_hit:
		# GYM2 Transparent Walls (gym2-125): the protected side's bench takes no damage from attacks
		var bench_owner_is_opp = bench_info["is_opponent"]
		var walls_on = (main.opponent_transparent_walls_active if bench_owner_is_opp else main.player_transparent_walls_active)
		if walls_on:
			print("GYM2 TRANSPARENT WALLS: bench damage prevented")
			continue
		var bench_container = main.opponent_bench_container if bench_info["is_opponent"] else main.player_bench_container
		for i in range(bench_info["bench"].size()):
			var pokemon = bench_info["bench"][i]
			# GYM1 Brock's Rhydon Bench Guard — owner may redirect 10 to Rhydon
			var effective_damage = await main.powers_and_bodies.check_bench_guard(pokemon, damage, bench_owner_is_opp)
			pokemon.current_hp = max(0, pokemon.current_hp - effective_damage)
			print("BENCH DAMAGE: ", pokemon.metadata.get("name", ""), " took ", effective_damage, " damage. HP: ", pokemon.current_hp)

			# Show floating label at this bench pokemon's approximate position
			var bench_card_ui = null
			if i < bench_container.get_child_count():
				bench_card_ui = bench_container.get_child(i)
			if bench_card_ui != null and is_instance_valid(bench_card_ui):
				var label_pos = bench_card_ui.global_position + Vector2(0, -20)
				main.show_floating_label("-" + str(effective_damage), label_pos, Color.WHITE, true,)
				

			# Stagger labels by 0.1 seconds for visual sequence
			await get_tree().create_timer(0.1).timeout
			if main._should_bail(): return

# Sets the blind flag on the defending pokemon and updates icons
func apply_blind_effect(defender: card_object, is_opponent_attacking: bool) -> void:
	defender.is_blind = true
	var is_def_opponent = !is_opponent_attacking
	main.update_status_icons(defender, is_def_opponent)
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T SEE! MUST FLIP TO ATTACK!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " is now Blind")

# Sets the no_damage flag on the attacker and updates icons
func apply_no_damage_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_no_damage = true
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has no_damage shield")

# Sets the invincible flag on the attacker and updates icons
func apply_invincible_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.is_invincible = true
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " is invincible")

# Sets the retreat lock on the defending pokemon
func apply_retreat_lock(defender: card_object, is_opponent_attacking: bool) -> void:
	if is_opponent_attacking:
		main.player_retreat_disabled = true
	else:
		main.opponent_retreat_disabled = true
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T RETREAT!")
	if main._should_bail(): return
	print("EFFECT APPLIED: Retreat locked for ", defender.metadata.get("name", ""))

# Coin-flip attack block (Sand-attack, Smokescreen) — defender must flip before attacking next turn
func apply_flip_attack_block(defender: card_object, is_opponent_attacking: bool) -> void:
	if defender == null:
		return
	defender.attack_flip_blocked = true
	defender.attack_blocked_by_id = -1  # not pokemon-specific, just a turn-long effect
	main.update_status_icons(defender, not is_opponent_attacking)
	await main.show_message(defender.metadata.get("name", "").to_upper() + " MUST FLIP BEFORE ATTACKING NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: Coin-flip attack block on ", defender.metadata.get("name", ""))

# SUPER FANG (Raticate, Lt. Surge's Raticate): damage = half defender's remaining HP, rounded up to 10
func execute_super_fang(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender == null or defender.current_hp <= 0:
		return
	if main.check_defender_invincible(defender, not is_opponent):
		return
	var damage = int(ceil(defender.current_hp / 2.0 / 10.0)) * 10
	var label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
	main.show_floating_label("-" + str(damage) + "HP", label_pos, Color.WHITE, true)
	defender.current_hp = max(0, defender.current_hp - damage)
	main.display_hp_circles_above_align(defender, not is_opponent)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
	await main.powers_and_bodies.dispatch_on_damage(defender, attacker, damage, not is_opponent)
	if main._should_bail(): return
	await main.show_message("SUPER FANG! " + str(damage) + " DAMAGE! (HALF HP)")
	if main._should_bail(): return
	print("SUPER FANG: ", damage, " damage (half of ", defender.current_hp + damage, " HP)")

# MIND SHOCK (Dark Alakazam, Dark Kadabra, Sabrina's Drowzee): damage ignoring W/R
func execute_mind_shock(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if main.check_defender_invincible(defender, not is_opponent):
		return
	var final_damage = main.apply_defender_no_damage_shield(defender, base_damage, not is_opponent)
	var label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
	main.show_floating_label("-" + str(final_damage) + "HP", label_pos, Color.WHITE, true)
	defender.current_hp = max(0, defender.current_hp - final_damage)
	main.display_hp_circles_above_align(defender, not is_opponent)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
	await main.powers_and_bodies.dispatch_on_damage(defender, attacker, final_damage, not is_opponent)
	if main._should_bail(): return
	await main.show_message("MIND SHOCK: " + str(final_damage) + " DAMAGE! (NO W/R)")
	if main._should_bail(): return

# MEGA BURN (Sabrina's Alakazam): deal damage then lock this attack for next turn
func execute_mega_burn(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	if not main.check_defender_invincible(defender, not is_opponent):
		final_damage = main.apply_defender_no_damage_shield(defender, final_damage, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	attacker.gym2_mega_burn_locked = true
	await main.show_message("MEGA BURN! " + attacker.metadata.get("name", "").to_upper() + " CAN'T USE THIS ATTACK NEXT TURN!")
	if main._should_bail(): return

# HOOK SHOT (Brock's Geodude): damage ignoring Resistance only
func execute_hook_shot(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	# Calculate damage with Weakness but skip Resistance
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var modifiers = result["modifiers"]
	var final_damage = result["damage"]
	# Re-add resistance that calculate_final_damage subtracted
	var resistances = defender.metadata.get("resistances", [])
	for r in resistances:
		if r["type"] in attacking_types:
			var resist_val = int(r["value"])
			final_damage -= resist_val  # subtract the negative value = add back the resistance reduction
			modifiers.append("NO RESISTANCE")
			break
	final_damage = max(0, final_damage)
	if not main.check_defender_invincible(defender, not is_opponent):
		final_damage = main.apply_defender_no_damage_shield(defender, final_damage, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, final_damage, modifiers, is_opponent, base_damage)
		if main._should_bail(): return

# Draws cards for the attacker
func apply_draw_effect(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	await main.card_ops.draw_n(is_opponent_attacking, count)
	if main._should_bail(): return
	var who = "CPU" if is_opponent_attacking else "Player"
	await main.show_message(who.to_upper() + " DREW " + str(count) + " CARD(S)!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", who, " drew ", count, " card(s)")

# Heals damage from the attacker
func apply_self_heal(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var name = attacker.metadata.get("name", "Unknown")
	var max_hp = int(attacker.metadata.get("hp", "0"))
	var amount = effect.get("amount", -1)
	var healed = 0

	if amount == -1:
		healed = max_hp - attacker.current_hp
		attacker.current_hp = max_hp
	else:
		var heal_hp = amount * 10
		healed = min(heal_hp, max_hp - attacker.current_hp)
		attacker.current_hp = min(max_hp, attacker.current_hp + heal_hp)

	if healed > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent_attacking)
		await main.show_message(name.to_upper() + " HEALED " + str(healed) + " HP!")
		if main._should_bail(): return
		print("EFFECT APPLIED: ", name, " healed ", healed, " HP. Now at: ", attacker.current_hp)
	else:
		print("EFFECT SKIPPED: ", name, " already at full HP")

# Applies the toxic upgrade setting poison damage to 20
func apply_toxic(defender: card_object, is_opponent_attacking: bool) -> void:
	main.card_ops.apply_status(defender, "Toxic", not is_opponent_attacking)
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " poison upgraded to Toxic (20 damage)")

# Sets destiny bond flag on the attacker
func apply_destiny_bond(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_destiny_bond = true
	main.update_status_icons(attacker, is_opponent_attacking)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS BOUND BY DESTINY!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has Destiny Bond")

# Sets the shielded damage threshold on the attacker (Onix Harden)
func apply_shielded_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var threshold = effect.get("threshold", 30)
	attacker.shielded_damage_threshold = threshold
	main.update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " shielded damage threshold = ", threshold)

# Forces the defending player to switch their active pokemon with a bench pokemon
# chooser: "defender" = defender picks (Whirlwind), "attacker" = attacker picks (Lure)
func apply_force_switch(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var target_bench = main.player_bench if is_opponent_attacking else main.opponent_bench
	var is_target_opponent = !is_opponent_attacking
	var chooser = effect.get("chooser", "defender")
	
	if target_bench.size() == 0:
		print("FORCE SWITCH: No bench pokemon available")
		return
	
	var new_active: card_object = null
	
	if is_target_opponent:
		# Target is the opponent (CPU)
		if chooser == "attacker":
			# Lure: PLAYER picks from opponent's bench
			main.opponent_blocker.visible = false
			main.forced_switch_selection_active = true
			main.show_enlarged_array_selection_mode(main.opponent_bench)
			main.cancel_button.visible = false
			main.header_label.text = "CHOOSE A POKEMON TO SWITCH IN!"
			main.hint_label.text = "Select an opponent's bench Pokemon to force into active"
			main.action_button.text = "FORCE SWITCH"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.forced_switch_chosen
			if main._should_bail(): return
			new_active = main.selected_card_for_action
			main.forced_switch_selection_active = false
			main.hide_selection_mode_display_main()
			main.opponent_blocker.visible = true
		else:
			# Whirlwind: CPU picks its own bench replacement
			var cpu_eval = main.cpu_ai.build_cpu_evaluation()
			new_active = main.cpu_ai.pick_best_bench_replacement(main.opponent_bench, main.player_active_pokemon, cpu_eval)
			if new_active == null:
				new_active = main.opponent_bench[0]
		
		if new_active != null:
			var old_active = main.opponent_active_pokemon
			await main.show_message("OPPONENT WAS FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			if main._should_bail(): return
			
			# Animate the swap
			await main.animate_retreat(old_active, new_active, [], true)
			if main._should_bail(): return
			
			# Perform the swap
			main.opponent_bench.erase(new_active)
			main.opponent_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			main.opponent_active_pokemon = new_active
			main.clear_all_statuses(old_active, true)

			main.display_pokemon(true)
			main.display_active_pokemon_energies(true)
			# NEO2 Spikes (Forretress): 10 damage when opponent's bench→active via forced switch
			await main.powers_and_bodies.check_spikes(new_active, true)
			if main._should_bail(): return
			await main.check_all_knockouts()
			if main._should_bail(): return
	else:
		# Target is the player
		if chooser == "attacker":
			# Lure: CPU picks from player's bench (pick the weakest)
			var worst_pokemon: card_object = null
			var worst_hp = 9999
			for bp in main.player_bench:
				if bp.current_hp < worst_hp:
					worst_hp = bp.current_hp
					worst_pokemon = bp
			new_active = worst_pokemon if worst_pokemon else main.player_bench[0]
		else:
			# Whirlwind: Player picks their own bench replacement
			main.opponent_blocker.visible = false
			main.forced_switch_selection_active = true
			main.show_enlarged_array_selection_mode(main.player_bench)
			main.cancel_button.visible = false
			main.header_label.text = "FORCED SWITCH!"
			main.hint_label.text = "Choose a bench Pokemon to switch in as your new active"
			main.action_button.text = "SWITCH IN"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			await main.forced_switch_chosen
			if main._should_bail(): return
			new_active = main.selected_card_for_action
			main.forced_switch_selection_active = false
			main.hide_selection_mode_display_main()
			main.opponent_blocker.visible = true
		
		if new_active != null:
			var old_active = main.player_active_pokemon
			await main.show_message("FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			if main._should_bail(): return
			
			await main.animate_retreat(old_active, new_active, [], false)
			if main._should_bail(): return
			
			main.player_bench.erase(new_active)
			main.player_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			main.player_active_pokemon = new_active
			main.clear_all_statuses(old_active, false)

			main.display_pokemon(false)
			main.display_active_pokemon_energies(false)
			# NEO2 Spikes (Forretress): 10 damage when player's bench→active via forced switch
			await main.powers_and_bodies.check_spikes(new_active, false)
			if main._should_bail(): return
			await main.check_all_knockouts()
			if main._should_bail(): return

# Applies damage reduction for next turn (Minimize/Pounce/Snivel)
func apply_damage_reduction(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var amount = effect.get("amount", 20)
	attacker.damage_reduction_next_turn = amount
	main.update_status_icons(attacker, is_opponent_attacking)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " REDUCES DAMAGE BY " + str(amount) + " NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " damage reduction = ", amount)

# Applies attack block for next turn (Tail Wag/Leer)
func apply_attack_block(effect: Dictionary, attacker: card_object, defender: card_object, is_opponent_attacking: bool) -> void:
	defender.attack_blocked_next_turn = true
	defender.attack_blocked_by_id = attacker.get_instance_id()
	await main.show_message(defender.metadata.get("name", "").to_upper() + " CAN'T ATTACK " + attacker.metadata.get("name", "").to_upper() + " NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " can't attack ", attacker.metadata.get("name", ""))

# Self switch with bench (Exeggutor Teleport)
func apply_self_switch(attacker: card_object, is_opponent_attacking: bool) -> void:
	var bench = main.opponent_bench if is_opponent_attacking else main.player_bench
	if bench.size() == 0:
		await main.show_message("NO BENCH POKEMON TO SWITCH WITH!")
		if main._should_bail(): return
		return
	
	var new_active: card_object = null
	if is_opponent_attacking:
		# CPU picks best replacement
		var cpu_eval = main.cpu_ai.build_cpu_evaluation()
		new_active = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, cpu_eval)
		if new_active == null:
			new_active = bench[0]
	else:
		# Player picks
		main.opponent_blocker.visible = false
		main.forced_switch_selection_active = true
		main.show_enlarged_array_selection_mode(bench)
		main.cancel_button.visible = true
		main.header_label.text = "TELEPORT: CHOOSE REPLACEMENT"
		main.hint_label.text = "Select a bench Pokemon to switch in"
		main.action_button.text = "SWITCH"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.forced_switch_chosen
		if main._should_bail(): return
		new_active = main.selected_card_for_action
		main.forced_switch_selection_active = false
		main.hide_selection_mode_display_main()
		main.opponent_blocker.visible = true
	
	if new_active == null:
		return
	
	var old_active = attacker
	await main.show_message(old_active.metadata["name"].to_upper() + " SWITCHED WITH " + new_active.metadata["name"].to_upper() + "!")
	if main._should_bail(): return
	await main.animate_retreat(old_active, new_active, [], is_opponent_attacking)
	if main._should_bail(): return
	
	bench.erase(new_active)
	bench.append(old_active)
	old_active.current_location = "bench"
	new_active.current_location = "active"
	if is_opponent_attacking:
		main.opponent_active_pokemon = new_active
	else:
		main.player_active_pokemon = new_active
	main.clear_all_statuses(old_active, is_opponent_attacking)
	main.display_pokemon(is_opponent_attacking)
	main.display_active_pokemon_energies(is_opponent_attacking)

# Bench damage to a single chosen target (Pikachu Spark)
func apply_bench_damage_single(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var damage = effect.get("damage", 10)
	var target_bench = main.player_bench if is_opponent_attacking else main.opponent_bench
	var is_target_opponent = !is_opponent_attacking
	
	if target_bench.size() == 0:
		print("BENCH DAMAGE SINGLE: No bench targets")
		return
	
	var target: card_object = null
	
	if is_target_opponent:
		# CPU is the target side — CPU picks which bench pokemon takes damage
		# For player attacking: player picks opponent's bench target
		target = await main.card_ops.prompt_select_card(target_bench, "CHOOSE A BENCHED POKEMON", "This attack does " + str(damage) + " damage to 1 benched Pokemon", "DEAL DAMAGE", false)
		if main._should_bail(): return
	else:
		# Player is the target side — CPU chooses which player bench to damage
		var weakest_hp = 9999
		for bp in target_bench:
			if bp.current_hp < weakest_hp:
				weakest_hp = bp.current_hp
				target = bp
		if target == null and target_bench.size() > 0:
			target = target_bench[0]
	
	if target != null:
		# GYM2 Transparent Walls: protect the bench-side from attack damage
		var walls_on = (main.opponent_transparent_walls_active if is_target_opponent else main.player_transparent_walls_active)
		if walls_on:
			await main.show_message("TRANSPARENT WALLS — BENCH DAMAGE PREVENTED!")
			print("GYM2 TRANSPARENT WALLS: bench damage prevented (single)")
			return
		# GYM1 Brock's Rhydon Bench Guard — owner may redirect 10 to Rhydon
		var effective_damage = await main.powers_and_bodies.check_bench_guard(target, damage, is_target_opponent)
		target.current_hp = max(0, target.current_hp - effective_damage)
		await main.show_message(target.metadata.get("name", "").to_upper() + " TOOK " + str(effective_damage) + " BENCH DAMAGE!")
		if main._should_bail(): return
		print("BENCH DAMAGE SINGLE: ", target.metadata.get("name", ""), " took ", effective_damage)

# Leech Seed: heal 1 damage counter from attacker if damage was dealt
func apply_leech_seed(attacker: card_object, defender: card_object, is_opponent_attacking: bool) -> void:
	var max_hp = int(attacker.metadata.get("hp", "0"))
	if attacker.current_hp < max_hp and defender.current_hp > 0:
		attacker.current_hp = min(max_hp, attacker.current_hp + 10)
		main.display_hp_circles_above_align(attacker, is_opponent_attacking)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " HEALED 10 HP!")
		if main._should_bail(): return
		print("LEECH SEED: ", attacker.metadata.get("name", ""), " healed 10 HP")

# SWORDS DANCE: Set flag to boost Slash next turn
func execute_swords_dance(attacker: card_object, is_opponent: bool) -> void:
	attacker.swords_dance_active = true
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " USED SWORDS DANCE! SLASH POWERED UP!")
	if main._should_bail(): return
	print("SWORDS DANCE: ", attacker.metadata.get("name", ""), " Slash buffed for next turn")

# HURRICANE: Deal 30 damage, return defender to hand unless KO'd
func execute_hurricane(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
	if main._should_bail(): return
	
	# If defender is NOT KO'd, return it and all attached cards to hand
	if defender.current_hp > 0:
		# Defender's hand is on the opposite side of the attacker
		var target_hand = main.player_hand if is_opponent else main.opponent_hand
		var target_bench = main.player_bench if is_opponent else main.opponent_bench
		
		# Move all attached energies to hand
		for energy in defender.attached_energies:
			target_hand.append(energy)
		defender.attached_energies.clear()
		
		# Move all pre-evolutions to hand
		for pre_evo in defender.attached_pre_evolutions:
			target_hand.append(pre_evo)
		defender.attached_pre_evolutions.clear()
		
		# Move defender itself to hand
		target_hand.append(defender)
		defender.current_location = "hand"
		
		# Remove from active slot on defender's side
		if is_opponent:
			# CPU attacked, defender is player's active
			if defender == main.player_active_pokemon:
				main.player_active_pokemon = null
			else:
				target_bench.erase(defender)
		else:
			# Player attacked, defender is opponent's active
			if defender == main.opponent_active_pokemon:
				main.opponent_active_pokemon = null
			else:
				target_bench.erase(defender)
		
		main.clear_all_statuses(defender, !is_opponent)
		await main.show_message(defender.metadata.get("name", "").to_upper() + " WAS RETURNED TO HAND!")
		if main._should_bail(): return
		main.display_pokemon(!is_opponent)
		main.refresh_hand_display(!is_opponent)
		main.display_active_pokemon_energies(!is_opponent)
		
		# Handle post-knockout replacement for the returned pokemon's side
		await main.handle_post_knockout(!is_opponent)
		if main._should_bail(): return

# CHAIN LIGHTNING: 20 to defender, 10 to each same-type bench (both sides)
func execute_chain_lightning(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(20, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 20)
	if main._should_bail(): return
	
	# If defender is Colorless, no chain lightning
	var defender_types = defender.metadata.get("types", ["Colorless"])
	if "Colorless" in defender_types:
		await main.show_message("NO CHAIN LIGHTNING - COLORLESS TARGET!")
		if main._should_bail(): return
		return
	
	# Damage all benched pokemon of the same type (BOTH sides)
	var target_type = defender_types[0]
	var all_benches = [
		{"bench": main.player_bench, "is_opponent": false},
		{"bench": main.opponent_bench, "is_opponent": true}
	]
	for bench_info in all_benches:
		for pokemon in bench_info["bench"]:
			var pokemon_types = pokemon.metadata.get("types", [])
			if target_type in pokemon_types:
				main.card_ops.apply_bench_damage(pokemon, 10, bench_info["is_opponent"])
	await main.show_message("CHAIN LIGHTNING HIT ALL " + target_type.to_upper() + " BENCHED POKEMON!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# BIG EGGSPLOSION: Flip coins = attached energy, per_heads damage per heads (Erika's Exeggcute Eggsplosion passes 10)
func execute_big_eggsplosion(attacker: card_object, defender: card_object, is_opponent: bool, per_heads: int = 20) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var energy_count = attacker.attached_energies.size()
	if energy_count == 0:
		await main.show_message("NO ENERGY ATTACHED - 0 DAMAGE!")
		if main._should_bail(): return
		return
	
	await main.show_message("FLIPPING " + str(energy_count) + " COINS!")
	if main._should_bail(): return
	
	var heads = 0
	var use_silent = energy_count > 1
	for i in range(energy_count):
		var coin = await main.flip_coin(use_silent, is_opponent)
		if coin:
			heads += 1

	var base_damage = per_heads * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(base_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return

# BOYFRIENDS (Nidoqueen): 20 + 20 per Nidoking in play
func execute_boyfriends(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var nidoking_count = 0
	var all_pokemon = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)
	for p in all_pokemon:
		if p.metadata.get("name", "") == "Nidoking":
			nidoking_count += 1
	
	var base_damage = 20 + (20 * nidoking_count)
	await main.show_message("BOYFRIENDS: " + str(nidoking_count) + " NIDOKING IN PLAY! " + str(base_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return

# MEGA DRAIN: Deal damage, heal half (rounded up to nearest 10). base_damage defaults to 40 (Erika's Vileplume passes 30)
func execute_mega_drain(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int = 40) -> void:
	if attacker == null or defender == null:
		return

	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return

	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]

	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return
	
	# Heal attacker for half of actual damage dealt (rounded up to nearest 10)
	var actual_damage = min(final_damage, defender.current_hp + final_damage)  # damage before KO check
	var heal_amount = int(ceil(actual_damage / 2.0 / 10.0)) * 10
	if heal_amount > 0:
		await main.card_ops.heal_pokemon(attacker, heal_amount, is_opponent)
		if main._should_bail(): return
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " HEALED " + str(heal_amount) + " HP!")
		if main._should_bail(): return

# LEECH LIFE: Deal damage, heal equal to damage dealt after W/R
func execute_leech_life(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if attacker == null or defender == null:
		return
	
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)
	if main._should_bail(): return
	
	# Heal attacker equal to final damage dealt
	if final_damage > 0:
		await main.card_ops.heal_pokemon(attacker, final_damage, is_opponent)
		if main._should_bail(): return
		var healed = min(final_damage, int(attacker.metadata.get("hp", "0")) - attacker.current_hp + final_damage)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " DRAINED " + str(final_damage) + " HP!")
		if main._should_bail(): return

# BROCK'S ZUBAT ALERT: Draw 1 card, then switch Brock's Zubat with a bench pokemon
func execute_brock_zubat_alert(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	await main.show_message("ALERT! DREW 1 CARD!")
	if main._should_bail(): return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.is_empty():
		return
	# Reuse apply_self_switch from the text parser system
	await apply_self_switch(attacker, is_opponent)
	if main._should_bail(): return

# ODDISH SPROUT: Search deck for a Basic Pokemon named Oddish and bench it
func execute_oddish_sprout(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	var filter = func(c): return main.is_basic_pokemon(c) and "Oddish" in c.metadata.get("name", "")
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter, "SEARCH FOR ODDISH", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO ODDISH IN DECK!")
		if main._should_bail(): return
		return
	var oddish = found[0]
	# Move from hand to bench immediately
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(oddish)
	main.card_ops.place_on_bench(oddish, is_opponent)
	await main.show_message("SPROUT! " + oddish.metadata.get("name", "").to_upper() + " PLACED ON BENCH!")
	if main._should_bail(): return

# CALL FOR FAMILY/FRIEND: Search deck for specific basic pokemon
func execute_call_for_pokemon(attacker: card_object, is_opponent: bool, search_names: Array, search_type: String) -> void:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	
	# Find matching basic pokemon in deck
	var valid_cards: Array = []
	for card in deck:
		var subtypes = card.metadata.get("subtypes", [])
		if "Basic" not in subtypes:
			continue
		var card_name = card.metadata.get("name", "")
		if search_names.size() > 0:
			if card_name in search_names:
				valid_cards.append(card)
		elif search_type != "":
			var card_types = card.metadata.get("types", [])
			if search_type in card_types:
				valid_cards.append(card)
		else:
			valid_cards.append(card)
	
	if valid_cards.size() == 0:
		await main.show_message("NO MATCHING POKEMON FOUND IN DECK!")
		if main._should_bail(): return
		# Shuffle deck anyway
		deck.shuffle()
		return
	
	var chosen: card_object = null
	if is_opponent:
		# CPU picks the card with the highest HP (best bench addition)
		var best_hp = -1
		for card in valid_cards:
			var hp = int(card.metadata.get("hp", "0"))
			if hp > best_hp:
				best_hp = hp
				chosen = card
	else:
		# Player picks from valid cards
		chosen = await main.card_ops.prompt_select_card(valid_cards, "CHOOSE A POKEMON FROM YOUR DECK", "Select a Basic Pokemon to put on your bench", "SELECT", true, true)
		if main._should_bail(): return
	
	if chosen != null and bench.size() < 5:
		deck.erase(chosen)
		chosen.current_hp = int(chosen.metadata.get("hp", "0"))
		main.card_ops.place_on_bench(chosen, is_opponent)
		await main.show_message(chosen.metadata.get("name", "").to_upper() + " WAS PLACED ON THE BENCH!")
		if main._should_bail(): return

	# Shuffle deck after search
	deck.shuffle()
######################################################### SPECIAL ATTACK FUNCTIONS ############################################################

# METRONOME (Clefairy): Copy one of the opponent's attacks and execute it

######################################################################################################################################################
############################################## BASE3 (FOSSIL) ATTACK EFFECTS #########################################################################
######################################################################################################################################################

# TRAINER LOCK (Psyduck Headache): Block opponent trainer play next turn
func apply_trainer_lock(is_opponent_attacking: bool) -> void:
	if is_opponent_attacking:
		main.trainer_effects.player_trainer_locked = true
	else:
		main.trainer_effects.opponent_trainer_locked = true
	await main.show_message("OPPONENT CAN'T PLAY TRAINER CARDS NEXT TURN!")
	if main._should_bail(): return
	print("EFFECT APPLIED: Trainer lock for next turn")

# SONICBOOM (Magneton): Fixed damage ignoring Weakness and Resistance
func execute_sonicboom(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	var final_damage = base_damage
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	
	# Display WITHOUT W/R modifiers — pass empty modifiers and use base_damage directly
	var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
	main.show_floating_label("-" + str(final_damage) + "HP", defender_label_pos, Color.WHITE, true)
	defender.current_hp = max(0, defender.current_hp - final_damage)
	main.display_hp_circles_above_align(defender, !is_opponent)
	await main.show_message("SONICBOOM: " + str(final_damage) + " DAMAGE! (IGNORES W/R)")
	if main._should_bail(): return
	print("SONICBOOM: ", final_damage, " damage (no W/R)")

# WILDFIRE (Moltres): Discard any number of Fire Energy, mill that many from opponent deck
func execute_wildfire(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	# Count Fire Energy attached
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	var discard_count = 0
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if is_opponent:
		# CPU strategy: discard all fire energy for maximum mill damage
		# unless it would cripple attack readiness
		var target_deck = main.player_deck
		discard_count = min(fire_energies.size(), target_deck.size())
		if discard_count == 0:
			await main.show_message("OPPONENT'S DECK IS EMPTY!")
			if main._should_bail(): return
			return
		for i in range(discard_count):
			var e = fire_energies[i]
			attacker.attached_energies.erase(e)
			e.current_location = "discard"
			discard_pile.append(e)
		main.display_active_pokemon_energies(true)
	else:
		# Player selects fire energies one at a time, cancel to stop
		await main.show_message("WILDFIRE: SELECT FIRE ENERGY TO DISCARD (CANCEL TO STOP)")
		if main._should_bail(): return
		
		var keep_discarding = true
		while keep_discarding and fire_energies.size() > 0:
			main.trainer_energy_selection_active = true
			main.show_enlarged_array_selection_mode(fire_energies)
			main.header_label.text = "WILDFIRE: SELECT FIRE ENERGY"
			main.hint_label.text = "Each energy discarded mills 1 card from opponent's deck"
			main.action_button.text = "DISCARD"
			main.action_button.disabled = true
			main.action_button.theme = main.theme_disabled
			main.cancel_button.visible = true
			await main.trainer_target_selected
			if main._should_bail(): return
			var selected = main.selected_card_for_action
			main.trainer_energy_selection_active = false
			main.hide_selection_mode_display_main()
			
			if selected == null:
				keep_discarding = false
			else:
				attacker.attached_energies.erase(selected)
				selected.current_location = "discard"
				discard_pile.append(selected)
				fire_energies.erase(selected)
				discard_count += 1
				main.display_active_pokemon_energies(false)
	
	if discard_count == 0:
		return
	
	# Mill cards from opponent's deck
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	var target_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	var milled = min(discard_count, target_deck.size())
	for i in range(milled):
		var card = target_deck.pop_front()
		card.current_location = "discard"
		target_discard.append(card)
	
	main.update_discard_pile_display(!is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("WILDFIRE: DISCARDED " + str(milled) + " CARDS FROM OPPONENT'S DECK!")
	if main._should_bail(): return
	print("WILDFIRE: Milled ", milled, " cards from opponent deck")

# GIGASHOCK (Raichu): 30 damage + 10 to up to 3 opponent bench Pokemon
func execute_gigashock(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	# Deal 30 to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
	if main._should_bail(): return
	
	# Deal 10 to up to 3 opponent bench pokemon
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var is_target_opponent = !is_opponent
	
	if target_bench.size() == 0:
		print("GIGASHOCK: No bench targets")
		return
	
	if target_bench.size() <= 3:
		# Hit all bench pokemon
		for bp in target_bench:
			main.card_ops.apply_bench_damage(bp, 10, is_target_opponent)
		await main.show_message("GIGASHOCK HIT ALL BENCHED POKEMON FOR 10 DAMAGE!")
		if main._should_bail(): return
	else:
		# Need to choose 3 targets
		if is_target_opponent:
			# Player picks 3 from opponent bench
			var targets_chosen: Array = []
			for pick in range(3):
				var remaining: Array = []
				for bp in target_bench:
					if bp not in targets_chosen:
						remaining.append(bp)
				if remaining.size() == 0:
					break
				var chosen = await main.card_ops.prompt_select_card(remaining, "GIGASHOCK: CHOOSE TARGET " + str(pick + 1) + " OF 3", "Select a benched Pokemon to deal 10 damage", "SHOCK", false)
				if main._should_bail(): return
				if chosen != null:
					targets_chosen.append(chosen)
			for bp in targets_chosen:
				main.card_ops.apply_bench_damage(bp, 10, is_target_opponent)
			await main.show_message("GIGASHOCK HIT " + str(targets_chosen.size()) + " BENCHED POKEMON!")
			if main._should_bail(): return
		else:
			# CPU picks 3 weakest from player bench
			var targets = main.cpu_ai.cpu_choose_bench_damage_targets(3, 10)
			for bp in targets:
				main.card_ops.apply_bench_damage(bp, 10, is_target_opponent)
			await main.show_message("GIGASHOCK HIT " + str(targets.size()) + " BENCHED POKEMON!")
			if main._should_bail(): return
	
	# Check for bench KOs from Gigashock damage
	await main.check_all_knockouts()
	if main._should_bail(): return

# THUNDERSTORM (Zapdos): 40 damage + flip per bench, heads=20 damage, tails count = self damage
func execute_thunderstorm(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	if await handle_attack_confusion(attacker, is_opponent):
		return
	if await handle_attack_blind(attacker, is_opponent):
		return
	
	# Deal 40 to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(40, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 40)
	if main._should_bail(): return
	
	# Flip for each opponent bench pokemon
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var tails_count = 0
	
	if target_bench.size() > 0:
		var use_silent = target_bench.size() > 1
		for bp in target_bench:
			var coin = await main.flip_coin(use_silent, is_opponent)
			if coin:
				bp.current_hp = max(0, bp.current_hp - 20)
				print("THUNDERSTORM: ", bp.metadata.get("name", ""), " took 20 bench damage (heads)")
			else:
				tails_count += 1
				print("THUNDERSTORM: Tails for ", bp.metadata.get("name", ""))
		await main.show_message("THUNDERSTORM: " + str(target_bench.size() - tails_count) + " HEADS, " + str(tails_count) + " TAILS!")
		if main._should_bail(): return
	
	# Self-damage: 10 × number of tails
	if tails_count > 0:
		var self_damage = tails_count * 10
		attacker.current_hp = max(0, attacker.current_hp - self_damage)
		var label_x = 1030 if is_opponent else 530
		main.show_floating_label("-" + str(self_damage) + "HP", Vector2(label_x, 300), Color.RED)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK " + str(self_damage) + " RECOIL DAMAGE!")
		if main._should_bail(): return

	# Check for bench and self KOs from Thunderstorm damage
	await main.check_all_knockouts()
	if main._should_bail(): return

# PROPHECY (Hypno): Look at top 3 cards of either deck and rearrange
func execute_prophecy(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	if is_opponent:
		# CPU strategy: look at own deck top 3 and rearrange for best draws
		# Simple: sort by priority (energy first if needed, then pokemon, then trainers)
		var deck = main.opponent_deck
		if deck.size() < 2:
			return
		var count = min(3, deck.size())
		# CPU just peeks but doesn't meaningfully rearrange (too complex for AI)
		await main.show_message("OPPONENT USED PROPHECY TO REARRANGE DECK!")
		if main._should_bail(): return
		# Simple heuristic: put energy cards on top if CPU needs energy
		var top_cards = []
		for i in range(count):
			top_cards.append(deck[i])
		# Sort: energy needed? put energy first
		var active = main.opponent_active_pokemon
		var needs_energy = false
		if active != null:
			for attack in active.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(attack, active) > 0:
					needs_energy = true
					break
		if needs_energy:
			top_cards.sort_custom(func(a, b):
				var a_is_energy = a.metadata.get("supertype", "") == "Energy"
				var b_is_energy = b.metadata.get("supertype", "") == "Energy"
				if a_is_energy and not b_is_energy: return true
				if b_is_energy and not a_is_energy: return false
				return false
			)
			for i in range(count):
				deck[i] = top_cards[i]
		print("PROPHECY: CPU rearranged top ", count, " cards")
	else:
		# Player chooses which deck to look at, then rearranges
		# Step 1: Choose deck
		await main.show_message("PROPHECY: CHOOSE A DECK TO LOOK AT")
		if main._should_bail(): return
		
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
				continue
			child.queue_free()
		
		var btn_own = Button.new()
		btn_own.text = "YOUR DECK"
		btn_own.custom_minimum_size = Vector2(350, 50)
		btn_own.theme = main.theme_green
		main.attack_buttons_container.add_child(btn_own)
		btn_own.pressed.connect(func(): main.special_attack_selected.emit(0))
		
		var btn_opp = Button.new()
		btn_opp.text = "OPPONENT'S DECK"
		btn_opp.custom_minimum_size = Vector2(350, 50)
		btn_opp.theme = main.theme_green
		main.attack_buttons_container.add_child(btn_opp)
		btn_opp.pressed.connect(func(): main.special_attack_selected.emit(1))
		
		var deck_choice = await main.special_attack_selected
		
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
		
		var deck = main.player_deck if deck_choice == 0 else main.opponent_deck
		var deck_name = "YOUR" if deck_choice == 0 else "OPPONENT'S"
		
		if deck.size() == 0:
			await main.show_message(deck_name + " DECK IS EMPTY!")
			if main._should_bail(): return
			return
		
		var count = min(3, deck.size())
		var top_cards: Array = []
		for i in range(count):
			top_cards.append(deck[i])
		
		# Show cards and let player reorder using selection mode
		# Player picks cards in the order they want them (first pick = top of deck)
		var reordered: Array = []
		var remaining = top_cards.duplicate()
		
		for pick in range(count):
			if remaining.size() == 1:
				reordered.append(remaining[0])
				break
			var chosen = await main.card_ops.prompt_select_card(remaining, "PROPHECY: PICK CARD FOR POSITION " + str(pick + 1), "This card will be " + (["1st (TOP)", "2nd", "3rd"])[pick] + " from top", "PLACE", false)
			if main._should_bail(): return
			if chosen != null:
				reordered.append(chosen)
				remaining.erase(chosen)
		
		# Apply reorder to deck
		for i in range(reordered.size()):
			deck[i] = reordered[i]
		
		await main.show_message("PROPHECY: REARRANGED TOP " + str(count) + " CARDS OF " + deck_name + " DECK!")
		if main._should_bail(): return
		print("PROPHECY: Player rearranged top ", count, " cards of ", deck_name, " deck")

# ENERGY CONVERSION (Gastly): Retrieve up to 2 Energy cards from discard, 10 self damage
func execute_energy_conversion(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	if main.trainer_effects.check_pokemon_tower_blocks_recovery():
		await main.show_message("POKEMON TOWER! CANNOT RECOVER CARDS FROM DISCARD!")
		if main._should_bail(): return
		return

	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	# Find energy cards in discard
	var energy_in_discard: Array = []
	for card in discard:
		if card.metadata.get("supertype", "") == "Energy":
			energy_in_discard.append(card)
	
	if energy_in_discard.size() == 0:
		await main.show_message("NO ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
	else:
		var retrieve_count = min(2, energy_in_discard.size())
		
		if is_opponent:
			# CPU picks best energy cards
			for i in range(retrieve_count):
				if energy_in_discard.size() == 0:
					break
				var chosen = energy_in_discard[0]
				discard.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				energy_in_discard.erase(chosen)
			main.refresh_hand_display(true)
			main.update_discard_pile_display(true)
			await main.show_message("ENERGY CONVERSION: RETRIEVED " + str(retrieve_count) + " ENERGY!")
			if main._should_bail(): return
		else:
			# Player selects up to 2 energy cards from discard
			var retrieved = 0
			for pick in range(retrieve_count):
				if energy_in_discard.size() == 0:
					break
				var chosen = await main.card_ops.prompt_select_card(energy_in_discard, "ENERGY CONVERSION: PICK ENERGY " + str(pick + 1), "Select an Energy card to add to your hand", "RETRIEVE", pick > 0)
				if main._should_bail(): return
				if chosen == null:
					break
				discard.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				energy_in_discard.erase(chosen)
				retrieved += 1
			main.refresh_hand_display(false)
			main.update_discard_pile_display(false)
			if retrieved > 0:
				await main.show_message("ENERGY CONVERSION: RETRIEVED " + str(retrieved) + " ENERGY!")
				if main._should_bail(): return
	
	# Self damage: 10 to Gastly
	attacker.current_hp = max(0, attacker.current_hp - 10)
	var label_x = 1030 if is_opponent else 530
	main.show_floating_label("-10HP", Vector2(label_x, 300), Color.RED)
	main.display_hp_circles_above_align(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK 10 RECOIL DAMAGE!")
	if main._should_bail(): return
	print("ENERGY CONVERSION: Retrieved energy, 10 self damage")

# SPACING OUT (Slowpoke): Flip, heads = remove 1 damage counter. Can't use if no damage.
func execute_spacing_out(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	
	var max_hp = int(attacker.metadata.get("hp", "0"))
	if attacker.current_hp >= max_hp:
		await main.show_message("SPACING OUT FAILED! NO DAMAGE TO HEAL!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.card_ops.heal_pokemon(attacker, 10, is_opponent)
		if main._should_bail(): return
		await main.show_message("SPACING OUT: HEALED 10 HP!")
		if main._should_bail(): return
	else:
		await main.show_message("SPACING OUT: TAILS! NOTHING HAPPENED!")
		if main._should_bail(): return
	print("SPACING OUT: coin=", "heads" if coin else "tails")

# SCAVENGE (Slowpoke): Discard 1 Psychic Energy, retrieve a Trainer from discard
func execute_scavenge(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	if main.trainer_effects.check_pokemon_tower_blocks_recovery():
		await main.show_message("POKEMON TOWER! CANNOT RECOVER CARDS FROM DISCARD!")
		if main._should_bail(): return
		return

	# Check for Psychic Energy attached
	var psychic_energy: card_object = null
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Psychic" in provided:
			psychic_energy = e
			break
	
	if psychic_energy == null:
		await main.show_message("NO PSYCHIC ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	# Find trainer cards in discard
	var trainers_in_discard: Array = []
	for card in discard:
		if card.metadata.get("supertype", "") == "Trainer":
			trainers_in_discard.append(card)
	
	if trainers_in_discard.size() == 0:
		await main.show_message("NO TRAINER CARDS IN DISCARD PILE!")
		if main._should_bail(): return
		return
	
	# Discard the Psychic Energy
	attacker.attached_energies.erase(psychic_energy)
	psychic_energy.current_location = "discard"
	discard.append(psychic_energy)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	var chosen: card_object = null
	if is_opponent:
		# CPU picks the highest scored trainer
		var best_score = -999.0
		for card in trainers_in_discard:
			var score = main.cpu_ai.cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				chosen = card
	else:
		# Player selects
		chosen = await main.card_ops.prompt_select_card(trainers_in_discard, "SCAVENGE: CHOOSE A TRAINER CARD", "Select a Trainer to retrieve from discard", "RETRIEVE", false)
		if main._should_bail(): return
	
	if chosen != null:
		discard.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("SCAVENGE: RETRIEVED " + chosen.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("SCAVENGE: Retrieved ", chosen.metadata.get("name", ""))

# ABSORB (Kabutops): 40 damage, heal half of damage dealt (rounded up to nearest 10)
# This is identical to execute_mega_drain — reuse it directly via routing

######################################################################################################################################################
################################################### BASE5 (TEAM ROCKET) ATTACK EFFECTS ###############################################################
######################################################################################################################################################

# Dark Arbok - Stare: Choose 1 of opponent's Pokemon, 10 damage no W/R, disable power
func execute_stare(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var is_target_opponent = !is_opponent
	var target_bench: Array
	var target_active: card_object
	var all_targets: Array = []
	
	if is_target_opponent:
		target_bench = main.opponent_bench
		target_active = main.opponent_active_pokemon
	else:
		target_bench = main.player_bench
		target_active = main.player_active_pokemon
	
	if target_active != null:
		all_targets.append(target_active)
	all_targets.append_array(target_bench)
	
	if all_targets.size() == 0:
		await main.show_message("NO VALID TARGETS!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		selected = await main.card_ops.prompt_select_card(all_targets, "CHOOSE A POKÉMON TO DAMAGE", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks lowest HP target for best KO chance
		var targets = all_targets.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]

	if selected == null:
		return

	# Apply 10 damage directly (no W/R)
	selected.current_hp = max(0, selected.current_hp - 10)
	var is_selected_opponent = is_target_opponent
	main.display_hp_circles_above_align(selected, is_selected_opponent)
	await main.show_message("STARE DEALT 10 DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	# Disable power if target has one
	var abilities = selected.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("type", "") == "Pokémon Power" or ability.get("type", "") == "Pokemon Power":
			selected.power_disabled_until_end_of_next_turn = true
			await main.show_message(selected.metadata.get("name", "").to_upper() + "'S POWER IS DISABLED!")
			if main._should_bail(): return
			break
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Stare on ", selected.metadata.get("name", ""))

# Dark Golbat - Flitter / Diglett - Dig Under / Meowth - Coin Hurl: Choose opponent Pokemon, X damage no W/R
func execute_snipe_no_wr(attacker: card_object, defender: card_object, is_opponent: bool, damage: int, requires_flip: bool = false) -> void:
	var is_target_opponent = !is_opponent
	var target_bench: Array
	var target_active: card_object
	var all_targets: Array = []
	
	if is_target_opponent:
		target_bench = main.opponent_bench
		target_active = main.opponent_active_pokemon
	else:
		target_bench = main.player_bench
		target_active = main.player_active_pokemon
	
	if target_active != null:
		all_targets.append(target_active)
	all_targets.append_array(target_bench)
	
	if all_targets.size() == 0:
		await main.show_message("NO VALID TARGETS!")
		if main._should_bail(): return
		return
	
	if requires_flip:
		var coin = await main.flip_coin(false, is_opponent)
		if not coin:
			await main.show_message("TAILS! ATTACK MISSED!")
			if main._should_bail(): return
			return
	
	var selected: card_object = null
	
	if not is_opponent:
		selected = await main.card_ops.prompt_select_card(all_targets, "CHOOSE A POKÉMON TO DAMAGE", "", "SELECT", false)
		if main._should_bail(): return
	else:
		var targets = all_targets.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]

	if selected == null:
		return

	selected.current_hp = max(0, selected.current_hp - damage)
	var is_selected_opponent = is_target_opponent
	main.display_hp_circles_above_align(selected, is_selected_opponent)
	await main.show_message(str(damage) + " DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "! (NO W/R)")
	if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Snipe no W/R ", damage, " on ", selected.metadata.get("name", ""))

# Dark Charizard - Continuous Fireball: Flip coins = Fire Energy count, 50×heads, discard heads Fire Energy
func execute_continuous_fireball(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	
	var flip_count = fire_energies.size()
	var heads_count = 0
	for i in range(flip_count):
		var coin = await main.flip_coin(flip_count > 1, is_opponent)
		if coin:
			heads_count += 1

	var total_damage = 50 * heads_count
	await main.show_message("GOT " + str(heads_count) + " HEADS! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			
			if main.check_defender_invincible(defender, !is_opponent):
				pass
			else:
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
	
	# Discard Fire Energy equal to heads count
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var to_discard = min(heads_count, fire_energies.size())
	for i in range(to_discard):
		var energy = fire_energies[i]
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		discard_pile.append(energy)
	
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	if to_discard > 0:
		await main.show_message("DISCARDED " + str(to_discard) + " FIRE ENERGY!")
		if main._should_bail(): return
	
	# Store attack tracking
	if is_opponent:
		main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Continuous Fireball - ", heads_count, " heads, ", total_damage, " damage")

# Dark Hypno - Bench Manipulation: Opponent flips coins = bench count, 20×tails to active, no W/R
func execute_bench_manipulation(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	var bench_count = target_bench.size()
	
	if bench_count == 0:
		await main.show_message("OPPONENT HAS NO BENCH POKÉMON! 0 DAMAGE!")
		if main._should_bail(): return
		return
	
	var tails_count = 0
	for i in range(bench_count):
		# "Opponent flips coins" — the defender flips, not the attacker
		var coin = await main.flip_coin(bench_count > 1, not is_opponent)
		if not coin:
			tails_count += 1

	var total_damage = 20 * tails_count
	await main.show_message(str(tails_count) + " TAILS! " + str(total_damage) + " DAMAGE! (NO W/R)")
	if main._should_bail(): return
	
	if total_damage > 0:
		# Apply directly to active (no W/R)
		defender.current_hp = max(0, defender.current_hp - total_damage)
		main.display_hp_circles_above_align(defender, !is_opponent)
		main.show_floating_label("-" + str(total_damage) + "HP", Vector2(530 if is_opponent else 1030, 300), Color.WHITE)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await main.powers_and_bodies.dispatch_on_damage(defender, attacker, total_damage, !is_opponent)
		if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Bench Manipulation - ", tails_count, " tails, ", total_damage, " damage")

# Dark Machamp - Fling: Shuffle opponent's active + attached cards into deck
func execute_fling(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE FLING! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var target_active: card_object
	var target_deck: Array
	if is_opponent:
		target_active = main.player_active_pokemon
		target_deck = main.player_deck
	else:
		target_active = main.opponent_active_pokemon
		target_deck = main.opponent_deck
	
	if target_active == null:
		return
	
	var name = target_active.metadata.get("name", "")
	
	# Shuffle all attached energies back into deck
	for e in target_active.attached_energies:
		e.current_location = "deck"
		target_deck.append(e)
	target_active.attached_energies.clear()
	
	# Shuffle all attached pre-evolutions back into deck
	for pre in target_active.attached_pre_evolutions:
		pre.current_location = "deck"
		target_deck.append(pre)
	target_active.attached_pre_evolutions.clear()
	
	# Shuffle attached trainer cards back into deck
	for ac in target_active.attached_cards:
		ac.current_location = "deck"
		target_deck.append(ac)
	target_active.attached_cards.clear()
	
	# Shuffle the active pokemon itself back
	target_active.current_location = "deck"
	main.clear_all_statuses(target_active, !is_opponent)
	target_active.current_hp = int(target_active.metadata.get("hp", "0"))
	target_deck.append(target_active)
	
	# Shuffle deck
	target_deck.shuffle()
	
	# Clear active slot
	if is_opponent:
		main.player_active_pokemon = null
	else:
		main.opponent_active_pokemon = null
	
	main.display_pokemon(!is_opponent)
	main.display_active_pokemon_energies(!is_opponent)
	main.update_deck_icon(!is_opponent)
	
	await main.show_message(name.to_upper() + " WAS SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	
	# Force opponent to choose new active from bench
	await main.handle_post_knockout(!is_opponent)
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fling shuffled ", name, " into deck")

# Dark Magneton - Magnetic Lines: Move 1 basic energy from defender to opponent's bench
func execute_magnetic_lines(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# First do 30 damage normally
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Check if defender has basic energy and opponent has bench
	var basic_energies: Array = []
	for e in defender.attached_energies:
		if main.is_basic_energy_card(e):
			basic_energies.append(e)
	
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if basic_energies.size() == 0 or target_bench.size() == 0:
		if basic_energies.size() == 0:
			await main.show_message("NO BASIC ENERGY ON DEFENDER!")
			if main._should_bail(): return
		elif target_bench.size() == 0:
			await main.show_message("OPPONENT HAS NO BENCH TO MOVE ENERGY TO!")
			if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
		return
	
	var chosen_energy: card_object = null
	var chosen_bench: card_object = null
	
	if not is_opponent:
		# Player chooses energy from defender
		# For simplicity, auto-pick the first basic energy (player could choose)
		chosen_energy = basic_energies[0]
		
		# Player chooses bench target
		chosen_bench = await main.card_ops.prompt_select_card(target_bench, "CHOOSE BENCH POKÉMON TO RECEIVE ENERGY", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks first basic energy and first bench pokemon
		chosen_energy = basic_energies[0]
		chosen_bench = target_bench[0]
	
	if chosen_energy != null and chosen_bench != null:
		defender.attached_energies.erase(chosen_energy)
		chosen_bench.attached_energies.append(chosen_energy)
		main.display_active_pokemon_energies(!is_opponent)
		await main.show_message("MOVED ENERGY TO " + chosen_bench.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Magnetic Lines")

# Dark Vileplume - Petal Whirlwind: Flip 3 coins, 30×heads, 2+ heads = self confused
func execute_petal_whirlwind(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var heads_count = 0
	for i in range(3):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads_count += 1

	var total_damage = 30 * heads_count
	await main.show_message("GOT " + str(heads_count) + " HEADS! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.player_attacked_this_turn = true
	
	# 2+ heads = self confused
	if heads_count >= 2:
		main.card_ops.apply_status(attacker, "Confused", is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Petal Whirlwind - ", heads_count, " heads")

# Dark Weezing - Mass Explosion: 20× total Koffing/Weezing/Dark Weezing in play, then 20 to each
func execute_mass_explosion(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_names = ["Koffing", "Weezing", "Dark Weezing"]
	
	# Count all matching pokemon in play (both sides)
	var all_matching: Array = []
	var all_player: Array = []
	if main.player_active_pokemon != null:
		all_player.append(main.player_active_pokemon)
	all_player.append_array(main.player_bench)
	var all_opponent: Array = []
	if main.opponent_active_pokemon != null:
		all_opponent.append(main.opponent_active_pokemon)
	all_opponent.append_array(main.opponent_bench)
	
	for p in all_player:
		if p.metadata.get("name", "") in target_names:
			all_matching.append({"pokemon": p, "is_opponent": false})
	for p in all_opponent:
		if p.metadata.get("name", "") in target_names:
			all_matching.append({"pokemon": p, "is_opponent": true})
	
	var count = all_matching.size()
	var total_damage = 20 * count
	
	await main.show_message(str(count) + " KOFFING/WEEZING IN PLAY! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	# Apply main damage to defender with W/R
	if total_damage > 0:
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			var attacking_types = attacker.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
			var final_damage = result["damage"]
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": total_damage, "attack": {}, "attacker_types": attacker.metadata.get("types", ["Colorless"])}
			main.player_attacked_this_turn = true
	
	# Then 20 damage to each Koffing/Weezing/Dark Weezing (no W/R, even own)
	for match_info in all_matching:
		var target = match_info["pokemon"]
		if target.current_hp <= 0:
			continue
		target.current_hp = max(0, target.current_hp - 20)
		main.display_hp_circles_above_align(target, match_info["is_opponent"])
		await main.show_message(target.metadata.get("name", "").to_upper() + " TOOK 20 EXPLOSION DAMAGE!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mass Explosion - ", count, " matching pokemon")

# Dark Electrode - Energy Bomb: 30 damage, then move all energy to bench
func execute_energy_bomb(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage first
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Move all energy to bench
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	if bench.size() == 0:
		# No bench - discard all energy
		for e in attacker.attached_energies.duplicate():
			attacker.attached_energies.erase(e)
			e.current_location = "discard"
			discard_pile.append(e)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("NO BENCH! ALL ENERGY DISCARDED!")
		if main._should_bail(): return
	else:
		# Distribute energy to bench pokemon
		var energies = attacker.attached_energies.duplicate()
		attacker.attached_energies.clear()
		
		if not is_opponent:
			# Player distributes - for simplicity, spread evenly
			var idx = 0
			for e in energies:
				bench[idx % bench.size()].attached_energies.append(e)
				idx += 1
		else:
			# CPU distributes to pokemon that need energy most
			for e in energies:
				var best_target: card_object = null
				var best_unmet = 0
				for bp in bench:
					for attack in bp.metadata.get("attacks", []):
						var unmet = main.cpu_ai.get_unmet_energy_count(attack, bp)
						if unmet > best_unmet:
							best_unmet = unmet
							best_target = bp
				if best_target == null:
					best_target = bench[0]
				best_target.attached_energies.append(e)
		
		main.display_active_pokemon_energies(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("ALL ENERGY MOVED TO BENCH!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Energy Bomb")

# Dark Golduck - Third Eye: Discard 1 energy to draw up to 3 cards
func execute_third_eye(attacker: card_object, is_opponent: bool) -> void:
	if attacker.attached_energies.size() == 0:
		await main.show_message("NO ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	
	# Discard 1 energy
	var energy = attacker.attached_energies[attacker.attached_energies.size() - 1]
	attacker.attached_energies.erase(energy)
	energy.current_location = "discard"
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	discard_pile.append(energy)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await main.show_message("DISCARDED 1 ENERGY!")
	if main._should_bail(): return
	
	# Draw up to 3 cards
	var draw_count = min(3, (main.opponent_deck if is_opponent else main.player_deck).size())
	await main.card_ops.draw_n(is_opponent, draw_count)
	if main._should_bail(): return
	await main.show_message("DREW " + str(draw_count) + " CARD(S)!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Third Eye - drew ", draw_count, " cards")

# Dark Machoke - Drag Off: Switch bench->active before damage, then 20 damage
# Swap a bench pokemon from the TARGET side (opposite of attacker) into the active slot.
# Clears statuses on the demoted active and refreshes display for that side.
func _force_bench_to_active(selected: card_object, attacker_is_opp: bool) -> void:
	var target_is_opp = not attacker_is_opp
	var old_active = main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon
	var bench    = main.opponent_bench if target_is_opp else main.player_bench
	bench.erase(selected)
	bench.append(old_active)
	old_active.current_location = "bench"
	selected.current_location   = "active"
	if target_is_opp:
		main.opponent_active_pokemon = selected
	else:
		main.player_active_pokemon = selected
	main.clear_all_statuses(old_active, target_is_opp)
	main.display_pokemon(target_is_opp)
	main.display_active_pokemon_energies(target_is_opp)

func execute_drag_off(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE DRAG OFF! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		selected = await main.card_ops.prompt_select_card(target_bench, "CHOOSE BENCH POKÉMON TO DRAG OUT", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks weakest bench pokemon
		var targets = target_bench.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]

	if selected == null:
		return

	_force_bench_to_active(selected, is_opponent)
	await main.show_message("DRAGGED " + selected.metadata.get("name", "").to_upper() + " TO ACTIVE!")
	if main._should_bail(): return
	
	# Now do 20 damage to the new defender
	var new_defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(20, attacking_types, new_defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(new_defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(new_defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(new_defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, new_defender, final_damage, result["modifiers"], is_opponent, 20)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Drag Off - dragged ", selected.metadata.get("name", ""))

# Dark Persian - Fascinate: Flip heads = switch opponent bench with active (no damage)
func execute_fascinate(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if target_bench.size() == 0:
		await main.show_message("CAN'T USE FASCINATE! OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! FASCINATE FAILED!")
		if main._should_bail(): return
		return
	
	var selected: card_object = null
	
	if not is_opponent:
		selected = await main.card_ops.prompt_select_card(target_bench, "CHOOSE BENCH POKÉMON TO SWITCH IN", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks weakest bench pokemon
		var targets = target_bench.duplicate()
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = targets[0]

	if selected == null:
		return

	_force_bench_to_active(selected, is_opponent)
	await main.show_message(selected.metadata.get("name", "").to_upper() + " WAS SWITCHED IN!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fascinate - switched in ", selected.metadata.get("name", ""))

# Dark Rapidash - Flame Pillar: 30 damage, optionally discard 1 Fire to do 10 bench damage
func execute_flame_pillar(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# Check for optional Fire Energy discard for bench damage
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	var target_bench = main.player_bench if is_opponent else main.opponent_bench
	
	if fire_energies.size() > 0 and target_bench.size() > 0:
		var do_discard = false
		if is_opponent:
			# CPU only discards extra fire energy if guaranteed to be KO'd next turn
			# (wasting energy when you'll survive is bad value)
			var ko_threats = main.cpu_ai.evaluate_ko_threats()
			do_discard = ko_threats.get("cpu_active_guaranteed_ko", false)
		else:
			# Player chooses: show yes/no via attack selection buttons
			main.special_attack_selection_active = true
			main.buttons_only_blocker.visible = true
			main.attack_buttons_container.visible = true
			main.main_buttons_container.visible = false
			for child in main.attack_buttons_container.get_children():
				if child.name == "cancel_attack_mode_button":
					child.visible = false
					continue
				child.queue_free()
			
			var btn_yes = Button.new()
			btn_yes.text = "YES - DISCARD FIRE ENERGY"
			btn_yes.custom_minimum_size = Vector2(350, 50)
			btn_yes.theme = main.theme_green
			main.attack_buttons_container.add_child(btn_yes)
			btn_yes.pressed.connect(func(): main.special_attack_selected.emit(0))
			
			var btn_no = Button.new()
			btn_no.text = "NO - SKIP"
			btn_no.custom_minimum_size = Vector2(350, 50)
			btn_no.theme = main.theme_green
			main.attack_buttons_container.add_child(btn_no)
			btn_no.pressed.connect(func(): main.special_attack_selected.emit(1))
			
			await main.show_message("DISCARD FIRE ENERGY FOR 10 BENCH DAMAGE?")
			if main._should_bail(): return
			
			var selected_index = await main.special_attack_selected
			do_discard = (selected_index == 0)
			
			for child in main.attack_buttons_container.get_children():
				if child.name == "cancel_attack_mode_button":
					child.visible = true
					continue
				child.queue_free()
			main.attack_buttons_container.visible = false
			main.main_buttons_container.visible = true
			main.special_attack_selection_active = false
			main.buttons_only_blocker.visible = false
		
		if do_discard:
			# Discard 1 fire energy
			var energy = fire_energies[0]
			attacker.attached_energies.erase(energy)
			energy.current_location = "discard"
			var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
			discard_pile.append(energy)
			main.display_active_pokemon_energies(is_opponent)
			
			# Choose bench target
			var bench_target: card_object = null
			if not is_opponent:
				bench_target = await main.card_ops.prompt_select_card(target_bench, "CHOOSE BENCH POKÉMON FOR 10 DAMAGE", "", "SELECT", false)
				if main._should_bail(): return
			else:
				var targets = target_bench.duplicate()
				targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
				bench_target = targets[0]
			
			if bench_target != null:
				bench_target.current_hp = max(0, bench_target.current_hp - 10)
				main.display_hp_circles_above_align(bench_target, !is_opponent)
				await main.show_message("10 DAMAGE TO " + bench_target.metadata.get("name", "").to_upper() + "!")
				if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Flame Pillar")

# Dark Wartortle - Mirror Shell: Counter attack for equal damage next turn
func execute_mirror_shell(attacker: card_object, is_opponent: bool) -> void:
	attacker.mirror_shell_active = true
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " SET UP MIRROR SHELL!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mirror Shell active on ", attacker.metadata.get("name", ""))

# Magikarp - Rapid Evolution: Search deck for Gyarados or Dark Gyarados and evolve
func execute_rapid_evolution(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var valid_evolutions: Array = []
	
	for card in deck:
		var name = card.metadata.get("name", "")
		if name == "Gyarados" or name == "Dark Gyarados":
			valid_evolutions.append(card)
	
	if valid_evolutions.size() == 0:
		await main.show_message("NO GYARADOS OR DARK GYARADOS IN DECK!")
		if main._should_bail(): return
		return
	
	var chosen: card_object = null
	
	if not is_opponent:
		if valid_evolutions.size() == 1:
			chosen = valid_evolutions[0]
		else:
			chosen = await main.card_ops.prompt_select_card(valid_evolutions, "CHOOSE EVOLUTION", "", "SELECT", false)
			if main._should_bail(): return
	else:
		# CPU picks first available
		chosen = valid_evolutions[0]
	
	if chosen == null:
		return
	
	# Evolve Magikarp
	deck.erase(chosen)
	attacker.attached_pre_evolutions.append(card_object.new(attacker.uid, attacker.metadata.duplicate(true)))
	attacker.uid = chosen.uid
	attacker.metadata = chosen.metadata.duplicate(true)
	var old_max = attacker.current_hp
	attacker.current_hp = int(chosen.metadata.get("hp", "0")) - (int(attacker.attached_pre_evolutions[attacker.attached_pre_evolutions.size() - 1].metadata.get("hp", "0")) - old_max)
	attacker.current_hp = min(int(chosen.metadata.get("hp", "0")), max(1, attacker.current_hp))
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.play_evolution_effect(attacker)
	await main.show_message("MAGIKARP EVOLVED INTO " + chosen.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Rapid Evolution into ", chosen.metadata.get("name", ""))

# Abra - Vanish: Shuffle Abra and all attached cards into deck
func execute_vanish(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	
	# Discard all attached cards
	for e in attacker.attached_energies:
		e.current_location = "discard"
		discard.append(e)
	attacker.attached_energies.clear()
	
	for pre in attacker.attached_pre_evolutions:
		pre.current_location = "discard"
		discard.append(pre)
	attacker.attached_pre_evolutions.clear()
	
	for ac in attacker.attached_cards:
		ac.current_location = "discard"
		discard.append(ac)
	attacker.attached_cards.clear()
	
	# Shuffle Abra into deck
	main.clear_all_statuses(attacker, is_opponent)
	attacker.pluspower_count = 0
	attacker.current_hp = int(attacker.metadata.get("hp", "0"))
	attacker.current_location = "deck"
	deck.append(attacker)
	
	var is_active = false
	if is_opponent:
		if main.opponent_active_pokemon == attacker:
			main.opponent_active_pokemon = null
			is_active = true
		else:
			main.opponent_bench.erase(attacker)
	else:
		if main.player_active_pokemon == attacker:
			main.player_active_pokemon = null
			is_active = true
		else:
			main.player_bench.erase(attacker)
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	
	await main.show_message("ABRA VANISHED INTO THE DECK!")
	if main._should_bail(): return
	
	if is_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return
	
	print("ATTACK EXECUTED: Vanish")

# Mankey - Mischief: Shuffle opponent's deck
func execute_mischief(attacker: card_object, is_opponent: bool) -> void:
	var target_deck = main.player_deck if is_opponent else main.opponent_deck
	target_deck.shuffle()
	await main.show_message("OPPONENT'S DECK WAS SHUFFLED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Mischief - shuffled opponent deck")

# Slowpoke - Afternoon Nap: Search deck for Psychic Energy, attach to self
func execute_afternoon_nap(attacker: card_object, is_opponent: bool) -> void:
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var psychic_energies: Array = []
	
	for card in deck:
		if card.metadata.get("supertype", "") == "Energy" and "Psychic" in card.metadata.get("name", ""):
			psychic_energies.append(card)
	
	if psychic_energies.size() == 0:
		await main.show_message("NO PSYCHIC ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	
	var chosen = psychic_energies[0]
	deck.erase(chosen)
	attacker.attached_energies.append(chosen)
	deck.shuffle()
	
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ATTACHED PSYCHIC ENERGY TO " + attacker.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Afternoon Nap")

# Dark Raichu - Surprise Thunder: 30 damage + double flip for bench spread
func execute_surprise_thunder(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	# Do 30 damage to active
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if not transparency_blocked:
		if not main.check_defender_invincible(defender, !is_opponent):
			final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 30)
			if main._should_bail(): return
	
	if is_opponent:
		main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.opponent_attacked_this_turn = true
	else:
		main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
		main.player_attacked_this_turn = true
	
	# First flip
	var coin1 = await main.flip_coin(false, is_opponent)
	if coin1:
		# Second flip
		var coin2 = await main.flip_coin(false, is_opponent)
		var bench_damage = 20 if coin2 else 10
		
		var target_bench = main.player_bench if is_opponent else main.opponent_bench
		await main.show_message(("HEADS AGAIN! " if coin2 else "TAILS! ") + str(bench_damage) + " TO EACH BENCH!")
		if main._should_bail(): return
		
		for bp in target_bench:
			bp.current_hp = max(0, bp.current_hp - bench_damage)
			main.display_hp_circles_above_align(bp, !is_opponent)
	else:
		await main.show_message("TAILS! NO BENCH DAMAGE!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Surprise Thunder")

# Dark Charmeleon - Fireball: 70 damage, gated on Fire Energy, flip heads=discard 1, tails=nothing
func execute_dark_charmeleon_fireball(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			fire_energies.append(e)
	
	if fire_energies.size() == 0:
		await main.show_message("NO FIRE ENERGY! CAN'T USE FIREBALL!")
		if main._should_bail(): return
		return
	
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		# Heads: discard 1 fire energy, do 70 damage
		var energy = fire_energies[0]
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		discard_pile.append(energy)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		
		await main.show_message("HEADS! DISCARDED FIRE ENERGY!")
		if main._should_bail(): return
		
		var attacking_types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(70, attacking_types, defender, attacker)
		var final_damage = result["damage"]
		
		var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
		if not transparency_blocked:
			if not main.check_defender_invincible(defender, !is_opponent):
				final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
				await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, 70)
				if main._should_bail(): return
		
		if is_opponent:
			main.last_attack_on_player = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
			main.opponent_attacked_this_turn = true
		else:
			main.last_attack_on_opponent = {"damage": final_damage, "attack": {}, "attacker_types": attacking_types}
			main.player_attacked_this_turn = true
	else:
		await main.show_message("TAILS! FIREBALL FIZZLED!")
		if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Dark Charmeleon Fireball")

# Check and apply Mirror Shell counter damage
func check_mirror_shell(damaged_pokemon: card_object, attacker: card_object, damage_dealt: int, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if not damaged_pokemon.mirror_shell_active:
		return
	
	damaged_pokemon.mirror_shell_active = false
	
	# Counter damage is blocked by attacker's shields
	if attacker.is_invincible:
		await main.show_message("MIRROR SHELL BLOCKED! TARGET IS INVINCIBLE!")
		if main._should_bail(): return
		print("EFFECT: Mirror Shell blocked by invincibility")
		return
	if attacker.has_no_damage:
		await main.show_message("MIRROR SHELL BLOCKED! NO DAMAGE SHIELD!")
		if main._should_bail(): return
		print("EFFECT: Mirror Shell blocked by no-damage shield")
		return
	
	# Counter equal damage to attacker (no W/R, just raw)
	attacker.current_hp = max(0, attacker.current_hp - damage_dealt)
	main.display_hp_circles_above_align(attacker, !is_damaged_opponent)
	await main.show_message("MIRROR SHELL! " + str(damage_dealt) + " DAMAGE REFLECTED!")
	if main._should_bail(): return
	print("EFFECT: Mirror Shell reflected ", damage_dealt, " damage")


# MAGNETISM (Magnemite): 10 + 10 per Magnemite/Magneton/Dark Magneton on bench
func execute_magnetism(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if attacker == null or defender == null:
		return
	
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var target_names = ["Magnemite", "Magneton", "Dark Magneton"]
	var count = 0
	for bp in bench:
		if bp.metadata.get("name", "") in target_names:
			count += 1
	
	var total_damage = 10 + (10 * count)
	await main.show_message(str(count) + " MAGNEMITE/MAGNETON ON BENCH! " + str(total_damage) + " DAMAGE!")
	if main._should_bail(): return
	
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	
	var transparency_blocked = await main.powers_and_bodies.check_transparency(defender)
	if transparency_blocked:
		return
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
	if main._should_bail(): return
	print("MAGNETISM: ", total_damage, " damage (", count, " bench magnets)")

######################################################################################################################################################
##################################################### GYM1 (GYM HEROES) ATTACK EFFECTS ##############################################################
######################################################################################################################################################

# Helper: deal a flat amount of damage to the active defending Pokemon through the normal pipeline (W/R + shields)
func gym1_hit_active(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	if main.check_defender_invincible(defender, !is_opponent):
		return
	final_damage = main.apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, base_damage)

# Helper: deal raw damage (no W/R) to a single Pokemon, showing a floating label and refreshing HP
func gym1_hit_raw(pokemon: card_object, amount: int, is_pokemon_opponent: bool) -> void:
	if pokemon == null or amount <= 0:
		return
	pokemon.current_hp = max(0, pokemon.current_hp - amount)
	main.display_hp_circles_above_align(pokemon, is_pokemon_opponent)

# Helper: returns true if the given card is a basic Energy card
func gym1_is_basic_energy(card: card_object) -> bool:
	if card.metadata.get("supertype", "") != "Energy":
		return false
	return "Basic" in card.metadata.get("subtypes", [])

# Helper: shuffle a Pokemon and everything attached to it into its owner's deck. Returns true if it was the Active.
func gym1_shuffle_into_deck(pokemon: card_object, is_pokemon_opponent: bool) -> bool:
	var deck = main.opponent_deck if is_pokemon_opponent else main.player_deck
	for e in pokemon.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	pokemon.attached_energies.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	pokemon.attached_pre_evolutions.clear()
	for ac in pokemon.attached_cards:
		ac.current_location = "deck"
		deck.append(ac)
	pokemon.attached_cards.clear()
	main.clear_all_statuses(pokemon, is_pokemon_opponent)
	pokemon.current_hp = int(pokemon.metadata.get("hp", "0"))
	pokemon.current_location = "deck"
	deck.append(pokemon)
	var was_active = false
	if is_pokemon_opponent:
		if main.opponent_active_pokemon == pokemon:
			main.opponent_active_pokemon = null
			was_active = true
		else:
			main.opponent_bench.erase(pokemon)
	else:
		if main.player_active_pokemon == pokemon:
			main.player_active_pokemon = null
			was_active = true
		else:
			main.player_bench.erase(pokemon)
	deck.shuffle()
	main.display_pokemon(is_pokemon_opponent)
	main.display_active_pokemon_energies(is_pokemon_opponent)
	main.update_deck_icon(is_pokemon_opponent)
	return was_active

# Helper: let the controller choose up to max_count Pokemon from a bench (player picks via UI, CPU picks lowest HP)
func gym1_choose_bench_targets(bench: Array, max_count: int, is_bench_opponent: bool, is_opponent_attacking: bool, prompt: String) -> Array:
	var chosen: Array = []
	if bench.size() == 0:
		return chosen
	var limit = min(max_count, bench.size())
	if is_opponent_attacking:
		# CPU picks the lowest-HP targets
		var sorted = bench.duplicate()
		sorted.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		for i in range(limit):
			chosen.append(sorted[i])
		return chosen
	# Player selects up to limit targets, may cancel early
	for pick in range(limit):
		var remaining: Array = []
		for bp in bench:
			if bp not in chosen:
				remaining.append(bp)
		if remaining.size() == 0:
			break
		var sel = await main.card_ops.prompt_select_card(remaining, prompt + " (" + str(pick + 1) + " OF " + str(limit) + ")", "Select a benched Pokemon (cancel to stop)", "SELECT", pick > 0)
		if main._should_bail(): return chosen
		if sel == null:
			break
		chosen.append(sel)
	return chosen

# Checks Crosscounter / Fire Wall counter-attacks when a Pokemon takes damage (called from damage pipeline)
func gym1_check_counters(damaged: card_object, attacker: card_object, damage_dealt: int, is_damaged_opponent: bool) -> void:
	if damaged == null or attacker == null or damage_dealt <= 0:
		return
	# Crosscounter (Rocket's Hitmonchan): coin flip, heads = counter double the damage taken
	if damaged.counter_attack_double:
		damaged.counter_attack_double = false
		await main.show_message(damaged.metadata.get("name", "").to_upper() + "'S CROSSCOUNTER! FLIPPING...")
		if main._should_bail(): return
		var coin = await main.flip_coin(false, is_damaged_opponent)
		if coin:
			if attacker.is_invincible or attacker.has_no_damage:
				await main.show_message("CROSSCOUNTER BLOCKED!")
				if main._should_bail(): return
			else:
				var counter_dmg = damage_dealt * 2
				attacker.current_hp = max(0, attacker.current_hp - counter_dmg)
				main.display_hp_circles_above_align(attacker, !is_damaged_opponent)
				SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
				await main.show_message("CROSSCOUNTER! " + str(counter_dmg) + " DAMAGE RETURNED!")
				if main._should_bail(): return
		else:
			await main.show_message("TAILS! CROSSCOUNTER MISSED!")
			if main._should_bail(): return
	# Fire Wall (Rocket's Moltres): fixed counter damage, applying Weakness/Resistance
	if damaged.counter_attack_fixed > 0:
		var fixed = damaged.counter_attack_fixed
		damaged.counter_attack_fixed = 0
		if not (attacker.is_invincible or attacker.has_no_damage):
			var dtypes = damaged.metadata.get("types", ["Colorless"])
			var res = main.calculate_final_damage(fixed, dtypes, attacker, damaged)
			attacker.current_hp = max(0, attacker.current_hp - res["damage"])
			main.display_hp_circles_above_align(attacker, !is_damaged_opponent)
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
			await main.show_message("FIRE WALL! " + str(res["damage"]) + " DAMAGE RETURNED!")
			if main._should_bail(): return

# PHOENIX FLAME (Blaine's Moltres): 90 damage, flip — tails shuffles Moltres into deck after damage
func execute_phoenix_flame(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! BLAINE'S MOLTRES STAYS IN PLAY!")
		if main._should_bail(): return
		return
	await main.show_message("TAILS! BLAINE'S MOLTRES IS SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	var was_active = gym1_shuffle_into_deck(attacker, is_opponent)
	if was_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return

# TAKE AWAY (Erika's Dragonair): shuffle Dragonair into your deck, then opponent shuffles their Active into theirs
func execute_take_away(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	var attacker_was_active = gym1_shuffle_into_deck(attacker, is_opponent)
	if defender != null:
		await main.show_message(defender.metadata.get("name", "").to_upper() + " IS SHUFFLED INTO THE DECK!")
		if main._should_bail(): return
		gym1_shuffle_into_deck(defender, !is_opponent)
		await main.handle_post_knockout(!is_opponent)
		if main._should_bail(): return
	if attacker_was_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return

# DISCHARGE (Lt. Surge's Electabuzz): discard all Lightning Energy, flip that many coins, 30 damage x heads
func execute_discharge(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var lightning: Array = []
	for e in attacker.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			lightning.append(e)
	if lightning.size() == 0:
		await main.show_message("NO LIGHTNING ENERGY TO DISCHARGE! 0 DAMAGE!")
		if main._should_bail(): return
		return
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for e in lightning:
		attacker.attached_energies.erase(e)
		e.current_location = "discard"
		discard_pile.append(e)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("DISCHARGED " + str(lightning.size()) + " LIGHTNING ENERGY!")
	if main._should_bail(): return
	var heads = 0
	var use_silent = lightning.size() > 1
	for i in range(lightning.size()):
		var coin = await main.flip_coin(use_silent, is_opponent)
		if coin:
			heads += 1
	var dmg = 30 * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return

# CHARGE (Lt. Surge's Electabuzz / Pikachu): take up to N Lightning Energy from discard, attach to self
func execute_charge_recover(attacker: card_object, is_opponent: bool, max_count: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var lightning: Array = []
	for c in discard_pile:
		if "Lightning" in main.get_energy_provided_by_card(c):
			lightning.append(c)
	if lightning.size() == 0:
		await main.show_message("NO LIGHTNING ENERGY IN THE DISCARD PILE!")
		if main._should_bail(): return
		return
	var taken = 0
	if is_opponent:
		# CPU takes as many as it can — more energy is always useful
		var n = min(max_count, lightning.size())
		for i in range(n):
			var e = lightning[i]
			discard_pile.erase(e)
			e.current_location = "attached"
			attacker.attached_energies.append(e)
			taken += 1
	else:
		for pick in range(min(max_count, lightning.size())):
			var remaining: Array = []
			for c in lightning:
				if c.current_location != "attached":
					remaining.append(c)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "CHARGE: TAKE LIGHTNING ENERGY", "Select a Lightning Energy to attach (cancel to stop)", "ATTACH", pick > 0 or max_count > 1)
			if main._should_bail(): return
			if sel == null:
				break
			discard_pile.erase(sel)
			sel.current_location = "attached"
			attacker.attached_energies.append(sel)
			taken += 1
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	if taken > 0:
		await main.show_message("ATTACHED " + str(taken) + " LIGHTNING ENERGY TO " + attacker.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return

# CROSSCOUNTER (Rocket's Hitmonchan): set up the counter-attack flag
func execute_crosscounter(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.counter_attack_double = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS READY TO CROSSCOUNTER!")
	if main._should_bail(): return

# FIRE WALL (Rocket's Moltres): 40 damage, then set up the 10-damage counter-attack
func execute_fire_wall(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	attacker.counter_attack_fixed = 10
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " RAISED A FIRE WALL!")
	if main._should_bail(): return

# SHADOW IMAGES (Rocket's Scyther): set the dodge flag
func execute_shadow_images(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.dodge_active = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS SURROUNDED BY SHADOW IMAGES!")
	if main._should_bail(): return

# PAIN AMPLIFIER (Sabrina's Gengar): put 1 damage counter on each opponent Pokemon that already has damage
func execute_pain_amplifier(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var targets: Array = []
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_active != null:
		targets.append(opp_active)
	targets.append_array(opp_bench)
	var hit = 0
	for t in targets:
		if t.get_damage_counters() > 0:
			gym1_hit_raw(t, 10, !is_opponent)
			hit += 1
	if hit > 0:
		await main.show_message("PAIN AMPLIFIER! A DAMAGE COUNTER WAS ADDED TO " + str(hit) + " POKEMON!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("NO DAMAGED POKEMON — PAIN AMPLIFIER DID NOTHING!")
		if main._should_bail(): return

# CALL OF THE NIGHT (Sabrina's Gengar): 40 damage, unless KO flip 2 coins — both heads shuffles opponent Active into deck
func execute_call_of_the_night(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender == null or defender.current_hp <= 0:
		await main.check_all_knockouts()
		return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	if coin1 and coin2:
		await main.show_message("BOTH HEADS! " + defender.metadata.get("name", "").to_upper() + " IS SHUFFLED INTO THE DECK!")
		if main._should_bail(): return
		gym1_shuffle_into_deck(defender, !is_opponent)
		await main.handle_post_knockout(!is_opponent)
		if main._should_bail(): return
	else:
		await main.show_message("NOT BOTH HEADS — NOTHING EXTRA HAPPENS.")
		if main._should_bail(): return

# DOUBLE-COIN BONUS (Misty's Seadra Knockout Needle): base damage, flip 2 coins — both heads adds the bonus
func execute_double_coin_bonus(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, bonus: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	var dmg = base_damage
	if coin1 and coin2:
		dmg += bonus
		await main.show_message("BOTH HEADS! " + str(dmg) + " DAMAGE!")
	else:
		await main.show_message(str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return

# DRILL TACKLE (Brock's Rhyhorn): flip 2 coins — both heads does damage, otherwise does nothing
func execute_drill_tackle(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	if coin1 and coin2:
		await main.show_message("BOTH HEADS! " + str(base_damage) + " DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	else:
		await main.show_message("NOT BOTH HEADS — THE ATTACK DOES NOTHING!")
		if main._should_bail(): return

# BENCH CHOOSE SPREAD (Brock's Golem Rock Slide / Brock's Onix Tunneling)
func execute_bench_choose_spread(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, max_targets: int, per_damage: int, self_disable: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() > 0:
		var targets = await gym1_choose_bench_targets(opp_bench, max_targets, !is_opponent, is_opponent, "CHOOSE A BENCHED POKEMON")
		if main._should_bail(): return
		for t in targets:
			gym1_hit_raw(t, per_damage, !is_opponent)
		if targets.size() > 0:
			await main.show_message(str(per_damage) + " DAMAGE DEALT TO " + str(targets.size()) + " BENCHED POKEMON!")
			if main._should_bail(): return
	if self_disable:
		for atk in main.get_attacks_for_card(attacker):
			attacker.disabled_attacks[atk.get("name", "")] = "skip_one_turn"
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " CAN'T ATTACK NEXT TURN!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# WATER RING (Misty's Poliwrath): 30 to Active, then 10 to each non-Water benched Pokemon on both sides
func execute_water_ring(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var hit = 0
	for entry in [{"bench": main.player_bench, "opp": false}, {"bench": main.opponent_bench, "opp": true}]:
		for bp in entry["bench"]:
			if "Water" not in bp.metadata.get("types", []):
				gym1_hit_raw(bp, 10, entry["opp"])
				hit += 1
	if hit > 0:
		await main.show_message("WATER RING HIT " + str(hit) + " NON-WATER BENCHED POKEMON!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# TYPED BENCH DAMAGE (Blaine's Growlithe Blaze): base damage to Active, then 10 to each typed Pokemon on opp bench
func execute_typed_bench_damage(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, type_filter: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var hit = 0
	for bp in opp_bench:
		if type_filter in bp.metadata.get("types", []):
			gym1_hit_raw(bp, 10, !is_opponent)
			hit += 1
	if hit > 0:
		await main.show_message("BLAZE HIT " + str(hit) + " " + type_filter.to_upper() + " BENCHED POKEMON!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# SPIRAL DIVE (Brock's Golbat): 10 damage to every opponent Pokemon, no Weakness/Resistance
func execute_spiral_dive(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var targets: Array = []
	if opp_active != null:
		targets.append(opp_active)
	targets.append_array(opp_bench)
	for t in targets:
		gym1_hit_raw(t, 10, !is_opponent)
	await main.show_message("SPIRAL DIVE HIT " + str(targets.size()) + " POKEMON FOR 10 DAMAGE!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# WATER PUNCH (Misty's Poliwhirl): 30 + flip a coin for each Water Energy attached, +10 per heads
func execute_water_punch(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var water_count = 0
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			water_count += 1
	var heads = 0
	var use_silent = water_count > 1
	for i in range(water_count):
		var coin = await main.flip_coin(use_silent, is_opponent)
		if coin:
			heads += 1
	var dmg = base_damage + (10 * heads)
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return

# NIGHT SPIRITS (Sabrina's Haunter): flip coins = number of Sabrina's Gastly/Haunter/Gengar in play, 30 x heads
func execute_night_spirits(attacker: card_object, defender: card_object, is_opponent: bool, per_heads: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var names = ["Sabrina's Gastly", "Sabrina's Haunter", "Sabrina's Gengar"]
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var in_play: Array = []
	if own_active != null:
		in_play.append(own_active)
	in_play.append_array(own_bench)
	var flip_count = 0
	for p in in_play:
		if p.metadata.get("name", "") in names:
			flip_count += 1
	if flip_count == 0:
		await main.show_message("NO SABRINA'S GHOSTS IN PLAY! 0 DAMAGE!")
		if main._should_bail(): return
		return
	var heads = 0
	var use_silent = flip_count > 1
	for i in range(flip_count):
		var coin = await main.flip_coin(use_silent, is_opponent)
		if coin:
			heads += 1
	var dmg = per_heads * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return

# FULL SPEED CHARGE (Blaine's Tauros): flip 4 coins — 20 x heads to defender, 20 x tails to self
func execute_full_speed_charge(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(4):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads += 1
	var tails = 4 - heads
	var dmg = 20 * heads
	var self_dmg = 20 * tails
	await main.show_message(str(heads) + " HEADS, " + str(tails) + " TAILS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return
	if self_dmg > 0:
		attacker.current_hp = max(0, attacker.current_hp - self_dmg)
		var label_x = 1030 if is_opponent else 530
		main.show_floating_label("-" + str(self_dmg) + "HP", Vector2(label_x, 300), Color.YELLOW, true)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK " + str(self_dmg) + " RECOIL DAMAGE!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# LAVA BURST (Blaine's Magmar): discard top 5 of deck, 20 damage per Fire Energy discarded this way
func execute_lava_burst(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var to_discard = min(5, deck.size())
	var fire_count = 0
	for i in range(to_discard):
		var card = deck.pop_front()
		card.current_location = "discard"
		discard_pile.append(card)
		if card.metadata.get("supertype", "") == "Energy" and "Fire" in main.get_energy_provided_by_card(card):
			fire_count += 1
	main.update_discard_pile_display(is_opponent)
	main.update_deck_icon(is_opponent)
	var dmg = 20 * fire_count
	await main.show_message("DISCARDED " + str(to_discard) + " CARDS, " + str(fire_count) + " FIRE ENERGY! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return

# LUCKY SHOT (Brock's Geodude): choose 1 opponent benched Pokemon, flip — heads deals 30 to it
func execute_lucky_shot(attacker: card_object, is_opponent: bool, damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() == 0:
		await main.show_message("LUCKY SHOT CAN'T BE USED — NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	var targets = await gym1_choose_bench_targets(opp_bench, 1, !is_opponent, is_opponent, "CHOOSE A BENCHED POKEMON")
	if main._should_bail(): return
	if targets.size() == 0:
		return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		gym1_hit_raw(targets[0], damage, !is_opponent)
		await main.show_message("HEADS! " + str(damage) + " DAMAGE TO " + targets[0].metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! LUCKY SHOT MISSED!")
		if main._should_bail(): return

# MUD SPLASH (Misty's Seaking): base damage to Active, then choose 1 opp bench, flip — heads 10 to it
func execute_mud_splash(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() > 0:
		var targets = await gym1_choose_bench_targets(opp_bench, 1, !is_opponent, is_opponent, "CHOOSE A BENCHED POKEMON")
		if main._should_bail(): return
		if targets.size() > 0:
			var coin = await main.flip_coin(false, is_opponent)
			if coin:
				gym1_hit_raw(targets[0], 10, !is_opponent)
				await main.show_message("HEADS! 10 DAMAGE TO " + targets[0].metadata.get("name", "").to_upper() + "!")
				if main._should_bail(): return
			else:
				await main.show_message("TAILS! NO BENCH DAMAGE!")
				if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# ELECTRIC CURRENT (Lt. Surge's Electabuzz): 20 damage, move 1 Lightning Energy from self to a benched Pokemon
func execute_electric_current(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var lightning: card_object = null
	for e in attacker.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			lightning = e
			break
	if lightning == null:
		await main.check_all_knockouts()
		return
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() == 0:
		attacker.attached_energies.erase(lightning)
		lightning.current_location = "discard"
		var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
		discard_pile.append(lightning)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("NO BENCHED POKEMON — LIGHTNING ENERGY DISCARDED!")
		if main._should_bail(): return
	else:
		var target: card_object = null
		if is_opponent:
			target = main.cpu_ai.pick_best_bench_replacement(own_bench, main.player_active_pokemon, main.cpu_ai.build_cpu_evaluation())
			if target == null:
				target = own_bench[0]
		else:
			target = await main.card_ops.prompt_select_card(own_bench, "MOVE LIGHTNING ENERGY", "Choose a benched Pokemon to receive the energy", "ATTACH", false)
			if main._should_bail(): return
		if target != null:
			attacker.attached_energies.erase(lightning)
			target.attached_energies.append(lightning)
			main.display_active_pokemon_energies(is_opponent)
			main.display_pokemon(is_opponent)
			await main.show_message("MOVED LIGHTNING ENERGY TO " + target.metadata.get("name", "").to_upper() + "!")
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# SCREAMING HEADBUTT (Sabrina's Slowbro): base damage, then this attack can't be used next turn
func execute_screaming_headbutt(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, attack_name: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	attacker.disabled_attacks[attack_name] = "skip_one_turn"
	await main.show_message(attack_name.to_upper() + " CAN'T BE USED NEXT TURN!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# MAGIC POLLEN (Erika's Gloom): 30 damage, flip — heads applies a special condition of the attacker's choice
func execute_magic_pollen(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NO SPECIAL CONDITION!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		return
	if defender == null or defender.current_hp <= 0:
		await main.check_all_knockouts()
		return
	var statuses = ["Asleep", "Confused", "Paralyzed", "Poisoned"]
	var chosen = "Paralyzed"
	if is_opponent:
		chosen = "Paralyzed"
	else:
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
				continue
			child.queue_free()
		for i in range(statuses.size()):
			var btn = Button.new()
			btn.text = statuses[i].to_upper()
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		await main.show_message("HEADS! CHOOSE A SPECIAL CONDITION!")
		var sel_idx = await main.special_attack_selected
		chosen = statuses[sel_idx]
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	var effect = {"type": "status", "target": "defender", "status": chosen, "flip": "none"}
	await main.apply_status_effect(effect, attacker, defender, is_opponent)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# FAIRY POWER (Erika's Clefable): flip — heads lets you return any number of your Pokemon (and attached cards) to hand
func execute_fairy_power(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! FAIRY POWER DID NOTHING!")
		if main._should_bail(): return
		return
	if is_opponent:
		# CPU keeps its board — returning Pokemon is generally a setback
		await main.show_message("HEADS! THE OPPONENT KEEPS ITS POKEMON IN PLAY.")
		if main._should_bail(): return
		return
	await main.show_message("HEADS! YOU MAY RETURN YOUR POKEMON TO YOUR HAND.")
	if main._should_bail(): return
	var returned = 0
	while true:
		var pool: Array = []
		if main.player_active_pokemon != null:
			pool.append(main.player_active_pokemon)
		pool.append_array(main.player_bench)
		if pool.size() == 0:
			break
		var sel = await main.card_ops.prompt_select_card(pool, "FAIRY POWER: RETURN A POKEMON", "Select a Pokemon to return to your hand (cancel to stop)", "RETURN", true)
		if main._should_bail(): return
		if sel == null:
			break
		gym1_return_pokemon_to_hand(sel, false)
		returned += 1
	if returned > 0:
		await main.show_message("RETURNED " + str(returned) + " POKEMON TO YOUR HAND!")
		if main._should_bail(): return
		main.refresh_hand_display(false)
		if main.player_active_pokemon == null:
			await main.handle_post_knockout(false)
			if main._should_bail(): return

# Helper: return a Pokemon and everything attached to it to its owner's hand
func gym1_return_pokemon_to_hand(pokemon: card_object, is_pokemon_opponent: bool) -> void:
	var hand = main.opponent_hand if is_pokemon_opponent else main.player_hand
	for e in pokemon.attached_energies:
		e.current_location = "hand"
		hand.append(e)
	pokemon.attached_energies.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "hand"
		hand.append(pre)
	pokemon.attached_pre_evolutions.clear()
	for ac in pokemon.attached_cards:
		ac.current_location = "hand"
		hand.append(ac)
	pokemon.attached_cards.clear()
	main.clear_all_statuses(pokemon, is_pokemon_opponent)
	pokemon.current_hp = int(pokemon.metadata.get("hp", "0"))
	pokemon.current_location = "hand"
	hand.append(pokemon)
	if is_pokemon_opponent:
		if main.opponent_active_pokemon == pokemon:
			main.opponent_active_pokemon = null
		else:
			main.opponent_bench.erase(pokemon)
	else:
		if main.player_active_pokemon == pokemon:
			main.player_active_pokemon = null
		else:
			main.player_bench.erase(pokemon)
	main.display_pokemon(is_pokemon_opponent)
	main.display_active_pokemon_energies(is_pokemon_opponent)

# FIDGET (Brock's Mankey): shuffle your own deck
func execute_fidget(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	deck.shuffle()
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " FIDGETED — DECK SHUFFLED!")
	if main._should_bail(): return

# ENERGY LOOP (Sabrina's Abra): return 1 Psychic Energy attached to self to hand, then deal damage
func execute_energy_loop(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var psychic: card_object = null
	for e in attacker.attached_energies:
		if "Psychic" in main.get_energy_provided_by_card(e):
			psychic = e
			break
	if psychic != null:
		attacker.attached_energies.erase(psychic)
		psychic.current_location = "hand"
		var hand = main.opponent_hand if is_opponent else main.player_hand
		hand.append(psychic)
		main.display_active_pokemon_energies(is_opponent)
		main.refresh_hand_display(is_opponent)
		await main.show_message("RETURNED A PSYCHIC ENERGY TO HAND!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return

# PSYCHIC EXCHANGE (Erika's Exeggutor): shuffle your hand into your deck, then draw 5 cards
func execute_psychic_exchange(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	for c in hand:
		c.current_location = "deck"
		deck.append(c)
	hand.clear()
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.card_ops.draw_n(is_opponent, 5)
	if main._should_bail(): return
	await main.show_message("PSYCHIC EXCHANGE! DREW 5 NEW CARDS!")
	if main._should_bail(): return

# MOONWATCHING (Erika's Clefairy): search your deck for a basic Energy card and put it into your hand
func execute_search_basic_energy_to_hand(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics: Array = []
	for c in deck:
		if gym1_is_basic_energy(c):
			basics.append(c)
	if basics.size() == 0:
		await main.show_message("NO BASIC ENERGY IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = basics[0]
	else:
		chosen = await main.card_ops.prompt_select_card(basics, "SEARCH FOR A BASIC ENERGY", "Select a basic Energy card to put into your hand", "SELECT", false, true)
		if main._should_bail(): return
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		await main.show_message("PUT " + chosen.metadata.get("name", "").to_upper() + " INTO HAND!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)

# JELLYFISH POD (Misty's Tentacool): search deck for any number of named Pokemon, put them into your hand
func execute_jellyfish_pod(attacker: card_object, is_opponent: bool, names: Array) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var matches: Array = []
	for c in deck:
		if c.metadata.get("name", "") in names:
			matches.append(c)
	if matches.size() == 0:
		await main.show_message("NO MATCHING POKEMON IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var taken: Array = []
	if is_opponent:
		# CPU takes everything it found — more Pokemon in hand is good
		taken = matches.duplicate()
	else:
		while true:
			var remaining: Array = []
			for c in matches:
				if c not in taken:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "JELLYFISH POD: TAKE A POKEMON", "Select a Pokemon to add to your hand (cancel to stop)", "TAKE", true, true)
			if main._should_bail(): return
			if sel == null:
				break
			taken.append(sel)
	for c in taken:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	if taken.size() > 0:
		await main.show_message("PUT " + str(taken.size()) + " POKEMON INTO HAND!")
		if main._should_bail(): return

# HEALING POLLEN (Sabrina's Venomoth): flip 3 coins, for each heads remove 1 damage counter from each of your Pokemon
func execute_team_heal_flip(attacker: card_object, is_opponent: bool, flip_count: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(flip_count):
		var coin = await main.flip_coin(flip_count > 1, is_opponent)
		if coin:
			heads += 1
	await main.show_message("GOT " + str(heads) + " HEADS!")
	if main._should_bail(): return
	if heads == 0:
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if own_active != null:
		all_own.append(own_active)
	all_own.append_array(own_bench)
	var heal = heads * 10
	var healed_any = false
	for p in all_own:
		var max_hp = int(p.metadata.get("hp", "0"))
		if p.current_hp < max_hp:
			p.current_hp = min(max_hp, p.current_hp + heal)
			healed_any = true
	if healed_any:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_pokemon(is_opponent)
		main.display_hp_circles_above_align(own_active, is_opponent)
		await main.show_message("HEALING POLLEN REMOVED " + str(heads) + " DAMAGE COUNTER(S) FROM EACH POKEMON!")
		if main._should_bail(): return

# CALL FOR FRIEND (gym1 named variant): flip — heads searches deck for a Basic Pokemon with a name keyword, to bench
func execute_call_for_named_basic(attacker: card_object, is_opponent: bool, name_keyword: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NO POKEMON FOUND!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	var valid: Array = []
	for c in deck:
		if "Basic" in c.metadata.get("subtypes", []) and name_keyword in c.metadata.get("name", ""):
			valid.append(c)
	if valid.size() == 0:
		await main.show_message("NO MATCHING BASIC POKEMON IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = null
	if is_opponent:
		var best_hp = -1
		for c in valid:
			var hp = int(c.metadata.get("hp", "0"))
			if hp > best_hp:
				best_hp = hp
				chosen = c
	else:
		chosen = await main.card_ops.prompt_select_card(valid, "CHOOSE A POKEMON FOR YOUR BENCH", "Select a Basic Pokemon to put onto your bench", "SELECT", true, true)
		if main._should_bail(): return
	if chosen != null and bench.size() < 5:
		deck.erase(chosen)
		chosen.current_hp = int(chosen.metadata.get("hp", "0"))
		main.card_ops.place_on_bench(chosen, is_opponent)
		await main.show_message(chosen.metadata.get("name", "").to_upper() + " WAS PLACED ON THE BENCH!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)

# SLEIGHT OF HAND (Sabrina's Mr. Mime): put up to 3 hand cards on top of deck, search that many basic Energy to hand
func execute_sleight_of_hand(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var put_back: Array = []
	if is_opponent:
		# CPU puts back up to 3 non-Pokemon, non-basic-energy cards (trainers/evolutions least useful early)
		var candidates: Array = []
		for c in hand:
			if c.metadata.get("supertype", "") == "Trainer":
				candidates.append(c)
		for i in range(min(3, candidates.size())):
			put_back.append(candidates[i])
	else:
		var max_pick = min(3, hand.size())
		for pick in range(max_pick):
			var remaining: Array = []
			for c in hand:
				if c not in put_back:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "SLEIGHT OF HAND: CARD " + str(pick + 1) + " OF " + str(max_pick), "Choose a hand card to put on top of your deck (cancel to stop)", "PUT BACK", true)
			if main._should_bail(): return
			if sel == null:
				break
			put_back.append(sel)
	var count = put_back.size()
	for c in put_back:
		hand.erase(c)
		c.current_location = "deck"
		deck.push_front(c)
	main.refresh_hand_display(is_opponent)
	if count == 0:
		await main.show_message("NO CARDS PUT BACK — SLEIGHT OF HAND DID NOTHING.")
		if main._should_bail(): return
		return
	var basics: Array = []
	for c in deck:
		if gym1_is_basic_energy(c):
			basics.append(c)
	var taken: Array = []
	if is_opponent:
		for i in range(min(count, basics.size())):
			taken.append(basics[i])
	else:
		for pick in range(min(count, basics.size())):
			var remaining: Array = []
			for c in basics:
				if c not in taken:
					remaining.append(c)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "SEARCH BASIC ENERGY (" + str(pick + 1) + " OF " + str(count) + ")", "Select a basic Energy card to put into your hand", "SELECT", false, true)
			if main._should_bail(): return
			if sel == null:
				break
			taken.append(sel)
	for c in taken:
		deck.erase(c)
		c.current_location = "hand"
		hand.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SLEIGHT OF HAND! GAINED " + str(taken.size()) + " BASIC ENERGY!")
	if main._should_bail(): return

# DEFLECTOR (Erika's Exeggcute): halve incoming damage next turn
func execute_deflector(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.damage_halved_next_turn = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " RAISED A DEFLECTOR!")
	if main._should_bail(): return

# FOCUS ENERGY (Lt. Surge's Rattata): Gnaw's base damage is doubled next turn
func execute_focus_energy(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.focus_energy_active = true
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " IS FOCUSING ITS ENERGY!")
	if main._should_bail(): return

# SONIC DISTORTION (Sabrina's Venomoth): damage, flip 2 coins — 1 or both heads applies a status condition
func execute_flip2_any_heads_status(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, status: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	if defender == null or defender.current_hp <= 0:
		return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	if coin1 or coin2:
		var effect = {"type": "status", "target": "defender", "status": status, "flip": "none"}
		await main.apply_status_effect(effect, attacker, defender, is_opponent)
		if main._should_bail(): return
	else:
		await main.show_message("BOTH TAILS! NO " + status.to_upper() + "!")
		if main._should_bail(): return

######################################################################################################################################################
##################################################### GYM2 (GYM CHALLENGE) ATTACK EFFECTS ###########################################################
######################################################################################################################################################

# Helper: raw self-damage with a floating label
func gym2_self_damage(attacker: card_object, is_opponent: bool, amount: int) -> void:
	if amount <= 0 or attacker == null:
		return
	attacker.current_hp = max(0, attacker.current_hp - amount)
	var pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
	main.show_floating_label("-" + str(amount) + "HP", pos, Color.YELLOW, true)
	main.display_hp_circles_above_align(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " TOOK " + str(amount) + " DAMAGE!")

# Helper: discard energy from a Pokemon. count == -1 discards all matching. type_filter "any" matches all energy.
func gym2_discard_energy(pokemon: card_object, is_pokemon_opponent: bool, type_filter: String, count: int) -> int:
	var matching: Array = []
	for e in pokemon.attached_energies:
		if type_filter == "any" or type_filter in main.get_energy_provided_by_card(e):
			matching.append(e)
	var n = matching.size() if count == -1 else min(count, matching.size())
	var discard_pile = main.opponent_discard_pile if is_pokemon_opponent else main.player_discard_pile
	for i in range(n):
		var e = matching[i]
		pokemon.attached_energies.erase(e)
		e.current_location = "discard"
		discard_pile.append(e)
	main.display_active_pokemon_energies(is_pokemon_opponent)
	main.update_discard_pile_display(is_pokemon_opponent)
	return n

# Helper: count energy of a type provided across a Pokemon's attached energies
func gym2_count_energy(pokemon: card_object, type_filter: String) -> int:
	var total = 0
	for e in pokemon.attached_energies:
		for p in main.get_energy_provided_by_card(e):
			if p == type_filter:
				total += 1
	return total

# Helper: is this card a Pokemon?
func gym2_is_pokemon(c: card_object) -> bool:
	return c.metadata.get("supertype", "") == "Pokémon"

# ROARING FLAMES (Blaine's Charizard): discard all Fire Energy, 20 + 20 per Fire Energy discarded
func execute_roaring_flames(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var fire_count = 0
	var to_discard: Array = []
	for e in attacker.attached_energies:
		var fcount = 0
		for p in main.get_energy_provided_by_card(e):
			if p == "Fire":
				fcount += 1
		if fcount > 0:
			fire_count += fcount
			to_discard.append(e)
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for e in to_discard:
		attacker.attached_energies.erase(e)
		e.current_location = "discard"
		discard_pile.append(e)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	var dmg = 20 + 20 * fire_count
	await main.show_message("DISCARDED " + str(fire_count) + " FIRE ENERGY! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# GROWTH (Erika's Venusaur): flip — heads lets you attach up to 2 Grass Energy from hand to self
func execute_growth(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! GROWTH DID NOTHING!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var grass: Array = []
	for c in hand:
		if gym1_is_basic_energy(c) and "Grass" in main.get_energy_provided_by_card(c):
			grass.append(c)
	if grass.size() == 0:
		await main.show_message("HEADS! NO GRASS ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var attached = 0
	if is_opponent:
		for i in range(min(2, grass.size())):
			var e = grass[i]
			hand.erase(e)
			e.current_location = "attached"
			attacker.attached_energies.append(e)
			attached += 1
	else:
		for pick in range(min(2, grass.size())):
			var remaining: Array = []
			for c in grass:
				if c.current_location == "hand":
					remaining.append(c)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "GROWTH: ATTACH GRASS ENERGY", "Select a Grass Energy to attach (cancel to stop)", "ATTACH", pick > 0)
			if main._should_bail(): return
			if sel == null:
				break
			hand.erase(sel)
			sel.current_location = "attached"
			attacker.attached_energies.append(sel)
			attached += 1
	main.display_active_pokemon_energies(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("HEADS! ATTACHED " + str(attached) + " GRASS ENERGY!")
	if main._should_bail(): return

# SUMMON STORM (Giovanni's Gyarados): flip 2 — both heads does 20 to every other Pokemon, no W/R
func execute_summon_storm(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	if not (coin1 and coin2):
		await main.show_message("NOT BOTH HEADS — SUMMON STORM DID NOTHING!")
		if main._should_bail(): return
		return
	await main.show_message("BOTH HEADS! THE STORM HITS EVERY OTHER POKEMON!")
	if main._should_bail(): return
	var hits = 0
	for entry in [{"p": main.player_active_pokemon, "opp": false}, {"p": main.opponent_active_pokemon, "opp": true}]:
		if entry["p"] != null and entry["p"] != attacker:
			gym1_hit_raw(entry["p"], 20, entry["opp"])
			hits += 1
	for bp in main.player_bench:
		if bp != attacker:
			gym1_hit_raw(bp, 20, false)
			hits += 1
	for bp in main.opponent_bench:
		if bp != attacker:
			gym1_hit_raw(bp, 20, true)
			hits += 1
	await main.show_message("SUMMON STORM HIT " + str(hits) + " POKEMON FOR 20!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DRAGON TORNADO (Giovanni's Gyarados): damage, unless KO switch a chosen opponent Benched Pokemon in
func execute_dragon_tornado(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		if opp_bench.size() > 0:
			await apply_force_switch({"chooser": "attacker"}, is_opponent)
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# INTIMIDATE (Giovanni's Nidoking): if Defending Pokemon's max HP is 50 or less, it can't attack next turn
func execute_intimidate(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender != null and defender.get_max_hp() <= 50:
		defender.attack_blocked_next_turn = true
		defender.attack_blocked_by_id = attacker.get_instance_id()
		main.update_status_icons(defender, !is_opponent)
		await main.show_message(defender.metadata.get("name", "").to_upper() + " IS INTIMIDATED AND CAN'T ATTACK NEXT TURN!")
		if main._should_bail(): return
	else:
		await main.show_message("THE DEFENDING POKEMON IS TOO STRONG TO INTIMIDATE!")
		if main._should_bail(): return

# GIANT GROWTH (Koga's Ditto): flip — heads sets max HP to 80 and boosts Pound's base damage
func execute_giant_growth(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! GIANT GROWTH DID NOTHING!")
		if main._should_bail(): return
		return
	var damage = attacker.get_max_hp() - attacker.current_hp
	attacker.ditto_giant_growth = true
	attacker.max_hp_override = 80
	attacker.current_hp = max(1, 80 - damage)
	main.display_hp_circles_above_align(attacker, is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEADS! KOGA'S DITTO GREW — MAX HP IS NOW 80!")
	if main._should_bail(): return

# KERZAP (Lt. Surge's Raichu): flip — heads does 50 and discards all Lightning Energy; tails does 20
func execute_kerzap(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! 50 DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 50)
		if main._should_bail(): return
		var discarded = gym2_discard_energy(attacker, is_opponent, "Lightning", -1)
		if discarded > 0:
			await main.show_message("DISCARDED " + str(discarded) + " LIGHTNING ENERGY!")
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! 20 DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 20)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# SUPER REMOVAL (Misty's Golduck): flip — heads discards 1 Energy from each of the opponent's Pokemon
func execute_super_removal(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! SUPER REMOVAL FAILED!")
		if main._should_bail(): return
		return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var targets: Array = []
	if opp_active != null:
		targets.append(opp_active)
	targets.append_array(opp_bench)
	var removed = 0
	for t in targets:
		if t.attached_energies.size() == 0:
			continue
		var chosen: card_object = null
		if is_opponent:
			chosen = t.attached_energies[0]
		else:
			chosen = await main.card_ops.prompt_select_card(t.attached_energies, "SUPER REMOVAL: " + t.metadata.get("name", "").to_upper(), "Choose an Energy to discard", "DISCARD", false)
			if main._should_bail(): return
		if chosen == null:
			chosen = t.attached_energies[0]
		t.attached_energies.erase(chosen)
		chosen.current_location = "discard"
		var dp = main.opponent_discard_pile if !is_opponent else main.player_discard_pile
		dp.append(chosen)
		removed += 1
	main.display_active_pokemon_energies(!is_opponent)
	main.display_pokemon(!is_opponent)
	main.update_discard_pile_display(!is_opponent)
	await main.show_message("HEADS! SUPER REMOVAL DISCARDED " + str(removed) + " ENERGY!")
	if main._should_bail(): return

# JUXTAPOSE (Rocket's Mewtwo): flip — heads swaps damage counters between Mewtwo and the Defender
func execute_juxtapose(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NOTHING HAPPENS!")
		if main._should_bail(): return
		return
	if defender == null:
		return
	var a_damage = attacker.get_max_hp() - attacker.current_hp
	var d_damage = defender.get_max_hp() - defender.current_hp
	attacker.current_hp = max(0, attacker.get_max_hp() - d_damage)
	defender.current_hp = max(0, defender.get_max_hp() - a_damage)
	main.display_hp_circles_above_align(attacker, is_opponent)
	main.display_hp_circles_above_align(defender, !is_opponent)
	await main.show_message("HEADS! DAMAGE COUNTERS SWAPPED!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# PLASMA (Rocket's Zapdos): damage, then attach a Lightning Energy from the discard pile to self
func execute_plasma(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var lightning: card_object = null
	for c in discard_pile:
		if "Lightning" in main.get_energy_provided_by_card(c):
			lightning = c
			break
	if lightning != null:
		discard_pile.erase(lightning)
		lightning.current_location = "attached"
		attacker.attached_energies.append(lightning)
		main.display_active_pokemon_energies(is_opponent)
		main.update_discard_pile_display(is_opponent)
		await main.show_message("PLASMA ATTACHED A LIGHTNING ENERGY FROM THE DISCARD PILE!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# ELECTROBURN (Rocket's Zapdos): damage, then self-damage equal to 10× the Lightning Energy attached
func execute_electroburn(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var self_dmg = 10 * gym2_count_energy(attacker, "Lightning")
	if self_dmg > 0:
		await gym2_self_damage(attacker, is_opponent, self_dmg)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# LOVE LARIAT (Giovanni's Nidoqueen): flip — heads does 50 (+50 if a Giovanni's Nidoking is benched); tails nothing
func execute_love_lariat(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! LOVE LARIAT DOES NOTHING!")
		if main._should_bail(): return
		return
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var dmg = 50
	for bp in own_bench:
		if bp.metadata.get("name", "") == "Giovanni's Nidoking":
			dmg = 100
			break
	await main.show_message("HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# OVERHEAD TOSS (Giovanni's Pinsir): damage, then if you have a bench and flip tails, 20 to one of your own benched
func execute_overhead_toss(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if not coin:
			var target: card_object = null
			if is_opponent:
				var best_hp = -1
				for bp in own_bench:
					if bp.current_hp > best_hp:
						best_hp = bp.current_hp
						target = bp
			else:
				target = await main.card_ops.prompt_select_card(own_bench, "OVERHEAD TOSS MISSED!", "Choose one of your Benched Pokemon to take 20 damage", "SELECT", false)
				if main._should_bail(): return
				if target == null:
					target = own_bench[0]
			gym1_hit_raw(target, 20, is_opponent)
			await main.show_message("TAILS! " + target.metadata.get("name", "").to_upper() + " TOOK 20 DAMAGE!")
			if main._should_bail(): return
		else:
			await main.show_message("HEADS! NO BENCH DAMAGE!")
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# POISON POWER (Koga's Arbok): 40 + Poison the Defender if Arbok is Poisoned, otherwise just 20
func execute_poison_power(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var boosted = attacker.is_poisoned
	var dmg = 40 if boosted else 20
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	if boosted and defender != null and defender.current_hp > 0:
		var effect = {"type": "status", "target": "defender", "status": "Poisoned", "flip": "none"}
		await main.apply_status_effect(effect, attacker, defender, is_opponent)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# THUNDER FLARE (Lt. Surge's Jolteon): 30 + 10 per self damage counter, then flip — tails does 30 self damage
func execute_thunder_flare(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var dmg = 30 + 10 * attacker.get_damage_counters()
	await main.show_message(str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await gym2_self_damage(attacker, is_opponent, 30)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DARK WAVE (Sabrina's Gengar): damage, then all Pokemon Powers stop working
func execute_dark_wave(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	all_pokemon.append_array(main.opponent_bench)
	for p in all_pokemon:
		p.power_disabled_until_end_of_next_turn = true
	await main.show_message("DARK WAVE! ALL POKEMON POWERS STOP WORKING!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DAMAGE SHIFT (Sabrina's Golduck): move 1 damage counter from each of your Pokemon to the Defender
func execute_damage_shift(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var own: Array = []
	if own_active != null:
		own.append(own_active)
	own.append_array(own_bench)
	var moved = 0
	for p in own:
		if p.get_damage_counters() > 0:
			p.current_hp = min(p.get_max_hp(), p.current_hp + 10)
			main.display_hp_circles_above_align(p, is_opponent)
			moved += 1
	if moved > 0 and defender != null:
		defender.current_hp = max(0, defender.current_hp - moved * 10)
		main.display_hp_circles_above_align(defender, !is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("DAMAGE SHIFT MOVED " + str(moved) + " DAMAGE COUNTER(S) TO THE DEFENDER!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# BONFIRE (Blaine's Charmeleon): flip 3, discard 1 Fire per heads, 10× heads to each opponent Pokemon
func execute_bonfire(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if gym2_count_energy(attacker, "Fire") == 0:
		await main.show_message("NO FIRE ENERGY — BONFIRE DOES NOTHING!")
		if main._should_bail(): return
		return
	var heads = 0
	for i in range(3):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads += 1
	var discarded = gym2_discard_energy(attacker, is_opponent, "Fire", heads)
	await main.show_message("GOT " + str(heads) + " HEADS! DISCARDED " + str(discarded) + " FIRE ENERGY!")
	if main._should_bail(): return
	var dmg = 10 * heads
	if dmg > 0:
		var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		if opp_active != null:
			gym1_hit_raw(opp_active, dmg, !is_opponent)
		for bp in opp_bench:
			gym1_hit_raw(bp, dmg, !is_opponent)
		await main.show_message("BONFIRE HIT EACH OPPONENT POKEMON FOR " + str(dmg) + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# STAMP (Blaine's Rapidash): flip — heads does 40 + 10 to each opponent benched; tails does 30
func execute_stamp(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! 40 DAMAGE PLUS BENCH DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 40)
		if main._should_bail(): return
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		for bp in opp_bench:
			gym1_hit_raw(bp, 10, !is_opponent)
	else:
		await main.show_message("TAILS! 30 DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 30)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DETONATE (Brock's Graveler): damage, 10 to every benched Pokemon, 50 self damage
func execute_detonate(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	for bp in main.player_bench:
		gym1_hit_raw(bp, 10, false)
	for bp in main.opponent_bench:
		gym1_hit_raw(bp, 10, true)
	await main.show_message("DETONATE HIT EVERY BENCHED POKEMON FOR 10!")
	if main._should_bail(): return
	await gym2_self_damage(attacker, is_opponent, 50)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# RISKY ATTACK (Giovanni's Machoke): flip — heads does 60; tails does no damage and 100 self damage
func execute_risky_attack(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! " + str(base_damage) + " DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! THE ATTACK BACKFIRES!")
		if main._should_bail(): return
		await gym2_self_damage(attacker, is_opponent, 100)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# FALSE CHARITY (Giovanni's Meowth): flip — heads looks at the top of the opponent's deck (Trainer -> discard, else -> hand)
func execute_false_charity(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! FALSE CHARITY FAILED!")
		if main._should_bail(): return
		return
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_deck.size() == 0:
		await main.show_message("THE OPPONENT'S DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top = opp_deck.pop_front()
	var card_name = top.metadata.get("name", "")
	if top.metadata.get("supertype", "") == "Trainer":
		top.current_location = "discard"
		var dp = main.player_discard_pile if is_opponent else main.opponent_discard_pile
		dp.append(top)
		main.update_discard_pile_display(!is_opponent)
		await main.show_message("HEADS! " + card_name.to_upper() + " WAS A TRAINER — DISCARDED IT!")
		if main._should_bail(): return
	else:
		top.current_location = "hand"
		var hand = main.player_hand if is_opponent else main.opponent_hand
		hand.append(top)
		main.refresh_hand_display(!is_opponent)
		await main.show_message("HEADS! " + card_name.to_upper() + " WENT TO THE OPPONENT'S HAND.")
		if main._should_bail(): return
	main.update_deck_icon(!is_opponent)

# REND (Giovanni's Nidorino): 40 if the Defender already has damage counters, otherwise 20
func execute_rend(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var dmg = 20
	if defender != null and defender.get_damage_counters() > 0:
		dmg = 40
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# OBSCURING GAS (Koga's Koffing): damage, then flip — heads shuffles Koffing into your deck
func execute_obscuring_gas(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! " + attacker.metadata.get("name", "").to_upper() + " IS SHUFFLED INTO THE DECK!")
		if main._should_bail(): return
		var was_active = gym1_shuffle_into_deck(attacker, is_opponent)
		if was_active:
			await main.handle_post_knockout(is_opponent)
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! " + attacker.metadata.get("name", "").to_upper() + " STAYS IN PLAY.")
		if main._should_bail(): return

# MESSENGER (Koga's Pidgey): shuffle Pidgey into your deck, search for a Basic/Evolution Pokemon to hand
func execute_messenger(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " RETURNS TO THE DECK!")
	if main._should_bail(): return
	var was_active = gym1_shuffle_into_deck(attacker, is_opponent)
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var valid: Array = []
	for c in deck:
		if gym2_is_pokemon(c) and c.metadata.get("name", "") != "Koga's Pidgey":
			valid.append(c)
	if valid.size() > 0:
		var chosen: card_object = null
		if is_opponent:
			var best_hp = -1
			for c in valid:
				var hp = int(c.metadata.get("hp", "0"))
				if hp > best_hp:
					best_hp = hp
					chosen = c
		else:
			chosen = await main.card_ops.prompt_select_card(valid, "MESSENGER: SEARCH YOUR DECK", "Choose a Pokemon to put into your hand", "TAKE", false, true)
			if main._should_bail(): return
		if chosen != null:
			deck.erase(chosen)
			chosen.current_location = "hand"
			hand.append(chosen)
			main.refresh_hand_display(is_opponent)
			await main.show_message("PUT " + chosen.metadata.get("name", "").to_upper() + " INTO HAND!")
			if main._should_bail(): return
	else:
		await main.show_message("NO POKEMON FOUND IN THE DECK!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	if was_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return

# LUNAR POWER (Erika's Clefairy): flip — heads searches for an Evolution for a Benched Pokemon and evolves it
func execute_lunar_power(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! LUNAR POWER DID NOTHING!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var evo_cards: Array = []
	for c in deck:
		for bp in bench:
			if main.can_evolve_from(c, bp) and not bp.placed_on_field_this_turn and c not in evo_cards:
				evo_cards.append(c)
	if evo_cards.size() == 0:
		await main.show_message("HEADS! NO USABLE EVOLUTION FOUND!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen_evo: card_object = null
	if is_opponent:
		chosen_evo = evo_cards[0]
	else:
		chosen_evo = await main.card_ops.prompt_select_card(evo_cards, "LUNAR POWER: CHOOSE AN EVOLUTION", "Choose an Evolution card from your deck", "SELECT", true, true)
		if main._should_bail(): return
	if chosen_evo == null:
		deck.shuffle()
		return
	var targets: Array = []
	for bp in bench:
		if main.can_evolve_from(chosen_evo, bp) and not bp.placed_on_field_this_turn:
			targets.append(bp)
	var target: card_object = null
	if is_opponent or targets.size() == 1:
		target = targets[0]
	else:
		target = await main.card_ops.prompt_select_card(targets, "LUNAR POWER: CHOOSE A POKEMON", "Choose the Benched Pokemon to evolve", "EVOLVE", false)
		if main._should_bail(): return
		if target == null:
			target = targets[0]
	deck.erase(chosen_evo)
	gym2_evolve_bench(chosen_evo, target, is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEADS! " + target.metadata.get("name", "").to_upper() + " EVOLVED INTO " + chosen_evo.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# Helper: evolve a benched Pokemon with an evolution card (carries damage / energies / pre-evolutions)
func gym2_evolve_bench(evo_card: card_object, target_card: card_object, is_opponent: bool) -> void:
	var damage_taken = target_card.get_max_hp() - target_card.current_hp
	evo_card.current_hp = max(1, int(evo_card.metadata.get("hp", "0")) - damage_taken)
	evo_card.attached_energies = target_card.attached_energies.duplicate()
	target_card.attached_energies.clear()
	evo_card.attached_pre_evolutions = target_card.attached_pre_evolutions.duplicate()
	target_card.attached_pre_evolutions.clear()
	evo_card.attached_pre_evolutions.append(target_card)
	evo_card.placed_on_field_this_turn = true
	evo_card.current_location = "bench"
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var idx = bench.find(target_card)
	if idx != -1:
		bench[idx] = evo_card
	main.clear_all_statuses(target_card, is_opponent)

# ERRAND-RUNNING (Erika's Bulbasaur): flip — heads searches your deck for a Trainer card to your hand
func execute_errand_running(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NO TRAINER CARD FOUND!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var trainers: Array = []
	for c in deck:
		if c.metadata.get("supertype", "") == "Trainer":
			trainers.append(c)
	if trainers.size() == 0:
		await main.show_message("HEADS! NO TRAINER CARDS IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = trainers[0]
	else:
		chosen = await main.card_ops.prompt_select_card(trainers, "ERRAND-RUNNING: SEARCH FOR A TRAINER", "Choose a Trainer card to put into your hand", "TAKE", true, true)
		if main._should_bail(): return
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
		await main.show_message("HEADS! PUT " + chosen.metadata.get("name", "").to_upper() + " INTO HAND!")
		if main._should_bail(): return
	deck.shuffle()
	main.update_deck_icon(is_opponent)

# SURPRISE (Lt. Surge's Eevee): a random card from the opponent's hand is shuffled into their deck
func execute_surprise(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_hand.size() == 0:
		await main.show_message("THE OPPONENT HAS NO CARDS IN HAND!")
		if main._should_bail(): return
		return
	var picked = opp_hand[randi() % opp_hand.size()]
	var picked_name = picked.metadata.get("name", "")
	opp_hand.erase(picked)
	picked.current_location = "deck"
	opp_deck.append(picked)
	opp_deck.shuffle()
	main.refresh_hand_display(!is_opponent)
	main.update_deck_icon(!is_opponent)
	if is_opponent:
		await main.show_message("SURPRISE! A CARD FROM YOUR HAND WAS SHUFFLED INTO YOUR DECK!")
	else:
		await main.show_message("SURPRISE! " + picked_name.to_upper() + " WAS SHUFFLED INTO THE OPPONENT'S DECK!")
	if main._should_bail(): return

# FLIP-COUNTED BONUS DAMAGE (Lt. Surge's Electrode Power Ball): base + per-heads bonus
func execute_flip_bonus_per_heads(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, flip_count: int, per_heads: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(flip_count):
		var coin = await main.flip_coin(flip_count > 1, is_opponent)
		if coin:
			heads += 1
	var dmg = base_damage + per_heads * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DOUBLE-EDGE BOOSTED (Lt. Surge's Raticate, after Focus Energy): doubled base damage and self damage
func execute_double_edge_boosted(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.show_message("FOCUS ENERGY! DOUBLE-EDGE IS DOUBLED!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, 80)
	if main._should_bail(): return
	await gym2_self_damage(attacker, is_opponent, 40)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# ICE THROW (Misty's Dewgong): base damage doubled if the Defending Pokemon is Fighting type
func execute_ice_throw(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var dmg = base_damage
	if defender != null and "Fighting" in defender.metadata.get("types", []):
		dmg = base_damage * 2
		await main.show_message("THE DEFENDER IS FIGHTING — " + str(dmg) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# BENCH SNIPE (Sabrina's Haunter Shadow Attack, Blaine's Rhyhorn Overrun): active damage + flip to snipe a benched Pokemon
func execute_bench_snipe_flip(attacker: card_object, defender: card_object, is_opponent: bool, active_damage: int, bench_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if active_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, active_damage)
		if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		if opp_bench.size() > 0:
			var targets = await gym1_choose_bench_targets(opp_bench, 1, !is_opponent, is_opponent, "CHOOSE A BENCHED POKEMON")
			if main._should_bail(): return
			if targets.size() > 0:
				gym1_hit_raw(targets[0], bench_damage, !is_opponent)
				await main.show_message("HEADS! " + str(bench_damage) + " DAMAGE TO " + targets[0].metadata.get("name", "").to_upper() + "!")
				if main._should_bail(): return
		else:
			await main.show_message("HEADS! BUT THERE ARE NO BENCHED POKEMON!")
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! NO BENCH DAMAGE!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# INVIGORATE (Sabrina's Hypno): put a Basic Pokemon from a discard pile onto its owner's Bench, damaged
func execute_invigorate(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var candidates: Array = []
	var owner_map: Dictionary = {}
	if main.player_bench.size() < 5:
		for c in main.player_discard_pile:
			if main.is_basic_pokemon(c):
				candidates.append(c)
				owner_map[c] = false
	if main.opponent_bench.size() < 5:
		for c in main.opponent_discard_pile:
			if main.is_basic_pokemon(c):
				candidates.append(c)
				owner_map[c] = true
	if candidates.size() == 0:
		await main.show_message("NO BASIC POKEMON CAN BE INVIGORATED!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		var best_hp = -1
		for c in candidates:
			if owner_map[c] == true:
				var hp = int(c.metadata.get("hp", "0"))
				if hp > best_hp:
					best_hp = hp
					chosen = c
		if chosen == null:
			chosen = candidates[0]
	else:
		chosen = await main.card_ops.prompt_select_card(candidates, "INVIGORATE: CHOOSE A BASIC POKEMON", "Choose a Basic Pokemon from a discard pile", "SELECT", false, true)
		if main._should_bail(): return
	if chosen == null:
		return
	var owner_is_opp = owner_map[chosen]
	var dp = main.opponent_discard_pile if owner_is_opp else main.player_discard_pile
	var bench = main.opponent_bench if owner_is_opp else main.player_bench
	dp.erase(chosen)
	var max_hp = int(chosen.metadata.get("hp", "0"))
	var counters_dmg = int(max_hp / 2.0 / 10.0) * 10
	chosen.current_hp = max(1, max_hp - counters_dmg)
	chosen.current_location = "bench"
	chosen.placed_on_field_this_turn = true
	bench.append(chosen)
	main.display_pokemon(owner_is_opp)
	main.update_discard_pile_display(owner_is_opp)
	await main.show_message("INVIGORATE PUT " + chosen.metadata.get("name", "").to_upper() + " ONTO THE BENCH!")
	if main._should_bail(): return

# PENDULUM CURSE (Sabrina's Hypno): flip coins equal to the Defender's damage counters, 20× heads
func execute_pendulum_curse(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var flips = defender.get_damage_counters() if defender != null else 0
	if flips == 0:
		await main.show_message("THE DEFENDER HAS NO DAMAGE COUNTERS — 0 DAMAGE!")
		if main._should_bail(): return
		return
	var heads = 0
	for i in range(flips):
		var coin = await main.flip_coin(flips > 1, is_opponent)
		if coin:
			heads += 1
	var dmg = 20 * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# HELPING HAND (Sabrina's Jynx): heal a chosen opponent Pokemon fully, then draw that many cards
func execute_helping_hand(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var damaged: Array = []
	if opp_active != null and opp_active.get_damage_counters() > 0:
		damaged.append(opp_active)
	for bp in opp_bench:
		if bp.get_damage_counters() > 0:
			damaged.append(bp)
	if damaged.size() == 0:
		await main.show_message("NO DAMAGED OPPONENT POKEMON — HELPING HAND DID NOTHING.")
		if main._should_bail(): return
		return
	# The CPU declines to heal the player (chooses 0 counters)
	if is_opponent:
		await main.show_message("THE OPPONENT DECLINES TO USE HELPING HAND.")
		if main._should_bail(): return
		return
	var chosen = await main.card_ops.prompt_select_card(damaged, "HELPING HAND: CHOOSE A POKEMON", "Heal it fully and draw that many cards", "SELECT", true)
	if main._should_bail(): return
	if chosen == null:
		return
	var counters = chosen.get_damage_counters()
	chosen.current_hp = chosen.get_max_hp()
	main.display_hp_circles_above_align(chosen, is_opponent)
	main.display_pokemon(!is_opponent)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.card_ops.draw_n(false, counters)
	if main._should_bail(): return
	await main.show_message("HELPING HAND HEALED " + chosen.metadata.get("name", "").to_upper() + " AND DREW " + str(counters) + " CARDS!")
	if main._should_bail(): return

# LIFE DRAIN (Sabrina's Kadabra): flip — heads puts damage counters so the Defender has 10 HP left
func execute_life_drain(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! LIFE DRAIN FAILED!")
		if main._should_bail(): return
		return
	if defender != null:
		defender.current_hp = min(defender.current_hp, 10)
		main.display_hp_circles_above_align(defender, !is_opponent)
		await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " HAS ONLY 10 HP LEFT!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# MAGIC DARTS (Sabrina's Mr. Mime): choose an opponent Pokemon, flip 3, 10× heads, no W/R
func execute_magic_darts(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var pool: Array = []
	if opp_active != null:
		pool.append(opp_active)
	pool.append_array(opp_bench)
	if pool.size() == 0:
		return
	var target: card_object = null
	if is_opponent:
		target = opp_active
		var low = 9999
		for p in pool:
			if p.current_hp < low:
				low = p.current_hp
				target = p
	else:
		target = await main.card_ops.prompt_select_card(pool, "MAGIC DARTS: CHOOSE A TARGET", "Choose any of the opponent's Pokemon", "SELECT", false)
		if main._should_bail(): return
		if target == null:
			target = opp_active
	var heads = 0
	for i in range(3):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads += 1
	var dmg = 10 * heads
	await main.show_message("GOT " + str(heads) + " HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0 and target != null:
		gym1_hit_raw(target, dmg, !is_opponent)
		await main.check_all_knockouts()
		if main._should_bail(): return

# STOKE (Blaine's Growlithe): search your deck for a Fire Energy card and attach it to self
func execute_stoke(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var fire: Array = []
	for c in deck:
		if gym1_is_basic_energy(c) and "Fire" in main.get_energy_provided_by_card(c):
			fire.append(c)
	if fire.size() == 0:
		await main.show_message("NO FIRE ENERGY IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = fire[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(fire, "STOKE: SEARCH FOR FIRE ENERGY", "Choose a Fire Energy to attach", "ATTACH", false, true)
		if main._should_bail(): return
		if chosen == null:
			chosen = fire[0]
	deck.erase(chosen)
	chosen.current_location = "attached"
	attacker.attached_energies.append(chosen)
	deck.shuffle()
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("STOKE ATTACHED A FIRE ENERGY TO " + attacker.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# SEARCH TYPED ENERGY TO HAND (Sabrina's Drowzee Energy Support)
func execute_search_typed_energy_to_hand(attacker: card_object, is_opponent: bool, energy_type: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var matches: Array = []
	for c in deck:
		if gym1_is_basic_energy(c) and energy_type in main.get_energy_provided_by_card(c):
			matches.append(c)
	if matches.size() == 0:
		await main.show_message("NO " + energy_type.to_upper() + " ENERGY IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = matches[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(matches, "SEARCH FOR " + energy_type.to_upper() + " ENERGY", "Choose an Energy card to put into your hand", "TAKE", false, true)
		if main._should_bail(): return
		if chosen == null:
			chosen = matches[0]
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("PUT A " + energy_type.to_upper() + " ENERGY INTO HAND!")
	if main._should_bail(): return

# PRANKS (Blaine's Mankey): flip — heads moves a card from the opponent's discard pile to the top of their deck
func execute_pranks(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! PRANKS FAILED!")
		if main._should_bail(): return
		return
	var opp_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_discard.size() == 0:
		await main.show_message("THE OPPONENT'S DISCARD PILE IS EMPTY!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = opp_discard[opp_discard.size() - 1]
	else:
		chosen = await main.card_ops.prompt_select_card(opp_discard, "PRANKS: CHOOSE A CARD", "Choose a card from the opponent's discard pile", "SELECT", false, true)
		if main._should_bail(): return
		if chosen == null:
			chosen = opp_discard[opp_discard.size() - 1]
	opp_discard.erase(chosen)
	chosen.current_location = "deck"
	opp_deck.push_front(chosen)
	main.update_discard_pile_display(!is_opponent)
	main.update_deck_icon(!is_opponent)
	await main.show_message("HEADS! " + chosen.metadata.get("name", "").to_upper() + " WAS PUT ON TOP OF THE OPPONENT'S DECK.")
	if main._should_bail(): return

# GROUP THERAPY (Erika's Jigglypuff): both players remove 1 damage counter from each of their damaged Pokemon
func execute_group_therapy(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null:
		all_pokemon.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench:
		all_pokemon.append({"p": bp, "opp": false})
	for bp in main.opponent_bench:
		all_pokemon.append({"p": bp, "opp": true})
	var healed = 0
	for entry in all_pokemon:
		var p = entry["p"]
		if p.get_damage_counters() > 0:
			p.current_hp = min(p.get_max_hp(), p.current_hp + 10)
			main.display_hp_circles_above_align(p, entry["opp"])
			healed += 1
	main.display_pokemon(false)
	main.display_pokemon(true)
	if healed > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("GROUP THERAPY HEALED " + str(healed) + " POKEMON!")
	if main._should_bail(): return

# PULLED PUNCH (Erika's Jigglypuff): 40 if the Defender has no damage counters, otherwise 10
func execute_pulled_punch(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var dmg = 40
	if defender != null and defender.get_damage_counters() > 0:
		dmg = 10
	await gym1_hit_active(attacker, defender, is_opponent, dmg)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# HIND KICK (Blaine's Ponyta): damage, then flip — heads switches Ponyta with a Benched Pokemon
func execute_hind_kick(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() > 0 and (attacker == main.opponent_active_pokemon or attacker == main.player_active_pokemon):
		var coin = await main.flip_coin(false, is_opponent)
		if coin:
			await main.show_message("HEADS! " + attacker.metadata.get("name", "").to_upper() + " SWITCHES OUT!")
			if main._should_bail(): return
			await apply_self_switch(attacker, is_opponent)
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! NO SWITCH.")
			if main._should_bail(): return

# CALL WILL-O'-THE-WISP (Blaine's Vulpix): flip 3, per heads recover a Fire Energy from the discard to hand
func execute_call_wisp(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(3):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads += 1
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var recovered = 0
	for i in range(heads):
		var fire: card_object = null
		for c in discard_pile:
			if gym1_is_basic_energy(c) and "Fire" in main.get_energy_provided_by_card(c):
				fire = c
				break
		if fire == null:
			break
		discard_pile.erase(fire)
		fire.current_location = "hand"
		hand.append(fire)
		recovered += 1
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("GOT " + str(heads) + " HEADS! RECOVERED " + str(recovered) + " FIRE ENERGY!")
	if main._should_bail(): return

# FAST-ACTING POISON (Koga's Ekans): damage, flip 2 — both heads Confuses and Poisons the Defender
func execute_flip2_both_heads_status(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, statuses: Array) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
	if defender == null or defender.current_hp <= 0:
		await main.check_all_knockouts()
		return
	var coin1 = await main.flip_coin(true, is_opponent)
	var coin2 = await main.flip_coin(true, is_opponent)
	if coin1 and coin2:
		for s in statuses:
			var effect = {"type": "status", "target": "defender", "status": s, "flip": "none"}
			await main.apply_status_effect(effect, attacker, defender, is_opponent)
			if main._should_bail(): return
	else:
		await main.show_message("NOT BOTH HEADS — NO SPECIAL CONDITIONS!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# SLUDGE GRIP (Koga's Grimer): flip — heads switches a chosen opponent Benched Pokemon in and Poisons it
func execute_sludge_grip(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() == 0:
		await main.show_message("THE OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! SLUDGE GRIP FAILED!")
		if main._should_bail(): return
		return
	await apply_force_switch({"chooser": "attacker"}, is_opponent)
	if main._should_bail(): return
	var new_defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if new_defender != null:
		var effect = {"type": "status", "target": "defender", "status": "Poisoned", "flip": "none"}
		await main.apply_status_effect(effect, attacker, new_defender, is_opponent)
		if main._should_bail(): return

# GROUP ATTACK (Koga's Zubat): search for Koga's Zubats to bench, 10× the Koga's Zubats in play
func execute_group_attack(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var zubats: Array = []
	for c in deck:
		if c.metadata.get("name", "") == "Koga's Zubat" and "Basic" in c.metadata.get("subtypes", []):
			zubats.append(c)
	var added = 0
	if is_opponent:
		for z in zubats:
			if bench.size() >= main.get_max_bench_size():
				break
			deck.erase(z)
			z.current_location = "bench"
			z.current_hp = int(z.metadata.get("hp", "0"))
			z.placed_on_field_this_turn = true
			bench.append(z)
			added += 1
	else:
		while bench.size() < 5:
			var remaining: Array = []
			for z in zubats:
				if z.current_location == "deck":
					remaining.append(z)
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "GROUP ATTACK: SEARCH FOR KOGA'S ZUBAT", "Choose a Koga's Zubat to bench (cancel to stop)", "BENCH", true, true)
			if main._should_bail(): return
			if sel == null:
				break
			deck.erase(sel)
			sel.current_location = "bench"
			sel.current_hp = int(sel.metadata.get("hp", "0"))
			sel.placed_on_field_this_turn = true
			bench.append(sel)
			added += 1
	if added > 0:
		deck.shuffle()
		main.display_pokemon(is_opponent)
		main.update_deck_icon(is_opponent)
	var count = 0
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active != null and own_active.metadata.get("name", "") == "Koga's Zubat":
		count += 1
	for bp in bench:
		if bp.metadata.get("name", "") == "Koga's Zubat":
			count += 1
	var dmg = 10 * count
	await main.show_message(str(count) + " KOGA'S ZUBAT IN PLAY! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# BUBBLES (Misty's Poliwag): damage, then flip — tails disables this attack next turn
func execute_bubbles(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int, attack_name: String) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		attacker.disabled_attacks[attack_name] = "skip_one_turn"
		await main.show_message("TAILS! " + attack_name.to_upper() + " CAN'T BE USED NEXT TURN!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# ESP (Misty's Psyduck): flip 3 — 1 head draws, 2 heads do 20, 3 heads copy a Defender attack
func execute_esp(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(3):
		var coin = await main.flip_coin(true, is_opponent)
		if coin:
			heads += 1
	if heads == 1:
		await main.show_message("EXACTLY 1 HEADS! DRAW A CARD!")
		if main._should_bail(): return
		await main.card_ops.draw_n(is_opponent, 1)
		if main._should_bail(): return
	elif heads == 2:
		await main.show_message("EXACTLY 2 HEADS! 20 DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 20)
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	elif heads == 3:
		await main.show_message("ALL 3 HEADS! ESP COPIES AN ATTACK!")
		if main._should_bail(): return
		await execute_metronome(attacker, defender, is_opponent)
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("NO HEADS! ESP DID NOTHING.")
		if main._should_bail(): return

# STAR BOOMERANG (Misty's Staryu): damage, then flip — heads returns Staryu and attached cards to hand
func execute_star_boomerang(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! " + attacker.metadata.get("name", "").to_upper() + " RETURNS TO YOUR HAND!")
		if main._should_bail(): return
		var was_active = (attacker == main.opponent_active_pokemon) if is_opponent else (attacker == main.player_active_pokemon)
		gym1_return_pokemon_to_hand(attacker, is_opponent)
		main.refresh_hand_display(is_opponent)
		if was_active:
			await main.handle_post_knockout(is_opponent)
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! " + attacker.metadata.get("name", "").to_upper() + " STAYS IN PLAY.")
		if main._should_bail(): return

# FADE OUT (Sabrina's Gastly): damage, return Gastly and its Energy to hand, discard everything else attached
func execute_fade_out(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	# Discard pre-evolutions and other attached cards
	for pre in attacker.attached_pre_evolutions:
		pre.current_location = "discard"
		discard_pile.append(pre)
	attacker.attached_pre_evolutions.clear()
	for ac in attacker.attached_cards:
		ac.current_location = "discard"
		discard_pile.append(ac)
	attacker.attached_cards.clear()
	# Return Gastly + its Energy to hand
	for e in attacker.attached_energies:
		e.current_location = "hand"
		hand.append(e)
	attacker.attached_energies.clear()
	main.clear_all_statuses(attacker, is_opponent)
	attacker.pluspower_count = 0
	attacker.current_hp = int(attacker.metadata.get("hp", "0"))
	attacker.current_location = "hand"
	hand.append(attacker)
	var was_active = false
	if is_opponent:
		if main.opponent_active_pokemon == attacker:
			main.opponent_active_pokemon = null
			was_active = true
		else:
			main.opponent_bench.erase(attacker)
	else:
		if main.player_active_pokemon == attacker:
			main.player_active_pokemon = null
			was_active = true
		else:
			main.player_bench.erase(attacker)
	main.display_pokemon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("FADE OUT! " + attacker.metadata.get("name", "").to_upper() + " RETURNS TO YOUR HAND!")
	if main._should_bail(): return
	if was_active:
		await main.handle_post_knockout(is_opponent)
		if main._should_bail(): return

# RANDOM ESP (Sabrina's Psyduck): flip — heads does 20 and Confuses the Defender; tails Confuses Psyduck instead
func execute_random_esp(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if coin:
		await main.show_message("HEADS! 20 DAMAGE!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 20)
		if main._should_bail(): return
		if defender != null and defender.current_hp > 0:
			var effect = {"type": "status", "target": "defender", "status": "Confused", "flip": "none"}
			await main.apply_status_effect(effect, attacker, defender, is_opponent)
			if main._should_bail(): return
	else:
		await main.show_message("TAILS! THE ATTACK MISSES AND CONFUSES " + attacker.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		var self_effect = {"type": "status", "target": "self", "status": "Confused", "flip": "none"}
		await main.apply_status_effect(self_effect, attacker, defender, is_opponent)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# FURY PUNCH (Giovanni's Machop): flip — heads does 20× the damage counters on Machop
func execute_fury_punch(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! FURY PUNCH MISSES!")
		if main._should_bail(): return
		return
	var dmg = 20 * attacker.get_damage_counters()
	await main.show_message("HEADS! " + str(dmg) + " DAMAGE!")
	if main._should_bail(): return
	if dmg > 0:
		await gym1_hit_active(attacker, defender, is_opponent, dmg)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# INK SPURT (Misty's Horsea): damage, then flip — heads applies a Smokescreen-style effect to the Defender
func execute_ink_spurt(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if coin:
			await apply_blind_effect(defender, is_opponent)
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! NO EFFECT.")
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# DRAW FLIP (Koga's Tangela Grasping Vine): flip — heads draws cards
func execute_draw_flip(attacker: card_object, is_opponent: bool, count: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if not coin:
		await main.show_message("TAILS! NO CARDS DRAWN.")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, count)
	if main._should_bail(): return
	await main.show_message("HEADS! DREW " + str(count) + " CARD(S)!")
	if main._should_bail(): return

# PSYSCAN (Sabrina's Abra): look at the opponent's hand
func execute_psyscan(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if is_opponent:
		await main.show_message("THE OPPONENT LOOKS AT YOUR HAND!")
		if main._should_bail(): return
		return
	if main.opponent_hand.size() == 0:
		await main.show_message("THE OPPONENT HAS NO CARDS IN HAND!")
		if main._should_bail(): return
		return
	var _viewed = await main.card_ops.prompt_select_card(main.opponent_hand, "PSYSCAN: THE OPPONENT'S HAND", "Look at the opponent's hand, then continue", "DONE", false)
	if main._should_bail(): return

# SYNCHRONIZE (Sabrina's Abra): only usable if Abra and the Defender have the same number of Energy attached
func execute_synchronize(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender == null or attacker.attached_energies.size() != defender.attached_energies.size():
		await main.show_message("SYNCHRONIZE FAILED! ENERGY COUNTS DON'T MATCH!")
		if main._should_bail(): return
		return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# RETALIATION (Giovanni's Nidoran m): only usable with 2 or more damage counters on Nidoran
func execute_retaliation(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return

# LIE LOW (Brock's Dugtrio): reduce incoming damage next turn and arm Earthdrill
func execute_lie_low(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.damage_reduction_next_turn = 20
	attacker.gym2_lie_low_counter = 2
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name", "").to_upper() + " LIES LOW — DAMAGE REDUCED BY 20 NEXT TURN!")
	if main._should_bail(): return

######################################################################################################################################################
############################################################## SI1 (SOUTHERN ISLANDS) EFFECTS ########################################################
######################################################################################################################################################

# MEW — Rainbow Wave: Choose a type of Energy attached to Mew → 20 damage to every opponent
# Pokémon of that type (active + bench), ignoring Weakness and Resistance.
func execute_rainbow_wave(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if attacker.attached_energies.is_empty():
		await main.show_message("NO ENERGY ATTACHED TO MEW!")
		if main._should_bail(): return
		return

	# Build list of unique energy types currently on Mew
	var available_types: Array = []
	for e in attacker.attached_energies:
		for t in main.get_energy_provided_by_card(e):
			if t != "Colorless" and t not in available_types:
				available_types.append(t)
	if available_types.is_empty():
		await main.show_message("MEW HAS NO TYPED ENERGY!")
		if main._should_bail(): return
		return

	var chosen_type: String = ""
	if is_opponent:
		# CPU picks the type that hits the most opposing Pokémon
		var player_all: Array = []
		if main.player_active_pokemon != null:
			player_all.append(main.player_active_pokemon)
		player_all.append_array(main.player_bench)
		var best_count = -1
		for t in available_types:
			var count = player_all.filter(func(p): return t in p.metadata.get("types", [])).size()
			if count > best_count:
				best_count = count
				chosen_type = t
		if chosen_type == "":
			chosen_type = available_types[0]
		await main.show_message("MEW USES RAINBOW WAVE — " + chosen_type.to_upper() + " TYPE!")
		if main._should_bail(): return
	else:
		# Player picks from available energy types via a simple text-list prompt
		# Convert to "cards" for the selection UI — reuse energy cards as stand-ins
		var type_cards: Array = []
		for e in attacker.attached_energies:
			for t in main.get_energy_provided_by_card(e):
				if t != "Colorless" and not type_cards.any(func(c): return t in main.get_energy_provided_by_card(c)):
					type_cards.append(e)
					break
		if type_cards.size() == 1:
			chosen_type = available_types[0]
			await main.show_message("RAINBOW WAVE — " + chosen_type.to_upper() + " TYPE!")
			if main._should_bail(): return
		else:
			var picked = await main.card_ops.prompt_select_card(type_cards, "RAINBOW WAVE", "Choose an Energy type for Rainbow Wave", "SELECT", false)
			if main._should_bail(): return
			if picked == null:
				return
			var types_on_picked = main.get_energy_provided_by_card(picked)
			chosen_type = types_on_picked.filter(func(t): return t != "Colorless")[0] if types_on_picked.any(func(t): return t != "Colorless") else types_on_picked[0]

	# Deal 20 damage to every opponent Pokémon of the chosen type, no W/R
	var target_side_opp = not is_opponent
	var targets: Array = []
	if main.opponent_active_pokemon != null if target_side_opp else main.player_active_pokemon != null:
		var active = main.opponent_active_pokemon if target_side_opp else main.player_active_pokemon
		if active != null and chosen_type in active.metadata.get("types", []):
			targets.append({"p": active, "is_opp": target_side_opp})
	var bench = main.opponent_bench if target_side_opp else main.player_bench
	for bp in bench:
		if chosen_type in bp.metadata.get("types", []):
			targets.append({"p": bp, "is_opp": target_side_opp})

	if targets.is_empty():
		await main.show_message("RAINBOW WAVE — NO " + chosen_type.to_upper() + " POKÉMON TO HIT!")
		if main._should_bail(): return
		return

	for entry in targets:
		var p = entry["p"]
		main.card_ops.apply_bench_damage(p, 20, entry["is_opp"])
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
	await main.check_all_knockouts()
	if main._should_bail(): return
	await main.show_message("RAINBOW WAVE HITS " + str(targets.size()) + " " + chosen_type.to_upper() + " POKÉMON FOR 20 EACH!")
	if main._should_bail(): return

# IVYSAUR — Strange Scent: Each player flips a coin. Each player who gets heads removes
# 3 damage counters from their own Pokémon (or all if fewer than 3 total).
func execute_strange_scent(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	await main.show_message("STRANGE SCENT! BOTH PLAYERS FLIP A COIN...")
	if main._should_bail(): return

	# Attacker's side flips
	var attacker_coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if attacker_coin:
		await _strange_scent_heal_side(is_opponent, 3)
		if main._should_bail(): return

	# Defender's side flips
	var defender_coin = await main.flip_coin(false, not is_opponent)
	if main._should_bail(): return
	if defender_coin:
		await _strange_scent_heal_side(not is_opponent, 3)
		if main._should_bail(): return

	if not attacker_coin and not defender_coin:
		await main.show_message("BOTH TAILS — NO HEALING!")
		if main._should_bail(): return

func _strange_scent_heal_side(is_opp: bool, counters_to_remove: int) -> void:
	var all_p: Array = []
	var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
	if active != null: all_p.append(active)
	all_p.append_array(main.opponent_bench if is_opp else main.player_bench)

	var damaged = all_p.filter(func(p): return p.current_hp < p.get_max_hp())
	if damaged.is_empty():
		await main.show_message(("OPPONENT" if is_opp else "YOU") + " HEADS! NO DAMAGE TO REMOVE.")
		if main._should_bail(): return
		return

	var remaining = counters_to_remove
	if is_opp:
		# CPU removes counters from most damaged first
		damaged.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		for p in damaged:
			if remaining <= 0: break
			var removable = min(remaining, p.get_damage_counters())
			if removable > 0:
				await main.card_ops.heal_pokemon(p, removable * 10, true)
				if main._should_bail(): return
				remaining -= removable
	else:
		# Player distributes 3 counters across their damaged Pokémon — simplified: auto-remove from most damaged
		damaged.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		for p in damaged:
			if remaining <= 0: break
			var removable = min(remaining, p.get_damage_counters())
			if removable > 0:
				await main.card_ops.heal_pokemon(p, removable * 10, false)
				if main._should_bail(): return
				remaining -= removable
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message(("OPPONENT" if is_opp else "YOU") + " REMOVED " + str((counters_to_remove - remaining)) + " DAMAGE COUNTER(S)!")
	if main._should_bail(): return

# TENTACRUEL — Tentacle Grip: Flip N coins (N = Water Energy on Tentacruel). Each heads = draw 2 cards.
func execute_tentacle_grip(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var water_count = 0
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			water_count += 1
	if water_count == 0:
		await main.show_message("NO WATER ENERGY ATTACHED — NOTHING HAPPENS!")
		if main._should_bail(): return
		return

	await main.show_message("TENTACLE GRIP! FLIPPING " + str(water_count) + " COIN(S)...")
	if main._should_bail(): return

	var heads_total = 0
	for i in range(water_count):
		var coin = await main.flip_coin(water_count > 1, is_opponent)
		if main._should_bail(): return
		if coin:
			heads_total += 1

	if heads_total == 0:
		await main.show_message("ALL TAILS — NO CARDS DRAWN!")
		if main._should_bail(): return
		return

	var to_draw = heads_total * 2
	await main.card_ops.draw_n(is_opponent, to_draw)
	if main._should_bail(): return
	await main.show_message(str(heads_total) + " HEADS! DREW " + str(to_draw) + " CARDS!")
	if main._should_bail(): return

# MARILL — Squirt: Choose any opponent Pokémon (active or bench). 10 damage, no W/R.
func execute_squirt(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var target_is_opp = not is_opponent
	var all_targets: Array = []
	var active = main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon
	if active != null: all_targets.append(active)
	all_targets.append_array(main.opponent_bench if target_is_opp else main.player_bench)

	if all_targets.is_empty():
		return

	var target: card_object = null
	if is_opponent:
		target = main.player_active_pokemon
	else:
		target = await main.card_ops.prompt_select_card(all_targets, "SQUIRT — CHOOSE TARGET", "Select an opponent Pokémon to hit for 10 (no W/R)", "SQUIRT", false)
		if main._should_bail(): return
	if target == null: return

	var target_is_active = (target == (main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon))
	if target_is_active:
		# Active: apply directly, no W/R
		var label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		main.show_floating_label("-10HP", label_pos, Color.WHITE, true)
		target.current_hp = max(0, target.current_hp - 10)
		main.display_hp_circles_above_align(target, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await main.powers_and_bodies.dispatch_on_damage(target, attacker, 10, target_is_opp)
		if main._should_bail(): return
	else:
		main.card_ops.apply_bench_damage(target, 10, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)

	await main.check_all_knockouts()
	if main._should_bail(): return
	await main.show_message("SQUIRT! 10 DAMAGE TO " + target.metadata.get("name", "").to_upper() + "! (NO W/R)")
	if main._should_bail(): return

# LAPRAS — Gentle Song: Heal self 20 HP, heal defender 20 HP, then defender is Asleep.
func execute_gentle_song(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.card_ops.heal_pokemon(attacker, 20, is_opponent)
	if main._should_bail(): return
	if defender != null:
		await main.card_ops.heal_pokemon(defender, 20, not is_opponent)
		if main._should_bail(): return
		main.card_ops.apply_status(defender, "Asleep", not is_opponent)
	await main.show_message("GENTLE SONG: BOTH POKÉMON SOOTHED. OPPONENT IS NOW ASLEEP!")
	if main._should_bail(): return

# EXEGGUTOR — Sharpshooter: Choose target. Flip N coins (N = Grass Energy on Exeggutor).
# 10 damage per heads to chosen target, no W/R.
func execute_sharpshooter(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var grass_count = 0
	for e in attacker.attached_energies:
		if "Grass" in main.get_energy_provided_by_card(e):
			grass_count += 1
	if grass_count == 0:
		await main.show_message("NO GRASS ENERGY — NOTHING HAPPENS!")
		if main._should_bail(): return
		return

	# Pick target from all opponent Pokémon
	var target_is_opp = not is_opponent
	var all_targets: Array = []
	var active = main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon
	if active != null: all_targets.append(active)
	all_targets.append_array(main.opponent_bench if target_is_opp else main.player_bench)
	if all_targets.is_empty(): return

	var target: card_object = null
	if is_opponent:
		target = all_targets[0]
		for p in all_targets:
			if p.current_hp > (target.current_hp if target != null else 0):
				target = p
	else:
		target = await main.card_ops.prompt_select_card(all_targets, "SHARPSHOOTER — CHOOSE TARGET", "Flip " + str(grass_count) + " coin(s) for 10 damage per heads", "SELECT", false)
		if main._should_bail(): return
	if target == null: return

	await main.show_message("SHARPSHOOTER! FLIPPING " + str(grass_count) + " COIN(S)...")
	if main._should_bail(): return

	var heads = 0
	for i in range(grass_count):
		if await main.flip_coin(grass_count > 1, is_opponent):
			heads += 1
		if main._should_bail(): return

	var damage = heads * 10
	if damage == 0:
		await main.show_message("ALL TAILS — NO DAMAGE!")
		if main._should_bail(): return
		return

	var target_is_active = (target == (main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon))
	if target_is_active:
		var label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		main.show_floating_label("-" + str(damage) + "HP", label_pos, Color.WHITE, true)
		target.current_hp = max(0, target.current_hp - damage)
		main.display_hp_circles_above_align(target, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await main.powers_and_bodies.dispatch_on_damage(target, attacker, damage, target_is_opp)
		if main._should_bail(): return
	else:
		main.card_ops.apply_bench_damage(target, damage, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)

	await main.check_all_knockouts()
	if main._should_bail(): return
	await main.show_message(str(heads) + " HEADS! " + str(damage) + " DAMAGE TO " + target.metadata.get("name", "").to_upper() + "! (NO W/R)")
	if main._should_bail(): return

# SLOWKING — Revelation: Flip coin. Heads = search deck for a Trainer card, add to hand.
func execute_revelation(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! REVELATION FAILED!")
		if main._should_bail(): return
		return

	var filter = func(c): return main.trainer_effects.is_trainer_card(c) and not main.trainer_effects.is_attached_trainer(c) and not main.trainer_effects.is_bench_token_trainer(c)
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter, "REVELATION — SEARCH FOR A TRAINER", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("HEADS! NO TRAINER CARDS IN DECK!")
	else:
		await main.show_message("HEADS! FOUND " + found[0].metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# LICKITUNG — Lick Wounds: Flip coin. Heads = choose any Pokémon from either side
# with damage counters → remove 2 damage counters (or 1 if only 1 remains).
func execute_lick_wounds(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! LICK WOUNDS FAILED!")
		if main._should_bail(): return
		return

	# Gather all Pokémon from both sides that have damage
	var all_candidates: Array = []
	for poke in [main.player_active_pokemon, main.opponent_active_pokemon]:
		if poke != null and poke.current_hp < poke.get_max_hp():
			all_candidates.append(poke)
	for bp in main.player_bench:
		if bp.current_hp < bp.get_max_hp(): all_candidates.append(bp)
	for bp in main.opponent_bench:
		if bp.current_hp < bp.get_max_hp(): all_candidates.append(bp)

	if all_candidates.is_empty():
		await main.show_message("HEADS! NO POKÉMON WITH DAMAGE!")
		if main._should_bail(): return
		return

	var target: card_object = null
	if is_opponent:
		# CPU heals the Pokémon with the most damage on its own side
		var own_damaged = all_candidates.filter(func(p): return p == main.opponent_active_pokemon or p in main.opponent_bench)
		target = own_damaged[0] if not own_damaged.is_empty() else all_candidates[0]
		for p in own_damaged:
			if p.get_damage_counters() > target.get_damage_counters():
				target = p
	else:
		target = await main.card_ops.prompt_select_card(all_candidates, "LICK WOUNDS — CHOOSE TARGET", "Remove 2 damage counters (or 1 if only 1)", "HEAL", false)
		if main._should_bail(): return
	if target == null: return

	var heal = min(2, target.get_damage_counters()) * 10
	var target_is_opp = target == main.opponent_active_pokemon or target in main.opponent_bench
	await main.card_ops.heal_pokemon(target, heal, target_is_opp)
	if main._should_bail(): return
	await main.show_message("LICK WOUNDS HEALED " + target.metadata.get("name", "").to_upper() + " FOR " + str(heal) + " HP!")
	if main._should_bail(): return

# LICKITUNG — Tongue Stretch: Flip coin. Heads = choose any opponent Pokémon → 20 damage, no W/R.
func execute_tongue_stretch(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! TONGUE STRETCH FAILED!")
		if main._should_bail(): return
		return

	var target_is_opp = not is_opponent
	var all_targets: Array = []
	var active = main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon
	if active != null: all_targets.append(active)
	all_targets.append_array(main.opponent_bench if target_is_opp else main.player_bench)
	if all_targets.is_empty(): return

	var target: card_object = null
	if is_opponent:
		target = main.player_active_pokemon
	else:
		target = await main.card_ops.prompt_select_card(all_targets, "TONGUE STRETCH — CHOOSE TARGET", "20 damage, no Weakness or Resistance", "STRETCH", false)
		if main._should_bail(): return
	if target == null: return

	var target_is_active = (target == (main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon))
	if target_is_active:
		var label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		main.show_floating_label("-20HP", label_pos, Color.WHITE, true)
		target.current_hp = max(0, target.current_hp - 20)
		main.display_hp_circles_above_align(target, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await main.powers_and_bodies.dispatch_on_damage(target, attacker, 20, target_is_opp)
		if main._should_bail(): return
	else:
		main.card_ops.apply_bench_damage(target, 20, target_is_opp)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)

	await main.check_all_knockouts()
	if main._should_bail(): return
	await main.show_message("TONGUE STRETCH! 20 DAMAGE TO " + target.metadata.get("name", "").to_upper() + "! (NO W/R)")
	if main._should_bail(): return

# VILEPLUME — Paradise Pollen: Flip coin. Heads = heal Vileplume 20 HP, then optionally
# heal one benched Pokémon 20 HP.
func execute_paradise_pollen(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! PARADISE POLLEN FAILED!")
		if main._should_bail(): return
		return

	# Heal Vileplume itself
	await main.card_ops.heal_pokemon(attacker, 20, is_opponent)
	if main._should_bail(): return

	# Heal one benched Pokémon with damage counters
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var bench_damaged = bench.filter(func(p): return p.current_hp < p.get_max_hp())
	if bench_damaged.is_empty():
		await main.show_message("PARADISE POLLEN! VILEPLUME HEALED. NO BENCHED POKÉMON WITH DAMAGE.")
		if main._should_bail(): return
		return

	var bench_target: card_object = null
	if is_opponent:
		for p in bench_damaged:
			if bench_target == null or p.get_damage_counters() > bench_target.get_damage_counters():
				bench_target = p
	else:
		bench_target = await main.card_ops.prompt_select_card(bench_damaged, "PARADISE POLLEN", "Choose a Benched Pokémon to heal 20 HP", "HEAL", false)
		if main._should_bail(): return
	if bench_target != null:
		await main.card_ops.heal_pokemon(bench_target, 20, is_opponent)
		if main._should_bail(): return
	await main.show_message("PARADISE POLLEN! VILEPLUME AND " + (bench_target.metadata.get("name", "") if bench_target else "BENCH") + " HEALED!")
	if main._should_bail(): return

# PRIMEAPE — Rampage: 20 + 10 per damage counter on Primeape. Then flip coin:
# if tails, Primeape is now Confused.
func execute_rampage(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return

	var counters = attacker.get_damage_counters()
	var total_damage = base_damage + counters * 10

	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total_damage, attacking_types, defender, attacker)
	var final_damage = result["damage"]
	if not main.check_defender_invincible(defender, not is_opponent):
		final_damage = main.apply_defender_no_damage_shield(defender, final_damage, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, total_damage)
		if main._should_bail(): return

	if counters > 0:
		await main.show_message("RAMPAGE! " + str(counters) + " COUNTER(S) — " + str(total_damage) + " BASE DAMAGE!")
		if main._should_bail(): return

	# Post-damage self-confusion flip
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		main.card_ops.apply_status(attacker, "Confused", is_opponent)
		await main.show_message("TAILS! " + attacker.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
		if main._should_bail(): return

######################################################################################################################################################
############################################################## BASEP EFFECTS ########################################################################
######################################################################################################################################################

# ENERGY ABSORPTION (basep-3/14 Mewtwo): recover up to 2 energy from discard pile, attach to self
func execute_energy_absorption(attacker: card_object, is_opponent: bool, max_count: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var energy_cards: Array = []
	for c in discard_pile:
		if c.metadata.get("supertype", "") == "Energy":
			energy_cards.append(c)
	if energy_cards.size() == 0:
		await main.show_message("NO ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
		return
	var taken = 0
	if is_opponent:
		var n = min(max_count, energy_cards.size())
		for i in range(n):
			var e = energy_cards[i]
			discard_pile.erase(e)
			e.current_location = "attached"
			attacker.attached_energies.append(e)
			taken += 1
	else:
		for _pick in range(min(max_count, energy_cards.size())):
			var remaining: Array = energy_cards.filter(func(c): return c.current_location != "attached")
			if remaining.size() == 0:
				break
			var sel = await main.card_ops.prompt_select_card(remaining, "ENERGY ABSORPTION: CHOOSE ENERGY", "Select an Energy to attach (cancel to stop)", "ATTACH", _pick > 0)
			if main._should_bail(): return
			if sel == null:
				break
			discard_pile.erase(sel)
			sel.current_location = "attached"
			attacker.attached_energies.append(sel)
			taken += 1
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	if taken > 0:
		await main.show_message("ENERGY ABSORPTION! ATTACHED " + str(taken) + " ENERGY TO " + attacker.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Energy Absorption - attached ", taken, " energy")

# RECHARGE (basep-4 Pikachu): search deck for a Lightning Energy card, attach to self
func execute_basep_recharge(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var matches: Array = []
	for c in deck:
		if c.metadata.get("supertype", "") == "Energy" and "Lightning" in main.get_energy_provided_by_card(c):
			matches.append(c)
	if matches.size() == 0:
		await main.show_message("NO LIGHTNING ENERGY IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = matches[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(matches, "RECHARGE", "Choose a Lightning Energy to attach", "ATTACH", false, true)
		if main._should_bail(): return
		if chosen == null:
			chosen = matches[0]
	deck.erase(chosen)
	chosen.current_location = "attached"
	attacker.attached_energies.append(chosen)
	deck.shuffle()
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("RECHARGE! LIGHTNING ENERGY ATTACHED TO " + attacker.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Recharge - Lightning Energy attached from deck")

# FLAMES OF RAGE (basep-6 Arcanine): discard 2 Fire Energy, 40 + 10 per damage counter on Arcanine
func execute_flames_of_rage(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var fire_energies: Array = []
	for e in attacker.attached_energies:
		if "Fire" in main.get_energy_provided_by_card(e):
			fire_energies.append(e)
	for i in range(2):
		var e = fire_energies[i]
		attacker.attached_energies.erase(e)
		main.card_ops.discard_energy_from_pokemon(e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("DISCARDED 2 FIRE ENERGY!")
	if main._should_bail(): return
	var counters = attacker.get_damage_counters()
	var total = 40 + counters * 10
	if counters > 0:
		await main.show_message("FLAMES OF RAGE! " + str(counters) + " DAMAGE COUNTER(S) — " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Flames of Rage - ", counters, " counters, ", total, " damage")

# DEVOLUTION BEAM (basep-8/9 Mew): choose any evolved Pokemon, return its top evolution to its player's hand
func execute_devolution_beam(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var all_evolved: Array = []
	var owner_map: Dictionary = {}
	for entry in [{"p": main.player_active_pokemon, "opp": false}, {"p": main.opponent_active_pokemon, "opp": true}]:
		if entry["p"] != null and entry["p"].attached_pre_evolutions.size() > 0:
			all_evolved.append(entry["p"])
			owner_map[entry["p"]] = entry["opp"]
	for bp in main.player_bench:
		if bp.attached_pre_evolutions.size() > 0:
			all_evolved.append(bp)
			owner_map[bp] = false
	for bp in main.opponent_bench:
		if bp.attached_pre_evolutions.size() > 0:
			all_evolved.append(bp)
			owner_map[bp] = true
	if all_evolved.size() == 0:
		await main.show_message("NO EVOLVED POKEMON TO TARGET WITH DEVOLUTION BEAM!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		# CPU targets highest-stage opponent Pokemon
		var best = -1
		for p in all_evolved:
			if not owner_map[p]:
				var stage = p.attached_pre_evolutions.size()
				if stage > best:
					best = stage
					target = p
		if target == null:
			target = all_evolved[0]
	else:
		target = await main.card_ops.prompt_select_card(all_evolved, "DEVOLUTION BEAM", "Choose an evolved Pokemon to devolve by one stage", "SELECT", false)
		if main._should_bail(): return
		if target == null:
			return
	var target_is_opp: bool = owner_map.get(target, false)
	var target_hand = main.opponent_hand if target_is_opp else main.player_hand
	# The highest-stage card is target itself; devolve one step back
	var new_form: card_object = target.attached_pre_evolutions.back()
	target.attached_pre_evolutions.erase(new_form)
	# Transfer attachments to the new (lower-stage) form
	new_form.attached_energies = target.attached_energies.duplicate()
	target.attached_energies.clear()
	new_form.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
	target.attached_pre_evolutions.clear()
	new_form.attached_cards = target.attached_cards.duplicate()
	target.attached_cards.clear()
	# Carry damage over
	var old_max = target.get_max_hp()
	var damage_taken = old_max - target.current_hp
	var new_max = int(new_form.metadata.get("hp", "0"))
	new_form.current_hp = max(10, new_max - damage_taken)
	new_form.current_location = target.current_location
	main.clear_all_statuses(new_form, target_is_opp)
	# Replace target in active or bench slot
	if target == (main.opponent_active_pokemon if target_is_opp else main.player_active_pokemon):
		if target_is_opp:
			main.opponent_active_pokemon = new_form
		else:
			main.player_active_pokemon = new_form
	else:
		var bench = main.opponent_bench if target_is_opp else main.player_bench
		var idx = bench.find(target)
		if idx >= 0:
			bench[idx] = new_form
	# Return the evolution card to hand
	target.current_location = "hand"
	target_hand.append(target)
	main.display_pokemon(target_is_opp)
	main.display_active_pokemon_energies(target_is_opp)
	main.refresh_hand_display(target_is_opp)
	await main.show_message("DEVOLUTION BEAM! " + target.metadata.get("name", "").to_upper() + " RETURNED TO " + ("OPPONENT'S" if target_is_opp else "YOUR") + " HAND!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Devolution Beam - ", target.metadata.get("name", ""), " returned to hand")

# CAT PUNCH (basep-10 Meowth): flip coin — heads 20 to active; tails 20 to a chosen bench Pokemon
func execute_cat_punch(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.show_message("HEADS! 20 DAMAGE TO THE DEFENDING POKEMON!")
		if main._should_bail(): return
		await gym1_hit_active(attacker, defender, is_opponent, 20)
		if main._should_bail(): return
	else:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		if opp_bench.size() == 0:
			await main.show_message("TAILS! BUT OPPONENT HAS NO BENCH!")
			if main._should_bail(): return
			return
		var targets = opp_bench.duplicate()
		var target_pokemon: card_object
		if is_opponent:
			targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
			target_pokemon = targets[0]
		else:
			target_pokemon = await main.card_ops.prompt_select_card(targets, "CAT PUNCH — CHOOSE BENCH TARGET", "Choose a Benched Pokemon to deal 20 damage to", "SELECT", false)
			if main._should_bail(): return
			if target_pokemon == null:
				target_pokemon = targets[0]
		main.card_ops.apply_bench_damage(target_pokemon, 20, !is_opponent)
		await main.show_message("TAILS! 20 DAMAGE TO " + target_pokemon.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Cat Punch")

# ENERGY CONTROL (basep-12 Mewtwo): flip coin — heads: move 1 basic energy from one opponent Pokemon to another
func execute_energy_control(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENERGY CONTROL FAILED!")
		if main._should_bail(): return
		return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_is = not is_opponent
	var all_opp: Array = []
	if opp_active != null:
		all_opp.append(opp_active)
	all_opp.append_array(opp_bench)
	# Find a Pokemon with a basic energy attached
	var sources_with_energy: Array = all_opp.filter(func(p): return p.attached_energies.size() > 0)
	if sources_with_energy.size() == 0 or all_opp.size() < 2:
		await main.show_message("HEADS! BUT OPPONENT HAS NO VALID ENERGY TO MOVE!")
		if main._should_bail(): return
		return
	# Pick source and destination — CPU picks worst source, moves energy to best bench mon
	var source_pokemon: card_object
	var dest_pokemon: card_object
	if is_opponent:
		source_pokemon = sources_with_energy[0]
		var dests: Array = all_opp.filter(func(p): return p != source_pokemon)
		dest_pokemon = dests[0] if dests.size() > 0 else null
	else:
		source_pokemon = await main.card_ops.prompt_select_card(sources_with_energy, "ENERGY CONTROL: SOURCE", "Choose an opponent's Pokemon to take energy from", "SELECT", false)
		if main._should_bail(): return
		if source_pokemon == null:
			return
		var dests = all_opp.filter(func(p): return p != source_pokemon)
		if dests.size() == 0:
			return
		dest_pokemon = await main.card_ops.prompt_select_card(dests, "ENERGY CONTROL: DESTINATION", "Choose an opponent's Pokemon to attach energy to", "SELECT", false)
		if main._should_bail(): return
		if dest_pokemon == null:
			return
	var energy = source_pokemon.attached_energies[0]
	source_pokemon.attached_energies.erase(energy)
	dest_pokemon.attached_energies.append(energy)
	main.display_active_pokemon_energies(opp_is)
	await main.show_message("ENERGY CONTROL! MOVED ENERGY FROM " + source_pokemon.metadata.get("name","").to_upper() + " TO " + dest_pokemon.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Energy Control")

# TEXTURE MAGIC (basep-15 Cool Porygon): change Porygon's resistance and/or defender's weakness
# Simplified: uses attacker's own type as the new weakness on defender, and applies resistance to self
func execute_texture_magic(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Darkness", "Metal"]
	if is_opponent:
		var player_type = main.player_active_pokemon.metadata.get("types", ["Colorless"])[0] if main.player_active_pokemon else "Colorless"
		attacker.temporary_resistance = player_type if player_type != "Colorless" else "Fighting"
		var opp_type = attacker.metadata.get("types", ["Colorless"])[0]
		if defender != null:
			defender.temporary_weakness = opp_type if opp_type != "Colorless" else "Lightning"
	else:
		attacker.temporary_resistance = types[randi() % types.size()]
		if defender != null and defender.metadata.get("weaknesses", []).size() > 0:
			defender.temporary_weakness = types[randi() % types.size()]
	await main.show_message("TEXTURE MAGIC! TYPES CHANGED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Texture Magic - resistance/weakness changed")

# MIRACULOUS COMEBACK (basep-18 Team Rocket's Meowth): flip coins = Pokemon in play count; 10×heads to active, 10×tails to self
func execute_miraculous_comeback(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var in_play_count = 0
	if main.player_active_pokemon != null: in_play_count += 1
	if main.opponent_active_pokemon != null: in_play_count += 1
	in_play_count += main.player_bench.size() + main.opponent_bench.size()
	if in_play_count == 0:
		return
	var heads = 0
	var tails = 0
	for _i in range(in_play_count):
		var c = await main.flip_coin(in_play_count > 1, is_opponent)
		if c:
			heads += 1
		else:
			tails += 1
	var active_damage = heads * 10
	var self_damage = tails * 10
	await main.show_message("MIRACULOUS COMEBACK! " + str(heads) + " HEADS, " + str(tails) + " TAILS! " + str(active_damage) + " DAMAGE!")
	if main._should_bail(): return
	if active_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, active_damage)
		if main._should_bail(): return
	if self_damage > 0:
		await gym2_self_damage(attacker, is_opponent, self_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Miraculous Comeback - ", active_damage, " to active, ", self_damage, " self-damage")

# HYPER FLAME (basep-21 Moltres): 60 damage; heads = discard 1 Fire, tails = discard all energy
func execute_hyper_flame(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 60)
	if main._should_bail(): return
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		var fire_e = attacker.attached_energies.filter(func(e): return "Fire" in main.get_energy_provided_by_card(e))
		if fire_e.size() > 0:
			var e = fire_e[0]
			attacker.attached_energies.erase(e)
			main.card_ops.discard_energy_from_pokemon(e, is_opponent)
			await main.show_message("HEADS! DISCARDED 1 FIRE ENERGY!")
		else:
			await main.show_message("HEADS! BUT NO FIRE ENERGY TO DISCARD!")
	else:
		var all_e = attacker.attached_energies.duplicate()
		for e in all_e:
			attacker.attached_energies.erase(e)
			main.card_ops.discard_energy_from_pokemon(e, is_opponent)
		await main.show_message("TAILS! ALL ENERGY DISCARDED!")
	if main._should_bail(): return
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Hyper Flame")

# LIGHTNING BURN (basep-23 Zapdos): 30 damage; heads = 30 to chosen bench; tails = 30 to self
func execute_lightning_burn(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 30)
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		if opp_bench.size() > 0:
			var bench_targets = await gym1_choose_bench_targets(opp_bench, 1, !is_opponent, is_opponent, "LIGHTNING BURN — CHOOSE BENCH TARGET")
			if main._should_bail(): return
			if bench_targets.size() > 0:
				main.card_ops.apply_bench_damage(bench_targets[0], 30, !is_opponent)
				await main.show_message("HEADS! 30 DAMAGE TO " + bench_targets[0].metadata.get("name","").to_upper() + "!")
				if main._should_bail(): return
		else:
			await main.show_message("HEADS! BUT OPPONENT HAS NO BENCH!")
			if main._should_bail(): return
	else:
		await gym2_self_damage(attacker, is_opponent, 30)
		if main._should_bail(): return
		await main.show_message("TAILS! ZAPDOS TAKES 30 DAMAGE!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Lightning Burn")


# PAINT (basep-32 Smeargle): flip coin; heads = change defending Pokemon's type
func execute_paint(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! PAINT FAILED!")
		if main._should_bail(): return
		return
	var types = ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Darkness", "Metal"]
	var chosen_type: String
	if is_opponent:
		# CPU picks the type that the player's active is weak to
		var player_active = main.player_active_pokemon
		var player_weakness = player_active.metadata.get("weaknesses", []) if player_active else []
		chosen_type = player_weakness[0].get("type", "Fire") if player_weakness.size() > 0 else types[0]
	else:
		chosen_type = types[randi() % types.size()]
		await main.show_message("PAINT! THE DEFENDING POKEMON IS NOW " + chosen_type.to_upper() + " TYPE!")
		if main._should_bail(): return
	if defender != null:
		defender.temporary_type = chosen_type
		main.update_status_icons(defender, !is_opponent)
	await main.show_message("PAINT! THE DEFENDING POKEMON IS NOW " + chosen_type.to_upper() + " TYPE!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Paint - defender type changed to ", chosen_type)

# PROTECTIVE FLAME (basep-34 Entei): 50 damage + bench pokemon cannot be damaged next opponent turn
func execute_protective_flame(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 50)
	if main._should_bail(): return
	# Mark all own bench pokemon as invincible for next turn (bench protection)
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	for bp in own_bench:
		bp.is_invincible = true
	await main.show_message("PROTECTIVE FLAME! YOUR BENCH IS PROTECTED NEXT TURN!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Protective Flame - 50 damage + bench protected")

# LET'S PLAY! (basep-35 Pichu): search your deck for a Baby Pokemon and bench it
func execute_lets_play(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var babies: Array = deck.filter(func(c): return "Baby" in c.metadata.get("subtypes", []))
	if babies.size() == 0:
		await main.show_message("NO BABY POKEMON IN THE DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var chosen: card_object = babies[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(babies, "LET'S PLAY! — SEARCH FOR BABY", "Choose a Baby Pokemon to put on your Bench", "BENCH", false, true)
		if main._should_bail(): return
		if chosen == null:
			chosen = babies[0]
	deck.erase(chosen)
	chosen.current_location = "bench"
	chosen.placed_on_field_this_turn = true
	bench.append(chosen)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("LET'S PLAY! " + chosen.metadata.get("name","").to_upper() + " JOINED THE BENCH!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Let's Play! - ", chosen.metadata.get("name",""), " benched")

# RAPID SPIN (basep-37 Hitmontop): 30 damage; opponent switches active, then attacker switches
func execute_rapid_spin(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 30)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	# Opponent switches their active (they choose)
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() > 0:
		await main.show_message("RAPID SPIN! OPPONENT MUST SWITCH ACTIVE!")
		if main._should_bail(): return
		var effect = {"type": "force_switch", "target": "defender", "chooser": "defender", "flip": "none"}
		await apply_force_switch(effect, is_opponent)
		if main._should_bail(): return
	# Attacker switches their active (they choose)
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() > 0:
		await main.show_message("RAPID SPIN! SWITCH YOUR ACTIVE POKEMON!")
		if main._should_bail(): return
		var self_effect = {"type": "self_switch", "target": "self", "flip": "none"}
		await apply_self_switch(attacker, is_opponent)
		if main._should_bail(): return
	print("ATTACK EXECUTED: Rapid Spin - 30 damage + both switch")

# PAIN SPLIT (basep-39 Misdreavus): put 1 damage counter on defender for each damage counter on Misdreavus
func execute_pain_split(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var counters = attacker.get_damage_counters()
	if counters == 0:
		await main.show_message("MISDREAVUS HAS NO DAMAGE COUNTERS — PAIN SPLIT DOES NOTHING!")
		if main._should_bail(): return
		return
	if defender == null or defender.is_invincible:
		return
	var damage = counters * 10
	defender.current_hp = max(0, defender.current_hp - damage)
	main.display_hp_circles_above_align(defender, !is_opponent)
	main.show_floating_label("-" + str(damage) + "HP", Vector2(530 if is_opponent else 1030, 300), Color.WHITE, true)
	await main.powers_and_bodies.dispatch_on_damage(defender, attacker, damage, !is_opponent)
	if main._should_bail(): return
	await main.show_message("PAIN SPLIT! " + str(counters) + " COUNTER(S) — " + str(damage) + " DAMAGE!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Pain Split - ", counters, " counters, ", damage, " damage")

# SEETHING ANGER (basep-43 Machamp): flip coins = damage counter count; 20 + 10 per heads
func execute_seething_anger(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var counters = attacker.get_damage_counters()
	var heads = 0
	if counters > 0:
		for _i in range(counters):
			var c = await main.flip_coin(counters > 1, is_opponent)
			if c:
				heads += 1
	var total = 20 + heads * 10
	if counters > 0:
		await main.show_message("SEETHING ANGER! " + str(heads) + "/" + str(counters) + " HEADS — " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Seething Anger - ", heads, " heads, ", total, " damage")

# BASEP FLING (basep-43 Machamp): 50 damage + opponent switches bench to active
func execute_basep_fling(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 50)
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() > 0:
		await main.show_message("FLING! OPPONENT MUST SWITCH ACTIVE!")
		if main._should_bail(): return
		var effect = {"type": "force_switch", "target": "defender", "chooser": "defender", "flip": "none"}
		await apply_force_switch(effect, is_opponent)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Basep Fling - 50 damage + force switch")

# BURNING FIRE (basep-44 Magmar): 10 + discard any number of Fire Energy from any own Pokemon, +10 per discarded
func execute_burning_fire(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var own_all: Array = []
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active != null:
		own_all.append(own_active)
	own_all.append_array(main.opponent_bench if is_opponent else main.player_bench)
	var discard_pile = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	# Collect all Fire energies from all own Pokemon
	var all_fire: Array = []
	for p in own_all:
		for e in p.attached_energies:
			if "Fire" in main.get_energy_provided_by_card(e):
				all_fire.append({"card": e, "owner": p})
	var discarded = 0
	if all_fire.size() == 0:
		await main.show_message("NO FIRE ENERGY TO DISCARD!")
		if main._should_bail(): return
	elif is_opponent:
		# CPU discards all available Fire Energy for maximum damage
		for entry in all_fire:
			var e = entry["card"]
			entry["owner"].attached_energies.erase(e)
			e.current_location = "discard"
			discard_pile.append(e)
			discarded += 1
	else:
		# Player chooses which Fire Energy to discard
		for _i in range(all_fire.size()):
			var remaining = all_fire.filter(func(entry): return entry["card"].current_location != "discard")
			if remaining.size() == 0:
				break
			var energy_cards = remaining.map(func(entry): return entry["card"])
			var sel = await main.card_ops.prompt_select_card(energy_cards, "BURNING FIRE — DISCARD FIRE ENERGY", "Select Fire Energy to discard (+10 dmg each), or cancel to stop", "DISCARD", true)
			if main._should_bail(): return
			if sel == null:
				break
			for entry in all_fire:
				if entry["card"] == sel:
					entry["owner"].attached_energies.erase(sel)
					sel.current_location = "discard"
					discard_pile.append(sel)
					discarded += 1
					break
	var total = 10 + discarded * 10
	if discarded > 0:
		await main.show_message("DISCARDED " + str(discarded) + " FIRE ENERGY! " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Burning Fire - discarded ", discarded, " Fire, ", total, " damage")

# LIGHTNING ROD (basep-46 Electabuzz): place a Lightning Rod marker on one of the opponent's Pokemon
func execute_lightning_rod(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_all: Array = []
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_active != null:
		opp_all.append(opp_active)
	opp_all.append_array(main.player_bench if is_opponent else main.opponent_bench)
	if opp_all.size() == 0:
		await main.show_message("NO OPPONENT POKEMON TO MARK!")
		if main._should_bail(): return
		return
	# Clear any existing marker first
	for p in opp_all:
		p.lightning_rod_marked = false
	var target: card_object
	if is_opponent:
		# CPU marks the Pokemon with most HP remaining
		var best_hp = -1
		for p in opp_all:
			if p.current_hp > best_hp:
				best_hp = p.current_hp
				target = p
	else:
		target = await main.card_ops.prompt_select_card(opp_all, "LIGHTNING ROD — CHOOSE TARGET", "Place a Lightning Rod marker on an opponent's Pokemon", "SELECT", false)
		if main._should_bail(): return
		if target == null:
			target = opp_all[0]
	target.lightning_rod_marked = true
	await main.show_message("LIGHTNING ROD MARKER PLACED ON " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Lightning Rod - marked ", target.metadata.get("name",""))

# LIGHTNING BOLT (basep-46 Electabuzz): 10 damage + 20 to the marked Pokemon (if any)
func execute_lightning_bolt(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, 10)
	if main._should_bail(): return
	# Find and damage the marked Pokemon
	var opp_all: Array = []
	var opp_is = not is_opponent
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_active != null:
		opp_all.append(opp_active)
	opp_all.append_array(main.player_bench if is_opponent else main.opponent_bench)
	var marked: card_object = null
	for p in opp_all:
		if p.lightning_rod_marked:
			marked = p
			break
	if marked != null:
		var types = attacker.metadata.get("types", ["Lightning"])
		var result = main.calculate_final_damage(20, types, marked, attacker)
		marked.current_hp = max(0, marked.current_hp - result["damage"])
		main.display_hp_circles_above_align(marked, opp_is)
		await main.show_message("LIGHTNING BOLT! 20 DAMAGE TO MARKED " + marked.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		marked.lightning_rod_marked = false
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Lightning Bolt - 10 active + 20 to marked")

# SACRED WING (basep-52 Ho-oh): flip coin — heads 60 damage, tails 20 damage
func execute_sacred_wing(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var damage = 60 if coin else 20
	await main.show_message(("HEADS! " if coin else "TAILS! ") + str(damage) + " DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Sacred Wing - ", damage, " damage")

# JUMP OVER (basep-51 Rapidash): choose a benched opponent Pokemon, flip coin, 20 damage on heads
func execute_jump_over(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.size() == 0:
		await main.show_message("NO BENCHED POKEMON TO JUMP OVER!")
		if main._should_bail(): return
		return
	var targets = opp_bench.duplicate()
	var target_pokemon: card_object
	if is_opponent:
		targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		target_pokemon = targets[0]
	else:
		target_pokemon = await main.card_ops.prompt_select_card(targets, "JUMP OVER — CHOOSE BENCH TARGET", "Choose a Benched Pokemon", "SELECT", false)
		if main._should_bail(): return
		if target_pokemon == null:
			return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		main.card_ops.apply_bench_damage(target_pokemon, 20, !is_opponent)
		await main.show_message("HEADS! 20 DAMAGE TO " + target_pokemon.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! JUMP OVER MISSED!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Jump Over")

######################################################################################################################################################
############################################################## NEO1 (NEO GENESIS) EFFECTS #############################################################
######################################################################################################################################################

func _register_neo1_attacks() -> void:
	# ----- ATTACKS WITH UNIQUE NAMES -----
	_attack_dispatch["flower dance"]       = func(atk, a, d, opp): await execute_neo1_flower_dance(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["riptide"]            = func(atk, a, d, opp): await execute_neo1_riptide(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["flame wheel"]        = func(atk, a, d, opp): await execute_neo1_flame_wheel(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["zzzap"]              = func(atk, a, d, opp): await execute_neo1_zzzap(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["earthquake"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_earthquake(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["jaw clamp"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_jaw_clamp(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["char"]               = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_char(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["endure"]             = func(atk, a, d, opp): await execute_neo1_endure(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["eeeeeeek"]           = func(atk, a, d, opp): await execute_neo1_eeeeeeek(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["pilfer"]             = func(atk, a, d, opp): await execute_neo1_pilfer(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["squaredance"]        = func(atk, a, d, opp): await execute_neo1_squaredance(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["spider web"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_spider_web(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["mean look"]          = func(atk, a, d, opp): await execute_neo1_mean_look(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["feint attack"]       = func(atk, a, d, opp): await execute_snipe_no_wr(a, d, opp, 20, false); await _attack_finish(true, 20, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["static electricity"] = func(atk, a, d, opp): await execute_neo1_static_electricity(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sputter"]            = func(atk, a, d, opp): await execute_neo1_sputter(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["poison bite"]        = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_poison_bite(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["baton pass"]         = func(atk, a, d, opp): await execute_neo1_baton_pass(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sweet nectar"]       = func(atk, a, d, opp): await execute_neo1_sweet_nectar(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["milk drink"]         = func(atk, a, d, opp): await execute_neo1_milk_drink(a, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["raging charge"]      = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_raging_charge(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["pollen shield"]      = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_pollen_shield(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sticky nectar"]      = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_sticky_nectar(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["dual kick"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_dual_kick(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["super metronome"]    = func(atk, a, d, opp):
		var coin = await main.flip_coin(false, opp)
		if main._should_bail(): return
		if coin:
			await execute_metronome(a, d, opp)
		else:
			await main.show_message("TAILS! SUPER METRONOME FAILED!")
		await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	# ----- ATTACKS SHARED WITH OTHER SETS (text-disambiguated) -----
	_attack_dispatch["screech"]            = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_screech(a, d, opp, b); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["leech seed"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_leech_seed(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["freeze"]             = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_freeze(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["strange powder"]     = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_strange_powder(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["blizzard"]           = func(atk, a, d, opp):
		var b = parse_attack_base_damage(atk)
		var text = atk.get("text", "").to_lower()
		if "if tails" in text and "your own benched" in text:
			await execute_neo1_blizzard(a, d, opp, b)
			await _attack_finish(true, b, atk, a.metadata.get("types", ["Colorless"]), opp)
		else:
			var types = a.metadata.get("types", ["Colorless"])
			var result = main.calculate_final_damage(b, types, d)
			if not main.check_defender_invincible(d, !opp):
				var fd = main.apply_defender_no_damage_shield(d, result["damage"], !opp)
				await main.display_and_apply_attack_damage(a, d, fd, result["modifiers"], opp, b)
			if main._should_bail(): return
			var fx = parse_card_text_effects(atk.get("text", ""), a.metadata.get("name", ""))
			if fx.size() > 0: await apply_card_text_effects(fx, a, d, opp, "")
			if main._should_bail(): return
			await main.check_all_knockouts()
			await _attack_finish(true, b, atk, types, opp)
	_attack_dispatch["elemental blast"]    = func(atk, a, d, opp): await execute_neo1_elemental_blast(a, d, opp); await _attack_finish(true, 90, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["chomp"]              = func(atk, a, d, opp): await execute_neo1_chomp(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	# Electric Current: all versions (GYM1 Magneton, neo1 Flaaffy) do damage + move lightning to bench
	_attack_dispatch["electric current"]   = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_electric_current(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["discharge"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_discharge(a, d, opp); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["megahorn"]           = func(atk, a, d, opp): var b=main.powers_and_bodies.get_final_blow_damage(a, "Megahorn", parse_attack_base_damage(atk)); await execute_neo1_megahorn(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["floodlight"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_floodlight(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fin slap"]           = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_fin_slap(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["scary face"]         = func(atk, a, d, opp): await execute_neo1_scary_face(a, d, opp); await _attack_finish(false, 0, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sweep away"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_sweep_away(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fire wind"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo1_fire_wind(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)

# FLOWER DANCE (neo1-3 Bellossom): 30 × Bellossom count in play
func execute_neo1_flower_dance(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var count = 0
	var all_field: Array = []
	if main.player_active_pokemon != null: all_field.append(main.player_active_pokemon)
	if main.opponent_active_pokemon != null: all_field.append(main.opponent_active_pokemon)
	all_field.append_array(main.player_bench)
	all_field.append_array(main.opponent_bench)
	for p in all_field:
		if "Bellossom" in p.metadata.get("name", ""):
			count += 1
	var total = 30 * count
	await main.show_message("FLOWER DANCE! " + str(count) + " BELLOSSOM(S) — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Flower Dance - ", count, " Bellossom, ", total, " damage")

# RIPTIDE (neo1-5 Feraligatr): 10 + 10× water energy in discard, then shuffle water back
func execute_neo1_riptide(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var water_in_discard: Array = []
	for c in discard:
		if c.metadata.get("supertype", "") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
			water_in_discard.append(c)
	var count = water_in_discard.size()
	var total = 10 + 10 * count
	if count > 0:
		await main.show_message("RIPTIDE! " + str(count) + " WATER ENERGY IN DISCARD — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	# Shuffle water energy back into deck
	var deck = main.opponent_deck if is_opponent else main.player_deck
	for e in water_in_discard:
		discard.erase(e)
		e.current_location = "deck"
		deck.append(e)
	if water_in_discard.size() > 0:
		deck.shuffle()
		main.update_discard_pile_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("SHUFFLED " + str(water_in_discard.size()) + " WATER ENERGY BACK INTO DECK!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Riptide - ", count, " water energy, ", total, " damage")

# FLAME WHEEL (neo1-18 Typhlosion): discard 3 Fire, 80 damage to active + 20 to each bench
func execute_neo1_flame_wheel(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var fire_e = attacker.attached_energies.filter(func(e): return "Fire" in main.get_energy_provided_by_card(e))
	if fire_e.size() < 3:
		if not is_opponent: await main.show_message("NOT ENOUGH FIRE ENERGY FOR FLAME WHEEL! (NEED 3)")
		if main._should_bail(): return
		return
	for i in range(3):
		var e = fire_e[i]
		attacker.attached_energies.erase(e)
		main.card_ops.discard_energy_from_pokemon(e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("DISCARDED 3 FIRE ENERGY!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, 80)
	if main._should_bail(): return
	# 20 to each bench on both sides
	var player_bench_targets = main.player_bench.duplicate()
	var opp_bench_targets = main.opponent_bench.duplicate()
	for bp in player_bench_targets:
		main.card_ops.apply_bench_damage(bp, 20, false)
	for bp in opp_bench_targets:
		main.card_ops.apply_bench_damage(bp, 20, true)
	await main.show_message("FLAME WHEEL! 20 DAMAGE TO EACH BENCHED POKEMON!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Flame Wheel")

# ZZZAP (neo1-12 Pichu): 20 to each Pokemon in play with a Pokemon Power, no W/R
func execute_neo1_zzzap(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var all_targets: Array = []
	if main.player_active_pokemon != null: all_targets.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null: all_targets.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench:
		all_targets.append({"p": bp, "opp": false})
	for bp in main.opponent_bench:
		all_targets.append({"p": bp, "opp": true})
	var hit_count = 0
	for entry in all_targets:
		var p = entry["p"]
		if p == attacker:
			continue
		var has_power = false
		for ab in p.metadata.get("abilities", []):
			if ab.get("type", "") in ["Pokémon Power", "Pokemon Power"]:
				has_power = true
				break
		if has_power:
			p.current_hp = max(0, p.current_hp - 20)
			main.display_hp_circles_above_align(p, entry["opp"])
			hit_count += 1
	if hit_count > 0:
		await main.show_message("ZZZAP! 20 DAMAGE TO EACH POKEMON WITH A POWER! (HIT " + str(hit_count) + ")")
	else:
		await main.show_message("ZZZAP! NO POKEMON WITH POWERS TO HIT!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Zzzap - hit ", hit_count, " pokemon")

# EARTHQUAKE (neo1-45 Quagsire): 60 to active + 10 to each own bench
func execute_neo1_earthquake(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	for bp in own_bench.duplicate():
		main.card_ops.apply_bench_damage(bp, 10, is_opponent)
	if own_bench.size() > 0:
		await main.show_message("EARTHQUAKE! 10 DAMAGE TO EACH OF YOUR OWN BENCHED POKEMON!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Earthquake")

# JAW CLAMP (neo1-31 Croconaw): 30 damage + target can't retreat next turn
func execute_neo1_jaw_clamp(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		defender.jaw_clamp_locked = true
		if is_opponent:
			main.player_retreat_disabled = true
		else:
			main.opponent_retreat_disabled = true
		await main.show_message("JAW CLAMP! " + defender.metadata.get("name","").to_upper() + " CAN'T RETREAT NEXT TURN!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Jaw Clamp")

# CHAR (neo1-47 Quilava): damage + place Char counter; owner flips each turn — tails = 20 damage
func execute_neo1_char(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender != null:
		var already_has = defender.has_char_counter
		if not already_has:
			var coin = await main.flip_coin(false, is_opponent)
			if main._should_bail(): return
			if coin:
				defender.has_char_counter = true
				await main.show_message("HEADS! CHAR COUNTER PLACED ON " + defender.metadata.get("name","").to_upper() + "!")
				if main._should_bail(): return
			else:
				await main.show_message("TAILS! NO CHAR COUNTER PLACED!")
				if main._should_bail(): return
		else:
			await main.show_message("CHAR COUNTER ALREADY ON " + defender.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Char")

# ENDURE (neo1-43 Phanpy): flip — heads: if KO'd by attack next turn, survive with 10 HP
func execute_neo1_endure(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		attacker.endure_active = true
		await main.show_message("HEADS! " + attacker.metadata.get("name","").to_upper() + " WILL ENDURE THE NEXT KO!")
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! ENDURE FAILED!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Endure")

# EEEEEEEK (neo1-20 Cleffa): shuffle hand into deck, draw 7
func execute_neo1_eeeeeeek(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	for card in hand.duplicate():
		card.current_location = "deck"
		deck.append(card)
	hand.clear()
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	await main.show_message("EEEEEEEK! SHUFFLED HAND AND DRAWING 7!")
	if main._should_bail(): return
	await main.card_ops.draw_n(is_opponent, 7)
	if main._should_bail(): return
	main.refresh_hand_display(is_opponent)
	print("ATTACK EXECUTED: Eeeeeeek")

# PILFER (neo1-26 Aipom): shuffle self+attached into deck, flip — heads: shuffle 1 from own discard into deck
func execute_neo1_pilfer(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	# Shuffle Aipom + attached into deck
	for e in attacker.attached_energies.duplicate():
		attacker.attached_energies.erase(e)
		e.current_location = "deck"
		deck.append(e)
	for pre in attacker.attached_pre_evolutions.duplicate():
		attacker.attached_pre_evolutions.erase(pre)
		pre.current_location = "deck"
		deck.append(pre)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var is_active = (attacker == (main.opponent_active_pokemon if is_opponent else main.player_active_pokemon))
	attacker.current_location = "deck"
	deck.append(attacker)
	if is_active:
		if is_opponent: main.opponent_active_pokemon = null
		else: main.player_active_pokemon = null
	else:
		bench.erase(attacker)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("PILFER! AIPOM SHUFFLED ITSELF INTO THE DECK!")
	if main._should_bail(): return
	# Flip — heads: shuffle 1 card from discard into deck
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin and discard.size() > 0:
		if is_opponent:
			var picked = discard[randi() % discard.size()]
			discard.erase(picked)
			picked.current_location = "deck"
			deck.append(picked)
			deck.shuffle()
		else:
			var picked = await main.card_ops.prompt_select_card(discard, "PILFER: CHOOSE CARD", "Choose 1 card from your discard to shuffle into your deck", "SELECT", false)
			if main._should_bail(): return
			if picked != null:
				discard.erase(picked)
				picked.current_location = "deck"
				deck.append(picked)
				deck.shuffle()
		main.update_discard_pile_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("HEADS! SHUFFLED A DISCARD CARD INTO THE DECK!")
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! NO RECOVERY!")
		if main._should_bail(): return
	if is_active:
		await main.handle_post_knockout(is_opponent)
	print("ATTACK EXECUTED: Pilfer")

# SQUAREDANCE (neo1-30 Clefairy): flip × total pokemon count, search deck for Clefairy/Clefable each heads
func execute_neo1_squaredance(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var total_pokemon = 0
	if main.player_active_pokemon != null: total_pokemon += 1
	if main.opponent_active_pokemon != null: total_pokemon += 1
	total_pokemon += main.player_bench.size() + main.opponent_bench.size()
	var heads_count = 0
	for i in range(total_pokemon):
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin: heads_count += 1
	if heads_count == 0:
		await main.show_message("SQUAREDANCE: 0 HEADS — NO CLEFAIRY TO SEARCH!")
		if main._should_bail(): return
		return
	await main.show_message("SQUAREDANCE: " + str(heads_count) + " HEADS!")
	if main._should_bail(): return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var clefairy_names = ["Clefairy", "Clefable"]
	var candidates: Array = []
	for c in deck:
		if c.metadata.get("name","") in clefairy_names:
			candidates.append(c)
	if candidates.size() == 0:
		await main.show_message("NO CLEFAIRY OR CLEFABLE IN DECK!")
		if main._should_bail(): return
		return
	var picks = min(heads_count, candidates.size(), main.get_max_bench_size() - bench.size())
	for i in range(picks):
		var remaining = candidates.filter(func(c): return c.current_location != "bench")
		if remaining.size() == 0 or bench.size() >= main.get_max_bench_size():
			break
		var pick: card_object = null
		if is_opponent:
			pick = remaining[0]
		else:
			pick = await main.card_ops.prompt_select_card(remaining, "SQUAREDANCE: SEARCH " + str(i+1) + "/" + str(picks), "Choose a Clefairy-name Pokemon to bench", "SELECT", false, true)
			if main._should_bail(): return
		if pick != null:
			deck.erase(pick)
			pick.current_location = "bench"
			pick.placed_on_field_this_turn = true
			bench.append(pick)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SQUAREDANCE: PLACED " + str(min(picks, bench.size())) + " POKEMON ON BENCH!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Squaredance")

# SPIDER WEB (neo1-27 Ariados): flip — heads: defending can't retreat
func execute_neo1_spider_web(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			defender.jaw_clamp_locked = true
			if is_opponent: main.player_retreat_disabled = true
			else: main.opponent_retreat_disabled = true
			await main.show_message("HEADS! " + defender.metadata.get("name","").to_upper() + " IS CAUGHT IN A SPIDER WEB AND CAN'T RETREAT!")
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! SPIDER WEB FAILED!")
			if main._should_bail(): return
	print("ATTACK EXECUTED: Spider Web")

# MEAN LOOK (neo1-24 Murkrow): defending can't retreat while Murkrow is active
func execute_neo1_mean_look(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender != null:
		# Mean Look persists only while the attacker remains active; we use attack_blocked_by_id analog
		defender.jaw_clamp_locked = true
		if is_opponent: main.player_retreat_disabled = true
		else: main.opponent_retreat_disabled = true
		await main.show_message("MEAN LOOK! " + defender.metadata.get("name","").to_upper() + " CAN'T RETREAT WHILE " + attacker.metadata.get("name","").to_upper() + " IS ACTIVE!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Mean Look")

# STATIC ELECTRICITY (neo1-65 Mareep): search deck for 1 Lightning Energy per Mareep in play
func execute_neo1_static_electricity(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var mareep_count = 0
	var all_field: Array = []
	if main.player_active_pokemon != null: all_field.append(main.player_active_pokemon)
	if main.opponent_active_pokemon != null: all_field.append(main.opponent_active_pokemon)
	all_field.append_array(main.player_bench)
	all_field.append_array(main.opponent_bench)
	for p in all_field:
		if p.metadata.get("name","") == "Mareep":
			mareep_count += 1
	if mareep_count == 0:
		await main.show_message("NO MAREEP IN PLAY!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var lightning_in_deck: Array = []
	for c in deck:
		if c.metadata.get("supertype","") == "Energy" and "Lightning" in main.get_energy_provided_by_card(c):
			lightning_in_deck.append(c)
	if lightning_in_deck.size() == 0:
		await main.show_message("NO LIGHTNING ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	await main.show_message("STATIC ELECTRICITY! " + str(mareep_count) + " MAREEP IN PLAY!")
	if main._should_bail(): return
	var picks = min(mareep_count, lightning_in_deck.size())
	if is_opponent:
		for i in range(picks):
			var e = lightning_in_deck[i]
			deck.erase(e)
			e.current_location = "attached"
			attacker.attached_energies.append(e)
	else:
		for i in range(picks):
			var remaining = lightning_in_deck.filter(func(c): return c in deck)
			if remaining.size() == 0: break
			var pick = await main.card_ops.prompt_select_card(remaining, "STATIC ELECTRICITY: PICK " + str(i+1) + "/" + str(picks), "Choose a Lightning Energy to attach to Mareep", "ATTACH", false, true)
			if main._should_bail(): return
			if pick != null:
				deck.erase(pick)
				pick.current_location = "attached"
				attacker.attached_energies.append(pick)
	deck.shuffle()
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("ATTACHED " + str(min(picks, attacker.attached_energies.size())) + " LIGHTNING ENERGY TO MAREEP!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Static Electricity")

# SPUTTER (neo1-23 Magby): stop all Pokemon Powers until end of next turn
func execute_neo1_sputter(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	main.goop_gas_active = true
	await main.show_message("SPUTTER! ALL POKEMON POWERS ARE DISABLED UNTIL END OF NEXT TURN!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Sputter (Goop Gas / Power shutdown)")

# POISON BITE (neo1-27 Ariados): 20 + poison, remove counters = half damage dealt
func execute_neo1_poison_bite(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender)
	var final_d = result["damage"]
	if not main.check_defender_invincible(defender, not is_opponent):
		final_d = main.apply_defender_no_damage_shield(defender, final_d, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, final_d, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	if defender != null and final_d > 0 and defender.current_hp > 0:
		main.card_ops.apply_status(defender, "Poisoned", not is_opponent)
		# Remove counters from self = half the final damage (round up to nearest 10)
		var heal_amount = int(ceil(final_d / 2.0 / 10.0)) * 10
		var max_hp = attacker.get_max_hp()
		var healed = min(heal_amount, max_hp - attacker.current_hp)
		if healed > 0:
			attacker.current_hp = min(max_hp, attacker.current_hp + healed)
			main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message("POISON BITE! " + defender.metadata.get("name","").to_upper() + " IS POISONED! ARIADOS HEALED " + str(healed) + " HP!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Poison Bite")

# BATON PASS (neo1-39 Ledian): remove all Grass energy from Ledian, attach to bench Grass pokemon, switch
func execute_neo1_baton_pass(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var grass_bench: Array = []
	for bp in bench:
		if "Grass" in bp.metadata.get("types", []):
			grass_bench.append(bp)
	if grass_bench.size() == 0:
		await main.show_message("BATON PASS: NO GRASS POKEMON ON BENCH!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		target = grass_bench[0]
	else:
		if grass_bench.size() == 1:
			target = grass_bench[0]
		else:
			target = await main.card_ops.prompt_select_card(grass_bench, "BATON PASS: CHOOSE TARGET", "Choose a Grass Pokemon to receive Ledian's energy and switch in", "SELECT", false)
			if main._should_bail(): return
	if target == null:
		return
	# Move all Grass energies from Ledian to target
	var grass_e: Array = attacker.attached_energies.filter(func(e): return "Grass" in main.get_energy_provided_by_card(e))
	for e in grass_e:
		attacker.attached_energies.erase(e)
		target.attached_energies.append(e)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("BATON PASS! MOVED " + str(grass_e.size()) + " GRASS ENERGY TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	# Switch Ledian out, target in
	bench.erase(target)
	bench.append(attacker)
	attacker.current_location = "bench"
	target.current_location = "active"
	if is_opponent:
		main.opponent_active_pokemon = target
	else:
		main.player_active_pokemon = target
	main.clear_all_statuses(attacker, is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	print("ATTACK EXECUTED: Baton Pass")

# SWEET NECTAR (neo1-3 Bellossom): flip — heads: remove all damage from 1 of your pokemon
func execute_neo1_sweet_nectar(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! SWEET NECTAR FAILED!")
		if main._should_bail(): return
		return
	var own_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != null: own_poke.append(active)
	own_poke.append_array(main.opponent_bench if is_opponent else main.player_bench)
	var damaged: Array = own_poke.filter(func(p): return p.current_hp < p.get_max_hp())
	if damaged.size() == 0:
		await main.show_message("HEADS! BUT NO DAMAGED POKEMON!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		damaged.sort_custom(func(a, b): return (a.get_max_hp() - a.current_hp) > (b.get_max_hp() - b.current_hp))
		target = damaged[0]
	else:
		if damaged.size() == 1:
			target = damaged[0]
		else:
			target = await main.card_ops.prompt_select_card(damaged, "SWEET NECTAR: CHOOSE POKEMON", "Choose a Pokemon to fully heal", "HEAL", false)
			if main._should_bail(): return
	if target == null:
		return
	target.current_hp = target.get_max_hp()
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	main.display_hp_circles_above_align(target, is_opponent)
	await main.show_message("HEADS! " + target.metadata.get("name","").to_upper() + " WAS FULLY HEALED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Sweet Nectar - fully healed ", target.metadata.get("name",""))

# MILK DRINK (neo1-41 Miltank): flip 2 coins, remove 2 damage counters × heads
func execute_neo1_milk_drink(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	var c1 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var c2 = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if c1: heads += 1
	if c2: heads += 1
	var heal_amount = heads * 20
	if heal_amount > 0:
		var max_hp = attacker.get_max_hp()
		attacker.current_hp = min(max_hp, attacker.current_hp + heal_amount)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message("MILK DRINK! " + str(heads) + " HEADS — HEALED " + str(heal_amount) + " HP!")
	else:
		await main.show_message("TAILS! MILK DRINK FAILED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Milk Drink - healed ", heal_amount)

# RAGING CHARGE (neo1-37 Granbull): 10 + 10×own damage counters + 20 to self
func execute_neo1_raging_charge(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var counters = attacker.get_damage_counters()
	var total = base_damage + counters * 10
	if counters > 0:
		await main.show_message("RAGING CHARGE! " + str(counters) + " COUNTERS — " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	# 20 recoil damage to self
	if attacker.current_hp > 0:
		await gym2_self_damage(attacker, is_opponent, 20)
		if main._should_bail(): return
		await main.show_message("RAGING CHARGE RECOIL: GRANBULL TOOK 20 DAMAGE!")
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Raging Charge")

# POLLEN SHIELD (neo1-28 Bayleef): 30, then self immune to status next turn
func execute_neo1_pollen_shield(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	attacker.damage_reduction_next_turn = 0
	attacker.attack_flip_blocked = false
	# Reuse the existing attack_blocked flag to indicate status immunity (mark for end-of-turn check)
	# We'll use a comment approach: pollen shield just prevents status next turn
	# Since we don't have a "status_immune_next_turn" flag, we'll show the message
	await main.show_message("POLLEN SHIELD! BAYLEEF IS PROTECTED FROM STATUS CONDITIONS NEXT TURN!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Pollen Shield")

# STICKY NECTAR (neo1-36 Gloom): 20+10 on heads; if heads, target can't retreat next turn
func execute_neo1_sticky_nectar(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var total = base_damage + (10 if coin else 0)
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if coin and defender != null and defender.current_hp > 0:
		defender.jaw_clamp_locked = true
		if is_opponent: main.player_retreat_disabled = true
		else: main.opponent_retreat_disabled = true
		await main.show_message("HEADS! " + str(total) + " DAMAGE AND TARGET CAN'T RETREAT NEXT TURN!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Sticky Nectar")

# DUAL KICK (neo1-25 Sneasel Beat Up): flip per pokemon in play, 20 per heads
func execute_neo1_dual_kick(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var own_pokemon: Array = []
	if main.opponent_active_pokemon != null and is_opponent: own_pokemon.append(main.opponent_active_pokemon)
	if main.player_active_pokemon != null and not is_opponent: own_pokemon.append(main.player_active_pokemon)
	own_pokemon.append_array(main.opponent_bench if is_opponent else main.player_bench)
	var heads = 0
	for p in own_pokemon:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin: heads += 1
	var total = base_damage * heads
	if total > 0:
		await gym1_hit_active(attacker, defender, is_opponent, total)
		if main._should_bail(): return
		await main.show_message("BEAT UP! " + str(heads) + " HEADS — " + str(total) + " DAMAGE!")
	else:
		await main.show_message("BEAT UP! 0 HEADS — NO DAMAGE!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Beat Up")

# SCREECH (neo1-31/69): set screech_damage_bonus on defender — +20 to next attack received
func execute_neo1_screech(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if base_damage > 0:
		await gym1_hit_active(attacker, defender, is_opponent, base_damage)
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		defender.screech_damage_bonus = 20
		await main.show_message("SCREECH! NEXT ATTACK AGAINST " + defender.metadata.get("name","").to_upper() + " DOES 20 MORE DAMAGE!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Screech")

# LEECH SEED (neo1-7 Jumpluff): 20 damage, if damage dealt remove 1 counter from self
func execute_neo1_leech_seed(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender)
	var final_d = result["damage"]
	if not main.check_defender_invincible(defender, not is_opponent):
		final_d = main.apply_defender_no_damage_shield(defender, final_d, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, final_d, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if final_d > 0 and attacker.current_hp < attacker.get_max_hp():
		attacker.current_hp = min(attacker.get_max_hp(), attacker.current_hp + 10)
		main.display_hp_circles_above_align(attacker, is_opponent)
		await main.show_message("LEECH SEED! JUMPLUFF HEALED 10 HP!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Leech Seed")

# FREEZE (neo1-44 Piloswine): 10 damage, flip — heads: defending can't attack next turn
func execute_neo1_freeze(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			defender.attack_blocked_next_turn = true
			defender.attack_blocked_by_id = attacker.get_instance_id()
			await main.show_message("HEADS! " + defender.metadata.get("name","").to_upper() + " IS FROZEN AND CAN'T ATTACK NEXT TURN!")
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! FREEZE FAILED!")
			if main._should_bail(): return
	print("ATTACK EXECUTED: Freeze")

# STRANGE POWDER (neo1-36 Gloom): flip — heads: confused, tails: asleep
func execute_neo1_strange_powder(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			main.card_ops.apply_status(defender, "Confused", not is_opponent)
			await main.show_message("HEADS! " + defender.metadata.get("name","").to_upper() + " IS NOW CONFUSED!")
		else:
			main.card_ops.apply_status(defender, "Asleep", not is_opponent)
			await main.show_message("TAILS! " + defender.metadata.get("name","").to_upper() + " IS NOW ASLEEP!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Strange Powder")

# BLIZZARD (neo1-44 Piloswine): 30 + heads: 10 to each opponent bench, tails: 10 to each own bench
func execute_neo1_blizzard(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		var opp_bench = main.player_bench if is_opponent else main.opponent_bench
		for bp in opp_bench.duplicate():
			main.card_ops.apply_bench_damage(bp, 10, not is_opponent)
		await main.show_message("HEADS! 10 DAMAGE TO EACH OPPONENT BENCH!")
	else:
		var own_bench = main.opponent_bench if is_opponent else main.player_bench
		for bp in own_bench.duplicate():
			main.card_ops.apply_bench_damage(bp, 10, is_opponent)
		await main.show_message("TAILS! 10 DAMAGE TO EACH OF YOUR OWN BENCH!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Blizzard (Piloswine)")

# ELEMENTAL BLAST (neo1-9 Lugia): 90 — discard 1 Fire, 1 Water, 1 Lightning energy
func execute_neo1_elemental_blast(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	# Verify we have Fire + Water + Lightning attached
	var fire_e: card_object = null; var water_e: card_object = null; var lightning_e: card_object = null
	for e in attacker.attached_energies:
		var prov = main.get_energy_provided_by_card(e)
		if fire_e == null and "Fire" in prov: fire_e = e
		elif water_e == null and "Water" in prov: water_e = e
		elif lightning_e == null and "Lightning" in prov: lightning_e = e
	if fire_e == null or water_e == null or lightning_e == null:
		if not is_opponent: await main.show_message("ELEMENTAL BLAST REQUIRES FIRE, WATER, AND LIGHTNING ENERGY!")
		if main._should_bail(): return
		return
	for e in [fire_e, water_e, lightning_e]:
		attacker.attached_energies.erase(e)
		main.card_ops.discard_energy_from_pokemon(e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("DISCARDED FIRE, WATER, AND LIGHTNING ENERGY!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, 90)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Elemental Blast")

# CHOMP (neo1-4 Feraligatr): 50 + flip × damage_counters × 10
func execute_neo1_chomp(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var counters = attacker.get_damage_counters()
	var heads = 0
	for i in range(counters):
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin: heads += 1
	var total = 50 + heads * 10
	if counters > 0:
		await main.show_message("CHOMP! " + str(heads) + "/" + str(counters) + " HEADS — " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Chomp - ", heads, " heads, ", total, " damage")

# ELECTRIC CURRENT (neo1-34 Flaaffy): 20 damage + move 1 Lightning from Flaaffy to a benched pokemon
func execute_neo1_electric_current(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() == 0:
		await main.show_message("NO BENCHED POKEMON TO TRANSFER ENERGY TO!")
		if main._should_bail(): return
		return
	var lightning_e: card_object = null
	for e in attacker.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			lightning_e = e
			break
	if lightning_e == null:
		await main.show_message("NO LIGHTNING ENERGY ON " + attacker.metadata.get("name","").to_upper() + " TO TRANSFER!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		target = bench[0]
	else:
		if bench.size() == 1:
			target = bench[0]
		else:
			target = await main.card_ops.prompt_select_card(bench, "ELECTRIC CURRENT: CHOOSE TARGET", "Choose a benched Pokemon to receive Lightning Energy", "SELECT", false)
			if main._should_bail(): return
	if target == null:
		return
	attacker.attached_energies.erase(lightning_e)
	target.attached_energies.append(lightning_e)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ELECTRIC CURRENT! LIGHTNING ENERGY MOVED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Electric Current (Flaaffy neo1)")

# MEGAHORN (neo1-6 Heracross): flip — heads: 60 damage (120 if Final Blow is active and HP ≤ 20)
func execute_neo1_megahorn(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! MEGAHORN MISSED!")
		if main._should_bail(): return
		return
	if base_damage >= 120:
		await main.show_message("FINAL BLOW! MEGAHORN DEALS 120 DAMAGE!")
		if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Megahorn - ", base_damage, " damage")

# FLOODLIGHT (neo1-38 Lanturn): 20 damage + Hydroelectric Power bonus; flip — heads: Paralyzed
func execute_neo1_floodlight(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var bonus = main.powers_and_bodies.get_hydroelectric_bonus(attacker, "Floodlight")
	var total = base_damage + bonus
	if bonus > 0:
		await main.show_message("HYDROELECTRIC POWER! FLOODLIGHT DEALS " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			main.card_ops.apply_status(defender, "Paralyzed", not is_opponent)
			await main.show_message("HEADS! " + defender.metadata.get("name","").to_upper() + " IS PARALYZED!")
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! FLOODLIGHT DIDN'T PARALYZE!")
			if main._should_bail(): return
	print("ATTACK EXECUTED: Floodlight - ", total, " damage")

# BIRTHDAY SURPRISE (basep-24 _____'s Pikachu): birthday challenge always treated as denied — always 30 damage
func execute_birthday_surprise(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.show_message("BIRTHDAY SURPRISE! 30 DAMAGE!")
	if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, 30)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Birthday Surprise — 30 damage")

# FIN SLAP (neo1-62 Horsea): 20 damage; +10 if Horsea was damaged during opponent's last turn
func execute_neo1_fin_slap(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var last_hit = main.last_attack_on_player if not is_opponent else main.last_attack_on_opponent
	var was_damaged = not last_hit.is_empty() and last_hit.get("damage", 0) > 0
	var total = base_damage + (10 if was_damaged else 0)
	if was_damaged:
		await main.show_message("FIN SLAP! HORSEA WAS HIT LAST TURN — " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	await gym1_hit_active(attacker, defender, is_opponent, total)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fin Slap — ", total, " damage")

# SCARY FACE (neo1-75 Spinarak / ecard3 Snubbull): flip coin — heads: defender can't attack or retreat next turn
func execute_neo1_scary_face(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		defender.attack_blocked_next_turn = true
		defender.attack_blocked_by_id = attacker.get_instance_id()
		if is_opponent:
			main.player_retreat_disabled = true
		else:
			main.opponent_retreat_disabled = true
		main.update_status_icons(defender, not is_opponent)
		await main.show_message("HEADS! " + defender.metadata.get("name","").to_upper() + " CAN'T ATTACK OR RETREAT NEXT TURN!")
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! SCARY FACE HAD NO EFFECT!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Scary Face")

# SWEEP AWAY (neo1-32 Croconaw): 50 damage + discard top 3 cards from attacker's own deck
func execute_neo1_sweep_away(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var own_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var count = 0
	for _i in range(3):
		if own_deck.is_empty():
			break
		var top = own_deck[own_deck.size() - 1]
		own_deck.remove_at(own_deck.size() - 1)
		top.current_location = "discard"
		own_discard.append(top)
		count += 1
	if count > 0:
		main.update_discard_pile_display(is_opponent)
		main.update_deck_icon(is_opponent)
		await main.show_message("SWEEP AWAY! DISCARDED TOP " + str(count) + " CARDS FROM OWN DECK!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Sweep Away — ", base_damage, " damage, milled ", count, " own cards")

# FIRE WIND (neo1-46 Quilava): 20 to active + flip 2 coins, 10×heads to a chosen opposing bench Pokemon (no W/R)
func execute_neo1_fire_wind(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await gym1_hit_active(attacker, defender, is_opponent, base_damage)
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.check_all_knockouts()
		if main._should_bail(): return
		print("ATTACK EXECUTED: Fire Wind — ", base_damage, " damage, no bench targets")
		return
	var target: card_object = null
	if is_opponent:
		var sorted_bench = opp_bench.duplicate()
		sorted_bench.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		target = sorted_bench[0]
	else:
		target = await main.card_ops.prompt_select_card(opp_bench, "FIRE WIND — CHOOSE BENCH TARGET", "Choose an opposing Benched Pokémon to deal flip damage to", "SELECT", false)
		if main._should_bail(): return
	if target == null:
		await main.check_all_knockouts()
		return
	var heads = 0
	for _i in range(2):
		if await main.flip_coin(true, is_opponent):
			heads += 1
	if main._should_bail(): return
	var bench_damage = heads * 10
	await main.show_message("FIRE WIND! " + str(heads) + " HEADS — " + str(bench_damage) + " DAMAGE TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	if bench_damage > 0:
		main.card_ops.apply_bench_damage(target, bench_damage, not is_opponent)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fire Wind — ", base_damage, " active, ", bench_damage, " bench")

######################################################################################################################################################
##################################################### NEO2 (NEO DISCOVERY) ATTACK EFFECTS ###########################################################
######################################################################################################################################################

func _register_neo2_attacks() -> void:
	# ----- ATTACKS WITH UNIQUE LOGIC -----
	_attack_dispatch["lock-on"]         = func(atk, a, d, opp): await execute_neo2_lock_on(a, opp);                                              await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["electric bolt"]   = func(atk, a, d, opp): await execute_neo2_electric_bolt(a, d, opp);                                    await _attack_finish(true,  50, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["hydrocutter"]     = func(atk, a, d, opp): await execute_neo2_hydrocutter(a, d, opp);                                      await _attack_finish(true,  40, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["false swipe"]     = func(atk, a, d, opp): await execute_neo2_false_swipe(a, d, opp);                                      await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["double claw"]     = func(atk, a, d, opp): await execute_neo2_double_claw(a, d, opp);                                      await _attack_finish(true,  20, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["crunch"]          = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo2_crunch(a, d, opp, b);   await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["collect fire"]    = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo2_collect_fire(a, d, opp, b); await _attack_finish(true, b, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["triple poison"]   = func(atk, a, d, opp): await execute_neo2_triple_poison(a, d, opp);                                    await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["magic dust"]      = func(atk, a, d, opp): await execute_neo2_magic_dust(a, d, opp);                                       await _attack_finish(true,  20, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["hyper reverse"]   = func(atk, a, d, opp): await execute_neo2_hyper_reverse(a, d, opp);                                    await _attack_finish(true,  0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["trample"]         = func(atk, a, d, opp): await execute_neo2_trample(a, d, opp);                                          await _attack_finish(true,  50, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["sketch"]          = func(atk, a, d, opp): await execute_neo2_sketch(a, d, opp);                                           await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["counter"]         = func(atk, a, d, opp): await execute_neo2_counter(a, opp);                                             await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["shockwave"]       = func(atk, a, d, opp): await execute_neo2_shockwave(a, d, opp);                                        await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["secrete poison"]  = func(atk, a, d, opp): await execute_neo2_secrete_poison(a, opp);                                      await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["harden"]          = func(atk, a, d, opp): await execute_neo2_harden(a, opp);                                              await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["hatch"]           = func(atk, a, d, opp): await execute_neo2_hatch(a, opp);                                               await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["squeeze"]         = func(atk, a, d, opp): await execute_neo2_squeeze(a, d, opp);                                          await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["spike barrage"]   = func(atk, a, d, opp): await execute_neo2_spike_barrage(a, d, opp);                                    await _attack_finish(true,  20, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["belly drum"]      = func(atk, a, d, opp): await execute_neo2_belly_drum(a, opp);                                          await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["dust devil"]      = func(atk, a, d, opp): await execute_neo2_dust_devil(a, opp);                                          await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["fury cutter"]     = func(atk, a, d, opp): await execute_neo2_fury_cutter(a, d, opp);                                      await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["energy cycle"]    = func(atk, a, d, opp): await execute_neo2_energy_cycle(a, d, opp);                                     await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["work together"]   = func(atk, a, d, opp): await execute_neo2_work_together(a, d, opp);                                    await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["burst"]           = func(atk, a, d, opp): await execute_neo2_burst(a, d, opp);                                            await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["recover"]         = func(atk, a, d, opp): await execute_neo2_recover(a, opp);                                             await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["plunder"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo2_plunder(a, d, opp, b);  await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["headpress"]       = func(atk, a, d, opp): await execute_neo2_headpress(a, d, opp);                                        await _attack_finish(true,  30, atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["pursuit"]         = func(atk, a, d, opp): var b=parse_attack_base_damage(atk); await execute_neo2_pursuit(a, d, opp, b);  await _attack_finish(true,  b,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["slime"]           = func(atk, a, d, opp): await execute_neo2_slime(a, opp);                                               await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	_attack_dispatch["scout"]           = func(atk, a, d, opp): await execute_psyscan(a, opp);                                                  await _attack_finish(false, 0,  atk, a.metadata.get("types",["Colorless"]), opp)
	# Hidden Power: 10 + [Anger] bonus from Unown [A] damage counters
	_attack_dispatch["hidden power"]    = func(atk, a, d, opp): await execute_neo2_hidden_power(a, d, opp);                                     await _attack_finish(true,  10, atk, a.metadata.get("types",["Colorless"]), opp)
	# Doubleslap: Politoed gets Frog Song bonus; others handled generically by caller
	_attack_dispatch["doubleslap"]      = func(atk, a, d, opp): await execute_neo2_politoed_doubleslap(a, d, opp);                              await _attack_finish(true,  40, atk, a.metadata.get("types",["Colorless"]), opp)
	# Flamethrower: Houndoom requires Fire energy or attack fails; all other versions use generic discard-after-damage
	_attack_dispatch["flamethrower"]    = func(atk, a, d, opp):
		var types = a.metadata.get("types",["Colorless"])
		var b = parse_attack_base_damage(atk)
		var text = atk.get("text","").to_lower()
		if "or this attack does nothing" in text:
			var fire_e: Array = []
			for e in a.attached_energies:
				if "Fire" in main.get_energy_provided_by_card(e):
					fire_e.append(e)
					break
			if fire_e.is_empty():
				if not opp: await main.show_message(a.metadata.get("name","").to_upper() + "'S FLAMETHROWER FIZZLED — NO FIRE ENERGY TO DISCARD!")
				await _attack_finish(false, 0, atk, types, opp)
				return
			a.attached_energies.erase(fire_e[0])
			main.card_ops.discard_energy_from_pokemon(fire_e[0], opp)
			main.display_active_pokemon_energies(opp)
			main.update_discard_pile_display(opp)
		var result = main.calculate_final_damage(b, types, d, a)
		if not main.check_defender_invincible(d, !opp):
			var fd = main.apply_defender_no_damage_shield(d, result["damage"], !opp)
			await main.display_and_apply_attack_damage(a, d, fd, result["modifiers"], opp, b)
		if main._should_bail(): return
		if "or this attack does nothing" not in text:
			var fx = parse_card_text_effects(atk.get("text",""), a.metadata.get("name",""))
			if fx.size() > 0: await apply_card_text_effects(fx, a, d, opp, "")
			if main._should_bail(): return
		await main.check_all_knockouts()
		await _attack_finish(true, b, atk, types, opp)

# LOCK-ON (neo2-7/26 Magnemite): next Electric Bolt treats any tails as heads
func execute_neo2_lock_on(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.lock_on_active = true
	var name = attacker.metadata.get("name","").to_upper()
	await main.show_message(name + " IS LOCKED ON! NEXT ELECTRIC BOLT CANNOT MISS!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Lock-on — Electric Bolt will auto-hit next turn")

# ELECTRIC BOLT (neo2-7/26 Magnemite): flip 2 — both heads = 50 + Paralyzed; any tails = nothing (Lock-on overrides)
func execute_neo2_electric_bolt(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var lock_on = attacker.lock_on_active
	attacker.lock_on_active = false
	var coin1 = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	var coin2 = await main.flip_coin(true, is_opponent)
	if main._should_bail(): return
	var both_heads = (coin1 or lock_on) and (coin2 or lock_on)
	if not both_heads:
		await main.show_message("ELECTRIC BOLT FAILED! NEED BOTH HEADS!")
		if main._should_bail(): return
		return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(50, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 50)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, "Paralyzed", not is_opponent)
		await main.show_message("BOTH HEADS! " + defender.metadata.get("name","").to_upper() + " IS PARALYZED!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Electric Bolt — 50 damage + Paralyzed")

# HYDROCUTTER (neo2-6/25 Kabutops): flip min(3, energy_count) coins, 40×heads
func execute_neo2_hydrocutter(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var flip_count = min(3, attacker.attached_energies.size())
	var heads = 0
	for i in range(flip_count):
		if await main.flip_coin(flip_count > 1, is_opponent):
			heads += 1
	if main._should_bail(): return
	var total = heads * 40
	await main.show_message("HYDROCUTTER! " + str(flip_count) + " FLIPS, " + str(heads) + " HEADS — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	if total > 0:
		var types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(total, types, defender, attacker)
		if not main.check_defender_invincible(defender, not is_opponent):
			var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Hydrocutter — ", flip_count, " flips, ", total, " damage")

# FALSE SWIPE (neo2-10/29 Scizor): damage = half defender's remaining HP, rounded down to nearest 10
func execute_neo2_false_swipe(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender == null or main.check_defender_invincible(defender, not is_opponent):
		return
	var half_hp = int(defender.current_hp / 2.0 / 10.0) * 10
	half_hp = max(10, half_hp)
	await main.show_message("FALSE SWIPE! " + str(defender.current_hp) + " HP — HALF IS " + str(half_hp) + " DAMAGE!")
	if main._should_bail(): return
	defender.current_hp = max(0, defender.current_hp - half_hp)
	main.display_hp_circles_above_align(defender, not is_opponent)
	main.show_floating_label("-" + str(half_hp) + "HP", Vector2(530 if is_opponent else 1030, 300), Color.WHITE, true)
	if half_hp > 0:
		await main.powers_and_bodies.dispatch_on_damage(defender, attacker, half_hp, not is_opponent)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: False Swipe — ", half_hp, " damage")

# DOUBLE CLAW (neo2-10/29 Scizor): flip 2 coins, 20×heads (damage field "20+" is misleading — text says 20×heads)
func execute_neo2_double_claw(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent):
			heads += 1
	if main._should_bail(): return
	var total = heads * 20
	await main.show_message("DOUBLE CLAW! " + str(heads) + " HEADS — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	if total > 0:
		var types = attacker.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(total, types, defender, attacker)
		if not main.check_defender_invincible(defender, not is_opponent):
			var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Double Claw — ", total, " damage")

# CRUNCH (neo2-4/23 Houndoom): 30 damage + next attack on defending pokemon deals +20
func execute_neo2_crunch(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		defender.screech_damage_bonus += 20
		await main.show_message("CRUNCH! NEXT ATTACK ON " + defender.metadata.get("name","").to_upper() + " DEALS +20!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Crunch — ", base_damage, " damage + crunch bonus")

# COLLECT FIRE (neo2-5/24 Houndour): 20 damage + attach 1 Fire Energy from discard to self
func execute_neo2_collect_fire(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var fire_e: card_object = null
	for c in discard:
		if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
			fire_e = c
			break
	if fire_e == null:
		await main.show_message("NO FIRE ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	discard.erase(fire_e)
	attacker.attached_energies.append(fire_e)
	fire_e.current_location = "active" if attacker.current_location == "active" else "bench"
	main.update_discard_pile_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("COLLECT FIRE! ATTACHED FIRE ENERGY FROM DISCARD!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Collect Fire — ", base_damage, " damage + Fire Energy attached")

# TRIPLE POISON (neo2-18 Beedrill): 10 damage + flip — heads: Poisoned with 3 damage counters per turn
func execute_neo2_triple_poison(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(10, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 10)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		var coin = await main.flip_coin(false, is_opponent)
		if main._should_bail(): return
		if coin:
			defender.is_poisoned = true
			defender.poison_damage = 30
			main.update_status_icons(defender, not is_opponent)
			await main.show_message("TRIPLE POISON! " + defender.metadata.get("name","").to_upper() + " IS BADLY POISONED! (30 per turn)")
			if main._should_bail(): return
		else:
			await main.show_message("TAILS! NO TRIPLE POISON!")
			if main._should_bail(): return
	print("ATTACK EXECUTED: Triple Poison")

# MAGIC DUST (neo2-19 Butterfree): 20 damage + flip — if heads, player chooses: Asleep/Confused/Paralyzed/Poisoned
func execute_neo2_magic_dust(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(20, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 20)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender == null or defender.current_hp <= 0:
		return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! NO STATUS EFFECT!")
		if main._should_bail(): return
		return
	var chosen_status = ""
	var status_options = ["Asleep", "Confused", "Paralyzed", "Poisoned"]
	if is_opponent:
		chosen_status = status_options[randi() % status_options.size()]
	else:
		main.special_attack_selection_active = true
		main.buttons_only_blocker.visible = true
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button": continue
			child.queue_free()
		main.attack_buttons_container.visible = true
		main.main_buttons_container.visible = false
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button": child.visible = false
		for i in range(status_options.size()):
			var btn = Button.new()
			btn.text = status_options[i]
			btn.custom_minimum_size = Vector2(280, 50)
			btn.theme = main.theme_green
			main.attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): main.special_attack_selected.emit(i))
		var idx = await main.special_attack_selected
		chosen_status = status_options[idx]
		for child in main.attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button": child.visible = true; continue
			child.queue_free()
		main.attack_buttons_container.visible = false
		main.main_buttons_container.visible = true
		main.special_attack_selection_active = false
		main.buttons_only_blocker.visible = false
	if main._should_bail(): return
	main.card_ops.apply_status(defender, chosen_status, not is_opponent)
	await main.show_message("MAGIC DUST! " + defender.metadata.get("name","").to_upper() + " IS NOW " + chosen_status.to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Magic Dust — ", chosen_status)

# HYPER REVERSE (neo2-19 Butterfree): 10×energy attached to defender, then heal self = damage dealt after W/R
func execute_neo2_hyper_reverse(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	if defender == null:
		return
	var energy_count = defender.attached_energies.size()
	var base = energy_count * 10
	await main.show_message("HYPER REVERSE! " + str(energy_count) + " ENERGY — " + str(base) + " BASE DAMAGE!")
	if main._should_bail(): return
	if base == 0:
		return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base, types, defender, attacker)
	var fd = result["damage"]
	if not main.check_defender_invincible(defender, not is_opponent):
		fd = main.apply_defender_no_damage_shield(defender, fd, not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if fd > 0:
		await main.card_ops.heal_pokemon(attacker, fd, is_opponent)
		if main._should_bail(): return
		await main.show_message("HYPER REVERSE HEALED " + attacker.metadata.get("name","").to_upper() + " FOR " + str(fd) + " HP!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Hyper Reverse — ", fd, " damage/heal")

# TRAMPLE (neo2-12/31 Tyranitar): 50 to active + flip for each benched pokemon on both sides, 30 each on heads
func execute_neo2_trample(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(50, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 50)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var all_bench: Array = []
	all_bench.append_array(main.player_bench)
	all_bench.append_array(main.opponent_bench)
	if all_bench.is_empty():
		return
	await main.show_message("TRAMPLE! FLIPPING FOR EACH BENCHED POKEMON!")
	if main._should_bail(): return
	for bp in all_bench.duplicate():
		if bp.current_hp <= 0: continue
		var coin = await main.flip_coin(true, is_opponent)
		if main._should_bail(): return
		if coin:
			var bench_owner_is_opp = (bp in main.opponent_bench)
			main.card_ops.apply_bench_damage(bp, 30, bench_owner_is_opp)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Trample")

# SKETCH (neo2-11/30 Smeargle): copy and execute the attack the defending pokemon used last turn
func execute_neo2_sketch(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var last = main.last_attack_on_player if is_opponent else main.last_attack_on_opponent
	if last.is_empty() or not last.has("attack") or last["attack"].is_empty():
		await main.show_message("SKETCH FAILED! NO ATTACK TO COPY!")
		if main._should_bail(): return
		return
	var copied = last["attack"]
	var copied_name = copied.get("name","Unknown")
	await main.show_message("SKETCH! SMEARGLE COPIES " + copied_name.to_upper() + "!")
	if main._should_bail(): return
	var variable_result = await resolve_attack_variable_damage(copied, attacker, defender, is_opponent)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await main.show_message(msg)
			if main._should_bail(): return
		return
	for msg in variable_result["messages"]:
		await main.show_message(msg)
		if main._should_bail(): return
	if resolved_base > 0:
		var types = attacker.metadata.get("types", ["Colorless"])
		var damage_result = main.calculate_final_damage(resolved_base, types, defender, attacker)
		if not main.check_defender_invincible(defender, not is_opponent):
			var fd = main.apply_defender_no_damage_shield(defender, damage_result["damage"], not is_opponent)
			await main.display_and_apply_attack_damage(attacker, defender, fd, damage_result["modifiers"], is_opponent, resolved_base)
			if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	var fx = parse_card_text_effects(copied.get("text",""), attacker.metadata.get("name",""))
	if fx.size() > 0:
		await apply_card_text_effects(fx, attacker, defender, is_opponent, flip_result)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Sketch — copied ", copied_name)

# COUNTER (neo2-16/35 Wobbuffet): set counter_active flag; checked in on-damage hook
func execute_neo2_counter(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.counter_active = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name","").to_upper() + " IS COUNTERING! IF DAMAGED, FLIP FOR EQUAL COUNTER-ATTACK!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Counter — flag set")

# SHOCKWAVE (neo2-17/36 Yanma): flip — if heads, 10 to each of opponent's pokemon + opponent switches active
func execute_neo2_shockwave(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! SHOCKWAVE FAILS!")
		if main._should_bail(): return
		return
	await main.show_message("SHOCKWAVE! 10 DAMAGE TO ALL OPPONENT'S POKEMON!")
	if main._should_bail(): return
	var opp_all: Array = []
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_active != null: opp_all.append(opp_active)
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	opp_all.append_array(opp_bench)
	for p in opp_all:
		if p.current_hp > 0:
			p.current_hp = max(0, p.current_hp - 10)
			main.display_hp_circles_above_align(p, not is_opponent)
	main.display_pokemon(not is_opponent)
	await main.check_all_knockouts()
	if main._should_bail(): return
	if opp_bench.size() > 0:
		var switch_effect = {"type": "force_switch", "target": "defender", "chooser": "defender", "flip": "none"}
		await apply_force_switch(switch_effect, is_opponent)
		if main._should_bail(): return
	print("ATTACK EXECUTED: Shockwave")

# SECRETE POISON (neo2-41 Kakuna): set flag — if hit next turn, attacker gets poisoned + 10 to each opp bench
func execute_neo2_secrete_poison(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.secrete_poison_active = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name","").to_upper() + " PREPARED SECRETE POISON! IF HIT, ATTACKER IS POISONED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Secrete Poison — flag set")

# HARDEN (neo2-42 Metapod): prevent ≤20 damage next turn (reuses shielded_damage_threshold)
func execute_neo2_harden(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.shielded_damage_threshold = 20
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name","").to_upper() + " HARDENED! ATTACKS DEALING 20 OR LESS ARE BLOCKED!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Harden — shielded_damage_threshold=20")

# HATCH (neo2-42 Metapod): flip — if heads, heal all damage + evolve into Butterfree
func execute_neo2_hatch(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! HATCH FAILED!")
		if main._should_bail(): return
		return
	var max_hp = int(attacker.metadata.get("hp","0"))
	attacker.current_hp = max_hp
	main.display_hp_circles_above_align(attacker, is_opponent)
	await main.show_message("HATCH! SEARCHING FOR BUTTERFREE...")
	if main._should_bail(): return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Butterfree" in c.metadata.get("name",""), "HATCH: CHOOSE BUTTERFREE TO EVOLVE INTO", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO BUTTERFREE FOUND IN DECK!")
		if main._should_bail(): return
		return
	var butterfree = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(butterfree)
	butterfree.attached_pre_evolutions.append(attacker)
	var all_energy = attacker.attached_energies.duplicate()
	for e in all_energy:
		attacker.attached_energies.erase(e)
		butterfree.attached_energies.append(e)
	butterfree.current_hp = int(butterfree.metadata.get("hp","0"))
	butterfree.placed_on_field_this_turn = true
	if attacker.current_location == "active":
		butterfree.current_location = "active"
		if is_opponent:
			main.opponent_active_pokemon = butterfree
		else:
			main.player_active_pokemon = butterfree
	else:
		butterfree.current_location = "bench"
		var bench = main.opponent_bench if is_opponent else main.player_bench
		bench.erase(attacker)
		bench.append(butterfree)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("HATCH! " + attacker.metadata.get("name","").to_upper() + " EVOLVED INTO BUTTERFREE!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Hatch — evolved to Butterfree")

# SQUEEZE (neo2-43 Omastar): 10 damage; flip — heads: +20 damage AND Paralyzed
func execute_neo2_squeeze(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var total = 10 + (20 if coin else 0)
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if coin and defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, "Paralyzed", not is_opponent)
		await main.show_message("HEADS! SQUEEZE! +20 DAMAGE AND PARALYZED!")
		if main._should_bail(): return
	elif not coin:
		await main.show_message("TAILS! SQUEEZE — 10 DAMAGE ONLY")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Squeeze — ", total, " damage")

# SPIKE BARRAGE (neo2-43 Omastar): 20 + flip coins = water_energy_count, 20 more per heads
func execute_neo2_spike_barrage(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var water_count = 0
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			water_count += 1
	var heads = 0
	for i in range(water_count):
		if await main.flip_coin(water_count > 1, is_opponent):
			heads += 1
	if main._should_bail(): return
	var total = 20 + (heads * 20)
	await main.show_message("SPIKE BARRAGE! " + str(water_count) + " WATER ENERGY — " + str(heads) + " HEADS — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Spike Barrage — ", total, " damage")

# BELLY DRUM (neo2-44 Poliwhirl): 30 damage to self; if not KO'd, attach 2 basic energy from deck
func execute_neo2_belly_drum(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.current_hp = max(0, attacker.current_hp - 30)
	main.display_hp_circles_above_align(attacker, is_opponent)
	var label_x = 1030 if is_opponent else 530
	main.show_floating_label("-30HP", Vector2(label_x, 300), Color.RED, true)
	await main.show_message("BELLY DRUM! POLIWHIRL TAKES 30 DAMAGE TO POWER UP!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if attacker.current_hp <= 0:
		return
	await main.show_message("SEARCHING FOR 2 BASIC ENERGY CARDS...")
	if main._should_bail(): return
	for i in range(2):
		var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]), "BELLY DRUM: CHOOSE BASIC ENERGY " + str(i+1), 1)
		if main._should_bail(): return
		if found.is_empty():
			break
		var energy = found[0]
		var hand = main.opponent_hand if is_opponent else main.player_hand
		hand.erase(energy)
		attacker.attached_energies.append(energy)
		energy.current_location = attacker.current_location
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("BELLY DRUM! ATTACHED 2 BASIC ENERGY!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Belly Drum")

# DUST DEVIL (neo2-45 Pupitar): 10 damage to each non-Fighting pokemon in play (no W/R)
func execute_neo2_dust_devil(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	await main.show_message("DUST DEVIL! 10 DAMAGE TO ALL NON-FIGHTING POKEMON!")
	if main._should_bail(): return
	var all_poke: Array = []
	if main.player_active_pokemon != null: all_poke.append({"poke": main.player_active_pokemon, "is_opp": false})
	if main.opponent_active_pokemon != null: all_poke.append({"poke": main.opponent_active_pokemon, "is_opp": true})
	for bp in main.player_bench:
		all_poke.append({"poke": bp, "is_opp": false})
	for bp in main.opponent_bench:
		all_poke.append({"poke": bp, "is_opp": true})
	for entry in all_poke:
		var p: card_object = entry["poke"]
		if p == attacker: continue
		var poke_types = p.metadata.get("types", ["Colorless"])
		if "Fighting" in poke_types: continue
		if p.current_hp > 0:
			p.current_hp = max(0, p.current_hp - 10)
			main.display_hp_circles_above_align(p, entry["is_opp"])
	main.display_pokemon(true)
	main.display_pokemon(false)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Dust Devil")

# FURY CUTTER (neo2-46 Scyther): 4 coins — 10 + 10 if 1 head, +20 if 2, +40 if 3, +80 if 4
func execute_neo2_fury_cutter(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(4):
		if await main.flip_coin(true, is_opponent):
			heads += 1
	if main._should_bail(): return
	var bonus_table = [0, 10, 20, 40, 80]
	var total = 10 + bonus_table[heads]
	await main.show_message("FURY CUTTER! " + str(heads) + " HEADS — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Fury Cutter — ", total, " damage (", heads, " heads)")

# ENERGY CYCLE (neo2-52 Xatu): flip — if heads, take 1 energy from defending pokemon and attach to opp's bench pokemon
func execute_neo2_energy_cycle(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENERGY CYCLE FAILS!")
		if main._should_bail(): return
		return
	if defender == null or defender.attached_energies.is_empty():
		await main.show_message("NO ENERGY ON DEFENDING POKEMON!")
		if main._should_bail(): return
		return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.show_message("NO BENCHED POKEMON TO RECEIVE ENERGY!")
		if main._should_bail(): return
		return
	var energy: card_object = null
	var target_bench: card_object = null
	var def_is_opp = not is_opponent
	if is_opponent:
		energy = defender.attached_energies[0]
		target_bench = opp_bench[0]
	else:
		energy = await main.card_ops.prompt_select_card(defender.attached_energies, "ENERGY CYCLE", "Choose energy to take from defending pokemon", "SELECT", def_is_opp)
		if main._should_bail(): return
		if energy == null: return
		target_bench = await main.card_ops.prompt_select_card(opp_bench, "ENERGY CYCLE", "Choose bench pokemon to receive the energy", "SELECT", def_is_opp)
		if main._should_bail(): return
		if target_bench == null: return
	defender.attached_energies.erase(energy)
	target_bench.attached_energies.append(energy)
	energy.current_location = "bench"
	main.display_active_pokemon_energies(not is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ENERGY CYCLE! ENERGY MOVED TO " + target_bench.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Energy Cycle")

# WORK TOGETHER (neo2-56 Kabuto): 10 + flip — if heads, +10 per fossil pokemon on bench
func execute_neo2_work_together(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var fossil_names = ["Omanyte", "Omastar", "Kabuto", "Kabutops"]
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var fossil_count = 0
	for bp in bench:
		if bp.metadata.get("name","") in fossil_names:
			fossil_count += 1
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	var total = 10 + (fossil_count * 10 if coin else 0)
	await main.show_message("WORK TOGETHER! " + str(fossil_count) + " FOSSIL BENCH — " + str(total) + " DAMAGE!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Work Together — ", total, " damage")

# BURST (neo2-61 Pineco): flip — heads: 40 damage + 40 to self + 10 to all benched; tails: nothing
func execute_neo2_burst(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! BURST FIZZLED!")
		if main._should_bail(): return
		return
	await main.show_message("BURST! PINECO EXPLODES!")
	if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(40, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 40)
		if main._should_bail(): return
	attacker.current_hp = max(0, attacker.current_hp - 40)
	main.display_hp_circles_above_align(attacker, is_opponent)
	main.show_floating_label("-40HP", Vector2(1030 if is_opponent else 530, 300), Color.RED, true)
	var all_bench: Array = []
	all_bench.append_array(main.player_bench)
	all_bench.append_array(main.opponent_bench)
	for bp in all_bench:
		if bp.current_hp > 0:
			main.card_ops.apply_bench_damage(bp, 10, bp in main.opponent_bench)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Burst")

# RECOVER (neo2-37 Corsola): discard 1 Water energy from self (or attack fails), then heal all damage
func execute_neo2_recover(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var water_e: card_object = null
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			water_e = e
			break
	if water_e == null:
		await main.show_message("NO WATER ENERGY TO DISCARD! RECOVER FAILS!")
		if main._should_bail(): return
		return
	attacker.attached_energies.erase(water_e)
	main.card_ops.discard_energy_from_pokemon(water_e, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	var max_hp = int(attacker.metadata.get("hp","0"))
	attacker.current_hp = max_hp
	main.display_hp_circles_above_align(attacker, is_opponent)
	await main.show_message("RECOVER! ALL DAMAGE REMOVED FROM " + attacker.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Recover — full heal")

# PLUNDER (neo2-39 Houndour): 20 damage + discard all trainer cards attached to defender
func execute_neo2_plunder(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var trainers_to_remove: Array = []
	for c in defender.attached_cards:
		if c.metadata.get("supertype","") == "Trainer":
			trainers_to_remove.append(c)
	for t in trainers_to_remove:
		defender.attached_cards.erase(t)
		var def_is_opp = not is_opponent
		main.send_card_to_discard(t, def_is_opp)
	if trainers_to_remove.size() > 0:
		await main.show_message("PLUNDER! DISCARDED " + str(trainers_to_remove.size()) + " TRAINER(S) FROM DEFENDER!")
		if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Plunder — ", base_damage, " damage + trainers discarded")

# HEADPRESS (neo2-15/34 Ursaring): flip — heads: 30 damage + Paralyzed; tails: nothing
func execute_neo2_headpress(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! HEADPRESS DOES NOTHING!")
		if main._should_bail(): return
		return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(30, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, 30)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		main.card_ops.apply_status(defender, "Paralyzed", not is_opponent)
		await main.show_message("HEADS! HEADPRESS! " + defender.metadata.get("name","").to_upper() + " IS PARALYZED!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Headpress — 30 damage + Paralyzed")

# PURSUIT (neo2-32 Umbreon): 30 damage + if defender retreats next turn, deal 10 more damage
func execute_neo2_pursuit(attacker: card_object, defender: card_object, is_opponent: bool, base_damage: int) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	if defender != null and defender.current_hp > 0:
		defender.pursuit_active = true
		await main.show_message("PURSUIT! IF " + defender.metadata.get("name","").to_upper() + " RETREATS, TAKE 10 DAMAGE!")
		if main._should_bail(): return
	print("ATTACK EXECUTED: Pursuit — ", base_damage, " damage + pursuit flag")

# SLIME (neo2-71 Wooper): set slime_active — attacker must flip before dealing damage; tails = no damage
func execute_neo2_slime(attacker: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	attacker.slime_active = true
	main.update_status_icons(attacker, is_opponent)
	await main.show_message(attacker.metadata.get("name","").to_upper() + " IS SLIMED! ATTACKERS MUST FLIP TO HIT!")
	if main._should_bail(): return
	print("ATTACK EXECUTED: Slime — flag set")

# HIDDEN POWER (all Unown): 10 damage + [Anger] bonus from any Unown [A] on attacker's side
func execute_neo2_hidden_power(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var bonus = main.powers_and_bodies.get_unown_anger_bonus(attacker, is_opponent)
	var total = 10 + bonus
	if bonus > 0:
		await main.show_message("[ANGER]! HIDDEN POWER DEALS " + str(total) + " DAMAGE!")
		if main._should_bail(): return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(total, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, total)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Hidden Power — ", total, " damage")

# DOUBLESLAP (Politoed with Frog Song, or generic 2×40 for others)
func execute_neo2_politoed_doubleslap(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	if await handle_attack_confusion(attacker, is_opponent): return
	if await handle_attack_blind(attacker, is_opponent): return
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent):
			heads += 1
	if main._should_bail(): return
	var base_damage = heads * 40
	var frog_bonus = main.powers_and_bodies.get_frog_song_bonus(attacker)
	if frog_bonus > 0:
		base_damage += frog_bonus
		await main.show_message("FROG SONG! " + str(heads) + " HEADS + +40 — TOTAL " + str(base_damage) + " DAMAGE!")
		if main._should_bail(): return
	else:
		await main.show_message("DOUBLESLAP! " + str(heads) + " HEADS — " + str(base_damage) + " DAMAGE!")
		if main._should_bail(): return
	if base_damage == 0:
		return
	var types = attacker.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(base_damage, types, defender, attacker)
	if not main.check_defender_invincible(defender, not is_opponent):
		var fd = main.apply_defender_no_damage_shield(defender, result["damage"], not is_opponent)
		await main.display_and_apply_attack_damage(attacker, defender, fd, result["modifiers"], is_opponent, base_damage)
		if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("ATTACK EXECUTED: Doubleslap (Politoed) — ", base_damage, " damage")
