extends Control

# ============================================================
# MATCH OUTRO SCENE SCRIPT
# ============================================================
# Displays after a match ends. Builds the shared BattleFrame with the outcome's
# gradient, greys out the loser, shows the match stats row, plays the jingle and
# (on a win) flies the rewards in below the badge. The opponent's closing line is
# shown in the character message box; clicking it advances through the gift reveal
# animations (coin spin, card flip, costume fade) before returning to the map.
#
# Win and loss are the SAME FRAME with different content. The only differences are
# the gradient, which trainer desaturates, the word in the badge, and whether the
# slot below the badge holds rewards or nothing.
# ============================================================

# Data loaded at startup
var opponent_data: Dictionary
var player_data: Dictionary
var battle_won: bool = false

# Opponents that must be defeated in the current time period before
# time auto-advances. Night never auto-advances — the player must sleep
# in bed. The counter resets on every time change (see GameState.advance_time).
const OPPONENTS_TO_ADVANCE_TIME: int = 3

const BATTLE_SPRITE_DIR := "res://Image_Assets/Character_Sprites/In_Battle_Sprites/"

# Icon textures for rewards
var pokedollar_icon_tex = preload("res://Image_Assets/Icons/Reward_Icons/pokedollar_icon.png")
var coin_icon_tex       = preload("res://Image_Assets/Icons/Reward_Icons/coin_icon.png")
var costume_icon_tex    = preload("res://Image_Assets/Icons/Reward_Icons/costume_icon.png")
var card_icon_tex       = preload("res://Image_Assets/Icons/Reward_Icons/card_icon.png")

# The shared stage. Everything on screen except the message boxes hangs off this.
var frame: BattleFrame = null

# Reward tracking. build_rewards() fills this with DATA during _ready; the nodes
# are added later by _build_rewards_block(), once the frame exists.
var reward_rows: Array = []
var _header_anim: Control = null    # the REWARDS caption's movement wrapper
var _header_label: Label = null

# Screen dimensions (matching the 1920x1080 project)
const SCREEN_W: float        = 1920.0
const SCREEN_CENTER_X: float = 960.0

# -- TWEAKABLE: the badge and the stats row -------------------
const OUTCOME_FONT_SIZE : int = 46      # the word inside the wheel
const STATS_SEPARATION  : int = 96      # gap between the three stat items
const FADE_TIME         : float = 0.5

# -- TWEAKABLE: the rewards block -----------------------------
# Laid out inside a block that is centred under the badge, so every x below is
# measured from the block's own left edge rather than from the screen.
const REWARD_BLOCK_W     : float = 620.0
const REWARD_LABEL_FONT  : int   = 14     # the small mono REWARDS caption
const REWARD_LABEL_H     : float = 26.0
const REWARD_FONT_SIZE   : int   = 22     # the reward lines themselves
const REWARD_NOTE_FONT   : int   = 17     # the "(first win x3!)" aside
const REWARD_NOTE_GAP    : float = 8.0
const REWARD_ROW_H       : float = 32.0
const REWARD_ROW_PITCH   : float = 38.0
const REWARD_ICON_PX     : float = 26.0
const REWARD_COIN_ICON_PX: float = 29.0   # coins get the larger glyph
const REWARD_ICON_GAP    : float = 12.0
# How far off-screen each half starts, measured from the rewards block's own left
# edge - which sits around x=650, not at the screen edge. 1200 left the right-hand
# half of a long reward line poking into view before it flew in; this clears the
# screen by several hundred px on both sides.
const REWARD_OFFSCREEN_X : float = 2200.0
const REWARD_DROP_PX     : float = 65.0
# Timings, at the FAST setting. Every one goes through GameState.transition_time().
const REWARD_LABEL_DELAY : float = 0.50
const REWARD_LABEL_TIME  : float = 0.45
const REWARD_ROW_DELAY   : float = 0.55   # the first line
const REWARD_ROW_STAGGER : float = 0.30   # each line after it
const REWARD_ROW_TIME    : float = 0.50

