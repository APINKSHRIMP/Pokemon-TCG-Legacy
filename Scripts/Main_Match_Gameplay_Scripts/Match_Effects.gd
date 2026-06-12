extends Node

# ═══════════════════════════════════════════════════════════════════════════════════════════
# MATCH EFFECTS — opponent-defined, match-wide rule modifiers.
#
# Opponent entries in NPC_and_Opponent_Data/*.json may carry a "match_effects" array,
# sibling of "restrictions":
#
#   "match_effects": [
#     {"type": "<effect>", "applies_to": "both"|"player"|"opponent", ...params}
#   ]
#
# "applies_to" is optional (default "both"); "player" = the human, "opponent" = the CPU.
# For offensive effects applies_to selects whose ATTACKS/ACTIONS are affected; for
# defensive effects (type_damage_reduction, no_status_effects, max_hp_modifier,
# end_of_turn_heal, no_healing, healing_multiplier) it selects whose POKEMON are affected.
# Unknown types are warned and ignored. Additive effects stack; override effects
# (coin_flip_override, draw_count, opening_hand_size, bench_size_limit, trainer_discard_cost,
# extra_energy_per_turn) — the LAST matching entry in the array wins.
#
# Supported effect types:
#   type_damage_bonus        {pokemon_type:"Fire", amount:20}   that type deals +X attack damage
#   ignore_weakness          {}                                 weakness skipped in damage calc
#   ignore_resistance        {}                                 resistance skipped in damage calc
#   ignore_weakness_and_resistance {}                           both skipped
#   no_retreat               {}                                 retreating is blocked
#   free_retreat             {}                                 retreating costs no energy
#   retreat_cost_modifier    {amount:1}                         added to retreat cost (floor 0)
#   evolved_damage_bonus     {amount:10}                        evolved pokemon deal +X
#   stage_damage_bonus       {basic:0, stage1:10, stage2:20}    per-stage flat attack bonus
#   draw_count               {count:2}                          draw N at turn start instead of 1
#   zero_attack_damage       {}                                 all raw attack damage becomes 0
#   no_healing               {}                                 all healing blocked
#   healing_multiplier       {multiplier:2}                     all healing scaled
#   type_damage_reduction    {pokemon_type:"Grass", amount:20}  damage TO that type reduced by X
#   double_prizes            {}                                 every KO awards 2 prizes
#   powers_blocked           {}                                 all Powers/Bodies off (always both sides)
#   raw_damage_only          {}                                 attacks lose effects; "20x"/"10+" flatten to 20/10
#   rainbow_energy           {}                                 every energy provides any type (DCE provides 2)
#   trainer_discard_cost     {count:1}                          discard N from hand to play a trainer
#   end_of_turn_heal         {amount:10}                        all in-play pokemon heal X at end of turn
#   no_status_effects        {}                                 special conditions cannot be applied
#   coin_flip_override       {result:"heads"|"tails"}           every coin flip forced
#   energy_attach_full_heal  {}                                 attaching energy fully heals that pokemon
#   energy_attach_halve_hp   {}                                 attaching energy halves HP (round up to 10s, min 10)
#   evolve_full_heal         {}                                 evolving fully heals the pokemon
#   extra_energy_per_turn    {count:2}                          may attach N energy per turn
#   max_hp_modifier          {amount:20}                        all pokemon max HP +/-X (floor 10)
#   poison_damage_multiplier {multiplier:2}                     poison tick damage scaled
#   bench_size_limit         {size:3}                           max bench size
#   opening_hand_size        {count:5}                          opening hand is N cards
#
# Interaction rules:
#   - no_healing beats all healing (multiplier, end-of-turn, attach/evolve full heals).
#   - zero_attack_damage is applied LAST in damage calc and wins over all bonuses.
#   - no_retreat beats free_retreat.
#   - Conflicting coin_flip_override entries: last in array wins. Forced flips disable
#     Sabrina's ESP re-flip.
#   - double_prizes multiplies after the no_prize_on_ko filter (bench tokens still give 0).
# ═══════════════════════════════════════════════════════════════════════════════════════════

