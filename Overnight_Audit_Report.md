# Overnight audit (23–24 Nov 2026)

Full audit of the code and data. Everything found was **fixed, not logged**. Nothing is committed.
Each code fix carries a `# AUDIT 2026-11-24:` comment.

- **Session 1:** 23 Nov, from 22:30 until its 5-hour usage window ran out.
- **Session 2:** started automatically at 01:32 by a scheduled task. It started with the weekly usage at 92%
  and stopped at about 94–95%, leaving room to finish the report and shut the PC down. A watchdog task also shuts the PC down after 25 minutes with no activity, or at 05:57.

## Summary
Nothing was committed. Every code change carries `# AUDIT 2026-11-24:`. All 217 scripts compile. The
autotester ran about 440 matches across both sessions (default, real opponents, smart bot): 0 problems.

**Fixed: real bugs**
- Trainer-undo was never closed by a message, because a glued line in `show_message()` never ran (S1).
- 16 gym card rewards never showed up in the collection, because of capital-G IDs. `give_cards()` now
  lowercases set prefixes itself (S1).
- Ninjaboy Sasuke's coin pointed at a file that didn't exist (`Exans` → `Ekans Purple.png`) (S1).
- 43 places read the printed HP instead of `get_max_hp()`: the HP display, heals, Potion-style
  Trainers with Energy Root, KO checks and HP resets (S1). In S2, the CPU's Potion Energy score had
  the same problem.
- The CPU's Windstorm checked for the wrong Tool subtype (S1).
- The Makeover planner reordered Energy while looping over it (S1).
- The starting save counted 2 costumes that don't exist (S1).
- The CPU could throw away Aqua / Magma Energy, which is discarded at the end of the turn (S2).
- 16 opponents' ban lists named a deleted card ID, `base5-72` (S2).
- Veteran Sylvester's costume reward was misspelled (`VeteranM_2`) (S2).

**Removed: dead code**
About 1,730 lines in total: 69 functions in S1, and the old attack-button row, the card-list side bar,
the old bed and 4 helpers in S2.

**Needs your call:** see below. Koga's and Margot's missing coin art, the identical Gym Challenge card rewards, the
old tilesets, the TEST deck, and Dark Raichu / Shining / ex-era rarities that no pack or shop gives.

**Not finished:** a full logic read of Attack_Effects, Powers_And_Bodies, Trainer_Effects and CPU_AI
(~150k lines, so scans and probes were used instead), plus most of the menus and overworld scripts.

**Left alone (low value):** about 88 constants are never referenced. Most are BGM names, layout sizes,
and the `CARD_SIZE_*` table in the core script. Sound_Manager's `BGM_*` names may be picked by name
from data. Removing them would be cosmetic only.

## Session 3 (24 Nov, daytime, with you)
- **Your calls, answered:**
  - Margot's coin art existed, but the file was misspelt `Goldbat Gold.png`. It's renamed to `Golbat Gold.png`.
  - Koga's `Energy Colorless Silver 2` really has no art anywhere, PKMTCG included. It needs drawing.
  - The Gym Challenge `gym1-1` card rewards are removed. Each leader now gives their own gym pack, and Giovanni gives 2.
  - The 6 old tilesets are deleted. No PNGs needed moving: every Image_Sheets PNG is in use.
  - Dark Raichu will be a gift, and no ex-era or Shining rarities come from packs yet.
- **Export readiness:** see `Export_Readiness_Report.md`. Menus would have been empty and trainer portraits missing in an exported build (case-sensitive PCK, `.import` listings). Fixed and probe-verified. `export_presets.cfg` added.
- **Area 8, save system: real bug fixed.**
  - Before: a crash, power cut or full disk while saving left a half-written `Player_Game_Progress.json`. The next boot couldn't read it, replaced it with a near-empty save, and wrote that straight over the file, losing the whole game.
  - Now: progress, owned cards (all 3 writers), current deck and the nature guide go through `GameState.write_text_atomic()`. It writes `.tmp` first, swaps it in, and keeps the previous copy as `.bak`.
  - On slot load, `recover_save_folder()` restores any unreadable file from its `.tmp` / `.bak` before seeding, and keeps the bad copy as `.corrupt`.
  - Verified with a scratch-folder probe covering a truncated file, a crash between the swaps, a healthy file and a no-backup case. Also verified with compile-all (217/0) and 30 autotester matches (0 problems).
