extends Node

# ============================================================
# SCENE CACHE - Autoload Singleton
#
# Preloads all map PackedScene resources during the splash screen
# so that subsequent scene transitions skip disk I/O. The cached
# PackedScenes live in memory for the lifetime of the game.
#
# Also owns the TEXTURE CACHE (card art + menu art, see that section below), the
# pause-menu PREDICTION that fills it, and the FRAME BUDGET every progressive
# grid build uses.
#
# Usage:
#   SceneCache.preload_all_async()      # kick off threaded loading
#   SceneCache.is_all_loaded()          # true when every scene is ready
#   SceneCache.change_scene(path)       # uses cached PackedScene if available,
#                                       # falls back to change_scene_to_file
# ============================================================

# Every scene path that should be preloaded. Add new map / interior
# paths here as they're created.
const SCENES_TO_PRELOAD: Array = [
	# First-boot setup
	"res://Scenes/Intro_And_Animation_Scenes/First_Boot_Setup_Scene.tscn",
	# Map scenes
	"res://Scenes/Map_Scenes/Celeste_Harbour.tscn",
	"res://Scenes/Map_Scenes/Verdant_Forest.tscn",
	"res://Scenes/Map_Scenes/Card_Mart.tscn",
	"res://Scenes/Map_Scenes/Rocket_Mart.tscn",
	"res://Scenes/Map_Scenes/Fish_Shop.tscn",
	"res://Scenes/Map_Scenes/Fish_Shop_Downstairs.tscn",
	"res://Scenes/Map_Scenes/Player_House_Downstairs.tscn",
	"res://Scenes/Map_Scenes/Player_House_Upstairs.tscn",
	"res://Scenes/Map_Scenes/Windmill.tscn",
	"res://Scenes/Map_Scenes/Gym_Plaza.tscn",
	"res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn",
	"res://Scenes/Map_Scenes/Gym_Challenge_Hall.tscn",
	"res://Scenes/Map_Scenes/TownHall.tscn",
	"res://Scenes/Map_Scenes/TrainStation.tscn",
	"res://Scenes/Map_Scenes/Hotel.tscn",
	"res://Scenes/Map_Scenes/Cafe.tscn",
	"res://Scenes/Map_Scenes/DeepOceanFishing.tscn",
	# Menu scenes
	"res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Costume_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Info_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Field_Guide_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Sleeves_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Options_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn",
	"res://Scenes/Main_Menu_Scenes/Coin_Shop.tscn",
	"res://Scenes/Main_Menu_Scenes/Holo_Rare_Shop.tscn",
	"res://Scenes/Main_Menu_Scenes/Bulk_Sell_Shop.tscn",
	"res://Scenes/Main_Menu_Scenes/Cosmetic_Shop.tscn",
	"res://Scenes/Main_Menu_Scenes/Bag_Scene.tscn",
	# Battle scenes
	"res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn",
	"res://Scenes/Main_Match_Gameplay_Scenes/Match_Start_Intro_Scene.tscn",
	"res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn",
	"res://Scenes/Main_Match_Gameplay_Scenes/Best_Of_3_Transition.tscn",
]

var _cache: Dictionary = {}            # path -> PackedScene
var _pending: Array = []               # paths still loading
var _waiting: Array = []               # paths not started yet (ISSUE #403)
var _started: bool = false
var _preload_start_usec: int = 0

## ISSUE #403 / #409: how many scenes load on background threads AT ONCE during the splash.
## It used to be all ~37 together. The maps share TileSets and sheet textures, and Godot's
## threaded loader races when several loads pull in the same sub-resource at the same time:
## sometimes a texture came back EMPTY - "Image width specified (0 pixels)" in the log, then
## the game died with no script error - and sometimes a TileSet lost its atlas texture, which
## is the "whole tilemap missing until restart". Timing-dependent, hence "sometimes" and why
## alt-tabbing (which changes the main thread's pacing) made it worse. One at a time still
## keeps every load off the main thread; later scenes find the shared parts already cached.
## TWEAKABLE, but anything above 1 brings the race back.
const PRELOAD_IN_FLIGHT := 1


