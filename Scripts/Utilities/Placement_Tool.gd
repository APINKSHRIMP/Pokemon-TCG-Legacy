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
##   F              close the tool
##   Tab / Shift+Tab   select next / previous actor (camera pans to them)
##   G              grab or drop the selected actor
##   Ctrl+arrows    nudge 1px (add Shift for 10px) -- Ctrl also holds the player still
##   R              cycle movement pattern
##   N              create a new NPC or opponent (opens the character editor)
##   M              edit the selected character in the character editor
##   Enter          save every pending change to the character file
##   Escape         close (refuses while changes are unsaved)
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

var _map_data: String = ""
var _container: Node2D = null
var _player: Node2D = null

var _actors: Array = []
var _index: int = -1
var _grabbed: bool = false
var _ctrl_held: bool = false

const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"

## "section|name|rule" -> { "at": Vector2, "pattern": String }
var _pending: Dictionary = {}

## "section|name" -> the draft dictionary the character editor built. Held here
## rather than written on Confirm so F still discards a mistake cleanly, and so a
## new character is placed before it is committed to a file.
var _drafts: Dictionary = {}

var _editor: CharacterEditor = null

var _panel: PanelContainer = null
var _label: RichTextLabel = null
var _tinted: Node2D = null
## collision_layer / collision_mask of the grabbed actor, restored when dropped.
var _grab_collision: Array = []
## Same for the player, restored when the tool closes.
var _player_collision: Array = []


func setup(map_data: String, container: Node2D, player: Node2D) -> void:
	_map_data = map_data
	_container = container
	_player = player
	layer = 128
	_disable_player_collision()
	_build_hud()
	_refresh_actors()
	if _actors.size() > 0:
		_index = 0
	_look_at_selection()
	_update_hud()


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
	if _editor != null and is_instance_valid(_editor):
		return

	var handled := true
	match event.keycode:
		KEY_F:
			_close()
		KEY_N:
			_open_editor(CharacterEditor.Mode.NEW)
		KEY_M:
			_open_editor(CharacterEditor.Mode.EDIT)
		KEY_ESCAPE:
			if has_unsaved_changes():
				_flash("[color=orange]unsaved changes — Enter to save, F to discard and close[/color]")
			else:
				_close()
		KEY_TAB:
			if _grabbed:
				_drop()
			_refresh_actors()
			if not _actors.is_empty():
				_index = wrapi(_index + (-1 if event.shift_pressed else 1), 0, _actors.size())
				_look_at_selection()
			_update_hud()
		KEY_G:
			if _grabbed:
				_drop()
			else:
				_grab()
			_update_hud()
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


func _process(_delta: float) -> void:
	# Ctrl is polled, not event-driven, so it would still register through the form --
	# a Ctrl+C in a dialogue box would lock and unlock the player behind it.
	if _editor != null and is_instance_valid(_editor):
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
	if not _pending.is_empty() or not _drafts.is_empty():
		print("PlacementTool: closed, DISCARDING %d move(s) and %d character draft(s)"
			% [_pending.size(), _drafts.size()])
	queue_free()


# ============================================================
# CHARACTER EDITOR
# ============================================================

## Open the creation / edit form. Nothing it produces reaches disk on its own --
## Confirm hands back a draft, which is placed in the world and held until Enter.
func _open_editor(mode: int) -> void:
	if _editor != null and is_instance_valid(_editor):
		return
	var actor: Node2D = null
	if mode == CharacterEditor.Mode.EDIT:
		actor = _selected()
		if actor == null:
			_flash("[color=orange]nothing selected — Tab to pick a character, then M[/color]")
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
	_editor.setup(_map_data, mode, actor, _draft_names(), _draft_coins())


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
	_update_hud()


func _on_editor_confirmed(draft: Dictionary) -> void:
	_editor = null
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
	if _pending.is_empty() and _drafts.is_empty():
		_flash("[color=orange]nothing to save — move an actor first[/color]")
		print("PlacementTool: save requested with no pending changes")
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
			_apply_draft(doc, constants, _drafts[key])
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
		# Write each field where it currently lives. A character whose rules only
		# say WHEN they appear keeps one shared position, so moving them moves them
		# everywhere; a rule that genuinely overrides the position keeps its override
		# scoped to those days.
		var at_target := _owner_of(character, int(change.get("at_owner", rule_index)))
		at_target["at"] = [roundi(at.x), roundi(at.y)]
		if change.has("pattern"):
			var move_target := _owner_of(character, int(change.get("move_owner", rule_index)))
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
	_flash("[color=lime]%s to %s.json[/color]" % [summary, _map_data])
	print("PlacementTool: %s -> %s" % [summary, path])


## Merge one editor draft into the two documents.
##
## Fields land wherever the draft said they should: the character's defaults, the
## `when` rule that produced the actor today, or the constants file. A new key is
## APPENDED to its section rather than inserted alphabetically -- the `opponents`
## section is sorted but `npcs` is not, so re-sorting would rewrite the whole file
## and bury the one real change in the diff.
func _apply_draft(doc: Dictionary, constants: Dictionary, draft: Dictionary) -> void:
	var section: String = str(draft.get("section", "npcs"))
	var name: String = str(draft.get("name", ""))
	if name == "":
		return

	if not (doc.get(section) is Dictionary):
		doc[section] = {}
	if not (doc[section].get(name) is Dictionary):
		doc[section][name] = {}
	var character: Dictionary = doc[section][name]

	for field in draft.get("character", {}):
		character[field] = draft["character"][field]

	var rule_fields: Dictionary = draft.get("rule", {})
	if not rule_fields.is_empty():
		var rule_index: int = int(draft.get("rule_index", -1))
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
				% [int(draft.get("rule_index", -1)), section, name])
			for field in rule_fields:
				character[field] = rule_fields[field]

	var constant_fields: Dictionary = draft.get("constants", {})
	var removals: Array = draft.get("remove", [])
	if constant_fields.is_empty() and removals.is_empty():
		return
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
		var index: int = int(draft.get("rule_index", -1))
		if rule_list is Array and index >= 0 and index < rule_list.size() \
				and rule_list[index] is Dictionary:
			rule_list[index].erase(field)


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


## Which days and times a save would rewrite for this actor.
##
## The save edits the matched rule in place, so the blast radius is that rule's
## whole schedule -- not just the day you happen to be standing on. A rule reading
## `days: "8,12"` moves the actor on day 12 as well. This is usually what you want
## when repositioning someone, but it has to be visible before you press Enter.
func _scope_text(actor: Node) -> String:
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
	lines.append("[color=%s]%s[/color]%s"
		% ["orange" if dirty > 0 or drafted > 0 else "gray", dirty_text,
		   "   [color=aqua]CTRL: player held still, arrows nudge[/color]" if _ctrl_held else ""])
	lines.append("[color=gray]Tab select  G grab  Ctrl+arrows nudge  R pattern[/color]")
	lines.append("[color=gray]N new character  M edit selected  Enter save  Esc/F close[/color]")
	_label.text = "\n".join(lines)


func _flash(message: String) -> void:
	_update_hud()
	if _label != null:
		_label.text += "\n" + message


func has_unsaved_changes() -> bool:
	return not _pending.is_empty() or not _drafts.is_empty()


func _exit_tree() -> void:
	# The editor is parented to the map scene, not to the tool, so it would outlive
	# a close and keep swallowing every key with nothing left to hand a draft back to.
	if _editor != null and is_instance_valid(_editor):
		_editor.queue_free()
		_editor = null
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
