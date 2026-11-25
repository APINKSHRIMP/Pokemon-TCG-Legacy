class_name PokemonHome
extends RefCounted

## POKÉMON AT HOME (2026-11-24).
##
## The roster: one ACTIVE follower (GameState.get_follower) plus any number of INACTIVE ones
## living in the house (GameState.get_home_pokemon, oldest first).
##   * Befriending a new Pokémon never asks you to dismiss anyone: the old follower just goes
##     home and becomes inactive.
##   * In the house, talk to your follower to leave it at home; talk to a Pokémon at home to
##     swap it with your follower.
##   * Beds are NOT needed until bedtime. Going to sleep warns about every Pokémon (active
##     too) with no bed: they leave while you sleep.
##   * Changing a bed that an INACTIVE Pokémon sleeps in warns first, and Yes dismisses it.
##     Changing your active follower's bed never warns (bedtime does).
##
## Beds: the bedroom has home_slots spaces (PokemonBedSpot, positions in Pokemon_Beds.json
## "bedroom_spots"). Each Pokémon sleeps in one KIND of bed (PokemonPrefs, the CSV). Who gets
## which bed is WORKED OUT, never saved: inactive Pokémon in order, then the follower, each
## takes the first free space holding its kind of bed.
##
## Where they are: by day the inactive ones wander downstairs (HOME_WANDER_SCENE); at night
## the ones with a bed sleep on it in the bedroom, and the bedless ones stay downstairs. A
## Pokémon whose bed is a water tank is always in its tank.
##
## Save: GameState home_pokemon / bed_slots / spare_beds (see Game_State_Script.gd).
##
## IDs (2026-11-24): you can own as many of one species as you like, so everything here (the
## follower, the home list, the flags, the bed assignment) is keyed by each Pokémon's ID - the
## species key for the first one ("019_Rattata"), then "019_Rattata#2", "019_Rattata#3"...
## (new_id). species_of(id) gives the species back for art, cries, the CSV and the Field Guide;
## id_of(node) is the ID of a follower / home Pokémon on the map.

const BEDS_PATH := "res://NPC_and_Opponent_Data/Pokemon/Pokemon_Beds.json"
const BED_ART_DIR := "res://Image_Assets/Beds"
## Where the home Pokémon wander by day (matched against the map's scene path).
const HOME_WANDER_SCENE := "Player_House_Downstairs"
## Where the beds are.
const BEDROOM_SCENE := "Player_House_Upstairs"
## Every scene that counts as "in your house" for leaving a follower at home.
const HOME_SCENES := ["Player_House_Downstairs", "Player_House_Upstairs"]

# ---- tweakables (Pokemon_Beds.json overrides the first three) -----------------
const DEFAULT_SLOTS := 3
const DEFAULT_BED := "Hay Bale"
const DEFAULT_SPOTS := [Vector2(60, 190), Vector2(130, 200), Vector2(200, 190)]
## A bed with no "seat": the sleeper's feet go this far down the bed's height.
const DEFAULT_SEAT_FRACTION := 0.62
## Size of the grey box drawn for a bed whose sprite file does not exist yet (the tanks).
const PLACEHOLDER_SIZE := Vector2(48, 40)
# -----------------------------------------------------------------------------

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}


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
	_textures.clear()
	PokemonPrefs.reload()


# ---- the bed list -------------------------------------------------------------

static func home_slots() -> int:
	return int(data().get("home_slots", DEFAULT_SLOTS))


## TESTING SWITCH (Pokemon_Beds.json "any_pokemon_any_bed"): every Pokémon fits every bed,
## so only HAVING a bed matters, not the CSV's bed kind.
static func any_bed_fits() -> bool:
	return bool(data().get("any_pokemon_any_bed", false))


static func default_bed() -> String:
	var bed := canonical_bed(str(data().get("default_bed", DEFAULT_BED)))
	return bed if bed != "" else DEFAULT_BED


