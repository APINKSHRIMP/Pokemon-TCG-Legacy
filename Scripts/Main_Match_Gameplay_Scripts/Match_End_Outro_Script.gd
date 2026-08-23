extends Control

# ============================================================
# MATCH OUTRO SCENE SCRIPT
# ============================================================
# Displays after a match ends. Shows win/loss background,
# plays the appropriate jingle, and (on win) displays reward
# labels that fly in from off-screen. The opponent's win/loss
# dialogue is shown in a message panel; clicking it advances
# through gift reveal animations (coin spin, card flip, costume
# fade) before transitioning back to the map.
# ============================================================

# Data loaded at startup
var opponent_data: Dictionary
var player_data: Dictionary
var battle_won: bool = false

# Opponents that must be defeated in the current time period before
# time auto-advances. Night never auto-advances — the player must sleep
# in bed. The counter resets on every time change (see GameState.advance_time).
const OPPONENTS_TO_ADVANCE_TIME: int = 3

# Animation config
var sprite_drift_duration: float = 5.0

# The Kenney UI theme used for reward labels
var kenney_theme = preload("res://UI_Themes/kenneyUI.tres")

# Icon textures for rewards
var pokedollar_icon_tex = preload("res://Image_Assets/Icons/Reward_Icons/pokedollar_icon.png")
var coin_icon_tex       = preload("res://Image_Assets/Icons/Reward_Icons/coin_icon.png")
var costume_icon_tex    = preload("res://Image_Assets/Icons/Reward_Icons/costume_icon.png")
var card_icon_tex       = preload("res://Image_Assets/Icons/Reward_Icons/card_icon.png")

# Scene node references
@onready var background          = $match_outro_background
@onready var player_sprite       = $PLAYER/player_sprite
@onready var opponent_sprite     = $OPPONENT/opponent_sprite
@onready var win_labels_container = $"WIN LABELS"

# Reward tracking — built during _ready, animated afterwards
var reward_rows: Array = []  # Each entry: { "label": Label, "icon": Sprite2D, ... }
var _header_label: Label = null   # "Rewards:" label, animated alongside rows

# Screen dimensions (matching the 1920x1080 project)
const SCREEN_W: float        = 1920.0
const SCREEN_CENTER_X: float = 960.0

# Reward fly-in layout (local to WIN LABELS container at screen y=684).
# The "Rewards:" header flies in first and lands at REWARD_ANCHOR_Y.
# Each new reward row also flies in to REWARD_ANCHOR_Y, while the header
# and any previously-shown rewards shift up by REWARD_ROW_SPACING so the
# header always remains the topmost element of the stack.
const REWARD_ANCHOR_Y: float   = -324.0   # container local → screen y 360
# ISSUE #123: reward text and icons are 50% bigger. The row pitch had to grow with them --
# at the old 35px a 32pt line would have overlapped the row above it.
const REWARD_ROW_SPACING: float =   52.5   # was 35.0
const REWARD_FONT_SIZE: int     =     32   # was 21
const REWARD_ICON_PX: float     =   30.0   # was 20.0
const REWARD_ICON_GAP: float    =   45.0   # icon width + gap; was 30.0
const REWARD_ICON_DROP: float   =    7.5   # icon sits this far below the label top; was 5.0
const HEADER_LOCAL_X: float    = -200.0   # final x for the centred header
const HEADER_WIDTH: float      =  800.0
const OFFSCREEN_RIGHT_X: float = 1200.0
const OFFSCREEN_LEFT_X: float  = -1200.0

# ── Gift animation ────────────────────────────────────────────
signal player_clicked   # emitted on every valid mouse click

# Populated in build_rewards() for the gift animation phase
var _coin_rewards_for_anim:    Array = []   # coin filename strings
var _card_rewards_for_anim:    Array = []   # card UID strings
var _costume_rewards_for_anim: Array = []   # costume key strings

var _result_dialogue: String = ""   # opponent win/loss text shown after fly-in

# Gift overlay nodes — created and freed around each revealed item
var _gift_overlay:   ColorRect = null
var _gift_container: Control   = null

# Two separate message panels used at different points in the outro:
#   _dialogue_panel — opponent win/loss text (small font, extra padding)
#   _gift_panel     — "You received…" notices (larger font, default padding)
var _dialogue_panel: DynamicMessageBox = null
var _dialogue_label: RichTextLabel = null
var _gift_panel:     DynamicMessageBox = null
var _gift_label:     RichTextLabel = null

