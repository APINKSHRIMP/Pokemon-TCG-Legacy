class_name BattleFrame
extends Control

# ============================================================
# BATTLE FRAME - the shared stage behind the intro, the outro and best-of-three
# ============================================================
# All three screens are the same picture with different content in the middle
# column, so all three are built from this. Anything that appears on more than
# one of them lives here; anything that appears on exactly one lives in that
# screen's own script.
#
# WHAT THIS OWNS
#   * The Spectrum Night field, with its four radial glows and drifting chevrons.
#   * The two slanted gradient bands, coloured by outcome.
#   * Both trainers: sprite, floor glow, name, rule, deck name.
#   * The three content slots the screens fill:
#         top_slot     - 19% down, centred: the stats row or the round title
#         badge_slot   - the middle column: the VS wheel or the round chips
#         below_badge  - 21px under it: the prize count or the rewards
#   * The one-shot entrance animation, and snapping it to rest.
#
# WHAT THIS DOES NOT OWN
#   The badge itself, the stats, the rewards, the round chips, the message box.
#   Those differ per screen.
#
# -- THE CENTRING TRAP ----------------------------------------
# Centre with LAYOUT; animate with TRANSFORM; never both on the same node. Every
# animated element here is a bare wrapper Control whose only job is to be moved,
# with the laid-out content as its child. That is why there are two nodes where
# one would seem to do - and it is also what lets a sprite's floor glow travel
# through both movement phases, because the glow is a child of the drift wrapper
# rather than a sibling of the sprite.
#
# -- ONE SHOT, NOT A LOOP -------------------------------------
# Nothing here repeats. Every element travels once and rests. The only thing
# still moving after the screen settles is the badge ring's rotation and the
# field's chevron drift, and reduce motion stops both.
# ============================================================

const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

const BAND_SHADER  := "res://Scripts/Shaders/UI_Battle_Band.gdshader"
const GLOW_SHADER  := "res://Scripts/Shaders/UI_Floor_Glow.gdshader"
const TEXT_SHADER  := "res://Scripts/Shaders/UI_Gradient_Text.gdshader"
const DESAT_SHADER := "res://Scripts/Shaders/UI_Desaturate.gdshader"
const RING_SHADER  := "res://Scripts/Shaders/UI_Selection_Ring.gdshader"

# -- TWEAKABLE LAYOUT -----------------------------------------
# Bands. Height is a fraction of the screen; the overhang is EXTRA on top of it,
# pushed off the screen edge so the second, slow phase of the entrance cannot
# drag the band's far edge into view and open a gap.
const BAND_H_FRACTION : float = 0.215
const BAND_OVERHANG   : float = 38.0
# The slant, as a fraction of the band's own height, at the left and right edges.
const BAND_TOP_CUT    : Vector2 = Vector2(1.00, 0.66)
const BAND_BOTTOM_CUT : Vector2 = Vector2(0.34, 0.00)

# Stage
const STAGE_PAD_X     : float = 96.0
const STAGE_CENTRE_Y  : float = 540.0
const SPRITE_H        : float = 365.0
# Sprite drop shadow. A straight offset silhouette rather than a real blur - the
# same treatment every other sprite in the game gets, and at 15px on a 365px
# figure the difference between this and a 27px blur is not visible.
const SPRITE_SHADOW_OFF : Vector2 = Vector2(0.0, 15.0)
# Column centres. The badge column is the screen's centre line; the two trainer
# columns sit either side of it, inside the stage padding.
const COL_PLAYER_X    : float = 445.0
const COL_BADGE_X     : float = 960.0
const COL_OPPONENT_X  : float = 1475.0

# Floor glow, under the sprite's feet
const GLOW_SIZE       : Vector2 = Vector2(288.0, 69.0)
const GLOW_SOFTNESS   : float = 0.62
const GLOW_ALPHA      : float = 0.55

