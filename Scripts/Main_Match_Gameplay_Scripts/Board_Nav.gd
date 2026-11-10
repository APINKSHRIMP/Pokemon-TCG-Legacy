extends Node

# ============================================================
# BOARD NAV - the match played on the keyboard or a pad
# ============================================================
# A cursor - the spinning gradient ring - that walks the board with the arrow
# keys / D-pad / left stick, where A (Space / Enter) does whatever a click on the
# thing under it would do and B (Escape / Backspace) backs out.
#
# WHAT THE CURSOR MOVES BETWEEN depends on what is on screen, worked out fresh on
# every press (_targets()):
#
#   board      your hand, the opponent's hand, both Actives, both Benches, both
#              discard piles, both prize rows, the stadium, your attack / Power /
#              Retreat rows, any Bench Power button and End Turn
#   selection  the cards of the large selection screen (the open hand, a target
#              list, a search...) plus its action and cancel buttons
#   yes / no   the two answer buttons
#   overlays   the coin call's two coins, the attack chooser's buttons and the
#              stadium detail's buttons
#
# Movement is GEOMETRIC: the next target is the nearest one in the pressed
# direction, weighting sideways distance more than forward distance. No zone keeps
# a hand-written neighbour list, so the board can change shape (any resolution,
# more bench, a stadium appearing) without this file knowing.
#
# ON A SELECTION SCREEN WHERE ONE CARD IS THE WHOLE ANSWER (the open hand, an
# attach / evolve / switch target...) moving the cursor also SELECTS that card -
# it pulses exactly as a click would, the action button says what will happen, and
# A presses it. On a pick-several screen (discards, retreat cost, reorder) moving
# only points, A toggles the card, and the confirm button is reached by moving
# down to it.
#
# When the player's turn starts the cursor lands on the hand; A opens it with the
# first card picked. X / Tab jumps to the hand, Y / Q jumps to End Turn.
#
# The ring only shows while InputDevice says the player is on the keyboard or a
# pad - a mouse player never sees it. Any key or pad press brings it back.
# ============================================================

var main: Node = null
var hand_drag: Node = null

## TWEAKABLE. Sideways distance counts this many times more than forward distance
## when choosing the next target, so "right" prefers what is level with you.
const SIDEWAYS_WEIGHT := 2.5
## TWEAKABLE. An accept this soon after the board comes back (a message closing, an
## animation ending) is ignored, so mashing Space through a run of messages cannot
## press whatever the cursor happens to be on when the last one closes.
const ACCEPT_GRACE_MS := 300

var _layer: CanvasLayer = null
## The focus frame (UIKit.add_focus_frame): ring + wash + caption.
var _ring: Control = null

## TWEAKABLE. The caption written over each whole zone while the cursor is on it.
const ZONE_NAMES := {
	"hand": "Your Hand", "opp_hand": "Opponent's Hand",
	"active": "Your Active", "opp_active": "Opponent's Active",
	"bench": "Your Bench", "opp_bench": "Opponent's Bench",
	"discard": "Your Discard", "opp_discard": "Opponent's Discard",
	"prizes": "Your Prizes", "opp_prizes": "Opponent's Prizes",
	"stadium": "Stadium",
}

# The focused target is remembered by key (a card object, a node, or a zone name),
# so it survives the target list being rebuilt between presses.
var _focus_key = null
var _mode := ""
var _last_pool: Array = []
var _was_players_turn := false
var _was_active := false
var _active_since_msec := 0


func _ready() -> void:
	_layer = CanvasLayer.new()
	# Over the board and the selection screen, under the pause menu (100) and the
	# card zoom (150). Hand_Drag's layer is 96; the cursor sits just above it.
	_layer.layer = 97
	add_child(_layer)
	UITheme.theme_changed.connect(_drop_ring)


func _drop_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null


# ── Whether the cursor exists right now ──────────────────────────────────────

