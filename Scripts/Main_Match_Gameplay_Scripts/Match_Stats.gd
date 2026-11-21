class_name MatchStats
extends RefCounted

# ============================================================
# MATCH STATS - what the player did in ONE match, for the League Point bonuses (League.compute_final) and anything
# else that wants to know. Owned by the match script (`league_stats`); poll() runs every frame from its _process and
# the hooks below are the only other touch points:
#   note_attack_damage   display_and_apply_attack_damage      note_flip   flip_coin (the player's own flips)
#   note_knockout        check_and_handle_knockout            mark_status_ko   process_status_between_turns
# Everything else is read off the board by polling (bench, Prize counts, healing, evolutions, status conditions), so
# no effect script needs to know about it.
# ============================================================

var max_damage := 0
var bench_ever := false
var max_behind := 0
var max_prizes_turn := 0
var healed := 0
var evo_baby := 0
var evo_stage1 := 0
var evo_stage2 := 0
var sniper_kos := 0
var poison_kos := 0
var burn_kos := 0
var confusion_kos := 0
var inflicts := {"Confused": 0, "Paralyzed": 0, "Asleep": 0, "Poisoned": 0}
var flips_heads := 0
var flips_total := 0

var _damage_seen: Dictionary = {}     # the player's Pokemon: instance id -> damage taken
var _instances_seen: Dictionary = {}  # the player's Pokemon ever seen (an unseen one WITH pre-evolutions just evolved)
var _opp_status: Dictionary = {}      # the opponent's Pokemon: instance id -> {"cond", "poison"}
var _status_ko: Dictionary = {}       # instance id -> "poison" / "burn"
var _turn_seen := -1
var _turn_start_prizes := 0


# ── Polling ───────────────────────────────────────────────────────────────────────────────────

func poll(m: Node) -> void:
	if m.game_is_over or m.card_ops == null:
		return
	if m.player_bench.size() > 0:
		bench_ever = true
	# Prize cards: taken in one turn, and how far behind the player has been
	var p: int = m.player_prize_cards.size()
	var o: int = m.opponent_prize_cards.size()
	if m.turn_number != _turn_seen:
		_turn_seen = m.turn_number
		_turn_start_prizes = p
	max_prizes_turn = maxi(max_prizes_turn, _turn_start_prizes - p)
	var sp: int = m._medal_player_start_prizes
	var so: int = m._medal_opp_start_prizes
	if sp > 0 and so > 0:
		max_behind = maxi(max_behind, (so - o) - (sp - p))
	# The player's Pokemon: healing, evolutions
	var live := {}
	for pk in m.card_ops.get_all_pokemon_in_play(false):
		if pk == null:
			continue
		var id: int = pk.get_instance_id()
		live[id] = true
		var dmg: int = pk.get_max_hp() - pk.current_hp
		if _damage_seen.has(id) and dmg < int(_damage_seen[id]) and pk.current_hp > 0:
			healed += int(_damage_seen[id]) - dmg
		_damage_seen[id] = dmg
		if not _instances_seen.has(id):
			_instances_seen[id] = true
			if pk.attached_pre_evolutions.size() > 0:
				_note_evolution(pk)
	for id in _damage_seen.keys():
		if not live.has(id):
			_damage_seen.erase(id)
	# The opponent's Pokemon: conditions inflicted on them
	var opp_live := {}
	for pk in m.card_ops.get_all_pokemon_in_play(true):
		if pk == null:
			continue
		var id2: int = pk.get_instance_id()
		opp_live[id2] = true
		var cond: String = String(pk.special_condition)
		var poisoned: bool = bool(pk.is_poisoned)
		if _opp_status.has(id2):
			var old: Dictionary = _opp_status[id2]
			if cond != String(old["cond"]) and inflicts.has(cond):
				inflicts[cond] = int(inflicts[cond]) + 1
			if poisoned and not bool(old["poison"]):
				inflicts["Poisoned"] = int(inflicts["Poisoned"]) + 1
		_opp_status[id2] = {"cond": cond, "poison": poisoned}
	for id2 in _opp_status.keys():
		if not opp_live.has(id2):
			_opp_status.erase(id2)


func _note_evolution(evo: Object) -> void:
	var base = evo.attached_pre_evolutions.back()
	var base_types: Array = base.metadata.get("subtypes", []) if base != null else []
	var types: Array = evo.metadata.get("subtypes", [])
	if "Baby" in base_types:
		evo_baby += 1
	elif "Stage 2" in types:
		evo_stage2 += 1
	elif "Stage 1" in types:
		evo_stage1 += 1


# ── Hooks ─────────────────────────────────────────────────────────────────────────────────────

func note_attack_damage(damage: int) -> void:
	max_damage = maxi(max_damage, damage)


## The player's own flips (a match rule that forces the result is not luck - the caller skips those).
func note_flip(heads: bool) -> void:
	flips_total += 1
	if heads:
		flips_heads += 1


## A Pokemon was just Knocked Out. `was_bench`: it was on the bench (a snipe).
func note_knockout(pokemon: Object, is_opponent: bool, was_bench: bool) -> void:
	if not is_opponent:
		return
	if was_bench:
		sniper_kos += 1
	var id: int = pokemon.get_instance_id()
	match String(_status_ko.get(id, "")):
		"poison": poison_kos += 1
		"burn": burn_kos += 1
		"confusion": confusion_kos += 1


## Between-turns damage (or Confusion self-damage, kind "confusion") just took this Pokemon to 0 HP: its Knock Out is the status's doing.
func mark_status_ko(pokemon: Object, kind: String) -> void:
	_status_ko[pokemon.get_instance_id()] = kind


# ── Result ────────────────────────────────────────────────────────────────────────────────────

## The raw stats of this match, for League.compute_final.
func to_dict(m: Node) -> Dictionary:
	var type_specialist := false
	for key in m._medal_archetypes:
		if String(key).begins_with("type:"):
			type_specialist = true
	var active = m.player_active_pokemon
	return {
		"max_damage": max_damage,
		"bench_ever": bench_ever,
		"max_behind": max_behind,
		"active_hp": active.current_hp if active != null else 999,
		"bench_count_end": m.player_bench.size(),
		"max_prizes_turn": max_prizes_turn,
		"healed": healed,
		"type_specialist": type_specialist,
		"deck_out": m._medal_deckout_win,
		"flawless": m._medal_opp_start_prizes > 0 and m.opponent_prize_cards.size() == m._medal_opp_start_prizes,
		"opp_prizes_start": m._medal_opp_start_prizes,
		"turn": m.turn_number,
		"sniper_kos": sniper_kos,
		"evo_baby": evo_baby,
		"evo_stage1": evo_stage1,
		"evo_stage2": evo_stage2,
		"poison_kos": poison_kos,
		"burn_kos": burn_kos,
		"confusion_kos": confusion_kos,
		"inflicts": inflicts.duplicate(),
		"flips_heads": flips_heads,
		"flips_total": flips_total,
	}