# ISSUE #122: match the overworld message box exactly -- same panel height, same body size.
const DIALOGUE_BOX_HEIGHT: float = 138.0
const DIALOGUE_FONT_SIZE:  int   = 28

const CARDBACK_PATH = "res://Image_Assets/Sleeves/1_Default_English.png"
const COINBACK_PATH = "res://Image_Assets/Coins/Back Basic.png"
const GIFT_FLIP_DURATIONS = [0.01, 0.02, 0.04, 0.06, 0.08, 0.1, 0.11, 0.12, 0.2]

# Click gating
var click_enabled: bool  = false
var transitioning: bool  = false

# ISSUE #33 FIX: skip support for the match-end reward animations. While _in_skippable_anim is true
# (reward fly-in, coin/card flip, costume fade), a mouse click sets _skip_anim to fast-forward that
# animation to its finished state, instead of the click being ignored (the previous fix only covered
# the overworld MapManager gift reveal, so match-end rewards couldn't be skipped at all).
var _in_skippable_anim: bool = false
var _skip_anim: bool = false
# ISSUE #34: set once in _ready() when the player has turned the intro/outro animation off. Only the
# reward-row FLY-IN honours it — the gift reveals (coin/card flip, costume fade) deliberately ignore
# it and keep playing at Item speed, since those are the rewards themselves, not ceremony.
var _force_skip_anim: bool = false

# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	modulate.a = 0.0

	# Hide placeholder labels — we build our own dynamically
	for child in win_labels_container.get_children():
		child.visible = false

	battle_won = (GameState.battle_result == "win")

	# ── Best-of-N series handling ──
	# After every game in a series, record the result and hand off to the
	# Best_Of_3_Transition scene which handles the round-counter animation.
	# That scene decides whether to route to the next-round intro or (when
	# the series is decided) to the final outro. battle_result is left intact
	# so the outro can read it correctly on the deciding game.
	if GameState.series_active and GameState.series_opponent_name == GameState.current_opponent_name:
		if battle_won:
			GameState.series_wins += 1
		else:
			GameState.series_losses += 1
		GameState.series_round_results.append("win" if battle_won else "loss")
		_transition_to_bo3_scene()
		return

	load_opponent_data(GameState.current_opponent_name)
	load_player_data()

	# Background texture
	if battle_won:
		var tex = load("res://Image_Assets/Backgrounds_And_Borders/Backgrounds/battle_win_screen.png")
		if tex:
			background.texture = tex
	else:
		var tex = load("res://Image_Assets/Backgrounds_And_Borders/Backgrounds/battle_loss_screen.png")
		if tex:
			background.texture = tex

	update_sprites()
	SoundManagerScript.stop_bgm()

	# Compute is_first_win once so both the dialogue and build_rewards share it
	var is_first_win = not GameState.has_beaten_opponent(GameState.current_opponent_name)

	# ISSUE #122 FIX ACTIVE: the opponent's name used to be glued onto the FRONT of their own
	# dialogue as plain text ("MISTY:\nnice match!"), which is exactly what the message box's
	# name chip is for. The name now goes on a sprite chip above the box like every overworld
	# NPC, and the body holds only what the opponent actually says.
	if battle_won:
		_result_dialogue = opponent_data.get("first_win_text" if is_first_win else "rematch_win_text", "")
	else:
		_result_dialogue = opponent_data.get("loss_text", "")
	print("ISSUE #122 FIX ACTIVE: outro dialogue shown on a name-chipped box for ",
		  opponent_data.get("name", "?"))

	# Build reward rows (win only), passing is_first_win to avoid recomputing it
	if battle_won:
		build_rewards(is_first_win)

	# ISSUE #34: Options "Play Match Intro / Outro Animation?" = skip animations.
	# build_rewards() above has already GRANTED everything (cash, coin, cards, costumes) and marked
	# the opponent beaten — the arrays below only drive the optional full-screen reveal animations.
	# So when there is nothing to reveal, the whole outro is ceremony over rewards the player already
	# has, and we bail straight back to the map. transition_back_to_map() still runs the time-of-day
	# advancement, so no progression is lost.
	var has_gifts: bool = not (_coin_rewards_for_anim.is_empty()
			and _card_rewards_for_anim.is_empty()
			and _costume_rewards_for_anim.is_empty())
	if GameState.is_transition_skipped() and not has_gifts:
		# No win/loss jingle either — it would be cut off mid-note by the scene change below.
		transition_back_to_map()
		return

	if battle_won:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_win)
	else:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_loss)

	# There ARE gifts to reveal, so the scene stays — but on "skip" every animation in it snaps
	# straight to its finished state. The player still sees each reward and clicks through them.
	_force_skip_anim = GameState.is_transition_skipped()

	# Create both message panels before they're needed
	_create_msg_panels()

	# Fade in from black
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.5)
	await fade_in.finished

	animate_sprites()

	# Show the opponent's win/loss dialogue BEFORE rewards fly in — visible for longer
	if _result_dialogue != "":
		_show_dialogue_message(_result_dialogue)

	# Animate reward label fly-ins (win only); dialogue stays visible during animation
	if battle_won:
		await animate_rewards()

	click_enabled = true
	await player_clicked       # first click dismisses dialogue
	_hide_dialogue_message()

	# Cash-only (no gift rewards) → exit immediately on the single click above
	if _coin_rewards_for_anim.is_empty() and _card_rewards_for_anim.is_empty() \
			and _costume_rewards_for_anim.is_empty():
		transition_back_to_map()
		return

	# Play the interactive gift reveal sequence then exit
	await _play_gift_sequence()
	transition_back_to_map()


