extends Control

# ============================================================
# BEST-OF-THREE ROUND TRACKER
# ============================================================
# Shown after every round of a best-of-three match. Same frame, sprites, names
# and decks as the intro, with three round slots where the VS wheel goes and a
# ROUND title where the win/loss stats row goes.
#
# The flow logic is untouched: this screen appears after each round, and after
# three rounds - or after two wins or two losses - it hands off to the normal
# outro instead of back to the match.
#
# -- WHY NOBODY IS GREYED OUT HERE ----------------------------
# Desaturation is how the FINAL win/loss screen says "this is settled". Using it
# between rounds would tell the player the match is over when it is not, so
# BattleFrame.desaturate() is deliberately never called from this file.
# ============================================================

const BATTLE_SPRITE_DIR := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"
const DISC_SHADER := "res://Scripts/Shaders/UI_Round_Disc.gdshader"

# -- TWEAKABLE ------------------------------------------------
const SLOT_D          : float = 180.0
const SLOT_GAP        : float = 46.0
const SLOT_RING_W     : float = 6.5
const SLOT_RING_INSET : float = 6.0
const DISC_INSET      : float = 21.0
const DISC_LABEL_FONT : int   = 29
const DISC_TRACK_EM   : float = 0.09

const TITLE_FONT      : int   = 60
const TITLE_TRACK_EM  : float = 0.15
const TITLE_SHADOW_PX : int   = 4
# The design asks for a soft 50px bloom behind the title as well as the offset
# shadow. Godot has no per-label blur, so this is a wide low-alpha OUTLINE in the
# same colour - the closest single-node stand-in, and it is what stops the title
# reading as flat type dropped on the band.
const TITLE_GLOW_PX   : int   = 8
const TITLE_GLOW_ALPHA: float = 0.45

# The newest chip flips in like a coin: five full turns while it grows from 0.72
# to full size, fast at first and slowing to a dead stop in its slot.
const FLIP_TURNS      : float = 5.0     # 1800 degrees
const FLIP_TIME       : float = 1.5
const FLIP_DELAY      : float = 0.45
const FLIP_FROM_SCALE : float = 0.72

# The ROUND title rides the frame's own top-slot drop-in (BattleFrame.SLOT_DELAY),
# which is the same 0.34s the win/loss stats row uses - they occupy the same slot.
const SLOTS_DELAY     : float = 0.30
const SLOTS_TIME      : float = 0.50
const HOLD_AFTER      : float = 1.4
## ISSUE #288: 0.5 -> 1.0. "Double the fade in time for all scene transitions."
## The same doubling is applied on the match board, the intro, the outro and the
## best-of-three tracker, so every boundary in a match moves at one pace. It is
## still multiplied by the Animation speed preset via transition_time(), and
## reduce motion still collapses it to zero. TWEAKABLE.
const FADE_TIME       : float = 1.0

var opponent_data: Dictionary = {}
var player_data: Dictionary = {}
var frame: BattleFrame = null

var _transitioning: bool = false
var _click_enabled: bool = false
var _decided: bool = false


func _ready() -> void:
	modulate.a = 0.0

	var round_results: Array = GameState.series_round_results
	var current_round: int = round_results.size()
	var current_result: String = round_results.back() if not round_results.is_empty() else "loss"
	_decided = (
		GameState.series_wins >= GameState.series_required_to_win
		or GameState.series_losses >= GameState.series_required_to_win
	)

	_load_data()
	SoundManagerScript.stop_bgm()

	# Options "Play Match Intro / Outro Animation?" = skip. The round-counter ceremony is
	# the same family as the intro and outro, so it is bypassed outright - no jingle, no
	# fade, no flip. The round result is already recorded in GameState.
	if GameState.is_transition_skipped():
		_do_transition()
		return

	_build_frame(round_results, current_result, current_round)

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_start)

	# The fade and the entrance run TOGETHER - see the same note in the intro. The
	# elements are already parked at their start offsets, so the fade reveals motion
	# that is under way rather than a still picture that then jumps.
	var fade_in := create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, GameState.transition_time(FADE_TIME))
	fade_in.tween_callback(func() -> void: _click_enabled = true)

	await frame.play_entrance()
	await get_tree().create_timer(frame.hold_time(HOLD_AFTER)).timeout
	_do_transition()


