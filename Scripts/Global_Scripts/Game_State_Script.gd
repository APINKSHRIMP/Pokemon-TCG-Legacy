extends Node

# ============================================================
# GAME STATE - Autoload Singleton
# ============================================================

var current_opponent_name: String = ""

# ISSUE #129: granted on game initialisation; 1_Default_English is also the equipped sleeve a
# new save starts with (see the "sleeve" key in Player_Data/Player_Current_Data.json). Names are
# bare basenames, matching everything else in progress["sleeves"].
const STARTER_SLEEVES: Array = [
	"1_Default_English",
	"1_Default_Japanese_New",
	"1_Default_Japanese_Old",
]

# The "1_Default*" card backs are the freebies the player owns from first launch (STARTER_SLEEVES
# above). ISSUE #139: they DO count towards the trainer card's "collected" total now — the Info
# screen asks for the universe with include_defaults = true, so they appear on both sides of the
# fraction. The flag is kept because get_sleeve_universe() still needs to be able to answer
# "which sleeves had to be earned". See get_sleeve_universe().
const DEFAULT_SLEEVE_PREFIX := "1_Default"

# TEMP TESTING: synthetic opponent metadata used by the T-key TEST match so no
# NPC JSON needs to exist. Sprite is left blank (intro skips a missing sprite).
func build_test_opponent_data() -> Dictionary:
	return {
		"name": "TEST OPPONENT",
		"deck": "TEST",
		"sprite": "",
		"music": "fast_battle (PTCG Ronalds Theme)",
		"prize_cards": 6,
		"coin_reward": "",
		"sleeve": "",
		"match_effects": [],
		"restrictions": {},
	}

var current_opponent_map: String = ""   # character-file basename for the map the battle started on
var returning_from_battle: bool = false
var battle_result: String = ""  # "win" or "loss"

# ── The finished match's summary line ─────────────────────────────────────────
# Written once by Main_Match_Core_Gameplay_Script.game_end_logic() and read by the
# outro's stats row. Deliberately three plain numbers rather than a dictionary: the
# outro is the only reader, and a missing key there would be a crash on the screen
# the player sees least often.
#
# `last_match_prizes_taken` counts the prizes the PLAYER took, so on a loss it is the
# honest partial figure rather than the winner's six. On a best-of-three these hold
# the DECIDING round only — the stats row describes the game just played, and the
# round tracker is what describes the series.
var last_match_prizes_taken: int = 0
var last_match_prize_total: int = 6
var last_match_turns: int = 0
var player_position: Vector2 = Vector2.ZERO
var current_opponent_deck: String = ""

# TEMP TESTING: when true, both the player AND the opponent draw from the
# "TEST" deck in user://Player_Decks/, and opponent metadata is synthesized
# (no NPC JSON is read). Set by the overworld T-key debug launcher; cleared
# whenever a normal battle starts.
var test_match_mode: bool = false

var return_to_scene: String = ""
var interior_entry_position: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var use_spawn_position: bool = false
var entering_from: String = ""

var return_map_scene_path: String = ""
var last_battled_opponent_entry: Dictionary = {}
var last_interior_scene: String = ""
var current_shop_id: String = "card_mart"

# ISSUE #34: global game-speed multipliers. 1.0 plays an animation at exactly its authored duration;
# higher = faster. Read these wherever an animation/movement duration is computed so the whole game
# honours the player's preference.
#   card_match_animation_speed  — in-match animations: card placement, energy, retreat, damage
#                                 labels, coin flips, KOs, CPU thinking pauses.
#   item_animation_speed        — reward reveals: gift coin/card flips and costume fade-ins.
#   pack_animation_speed        — the pack opening sequence only.
#   overworld_walking_speed     — the player's default overworld walk/run speed multiplier.
#
# ── UI OVERHAUL 2026-08-30: THREE SETTINGS BECAME ONE ────────────────────────────────────────
# The first three used to be three separate Options rows with three separate saved keys, each on
# its own five-step ladder. They are now driven by ONE "Animation speed" row at slow / medium /
# fast, saved under "animation_speed".
#
# The three MULTIPLIER TABLES stayed separate, and that is the point: a match, a gift reveal and a
# pack tear are authored at different tempos, so "medium" still means 1.25 for a match and 0.75 for
# a pack. One preset key, three ladders. Tune each table on its own.
#
# The old per-ladder "skip" presets are gone too. Skipping is now REDUCE MOTION — one switch that
# collapses all three at once, so the player cannot end up with a skipped pack opening and a slow
# match by accident. It is an accessibility control, not a fourth speed.
#
# Walking speed is deliberately NOT part of this. It affects play, not presentation.
#
# The match intro/outro has NO multiplier — see INTRO_OUTRO_OPTIONS below.
var card_match_animation_speed: float = 1.25
var item_animation_speed: float = 1.25
var pack_animation_speed: float = 0.75   # PACK_SPEED_PRESETS["medium"], the boot default
var overworld_walking_speed: float = 1.1

# The one ladder the player picks from. Three steps, in this order — the Options row is built from
# this array, so adding a step here adds the button.
const ANIMATION_SPEED_OPTIONS := ["slow", "medium", "fast"]

# TWEAKABLE — raising a number speeds that preset up. The three tables are deliberately separate
# and MUST all carry the same three keys as ANIMATION_SPEED_OPTIONS. "medium" does not have to mean
# the same multiplier in each, and does not: a pack tear is a set-piece and runs slower than the
# match it paid for.
const MATCH_SPEED_PRESETS := {
	"slow": 1.0,
	"medium": 1.25,
	"fast": 2.2,
}
const ITEM_SPEED_PRESETS := {
	"slow": 1.0,
	"medium": 1.25,
	"fast": 2.2,
}
# ISSUE #94's relabel is preserved: "fast" is the straight 1.0 passthrough where the base durations
# written into Pack_Opening_Manager.gd play exactly as authored, and the default sits one notch
# under it.
const PACK_SPEED_PRESETS := {
	"slow": 0.5,
	"medium": 0.75,
	"fast": 1.0,
}

# Reduce motion. An accessibility switch, not a fourth speed.
#
# SKIP_MULTIPLIER is deliberately huge rather than infinite so scaled_duration() collapses every
# animation to about one frame INSTEAD of skipping the await chains outright — bypassing the awaits
# would desync the match engine. This is the same trick the old per-ladder "skip" presets used; it
# now lives in one place and drives all three domains together.
#
# It also stops the chevron scroll and freezes the selection ring — see UITheme.motion_reduced(),
# which reads reduce_motion_setting directly.
const REDUCE_MOTION_OPTIONS := ["off", "where_possible"]
const SKIP_MULTIPLIER := 100.0

# The match intro/outro is a plain on/off, and stays its own row. Everything in those scenes is
# already click-to-skip and the only thing a multiplier changed was how long the screen sat there —
# so the choice that actually matters is "play it" or "don't".
#
# NOTE the two are NOT the same control: "skip" here bypasses the intro/outro SCREEN entirely, while
# reduce motion keeps the screen and collapses its animations. See is_transition_skipped().
const INTRO_OUTRO_OPTIONS := ["play", "skip"]

