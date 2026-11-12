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
##   V              surfacing / fish tank area: V to start (clears it), then V at 4 corners  REGION
##   Ctrl+arrows    nudge 1px (add Shift for 10px) -- Ctrl also holds the player still
##   R              cycle movement pattern
##   E              draw / edit the selected character's ROUTE (walk + key):  ROUTE
##                    Q  add a point where the player stands (after the picked step)
##                    X  move the picked point to where the player stands
##                    T  jump the player to the picked point
##                    Tab / Shift+Tab  pick a step     Del  delete the picked step
##                    Ctrl+arrows  nudge the picked point     E / Esc  done
##                    pauses, idle patterns, speeds, loop / ping-pong / random: the right-hand panel
##                    hold Z and walk: records the path as you walk it -- a point at every
##                    turn, a pause wherever you stand still
##                    Alt+arrows  the picked pause's idle direction (again: + glances)
##   Q, - / =       a selected WANDERER: radius (or box) to the player / smaller / bigger
##   Alt+arrows     face the selected character that way (press again: + glances)
##   C              clone the selected character (new name, everything copied) or spawn point
##   Delete         a held spawn point: delete it. A selected character: press twice to
##                  delete them entirely (map file + constants; their deck file is kept)
##   [ / ]          preview the previous / next time slot (Shift: previous / next DAY)
##   \              back to the real day and time
##   H              ghosts: where this map's characters stand at every OTHER day and time
##   L              cast list: everyone on this map by day and time, plus a CASH tab
##   N              add a random filler NPC here, for this day and time
##   Y              fast-forward: world speed x1 / x2 / x4 / x8
##   J              jump to whoever is selected; Shift+J: Tab / PREV / NEXT jump there too
##   left click     select the character / spawn point under the cursor (while drawing
##                  a route: pick the route point clicked)
##   M              edit the selected character in the character editor   EDIT NPC
##                    (its Rename to box renames them everywhere; Difficulty sets stars)
##   Enter          save every pending change to the character file       SAVE
##   Escape         close (refuses while changes are unsaved)              CLOSE
##   The right-hand panel also has MOVE TO MAP and, for an opponent, DECK TEST.
##
## Input is taken in _input() rather than _unhandled_input() so the tool gets first
## refusal on every key. Escape and Enter would otherwise reach BaseMapScene and
## open the pause menu, and Space would start a conversation with whoever is being
## dragged around.

const PATTERNS := [
	"idle_down", "idle_up", "idle_left", "idle_right", "idle_random",
	"idle_cycle", "random_wander", "route",
]

const RouteOverlay := preload("res://Scripts/Utilities/Route_Overlay.gd")
const RouteEditPanel := preload("res://Scripts/Utilities/Route_Edit_Panel.gd")
## TWEAKABLE: smallest wander radius / route speed the tool will set (world px, px/s).
const MIN_WANDER_RADIUS := 8.0
const MIN_MOVE_SPEED := 5.0
## TWEAKABLE: - / = keys change a wanderer's radius by this (Shift: the fine step).
const RADIUS_KEY_STEP := 10.0
const RADIUS_KEY_FINE := 1.0
const CastDataOps := preload("res://Scripts/Utilities/Cast_Data_Ops.gd")
const CastListScreen := preload("res://Scripts/Utilities/Cast_List_Screen.gd")
const DeckTestRunner := preload("res://Scripts/Utilities/Deck_Test_Runner.gd")
const OpponentRatings := preload("res://Scripts/Global_Scripts/Opponent_Ratings.gd")
## TWEAKABLE: Y cycles the world's speed through these.
const FAST_FORWARD_SPEEDS := [1.0, 2.0, 4.0, 8.0]
## TWEAKABLE: hold-Z route recording. A point is dropped where the walk turns by more
## than REC_TURN_DOT (cosine), at least REC_MIN_SEGMENT world px from the last one;
## standing still for REC_PAUSE_MIN seconds becomes a pause of however long you stood.
const REC_MIN_SEGMENT := 12.0
const REC_TURN_DOT := 0.9
const REC_PAUSE_MIN := 0.6
## TWEAKABLE: seconds the first Delete on a character stays armed for the second.
const DELETE_CONFIRM_SECONDS := 3.0
## TWEAKABLE: click to select picks the nearest character / spawn point / route point
## within this many world px of the cursor (x2.5 on screen at the default zoom). A
## character's clickable centre sits CLICK_CENTRE_OFFSET from its origin.
const CLICK_RADIUS := 16.0
const CLICK_CENTRE_OFFSET := Vector2(0, -4)
## TWEAKABLE: where J (and jumping while cycling) puts the player, from the character.
const JUMP_OFFSET := Vector2(0, 20)
## TWEAKABLE: ready-made routes (the panel's Template list), offsets in world px from the
## start point. Applying one replaces the route being drawn (F discards).
const ROUTE_TEMPLATES := {
	"Pace left-right (shopkeeper)": {"mode": "pingpong", "steps": [
		{"wait": 1.5, "idle": "idle_down"}, {"to": [48, 0]}, {"wait": 1.5, "idle": "idle_down"}]},
	"Guard square": {"mode": "loop", "steps": [
		{"wait": 1.0, "idle": "idle_random"}, {"to": [0, 64]}, {"wait": 1.0, "idle": "idle_random"},
		{"to": [64, 64]}, {"wait": 1.0, "idle": "idle_random"}, {"to": [64, 0]}, {"wait": 1.0, "idle": "idle_random"}]},
	"Stroll loop": {"mode": "loop", "steps": [{"to": [120, 0]}, {"to": [120, 80]}, {"to": [0, 80]}]},
	"Back and forth (long)": {"mode": "pingpong", "steps": [{"to": [160, 0]}]},
	"Window shopper": {"mode": "pingpong", "steps": [
		{"wait": 2.0, "idle": "idle_up"}, {"to": [40, 0]}, {"wait": 2.0, "idle": "idle_up"},
		{"to": [80, 0]}, {"wait": 2.0, "idle": "idle_up"}]},
	"Look-out (stand, look around)": {"mode": "loop", "steps": [{"wait": 4.0, "idle": "idle_random"}]},
	"Fidget on the spot": {"mode": "loop", "steps": [
		{"wait": 2.0, "idle": "idle_down_random"}, {"to": [8, 0]}, {"wait": 2.0, "idle": "idle_down_random"}]},
}

const HUD_FONT_SIZE := 20
const NUDGE_SMALL := 1.0
const NUDGE_LARGE := 10.0

## How the DEL debug menu opened the tool.
##   EDIT    walk round and edit what is already on the map
##   NEW     straight onto the create screen, and back to it after every save
##   FLYERS  straight onto the map's flyer tables; closes once they are saved
##   FISH    EDIT, opened with this map's first fishing spot already selected
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

## ---- routes and wanderers ----
## The character whose route is being drawn (E), or null. While set, Tab picks route
## steps instead of characters, and Q / X / T / Del act on the route.
var _route_actor: Node2D = null
## The picked step in _route_actor.route_steps; -1 = the start point (its `at`).
var _route_sel: int = -1
var _route_button: Button = null
var _overlay: Node2D = null
var _route_panel: PanelContainer = null

## ---- day / time preview, ghosts, cast list ----
## The day and time the map's cast is showing. Starts as the real one; [ ] \ change it.
var _preview_day: int = 1
var _preview_time: String = "Morning"
var _real_day: int = 1
var _real_time: String = "Morning"
## H: faded copies of where characters stand at every other day / time.
## [{name, pos (container space), sprite, label}]
var _ghosts_on: bool = false
var ghosts: Array = []
var _cast_list: Control = null
## Y: index into FAST_FORWARD_SPEEDS.
var _ff_index: int = 0
## Shift+J: Tab / PREV / NEXT take the player to each one in turn.
var _jump_on_cycle: bool = false
var _ops = null

## ---- hold-Z route recording ----
var _rec_on: bool = false
var _rec_last: Vector2 = Vector2.ZERO
var _rec_corner: Vector2 = Vector2.ZERO
var _rec_dir: Vector2 = Vector2.ZERO
var _rec_still: float = 0.0
var _rec_paused: bool = false

