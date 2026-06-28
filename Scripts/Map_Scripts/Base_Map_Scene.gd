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
#   - Cash label (opt-in: call _create_cash_label / _update_cash_label)
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

	if GameState.has_menu_return_state and GameState.menu_return_scene_path == scene_path:
		_player.position = GameState.menu_return_position
		_player.set_direction(GameState.menu_return_direction)
		GameState.clear_menu_return_state()
	elif GameState.use_spawn_position:
		_player.position = GameState.spawn_position
		_player.set_direction(GameState.get_player_direction())
		GameState.use_spawn_position = false
	elif GameState.returning_from_battle:
		_player.position = GameState.player_position
		_player.set_direction(GameState.get_player_direction())
		GameState.returning_from_battle = false
	elif entry_positions.has(GameState.entering_from):
		_player.position = entry_positions[GameState.entering_from]
		_player.set_direction(GameState.get_player_direction())
		GameState.entering_from = ""
	else:
		_player.position = get_default_spawn()
		_player.set_direction(GameState.get_player_direction())

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

func _exit_tree():
	_remove_cash_label()

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

func _get_opponents_container() -> Node2D:
	if has_node("OPPONENTS"):
		return get_node("OPPONENTS") as Node2D
	if has_node("NPCS"):
		return get_node("NPCS") as Node2D
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

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	var is_enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	var is_escape: bool = event.keycode == KEY_ESCAPE
	if not (is_enter or is_escape):
		return
	if is_enter and MapManager.message_panel != null and MapManager.message_panel.visible:
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

func _close_menu_overlay() -> void:
	if _menu_canvas_layer != null and is_instance_valid(_menu_canvas_layer):
		_menu_canvas_layer.queue_free()
		_menu_canvas_layer = null
	_player.unlock_movement()
	var bgm := get_bgm_path()
	if bgm != "":
		SoundManagerScript.play_bgm(bgm, false)

# ============================================================
# CASH LABEL — opt-in
# ============================================================

var _cash_label: Label = null

func _create_cash_label():
	_cash_label = Label.new()
	_cash_label.name = "CashLabel"
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cash_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_cash_label.add_theme_font_size_override("font_size", 18)
	_cash_label.add_theme_color_override("font_color", Color.WHITE)
	_cash_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cash_label.add_theme_constant_override("shadow_offset_x", 1)
	_cash_label.add_theme_constant_override("shadow_offset_y", 1)
	_cash_label.anchor_left   = 1.0
	_cash_label.anchor_top    = 1.0
	_cash_label.anchor_right  = 1.0
	_cash_label.anchor_bottom = 1.0
	_cash_label.offset_left   = -160
	_cash_label.offset_top    = -40
	_cash_label.offset_right  = -10
	_cash_label.offset_bottom = -10
	_ui_layer.add_child(_cash_label)

func _update_cash_label():
	if _cash_label == null:
		return
	_cash_label.text = "Cash: $" + str(GameState.get_cash())

func _remove_cash_label():
	if _cash_label != null and is_instance_valid(_cash_label):
		_cash_label.queue_free()
		_cash_label = null

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
