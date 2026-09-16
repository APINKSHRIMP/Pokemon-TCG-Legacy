class_name PlacementTool
extends CanvasLayer

## In-game NPC/opponent placement editor. Debug builds only -- MapManager only
## ever constructs this behind DebugMode.is_enabled().
##
## Authoring a position as two numbers in a JSON file means guessing, relaunching,
## looking, adjusting. This lets you walk to the spot instead: grab an actor, take
## them where they belong, drop them, save. The write goes back to the exact rule
## in the map's character file that produced this actor today, so a position that
## only applies on Tuesday evenings stays scoped to Tuesday evenings.
##
## Opened from the DEL debug menu in one of three modes (see Mode): EDIT CURRENT NPCS,
## NEW NPC / OPPONENT / POKÉMON, or FLYER TABLES. The buttons along the bottom do
## the same as the keys.
##
##   F              close the tool, discarding unsaved changes
##   Tab / Shift+Tab   select next / previous actor (camera pans to them)   PREV / NEXT
##   G              grab or drop the selected actor                         GRAB / DROP
##   C              clone the selected Pokémon spawn point, held at the player  CLONE
##   Delete         delete the spawn point being held                       DELETE
##   P              Pokémon spawns: FORCED (all out, to place / scale) or RANDOM (real odds)
##   V              surfacing point's water area: V to start (clears it), then V at 4 corners  REGION
##   Ctrl+arrows    nudge 1px (add Shift for 10px) -- Ctrl also holds the player still
##   R              cycle movement pattern
##   M              edit the selected character in the character editor   EDIT NPC
##   Enter          save every pending change to the character file       SAVE
##   Escape         close (refuses while changes are unsaved)              CLOSE
##
## Input is taken in _input() rather than _unhandled_input() so the tool gets first
## refusal on every key. Escape and Enter would otherwise reach BaseMapScene and
## open the pause menu, and Space would start a conversation with whoever is being
## dragged around.

const PATTERNS := [
	"idle_down", "idle_up", "idle_left", "idle_right", "idle_random",
	"idle_cycle", "random_wander", "patrol_line", "patrol_square",
]

const HUD_FONT_SIZE := 20
const NUDGE_SMALL := 1.0
const NUDGE_LARGE := 10.0

## How the DEL debug menu opened the tool.
##   EDIT    walk round and edit what is already on the map
##   NEW     straight onto the create screen, and back to it after every save
##   FLYERS  straight onto the map's flyer tables; closes once they are saved
##   FISH    straight onto the map's fishing tables; same, but the fish table
enum Mode { EDIT, NEW, FLYERS, FISH }

## The clickable button bar along the bottom of the screen.
## Eleven buttons: 11 x 155 + 10 x 12 = 1825px, inside the 1872px between the margins.
const BUTTON_FONT_SIZE := 18
const BUTTON_SIZE := Vector2(155, 56)
## A water area smaller than this (world px) either way is refused -- four clicks on
## nearly the same spot.
const REGION_MIN_SIZE := 8.0
const BUTTON_BAR_MARGIN := 24

var _map_data: String = ""
var _container: Node2D = null
var _player: Node2D = null

var _actors: Array = []
var _index: int = -1
var _grabbed: bool = false
var _ctrl_held: bool = false
var _mode: int = Mode.EDIT
var _grab_button: Button = null
## P / the SPAWNS button. true = every spawn point and a steady stream of flocks are
## forced out, to check placement and scale; false = real chances, rates and timers,
## to see what a 2% rate actually looks like. Both run on the unsaved working copy.
var _forced_spawns: bool = true
var _spawns_button: Button = null
## V / the REGION button: capturing a surfacing point's water area, one corner per press.
var _region_capture_id: String = ""
var _region_corners: Array = []
## The area the point had before capture started, put back if the capture is abandoned.
var _region_backup = null
var _region_button: Button = null

const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"

## "section|name|rule" -> { "at": Vector2, "pattern": String }
var _pending: Dictionary = {}

## "section|name" -> the draft dictionary the character editor built. Held here
## rather than written on Confirm so F still discards a mistake cleanly, and so a
## new character is placed before it is committed to a file.
var _drafts: Dictionary = {}

var _editor: CharacterEditor = null

## ---- overworld Pokémon spawns ----
## The map's spawner, whose markers are selectable here like actors.
var _spawner: OverworldPokemonSpawner = null
## Working copy of Pokemon/Spawns/<map>.json. Markers hold references into it, so
## moving one edits it directly. Written on Enter, thrown away on F.
var _pk_doc: Dictionary = {}
var _pk_dirty: bool = false
## species -> [templates] to append to Overworld_Pokemon.json on save.
var _pk_registry_additions: Dictionary = {}
## species -> {speed_min, speed_max, scale, spin, erratic, bug, ghost} edited in the Pokémon form, written to
## Overworld_Pokemon.json on save. Species-wide, so they apply on every table and map.
var _pk_species_settings: Dictionary = {}
var _pokemon_editor: PokemonSpawnEditor = null

const POKEMON_SPAWN_HELP := [
	"Overworld Pokemon for this map. Written by the placement tool (DEL debug menu -> NEW NPC / OPPONENT / POKEMON or FLYER TABLES, or EDIT CURRENT NPCS then EDIT NPC on a spawn marker); safe to hand-edit.",
	"flyers: map-wide, one table per time of day (Morning/Afternoon/Evening/Night). The current time's table rolls every `interval` seconds with `chance`% to send a flock of ONE species from its `table` [{species, percent, min, max}] across the screen. min/max = flock size. Speed (px/s), scale, spin, erratic, bug, ghost, (skittish) wander_speed and (surfacing) swim_speed are per SPECIES, in Overworld_Pokemon.json, not per table.",
	"spawn_points: id, template, at [x, y], group (points sharing a group share every rule -- clones join their source's group, and editing one edits them all), tables {Morning/Afternoon/Evening/Night: {chance (%), table [{species, percent}]}} -- an empty table spawns nothing at that time. burying/surfacing tables also have `interval` (seconds between rolls); surfacing may have `region` [min_x, min_y, max_x, max_y] (a water area: surfaces anywhere inside, swims to the furthest edge; set with V, `at` is its centre); burying may set up_time; skittish sets flee (the run-away directions it is ALLOWED, any of left/right/up/down; out of those it takes whichever heads away from the player -- missing or empty means all four) and into_water (true = it stops at the first collider it runs into, leaps and sinks with a splash instead of fading out); static sets pattern (+ distance/speed/axis for patrols).",
	"fishing: map-wide, one table per time of day (DEL debug menu -> FISH TABLE). Which Pokemon can be hooked from a fishing area on this map. A cast always rolls exactly ONE fish, so there is no chance and no interval -- just `table` [{species, percent}]. An empty table means nothing bites at that time of day. Fishing areas themselves are named CollisionShape2D children of a FishingAreas Area2D in the map scene (Fish_Down, Fish_Left_2, ... -- the name says which way the water is), not data in this file.",
	"Table percents are weights and need not add to 100. Species keys are sprite basenames in Image_Assets/Pokemon_Sprites/.",
]

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _tinted: Node2D = null
## collision_layer / collision_mask of the grabbed actor, restored when dropped.
var _grab_collision: Array = []
## Same for the player, restored when the tool closes.
var _player_collision: Array = []