var main: Node
var effects: Array = []

const KNOWN_TYPES := [
	"type_damage_bonus", "ignore_weakness", "ignore_resistance", "ignore_weakness_and_resistance",
	"no_retreat", "free_retreat", "retreat_cost_modifier", "evolved_damage_bonus",
	"stage_damage_bonus", "draw_count", "zero_attack_damage", "no_healing", "healing_multiplier",
	"type_damage_reduction", "double_prizes", "powers_blocked", "raw_damage_only", "rainbow_energy",
	"trainer_discard_cost", "end_of_turn_heal", "no_status_effects", "coin_flip_override",
	"energy_attach_full_heal", "energy_attach_halve_hp", "evolve_full_heal", "extra_energy_per_turn",
	"max_hp_modifier", "poison_damage_multiplier", "bench_size_limit", "opening_hand_size",
]

# ── Setup ─────────────────────────────────────────────────────────────────────────────────

# Parse and validate the match_effects array from the opponent's JSON entry.
func initialize(opp_data: Dictionary) -> void:
	effects = []
	var raw = opp_data.get("match_effects", [])
	if not raw is Array:
		push_warning("match_effects must be an Array — got %s; ignoring." % typeof(raw))
		return
	for entry in raw:
		if not entry is Dictionary or not entry.has("type"):
			push_warning("match_effects entry missing 'type': %s" % str(entry))
			continue
		var etype: String = str(entry["type"])
		if etype not in KNOWN_TYPES:
			push_warning("Unknown match_effects type '%s' — ignored." % etype)
			continue
		var normalized: Dictionary = entry.duplicate()
		var applies = str(entry.get("applies_to", "both"))
		if applies not in ["both", "player", "opponent"]:
			push_warning("match_effects '%s' has invalid applies_to '%s' — using 'both'." % [etype, applies])
			applies = "both"
		normalized["applies_to"] = applies
		effects.append(normalized)

func has_any() -> bool:
	return effects.size() > 0

# ── Internal helpers ──────────────────────────────────────────────────────────────────────

# Does this effect entry apply to the given side? (is_opponent true = the CPU side)
func _applies(effect: Dictionary, is_opponent: bool) -> bool:
	match effect["applies_to"]:
		"both": return true
		"player": return not is_opponent
		"opponent": return is_opponent
	return false

# All effects of a type that apply to a side, in array order.
func _matching(etype: String, is_opponent: bool) -> Array:
	var out := []
	for e in effects:
		if e["type"] == etype and _applies(e, is_opponent):
			out.append(e)
	return out

# True if any effect of the type applies to the side.
func _active(etype: String, is_opponent: bool) -> bool:
	return _matching(etype, is_opponent).size() > 0

# Last matching entry's numeric param, or the fallback (for override-style effects).
func _last_value(etype: String, is_opponent: bool, key: String, fallback: float) -> float:
	var hits := _matching(etype, is_opponent)
	if hits.size() == 0:
		return fallback
	return float(hits[hits.size() - 1].get(key, fallback))

# True if the card is on the CPU's side of the field.
func is_card_on_opponent_side(card) -> bool:
	return card == main.opponent_active_pokemon or card in main.opponent_bench

# ── Damage (called from calculate_final_damage) ───────────────────────────────────────────

