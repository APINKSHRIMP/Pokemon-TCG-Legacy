extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const MAX_NAME_LENGTH    := 21
const OWNED_CARDS_FOLDER := "user://Player_Owned_Cards"
const OWNED_CARDS_SUFFIX := "_player_owned_cards.json"

# ISSUE #134: the cosmetic-collection folder constants that used to sit here now live in
# GameState (COIN_ASSET_FOLDER / COSTUME_ASSET_FOLDER / SLEEVE_SMALL_FOLDER / COIN_BACK_IMAGE /
# DEFAULT_SLEEVE_PREFIX), so the X / Y counters below and the CHT.All_* cheats read one list.

# Godot centres a Label on the full ascent+descent box, but kenvector_future is caps-only, so
# the empty descent space parks the visible ink below the middle of the bar. Measured off a
# render: 10px of bar above the caps and 5px below, so lift the row by half that difference.
const STAT_TEXT_Y_NUDGE := -2.5          # screen px, negative is up

# Largest size whose line height still clears the 33px bar (measured in Godot with the theme font:
# 32px at 28, but 35px at 30). kenvector_future is caps-only, so labels render uppercase whatever
# case the string is in.
const STAT_FONT_SIZE  := 28

# DOB / cash block under the name box — two centred lines in the one 614x115 Label.
const DOB_CASH_FONT_SIZE    := 32
const DOB_CASH_LINE_SPACING := 14



# Colour-change burst. Same particle recipe as Coin_Shop_Script._start_sparkle — same scale range,
# same four-stop gradient, same palette — with three changes: one_shot so it never re-emits, a
# lifetime 40% shorter than the coin sparkle’s 0.9s so the burst is over quickly, and explosiveness
# just under 1.0. At exactly 1.0 every pixel spawns on the same frame, which reads as a single flat
# flash; 0.9 spreads the spawns over lifetime x (1 - explosiveness) — about 54ms — so the glitter
# stutters in. The count dwarfs the coin sparkle’s 20 because the emission rectangle is the whole
# card rather than an 80px coin.
const SPARKLE_AMOUNT        := 450
const SPARKLE_LIFETIME      := 0.54
const SPARKLE_EXPLOSIVENESS := 0.9
const SPARKLE_COLOURS       := {
	"blue":   Color(0.3,  0.5,  1.0),
	"green":  Color(0.2,  0.9,  0.3),
	"yellow": Color(1.0,  0.85, 0.2),
	"red":    Color(1.0,  0.2,  0.2),
	"white":  Color(1.0,  1.0,  1.0),
}

# Target display sizes — uniform regardless of source image dimensions.
## ISSUE #200: the costume's fit box went 230x300 -> 322x420 -> 386x504, and is
## now DERIVED rather than written down at all — see SPRITE_SIZE further down,
## which takes whatever the top panel has left after the name field and the dates.

# ── Layout (UI overhaul) ─────────────────────────────────────────────────────
# TWEAKABLE. Left column is the trainer; the right column carries every stat.
const SET_DICT_PATH := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"

## basep (Wizard Promos) and np (EX Promos) are gift-only, so they can never be
## completed by playing and must not sit at the top of the nearest-sets list.
const PROMO_SET_IDS := ["basep", "np"]
const NEAREST_SETS  := 3

## ISSUE #201 (retest): THE LEFT COLUMN IS 50% WIDER (300 -> 450) AND THE RIGHT
## ONE GIVES UP EXACTLY THAT WIDTH. The name box had 264px of usable width for a
## 21-character name at font 36, so a long name ran straight off the end of the
## box; widening the column is what actually fixes that, and it also makes room
## for the 40%-bigger costume sprite (#200). The right column keeps the same
## 34px gutter on both sides, so nothing else on the screen has to move.
const PANEL_PAD      := 18.0
const LEFT_X         := 34.0
const LEFT_W         := 450.0
const LEFT_Y         := 104.0
## ISSUE #200 (retest 2): 800 -> 880. A 504px sprite plus the name box, the dates
## and the equipped pair does not fit in an 800px panel however tight the gaps
## get, and the room the fix asks for is genuinely there: the content band runs to
## UIKit.CONTENT_BOTTOM (988) and the right column's last panel stops at 904, so
## the left panel can reach 984 without touching anything on the screen.
## ISSUE #200 (retest 3): THE LEFT COLUMN IS TWO BOXES, NOT ONE.
##
## The user asked for the trainer half and the equipped half to be separate
## panels, each lining up with a panel opposite it in the right column - so the
## screen reads as a 2x3 grid of boxes rather than one tall slab beside three
## short ones. Both are DERIVED from the right column's own constants, because
## "in line with" is the whole point: nudge BOX_Y or SETS_Y and the left column
## follows instead of quietly drifting out of alignment.
##
##   TOP box    LEFT_Y .. bottom of the "Matches won" box   (BOX_Y + BOX_H)
##   BOTTOM box exactly the "Set completion" band           (SETS_Y .. + SETS_H)
##
## LEFT_H is gone: neither box is 880 tall and nothing else used it.
const LEFT_TOP_Y     := LEFT_Y
const LEFT_TOP_H     := BOX_Y + BOX_H - LEFT_Y
const LEFT_BOT_Y     := SETS_Y
const LEFT_BOT_H     := SETS_H
const RIGHT_X        := 518.0
const RIGHT_W        := 1368.0

