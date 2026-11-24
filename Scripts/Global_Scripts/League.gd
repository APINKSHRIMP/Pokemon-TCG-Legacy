class_name League
extends RefCounted

# ============================================================
# THE LEAGUE - League Points (LP), League Rank and the end-of-match bonuses.
# All numbers are in NPC_and_Opponent_Data/League_Config.json. One league for now ("base"); the save keeps a
# wallet per league id (GameState.league_*) so a Neo league can have its own later.
#
#   * Opponents have a League Rank 1-8 (their difficulty stars: 6 = Card Elders, 7 = gym leaders, 8 = Mewtwo).
#   * Beating an opponent for the FIRST time pays base LP by THEIR rank; every win pays the bonuses.
#   * The player's League Rank comes from lifetime LP earned (xp); spending LP never lowers it.
#   * Nothing is paid or shown until the player has registered (the TCG Tracker item).
# ============================================================

const CONFIG_PATH := "res://NPC_and_Opponent_Data/League_Config.json"
const ICON_PATH := "res://Image_Assets/Icons/Reward_Icons/league_points_icon.png"

const OpponentRatings := preload("res://Scripts/Global_Scripts/Opponent_Ratings.gd")

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			_cfg = parsed
		else:
			push_error("League: could not read " + CONFIG_PATH)
	return _cfg


# ── Rank ──────────────────────────────────────────────────────────────────────────────────────

static func rank_xp() -> Array:
	return config().get("rank_xp", [0])


static func max_rank() -> int:
	return rank_xp().size()


## The player's League Rank (1-based) for a lifetime LP total.
static func rank_for_xp(xp: int) -> int:
	var r := 1
	var th := rank_xp()
	for i in range(th.size()):
		if xp >= int(th[i]):
			r = i + 1
	return r


## Lifetime LP needed for the NEXT rank, or -1 at the top.
static func next_rank_xp(xp: int) -> int:
	var th := rank_xp()
	var r := rank_for_xp(xp)
	return int(th[r]) if r < th.size() else -1


## Ranks the player is told about (League_Config visible_ranks). Ranks above it are SECRET: earned the normal way,
## but their LP target is never shown before they are reached.
static func visible_ranks() -> int:
	return int(config().get("visible_ranks", max_rank()))


## Lifetime LP for the next rank the player may SEE, or -1 when the next one is secret (or there is none).
static func next_visible_rank_xp(xp: int) -> int:
	return next_rank_xp(xp) if rank_for_xp(xp) < visible_ranks() else -1


# ── Opponents ─────────────────────────────────────────────────────────────────────────────────

## An opponent's League Rank 1-8 (their stars; an unrated opponent is rank 1).
static func opponent_rank(opponent_name: String) -> int:
	return clampi(OpponentRatings.stars_for(opponent_name), 1, 8)


static func base_lp_for_rank(opponent_rank_value: int) -> int:
	var t: Array = config().get("base_lp_by_opponent_rank", [10])
	return int(t[clampi(opponent_rank_value - 1, 0, t.size() - 1)])


# ── Rank-up rewards (claimed at the Town Hall) ───────────────────────────────────────────────

## The rewards for every rank the player has reached but not yet claimed (rank_claimed + 1 .. current rank) that has
## one set in League_Config.json's rank_rewards: [{ "rank", "kind": coin|sleeve|costume, "id" }], lowest rank first.
static func pending_rank_rewards() -> Array:
	var out: Array = []
	var rewards: Dictionary = config().get("rank_rewards", {})
	var have: int = GameState.league_rank()
	for r in range(GameState.league_rank_claimed() + 1, have + 1):
		var entry = rewards.get(str(r), {})
		if entry is Dictionary and String(entry.get("id", "")) != "":
			out.append({"rank": r, "kind": String(entry.get("kind", "coin")), "id": String(entry["id"])})
	return out