func _input(event: InputEvent) -> void:
	# Space / Enter / Escape do whatever a click would do here — skip a reward
	# animation, or advance the dialogue and the gift reveal. Escape used to call
	# get_tree().quit(), which closed the game mid-reward-screen.
	if UIInput.is_advance(event):
		if _in_skippable_anim and not transitioning:
			_skip_anim = true
			get_viewport().set_input_as_handled()
			return
		if click_enabled and not transitioning:
			player_clicked.emit()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		# ISSUE #33 FIX: a click during a skippable animation (reward fly-in, coin/card flip, costume
		# fade) fast-forwards it to its finished state. This is checked BEFORE the normal click gate so
		# it works even during the fly-in, when click_enabled is still false.
		if _in_skippable_anim and not transitioning:
			_skip_anim = true
			get_viewport().set_input_as_handled()
			return
		if click_enabled and not transitioning:
			player_clicked.emit()
			get_viewport().set_input_as_handled()

# ISSUE #33 FIX: awaits a tween, but returns early (killing the tween) if the player clicks to skip.
# Uses the finished signal for natural completion and polls _skip_anim each frame for the skip.
func _await_tween_or_skip(tw: Tween) -> void:
	if tw == null or not tw.is_valid():
		return
	var done := {"v": false}
	tw.finished.connect(func(): done["v"] = true)
	while not done["v"] and not _skip_anim:
		await get_tree().process_frame
	if not done["v"] and tw.is_valid():
		tw.kill()

# ISSUE #33 FIX: instantly places the "Rewards:" header and every reward row at its final resting
# position (the stacked layout the fly-in animation builds up). Called when the fly-in finishes OR is
# skipped, so a skipped fly-in shows all rewards at once exactly where they would have ended up.
func _snap_rewards_to_final() -> void:
	var n := reward_rows.size()
	if _header_label != null:
		_header_label.position = Vector2(HEADER_LOCAL_X, REWARD_ANCHOR_Y - n * REWARD_ROW_SPACING)
	for j in range(n):
		var row = reward_rows[j]
		var up := (n - 1 - j) * REWARD_ROW_SPACING
		row["label"].position = Vector2(row["label_final_x"], REWARD_ANCHOR_Y - up)
		row["icon"].position  = Vector2(row["icon_final_x"], REWARD_ANCHOR_Y + REWARD_ICON_DROP - up)

# ============================================================
# DATA LOADING
# ============================================================

func load_opponent_data(trainer_name: String) -> void:
	# TEMP TESTING: T-key TEST match synthesizes opponent data instead of reading NPC JSON.
	if GameState.test_match_mode:
		opponent_data = GameState.build_test_opponent_data()
		GameDataManager.opponent_data = opponent_data
		return

	var file = FileAccess.open(GameState.current_opponent_json_path, FileAccess.READ)
	if file == null:
		print("Error loading opponent file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error")
		return

	var opponents = json.data["opponents"]
	for opponent in opponents:
		if opponent.get("name") == trainer_name:
			opponent_data = opponent
			break

	if opponent_data.is_empty():
		print("Opponent with name ", trainer_name, " not found")
		return

	var const_file = FileAccess.open("res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json", FileAccess.READ)
	if const_file != null:
		var const_data = JSON.parse_string(const_file.get_as_text())
		const_file.close()
		if const_data is Dictionary:
			var consts: Dictionary = const_data.get("opponents", {}).get(trainer_name, {})
			for key in consts:
				if not opponent_data.has(key):
					opponent_data[key] = consts[key]

	GameDataManager.opponent_data = opponent_data

