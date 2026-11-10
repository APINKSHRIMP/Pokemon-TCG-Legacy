extends Node

# ============================================================
# SOUND MANAGER - Autoload Singleton
# ============================================================
# Handles all audio playback: SFX (one-shot) and BGM (looping).
# Register this as an Autoload named "SoundManagerScript".
#
# Every sound in the game is routed through one of three audio buses created at boot by
# _ensure_buses() — MUSIC_BUS for anything looping in the background, SFX_BUS for one-shots, and
# AUDITION_BUS for the debug music preview. The Options screen drives the first two via
# GameState.set_music_volume / set_sfx_volume, so the two sliders there cover the overworld, the
# menus AND a match without any per-scene plumbing.
#
# AUDITION_BUS is deliberately NOT wired to either slider: the debug character editor's PLAY button
# has to stay audible while the music slider is muted, which is exactly what you want when picking
# opponent tracks with the overworld loop silenced. It sits at a fixed AUDITION_VOLUME instead.
#
# The buses are built in code rather than in a default_bus_layout.tres so there is no resource file
# to keep in sync with this script. If you add a NEW AudioStreamPlayer anywhere outside this
# singleton, set its .bus to MUSIC_BUS or SFX_BUS or it will land on "Master" and ignore the
# sliders entirely.
# ============================================================

# ─── Audio buses ─────────────────────────────────────────────────────────────

const MUSIC_BUS    := "Music"
const SFX_BUS      := "SFX"
## Overworld Pokémon cries, with their own Options slider (GameState.set_cries_volume).
const CRIES_BUS    := "Cries"
const AUDITION_BUS := "Audition"

# TWEAKABLE — the fixed 0.0 - 1.0 level the debug music audition plays at. Matches the default music
# volume so a track sounds in the preview roughly the way it will in a match.
const AUDITION_VOLUME := 0.8

# The player-facing volume, 0.0 - 1.0, is converted to decibels with linear_to_db(): 1.0 = 0 dB
# (untouched), 0.5 = -6 dB, 0.1 = -20 dB. A slider sitting at exactly 0 mutes its bus outright
# rather than trying to express silence in decibels.
func _ready() -> void:
	_ensure_buses()

# Creates the Music, SFX and Audition buses if they don't exist yet. Idempotent, so it is safe to
# call from set_bus_volume() as well — GameState applies the saved volumes during its own _ready()
# and the autoload order that puts this singleton first is not something to depend on silently.
func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS, CRIES_BUS, AUDITION_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
		# The audition bus has no slider behind it, so its level is set once, here.
		if bus_name == AUDITION_BUS:
			AudioServer.set_bus_volume_db(idx, linear_to_db(AUDITION_VOLUME))

# Sets one bus to a 0.0 - 1.0 level. Callers should go through GameState so the choice is persisted.
func set_bus_volume(bus_name: String, linear: float) -> void:
	_ensure_buses()
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("SoundManager: unknown audio bus '" + bus_name + "'")
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	if linear > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

# --- Preloaded SFX constants ---
const SFX_attack_sound = preload("res://Audio/SFX/attack_sound.ogg")
const SFX_coin_flip_sound = preload("res://Audio/SFX/coin_flip_sound.ogg")
# Placeholder: a copy of coin_flip_sound until the real landing sound is dropped in over it.
const SFX_coin_land_sound = preload("res://Audio/SFX/coin_land_sound.ogg")
const SFX_knockout_sound = preload("res://Audio/SFX/knockout_sound.ogg")
const SFX_select_button = preload("res://Audio/SFX/select_button.ogg")
## ISSUE #447 / #454: the quiet blip - a menu cursor moving, a hand card pressed.
const SFX_select_change = preload("res://Audio/SFX/Select_Change.ogg")
## MATCH SFX OLD / NEW SWITCH (2026-11-06). true = the newer evolve / energy clips plus the louder,
## slightly slower draw / shuffle; false = the very first match sounds the game shipped with.
## TWEAKABLE: flip it, or point any *_NEW path at another clip.
const USE_NEW_MATCH_SFX := true
const SFX_EVOLVE_OLD := "res://Audio/SFX/evolve_sound.ogg"
const SFX_EVOLVE_NEW := "res://Audio/SFX/Evolve.ogg"
const SFX_ENERGY_OLD := "res://Audio/SFX/energy_sound.ogg"
const SFX_ENERGY_NEW := "res://Audio/SFX/EnergyAttached.ogg"
## The draw / shuffle had no better replacement: the same clips at 0.9x speed (same pitch, WSOLA
## time-stretch) and louder (draw +8 dB - it was far quieter than every other SFX - shuffle +3 dB).
const SFX_DRAW_OLD := "res://Audio/SFX/card_draw_sound.ogg"
const SFX_DRAW_NEW := "res://Audio/SFX/card_draw_sound_v2.ogg"
const SFX_SHUFFLE_OLD := "res://Audio/SFX/card_shuffle_riffle.ogg"
const SFX_SHUFFLE_NEW := "res://Audio/SFX/card_shuffle_riffle_v2.ogg"