const DEFAULT_ANIMATION_SPEED := "medium"
const DEFAULT_REDUCE_MOTION   := "off"
const DEFAULT_INTRO_OUTRO     := "play"

# The player's currently selected preset keys. Persisted in Player_Current_Data.json.
var animation_speed_setting: String   = DEFAULT_ANIMATION_SPEED
var reduce_motion_setting: String     = DEFAULT_REDUCE_MOTION
var intro_outro_setting: String       = DEFAULT_INTRO_OUTRO

# Applies a preset key to the live multiplier. Pass save = false to set it without touching the
# save file (used on boot).
## Sets the one animation-speed preset. All three domains follow it through
## _apply_animation_multipliers(), each from its own table.
func set_animation_speed(preset: String, save: bool = true) -> void:
	if not preset in ANIMATION_SPEED_OPTIONS:
		push_warning("GameState: unknown animation speed preset '" + preset + "'")
		return
	animation_speed_setting = preset
	_apply_animation_multipliers()
	if save:
		_save_current_data_field("animation_speed", animation_speed_setting)


## Reduce motion. Overrides the speed preset for as long as it is on, so turning it off must
## recompute rather than restore — which is exactly what _apply_animation_multipliers() does.
func set_reduce_motion(choice: String, save: bool = true) -> void:
	if not choice in REDUCE_MOTION_OPTIONS:
		push_warning("GameState: unknown reduce motion choice '" + choice + "'")
		return
	reduce_motion_setting = choice
	_apply_animation_multipliers()
	if save:
		_save_current_data_field("reduce_motion", reduce_motion_setting)


## The single place the three live multipliers are computed. Called by both setters, so the pair of
## settings can never disagree with the numbers the game is actually animating at.
func _apply_animation_multipliers() -> void:
	if reduce_motion_setting == "where_possible":
		card_match_animation_speed = SKIP_MULTIPLIER
		item_animation_speed = SKIP_MULTIPLIER
		pack_animation_speed = SKIP_MULTIPLIER
		return
	card_match_animation_speed = MATCH_SPEED_PRESETS[animation_speed_setting]
	item_animation_speed = ITEM_SPEED_PRESETS[animation_speed_setting]
	pack_animation_speed = PACK_SPEED_PRESETS[animation_speed_setting]


func set_intro_outro(choice: String, save: bool = true) -> void:
	if not choice in INTRO_OUTRO_OPTIONS:
		push_warning("GameState: unknown intro/outro choice '" + choice + "'")
		return
	intro_outro_setting = choice
	if save:
		_save_current_data_field("intro_outro_animation", intro_outro_setting)

# Reads every saved animation preset out of Player_Current_Data.json and applies it. Called once on
# boot. An unknown value falls back to the default rather than erroring, so a wiped or hand-edited
# save still boots cleanly.
func _load_animation_speed() -> void:
	var data := _read_current_data()

	# Reduce motion is read FIRST so the speed setter below computes the right multipliers on the
	# first pass rather than being immediately overwritten.
	var motion: String = str(data.get("reduce_motion", DEFAULT_REDUCE_MOTION))
	if not motion in REDUCE_MOTION_OPTIONS:
		motion = DEFAULT_REDUCE_MOTION
	reduce_motion_setting = motion

	var preset: String = str(data.get("animation_speed", DEFAULT_ANIMATION_SPEED))
	if not preset in ANIMATION_SPEED_OPTIONS:
		preset = DEFAULT_ANIMATION_SPEED
	set_animation_speed(preset, false)

	var intro: String = str(data.get("intro_outro_animation", DEFAULT_INTRO_OUTRO))
	if not intro in INTRO_OUTRO_OPTIONS:
		intro = DEFAULT_INTRO_OUTRO
	set_intro_outro(intro, false)

# ISSUE #34: the overworld walking-speed presets offered by the Options screen, keyed by the value
# stored in Player_Current_Data.json under "walking_speed". TWEAKABLE — raising a number speeds that
# preset up. Shift-to-run stacks on top of this (run_multiplier in Player_Object_Script.gd), so the
# gap between slow and fast reads more clearly while walking than while sprinting.
const WALKING_SPEED_PRESETS := {
	"very_slow": 0.4,
	"slow": 0.6,
	"normal": 1.1,
	"fast": 1.6,
}
const DEFAULT_WALKING_SPEED := "normal"

# The player's currently selected preset key. Persisted in Player_Current_Data.json.
var walking_speed_setting: String = DEFAULT_WALKING_SPEED

# Applies a preset key to the live walking multiplier. Pass save = true to also persist it.
func set_walking_speed(preset: String, save: bool = true) -> void:
	if not WALKING_SPEED_PRESETS.has(preset):
		push_warning("GameState: unknown walking speed preset '" + preset + "'")
		return
	walking_speed_setting = preset
	overworld_walking_speed = WALKING_SPEED_PRESETS[preset]
	if save:
		_save_walking_speed()

# Reads the saved preset out of Player_Current_Data.json and applies it. Called once on boot.
func _load_walking_speed() -> void:
	var data := _read_current_data()
	var preset: String = str(data.get("walking_speed", DEFAULT_WALKING_SPEED))
	if not WALKING_SPEED_PRESETS.has(preset):
		preset = DEFAULT_WALKING_SPEED
	set_walking_speed(preset, false)

func _save_walking_speed() -> void:
	_save_current_data_field("walking_speed", walking_speed_setting)

# ISSUE #34: the two match-rule variants offered by the Options screen. Each entry is the string
# stored in Player_Current_Data.json, and is copied into the match core's own burn_rules /
# confusion_rules at the start of every match.
#   Confusion — base_set:   retreat flip AFTER paying the energy; tails = energy still discarded
#                           and the Pokemon stays put.
#               fairer:     retreat flip BEFORE paying the energy; tails = 20 self-damage and the
#                           retreat is cancelled, but the energy is kept. (House rule.)
#               modern_era: confusion doesn't affect retreat at all (ex-era rules).
#   Burn      — base_set:   flip between turns; tails = 20 burn damage, and burn never self-cures.
#               modern_era: 20 burn damage every turn, then flip — heads cures the burn.
const CONFUSION_RULE_OPTIONS := ["base_set_confusion_rules", "fairer_confusion_rules", "modern_era_confusion_rules"]
const BURN_RULE_OPTIONS      := ["base_set_burn_rules", "modern_era_burn_rules"]
const DEFAULT_CONFUSION_RULE := "base_set_confusion_rules"
const DEFAULT_BURN_RULE      := "base_set_burn_rules"

var confusion_rule_setting: String = DEFAULT_CONFUSION_RULE
var burn_rule_setting: String = DEFAULT_BURN_RULE

# Applies a rule choice. Pass save = false to set it without touching the save file (used on boot).
func set_confusion_rule(rule: String, save: bool = true) -> void:
	if not rule in CONFUSION_RULE_OPTIONS:
		push_warning("GameState: unknown confusion rule '" + rule + "'")
		return
	confusion_rule_setting = rule
	if save:
		_save_current_data_field("confusion_rules", rule)