func setup(map_data: String, container: Node2D, player: Node2D, mode: int = Mode.EDIT) -> void:
	_map_data = map_data
	_container = container
	_player = player
	_mode = mode
	layer = 128
	_disable_player_collision()
	_build_hud()
	_build_buttons()
	_spawner = get_tree().get_first_node_in_group(OverworldPokemonSpawner.GROUP) as OverworldPokemonSpawner
	if _spawner != null:
		_pk_doc = _spawner.doc.duplicate(true)
		_spawner.show_markers(_pk_doc)
		# Every spawn point (and a stream of flocks) shows while the tool is open, so they
		# can be seen. P switches to the real random rolls.
		_spawner.set_preview(_forced_spawns, _pk_doc)
	_refresh_actors()
	if _actors.size() > 0:
		_index = 0
	_look_at_selection()
	_update_hud()
	match _mode:
		Mode.NEW:
			_open_editor(CharacterEditor.Mode.NEW)
		Mode.FLYERS:
			_open_pokemon_editor({}, true)
		Mode.FISH:
			_open_pokemon_editor({}, false, true)


# ============================================================
# ACTOR LIST
# ============================================================

## Nearest first, so the first Tab lands on someone you can actually see. The
## order is only rebuilt when the cast changes, not on every Tab, so cycling stays
## predictable as you walk around.
func _refresh_actors() -> void:
	var previous := _selected()
	_actors.clear()
	if _container == null or not is_instance_valid(_container):
		return
	for child in _container.get_children():
		if child.has_meta("source"):
			# Remember what pattern it spawned with, so a save can tell whether R
			# actually changed it.
			if not child.has_meta("original_pattern") and "movement_pattern" in child:
				child.set_meta("original_pattern", child.movement_pattern)
			_actors.append(child)
	if _spawner != null and is_instance_valid(_spawner):
		_actors.append_array(_spawner.get_markers())
	if _player != null and is_instance_valid(_player):
		var origin: Vector2 = _player.global_position
		_actors.sort_custom(func(a, b):
			return a.global_position.distance_squared_to(origin) \
				< b.global_position.distance_squared_to(origin))
	if previous != null and _actors.has(previous):
		_index = _actors.find(previous)
	elif _index >= _actors.size():
		_index = _actors.size() - 1


func _name_of(actor: Node) -> String:
	if actor is PokemonSpawnMarker:
		return "Pokémon spawn: %s" % str(actor.point.get("id", "?"))
	if "opponent_name" in actor and actor.opponent_name != "":
		return actor.opponent_name
	if "npc_name" in actor:
		return actor.npc_name
	return "?"


func _selected() -> Node2D:
	if _index < 0 or _index >= _actors.size():
		return null
	var actor = _actors[_index]
	return actor if is_instance_valid(actor) else null


func _key_for(actor: Node) -> String:
	var src: Dictionary = actor.get_meta("source", {})
	return "%s|%s|%d" % [src.get("section", "npcs"), src.get("name", ""), int(src.get("rule", -1))]


## Pan the view onto whoever is selected. Selecting an actor halfway across the map
## used to look like nothing had happened -- they only appeared once grabbed.
func _look_at_selection() -> void:
	if _player == null or not is_instance_valid(_player) or not ("camera" in _player):
		return
	var camera = _player.camera
	if camera == null or not is_instance_valid(camera):
		return
	var actor := _selected()
	if actor == null or _grabbed:
		camera.offset = Vector2.ZERO
	else:
		camera.offset = actor.global_position - _player.global_position


## The player walks through everything while the tool is open. Three reasons:
## dropping an actor no longer shunts the player a few pixels (which was enough to
## end up out of bounds), crossing a large map to reach one NPC is much quicker,
## and characters can be placed where the player cannot stand -- the maintenance
## worker fixing a light out in the water is scenery for that time slot, not
## somebody you are meant to reach.
##
## Note this means you can close the tool standing inside geometry. Walk clear
## first, or reopen the tool to walk out again.
func _disable_player_collision() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player_collision = [_player.collision_layer, _player.collision_mask]
	_player.collision_layer = 0
	_player.collision_mask = 0


func _restore_player_collision() -> void:
	if _player == null or not is_instance_valid(_player) or _player_collision.size() != 2:
		return
	_player.collision_layer = _player_collision[0]
	_player.collision_mask = _player_collision[1]
	_player_collision.clear()


func _clear_camera() -> void:
	if _player != null and is_instance_valid(_player) and "camera" in _player:
		var camera = _player.camera
		if camera != null and is_instance_valid(camera):
			camera.offset = Vector2.ZERO


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# The character editor is full of text boxes and takes its own keys. This runs
	# first, so without standing down entirely, typing a G into a dialogue line would
	# also grab whoever is selected out in the world.
	if _form_open():
		return

	var handled := true
	match event.keycode:
		KEY_F:
			_close()
		KEY_M:
			_open_editor(CharacterEditor.Mode.EDIT)
		KEY_ESCAPE:
			_request_close()
		KEY_TAB:
			_step_selection(-1 if event.shift_pressed else 1)
		KEY_G:
			_toggle_grab()
		KEY_DELETE:
			_delete_held()
		KEY_P:
			_toggle_forced_spawns()
		KEY_V:
			_region_step()
		KEY_C:
			# Plain C only: Ctrl is the nudge modifier and is held while nudging.
			if event.ctrl_pressed:
				handled = false
			else:
				_clone_spawn_point()
		KEY_R:
			_cycle_pattern()
		KEY_ENTER, KEY_KP_ENTER:
			_save()
		KEY_SPACE:
			# Swallowed, not acted on: Space is the interact key, and a grabbed
			# actor stands on the player, so it would open a conversation with
			# whoever is currently being dragged around.
			pass
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if event.ctrl_pressed:
				_nudge(event.keycode, NUDGE_LARGE if event.shift_pressed else NUDGE_SMALL)
			else:
				handled = false
		_:
			handled = false

	if handled:
		get_viewport().set_input_as_handled()


## Tab / Shift+Tab and the PREV / NEXT buttons.
func _step_selection(step: int) -> void:
	if _grabbed:
		_drop()
	_refresh_actors()
	if not _actors.is_empty():
		_index = wrapi(_index + step, 0, _actors.size())
		_look_at_selection()
	_update_hud()


## G and the GRAB / DROP button.
func _toggle_grab() -> void:
	if _grabbed:
		_drop()
	else:
		_grab()
	_update_hud()


## C and the CLONE button: copy the selected Pokémon spawn point -- template, time-of-day
## tables, pattern, everything -- as a new point with its own id under the player,
## already grabbed, so it can be walked to its spot and dropped with G. Pressing it
## again while carrying the copy puts that one down where it is and hands over another.
func _clone_spawn_point() -> void:
	var marker := _selected() as PokemonSpawnMarker
	if marker == null:
		_flash("[color=orange]select a Pokémon spawn point to clone (Tab), then C[/color]")
		return
	if _player == null or not is_instance_valid(_player):
		return
	# Drop first, so a point being carried is recorded where it is before the copy is made.
	if _grabbed:
		_drop()
	var source: Dictionary = marker.point
	# The clone joins the source's group, so editing either one later edits both.
	if str(source.get("group", "")) == "":
		source["group"] = str(source.get("id", ""))
	var copy: Dictionary = source.duplicate(true)
	copy["id"] = OverworldPokemonData.next_point_id(_pk_doc, str(copy.get("template", "")))
	copy["at"] = [roundi(_player.global_position.x), roundi(_player.global_position.y)]
	# A cloned water area comes along centred on the new spot.
	var source_region := OverworldPokemonData.point_region(source)
	if source_region.has_area():
		var source_at = source.get("at", [0, 0])
		var shift := Vector2(copy["at"][0] - float(source_at[0]), copy["at"][1] - float(source_at[1]))
		copy["region"] = OverworldPokemonData.region_from_corners(
				[source_region.position + shift, source_region.end + shift])
	if not (_pk_doc.get("spawn_points") is Array):
		_pk_doc["spawn_points"] = []
	(_pk_doc["spawn_points"] as Array).append(copy)
	_pk_dirty = true
	_rebuild_markers(str(copy["id"]))
	_grab()
	_update_hud()
	_flash("[color=lime]%s cloned as %s — walk it to its spot and G to drop, C for another, Enter to save[/color]"
			% [str(source.get("id", "?")), str(copy["id"])])


