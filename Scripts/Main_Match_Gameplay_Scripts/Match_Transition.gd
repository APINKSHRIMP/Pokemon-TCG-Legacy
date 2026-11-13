class_name MatchTransition
extends CanvasLayer

# ============================================================
# MATCH TRANSITION - one unbroken flow from "Yes" to the opening hand
# ============================================================
# Replaces the old Match_Start_Intro scene (still on disk, commented out). Instead
# of cutting overworld -> VS screen -> match, this overlay sits on the tree ROOT,
# above every scene, and plays the whole sequence on top of whatever is there. The
# match scene is loaded UNDERNEATH it partway through; its background is the exact
# same picture (MatchBackdrop), so when the overlay frees itself the only thing that
# changes is that the setup screen's words and buttons fade in.
#
# THE SEQUENCE (full version, from the overworld)
#    1-2  screenshot the overworld; zoom in on the player with a growing radial blur,
#         soft blur and darkening (ZOOM_TIME)
#    3    the VS badge grows out of nothing in the exact centre of the screen; a
#         gradient line shoots out of each side toward the top-right and bottom-left
#         corners, stopping short of them. The stripes start fading in here, slowly.
#    4    trainers fly + fade in from their sides, names from above / below. The
#         player's column sits up and left, the opponent's down and right, clear of
#         the lines.
#    5    hold (HOLD) - the match scene is loaded underneath during this beat
#    6    the lines wipe away from the centre outward, the badge shrinks to nothing,
#         trainers and names leave the way they came (deck names stay); each deck
#         flies in from where its trainer came from
#    7-8  the decks are 3D stacks of each player's sleeve, and shuffle hard (SHUFFLE_TIME)
#    9    the opponent's deck and deck name leave
#    10   the opening hand is dealt RIGHT TO LEFT off the top of the player's deck,
#         each card flattening as it flies onto the exact spot the setup screen shows it
#    11   the deck and deck name leave from the 4th card on; every card flips over
#    12   hand-over: the overlay frees itself and the setup screen's text fades in
#   (13   the prize draw is the match's own job - Main_Match_Core._play_prize_draw)
#
# OTHER ENTRY POINTS
#   start_vs()    - no overworld to zoom from (a story retry from the outro): starts at
#                   the VS badge, over the saved backdrop
#   start_decks() - the next round of a best-of-three: starts with the two decks
#
# return_to_scene() is the way OUT of a match: the outro (stripes and all) is covered
# fast by the screenshot, the map loads underneath, and the screenshot cross-fades
# into the LIVE overworld - blurred and zoomed the same way - while it un-zooms and
# comes back into focus, all at once. A time-of-day change fades in on the way.
#
# Options "Play Match Intro / Outro Animation? = skip" and Reduce motion both skip
# everything: the backdrop is still captured, and the setup screen appears directly.
# A click / Space / Enter mid-sequence skips to the setup screen the same way.
#
# Every timing goes through _t(): the Animation speed preset, then PACE on top.
# ============================================================

const MATCH_SCENE := "res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn"
const BATTLE_SPRITE_DIR := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"
const DEFAULT_SLEEVE := "res://Image_Assets/Sleeves/1_Default_English.png"

enum Mode { OVERWORLD, VS, DECKS, RETURN }

# -- TWEAKABLE: overall pace ---------------------------------------------------
## Multiplies EVERY duration below (after the Animation speed preset). 0.9 = the
## 2026-11-05 "a further 10% quicker" pass. Lower = faster.
const PACE           : float = 0.72   # 2026-11-05: 0.9 -> 0.72 (a further ~20% off the intro)

# -- TWEAKABLE: timings (seconds, scaled by the Animation speed preset and PACE) -
const ZOOM_TIME      : float = 0.5    # step 1-2: zoom, blur and darken (was 1.5)
const STRIPES_FADE   : float = 2.0    # stripes fade in, starting with the VS badge
const COVER_FADE     : float = 0.3    # start_vs / start_decks: backdrop fades over the outro / bo3 screen
const BADGE_GROW     : float = 0.45   # step 3: the VS badge growing from nothing
const LINE_SHOOT     : float = 0.35   # each line shooting out toward its corner
const LINE_START     : float = 0.5    # ...starting this share of the way through the badge growing
const TRAINER_IN     : float = 0.3    # step 4: sprites and names flying in (was 0.6)
const NAME_DELAY     : float = 0.05
const HOLD           : float = 0.75   # step 5: everything on screen (was 1.5)
const LINE_WIPE      : float = 0.3    # step 6: lines wiped away, centre outward
const BADGE_SHRINK   : float = 0.3
const TRAINER_OUT    : float = 0.35
const DECK_IN        : float = 0.45
const DECK_IN_DELAY  : float = 0.08
const SHUFFLE_TIME   : float = 0.6    # step 8 (was 0.75 with 5 cuts)
const SHUFFLE_CYCLES : int   = 4      # cuts in that time - 0.15s each (one fewer than before)
const OPP_DECK_OUT   : float = 0.35   # step 9
const DEAL_FLIGHT    : float = 0.42   # step 10: one card, deck -> its place in the row
const DEAL_STAGGER   : float = 0.05   # was 0.1
const DECK_OUT       : float = 0.35   # step 11: the player's deck leaving...
const DECK_OUT_AT    : int   = 4      # ...as this card (1st, 2nd...) is dealt
const FLIP_BEAT      : float = 0.05   # pause between the last card landing and the flips (was 0.1)
const FLIP_TIME      : float = 0.26   # one card's full flip
const FLIP_STAGGER   : float = 0.04
const UI_FADE        : float = 0.22   # step 12: setup screen header / hint / buttons
const DECK_LABEL_RISE: float = 0.25   # deck names moving up to sit under their decks
const SKIP_FADE      : float = 0.25   # click-to-skip and the Options skip
const SKIP_GUARD     : float = 0.4    # a click this soon after "Yes" is not a skip (never scaled)
const RETURN_COVER   : float = 0.18   # outro -> map: outro content and its stripes vanish (fast)
const RETURN_COLOUR  : float = 0.5    # outro -> map: old screenshot cross-fades into the live map (was 1.3)...
const RETURN_UNZOOM  : float = 0.5    # ...WHILE the live map un-zooms and de-blurs (same time, was 0.6 after it)