func set_burn_rule(rule: String, save: bool = true) -> void:
	if not rule in BURN_RULE_OPTIONS:
		push_warning("GameState: unknown burn rule '" + rule + "'")
		return
	burn_rule_setting = rule
	if save:
		_save_current_data_field("burn_rules", rule)

# Reads both saved rule choices out of Player_Current_Data.json. Called once on boot.
func _load_rule_settings() -> void:
	var data := _read_current_data()
	var confusion: String = str(data.get("confusion_rules", DEFAULT_CONFUSION_RULE))
	if not confusion in CONFUSION_RULE_OPTIONS:
		confusion = DEFAULT_CONFUSION_RULE
	set_confusion_rule(confusion, false)
	var burn: String = str(data.get("burn_rules", DEFAULT_BURN_RULE))
	if not burn in BURN_RULE_OPTIONS:
		burn = DEFAULT_BURN_RULE
	set_burn_rule(burn, false)

# NOTE: message box colour is deliberately NOT a setting here. Each NPC/opponent carries its own
# `message_colour` in All_NPC_Constant_Data.json and the box is themed per speaker — see
# MessageBoxTheme.

# ─── Audio volume ────────────────────────────────────────────────────────────
# Two independent 0.0 - 1.0 levels, one per audio bus. Unlike every other Options row these are
# continuous rather than a preset key, because they are driven by sliders. The actual decibel
# conversion and the bus wiring live in Sound_Manager_Script.gd; GameState only owns the value and
# its persistence in Player_Current_Data.json ("music_volume" / "sfx_volume").
#
# TWEAKABLE — the level a fresh save boots on. 0.8 rather than 1.0 so there is headroom to turn the
# game UP, which is the more useful direction when the default mix already sits near the ceiling.
const DEFAULT_MUSIC_VOLUME := 0.8
const DEFAULT_SFX_VOLUME   := 0.8

var music_volume_setting: float = DEFAULT_MUSIC_VOLUME
var sfx_volume_setting: float   = DEFAULT_SFX_VOLUME

# Applies a level to the Music bus. Pass save = false while a slider is being dragged so the player
# hears the change immediately without a disk write per pixel of travel — the Options screen commits
# it once, on Save.
func set_music_volume(value: float, save: bool = true) -> void:
	music_volume_setting = clampf(value, 0.0, 1.0)
	SoundManagerScript.set_bus_volume(SoundManagerScript.MUSIC_BUS, music_volume_setting)
	if save:
		_save_current_data_field("music_volume", music_volume_setting)

func set_sfx_volume(value: float, save: bool = true) -> void:
	sfx_volume_setting = clampf(value, 0.0, 1.0)
	SoundManagerScript.set_bus_volume(SoundManagerScript.SFX_BUS, sfx_volume_setting)
	if save:
		_save_current_data_field("sfx_volume", sfx_volume_setting)

# Reads both saved levels out of Player_Current_Data.json and applies them. Called once on boot. A
# missing or non-numeric value falls back to the default rather than erroring.
func _load_audio_volumes() -> void:
	var data := _read_current_data()
	set_music_volume(_read_volume(data, "music_volume", DEFAULT_MUSIC_VOLUME), false)
	set_sfx_volume(_read_volume(data, "sfx_volume", DEFAULT_SFX_VOLUME), false)

func _read_volume(data: Dictionary, key: String, fallback: float) -> float:
	var value = data.get(key, fallback)
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0)
	return fallback

# Writes a single key back into Player_Current_Data.json, leaving every other key untouched.
func _save_current_data_field(key: String, value) -> void:
	var data := _read_current_data()
	if data.is_empty():
		return
	data[key] = value
	var write_file := FileAccess.open(PLAYER_CURRENT_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("GameState: cannot write " + PLAYER_CURRENT_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

func _read_current_data() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_CURRENT_DATA_PATH):
		return {}
	var file := FileAccess.open(PLAYER_CURRENT_DATA_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

# Scales an animation DURATION by a speed multiplier (duration / multiplier), clamped so a zero or
# negative multiplier can never divide by zero or invert the animation.
func scaled_duration(base_seconds: float, multiplier: float) -> float:
	if multiplier <= 0.05:
		multiplier = 0.05
	return base_seconds / multiplier

# ISSUE #34: shorthands for the three animation multipliers. Prefer these over calling
# scaled_duration() with an explicit multiplier — they keep call sites short enough that wrapping a
# hardcoded duration stays a drop-in edit:
#     await get_tree().create_timer(0.5).timeout
#     await get_tree().create_timer(GameState.match_time(0.5)).timeout
#   match_time() — anything inside a card match
#   item_time()  — gift coin/card flips and costume fade-ins
#   pack_time()  — the pack opening sequence
# The match intro/outro scenes use plain literal durations; they are governed by an on/off choice,
# not a multiplier. Do NOT use any of these for loading throttles or asset-streaming waits — at a
# "skip" preset they collapse to ~0 and would spin those loops.
func match_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, card_match_animation_speed)

func item_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, item_animation_speed)

func pack_time(base_seconds: float) -> float:
	return scaled_duration(base_seconds, pack_animation_speed)

# True when the player has turned the match intro/outro ceremony OFF. Callers bypass whole sequences
# (and their sound) rather than playing them fast — see Match_Start_Intro_Script.gd and
# Match_End_Outro_Script.gd. Note this never suppresses a REWARD reveal: those follow item speed.
#
# This is NOT reduce motion. Reduce motion keeps the intro/outro screen and collapses its
# animations; this removes the screen. Both can be on, and then the screen never appears at all.
func is_transition_skipped() -> bool:
	return intro_outro_setting == "skip"

# True when the player has asked for reduced motion. Read it for anything decorative that a
# multiplier cannot express — the chevron scroll, the selection ring spin, a purely cosmetic drift.
func is_motion_reduced() -> bool:
	return reduce_motion_setting == "where_possible"

# True when the pack opening animation should be bypassed entirely — the buy press jumps straight to
# the finished row of cards. See Pack_Opening_Manager._start_pack_opening().
#
# This used to be its own "skip" preset on the pack speed ladder. It is reduce motion now, so a
# player who wants to stop watching pack tears turns off one switch rather than hunting three rows.
func is_pack_skipped() -> bool:
	return is_motion_reduced()

# TWEAKABLE — how long the intro / outro / best-of-three entrance takes, per Animation speed
# preset. Unlike the three tables above these are DIVISORS turned the other way up: the numbers
# authored into those screens are the FAST timings, and a slower preset stretches them. So a
# higher number here means a SLOWER screen, the opposite of MATCH_SPEED_PRESETS.
#
# Every duration AND every delay on those screens goes through transition_time(), so the ratio
# between elements is identical at all three settings — there is no per-element hand-tuning.
const TRANSITION_SPEED_PRESETS := {
	"slow": 2.0,
	"medium": 1.5,
	"fast": 1.0,
}

