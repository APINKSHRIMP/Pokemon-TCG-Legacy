extends Node

# ============================================================
# HAND DRAG - mouse play straight off the board
# ============================================================
# The bottom-bar hand used to be one big button: any click on it opened the large
# hand view, and every play went through that screen. On the player's own free
# turn this node takes the hand's mouse input over instead:
#
#   click          picks the card up IN PLACE (it pulses and wears the focus frame)
#   click it again plays it - so a double-click is "play now". Picking up is a
#                  mouse-only state: the first key or pad press puts the card back
#                  down and the keyboard / pad cursor (Board_Nav) takes over.
#   drag           carries a copy of the card under the mouse:
#                    Energy    dropped on one of your Pokemon -> attached to it
#                    Evolution dropped on a Pokemon it evolves from -> evolved
#                    Trainer   dropped on a Pokemon it can be played onto -> played on it
#                              (ISSUE #547); released just above the hand -> played
#                    Basic     released just above the hand (play_line_y, ISSUE #548) -> benched
#                  A drop that cannot happen flashes the card red and flies it back
#                  to its slot; a drop on nothing just flies it back.
#   drag Active onto a Bench Pokemon (or a Bench Pokemon onto the Active) retreats,
#                  asking for the Energy to discard first when there is a cost.
#   Alt + click    the old behaviour - the large hand view (the node stands aside).
#
# Every play goes through the SAME match functions the action button calls
# (handle_action_normal_card / perform_energy_attachment / handle_action_evolution
# / start_retreat), so every rule, prompt, tutorial gate, message and animation is
# the one the old flow had. The only addition on the match side is
# `play_from_rect_override`: a dropped card's flight starts where it was dropped.
#
# Outside the player's free turn (opponent's turn, any selection screen, a message
# up) the node does nothing at all, and clicks fall through to the old handlers.
# ============================================================

var main: Node = null

## TWEAKABLE. Pixels the mouse must travel with the button held before a press
## becomes a drag rather than a click.
const DRAG_START_PX := 10.0
## TWEAKABLE. How much bigger the dragged card is than its hand slot.
const DRAG_SCALE := 1.3
## TWEAKABLE. Trainers and Basics play when released ABOVE this fraction of the
## screen height (0.667 = anywhere above the bottom third, which is the hand bar).
const PLAY_LINE := 0.667
## TWEAKABLE. The red "can't go there" flash and the fly home.
const FLASH_COLOUR := Color(1.0, 0.32, 0.32)
const FLASH_TIME := 0.08          # one half-blink
const FLASH_BLINKS := 2
const RETURN_TIME := 0.22

## The card picked up in the bar (single click), or null.
var bar_selected: card_object = null
var _bar_lifted_node: Control = null
var _bar_ring: Control = null

# The press being watched: {"kind": "hand"|"board", "card", "node", "start": Vector2}
var _press: Dictionary = {}
var _dragging := false
var _floater: TextureRect = null
var _grab_offset := Vector2.ZERO
var _hover_ring: Control = null

# ── Swing ────────────────────────────────────────────────────────────────────
# The dragged card hangs from the point the mouse holds it by, and swings about
# that point as it is moved sideways: drag right and it tilts, lagging behind like
# something carried; stop and it eases back to upright. A damped spring chasing a
# target tilt set by the mouse's sideways speed. TWEAKABLE:
## Degrees of tilt per 1000 px/s of sideways mouse speed.
const SWING_DEG_PER_KPX := 9.0
## The tilt never goes past this, however fast the mouse.
const SWING_MAX_DEG := 22.0
## Spring stiffness (higher = snappier) and damping (higher = less wobble).
## Critical damping is 2 * sqrt(stiffness) = 19 here; 16 is just under it, so a
## stop settles with one soft drift past upright rather than a snap back. Keep the
## damping near that figure - well below it the card jolts when the mouse stops.
const SWING_STIFFNESS := 90.0
const SWING_DAMPING := 16.0
## How fast the measured mouse speed follows the real one, per second. Mouse events
## arrive unevenly between frames, so the raw speed flickers; this evens it out,
## and makes a stop fade the tilt away rather than drop it in one frame.
const SWING_SPEED_RATE := 9.0
var _drag_dx := 0.0          # sideways mouse travel since the last frame
var _swing_speed := 0.0      # smoothed px/s
var _swing_vel := 0.0        # radians/s
var _busy := false               # a drop is resolving (awaiting the play)