func load_player_data() -> void:
	var file = FileAccess.open(GameState.PLAYER_CURRENT_DATA_PATH, FileAccess.READ)
	if file == null:
		print("Error loading player file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error for player data")
		return

	player_data = json.data
	GameDataManager.player_data = player_data

# ============================================================
# SPRITE SETUP
# ============================================================

func _normalize_sprite_scale(sprite: Sprite2D, tex: Texture2D) -> void:
	const TARGET: float = 480.0
	var tex_size := tex.get_size()
	var s := minf(TARGET / tex_size.x, TARGET / tex_size.y)
	sprite.scale = Vector2(s, s)

func update_sprites() -> void:
	if opponent_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + opponent_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			opponent_sprite.texture = tex
			_normalize_sprite_scale(opponent_sprite, tex)
		else:
			print("Could not load opponent sprite: ", path)

	if player_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + player_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			player_sprite.texture = tex
			player_sprite.flip_h = true
			_normalize_sprite_scale(player_sprite, tex)
		else:
			print("Could not load player sprite: ", path)

# ============================================================
# SPRITE DRIFT ANIMATION (same as intro — slow slide apart)
# ============================================================

func animate_sprites() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(true)
	tween.tween_property(player_sprite,   "position:x", player_sprite.position.x   - 100, sprite_drift_duration)
	tween.tween_property(opponent_sprite, "position:x", opponent_sprite.position.x + 100, sprite_drift_duration)

# ============================================================
# REWARD BUILDING (win only)
# ============================================================

func build_rewards(is_first_win: bool) -> void:
	# --- "Rewards:" header — starts off-screen right, flies in during animate_rewards() ---
	var header = Label.new()
	header.text = "Rewards:"
	header.theme = kenney_theme
	header.add_theme_font_size_override("font_size", REWARD_FONT_SIZE)   # ISSUE #123
	header.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(OFFSCREEN_RIGHT_X, REWARD_ANCHOR_Y)
	header.size = Vector2(HEADER_WIDTH, 90)   # ISSUE #123: taller to hold the bigger face
	win_labels_container.add_child(header)
	_header_label = header

	var row_index: int = 0

	# --- 1. Cash reward (always granted, tripled on first win) ---
	var cash_amount = int(opponent_data.get("cash_reward", "0"))
	if is_first_win:
		cash_amount *= 3
	GameState.add_cash(cash_amount)

	var cash_text = str(cash_amount)
	if is_first_win:
		cash_text += " (First Win ×3!)"
	reward_rows.append(_create_reward_row(cash_text, pokedollar_icon_tex, row_index))
	row_index += 1

	# --- First-win-only rewards ---
	if is_first_win:
		# --- 2. Coin reward ---
		var coin_key = opponent_data.get("coin_reward", "")
		if coin_key != "" and not GameState.has_coin(coin_key):
			GameState.add_coin_to_collection(coin_key)
			reward_rows.append(_create_reward_row(format_coin_name(coin_key), coin_icon_tex, row_index))
			row_index += 1
			_coin_rewards_for_anim.append(coin_key)

		# --- 3. Card reward (comma-separated) ---
		var card_reward_str = opponent_data.get("card_reward", "")
		if card_reward_str != "":
			GameState.give_cards(card_reward_str)
			for raw_id in card_reward_str.split(","):
				var cid = raw_id.strip_edges()
				if cid != "":
					reward_rows.append(_create_reward_row(_get_card_display_name(cid), card_icon_tex, row_index))
					row_index += 1
					_card_rewards_for_anim.append(cid)

		# --- 4. Costume reward (comma-separated, supports multiple) ---
		var costume_reward_str = opponent_data.get("costume_reward", "")
		if costume_reward_str != "":
			for raw_key in costume_reward_str.split(","):
				var ck = raw_key.strip_edges()
				if ck != "" and not GameState.has_costume(ck):
					GameState.add_costume_to_collection(ck)
					var display = capitalise_words(_format_costume_name(ck) + " Trainer Class")
					reward_rows.append(_create_reward_row(display, costume_icon_tex, row_index))
					row_index += 1
					_costume_rewards_for_anim.append(ck)

	GameState.mark_opponent_beaten(GameState.current_opponent_name)