# Flat attack damage bonus from type/evolved/stage effects for this attacker.
func attack_damage_bonus(attacker, attacker_is_opponent: bool) -> int:
	if attacker == null or attacker.metadata == null:
		return 0
	var bonus := 0
	var attacker_types: Array = attacker.metadata.get("types", [])

	for e in _matching("type_damage_bonus", attacker_is_opponent):
		if str(e.get("pokemon_type", "")) in attacker_types:
			bonus += int(e.get("amount", 0))

	var is_basic: bool = main.is_basic_pokemon(attacker)
	if not is_basic:
		for e in _matching("evolved_damage_bonus", attacker_is_opponent):
			bonus += int(e.get("amount", 0))

	for e in _matching("stage_damage_bonus", attacker_is_opponent):
		var subtypes: Array = attacker.metadata.get("subtypes", [])
		if is_basic:
			bonus += int(e.get("basic", 0))
		elif "Stage 2" in subtypes or "Stage2" in subtypes:
			bonus += int(e.get("stage2", 0))
		elif "Stage 1" in subtypes or "Stage1" in subtypes:
			bonus += int(e.get("stage1", 0))
	return bonus

# Flat reduction for damage dealt TO this defender (type_damage_reduction).
func damage_reduction_for(defender, defender_is_opponent: bool) -> int:
	if defender == null or defender.metadata == null:
		return 0
	var reduction := 0
	var defender_types: Array = defender.metadata.get("types", [])
	for e in _matching("type_damage_reduction", defender_is_opponent):
		if str(e.get("pokemon_type", "")) in defender_types:
			reduction += int(e.get("amount", 0))
	return reduction

func zero_attack_damage(attacker_is_opponent: bool) -> bool:
	return _active("zero_attack_damage", attacker_is_opponent)

func ignore_weakness(attacker_is_opponent: bool) -> bool:
	return _active("ignore_weakness", attacker_is_opponent) \
		or _active("ignore_weakness_and_resistance", attacker_is_opponent)

func ignore_resistance(attacker_is_opponent: bool) -> bool:
	return _active("ignore_resistance", attacker_is_opponent) \
		or _active("ignore_weakness_and_resistance", attacker_is_opponent)

# "Global" variants for damage calls that don't know the attacker (CPU planning):
# only true when the effect applies to both sides, so planning never sees a one-sided rule.
func ignore_weakness_global() -> bool:
	return ignore_weakness(true) and ignore_weakness(false)

func ignore_resistance_global() -> bool:
	return ignore_resistance(true) and ignore_resistance(false)

func raw_damage_only(attacker_is_opponent: bool) -> bool:
	return _active("raw_damage_only", attacker_is_opponent)

# ── Healing ───────────────────────────────────────────────────────────────────────────────

# Single gate all healing funnels through: 0 when blocked, else scaled by multiplier(s).
func modify_heal_amount(amount: int, target_is_opponent: bool) -> int:
	if amount <= 0:
		return 0
	if healing_blocked(target_is_opponent):
		return 0
	var scaled := float(amount)
	for e in _matching("healing_multiplier", target_is_opponent):
		scaled *= float(e.get("multiplier", 1))
	return int(round(scaled))

func healing_blocked(target_is_opponent: bool) -> bool:
	return _active("no_healing", target_is_opponent)

func end_of_turn_heal_amount(side_is_opponent: bool) -> int:
	var total := 0
	for e in _matching("end_of_turn_heal", side_is_opponent):
		total += int(e.get("amount", 0))
	return total

# ── Turn flow ─────────────────────────────────────────────────────────────────────────────

func turn_start_draw_count(is_opponent: bool) -> int:
	return max(1, int(_last_value("draw_count", is_opponent, "count", 1)))

# Returns -1 when no override (caller uses the normal opening hand size).
func opening_hand_size(is_opponent: bool) -> int:
	return int(_last_value("opening_hand_size", is_opponent, "count", -1))

# ── Retreat ───────────────────────────────────────────────────────────────────────────────

func retreat_blocked(is_opponent: bool) -> bool:
	return _active("no_retreat", is_opponent)

func retreat_is_free(is_opponent: bool) -> bool:
	return _active("free_retreat", is_opponent)

func retreat_cost_modifier(is_opponent: bool) -> int:
	var total := 0
	for e in _matching("retreat_cost_modifier", is_opponent):
		total += int(e.get("amount", 0))
	return total

# ── Prizes / powers / status / coins ──────────────────────────────────────────────────────

