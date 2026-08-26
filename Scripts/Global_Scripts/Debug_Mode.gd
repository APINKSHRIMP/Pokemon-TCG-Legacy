class_name DebugMode
extends RefCounted

# ============================================================
# DEBUG MODE
# ============================================================
# The single switch that gates every developer-only feature in the game:
#
#   * MapManager._unhandled_input()          — overworld cheat keys
#                                              (C, P, O, T, 1-0/-/=, H/J/K/L, [)
#   * PlacementTool (opened with F)          — the NPC/opponent placement editor,
#                                              and the N/M character creation and
#                                              editing form inside it. Constructed
#                                              only from MapManager, behind the gate
#                                              above; the tool and its form contain
#                                              no check of their own.
#   * Main_Match_Core_Gameplay_Script._input() — in-match cheat keys
#                                              (9, 0, D, S, E, H, B)
#   * Deck_Build_And_Card_View_Script        — unlimited-deck building
#                                              (no 60-card / 4-copy / ownership rules)
#   * Player_Object_Script                   — 10x run speed instead of 2x
#
# Nothing else in the project decides for itself whether it is "testing" — new
# debug features go behind DebugMode.is_enabled() so there is exactly one place
# to look, and exactly one place to flip.
#
# ── HOW TO TURN IT ON AND OFF ───────────────────────────────────────────────
#
# 1) AUTO (the default, and what you want almost always)
#    Debug mode follows OS.is_debug_build():
#      - Running from the Godot editor ............ ON
#      - An exported build made with "Debug" ...... ON
#      - An exported build made with "Release" .... OFF
#    So day-to-day work needs no action at all: press play, cheats work.
#
# 2) Force it, for a one-off test
#    Change MODE below to Mode.FORCE_OFF to play the game exactly as a real
#    player would while still running from the editor — the fastest way to
#    check that a release build behaves. Mode.FORCE_ON does the reverse.
#    This is a const, so it costs nothing at runtime.
#
# 3) Command line, for an already-exported build
#    Launch the exe with --debug-mode to switch cheats on, or --no-debug-mode
#    to switch them off, without re-exporting. Only useful when MODE is AUTO;
#    a forced MODE deliberately ignores the command line.
#
# Everything is resolved once on first use and cached, so calling is_enabled()
# inside _physics_process() or a per-card loop is free.
# ============================================================

enum Mode {
	AUTO,       ## Follow OS.is_debug_build() — editor and debug exports are ON, release is OFF.
	FORCE_ON,   ## Always ON, even in a release export.
	FORCE_OFF,  ## Always OFF, even in the editor.
}

## The switch. Leave on AUTO unless you are deliberately testing the other side.
const MODE: Mode = Mode.AUTO

const CMDLINE_ENABLE  := "--debug-mode"
const CMDLINE_DISABLE := "--no-debug-mode"

# -1 = not resolved yet, 0 = off, 1 = on. Cached so the checks below run once per launch.
static var _resolved: int = -1


## True when developer-only features are allowed. The only question any caller
## should be asking — do not test OS.is_debug_build() directly anywhere else.
static func is_enabled() -> bool:
	if _resolved == -1:
		_resolved = 1 if _resolve() else 0
		print("DEBUG MODE: ", "ON" if _resolved == 1 else "OFF", " (", _reason(), ")")
	return _resolved == 1


static func _resolve() -> bool:
	if MODE == Mode.FORCE_ON:
		return true
	if MODE == Mode.FORCE_OFF:
		return false

	# AUTO: the command line wins over the build type so an exported build can be
	# flipped without re-exporting; disable wins over enable if both are passed.
	var args := OS.get_cmdline_args()
	if args.has(CMDLINE_DISABLE):
		return false
	if args.has(CMDLINE_ENABLE):
		return true

	return OS.is_debug_build()


## Human-readable explanation of why debug mode ended up on or off, for the
## startup print and anywhere else that wants to show the reason.
static func _reason() -> String:
	if MODE == Mode.FORCE_ON:
		return "forced on in Debug_Mode.gd"
	if MODE == Mode.FORCE_OFF:
		return "forced off in Debug_Mode.gd"
	var args := OS.get_cmdline_args()
	if args.has(CMDLINE_DISABLE):
		return CMDLINE_DISABLE + " on the command line"
	if args.has(CMDLINE_ENABLE):
		return CMDLINE_ENABLE + " on the command line"
	return "debug build" if OS.is_debug_build() else "release build"