# Kicks off threaded loading of every scene in SCENES_TO_PRELOAD.
# Safe to call multiple times — only starts on the first call.
func preload_all_async() -> void:
	if _started:
		return
	_started = true
	# The owned cards' images follow once the scenes are in (see _process), so they
	# never slow the splash down.
	_owned_prewarm_wanted = true
	_preload_start_usec = Time.get_ticks_usec()
	# ISSUE #403: queued, then started PRELOAD_IN_FLIGHT at a time by _start_waiting().
	for path in SCENES_TO_PRELOAD:
		if not _cache.has(path):
			_waiting.append(path)
	_start_waiting()


## ISSUE #403: tops the in-flight threaded loads back up to PRELOAD_IN_FLIGHT.
func _start_waiting() -> void:
	while _pending.size() < PRELOAD_IN_FLIGHT and not _waiting.is_empty():
		var path: String = _waiting.pop_front()
		if _cache.has(path):
			continue
		var err := ResourceLoader.load_threaded_request(path)
		if err != OK:
			push_warning("SceneCache: failed to start threaded load: " + path)
			continue
		_pending.append(path)
	if _started and _pending.is_empty() and _waiting.is_empty() and _preload_start_usec != 0:
		print("ISSUE #403 FIX ACTIVE: ", SCENES_TO_PRELOAD.size(), " scenes preloaded ",
				PRELOAD_IN_FLIGHT, " at a time in ", (Time.get_ticks_usec() - _preload_start_usec) / 1000, " ms")
		_preload_start_usec = 0


# Returns true when every requested scene has finished loading.
# Polls ResourceLoader and migrates completed loads into _cache.
func is_all_loaded() -> bool:
	_drain_completed()
	return _started and _pending.is_empty() and _waiting.is_empty()


# Returns 0.0–1.0 progress across all pending loads (averaged).
func get_load_progress() -> float:
	_drain_completed()
	if not _started:
		return 0.0
	var total := SCENES_TO_PRELOAD.size()
	if total == 0:
		return 1.0
	var done := total - _pending.size() - _waiting.size()
	var partial := 0.0
	for path in _pending:
		var progress: Array = []
		ResourceLoader.load_threaded_get_status(path, progress)
		if progress.size() > 0:
			partial += float(progress[0])
	return (float(done) + partial) / float(total)


# Returns a cached PackedScene, or null if not cached.
func get_packed_scene(path: String) -> PackedScene:
	_drain_completed()
	return _cache.get(path, null)


# Switch to the given scene using a cached PackedScene if available.
# Falls back to change_scene_to_file otherwise so this is always safe.
func change_scene(path: String) -> int:
	_drain_completed()
	var packed: PackedScene = _cache.get(path, null)
	if packed != null:
		return get_tree().change_scene_to_packed(packed)
	# Cache miss — load synchronously now and remember for next time.
	var loaded := load(path)
	if loaded is PackedScene:
		_cache[path] = loaded
		return get_tree().change_scene_to_packed(loaded)
	return get_tree().change_scene_to_file(path)


# Move any completed threaded loads from _pending into _cache.
func _drain_completed() -> void:
	if _pending.is_empty():
		_start_waiting()
		return
	var still_pending: Array = []
	for path in _pending:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(path)
				if res is PackedScene:
					_cache[path] = res
				else:
					push_warning("SceneCache: loaded resource is not a PackedScene: " + path)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("SceneCache: threaded load failed: " + path)
			_:
				still_pending.append(path)
	_pending = still_pending
	_start_waiting()   # ISSUE #403: the next scene starts the moment a slot frees up


# ============================================================
# TEXTURE CACHE (card art + menu art)
#
# A small card image costs ~5.6 ms to load on the main thread (measured), so a
# 160-card set stalled the deck builder for about a second. Loaded on background
# threads they cost under 1 ms each and run in parallel, and a cached one is free.
#
# Pools, each capped and dropping its least recently used entry:
#   "card" - SMALL card images only (~460 KB of video memory each, so all ~3,200
#            would be ~1.4 GB - hence the cap rather than "cache everything").
#            Filled with every OWNED card straight after the splash (unowned cards
#            show as empty slots, so their art is never drawn), and by screens that
#            know what they are about to draw (the deck builder's current set and
#            its two neighbours, both decks at match start).
#   "coin" / "costume" / "sleeve" - each pause-menu screen's own art, one pool per
#            screen so they never evict each other (ISSUE #406). Filled by
#            predict_menu_screens() the moment the pause menu opens, and again on the
#            way back from a sub-menu, so whichever screen is picked is in memory.
#   "menu" - everything else menu-side (the energy-icon large art).
#
# Anything not cached still loads (synchronously) on first use, so a cache miss is
# only ever as slow as the game used to be - never wrong.
# ============================================================