## P and the SPAWNS button: switch between FORCED (every point out, flocks every
## PREVIEW_FLYER_INTERVAL taking species in turn) and RANDOM (the real chances). Both
## respawn everything at once from the working copy, unsaved edits included.
func _toggle_forced_spawns() -> void:
	_forced_spawns = not _forced_spawns
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.set_preview(_forced_spawns, _pk_doc)
	_update_hud()
	_flash("[color=aqua]%s[/color]" % ("FORCED spawns — every spawn point out, a flock every %.1fs, species in turn"
			% OverworldPokemonSpawner.PREVIEW_FLYER_INTERVAL if _forced_spawns
			else "RANDOM spawns — real chances, rates and timers (from your unsaved edits)"))


## Delete and the DELETE button: remove the spawn point being HELD, with no form. Only
## while grabbed, so a stray key can't delete whatever happens to be selected. Like
## every other edit it waits for Enter / SAVE (F discards). Characters have no delete
## path anywhere in the tool, so this is spawn points only.
func _delete_held() -> void:
	if not _grabbed:
		_flash("[color=orange]grab a spawn point first (G), then Delete[/color]")
		return
	var marker := _selected() as PokemonSpawnMarker
	if marker == null:
		_flash("[color=orange]only Pokémon spawn points can be deleted here[/color]")
		return
	var id := str(marker.point.get("id", ""))
	# Let go without _drop(): there is nothing left to record a position for.
	_grabbed = false
	_grab_collision.clear()
	var points: Array = _pk_doc.get("spawn_points", [])
	for i in points.size():
		if points[i] is Dictionary and str(points[i].get("id", "")) == id:
			points.remove_at(i)
			break
	_pk_dirty = true
	_rebuild_markers("")
	_preview_point(id)
	_update_hud()
	_flash("[color=orange]%s deleted — Enter to write, F to discard[/color]" % id)


## V and the REGION button. Not capturing: start capturing the selected surfacing point's
## water area, clearing any area it had (the "reset"). Capturing: drop a corner where the
## player stands; the fourth snaps all four to the rectangle around them, moves the point
## to its centre and shows a Pokémon in it.
func _region_step() -> void:
	if _region_capture_id == "":
		var marker := _selected() as PokemonSpawnMarker
		if marker == null or str(marker.point.get("template", "")) != "surfacing":
			_flash("[color=orange]select a surfacing spawn point (Tab), then V to set its water area[/color]")
			return
		if _grabbed:
			_drop()
		_start_region_capture(str(marker.point.get("id", "")))
		return
	if _player == null or not is_instance_valid(_player):
		return
	_region_corners.append(_player.global_position.round())
	if _region_corners.size() < 4:
		_refresh_capture_marker()
		_update_hud()
		_flash("[color=aqua]corner %d/4 set — walk to the next corner and press V[/color]" % _region_corners.size())
		return
	_finish_region_capture()


func _start_region_capture(id: String) -> void:
	var point := OverworldPokemonData.find_point(_pk_doc, id)
	if point.is_empty():
		return
	_region_capture_id = id
	_region_corners.clear()
	_region_backup = point.get("region")
	point.erase("region")
	_pk_dirty = true
	_preview_point(id)
	_refresh_capture_marker()
	_update_hud()
	_flash("[color=aqua]%s: walk to a corner of the water and press V (4 corners). Esc cancels.[/color]" % id)


func _finish_region_capture() -> void:
	var id := _region_capture_id
	var point := OverworldPokemonData.find_point(_pk_doc, id)
	var region := OverworldPokemonData.region_from_corners(_region_corners)
	var rect := Rect2(Vector2(region[0], region[1]), Vector2(region[2] - region[0], region[3] - region[1]))
	if point.is_empty() or rect.size.x < REGION_MIN_SIZE or rect.size.y < REGION_MIN_SIZE:
		_region_corners.clear()
		_refresh_capture_marker()
		_update_hud()
		_flash("[color=orange]that area is too thin — pick the 4 corners again (V), or Esc to cancel[/color]")
		return
	point["region"] = region
	var centre := rect.get_center()
	point["at"] = [roundi(centre.x), roundi(centre.y)]
	_region_capture_id = ""
	_region_corners.clear()
	_region_backup = null
	_pk_dirty = true
	_rebuild_markers(id)
	_preview_point(id)
	_update_hud()
	_flash("[color=lime]%s water area set (%d x %d) — Enter to save, V again to redo it[/color]"
			% [id, roundi(rect.size.x), roundi(rect.size.y)])


## Escape mid-capture: the point gets back whatever area it had before.
func _cancel_region_capture() -> void:
	var point := OverworldPokemonData.find_point(_pk_doc, _region_capture_id)
	if not point.is_empty() and _region_backup is Array:
		point["region"] = _region_backup
	var id := _region_capture_id
	_region_capture_id = ""
	_region_corners.clear()
	_region_backup = null
	_rebuild_markers(id)
	_preview_point(id)
	_update_hud()
	_flash("[color=orange]water area capture cancelled[/color]")


func _refresh_capture_marker() -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	var marker := _spawner.find_marker(_region_capture_id)
	if marker != null:
		marker.pending_corners = _region_corners.duplicate()
		marker.queue_redraw()


## Escape and the CLOSE button. Refuses while anything is unsaved -- F is the
## deliberate discard.
func _request_close() -> void:
	# Mid-capture, Escape backs out of the capture rather than the tool.
	if _region_capture_id != "":
		_cancel_region_capture()
		return
	if has_unsaved_changes():
		_flash("[color=orange]unsaved changes — SAVE (Enter) first, or F to discard and close[/color]")
	else:
		_close()


## NEW and FLYERS mode exist for the form they opened on, so backing out of it with
## nothing waiting to be saved goes straight back to the game.
func _close_if_done() -> void:
	if _mode != Mode.EDIT and not has_unsaved_changes():
		_close()


func _process(_delta: float) -> void:
	# Ctrl is polled, not event-driven, so it would still register through the form --
	# a Ctrl+C in a dialogue box would lock and unlock the player behind it.
	if _form_open():
		return
	# Arrow keys are the player's movement and are polled, not event-driven, so
	# consuming the key event is not enough -- the player has to be held still for
	# the duration of a nudge. Ctrl is the modifier that does it.
	var ctrl_now := Input.is_key_pressed(KEY_CTRL)
	if ctrl_now != _ctrl_held:
		_ctrl_held = ctrl_now
		if _player != null and is_instance_valid(_player):
			if _ctrl_held:
				_player.lock_movement()
			else:
				_player.unlock_movement()
		_update_hud()

	if not _grabbed:
		return
	var actor := _selected()
	if actor == null or _player == null or not is_instance_valid(_player):
		_drop()
		return
	actor.global_position = _player.global_position
	_update_hud()


# ============================================================
# GRAB / DROP
# ============================================================

## A grabbed actor sits exactly where the player stands. Two solid bodies in one
## spot shove each other apart hard -- which is what fired the player off across
## the map -- so its collision comes off for the duration, and its own movement is
## frozen so it does not wander out of your hands.
func _grab() -> void:
	var actor := _selected()
	if actor == null:
		return
	_grabbed = true
	_grab_collision.clear()
	# Spawn markers are plain Node2Ds with no collision to lift.
	if actor is CollisionObject2D:
		_grab_collision = [actor.collision_layer, actor.collision_mask]
		actor.collision_layer = 0
		actor.collision_mask = 0
	if actor.has_method("freeze"):
		actor.freeze()
	_clear_camera()