# -- TWEAKABLE: distances and sizes (screen px) ---------------------------------
const SPRITE_FLY_PX  : float = 700.0
const NAME_FLY_PX    : float = 260.0
const DECK_FLY_PX    : float = 650.0
## The player's whole column (sprite, name, deck name, deck) is moved by this from
## the BattleFrame layout; the opponent's by the mirror of it. Keeps both clear of
## the diagonal lines.
const PLAYER_SHIFT   : Vector2 = Vector2(-150.0, -100.0)
const VS_FONT_SIZE   : int   = 56
const LINE_W         : float = 7.0
## Gap left between the end of each line and its screen corner (along the line).
const LINE_CORNER_GAP: float = 140.0
const DECK_CARD_W    : float = 190.0  # one card of the 3D stack, before squash
const DECK_LAYERS    : int   = 16
const DECK_LAYER_GAP : float = 3.5    # px between stacked cards
const DECK_SQUASH    : float = 0.55   # vertical squash - how flat the stack lies
const DECK_TILT_DEG  : float = 30.0   # rotation of the cards before the squash
## Deck name's top edge, this far below its deck's centre once it has risen.
const DECK_LABEL_GAP : float = 105.0
const SHUFFLE_PX     : float = 135.0  # how far a cut slides out of the stack
const SHUFFLE_JITTER_DEG : float = 7.0   # random twist on cut cards - the "frantic" part

signal _match_ready

static var _current: MatchTransition = null
static var _returning: MatchTransition = null

var _mode: int = Mode.OVERWORLD
var _return_path: String = ""
var _opponent_data: Dictionary = {}
var _player_data: Dictionary = {}

var _stage: Control
var _bg: ColorRect
var _live: ColorRect
var _stripes: ColorRect
var _lines: Array = []
var _frame: BattleFrame
var _badge: Control
var _deck_wraps: Array = []         # [player, opponent] deck-label wrappers
var _rest: Dictionary = {}          # node -> its resting position (after the column shift)
var _decks_root: Control
var _cards_root: Control
var _player_deck: Node2D
var _opp_deck: Node2D
var _p_centre: Vector2
var _o_centre: Vector2
var _player_back: Texture2D
var _opp_back: Texture2D
var _dealt: Array = []              # [{fly, spr, front, front_scale, x}]

var _main: Node = null
var _loading: bool = false
var _aborting: bool = false
var _handing_over: bool = false
var _accept_skip: bool = false


# ============================================================
# ENTRY POINTS
# ============================================================

## True while a match intro overlay is on screen. The match core reads this in
## _ready() to skip its own fade-in and hold the setup screen's text back.
static func is_active() -> bool:
	return _current != null and is_instance_valid(_current)


## True while the way back to the overworld is still on screen. MapManager waits
## for this before a just-fought opponent says goodbye.
static func is_returning() -> bool:
	return _returning != null and is_instance_valid(_returning)


## Every battle accepted in the overworld. `player` is the overworld player node -
## the zoom heads for it. Returns once the overworld has been captured; the rest
## runs on its own.
static func start_from_overworld(player: Node) -> void:
	var t := _make(Mode.OVERWORLD)
	await t._capture(player)
	t._run()


## No overworld to zoom from (the outro's retry-on-loss): starts at the VS badge.
static func start_vs() -> void:
	_make(Mode.VS)._run()


## Best-of-three, next round: starts with the two decks.
static func start_decks() -> void:
	_make(Mode.DECKS)._run()


## Out of a match. See the header.
static func return_to_scene(path: String) -> void:
	var t := MatchTransition.new()
	t._mode = Mode.RETURN
	t._return_path = path
	t.layer = 100
	_returning = t
	(Engine.get_main_loop() as SceneTree).root.add_child(t)
	t._run_return()


static func _make(mode: int) -> MatchTransition:
	var t := MatchTransition.new()
	t._mode = mode
	t.layer = 100
	(Engine.get_main_loop() as SceneTree).root.add_child(t)
	_current = t
	return t


func _exit_tree() -> void:
	if _current == self:
		_current = null
	if _returning == self:
		_returning = null


# ============================================================
# INPUT - everything is swallowed while the overlay is up
# ============================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if _mode == Mode.RETURN:
		return
	if _accept_skip and (UIInput.is_advance(event) or UIInput.is_click(event)):
		_skip()


# ============================================================
# CAPTURE + DATA
# ============================================================

