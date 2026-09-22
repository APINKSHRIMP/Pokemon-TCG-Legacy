class_name FishingZone
extends Area2D

## ============================================================
## FISHING AREAS -- attached to a "FishingAreas" Area2D node
## ============================================================
## Each RectangleShape2D CollisionShape2D child of this node is a place the player can
## cast FROM. The shape's NAME carries the direction the WATER lies in:
##
##   Fish_Down      water is below the player -- they end up facing down
##   Fish_Left_2    water is to the left; the _2 only keeps the node name unique
##
## Pressing Space/Enter while standing inside one starts the cast.
##
## That is ALL these rectangles do. The water the hooked fish then fights in, and the
## table of what bites there, belong to a `fishing_spot` spawn point -- placed and drawn
## in the placement tool, picked per cast by whichever one is nearest (FishingData).
## So a map with two fishing spots needs no scene change here beyond a rect to stand on.
##
## Shaped after Interactables_Script.gd, which does the same named-shape lookup for
## signs and the bed. Do NOT overlap a fishing rect with an interactable rect on the same
## map: both listen on _unhandled_input and the winner is decided by tree order.
## ============================================================

const NAME_PREFIX := "Fish_"

## ---- SEA AMBIENCE ----------------------------------------------------------
## A looping sea bed that fades up whenever the player is stood in a fishing spot and
## slowly away again when they walk off it. Its own AudioStreamPlayer on the Music bus,
## so the player's music slider still covers it, and its own fade -- it is NOT the BGM,
## which the fishing minigame silences for the duration of a cast.
##
## While a cast is running the minigame takes the level over with set_ambience() (the sea
## comes UP to full as the music goes down) and hands it back with clear_ambience().
const AMBIENCE_PATH := "res://Audio/BGM/Sea2.ogg"
const AMBIENCE_IDLE := 0.5        ## stood in a fishing spot, not fishing
const AMBIENCE_FADE_IN := 1.5
const AMBIENCE_FADE_OUT := 3.0    ## walking away: "lower the ocean sound slowly"
const AMBIENCE_SILENT_DB := -60.0
const AMBIENCE_PAUSE_FADE := 0.4   ## fading the sea out under the main menu, and back in

## Left over from when the water was a shape in the scene too. It is a `fishing_spot`
## spawn point now, but a map whose old shape has not been deleted would otherwise be
## read as a cast rect with a nonsense direction, so it is still skipped.
const BOUNDS_NAME := "Fishing_Zone"

var _player: Node2D = null

var _ambience: AudioStreamPlayer = null
var _ambience_level: float = 0.0
var _ambience_target: float = 0.0
var _ambience_rate: float = 0.0
## >= 0 while the minigame is driving the level itself; -1 means "follow the player".
var _ambience_override: float = -1.0
## True while the main menu is up: the sea fades away and comes back when it closes. The
## zone keeps processing while the rest of the map is frozen so that fade can run.
var _ambience_paused: bool = false


func _ready() -> void:
	# Purely a lookup table of rectangles -- it never needs to detect anything itself.
	monitoring = false
	monitorable = false
	_player = get_parent().get_node_or_null("Player") as Node2D


# ============================================================
# SEA AMBIENCE
# ============================================================

## Hands the level to the caller (the fishing minigame) until clear_ambience().
func set_ambience(level: float, seconds: float) -> void:
	_ambience_override = clampf(level, 0.0, 1.0)
	_fade_ambience(_ambience_override, seconds)


## Gives the level back to "wherever the player is standing".
func clear_ambience() -> void:
	_ambience_override = -1.0


## Called by MapManager.set_overworld_paused(). The override is left alone, so a cast that
## was paused mid-way gets its own level back rather than the standing-still one.
func set_ambience_paused(paused: bool) -> void:
	_ambience_paused = paused


func _fade_ambience(target: float, seconds: float) -> void:
	_ambience_target = clampf(target, 0.0, 1.0)
	_ambience_rate = 1.0 / maxf(0.01, seconds)
	if _ambience_target > 0.0:
		_ensure_ambience()


