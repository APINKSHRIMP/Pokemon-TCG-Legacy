# Card Audit Findings — 2026-11-19 (extended probe: Tools, Stadiums, Special Energy, conditional boards)

Produced by running code: the headless `Card_Probe` harness extended to play Pokémon Tools, Stadiums and Special Energy for real and to run
condition-dependent attacks on a board where the condition is true. Complements `AUDIT_FINDINGS_2026-11-19.md` (one-shot attacks/Powers/Trainers) and
`AUDIT_FINDINGS_2026-11-18.md`. **Findings were written by an AI reviewer: verify each one against the code before changing anything.**
Nothing has been fixed or committed by this audit. Helper scripts: `Scripts/Utilities/audit/` (`Card_Probe.gd`, `run_compare.py` + `run_compare_ext.py`), output: `audit_out/`.

## Coverage of this pass (all 37 sets, 0 hangs, 0 script errors outside known artifacts)

| Kind | Jobs | What each job does |
|---|---|---|
| Pokémon Tool (38 cards) | 318 | play from hand (me / CPU), attacker holds it, defender holds it, defender KO'd while holding it (30 HP), damaged defender, Prize-condition, type-restricted attacker, "between turns" berries, discard at end of turn(s) |
| Stadium (66 cards) | 495 | play, replace an opponent-owned Stadium, same-name replay, every menu action twice (once-per-turn), attack with it in play, per-type / per-name HP and retreat-cost stats, 5-Bench play |
| Special Energy (70 cards) | 669 | provided Energy, attach rule, on-attach effect on a hurt/statused Pokémon, attacker alone / with basics / per mentioned type, on the defender, and a "holder meets its own attach rule" board (Evolved, named, behind on Prizes, one basic of every type) |
| Conditional boards | 1,532 | each attack whose text names a condition, on boards: Defending ex / Evolved / Stage 2 / damaged / statused / typed / with Energy, own damaged, 1 Prize left (each side), own & foe Bench 0/5, discard pile rich/empty, hand 0/8, own/def Tool, +Energy of the named type |

Run lines: `... Card_Probe.tscn -- --probe-set=<all sets> --kind=tool|stadium|senergy|cond` (resumes via `run_progress.json`), then `python -I Scripts/Utilities/audit/run_compare.py`.
Exact per-unit damage formulas (damage counters, Defending Energy, Bench size, Prizes taken, hand size) were checked on 54 condition boards: no mismatch.
"N more damage if ..." attacks (all conditions above): no attack failed to apply its bonus.

## How to work through this (instructions for the fixing session)

**Project rules (CLAUDE.md + memory):** never commit unless asked; syntax-check each edited script with `--check-only --script` one file at a time; tag fixes with `ISSUE`/`FIX ACTIVE` prints and an Issue_Log "Untested Fix" row as usual.
After a fix, re-run just that card: `"C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --fixed-fps 60 --path . res://Scripts/Utilities/audit/Card_Probe.tscn -- --probe-cards=<uid> --probe-reset`
(the new job kinds are generated for these uids automatically), then `python -I Scripts/Utilities/audit/run_compare.py` and look for the flag named in each item.
Do not run the probe while another session runs the probe or the autotester (shared `user://autotest/`).

## Totals

- high / rules: 1 (neo4-100 Lucky Stadium)
- medium / rules: 2 (same-name Stadium rule, end-of-turn Tool discard)
- **Total unique findings: 3** (covering 1 + 20 + 5 cards)

## HIGH severity

### 1. [ ] neo4-100 Lucky Stadium — can be used any number of times per turn  (stadium action) [EASY]
- **Problem:** Card text: "Once during each player's turn (before attacking), that player may flip a coin. If heads, that player draws a card." For the human player the menu entry never goes away after use, so it can be used repeatedly in one turn (each use flips again and draws on heads).
- **Evidence:** the player's menu action "Lucky Stadium" is routed by NAME to basep-41's handler: `Powers_And_Bodies_Effects.gd:77` (`_power_dispatch["Lucky Stadium"] = ... basep_lucky_stadium_activate(false)`). That handler sets `player_lucky_stadium_used_this_turn` (`Trainer_Effects.gd:7175-7181`) but neo4-100's availability is `neo4_lucky_stadium_active()` (`Trainer_Effects.gd:8649-8653`), which only checks `_neo4_stadium_used()`; `neo4_lucky_stadium_activate` (`Trainer_Effects.gd:8655-8657`, which would call `_mark_neo4_stadium_used`) is only called for the CPU (`Powers_And_Bodies_Effects.gd:7901-7902`). Menu listing: `Powers_And_Bodies_Effects.gd:754-756`. Probe: `audit_out/run_diffs.csv` flag `stadium_reusable_same_turn`, neo4-100 `actions`: the action was still listed after use (`listed_before_2: true`) and a second use changed hand/deck again; basep-41 correctly drops out after one use.
- **Proposed fix:** make the `"Lucky Stadium"` power dispatch branch on the Stadium in play (`main.current_stadium_card.uid`): neo4-100 -> `neo4_lucky_stadium_activate(false)`, basep-41 -> `basep_lucky_stadium_activate(false)`. Check the other name-shared Stadium actions the same way (Healing Field, Radio Tower etc. were fine in the probe).