func _input(event: InputEvent) -> void:
	# Space / Enter / Escape advance the between-games screen, the same as a click.
	# Escape used to call get_tree().quit() - mid-series, that lost the whole match.
	if UIInput.is_advance(event) and _click_enabled and not _transitioning:
		get_viewport().set_input_as_handled()
		_do_transition()
		return
	# The wheel is not a click -- scrolling must not skip the between-games screen.
	if UIInput.is_click(event) and _click_enabled and not _transitioning:
		_do_transition()


# ============================================================
# THE SCREEN
# ============================================================

func _build_frame(round_results: Array, current_result: String, current_round: int) -> void:
	frame = BattleFrame.new()
	add_child(frame)
	# The bands and the title take the colour of the LATEST result.
	frame.setup(current_result)

	frame.set_trainer(frame.player, _sprite_for(player_data),
			str(player_data.get("name", "")), str(player_data.get("deck", "")))
	frame.set_trainer(frame.opponent, _sprite_for(opponent_data),
			str(opponent_data.get("name", "")), str(opponent_data.get("deck", "")))

	_build_title(current_round, current_result)
	_build_slots(round_results)


# The word ROUND and the number, announcing the round about to be played - or the
# one just decided, when the series ends here.
func _build_title(current_round: int, result: String) -> void:
	var shown_round: int = mini(current_round + 1, 3)
	var accent: Color = UITheme.outcome_grad(result)[1]

	var title := Label.new()
	title.text = "ROUND %d" % shown_round
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", UITheme.font("title"))
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.add_theme_constant_override("font_spacing_glyph",
			int(round(TITLE_TRACK_EM * float(TITLE_FONT))))
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", accent)
	title.add_theme_constant_override("shadow_offset_x", TITLE_SHADOW_PX)
	title.add_theme_constant_override("shadow_offset_y", TITLE_SHADOW_PX)
	var glow := accent
	glow.a = TITLE_GLOW_ALPHA
	title.add_theme_color_override("font_outline_color", glow)
	title.add_theme_constant_override("outline_size", TITLE_GLOW_PX)
	title.position = Vector2.ZERO
	title.size = frame.top_slot.size
	frame.top_slot.add_child(title)


# All three rings are drawn from round one. The empty ones hold their place, so
# the row never reflows and the player can see how many rounds are left without
# counting them.
func _build_slots(round_results: Array) -> void:
	var row_w := SLOT_D * 3.0 + SLOT_GAP * 2.0
	var left := BattleFrame.COL_BADGE_X - row_w * 0.5
	# The slots are taller than a chip but shorter than the badge, so they are
	# centred in the badge slot rather than filling it.
	var top := (frame.badge_slot.size.y - SLOT_D) * 0.5
	var newest: int = round_results.size() - 1

	# The row drops in on its own delay, so it needs a wrapper of its own to be
	# moved by - the badge slot itself must stay put, because the intro's VS wheel
	# lives in it and does not move.
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.badge_slot.add_child(row)
	frame.drop_in(row, GameState.transition_time(SLOTS_DELAY),
			GameState.transition_time(SLOTS_TIME))

	for i in 3:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2(left + float(i) * (SLOT_D + SLOT_GAP), top)
		holder.size = Vector2(SLOT_D, SLOT_D)
		# The flip scales the chip about its own middle.
		holder.pivot_offset = holder.size * 0.5
		row.add_child(holder)

		if i >= round_results.size():
			_build_empty_slot(holder)
			continue

		var result: String = String(round_results[i])
		# Only the newest chip's ring turns; the older ones hold a static gradient,
		# which is what tells the player which result just landed.
		_build_filled_slot(holder, result, i == newest)
		if i == newest:
			_flip_in(holder)