func _capture(player: Node) -> void:
	# The frame drawn AFTER MapManager hid the message box: wait for it to finish
	# drawing, then read it back. Nothing is moving (the actors are frozen), so the
	# one-frame stall of the GPU read-back cannot be seen.
	await RenderingServer.frame_post_draw
	var vp: Viewport = get_tree().root
	var focus_px: Vector2 = vp.get_visible_rect().size * 0.5
	if player != null and is_instance_valid(player) and player is CanvasItem:
		focus_px = (player as CanvasItem).get_global_transform_with_canvas().origin
	MatchBackdrop.capture(vp, focus_px)


func _load_data() -> void:
	if _mode == Mode.DECKS:
		# Best-of-three: GameDataManager still holds this series' two sides.
		_opponent_data = GameDataManager.opponent_data
		_player_data = GameDataManager.player_data
		return
	_load_opponent_data(GameState.current_opponent_name)
	_load_player_data()


# Copied from the retired Match_Start_Intro_Script.gd.
func _load_opponent_data(trainer_name: String) -> void:
	if GameState.test_match_mode:
		_opponent_data = GameState.build_test_opponent_data()
		GameDataManager.opponent_data = _opponent_data
		return
	_opponent_data = CharacterSchedule.find_opponent(
		GameState.current_opponent_map, trainer_name,
		GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	_opponent_data.merge(GameState.forced_opponent_overrides, true)
	if _opponent_data.is_empty():
		print("Opponent with name ", trainer_name, " not found on map ", GameState.current_opponent_map)
		return
	GameDataManager.opponent_data = _opponent_data


func _load_player_data() -> void:
	var file := FileAccess.open(GameState.PLAYER_CURRENT_DATA_PATH, FileAccess.READ)
	if file == null:
		print("Error loading player file")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_player_data = parsed
		GameDataManager.player_data = _player_data


# ============================================================
# THE MAIN RUN
# ============================================================

func _skip_everything() -> bool:
	return GameState.is_transition_skipped() or GameState.transition_time(1.0) <= 0.0


## A duration at the player's Animation speed, then PACE.
func _t(base: float) -> float:
	return GameState.transition_time(base) * PACE


func _run() -> void:
	_load_data()
	_build_stage()

	if _skip_everything():
		await _run_skipped()
		return

	get_tree().create_timer(SKIP_GUARD).timeout.connect(func() -> void: _accept_skip = true)

	# THE SOUND TIMELINE: the battle-start sting (double speed - SFX_battle_start_fast) plays over
	# the zoom and the VS screen and has died away by the time the decks arrive (anything left is
	# faded out in _decks_in). The shuffle and the deal are quiet apart from their own card sounds,
	# and the opponent's music starts as the first card flips (_deal). A skip cuts the sting and
	# starts the music at once. The match core holds its own music back while this overlay runs.
	if _mode != Mode.DECKS:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start_fast)

	# Steps 1-2, or the cover fade for the other two entry points.
	if _mode == Mode.OVERWORLD:
		_stripes.modulate.a = 0.0
		var zt := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		zt.tween_property(_bg.material, "shader_parameter/progress", 1.0, _t(ZOOM_TIME))
		if not await _wait(_t(ZOOM_TIME)): return
		# The stripes come in late and slowly, from the moment the badge starts.
		create_tween().tween_property(_stripes, "modulate:a", 1.0, _t(STRIPES_FADE))
	else:
		_stage.modulate.a = 0.0
		create_tween().tween_property(_stage, "modulate:a", 1.0, _t(COVER_FADE))
		if not await _wait(_t(COVER_FADE)): return

	if _mode == Mode.DECKS:
		# The screen is still here: load the match under it now.
		await _ensure_match()
		if _aborting: return
		_decks_in(true)
		if not await _wait(_t(DECK_IN)): return
		_deck_labels_to_decks()
	else:
		if not await _vs_in(): return
		# Step 5: the match loads underneath while everything sits still.
		var hold_start := Time.get_ticks_msec()
		await _ensure_match()
		if _aborting: return
		var left: float = _frame.hold_time(HOLD) * PACE - float(Time.get_ticks_msec() - hold_start) / 1000.0
		if not await _wait(maxf(left, 0.0)): return
		_vs_out()
		_decks_in(false)
		if not await _wait(_t(DECK_IN_DELAY + DECK_IN)): return
		_deck_labels_to_decks()

	# Step 8.
	_shuffle(_player_deck, _t(SHUFFLE_TIME))
	_shuffle(_opp_deck, _t(SHUFFLE_TIME))
	if not await _wait(_t(SHUFFLE_TIME)): return

	# Step 9.
	_fly_to(_opp_deck, _opp_deck.position + Vector2(DECK_FLY_PX, 0.0), 0.0, _t(OPP_DECK_OUT), false)
	_fly_to(_deck_wraps[1], _rest_of(_deck_wraps[1]) + Vector2(DECK_FLY_PX, 0.0), 0.0, _t(OPP_DECK_OUT), false)
	if not await _wait(_t(OPP_DECK_OUT)): return

	# Steps 10-11.
	if not await _deal(): return

	# Step 12.
	_hand_over()


## The Options skip / Reduce motion: no sequence at all. The backdrop still fades
## over the old screen so the setup screen arrives on the same ground.
func _run_skipped() -> void:
	var fade: float = _t(SKIP_FADE)
	if _bg != null:
		_bg.material.set_shader_parameter("progress", 1.0)
	_stage.modulate.a = 0.0
	if fade > 0.0:
		create_tween().tween_property(_stage, "modulate:a", 1.0, fade)
		await get_tree().create_timer(fade).timeout
	else:
		_stage.modulate.a = 1.0
	_start_battle_music()
	_hide_foreground()
	await _ensure_match()
	_handing_over = true
	_main.intro_reveal(0.0)
	await _fade_out_and_free(fade)