var _layer: CanvasLayer = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	# Above the board and the selection screen, below the pause menu (100).
	_layer.layer = 96
	add_child(_layer)
	# Moving from the mouse to the keyboard or a pad puts a picked-up card down, so
	# the mouse's selection and the cursor's never show at once.
	InputDevice.device_changed.connect(func(device: int):
		if device != InputDevice.MOUSE and bar_selected != null:
			clear_bar_selection())


# ── When this node is allowed to act ────────────────────────────────────────

## The player's own turn with nothing else on screen. Mirrors what the mouse can
## reach: no message, coin, blocker, overlay or preview up.
func board_free() -> bool:
	if main == null or GameState.autotest != null:
		return false
	if not main._player_can_act_now():
		return false
	if main.msgbox_container.visible or main.coin_container.visible:
		return false
	if main.animation_blocker.visible or main.opponent_blocker.visible:
		return false
	if main.is_zoomed or main.match_log_open:
		return false
	if main.pause_menu != null and is_instance_valid(main.pause_menu):
		return false
	if main.forfeit_dialog != null and is_instance_valid(main.forfeit_dialog):
		return false
	if main.attack_buttons_container.visible or main._stadium_overlay != null:
		return false
	if CardDisplay.zoom_active or CardDisplay.input_blocked:
		return false
	return true


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseMotion and not _press.is_empty():
		_on_motion(event as InputEventMouseMotion)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if UIInput.is_inert_mouse_button(mb):
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed and bar_selected != null:
			clear_bar_selection()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if mb.pressed:
		_on_press(mb)
	elif not _press.is_empty():
		get_viewport().set_input_as_handled()
		_on_release(mb)


func _on_press(mb: InputEventMouseButton) -> void:
	# ISSUE #545: Alt is read off THIS click, not polled - Input.is_key_pressed(KEY_ALT) can stay
	# "down" after an Alt-Tab eats the release, and every click then opened the large hand.
	if not board_free() or mb.alt_pressed:
		return
	var pos := mb.position
	var hand_hit := _hand_card_at(pos)
	if not hand_hit.is_empty():
		_press = {"kind": "hand", "card": hand_hit["card"], "node": hand_hit["node"], "start": pos}
		get_viewport().set_input_as_handled()
		return
	# ISSUE #545: a click on the hand bar that misses every card (the gaps, the bar's edge) used to
	# fall through to the old handler and open the large hand view. Alt + click is the way to it now.
	if _on_hand_bar(pos):
		print("ISSUE #545 FIX ACTIVE: click on the hand bar between cards - large hand not opened (Alt + click opens it)")
		if bar_selected != null:
			clear_bar_selection()
		get_viewport().set_input_as_handled()
		return
	var mon := pokemon_at(pos)
	if mon != null:
		_press = {"kind": "board", "card": mon, "node": main.find_card_ui_for_object(mon), "start": pos}
		get_viewport().set_input_as_handled()
		return
	# A click anywhere else puts a picked-up card back down.
	if bar_selected != null:
		clear_bar_selection()


func _on_motion(mm: InputEventMouseMotion) -> void:
	if not _dragging:
		if mm.position.distance_to(_press["start"]) < DRAG_START_PX:
			return
		if not board_free():
			_press = {}
			return
		_begin_drag()
	if _floater != null:
		_floater.global_position = mm.position - _grab_offset
		_drag_dx += mm.relative.x
		_update_hover(mm.position)
	get_viewport().set_input_as_handled()


