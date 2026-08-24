extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const MAX_NAME_LENGTH    := 21
const OWNED_CARDS_FOLDER := "user://Player_Owned_Cards"
const OWNED_CARDS_SUFFIX := "_player_owned_cards.json"

# ISSUE #134: the cosmetic-collection folder constants that used to sit here now live in
# GameState (COIN_ASSET_FOLDER / COSTUME_ASSET_FOLDER / SLEEVE_SMALL_FOLDER / COIN_BACK_IMAGE /
# DEFAULT_SLEEVE_PREFIX), so the X / Y counters below and the CHT.All_* cheats read one list.

# ─── Trainer-card row geometry ───────────────────────────────
# The stat rows sit on bars painted into Trainer_card.png, so the art dictates their spacing, not
# a container. Measured off the 4102x1911 source: nine bars, each 76px tall on a 149.25px pitch,
# first bar top at y=185 and last bar bottom at y=1455 — a 1270px block. The `statistics` Control
# is set to exactly that block in screen space, so expressing the bar height as a ratio of its
# height keeps the text glued to the bars if the card is ever moved or rescaled.
# Nine rows is fixed by the artwork: a tenth row needs a tenth bar painted first.
const STAT_ROWS       := 9
const STAT_BAR_RATIO  := 76.0 / 1270.0   # bar height as a fraction of the block height
const STAT_TEXT_INSET := 22.0            # left/right padding inside a bar, screen px

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


# ─── Trainer-card colour ───────────────────────────────────
# The cycle order lives in GameState.TRAINER_CARD_COLOURS; these two tables just say what each
# colour looks like. medals_button follows the card — white uses the plain Kenney theme, the rest
# use the matching named variant.
const CARD_TEXTURE_PREFIX := "res://Image_Assets/Main_Menu_Images/Trainer_card_"
const CARD_THEMES := {
	"blue":   "res://UI_Themes/kenneyUI-blue.tres",
	"green":  "res://UI_Themes/kenneyUI-green.tres",
	"yellow": "res://UI_Themes/kenneyUI-yellow.tres",
	"red":    "res://UI_Themes/kenneyUI-red.tres",
	"white":  "res://UI_Themes/kenneyUI.tres",
}

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

# Target display sizes — uniform regardless of source image dimensions
const SPRITE_SIZE  := Vector2(280, 360)  # fit (whole sprite visible, letterboxed)

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
@onready var card_rect     : TextureRect = $"BACKGROUND/id_background"
@onready var medals_btn    : Button      = $"medals_button"
@onready var player_sprite : TextureRect = $"PlayerSprite"
@onready var stats_control : Control     = $"statistics"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# ISSUE #128: every sub-menu plays the same track. This screen had none, so it ran on
	# whatever the main menu was still playing behind it -- and once that overlap was fixed
	# (Main_Menu_Script.pause_music) it would have been left silent instead.
	add_child(audio_player)
	var audio_stream = load("res://Audio/BGM/coin_mode (TCG GB Water Club).ogg")
	audio_player.stream = audio_stream
	audio_player.bus = SoundManagerScript.MUSIC_BUS
	if audio_stream != null:
		audio_stream.loop = true
		audio_player.play()

	_style_dob_cash_label()
	_setup_card_colour_cycling()

	_load_player_data()

	name_box.max_length = MAX_NAME_LENGTH
	name_box.alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_box.text_changed.connect(_on_name_changed)

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_populate_stats()


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
	dob_cash_lbl.text = "DOB: " + (dob if dob != "" else "--/--") + "\n$" + str(GameState.get_cash())

	# Battle sprite — fit inside SPRITE_SIZE so different-shaped sprites all appear the same size
	var sprite_name: String = data.get("sprite", "")
	if sprite_name != "":
		if not sprite_name.ends_with(".png"):
			sprite_name += ".png"
		var tex := load(SPRITE_FOLDER + "/" + sprite_name) as Texture2D
		if tex:
			_apply_fit_size(player_sprite, tex, SPRITE_SIZE)


# ─── DOB / cash label ─────────────────────────────────────

# One Label carries both lines — "DOB: 21/12" over the cash total — centred in its box. The text is
# filled in by _load_player_data(); this only sets the look, so the order of the two does not matter.
func _style_dob_cash_label() -> void:
	dob_cash_lbl.add_theme_font_size_override("font_size", DOB_CASH_FONT_SIZE)
	dob_cash_lbl.add_theme_color_override("font_color", Color.BLACK)
	dob_cash_lbl.add_theme_constant_override("line_spacing", DOB_CASH_LINE_SPACING)
	dob_cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dob_cash_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER


# ─── Trainer-card colour cycling ───────────────────────────

