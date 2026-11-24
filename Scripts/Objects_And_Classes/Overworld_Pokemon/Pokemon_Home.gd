class_name PokemonHome
extends RefCounted

## POKÉMON AT HOME (2026-11-24, GROUNDWORK -- the user is still settling the details).
##
## The rules as they stand:
##   * You cannot go to bed with a follower unless it has a bed in your house.
##     Going to bed puts it in a free bed that fits it. If every bed that fits it is
##     taken, you are asked to let the sleeper go (the "conflict"). If no bed fits, you
##     are asked to let the follower go. Either way the bed stays shut until it is settled.
##   * The house has home_slots bed spaces (Pokemon_Beds.json, 3 for now). Each bed holds
##     ONE Pokémon. A Pokémon with a bed that is not following you wanders the house
##     (PokemonHomeWanderer). A "water" bed's Pokémon swims there instead, so it does not
##     wander (no tank art yet).
##   * In the house: talk to your follower to leave it at home (it keeps its bed), or talk
##     to a Pokémon at home to take it out with you.
##   * Letting a Pokémon go (back to the wild) also frees its bed.
##
## Save: GameState.progress["home_beds"] = [{"bed": name, "pokemon": species or ""}, ...]
## (placed beds, at most home_slots); progress["spare_beds"] = {name: count} for beds
## owned with no space for them (the bed-swap screen will use it).
## Data: NPC_and_Opponent_Data/Pokemon/Pokemon_Beds.json (placeholder beds).
##
## Still to build: shops that sell beds (the user's), a screen to swap which beds are
## placed, bed/tank art in the house, home Pokémon sleeping in their beds at night, a
## choice between several sleepers in a conflict (it takes the first for now).

const BEDS_PATH := "res://NPC_and_Opponent_Data/Pokemon/Pokemon_Beds.json"
## Which scene the home Pokémon wander in (matched against the map's scene path).
const HOME_WANDER_SCENE := "Player_House_Downstairs"
## Every scene that counts as "in your house" for leaving/taking out a follower.
const HOME_SCENES := ["Player_House_Downstairs", "Player_House_Upstairs"]
const DEFAULT_SLOTS := 3

static var _data: Dictionary = {}
static var _loaded: bool = false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(BEDS_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(BEDS_PATH))
			if parsed is Dictionary:
				_data = parsed
			else:
				push_error("PokemonHome: %s is not a JSON object" % BEDS_PATH)
	return _data


static func reload() -> void:
	_loaded = false


static func home_slots() -> int:
	return int(data().get("home_slots", DEFAULT_SLOTS))


static func bed_names() -> Array:
	var beds = data().get("beds", {})
	return (beds as Dictionary).keys() if beds is Dictionary else []


static func bed_info(bed_name: String) -> Dictionary:
	var beds = data().get("beds", {})
	var info = (beds as Dictionary).get(bed_name, {}) if beds is Dictionary else {}
	return info if info is Dictionary else {}


static func is_water_bed(bed_name: String) -> bool:
	return bool(bed_info(bed_name).get("water", false))


## Does `bed_name` fit this species? By display name, by overworld template, or any.
static func bed_fits(bed_name: String, species_key: String) -> bool:
	var info := bed_info(bed_name)
	if info.is_empty():
		return false
	if bool(info.get("accepts_any", false)):
		return true
	var name := OverworldPokemonData.display_name(species_key).to_lower()
	for liked in info.get("accepts", []):
		if str(liked).to_lower() == name:
			return true
	var templates: Array = OverworldPokemonData.species_info(species_key).get("templates", [])
	for t in info.get("accepts_templates", []):
		if str(t) in templates:
			return true
	return false


# ---- the house --------------------------------------------------------------

static func beds() -> Array:
	return GameState.get_home_beds()


## Index of the bed this species sleeps in, -1 for none.
static func bed_of(species_key: String) -> int:
	if species_key == "":
		return -1
	var list := beds()
	for i in list.size():
		if str(list[i].get("pokemon", "")) == species_key:
			return i
	return -1


static func free_bed_for(species_key: String) -> int:
	var list := beds()
	for i in list.size():
		if str(list[i].get("pokemon", "")) == "" and bed_fits(str(list[i].get("bed", "")), species_key):
			return i
	return -1