## A click / Space / Enter mid-sequence: straight to the setup screen, and the
## battle-start sting is cut off with it.
func _skip() -> void:
	if _aborting or _handing_over:
		return
	_aborting = true
	_accept_skip = false
	_stop_intro_sfx()
	_start_battle_music()
	await _ensure_match()
	_handing_over = true
	_main.intro_reveal(_t(UI_FADE))
	await _fade_out_and_free(_t(SKIP_FADE))


## Fades the battle-start sting out over `secs` (if it is still playing), then frees it.
func _fade_intro_sfx(secs: float) -> void:
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == SoundManagerScript.SFX_battle_start_fast:
			var p := child as AudioStreamPlayer
			if secs <= 0.0:
				p.stop()
				p.queue_free()
				continue
			var tw := p.create_tween()
			tw.tween_property(p, "volume_db", -40.0, secs)
			tw.tween_callback(p.queue_free)


func _stop_intro_sfx() -> void:
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream in [SoundManagerScript.SFX_battle_start, SoundManagerScript.SFX_battle_start_fast]:
			(child as AudioStreamPlayer).stop()
			child.queue_free()


func _fade_out_and_free(fade: float) -> void:
	if fade > 0.0:
		var tw := create_tween()
		tw.tween_property(_stage, "modulate:a", 0.0, fade)
		await tw.finished
	queue_free()


## Waits, then says whether the sequence should carry on (false once skipped).
func _wait(seconds: float) -> bool:
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
	return not _aborting


# ============================================================
# THE STAGE
# ============================================================

func _build_stage() -> void:
	_stage = Control.new()
	_stage.name = "match_transition_stage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under it can be clicked
	add_child(_stage)

	if _mode == Mode.RETURN:
		# The live map blurred (under) and the old screenshot (over). No stripes: the
		# outro's own stripes vanish as this covers them.
		if MatchBackdrop.has():
			_live = MatchBackdrop.make_live_rect(1.0)
			_live.visible = false     # nothing to blur until the map is underneath
			_stage.add_child(_live)
			_bg = MatchBackdrop.make_rect(1.0)
			_stage.add_child(_bg)
		else:
			var cover := ColorRect.new()
			cover.color = Color.BLACK
			cover.set_anchors_preset(Control.PRESET_FULL_RECT)
			cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_stage.add_child(cover)
		return

	# Background: the screenshot (zooming from 0 on the overworld, finished
	# otherwise) and the stripes. Without a screenshot, the theme's own field.
	if MatchBackdrop.has():
		_bg = MatchBackdrop.make_rect(0.0 if _mode == Mode.OVERWORLD else 1.0)
		_stage.add_child(_bg)
		_stripes = UIKit.add_field(_stage)
		MatchBackdrop.make_stripes_only(_stripes)
		_stage.move_child(_bg, 0)
		_bg.z_index = _stripes.z_index
	else:
		_stripes = UIKit.add_field(_stage)
		_bg = null

	var sw := UIKit.screen_w()
	var sh := UIKit.screen_h()
	var centre := Vector2(sw * 0.5, sh * 0.5)

	# Lines go UNDER the badge, so they are added before the frame.
	var lines_root := Control.new()
	lines_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(lines_root)

	_frame = BattleFrame.new()
	_frame.own_ground = false
	_stage.add_child(_frame)
	_frame.setup("intro")
	_frame.snap_to_rest()
	# The overlay owns the ground: the frame's own field is not part of this.
	_frame.field.visible = false
	_frame.top_band_fast.visible = false
	_frame.bottom_band_fast.visible = false

	_frame.set_trainer(_frame.player, _sprite_for(_player_data),
			str(_player_data.get("name", "")), str(_player_data.get("deck", "")))
	_frame.set_trainer(_frame.opponent, _sprite_for(_opponent_data),
			GameState.battle_display_name(str(_opponent_data.get("name", ""))),
			str(_opponent_data.get("deck", "")))

	# The deck names leave the name blocks: they stay on screen after the names go.
	for f in [_frame.player, _frame.opponent]:
		var wrap := Control.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(wrap)
		f.deck_label.reparent(wrap)
		_deck_wraps.append(wrap)

	# Each column moves away from the centre line: player up-left, opponent down-right.
	for pair in [[_frame.player, _deck_wraps[0], PLAYER_SHIFT], [_frame.opponent, _deck_wraps[1], -PLAYER_SHIFT]]:
		var f = pair[0]
		var shift: Vector2 = pair[2]
		for node in [f.fast, f.name_anim, pair[1]]:
			(node as Control).position += shift
			_rest[node] = (node as Control).position

	# The VS badge, in the exact centre of the screen (BattleFrame's own badge row
	# sits 70px above centre, for the outro's layout).
	_frame.badge_slot.position.y = centre.y - BattleFrame.BADGE_D * 0.5
	_badge = _frame.make_badge("VS", "intro", VS_FONT_SIZE)
	_frame.badge_slot.add_child(_badge)
	_badge.position.x = centre.x - BattleFrame.BADGE_D * 0.5
	_badge.pivot_offset = _badge.size * 0.5
	_badge.scale = Vector2.ZERO

	# Toward the top-right and bottom-left corners, stopping LINE_CORNER_GAP short.
	var stops: Array = UITheme.outcome_grad("intro")
	var r: float = BattleFrame.BADGE_D * 0.5
	for corner in [Vector2(sw, 0.0), Vector2(0.0, sh)]:
		var line := _Line.new()
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dir: Vector2 = (corner - centre).normalized()
		line.a = centre + dir * r
		line.b = corner - dir * LINE_CORNER_GAP
		line.width = LINE_W
		line.stops = stops
		lines_root.add_child(line)
		_lines.append(line)

	_decks_root = Control.new()
	_decks_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_decks_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_decks_root)
	_cards_root = Control.new()
	_cards_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_cards_root)

	_player_back = _sleeve_texture(str(_player_data.get("sleeve", "default")))
	_opp_back = _sleeve_texture(str(_opponent_data.get("sleeve", "")))

	_measure_deck_spots()
	_hide_foreground()


