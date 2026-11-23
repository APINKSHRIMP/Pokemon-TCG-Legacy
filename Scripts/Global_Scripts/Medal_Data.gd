class_name MedalData
extends RefCounted

# ============================================================
# MEDALS - definitions, progress and awards
# ============================================================
# The list lives in NPC_and_Opponent_Data/Medals.json (one entry per medal - add a medal there and
# in nothing else). Art is Image_Assets/Medals/<id>.png, or <id>_<n>.png for a tiered medal (n =
# 1 .. tiers); the PNGs are generated placeholders (Scripts/Utilities/medal_art_build.py) that a
# hand-drawn 32x32 file of the same name replaces with no code change.
#
# Nearly everything is DERIVED from what the save already holds (cards owned, matches won, packs
# opened, coins / sleeves / costumes, opponent records). The only new tracked values are the
# counters GameState.bump_counter() keeps - cash_earned_total, coin_flips_total, prizes_taken_total,
# archetype_wins (per all-one-type / all-one-leader deck), the flawless / deck-out win counts and the
# MATCH FEATS records (bonus_best / match_best / match_totals, GameState.record_match_feats).
#
# TIERED medals are ONE slot whose grade rises: tier index 0 .. tiers.size()-1, the highest threshold
# passed. A medal with a single tier ([1]) is simply earned or not.

const JSON_PATH := "res://NPC_and_Opponent_Data/Medals.json"
const ART_DIR := "res://Image_Assets/Medals/"
const SEEN_KEY := "medals_seen"          # progress: medal id -> highest tier index already announced
const DEBUG_ALL_KEY := "medals_debug_all"  # progress: true = CHT.All_Medals is on (every medal at its top grade)
const OWNED_SUFFIX := "_player_owned_cards.json"
const GRADE_NAMES := {
	1: ["Earned"],
	4: ["Bronze", "Silver", "Gold", "Platinum"],
	5: ["Slate", "Bronze", "Silver", "Gold", "Platinum"],
	6: ["Slate", "Bronze", "Silver", "Gold", "Platinum", "Platinum+"],
}
## Leader name prefix a deck's Pokemon must all share (Pokemon cards are named "Brock's Onix").
const LEADER_PREFIX_SUFFIX := "'s "
## A type / leader deck needs at least this many DIFFERENT named Pokemon (the same number is in Medals.json's text).
const MIN_NAMES := 6

static var _defs: Array = []