# Helper: create a label + icon pair for one reward row.
# Both start off-screen at REWARD_ANCHOR_Y; animate_rewards() flies them in.
# (row_index is unused now — the stack-from-top animation handles vertical placement.)
func _create_reward_row(label_text: String, icon_texture: Texture2D, _row_index: int) -> Dictionary:
	# WIN LABELS is at x=762 in screen space. Screen centre in local coords = 960 - 762 = 198.
	var local_centre_x: float = 198.0
	var icon_gap: float = REWARD_ICON_GAP   # ISSUE #123: icon width (30) + 15px gap

	var label = Label.new()
	label.text = label_text
	label.theme = kenney_theme
	label.add_theme_font_size_override("font_size", REWARD_FONT_SIZE)   # ISSUE #123
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	win_labels_container.add_child(label)

	label.reset_size()
	var label_width = label.size.x
	var total_width = icon_gap + label_width

	var label_final_x = local_centre_x - total_width / 2.0 + icon_gap
	var icon_final_x  = local_centre_x - total_width / 2.0

	label.position = Vector2(OFFSCREEN_RIGHT_X, REWARD_ANCHOR_Y)

	var icon = Sprite2D.new()
	icon.texture  = icon_texture
	icon.centered = false
	var tex_size  = icon_texture.get_size()
	icon.scale    = Vector2(REWARD_ICON_PX / tex_size.x, REWARD_ICON_PX / tex_size.y)   # ISSUE #123
	icon.position = Vector2(OFFSCREEN_LEFT_X, REWARD_ANCHOR_Y + REWARD_ICON_DROP)
	win_labels_container.add_child(icon)

	return {
		"label":        label,
		"icon":         icon,
		"label_final_x": label_final_x,
		"icon_final_x":  icon_final_x,
	}

# ============================================================
# REWARD FLY-IN ANIMATION
# ============================================================

func animate_rewards() -> void:
	# ISSUE #33 FIX: the whole fly-in is now click-skippable. On a click, remaining tweens are killed
	# and every reward snaps to its final stacked position at once (see _snap_rewards_to_final).
	_in_skippable_anim = true
	_skip_anim = _force_skip_anim
	await get_tree().create_timer(0.3).timeout

	# Step 1 — fly the "Rewards:" header in horizontally to the anchor row.
	if _header_label != null and not _skip_anim:
		var hdr_tween = create_tween()
		hdr_tween.set_trans(Tween.TRANS_CUBIC)
		hdr_tween.set_ease(Tween.EASE_OUT)
		hdr_tween.tween_property(_header_label, "position:x", HEADER_LOCAL_X, 0.6)
		await _await_tween_or_skip(hdr_tween)
		if not _skip_anim:
			await get_tree().create_timer(0.3).timeout

	# Step 2 — for each reward: shift the header (and any previously-shown
	# rewards) up by ROW_SPACING, then fly the new reward in to the anchor row.
	for i in range(reward_rows.size()):
		if _skip_anim:
			break
		var row          = reward_rows[i]
		var label: Label    = row["label"]
		var icon: Sprite2D  = row["icon"]

		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)

		# Shift the header up one row.
		if _header_label != null:
			tween.tween_property(_header_label, "position:y",
				_header_label.position.y - REWARD_ROW_SPACING, 0.6)

		# Shift every previously-shown reward up one row.
		for j in range(i):
			var prev = reward_rows[j]
			var prev_label: Label   = prev["label"]
			var prev_icon:  Sprite2D = prev["icon"]
			tween.tween_property(prev_label, "position:y",
				prev_label.position.y - REWARD_ROW_SPACING, 0.6)
			tween.tween_property(prev_icon, "position:y",
				prev_icon.position.y - REWARD_ROW_SPACING, 0.6)

		# Fly the new reward in horizontally to the anchor row.
		tween.tween_property(label, "position:x", row["label_final_x"], 0.6)
		tween.tween_property(icon,  "position:x", row["icon_final_x"],  0.6)

		await _await_tween_or_skip(tween)

		if not _skip_anim and i < reward_rows.size() - 1:
			await get_tree().create_timer(0.3).timeout

	# Finished naturally or skipped — pin everything to its final resting position.
	_snap_rewards_to_final()
	_in_skippable_anim = false

# ============================================================
# MESSAGE PANELS
# ============================================================
# Two panels share the same image but differ in font and padding:
#   Dialogue  — opponent win/loss text  (small font, +50 px padding)
#   Gift      — "You received…" notice  (larger font, default padding)
# Both use MOUSE_FILTER_IGNORE so clicks reach _input().

