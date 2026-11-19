# Card Audit Findings — 2026-11-19 (script-first audit)

Produced by running code, not by reading it: a static triage script, a headless run-the-card probe, 210 autotester matches, then a model
review of only the flagged cards. Complements `AUDIT_FINDINGS_2026-11-18.md` (nothing already listed there was re-audited).
**Findings were written by an AI reviewer: verify each one against the code before changing anything.**
Nothing has been fixed or committed by this audit. Helper scripts live in `Scripts/Utilities/audit/`, all output in `audit_out/`.

## How to work through this (instructions for the fixing session)

**Model guidance:** both items below are `[EASY]` (a number read from the wrong phrase; a coin flip that is not on the card). A cheaper model can fix them.
For anything that touches shared engine code, use Opus.

**Project rules (CLAUDE.md + memory):** never commit unless asked; syntax-check each edited script with `--check-only --script` one file at a time
(`reference_godot_syntax_check.md`); attack handlers are keyed by LOWERCASED NAME and chained (later registrations / `_r3_wrap` / `_r4_wrap_if` / uid-prefix branches
win), so before changing a handler list every registration of that name: `grep -n '"skill dive"' Attack_Effects.gd`.
After fixing, re-run the probe on the card (`Card_Probe.tscn -- --probe-cards=ex11-86 --probe-reset`) and then the autotester (>=100 matches).

## Totals

- high / effect: 2
- **Total unique findings: 2**

## HIGH severity

### 1. [x] ex11-86 Taillow — Skill Dive  (effect) [EASY]
- **Done (2026-11-19):** handler now falls back to `extract_number_before(text, "damage to 1 of")`; re-probed ex11-86 = 10, ex7-3 = 30, ex9-41 = 40.
- **Problem:** The card says "Does 10 damage to 1 of your opponent's Pokémon". The handler reads the number with `extract_number_before(text, "damage to that")`, a phrase that is not in this card's text, so it returns 0 and falls back to the default 30. Skill Dive does 30 instead of 10.
- **Evidence:** `Attack_Effects.gd:26618-26620` (`var n = extract_number_before(atk.get("text","").to_lower(), "damage to that")` then `n if n > 0 else 30`). Older registration `Attack_Effects.gd:24700` hardcodes 30. Probe (`audit_out/run_log.jsonl`, ex11-86 Skill Dive): a chosen Benched Pokémon went 900 -> 870.
- **Proposed fix:** also try `extract_number_before(text, "damage to 1 of")` before the 30 default. Check every card named Skill Dive for its own printed number (an ex3 version may really be 30).
- **Files:** Attack_Effects.gd

### 2. [x] ex12-24 Pinsir — Overhead Toss  (effect) [EASY]
- **Done (2026-11-19):** `execute_overhead_toss` has a `needs_flip` parameter (default true); the ex12 branch passes false. Re-probed: ex12-24 always damages your Bench; gym2-24 and neo3-38 still flip.
- **Problem:** Pinsir's text has no coin flip: "Does 20 damage to 1 of your Benched Pokémon" (after its 30 to the Defending Pokémon). The shared executor flips a coin and only damages the Bench on TAILS, so half the time (heads) the self-damage never happens. The probe printed "HEADS! NO BENCH DAMAGE!".
- **Evidence:** `Attack_Effects.gd:6792-6800` (`execute_overhead_toss`: `var coin = await main.flip_coin(...)`, `if not coin:`); the ex12 branch at `Attack_Effects.gd:29400-29406` calls the same executor with the bench damage read from text.
- **Proposed fix:** add a parameter (e.g. `needs_flip := true`) to `execute_overhead_toss` and pass `false` from the `ex12-` branch; keep the coin for the card whose text has one.
- **Files:** Attack_Effects.gd

