extends Node

######################################################################################################################################################
########################################################## POWERS AND BODIES EFFECTS ###############################################################
######################################################################################################################################################
#
# This file contains Pokémon Powers, Pokémon Bodies, and related helpers.
# Powers are activated abilities (Rain Dance, Energy Trans, Damage Swap, etc.)
# Bodies are passive abilities (Energy Burn, Strikes Back, etc.)
# All game state, signals, and node references are accessed through the main back-reference.
#

var main: Node

# ── Power dispatch registry ────────────────────────────────────────────────────
# Maps ability name → async Callable(pokemon). Player path only; CPU path is separate.
# Add new set powers by calling _register_<set>_powers() from _ensure_power_dispatch_ready().
var _power_dispatch: Dictionary = {}
var _power_dispatch_ready := false

func _ensure_power_dispatch_ready() -> void:
	if _power_dispatch_ready:
		return
	_power_dispatch_ready = true
	_register_all_powers()
	# Neo1 and Neo2 powers are registered via _register_neo1_powers() / _register_neo2_powers() called from _register_all_powers()

func _register_all_powers() -> void:
	_power_dispatch["Damage Swap"]           = func(p): await power_damage_swap(p)
	_power_dispatch["Rain Dance"]            = func(p): await power_rain_dance(p)
	_power_dispatch["Energy Trans"]          = func(p): await power_energy_trans(p)
	_power_dispatch["Buzzap"]                = func(p): await power_buzzap(p)
	_power_dispatch["Discard"]               = func(p): await power_bench_token_discard(p)
	_power_dispatch["Shift"]                 = func(p): await power_shift(p)
	_power_dispatch["Heal"]                  = func(p): await power_heal_vileplume(p)
	_power_dispatch["Peek"]                  = func(p): await power_peek(p)
	_power_dispatch["Step In"]               = func(p): await power_step_in(p)
	_power_dispatch["Curse"]                 = func(p): await power_curse(p)
	_power_dispatch["Strange Behavior"]      = func(p): await power_strange_behavior(p)
	_power_dispatch["Cowardice"]             = func(p): await power_cowardice(p)
	_power_dispatch["Evolutionary Light"]    = func(p): await power_evolutionary_light(p)
	_power_dispatch["Pollen Stench"]         = func(p): await power_pollen_stench(p)
	_power_dispatch["Matter Exchange"]       = func(p): await power_matter_exchange(p)
	_power_dispatch["Gather Fire"]           = func(p): await power_gather_fire(p)
	_power_dispatch["Long-Distance Hypnosis"]= func(p): await power_long_distance_hypnosis(p)
	_power_dispatch["Trickery"]              = func(p): await power_trickery(p)
	_power_dispatch["Celadon City Gym"]      = func(p): await main.trainer_effects.gym1_celadon_activate(false)
	_power_dispatch["Fuchsia City Gym"]      = func(p): await main.trainer_effects.gym2_fuchsia_activate(false)
	_power_dispatch["Saffron City Gym"]      = func(p): await main.trainer_effects.gym2_saffron_activate(false)
	_power_dispatch["Energy Charge"]         = func(p): await power_energy_charge(p)
	_power_dispatch["Fragrance Trap"]        = func(p): await power_fragrance_trap(p)
	_power_dispatch["Natural Healing"]       = func(p): await power_natural_healing(p)
	_power_dispatch["Shapeshift"]            = func(p): await power_shapeshift(p)
	_power_dispatch["Discard Form"]          = func(p): await power_shapeshift_discard(p)
	_power_dispatch["Soak Up"]               = func(p): await power_soak_up(p)
	_power_dispatch["Emerge"]                = func(p): await power_emerge(p)
	_power_dispatch["Special Delivery"]     = func(p): await power_special_delivery(p)
	_power_dispatch["Solar Power"]          = func(p): await power_solar_power(p)
	_power_dispatch["[Join]"]               = func(p): await power_join_unown(p)
	_power_dispatch["Lucky Stadium"]        = func(p): await main.trainer_effects.basep_lucky_stadium_activate(false)
	_power_dispatch["Healing Field"]        = func(p): await main.trainer_effects.neo3_healing_field_activate(false)
	_power_dispatch["Chain Reaction"]      = func(p): await power_chain_reaction(p)
	_register_neo1_powers()
	_register_neo2_powers()
	_register_neo3_powers()
	_register_neo4_powers()
	_register_np_powers()
	_register_ecard1_powers()
	_register_ecard2_powers()
	_register_ecard3_powers()
	_register_ex1_powers()
	_register_ex2_powers()
	_register_ex3_powers()
	_register_ex4_powers()
	_register_ex5_powers()

# ── On-damage and pre-KO event hooks ──────────────────────────────────────────
# Each Callable is fired after active-pokemon damage resolves (on_damage) or
# just before a KO'd pokemon's discard sequence begins (pre_ko).
# Signature: func(defender, attacker, damage: int, is_def_opp: bool) — for on_damage
# Signature: func(pokemon, attacker, is_pokemon_opp: bool)           — for pre_ko
# attack_effects registers its own hooks at startup via register_on_damage_hook.
var _on_damage_hooks: Array = []
var _pre_ko_hooks: Array = []

# Damage-modifier hooks: called from Main.calculate_final_damage AFTER Weakness/Resistance.
# Signature: fn(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int
# Each hook returns the (possibly reduced/increased) damage. NOT async — no awaits allowed inside.
# All NEW passive damage-modifying bodies from ecard2 onward register a hook here; do not edit
# calculate_final_damage directly.
var _damage_modifier_hooks: Array = []

func register_on_damage_hook(fn: Callable) -> void:
	_on_damage_hooks.append(fn)

func register_pre_ko_hook(fn: Callable) -> void:
	_pre_ko_hooks.append(fn)

func add_damage_modifier_hook(fn: Callable) -> void:
	_damage_modifier_hooks.append(fn)

func run_damage_modifier_hooks(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	for fn in _damage_modifier_hooks:
		damage = fn.call(damage, attacker, defender, modifiers)
	return damage

func _register_all_power_hooks() -> void:
	_on_damage_hooks.clear()
	_pre_ko_hooks.clear()
	_damage_modifier_hooks.clear()
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ecard1_reduction_bodies(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ecard1_strength_charm(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ecard2_reduction_bodies(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ecard3_thick_shell(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex1_intimidating_fang(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex1_hard_cocoon(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex2_glowing_screen(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex2_safeguard(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex3_buffer_piece(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex3_sand_guard(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex3_energy_guard(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex3_power_pinchers(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex3_wonder_guard(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex4_shell_retreat(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex5_crust(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex5_ice_wall(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex5_core_guard(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex5_overzealous(dmg, atk, def, mods))
	_damage_modifier_hooks.append(func(dmg, atk, def, mods): return _hook_ex5_silver_wind(dmg, atk, def, mods))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_strikes_back(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_restless_sleep(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_pollen_defense(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_energy_drain(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_shock_blast(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_scram(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_flee(def, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_koga_poison(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_bolt(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo2_counter(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo2_secrete_poison(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo4_fluffy_wool(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_neo4_counters(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_ecard2_fluff(def, atk, dmg, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_ex1_rough_skin(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_ex2_poison_payback(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_ex2_fire_veil(def, atk, is_def_opp))
	_on_damage_hooks.append(func(def, atk, dmg, is_def_opp): await check_ex2_jagged_stone(def, atk, is_def_opp))
	_pre_ko_hooks.append(func(poke, atk, is_poke_opp): await check_ex5_energy_grounding(poke, atk, is_poke_opp))
	_pre_ko_hooks.append(func(poke, atk, is_poke_opp): await check_final_beam(poke, atk, is_poke_opp))
	_pre_ko_hooks.append(func(poke, atk, is_poke_opp): await main.trainer_effects.check_time_shard(poke, atk, is_poke_opp))

# Fires all on-damage hooks in registration order. Called once from Main after active damage lands.
func dispatch_on_damage(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	for fn in _on_damage_hooks:
		if main._should_bail(): return
		await fn.call(defender, attacker, damage, is_def_opp)
		# If a preceding hook switched the defender out of the Active spot (e.g. Flee), stop —
		# later hooks must not keep applying effects (like status) to a stale reference for a
		# Pokemon that is no longer the one being attacked.
		var still_active = defender == (main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon)
		if not still_active:
			return

# Fires all pre-KO hooks. Called once from Main before the KO'd pokemon is discarded.
func dispatch_pre_ko(pokemon: card_object, attacker: card_object, is_pokemon_opp: bool) -> void:
	for fn in _pre_ko_hooks:
		if main._should_bail(): return
		await fn.call(pokemon, attacker, is_pokemon_opp)

# GYM2 Koga (gym2-19/106) poison: a Koga-named attacker that dealt damage this turn poisons the defender.
func check_koga_poison(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if attacker == null or defender == null:
		return
	var attacker_owner_is_opp = (attacker == main.opponent_active_pokemon)
	var koga_on = main.opponent_koga_poison_active if attacker_owner_is_opp else main.player_koga_poison_active
	if not koga_on:
		return
	if not ("Koga" in attacker.metadata.get("name", "")):
		return
	if defender.is_poisoned or defender.special_condition == "Asleep":
		return
	main.card_ops.apply_status(defender, "Poisoned", is_def_opp)
	print("GYM2 KOGA: Poisoned ", defender.metadata.get("name", ""))

func is_power_blocked_by_status(pokemon: card_object) -> bool:
	if pokemon == null:
		return true
	# ecard2 Dark Impact (Houndoom-15): target can't use Poké-Powers until end of its owner's next turn
	if pokemon.has_effect("ecard2_dark_impact_power_lock"):
		return true
	return pokemon.is_status_blocked()

# Full power-blocker check: status conditions, Toxic Gas, Goop Gas, and temporary disable flag.
# Pass works_through_status=true for powers like Buzzap that still work while statused.
func is_power_blocked(pokemon: card_object, works_through_status: bool = false) -> bool:
	if pokemon == null:
		return true
	if not works_through_status and pokemon.is_status_blocked():
		return true
	if is_toxic_gas_active():
		return true
	if main.goop_gas_active:
		return true
	if pokemon.power_disabled_until_end_of_next_turn:
		return true
	# ECARD3 Dark Gaze (Umbreon): while Umbreon is Active on either side, Benched Pokemon
	# (both sides) can't use Poké-Powers. Umbreon itself is unaffected while Active.
	if pokemon != main.player_active_pokemon and pokemon != main.opponent_active_pokemon:
		var pa = main.player_active_pokemon
		var oa = main.opponent_active_pokemon
		if (pa != null and pa.has_ability("Dark Gaze") and not pa.is_status_blocked()) or (oa != null and oa.has_ability("Dark Gaze") and not oa.is_status_blocked()):
			return true
	# EX1 Lazy (Slaking): while Slaking is a side's Active, the OPPOSING side's Pokemon (both
	# Active and Benched) can't use Poké-Powers. Slaking's own side is unaffected.
	var pokemon_is_opp = pokemon.is_owner_opp(main)
	var opposing_active = main.player_active_pokemon if pokemon_is_opp else main.opponent_active_pokemon
	if opposing_active != null and opposing_active.has_ability("Lazy") and not opposing_active.is_status_blocked():
		return true
	return false

# Returns true if a card is a trainer card

func is_energy_burn_active(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	var name = pokemon.metadata.get("name", "")
	if name != "Charizard":
		return false
	# Check if it has the Energy Burn ability
	var abilities = pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") == "Energy Burn":
			# Blocked by status
			if is_power_blocked_by_status(pokemon):
				return false
			return true
	return false

# ECARD1 Burning Energy (Charizard ecard1-6): while active for a side, all basic Energy
# attached to that side's Pokemon counts as Fire for the rest of the turn.
func is_ecard1_burning_energy_active(pokemon: card_object) -> bool:
	if pokemon == null: return false
	var is_opponent = pokemon.is_owner_opp(main)
	return main.opponent_ecard1_burning_energy_active if is_opponent else main.player_ecard1_burning_energy_active

# ECARD1 Dark Aura (Tyranitar ecard1-29/66): all Energy attached to Tyranitar counts as Darkness
func is_ecard1_dark_aura_active(pokemon: card_object) -> bool:
	if pokemon == null: return false
	if pokemon.metadata.get("name", "") != "Tyranitar": return false
	for ability in pokemon.metadata.get("abilities", []):
		if ability.get("name", "") == "Dark Aura":
			if is_power_blocked_by_status(pokemon): return false
			return true
	return false

# ECARD3 Rare Metal (Steelix): all basic Energy attached to Steelix provides Metal instead
func is_ecard3_rare_metal_active(pokemon: card_object) -> bool:
	if pokemon == null: return false
	if not pokemon.has_ability("Rare Metal"): return false
	return not is_power_blocked_by_status(pokemon)

# ECARD3 Prismatic Body (Ditto): each basic Energy attached to Ditto provides every type,
# but only 1 Energy at a time (i.e. it can pay for any single Colorless-equivalent cost slot,
# not multiple types simultaneously from the same card)
func is_ecard3_prismatic_body_active(pokemon: card_object) -> bool:
	if pokemon == null: return false
	if not pokemon.has_ability("Prismatic Body"): return false
	return not is_power_blocked_by_status(pokemon)

# Resets power_used_this_turn for all pokemon on one side

func reset_power_used_flags(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		active.reset_power_used()
	for bp in bench:
		bp.reset_power_used()
	# Refresh Gaseous Form HP each turn in case Toxic Gas / Goop Gas state changed
	refresh_gaseous_form_hp()

# Discards PlusPower from a pokemon at end of turn

func open_power_menu() -> void:
	if main.opponents_turn_active:
		return
	
	# Scan for available powers
	var available_powers = []
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	# Check if Toxic Gas is active (blocks all non-Toxic-Gas powers)
	var toxic_gas_active = is_toxic_gas_active()
	
	for pokemon in all_pokemon:
		var abilities = pokemon.metadata.get("abilities", [])
		for ability in abilities:
			var ability_type = ability.get("type", "")
			if ability_type != "Pokémon Power" and ability_type != "Pokemon Power" and ability_type != "Poké-Power" and ability_type != "Poke-Power":
				continue
			var ability_name = ability.get("name", "")
			# Only offer abilities that have a registered activation function — passives (and
			# not-yet-implemented powers) simply aren't in _power_dispatch, so they never
			# appear here. This is derived from _power_dispatch instead of a hand-maintained
			# skip list; see activate_power() which uses the same dictionary.
			_ensure_power_dispatch_ready()
			if not _power_dispatch.has(ability_name):
				continue
			# Toxic Gas blocks all other powers
			if toxic_gas_active:
				continue
			# Dark Arbok Stare: power disabled temporarily
			if pokemon.power_disabled_until_end_of_next_turn:
				continue
			# NEO2 Gaze (Igglybuff): suppress this pokemon's power for the turn
			if pokemon.gaze_suppressed:
				continue
			# SCARE (neo4-5 Dark Feraligatr): opponent's active Feraligatr blocks Baby Pokémon powers
			if "Baby" in pokemon.metadata.get("subtypes", []) and is_scare_active(false):
				continue
			# Check if usable
			if ability_name != "Buzzap" and is_power_blocked_by_status(pokemon):
				continue
			available_powers.append({"pokemon": pokemon, "ability": ability})
	
	if available_powers.size() == 0:
		# Also check for bench tokens with voluntary discard (their ability is in rules text, not abilities field)
		for bp in main.player_bench:
			if bp.is_bench_token:
				available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active pokemon too
		if main.player_active_pokemon != null and main.player_active_pokemon.is_bench_token:
			available_powers.append({"pokemon": main.player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	else:
		# Add bench token discards if they weren't already found via abilities
		for bp in main.player_bench:
			if bp.is_bench_token:
				var already_added = false
				for p in available_powers:
					if p["pokemon"] == bp:
						already_added = true
						break
				if not already_added:
					available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active too
		if main.player_active_pokemon != null and main.player_active_pokemon.is_bench_token:
			var already_added = false
			for p in available_powers:
				if p["pokemon"] == main.player_active_pokemon:
					already_added = true
					break
			if not already_added:
				available_powers.append({"pokemon": main.player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	
	# GYM1-107 Celadon City Gym (Stadium): treat as an activatable power. Add a synthetic entry that targets the stadium card itself.
	if main.trainer_effects.gym1_celadon_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Celadon City Gym", "type": "Stadium", "text": "Discard an Energy from one of your Erika Pokemon to cure it of all status conditions."}})

	# GYM2-114 Fuchsia City Gym (Stadium): once-per-turn flip → heads shuffles a Koga pokemon into deck
	if main.trainer_effects.gym2_fuchsia_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Fuchsia City Gym", "type": "Stadium", "text": "Flip a coin. Heads: shuffle 1 of your Koga Pokemon (with all attached cards) into your deck."}})

	# GYM2-122 Saffron City Gym (Stadium): return 1 basic Energy from a Sabrina pokemon to hand (unlimited)
	if main.trainer_effects.gym2_saffron_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Saffron City Gym", "type": "Stadium", "text": "Return 1 basic Energy from a Sabrina Pokemon to your hand."}})

	# basep-41 Lucky Stadium: per-turn flip to draw a card
	if main.trainer_effects.basep_lucky_stadium_has_target(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Lucky Stadium", "type": "Stadium", "text": "Flip a coin. If heads, draw 1 card."}})

	# neo3-61 Healing Field: once per turn, flip — heads removes 2 damage counters from your Active
	if main.trainer_effects.neo3_healing_field_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Healing Field", "type": "Stadium", "text": "Flip a coin. If heads, remove 2 damage counters from your Active Pokemon."}})

	# neo4-95 Radio Tower: once per turn, look at the top 2 cards of your deck
	if main.trainer_effects.neo4_radio_tower_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Radio Tower", "type": "Stadium", "text": "Look at the top 2 cards of your deck and put them back in the same order."}})

	# neo4-99 Energy Stadium: once per turn, flip — heads put a basic Energy from discard to hand
	if main.trainer_effects.neo4_energy_stadium_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Energy Stadium", "type": "Stadium", "text": "Flip a coin. If heads, put a basic Energy from your discard pile into your hand."}})

	# neo4-100 Lucky Stadium: once per turn, flip — heads draw a card (reuses the Lucky Stadium dispatch)
	if main.trainer_effects.neo4_lucky_stadium_active():
		available_powers.append({"pokemon": null, "ability": {"name": "Lucky Stadium", "type": "Stadium", "text": "Flip a coin. If heads, draw 1 card."}})

	# ecard2-118 Apricorn Forest: once per turn, if bench isn't full, flip to bench a matching-type Basic
	if main.trainer_effects.apricorn_forest_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Apricorn Forest", "type": "Stadium", "text": "Flip a coin. If heads, reveal a basic Energy from hand and search your deck for a matching-type Basic Pokemon to bench."}})

	# ecard2-138 Undersea Ruins: once per turn, flip to devolve one of your own Evolved Pokemon
	if main.trainer_effects.undersea_ruins_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Undersea Ruins", "type": "Stadium", "text": "Flip a coin. If heads, devolve one of your Evolved Pokemon."}})

	# ecard2-139 Power Plant: once per turn, discard a basic Energy to swap for one from your discard pile
	if main.trainer_effects.power_plant_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Power Plant", "type": "Stadium", "text": "Discard a basic Energy card to put a different basic Energy from your discard pile into your hand."}})

	# ecard3-119 Ancient Ruins: once per turn, if no Supporter played, reveal hand — if no Supporter shown, draw a card
	if main.trainer_effects.ancient_ruins_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Ancient Ruins", "type": "Stadium", "text": "Reveal your hand. If there is no Supporter card there, draw a card."}})

	# ecard3-137 Mystery Zone: once per turn, if you have an Evolution card in hand, search for a basic Energy then return an Evolution card to your deck
	if main.trainer_effects.mystery_zone_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Mystery Zone", "type": "Stadium", "text": "Search your deck for a basic Energy card, then put an Evolution card from your hand into your deck."}})

	# ecard3-141 Underground Lake: once per turn, put an Omanyte or Kabuto from discard onto your Bench
	if main.trainer_effects.underground_lake_active(false):
		available_powers.append({"pokemon": null, "ability": {"name": "Underground Lake", "type": "Stadium", "text": "Put an Omanyte or Kabuto from your discard pile onto your Bench."}})

	# Brock's Ninetales Shapeshift discard option — only when a form is attached
	for p_check in all_pokemon:
		if p_check.shapeshift_form_card != null:
			available_powers.append({"pokemon": p_check, "ability": {"name": "Discard Form", "type": "Pokémon Power", "text": "Discard the Evolution card attached as a Shapeshift form."}})

	if available_powers.size() == 0:
		await main.show_message("No Pokemon Powers available!")
		return

	# Create power buttons
	main.main_buttons_container.visible = false
	main.attack_buttons_container.visible = true

	for power_info in available_powers:
		var pokemon = power_info["pokemon"]
		var ability = power_info["ability"]
		var btn = Button.new()
		if pokemon == null:
			# Stadium activation entry
			btn.text = "STADIUM - " + ability.get("name", "")
		else:
			btn.text = pokemon.metadata.get("name", "") + " - " + ability.get("name", "")
		btn.custom_minimum_size = Vector2(450, 50)
		btn.theme = main.theme_blue
		main.attack_buttons_container.add_child(btn)
		btn.pressed.connect(activate_power.bind(pokemon, ability))

# Activates a specific Pokemon Power

func activate_power(pokemon: card_object, ability: Dictionary) -> void:
	main.hide_attack_buttons()
	_ensure_power_dispatch_ready()
	var ability_name = ability.get("name", "")
	if _power_dispatch.has(ability_name):
		await _power_dispatch[ability_name].call(pokemon)
		return
	await main.show_message("Power not implemented: " + ability_name)

# Damage Swap (Alakazam): Move 1 damage counter between your pokemon

func power_damage_swap(alakazam: card_object) -> void:
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	await main.show_message("DAMAGE SWAP: Move damage counters between your Pokemon")
	if main._should_bail(): return
	
	var keep_swapping = true
	while keep_swapping:
		# Select source (pokemon with damage)
		var sources = []
		for p in all_pokemon:
			if p.current_hp < int(p.metadata.get("hp", "0")):
				sources.append(p)
		if sources.size() == 0:
			await main.show_message("No Pokemon with damage!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "DAMAGE SWAP - SOURCE", "Select a Pokemon to take damage FROM (or cancel to stop)", "SELECT", true)
		if main._should_bail(): return

		if source == null:
			break

		# Select destination (pokemon that can take 1 more without KO)
		var destinations = []
		for p in all_pokemon:
			if p == source: continue
			if p.current_hp > 10:
				destinations.append(p)

		if destinations.size() == 0:
			await main.show_message("No Pokemon can receive the damage counter!")
			if main._should_bail(): return
			break

		var dest = await main.card_ops.prompt_select_card(destinations, "DAMAGE SWAP - DESTINATION", "Select a Pokemon to move damage TO", "MOVE", true)
		if main._should_bail(): return

		if dest == null:
			break
		
		# Move 1 damage counter
		source.current_hp += 10
		dest.current_hp -= 10
		main.display_hp_circles_above_align(main.player_active_pokemon, false)
		main.display_pokemon(false)
		await main.show_message("Moved 1 damage counter from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Rain Dance (Blastoise): Attach Water Energy from hand to Water Pokemon

func power_rain_dance(blastoise: card_object) -> void:
	await main.show_message("RAIN DANCE: Attach Water Energy to Water Pokemon!")
	if main._should_bail(): return
	
	var keep_going = true
	while keep_going:
		# Find Water Energy in hand
		var water_energies = []
		for card in main.player_hand:
			if card.metadata.get("supertype", "").to_lower() == "energy":
				if "Water" in card.metadata.get("name", ""):
					water_energies.append(card)
		
		if water_energies.size() == 0:
			await main.show_message("No Water Energy in hand!")
			if main._should_bail(): return
			break
		
		# Find Water Pokemon
		var water_pokemon = []
		if main.player_active_pokemon != null and "Water" in main.player_active_pokemon.metadata.get("types", []):
			water_pokemon.append(main.player_active_pokemon)
		for bp in main.player_bench:
			if "Water" in bp.metadata.get("types", []):
				water_pokemon.append(bp)
		
		if water_pokemon.size() == 0:
			await main.show_message("No Water Pokemon in play!")
			if main._should_bail(): return
			break
		
		# Select target
		var target = await main.card_ops.prompt_select_card(water_pokemon, "RAIN DANCE", "Select a Water Pokemon to attach energy to (cancel to stop)", "ATTACH", true)
		if main._should_bail(): return
		
		if target == null:
			break
		
		# Attach the first water energy
		var energy = water_energies[0]
		main.player_hand.erase(energy)
		target.attached_energies.append(energy)
		main.refresh_hand_display(false)
		main.display_active_pokemon_energies(false)
		await main.show_message("Attached Water Energy to " + target.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Energy Trans (Venusaur): Move Grass Energy between your Pokemon

func power_energy_trans(venusaur: card_object) -> void:
	await main.show_message("ENERGY TRANS: Move Grass Energy between your Pokemon!")
	if main._should_bail(): return
	
	var keep_going = true
	while keep_going:
		# Find pokemon with Grass Energy attached
		var all_pokemon = []
		if main.player_active_pokemon != null: all_pokemon.append(main.player_active_pokemon)
		all_pokemon.append_array(main.player_bench)
		
		var sources = []
		for p in all_pokemon:
			for e in p.attached_energies:
				if "Grass" in main.get_energy_provided_by_card(e):
					if p not in sources:
						sources.append(p)
		
		if sources.size() == 0:
			await main.show_message("No Pokemon with Grass Energy!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "ENERGY TRANS - SOURCE", "Select Pokemon to take Grass Energy from (cancel to stop)", "SELECT", true)
		if main._should_bail(): return

		if source == null:
			break

		# Find the grass energy to move
		var grass_energy: card_object = null
		for e in source.attached_energies:
			if "Grass" in main.get_energy_provided_by_card(e):
				grass_energy = e
				break
		if grass_energy == null:
			break

		# Select destination
		var destinations = all_pokemon.filter(func(p): return p != source)
		if destinations.size() == 0:
			break

		var dest = await main.card_ops.prompt_select_card(destinations, "ENERGY TRANS - DESTINATION", "Select Pokemon to move Grass Energy to", "MOVE", true)
		if main._should_bail(): return

		if dest == null:
			break
		
		source.attached_energies.erase(grass_energy)
		dest.attached_energies.append(grass_energy)
		main.display_active_pokemon_energies(false)
		await main.show_message("Moved Grass Energy from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")
		if main._should_bail(): return

# Buzzap (Electrode): KO Electrode, attach as energy to another pokemon

func power_buzzap(electrode: card_object) -> void:
	# Cannot use if Electrode is the last pokemon
	var total_pokemon = (1 if main.player_active_pokemon != null else 0) + main.player_bench.size()
	if total_pokemon <= 1:
		await main.show_message("Cannot use Buzzap - Electrode is your last Pokemon!")
		if main._should_bail(): return
		return
	
	await main.show_message("BUZZAP: Electrode will be Knocked Out and become Energy!")
	if main._should_bail(): return
	
	# Select energy type
	var energy_types = ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Colorless"]
	# Use simple message-based selection for type
	# For simplicity, create a selection of fake energy cards
	var type_options = []
	for etype in energy_types:
		# Create a temporary card_object to represent each type
		var temp = card_object.new("base1-96", {"name": etype + " Energy", "supertype": "Energy"})
		type_options.append(temp)
	
	main.energy_type_selection_active = true
	main.show_enlarged_array_selection_mode(type_options)
	main.header_label.text = "BUZZAP - CHOOSE ENERGY TYPE"
	main.hint_label.text = "Select what type of Energy Electrode will become"
	main.action_button.text = "SELECT TYPE"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	main.cancel_button.visible = true
	await main.energy_type_selected
	if main._should_bail(): return
	var chosen_type = ""
	if main.selected_card_for_action != null:
		chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "")
	main.energy_type_selection_active = false
	main.hide_selection_mode_display_main()
	
	# Temp type_options are RefCounted and will be freed automatically when out of scope
	
	if chosen_type == "":
		return
	
	# Select target pokemon
	var targets = main.player_bench.duplicate()
	if main.player_active_pokemon != null and main.player_active_pokemon != electrode:
		targets.append(main.player_active_pokemon)
	targets.erase(electrode)
	
	if targets.size() == 0:
		return
	
	var target = await main.card_ops.prompt_select_card(targets, "BUZZAP - ATTACH TO", "Select a Pokemon to attach Electrode-Energy to", "ATTACH", false)
	if main._should_bail(): return
	
	if target == null:
		return
	
	# KO Electrode (prize will be awarded via normal knockout flow)
	electrode.current_hp = 0
	
	# Create the electrode-as-energy token
	var electrode_energy = card_object.new(electrode.uid, electrode.metadata)
	electrode_energy.is_electrode_energy = true
	electrode_energy.electrode_energy_type = chosen_type
	target.attached_energies.append(electrode_energy)
	
	main.display_active_pokemon_energies(false)
	await main.show_message("Electrode became " + chosen_type + " Energy!")
	if main._should_bail(): return
	
	# Process the knockout
	await main.check_all_knockouts()
	if main._should_bail(): return

# Discard bench token (Clefairy Doll voluntary discard)

func power_bench_token_discard(token: card_object) -> void:
	var was_active = (token == main.player_active_pokemon)
	
	if was_active:
		# Remove from active slot
		main.player_active_pokemon = null
	else:
		main.player_bench.erase(token)
	
	main.send_card_to_discard(token, false)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	await main.show_message(token.metadata.get("name", "") + " was voluntarily discarded!")
	if main._should_bail(): return
	
	# If it was active, force a bench replacement (no prize awarded)
	if was_active:
		if main.player_bench.size() == 0:
			await main.show_message("No Pokemon remaining!")
			if main._should_bail(): return
			main.game_end_logic(true)  # true = player loses
			return
		main.knockout_bench_selection_active = true
		main.show_enlarged_array_selection_mode(main.player_bench)
		main.cancel_button.visible = false
		main.header_label.text = "CHOOSE NEW ACTIVE POKEMON"
		main.hint_label.text = "Your active was discarded - select a replacement"
		main.action_button.text = "SET ACTIVE"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		await main.knockout_replacement_chosen
		if main._should_bail(): return
		main.display_active_pokemon_energies(false)



############################################### Section K: JUNGLE SET POWERS ###############################################################

# Get retreat cost reduction from Dodrio Retreat Aid
func get_retreat_cost_reduction(is_opponent: bool) -> int:
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var reduction = 0
	for bp in bench:
		var abilities = bp.metadata.get("abilities", [])
		for ab in abilities:
			if ab.get("name", "") == "Retreat Aid":
				if not is_power_blocked_by_status(bp):
					reduction += 1
					print("RETREAT AID: Dodrio reduces retreat cost by 1")
	return reduction

# Shift (Venomoth): Change Venomoth's type to match another Pokemon in play
func power_shift(venomoth: card_object) -> void:
	if is_power_blocked_by_status(venomoth):
		await main.show_message("SHIFT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if venomoth.power_used_this_turn:
		await main.show_message("SHIFT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Find all unique types from pokemon in play (excluding Colorless)
	var all_pokemon = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	var available_types: Array = []
	for p in all_pokemon:
		for ptype in p.metadata.get("types", []):
			if ptype != "Colorless" and ptype not in available_types:
				available_types.append(ptype)
	
	if available_types.size() == 0:
		await main.show_message("NO TYPES AVAILABLE TO SHIFT TO!")
		if main._should_bail(): return
		return
	
	# Create type selection using energy card representations
	var type_options = []
	for etype in available_types:
		var temp = card_object.new("base1-96", {"name": etype + " Energy", "supertype": "Energy"})
		type_options.append(temp)
	
	main.energy_type_selection_active = true
	main.show_enlarged_array_selection_mode(type_options)
	main.cancel_button.visible = true
	main.header_label.text = "SHIFT: CHOOSE NEW TYPE"
	main.hint_label.text = "Select the type Venomoth will become"
	main.action_button.text = "SHIFT"
	main.action_button.disabled = true
	main.action_button.theme = main.theme_disabled
	await main.energy_type_selected
	if main._should_bail(): return
	var chosen_type = ""
	if main.selected_card_for_action != null:
		chosen_type = main.selected_card_for_action.metadata.get("name", "").replace(" Energy", "")
	main.energy_type_selection_active = false
	main.hide_selection_mode_display_main()
	
	if chosen_type == "":
		return
	
	venomoth.temporary_type = chosen_type
	venomoth.power_used_this_turn = true
	await main.show_message("VENOMOTH SHIFTED TO " + chosen_type.to_upper() + " TYPE!")
	if main._should_bail(): return
	print("POWER USED: Shift -> ", chosen_type)

# Heal (Vileplume): Flip coin, heads = remove 1 damage counter from 1 of your Pokemon
func power_heal_vileplume(vileplume: card_object) -> void:
	if is_power_blocked_by_status(vileplume):
		await main.show_message("HEAL IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if vileplume.power_used_this_turn:
		await main.show_message("HEAL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	vileplume.power_used_this_turn = true
	
	await main.show_message("HEAL: FLIPPING COIN...")
	if main._should_bail(): return
	# Activated only via the player's power menu — player flips.
	var coin = await main.flip_coin(false, false)
	
	if not coin:
		await main.show_message("TAILS! HEAL FAILED!")
		if main._should_bail(): return
		return
	
	# Find pokemon with damage
	var damaged = []
	if main.player_active_pokemon != null and main.player_active_pokemon.current_hp < int(main.player_active_pokemon.metadata.get("hp", "0")):
		damaged.append(main.player_active_pokemon)
	for bp in main.player_bench:
		if bp.current_hp < int(bp.metadata.get("hp", "0")):
			damaged.append(bp)
	
	if damaged.size() == 0:
		await main.show_message("NO POKEMON WITH DAMAGE!")
		if main._should_bail(): return
		return
	
	var target = await main.card_ops.prompt_select_card(damaged, "HEAL: CHOOSE POKEMON", "Select a Pokemon to remove 1 damage counter from", "HEAL", false)
	if main._should_bail(): return
	
	if target != null:
		# MATCH EFFECTS: no_healing / healing_multiplier gate
		var rule_heal = main.match_effects.modify_heal_amount(10, main.match_effects.is_card_on_opponent_side(target))
		if rule_heal <= 0:
			await main.show_message("SPECIAL MATCH RULE: HEALING IS BLOCKED!")
			if main._should_bail(): return
			return
		target.current_hp = min(int(target.metadata.get("hp", "0")), target.current_hp + rule_heal)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		main.display_hp_circles_above_align(target, false)
		await main.show_message("HEALED " + str(rule_heal) + " HP FROM " + target.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("POWER USED: Vileplume Heal on ", target.metadata.get("name", ""))

# Peek (Mankey): Look at top card of either deck, random card from opponent hand, or a prize card
func power_peek(mankey: card_object) -> void:
	if is_power_blocked_by_status(mankey):
		await main.show_message("PEEK IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if mankey.power_used_this_turn:
		await main.show_message("PEEK ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	mankey.power_used_this_turn = true
	
	# Create selection options
	main.special_attack_selection_active = true
	main.buttons_only_blocker.visible = true
	main.attack_buttons_container.visible = true
	main.main_buttons_container.visible = false
	for child in main.attack_buttons_container.get_children():
		if child.name == "cancel_attack_mode_button":
			child.visible = false
			continue
		child.queue_free()
	
	var options = ["Top of Your Deck", "Top of Opponent\'s Deck", "Random from Opponent\'s Hand", "One of Your Prizes", "One of Opponent\'s Prizes"]
	for i in range(options.size()):
		var btn = Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(400, 45)
		btn.theme = main.theme_blue
		main.attack_buttons_container.add_child(btn)
		btn.pressed.connect(func(): main.special_attack_selected.emit(i))
	
	var selected = await main.special_attack_selected
	
	for child in main.attack_buttons_container.get_children():
		if child.name == "cancel_attack_mode_button":
			child.visible = true
			continue
		child.queue_free()
	main.attack_buttons_container.visible = false
	main.main_buttons_container.visible = true
	main.special_attack_selection_active = false
	main.buttons_only_blocker.visible = false
	
	var peeked_card: card_object = null
	var peek_source = ""
	
	match selected:
		0: # Top of your deck
			if main.player_deck.size() > 0:
				peeked_card = main.player_deck[0]
				peek_source = "TOP OF YOUR DECK"
		1: # Top of opponent's deck
			if main.opponent_deck.size() > 0:
				peeked_card = main.opponent_deck[0]
				peek_source = "TOP OF OPPONENT\'S DECK"
		2: # Random from opponent's hand
			if main.opponent_hand.size() > 0:
				var rand_idx = randi() % main.opponent_hand.size()
				peeked_card = main.opponent_hand[rand_idx]
				peek_source = "OPPONENT\'S HAND"
		3: # One of your prizes
			if main.player_prize_cards.size() > 0:
				peeked_card = main.player_prize_cards[0]
				peek_source = "YOUR PRIZES"
		4: # One of opponent's prizes
			if main.opponent_prize_cards.size() > 0:
				peeked_card = main.opponent_prize_cards[0]
				peek_source = "OPPONENT\'S PRIZES"
	
	if peeked_card != null:
		# Show the card briefly
		main.show_enlarged_array_selection_mode([peeked_card])
		main.header_label.text = "PEEK: " + peek_source
		main.hint_label.text = peeked_card.metadata.get("name", "Unknown")
		main.action_button.text = "OK"
		main.action_button.disabled = false
		main.cancel_button.visible = false
		await main.trainer_target_selected
		if main._should_bail(): return
		main.hide_selection_mode_display_main()
		print("POWER USED: Peek at ", peek_source, " -> ", peeked_card.metadata.get("name", ""))
	else:
		await main.show_message("NOTHING TO PEEK AT!")
		if main._should_bail(): return

######################################################################################################################################################
############################################## BASE3 (FOSSIL) POWERS AND BODIES ######################################################################
######################################################################################################################################################

# STEP IN (Dragonite): Switch from bench to active. Once per turn. Must be on bench.
func power_step_in(dragonite: card_object) -> void:
	if dragonite.power_used_this_turn:
		await main.show_message("STEP IN ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if dragonite.current_location != "bench":
		await main.show_message("DRAGONITE MUST BE ON THE BENCH!")
		if main._should_bail(): return
		return
	
	if dragonite not in main.player_bench:
		await main.show_message("DRAGONITE MUST BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	
	dragonite.power_used_this_turn = true
	
	var old_active = main.player_active_pokemon
	
	await main.show_message("STEP IN: DRAGONITE SWITCHES IN!")
	if main._should_bail(): return
	
	await main.animate_retreat(old_active, dragonite, [], false)
	if main._should_bail(): return
	
	main.player_bench.erase(dragonite)
	main.player_bench.append(old_active)
	old_active.current_location = "bench"
	dragonite.current_location = "active"
	main.player_active_pokemon = dragonite
	main.clear_all_statuses(old_active, false)
	
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	print("STEP IN: Dragonite switched in, ", old_active.metadata.get("name", ""), " moved to bench")

# CURSE (Gengar): Move 1 damage counter from one opponent pokemon to another. Once per turn.
func power_curse(gengar: card_object) -> void:
	if gengar.power_used_this_turn:
		await main.show_message("CURSE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Get all opponent's pokemon with damage
	var opponent_pokemon: Array = []
	if main.opponent_active_pokemon != null:
		opponent_pokemon.append(main.opponent_active_pokemon)
	opponent_pokemon.append_array(main.opponent_bench)
	
	var sources: Array = []
	for p in opponent_pokemon:
		if p.current_hp < int(p.metadata.get("hp", "0")):
			sources.append(p)
	
	if sources.size() == 0:
		await main.show_message("NO OPPONENT POKEMON HAVE DAMAGE!")
		if main._should_bail(): return
		return
	
	if opponent_pokemon.size() < 2:
		await main.show_message("OPPONENT NEEDS 2+ POKEMON FOR CURSE!")
		if main._should_bail(): return
		return
	
	# Select source (take damage FROM)
	var source = await main.card_ops.prompt_select_card(sources, "CURSE: SELECT SOURCE", "Remove 1 damage counter from this Pokemon", "SELECT", true)
	if main._should_bail(): return

	if source == null:
		return

	# Select destination (move damage TO) — can KO
	var destinations: Array = []
	for p in opponent_pokemon:
		if p != source:
			destinations.append(p)

	if destinations.size() == 0:
		return

	var dest = await main.card_ops.prompt_select_card(destinations, "CURSE: SELECT TARGET", "Move the damage counter TO this Pokemon (can KO)", "CURSE", true)
	if main._should_bail(): return

	if dest == null:
		return
	
	gengar.power_used_this_turn = true
	source.current_hp = min(int(source.metadata.get("hp", "0")), source.current_hp + 10)
	dest.current_hp = max(0, dest.current_hp - 10)
	
	# Determine is_opponent for each pokemon for display
	var source_is_opp = (source == main.opponent_active_pokemon or source in main.opponent_bench)
	var dest_is_opp = (dest == main.opponent_active_pokemon or dest in main.opponent_bench)
	main.display_hp_circles_above_align(source, source_is_opp)
	main.display_hp_circles_above_align(dest, dest_is_opp)
	
	await main.show_message("CURSE: MOVED DAMAGE FROM " + source.metadata.get("name", "").to_upper() + " TO " + dest.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("CURSE: Moved 1 damage counter from ", source.metadata.get("name", ""), " to ", dest.metadata.get("name", ""))
	
	# Check if the curse KO'd the target
	if dest.current_hp <= 0:
		await main.check_all_knockouts()
		if main._should_bail(): return

# STRANGE BEHAVIOR (Slowbro): Move damage TO Slowbro from your other pokemon, as often as you like
func power_strange_behavior(slowbro: card_object) -> void:
	if is_power_blocked_by_status(slowbro):
		await main.show_message("STRANGE BEHAVIOR BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	await main.show_message("STRANGE BEHAVIOR: MOVE DAMAGE TO SLOWBRO")
	if main._should_bail(): return
	
	var keep_moving = true
	while keep_moving:
		# Find player pokemon with damage (excluding Slowbro)
		var all_pokemon: Array = []
		if main.player_active_pokemon != null:
			all_pokemon.append(main.player_active_pokemon)
		all_pokemon.append_array(main.player_bench)
		
		var sources: Array = []
		for p in all_pokemon:
			if p == slowbro:
				continue
			if p.current_hp < int(p.metadata.get("hp", "0")):
				sources.append(p)
		
		if sources.size() == 0:
			await main.show_message("NO OTHER POKEMON HAVE DAMAGE!")
			if main._should_bail(): return
			break
		
		# Check if Slowbro would be KO'd
		if slowbro.current_hp <= 10:
			await main.show_message("SLOWBRO CAN'T TAKE MORE DAMAGE WITHOUT BEING KO'D!")
			if main._should_bail(): return
			break
		
		var source = await main.card_ops.prompt_select_card(sources, "STRANGE BEHAVIOR", "Move 1 damage counter TO Slowbro from this Pokemon (cancel to stop)", "MOVE DAMAGE", true)
		if main._should_bail(): return

		if source == null:
			break
		
		source.current_hp = min(int(source.metadata.get("hp", "0")), source.current_hp + 10)
		slowbro.current_hp = max(0, slowbro.current_hp - 10)
		
		var source_is_opp = (source == main.opponent_active_pokemon or source in main.opponent_bench)
		main.display_hp_circles_above_align(source, source_is_opp)
		var slowbro_is_opp = (slowbro == main.opponent_active_pokemon or slowbro in main.opponent_bench)
		main.display_hp_circles_above_align(slowbro, slowbro_is_opp)
		
		print("STRANGE BEHAVIOR: Moved damage from ", source.metadata.get("name", ""), " to Slowbro")

# COWARDICE (Tentacool): Return Tentacool to hand. Can't use on placement turn or with status.
func power_cowardice(tentacool: card_object) -> void:
	if is_power_blocked_by_status(tentacool):
		await main.show_message("COWARDICE BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	
	if tentacool.placed_on_field_this_turn:
		await main.show_message("CAN'T USE COWARDICE ON THE TURN TENTACOOL WAS PLAYED!")
		if main._should_bail(): return
		return
	
	# Tentacool must be on bench or active
	var is_active = (tentacool == main.player_active_pokemon)
	
	if is_active and main.player_bench.size() == 0:
		await main.show_message("CAN'T RETURN ACTIVE WITH EMPTY BENCH!")
		if main._should_bail(): return
		return
	
	# Discard all attached cards
	var discard = main.player_discard_pile
	for e in tentacool.attached_energies:
		e.current_location = "discard"
		discard.append(e)
	tentacool.attached_energies.clear()
	for pre in tentacool.attached_pre_evolutions:
		pre.current_location = "discard"
		discard.append(pre)
	tentacool.attached_pre_evolutions.clear()
	for ac in tentacool.attached_cards:
		ac.current_location = "discard"
		discard.append(ac)
	tentacool.attached_cards.clear()
	
	# Return to hand
	if is_active:
		main.player_active_pokemon = null
		# Need to promote a bench pokemon
		tentacool.current_location = "hand"
		main.player_hand.append(tentacool)
		main.clear_all_statuses(tentacool, false)
		tentacool.pluspower_count = 0
		await main.show_message("COWARDICE: TENTACOOL RETURNED TO HAND!")
		if main._should_bail(): return
		# Handle post-knockout style replacement
		await main.handle_post_knockout(false)
		if main._should_bail(): return
	else:
		main.player_bench.erase(tentacool)
		tentacool.current_location = "hand"
		main.player_hand.append(tentacool)
		main.clear_all_statuses(tentacool, false)
		tentacool.pluspower_count = 0
		await main.show_message("COWARDICE: TENTACOOL RETURNED TO HAND!")
		if main._should_bail(): return
	
	main.display_pokemon(false)
	main.refresh_hand_display(false)
	main.display_active_pokemon_energies(false)
	main.update_discard_pile_display(false)
	print("COWARDICE: Tentacool returned to hand")

############################################### PASSIVE POWER/BODY HOOKS (called from main) #########################################################

# DITTO TRANSFORM: Apply/revert Transform based on active status
# Called after any switch, KO, or start of turn to keep Transform in sync
func update_ditto_transform(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var opposing_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	
	# Check if Toxic Gas shuts it down
	var toxic_gas = is_toxic_gas_active()
	
	# First: revert any benched Dittos that are still transformed
	for bp in bench:
		if bp != null and bp.is_ditto_transformed:
			bp.revert_ditto_transform()
			print("TRANSFORM: Reverted benched Ditto")
	
	# Second: handle active
	if active == null or opposing_active == null:
		return
	
	# Check if active is a Ditto with Transform
	var is_ditto = false
	var real_name = active.ditto_original_metadata.get("name", "") if active.is_ditto_transformed else active.metadata.get("name", "")
	if real_name == "Ditto":
		is_ditto = true
	if not active.is_ditto_transformed:
		# Check abilities on the current (untransformed) card
		for ability in active.metadata.get("abilities", []):
			if ability.get("name", "") == "Transform":
				is_ditto = true
				break
	
	if not is_ditto:
		return
	
	# Ditto is blocked by status (Asleep, Confused, Paralyzed)
	if active.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		if active.is_ditto_transformed:
			active.revert_ditto_transform()
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
			print("TRANSFORM: Reverted — Ditto has status condition")
		return
	
	# Toxic Gas blocks Transform
	if toxic_gas:
		if active.is_ditto_transformed:
			active.revert_ditto_transform()
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
			print("TRANSFORM: Reverted — Toxic Gas active")
		return
	
	# Check if already transformed into the current opposing active
	if active.is_ditto_transformed:
		if active.ditto_transform_uid == opposing_active.uid:
			# Already transformed into this exact card — no change needed
			return
		else:
			# Opposing active changed — revert and re-transform
			active.revert_ditto_transform()
	
	# Apply Transform: copy the opposing active's metadata
	active.apply_ditto_transform(opposing_active.metadata, opposing_active.uid)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	print("TRANSFORM: Ditto copied ", opposing_active.metadata.get("name", ""))

# Called when Ditto leaves play (KO, Scoop Up, Mr. Fuji, etc.) to ensure clean revert
func revert_ditto_if_needed(pokemon: card_object) -> void:
	if pokemon != null and pokemon.is_ditto_transformed:
		pokemon.revert_ditto_transform()
		print("TRANSFORM: Reverted Ditto leaving play")

# TRANSPARENCY (Haunter): When Haunter is attacked, flip coin. Heads = prevent all effects.
# Called BEFORE damage is applied. Returns true if attack is blocked.
func check_transparency(defender: card_object) -> bool:
	if defender == null:
		return false
	var abilities = defender.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Transparency":
			continue
		if is_power_blocked_by_status(defender):
			print("TRANSPARENCY: Blocked by status on ", defender.metadata.get("name", ""))
			return false
		# Check if Muk's Toxic Gas is active
		if is_toxic_gas_active():
			print("TRANSPARENCY: Blocked by Toxic Gas")
			return false
		# Defender (Haunter's controller) is the one flipping.
		var defender_is_opp: bool = defender == main.opponent_active_pokemon
		var coin = await main.flip_coin(false, defender_is_opp)
		if coin:
			await main.show_message("TRANSPARENCY: ATTACK BLOCKED!")
			if main._should_bail(): return true
			print("TRANSPARENCY: Blocked attack on Haunter (heads)")
			return true
		else:
			await main.show_message("TRANSPARENCY: TAILS! ATTACK HITS!")
			if main._should_bail(): return false
			print("TRANSPARENCY: Attack hits Haunter (tails)")
			return false
	return false

# KABUTO ARMOR (Kabuto): Halve incoming damage (rounded down to nearest 10)
# Called during damage calculation. Returns modified damage.
func apply_kabuto_armor(defender: card_object, damage: int) -> int:
	if defender == null:
		return damage
	var abilities = defender.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Kabuto Armor":
			continue
		if is_power_blocked_by_status(defender):
			print("KABUTO ARMOR: Blocked by status")
			return damage
		if is_toxic_gas_active():
			print("KABUTO ARMOR: Blocked by Toxic Gas")
			return damage
		var halved = int(floor(damage / 2.0 / 10.0)) * 10
		print("KABUTO ARMOR: Reduced ", damage, " -> ", halved)
		return halved
	return damage

# PREHISTORIC POWER (Aerodactyl): Block all evolution card plays
# Returns true if evolution should be blocked
func is_prehistoric_power_active() -> bool:
	# Check both sides for Aerodactyl with Prehistoric Power
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Prehistoric Power":
				continue
			if is_power_blocked_by_status(p):
				continue
			if is_toxic_gas_active():
				continue
			return true
	return false

# TOXIC GAS (Muk): Ignore all other Pokemon Powers
# Returns true if Toxic Gas is currently active
func is_toxic_gas_active() -> bool:
	# MATCH EFFECT: powers_blocked — all Powers/Bodies disabled for the whole match
	if main.match_effects.powers_blocked():
		return true
	# Goop Gas Attack trainer also disables all powers
	if main.goop_gas_active:
		return true
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Toxic Gas":
				continue
			# Toxic Gas is blocked by its own status conditions
			if p.special_condition in ["Paralyzed", "Asleep", "Confused"]:
				continue
			return true
	return false

# CLAIRVOYANCE (Omanyte): Opponent plays with hand face up
# Returns true if Clairvoyance is active (used for UI display)
func is_clairvoyance_active() -> bool:
	# Check player's side for Omanyte with Clairvoyance
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	for p in all_pokemon:
		var abilities = p.metadata.get("abilities", [])
		for ability in abilities:
			if ability.get("name", "") != "Clairvoyance":
				continue
			if is_power_blocked_by_status(p):
				continue
			if is_toxic_gas_active():
				continue
			return true
	return false

############################################### Section H: CPU POWER ACTIVATION ######################################################################

# CPU activates beneficial powers at start of turn

func cpu_phase_activate_powers() -> void:
	# Note: Toxic Gas blocks individual powers. Each power section checks is_toxic_gas_active()
	# or is_power_blocked_by_status() as appropriate. Rain Dance/Energy Trans/etc. are also
	# blocked by Toxic Gas since they are Pokemon Powers.
	var toxic_gas = is_toxic_gas_active()

	# basep-41 Lucky Stadium: CPU always flips for a free draw
	if main.trainer_effects.basep_lucky_stadium_has_target(true):
		await main.trainer_effects.basep_lucky_stadium_activate(true)
		if main._should_bail(): return

	# neo3-61 Healing Field: CPU uses if its Active pokemon has damage
	if main.trainer_effects.neo3_healing_field_active():
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.current_hp < main.opponent_active_pokemon.get_max_hp():
			await main.trainer_effects.neo3_healing_field_activate(true)
			if main._should_bail(): return

	# ecard2-118 Apricorn Forest: CPU always uses when available (free chance at a bench Pokemon)
	if main.trainer_effects.apricorn_forest_active(true):
		await main.trainer_effects.apricorn_forest_activate(true)
		if main._should_bail(): return

	# ecard2-138 Undersea Ruins: CPU only devolves if the resulting Pre-Evolution can still attack
	# usefully — heuristic: only devolve a Pokemon that's heavily damaged relative to the
	# pre-evolution's own max HP (protecting a low-HP body isn't worth it, so skip that case)
	if main.trainer_effects.undersea_ruins_active(true):
		var active2 = main.opponent_active_pokemon
		var bench2 = main.opponent_bench
		var all_own2: Array = []
		if active2 != null: all_own2.append(active2)
		all_own2.append_array(bench2)
		var worth_it = false
		for p in all_own2:
			if p.attached_pre_evolutions.size() > 0 and p.current_hp < p.get_max_hp() * 0.4:
				worth_it = true
				break
		if worth_it:
			await main.trainer_effects.undersea_ruins_activate(true)
			if main._should_bail(): return

	# ecard2-139 Power Plant: CPU uses if it has a spare basic Energy card to trade away
	if main.trainer_effects.power_plant_active(true):
		var hand_basics = main.opponent_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
		if main.opponent_hand.size() > 1 and hand_basics.size() > 0:
			await main.trainer_effects.power_plant_activate(true)
			if main._should_bail(): return

	# ecard3-119 Ancient Ruins: CPU always uses when available (free chance at a card, no real cost)
	if main.trainer_effects.ancient_ruins_active(true):
		await main.trainer_effects.ancient_ruins_activate(true)
		if main._should_bail(): return

	# ecard3-137 Mystery Zone: CPU uses if it has a spare Evolution card in hand it can afford to lose
	if main.trainer_effects.mystery_zone_active(true):
		await main.trainer_effects.mystery_zone_activate(true)
		if main._should_bail(): return

	# ecard3-141 Underground Lake: CPU always uses when available (free bench Pokemon)
	if main.trainer_effects.underground_lake_active(true):
		await main.trainer_effects.underground_lake_activate(true)
		if main._should_bail(): return

	# basep-5 Special Delivery (Dragonite): CPU draws if deck not empty
	if not toxic_gas:
		var dragonite = _find_cpu_pokemon_with_power("Special Delivery")
		if dragonite != null and not is_power_blocked_by_status(dragonite) and not dragonite.power_used_this_turn:
			if main.opponent_deck.size() > 0:
				await power_special_delivery(dragonite)
				if main._should_bail(): return

	# basep-11 Chain Reaction (Eevee): CPU evolves all Eevees if it has evolution cards in hand
	if not toxic_gas:
		var cr_eevee = _find_cpu_pokemon_with_power("Chain Reaction")
		if cr_eevee != null and not is_power_blocked_by_status(cr_eevee) and not cr_eevee.power_used_this_turn:
			var has_eevee_evo: bool = false
			for c in main.opponent_hand:
				if c.metadata.get("evolvesFrom", "") == "Eevee":
					has_eevee_evo = true
					break
			if has_eevee_evo:
				await power_chain_reaction(cr_eevee)
				if main._should_bail(): return

	# basep-13 Solar Power (Venusaur): CPU clears status if own active or opponent's active has status
	if not toxic_gas:
		var venusaur = _find_cpu_pokemon_with_power("Solar Power")
		if venusaur != null and not is_power_blocked_by_status(venusaur) and not venusaur.power_used_this_turn:
			var own_afflicted = main.opponent_active_pokemon != null and (main.opponent_active_pokemon.special_condition != "" or main.opponent_active_pokemon.is_poisoned)
			var opp_afflicted = main.player_active_pokemon != null and (main.player_active_pokemon.special_condition != "" or main.player_active_pokemon.is_poisoned)
			if own_afflicted or opp_afflicted:
				await power_solar_power(venusaur)
				if main._should_bail(): return

	# GYM1-107 Celadon City Gym (Stadium): activate if CPU has a status-afflicted Erika pokemon with energy.
	# Not affected by toxic_gas (Stadium card, not a Pokemon Power).
	if main.trainer_effects.gym1_celadon_has_target(true):
		await main.trainer_effects.gym1_celadon_activate(true)
		if main._should_bail(): return

	# GYM2-114 Fuchsia City Gym (Stadium): activate if CPU has a damaged Koga pokemon worth recovering.
	# Heuristic: only fire if a Koga pokemon has >= 40 damage (worth the deck recycle / coin flip risk).
	if main.trainer_effects.gym2_fuchsia_has_target(true):
		var fuchsia_should_use = false
		var fuchsia_candidates: Array = []
		if main.opponent_active_pokemon != null and "Koga" in main.opponent_active_pokemon.metadata.get("name", ""):
			fuchsia_candidates.append(main.opponent_active_pokemon)
		for bp in main.opponent_bench:
			if "Koga" in bp.metadata.get("name", ""):
				fuchsia_candidates.append(bp)
		for p in fuchsia_candidates:
			var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
			if dmg >= 40:
				fuchsia_should_use = true
				break
		if fuchsia_should_use:
			await main.trainer_effects.gym2_fuchsia_activate(true)
			if main._should_bail(): return

	# GYM2-122 Saffron City Gym (Stadium): return basic Energy to hand from Sabrina pokemon.
	# Heuristic: only use if CPU has an OVER-energized Sabrina pokemon (more attached than needed for any attack).
	while main.trainer_effects.gym2_saffron_has_target(true):
		var saffron_used = false
		var active = main.opponent_active_pokemon
		var sabrina_targets: Array = []
		if active != null and "Sabrina" in active.metadata.get("name", ""):
			sabrina_targets.append(active)
		for bp in main.opponent_bench:
			if "Sabrina" in bp.metadata.get("name", ""):
				sabrina_targets.append(bp)
		var any_excess = false
		for p in sabrina_targets:
			# Excess energy = more attached than the highest-cost attack
			var max_cost = 0
			for atk in p.metadata.get("attacks", []):
				var c = atk.get("cost", []).size()
				if c > max_cost:
					max_cost = c
			var basics = 0
			for e in p.attached_energies:
				if main.is_basic_energy_card(e):
					basics += 1
			if basics > max_cost:
				any_excess = true
				break
		if not any_excess:
			break
		await main.trainer_effects.gym2_saffron_activate(true)
		if main._should_bail(): return
		saffron_used = true

	# Rain Dance: attach all Water Energy to Water Pokemon
	var blastoise = _find_cpu_pokemon_with_power("Rain Dance")
	if blastoise != null and not is_power_blocked_by_status(blastoise) and not toxic_gas:
		var keep_going = true
		while keep_going:
			keep_going = false
			var water_energy: card_object = null
			for card in main.opponent_hand:
				if card.metadata.get("supertype", "").to_lower() == "energy" and "Water" in card.metadata.get("name", ""):
					water_energy = card
					break
			if water_energy == null:
				break
			# Find best Water Pokemon target
			var best_target: card_object = null
			var best_unmet = 999
			var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
			for p in all_pokemon:
				if "Water" not in p.metadata.get("types", []):
					continue
				for attack in p.metadata.get("attacks", []):
					var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
					if unmet > 0 and unmet < best_unmet:
						best_unmet = unmet
						best_target = p
			if best_target == null:
				break
			main.opponent_hand.erase(water_energy)
			best_target.attached_energies.append(water_energy)
			await main.show_message("Rain Dance: Attached Water Energy to " + best_target.metadata.get("name", "") + "!")
			if main._should_bail(): return
			main.refresh_hand_display(true)
			main.display_active_pokemon_energies(true)
			keep_going = true
	
	# Energy Trans: consolidate Grass Energy to the pokemon that needs it most
	var venusaur = _find_cpu_pokemon_with_power("Energy Trans")
	if venusaur != null and not is_power_blocked_by_status(venusaur) and not toxic_gas:
		# Find pokemon that needs Grass Energy most
		var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
		var best_target: card_object = null
		var best_unmet = 999
		for p in all_pokemon:
			for attack in p.metadata.get("attacks", []):
				var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
				if unmet > 0 and unmet < best_unmet:
					for req in attack.get("cost", []):
						if req == "Grass":
							best_unmet = unmet
							best_target = p
							break
		if best_target != null:
			# Find a source with spare Grass Energy
			for p in all_pokemon:
				if p == best_target:
					continue
				for e in p.attached_energies.duplicate():
					if "Grass" in main.get_energy_provided_by_card(e):
						p.attached_energies.erase(e)
						best_target.attached_energies.append(e)
						await main.show_message("Energy Trans: Moved Grass Energy to " + best_target.metadata.get("name", "") + "!")
						if main._should_bail(): return
						main.display_active_pokemon_energies(true)
						break
	
	# Vileplume Heal: CPU tries to heal damaged pokemon
	var vileplume = _find_cpu_pokemon_with_power("Heal")
	if vileplume != null and not is_power_blocked_by_status(vileplume) and not toxic_gas and not vileplume.power_used_this_turn:
		vileplume.power_used_this_turn = true
		# Only use if there's damage to heal
		var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
		var most_damaged: card_object = null
		var most_damage = 0
		for p in all_cpu:
			var dmg = int(p.metadata.get("hp", "0")) - p.current_hp
			if dmg > most_damage:
				most_damage = dmg
				most_damaged = p
		if most_damaged != null and most_damage > 0:
			# CPU Vileplume Heal — opponent flips.
			var coin = await main.flip_coin(false, true)
			if coin:
				most_damaged.current_hp = min(int(most_damaged.metadata.get("hp", "0")), most_damaged.current_hp + 10)
				main.display_hp_circles_above_align(most_damaged, true)
				await main.show_message("Vileplume Heal: Healed 10 HP from " + most_damaged.metadata.get("name", "") + "!")
				if main._should_bail(): return
			else:
				await main.show_message("Vileplume Heal: Tails! Failed!")
				if main._should_bail(): return
	
	# Venomoth Shift: CPU shifts to the type that gives best coverage
	var venomoth = _find_cpu_pokemon_with_power("Shift")
	if venomoth != null and not is_power_blocked_by_status(venomoth) and not toxic_gas and not venomoth.power_used_this_turn:
		# Shift to the type that the player's active is weak to
		var player_weaknesses = main.player_active_pokemon.metadata.get("weaknesses", []) if main.player_active_pokemon != null else []
		if player_weaknesses.size() > 0:
			var weak_type = player_weaknesses[0].get("type", "")
			if weak_type != "" and weak_type != "Colorless":
				venomoth.temporary_type = weak_type
				venomoth.power_used_this_turn = true
				await main.show_message("Venomoth Shift: Changed to " + weak_type + " type!")
				if main._should_bail(): return
	
	
	# Damage Swap: move damage off active to bench with most buffer
	var alakazam = _find_cpu_pokemon_with_power("Damage Swap")
	if alakazam != null and not is_power_blocked_by_status(alakazam) and not toxic_gas:
		var active = main.opponent_active_pokemon
		if active != null:
			var active_damage = int(active.metadata.get("hp", "0")) - active.current_hp
			while active_damage >= 10:
				# Find bench pokemon with most HP buffer
				var best_buffer: card_object = null
				var best_hp = 0
				for bp in main.opponent_bench:
					var buffer = bp.current_hp - 10
					if buffer > best_hp:
						best_hp = buffer
						best_buffer = bp
				if best_buffer == null or best_hp <= 0:
					break
				active.current_hp += 10
				best_buffer.current_hp -= 10
				active_damage -= 10
			main.display_hp_circles_above_align(main.opponent_active_pokemon, true)
	
	# Buzzap (Electrode): KO Electrode to become 2 energy of chosen type on another pokemon
	# CPU uses Buzzap when: another pokemon is 2+ energy short of attacking, Electrode is on bench,
	# and there are enough total pokemon to survive the prize loss
	var electrode_buzzap = _find_cpu_pokemon_with_power("Buzzap")
	if electrode_buzzap != null and not toxic_gas:
		if not is_power_blocked_by_status(electrode_buzzap):
			var total_pokemon = (1 if main.opponent_active_pokemon != null else 0) + main.opponent_bench.size()
			if total_pokemon > 1 and electrode_buzzap != main.opponent_active_pokemon:
				# Find a pokemon that needs 2+ energy to attack
				var best_target: card_object = null
				var best_type: String = ""
				var best_unmet = 0
				var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
				for p in all_cpu:
					if p == electrode_buzzap:
						continue
					for attack in p.metadata.get("attacks", []):
						var unmet = main.cpu_ai.get_unmet_energy_count(attack, p)
						if unmet >= 2 and unmet > best_unmet:
							# Find what type is needed most
							var cost = attack.get("cost", [])
							var type_counts = {}
							for c in cost:
								if c != "Colorless":
									type_counts[c] = type_counts.get(c, 0) + 1
							if type_counts.size() > 0:
								var needed_type = ""
								var needed_count = 0
								for t in type_counts:
									if type_counts[t] > needed_count:
										needed_count = type_counts[t]
										needed_type = t
								best_target = p
								best_type = needed_type
								best_unmet = unmet
							else:
								# All colorless cost — provide Lightning (Electrode's type)
								best_target = p
								best_type = "Lightning"
								best_unmet = unmet
				
				if best_target != null and best_type != "":
					# Execute Buzzap
					electrode_buzzap.current_hp = 0
					var electrode_energy = card_object.new(electrode_buzzap.uid, electrode_buzzap.metadata)
					electrode_energy.is_electrode_energy = true
					electrode_energy.electrode_energy_type = best_type
					best_target.attached_energies.append(electrode_energy)
					main.display_active_pokemon_energies(true)
					await main.show_message("Buzzap: Electrode became " + best_type + " Energy for " + best_target.metadata.get("name", "") + "!")
					if main._should_bail(): return
					await main.check_all_knockouts()
					if main._should_bail(): return
	
	# --- BASE3 POWERS ---
	
	# Step In (Dragonite): Switch to active if better than current active
	var dragonite = _find_cpu_bench_pokemon_with_power("Step In")
	if dragonite != null and not dragonite.power_used_this_turn:
		if not is_power_blocked_by_status(dragonite) and not is_toxic_gas_active():
			var active = main.opponent_active_pokemon
			if active != null:
				# Switch in if Dragonite has better attack readiness
				var dragonite_ready = false
				for attack in dragonite.metadata.get("attacks", []):
					if main.cpu_ai.get_unmet_energy_count(attack, dragonite) == 0:
						dragonite_ready = true
						break
				var active_hp_pct = float(active.current_hp) / float(int(active.metadata.get("hp", "1")))
				if dragonite_ready and active_hp_pct < 0.4:
					# Active is low, Dragonite is ready — switch
					dragonite.power_used_this_turn = true
					var old_active = main.opponent_active_pokemon
					main.opponent_bench.erase(dragonite)
					main.opponent_bench.append(old_active)
					old_active.current_location = "bench"
					dragonite.current_location = "active"
					main.opponent_active_pokemon = dragonite
					main.clear_all_statuses(old_active, true)
					main.display_pokemon(true)
					main.display_active_pokemon_energies(true)
					await main.show_message("Step In: Dragonite switches in!")
					if main._should_bail(): return
	
	# Curse (Gengar): Move damage to opponent's active for KO potential
	var gengar = _find_cpu_pokemon_with_power("Curse")
	if gengar != null and not gengar.power_used_this_turn:
		if not is_power_blocked_by_status(gengar) and not is_toxic_gas_active():
			var player_pokemon: Array = []
			if main.player_active_pokemon != null:
				player_pokemon.append(main.player_active_pokemon)
			player_pokemon.append_array(main.player_bench)
			
			# Find a source with damage that isn't the active
			var best_source: card_object = null
			var best_dest: card_object = null
			
			# Strategy: move damage TO the player's active if it helps KO
			if main.player_active_pokemon != null and main.player_active_pokemon.current_hp <= 10:
				# Active already almost dead, skip
				pass
			elif main.player_active_pokemon != null:
				# Find source with damage on bench
				for bp in main.player_bench:
					if bp.current_hp < int(bp.metadata.get("hp", "0")):
						best_source = bp
						best_dest = main.player_active_pokemon
						break
			
			if best_source != null and best_dest != null:
				gengar.power_used_this_turn = true
				best_source.current_hp = min(int(best_source.metadata.get("hp", "0")), best_source.current_hp + 10)
				best_dest.current_hp = max(0, best_dest.current_hp - 10)
				main.display_hp_circles_above_align(best_source, false)
				main.display_hp_circles_above_align(best_dest, false)
				await main.show_message("Curse: Moved damage to " + best_dest.metadata.get("name", "") + "!")
				if main._should_bail(): return
				if best_dest.current_hp <= 0:
					await main.check_all_knockouts()
					if main._should_bail(): return
	
	# Strange Behavior (Slowbro): Move damage off CPU active to Slowbro
	var slowbro = _find_cpu_pokemon_with_power("Strange Behavior")
	if slowbro != null and not is_power_blocked_by_status(slowbro) and not is_toxic_gas_active():
		var active = main.opponent_active_pokemon
		if active != null and active != slowbro:
			var active_damage = int(active.metadata.get("hp", "0")) - active.current_hp
			while active_damage >= 10 and slowbro.current_hp > 10:
				active.current_hp += 10
				slowbro.current_hp -= 10
				active_damage -= 10
			main.display_hp_circles_above_align(active, true)
			var slowbro_is_active = (slowbro == main.opponent_active_pokemon)
			main.display_hp_circles_above_align(slowbro, true)
	
	# Cowardice (Tentacool): CPU returns Tentacool if badly damaged
	var tentacool = _find_cpu_pokemon_with_power("Cowardice")
	if tentacool != null and not is_power_blocked_by_status(tentacool) and not is_toxic_gas_active():
		if not tentacool.placed_on_field_this_turn:
			var max_hp = int(tentacool.metadata.get("hp", "0"))
			if tentacool.current_hp <= max_hp / 2:
				# Return to hand
				var discard = main.opponent_discard_pile
				for e in tentacool.attached_energies:
					e.current_location = "discard"
					discard.append(e)
				tentacool.attached_energies.clear()
				for pre in tentacool.attached_pre_evolutions:
					pre.current_location = "discard"
					discard.append(pre)
				tentacool.attached_pre_evolutions.clear()
				for ac in tentacool.attached_cards:
					ac.current_location = "discard"
					discard.append(ac)
				tentacool.attached_cards.clear()

				var is_active = (tentacool == main.opponent_active_pokemon)
				if is_active:
					main.opponent_active_pokemon = null
				else:
					main.opponent_bench.erase(tentacool)
				tentacool.current_location = "hand"
				main.opponent_hand.append(tentacool)
				main.clear_all_statuses(tentacool, true)
				tentacool.pluspower_count = 0
				main.update_discard_pile_display(true)
				main.display_pokemon(true)
				main.refresh_hand_display(true)
				await main.show_message("Cowardice: Tentacool returned to hand!")
				if main._should_bail(): return
				if is_active:
					await main.handle_post_knockout(true)
					if main._should_bail(): return
	
	# --- BASE5 CPU POWER ACTIVATIONS ---
	
	# Evolutionary Light (Dark Dragonair): Search deck for Evolution card
	var dragonair = _find_cpu_pokemon_with_power("Evolutionary Light")
	if dragonair != null and not dragonair.power_used_this_turn and not dragonair.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(dragonair) and not toxic_gas:
			var cpu_deck = main.opponent_deck
			var evolutions: Array = []
			for card in cpu_deck:
				var subtypes = card.metadata.get("subtypes", [])
				if "Stage 1" in subtypes or "Stage 2" in subtypes:
					evolutions.append(card)
			if evolutions.size() > 0:
				# Pick evolution that matches something on field
				var best: card_object = null
				var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
				for evo in evolutions:
					var evolves_from = evo.metadata.get("evolvesFrom", "")
					for p in all_cpu:
						if p.metadata.get("name", "") == evolves_from:
							best = evo
							break
					if best != null:
						break
				if best == null:
					best = evolutions[0]
				cpu_deck.erase(best)
				best.current_location = "hand"
				main.opponent_hand.append(best)
				cpu_deck.shuffle()
				dragonair.power_used_this_turn = true
				main.refresh_hand_display(true)
				await main.show_message("Evolutionary Light: Found " + best.metadata.get("name", "") + "!")
				if main._should_bail(): return
	
	# Matter Exchange (Dark Kadabra): Discard 1, draw 1
	var kadabra = _find_cpu_pokemon_with_power("Matter Exchange")
	if kadabra != null and not kadabra.power_used_this_turn and not kadabra.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(kadabra) and not toxic_gas:
			if main.opponent_hand.size() >= 2 and main.opponent_deck.size() > 0:
				var to_discard = main.trainer_effects.cpu_get_discard_priority(main.opponent_hand, 1)
				if to_discard.size() > 0:
					var card = to_discard[0]
					main.opponent_hand.erase(card)
					card.current_location = "discard"
					main.opponent_discard_pile.append(card)
					await main.card_ops.draw_n(true, 1)
					if main._should_bail(): return
					kadabra.power_used_this_turn = true
					await main.show_message("Matter Exchange: Swapped a card!")
					if main._should_bail(): return
	
	# Pollen Stench (Dark Gloom): Flip for confusion
	var gloom = _find_cpu_pokemon_with_power("Pollen Stench")
	if gloom != null and not gloom.power_used_this_turn and not gloom.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(gloom) and not toxic_gas:
			# Only use if player active isn't already confused
			if main.player_active_pokemon != null and main.player_active_pokemon.special_condition != "Confused":
				# CPU's Gloom — opponent flips.
				var coin = await main.flip_coin(false, true)
				gloom.power_used_this_turn = true
				if coin:
					main.card_ops.apply_status(main.player_active_pokemon, "Confused", false)
					await main.show_message("Pollen Stench: Defending Pokemon is Confused!")
					if main._should_bail(): return
				else:
					# Tails: own active confused
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						main.card_ops.apply_status(cpu_active, "Confused", true)
						await main.show_message("Pollen Stench: Tails! Own active is Confused!")
						if main._should_bail(): return
	
	# Gather Fire (Charmander): Move Fire Energy from another Pokemon
	var charmander = _find_cpu_pokemon_with_power("Gather Fire")
	if charmander != null and not charmander.power_used_this_turn and not charmander.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(charmander) and not toxic_gas:
			var all_cpu = main.cpu_ai.get_all_cpu_field_pokemon()
			var best_source: card_object = null
			var best_energy: card_object = null
			for p in all_cpu:
				if p == charmander:
					continue
				for e in p.attached_energies:
					var provided = main.get_energy_provided_by_card(e)
					if "Fire" in provided:
						# Only take if source has spare energy
						if p.attached_energies.size() > 1:
							best_source = p
							best_energy = e
							break
				if best_energy != null:
					break
			if best_source != null and best_energy != null:
				best_source.attached_energies.erase(best_energy)
				charmander.attached_energies.append(best_energy)
				charmander.power_used_this_turn = true
				main.display_active_pokemon_energies(true)
				await main.show_message("Gather Fire: Moved Fire Energy to Charmander!")
				if main._should_bail(): return
	
	# Long-Distance Hypnosis (Drowzee): Flip for sleep
	var drowzee = _find_cpu_pokemon_with_power("Long-Distance Hypnosis")
	if drowzee != null and not drowzee.power_used_this_turn and not drowzee.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(drowzee) and not toxic_gas:
			if main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "":
				# CPU's Drowzee — opponent flips.
				var coin = await main.flip_coin(false, true)
				drowzee.power_used_this_turn = true
				if coin:
					main.card_ops.apply_status(main.player_active_pokemon, "Asleep", false)
					await main.show_message("Long-Distance Hypnosis: Defending Pokemon is Asleep!")
					if main._should_bail(): return
				else:
					var cpu_active = main.opponent_active_pokemon
					if cpu_active != null:
						main.card_ops.apply_status(cpu_active, "Asleep", true)
						await main.show_message("Long-Distance Hypnosis: Tails! Own active is Asleep!")
						if main._should_bail(): return
	
	# Trickery (Rattata): Switch prize with top of deck — CPU uses if deck top might be better
	var rattata = _find_cpu_pokemon_with_power("Trickery")
	if rattata != null and not rattata.power_used_this_turn and not rattata.power_disabled_until_end_of_next_turn:
		if not is_power_blocked_by_status(rattata) and not toxic_gas:
			if main.opponent_prize_cards.size() > 0 and main.opponent_deck.size() > 0:
				# Simple heuristic: use if prizes > 3 remaining (more chances to improve)
				if main.opponent_prize_cards.size() >= 3:
					var top_card = main.opponent_deck[0]
					var prize_idx = 0
					main.opponent_deck.erase(top_card)
					var prize_card = main.opponent_prize_cards[prize_idx]
					main.opponent_prize_cards[prize_idx] = top_card
					main.opponent_deck.insert(0, prize_card)
					rattata.power_used_this_turn = true
					await main.show_message("Trickery: Swapped a prize with top of deck!")
					if main._should_bail(): return

	# --- GYM1 + GYM2 POWERS ---
	await cpu_phase_gym_powers()
	if main._should_bail(): return

	# --- NEO1 POWERS ---
	await cpu_phase_neo1_powers()
	if main._should_bail(): return
	# --- NEO2 POWERS ---
	await cpu_phase_neo2_powers()
	if main._should_bail(): return
	# --- NEO3 POWERS ---
	await cpu_phase_neo3_powers()
	if main._should_bail(): return
	# --- NEO4 POWERS ---
	await cpu_phase_neo4_powers()
	if main._should_bail(): return
	# --- NP POWERS ---
	await cpu_phase_np_powers()
	if main._should_bail(): return
	# --- ECARD1 POWERS ---
	await cpu_phase_ecard1_powers()
	if main._should_bail(): return
	await cpu_phase_ecard2_powers()
	if main._should_bail(): return
	await cpu_phase_ecard3_powers()
	if main._should_bail(): return
	await cpu_phase_ex1_powers()
	if main._should_bail(): return
	await cpu_phase_ex2_powers()
	if main._should_bail(): return
	await cpu_phase_ex3_powers()
	if main._should_bail(): return
	await cpu_phase_ex4_powers()
	if main._should_bail(): return
	await cpu_phase_ex5_powers()
	if main._should_bail(): return


# Helper to find a CPU pokemon with a specific power name

func _find_cpu_pokemon_with_power(power_name: String) -> card_object:
	var all_pokemon = main.cpu_ai.get_all_cpu_field_pokemon()
	for p in all_pokemon:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == power_name:
				return p
	return null

# Helper to find a CPU bench pokemon with a specific power name
func _find_cpu_bench_pokemon_with_power(power_name: String) -> card_object:
	for p in main.opponent_bench:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == power_name:
				return p
	return null

############################################### Section I: MACHAMP STRIKES BACK HOOK #################################################################

# Called after damage is applied to a pokemon - checks for Machamp's Strikes Back

func check_strikes_back(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var abilities = damaged_pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Strikes Back":
			continue
		if is_power_blocked_by_status(damaged_pokemon):
			print("STRIKES BACK: Blocked by status on ", damaged_pokemon.metadata.get("name", ""))
			return
		# Deal 10 damage to the attacker, ignoring weakness/resistance
		attacker.current_hp = max(0, attacker.current_hp - 10)
		var attacker_is_opp = not is_damaged_opponent
		main.display_hp_circles_above_align(attacker, attacker_is_opp)
		# Show floating label for the -10HP on the attacker
		var attacker_label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
		main.show_floating_label("-10HP", attacker_label_pos, true)
		await main.show_message(damaged_pokemon.metadata.get("name", "") + "'s STRIKES BACK dealt 10 damage to " + attacker.metadata.get("name", "") + "!")
		print("STRIKES BACK: 10 damage to ", attacker.metadata.get("name", ""))

############################################### Section J: DOUBLE COLORLESS ENERGY HANDLING ##########################################################

# Check if a card is Double Colorless Energy (Special Energy)

######################################################################################################################################################
################################################### BASE5 (TEAM ROCKET) POWERS AND BODIES ############################################################
######################################################################################################################################################

# --- HAY FEVER CHECK ---
func is_hay_fever_active() -> bool:
	# Check if any Dark Vileplume in play has Hay Fever active
	# Goop Gas also disables this
	if main.goop_gas_active:
		return false
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_pokemon.append(main.opponent_active_pokemon)
	all_pokemon.append_array(main.opponent_bench)
	for p in all_pokemon:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == "Hay Fever":
				if not is_power_blocked_by_status(p):
					return true
	return false

# --- SINKHOLE: Called when opponent's active retreats ---
func check_sinkhole(retreating_pokemon: card_object, is_retreating_opponent: bool) -> void:
	# Sinkhole triggers on the OPPOSING side's retreat
	# Find Dark Dugtrio on the side that is NOT retreating
	var dugtrio: card_object = null
	if is_retreating_opponent:
		# Opponent is retreating, check player's side for Dugtrio
		var player_all: Array = []
		if main.player_active_pokemon != null:
			player_all.append(main.player_active_pokemon)
		player_all.append_array(main.player_bench)
		for p in player_all:
			for ability in p.metadata.get("abilities", []):
				if ability.get("name", "") == "Sinkhole":
					dugtrio = p
					break
			if dugtrio != null:
				break
	else:
		# Player is retreating, check opponent's side for Dugtrio
		var opp_all: Array = []
		if main.opponent_active_pokemon != null:
			opp_all.append(main.opponent_active_pokemon)
		opp_all.append_array(main.opponent_bench)
		for p in opp_all:
			for ability in p.metadata.get("abilities", []):
				if ability.get("name", "") == "Sinkhole":
					dugtrio = p
					break
			if dugtrio != null:
				break
	
	if dugtrio == null:
		return
	if is_power_blocked_by_status(dugtrio):
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return

	# Dugtrio's controller (Sinkhole owner) flips — opposite of retreating side.
	var coin = await main.flip_coin(false, not is_retreating_opponent)
	if not coin:
		# Tails: 20 damage to retreating pokemon (no W/R)
		retreating_pokemon.current_hp = max(0, retreating_pokemon.current_hp - 20)
		main.display_hp_circles_above_align(retreating_pokemon, is_retreating_opponent)
		await main.show_message("SINKHOLE! 20 DAMAGE TO " + retreating_pokemon.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	else:
		await main.show_message("SINKHOLE: HEADS! NO DAMAGE!")
		if main._should_bail(): return
	print("POWER CHECK: Sinkhole - coin was ", "tails" if not coin else "heads")

# --- SNEAK ATTACK: When Dark Golbat played from hand, 10 damage to chosen opponent Pokemon ---
func trigger_sneak_attack(golbat: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var all_targets: Array = []
	if is_opponent:
		if main.player_active_pokemon != null:
			all_targets.append(main.player_active_pokemon)
		all_targets.append_array(main.player_bench)
	else:
		if main.opponent_active_pokemon != null:
			all_targets.append(main.opponent_active_pokemon)
		all_targets.append_array(main.opponent_bench)
	
	if all_targets.size() == 0:
		return
	
	await main.show_message("SNEAK ATTACK!")
	if main._should_bail(): return
	
	var selected: card_object = null
	
	if not is_opponent:
		# Player chooses target
		selected = await main.card_ops.prompt_select_card(all_targets, "CHOOSE POKÉMON FOR SNEAK ATTACK", "", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks lowest HP target
		all_targets.sort_custom(func(a, b): return a.current_hp < b.current_hp)
		selected = all_targets[0]
	
	if selected == null:
		return
	
	# 10 damage WITH Weakness and Resistance
	var golbat_types = golbat.metadata.get("types", ["Colorless"])
	var result = main.calculate_final_damage(10, golbat_types, selected)
	selected.current_hp = max(0, selected.current_hp - result["damage"])
	
	var is_target_opp = !is_opponent
	main.display_hp_circles_above_align(selected, is_target_opp)
	await main.show_message("SNEAK ATTACK: " + str(result["damage"]) + " DAMAGE TO " + selected.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER: Sneak Attack dealt ", result["damage"], " to ", selected.metadata.get("name", ""))

# --- FINAL BEAM: When Dark Gyarados is KO'd, flip heads = 20×Water Energy damage to attacker ---
func check_final_beam(gyarados: card_object, attacker: card_object, is_gyarados_opponent: bool) -> void:
	if gyarados == null or attacker == null:
		return
	
	var has_final_beam = false
	for ability in gyarados.metadata.get("abilities", []):
		if ability.get("name", "") == "Final Beam":
			has_final_beam = true
			break
	
	if not has_final_beam:
		return
	if is_power_blocked_by_status(gyarados):
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	# Count Water Energy
	var water_count = 0
	for e in gyarados.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Water" in provided:
			water_count += 1
	
	if water_count == 0:
		return

	# Gyarados (Final Beam) owner flips on its own KO.
	var coin = await main.flip_coin(false, is_gyarados_opponent)
	if coin:
		var damage = 20 * water_count
		# Apply with W/R
		var gyarados_types = gyarados.metadata.get("types", ["Colorless"])
		var result = main.calculate_final_damage(damage, gyarados_types, attacker)
		attacker.current_hp = max(0, attacker.current_hp - result["damage"])
		main.display_hp_circles_above_align(attacker, !is_gyarados_opponent)
		await main.show_message("FINAL BEAM! " + str(result["damage"]) + " DAMAGE TO " + attacker.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
		print("POWER: Final Beam dealt ", result["damage"])
	else:
		await main.show_message("FINAL BEAM: TAILS! NO EFFECT!")
		if main._should_bail(): return

# --- SUMMON MINIONS: When Dark Dragonite played from hand, search deck for up to 2 basics ---
func trigger_summon_minions(dragonite: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var bench = main.opponent_bench if is_opponent else main.player_bench
	
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("BENCH IS FULL! CAN'T SUMMON MINIONS!")
		if main._should_bail(): return
		return
	
	var basics: Array = []
	for card in deck:
		if main.is_basic_pokemon(card):
			basics.append(card)
	
	if basics.size() == 0:
		await main.show_message("NO BASIC POKÉMON IN DECK!")
		if main._should_bail(): return
		return
	
	await main.show_message("SUMMON MINIONS!")
	if main._should_bail(): return
	
	var picks_remaining = min(2, 5 - bench.size())
	
	for i in range(picks_remaining):
		var remaining_basics: Array = []
		for card in deck:
			if main.is_basic_pokemon(card):
				remaining_basics.append(card)
		if remaining_basics.size() == 0:
			break
		
		var pick: card_object = null
		
		if not is_opponent:
			pick = await main.card_ops.prompt_select_card(remaining_basics, "CHOOSE BASIC " + str(i + 1) + "/" + str(picks_remaining), "", "SELECT", false, true)
			if main._should_bail(): return
		else:
			pick = main.cpu_ai.cpu_search_deck_for_best_pokemon(remaining_basics)
			if pick == null:
				pick = remaining_basics[0]
		
		if pick != null:
			deck.erase(pick)
			pick.current_location = "bench"
			pick.placed_on_field_this_turn = true
			bench.append(pick)
		
		if bench.size() >= main.get_max_bench_size():
			break
	
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SUMMONED POKÉMON TO BENCH!")
	if main._should_bail(): return
	print("POWER: Summon Minions")

# --- REEL IN: When Dark Slowbro played from hand, retrieve up to 3 Pokemon/Evolution from discard ---
func trigger_reel_in(slowbro: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	
	var valid: Array = []
	for card in discard:
		var supertype = card.metadata.get("supertype", "")
		var subtypes = card.metadata.get("subtypes", [])
		if supertype == "Pokémon":
			valid.append(card)
	
	if valid.size() == 0:
		await main.show_message("NO POKÉMON IN DISCARD!")
		if main._should_bail(): return
		return
	
	await main.show_message("REEL IN!")
	if main._should_bail(): return
	
	var max_picks = min(3, valid.size())
	var chosen: Array = []
	
	if not is_opponent:
		for i in range(max_picks):
			var remaining: Array = []
			for c in valid:
				if c not in chosen:
					remaining.append(c)
			if remaining.size() == 0:
				break
			
			var pick = await main.card_ops.prompt_select_card(remaining, "CHOOSE CARD " + str(i + 1) + "/" + str(max_picks), "", "SELECT", true)
			if main._should_bail(): return
			
			if pick != null:
				chosen.append(pick)
			else:
				break
	else:
		# CPU picks evolution cards first
		valid.sort_custom(func(a, b):
			var a_is_evo = "Stage" in str(a.metadata.get("subtypes", []))
			var b_is_evo = "Stage" in str(b.metadata.get("subtypes", []))
			return a_is_evo and not b_is_evo
		)
		for i in range(max_picks):
			chosen.append(valid[i])
	
	for card in chosen:
		discard.erase(card)
		card.current_location = "hand"
		hand.append(card)
	
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("RETRIEVED " + str(chosen.size()) + " CARD(S) FROM DISCARD!")
	if main._should_bail(): return
	print("POWER: Reel In - retrieved ", chosen.size(), " cards")

# --- EVOLUTIONARY LIGHT (Dark Dragonair): Search deck for Evolution, put in hand ---
func power_evolutionary_light(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	var deck = main.player_deck
	var evolutions: Array = []
	for card in deck:
		var subtypes = card.metadata.get("subtypes", [])
		if card.metadata.get("supertype", "") == "Pokémon" and ("Stage 1" in subtypes or "Stage 2" in subtypes):
			evolutions.append(card)
	
	if evolutions.size() == 0:
		await main.show_message("NO EVOLUTION CARDS IN DECK!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	var selected = await main.card_ops.prompt_select_card(evolutions, "CHOOSE AN EVOLUTION CARD", "", "SELECT", false, true)
	if main._should_bail(): return
	
	if selected == null:
		pokemon.power_used_this_turn = false
		return
	
	deck.erase(selected)
	selected.current_location = "hand"
	main.player_hand.append(selected)
	deck.shuffle()
	
	main.refresh_hand_display(false)
	main.update_deck_icon(false)
	await main.show_message("ADDED " + selected.metadata.get("name", "").to_upper() + " TO HAND!")
	if main._should_bail(): return
	print("POWER: Evolutionary Light - found ", selected.metadata.get("name", ""))

# --- POLLEN STENCH (Dark Gloom): Flip, heads=defender confused, tails=self confused ---
func power_pollen_stench(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	# Player-activated Power — player flips.
	var coin = await main.flip_coin(false, false)

	if coin:
		var defender = main.opponent_active_pokemon
		if defender != null:
			main.card_ops.apply_status(defender, "Confused", true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			main.card_ops.apply_status(active, "Confused", false)
			await main.show_message("TAILS! " + active.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
			if main._should_bail(): return
	print("POWER: Pollen Stench")

# --- MATTER EXCHANGE (Dark Kadabra): Discard 1 from hand, draw 1 ---
func power_matter_exchange(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if main.player_hand.size() == 0:
		await main.show_message("NO CARDS IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	
	if main.player_deck.size() == 0:
		await main.show_message("NO CARDS IN DECK TO DRAW!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player selects card to discard
	var selected = await main.card_ops.prompt_select_card(main.player_hand, "CHOOSE A CARD TO DISCARD", "", "DISCARD", false)
	if main._should_bail(): return

	if selected == null:
		pokemon.power_used_this_turn = false
		return
	
	main.player_hand.erase(selected)
	selected.current_location = "discard"
	main.player_discard_pile.append(selected)
	main.update_discard_pile_display(false)
	
	await main.card_ops.draw_n(false, 1)
	if main._should_bail(): return
	await main.show_message("MATTER EXCHANGE: DISCARDED 1, DREW 1!")
	if main._should_bail(): return
	print("POWER: Matter Exchange")

# --- GATHER FIRE (Charmander): Move 1 Fire Energy from another Pokemon to self ---
func power_gather_fire(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	# Find other pokemon with Fire Energy
	var sources: Array = []
	var all_pokemon: Array = []
	if main.player_active_pokemon != null:
		all_pokemon.append(main.player_active_pokemon)
	all_pokemon.append_array(main.player_bench)
	
	for p in all_pokemon:
		if p == pokemon:
			continue
		for e in p.attached_energies:
			var provided = main.get_energy_provided_by_card(e)
			if "Fire" in provided:
				sources.append(p)
				break
	
	if sources.size() == 0:
		await main.show_message("NO OTHER POKÉMON WITH FIRE ENERGY!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player chooses source
	var source = await main.card_ops.prompt_select_card(sources, "CHOOSE POKÉMON TO TAKE FIRE ENERGY FROM", "", "SELECT", false)
	if main._should_bail(): return

	if source == null:
		pokemon.power_used_this_turn = false
		return
	
	# Move 1 Fire Energy
	for e in source.attached_energies:
		var provided = main.get_energy_provided_by_card(e)
		if "Fire" in provided:
			source.attached_energies.erase(e)
			pokemon.attached_energies.append(e)
			break
	
	main.display_active_pokemon_energies(false)
	await main.show_message("GATHERED FIRE ENERGY FROM " + source.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	print("POWER: Gather Fire")

# --- LONG-DISTANCE HYPNOSIS (Drowzee): Flip, heads=defender asleep, tails=self asleep ---
func power_long_distance_hypnosis(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	# Player-activated Power — player flips.
	var coin = await main.flip_coin(false, false)

	if coin:
		var defender = main.opponent_active_pokemon
		if defender != null:
			main.card_ops.apply_status(defender, "Asleep", true)
			await main.show_message("HEADS! " + defender.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	else:
		var active = main.player_active_pokemon
		if active != null:
			main.card_ops.apply_status(active, "Asleep", false)
			await main.show_message("TAILS! " + active.metadata.get("name", "").to_upper() + " IS NOW ASLEEP!")
			if main._should_bail(): return
	print("POWER: Long-Distance Hypnosis")

# --- TRICKERY (Rattata): Switch 1 prize with top of deck ---
func power_trickery(pokemon: card_object) -> void:
	if is_power_blocked_by_status(pokemon):
		await main.show_message("POWER BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	
	if main.player_deck.size() == 0:
		await main.show_message("NO CARDS IN DECK!")
		if main._should_bail(): return
		return
	
	if main.player_prize_cards.size() == 0:
		await main.show_message("NO PRIZE CARDS!")
		if main._should_bail(): return
		return
	
	pokemon.power_used_this_turn = true
	
	# Player chooses prize card
	var selected_prize = await main.card_ops.prompt_select_card(main.player_prize_cards, "CHOOSE A PRIZE CARD TO SWAP", "", "SWAP", false)
	if main._should_bail(): return

	if selected_prize == null:
		pokemon.power_used_this_turn = false
		return
	
	# Swap with top of deck
	var top_deck = main.player_deck[0]
	var prize_idx = main.player_prize_cards.find(selected_prize)
	
	main.player_prize_cards[prize_idx] = top_deck
	main.player_deck[0] = selected_prize
	
	main.display_prize_cards(false)
	main.update_deck_icon(false)
	await main.show_message("TRICKERY: SWAPPED PRIZE WITH TOP OF DECK!")
	if main._should_bail(): return
	print("POWER: Trickery")

# --- STICKY GOO (Dark Muk): Check for +2 retreat cost ---
func get_sticky_goo_cost(is_opponent: bool) -> int:
	# Sticky Goo: opponent pays 2 more to retreat if Dark Muk is their opponent's active
	# "As long as Dark Muk is your Active Pokémon"
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_active == null:
		return 0
	for ability in opp_active.metadata.get("abilities", []):
		if ability.get("name", "") == "Sticky Goo":
			if not is_power_blocked_by_status(opp_active) and not is_toxic_gas_active() and not main.goop_gas_active:
				return 2
	return 0

# --- FRENZY (Dark Primeape): +30 damage when confused ---
func check_frenzy_bonus(attacker: card_object) -> int:
	if attacker == null:
		return 0
	if attacker.special_condition != "Confused":
		return 0
	for ability in attacker.metadata.get("abilities", []):
		if ability.get("name", "") == "Frenzy":
			if not is_toxic_gas_active() and not main.goop_gas_active:
				return 30
	return 0

######################################################################################################################################################
######################################################## GYM1 (GYM HEROES) POWERS AND BODIES ########################################################
######################################################################################################################################################

# Returns true if `pokemon` carries the named ability AND the ability is currently usable.
# `works_through_status`: ability text contains "even while Asleep/Confused/Paralyzed".
# Always blocked by Toxic Gas / Goop Gas Attack.
func _power_active_on(pokemon: card_object, power_name: String, works_through_status: bool = false) -> bool:
	if pokemon == null or pokemon.current_hp <= 0:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	if pokemon.power_disabled_until_end_of_next_turn:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == power_name:
			has_it = true
			break
	if not has_it:
		return false
	if not works_through_status and is_power_blocked_by_status(pokemon):
		return false
	return true

# Helper: locate a Pokemon Power on a side by ability name. Returns the card_object or null.
func _find_pokemon_with_power_on_side(power_name: String, is_opponent: bool) -> card_object:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null:
		for ab in active.metadata.get("abilities", []):
			if ab.get("name", "") == power_name:
				return active
	for bp in bench:
		for ab in bp.metadata.get("abilities", []):
			if ab.get("name", "") == power_name:
				return bp
	return null

# --- gym1-2 Brock's Rhydon — Bench Guard ---
# When a benched Pokemon on Rhydon's side takes damage, owner may redirect 10 of that damage to Rhydon.
# Called BEFORE damage is applied to a benched pokemon. Returns the damage that should actually land
# on the original target (caller applies the redirected 10 to Rhydon separately).
func check_bench_guard(damaged_pokemon: card_object, damage: int, owner_is_opp: bool) -> int:
	if damaged_pokemon == null or damage <= 0:
		return damage
	# Find a benched Brock's Rhydon on the SAME side as the damaged pokemon
	var bench = main.opponent_bench if owner_is_opp else main.player_bench
	if damaged_pokemon not in bench:
		return damage
	var rhydon: card_object = null
	for bp in bench:
		if bp == damaged_pokemon:
			continue
		if _power_active_on(bp, "Bench Guard", false):
			rhydon = bp
			break
	if rhydon == null:
		return damage
	# Player opt-in vs CPU automatic
	var redirect: bool = false
	if owner_is_opp:
		# CPU: redirect if Rhydon has enough HP buffer (more than 20) and the bench pokemon is more valuable
		if rhydon.current_hp > 20:
			redirect = true
	else:
		redirect = await main.trainer_effects.gym1_prompt_yes_no(rhydon, "BENCH GUARD", \
			rhydon.metadata.get("name", "") + " may take 10 damage instead?", "REDIRECT", "DECLINE")
		if main._should_bail(): return damage
	if not redirect:
		return damage
	# Redirect 10 to Rhydon (capped at the actual damage)
	var redirected: int = min(10, damage)
	rhydon.current_hp = max(0, rhydon.current_hp - redirected)
	main.display_hp_circles_above_align(rhydon, owner_is_opp)
	await main.show_message("BENCH GUARD: " + rhydon.metadata.get("name", "").to_upper() + " TOOK " + str(redirected) + " DAMAGE INSTEAD!")
	if main._should_bail(): return damage - redirected
	return damage - redirected

# --- gym1-5 Erika's Vileplume — Pollen Defense ---
# When an attack damages Vileplume (your Active), flip; heads -> opponent's Active becomes Confused.
# Works even while Vileplume is Asleep/Confused/Paralyzed.
func check_pollen_defense(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return
	if not _power_active_on(damaged_pokemon, "Pollen Defense", true):
		return
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if not coin:
		await main.show_message("POLLEN DEFENSE: TAILS!")
		return
	if attacker.special_condition == "Confused":
		await main.show_message("POLLEN DEFENSE: " + attacker.metadata.get("name", "").to_upper() + " IS ALREADY CONFUSED!")
		return
	if attacker.is_bench_token:
		return
	# Snorlax Thick Skinned check
	for ab in attacker.metadata.get("abilities", []):
		if ab.get("name", "") == "Thick Skinned" and not is_toxic_gas_active():
			await main.show_message("THICK SKINNED PREVENTS CONFUSION!")
			return
	main.card_ops.apply_status(attacker, "Confused", not is_damaged_opp)
	await main.show_message("POLLEN DEFENSE: " + attacker.metadata.get("name", "").to_upper() + " IS NOW CONFUSED!")
	if main._should_bail(): return

# --- gym1-8 Lt. Surge's Magneton — Energy Charge ---
# As often as you like: take 1 Lightning Energy from one of your Pokemon, attach to active Magneton.
func power_energy_charge(magneton: card_object) -> void:
	if magneton == null:
		return
	var is_opp: bool = (magneton == main.opponent_active_pokemon)
	# Build list of sources (any of your other pokemon that has a Lightning energy)
	var sources: Array = []
	var bench = main.opponent_bench if is_opp else main.player_bench
	for bp in bench:
		if bp == magneton:
			continue
		for e in bp.attached_energies:
			if "Lightning" in main.get_energy_provided_by_card(e):
				sources.append(bp)
				break
	if sources.size() == 0:
		if not is_opp:
			await main.show_message("NO LIGHTNING ENERGY ON YOUR OTHER POKEMON!")
		return
	var source: card_object = null
	if is_opp:
		# CPU: pick any source with spare lightning
		source = sources[0]
	else:
		if sources.size() == 1:
			source = sources[0]
		else:
			source = await main.card_ops.prompt_select_card(sources, "ENERGY CHARGE", "Choose a Pokemon to take Lightning Energy from", "SELECT", true)
			if main._should_bail(): return
		if source == null:
			return
	# Move one Lightning energy
	var moved: card_object = null
	for e in source.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			moved = e
			break
	if moved == null:
		return
	source.attached_energies.erase(moved)
	magneton.attached_energies.append(moved)
	main.display_active_pokemon_energies(is_opp)
	main.display_pokemon(is_opp)
	await main.show_message("ENERGY CHARGE: MOVED LIGHTNING ENERGY TO " + magneton.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return
	# Energy Charge is multi-use per turn — DO NOT set power_used_this_turn

# --- gym1-10 Misty's Tentacruel — Flee ---
# After damage hits Tentacruel as Active, owner may switch with a bench pokemon to prevent other effects.
# Returns true if Tentacruel fled (caller should skip remaining attack effects on it).
func check_flee(damaged_pokemon: card_object, is_damaged_opp: bool) -> bool:
	if damaged_pokemon == null or damaged_pokemon.current_hp <= 0:
		return false
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return false
	if not _power_active_on(damaged_pokemon, "Flee", false):
		return false
	var bench = main.opponent_bench if is_damaged_opp else main.player_bench
	if bench.size() == 0:
		return false
	var do_flee: bool = false
	if is_damaged_opp:
		# CPU: flee if HP is critical or there's a healthier replacement
		var hp_pct = float(damaged_pokemon.current_hp) / max(1, int(damaged_pokemon.metadata.get("hp", "0")))
		if hp_pct <= 0.4:
			do_flee = true
	else:
		do_flee = await main.trainer_effects.gym1_prompt_yes_no(damaged_pokemon, "FLEE", \
			"Switch " + damaged_pokemon.metadata.get("name", "") + " with a bench Pokemon?", "FLEE", "STAY")
		if main._should_bail(): return false
	if not do_flee:
		return false
	# Choose replacement
	var replacement: card_object = null
	if is_damaged_opp:
		replacement = main.cpu_ai.pick_best_bench_replacement(bench, main.player_active_pokemon, main.cpu_ai.get_cpu_evaluation())
		if replacement == null:
			replacement = bench[0]
	else:
		if bench.size() == 1:
			replacement = bench[0]
		else:
			replacement = await main.card_ops.prompt_select_card(bench, "FLEE", "Choose a bench Pokemon to switch to", "SELECT", false)
			if main._should_bail(): return false
		if replacement == null:
			return false
	# Perform swap (no retreat cost)
	if is_damaged_opp:
		main.opponent_bench.erase(replacement)
		main.opponent_bench.append(damaged_pokemon)
		damaged_pokemon.current_location = "bench"
		replacement.current_location = "active"
		main.opponent_active_pokemon = replacement
	else:
		main.player_bench.erase(replacement)
		main.player_bench.append(damaged_pokemon)
		damaged_pokemon.current_location = "bench"
		replacement.current_location = "active"
		main.player_active_pokemon = replacement
	main.clear_all_statuses(damaged_pokemon, is_damaged_opp)
	main.display_pokemon(is_damaged_opp)
	main.display_active_pokemon_energies(is_damaged_opp)
	await main.show_message("FLEE: " + damaged_pokemon.metadata.get("name", "").to_upper() + " SWITCHED OUT!")
	if main._should_bail(): return true
	return true

# --- gym1-12 Rocket's Moltres — Rebirth ---
# When Moltres is KO'd, owner may return it to hand instead of discarding.
# Blocked if Asleep/Confused/Paralyzed when KO'd.
# Returns true if rebirth was used (caller should skip the discard step).
func check_rebirth(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null:
		return false
	# Look for the Rebirth ability
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Rebirth":
			has_it = true
			break
	if not has_it:
		return false
	# Blocked by status / toxic gas
	if pokemon.special_condition in ["Paralyzed", "Asleep", "Confused"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	var do_rebirth: bool = false
	if is_opp:
		do_rebirth = true  # CPU always rebirths
	else:
		do_rebirth = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "REBIRTH", \
			"Return " + pokemon.metadata.get("name", "") + " to your hand instead of discarding?", "REBIRTH", "DISCARD")
		if main._should_bail(): return false
	if not do_rebirth:
		return false
	# Return Moltres to hand (attached cards/energies/pre-evos all go to discard)
	var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
	for e in pokemon.attached_energies:
		e.current_location = "discard"
		discard_pile.append(e)
	pokemon.attached_energies.clear()
	for c in pokemon.attached_cards:
		c.current_location = "discard"
		discard_pile.append(c)
	pokemon.attached_cards.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "discard"
		discard_pile.append(pre)
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.special_condition = ""
	pokemon.is_poisoned = false
	pokemon.is_burned = false
	pokemon.pluspower_count = 0
	pokemon.defender_turns_remaining = -1
	pokemon.current_location = "hand"
	var hand = main.opponent_hand if is_opp else main.player_hand
	hand.append(pokemon)
	main.refresh_hand_display(is_opp)
	main.update_discard_pile_display(is_opp)
	await main.show_message("REBIRTH: " + pokemon.metadata.get("name", "").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return true
	return true

# --- gym1-26 Erika's Victreebel — Fragrance Trap ---
# Once/turn: flip; heads, switch one of opponent's bench with their Active.
func power_fragrance_trap(victreebel: card_object) -> void:
	if victreebel == null or victreebel.power_used_this_turn:
		return
	var is_opp: bool = (victreebel == main.opponent_active_pokemon or victreebel in main.opponent_bench)
	var opp_bench = main.player_bench if is_opp else main.opponent_bench
	if opp_bench.size() == 0:
		if not is_opp:
			await main.show_message("OPPONENT HAS NO BENCHED POKEMON!")
		return
	victreebel.power_used_this_turn = true
	# Owner flips
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FRAGRANCE TRAP: TAILS!")
		return
	# Choose opponent's bench pokemon to bring up
	var target: card_object = null
	if is_opp:
		# CPU picks player's bench pokemon that helps the CPU most (e.g. lowest HP%, weakest, no energy)
		var best_score = 999999.0
		for bp in main.player_bench:
			var max_hp = int(bp.metadata.get("hp", "0"))
			var hp_pct = float(bp.current_hp) / max(1, max_hp)
			var e_count = bp.attached_energies.size()
			var s = hp_pct * 100.0 + e_count * 30.0
			if s < best_score:
				best_score = s
				target = bp
	else:
		target = await main.card_ops.prompt_select_card(opp_bench, "FRAGRANCE TRAP", "Choose an opponent bench Pokemon to bring up", "SELECT", false)
		if main._should_bail(): return
	if target == null:
		return
	# Swap target with opponent's Active
	var opp_active_var = "player_active_pokemon" if is_opp else "opponent_active_pokemon"
	var old_active = main.player_active_pokemon if is_opp else main.opponent_active_pokemon
	if is_opp:
		main.player_bench.erase(target)
		main.player_bench.append(old_active)
		main.player_active_pokemon = target
	else:
		main.opponent_bench.erase(target)
		main.opponent_bench.append(old_active)
		main.opponent_active_pokemon = target
	if old_active != null:
		old_active.current_location = "bench"
	target.current_location = "active"
	main.clear_all_statuses(old_active, not is_opp)
	main.display_pokemon(not is_opp)
	main.display_active_pokemon_energies(not is_opp)
	await main.show_message("FRAGRANCE TRAP: " + target.metadata.get("name", "").to_upper() + " WAS DRAGGED OUT!")
	if main._should_bail(): return

# --- gym1-29 Misty's Cloyster — Shell Armor ---
# Passive: -10 damage (after W/R). Blocked by status / Toxic Gas.
func apply_shell_armor(defender: card_object, damage: int) -> int:
	if defender == null or damage <= 0:
		return damage
	if not _power_active_on(defender, "Shell Armor", false):
		return damage
	var reduced: int = max(0, damage - 10)
	print("SHELL ARMOR: ", damage, " -> ", reduced)
	return reduced

# --- gym1-33 Rocket's Snorlax — Restless Sleep ---
# If opp's attack damages Snorlax while Snorlax is Asleep, deal 20 to attacker.
# Works through ALL status (the card text only excludes the case "if it's already Asleep" — flipped condition).
# Re-read: "if your opponent's attack does damage to Rocket's Snorlax and Rocket's Snorlax is already Asleep (even if it's Knocked Out), this power does 20 damage to the attacking Pokémon."
# So it triggers WHEN Snorlax is Asleep at time of damage.
func check_restless_sleep(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if damaged_pokemon.special_condition != "Asleep":
		return
	# Card-side check
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Restless Sleep":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	attacker.current_hp = max(0, attacker.current_hp - 20)
	var attacker_is_opp: bool = not is_damaged_opp
	main.display_hp_circles_above_align(attacker, attacker_is_opp)
	var label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
	main.show_floating_label("-20HP", label_pos, true)
	await main.show_message("RESTLESS SLEEP: " + attacker.metadata.get("name", "").to_upper() + " TOOK 20 DAMAGE!")
	if main._should_bail(): return

# --- gym1-42 Erika's Dratini — Strange Barrier ---
# When a Basic Pokemon attack (any side, including own) does ≥20 to Dratini (after W/R), reduce to 10.
func apply_strange_barrier(defender: card_object, attacker: card_object, damage: int) -> int:
	if defender == null or attacker == null or damage < 20:
		return damage
	if not _power_active_on(defender, "Strange Barrier", false):
		return damage
	# Attacker must be a Basic Pokemon (Stage 1/2 attackers are NOT capped)
	var subtypes = attacker.metadata.get("subtypes", [])
	if "Basic" not in subtypes:
		return damage
	print("STRANGE BARRIER: ", damage, " -> 10")
	return 10

# --- gym1-47 Erika's Oddish — Photosynthesis ---
# All attached energy provides Grass. Works through status.
func is_photosynthesis_active(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Photosynthesis":
			return true
	return false

# --- gym1-65 Blaine's Vulpix — Natural Healing ---
# Once/turn: remove 1 damage counter (10 HP).
func power_natural_healing(vulpix: card_object) -> void:
	if vulpix == null or vulpix.power_used_this_turn:
		return
	var max_hp = int(vulpix.metadata.get("hp", "0"))
	if vulpix.current_hp >= max_hp:
		if not (vulpix == main.opponent_active_pokemon or vulpix in main.opponent_bench):
			await main.show_message(vulpix.metadata.get("name", "").to_upper() + " HAS NO DAMAGE TO HEAL!")
		return
	var is_opp: bool = (vulpix == main.opponent_active_pokemon or vulpix in main.opponent_bench)
	# MATCH EFFECTS: no_healing / healing_multiplier gate (don't consume the power if blocked)
	var rule_heal = main.match_effects.modify_heal_amount(10, is_opp)
	if rule_heal <= 0:
		if not is_opp:
			await main.show_message("SPECIAL MATCH RULE: HEALING IS BLOCKED!")
		return
	vulpix.power_used_this_turn = true
	var actual_heal = min(rule_heal, max_hp - vulpix.current_hp)
	vulpix.current_hp = min(max_hp, vulpix.current_hp + rule_heal)
	main.display_hp_circles_above_align(vulpix, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("NATURAL HEALING: " + vulpix.metadata.get("name", "").to_upper() + " HEALED " + str(actual_heal) + " HP!")
	if main._should_bail(): return

######################################################################################################################################################
######################################################## GYM2 (GYM CHALLENGE) POWERS AND BODIES #####################################################
######################################################################################################################################################

# --- gym2-3 Brock's Ninetales — Shapeshift ---
# Active: attach Evolution card from hand; Ninetales uses that card's attacks instead of its own.
# Card's ability/HP/types stay as Ninetales. Discarding the form (also a free action) is a separate menu entry.
func power_shapeshift(ninetales: card_object) -> void:
	if ninetales == null:
		return
	# If form already attached, decline new attach (card says "attach an Evolution card" — implicit one form at a time per current setup)
	var is_opp: bool = (ninetales == main.opponent_active_pokemon or ninetales in main.opponent_bench)
	var hand = main.opponent_hand if is_opp else main.player_hand
	var evolutions: Array = []
	for c in hand:
		if c.metadata.get("supertype", "").to_lower() != "pokémon" and c.metadata.get("supertype", "").to_lower() != "pokemon":
			continue
		var sts = c.metadata.get("subtypes", [])
		if "Stage 1" in sts or "Stage 2" in sts:
			evolutions.append(c)
	if evolutions.size() == 0:
		if not is_opp:
			await main.show_message("NO EVOLUTION CARDS IN HAND!")
		return
	var chosen: card_object = null
	if is_opp:
		# CPU picks the evolution with strongest attack (highest base damage)
		var best_dmg = -1
		for ev in evolutions:
			for atk in ev.metadata.get("attacks", []):
				var d_raw = atk.get("damage", "0")
				var d = int(str(d_raw).replace("+", "").replace("×", "").replace("x", "")) if str(d_raw) != "" else 0
				if d > best_dmg:
					best_dmg = d
					chosen = ev
	else:
		if evolutions.size() == 1:
			chosen = evolutions[0]
		else:
			chosen = await main.card_ops.prompt_select_card(evolutions, "SHAPESHIFT", "Choose an Evolution card to attach as a form", "SELECT", true)
			if main._should_bail(): return
		if chosen == null:
			return
	# Discard previous form if any
	if ninetales.shapeshift_form_card != null:
		var prev_form = ninetales.shapeshift_form_card
		var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
		prev_form.current_location = "discard"
		discard_pile.append(prev_form)
		main.update_discard_pile_display(is_opp)
	# Attach new form
	hand.erase(chosen)
	chosen.current_location = "attached"
	ninetales.shapeshift_form_card = chosen
	ninetales.shapeshift_form_uid = chosen.uid
	ninetales.shapeshift_form_metadata = chosen.metadata.duplicate(true)
	# Mirror the form's attacks onto Ninetales (preserve original attacks for revert)
	if not ninetales.metadata.has("_original_attacks"):
		ninetales.metadata["_original_attacks"] = ninetales.metadata.get("attacks", [])
	ninetales.metadata["attacks"] = chosen.metadata.get("attacks", [])
	ninetales.power_used_this_turn = true
	main.refresh_hand_display(is_opp)
	await main.show_message("SHAPESHIFT: " + ninetales.metadata.get("name", "").to_upper() + " IS NOW " + chosen.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# Active: discard the attached Shapeshift form (counts as a free action per card text)
func power_shapeshift_discard(ninetales: card_object) -> void:
	if ninetales == null or ninetales.shapeshift_form_card == null:
		return
	var is_opp: bool = (ninetales == main.opponent_active_pokemon or ninetales in main.opponent_bench)
	var prev_form = ninetales.shapeshift_form_card
	var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
	prev_form.current_location = "discard"
	discard_pile.append(prev_form)
	# Restore original attacks
	if ninetales.metadata.has("_original_attacks"):
		ninetales.metadata["attacks"] = ninetales.metadata.get("_original_attacks", [])
		ninetales.metadata.erase("_original_attacks")
	ninetales.shapeshift_form_card = null
	ninetales.shapeshift_form_uid = ""
	ninetales.shapeshift_form_metadata = {}
	main.update_discard_pile_display(is_opp)
	await main.show_message("SHAPESHIFT FORM DISCARDED!")
	if main._should_bail(): return

# If Ninetales gets Asleep/Confused/Paralyzed, all attached forms are discarded.
func shapeshift_check_status_discard(pokemon: card_object) -> void:
	if pokemon == null or pokemon.shapeshift_form_card == null:
		return
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		var is_opp: bool = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
		var prev_form = pokemon.shapeshift_form_card
		var discard_pile = main.opponent_discard_pile if is_opp else main.player_discard_pile
		prev_form.current_location = "discard"
		discard_pile.append(prev_form)
		if pokemon.metadata.has("_original_attacks"):
			pokemon.metadata["attacks"] = pokemon.metadata.get("_original_attacks", [])
			pokemon.metadata.erase("_original_attacks")
		pokemon.shapeshift_form_card = null
		pokemon.shapeshift_form_uid = ""
		pokemon.shapeshift_form_metadata = {}
		main.update_discard_pile_display(is_opp)
		await main.show_message("SHAPESHIFT FORM DISCARDED DUE TO STATUS!")

# --- gym2-6 Giovanni's Machamp — Fortitude ---
# When Machamp would be KO'd by an opponent's attack, flip; heads, survive with 10 HP.
# Blocked if already Asleep/Confused/Paralyzed.
# Returns true if survived.
func check_fortitude(pokemon: card_object) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Fortitude":
			has_it = true
			break
	if not has_it:
		return false
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Owner flips
	var is_opp: bool = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return false
	if not coin:
		await main.show_message("FORTITUDE: TAILS!")
		return false
	pokemon.current_hp = 10
	main.display_hp_circles_above_align(pokemon, is_opp)
	await main.show_message("FORTITUDE: " + pokemon.metadata.get("name", "").to_upper() + " SURVIVED WITH 10 HP!")
	if main._should_bail(): return true
	return true

# --- gym2-8 Giovanni's Persian — Call the Boss ---
# When Persian comes into play from hand, owner may search deck for a Giovanni trainer card.
func trigger_call_the_boss(persian: card_object, is_opp: bool) -> void:
	if persian == null:
		return
	var has_it: bool = false
	for ab in persian.metadata.get("abilities", []):
		if ab.get("name", "") == "Call the Boss":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	var deck = main.opponent_deck if is_opp else main.player_deck
	var hand = main.opponent_hand if is_opp else main.player_hand
	var giovanni_cards: Array = []
	for c in deck:
		if c.metadata.get("name", "") == "Giovanni":
			giovanni_cards.append(c)
	if giovanni_cards.size() == 0:
		return
	var do_search: bool = false
	if is_opp:
		do_search = true
	else:
		do_search = await main.trainer_effects.gym1_prompt_yes_no(persian, "CALL THE BOSS", \
			"Search deck for a Giovanni trainer card?", "SEARCH", "DECLINE")
		if main._should_bail(): return
	if not do_search:
		return
	# CPU + Player flow: pick the first Giovanni
	var chosen: card_object = giovanni_cards[0]
	if not is_opp and giovanni_cards.size() > 1:
		chosen = await main.card_ops.prompt_select_card(giovanni_cards, "CALL THE BOSS", "Choose a Giovanni card to take", "SELECT", true, true)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("CALL THE BOSS: TOOK GIOVANNI FROM DECK!")
	if main._should_bail(): return

# --- gym2-13 Misty's Gyarados — Rebellion ---
# When Gyarados attacks, flip 2 coins. Both tails: attack does nothing AND shuffle Gyarados+attached into deck.
# Works through Confusion.
# Returns true if attack was negated.
func check_rebellion(attacker: card_object, is_opp: bool) -> bool:
	if attacker == null:
		return false
	var has_it: bool = false
	for ab in attacker.metadata.get("abilities", []):
		if ab.get("name", "") == "Rebellion":
			has_it = true
			break
	if not has_it:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Owner flips
	var attacker_is_player: bool = not is_opp
	var c1 = await main.flip_coin(not attacker_is_player, attacker_is_player)
	if main._should_bail(): return false
	var c2 = await main.flip_coin(not attacker_is_player, attacker_is_player)
	if main._should_bail(): return false
	if c1 or c2:
		await main.show_message("REBELLION: AT LEAST ONE HEADS — ATTACK PROCEEDS!")
		return false
	await main.show_message("REBELLION: TWO TAILS — ATTACK FIZZLES!")
	if main._should_bail(): return true
	# Shuffle Gyarados + attached into deck
	var deck = main.opponent_deck if is_opp else main.player_deck
	for e in attacker.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	attacker.attached_energies.clear()
	for c in attacker.attached_cards:
		c.current_location = "deck"
		deck.append(c)
	attacker.attached_cards.clear()
	for pre in attacker.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	attacker.attached_pre_evolutions.clear()
	attacker.current_hp = attacker.get_max_hp()
	attacker.special_condition = ""
	attacker.is_poisoned = false
	attacker.is_burned = false
	attacker.pluspower_count = 0
	attacker.defender_turns_remaining = -1
	attacker.current_location = "deck"
	if attacker == main.opponent_active_pokemon:
		main.opponent_active_pokemon = null
	elif attacker == main.player_active_pokemon:
		main.player_active_pokemon = null
	elif attacker in main.opponent_bench:
		main.opponent_bench.erase(attacker)
	elif attacker in main.player_bench:
		main.player_bench.erase(attacker)
	deck.append(attacker)
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("MISTY'S GYARADOS WAS SHUFFLED INTO DECK!")
	if main._should_bail(): return true
	# If Gyarados was the active, post-KO logic triggers (must pick new active)
	if (is_opp and main.opponent_active_pokemon == null) or (not is_opp and main.player_active_pokemon == null):
		await main.handle_post_knockout(is_opp)
	return true

# --- gym2-16 Sabrina's Alakazam — Psylink ---
# Alakazam always has a copy of every attack of your Psychic Pokemon in play, with their original cost.
# Returns the merged attack list (Alakazam's own + every other Psychic-typed pokemon you control).
func get_psylink_attacks(alakazam: card_object, is_alakazam_opp: bool) -> Array:
	var attacks: Array = alakazam.metadata.get("attacks", []).duplicate()
	if not _power_active_on(alakazam, "Psylink", false):
		return attacks
	var own_field: Array = []
	var own_active = main.opponent_active_pokemon if is_alakazam_opp else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_alakazam_opp else main.player_bench
	if own_active != null:
		own_field.append(own_active)
	own_field.append_array(own_bench)
	for p in own_field:
		if p == alakazam:
			continue
		if "Psychic" not in p.metadata.get("types", []):
			continue
		for atk in p.metadata.get("attacks", []):
			attacks.append(atk)
	return attacks

# --- gym2-21 Blaine's Ninetales — Healing Fire ---
# When a Fire energy is attached to Ninetales from hand, remove 1 damage counter.
# Blocked if Asleep/Confused/Paralyzed.
func check_healing_fire(pokemon: card_object, energy: card_object, is_opp: bool) -> void:
	if pokemon == null or energy == null:
		return
	if not _power_active_on(pokemon, "Healing Fire", false):
		return
	# Energy must provide Fire
	var provided = main.get_energy_provided_by_card(energy)
	if "Fire" not in provided:
		return
	var max_hp = int(pokemon.metadata.get("hp", "0"))
	if pokemon.current_hp >= max_hp:
		return
	# MATCH EFFECTS: no_healing / healing_multiplier gate
	var rule_heal = main.match_effects.modify_heal_amount(10, is_opp)
	if rule_heal <= 0:
		return
	var actual_heal = min(rule_heal, max_hp - pokemon.current_hp)
	pokemon.current_hp = min(max_hp, pokemon.current_hp + rule_heal)
	main.display_hp_circles_above_align(pokemon, is_opp)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("HEALING FIRE: " + pokemon.metadata.get("name", "").to_upper() + " HEALED " + str(actual_heal) + " HP!")
	if main._should_bail(): return

# --- gym2-26 Koga's Muk — Energy Drain ---
# When an opp attack damages Muk, flip; heads, discard 1 energy from the attacker.
# Works even if Muk KO'd. Blocked if Muk was Asleep/Confused/Paralyzed when attacked.
func check_energy_drain(damaged_pokemon: card_object, attacker: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Energy Drain":
			has_it = true
			break
	if not has_it:
		return
	if damaged_pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	if attacker.attached_energies.size() == 0:
		return
	# Owner of Muk flips
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY DRAIN: TAILS!")
		return
	# Owner of Muk chooses which energy to discard
	var chosen_energy: card_object = null
	if defender_is_player:
		chosen_energy = await main.card_ops.prompt_select_card(attacker.attached_energies, "ENERGY DRAIN", "Choose 1 energy on the attacker to discard", "SELECT", false)
		if main._should_bail(): return
	else:
		# CPU picks first energy
		chosen_energy = attacker.attached_energies[0]
	if chosen_energy == null:
		return
	attacker.attached_energies.erase(chosen_energy)
	chosen_energy.current_location = "discard"
	var attacker_is_opp: bool = not is_damaged_opp
	var discard_pile = main.opponent_discard_pile if attacker_is_opp else main.player_discard_pile
	discard_pile.append(chosen_energy)
	main.display_active_pokemon_energies(attacker_is_opp)
	main.update_discard_pile_display(attacker_is_opp)
	await main.show_message("ENERGY DRAIN: DISCARDED " + chosen_energy.metadata.get("name", "").to_upper() + "!")
	if main._should_bail(): return

# --- gym2-35 Brock's Primeape — Scram ---
# If Primeape ever has exactly 10 HP left, shuffle it (and attached cards) into deck.
# Blocked if Asleep/Confused/Paralyzed.
# Returns true if scrammed.
func check_scram(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null:
		return false
	if pokemon.current_hp != 10:
		return false
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Scram":
			has_it = true
			break
	if not has_it:
		return false
	if pokemon.special_condition in ["Asleep", "Confused", "Paralyzed"]:
		return false
	if is_toxic_gas_active() or main.goop_gas_active:
		return false
	# Shuffle into deck
	var deck = main.opponent_deck if is_opp else main.player_deck
	for e in pokemon.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	pokemon.attached_energies.clear()
	for c in pokemon.attached_cards:
		c.current_location = "deck"
		deck.append(c)
	pokemon.attached_cards.clear()
	for pre in pokemon.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.current_location = "deck"
	if pokemon == main.opponent_active_pokemon:
		main.opponent_active_pokemon = null
	elif pokemon == main.player_active_pokemon:
		main.player_active_pokemon = null
	elif pokemon in main.opponent_bench:
		main.opponent_bench.erase(pokemon)
	elif pokemon in main.player_bench:
		main.player_bench.erase(pokemon)
	deck.append(pokemon)
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("SCRAM: " + pokemon.metadata.get("name", "").to_upper() + " WAS SHUFFLED INTO DECK!")
	if main._should_bail(): return true
	return true

# --- gym2-38 Erika's Bellsprout — Soak Up ---
# Once/turn: move up to 2 Grass energy from your other pokemon to Bellsprout.
func power_soak_up(bellsprout: card_object) -> void:
	if bellsprout == null or bellsprout.power_used_this_turn:
		return
	var is_opp: bool = (bellsprout == main.opponent_active_pokemon or bellsprout in main.opponent_bench)
	# Build source pokemon list (any of your other pokemon with Grass energy)
	var moved_count := 0
	for _i in range(2):
		var sources: Array = []
		var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
		var bench = main.opponent_bench if is_opp else main.player_bench
		var all_p: Array = []
		if active != null:
			all_p.append(active)
		all_p.append_array(bench)
		for p in all_p:
			if p == bellsprout:
				continue
			for e in p.attached_energies:
				if "Grass" in main.get_energy_provided_by_card(e):
					sources.append(p)
					break
		if sources.size() == 0:
			break
		var source: card_object = null
		if is_opp:
			source = sources[0]
		else:
			if sources.size() == 1:
				source = sources[0]
			else:
				source = await main.card_ops.prompt_select_card(sources, "SOAK UP (" + str(moved_count) + "/2)", "Choose a Pokemon to take Grass Energy from (or cancel to stop)", "SELECT", true)
				if main._should_bail(): return
			if source == null:
				break
		var moved: card_object = null
		for e in source.attached_energies:
			if "Grass" in main.get_energy_provided_by_card(e):
				moved = e
				break
		if moved == null:
			break
		source.attached_energies.erase(moved)
		bellsprout.attached_energies.append(moved)
		moved_count += 1
		main.display_active_pokemon_energies(is_opp)
		main.display_pokemon(is_opp)
	bellsprout.power_used_this_turn = true
	if moved_count > 0:
		await main.show_message("SOAK UP: MOVED " + str(moved_count) + " GRASS ENERGY!")
		if main._should_bail(): return
	elif not is_opp:
		await main.show_message("NO GRASS ENERGY TO MOVE!")

# --- gym2-41 Erika's Ivysaur — Relaxing Scent ---
# While Ivysaur is your Active Pokemon, all damage (after W/R) to any pokemon is halved (round up to nearest 10).
func is_relaxing_scent_active_on_side(is_opp: bool) -> bool:
	var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
	if active == null:
		return false
	return _power_active_on(active, "Relaxing Scent", false)

func apply_relaxing_scent(damage: int) -> int:
	if damage <= 0:
		return damage
	if not (is_relaxing_scent_active_on_side(true) or is_relaxing_scent_active_on_side(false)):
		return damage
	# Round UP to nearest 10
	var half = int(ceil(damage / 2.0 / 10.0)) * 10
	print("RELAXING SCENT: ", damage, " -> ", half)
	return half

# --- gym2-47 Koga's Kakuna — Emerge ---
# Once/turn: flip heads, search deck for "Koga's Beedrill" and evolve Kakuna into it (free, bypasses placed-this-turn).
func power_emerge(kakuna: card_object) -> void:
	if kakuna == null or kakuna.power_used_this_turn:
		return
	var is_opp: bool = (kakuna == main.opponent_active_pokemon or kakuna in main.opponent_bench)
	var deck = main.opponent_deck if is_opp else main.player_deck
	# Find Koga's Beedrill in deck
	var beedrills: Array = []
	for c in deck:
		if c.metadata.get("name", "") == "Koga's Beedrill" and c.metadata.get("evolvesFrom", "") == "Koga's Kakuna":
			beedrills.append(c)
	if beedrills.size() == 0:
		if not is_opp:
			await main.show_message("NO KOGA'S BEEDRILL IN DECK!")
		return
	kakuna.power_used_this_turn = true
	var coin = await main.flip_coin(is_opp, not is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("EMERGE: TAILS!")
		return
	# Evolve: move Kakuna to attached_pre_evolutions of Beedrill, replace card in active/bench
	var beedrill: card_object = beedrills[0]
	deck.erase(beedrill)
	beedrill.current_hp = beedrill.get_max_hp()
	beedrill.current_location = "active" if kakuna == (main.opponent_active_pokemon if is_opp else main.player_active_pokemon) else "bench"
	# Carry damage forward
	var kakuna_max = int(kakuna.metadata.get("hp", "0"))
	var damage_taken = kakuna_max - kakuna.current_hp
	beedrill.current_hp = max(10, int(beedrill.metadata.get("hp", "0")) - damage_taken)
	# Carry attachments
	beedrill.attached_energies = kakuna.attached_energies.duplicate()
	beedrill.attached_cards = kakuna.attached_cards.duplicate()
	beedrill.attached_pre_evolutions = kakuna.attached_pre_evolutions.duplicate()
	# Demote Kakuna into the pre-evolution chain
	kakuna.current_location = "attached_preevo"
	beedrill.attached_pre_evolutions.append(kakuna)
	# Replace in board
	if kakuna == main.opponent_active_pokemon:
		main.opponent_active_pokemon = beedrill
	elif kakuna == main.player_active_pokemon:
		main.player_active_pokemon = beedrill
	elif kakuna in main.opponent_bench:
		var idx = main.opponent_bench.find(kakuna)
		main.opponent_bench[idx] = beedrill
	elif kakuna in main.player_bench:
		var idx = main.player_bench.find(kakuna)
		main.player_bench[idx] = beedrill
	# Mark evolution sickness off (Koga's Beedrill should still get attack)
	beedrill.placed_on_field_this_turn = false
	deck.shuffle()
	main.display_pokemon(is_opp)
	main.display_active_pokemon_energies(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("EMERGE: KAKUNA EVOLVED INTO KOGA'S BEEDRILL!")
	if main._should_bail(): return

# --- gym2-52 Lt. Surge's Electrode — Shock Blast ---
# If Active Electrode gets damaged (even if KO'd), flip; tails -> 20 damage to BOTH actives.
# Works through ALL status.
func check_shock_blast(damaged_pokemon: card_object, is_damaged_opp: bool) -> void:
	if damaged_pokemon == null:
		return
	if damaged_pokemon != (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon):
		return
	var has_it: bool = false
	for ab in damaged_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Shock Blast":
			has_it = true
			break
	if not has_it:
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		return
	var defender_is_player: bool = not is_damaged_opp
	var coin = await main.flip_coin(not defender_is_player, defender_is_player)
	if main._should_bail(): return
	if coin:
		await main.show_message("SHOCK BLAST: HEADS — NO EFFECT!")
		return
	# Tails: 20 to BOTH actives
	var both: Array = []
	if main.player_active_pokemon != null:
		both.append({"p": main.player_active_pokemon, "is_opp": false})
	if main.opponent_active_pokemon != null:
		both.append({"p": main.opponent_active_pokemon, "is_opp": true})
	for info in both:
		var p = info["p"]
		p.current_hp = max(0, p.current_hp - 20)
		main.display_hp_circles_above_align(p, info["is_opp"])
		var lbl_pos = Vector2(1030, 300) if info["is_opp"] else Vector2(530, 300)
		main.show_floating_label("-20HP", lbl_pos, true)
	await main.show_message("SHOCK BLAST: TAILS — 20 DAMAGE TO BOTH ACTIVES!")
	if main._should_bail(): return

# --- gym2-97 Sabrina's Gastly — Gaseous Form ---
# +10 HP per Psychic energy attached. Works through status.
# Returns the effective max HP for any pokemon (call from get_max_hp path).
func compute_gaseous_form_bonus_hp(pokemon: card_object) -> int:
	if pokemon == null:
		return 0
	var has_it: bool = false
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Gaseous Form":
			has_it = true
			break
	if not has_it:
		return 0
	if is_toxic_gas_active() or main.goop_gas_active:
		return 0
	var psy := 0
	for e in pokemon.attached_energies:
		if "Psychic" in main.get_energy_provided_by_card(e):
			psy += 1
	return psy * 10

# Recomputes max_hp_override for any pokemon with Gaseous Form when its energies change.
# Called after every energy attach / discard.
func refresh_gaseous_form_hp() -> void:
	var all_p: Array = []
	if main.player_active_pokemon != null:
		all_p.append(main.player_active_pokemon)
	all_p.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_p.append(main.opponent_active_pokemon)
	all_p.append_array(main.opponent_bench)
	for p in all_p:
		var bonus = compute_gaseous_form_bonus_hp(p)
		if bonus > 0:
			var base = int(p.metadata.get("hp", "0"))
			var new_max = base + bonus
			# Preserve damage taken when raising/lowering the cap
			var damage_taken = max(0, p.max_hp_override - p.current_hp) if p.max_hp_override > 0 else (base - p.current_hp)
			p.max_hp_override = new_max
			p.current_hp = max(0, new_max - damage_taken)
		else:
			# Only clear override if it was set BY Gaseous Form (use ability presence check)
			var has_it: bool = false
			for ab in p.metadata.get("abilities", []):
				if ab.get("name", "") == "Gaseous Form":
					has_it = true
					break
			if has_it and p.max_hp_override > 0:
				var base2 = int(p.metadata.get("hp", "0"))
				var damage_taken2 = max(0, p.max_hp_override - p.current_hp)
				p.max_hp_override = 0
				p.current_hp = max(0, base2 - damage_taken2)

# Recomputes max_hp_override for Dark-named pokemon under Rocket's Hideout (neo3 stadium, +20 HP).
# Called whenever the stadium is played/removed, and each between-turn check as a safety net for
# pokemon placed onto the field while the stadium is already active. Reuses
# trainer_effects.rockets_hideout_bonus_hp() rather than re-implementing the eligibility check.
func refresh_rockets_hideout_hp() -> void:
	var all_p: Array = []
	if main.player_active_pokemon != null:
		all_p.append(main.player_active_pokemon)
	all_p.append_array(main.player_bench)
	if main.opponent_active_pokemon != null:
		all_p.append(main.opponent_active_pokemon)
	all_p.append_array(main.opponent_bench)
	for p in all_p:
		# Both are stadiums (mutually exclusive), so at most one bonus is ever non-zero.
		var bonus = main.trainer_effects.rockets_hideout_bonus_hp(p) + main.trainer_effects.low_pressure_bonus_hp(p)
		if bonus > 0:
			var base = int(p.metadata.get("hp", "0"))
			var new_max = base + bonus
			# Preserve damage taken when raising/lowering the cap
			var damage_taken = max(0, p.max_hp_override - p.current_hp) if p.max_hp_override > 0 else (base - p.current_hp)
			p.max_hp_override = new_max
			p.current_hp = max(0, new_max - damage_taken)
		else:
			# Only clear an override that could have been set by a stadium HP bonus (Dark-named for
			# Rocket's Hideout, Grass/Lightning-typed for Low Pressure System). Never touch a
			# Gaseous Form override (that system owns its own holders and refreshes separately).
			var has_gaseous = false
			for ab in p.metadata.get("abilities", []):
				if ab.get("name", "") == "Gaseous Form":
					has_gaseous = true
					break
			var eff_types = p.get_effective_types()
			var stadium_eligible = "Dark" in p.metadata.get("name", "") or "Grass" in eff_types or "Lightning" in eff_types
			if stadium_eligible and p.max_hp_override > 0 and not has_gaseous:
				var base2 = int(p.metadata.get("hp", "0"))
				var damage_taken2 = max(0, p.max_hp_override - p.current_hp)
				p.max_hp_override = 0
				p.current_hp = max(0, base2 - damage_taken2)

######################################################################################################################################################
######################################################## GYM1 + GYM2 CPU POWER ACTIVATIONS ###########################################################
######################################################################################################################################################

# Called from cpu_phase_activate_powers() to activate gym1/gym2 active powers in CPU's turn.
func cpu_phase_gym_powers() -> void:
	# --- Energy Charge (gym1-8 Lt. Surge's Magneton) ---
	var magneton = _find_pokemon_with_power_on_side("Energy Charge", true)
	if magneton != null and magneton == main.opponent_active_pokemon and _power_active_on(magneton, "Energy Charge", false):
		var keep_going: bool = true
		while keep_going:
			keep_going = false
			# Find a bench source with Lightning energy
			var src: card_object = null
			for bp in main.opponent_bench:
				for e in bp.attached_energies:
					if "Lightning" in main.get_energy_provided_by_card(e):
						# Only steal if the source has spare energy
						if bp.attached_energies.size() > 1 or _cpu_unmet_energy(bp) > 0:
							src = bp
							break
				if src != null:
					break
			if src == null:
				break
			# Only consolidate if Magneton actually needs Lightning
			if _cpu_unmet_energy(magneton) == 0:
				break
			await power_energy_charge(magneton)
			if main._should_bail(): return
			keep_going = true

	# --- Fragrance Trap (gym1-26 Erika's Victreebel) ---
	var victreebel = _find_pokemon_with_power_on_side("Fragrance Trap", true)
	if victreebel != null and not victreebel.power_used_this_turn and _power_active_on(victreebel, "Fragrance Trap", false):
		# Only use if player has bench targets weaker than their active
		if main.player_bench.size() > 0 and main.player_active_pokemon != null:
			var pa_hp = float(main.player_active_pokemon.current_hp)
			var has_weaker: bool = false
			for bp in main.player_bench:
				if float(bp.current_hp) < pa_hp:
					has_weaker = true
					break
			if has_weaker:
				await power_fragrance_trap(victreebel)
				if main._should_bail(): return

	# --- Natural Healing (gym1-65 Blaine's Vulpix) ---
	var vulpix = _find_pokemon_with_power_on_side("Natural Healing", true)
	if vulpix != null and not vulpix.power_used_this_turn and _power_active_on(vulpix, "Natural Healing", false):
		if vulpix.current_hp < int(vulpix.metadata.get("hp", "0")):
			await power_natural_healing(vulpix)
			if main._should_bail(): return

	# --- Shapeshift (gym2-3 Brock's Ninetales) ---
	var ninetales = _find_pokemon_with_power_on_side("Shapeshift", true)
	if ninetales != null and not ninetales.power_used_this_turn and _power_active_on(ninetales, "Shapeshift", false):
		# Use if CPU has any evolution card in hand
		var has_evo: bool = false
		for c in main.opponent_hand:
			if c.metadata.get("supertype", "").to_lower() in ["pokémon", "pokemon"]:
				var sts = c.metadata.get("subtypes", [])
				if "Stage 1" in sts or "Stage 2" in sts:
					has_evo = true
					break
		if has_evo and ninetales.shapeshift_form_card == null:
			await power_shapeshift(ninetales)
			if main._should_bail(): return

	# --- Soak Up (gym2-38 Erika's Bellsprout) ---
	var bellsprout = _find_pokemon_with_power_on_side("Soak Up", true)
	if bellsprout != null and not bellsprout.power_used_this_turn and _power_active_on(bellsprout, "Soak Up", false):
		# Use if any other CPU pokemon has Grass energy and Bellsprout still needs energy
		if _cpu_unmet_energy(bellsprout) > 0:
			var has_grass: bool = false
			var all_p: Array = []
			if main.opponent_active_pokemon != null:
				all_p.append(main.opponent_active_pokemon)
			all_p.append_array(main.opponent_bench)
			for p in all_p:
				if p == bellsprout:
					continue
				for e in p.attached_energies:
					if "Grass" in main.get_energy_provided_by_card(e):
						has_grass = true
						break
				if has_grass:
					break
			if has_grass:
				await power_soak_up(bellsprout)
				if main._should_bail(): return

	# --- Emerge (gym2-47 Koga's Kakuna) ---
	var kakuna = _find_pokemon_with_power_on_side("Emerge", true)
	if kakuna != null and not kakuna.power_used_this_turn and _power_active_on(kakuna, "Emerge", false):
		# Use if Koga's Beedrill exists in deck
		var has_beedrill: bool = false
		for c in main.opponent_deck:
			if c.metadata.get("name", "") == "Koga's Beedrill" and c.metadata.get("evolvesFrom", "") == "Koga's Kakuna":
				has_beedrill = true
				break
		if has_beedrill:
			await power_emerge(kakuna)
			if main._should_bail(): return

# Helper: cumulative unmet energy across all of a pokemon's attacks (cheap CPU heuristic)
func _cpu_unmet_energy(p: card_object) -> int:
	var best := 9999
	for atk in p.metadata.get("attacks", []):
		var u = main.cpu_ai.get_unmet_energy_count(atk, p)
		if u < best:
			best = u
	return best if best < 9999 else 0

######################################################################################################################################################
############################################################## BASEP POWERS & BODIES ###############################################################
######################################################################################################################################################

# SPECIAL DELIVERY (basep-5 Dragonite): draw 1 card, then put 1 card from hand on top of deck
func power_special_delivery(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("SPECIAL DELIVERY IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SPECIAL DELIVERY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var is_opponent = pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench
	await main.show_message("SPECIAL DELIVERY: DRAWING A CARD...")
	if main._should_bail(): return
	await main.card_ops.draw_n(is_opponent, 1)
	if main._should_bail(): return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if hand.size() == 0:
		return
	var chosen: card_object
	if is_opponent:
		# CPU: put the least-useful card back on top (lowest-priority card, e.g. excess energy)
		chosen = hand[hand.size() - 1]
	else:
		chosen = await main.card_ops.prompt_select_card(hand, "SPECIAL DELIVERY — PUT ON TOP OF DECK", "Choose a card to put on top of your deck", "PLACE", false)
		if main._should_bail(): return
		if chosen == null:
			chosen = hand[hand.size() - 1]
	hand.erase(chosen)
	chosen.current_location = "deck"
	deck.push_front(chosen)
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SPECIAL DELIVERY! CARD PLACED ON TOP OF DECK!")
	if main._should_bail(): return
	print("POWER USED: Special Delivery")

# SOLAR POWER (basep-13 Venusaur): clear all status from both Active Pokemon
func power_solar_power(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("SOLAR POWER IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SOLAR POWER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var player_active = main.player_active_pokemon
	var opp_active = main.opponent_active_pokemon
	if player_active != null:
		main.clear_all_statuses(player_active, false)
	if opp_active != null:
		main.clear_all_statuses(opp_active, true)
	await main.show_message("SOLAR POWER! ALL STATUS CONDITIONS CURED!")
	if main._should_bail(): return
	print("POWER USED: Solar Power")

# [JOIN] (basep-38 Unown J): if all 4 Unown (J, O, I, Dragon) are on bench, search deck for any card
func power_join_unown(pokemon: card_object) -> void:
	if is_power_blocked(pokemon):
		await main.show_message("[JOIN] IS BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[JOIN] ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var is_opponent = pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var required = ["Unown [J]", "Unown [O]", "Unown [I]", "Unown Dragon"]
	var found: Array = []
	for bp in bench:
		var bname = bp.metadata.get("name", "")
		if bname in required:
			found.append(bname)
	for req in required:
		if req not in found:
			await main.show_message("[JOIN] REQUIRES ALL 4 UNOWN (J, O, I, DRAGON) ON YOUR BENCH!")
			if main._should_bail(): return
			return
	pokemon.power_used_this_turn = true
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if deck.size() == 0:
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = deck[0]
	else:
		chosen = await main.card_ops.prompt_select_card(deck, "[JOIN] — SEARCH YOUR DECK", "Choose any card to put into your hand", "TAKE", false, true)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("[JOIN]! FOUND " + chosen.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Join] Unown")

# BOLT (basep-34 Entei): on-damage hook — if damaged but not KO'd, flip; heads = shuffle into deck
func check_bolt(damaged: card_object, attacker: card_object, damage: int, is_damaged_opp: bool) -> void:
	if damaged == null or damage <= 0:
		return
	if damaged.current_hp <= 0:
		return
	if not damaged.has_ability("Bolt"):
		return
	if is_power_blocked(damaged):
		return
	await main.show_message("BOLT! " + damaged.metadata.get("name","").to_upper() + " FLIPPING TO ESCAPE...")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_damaged_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! ENTEI STAYS!")
		if main._should_bail(): return
		return
	# Heads — shuffle Entei and all attached cards into its deck
	var deck = main.opponent_deck if is_damaged_opp else main.player_deck
	var bench = main.opponent_bench if is_damaged_opp else main.player_bench
	var is_active = (damaged == (main.opponent_active_pokemon if is_damaged_opp else main.player_active_pokemon))
	for e in damaged.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	damaged.attached_energies.clear()
	for pre in damaged.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	damaged.attached_pre_evolutions.clear()
	for ac in damaged.attached_cards:
		ac.current_location = "deck"
		deck.append(ac)
	damaged.attached_cards.clear()
	main.clear_all_statuses(damaged, is_damaged_opp)
	damaged.current_hp = damaged.get_max_hp()
	damaged.current_location = "deck"
	deck.append(damaged)
	deck.shuffle()
	if is_active:
		if is_damaged_opp:
			main.opponent_active_pokemon = null
		else:
			main.player_active_pokemon = null
	else:
		bench.erase(damaged)
	main.display_pokemon(is_damaged_opp)
	main.update_deck_icon(is_damaged_opp)
	await main.show_message("BOLT! ENTEI SHUFFLED INTO THE DECK!")
	if main._should_bail(): return
	if is_active:
		await main.handle_post_knockout(is_damaged_opp)
	if main._should_bail(): return
	print("POWER TRIGGERED: Bolt - Entei shuffled into deck")

# NEUTRAL SHIELD (basep-47 Mew): prevent all effects from Evolved Pokemon
# Returns true if the attack should be blocked (caller must check this)
func check_neutral_shield(defender: card_object, attacker: card_object) -> bool:
	if defender == null or attacker == null:
		return false
	if not defender.has_ability("Neutral Shield"):
		return false
	if is_power_blocked(defender):
		return false
	var subtypes = attacker.metadata.get("subtypes", [])
	if "Stage 1" in subtypes or "Stage 2" in subtypes:
		print("NEUTRAL SHIELD: Blocked attack from evolved Pokemon ", attacker.metadata.get("name",""))
		return true
	return false

# AURORA VEIL (basep-48 Articuno): bench Pokemon immune to damage while Articuno is active
# Returns true if bench damage is blocked (caller must skip the damage)
func check_aurora_veil(bench_owner_is_opp: bool) -> bool:
	var active = main.opponent_active_pokemon if bench_owner_is_opp else main.player_active_pokemon
	if active == null:
		return false
	if not active.has_ability("Aurora Veil"):
		return false
	if is_power_blocked(active):
		return false
	print("AURORA VEIL: Bench damage blocked for ", "opponent" if bench_owner_is_opp else "player")
	return true

# CHAIN REACTION (basep-11 Eevee): evolve all Eevees in play using Evolution cards from hand
func power_chain_reaction(eevee: card_object) -> void:
	if is_power_blocked_by_status(eevee):
		await main.show_message("CHAIN REACTION BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if eevee.power_used_this_turn:
		await main.show_message("CHAIN REACTION ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var is_opp: bool = (eevee == main.opponent_active_pokemon or eevee in main.opponent_bench)
	var hand = main.opponent_hand if is_opp else main.player_hand
	var active = main.opponent_active_pokemon if is_opp else main.player_active_pokemon
	var bench = main.opponent_bench if is_opp else main.player_bench
	# Collect all Eevees in play
	var eevees: Array = []
	if active != null and active.metadata.get("name", "") == "Eevee":
		eevees.append(active)
	for bp in bench:
		if bp.metadata.get("name", "") == "Eevee":
			eevees.append(bp)
	if eevees.size() == 0:
		await main.show_message("NO EEVEES IN PLAY!")
		if main._should_bail(): return
		return
	# Check for evolution cards in hand
	var has_evo: bool = false
	for c in hand:
		if c.metadata.get("evolvesFrom", "") == "Eevee":
			has_evo = true
			break
	if not has_evo:
		await main.show_message("NO EEVEE EVOLUTION CARDS IN HAND!")
		if main._should_bail(): return
		return
	eevee.power_used_this_turn = true
	await main.show_message("CHAIN REACTION! EVOLVING ALL EEVEES!")
	if main._should_bail(): return
	for target_eevee in eevees:
		var available_evo: Array = []
		for c in hand:
			if c.metadata.get("evolvesFrom", "") == "Eevee":
				available_evo.append(c)
		if available_evo.size() == 0:
			break
		var chosen_evo: card_object = null
		if is_opp:
			chosen_evo = available_evo[0]
			for c in available_evo:
				if int(c.metadata.get("hp", "0")) > int(chosen_evo.metadata.get("hp", "0")):
					chosen_evo = c
		else:
			if available_evo.size() == 1:
				chosen_evo = available_evo[0]
			else:
				chosen_evo = await main.card_ops.prompt_select_card(available_evo, "CHAIN REACTION: EVOLVE " + target_eevee.metadata.get("name", "").to_upper(), "Choose an Evolution for this Eevee (cancel to skip)", "EVOLVE", true)
				if main._should_bail(): return
			if chosen_evo == null:
				continue
		# Perform evolution (mirrors perform_evolution in Main)
		var max_hp_old = int(target_eevee.metadata.get("hp", "0"))
		var damage_taken = max_hp_old - target_eevee.current_hp
		var max_hp_new = int(chosen_evo.metadata.get("hp", "0"))
		chosen_evo.current_hp = max(1, max_hp_new - damage_taken)
		chosen_evo.attached_energies = target_eevee.attached_energies.duplicate()
		target_eevee.attached_energies.clear()
		chosen_evo.attached_pre_evolutions = target_eevee.attached_pre_evolutions.duplicate()
		target_eevee.attached_pre_evolutions.clear()
		chosen_evo.attached_pre_evolutions.append(target_eevee)
		chosen_evo.placed_on_field_this_turn = true
		hand.erase(chosen_evo)
		chosen_evo.current_location = target_eevee.current_location
		var is_active_slot = (target_eevee == (main.opponent_active_pokemon if is_opp else main.player_active_pokemon))
		if is_active_slot:
			if is_opp:
				main.opponent_active_pokemon = chosen_evo
			else:
				main.player_active_pokemon = chosen_evo
		else:
			var bench_idx = bench.find(target_eevee)
			if bench_idx >= 0:
				bench[bench_idx] = chosen_evo
		main.clear_all_statuses(target_eevee, is_opp)
		main.display_pokemon(is_opp)
		main.display_active_pokemon_energies(is_opp)
		main.refresh_hand_display(is_opp)
		await main.show_message("CHAIN REACTION: " + target_eevee.metadata.get("name", "").to_upper() + " EVOLVED INTO " + chosen_evo.metadata.get("name", "").to_upper() + "!")
		if main._should_bail(): return
	print("POWER USED: Chain Reaction")

# PURE BODY (basep-53/np-30 Suicune): attaching a Water Energy to Suicune forces it to discard one
# of its own attached energies; if Suicune has none attached, Water Energy can't be attached at all.
# Block check lives in Special_Energy_Effects.can_attach_to() + the pre-attach gates in Main/CPU_AI;
# the discard trigger is check_pure_body_discard() below, called after the attach completes.

# GUARD (basep-49 Snorlax): defending Pokemon can't retreat while Snorlax is active
# Returns true if retreat should be blocked (called from can_retreat)
func check_guard_body(is_retreating_opp: bool) -> bool:
	# The OPPOSING active Pokémon is the one that might have Guard
	var blocking_active = main.player_active_pokemon if is_retreating_opp else main.opponent_active_pokemon
	if blocking_active == null:
		return false
	# Snorlax Guard (basep-49) and Cradily Super Suction Cups (ex2-3) both block the opposing
	# Active from retreating while they are Active.
	if not (blocking_active.has_ability("Guard") or blocking_active.has_ability("Super Suction Cups")):
		return false
	if is_power_blocked(blocking_active):
		return false
	print("GUARD: Retreat blocked by opposing Active body (", blocking_active.metadata.get("name",""), ")")
	return true

######################################################################################################################################################
############################################################## NEO1 (NEO GENESIS) POWERS & BODIES ####################################################
######################################################################################################################################################

# ── Register neo1 powers in the dispatch ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
func _register_neo1_powers() -> void:
	_power_dispatch["Downpour"]           = func(p): await power_neo1_downpour(p)
	_power_dispatch["Fire Recharge"]      = func(p): await power_neo1_fire_recharge(p)
	_power_dispatch["Glaring Gaze"]       = func(p): await power_neo1_glaring_gaze(p)
	_power_dispatch["Playful Punch"]      = func(p): await power_neo1_playful_punch(p)

# Called from _register_all_powers at startup

# ── Passive checks (called directly from Main / Attack_Effects) ────────────────────────────────────────────────────────────────────────────────────────

# WILD GROWTH (neo1-11 Meganium): each Grass Energy on Grass Pokemon counts as 2 Grass
# Called from get_energy_provided_by_card when a Grass energy is on a Grass pokemon
func is_wild_growth_active() -> bool:
	var all_poke: Array = []
	if main.player_active_pokemon != null: all_poke.append(main.player_active_pokemon)
	if main.opponent_active_pokemon != null: all_poke.append(main.opponent_active_pokemon)
	all_poke.append_array(main.player_bench)
	all_poke.append_array(main.opponent_bench)
	for p in all_poke:
		if _power_active_on(p, "Wild Growth", false):
			return true
	return false

# FINAL BLOW (neo1-6 Heracross): if HP ≤ 20, Megahorn does 120 instead of 60
func get_final_blow_damage(attacker: card_object, attack_name: String, base_damage: int) -> int:
	if attack_name.to_lower() != "megahorn":
		return base_damage
	if not _power_active_on(attacker, "Final Blow", false):
		return base_damage
	if attacker.current_hp > 20:
		return base_damage
	return 120

# HYDROELECTRIC POWER (neo1-38 Lanturn): Floodlight does +10 per extra Water Energy
func get_hydroelectric_bonus(attacker: card_object, attack_name: String) -> int:
	if attack_name.to_lower() != "floodlight":
		return 0
	if not _power_active_on(attacker, "Hydroelectric Power", false):
		return 0
	var attack_cost_water = 0
	for ab in attacker.metadata.get("attacks", []):
		if ab.get("name", "").to_lower() == "floodlight":
			for c in ab.get("cost", []):
				if c == "Water":
					attack_cost_water += 1
			break
	var attached_water = 0
	for e in attacker.attached_energies:
		if "Water" in main.get_energy_provided_by_card(e):
			attached_water += 1
	var extra = max(0, attached_water - attack_cost_water)
	return extra * 10

# SPROUT TOWER (neo1-97 Stadium): Colorless Pokemon attacks reduced by 30
func apply_sprout_tower_reduction(attacker: card_object, damage: int) -> int:
	if not main.is_stadium_in_play(StadiumIds.SPROUT_TOWER):
		return damage
	var types = attacker.metadata.get("types", ["Colorless"])
	if types.is_empty() or types[0] != "Colorless":
		return damage
	return max(0, damage - 30)

# MIND GAMES (neo1-14 Slowking): when opponent plays Trainer, flip — heads: cancel it
# Returns true if the trainer is cancelled (caller must abort trainer effect)
func check_mind_games(is_opponent_playing_trainer: bool) -> bool:
	if is_power_blocked_by_status(null):
		return false
	var mind_games_side = main.opponent_active_pokemon if is_opponent_playing_trainer else main.player_active_pokemon
	var opp_side_bench = main.opponent_bench if is_opponent_playing_trainer else main.player_bench
	var mind_games_pokemon: card_object = null
	var check_bench = main.player_bench if is_opponent_playing_trainer else main.opponent_bench
	var check_active = main.player_active_pokemon if is_opponent_playing_trainer else main.opponent_active_pokemon
	if check_active != null and _power_active_on(check_active, "Mind Games", false):
		mind_games_pokemon = check_active
	if mind_games_pokemon == null:
		for bp in check_bench:
			if _power_active_on(bp, "Mind Games", false):
				mind_games_pokemon = bp
				break
	if mind_games_pokemon == null:
		return false
	var slowking_is_opp = (mind_games_pokemon == main.opponent_active_pokemon or mind_games_pokemon in main.opponent_bench)
	var coin = await main.flip_coin(is_opponent_playing_trainer, slowking_is_opp)
	if main._should_bail(): return false
	if coin:
		await main.show_message("MIND GAMES! " + mind_games_pokemon.metadata.get("name","").to_upper() + " CANCELLED THE TRAINER CARD! IT GOES BACK ON TOP OF DECK!")
		if main._should_bail(): return false
		return true
	await main.show_message("MIND GAMES: TAILS — TRAINER CARD PROCEEDS!")
	if main._should_bail(): return false
	return false

# Check Focus Band (neo1-86 Tool): when KO'd by opponent's attack, flip — heads: survive at 10 HP
func check_focus_band(pokemon: card_object, is_opp: bool) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
		return false
	for card in pokemon.attached_cards:
		if card.metadata.get("name", "") == "Focus Band":
			var coin = await main.flip_coin(is_opp, not is_opp)
			if main._should_bail(): return false
			if coin:
				pokemon.current_hp = 10
				main.display_hp_circles_above_align(pokemon, is_opp)
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
				discard.append(card)
				main.update_discard_pile_display(is_opp)
				await main.show_message("FOCUS BAND! " + pokemon.metadata.get("name","").to_upper() + " SURVIVED WITH 10 HP!")
				if main._should_bail(): return false
				return true
			else:
				await main.show_message("FOCUS BAND: TAILS! " + pokemon.metadata.get("name","").to_upper() + " IS KNOCKED OUT!")
				if main._should_bail(): return false
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard2 = main.opponent_discard_pile if is_opp else main.player_discard_pile
				discard2.append(card)
			break
	return false

# Process Pokemon Tools at start of turn: Gold Berry, Miracle Berry, Berry, Char counter
func process_turn_start_tools_and_counters(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for pokemon in all_poke:
		if main._should_bail(): return
		var poke_is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
		# Char counter: owner must flip — tails = 20 damage
		if pokemon.has_char_counter:
			var coin = await main.flip_coin(false, poke_is_opp)
			if main._should_bail(): return
			if not coin:
				pokemon.current_hp = max(0, pokemon.current_hp - 20)
				main.display_hp_circles_above_align(pokemon, poke_is_opp)
				await main.show_message("CHAR COUNTER! " + pokemon.metadata.get("name","").to_upper() + " TOOK 20 DAMAGE!")
				if main._should_bail(): return
				await main.check_all_knockouts()
				if main._should_bail(): return
		# Tool processing for this side's pokemon only
		if poke_is_opp == is_opponent:
			for tool in pokemon.attached_cards.duplicate():
				if main._should_bail(): return
				var tool_name = tool.metadata.get("name", "")
				var max_hp = pokemon.get_max_hp()
				if tool_name == "Gold Berry":
					# MATCH EFFECTS: healing gate — berry is NOT consumed while healing is blocked
					if max_hp - pokemon.current_hp >= 40 and main.match_effects.modify_heal_amount(40, is_opponent) > 0:
						pokemon.current_hp = min(max_hp, pokemon.current_hp + main.match_effects.modify_heal_amount(40, is_opponent))
						SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
						main.display_hp_circles_above_align(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("GOLD BERRY! " + pokemon.metadata.get("name","").to_upper() + " HEALED 40 HP!")
						if main._should_bail(): return
				elif tool_name == "Berry":
					# MATCH EFFECTS: healing gate — berry is NOT consumed while healing is blocked
					if max_hp - pokemon.current_hp >= 20 and main.match_effects.modify_heal_amount(20, is_opponent) > 0:
						pokemon.current_hp = min(max_hp, pokemon.current_hp + main.match_effects.modify_heal_amount(20, is_opponent))
						SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
						main.display_hp_circles_above_align(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp2 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp2.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("BERRY! " + pokemon.metadata.get("name","").to_upper() + " HEALED 20 HP!")
						if main._should_bail(): return
				elif tool_name == "Miracle Berry":
					if pokemon.special_condition != "" or pokemon.is_poisoned or pokemon.is_burned:
						main.clear_all_statuses(pokemon, is_opponent)
						pokemon.attached_cards.erase(tool)
						tool.current_location = "discard"
						var dp3 = main.opponent_discard_pile if is_opponent else main.player_discard_pile
						dp3.append(tool)
						main.update_discard_pile_display(is_opponent)
						await main.show_message("MIRACLE BERRY! " + pokemon.metadata.get("name","").to_upper() + " CURED OF ALL STATUS CONDITIONS!")
						if main._should_bail(): return

# Clear jaw_clamp_locked at end of opponent's turn (called when clearing retreat flags)
func clear_neo1_flags_end_of_turn(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.jaw_clamp_locked = false
		p.screech_damage_bonus = 0
		p.endure_active = false
	if is_opponent:
		if main.opponent_retreat_disabled and not main.opponent_active_pokemon in []:
			main.opponent_retreat_disabled = false
	else:
		if main.player_retreat_disabled:
			main.player_retreat_disabled = false

# ── On-play triggers ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# BERSERK (neo1-4 Feraligatr): on-play flip — heads: discard top 5 opponent deck; tails: discard top 5 own deck
func trigger_neo1_berserk(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if coin:
		var deck = main.player_deck if is_opp else main.opponent_deck
		var discard = main.player_discard_pile if is_opp else main.opponent_discard_pile
		var target_is_opp = not is_opp
		var n = min(5, deck.size())
		for i in range(n):
			var c = deck[0]
			deck.remove_at(0)
			c.current_location = "discard"
			discard.append(c)
		main.update_discard_pile_display(target_is_opp)
		main.update_deck_icon(target_is_opp)
		await main.show_message("BERSERK! HEADS! DISCARDED TOP " + str(n) + " CARDS FROM OPPONENT'S DECK!")
	else:
		var deck = main.opponent_deck if is_opp else main.player_deck
		var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
		var n = min(5, deck.size())
		for i in range(n):
			var c = deck[0]
			deck.remove_at(0)
			c.current_location = "discard"
			discard.append(c)
		main.update_discard_pile_display(is_opp)
		main.update_deck_icon(is_opp)
		await main.show_message("BERSERK! TAILS! DISCARDED TOP " + str(n) + " CARDS FROM YOUR OWN DECK!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Berserk")

# HERBAL SCENT (neo1-10 Meganium): on-play flip — heads: remove all damage from all Grass Pokemon in play
func trigger_neo1_herbal_scent(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var do_flip: bool = false
	if is_opp:
		do_flip = true
	else:
		do_flip = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "HERBAL SCENT", "Flip a coin? Heads = heal all Grass Pokemon!", "FLIP", "SKIP")
		if main._should_bail(): return
	if not do_flip: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("HERBAL SCENT: TAILS!")
		if main._should_bail(): return
		return
	var all_poke: Array = []
	if main.player_active_pokemon != null: all_poke.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null: all_poke.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench: all_poke.append({"p": bp, "opp": false})
	for bp in main.opponent_bench: all_poke.append({"p": bp, "opp": true})
	var healed_count = 0
	for entry in all_poke:
		var p = entry["p"]
		if "Grass" in p.metadata.get("types", []):
			p.current_hp = p.get_max_hp()
			main.display_hp_circles_above_align(p, entry["opp"])
			healed_count += 1
	if healed_count > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	await main.show_message("HERBAL SCENT! HEADS! FULLY HEALED " + str(healed_count) + " GRASS POKEMON!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Herbal Scent - healed ", healed_count)

# FIRE BOOST (neo1-18 Typhlosion): on-play flip — heads: search deck for up to 4 Fire Energy, attach to self
func trigger_neo1_fire_boost(pokemon: card_object, is_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var do_flip: bool = false
	if is_opp:
		do_flip = true
	else:
		do_flip = await main.trainer_effects.gym1_prompt_yes_no(pokemon, "FIRE BOOST", "Flip a coin? Heads = attach up to 4 Fire Energy from deck!", "FLIP", "SKIP")
		if main._should_bail(): return
	if not do_flip: return
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FIRE BOOST: TAILS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opp else main.player_deck
	var fire_in_deck: Array = []
	for c in deck:
		if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
			fire_in_deck.append(c)
	if fire_in_deck.size() == 0:
		await main.show_message("FIRE BOOST: HEADS! BUT NO FIRE ENERGY IN DECK!")
		if main._should_bail(): return
		return
	var picks = min(4, fire_in_deck.size())
	for i in range(picks):
		var e = fire_in_deck[i]
		deck.erase(e)
		e.current_location = "attached"
		pokemon.attached_energies.append(e)
	deck.shuffle()
	main.display_active_pokemon_energies(is_opp)
	main.update_deck_icon(is_opp)
	await main.show_message("FIRE BOOST! HEADS! ATTACHED " + str(picks) + " FIRE ENERGY TO TYPHLOSION!")
	if main._should_bail(): return
	print("POWER TRIGGERED: Fire Boost - attached ", picks, " fire energy")

# ── Active power implementations ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# DOWNPOUR (neo1-5 Feraligatr): discard a Water Energy from hand as often as you like
func power_neo1_downpour(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("DOWNPOUR BLOCKED BY STATUS!")
		return
	var hand = main.opponent_hand if is_opp else main.player_hand
	var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
	var water_in_hand: Array = []
	for c in hand:
		if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
			water_in_hand.append(c)
	if water_in_hand.size() == 0:
		if not is_opp: await main.show_message("NO WATER ENERGY IN HAND TO DISCARD!")
		return
	if is_opp:
		var e = water_in_hand[0]
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
		main.refresh_hand_display(is_opp)
		main.update_discard_pile_display(is_opp)
		await main.show_message("DOWNPOUR: DISCARDED A WATER ENERGY!")
		if main._should_bail(): return
	else:
		var e = await main.card_ops.prompt_select_card(water_in_hand, "DOWNPOUR: DISCARD WATER ENERGY", "Choose a Water Energy to discard (increases Riptide damage)", "DISCARD", true)
		if main._should_bail(): return
		if e == null: return
		hand.erase(e)
		e.current_location = "discard"
		discard.append(e)
		main.refresh_hand_display(is_opp)
		main.update_discard_pile_display(is_opp)
		await main.show_message("DOWNPOUR: DISCARDED A WATER ENERGY!")
		if main._should_bail(): return
	print("POWER USED: Downpour")

# FIRE RECHARGE (neo1-17 Typhlosion): flip — heads: attach Fire Energy from discard to a Fire Pokemon
func power_neo1_fire_recharge(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("FIRE RECHARGE BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("FIRE RECHARGE ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("FIRE RECHARGE: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opp else main.player_discard_pile
	var fire_in_discard: Array = []
	for c in discard:
		if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
			fire_in_discard.append(c)
	if fire_in_discard.size() == 0:
		await main.show_message("FIRE RECHARGE: HEADS! BUT NO FIRE ENERGY IN DISCARD!")
		if main._should_bail(): return
		return
	var fire_poke: Array = []
	var all_p: Array = []
	if main.opponent_active_pokemon != null and is_opp: all_p.append(main.opponent_active_pokemon)
	if main.player_active_pokemon != null and not is_opp: all_p.append(main.player_active_pokemon)
	all_p.append_array(main.opponent_bench if is_opp else main.player_bench)
	for p in all_p:
		if "Fire" in p.metadata.get("types", []):
			fire_poke.append(p)
	if fire_poke.size() == 0:
		await main.show_message("FIRE RECHARGE: HEADS! BUT NO FIRE POKEMON IN PLAY!")
		if main._should_bail(): return
		return
	var target: card_object = null
	var energy: card_object = null
	if is_opp:
		target = fire_poke[0]
		energy = fire_in_discard[0]
	else:
		if fire_poke.size() == 1: target = fire_poke[0]
		else:
			target = await main.card_ops.prompt_select_card(fire_poke, "FIRE RECHARGE: CHOOSE TARGET", "Choose a Fire Pokemon to attach energy to", "SELECT", false)
			if main._should_bail(): return
		if target == null: return
		if fire_in_discard.size() == 1: energy = fire_in_discard[0]
		else:
			energy = await main.card_ops.prompt_select_card(fire_in_discard, "FIRE RECHARGE: CHOOSE ENERGY", "Choose a Fire Energy from discard", "ATTACH", false)
			if main._should_bail(): return
		if energy == null: return
	discard.erase(energy)
	energy.current_location = "attached"
	target.attached_energies.append(energy)
	main.display_active_pokemon_energies(is_opp)
	main.update_discard_pile_display(is_opp)
	await main.show_message("FIRE RECHARGE! ATTACHED FIRE ENERGY TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Fire Recharge")

# GLARING GAZE (neo1-42 Noctowl): flip — heads: look at opp hand, remove 1 trainer to deck
func power_neo1_glaring_gaze(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("GLARING GAZE BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("GLARING GAZE ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("GLARING GAZE: TAILS!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opp else main.opponent_hand
	var opp_deck = main.player_deck if is_opp else main.opponent_deck
	var trainers: Array = []
	for c in opp_hand:
		if c.metadata.get("supertype","") == "Trainer":
			trainers.append(c)
	if trainers.size() == 0:
		await main.show_message("GLARING GAZE: HEADS! BUT OPPONENT HAS NO TRAINER CARDS!")
		if main._should_bail(): return
		return
	await main.show_message("GLARING GAZE: HEADS! LOOKING AT OPPONENT'S HAND...")
	if main._should_bail(): return
	var target: card_object = null
	if is_opp:
		target = trainers[0]
	else:
		target = await main.card_ops.prompt_select_card(trainers, "GLARING GAZE: CHOOSE TRAINER", "Choose a Trainer card to shuffle into opponent's deck", "SELECT", false)
		if main._should_bail(): return
	if target == null: return
	opp_hand.erase(target)
	target.current_location = "deck"
	opp_deck.append(target)
	opp_deck.shuffle()
	main.refresh_hand_display(not is_opp)
	main.update_deck_icon(not is_opp)
	await main.show_message("GLARING GAZE! SHUFFLED " + target.metadata.get("name","").to_upper() + " INTO OPPONENT'S DECK!")
	if main._should_bail(): return
	print("POWER USED: Glaring Gaze")

# PLAYFUL PUNCH (neo1-22 Elekid): flip — heads: 20 to each pokemon in play (except self)
func power_neo1_playful_punch(pokemon: card_object) -> void:
	var is_opp = (pokemon == main.opponent_active_pokemon or pokemon in main.opponent_bench)
	if is_power_blocked_by_status(pokemon):
		if not is_opp: await main.show_message("PLAYFUL PUNCH BLOCKED BY STATUS!")
		return
	if pokemon.power_used_this_turn:
		if not is_opp: await main.show_message("PLAYFUL PUNCH ALREADY USED THIS TURN!")
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opp)
	if main._should_bail(): return
	if not coin:
		await main.show_message("PLAYFUL PUNCH: TAILS!")
		if main._should_bail(): return
		return
	var all_targets: Array = []
	if main.player_active_pokemon != null and main.player_active_pokemon != pokemon: all_targets.append({"p": main.player_active_pokemon, "opp": false})
	if main.opponent_active_pokemon != null and main.opponent_active_pokemon != pokemon: all_targets.append({"p": main.opponent_active_pokemon, "opp": true})
	for bp in main.player_bench:
		if bp != pokemon: all_targets.append({"p": bp, "opp": false})
	for bp in main.opponent_bench:
		if bp != pokemon: all_targets.append({"p": bp, "opp": true})
	for entry in all_targets:
		entry["p"].current_hp = max(0, entry["p"].current_hp - 20)
		main.display_hp_circles_above_align(entry["p"], entry["opp"])
	await main.show_message("PLAYFUL PUNCH! HEADS! 20 DAMAGE TO EACH POKEMON IN PLAY!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Playful Punch")

# ── CPU activations for neo1 powers ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
######################################################################################################################################################
##################################################### NEO2 (NEO DISCOVERY) POWERS & BODIES ##########################################################
######################################################################################################################################################

func _register_neo2_powers() -> void:
	# Active powers — player-activatable
	_power_dispatch["[Find]"]          = func(p): await power_neo2_unown_find(p)
	_power_dispatch["[Undo]"]          = func(p): await power_neo2_unown_undo(p)
	_power_dispatch["[Observe]"]       = func(p): await power_neo2_unown_observe(p)
	_power_dispatch["Gaze"]            = func(p): await power_neo2_gaze(p)
	_power_dispatch["Revive Friends"]  = func(p): await power_neo2_revive_friends(p)
	_power_dispatch["Revive Fossil"]   = func(p): await power_neo2_revive_fossil(p)

# ─── PASSIVE DAMAGE BONUSES ──────────────────────────────────────────────────

# [Anger] (Unown [A]): Hidden Power does +10 per damage counter on Unown [A] (one [A] max)
func get_unown_anger_bonus(attacker: card_object, is_opponent: bool) -> int:
	if "Unown" not in attacker.metadata.get("name",""):
		return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var all_poke: Array = []
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	var unown_a: card_object = null
	var count = 0
	for p in all_poke:
		if "Unown [A]" in p.metadata.get("name","") or "[Anger]" in str(p.metadata.get("abilities",[])):
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Anger]":
					if p.gaze_suppressed: continue
					count += 1
					if unown_a == null:
						unown_a = p
	if unown_a == null:
		return 0
	if is_power_blocked_by_status(unown_a):
		return 0
	var damage_counters = unown_a.get_damage_counters()
	return damage_counters * 10

# FROG SONG (Politoed neo2-8/27): if 4+ poliwag-line in play, Politoed's attacks do +40
func get_frog_song_bonus(attacker: card_object) -> int:
	if "Politoed" not in attacker.metadata.get("name",""):
		return 0
	if is_power_blocked_by_status(attacker): return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	if attacker.gaze_suppressed: return 0
	var names = ["Poliwag", "Poliwhirl", "Poliwrath", "Politoed"]
	var count = 0
	var all_poke: Array = []
	if main.player_active_pokemon: all_poke.append(main.player_active_pokemon)
	if main.opponent_active_pokemon: all_poke.append(main.opponent_active_pokemon)
	all_poke.append_array(main.player_bench)
	all_poke.append_array(main.opponent_bench)
	for p in all_poke:
		if p.metadata.get("name","") in names:
			count += 1
	if count > 3:
		return 40
	return 0

# UNOWN TYPE REDUCTIONS: [D]/[M]/[N] — reduce damage from Darkness/Metal/Colorless pokemon by 30
func apply_unown_type_reductions(attacker_pokemon: card_object, defending_pokemon: card_object, damage: int, modifiers: Array) -> int:
	if attacker_pokemon == null or damage <= 0:
		return damage
	if is_toxic_gas_active() or main.goop_gas_active:
		return damage
	var atk_types = attacker_pokemon.metadata.get("types", ["Colorless"])
	# Determine defender's side
	var def_is_player = (defending_pokemon == main.player_active_pokemon or defending_pokemon in main.player_bench)
	var def_bench = main.player_bench if def_is_player else main.opponent_bench
	var def_active = main.player_active_pokemon if def_is_player else main.opponent_active_pokemon
	var def_all: Array = []
	if def_active != null: def_all.append(def_active)
	def_all.append_array(def_bench)
	# [Darkness] — Unown [D]
	if "Darkness" in atk_types:
		var d_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Darkness]" and not p.gaze_suppressed:
					d_count += 1
		if d_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [D] -30")
	# [Metal] — Unown [M]
	if "Metal" in atk_types:
		var m_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Metal]" and not p.gaze_suppressed:
					m_count += 1
		if m_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [M] -30")
	# [Normal] — Unown [N]
	if "Colorless" in atk_types:
		var n_count = 0
		for p in def_all:
			for ab in p.metadata.get("abilities",[]):
				if ab.get("name","") == "[Normal]" and not p.gaze_suppressed:
					n_count += 1
		if n_count == 1:
			damage = max(0, damage - 30)
			modifiers.append("UNOWN [N] -30")
	return damage

# ─── ON-DAMAGE HOOKS ─────────────────────────────────────────────────────────

# COUNTER (Wobbuffet): if damaged and counter_active, flip — heads: deal equal damage back to attacker
func check_neo2_counter(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	if not defender.counter_active or damage <= 0 or attacker == null:
		return
	defender.counter_active = false
	if is_toxic_gas_active() or main.goop_gas_active: return
	if is_power_blocked_by_status(defender): return
	var coin = await main.flip_coin(false, is_def_opp)
	if main._should_bail(): return
	if coin:
		attacker.current_hp = max(0, attacker.current_hp - damage)
		var atk_is_opp = not is_def_opp
		main.display_hp_circles_above_align(attacker, atk_is_opp)
		main.show_floating_label("-" + str(damage) + "HP", Vector2(530 if atk_is_opp else 1030, 300), Color.ORANGE, true)
		await main.show_message("COUNTER! " + defender.metadata.get("name","").to_upper() + " DEALS " + str(damage) + " DAMAGE BACK!")
		if main._should_bail(): return
	else:
		await main.show_message("TAILS! COUNTER FAILED!")
		if main._should_bail(): return
	print("EFFECT: Counter checked — ", "hit" if coin else "miss")

# SECRETE POISON (Kakuna): if damaged with secrete_poison_active, attacker poisoned + 10 to each opp bench
func check_neo2_secrete_poison(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	if not defender.secrete_poison_active or damage <= 0 or attacker == null:
		return
	defender.secrete_poison_active = false
	if is_toxic_gas_active() or main.goop_gas_active: return
	main.card_ops.apply_status(attacker, "Poisoned", not is_def_opp)
	await main.show_message("SECRETE POISON! " + attacker.metadata.get("name","").to_upper() + " IS POISONED!")
	if main._should_bail(): return
	var opp_bench = main.player_bench if is_def_opp else main.opponent_bench
	for bp in opp_bench:
		if bp.current_hp > 0:
			main.card_ops.apply_bench_damage(bp, 10, not is_def_opp)
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("EFFECT: Secrete Poison triggered")

# ─── SPIKES (Forretress neo2-2/21): 10 damage to bench→active switch target ─
func check_spikes(new_active: card_object, is_new_active_opp: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var forretress_bench = main.opponent_bench if not is_new_active_opp else main.player_bench
	var forretress_active = main.opponent_active_pokemon if not is_new_active_opp else main.player_active_pokemon
	var forretress_side: Array = []
	if forretress_active != null: forretress_side.append(forretress_active)
	forretress_side.append_array(forretress_bench)
	for p in forretress_side:
		if "Forretress" not in p.metadata.get("name",""):
			continue
		if is_power_blocked_by_status(p):
			continue
		if p.gaze_suppressed:
			continue
		var has_spikes = false
		for ab in p.metadata.get("abilities",[]):
			if ab.get("name","") == "Spikes":
				has_spikes = true
				break
		if not has_spikes:
			continue
		if new_active.current_hp > 0:
			new_active.current_hp = max(0, new_active.current_hp - 10)
			main.display_hp_circles_above_align(new_active, is_new_active_opp)
			main.show_floating_label("-10HP", Vector2(530 if is_new_active_opp else 1030, 300), Color.WHITE, true)
			await main.show_message("SPIKES! " + p.metadata.get("name","").to_upper() + " DEALS 10 DAMAGE TO " + new_active.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
		break

# ─── ENERGY EVOLUTION (Eevee neo2-38): on energy attach, flip for matching evo
func check_energy_evolution(eevee: card_object, energy: card_object, is_opponent: bool) -> void:
	if "Eevee" not in eevee.metadata.get("name",""):
		return
	var has_ee = false
	for ab in eevee.metadata.get("abilities",[]):
		if ab.get("name","") == "Energy Evolution":
			has_ee = true
			break
	if not has_ee: return
	if is_power_blocked_by_status(eevee): return
	if is_toxic_gas_active() or main.goop_gas_active: return
	if eevee.gaze_suppressed: return
	var energy_types = main.get_energy_provided_by_card(energy)
	if energy_types.is_empty(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("ENERGY EVOLUTION: TAILS! NO EVOLUTION!")
		if main._should_bail(): return
		return
	var energy_type = energy_types[0]
	await main.show_message("ENERGY EVOLUTION! SEARCHING FOR " + energy_type.to_upper() + "-TYPE EVO...")
	if main._should_bail(): return
	var evo_filter = func(c: card_object) -> bool:
		if "evolvesFrom" not in c.metadata or c.metadata["evolvesFrom"] != "Eevee":
			return false
		var evo_types = c.metadata.get("types",[])
		return energy_type in evo_types
	var found = await main.card_ops.search_deck_to_hand(is_opponent, evo_filter, "ENERGY EVOLUTION: CHOOSE EVO OF MATCHING TYPE", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO MATCHING EVOLUTION FOUND IN DECK!")
		if main._should_bail(): return
		return
	var evo_card: card_object = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(evo_card)
	evo_card.attached_pre_evolutions.append(eevee)
	var all_energy = eevee.attached_energies.duplicate()
	for e in all_energy:
		eevee.attached_energies.erase(e)
		evo_card.attached_energies.append(e)
	evo_card.current_hp = evo_card.get_max_hp()
	evo_card.placed_on_field_this_turn = true
	if eevee.current_location == "active":
		evo_card.current_location = "active"
		if is_opponent:
			main.opponent_active_pokemon = evo_card
		else:
			main.player_active_pokemon = evo_card
	else:
		evo_card.current_location = "bench"
		var bench = main.opponent_bench if is_opponent else main.player_bench
		bench.erase(eevee)
		bench.append(evo_card)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ENERGY EVOLUTION! EEVEE EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("ENERGY EVOLUTION: Eevee evolved to ", evo_card.metadata.get("name",""))

# ─── ACTIVE POWERS ────────────────────────────────────────────────────────────

# [FIND] (Unown [F]): if F,I,N,D all on bench, search deck for a Trainer
func power_neo2_unown_find(unown_f: card_object) -> void:
	if unown_f.power_used_this_turn: return
	var bench = main.player_bench
	var names_on_bench = bench.map(func(p): return p.metadata.get("name",""))
	var has_i = names_on_bench.any(func(n): return "Unown [I]" in n)
	var has_n = names_on_bench.any(func(n): return "Unown [N]" in n)
	var has_d = names_on_bench.any(func(n): return "Unown [D]" in n)
	if not (has_i and has_n and has_d):
		await main.show_message("[FIND] REQUIRES UNOWN [F], [I], [N], AND [D] ON BENCH!")
		if main._should_bail(): return
		return
	unown_f.power_used_this_turn = true
	var found = await main.card_ops.search_deck_to_hand(false, func(c): return c.metadata.get("supertype","") == "Trainer", "[FIND]: CHOOSE A TRAINER CARD", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO TRAINER CARD FOUND IN DECK!")
		if main._should_bail(): return
		return
	await main.show_message("[FIND]! TRAINER CARD ADDED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Find] — Trainer card retrieved")

# [UNDO] (Unown [U]): if U,N,D,O all on bench, return active + attachments to hand
func power_neo2_unown_undo(unown_u: card_object) -> void:
	if unown_u.power_used_this_turn: return
	var bench = main.player_bench
	var names_on_bench = bench.map(func(p): return p.metadata.get("name",""))
	var has_n = names_on_bench.any(func(n): return "Unown [N]" in n)
	var has_d = names_on_bench.any(func(n): return "Unown [D]" in n)
	var has_o = names_on_bench.any(func(n): return "Unown [O]" in n)
	if not (has_n and has_d and has_o):
		await main.show_message("[UNDO] REQUIRES UNOWN [U], [N], [D], AND [O] ON BENCH!")
		if main._should_bail(): return
		return
	var active = main.player_active_pokemon
	if active == null:
		await main.show_message("NO ACTIVE POKEMON TO RETURN!")
		if main._should_bail(): return
		return
	unown_u.power_used_this_turn = true
	var to_return: Array = [active]
	for e in active.attached_energies.duplicate():
		to_return.append(e)
	for c in active.attached_cards.duplicate():
		to_return.append(c)
	for pre in active.attached_pre_evolutions.duplicate():
		to_return.append(pre)
	active.attached_energies.clear()
	active.attached_cards.clear()
	active.attached_pre_evolutions.clear()
	main.player_active_pokemon = null
	for card_item in to_return:
		card_item.current_location = "hand"
		card_item.placed_on_field_this_turn = false
		main.player_hand.append(card_item)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	main.refresh_hand_display(false)
	await main.show_message("[UNDO]! " + active.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Undo] — active returned to hand")

# [OBSERVE] (Unown [O]): look at top 5 of opponent's deck
func power_neo2_unown_observe(unown_o: card_object) -> void:
	if unown_o.power_used_this_turn: return
	unown_o.power_used_this_turn = true
	var deck = main.opponent_deck
	if deck.is_empty():
		await main.show_message("OPPONENT'S DECK IS EMPTY!")
		if main._should_bail(): return
		return
	var top5 = []
	for i in range(min(5, deck.size())):
		top5.append(deck[i])
	await main.show_message("[OBSERVE]! LOOKING AT TOP " + str(top5.size()) + " CARDS OF OPPONENT'S DECK...")
	if main._should_bail(): return
	var _viewed = await main.card_ops.prompt_select_card(top5, "[OBSERVE]: OPPONENT'S TOP " + str(top5.size()), "Look at these cards, then press Done", "DONE", true)
	if main._should_bail(): return
	print("POWER USED: [Observe] — viewed top 5 opponent deck")

# GAZE (Igglybuff neo2-40): choose 1 opponent bench pokemon with a power; suppress its power until EOT
func power_neo2_gaze(igglybuff: card_object) -> void:
	if igglybuff.power_used_this_turn: return
	var opp_bench = main.opponent_bench
	var valid_targets: Array = []
	for bp in opp_bench:
		for ab in bp.metadata.get("abilities",[]):
			if ab.get("type","") in ["Pokémon Power","Pokemon Power","Poké-Power","Poke-Power"]:
				valid_targets.append(bp)
				break
	if valid_targets.is_empty():
		await main.show_message("GAZE: NO OPPONENT BENCH POKEMON WITH A POWER!")
		if main._should_bail(): return
		return
	igglybuff.power_used_this_turn = true
	var target: card_object = null
	target = await main.card_ops.prompt_select_card(valid_targets, "GAZE", "Choose opponent bench pokemon to suppress", "SELECT", true)
	if main._should_bail(): return
	if target == null: return
	target.gaze_suppressed = true
	await main.show_message("GAZE! " + target.metadata.get("name","").to_upper() + "'S POWER IS SUPPRESSED THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Gaze — suppressed ", target.metadata.get("name",""))

# REVIVE FRIENDS (Kabuto neo2-56): flip — if heads, search deck for Kabuto and bench it
func power_neo2_revive_friends(kabuto: card_object) -> void:
	if kabuto.power_used_this_turn: return
	if is_power_blocked_by_status(kabuto): return
	var is_opponent = (kabuto == main.opponent_active_pokemon or kabuto in main.opponent_bench)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("REVIVE FRIENDS: BENCH IS FULL!")
		if main._should_bail(): return
		return
	kabuto.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! REVIVE FRIENDS FAILED!")
		if main._should_bail(): return
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Kabuto" in c.metadata.get("name","") and main.is_basic_pokemon(c), "REVIVE FRIENDS: CHOOSE KABUTO TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO KABUTO FOUND IN DECK!")
		if main._should_bail(): return
		return
	var new_kabuto = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(new_kabuto)
	var placed = main.card_ops.place_on_bench(new_kabuto, is_opponent)
	if placed:
		await main.show_message("REVIVE FRIENDS! KABUTO JOINED THE BENCH!")
		if main._should_bail(): return
	print("POWER USED: Revive Friends")

# REVIVE FOSSIL (Omanyte neo2-60): flip — if heads, search deck for any fossil evo, bench it as Basic
func power_neo2_revive_fossil(omanyte: card_object) -> void:
	if omanyte.power_used_this_turn: return
	if is_power_blocked_by_status(omanyte): return
	var is_opponent = (omanyte == main.opponent_active_pokemon or omanyte in main.opponent_bench)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("REVIVE FOSSIL: BENCH IS FULL!")
		if main._should_bail(): return
		return
	omanyte.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! REVIVE FOSSIL FAILED!")
		if main._should_bail(): return
		return
	var fossil_filter = func(c: card_object) -> bool:
		return "Mysterious Fossil" in c.metadata.get("evolvesFrom","") and "Stage 1" in c.metadata.get("subtypes",[])
	var found = await main.card_ops.search_deck_to_hand(is_opponent, fossil_filter, "REVIVE FOSSIL: CHOOSE FOSSIL POKEMON TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		await main.show_message("NO FOSSIL POKEMON FOUND IN DECK!")
		if main._should_bail(): return
		return
	var fossil_poke = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(fossil_poke)
	fossil_poke.placed_on_field_this_turn = true
	fossil_poke.current_location = "bench"
	fossil_poke.current_hp = fossil_poke.get_max_hp()
	bench.append(fossil_poke)
	main.display_pokemon(is_opponent)
	await main.show_message("REVIVE FOSSIL! " + fossil_poke.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
	if main._should_bail(): return
	print("POWER USED: Revive Fossil")

# ─── ON-PLAY TRIGGERS ────────────────────────────────────────────────────────

# [ENGAGE] (Unown [E] neo2-67): when played, both sides may shuffle and draw 4
func trigger_neo2_unown_engage(unown_e: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var has_engage = false
	for ab in unown_e.metadata.get("abilities",[]):
		if ab.get("name","") == "[Engage]":
			has_engage = true
			break
	if not has_engage: return
	await main.show_message("[ENGAGE]! UNOWN [E] WAS PLAYED!")
	if main._should_bail(): return
	# Opponent of the player who played it can choose to draw
	var opp_of_player = not is_opponent
	var opp_hand = main.opponent_hand if opp_of_player else main.player_hand
	var opp_deck = main.opponent_deck if opp_of_player else main.player_deck
	var should_opp_draw = false
	if opp_of_player:  # CPU would be the one choosing
		should_opp_draw = (opp_hand.size() < 5)
	else:
		# Player chooses
		await main.show_message("[ENGAGE]: OPPONENT CAN SHUFFLE HAND AND DRAW 4. OPPONENT CHOOSES...")
		if main._should_bail(): return
		should_opp_draw = (opp_hand.size() < 4)
	if should_opp_draw and opp_deck.size() > 0:
		for c in opp_hand.duplicate():
			c.current_location = "deck"
			opp_deck.append(c)
		opp_hand.clear()
		opp_deck.shuffle()
		main.update_deck_icon(opp_of_player)
		await main.card_ops.draw_n(opp_of_player, 4)
		if main._should_bail(): return
		main.refresh_hand_display(opp_of_player)
		await main.show_message("[ENGAGE]: OPPONENT SHUFFLED AND DREW 4!")
		if main._should_bail(): return
	# Player who played it always gets the option
	var player_hand = main.opponent_hand if is_opponent else main.player_hand
	var player_deck = main.opponent_deck if is_opponent else main.player_deck
	var should_draw = false
	if is_opponent:
		should_draw = (player_hand.size() < 5)
	else:
		await main.show_message("[ENGAGE]: DO YOU WANT TO SHUFFLE AND DRAW 4? (OPPONENT CHOOSES FOR YOU)")
		should_draw = (player_hand.size() < 4)
	if should_draw and player_deck.size() > 0:
		for c in player_hand.duplicate():
			c.current_location = "deck"
			player_deck.append(c)
		player_hand.clear()
		player_deck.shuffle()
		main.update_deck_icon(is_opponent)
		await main.card_ops.draw_n(is_opponent, 4)
		if main._should_bail(): return
		main.refresh_hand_display(is_opponent)
		await main.show_message("[ENGAGE]: " + ("OPPONENT" if is_opponent else "YOU") + " SHUFFLED AND DREW 4!")
		if main._should_bail(): return
	print("TRIGGER: [Engage] — bench-play power triggered")

# [INCREASE] (Unown [I] neo2-68): when played, may search deck for any Unown and bench it
func trigger_neo2_unown_increase(unown_i: card_object, is_opponent: bool) -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var has_inc = false
	for ab in unown_i.metadata.get("abilities",[]):
		if ab.get("name","") == "[Increase]":
			has_inc = true
			break
	if not has_inc: return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		return
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return "Unown" in c.metadata.get("name","") and main.is_basic_pokemon(c), "[INCREASE]: CHOOSE AN UNOWN TO BENCH", 1)
	if main._should_bail(): return
	if found.is_empty():
		return
	var new_unown = found[0]
	var hand = main.opponent_hand if is_opponent else main.player_hand
	hand.erase(new_unown)
	var placed = main.card_ops.place_on_bench(new_unown, is_opponent)
	if placed:
		await main.show_message("[INCREASE]! " + new_unown.metadata.get("name","").to_upper() + " PLACED ON BENCH!")
		if main._should_bail(): return
	print("TRIGGER: [Increase] — Unown benched")

# ─── FLAG CLEARING ────────────────────────────────────────────────────────────

func clear_neo2_flags_end_of_turn(is_opponent: bool) -> void:
	var all_poke: Array = []
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.lock_on_active = false
		p.counter_active = false
		p.pursuit_active = false
		p.secrete_poison_active = false
		p.slime_active = false
		p.gaze_suppressed = false

# ─── CPU PHASE ────────────────────────────────────────────────────────────────

func cpu_phase_neo2_powers() -> void:
	var toxic = is_toxic_gas_active()
	if toxic: return
	# Revive Friends (Kabuto): use if bench not full and Kabuto in deck
	var kabuto = _find_cpu_pokemon_with_power("Revive Friends")
	if kabuto != null and not kabuto.power_used_this_turn and not is_power_blocked_by_status(kabuto):
		if main.opponent_bench.size() < main.get_max_bench_size():
			var has_kabuto_in_deck = false
			for c in main.opponent_deck:
				if "Kabuto" in c.metadata.get("name","") and main.is_basic_pokemon(c):
					has_kabuto_in_deck = true
					break
			if has_kabuto_in_deck:
				await power_neo2_revive_friends(kabuto)
				if main._should_bail(): return
	# Revive Fossil (Omanyte): use if bench not full and fossil in deck
	var omanyte = _find_cpu_pokemon_with_power("Revive Fossil")
	if omanyte != null and not omanyte.power_used_this_turn and not is_power_blocked_by_status(omanyte):
		if main.opponent_bench.size() < main.get_max_bench_size():
			var has_fossil = false
			for c in main.opponent_deck:
				if "Mysterious Fossil" in c.metadata.get("evolvesFrom",""):
					has_fossil = true
					break
			if has_fossil:
				await power_neo2_revive_fossil(omanyte)
				if main._should_bail(): return
	# [Find] (Unown [F]): use if FIND combo on bench and CPU needs a trainer
	var find_combo = _check_unown_combo_on_cpu_bench(["[F]","[I]","[N]","[D]"])
	if find_combo:
		var unown_f = _find_cpu_pokemon_with_power("[Find]")
		if unown_f != null and not unown_f.power_used_this_turn:
			await power_neo2_unown_find(unown_f)
			if main._should_bail(): return
	# Gaze (Igglybuff): use if opponent has a powerful bench power
	var igglybuff = _find_cpu_pokemon_with_power("Gaze")
	if igglybuff != null and not igglybuff.power_used_this_turn and not is_power_blocked_by_status(igglybuff):
		var opp_bench_powers: Array = []
		for bp in main.player_bench:
			for ab in bp.metadata.get("abilities",[]):
				if ab.get("type","") in ["Pokémon Power","Pokemon Power","Poké-Power","Poke-Power"] and not ab.get("name","") in ["Spikes", "Frog Song"]:
					opp_bench_powers.append(bp)
					break
		if not opp_bench_powers.is_empty():
			igglybuff.power_used_this_turn = true
			var target = opp_bench_powers[0]
			target.gaze_suppressed = true
			await main.show_message("GAZE! OPPONENT'S " + target.metadata.get("name","").to_upper() + "'S POWER IS SUPPRESSED!")
			if main._should_bail(): return

func _check_unown_combo_on_cpu_bench(letters: Array) -> bool:
	var all_opp: Array = []
	if main.opponent_active_pokemon: all_opp.append(main.opponent_active_pokemon)
	all_opp.append_array(main.opponent_bench)
	for letter in letters:
		var found = false
		for p in all_opp:
			if letter in p.metadata.get("name",""):
				found = true
				break
		if not found: return false
	return true

func cpu_phase_neo1_powers() -> void:
	var toxic = is_toxic_gas_active()
	if toxic: return
	# Fire Recharge (Typhlosion): flip to attach Fire from discard
	var typhlosion = _find_cpu_pokemon_with_power("Fire Recharge")
	if typhlosion != null and not typhlosion.power_used_this_turn and not is_power_blocked_by_status(typhlosion):
		var fire_in_discard = false
		for c in main.opponent_discard_pile:
			if c.metadata.get("supertype","") == "Energy" and "Fire" in main.get_energy_provided_by_card(c):
				fire_in_discard = true
				break
		if fire_in_discard:
			await power_neo1_fire_recharge(typhlosion)
			if main._should_bail(): return
	# Glaring Gaze (Noctowl): use if player has trainers in hand
	var noctowl = _find_cpu_pokemon_with_power("Glaring Gaze")
	if noctowl != null and not noctowl.power_used_this_turn and not is_power_blocked_by_status(noctowl):
		var player_has_trainer = false
		for c in main.player_hand:
			if c.metadata.get("supertype","") == "Trainer":
				player_has_trainer = true
				break
		if player_has_trainer:
			await power_neo1_glaring_gaze(noctowl)
			if main._should_bail(): return
	# Downpour (Feraligatr): discard surplus water from hand to boost Riptide
	# Keeps at least 1 water in hand as a buffer; stops if Riptide already KOs the target
	var feraligtr = _find_cpu_pokemon_with_power("Downpour")
	if feraligtr != null and not is_power_blocked_by_status(feraligtr):
		var has_riptide = false
		for atk in feraligtr.metadata.get("attacks", []):
			if atk.get("name","").to_lower() == "riptide":
				has_riptide = true
				break
		if has_riptide:
			var water_in_discard = 0
			for c in main.opponent_discard_pile:
				if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
					water_in_discard += 1
			var opp_active_hp = main.player_active_pokemon.current_hp if main.player_active_pokemon != null else 999
			var discarded = 0
			while discarded < 3:
				var water_hand_count = 0
				for c in main.opponent_hand:
					if c.metadata.get("supertype","") == "Energy" and "Water" in main.get_energy_provided_by_card(c):
						water_hand_count += 1
				if water_hand_count <= 1:
					break
				if 10 + (water_in_discard + discarded) * 10 >= opp_active_hp:
					break
				await power_neo1_downpour(feraligtr)
				if main._should_bail(): return
				discarded += 1
	# Playful Punch (Elekid): use if all opponent pokemon have > 20 HP
	var elekid = _find_cpu_pokemon_with_power("Playful Punch")
	if elekid != null and not elekid.power_used_this_turn and not is_power_blocked_by_status(elekid):
		var all_opp_safe = true
		if main.player_active_pokemon != null and main.player_active_pokemon.current_hp <= 20:
			all_opp_safe = false
		if all_opp_safe:
			for bp in main.player_bench:
				if bp.current_hp <= 20:
					all_opp_safe = false
					break
		if all_opp_safe:
			await power_neo1_playful_punch(elekid)
			if main._should_bail(): return

######################################################################################################################################################
##################################################### NEO3 (NEO REVELATION) POWERS & BODIES ##########################################################
######################################################################################################################################################

func _register_neo3_powers() -> void:
	# Active powers
	_power_dispatch["Softboiled"]           = func(p): await power_neo3_softboiled(p)
	_power_dispatch["Howl"]                 = func(p): await power_neo3_howl(p)
	_power_dispatch["Electromagnetic Power"] = func(p): await power_neo3_electromagnetic_power(p)
	_power_dispatch["Energy Converter"]     = func(p): await power_neo3_energy_converter(p)
	_power_dispatch["Submerge"]             = func(p): await power_neo3_submerge(p)
	_power_dispatch["[Bear]"]               = func(p): await power_neo3_unown_bear(p)
	_power_dispatch["[Yield]"]              = func(p): await power_neo3_unown_yield(p)

# ── PASSIVE BODIES ──────────────────────────────────────────────────────────────

# CRYSTAL BODY (neo3-12 Porygon2): opponent's effects on Porygon2 are prevented (but damage still applies)
# This is queried from apply_attack_effects_on_target. Returns true if effects are blocked.
func has_crystal_body(pokemon: card_object) -> bool:
	if pokemon == null: return false
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Crystal Body":
			if not pokemon.gaze_suppressed and not is_power_blocked_by_status(pokemon):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# LEGENDARY BODY (neo3-17 Entei, neo3-22 Raikou, neo3-27 Suicune Rare): while Active, trainer effects ignored
# Called from play_trainer_card in Main_Match. Returns true if trainer should be blocked.
func check_legendary_body_blocks_trainer(is_opponent_playing_trainer: bool) -> bool:
	# The defender of the trainer effect is the opponent of the player playing it
	var target_active = main.player_active_pokemon if is_opponent_playing_trainer else main.opponent_active_pokemon
	if target_active == null: return false
	for ab in target_active.metadata.get("abilities",[]):
		if ab.get("name","") == "Legendary Body":
			if not target_active.gaze_suppressed and not is_power_blocked_by_status(target_active):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# LIGHTNING BURST (neo3-28 Flaaffy): when a Lightning Energy is attached to Flaaffy, deal 10 to each opp bench
# Called from perform_energy_attachment and CPU energy attach.
func check_lightning_burst(pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Lightning Burst":
			if not pokemon.gaze_suppressed and not is_power_blocked_by_status(pokemon):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if "Lightning" in main.get_energy_provided_by_card(energy_card):
						var opp_bench = main.player_bench if is_opponent else main.opponent_bench
						if not opp_bench.is_empty():
							for bp in opp_bench:
								main.card_ops.apply_damage_to_pokemon(bp, 10, not is_opponent)
							main.display_pokemon(not is_opponent)

# MAGMA POOL (neo3-33 Magcargo): when Magcargo retreats, both pokemon take 20 damage (no W/R)
# Called from handle_action_retreat_bench and execute_cpu_retreat after the swap completes.
func check_magma_pool(retreating: card_object, new_active: card_object, is_opponent: bool) -> void:
	for ab in retreating.metadata.get("abilities",[]):
		if ab.get("name","") == "Magma Pool":
			if not retreating.gaze_suppressed and not is_power_blocked_by_status(retreating):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					main.card_ops.apply_damage_to_pokemon(retreating, 20, is_opponent)
					main.card_ops.apply_damage_to_pokemon(new_active, 20, is_opponent)
					main.display_pokemon(is_opponent)
					return

# [KEEP] (neo3-46 Murkrow): once per turn, may prevent opponent from playing a trainer on Murkrow
# This is a passive blocking ability similar to Crystal Body but trainer-specific.
# Implemented as a check in play_trainer_card, same as Legendary Body.
func check_keep_blocks_trainer_on_murkrow(target: card_object, is_opponent_playing: bool) -> bool:
	if target == null: return false
	var target_name = target.metadata.get("name","")
	if "Murkrow" not in target_name: return false
	for ab in target.metadata.get("abilities",[]):
		if ab.get("name","") == "[Keep]":
			if not target.gaze_suppressed and not is_power_blocked_by_status(target):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					return true
	return false

# ALLERGIC POLLEN (neo3-9 Jumpluff): when Jumpluff is damaged by an attack, attacker becomes Poisoned
func check_allergic_pollen(jumpluff: card_object, attacker: card_object, is_jumpluff_opponent: bool) -> void:
	if jumpluff == null or attacker == null: return
	for ab in jumpluff.metadata.get("abilities",[]):
		if ab.get("name","") == "Allergic Pollen":
			if not jumpluff.gaze_suppressed and not is_power_blocked_by_status(jumpluff):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if not attacker.is_poisoned:
						attacker.is_poisoned = true
						attacker.poison_damage = 10
						main.update_status_icons(attacker, not is_jumpluff_opponent)

# HARD SHELL (neo3-51 Shuckle): if damage is ≤ 40, reduce it to 10
# Called from calculate_final_damage in Main_Match after all modifiers.
func apply_hard_shell(defender: card_object, damage: int, modifiers_applied: Array) -> int:
	if defender == null: return damage
	for ab in defender.metadata.get("abilities",[]):
		if ab.get("name","") == "Hard Shell":
			if not defender.gaze_suppressed and not is_power_blocked_by_status(defender):
				if not is_toxic_gas_active() and not main.goop_gas_active:
					if damage <= 40:
						modifiers_applied.append("Hard Shell (→10)")
						return 10
	return damage

# ── NEO3 FLAG CLEARING ─────────────────────────────────────────────────────────

func clear_neo3_flags_end_of_turn(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_poke: Array = []
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.triggered_poison_active = false
		p.neo3_high_speed_locked = false
		p.submerge_active = false
		# NEO4 per-turn protection flags (last until your next turn ends)
		p.neo4_prevent_high_damage = 0
		p.neo4_prevent_bench_damage = false
		p.neo4_cant_evolve_next_turn = false
		# night_eyes_used intentionally NOT cleared here (persists across turns for Perish Song)
		# legendary_body_active is metadata-based, not per-turn

# ── NEO4 FLAG CLEARING ─────────────────────────────────────────────────────────
# Clears per-turn neo4 flags for the side that just finished their own turn.
# is_opponent: true = clear opponent's pokemon, false = clear player's pokemon.
func clear_neo4_flags_end_of_turn(is_opponent: bool) -> void:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_poke: Array = []
	if active != null: all_poke.append(active)
	all_poke.append_array(bench)
	for p in all_poke:
		p.perform_damage_stored = 0

# ── TRIGGERED POISON (neo3-4 Crobat) ─────────────────────────────────────────

func check_triggered_poison(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null: return
	if pokemon.triggered_poison_active and not pokemon.is_poisoned:
		pokemon.is_poisoned = true
		pokemon.poison_damage = 10
		pokemon.triggered_poison_active = false
		main.update_status_icons(pokemon, is_opponent)
		print("TRIGGERED POISON: ", pokemon.metadata.get("name",""), " poisoned from energy attachment")

# ── TIME TRAVEL (neo3-3 Celebi) ───────────────────────────────────────────────

# Called just before a KO in check_and_handle_knockout.
# If pokemon is Celebi with Time Travel ability: flip — heads = shuffle back into deck instead of KO.
# Returns true if KO was prevented.
func check_time_travel(pokemon: card_object, is_opponent: bool) -> bool:
	if pokemon == null: return false
	var has_tt = false
	for ab in pokemon.metadata.get("abilities",[]):
		if ab.get("name","") == "Time Travel":
			has_tt = true
			break
	if not has_tt: return false
	if is_power_blocked_by_status(pokemon): return false
	if is_toxic_gas_active() or main.goop_gas_active: return false
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return false
	if not coin:
		await main.show_message("TIME TRAVEL: TAILS — " + pokemon.metadata.get("name","").to_upper() + " IS KNOCKED OUT!")
		if main._should_bail(): return false
		return false
	# Heads: shuffle Celebi + all attached cards into deck
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var all_attached: Array = []
	all_attached.append_array(pokemon.attached_energies)
	all_attached.append_array(pokemon.attached_cards)
	all_attached.append_array(pokemon.attached_pre_evolutions)
	for c in all_attached:
		c.current_location = "deck"
		own_deck.append(c)
	pokemon.attached_energies.clear()
	pokemon.attached_cards.clear()
	pokemon.attached_pre_evolutions.clear()
	pokemon.current_hp = pokemon.get_max_hp()
	pokemon.current_location = "deck"
	own_deck.append(pokemon)
	own_deck.shuffle()
	# Remove from active/bench
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active == pokemon:
		if is_opponent:
			main.opponent_active_pokemon = null
		else:
			main.player_active_pokemon = null
	else:
		var own_bench = main.opponent_bench if is_opponent else main.player_bench
		own_bench.erase(pokemon)
	main.update_deck_icon(is_opponent)
	await main.show_message("TIME TRAVEL! HEADS! " + pokemon.metadata.get("name","").to_upper() + " WAS SHUFFLED BACK INTO THE DECK!")
	if main._should_bail(): return true
	print("TIME TRAVEL: ", pokemon.metadata.get("name",""), " avoided KO and shuffled into deck")
	return true

# ── ACTIVE POWERS ─────────────────────────────────────────────────────────────

# SOFTBOILED (neo3-15/16 Chansey): heal 4 damage counters from any of your pokemon; discard 1 energy
func power_neo3_softboiled(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("SOFTBOILED: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	# Must discard 1 energy from Chansey
	if pokemon.attached_energies.is_empty():
		await main.show_message("SOFTBOILED: NO ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	var targets: Array = []
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_active != null: targets.append(own_active)
	targets.append_array(own_bench)
	var heal_targets = targets.filter(func(p): return p.current_hp < p.get_max_hp())
	if heal_targets.is_empty():
		await main.show_message("SOFTBOILED: ALL POKEMON ARE AT FULL HP!")
		if main._should_bail(): return
		return
	# Discard 1 energy from Chansey
	var e_to_discard: card_object = null
	if is_opponent:
		e_to_discard = pokemon.attached_energies[0]
	else:
		if pokemon.attached_energies.size() == 1:
			e_to_discard = pokemon.attached_energies[0]
		else:
			e_to_discard = await main.card_ops.prompt_select_card(pokemon.attached_energies.duplicate(), "SOFTBOILED!", "Choose an energy to discard from Chansey", "DISCARD", false)
			if main._should_bail(): return
			if e_to_discard == null: e_to_discard = pokemon.attached_energies[0]
	main.card_ops.discard_energy_from_pokemon(e_to_discard, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	# Choose target to heal
	var target: card_object = null
	if is_opponent:
		var best_dmg = 0
		for p in heal_targets:
			var dmg = p.get_max_hp() - p.current_hp
			if dmg > best_dmg:
				best_dmg = dmg
				target = p
	else:
		target = await main.card_ops.prompt_select_card(heal_targets, "SOFTBOILED!", "Choose a Pokemon to heal 4 damage counters (40 HP)", "HEAL", false)
		if main._should_bail(): return
		if target == null: target = heal_targets[0]
	if target != null:
		target.current_hp = min(target.get_max_hp(), target.current_hp + 40)
		main.display_hp_circles_above_align(target, is_opponent)
		pokemon.power_used_this_turn = true
		await main.show_message("SOFTBOILED! HEALED 4 DAMAGE COUNTERS FROM " + target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
	print("POWER USED: Softboiled — healed ", target.metadata.get("name","") if target != null else "none")

# HOWL (neo3-16 Chansey non-holo): +20 damage on all your attacks this turn
func power_neo3_howl(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("HOWL: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("HOWL: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	# Set a pluspower-like bonus on the attacker (use pluspower_count on the active, or screech_damage_bonus)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if own_active != null:
		own_active.screech_damage_bonus += 20
	pokemon.power_used_this_turn = true
	await main.show_message("HOWL! ALL ATTACKS DO +20 DAMAGE THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Howl — +20 attack bonus")

# ELECTROMAGNETIC POWER (neo3-29 Golbat... wait, that's neo3-28 Ampharos? checking original spec)
# Actually Flaaffy (neo3-28) has "Lightning Burst" body. Let me check:
# The original task specified: Electromagnetic Power is Ampharos (neo3-1).
# Active: Discard 1 Lightning energy to deal 20 to any opponent's pokemon (no W/R)
func power_neo3_electromagnetic_power(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("ELECTROMAGNETIC POWER: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("ELECTROMAGNETIC POWER: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("ELECTROMAGNETIC POWER: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	# Find Lightning energy on this pokemon
	var lightning_e: Array = []
	for e in pokemon.attached_energies:
		if "Lightning" in main.get_energy_provided_by_card(e):
			lightning_e.append(e)
	if lightning_e.is_empty():
		await main.show_message("ELECTROMAGNETIC POWER: NO LIGHTNING ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	# Discard 1 Lightning
	var e_to_discard = lightning_e[0]
	if not is_opponent and lightning_e.size() > 1:
		e_to_discard = await main.card_ops.prompt_select_card(lightning_e, "ELECTROMAGNETIC POWER!", "Choose a Lightning Energy to discard", "DISCARD", false)
		if main._should_bail(): return
		if e_to_discard == null: e_to_discard = lightning_e[0]
	main.card_ops.discard_energy_from_pokemon(e_to_discard, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	# Choose target (any opponent pokemon)
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var all_opp: Array = []
	if opp_active != null: all_opp.append(opp_active)
	all_opp.append_array(opp_bench)
	if all_opp.is_empty():
		await main.show_message("ELECTROMAGNETIC POWER: NO TARGETS!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		var lowest = 999
		for p in all_opp:
			if p.current_hp < lowest:
				lowest = p.current_hp
				target = p
	else:
		target = await main.card_ops.prompt_select_card(all_opp, "ELECTROMAGNETIC POWER!", "Choose an opponent's Pokemon for 20 damage (no W/R)", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = opp_active
	if target != null:
		main.card_ops.apply_damage_to_pokemon(target, 20, not is_opponent)
		main.display_hp_circles_above_align(target, not is_opponent)
		pokemon.power_used_this_turn = true
		await main.show_message("ELECTROMAGNETIC POWER! 20 DAMAGE TO " + target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		await main.check_all_knockouts()
		if main._should_bail(): return
	print("POWER USED: Electromagnetic Power — 20 to chosen target")

# ENERGY CONVERTER (neo3-12 Porygon2): once per turn, discard 3 energy from hand, attach 1 of any type to Porygon2
func power_neo3_energy_converter(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("ENERGY CONVERTER: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("ENERGY CONVERTER: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("ENERGY CONVERTER: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_hand = main.opponent_hand if is_opponent else main.player_hand
	var own_discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var energies_in_hand: Array = []
	for c in own_hand:
		if c.metadata.get("supertype","") == "Energy":
			energies_in_hand.append(c)
	if energies_in_hand.size() < 3:
		await main.show_message("ENERGY CONVERTER: NEED 3 ENERGY IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	# Discard 3 energy from hand
	var to_discard: Array = []
	if is_opponent:
		to_discard = energies_in_hand.slice(0, 3)
	else:
		to_discard = energies_in_hand.slice(0, 3)  # Simplified: first 3
	for e in to_discard:
		own_hand.erase(e)
		e.current_location = "discard"
		own_discard.append(e)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	# Search deck for any basic energy and attach to Porygon2
	var own_deck = main.opponent_deck if is_opponent else main.player_deck
	var basic_energies_in_deck: Array = []
	for c in own_deck:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basic_energies_in_deck.append(c)
	if basic_energies_in_deck.is_empty():
		await main.show_message("ENERGY CONVERTER: NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		pokemon.power_used_this_turn = true
		return
	var chosen_energy: card_object = null
	if is_opponent:
		chosen_energy = basic_energies_in_deck[0]
	else:
		chosen_energy = await main.card_ops.prompt_select_card(basic_energies_in_deck, "ENERGY CONVERTER!", "Choose a Basic Energy from your deck to attach to Porygon2", "ATTACH", false)
		if main._should_bail(): return
		if chosen_energy == null: chosen_energy = basic_energies_in_deck[0]
	own_deck.erase(chosen_energy)
	chosen_energy.current_location = "active"
	pokemon.attached_energies.append(chosen_energy)
	own_deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	pokemon.power_used_this_turn = true
	await main.show_message("ENERGY CONVERTER! DISCARDED 3 ENERGY, ATTACHED " + chosen_energy.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Energy Converter — attached ", chosen_energy.metadata.get("name",""))

# SUBMERGE (neo3-32 Lanturn): type is Water this turn (prevents effects against Water); set flag
func power_neo3_submerge(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("SUBMERGE: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_toxic_gas_active() or main.goop_gas_active:
		await main.show_message("SUBMERGE: BLOCKED BY TOXIC GAS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("SUBMERGE: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.submerge_active = true
	pokemon.temporary_type = "Water"
	pokemon.power_used_this_turn = true
	await main.show_message("SUBMERGE! " + pokemon.metadata.get("name","").to_upper() + " IS NOW A WATER TYPE — EFFECTS CAN'T BE USED ON IT THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Submerge — Lanturn becomes Water type")

# [BEAR] (neo3-? Unown [B]): once per turn, search deck for 1 Trainer card and put in hand
func power_neo3_unown_bear(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("[BEAR]: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[BEAR]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Trainer", "[BEAR]! CHOOSE A TRAINER CARD", 1)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	main.refresh_hand_display(is_opponent)
	await main.show_message("[BEAR]! TRAINER CARD RETRIEVED!")
	if main._should_bail(): return
	print("POWER USED: [Bear] — trainer retrieved from deck")

# [YIELD] (neo3-? Unown [Y]): once per turn, search deck for 1 Basic Pokemon and put in hand
func power_neo3_unown_yield(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("[YIELD]: BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[YIELD]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]), "[YIELD]! CHOOSE A BASIC POKEMON", 1)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	main.refresh_hand_display(is_opponent)
	await main.show_message("[YIELD]! BASIC POKEMON RETRIEVED!")
	if main._should_bail(): return
	print("POWER USED: [Yield] — basic pokemon retrieved from deck")

# ── CPU PHASE ─────────────────────────────────────────────────────────────────

func cpu_phase_neo3_powers() -> void:
	if is_toxic_gas_active(): return
	# Electromagnetic Power (Ampharos): use if there's a Lightning energy attached and a low-HP target
	var ampharos = _find_cpu_pokemon_with_power("Electromagnetic Power")
	if ampharos != null and not ampharos.power_used_this_turn and not is_power_blocked_by_status(ampharos):
		var has_lightning = false
		for e in ampharos.attached_energies:
			if "Lightning" in main.get_energy_provided_by_card(e):
				has_lightning = true
				break
		if has_lightning:
			var opp_active = main.player_active_pokemon
			if opp_active != null and opp_active.current_hp <= 30:
				await power_neo3_electromagnetic_power(ampharos)
				if main._should_bail(): return
	# Softboiled (Chansey): use if any pokemon has damage
	var chansey = _find_cpu_pokemon_with_power("Softboiled")
	if chansey != null and not chansey.power_used_this_turn and not is_power_blocked_by_status(chansey):
		if not chansey.attached_energies.is_empty():
			var has_damage = false
			var all_cpu = ([main.opponent_active_pokemon] if main.opponent_active_pokemon != null else []) + main.opponent_bench
			for p in all_cpu:
				if p.current_hp < p.get_max_hp():
					has_damage = true
					break
			if has_damage:
				await power_neo3_softboiled(chansey)
				if main._should_bail(): return
	# Energy Converter (Porygon2): use if deck is big enough
	var porygon2 = _find_cpu_pokemon_with_power("Energy Converter")
	if porygon2 != null and not porygon2.power_used_this_turn and not is_power_blocked_by_status(porygon2):
		var energy_in_hand = main.opponent_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy").size()
		if energy_in_hand >= 3:
			await power_neo3_energy_converter(porygon2)
			if main._should_bail(): return
	# [Bear] Unown: always search for a trainer
	var unown_bear = _find_cpu_pokemon_with_power("[Bear]")
	if unown_bear != null and not unown_bear.power_used_this_turn and not is_power_blocked_by_status(unown_bear):
		await power_neo3_unown_bear(unown_bear)
		if main._should_bail(): return
	# [Yield] Unown: search for a basic if bench not full
	var unown_yield = _find_cpu_pokemon_with_power("[Yield]")
	if unown_yield != null and not unown_yield.power_used_this_turn and not is_power_blocked_by_status(unown_yield):
		if main.opponent_bench.size() < main.get_max_bench_size():
			await power_neo3_unown_yield(unown_yield)
			if main._should_bail(): return

######################################################################################################################################################
############################################################## NEO4 (NEO DESTINY) POWERS ############################################################
######################################################################################################################################################

func _register_neo4_powers() -> void:
	# Active powers
	_power_dispatch["Spatial Distortion"] = func(p): await power_neo4_spatial_distortion(p)
	_power_dispatch["Cunning"]            = func(p): await power_neo4_cunning(p)
	_power_dispatch["Drive Off"]          = func(p): await power_neo4_drive_off(p)
	_power_dispatch["[Give]"]             = func(p): await power_neo4_give(p)
	_power_dispatch["[Want]"]             = func(p): await power_neo4_want(p)
	_power_dispatch["[Help]"]             = func(p): await power_neo4_help(p)
	_power_dispatch["[Quicken]"]          = func(p): await power_neo4_quicken(p)
	_power_dispatch["[Laugh]"]            = func(p): await power_neo4_laugh(p)
	_power_dispatch["[Search]"]           = func(p): await power_neo4_search(p)
	_power_dispatch["[Tell]"]             = func(p): await power_neo4_tell(p)
	# Stadium per-turn activatable entries
	_power_dispatch["Radio Tower"]        = func(p): await main.trainer_effects.neo4_radio_tower_activate(false)
	_power_dispatch["Energy Stadium"]     = func(p): await main.trainer_effects.neo4_energy_stadium_activate(false)

# Helper: standard once-per-turn power preamble. Returns false if the power can't be used.
func _neo4_power_ready(pokemon: card_object, label: String) -> bool:
	if is_power_blocked(pokemon):
		await main.show_message(label + ": BLOCKED!")
		return false
	if pokemon.power_used_this_turn:
		await main.show_message(label + ": ALREADY USED THIS TURN!")
		return false
	return true

# SPATIAL DISTORTION (neo4-8 Dark Porygon2): flip heads, put a Stadium from discard into play
func power_neo4_spatial_distortion(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "SPATIAL DISTORTION"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("SPATIAL DISTORTION: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var stadiums: Array = []
	for c in discard:
		if main.trainer_effects.is_stadium_trainer(c):
			stadiums.append(c)
	if stadiums.is_empty():
		await main.show_message("SPATIAL DISTORTION: NO STADIUM IN DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = stadiums[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(stadiums, "SPATIAL DISTORTION!", "Choose a Stadium from your discard to put into play", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = stadiums[0]
	discard.erase(chosen)
	await main.trainer_effects.resolve_stadium_trainer(chosen, is_opponent)
	if main._should_bail(): return
	await main.show_message("SPATIAL DISTORTION! HEADS! " + chosen.metadata.get("name","").to_upper() + " IS IN PLAY!")
	if main._should_bail(): return
	print("POWER USED: Spatial Distortion")

# CUNNING (neo4-20 Dark Slowking): flip heads, look at top of opp deck; may shuffle opp deck
func power_neo4_cunning(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "CUNNING"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("CUNNING: TAILS!")
		if main._should_bail(): return
		return
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_deck.is_empty():
		await main.show_message("CUNNING: OPPONENT'S DECK IS EMPTY!")
		if main._should_bail(): return
		return
	await main.show_message("CUNNING! TOP OF OPPONENT'S DECK: " + opp_deck[0].metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	if not is_opponent:
		opp_deck.shuffle()
		main.update_deck_icon(not is_opponent)
		await main.show_message("CUNNING! OPPONENT'S DECK WAS SHUFFLED!")
	if main._should_bail(): return
	print("POWER USED: Cunning")

# DRIVE OFF (neo4-12 Light Arcanine): while Active, opp chooses a benched and switches with Defending
func power_neo4_drive_off(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if pokemon != own_active:
		await main.show_message("DRIVE OFF: ONLY WORKS WHILE ACTIVE!")
		if main._should_bail(): return
		return
	if not await _neo4_power_ready(pokemon, "DRIVE OFF"): return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.show_message("DRIVE OFF: OPPONENT HAS NO BENCH!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	await main.attack_effects.apply_force_switch({"chooser": "defender"}, is_opponent)
	if main._should_bail(): return
	await main.show_message("DRIVE OFF! OPPONENT SWITCHED THEIR ACTIVE POKEMON!")
	if main._should_bail(): return
	print("POWER USED: Drive Off")

# [GIVE] (neo4-27 Unown [G]): flip heads, search deck for a basic Energy and attach to 1 of your Pokemon
func power_neo4_give(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[GIVE]"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("[GIVE]: TAILS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var basic_e: card_object = null
	for c in deck:
		if c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes",[]):
			basic_e = c
			break
	if basic_e == null:
		await main.show_message("[GIVE]: NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		return
	var targets = main.attack_effects._neo4_opp_targets(not is_opponent)  # own side
	if targets.is_empty():
		return
	var target: card_object = targets[0]
	if not is_opponent:
		target = await main.card_ops.prompt_select_card(targets, "[GIVE]!", "Choose a Pokemon to attach a basic Energy to", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = targets[0]
	deck.erase(basic_e)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	basic_e.current_location = "active" if target == own_active else "bench"
	target.attached_energies.append(basic_e)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("[GIVE]! HEADS! ENERGY ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Give]")

# [WANT] (neo4-29 Unown [W]): flip heads, put a Trainer from discard into hand
func power_neo4_want(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[WANT]"): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	pokemon.power_used_this_turn = true
	if not coin:
		await main.show_message("[WANT]: TAILS!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var trainers: Array = []
	for c in discard:
		if c.metadata.get("supertype","") == "Trainer":
			trainers.append(c)
	if trainers.is_empty():
		await main.show_message("[WANT]: NO TRAINER IN DISCARD!")
		if main._should_bail(): return
		return
	var chosen: card_object = trainers[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(trainers, "[WANT]!", "Choose a Trainer from your discard", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = trainers[0]
	discard.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	main.update_discard_pile_display(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("[WANT]! HEADS! " + chosen.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: [Want]")

# [HELP] (neo4-28 Unown [H]): shuffle hand into deck, draw a new hand of same size
func power_neo4_help(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if not await _neo4_power_ready(pokemon, "[HELP]"): return
	pokemon.power_used_this_turn = true
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var n = hand.size()
	for c in hand.duplicate():
		c.current_location = "deck"
		deck.append(c)
	hand.clear()
	deck.shuffle()
	await main.card_ops.draw_n(is_opponent, n)
	if main._should_bail(): return
	main.update_deck_icon(is_opponent)
	main.refresh_hand_display(is_opponent)
	await main.show_message("[HELP]! SHUFFLED HAND AND DREW " + str(n) + " NEW CARDS!")
	if main._should_bail(): return
	print("POWER USED: [Help]")

# [QUICKEN] (neo4-59 Unown [Q]): flip heads, prevent all effects to your Unown next turn (invincible)
func power_neo4_quicken(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	# usable even if statused — only check toxic gas / disable
	if is_toxic_gas_active() or main.goop_gas_active or pokemon.power_disabled_until_end_of_next_turn:
		await main.show_message("[QUICKEN]: BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[QUICKEN]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[QUICKEN]: TAILS!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if own_active != null: all_own.append(own_active)
	all_own.append_array(own_bench)
	for p in all_own:
		if "Unown" in p.metadata.get("name",""):
			p.is_invincible = true
			main.update_status_icons(p, is_opponent)
	await main.show_message("[QUICKEN]! HEADS! YOUR UNOWN ARE PROTECTED NEXT TURN!")
	if main._should_bail(): return
	print("POWER USED: [Quicken]")

# [LAUGH] (neo4-86 Unown [L]): flip heads, each player shuffles their deck
func power_neo4_laugh(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_toxic_gas_active() or main.goop_gas_active or pokemon.power_disabled_until_end_of_next_turn:
		await main.show_message("[LAUGH]: BLOCKED!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("[LAUGH]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[LAUGH]: TAILS!")
		if main._should_bail(): return
		return
	main.player_deck.shuffle()
	main.opponent_deck.shuffle()
	main.update_deck_icon(false)
	main.update_deck_icon(true)
	await main.show_message("[LAUGH]! HEADS! BOTH DECKS SHUFFLED!")
	if main._should_bail(): return
	print("POWER USED: [Laugh]")

# [SEARCH] (neo4-87 Unown [S]): look at 1 of your Prize cards (flavor)
func power_neo4_search(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if pokemon.power_used_this_turn:
		await main.show_message("[SEARCH]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var prizes = main.opponent_prize_cards if is_opponent else main.player_prize_cards
	if prizes.is_empty():
		await main.show_message("[SEARCH]: NO PRIZE CARDS!")
		if main._should_bail(): return
		return
	await main.show_message("[SEARCH]! YOU PEEKED AT A PRIZE CARD: " + prizes[0].metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: [Search]")

# [TELL] (neo4-88 Unown [T]): flip heads, look at opp hand and show yours (flavor)
func power_neo4_tell(pokemon: card_object) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if pokemon.power_used_this_turn:
		await main.show_message("[TELL]: ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[TELL]: TAILS!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	await main.show_message("[TELL]! HEADS! OPPONENT HAS " + str(opp_hand.size()) + " CARDS IN HAND!")
	if main._should_bail(): return
	print("POWER USED: [Tell]")

# ── NEO4 PLAY-FROM-HAND TRIGGERS ──────────────────────────────────────────────

# SURPRISE BITE (neo4-2 Dark Crobat): when played from hand, 20 to a chosen opp Pokemon (no W/R)
func trigger_neo4_surprise_bite(crobat: card_object, is_opponent: bool) -> void:
	if is_power_blocked(crobat):
		return
	var targets = main.attack_effects._neo4_opp_targets(is_opponent)
	if targets.is_empty():
		return
	var target: card_object = targets[0]
	if not is_opponent:
		target = await main.card_ops.prompt_select_card(targets, "SURPRISE BITE!", "Choose an opponent's Pokemon for 20 damage (no W/R)", "SELECT", false)
		if main._should_bail(): return
		if target == null: target = targets[0]
	else:
		var lowest = 999
		for t in targets:
			if t.current_hp < lowest:
				lowest = t.current_hp
				target = t
	main.card_ops.apply_bench_damage(target, 20, not is_opponent)
	main.display_pokemon(not is_opponent)
	await main.show_message("SURPRISE BITE! 20 DAMAGE TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER: Surprise Bite")

# GIFT (neo4-15 Light Togetic): when played, each player may search deck for a Pokemon Tool to hand
func trigger_neo4_gift(togetic: card_object, is_opponent: bool) -> void:
	if is_power_blocked(togetic):
		return
	# Opponent searches first (auto)
	_neo4_search_tool_to_hand(not is_opponent, true)
	# You search
	await _neo4_search_tool_to_hand(is_opponent, is_opponent)
	if main._should_bail(): return
	await main.show_message("GIFT! EACH PLAYER MAY HAVE SEARCHED FOR A POKEMON TOOL!")
	if main._should_bail(): return
	print("POWER: Gift")

func _neo4_search_tool_to_hand(side_is_opponent: bool, auto: bool) -> void:
	var deck = main.opponent_deck if side_is_opponent else main.player_deck
	var hand = main.opponent_hand if side_is_opponent else main.player_hand
	var tools: Array = []
	for c in deck:
		if c.metadata.get("supertype","") == "Trainer" and "Pokémon Tool" in c.metadata.get("subtypes",[]):
			tools.append(c)
	if tools.is_empty():
		return
	var chosen: card_object = tools[0]
	if not auto:
		chosen = await main.card_ops.prompt_select_card(tools, "GIFT!", "Choose a Pokemon Tool from your deck", "SELECT", false)
		if main._should_bail(): return
		if chosen == null:
			return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.update_deck_icon(side_is_opponent)
	main.refresh_hand_display(side_is_opponent)

# TAG TEAM (neo4-25 Light Machamp): when played on bench, heal Active 30 and switch Machamp to Active
func trigger_neo4_tag_team(machamp: card_object, is_opponent: bool) -> void:
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if machamp not in own_bench:
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != null:
		var heal = min(30, active.get_max_hp() - active.current_hp)
		active.current_hp += heal
		main.display_hp_circles_above_align(active, is_opponent)
		active.current_location = "bench"
		own_bench.append(active)
	own_bench.erase(machamp)
	machamp.current_location = "active"
	if is_opponent:
		main.opponent_active_pokemon = machamp
	else:
		main.player_active_pokemon = machamp
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("TAG TEAM! " + machamp.metadata.get("name","").to_upper() + " SWITCHED IN, ACTIVE HEALED!")
	if main._should_bail(): return
	print("POWER: Tag Team")

# [VANISH] (neo4-89 Unown [V]): when played from hand, flip heads return another Unown to hand (discard attachments)
func trigger_neo4_vanish(unown_v: card_object, is_opponent: bool) -> void:
	if is_power_blocked(unown_v):
		return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[VANISH]: TAILS!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var unowns: Array = []
	if own_active != null and own_active != unown_v and "Unown" in own_active.metadata.get("name",""):
		unowns.append(own_active)
	for bp in own_bench:
		if bp != unown_v and "Unown" in bp.metadata.get("name",""):
			unowns.append(bp)
	if unowns.is_empty():
		await main.show_message("[VANISH]: NO OTHER UNOWN TO RETURN!")
		if main._should_bail(): return
		return
	var chosen: card_object = unowns[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(unowns, "[VANISH]!", "Choose an Unown to return to your hand", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = unowns[0]
	# Discard attachments, return the Unown to hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	for c in chosen.attached_energies + chosen.attached_cards + chosen.attached_pre_evolutions:
		c.current_location = "discard"
		discard.append(c)
	chosen.attached_energies.clear()
	chosen.attached_cards.clear()
	chosen.attached_pre_evolutions.clear()
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if own_active == chosen:
		if is_opponent: main.opponent_active_pokemon = null
		else: main.player_active_pokemon = null
	else:
		own_bench.erase(chosen)
	chosen.current_hp = chosen.get_max_hp()
	chosen.current_location = "hand"
	hand.append(chosen)
	main.display_pokemon(is_opponent)
	main.refresh_hand_display(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("[VANISH]! HEADS! " + chosen.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER: [Vanish]")

# ── NEO4 PASSIVE HOOKS ────────────────────────────────────────────────────────

# CONDUCTIVITY (neo4-1 Dark Ampharos): when opponent attaches Energy to a Pokemon, 10 to that Pokemon (no W/R)
# Called from energy-attachment sites. `target` received energy; `target_is_opponent` = target's side.
func check_neo4_conductivity(target: card_object, target_is_opponent: bool) -> void:
	if target == null: return
	# Dark Ampharos belongs to the side opposing the attacher (= opposing the target's owner)
	var amp_active = main.player_active_pokemon if target_is_opponent else main.opponent_active_pokemon
	var amp_bench = main.player_bench if target_is_opponent else main.opponent_bench
	var amphs: Array = []
	if amp_active != null and amp_active.has_ability("Conductivity"): amphs.append(amp_active)
	for bp in amp_bench:
		if bp.has_ability("Conductivity"): amphs.append(bp)
	if amphs.size() != 1:
		return  # stops working with more than 1 Dark Ampharos
	var amp = amphs[0]
	if is_power_blocked_by_status(amp) or is_toxic_gas_active() or main.goop_gas_active:
		return
	main.card_ops.apply_bench_damage(target, 10, target_is_opponent)
	main.display_pokemon(target_is_opponent)
	print("CONDUCTIVITY: 10 damage to ", target.metadata.get("name",""))

# HOT PLATE (neo4-18 Dark Magcargo): when a Basic/Baby is benched from hand, active Magcargo deals 10 to it
func check_neo4_hot_plate(benched: card_object, benched_is_opponent: bool) -> void:
	if benched == null: return
	for side_opp in [false, true]:
		var active = main.opponent_active_pokemon if side_opp else main.player_active_pokemon
		if active != null and active.has_ability("Hot Plate"):
			if not is_power_blocked_by_status(active) and not is_toxic_gas_active() and not main.goop_gas_active:
				main.card_ops.apply_bench_damage(benched, 10, benched_is_opponent)
				main.display_pokemon(benched_is_opponent)
				print("HOT PLATE: 10 damage to benched ", benched.metadata.get("name",""))
				return

# FLUFFY WOOL (neo4-26 Light Piloswine): if Active Piloswine damaged by attack, flip heads attacker Asleep
func check_neo4_fluffy_wool(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if defender == null or attacker == null: return
	if not defender.has_ability("Fluffy Wool"): return
	var own_active = main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon
	if defender != own_active: return
	if defender.is_status_blocked(): return
	var coin = await main.flip_coin(false, is_def_opp)
	if main._should_bail(): return
	if coin:
		main.card_ops.apply_status(attacker, "Asleep", not is_def_opp)
		await main.show_message("FLUFFY WOOL! " + attacker.metadata.get("name","").to_upper() + " FELL ASLEEP!")
		if main._should_bail(): return

# REFLECT SHIELD / COUNTERATTACK CLAWS: if Active was damaged, flip → 20/2-counters to attacker
func check_neo4_counters(defender: card_object, attacker: card_object, is_def_opp: bool) -> void:
	if defender == null or attacker == null: return
	# Reflect Shield (Shining Mewtwo)
	if defender.neo4_counter_flip_20:
		defender.neo4_counter_flip_20 = false
		var coin = await main.flip_coin(false, is_def_opp)
		if main._should_bail(): return
		if coin:
			main.card_ops.apply_bench_damage(attacker, 20, not is_def_opp)
			main.display_pokemon(not is_def_opp)
			await main.show_message("REFLECT SHIELD! 20 DAMAGE TO " + attacker.metadata.get("name","").to_upper() + "!")
			if main._should_bail(): return
	# Counterattack Claws (neo4-97 Tool)
	var has_claws = false
	for ac in defender.attached_cards:
		if ac.uid.to_lower() == "neo4-97":
			has_claws = true
			break
	if has_claws:
		var own_active = main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon
		if defender == own_active:
			var coin2 = await main.flip_coin(false, is_def_opp)
			if main._should_bail(): return
			if coin2:
				main.card_ops.apply_bench_damage(attacker, 20, not is_def_opp)
				main.display_pokemon(not is_def_opp)
				await main.show_message("COUNTERATTACK CLAWS! 20 DAMAGE TO " + attacker.metadata.get("name","").to_upper() + "!")
			# Discard the claws
			for ac in defender.attached_cards.duplicate():
				if ac.uid.to_lower() == "neo4-97":
					defender.attached_cards.erase(ac)
					var discard = main.opponent_discard_pile if is_def_opp else main.player_discard_pile
					ac.current_location = "discard"
					discard.append(ac)
			main.trainer_effects.display_attached_trainer_cards(is_def_opp)
			main.update_discard_pile_display(is_def_opp)
			if main._should_bail(): return

# SCARE (neo4-5 Dark Feraligatr): while Active and not A/C/P, opponent's Baby Pokémon can't attack
# and their Pokémon Powers stop working. victim_is_opponent = the side being suppressed.
func is_scare_active(victim_is_opponent: bool) -> bool:
	var opp_active = main.player_active_pokemon if victim_is_opponent else main.opponent_active_pokemon
	if opp_active == null: return false
	if not opp_active.has_ability("Scare"): return false
	if is_power_blocked_by_status(opp_active) or is_toxic_gas_active() or main.goop_gas_active: return false
	return true

# DEEP SLEEP (neo4-6 Dark Gengar): while any Dark Gengar is in play and not A/C/P,
# sleeping Pokémon flip 2 coins — must get BOTH heads to wake up (either tails = still asleep).
func is_deep_sleep_active() -> bool:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		var bench = main.opponent_bench if side else main.player_bench
		if active != null and active.has_ability("Deep Sleep") and not is_power_blocked_by_status(active) and not is_toxic_gas_active() and not main.goop_gas_active:
			return true
		for bp in bench:
			if bp.has_ability("Deep Sleep") and not is_power_blocked_by_status(bp) and not is_toxic_gas_active() and not main.goop_gas_active:
				return true
	return false

# MIRACULOUS WIND (neo4-14 Light Dragonite): while Active and not A/C/P, all Special Energy
# provides only Colorless and their passive effects (Darkness bonus, Metal reduction) are suppressed.
func is_miraculous_wind_active() -> bool:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active != null and active.has_ability("Miraculous Wind") and not is_power_blocked_by_status(active) and not is_toxic_gas_active() and not main.goop_gas_active:
			return true
	return false

# [CHASE] (neo4-57 Unown [C]): when opponent retreats, flip — heads puts 1 damage counter (with W/R)
# retreating_is_opponent: true if the CPU/opponent is retreating
func check_neo4_chase(retreating_pokemon: card_object, retreating_is_opponent: bool) -> void:
	if retreating_pokemon == null: return
	var chase_active = main.player_active_pokemon if retreating_is_opponent else main.opponent_active_pokemon
	if chase_active == null: return
	if not chase_active.has_ability("[Chase]"): return
	if is_power_blocked_by_status(chase_active) or is_toxic_gas_active() or main.goop_gas_active: return
	var coin = await main.flip_coin(false, not retreating_is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("[CHASE]! TAILS — NO DAMAGE.")
		if main._should_bail(): return
		return
	# Apply 10 damage with Weakness and Resistance (Unown [C] is Psychic)
	var attacker_types = ["Psychic"]
	var result = main.calculate_final_damage(10, attacker_types, retreating_pokemon, chase_active)
	retreating_pokemon.current_hp = max(0, retreating_pokemon.current_hp - result["damage"])
	main.display_hp_circles_above_align(retreating_pokemon, retreating_is_opponent)
	await main.show_message("[CHASE]! HEADS — " + retreating_pokemon.metadata.get("name","").to_upper() + " TAKES " + str(result["damage"]) + " DAMAGE!")
	if main._should_bail(): return
	print("[Chase]: ", result["damage"], " damage to ", retreating_pokemon.metadata.get("name",""))

# [PERFORM] (neo4-58 Unown [P]): if Unown [P] was damaged while Active last turn, Hidden Power
# does that much more damage. Works even if Confused.
func get_perform_bonus(attacker: card_object, is_opponent: bool) -> int:
	if attacker == null: return 0
	if "Unown [P]" not in attacker.metadata.get("name", ""): return 0
	if not attacker.has_ability("[Perform]"): return 0
	# [Perform] works even if Confused but still blocked by Asleep/Paralyzed
	var sc = attacker.special_condition
	if sc == "Asleep" or sc == "Paralyzed": return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	return attacker.perform_damage_stored

# [XXXXX] (neo4-30 Unown [X]): when any of your Unown uses Hidden Power, flip until tails,
# add 10 per heads. Only 1 Unown [X] can apply per turn.
func get_xxxxx_bonus(attacker: card_object, is_opponent: bool) -> int:
	if attacker == null: return 0
	if "Unown" not in attacker.metadata.get("name", ""): return 0
	if main.xxxxx_used_this_turn: return 0
	# Check if any Unown [X] is on the attacker's side, not A/C/P
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var has_x: bool = false
	if own_active != null and own_active.has_ability("[XXXXX]") and not is_power_blocked_by_status(own_active):
		has_x = true
	if not has_x:
		for bp in own_bench:
			if bp.has_ability("[XXXXX]") and not is_power_blocked_by_status(bp):
				has_x = true
				break
	if not has_x: return 0
	return -1  # sentinel: caller must flip until tails

# CPU activation of neo4 stadium effects (called from cpu_phase_activate_powers)
func cpu_phase_neo4_powers() -> void:
	if main.trainer_effects.neo4_lucky_stadium_active():
		await main.trainer_effects.neo4_lucky_stadium_activate(true)
		if main._should_bail(): return
	if main.trainer_effects.neo4_energy_stadium_active():
		await main.trainer_effects.neo4_energy_stadium_activate(true)
		if main._should_bail(): return
	if main.trainer_effects.neo4_radio_tower_active():
		await main.trainer_effects.neo4_radio_tower_activate(true)
		if main._should_bail(): return

######################################################################################################################################################
######################################################## NP (NINTENDO PROMOS) POWERS AND BODIES #######################################################
######################################################################################################################################################

func _register_np_powers() -> void:
	_power_dispatch["Magnetic Call"] = func(p): await power_magnetic_call(p)

# MAGNETIC CALL (np-22 Beldum): flip; heads → search deck for Metal Basic Pokémon → Bench
func power_magnetic_call(beldum: card_object) -> void:
	if is_power_blocked_by_status(beldum):
		await main.show_message("MAGNETIC CALL IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if beldum.power_used_this_turn:
		await main.show_message("MAGNETIC CALL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var is_opponent = (beldum == main.opponent_active_pokemon or beldum in main.opponent_bench)
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if bench.size() >= 5:
		await main.show_message("BENCH IS FULL! CANNOT USE MAGNETIC CALL!")
		if main._should_bail(): return
		return
	beldum.power_used_this_turn = true
	await main.show_message("MAGNETIC CALL!")
	if main._should_bail(): return
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! MAGNETIC CALL FAILS!")
		if main._should_bail(): return
		return
	var metal_basics: Array = []
	for c in deck:
		var subtypes = c.metadata.get("subtypes", [])
		var types = c.metadata.get("types", [])
		if "Basic" in subtypes and "Metal" in types:
			metal_basics.append(c)
	if metal_basics.is_empty():
		await main.show_message("HEADS! BUT NO METAL BASIC POKÉMON IN DECK!")
		if main._should_bail(): return
		main.card_ops.shuffle_deck(is_opponent)
		return
	var chosen: card_object
	if is_opponent:
		chosen = metal_basics[0]
	else:
		chosen = await main.card_ops.prompt_select_card(metal_basics, "MAGNETIC CALL", "Choose a Metal Basic Pokémon to bench", "BENCH", false)
		if main._should_bail(): return
	if chosen == null:
		main.card_ops.shuffle_deck(is_opponent)
		return
	deck.erase(chosen)
	chosen.current_location = "bench"
	bench.append(chosen)
	main.card_ops.shuffle_deck(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEADS! " + chosen.metadata.get("name", "").to_upper() + " PLACED ON BENCH!")
	if main._should_bail(): return
	print("POWER: Magnetic Call — ", chosen.metadata.get("name", ""), " benched")

# NP FRENZY (np-37/38/39 Kyogre/Groudon/Rayquaza ex): +40 damage if specific opponent legendary in play
func get_np_frenzy_bonus(attacker: card_object, is_opponent: bool) -> int:
	if attacker == null: return 0
	if is_toxic_gas_active() or main.goop_gas_active: return 0
	var attacker_name = attacker.metadata.get("name", "").to_lower()
	var triggers: Array = []
	if "kyogre" in attacker_name:
		for ab in attacker.metadata.get("abilities", []):
			if ab.get("name", "") == "Frenzy" and ab.get("type", "") in ["Poké-Body", "Poke-Body"]:
				triggers = ["Groudon", "Groudon ex", "Rayquaza", "Rayquaza ex"]
				break
	elif "groudon" in attacker_name:
		for ab in attacker.metadata.get("abilities", []):
			if ab.get("name", "") == "Frenzy" and ab.get("type", "") in ["Poké-Body", "Poke-Body"]:
				triggers = ["Kyogre", "Kyogre ex", "Rayquaza", "Rayquaza ex"]
				break
	elif "rayquaza" in attacker_name:
		for ab in attacker.metadata.get("abilities", []):
			if ab.get("name", "") == "Frenzy" and ab.get("type", "") in ["Poké-Body", "Poke-Body"]:
				triggers = ["Kyogre", "Kyogre ex", "Groudon", "Groudon ex"]
				break
	if triggers.is_empty(): return 0
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var all_opp: Array = []
	if opp_active != null: all_opp.append(opp_active)
	all_opp.append_array(opp_bench)
	for p in all_opp:
		var pname = p.metadata.get("name", "")
		for t in triggers:
			if t == pname:
				print("NP FRENZY: +40 (", attacker.metadata.get("name",""), " vs ", pname, ")")
				return 40
	return 0

# PURE BODY (np-30/basep-53 Suicune): when Water Energy attached from hand, discard one energy from Suicune.
# Returns true if attachment should be blocked (no energies to discard).
func check_pure_body_block(energy_card: card_object, target_pokemon: card_object) -> bool:
	if target_pokemon == null: return false
	if is_power_blocked(target_pokemon): return false
	for ab in target_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") != "Pure Body": continue
		# Guarded type is the holder's own base type (Suicune=Water, Entei=Fire, etc.)
		var guarded_types = target_pokemon.metadata.get("types", [])
		var energy_name = energy_card.metadata.get("name", "")
		var provided = main.special_energy_effects.get_energy_types_provided(energy_name)
		if provided.is_empty():
			provided = energy_card.metadata.get("types", [])
		for t in guarded_types:
			if t in provided:
				return target_pokemon.attached_energies.is_empty()
	return false

# Trigger Pure Body discard after a matching-type Energy is attached. Call after energy is appended.
func check_pure_body_discard(energy_card: card_object, target_pokemon: card_object, is_opponent: bool) -> void:
	if target_pokemon == null: return
	if is_power_blocked(target_pokemon): return
	for ab in target_pokemon.metadata.get("abilities", []):
		if ab.get("name", "") != "Pure Body": continue
		var guarded_types = target_pokemon.metadata.get("types", [])
		var energy_name = energy_card.metadata.get("name", "")
		var provided = main.special_energy_effects.get_energy_types_provided(energy_name)
		if provided.is_empty():
			provided = energy_card.metadata.get("types", [])
		var matched = false
		for t in guarded_types:
			if t in provided: matched = true
		if not matched: return
		if target_pokemon.attached_energies.is_empty(): return
		var to_discard: card_object = null
		if is_opponent:
			to_discard = target_pokemon.attached_energies[0]
		else:
			if target_pokemon.attached_energies.size() == 1:
				to_discard = target_pokemon.attached_energies[0]
			else:
				to_discard = await main.card_ops.prompt_select_card(target_pokemon.attached_energies.duplicate(), "PURE BODY", "Choose an energy to discard from " + target_pokemon.metadata.get("name",""), "DISCARD", false)
				if main._should_bail(): return
				if to_discard == null:
					to_discard = target_pokemon.attached_energies[0]
		main.card_ops.discard_energy_from_pokemon(to_discard, is_opponent)
		main.display_active_pokemon_energies(is_opponent)
		await main.show_message("PURE BODY! AN ENERGY WAS DISCARDED FROM " + target_pokemon.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		return

# RAIN DISH / BURNING AURA: passive body effects between turns
func apply_np_between_turn_bodies() -> void:
	# EX2 Primal Lock (Aerodactyl ex): strip any Pokemon Tools from the opponent's Pokemon.
	await apply_ex2_primal_lock_removal()
	if main._should_bail(): return
	# RAIN DISH (np-20 Ludicolo): remove 1 damage counter from Ludicolo between turns
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		var bench_arr = main.opponent_bench if side else main.player_bench
		var all_poke: Array = []
		if active != null: all_poke.append(active)
		all_poke.append_array(bench_arr)
		for p in all_poke:
			if p.current_hp <= 0: continue
			if is_toxic_gas_active() or main.goop_gas_active: continue
			if is_power_blocked_by_status(p): continue
			for ab in p.metadata.get("abilities", []):
				if ab.get("name", "") in ["Rain Dish", "Spongy Stone"]:
					var max_hp = p.get_max_hp()
					if p.current_hp < max_hp:
						p.current_hp = min(max_hp, p.current_hp + 10)
						main.display_hp_circles_above_align(p, side)
						await main.show_message(ab.get("name","").to_upper() + "! " + p.metadata.get("name","").to_upper() + " RECOVERED 10 HP!")
						if main._should_bail(): return

	# EX5 HEALING STONE (Regirock ex ex5-98): at any time between turns, remove 1 damage counter from
	# Regirock ex (wherever it is in play).
	for side in [false, true]:
		var active_h = main.opponent_active_pokemon if side else main.player_active_pokemon
		var bench_h = main.opponent_bench if side else main.player_bench
		var all_h: Array = []
		if active_h != null: all_h.append(active_h)
		all_h.append_array(bench_h)
		for p in all_h:
			if p.current_hp <= 0: continue
			if is_toxic_gas_active() or main.goop_gas_active: continue
			if is_power_blocked_by_status(p): continue
			if p.has_ability("Healing Stone"):
				var max_hp = p.get_max_hp()
				if p.current_hp < max_hp:
					p.current_hp = min(max_hp, p.current_hp + 10)
					main.display_hp_circles_above_align(p, side)
					await main.show_message("HEALING STONE! " + p.metadata.get("name","").to_upper() + " REMOVED 1 DAMAGE COUNTER!")
					if main._should_bail(): return

	# EX5 DESERT RUINS (ex5-88 Stadium): between turns each player puts 1 damage counter on their own
	# Pokemon-ex whose maximum HP is at least 100.
	if main.is_stadium_in_play(StadiumIds.DESERT_RUINS):
		for side in [false, true]:
			for p in main.card_ops.get_all_pokemon_in_play(side):
				if p.current_hp <= 0: continue
				if main.is_ex_pokemon(p) and p.get_max_hp() >= 100:
					p.current_hp = max(0, p.current_hp - 10)
					main.display_hp_circles_above_align(p, side)
			await main.check_all_knockouts()
			if main._should_bail(): return
		await main.show_message("DESERT RUINS! DAMAGE COUNTERS PLACED ON POKEMON-EX!")
		if main._should_bail(): return

	# BURNING AURA (np-34 Typhlosion): while Active, put 1 damage counter on EACH Active between turns
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active == null: continue
		if is_toxic_gas_active() or main.goop_gas_active: continue
		if is_power_blocked_by_status(active): continue
		for ab in active.metadata.get("abilities", []):
			if ab.get("name", "") == "Burning Aura":
				var opp_active = main.player_active_pokemon if side else main.opponent_active_pokemon
				active.current_hp = max(0, active.current_hp - 10)
				main.display_hp_circles_above_align(active, side)
				if opp_active != null:
					opp_active.current_hp = max(0, opp_active.current_hp - 10)
					main.display_hp_circles_above_align(opp_active, not side)
				await main.show_message("BURNING AURA! BOTH ACTIVE POKÉMON TAKE 10 DAMAGE!")
				if main._should_bail(): return
				await main.check_all_knockouts()
				if main._should_bail(): return
				break

# SYNCHRONIZED LIFT (np-31/32/33 Moltres/Articuno/Zapdos ex): free retreat if specific partners in play
func check_synchronized_lift(pokemon: card_object, is_opponent: bool) -> bool:
	if pokemon == null: return false
	if is_toxic_gas_active() or main.goop_gas_active: return false
	if is_power_blocked_by_status(pokemon): return false
	var ab_text = ""
	for ab in pokemon.metadata.get("abilities", []):
		if ab.get("name", "") == "Synchronized Lift":
			ab_text = ab.get("text", "").to_lower()
			break
	if ab_text == "": return false
	var bench_arr = main.opponent_bench if is_opponent else main.player_bench
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var all_own: Array = []
	if own_active != null: all_own.append(own_active)
	all_own.append_array(bench_arr)
	var has_articuno = false
	var has_zapdos = false
	var has_moltres = false
	for p in all_own:
		var pname = p.metadata.get("name", "").to_lower()
		if "articuno ex" in pname: has_articuno = true
		if "zapdos ex" in pname: has_zapdos = true
		if "moltres ex" in pname: has_moltres = true
	if "articuno ex" in ab_text and not has_articuno: return false
	if "zapdos ex" in ab_text and not has_zapdos: return false
	if "moltres ex" in ab_text and not has_moltres: return false
	return true

# CPU phase for NP active powers (Magnetic Call)
func cpu_phase_np_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var all_opp: Array = []
	if main.opponent_active_pokemon != null: all_opp.append(main.opponent_active_pokemon)
	all_opp.append_array(main.opponent_bench)
	for p in all_opp:
		if p.power_used_this_turn: continue
		if is_power_blocked_by_status(p): continue
		for ab in p.metadata.get("abilities", []):
			if ab.get("name", "") == "Magnetic Call":
				if main.opponent_bench.size() < 5:
					var has_metal_basic = main.opponent_deck.any(func(c):
						return "Basic" in c.metadata.get("subtypes", []) and "Metal" in c.metadata.get("types", []))
					if has_metal_basic:
						await power_magnetic_call(p)
						if main._should_bail(): return

######################################################################################################################################################
##################################################### ECARD1 (EXPEDITION) POWERS #####################################################################
######################################################################################################################################################

func _register_ecard1_powers() -> void:
	_power_dispatch["Beating Wings"]     = func(p): await power_ecard1_beating_wings(p)
	_power_dispatch["Burning Energy"]    = func(p): await power_ecard1_burning_energy(p)
	_power_dispatch["Chaos Move"]        = func(p): await power_ecard1_chaos_move(p)
	_power_dispatch["Energy Connect"]    = func(p): await power_ecard1_energy_connect(p)
	_power_dispatch["Harvest Bounty"]    = func(p): await power_ecard1_harvest_bounty(p)
	_power_dispatch["Heat Up"]           = func(p): await power_ecard1_heat_up(p)
	_power_dispatch["Jet Stream"]        = func(p): await power_ecard1_jet_stream(p)
	_power_dispatch["Major Tsunami"]     = func(p): await power_ecard1_major_tsunami(p)
	_power_dispatch["Miraculous Powder"] = func(p): await power_ecard1_miraculous_powder(p)
	_power_dispatch["Moonlight"]         = func(p): await power_ecard1_moonlight(p)
	_power_dispatch["Plunge"]            = func(p): await power_ecard1_plunge(p)
	_power_dispatch["Poison Pollen"]     = func(p): await power_ecard1_poison_pollen(p)
	_power_dispatch["Psymimic"]          = func(p): await power_ecard1_psymimic(p)
	_power_dispatch["Soothing Aroma"]    = func(p): await power_ecard1_soothing_aroma(p)
	_power_dispatch["Tailwind"]          = func(p): await power_ecard1_tailwind(p)
	_power_dispatch["Terraforming"]      = func(p): await power_ecard1_terraforming(p)
	# Rock Body (Golem), Dark Aura (Tyranitar) and Exoskeleton (Metapod) are Poké-Bodies —
	# handled passively via is_ecard1_dark_aura_active()/calculate_final_damage, not this dispatch.

# BEATING WINGS (Pidgeot ecard1-23): once per turn, if Pidgeot is Active, shuffle 1 Benched Pokemon + attachments into deck
func power_ecard1_beating_wings(pidgeot: card_object) -> void:
	var is_opponent = pidgeot.is_owner_opp(main)
	if is_power_blocked_by_status(pidgeot):
		await main.show_message("BEATING WINGS IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pidgeot.power_used_this_turn:
		await main.show_message("BEATING WINGS ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != pidgeot:
		await main.show_message("BEATING WINGS REQUIRES PIDGEOT TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if bench.is_empty():
		await main.show_message("NO BENCHED POKEMON TO SHUFFLE!")
		if main._should_bail(): return
		return
	var target: card_object = null
	if is_opponent:
		# CPU: reclaim the worst-condition bench Pokemon (lowest HP ratio) rather than a random pick
		var worst_ratio = 2.0
		for bp in bench:
			var ratio = float(bp.current_hp) / float(max(1, bp.get_max_hp()))
			if ratio < worst_ratio:
				worst_ratio = ratio
				target = bp
	else:
		target = await main.card_ops.prompt_select_card(bench, "BEATING WINGS", "Select a Benched Pokemon to shuffle into your deck", "SHUFFLE", false)
		if main._should_bail(): return
	if target == null: return
	pidgeot.power_used_this_turn = true
	for e in target.attached_energies:
		e.current_location = "deck"
		deck.append(e)
	target.attached_energies.clear()
	for pre in target.attached_pre_evolutions:
		pre.current_location = "deck"
		deck.append(pre)
	target.attached_pre_evolutions.clear()
	for ac in target.attached_cards:
		ac.current_location = "deck"
		deck.append(ac)
	target.attached_cards.clear()
	bench.erase(target)
	target.current_location = "deck"
	main.clear_all_statuses(target, is_opponent)
	deck.append(target)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("BEATING WINGS! " + target.metadata.get("name","").to_upper() + " SHUFFLED INTO DECK!")
	if main._should_bail(): return
	print("POWER USED: Beating Wings")

# BURNING ENERGY (Charizard ecard1-6): once per turn, all basic Energy on your side counts as Fire this turn
func power_ecard1_burning_energy(charizard: card_object) -> void:
	var is_opponent = charizard.is_owner_opp(main)
	if is_power_blocked_by_status(charizard):
		await main.show_message("BURNING ENERGY IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if charizard.power_used_this_turn:
		await main.show_message("BURNING ENERGY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	charizard.power_used_this_turn = true
	if is_opponent:
		main.opponent_ecard1_burning_energy_active = true
	else:
		main.player_ecard1_burning_energy_active = true
	await main.show_message("BURNING ENERGY! ALL BASIC ENERGY COUNTS AS FIRE THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Burning Energy")

# CHAOS MOVE (Gengar ecard1-13): once per turn, if opponent has 3 or fewer Prizes, move 1 damage counter between any two Pokemon
func power_ecard1_chaos_move(gengar: card_object) -> void:
	var is_opponent = gengar.is_owner_opp(main)
	if is_power_blocked_by_status(gengar):
		await main.show_message("CHAOS MOVE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if gengar.power_used_this_turn:
		await main.show_message("CHAOS MOVE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var opp_prizes = main.player_prize_cards if is_opponent else main.opponent_prize_cards
	if opp_prizes.size() > 3:
		await main.show_message("CHAOS MOVE REQUIRES OPPONENT TO HAVE 3 OR FEWER PRIZES!")
		if main._should_bail(): return
		return
	var all_pokemon: Array = []
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		var bench_arr = main.opponent_bench if side else main.player_bench
		if active != null: all_pokemon.append(active)
		all_pokemon.append_array(bench_arr)
	var sources = all_pokemon.filter(func(p): return p.current_hp < p.get_max_hp())
	if sources.is_empty():
		await main.show_message("NO POKEMON HAS DAMAGE TO MOVE!")
		if main._should_bail(): return
		return
	var source: card_object = null
	var dest: card_object = null
	if is_opponent:
		source = sources[0]
		var dests = all_pokemon.filter(func(p): return p != source)
		dest = dests[0] if dests.size() > 0 else null
	else:
		source = await main.card_ops.prompt_select_card(sources, "CHAOS MOVE - SOURCE", "Select a Pokemon to move a damage counter FROM", "SELECT", true)
		if main._should_bail(): return
		if source == null: return
		var dests = all_pokemon.filter(func(p): return p != source)
		dest = await main.card_ops.prompt_select_card(dests, "CHAOS MOVE - DESTINATION", "Select a Pokemon to move the damage counter TO", "MOVE", true)
		if main._should_bail(): return
	if source == null or dest == null: return
	gengar.power_used_this_turn = true
	source.current_hp = min(source.get_max_hp(), source.current_hp + 10)
	dest.current_hp = max(0, dest.current_hp - 10)
	main.display_pokemon(false)
	main.display_pokemon(true)
	await main.show_message("CHAOS MOVE! DAMAGE COUNTER MOVED FROM " + source.metadata.get("name","").to_upper() + " TO " + dest.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Chaos Move")

# ENERGY CONNECT (Ampharos ecard1-2): repeatable, move a basic Energy from a Benched Pokemon to your Active
func power_ecard1_energy_connect(ampharos: card_object) -> void:
	var is_opponent = ampharos.is_owner_opp(main)
	if is_power_blocked_by_status(ampharos):
		await main.show_message("ENERGY CONNECT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active == null: return
	var keep_going = true
	while keep_going:
		var sources = bench.filter(func(p): return p.attached_energies.any(func(e): return e.metadata.get("supertype","") == "Energy" and "Special" not in e.metadata.get("subtypes",[])))
		if sources.is_empty():
			if not is_opponent:
				await main.show_message("NO BENCHED ENERGY TO MOVE!")
				if main._should_bail(): return
			break
		var source: card_object = null
		if is_opponent:
			source = sources[0]
		else:
			source = await main.card_ops.prompt_select_card(sources, "ENERGY CONNECT", "Select a Benched Pokemon to move Energy from (cancel to stop)", "SELECT", true)
			if main._should_bail(): return
		if source == null: break
		var basics = source.attached_energies.filter(func(e): return e.metadata.get("supertype","") == "Energy" and "Special" not in e.metadata.get("subtypes",[]))
		var energy: card_object = null
		if is_opponent:
			energy = basics[0]
		else:
			energy = await main.card_ops.prompt_select_card(basics, "ENERGY CONNECT", "Select the Energy to move", "SELECT", true)
			if main._should_bail(): return
		if energy == null: break
		source.attached_energies.erase(energy)
		active.attached_energies.append(energy)
		main.display_active_pokemon_energies(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("ENERGY CONNECT! " + energy.metadata.get("name","").to_upper() + " MOVED TO " + active.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		if is_opponent:
			keep_going = false
	print("POWER USED: Energy Connect")

# HARVEST BOUNTY (Venusaur ecard1-30): once per turn, attach an extra basic Energy from hand to your Active
func power_ecard1_harvest_bounty(venusaur: card_object) -> void:
	var is_opponent = venusaur.is_owner_opp(main)
	if is_power_blocked_by_status(venusaur):
		await main.show_message("HARVEST BOUNTY IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if venusaur.power_used_this_turn:
		await main.show_message("HARVEST BOUNTY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics = hand.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
	if basics.is_empty():
		await main.show_message("NO BASIC ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var chosen: card_object = null
	if is_opponent:
		chosen = basics[0]
	else:
		chosen = await main.card_ops.prompt_select_card(basics, "HARVEST BOUNTY", "Select a basic Energy to attach to your Active", "ATTACH", true)
		if main._should_bail(): return
	if chosen == null: return
	venusaur.power_used_this_turn = true
	hand.erase(chosen)
	chosen.current_location = "active"
	active.attached_energies.append(chosen)
	main.refresh_hand_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("HARVEST BOUNTY! " + chosen.metadata.get("name","").to_upper() + " ATTACHED TO " + active.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Harvest Bounty")

# HEAT UP (Typhlosion ecard1-28): once per turn, if opponent has more total Energy attached, search deck for 1 Fire Energy and bench-attach it
func power_ecard1_heat_up(typhlosion: card_object) -> void:
	var is_opponent = typhlosion.is_owner_opp(main)
	if is_power_blocked_by_status(typhlosion):
		await main.show_message("HEAT UP IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if typhlosion.power_used_this_turn:
		await main.show_message("HEAT UP ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var own_total = 0
	var all_own: Array = []
	if own_active != null: all_own.append(own_active)
	all_own.append_array(own_bench)
	for p in all_own: own_total += p.attached_energies.size()
	var opp_total = 0
	var all_opp: Array = []
	if opp_active != null: all_opp.append(opp_active)
	all_opp.append_array(opp_bench)
	for p in all_opp: opp_total += p.attached_energies.size()
	typhlosion.power_used_this_turn = true
	if opp_total <= own_total:
		await main.show_message("HEAT UP! OPPONENT DOESN'T HAVE MORE ENERGY — NO EFFECT!")
		if main._should_bail(): return
		return
	if own_bench.is_empty():
		await main.show_message("HEAT UP! NO BENCHED POKEMON TO ATTACH ENERGY TO!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var fire_energies = deck.filter(func(c): return c.metadata.get("name","") == "Fire Energy")
	if fire_energies.is_empty():
		await main.show_message("HEAT UP! NO FIRE ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		return
	var target: card_object = null
	if is_opponent:
		target = own_bench[0]
	else:
		target = await main.card_ops.prompt_select_card(own_bench, "HEAT UP", "Select a Benched Pokemon to attach Fire Energy to", "ATTACH", false)
		if main._should_bail(): return
	if target == null:
		deck.shuffle()
		return
	var energy = fire_energies[0]
	deck.erase(energy)
	energy.current_location = "bench"
	target.attached_energies.append(energy)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEAT UP! FIRE ENERGY ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Heat Up")

# JET STREAM (Blastoise ecard1-4): once per turn if Blastoise is Active, flip; heads discard own Energy then 1 opponent Energy
func power_ecard1_jet_stream(blastoise: card_object) -> void:
	var is_opponent = blastoise.is_owner_opp(main)
	if is_power_blocked_by_status(blastoise):
		await main.show_message("JET STREAM IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if blastoise.power_used_this_turn:
		await main.show_message("JET STREAM ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != blastoise:
		await main.show_message("JET STREAM REQUIRES BLASTOISE TO BE ACTIVE!")
		if main._should_bail(): return
		return
	blastoise.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! JET STREAM HAD NO EFFECT!")
		if main._should_bail(): return
		return
	if blastoise.attached_energies.size() > 0:
		var own_e = blastoise.attached_energies[0]
		main.card_ops.discard_energy_from_pokemon(own_e, is_opponent)
		main.display_active_pokemon_energies(is_opponent)
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender != null and defender.attached_energies.size() > 0:
		var opp_e = defender.attached_energies[0]
		main.card_ops.discard_energy_from_pokemon(opp_e, not is_opponent)
		main.display_active_pokemon_energies(not is_opponent)
	await main.show_message("HEADS! JET STREAM DISCARDED ENERGY FROM BOTH ACTIVES!")
	if main._should_bail(): return
	print("POWER USED: Jet Stream")

# MAJOR TSUNAMI (Feraligatr ecard1-12): once per turn if Feraligatr is Active, force-switch opponent's Active, then switch Feraligatr with your bench
func power_ecard1_major_tsunami(feraligatr: card_object) -> void:
	var is_opponent = feraligatr.is_owner_opp(main)
	if is_power_blocked_by_status(feraligatr):
		await main.show_message("MAJOR TSUNAMI IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if feraligatr.power_used_this_turn:
		await main.show_message("MAJOR TSUNAMI ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != feraligatr:
		await main.show_message("MAJOR TSUNAMI REQUIRES FERALIGATR TO BE ACTIVE!")
		if main._should_bail(): return
		return
	feraligatr.power_used_this_turn = true
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_target_is_opp = not is_opponent
	if opp_bench.size() > 0:
		var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
		var new_opp_active: card_object = null
		if opp_target_is_opp:
			var cpu_eval = main.cpu_ai.get_cpu_evaluation()
			new_opp_active = main.cpu_ai.pick_best_bench_replacement(opp_bench, main.player_active_pokemon, cpu_eval)
			if new_opp_active == null: new_opp_active = opp_bench[0]
		else:
			new_opp_active = await main.card_ops.prompt_select_card(opp_bench, "MAJOR TSUNAMI", "Opponent switches: select a Benched Pokemon", "SWITCH", false)
			if main._should_bail(): return
		if new_opp_active != null:
			opp_bench.erase(new_opp_active)
			opp_bench.append(opp_active)
			opp_active.current_location = "bench"
			new_opp_active.current_location = "active"
			if opp_target_is_opp:
				main.opponent_active_pokemon = new_opp_active
			else:
				main.player_active_pokemon = new_opp_active
			await main.animate_retreat(opp_active, new_opp_active, [], opp_target_is_opp)
			if main._should_bail(): return
			main.clear_all_statuses(opp_active, opp_target_is_opp)
			main.display_pokemon(opp_target_is_opp)
			main.display_active_pokemon_energies(opp_target_is_opp)
	var own_bench = main.opponent_bench if is_opponent else main.player_bench
	if own_bench.size() > 0:
		var new_own_active: card_object = null
		if is_opponent:
			var cpu_eval2 = main.cpu_ai.get_cpu_evaluation()
			new_own_active = main.cpu_ai.pick_best_bench_replacement(own_bench, main.player_active_pokemon, cpu_eval2)
			if new_own_active == null: new_own_active = own_bench[0]
		else:
			new_own_active = await main.card_ops.prompt_select_card(own_bench, "MAJOR TSUNAMI", "Select a Benched Pokemon to switch Feraligatr with", "SWITCH", false)
			if main._should_bail(): return
		if new_own_active != null:
			own_bench.erase(new_own_active)
			own_bench.append(feraligatr)
			feraligatr.current_location = "bench"
			new_own_active.current_location = "active"
			if is_opponent:
				main.opponent_active_pokemon = new_own_active
			else:
				main.player_active_pokemon = new_own_active
			await main.animate_retreat(feraligatr, new_own_active, [], is_opponent)
			if main._should_bail(): return
			main.clear_all_statuses(feraligatr, is_opponent)
			main.display_pokemon(is_opponent)
			main.display_active_pokemon_energies(is_opponent)
	await main.show_message("MAJOR TSUNAMI!")
	if main._should_bail(): return
	print("POWER USED: Major Tsunami")

# MIRACULOUS POWDER (Butterfree ecard1-5): once per turn, remove all Special Conditions from your Active
func power_ecard1_miraculous_powder(butterfree: card_object) -> void:
	var is_opponent = butterfree.is_owner_opp(main)
	if is_power_blocked_by_status(butterfree):
		await main.show_message("MIRACULOUS POWDER IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if butterfree.power_used_this_turn:
		await main.show_message("MIRACULOUS POWDER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	butterfree.power_used_this_turn = true
	var had_status = active.special_condition != "" or active.is_poisoned
	main.clear_all_statuses(active, is_opponent)
	if had_status:
		await main.show_message("MIRACULOUS POWDER! ALL SPECIAL CONDITIONS REMOVED!")
	else:
		await main.show_message("MIRACULOUS POWDER! NO CONDITIONS TO REMOVE!")
	if main._should_bail(): return
	print("POWER USED: Miraculous Powder")

# MOONLIGHT (Clefable ecard1-7): once per turn, put a hand card back on deck, then search deck for a basic Energy
func power_ecard1_moonlight(clefable: card_object) -> void:
	var is_opponent = clefable.is_owner_opp(main)
	if is_power_blocked_by_status(clefable):
		await main.show_message("MOONLIGHT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if clefable.power_used_this_turn:
		await main.show_message("MOONLIGHT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.is_empty():
		await main.show_message("NO CARDS IN HAND!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var card_to_return: card_object = await main.card_ops.choose_card(hand, is_opponent,
			"MOONLIGHT", "Select a card to put back on your deck", "SELECT", true, func(_c): return 0.0)
	if main._should_bail(): return
	if card_to_return == null: return
	clefable.power_used_this_turn = true
	hand.erase(card_to_return)
	card_to_return.current_location = "deck"
	deck.insert(0, card_to_return)
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	var basic_energies = deck.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
	if basic_energies.is_empty():
		await main.show_message("MOONLIGHT! NO BASIC ENERGY IN DECK!")
		if main._should_bail(): return
		deck.shuffle()
		main.update_deck_icon(is_opponent)
		return
	var chosen: card_object = await main.card_ops.choose_card(basic_energies, is_opponent,
			"MOONLIGHT", "Select a basic Energy to add to hand", "SELECT", false, Callable(), true)
	if main._should_bail(): return
	if chosen != null:
		deck.erase(chosen)
		chosen.current_location = "hand"
		hand.append(chosen)
		main.refresh_hand_display(is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	await main.show_message("MOONLIGHT! ADDED " + (chosen.metadata.get("name","").to_upper() if chosen != null else "NOTHING") + " TO HAND!")
	if main._should_bail(): return
	print("POWER USED: Moonlight")

# PLUNGE (Poliwrath ecard1-24): once per turn if Poliwrath on Bench, flip; heads move all Active's Energy to Poliwrath, then switch in
func power_ecard1_plunge(poliwrath: card_object) -> void:
	var is_opponent = poliwrath.is_owner_opp(main)
	if is_power_blocked_by_status(poliwrath):
		await main.show_message("PLUNGE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if poliwrath.power_used_this_turn:
		await main.show_message("PLUNGE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if poliwrath not in bench:
		await main.show_message("PLUNGE REQUIRES POLIWRATH TO BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	poliwrath.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! PLUNGE HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	for e in active.attached_energies.duplicate():
		active.attached_energies.erase(e)
		poliwrath.attached_energies.append(e)
	bench.erase(poliwrath)
	bench.append(active)
	active.current_location = "bench"
	poliwrath.current_location = "active"
	if is_opponent:
		main.opponent_active_pokemon = poliwrath
	else:
		main.player_active_pokemon = poliwrath
	await main.animate_retreat(active, poliwrath, [], is_opponent)
	if main._should_bail(): return
	main.clear_all_statuses(active, is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("HEADS! PLUNGE! POLIWRATH SWITCHED IN WITH ALL ENERGY!")
	if main._should_bail(): return
	print("POWER USED: Plunge")

# POISON POLLEN (Vileplume ecard1-31): once per turn, flip; heads Poison the Defending Pokemon
func power_ecard1_poison_pollen(vileplume: card_object) -> void:
	var is_opponent = vileplume.is_owner_opp(main)
	if is_power_blocked_by_status(vileplume):
		await main.show_message("POISON POLLEN IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if vileplume.power_used_this_turn:
		await main.show_message("POISON POLLEN ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender == null: return
	vileplume.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! POISON POLLEN HAD NO EFFECT!")
		if main._should_bail(): return
		return
	main.card_ops.apply_status(defender, "Poisoned", not is_opponent)
	main.update_status_icons(defender, not is_opponent)
	await main.show_message("HEADS! DEFENDING POKEMON IS POISONED!")
	if main._should_bail(): return
	print("POWER USED: Poison Pollen")

# PSYMIMIC (Alakazam ecard1-1): once per turn, instead of attacking, choose 1 of your opponent's
# Pokémon's attacks (any of their Pokémon — Active or Benched, per card text) and copy it.
# The player is offered a real choice via the shared attack chooser (choose_attack_from_pool) —
# the same mechanism used by Metronome. Energy cost is validated against Alakazam's own attached
# energy via execute_copied_attack(require_cost=true). The copied attack always targets the
# opponent's Active Pokemon (as the real card requires), regardless of which of their Pokemon it
# was copied from.
func power_ecard1_psymimic(alakazam: card_object) -> void:
	var is_opponent = alakazam.is_owner_opp(main)
	if is_power_blocked_by_status(alakazam):
		await main.show_message("PSYMIMIC IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if alakazam.power_used_this_turn:
		await main.show_message("PSYMIMIC ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != alakazam:
		await main.show_message("PSYMIMIC REQUIRES ALAKAZAM TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_active == null: return
	var opp_pokemon: Array = [opp_active]
	opp_pokemon.append_array(opp_bench)
	var candidate_attacks: Array = []
	var seen_names: Dictionary = {}
	for p in opp_pokemon:
		for atk in main.get_attacks_for_card(p):
			var n = atk.get("name", "")
			# Only offer attacks Alakazam can actually pay for — per card text the copied attack's
			# cost is paid from Alakazam's own energy, so an unaffordable attack is never a real choice.
			if n != "" and not seen_names.has(n) and main.cpu_ai.get_unmet_energy_count(atk, alakazam) == 0:
				seen_names[n] = true
				candidate_attacks.append(atk)
	if candidate_attacks.is_empty():
		await main.show_message("NO AFFORDABLE ATTACKS TO COPY!")
		if main._should_bail(): return
		return
	var cpu_rank = func(atk: Dictionary) -> float:
		var dmg_range = main.attack_effects.estimate_attack_damage_range(atk, alakazam, opp_active)
		var result = main.calculate_final_damage(dmg_range["max"], alakazam.metadata.get("types", ["Colorless"]), opp_active, alakazam)
		var score = float(result["damage"])
		var parsed = main.attack_effects.parse_card_text_effects(atk.get("text", ""), alakazam.metadata.get("name", ""))
		score += main.cpu_ai.score_parsed_effects(parsed, opp_active)
		return score
	var chosen_attack = await main.attack_effects.choose_attack_from_pool(candidate_attacks, is_opponent, cpu_rank)
	if chosen_attack.is_empty(): return
	alakazam.power_used_this_turn = true
	await main.show_message("PSYMIMIC! COPYING " + chosen_attack.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.attack_effects.execute_copied_attack(chosen_attack, alakazam, opp_active, is_opponent, true)
	if main._should_bail(): return
	print("POWER USED: Psymimic — copied ", chosen_attack.get("name",""))

# SOOTHING AROMA (Meganium ecard1-18): once per turn, flip; heads remove 1 damage counter from each of your damaged Pokemon
func power_ecard1_soothing_aroma(meganium: card_object) -> void:
	var is_opponent = meganium.is_owner_opp(main)
	if is_power_blocked_by_status(meganium):
		await main.show_message("SOOTHING AROMA IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if meganium.power_used_this_turn:
		await main.show_message("SOOTHING AROMA ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	meganium.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! SOOTHING AROMA HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_pokemon: Array = []
	if active != null: all_pokemon.append(active)
	all_pokemon.append_array(bench)
	var healed_any = false
	for p in all_pokemon:
		if p.current_hp < p.get_max_hp():
			p.current_hp = min(p.get_max_hp(), p.current_hp + 10)
			main.display_hp_circles_above_align(p, is_opponent)
			healed_any = true
	main.display_pokemon(is_opponent)
	if healed_any:
		await main.show_message("HEADS! SOOTHING AROMA! ALL DAMAGED POKEMON HEALED 10 HP!")
	else:
		await main.show_message("HEADS! BUT NO POKEMON HAD DAMAGE!")
	if main._should_bail(): return
	print("POWER USED: Soothing Aroma")

# TAILWIND (Dragonite ecard1-9): once per turn, if Dragonite is on your Bench, your Active's Retreat Cost becomes 0
func power_ecard1_tailwind(dragonite: card_object) -> void:
	var is_opponent = dragonite.is_owner_opp(main)
	if is_power_blocked_by_status(dragonite):
		await main.show_message("TAILWIND IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if dragonite.power_used_this_turn:
		await main.show_message("TAILWIND ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if dragonite not in bench:
		await main.show_message("TAILWIND REQUIRES DRAGONITE TO BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	dragonite.power_used_this_turn = true
	active.set_effect("ecard1_tailwind", "end_of_own_turn")
	await main.show_message("TAILWIND! " + active.metadata.get("name","").to_upper() + "'S RETREAT COST IS NOW 0!")
	if main._should_bail(): return
	print("POWER USED: Tailwind")

# TERRAFORMING (Machamp ecard1-16): once per turn, look at the top 4 cards of your deck; you may move 1 to the top
# TERRAFORMING (Machamp ecard1-16): once per turn, look at the top 4 cards of your deck and
# rearrange them as you like. Uses the same click-in-order reorder UI as base1-87 Pokedex
# (main.trainer_reorder_active / pokedex_cards / pokedex_reorder_result / trainer_reorder_done),
# just with a 4-card window instead of 5. CPU reorders via the same priority heuristic Pokedex uses.
func power_ecard1_terraforming(machamp: card_object) -> void:
	var is_opponent = machamp.is_owner_opp(main)
	if is_power_blocked_by_status(machamp):
		await main.show_message("TERRAFORMING IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if machamp.power_used_this_turn:
		await main.show_message("TERRAFORMING ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if deck.is_empty():
		await main.show_message("DECK IS EMPTY!")
		if main._should_bail(): return
		return
	machamp.power_used_this_turn = true
	var count = min(4, deck.size())
	var top_cards: Array = []
	for i in range(count):
		top_cards.append(deck[i])
	await main.show_message("TERRAFORMING: LOOKING AT TOP " + str(count) + " CARDS!")
	if main._should_bail(): return

	if is_opponent:
		top_cards.sort_custom(func(a, b): return main.trainer_effects._cpu_pokedex_priority(a) > main.trainer_effects._cpu_pokedex_priority(b))
		for i in range(count):
			deck[i] = top_cards[i]
		await main.show_message("OPPONENT REARRANGED THE TOP " + str(count) + " CARDS OF THEIR DECK!")
		if main._should_bail(): return
	else:
		main.pokedex_cards = top_cards.duplicate()
		main.pokedex_reorder_result.clear()
		main.trainer_reorder_active = true

		main.show_enlarged_array_selection_mode(main.pokedex_cards)
		main.header_label.text = "TERRAFORMING - CLICK CARDS IN ORDER"
		main.hint_label.text = "Click cards in the order you want them (top of deck first)"
		main.action_button.text = "0/" + str(count) + " SELECTED"
		main.action_button.disabled = true
		main.action_button.theme = main.theme_disabled
		main.cancel_button.visible = false

		await main.trainer_reorder_done
		if main._should_bail(): return
		main.trainer_reorder_active = false
		main.hide_selection_mode_display_main()

		for i in range(main.pokedex_reorder_result.size()):
			deck[i] = main.pokedex_reorder_result[i]
		main.pokedex_cards.clear()
		main.pokedex_reorder_result.clear()
	print("POWER USED: Terraforming")

# CPU phase for ECARD1 active powers
func cpu_phase_ecard1_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var poison_pollen = _find_cpu_pokemon_with_power("Poison Pollen")
	if poison_pollen != null and not poison_pollen.power_used_this_turn and not is_power_blocked_by_status(poison_pollen):
		await power_ecard1_poison_pollen(poison_pollen)
		if main._should_bail(): return

	var miraculous_powder = _find_cpu_pokemon_with_power("Miraculous Powder")
	if miraculous_powder != null and not miraculous_powder.power_used_this_turn and not is_power_blocked_by_status(miraculous_powder):
		if main.opponent_active_pokemon != null and (main.opponent_active_pokemon.special_condition != "" or main.opponent_active_pokemon.is_poisoned):
			await power_ecard1_miraculous_powder(miraculous_powder)
			if main._should_bail(): return

	var soothing_aroma = _find_cpu_pokemon_with_power("Soothing Aroma")
	if soothing_aroma != null and not soothing_aroma.power_used_this_turn and not is_power_blocked_by_status(soothing_aroma):
		var any_opp_damaged = false
		var all_opp_p: Array = []
		if main.opponent_active_pokemon != null: all_opp_p.append(main.opponent_active_pokemon)
		all_opp_p.append_array(main.opponent_bench)
		for p in all_opp_p:
			if p.current_hp < p.get_max_hp(): any_opp_damaged = true
		if any_opp_damaged:
			await power_ecard1_soothing_aroma(soothing_aroma)
			if main._should_bail(): return

	var jet_stream = _find_cpu_pokemon_with_power("Jet Stream")
	if jet_stream != null and jet_stream == main.opponent_active_pokemon and not jet_stream.power_used_this_turn and not is_power_blocked_by_status(jet_stream):
		if main.player_active_pokemon != null and main.player_active_pokemon.attached_energies.size() > 0:
			await power_ecard1_jet_stream(jet_stream)
			if main._should_bail(): return

	var harvest_bounty = _find_cpu_pokemon_with_power("Harvest Bounty")
	if harvest_bounty != null and not harvest_bounty.power_used_this_turn and not is_power_blocked_by_status(harvest_bounty):
		var has_basic_energy_in_hand = main.opponent_hand.any(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
		if has_basic_energy_in_hand:
			await power_ecard1_harvest_bounty(harvest_bounty)
			if main._should_bail(): return

	var energy_connect = _find_cpu_pokemon_with_power("Energy Connect")
	if energy_connect != null and not is_power_blocked_by_status(energy_connect):
		await power_ecard1_energy_connect(energy_connect)
		if main._should_bail(): return

	var tailwind = _find_cpu_bench_pokemon_with_power("Tailwind")
	if tailwind != null and not tailwind.power_used_this_turn and not is_power_blocked_by_status(tailwind):
		if main.opponent_active_pokemon != null and main.get_retreat_cost(main.opponent_active_pokemon) > 0:
			await power_ecard1_tailwind(tailwind)
			if main._should_bail(): return

	var chaos_move = _find_cpu_pokemon_with_power("Chaos Move")
	if chaos_move != null and not chaos_move.power_used_this_turn and not is_power_blocked_by_status(chaos_move):
		if main.player_prize_cards.size() <= 3:
			await power_ecard1_chaos_move(chaos_move)
			if main._should_bail(): return

	var beating_wings = _find_cpu_pokemon_with_power("Beating Wings")
	if beating_wings != null and beating_wings == main.opponent_active_pokemon and not beating_wings.power_used_this_turn and not is_power_blocked_by_status(beating_wings):
		# Only worth it to reclaim a bench Pokemon that's badly damaged and not pulling its weight
		var worst_ratio = 1.0
		for bp in main.opponent_bench:
			var ratio = float(bp.current_hp) / float(max(1, bp.get_max_hp()))
			if ratio < worst_ratio:
				worst_ratio = ratio
		if worst_ratio < 0.35:
			await power_ecard1_beating_wings(beating_wings)
			if main._should_bail(): return

	var burning_energy = _find_cpu_pokemon_with_power("Burning Energy")
	if burning_energy != null and not burning_energy.power_used_this_turn and not is_power_blocked_by_status(burning_energy):
		# Only useful if the CPU's Active has a Fire-cost attack it currently can't pay for
		var needs_fire = false
		if main.opponent_active_pokemon != null:
			for atk in main.opponent_active_pokemon.metadata.get("attacks", []):
				if "Fire" in atk.get("cost", []) and main.cpu_ai.get_unmet_energy_count(atk, main.opponent_active_pokemon) > 0:
					needs_fire = true
					break
		if needs_fire:
			await power_ecard1_burning_energy(burning_energy)
			if main._should_bail(): return

	var heat_up = _find_cpu_pokemon_with_power("Heat Up")
	if heat_up != null and not heat_up.power_used_this_turn and not is_power_blocked_by_status(heat_up):
		var own_total = 0
		var all_own: Array = []
		if main.opponent_active_pokemon != null: all_own.append(main.opponent_active_pokemon)
		all_own.append_array(main.opponent_bench)
		for p in all_own: own_total += p.attached_energies.size()
		var opp_total = 0
		var all_opp: Array = []
		if main.player_active_pokemon != null: all_opp.append(main.player_active_pokemon)
		all_opp.append_array(main.player_bench)
		for p in all_opp: opp_total += p.attached_energies.size()
		# Matches the power's own no-op condition — don't waste the once-per-turn use on a fizzle
		if opp_total > own_total and main.opponent_bench.size() > 0:
			await power_ecard1_heat_up(heat_up)
			if main._should_bail(): return

	var major_tsunami = _find_cpu_pokemon_with_power("Major Tsunami")
	if major_tsunami != null and major_tsunami == main.opponent_active_pokemon and not major_tsunami.power_used_this_turn and not is_power_blocked_by_status(major_tsunami):
		# Use it defensively: disrupt the opponent's setup while retreating a badly-hurt Feraligatr
		var hp_ratio = float(major_tsunami.current_hp) / float(max(1, major_tsunami.get_max_hp()))
		if hp_ratio < 0.5 and main.opponent_bench.size() > 0:
			await power_ecard1_major_tsunami(major_tsunami)
			if main._should_bail(): return

	var moonlight = _find_cpu_pokemon_with_power("Moonlight")
	if moonlight != null and not moonlight.power_used_this_turn and not is_power_blocked_by_status(moonlight):
		var has_basic_energy_in_deck = main.opponent_deck.any(func(c): return c.metadata.get("supertype","") == "Energy" and "Special" not in c.metadata.get("subtypes",[]))
		# Don't sacrifice the CPU's only card in hand, and don't bother if there's nothing to fetch
		if main.opponent_hand.size() >= 2 and has_basic_energy_in_deck:
			await power_ecard1_moonlight(moonlight)
			if main._should_bail(): return

	var plunge = _find_cpu_bench_pokemon_with_power("Plunge")
	if plunge != null and not plunge.power_used_this_turn and not is_power_blocked_by_status(plunge):
		var current_active = main.opponent_active_pokemon
		if current_active != null and current_active.attached_energies.size() > 0:
			var hp_ratio = float(current_active.current_hp) / float(max(1, current_active.get_max_hp()))
			# Preserve the Active's energy investment onto Poliwrath before the Active gets KO'd
			if hp_ratio < 0.4:
				await power_ecard1_plunge(plunge)
				if main._should_bail(): return

	var psymimic = _find_cpu_pokemon_with_power("Psymimic")
	if psymimic != null and psymimic == main.opponent_active_pokemon and not psymimic.power_used_this_turn and not is_power_blocked_by_status(psymimic):
		var opp_target = main.player_active_pokemon
		if opp_target != null:
			# Compare Alakazam's own best attack against the best attack it could copy; only use
			# Psymimic if copying is clearly better than attacking normally this turn.
			var own_best_score = 0.0
			for atk in psymimic.metadata.get("attacks", []):
				if main.cpu_ai.get_unmet_energy_count(atk, psymimic) == 0:
					var dmg_range = main.attack_effects.estimate_attack_damage_range(atk, psymimic, opp_target)
					var result = main.calculate_final_damage(dmg_range["max"], psymimic.metadata.get("types", ["Colorless"]), opp_target, psymimic)
					own_best_score = max(own_best_score, float(result["damage"]))
			var pool: Array = []
			var seen: Dictionary = {}
			var opp_field: Array = [opp_target]
			opp_field.append_array(main.player_bench)
			for p in opp_field:
				for atk in main.get_attacks_for_card(p):
					var n = atk.get("name", "")
					if n != "" and not seen.has(n) and main.cpu_ai.get_unmet_energy_count(atk, psymimic) == 0:
						seen[n] = true
						pool.append(atk)
			var best_copy_score = 0.0
			for atk in pool:
				var dmg_range2 = main.attack_effects.estimate_attack_damage_range(atk, psymimic, opp_target)
				var result2 = main.calculate_final_damage(dmg_range2["max"], psymimic.metadata.get("types", ["Colorless"]), opp_target, psymimic)
				best_copy_score = max(best_copy_score, float(result2["damage"]))
			if best_copy_score > own_best_score * 1.3:
				await power_ecard1_psymimic(psymimic)
				if main._should_bail(): return

	var terraforming = _find_cpu_pokemon_with_power("Terraforming")
	if terraforming != null and not terraforming.power_used_this_turn and not is_power_blocked_by_status(terraforming):
		await power_ecard1_terraforming(terraforming)
		if main._should_bail(): return

######################################################################################################################################################
################################################## DAMAGE-MODIFIER HOOK EXEMPLARS (Phase 3) ##########################################################
######################################################################################################################################################

# Flat unconditional damage-reduction Poké-Bodies (Exoskeleton/Rock Body/Vase Body/etc.), after
# W/R. The reduction amount is parsed from each card's own ability text ("reduced by N") rather
# than hardcoded, since the same ability name reprints with different amounts across sets
# (Metapod's Exoskeleton is -20, Forretress's ecard3 reprint is -10).
const _FLAT_REDUCTION_BODY_NAMES := ["Exoskeleton", "Rock Body", "Vase Body"]
func _hook_ecard1_reduction_bodies(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	for ability in defender.metadata.get("abilities", []):
		var ab_name = ability.get("name", "")
		if ab_name in _FLAT_REDUCTION_BODY_NAMES:
			var amount = main.attack_effects.extract_number_before(ability.get("text","").to_lower(), "(after applying")
			if amount <= 0: amount = 20
			var r = min(damage, amount)
			modifiers.append(ab_name.to_upper() + " -" + str(r))
			return damage - r
	return damage

# THICK SHELL (Kabuto, ecard3): -10 damage after W/R, but ONLY from Evolved Pokemon attackers
func _hook_ecard3_thick_shell(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if not defender.has_ability("Thick Shell"):
		return damage
	if main.is_basic_pokemon(attacker):
		return damage
	var r = min(damage, 10)
	modifiers.append("THICK SHELL -" + str(r))
	return damage - r

# EX3 Buffer Piece (ex3-83, Pokemon Tool): -20 damage after W/R while attached to the defender.
func _hook_ex3_buffer_piece(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	for ac in defender.attached_cards:
		if ac.uid.to_lower() == "ex3-83":
			var r = min(damage, 20)
			modifiers.append("BUFFER PIECE -" + str(r))
			return damage - r
	return damage

# EX3 Sand Guard (Flygon ex3-15, Poke-Body): flip a coin; heads reduces the damage by 20 (after W/R).
# Damage-modifier hooks are synchronous, so use an inline coin flip (no animation) — same documented
# simplification as ex1 Hard Cocoon.
func _hook_ex3_sand_guard(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if not defender.has_ability("Sand Guard"):
		return damage
	if randi() % 2 == 0:
		return damage
	var r = min(damage, 20)
	modifiers.append("SAND GUARD -" + str(r))
	return damage - r

# EX3 Energy Guard (Shelgon ex3-41, Poke-Body): -10 after W/R while any basic Energy is attached.
func _hook_ex3_energy_guard(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if not defender.has_ability("Energy Guard"):
		return damage
	var has_basic = false
	for e in defender.attached_energies:
		if "Basic" in e.metadata.get("subtypes", []):
			has_basic = true
			break
	if not has_basic:
		return damage
	var r = min(damage, 10)
	modifiers.append("ENERGY GUARD -" + str(r))
	return damage - r

# Strength Charm (ecard1-150 / ex4-74): +10 to attacker's damage once; flags itself for end-of-turn discard.
func _hook_ecard1_strength_charm(damage: int, attacker: card_object, _defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or attacker == null:
		return damage
	for ac in attacker.attached_cards:
		if ac.uid.to_lower() in ["ecard1-150", "ex4-74"]:
			modifiers.append("STRENGTH CHARM +10")
			attacker.set_effect("ecard1_strength_charm_triggered", "end_of_own_turn")
			return damage + 10
	return damage

# ECARD2 Poké-Bodies: Dense Body (Slowbro, -20 vs Basic non-Baby attackers), Energy Barrier
# (Mr. Mime, -10 per own attached basic Energy, capped at -20)
func _hook_ecard2_reduction_bodies(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if is_power_blocked(defender):
		return damage
	for ability in defender.metadata.get("abilities", []):
		var ab_name = ability.get("name", "")
		if ab_name == "Dense Body":
			if attacker != null:
				var atk_subtypes = attacker.metadata.get("subtypes", [])
				if "Basic" in atk_subtypes and "Baby" not in atk_subtypes:
					var r = min(damage, 20)
					modifiers.append("DENSE BODY -" + str(r))
					return damage - r
		elif ab_name == "Energy Barrier":
			var basic_count = 0
			for e in defender.attached_energies:
				if e.metadata.get("supertype","") == "Energy" and "Special" not in e.metadata.get("subtypes",[]):
					basic_count += 1
			var r2 = min(damage, min(20, basic_count * 10))
			if r2 > 0:
				modifiers.append("ENERGY BARRIER -" + str(r2))
				return damage - r2
	return damage

######################################################################################################################################################
######################################################### ECARD2 (AQUAPOLIS) POWERS/BODIES ###########################################################
######################################################################################################################################################

func _register_ecard2_powers() -> void:
	_power_dispatch["Bubble Turn"]        = func(p): await power_ecard2_bubble_turn(p)
	_power_dispatch["Flower Supplement"]  = func(p): await power_ecard2_flower_supplement(p)
	_power_dispatch["Happy Healing"]      = func(p): await power_ecard2_happy_healing(p)
	_power_dispatch["Super Dynamo"]       = func(p): await power_ecard2_super_dynamo(p)
	_power_dispatch["Energy Return"]      = func(p): await power_ecard2_energy_return(p)
	_power_dispatch["Sleep Pendulum"]     = func(p): await power_ecard2_sleep_pendulum(p)
	_power_dispatch["Water Cyclone"]      = func(p): await power_ecard2_water_cyclone(p)
	_power_dispatch["Ion Coating"]        = func(p): await power_ecard2_ion_coating(p)
	_power_dispatch["Magnetic Flow"]      = func(p): await power_ecard2_magnetic_flow(p)
	_power_dispatch["Earth Rage"]         = func(p): await power_ecard2_earth_rage(p)
	_power_dispatch["Backup"]             = func(p): await power_ecard2_backup(p)
	_power_dispatch["Strange Tentacles"]  = func(p): await power_ecard2_strange_tentacles(p)
	_power_dispatch["Miracle Shift"]      = func(p): await power_ecard2_miracle_shift(p)
	_power_dispatch["Dark Moon"]          = func(p): await power_ecard2_dark_moon(p)
	_power_dispatch["Fragrance Trap"]     = func(p): await power_ecard2_fragrance_trap(p)
	_power_dispatch["Scavenger Hunt"]     = func(p): await power_ecard2_scavenger_hunt(p)
	_power_dispatch["Apricorn Forest"]    = func(p): await main.trainer_effects.apricorn_forest_activate(false)
	_power_dispatch["Undersea Ruins"]     = func(p): await main.trainer_effects.undersea_ruins_activate(false)
	_power_dispatch["Power Plant"]        = func(p): await main.trainer_effects.power_plant_activate(false)
	_power_dispatch["Ancient Ruins"]      = func(p): await main.trainer_effects.ancient_ruins_activate(false)
	_power_dispatch["Mystery Zone"]       = func(p): await main.trainer_effects.mystery_zone_activate(false)
	_power_dispatch["Underground Lake"]   = func(p): await main.trainer_effects.underground_lake_activate(false)
	# Extreme Speed/Heavyweight/Lightweight/Conductive Body/Gluey Slime (retreat cost),
	# Pure Body/Poison Resistance/Anti-Lightning (attach/status blocks), Dense Body/Energy Barrier
	# (damage reduction), Fluff (on-damage), Suction Cups (on-retreat), Enervating Pollen
	# (resistance), and Crystal Type are all Poké-Bodies — handled passively via hooks, not dispatch.

# BUBBLE TURN (Azumarill): once per turn, if on Bench, flip; heads return self + attachments to hand
func power_ecard2_bubble_turn(azumarill: card_object) -> void:
	var is_opponent = azumarill.is_owner_opp(main)
	if is_power_blocked_by_status(azumarill):
		await main.show_message("BUBBLE TURN IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if azumarill.power_used_this_turn:
		await main.show_message("BUBBLE TURN ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if azumarill not in bench:
		await main.show_message("BUBBLE TURN REQUIRES AZUMARILL TO BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	azumarill.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! BUBBLE TURN HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	for e in azumarill.attached_energies.duplicate():
		e.current_location = "hand"
		hand.append(e)
	azumarill.attached_energies.clear()
	for ac in azumarill.attached_cards.duplicate():
		ac.current_location = "hand"
		hand.append(ac)
	azumarill.attached_cards.clear()
	bench.erase(azumarill)
	main.clear_all_statuses(azumarill, is_opponent)
	azumarill.current_location = "hand"
	hand.append(azumarill)
	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEADS! AZUMARILL AND ITS CARDS RETURNED TO HAND!")
	if main._should_bail(): return
	print("POWER USED: Bubble Turn")

# FLOWER SUPPLEMENT (Bellossom): once per turn, flip; heads attach 1 basic Energy from hand to a Benched Pokemon
func power_ecard2_flower_supplement(bellossom: card_object) -> void:
	var is_opponent = bellossom.is_owner_opp(main)
	if is_power_blocked_by_status(bellossom):
		await main.show_message("FLOWER SUPPLEMENT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if bellossom.power_used_this_turn:
		await main.show_message("FLOWER SUPPLEMENT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.is_empty():
		await main.show_message("NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if basics.is_empty():
		await main.show_message("NO BASIC ENERGY IN HAND!")
		if main._should_bail(): return
		return
	bellossom.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! FLOWER SUPPLEMENT HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var energy: card_object = basics[0]
	var target: card_object = bench[0]
	if not is_opponent:
		if basics.size() > 1:
			energy = await main.card_ops.prompt_select_card(basics, "FLOWER SUPPLEMENT", "Select a basic Energy to attach", "SELECT", false)
			if main._should_bail(): return
			if energy == null: return
		if bench.size() > 1:
			target = await main.card_ops.prompt_select_card(bench, "FLOWER SUPPLEMENT", "Select a Benched Pokemon to attach it to", "ATTACH", false)
			if main._should_bail(): return
			if target == null: return
	hand.erase(energy)
	energy.current_location = "bench"
	target.attached_energies.append(energy)
	main.refresh_hand_display(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("HEADS! " + energy.metadata.get("name","").to_upper() + " ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Flower Supplement")

# HAPPY HEALING (Blissey): once per turn, choose a Benched Pokemon, flip; heads heal it by Blissey's own Energy count
func power_ecard2_happy_healing(blissey: card_object) -> void:
	var is_opponent = blissey.is_owner_opp(main)
	if is_power_blocked_by_status(blissey):
		await main.show_message("HAPPY HEALING IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if blissey.power_used_this_turn:
		await main.show_message("HAPPY HEALING ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.is_empty():
		await main.show_message("NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	var target: card_object = bench[0]
	if not is_opponent and bench.size() > 1:
		target = await main.card_ops.prompt_select_card(bench, "HAPPY HEALING", "Select a Benched Pokemon to heal", "SELECT", false)
		if main._should_bail(): return
		if target == null: return
	blissey.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! HAPPY HEALING HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var heal = blissey.attached_energies.size() * 10
	if heal > 0:
		await main.card_ops.heal_pokemon(target, heal, is_opponent)
		if main._should_bail(): return
	await main.show_message("HEADS! HEALED " + str(heal) + " HP FROM " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Happy Healing")

# SUPER DYNAMO (Electrode): once per turn if Active, flip; heads attach a Lightning Energy from discard to any own Pokemon
func power_ecard2_super_dynamo(electrode: card_object) -> void:
	var is_opponent = electrode.is_owner_opp(main)
	if is_power_blocked_by_status(electrode):
		await main.show_message("SUPER DYNAMO IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if electrode.power_used_this_turn:
		await main.show_message("SUPER DYNAMO ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != electrode:
		await main.show_message("SUPER DYNAMO REQUIRES ELECTRODE TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var lightning_e = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Lightning" in main.get_energy_provided_by_card(c))
	if lightning_e.is_empty():
		await main.show_message("NO LIGHTNING ENERGY IN DISCARD PILE!")
		if main._should_bail(): return
		return
	electrode.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! SUPER DYNAMO HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var all_own = build_field_pokemon_array_ecard2(is_opponent)
	var energy: card_object = lightning_e[0]
	var target: card_object = electrode
	if not is_opponent:
		if lightning_e.size() > 1:
			energy = await main.card_ops.prompt_select_card(lightning_e, "SUPER DYNAMO", "Select a Lightning Energy to attach", "SELECT", false, true)
			if main._should_bail(): return
			if energy == null: return
		target = await main.card_ops.prompt_select_card(all_own, "SUPER DYNAMO", "Select a Pokemon to attach it to", "ATTACH", false)
		if main._should_bail(): return
		if target == null: return
	discard.erase(energy)
	energy.current_location = "active" if target.current_location == "active" else "bench"
	target.attached_energies.append(energy)
	main.update_discard_pile_display(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("HEADS! " + energy.metadata.get("name","").to_upper() + " ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Super Dynamo")

# ENERGY RETURN (Espeon): repeatable, return an Energy attached to any own Pokemon to hand
func power_ecard2_energy_return(espeon: card_object) -> void:
	var is_opponent = espeon.is_owner_opp(main)
	if is_power_blocked_by_status(espeon):
		await main.show_message("ENERGY RETURN IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var keep_going = true
	while keep_going:
		var all_own = build_field_pokemon_array_ecard2(is_opponent)
		var sources = all_own.filter(func(p): return p.attached_energies.size() > 0)
		if sources.is_empty():
			if not is_opponent:
				await main.show_message("NO ENERGY TO RETURN!")
				if main._should_bail(): return
			break
		var source: card_object = null
		if is_opponent:
			source = sources[0]
		else:
			source = await main.card_ops.prompt_select_card(sources, "ENERGY RETURN", "Select a Pokemon to return Energy from (cancel to stop)", "SELECT", true)
			if main._should_bail(): return
		if source == null: break
		var energy: card_object = null
		if is_opponent:
			energy = source.attached_energies[0]
		else:
			energy = await main.card_ops.prompt_select_card(source.attached_energies, "ENERGY RETURN", "Select the Energy to return", "SELECT", true)
			if main._should_bail(): return
		if energy == null: break
		source.attached_energies.erase(energy)
		energy.current_location = "hand"
		hand.append(energy)
		main.refresh_hand_display(is_opponent)
		main.display_pokemon(is_opponent)
		main.display_active_pokemon_energies(is_opponent)
		await main.show_message("ENERGY RETURN! " + energy.metadata.get("name","").to_upper() + " RETURNED TO HAND!")
		if main._should_bail(): return
		if is_opponent:
			keep_going = false
	print("POWER USED: Energy Return")

# SLEEP PENDULUM (Hypno): once per turn, if Active, make the Defending Pokemon Asleep (no flip)
func power_ecard2_sleep_pendulum(hypno: card_object) -> void:
	var is_opponent = hypno.is_owner_opp(main)
	if is_power_blocked_by_status(hypno):
		await main.show_message("SLEEP PENDULUM IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if hypno.power_used_this_turn:
		await main.show_message("SLEEP PENDULUM ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != hypno:
		await main.show_message("SLEEP PENDULUM REQUIRES HYPNO TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender == null: return
	hypno.power_used_this_turn = true
	main.card_ops.apply_status(defender, "Asleep", not is_opponent)
	main.update_status_icons(defender, not is_opponent)
	await main.show_message("SLEEP PENDULUM! DEFENDING POKEMON IS NOW ASLEEP!")
	if main._should_bail(): return
	print("POWER USED: Sleep Pendulum")

# WATER CYCLONE (Kingdra): repeatable, move a Water Energy from Active to a Benched Pokemon
func power_ecard2_water_cyclone(kingdra: card_object) -> void:
	var is_opponent = kingdra.is_owner_opp(main)
	if is_power_blocked_by_status(kingdra):
		await main.show_message("WATER CYCLONE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if active == null or bench.is_empty(): return
	var keep_going = true
	while keep_going:
		var water_e = active.attached_energies.filter(func(e): return "Water" in main.get_energy_provided_by_card(e))
		if water_e.is_empty():
			if not is_opponent:
				await main.show_message("NO WATER ENERGY ON YOUR ACTIVE!")
				if main._should_bail(): return
			break
		var energy: card_object = null
		var target: card_object = null
		if is_opponent:
			energy = water_e[0]
			target = bench[0]
		else:
			energy = await main.card_ops.prompt_select_card(water_e, "WATER CYCLONE", "Select a Water Energy to move (cancel to stop)", "SELECT", true)
			if main._should_bail(): return
			if energy == null: break
			target = await main.card_ops.prompt_select_card(bench, "WATER CYCLONE", "Select a Benched Pokemon to move it to", "MOVE", true)
			if main._should_bail(): return
			if target == null: break
		active.attached_energies.erase(energy)
		target.attached_energies.append(energy)
		main.display_active_pokemon_energies(is_opponent)
		main.display_pokemon(is_opponent)
		await main.show_message("WATER CYCLONE! ENERGY MOVED TO " + target.metadata.get("name","").to_upper() + "!")
		if main._should_bail(): return
		if is_opponent:
			keep_going = false
	print("POWER USED: Water Cyclone")

# ION COATING (Lanturn): once per turn, all Lightning Energy attached to your Active becomes Water for the rest of the turn
func power_ecard2_ion_coating(lanturn: card_object) -> void:
	var is_opponent = lanturn.is_owner_opp(main)
	if is_power_blocked_by_status(lanturn):
		await main.show_message("ION COATING IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if lanturn.power_used_this_turn:
		await main.show_message("ION COATING ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null: return
	lanturn.power_used_this_turn = true
	active.set_effect("ecard2_ion_coating", "end_of_own_turn")
	await main.show_message("ION COATING! ALL LIGHTNING ENERGY ON YOUR ACTIVE COUNTS AS WATER THIS TURN!")
	if main._should_bail(): return
	print("POWER USED: Ion Coating")

# MAGNETIC FLOW (Magneton): once per turn if Active, flip; heads swap 1 energy card between 2 chosen opponent Pokemon
func power_ecard2_magnetic_flow(magneton: card_object) -> void:
	var is_opponent = magneton.is_owner_opp(main)
	if is_power_blocked_by_status(magneton):
		await main.show_message("MAGNETIC FLOW IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if magneton.power_used_this_turn:
		await main.show_message("MAGNETIC FLOW ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != magneton:
		await main.show_message("MAGNETIC FLOW REQUIRES MAGNETON TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_field: Array = []
	if opp_active != null: opp_field.append(opp_active)
	opp_field.append_array(opp_bench)
	var with_energy = opp_field.filter(func(p): return p.attached_energies.size() > 0)
	if with_energy.size() < 2:
		await main.show_message("OPPONENT NEEDS 2 POKEMON WITH ENERGY!")
		if main._should_bail(): return
		return
	magneton.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! MAGNETIC FLOW HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var pokemon_a: card_object = with_energy[0]
	var pokemon_b: card_object = with_energy[1]
	if not is_opponent:
		pokemon_a = await main.card_ops.prompt_select_card(with_energy, "MAGNETIC FLOW", "Select the first Pokemon", "SELECT", false)
		if main._should_bail(): return
		if pokemon_a == null: return
		var remaining = with_energy.filter(func(p): return p != pokemon_a)
		pokemon_b = await main.card_ops.prompt_select_card(remaining, "MAGNETIC FLOW", "Select the second Pokemon", "SELECT", false)
		if main._should_bail(): return
		if pokemon_b == null: return
	var energy_a = pokemon_a.attached_energies[0]
	var energy_b = pokemon_b.attached_energies[0]
	pokemon_a.attached_energies.erase(energy_a)
	pokemon_b.attached_energies.erase(energy_b)
	pokemon_a.attached_energies.append(energy_b)
	pokemon_b.attached_energies.append(energy_a)
	main.display_pokemon(not is_opponent)
	main.display_active_pokemon_energies(not is_opponent)
	await main.show_message("HEADS! ENERGY SWAPPED BETWEEN " + pokemon_a.metadata.get("name","").to_upper() + " AND " + pokemon_b.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Magnetic Flow")

# EARTH RAGE (Nidoking): once per turn if Active, flip; heads put a damage counter on EACH opponent Benched Pokemon
func power_ecard2_earth_rage(nidoking: card_object) -> void:
	var is_opponent = nidoking.is_owner_opp(main)
	if is_power_blocked_by_status(nidoking):
		await main.show_message("EARTH RAGE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if nidoking.power_used_this_turn:
		await main.show_message("EARTH RAGE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != nidoking:
		await main.show_message("EARTH RAGE REQUIRES NIDOKING TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.show_message("OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	nidoking.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! EARTH RAGE HAD NO EFFECT!")
		if main._should_bail(): return
		return
	for bp in opp_bench:
		main.card_ops.apply_bench_damage(bp, 10, not is_opponent)
	await main.show_message("HEADS! A DAMAGE COUNTER WAS PUT ON EACH OF OPPONENT'S BENCHED POKEMON!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Earth Rage")

# BACKUP (Porygon2): once per turn, if 2 or fewer cards in hand, draw until you have 3
func power_ecard2_backup(porygon2: card_object) -> void:
	var is_opponent = porygon2.is_owner_opp(main)
	if is_power_blocked_by_status(porygon2):
		await main.show_message("BACKUP IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if porygon2.power_used_this_turn:
		await main.show_message("BACKUP ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.size() > 2:
		await main.show_message("YOU HAVE MORE THAN 2 CARDS IN HAND!")
		if main._should_bail(): return
		return
	porygon2.power_used_this_turn = true
	var to_draw = 3 - hand.size()
	if to_draw > 0:
		await main.card_ops.draw_n(is_opponent, to_draw)
		if main._should_bail(): return
	await main.show_message("BACKUP! DREW UP TO 3 CARDS IN HAND!")
	if main._should_bail(): return
	print("POWER USED: Backup")

# STRANGE TENTACLES (Tentacruel): once per turn, if Defending has less Energy than your Active,
# may take an Energy from opponent's discard and attach it to the Defending Pokemon
func power_ecard2_strange_tentacles(tentacruel: card_object) -> void:
	var is_opponent = tentacruel.is_owner_opp(main)
	if is_power_blocked_by_status(tentacruel):
		await main.show_message("STRANGE TENTACLES IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if tentacruel.power_used_this_turn:
		await main.show_message("STRANGE TENTACLES ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if own_active == null or defender == null: return
	if defender.attached_energies.size() >= own_active.attached_energies.size():
		await main.show_message("DEFENDING POKEMON DOESN'T HAVE LESS ENERGY THAN YOUR ACTIVE!")
		if main._should_bail(): return
		return
	var opp_discard = main.player_discard_pile if is_opponent else main.opponent_discard_pile
	var candidates = opp_discard.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if candidates.is_empty():
		await main.show_message("NO ENERGY IN OPPONENT'S DISCARD PILE!")
		if main._should_bail(): return
		return
	var chosen: card_object = candidates[0]
	if not is_opponent and candidates.size() > 1:
		chosen = await main.card_ops.prompt_select_card(candidates, "STRANGE TENTACLES", "Select an Energy to attach to the Defending Pokemon (optional)", "ATTACH", true)
		if main._should_bail(): return
		if chosen == null: return
	tentacruel.power_used_this_turn = true
	opp_discard.erase(chosen)
	chosen.current_location = "active"
	defender.attached_energies.append(chosen)
	main.display_pokemon(not is_opponent)
	main.display_active_pokemon_energies(not is_opponent)
	main.update_discard_pile_display(not is_opponent)
	await main.show_message("STRANGE TENTACLES! " + chosen.metadata.get("name","").to_upper() + " ATTACHED TO THE DEFENDING POKEMON!")
	if main._should_bail(): return
	print("POWER USED: Strange Tentacles")

# MIRACLE SHIFT (Togetic): once per turn, discard a basic Energy from own Pokemon, then attach a
# basic Energy from discard to that same Pokemon
func power_ecard2_miracle_shift(togetic: card_object) -> void:
	var is_opponent = togetic.is_owner_opp(main)
	if is_power_blocked_by_status(togetic):
		await main.show_message("MIRACLE SHIFT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if togetic.power_used_this_turn:
		await main.show_message("MIRACLE SHIFT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var all_own = build_field_pokemon_array_ecard2(is_opponent)
	var sources = all_own.filter(func(p): return p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0)
	if sources.is_empty():
		await main.show_message("NO BASIC ENERGY TO DISCARD!")
		if main._should_bail(): return
		return
	var target: card_object = sources[0]
	if not is_opponent and sources.size() > 1:
		target = await main.card_ops.prompt_select_card(sources, "MIRACLE SHIFT", "Select a Pokemon to shift Energy on", "SELECT", false)
		if main._should_bail(): return
		if target == null: return
	var basics = target.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))
	var to_discard: card_object = basics[0]
	if not is_opponent and basics.size() > 1:
		to_discard = await main.card_ops.prompt_select_card(basics, "MIRACLE SHIFT", "Select the Energy to discard", "DISCARD", false)
		if main._should_bail(): return
		if to_discard == null: return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var discard_basics_before = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	togetic.power_used_this_turn = true
	main.card_ops.discard_energy_from_pokemon(to_discard, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	if discard_basics_before.is_empty():
		await main.show_message("NO OTHER BASIC ENERGY IN DISCARD TO ATTACH!")
		if main._should_bail(): return
		return
	var new_energy: card_object = discard_basics_before[0]
	if not is_opponent and discard_basics_before.size() > 1:
		new_energy = await main.card_ops.prompt_select_card(discard_basics_before, "MIRACLE SHIFT", "Select a basic Energy to attach", "ATTACH", false, true)
		if main._should_bail(): return
		if new_energy == null: return
	discard.erase(new_energy)
	new_energy.current_location = target.current_location
	target.attached_energies.append(new_energy)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("MIRACLE SHIFT! " + new_energy.metadata.get("name","").to_upper() + " ATTACHED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Miracle Shift")

# DARK MOON (Umbreon): while Active with Darkness Energy attached, once per turn, look at
# opponent's hand and shuffle up to (Darkness Energy count) cards into their deck; they draw that many
func power_ecard2_dark_moon(umbreon: card_object) -> void:
	var is_opponent = umbreon.is_owner_opp(main)
	if is_power_blocked_by_status(umbreon):
		await main.show_message("DARK MOON IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if umbreon.power_used_this_turn:
		await main.show_message("DARK MOON ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active != umbreon:
		await main.show_message("DARK MOON REQUIRES UMBREON TO BE ACTIVE!")
		if main._should_bail(): return
		return
	var darkness_count = 0
	for e in umbreon.attached_energies:
		if "Darkness" in main.get_energy_provided_by_card(e): darkness_count += 1
	if darkness_count <= 0:
		await main.show_message("DARK MOON REQUIRES A DARKNESS ENERGY ATTACHED!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	if opp_hand.is_empty():
		await main.show_message("OPPONENT HAS NO CARDS IN HAND!")
		if main._should_bail(): return
		return
	umbreon.power_used_this_turn = true
	var want = min(darkness_count, opp_hand.size())
	var chosen: Array = []
	if is_opponent:
		for i in range(want): chosen.append(opp_hand[i])
	else:
		for i in range(want):
			var pool = opp_hand.filter(func(c): return c not in chosen)
			if pool.is_empty(): break
			var pick = await main.card_ops.prompt_select_card(pool, "DARK MOON", "Choose a card from opponent's hand to shuffle away (" + str(want - chosen.size()) + " remaining, cancel to stop)", "SELECT", true, true)
			if main._should_bail(): return
			if pick == null: break
			chosen.append(pick)
	for c in chosen:
		opp_hand.erase(c)
		c.current_location = "deck"
		opp_deck.append(c)
	opp_deck.shuffle()
	main.refresh_hand_display(not is_opponent)
	main.update_deck_icon(not is_opponent)
	if chosen.size() > 0:
		await main.card_ops.draw_n(not is_opponent, chosen.size())
		if main._should_bail(): return
	await main.show_message("DARK MOON! SHUFFLED " + str(chosen.size()) + " CARD(S) FROM OPPONENT'S HAND!")
	if main._should_bail(): return
	print("POWER USED: Dark Moon")

# FRAGRANCE TRAP (Victreebel): once per turn, flip; heads choose opponent Benched Pokemon, switch it with the Defending Pokemon
func power_ecard2_fragrance_trap(victreebel: card_object) -> void:
	var is_opponent = victreebel.is_owner_opp(main)
	if is_power_blocked_by_status(victreebel):
		await main.show_message("FRAGRANCE TRAP IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if victreebel.power_used_this_turn:
		await main.show_message("FRAGRANCE TRAP ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if opp_bench.is_empty() or opp_active == null:
		await main.show_message("OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	victreebel.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! FRAGRANCE TRAP HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var chosen: card_object = opp_bench[0]
	if not is_opponent and opp_bench.size() > 1:
		chosen = await main.card_ops.prompt_select_card(opp_bench, "FRAGRANCE TRAP", "Choose an opponent Benched Pokemon to switch in", "SWITCH", false)
		if main._should_bail(): return
		if chosen == null: return
	opp_bench.erase(chosen)
	opp_bench.append(opp_active)
	opp_active.current_location = "bench"
	chosen.current_location = "active"
	if is_opponent:
		main.player_active_pokemon = chosen
	else:
		main.opponent_active_pokemon = chosen
	await main.animate_retreat(opp_active, chosen, [], not is_opponent)
	if main._should_bail(): return
	main.clear_all_statuses(opp_active, not is_opponent)
	main.display_pokemon(not is_opponent)
	main.display_active_pokemon_energies(not is_opponent)
	await main.show_message("HEADS! " + chosen.metadata.get("name","").to_upper() + " SWITCHED IN!")
	if main._should_bail(): return
	print("POWER USED: Fragrance Trap")

# SCAVENGER HUNT (Furret): once per turn, put 2 hand cards into deck, then search deck for an Energy card to hand
func power_ecard2_scavenger_hunt(furret: card_object) -> void:
	var is_opponent = furret.is_owner_opp(main)
	if is_power_blocked_by_status(furret):
		await main.show_message("SCAVENGER HUNT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if furret.power_used_this_turn:
		await main.show_message("SCAVENGER HUNT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	if hand.size() < 2:
		await main.show_message("NOT ENOUGH CARDS IN HAND!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var to_deck: Array = []
	if is_opponent:
		to_deck = cpu_get_discard_priority_ecard2(hand, 2)
	else:
		await main.trainer_effects.player_select_cards_to_discard(hand, 2, "SCAVENGER HUNT", "Select 2 cards to put into your deck")
		if main._should_bail(): return
		to_deck = main.trainer_discard_selected.duplicate()
		main.trainer_discard_selected.clear()
	furret.power_used_this_turn = true
	for c in to_deck:
		hand.erase(c)
		c.current_location = "deck"
		deck.append(c)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	var energies = deck.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if energies.is_empty():
		await main.show_message("SCAVENGER HUNT! NO ENERGY CARDS IN DECK!")
		if main._should_bail(): return
		return
	var chosen: card_object = energies[0]
	if not is_opponent and energies.size() > 1:
		chosen = await main.card_ops.prompt_select_card(energies, "SCAVENGER HUNT", "Select an Energy card to add to hand", "SELECT", false, true)
		if main._should_bail(): return
		if chosen == null: return
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("SCAVENGER HUNT! ADDED " + chosen.metadata.get("name","").to_upper() + " TO HAND!")
	if main._should_bail(): return
	print("POWER USED: Scavenger Hunt")

# ── Small shared helpers for ecard2 ──────────────────────────────────────────────

# Same shape as build_field_pokemon_array (Trainer_Effects.gd) — local copy avoids a cross-script
# call for a trivial array build used repeatedly above.
func build_field_pokemon_array_ecard2(is_opponent: bool) -> Array:
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var result: Array = []
	if active != null: result.append(active)
	result.append_array(bench)
	return result

# Simple CPU discard-priority fallback for Scavenger Hunt (lowest-value-first), mirroring the
# general spirit of Trainer_Effects.cpu_get_discard_priority without depending on its internals.
func cpu_get_discard_priority_ecard2(hand: Array, count: int) -> Array:
	var pool = hand.duplicate()
	pool.sort_custom(func(a, b): return a.metadata.get("supertype","") == "Energy" and b.metadata.get("supertype","") != "Energy")
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result

# ── Passive Poké-Body helpers ─────────────────────────────────────────────────────

# ANTI-LIGHTNING (Zapdos): can't attach Lightning Energy from hand to Zapdos. Returns true if blocked.
func check_anti_lightning_block(energy_card: card_object, target_pokemon: card_object) -> bool:
	if target_pokemon == null: return false
	if is_power_blocked(target_pokemon): return false
	if not target_pokemon.has_ability("Anti-Lightning"): return false
	var energy_name = energy_card.metadata.get("name", "")
	var provided = main.special_energy_effects.get_energy_types_provided(energy_name)
	if provided.is_empty():
		provided = energy_card.metadata.get("types", [])
	return "Lightning" in provided

# ECARD3 Water Immunity (Articuno) / Fire Immunity (Moltres): can't attach that type of Energy
# from hand. Ability name maps directly to the guarded type.
const _TYPE_IMMUNITY_BODY_NAMES := {"Water Immunity": "Water", "Fire Immunity": "Fire"}
func check_ecard3_type_immunity_block(energy_card: card_object, target_pokemon: card_object) -> bool:
	if target_pokemon == null: return false
	if is_power_blocked(target_pokemon): return false
	var guarded_type = ""
	for ab_name in _TYPE_IMMUNITY_BODY_NAMES:
		if target_pokemon.has_ability(ab_name):
			guarded_type = _TYPE_IMMUNITY_BODY_NAMES[ab_name]
			break
	if guarded_type == "": return false
	var energy_name = energy_card.metadata.get("name", "")
	var provided = main.special_energy_effects.get_energy_types_provided(energy_name)
	if provided.is_empty():
		provided = energy_card.metadata.get("types", [])
	return guarded_type in provided

# SUCTION CUPS (Octillery): while Active, when the Defending Pokemon retreats, discard all its
# Energy cards as it goes to the Bench. Called right after a retreat completes on the retreating side.
func check_suction_cups(retreating_pokemon: card_object, retreating_is_opponent: bool) -> void:
	if retreating_pokemon == null: return
	var opposing_active = main.player_active_pokemon if retreating_is_opponent else main.opponent_active_pokemon
	if opposing_active == null: return
	if not opposing_active.has_ability("Suction Cups"): return
	if is_power_blocked(opposing_active): return
	if retreating_pokemon.attached_energies.is_empty(): return
	var discard = main.opponent_discard_pile if retreating_is_opponent else main.player_discard_pile
	for e in retreating_pokemon.attached_energies.duplicate():
		retreating_pokemon.attached_energies.erase(e)
		e.current_location = "discard"
		discard.append(e)
	main.display_active_pokemon_energies(retreating_is_opponent)
	main.update_discard_pile_display(retreating_is_opponent)
	print("SUCTION CUPS: discarded retreating ", retreating_pokemon.metadata.get("name",""), "'s energy")

# FLUFF (Jumpluff): during the opponent's turn, if Jumpluff already had a damage counter BEFORE
# this attack landed, flip a coin — heads retroactively heals back the damage this hit just did.
# Simplification: the hook system fires after damage is already applied and can't intercept
# non-damage effects (status, energy discard, etc.) from the same attack, so this undoes the HP
# loss but not any other simultaneous effect — a close approximation of "prevent all effects."
func check_ecard2_fluff(defender: card_object, attacker: card_object, damage: int, is_def_opp: bool) -> void:
	if damage <= 0: return
	if defender == null: return
	if not defender.has_ability("Fluff"): return
	if is_power_blocked(defender): return
	if defender != (main.opponent_active_pokemon if is_def_opp else main.player_active_pokemon): return
	var pre_hit_damage_taken = (defender.get_max_hp() - defender.current_hp) - damage
	if pre_hit_damage_taken < 10: return
	var coin = await main.flip_coin(false, is_def_opp)
	if main._should_bail(): return
	if not coin: return
	defender.current_hp = min(defender.get_max_hp(), defender.current_hp + damage)
	main.display_hp_circles_above_align(defender, is_def_opp)
	await main.show_message("FLUFF! HEADS — THE ATTACK'S DAMAGE WAS PREVENTED!")
	if main._should_bail(): return
	print("BODY: Fluff prevented ", damage, " damage on ", defender.metadata.get("name",""))

# ENERVATING POLLEN (Gloom): true if any Gloom is in play (either side) with its Body active
func is_enervating_pollen_active() -> bool:
	var all_field: Array = []
	if main.player_active_pokemon != null: all_field.append(main.player_active_pokemon)
	all_field.append_array(main.player_bench)
	if main.opponent_active_pokemon != null: all_field.append(main.opponent_active_pokemon)
	all_field.append_array(main.opponent_bench)
	for p in all_field:
		if p.metadata.get("name", "") == "Gloom" and not is_power_blocked(p):
			return true
	return false

# CPU phase for ECARD2 active powers
func cpu_phase_ecard2_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var bubble_turn = _find_cpu_bench_pokemon_with_power("Bubble Turn")
	if bubble_turn != null and not bubble_turn.power_used_this_turn and not is_power_blocked_by_status(bubble_turn):
		# Only worth retreating to hand if it's significantly damaged (protect the investment)
		if bubble_turn.current_hp < bubble_turn.get_max_hp() * 0.4:
			await power_ecard2_bubble_turn(bubble_turn)
			if main._should_bail(): return

	var flower_supplement = _find_cpu_pokemon_with_power("Flower Supplement")
	if flower_supplement != null and not flower_supplement.power_used_this_turn and not is_power_blocked_by_status(flower_supplement):
		if main.opponent_bench.size() > 0 and main.opponent_hand.any(func(c): return main.attack_effects.gym1_is_basic_energy(c)):
			await power_ecard2_flower_supplement(flower_supplement)
			if main._should_bail(): return

	var happy_healing = _find_cpu_pokemon_with_power("Happy Healing")
	if happy_healing != null and not happy_healing.power_used_this_turn and not is_power_blocked_by_status(happy_healing):
		var damaged_bench = main.opponent_bench.filter(func(p): return p.current_hp < p.get_max_hp())
		if damaged_bench.size() > 0 and happy_healing.attached_energies.size() > 0:
			await power_ecard2_happy_healing(happy_healing)
			if main._should_bail(): return

	var super_dynamo = _find_cpu_pokemon_with_power("Super Dynamo")
	if super_dynamo != null and super_dynamo == main.opponent_active_pokemon and not super_dynamo.power_used_this_turn and not is_power_blocked_by_status(super_dynamo):
		await power_ecard2_super_dynamo(super_dynamo)
		if main._should_bail(): return

	var energy_return = _find_cpu_pokemon_with_power("Energy Return")
	if energy_return != null and not is_power_blocked_by_status(energy_return):
		# Only pull energy back if it's from a heavily-damaged Pokemon worth abandoning
		var worth_it = false
		for p in build_field_pokemon_array_ecard2(true):
			if p.attached_energies.size() > 0 and p.current_hp < p.get_max_hp() * 0.3:
				worth_it = true
				break
		if worth_it:
			await power_ecard2_energy_return(energy_return)
			if main._should_bail(): return

	var sleep_pendulum = _find_cpu_pokemon_with_power("Sleep Pendulum")
	if sleep_pendulum != null and sleep_pendulum == main.opponent_active_pokemon and not sleep_pendulum.power_used_this_turn and not is_power_blocked_by_status(sleep_pendulum):
		if main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "":
			await power_ecard2_sleep_pendulum(sleep_pendulum)
			if main._should_bail(): return

	var water_cyclone = _find_cpu_pokemon_with_power("Water Cyclone")
	if water_cyclone != null and water_cyclone == main.opponent_active_pokemon and not is_power_blocked_by_status(water_cyclone):
		if water_cyclone.current_hp < water_cyclone.get_max_hp() * 0.3 and main.opponent_bench.size() > 0:
			await power_ecard2_water_cyclone(water_cyclone)
			if main._should_bail(): return

	var ion_coating = _find_cpu_pokemon_with_power("Ion Coating")
	if ion_coating != null and ion_coating == main.opponent_active_pokemon and not ion_coating.power_used_this_turn and not is_power_blocked_by_status(ion_coating):
		var needs_water = false
		for atk in ion_coating.metadata.get("attacks", []):
			if "Water" in atk.get("cost", []) and main.cpu_ai.get_unmet_energy_count(atk, ion_coating) > 0:
				needs_water = true
				break
		if needs_water:
			await power_ecard2_ion_coating(ion_coating)
			if main._should_bail(): return

	var magnetic_flow = _find_cpu_pokemon_with_power("Magnetic Flow")
	if magnetic_flow != null and magnetic_flow == main.opponent_active_pokemon and not magnetic_flow.power_used_this_turn and not is_power_blocked_by_status(magnetic_flow):
		await power_ecard2_magnetic_flow(magnetic_flow)
		if main._should_bail(): return

	var earth_rage = _find_cpu_pokemon_with_power("Earth Rage")
	if earth_rage != null and earth_rage == main.opponent_active_pokemon and not earth_rage.power_used_this_turn and not is_power_blocked_by_status(earth_rage):
		if main.player_bench.size() > 0:
			await power_ecard2_earth_rage(earth_rage)
			if main._should_bail(): return

	var backup = _find_cpu_pokemon_with_power("Backup")
	if backup != null and not backup.power_used_this_turn and not is_power_blocked_by_status(backup):
		if main.opponent_hand.size() <= 2:
			await power_ecard2_backup(backup)
			if main._should_bail(): return

	var strange_tentacles = _find_cpu_pokemon_with_power("Strange Tentacles")
	if strange_tentacles != null and not strange_tentacles.power_used_this_turn and not is_power_blocked_by_status(strange_tentacles):
		await power_ecard2_strange_tentacles(strange_tentacles)
		if main._should_bail(): return

	var miracle_shift = _find_cpu_pokemon_with_power("Miracle Shift")
	if miracle_shift != null and not miracle_shift.power_used_this_turn and not is_power_blocked_by_status(miracle_shift):
		var has_diff_energy = main.opponent_discard_pile.any(func(c): return main.attack_effects.gym1_is_basic_energy(c))
		if has_diff_energy:
			await power_ecard2_miracle_shift(miracle_shift)
			if main._should_bail(): return

	var dark_moon = _find_cpu_pokemon_with_power("Dark Moon")
	if dark_moon != null and dark_moon == main.opponent_active_pokemon and not dark_moon.power_used_this_turn and not is_power_blocked_by_status(dark_moon):
		if main.player_hand.size() > 0:
			await power_ecard2_dark_moon(dark_moon)
			if main._should_bail(): return

	var fragrance_trap = _find_cpu_pokemon_with_power("Fragrance Trap")
	if fragrance_trap != null and not fragrance_trap.power_used_this_turn and not is_power_blocked_by_status(fragrance_trap):
		if main.player_bench.size() > 0:
			await power_ecard2_fragrance_trap(fragrance_trap)
			if main._should_bail(): return

	var scavenger_hunt = _find_cpu_pokemon_with_power("Scavenger Hunt")
	if scavenger_hunt != null and not scavenger_hunt.power_used_this_turn and not is_power_blocked_by_status(scavenger_hunt):
		if main.opponent_hand.size() >= 2:
			await power_ecard2_scavenger_hunt(scavenger_hunt)
			if main._should_bail(): return

# CRYSTAL TYPE (ecard2 Kingdra/Lugia/Nidoking, ecard3 Celebi/Charizard/Crobat/Golem/Ho-oh/Kabutops):
# whenever a matching-type basic Energy is attached from hand, the holder's type (color) becomes
# that Energy's type until the end of the holder's own turn. Eligible types are per-card (from
# each card's own printed ability text) — kept as a lookup here since they don't follow a
# derivable pattern. The actual effect lives in card_object.get_effective_types(), consulted by
# Main's calculate_final_damage for Weakness-triggering and by any type-restricted effect that
# calls get_effective_types() instead of reading metadata.types directly.
const CRYSTAL_TYPE_ELIGIBLE := {
	"Kingdra": ["Water", "Lightning", "Psychic"],
	"Lugia": ["Fire", "Water", "Psychic"],
	"Nidoking": ["Grass", "Lightning", "Fire"],
	"Celebi": ["Grass", "Water", "Psychic"],
	"Charizard": ["Fire", "Lightning", "Fighting"],
	"Crobat": ["Grass", "Fire", "Psychic"],
	"Golem": ["Grass", "Fire", "Fighting"],
	"Ho-oh": ["Fire", "Water", "Lightning"],
	"Kabutops": ["Water", "Lightning", "Fighting"],
}

func check_crystal_type_attach(target_pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	if target_pokemon == null: return
	if is_power_blocked(target_pokemon): return
	if not target_pokemon.has_ability("Crystal Type"): return
	var pname = target_pokemon.metadata.get("name", "")
	if not CRYSTAL_TYPE_ELIGIBLE.has(pname): return
	if not main.attack_effects.gym1_is_basic_energy(energy_card): return
	var energy_type = main.get_energy_provided_by_card(energy_card)
	var eligible = CRYSTAL_TYPE_ELIGIBLE[pname]
	var matched = ""
	for t in energy_type:
		if t in eligible:
			matched = t
			break
	if matched == "": return
	target_pokemon.set_effect("crystal_type_active", "end_of_own_turn", matched)
	print("CRYSTAL TYPE: ", pname, " is now ", matched, " until end of turn")

######################################################################################################################################################
######################################################### ECARD3 (SKYRIDGE) POWERS/BODIES #############################################################
######################################################################################################################################################

func _register_ecard3_powers() -> void:
	_power_dispatch["Ancient Wind"]     = func(p): await power_ecard3_ancient_wind(p)
	_power_dispatch["Energy Jump"]      = func(p): await power_ecard3_energy_jump(p)
	_power_dispatch["Carry Off"]        = func(p): await power_ecard3_carry_off(p)
	_power_dispatch["Evolution Helper"] = func(p): await power_ecard3_evolution_helper(p)
	_power_dispatch["Strange Spiral"]   = func(p): await power_ecard3_strange_spiral(p)
	_power_dispatch["Good Neighbor"]    = func(p): await power_ecard3_good_neighbor(p)
	_power_dispatch["Investigate"]      = func(p): await power_ecard3_investigate(p)
	_power_dispatch["Reconstruction"]   = func(p): await power_ecard3_reconstruction(p)
	_power_dispatch["Lolling About"]    = func(p): await power_ecard3_lolling_about(p)
	# Water Immunity/Fire Immunity (energy-attach blocks), Self-healing (on-attach cure),
	# Primal Aura/Primal Stare (evolution blocks), Immunity (status-application block),
	# Rare Metal/Prismatic Body (CPU energy-pool heuristics), Dark Gaze (bench power block),
	# Synchronicity (no-op — TM attach was never type-restricted for non-Cube TMs), Thick Shell/
	# Exoskeleton/Vase Body (damage-modifier hooks), Mirror Coat (apply_status hook), Psychoflow/
	# Slippery Skin (retreat cost hooks), Pure Body (already generic via own-type matching), and
	# Crystal Type (Celebi already covered by the existing CRYSTAL_TYPE_ELIGIBLE table) are all
	# Poké-Bodies — handled passively via hooks, not dispatch.

# ANCIENT WIND (Aerodactyl): once per turn, if Active, may ignore all Poké-Bodies until end of turn
func power_ecard3_ancient_wind(aerodactyl: card_object) -> void:
	var is_opponent = aerodactyl.is_owner_opp(main)
	if is_power_blocked(aerodactyl, false):
		await main.show_message("ANCIENT WIND IS BLOCKED!")
		if main._should_bail(): return
		return
	if aerodactyl.power_used_this_turn:
		await main.show_message("ANCIENT WIND ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if aerodactyl != active:
		await main.show_message("AERODACTYL MUST BE YOUR ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	aerodactyl.power_used_this_turn = true
	aerodactyl.set_effect("ecard3_ancient_wind_ignore_bodies", "end_of_own_turn")
	await main.show_message("ANCIENT WIND! ALL POKE-BODIES ARE IGNORED UNTIL THE END OF YOUR TURN!")
	if main._should_bail(): return
	print("POWER USED: Ancient Wind")

# ENERGY JUMP (Alakazam): once per turn, move an Energy card from 1 of your Pokemon to another
func power_ecard3_energy_jump(alakazam: card_object) -> void:
	var is_opponent = alakazam.is_owner_opp(main)
	if is_power_blocked(alakazam, false):
		await main.show_message("ENERGY JUMP IS BLOCKED!")
		if main._should_bail(): return
		return
	if alakazam.power_used_this_turn:
		await main.show_message("ENERGY JUMP ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if active != null: all_own.append(active)
	all_own.append_array(bench)
	var sources = all_own.filter(func(p): return p.attached_energies.size() > 0)
	if sources.is_empty():
		await main.show_message("NO ENERGY TO MOVE!")
		if main._should_bail(): return
		return
	var source: card_object = sources[0]
	var energy: card_object = source.attached_energies[0]
	if not is_opponent:
		source = await main.card_ops.prompt_select_card(sources, "ENERGY JUMP", "Select a Pokemon to move Energy from", "SELECT", false)
		if main._should_bail(): return
		if source == null: return
		energy = await main.card_ops.prompt_select_card(source.attached_energies, "ENERGY JUMP", "Select the Energy card to move", "SELECT", false)
		if main._should_bail(): return
		if energy == null: return
	var targets = all_own.filter(func(p): return p != source)
	if targets.is_empty(): return
	var target: card_object = targets[0]
	if not is_opponent and targets.size() > 1:
		target = await main.card_ops.prompt_select_card(targets, "ENERGY JUMP", "Select a Pokemon to move the Energy to", "ATTACH", false)
		if main._should_bail(): return
		if target == null: return
	alakazam.power_used_this_turn = true
	source.attached_energies.erase(energy)
	target.attached_energies.append(energy)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	await main.show_message("ENERGY JUMP! MOVED TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Energy Jump")

# CARRY OFF (Crobat): once per turn, flip; heads look at opponent's hand, choose a Baby/Basic/
# Evolution card there, shuffle it into their deck
func power_ecard3_carry_off(crobat: card_object) -> void:
	var is_opponent = crobat.is_owner_opp(main)
	if is_power_blocked(crobat, false):
		await main.show_message("CARRY OFF IS BLOCKED!")
		if main._should_bail(): return
		return
	if crobat.power_used_this_turn:
		await main.show_message("CARRY OFF ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	crobat.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("CARRY OFF! TAILS — NO EFFECT!")
		if main._should_bail(): return
		return
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	var candidates = opp_hand.filter(func(c): return c.metadata.get("supertype","") == "Pokémon")
	if candidates.is_empty():
		await main.show_message("HEADS! BUT NO POKEMON CARDS IN OPPONENT'S HAND!")
		if main._should_bail(): return
		return
	var chosen: card_object = candidates[0]
	if not is_opponent:
		chosen = await main.card_ops.prompt_select_card(candidates, "CARRY OFF", "Choose a card from your opponent's hand to shuffle into their deck", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: return
	var opp_deck = main.player_deck if is_opponent else main.opponent_deck
	opp_hand.erase(chosen)
	chosen.current_location = "deck"
	opp_deck.append(chosen)
	opp_deck.shuffle()
	main.refresh_hand_display(not is_opponent)
	main.update_deck_icon(not is_opponent)
	await main.show_message("CARRY OFF! " + chosen.metadata.get("name","").to_upper() + " WAS SHUFFLED INTO THE OPPONENT'S DECK!")
	if main._should_bail(): return
	print("POWER USED: Carry Off")

# EVOLUTION HELPER (Nidoqueen): once per turn, if Nidoqueen is on your bench, search deck for a
# card that evolves from your Active and attach it (counts as evolving)
func power_ecard3_evolution_helper(nidoqueen: card_object) -> void:
	var is_opponent = nidoqueen.is_owner_opp(main)
	if is_power_blocked(nidoqueen, false):
		await main.show_message("EVOLUTION HELPER IS BLOCKED!")
		if main._should_bail(): return
		return
	if nidoqueen.power_used_this_turn:
		await main.show_message("EVOLUTION HELPER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if nidoqueen not in bench:
		await main.show_message("NIDOQUEEN MUST BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if active == null:
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var active_name = active.metadata.get("name", "")
	var candidates = deck.filter(func(c): return c.metadata.get("evolvesFrom","") == active_name)
	if candidates.is_empty():
		await main.show_message("NO EVOLUTION CARD FOR " + active_name.to_upper() + " IN DECK!")
		if main._should_bail(): return
		return
	nidoqueen.power_used_this_turn = true
	var evo_card: card_object = candidates[0]
	if not is_opponent and candidates.size() > 1:
		evo_card = await main.card_ops.prompt_select_card(candidates, "EVOLUTION HELPER", "Choose an Evolution card", "EVOLVE", false)
		if main._should_bail(): return
		if evo_card == null: return
	deck.erase(evo_card)
	var max_hp_old = active.get_max_hp()
	var damage_taken = max_hp_old - active.current_hp
	var max_hp_new = int(evo_card.metadata.get("hp", "0"))
	evo_card.current_hp = max(1, max_hp_new - damage_taken)
	evo_card.attached_energies = active.attached_energies.duplicate()
	active.attached_energies.clear()
	evo_card.attached_pre_evolutions = active.attached_pre_evolutions.duplicate()
	active.attached_pre_evolutions.clear()
	evo_card.attached_pre_evolutions.append(active)
	evo_card.placed_on_field_this_turn = true
	evo_card.current_location = "active"
	if is_opponent:
		main.opponent_active_pokemon = evo_card
	else:
		main.player_active_pokemon = evo_card
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("EVOLUTION HELPER! " + active_name.to_upper() + " EVOLVED INTO " + evo_card.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Evolution Helper")

# STRANGE SPIRAL (Poliwrath): once per turn, if Active, may discard a basic Energy attached to
# itself to Confuse the Defending Pokemon
func power_ecard3_strange_spiral(poliwrath: card_object) -> void:
	var is_opponent = poliwrath.is_owner_opp(main)
	if is_power_blocked(poliwrath, false):
		await main.show_message("STRANGE SPIRAL IS BLOCKED!")
		if main._should_bail(): return
		return
	if poliwrath.power_used_this_turn:
		await main.show_message("STRANGE SPIRAL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if poliwrath != active:
		await main.show_message("POLIWRATH MUST BE YOUR ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	var basics = poliwrath.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))
	if basics.is_empty():
		await main.show_message("NO BASIC ENERGY ATTACHED TO DISCARD!")
		if main._should_bail(): return
		return
	var energy: card_object = basics[0]
	if not is_opponent and basics.size() > 1:
		energy = await main.card_ops.prompt_select_card(basics, "STRANGE SPIRAL", "Choose a basic Energy to discard", "DISCARD", false)
		if main._should_bail(): return
		if energy == null: return
	poliwrath.power_used_this_turn = true
	poliwrath.attached_energies.erase(energy)
	main.card_ops.discard_energy_from_pokemon(energy, is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender != null:
		main.card_ops.apply_status(defender, "Confused", not is_opponent)
		main.update_status_icons(defender, not is_opponent)
	await main.show_message("STRANGE SPIRAL! THE DEFENDING POKEMON IS CONFUSED!")
	if main._should_bail(): return
	print("POWER USED: Strange Spiral")

# GOOD NEIGHBOR (Wigglytuff): once per turn, if on your bench, flip; heads each player removes
# up to 2 damage counters from their Active
func power_ecard3_good_neighbor(wigglytuff: card_object) -> void:
	var is_opponent = wigglytuff.is_owner_opp(main)
	if is_power_blocked(wigglytuff, false):
		await main.show_message("GOOD NEIGHBOR IS BLOCKED!")
		if main._should_bail(): return
		return
	if wigglytuff.power_used_this_turn:
		await main.show_message("GOOD NEIGHBOR ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if wigglytuff not in bench:
		await main.show_message("WIGGLYTUFF MUST BE ON YOUR BENCH!")
		if main._should_bail(): return
		return
	wigglytuff.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("GOOD NEIGHBOR! TAILS — NO EFFECT!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var opp_active = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	for entry in [[own_active, is_opponent], [opp_active, not is_opponent]]:
		var p: card_object = entry[0]
		var p_is_opp: bool = entry[1]
		if p != null and p.current_hp < p.get_max_hp():
			var heal = min(20, p.get_max_hp() - p.current_hp)
			await main.card_ops.heal_pokemon(p, heal, p_is_opp)
			if main._should_bail(): return
	await main.show_message("GOOD NEIGHBOR! HEADS — BOTH ACTIVE POKEMON HEALED UP TO 20!")
	if main._should_bail(): return
	print("POWER USED: Good Neighbor")

# INVESTIGATE (Noctowl): once per turn, look at the top 2 cards of any player's deck, or up to 2
# of any player's Prizes; put back in the same order (read-only, informational)
func power_ecard3_investigate(noctowl: card_object) -> void:
	var is_opponent = noctowl.is_owner_opp(main)
	if is_power_blocked(noctowl, false):
		await main.show_message("INVESTIGATE IS BLOCKED!")
		if main._should_bail(): return
		return
	if noctowl.power_used_this_turn:
		await main.show_message("INVESTIGATE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	noctowl.power_used_this_turn = true
	# Simplification: always peeks the OPPONENT's top 2 deck cards (the most information-dense
	# legal choice; Prize-peeking is a strict subset of what this reveals in practice).
	var top_cards = main.card_ops.peek_top_n(is_opponent, 2)
	if is_opponent:
		await main.show_message("INVESTIGATE: OPPONENT LOOKED AT THE TOP OF YOUR DECK!")
		if main._should_bail(): return
	else:
		if top_cards.is_empty():
			await main.show_message("OPPONENT'S DECK IS EMPTY!")
			if main._should_bail(): return
			return
		var names = ""
		for c in top_cards:
			names += c.metadata.get("name","") + "  "
		await main.show_message("INVESTIGATE! TOP OF OPPONENT'S DECK: " + names.to_upper())
		if main._should_bail(): return
	print("POWER USED: Investigate")

# RECONSTRUCTION (Buried Fossil): once per turn, if you have a basic Energy in hand, search deck
# for an Omanyte or Kabuto to hand, then put a basic Energy from hand into the deck and shuffle
func power_ecard3_reconstruction(fossil: card_object) -> void:
	var is_opponent = fossil.is_owner_opp(main)
	if is_power_blocked(fossil, false):
		await main.show_message("RECONSTRUCTION IS BLOCKED!")
		if main._should_bail(): return
		return
	if fossil.power_used_this_turn:
		await main.show_message("RECONSTRUCTION ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var hand_basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
	if hand_basics.is_empty():
		await main.show_message("NO BASIC ENERGY IN HAND!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var candidates = deck.filter(func(c): return c.metadata.get("name","") in ["Omanyte","Kabuto"])
	if candidates.is_empty():
		await main.show_message("NO OMANYTE OR KABUTO IN DECK!")
		if main._should_bail(): return
		return
	fossil.power_used_this_turn = true
	var chosen: card_object = candidates[0]
	if not is_opponent and candidates.size() > 1:
		chosen = await main.card_ops.prompt_select_card(candidates, "RECONSTRUCTION", "Choose Omanyte or Kabuto", "SELECT", false)
		if main._should_bail(): return
		if chosen == null: chosen = candidates[0]
	deck.erase(chosen)
	chosen.current_location = "hand"
	hand.append(chosen)
	hand_basics = hand.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c) and c != chosen)
	var to_return: card_object = hand_basics[0] if hand_basics.size() > 0 else null
	if to_return != null:
		if not is_opponent and hand_basics.size() > 1:
			to_return = await main.card_ops.prompt_select_card(hand_basics, "RECONSTRUCTION", "Choose a basic Energy to put into your deck", "RETURN", false)
			if main._should_bail(): return
			if to_return == null: to_return = hand_basics[0]
		hand.erase(to_return)
		to_return.current_location = "deck"
		deck.append(to_return)
	deck.shuffle()
	main.refresh_hand_display(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("RECONSTRUCTION! FOUND " + chosen.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Reconstruction")

# LOLLING ABOUT (Snorlax): once per turn, if Active, may remove 1 damage counter — Snorlax becomes Asleep
func power_ecard3_lolling_about(snorlax: card_object) -> void:
	var is_opponent = snorlax.is_owner_opp(main)
	if is_power_blocked(snorlax, false):
		await main.show_message("LOLLING ABOUT IS BLOCKED!")
		if main._should_bail(): return
		return
	if snorlax.power_used_this_turn:
		await main.show_message("LOLLING ABOUT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if snorlax != active:
		await main.show_message("SNORLAX MUST BE YOUR ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	snorlax.power_used_this_turn = true
	await main.card_ops.heal_pokemon(snorlax, 10, is_opponent)
	if main._should_bail(): return
	main.card_ops.apply_status(snorlax, "Asleep", is_opponent)
	main.update_status_icons(snorlax, is_opponent)
	await main.show_message("LOLLING ABOUT! SNORLAX REMOVED A DAMAGE COUNTER AND FELL ASLEEP!")
	if main._should_bail(): return
	print("POWER USED: Lolling About")

######################################################################################################################################################
######################################################### ECARD3 EVOLVE-FROM-HAND TRIGGERS #############################################################
######################################################################################################################################################

# ENERGY RECHARGE (Arcanine): when played from hand to evolve your Active, may flip 3 coins —
# for each heads, choose a basic Energy from discard and attach it to Arcanine
func trigger_ecard3_energy_recharge(arcanine: card_object, is_opponent: bool) -> void:
	if is_power_blocked(arcanine): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if arcanine != active: return
	var heads = 0
	for i in range(3):
		if await main.flip_coin(true, is_opponent): heads += 1
	if main._should_bail(): return
	if heads == 0:
		await main.show_message("ENERGY RECHARGE! NO HEADS — NO EFFECT!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var attached_n = 0
	for i in range(heads):
		var basics = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
		if basics.is_empty(): break
		var chosen: card_object = basics[0]
		if not is_opponent and basics.size() > 1:
			chosen = await main.card_ops.prompt_select_card(basics, "ENERGY RECHARGE", "Choose a basic Energy to attach (" + str(heads - attached_n) + " remaining)", "ATTACH", false)
			if main._should_bail(): return
			if chosen == null: break
		discard.erase(chosen)
		arcanine.attached_energies.append(chosen)
		attached_n += 1
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message(str(heads) + " HEADS! ATTACHED " + str(attached_n) + " ENERGY TO ARCANINE!")
	if main._should_bail(): return
	print("POWER: Energy Recharge — attached ", attached_n)

# VENOM SPRAY (Beedrill): when played from hand to evolve your Active, Defending Pokemon is now Paralyzed and Poisoned
func trigger_ecard3_venom_spray(beedrill: card_object, is_opponent: bool) -> void:
	if is_power_blocked(beedrill): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if beedrill != active: return
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender == null: return
	main.card_ops.apply_status(defender, "Paralyzed", not is_opponent)
	main.card_ops.apply_status(defender, "Poisoned", not is_opponent)
	main.update_status_icons(defender, not is_opponent)
	await main.show_message("VENOM SPRAY! THE DEFENDING POKEMON IS PARALYZED AND POISONED!")
	if main._should_bail(): return
	print("POWER: Venom Spray")

# MANIPULATE (Gengar): when played from hand to evolve your Active, may put a Basic (non-Baby)
# from discard onto your bench, then flip 3 for basic Energy from discard onto it
func trigger_ecard3_manipulate(gengar: card_object, is_opponent: bool) -> void:
	if is_power_blocked(gengar): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if gengar != active: return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size(): return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var candidates = discard.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes",[]) and "Baby" not in c.metadata.get("subtypes",[]))
	if candidates.is_empty(): return
	var do_it = is_opponent
	if not is_opponent:
		do_it = await main.trainer_effects.gym1_prompt_yes_no(gengar, "MANIPULATE", "Put a Basic Pokemon from your discard pile onto your Bench?", "YES", "NO")
		if main._should_bail(): return
	if not do_it: return
	var chosen: card_object = candidates[0]
	if not is_opponent and candidates.size() > 1:
		chosen = await main.card_ops.prompt_select_card(candidates, "MANIPULATE", "Choose a Basic Pokemon", "BENCH", false)
		if main._should_bail(): return
		if chosen == null: return
	discard.erase(chosen)
	chosen.current_location = "bench"
	chosen.current_hp = chosen.get_max_hp()
	bench.append(chosen)
	main.display_pokemon(is_opponent)
	main.update_discard_pile_display(is_opponent)
	var heads = 0
	for i in range(3):
		if await main.flip_coin(true, is_opponent): heads += 1
	if main._should_bail(): return
	var attached_n = 0
	for i in range(heads):
		var basics = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
		if basics.is_empty(): break
		var e: card_object = basics[0]
		if not is_opponent and basics.size() > 1:
			e = await main.card_ops.prompt_select_card(basics, "MANIPULATE", "Choose a basic Energy to attach", "ATTACH", false)
			if main._should_bail(): return
			if e == null: break
		discard.erase(e)
		chosen.attached_energies.append(e)
		attached_n += 1
	main.display_active_pokemon_energies(is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("MANIPULATE! " + chosen.metadata.get("name","").to_upper() + " BENCHED WITH " + str(attached_n) + " ENERGY!")
	if main._should_bail(): return
	print("POWER: Manipulate")

# FLAME VAPOR (Gyarados): when played from hand to evolve your Active, may flip 2 — for each
# heads, discard an Energy attached to the Defending Pokemon
func trigger_ecard3_flame_vapor(gyarados: card_object, is_opponent: bool) -> void:
	if is_power_blocked(gyarados): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if gyarados != active: return
	var defender = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defender == null: return
	var heads = 0
	for i in range(2):
		if await main.flip_coin(true, is_opponent): heads += 1
	if main._should_bail(): return
	if heads == 0:
		await main.show_message("FLAME VAPOR! NO HEADS — NO EFFECT!")
		if main._should_bail(): return
		return
	var discarded = 0
	for i in range(heads):
		if defender.attached_energies.is_empty(): break
		var e: card_object = defender.attached_energies[0]
		if not is_opponent and defender.attached_energies.size() > 1:
			e = await main.card_ops.prompt_select_card(defender.attached_energies, "FLAME VAPOR", "Choose an Energy to discard from the Defending Pokemon", "DISCARD", false)
			if main._should_bail(): return
			if e == null: break
		defender.attached_energies.erase(e)
		main.card_ops.discard_energy_from_pokemon(e, not is_opponent)
		discarded += 1
	main.display_active_pokemon_energies(not is_opponent)
	await main.show_message(str(heads) + " HEADS! DISCARDED " + str(discarded) + " ENERGY FROM THE DEFENDING POKEMON!")
	if main._should_bail(): return
	print("POWER: Flame Vapor — discarded ", discarded)

# STREAMING MANTLE (Magcargo): when played from hand to evolve your Active, may discard the top 3
# of your deck then shuffle 3 basic Energy from discard into your deck — if you do, opponent does the same
func trigger_ecard3_streaming_mantle(magcargo: card_object, is_opponent: bool) -> void:
	if is_power_blocked(magcargo): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if magcargo != active: return
	var do_it = is_opponent
	if not is_opponent:
		do_it = await main.trainer_effects.gym1_prompt_yes_no(magcargo, "STREAMING MANTLE", "Discard the top 3 of your deck and shuffle 3 basic Energy from discard into your deck?", "YES", "NO")
		if main._should_bail(): return
	if not do_it: return
	for side in [is_opponent, not is_opponent]:
		var deck = main.opponent_deck if side else main.player_deck
		var discard = main.opponent_discard_pile if side else main.player_discard_pile
		var moved_top = 0
		for i in range(3):
			if deck.is_empty(): break
			var c = deck.pop_front()
			c.current_location = "discard"
			discard.append(c)
			moved_top += 1
		var basics = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
		var want = min(3, basics.size())
		for i in range(want):
			var pool = discard.filter(func(c): return main.attack_effects.gym1_is_basic_energy(c))
			if pool.is_empty(): break
			var e: card_object = pool[0]
			discard.erase(e)
			e.current_location = "deck"
			deck.append(e)
		deck.shuffle()
		main.update_deck_icon(side)
		main.update_discard_pile_display(side)
	await main.show_message("STREAMING MANTLE! BOTH PLAYERS DISCARDED 3 AND SHUFFLED BASIC ENERGY BACK IN!")
	if main._should_bail(): return
	print("POWER: Streaming Mantle")

# ATTRACT ENERGY (Magneton): when played from hand to evolve 1 of your Pokemon, may move any
# number of basic Energy attached to your OTHER Pokemon onto Magneton
func trigger_ecard3_attract_energy(magneton: card_object, is_opponent: bool) -> void:
	if is_power_blocked(magneton): return
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	var all_own: Array = []
	if active != null: all_own.append(active)
	all_own.append_array(bench)
	if magneton not in all_own: return
	var others = all_own.filter(func(p): return p != magneton and p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0)
	if others.is_empty(): return
	var moved = 0
	if is_opponent:
		for p in others:
			for e in p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).duplicate():
				p.attached_energies.erase(e)
				magneton.attached_energies.append(e)
				moved += 1
	else:
		var do_it = await main.trainer_effects.gym1_prompt_yes_no(magneton, "ATTRACT ENERGY", "Move basic Energy from your other Pokemon onto Magneton?", "YES", "NO")
		if main._should_bail(): return
		if not do_it: return
		var keep_going = true
		while keep_going:
			var pool = all_own.filter(func(p): return p != magneton and p.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0)
			if pool.is_empty(): break
			var source = await main.card_ops.prompt_select_card(pool, "ATTRACT ENERGY", "Select a Pokemon to move Energy from (or cancel to stop)", "SELECT", true)
			if main._should_bail(): return
			if source == null: break
			var basics = source.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e))
			var e = await main.card_ops.prompt_select_card(basics, "ATTRACT ENERGY", "Select the Energy to move", "MOVE", false)
			if main._should_bail(): return
			if e == null: continue
			source.attached_energies.erase(e)
			magneton.attached_energies.append(e)
			moved += 1
	if moved > 0:
		main.display_active_pokemon_energies(is_opponent)
		await main.show_message("ATTRACT ENERGY! MOVED " + str(moved) + " ENERGY TO MAGNETON!")
		if main._should_bail(): return
	print("POWER: Attract Energy — moved ", moved)

######################################################################################################################################################
######################################################### ECARD3 PASSIVE BODY HELPERS #################################################################
######################################################################################################################################################

# SELF-HEALING (Flareon): whenever a Fire Energy card is attached from hand to Flareon, remove
# all Special Conditions affecting it. Called right after a successful hand-to-Pokemon attach.
func check_ecard3_self_healing(target_pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	if target_pokemon == null: return
	if is_power_blocked(target_pokemon): return
	if not target_pokemon.has_ability("Self-healing"): return
	if not main.attack_effects.gym1_is_basic_energy(energy_card): return
	if "Fire" not in main.get_energy_provided_by_card(energy_card): return
	main.clear_all_statuses(target_pokemon, is_opponent)
	print("BODY: Self-healing — cured ", target_pokemon.metadata.get("name",""))

######################################################################################################################################################
######################################################### ECARD3 CPU ACTIVE-POWER TRIGGERS #############################################################
######################################################################################################################################################

func cpu_phase_ecard3_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var ancient_wind = _find_cpu_pokemon_with_power("Ancient Wind")
	if ancient_wind != null and main.opponent_active_pokemon == ancient_wind and not ancient_wind.power_used_this_turn and not is_power_blocked_by_status(ancient_wind):
		await power_ecard3_ancient_wind(ancient_wind)
		if main._should_bail(): return

	var carry_off = _find_cpu_pokemon_with_power("Carry Off")
	if carry_off == null: carry_off = _find_cpu_bench_pokemon_with_power("Carry Off")
	if carry_off != null and not carry_off.power_used_this_turn and not is_power_blocked_by_status(carry_off):
		await power_ecard3_carry_off(carry_off)
		if main._should_bail(): return

	var evo_helper = _find_cpu_bench_pokemon_with_power("Evolution Helper")
	if evo_helper != null and not evo_helper.power_used_this_turn and not is_power_blocked_by_status(evo_helper):
		if main.opponent_active_pokemon != null:
			await power_ecard3_evolution_helper(evo_helper)
			if main._should_bail(): return

	var strange_spiral = _find_cpu_pokemon_with_power("Strange Spiral")
	if strange_spiral != null and main.opponent_active_pokemon == strange_spiral and not strange_spiral.power_used_this_turn and not is_power_blocked_by_status(strange_spiral):
		if strange_spiral.attached_energies.filter(func(e): return main.attack_effects.gym1_is_basic_energy(e)).size() > 0 and main.player_active_pokemon != null and main.player_active_pokemon.special_condition == "":
			await power_ecard3_strange_spiral(strange_spiral)
			if main._should_bail(): return

	var good_neighbor = _find_cpu_bench_pokemon_with_power("Good Neighbor")
	if good_neighbor != null and not good_neighbor.power_used_this_turn and not is_power_blocked_by_status(good_neighbor):
		if main.opponent_active_pokemon != null and main.opponent_active_pokemon.current_hp < main.opponent_active_pokemon.get_max_hp():
			await power_ecard3_good_neighbor(good_neighbor)
			if main._should_bail(): return

	var reconstruction = _find_cpu_pokemon_with_power("Reconstruction")
	if reconstruction == null: reconstruction = _find_cpu_bench_pokemon_with_power("Reconstruction")
	if reconstruction != null and not reconstruction.power_used_this_turn and not is_power_blocked_by_status(reconstruction):
		await power_ecard3_reconstruction(reconstruction)
		if main._should_bail(): return

	var lolling_about = _find_cpu_pokemon_with_power("Lolling About")
	if lolling_about != null and main.opponent_active_pokemon == lolling_about and not lolling_about.power_used_this_turn and not is_power_blocked_by_status(lolling_about):
		if lolling_about.current_hp < lolling_about.get_max_hp() and main.opponent_active_pokemon.special_condition == "":
			await power_ecard3_lolling_about(lolling_about)
			if main._should_bail(): return

	# Energy Jump/Investigate are low-value CPU actions (no clear board-state trigger) — skipped
	# intentionally, consistent with other "no obvious heuristic" powers elsewhere in this file.

######################################################################################################################################################
######################################################### EX1 (RUBY & SAPPHIRE) POWERS AND BODIES ###################################################
######################################################################################################################################################
#
# Energy Trans (Sceptile) reuses the existing global "Energy Trans" dispatch entry (Venusaur) —
# no new registration needed. All Active/Defending Pokemon lookups below go through
# main.card_ops.get_active_pokemon() / get_defending_pokemon() / get_all_pokemon_in_play() for
# double-battle future-proofing, per the ex-series convention established this session.

func _register_ex1_powers() -> void:
	_power_dispatch["Firestarter"] = func(p): await power_ex1_firestarter(p)
	_power_dispatch["Energy Draw"] = func(p): await power_ex1_energy_draw(p)
	_power_dispatch["Psy Shadow"]  = func(p): await power_ex1_psy_shadow(p)
	_power_dispatch["Water Call"]  = func(p): await power_ex1_water_call(p)
	_power_dispatch["Drive Off"]   = func(p): await power_ex1_drive_off(p)

# FIRESTARTER (Blaziken): once per turn, may attach a Fire Energy from the discard pile to 1 of
# your Benched Pokemon.
func power_ex1_firestarter(blaziken: card_object) -> void:
	if is_power_blocked_by_status(blaziken):
		await main.show_message("FIRESTARTER IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if blaziken.power_used_this_turn:
		await main.show_message("FIRESTARTER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var fire_energies = main.player_discard_pile.filter(func(c): return "Fire" in main.get_energy_provided_by_card(c))
	if fire_energies.is_empty():
		await main.show_message("NO FIRE ENERGY IN THE DISCARD PILE!")
		if main._should_bail(): return
		return
	if main.player_bench.is_empty():
		await main.show_message("NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	var target = await main.card_ops.prompt_select_card(main.player_bench, "FIRESTARTER", "Choose a Benched Pokemon to attach Fire Energy to (cancel to stop)", "SELECT", true)
	if main._should_bail(): return
	if target == null: return
	var chosen = await main.card_ops.prompt_select_card(fire_energies, "FIRESTARTER", "Choose a Fire Energy from the discard pile", "ATTACH", false)
	if main._should_bail(): return
	if chosen == null: return
	blaziken.power_used_this_turn = true
	main.player_discard_pile.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.display_active_pokemon_energies(false)
	main.update_discard_pile_display(false)
	await main.show_message("FIRESTARTER! ATTACHED " + chosen.metadata.get("name","").to_upper() + " TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Firestarter")

func cpu_ex1_firestarter(blaziken: card_object) -> void:
	var fire_energies = main.opponent_discard_pile.filter(func(c): return "Fire" in main.get_energy_provided_by_card(c))
	if fire_energies.is_empty() or main.opponent_bench.is_empty(): return
	blaziken.power_used_this_turn = true
	var target = main.opponent_bench[0]
	for p in main.opponent_bench:
		if p.current_hp < target.current_hp: target = p
	var chosen = fire_energies[0]
	main.opponent_discard_pile.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.display_active_pokemon_energies(true)
	main.update_discard_pile_display(true)
	await main.show_message("OPPONENT USED FIRESTARTER!")
	if main._should_bail(): return
	print("CPU POWER: Firestarter")

# ENERGY DRAW (Delcatty): once per turn, may discard 1 Energy from hand, then draw up to 3 cards.
func power_ex1_energy_draw(delcatty: card_object) -> void:
	if is_power_blocked_by_status(delcatty):
		await main.show_message("ENERGY DRAW IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if delcatty.power_used_this_turn:
		await main.show_message("ENERGY DRAW ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var energies = main.player_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if energies.is_empty():
		await main.show_message("NO ENERGY CARDS IN HAND!")
		if main._should_bail(): return
		return
	var chosen = await main.card_ops.prompt_select_card(energies, "ENERGY DRAW", "Choose an Energy card from your hand to discard (cancel to stop)", "DISCARD", true)
	if main._should_bail(): return
	if chosen == null: return
	delcatty.power_used_this_turn = true
	await main.card_ops.send_to_discard(chosen, false, true)
	if main._should_bail(): return
	main.refresh_hand_display(false)
	await main.card_ops.draw_n(false, 3)
	if main._should_bail(): return
	await main.show_message("ENERGY DRAW! DISCARDED AN ENERGY AND DREW 3 CARDS!")
	if main._should_bail(): return
	print("POWER USED: Energy Draw")

func cpu_ex1_energy_draw(delcatty: card_object) -> void:
	var energies = main.opponent_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy")
	if energies.is_empty() or main.opponent_hand.size() < 2: return
	delcatty.power_used_this_turn = true
	var chosen = energies[0]
	await main.card_ops.send_to_discard(chosen, true, false)
	if main._should_bail(): return
	main.refresh_hand_display(true)
	await main.card_ops.draw_n(true, 3)
	if main._should_bail(): return
	await main.show_message("OPPONENT USED ENERGY DRAW!")
	if main._should_bail(): return
	print("CPU POWER: Energy Draw")

# PSY SHADOW (Gardevoir): once per turn, may search deck for a Psychic Energy, attach it to 1 of
# your Pokemon (get_all_pokemon_in_play), and put 2 damage counters on that Pokemon.
func power_ex1_psy_shadow(gardevoir: card_object) -> void:
	if is_power_blocked_by_status(gardevoir):
		await main.show_message("PSY SHADOW IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if gardevoir.power_used_this_turn:
		await main.show_message("PSY SHADOW ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var psychic_in_deck = main.player_deck.filter(func(c): return "Psychic" in main.get_energy_provided_by_card(c))
	if psychic_in_deck.is_empty():
		await main.show_message("NO PSYCHIC ENERGY IN YOUR DECK!")
		if main._should_bail(): return
		return
	var targets = main.card_ops.get_all_pokemon_in_play(false)
	if targets.is_empty(): return
	var target = targets[0] if targets.size() == 1 else await main.card_ops.prompt_select_card(targets, "PSY SHADOW", "Choose a Pokemon to attach Psychic Energy to (cancel to stop)", "SELECT", true)
	if main._should_bail(): return
	if target == null: return
	gardevoir.power_used_this_turn = true
	var chosen = psychic_in_deck[0]
	main.player_deck.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.player_deck.shuffle()
	main.display_active_pokemon_energies(false)
	main.update_deck_icon(false)
	target.current_hp = max(0, target.current_hp - 20)
	main.display_hp_circles_above_align(target, false)
	await main.show_message("PSY SHADOW! ATTACHED PSYCHIC ENERGY AND PUT 2 DAMAGE COUNTERS ON " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Psy Shadow")

func cpu_ex1_psy_shadow(gardevoir: card_object) -> void:
	var psychic_in_deck = main.opponent_deck.filter(func(c): return "Psychic" in main.get_energy_provided_by_card(c))
	if psychic_in_deck.is_empty(): return
	var targets = main.card_ops.get_all_pokemon_in_play(true)
	if targets.is_empty(): return
	var target = main.opponent_active_pokemon if main.opponent_active_pokemon != null else targets[0]
	if target.current_hp <= 20: return
	gardevoir.power_used_this_turn = true
	var chosen = psychic_in_deck[0]
	main.opponent_deck.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.opponent_deck.shuffle()
	main.display_active_pokemon_energies(true)
	main.update_deck_icon(true)
	target.current_hp = max(0, target.current_hp - 20)
	main.display_hp_circles_above_align(target, true)
	await main.show_message("OPPONENT USED PSY SHADOW!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("CPU POWER: Psy Shadow")

# WATER CALL (Swampert): once per turn, may attach a Water Energy from hand to your Active
# Pokemon. Uses get_active_pokemon() (1 target today).
func power_ex1_water_call(swampert: card_object) -> void:
	if is_power_blocked_by_status(swampert):
		await main.show_message("WATER CALL IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if swampert.power_used_this_turn:
		await main.show_message("WATER CALL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var water_in_hand = main.player_hand.filter(func(c): return "Water" in main.get_energy_provided_by_card(c))
	if water_in_hand.is_empty():
		await main.show_message("NO WATER ENERGY IN YOUR HAND!")
		if main._should_bail(): return
		return
	var actives = main.card_ops.get_active_pokemon(false)
	if actives.is_empty(): return
	var target = actives[0]
	var chosen = await main.card_ops.prompt_select_card(water_in_hand, "WATER CALL", "Choose a Water Energy card to attach to your Active Pokemon (cancel to stop)", "ATTACH", true)
	if main._should_bail(): return
	if chosen == null: return
	swampert.power_used_this_turn = true
	main.player_hand.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.refresh_hand_display(false)
	main.display_active_pokemon_energies(false)
	await main.show_message("WATER CALL! ATTACHED " + chosen.metadata.get("name","").to_upper() + " TO " + target.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Water Call")

func cpu_ex1_water_call(swampert: card_object) -> void:
	var water_in_hand = main.opponent_hand.filter(func(c): return "Water" in main.get_energy_provided_by_card(c))
	if water_in_hand.is_empty(): return
	var target = main.opponent_active_pokemon
	if target == null: return
	swampert.power_used_this_turn = true
	var chosen = water_in_hand[0]
	main.opponent_hand.erase(chosen)
	chosen.current_location = "attached"
	target.attached_energies.append(chosen)
	main.refresh_hand_display(true)
	main.display_active_pokemon_energies(true)
	await main.show_message("OPPONENT USED WATER CALL!")
	if main._should_bail(): return
	print("CPU POWER: Water Call")

# DRIVE OFF (Swellow): once per turn, if Swellow is your Active Pokemon, may switch 1 Defending
# Pokemon with 1 of the opponent's Benched Pokemon. The opponent picks the replacement — since
# the "opponent" here is the CPU, that pick is made via the CPU's own bench-replacement heuristic
# (the same one used for post-KO replacement), matching the codebase's existing "opponent picks"
# convention (e.g. Warp Point) where a human decision is only prompted when a real human is on
# the deciding side.
func power_ex1_drive_off(swellow: card_object) -> void:
	if is_power_blocked_by_status(swellow):
		await main.show_message("DRIVE OFF IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if swellow != main.player_active_pokemon:
		await main.show_message("SWELLOW MUST BE YOUR ACTIVE POKEMON!")
		if main._should_bail(): return
		return
	if swellow.power_used_this_turn:
		await main.show_message("DRIVE OFF ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var defending = main.card_ops.get_defending_pokemon(false)
	if defending.is_empty(): return
	if main.opponent_bench.is_empty():
		await main.show_message("OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	swellow.power_used_this_turn = true
	var cpu_eval = main.cpu_ai.get_cpu_evaluation()
	var new_active = main.cpu_ai.pick_best_bench_replacement(main.opponent_bench, main.player_active_pokemon, cpu_eval)
	if new_active == null:
		new_active = main.opponent_bench[0]
	# Reuse the canonical bench->active swap (handles current_location, status-clear on the
	# Pokemon leaving Active, and both display refreshes). attacker_is_opp=false → target is the
	# opponent, so their chosen benched Pokemon (new_active) becomes their Active.
	main.attack_effects._force_bench_to_active(new_active, false)
	await main.show_message("DRIVE OFF! OPPONENT SWITCHED IN " + new_active.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: Drive Off")

# CPU-side Drive Off: since the "opponent" being forced to switch is the human player, the human
# is prompted directly for their replacement (the codebase only auto-picks via heuristic when the
# deciding side has no real UI to prompt — see power_ex1_drive_off's comment above).
func cpu_ex1_drive_off(swellow: card_object) -> void:
	if main.player_active_pokemon == null or main.player_bench.is_empty(): return
	swellow.power_used_this_turn = true
	var new_active = await main.card_ops.prompt_select_card(main.player_bench, "DRIVE OFF", "The opponent's Swellow used Drive Off — choose your replacement", "SWITCH", false)
	if main._should_bail(): return
	if new_active == null:
		new_active = main.player_bench[0]
	# attacker_is_opp=true → target is the player, so their chosen benched Pokemon becomes Active.
	main.attack_effects._force_bench_to_active(new_active, true)
	await main.show_message("DRIVE OFF! YOU SWITCHED IN " + new_active.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("CPU POWER: Drive Off")

# LAZY (Slaking): registered directly in is_power_blocked() above (symmetric with Dark Gaze).

# INTIMIDATING FANG (Mightyena): while Mightyena is a side's Active, damage done to that side's
# Pokemon by an opponent's attack is reduced by 10. Checked via "defender's side has an Active
# Mightyena with this ability" rather than requiring defender == Mightyena, so this generalizes
# correctly once Double Battles exist (today the two are equivalent — 1 Active per side).
func _hook_ex1_intimidating_fang(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	var defender_is_opp = defender.is_owner_opp(main)
	var own_active = main.opponent_active_pokemon if defender_is_opp else main.player_active_pokemon
	if own_active == null or not own_active.has_ability("Intimidating Fang"):
		return damage
	if is_power_blocked_by_status(own_active):
		return damage
	var r = min(damage, 10)
	modifiers.append("INTIMIDATING FANG -" + str(r))
	return damage - r

# HARD COCOON (Cascoon / Silcoon): during the opponent's turn, if the holder would be damaged by
# an attack (after W/R), flip a coin; heads reduces that damage by 30. Damage-modifier hooks run
# synchronously (no awaits allowed), so this uses an inline RNG flip with no coin-flip animation —
# a documented simplification, consistent with other synchronous-hook bodies in this codebase.
func _hook_ex1_hard_cocoon(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if not defender.has_ability("Hard Cocoon"):
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if randi() % 2 == 0:
		return damage
	var r = min(damage, 30)
	modifiers.append("HARD COCOON -" + str(r))
	return damage - r

# ROUGH SKIN (Sharpedo: 2 counters / Carvanha: 1 counter): if the holder is Active and damaged by
# an opponent's attack (even if KO'd), put N damage counters on the Attacking Pokemon. Shared body
# name across both cards — amount is parsed from each card's own ability text. on_damage hooks
# only fire for the Active Pokemon, so no extra "is Active" check is needed here.
func check_ex1_rough_skin(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var ability = damaged_pokemon.get_ability("Rough Skin")
	if ability.is_empty():
		return
	if is_power_blocked_by_status(damaged_pokemon):
		return
	var text = ability.get("text", "").to_lower()
	var amount = 2
	var pos = text.find("put ")
	if pos != -1:
		var after = text.substr(pos + 4)
		var num_str = ""
		for ch in after:
			if ch.is_valid_int():
				num_str += ch
			else:
				break
		if num_str != "":
			amount = int(num_str)
	var dmg = amount * 10
	attacker.current_hp = max(0, attacker.current_hp - dmg)
	var attacker_is_opp = not is_damaged_opponent
	main.display_hp_circles_above_align(attacker, attacker_is_opp)
	var attacker_label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
	main.show_floating_label("-" + str(dmg) + "HP", attacker_label_pos, Color.WHITE, true)
	await main.show_message(damaged_pokemon.metadata.get("name", "").to_upper() + "'S ROUGH SKIN DEALT " + str(dmg) + " DAMAGE TO " + attacker.metadata.get("name", "").to_upper() + "!")
	print("ROUGH SKIN: ", dmg, " damage to ", attacker.metadata.get("name", ""))

# WITHERING DUST (Beautifly): true if Beautifly is in play on EITHER side (Active or Benched)
# and not status-blocked. Card text says "as long as Beautifly is in play" — not Active-only.
func is_ex1_withering_dust_in_play() -> bool:
	for side in [false, true]:
		for p in main.card_ops.get_all_pokemon_in_play(side):
			if p.has_ability("Withering Dust") and not is_power_blocked_by_status(p):
				return true
	return false

# NATURAL CURE (Combusken / Grovyle / Marshtomp): when you attach a matching-type Energy card
# from your hand, remove all Special Conditions. Type is derived from the holder's own types
# (data-driven) so this one function covers all three cards.
func check_ex1_natural_cure(target_pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	if target_pokemon == null: return
	if is_power_blocked(target_pokemon): return
	if not target_pokemon.has_ability("Natural Cure"): return
	var holder_types = target_pokemon.metadata.get("types", [])
	var provided = main.get_energy_provided_by_card(energy_card)
	var matches = false
	for t in holder_types:
		if t in provided:
			matches = true
			break
	if not matches: return
	main.clear_all_statuses(target_pokemon, is_opponent)
	print("BODY: Natural Cure — cured ", target_pokemon.metadata.get("name",""))

# NATURAL REMEDY (Swampert ex1-23): when you attach a Water Energy card from your hand, remove
# 1 damage counter.
func check_ex1_natural_remedy(target_pokemon: card_object, energy_card: card_object, is_opponent: bool) -> void:
	if target_pokemon == null: return
	if is_power_blocked(target_pokemon): return
	if not target_pokemon.has_ability("Natural Remedy"): return
	if "Water" not in main.get_energy_provided_by_card(energy_card): return
	if target_pokemon.current_hp >= target_pokemon.get_max_hp(): return
	target_pokemon.current_hp = min(target_pokemon.get_max_hp(), target_pokemon.current_hp + 10)
	main.display_hp_circles_above_align(target_pokemon, is_opponent)
	print("BODY: Natural Remedy — healed 10 on ", target_pokemon.metadata.get("name",""))

######################################################################################################################################################
######################################################### EX1 CPU ACTIVE-POWER TRIGGERS ##############################################################
######################################################################################################################################################

func cpu_phase_ex1_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var blaziken = _find_cpu_pokemon_with_power("Firestarter")
	if blaziken != null and not blaziken.power_used_this_turn and not is_power_blocked_by_status(blaziken):
		await cpu_ex1_firestarter(blaziken)
		if main._should_bail(): return

	var delcatty = _find_cpu_pokemon_with_power("Energy Draw")
	if delcatty != null and not delcatty.power_used_this_turn and not is_power_blocked_by_status(delcatty):
		await cpu_ex1_energy_draw(delcatty)
		if main._should_bail(): return

	var gardevoir = _find_cpu_pokemon_with_power("Psy Shadow")
	if gardevoir != null and not gardevoir.power_used_this_turn and not is_power_blocked_by_status(gardevoir):
		await cpu_ex1_psy_shadow(gardevoir)
		if main._should_bail(): return

	var swampert = _find_cpu_pokemon_with_power("Water Call")
	if swampert != null and not swampert.power_used_this_turn and not is_power_blocked_by_status(swampert):
		await cpu_ex1_water_call(swampert)
		if main._should_bail(): return

	var swellow = _find_cpu_pokemon_with_power("Drive Off")
	if swellow != null and main.opponent_active_pokemon == swellow and not swellow.power_used_this_turn and not is_power_blocked_by_status(swellow):
		await cpu_ex1_drive_off(swellow)
		if main._should_bail(): return

######################################################################################################################################################
##################################################### EX2 (SANDSTORM) POWERS & BODIES ################################################################
######################################################################################################################################################
# Auto-handled by existing name-based machinery (no ex2 code needed):
#   Rain Dish (Ludicolo/Lombre/Lotad)    -> apply_np_between_turn_bodies() name loop (+ Spongy Stone added there)
#   Exoskeleton (Kabuto)                 -> _FLAT_REDUCTION_BODY_NAMES flat -20 modifier hook
#   Intimidating Fang (Arbok)            -> _hook_ex1_intimidating_fang (has_ability check, -10)
#   Poison Resistance (Zangoose)         -> Card_Ops.apply_status name block

func _register_ex2_powers() -> void:
	_power_dispatch["Baby Evolution"] = func(p): await power_ex2_baby_evolution(p)
	_power_dispatch["Lunar Eclipse"]  = func(p): await power_ex2_eclipse(p, "Solrock", "Darkness")
	_power_dispatch["Solar Eclipse"]  = func(p): await power_ex2_eclipse(p, "Lunatone", "Fire")
	_power_dispatch["Fan Away"]       = func(p): await power_ex2_fan_away(p)
	_power_dispatch["Chaos Flash"]    = func(p): await power_ex2_chaos_flash(p)
	_power_dispatch["Healing Wind"]   = func(p): await power_ex2_healing_wind(p)

# True if a named Pokemon is in play (Active or Bench) on the given side.
func _ex2_named_in_play(is_opponent: bool, poke_name: String) -> bool:
	for p in main.card_ops.get_all_pokemon_in_play(is_opponent):
		if p.metadata.get("name","") == poke_name:
			return true
	return false

# BABY EVOLUTION (Pichu/Azurill/Elekid/Wynaut): once per turn, put the named Evolution from your
# hand onto this baby (counts as evolving) and remove all damage counters from it.
func power_ex2_baby_evolution(baby: card_object) -> void:
	var is_opponent = baby.is_owner_opp(main)
	if is_power_blocked_by_status(baby):
		await main.show_message("BABY EVOLUTION IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if baby.power_used_this_turn:
		await main.show_message("BABY EVOLUTION ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	# Parse the evolution's name from the ability text ("put Pikachu from your hand onto ...").
	var ability = baby.get_ability("Baby Evolution")
	var text = ability.get("text", "")
	var evo_name = ""
	var lo = text.to_lower()
	var p1 = lo.find("put ")
	var p2 = lo.find(" from your hand")
	if p1 != -1 and p2 != -1 and p2 > p1:
		evo_name = text.substr(p1 + 4, p2 - (p1 + 4)).strip_edges()
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var matches = hand.filter(func(c): return c.metadata.get("name","") == evo_name)
	if matches.is_empty():
		await main.show_message("BABY EVOLUTION: NO " + evo_name.to_upper() + " IN HAND!")
		if main._should_bail(): return
		return
	baby.power_used_this_turn = true
	var evo_card = matches[0]
	await main.trainer_effects._ex2_do_evolution(evo_card, baby, is_opponent, hand)
	evo_card.current_hp = evo_card.get_max_hp()
	main.display_pokemon(is_opponent)
	main.display_hp_circles_above_align(evo_card, is_opponent)
	await main.show_message("BABY EVOLUTION! EVOLVED INTO " + evo_name.to_upper() + " AND HEALED FULLY!")
	if main._should_bail(): return

# LUNAR / SOLAR ECLIPSE (Lunatone / Solrock): once per turn, if the partner is in play, change this
# Pokemon's type until the end of your turn.
func power_ex2_eclipse(pokemon: card_object, partner_name: String, new_type: String) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("ECLIPSE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("ECLIPSE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	if not _ex2_named_in_play(is_opponent, partner_name):
		await main.show_message("ECLIPSE REQUIRES " + partner_name.to_upper() + " IN PLAY!")
		if main._should_bail(): return
		return
	pokemon.power_used_this_turn = true
	pokemon.set_effect("ex2_type_override", "end_of_own_turn", new_type)
	main.display_pokemon(is_opponent)
	await main.show_message(pokemon.metadata.get("name","").to_upper() + "'S TYPE IS NOW " + new_type.to_upper() + " UNTIL END OF TURN!")
	if main._should_bail(): return

# FAN AWAY (Shiftry): once per turn, flip a coin; if heads, return 1 Energy attached to the
# Defending Pokemon to your opponent's hand.
func power_ex2_fan_away(shiftry: card_object) -> void:
	var is_opponent = shiftry.is_owner_opp(main)
	if is_power_blocked_by_status(shiftry):
		await main.show_message("FAN AWAY IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if shiftry.power_used_this_turn:
		await main.show_message("FAN AWAY ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	shiftry.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! FAN AWAY HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var defending = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defending == null or defending.attached_energies.is_empty():
		await main.show_message("HEADS! BUT THE DEFENDING POKEMON HAS NO ENERGY!")
		if main._should_bail(): return
		return
	var target_is_opp = not is_opponent
	var chosen = await main.card_ops.choose_card(defending.attached_energies, is_opponent, "FAN AWAY", "Choose an Energy to return to your opponent's hand", "RETURN", false)
	if main._should_bail(): return
	if chosen == null: return
	defending.attached_energies.erase(chosen)
	chosen.current_location = "hand"
	var opp_hand = main.player_hand if is_opponent else main.opponent_hand
	opp_hand.append(chosen)
	main.display_active_pokemon_energies(target_is_opp)
	main.refresh_hand_display(target_is_opp)
	await main.show_message("HEADS! FAN AWAY RETURNED " + chosen.metadata.get("name","").to_upper() + " TO YOUR OPPONENT'S HAND!")
	if main._should_bail(): return

# CHAOS FLASH (Golduck): once per turn, if Golduck is your Active Pokemon, flip a coin; if heads,
# the Defending Pokemon is now Confused.
func power_ex2_chaos_flash(golduck: card_object) -> void:
	var is_opponent = golduck.is_owner_opp(main)
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if golduck != own_active:
		await main.show_message("CHAOS FLASH REQUIRES GOLDUCK TO BE ACTIVE!")
		if main._should_bail(): return
		return
	if is_power_blocked_by_status(golduck):
		await main.show_message("CHAOS FLASH IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if golduck.power_used_this_turn:
		await main.show_message("CHAOS FLASH ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	golduck.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("TAILS! CHAOS FLASH HAD NO EFFECT!")
		if main._should_bail(): return
		return
	var defending = main.player_active_pokemon if is_opponent else main.opponent_active_pokemon
	if defending != null:
		main.card_ops.apply_status(defending, "Confused", not is_opponent)
	await main.show_message("HEADS! THE DEFENDING POKEMON IS NOW CONFUSED!")
	if main._should_bail(): return

# HEALING WIND (Xatu): once per turn, remove 1 damage counter from each of your Active Pokemon.
func power_ex2_healing_wind(xatu: card_object) -> void:
	var is_opponent = xatu.is_owner_opp(main)
	if is_power_blocked_by_status(xatu):
		await main.show_message("HEALING WIND IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if xatu.power_used_this_turn:
		await main.show_message("HEALING WIND ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	xatu.power_used_this_turn = true
	for p in main.card_ops.get_active_pokemon(is_opponent):
		if p.current_hp < p.get_max_hp():
			p.current_hp = min(p.get_max_hp(), p.current_hp + 10)
			main.display_hp_circles_above_align(p, is_opponent)
	await main.show_message("HEALING WIND! REMOVED 1 DAMAGE COUNTER FROM EACH OF YOUR ACTIVE POKEMON!")
	if main._should_bail(): return

# ── EX2 passive bodies ─────────────────────────────────────────────────────────────────────────

# POISON PAYBACK (Cacturne / Cacnea): if this Pokemon is Active and damaged by an opponent's attack
# (even if KO'd), the Attacking Pokemon is now Poisoned.
func check_ex2_poison_payback(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if not damaged_pokemon.has_ability("Poison Payback"):
		return
	if is_power_blocked_by_status(damaged_pokemon):
		return
	main.card_ops.apply_status(attacker, "Poisoned", not is_damaged_opponent)
	await main.show_message(damaged_pokemon.metadata.get("name","").to_upper() + "'S POISON PAYBACK POISONED " + attacker.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return

# FIRE VEIL (Arcanine / Growlithe): if this Pokemon is Active and damaged by an opponent's attack
# (even if KO'd), the Attacking Pokemon is now Burned.
func check_ex2_fire_veil(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if not damaged_pokemon.has_ability("Fire Veil"):
		return
	if is_power_blocked_by_status(damaged_pokemon):
		return
	main.card_ops.apply_status(attacker, "Burned", not is_damaged_opponent)
	await main.show_message(damaged_pokemon.metadata.get("name","").to_upper() + "'S FIRE VEIL BURNED " + attacker.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return

# JAGGED STONE (Claw Fossil): if this is your Active and damaged by an opponent's attack (even if
# KO'd), put 1 damage counter on the Attacking Pokemon.
func check_ex2_jagged_stone(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	if not damaged_pokemon.has_ability("Jagged Stone"):
		return
	attacker.current_hp = max(0, attacker.current_hp - 10)
	var attacker_is_opp = not is_damaged_opponent
	main.display_hp_circles_above_align(attacker, attacker_is_opp)
	main.show_floating_label("-10", Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300), Color.WHITE, true)
	await main.show_message(damaged_pokemon.metadata.get("name","").to_upper() + "'S JAGGED STONE PUT 1 DAMAGE COUNTER ON " + attacker.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return

# GLOWING SCREEN (Illumise): while Volbeat is in play on Illumise's side, damage to Illumise from
# Fighting and Darkness Pokemon is reduced by 30 (capped at 30 total). Synchronous modifier hook.
func _hook_ex2_glowing_screen(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if not defender.has_ability("Glowing Screen"):
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	var defender_is_opp = defender.is_owner_opp(main)
	if not _ex2_named_in_play(defender_is_opp, "Volbeat"):
		return damage
	var atypes = attacker.get_effective_types()
	if "Fighting" not in atypes and "Darkness" not in atypes:
		return damage
	var r = min(damage, 30)
	modifiers.append("GLOWING SCREEN -" + str(r))
	return damage - r

# SAFEGUARD (Wobbuffet): prevent all effects of attacks, including damage, done by the opponent's
# Pokemon-ex. Implemented as damage prevention (set to 0) via a modifier hook; the "prevent all
# effects" scope is simplified to damage here, consistent with other synchronous-hook bodies.
func _hook_ex2_safeguard(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if not defender.has_ability("Safeguard"):
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if not main.is_ex_pokemon(attacker):
		return damage
	modifiers.append("SAFEGUARD (NO EFFECT FROM EX)")
	return 0

# PRIMAL VEIL (Armaldo): true if either side has an Active Armaldo with this body (blocks Supporters
# for BOTH players). Checked in the trainer play/validation gates.
func is_ex2_primal_veil_active() -> bool:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active != null and active.has_ability("Primal Veil") and not is_power_blocked_by_status(active):
			return true
	return false

# PRIMAL LOCK (Aerodactyl ex): true if the side OPPOSING `tool_player_is_opp` has Aerodactyl ex
# (with this body) in play — that player can't play Pokemon Tool cards.
func is_ex2_primal_lock_blocking(tool_player_is_opp: bool) -> bool:
	var blocker_side = not tool_player_is_opp
	for p in main.card_ops.get_all_pokemon_in_play(blocker_side):
		if p.has_ability("Primal Lock") and not is_power_blocked_by_status(p):
			return true
	return false

# Discards any Pokemon Tool cards attached to the opponent's Pokemon while Primal Lock is in play.
# Called between turns (the "remove any Pokemon Tool cards" clause of Primal Lock).
func apply_ex2_primal_lock_removal() -> void:
	for side in [false, true]:
		# `side` has Aerodactyl ex → strip tools from the OTHER side
		var has_lock = false
		for p in main.card_ops.get_all_pokemon_in_play(side):
			if p.has_ability("Primal Lock") and not is_power_blocked_by_status(p):
				has_lock = true
				break
		if not has_lock:
			continue
		var victim_side = not side
		var discard = main.opponent_discard_pile if victim_side else main.player_discard_pile
		for p in main.card_ops.get_all_pokemon_in_play(victim_side):
			for ac in p.attached_cards.duplicate():
				if "Pokémon Tool" in ac.metadata.get("subtypes", []):
					p.attached_cards.erase(ac)
					ac.current_location = "discard"
					discard.append(ac)
					display_attached_trainer_cards(victim_side)
					main.update_discard_pile_display(victim_side)
					await main.show_message("PRIMAL LOCK DISCARDED " + ac.metadata.get("name","").to_upper() + "!")
					if main._should_bail(): return

# ── CPU activation for ex2 active powers ─────────────────────────────────────────────────────────
func cpu_phase_ex2_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	# Baby Evolution: evolve whenever the CPU holds the evolution in hand.
	for baby in main.card_ops.get_all_pokemon_in_play(true):
		if baby.has_ability("Baby Evolution") and not baby.power_used_this_turn and not is_power_blocked_by_status(baby):
			var ability = baby.get_ability("Baby Evolution")
			var lo = ability.get("text","").to_lower()
			var p1 = lo.find("put ")
			var p2 = lo.find(" from your hand")
			if p1 != -1 and p2 != -1 and p2 > p1:
				var evo_name = ability.get("text","").substr(p1 + 4, p2 - (p1 + 4)).strip_edges()
				var has_it = main.opponent_hand.any(func(c): return c.metadata.get("name","") == evo_name)
				if has_it:
					await power_ex2_baby_evolution(baby)
					if main._should_bail(): return

	# Fan Away: disrupt whenever the Defending Pokemon has Energy attached.
	var shiftry = _find_cpu_pokemon_with_power("Fan Away")
	if shiftry != null and not shiftry.power_used_this_turn and not is_power_blocked_by_status(shiftry):
		if main.player_active_pokemon != null and not main.player_active_pokemon.attached_energies.is_empty():
			await cpu_ex2_fan_away(shiftry)
			if main._should_bail(): return

	# Chaos Flash: use whenever Golduck is the CPU's Active.
	var golduck = _find_cpu_pokemon_with_power("Chaos Flash")
	if golduck != null and main.opponent_active_pokemon == golduck and not golduck.power_used_this_turn and not is_power_blocked_by_status(golduck):
		await power_ex2_chaos_flash(golduck)
		if main._should_bail(): return

	# Healing Wind: use whenever an Active Pokemon is damaged.
	var xatu = _find_cpu_pokemon_with_power("Healing Wind")
	if xatu != null and not xatu.power_used_this_turn and not is_power_blocked_by_status(xatu):
		for p in main.card_ops.get_active_pokemon(true):
			if p.current_hp < p.get_max_hp():
				await power_ex2_healing_wind(xatu)
				break
		if main._should_bail(): return

# CPU Fan Away: pick the Defending Pokemon's most-plentiful Energy (choose_card with pool[0] default).
func cpu_ex2_fan_away(shiftry: card_object) -> void:
	await power_ex2_fan_away(shiftry)

######################################################################################################################################################
##################################################### EX3 (EX DRAGON) POWERS & BODIES ################################################################
######################################################################################################################################################
# Auto-handled by existing name-based machinery (no ex3 code needed):
#   Intimidating Fang (Salamence ex3-19) -> _hook_ex1_intimidating_fang (has_ability, -10)
#   Exoskeleton (Pineco ex3-71)          -> _FLAT_REDUCTION_BODY_NAMES flat reduction (reads -10 from text)
#   Conductivity (Ampharos ex ex3-89)    -> check_neo4_conductivity (has_ability, +1 counter on opponent attach)
#   Toxic Gas (Muk ex ex3-96)            -> is_toxic_gas_active() (has_ability "Toxic Gas")
#   Sand Guard / Energy Guard / Buffer Piece -> damage-modifier hooks (see _register_all_power_hooks)
#   Thick Skin (Roselia ex3-9)           -> Card_Ops.apply_status name block
#   Submerge (Whiscash ex3-48)           -> Card_Ops.apply_bench_damage guard
#   Levitate (Vibrava ex3-46)            -> get_retreat_cost self-reduction
#   Chain of Events (Minun/Plusle)       -> double-battle-only Poké-Body; structural no-op in single battles
func _register_ex3_powers() -> void:
	_power_dispatch["Dragon Wind"]    = func(p): await power_ex3_dragon_wind(p)
	_power_dispatch["Magnetic Field"] = func(p): await power_ex3_magnetic_field(p)
	_power_dispatch["Call for Power"] = func(p): await power_ex3_call_for_power(p)

# POWER PINCHERS (Crawdaunt ex3-3, Poké-Body): while Crawdaunt is your Active Pokemon, your attacks
# do +10 damage to the Defending Pokemon. (Applied after W/R here; the card says "before W/R" — a
# minor, consistent simplification for the flat-modifier hook system.)
func _hook_ex3_power_pinchers(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or attacker == null or defender == null:
		return damage
	var atk_is_opp = attacker.is_owner_opp(main)
	var own_active = main.opponent_active_pokemon if atk_is_opp else main.player_active_pokemon
	if own_active == null or not own_active.has_ability("Power Pinchers"):
		return damage
	if is_power_blocked_by_status(own_active):
		return damage
	modifiers.append("POWER PINCHERS +10")
	return damage + 10

# WONDER GUARD (Shedinja ex3-11, Poké-Body): prevent all damage done to Shedinja by the opponent's
# Evolved Pokemon and Pokemon-ex. ("All effects" is simplified to damage, same depth as ex2 Safeguard.)
func _hook_ex3_wonder_guard(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if not defender.has_ability("Wonder Guard"):
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if (not main.is_basic_pokemon(attacker)) or main.is_ex_pokemon(attacker):
		modifiers.append("WONDER GUARD")
		return 0
	return damage

# DRAGON WIND (Salamence ex3-10, Poké-Power): once per turn, gust up 1 of your opponent's Benched
# Pokemon into the Active spot (you choose which Benched Pokemon).
func power_ex3_dragon_wind(salamence: card_object) -> void:
	var is_opponent = salamence.is_owner_opp(main)
	if is_power_blocked_by_status(salamence):
		await main.show_message("DRAGON WIND IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if salamence.power_used_this_turn:
		await main.show_message("DRAGON WIND ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if salamence != own_active:
		await main.show_message("DRAGON WIND ONLY WORKS WHILE SALAMENCE IS ACTIVE!")
		if main._should_bail(): return
		return
	var opp_bench = main.player_bench if is_opponent else main.opponent_bench
	if opp_bench.is_empty():
		await main.show_message("DRAGON WIND: OPPONENT HAS NO BENCHED POKEMON!")
		if main._should_bail(): return
		return
	salamence.power_used_this_turn = true
	var eff = {"type": "force_switch", "target": "defender", "chooser": "attacker", "flip": "none"}
	await main.attack_effects.apply_force_switch(eff, is_opponent)
	if main._should_bail(): return
	print("POWER USED: Dragon Wind")

func cpu_ex3_dragon_wind(salamence: card_object) -> void:
	if main.player_bench.is_empty():
		return
	salamence.power_used_this_turn = true
	var eff = {"type": "force_switch", "target": "defender", "chooser": "attacker", "flip": "none"}
	await main.attack_effects.apply_force_switch(eff, true)
	if main._should_bail(): return
	print("CPU POWER: Dragon Wind")

# MAGNETIC FIELD (Magneton ex3-17, Poké-Power): once per turn, if you have basic Energy in your
# discard pile, discard 1 card from your hand, then take up to 2 basic Energy from your discard pile
# into your hand (not the card you just discarded).
func power_ex3_magnetic_field(magneton: card_object) -> void:
	var is_opponent = magneton.is_owner_opp(main)
	if is_power_blocked_by_status(magneton):
		await main.show_message("MAGNETIC FIELD IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if magneton.power_used_this_turn:
		await main.show_message("MAGNETIC FIELD ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.player_hand if not is_opponent else main.opponent_hand
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		await main.show_message("MAGNETIC FIELD: NO BASIC ENERGY IN YOUR DISCARD PILE!")
		if main._should_bail(): return
		return
	if hand.is_empty():
		await main.show_message("MAGNETIC FIELD: NO CARDS IN HAND TO DISCARD!")
		if main._should_bail(): return
		return
	var to_discard = await main.card_ops.prompt_select_card(hand, "MAGNETIC FIELD", "Choose a card from your hand to discard", "DISCARD", false)
	if main._should_bail(): return
	if to_discard == null: return
	magneton.power_used_this_turn = true
	await main.card_ops.send_to_discard(to_discard, is_opponent, true)
	if main._should_bail(): return
	var moved = 0
	for i in range(2):
		var pool = discard.filter(func(c): return c != to_discard and c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
		if pool.is_empty(): break
		var chosen = await main.card_ops.prompt_select_card(pool, "MAGNETIC FIELD", "Choose a basic Energy from your discard (cancel to stop)", "TAKE", moved >= 1)
		if main._should_bail(): return
		if chosen == null: break
		await main.card_ops.recover_to_hand(chosen, is_opponent)
		if main._should_bail(): return
		moved += 1
	await main.show_message("MAGNETIC FIELD! RECOVERED " + str(moved) + " BASIC ENERGY TO HAND!")
	if main._should_bail(): return
	print("POWER USED: Magnetic Field")

func cpu_ex3_magnetic_field(magneton: card_object) -> void:
	var discard = main.opponent_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty() or main.opponent_hand.is_empty():
		return
	# Discard the least-useful hand card (prefer a duplicate basic Energy; else the first card).
	var to_discard = main.opponent_hand[0]
	for c in main.opponent_hand:
		if c.metadata.get("supertype","") == "Energy":
			to_discard = c
			break
	magneton.power_used_this_turn = true
	await main.card_ops.send_to_discard(to_discard, true, true)
	if main._should_bail(): return
	var moved = 0
	for i in range(2):
		var pool = discard.filter(func(c): return c != to_discard and c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
		if pool.is_empty(): break
		await main.card_ops.recover_to_hand(pool[0], true)
		if main._should_bail(): return
		moved += 1
	await main.show_message("OPPONENT USED MAGNETIC FIELD!")
	if main._should_bail(): return
	print("CPU POWER: Magnetic Field")

# CALL FOR POWER (Dragonite ex ex3-90, Poké-Power): as often as you like, move an Energy attached to
# 1 of your Pokemon to Dragonite ex.
func power_ex3_call_for_power(dragonite: card_object) -> void:
	var is_opponent = dragonite.is_owner_opp(main)
	if is_power_blocked_by_status(dragonite):
		await main.show_message("CALL FOR POWER IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	while true:
		var sources: Array = []
		for p in main.card_ops.get_all_pokemon_in_play(is_opponent):
			if p == dragonite:
				continue
			for e in p.attached_energies:
				sources.append({"pokemon": p, "energy": e})
		if sources.is_empty():
			await main.show_message("CALL FOR POWER: NO ENERGY TO MOVE!")
			if main._should_bail(): return
			return
		# Present the source Pokemon that still have Energy; move all of the chosen one's Energy is
		# too coarse, so choose an individual Energy card from a flat pool.
		var energy_pool: Array = []
		for s in sources:
			energy_pool.append(s["energy"])
		var chosen = await main.card_ops.choose_card(energy_pool, is_opponent, "CALL FOR POWER", "Choose an Energy to move to Dragonite ex (cancel to stop)", "MOVE", true)
		if main._should_bail(): return
		if chosen == null:
			break
		# Find and detach it from its current holder, then attach to Dragonite ex.
		for s in sources:
			if s["energy"] == chosen:
				s["pokemon"].attached_energies.erase(chosen)
				break
		chosen.current_location = "attached"
		dragonite.attached_energies.append(chosen)
		main.display_active_pokemon_energies(is_opponent)
		main.display_pokemon(is_opponent)
	await main.show_message("CALL FOR POWER! MOVED ENERGY TO DRAGONITE EX!")
	if main._should_bail(): return
	print("POWER USED: Call for Power")

func cpu_ex3_call_for_power(dragonite: card_object) -> void:
	# CPU: pull all Energy off its Benched Pokemon onto Dragonite ex to power it up.
	var moved = 0
	for p in main.card_ops.get_all_pokemon_in_play(true):
		if p == dragonite:
			continue
		for e in p.attached_energies.duplicate():
			p.attached_energies.erase(e)
			e.current_location = "attached"
			dragonite.attached_energies.append(e)
			moved += 1
	if moved > 0:
		main.display_active_pokemon_energies(true)
		main.display_pokemon(true)
		await main.show_message("OPPONENT USED CALL FOR POWER!")
		if main._should_bail(): return
		print("CPU POWER: Call for Power")

# LOOSE SHELL (Ninjask ex3-18, Poké-Power): when Ninjask evolves from hand, you may search your deck
# for Shedinja and put it onto your Bench (treated as a Basic).
func trigger_ex3_loose_shell(ninjask: card_object, is_opponent: bool) -> void:
	if is_power_blocked_by_status(ninjask) or is_toxic_gas_active() or main.goop_gas_active:
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= 5:
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var shedinjas = deck.filter(func(c): return c.metadata.get("name","") == "Shedinja")
	if shedinjas.is_empty():
		return
	var do_it = true
	if not is_opponent:
		do_it = await main.trainer_effects.gym1_prompt_yes_no(ninjask, "LOOSE SHELL", "Search your deck for Shedinja and put it on your Bench?", "YES", "NO")
		if main._should_bail(): return
	if not do_it:
		return
	var shedinja = shedinjas[0]
	deck.erase(shedinja)
	shedinja.current_hp = shedinja.get_max_hp()
	main.card_ops.place_on_bench(shedinja, is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	main.display_pokemon(is_opponent)
	await main.show_message("LOOSE SHELL! PUT SHEDINJA ONTO THE BENCH!")
	if main._should_bail(): return
	print("POWER USED: Loose Shell")

# CPU activation for the ex3 active Poké-Powers.
func cpu_phase_ex3_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var salamence = _find_cpu_pokemon_with_power("Dragon Wind")
	if salamence != null and main.opponent_active_pokemon == salamence and not salamence.power_used_this_turn and not is_power_blocked_by_status(salamence):
		# Only gust if the player has a Benched Pokemon worth dragging up (low HP = KO target).
		if not main.player_bench.is_empty():
			await cpu_ex3_dragon_wind(salamence)
			if main._should_bail(): return

	var magneton = _find_cpu_pokemon_with_power("Magnetic Field")
	if magneton != null and not magneton.power_used_this_turn and not is_power_blocked_by_status(magneton):
		await cpu_ex3_magnetic_field(magneton)
		if main._should_bail(): return

	var dragonite = _find_cpu_pokemon_with_power("Call for Power")
	if dragonite != null and not is_power_blocked_by_status(dragonite):
		await cpu_ex3_call_for_power(dragonite)
		if main._should_bail(): return

######################################################################################################################################################
################################### EX4 (TEAM MAGMA VS TEAM AQUA) POWERS & BODIES ####################################################################
######################################################################################################################################################
func _register_ex4_powers() -> void:
	_power_dispatch["Power Shift"]     = func(p): await power_ex4_energy_move(p, "Team Aqua", -1)
	_power_dispatch["Magma Switch"]    = func(p): await power_ex4_energy_move(p, "Team Magma", 1)
	_power_dispatch["Overheat"]        = func(p): await power_ex4_overheat(p)
	_power_dispatch["Auxiliary Light"] = func(p): await power_ex4_auxiliary_light(p)
	_power_dispatch["Call for Help"]   = func(p): await power_ex4_call_for_help(p)

# ── Passive bodies ──────────────────────────────────────────────────────────

# POWER SAVER (Kyogre ex4-3 / Groudon ex4-9, Poké-Body): as long as the number of Pokemon in play
# (both sides) with this Team's name is 3 or less, the holder can't attack. Checked in
# Main.get_attacks_for_card (returns [] → no attacks selectable).
func check_power_saver_blocks_attack(card: card_object) -> bool:
	if card == null or not card.has_ability("Power Saver"):
		return false
	if is_power_blocked(card):
		return false
	var team = "Team Aqua" if "Team Aqua" in card.metadata.get("name","") else "Team Magma"
	var count = 0
	for p in main.card_ops.get_all_pokemon_in_play(false):
		if team in p.metadata.get("name",""): count += 1
	for p in main.card_ops.get_all_pokemon_in_play(true):
		if team in p.metadata.get("name",""): count += 1
	return count <= 3

# SHELL RETREAT (Squirtle ex4-46, Poké-Body): while Squirtle has any Energy attached, damage done to
# it by an opponent's attack is reduced by 10 (after Weakness/Resistance).
func _hook_ex4_shell_retreat(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if not defender.has_ability("Shell Retreat"):
		return damage
	if is_power_blocked_by_status(defender):
		return damage
	if defender.attached_energies.is_empty():
		return damage
	modifiers.append("SHELL RETREAT -10")
	return max(0, damage - 10)

# ── Active powers ───────────────────────────────────────────────────────────

func _ex4_energy_pool(p: card_object, basic_only: bool) -> Array:
	if not basic_only:
		return p.attached_energies.duplicate()
	return p.attached_energies.filter(func(e): return "Basic" in e.metadata.get("subtypes", []))

# POWER SHIFT (Manectric ex4-4) / MAGMA SWITCH (Claydol ex4-8): move Energy from one of your Team
# Pokemon to another of your Pokemon. Power Shift moves any number of BASIC Energy (max_move -1);
# Magma Switch moves 1 Energy of any kind (max_move 1). Player-interactive only — the CPU skips
# energy redistribution (low value for the heuristic AI).
func power_ex4_energy_move(pokemon: card_object, team: String, max_move: int) -> void:
	var is_opponent = pokemon.is_owner_opp(main)
	if is_power_blocked_by_status(pokemon):
		await main.show_message("THIS POWER IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if pokemon.power_used_this_turn:
		await main.show_message("THIS POWER WAS ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	if is_opponent:
		return
	var basic_only = (max_move == -1)
	var mine = main.card_ops.get_all_pokemon_in_play(false)
	var sources = mine.filter(func(p): return (team in p.metadata.get("name","")) and _ex4_energy_pool(p, basic_only).size() > 0)
	if sources.is_empty():
		await main.show_message("NO ENERGY AVAILABLE TO MOVE!")
		if main._should_bail(): return
		return
	var source: card_object
	if sources.size() == 1:
		source = sources[0]
	else:
		source = await main.card_ops.choose_card(sources, false, "MOVE ENERGY", "Choose the Pokemon to move Energy FROM", "SELECT", false)
		if main._should_bail(): return
		if source == null: return
	var dests = mine.filter(func(p): return p != source)
	if dests.is_empty():
		await main.show_message("NO OTHER POKEMON TO MOVE ENERGY TO!")
		if main._should_bail(): return
		return
	var dest = await main.card_ops.choose_card(dests, false, "MOVE ENERGY", "Choose the Pokemon to move Energy TO", "SELECT", false)
	if main._should_bail(): return
	if dest == null: return
	var pool = _ex4_energy_pool(source, basic_only)
	var to_move: Array = []
	if max_move == 1:
		var e = pool[0] if pool.size() == 1 else await main.card_ops.choose_card(pool, false, "MOVE ENERGY", "Choose an Energy to move", "SELECT", false)
		if main._should_bail(): return
		if e == null: return
		to_move = [e]
	else:
		to_move = pool  # move all basic Energy (all-or-nothing simplification of "any number")
	pokemon.power_used_this_turn = true
	for e in to_move:
		source.attached_energies.erase(e)
		dest.attached_energies.append(e)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	await main.show_message("MOVED " + str(to_move.size()) + " ENERGY TO " + dest.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return
	print("POWER USED: ", team, " energy move")

# OVERHEAT (Camerupt ex4-19): once per turn, take a basic Energy from your discard and attach it to
# Camerupt; put 2 damage counters on Camerupt.
func power_ex4_overheat(camerupt: card_object) -> void:
	var is_opponent = camerupt.is_owner_opp(main)
	if is_power_blocked_by_status(camerupt):
		await main.show_message("OVERHEAT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if camerupt.power_used_this_turn:
		await main.show_message("OVERHEAT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var discard = main.opponent_discard_pile if is_opponent else main.player_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		await main.show_message("OVERHEAT: NO BASIC ENERGY IN YOUR DISCARD PILE!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = basics[0]
	else:
		chosen = await main.card_ops.choose_card(basics, false, "OVERHEAT", "Choose a basic Energy to attach to Camerupt", "ATTACH", false)
		if main._should_bail(): return
		if chosen == null: return
	camerupt.power_used_this_turn = true
	discard.erase(chosen)
	chosen.current_location = "attached"
	camerupt.attached_energies.append(chosen)
	camerupt.current_hp = max(0, camerupt.current_hp - 20)
	main.display_active_pokemon_energies(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_hp_circles_above_align(camerupt, is_opponent)
	main.update_discard_pile_display(is_opponent)
	await main.show_message("OVERHEAT! ATTACHED AN ENERGY AND PUT 2 DAMAGE COUNTERS ON CAMERUPT!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Overheat")

func cpu_ex4_overheat(camerupt: card_object) -> void:
	var discard = main.opponent_discard_pile
	var basics = discard.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		return
	await power_ex4_overheat(camerupt)

# AUXILIARY LIGHT (Lanturn ex4-28): once per turn, attach a basic Energy from your hand to Lanturn;
# put 2 damage counters on Lanturn.
func power_ex4_auxiliary_light(lanturn: card_object) -> void:
	var is_opponent = lanturn.is_owner_opp(main)
	if is_power_blocked_by_status(lanturn):
		await main.show_message("AUXILIARY LIGHT IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if lanturn.power_used_this_turn:
		await main.show_message("AUXILIARY LIGHT ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var hand = main.opponent_hand if is_opponent else main.player_hand
	var basics = hand.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		await main.show_message("AUXILIARY LIGHT: NO BASIC ENERGY IN YOUR HAND!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = basics[0]
	else:
		chosen = await main.card_ops.choose_card(basics, false, "AUXILIARY LIGHT", "Choose a basic Energy to attach to Lanturn", "ATTACH", false)
		if main._should_bail(): return
		if chosen == null: return
	lanturn.power_used_this_turn = true
	hand.erase(chosen)
	chosen.current_location = "attached"
	lanturn.attached_energies.append(chosen)
	lanturn.current_hp = max(0, lanturn.current_hp - 20)
	main.refresh_hand_display(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.display_pokemon(is_opponent)
	main.display_hp_circles_above_align(lanturn, is_opponent)
	await main.show_message("AUXILIARY LIGHT! ATTACHED AN ENERGY AND PUT 2 DAMAGE COUNTERS ON LANTURN!")
	if main._should_bail(): return
	await main.check_all_knockouts()
	if main._should_bail(): return
	print("POWER USED: Auxiliary Light")

func cpu_ex4_auxiliary_light(lanturn: card_object) -> void:
	var basics = main.opponent_hand.filter(func(c): return c.metadata.get("supertype","") == "Energy" and "Basic" in c.metadata.get("subtypes", []))
	if basics.is_empty():
		return
	await power_ex4_auxiliary_light(lanturn)

# CALL FOR HELP (Mightyena ex4-37): once per turn, if Mightyena is your Active Pokemon, search your
# deck for a Team Magma Pokemon and put it into your hand.
func power_ex4_call_for_help(mightyena: card_object) -> void:
	var is_opponent = mightyena.is_owner_opp(main)
	if is_power_blocked_by_status(mightyena):
		await main.show_message("CALL FOR HELP IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if mightyena.power_used_this_turn:
		await main.show_message("CALL FOR HELP ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var own_active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	if mightyena != own_active:
		await main.show_message("CALL FOR HELP ONLY WORKS WHILE MIGHTYENA IS ACTIVE!")
		if main._should_bail(): return
		return
	mightyena.power_used_this_turn = true
	var found = await main.card_ops.search_deck_to_hand(is_opponent, func(c): return c.metadata.get("supertype","") == "Pokémon" and "Team Magma" in c.metadata.get("name",""), "CALL FOR HELP: CHOOSE A TEAM MAGMA POKEMON", 1)
	if main._should_bail(): return
	await main.show_message("CALL FOR HELP! ADDED " + str(found.size()) + " POKEMON TO HAND!")
	if main._should_bail(): return
	print("POWER USED: Call for Help")

func cpu_ex4_call_for_help(mightyena: card_object) -> void:
	await power_ex4_call_for_help(mightyena)

func cpu_phase_ex4_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return

	var camerupt = _find_cpu_pokemon_with_power("Overheat")
	if camerupt != null and not camerupt.power_used_this_turn and not is_power_blocked_by_status(camerupt) and camerupt.current_hp > 20:
		await cpu_ex4_overheat(camerupt)
		if main._should_bail(): return

	var lanturn = _find_cpu_pokemon_with_power("Auxiliary Light")
	if lanturn != null and not lanturn.power_used_this_turn and not is_power_blocked_by_status(lanturn) and lanturn.current_hp > 20:
		await cpu_ex4_auxiliary_light(lanturn)
		if main._should_bail(): return

	var mightyena = _find_cpu_pokemon_with_power("Call for Help")
	if mightyena != null and main.opponent_active_pokemon == mightyena and not mightyena.power_used_this_turn and not is_power_blocked_by_status(mightyena):
		await cpu_ex4_call_for_help(mightyena)
		if main._should_bail(): return

# ══════════════════════════════════════════════════════════════════════════════
#  EX5 (EX Hidden Legends) — Poké-Powers & Poké-Bodies
#  Auto-working by existing name-based machinery (no ex5 code needed):
#    Strikes Back (Machoke ex5-41)   -> check_strikes_back
#    Safeguard (Ninetales ex5-22)    -> _hook_ex2_safeguard (damage from ex -> 0)
#    Deep Sleep (Relicanth ex5-24)   -> is_deep_sleep_active() + process_status_between_turns
#    Exoskeleton (Clamperl ex5-58 / Registeel ex ex5-99) -> _FLAT_REDUCTION_BODY_NAMES
#    Levitate (Beldum ex5-28 / Metang ex5-44) -> get_retreat_cost
#    Primal Pull (Claydol ex5-2) -> is_ex5_primal_pull_active() consulted in CPU_AI.get_unmet_energy_count
# ══════════════════════════════════════════════════════════════════════════════
func _register_ex5_powers() -> void:
	_power_dispatch["Metal Juncture"]        = func(p): await power_ex5_metal_juncture(p)
	_power_dispatch["Crush Draw"]            = func(p): await power_ex5_crush_draw(p)
	_power_dispatch["Heal Dance"]            = func(p): await power_ex5_heal_dance(p)
	_power_dispatch["Magnetic Call"]         = func(p): await power_ex5_magnetic_call(p)
	_power_dispatch["Temperamental Weather"] = func(p): await power_ex5_temperamental_weather(p)

# ── Passive damage-modifier bodies ────────────────────────────────────────────

# CRUST (Pinsir ex5-13): damage from the opponent's Basic Pokemon is reduced by 30 (after W/R).
func _hook_ex5_crust(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if not defender.has_ability("Crust") or is_power_blocked_by_status(defender):
		return damage
	if "Basic" in attacker.metadata.get("subtypes", []):
		modifiers.append("CRUST -30")
		return max(0, damage - 30)
	return damage

# ICE WALL (Glalie ex5-34): damage from an attacker with any Special Energy attached is reduced by 40.
func _hook_ex5_ice_wall(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null or attacker == null:
		return damage
	if not defender.has_ability("Ice Wall") or is_power_blocked_by_status(defender):
		return damage
	for e in attacker.attached_energies:
		if "Special" in e.metadata.get("subtypes", []):
			modifiers.append("ICE WALL -40")
			return max(0, damage - 40)
	return damage

# CORE GUARD (Staryu ex5-75): while a Psychic Energy is attached to Staryu, damage is reduced by 10.
func _hook_ex5_core_guard(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if not defender.has_ability("Core Guard") or is_power_blocked_by_status(defender):
		return damage
	for e in defender.attached_energies:
		if "Psychic" in main.get_energy_provided_by_card(e):
			modifiers.append("CORE GUARD -10")
			return max(0, damage - 10)
	return damage

# OVERZEALOUS (Machamp ex5-9): while the opponent has any Pokemon-ex in play, Machamp's attacks do 30
# more damage to the Defending Pokemon.
func _hook_ex5_overzealous(damage: int, attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or attacker == null or defender == null:
		return damage
	if not attacker.has_ability("Overzealous") or is_power_blocked_by_status(attacker):
		return damage
	var attacker_is_opp = attacker.is_owner_opp(main)
	for p in main.card_ops.get_all_pokemon_in_play(not attacker_is_opp):
		if main.is_ex_pokemon(p):
			modifiers.append("OVERZEALOUS +30")
			return damage + 30
	return damage

# SILVER WIND (Masquerain ex5-20): the marked Defending Pokemon takes 30 more from attacks during the
# marker's window (set by the Silver Wind attack; cleared at end of the opponent's turn).
func _hook_ex5_silver_wind(damage: int, _attacker: card_object, defender: card_object, modifiers: Array) -> int:
	if damage <= 0 or defender == null:
		return damage
	if defender.has_effect("ex5_silver_wind"):
		modifiers.append("SILVER WIND +30")
		return damage + 30
	return damage

# ── Passive body helpers wired into core hooks ────────────────────────────────

# MARK OF ANTIQUITY (Groudon ex ex5-93 / Kyogre ex ex5-94): while this is a side's Active Pokemon,
# each player's Kyogre ex / Groudon ex / Rayquaza ex can't attack (per the holder's ability text).
# Called from Main.get_attacks_for_card.
func check_ex5_mark_of_antiquity_blocks_attack(card: card_object) -> bool:
	if card == null:
		return false
	var cname = card.metadata.get("name", "")
	if cname not in ["Kyogre ex", "Groudon ex", "Rayquaza ex"]:
		return false
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active == null or active == card: continue
		if active.has_ability("Mark of Antiquity") and not is_power_blocked_by_status(active):
			var ab = active.get_ability("Mark of Antiquity")
			if ab != null and cname.to_lower() in ab.get("text","").to_lower():
				return true
	return false

# POWER DIFFUSION (Rhydon ex5-46): while Rhydon is a side's Active Pokemon, prevent all attack damage
# to that side's Benched Pokemon. Called from Card_Ops.apply_bench_damage.
func is_ex5_power_diffusion_active(bench_owner_is_opp: bool) -> bool:
	var active = main.opponent_active_pokemon if bench_owner_is_opp else main.player_active_pokemon
	if active == null: return false
	return active.has_ability("Power Diffusion") and not is_power_blocked_by_status(active)

# FREEFLOATING (Tentacool ex5-77): Retreat Cost is 0 while NO Energy is attached. Called from
# Main.get_retreat_cost.
func is_ex5_freefloating_free(pokemon: card_object) -> bool:
	if pokemon == null: return false
	if not pokemon.has_ability("Freefloating") or is_power_blocked_by_status(pokemon): return false
	return pokemon.attached_energies.is_empty()

# CRYSTAL BODY (Regice ex ex5-97): prevents all effects of attacks except damage. Checked in
# Card_Ops.apply_status (blocks Special Conditions from attacks — same depth as ecard3 Immunity).
func has_ex5_crystal_body(pokemon: card_object) -> bool:
	if pokemon == null: return false
	return pokemon.has_ability("Crystal Body") and not is_power_blocked_by_status(pokemon)

# PRIMAL PULL (Claydol ex5-2): while a Claydol with this Poké-Body is a side's Active Pokemon, each
# player's Evolved Pokemon pays Colorless more Energy to use its attacks. Consulted in
# CPU_AI.get_unmet_energy_count (the shared player+CPU attack-cost gate).
func is_ex5_primal_pull_active() -> bool:
	for side in [false, true]:
		var active = main.opponent_active_pokemon if side else main.player_active_pokemon
		if active != null and active.has_ability("Primal Pull") and not is_power_blocked_by_status(active):
			return true
	return false

# BLOCK DUST (Vileplume ex ex5-100): while Vileplume ex is a side's Active, that side's OPPONENT can't
# play non-Supporter Trainer cards. Mirrors Primal Lock but requires the blocker to be Active.
func is_ex5_block_dust_blocking(trainer_player_is_opp: bool) -> bool:
	var blocker_active = main.opponent_active_pokemon if not trainer_player_is_opp else main.player_active_pokemon
	if blocker_active == null: return false
	return blocker_active.has_ability("Block Dust") and not is_power_blocked_by_status(blocker_active)

# ── Reactive body: Energy Grounding (pre-KO hook) ─────────────────────────────

# ENERGY GROUNDING (Lanturn ex5-38): once per turn, when one of your Pokemon is Knocked Out by the
# opponent's attack, move a basic Energy that would be discarded from it onto Lanturn instead. Fires
# from the pre-KO hook (the KO'd Pokemon still holds its Energy). Auto-resolves (grabs one basic Energy).
func check_ex5_energy_grounding(pokemon: card_object, attacker: card_object, is_pokemon_opp: bool) -> void:
	if pokemon == null or attacker == null:
		return
	# Only trigger when the KO is caused by the opponent (the attacker is on the other side).
	if attacker.is_owner_opp(main) == is_pokemon_opp:
		return
	var lanturn: card_object = null
	for p in main.card_ops.get_all_pokemon_in_play(is_pokemon_opp):
		if p != pokemon and p.has_ability("Energy Grounding") and not p.power_used_this_turn and not is_power_blocked_by_status(p):
			lanturn = p
			break
	if lanturn == null:
		return
	var basic_e: card_object = null
	for e in pokemon.attached_energies:
		if "Basic" in e.metadata.get("subtypes", []):
			basic_e = e
			break
	if basic_e == null:
		return
	lanturn.power_used_this_turn = true
	pokemon.attached_energies.erase(basic_e)
	basic_e.current_location = "attached"
	lanturn.attached_energies.append(basic_e)
	main.display_active_pokemon_energies(is_pokemon_opp)
	main.display_pokemon(is_pokemon_opp)
	await main.show_message("ENERGY GROUNDING! A BASIC ENERGY WAS MOVED TO LANTURN!")
	if main._should_bail(): return

# ── Evolve-trigger power: Healing Shower ──────────────────────────────────────

# HEALING SHOWER (Milotic ex5-12): when you play Milotic to evolve one of your Pokemon, you may remove
# all damage counters from all Pokemon (both players', excluding Pokemon-ex). Called from
# Main.perform_evolution's on-evolve trigger chain.
func trigger_ex5_healing_shower(milotic: card_object, is_opponent: bool) -> void:
	if is_power_blocked_by_status(milotic):
		return
	var do_it = true
	if not is_opponent:
		do_it = await main.trainer_effects.gym1_prompt_yes_no(milotic, "HEALING SHOWER", "Remove all damage counters from all Pokemon (excluding Pokemon-ex)?", "YES", "NO")
		if main._should_bail(): return
	if not do_it:
		return
	for side in [false, true]:
		for p in main.card_ops.get_all_pokemon_in_play(side):
			if main.is_ex_pokemon(p): continue
			if p.current_hp < p.get_max_hp():
				p.current_hp = p.get_max_hp()
				main.display_hp_circles_above_align(p, side)
	main.display_pokemon(false)
	main.display_pokemon(true)
	await main.show_message("HEALING SHOWER! ALL DAMAGE COUNTERS REMOVED (EXCEPT POKEMON-EX)!")
	if main._should_bail(): return

# ── Active powers ─────────────────────────────────────────────────────────────

# METAL JUNCTURE (Metagross ex5-11): as often as you like, move a Metal Energy from one of your Benched
# Pokemon to your Active. Player-interactive; CPU skips (low heuristic value, like ex4 energy moves).
func power_ex5_metal_juncture(metagross: card_object) -> void:
	var is_opponent = metagross.is_owner_opp(main)
	if is_power_blocked_by_status(metagross):
		await main.show_message("METAL JUNCTURE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if is_opponent:
		return
	var active = main.player_active_pokemon
	if active == null:
		return
	var bench = main.player_bench
	var sources = bench.filter(func(p):
		for e in p.attached_energies:
			if "Metal" in main.get_energy_provided_by_card(e) and "Basic" in e.metadata.get("subtypes", []): return true
		return false)
	if sources.is_empty():
		await main.show_message("NO METAL ENERGY ON YOUR BENCH TO MOVE!")
		if main._should_bail(): return
		return
	var source = sources[0] if sources.size() == 1 else await main.card_ops.choose_card(sources, false, "METAL JUNCTURE", "Choose a Benched Pokemon to move Metal Energy FROM", "SELECT", true)
	if main._should_bail(): return
	if source == null: return
	var metal: card_object = null
	for e in source.attached_energies:
		if "Metal" in main.get_energy_provided_by_card(e) and "Basic" in e.metadata.get("subtypes", []):
			metal = e
			break
	if metal == null: return
	source.attached_energies.erase(metal)
	active.attached_energies.append(metal)
	main.display_pokemon(false)
	main.display_active_pokemon_energies(false)
	await main.show_message("METAL JUNCTURE! MOVED A METAL ENERGY TO YOUR ACTIVE!")
	if main._should_bail(): return

# CRUSH DRAW (Walrein ex5-15): once per turn, reveal the top card of your deck; if it is a basic Energy,
# attach it to 1 of your Pokemon; otherwise put it back.
func power_ex5_crush_draw(walrein: card_object) -> void:
	var is_opponent = walrein.is_owner_opp(main)
	if is_power_blocked_by_status(walrein):
		await main.show_message("CRUSH DRAW IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if walrein.power_used_this_turn:
		await main.show_message("CRUSH DRAW ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	if deck.is_empty():
		await main.show_message("CRUSH DRAW: YOUR DECK IS EMPTY!")
		if main._should_bail(): return
		return
	walrein.power_used_this_turn = true
	var top = deck[0]
	var is_basic_energy = top.metadata.get("supertype","") == "Energy" and "Basic" in top.metadata.get("subtypes", [])
	if not is_basic_energy:
		await main.show_message("CRUSH DRAW REVEALED " + top.metadata.get("name","").to_upper() + " — PUT BACK ON TOP!")
		if main._should_bail(): return
		return
	deck.erase(top)
	var target := walrein
	if not is_opponent:
		var mine = main.card_ops.get_all_pokemon_in_play(false)
		if mine.size() > 1:
			target = await main.card_ops.choose_card(mine, false, "CRUSH DRAW", "Choose a Pokemon to attach the Energy to", "ATTACH", false)
			if main._should_bail(): return
			if target == null: target = walrein
	top.current_location = "attached"
	target.attached_energies.append(top)
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("CRUSH DRAW! ATTACHED " + top.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return

# HEAL DANCE (Bellossom ex5-16): once per turn (at most 1 Heal Dance per turn across all copies),
# remove 2 damage counters from 1 of your Pokemon.
func power_ex5_heal_dance(bellossom: card_object) -> void:
	var is_opponent = bellossom.is_owner_opp(main)
	if is_power_blocked_by_status(bellossom):
		await main.show_message("HEAL DANCE IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var flag_owner_used = main.opponent_ex5_heal_dance_used if is_opponent else main.player_ex5_heal_dance_used
	if bellossom.power_used_this_turn or flag_owner_used:
		await main.show_message("HEAL DANCE ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var mine = main.card_ops.get_all_pokemon_in_play(is_opponent).filter(func(p): return p.current_hp < p.get_max_hp())
	if mine.is_empty():
		await main.show_message("NO DAMAGED POKEMON TO HEAL!")
		if main._should_bail(): return
		return
	var target: card_object
	if is_opponent:
		target = mine[0]
	else:
		target = await main.card_ops.choose_card(mine, false, "HEAL DANCE", "Choose a Pokemon to remove 2 damage counters from", "HEAL", false)
		if main._should_bail(): return
		if target == null: return
	bellossom.power_used_this_turn = true
	if is_opponent: main.opponent_ex5_heal_dance_used = true
	else: main.player_ex5_heal_dance_used = true
	await main.card_ops.heal_pokemon(target, 20, is_opponent)
	if main._should_bail(): return
	await main.show_message("HEAL DANCE! REMOVED 2 DAMAGE COUNTERS!")

# MAGNETIC CALL (Beldum ex5-29): once per turn, flip a coin; if heads, search deck for a Metal Basic
# Pokemon and put it on your Bench.
func power_ex5_magnetic_call(beldum: card_object) -> void:
	var is_opponent = beldum.is_owner_opp(main)
	if is_power_blocked_by_status(beldum):
		await main.show_message("MAGNETIC CALL IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	if beldum.power_used_this_turn:
		await main.show_message("MAGNETIC CALL ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var bench = main.opponent_bench if is_opponent else main.player_bench
	if bench.size() >= main.get_max_bench_size():
		await main.show_message("YOUR BENCH IS FULL!")
		if main._should_bail(): return
		return
	beldum.power_used_this_turn = true
	var coin = await main.flip_coin(false, is_opponent)
	if main._should_bail(): return
	if not coin:
		await main.show_message("MAGNETIC CALL — TAILS!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and "Basic" in c.metadata.get("subtypes", []) and "Metal" in c.metadata.get("types", []))
	if pool.is_empty():
		await main.show_message("NO METAL BASIC POKEMON IN YOUR DECK!")
		deck.shuffle()
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = pool[0]
	else:
		chosen = await main.card_ops.choose_card(pool, false, "MAGNETIC CALL", "Choose a Metal Basic Pokemon to put on your Bench", "SELECT", true)
		if main._should_bail(): return
		if chosen == null:
			deck.shuffle()
			return
	deck.erase(chosen)
	chosen.current_hp = chosen.get_max_hp()
	main.card_ops.place_on_bench(chosen, is_opponent)
	deck.shuffle()
	main.update_deck_icon(is_opponent)
	await main.show_message("MAGNETIC CALL! " + chosen.metadata.get("name","").to_upper() + " WAS PLACED ON THE BENCH!")
	if main._should_bail(): return

# TEMPERAMENTAL WEATHER (Castform line ex5-23/25/26/30): once per turn, search your deck for another
# named Castform form and switch it in for this one, carrying over all attachments, damage counters
# and Special Conditions; shuffle this Castform back into your deck.
func power_ex5_temperamental_weather(castform: card_object) -> void:
	var is_opponent = castform.is_owner_opp(main)
	if is_power_blocked_by_status(castform):
		await main.show_message("TEMPERAMENTAL WEATHER IS BLOCKED BY STATUS!")
		if main._should_bail(): return
		return
	var flag_used = main.opponent_ex5_weather_used if is_opponent else main.player_ex5_weather_used
	if castform.power_used_this_turn or flag_used:
		await main.show_message("TEMPERAMENTAL WEATHER ALREADY USED THIS TURN!")
		if main._should_bail(): return
		return
	var deck = main.opponent_deck if is_opponent else main.player_deck
	var forms = ["Castform", "Rain Castform", "Sunny Castform", "Snow-cloud Castform"]
	var pool = deck.filter(func(c): return c.metadata.get("supertype","") == "Pokémon" and c.metadata.get("name","") in forms and c.metadata.get("name","") != castform.metadata.get("name",""))
	if pool.is_empty():
		await main.show_message("NO OTHER CASTFORM IN YOUR DECK!")
		if main._should_bail(): return
		return
	var chosen: card_object
	if is_opponent:
		chosen = pool[0]
	else:
		chosen = await main.card_ops.choose_card(pool, false, "TEMPERAMENTAL WEATHER", "Choose a Castform to switch in", "SELECT", true)
		if main._should_bail(): return
		if chosen == null: return
	castform.power_used_this_turn = true
	if is_opponent: main.opponent_ex5_weather_used = true
	else: main.player_ex5_weather_used = true
	# Carry over runtime state to the incoming Castform.
	chosen.attached_energies = castform.attached_energies.duplicate()
	chosen.attached_pre_evolutions = castform.attached_pre_evolutions.duplicate()
	chosen.attached_cards = castform.attached_cards.duplicate()
	var max_hp_new = chosen.get_max_hp()
	var damage_taken = castform.get_max_hp() - castform.current_hp
	chosen.current_hp = max(1, max_hp_new - damage_taken)
	chosen.special_condition = castform.special_condition
	chosen.is_poisoned = castform.is_poisoned
	chosen.poison_damage = castform.poison_damage
	chosen.is_burned = castform.is_burned
	chosen.placed_on_field_this_turn = castform.placed_on_field_this_turn
	# Swap positions.
	var active = main.opponent_active_pokemon if is_opponent else main.player_active_pokemon
	var bench = main.opponent_bench if is_opponent else main.player_bench
	deck.erase(chosen)
	if castform == active:
		if is_opponent: main.opponent_active_pokemon = chosen
		else: main.player_active_pokemon = chosen
		chosen.current_location = "active"
	else:
		var idx = bench.find(castform)
		if idx != -1:
			bench[idx] = chosen
			chosen.current_location = "bench"
	castform.attached_energies.clear()
	castform.attached_pre_evolutions.clear()
	castform.attached_cards.clear()
	castform.current_hp = castform.get_max_hp()
	main.clear_all_statuses(castform, is_opponent)
	castform.current_location = "deck"
	deck.append(castform)
	deck.shuffle()
	main.display_pokemon(is_opponent)
	main.display_active_pokemon_energies(is_opponent)
	main.update_deck_icon(is_opponent)
	await main.show_message("TEMPERAMENTAL WEATHER! SWITCHED TO " + chosen.metadata.get("name","").to_upper() + "!")
	if main._should_bail(): return

# ── CPU phase for ex5 active powers ───────────────────────────────────────────
func cpu_phase_ex5_powers() -> void:
	if is_toxic_gas_active() or main.goop_gas_active: return
	var walrein = _find_cpu_pokemon_with_power("Crush Draw")
	if walrein != null and not walrein.power_used_this_turn and not is_power_blocked_by_status(walrein):
		await power_ex5_crush_draw(walrein)
		if main._should_bail(): return
	var beldum = _find_cpu_pokemon_with_power("Magnetic Call")
	if beldum != null and not beldum.power_used_this_turn and not is_power_blocked_by_status(beldum):
		await power_ex5_magnetic_call(beldum)
		if main._should_bail(): return
	var bellossom = _find_cpu_pokemon_with_power("Heal Dance")
	if bellossom != null and not bellossom.power_used_this_turn and not main.opponent_ex5_heal_dance_used and not is_power_blocked_by_status(bellossom):
		# Only bother if something is damaged.
		for p in main.card_ops.get_all_pokemon_in_play(true):
			if p.current_hp < p.get_max_hp():
				await power_ex5_heal_dance(bellossom)
				break
		if main._should_bail(): return