func _on_release(mb: InputEventMouseButton) -> void:
	var press := _press
	_press = {}
	if _dragging:
		_dragging = false
		_clear_hover()
		_resolve_drop(press, mb.position)
		return
	# A plain click.
	if not board_free():
		return
	if press["kind"] == "hand":
		_click_hand_card(press["card"])
	elif press["card"] in main.player_bench:
		# The bench used to open its view on the press; it waits for the release now so
		# the same press can become a retreat drag.
		var fake := InputEventMouseButton.new()
		fake.button_index = MOUSE_BUTTON_LEFT
		fake.pressed = true
		main.array_container_clicked(fake, main.player_bench)


# ── Hit tests ────────────────────────────────────────────────────────────────

## The bar-hand card under `pos`: {"card", "node"} or {}. The topmost (last drawn)
## card wins where an overlapping hand stacks them.
func _hand_card_at(pos: Vector2) -> Dictionary:
	var box: Control = main.player_hand_container
	if box == null or not box.is_visible_in_tree():
		return {}
	var clip: Control = box.get_parent() as Control
	if clip is ScrollContainer and not clip.get_global_rect().has_point(pos):
		return {}
	var hit := {}
	for child in box.get_children():
		if not (child is CardDisplay):
			continue
		var cd := child as CardDisplay
		if cd.card_ref == null or not cd.is_visible_in_tree():
			continue
		if _rest_rect(cd).has_point(pos):
			hit = {"card": cd.card_ref, "node": cd}
	return hit


## ISSUE #548: a Trainer or Basic is played once it is released this far above the TOP of the hand's
## cards - just clear of the hand, not a third of the screen up (PLAY_LINE is only the fallback when
## the hand has no cards drawn to measure). TWEAKABLE: PLAY_ABOVE_HAND_PX.
const PLAY_ABOVE_HAND_PX := 6.0

func play_line_y() -> float:
	var top := INF
	var box: Control = main.player_hand_container
	if box != null and box.is_visible_in_tree():
		for child in box.get_children():
			if child is CardDisplay and (child as CardDisplay).is_visible_in_tree():
				top = minf(top, _rest_rect(child as Control).position.y)
	if top == INF:
		return UIKit.screen_h() * PLAY_LINE
	return top - PLAY_ABOVE_HAND_PX


## ISSUE #545: is `pos` on the bottom-bar hand area (its visible clip, or the hand box itself)?
func _on_hand_bar(pos: Vector2) -> bool:
	var box: Control = main.player_hand_container
	if box == null or not box.is_visible_in_tree() or main.player_hand.is_empty():
		return false
	var clip: Control = box.get_parent() as Control
	var area: Control = clip if clip is ScrollContainer else box
	return area.get_global_rect().has_point(pos)


## The player's Pokemon in play whose CARD is under `pos`, or null.
func pokemon_at(pos: Vector2) -> card_object:
	for mon in _player_pokemon():
		var r := pokemon_rect(mon)
		if r.size != Vector2.ZERO and r.has_point(pos):
			return mon
	return null


func _player_pokemon() -> Array:
	var out: Array = []
	if main.player_active_pokemon != null:
		out.append(main.player_active_pokemon)
	out.append_array(main.player_bench)
	return out


## The player's bench slot (0 .. max-1, empty or not) under `pos`, or -1. A little
## forgiving (BENCH_DROP_PAD) so a drop that just misses the slot outline still counts.
const BENCH_DROP_PAD := 12.0

func bench_slot_at(pos: Vector2) -> int:
	if not main.player_bench_container.is_visible_in_tree():
		return -1
	for i in main.get_max_bench_size():
		if _bench_slot(i).grow(BENCH_DROP_PAD).has_point(pos):
			return i
	return -1


func _bench_slot(i: int) -> Rect2:
	var d: Dictionary = main._bench_slot_rect(i, main.player_bench_container)
	return Rect2(d["position"], d["size"])


func pokemon_rect(mon: card_object) -> Rect2:
	# The card's own art when it is drawn; the board's computed slot otherwise.
	var node = main.find_card_ui_for_object(mon)
	if node != null and is_instance_valid(node) and node.is_visible_in_tree() and node is TextureRect:
		return _rest_rect(node)
	var loc: Dictionary = main.get_pokemon_screen_location(mon)
	if loc.is_empty():
		return Rect2()
	return Rect2(loc.get("position", Vector2.ZERO), loc.get("size", Vector2.ZERO))


