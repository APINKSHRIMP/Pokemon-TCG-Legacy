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
const SFX_knockout_sound = preload("res://Audio/SFX/knockout_sound.ogg")
const SFX_select_button = preload("res://Audio/SFX/select_button.ogg")
const SFX_evolve_sound = preload("res://Audio/SFX/evolve_sound.ogg")
const SFX_trainer_sound = preload("res://Audio/SFX/trainer_sound.ogg")
const SFX_damage_sound = preload("res://Audio/SFX/damage_sound.ogg")
const SFX_status_sound = preload("res://Audio/SFX/status_sound.ogg")
const SFX_energy_sound = preload("res://Audio/SFX/energy_sound.ogg")
const SFX_card_draw_sound = preload("res://Audio/SFX/card_draw_sound.ogg")
const SFX_poison_sound = preload("res://Audio/SFX/poison_sound.ogg")
const SFX_heal_sound = preload("res://Audio/SFX/heal_sound.ogg")

const SFX_plus_select = preload("res://Audio/SFX/plus_select.ogg")
const SFX_minus_select = preload("res://Audio/SFX/minus_select.ogg")
const SFX_gamemode_select = preload("res://Audio/SFX/gamemode_select_sound.ogg")

const SFX_battle_start = preload("res://Audio/SFX/battle_start.ogg")
const SFX_battle_win = preload("res://Audio/SFX/battle_win_sound.ogg")
const SFX_battle_loss = preload("res://Audio/SFX/battle_loss_sound.ogg")

const SFX_taxi_intro = preload("res://Audio/SFX/Taxi_intro.ogg")
const SFX_taxi_out   = preload("res://Audio/SFX/Taxi_out.ogg")

# Celebration sting for the Gym Plaza coin flipper's five-heads win.
const SFX_confetti_applause = preload("res://Audio/SFX/confetti applause.ogg")

# The "you got something" sting. Plays under the big centred announcement for a
# one-off story item -- the starter box upstairs, the starter set from the mart.
# Pack openings and gift NPCs have their own reveal sequences and do not use it.
const SFX_item_acquired = preload("res://Audio/SFX/ItemAcquired.ogg")

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
const BGM_DARK_BATTLE                    := BGM_DIR + "Dark_battle (PTCG2 Duel Vs Team GR)" + BGM_EXT
const BGM_DARK_BATTLE_2                  := BGM_DIR + "Dark_battle_2 (PTCG2 Colorless Altar A Dark Dwelling)" + BGM_EXT
const BGM_EASY_BATTLE                    := BGM_DIR + "Easy_battle (PMD beach cave)" + BGM_EXT
const BGM_EASY_TENSE_BATTLE              := BGM_DIR + "Easy tense Battle (Pinball Catchem Evolution in Blue Field)" + BGM_EXT
const BGM_FUN_BATTLE_PMD                 := BGM_DIR + "Fun_battle (PMD Makuhita_Dojo)" + BGM_EXT
const BGM_FUN_BATTLE_PINBALL             := BGM_DIR + "Fun_battle (Pinball Red Field)" + BGM_EXT
const BGM_GYM_LEADER_CHALLENGE_BATTLE    := BGM_DIR + "Gym Leader Challenge Battle (Pokemon Card GB2 - Duel Vs Fortress Leader)" + BGM_EXT
const BGM_IMPORTANT_BATTLE               := BGM_DIR + "Important_battle (Pokmon Card GB2 - GRs Challenge Cup)" + BGM_EXT
const BGM_IMPORTANT_BATTLE_2             := BGM_DIR + "Important_battle_2 (Pokemon Card GB2 - Duel Vs Fortress Leader)" + BGM_EXT
const BGM_JOLLY_BATTLE                   := BGM_DIR + "Jolly_battle (Pinball Hi Score Screen)" + BGM_EXT
const BGM_JOLLY_BATTLE_2                 := BGM_DIR + "Jolly_battle 2 (Pinball Catchem Evolution in Red Field)" + BGM_EXT
const BGM_LAID_BACK_BATTLE               := BGM_DIR + "Laid Back Battle (Pinball Blue Field)" + BGM_EXT
const BGM_MEDIUM_BATTLE                  := BGM_DIR + "Medium Battle (PMD Mt Freeze)" + BGM_EXT
const BGM_MEDIUM_BATTLE_2                := BGM_DIR + "Medium_battle 2 (PMD Amp_Plains)" + BGM_EXT
const BGM_MEDIUM_BATTLE_3                := BGM_DIR + "Medium_Battle 3 (PMD Thunderwave_Cave)" + BGM_EXT
const BGM_NICE_BATTLE                    := BGM_DIR + "Nice_battle (PTCG2 - GRs Grass Water Forts)" + BGM_EXT
const BGM_OUTLAW_BATTLE                  := BGM_DIR + "Outlaw_battle (PMD Outlaw)" + BGM_EXT
const BGM_SERIOUS_BATTLE                 := BGM_DIR + "Serious Battle (PTCG2 GR Rises to Power)" + BGM_EXT
const BGM_SIMPLE_BATTLE                  := BGM_DIR + "Simple_battle (PTCG2 Mr Ishiharas Villa)" + BGM_EXT
const BGM_TENSE_BATTLE                   := BGM_DIR + "Tense_battle (PTCG2 GRs Lightning Psychic Forts)" + BGM_EXT
const BGM_WORRYING_BATTLE                := BGM_DIR + "Worrying_Battle (PTCG2 GRs Fire Fighting Forts)" + BGM_EXT
const BGM_CHILLED_BATTLE                 := BGM_DIR + "chilled_battle (PTCG Masons Lab)" + BGM_EXT
const BGM_FAST_BATTLE                    := BGM_DIR + "fast_battle (PTCG Ronalds Theme)" + BGM_EXT
const BGM_HARD_BATTLE                    := BGM_DIR + "hard_battle (PTCG Club Master)" + BGM_EXT
const BGM_HARD_BATTLE_2                  := BGM_DIR + "hard_battle_2 (PTCG Grand Master Battle)" + BGM_EXT
const BGM_JAZZY_BATTLE                   := BGM_DIR + "jazzy_battle (PTCG Grass Lightning Club)" + BGM_EXT
const BGM_NORMAL_BATTLE                  := BGM_DIR + "normal_battle (PTCG)" + BGM_EXT
const BGM_WEIRD_BATTLE                   := BGM_DIR + "weird_battle (PTCG Imakuma)" + BGM_EXT

