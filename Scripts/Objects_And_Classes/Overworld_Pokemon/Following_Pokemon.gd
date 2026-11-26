class_name FollowingPokemon
extends RefCounted

## FOLLOWING POKÉMON (2026-11-24) -- the rules side: which foods a species likes, the
## befriend roll, and putting the follower on a map. The walking is PokemonFollower.
##
## How a Pokémon starts following you:
##   * Land: talk to a wild overworld Pokémon (Space) while a food it likes is in the
##     bag -> "offer it some?" -> Yes rolls the food's `chance`. Skittish ones (rats)
##     bolt unless you SNEAK up on them -- hold Ctrl (PlayerObject.is_sneaking()).
##   * Fishing: land a fish while a food it likes is in the bag -> the same roll; on a
##     success it follows you instead of going to the FISH tanks or back in the water.
## One follower at a time; a new friend sends the old one to live at your house
## (PokemonHome; GameState.befriended remembers every one). Talk to your follower while
## facing it to leave it at home (in the house) or let it go (anywhere else).
##
## Data: which food each Pokémon likes = Pokemon_Food_And_Beds.csv (PokemonPrefs);
## each food's chance / description / sprite = Pokemon_Foods.json.
## Save: GameState.get_follower / set_follower / food_count / add_food / use_food.

const FOODS_PATH := "res://NPC_and_Opponent_Data/Pokemon/Pokemon_Foods.json"

# ---- tweakables -------------------------------------------------------------
## Does a failed offer still eat the food? false = only a success uses it up.
const CONSUME_ON_FAIL := false
## Does a failed FISHING roll eat the food? (The fish bit the bait either way.)
const CONSUME_ON_FAIL_FISHING := false
## Chance used when a food entry has no `chance`.
const DEFAULT_CHANCE := 50.0
## Food art for the bag: Image_Assets/Food/<sprite or food name>.png.
const FOOD_ART_DIR := "res://Image_Assets/Food"
## DEBUG (2026-11-24): SUPER FOOD is liked by every Pokémon, always works, and with it in
## the bag Space/click/A on ANY Pokémon you overlap (any template, flyers and bugs too)
## or any fish you land offers to make it your follower. Given by the DEL menu. Not in
## Pokemon_Foods.json on purpose.
const SUPER_FOOD := "SUPER FOOD"
## Does capturing with SUPER FOOD use one up? false = one in the bag lasts forever.
const SUPER_FOOD_USED_UP := false
## Templates SUPER FOOD cannot take: the FISH shop's tank fish are your collection there.
const UNCAPTURABLE_TEMPLATES := ["PokemonFishTank", "PokemonTankWalker", "PokemonFollower"]
## The art box used for "the player overlaps this Pokémon" is the sprite's drawn rows,
## narrowed to this fraction of the cell's width (the cell has empty sides).
const OVERLAP_WIDTH_FRACTION := 0.7
# -----------------------------------------------------------------------------

static var _foods_cache: Dictionary = {}
static var _loaded: bool = false
## Debug/tests: when >= 0 every roll uses this instead of randf() * 100.
static var forced_roll: float = -1.0


static func foods() -> Dictionary:
	if not _loaded:
		_loaded = true
		_foods_cache = {}
		if FileAccess.file_exists(FOODS_PATH):
			var data = JSON.parse_string(FileAccess.get_file_as_string(FOODS_PATH))
			if data is Dictionary and data.get("foods") is Dictionary:
				_foods_cache = data["foods"]
			else:
				push_error("FollowingPokemon: %s has no 'foods' object" % FOODS_PATH)
	return _foods_cache


static func reload() -> void:
	_loaded = false
	PokemonPrefs.reload()


## Every food: the ones the CSV names, then any extra ones only Pokemon_Foods.json has.
static func food_names() -> Array:
	var out: Array = PokemonPrefs.food_names()
	for food_name in foods().keys():
		if AssetLookup.match_key(_as_dict(out), str(food_name)) == "":
			out.append(str(food_name))
	return out


static func _as_dict(names: Array) -> Dictionary:
	var d := {}
	for n in names:
		d[n] = true
	return d


## Pokemon_Foods.json's entry for a food, matched ignoring case; {} for a CSV-only food.
static func food_info(food_name: String) -> Dictionary:
	var key := AssetLookup.match_key(foods(), food_name)
	var entry = foods().get(key, {}) if key != "" else {}
	return entry if entry is Dictionary else {}


static func food_description(food_name: String) -> String:
	return str(food_info(food_name).get("description", ""))


## The food's picture for the bag, "" until its art exists in Image_Assets/Food.
static func food_art_path(food_name: String) -> String:
	if not DirAccess.dir_exists_absolute(FOOD_ART_DIR):
		return ""
	return AssetLookup.resolve(FOOD_ART_DIR, str(food_info(food_name).get("sprite", food_name)), ".png")


## Does `food_name` attract this species? Its ONE food is the CSV's "Food" column, matched
## on display name, so every variant sheet ("019_Rattata", "019_Rattata_Alolan") counts.
static func likes(species_key: String, food_name: String) -> bool:
	if food_name == SUPER_FOOD:
		return true
	var liked := PokemonPrefs.food_of(species_key)
	return liked != "" and liked.to_lower() == food_name.strip_edges().to_lower()


static func chance(food_name: String) -> float:
	if food_name == SUPER_FOOD:
		return 100.0
	return float(food_info(food_name).get("chance", DEFAULT_CHANCE))