static func bed_names() -> Array:
	var beds = data().get("beds", {})
	return (beds as Dictionary).keys() if beds is Dictionary else []


static func bed_info(bed_name: String) -> Dictionary:
	var beds = data().get("beds", {})
	var info = (beds as Dictionary).get(bed_name, {}) if beds is Dictionary else {}
	return info if info is Dictionary else {}


static func _norm(text: String) -> String:
	return text.strip_edges().to_lower().replace("_", " ").replace("  ", " ")


## The bed's key as Pokemon_Beds.json spells it, from its name or sprite file name typed
## any old way ("hay bale", "Haybale", "Lily_Pad_Big"). "" when there is no such bed.
static func canonical_bed(written: String) -> String:
	var wanted := _norm(written)
	if wanted == "":
		return ""
	for bed_name in bed_names():
		if _norm(str(bed_name)) == wanted or _norm(str(bed_info(str(bed_name)).get("sprite", ""))) == wanted:
			return str(bed_name)
	# "haybale" vs "hay bale"
	wanted = wanted.replace(" ", "")
	for bed_name in bed_names():
		if _norm(str(bed_name)).replace(" ", "") == wanted:
			return str(bed_name)
	return ""


static func is_water_bed(bed_name: String) -> bool:
	return bool(bed_info(bed_name).get("water", false))


static func bed_description(bed_name: String) -> String:
	return str(bed_info(bed_name).get("description", ""))


## The bed's art: {"texture": Texture2D or null, "frames": int, "fps": float, "size": Vector2
## (one frame; PLACEHOLDER_SIZE with no texture)}.
static func bed_art(bed_name: String) -> Dictionary:
	if _textures.has(bed_name):
		return _textures[bed_name]
	var info := bed_info(bed_name)
	var frames := maxi(1, int(info.get("frames", 1)))
	var path := AssetLookup.resolve(BED_ART_DIR, str(info.get("sprite", bed_name)), ".png")
	var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	var size := PLACEHOLDER_SIZE
	if tex != null:
		size = Vector2(floorf(tex.get_width() / float(frames)), tex.get_height())
	var art := {"texture": tex, "frames": frames if tex != null else 1,
			"fps": float(info.get("fps", 8.0)), "size": size}
	_textures[bed_name] = art
	return art


## A still picture of the bed for menus (the bag): "icon" if the bed has one, else the sprite.
static func bed_icon_path(bed_name: String) -> String:
	var info := bed_info(bed_name)
	return AssetLookup.resolve(BED_ART_DIR, str(info.get("icon", info.get("sprite", bed_name))), ".png")


## Px down from the bed's top edge where a sleeper's feet go.
static func seat_from_top(bed_name: String) -> float:
	var size: Vector2 = bed_art(bed_name)["size"]
	var info := bed_info(bed_name)
	if info.has("seat"):
		return minf(float(info["seat"]), size.y)
	return roundf(size.y * DEFAULT_SEAT_FRACTION)


# ---- bedroom spots --------------------------------------------------------------

## Where each bed space is in the bedroom: the bed's bottom-centre, map coordinates.
static func bedroom_spots() -> Array:
	var out: Array = []
	var raw = data().get("bedroom_spots", [])
	for i in home_slots():
		var p: Vector2 = DEFAULT_SPOTS[i % DEFAULT_SPOTS.size()] + Vector2(70 * int(i / DEFAULT_SPOTS.size()), 0)
		if raw is Array and i < raw.size() and raw[i] is Array and (raw[i] as Array).size() >= 2:
			p = Vector2(float(raw[i][0]), float(raw[i][1]))
		out.append(p)
	return out