# Duration for a transition-screen tween — the match intro, outro and best-of-3 screens.
#
# The authored numbers are the "fast" timings; medium stretches them by 1.5 and slow by 2, from
# the one Animation speed row in Options.
#
# Under reduce motion the screen still APPEARS and every duration collapses to zero, so each
# element is already at rest on the first frame. That is the difference the player asked for:
# they want to stop the sliding and the fading, not to stop being told who they are about to
# fight. Removing the screen outright is what the separate intro/outro row does.
func transition_time(base_seconds: float) -> float:
	if is_motion_reduced():
		return 0.0
	return base_seconds * float(TRANSITION_SPEED_PRESETS.get(animation_speed_setting, 1.0))

var sleep_wakeup_fade: bool = false

# ISSUE #52: when a sub-menu (deck/costume/coin/sleeves/options/info) closes back to the standalone
# Main Menu, the menu redirects to the saved map scene with this flag set so the map is reloaded and
# the main menu is reopened as a transparent overlay on top of it (rather than showing black behind).
var reopen_menu_overlay: bool = false

# ISSUE #52 (retest): the live map scene registers itself here while its main-menu overlay is open.
# Sub-menus are then opened/closed as overlays on top of the still-loaded map, so returning to the
# main menu is instant instead of triggering a full world reload (the long black screen). Both
# helpers return false when there is no host (e.g. the menu was reached from a non-map scene), so
# every caller can fall back to the old change_scene behaviour.
var menu_overlay_host: Node = null

func open_sub_menu(scene_path: String) -> bool:
	if menu_overlay_host != null and is_instance_valid(menu_overlay_host) and menu_overlay_host.has_method("open_submenu_overlay"):
		menu_overlay_host.open_submenu_overlay(scene_path)
		return true
	return false

func close_sub_menu() -> bool:
	if menu_overlay_host != null and is_instance_valid(menu_overlay_host) and menu_overlay_host.has_method("close_submenu_overlay"):
		menu_overlay_host.close_submenu_overlay(true)
		return true
	return false

# ============================================================
# MATCH SERIES (best-of-N support)
# ============================================================
# Ephemeral — never saved to disk. Quitting the app mid-series
# resets the player to challenging the opponent fresh.
# Driven by an opponent's optional "match_format" field
# (e.g. "best_of_3"). Mid-series rematches bypass the outro and
# route straight to the intro; only the deciding game shows
# the outro/rewards.
var series_active: bool = false
var series_format: String = ""
var series_opponent_name: String = ""
var series_wins: int = 0
var series_losses: int = 0
var series_required_to_win: int = 0
var series_total_games: int = 0
var series_round_results: Array = []

func start_match_series(opponent_name: String, match_format: String) -> void:
	series_opponent_name = opponent_name
	series_format = match_format
	series_wins = 0
	series_losses = 0
	series_round_results = []
	match match_format:
		"best_of_3":
			series_total_games = 3
			series_required_to_win = 2
		_:
			# Unknown format — fall back to a single match.
			clear_match_series()
			return
	series_active = true

func clear_match_series() -> void:
	series_active = false
	series_format = ""
	series_opponent_name = ""
	series_wins = 0
	series_losses = 0
	series_total_games = 0
	series_required_to_win = 0
	series_round_results = []

# ============================================================
# CURRENT SCENE PERSISTENCE
# Tracks the player's current map and position so that the
# splash-screen entry point can resume them at the right place
# after the game restarts. Updated whenever the player moves
# between map scenes.
# ============================================================

const DEFAULT_START_SCENE := "res://Scenes/Map_Scenes/Player_House_Upstairs.tscn"

func save_current_location(scene_path: String, pos: Vector2) -> void:
	progress["current_scene_path"] = scene_path
	progress["current_player_position"] = {"x": pos.x, "y": pos.y}
	save_progress()

func get_saved_scene_path() -> String:
	return progress.get("current_scene_path", DEFAULT_START_SCENE)

func get_saved_player_position() -> Vector2:
	var data = progress.get("current_player_position", null)
	if data is Dictionary and data.has("x") and data.has("y"):
		return Vector2(float(data["x"]), float(data["y"]))
	return Vector2.ZERO

func has_saved_player_position() -> bool:
	return progress.has("current_player_position")

