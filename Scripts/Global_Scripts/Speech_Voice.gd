class_name SpeechVoice

# ============================================================
# SPEECH VOICE — static lookup
# ============================================================
# The dialogue blip's pitch and cadence for one speaker, the way Animal Crossing
# and Mystery Dungeon do it: one short sample retriggered as the letters land,
# pitched and paced to suggest the person talking.
#
# -- WHY THE SPRITE IS THE KEY --------------------------------
# A voice belongs to the ARCHETYPE, not to the placement. "Biker1".."Biker4" in
# All_NPC_Constant_Data.json are four entries pointing at one sprite, and they
# must not be four different voices by accident. The overworld sprite name is
# also the only identifier all three speaking paths share — overworld NPCs and
# opponents (MapManager), phone callers (PhoneCall) and the post-match line
# (Match_End_Outro) every one of them already passes a sprite into the name
# pill — so keying on it means no schema change to the 237 NPC entries, the
# opponent files or the N/M character editor, and a newly placed character that
# reuses an existing sprite is voiced the moment it is placed.
#
# -- THE TABLE ------------------------------------------------
# Scripts do not own the numbers; NPC_and_Opponent_Data/speech_voices.json does,
# so the voices can be tuned by hand during a play test without touching code.
# Each row is one sprite BASE name:
#
#     "Biker": { "pitch": 0.74, "rate": 0.88 }
#
#   pitch  playback pitch. 1.0 is the sample untouched. Below 1 is deeper (big,
#          heavy or mean), above 1 is higher (young, small, female).
#   rate   blips per letter, relative. 1.0 is the default cadence; 1.3 is a fast
#          chatty kid, 0.7 is a slow, ponderous elder. It does NOT change how
#          fast the text itself types — that is the player's Animation-speed
#          option — only how often the sample retriggers as it does.
#
# -- RESOLVING A SPRITE ---------------------------------------
# The sprite folder holds 1,249 files but only ~318 distinct archetypes: the
# rest are numbered alternates (Beauty5) and second walk frames (NPCMan_2). Both
# suffixes are stripped on the way in, so one row covers every variant of a
# character and only genuinely new archetypes need a new row. Anything still
# unmatched falls back on its _F/_M suffix, then on the neutral default, so an
# unlisted sprite is never silent and never wrong-sounding by much.
# ============================================================

const VOICE_DATA_PATH := "res://NPC_and_Opponent_Data/speech_voices.json"

# The voice a sprite that matches nothing at all gets. Overridden by the
# "defaults" block in the JSON; these are the last resort if the file is missing.
const FALLBACK_NEUTRAL := { "pitch": 1.0, "rate": 1.0 }

# Guard rails on hand-edited data. A pitch of 0 would stop the sample dead and a
# rate of 0 would divide by zero in the cadence, so both are clamped on load
# rather than trusted.
const PITCH_MIN := 0.4
const PITCH_MAX := 2.2
const RATE_MIN  := 0.3
const RATE_MAX  := 2.5

# Parsed once per run. The table is small and every message box asks for a voice,
# so it is not worth re-reading the file per conversation.
static var _voices: Dictionary = {}
static var _defaults: Dictionary = {}
# Name PREFIX -> the voices key to use. Longest prefix wins. See _ensure_loaded().
static var _aliases: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_defaults = { "neutral": FALLBACK_NEUTRAL.duplicate() }
	_aliases = {}

	if not FileAccess.file_exists(VOICE_DATA_PATH):
		push_warning("SpeechVoice: no voice table at %s — every speaker gets the neutral voice"
			% VOICE_DATA_PATH)
		return
	var text := FileAccess.get_file_as_string(VOICE_DATA_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SpeechVoice: %s is not valid JSON — every speaker gets the neutral voice"
			% VOICE_DATA_PATH)
		return

	for key in parsed.get("defaults", {}):
		_defaults[key] = _sanitise(parsed["defaults"][key])
	for key in parsed.get("voices", {}):
		_voices[String(key)] = _sanitise(parsed["voices"][key])
	# Aliases are resolved to a real row here, once, so a lookup never chases a chain
	# and a typo is reported at load rather than silently going neutral for ever.
	for key in parsed.get("aliases", {}):
		var target := String(parsed["aliases"][key])
		if _voices.has(target):
			_aliases[String(key)] = target
		else:
			push_warning("SpeechVoice: alias '%s' points at unknown voice '%s'" % [key, target])