# Prizes the KO-taker receives per knockout (applies_to selects whose KOs are doubled).
func prizes_per_ko(taker_is_opponent: bool) -> int:
	return 2 if _active("double_prizes", taker_is_opponent) else 1

# Global gate (applies_to intentionally ignored — powers are a shared system).
func powers_blocked() -> bool:
	for e in effects:
		if e["type"] == "powers_blocked":
			return true
	return false

func status_blocked(target_is_opponent: bool) -> bool:
	return _active("no_status_effects", target_is_opponent)

func poison_tick_damage(base: int, victim_is_opponent: bool) -> int:
	var scaled := float(base)
	for e in _matching("poison_damage_multiplier", victim_is_opponent):
		scaled *= float(e.get("multiplier", 1))
	return int(round(scaled))

# "" = no override; otherwise "heads"/"tails". Last matching entry wins.
func coin_override(flipper_is_opponent: bool) -> String:
	var hits := _matching("coin_flip_override", flipper_is_opponent)
	if hits.size() == 0:
		return ""
	var result = str(hits[hits.size() - 1].get("result", "")).to_lower()
	if result in ["heads", "tails"]:
		return result
	return ""

# ── Energy / evolution / trainers ─────────────────────────────────────────────────────────

func rainbow_energy_active(owner_is_opponent: bool) -> bool:
	return _active("rainbow_energy", owner_is_opponent)

func energy_attach_limit(is_opponent: bool) -> int:
	return max(1, int(_last_value("extra_energy_per_turn", is_opponent, "count", 1)))

func energy_attach_full_heal(is_opponent: bool) -> bool:
	return _active("energy_attach_full_heal", is_opponent)

func energy_attach_halve_hp(is_opponent: bool) -> bool:
	return _active("energy_attach_halve_hp", is_opponent)

# Halve HP rounding half UP to the nearest 10, never below 10 (50 -> 30, 70 -> 40).
static func halve_hp_round_up_10(hp: int) -> int:
	return max(10, int(ceil(hp / 20.0)) * 10)

func evolve_full_heal(is_opponent: bool) -> bool:
	return _active("evolve_full_heal", is_opponent)

func trainer_discard_cost(is_opponent: bool) -> int:
	return max(0, int(_last_value("trainer_discard_cost", is_opponent, "count", 0)))

# ── Field-wide extras ─────────────────────────────────────────────────────────────────────

func max_hp_modifier(side_is_opponent: bool) -> int:
	var total := 0
	for e in _matching("max_hp_modifier", side_is_opponent):
		total += int(e.get("amount", 0))
	return total

# -1 = no override.
func max_bench_size_override() -> int:
	var limit := -1
	for e in effects:
		if e["type"] == "bench_size_limit":
			limit = int(e.get("size", -1))
	return limit

# ── Announcement ──────────────────────────────────────────────────────────────────────────

# One human-readable uppercase line per effect, shown at the start of each game.
func get_announcement_lines() -> Array:
	var lines := []
	for e in effects:
		var line := _describe_effect(e)
		if line == "":
			continue
		match e["applies_to"]:
			"player":
				line += " (YOUR SIDE ONLY)"
			"opponent":
				line += " (OPPONENT'S SIDE ONLY)"
		lines.append(line + "!")
	return lines