## ISSUE #203: EVERY font on this screen is 50% larger except the "Trainer card"
## title in the header and the button labels — those two are chrome and take their
## roles straight from UITheme. Read the sizes through _stat_font() rather than
## writing numbers, so the multiplier stays in one place.
##
## The panels below were re-measured to hold the bigger type: every row, panel and
## band grew with it, and the three panels still stack inside the 104..904 band.
const STAT_FONT_SCALE := 1.5

const METER_Y        := 104.0
const METER_H        := 386.0
const METER_ROW_H    := 58.0
const METER_LABEL_W  := 300.0
const METER_VALUE_W  := 180.0
const METER_ROW_H_TXT := 32.0    # height of a row's label / value box

const BOX_Y          := 510.0
const BOX_H          := 158.0
const BOX_GAP        := 18.0
const BOX_VALUE_FONT := 60

const SETS_Y         := 688.0
const SETS_H         := 216.0

## The left panel's vertical rhythm, top to bottom. ALL TWEAKABLE — every gap in
## _build_left_panel is one of these, so the stack can be retuned from here
## without reading the builder.
## ISSUE #200 (retest 3): SPRITE_TOP_GAP 20 -> 10 is the "move the sprite, the
## name box and the dates up 10 pixels" - the three are one measured stack, so
## lifting its head lifts all of it and the gaps between them are untouched.
const SPRITE_TOP_GAP := 10.0   # top box top -> top of the costume art (ISSUE #200)
const NAME_TOP_GAP   := 10.0   # bottom of the ART -> name box     (ISSUE #200)
const DOB_H          := 56.0   # height of the "Trainer since / $" block
const EQUIP_TOP_GAP  := 14.0   # bottom box top -> thumbnails      (ISSUE #200)
## ISSUE #200 (retest 3): "move the sleeve and coin down 10 pixels", inside their
## own box. 14 + 10 = 24 off the top, which leaves 26 under the captions - the
## pair sits very nearly centred in the band.
const EQUIP_DOWN_NUDGE := 10.0

## Equipped thumbnails under the costume sprite. The "Equipped" heading that used
## to sit over them was removed in #200 — each thumbnail captions itself.
## ISSUE #200 (retest 2): EQUIP_GAP 18 -> 28. (retest 4): 28 -> 140 - the user
## said 28 looked no different from 18, and it did not: 10px between two 96px
## thumbnails is inside the noise. 140 puts them at opposite ends of the box
## instead of side by side. The pair is 2*96 + 140 = 332 wide, centred in the
## 450px panel, so 59px of margin each side.
const EQUIP_SIZE     := Vector2(96.0, 132.0)
const EQUIP_GAP      := 140.0
const MEDALS_BTN_W   := 240.0
const NAME_BOX_H     := 62.0
## ISSUE #203: +50% (24 -> 36). ISSUE #201 (retest): -25% again (36 -> 27) - at
## 36 a full-length name overran the box no matter how wide it was.
const NAME_FONT      := 27
## ISSUE #201 (retest): how far the name box overhangs the panel padding on EACH
## side. Small on purpose: it is a text field, not a panel.
const NAME_BOX_BLEED := 5.0
## ISSUE #204: gap between the name box and the "Trainer since" / cash lines. It
## was 10px and the two read as one block. ISSUE #200 (retest 2): -5 (24 -> 19).
const DOB_GAP        := 19.0

## ISSUE #200 (retest 3): THE FIT BOX IS WHATEVER IS LEFT, NOT A NUMBER.
##
## The top box is now pinned top and bottom (LEFT_TOP_H), and the name field, the
## dates and the gaps between them are fixed heights - so the costume art gets the
## remainder, and it is computed rather than guessed. That is the honest cost of
## the alignment the redesign asks for: at 504 tall the sprite alone was most of a
## 564px box, so it comes down to ~389.
##
## Only the BOX has a shape of its own - _apply_fit_size letterboxes the real art
## inside it and keeps the art's aspect, which is what #200 was logged for.
const SPRITE_FIT_H  := LEFT_TOP_H - (SPRITE_TOP_GAP + NAME_TOP_GAP
	+ NAME_BOX_H + DOB_GAP + DOB_H + PANEL_PAD)

## ISSUE #200 (retest 4): +25%, AND IT IS THE *WIDTH* THAT DELIVERS IT.
##
## Nearly every in-battle sprite on disk is SQUARE (160x160, 180x180, 928x928 -
## 250 of the 258 files). Fitted into the 298x389 portrait box the previous pass
## derived, a square sprite letterboxes on WIDTH and renders 298x298, leaving
## ~91px of dead space underneath it. So making the BOX taller would have changed
## nothing on screen at all, and the box could not get taller anyway without
## breaking the alignment with the Matches won panel that the same row asked for.
##
## 298 * 1.25 = 372. That fits the panel's 414px of inner width (450 - 2*18), and
## it is still under SPRITE_FIT_H, so the +25% costs the top box nothing and its
## bottom edge stays exactly level with Matches won.
##
## The name field and the dates need no numbers of their own: _build_left_panel
## measures them from the BOTTOM OF THE ART, so they move down 74px by themselves.
const SPRITE_FIT_W  := 372.0
const SPRITE_SIZE   := Vector2(SPRITE_FIT_W, SPRITE_FIT_H)

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH

# ─── State ───────────────────────────────────────────────────────────────────

var saved_player_name : String = ""

var _cheat_label       : RichTextLabel = null   # ISSUE #132: RichTextLabel, for the [rainbow] BBCode
var _cheat_label_token : int   = 0