## ---- delete / rename ----
## The character the first Delete armed, and when (msec).
var _delete_armed: String = ""
var _delete_armed_at: int = 0
## [[old, new], ...] renames waiting for the next successful save.
var _pending_renames: Array = []

## ---- deck test panel choices ----
var deck_test_vs: String = "benchmark"
var deck_test_games: int = 30

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
	"spawn_points: id, template, at [x, y], group (points sharing a group share every rule -- clones join their source's group, and editing one edits them all), tables {Morning/Afternoon/Evening/Night: {chance (%), table [{species, percent}]}} -- an empty table spawns nothing at that time. burying/surfacing tables also have `interval` (seconds between rolls); surfacing and fish_tank have `region` [min_x, min_y, max_x, max_y] (the water: set with V, `at` is its centre). A fish_tank has NO `tables` at all -- it is not rolled and has no time of day: its `fish_table` [{species, count}] is put out in full, every count of every row, inside the region. ANY point, whatever its template, may tick `in_tank` to be drawn INSIDE the aquarium it stands in: indoors the scene tree's order is the draw order, so the Pokemon is parented one place before that tank's FishTankFront layer at relative z 0 -- which is what puts a bug, an idle Pokemon or a whole tank of fish behind the glass instead of over it. Which of the map's tanks is worked out from the point's position (the one it is inside, else the nearest), so nothing names a node. A fish_tank is always in a tank and does not carry the key; burying may set up_time; skittish sets flee (the run-away directions it is ALLOWED, any of left/right/up/down; out of those it takes whichever heads away from the player -- missing or empty means all four) and into_water (true = it stops at the first collider it runs into, leaps and sinks with a splash instead of fading out); static sets pattern (+ distance/speed/axis for patrols); walker has `route` {speed, mode: loop|pingpong|random, steps: [{to: [dx, dy], speed?} | {wait: s, idle?}]} -- offsets from `at`, drawn with E in the placement tool.",
	"fishing_spot: a spawn point that spawns NOTHING. Its `region` is a patch of water that can be fished -- how far the bobber is thrown, where a fish is landed and where it breaks free are all read off that rectangle -- and its four `tables` are what bites there, one per time of day. A cast always rolls exactly ONE fish, so there is no chance and no interval, just `table` [{species, percent}]; an empty table means nothing bites then and the bait is stolen. A map may have any number and they fish differently: a cast uses the spot whose water the player stands in, else the NEAREST one, so nothing names a node. The rectangles the player stands ON to cast are still CollisionShape2D children of a FishingAreas Area2D in the map scene (Fish_Down, Fish_Left_2, ... -- the name says which way the water is); they say only which way to face and belong to no particular spot.",
	"Table percents are weights and need not add to 100. Species keys are sprite basenames in Image_Assets/Pokemon_Sprites/Overworld_Sprites/.",
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
	_real_day = GameState.get_date()
	_real_time = GameState.get_time()
	_preview_day = _real_day
	_preview_time = _real_time
	_ops = CastDataOps.new(_write_json)
	_disable_player_collision()
	_build_hud()
	_build_buttons()
	_route_panel = RouteEditPanel.new()
	_route_panel.tool = self
	add_child(_route_panel)
	# Beside the NPC container, not in it: MapManager walks the container's children
	# as characters. top_level, so where it sits does not move what it draws.
	if _container != null and is_instance_valid(_container) and _container.get_parent() != null:
		_overlay = RouteOverlay.new()
		_overlay.tool = self
		_container.get_parent().add_child(_overlay)
	_spawner =get_tree().get_first_node_in_group(OverworldPokemonSpawner.GROUP) as OverworldPokemonSpawner
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
			_select_first_fishing_spot()


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
	# Click to select. Not over a button or the panel (they take their own clicks), and
	# never while a form or the cast list is up.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _form_open() and get_viewport().gui_get_hovered_control() == null:
			_click_select(event.position)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	# The character editor is full of text boxes and takes its own keys. This runs
	# first, so without standing down entirely, typing a G into a dialogue line would
	# also grab whoever is selected out in the world.
	if _form_open():
		return
	# Drawing a route: its own keys come first. Anything it does not use falls through
	# to the normal ones below (G carries the whole route, Enter saves, F discards).
	if _route_valid() and _route_input(event):
		get_viewport().set_input_as_handled()
		return

	# Alt+arrows: which way the selected character faces.
	if event.alt_pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_set_facing(_arrow_dir(event.keycode))
		get_viewport().set_input_as_handled()
		return

	var handled := true
	match event.keycode:
		KEY_BRACKETLEFT:
			_preview_step(-1, event.shift_pressed)
		KEY_BRACKETRIGHT:
			_preview_step(1, event.shift_pressed)
		KEY_BACKSLASH:
			_preview_reset()
		KEY_H:
			_toggle_ghosts()
		KEY_L:
			_open_cast_list()
		KEY_N:
			_add_filler()
		KEY_Y:
			_cycle_fast_forward()
		KEY_J:
			if event.shift_pressed:
				_toggle_jump_on_cycle()
			else:
				_jump_to_selected()
		KEY_E:
			_route_edit_toggle()
		KEY_Q:
			_wander_radius_to_player()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_wander_adjust_radius(-(RADIUS_KEY_FINE if event.shift_pressed else RADIUS_KEY_STEP))
		KEY_EQUAL, KEY_KP_ADD:
			_wander_adjust_radius(RADIUS_KEY_FINE if event.shift_pressed else RADIUS_KEY_STEP)
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
			_delete_key()
		KEY_P:
			_toggle_forced_spawns()
		KEY_V:
			_region_step()
		KEY_C:
			# Plain C only: Ctrl is the nudge modifier and is held while nudging.
			if event.ctrl_pressed:
				handled = false
			else:
				_clone_selected()
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
	# While a route is being drawn, PREV / NEXT pick its steps, the same as Tab.
	if _route_valid():
		_route_step_selection(step)
		return
	if _grabbed:
		_drop()
	_refresh_actors()
	if not _actors.is_empty():
		_index = wrapi(_index + step, 0, _actors.size())
		if _jump_on_cycle:
			_jump_to_selected()
		_look_at_selection()
	_update_hud()


## J: put the player right by whoever is selected (collision is off, so anywhere).
func _jump_to_selected() -> void:
	var actor := _selected()
	if actor == null or not _player_ok() or _grabbed:
		return
	_player.global_position = actor.global_position + JUMP_OFFSET
	_look_at_selection()


## Shift+J: Tab / PREV / NEXT also jump the player to each one in turn.
func _toggle_jump_on_cycle() -> void:
	_jump_on_cycle = not _jump_on_cycle
	_update_hud()
	_flash("[color=aqua]jump while cycling %s[/color]" % ("ON — Tab takes you to each one" if _jump_on_cycle else "off — Tab only looks"))


## Left click in the world: select the character or spawn point under the cursor (the
## nearest within CLICK_RADIUS). While a route is being drawn, a click on one of its
## points picks that step instead.
func _click_select(screen_pos: Vector2) -> void:
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	if _route_valid():
		var nodes: Array = _route_actor._route_nodes
		var best_node := -1
		var best_d := CLICK_RADIUS
		for i in nodes.size():
			var d := _route_global(_route_actor.route_node_position(i)).distance_to(world)
			if d <= best_d:
				best_d = d
				best_node = i
		if best_node >= 0:
			_route_select(int(nodes[best_node]["step"]))
		return
	_refresh_actors()
	var best := -1
	var best_dist := CLICK_RADIUS
	for i in _actors.size():
		var actor = _actors[i]
		if not is_instance_valid(actor):
			continue
		# Characters are drawn centred a little above their origin; markers on it.
		var centre: Vector2 = actor.global_position + (CLICK_CENTRE_OFFSET if actor is WorldObjectBase else Vector2.ZERO)
		var d := centre.distance_to(world)
		if d <= best_dist:
			best_dist = d
			best = i
	if best < 0:
		return
	if _grabbed:
		_drop()
	_index = best
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
		if marker == null or not OverworldPokemonData.REGION_TEMPLATES.has(str(marker.point.get("template", ""))):
			_flash("[color=orange]select a surfacing point, fish tank or fishing spot (Tab), then V to draw its water[/color]")
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

	_tick_record(_delta)

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
	# Where it was put down is its new home: a route's start (the whole route comes
	# along, as its points are offsets from it) or a wanderer's centre.
	if actor is WorldObjectBase:
		actor.set_home(actor.position)
	if actor.has_method("resume_movement"):
		actor.resume_movement()
	_record(actor)
	_look_at_selection()