## The best liked food the player is carrying for `species_key` (highest chance), "" for none.
static func liked_food_in_bag(species_key: String) -> String:
	if has_super_food():
		return SUPER_FOOD
	var best := ""
	var best_chance := -1.0
	for food_name in GameState.get_foods().keys():
		if str(food_name) == SUPER_FOOD or GameState.food_count(str(food_name)) <= 0 or not likes(species_key, str(food_name)):
			continue
		if chance(str(food_name)) > best_chance:
			best = str(food_name)
			best_chance = chance(str(food_name))
	return best


## Rolls the befriend chance for `food_name` and uses the food up as the tweakables say.
## True = it wants to follow you (the caller makes it the follower).
static func try_befriend(food_name: String, fishing: bool = false) -> bool:
	if GameState.food_count(food_name) <= 0:
		return false
	var roll := forced_roll if forced_roll >= 0.0 else randf() * 100.0
	var success := roll < chance(food_name)
	var consume_on_fail := CONSUME_ON_FAIL_FISHING if fishing else CONSUME_ON_FAIL
	if food_name == SUPER_FOOD and not SUPER_FOOD_USED_UP:
		return success
	if success or consume_on_fail:
		GameState.use_food(food_name)
	return success


static func has_super_food() -> bool:
	return GameState.food_count(SUPER_FOOD) > 0


## Can SUPER FOOD take this Pokémon? Any live, visible overworld Pokémon but your own
## follower and the FISH tank fish.
static func capturable(pokemon: Node) -> bool:
	if not (pokemon is OverworldPokemon) or not is_instance_valid(pokemon) or pokemon.is_queued_for_deletion():
		return false
	var p := pokemon as OverworldPokemon
	if p._is_gone or p.sprite == null or not p.sprite.is_visible_in_tree():
		return false
	var script: Script = p.get_script()
	if script != null and script.get_global_name() in UNCAPTURABLE_TEMPLATES:
		return false
	return true


## Where the Pokémon's art is drawn, in global coordinates (its "collision" for SUPER FOOD:
## most templates have no physics shape at all).
static func art_rect(p: OverworldPokemon) -> Rect2:
	var local := p.sprite.get_rect()
	if p.clip_rows < 0 and p.cell.y > 0.0:
		var top := local.position.y + local.size.y * float(p.art_top) / p.cell.y
		var bottom := local.position.y + local.size.y * float(p.art_bottom + 1) / p.cell.y
		local = Rect2(local.position.x, top, local.size.x, maxf(1.0, bottom - top))
	var inset := local.size.x * (1.0 - OVERLAP_WIDTH_FRACTION) * 0.5
	local = local.grow_individual(-inset, 0.0, -inset, 0.0)
	return p.sprite.get_global_transform() * local


## The player's body box in global coordinates.
static func player_rect(player: Node2D) -> Rect2:
	var shape_node := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var size: Vector2 = (shape_node.shape as RectangleShape2D).size
		return Rect2(shape_node.global_position - size * 0.5, size)
	return Rect2(player.global_position - Vector2(8, 11.5), Vector2(16, 23))


## The capturable Pokémon the player is standing on (nearest first), null for none.
static func super_food_target(player: Node2D) -> OverworldPokemon:
	if player == null:
		return null
	var body := player_rect(player)
	var best: OverworldPokemon = null
	var best_d := INF
	for node in player.get_tree().get_nodes_in_group(OverworldPokemon.ALL_GROUP):
		if not capturable(node):
			continue
		var p := node as OverworldPokemon
		if not body.intersects(art_rect(p)):
			continue
		var d := player.global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## A NEW `species_key` joins you (always a new one, even if you already have that species -
## PokemonHome.recruit gives it its own ID) and walks behind the player on the current map.
## Any follower already there goes to live at your house if it can (been there + a free bed,
## PokemonHome.can_live_at_home), else back to the wild - callers warn first with
## PokemonHome.new_partner_warning(). Returns the old follower's ID, "" if none.
## `shiny` goes into its flags (PokemonHome.is_shiny): the wild one's.
static func befriend(species_key: String, at_global: Variant = null, shiny: bool = false) -> String:
	var old := PokemonHome.recruit(species_key, shiny)
	_put_follower_on_map(at_global)
	return old


## FOLLOW ME: your Pokémon `pokemon_id` (living at home) swaps places with the follower.
## Returns the old follower's ID, "" if none.
static func take_out(pokemon_id: String, at_global: Variant = null) -> String:
	var old := PokemonHome.make_follower(pokemon_id)
	_put_follower_on_map(at_global)
	return old


static func _put_follower_on_map(at_global: Variant) -> void:
	var player := _player()
	if player != null:
		PokemonFollower.spawn_for(player.get_parent(), player, at_global)
		# In the house the old follower walks about (or lies down) again.
		if PokemonHome.in_house(MapManager._map_scene_path):
			PokemonHome.refresh_house(player.get_parent())


## The follower goes back to the WILD: off your heels and out of the house for good
## (PokemonHome.release). Leaving it at home instead is MapManager._leave_follower_home.
static func send_home() -> void:
	PokemonHome.release(GameState.get_follower())
	var player := _player()
	if player == null:
		return
	for node in player.get_tree().get_nodes_in_group(PokemonFollower.GROUP):
		(node as OverworldPokemon).despawn()


static func _player() -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("player") as Node2D if tree != null else null