func _drop() -> void:
	var actor := _selected()
	_grabbed = false
	if actor == null:
		_grab_collision.clear()
		return
	if _grab_collision.size() == 2:
		actor.collision_layer = _grab_collision[0]
		actor.collision_mask = _grab_collision[1]
	_grab_collision.clear()
	if actor.has_method("resume_movement"):
		actor.resume_movement()
	_record(actor)
	_look_at_selection()


func _nudge(keycode: int, amount: float) -> void:
	var actor := _selected()
	if actor == null:
		return
	match keycode:
		KEY_LEFT:  actor.position.x -= amount
		KEY_RIGHT: actor.position.x += amount
		KEY_UP:    actor.position.y -= amount
		KEY_DOWN:  actor.position.y += amount
	_record(actor)
	_look_at_selection()
	_update_hud()


func _cycle_pattern() -> void:
	var actor := _selected()
	if actor == null or not ("movement_pattern" in actor):
		return
	var current: int = PATTERNS.find(actor.movement_pattern)
	actor.movement_pattern = PATTERNS[wrapi(current + 1, 0, PATTERNS.size())]
	_record(actor)
	_update_hud()


func _record(actor: Node2D) -> void:
	# A spawn marker holds a reference into _pk_doc, so its new position goes
	# straight into the working copy of the spawn file.
	if actor is PokemonSpawnMarker:
		var old_at = actor.point.get("at", [0, 0])
		var new_at := [roundi(actor.global_position.x), roundi(actor.global_position.y)]
		# A water area travels with its point.
		var region := OverworldPokemonData.point_region(actor.point)
		if region.has_area():
			var shift := Vector2(new_at[0] - float(old_at[0]), new_at[1] - float(old_at[1]))
			actor.point["region"] = OverworldPokemonData.region_from_corners([region.position + shift, region.end + shift])
		actor.point["at"] = new_at
		actor.queue_redraw()
		_pk_dirty = true
		# Show what it spawns at its new spot straight away.
		_preview_point(str(actor.point.get("id", "")))
		return
	var key := _key_for(actor)
	var src: Dictionary = actor.get_meta("source", {})
	var entry: Dictionary = _pending.get(key, {})
	entry["at"] = actor.position
	entry["at_owner"] = int(src.get("at_owner", -1))
	entry["move_owner"] = int(src.get("move_owner", -1))
	# Only record the pattern if R actually changed it. Writing it unconditionally
	# replaced a structured move ({pattern, radius, speed}) with a bare pattern
	# string, silently dropping the radius and speed the character was tuned with.
	# Cycling R all the way back round to where it started counts as no change too,
	# so the key is dropped again rather than left behind from the press before.
	var was: String = str(actor.get_meta("original_pattern", ""))
	var changed: bool = ("movement_pattern" in actor) and was != ""
	if changed and actor.movement_pattern != was:
		entry["pattern"] = actor.movement_pattern
	elif changed:
		entry.erase("pattern")
	_pending[key] = entry


func _close() -> void:
	if _grabbed:
		_drop()
	# F is the deliberate discard path (Escape refuses instead), but say what went
	# in the bin -- losing a move silently is how you lose it twice.
	if has_unsaved_changes():
		print("PlacementTool: closed, DISCARDING %d move(s), %d character draft(s)%s"
			% [_pending.size(), _drafts.size(), " and Pokémon spawn edits" if _pk_dirty else ""])
	queue_free()


# ============================================================
# CHARACTER EDITOR
# ============================================================

## Open the creation / edit form. Nothing it produces reaches disk on its own --
## Confirm hands back a draft, which is placed in the world and held until Enter.
func _open_editor(mode: int) -> void:
	if _form_open():
		return
	var actor: Node2D = null
	if mode == CharacterEditor.Mode.EDIT:
		actor = _selected()
		if actor == null:
			_flash("[color=orange]nothing selected — Tab to pick a character, then M[/color]")
			return
		if actor is PokemonSpawnMarker:
			_open_pokemon_editor(actor.point)
			return
		if not actor.has_meta("source"):
			# Dynamically generated actors (the gym crowd) are spawned without
			# provenance, so there is no file entry to edit.
			_flash("[color=orange]%s was generated at runtime — it has no file entry to edit[/color]"
				% _name_of(actor))
			return
	if _grabbed:
		_drop()
		_update_hud()
	_editor = CharacterEditor.new()
	get_tree().current_scene.add_child(_editor)
	_editor.confirmed.connect(_on_editor_confirmed)
	_editor.cancelled.connect(_on_editor_cancelled)
	_editor.pokemon_chosen.connect(_on_editor_pokemon_chosen)
	_editor.flyers_chosen.connect(_on_editor_flyers_chosen)
	# Before setup(): an edit whose character has vanished from the file cancels from
	# inside setup(), and _on_editor_cancelled has to be the thing that thaws.
	_freeze_player_for_form()
	_editor.setup(_map_data, mode, actor, _draft_names(), _draft_coins())


## The player must not walk while the form is on screen.
##
## Player_Object polls Input.is_key_pressed(KEY_W/A/S/D) straight from the OS in
## _physics_process, so neither GUI focus nor a consumed event stops it: every
## letter typed into a dialogue box walked the player, every capital held Shift and
## ran them at the debug 10x multiplier, and the tool has already taken their
## collision off -- so they left the map through the tree line while the form hid
## the view. Confirm then dropped the new character on top of them, thousands of
## pixels outside the map, and the camera (clamped to its limits) came back showing
## nothing but empty space: an entirely black screen with no way to tell why.
func _freeze_player_for_form() -> void:
	if _player != null and is_instance_valid(_player):
		_player.lock_movement()


## Ctrl is polled in _process(), which stands down entirely while the form is open,
## so _ctrl_held can be stale by the time we get back. Re-read it rather than
## unlocking into a Ctrl that is still being held.
func _thaw_player_after_form() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_ctrl_held = Input.is_key_pressed(KEY_CTRL)
	if _ctrl_held:
		_player.lock_movement()
	else:
		_player.unlock_movement()


## Names and coins the drafts have already claimed. The editor reads the files on
## disk for uniqueness, and a draft is not on disk yet.
func _draft_names() -> Array:
	var out: Array = []
	for key in _drafts:
		out.append(_drafts[key].get("name", ""))
	return out


func _draft_coins() -> Array:
	var out: Array = []
	for key in _drafts:
		var draft: Dictionary = _drafts[key]
		for source in [draft.get("constants", {}), draft.get("character", {}), draft.get("rule", {})]:
			if source.has("coin_reward"):
				out.append(source["coin_reward"])
			if str(source.get("gift_type", "")) == "coin":
				out.append(source.get("gift_value", ""))
	return out


func _on_editor_cancelled() -> void:
	_editor = null
	_thaw_player_after_form()
	_update_hud()
	_close_if_done()


func _form_open() -> bool:
	return (_editor != null and is_instance_valid(_editor)) \
		or (_pokemon_editor != null and is_instance_valid(_pokemon_editor))


# ============================================================
# POKÉMON SPAWN EDITOR
# ============================================================

## N -> POKÉMON. The character form has already freed itself; the player is still
## frozen from when it opened.
func _on_editor_pokemon_chosen() -> void:
	_editor = null
	_open_pokemon_editor({})


## N -> FLYER TABLES. As above, but straight onto the map's flyer tables.
func _on_editor_flyers_chosen() -> void:
	_editor = null
	_open_pokemon_editor({}, true)


