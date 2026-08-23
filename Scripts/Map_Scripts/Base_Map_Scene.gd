class_name BaseMapScene
extends Node2D

# ============================================================
# BASE MAP SCENE
# ============================================================
# Shared lifecycle for all overworld area scripts. Subclasses
# override the virtual getters below and optionally the hooks.
#
# Universal behaviour handled here:
#   - Fade in / fade out
#   - Door area setup (collision, signal connection)
#   - Spawn position resolution (menu return → shop return →
#     battle return → entering_from lookup → default fallback)
#   - Save current location to GameState
#   - MapManager.initialise() call
#   - _input() main-menu exit shortcut
#   - _on_door_entered() fade-black scene transition
#   - Moving-in visibility helper
#   - Tileset recursive helper
# ============================================================

@onready var _player: CharacterBody2D = $Player
@onready var _ui_layer: CanvasLayer = $UILAYER

# ============================================================
# VIRTUAL INTERFACE — subclasses must / should override
# ============================================================

# Return the full res:// path of this scene's .tscn file.
func get_scene_path() -> String:
	push_error("BaseMapScene: get_scene_path() not overridden in " + name)
	return ""

# Map of entering_from keys → spawn Vector2 for each door.
func get_entry_positions() -> Dictionary:
	return {}

# Fallback spawn when no entering_from key matches. Default: first
# entry position, or Vector2.ZERO if no entries are defined.
func get_default_spawn() -> Vector2:
	var positions := get_entry_positions()
	if not positions.is_empty():
		return positions.values()[0]
	return Vector2.ZERO

# BGM .ogg path for this scene. Return "" to skip BGM play.
func get_bgm_path() -> String:
	return ""

# Opponent JSON path (first argument to MapManager.initialise).
func get_opponent_json_path() -> String:
	return ""

# NPC JSON path (seventh argument to MapManager.initialise).
func get_npc_json_path() -> String:
	return ""

# Called after spawn resolution and before MapManager.initialise.
# Override for time-of-day tiles, date events, cash label, starter
# set visibility, or any other scene-specific setup.
func _scene_setup() -> void:
	pass

# Return false to block menu opening for a given key type.
# Enter (is_enter=true) and Escape (is_enter=false) are passed separately
# so scenes can block only Enter (e.g. near a starter box).
func _allow_menu_open(_is_enter: bool) -> bool:
	return true

# Called with the target scene path after finding the nearest door shape.
# Return false to cancel the transition (e.g. downstairs starter-box gate).
# Side-effects (showing a message) are acceptable.
func _on_before_door_transition(_body: Node2D, _target: String) -> bool:
	return true

# ============================================================
# LIFECYCLE
# ============================================================

