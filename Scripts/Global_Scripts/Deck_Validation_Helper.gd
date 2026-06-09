class_name DeckValidationHelper

# ============================================================
# DECK VALIDATION HELPER — static utility
# ============================================================
# Validates the player's currently-selected deck against an
# opponent's "restrictions" block (read from the opponent JSON).
#
# Restriction schema — all keys are optional, can mix and match:
#
# "restrictions": {
#   "banned_card_ids":    ["base1-88", "base1-89"],           # strict blacklist by id
#   "banned_card_names":  ["Professor Oak", "Bill"],          # blacklist by NAME (cross-set)
#   "required_card_ids":   [{"id": "base1-1",      "min": 4}],
#   "required_card_names": [{"name": "Alakazam",     "min": 4},
#                           {"name": "Psychic Energy","min": 10}],
#   "allowed_pokemon_types": ["Fire"],   # Pokémon must have at least one of these types
#   "allowed_energy_types":  ["Fire"],   # Energy cards must match (by name e.g. "Fire Energy")
#   "no_trainers":          true,
#   "no_special_energies":  true,
#   "special_energies_only": true,        # any Basic energy is invalid
#   "basic_pokemon_only":   true,         # Stage 1 / Stage 2 forbidden
#   "max_hp":               60,           # Pokémon HP cap
#
#   "allowed_set_ids":              ["base1","base2"],     # card id prefix must match one of these sets
#   "delta_species_only":           true,                   # Pokémon must have " δ" in their name
#   "no_ex_cards":                  true,                   # any card whose subtypes include "ex" is invalid
#   "allowed_pokemon_name_prefixes":["Dark "],              # Pokémon name must start with one of these
#   "banned_pokemon_name_prefixes": ["Dark "],              # Pokémon name must NOT start with these
#   "min_stage_2_pokemon":          4                       # require at least N Stage-2 Pokémon (text-only)
# }
#
# Result Dictionary:
#   { "passed": bool,
#     "mode":   "banned" | "invalid" | "missing" | "",
#     "banned_cards":   Array[String],   # card ids from restriction config (mode=="banned")
#     "invalid_cards":  Array[String],   # card ids from PLAYER deck (mode=="invalid")
#     "missing_lines":  Array[String],   # human-readable lines (mode=="missing")
#     "rule_lines":     Array[String] }  # short summary of every rule that failed
#
# Display priority is banned → invalid → missing. If multiple
# categories fail simultaneously, the caller surfaces the highest-
# priority one first; the player can re-attempt after fixing.
# ============================================================

const POKEMON_SUPERTYPE := "pokémon"
const TRAINER_SUPERTYPE := "trainer"
const ENERGY_SUPERTYPE  := "energy"

# Cache of loaded set JSONs so repeated checks across many cards
# only hit disk once per set during the same call.
static var _set_cache: Dictionary = {}

# ============================================================
# PUBLIC ENTRY POINT
# ============================================================

# Returns true when the restrictions dict has any keys. The argument is the
# restrictions block itself (as stored on Opponent_Object.restrictions), NOT
# the full opponent entry — MapManager passes the dict directly.
static func opponent_has_restrictions(restrictions: Dictionary) -> bool:
	return not restrictions.is_empty()