# Name block, below the sprite
const NAME_GAP        : float = 18.0    # sprite's feet -> name block
const NAME_FONT       : int   = 36
const NAME_TRACK_EM   : float = 0.09
const RULE_H          : float = 3.0
const RULE_W_FRACTION : float = 0.70
const RULE_GAP        : float = 10.0
const DECK_FONT       : int   = 16
const DECK_TRACK_EM   : float = 0.19
const DECK_GAP        : float = 10.0
const NAME_BLOCK_W    : float = 620.0

# The badge column
const BADGE_D         : float = 211.0
const BADGE_RING_W    : float = 7.0
const BADGE_RING_INSET: float = 10.0
const BADGE_CENTRE_Y  : float = 470.0
const BELOW_BADGE_GAP : float = 21.0
const BELOW_BADGE_W   : float = 620.0

# The top slot - stats row, round title
const TOP_SLOT_FRACTION : float = 0.19
const TOP_SLOT_H        : float = 120.0

# Loser treatment
const DESAT_GREY      : float = 0.80
const DESAT_BRIGHT    : float = 0.55

# -- TWEAKABLE TIMING -----------------------------------------
# These are the FAST numbers. GameState.transition_time() stretches every one of
# them by 1.5 at medium and 2 at slow, and collapses them all to zero under
# reduce motion, so the ratios between elements never need retuning.
const P1_TIME         : float = 0.55    # fast phase, everything that has one
const P2_TIME         : float = 1.90    # slow continued travel
const SPRITE_P1_DELAY : float = 0.10
const BAND_P1_PX      : float = 65.0    # how far behind rest phase 1 starts
const BAND_P2_PX      : float = 13.0    # how much further phase 2 carries it
const SPRITE_P1_PX    : float = 115.0
const SPRITE_P2_PX    : float = 16.0
const BLOCK_DROP_PX   : float = 65.0    # name blocks, top slot, below-badge slot
const NAME_DELAY      : float = 0.26
const SLOT_DELAY      : float = 0.34

const RING_PERIOD     : float = 3.0     # seconds per revolution


# ============================================================
# Fighter - one trainer's whole column
# ============================================================
# Three nested nodes, outermost first:
#   fast   - moved by phase 1 of the entrance
#   drift  - moved by phase 2, and the PARENT of both the sprite and its glow
#   sprite - the trainer, plus the floor glow underneath
#
# The nesting is what makes the two-phase motion possible without either tween
# fighting the other for the same property, and what keeps the glow travelling
# with the trainer.
class Fighter extends RefCounted:
	var fast: Control          # phase-1 wrapper
	var drift: Control         # phase-2 wrapper
	var sprite: TextureRect
	var glow: ColorRect
	var name_anim: Control     # the name block's own wrapper
	var name_label: Label
	var rule: ColorRect
	var deck_label: Label


# -- Public nodes ---------------------------------------------
var field: Control = null
var top_band_fast: Control = null
var top_band_drift: Control = null
var bottom_band_fast: Control = null
var bottom_band_drift: Control = null

var player: Fighter = null
var opponent: Fighter = null

## The middle column, at the badge's own size. Screens add their VS wheel or
## their three round chips to this.
var badge_slot: Control = null
## Centred under the badge. The intro's prize count, the win screen's rewards.
var below_badge: VBoxContainer = null
## 19% down, full width, centred. The stats row, or the round title.
var top_slot: Control = null

var _top_slot_anim: Control = null
var _below_badge_anim: Control = null
var _kind: String = "intro"
var _band_mats: Array = []


# ============================================================
# BUILD
# ============================================================
# `kind` is "intro", "win" or "loss" - the one word that picks the band and
# badge-ring gradient. Best-of-three passes "win" or "loss" for the latest
# round's result and re-calls set_kind() when that changes.
func setup(kind: String) -> void:
	_kind = kind
	# FULL_RECT anchors plus non-zero offsets would ADD to the parent size - a
	# full-rect Control with offset_right = 1920 comes out 3840 wide. Anchors do the
	# sizing here; every offset stays at zero.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	field = UIKit.add_field(self)
	_build_bands()
	player = _build_fighter(COL_PLAYER_X, true)
	opponent = _build_fighter(COL_OPPONENT_X, false)
	_build_badge_column()
	_build_top_slot()
	set_kind(kind)
	# Park everything at its starting offset NOW, before the screen fades in.
	prepare_entrance()