## The debug mover's Enter: writes "bedroom_spots" into Pokemon_Beds.json, touching nothing
## else in the file. Only works where res:// is writable (running from the editor/project).
static func save_bedroom_spots(points: Array) -> String:
	var parts: Array = []
	for p in points:
		parts.append("[%d, %d]" % [roundi((p as Vector2).x), roundi((p as Vector2).y)])
	var line := "\"bedroom_spots\": [%s]" % ", ".join(PackedStringArray(parts))
	var text := FileAccess.get_file_as_string(BEDS_PATH)
	if text == "":
		return "Could not read %s." % BEDS_PATH
	var re := RegEx.new()
	re.compile("\"bedroom_spots\"\\s*:\\s*\\[(?:\\s*\\[[^\\]]*\\]\\s*,?)*\\s*\\]")
	if re.search(text) == null:
		return "No \"bedroom_spots\" line found in %s." % BEDS_PATH
	text = re.sub(text, line)
	var f := FileAccess.open(BEDS_PATH, FileAccess.WRITE)
	if f == null:
		return "Could not write %s (%s)." % [BEDS_PATH, error_string(FileAccess.get_open_error())]
	f.store_string(text)
	f.close()
	_loaded = false
	return ""


# ---- slots and who sleeps where -------------------------------------------------

## The bed in each space, always home_slots long ("" = empty).
static func slots() -> Array:
	var list := GameState.get_bed_slots()
	list.resize(home_slots())
	for i in list.size():
		list[i] = "" if list[i] == null else str(list[i])
	return list


static func home_pokemon() -> Array:
	return GameState.get_home_pokemon()


## "019_Rattata#2" -> "019_Rattata".
static func species_of(id: String) -> String:
	return OverworldPokemonData.species_of(id)


## The ID of one of your Pokémon on the map (PokemonFollower / PokemonHomeWanderer); a wild one's
## species if handed one.
static func id_of(pokemon: Node) -> String:
	if pokemon == null or not is_instance_valid(pokemon):
		return ""
	var id := str(pokemon.get("pokemon_id")) if pokemon.get("pokemon_id") != null else ""
	return id if id != "" else str(pokemon.get("species"))


## The ID a newly befriended `species_key` gets: the bare species key if it is free, else
## "#2", "#3"... - the first one not already yours.
static func new_id(species_key: String) -> String:
	var base := species_of(species_key)
	var taken := roster()
	for n in range(1, 10000):
		var id := base if n == 1 else "%s#%d" % [base, n]
		if not (id in taken) and GameState.get_pokemon_flags(id).is_empty():
			return id
	return base


## Everyone who needs a bed, in the order beds are handed out: home first, follower last.
static func roster(home: Variant = null, follower: Variant = null) -> Array:
	var out: Array = (home if home is Array else home_pokemon()).duplicate()
	var active := str(follower) if follower != null else GameState.get_follower()
	if active != "" and active not in out:
		out.append(active)
	return out


## ID -> slot index, for everyone in the roster who has a bed.
static func assignment(slot_list: Variant = null, home: Variant = null, follower: Variant = null) -> Dictionary:
	var list: Array = slot_list if slot_list is Array else slots()
	var taken := {}
	var out := {}
	var any_bed := any_bed_fits()
	for species_key in roster(home, follower):
		var kind := PokemonPrefs.bed_of(species_of(str(species_key)))
		for i in list.size():
			if not taken.has(i) and (str(list[i]) == kind or (any_bed and str(list[i]) != "")):
				taken[i] = true
				out[species_key] = i
				break
	return out


## The slot this species sleeps in, -1 for none.
static func bed_of(species_key: String) -> int:
	return int(assignment().get(species_key, -1))


## Who sleeps in slot `index`, "" for nobody.
static func sleeper_in(index: int) -> String:
	var a := assignment()
	for species_key in a:
		if int(a[species_key]) == index:
			return str(species_key)
	return ""


## INACTIVE Pokémon that have a bed now but would have none if slot `index` held `new_bed`.
static func homeless_after_change(index: int, new_bed: String) -> Array:
	var before := assignment()
	var list := slots()
	list[index] = new_bed
	var after := assignment(list)
	var out: Array = []
	for species_key in home_pokemon():
		if before.has(species_key) and not after.has(species_key):
			out.append(species_key)
	return out