## Where a card really is on screen: its ART (the node can be taller than the picture),
## through its transform, so the frame fits the card and pulses with it.
func _rest_rect(c: Control) -> Rect2:
	if c is TextureRect and (c as TextureRect).texture != null:
		return UIKit.drawn_texture_rect(c as TextureRect)
	return UIKit.transformed_rect(c, Rect2(Vector2.ZERO, c.size))


# ── Picking up in place ──────────────────────────────────────────────────────

func _click_hand_card(card: card_object) -> void:
	if card == bar_selected:
		# The second click of a double-click, or a deliberate click on the picked-up card.
		play_bar_selected()
		return
	select_in_bar(card)


func select_in_bar(card: card_object) -> void:
	clear_bar_selection()
	var node := _hand_node_for(card)
	if node == null:
		return
	bar_selected = card
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)
	node.set_selected(true)
	_bar_lifted_node = node
	_bar_ring = UIKit.add_focus_frame(_layer)
	UIKit.place_focus_frame(_bar_ring, _rest_rect(node))


func clear_bar_selection() -> void:
	if _bar_lifted_node != null and is_instance_valid(_bar_lifted_node):
		(_bar_lifted_node as CardDisplay).set_selected(false)
	_bar_lifted_node = null
	bar_selected = null
	if _bar_ring != null and is_instance_valid(_bar_ring):
		_bar_ring.queue_free()
	_bar_ring = null


## Space / Enter / A, or the second click: play the picked-up card exactly as the
## large hand view's action button would.
func play_bar_selected() -> void:
	var card := bar_selected
	if card == null:
		return
	var node := _hand_node_for(card)
	clear_bar_selection()
	if not board_free() or card not in main.player_hand:
		return
	if not main.hand_card_play_ready(card):
		if node != null:
			_flash_node(node)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return
	_busy = true
	await main.play_hand_card_from_board(card)
	_busy = false


func _hand_node_for(card: card_object) -> CardDisplay:
	for child in main.player_hand_container.get_children():
		if child is CardDisplay and (child as CardDisplay).card_ref == card:
			return child as CardDisplay
	return null


func _process(delta: float) -> void:
	if _dragging and _floater != null and is_instance_valid(_floater) and delta > 0.0:
		_swing(delta)
	# A picked-up card is put down the moment the board stops being the player's -
	# the hand redrawn under it, a message, the turn ending.
	if bar_selected != null:
		var gone: bool = _bar_lifted_node == null or not is_instance_valid(_bar_lifted_node) \
			or not _bar_lifted_node.is_inside_tree() or bar_selected not in main.player_hand
		if gone or not board_free():
			if gone:
				_bar_lifted_node = null
			clear_bar_selection()
		elif _bar_ring != null and is_instance_valid(_bar_ring):
			UIKit.place_focus_frame(_bar_ring, _rest_rect(_bar_lifted_node))


# ── Dragging ─────────────────────────────────────────────────────────────────

## One frame of the swing (see SWING_*). Rotation pivots on the grab point, which is
## where the mouse is, so the card turns about the cursor.
func _swing(delta: float) -> void:
	var speed: float = _drag_dx / delta
	_drag_dx = 0.0
	_swing_speed = lerpf(_swing_speed, speed, 1.0 - exp(-SWING_SPEED_RATE * delta))
	var max_rad := deg_to_rad(SWING_MAX_DEG)
	var target: float = clampf(deg_to_rad(SWING_DEG_PER_KPX) * _swing_speed / 1000.0, -max_rad, max_rad)
	_swing_vel += (target - _floater.rotation) * SWING_STIFFNESS * delta
	_swing_vel *= exp(-SWING_DAMPING * delta)
	# No clamp here: the TARGET is already capped, and clamping the angle itself
	# stopped the card dead mid-swing - a visible jolt.
	_floater.rotation += _swing_vel * delta