var _sparkle : CPUParticles2D = null

# ─── Node references ─────────────────────────────────────────────────────────

@onready var name_box      : LineEdit    = $"player_name"
@onready var dob_cash_lbl  : Label       = $"dobandcash"
@onready var audio_player = AudioStreamPlayer.new()
@onready var save_btn      : Button      = $"info_save_button"
@onready var cancel_btn    : Button      = $"info_cancel_button"
@onready var medals_btn    : Button      = $"medals_button"
@onready var player_sprite : TextureRect = $"PlayerSprite"
@onready var stats_control : Control     = $"statistics"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ISSUE #128: every sub-menu plays the same track. This screen had none, so it ran on
	# whatever the main menu was still playing behind it -- and once that overlap was fixed
	# (Main_Menu_Script.pause_music) it would have been left silent instead.
	add_child(audio_player)
	var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
	audio_player.stream = audio_stream
	audio_player.bus = SoundManagerScript.MUSIC_BUS
	if audio_stream != null:
		audio_stream.loop = true
		audio_player.play()


	# ISSUE #200 (retest 2): DATA FIRST, THEN LAYOUT. The stack below the costume is
	# measured from the bottom of the ART, and the art's real height is not known
	# until its texture has been loaded and fitted — so _build_chrome (which calls
	# _build_left_panel) has to run after the sprite exists, not before it.
	_load_player_data()
	_build_chrome()

	name_box.max_length = MAX_NAME_LENGTH
	name_box.alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_box.text_changed.connect(_on_name_changed)

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_populate_stats()


## Swaps the old chrome for the Spectrum Night bars and lays out the left column.
##
## THE TRAINER CARD ARTWORK IS GONE. This screen used to be a drawn card with the
## stat rows painted onto bars in the image and five colour variants the player
## cycled by clicking it. All of it was retired in the UI overhaul; the stats are
## real controls now, which is what let them become meters and boxes.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "Trainer card")

	# The medals screen does not exist yet, so the button is left as it is —
	# present, styled, and wired to nothing. Do not invent a count for it.
	UIKit.adopt_button(medals_btn, bars["header"].right, "secondary", false)
	medals_btn.custom_minimum_size.x = MEDALS_BTN_W

	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")
	UIKit.adopt_button(save_btn, bars["footer"].centre, "primary")

	# stats_control is the parent every stat panel is added to; it spans the whole
	# content band now rather than the nine painted bars it used to sit on.
	stats_control.position = Vector2.ZERO
	stats_control.size = Vector2(UIKit.SCREEN_W, UIKit.SCREEN_H)
	# ISSUE #201: THIS IS WHY THE NAME BOX COULD NOT BE CLICKED. stats_control now
	# spans the whole screen, it is a later sibling than player_name, and Godot
	# picks GUI input by walking siblings in REVERSE order — so a Control with the
	# default MOUSE_FILTER_STOP sitting over everything swallowed every click on
	# the box beneath it. Its panels are already IGNORE; the container was not.
	stats_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_left_panel()