const SFX_evolve_sound = preload(SFX_EVOLVE_NEW) if USE_NEW_MATCH_SFX else preload(SFX_EVOLVE_OLD)
const SFX_trainer_sound = preload("res://Audio/SFX/trainer_sound.ogg")
const SFX_damage_sound = preload("res://Audio/SFX/damage_sound.ogg")
const SFX_status_sound = preload("res://Audio/SFX/status_sound.ogg")
const SFX_energy_sound = preload(SFX_ENERGY_NEW) if USE_NEW_MATCH_SFX else preload(SFX_ENERGY_OLD)
const SFX_card_draw_sound = preload(SFX_DRAW_NEW) if USE_NEW_MATCH_SFX else preload(SFX_DRAW_OLD)
const SFX_poison_sound = preload("res://Audio/SFX/poison_sound.ogg")
const SFX_heal_sound = preload("res://Audio/SFX/heal_sound.ogg")

const SFX_plus_select = preload("res://Audio/SFX/plus_select.ogg")
const SFX_minus_select = preload("res://Audio/SFX/minus_select.ogg")
const SFX_gamemode_select = preload("res://Audio/SFX/gamemode_select_sound.ogg")

const SFX_battle_start = preload("res://Audio/SFX/battle_start.ogg")
## The match intro's sting at DOUBLE SPEED, same pitch (time-stretched offline, 7.0s -> 3.5s),
## so it has died away by the time the decks arrive. Match_Transition.gd.
const SFX_battle_start_fast = preload("res://Audio/SFX/battle_start_fast.ogg")
## One riffle of a deck shuffle (0.17s, synthesised) - played per cut of the intro shuffle.
const SFX_card_shuffle = preload(SFX_SHUFFLE_NEW) if USE_NEW_MATCH_SFX else preload(SFX_SHUFFLE_OLD)
const SFX_battle_win = preload("res://Audio/SFX/battle_win_sound.ogg")
const SFX_battle_loss = preload("res://Audio/SFX/battle_loss_sound.ogg")

const SFX_taxi_intro = preload("res://Audio/SFX/Taxi_intro.ogg")
const SFX_taxi_out   = preload("res://Audio/SFX/Taxi_out.ogg")

# Celebration sting for the Gym Plaza coin flipper's five-heads win.
const SFX_confetti_applause = preload("res://Audio/SFX/confetti applause.ogg")

# Overworld "You received..." notice and reveal: every MapManager gift, plus the two
# notices with no gift overlay (Medal of Elders, TCG Tracker App).
const SFX_gift_received = preload("res://Audio/SFX/GiftReceived.ogg")
# End-of-match reward reveal (coin, card, costume, sleeve, pack), once per reward.
const SFX_reward_received = preload("res://Audio/SFX/RewardReceived.ogg")

# Phone call one-shots: Connecting as the phone rises into view, Disconnecting as the screen
# slides back over the caller at hang-up. Played from PhoneCall.play().
const SFX_phone_connecting    = preload("res://Audio/SFX/PhoneConnecting.ogg")
const SFX_phone_disconnecting = preload("res://Audio/SFX/PhoneDisconnecting.ogg")


# ─── BGM registry ────────────────────────────────────────────────────────────
#
# Every track in Audio/BGM/ has a constant below, so no caller spells a filename out by
# hand — rename a track on disk, fix the one line here, and every scene follows it. The
# tracks are deliberately NOT preloaded the way the SFX above are: the folder is ~84 MB,
# so play_bgm() load()s one on demand and lets go of it again in stop_bgm().
#
# The battle half doubles as the pool the opponent music picker offers (N/M in the debug
# character editor). Membership is decided by the FILENAME, not by this list —
# is_battle_bgm() just looks for "battle" in it — so a newly added battle track shows up
# in the picker on its own as long as it is named like the rest: mood word + "battle",
# then the source in brackets. A track without "battle" in its name is treated as
# location/menu music and stays out of the picker.

const BGM_DIR := "res://Audio/BGM/"
const BGM_EXT := ".ogg"
## Substring that marks a filename as selectable opponent battle music.
const BATTLE_BGM_MARKER := "battle"