func _create_msg_panels() -> void:
	# ISSUE #122: the dialogue box is now exactly an overworld message box -- same 138px panel,
	# same 28pt body, no extra padding -- instead of the outsized 220px/36pt one-off it was.
	var d = MessageBoxHelper.build(DIALOGUE_BOX_HEIGHT, DIALOGUE_FONT_SIZE, false)
	_dialogue_panel = d["root"]
	_dialogue_label = d["label"]
	add_child(_dialogue_panel)

	# Gift: compact main-match-style box with centred text.
	# ISSUE #124: the fit_content/expand-fill pair that used to live here made the label fill
	# the whole panel, so "You received X" rendered hard against its top edge. Vertical centring
	# is the box's own job now (DynamicMessageBox._place_body_label) -- don't reintroduce them.
	var g = MessageBoxHelper.build(156.0, 45, false, 0.0)
	_gift_panel = g["root"]
	_gift_label = g["label"]
	add_child(_gift_panel)

	# Both panels take the beaten opponent's colour, so the whole outro reads as one screen in
	# their theme rather than the dialogue and the reward notices disagreeing. The key comes off
	# opponent_data, which load_opponent_data() has already merged with All_NPC_Constant_Data.json
	# by this point; an unset or unknown key falls back to the default theme inside apply_theme().
	var opp_colour := str(opponent_data.get("message_colour", ""))
	_dialogue_panel.apply_theme(opp_colour)
	_gift_panel.apply_theme(opp_colour)

	# ISSUE #122: the opponent's name and overworld sprite, on the same chip the overworld box
	# gives them. set_chips AFTER apply_theme -- the chip ramp is derived from the theme.
	# `sprite` names a file in both the in-battle and overworld sprite folders, so the same
	# key that picks the battle portrait picks the little walking sprite for the chip.
	var opp_name := str(opponent_data.get("name", ""))
	if opp_name != "":
		_dialogue_panel.set_chips([
			{ "text": opp_name.to_upper(), "sprite": str(opponent_data.get("sprite", "")) },
		])

func _show_dialogue_message(text: String) -> void:
	if _dialogue_panel == null:
		return
	# set_body_text rather than label.text: it shrinks the font if a long line
	# of opponent flavour would otherwise spill out of the panel.
	_dialogue_panel.set_body_text(text)
	_dialogue_panel.visible = true
	move_child(_dialogue_panel, get_child_count() - 1)

func _hide_dialogue_message() -> void:
	if _dialogue_panel != null:
		_dialogue_panel.visible = false

func _show_gift_message(text: String) -> void:
	if _gift_panel == null:
		return
	_gift_panel.set_body_text("[center]" + text + "[/center]")
	_gift_panel.visible = true
	move_child(_gift_panel, get_child_count() - 1)

func _hide_gift_message() -> void:
	if _gift_panel != null:
		_gift_panel.visible = false

# ============================================================
# GIFT ANIMATION SEQUENCE
# ============================================================

