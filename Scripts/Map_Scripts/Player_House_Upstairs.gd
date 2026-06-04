extends BaseMapScene

const SCENE_PATH = "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

const SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS = Vector2(50, 20)

# PLACEHOLDER: Replace with actual 60 card IDs
const STARTER_BOX_CARDS = "base1-43, base1-43, base1-43, base1-43, base1-47, base1-47, base1-47, base1-47, base1-27, base1-27, base1-52, base1-52, base1-52, base1-52, base1-61, base1-61,base1-61,base1-61,base1-67,base1-67,base1-67,base1-67,base1-88,base1-91,base1-94,base1-94"

var player_near_box: bool = false

func get_scene_path() -> String:      return SCENE_PATH
func get_default_spawn() -> Vector2:  return SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS
func get_entry_positions() -> Dictionary:
	return {"Player_House_Downstairs": SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS}

func _scene_setup():
	_apply_moving_in_visibility($UPSTAIRS)
	if GameState.progress.get("player_collected_starter_box", false):
		$Starter_Box.visible = false

# Block Enter (not Escape) while standing next to the unopened box —
# that key is reserved for the starter-box interaction.
func _allow_menu_open(is_enter: bool) -> bool:
	if is_enter and player_near_box \
			and not GameState.progress.get("player_collected_starter_box", false):
		return false
	return true

func _physics_process(_delta):
	if $Starter_Box.visible and not GameState.progress.get("player_collected_starter_box", false):
		player_near_box = _player.global_position.distance_to($Starter_Box.global_position) < 40.0
	else:
		player_near_box = false

func _process(_delta):
	if player_near_box and not MapManager.message_panel.visible \
			and Input.is_action_just_pressed("ui_accept"):
		$Starter_Box.visible = false
		GameState.progress["player_collected_starter_box"] = true
		GameState.save_progress()
		GameState.give_cards(STARTER_BOX_CARDS)
		MapManager._show_message_with_ok("Pokemon Starter deck acquired!")
