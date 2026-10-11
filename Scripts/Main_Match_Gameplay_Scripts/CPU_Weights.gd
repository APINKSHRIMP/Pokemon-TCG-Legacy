extends RefCounted
## ISSUE #375 (self-play tuning): every tunable number in CPU_AI.gd is read through CpuWeights.g(key, default).
## The value used is default × multiplier — 1.0 means "as written in the code", so a missing key is always safe.
##
## Multipliers come from res://NPC_and_Opponent_Data/CPU_Weights.json ({"key": multiplier, ...}) — the shipped,
## tuned values. The autotester's --tune mode replaces them per process with the candidate being tested
## (set_multipliers). The tuner (Tools/cpu_tuner.py) finds every key by scanning CPU_AI.gd for CpuWeights.g("...").

const SHIPPED_PATH := "res://NPC_and_Opponent_Data/CPU_Weights.json"

static var _mult: Dictionary = {}
static var _loaded := false


static func g(key: String, default_value: float) -> float:
	if not _loaded:
		_load_shipped()
	return default_value * float(_mult.get(key, 1.0))


## A yes/no CPU rule (ISSUE #375 rule audit): on unless its multiplier is set below 0.5 ("rule.x": 0 switches it off).
static func on(key: String) -> bool:
	return g(key, 1.0) >= 0.5


# ── Branch replay (ISSUE #375, lab only) ── every real CPU choice is counted; the lab replays a match with choice number
# branch_target replaced by a random alternative, then compares the result with the unbranched match on the same seed.
static var branch_target := -1
static var branch_counter := 0
static var branch_record: Dictionary = {}
static var _branch_rng := RandomNumberGenerator.new()

static func branch_reset(target: int, s: int) -> void:
	branch_target = target
	branch_counter = 0
	branch_record = {}
	_branch_rng.seed = s

## Returns the option to take: `chosen` normally, a random other option when this is the targeted choice.
static func branch_point(kind: String, n: int, chosen: int, labels: Array = []) -> int:
	if n < 2 or chosen < 0 or chosen >= n:
		return chosen
	branch_counter += 1
	if branch_counter != branch_target:
		return chosen
	var alt := _branch_rng.randi() % (n - 1)
	if alt >= chosen:
		alt += 1
	branch_record = {"kind": kind, "n": n, "chosen": chosen, "alt": alt, "k": branch_counter,
		"labels": labels.map(func(x): return str(x))}
	return alt

## True straight after branch_point() took the alternative and before its context was recorded.
static func needs_branch_ctx() -> bool:
	return not branch_record.is_empty() and int(branch_record.get("k", -1)) == branch_counter and not branch_record.has("ctx")


static func set_multipliers(m: Dictionary) -> void:
	_mult = m.duplicate()
	_loaded = true


# ── Learned card synergy (ISSUE #375) ── {"uid_a": {"uid_b": points}} — symmetric; positive = these two win more
# together than apart. Built by the tuner from self-play; shipped copy in res://NPC_and_Opponent_Data/CPU_Synergy.json.
const SHIPPED_SYNERGY_PATH := "res://NPC_and_Opponent_Data/CPU_Synergy.json"
static var _syn: Dictionary = {}
static var _syn_loaded := false

static func synergy() -> Dictionary:
	if not _syn_loaded:
		_syn_loaded = true
		if FileAccess.file_exists(SHIPPED_SYNERGY_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_SYNERGY_PATH))
			if parsed is Dictionary:
				_syn = parsed
	return _syn

static func set_synergy(table: Dictionary) -> void:
	_syn = table
	_syn_loaded = true


# ── Exploration (tuner only) ── with probability explore_rate a free "fetch a card" choice is made at random, so
# self-play tries combinations the CPU would never pick. Seeded per match, so a match stays reproducible.
static var explore_rate := 0.0
static var _explore_rng := RandomNumberGenerator.new()

static func seed_explore(s: int) -> void:
	_explore_rng.seed = s