# One row, clamped into range with anything missing filled from neutral.
static func _sanitise(row) -> Dictionary:
	if typeof(row) != TYPE_DICTIONARY:
		return FALLBACK_NEUTRAL.duplicate()
	return {
		"pitch": clampf(float(row.get("pitch", 1.0)), PITCH_MIN, PITCH_MAX),
		"rate":  clampf(float(row.get("rate",  1.0)), RATE_MIN,  RATE_MAX),
	}


## Strips the two variant suffixes the sprite folder uses, so every alternate of a
## character resolves to the one row that names it. "_2" (a second walk frame or a
## costume swap) comes off first, then trailing digits ("Beauty5" -> "Beauty",
## "AceTrainer_F3" -> "AceTrainer_F"). A name that is ONLY digits after the prefix
## — "NPC27" — keeps them: those are distinct characters, not variants, and they
## have their own rows.
static func _base_name(sprite: String) -> String:
	var name := sprite
	var underscore := name.rfind("_")
	if underscore > 0 and underscore < name.length() - 1:
		var tail := name.substr(underscore + 1)
		if tail.is_valid_int() and tail.length() <= 2:
			name = name.substr(0, underscore)
	# NPC01..NPC75 and the numbered Gym sprites are characters in their own right;
	# only strip digits when what is left is still a real name.
	var stripped := name
	while stripped.length() > 0 and stripped[stripped.length() - 1].is_valid_int():
		stripped = stripped.substr(0, stripped.length() - 1)
	if stripped.length() >= 3 and _voices.has(stripped):
		return stripped
	return name


## The voice for an overworld sprite name, as { "pitch": float, "rate": float }.
## Never fails: an unknown sprite gets the _F/_M default for its suffix, or neutral.
static func for_sprite(sprite: String) -> Dictionary:
	_ensure_loaded()
	if sprite == "":
		return _default_row("neutral")

	if _voices.has(sprite):
		return _voices[sprite]
	var base := _base_name(sprite)
	if _voices.has(base):
		return _voices[base]

	# NOT every sprite a speaker carries is an overworld sprite. A phone call names a
	# TALKING-HEAD costume ("Rival_Ellie_Call_Dress_Clutch_Happy_2") and a handful of
	# in-battle sprites are named differently from their overworld twin, so those names
	# resolve through a prefix alias instead - one alias row covers every costume,
	# expression and mouth frame a character will ever have.
	var alias := _alias_for(sprite)
	if alias != "":
		return _voices[alias]

	# Nothing named this character. The suffix is the last real information in the
	# name, and it is the one thing worth guessing from.
	if base.ends_with("_F") or base.ends_with("Girl") or base.ends_with("Lady"):
		return _default_row("F")
	if base.ends_with("_M") or base.ends_with("Boy") or base.ends_with("Man"):
		return _default_row("M")
	return _default_row("neutral")


## The longest alias prefix this name starts with, or "" for none. Longest wins so a
## specific costume can override the character it belongs to.
static func _alias_for(sprite: String) -> String:
	var best := ""
	for prefix in _aliases:
		if sprite.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	return "" if best == "" else String(_aliases[best])


static func _default_row(key: String) -> Dictionary:
	if _defaults.has(key):
		return _defaults[key]
	return FALLBACK_NEUTRAL.duplicate()


## Drops the parsed table so the next lookup re-reads the file. For tuning the
## numbers with the game running; nothing in normal play needs it.
static func reload() -> void:
	_loaded = false
	_voices = {}
	_defaults = {}
	_aliases = {}