# ── Gift animation ────────────────────────────────────────────
signal player_clicked   # emitted on every valid mouse click

# Populated in build_rewards() for the gift animation phase
var _coin_rewards_for_anim:    Array = []   # coin filename strings
var _card_rewards_for_anim:    Array = []   # card UID strings
var _costume_rewards_for_anim: Array = []   # costume key strings
var _sleeve_rewards_for_anim:  Array = []   # sleeve basename strings
var _pack_rewards_for_anim:    Array = []   # pack ART basenames, e.g. "gym1_a"

# Where the booster pack artwork lives. The name in an opponent's `pack_reward` is
# the art BASENAME and must match a file here exactly — PackOpeningManager builds
# both the texture path and the set id from it (see _validated_pack_arts).
const PACK_IMAGE_DIR: String = "res://Image_Assets/Packs/"
# Aspect-fit box for the pack reveal. The gym arts are ~457x726 and base5's is
# 1555x2464, so this is a maximum rather than a size — _show_gift() fits to it.
const PACK_REVEAL_BOX: Vector2 = Vector2(430, 682)

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

# The closing line matches an overworld message box exactly: same minimum height,
# same body size (the character variant's own 22pt, which -1 selects).
const DIALOGUE_BOX_HEIGHT: float = 138.0
# The gift notice is the SYSTEM variant but keeps its larger headline type - it is
# an announcement over a nearly-black reveal overlay, not dialogue to be read.
const GIFT_BOX_HEIGHT: float = 156.0
const GIFT_FONT_SIZE:  int   = 45

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

	SoundManagerScript.stop_bgm()

	# The head-to-head record, counted once per MATCH. It has to happen before the
	# stats row is built, because that row shows the score INCLUDING this game.
	GameState.record_opponent_result(GameState.current_opponent_name, battle_won)

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

	# Build reward rows (win only), passing is_first_win to avoid recomputing it
	if battle_won:
		build_rewards(is_first_win)

	# ISSUE #34: Options "Play Match Intro / Outro Animation?" = skip animations.
	# build_rewards() above has already GRANTED everything (cash, coin, cards, costumes) and marked
	# the opponent beaten — the arrays below only drive the optional full-screen reveal animations.
	# So when there is nothing to reveal, the whole outro is ceremony over rewards the player already
	# has, and we bail straight back to the map. transition_back_to_map() still runs the time-of-day
	# advancement, so no progression is lost.
	# A pack counts here even though the comment above says these arrays only drive
	# OPTIONAL animation: a pack is the one reward that has not been granted yet at
	# this point, because its cards do not exist until it is opened. Bailing out
	# early with a pack owed would silently throw the reward away.
	var has_gifts: bool = not (_coin_rewards_for_anim.is_empty()
			and _card_rewards_for_anim.is_empty()
			and _costume_rewards_for_anim.is_empty()
			and _sleeve_rewards_for_anim.is_empty()
			and _pack_rewards_for_anim.is_empty())
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
	#
	# Reduce motion lands in the same place from the other direction: it keeps the screen and
	# removes the movement, which is precisely what this flag already does.
	_force_skip_anim = GameState.is_transition_skipped() or GameState.is_motion_reduced()

	# The whole screen. Built here rather than in _ready's first lines because every
	# bail-out above this point leaves without ever showing it.
	_build_frame()
	_create_msg_panels()

	# Fade in from black. NOT awaited: the fade and the entrance run TOGETHER, so the
	# screen is revealed already in motion rather than sitting still and then jumping.
	# The elements were parked at their start offsets when the frame was built.
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, GameState.transition_time(FADE_TIME))

	# The one-shot entrance, also not awaited: the reward fly-in and the closing line
	# run over the top of it on their own delays, which is what the design asks for.
	frame.play_entrance()

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
			and _costume_rewards_for_anim.is_empty() and _sleeve_rewards_for_anim.is_empty() \
			and _pack_rewards_for_anim.is_empty():
		transition_back_to_map()
		return

	# Play the interactive gift reveal sequence then exit
	await _play_gift_sequence()
	transition_back_to_map()