func _rest_of(node: Node) -> Vector2:
	return _rest.get(node, Vector2.ZERO)


## Everything but the background, parked invisible. Each step reveals its own part.
func _hide_foreground() -> void:
	if _frame == null:
		return
	for f in [_frame.player, _frame.opponent]:
		f.fast.modulate.a = 0.0
		f.name_anim.modulate.a = 0.0
	for w in _deck_wraps:
		(w as Control).modulate.a = 0.0


# ============================================================
# STEPS 3-4 IN, 6 OUT
# ============================================================

func _vs_in() -> bool:
	# Step 3: the badge grows out of nothing - it IS the dot - then the lines.
	var bt := _badge.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_property(_badge, "scale", Vector2.ONE, _t(BADGE_GROW))
	if not await _wait(_t(BADGE_GROW) * LINE_START): return false

	for line in _lines:
		var lt := (line as Control).create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lt.tween_method(line.set_head, 0.0, 1.0, _t(LINE_SHOOT))
	if not await _wait(_t(BADGE_GROW) * (1.0 - LINE_START)): return false

	# Step 4: trainers from their own sides, names from above (player) / below (opponent).
	var p := _frame.player
	var o := _frame.opponent
	_fly_in(p.fast, Vector2(-SPRITE_FLY_PX, 0.0), 0.0, _t(TRAINER_IN))
	_fly_in(o.fast, Vector2(SPRITE_FLY_PX, 0.0), 0.0, _t(TRAINER_IN))
	_fly_in(p.name_anim, Vector2(0.0, -NAME_FLY_PX), _t(NAME_DELAY), _t(TRAINER_IN))
	_fly_in(_deck_wraps[0], Vector2(0.0, -NAME_FLY_PX), _t(NAME_DELAY), _t(TRAINER_IN))
	_fly_in(o.name_anim, Vector2(0.0, NAME_FLY_PX), _t(NAME_DELAY), _t(TRAINER_IN))
	_fly_in(_deck_wraps[1], Vector2(0.0, NAME_FLY_PX), _t(NAME_DELAY), _t(TRAINER_IN))
	return await _wait(_t(NAME_DELAY + TRAINER_IN))


func _vs_out() -> void:
	# The lines are wiped from the badge outward: their near end races to the far end.
	for line in _lines:
		var lt := (line as Control).create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		lt.tween_method(line.set_tail, 0.0, 1.0, _t(LINE_WIPE))
	var bt := _badge.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	bt.tween_property(_badge, "scale", Vector2.ZERO, _t(BADGE_SHRINK))

	# Trainers and names leave the way they came. The deck names stay.
	var p := _frame.player
	var o := _frame.opponent
	_fly_to(p.fast, _rest_of(p.fast) + Vector2(-SPRITE_FLY_PX, 0.0), 0.0, _t(TRAINER_OUT), false)
	_fly_to(o.fast, _rest_of(o.fast) + Vector2(SPRITE_FLY_PX, 0.0), 0.0, _t(TRAINER_OUT), false)
	_fly_to(p.name_anim, _rest_of(p.name_anim) + Vector2(0.0, -NAME_FLY_PX), 0.0, _t(TRAINER_OUT), false)
	_fly_to(o.name_anim, _rest_of(o.name_anim) + Vector2(0.0, NAME_FLY_PX), 0.0, _t(TRAINER_OUT), false)


## A node arriving: it starts `offset` away and invisible, and lands at rest.
func _fly_in(node: CanvasItem, offset: Vector2, delay: float, dur: float) -> void:
	var rest: Vector2 = node.get("position")
	node.set("position", rest + offset)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", rest, dur).set_delay(delay)
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.75).set_delay(delay)


## A node moving to `to` and fading to `alpha`. `ease_out` for arrivals, else the
## motion accelerates away.
func _fly_to(node: CanvasItem, to: Vector2, alpha: float, dur: float, ease_out: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := node.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_EXPO if ease_out else Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT if ease_out else Tween.EASE_IN)
	tw.tween_property(node, "position", to, dur)
	tw.tween_property(node, "modulate:a", alpha, dur)


# ============================================================
# STEPS 6-9: THE DECKS
# ============================================================

