class_name PokemonPrefs
extends RefCounted

## WHAT EACH POKÉMON LIKES (2026-11-24): one food and one bed per Pokémon, read from
## NPC_and_Opponent_Data/Pokemon/Pokemon_Food_And_Beds.csv (the user fills it in; Excel is fine).
## Many Pokémon can share a food or a bed -- Rattata and Pikachu both like Rat Cheese, but
## Rattata sleeps on a Hay Bale and Pikachu on the Glowing Crystal Rock.
##
## Columns used (found by header name, any order): "Pokemon" (display name, so every variant
## sheet -- 019_Rattata, 019_Rattata_Alolan -- shares the row), "Food", "Bed". Other columns
## are notes for the user. Names are matched ignoring case, and a bed may be written as its
## name ("Hay Bale") or its sprite file name ("Haybale", "Lily_Pad_Big").
##   * Food blank -> no food attracts it (only the debug SUPER FOOD).
##   * Bed blank, or a name Pokemon_Beds.json does not have -> Pokemon_Beds.json's default_bed.
## The CSV has a "keep" .import next to it so Godot ships it as-is instead of importing it
## as a translation table.

const CSV_PATH := "res://NPC_and_Opponent_Data/Pokemon/Pokemon_Food_And_Beds.csv"

static var _rows: Dictionary = {}   ## lower-case display name -> {"food": String, "bed": String}
static var _loaded: bool = false
static var _bad_beds_reported: Dictionary = {}


static func rows() -> Dictionary:
	if not _loaded:
		_loaded = true
		_rows = _parse()
	return _rows


static func reload() -> void:
	_loaded = false
	_bad_beds_reported.clear()


static func _parse() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(CSV_PATH):
		push_error("PokemonPrefs: no %s" % CSV_PATH)
		return out
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	var cols := {}
	for i in header.size():
		cols[header[i].replace("﻿", "").strip_edges().to_lower()] = i
	var name_col: int = cols.get("pokemon", -1)
	var food_col: int = cols.get("food", -1)
	var bed_col: int = cols.get("bed", -1)
	if name_col < 0:
		push_error("PokemonPrefs: %s has no 'Pokemon' column" % CSV_PATH)
		return out
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() <= name_col:
			continue
		var pokemon := line[name_col].strip_edges()
		if pokemon == "":
			continue
		out[pokemon.to_lower()] = {
			"food": line[food_col].strip_edges() if food_col >= 0 and line.size() > food_col else "",
			"bed": line[bed_col].strip_edges() if bed_col >= 0 and line.size() > bed_col else "",
		}
	return out


static func _row(species_key: String) -> Dictionary:
	return rows().get(OverworldPokemonData.display_name(species_key).to_lower(), {})


## The one food this species likes, "" for none.
static func food_of(species_key: String) -> String:
	return str(_row(species_key).get("food", ""))


## The KIND of bed this species sleeps in: a key of Pokemon_Beds.json "beds", never "".
static func bed_of(species_key: String) -> String:
	var written := str(_row(species_key).get("bed", ""))
	if written != "":
		var bed := PokemonHome.canonical_bed(written)
		if bed != "":
			return bed
		if not _bad_beds_reported.has(written):
			_bad_beds_reported[written] = true
			push_warning("PokemonPrefs: bed '%s' (CSV) is not in Pokemon_Beds.json, using the default" % written)
	return PokemonHome.default_bed()


## Every food any Pokémon in the CSV likes, in first-seen order.
static func food_names() -> Array:
	var out: Array = []
	for row in rows().values():
		var food := str(row.get("food", ""))
		if food != "" and food not in out:
			out.append(food)
	return out