## Recolours the bands. Best-of-three calls this when the newest result flips the
## screen from green to red or back.
func set_kind(kind: String) -> void:
	_kind = kind
	var stops: Array = _ui().outcome_grad(kind)
	for mat in _band_mats:
		mat.set_shader_parameter("grad_a", stops[0])
		mat.set_shader_parameter("grad_b", stops[1])
		mat.set_shader_parameter("grad_c", stops[2])


func kind() -> String:
	return _kind


func _build_bands() -> void:
	# The band as designed: 21.5% of the screen plus the overhang that keeps the
	# slow second phase from dragging its far edge into view.
	var band_h := SCREEN_H * BAND_H_FRACTION + BAND_OVERHANG
	# Phase 1 starts the band 65px BEHIND rest, which is further than the overhang
	# covers. Rather than change the authored overhang, the RECT is extended off
	# the screen by the whole entrance travel and the cut fractions are remapped so
	# the slanted edge lands in exactly the same place. Nothing visible moves; the
	# band simply has more of itself off-screen to give.
	var extra := BAND_P1_PX + BAND_P2_PX
	var full_h := band_h + extra

	# TOP - grows UPWARD, so every cut fraction shifts down the taller rect.
	top_band_fast = Control.new()
	top_band_fast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_band_fast)
	top_band_drift = Control.new()
	top_band_drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_band_fast.add_child(top_band_drift)
	_add_band_rect(top_band_drift, Vector2(0.0, -BAND_OVERHANG - extra), full_h,
			Vector2((extra + BAND_TOP_CUT.x * band_h) / full_h,
					(extra + BAND_TOP_CUT.y * band_h) / full_h), false)

	# BOTTOM - grows DOWNWARD from an unchanged top edge, so the fractions simply
	# shrink against the taller rect.
	bottom_band_fast = Control.new()
	bottom_band_fast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_band_fast)
	bottom_band_drift = Control.new()
	bottom_band_drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_band_fast.add_child(bottom_band_drift)
	_add_band_rect(bottom_band_drift,
			Vector2(0.0, SCREEN_H + BAND_OVERHANG - band_h), full_h,
			Vector2(BAND_BOTTOM_CUT.x * band_h / full_h,
					BAND_BOTTOM_CUT.y * band_h / full_h), true)


func _add_band_rect(parent: Control, at: Vector2, h: float,
					cut: Vector2, keep_below: bool) -> void:
	var rect := ColorRect.new()
	rect.color = Color.WHITE            # the shader replaces this entirely
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = at
	rect.size = Vector2(SCREEN_W, h)

	var mat := ShaderMaterial.new()
	mat.shader = load(BAND_SHADER)
	mat.set_shader_parameter("rect_size", rect.size)
	mat.set_shader_parameter("cut_start", cut.x)
	mat.set_shader_parameter("cut_end", cut.y)
	mat.set_shader_parameter("keep_below", 1.0 if keep_below else 0.0)
	rect.material = mat
	_band_mats.append(mat)

	parent.add_child(rect)


# ============================================================
# TRAINERS
# ============================================================