func _build_empty_slot(holder: Control) -> void:
	var ring := frame.make_ring(holder.size, frame.kind(), false, SLOT_RING_W, SLOT_RING_INSET)
	ring.modulate.a = UITheme.BATTLE["empty_ring_alpha"]
	holder.add_child(ring)


func _build_filled_slot(holder: Control, result: String, spinning: bool) -> void:
	var disc_d := SLOT_D - DISC_INSET * 2.0
	var stops: Array = UITheme.battle_grad("disc_%s_grad" % result)

	var disc := ColorRect.new()
	disc.color = Color.WHITE            # the shader replaces this entirely
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.position = Vector2(DISC_INSET, DISC_INSET)
	disc.size = Vector2(disc_d, disc_d)
	var mat := ShaderMaterial.new()
	mat.shader = load(DISC_SHADER)
	mat.set_shader_parameter("grad_a", stops[0])
	mat.set_shader_parameter("grad_b", stops[1])
	mat.set_shader_parameter("grad_c", stops[2])
	mat.set_shader_parameter("sheen_col", UITheme.battle_col("disc_sheen"))
	disc.material = mat
	holder.add_child(disc)

	var lbl := Label.new()
	lbl.text = "Win" if result == "win" else "Loss"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UITheme.font("title"))
	lbl.add_theme_font_size_override("font_size", DISC_LABEL_FONT)
	lbl.add_theme_constant_override("font_spacing_glyph",
			int(round(DISC_TRACK_EM * float(DISC_LABEL_FONT))))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = Vector2.ZERO
	lbl.size = holder.size
	holder.add_child(lbl)

	holder.add_child(frame.make_ring(holder.size, result, spinning,
			SLOT_RING_W, SLOT_RING_INSET))


# The coin flip. A 2D node cannot rotate about Y, so the turn is done the way a
# spinning card is done everywhere else in this game: scale.x follows the cosine
# of the rotation, passing through zero at each quarter turn, while the overall
# size grows from FLIP_FROM_SCALE to 1. Driven by a single method tween so the
# easing applies to the ROTATION rather than to each half-turn separately - which
# is what makes it slow to a dead stop rather than stuttering to one.
func _flip_in(holder: Control) -> void:
	var dur: float = GameState.transition_time(FLIP_TIME)
	var delay: float = GameState.transition_time(FLIP_DELAY)
	if dur <= 0.0:
		holder.scale = Vector2.ONE
		return

	holder.scale = Vector2(0.0, FLIP_FROM_SCALE)
	var tw := holder.create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(t: float) -> void:
			var size_now: float = lerpf(FLIP_FROM_SCALE, 1.0, t)
			holder.scale = Vector2(cos(t * FLIP_TURNS * TAU) * size_now, size_now),
			0.0, 1.0, dur)
	# Land exactly, rather than wherever the cosine happened to be on the last frame.
	tw.tween_callback(func() -> void: holder.scale = Vector2.ONE)


func _sprite_for(data: Dictionary) -> Texture2D:
	var key := str(data.get("sprite", ""))
	if key == "":
		return null
	var path := BATTLE_SPRITE_DIR + key.to_lower() + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# ============================================================
# DATA AND HAND-OFF
# ============================================================

func _load_data() -> void:
	# GameDataManager is already populated by Match_Start_Intro (including the
	# All_NPC_Constant_Data merge), so reuse it rather than re-loading.
	opponent_data = GameDataManager.opponent_data
	player_data   = GameDataManager.player_data


func _do_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	_click_enabled = false
	if _decided:
		GameState.clear_match_series()
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn")
	else:
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Main_Match_Core_GamePlay_Scene.tscn")