## TWEAKABLE: how many small card images stay in memory (~460 KB VRAM each, so
## 900 is ~400 MB). Lower it if a low-end GPU runs short.
const CARD_CACHE_MAX := 900
## TWEAKABLE: how many other menu images (the energy-icon large art and the deck
## builder's odd extras) stay in memory.
const MENU_CACHE_MAX := 600
## ISSUE #406: coins, costumes and sleeves each have their OWN pool. They used to share
## the 600-slot "menu" pool, but a full collection is 420 coins + 429 costumes + 593
## sleeves, so predicting all three pushed the coins straight back out, and opening one
## screen evicted the next one's art - coins -> sleeves or deck -> costumes reloaded
## everything. Each cap covers its whole catalogue, so no screen can evict another.
## TWEAKABLE: VRAM at a full collection is roughly coins 311 MB, sleeves 293 MB,
## costumes 83 MB. Lower a cap to trade memory for reload time on that one screen.
const COIN_CACHE_MAX := 450
const COSTUME_CACHE_MAX := 450
const SLEEVE_CACHE_MAX := 650

## TWEAKABLE: every progressive grid build (deck builder, coin case, costumes,
## sleeves) adds items until this many ms of the current frame are used, then waits
## a frame. Replaced one-item-per-frame, which made a 160-item grid take ~2.7 s even
## with every image in memory. Lower = smoother while loading, higher = sooner.
const GRID_BUILD_BUDGET_MS := 10

# The current save slot's folder — it moves when the player picks another slot.
var OWNED_CARDS_FOLDER: String:
	get: return GameState.OWNED_CARDS_FOLDER
const CARD_LIBRARY_DIR := "res://Image_Assets/Card_Image_Library/"
const COIN_FOLDER := "res://Image_Assets/Coins/"
const COSTUME_FOLDER := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"
const SLEEVE_SMALL_FOLDER := "res://Image_Assets/Sleeves/small/"

var _pools: Dictionary = {"card": {}, "menu": {}, "coin": {}, "costume": {}, "sleeve": {}}   # pool -> {path -> Texture2D}, oldest-used first
const _POOL_MAX := {"card": CARD_CACHE_MAX, "menu": MENU_CACHE_MAX,
		"coin": COIN_CACHE_MAX, "costume": COSTUME_CACHE_MAX, "sleeve": SLEEVE_CACHE_MAX}
var _tex_pending: Dictionary = {}                              # path -> pool, threaded loads in flight
var _prewarm_queue: Array = []                                 # [path, pool] waiting to be started, oldest first
var _queued: Dictionary = {}                                   # path -> true, mirror of _prewarm_queue

## TWEAKABLE: starting one background load costs ~0.1 ms of the main thread, so a
## big batch (a late-game save's 600 sleeves and coins took 60 ms) is started a few
## at a time: at most this many ms per frame.
const PREWARM_QUEUE_BUDGET_MS := 2
var _owned_prewarm_wanted: bool = false
var _budget_start_usec: int = 0


## The small-image path for a card id ("base1-4"). Every caller builds the path
## this one way so the cache keys always match.
static func small_card_path(card_id: String) -> String:
	var card_set := card_id.split("-")[0]
	return CARD_LIBRARY_DIR + card_set + "/Small/" + AssetLookup.card_image_name(card_id) + ".png"


## A small card image, from memory when it has been loaded before.
func card_texture(path: String) -> Texture2D:
	return cached_texture(path, "card")


func prewarm_card_textures(paths: Array, now: bool = false) -> void:
	prewarm_textures(paths, "card", now)


## The texture at `path`, from `pool` when it has been loaded before. A path still
## loading in the background is waited on (it is already part-way done); anything
## else loads now and is kept. Returns null when the file does not exist.
func cached_texture(path: String, pool: String = "menu") -> Texture2D:
	var store: Dictionary = _pools[pool]
	var tex: Texture2D = store.get(path, null)
	if tex != null:
		# Re-insert so it counts as the most recently used.
		store.erase(path)
		store[path] = tex
		return tex
	if _tex_pending.has(path):
		_tex_pending.erase(path)
		tex = ResourceLoader.load_threaded_get(path) as Texture2D
	elif ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex != null:
		_store_texture(path, tex, pool)
	return tex