static func all() -> Array:
	if _defs.is_empty():
		var f := FileAccess.open(JSON_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Array:
				_defs = parsed
		if _defs.is_empty():
			push_error("MedalData: could not read " + JSON_PATH)
	return _defs


static func tier_count(def: Dictionary) -> int:
	return maxi(1, (def.get("tiers", [1]) as Array).size())


static func is_tiered(def: Dictionary) -> bool:
	return tier_count(def) > 1


static func grade_name(def: Dictionary, tier: int) -> String:
	var names: Array = GRADE_NAMES.get(tier_count(def), ["Earned"])
	return String(names[clampi(tier, 0, names.size() - 1)])


## The metal a medal is struck in at a tier: slate / bronze / silver / gold / platinum / "platinum+" (the 6th
## grade of a six-grade medal), or the entry's own "metal" for a single-grade medal. Mirrors TIER_METALS in
## Scripts/Utilities/medal_art_build.py.
const TIER_METALS := {
	4: ["bronze", "silver", "gold", "platinum"],
	5: ["slate", "bronze", "silver", "gold", "platinum"],
	6: ["slate", "bronze", "silver", "gold", "platinum", "platinum+"],
}

static func metal_of(def: Dictionary, tier: int) -> String:
	if not is_tiered(def):
		return String(def.get("metal", "gold"))
	var list: Array = TIER_METALS.get(tier_count(def), ["gold"])
	return String(list[clampi(tier, 0, list.size() - 1)])


## Art for a tier (0-based). A locked slot passes tier 0 and the screen blacks it out.
static func art_path(def: Dictionary, tier: int) -> String:
	if not is_tiered(def):
		return ART_DIR + String(def["id"]) + ".png"
	return ART_DIR + "%s_%d.png" % [String(def["id"]), clampi(tier, 0, tier_count(def) - 1) + 1]


# ── Context: the expensive scans, done once per screen / check ────────────────────────────────

## set_id -> { "owned": n, "total": n }  and the grand total of owned copies.
static func scan_collection() -> Dictionary:
	var per_set := {}
	var total := 0
	var dir := DirAccess.open(GameState.OWNED_CARDS_FOLDER)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(OWNED_SUFFIX):
				var f := FileAccess.open(GameState.OWNED_CARDS_FOLDER + fname, FileAccess.READ)
				if f != null:
					var parsed = JSON.parse_string(f.get_as_text())
					f.close()
					if parsed is Dictionary and parsed.has("owned_cards"):
						var cards := 0
						var have := 0
						for entry in parsed["owned_cards"]:
							if entry is Dictionary:
								cards += 1
								var n := int(entry.get("owned", 0))
								if n > 0:
									have += 1
									total += n
						per_set[fname.trim_suffix(OWNED_SUFFIX)] = {"owned": have, "total": cards}
			fname = dir.get_next()
		dir.list_dir_end()
	return {"per_set": per_set, "cards_owned": total}


static func make_context() -> Dictionary:
	var ctx := scan_collection()
	var sl: Dictionary = GameState.get_sleeve_universe(true)
	var co: Dictionary = GameState.get_coin_universe()
	var cu: Dictionary = GameState.get_costume_universe()
	ctx["sleeves_owned"] = _count_owned(sl, GameState.get_sleeves())
	ctx["coins_owned"] = _count_owned(co, GameState.get_coins())
	ctx["costumes_owned"] = _count_owned(cu, GameState.get_costumes())
	ctx["all_sleeves"] = sl.size()      # what "all" means for each ladder
	ctx["all_coins"] = co.size()
	ctx["all_costumes"] = cu.size()
	ctx["all_fish_species"] = fish_species_total()
	ctx["fish_species"] = (GameState.get_fish_species_caught() as Dictionary).size()
	return ctx


static func _count_owned(universe: Dictionary, owned: Array) -> int:
	var n := 0
	var seen := {}
	for e in owned:
		var k := String(e)
		if universe.has(k) and not seen.has(k):
			seen[k] = true
			n += 1
	return n


## Every species that can be hooked at any fishing spot (the Spawns files) - the "all" of Marine Biologist.
static var _fish_species_total: int = -1

static func fish_species_total() -> int:
	if _fish_species_total >= 0:
		return _fish_species_total
	var seen := {}
	var dir := DirAccess.open("res://NPC_and_Opponent_Data/Pokemon/Spawns")
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://NPC_and_Opponent_Data/Pokemon/Spawns/" + f))
			_collect_fish(parsed, seen)
	_fish_species_total = seen.size()
	return _fish_species_total


static func _collect_fish(node, seen: Dictionary) -> void:
	if node is Dictionary:
		var tables = node.get("tables")
		if tables is Dictionary:
			for t in (tables as Dictionary).values():
				if t is Dictionary:
					for row in (t as Dictionary).get("table", []):
						if row is Dictionary and row.has("species"):
							seen[String(row["species"])] = true
		for v in (node as Dictionary).values():
			_collect_fish(v, seen)
	elif node is Array:
		for v in node:
			_collect_fish(v, seen)


# ── Progress ──────────────────────────────────────────────────────────────────────────────────

## The number this medal is measured by (cards owned, matches won, ... or 0 / 1 for a one-off).
static func value_of(def: Dictionary, ctx: Dictionary) -> int:
	var prog: Dictionary = GameState.progress
	if String(def.get("kind", "")) == "set":
		var s: Dictionary = (ctx["per_set"] as Dictionary).get(String(def["set_id"]), {})
		return 1 if int(s.get("total", 0)) > 0 and int(s.get("owned", 0)) >= int(s.get("total", 0)) else 0
	if String(def.get("kind", "")) == "archetype":
		return int((prog.get("archetype_wins", {}) as Dictionary).get(String(def["key"]), 0))
	# MATCH FEATS (GameState.record_match_feats, WON games only):
	#   "bonus:<id>:<tier>"  1 once that League bonus reached that tier in one game (bonus:healer:4 = Ultra Healer)
	#   "best:<stat>"        the best single game (flips_heads / flips_tails)
	#   "total:<stat>"       the running total (healed, multi_ko_points, evolutions, sniper_kos, poison_kos, ...)
	var stat := String(def.get("stat", ""))
	if stat.begins_with("bonus:"):
		var parts := stat.split(":")
		var reached := int((prog.get(GameState.BONUS_BEST_KEY, {}) as Dictionary).get(parts[1], 0))
		return 1 if reached >= (int(parts[2]) if parts.size() > 2 else 1) else 0
	if stat.begins_with("best:"):
		return int((prog.get(GameState.MATCH_BEST_KEY, {}) as Dictionary).get(stat.substr(5), 0))
	if stat.begins_with("total:"):
		return int((prog.get(GameState.MATCH_TOTALS_KEY, {}) as Dictionary).get(stat.substr(6), 0))
	match stat:
		"cards_owned": return int(ctx.get("cards_owned", 0))
		"cash_earned": return int(prog.get("cash_earned_total", 0))
		"packs_opened": return int(prog.get("packs_opened_total", 0))
		"matches_won": return int(prog.get("matches_won", 0))
		"coin_flips": return int(prog.get("coin_flips_total", 0))
		"prizes_taken": return int(prog.get("prizes_taken_total", 0))
		"god_packs": return int(prog.get("god_packs_opened", 0))
		"flawless_wins": return int(prog.get("flawless_wins_total", 0))
		"deckout_wins": return int(prog.get("deckout_wins_total", 0))
		"coins_owned", "costumes_owned", "sleeves_owned", "fish_species": return int(ctx.get(String(def["stat"]), 0))
		"fish_caught": return GameState.get_fish_caught()
		"elders": return 1 if GameState.card_elders_beaten() >= GameState.CARD_ELDERS.size() else 0
		"gym_challenge": return 1 if GameState.has_flag(GameState.GYM_CHALLENGE_COMPLETE_FLAG) else 0
		"nemesis":
			for rec in (prog.get(GameState.OPPONENT_RECORD_KEY, {}) as Dictionary).values():
				if int((rec as Dictionary).get("w", 0)) >= 10:
					return 1
			return 0
	return 0


## The numbers for each grade. A tier written "all" means every one that exists (every coin, every
## costume, every fish species ...), read live so adding content moves the goalposts by itself.
static func thresholds(def: Dictionary, ctx: Dictionary) -> Array:
	if String(def.get("kind", "")) == "set":
		return [1]
	var out: Array = []
	for t in def.get("tiers", [1]):
		if t is String and String(t) == "all":
			var key := "all_" + String(def.get("stat", "")).trim_suffix("_owned")
			if String(def.get("stat", "")) == "fish_species":
				key = "all_fish_species"
			out.append(maxi(1, int(ctx.get(key, 1))))
		else:
			out.append(int(t))
	return out


## Highest tier index passed, or -1 when still locked.
static func earned_tier(def: Dictionary, ctx: Dictionary) -> int:
	if bool(GameState.progress.get(DEBUG_ALL_KEY, false)):
		return tier_count(def) - 1   # CHT.All_Medals: every medal at its top grade
	var v := value_of(def, ctx)
	var best := -1
	var th := thresholds(def, ctx)
	for i in range(th.size()):
		if v >= int(th[i]):
			best = i
	return best


## "Win 25 matches." for the tier the player is working towards (or the last one once all are done).
static func describe(def: Dictionary, tier: int, ctx: Dictionary) -> String:
	var th := thresholds(def, ctx)
	var shown: int = int(th[mini(tier + 1, th.size() - 1)]) if not th.is_empty() else 1
	var text := String(def.get("desc", ""))
	if text.contains("%d"):
		text = text % shown
	return text


## "37 / 100" style progress line toward the next tier, "" for a one-off or a finished ladder.
static func progress_line(def: Dictionary, ctx: Dictionary) -> String:
	var th := thresholds(def, ctx)
	if th.size() <= 1:
		return ""
	var v := value_of(def, ctx)
	var tier := earned_tier(def, ctx)
	if tier >= th.size() - 1:
		return "%s  (complete)" % _fmt(v)
	return "%s / %s  to %s" % [_fmt(v), _fmt(int(th[tier + 1])), grade_name(def, tier + 1)]


static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


## Whether a medal is on the chart at all. A set's medal waits until that set is unlocked (GameState's one
## check); the Gym Leader group waits until a Gym set is unlocked. Anything already earned always shows.
static func is_visible(def: Dictionary, ctx: Dictionary) -> bool:
	if earned_tier(def, ctx) >= 0:
		return true
	if bool(def.get("hidden", false)):
		return false   # a secret medal: not on the chart, and not in its total, until earned
	match String(def.get("group", "")):
		"Sets": return GameState.is_set_unlocked(String(def.get("set_id", "")))
		"Gym Leaders": return GameState.is_set_unlocked("gym1") or GameState.is_set_unlocked("gym2")
	return true


## How many medals have at least their first grade.
static func count_earned(ctx: Dictionary) -> int:
	var n := 0
	for def in all():
		if earned_tier(def, ctx) >= 0:
			n += 1
	return n


# ── Awards ────────────────────────────────────────────────────────────────────────────────────

## Medals (or new grades of one) earned since the player last heard about them, as
## [{ "def": Dictionary, "tier": int }]. Marks them heard (saved), so each is announced once.
static func take_new_awards() -> Array:
	# First ever check on this save: everything already earned is taken as heard (a save made before
	# medals existed must not open with dozens of notices); only NEW grades are announced from here.
	var first_check: bool = not GameState.progress.has(SEEN_KEY)
	var seen: Dictionary = GameState.progress.get(SEEN_KEY, {})
	var ctx := make_context()
	var fresh: Array = []
	for def in all():
		var tier := earned_tier(def, ctx)
		var was: int = int(seen.get(String(def["id"]), -1))
		if tier > was:
			fresh.append({"def": def, "tier": tier})
			seen[String(def["id"])] = tier
	if not fresh.is_empty() or first_check:
		GameState.progress[SEEN_KEY] = seen
		GameState.save_progress()
	return [] if first_check else fresh


## CHT.All_Medals: every medal at its top grade on this save. All of them are marked as already announced
## except ONE picked at random, so the map plays a single reveal instead of one per medal.
static func debug_grant_all() -> void:
	var defs := all()
	if defs.is_empty():
		return
	var seen := {}
	for def in defs:
		seen[String(def["id"])] = tier_count(def) - 1
	var shown: Dictionary = defs[randi() % defs.size()]
	seen[String(shown["id"])] = tier_count(shown) - 2   # one below the top: its top grade is the one revealed
	GameState.progress[DEBUG_ALL_KEY] = true
	GameState.progress[SEEN_KEY] = seen
	GameState.save_progress()


## CHT.Real_Medals: undoes CHT.All_Medals - back to the medals this save really earned, with no notices.
static func debug_clear_all() -> void:
	GameState.progress.erase(DEBUG_ALL_KEY)
	var seen := {}
	var ctx := make_context()
	for def in all():
		seen[String(def["id"])] = earned_tier(def, ctx)
	GameState.progress[SEEN_KEY] = seen
	GameState.save_progress()


# ── Deck classification (match start) ─────────────────────────────────────────────────────────

## Archetype keys a deck qualifies for: "type:Fire" when EVERY Pokemon in it is of that type,
## "leader:Brock" when every Pokemon is named "Brock's ...". Energy and Trainers are unrestricted.
## `cards` are card_objects (their `.metadata` is the card JSON).
static func classify_deck(cards: Array) -> Array:
	var pokemon: Array = []
	for c in cards:
		var md: Dictionary = c.metadata if c != null and "metadata" in c else {}
		if String(md.get("supertype", "")).begins_with("Pok"):
			pokemon.append(md)
	if pokemon.is_empty():
		return []
	# At least MIN_NAMES DIFFERENT named Pokemon (four printings of Pikachu count as one).
	var names := {}
	for md in pokemon:
		names[String(md.get("name", ""))] = true
	if names.size() < MIN_NAMES:
		return []
	var out: Array = []
	# Type: the Pokemon's own types - qualifies for every type they ALL carry.
	var common: Array = []
	for i in range(pokemon.size()):
		var t: Array = pokemon[i].get("types", [])
		if i == 0:
			common = t.duplicate()
		else:
			var keep: Array = []
			for x in common:
				if x in t:
					keep.append(x)
			common = keep
	for t in common:
		out.append("type:" + String(t))
	# Leader: every Pokemon carries the same "<Name>'s " prefix.
	for def in all():
		if String(def.get("group", "")) != "Gym Leaders":
			continue
		var prefix: String = String(def["key"]).substr(7) + LEADER_PREFIX_SUFFIX
		var ok := true
		for md in pokemon:
			if not String(md.get("name", "")).begins_with(prefix):
				ok = false
				break
		if ok:
			out.append(String(def["key"]))
	return out