# --- Battle tracks (these are what the opponent music picker offers) ---
const BGM_BOSS_BATTLE                    := BGM_DIR + "Boss_battle (PTCG2 The Final Duel GRs King Biruri)" + BGM_EXT
const BGM_CALM_BATTLE                    := BGM_DIR + "Calm Battle (PMD Surrounded Sea)" + BGM_EXT
const BGM_CALM_BATTLE_2                  := BGM_DIR + "Calm Battle 2 (PMD Crystal_Cave)" + BGM_EXT
const BGM_CALM_BATTLE_3                  := BGM_DIR + "Calm Battle 3 (PMDEoS Drenched Bluff)" + BGM_EXT
const BGM_DARK_BATTLE                    := BGM_DIR + "Dark_battle (PTCG2 Duel Vs Team GR)" + BGM_EXT
const BGM_DARK_BATTLE_2                  := BGM_DIR + "Dark_battle_2 (PTCG2 Colorless Altar A Dark Dwelling)" + BGM_EXT
const BGM_DARK_BATTLE_3                  := BGM_DIR + "Dark Battle 3 (PMDEoS In the Depths of the Pit)" + BGM_EXT
const BGM_EASY_BATTLE                    := BGM_DIR + "Easy_battle (PMD beach cave)" + BGM_EXT
const BGM_EASY_BATTLE_2                  := BGM_DIR + "Easy Battle 2 (PMDEoS Foggy Forest)" + BGM_EXT
const BGM_EASY_TENSE_BATTLE              := BGM_DIR + "Easy tense Battle (Pinball Catchem Evolution in Blue Field)" + BGM_EXT
const BGM_FUN_BATTLE_PMD                 := BGM_DIR + "Fun_battle (PMDX Makuhita Dojo)" + BGM_EXT
const BGM_FUN_BATTLE_PINBALL             := BGM_DIR + "Fun_battle (Pinball Red Field)" + BGM_EXT
const BGM_FUN_BATTLE_3                   := BGM_DIR + "Fun Battle 3 (PMDEoS Craggy Coast)" + BGM_EXT
const BGM_GYM_LEADER_CHALLENGE_BATTLE    := BGM_DIR + "Gym Leader Challenge Battle (Pokemon Card GB2 - Duel Vs Fortress Leader)" + BGM_EXT
const BGM_IMPORTANT_BATTLE               := BGM_DIR + "Important_battle (Pokmon Card GB2 - GRs Challenge Cup)" + BGM_EXT
const BGM_IMPORTANT_BATTLE_2             := BGM_DIR + "Important_battle_2 (Pokemon Card GB2 - Duel Vs Fortress Leader)" + BGM_EXT
const BGM_JOLLY_BATTLE                   := BGM_DIR + "Jolly_battle (Pinball Hi Score Screen)" + BGM_EXT
const BGM_JOLLY_BATTLE_2                 := BGM_DIR + "Jolly_battle 2 (Pinball Catchem Evolution in Red Field)" + BGM_EXT
const BGM_LAID_BACK_BATTLE               := BGM_DIR + "Laid Back Battle (Pinball Blue Field)" + BGM_EXT
const BGM_MEDIUM_BATTLE                  := BGM_DIR + "Medium Battle (PMD Mt Freeze)" + BGM_EXT
const BGM_MEDIUM_BATTLE_2                := BGM_DIR + "Medium_battle 2 (PMD Amp_Plains)" + BGM_EXT
const BGM_MEDIUM_BATTLE_3                := BGM_DIR + "Medium_Battle 3 (PMDX Thunderwave Cave)" + BGM_EXT
const BGM_MEDIUM_BATTLE_4                := BGM_DIR + "Medium Battle (PMD Mt. Bristle)" + BGM_EXT
const BGM_MEDIUM_BATTLE_5                := BGM_DIR + "Medium Battle 5 (PMDX Mt Steel)" + BGM_EXT
const BGM_MEDIUM_BATTLE_6                := BGM_DIR + "Medium Battle 6 (PMDEoS Cave and Side Path)" + BGM_EXT
const BGM_NICE_BATTLE                    := BGM_DIR + "Nice_battle (PTCG2 - GRs Grass Water Forts)" + BGM_EXT
const BGM_OUTLAW_BATTLE                  := BGM_DIR + "Outlaw_battle (PMD Outlaw)" + BGM_EXT
const BGM_SERIOUS_BATTLE                 := BGM_DIR + "Serious Battle (PTCG2 GR Rises to Power)" + BGM_EXT
const BGM_SIMPLE_BATTLE                  := BGM_DIR + "Simple_battle (PTCG2 Mr Ishiharas Villa)" + BGM_EXT
const BGM_TENSE_BATTLE                   := BGM_DIR + "Tense_battle (PTCG2 GRs Lightning Psychic Forts)" + BGM_EXT
const BGM_TENSE_BATTLE_2                 := BGM_DIR + "Tense Battle 2 (PMDX Buried Relic)" + BGM_EXT
const BGM_WORRYING_BATTLE                := BGM_DIR + "Worrying_Battle (PTCG2 GRs Fire Fighting Forts)" + BGM_EXT
const BGM_CHILLED_BATTLE                 := BGM_DIR + "chilled_battle (PTCG Masons Lab)" + BGM_EXT
const BGM_FAST_BATTLE                    := BGM_DIR + "fast_battle (PTCG Ronalds Theme)" + BGM_EXT
const BGM_HARD_BATTLE                    := BGM_DIR + "hard_battle (PTCG Club Master)" + BGM_EXT
const BGM_HARD_BATTLE_2                  := BGM_DIR + "hard_battle_2 (PTCG Grand Master Battle)" + BGM_EXT
const BGM_HARD_BATTLE_3                  := BGM_DIR + "Hard Battle 3 (PMDX Mt Blaze Peak)" + BGM_EXT
const BGM_HARD_BATTLE_4                  := BGM_DIR + "Hard Battle 4 (PMDX Magma Cavern)" + BGM_EXT
const BGM_JAZZY_BATTLE                   := BGM_DIR + "jazzy_battle (PTCG Grass Lightning Club)" + BGM_EXT
const BGM_NORMAL_BATTLE                  := BGM_DIR + "normal_battle (PTCG)" + BGM_EXT
const BGM_WEIRD_BATTLE                   := BGM_DIR + "weird_battle (PTCG Imakuma)" + BGM_EXT