## `point` is a spawn point in _pk_doc to edit, or {} for a new point / the flyers.
## `flyers` opens the form on the map's time-of-day flyer tables.
func _open_pokemon_editor(point: Dictionary, flyers: bool = false, fish: bool = false) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		_thaw_player_after_form()
		_flash("[color=orange]this map has no Pokémon spawner (it has no character file)[/color]")
		return
	if _grabbed:
		_drop()
	_pokemon_editor = PokemonSpawnEditor.new()
	get_tree().current_scene.add_child(_pokemon_editor)
	_pokemon_editor.confirmed.connect(_on_pokemon_editor_confirmed)
	_pokemon_editor.cancelled.connect(_on_pokemon_editor_cancelled)
	_pokemon_editor.save_requested.connect(_on_pokemon_editor_save_requested)
	_freeze_player_for_form()
	_pokemon_editor.setup(_map_data, _pk_doc, point, _pk_registry_additions, flyers,
			_pk_species_settings, fish)
	_update_hud()


func _on_pokemon_editor_cancelled() -> void:
	_pokemon_editor = null
	_thaw_player_after_form()
	_update_hud()
	_close_if_done()


func _on_pokemon_editor_confirmed(draft: Dictionary) -> void:
	_pokemon_editor = null
	_thaw_player_after_form()
	_merge_registry_additions(draft)
	_pk_dirty = true

	if not (_pk_doc.get("spawn_points") is Array):
		_pk_doc["spawn_points"] = []
	var points: Array = _pk_doc["spawn_points"]
	var original_id := str(draft.get("original_id", ""))
	var point: Dictionary = draft.get("point", {})
	var id := str(point.get("id", ""))
	var linked_updates := 0

	if bool(draft.get("delete", false)):
		for i in points.size():
			if points[i] is Dictionary and str(points[i].get("id", "")) == original_id:
				points.remove_at(i)
				break
		_rebuild_markers("")
		_preview_point(original_id)
		_update_hud()
		_flash("[color=orange]%s deleted — Enter to write, F to discard[/color]" % original_id)
		return

	if bool(draft.get("is_new", true)):
		if _player == null or not is_instance_valid(_player):
			_flash("[color=red]no player to place %s at[/color]" % id)
			return
		point["at"] = [roundi(_player.global_position.x), roundi(_player.global_position.y)]
		points.append(point)
		_rebuild_markers(id)
		if str(point.get("template", "")) == "surfacing":
			# A surfacing point is an area of water: straight into picking its 4 corners.
			_start_region_capture(id)
		else:
			# Handed to you to place, the same as a new character.
			_grab()
	else:
		var existing := OverworldPokemonData.find_point(_pk_doc, original_id)
		if existing.is_empty():
			points.append(point)
		else:
			# Rewritten in place so the point keeps its position in the list.
			existing.clear()
			existing.merge(point)
		# Linked clones: every other point in the same group takes the same rules, keeping
		# only its own id and position. Cleared and merged in place, because the markers
		# hold references to these dictionaries.
		var group := str(point.get("group", id))
		for other in points:
			if not (other is Dictionary) or is_same(other, existing) or str(other.get("group", "")) != group:
				continue
			# Id, spot and water area are where each clone IS, not its rules.
			var keep_id = other.get("id")
			var keep_at = other.get("at")
			var keep_region = other.get("region")
			other.clear()
			other.merge(point.duplicate(true))
			other["id"] = keep_id
			other["at"] = keep_at
			if keep_region is Array:
				other["region"] = keep_region
			else:
				other.erase("region")
			linked_updates += 1
		_rebuild_markers(id)
		for other in points:
			if other is Dictionary and str(other.get("group", "")) == group:
				_preview_point(str(other.get("id", "")))
		_look_at_selection()
	_update_hud()
	var also := "" if linked_updates == 0 else " (and %d linked clone%s)" % [linked_updates, "" if linked_updates == 1 else "s"]
	_flash("[color=lime]%s%s ready — Enter to write Pokemon/Spawns/%s.json[/color]" % [id, also, _map_data])


## Flyer or fish tables. SAVE: write the spawn file straight away and leave the form open.
## Any spawn-point edits already waiting in _pk_doc are written with it.
func _on_pokemon_editor_save_requested(draft: Dictionary) -> void:
	_merge_registry_additions(draft)
	var kind := str(draft.get("kind", "flyers"))
	if kind == "fishing":
		_pk_doc["fishing"] = draft.get("fishing", {})
		# The next cast reads the file again rather than the table it cached on load.
		FishingData.invalidate()
	else:
		_pk_doc["flyers"] = draft.get("flyers", {})
	_pk_dirty = true
	var ok := _save_pokemon()
	if ok:
		print("PlacementTool: saved %s tables -> %s"
				% [kind, OverworldPokemonData.spawn_path(_map_data)])
	if _pokemon_editor != null and is_instance_valid(_pokemon_editor):
		_pokemon_editor.notify_saved(ok)
	_update_hud()


func _merge_registry_additions(draft: Dictionary) -> void:
	var settings: Dictionary = draft.get("species_settings", {})
	for species in settings:
		var merged: Dictionary = _pk_species_settings.get(species, {})
		merged.merge(settings[species], true)
		_pk_species_settings[species] = merged
	var additions: Dictionary = draft.get("registry_additions", {})
	for species in additions:
		var list: Array = _pk_registry_additions.get(species, [])
		for template in additions[species]:
			if not list.has(template):
				list.append(template)
		_pk_registry_additions[species] = list


## Show the Pokémon spawn point `id` would put out, where the point now is (or clear
## it if the point has been deleted).
func _preview_point(id: String) -> void:
	if _spawner != null and is_instance_valid(_spawner) and id != "":
		_spawner.respawn_point(id)


## Redraw every marker from _pk_doc and reselect `select_id` if given.
func _rebuild_markers(select_id: String) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		return
	_spawner.show_markers(_pk_doc)
	_refresh_actors()
	if select_id != "":
		var marker := _spawner.find_marker(select_id)
		if marker != null and _actors.has(marker):
			_index = _actors.find(marker)
	_look_at_selection()


## Write the spawn file (and any new species->template assignments), then re-roll
## the live Pokémon from it so the change can be seen straight away.
func _save_pokemon() -> bool:
	DirAccess.make_dir_recursive_absolute(OverworldPokemonData.SPAWN_DIR)
	var out: Dictionary = {"_help": POKEMON_SPAWN_HELP}
	for key in _pk_doc:
		if key != "_help":
			out[key] = _pk_doc[key]
	if not _write_json(OverworldPokemonData.spawn_path(_map_data), out):
		return false
	if not _pk_registry_additions.is_empty() or not _pk_species_settings.is_empty():
		var registry := OverworldPokemonData._read_json(OverworldPokemonData.REGISTRY_PATH)
		if not (registry.get("species") is Dictionary):
			registry["species"] = {}
		for species in _pk_registry_additions:
			var body = registry["species"].get(species)
			if not (body is Dictionary):
				body = {"templates": []}
				registry["species"][species] = body
			var list: Array = body.get("templates", [])
			for template in _pk_registry_additions[species]:
				if not list.has(template):
					list.append(template)
			body["templates"] = list
		# Speed and scale are the species' own, so they go here rather than into a table.
		for species in _pk_species_settings:
			var body = registry["species"].get(species)
			if not (body is Dictionary):
				body = {"templates": []}
				registry["species"][species] = body
			for key in _pk_species_settings[species]:
				body[key] = _pk_species_settings[species][key]
		if not _write_registry(registry):
			return false
		OverworldPokemonData.invalidate()
		_pk_registry_additions.clear()
		_pk_species_settings.clear()
	_pk_dirty = false
	if _spawner != null and is_instance_valid(_spawner):
		# Still open, so still previewing -- against the working copy that was just saved.
		_spawner.set_preview(_forced_spawns, _pk_doc)
	return true