func _build_fighter(centre_x: float, is_player: bool) -> Fighter:
	var ui := _ui()
	var f := Fighter.new()
	var side: Color = ui.battle_col("side_player" if is_player else "side_opponent")

	# The stage's vertical layout, worked out once so the sprite, the glow and
	# the name block all hang off the same two numbers.
	var block_h := NAME_FONT + RULE_GAP + RULE_H + DECK_GAP + DECK_FONT + 12.0
	var stage_h := SPRITE_H + NAME_GAP + block_h
	var sprite_top := STAGE_CENTRE_Y - stage_h * 0.5
	var feet_y := sprite_top + SPRITE_H

	f.fast = Control.new()
	f.fast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(f.fast)
	f.drift = Control.new()
	f.drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.fast.add_child(f.drift)

	# Floor glow FIRST, so the sprite draws over it, and a CHILD of the drift
	# wrapper so it travels through both phases with the trainer.
	f.glow = ColorRect.new()
	f.glow.color = Color.WHITE
	f.glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.glow.size = GLOW_SIZE
	f.glow.position = Vector2(centre_x - GLOW_SIZE.x * 0.5, feet_y - GLOW_SIZE.y * 0.5)
	var gmat := ShaderMaterial.new()
	gmat.shader = load(GLOW_SHADER)
	var gcol := side
	gcol.a = GLOW_ALPHA
	gmat.set_shader_parameter("glow_col", gcol)
	gmat.set_shader_parameter("softness", GLOW_SOFTNESS)
	f.glow.material = gmat
	f.drift.add_child(f.glow)

	f.sprite = TextureRect.new()
	f.sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.sprite.stretch_mode = TextureRect.STRETCH_SCALE
	f.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.sprite.flip_h = is_player
	f.sprite.position = Vector2(centre_x, sprite_top)   # width set by set_trainer()
	f.sprite.size = Vector2(0.0, SPRITE_H)
	f.drift.add_child(f.sprite)

	# -- Name block. Its own wrapper: it drops in on its own delay, and BOTH
	# blocks drop DOWN now that the opponent's sits below their sprite too.
	# No glow behind it - the floor glow belongs to the sprite alone, and putting
	# one here is what made the deck name unreadable.
	f.name_anim = Control.new()
	f.name_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(f.name_anim)

	var block_l := centre_x - NAME_BLOCK_W * 0.5
	var y := feet_y + NAME_GAP

	f.name_label = Label.new()
	f.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.name_label.add_theme_font_override("font", ui.font("name"))
	f.name_label.add_theme_font_size_override("font_size", NAME_FONT)
	f.name_label.add_theme_constant_override("font_spacing_glyph",
			int(round(NAME_TRACK_EM * float(NAME_FONT))))
	f.name_label.add_theme_color_override("font_color", ui.col("field_fg"))
	f.name_label.position = Vector2(block_l, y)
	f.name_label.size = Vector2(NAME_BLOCK_W, NAME_FONT + 12.0)
	f.name_anim.add_child(f.name_label)
	y += NAME_FONT + 12.0 + RULE_GAP

	f.rule = ColorRect.new()
	f.rule.color = side
	f.rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.rule.size = Vector2(NAME_BLOCK_W * RULE_W_FRACTION, RULE_H)
	f.rule.position = Vector2(centre_x - f.rule.size.x * 0.5, y)
	f.name_anim.add_child(f.rule)
	y += RULE_H + DECK_GAP

	f.deck_label = Label.new()
	f.deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.deck_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.deck_label.add_theme_font_override("font", ui.font_at(ui.FONT_MONO_MEDIUM))
	f.deck_label.add_theme_font_size_override("font_size", DECK_FONT)
	f.deck_label.add_theme_constant_override("font_spacing_glyph",
			int(round(DECK_TRACK_EM * float(DECK_FONT))))
	f.deck_label.add_theme_color_override("font_color", ui.col("field_mute"))
	f.deck_label.position = Vector2(block_l, y)
	f.deck_label.size = Vector2(NAME_BLOCK_W, DECK_FONT + 8.0)
	f.name_anim.add_child(f.deck_label)

	return f


## Fills one trainer's column. `tex` is an In_Battle_Sprites texture; it is scaled
## to SPRITE_H and centred on its column, so sprites of different aspect ratios
## still stand on the same floor.
func set_trainer(f: Fighter, tex: Texture2D, trainer_name: String, deck_name: String) -> void:
	var ui := _ui()
	if tex != null and tex.get_height() > 0:
		var w := tex.get_width() * (SPRITE_H / float(tex.get_height()))
		var centre_x := f.sprite.position.x
		f.sprite.texture = tex
		f.sprite.size = Vector2(w, SPRITE_H)
		f.sprite.position.x = centre_x - w * 0.5
		_add_sprite_shadow(f.sprite)

	f.name_label.text = ui.cased("name", trainer_name.replace("_", " "))
	f.deck_label.text = deck_name.replace("_", " ").to_upper()