# --- Maps with a track per time slot (BaseMapScene.get_time_bgm returns one of these tables) ---
const BGM_HARBOUR_MORNING                := BGM_DIR + "Celeste Harbour Morning (ORAS Dewford Town)" + BGM_EXT
const BGM_HARBOUR_AFTERNOON              := BGM_DIR + "Celeste Harbour Afternoon (ORAS Sootopolis City)" + BGM_EXT
const BGM_HARBOUR_EVENING                := BGM_DIR + "Celeste Harbour Evening and Town Hall (ORAS Verdanturf Town)" + BGM_EXT
const BGM_HARBOUR_NIGHT                  := BGM_DIR + "Celeste Harbour Night (HGSS Vermilion City)" + BGM_EXT
const BGM_FOREST_MORNING                 := BGM_DIR + "Verdant Forest Morning (HGSS National Park)" + BGM_EXT
const BGM_FOREST_AFTERNOON               := BGM_DIR + "Verdant Forest Afternoon (HGSS Viridian Forest)" + BGM_EXT
const BGM_FOREST_EVENING                 := BGM_DIR + "Verdant Forest Evening (DPPT Lake)" + BGM_EXT
const BGM_FOREST_NIGHT                   := BGM_DIR + "Verdant Forest Night (DPPT Eterna Forest)" + BGM_EXT
const BGM_FOREST_BEDTIME                 := BGM_DIR + "TreeWind" + BGM_EXT
const BGM_GYM_PLAZA_MORNING              := BGM_DIR + "Gym Plaza Morning (BW2 Opelucid City Gym)" + BGM_EXT
const BGM_GYM_PLAZA_AFTERNOON            := BGM_DIR + "Gym Plaza Afternoon (BW2 Driftveil Gym)" + BGM_EXT
const BGM_GYM_PLAZA_EVENING              := BGM_DIR + "Gym Plaza Evening (BW2 Humilau City Gym)" + BGM_EXT
const BGM_GYM_PLAZA_NIGHT                := BGM_DIR + "Gym Plaza Night (BW2 Castelia City Gym)" + BGM_EXT
const BGM_NEO_TOWN_MORNING               := BGM_DIR + "Neo Town Morning (DPPT Jubilife City)" + BGM_EXT
const BGM_NEO_TOWN_AFTERNOON             := BGM_DIR + "Neo Town Afternoon (DPPT Hearthome City)" + BGM_EXT
const BGM_NEO_TOWN_EVENING               := BGM_DIR + "Neo Town Evening (HGSS Ecruteak City)" + BGM_EXT
const BGM_NEO_TOWN_NIGHT                 := BGM_DIR + "Neo Town Night (HGSS Cianwood City)" + BGM_EXT
const BGM_NEO_FOREST_MORNING             := BGM_DIR + "Neo Forest Morning (PMDEoS Waterfall Cave)" + BGM_EXT
const BGM_NEO_FOREST_AFTERNOON           := BGM_DIR + "Neo Forest Afternoon (RGR Panula Cave)" + BGM_EXT
const BGM_NEO_FOREST_EVENING             := BGM_DIR + "Neo Forest Evening (DPPT Mt Coronet)" + BGM_EXT
const BGM_NEO_FOREST_NIGHT               := BGM_DIR + "Neo Forest Night (HGSS Ice Cave)" + BGM_EXT