- **Your 267 logged matches (CPU look):** nothing glaring.
  - The analyser's "CPU would Flamethrower a target Slash already KOs" was a false alarm. Its shadow scorer left out the discard penalty, and the real CPU picks Slash / Fire Punch.
  - The shadow now mirrors the drawback terms. Two scenarios (`sc_ko_*`) were added, and all 59 scenarios pass.
  - The "CPU would retreat where you stayed" cases are all weak or zero-Energy Actives, which is sensible.

## Needs your call
_(things that need a design decision, so they were left alone)_

- **Gym Challenge Koga's coin `Energy Colorless Silver 2` has no image.** Every other type has a
  "2" coin (`Energy Fire Red 2`...), but Colorless only has `Energy Colorless Silver` (Ex Gym Leader
  Koga's reward). It needs the art, or a different coin.
- **Rocket Grunt Margot's coin `Golbat Gold` has no image either** (session 2). No Golbat coin exists in
  `Image_Assets/Coins/`, so the reward reveal has no art. It needs the art, or a different coin.
- **All 8 Gym Challenge opponents reward the same card, `gym1-1`.** Is that a placeholder?
- **The old time-of-day tilesets can go.** These 6 tilesets in `Image_Assets/Map_Sheets/Tile_Sets/` are unused:
  `Celeste_Harbour_Morning/Evening/Night.tres` and `Verdant_Forest_Morning/Evening/Night.tres`. The colour
  grade replaced them on 13 Oct, and the Evening/Night ones now point at images you've already deleted.
  I left them because the notes say they stay until you delete them. Nothing references them, so
  they're safe to delete.
- **Dark Raichu (base5-83, "Rare Secret") can't be obtained.** The pack roller
  (`Pack_Opening_Manager._generate_pack_cards`) only sorts Common / Uncommon / Rare / Rare Holo, and the
  Holo Rare shop only sells "Rare Holo", so no pack or shop ever gives it. The same will apply to
  neo3/neo4's 10 "Rare Shining" cards and the ex-era "Rare Holo EX" / "Rare Holo Star" / "Rare Secret"
  cards once those packs go on sale (none are stocked yet: neo1–4 have prices in pack_prices.json
  but no shop sells them and they have no pack art). Do you want them in the rare slot (as a rare
  chance), in the Holo shop, or left out on purpose?
- **TEST.json** (your test deck) has 12 Loudred / 14 Whismur and mixes eras. That's fine for a
  test deck; mentioned only because the deck check flagged it.

## Areas
Mark each area `[x]` when finished. Add a line saying which session did it.

- [x] 1. Compile-all: every .gd loads with the autoloads registered. *(Session 1: 217/217, re-run after every fix.)*
- [ ] 2. Battle core: Main_Match_Core_Gameplay_Script.gd (turn loop, KO, prizes, retreat, status, evolution)
  *(Session 1: HP display, glued `trainer_undo_commit` call. Autotester 260 matches clean.)*
- [ ] 3. Effect scripts: Attack_Effects, Trainer_Effects, Powers_And_Bodies_Effects, Special_Energy_Effects, Match_Effects, Card_Ops
  *(Session 1: the max-HP class across all of them, the loop-erase scan, the string-literal scan vs card data.
  Not done: a read-through for logic bugs.)*
  *(Session 2: Match_Effects and Special_Energy_Effects read in full (Aqua/Magma CPU gate, Potion Energy
  score, 2 dead functions); every uncapped heal, Damage Swap / Strange Behavior loops, status strings,
  divisions. Attack_Effects / Powers / Trainer_Effects still only scanned, not read.)*
- [ ] 4. CPU_AI.gd (and CPU weights / scenarios)
- [ ] 5. Match UI: intro/outro, rewards, transition overlay, message box, hand bar, pause menu
  *(Session 2: outro `_ready` / reward / LP flow read, clean; old attack-button row removed as dead.)*
- [ ] 6. Overworld: MapManager, map scenes, doors, cutscenes, character schedules, NPC routes, phone, clock
  *(Session 2: Character_Schedule.gd read in full; all 20 character files' rules validated; all 45 doors
  (3 inert by design: Train Station endgame ×2, Fish Shop upstairs placeholder), every link two-way.)*
- [ ] 7. Menus: deck builder, card search, pack opening, shops (cards, cosmetics, fish, bulk sell), coin case, options, save select
  *(Session 2: pack roller, pack shop stock, cosmetic/fish/LP shop art, bulk-sell rarity bands,
  deck-builder copy limits. Not read: the rest of the deck builder, coin case, options, save select.)*
- [ ] 8. GameState / save system / Settings / medals / LP
  *(Session 2: cash, LP wallet, card give/remove, opponent beaten/record, time points, medal stats.)*
  *(Session 3: slot load / new game / delete / seeding / intro checkpoint read; crash-safe saves added (see Session 3).
  Still direct writes (low value, one small file each): Player_Current_Data from Coin Case / Costume / Info /
  deck builder, deck files, Settings.json.)*
- [x] 9. JSON data: card sets, opponent decks and opponents, NPC/time-of-day files, shops, schedules, medals, deck ratings
  *(Session 1: all 300 JSON files parse, no duplicate keys. Decks, rewards, ratings, match_effects
  types, story flags (every flag the game checks also gets set), medal bonus ids, file paths, the
  starting save, card fields.)*
- [ ] 10. Utilities, debug tools, Python scripts, autotester *(Session 1: all 41 .py files compile.)*
- [x] 11. Dead code and unused files (functions, variables, scripts, scenes, assets)
  *(Session 1: 69 functions. Broken scene/resource references: only the old tilesets, see "Needs your call".)*
- [x] 12. Efficiency: hot paths in _process, repeated loads, per-frame allocations
  *(Session 1: no waste in any `_process`. The CPU's first turn can take ~1s (95th percentile ~0.55s);
  not changed, because it is the planner thinking.)*

## Fixes
_(one line per fix: file — what was wrong — what changed)_

- **Main_Match_Core_Gameplay_Script.gd `show_message()`** — the Pokémon-cries commit had glued
  `trainer_undo_commit("message")` onto the end of a comment, so it never ran. No message closed the
  Trainer-undo window any more: a Trainer that had already shown a message could still be cancelled
  at its first picker. Put back on its own line. (Scanned every script for the same glued-code
  pattern: no other cases.)
- **All_NPC_Constant_Data.json** — 16 `card_reward`s were typed `Gym1-1` / `Gym2-4` etc. (capital G).
  `give_cards()` saved them as a separate entry that never matches the real `gym1-1`, so those gym
  rewards never showed up in the collection. Lowercased the prefixes (Ex Gym Leaders ×8, Gym Challenge ×8).
- **Game_State_Script.gd `give_cards()`** — now lowercases the set prefix of every ID itself, so a
  mistyped reward can't do that again. Only the prefix: some numbers are upper case (`ex10-A`).
- **Image_Assets/Coins/Exans Purple.png → Ekans Purple.png** — the image name was misspelled, so Ninjaboy
  Sasuke's coin reward `Ekans Purple` pointed at a file that didn't exist. No other references.
- **Dead code: removed 69 functions (~680 lines) across 28 scripts.** Each had zero references anywhere
  in .gd/.tscn/.json/.py, and no code builds a function name from a string (the only callers that do,
  CPU_Scenarios `sc_*` and Gif_Director `shot_*`, were left alone). Each one that looked like a
  missing feature was checked first: Crystal Body, Legendary Body, Retreat Aid, Intimidating Armor,
  Dark Mind, Scoop Up / Super Scoop Up / Mr. Briney scoring and Alt+click hand view are all handled
  by newer code. These were superseded copies. Biggest: old Dark Charmeleon Fireball / gym2 evolve /
  neo4 helpers (Attack_Effects), 5 old CPU trainer scorers + `evaluate_hand_card_priority` (CPU_AI),
  the HP-circle row builders and `get_side`/`get_owner_side` (core), the unused deck-viewer list
  builders (Card_Viewer_List / deck builder), interior-position getters (GameState).
  `_walk_reveal_new_only` (marked "Kept, unused") and the commented-out Match_Start_Intro_Script
  ("kept for reference") were kept. All 217 scripts still compile.
- **Max HP read from the printed card (43 sites → `get_max_hp()`).** `get_max_hp()` adds Energy Root
  (+20), Giant Growth / Gaseous Form style overrides and the `max_hp_modifier` match rule (Verdant
  Forest + the `[` test day). These places used the printed HP instead:
  - **HP display** (active and bench, core): a full Pokémon with Energy Root showed "100 / 80" and the
    wrong damage-counter blocks.
  - **Heals:** Leech Seed, Spacing Out, the coin-flip heal-all attack, Potion Energy, Healing Fire,
    and the CPU's Natural Healing check. A Pokémon with Energy Root couldn't be healed; with a −HP rule,
    a heal could go over the real maximum.
  - **Damage moves:** Slowbro's counter move (wrong counter count), Unown J's damage swap, Ninetales
    Shapeshift's KO check, the Eevee-evolve power (now sets HP after the Tools move over, like normal
    evolution), and the CPU's Ditto foresight clone.
  - **HP resets:** six places put a Pokémon back to its printed HP (bench from hand/discard, Provoke,
    Unown return-to-hand, Electrode Buzzap), dropping the match HP rule.
  - **Trainers (18 more in Trainer_Effects.gd):**
    - The shared `gym1_heal_pokemon` cap.
    - The "is anything damaged?" checks behind Potion-style Trainers. With Energy Root these said
      "No damaged Pokémon to heal!".
    - A full-heal Trainer that healed nothing with Energy Root attached.
    - The devolve-to-Basic damage carry-over.
    - The CPU's most-damaged / HP% picks.
  - CPU-only rankings ("pick the biggest Basic") and card-text conditions ("Basic Pokémon with 100 HP
    or less") stay on the printed HP: that is what the card means.
- **CPU_AI.gd Windstorm scoring** — checked for subtype `"Tool"`, but the card data says `"Pokémon Tool"`,
  so the CPU never counted the player's Tools and only played Windstorm against a Stadium. (Scanned every
  subtype/type/ability/attack/name string in the code against the card data: this was the only real miss.)
