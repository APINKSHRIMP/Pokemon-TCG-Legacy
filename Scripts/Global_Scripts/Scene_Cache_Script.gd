extends Node

# ============================================================
# SCENE CACHE - Autoload Singleton
#
# Preloads all map PackedScene resources during the splash screen
# so that subsequent scene transitions skip disk I/O. The cached
# PackedScenes live in memory for the lifetime of the game.
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
	"res://Scenes/Map_Scenes/Player_House_Downstairs.tscn",
	"res://Scenes/Map_Scenes/Player_House_Upstairs.tscn",
	# Menu scenes
	"res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Deck_Build_And_Card_View_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Trainer_Card_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Options_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Coin_Case_Scene.tscn",
	"res://Scenes/Main_Menu_Scenes/Pack_Purchase.tscn",
	"res://Scenes/Main_Menu_Scenes/Coin_Shop.tscn",
	"res://Scenes/Main_Menu_Scenes/Holo_Rare_Shop.tscn",
	# Battle scenes
	"res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn",
	"res://Scenes/Main_Match_Gameplay_Scenes/Match_Start_Intro_Scene.tscn",
	"res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn",
]

var _cache: Dictionary = {}            # path -> PackedScene
var _pending: Array = []               # paths still loading
var _started: bool = false


# Kicks off threaded loading of every scene in SCENES_TO_PRELOAD.
# Safe to call multiple times — only starts on the first call.
func preload_all_async() -> void:
	if _started:
		return
	_started = true
	for path in SCENES_TO_PRELOAD:
		if _cache.has(path):
			continue
		var err := ResourceLoader.load_threaded_request(path)
		if err != OK:
			push_warning("SceneCache: failed to start threaded load: " + path)
			continue
		_pending.append(path)


# Returns true when every requested scene has finished loading.
# Polls ResourceLoader and migrates completed loads into _cache.
func is_all_loaded() -> bool:
	_drain_completed()
	return _started and _pending.is_empty()


# Returns 0.0–1.0 progress across all pending loads (averaged).
func get_load_progress() -> float:
	_drain_completed()
	if not _started:
		return 0.0
	var total := SCENES_TO_PRELOAD.size()
	if total == 0:
		return 1.0
	var done := total - _pending.size()
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