## A slot a table leaves out: outdoors it is silence at Bedtime, indoors the Night track carries on.
const TIME_BGM_HARBOUR := {
	"Morning": BGM_HARBOUR_MORNING, "Afternoon": BGM_HARBOUR_AFTERNOON,
	"Evening": BGM_HARBOUR_EVENING, "Night": BGM_HARBOUR_NIGHT,
}
const TIME_BGM_FOREST := {
	"Morning": BGM_FOREST_MORNING, "Afternoon": BGM_FOREST_AFTERNOON,
	"Evening": BGM_FOREST_EVENING, "Night": BGM_FOREST_NIGHT, "Bedtime": BGM_FOREST_BEDTIME,
}
## Gym Challenge Reception, which has no Bedtime entry so its Night track carries on then.
const TIME_BGM_GYM_RECEPTION := {
	"Morning": BGM_GYM_PLAZA_MORNING, "Afternoon": BGM_GYM_PLAZA_AFTERNOON,
	"Evening": BGM_GYM_PLAZA_EVENING, "Night": BGM_GYM_PLAZA_NIGHT,
}
## Gym Plaza: the same tracks, so the music runs on through the door, with the forest's wind at
## Bedtime to match Verdant Forest.
const TIME_BGM_GYM_PLAZA := {
	"Morning": BGM_GYM_PLAZA_MORNING, "Afternoon": BGM_GYM_PLAZA_AFTERNOON,
	"Evening": BGM_GYM_PLAZA_EVENING, "Night": BGM_GYM_PLAZA_NIGHT, "Bedtime": BGM_FOREST_BEDTIME,
}
## Maps not built yet: return these from get_time_bgm() when they arrive.
const TIME_BGM_NEO_TOWN := {
	"Morning": BGM_NEO_TOWN_MORNING, "Afternoon": BGM_NEO_TOWN_AFTERNOON,
	"Evening": BGM_NEO_TOWN_EVENING, "Night": BGM_NEO_TOWN_NIGHT,
}
const TIME_BGM_NEO_FOREST := {
	"Morning": BGM_NEO_FOREST_MORNING, "Afternoon": BGM_NEO_FOREST_AFTERNOON,
	"Evening": BGM_NEO_FOREST_EVENING, "Night": BGM_NEO_FOREST_NIGHT,
}

# --- Ambience (looped beds, played by their own systems) ---
const BGM_OCEAN_CLOSE                    := BGM_DIR + "OceanClose" + BGM_EXT
const BGM_OCEAN_FAR                      := BGM_DIR + "OceanFar" + BGM_EXT
const BGM_SEA_SOUNDS                     := BGM_DIR + "SEA SOUNDS_bgm" + BGM_EXT

# --- Interior, menu and cutscene tracks ---
## Until the 7th Gym Leader (Blaine) falls, then the FINAL one: only Giovanni is left.
const BGM_GYM_CHALLENGE_HALL             := BGM_DIR + "Gym Challenge Hall (BW2 Nimbasa City Gym Runway)" + BGM_EXT
const BGM_GYM_CHALLENGE_HALL_FINAL       := BGM_DIR + "Gym Challenge Hall Final (BW2 Nimbasa City Gym Stage)" + BGM_EXT
const BGM_FISH_SHOP                      := BGM_DIR + "FISH (RGR Summertown)" + BGM_EXT
const BGM_WINDMILL                       := BGM_DIR + "Windmill (HGSS Ruins of Alph)" + BGM_EXT
const BGM_CAFE                           := BGM_DIR + "Cafe (ORAS Oceanic Museum)" + BGM_EXT
const BGM_CARD_MART                      := BGM_DIR + "Card Mart (ORAS Poke Mart)" + BGM_EXT
const BGM_HOTEL                          := BGM_DIR + "Hotel (ORAS Lilycove City)" + BGM_EXT
## The same file as the harbour's Evening track, so walking in at Evening does not restart it.
const BGM_TOWN_HALL                      := BGM_HARBOUR_EVENING
const BGM_PLAYER_HOME_DAY                := BGM_DIR + "Player Home Day (PMDX File Select)" + BGM_EXT
const BGM_PLAYER_HOME_NIGHT              := BGM_DIR + "Player Home Night (PMDX Personality Test)" + BGM_EXT
## Only the Train Station plays this now.
const BGM_SHOP_1                         := BGM_DIR + "Shop1 (PMD Spindas Cafe)" + BGM_EXT
## The Rocket Mart and every shop screen.
const BGM_SHOP_2                         := BGM_DIR + "Rocket Mart and Shops (PMDX Kecleon Shop)" + BGM_EXT
## Won a match: after the win jingle, until the rewards are cleared (Match_End_Outro).
const BGM_VICTORY                        := BGM_DIR + "Victory (PMDX Happiness)" + BGM_EXT
## The Gym Plaza five-coin flipper, from paying up to walking away (MapManager).
const BGM_COIN_FLIP_GAME                 := BGM_DIR + "Coin Flip Game (HGSS Mt Moon)" + BGM_EXT
## The escape menu and its sub-menus: pick with menu_bgm(), never name this directly.
const BGM_COIN_MODE                      := BGM_DIR + "coin_mode (PTCG Water Club)" + BGM_EXT
# Hard Mode's draft: Olly's twelve packs opening only (the deck build after it uses the menu track).
const BGM_DRAFT_TIME                     := BGM_DIR + "DraftTime (RSE Trick House)" + BGM_EXT
# The PTCG main-menu theme. The FILE was renamed gym_plaza -> starting_menu when the
# track moved off the Gym Plaza (ISSUE #211) and onto the boot splash and the
# first-launch setup screen, but this constant kept pointing at the old name, so
# every load() of it returned null and the setup screen booted in silence.
const BGM_STARTING_MENU                  := BGM_DIR + "starting_menu (PTCG Main Menu)" + BGM_EXT
const BGM_MAIN_MENU                      := BGM_DIR + "main_menu_music (PTCG Menu Theme)" + BGM_EXT