- **Powers_And_Bodies_Effects.gd CPU Makeover planner** — removed and re-added Energy while looping
  over that same Energy list. That skipped the next Energy, re-checked the moved one, and left the
  Pokémon's Energy in a different order on screen. Now it swaps in place. (Scanned for the same
  pattern: the other hits copy the list first or stop right after.)
- **Player_Data/Player_Game_Progress.json** — the starting costumes listed `1champion_f.png` /
  `1champion_m.png`, which don't exist. They were counted as owned, so the costume screen's
  "owned / total" count was 2 too high. Removed.
- **Card_Image_Loader_Script.gd** — removed a "selection mode" block in the card-click handler that never
  ran. It found "the match" as `root.get_child(0)`, which is the first autoload (GameState), and then
  called `has_method()` on a variable, which is always false. (Scanned every `has_method`/`call`
  string in the code: no other dead lookups.)
- Autotester batch 2 (80 matches, after the dead-code removal): 0 problems, 100% coverage, oracles 0 wrong.
- Autotester batch 3 (60 matches, after the HP fixes): 0 problems, oracles 0 wrong.
- Autotester `--real --bot=smart` (all 111 real opponents, with their decks and match rules, after the
  HP fixes): 0 problems, damage oracle 363 checked / 0 wrong, status 51 / 0. The slowest CPU turn was
  3.3 s (a Blastoise deck, match 13 turn 7); the 95th percentile is 0.48 s.