func _play_gift_sequence() -> void:
	for coin_name in _coin_rewards_for_anim:
		var img: Texture2D = load("res://Image_Assets/Coins/" + coin_name + ".png")
		_show_gift(img, "coin")
		var rect = _gift_container.get_child(0) as TextureRect
		await _play_flip_anim(rect, load(COINBACK_PATH), img)
		_show_gift_message("You received the " + format_coin_name(coin_name) + "!")
		await player_clicked
		_hide_gift_message()
		_clear_gift()

	for card_uid in _card_rewards_for_anim:
		var split = card_uid.split("-")
		var img: Texture2D = load("res://Image_Assets/Card_Image_Library/" + split[0] + "/Large/" + card_uid + ".png")
		_show_gift(img, "card")
		var rect = _gift_container.get_child(0) as TextureRect
		await _play_flip_anim(rect, load(CARDBACK_PATH), img)
		_show_gift_message("You received " + _get_card_display_name(card_uid) + "!")
		await player_clicked
		_hide_gift_message()
		_clear_gift()

	for costume_key in _costume_rewards_for_anim:
		var img: Texture2D = load("res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + costume_key + ".png")
		_show_gift(img, "costume")
		var rect = _gift_container.get_child(0) as TextureRect
		await _play_costume_fadein_anim(rect)
		_show_gift_message("You received the " + _format_costume_name(costume_key) + " costume!")
		await player_clicked
		_hide_gift_message()
		_clear_gift()


func _show_gift(tex: Texture2D, kind: String) -> void:
	# Use explicit 1920×1080 coords so parent size doesn't affect placement
	_gift_overlay = ColorRect.new()
	_gift_overlay.color        = Color(0, 0, 0, 0.92)   # nearly-opaque dark bg
	_gift_overlay.offset_left  = 0.0
	_gift_overlay.offset_top   = 0.0
	_gift_overlay.offset_right = 1920.0
	_gift_overlay.offset_bottom = 1080.0
	_gift_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gift_overlay)

	_gift_container = Control.new()
	_gift_container.offset_left   = 0.0
	_gift_container.offset_top    = 0.0
	_gift_container.offset_right  = 1920.0
	_gift_container.offset_bottom = 1080.0
	_gift_container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_gift_container)

	var sz: Vector2
	match kind:
		"coin":    sz = Vector2(250, 250)
		"card":    sz = Vector2(430, 600)
		"costume": sz = Vector2(432, 594)
		_:         sz = Vector2(300, 300)

	# ISSUE #77 FIX: these boxes were used as fixed sizes with STRETCH_SCALE, so any texture whose
	# aspect ratio didn't match got squashed — the in-battle costume sprites are square (e.g.
	# 539x539) but were forced into a 432x594 portrait box, which is why a won costume appeared
	# stretched thin. Treat the box as a MAXIMUM and aspect-fit the texture inside it, the same
	# pattern MapManager._show_gift_display already uses for the overworld gift reveal. Coins keep
	# the fixed box so every coin renders at an identical size regardless of its source image.
	if kind != "coin" and tex != null:
		var orig_w := float(tex.get_width())
		var orig_h := float(tex.get_height())
		if orig_w > 0.0 and orig_h > 0.0:
			var fit_scale: float = min(sz.x / orig_w, sz.y / orig_h)
			sz = Vector2(orig_w * fit_scale, orig_h * fit_scale)

	# Centre the item on screen using explicit offsets (anchor stays at 0)
	var cx := 960.0
	var cy := 540.0
	var rect := TextureRect.new()
	rect.texture             = tex
	rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode        = TextureRect.STRETCH_SCALE
	rect.pivot_offset        = sz / 2.0
	rect.offset_left         = cx - sz.x / 2.0
	rect.offset_top          = cy - sz.y / 2.0
	rect.offset_right        = cx + sz.x / 2.0
	rect.offset_bottom       = cy + sz.y / 2.0
	rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_gift_container.add_child(rect)

	# Keep the gift message panel above the overlay (dialogue panel stays hidden here)
	if _gift_panel != null:
		move_child(_gift_panel, get_child_count() - 1)


func _clear_gift() -> void:
	if _gift_overlay != null and is_instance_valid(_gift_overlay):
		_gift_overlay.queue_free()
	_gift_overlay = null
	if _gift_container != null and is_instance_valid(_gift_container):
		_gift_container.queue_free()
	_gift_container = null


func _play_flip_anim(rect: TextureRect, back_tex: Texture2D, front_tex: Texture2D) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	rect.texture      = back_tex
	rect.scale        = Vector2(1.0, 1.0)
	rect.pivot_offset = rect.size / 2.0
	var swaps = [front_tex, back_tex, front_tex, back_tex, front_tex,
				 back_tex, front_tex, back_tex, front_tex]
	# ISSUE #33 FIX: the coin/card flip is click-skippable — a click snaps it to its finished
	# face-up state (front texture, full scale) instead of the click being ignored.
	# NOTE: deliberately NOT _force_skip_anim. This is a reward reveal, not intro/outro ceremony, so
	# it plays at Item speed even when the player has the intro/outro animation turned off.
	_in_skippable_anim = true
	_skip_anim = false
	var tw = create_tween()
	for i in GIFT_FLIP_DURATIONS.size():
		var d: float = GameState.item_time(GIFT_FLIP_DURATIONS[i])
		tw.tween_property(rect, "scale:x", 0.0, d)
		tw.tween_callback(rect.set.bind("texture", swaps[i]))
		tw.tween_property(rect, "scale:x", 1.0, d)
	await _await_tween_or_skip(tw)
	# Snap to the finished face-up state whether it completed or was skipped.
	if is_instance_valid(rect):
		rect.texture = front_tex
		rect.scale.x = 1.0
	_in_skippable_anim = false