## The menu family's track, at every time of day.
func menu_bgm() -> String:
	return BGM_COIN_MODE


# --- BGM player (persists until stopped or replaced) ---
var bgm_player: AudioStreamPlayer = null
var _current_bgm_path: String = ""

# --- SFX: play a preloaded AudioStream as a one-shot ---
# `pitch` scales pitch AND tempo together, which is what a "random pitch/tempo wobble"
# means for a one-shot -- the fishing fight rolls one per splash so the same two files
# never sound like a loop.
func play_sfx(sound: AudioStream, pitch: float = 1.0) -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = sound
	player.bus = SFX_BUS
	player.pitch_scale = maxf(0.01, pitch)
	player.play()
	player.finished.connect(player.queue_free)

# --- SFX: load from a res:// path and play as a one-shot ---
func play_sfx_from_path(path: String, pitch: float = 1.0) -> void:
	var stream = load(path)
	if stream:
		play_sfx(stream, pitch)
	else:
		print("SoundManager: Could not load SFX at: ", path)

# ============================================================
# SPEECH BLIP
# ============================================================
# The dialogue tick that plays as letters land in a character message box, one
# short sample retriggered per few letters and pitched to the speaker. See
# Speech_Voice.gd for where a pitch comes from and Dynamic_Message_Box.gd for
# when one is asked for.
#
# ONE player, reused and restarted, rather than play_sfx()'s throwaway node: a
# blip fires several times a second for the length of every conversation in the
# game, and spawning an AudioStreamPlayer per letter would churn hundreds of
# nodes a minute. Restarting the same player also self-limits the sound — a blip
# can never stack on top of itself into a drone, which is exactly the behaviour
# the Animal Crossing style tick wants.
const SPEECH_BLIP_PATH := "res://Audio/SFX/Speech.ogg"

var _speech_player: AudioStreamPlayer = null

# Plays one dialogue blip at `pitch` (1.0 is the sample untouched). Lives on the
# SFX bus, so the Options SFX slider covers it like every other sound.
func play_speech_blip(pitch: float = 1.0) -> void:
	# is_instance_valid as well as null: the match outro frees every AudioStreamPlayer
	# child of this node to stop the win/loss jingle, and this player is one of them.
	# A freed Object is not null, so checking only for null would call play() on it.
	if _speech_player == null or not is_instance_valid(_speech_player):
		var stream = load(SPEECH_BLIP_PATH)
		if stream == null:
			print("SoundManager: Could not load speech blip at: ", SPEECH_BLIP_PATH)
			return
		# An .ogg that was imported with looping on would turn the first blip into a
		# continuous tone, since nothing ever stops it. Say so rather than rely on
		# the import setting.
		if "loop" in stream:
			stream = stream.duplicate()
			stream.loop = false
		_speech_player = AudioStreamPlayer.new()
		_speech_player.stream = stream
		_speech_player.bus = SFX_BUS
		add_child(_speech_player)
	_speech_player.pitch_scale = pitch
	# play() from the top restarts a blip that is still ringing, which is what
	# keeps a fast talker crisp instead of muddy.
	_speech_player.play()


# ============================================================
# POKÉMON CRIES
# ============================================================
# One player on its own bus. A cry asked for while another is still playing is
# DROPPED, not queued: a screen of Wingull should sound like birds now and then, not
# a backlog that keeps crying after they have flown off.
const CRY_DIR := "res://Audio/Cries/"

var _cry_player: AudioStreamPlayer = null

# How long this species' cry runs for, in seconds, or 0 when it has not got one. For
# lining something up with the end of a cry -- the fishing minigame's catch jingle waits
# on it.
func cry_length(species: String) -> float:
	var path := CRY_DIR + species + ".ogg"
	if not ResourceLoader.exists(path):
		return 0.0
	var stream = load(path)
	return stream.get_length() if stream != null else 0.0


# TWEAKABLE -- how loud a cry plays with the Cries slider at 100%. The slider scales down from here.
const CRY_LEVEL := 0.375

