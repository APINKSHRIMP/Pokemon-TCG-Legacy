# Export readiness — 2026-11-24

## What was wrong (would have broken an exported build)

An exported game differs from the editor in two ways that matter here:

1. **Folders hold `X.png.import`, not `X.png`.** Any loop that lists a folder and skips `.import` files comes back EMPTY.
2. **The PCK is case-sensitive.** In the editor Windows ignores case, but in an export `1ash.png` does not find `1Ash.png`.

| # | Where | Symptom in an export | Fixed |
|---|-------|----------------------|-------|
| 1 | `First_Boot_Setup_Script.gd` sprite grid + starter costume list | New game shows no characters to pick | ✅ uses `GameState.list_asset_files` |
| 2 | `Coin_Case_Script.gd` | Coin Case empty | ✅ |
| 3 | `Costume_Script.gd` | Costume screen empty | ✅ |
| 4 | `Sleeves_Scene_Script.gd` | Sleeve screen empty | ✅ |
| 5 | `Match_Transition.gd`, `Match_End_Outro_Script.gd`, `Best_Of_3_Transition_Script.gd` `_sprite_for` | No trainer portraits on VS / outro / Bo3 screens (584 of 586 portraits have capitals; the code lower-cased the name) | ✅ `AssetLookup.resolve` |
| 6 | Outro costume reward, overworld costume gift (`MapManager`), trainer card (`Info_Script`), save-slot preview (`Save_Select_Screen`) | Costume art missing (costume keys are stored lower-case) | ✅ new `GameState.costume_path()` / `costume_texture()` |
| 7 | `Cosmetic_Shop_Script.gd` row art | Art missing if a hand-typed row's case differs | ✅ `AssetLookup.resolve` |
| 8 | `Scenes/_Probe/_probe.tscn` pointed at `_probe/` (wrong case) | Dev probe only | ✅ path fixed |

All code changes are tagged `# EXPORT 2026-11-24:`. Verification: compile-all probe gave 217 scripts with 0 failures. A headless probe confirmed:
- `costume_path("1ash.png")` → `1Ash.png`
- `"roughneck"` → `Roughneck.png`
- the coin listing shows 420 files with no `.import` leaks
- the sprite listing shows 586 files

Already export-safe (checked, no change needed): `GameState.list_asset_files`, `SceneCache._folder_files`, `Phone_Call`, `Overworld_Pokemon_Data`, `Sound_Manager.list_bgm` and cries, `AssetLookup`, the splash card pool, and all JSON folder reads.

## export_presets.cfg (new)

I added one **Windows Desktop** preset:
- **Include filter `*.json`.** This is essential: card sets, opponents, decks, characters and player seeds are plain JSON, and Godot only packs imported resources by default.
- **Excludes:** `audit_out/`, `Docs/`, `Spreadsheets/`, the stray top-level `In_Battle_Sprites/` (a 428-image duplicate nothing references), `Scenes/_Probe/`, `Scripts/Utilities/audit/`, `*.py`, `*.md`, `*.xlsx`.
- **Output:** `../PKMTCG_Export/Pokemon TCG Legacy.exe`. The PCK sits beside the exe, not embedded.

## Still needs you

1. **Export templates are not installed.** In Godot, go to Editor → Manage Export Templates → Download (4.6.1, about 1 GB). I didn't download them without asking.
2. **Windows .exe icon:** `application/icon` is blank. It needs an `.ico` file; the project icon is a PNG.
3. **Version / company / copyright** fields are blank. Fill them in under Project → Export.
4. **Export with "Release"** (untick "Export With Debug"). That turns `DebugMode` off: no DEL menu, cheats or placement tool.
5. Do a test run of the exe: new game → pick a sprite → open Coin Case, Costumes and Sleeves → play one match, checking the portraits on the VS screen and the outro.

## Known dev-only things that simply won't work in an export (fine)

- These all write into `res://`, which is read-only in an export, and they are all debug-gated:
  - Opponent_Ratings deck test
  - Bug_Report (writes `Spreadsheets/_pending_bug_reports.jsonl`)
  - the autotester
  - the placement tool / character editor
- `Match_End_Outro_Script.gd:1551`: the fallback scene `World_Map_Base_Scene.tscn` doesn't exist. It is only used if the return map path is empty, which never happens in normal play.