func _ready():
	var bgm := get_bgm_path()
	if bgm != "":
		SoundManagerScript.play_bgm(bgm, true)

	var is_sleep_wakeup := GameState.sleep_wakeup_fade
	GameState.sleep_wakeup_fade = false

	# For sleep: add a black overlay to the UI layer immediately so the scene is
	# covered on the first rendered frame, then fade it out after setup completes.
	# For all other transitions: snap root to transparent so it fades in normally.
	var _sleep_overlay: ColorRect = null
	if is_sleep_wakeup:
		_sleep_overlay = ColorRect.new()
		_sleep_overlay.color = Color.BLACK
		_sleep_overlay.size = get_viewport().get_visible_rect().size
		_sleep_overlay.position = Vector2.ZERO
		_ui_layer.add_child(_sleep_overlay)
	else:
		get_tree().root.set("modulate", Color(1, 1, 1, 0))

	_setup_doors()
	_scene_setup()

	var scene_path := get_scene_path()
	var entry_positions := get_entry_positions()

	# ISSUE #96 FIX: every branch below is fed by a ONE-SHOT flag, but each used to clear only its own
	# flag — so whenever a higher-priority branch won, the loser's flag survived into the next map load
	# and hijacked that spawn instead ("spawns are whack all over"). The worst offender was
	# entering_from: a door key with no matching entry in the destination fell through to the default
	# spawn and left the key set, so the NEXT map that happened to define that key teleported the
	# player to it. Resolve first, then consume ALL of them unconditionally.
	var resolved_spawn: Vector2
	var resolved_dir: String = GameState.get_player_direction()
	var spawn_source: String
	if GameState.has_menu_return_state and GameState.menu_return_scene_path == scene_path:
		resolved_spawn = GameState.menu_return_position
		resolved_dir   = GameState.menu_return_direction
		spawn_source   = "menu_return"
	elif GameState.use_spawn_position:
		resolved_spawn = GameState.spawn_position
		spawn_source   = "shop_return"
	elif GameState.returning_from_battle:
		resolved_spawn = GameState.player_position
		spawn_source   = "battle_return"
	elif entry_positions.has(GameState.entering_from):
		resolved_spawn = entry_positions[GameState.entering_from]
		spawn_source   = "door:" + GameState.entering_from
	else:
		resolved_spawn = get_default_spawn()
		spawn_source   = "default"

	_player.position = resolved_spawn
	_player.set_direction(resolved_dir)

	# Menu-return state is only ever consumed by the scene it names, so clear it only on a match —
	# a different map must not eat a pending return into another one.
	if GameState.menu_return_scene_path == scene_path:
		GameState.clear_menu_return_state()
	GameState.use_spawn_position = false
	GameState.entering_from      = ""
	# returning_from_battle is deliberately NOT cleared here: MapManager.initialise() below still needs
	# it to respawn the opponent that was just fought, to resolve opponent_defeated spawn conditions,
	# and to show the post-battle dialogue. It clears the flag itself in _handle_battle_return().
	# (The old code cleared it in the battle branch — i.e. BEFORE initialise — so whenever that branch
	# actually won, all three of those behaviours silently no-op'd.)
	print("ISSUE #96 FIX ACTIVE: spawned in ", scene_path.get_file(), " at ", resolved_spawn, " via ", spawn_source)

	GameState.save_current_location(scene_path, _player.position)

	MapManager.initialise(
		_player,
		_get_opponents_container(),
		_ui_layer,
		get_opponent_json_path(),
		[],
		scene_path,
		get_npc_json_path(),
		[]
	)

	await get_tree().process_frame
	if _sleep_overlay != null:
		var tween := create_tween()
		tween.tween_property(_sleep_overlay, "modulate:a", 0.0, 1.5)
		tween.tween_callback(_sleep_overlay.queue_free)
	else:
		var tween := create_tween()
		tween.tween_property(get_tree().root, "modulate", Color.WHITE, 1.0)

	# ISSUE #52 FIX: reopen the main-menu overlay on top of the freshly-reloaded map when returning
	# from a sub-menu, so the transparent menu shows the world map behind it instead of black.
	if GameState.reopen_menu_overlay:
		GameState.reopen_menu_overlay = false
		_open_menu_overlay()

func _exit_tree():
	# ISSUE #56: snapshot NPC/opponent positions before this map unloads (battle, sub-menu, door) so
	# they resume from where they were instead of teleporting back to their data-file spawn on reload.
	MapManager.capture_actor_positions()
	# ISSUE #52: never leave a freed map registered as the menu overlay host.
	if GameState.menu_overlay_host == self:
		GameState.menu_overlay_host = null

# ============================================================
# DOORS
# ============================================================

func _setup_doors():
	var door_areas := $"Door Areas"
	door_areas.collision_layer = 3
	door_areas.collision_mask  = 2
	door_areas.monitoring      = true
	door_areas.monitorable     = true
	door_areas.body_entered.connect(_on_door_entered)

# ISSUE #93: the OPPONENTS/NPCS container is the parent every NPC and opponent is spawned into, so
# their data-file positions are relative to it. This used to look only at the scene root, which meant
# dragging the container under another node in the editor silently fell through to the runtime
# fallback below — a fresh container at (0,0) — and every actor in that map spawned offset by the
# container's position (this is exactly how the Card Mart shopkeeper ended up off in the corner
# instead of behind his counter). The lookup is now recursive and warns when it finds the container
# somewhere other than the root, so the next accidental reparent is visible instead of silent.
func _get_opponents_container() -> Node2D:
	for container_name in ["OPPONENTS", "NPCS"]:
		if has_node(container_name):
			return get_node(container_name) as Node2D
		var nested := find_child(container_name, true, false)
		if nested is Node2D:
			push_warning("BaseMapScene: '%s' container in %s is not a direct child of the scene root "
				% [container_name, name] + "(found at '%s') — actor positions are relative to it, so "
				% get_path_to(nested) + "check the shop/NPC placements in that scene.")
			return nested as Node2D
	# Interior scenes (Gym Reception/Hall) have no container in the .tscn — create at runtime
	var c := Node2D.new()
	c.name = "OPPONENTS"
	c.z_index = 1
	add_child(c)
	return c