func _input(event: InputEvent) -> void:
	# While a reward pack is being opened, PackOpeningManager owns the screen and
	# every click and key belongs to it. This scene is DEEPER in the tree than that
	# autoload, and _input runs deepest-first, so without this guard the outro sees
	# each event first and fires player_clicked — the click that turns over a card
	# in the pack would also advance the gift sequence underneath it.
	if PackOpeningManager.is_active():
		return

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

	# ISSUE #135 FIX: UIInput.is_click() is "a real mouse button went down" -- it filters out the
	# wheel, which Godot also reports as a pressed mouse button. Scrolling used to advance the outro
	# dialogue and fast-forward the reward animations.
	if UIInput.is_click(event):
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

# Instantly places the REWARDS caption and every reward row at its resting position.
# Called when the fly-in finishes OR is skipped, so a skipped fly-in shows all
# rewards at once exactly where they would have ended up.
func _snap_rewards_to_final() -> void:
	if _header_anim != null:
		_header_anim.position = Vector2.ZERO
	for row in reward_rows:
		if not row.has("icon_node"):
			continue
		row["icon_node"].position.x = row["icon_final_x"]
		row["value_node"].position.x = row["value_final_x"]
# ============================================================
# DATA LOADING
# ============================================================

func load_opponent_data(trainer_name: String) -> void:
	# TEMP TESTING: T-key TEST match synthesizes opponent data instead of reading NPC JSON.
	if GameState.test_match_mode:
		opponent_data = GameState.build_test_opponent_data()
		GameDataManager.opponent_data = opponent_data
		return

	# find_opponent falls back to the character's defaults when today's cast no
	# longer contains them -- the outro runs after the win that filtered them out.
	opponent_data = CharacterSchedule.find_opponent(
		GameState.current_opponent_map, trainer_name,
		GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if opponent_data.is_empty():
		print("Opponent with name ", trainer_name, " not found on map ",
			GameState.current_opponent_map)
		return

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
# THE SCREEN
# ============================================================
# Same frame as the intro and the best-of-three tracker, with the outcome's
# gradient on the bands and the badge ring. Win and loss are the SAME frame with
# different content, which is why the stats row lands in an identical position on
# both and only what fills the slot below the badge differs.

func _build_frame() -> void:
	var kind := "win" if battle_won else "loss"

	frame = BattleFrame.new()
	add_child(frame)
	frame.setup(kind)

	frame.set_trainer(frame.player, _sprite_for(player_data),
			str(player_data.get("name", "")), str(player_data.get("deck", "")))
	frame.set_trainer(frame.opponent, _sprite_for(opponent_data),
			str(opponent_data.get("name", "")), str(opponent_data.get("deck", "")))

	# The DEFEATED trainer greys out; the winner is untouched. This is what lets
	# the outcome read before the word does.
	frame.desaturate(frame.opponent if battle_won else frame.player)

	frame.badge_slot.add_child(frame.make_badge(
			"WIN" if battle_won else "LOSS", kind, OUTCOME_FONT_SIZE))
	_build_stats_row()

	# On a loss the slot below the badge stays EMPTY. No missed rewards, no greyed
	# prize money, no "what you could have won" - that punishes twice for one loss.
	if battle_won:
		_build_rewards_block()


# Prizes taken, turns and the head-to-head record. Identical fields in an
# identical position on both screens.
func _build_stats_row() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", STATS_SEPARATION)
	row.position = Vector2.ZERO
	row.size = frame.top_slot.size
	frame.top_slot.add_child(row)

	row.add_child(frame.make_stat("Prizes taken", "%d / %d" % [
			GameState.last_match_prizes_taken, GameState.last_match_prize_total]))
	row.add_child(frame.make_stat("Turns", str(GameState.last_match_turns)))

	# record_opponent_result() has already counted the match just played, so this
	# reads as the player expects: the score INCLUDING the game they just finished.
	var record: Array = GameState.get_opponent_record(GameState.current_opponent_name)
	var short_name := str(opponent_data.get("name", GameState.current_opponent_name))
	row.add_child(frame.make_stat("Record vs %s" % short_name.replace("_", " "),
			"%d – %d" % [record[0], record[1]]))


func _sprite_for(data: Dictionary) -> Texture2D:
	var key := str(data.get("sprite", ""))
	if key == "":
		return null
	var path := BATTLE_SPRITE_DIR + key.to_lower() + ".png"
	if not ResourceLoader.exists(path):
		print("Could not load battle sprite: ", path)
		return null
	return load(path)


# ============================================================
# REWARD BUILDING (win only)
# ============================================================

func build_rewards(is_first_win: bool) -> void:
	# Nothing is BUILT here - this only decides what the player has won and grants it.
	# The nodes come later, in _build_rewards_block(), once the frame exists.
	var row_index: int = 0

	# --- 1. Cash reward (always granted, tripled on first win) ---
	var cash_amount = int(opponent_data.get("cash_reward", "0"))
	if is_first_win:
		cash_amount *= 3
	GameState.add_cash(cash_amount)

	# The multiplier is an ASIDE, not part of the figure: smaller and in the accent,
	# so the amount is what the eye lands on.
	var cash_note: String = "(first win ×3!)" if is_first_win else ""
	reward_rows.append(_reward_row(str(cash_amount), pokedollar_icon_tex, cash_note))
	row_index += 1

	# --- First-win-only rewards ---
	if is_first_win:
		# --- 2. Coin reward ---
		var coin_key = opponent_data.get("coin_reward", "")
		if coin_key != "" and not GameState.has_coin(coin_key):
			GameState.add_coin_to_collection(coin_key)
			reward_rows.append(_reward_row(format_coin_name(coin_key), coin_icon_tex, "", REWARD_COIN_ICON_PX))
			row_index += 1
			_coin_rewards_for_anim.append(coin_key)

		# --- 3. Card reward (comma-separated) ---
		var card_reward_str = opponent_data.get("card_reward", "")
		if card_reward_str != "":
			GameState.give_cards(card_reward_str)
			for raw_id in card_reward_str.split(","):
				var cid = raw_id.strip_edges()
				if cid != "":
					reward_rows.append(_reward_row(_get_card_display_name(cid), card_icon_tex))
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
					reward_rows.append(_reward_row(display, costume_icon_tex))
					row_index += 1
					_costume_rewards_for_anim.append(ck)

		# --- 5. Sleeve reward (the opponent's own card back, when they grant it) ---
		# Set by the "Grant sleeve?" tickbox in the in-game character editor, which
		# writes `sleeve_reward` alongside the opponent's `sleeve`. There is no sleeve
		# icon in Reward_Icons/ yet, so this borrows the card icon — a sleeve is a card
		# back, and it reads better than the costume icon would.
		var sleeve_reward = opponent_data.get("sleeve_reward", "")
		if sleeve_reward != "" and not GameState.has_sleeve(sleeve_reward):
			GameState.add_sleeve_to_collection(sleeve_reward)
			reward_rows.append(_reward_row(
					_format_sleeve_name(sleeve_reward) + " Sleeve", card_icon_tex))
			row_index += 1
			_sleeve_rewards_for_anim.append(sleeve_reward)

		# --- 6. Booster pack reward (comma-separated art names) ---
		# FIRST WIN ONLY, like every other reward in this block, and for a harder
		# reason than the collectibles above: a pack is consumable, not a one-off
		# collectible, so granting one on every rematch would be an unlimited
		# source of cards worth $150-$400 a time. There is deliberately no
		# "already owned" test to fall back on the way coins and costumes have.
		#
		# Nothing is granted here. Unlike the other five rewards, the CARDS DO NOT
		# EXIST YET -- PackOpeningManager rolls the contents and writes them to the
		# player's collection when the pack is actually opened, at the end of the
		# gift sequence. All this does is record which packs are owed.
		var pack_reward_str = opponent_data.get("pack_reward", "")
		for art in _validated_pack_arts(pack_reward_str):
			# There is no pack icon in Reward_Icons/ yet, so this borrows the card
			# icon -- the same stand-in the sleeve row above uses.
			reward_rows.append(_reward_row(_format_pack_name(art), card_icon_tex))
			row_index += 1
			_pack_rewards_for_anim.append(art)

	GameState.mark_opponent_beaten(GameState.current_opponent_name)


## Splits a `pack_reward` field into art basenames, dropping any that have no
## artwork on disk.
##
## The check is not paranoia. PackOpeningManager derives BOTH the texture path
## (PACK_IMAGE_DIR + art + ".png") and the set id (everything before the LAST
## UNDERSCORE) from this one string. The separator is therefore load-bearing: the
## eight opponents that held "Gym2-c" before this was wired up would have failed
## twice over -- no such texture, and a set id of "Gym2-c" that matches no file in
## Card_Set_Data/, so the pack would have rolled zero cards.
##
## Case is NOT load-bearing, despite appearances: res:// paths are resolved
## through the host filesystem, which on Windows folds case, so "Gym1_a" does find
## gym1_a.png (measured, not assumed). The data was normalised to the on-disk
## names anyway rather than leaning on that -- a set id is used as a dictionary
## key in places where case would matter, and depending on filesystem case-folding
## for correctness is a trap waiting for anyone who builds elsewhere.
func _validated_pack_arts(raw: String) -> Array:
	var out: Array = []
	if raw.strip_edges() == "":
		return out
	for piece in raw.split(","):
		var art: String = piece.strip_edges()
		if art == "":
			continue
		if not ResourceLoader.exists(PACK_IMAGE_DIR + art + ".png"):
			push_error("Match outro: pack_reward art not found, reward skipped: '%s' (expected %s%s.png)"
					% [art, PACK_IMAGE_DIR, art])
			continue
		out.append(art)
	return out


## "gym1_a" -> "Gym Heroes Booster Pack". Falls back to the raw set id when the
## set is not in the dictionary, so a new set reads as e.g. "ex9 Booster Pack"
## rather than showing nothing.
func _format_pack_name(art: String) -> String:
	var set_id: String = art.rsplit("_", true, 1)[0]
	return _set_display_name(set_id) + " Booster Pack"


## set id -> printed set name, from the same dictionary the deck builder and the
## card detail panel read. Loaded once and cached; the file is small but this is
## called per reward row and again per reveal.
static var _set_name_cache: Dictionary = {}

func _set_display_name(set_id: String) -> String:
	if _set_name_cache.is_empty():
		var path := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					for entry in parsed.get("set_list", []):
						if entry is Dictionary and entry.has("set_id"):
							_set_name_cache[str(entry["set_id"])] = str(entry.get("set_name", ""))
	return _set_name_cache.get(set_id, set_id)



## One reward, as data. Nothing is built until _build_rewards_block() runs, because
## build_rewards() is called before the frame exists - it has to run even on the
## paths that never show a screen, since it is what actually GRANTS the rewards.
##
## `note` is the smaller accent aside after the value; `icon_px` overrides the
## default icon size for the one reward that needs a bigger glyph.
func _reward_row(text: String, icon: Texture2D, note: String = "",
				 icon_px: float = REWARD_ICON_PX) -> Dictionary:
	return { "text": text, "icon": icon, "note": note, "icon_px": icon_px }


# ============================================================
# THE REWARDS BLOCK
# ============================================================
# Sits BELOW the badge, in the same slot the intro uses for the prize count -
# that column is the match-information column on all three screens.
#
# A label and an icon list, deliberately not cards, chips or boxes. Those were
# tried and rejected: a reward is a line of information, and boxing each one made
# a short list look like a menu.
#
# Every row is placed by hand inside a plain Control rather than by a container,
# because the fly-in animates each row's x and a container would fight it for the
# same property on the same frame.
func _build_rewards_block() -> void:
	if reward_rows.is_empty():
		return

	var pitch := REWARD_ROW_PITCH
	var block := Control.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size = Vector2(REWARD_BLOCK_W,
			REWARD_LABEL_H + float(reward_rows.size()) * pitch)
	block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.below_badge.add_child(block)

	# The REWARDS caption. Its own wrapper so it can drop in while the rows fly
	# in sideways - centring on the label, movement on the wrapper.
	_header_anim = Control.new()
	_header_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_header_anim)

	_header_label = Label.new()
	_header_label.text = "REWARDS"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.add_theme_font_override("font", UITheme.font_at(UITheme.FONT_MONO_MEDIUM))
	_header_label.add_theme_font_size_override("font_size", REWARD_LABEL_FONT)
	_header_label.add_theme_constant_override("font_spacing_glyph",
			int(round(0.2 * float(REWARD_LABEL_FONT))))
	_header_label.add_theme_color_override("font_color", UITheme.col("field_mute"))
	_header_label.position = Vector2.ZERO
	_header_label.size = Vector2(REWARD_BLOCK_W, REWARD_LABEL_H)
	_header_anim.add_child(_header_label)

	for i in reward_rows.size():
		_place_reward_row(block, reward_rows[i], REWARD_LABEL_H + float(i) * pitch)