# Validates the given player deck file path against the restrictions dict.
# `deck_path` is e.g. "user://Player_Decks/Your First Deck.json".
static func validate(deck_path: String, restrictions: Dictionary) -> Dictionary:
	var result := {
		"passed":         true,
		"mode":           "",
		"banned_cards":   [],
		"invalid_cards":  [],
		"missing_lines":  [],
		"rule_lines":     [],
	}
	if restrictions == null or restrictions.is_empty():
		return result

	var deck_entries := _load_deck_entries(deck_path)
	if deck_entries.is_empty():
		# Empty/missing deck — treat as a hard failure so the player isn't
		# silently waved into a battle with no deck file.
		result["passed"] = false
		result["mode"] = "missing"
		result["missing_lines"] = ["No deck found. Select a deck before battling."]
		return result

	# Pre-load metadata for every card in the deck so per-rule checks are pure data lookups.
	var meta_by_id: Dictionary = {}
	for entry in deck_entries:
		var cid: String = entry["id"]
		if not meta_by_id.has(cid):
			meta_by_id[cid] = _lookup_metadata(cid)

	# ---- 1) BANNED CARDS --------------------------------------
	var banned_ids := _normalise_string_array(restrictions.get("banned_card_ids", []))
	var banned_names := _normalise_string_array(restrictions.get("banned_card_names", []))
	if not banned_ids.is_empty() or not banned_names.is_empty():
		var triggered := false
		for entry in deck_entries:
			var cid: String = entry["id"]
			var meta = meta_by_id.get(cid, null)
			var cname: String = ""
			if meta is Dictionary:
				cname = String(meta.get("name", "")).to_lower()
			if cid.to_lower() in banned_ids:
				triggered = true
				break
			if cname != "" and cname in banned_names:
				triggered = true
				break
		if triggered:
			# Mode-banned popup: show every card on the NPC's banlist regardless
			# of whether each individual id is actually present in the player's
			# deck — the player needs to see the full list to clean their deck.
			result["banned_cards"] = _expand_banlist_to_ids(banned_ids, banned_names)
			result["rule_lines"].append("Banned cards detected in your deck.")
			result["passed"] = false
			result["mode"] = "banned"
			# Banned check short-circuits — banlist popup is the most useful response.
			return result

	# ---- 2) STRUCTURAL "INVALID" RULES ------------------------
	var invalid_ids: Array[String] = []
	var rule_lines: Array[String] = []

	var no_trainers: bool          = bool(restrictions.get("no_trainers", false))
	var no_special_energies: bool  = bool(restrictions.get("no_special_energies", false))
	var special_energies_only:bool = bool(restrictions.get("special_energies_only", false))
	var basic_pokemon_only: bool   = bool(restrictions.get("basic_pokemon_only", false))
	var max_hp: int                = int(restrictions.get("max_hp", 0))
	var delta_species_only: bool   = bool(restrictions.get("delta_species_only", false))
	var no_ex_cards: bool          = bool(restrictions.get("no_ex_cards", false))
	var allowed_pokemon_types := _normalise_string_array(restrictions.get("allowed_pokemon_types", []))
	var allowed_energy_types  := _normalise_string_array(restrictions.get("allowed_energy_types", []))
	var allowed_set_ids       := _normalise_string_array(restrictions.get("allowed_set_ids", []))
	var allowed_name_prefixes := _normalise_string_array(restrictions.get("allowed_pokemon_name_prefixes", []))
	var banned_name_prefixes  := _normalise_string_array(restrictions.get("banned_pokemon_name_prefixes", []))

	if no_trainers:
		rule_lines.append("No Trainer cards allowed.")
	if no_special_energies:
		rule_lines.append("No Special Energy cards allowed.")
	if special_energies_only:
		rule_lines.append("Only Special Energy cards allowed (no basic energies).")
	if basic_pokemon_only:
		rule_lines.append("Only Basic Pokémon allowed.")
	if max_hp > 0:
		rule_lines.append("Only Pokémon with HP %d or under allowed." % max_hp)
	if not allowed_pokemon_types.is_empty():
		rule_lines.append("Only %s Pokémon allowed." % _join_types_pretty(allowed_pokemon_types))
	if not allowed_energy_types.is_empty():
		rule_lines.append("Only %s Energy cards allowed." % _join_types_pretty(allowed_energy_types))
	if not allowed_set_ids.is_empty():
		rule_lines.append("Only cards from these sets allowed: %s." % ", ".join(allowed_set_ids))
	if delta_species_only:
		rule_lines.append("Only Delta Species Pokémon (δ) allowed.")
	if no_ex_cards:
		rule_lines.append("No Pokémon-ex cards allowed.")
	if not allowed_name_prefixes.is_empty():
		rule_lines.append("Only Pokémon named \"%s…\" allowed." % "\", \"".join(allowed_name_prefixes))
	if not banned_name_prefixes.is_empty():
		rule_lines.append("No Pokémon named \"%s…\" allowed." % "\", \"".join(banned_name_prefixes))

	for entry in deck_entries:
		var cid: String = entry["id"]
		var meta = meta_by_id.get(cid, null)
		if meta == null or not (meta is Dictionary):
			continue
		if _card_violates(meta, cid, no_trainers, no_special_energies, special_energies_only,
				basic_pokemon_only, max_hp, allowed_pokemon_types, allowed_energy_types,
				allowed_set_ids, delta_species_only, no_ex_cards,
				allowed_name_prefixes, banned_name_prefixes):
			if cid not in invalid_ids:
				invalid_ids.append(cid)

	if not invalid_ids.is_empty():
		result["invalid_cards"] = invalid_ids
		result["rule_lines"] = rule_lines
		result["passed"] = false
		result["mode"] = "invalid"
		# Don't return yet — fall through to also collect missing-requirement
		# text so the popup can also describe required cards. The mode stays
		# "invalid" so the caller renders the grid.

	# ---- 3) REQUIRED CARDS (quantities) -----------------------
	var missing_lines: Array[String] = []
	var required_ids: Array = restrictions.get("required_card_ids", [])
	var required_names: Array = restrictions.get("required_card_names", [])

	if required_ids is Array:
		for req in required_ids:
			if not (req is Dictionary):
				continue
			var rid := String(req.get("id", "")).to_lower()
			var rmin := int(req.get("min", 0))
			if rid == "" or rmin <= 0:
				continue
			var count := _count_by_id(deck_entries, rid)
			if count < rmin:
				var display_name := rid
				var m = meta_by_id.get(rid, null)
				if m is Dictionary and String(m.get("name", "")) != "":
					display_name = "%s (%s)" % [m["name"], rid]
				missing_lines.append("• Need at least %d×  %s  (have %d)" % [rmin, display_name, count])

	if required_names is Array:
		for req in required_names:
			if not (req is Dictionary):
				continue
			var rname := String(req.get("name", ""))
			var rmin := int(req.get("min", 0))
			if rname == "" or rmin <= 0:
				continue
			var count := _count_by_name(deck_entries, meta_by_id, rname)
			if count < rmin:
				missing_lines.append("• Need at least %d×  %s  (have %d)" % [rmin, rname, count])

	var min_stage_2: int = int(restrictions.get("min_stage_2_pokemon", 0))
	if min_stage_2 > 0:
		var stage_2_count := _count_stage_2_pokemon(deck_entries, meta_by_id)
		if stage_2_count < min_stage_2:
			missing_lines.append("• Need at least %d Stage 2 Pokémon (have %d)" % [min_stage_2, stage_2_count])

	if not missing_lines.is_empty():
		result["missing_lines"] = missing_lines
		result["passed"] = false
		# Only set mode if we haven't already flagged "invalid" — invalid
		# takes priority so the caller still renders the offending-cards grid.
		if result["mode"] == "":
			result["mode"] = "missing"

	if result["mode"] == "" and not result["passed"]:
		# Shouldn't happen, but a safety net.
		result["mode"] = "missing"

	return result