func _nudge(keycode: int, amount: float) -> void:
	var actor := _selected()
	if actor == null:
		return
	var step := Vector2.ZERO
	match keycode:
		KEY_LEFT:  step.x = -amount
		KEY_RIGHT: step.x = amount
		KEY_UP:    step.y = -amount
		KEY_DOWN:  step.y = amount
	# A walking character is nudged by its home, not wherever it has walked to.
	if actor is WorldObjectBase:
		actor.set_home(actor.home_position() + step)
	else:
		actor.position += step
	_record(actor)
	_look_at_selection()
	_update_hud()


func _cycle_pattern() -> void:
	var actor := _selected()
	if actor == null or not (actor is WorldObjectBase):
		return
	var current: int = PATTERNS.find(actor.movement_pattern)
	var next: String = PATTERNS[wrapi(current + 1, 0, PATTERNS.size())]
	# Restarted on the new pattern, so what you see is what it will do.
	if actor is WorldObjectBase:
		actor.apply_pattern(next)
	else:
		actor.movement_pattern = next
	_record(actor)
	_update_hud()
	if next == "route" and actor is WorldObjectBase and actor.route_steps.is_empty():
		_flash("[color=aqua]route with no points yet — press E to draw it[/color]")


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
	# The home, not where a walker happens to be mid-route or mid-wander.
	entry["at"] = actor.home_position() if actor is WorldObjectBase else actor.position
	entry["at_owner"] = int(src.get("at_owner", -1))
	entry["move_owner"] = int(src.get("move_owner", -1))
	# Only write `move` if the movement actually changed: R pressed, or a route /
	# wander setting edited. Writing it unconditionally would rewrite every character
	# you merely moved. Cycling R all the way back round with nothing else touched
	# counts as no change, so the key is dropped again.
	var was: String = str(actor.get_meta("original_pattern", ""))
	var edited: bool = bool(actor.get_meta("move_edited", false))
	if actor is WorldObjectBase and (edited or (was != "" and actor.movement_pattern != was)):
		entry["move"] = actor.get_move_value()
	else:
		entry.erase("move")
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
# ROUTES AND WANDERERS
# ============================================================
# A route is drawn by walking: E on a character starts it, Q drops a point where the
# player stands, X moves the picked point there, T jumps back to a point. Pauses, idle
# patterns, speeds and loop / ping-pong / random are on the right-hand panel (Route_Edit_Panel).
# Every change goes straight onto the live character -- it walks the new route at once --
# and into _pending, so Enter writes it and F throws it away like any other edit.

func _route_valid() -> bool:
	if _route_actor != null and not is_instance_valid(_route_actor):
		_route_actor = null
	return _route_actor != null


## Anything a route can be drawn on: a character, or a walker Pokémon's spawn marker.
func _is_route_host(actor: Node) -> bool:
	return actor is WorldObjectBase or (actor is PokemonSpawnMarker and actor.is_walker())


## A route's points live in its host's PARENT space (the NPC container, or the spawner).
func _route_local(global_pos: Vector2) -> Vector2:
	return (_route_actor.get_parent() as Node2D).to_local(global_pos)


func _route_global(local_pos: Vector2) -> Vector2:
	return (_route_actor.get_parent() as Node2D).to_global(local_pos)


## A walker's route edits the working copy of the spawn file; a character's goes into
## _pending like any other move.
func _route_record() -> void:
	if _route_actor is PokemonSpawnMarker:
		_pk_dirty = true
	else:
		_route_actor.set_meta("move_edited", true)
		_record(_route_actor)


## E and the ROUTE button: start drawing the selected character's route, or finish.
## A character that is not on a route yet becomes one, starting where it stands.
func _route_edit_toggle() -> void:
	if _route_valid():
		_end_route_edit()
		return
	var actor := _selected()
	if not _is_route_host(actor):
		_flash("[color=orange]select a character or a walker Pokémon's spawn point (Tab), then E to draw its route[/color]")
		return
	if actor is WorldObjectBase and not actor.has_meta("source") and not _is_draft(actor):
		_flash("[color=orange]%s was generated at runtime — it has no file entry to give a route[/color]" % _name_of(actor))
		return
	if _grabbed:
		_drop()
	if actor is WorldObjectBase and actor.movement_pattern != "route":
		actor.apply_pattern("route")
		actor.set_meta("move_edited", true)
		_record(actor)
	_route_actor = actor
	_route_sel = actor.route_steps.size() - 1
	_update_hud()
	_flash("[color=aqua]drawing %s's route — walk somewhere and press Q to add a point, E when done[/color]" % _name_of(actor))


func _end_route_edit() -> void:
	_route_actor = null
	_route_sel = -1
	_update_hud()


## A character the editor made this session has a draft but may have no provenance yet.
func _is_draft(actor: Node) -> bool:
	var src: Dictionary = actor.get_meta("source", {})
	return _drafts.has("%s|%s" % [str(src.get("section", "")), str(src.get("name", ""))])