## Background-loads every path not already cached or loading, in order; cached_texture()
## picks the results up. Stops at the pool's cap (anything past it would only push out
## what was asked for first).
##   now = true   start every load this instant - for what is about to be drawn (the
##                set the deck builder is opening). ~0.1 ms each on the main thread.
##   now = false  queue them; _process() starts them PREWARM_QUEUE_BUDGET_MS per frame,
##                so a big prediction never hitches a frame.
func prewarm_textures(paths: Array, pool: String = "menu", now: bool = false) -> void:
	var room: int = _POOL_MAX[pool]
	for p in paths:
		if room <= 0:
			break
		var path := String(p)
		if now:
			_request_texture(path, pool)
		elif not _queued.has(path) and not _pools[pool].has(path) and not _tex_pending.has(path):
			_queued[path] = true
			_prewarm_queue.append([path, pool])
		room -= 1


func _request_texture(path: String, pool: String) -> void:
	if _pools[pool].has(path) or _tex_pending.has(path):
		return
	if not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D", true) != OK:
		return
	_tex_pending[path] = pool


## Background-loads the small image of every card the player owns at least one of.
func prewarm_owned_cards() -> void:
	var paths: Array = []
	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return
	for fname in dir.get_files():
		if fname.ends_with("_player_owned_cards.json"):
			paths.append_array(_owned_card_paths_in_file(OWNED_CARDS_FOLDER + fname))
	print("CARD CACHE: prewarming ", mini(paths.size(), CARD_CACHE_MAX), " owned card images")
	prewarm_card_textures(paths)


## Small-image paths of every card owned at least once in one owned-cards file.
func _owned_card_paths_in_file(path: String) -> Array:
	var out: Array = []
	var data = _read_json(path)
	if not data is Dictionary:
		return out
	for entry in data.get("owned_cards", []):
		if entry is Dictionary and int(entry.get("owned", 0)) > 0:
			out.append(small_card_path(String(entry.get("card_id", ""))))
	return out


func _store_texture(path: String, tex: Texture2D, pool: String) -> void:
	var store: Dictionary = _pools[pool]
	store[path] = tex
	var cap: int = _POOL_MAX[pool]
	if store.size() <= cap:
		return
	# Over the cap: drop the least recently used. Anything still on screen keeps its
	# texture alive through its own node, so dropping it here frees nothing early.
	for old_path in store.keys().slice(0, store.size() - cap):
		store.erase(old_path)


# ============================================================
# MENU PREDICTION
#
# Called the moment the pause menu opens. While the player is still looking at the
# six tiles, the art of all four heavy screens loads in the background, most likely
# first: the deck builder (the set it reopens on, the current deck for the viewer,
# the energy icons), then owned coins, owned costumes and owned sleeves - exactly
# the items each screen draws by default (unowned ones are empty slots). Re-calling
# it is cheap: anything already cached or loading is skipped.
# ============================================================

func predict_menu_screens() -> void:
	var t := Time.get_ticks_usec()
	var current = _read_json(GameState.PLAYER_CURRENT_DATA_PATH)
	if not current is Dictionary:
		current = {}

	# 1. Deck builder: the set it opens on, then the deck being edited, then the
	# six energy icons (large art) and the energy-style picker.
	var last_set := String(current.get("last_set_loaded", "base1"))
	prewarm_card_textures(_owned_card_paths_in_file(OWNED_CARDS_FOLDER + last_set + "_player_owned_cards.json"))
	var deck_name := String(current.get("deck", ""))
	if deck_name != "":
		var deck = _read_json(GameState.PLAYER_DECKS_FOLDER + deck_name + ".json")
		if deck is Array:
			var deck_paths: Array = []
			for entry in deck:
				if entry is Dictionary and entry.has("id"):
					deck_paths.append(small_card_path(String(entry["id"])))
			prewarm_card_textures(deck_paths)
	var style := String(current.get("energy_style", "Base1"))
	if GameState.ENERGY_STYLES.has(style):
		var icon_paths: Array = []
		for card_id in GameState.ENERGY_STYLES[style]:
			icon_paths.append(small_card_path(String(card_id)).replace("/Small/", "/Large/"))
		prewarm_textures(icon_paths)

	# 2-4. Owned coins, costumes and sleeves - each screen's default view.
	var coin_paths: Array = []
	for coin in GameState.progress.get("coins", []):
		coin_paths.append(COIN_FOLDER + String(coin))
	# ISSUE #406: one pool each, so predicting (or opening) one never evicts another.
	prewarm_textures(coin_paths, "coin")
	prewarm_textures(_owned_files_in(COSTUME_FOLDER, GameState.progress.get("costumes", []), false), "costume")
	prewarm_textures(_owned_files_in(SLEEVE_SMALL_FOLDER, GameState.progress.get("sleeves", []), true), "sleeve")
	print("ISSUE #406 FIX ACTIVE: menu art pools held - coin ", _pools["coin"].size(), ", costume ",
			_pools["costume"].size(), ", sleeve ", _pools["sleeve"].size(), ", queued ", _prewarm_queue.size())
	# Only when something new was queued: printing is slow enough on Windows to be
	# the costliest part of a repeat call.
	if not _prewarm_queue.is_empty():
		print("MENU CACHE: predicted pause-menu screens, ", _prewarm_queue.size(),
				" images queued to load in the background (in ", (Time.get_ticks_usec() - t) / 1000, " ms)")