func _begin_drag() -> void:
	_dragging = true
	var card: card_object = _press["card"]
	if _press["kind"] == "hand" and card == bar_selected:
		clear_bar_selection()
	var node: Control = _press.get("node")
	var from: Rect2
	if _press["kind"] == "hand" and node != null and is_instance_valid(node):
		from = _rest_rect(node)
	else:
		from = pokemon_rect(card)
	var sz := from.size * (DRAG_SCALE if _press["kind"] == "hand" else 1.0)

	_floater = TextureRect.new()
	_floater.texture = main.get_card_texture(card)
	_floater.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_floater.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floater.size = sz
	_layer.add_child(_floater)
	# Held where it was grabbed, scaled about that point.
	var start: Vector2 = _press["start"]
	_grab_offset = (start - from.position) * (sz.x / maxf(from.size.x, 1.0))
	_floater.global_position = start - _grab_offset
	# It swings about the point the mouse holds it by (see _swing), and always draws
	# over the frame of the Pokemon it is hovering.
	_floater.pivot_offset = _grab_offset
	_floater.z_index = 10
	_drag_dx = 0.0
	_swing_speed = 0.0
	_swing_vel = 0.0

	if node != null and is_instance_valid(node):
		node.modulate.a = 0.3
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_select_button)


## The ring sits on whatever the dragged card would land on, if that is allowed.
func _update_hover(pos: Vector2) -> void:
	var target := _drop_target_rect(_press, pos)
	if target.size == Vector2.ZERO:
		_clear_hover()
		return
	if _hover_ring == null or not is_instance_valid(_hover_ring):
		_hover_ring = UIKit.add_focus_frame(_layer)
		_layer.move_child(_hover_ring, 0)   # under the dragged card
	UIKit.place_focus_frame(_hover_ring, target)


func _clear_hover() -> void:
	if _hover_ring != null and is_instance_valid(_hover_ring):
		_hover_ring.queue_free()
	_hover_ring = null


## The rect of the Pokemon the drop would go to, only when that drop is legal.
func _drop_target_rect(press: Dictionary, pos: Vector2) -> Rect2:
	var card: card_object = press["card"]
	# A Basic over a bench slot: frame the slot it will actually land in.
	if press["kind"] == "hand" and String(main.get_card_action(card).get("action", "")) == "SET_POKEMON":
		var slot := bench_slot_at(pos)
		if slot < 0 or main.player_bench.size() >= main.get_max_bench_size():
			return Rect2()
		return _bench_slot(mini(slot, main.player_bench.size()))
	var mon := pokemon_at(pos)
	if mon == null:
		return Rect2()
	if press["kind"] == "board":
		var into := _retreat_pick(card, mon)
		return pokemon_rect(mon) if into != null else Rect2()
	match String(main.get_card_action(card).get("action", "")):
		"ATTACH_ENERGY":
			return pokemon_rect(mon) if _energy_drop_ok(card, mon) else Rect2()
		"EVOLVE":
			return pokemon_rect(mon) if mon in main.get_valid_evolution_targets(card, false) else Rect2()
		"PLAY_TRAINER":
			return pokemon_rect(mon) if trainer_drop_ok(card, mon) else Rect2()   # ISSUE #547
	return Rect2()


# ── Trainers dropped on a Pokemon (ISSUE #547) ───────────────────────────────
# A Trainer that is played ONTO one of your Pokemon - Potion, Super Potion, Defender, PlusPower,
# every Pokemon Tool and Technical Machine, Switch, Scoop Up, Devolution Spray... - can be dropped
# straight on it: the Pokemon is framed while the card hovers, and the card's own "choose a
# Pokemon" screen is answered by the drop (main.trainer_drop_target). Dropped anywhere else above
# the hand, the card plays as before and that screen asks.

const _TRAINER_TARGET_RX := "1 of your (own )?(benched )?pok[eé]mon|attached to your own pok[eé]mon|a pok[eé]mon on your bench|attach [^.]* to your active pok[eé]mon"

## The card's rules text, lower case, minus the Supporter boilerplate ("put it next to your Active
## Pokémon") that would otherwise read as a target on every Supporter.
func _trainer_text(card: card_object) -> String:
	var text := " ".join(PackedStringArray(card.metadata.get("rules", []))).to_lower()
	return RegEx.create_from_string("put it next to your active pok[eé]mon").sub(text, "", true)