# Lays one row out and parks both halves off-screen ready for the fly-in. The
# icon comes in from the left and the value from the right; they meet in the
# middle, which is the animation this screen has always had. Only where they land
# has changed.
func _place_reward_row(block: Control, row: Dictionary, y: float) -> void:
	var centre := REWARD_BLOCK_W * 0.5

	var value := Control.new()
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(value)

	var main_lbl := Label.new()
	main_lbl.text = String(row["text"])
	main_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_lbl.add_theme_font_override("font", UITheme.font_card("name"))
	main_lbl.add_theme_font_size_override("font_size", REWARD_FONT_SIZE)
	main_lbl.add_theme_color_override("font_color", UITheme.col("field_fg"))
	var main_w: float = UITheme.font_card("name").get_string_size(
			main_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, REWARD_FONT_SIZE).x
	main_lbl.position = Vector2(0.0, 0.0)
	main_lbl.size = Vector2(main_w, REWARD_ROW_H)
	value.add_child(main_lbl)

	# The "(first win x3!)" aside, smaller and in the accent, so the FIGURE is
	# what the eye lands on rather than the reason for it.
	var note := String(row.get("note", ""))
	var note_w := 0.0
	if note != "":
		var note_lbl := Label.new()
		note_lbl.text = note
		note_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_lbl.add_theme_font_override("font", UITheme.font_card("subtitle"))
		note_lbl.add_theme_font_size_override("font_size", REWARD_NOTE_FONT)
		note_lbl.add_theme_color_override("font_color", UITheme.col("accent"))
		note_w = UITheme.font_card("subtitle").get_string_size(
				note, HORIZONTAL_ALIGNMENT_LEFT, -1, REWARD_NOTE_FONT).x
		note_lbl.position = Vector2(main_w + REWARD_NOTE_GAP, 0.0)
		note_lbl.size = Vector2(note_w, REWARD_ROW_H)
		value.add_child(note_lbl)
		note_w += REWARD_NOTE_GAP

	var icon_px: float = float(row.get("icon_px", REWARD_ICON_PX))
	var total := icon_px + REWARD_ICON_GAP + main_w + note_w
	var icon_x := centre - total * 0.5
	var value_x := icon_x + icon_px + REWARD_ICON_GAP

	value.position = Vector2(REWARD_OFFSCREEN_X, y)
	value.size = Vector2(main_w + note_w, REWARD_ROW_H)

	var icon := TextureRect.new()
	icon.texture = row["icon"]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(-REWARD_OFFSCREEN_X, y + (REWARD_ROW_H - icon_px) * 0.5)
	icon.size = Vector2(icon_px, icon_px)
	block.add_child(icon)

	row["icon_node"] = icon
	row["value_node"] = value
	row["icon_final_x"] = icon_x
	row["value_final_x"] = value_x