func _play_costume_fadein_anim(rect: TextureRect) -> void:
	if rect == null or not is_instance_valid(rect):
		return
	rect.modulate = Color(0, 0, 0, 1)
	# ISSUE #33 FIX: the costume fade-in is click-skippable — a click snaps it to fully visible.
	# As with the flip above, a reward reveal ignores _force_skip_anim and runs at Item speed.
	_in_skippable_anim = true
	_skip_anim = false
	await get_tree().create_timer(GameState.item_time(0.5)).timeout
	if rect == null or not is_instance_valid(rect):
		_in_skippable_anim = false
		return
	var tw = create_tween()
	tw.tween_property(rect, "modulate", Color(1, 1, 1, 1), GameState.item_time(1.0))
	await _await_tween_or_skip(tw)
	# Snap to fully visible whether the fade completed or was skipped.
	if is_instance_valid(rect):
		rect.modulate = Color(1, 1, 1, 1)
	_in_skippable_anim = false

# ============================================================
# NAME FORMATTING HELPERS
# ============================================================

# Converts e.g. "Gyarados Blue 1" → "Blue Gyarados Coin 1"
func format_coin_name(raw: String) -> String:
	var base    := raw.trim_suffix(".png")
	var is_rare := false
	for prefix in ["Zzzz ", "Zzz ", "Zz "]:
		if base.begins_with(prefix):
			base    = base.trim_prefix(prefix)
			is_rare = true
			break
	var words   := base.split(" ")
	var colours := ["red", "blue", "gold", "silver", "green", "black", "purple",
					"pink", "brown", "yellow", "orange", "white"]
	var colour     := ""
	var number     := ""
	var name_parts: Array = []
	var i := words.size() - 1
	if i >= 0 and words[i].is_valid_int():
		number = words[i]
		i -= 1
	if i >= 0 and words[i].to_lower() in colours:
		colour = words[i]
		i -= 1
	for j in range(i + 1):
		name_parts.append(words[j])
	var pieces: Array = []
	if is_rare:
		pieces.append("Rare")
	if colour != "":
		pieces.append(colour)
	pieces.append_array(name_parts)
	pieces.append("Coin")
	if number != "":
		pieces.append(number)
	return " ".join(pieces)


func capitalise_words(text: String) -> String:
	var words  = text.split(" ")
	var result = []
	for word in words:
		if word.length() > 0:
			result.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(result)


# "fisherman_m1" → "Fisherman M1"
func _format_costume_name(raw: String) -> String:
	var parts = raw.replace(".png", "").split("_")
	var out: Array = []
	for p in parts:
		if p.length() > 0:
			out.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(out)


# Looks up the card's name from its set JSON file.
# Returns the raw UID as fallback if the file or card isn't found.
func _get_card_display_name(card_uid: String) -> String:
	var split = card_uid.split("-")
	if split.size() != 2:
		return card_uid
	var file = FileAccess.open("res://Card_Set_Data/" + split[0] + ".json", FileAccess.READ)
	if file == null:
		return card_uid
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Array:
		for card in data:
			if card.get("id", "") == card_uid:
				return card.get("name", card_uid)
	return card_uid

# ============================================================
# SCENE TRANSITION — BO3 TRANSITION SCENE
# ============================================================
# Always called after any match in a best-of-N series, regardless of
# whether the series is decided. The BO3 transition scene handles
# routing to the next round's intro or the final outro itself.
func _transition_to_bo3_scene() -> void:
	transitioning = true
	click_enabled = false
	SoundManagerScript.stop_bgm()
	SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Best_Of_3_Transition.tscn")

# ============================================================
# SCENE TRANSITION — BACK TO MAP
# ============================================================

func transition_back_to_map() -> void:
	print("DEBUG return path: ", GameState.return_map_scene_path)
	transitioning  = true
	click_enabled  = false

	# Time advancement checks — applies to every day. Defeating enough
	# opponents pushes Morning -> Afternoon -> Evening -> Night. Night never
	# auto-advances; the player advances it by sleeping in bed.
	if battle_won and GameState.get_current_defeated() >= OPPONENTS_TO_ADVANCE_TIME:
		match GameState.get_time():
			"Morning":
				GameState.advance_time("Afternoon")
			"Afternoon":
				GameState.advance_time("Evening")
			"Evening":
				# Day-1 onboarding gate: the player must collect the shop
				# starter set before night. The flag stays true forever
				# afterwards, so this is a no-op on every later day.
				if GameState.progress.get("player_collected_shop_starter_set", false):
					GameState.advance_time("Night")

	# Stop win/loss jingle
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.queue_free()

	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished

	# Clear battle_result so MapManager knows the outro already handled the dialogue
	GameState.battle_result = ""

	var map_path = GameState.return_map_scene_path
	if map_path == "":
		map_path = "res://Scenes/Map_Scenes/World_Maps/World_Map_Base_Scene.tscn"

	SceneCache.change_scene(map_path)
