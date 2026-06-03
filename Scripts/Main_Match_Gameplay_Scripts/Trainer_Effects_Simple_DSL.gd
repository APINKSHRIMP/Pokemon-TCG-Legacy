extends Node

######################################################################################################################################################
####################################################### SIMPLE TRAINER DSL ##########################################################################
######################################################################################################################################################
#
# Interpreter for trainer cards whose effects are expressible as a single data dictionary.
# Roughly 30% of trainers across future sets (Neo1–Neo4, EX sets) are this simple.
#
# Usage in Trainer_Effects._register_*_trainers():
#   _trainer_dispatch["neo1-xx"] = func(c, opp): await main.trainer_dsl.resolve({"op":"draw","n":2}, c, opp)
#
# Access via main.trainer_dsl (wired in Main._ready after trainer_effects).
#
# Supported operations (see resolve() below):
#   draw          n:int                              Draw N cards
#   draw_to_n     target:int                         Draw until hand has N cards (stop if deck empty)
#   heal          amount:int                         Heal N HP from a chosen damaged pokemon
#   heal_active   amount:int                         Heal N HP from active pokemon only
#   heal_all      amount:int                         Heal N HP from every pokemon on your side
#   full_heal                                        Remove all status conditions from active
#   search_energy n:int, energy_type:String=""       Search deck for N energy cards (any type or specific)
#   search_basic  n:int                              Search deck for N basic pokemon
#   flip_draw     n:int                              Flip coin; heads = draw N cards
#   discard_draw  discard:int, draw:int              Discard M cards from hand, then draw N cards
#

var main: Node

# ──────────────────────────────────────────────────────────────────────────────

func resolve(dsl: Dictionary, _card: card_object, is_opponent: bool) -> void:
	match dsl.get("op", ""):
		"draw":          await _op_draw(is_opponent, dsl.get("n", 1))
		"draw_to_n":     await _op_draw_to_n(is_opponent, dsl.get("target", 4))
		"heal":          await _op_heal(is_opponent, dsl.get("amount", 20))
		"heal_active":   await _op_heal_active(is_opponent, dsl.get("amount", 20))
		"heal_all":      await _op_heal_all(is_opponent, dsl.get("amount", 10))
		"full_heal":     await _op_full_heal(is_opponent)
		"search_energy": await _op_search_energy(is_opponent, dsl.get("n", 1), dsl.get("energy_type", ""))
		"search_basic":  await _op_search_basic(is_opponent, dsl.get("n", 1))
		"flip_draw":     await _op_flip_draw(is_opponent, dsl.get("n", 2))
		"discard_draw":  await _op_discard_draw(_card, is_opponent, dsl.get("discard", 1), dsl.get("draw", 2))
		_:
			push_error("Trainer DSL: unknown op '" + dsl.get("op", "") + "'")


# ── draw ──────────────────────────────────────────────────────────────────────

func _op_draw(is_opponent: bool, n: int) -> void:
	await main.card_ops.draw_n(is_opponent, n)
	if main._should_bail(): return
	if n == 1:
		await main.show_message("DREW 1 CARD!")
	else:
		await main.show_message("DREW " + str(n) + " CARDS!")
	if main._should_bail(): return


# ── draw_to_n ─────────────────────────────────────────────────────────────────

func _op_draw_to_n(is_opponent: bool, target: int) -> void:
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var to_draw = max(0, target - hand.size())
	if to_draw == 0:
		await main.show_message("HAND ALREADY HAS " + str(target) + " OR MORE CARDS!")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, to_draw)
	if main._should_bail(): return
	await main.show_message("DREW " + str(to_draw) + " CARD(S)!")
	if main._should_bail(): return


# ── heal (any damaged pokemon, player chooses) ────────────────────────────────

func _op_heal(is_opponent: bool, amount: int) -> void:
	var all_poke = _build_field(is_opponent)
	var damaged = all_poke.filter(func(p): return p.current_hp < p.get_max_hp())
	if damaged.is_empty():
		await main.show_message("NO POKEMON WITH DAMAGE TO HEAL!")
		if main._should_bail(): return
		return
	if is_opponent:
		var target = damaged[0]
		for p in damaged:
			if p.get_damage_counters() > target.get_damage_counters():
				target = p
		await main.card_ops.heal_pokemon(target, amount, true)
	else:
		var target = await main.card_ops.prompt_select_card(
			damaged, "HEAL A POKEMON", "Select a Pokemon to heal " + str(amount) + " HP", "HEAL", false)
		if main._should_bail(): return
		if target != null:
			await main.card_ops.heal_pokemon(target, amount, false)
	if main._should_bail(): return