# ============================================================
# REWARD FLY-IN ANIMATION
# ============================================================

func animate_rewards() -> void:
	# The whole fly-in is click-skippable. On a click the remaining tweens are killed
	# and every reward snaps to its resting position at once.
	_in_skippable_anim = true
	_skip_anim = _force_skip_anim
	if _skip_anim:
		_snap_rewards_to_final()
		_in_skippable_anim = false
		return

	var gs := GameState
	frame.drop_in(_header_anim, gs.transition_time(REWARD_LABEL_DELAY),
			gs.transition_time(REWARD_LABEL_TIME), REWARD_DROP_PX)

	# One line after another, each on its own delay, both halves meeting in the
	# middle. Fixed rows rather than a stack that shifts up: the block grows
	# downwards out of the badge now, so there is nothing above it to make room for.
	var last_end := 0.0
	for i in reward_rows.size():
		var row = reward_rows[i]
		var delay: float = gs.transition_time(
				REWARD_ROW_DELAY + float(i) * REWARD_ROW_STAGGER)
		var dur: float = gs.transition_time(REWARD_ROW_TIME)
		last_end = maxf(last_end, delay + dur)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(row["icon_node"], "position:x", row["icon_final_x"], dur).set_delay(delay)
		tween.tween_property(row["value_node"], "position:x", row["value_final_x"], dur).set_delay(delay)

	await _await_timer_or_skip(last_end)

	# Finished naturally or skipped - pin everything to its resting position.
	_snap_rewards_to_final()
	_in_skippable_anim = false