## MEDIUM severity

### 2. [ ] 20 Stadium cards — "a Stadium with the same name is in play: you can't play this card" is not enforced  (rules) [EASY]
- **Problem:** These cards print "If a Stadium card with the same name is in play, you can't play this card." The game lets you play the second copy; it replaces the first (first goes to the discard pile, "X WAS DISCARDED!", on-play effects such as Giant Stump's trim run again, and a played card is consumed for nothing).
- **Cards:** ex11-94, ex11-96, ex12-72, ex12-74, ex12-75, ex12-76, ex12-77, ex13-87, ex14-75, ex14-79, ex15-74, ex16-71, ex16-72, ex16-76, ex16-79, ex16-82, np-28, pop2-10, pop3-10, pop3-11 (probe flag `stadium_same_name_allowed`).
- **Evidence:** `Trainer_Effects.gd:1174-1250` `validate_trainer_can_be_played` has no Stadium same-name check (only Commanding Aura / Delta Block, `:1224,1229`); `resolve_stadium_trainer` (`Trainer_Effects.gd:5712-5733`) discards any existing Stadium unconditionally. Probe `same_name` job: validate returned "" and the log shows "<name> WAS DISCARDED!" (e.g. ex12-75).
- **Proposed fix:** in `validate_trainer_can_be_played`, if the card is a Stadium and `main.current_stadium_card` has the same `metadata.name` (treat pop reprints by name, they match) and the card text contains "same name", return a refusal string. The CPU already calls the validator (`CPU_AI.gd:7416,7429`), so it picks up the rule. Cards WITHOUT that clause (46 older ones) may legitimately replace a same-named Stadium - do not apply it to them.

### 3. [ ] Memory Berry (ecard2-128, ex14-80) and Crystal Shard (ecard3-122, ex8-85, ex14-76) are never discarded after the holder attacks  (tool discard) [EASY]
- **Problem:** "Discard this card at the end of any turn the Pokémon attacks" / "If that Pokémon attacks, discard this card at the end of the turn." The Tool stays attached forever, so the Memory Berry's extra attacks and Crystal Shard's Colorless typing are permanent instead of one-shot.
- **Evidence:** the discard code is gated on `main.player_attacked_this_turn` / `opponent_attacked_this_turn` (`Trainer_Effects.gd:4500-4501` and `:4542`, inside `gym1_end_of_turn_cleanup`), but `inbetween_turn_checks` clears those flags first: `Main_Match_Core_Gameplay_Script.gd:8433` (player) and `:8437` (opponent), and only afterwards calls `gym1_end_of_turn_cleanup(false)` at `:8462` / `(true)` at `:8488`. So the condition is always false. Probe `atk_tool`: after the attack turn and the CPU's following turn (turn counter +2) `me_cards` still held the Berry/Shard (flag `tool_not_discarded_end_of_turn`); Strength Charm (uses its own effect flag) and Buffer Piece did discard correctly.
- **Proposed fix:** read the attacked flag before it is cleared (e.g. pass it into `gym1_end_of_turn_cleanup`, or clear the flags after the cleanup calls, checking nothing between `:8433` and `:8462` needs the cleared value - the `last_attack_on_*` mirror-move reset just above uses it before clearing).

## Probe artifacts found and filtered (also recorded in the memory note)

- Power Saver cards (Kyogre ex ex4-3, Team Magma's Groudon ex4-9): `Main:9967` error, already known; now filtered in both compare scripts.
- Condition boards that do not model direction/history: "damage counters on the Defending Pokémon" vs own damage, "your opponent has only 1 Prize", Stage 2 only (needs `def_stage2`), "more Energy than", energy-cap attacks ("can't add more than 20"), "you may discard" prompt-dependent attacks, "last turn" attack history, per-name Bench counts (Magnemite, Zubat, Omanyte...).
- Stadium actions offered at the start of the turn instead of the menu: Holon Ruins, Power Tree, Strange Cave; Pokémon Park is passive.
- Tools "between turns" scenario runs the whole next CPU turn, so HP read-outs are noisy; the berries' messages show them firing (Oran, Lum, Sitrus, Healing Berry), no flag raised.
- Team Aqua/Magma Belt cannot attach to a non-team Pokémon, Miracle Energy needs a Shining/Light Pokémon: correct refusals.

## Not covered by this pass (needs a different harness)

- Tools/Stadiums/Special Energy whose effect needs the CPU to act mid-turn (Time Shard, Counterattack Claws, EXP.ALL, Focus Band coin flips, Star Piece, Team Belts evolving a team Pokémon from the deck).
- Stadium effects needing specific cards in play (Holon Legacy / Lake on δ Pokémon, Sidney's/Glacia's on typed Pokémon with status or Weakness, Mirage Stadium retreat flips, Cursed Stone / Desert Ruins / Full Flame between-turn counters).
- Special Energy whose text depends on the other Energy / weakness (Holon FF no Weakness, GL status immunity, WP effect prevention, Recycle Energy, Retro Energy's optional prompt).