## Puts `new_bed` ("" = clear) in slot `index`. use_spares: the new bed comes out of the
## spare beds and the old one goes back in (false = debug, beds from nowhere).
static func change_bed(index: int, new_bed: String, use_spares: bool) -> void:
	var list := slots()
	if index < 0 or index >= list.size():
		return
	var old := str(list[index])
	if old == new_bed:
		return
	if use_spares:
		if new_bed != "":
			GameState.add_spare_bed(new_bed, -1)
		if old != "":
			GameState.add_spare_bed(old, 1)
	list[index] = new_bed
	GameState.set_bed_slots(list)


## The order Space cycles a slot through: debug = every bed; else the slot's bed and every
## spare one. "" (empty) comes last.
static func bed_cycle(index: int, debug: bool) -> Array:
	var out: Array = []
	if debug:
		out = bed_names().duplicate()
	else:
		var current := str(slots()[index])
		var names: Array = GameState.get_spare_beds().keys()
		if current != "" and current not in names:
			names.append(current)
		for bed_name in bed_names():
			if bed_name in names:
				out.append(bed_name)
	out.append("")
	return out


## A bed for the house: into the spare beds (placed with Space on a bed space).
static func add_bed(bed_name: String) -> void:
	GameState.add_spare_bed(bed_name, 1)


# ---- names -------------------------------------------------------------------------

## TWEAKABLE: the longest nickname the rename keyboard allows.
const NICKNAME_MAX := 12

## What YOUR Pokémon is called: its nickname, else its species name. Every message about
## your follower or a Pokémon at home goes through here, so a rename shows up everywhere.
## A wild Pokémon of the same species is still called by its species name - that comes
## from OverworldPokemonData.display_name, not this.
static func name_of(species_key: String) -> String:
	var nick := GameState.get_pokemon_nickname(species_key)
	return nick if nick != "" else OverworldPokemonData.display_name(species_key)


## A typed nickname made safe: trimmed, capped, and with no [ ] - every line goes through the
## dialogue-token and emote parsers, which would eat a "[" in a name and the rest of the line.
static func clean_nickname(typed: String) -> String:
	var out := typed.replace("[", "").replace("]", "").strip_edges()
	return out.substr(0, NICKNAME_MAX)


## Is YOUR Pokémon shiny? (The "shiny" flag, set when it joins you. No shinies yet.)
static func is_shiny(species_key: String) -> bool:
	return bool(GameState.get_pokemon_flags(species_key).get("shiny", false))


## Its portrait for the message box's name pill (DynamicMessageBox.sprite_icon takes the path).
static func portrait_path(species_key: String) -> String:
	return OverworldPokemonData.sheet_path(species_of(species_key), is_shiny(species_key))


# ---- the roster -------------------------------------------------------------------

## A NEW Pokémon joins you (befriended / caught): it gets its own ID - even if you already
## have one of its species - and its flag block, and becomes the follower. Returns the old
## follower's ID, "" if none.
static func recruit(species_key: String, shiny: bool = false) -> String:
	var id := new_id(species_key)
	_ensure_flags(id, shiny)
	return make_follower(id)


## Makes the Pokémon `species_key` (an ID - one already yours, or one recruit() just made) the
## follower. The old follower goes home (inactive). Returns the old follower's ID, "" if none
## or the same one.
static func make_follower(species_key: String) -> String:
	var old := GameState.get_follower()
	# AFFECTION: the old follower is paid its hours before it stops following; the new one
	# starts counting from now (time at home does not count).
	PokemonAffection.credit_hours()
	_ensure_flags(species_key, false)
	var home := home_pokemon()
	home.erase(species_key)
	if old != "" and old != species_key and old not in home:
		home.append(old)
	GameState.set_home_pokemon(home)
	GameState.set_follower(species_key)
	if old != species_key:
		PokemonAffection.start_clock(species_key)
	return old if old != species_key else ""