## What was checked and found clean (so nobody re-audits it)
100 flagged cards were reviewed in full (list: `audit_out/done.txt`, notes: `audit_out/findings.jsonl`): the 62 top-scored ex1–ex16 cards plus a 24-card sweep of base/gym/neo/ecard/basep cards. Examples confirmed correct by running them: Link Blast, Energy Ball/Hydro Pump/Hydrocannon caps, Pebble Throw (all four printings), the self-switch attacks (Reverse Thrust, Run Around, Hide in Shadows, Leap Out), Ram/Knock Back/Horn Toss/Crystal Wave switching, Hyper Needle lock, Super Fang. The step-3 "CPU skipped Pebble Throw" report was a deliberate pass (Pebble Throw only hits the Bench and the player's Bench was empty).
On-evolve / on-bench Powers (Evolutionary Fan, Blissful Support, Crush Chance, Delta Switch, Tropical Heal, Chilling Breath, Darker Ring) ARE implemented, through evolve hooks in `Main_Match_Core_Gameplay_Script.gd` (~7323, 9018-9052) and `Powers_And_Bodies_Effects.gd` (~17445, 20257); Poké-Bodies that change type live in `Card_Class_Object_Script.gd:334-371`.

## Summary

| Step | What ran | Result |
|---|---|---|
| 1 Triage (`triage.py`, no model) | all 3,221 cards, all attacks/powers/bodies/trainers vs the battle scripts | 1,581 static leads on 680 cards (after skipping the 184 already-audited items) |
| 2 Probe (`Card_Probe.gd`, headless real match scene) | 800 jobs: every flagged ex1–ex16 attack, activated Power and Trainer run once against a standard defender | 0 hangs, 2 probe-only script errors (a Power Saver rule), 129 diffs on 77 cards after filter fixes |
| 3 Autotester | 210 CPU-vs-bot matches, ex1–ex16 decks | 0 crashes/stalls/duplicates, oracles 0 wrong, 1 CPU flag (deliberate pass) |
| 4 Model review | 100 cards in 5 batches | **2 real bugs**, 98 cleared |

- **Cards flagged:** 866 by triage + probe; the queue was cut to 88 once batch 1 showed the static flags were noise.
- **Findings that were real:** 2 of 100 reviewed cards. Both came from the probe (one from a "stated damage not seen" diff, one from the "NO BENCH DAMAGE" message), neither from a static flag.
- **What the scripts caught that reading would have missed:** both bugs were found by *observing* behaviour (a 30 where 10 is printed; a coin flip that the card doesn't have) in handlers that look plausible when read, because the wrong number is a fallback default and the coin is inside a shared executor. The static "number missing / name collision / no prompt" leads on the reviewed cards were all disproved cheaply by the probe's numbers (handlers split variants by uid prefix or by text), which is what stopped a full read of 35,000-line files. The static flags themselves had ~0% precision: do not trust `b_name_collision`, `a_number_missing`, `c_choice_no_prompt`.
- **Honest limits:** the probe only runs one attack once on one board, so it cannot see conditional effects (Darkness Energy adds damage for Darkness attackers; no basic Darkness/Metal Energy exists, so those attackers' damage is not checked), coin-flip results, or multi-turn effects. Cards not flagged by the triage (about 2,300) and Pokémon Tools / Stadiums / Special Energy were not run. Most of the 1,581 triage leads were never model-reviewed (dropped by the filters after batch 1 showed they were noise).

## Tools (re-runnable)
- `python -I Scripts/Utilities/audit/triage.py` → `audit_out/triage.csv`, `triage_cards.csv`
- `Card_Probe.tscn -- --probe-set=ex10[,ex11...] [--all] [--probe-cards=uid,uid] [--probe-reset]` → `run_log.jsonl`; then `python -I Scripts/Utilities/audit/run_compare.py` → `run_diffs.csv`
- `python -I Scripts/Utilities/audit/make_batch.py [N size]` builds the review queue / evidence packs (`queue.txt`, `batch_N.md`)
- Memory worth saving after fixing: the probe harness and its Darkness Energy blind spot.
