extends Area2D

# ============================================================
# INTERACTABLES — attached to the "Interactables" Area2D node
# ============================================================
# Each CollisionShape2D child of this node is an interaction
# zone. Pressing the interact key (Space) while the player
# stands inside a shape triggers a response based on the
# shape's NAME:
#
#   "Bed"  -> sleep logic (see _interact_bed)
#   "TV"   -> cycling news headlines (see _interact_tv)
#   other  -> flavour text looked up in Interactables_Data.json
#
# To add a plain flavour-text interactable: add a named
# CollisionShape2D under this node in the scene, then add a
# matching entry under the scene's key in Interactables_Data.json.
# ============================================================

const DATA_PATH := "res://Map_Data/Interactables_Data.json"

# Fade-to-black duration when the player sleeps, in seconds.
const SLEEP_FADE_DURATION := 3.0

# Fallback text shown when a non-special shape has no JSON entry.
const MISSING_TEXT := "There's nothing of interest here."

# Text shown when interacting with the bed outside of night time.
const BED_TOO_EARLY_TEXT := "Nothing wrong with an early night but it's far too early to go to sleep now!"

# Prompt shown when interacting with the bed at night.
const BED_SLEEP_PROMPT := "Would you like to go to sleep now?"

# TV news headlines, grouped by progression stage. _tv_stage()
# picks the highest stage whose condition is currently met, and
# each interaction cycles to the next headline in that stage.
const TV_NEWS := {
	1: [
		"Increased tariffs hit imports hard. Local shops have been left unable to import their usual products.",
		"Verdant Forest has been closed to pedestrians due to an intense storm over the previous nights.",
		"Local harbour excited for the arrival of the SS Anne on its annual trip.",
	],
	2: [
		"Head down to your local card mart to buy packs of cards!",
		"Verdant Forest still closed while workers attempt to clear debris.",
		"The weather today is 28° degrees, mostly sun with a few clouds and no chance of rain.",
	],
	3: [
		"Brand new cards available to buy at Celeste Harbour card mart. Head down to pick up some new sets!",
		"SS Anne due to dock at the harbour tomorrow morning, bringing a wave of tourists into town.",
		"Train services still slowed due to the storm, leaving many passengers stranded and unable to purchase tickets due to full trains.",
	],
	4: [
		"SS Anne has officially made for port at Celeste Harbour.",
		"Gym Hero Challenge confirmed to start in less than a week's time.",
		"The weather today has hit record highs for this year at a scorching 31° degrees. Authorities remind you to wear sunscreen outside at all times.",
		"Verdant Forest has nearly been cleared and should be open from tomorrow.",
	],
	5: [
		"Verdant Forest successfully opened to the public.",
		"Verdant Event Hall making preparations for the Gym Hero Challenge.",
		"Police report possible shady behaviour in Verdant Forest, particularly at night time. A reminder to remain vigilant.",
	],
}

var _scene_root: Node = null
var _player: Node2D = null
var _flavour_text: Dictionary = {}

# Index into the current TV stage's headline list; advances each press.
var _tv_index: int = 0


func _ready() -> void:
	_scene_root = get_parent()
	_player = _scene_root.get_node_or_null("Player") as Node2D
	var scene_key := String(_scene_root.scene_file_path).get_file().get_basename()
	_load_flavour_text(scene_key)


# Loads this scene's flavour-text block from Interactables_Data.json.
func _load_flavour_text(scene_key: String) -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Interactables: cannot open " + DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		_flavour_text = data.get(scene_key, {})


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	# A dialog is already open — let the player / MapManager handle it. Also covers
	# the validation popup and an in-flight gift reveal, which own the press too.
	if MapManager.wants_message_input():
		return
	if _player == null or not is_instance_valid(_player) or not _player.can_move:
		return
	var shape_name := _shape_at(_player.global_position)
	if shape_name == "":
		return
	# Consume the press so it can't also trigger an opponent/NPC interaction.
	get_viewport().set_input_as_handled()
	_trigger(shape_name)


# Returns the name of the CollisionShape2D the world point falls inside,
# or "" if the point is not inside any shape.
func _shape_at(world_pos: Vector2) -> String:
	var local := to_local(world_pos)
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var rect_size: Vector2 = child.shape.size
			var rect := Rect2(child.position - rect_size / 2.0, rect_size)
			if rect.has_point(local):
				return child.name
	return ""


func _trigger(shape_name: String) -> void:
	match shape_name:
		"TV":
			_interact_tv()
		_:
			var text: String = _flavour_text.get(shape_name, "")
			if text == "":
				text = MISSING_TEXT
			if shape_name.begins_with("Sign_"):
				MapManager.show_interactable_message("[center]" + text + "[/center]", 38)
			else:
				MapManager.show_interactable_message(text)


# ============================================================
# BED
# ============================================================

func _interact_bed() -> void:
	if GameState.get_time() == "Night":
		MapManager.show_interactable_confirm(BED_SLEEP_PROMPT, Callable(self, "_do_sleep"))
	else:
		MapManager.show_interactable_message(BED_TOO_EARLY_TEXT)


# Fades to black, advances the in-game day, and reloads the scene fresh
# so any night/day specific tiles are rebuilt on wake-up.
func _do_sleep() -> void:
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()

	var scene_path := String(_scene_root.scene_file_path)

	# Remember the player's spot so the reloaded scene restores it.
	GameState.save_menu_return_state(
		scene_path,
		_player.position,
		_player.get_current_direction()
	)

	# Sleep through the night: date +1 and Night -> Morning.
	GameState.advance_time("Morning")

	var tween := create_tween()
	tween.tween_property(_scene_root, "modulate", Color.BLACK, SLEEP_FADE_DURATION)
	tween.tween_callback(func(): SceneCache.change_scene(scene_path))


# ============================================================
# TV
# ============================================================

func _interact_tv() -> void:
	var stage := _tv_stage()
	var headlines: Array = TV_NEWS.get(stage, TV_NEWS[1])
	if headlines.is_empty():
		return
	var headline: String = headlines[_tv_index % headlines.size()]
	_tv_index += 1
	MapManager.show_interactable_message(headline)


# Highest progression stage whose condition is currently met.
func _tv_stage() -> int:
	var date: int = GameState.get_date()
	if date >= 4:
		return 5  # Verdant Forest open
	if date >= 3:
		return 4  # SS Anne arrived
	var packs: Array = GameState.progress.get("packs_unlocked", [])
	if "base2" in packs or "base3" in packs:
		return 3  # new sets in store
	if GameState.progress.get("shop_state", "initial") == "open":
		return 2  # shop ready to sell packs
	return 1