## Greys and dims one trainer. The winner is untouched, which is what lets the
## outcome read before the word does. Never called on the best-of-three screen.
func desaturate(f: Fighter) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(DESAT_SHADER)
	mat.set_shader_parameter("grey_amount", DESAT_GREY)
	mat.set_shader_parameter("brightness", DESAT_BRIGHT)
	f.sprite.material = mat
	# The floor glow goes with them. A bright pad under a grey trainer reads as
	# a rendering mistake rather than a result.
	f.glow.modulate = Color(1.0, 1.0, 1.0, 0.35)


# ============================================================
# THE MIDDLE COLUMN
# ============================================================

func _build_badge_column() -> void:
	badge_slot = Control.new()
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_slot.position = Vector2(0.0, BADGE_CENTRE_Y - BADGE_D * 0.5)
	badge_slot.size = Vector2(SCREEN_W, BADGE_D)
	add_child(badge_slot)

	# Wrapper is animated, the VBox inside it is laid out. Never both on one node.
	_below_badge_anim = Control.new()
	_below_badge_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_below_badge_anim)

	below_badge = VBoxContainer.new()
	below_badge.alignment = BoxContainer.ALIGNMENT_BEGIN
	below_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	below_badge.position = Vector2(COL_BADGE_X - BELOW_BADGE_W * 0.5,
			BADGE_CENTRE_Y + BADGE_D * 0.5 + BELOW_BADGE_GAP)
	below_badge.size = Vector2(BELOW_BADGE_W, 0.0)
	_below_badge_anim.add_child(below_badge)


func _build_top_slot() -> void:
	_top_slot_anim = Control.new()
	_top_slot_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_slot_anim)

	top_slot = Control.new()
	top_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_slot.position = Vector2(0.0, SCREEN_H * TOP_SLOT_FRACTION)
	top_slot.size = Vector2(SCREEN_W, TOP_SLOT_H)
	_top_slot_anim.add_child(top_slot)


## The VS / WIN / LOSS wheel: a dark well, a rotating gradient ring and the word.
## The ring is the SAME shader as the card selection ring at a larger radius -
## one effect, two uses, which is what makes the badge read as part of the game
## rather than a title card.
##
## `text_kind` picks the word's own gradient: "intro", "win" or "loss".
func make_badge(text: String, text_kind: String, font_size: int) -> Control:
	var ui := _ui()
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(COL_BADGE_X - BADGE_D * 0.5, 0.0)
	holder.size = Vector2(BADGE_D, BADGE_D)

	var well := _Disc.new()
	well.fill = ui.battle_col("badge_well")
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.size = Vector2(BADGE_D, BADGE_D)
	holder.add_child(well)

	holder.add_child(make_ring(Vector2(BADGE_D, BADGE_D), _kind, true))

	# The label is sized to the TEXT, not to the badge, and centred by position. The
	# gradient shader ramps across the whole control, so a 211px-wide label holding a
	# 90px word would leave the glyphs sampling only the middle of the ramp - which
	# reads as one flat colour instead of a sweep.
	var font: Font = ui.font("title")
	var text_w: float = font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.position = Vector2((BADGE_D - text_w) * 0.5, 0.0)
	lbl.size = Vector2(text_w, BADGE_D)
	_apply_text_gradient(lbl, text_kind, text_w)
	holder.add_child(lbl)

	return holder