# Waits `seconds`, returning early if the player clicks to skip. The fly-in runs
# several tweens at once on their own delays, so there is no single tween to await.
func _await_timer_or_skip(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skip_anim:
		await get_tree().process_frame
		left -= get_process_delta_time()
	_in_skippable_anim = false
# ============================================================
# MESSAGE PANELS
# ============================================================
# Two boxes, both DynamicMessageBox, differing only by variant:
#   Dialogue - the opponent's closing line. CHARACTER variant: their colour on the
#              spine and the glow, their name and portrait on the pill.
#   Gift     - "You received..." notices. SYSTEM variant: the game is speaking,
#              not the beaten trainer, so no pill and the theme gradient border.
#              It keeps its larger type, because it is a headline rather than
#              dialogue and it sits over a nearly-black reveal overlay.
# Both use MOUSE_FILTER_IGNORE so clicks reach _input().

func _create_msg_panels() -> void:
	var d = MessageBoxHelper.build(DIALOGUE_BOX_HEIGHT, -1, false)
	_dialogue_panel = d["root"]
	_dialogue_label = d["label"]
	# "ok" means no buttons and a caret in the bottom-right corner, which is what
	# both of these boxes are: click anywhere to move on.
	_dialogue_panel.set_mode("ok")
	add_child(_dialogue_panel)

	var g = MessageBoxHelper.build(GIFT_BOX_HEIGHT, GIFT_FONT_SIZE, false)
	_gift_panel = g["root"]
	_gift_label = g["label"]
	_gift_panel.set_system_variant(true)
	_gift_panel.set_mode("ok")
	add_child(_gift_panel)

	# The dialogue box takes the beaten opponent's colour, so the closing line reads
	# as them speaking. The key comes off opponent_data, which load_opponent_data()
	# has already merged with All_NPC_Constant_Data.json by this point; an unset or
	# unknown key falls back to the default theme inside apply_theme().
	#
	# The gift box does NOT: it is the game talking and wears the theme gradient.
	var opp_colour := str(opponent_data.get("message_colour", ""))
	_dialogue_panel.apply_theme(opp_colour)

	# The opponent's name and overworld portrait on the pill, exactly as the
	# overworld box gives them. set_name_pill AFTER apply_theme -- the pill's fill
	# is the theme's own base colour. `sprite` names a file in both the in-battle
	# and overworld sprite folders, so the same key that picks the battle portrait
	# picks the little walking sprite for the pill.
	var opp_name := str(opponent_data.get("name", ""))
	if opp_name != "":
		_dialogue_panel.set_name_pill(opp_name, str(opponent_data.get("sprite", "")))
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
	# Centring is the system variant's own job -- do not wrap in [center] here.
	_gift_panel.set_body_text(text)
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

	for sleeve_name in _sleeve_rewards_for_anim:
		# The full-size original, not the small/ thumbnail: this is a 430x600 reveal
		# and a 412px-tall thumbnail would visibly soften. Originals are a mix of
		# .jpg and .png, so both are tried.
		var img: Texture2D = _load_sleeve_texture(sleeve_name)
		if img == null:
			continue
		# A card-back flip to reveal a card back -- the same animation the card and
		# coin rewards use, and the one that suits a sleeve best.
		_show_gift(img, "card")
		var rect = _gift_container.get_child(0) as TextureRect
		await _play_flip_anim(rect, load(CARDBACK_PATH), img)
		_show_gift_message("You received the " + _format_sleeve_name(sleeve_name) + " card sleeve!")
		await player_clicked
		_hide_gift_message()
		_clear_gift()

	# Packs go LAST, after every other reveal is finished and cleared. Two reasons:
	# the pack opening is the only reward that takes the screen away from this
	# scene (PackOpeningManager builds its own overlay on the current scene), and
	# it is the only one that hands the player cards they have not seen yet, so it
	# is the natural crescendo.
	for pack_art in _pack_rewards_for_anim:
		var img: Texture2D = load(PACK_IMAGE_DIR + pack_art + ".png")
		if img == null:
			continue
		# A fade-in rather than the card/coin flip: a booster pack has no back to
		# flip from, so the costume reveal is the right animation here.
		_show_gift(img, "pack")
		var rect = _gift_container.get_child(0) as TextureRect
		await _play_costume_fadein_anim(rect)
		_show_gift_message("You received a " + _format_pack_name(pack_art) + "!")
		await player_clicked
		_hide_gift_message()
		_clear_gift()
		await _open_reward_pack(pack_art)


## Hands one pack to PackOpeningManager and waits for the whole opening to finish.
##
## This is where the cards are actually rolled and written to the player's
## collection — build_rewards() only recorded that a pack was owed.
##
## click_enabled is dropped for the duration. _input() also stands down while a
## pack is open (see the guard there), but the two are not redundant: the guard
## stops events being consumed twice in the same frame, while this stops a click
## that lands in the gap between the overlay closing and this function resuming
## from firing player_clicked into a sequence that is no longer awaiting one.
func _open_reward_pack(pack_art: String) -> void:
	if PackOpeningManager.is_active():
		push_warning("Match outro: a pack opening is already running, skipping " + pack_art)
		return
	var was_click_enabled := click_enabled
	click_enabled = false
	PackOpeningManager.open_packs([pack_art])
	await PackOpeningManager.all_packs_opened
	click_enabled = was_click_enabled


## Sleeve basename -> readable name. Sleeves keep their own capitalisation
## ("Apex_Charizard", "1_Default_English") rather than being title-cased, so the
## name reads the same way it does in the sleeve menu.
func _format_sleeve_name(raw: String) -> String:
	return raw.get_basename().replace("_", " ").strip_edges()


func _load_sleeve_texture(sleeve_name: String) -> Texture2D:
	for ext in [".jpg", ".png"]:
		var path: String = "res://Image_Assets/Sleeves/" + sleeve_name + ext
		if ResourceLoader.exists(path):
			return load(path)
	push_warning("Match outro: sleeve reward image not found: " + sleeve_name)
	return null


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
		"pack":    sz = PACK_REVEAL_BOX
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