func _ensure_ambience() -> void:
	if _ambience != null and is_instance_valid(_ambience):
		return
	if not ResourceLoader.exists(AMBIENCE_PATH):
		return
	var stream: AudioStream = load(AMBIENCE_PATH)
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = stream
	_ambience.bus = SoundManagerScript.MUSIC_BUS
	_ambience.volume_db = AMBIENCE_SILENT_DB
	add_child(_ambience)
	_ambience.play()


func _process(delta: float) -> void:
	if _ambience_paused:
		if not is_equal_approx(_ambience_target, 0.0):
			_fade_ambience(0.0, AMBIENCE_PAUSE_FADE)
	elif _ambience_override >= 0.0 and not is_equal_approx(_ambience_target, _ambience_override):
		# Unpaused mid-cast: the minigame is not going to ask again, so restore its level.
		_fade_ambience(_ambience_override, AMBIENCE_PAUSE_FADE)
	elif _ambience_override < 0.0:
		var inside := _player != null and is_instance_valid(_player) \
				and direction_at(_player.global_position) != ""
		var want := AMBIENCE_IDLE if inside else 0.0
		if not is_equal_approx(want, _ambience_target):
			_fade_ambience(want, AMBIENCE_FADE_IN if inside else AMBIENCE_FADE_OUT)
	if is_equal_approx(_ambience_level, _ambience_target):
		return
	_ambience_level = move_toward(_ambience_level, _ambience_target, _ambience_rate * delta)
	if _ambience == null or not is_instance_valid(_ambience):
		return
	if _ambience_level <= 0.001:
		# All the way down: give the voice back rather than leaving a silent loop running.
		_ambience.queue_free()
		_ambience = null
		return
	_ambience.volume_db = linear_to_db(_ambience_level)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	# A dialog owns the press while it is up.
	if MapManager.wants_message_input():
		return
	if _player == null or not is_instance_valid(_player) or not _player.can_move:
		return
	if not FishingData.player_has_rod():
		return
	var direction := direction_at(_player.global_position)
	if direction == "":
		return
	# Consume it so it can't also trigger an NPC or a sign behind us.
	get_viewport().set_input_as_handled()
	MapManager.start_fishing(direction)


## The water direction of the fishing rect the world point falls inside, or "" if it is
## not in one.
func direction_at(world_pos: Vector2) -> String:
	var local := to_local(world_pos)
	for child in get_children():
		if not (child is CollisionShape2D) or not (child.shape is RectangleShape2D):
			continue
		if String(child.name) == BOUNDS_NAME:
			continue
		var rect_size: Vector2 = child.shape.size
		var rect := Rect2(child.position - rect_size / 2.0, rect_size)
		if rect.has_point(local):
			var direction := _direction_from_name(String(child.name))
			if direction != "":
				return direction
			push_warning("FishingZone: '%s' has no direction in its name (expected e.g. %sDown)"
					% [child.name, NAME_PREFIX])
	return ""


## "Fish_Left_2" -> "left", and so does "Fish_Left2": Godot's own "duplicate node" names
## are the bare word with a number stuck on the end, with no underscore, and those were
## silently refusing to fish.
static func _direction_from_name(shape_name: String) -> String:
	var rest := shape_name
	if rest.begins_with(NAME_PREFIX):
		rest = rest.substr(NAME_PREFIX.length())
	var word := rest.split("_")[0].to_lower()
	while word.length() > 0 and word[word.length() - 1].is_valid_int():
		word = word.substr(0, word.length() - 1)
	return word if word in OverworldPokemon.DIRECTIONS else ""


## The FishingZone on a map, or null. The minigame is built by MapManager and has no
## reference to the zone that started it, so it looks it up off the map root.
static func find_in(map_root: Node) -> FishingZone:
	if map_root == null:
		return null
	for child in map_root.get_children():
		if child is FishingZone:
			return child
	return null