# `species` is the sprite basename, e.g. "278_Wingull" -> res://Audio/Cries/278_Wingull.ogg.
# Returns true if the cry started.
func play_cry(species: String) -> bool:
	# The main menu pauses the overworld: nothing out there should still be calling out
	# from behind the menu. The Pokemon themselves are frozen too, so this is the safety
	# net for any other caller (a cry fired from an interaction, the fishing catch).
	if MapManager.overworld_paused:
		return false
	# is_instance_valid as well as null: the match outro frees every AudioStreamPlayer child.
	if _cry_player != null and is_instance_valid(_cry_player) and _cry_player.playing:
		return false
	var path := CRY_DIR + species + ".ogg"
	if not ResourceLoader.exists(path):
		return false
	var stream = load(path)
	if stream == null:
		return false
	if "loop" in stream:
		stream = stream.duplicate()
		stream.loop = false
	_ensure_buses()
	if _cry_player == null or not is_instance_valid(_cry_player):
		_cry_player = AudioStreamPlayer.new()
		_cry_player.bus = CRIES_BUS
		_cry_player.volume_db = linear_to_db(CRY_LEVEL)
		add_child(_cry_player)
	_cry_player.stream = stream
	_cry_player.play()
	return true


# Cuts a cry that is still sounding. Used when the overworld pauses under the main menu,
# so a cry that started a frame before the menu opened does not carry on over it.
func stop_cry() -> void:
	if _cry_player != null and is_instance_valid(_cry_player):
		_cry_player.stop()


# --- BGM: play background music from a res:// path ---
# If loop is true the track will repeat. Calling this while BGM is
# already playing will stop the old track and start the new one.
## ISSUE #467 / #470: true while Olly's intro walks the player through the menus (deck builder, coin
## case). The overworld track keeps playing: the menus' own track is not started and nothing stops the
## world's. Set and cleared by OllyIntroCutscene.
var hold_world_bgm: bool = false

func play_bgm(path: String, loop: bool = true) -> void:
	if hold_world_bgm and path == BGM_COIN_MODE:
		print("ISSUE #467 FIX ACTIVE: menu track skipped, the overworld BGM plays on")
		return
	# A new track always wins over a fade_out_bgm() still on its way down: one player, no overlap.
	if _stop_when_faded:
		_cancel_fade_out()
	if _current_bgm_path == path and bgm_player != null:
		return
	stop_bgm()

	var stream = load(path)
	if stream == null:
		print("SoundManager: Could not load BGM at: ", path)
		return
	
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	bgm_player.stream = stream
	bgm_player.bus = MUSIC_BUS
	
	if loop:
		bgm_player.stream.loop = true
	
	_current_bgm_path = path
	_apply_bgm_duck()
	bgm_player.play()


## ISSUE #446: the escape menu and every sub-menu opened from it share ONE track on the
## global player, so the music runs on unbroken from menu to sub-menu and back (play_bgm
## is a no-op when the same track is already on). Returns false when the screen was NOT
## opened from the escape menu overlay -- the caller then plays its own local player as
## before. The map's _close_menu_overlay() brings the map music back.
func play_menu_family_bgm() -> bool:
	var host: Node = GameState.menu_overlay_host
	if host == null or not is_instance_valid(host):
		return false
	print("ISSUE #446 FIX ACTIVE: shared menu BGM (", _current_bgm_path == menu_bgm(), " already on)")
	play_bgm(menu_bgm())
	return true


## Fades the current track out, starts `path`, and fades that in. Awaitable; returns once
## the new track is at full volume. TWEAKABLE: the two halves' lengths.
func crossfade_bgm(path: String, out_seconds: float = 0.6, in_seconds: float = 0.8) -> void:
	if _current_bgm_path == path and bgm_player != null:
		return
	fade_bgm(0.0, out_seconds)
	await get_tree().create_timer(out_seconds).timeout
	play_bgm(path, true)
	fade_bgm(1.0, in_seconds)
	await get_tree().create_timer(in_seconds).timeout


# --- BGM: play by bare track name ---
# The form opponent JSON stores in its "music" field, and what the pickers hand back:
# a filename with no folder and no extension. An empty name is a silent no-op, so an
# opponent that has never had music chosen simply keeps whatever is already playing.
func play_bgm_named(track_name: String, loop: bool = true) -> void:
	if track_name.strip_edges().is_empty():
		return
	play_bgm(bgm_path(track_name), loop)

# --- Bare track name -> full res:// path ---
func bgm_path(track_name: String) -> String:
	return BGM_DIR + track_name + BGM_EXT

# --- Is this track selectable as opponent battle music? ---
# Filename-driven on purpose: see the note above the registry.
static func is_battle_bgm(track_name: String) -> bool:
	return track_name.to_lower().contains(BATTLE_BGM_MARKER)

# --- Every track in Audio/BGM/, bare names, natural sort ---
# Reads the folder rather than the constants above so a track dropped in without a
# constant is still reachable. In an export the sources are replaced by .import/.remap
# stubs, hence the trimming.
func list_bgm() -> Array[String]:
	var names: Dictionary = {}
	var dir := DirAccess.open(BGM_DIR)
	if dir == null:
		push_warning("SoundManager: could not open " + BGM_DIR)
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			if clean.ends_with(BGM_EXT):
				names[clean.trim_suffix(BGM_EXT)] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var out: Array[String] = []
	for n in names.keys():
		out.append(str(n))
	out.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	return out