## Route-editing keys. Returns false for anything it leaves to the normal handler.
func _route_input(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_E, KEY_ESCAPE:
			_end_route_edit()
		KEY_TAB:
			_route_step_selection(-1 if event.shift_pressed else 1)
		KEY_Q:
			_route_add_point()
		KEY_X:
			_route_move_point()
		KEY_T:
			_route_goto_point()
		KEY_DELETE:
			_route_delete_step()
		KEY_Z:
			pass   # held: _tick_record() polls it
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if event.alt_pressed:
				_route_face_pause(_arrow_dir(event.keycode))
				return true
			if not event.ctrl_pressed:
				return false
			var amount := NUDGE_LARGE if event.shift_pressed else NUDGE_SMALL
			var step := Vector2.ZERO
			match event.keycode:
				KEY_LEFT:  step.x = -amount
				KEY_RIGHT: step.x = amount
				KEY_UP:    step.y = -amount
				KEY_DOWN:  step.y = amount
			_route_shift_point(step)
		# Keys that act on whoever is selected would act on someone else mid-route.
		KEY_R, KEY_C, KEY_V, KEY_P, KEY_M, KEY_MINUS, KEY_EQUAL, KEY_N, KEY_L, \
				KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH:
			_flash("[color=orange]finish the route first (E)[/color]")
		_:
			return false
	return true


func _route_steps_copy() -> Array:
	return (_route_actor.route_steps as Array).duplicate(true)


## Put an edited step list onto the live character and record it for the save.
func _route_apply(steps: Array, mode: String = "") -> void:
	if not _route_valid():
		return
	_route_actor.set_route(steps, mode if mode != "" else _route_actor.route_mode)
	_route_record()
	_route_sel = clampi(_route_sel, -1, steps.size() - 1)
	_update_hud()


func _route_select(index: int) -> void:
	if not _route_valid():
		return
	_route_sel = clampi(index, -1, _route_actor.route_steps.size() - 1)
	_update_hud()


## Tab / Shift+Tab: round the steps, the start point (-1) included.
func _route_step_selection(step: int) -> void:
	if not _route_valid():
		return
	var count: int = _route_actor.route_steps.size() + 1
	_route_sel = wrapi(_route_sel + 1 + step, 0, count) - 1
	_update_hud()


func _player_ok() -> bool:
	return _player != null and is_instance_valid(_player) and _container != null and is_instance_valid(_container)


## Q / + POINT HERE: a new walk point where the player stands, after the picked step.
func _route_add_point() -> void:
	if not _route_valid() or not _player_ok():
		return
	_route_insert_point(_route_local(_player.global_position).round())
	_flash("[color=lime]point added — walk on and Q for the next, + PAUSE for a stop here (or hold Z and walk)[/color]")


## A walk point at `local_pos` (route space), after the picked step, which it becomes.
func _route_insert_point(local_pos: Vector2) -> void:
	var off: Vector2 = (local_pos - (_route_actor.route_anchor as Vector2)).round()
	var steps := _route_steps_copy()
	_route_sel += 1
	steps.insert(_route_sel, {"to": [int(off.x), int(off.y)]})
	_route_apply(steps)


## A pause after the picked step, which it becomes.
func _route_insert_pause(wait: float, idle: String = "") -> void:
	var steps := _route_steps_copy()
	_route_sel += 1
	var pause := {"wait": maxf(snappedf(wait, 0.1), 0.1)}
	if idle != "":
		pause["idle"] = idle
	steps.insert(_route_sel, pause)
	_route_apply(steps)


## X / MOVE HERE: the picked point goes to where the player stands. The start point
## moves on its own -- the other points stay where they are in the world.
func _route_move_point() -> void:
	if not _route_valid() or not _player_ok():
		return
	_route_set_point(_route_local(_player.global_position).round())


## Ctrl+arrows: the picked point by a pixel (Shift: ten).
func _route_shift_point(step: Vector2) -> void:
	if not _route_valid():
		return
	_route_set_point(_route_point_position(_route_sel) + step)


## Move the point the picked step belongs to (a pause moves the point it is at).
func _route_set_point(target: Vector2) -> void:
	var steps := _route_steps_copy()
	var walk := _route_walk_index(_route_sel, steps)
	if walk < 0:
		# The start: shift every other point the opposite way so they stay put.
		var delta := target - (_route_actor.route_anchor as Vector2)
		for s in steps:
			if s is Dictionary and s.get("to") is Array:
				s["to"] = [roundi(float(s["to"][0]) - delta.x), roundi(float(s["to"][1]) - delta.y)]
		if _route_actor is PokemonSpawnMarker:
			# The marker IS the start: move it (that writes `at`) and respawn the walker there.
			_route_actor.set_route(steps, _route_actor.route_mode)
			_route_actor.position = target
			_record(_route_actor)
			_update_hud()
			return
		_route_actor.set_home(target)
		_route_apply(steps)
		return
	var off: Vector2 = target - (_route_actor.route_anchor as Vector2)
	steps[walk]["to"] = [roundi(off.x), roundi(off.y)]
	_route_apply(steps)


## T / GO TO: jump the player onto the picked point, to look at it or walk on from it.
func _route_goto_point() -> void:
	if not _route_valid() or not _player_ok():
		return
	_player.global_position = _route_global(_route_point_position(_route_sel))


## Where step `index` stands, in the container's space.
func _route_point_position(index: int) -> Vector2:
	var steps: Array = _route_actor.route_steps
	var walk := _route_walk_index(index, steps)
	var anchor: Vector2 = _route_actor.route_anchor
	if walk < 0:
		return anchor
	var to: Array = steps[walk]["to"]
	return anchor + Vector2(float(to[0]), float(to[1]))


## The walk step a step belongs to: itself, or for a pause the last walk before it.
## -1 = the start point.
func _route_walk_index(index: int, steps: Array) -> int:
	for i in range(mini(index, steps.size() - 1), -1, -1):
		if steps[i] is Dictionary and steps[i].get("to") is Array:
			return i
	return -1


func _route_delete_step() -> void:
	if not _route_valid():
		return
	if _route_sel < 0:
		_flash("[color=orange]the start point can't be deleted — move it with X, or G to carry the whole route[/color]")
		return
	var steps := _route_steps_copy()
	steps.remove_at(_route_sel)
	_route_sel -= 1
	_route_apply(steps)


## + PAUSE: a 1 second stop, keeping the facing it walked in with, after the picked step.
func _route_add_pause() -> void:
	if not _route_valid():
		return
	_route_insert_pause(1.0)


## Alt+arrows while drawing: the picked pause faces that way; again, it also glances.
## On a walk point it adds a 1 second pause facing that way.
func _route_face_pause(dir: String) -> void:
	if not _route_valid() or dir == "":
		return
	var steps := _route_steps_copy()
	var step := _route_selected_step(steps)
	if not step.has("wait"):
		_route_insert_pause(1.0, "idle_" + dir)
		return
	var current := str(step.get("idle", ""))
	step["idle"] = ("idle_%s_random" % dir) if current == "idle_" + dir else "idle_" + dir
	_route_apply(steps)


## The panel's Template list: replace the route with a ready-made one from its start.
func route_apply_template(template_name: String) -> void:
	if not _route_valid() or not ROUTE_TEMPLATES.has(template_name):
		return
	var t: Dictionary = ROUTE_TEMPLATES[template_name]
	var steps: Array = (t["steps"] as Array).duplicate(true)
	_route_sel = steps.size() - 1
	_route_apply(steps, str(t["mode"]))
	_flash("[color=lime]route set to \"%s\" — adjust it, or F to discard[/color]" % template_name)


# ── hold Z to record ──────────────────────────────────────────────────────────

## Polled every frame: while a route is being drawn and Z is held, the walk is recorded.
func _tick_record(delta: float) -> void:
	var holding := _route_valid() and not _form_open() and _player_ok() and Input.is_key_pressed(KEY_Z)
	if holding and not _rec_on:
		_rec_begin()
	elif not holding and _rec_on:
		_rec_end()
	if not _rec_on:
		return
	var pos: Vector2 = _route_local(_player.global_position).round()
	var moved := pos - _rec_last
	if moved.length() < 0.5:
		_rec_still += delta
		# Standing still: the spot is a point of its own; the pause is added, with
		# however long it lasted, once you walk on (or let go of Z).
		if _rec_still >= REC_PAUSE_MIN and not _rec_paused:
			if pos.distance_to(_rec_corner) >= REC_MIN_SEGMENT:
				_route_insert_point(pos)
				_rec_corner = pos
			_rec_paused = true
		return
	if _rec_paused:
		_route_insert_pause(_rec_still)
		_rec_paused = false
		_rec_dir = Vector2.ZERO
	_rec_still = 0.0
	var dir := moved.normalized()
	if _rec_dir != Vector2.ZERO and dir.dot(_rec_dir) < REC_TURN_DOT \
			and _rec_last.distance_to(_rec_corner) >= REC_MIN_SEGMENT:
		_route_insert_point(_rec_last)
		_rec_corner = _rec_last
	_rec_dir = dir
	_rec_last = pos


func _rec_begin() -> void:
	_rec_on = true
	var pos: Vector2 = _route_local(_player.global_position).round()
	_rec_last = pos
	_rec_dir = Vector2.ZERO
	_rec_still = 0.0
	_rec_paused = false
	# Starting away from the picked point: the walk there is the first leg.
	_rec_corner = _route_point_position(_route_sel)
	if pos.distance_to(_rec_corner) >= REC_MIN_SEGMENT:
		_route_insert_point(pos)
		_rec_corner = pos
	_flash("[color=aqua]RECORDING — walk the route; stand still for a pause; let go of Z to stop[/color]")


func _rec_end() -> void:
	_rec_on = false
	if not _route_valid() or not _player_ok():
		return
	var pos: Vector2 = _route_local(_player.global_position).round()
	if _rec_paused:
		_route_insert_pause(_rec_still)
	elif pos.distance_to(_rec_corner) >= REC_MIN_SEGMENT:
		_route_insert_point(pos)
	_rec_paused = false
	_flash("[color=lime]recorded — %d step(s) in the route now[/color]" % _route_actor.route_steps.size())


func _route_move_step(direction: int) -> void:
	if not _route_valid() or _route_sel < 0:
		return
	var steps := _route_steps_copy()
	var other := _route_sel + direction
	if other < 0 or other >= steps.size():
		return
	var held = steps[_route_sel]
	steps[_route_sel] = steps[other]
	steps[other] = held
	_route_sel = other
	_route_apply(steps)


func _route_selected_step(steps: Array) -> Dictionary:
	if _route_sel < 0 or _route_sel >= steps.size() or not (steps[_route_sel] is Dictionary):
		return {}
	return steps[_route_sel]


func _route_adjust_wait(amount: float) -> void:
	if not _route_valid():
		return
	var steps := _route_steps_copy()
	var step := _route_selected_step(steps)
	if not step.has("wait"):
		return
	step["wait"] = maxf(snappedf(float(step["wait"]) + amount, 0.1), 0.1)
	_route_apply(steps)


func _route_set_idle(idle: String) -> void:
	if not _route_valid():
		return
	var steps := _route_steps_copy()
	var step := _route_selected_step(steps)
	if not step.has("wait"):
		return
	if idle == "":
		step.erase("idle")
	else:
		step["idle"] = idle
	_route_apply(steps)


## A walk step's own speed for the leg into it; down to nothing = the route's speed.
func _route_adjust_leg_speed(amount: float) -> void:
	if not _route_valid():
		return
	var steps := _route_steps_copy()
	var step := _route_selected_step(steps)
	if not (step.get("to") is Array):
		return
	var current := float(step.get("speed", 0.0))
	if current <= 0.0:
		current = _route_actor.patrol_speed
	var next := current + amount
	if next < MIN_MOVE_SPEED or (amount < 0.0 and float(step.get("speed", 0.0)) <= 0.0):
		step.erase("speed")
	else:
		step["speed"] = snappedf(next, 1.0)
	_route_apply(steps)


func _route_toggle_mode() -> void:
	if not _route_valid():
		return
	# loop -> ping-pong -> random -> loop
	var next: String = {"loop": "pingpong", "pingpong": "random"}.get(_route_actor.route_mode, "loop")
	_route_apply(_route_steps_copy(), next)


## The walking speed of a route or a wanderer (the panel's Speed -/+).
func _adjust_speed(amount: float) -> void:
	var actor: Node = _route_actor if _route_valid() else _selected()
	if not _is_route_host(actor):
		return
	actor.patrol_speed = maxf(actor.patrol_speed + amount, MIN_MOVE_SPEED)
	if actor is PokemonSpawnMarker:
		_pk_dirty = true
	else:
		actor.set_meta("move_edited", true)
		_record(actor)
	_update_hud()


func _selected_wanderer() -> WorldObjectBase:
	var actor := _selected()
	if actor is WorldObjectBase and actor.movement_pattern == "random_wander":
		return actor
	return null


## Q / RADIUS = TO ME on a wanderer: the radius becomes the player's distance from its centre.
func _wander_radius_to_player() -> void:
	var actor := _selected_wanderer()
	if actor == null:
		_flash("[color=orange]Q: select a wanderer (random_wander) to set its radius, or E to draw a route[/color]")
		return
	if not _player_ok():
		return
	var off := _container.to_local(_player.global_position) - actor.wander_origin()
	if actor.wander_box != Vector2.ZERO:
		# A box: that corner of it goes to the player.
		_set_wander_box(actor, off.abs())
		return
	_set_wander_radius(actor, off.length())


## - / = and the panel's Radius -/+. A box grows or shrinks on both sides.
func _wander_adjust_radius(amount: float) -> void:
	var actor := _selected_wanderer()
	if actor == null:
		return
	if actor.wander_box != Vector2.ZERO:
		_set_wander_box(actor, actor.wander_box + Vector2(amount, amount))
		return
	_set_wander_radius(actor, actor.wander_radius + amount)


## The panel's SHAPE button: wander in a circle or in a box (sized from the circle).
func wander_toggle_shape() -> void:
	var actor := _selected_wanderer()
	if actor == null:
		return
	if actor.wander_box == Vector2.ZERO:
		_set_wander_box(actor, Vector2(actor.wander_radius, actor.wander_radius))
	else:
		actor.wander_box = Vector2.ZERO
		actor.set_meta("move_edited", true)
		_record(actor)
		_update_hud()


func _set_wander_box(actor: WorldObjectBase, half: Vector2) -> void:
	actor.wander_box = Vector2(maxf(roundf(half.x), MIN_WANDER_RADIUS), maxf(roundf(half.y), MIN_WANDER_RADIUS))
	actor.set_meta("move_edited", true)
	_record(actor)
	_update_hud()


func _arrow_dir(keycode: int) -> String:
	match keycode:
		KEY_LEFT: return "left"
		KEY_RIGHT: return "right"
		KEY_UP: return "up"
		KEY_DOWN: return "down"
	return ""


## Alt+arrows: the selected character stands facing that way; press the same way again
## and they also glance about (idle_<dir>_random).
func _set_facing(dir: String) -> void:
	if _route_valid():
		_route_face_pause(dir)
		return
	var actor := _selected()
	if not (actor is WorldObjectBase) or dir == "":
		_flash("[color=orange]select a character (Tab), then Alt+arrow to face them that way[/color]")
		return
	var pattern := ("idle_%s_random" % dir) if actor.movement_pattern == "idle_" + dir else "idle_" + dir
	actor.apply_pattern(pattern)
	_record(actor)
	_update_hud()
	_flash("[color=lime]%s: %s[/color]" % [_name_of(actor), pattern])


func _set_wander_radius(actor: WorldObjectBase, radius: float) -> void:
	actor.wander_radius = maxf(roundf(radius), MIN_WANDER_RADIUS)
	actor.set_meta("move_edited", true)
	_record(actor)
	_update_hud()


# ============================================================
# WHOLE CHARACTERS: clone, delete, move to map, filler
# ============================================================
# File work lives in Cast_Data_Ops.gd. Anything that rewrites files other than the
# pending save (delete, move) saves your other changes first, then rewrites, then
# respawns the cast from disk (_refresh_cast) so what you see is what is saved.

func _source_of(actor: Node) -> Dictionary:
	return actor.get_meta("source", {}) if actor != null else {}


## C and the CLONE button: a spawn point, or a whole character under a new name.
func _clone_selected() -> void:
	var actor := _selected()
	if actor is PokemonSpawnMarker:
		_clone_spawn_point()
		return
	if not (actor is WorldObjectBase) or not actor.has_meta("source"):
		_flash("[color=orange]select a character or spawn point (Tab), then C to clone it[/color]")
		return
	if _is_draft(actor):
		_flash("[color=orange]save %s first (Enter), then clone them[/color]" % _name_of(actor))
		return
	if _grabbed:
		_drop()
	var src := _source_of(actor)
	var section := str(src.get("section", "npcs"))
	var spawned_as := str(src.get("spawned_as", section))
	var name := str(src.get("name", ""))
	var new_name: String = CastDataOps.unique_name(name, _draft_names())
	var draft: Dictionary = CastDataOps.clone_draft(_map_data, section, spawned_as, name, new_name)
	if draft.is_empty():
		_flash("[color=red]%s is not in %s.json — save first?[/color]" % [name, _map_data])
		return
	var entry := _clone_entry(draft, int(src.get("rule", -1)), spawned_as)
	var at := _container.to_local(_player.global_position) if _player_ok() else actor.position
	var copy := MapManager.spawn_editor_actor(entry, spawned_as, at)
	if copy == null:
		return
	var new_src := src.duplicate(true)
	new_src["name"] = new_name
	copy.set_meta("source", new_src)
	_drafts["%s|%s" % [section, new_name]] = draft
	_refresh_actors()
	_index = _actors.find(copy)
	_record(copy)
	_grab()
	_update_hud()
	var note := "" if (draft["dropped"] as Array).is_empty() else " (left off the copy, coins are one-per-giver: %s)" % ", ".join(draft["dropped"])
	_flash("[color=lime]cloned %s as \"%s\"%s — G to put them down, Enter to save, M to change them after[/color]" % [name, new_name, note])


## The spawn entry for a clone, resolved the way the map resolves its source today.
func _clone_entry(draft: Dictionary, rule_index: int, spawned_as: String) -> Dictionary:
	var body: Dictionary = {}
	var character: Dictionary = draft["body"]
	for key in character:
		if key not in CharacterSchedule.SCHEDULE_KEYS:
			body[key] = character[key]
	var rules = character.get("when")
	if rules is Array and rule_index >= 0 and rule_index < rules.size() and rules[rule_index] is Dictionary:
		for key in rules[rule_index]:
			if key in ["days", "times"]:
				continue
			if rules[rule_index][key] == null:
				body.erase(key)
			else:
				body[key] = rules[rule_index][key]
	var entry := CharacterSchedule.to_entry(str(draft["name"]), body)
	var consts: Dictionary = draft.get("constants", {})
	for key in consts:
		if not entry.has(key):
			entry[key] = consts[key]
	return entry


## Delete and the DELETE button. A held spawn point goes at once (as before). A selected
## character needs a second press within DELETE_CONFIRM_SECONDS.
func _delete_key() -> void:
	var actor := _selected()
	if _grabbed and actor is PokemonSpawnMarker:
		_delete_held()
		return
	if not (actor is WorldObjectBase) or not actor.has_meta("source"):
		_delete_held()
		return
	var name := _name_of(actor)
	var now := Time.get_ticks_msec()
	if _delete_armed != name or now - _delete_armed_at > int(DELETE_CONFIRM_SECONDS * 1000.0):
		_delete_armed = name
		_delete_armed_at = now
		_flash("[color=orange]Delete %s ENTIRELY (map file + constants, deck kept)? Press Delete again[/color]" % name)
		return
	_delete_armed = ""
	_delete_character(actor)


func _delete_character(actor: Node2D) -> void:
	if _grabbed:
		_drop()
	var src := _source_of(actor)
	var section := str(src.get("section", "npcs"))
	var name := str(src.get("name", ""))
	var key := "%s|%s" % [section, name]
	# Never saved (a fresh clone, filler or new character): just forget it.
	if _drafts.has(key) and bool(_drafts[key].get("is_new", false)):
		_drafts.erase(key)
		for pending_key in _pending.keys():
			if str(pending_key).begins_with(key + "|"):
				_pending.erase(pending_key)
		_container.remove_child(actor)
		actor.queue_free()
		_refresh_actors()
		_update_hud()
		_flash("[color=orange]%s removed (it was never saved)[/color]" % name)
		return
	if has_unsaved_changes():
		_drafts.erase(key)
		_save()
	var result: Dictionary = _ops.delete_character(_map_data, section, name)
	if result.has("error"):
		_flash("[color=red]%s[/color]" % result["error"])
		return
	_refresh_cast()
	var notes: Array = []
	if not bool(result.get("constants_removed", false)):
		notes.append("constants kept — still on " + ", ".join(result.get("elsewhere", [])))
	var gates: Array = result.get("gates", [])
	if not gates.is_empty():
		notes.append("%d gate(s) still name them: %s" % [gates.size(), ", ".join(gates.slice(0, 4))])
		print("PlacementTool: gates still naming %s: %s" % [name, gates])
	_flash("[color=orange]%s deleted from %s.json%s[/color]" % [name, _map_data,
			"" if notes.is_empty() else " — " + "; ".join(notes)])


## The panel's MOVE TO MAP: the selected character leaves this map's file for another
## one, schedule and all. Walk there and Tab to find them to place them.
func move_selected_to_map(target_map: String) -> void:
	var actor := _selected()
	if not (actor is WorldObjectBase) or not actor.has_meta("source"):
		return
	var src := _source_of(actor)
	var section := str(src.get("section", "npcs"))
	var name := str(src.get("name", ""))
	if _drafts.has("%s|%s" % [section, name]) or has_unsaved_changes():
		_save()
	var problem: String = _ops.move_to_map(_map_data, target_map, section, name)
	if problem != "":
		_flash("[color=red]%s[/color]" % problem)
		return
	_refresh_cast()
	_flash("[color=lime]%s moved to %s — go there, open this tool and Tab to them to place them[/color]" % [name, target_map])


## N: a random filler NPC at the player, on the day and time being shown.
func _add_filler() -> void:
	if not _player_ok():
		return
	if _grabbed:
		_drop()
	var cal: Dictionary = CharacterSchedule.load_map(_map_data).get("calendar", {})
	var day := CharacterSchedule.resolve_day(cal, _preview_day)
	var draft: Dictionary = CastDataOps.filler_draft(day, _preview_time, _draft_names())
	var at := _container.to_local(_player.global_position)
	var actor := MapManager.spawn_editor_actor(draft["entry"], "npcs", at)
	if actor == null:
		return
	actor.set_meta("source", {"section": "npcs", "spawned_as": "npcs", "name": draft["name"],
			"rule": -1, "at_owner": -1, "move_owner": -1})
	_drafts["npcs|%s" % draft["name"]] = draft
	_refresh_actors()
	_index = _actors.find(actor)
	_record(actor)
	_grab()
	_update_hud()
	_flash("[color=lime]filler \"%s\" (%s) for day %d %s — G to put down, N for another, Enter to save, M to edit[/color]"
			% [draft["name"], draft["constants"]["sprite"], day, _preview_time])


## Respawn the map's cast from the files for the day / time being shown, keeping the
## selection by name. After a save this is what makes the screen match the files (and
## gives every actor fresh provenance, so a later edit lands on the right rule).
func _refresh_cast(select_name: String = "") -> void:
	if _route_valid():
		_end_route_edit()
	if _grabbed:
		_drop()
	var keep := select_name
	var current := _selected()
	if keep == "" and current is WorldObjectBase:
		keep = _name_of(current)
	var keep_marker = current if current is PokemonSpawnMarker else null
	if _tinted != null and is_instance_valid(_tinted):
		_tinted.modulate = Color.WHITE
	_tinted = null
	MapManager.debug_respawn_cast(_preview_day, _preview_time)
	_refresh_actors()
	if keep_marker != null and _actors.has(keep_marker):
		_index = _actors.find(keep_marker)
	elif keep != "":
		for i in _actors.size():
			if is_instance_valid(_actors[i]) and _name_of(_actors[i]) == keep:
				_index = i
				break
	if _ghosts_on:
		_build_ghosts()
	_look_at_selection()
	_update_hud()


# ============================================================
# DAY / TIME PREVIEW, GHOSTS, CAST LIST, FAST-FORWARD
# ============================================================

func _is_real_slot() -> bool:
	return _preview_day == _real_day and _preview_time == _real_time


## [ / ]: the previous / next time slot; with Shift, the previous / next day. Unsaved
## changes are saved first -- the cast about to be replaced is what they are on.
func _preview_step(step: int, by_day: bool) -> void:
	var times: Array = GameState.TIMES_OF_DAY
	var day := _preview_day
	var t := times.find(_preview_time)
	if by_day:
		day += step
	else:
		t += step
		if t < 0:
			t = times.size() - 1
			day -= 1
		elif t >= times.size():
			t = 0
			day += 1
	if day < 1:
		return
	preview_slot(day, str(times[clampi(t, 0, times.size() - 1)]))


## \: back to the real day and time.
func _preview_reset() -> void:
	preview_slot(_real_day, _real_time)


## Show the map's cast for `day` / `time_of_day`, selecting `select_name` if given.
func preview_slot(day: int, time_of_day: String, select_name: String = "") -> void:
	if has_unsaved_changes():
		_save()
	_preview_day = clampi(day, 1, 999)
	_preview_time = time_of_day
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.debug_time_override = "" if _is_real_slot() else _preview_time
		_spawner.set_preview(_forced_spawns, _pk_doc)
	_refresh_cast(select_name)
	_flash("[color=aqua]showing %s[/color]" % _slot_text())


func _slot_text() -> String:
	var cal: Dictionary = CharacterSchedule.load_map(_map_data).get("calendar", {})
	var looped := CharacterSchedule.resolve_day(cal, _preview_day)
	var text := "Day %d %s" % [_preview_day, _preview_time]
	if looped != _preview_day:
		text += " (the loop plays day %d here — edits change day %d)" % [looped, looped]
	if not _is_real_slot():
		text += "   [real: Day %d %s]" % [_real_day, _real_time]
	return text


## H: ghosts on / off.
func _toggle_ghosts() -> void:
	_ghosts_on = not _ghosts_on
	if _ghosts_on:
		_build_ghosts()
	else:
		ghosts = []
	_update_hud()
	_flash("[color=aqua]ghosts %s[/color]" % ("ON — faded: where they stand at other days / times" if _ghosts_on else "off"))


## Every spot a character on this map stands at, at any OTHER day / time than the one
## shown, grouped so one spot is one ghost with all its days and times on its label.
## Spots someone is standing on right now are left out. Story gates are ignored.
func _build_ghosts() -> void:
	ghosts = []
	var doc := CharacterSchedule.load_map(_map_data)
	var days := CastListScreen.days_for(doc)
	var consts := CastDataOps.read_json(CastDataOps.CONSTANTS_PATH)
	var cal: Dictionary = doc.get("calendar", {})
	var shown_day := CharacterSchedule.resolve_day(cal, _preview_day)
	var groups: Dictionary = {}
	var order: Array = []
	for d in range(1, days + 1):
		for t in GameState.TIMES_OF_DAY:
			if d == shown_day and t == _preview_time:
				continue
			var cast := CharacterSchedule.cast_for(_map_data, d, str(t))
			for kind in ["npcs", "opponents"]:
				for entry in cast.get(kind, []):
					var p = entry.get("position")
					if not (p is Dictionary):
						continue
					var name := str(entry.get("name", ""))
					var pos := Vector2(float(p["x"]), float(p["y"]))
					var key := "%s|%d|%d" % [name, roundi(pos.x), roundi(pos.y)]
					if not groups.has(key):
						var sprite := str(entry.get("sprite", consts.get(kind, {}).get(name, {}).get("sprite", "")))
						groups[key] = {"name": name, "pos": pos, "sprite": sprite, "slots": {}}
						order.append(key)
					var letter := str(t).left(1)
					var slot_days: Array = groups[key]["slots"].get(letter, [])
					slot_days.append(d)
					groups[key]["slots"][letter] = slot_days
	var live: Dictionary = {}
	for actor in _actors:
		if actor is WorldObjectBase and is_instance_valid(actor):
			var home: Vector2 = actor.home_position()
			live["%s|%d|%d" % [_name_of(actor), roundi(home.x), roundi(home.y)]] = true
	for key in order:
		if live.has(key):
			continue
		var g: Dictionary = groups[key]
		var parts: Array = []
		for letter in ["M", "A", "E", "N", "B"]:
			if g["slots"].has(letter):
				parts.append("%s %s" % [letter, _day_ranges(g["slots"][letter])])
		ghosts.append({"name": g["name"], "pos": g["pos"], "sprite": g["sprite"], "label": "  ".join(parts)})


## [1, 2, 3, 5, 7, 8] -> "d1-3,5,7-8"
static func _day_ranges(days: Array) -> String:
	var sorted := days.duplicate()
	sorted.sort()
	var parts: Array = []
	var i := 0
	while i < sorted.size():
		var j := i
		while j + 1 < sorted.size() and int(sorted[j + 1]) == int(sorted[j]) + 1:
			j += 1
		parts.append(str(sorted[i]) if j == i else "%d-%d" % [sorted[i], sorted[j]])
		i = j + 1
	return "d" + ",".join(parts)


## L: the cast list screen.
func _open_cast_list() -> void:
	if _form_open():
		return
	if _grabbed:
		_drop()
	_cast_list = CastListScreen.new()
	_cast_list.setup(_map_data)
	_cast_list.closed.connect(_close_cast_list)
	_cast_list.slot_chosen.connect(func(day: int, t: String, who: String):
		_close_cast_list()
		preview_slot(day, t, who))
	add_child(_cast_list)
	_freeze_player_for_form()


func _close_cast_list() -> void:
	if _cast_list != null and is_instance_valid(_cast_list):
		_cast_list.queue_free()
	_cast_list = null
	_thaw_player_after_form()
	_update_hud()


## Y: the world's speed, for watching long routes and wanders come round.
func _cycle_fast_forward() -> void:
	_ff_index = (_ff_index + 1) % FAST_FORWARD_SPEEDS.size()
	Engine.time_scale = FAST_FORWARD_SPEEDS[_ff_index]
	_update_hud()
	_flash("[color=aqua]world speed x%d[/color]" % roundi(Engine.time_scale))


## The panel's DECK TEST: the selected opponent's CPU and deck against the smart bot.
func run_deck_test() -> void:
	var actor := _selected()
	if not ("opponent_name" in actor) or str(actor.opponent_name) == "":
		_flash("[color=orange]select an opponent (Tab) to deck-test[/color]")
		return
	var runner = DeckTestRunner.instance()
	var problem: String = runner.test_opponent(str(actor.opponent_name), deck_test_vs, deck_test_games)
	if problem != "":
		_flash("[color=orange]%s[/color]" % problem)
		return
	if not runner.finished.is_connected(_on_deck_test_finished):
		runner.finished.connect(_on_deck_test_finished)
	_flash("[color=aqua]deck test started in the background — progress bottom-right[/color]")


func _on_deck_test_finished(_results: Dictionary) -> void:
	if is_inside_tree():
		_update_hud()


# ============================================================
# CHARACTER EDITOR
# ============================================================

## Open the creation / edit form. Nothing it produces reaches disk on its own --
## Confirm hands back a draft, which is placed in the world and held until Enter.
func _open_editor(mode: int) -> void:
	if _form_open():
		return
	var actor: Node2D = null
	# The editor respawns the character, so a route being drawn on it ends here (its
	# steps are carried over to the new node).
	if _route_valid():
		_end_route_edit()
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
		or (_pokemon_editor != null and is_instance_valid(_pokemon_editor)) \
		or (_cast_list != null and is_instance_valid(_cast_list))


# ============================================================
# POKÉMON SPAWN EDITOR
# ============================================================

## N -> POKÉMON. The character form has already freed itself; the player is still
## frozen from when it opened.
func _on_editor_pokemon_chosen() -> void:
	_editor = null
	_open_pokemon_editor({})


## The FISH TABLE button (Mode.FISH). A fishing spot is an ordinary spawn point now, so
## this is only a shortcut past Tabbing round to it: the form opens on the spot NEAREST
## the player, which is the one they walked to. A map with none is told where to make one.
func _select_first_fishing_spot() -> void:
	var spots := OverworldPokemonData.fishing_spots(_pk_doc)
	if spots.is_empty():
		_flash("[color=orange]no fishing spot on this map yet — make one with NEW NPC / OPPONENT / POKÉMON, template \"Fishing spot\"[/color]")
		return
	var spot: Dictionary = spots[0]
	if _player != null and is_instance_valid(_player):
		spot = OverworldPokemonData.nearest_fishing_spot(spots, _player.global_position)
	_rebuild_markers(str(spot.get("id", "")))
	_open_pokemon_editor(spot)


## N -> FLYER TABLES. As above, but straight onto the map's flyer tables.
func _on_editor_flyers_chosen() -> void:
	_editor = null
	_open_pokemon_editor({}, true)


## `point` is a spawn point in _pk_doc to edit, or {} for a new point / the flyers.
## `flyers` opens the form on the map's time-of-day flyer tables.
func _open_pokemon_editor(point: Dictionary, flyers: bool = false) -> void:
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
			_pk_species_settings)
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
		if OverworldPokemonData.REGION_TEMPLATES.has(str(point.get("template", ""))):
			# Surfacing points, fish tanks and fishing spots are areas of water rather
			# than spots: straight into picking their 4 corners.
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


