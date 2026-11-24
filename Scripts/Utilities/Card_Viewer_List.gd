class_name CardViewerList
extends RefCounted

# ============================================================
# SHARED CARD-COLLECTION VIEWER (extracted from Deck_Build_And_Card_View_Script.gd)
# ============================================================
# Everything the "view deck" screen uses to turn a {card_id: count} dictionary into
#   1. a display ORDER for the card grid, and
#   2. the right-hand INDIVIDUAL / CATEGORIES text list beside it.
#
# It lives here rather than in the deck builder because the Card Buyer's bulk-sell
# screen shows the exact same thing for a different set of cards, and the two must
# never drift apart. Nothing in here reads deck state or touches the tree beyond the
# parent it is handed.
#
# CARD METADATA is NOT owned here. Every entry point takes a `meta_fn` Callable of the
# shape `func(card_id: String) -> Variant` returning the card's metadata dictionary
# (name / supertype / subtypes / types / evolvesFrom / rarity) or null. The deck
# builder passes its own cache, which carries extra fields the search screen needs;
# the sell screen passes a smaller one. Neither has to know about the other.
# ============================================================


# Display order for Pokémon types in the card grid.
const POKEMON_TYPE_DISPLAY_ORDER : Array = [
	"Grass", "Fire", "Water", "Lightning", "Psychic",
	"Fighting", "Darkness", "Metal", "Colorless",
]


# ─── Sorting ─────────────────────────────────────────────────────────────────