# Captures the live player position from whichever map scene is active and
# writes it to disk. Called on window close so a quit-mid-walk doesn't lose
# the player's actual position.
func _save_live_player_position_on_quit() -> void:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	var scene_path := String(current_scene.scene_file_path)
	var player = current_scene.get_node_or_null("Player")
	if player == null:
		return
	if not (player is Node2D):
		return
	save_current_location(scene_path, player.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_live_player_position_on_quit()
		get_tree().quit()

# ============================================================
# MENU RETURN STATE
# Set by a map scene before opening the main menu so the player
# can be restored to the exact spot when the menu closes.
# Survives navigation through sub-menus (deck builder, options,
# coin case, trainer card) and is consumed by the destination
# map scene's _ready.
# ============================================================

var has_menu_return_state: bool = false
var menu_return_scene_path: String = ""
var menu_return_position: Vector2 = Vector2.ZERO
var menu_return_direction: String = "down"

func save_menu_return_state(scene_path: String, pos: Vector2, direction: String) -> void:
	has_menu_return_state = true
	menu_return_scene_path = scene_path
	menu_return_position = pos
	menu_return_direction = direction

func clear_menu_return_state() -> void:
	has_menu_return_state = false
	menu_return_scene_path = ""

# Progress tracking
var progress: Dictionary = {}

# user:// is writable in both editor and exported builds.
# On first run, if the file doesn't exist, we copy from res://.
const PROGRESS_PATH = "user://Player_Game_Progress.json"
const PROGRESS_SEED_PATH = "res://Player_Data/Player_Game_Progress.json"

const PLAYER_CURRENT_DATA_PATH = "user://Player_Current_Data.json"
const PLAYER_CURRENT_DATA_SEED_PATH = "res://Player_Data/Player_Current_Data.json"

const OWNED_CARDS_FOLDER = "user://Player_Owned_Cards/"
const OWNED_CARDS_SEED_FOLDER = "res://Player_Data/Player_Owned_Cards/"

const PLAYER_DECKS_FOLDER = "user://Player_Decks/"
const PLAYER_DECKS_SEED_FOLDER = "res://Player_Data/Player_Decks/"

# ============================================================
# INTERIOR SCENE TRANSITIONS
# ============================================================

var last_player_direction: String = "down"

func save_player_direction(direction: String):
	last_player_direction = direction

func get_player_direction() -> String:
	return last_player_direction

func save_interior_player_position(pos: Vector2):
	player_position = pos
	print("Saved interior position: ", pos)

func get_interior_player_position() -> Vector2:
	return player_position

func set_last_interior_scene(scene_name: String):
	last_interior_scene = scene_name
	print("Set last interior scene: ", scene_name)

func get_last_interior_scene() -> String:
	return last_interior_scene

# ============================================================
# ISSUE #253 - CLICK QUEUEING
# ============================================================
# REVERTED at the user's request (01/09/2026 retest 2). There WAS a global
# `_input` here that swallowed any mouse press arriving within 260ms of the last
# accepted one. It is gone, and deliberately not coming back.
#
# Why the whole idea was wrong: a time window can only ever say "that click came
# too soon", and the symptom the player actually sees - a button that keeps
# firing after they have stopped clicking - is a SLOW SCREEN, not a fast player.
# When a handler takes 300ms to redraw, every one of the player's clicks is
# hundreds of ms apart and every one of them is legitimate, so no window catches
# them; meanwhile the window is busy eating deliberate clicks on every fast
# screen in the game. It cost real input and bought nothing.
#
# The fix that does work is per-screen and is the opposite shape: a control that
# starts something is held DISABLED until the thing it started is on screen. See
# Pack_Purchase_Script._step_to_current_set for the worked example, and
# UIKit.hold_buttons() for the helper to do it on any other screen that shows the
# same symptom.


func _ready():
	_ensure_user_data_exists()
	load_progress()
	_load_animation_speed()   # ISSUE #34: apply the saved Options animation-speed preset
	_load_walking_speed()     # ISSUE #34: apply the saved Options overworld walking-speed preset
	_load_rule_settings()     # ISSUE #34: apply the saved Options confusion / burn rule choices
	_load_audio_volumes()     # apply the saved Options music / SFX volume levels to the audio buses

# ============================================================
# FIRST-RUN DATA MIGRATION (res:// → user://)
# ============================================================

func _ensure_user_data_exists():
	# Copy Player_Game_Progress.json
	_copy_seed_file(PROGRESS_SEED_PATH, PROGRESS_PATH)

	# Copy Player_Current_Data.json
	_copy_seed_file(PLAYER_CURRENT_DATA_SEED_PATH, PLAYER_CURRENT_DATA_PATH)

	# Copy Player_Owned_Cards folder
	_copy_seed_folder(OWNED_CARDS_SEED_FOLDER, OWNED_CARDS_FOLDER)

	# Copy Player_Decks folder
	_copy_seed_folder(PLAYER_DECKS_SEED_FOLDER, PLAYER_DECKS_FOLDER)


func _copy_seed_file(seed_path: String, dest_path: String):
	if FileAccess.file_exists(dest_path):
		return
	if not FileAccess.file_exists(seed_path):
		return
	var file = FileAccess.open(seed_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var write_file = FileAccess.open(dest_path, FileAccess.WRITE)
	write_file.store_string(content)
	write_file.close()
	print("Copied seed file: ", seed_path, " -> ", dest_path)


func _copy_seed_folder(seed_folder: String, dest_folder: String):
	if not DirAccess.dir_exists_absolute(seed_folder):
		return
	if not DirAccess.dir_exists_absolute(dest_folder):
		DirAccess.make_dir_recursive_absolute(dest_folder)
	var dir = DirAccess.open(seed_folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			var dest_file = dest_folder + file_name
			if not FileAccess.file_exists(dest_file):
				_copy_seed_file(seed_folder + file_name, dest_file)
		file_name = dir.get_next()
	dir.list_dir_end()

# ============================================================
# PROGRESS FILE I/O
# ============================================================

func load_progress():
	if FileAccess.file_exists(PROGRESS_PATH):
		var file = FileAccess.open(PROGRESS_PATH, FileAccess.READ)
		var text = file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(text)
		if parsed != null:
			progress = parsed
		else:
			progress = {"opponents_beaten": [], "cash": 0, "coins": [], "costumes": []}
	else:
		progress = {"opponents_beaten": [], "cash": 0, "coins": [], "costumes": []}
		save_progress()

	# Ensure all expected fields exist for saves created before this update
	if not progress.has("cash"):
		progress["cash"] = 0
	if not progress.has("coins"):
		progress["coins"] = []
	if not progress.has("costumes"):
		progress["costumes"] = []
	if not progress.has("player_collected_starter_box"):
		progress["player_collected_starter_box"] = false
	if not progress.has("moving_in_completed"):
		progress["moving_in_completed"] = false
	if not progress.has("gifts_received"):
		progress["gifts_received"] = []
	if not progress.has("opponents_beaten_count_current"):
		progress["opponents_beaten_count_current"] = 0
	if not progress.has("opponents_beaten_count_total"):
		progress["opponents_beaten_count_total"] = 0
	if not progress.has("time"):
		progress["time"] = "Morning"
	elif progress.get("time") == "Day":
		progress["time"] = "Morning"
	if not progress.has("date"):
		progress["date"] = 1

	if not progress.has("gym_challenge_audience"):
		progress["gym_challenge_audience"] = {}
	if not progress.has("gym_challenge_audience_time"):
		progress["gym_challenge_audience_time"] = ""
	if not progress.has("gym_challenge_audience_date"):
		progress["gym_challenge_audience_date"] = 0
	if not progress.has("gym_challenge_audience_from_plaza"):
		progress["gym_challenge_audience_from_plaza"] = false

	# Story flags are seeded so they are visible in the save file rather than only existing
	# once raised. An opponent-derived flag is seeded from its own source of truth, so a save
	# that already beat that opponent starts with the flag up rather than never getting it.
	for unlock_opponent in OPPONENT_FLAG_UNLOCKS:
		var unlock_flag: String = OPPONENT_FLAG_UNLOCKS[unlock_opponent]
		if not progress.has(unlock_flag):
			progress[unlock_flag] = unlock_opponent in progress.get("opponents_beaten", [])

	if not progress.has("shop_state"):
		progress["shop_state"] = "initial"
	if not progress.has("shop_free_packs_given"):
		progress["shop_free_packs_given"] = false
	if not progress.has("player_collected_shop_starter_set"):
		progress["player_collected_shop_starter_set"] = false
	# Existing saves predate this field — treat them as already launched.
	# New games get false from the seed file, so this migration never fires for them.
	if not progress.has("first_launch_complete"):
		progress["first_launch_complete"] = true

	# Migrate old met_npcs dict to npc_interactions array
	if not progress.has("npc_interactions"):
		var old = progress.get("met_npcs", {})
		progress["npc_interactions"] = old.keys()
		progress.erase("met_npcs")

	# ISSUE #129: the three starter card backs the player owns from the very first launch.
	# Kept in step with the "sleeves" array in Player_Data/Player_Game_Progress.json, which is
	# what a brand-new save actually copies -- this branch only catches a save made before the
	# key existed. "default" used to stand in here and matched no file on disk, so the sleeve
	# grid had nothing to show and _resolve_sleeve_path() fell through to its hardcoded default.
	if not progress.has("sleeves"):
		progress["sleeves"] = STARTER_SLEEVES.duplicate()

	# Migrate old coin filenames from "coin_pikachu_gold.png" to "Pikachu Gold.png"
	var coins_arr : Array = progress.get("coins", [])
	var migrated_any := false
	for i in coins_arr.size():
		if (coins_arr[i] as String).begins_with("coin_"):
			coins_arr[i] = _migrate_old_coin_name(coins_arr[i])
			migrated_any = true
	if migrated_any:
		progress["coins"] = coins_arr

	save_progress()

func save_progress():
	var file = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(progress, "\t"))
	file.close()

func mark_first_launch_complete() -> void:
	progress["first_launch_complete"] = true
	# Safety reset: zero every owned card and lock all pack sets so a game
	# reset always starts clean regardless of leftover user:// data.
	_reset_all_owned_cards()
	progress["packs_unlocked"] = []
	save_progress()

func _reset_all_owned_cards() -> void:
	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_player_owned_cards.json"):
			var path := OWNED_CARDS_FOLDER + fname
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var data = JSON.parse_string(f.get_as_text())
				f.close()
				if data is Dictionary and data.has("owned_cards"):
					for entry in data["owned_cards"]:
						entry["owned"] = 0
					var wf := FileAccess.open(path, FileAccess.WRITE)
					if wf != null:
						wf.store_string(JSON.stringify(data, "\t"))
						wf.close()
		fname = dir.get_next()
	dir.list_dir_end()

# Converts old "coin_pikachu_gold_1.png" format to "Pikachu Gold 1.png".
# Handles teamXXX compound words (teamplasma → Team Plasma, etc.).
func _migrate_old_coin_name(old: String) -> String:
	var base := old.replace("coin_", "").replace(".png", "")
	for team in ["teamplasma", "teamrocket", "teamaqua", "teammagma"]:
		base = base.replace(team, team.substr(0, 4) + "_" + team.substr(4))
	var parts := base.split("_")
	var titled : Array = []
	for p in parts:
		if p.length() > 0:
			titled.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(titled) + ".png"

# ============================================================
# CASH
# ============================================================

func get_cash() -> int:
	return progress.get("cash", 1000)

func add_cash(amount: int) -> void:
	progress["cash"] = get_cash() + amount
	save_progress()

# ============================================================
# OPPONENT TRACKING
# ============================================================

func has_beaten_opponent(opponent_name: String) -> bool:
	return opponent_name in progress.get("opponents_beaten", [])

func mark_opponent_beaten(opponent_name: String):
	if not has_beaten_opponent(opponent_name):
		progress["opponents_beaten"].append(opponent_name)
		progress["opponents_beaten_count_current"] = progress.get("opponents_beaten_count_current", 0) + 1
		progress["opponents_beaten_count_total"] = progress.get("opponents_beaten_count_total", 0) + 1
		if OPPONENT_FLAG_UNLOCKS.has(opponent_name):
			progress[OPPONENT_FLAG_UNLOCKS[opponent_name]] = true
		save_progress()


# ── HEAD-TO-HEAD RECORD ──────────────────────────────────────────────────────
# One wins/losses pair per opponent, keyed by the same name every other opponent
# call uses. Feeds the "Record vs <opponent>" item on the win and loss screens.
#
# This is a SERIES-LEVEL tally, not a game-level one: a best-of-three counts once,
# when it is decided, because that is what the player would call a match. The
# rounds inside it are the round tracker's business.
#
# `opponents_beaten` is a set and cannot answer this — it knows whether you have
# ever won, not how many times, and nothing at all about losses.
const OPPONENT_RECORD_KEY := "opponent_records"

## The pair for one opponent as [wins, losses]. An opponent never fought reads
## 0 – 0, which is the correct thing to show on a first meeting.
func get_opponent_record(opponent_name: String) -> Array:
	var records: Dictionary = progress.get(OPPONENT_RECORD_KEY, {})
	var entry: Dictionary = records.get(opponent_name, {})
	return [int(entry.get("w", 0)), int(entry.get("l", 0))]


## Adds one finished MATCH to an opponent's record. Called from the outro, which
## runs once per match — including the deciding game of a best-of-three, and not
## on the rounds before it. Test matches are ignored: they have no real opponent.
func record_opponent_result(opponent_name: String, won: bool) -> void:
	if test_match_mode or opponent_name == "":
		return
	if not progress.has(OPPONENT_RECORD_KEY):
		progress[OPPONENT_RECORD_KEY] = {}
	var records: Dictionary = progress[OPPONENT_RECORD_KEY]
	var entry: Dictionary = records.get(opponent_name, {"w": 0, "l": 0})
	entry["w" if won else "l"] = int(entry.get("w" if won else "l", 0)) + 1
	records[opponent_name] = entry
	save_progress()

# ============================================================
# STORY FLAGS
# ============================================================
# One-way global switches for milestones the whole game keys off. They live as plain
# top-level keys in `progress` because that is exactly what the character-schedule gate
# "requires: flag: NAME" already reads — declaring a flag here makes it usable in every
# character JSON with no extra plumbing.

## Raised the first time the player beats Gym Challenge Giovanni, i.e. the whole Gym
## Challenge is complete. Currently gates the Gym packs at the Weighed Pack Seller.
const GYM_CHALLENGE_COMPLETE_FLAG := "gym_challenge_complete"

## opponent name -> flag raised by their first defeat. Handled in mark_opponent_beaten().
const OPPONENT_FLAG_UNLOCKS := {
	"Gym Challenge Giovanni": GYM_CHALLENGE_COMPLETE_FLAG,
}

func has_flag(flag_name: String) -> bool:
	return bool(progress.get(flag_name, false))

func set_flag(flag_name: String, value: bool = true) -> void:
	if bool(progress.get(flag_name, false)) == value:
		return
	progress[flag_name] = value
	save_progress()

# ============================================================
# MATCH RECORD
# ============================================================

# Lifetime tally of individual MATCHES — a different number from the opponent counters above,
# which only move the first time each opponent falls. Every finished match counts here: each
# round of a best-of-3 separately, a rematch against an already-beaten opponent again, and a
# forfeit as a played loss. Losses are matches_played - matches_won, so they aren't stored.
# Called from Main_Match_Core_Gameplay_Script.game_end_logic(), the one place a result is set.
func record_match_result(won: bool) -> void:
	if test_match_mode:
		return  # the T-key debug match isn't a real match — keep it out of the trainer card
	progress["matches_played"] = int(progress.get("matches_played", 0)) + 1
	if won:
		progress["matches_won"] = int(progress.get("matches_won", 0)) + 1
	save_progress()

# ============================================================
# TIME / DATE SYSTEM
# ============================================================

## Returns the current time of day string ("Morning", "Afternoon", "Evening", "Night")
func get_time() -> String:
	return progress.get("time", "Morning")

## Returns the current date as an integer (1, 2, 3, ...)
func get_date() -> int:
	return int(progress.get("date", 1))

func get_current_defeated() -> int:
	return int(progress.get("opponents_beaten_count_current", 0))

## Sets the time to a specific value. Pass an empty string to auto-step.
## Auto-step: Morning -> Afternoon -> Evening -> Night -> Morning (and increment date).
## Resets opponents_beaten_count_current to 0 on every time change.
func advance_time(new_time: String = "") -> void:
	if new_time == "":
		# Auto-step to next time period
		match get_time():
			"Morning":
				new_time = "Afternoon"
			"Afternoon":
				new_time = "Evening"
			"Evening":
				new_time = "Night"
			"Night":
				new_time = "Morning"
				progress["date"] = get_date() + 1
			_:
				new_time = "Morning"
	elif new_time == "Morning" and get_time() == "Night":
		# If explicitly moving from Night to Morning, also increment date
		progress["date"] = get_date() + 1

	progress["time"] = new_time
	progress["opponents_beaten_count_current"] = 0
	save_progress()
	print("Time advanced to: ", new_time, " | Date: ", get_date())

# ============================================================
# NPC INTERACTION TRACKING
# ============================================================

func has_met_npc(npc_name: String) -> bool:
	return npc_name in progress.get("npc_interactions", [])

func mark_npc_met(npc_name: String) -> void:
	if not has_met_npc(npc_name):
		if not progress.has("npc_interactions"):
			progress["npc_interactions"] = []
		progress["npc_interactions"].append(npc_name)
		save_progress()

# ============================================================
# GIFT TRACKING
# ============================================================

func has_received_gift(npc_name: String) -> bool:
	return npc_name in progress.get("gifts_received", [])

func mark_gift_received(npc_name: String):
	if not has_received_gift(npc_name):
		progress["gifts_received"].append(npc_name)
		save_progress()

# ============================================================
# COSMETIC ASSET UNIVERSES
# ============================================================
# ISSUE #134: "what could I possibly own" for each cosmetic collection. These used to live as
# private helpers in Info_Script (they drive the X / Y counters on the trainer card); the
# CHT.All_* cheats need exactly the same lists, so they moved here rather than being copied.
# Each universe is keyed EXACTLY the way that collection is stored in `progress`, so ownership
# is a straight lookup and no per-collection name-munging is needed at the call site.

const COIN_ASSET_FOLDER    := "res://Image_Assets/Coins"
const COIN_BACK_IMAGE      := "Back Basic.png"   # placeholder art for unowned coins, not a collectible
const COSTUME_ASSET_FOLDER := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const SLEEVE_SMALL_FOLDER  := "res://Image_Assets/Sleeves/small"  # what the sleeve grid lists

# Lists the real asset files in a res:// folder. The editor shows "Ditto.jpg" next to its
# "Ditto.jpg.import" sidecar, and an exported build can list "Ditto.jpg.remap" instead, so both
# suffixes are stripped and the result de-duplicated through a Dictionary.
func list_asset_files(folder: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("GameState: cannot open folder " + folder)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			out[clean] = true
		fname = dir.get_next()
	dir.list_dir_end()
	return out

# progress["coins"] holds filenames: "Pikachu Gold.png"
func get_coin_universe() -> Dictionary:
	var out: Dictionary = {}
	for fname in list_asset_files(COIN_ASSET_FOLDER):
		if fname != COIN_BACK_IMAGE:
			out[fname] = true
	return out

# progress["costumes"] holds lowercased filenames: "1ash.png"
func get_costume_universe() -> Dictionary:
	var out: Dictionary = {}
	for fname in list_asset_files(COSTUME_ASSET_FOLDER):
		out[String(fname).to_lower()] = true
	return out

# progress["sleeves"] holds bare basenames: "Ditto". `include_defaults` controls the four
# "1_Default*" card backs: the sleeve GRID shows them (so the CHT.All_Sleeves cheat grants them),
# but the trainer card's collected counter excludes them — freebies every save starts with are
# not "collected".
func get_sleeve_universe(include_defaults: bool = false) -> Dictionary:
	var out: Dictionary = {}
	for fname in list_asset_files(SLEEVE_SMALL_FOLDER):
		if not include_defaults and String(fname).begins_with(DEFAULT_SLEEVE_PREFIX):
			continue
		out[String(fname).get_basename()] = true
	return out


# ============================================================
# ENERGY STYLE COLLECTION
# ============================================================
# Which printing of the six basic Energy a deck uses. ISSUE #155 moved this table here from
# Deck_Build_And_Card_View_Script so the CHT.All_Energy_Styles cheat and the deck builder's picker
# read the SAME list — the ISSUE #134 rule: a cheat that grants "all" of something must be driven
# by the same universe the screen displays, or the two drift.
#
# Key   = the style name, exactly as it is stored in progress["energy_styles"].
# Value = that style's six basic Energy card ids, in the order
#         Grass, Fire, Water, Lightning, Psychic, Fighting.
# Adding a style is one entry here and nothing else.
const ENERGY_STYLES : Dictionary = {
	"Base1":  ["base1-99",  "base1-98",  "base1-102", "base1-100", "base1-101", "base1-97"],
	"Ecard1": ["ecard1-162","ecard1-161","ecard1-165","ecard1-163","ecard1-164","ecard1-160"],
	"ex1":    ["ex1-104",   "ex1-108",   "ex1-106",   "ex1-109",   "ex1-107",   "ex1-105"],
	"ex9":    ["ex9-101",   "ex9-102",   "ex9-103",   "ex9-104",   "ex9-105",   "ex9-106"],
	"ex13":   ["ex13-105",  "ex13-106",  "ex13-107",  "ex13-108",  "ex13-109",  "ex13-110"],
	"ex16":   ["ex16-103",  "ex16-104",  "ex16-105",  "ex16-106",  "ex16-107",  "ex16-108"],
}


## Every style that exists, whether or not the player has it. Named to match
## get_coin_universe() / get_costume_universe() / get_sleeve_universe().
func get_energy_style_universe() -> Array:
	return ENERGY_STYLES.keys()


## The styles the player has unlocked. "Base1" is the floor — a save with nothing recorded still has
## the Base Set printing, because the deck builder has to render SOME energy.
func get_energy_styles() -> Array:
	var styles : Array = progress.get("energy_styles", [])
	if styles.is_empty():
		return ["Base1"]
	return styles


# ISSUE #155: bulk grant used by the CHT.All_Energy_Styles cheat. One save at the end, the same
# reasoning as add_coins_to_collection(). Returns how many were newly added.
func add_energy_styles_to_collection(style_names: Array) -> int:
	var styles : Array = progress.get("energy_styles", [])
	var added := 0
	for raw in style_names:
		var style_name := String(raw)
		if style_name not in styles:
			styles.append(style_name)
			added += 1
	if added > 0:
		progress["energy_styles"] = styles
		save_progress()
	return added


# ============================================================
# COIN COLLECTION
# ============================================================

func add_coin_to_collection(coin_name: String):
	var coins = progress.get("coins", [])
	var coin_filename = coin_name if coin_name.ends_with(".png") else coin_name + ".png"
	if coin_filename not in coins:
		coins.append(coin_filename)
		progress["coins"] = coins
		save_progress()

func has_coin(coin_name: String) -> bool:
	var coins = progress.get("coins", [])
	var coin_filename = coin_name if coin_name.ends_with(".png") else coin_name + ".png"
	return coin_filename in coins

func get_coins() -> Array:
	return progress.get("coins", [])

# ISSUE #134: bulk grant used by the CHT.All_Coins cheat. Saves ONCE at the end rather than once
# per coin — add_coin_to_collection() writes the whole progress file every call, which over 400+
# coins would be 400+ disk writes. Names are canonicalised the same way as the singular version,
# so it accepts either "Pikachu Gold" or "Pikachu Gold.png". Returns how many were newly added.
func add_coins_to_collection(coin_names: Array) -> int:
	var coins: Array = progress.get("coins", [])
	var added := 0
	for raw in coin_names:
		var coin_filename := String(raw)
		if not coin_filename.ends_with(".png"):
			coin_filename += ".png"
		if coin_filename not in coins:
			coins.append(coin_filename)
			added += 1
	if added > 0:
		progress["coins"] = coins
		save_progress()
	return added

# ============================================================
# COSTUME COLLECTION
# ============================================================

func has_costume(battle_sprite: String) -> bool:
	var costumes = progress.get("costumes", [])
	var costume_filename = battle_sprite.to_lower() + ".png"
	return costume_filename in costumes

func add_costume_to_collection(battle_sprite: String) -> void:
	var costumes = progress.get("costumes", [])
	var costume_filename = battle_sprite.to_lower() + ".png"
	if costume_filename not in costumes:
		costumes.append(costume_filename)
		progress["costumes"] = costumes
		save_progress()

func get_costumes() -> Array:
	return progress.get("costumes", [])

# ISSUE #134: bulk grant used by the CHT.All_Costumes cheat. One save at the end, same reasoning
# as add_coins_to_collection(). Accepts either a bare sprite name or a stored "1ash.png" filename.
func add_costumes_to_collection(battle_sprites: Array) -> int:
	var costumes: Array = progress.get("costumes", [])
	var added := 0
	for raw in battle_sprites:
		var costume_filename := String(raw).to_lower()
		if not costume_filename.ends_with(".png"):
			costume_filename += ".png"
		if costume_filename not in costumes:
			costumes.append(costume_filename)
			added += 1
	if added > 0:
		progress["costumes"] = costumes
		save_progress()
	return added

# ============================================================
# SLEEVE COLLECTION
# ============================================================

func has_sleeve(sleeve_name: String) -> bool:
	return sleeve_name in progress.get("sleeves", [])

func add_sleeve_to_collection(sleeve_name: String) -> void:
	var sleeves = progress.get("sleeves", [])
	if sleeve_name not in sleeves:
		sleeves.append(sleeve_name)
		progress["sleeves"] = sleeves
		save_progress()

func get_sleeves() -> Array:
	return progress.get("sleeves", [])

# ISSUE #134: bulk grant used by the CHT.All_Sleeves cheat. One save at the end, same reasoning as
# add_coins_to_collection(). Sleeves are stored as bare basenames, so any extension is stripped.
func add_sleeves_to_collection(sleeve_names: Array) -> int:
	var sleeves: Array = progress.get("sleeves", [])
	var added := 0
	for raw in sleeve_names:
		var sleeve_name := String(raw).get_basename()
		if sleeve_name not in sleeves:
			sleeves.append(sleeve_name)
			added += 1
	if added > 0:
		progress["sleeves"] = sleeves
		save_progress()
	return added


# ============================================================
# CARD GIVING (Global)
# ============================================================
# Accepts a comma-separated string of card IDs, e.g.:
#   "base1-1, base2-5, base5-20"
# Duplicates are fine — each occurrence increments owned count by 1.
# Batches writes per set file so "base1-1, base1-1, base1-5" only
# opens/writes the base1 file once.

func give_cards(card_ids_csv: String) -> void:
	var ids: Array = []
	for raw in card_ids_csv.split(","):
		var trimmed = raw.strip_edges()
		if trimmed != "":
			ids.append(trimmed)

	if ids.is_empty():
		push_error("GameState.give_cards: No valid card IDs in: " + card_ids_csv)
		return

	# Group by set name so we only read/write each file once
	var by_set: Dictionary = {}
	for card_id in ids:
		var parts = card_id.split("-")
		if parts.size() < 2:
			push_error("GameState.give_cards: Invalid card_id format: " + card_id)
			continue
		var set_name = parts[0]
		if not by_set.has(set_name):
			by_set[set_name] = []
		by_set[set_name].append(card_id)

	for set_name in by_set.keys():
		var json_path = OWNED_CARDS_FOLDER + set_name + "_player_owned_cards.json"
		var file = FileAccess.open(json_path, FileAccess.READ)
		if file == null:
			push_error("GameState.give_cards: Cannot open: " + json_path)
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()

		for card_id in by_set[set_name]:
			var found = false
			for entry in data["owned_cards"]:
				if entry["card_id"] == card_id:
					entry["owned"] = entry["owned"] + 1
					found = true
					break
			if not found:
				data["owned_cards"].append({"card_id": card_id, "owned": 1})

		data["set_unlocked"] = true
		var write_file = FileAccess.open(json_path, FileAccess.WRITE)
		write_file.store_string(JSON.stringify(data, "\t"))
		write_file.close()

	print("GameState.give_cards: Gave ", ids.size(), " cards")


# ============================================================
# CARD REMOVING (Global)
# ============================================================
# The counterpart to give_cards(), written for the Card Buyer's bulk-sell screen.
# Takes a {card_id: count} dictionary rather than a CSV because every caller so far
# already has its counts tallied, and a 300-card sale as a comma-separated string
# would be absurd.
#
# Batches per set file exactly as give_cards() does, so a 200-card sale spanning
# seven sets is seven reads and seven writes rather than 400.
#
# NEVER goes below zero and never removes a card the file does not list: the sell
# screen only ever offers copies it read out of these same files, so a mismatch
# means something else has already changed them and the safe move is to leave the
# entry alone rather than invent a negative.
#
# set_unlocked is deliberately NOT touched — selling every spare copy of a set's
# cards does not re-lock the set.

func remove_cards(counts: Dictionary) -> int:
	if counts.is_empty():
		return 0

	# Group by set name so we only read/write each file once
	var by_set: Dictionary = {}
	for card_id in counts.keys():
		var amount: int = int(counts[card_id])
		if amount <= 0:
			continue
		var parts = String(card_id).split("-")
		if parts.size() < 2:
			push_error("GameState.remove_cards: Invalid card_id format: " + str(card_id))
			continue
		var set_name = parts[0]
		if not by_set.has(set_name):
			by_set[set_name] = {}
		by_set[set_name][card_id] = amount

	var removed_total: int = 0

	for set_name in by_set.keys():
		var json_path = OWNED_CARDS_FOLDER + set_name + "_player_owned_cards.json"
		var file = FileAccess.open(json_path, FileAccess.READ)
		if file == null:
			push_error("GameState.remove_cards: Cannot open: " + json_path)
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if not (data is Dictionary and data.has("owned_cards")):
			push_error("GameState.remove_cards: Unexpected format in: " + json_path)
			continue

		var wanted: Dictionary = by_set[set_name]
		for entry in data["owned_cards"]:
			var cid = entry.get("card_id", "")
			if not wanted.has(cid):
				continue
			var have: int = int(entry.get("owned", 0))
			var take: int = mini(int(wanted[cid]), have)
			if take <= 0:
				continue
			entry["owned"] = have - take
			removed_total += take

		var write_file = FileAccess.open(json_path, FileAccess.WRITE)
		if write_file == null:
			push_error("GameState.remove_cards: Cannot write: " + json_path)
			continue
		write_file.store_string(JSON.stringify(data, "\t"))
		write_file.close()

	print("GameState.remove_cards: Removed ", removed_total, " cards across ",
		by_set.size(), " set file(s)")
	return removed_total