## A ring on its own, at any size - the badge uses one, the best-of-three chips
## use one each. `spinning` false leaves a static gradient, which is how the
## older round chips are told apart from the newest one.
func make_ring(ring_size: Vector2, grad_kind: String, spinning: bool,
			   width: float = BADGE_RING_W, inset: float = BADGE_RING_INSET) -> ColorRect:
	var ui := _ui()
	var stops: Array = ui.outcome_grad(grad_kind)

	var ring := ColorRect.new()
	ring.color = Color.WHITE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = ring_size

	var mat := ShaderMaterial.new()
	mat.shader = load(RING_SHADER)
	mat.set_shader_parameter("rect_size", ring_size)
	mat.set_shader_parameter("grad_a", stops[0])
	mat.set_shader_parameter("grad_b", stops[1])
	mat.set_shader_parameter("grad_c", stops[2])
	mat.set_shader_parameter("ring_width", width)
	mat.set_shader_parameter("inset", inset)
	# A radius of half the rect turns the shader's rounded rect into a circle.
	mat.set_shader_parameter("corner_radius", min(ring_size.x, ring_size.y) * 0.5)
	# Reduced motion freezes the gradient rather than removing the ring.
	var spin: float = TAU / RING_PERIOD if spinning else 0.0
	mat.set_shader_parameter("spin_speed", 0.0 if ui.motion_reduced() else spin)
	ring.material = mat
	return ring


## Fills a label's glyphs with one of the badge gradients. `width` must be the
## label's real width - the shader ramps across the whole control, and a wrong
## width clamps every letter to one end of the ramp.
func _apply_text_gradient(lbl: Label, grad_kind: String, width: float) -> void:
	var stops: Array = _ui().outcome_text_grad(grad_kind)
	var mat := ShaderMaterial.new()
	mat.shader = load(TEXT_SHADER)
	mat.set_shader_parameter("grad_a", stops[0])
	mat.set_shader_parameter("grad_b", stops[1])
	mat.set_shader_parameter("grad_c", stops[2])
	mat.set_shader_parameter("grad_b_pos", 0.5)
	mat.set_shader_parameter("rect_w", width)
	lbl.material = mat


# A plain filled circle. Used for the badge well and the best-of-three discs.
class _Disc extends Control:
	var fill: Color = Color(0.0, 0.0, 0.0, 0.55)

	func _draw() -> void:
		draw_circle(size * 0.5, min(size.x, size.y) * 0.5, fill)


## Parks every moving element at its STARTING offset, before anything is visible.
##
## Called at the end of setup(), which is the whole point: the screen fades in from
## black BEFORE play_entrance() runs, and if the elements were still at rest during
## that fade the player would watch the finished picture appear and then jump back
## to the start when the tweens began. Parking first means the fade reveals the
## pre-animation state, which is what the entrance then moves away from.
func prepare_entrance() -> void:
	var gs := _gs()
	if gs.transition_time(P1_TIME) <= 0.0:
		# Reduce motion: there is no entrance to prepare for.
		snap_to_rest()
		return

	top_band_fast.position = Vector2(0.0, BAND_P1_PX)
	bottom_band_fast.position = Vector2(0.0, -BAND_P1_PX)
	player.fast.position = Vector2(SPRITE_P1_PX, 0.0)
	opponent.fast.position = Vector2(-SPRITE_P1_PX, 0.0)
	top_band_drift.position = Vector2.ZERO
	bottom_band_drift.position = Vector2.ZERO
	player.drift.position = Vector2.ZERO
	opponent.drift.position = Vector2.ZERO

	# ISSUE #289: parked INVISIBLE as well as parked offset. Everything that flies
	# in was fully opaque and stationary while the screen faded up, so the eye had
	# already read the finished picture before anything moved and the entrance
	# looked like a twitch rather than an arrival. Same reasoning as
	# prepare_entrance itself, applied to opacity instead of position.
	for anim in [player.name_anim, opponent.name_anim, _top_slot_anim, _below_badge_anim]:
		anim.position = Vector2(0.0, -BLOCK_DROP_PX)
		anim.modulate.a = 0.0