# ============================================================
# RULE EVALUATION
# ============================================================

static func _card_violates(meta: Dictionary,
		card_id: String,
		no_trainers: bool,
		no_special_energies: bool,
		special_energies_only: bool,
		basic_pokemon_only: bool,
		max_hp: int,
		allowed_pokemon_types: Array,
		allowed_energy_types: Array,
		allowed_set_ids: Array,
		delta_species_only: bool,
		no_ex_cards: bool,
		allowed_name_prefixes: Array,
		banned_name_prefixes: Array) -> bool:
	var super_type := String(meta.get("supertype", "")).to_lower()
	var subtypes := []
	if meta.get("subtypes", null) is Array:
		subtypes = meta["subtypes"]
	var types := []
	if meta.get("types", null) is Array:
		types = meta["types"]
	var card_name := String(meta.get("name", ""))

	# Set membership applies to ALL card types (Pokémon, Trainer, Energy).
	if not allowed_set_ids.is_empty():
		var set_prefix := _card_set_id(card_id)
		if set_prefix == "" or set_prefix not in allowed_set_ids:
			return true

	# Pokémon-ex rule also applies to all cards via subtypes (only Pokémon
	# carry the "ex" subtype, but a uniform check keeps the logic simple).
	if no_ex_cards:
		for st in subtypes:
			if String(st).to_lower() == "ex":
				return true

	# Trainer rules
	if super_type == TRAINER_SUPERTYPE:
		if no_trainers:
			return true
		# Trainers ignore Pokemon/energy rules — no further checks.
		return false

	# Energy rules
	if super_type == ENERGY_SUPERTYPE:
		var is_special := false
		var is_basic := false
		for st in subtypes:
			var stl := String(st).to_lower()
			if stl == "special":
				is_special = true
			elif stl == "basic":
				is_basic = true
		if no_special_energies and is_special:
			return true
		if special_energies_only and not is_special:
			return true
		if not allowed_energy_types.is_empty():
			# Match energy type from the card NAME (e.g. "Fire Energy" → "fire"),
			# NOT the id — different sets share the same "Fire Energy" name.
			var energy_type := _energy_type_from_name(card_name)
			if energy_type == "" or energy_type not in allowed_energy_types:
				return true
		return false

	# Pokémon rules
	if super_type == POKEMON_SUPERTYPE:
		if basic_pokemon_only:
			var is_basic_pkmn := false
			for st in subtypes:
				var stl := String(st).to_lower()
				if stl == "basic" or stl == "baby":
					is_basic_pkmn = true
					break
			if not is_basic_pkmn:
				return true
		if max_hp > 0:
			var hp_str := String(meta.get("hp", ""))
			if hp_str.is_valid_int() and int(hp_str) > max_hp:
				return true
		if not allowed_pokemon_types.is_empty():
			var matched := false
			for t in types:
				if String(t).to_lower() in allowed_pokemon_types:
					matched = true
					break
			if not matched:
				return true
		# Delta species — name contains " δ" (typically as a suffix).
		if delta_species_only and not _name_is_delta(card_name):
			return true
		# Name-prefix rules (Dark / Light / etc.) — compared case-insensitively.
		# allowed_name_prefixes / banned_name_prefixes are pre-lowered.
		var name_lower := card_name.to_lower()
		if not allowed_name_prefixes.is_empty():
			var prefix_ok := false
			for p in allowed_name_prefixes:
				if name_lower.begins_with(String(p)):
					prefix_ok = true
					break
			if not prefix_ok:
				return true
		if not banned_name_prefixes.is_empty():
			for p in banned_name_prefixes:
				if name_lower.begins_with(String(p)):
					return true
		return false

	# Unknown supertype — be permissive.
	return false