## "" when `card` doesn't target one of your own Pokemon, else "any" / "active" / "bench".
func trainer_target_kind(card: card_object) -> String:
	var subtypes: Array = card.metadata.get("subtypes", [])
	var cname: String = card.metadata.get("name", "")
	if cname == "PlusPower":
		return "active"
	if "Pokémon Tool" in subtypes or "Technical Machine" in subtypes or main.trainer_effects.is_attached_trainer(card):
		return "any"
	var text := _trainer_text(card)
	if "damage counter on 1 of your pok" in text:
		return ""   # Venture Bomb's tails - a cost, not a target to aim
	var rx := RegEx.create_from_string(_TRAINER_TARGET_RX)
	var m := rx.search(text)
	if m == null:
		return ""
	var hit := m.get_string()
	if "bench" in hit:
		return "bench"
	if "active" in hit and rx.search_all(text).size() == 1:
		return "active"
	return "any"


## Would dropping `card` on `mon` be a sensible target? Only checks what the card plainly needs
## (damage for a heal, Energy to discard, a free Tool slot, an Evolution to spray off) - the card's
## own prompt still has the final word, and shows its screen when the drop doesn't fit.
func trainer_drop_ok(card: card_object, mon: card_object) -> bool:
	if mon == null:
		return false
	var kind := trainer_target_kind(card)
	if kind == "":
		return false
	if kind == "active" and mon != main.player_active_pokemon:
		return false
	if kind == "bench" and mon not in main.player_bench:
		return false
	var text := _trainer_text(card)
	if "damage counter" in text and ("remove" in text or "heal" in text) and mon.current_hp >= mon.get_max_hp():
		return false
	if "discard" in text and "energy card attached to" in text and mon.attached_energies.is_empty():
		return false
	if "evolution card" in text and "discard" in text and mon.attached_pre_evolutions.is_empty():
		return false
	if "Pokémon Tool" in card.metadata.get("subtypes", []):
		for ac in mon.attached_cards:
			if "Pokémon Tool" in ac.metadata.get("subtypes", []):
				return false
	return true


func _energy_drop_ok(energy: card_object, target: card_object) -> bool:
	if main.player_energy_played_this_turn:
		return false
	if "Special" in energy.metadata.get("subtypes", []):
		var check: Dictionary = main.special_energy_effects.can_attach_to(energy, target)
		if not bool(check.get("allowed", true)):
			return false
	return true


## Dragging `from` onto `onto` as a retreat: returns the Pokemon that becomes Active,
## or null when the pair is not Active + one of the player's Bench.
func _retreat_pick(from: card_object, onto: card_object) -> card_object:
	var active: card_object = main.player_active_pokemon
	if from == active and onto in main.player_bench:
		return onto
	if from in main.player_bench and onto == active:
		return from
	return null