# ============================================================
# THE ENTRANCE
# ============================================================
# Four elements move in two chained phases - fast in, then slow continued travel
# in the SAME direction, easing to a stop. Everything else is a single move down.
#
# Phase 1 is a hard deceleration (EXPO out), phase 2 a gentle settle (CUBIC out).
# Those are the closest Godot curves to the two beziers in the design, and the
# feel they carry is "momentum bleeding off" rather than "a hard landing".
#
# Everything starts from where prepare_entrance() parked it, so this never moves
# anything instantly - a jump here is what the two-step split exists to avoid.
# The screen's own fade from black covers the opacity ramp; there is deliberately
# no second fade on this node.
#
# Awaiting this returns when the whole sequence has finished. It is safe to not
# await it: every tween is bound to a node, so a scene change kills them.
func play_entrance() -> void:
	var gs := _gs()
	var p1: float = gs.transition_time(P1_TIME)
	var p2: float = gs.transition_time(P2_TIME)
	var sprite_delay: float = gs.transition_time(SPRITE_P1_DELAY)
	var total: float = sprite_delay + p1 + p2

	# Reduce motion collapses every duration to zero, so the whole screen is at
	# rest on the first frame. Nothing is skipped, it simply does not move.
	if total <= 0.0:
		snap_to_rest()
		return

	_two_phase(top_band_fast, top_band_drift, Vector2(0.0, BAND_P1_PX),
			Vector2(0.0, -BAND_P2_PX), 0.0, p1, p2)
	_two_phase(bottom_band_fast, bottom_band_drift, Vector2(0.0, -BAND_P1_PX),
			Vector2(0.0, BAND_P2_PX), 0.0, p1, p2)
	_two_phase(player.fast, player.drift, Vector2(SPRITE_P1_PX, 0.0),
			Vector2(-SPRITE_P2_PX, 0.0), sprite_delay, p1, p2)
	_two_phase(opponent.fast, opponent.drift, Vector2(-SPRITE_P1_PX, 0.0),
			Vector2(SPRITE_P2_PX, 0.0), sprite_delay, p1, p2)

	# Both name blocks move DOWN. The opponent's used to move up because it sat
	# above their sprite; it sits below now, so the two match.
	var name_delay: float = gs.transition_time(NAME_DELAY)
	drop_in(player.name_anim, name_delay)
	drop_in(opponent.name_anim, name_delay)

	var slot_delay: float = gs.transition_time(SLOT_DELAY)
	drop_in(_top_slot_anim, slot_delay)
	drop_in(_below_badge_anim, slot_delay)

	await get_tree().create_timer(total).timeout


## One element's single-phase drop. Public because the screens reuse it for the
## pieces they own - the REWARDS label, a round title.
##
## ISSUE #289: the element FADES UP AS IT TRAVELS. It starts fully transparent and
## reaches full opacity as it lands, so a line of text arrives rather than being
## already there and then jumping. The fade runs on its own tween in parallel with
## the move: putting both on one sequential tween would play them one after the
## other, and a tween bound to the node dies with it either way.
## FADE_SHARE is how much of the travel the fade takes - finishing slightly early
## keeps the last of the movement readable rather than still half-invisible.
const DROP_FADE_SHARE := 0.75

func drop_in(node: Control, delay: float, duration: float = -1.0,
			 distance: float = BLOCK_DROP_PX) -> void:
	if node == null:
		return
	var gs := _gs()
	var dur: float = duration if duration >= 0.0 else gs.transition_time(P1_TIME)
	if dur <= 0.0 and delay <= 0.0:
		node.position = Vector2.ZERO
		node.modulate.a = 1.0
		return
	node.position = Vector2(0.0, -distance)
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "position", Vector2.ZERO, dur)

	var fade := node.create_tween()
	if delay > 0.0:
		fade.tween_interval(delay)
	fade.tween_property(node, "modulate:a", 1.0, maxf(dur * DROP_FADE_SHARE, 0.01))