- Checked, clean: no hot-path waste (the only `_process` loads are the texture prewarmers, which are
  meant to run there); Medals.json `bonus:` ids and tiers all exist in League_Config; the starting save's
  sleeves / coin / energy style exist; menus that write Player_Current_Data.json directly are safe,
  because GameState re-reads that file every time and never caches it.
- **Gym_Challenge_Hall.json + Verdant_Forest.json `restrictions.banned_card_ids`** (session 2) — all 16
  Ex Gym Leader / Gym Challenge opponents banned `base5-72`, the non-holo Rocket's Sneak Attack that the
  holo-duplicate cleanup deleted. The holo `base5-16` was already on the same lists, so nothing was
  un-banned; removed the dead ID. A sweep of every card-ID string in all 295 data JSON files
  (11,982 references) found no other missing card.
- **CPU_AI.gd `_cpu_one_turn_energy_wasted()`** (session 2) — the gate that stops the CPU attaching a one-turn
  Energy that adds no damage this turn only knew R / Boost / Miracle Energy (`must_discard_end_of_turn`).
  Aqua Energy and Magma Energy ("At the end of your turn, discard") are discarded by
  `gym1_end_of_turn_cleanup` instead, so the gate let the CPU throw them away (their own score even says
  "only worth attaching on the Active when it enables an attack this turn"). They now go through the gate.
  The game-side discard was already correct.
- **Special_Energy_Effects.gd** (session 2) — removed `get_outgoing_damage_modifier()` /
  `get_incoming_damage_reduction()`: never called (`r4_energy_damage_mod` replaced them); session 1's
  dead-code scan missed them because a comment names them. The CPU's Potion Energy score used the printed
  HP for "is it damaged?", so with Energy Root it scored a damaged Pokémon as full; now `get_max_hp()`.
  All 217 scripts still compile.