## False whenever the board is not the player's to look at: a message, a coin
## flip, an animation, the opponent's turn, a preview, the log, the pause menu.
func _active() -> bool:
	if main == null or GameState.autotest != null:
		return false
	if main.game_is_over:
		return false
	if main.msgbox_container.visible or main.coin_container.visible:
		return false
	if main.animation_blocker.visible:
		return false
	# ISSUE #465: and for a moment after one, and through the turn-start draw.
	if main.nav_input_settling():
		return false
	if main.is_zoomed or main.match_log_open:
		return false
	if main.pause_menu != null and is_instance_valid(main.pause_menu):
		return false
	if main.forfeit_dialog != null and is_instance_valid(main.forfeit_dialog):
		return false
	if main.vfx_debugger_open():
		return false
	# The opponent's turn blocks the board for the mouse; the cursor follows suit -
	# except over a screen the player must answer mid-turn (a forced switch, a coin call).
	if main.opponent_blocker.visible and _mode_now() == "board":
		return false
	return true


func _mode_now() -> String:
	# Metronome & co. choosing: only the live copy rows in the action panel (main.begin_copy_pick).
	if main.copy_pick_active:
		return "copy_pick"
	if _coin_overlay() != null:
		return "coins"
	if main._stadium_overlay != null and is_instance_valid(main._stadium_overlay):
		return "stadium"
	if main.attack_buttons_container.visible:
		return "attack_chooser"
	if main.yes_no_prompt_active:
		return "yes_no"
	if main.card_selection_mode_enabled:
		return "selection"
	return "board"


func _coin_overlay() -> Node:
	var n: Node = main.get_node_or_null("coin_call_overlay")
	return n if n != null and is_instance_valid(n) and not n.is_queued_for_deletion() else null


# ── Targets ──────────────────────────────────────────────────────────────────
# Each target: {"key", "rect": Rect2, "activate": Callable, "card": card_object|null,
#               "node": Control|null}

func _targets(mode: String) -> Array:
	match mode:
		"coins":          return _coin_targets()
		"stadium":        return _button_targets(main._stadium_overlay)
		"attack_chooser": return _button_targets(main.attack_buttons_container)
		"copy_pick":      return _button_targets(main._player_action_panel)   # live rows only = the copies
		"yes_no":         return _answer_button_targets()
		"selection":      return _selection_targets()
	return _board_targets()


func _coin_targets() -> Array:
	var out: Array = []
	var overlay := _coin_overlay()
	if overlay == null:
		return out
	for coin in overlay.get_children():
		if coin is Control and coin.has_meta("nav_activate"):
			out.append({"key": coin, "rect": _rect_of(coin), "node": coin,
				"activate": coin.get_meta("nav_activate"), "card": null})
	return out