# --- Just the battle tracks, for the opponent music picker ---
func list_battle_bgm() -> Array[String]:
	var out: Array[String] = []
	for n in list_bgm():
		if is_battle_bgm(n):
			out.append(n)
	return out

# ─── BGM ducking ─────────────────────────────────────────────────────────────
#
# A multiplier on the CURRENT track only, applied to bgm_player.volume_db and NOT to the
# Music bus -- the bus carries the player's own music slider (GameState.set_music_volume)
# and must never be stomped by a gameplay effect.
#
# fade_bgm(0.0, 2.0) takes two seconds to silence, fade_bgm(1.0, 1.0) one second to come
# back. The level is remembered across a play_bgm(), so a track that starts while the
# music is ducked starts ducked; anything that ducks must fade back when it is done.

const BGM_SILENT_DB := -60.0

var _bgm_duck: float = 1.0
var _bgm_duck_target: float = 1.0
var _bgm_duck_rate: float = 0.0
var _bgm_duck_delay: float = 0.0
## True while fade_out_bgm() is taking the track down to be stopped.
var _stop_when_faded: bool = false


## Ramp the current track to `target_linear` (0 = silent, 1 = full) over `seconds`, after
## waiting `delay` first. The delay is what keeps a chain-fisher's music down: each cast
## starts a new fade to 0 with no delay, which cancels the pending fade back up.
func fade_bgm(target_linear: float, seconds: float, delay: float = 0.0) -> void:
	_bgm_duck_target = clampf(target_linear, 0.0, 1.0)
	_bgm_duck_delay = maxf(0.0, delay)
	if seconds <= 0.0 and _bgm_duck_delay <= 0.0:
		_bgm_duck = _bgm_duck_target
		_bgm_duck_rate = 0.0
		_apply_bgm_duck()
		return
	_bgm_duck_rate = 1.0 / maxf(0.01, seconds)


## Fades the current track away and stops it, leaving the level back at full for whatever
## plays next. play_bgm() during the fade simply cuts over (see the top of play_bgm).
func fade_out_bgm(seconds: float) -> void:
	if bgm_player == null:
		return
	_stop_when_faded = true
	fade_bgm(0.0, seconds)


func _cancel_fade_out() -> void:
	_stop_when_faded = false
	_bgm_duck = 1.0
	_bgm_duck_target = 1.0
	_bgm_duck_rate = 0.0
	_bgm_duck_delay = 0.0


func _process(delta: float) -> void:
	if is_equal_approx(_bgm_duck, _bgm_duck_target):
		return
	if _bgm_duck_delay > 0.0:
		_bgm_duck_delay -= delta
		return
	_bgm_duck = move_toward(_bgm_duck, _bgm_duck_target, _bgm_duck_rate * delta)
	_apply_bgm_duck()
	if _stop_when_faded and _bgm_duck <= 0.001:
		stop_bgm()


func _apply_bgm_duck() -> void:
	if bgm_player == null or not is_instance_valid(bgm_player):
		return
	bgm_player.volume_db = BGM_SILENT_DB if _bgm_duck <= 0.001 else linear_to_db(_bgm_duck)


# --- BGM: stop and free the current BGM player ---
func stop_bgm() -> void:
	if hold_world_bgm:
		return   # ISSUE #467: the walkthrough keeps the world's music
	if _stop_when_faded:
		_cancel_fade_out()
	if bgm_player != null:
		bgm_player.stop()
		bgm_player.queue_free()
		bgm_player = null
	_current_bgm_path = ""


# ─── Debug music audition ────────────────────────────────────────────────────
#
# A second, independent BGM player on AUDITION_BUS, used by the PLAY button in the debug
# character editor. It exists purely so the preview ignores the music slider: with the
# overworld muted while tracks are being assigned to opponents, the preview still plays.
#
# It does not touch bgm_player or _current_bgm_path, so the caller decides whether the map
# track keeps running underneath (the editor stops it, so nothing overlaps).

var audition_player: AudioStreamPlayer = null

# --- Audition: play a track by bare name, always looping ---
# Restarts from the top even if the same track is already auditioning, which is what the
# PLAY button should do. An empty name is a silent no-op.
func play_audition_bgm(track_name: String) -> void:
	stop_audition_bgm()
	if track_name.strip_edges().is_empty():
		return
	var stream = load(bgm_path(track_name))
	if stream == null:
		print("SoundManager: Could not load BGM at: ", bgm_path(track_name))
		return
	_ensure_buses()
	audition_player = AudioStreamPlayer.new()
	add_child(audition_player)
	audition_player.stream = stream
	audition_player.bus = AUDITION_BUS
	audition_player.stream.loop = true
	audition_player.play()

# --- Audition: stop and free the preview player ---
func stop_audition_bgm() -> void:
	if audition_player != null:
		audition_player.stop()
		audition_player.queue_free()
		audition_player = null