# ── Bonuses ───────────────────────────────────────────────────────────────────────────────────
# `stats` (MatchStats.to_dict) for ONE won game:
#   max_damage, bench_ever, max_behind, active_hp, bench_count_end, ko_turns (opponent's Pokemon KO'd in each turn
#   with a KO), healed, type_specialist, deck_out, empty_deck, flawless, opp_prizes_start, player_prizes_start, turn,
#   sniper_kos, evo_baby, evo_stage1, evo_stage2, poison_kos, burn_kos, confusion_kos,
#   inflicts {Confused, Paralyzed, Asleep, Poisoned}, flips_heads, flips_total
# 2026-11-22 rebalance: every bonus has ONE naming scheme - tier 1 = its label, tier 2+ = League_Config
# tier_prefixes + label (Super / Mega / Ultra / Crazy / Insane). Stackable bonuses take the tier from the count.

## "Healer" (tier 1), "Super Healer" (tier 2) ... A tier past the last prefix keeps the last one.
static func tier_label(label: String, tier: int) -> String:
	var pre: Array = config().get("tier_prefixes", [""])
	var p: String = "" if pre.is_empty() else String(pre[clampi(tier - 1, 0, pre.size() - 1)])
	return label if p == "" else "%s %s" % [p, label]


## Bonuses for the game(s) just WON. `games` = the stats of every won game of the series (one for a single
## match). Each game is worked out on its own (game_bonuses); a row earned in more than one game - the SAME
## name, so Super Double Knockout and Double Knockout stay apart - is shown once as "(x2)" and pays each time.
## Lost games never appear. Returns [{ "id", "tier", "label", "lp", "count" }] (count = games it came from).
static func compute_final(games: Array) -> Array:
	var merged: Dictionary = {}   # label -> row
	var order: Array = []
	for g in games:
		for b in game_bonuses(g):
			var key: String = String(b["label"])
			if not merged.has(key):
				var row: Dictionary = (b as Dictionary).duplicate()
				row["lp"] = 0
				row["count"] = 0
				merged[key] = row
				order.append(key)
			merged[key]["lp"] = int(merged[key]["lp"]) + int(b["lp"])
			merged[key]["count"] = int(merged[key]["count"]) + 1
	var out: Array = []
	for key in order:
		var e: Dictionary = merged[key]
		if int(e["count"]) > 1:
			e["label"] = "%s (x%d)" % [e["label"], int(e["count"])]
		out.append(e)
	return out