# --- Location, menu and cutscene tracks ---
const BGM_CELESTE_HARBOUR                := BGM_DIR + "Celeste_Harbour_BGM (HGSS National Park)" + BGM_EXT
const BGM_GYM_CHALLENGE_HALL             := BGM_DIR + "Gym Leader Challenge Hall (Pokmon Card GB2 - GRs Challenge Cup)" + BGM_EXT
const BGM_MYSTERY                        := BGM_DIR + "Mystery (PMD Personality_Test)" + BGM_EXT
const BGM_MYSTERY_2                      := BGM_DIR + "Mystery 2 (PMD Welcome_to_the_World_of_Pokmon)" + BGM_EXT
const BGM_PLAYER_HOME                    := BGM_DIR + "Player Home (003 File Select PMD Blue Rescue Team OST)" + BGM_EXT
const BGM_PLAYER_HOME_ALT                := BGM_DIR + "Player Home (PMD File Select)" + BGM_EXT
const BGM_SEA_SOUNDS                     := BGM_DIR + "SEA SOUNDS_bgm" + BGM_EXT
const BGM_SHOP_1                         := BGM_DIR + "Shop1 (PMD Spindas Cafe)" + BGM_EXT
const BGM_SHOP_2                         := BGM_DIR + "Shop2 (PMD Kecleon Shop)" + BGM_EXT
const BGM_SHOP_3                         := BGM_DIR + "Shop3 (Undertale Sans Theme)" + BGM_EXT
const BGM_VERDANT_FOREST                 := BGM_DIR + "Verdant Forest (DPPT Eterna Forest)" + BGM_EXT
const BGM_BEACH                          := BGM_DIR + "beach_bgm (PMD Beach at dusk)" + BGM_EXT
const BGM_COIN_MODE                      := BGM_DIR + "coin_mode (PTCG Water Club)" + BGM_EXT
# The PTCG main-menu theme. The FILE was renamed gym_plaza -> starting_menu when the
# track moved off the Gym Plaza (ISSUE #210) and onto the boot splash and the
# first-launch setup screen, but this constant kept pointing at the old name, so
# every load() of it returned null and the setup screen booted in silence.
const BGM_STARTING_MENU                  := BGM_DIR + "starting_menu (PTCG Main Menu)" + BGM_EXT
const BGM_MAIN_MENU                      := BGM_DIR + "main_menu_music (PTCG Menu Theme)" + BGM_EXT
const BGM_WORLD_MAP                      := BGM_DIR + "world_map_music (PMD Square)" + BGM_EXT

# --- BGM player (persists until stopped or replaced) ---
var bgm_player: AudioStreamPlayer = null
var _current_bgm_path: String = ""

# --- SFX: play a preloaded AudioStream as a one-shot ---
func play_sfx(sound: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = sound
	player.bus = SFX_BUS
	player.play()
	player.finished.connect(player.queue_free)

# --- SFX: load from a res:// path and play as a one-shot ---
func play_sfx_from_path(path: String) -> void:
	var stream = load(path)
	if stream:
		play_sfx(stream)
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

# `species` is the sprite basename, e.g. "278_Wingull" -> res://Audio/Cries/278_Wingull.ogg.
# Returns true if the cry started.
func play_cry(species: String) -> bool:
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
		add_child(_cry_player)
	_cry_player.stream = stream
	_cry_player.play()
	return true


# --- BGM: play background music from a res:// path ---
# If loop is true the track will repeat. Calling this while BGM is
# already playing will stop the old track and start the new one.
func play_bgm(path: String, loop: bool = true) -> void:
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
	bgm_player.play()


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

# --- BGM: stop and free the current BGM player ---
func stop_bgm() -> void:
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