# ── heal_active ───────────────────────────────────────────────────────────────

func _op_heal_active(is_opponent: bool, amount: int) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null or active.current_hp >= active.get_max_hp():
		await main.show_message("ACTIVE POKEMON IS AT FULL HEALTH!")
		if main._should_bail(): return
		return
	await main.card_ops.heal_pokemon(active, amount, is_opponent)
	if main._should_bail(): return


# ── heal_all ──────────────────────────────────────────────────────────────────

func _op_heal_all(is_opponent: bool, amount: int) -> void:
	var healed = 0
	for p in _build_field(is_opponent):
		if p.current_hp < p.get_max_hp():
			await main.card_ops.heal_pokemon(p, amount, is_opponent)
			if main._should_bail(): return
			healed += 1
	if healed == 0:
		await main.show_message("ALL POKEMON ARE AT FULL HEALTH!")
	else:
		await main.show_message("HEALED " + str(amount) + " HP FROM " + str(healed) + " POKEMON!")
	if main._should_bail(): return


# ── full_heal ─────────────────────────────────────────────────────────────────

func _op_full_heal(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null:
		return
	var had = active.special_condition != "" or active.is_poisoned or active.is_burned
	main.clear_all_statuses(active, is_opponent)
	if had:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		await main.show_message(active.metadata.get("name", "").to_upper() + " FULLY HEALED OF ALL CONDITIONS!")
	else:
		await main.show_message(active.metadata.get("name", "").to_upper() + " HAD NO CONDITIONS TO HEAL.")
	if main._should_bail(): return


# ── search_energy ─────────────────────────────────────────────────────────────

func _op_search_energy(is_opponent: bool, n: int, energy_type: String) -> void:
	var filter: Callable
	if energy_type == "":
		filter = func(c): return c.metadata.get("supertype", "") == "Energy" and c.metadata.get("subtypes", []).has("Basic")
	else:
		filter = func(c): return c.metadata.get("supertype", "") == "Energy" \
			and c.metadata.get("subtypes", []).has("Basic") \
			and energy_type in c.metadata.get("name", "")
	var prompt = "SEARCH FOR A BASIC ENERGY" if energy_type == "" else "SEARCH FOR " + energy_type.to_upper() + " ENERGY"
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter, prompt, n)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO MATCHING ENERGY IN DECK!")
	else:
		await main.show_message("FOUND " + str(found.size()) + " ENERGY CARD(S)!")
	if main._should_bail(): return


# ── search_basic ──────────────────────────────────────────────────────────────

func _op_search_basic(is_opponent: bool, n: int) -> void:
	var filter = func(c): return main.is_basic_pokemon(c)
	var found = await main.card_ops.search_deck_to_hand(is_opponent, filter, "SEARCH FOR A BASIC POKEMON", n)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO BASIC POKEMON IN DECK!")
	else:
		await main.show_message("FOUND " + str(found.size()) + " BASIC POKEMON!")
	if main._should_bail(): return


# ── flip_draw ─────────────────────────────────────────────────────────────────

func _op_flip_draw(is_opponent: bool, n: int) -> void:
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if coin:
		await main.card_ops.draw_n(is_opponent, n)
		if main._should_bail(): return
		await main.show_message("HEADS! DREW " + str(n) + " CARD(S)!")
	else:
		await main.show_message("TAILS! NO EFFECT.")
	if main._should_bail(): return


# ── discard_draw ──────────────────────────────────────────────────────────────

func _op_discard_draw(played_card: card_object, is_opponent: bool, discard_n: int, draw_n: int) -> void:
	var discarded = await main.card_ops.discard_from_hand(is_opponent, discard_n, played_card)
	if main._should_bail(): return
	if discarded.size() < discard_n:
		await main.show_message("NOT ENOUGH CARDS TO DISCARD!")
		if main._should_bail(): return
		return
	await main.card_ops.draw_n(is_opponent, draw_n)
	if main._should_bail(): return
	await main.show_message("DISCARDED " + str(discard_n) + ", DREW " + str(draw_n) + "!")
	if main._should_bail(): return


# ── helpers ───────────────────────────────────────────────────────────────────

func _build_field(is_opponent: bool) -> Array:
	var result: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		result.append(active)
	result.append_array(bench)
	return result
