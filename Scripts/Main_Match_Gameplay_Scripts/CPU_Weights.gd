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