func _describe_effect(e: Dictionary) -> String:
	match e["type"]:
		"type_damage_bonus":
			return "%s POKEMON DEAL +%d ATTACK DAMAGE" % [str(e.get("pokemon_type", "?")).to_upper(), int(e.get("amount", 0))]
		"ignore_weakness":
			return "ATTACKS IGNORE WEAKNESS"
		"ignore_resistance":
			return "ATTACKS IGNORE RESISTANCE"
		"ignore_weakness_and_resistance":
			return "ATTACKS IGNORE WEAKNESS AND RESISTANCE"
		"no_retreat":
			return "POKEMON CANNOT RETREAT"
		"free_retreat":
			return "ALL RETREATS ARE FREE"
		"retreat_cost_modifier":
			var amt := int(e.get("amount", 0))
			if amt >= 0:
				return "RETREATING COSTS %d MORE ENERGY" % amt
			return "RETREATING COSTS %d LESS ENERGY" % -amt
		"evolved_damage_bonus":
			return "EVOLVED POKEMON DEAL +%d DAMAGE" % int(e.get("amount", 0))
		"stage_damage_bonus":
			var parts := []
			if int(e.get("basic", 0)) != 0:
				parts.append("BASIC +%d" % int(e.get("basic", 0)))
			if int(e.get("stage1", 0)) != 0:
				parts.append("STAGE 1 +%d" % int(e.get("stage1", 0)))
			if int(e.get("stage2", 0)) != 0:
				parts.append("STAGE 2 +%d" % int(e.get("stage2", 0)))
			return "POKEMON DEAL BONUS DAMAGE: " + ", ".join(parts)
		"draw_count":
			return "DRAW %d CARDS AT THE START OF EACH TURN" % int(e.get("count", 1))
		"zero_attack_damage":
			return "ATTACKS DEAL NO DAMAGE - ONLY EFFECTS APPLY"
		"no_healing":
			return "NO HEALING ALLOWED"
		"healing_multiplier":
			if float(e.get("multiplier", 1)) == 2.0:
				return "ALL HEALING IS DOUBLED"
			return "ALL HEALING IS x%s" % str(e.get("multiplier", 1))
		"type_damage_reduction":
			return "%s POKEMON TAKE %d LESS DAMAGE" % [str(e.get("pokemon_type", "?")).to_upper(), int(e.get("amount", 0))]
		"double_prizes":
			return "EVERY KNOCKOUT AWARDS 2 PRIZE CARDS"
		"powers_blocked":
			return "ALL POKEMON POWERS ARE BLOCKED"
		"raw_damage_only":
			return "ATTACKS HAVE NO EFFECTS - ONLY PRINTED DAMAGE"
		"rainbow_energy":
			return "EVERY ENERGY COUNTS AS ANY TYPE"
		"trainer_discard_cost":
			var cost := int(e.get("count", 1))
			if cost == 1:
				return "DISCARD 1 CARD TO PLAY A TRAINER"
			return "DISCARD %d CARDS TO PLAY A TRAINER" % cost
		"end_of_turn_heal":
			return "ALL POKEMON HEAL %d HP AT THE END OF EACH TURN" % int(e.get("amount", 0))
		"no_status_effects":
			return "SPECIAL CONDITIONS CANNOT BE APPLIED"
		"coin_flip_override":
			return "EVERY COIN FLIP LANDS ON %s" % str(e.get("result", "heads")).to_upper()
		"energy_attach_full_heal":
			return "ATTACHING ENERGY FULLY HEALS THAT POKEMON"
		"energy_attach_halve_hp":
			return "ATTACHING ENERGY HALVES THAT POKEMON'S HP"
		"evolve_full_heal":
			return "EVOLVING FULLY HEALS THE POKEMON"
		"extra_energy_per_turn":
			return "YOU MAY ATTACH %d ENERGY PER TURN" % int(e.get("count", 2))
		"max_hp_modifier":
			var amt := int(e.get("amount", 0))
			if amt >= 0:
				return "ALL POKEMON HAVE +%d MAX HP" % amt
			return "ALL POKEMON HAVE %d MAX HP" % amt
		"poison_damage_multiplier":
			if float(e.get("multiplier", 1)) == 2.0:
				return "POISON DAMAGE IS DOUBLED"
			return "POISON DAMAGE IS x%s" % str(e.get("multiplier", 1))
		"bench_size_limit":
			return "BENCH IS LIMITED TO %d POKEMON" % int(e.get("size", 5))
		"opening_hand_size":
			return "OPENING HANDS ARE %d CARDS" % int(e.get("count", 7))
	return ""