# Two things guard this, because the scene’s mouse picking is awkward: BACKGROUND holds a
# full-screen background_scroller and the card itself, both of which sit under every button.
#  1. The card keeps MOUSE_FILTER_PASS — the TextureRect default, set explicitly here so nobody
#     "fixes" it to STOP later. STOP does make gui_input fire reliably, but it also CONSUMES the
#     click, which stops Save, Cancel, View MEDALS and the name box from ever seeing it.
#  2. _click_lands_on_a_control() rejects clicks inside any interactive rect, so even if the card
#     does win the pick over a button, pressing that button cannot also flip the colour.
func _setup_card_colour_cycling() -> void:
	card_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	card_rect.gui_input.connect(_on_card_gui_input)
	# The stats block and its rows are pure text lying over the card — leaving them
	# click-transparent lets that whole area cycle the colour too.
	stats_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Same for the battle sprite: decoration sitting on the card, not a control.
	player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_card_colour(GameState.get_trainer_card_colour(), false)


# Clicking the card steps blue > green > yellow > red > white > blue and writes the choice to
# Player_Current_Data.json there and then — no Save button involved.
func _on_card_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	# A mouse WHEEL also arrives as InputEventMouseButton, so the button test is doing real work.
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Inside gui_input the event has been transformed into card_rect's own space, so
	# mb.global_position is NOT viewport-global here — rebuild the screen point by hand.
	var screen_pos := card_rect.global_position + mb.position
	if _click_lands_on_a_control(screen_pos):
		return
	_apply_card_colour(GameState.cycle_trainer_card_colour(), true)


# True when the click belongs to something the player can actually operate. Add to this list if a
# new control is ever laid on top of the card.
func _click_lands_on_a_control(pos: Vector2) -> bool:
	for c : Control in [name_box, save_btn, cancel_btn, medals_btn]:
		if c.visible and c.get_global_rect().has_point(pos):
			return true
	return false


# Repaints the card and the medals button. `with_sparkle` is false for the initial load so the
# screen does not burst on open, and true for a click.
func _apply_card_colour(colour: String, with_sparkle: bool) -> void:
	var tex := load(CARD_TEXTURE_PREFIX + colour + ".png") as Texture2D
	if tex:
		card_rect.texture = tex

	var theme_path : String = CARD_THEMES.get(colour, CARD_THEMES["white"])
	var btn_theme := load(theme_path) as Theme
	if btn_theme:
		medals_btn.theme = btn_theme

	if with_sparkle:
		_burst_sparkle(colour)


# One-shot glitter across the whole card. Lifted from Coin_Shop_Script._start_sparkle; see the
# SPARKLE_* constants for what was changed and why.
func _burst_sparkle(colour: String) -> void:
	if _sparkle != null and is_instance_valid(_sparkle):
		_sparkle.queue_free()

	var particles := CPUParticles2D.new()
	add_child(particles)
	_sparkle = particles

	particles.global_position       = card_rect.global_position + card_rect.size / 2.0
	particles.z_index               = 50
	particles.amount                = SPARKLE_AMOUNT
	particles.lifetime              = SPARKLE_LIFETIME
	particles.one_shot              = true
	particles.explosiveness         = SPARKLE_EXPLOSIVENESS
	particles.emitting              = true
	particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = card_rect.size / 2.0
	particles.direction             = Vector2(0, 0)
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.gravity               = Vector2(0, 0)
	particles.scale_amount_min      = 3.0
	particles.scale_amount_max      = 6.0

	var sparkle_colour : Color = SPARKLE_COLOURS.get(colour, Color(1.0, 1.0, 1.0))
	var bright         : Color = sparkle_colour.lightened(1.0)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient

	# The last particle spawns at lifetime x (1 - explosiveness) and then lives a full lifetime,
	# so the node has to outlast lifetime x (2 - explosiveness) before it is safe to free.
	# ISSUE #53 pattern: the timer is owned by the tree, not this script, so leaving the screen
	# mid-burst can never strand the node.
	var burst_duration := SPARKLE_LIFETIME * (2.0 - SPARKLE_EXPLOSIVENESS)
	get_tree().create_timer(burst_duration + 0.2).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free())


# ─── Uniform image sizing ────────────────────────────────────────────────────

# Scales the texture to fit entirely inside target (letterbox / minf).
# Sets size explicitly — does not rely on the layout engine.
func _apply_fit_size(rect: TextureRect, tex: Texture2D, target: Vector2) -> void:
	var tex_size := tex.get_size()
	var s        := minf(target.x / tex_size.x, target.y / tex_size.y)
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture      = tex
	rect.size         = Vector2(tex_size.x * s, tex_size.y * s)