func _on_editor_confirmed(draft: Dictionary) -> void:
	_editor = null
	_thaw_player_after_form()
	var section: String = str(draft.get("section", "npcs"))
	var name: String = str(draft.get("name", ""))
	var entry: Dictionary = draft.get("entry", {}).duplicate(true)

	# Where the actor goes, and the provenance a save needs. An edited character
	# keeps its original provenance so a positional write still lands on the rule it
	# came from; a new one owns its defaults outright.
	var at: Vector2
	# What the actor is walking with right now, and what it spawned with. Both have to
	# survive the respawn. The live pattern is what you can see it doing -- respawned
	# from the form alone, a patrol line came back standing still. `original_pattern`
	# is what _record() compares against to tell a deliberate R press from no change,
	# and _refresh_actors() would otherwise stamp the editor's default onto the new
	# node: R would then cycle on from the wrong pattern and save that.
	var was_pattern: String = ""
	var existing := _selected()
	if not bool(draft.get("is_new", true)) and existing != null and is_instance_valid(existing):
		at = existing.position
		entry["_source"] = existing.get_meta("source", {}).duplicate(true)
		if "movement_pattern" in existing:
			# Set on the entry rather than on the node afterwards, so _init_movement()
			# runs against the right pattern in _ready() -- an unsaved R press is kept
			# this way round, not re-applied to a node that has already set itself up.
			entry["pattern"] = existing.movement_pattern
			was_pattern = str(existing.get_meta("original_pattern", existing.movement_pattern))
		# Respawned rather than reconfigured: WorldObjectBase loads its sprite sheet
		# in _ready(), so assigning a new sprite to a live node changes nothing.
		if _tinted == existing:
			_tinted = null
		# remove_child before queue_free: a queued node stays a child until the end
		# of the frame, so _refresh_actors() below would pick the old one back up and
		# leave the list holding a corpse.
		_container.remove_child(existing)
		existing.queue_free()
	else:
		if _player == null or not is_instance_valid(_player):
			_flash("[color=red]no player to place %s at[/color]" % name)
			return
		at = _container.to_local(_player.global_position)
		entry["_source"] = {
			"section": section, "name": name, "rule": -1,
			"at_owner": -1, "move_owner": -1,
		}

	var actor := MapManager.spawn_editor_actor(entry, section, at)
	if actor == null:
		_flash("[color=red]could not spawn %s[/color]" % name)
		return
	# Before _refresh_actors(), which only stamps this meta on an actor that has none.
	if was_pattern != "":
		actor.set_meta("original_pattern", was_pattern)

	_drafts["%s|%s" % [section, name]] = draft
	_refresh_actors()
	if _actors.has(actor):
		_index = _actors.find(actor)
	# A new character is handed straight to you to place. An edited one is already
	# where it belongs, so it stays put -- forcing you to re-place someone whose
	# dialogue you only came to fix would be a good way to move them by accident.
	if bool(draft.get("is_new", true)):
		_record(actor)
		_grab()
	else:
		_look_at_selection()
	_update_hud()
	_flash("[color=lime]%s ready — Enter to write it to %s.json[/color]" % [name, _map_data])


# ============================================================
# SAVING
# ============================================================

func _save() -> void:
	# Enter means "save what I am looking at". A grab in flight has moved the actor
	# but not recorded it -- only _drop() does that -- so saving mid-grab used to
	# report nothing to save and quietly throw the move away.
	if _grabbed:
		_drop()
		_update_hud()
	if _pending.is_empty() and _drafts.is_empty() and not _pk_dirty:
		_flash("[color=orange]nothing to save — move an actor first[/color]")
		print("PlacementTool: save requested with no pending changes")
		return
	# Pokémon spawns live in their own file, so they are written first and on their
	# own -- the character file is only rewritten when a character actually changed.
	var pokemon_saved := false
	if _pk_dirty:
		if not _save_pokemon():
			return
		pokemon_saved = true
		if _pending.is_empty() and _drafts.is_empty():
			_flash("[color=lime]saved Pokémon spawns to Pokemon/Spawns/%s.json[/color]" % _map_data)
			print("PlacementTool: saved Pokémon spawns -> " + OverworldPokemonData.spawn_path(_map_data))
			_after_save()
			return
	var path := CharacterSchedule.DIR + _map_data + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_flash("[color=red]cannot open %s[/color]" % path)
		return
	var doc = JSON.parse_string(file.get_as_text())
	file.close()
	if not (doc is Dictionary):
		_flash("[color=red]%s is not valid JSON[/color]" % path)
		return

	# Characters first: a new character's entry has to exist in `doc` before the
	# positional pass below goes looking for it by name.
	var constants: Dictionary = {}
	var characters_written := 0
	## "section|name" -> { old rule index: new rule index }, for the characters whose
	## rule list a schedule change reshaped. The positional writes below still hold
	## the indices the map spawned with.
	var remaps: Dictionary = {}
	if not _drafts.is_empty():
		var cfile := FileAccess.open(CONSTANTS_PATH, FileAccess.READ)
		if cfile == null:
			_flash("[color=red]cannot open %s[/color]" % CONSTANTS_PATH)
			return
		var parsed = JSON.parse_string(cfile.get_as_text())
		cfile.close()
		if not (parsed is Dictionary):
			_flash("[color=red]All_NPC_Constant_Data.json is not valid JSON[/color]")
			return
		constants = parsed
		for key in _drafts:
			var draft: Dictionary = _drafts[key]
			var remap := _apply_draft(doc, constants, draft)
			if not remap.is_empty():
				remaps["%s|%s" % [str(draft.get("section", "npcs")),
						str(draft.get("name", ""))]] = remap
			characters_written += 1

	var written := 0
	for key in _pending:
		var parts: PackedStringArray = str(key).split("|")
		if parts.size() != 3:
			continue
		var section: String = parts[0]
		var name: String = parts[1]
		var rule_index := int(parts[2])
		var character = doc.get(section, {}).get(name)
		if not (character is Dictionary):
			push_warning("PlacementTool: %s/%s vanished from %s" % [section, name, path])
			continue
		var change: Dictionary = _pending[key]
		var at: Vector2 = change["at"]
		# A schedule edit in the same save may have spliced this character's rule
		# list, so the index the actor spawned with is translated before it is used.
		var remap: Dictionary = remaps.get("%s|%s" % [section, name], {})
		# Write each field where it currently lives. A character whose rules only
		# say WHEN they appear keeps one shared position, so moving them moves them
		# everywhere; a rule that genuinely overrides the position keeps its override
		# scoped to those days.
		var at_target := _owner_of(character,
				_remap(remap, int(change.get("at_owner", rule_index))))
		at_target["at"] = [roundi(at.x), roundi(at.y)]
		if change.has("pattern"):
			var move_target := _owner_of(character,
					_remap(remap, int(change.get("move_owner", rule_index))))
			# Keep the object form's extra numbers if the character already had them.
			if move_target.get("move") is Dictionary:
				move_target["move"]["pattern"] = change["pattern"]
			else:
				move_target["move"] = change["pattern"]
		written += 1

	if not _write_json(path, doc):
		return
	if not _drafts.is_empty() and not _write_json(CONSTANTS_PATH, constants):
		return

	_pending.clear()
	_drafts.clear()
	CharacterSchedule.invalidate(_map_data)
	var summary := "saved %d move(s)" % written
	if characters_written > 0:
		summary += " and %d character(s), incl. All_NPC_Constant_Data.json" % characters_written
	if pokemon_saved:
		summary += ", plus Pokémon spawns"
	_flash("[color=lime]%s to %s.json[/color]" % [summary, _map_data])
	print("PlacementTool: %s -> %s" % [summary, path])
	_after_save()