## The trainer: costume sprite, name, date, cash — and beneath the sprite, the
## other two equipped cosmetics.
##
## The costume is NOT repeated in an equipped row. It is already the sprite at the
## top of this panel, and showing it twice was the thing the user flagged; the
## sleeve and coin sit under it instead.
func _build_left_panel() -> void:
	# ISSUE #200 (retest 3): TWO panels, both in the same UIKit.make_panel() style
	# as the three opposite them. The top one ends level with the "Matches won"
	# box; the bottom one occupies exactly the "Set completion" band, top and
	# bottom. See LEFT_TOP_H / LEFT_BOT_Y - both are derived from the right
	# column, so the alignment cannot drift.
	var top_panel := UIKit.make_panel()
	top_panel.position = Vector2(LEFT_X, LEFT_TOP_Y)
	top_panel.size = Vector2(LEFT_W, LEFT_TOP_H)
	top_panel.custom_minimum_size = top_panel.size
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_panel)

	var bot_panel := UIKit.make_panel()
	bot_panel.position = Vector2(LEFT_X, LEFT_BOT_Y)
	bot_panel.size = Vector2(LEFT_W, LEFT_BOT_H)
	bot_panel.custom_minimum_size = bot_panel.size
	bot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bot_panel)

	var centre_x := LEFT_X + LEFT_W * 0.5

	# ISSUE #200/#201/#202: ONE VERTICAL STACK, measured top-down, so the sprite and
	# the wider column cannot push the dates out of the bottom of the panel. Every
	# gap below is a named constant, and SPRITE_FIT_H is the remainder after them -
	# so the sum fits LEFT_TOP_H by construction rather than by luck.
	var sprite_y := LEFT_TOP_Y + SPRITE_TOP_GAP

	# The scene left scale = (2,2) on this node, from when the sprite was drawn
	# small onto the card art and doubled. It is sized to a real box now, so the
	# doubling has to go or it bursts out of the panel.
	# The scene left scale = (2,2) on this node. Sized to a real box now, so it goes.
	# _load_player_data has already fitted the art inside SPRITE_SIZE (see _ready),
	# so its size is left alone here — overwriting it with the full box is the
	# stretch #200 started out as. Only a save with no costume falls back to the box.
	player_sprite.scale = Vector2.ONE
	if player_sprite.texture == null:
		player_sprite.size = SPRITE_SIZE
		player_sprite.custom_minimum_size = SPRITE_SIZE
	player_sprite.position = Vector2(centre_x - player_sprite.size.x * 0.5, sprite_y)

	# ISSUE #200 (retest 2): the name box rides NAME_TOP_GAP under the BOTTOM OF THE
	# ART, not under the bottom of the fit BOX. A portrait sprite letterboxed into
	# this box can leave 80px of empty space beneath it, and measuring from the box
	# put the name that far adrift of the costume.
	var art_bottom: float = sprite_y + SPRITE_SIZE.y
	if player_sprite.texture != null and player_sprite.size.y > 1.0:
		art_bottom = player_sprite.position.y + player_sprite.size.y
	var name_y := art_bottom + NAME_TOP_GAP
	# ISSUE #201: NAME_BOX_BLEED wider on each side than the panel padding.
	name_box.position = Vector2(LEFT_X + PANEL_PAD - NAME_BOX_BLEED, name_y)
	name_box.size = Vector2(LEFT_W - PANEL_PAD * 2.0 + NAME_BOX_BLEED * 2.0, NAME_BOX_H)
	name_box.custom_minimum_size = name_box.size
	name_box.theme = null
	name_box.add_theme_color_override("font_color", Color.WHITE)
	name_box.add_theme_font_override("font", UITheme.font("name"))
	name_box.add_theme_font_size_override("font_size", NAME_FONT)

	dob_cash_lbl.theme = null
	# ISSUE #203: +50%. ISSUE #204: DOB_GAP below the name box, not 10px.
	UIKit.style_label(dob_cash_lbl, "small_label", "field_mute", _stat_font("small_label"))
	dob_cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dob_y := name_y + NAME_BOX_H + DOB_GAP
	dob_cash_lbl.position = Vector2(LEFT_X + PANEL_PAD, dob_y)
	dob_cash_lbl.size = Vector2(LEFT_W - PANEL_PAD * 2.0, DOB_H)

	# ── Equipped: sleeve and coin ──
	# ISSUE #200 (retest 2): THE "EQUIPPED" HEADING IS GONE. Each thumbnail already
	# carries its own caption ("Sleeve", "Coin"), so the heading was labelling two
	# things that were labelled, and it was the row that had pushed the captions
	# out of the bottom of the panel when the thumbnails moved down for #202.
	# Removing it is what buys the space back.
	var data := _read_current_data()
	# ISSUE #200 (retest 3): the pair lives in the BOTTOM panel now and is measured
	# from that panel's own top, not from the bottom of the dates in the panel
	# above - the two boxes are independent, which is the point of splitting them.
	var total_w := EQUIP_SIZE.x * 2.0 + EQUIP_GAP
	var x := centre_x - total_w * 0.5
	var thumb_y := LEFT_BOT_Y + EQUIP_TOP_GAP + EQUIP_DOWN_NUDGE
	print("ISSUE #200 FIX ACTIVE: top box ", LEFT_TOP_Y, "..", LEFT_TOP_Y + LEFT_TOP_H,
		" (sprite ", sprite_y, " fit ", SPRITE_SIZE, ", name ", name_y, ", dates ", dob_y,
		") / bottom box ", LEFT_BOT_Y, "..", LEFT_BOT_Y + LEFT_BOT_H, " (equipped ", thumb_y, ")")

	var sleeve := String(data.get("sleeve", ""))
	if sleeve != "":
		_add_equipped_thumb(GameState.SLEEVE_SMALL_FOLDER + "/" + sleeve + ".jpg",
			Vector2(x, thumb_y), "Sleeve")
	x += EQUIP_SIZE.x + EQUIP_GAP

	var coin := String(data.get("coin", ""))
	if coin != "":
		if not coin.ends_with(".png"):
			coin += ".png"
		_add_equipped_thumb(GameState.COIN_ASSET_FOLDER + "/" + coin,
			Vector2(x, thumb_y), "Coin")