## A Pokémon joining you gets its flag block: species, shiny, nickname, counts. One already
## yours (swapping in from home) keeps what it has.
static func _ensure_flags(species_key: String, shiny: bool) -> void:
	if species_key == "" or not GameState.get_pokemon_flags(species_key).is_empty():
		return
	GameState.set_pokemon_flags(species_key, {
		"species": species_of(species_key), "shiny": shiny, "name": "", "pets": 0, "meals": 0,
		"affection": 0,
	})


## EVOLUTION: your Pokémon `old` (an ID) becomes the species `into` everywhere - follower,
## home list (same place in it), flags (nickname, shiny, affection and counts carry over) -
## under a new ID for its new species, and the new species goes in the Field Guide. Returns
## the new ID (`old` if nothing changed).
static func evolve(old: String, into: String) -> String:
	if old == "" or into == "" or species_of(old) == into:
		return old
	var new := new_id(into)
	var flags := GameState.get_pokemon_flags(old)
	flags["species"] = into
	GameState.clear_pokemon_flags(old)
	GameState.set_pokemon_flags(new, flags)
	var home := home_pokemon()
	var i := home.find(old)
	if i >= 0:
		home[i] = new
		GameState.set_home_pokemon(home)
	if GameState.get_follower() == old:
		GameState.set_follower(new)
	GameState.record_pokemon_met(into)
	return new


## The follower stops following and lives at home.
static func leave_at_home() -> void:
	var follower := GameState.get_follower()
	if follower == "":
		return
	PokemonAffection.credit_hours()
	var home := home_pokemon()
	if follower not in home:
		home.append(follower)
	GameState.set_home_pokemon(home)
	GameState.clear_follower()


## A Pokémon goes back to the wild: off your heels and out of the house.
static func release(species_key: String) -> void:
	if species_key == "":
		return
	var home := home_pokemon()
	if species_key in home:
		home.erase(species_key)
		GameState.set_home_pokemon(home)
	if GameState.get_follower() == species_key:
		GameState.clear_follower()
	# Back in the wild it is just a wild one again: a friend made later starts afresh.
	GameState.clear_pokemon_flags(species_key)


## Everyone (active too) with no bed: they leave if you go to sleep.
static func homeless_at_bedtime() -> Array:
	var a := assignment()
	var out: Array = []
	for species_key in roster():
		if not a.has(species_key):
			out.append(species_key)
	return out


## What happened to the old follower when a new one replaced it, for the message box.
static func old_follower_note(old_species: String) -> String:
	if old_species == "":
		return ""
	var name := name_of(old_species)
	if old_species in home_pokemon():
		return "(%s went back to your house.)" % name
	return "(%s went back to the wild.)" % name


static func in_house(scene_path: String) -> bool:
	for scene in HOME_SCENES:
		if scene in scene_path:
			return true
	return false


## "Rattata", "Rattata and Pikachu", "Rattata, Pikachu and Pidgey".
static func names_text(species_list: Array) -> String:
	var names: Array = []
	for s in species_list:
		names.append(name_of(str(s)))
	if names.size() <= 1:
		return "".join(PackedStringArray(names))
	return ", ".join(PackedStringArray(names.slice(0, names.size() - 1))) + " and " + str(names[-1])


# ---- putting them on the map --------------------------------------------------------