## A random element of pool when exploring this decision, else null (= decide normally).
static func explore_pick(pool: Array):
	if explore_rate <= 0.0 or pool.is_empty() or _explore_rng.randf() >= explore_rate:
		return null
	return pool[_explore_rng.randi() % pool.size()]


static func _load_shipped() -> void:
	_loaded = true
	_mult = {}
	if not FileAccess.file_exists(SHIPPED_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_PATH))
	if parsed is Dictionary:
		for k in parsed:
			if k is String and not k.begins_with("_") and (parsed[k] is float or parsed[k] is int):
				_mult[k] = float(parsed[k])


# ── Learned matchups (ISSUE #375) ── {"cards": {uid: [traits]}, "attacks": {"uid|attack": [traits]}, "bench_traits": [...],
# "w": {cross: weight}} — trait-combination weights learned from self-play (Scripts/Autotest/cpu_learner.py). Shipped copy
# in res://NPC_and_Opponent_Data/CPU_Learned.json; empty = no learned terms.
const SHIPPED_LEARNED_PATH := "res://NPC_and_Opponent_Data/CPU_Learned.json"
static var _learned: Dictionary = {}
static var _learned_loaded := false

static func learned() -> Dictionary:
	if not _learned_loaded:
		_learned_loaded = true
		if FileAccess.file_exists(SHIPPED_LEARNED_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_LEARNED_PATH))
			if parsed is Dictionary:
				_learned = parsed
	return _learned

static func set_learned(table: Dictionary) -> void:
	_learned = table
	_learned_loaded = true


# ── CPU foresight / "cheat mode" (ISSUE #375) ── two SEPARATE dials, 0.0 = fair (default) .. 1.0 = always:
#   cheat_cards — sees hidden CARDS: its own Prize cards, the player's hand and next draw. Subtle: it just seems to pick
#                 the right Prize or play safe at the right time.
#   cheat_coins — knows the coin results it is about to flip (the flips stay fair). Obvious if overused (it never goes
#                 for a flip that will fail), so it is a separate switch.
# Between 0 and 1 each decision uses the knowledge with that probability (sometimes it still makes the "honest" choice).
# Opponent JSON: "cpu_cheat_cards" / "cpu_cheat_coins" (Main loads them); autotester: --cheat-cards= / --cheat-coins=.
static var cheat_cards := 0.0
static var cheat_coins := 0.0
static var _cheat_rng := RandomNumberGenerator.new()

static func seed_cheat(s: int) -> void:
	_cheat_rng.seed = s

static func cheating_cards() -> bool:
	return cheat_cards > 0.0 and (cheat_cards >= 1.0 or _cheat_rng.randf() < cheat_cards)

static func cheating_coins() -> bool:
	return cheat_coins > 0.0 and (cheat_coins >= 1.0 or _cheat_rng.randf() < cheat_coins)


# ── Learned counters (ISSUE #375) ── {"cards": {cpu_uid: {player_uid: pts}}, "style": {trait: {style: pts}},
# "traits": {uid: [traits]}} — which CPU cards win more when the player has a given card out, and which CPU card traits
# pay off against a player's play style (Trainer-heavy, evolving, bench damage...). Shipped: res://NPC_and_Opponent_Data/
# CPU_Counters.json; the lab passes its own with --counters.
const SHIPPED_COUNTERS_PATH := "res://NPC_and_Opponent_Data/CPU_Counters.json"
static var _counters: Dictionary = {}
static var _counters_loaded := false

static func counters() -> Dictionary:
	if not _counters_loaded:
		_counters_loaded = true
		if FileAccess.file_exists(SHIPPED_COUNTERS_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_COUNTERS_PATH))
			if parsed is Dictionary:
				_counters = parsed
	return _counters

static func set_counters(table: Dictionary) -> void:
	_counters = table
	_counters_loaded = true


# ── Multi-turn planner (ISSUE #375 phase 3) ── turns of lookahead (0 = off). Opponent JSON "cpu_plan_turns"; autotester
# --plan-turns=N. Timing accumulators let the tester report thinking time.
static var plan_turns := 0
static var plan_ms_total := 0.0
static var plan_calls := 0