# "base1-27" → "base1"  ;  empty if the id is malformed.
static func _card_set_id(card_id: String) -> String:
	var parts := card_id.split("-")
	if parts.size() < 2:
		return ""
	return String(parts[0]).to_lower()

# Pokémon TCG Delta Species cards have " δ" appended to the species name.
static func _name_is_delta(card_name: String) -> bool:
	return card_name.find(" δ") != -1

# Lower-cases and trims a name array. Energy types are stored in
# the data with a capital first letter ("Fire", "Water", etc.) so
# everything is compared in lowercase to avoid surprises.
static func _normalise_string_array(arr) -> Array[String]:
	var out: Array[String] = []
	if not (arr is Array):
		return out
	for v in arr:
		var s := String(v).strip_edges().to_lower()
		if s != "":
			out.append(s)
	return out

# "Fire Energy" → "fire" ; "Double Colorless Energy" → "double colorless"
# Used so allowed_energy_types matching is done by NAME, not id, so the same
# rule (e.g. Fire-only) admits Fire Energies from any set.
static func _energy_type_from_name(name: String) -> String:
	var n := name.to_lower().strip_edges()
	if n.ends_with(" energy"):
		return n.substr(0, n.length() - 7).strip_edges()
	return n

static func _count_by_id(deck_entries: Array, target_id: String) -> int:
	var total := 0
	for entry in deck_entries:
		if String(entry["id"]).to_lower() == target_id:
			total += int(entry.get("count", 0))
	return total

