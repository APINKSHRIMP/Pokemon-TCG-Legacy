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

## "section|name|rule" -> { "at": Vector2, "pattern": String }
var _pending: Dictionary = {}

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

	var handled := true
	match event.keycode:
		KEY_F:
			_close()
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
	var was: String = str(actor.get_meta("original_pattern", ""))
	var changed: bool = ("movement_pattern" in actor) and was != ""
	if changed and actor.movement_pattern != was:
		entry["pattern"] = actor.movement_pattern
	_pending[key] = entry


func _close() -> void:
	if _grabbed:
		_drop()
	# F is the deliberate discard path (Escape refuses instead), but say what went
	# in the bin -- losing a move silently is how you lose it twice.
	if not _pending.is_empty():
		print("PlacementTool: closed, DISCARDING %d unsaved change(s)" % _pending.size())
	queue_free()


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
	if _pending.is_empty():
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

	var text := JSON.stringify(doc, "  ", false)
	text = _compact_pairs(text)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_flash("[color=red]cannot write %s[/color]" % path)
		return
	out.store_string(text + "\n")
	out.close()
	_pending.clear()
	CharacterSchedule.invalidate(_map_data)
	_flash("[color=lime]saved %d change(s) to %s.json[/color]" % [written, _map_data])
	print("PlacementTool: wrote %d change(s) to %s" % [written, path])


## The rule that owns a field, or the character itself when the value is inherited.
func _owner_of(character: Dictionary, owner_index: int) -> Dictionary:
	if owner_index < 0:
		return character
	var rules = character.get("when")
	if rules is Array and owner_index < rules.size() and rules[owner_index] is Dictionary:
		return rules[owner_index]
	return character


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
	lines.append("[color=%s]%d unsaved change(s)[/color]%s"
		% ["orange" if dirty > 0 else "gray", dirty,
		   "   [color=aqua]CTRL: player held still, arrows nudge[/color]" if _ctrl_held else ""])
	lines.append("[color=gray]Tab select  G grab  Ctrl+arrows nudge  R pattern  Enter save  Esc/F close[/color]")
	_label.text = "\n".join(lines)


func _flash(message: String) -> void:
	_update_hud()
	if _label != null:
		_label.text += "\n" + message


func has_unsaved_changes() -> bool:
	return not _pending.is_empty()


func _exit_tree() -> void:
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