# ─── Name box ────────────────────────────────────────────────────────────────

func _on_name_changed(_new_text: String) -> void:
	_refresh_save_button_state()


# ─── Save button state ───────────────────────────────────────────────────────

func _refresh_save_button_state() -> void:
	var name_changed := name_box.text.strip_edges() != saved_player_name
	if name_changed:
		save_btn.disabled = false
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		save_btn.disabled = true
		save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


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
	save_btn.theme = load("res://UI_Themes/kenneyUI.tres")

	var cheat_msg := CheatManager.check_and_apply(new_name)
	if cheat_msg != "":
		_flash_cheat_message(cheat_msg)


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

	var prog := GameState.progress

	# Only the stats the trainer card actually shows are read here. The opponent counters
	# (opponents_beaten / opponents_beaten_count_total) and matches_played are still recorded
	# by Game_State, just not surfaced: a visible loss tally punishes a player who forfeits or
	# grinds, and "unique opponents" is near-redundant with Matches Won.
	var packs_opened : int = int(prog.get("packs_opened_total", 0))
	var matches_won  : int = int(prog.get("matches_won", 0))

	var cards := _scan_card_collection()
	var sets_total : int = int(cards["sets_total"])

	# "Unlocked" means the set's pack is buyable — progress["packs_unlocked"] holds set ids.
	# Intersected with the sets that actually exist so a stray entry can never push the
	# numerator past the denominator.
	var sets_unlocked := 0
	for set_id in prog.get("packs_unlocked", []):
		if cards["set_ids"].has(String(set_id)):
			sets_unlocked += 1

	var sleeve_universe  := GameState.get_sleeve_universe()
	var coin_universe    := GameState.get_coin_universe()
	var costume_universe := GameState.get_costume_universe()

	var rows := [
		["Matches Won",            str(matches_won)],
		["Packs Opened",           str(packs_opened)],
		["Total Cards Owned",      str(cards["total"])],
		["Unique Cards Collected", _fraction(int(cards["unique"]), int(cards["collectible"]))],
		["Card Sets Unlocked",     _fraction(sets_unlocked, sets_total)],
		["Sets Completed",         _fraction(int(cards["sets_completed"]), sets_total)],
		["Coins Owned",            _fraction(_count_owned(coin_universe, GameState.get_coins()), coin_universe.size())],
		["Costumes Owned",         _fraction(_count_owned(costume_universe, GameState.get_costumes()), costume_universe.size())],
		["Sleeves Owned",          _fraction(_count_owned(sleeve_universe, GameState.get_sleeves()), sleeve_universe.size())],
	]

	if rows.size() != STAT_ROWS:
		push_warning("Info: %d stat rows but the trainer card art has %d bars" % [rows.size(), STAT_ROWS])

	# Rows are placed on the bars painted into the card rather than stacked in a container:
	# a VBoxContainer separation cannot be made to land on the artwork at every font size.
	var bar_h := stats_control.size.y * STAT_BAR_RATIO
	var pitch := (stats_control.size.y - bar_h) / float(STAT_ROWS - 1)
	for i in rows.size():
		var row := _make_stat_row(rows[i][0], rows[i][1])
		row.position = Vector2(STAT_TEXT_INSET, i * pitch + STAT_TEXT_Y_NUDGE)
		row.size     = Vector2(stats_control.size.x - STAT_TEXT_INSET * 2.0, bar_h)
		stats_control.add_child(row)


# "12 / 37" — used by every X / Y counter so they all format identically.
func _fraction(owned: int, total: int) -> String:
	return str(owned) + " / " + str(total)


func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	val.add_theme_color_override("font_color", Color.BLACK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	hbox.add_child(lbl)
	hbox.add_child(val)
	return hbox


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

const CHEAT_THEME_PATH := "res://UI_Themes/kenneyUI.tres"

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

	print("ISSUE #132 FIX ACTIVE: rainbow cheat popup '", message, "' holding ", CHEAT_HOLD_TIME,
			"s then rising ", CHEAT_RISE_PX, "px over ", CHEAT_RISE_TIME, "s")

	# Hold at full opacity (set_delay), then float up while fading. The tween is owned by `layer`
	# (a root child), so it completes even after this Info scene is freed.
	var tween := layer.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - CHEAT_RISE_PX, CHEAT_RISE_TIME) 			.set_ease(Tween.EASE_OUT).set_delay(CHEAT_HOLD_TIME)
	tween.tween_property(label, "modulate:a", 0.0, CHEAT_FADE_TIME) 			.set_ease(Tween.EASE_IN).set_delay(CHEAT_HOLD_TIME)
	tween.chain().tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if my_token == _cheat_label_token:
			_cheat_label = null
	)