# Sets up one element's two chained phases. `from` is where the FAST wrapper
# starts relative to rest; `carry` is how much further the DRIFT wrapper travels
# afterwards, in the same direction.
func _two_phase(fast: Control, drift: Control, from: Vector2, carry: Vector2,
				delay: float, p1: float, p2: float) -> void:
	fast.position = from
	drift.position = Vector2.ZERO

	var tw1 := fast.create_tween()
	tw1.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tw1.tween_interval(delay)
	tw1.tween_property(fast, "position", Vector2.ZERO, p1)

	var tw2 := drift.create_tween()
	tw2.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_interval(delay + p1)
	tw2.tween_property(drift, "position", carry, p2)


## Everything at its final resting position, immediately. Used by reduce motion
## and by anything that needs the screen settled without waiting for it.
func snap_to_rest() -> void:
	modulate.a = 1.0
	top_band_fast.position = Vector2.ZERO
	top_band_drift.position = Vector2(0.0, -BAND_P2_PX)
	bottom_band_fast.position = Vector2.ZERO
	bottom_band_drift.position = Vector2(0.0, BAND_P2_PX)
	player.fast.position = Vector2.ZERO
	player.drift.position = Vector2(-SPRITE_P2_PX, 0.0)
	opponent.fast.position = Vector2.ZERO
	opponent.drift.position = Vector2(SPRITE_P2_PX, 0.0)
	# ISSUE #289: at rest is fully opaque - reduce motion and click-to-skip both
	# land here, and neither may leave an element invisible.
	for anim in [player.name_anim, opponent.name_anim, _top_slot_anim, _below_badge_anim]:
		anim.position = Vector2.ZERO
		anim.modulate.a = 1.0


# ============================================================
# SHARED CONTENT HELPERS
# ============================================================

## One item of the stats row: a small mono label over a big value. Used by both
## the win and the loss screen, in the identical position, because they are the
## same frame with different content.
func make_stat(stat_label: String, value: String) -> VBoxContainer:
	var ui := _ui()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var k := Label.new()
	k.text = stat_label.to_upper()
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_theme_font_override("font", ui.font_at(ui.FONT_MONO_MEDIUM))
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_constant_override("font_spacing_glyph", int(round(0.17 * 14.0)))
	k.add_theme_color_override("font_color", ui.col("field_mute"))
	box.add_child(k)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_font_override("font", ui.font("title"))
	v.add_theme_font_size_override("font_size", 31)
	v.add_theme_color_override("font_color", ui.col("field_fg"))
	box.add_child(v)

	return box


func _ui() -> Node:
	return Engine.get_main_loop().get_root().get_node_or_null("/root/UITheme")


func _gs() -> Node:
	return Engine.get_main_loop().get_root().get_node_or_null("/root/GameState")


# The sprite's own drop shadow: the same silhouette, offset down, drawn behind.
# Not UIKit.add_drop_shadow(), which places its shadow by ANCHOR FRACTIONS so the
# offset scales with the item - right for a grid of packs and coins, wrong here,
# where the design asks for the same 15px under trainers of very different heights.
func _add_sprite_shadow(item: TextureRect) -> void:
	if item.texture == null:
		return
	var shadow := TextureRect.new()
	shadow.name = "sprite_shadow"
	shadow.texture = item.texture
	shadow.expand_mode = item.expand_mode
	shadow.stretch_mode = item.stretch_mode
	shadow.texture_filter = item.texture_filter
	shadow.flip_h = item.flip_h
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.size = item.size
	shadow.position = SPRITE_SHADOW_OFF
	shadow.modulate = _ui().battle_col("sprite_shadow")
	shadow.show_behind_parent = true
	item.add_child(shadow)


## How long a screen should SIT there once it has settled, at the player's speed
## preset. Same multiplier as every duration, but it never collapses to zero:
## reduce motion removes the movement, not the screen, so the player is still
## told who they are fighting or how the match went.
func hold_time(base_seconds: float) -> float:
	var gs := _gs()
	var mult: float = float(gs.TRANSITION_SPEED_PRESETS.get(gs.animation_speed_setting, 1.0))
	return base_seconds * mult