## Where each deck sits: the centre of its trainer's sprite AT REST (after the column
## shift). Measured while building, before step 6 flies the trainers away.
func _measure_deck_spots() -> void:
	_p_centre = Vector2(_frame._col_x(BattleFrame.COL_PLAYER_X), _frame._stage_centre_y()) + PLAYER_SHIFT
	_o_centre = Vector2(_frame._col_x(BattleFrame.COL_OPPONENT_X), _frame._stage_centre_y()) - PLAYER_SHIFT
	# A trainer with no sprite has a zero-width rect; the column centre stands in.
	var ps: TextureRect = _frame.player.sprite
	var os: TextureRect = _frame.opponent.sprite
	if ps.texture != null:
		_p_centre = ps.get_parent().position + ps.get_parent().get_parent().position + ps.position + ps.size * 0.5
	if os.texture != null:
		_o_centre = os.get_parent().position + os.get_parent().get_parent().position + os.position + os.size * 0.5


## Once the decks have landed, each deck name rises (or drops) to sit just under
## its deck. Runs alongside the shuffle, so it adds no time.
func _deck_labels_to_decks() -> void:
	for pair in [[_deck_wraps[0], _frame.player.deck_label, _p_centre],
				 [_deck_wraps[1], _frame.opponent.deck_label, _o_centre]]:
		var wrap: Control = pair[0]
		var lbl: Label = pair[1]
		var deck_c: Vector2 = pair[2]
		var target := Vector2(wrap.position.x, deck_c.y + DECK_LABEL_GAP - lbl.position.y)
		_rest[wrap] = target
		var tw := wrap.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(wrap, "position", target, _t(DECK_LABEL_RISE))


func _start_battle_music() -> void:
	var music_file := str(_opponent_data.get("music", ""))
	if music_file.strip_edges() == "" or not ResourceLoader.exists(SoundManagerScript.bgm_path(music_file)):
		SoundManagerScript.play_bgm(SoundManagerScript.BGM_NORMAL_BATTLE, true)
	else:
		SoundManagerScript.play_bgm_named(music_file, true)


func _decks_in(with_labels: bool) -> void:
	# Whatever is left of the battle-start sting fades away as the decks arrive: the shuffle
	# and the deal happen in quiet, with only their own card sounds.
	_fade_intro_sfx(_t(DECK_IN))
	_player_deck = _make_deck(_player_back)
	_opp_deck = _make_deck(_opp_back)
	_decks_root.add_child(_player_deck)
	_decks_root.add_child(_opp_deck)
	var delay: float = 0.0 if with_labels else _t(DECK_IN_DELAY)
	_player_deck.position = _p_centre
	_opp_deck.position = _o_centre
	_fly_in(_player_deck, Vector2(-DECK_FLY_PX, 0.0), delay, _t(DECK_IN))
	_fly_in(_opp_deck, Vector2(DECK_FLY_PX, 0.0), delay, _t(DECK_IN))
	if with_labels:
		# Best-of-three: nothing was on screen before, so the deck names arrive with the decks.
		_fly_in(_deck_wraps[0], Vector2(-DECK_FLY_PX, 0.0), delay, _t(DECK_IN))
		_fly_in(_deck_wraps[1], Vector2(DECK_FLY_PX, 0.0), delay, _t(DECK_IN))


## A deck lying on the table: DECK_LAYERS copies of the sleeve, each rotated then
## squashed (the squash is on a parent node, so it applies AFTER the rotation - that
## is what makes a flat card lying at an angle rather than a skewed rectangle), and
## stacked a few px apart, lowest darkest.
func _make_deck(back: Texture2D) -> Node2D:
	var deck := Node2D.new()
	for i in range(DECK_LAYERS):
		var layer := Node2D.new()
		layer.position = Vector2(0.0, -float(i) * DECK_LAYER_GAP)
		layer.scale = Vector2(1.0, DECK_SQUASH)
		var spr := Sprite2D.new()
		spr.texture = back
		spr.rotation = deg_to_rad(DECK_TILT_DEG)
		if back != null:
			spr.scale = Vector2.ONE * (DECK_CARD_W / float(back.get_width()))
		layer.add_child(spr)
		deck.add_child(layer)
	_shade_deck(deck)
	return deck


func _shade_deck(deck: Node2D) -> void:
	var n: int = deck.get_child_count()
	for i in range(n):
		var shade: float = lerpf(0.62, 1.0, float(i) / float(maxi(n - 1, 1)))
		(deck.get_child(i).get_child(0) as CanvasItem).modulate = Color(shade, shade, shade, 1.0)


