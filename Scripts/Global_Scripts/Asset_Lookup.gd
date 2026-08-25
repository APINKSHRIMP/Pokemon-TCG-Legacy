class_name AssetLookup
extends RefCounted

## Case-insensitive file lookup for data referenced by name.
##
## Deck names, opponent names and gift values are typed by hand in JSON, so a
## capitalisation slip ("Stoke the flames" vs "Stoke The Flames") silently breaks
## the lookup. NTFS hides that locally -- the game only ships on Windows -- but the
## project is public and a PCK index, ext4 and APFS are all case-sensitive, so the
## same data would fail for anyone running it elsewhere.
##
## Each directory is indexed once and cached for the session.

static var _dir_cache: Dictionary = {}


static func _index(dir_path: String) -> Dictionary:
	if _dir_cache.has(dir_path):
		return _dir_cache[dir_path]
	var index: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for file_name in dir.get_files():
			# Exported builds append .remap / .import to some resources.
			var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
			index[clean.to_lower()] = clean
	else:
		push_warning("AssetLookup: cannot open directory " + dir_path)
	_dir_cache[dir_path] = index
	return index


## Full path to `name + extension` inside `dir_path`, matched without regard to
## case. Returns "" when nothing matches.
static func resolve(dir_path: String, name: String, extension: String = ".json") -> String:
	if name.strip_edges() == "":
		return ""
	var index := _index(dir_path)
	var wanted := (name.strip_edges() + extension).to_lower()
	if index.has(wanted):
		return dir_path.path_join(index[wanted])
	return ""


## Full path to an opponent's deck file, or "" if there is no such deck.
static func deck_path(deck_name: String) -> String:
	return resolve("res://NPC_and_Opponent_Data/Opponent_Deck_Data", deck_name)


## Case-insensitive key lookup in a dictionary loaded from JSON. Returns the key as
## actually spelled in the data, or "" when absent.
static func match_key(source: Dictionary, wanted: String) -> String:
	if source.has(wanted):
		return wanted
	var lowered := wanted.strip_edges().to_lower()
	for key in source:
		if str(key).strip_edges().to_lower() == lowered:
			return key
	return ""


static func invalidate() -> void:
	_dir_cache.clear()