## Re-places every home Pokémon on `map_root` for the scene `scene_path` and the time of day:
## wanderers downstairs, sleepers / tank swimmers on the bedroom's bed spots.
static func refresh_house(map_root: Node, scene_path: String = "") -> void:
	if map_root == null or not map_root.is_inside_tree():
		return
	if scene_path == "":
		scene_path = MapManager._map_scene_path
	for old in map_root.get_tree().get_nodes_in_group(PokemonHomeWanderer.GROUP):
		(old as OverworldPokemon).despawn()
	var night := GameState.is_night_time()
	var a := assignment()
	var list := slots()
	if HOME_WANDER_SCENE in scene_path:
		_spawn_wanderers(map_root, a, list, night)
	elif BEDROOM_SCENE in scene_path:
		var spots := {}
		for spot in map_root.get_tree().get_nodes_in_group(PokemonBedSpot.GROUP):
			spots[(spot as PokemonBedSpot).slot] = spot
			(spot as PokemonBedSpot).refresh()
		for species_key in home_pokemon():
			if not a.has(species_key) or not spots.has(int(a[species_key])):
				continue
			var water := is_water_bed(str(list[int(a[species_key])]))
			if not (water or night):
				continue
			if not ResourceLoader.exists(OverworldPokemonData.sheet_path(species_of(str(species_key)))):
				continue
			var spot: PokemonBedSpot = spots[int(a[species_key])]
			PokemonHomeWanderer.spawn_resting(map_root, str(species_key), spot.seat_global(), night)


## TWEAKABLE: how far (world px) from the player toward the room's middle home Pokémon appear
## when the map has no "home_pokemon_spot" markers.
const WANDER_START_STEP := 48.0


## The centre of the map's floor (its first TileMapLayer's used cells), global; null if none.
static func _room_middle(map_root: Node) -> Variant:
	for layer in map_root.find_children("*", "TileMapLayer", true, false):
		var tl := layer as TileMapLayer
		var used := tl.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var mid_cell := used.position + used.size / 2
		return tl.to_global(tl.map_to_local(mid_cell))
	return null


static func _spawn_wanderers(map_root: Node, a: Dictionary, list: Array, night: bool) -> void:
	var spots: Array = map_root.get_tree().get_nodes_in_group("home_pokemon_spot")
	var around := Vector2.ZERO
	var player := map_root.get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		around = player.global_position
	var inward := Vector2.UP
	var middle: Variant = _room_middle(map_root)
	if middle is Vector2 and (middle as Vector2).distance_to(around) > 1.0:
		inward = ((middle as Vector2) - around).normalized()
	var n := 0
	for species_key in home_pokemon():
		if a.has(species_key):
			# In its tank all day, or asleep upstairs at night.
			if is_water_bed(str(list[int(a[species_key])])) or night:
				continue
		if not ResourceLoader.exists(OverworldPokemonData.sheet_path(species_of(str(species_key)))):
			continue
		# No placed spots: a few steps from the player TOWARD the room's middle (they usually
		# stand in a doorway, so "below them" was outside the room).
		var at: Vector2 = around + inward * WANDER_START_STEP + Vector2(-30 + 30 * (n % 3), 18 * int(n / 3) * signf(inward.y + 0.001))
		if n < spots.size() and spots[n] is Node2D:
			at = (spots[n] as Node2D).global_position
		PokemonHomeWanderer.spawn(map_root, str(species_key), at)
		n += 1


## Bedtime: the follower walks onto its bed and lies down (the bedroom's _do_sleep, while the
## lights go out). Nothing happens if it has no bed or no follower is on the map.
static func tuck_in_follower(map_root: Node, walk_time: float) -> void:
	if map_root == null:
		return
	var follower := map_root.get_tree().get_first_node_in_group(PokemonFollower.GROUP) as PokemonFollower
	if follower == null:
		return
	var bed := bed_of(id_of(follower))
	if bed < 0:
		return
	for node in map_root.get_tree().get_nodes_in_group(PokemonBedSpot.GROUP):
		var spot := node as PokemonBedSpot
		if spot.slot != bed:
			continue
		follower.set_physics_process(false)
		var target := spot.seat_global() - Vector2(0, (follower.art_bottom + 1 - follower.cell.y * 0.5) * follower.draw_scale())
		follower.face_vector(target - follower.global_position)
		follower.z_as_relative = false
		follower.z_index = PokemonHomeWanderer.RESTING_Z
		var tween := follower.create_tween()
		tween.tween_property(follower, "global_position", target, walk_time)
		tween.tween_callback(func():
			follower.set_facing("down")
			follower.animating = false)
		return