## A hard, fast shuffle: every cut splits the stack in three, the top and middle
## packets fly out to OPPOSITE sides with a random twist, the order is rebuilt
## (middle on top, top on the bottom) and they slam back in. SHUFFLE_CYCLES cuts.
func _shuffle(deck: Node2D, total: float) -> void:
	var per: float = total / float(SHUFFLE_CYCLES)
	var tilt: float = deg_to_rad(DECK_TILT_DEG)
	for c in range(SHUFFLE_CYCLES):
		if _aborting or not is_instance_valid(deck):
			return
		var layers: Array = deck.get_children()
		var n: int = layers.size()
		var cut_a: int = randi_range(n / 4, n / 2)              # bottom packet ends here
		var cut_b: int = randi_range(cut_a + 2, n - 2)          # middle packet ends here
		var bottom: Array = layers.slice(0, cut_a)
		var middle: Array = layers.slice(cut_a, cut_b)
		var top: Array = layers.slice(cut_b, n)
		var side: float = 1.0 if c % 2 == 0 else -1.0
		# One riffle per cut, a touch higher or lower each time so the cuts don't sound identical.
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_shuffle, randf_range(0.92, 1.1))

		var out := deck.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for l in top:
			out.tween_property(l, "position:x", side * SHUFFLE_PX, per * 0.45)
			out.tween_property(l.get_child(0), "rotation",
					tilt + deg_to_rad(randf_range(-SHUFFLE_JITTER_DEG, SHUFFLE_JITTER_DEG)), per * 0.45)
		for l in middle:
			out.tween_property(l, "position:x", -side * SHUFFLE_PX * 0.8, per * 0.45)
			out.tween_property(l.get_child(0), "rotation",
					tilt + deg_to_rad(randf_range(-SHUFFLE_JITTER_DEG, SHUFFLE_JITTER_DEG)), per * 0.45)
		if not await _wait(per * 0.45): return
		if not is_instance_valid(deck): return

		# New order, bottom to top: the old top packet, the old bottom, the old middle.
		var order: Array = top + bottom + middle
		for i in range(order.size()):
			deck.move_child(order[i], i)
		_shade_deck(deck)
		var back := deck.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		for i in range(order.size()):
			var l: Node2D = order[i]
			back.tween_property(l, "position", Vector2(0.0, -float(i) * DECK_LAYER_GAP), per * 0.5)
			back.tween_property(l.get_child(0), "rotation", tilt, per * 0.5)
		if not await _wait(per * 0.55): return


# ============================================================
# STEPS 10-11: THE DEAL AND THE FLIP
# ============================================================

func _deal() -> bool:
	var nodes: Array = _main.intro_hand_card_nodes() if _main != null else []
	var n: int = nodes.size()
	if n == 0:
		_player_deck_out()
		return await _wait(_t(DECK_OUT))
	# RIGHT TO LEFT: the first card travels furthest, to the right-hand end of the row.
	for k in range(n):
		_deal_one(nodes[n - 1 - k])
		if k + 1 == mini(DECK_OUT_AT, n):
			_player_deck_out()
		if not await _wait(_t(DEAL_STAGGER)): return false
	if not await _wait(_t(DEAL_FLIGHT) - _t(DEAL_STAGGER) + _t(FLIP_BEAT)): return false

	# Every card turns over, left to right.
	var by_x: Array = _dealt.duplicate()
	by_x.sort_custom(func(a, b): return a["x"] < b["x"])
	# The opponent's music starts with the first flip - the reveal is the start of the match.
	_start_battle_music()
	for d in by_x:
		_flip(d)
		if not await _wait(_t(FLIP_STAGGER)): return false
	return await _wait(_t(FLIP_TIME))


func _player_deck_out() -> void:
	_fly_to(_player_deck, _player_deck.position + Vector2(-DECK_FLY_PX, 0.0), 0.0, _t(DECK_OUT), false)
	_fly_to(_deck_wraps[0], _rest_of(_deck_wraps[0]) + Vector2(-DECK_FLY_PX, 0.0), 0.0, _t(DECK_OUT), false)


## One card off the top of the player's deck onto `real`'s spot. It leaves lying at
## the deck's angle and arrives flat, at the size the setup screen draws it.
func _deal_one(real: TextureRect) -> void:
	var start_pos: Vector2 = _player_deck.position
	var top: Node2D = null
	if _player_deck.get_child_count() > 0:
		top = _player_deck.get_child(_player_deck.get_child_count() - 1)
		start_pos = _player_deck.position + top.position
	if top != null and _player_deck.get_child_count() > 1:
		_player_deck.remove_child(top)
		top.queue_free()

	# Where the setup screen really draws this card: KEEP_ASPECT, top-left aligned.
	var r: Rect2 = real.get_global_rect()
	var front: Texture2D = real.texture
	var fs: Vector2 = front.get_size()
	var k: float = minf(r.size.x / fs.x, r.size.y / fs.y)
	var drawn := Rect2(r.position, fs * k)

	var fly := Node2D.new()
	fly.position = start_pos
	fly.scale = Vector2(1.0, DECK_SQUASH)
	var spr := Sprite2D.new()
	spr.texture = _player_back
	spr.rotation = deg_to_rad(DECK_TILT_DEG)
	var bs: Vector2 = _player_back.get_size() if _player_back != null else fs
	spr.scale = Vector2.ONE * (DECK_CARD_W / bs.x)
	fly.add_child(spr)
	_cards_root.add_child(fly)
	_dealt.append({"fly": fly, "spr": spr, "front": front, "front_scale": Vector2.ONE * k, "x": drawn.position.x})

	var dur: float = _t(DEAL_FLIGHT)
	var tw := fly.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(fly, "position", drawn.get_center(), dur)
	tw.tween_property(fly, "scale", Vector2.ONE, dur)
	tw.tween_property(spr, "rotation", 0.0, dur)
	tw.tween_property(spr, "scale", drawn.size / bs, dur)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)


func _flip(d: Dictionary) -> void:
	var fly: Node2D = d["fly"]
	var spr: Sprite2D = d["spr"]
	var half: float = _t(FLIP_TIME) * 0.5
	var tw := fly.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(fly, "scale:x", 0.0, half).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		spr.texture = d["front"]
		spr.scale = d["front_scale"])
	tw.tween_property(fly, "scale:x", 1.0, half).set_ease(Tween.EASE_OUT)


# ============================================================
# THE MATCH UNDERNEATH, AND THE HAND-OVER
# ============================================================