## One equipped-cosmetic thumbnail with its caption underneath.
func _add_equipped_thumb(path: String, pos: Vector2, caption: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.position = pos
	rect.size = EQUIP_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	var lbl := Label.new()
	UIKit.set_label(lbl, "small_label", caption, "field_mute", _stat_font("small_label"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(pos.x, pos.y + EQUIP_SIZE.y + 4.0)
	lbl.size = Vector2(EQUIP_SIZE.x, 30.0)
	add_child(lbl)


## Player_Current_Data.json as a Dictionary, or empty on failure.
func _read_current_data() -> Dictionary:
	var f := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}



# ─── Data loading ────────────────────────────────────────────────────────────

func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Info: cannot open " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Info: player_data.json is malformed")
		return

	# Name
	saved_player_name = data.get("name", "")
	name_box.text = saved_player_name

	# DOB and cash share one centred Label under the name box - see _style_dob_cash_label().
	var dob: String = data.get("date_of_birth", "")
	dob_cash_lbl.text = "Trainer since " + (dob if dob != "" else "--/--") + "\n$" + str(GameState.get_cash())

	# Battle sprite — fit inside SPRITE_SIZE so different-shaped sprites all appear the same size
	var sprite_name: String = data.get("sprite", "")
	if sprite_name != "":
		if not sprite_name.ends_with(".png"):
			sprite_name += ".png"
		var tex := load(SPRITE_FOLDER + "/" + sprite_name) as Texture2D
		if tex:
			_apply_fit_size(player_sprite, tex, SPRITE_SIZE)
			# ISSUE #200: recentre in BOTH axes. A wide sprite fitted into the
			# taller box leaves letterboxing at the bottom, which used to read as
			# the sprite sitting high in the panel.
			player_sprite.position.x = LEFT_X + LEFT_W * 0.5 - player_sprite.size.x * 0.5
			# ISSUE #200 (retest 2): the art is TOP-aligned in its fit box now, not
			# centred — "the top of the sprite about 20 pixels under the top of the
			# box". Centring it in a box a fifth taller than the art pushed a wide
			# costume down into the name field.
			player_sprite.position.y = LEFT_Y + SPRITE_TOP_GAP
			print("ISSUE #200 FIX ACTIVE: costume sprite fitted to ", player_sprite.size, " in a ", SPRITE_SIZE, " box")


# ─── DOB / cash label ─────────────────────────────────────



# ─── Trainer-card colour cycling ───────────────────────────











## ISSUE #203: a type role's size, scaled up for this screen only. Pass the result
## as style_label / set_label's `size_px` so the face, tracking and casing of the
## role are all kept — only the size changes.
func _stat_font(role: String) -> int:
	return int(round(float(UITheme.size(role)) * STAT_FONT_SCALE))


# ─── Uniform image sizing ────────────────────────────────────────────────────

# Scales the texture to fit entirely inside target (letterbox / minf).
# Sets size explicitly — does not rely on the layout engine.
func _apply_fit_size(rect: TextureRect, tex: Texture2D, target: Vector2) -> void:
	var tex_size := tex.get_size()
	var s        := minf(target.x / tex_size.x, target.y / tex_size.y)
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture      = tex
	# ISSUE #200: CLEAR THE MINIMUM SIZE FIRST. _build_left_panel sets
	# custom_minimum_size to the full 230x300 box, and Godot clamps `size` up to
	# the combined minimum — so the fitted size below was silently thrown away and
	# a portrait sprite was stretched to fill a wider box. The fit maths was always
	# right; the minimum was overruling it.
	rect.custom_minimum_size = Vector2.ZERO
	rect.size         = Vector2(tex_size.x * s, tex_size.y * s)


# ─── Name box ────────────────────────────────────────────────────────────────

func _on_name_changed(_new_text: String) -> void:
	_refresh_save_button_state()


# ─── Save button state ───────────────────────────────────────────────────────

func _refresh_save_button_state() -> void:
	var name_changed := name_box.text.strip_edges() != saved_player_name
	if name_changed:
		save_btn.disabled = false
		UIKit.style_button(save_btn, "good")
	else:
		save_btn.disabled = true
		UIKit.style_button(save_btn, "primary")


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Info: cannot read " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Info: player_data.json is malformed")
		return

	var new_name := name_box.text.strip_edges()
	if new_name != "":
		data["name"]      = new_name
		saved_player_name = new_name

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("Info: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	save_btn.disabled = true
	UIKit.style_button(save_btn, "primary")

	var cheat_msg := CheatManager.check_and_apply(new_name)
	if cheat_msg != "":
		_flash_cheat_message(cheat_msg)
		# ISSUE #133 FIX: the cheats that just ran can move almost every counter on this card —
		# cards owned, sets unlocked, sets completed, coins, costumes, sleeves — but the stat rows
		# were built once in _ready() and never touched again, so the player had to leave and
		# re-enter the trainer card to see any of it. Rebuild them in place instead.
		# Deliberately gated on cheat_msg: a plain name change moves nothing, so a normal Save
		# does not pay for a full collection rescan.
		_populate_stats()


func _on_cancel_pressed() -> void:
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape key ──────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Statistics ──────────────────────────────────────────────────────────────

func _populate_stats() -> void:
	# ISSUE #133: callable more than once — the Save button rebuilds these rows after a cheat has
	# changed the underlying numbers.
	for old_row in stats_control.get_children():
		stats_control.remove_child(old_row)
		old_row.free()

	var prog := GameState.progress
	var packs_opened : int = int(prog.get("packs_opened_total", 0))
	var matches_won  : int = int(prog.get("matches_won", 0))

	var cards := _scan_card_collection()
	var sets_total : int = int(cards["sets_total"])

	# "Unlocked" means the set's pack is buyable — progress["packs_unlocked"] holds set ids.
	var sets_unlocked := 0
	for set_id in prog.get("packs_unlocked", []):
		if cards["set_ids"].has(String(set_id)):
			sets_unlocked += 1

	# ISSUE #139 FIX: include_defaults = true, so the three "1_Default*" card backs the player
	# owns from first launch count on BOTH sides of the fraction.
	var sleeve_universe  := GameState.get_sleeve_universe(true)
	var coin_universe    := GameState.get_coin_universe()
	var costume_universe := GameState.get_costume_universe()

	# FRACTIONS GET A METER, whole numbers get a box. A bar with no ceiling is a
	# progress track that does not exist, which is the same reason the "next
	# unlock" panels were cut from the collection screens.
	var meters := [
		["Unique cards",  int(cards["unique"]),  int(cards["collectible"])],
		["Sets unlocked", sets_unlocked,         sets_total],
		["Sets completed", int(cards["sets_completed"]), sets_total],
		["Coins",    _count_owned(coin_universe, GameState.get_coins()),       coin_universe.size()],
		["Costumes", _count_owned(costume_universe, GameState.get_costumes()), costume_universe.size()],
		["Sleeves",  _count_owned(sleeve_universe, GameState.get_sleeves()),   sleeve_universe.size()],
	]
	var boxes := [
		["Matches won",  str(matches_won)],
		["Packs opened", str(packs_opened)],
		["Cards owned",  str(cards["total"])],
		["Decks built",  str(_count_decks())],
	]

	_build_meter_panel(meters)
	_build_stat_boxes(boxes)
	_build_nearest_sets(cards["per_set"])


## Six fraction rows, each a label, a meter and its n / N.
func _build_meter_panel(rows: Array) -> void:
	var panel := UIKit.make_panel()
	panel.position = Vector2(RIGHT_X, METER_Y)
	panel.size = Vector2(RIGHT_W, METER_H)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_control.add_child(panel)

	var y := METER_Y + PANEL_PAD
	for r in rows:
		var label := Label.new()
		UIKit.set_label(label, "small_label", String(r[0]), "field_fg",
			_stat_font("small_label"))    # ISSUE #203
		label.position = Vector2(RIGHT_X + PANEL_PAD, y + 2.0)
		label.size = Vector2(METER_LABEL_W, METER_ROW_H_TXT)
		stats_control.add_child(label)

		var meter_x := RIGHT_X + PANEL_PAD + METER_LABEL_W + PANEL_PAD
		var meter_w := RIGHT_W - (meter_x - RIGHT_X) - PANEL_PAD - METER_VALUE_W - PANEL_PAD
		var holder := UIKit.make_meter(float(r[1]), float(r[2]), meter_w)
		holder.position = Vector2(meter_x, y + 12.0)
		stats_control.add_child(holder)

		var value := Label.new()
		UIKit.set_label(value, "hp", _fraction(int(r[1]), int(r[2])), "field_fg",
			_stat_font("hp"))             # ISSUE #203
		value.position = Vector2(RIGHT_X + RIGHT_W - PANEL_PAD - METER_VALUE_W, y)
		value.size = Vector2(METER_VALUE_W, METER_ROW_H_TXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats_control.add_child(value)

		y += METER_ROW_H


## Four whole-number boxes across the width: a big numeral under a small label.
func _build_stat_boxes(boxes: Array) -> void:
	var gap := BOX_GAP
	var w: float = (RIGHT_W - gap * float(boxes.size() - 1)) / float(boxes.size())
	for i in boxes.size():
		var x: float = RIGHT_X + float(i) * (w + gap)

		var panel := UIKit.make_panel()
		panel.position = Vector2(x, BOX_Y)
		panel.size = Vector2(w, BOX_H)
		panel.custom_minimum_size = panel.size
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_control.add_child(panel)

		# ISSUE #273: heading AND numeral centred in the box. Both labels are already
		# the full inner width of the panel, so this is one alignment each - a
		# left-aligned caption over a left-aligned numeral read as text that had
		# been pushed into the corner rather than as a stat tile.
		var caption := Label.new()
		UIKit.set_label(caption, "small_label", String(boxes[i][0]), "field_mute",
			_stat_font("small_label"))    # ISSUE #203
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(x + PANEL_PAD, BOX_Y + PANEL_PAD)
		caption.size = Vector2(w - PANEL_PAD * 2.0, 30.0)
		stats_control.add_child(caption)

		var value := Label.new()
		UIKit.set_label(value, "title", String(boxes[i][1]), "field_fg", BOX_VALUE_FONT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.position = Vector2(x + PANEL_PAD, BOX_Y + PANEL_PAD + 34.0)
		value.size = Vector2(w - PANEL_PAD * 2.0, float(BOX_VALUE_FONT) + 12.0)
		stats_control.add_child(value)
	print("ISSUE #273 FIX ACTIVE: ", boxes.size(), " stat boxes centred (caption + value)")


## The three sets closest to being finished.
##
## The ONE progress track this screen keeps — the user asked for it by name, and
## unlike a "next unlock" hint it is measuring something real: cards the player
## already owns against a set they can already buy.
##
## Only UNLOCKED sets are eligible (an unbuyable set is not something you are
## working on), already-complete sets are skipped, and PROMOS are excluded
## outright — basep and np are gift-only, so they can never be completed by
## playing and would sit at the top of the list forever.
func _build_nearest_sets(per_set: Dictionary) -> void:
	var panel := UIKit.make_panel()
	panel.position = Vector2(RIGHT_X, SETS_Y)
	panel.size = Vector2(RIGHT_W, SETS_H)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_control.add_child(panel)

	var heading := Label.new()
	# ISSUE #203: +50%. ISSUE #202/#189: headings are centred.
	UIKit.set_label(heading, "small_label", "Nearest sets to completion", "field_mute",
		_stat_font("small_label"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.position = Vector2(RIGHT_X + PANEL_PAD, SETS_Y + PANEL_PAD)
	heading.size = Vector2(RIGHT_W - PANEL_PAD * 2.0, 30.0)
	stats_control.add_child(heading)

	var unlocked: Array = GameState.progress.get("packs_unlocked", [])
	var names := _set_name_map()

	var candidates: Array = []
	for set_id in per_set:
		var sid := String(set_id)
		if sid in PROMO_SET_IDS:
			continue
		if not (sid in unlocked):
			continue
		var d: Dictionary = per_set[sid]
		var total: int = int(d["total"])
		var owned: int = int(d["owned"])
		if total <= 0 or owned >= total:
			continue
		candidates.append({ "id": sid, "owned": owned, "total": total,
			"frac": float(owned) / float(total) })

	candidates.sort_custom(func(a, b): return a["frac"] > b["frac"])

	if candidates.is_empty():
		var none := Label.new()
		UIKit.set_label(none, "attack_name",
			"Every unlocked set is complete.", "field_mute", _stat_font("attack_name"))
		none.position = Vector2(RIGHT_X + PANEL_PAD, SETS_Y + PANEL_PAD + 42.0)
		none.size = Vector2(RIGHT_W - PANEL_PAD * 2.0, 34.0)
		stats_control.add_child(none)
		return

	var y := SETS_Y + PANEL_PAD + 40.0
	for i in mini(NEAREST_SETS, candidates.size()):
		var c: Dictionary = candidates[i]

		# The set name sits on the SAME row as its bar, per the user's note.
		var label := Label.new()
		UIKit.set_label(label, "small_label", String(names.get(c["id"], c["id"])), "field_fg",
			_stat_font("small_label"))    # ISSUE #203
		label.position = Vector2(RIGHT_X + PANEL_PAD, y + 2.0)
		label.size = Vector2(METER_LABEL_W, METER_ROW_H_TXT)
		stats_control.add_child(label)

		var meter_x := RIGHT_X + PANEL_PAD + METER_LABEL_W + PANEL_PAD
		var meter_w := RIGHT_W - (meter_x - RIGHT_X) - PANEL_PAD - METER_VALUE_W - PANEL_PAD
		var holder := UIKit.make_meter(float(c["owned"]), float(c["total"]), meter_w)
		holder.position = Vector2(meter_x, y + 12.0)
		stats_control.add_child(holder)

		var value := Label.new()
		UIKit.set_label(value, "hp", _fraction(int(c["owned"]), int(c["total"])), "field_fg",
			_stat_font("hp"))             # ISSUE #203
		value.position = Vector2(RIGHT_X + RIGHT_W - PANEL_PAD - METER_VALUE_W, y)
		value.size = Vector2(METER_VALUE_W, METER_ROW_H_TXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats_control.add_child(value)

		y += METER_ROW_H


## set_id -> display name, from the dictionary the deck builder and shops share.
func _set_name_map() -> Dictionary:
	var out := {}
	var f := FileAccess.open(SET_DICT_PATH, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("set_list"):
		for entry in parsed["set_list"]:
			out[String(entry.get("set_id", ""))] = String(entry.get("set_name", ""))
	return out


## How many decks the player has saved. Derived from the folder rather than
## tracked in progress, so it cannot drift from what the load screen lists.
func _count_decks() -> int:
	var dir := DirAccess.open(GameState.PLAYER_DECKS_FOLDER)
	if dir == null:
		return 0
	var n := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


# "12 / 37" — used by every X / Y counter so they all format identically.
func _fraction(owned: int, total: int) -> String:
	return str(owned) + " / " + str(total)




# One pass over user://Player_Owned_Cards/ answers every card statistic on this screen:
#   total / unique  — copies owned, and distinct cards owned
#   collectible     — the denominator for Unique Cards Collected: every card the owned-cards
#                     files track between them. Basic Energy is left out of those files, so
#                     it can't inflate the target with cards the player is handed for free.
#   sets_total      — the denominator for both set counters (one file per set, 37 of them)
#   sets_completed  — a set counts as complete once at least one copy of EVERY card in it is
#                     owned. The owned-cards files leave basic Energy out (base1 lists 96 of its
#                     102 cards), so those unlimited cards can't block completion.
#   set_ids         — {"base1": true, ...}, used to sanity-check progress["packs_unlocked"]
# The folder also holds a Set_ID_Names_Dictionary and hand-made backups ("base1_player_owned_cards
# ALL.json"); the OWNED_CARDS_SUFFIX test is what keeps those out of the counts.
func _scan_card_collection() -> Dictionary:
	var result := {
		"total": 0,
		"unique": 0,
		"collectible": 0,
		"sets_total": 0,
		"sets_completed": 0,
		"set_ids": {},
		# set_id -> { "owned": n, "total": n }, for the nearest-to-completion panel.
		"per_set": {},
	}

	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return result

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(OWNED_CARDS_SUFFIX):
			var path := OWNED_CARDS_FOLDER + "/" + fname
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary and parsed.has("owned_cards"):
					result["sets_total"] += 1
					result["set_ids"][fname.trim_suffix(OWNED_CARDS_SUFFIX)] = true
					var cards_in_set := 0
					var owned_in_set := 0
					for entry in parsed["owned_cards"]:
						if entry is Dictionary:
							cards_in_set += 1
							var owned := int(entry.get("owned", 0))
							if owned > 0:
								owned_in_set    += 1
								result["total"] += owned
								result["unique"] += 1
					result["collectible"] += cards_in_set
					if cards_in_set > 0 and owned_in_set == cards_in_set:
						result["sets_completed"] += 1
					result["per_set"][fname.trim_suffix(OWNED_CARDS_SUFFIX)] = {
						"owned": owned_in_set, "total": cards_in_set,
					}
		fname = dir.get_next()
	dir.list_dir_end()

	return result


# ─── Cosmetic collection counting ────────────────────────────────────────────

# ISSUE #134: the three universes below moved to GameState (get_coin_universe /
# get_costume_universe / get_sleeve_universe) so the CHT.All_* cheats grant exactly the set of
# cosmetics these counters measure. Two copies of the folder-listing rules would have drifted.
# Each universe is keyed EXACTLY the way that collection is stored in progress, so ownership is
# a straight lookup: coins "Pikachu Gold.png", costumes "1ash.png", sleeves bare "Ditto".


func _count_owned(universe: Dictionary, owned: Array) -> int:
	var count := 0
	for entry in owned:
		if universe.has(String(entry)):
			count += 1
	return count


# ─── Cheat notification ──────────────────────────────────────────────────────

# ISSUE #132 TWEAKABLES — the cheat popup's look and timing.
# HOLD_TIME is dead air at full opacity before the rise/fade starts; it is the "1 second longer"
# the popup now lives for (total on-screen time = HOLD_TIME + RISE_TIME).
# RISE_PX / RISE_TIME set the drift SPEED between them, exactly as in Pack_Opening_Manager's
# NEW! and Bonus! labels — scale both by the same factor to change duration without changing speed.
const CHEAT_HOLD_TIME    : float = 1.0
const CHEAT_RISE_PX      : float = 120.0
const CHEAT_RISE_TIME    : float = 2.0
const CHEAT_FADE_TIME    : float = 2.0
const CHEAT_FONT_SIZE    : int   = 64
const CHEAT_OUTLINE_SIZE : int   = 10
# kenvector_future.ttf ships in one weight with no bold face, so "bold" is synthesised: a
# FontVariation thickens the strokes without changing glyph advances, so the measured width is
# unchanged. Same value and same reasoning as Pack_Opening_Manager.LABEL_EMBOLDEN.
const CHEAT_EMBOLDEN     : float = 0.6
# Rainbow settings copied from the pack "Bonus!" label so the two read as the same effect.
const CHEAT_RAINBOW_FREQ : float = 1.0   # colour cycles per second
const CHEAT_RAINBOW_SAT  : float = 0.9   # 0 = white, 1 = fully saturated hues
const CHEAT_RAINBOW_VAL  : float = 1.0   # brightness
# RichTextLabel clips to its own rect (unlike Label), so the box needs real headroom or the
# outline and any descender get sliced off. Y_OFFSET re-centres the top-aligned text on screen.
const CHEAT_BOX_HEIGHT   : float = 120.0
const CHEAT_BOX_Y_OFFSET : float = -42.0

const CHEAT_THEME_PATH := "res://UI_Themes/ui/ui_secondary.tres"

func _flash_cheat_message(message: String) -> void:
	# ISSUE #53 FIX: drive the cheat popup as a self-contained "float up + fade out" like the in-match
	# floating labels, animated by a Tween OWNED BY the CanvasLayer (a root child). Previously the
	# cleanup awaited a timer bound to THIS script; escaping the Info sub-menu freed the script and
	# cancelled the await, leaving the label stuck on screen forever. Now it always fades.
	# ISSUE #132: same mechanism, restyled — bold, rainbow-cycled text that holds before it fades.
	_cheat_label_token += 1
	var my_token := _cheat_label_token

	# Remove any existing popup so rapid re-triggers don't stack.
	if _cheat_label != null and is_instance_valid(_cheat_label) and _cheat_label.get_parent() != null:
		_cheat_label.get_parent().queue_free()
	_cheat_label = null

	var layer := CanvasLayer.new()
	layer.name = "CheatCanvasLayer"
	layer.layer = 128
	get_tree().root.add_child(layer)

	# ISSUE #132: RichTextLabel rather than Label purely for BBCode's built-in [rainbow], which
	# offsets the hue per character and advances it every frame — the same colour wave the "Bonus!"
	# label uses in Pack_Opening_Manager._show_bonus_label().
	var theme_kenney : Theme = load(CHEAT_THEME_PATH)
	var label := RichTextLabel.new()
	label.name                = "CheatNotificationLabel"
	label.bbcode_enabled      = true
	label.scroll_active       = false
	label.autowrap_mode       = TextServer.AUTOWRAP_OFF   # one line, never rewrapped
	label.add_theme_font_size_override("normal_font_size", CHEAT_FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", CHEAT_OUTLINE_SIZE)
	if theme_kenney != null:
		label.theme = theme_kenney
		var base_font : Font = theme_kenney.default_font
		if base_font != null:
			var bold := FontVariation.new()
			bold.base_font          = base_font
			bold.variation_embolden = CHEAT_EMBOLDEN
			label.add_theme_font_override("normal_font", bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "[center][rainbow freq=%s sat=%s val=%s]%s[/rainbow][/center]" % [
			CHEAT_RAINBOW_FREQ, CHEAT_RAINBOW_SAT, CHEAT_RAINBOW_VAL, message]

	var vp_size := get_viewport().get_visible_rect().size
	label.size     = Vector2(vp_size.x, CHEAT_BOX_HEIGHT)
	label.position = Vector2(0, vp_size.y * 0.5 + CHEAT_BOX_Y_OFFSET)
	layer.add_child(label)
	_cheat_label = label


	# Hold at full opacity (set_delay), then float up while fading. The tween is owned by `layer`
	# (a root child), so it completes even after this Info scene is freed.
	var tween := layer.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - CHEAT_RISE_PX, CHEAT_RISE_TIME).set_ease(Tween.EASE_OUT).set_delay(CHEAT_HOLD_TIME)
	tween.tween_property(label, "modulate:a", 0.0, CHEAT_FADE_TIME).set_ease(Tween.EASE_IN).set_delay(CHEAT_HOLD_TIME)
	tween.chain().tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if my_token == _cheat_label_token:
			_cheat_label = null
	)