func _on_door_entered(body: Node2D):
	if not body.is_in_group("player"):
		return

	var door_area := $"Door Areas"
	var nearest_shape: CollisionShape2D = null
	var nearest_dist := INF
	for child in door_area.get_children():
		if child is CollisionShape2D:
			var dist: float = child.global_position.distance_to(body.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_shape = child

	if nearest_shape == null:
		return

	var target: String = nearest_shape.get_meta("target_scene")

	if not _on_before_door_transition(body, target):
		return

	GameState.save_player_direction(body.get_current_direction())
	body.lock_movement()
	GameState.entering_from = get_scene_path().get_file().get_basename()

	var tween := create_tween()
	tween.tween_property(get_tree().current_scene, "modulate", Color.BLACK, 0.5)
	tween.tween_callback(func():
		SceneCache.change_scene(target)
	)

# ============================================================
# INPUT — main menu shortcut
# ============================================================

var _menu_canvas_layer: CanvasLayer = null
var _menu_instance: Node = null

func _input(event: InputEvent) -> void:
	# A dialog on screen owns Escape: it answers NO on a Yes/No question and
	# dismisses a plain message, rather than opening the main menu behind it.
	# Space/Enter reach the same box through the player's ui_accept path, which
	# runs later (_unhandled_input) — they only have to be kept out of the menu
	# shortcut below. Handled here rather than in the player script because the
	# menu shortcut lives here and would otherwise win the press.
	if UIInput.is_cancel(event) and MapManager.wants_message_input():
		get_viewport().set_input_as_handled()
		MapManager.handle_message_cancel()
		return

	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	var is_escape: bool = event.keycode == KEY_ESCAPE
	if not (is_enter or is_escape):
		return
	if is_enter and MapManager.wants_message_input():
		return
	if not _allow_menu_open(is_enter):
		return
	if _menu_canvas_layer != null:
		return
	get_viewport().set_input_as_handled()
	_open_menu_overlay()

func _open_menu_overlay() -> void:
	var scene_path := get_scene_path()
	GameState.save_menu_return_state(scene_path, _player.position, _player.get_current_direction())
	GameState.save_current_location(scene_path, _player.position)
	SoundManagerScript.stop_bgm()
	_player.lock_movement()

	_menu_canvas_layer = CanvasLayer.new()
	_menu_canvas_layer.layer = 10
	add_child(_menu_canvas_layer)

	var menu_packed: PackedScene = SceneCache.get_packed_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
	if menu_packed == null:
		menu_packed = load("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
	var menu_instance: Node = menu_packed.instantiate()
	menu_instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_instance.is_overlay = true
	menu_instance.close_overlay_callback = _close_menu_overlay
	_menu_canvas_layer.add_child(menu_instance)
	_menu_instance = menu_instance

	# ISSUE #52 FIX (retest): register as the overlay host so the main menu can open sub-menus as
	# further overlays on top of this still-loaded map, instead of swapping the whole scene out.
	GameState.menu_overlay_host = self

func _close_menu_overlay() -> void:
	close_submenu_overlay(false)
	if _menu_canvas_layer != null and is_instance_valid(_menu_canvas_layer):
		_menu_canvas_layer.queue_free()
		_menu_canvas_layer = null
	_menu_instance = null
	if GameState.menu_overlay_host == self:
		GameState.menu_overlay_host = null
	# ISSUE #96 FIX: _open_menu_overlay() saves a menu-return position so a full scene change back into
	# this map lands the player where they opened the menu. Since ISSUE #52 the overlay closes WITHOUT
	# a scene change, so nothing ever consumed that state — it sat in GameState forever and won the
	# spawn-resolution race in _ready() (it is checked first). Every later load of this same scene —
	# returning from a battle, walking back in through a door — then teleported the player to that stale
	# spot instead of the spot in front of the trainer / the doorway. The state has served its purpose
	# the moment the overlay closes in place, so drop it here.
	if GameState.has_menu_return_state and GameState.menu_return_scene_path == get_scene_path():
		print("ISSUE #96 FIX ACTIVE: cleared stale menu-return state on overlay close for ", get_scene_path())
		GameState.clear_menu_return_state()
	_player.unlock_movement()
	var bgm := get_bgm_path()
	if bgm != "":
		SoundManagerScript.play_bgm(bgm, false)

# ============================================================
# SUB-MENU OVERLAYS (ISSUE #52)
# ============================================================
# The map scene used to be unloaded whenever a sub-menu (deck/costume/coin/sleeves/options/info) was
# opened, so coming back to the main menu meant reloading the whole world from scratch — a long black
# screen. The only thing a sub-menu can actually change about the overworld is the player's sprite,
# so the map now stays loaded underneath: sub-menus are pushed as another CanvasLayer over it and the
# main menu layer is merely hidden. Closing a sub-menu is then instant, and the player sprite is
# refreshed in case the Costume menu changed it.

var _submenu_canvas_layer: CanvasLayer = null

func open_submenu_overlay(scene_path: String) -> void:
	if scene_path == "":
		return
	close_submenu_overlay(false)
	if _menu_canvas_layer != null and is_instance_valid(_menu_canvas_layer):
		_menu_canvas_layer.visible = false   # keep the main menu loaded, just out of sight
	# The hidden main menu must also stop listening for Escape/Enter, or its handler would close the
	# whole menu at the same time as the sub-menu's own back handler.
	if _menu_instance != null and is_instance_valid(_menu_instance):
		_menu_instance.set_process_input(false)
		# ISSUE #128: and it must stop PLAYING, or its theme runs under the sub-menu's own track.
		if _menu_instance.has_method("pause_music"):
			_menu_instance.pause_music()

	_submenu_canvas_layer = CanvasLayer.new()
	_submenu_canvas_layer.layer = 11
	add_child(_submenu_canvas_layer)

	var packed: PackedScene = SceneCache.get_packed_scene(scene_path)
	if packed == null:
		packed = load(scene_path)
	if packed == null:
		push_error("BaseMapScene: could not load sub-menu scene " + scene_path)
		close_submenu_overlay(true)
		return
	var instance: Node = packed.instantiate()
	if instance is Control:
		instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_submenu_canvas_layer.add_child(instance)

# restore_menu: true when returning to the main menu (the normal "back" path), false when the whole
# menu stack is being torn down.
func close_submenu_overlay(restore_menu: bool = true) -> void:
	if _submenu_canvas_layer != null and is_instance_valid(_submenu_canvas_layer):
		_submenu_canvas_layer.queue_free()
	_submenu_canvas_layer = null
	if not restore_menu:
		return
	if _menu_canvas_layer != null and is_instance_valid(_menu_canvas_layer):
		_menu_canvas_layer.visible = true
	if _menu_instance != null and is_instance_valid(_menu_instance):
		_menu_instance.set_process_input(true)
		if _menu_instance.has_method("resume_music"):   # ISSUE #128
			_menu_instance.resume_music()
	# The Costume sub-menu can change the player's sprite; push it onto the live player node since
	# the map is no longer reloaded.
	if _player != null and is_instance_valid(_player) and _player.has_method("refresh_sprite"):
		_player.refresh_sprite()

# ============================================================
# MOVING-IN VISIBILITY — opt-in
# Hides tiles named exclude_name once moving-in is complete.
# ============================================================

func _apply_moving_in_visibility(layer_parent: Node, exclude_name: String = "Moving In"):
	if not GameState.progress.get("moving_in_completed", false):
		return
	for layer in layer_parent.get_children():
		if layer is TileMapLayer:
			layer.visible = layer.name != exclude_name

# ============================================================
# TILESET HELPER — used by scenes with time-of-day tilesets
# ============================================================

func _apply_tileset(node: Node, tileset: TileSet) -> void:
	if node is TileMapLayer:
		node.tile_set = tileset
	for child in node.get_children():
		_apply_tileset(child, tileset)
