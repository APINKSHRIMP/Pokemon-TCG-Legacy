# Autotest summary (step 3) - 2026-11-19

Run: `Autotest_Runner.tscn -- --matches=210 --sets=ex1..ex16` (CPU vs random-legal bot, decks drawn only from the 16 ex sets).
Raw output: `%APPDATA%/Godot/app_userdata/Pokemon_TCG_Legacy/autotest/runs/2026-11-19T15-54-50/` (summary.txt, problems.txt, matches.jsonl).

| Item | Result |
|---|---|
| Matches | 210 (bot 28 wins / CPU 181 / 1 draw / 0 aborted) |
| Crashes / script errors | 0 |
| Stalls / soft-locks / turn limit | 0 |
| Card duplicated / missing, HP out of range, stale effect | 0 |
| Rule-check oracles (clean boards) | damage 48/0 wrong, status 115/0, draw 3/0 |
| CPU decision flags | 1 (SKIPPED ATTACK, match 4) |
| Coverage (cumulative) | attacks 4455/4455, powers 285/285, trainers 422/422, energy 70/70 |
| CPU turn time | avg 96 ms, p95 306 ms, slowest 629 ms |

## The one problem
`CPU DECISION: SKIPPED ATTACK` - match 4, seed 103693, turn 4: CPU (Snorunt, ex16-64) "could use Pebble Throw but ended the turn without attacking".
- `--replay=2026-11-19T15-54-50:4` did NOT reproduce it (0 problems), so it is not deterministic from the stored decks/seed alone; treated as unreproduced.
- The log line just before it: `EFFECT PARSED: No recognised effects in: choose 1 of your opponent's benched pokemon. this attack does 10 damage to that...` -
  Pebble Throw (ex3-55, ex12-67, ex13-65, ex16-64) is NOT in the attack registry with a matching handler for this text; it resolves to a handler (Attack_Effects.gd L30087) shared with another Pebble Throw text, and the generic parser has no phrase for "choose 1 of the opponent's Benched Pokemon ... 10 damage".
  The static triage independently flagged all four cards (b_name_collision, c_choice_no_prompt, a_number_missing). Likely a REAL bug: handler shape/name collision. Goes to step 4 as a high-priority lead.

## Reading
The engine is stable for these sets under random play (no crashes in 210 matches, ~2,400 CPU turns): the remaining bugs are effect-correctness bugs (wrong numbers, missing prompts, wrong target), which random play does not crash on. That is what steps 1, 2 and 4 look for.