## Swaps the scene under the overlay for the match, once. Safe to call from both
## the main run and a skip; the second caller waits for the first.
func _ensure_match() -> void:
	if _main != null:
		return
	if _loading:
		await _match_ready
		return
	_loading = true
	var tree := get_tree()
	var old: Node = tree.current_scene
	var packed: PackedScene = SceneCache.get_packed_scene(MATCH_SCENE)
	if packed == null:
		# Not preloaded yet (the splash normally does it): load it now, synchronously.
		packed = load(MATCH_SCENE)
	tree.change_scene_to_packed(packed)
	while tree.current_scene == null or tree.current_scene == old:
		await tree.process_frame
	_main = tree.current_scene
	# _input runs last-child-first: stay ahead of the match so it hears nothing.
	get_parent().move_child(self, -1)
	# The setup screen's row lays itself out over the next frame or two; its rects
	# are what the deal flies to.
	await tree.process_frame
	await tree.process_frame
	_loading = false
	_match_ready.emit()


func _hand_over() -> void:
	_handing_over = true
	_start_battle_music()   # no-op if the first flip already started it
	# The dealt cards are sitting exactly on the real ones and the two backgrounds
	# are the same picture, so removing the overlay changes nothing on screen.
	_main.intro_reveal(_t(UI_FADE))
	queue_free()


# ============================================================
# OUT OF A MATCH
# ============================================================

func _run_return() -> void:
	_build_stage()

	# 1. Cover the outro FAST - its words, sprites and stripes are gone in a blink,
	#    leaving the blurred screenshot.
	var cover: float = _t(RETURN_COVER)
	_stage.modulate.a = 0.0
	if cover > 0.0:
		var ct := create_tween()
		ct.tween_property(_stage, "modulate:a", 1.0, cover)
		await ct.finished
	else:
		_stage.modulate.a = 1.0

	# 2. The map loads underneath.
	var tree := get_tree()
	var old: Node = tree.current_scene
	SceneCache.change_scene(_return_path)
	while tree.current_scene == null or tree.current_scene == old:
		await tree.process_frame
	get_parent().move_child(self, -1)
	await tree.process_frame

	if _bg == null or _live == null:
		queue_free()
		return

	# 3. The live map - already in its NEW time of day, with the new slot's NPCs -
	#    appears UNDER the screenshot, blurred and zoomed exactly the same way.
	# 4. 2026-11-12 (user: the way back was slow and sluggish, one effect after another):
	#    the screenshot's fade (the new time-of-day colour) and the un-zoom / de-blur
	#    now run TOGETHER, in one parallel tween. At progress 0 the live rect IS the
	#    screen, so freeing the overlay changes nothing.
	_live.visible = true
	var colour: float = _t(RETURN_COLOUR)
	var unzoom: float = _t(RETURN_UNZOOM)
	if colour > 0.0 or unzoom > 0.0:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_bg, "modulate:a", 0.0, maxf(colour, 0.01))
		tw.tween_property(_live.material, "shader_parameter/progress", 0.0, maxf(unzoom, 0.01))
		await tw.finished
	queue_free()

# ============================================================
# HELPERS
# ============================================================

func _sprite_for(data: Dictionary) -> Texture2D:
	var key := str(data.get("sprite", ""))
	if key == "":
		return null
	var path := BATTLE_SPRITE_DIR + key.to_lower() + ".png"
	if not ResourceLoader.exists(path):
		print("Could not load battle sprite: ", path)
		return null
	return load(path)


## Same resolution as Main_Match_Core._resolve_sleeve_path(small = false).
func _sleeve_texture(sleeve_name: String) -> Texture2D:
	if sleeve_name != "" and sleeve_name != "default":
		for ext in [".jpg", ".png"]:
			var path: String = "res://Image_Assets/Sleeves/" + sleeve_name + ext
			if ResourceLoader.exists(path):
				var tex: Texture2D = load(path)
				if tex != null:
					return tex
	return load(DEFAULT_SLEEVE)


# One of the two lines out of the badge. `head` is how far the far tip has got
# (0..1 along a -> b), `tail` how far the near end has been wiped. Coloured along
# its length through the badge ring's three gradient stops, so it leaves the
# badge in the ring's own colour.
class _Line extends Control:
	var a: Vector2
	var b: Vector2
	var head: float = 0.0
	var tail: float = 0.0
	var width: float = 7.0
	var stops: Array = [Color.WHITE, Color.WHITE, Color.WHITE]

	func set_head(v: float) -> void:
		head = v
		queue_redraw()

	func set_tail(v: float) -> void:
		tail = v
		queue_redraw()

	func _col(t: float) -> Color:
		if t < 0.5:
			return (stops[0] as Color).lerp(stops[1], t * 2.0)
		return (stops[1] as Color).lerp(stops[2], (t - 0.5) * 2.0)

	func _draw() -> void:
		if head - tail <= 0.0005:
			return
		var nrm: Vector2 = (b - a).normalized().orthogonal() * width * 0.5
		for seg in [[tail, minf(head, 0.5)], [maxf(tail, 0.5), head]]:
			var t0: float = seg[0]
			var t1: float = seg[1]
			if t1 <= t0:
				continue
			var p0: Vector2 = a.lerp(b, t0)
			var p1: Vector2 = a.lerp(b, t1)
			var c0 := _col(t0)
			var c1 := _col(t1)
			draw_polygon(PackedVector2Array([p0 + nrm, p1 + nrm, p1 - nrm, p0 - nrm]),
					PackedColorArray([c0, c1, c1, c0]))