static func _count_by_name(deck_entries: Array, meta_by_id: Dictionary, target_name: String) -> int:
	var total := 0
	var tlower := target_name.to_lower()
	for entry in deck_entries:
		var cid: String = entry["id"]
		var meta = meta_by_id.get(cid, null)
		if meta is Dictionary and String(meta.get("name", "")).to_lower() == tlower:
			total += int(entry.get("count", 0))
	return total

static func _count_stage_2_pokemon(deck_entries: Array, meta_by_id: Dictionary) -> int:
	var total := 0
	for entry in deck_entries:
		var cid: String = entry["id"]
		var meta = meta_by_id.get(cid, null)
		if not (meta is Dictionary):
			continue
		if String(meta.get("supertype", "")).to_lower() != POKEMON_SUPERTYPE:
			continue
		var subtypes = meta.get("subtypes", [])
		if not (subtypes is Array):
			continue
		for st in subtypes:
			if String(st).to_lower() == "stage 2":
				total += int(entry.get("count", 0))
				break
	return total

# Returns the full set of card ids representing the banlist for display.
# - banned_card_ids are taken as-is.
# - banned_card_names are resolved to one representative id per name by
#   walking every set on disk in lexicographic order and taking the first
#   match. That gives the player one printable image per banned card name.
static func _expand_banlist_to_ids(banned_ids: Array, banned_names: Array) -> Array[String]:
	var out: Array[String] = []
	for raw_id in banned_ids:
		var s := String(raw_id)
		if s != "" and s not in out:
			out.append(s)

	if banned_names.is_empty():
		return out

	# Walk every set JSON in res://Card_Set_Data/ once.
	var set_paths := _list_card_set_paths()
	var remaining := banned_names.duplicate()
	for set_path in set_paths:
		if remaining.is_empty():
			break
		var cards := _load_card_set(set_path)
		for c in cards:
			if not (c is Dictionary):
				continue
			var cname := String(c.get("name", "")).to_lower()
			if cname == "":
				continue
			if cname in remaining:
				var cid := String(c.get("id", ""))
				if cid != "" and cid not in out:
					out.append(cid)
				remaining.erase(cname)
				if remaining.is_empty():
					break
	return out

static func _list_card_set_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://Card_Set_Data")
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json") and fname != "pack_prices.json":
			out.append("res://Card_Set_Data/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

# ============================================================
# DECK & METADATA LOADERS
# ============================================================

static func _load_deck_entries(deck_path: String) -> Array:
	var f := FileAccess.open(deck_path, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		return parsed
	return []

static func _lookup_metadata(card_id: String):
	var parts := card_id.split("-")
	if parts.size() != 2:
		return null
	var set_id := String(parts[0])
	var cards := _load_card_set("res://Card_Set_Data/" + set_id + ".json")
	for c in cards:
		if c is Dictionary and String(c.get("id", "")).to_lower() == card_id.to_lower():
			return c
	return null

static func _load_card_set(path: String) -> Array:
	if _set_cache.has(path):
		return _set_cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_set_cache[path] = []
		return []
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		_set_cache[path] = parsed
		return parsed
	_set_cache[path] = []
	return []

# ============================================================
# DISPLAY HELPERS
# ============================================================

# "Fire" → "Fire" ; ["Fire","Water"] → "Fire / Water"
static func _join_types_pretty(types: Array) -> String:
	var out: Array[String] = []
	for t in types:
		var s := String(t)
		if s == "":
			continue
		# Capitalise first character only for display; types are stored lower.
		out.append(s.substr(0, 1).to_upper() + s.substr(1))
	return " / ".join(out)

# Returns the absolute card image path used by the popup.
static func card_image_path(card_id: String) -> String:
	var parts := card_id.split("-")
	if parts.size() != 2:
		return ""
	return "res://Image_Assets/Card_Image_Library/" + String(parts[0]) + "/Large/" + card_id + ".png"
