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


## 0..1 of the way from this rank's threshold to the next (1 at the top rank).
static func rank_progress(xp: int) -> float:
	var th := rank_xp()
	var r := rank_for_xp(xp)
	if r >= th.size():
		return 1.0
	var lo := float(th[r - 1])
	var hi := float(th[r])
	return clampf((float(xp) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


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
#   max_damage, bench_ever, max_behind, active_hp, bench_count_end, max_prizes_turn, healed, type_specialist,
#   deck_out, flawless, opp_prizes_start, turn, sniper_kos, evo_baby, evo_stage1, evo_stage2, poison_kos, burn_kos, confusion_kos,
#   inflicts {Confused, Paralyzed, Asleep, Poisoned}, flips_heads, flips_total

## Bonuses for the game(s) just WON. `games` = the stats of every won game of the series (one for a single
## match). Per-game bonuses (tiers, flags) are worked out per game and merged "x2"; the STACKABLE ones (snipes,
## evolutions, status KOs, status inflictions) are added up across the games first. Lost games never appear.
## Returns [{ "label", "lp", "count" }].
static func compute_final(games: Array) -> Array:
	var cfg: Dictionary = config().get("bonuses", {})
	var merged: Dictionary = {}   # label -> {label, lp, count}
	var order: Array = []
	for g in games:
		for b in _per_game(g, cfg):
			var key: String = String(b["label"])
			if not merged.has(key):
				merged[key] = {"label": key, "lp": 0, "count": 0}
				order.append(key)
			merged[key]["lp"] = int(merged[key]["lp"]) + int(b["lp"])
			merged[key]["count"] = int(merged[key]["count"]) + 1
	var out: Array = []
	for key in order:
		var e: Dictionary = merged[key]
		if int(e["count"]) > 1:
			e["label"] = "%s x%d" % [e["label"], int(e["count"])]
		out.append(e)
	out.append_array(_stacked(games, cfg))
	return out


static func _per_game(s: Dictionary, cfg: Dictionary) -> Array:
	var out: Array = []
	# Big Damage: the highest tier met
	var best_dmg := 0
	var dmg_lp := 0
	for t in (cfg.get("big_damage", {}) as Dictionary).get("tiers", []):
		if int(s.get("max_damage", 0)) >= int(t[0]):
			best_dmg = int(t[0])
			dmg_lp = int(t[1])
	if best_dmg > 0:
		out.append({"label": "Big Damage! (%d)" % best_dmg, "lp": dmg_lp})
	if not bool(s.get("bench_ever", true)):
		out.append({"label": cfg["only_one"]["label"], "lp": int(cfg["only_one"]["lp"])})
	# Comeback: the deeper one replaces the shallower
	var behind := int(s.get("max_behind", 0))
	if behind >= int(cfg["crazy_comeback"]["behind"]):
		out.append({"label": cfg["crazy_comeback"]["label"], "lp": int(cfg["crazy_comeback"]["lp"])})
	elif behind >= int(cfg["comeback"]["behind"]):
		out.append({"label": cfg["comeback"]["label"], "lp": int(cfg["comeback"]["lp"])})
	if int(s.get("active_hp", 999)) <= int(cfg["last_resort"]["hp_at_most"]) and int(s.get("bench_count_end", 1)) == 0:
		out.append({"label": cfg["last_resort"]["label"], "lp": int(cfg["last_resort"]["lp"])})
	# Prizes in one turn: the highest tier
	var mp := int(s.get("max_prizes_turn", 0))
	var mp_label := ""
	var mp_lp := 0
	for t in cfg["multi_prize"]["tiers"]:
		if mp >= int(t[0]):
			mp_label = String(t[1])
			mp_lp = int(t[2])
	if mp_label != "":
		out.append({"label": mp_label, "lp": mp_lp})
	# Healing: the highest tier
	var hl_label := ""
	var hl_lp := 0
	for t in cfg["healer"]["tiers"]:
		if int(s.get("healed", 0)) >= int(t[0]):
			hl_label = String(t[1])
			hl_lp = int(t[2])
	if hl_label != "":
		out.append({"label": hl_label, "lp": hl_lp})
	if bool(s.get("type_specialist", false)):
		out.append({"label": cfg["type_specialist"]["label"], "lp": int(cfg["type_specialist"]["lp"])})
	if bool(s.get("deck_out", false)):
		out.append({"label": cfg["deck_out"]["label"], "lp": int(cfg["deck_out"]["lp"])})
	if bool(s.get("flawless", false)):
		# +1 per Prize card the opponent started with (a 2-Prize flawless = +2, a 6-Prize one = +6)
		out.append({"label": cfg["flawless"]["label"], "lp": int(s.get("opp_prizes_start", 6)) * int(cfg["flawless"]["lp_per_prize"])})
	# Turn count (the match's GLOBAL turn counter, both players' turns: turn 6 = 3 each): exclusive, the longest tier wins
	var turn := int(s.get("turn", 0))
	if turn > 0 and turn <= int(cfg["speedrun"]["turn_at_most"]):
		out.append({"label": cfg["speedrun"]["label"], "lp": int(cfg["speedrun"]["lp"])})
	elif turn > int(cfg["marathon"]["turn_over"]):
		out.append({"label": cfg["marathon"]["label"], "lp": int(cfg["marathon"]["lp"])})
	# Coin luck: lucky heads OR unlucky tails (never both), double at a clean sweep either way
	var cl: Dictionary = cfg["coin_luck"]
	var flips := int(s.get("flips_total", 0))
	if flips >= int(cl["min_flips"]):
		var heads := int(s.get("flips_heads", 0))
		var h_ratio := float(heads) / float(flips)
		var t_ratio := 1.0 - h_ratio
		var amount := int(cl["lp"])
		if h_ratio >= float(cl["ratio"]):
			out.append({"label": cl["lucky_label"], "lp": amount * (2 if h_ratio >= float(cl["double_at_ratio"]) else 1)})
		elif t_ratio >= float(cl["ratio"]):
			out.append({"label": cl["unlucky_label"], "lp": amount * (2 if t_ratio >= float(cl["double_at_ratio"]) else 1)})
	return out


static func _stacked(games: Array, cfg: Dictionary) -> Array:
	var total := {"sniper_kos": 0, "evo_baby": 0, "evo_stage1": 0, "evo_stage2": 0, "poison_kos": 0, "burn_kos": 0, "confusion_kos": 0}
	var inflicts := {}
	for g in games:
		for k in total.keys():
			total[k] = int(total[k]) + int(g.get(k, 0))
		for st in (g.get("inflicts", {}) as Dictionary).keys():
			inflicts[st] = int(inflicts.get(st, 0)) + int((g["inflicts"] as Dictionary)[st])
	var out: Array = []
	var n := int(total["sniper_kos"])
	if n > 0:
		out.append({"label": _times(cfg["sniper"]["label"], n), "lp": n * int(cfg["sniper"]["lp_each"]), "count": n})
	var ev: Dictionary = cfg["evolution"]
	# Evolution Master: every evolution counts the same; the HIGHEST milestone reached pays (5 -> +5, 10 -> +10, ...)
	var evo_n := int(total["evo_baby"]) + int(total["evo_stage1"]) + int(total["evo_stage2"])
	var evo_tier := 0
	var evo_lp := 0
	for t in ev.get("tiers", []):
		if evo_n >= int(t[0]):
			evo_tier = int(t[0])
			evo_lp = int(t[1])
	if evo_tier > 0:
		out.append({"label": "%s (%d)" % [ev["label"], evo_tier], "lp": evo_lp, "count": evo_n})
	n = int(total["poison_kos"])
	if n > 0:
		out.append({"label": _times(cfg["poison_master"]["label"], n), "lp": n * int(cfg["poison_master"]["lp_each"]), "count": n})
	n = int(total["burn_kos"])
	if n > 0:
		out.append({"label": _times(cfg["burn_master"]["label"], n), "lp": n * int(cfg["burn_master"]["lp_each"]), "count": n})
	n = int(total["confusion_kos"])
	if n > 0:
		out.append({"label": _times(cfg["confusion_master"]["label"], n), "lp": n * int(cfg["confusion_master"]["lp_each"]), "count": n})
	var inf: Dictionary = cfg["inflictor"]
	for st in (inf["statuses"] as Dictionary).keys():
		var times := int(inflicts.get(st, 0))
		var steps := int(times / int(inf["every"]))
		if steps > 0:
			out.append({"label": _times(inf["statuses"][st], steps * int(inf["every"])), "lp": steps * int(inf["lp_per_step"]), "count": times})
	return out


static func _times(label: String, n: int) -> String:
	return label if n <= 1 else "%s x%d" % [label, n]


static func total_lp(rows: Array) -> int:
	var t := 0
	for r in rows:
		t += int(r.get("lp", 0))
	return t