- **Dead code, second pass (session 2): ~1,050 more lines.** Session 1's scan counted a name in a *comment*
  as a reference. Re-ran it with comments stripped. Removed:
  - **Main_Match_Core_Gameplay_Script.gd** — the old attack-button row: `show_attack_buttons()` (nothing
    calls it; attacks are picked from the action-panel rows), `_render_attack_page`, the MORE pager,
    `_attack_row_metrics`, `_attack_cost_width/_types`, `_build_attack_button_content`, the button font and
    their sizing constants (386 lines). Kept the 4 constants still used elsewhere. `hide_attack_buttons()`
    still resets the CANCEL row.
  - **Card_Viewer_List.gd** — the ISSUE #154 right-hand text list (`build_side_list` + 6 font/bbcode
    helpers + constants, 257 lines). The deck viewer replaced it with boxed rows and the bulk-sell screen
    only calls `sort_ids`; the deck builder's comment that "the helper is untouched for the bulk-sell
    screen" was out of date and is corrected.
  - **Interactables_Script.gd** — the old bed (`_interact_bed`, `_do_sleep`, `BED_TOO_EARLY_TEXT`,
    `SLEEP_FADE_DURATION`). `_trigger()` stopped routing "Bed" there; the live bed is Player_House_Upstairs.gd.
  - **Card_Search_Overlay.gd** — `_row_pitch()`, `_make_icon_h()` (no callers).
  - Kept on purpose: `Cutscene.release_player`, `UIKit.restyle_buttons` (theme API), PixelDissolve (its calls
    are commented out, parked), `_bedtime_dismiss_battled_opponent` (sits beside its commented-out OLD call),
    `Speech_Voice.reload` (tuning tool), `labels_on` / `_resolve_player_cardback_path` / `_walk_reveal_new_only`
    (marked kept), and the one-line wrappers `pick_species` / `measure_and_hide_new_hand_slot`.
  - 217/217 compile; autotester 40 matches: 0 problems, coverage 100%.
- **All_NPC_Constant_Data.json, Veteran Sylvester** (session 2) — `costume_reward` said `VeteranM_2`; the
  file (and his own sprite) is `Veteran_M2`. Beating him added a costume that matches no image: it never
  showed on the costume screen and pushed the owned count up by one. Corrected. Every other opponent's
  coin / sleeve / costume reward resolves to a file (the costume names differ only in case, which is fine:
  GameState lowercases both sides).
- **Session 2 checks, all clean (no fix needed):** self-comparisons / duplicated conditions in every
  script; every `card.x` field access in the battle scripts exists on `card_object`; no coroutine
  result is used without `await` (2,369 coroutines checked); single-use dictionary keys (typo hunt);
  `$Node` / `get_node()` paths against their scenes (Gym Plaza lamps/shadows included); every cosmetic /
  fish / LP shop row has its art (sleeves full + small), every NPC `shop_id` exists in the inventory or
  shops.json; every heal that raises HP is capped at `get_max_hp()`; Damage Swap / Strange Behavior
  loops; the outro reward flow (first-win detection runs before `mark_opponent_beaten`, packs owed
  stop the skip-outro bail, LP rows) and GameState cash / LP / card give/remove; opponent `restrictions`
  keys / set ids / card names against Deck_Validation_Helper and the card data; every character file's
  `when` rules (time letters, day specs, `requires` heads and their `beaten:`/`met:` targets, kinds,
  positions, no rule shadowed by an identical earlier one); every Medals.json stat is handled by
  MedalData and every progress counter it reads is written; deck-builder copy limits (δ shares the
  name pool, ★ max 1 in total, ex separate); pack sets vs. pack art / prices / owned seeds; status
  condition strings; every division by a size/count is guarded; the 19 Nov probe's three open bugs
  (Lucky Stadium, same-name Stadium, Memory Berry / Crystal Shard) were already fixed that night.
- Checked, clean: all 217 scripts compile with autoloads; every opponent deck and starter deck is 60
  cards, max 4 per name, all card IDs exist; every opponent's deck file exists; every character file's
  opponents/NPCs exist in All_NPC_Constant_Data; Deck_Ratings / Opponent_Ratings keys all exist; coin
  shop files all exist; shops.json scenes exist. `REPLACEMUSIC` opponents fall back to the normal battle
  theme (by design).