## Flyer tables. SAVE: write the spawn file straight away and leave the form open.
## Any spawn-point edits already waiting in _pk_doc are written with it.
func _on_pokemon_editor_save_requested(draft: Dictionary) -> void:
	_merge_registry_additions(draft)
	var kind := str(draft.get("kind", "flyers"))
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
	# Fishing spots live in this file, so the next cast reads what was just written
	# rather than the spots cached when the map loaded.
	FishingData.invalidate()
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
	var was_edited := false
	var existing := _selected()
	if not bool(draft.get("is_new", true)) and existing != null and is_instance_valid(existing):
		at = existing.home_position() if existing is WorldObjectBase else existing.position
		entry["_source"] = existing.get_meta("source", {}).duplicate(true)
		if existing is WorldObjectBase:
			# Set on the entry rather than on the node afterwards, so _init_movement()
			# runs against the right movement in _ready() -- an unsaved R press, route
			# or radius is kept this way round, not re-applied to a node that has
			# already set itself up.
			entry.merge(existing.movement_entry_fields(), true)
			was_pattern = str(existing.get_meta("original_pattern", existing.movement_pattern))
			was_edited = bool(existing.get_meta("move_edited", false))
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

	# Respawn as the KIND it was edited as -- an "npcs" character whose rule made it an
	# opponent today has to come back as an opponent.
	var actor := MapManager.spawn_editor_actor(entry, str(draft.get("constants_section", section)), at)
	if actor == null:
		_flash("[color=red]could not spawn %s[/color]" % name)
		return
	# Before _refresh_actors(), which only stamps this meta on an actor that has none.
	if was_pattern != "":
		actor.set_meta("original_pattern", was_pattern)
	if was_edited:
		actor.set_meta("move_edited", true)

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
		_update_hud()
		_flash("[color=lime]%s ready — place them, then Enter to write it to %s.json[/color]" % [name, _map_data])
		return
	_look_at_selection()
	_update_hud()
	# Rename everywhere happens right after the save that writes this edit.
	var rename_to := str(draft.get("rename_to", ""))
	if rename_to != "":
		_pending_renames.append([name, rename_to])
	# An edit to someone already placed is written straight away: the editor's SAVE
	# means save. Only a character still being placed (carried with G) waits for Enter,
	# since where they end up is not decided yet. Any other unsaved moves on this map
	# go out in the same write -- _save() writes everything pending.
	if _grabbed:
		_flash("[color=lime]%s ready — drop them, then Enter to write it to %s.json[/color]" % [name, _map_data])
		return
	_save()


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
		if change.has("move"):
			# The whole movement is written where `move` already lives, so a route
			# drawn for one when-rule stays scoped to it. The live character's value
			# is complete (pattern + speed + radius or steps), so it replaces outright.
			var move_target := _owner_of(character,
					_remap(remap, int(change.get("move_owner", rule_index))))
			move_target["move"] = change["move"]
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
	var select_name := ""
	for pair in _pending_renames:
		var result: Dictionary = _ops.rename_everywhere(str(pair[0]), str(pair[1]))
		if result.has("error"):
			summary += ". RENAME FAILED: " + str(result["error"])
			continue
		select_name = str(pair[1])
		summary += ". Renamed %s -> %s in %s" % [pair[0], pair[1], ", ".join(result.get("files", []))]
		var code: Array = result.get("code_hits", [])
		if not code.is_empty():
			summary += " — scripts still say \"%s\": %s" % [pair[0], ", ".join(code)]
		print("PlacementTool: renamed %s -> %s; files %s; scripts naming the old name: %s"
				% [pair[0], pair[1], result.get("files", []), code])
	_pending_renames.clear()
	# What is on screen now comes from the files just written, so it matches them -- and
	# every actor's record of which rule it came from is fresh (a schedule edit can move
	# rules about, and a later move would otherwise land on the wrong one).
	_refresh_cast(select_name)
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
	# A clone arrives whole: its map-file body (every rule) and its constants.
	if str(draft.get("kind", "")) == "clone":
		doc[section][name] = (draft["body"] as Dictionary).duplicate(true)
		var cs := str(draft.get("constants_section", section))
		if not (constants.get(cs) is Dictionary):
			constants[cs] = {}
		constants[cs][name] = (draft.get("constants", {}) as Dictionary).duplicate(true)
		return {}
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
	# The constants block follows the kind the character was edited as, not the map-file
	# section: Psychic Brienne lives under "npcs" but her deck/music/sleeve are opponent
	# constants.
	var const_section: String = str(draft.get("constants_section", section))
	if not (constants.get(const_section) is Dictionary):
		constants[const_section] = {}
	if not (constants[const_section].get(name) is Dictionary):
		constants[const_section][name] = {}
	var body: Dictionary = constants[const_section][name]
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
	text = re.sub(text, "[$1, $2]", true)
	# Route steps one per line: {"to": [120, 0], "speed": 90} / {"wait": 1.5, "idle": "idle_left"}.
	# Only objects that START with "to" or "wait" and hold nothing nested, so nothing
	# else in the file is touched.
	var step := RegEx.new()
	step.compile(r'\{\s*\n\s*("(?:to|wait)":[^{}\n]*(?:,\s*\n\s*"[a-z_]+":[^{}\n]*)*)\s*\n\s*\}')
	var ws := RegEx.new()
	ws.compile(r',\s*\n\s*')
	var out := ""
	var last := 0
	for m in step.search_all(text):
		out += text.substr(last, m.get_start() - last)
		out += "{" + ws.sub(m.get_string(1), ", ", true) + "}"
		last = m.get_end()
	return out + text.substr(last)


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
	_add_button(bar, "CLONE", _clone_selected)
	_add_button(bar, "DELETE", _delete_key)
	_spawns_button = _add_button(bar, "FORCED SPAWNS", _toggle_forced_spawns)
	_region_button = _add_button(bar, "REGION", _region_step)
	_route_button = _add_button(bar, "ROUTE", _route_edit_toggle)
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
	if _route_button != null:
		_route_button.text = "ROUTE DONE" if _route_valid() else "ROUTE"
	if _route_panel != null and is_instance_valid(_route_panel):
		_route_panel.refresh()
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
	var view := "[color=%s]%s[/color]" % ["gray" if _is_real_slot() else "yellow", _slot_text()]
	if _ghosts_on:
		view += "   [color=aqua]ghosts on[/color]"
	if _ff_index > 0:
		view += "   [color=yellow]world x%d[/color]" % roundi(FAST_FORWARD_SPEEDS[_ff_index])
	if _jump_on_cycle:
		view += "   [color=aqua]Tab jumps[/color]"
	lines.append(view)
	if _route_valid():
		lines.append("[color=yellow]DRAWING ROUTE[/color] [color=gray]Q add point here  hold Z + walk to record  X move picked point here  T go to picked point  Tab pick step  Del delete step  Alt+arrows pause facing  Ctrl+arrows nudge point  G carry whole route  E / Esc done[/color]")
		if _rec_on:
			lines.append("[color=red]● RECORDING[/color] [color=gray]stand still for a pause, let go of Z to stop[/color]")
	lines.append("[color=gray]Tab / click select  J jump to them (Shift+J: Tab jumps)  G grab  C clone  Del delete (twice for a character)  Alt+arrows face  R pattern  E route  Q / - / = wander size  M edit  N filler NPC[/color]")
	lines.append("[color=gray][ ] time  Shift+[ ] day  \\ today  H ghosts  L cast list  Y speed  P forced/random spawns  V water area  Ctrl+arrows nudge[/color]")
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
	if _cast_list != null and is_instance_valid(_cast_list):
		_cast_list.queue_free()
		_cast_list = null
	Engine.time_scale = 1.0
	# Previewing another day / time: the real cast comes back.
	if not _is_real_slot():
		MapManager.debug_respawn_cast(_real_day, _real_time)
	# Markers and the force-everything-out preview only exist while the tool is open.
	# Leaving preview reloads the spawn FILE, so unsaved spawn edits in _pk_doc are
	# dropped and normal chance-based spawning resumes.
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.debug_time_override = ""
		_spawner.hide_markers()
		_spawner.set_preview(false)
	# The guides live in the map scene, not under this CanvasLayer.
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
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