## Every bonus ONE won game earned: [{ "id", "tier", "label", "lp" }]. `id` is the League_Config key (an
## inflictor is "<condition>_inflictor", a multi-KO kind its own id) and `tier` 1-based - the medals that stand
## for a bonus (Medals.json "bonus:<id>:<tier>") read these, so they never disagree with the LP rows.
static func game_bonuses(s: Dictionary) -> Array:
	var cfg: Dictionary = config().get("bonuses", {})
	var out: Array = []
	# TIERED: only the highest tier met pays
	_tiered(out, cfg, "damage", float(s.get("max_damage", 0)))
	_tiered(out, cfg, "healer", float(s.get("healed", 0)))
	_tiered(out, cfg, "comeback", float(s.get("max_behind", 0)))
	var flips := int(s.get("flips_total", 0))
	if flips > 0:
		var h_ratio := float(s.get("flips_heads", 0)) / float(flips)
		if not _tiered(out, cfg, "lucky_heads", h_ratio, flips):
			_tiered(out, cfg, "unlucky_tails", 1.0 - h_ratio, flips)
	_tiered(out, cfg, "evolution", float(evolutions(s)))
	var inf: Dictionary = cfg.get("inflictor", {})
	var inflicts: Dictionary = s.get("inflicts", {})
	for st in (inf.get("statuses", {}) as Dictionary).keys():
		var label: String = String(inf["statuses"][st])
		_tiered_rows(out, label.to_lower().replace(" ", "_"), label, inf.get("tiers", []), float(inflicts.get(st, 0)))
	# STACKABLE: LP per count, the count picks the name
	var mk: Dictionary = cfg.get("multi_ko", {})
	var kinds: Array = mk.get("kinds", [])
	var per_kind: Dictionary = {}   # kind index -> turns
	for k in s.get("ko_turns", []):
		var best := -1
		for i in range(kinds.size()):
			if int(k) >= int(kinds[i]["kos"]):
				best = i
		if best >= 0:
			per_kind[best] = int(per_kind.get(best, 0)) + 1
	for i in range(kinds.size()):
		if per_kind.has(i):
			var kd: Dictionary = kinds[i]
			_stack(out, String(kd["id"]), String(kd["label"]), int(kd["lp"]), int(per_kind[i]))
	for pair in [["sniper", "sniper_kos"], ["poison_master", "poison_kos"], ["burn_master", "burn_kos"], ["confusion_master", "confusion_kos"]]:
		var c: Dictionary = cfg.get(pair[0], {})
		if not c.is_empty():
			_stack(out, String(pair[0]), String(c["label"]), int(c["lp_each"]), int(s.get(pair[1], 0)))
	# ONE-OFFS
	if not bool(s.get("bench_ever", true)):
		_flat(out, cfg, "only_one")
	if int(s.get("active_hp", 999)) <= int(cfg.get("last_resort", {}).get("hp_at_most", -1)) and int(s.get("bench_count_end", 1)) == 0:
		_flat(out, cfg, "last_resort")
	if bool(s.get("type_specialist", false)):
		_flat(out, cfg, "type_specialist")
	if bool(s.get("deck_out", false)):
		_flat(out, cfg, "deck_out")
	if bool(s.get("empty_deck", false)):
		_flat(out, cfg, "empty_deck")
	if bool(s.get("flawless", false)) and cfg.has("flawless"):
		# +1 per Prize card the opponent started with (a 2-Prize flawless = +2, a 6-Prize one = +6)
		out.append({"id": "flawless", "tier": 1, "label": String(cfg["flawless"]["label"]),
				"lp": int(s.get("opp_prizes_start", 6)) * int(cfg["flawless"]["lp_per_prize"])})
	# Turn count (the match's GLOBAL turn counter, both players' turns: turn 6 = 3 each): never both
	var turn := int(s.get("turn", 0))
	if turn > 0 and cfg.has("speedrun") and turn <= int(cfg["speedrun"]["turn_at_most"]):
		_flat(out, cfg, "speedrun")
	elif cfg.has("marathon") and turn > int(cfg["marathon"]["turn_over"]):
		_flat(out, cfg, "marathon")
	return out


## Evolutions the player made in one game (Baby -> Basic counts).
static func evolutions(s: Dictionary) -> int:
	return int(s.get("evo_baby", 0)) + int(s.get("evo_stage1", 0)) + int(s.get("evo_stage2", 0))


## The Multi Knockout medal's points for one game: +1 for every Pokemon past the first Knocked Out in one turn
## (a Double Knockout +1, a Triple +2 ...).
static func multi_ko_points(s: Dictionary) -> int:
	var n := 0
	for k in s.get("ko_turns", []):
		n += maxi(0, int(k) - 1)
	return n


## Appends the highest tier of bonus `key` that `value` meets; false when none does (or too few flips).
static func _tiered(out: Array, cfg: Dictionary, key: String, value: float, flips: int = -1) -> bool:
	var c: Dictionary = cfg.get(key, {})
	if c.is_empty() or (c.has("min_flips") and flips < int(c["min_flips"])):
		return false
	return _tiered_rows(out, key, String(c.get("label", key)), c.get("tiers", []), value)


static func _tiered_rows(out: Array, id: String, label: String, tiers: Array, value: float) -> bool:
	var best := -1
	for i in range(tiers.size()):
		if value >= float(tiers[i][0]):
			best = i
	if best < 0:
		return false
	out.append({"id": id, "tier": best + 1, "label": tier_label(label, best + 1), "lp": int(tiers[best][1])})
	return true


static func _stack(out: Array, id: String, label: String, lp_each: int, n: int) -> void:
	if n > 0:
		out.append({"id": id, "tier": n, "label": tier_label(label, n), "lp": n * lp_each})


static func _flat(out: Array, cfg: Dictionary, key: String) -> void:
	var c: Dictionary = cfg.get(key, {})
	if not c.is_empty():
		out.append({"id": key, "tier": 1, "label": String(c["label"]), "lp": int(c["lp"])})


static func total_lp(rows: Array) -> int:
	var t := 0
	for r in rows:
		t += int(r.get("lp", 0))
	return t