func _resolve_drop(press: Dictionary, pos: Vector2) -> void:
	var card: card_object = press["card"]
	var node: Control = press.get("node")
	if not board_free():
		_fly_home(press, false)
		return

	if press["kind"] == "board":
		var onto := pokemon_at(pos)
		if onto == null or onto == card:
			_fly_home(press, false)
			return
		var new_active := _retreat_pick(card, onto)
		if new_active == null:
			_fly_home(press, true)
			return
		var rc: Dictionary = main.can_retreat(false)
		if not bool(rc.get("can_retreat", false)):
			await _fly_home(press, true)
			await main.show_message(String(rc.get("reason", "")))
			return
		_drop_floater(node)
		_busy = true
		await main.drag_retreat(new_active)
		_busy = false
		return

	var action := String(main.get_card_action(card).get("action", ""))
	var above_line := pos.y < play_line_y()   # ISSUE #548: just above the hand
	print("ISSUE #548 FIX ACTIVE: drop at y ", int(pos.y), " vs play line ", int(play_line_y()), " -> ", "above" if above_line else "in the hand")
	match action:
		"ATTACH_ENERGY":
			var target := pokemon_at(pos)
			if target == null:
				_fly_home(press, false)
				return
			if not _energy_drop_ok(card, target):
				_fly_home(press, true)
				return
			_land_and(press, func(): return await main.drag_attach_energy(card, target))
		"EVOLVE":
			var target := pokemon_at(pos)
			if target == null:
				_fly_home(press, false)
				return
			if target not in main.get_valid_evolution_targets(card, false):
				_fly_home(press, true)
				return
			_land_and(press, func(): return await main.drag_evolve(card, target))
		"SET_POKEMON", "PLAY_TRAINER":
			# A Basic on a bench slot goes to that slot; anywhere else above the line, to the end.
			var slot := bench_slot_at(pos) if action == "SET_POKEMON" else -1
			# ISSUE #547: a Trainer dropped on a Pokemon it can be played onto counts wherever that is.
			var drop_mon: card_object = pokemon_at(pos) if action == "PLAY_TRAINER" else null
			var on_target: bool = drop_mon != null and trainer_drop_ok(card, drop_mon)
			if not above_line and slot < 0 and not on_target:
				_fly_home(press, false)
				return
			if not main.hand_card_play_ready(card):
				_fly_home(press, true)
				return
			if action == "PLAY_TRAINER":
				var err: String = main.trainer_effects.validate_trainer_can_be_played(card, false)
				if err != "":
					await _fly_home(press, true)
					await main.show_message(err)
					return
			main.bench_drop_index = slot
			if on_target:
				print("ISSUE #547 FIX ACTIVE: ", card.metadata.get("name", ""), " dropped on ", drop_mon.metadata.get("name", ""))
				main.trainer_drop_target = drop_mon
			_land_and(press, func(): return await main.play_hand_card_from_board(card))
		_:
			_fly_home(press, true)


## A legal drop: the copy under the mouse hands over to the match's own flight,
## which starts from exactly where it was dropped.
func _land_and(press: Dictionary, play: Callable) -> void:
	var card: card_object = press["card"]
	main.play_from_rect_override = {"card": card,
		"rect": {"position": _floater.global_position, "size": _floater.size}}
	_drop_floater(press.get("node"), true)
	_busy = true
	await play.call()
	_busy = false
	main.play_from_rect_override = {}
	main.bench_drop_index = -1
	main.trainer_drop_target = null   # ISSUE #547: never carried into a later play


func _drop_floater(node: Control, keep_hidden: bool = false) -> void:
	if _floater != null and is_instance_valid(_floater):
		_floater.queue_free()
	_floater = null
	if node != null and is_instance_valid(node):
		node.modulate.a = 0.0 if keep_hidden else 1.0


## The copy flies back to its slot (after a red flash when `refused`), and the
## original is shown again.
func _fly_home(press: Dictionary, refused: bool) -> void:
	var node: Control = press.get("node")
	var f := _floater
	_floater = null
	if f == null or not is_instance_valid(f):
		if node != null and is_instance_valid(node):
			node.modulate.a = 1.0
		return
	var home: Rect2
	if press["kind"] == "hand" and node != null and is_instance_valid(node):
		home = _rest_rect(node)
	else:
		home = pokemon_rect(press["card"])
	var t := f.create_tween()
	if refused:
		for i in FLASH_BLINKS:
			t.tween_property(f, "modulate", FLASH_COLOUR, FLASH_TIME)
			t.tween_property(f, "modulate", Color.WHITE, FLASH_TIME)
	t.tween_property(f, "global_position", home.position, RETURN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(f, "size", home.size, RETURN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(f, "rotation", 0.0, RETURN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	if is_instance_valid(f):
		f.queue_free()
	if node != null and is_instance_valid(node):
		node.modulate.a = 1.0


## The same red flash on a card that is NOT being dragged (Enter / double-click on a
## card that cannot be played right now).
func _flash_node(node: Control) -> void:
	var t := node.create_tween()
	for i in FLASH_BLINKS:
		t.tween_property(node, "modulate", FLASH_COLOUR, FLASH_TIME)
		t.tween_property(node, "modulate", Color.WHITE, FLASH_TIME)