## Beds that fit this species but someone else is sleeping in.
static func taken_beds_for(species_key: String) -> Array:
	var out: Array = []
	var list := beds()
	for i in list.size():
		var sleeper := str(list[i].get("pokemon", ""))
		if sleeper != "" and sleeper != species_key and bed_fits(str(list[i].get("bed", "")), species_key):
			out.append(i)
	return out


## Puts `species_key` in bed `index`. Anyone already in it goes back to the wild (and stops
## following, if it was). Returns who was turned out, "" for nobody.
static func assign(species_key: String, index: int) -> String:
	var list := beds()
	if index < 0 or index >= list.size():
		return ""
	var old := bed_of(species_key)
	if old >= 0:
		list[old]["pokemon"] = ""
	var turned_out := str(list[index].get("pokemon", ""))
	list[index]["pokemon"] = species_key
	GameState.set_home_beds(list)
	if turned_out != "" and turned_out == GameState.get_follower():
		GameState.clear_follower()
	return turned_out


## A Pokémon goes back to the wild: off your heels AND out of its bed.
static func release(species_key: String) -> void:
	var i := bed_of(species_key)
	if i >= 0:
		var list := beds()
		list[i]["pokemon"] = ""
		GameState.set_home_beds(list)
	if GameState.get_follower() == species_key:
		GameState.clear_follower()


## Gives a bed: into the first free space in the house, else kept spare. True if placed.
static func add_bed(bed_name: String) -> bool:
	var list := beds()
	if list.size() < home_slots():
		list.append({"bed": bed_name, "pokemon": ""})
		GameState.set_home_beds(list)
		return true
	GameState.add_spare_bed(bed_name)
	return false


## The Pokémon living at home that are NOT following you right now.
static func at_home() -> Array:
	var out: Array = []
	for entry in beds():
		var sleeper := str(entry.get("pokemon", ""))
		if sleeper != "" and sleeper != GameState.get_follower():
			out.append({"species": sleeper, "bed": str(entry.get("bed", ""))})
	return out


## What happens to the old follower when a new one replaces it, for the message box.
static func old_follower_note(old_species: String) -> String:
	if old_species == "":
		return ""
	var name := OverworldPokemonData.display_name(old_species)
	if bed_of(old_species) >= 0:
		return "(%s went back to your house.)" % name
	return "(%s went back to the wild.)" % name


static func in_house(scene_path: String) -> bool:
	for scene in HOME_SCENES:
		if scene in scene_path:
			return true
	return false


# ---- going to bed -----------------------------------------------------------

## Can the player sleep with the follower they have?
##   {"result": "ok"}                              no follower, or it already has a bed
##   {"result": "free", "bed": i}                  it will take free bed i
##   {"result": "conflict", "bed": i, "sleeper": s} its bed kind is full; i is the first
##   {"result": "no_bed"}                          nothing in the house fits it
static func sleep_check() -> Dictionary:
	var follower := GameState.get_follower()
	if follower == "" or bed_of(follower) >= 0:
		return {"result": "ok"}
	var free := free_bed_for(follower)
	if free >= 0:
		return {"result": "free", "bed": free}
	var taken := taken_beds_for(follower)
	if not taken.is_empty():
		var i: int = taken[0]
		return {"result": "conflict", "bed": i, "sleeper": str(beds()[i].get("pokemon", ""))}
	return {"result": "no_bed"}


# ---- spawning the home Pokémon ----------------------------------------------

## Puts every home Pokémon (not following, not in a water bed) wandering `map_root`,
## around nodes in group "home_pokemon_spot" if the scene has any, else near `around`.
static func spawn_wanderers(map_root: Node, around: Vector2) -> void:
	if map_root == null:
		return
	for old in map_root.get_tree().get_nodes_in_group(PokemonHomeWanderer.GROUP):
		(old as OverworldPokemon).despawn()
	var spots: Array = map_root.get_tree().get_nodes_in_group("home_pokemon_spot")
	var n := 0
	for entry in at_home():
		if is_water_bed(str(entry["bed"])):
			continue
		var species_key := str(entry["species"])
		if not ResourceLoader.exists(OverworldPokemonData.sheet_path(species_key)):
			continue
		var at: Vector2 = around + Vector2(-30 + 30 * (n % 3), 24 + 18 * int(n / 3))
		if n < spots.size() and spots[n] is Node2D:
			at = (spots[n] as Node2D).global_position
		PokemonHomeWanderer.spawn(map_root, species_key, at)
		n += 1