## NEW mode goes straight back to the create screen for the next one. (FLYERS mode
## saves from the form itself and closes when the form is closed.)
func _after_save() -> void:
	if _mode == Mode.NEW:
		_open_editor(CharacterEditor.Mode.NEW)


## Merge one editor draft into the two documents.
##
## Fields land wherever the draft said they should: the character's defaults, the
## `when` rule that produced the actor today, or the constants file. A new key is
## APPENDED to its section rather than inserted alphabetically -- the `opponents`
## section is sorted but `npcs` is not, so re-sorting would rewrite the whole file
## and bury the one real change in the diff.
##
## Returns the old rule index -> new rule index map from the schedule rewrite, so the
## positional pass can still find the rule an actor came from.
func _apply_draft(doc: Dictionary, constants: Dictionary, draft: Dictionary) -> Dictionary:
	var section: String = str(draft.get("section", "npcs"))
	var name: String = str(draft.get("name", ""))
	if name == "":
		return {}

	if not (doc.get(section) is Dictionary):
		doc[section] = {}
	if not (doc[section].get(name) is Dictionary):
		doc[section][name] = {}
	var character: Dictionary = doc[section][name]

	for field in draft.get("character", {}):
		character[field] = draft["character"][field]

	# The schedule goes in before any per-rule field, because rewriting it can add,
	# drop or move the very rules those fields are about to be written into.
	var remap := CharacterSchedule.apply_schedule(character, draft.get("schedule", {}))
	var rule_index: int = _remap(remap, int(draft.get("rule_index", -1)))

	var rule_fields: Dictionary = draft.get("rule", {})
	if not rule_fields.is_empty():
		var rules = character.get("when")
		if rules is Array and rule_index >= 0 and rule_index < rules.size() \
				and rules[rule_index] is Dictionary:
			for field in rule_fields:
				rules[rule_index][field] = rule_fields[field]
		else:
			# The rule the actor came from is gone -- the file was edited by hand
			# since the map loaded. Put the values on the defaults rather than
			# dropping the edit on the floor.
			push_warning("PlacementTool: when-rule #%d missing on %s/%s, writing to defaults"
				% [rule_index, section, name])
			for field in rule_fields:
				character[field] = rule_fields[field]

	var constant_fields: Dictionary = draft.get("constants", {})
	var removals: Array = draft.get("remove", [])
	if constant_fields.is_empty() and removals.is_empty():
		return remap
	if not (constants.get(section) is Dictionary):
		constants[section] = {}
	if not (constants[section].get(name) is Dictionary):
		constants[section][name] = {}
	var body: Dictionary = constants[section][name]
	for field in constant_fields:
		body[field] = constant_fields[field]

	# A cleared field is erased from all three homes. Which one it actually lived in
	# depends on whether the map file overrode the constant, and the answer has to be
	# "gone" either way -- leaving a copy behind in the file the editor did not think
	# it was writing is exactly the silent-failure this tool exists to stop.
	for field in removals:
		body.erase(field)
		character.erase(field)
		var rule_list = character.get("when")
		if rule_list is Array and rule_index >= 0 and rule_index < rule_list.size() \
				and rule_list[rule_index] is Dictionary:
			rule_list[rule_index].erase(field)
	return remap


## An old rule index seen through a rule-list rewrite. Anything the rewrite did not
## touch -- including the -1 that means "the character's own defaults" -- passes
## straight through.
func _remap(remap: Dictionary, index: int) -> int:
	return int(remap.get(index, index))


func _write_json(path: String, doc: Dictionary) -> bool:
	var text := JSON.stringify(_normalise_numbers(doc), "  ", false)
	text = _compact_pairs(text)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_flash("[color=red]cannot write %s[/color]" % path)
		return false
	out.store_string(text + "\n")
	out.close()
	return true


## Overworld_Pokemon.json is hand-edited and kept one species per line. The general
## writer would spread every entry over several lines and bury a one-number speed
## change in a diff of the whole file, so it gets this compact layout instead.
func _write_registry(registry: Dictionary) -> bool:
	var doc: Dictionary = _normalise_numbers(registry)
	var lines: Array = ["{"]
	if doc.has("_help"):
		lines.append('  "_help": %s,' % JSON.stringify(doc["_help"], "  ").replace("\n", "\n  "))
	lines.append('  "species": {')
	var species: Dictionary = doc.get("species", {})
	var keys: Array = species.keys()
	for i in keys.size():
		var comma := "," if i < keys.size() - 1 else ""
		lines.append('    %s: %s%s' % [JSON.stringify(str(keys[i])), JSON.stringify(species[keys[i]]), comma])
	lines.append("  }")
	lines.append("}")
	var out := FileAccess.open(OverworldPokemonData.REGISTRY_PATH, FileAccess.WRITE)
	if out == null:
		_flash("[color=red]cannot write %s[/color]" % OverworldPokemonData.REGISTRY_PATH)
		return false
	out.store_string("\n".join(lines) + "\n")
	out.close()
	return true


## The rule that owns a field, or the character itself when the value is inherited.
func _owner_of(character: Dictionary, owner_index: int) -> Dictionary:
	if owner_index < 0:
		return character
	var rules = character.get("when")
	if rules is Array and owner_index < rules.size() and rules[owner_index] is Dictionary:
		return rules[owner_index]
	return character


## Turn whole-number floats back into ints, everywhere in the document.
##
## Godot's JSON parser reads EVERY number as a float -- `"radius": 65` comes back
## as 65.0 and JSON.stringify writes it out that way. Saving therefore rewrote
## numbers the tool never touched: the last placement pass turned 65 radius and
## speed values in Verdant_Forest.json into floats, burying the positions that
## actually changed. Writing All_NPC_Constant_Data.json without this would do the
## same to all 103 `prize_cards`, which the schema documents as an int.
##
## Nothing reads these as ints, so collapsing a genuine 20.0 to 20 changes no
## behaviour -- JSON has one number type and the parser floats them again on the
## way back in. What it buys is a writer that round-trips, so the next save's diff
## is only what moved.
func _normalise_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out_dict: Dictionary = {}
		for key in value:
			out_dict[key] = _normalise_numbers(value[key])
		return out_dict
	if value is Array:
		var out_array: Array = []
		for item in value:
			out_array.append(_normalise_numbers(item))
		return out_array
	if value is float:
		var number: float = value
		# 2^53 is where a float stops being able to hold every integer exactly.
		if number == floor(number) and absf(number) < 9007199254740992.0:
			return int(number)
	return value


## Put coordinate pairs back on one line. JSON.stringify would otherwise spread
## every "at" over four lines and churn the whole file in the diff.
func _compact_pairs(text: String) -> String:
	var re := RegEx.new()
	re.compile(r'\[\s*\n\s*(-?\d+(?:\.\d+)?),\s*\n\s*(-?\d+(?:\.\d+)?)\s*\n\s*\]')
	return re.sub(text, "[$1, $2]", true)


# ============================================================
# HUD
# ============================================================

func _build_hud() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(24, 24)
	_panel.custom_minimum_size = Vector2(620, 0)
	# Never take focus or swallow clicks -- a focused Control eats the arrow keys.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.focus_mode = Control.FOCUS_NONE
	_label.custom_minimum_size = Vector2(596, 0)
	_label.add_theme_font_size_override("normal_font_size", HUD_FONT_SIZE)
	_label.add_theme_font_size_override("bold_font_size", HUD_FONT_SIZE)
	_panel.add_child(_label)
	add_child(_panel)