func _button_targets(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var buttons: Array = []
	_collect_buttons(root, buttons, false)
	for b in buttons:
		out.append({"key": b, "rect": _rect_of(b), "node": b, "card": null,
			"activate": _press_button.bind(b)})
	return out


func _answer_button_targets() -> Array:
	var out: Array = []
	for b in [main.action_button, main.cancel_button]:
		if b != null and b.is_visible_in_tree():
			out.append({"key": b, "rect": _rect_of(b), "node": b, "card": null,
				"activate": _press_button.bind(b)})
	return out


func _selection_targets() -> Array:
	var out: Array = []
	var cards: Array = []
	for root in [main.large_selection_container, main.small_selection_container]:
		if root != null and root.is_visible_in_tree():
			_collect_cards(root, cards)
	# 2026-11-05: only the cards the screen is OFFERING (main.shown_selection_pool) are
	# cursor stops. On a target pick (attach / evolve / Potion...) the pool is the
	# Pokémon; the Energies and tools drawn with them are decoration, and landing on one
	# selected it as the target. Pools that really offer Energies (retreat cost, Energy
	# Removal, Super Potion) still list them. If nothing on screen matches the pool
	# (a screen redrawn from another array) the old list stands, so the cursor never strands.
	var pool: Array = main.shown_selection_pool
	var offered: Array = cards.filter(func(cd): return cd.card_ref in pool)
	if not offered.is_empty():
		if offered.size() < cards.size():
			print("BOARD NAV: skipped ", cards.size() - offered.size(), " card(s) not in the selection pool")
		cards = offered
	for cd in cards:
		out.append({"key": cd.card_ref, "rect": _rect_of(cd), "node": cd,
			"card": cd.card_ref, "activate": _activate_selection_card.bind(cd.card_ref)})
	for b in [main.action_button, main.cancel_button]:
		if b != null and b.is_visible_in_tree():
			out.append({"key": b, "rect": _rect_of(b), "node": b, "card": null,
				"activate": _press_button.bind(b)})
	return out


func _board_targets() -> Array:
	var out: Array = []
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	fake_click.set_meta("nav", true)   # array_container_clicked: the cursor, not a mouse click (no Alt needed)

	# The hands. Your hand's rect is the cards themselves, not the whole bar.
	if not main.player_hand.is_empty() and main.player_hand_container.is_visible_in_tree():
		out.append({"key": "hand", "rect": _children_rect(main.player_hand_container),
			"node": main.player_hand_container, "card": null, "activate": _open_hand})
	if not main.opponent_hand.is_empty() and main.opponent_hand_container.is_visible_in_tree():
		out.append({"key": "opp_hand", "rect": _children_rect(main.opponent_hand_container),
			"node": main.opponent_hand_container, "card": null,
			"activate": main.array_container_clicked.bind(fake_click, main.opponent_hand)})

	# The Actives open their single-card view (the card and everything attached).
	for pair in [[main.player_active_pokemon, "active"], [main.opponent_active_pokemon, "opp_active"]]:
		var mon: card_object = pair[0]
		if mon == null:
			continue
		var r := Rect2()
		var card_node = main.find_card_ui_for_object(mon)
		if card_node != null and is_instance_valid(card_node) and card_node.is_visible_in_tree():
			r = _rect_of(card_node)
		else:
			var loc: Dictionary = main.get_pokemon_screen_location(mon)
			if loc.is_empty():
				continue
			r = Rect2(loc["position"], loc["size"])
		out.append({"key": pair[1], "rect": r, "node": null,
			"card": mon, "activate": main.show_pokemon_preview.bind(mon)})

	# Benches, piles and prizes: exactly what a click on them opens.
	var arrays := [
		["bench", main.player_bench_container, main.player_bench],
		["opp_bench", main.opponent_bench_container, main.opponent_bench],
		["discard", main.player_discard_icon, main.player_discard_pile],
		["opp_discard", main.opponent_discard_icon, main.opponent_discard_pile],
		["prizes", main.player_prize_container, main.player_prize_cards],
		["opp_prizes", main.opponent_prize_container, main.opponent_prize_cards],
	]
	for a in arrays:
		var node: Control = a[1]
		var pool: Array = a[2]
		if node == null or not node.is_visible_in_tree() or pool.is_empty():
			continue
		var r := _children_rect(node) if a[0] in ["bench", "opp_bench", "prizes", "opp_prizes"] else _rect_of(node)
		if r.size == Vector2.ZERO:
			continue
		out.append({"key": a[0], "rect": r, "node": node, "card": null,
			"activate": main.array_container_clicked.bind(fake_click, pool)})

	# The stadium in the header.
	var stadium: Control = main.get_node_or_null("CARD_COLLECTIONS/stadium_card")
	if stadium != null and stadium.is_visible_in_tree() and main.current_stadium_card != null:
		out.append({"key": "stadium", "rect": _rect_of(stadium), "node": stadium, "card": null,
			"activate": main._show_stadium_detail})

	# Your action rows (Powers, attacks, Retreat) and the Bench Power buttons.
	var buttons: Array = []
	if main._player_action_panel != null and is_instance_valid(main._player_action_panel):
		_collect_buttons(main._player_action_panel, buttons, true)
	_collect_buttons(main.player_bench_container, buttons, false)
	for b in buttons:
		out.append({"key": b, "rect": _rect_of(b), "node": b, "card": null,
			"activate": _press_button.bind(b)})

	if main._end_turn_btn != null and is_instance_valid(main._end_turn_btn) \
			and main._end_turn_btn.is_visible_in_tree():
		out.append({"key": "end_turn", "rect": _rect_of(main._end_turn_btn),
			"node": main._end_turn_btn, "card": null,
			"activate": _press_button.bind(main._end_turn_btn)})
	return out


func _collect_cards(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is CardDisplay:
			var cd := child as CardDisplay
			# Energies stacked behind a Pokemon in its slot ignore the mouse; they are
			# part of that Pokemon, not choices of their own.
			if cd.card_ref != null and cd.is_visible_in_tree() \
					and cd.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				out.append(cd)
		_collect_cards(child, out)


## Visible buttons under `node`. `keep_disabled` keeps a dead action row that can
## still explain itself (ISSUE #266's reason catcher) - A on it shows the reason.
func _collect_buttons(node: Node, out: Array, keep_disabled: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var b := child as BaseButton
			if b.is_visible_in_tree() and b.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				if not b.disabled or (keep_disabled and b.get_node_or_null("disabled_reason_catcher") != null):
					out.append(b)
			continue
		_collect_buttons(child, out, keep_disabled)


# ── Geometry ─────────────────────────────────────────────────────────────────

## Where a target really is on screen. A card is measured by its ART (the node can be
## taller than the picture it draws) and through its transform, so the frame matches
## the card exactly and grows and shrinks with its selection pulse.
func _rect_of(c: Control) -> Rect2:
	if c is TextureRect and (c as TextureRect).texture != null:
		return UIKit.drawn_texture_rect(c as TextureRect)
	return UIKit.transformed_rect(c, Rect2(Vector2.ZERO, c.size))


## The union of the cards under a container - a hand, a bench or a prize row is the
## cards themselves, not the bar or the empty slots around them.
func _children_rect(c: Control) -> Rect2:
	var cards: Array = []
	_collect_cards(c, cards)
	var r := Rect2()
	var any := false
	for cd in cards:
		var cr := _rect_of(cd)
		r = cr if not any else r.merge(cr)
		any = true
	if any:
		return r
	for child in c.get_children():
		if child is Control and (child as Control).is_visible_in_tree() and (child as Control).size != Vector2.ZERO:
			var cr2 := _rect_of(child)
			r = cr2 if not any else r.merge(cr2)
			any = true
	return r if any else _rect_of(c)


func _find(targets: Array, key) -> int:
	if key == null:
		return -1
	# Keys are zone names, nodes or card objects - only compare like with like
	# (GDScript refuses == between an Object and a String).
	var kind := typeof(key)
	for i in targets.size():
		var k = targets[i]["key"]
		if typeof(k) == kind and k == key:
			return i
	return -1


## The best target from `from` in direction `dir`, or -1.
func _step(targets: Array, from: int, dir: Vector2i) -> int:
	var c: Vector2 = targets[from]["rect"].get_center()
	var d := Vector2(dir)
	var best := -1
	var best_score := INF
	for i in targets.size():
		if i == from:
			continue
		var r: Rect2 = targets[i]["rect"]
		var delta: Vector2 = r.get_center() - c
		var forward: float = delta.dot(d)
		if forward <= 4.0:
			continue
		var sideways: float = absf(delta.dot(Vector2(-d.y, d.x)))
		var score: float = forward + sideways * SIDEWAYS_WEIGHT
		if score < best_score:
			best_score = score
			best = i
	return best


# ── Default focus ────────────────────────────────────────────────────────────

func _default_index(mode: String, targets: Array) -> int:
	if targets.is_empty():
		return -1
	match mode:
		"board":
			for key in ["hand", "end_turn", "active"]:
				var i := _find(targets, key)
				if i >= 0:
					return i
		"yes_no":
			var i := _find(targets, main.action_button)
			if i >= 0:
				return i
		"selection":
			# The card already chosen, else the first card (left-most of the top row).
			var sel := _find(targets, main.selected_card_for_action)
			if sel >= 0:
				return sel
			var best := -1
			for i in targets.size():
				if targets[i]["card"] == null:
					continue
				if best < 0:
					best = i
					continue
				var p: Vector2 = targets[i]["rect"].position
				var q: Vector2 = targets[best]["rect"].position
				if p.y < q.y - 20.0 or (absf(p.y - q.y) <= 20.0 and p.x < q.x):
					best = i
			if best >= 0:
				return best
	return 0


## The current focus index in `targets`, re-deriving it when the screen changed.
func _current(mode: String, targets: Array) -> int:
	var pool_changed: bool = mode == "selection" and main.shown_selection_pool != _last_pool
	if mode != _mode or pool_changed:
		_mode = mode
		_last_pool = main.shown_selection_pool if mode == "selection" else []
		_focus_key = null
		var i := _default_index(mode, targets)
		if i >= 0:
			_set_focus(targets, i, true)
		return i
	var idx := _find(targets, _focus_key)
	if idx < 0:
		idx = _default_index(mode, targets)
		if idx >= 0:
			_focus_key = targets[idx]["key"]
	return idx


func _set_focus(targets: Array, i: int, arriving: bool) -> void:
	_focus_key = targets[i]["key"]
	if _mode == "selection":
		var card: card_object = targets[i]["card"]
		if card != null:
			var node: Control = targets[i]["node"]
			if node != null and main.selection_scroller.is_ancestor_of(node):
				main.selection_scroller.ensure_control_visible(node)
			# One card is the whole answer here: pointing at it picks it.
			if _single_pick_mode() and card != main.selected_card_for_action \
					and (InputDevice.using_nav() or not arriving):
				main._handle_card_click(card)


## A selection screen where a single card is the answer and the action button acts on it.
func _single_pick_mode() -> bool:
	if not main.card_selection_mode_enabled or not main.action_button.visible:
		return false
	if main.bench_view_active or main.pokemon_preview_active:
		return false
	if main.trainer_reorder_active:
		return false
	if main.trainer_discard_selection_active:
		return main.trainer_discard_cards_needed == 1 and main.multi_select_min() >= 1
	if main.retreat_mode_active:
		return false
	return true


# ── Activation ───────────────────────────────────────────────────────────────

func _press_button(b: BaseButton) -> void:
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree():
		return
	if b.disabled:
		var catcher := b.get_node_or_null("disabled_reason_catcher")
		if catcher != null and catcher.has_meta("disabled_reason"):
			var reason := String(catcher.get_meta("disabled_reason"))
			if reason != "" and not main._disabled_reason_showing:
				main._disabled_reason_showing = true
				await main.show_message(reason.to_upper())
				main._disabled_reason_showing = false
		return
	b.pressed.emit()


func _activate_selection_card(card: card_object) -> void:
	# View-only screens: a bench view opens the single-card view; a preview does nothing.
	if main.bench_view_active:
		main._handle_card_click(card)
		return
	if main.pokemon_preview_active:
		return
	if _single_pick_mode():
		if card != main.selected_card_for_action:
			main._handle_card_click(card)
		if main.action_button.visible and not main.action_button.disabled:
			main.action_button.pressed.emit()
		else:
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
		return
	# Pick-several: toggle it.
	main._handle_card_click(card)


func _open_hand() -> void:
	if main.player_hand.is_empty():
		return
	var fake := InputEventMouseButton.new()
	fake.button_index = MOUSE_BUTTON_LEFT
	fake.pressed = true
	main.array_container_clicked(fake, main.player_hand)


# ── Input ────────────────────────────────────────────────────────────────────

## Called from the match's _input, below the preview / log / pause / forfeit /
## message-box branches. True when the event was the cursor's and is used up.
func handle_input(event: InputEvent) -> bool:
	if not _active():
		# Direction presses still belong to the board, not to Godot's GUI focus.
		return UIInput.is_nav_event(event) and not (main.pause_menu != null and is_instance_valid(main.pause_menu))

	var mode := _mode_now()
	var dir := UIInput.nav_direction(event)
	if dir != Vector2i.ZERO:
		var targets := _targets(mode)
		if targets.is_empty():
			return true
		var cur := _current(mode, targets)
		if cur < 0:
			return true
		# The first press after using the mouse only brings the ring back.
		if not _ring_showing():
			_place_ring()
			return true
		var next := _step(targets, cur, dir)
		if next >= 0:
			# ISSUE #458: a cursor MOVE is the menus' soft blip (plus_select), not the high click.
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
			_set_focus(targets, next, false)
		_place_ring()
		return true
	if UIInput.is_nav_event(event):
		return true

	# ISSUE #419: while the ring is hidden (the player was on the mouse) the cursor still sits on
	# "Your Hand" from the start of the turn - Space / Enter pressed to get through a message then
	# OPENED the hand as if it had been Alt-clicked. The first accept or jump only brings the ring
	# back, the same as the first arrow press. Yes / No keeps its own Space = YES answer.
	# 2026-11-05: V / pad R3 opens your Active's viewer, C the opponent's - straight away, with or
	# without the cursor showing (it opens a screen, it does not move or press anything).
	if UIInput.is_view_active(event) or UIInput.is_view_opp_active(event):
		if mode == "board":
			var mon: card_object = main.player_active_pokemon if UIInput.is_view_active(event) \
				else main.opponent_active_pokemon
			if mon != null:
				main.show_pokemon_preview(mon)
		return true

	if mode != "yes_no" and not _ring_showing() \
			and (UIInput.is_accept(event) or UIInput.is_hand_jump(event) or UIInput.is_end_turn_jump(event) \
				or UIInput.is_attack_jump(event)):
		print("ISSUE #419 FIX ACTIVE: first key press only shows the cursor (nothing activated)")
		if UIInput.is_hand_jump(event) and mode == "board":
			_focus_key = "hand"
			_mode = mode
		elif UIInput.is_end_turn_jump(event) and mode == "board":
			_focus_key = "end_turn"
			_mode = mode
		elif UIInput.is_attack_jump(event) and mode == "board":
			_focus_key = _attack_jump_key()
			_mode = mode
		_current(mode, _targets(mode))
		_place_ring()
		return true

	if UIInput.is_hand_jump(event):
		if mode == "board":
			_focus_key = "hand"
			_mode = mode
			_place_ring()
		return true
	if UIInput.is_end_turn_jump(event):
		if mode == "board":
			_focus_key = "end_turn"
			_mode = mode
			_place_ring()
		return true
	# F / pad RB: the cursor to your Active's first action row (attacks, Power, Retreat).
	if UIInput.is_attack_jump(event):
		if mode == "board":
			_focus_key = _attack_jump_key()
			_mode = mode
			_place_ring()
		return true

	if UIInput.is_accept(event):
		return _on_accept(mode)
	if UIInput.is_cancel(event):
		return _on_cancel(event, mode)
	return false


## Where F / pad RB puts the cursor: your Active's first usable action row (top to bottom -
## a Power, then the attacks, then Retreat), else its first row at all (A on a dead row says
## why it can't be used), else the Active itself.
func _attack_jump_key() -> Variant:
	var rows: Array = []
	if main._player_action_panel != null and is_instance_valid(main._player_action_panel):
		_collect_buttons(main._player_action_panel, rows, false)
		if rows.is_empty():
			_collect_buttons(main._player_action_panel, rows, true)
	if not rows.is_empty():
		rows.sort_custom(func(a, b): return (a as Control).global_position.y < (b as Control).global_position.y)
		return rows[0]
	return "active"


func _on_accept(mode: String) -> bool:
	if mode != "yes_no" and Time.get_ticks_msec() - _active_since_msec < ACCEPT_GRACE_MS:
		return true
	var targets := _targets(mode)
	if targets.is_empty():
		return mode != "yes_no"
	var cur := _current(mode, targets)
	if cur < 0:
		return mode != "yes_no"
	# Yes / No: accept answers YES unless the cursor is on NO (the match's own
	# yes/no branch does the YES).
	if mode == "yes_no" and targets[cur]["key"] != main.cancel_button:
		return false
	var act: Callable = targets[cur]["activate"]
	if act.is_valid():
		act.call()
	return true


## B / Escape / Backspace. Backs out of whatever is up; Escape with nothing to back
## out of is left to the match (it opens the pause menu).
func _on_cancel(event: InputEvent, mode: String) -> bool:
	match mode:
		"coins":
			return true
		"stadium":
			main._close_stadium_detail()
			return true
		"attack_chooser":
			main.hide_attack_buttons()
			return true
		"copy_pick":
			# A copy has to be chosen: B / Backspace do nothing; Escape still opens the pause menu.
			return not _is_escape(event)
		"yes_no":
			return false   # the match's yes/no branch answers NO
		"selection":
			# Bench setup's cancel button is "Done" (it starts the game) - never on a KEYBOARD back key.
			# ISSUE #472: pad B IS Done there (the user asked for it - B is "finished" on a controller).
			if main.bench_setup_phase_active:
				if event is InputEventJoypadButton and main.cancel_button.visible and not main.cancel_button.disabled:
					print("ISSUE #472 FIX ACTIVE: pad B pressed bench-setup Done")
					main.cancel_button.pressed.emit()
					return true
				return not _is_escape(event)
			if main.cancel_button.visible and not main.cancel_button.disabled:
				main.cancel_button.pressed.emit()
				return true
			return not _is_escape(event)
	if hand_drag != null and hand_drag.bar_selected != null:
		hand_drag.clear_bar_selection()
		return true
	return not _is_escape(event)


func _is_escape(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE


# ── The ring ─────────────────────────────────────────────────────────────────

func _ring_showing() -> bool:
	return _ring != null and is_instance_valid(_ring) and _ring.visible


func _place_ring() -> void:
	var mode := _mode_now()
	var targets := _targets(mode)
	var cur := _current(mode, targets)
	if cur < 0:
		_hide_ring()
		return
	var t: Dictionary = targets[cur]
	# Grow and shrink whatever is framed, exactly like a selected hand card. The
	# Actives have no node in the target (their rect is the card's), so pulse the card.
	var pulse_node = t["node"]
	if pulse_node == null and t["card"] != null:
		pulse_node = main.find_card_ui_for_object(t["card"])
	_pulse(pulse_node)
	# Re-measured after the pulse starts, so the frame rides the same scale.
	if pulse_node is Control and is_instance_valid(pulse_node):
		t["rect"] = _target_rect_now(t, pulse_node)
	if _ring == null or not is_instance_valid(_ring):
		_ring = UIKit.add_focus_frame(_layer)
	# Buttons keep their rounded corners and their own face; cards and piles get a
	# square frame, a light wash and - for a whole zone - its name over the top.
	var rounded: bool = t["node"] is BaseButton
	UIKit.place_focus_frame(_ring, t["rect"], String(ZONE_NAMES.get(t["key"], "")) if t["key"] is String else "", rounded)


func _hide_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.visible = false
	_pulse(null)


# ── The pulse ────────────────────────────────────────────────────────────────
# The same grow / shrink a selected card does (CardDisplay.set_selected): up to
# PULSE_SCALE and back, PULSE_TIME each way, looping. TWEAKABLE.
const PULSE_SCALE := 1.03
const PULSE_TIME := 0.5
var _pulse_node: Control = null
var _pulse_tween: Tween = null


## Moves the pulse onto `node` (null stops it). A card that is already SELECTED
## pulses itself, so it is left alone - two tweens on one scale would fight.
func _pulse(node) -> void:
	if node != null and not (node is Control and is_instance_valid(node)):
		node = null
	if node == _pulse_node:
		if node is CardDisplay and (node as CardDisplay).is_selected and _pulse_tween != null:
			_pulse_tween.kill()
			_pulse_tween = null
		return
	_stop_pulse()
	if node == null:
		return
	if node is CardDisplay and (node as CardDisplay).is_selected:
		_pulse_node = node
		return
	_pulse_node = node
	# A card keeps the pivot it was built with (the centre of its art); anything else
	# grows from its own centre.
	if not (node is CardDisplay):
		node.pivot_offset = node.size * 0.5
	_pulse_tween = node.create_tween().set_loops()
	_pulse_tween.tween_property(node, "scale", Vector2.ONE * PULSE_SCALE, PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(node, "scale", Vector2.ONE, PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
		if _pulse_node != null and is_instance_valid(_pulse_node):
			_pulse_node.scale = Vector2.ONE
	_pulse_node = null


## A target's rect measured now (so it includes the current pulse scale).
func _target_rect_now(t: Dictionary, node: Control) -> Rect2:
	var key = t["key"]
	if key is String and key in ["hand", "opp_hand", "bench", "opp_bench", "prizes", "opp_prizes"]:
		return _children_rect(node)
	return _rect_of(node)


func _process(_delta: float) -> void:
	if main == null:
		return
	if not main.is_zoomed:
		_preview_moved = false
	# The player's turn starting puts the cursor on the hand.
	var players_turn: bool = not main.opponents_turn_active and not main.game_is_over
	if players_turn and not _was_players_turn:
		_focus_key = "hand"
		_mode = "board"
	_was_players_turn = players_turn

	var active_now := _active()
	if active_now and not _was_active:
		_active_since_msec = Time.get_ticks_msec()
	_was_active = active_now

	# ISSUE #463: under a held preview the cursor stays where it is (preview_step moves it), so the
	# preview keeps following it even though the board itself is frozen.
	if main.is_zoomed and InputDevice.using_nav():
		return
	if not InputDevice.using_nav() or not _active():
		_hide_ring()
		return
	_drop_mouse_selection()
	_place_ring()


## ISSUE #420: the cursor and a mouse-picked card never show together. A card clicked in the bar
## is put down, and any hand card still pulsing "selected" on the open board (a pick the hand
## redraw carried over) is cleared - only the cursor's own pulse is left.
func _drop_mouse_selection() -> void:
	if hand_drag != null and hand_drag.bar_selected != null:
		print("ISSUE #420 FIX ACTIVE: cursor up - mouse-picked ", hand_drag.bar_selected.metadata.get("name", ""), " put down")
		hand_drag.clear_bar_selection()
	if _mode_now() != "board" or main.player_hand_container == null:
		return
	for child in main.player_hand_container.get_children():
		if child is CardDisplay and (child as CardDisplay).is_selected:
			print("ISSUE #420 FIX ACTIVE: stale selected hand card cleared")
			(child as CardDisplay).set_selected(false)


## ISSUE #463: arrows / d-pad / stick while a card preview is held (L1 / Shift). The cursor moves
## exactly as it would without the preview (the match's _process then swaps the preview to the card
## it lands on) - but nothing is SELECTED on the way: single-pick screens normally pick on move, and
## a preview must never change the match under it. Skips the cards' own preview-blocking gates.
var _preview_moved: bool = false

func preview_step(dir: Vector2i) -> void:
	if main == null or GameState.autotest != null or dir == Vector2i.ZERO:
		return
	var mode := _preview_mode()
	var targets := _targets(mode)
	if targets.is_empty():
		return
	var cur := _current(mode, targets)
	if cur < 0:
		return
	if not _ring_showing():
		_place_ring()
	var next := _step(targets, cur, dir)
	if next < 0:
		return
	# Hop over anything that is not a card (buttons, action rows): the preview only shows cards.
	var guard := 0
	while next >= 0 and targets[next]["card"] == null and not (targets[next]["node"] is CardDisplay) and guard < 12:
		var after := _step(targets, next, dir)
		if after < 0 or after == next:
			break
		next = after
		guard += 1
	print("ISSUE #463 FIX ACTIVE: preview cursor ", dir, " -> ", targets[next]["key"])
	_preview_moved = true
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_focus_key = targets[next]["key"]
	_place_ring()


## ISSUE #463: while a preview is up the cursor walks cards - a selection screen's own cards, else the
## whole board (a coin call / yes-no / attack chooser offers buttons, which have nothing to preview).
func _preview_mode() -> String:
	return "selection" if _mode_now() == "selection" else "board"


## The card under the cursor, for hold-to-zoom on a pad (L1 / Shift) - null when the
## cursor is not on a card or is not showing.
func focused_card_node() -> CardDisplay:
	if not _ring_showing() and not (main.is_zoomed and _preview_moved):
		return null
	var targets := _targets(_preview_mode() if main.is_zoomed else _mode_now())
	var i := _find(targets, _focus_key)
	if i < 0:
		return null
	var node = targets[i]["node"]
	if node is CardDisplay:
		return node
	var card: card_object = targets[i]["card"]
	if card != null:
		return main.find_card_ui_for_object(card) as CardDisplay
	return null
