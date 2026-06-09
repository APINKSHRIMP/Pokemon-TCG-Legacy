extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"
const BGM_PATH   = "res://Audio/BGM/Player Home (003 File Select PMD Blue Rescue Team OST).ogg"

const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(50, 20)

const STARTER_BOX_CARDS = "base1-47,base1-47,base1-47,base1-47, base1-27,base1-27, base1-52,base1-52,base1-52,base1-52, base1-61,base1-61,base1-61,base1-61, base1-65,base1-65,base1-65,base1-65, base1-67,base1-67,base1-67,base1-67, base1-94,base1-94, base1-90,base1-90"

const NOTE_TEXT = "\"Hi Sweetie, we found these tucked away in a cupboard when we were packing our things up. They must have been your's from when you were just a kid! Oh my - how time flies. Everyone in the harbour seems to play the game too but me and your father never got the hang of it so you might as well keep hold of them to see if you're still any good. Don't forget to catch the train and come visit us at our new place as soon as you can. Love you lots, See you soon x\""

var _box_sparkle: CPUParticles2D = null
var _box_triggered: bool = false
const SLEEP_FADE_DURATION := 3.0
const BED_TOO_EARLY_TEXT := "Nothing wrong with an early night but it's far too early to go to sleep now!"
const BED_SLEEP_PROMPT := "Would you like to go to sleep now?"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return BGM_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS
func get_entry_positions() -> Dictionary:
	return {"Player_House_Downstairs": SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS}

func _scene_setup():
	_apply_moving_in_visibility($UPSTAIRS)
	if GameState.progress.get("player_collected_starter_box", false):
		$Interactables/Starter_Box.visible = false
	else:
		_start_box_sparkle()
		var box_area := $Interactables/Starter_Box/box_area
		box_area.collision_mask = 2
		box_area.monitoring     = true
		box_area.monitorable    = true
		box_area.body_entered.connect(_on_box_body_entered)

	var interactables := $Interactables as Area2D
	interactables.collision_mask = 2
	interactables.monitoring     = true
	interactables.monitorable    = true
	interactables.body_entered.connect(_on_bed_body_entered)

func _start_box_sparkle() -> void:
	_box_sparkle = CPUParticles2D.new()
	add_child(_box_sparkle)

	var box := $Interactables/Starter_Box
	var box_size := Vector2(box.offset_right - box.offset_left, box.offset_bottom - box.offset_top)
	var box_center := Vector2(box.offset_left, box.offset_top) + box_size / 2.0

	_box_sparkle.global_position       = box_center
	_box_sparkle.z_index               = 10
	_box_sparkle.amount                = 30
	_box_sparkle.lifetime              = 1.2
	_box_sparkle.one_shot              = false
	_box_sparkle.explosiveness         = 0.0
	_box_sparkle.emitting              = true
	_box_sparkle.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_box_sparkle.emission_rect_extents = box_size / 2.0
	_box_sparkle.direction             = Vector2(0, 0)
	_box_sparkle.initial_velocity_min  = 0.0
	_box_sparkle.initial_velocity_max  = 0.0
	_box_sparkle.gravity               = Vector2(0, 0)
	_box_sparkle.scale_amount_min      = 0.6
	_box_sparkle.scale_amount_max      = 1.4

	var blue := Color(0.3, 0.55, 1.0)
	var bright := blue.lightened(0.8)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, blue)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(blue.r, blue.g, blue.b, 0.0))
	_box_sparkle.color_ramp = gradient

func _on_box_body_entered(body: Node2D) -> void:
	if _box_triggered:
		return
	if not body.is_in_group("player"):
		return
	if GameState.progress.get("player_collected_starter_box", false):
		return
	_box_triggered = true
	MapManager.show_message_then(
		"Huh? A box of Pokemon Cards have been left here? I definitely didn't bring these with me...... Oh There's a note on top....",
		_on_box_step2
	)

func _on_box_step2() -> void:
	MapManager.show_message_then(NOTE_TEXT, _on_box_step3)

func _on_bed_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if MapManager.message_panel != null and MapManager.message_panel.visible:
		return
	if GameState.get_time() == "Night":
		MapManager.show_interactable_confirm(BED_SLEEP_PROMPT, _do_sleep)
	else:
		MapManager.show_interactable_message(BED_TOO_EARLY_TEXT)

func _do_sleep() -> void:
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()
	var scene_path := get_scene_path()
	GameState.save_menu_return_state(scene_path, _player.position, _player.get_current_direction())
	GameState.advance_time("Day")
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.BLACK, SLEEP_FADE_DURATION)
	tween.tween_callback(func(): SceneCache.change_scene(scene_path))

func _on_box_step3() -> void:
	if _box_sparkle != null:
		_box_sparkle.emitting = false
		_box_sparkle.queue_free()
		_box_sparkle = null
	$Interactables/Starter_Box.visible = false
	GameState.progress["player_collected_starter_box"] = true
	if not GameState.progress.has("packs_unlocked"):
		GameState.progress["packs_unlocked"] = []
	if "base1" not in GameState.progress["packs_unlocked"]:
		GameState.progress["packs_unlocked"].append("base1")
	GameState.save_progress()
	GameState.give_cards(STARTER_BOX_CARDS)
	MapManager._show_message_with_ok("Pokemon Starter Deck Acquired!")