## Paths in `folder` whose file is in `owned`. Costumes are saved lower-cased while
## the files are mixed-case, and sleeves are saved without their extension, so the
## match is case-insensitive and optionally extension-free.
func _owned_files_in(folder: String, owned: Array, match_basename: bool) -> Array:
	var wanted: Dictionary = {}
	for item in owned:
		wanted[String(item).to_lower()] = true
	var out: Array = []
	for fname in _folder_files(folder):
		var key := (fname.get_basename() if match_basename else fname).to_lower()
		if wanted.has(key):
			out.append(folder + fname)
	return out


## The image files in a folder, listed once per session (the folders never change
## while the game runs). DirAccess, not ResourceLoader.list_directory: measured 1 ms
## against 30-40 ms for the 593-file sleeve folder, which hitched the pause menu.
## An exported build lists ".import"/".remap" stubs, so those are trimmed and folded
## into one entry, as the splash's card pool does.
var _folder_listing: Dictionary = {}   # folder -> PackedStringArray

func _folder_files(folder: String) -> PackedStringArray:
	if _folder_listing.has(folder):
		return _folder_listing[folder]
	var found: Dictionary = {}
	for fname in DirAccess.get_files_at(folder):
		var clean := fname.trim_suffix(".import").trim_suffix(".remap")
		if clean.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			found[clean] = true
	var files := PackedStringArray(found.keys())
	_folder_listing[folder] = files
	return files


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data


# ============================================================
# FRAME BUDGET for progressive grid builds
#
#   SceneCache.start_build_budget()
#   for item in items:
#       if not is_inside_tree(): return      # caller's own abort checks
#       _add_item(item)
#       await SceneCache.yield_if_over_budget()
# ============================================================

func start_build_budget() -> void:
	_budget_start_usec = Time.get_ticks_usec()


## Waits for the next frame only once this frame's GRID_BUILD_BUDGET_MS is spent.
func yield_if_over_budget() -> void:
	if Time.get_ticks_usec() - _budget_start_usec < GRID_BUILD_BUDGET_MS * 1000:
		return
	await get_tree().process_frame
	_budget_start_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if _owned_prewarm_wanted and is_all_loaded():
		_owned_prewarm_wanted = false
		prewarm_owned_cards()
	# Start queued background loads, a few per frame.
	if not _prewarm_queue.is_empty():
		var start := Time.get_ticks_usec()
		var taken := 0
		while taken < _prewarm_queue.size() and Time.get_ticks_usec() - start < PREWARM_QUEUE_BUDGET_MS * 1000:
			var item: Array = _prewarm_queue[taken]
			taken += 1
			_queued.erase(item[0])
			_request_texture(item[0], item[1])
		_prewarm_queue = _prewarm_queue.slice(taken)
	if _tex_pending.is_empty():
		return
	# Move finished background loads into their pools.
	for path in _tex_pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var pool: String = _tex_pending[path]
		_tex_pending.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var tex := ResourceLoader.load_threaded_get(path) as Texture2D
			if tex != null and not _pools[pool].has(path):
				_store_texture(path, tex, pool)