## Stage of a Pokémon card: 2 / 1 / 0 (Basic) / -1 (Baby).
static func card_stage(card_id: String, meta_fn: Callable) -> int:
	var meta = meta_fn.call(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stage 2" in subtypes:
		return 2
	if "Stage 1" in subtypes:
		return 1
	if "Baby" in subtypes:
		return -1
	return 0


## Sort priority for a Trainer subtype: 0 = Normal, 1 = Stadium, 2 = Tool.
static func trainer_subtype_priority(card_id: String, meta_fn: Callable) -> int:
	var meta = meta_fn.call(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stadium" in subtypes:
		return 1
	if "Tool" in subtypes or "Pokémon Tool" in subtypes:
		return 2
	return 0


## Card name for sorting, falling back to the id when metadata is missing.
static func _sort_name(card_id: String, meta_fn: Callable) -> String:
	var meta = meta_fn.call(card_id)
	return str(meta.get("name", card_id)) if meta != null else card_id


## Sorts energy card_ids: Special Energy first, then Basic, alphabetically within each.
static func sort_energy(energy_ids: Array, meta_fn: Callable) -> Array:
	var special : Array = []
	var basic   : Array = []
	for cid in energy_ids:
		var meta = meta_fn.call(cid)
		if meta != null and "Special" in meta.get("subtypes", []):
			special.append(cid)
		else:
			basic.append(cid)
	var name_sort := func(a: String, b: String) -> bool:
		return _sort_name(a, meta_fn) < _sort_name(b, meta_fn)
	special.sort_custom(name_sort)
	basic.sort_custom(name_sort)
	return special + basic


## Sorts trainer card_ids: Normal → Stadium → Tool, alphabetically within each group.
static func sort_trainers(trainer_ids: Array, meta_fn: Callable) -> Array:
	trainer_ids.sort_custom(func(a: String, b: String) -> bool:
		var pa : int = trainer_subtype_priority(a, meta_fn)
		var pb : int = trainer_subtype_priority(b, meta_fn)
		if pa != pb:
			return pa < pb
		return _sort_name(a, meta_fn) < _sort_name(b, meta_fn)
	)
	return trainer_ids


## Groups Pokémon in one type bucket into evolution families, then sorts:
##   Segments ordered by max_stage DESC; standalones before families of same max_stage.
##   Within a family: Stage 2 → Stage 1 → Basic → Baby.
static func sort_type_group_pokemon(type_ids: Array, meta_fn: Callable) -> Array:
	if type_ids.is_empty():
		return type_ids

	# name → [card_ids] for cards in this group
	var name_to_ids : Dictionary = {}
	for cid in type_ids:
		var cname : String = _sort_name(cid, meta_fn)
		if not name_to_ids.has(cname):
			name_to_ids[cname] = []
		(name_to_ids[cname] as Array).append(cid)

	# Union-find: group_of[cid] = representative id
	var group_of : Dictionary = {}
	for cid in type_ids:
		group_of[cid] = cid

	# Three passes handles Stage 2 chains (Basic→Stage1→Stage2)
	for _pass in range(3):
		for cid in type_ids:
			var meta = meta_fn.call(cid)
			if meta == null:
				continue
			var from_name : String = meta.get("evolvesFrom", "")
			if from_name == "" or not name_to_ids.has(from_name):
				continue
			# Path-compress my root
			var my_root : String = group_of[cid]
			while group_of[my_root] != my_root:
				my_root = group_of[my_root]
			# Union with each "from" card's root
			for from_cid in (name_to_ids[from_name] as Array):
				var from_root : String = group_of[from_cid]
				while group_of[from_root] != from_root:
					from_root = group_of[from_root]
				if my_root != from_root:
					group_of[from_root] = my_root

	# Path-compress all
	for cid in type_ids:
		var root : String = group_of[cid]
		while group_of[root] != root:
			root = group_of[root]
		group_of[cid] = root

	# Build segments keyed by root
	var segments : Dictionary = {}
	for cid in type_ids:
		var root : String = group_of[cid]
		if not segments.has(root):
			segments[root] = []
		(segments[root] as Array).append(cid)

	# Build segment metadata and sort cards within each segment by stage DESC
	var segment_list : Array = []
	for root in segments:
		var seg_cards : Array = segments[root]
		var max_stage : int = -99
		for cid in seg_cards:
			var s : int = card_stage(cid, meta_fn)
			if s > max_stage:
				max_stage = s
		seg_cards.sort_custom(func(a: String, b: String) -> bool:
			return card_stage(a, meta_fn) > card_stage(b, meta_fn)
		)
		segment_list.append({
			"cards":       seg_cards,
			"max_stage":   max_stage,
			"standalone":  seg_cards.size() == 1,
			"first_name":  _sort_name(seg_cards[0], meta_fn),
		})

	# Sort segments: max_stage DESC → standalone first (true > false) → name ASC
	segment_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["max_stage"] != b["max_stage"]:
			return a["max_stage"] > b["max_stage"]
		if a["standalone"] != b["standalone"]:
			return a["standalone"]  # true sorts before false
		return a["first_name"] < b["first_name"]
	)

	var result : Array = []
	for seg in segment_list:
		result.append_array(seg["cards"])
	return result


## Returns the full sorted card_id list, ready for the viewer grid.
## Order: Pokémon by type → Trainers (Normal/Stadium/Tool) → Energy (Special/Basic).
static func sort_ids(card_ids: Array, meta_fn: Callable) -> Array:
	var pokemon_by_type : Dictionary = {}
	var trainer_ids     : Array      = []
	var energy_ids      : Array      = []

	for card_id in card_ids:
		var meta = meta_fn.call(card_id)
		if meta == null:
			continue
		var supertype : String = meta.get("supertype", "")
		if supertype == "Pokémon":
			var types  : Array  = meta.get("types", [])
			var ptype  : String = types[0] if types.size() > 0 else "Colorless"
			if not pokemon_by_type.has(ptype):
				pokemon_by_type[ptype] = []
			(pokemon_by_type[ptype] as Array).append(card_id)
		elif supertype == "Trainer":
			trainer_ids.append(card_id)
		elif supertype == "Energy":
			energy_ids.append(card_id)

	var result : Array = []
	for ptype in POKEMON_TYPE_DISPLAY_ORDER:
		if pokemon_by_type.has(ptype):
			result.append_array(sort_type_group_pokemon(pokemon_by_type[ptype], meta_fn))
	result.append_array(sort_trainers(trainer_ids, meta_fn))
	result.append_array(sort_energy(energy_ids, meta_fn))
	return result


# AUDIT 2026-11-24: removed the right-hand text list (ISSUE #154): build_side_list() and its font fits /
# constants. The deck viewer replaced it with boxed rows (_build_viewer_contents) and the bulk-sell screen
# no longer calls it, so nothing used any of it.