## Clickable versions of the keys, along the bottom-left of the screen. Every button
## is FOCUS_NONE: a focused button eats the arrow keys the player walks with, and
## Space / Enter would press it again.
func _build_buttons() -> void:
	var bar := HBoxContainer.new()
	bar.theme = DebugFormTheme.build()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	_add_button(bar, "< PREV", func(): _step_selection(-1))
	_add_button(bar, "NEXT >", func(): _step_selection(1))
	_grab_button = _add_button(bar, "GRAB", _toggle_grab)
	_add_button(bar, "CLONE", _clone_spawn_point)
	_add_button(bar, "DELETE", _delete_held)
	_spawns_button = _add_button(bar, "FORCED SPAWNS", _toggle_forced_spawns)
	_region_button = _add_button(bar, "REGION", _region_step)
	_add_button(bar, "EDIT NPC", func(): _open_editor(CharacterEditor.Mode.EDIT))
	_add_button(bar, "SAVE", _save)
	_add_button(bar, "CLOSE", _request_close)
	bar.position = Vector2(BUTTON_BAR_MARGIN, 1080 - BUTTON_BAR_MARGIN - BUTTON_SIZE.y)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Which days and times a save would rewrite for this actor.
##
## The save edits the matched rule in place, so the blast radius is that rule's
## whole schedule -- not just the day you happen to be standing on. A rule reading
## `days: "8,12"` moves the actor on day 12 as well. This is usually what you want
## when repositioning someone, but it has to be visible before you press Enter.
func _scope_text(actor: Node) -> String:
	if actor is PokemonSpawnMarker:
		return "%s spawn point in Pokemon/Spawns/%s.json" % [str(actor.point.get("template", "?")), _map_data]
	var src: Dictionary = actor.get_meta("source", {})
	var doc := CharacterSchedule.load_map(_map_data)
	var character = doc.get(str(src.get("section", "")), {}).get(str(src.get("name", "")))
	if not (character is Dictionary):
		return "this character"
	# The position is edited where it LIVES, which is not always the rule that
	# matched: a character whose rules only say when they appear keeps one shared
	# position, so the edit lands on the defaults and moves them everywhere.
	var owner := int(src.get("at_owner", -1))
	if owner < 0:
		var rules = character.get("when")
		if rules is Array and not rules.is_empty():
			return "this character on every day (one shared position)"
		return "days %s, %s" % [str(character.get("days", "*")), str(character.get("times", "*"))]
	var rules_any = character.get("when")
	if rules_any is Array and owner < rules_any.size():
		var scope: Dictionary = rules_any[owner]
		return "when-rule #%d only — days %s, %s" % [
			owner, str(scope.get("days", "*")), str(scope.get("times", "*"))]
	return "this character"


## Tint whoever is selected so it is obvious which actor the keys are driving.
func _apply_selection_tint() -> void:
	if _tinted != null and is_instance_valid(_tinted):
		_tinted.modulate = Color.WHITE
	_tinted = _selected()
	if _tinted != null:
		_tinted.modulate = Color(1.0, 0.75, 0.35) if _grabbed else Color(0.55, 1.0, 0.65)


func _update_hud() -> void:
	_apply_selection_tint()
	if _grab_button != null:
		_grab_button.text = "DROP" if _grabbed else "GRAB"
	if _spawns_button != null:
		_spawns_button.text = "FORCED SPAWNS" if _forced_spawns else "RANDOM SPAWNS"
	if _region_button != null:
		_region_button.text = ("CORNER %d/4" % (_region_corners.size() + 1)) if _region_capture_id != "" else "REGION"
	if _label == null:
		return
	var actor := _selected()
	var lines: Array = []
	lines.append("[b]PLACEMENT MODE[/b]   %s   [%d actor(s)]   [color=aqua]noclip[/color]"
		% [_map_data, _actors.size()])
	if actor == null:
		lines.append("[color=gray]no actor selected -- Tab to cycle[/color]")
	else:
		var src: Dictionary = actor.get_meta("source", {})
		var away := 0.0
		if _player != null and is_instance_valid(_player):
			away = actor.global_position.distance_to(_player.global_position)
		lines.append("[%d/%d] [b]%s[/b]   [color=gray](%s, %dpx away)[/color]"
			% [_index + 1, _actors.size(), _name_of(actor),
			   src.get("section", "?"), roundi(away)])
		# Saving rewrites the rule that matched TODAY, in place -- it does not split
		# the day out. So a rule covering days 8,12 moves the actor on both. Spell
		# that out before the save rather than after.
		lines.append("[color=aqua]edit applies to: %s[/color]" % _scope_text(actor))
		lines.append("at [%d, %d]   pattern: %s%s"
			% [roundi(actor.position.x), roundi(actor.position.y),
			   actor.movement_pattern if "movement_pattern" in actor else "-",
			   "   [color=yellow]<< GRABBED[/color]" if _grabbed else ""])
	var dirty := _pending.size()
	var drafted := _drafts.size()
	var dirty_text := "%d unsaved move(s)" % dirty
	if drafted > 0:
		dirty_text += ", %d new/edited character(s)" % drafted
	if _pk_dirty:
		dirty_text += ", Pokémon spawns edited"
	lines.append("[color=%s]%s[/color]%s"
		% ["orange" if has_unsaved_changes() else "gray", dirty_text,
		   "   [color=aqua]CTRL: player held still, arrows nudge[/color]" if _ctrl_held else ""])
	lines.append("[color=gray]Tab select  G grab  C clone spawn point  Del delete held spawn point  P forced/random spawns  V surfacing water area (4 corners)  Ctrl+arrows nudge  R pattern  M edit selected[/color]")
	lines.append("[color=gray]Enter save  Esc close  F close and discard  (or the buttons along the bottom)[/color]")
	if _mode == Mode.NEW:
		lines.append("[color=aqua]NEW: place it, then SAVE — the create screen opens again for the next one[/color]")
	_label.text = "\n".join(lines)


func _flash(message: String) -> void:
	_update_hud()
	if _label != null:
		_label.text += "\n" + message


func has_unsaved_changes() -> bool:
	return not _pending.is_empty() or not _drafts.is_empty() or _pk_dirty


func _exit_tree() -> void:
	# The editor is parented to the map scene, not to the tool, so it would outlive
	# a close and keep swallowing every key with nothing left to hand a draft back to.
	if _editor != null and is_instance_valid(_editor):
		_editor.queue_free()
		_editor = null
	if _pokemon_editor != null and is_instance_valid(_pokemon_editor):
		_pokemon_editor.queue_free()
		_pokemon_editor = null
	# Markers and the force-everything-out preview only exist while the tool is open.
	# Leaving preview reloads the spawn FILE, so unsaved spawn edits in _pk_doc are
	# dropped and normal chance-based spawning resumes.
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.hide_markers()
		_spawner.set_preview(false)
	# Never leave the world in a tool-only state: restore the tint, the camera, the
	# grabbed actor's collision, and the player's ability to move.
	if _tinted != null and is_instance_valid(_tinted):
		_tinted.modulate = Color.WHITE
	_clear_camera()
	_restore_player_collision()
	var actor := _selected()
	if actor != null and _grab_collision.size() == 2:
		actor.collision_layer = _grab_collision[0]
		actor.collision_mask = _grab_collision[1]
		if actor.has_method("resume_movement"):
			actor.resume_movement()
	if _player != null and is_instance_valid(_player):
		_player.unlock_movement()
