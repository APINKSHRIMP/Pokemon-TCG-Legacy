# Card Audit Findings — 2026-11-18

Produced by a read-only audit of card text vs. game code (effects, player choices, CPU decisions, animation).
**Coverage is PARTIAL (roughly a third of the 3,064 non-basic cards).** Audits were cut off by usage limits.
Sets with little or no coverage: ex10-ex16 (barely started), base1/base2, gym1, gym2, neo1, neo2-neo3, neo4, ecard1-3, ex1-ex9 (partial).
Findings were written by AI auditors: **verify each one against the code before changing anything** (a few may be wrong).

Nothing in the audit has been fixed. The only project change from this session is an UNTESTED edit to
`Scripts/Main_Match_Gameplay_Scripts/Attack_VFX.gd` (animation/sound end-fade) — review it with `git diff` or revert it with
`git checkout -- Scripts/Main_Match_Gameplay_Scripts/Attack_VFX.gd`. The animation/audio timing audit never produced its report.

## How to work through this (instructions for the fixing session)

**Model guidance:** Use **Opus (medium effort)** for every item tagged `[OPUS]` below, and for any fix that changes shared engine
code (durations/clearing of lingering effects, W/R ordering, damage pipeline, CPU scoring). Simple data/number fixes tagged
`[EASY]` can be done by a cheaper model. For `[OPUS]` items do the thinking: read the cited code, confirm the bug is real,
check name-collisions across sets (attack handlers are keyed by lowercased NAME — a later registration or `_r3_wrap`/`_r4`
wrap may change which handler runs), then choose the fix.

**Project rules to follow (from CLAUDE.md and memory notes):**
- Read first: `memory/project_base_gym_rules_audit.md`, `project_ex_rules_audit_round4.md`, `project_card_text_audit_round5.md`,
  `feedback_multi_select_and_card_flights.md`, `feedback_cpu_thinks_like_a_human.md`, `project_effect_ui_audit_2026-11-17.md`.
- Never commit unless the user asks. Syntax-check each edited script: `--check-only --script` one file at a time
  (see `reference_godot_syntax_check.md`).
- Reuse shared helpers (prompt_select_cards, pick_option/pick_yes_no, fly_card, r4 CPU helpers). No new one-at-a-time pick loops.
- After a batch of fixes: run the autotester (`project_autotest_harness.md`, >=100 matches) and replay any new problems.
- Shape of fix per kind: **effect** = make code match card text; **choice** = player must be prompted where text says "choose/may/up to";
  **cpu** = give the CPU a situational decision (when to play / when not to; sensible in-effect picks), tweak via CPU_AI scoring;
  **anim** = animation/sound mismatch (generator `Scripts/Utilities/attack_vfx_build.py` is the source of truth — never hand-edit the JSON outputs);
  **data** = card JSON error (also check seed files — see `project_holo_duplicate_removal.md`).
- Work in severity order: high -> medium -> low. Tick items off in this file as you go.
- Still to do afterwards: finish the audit for the uncovered sets (smaller batches, one set at a time), and the animation/audio timing
  audit (recipe vs. sfx clip length/hit offset), which produced nothing usable.

## Totals

- high / choice: 1
- high / data: 1
- high / effect: 35
- medium / anim: 3
- medium / choice: 3
- medium / cpu: 60
- medium / effect: 37
- low / anim: 3
- low / choice: 10
- low / cpu: 8
- low / data: 1
- low / effect: 22
- **Total unique findings: 184**


## HIGH severity

### 1. [x] base1-27 Farfetch'd — Leek Slap  (effect) [OPUS]
- **Done:** clear_all_statuses now keeps 'while_in_play' disabled attacks (only leaving play clears them).
- **Problem:** Leek Slap's 'while_in_play' lock is wiped whenever Farfetch'd leaves the Active spot (retreat, Switch, Whirlwind, Scoop-Up-less bench moves), so it can be used again after a retreat. Card text: 'even putting Farfetch'd on the Bench won't let you use it again'.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:11179-11185 (clear_all_statuses) erases every disabled_attacks entry that isn't 'entire_game'; clear_all_statuses is called on retreat at Main_Match_Core_Gameplay_Script.gd:11969 and by every switch helper. Lock is set at Attack_Effects.gd:1768 as 'while_in_play'.
- **Proposed fix:** In clear_all_statuses (Main ~11179) only erase entries whose value is not in ['entire_game','while_in_play'] (leave the leaving-play cleanup at Main ~8100 and Card_Ops.reset_returned_pokemon, which correctly drop 'while_in_play').
- **Files:** Main_Match_Core_Gameplay_Script.gd

### 2. [x] base5-46 Dark Wartortle — Mirror Shell  (effect) [OPUS]
- **Done:** mirror_shell_active cleared in clear_defensive_statuses (end of the opponent's turn) and in clear_all_statuses (benched).
- **Problem:** Mirror Shell lasts only 'during your opponent's next turn', but mirror_shell_active is cleared ONLY when it triggers. If Dark Wartortle isn't damaged that turn the shield stays on forever (even after retreating/benching and turns later) and reflects the next damage whenever it comes.
- **Evidence:** Attack_Effects.gd:4819 sets mirror_shell_active; only other writes are check_mirror_shell:5080 (on trigger). grep finds no expiry in clear_defensive_statuses (Main_Match_Core_Gameplay_Script.gd:8658) or end-of-turn code.
- **Proposed fix:** In clear_defensive_statuses (Main:8658) also reset pokemon.mirror_shell_active = false (it is called for the Active at the end of the opponent's turn, lines 8411/8437), and reset it in the bench/switch cleanup (wherever has_no_damage/is_invincible are cleared on retreat, e.g. Main:11143) so retreating ends it too.
- **Files:** Main_Match_Core_Gameplay_Script.gd, Attack_Effects.gd

### 3. [x] basep-1 Pikachu — Growl  (effect) [OPUS]
- **Done:** 'growl' lambda branches on 'after applying weakness and resistance': basep-1 uses the after-W/R, source-gated damage_reduction_next_turn (Pounce path); neo1 keeps neo_growl.
- **Problem:** basep-1 Growl text says the damage is reduced by 10 AFTER applying Weakness and Resistance, but the name resolves to the neo1 handler which reduces BEFORE W/R (neo_growl effect read in calculate_final_damage's pre-W/R block). Vs a Pokemon weak to the attacker, e.g. 30x2: card = 50, code = 40.
- **Evidence:** Attack_Effects.gd:9348 (neo1 'growl' registration, last writer) -> execute_neo1_growl:10378 sets neo_growl; Main_Match_Core_Gameplay_Script.gd:10140-10144 subtracts it before W/R
- **Proposed fix:** In the neo1 'growl' lambda (Attack_Effects.gd:9348) branch on text: if 'after applying weakness and resistance' in text, set a separate effect (e.g. 'basep_growl' {source, amount:10}, end_of_opponent_turn) on the attacker and subtract it in calculate_final_damage AFTER W/R (next to the Defender/Minimize after-W/R reductions), still gated on source == attacker instance id; otherwise keep execute_neo1_growl.
- **Files:** Attack_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 4. [x] basep-34 Entei — Protective Flame  (effect) [OPUS]
- **Done:** Protective Flame now sets a 'basep_protective_flame' end_of_opponent_turn effect, read only while benched via Attack_Effects._protective_flame_benched (is_protected_from_effects + Card_Ops.apply_bench_damage).
- **Problem:** Protective Flame sets is_invincible = true on every Benched Pokemon, but is_invincible is only ever cleared by clear_defensive_statuses for the ACTIVE Pokemon (end of turn). Benched Pokemon therefore stay immune to all attack effects/damage indefinitely, not just during the opponent's next turn.
- **Evidence:** Attack_Effects.gd:8939-8950 execute_protective_flame loops own_bench setting bp.is_invincible; clear_defensive_statuses is called only at Main_Match_Core_Gameplay_Script.gd:8411/8437 with the Active.
- **Proposed fix:** Use a timed effect instead: bp.set_effect('basep_protective_flame', 'end_of_opponent_turn') (or the side-wide flag the bench-damage path already honours, e.g. a 'bench_protected_until' turn number checked in card_ops.apply_bench_damage and in is_protected_from_effects for Benched Pokemon only). If keeping is_invincible, clear it for every Pokemon on that side's bench at the end of the opponent's next turn (in the same place clear_defensive_statuses is called) and when a protected Pokemon becomes Active.
- **Files:** Attack_Effects.gd, Main_Match_Core_Gameplay_Script.gd, Card_Ops.gd

### 5. [x] ecard1-1 Alakazam — Psymimic  (effect) [OPUS]
- **Done:** Psymimic sets attacked_this_turn + opponent_turn_force_end; CPU only uses it in the final power pass; cpu_phase_attack returns if the CPU already attacked.
- **Problem:** CPU Psymimic attacks during the power phase (Phase 0 of cpu_turn_orchestrator) and then the CPU turn continues: it plays Trainers, attaches Energy, retreats and finally runs cpu_phase_attack and attacks AGAIN. _attack_finish only sets opponent_attacked_this_turn, which neither the orchestrator nor cpu_phase_attack checks.
- **Evidence:** Powers_And_Bodies_Effects.gd:9294-9325 (cpu_phase_ecard1_powers calls power_ecard1_psymimic -> Attack_Effects.execute_copied_attack -> dispatch_attack -> _attack_finish:501-519, which for is_opponent only sets main.opponent_attacked_this_turn); CPU_AI.gd:147-159 continues after cpu_phase_activate_powers unless opponent_turn_force_end; CPU_AI.gd:3329 cpu_phase_attack has no opponent_attacked_this_turn guard.
- **Proposed fix:** In power_ecard1_psymimic, after execute_copied_attack returns true for the CPU, set main.opponent_turn_force_end = true (the orchestrator then ends the turn). Also only consider Psymimic in cpu_phase_ecard1_powers when cpu_final_power_check is true (Phase 7c) so Trainers/Energy/retreat happen BEFORE the copied attack; and add a guard at the top of cpu_phase_attack: if main.opponent_attacked_this_turn: return.
- **Files:** Powers_And_Bodies_Effects.gd, CPU_AI.gd

### 6. [x] ecard1-1 Alakazam — Psymimic  (effect) [OPUS]
- **Done:** Psymimic refuses on turn 1 / after an attack / under a can't-attack lock, filters unusable attacks, and runs begin_attack + run_attack_prechecks (failed precheck ends the turn via _attack_finish).
- **Problem:** Psymimic replaces Alakazam's attack but skips all attack legality: it can be used on turn 1 by the first player (no turn_number check), and it never calls begin_attack / run_attack_prechecks, so Leer/Tail Wag/Intimidate, 'can't attack' effects (cant_attack_next_turn, Freeze, Giant Wave-style locks), Smokescreen etc. are ignored. It also has no check that Alakazam hasn't already attacked this turn.
- **Evidence:** Powers_And_Bodies_Effects.gd:8972-9020 power_ecard1_psymimic goes straight to attack_effects.execute_copied_attack (Attack_Effects.gd:15727) which calls dispatch_attack without begin_attack/run_attack_prechecks (Attack_Effects.gd:538, 661). Contrast CPU_AI.gd:3338 turn_number<=1 guard for normal attacks.
- **Proposed fix:** At the top of power_ecard1_psymimic (after the status/once-per-turn checks) refuse when main.turn_number <= 1 for the first player, when (opponent_attacked_this_turn/player_attacked_this_turn) is already true, or main.is_attack_disabled / attack_unusable_reason says Alakazam can't attack. Before execute_copied_attack call attack_effects.begin_attack(chosen_attack, alakazam, opp_active, is_opponent) and `if await attack_effects.run_attack_prechecks(alakazam, opp_active, is_opponent): (finish turn as a failed attack via _attack_finish(false,0,...)) return`. Mirror the same gates in the CPU trigger at :9294.
- **Files:** Powers_And_Bodies_Effects.gd, Attack_Effects.gd

### 7. [x] ecard2-H17 Muk — Burning Sludge  (effect) [OPUS]
- **Done:** Burning Sludge deals parse_attack_base_damage (10) first, then the flips (skipped if the Defender was KO'd).
- **Problem:** Printed 10 damage is never dealt; only the Poison+Burn coin effect runs.
- **Evidence:** Attack_Effects.gd:16559 registration -> execute_ecard2_burning_sludge (17394-17415) has no gym1_hit_active call; _attack_finish(false, 0,...). Card damage = "10".
- **Proposed fix:** In execute_ecard2_burning_sludge, after the confusion/blind checks call `await gym1_hit_active(attacker, defender, is_opponent, 10)` (or parse_attack_base_damage passed in) and check_all_knockouts; skip the status if not _ko_alive(defender); registration -> _attack_finish(true, 10, ...).
- **Files:** Attack_Effects.gd

### 8. [x] ecard2-H31 Vileplume — Addictive Pollen  (effect) [OPUS]
- **Done:** Addictive Pollen deals the printed 40 before the Supporter-lock flip; finish passes the real damage.
- **Problem:** Printed 40 damage is never dealt. Handler only flips for the Supporter lock and _attack_finish is called with is_damage=false, 0.
- **Evidence:** Attack_Effects.gd:16555 registration calls execute_ecard2_addictive_pollen(a, opp) then _attack_finish(false, 0,...); execute_ecard2_addictive_pollen (17301-17316) never calls gym1_hit_active. Card data damage = "40".
- **Proposed fix:** Change signature to execute_ecard2_addictive_pollen(attacker, defender, is_opponent, base) and call `await gym1_hit_active(attacker, defender, is_opponent, base)` + check_all_knockouts before the coin flip; registration: var b=parse_attack_base_damage(atk); pass d,b; _attack_finish(true, b, ...).
- **Files:** Attack_Effects.gd

### 9. [x] ecard2-H31 Vileplume — Poison Scent  (effect) [OPUS]
- **Done:** New _attack_dispatch['poison scent'] (execute_ecard2_poison_scent): Poisoned always, heads Confused / tails Asleep, via card_ops.apply_status.
- **Problem:** Tails should make the Defending Pokémon Poisoned AND Asleep; the generic parser only produces Asleep on tails (Poisoned is attached only to heads), so tails never poisons.
- **Evidence:** parse_card_text_effects output for ecard2-H31 Poison Scent: [{flip:tails,Asleep},{flip:heads,Poisoned},{flip:heads,Confused}] — no tails Poisoned. Attack is undispatched (no 'poison scent' key in _attack_dispatch).
- **Proposed fix:** Register _attack_dispatch['poison scent'] (or an _r3_wrap on text 'if tails, the defending pokémon is now poisoned and asleep'): flip once; apply Poisoned + (heads ? Confused : Asleep) via card_ops.apply_status(defender,..., not opp) respecting is_protected_from_effects; finish with _attack_finish(false,0,...). Alternatively teach parse_card_text_effects to split 'X and Y' status lists per heads/tails clause.
- **Files:** Attack_Effects.gd

### 10. [x] ecard3-107 Swinub — Freezing Breath  (effect) [OPUS]
- **Done:** Freezing Breath takes parse_attack_base_damage; 0 (Swinub, ex5 Spheal) skips the damage step and finishes as non-damaging.
- **Problem:** Swinub's Freezing Breath has no printed damage (status only) but routes to the neo4 handler that always deals 10 damage.
- **Evidence:** Attack_Effects.gd:13151 / 14787 — _neo4_deal(attacker, defender, 10, ...) unconditionally.
- **Proposed fix:** Same fix as ecard3-H22: pass parse_attack_base_damage(atk) (0 here) into execute_neo4_freezing_breath and skip the damage step when it is 0; _attack_finish(false,0,...) for 0.
- **Files:** Attack_Effects.gd

### 11. [x] ecard3-H22 Piloswine — Freezing Breath  (effect) [OPUS]
- **Done:** Same change: Piloswine's printed 20 now used (Dewgong keeps 10).
- **Problem:** Freezing Breath resolves to the neo4 handler which hard-codes 10 damage; this Piloswine's printed damage is 20, so it always does 10.
- **Evidence:** Attack_Effects.gd:13151 registration (_attack_finish(true, 10,...)) -> execute_neo4_freezing_breath (14787) calls _neo4_deal(attacker, defender, 10, ...). No r3/r4 wrap for 'freezing breath'.
- **Proposed fix:** Register 'freezing breath' as func(atk,a,d,opp): var b=parse_attack_base_damage(atk); await execute_neo4_freezing_breath(a,d,opp,b); await _attack_finish(b>0,b,...) and give execute_neo4_freezing_breath a base_damage param used in place of the literal 10 (skip the damage step when b==0). Also update the CPU estimator if it hard-codes 10.
- **Files:** Attack_Effects.gd

### 12. [x] ex2-80 Slakoth — Lazy Punch  (effect) [OPUS]
- **Done:** Lazy Punch deals the printed 10 before the lock (lock skipped if Slakoth was KO'd).
- **Problem:** Lazy Punch is printed 10 damage, but the handler only disables Slakoth's attacks and never deals damage; _attack_finish is called with is_damage=false, 0.
- **Evidence:** Attack_Effects.gd:19054 — `_attack_dispatch["lazy punch"] = func(...): await execute_ex2_lazy_punch(a, opp); await _attack_finish(false, 0, ...)`; execute_ex2_lazy_punch (19953) has no hit
- **Proposed fix:** Lambda: `var b = parse_attack_base_damage(atk)`; in execute_ex2_lazy_punch call `await gym1_hit_active(attacker, defender, is_opponent, b)` (pass d and b) before setting disabled_attacks, then check_all_knockouts; finish with `_attack_finish(b > 0, b, ...)`. Skip the lock if Slakoth was KO'd (_ko_alive).
- **Files:** Attack_Effects.gd

### 13. [x] ex2-88 Rare Candy — Rare Candy  (effect) [OPUS]
- **Done:** Rare Candy accepts a Stage 1 OR a Stage 2 whose line starts at the Basic (_basic_matches_stage2); CPU ranks Stage 2 jumps first. Shared by ex9/ex13/pop5. CPU scorer already required a Stage 2.
- **Problem:** Rare Candy can't skip a Stage. The effect only accepts hand cards where main.can_evolve_from(h, basic) is true, i.e. a Stage 1 whose evolvesFrom is the Basic. A Stage 2 (evolvesFrom = the Stage 1 name) never matches, so Basic -> Stage 2, which is the card's main use, is impossible. The CPU scorer (_cpu_score_ex2_rare_candy -> _cpu_score_pokemon_breeder) only plays it when it holds a matching Stage 2, so every CPU Rare Candy is wasted with 'NO BASIC POKEMON HAS A MATCHING EVOLUTION'. The same function is shared by ex9-83, ex13-90 and pop5-7.
- **Evidence:** Trainer_Effects.gd:10464-10476 — `main.can_evolve_from(h, p)` for valid_basics and evos; CPU_AI.gd:5922-5926 scores on Stage 2 via _basic_matches_stage2
- **Proposed fix:** In effect_ex2_rare_candy, a hand card qualifies if `main.can_evolve_from(h, p)` (Stage 1) OR (`"Stage 2" in h.subtypes and _basic_matches_stage2(p, h)`), using the same helper Pokémon Breeder uses. Build both valid_basics and evos with that test. Make sure perform_evolution accepts the Stage 2 on a Basic (follow effect_pokemon_breeder, Trainer_Effects.gd:2382). Also give the CPU target pick a rank (prefer the Basic whose Stage 2 is best), not choose_card's default.
- **Files:** Trainer_Effects.gd, CPU_AI.gd

### 14. [x] ex3-34 Houndoom — Flamethrower  (data) [OPUS]
- **Done:** ex3-34 Flamethrower cost Fighting -> Fire in Card_Set_Data/ex3.json (seed file only holds ids/counts - no change needed).
- **Problem:** Flamethrower cost is stored as [Fighting, Colorless, Colorless]; the printed card (EX Dragon 34) is [Fire, Colorless, Colorless]. A Darkness Houndoom deck must run Fighting Energy to use it, and the attack's 'Discard a Fire Energy card' then usually has nothing to discard.
- **Evidence:** Card_Set_Data/ex3.json ex3-34 attacks[1].cost = ['Fighting','Colorless','Colorless']
- **Proposed fix:** Change ex3-34 Flamethrower cost to ['Fire','Colorless','Colorless'] (convertedEnergyCost 3 unchanged).
- **Files:** Card_Set_Data/ex3.json

### 15. [x] ex4-63 Team Magma's Houndour — Kick Away  (effect) [OPUS]
- **Done:** ex4 'kick away' now uses execute_ex5_gust_opp_choose with the printed damage (10, then the opponent switches; no switch if KO'd/protected).
- **Problem:** Kick Away has a 10 damage printed but the handler only forces the switch; the attack does 0 damage.
- **Evidence:** Attack_Effects.gd:21286 — ex4 registration calls execute_ex3_force_switch_defender(a, opp) then _attack_finish(false, 0,...). Later wraps (30649 ex14 uid-gated, 32716 r3 needle '(do the damage before switching the pokémon.)') don't match ex4-63 text, so it falls through to 21286.
- **Proposed fix:** In _register_ex4_attacks (21286) change kick away to: var b=parse_attack_base_damage(atk); if b>0: await gym1_hit_active(a,d,opp,b); if not main._should_bail(): await main.check_all_knockouts(); then if not bail and _ko_alive(defender) (or opponent still has a bench) await execute_ex3_force_switch_defender(a, opp); await _attack_finish(b>0, b, ...). Same shape as the ex14 branch at 30649.
- **Files:** Attack_Effects.gd

### 16. [x] ex4-69 Team Aqua Schemer — Supporter  (effect) [OPUS]
- **Done:** New _register_ex4_validations: Schemer can't be played without another Pokémon card in hand (CPU scorer already returned -100).
- **Problem:** Discarding 1 Pokémon from hand is the cost of the card, but it can be played with no Pokémon in hand and still draws 3 (free draw). No validator exists.
- **Evidence:** Trainer_Effects.gd:10687 effect_ex4_schemer — `if not pokes.is_empty():` skips the discard and still draws 3; no _validator_dispatch entry for ex4-69/ex4-70 (validators registered at Trainer_Effects.gd:427-438).
- **Proposed fix:** Add a validator (e.g. in a new _register_ex4_validations() called from _ensure_validator_dispatch_ready): for ex4-69/ex4-70 return "No Pokémon in hand to discard!" when the hand (excluding the Schemer itself) has no Pokémon card. Also make the CPU score (CPU_AI _cpu_score_draw_card mode 'discard1') return -100 when no Pokémon is in hand.
- **Files:** Trainer_Effects.gd, CPU_AI.gd

### 17. [x] ex4-70 Team Magma Schemer — Supporter  (effect) [OPUS]
- **Done:** Same validator registered for ex4-70.
- **Problem:** Same as Team Aqua Schemer: playable with no Pokémon in hand, then draws 3 without paying the discard.
- **Evidence:** Trainer_Effects.gd:10687 effect_ex4_schemer (shared); no validator for ex4-70.
- **Proposed fix:** Same validator as ex4-69 (hand must contain a Pokémon card).
- **Files:** Trainer_Effects.gd

### 18. [x] ex5-11 Metagross — Metal Juncture  (effect) [OPUS]
- **Done:** All 4 Metal Juncture filters now use main.is_typed_energy_card(e, 'Metal') (Special Metal Energy counts).
- **Problem:** Metal Juncture moves 'a Metal Energy card' but both the player and CPU paths only accept Energy with subtype 'Basic'. Every Metal Energy card in the game data (ex1-94, ex9-88, ecard1-159...) is a Special Energy, so the power can never move anything ('NO METAL ENERGY ON YOUR BENCH TO MOVE!') and the CPU plan is always empty.
- **Evidence:** Powers_And_Bodies_Effects.gd:13139 (CPU pool), :13149 and :13159 (player sources/pick), :13438 (cpu_phase_ex5_powers dry run) all require "Basic" in subtypes; Main.is_typed_energy_card (Main_Match_Core_Gameplay_Script.gd:11257) already treats Special 'Metal Energy' as a Metal Energy card
- **Proposed fix:** Replace the 4 filters `"Metal" in main.get_energy_provided_by_card(e) and "Basic" in e.metadata.get("subtypes", [])` with `main.is_typed_energy_card(e, "Metal")` (Metal Energy cards, basic or the Special 'Metal Energy'). Player path: when the chosen source has more than one Metal Energy card, any is fine (identical) - keep first.
- **Files:** Powers_And_Bodies_Effects.gd

### 19. [x] ex6-21 Dodrio — Retreat Aid  (effect) [OPUS]
- **Done:** Retreat Aid reads the ability text: ColorlessColorless = -2, 'excluding Pokémon-ex' skips ex/Baby, gated by is_power_blocked_by_status (Body-aware) in Main.get_retreat_cost and the (unused) Powers.get_retreat_cost_reduction.
- **Problem:** ex6 Dodrio's Poké-Body says 'you pay ColorlessColorless less to retreat your Active Pokémon (excluding Pokémon-ex and Baby Pokémon)'. The shared Retreat Aid code (written for the base-set Jungle Dodrio Power, -1) reduces only 1 per Dodrio and never excludes Pokémon-ex / Baby Pokémon. It is also gated by the Bench Dodrio's status (Bodies are not stopped by Special Conditions) and ignores Body locks.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:11392-11404 — `if _ability.get("name","") == "Retreat Aid": if bp.special_condition not in [...] and not bp.is_poisoned: cost = max(0, cost - 1)`; Powers_And_Bodies_Effects.gd:1300-1310 get_retreat_cost_reduction also +1 flat
- **Proposed fix:** In the Retreat Aid loop read the reduction from the ability text: n = 2 if 'colorlesscolorless less' in text.to_lower() else 1. If the text contains 'excluding pokémon-ex' skip when is_ex_pokemon(pokemon) or 'Baby' in pokemon subtypes. Gate with `not powers_and_bodies.is_power_blocked(bp)` (body-aware) instead of the raw status check. Mirror the same in get_retreat_cost_reduction (CPU/preview use).
- **Files:** Main_Match_Core_Gameplay_Script.gd, Powers_And_Bodies_Effects.gd

### 20. [x] ex6-72 Paras — Call for Family  (effect) [OPUS]
- **Done:** execute_call_for_pokemon skips non-Pokémon (basic Energy has subtype Basic) - fixes every Call for Family caller.
- **Problem:** Text 'Search your deck for up to 2 Basic Pokémon and put them onto your Bench'. _ex6_call_for_family finds no names and no type restriction, so execute_call_for_pokemon(..., [], '') accepts every deck card whose subtypes contain 'Basic' — basic Energy cards have subtypes ['Basic'] too, so a Basic Energy can be chosen (player) or picked by the CPU keep-value ranking and placed on the Bench as a Pokémon.
- **Evidence:** Attack_Effects.gd:3544-3557 — filter is only `if "Basic" not in subtypes: continue` with no supertype check; Card_Set_Data/base1.json Energy cards carry subtypes ['Basic']
- **Proposed fix:** In execute_call_for_pokemon (Attack_Effects.gd:3544) add `if card.metadata.get("supertype","") != "Pokémon": continue` before the subtype test (or use main.is_basic_pokemon(card)). This is shared by every Call for Family / Call for Friends caller, so it fixes all of them.
- **Files:** Attack_Effects.gd

### 21. [x] ex8-104 Sharpedo ex — Drag Off  (effect) [OPUS]
- **Done:** New _r3_wrap('drag off', 'before doing damage, you may switch 1 of your opponent's benched', r3_drag_off_optional) - covers ex8-104, ex7-103, ex10-18 (optional gust, damage always lands).
- **Problem:** Text 'Before doing damage, you MAY switch 1 of your opponent's Benched Pokemon with the Defending Pokemon. If you do, 20 to the new Defending' (20 to the Defending either way). Neither r3 needle matches this wording ('you may switch', not 'you may choose'), so it falls through ex14/ex12 wrappers to base execute_drag_off: the gust is MANDATORY (prompt_select_card cancel=false) and if the opponent has no Bench the attack does NO damage at all ('CAN'T USE DRAG OFF').
- **Evidence:** Attack_Effects.gd:32717-32718 r3 needles; :30659/:29223 uid-gated; :334 -> execute_drag_off :4664-4669 returns with 0 damage on empty bench, :4688 mandatory pick
- **Proposed fix:** In _register_r3_fixes add `_r3_wrap("drag off", "before doing damage, you may switch 1 of your opponent's benched", r3_drag_off_optional)` (execute_ex5_metal_reversal = optional gust, CPU gusts only when it gains, 20 always lands).
- **Files:** Attack_Effects.gd

### 22. [x] ex8-91 Space Center — Stadium effect  (effect) [OPUS]
- **Done:** body_lock_active now returns true for ex8_space_center_ignores_body(pokemon), so every Body gate (is_power_blocked / _by_status / is_body_blocked) honours Space Center.
- **Problem:** 'Ignore Poke-Bodies for all Basic Pokemon in play (excl. ex and owner-named)' is only spot-checked in 6 places (ex8_blocks_status, Sunbeam, Fluff, Exoskeleton, Dense, Mirror Coat). It is NOT in the shared body gate, so every other Basic Poke-Body keeps working under Space Center: ex8 Tropius Tropical Motion, Skarmory Metallic Lift, Lunatone Moonglow, Rayquaza Dragon Aura effect shield partly, plus every Basic body from other sets (damage-reduction hooks, retreat bodies, etc.).
- **Evidence:** Powers_And_Bodies_Effects.gd:525 body_lock_active has Ancient Wind + Dual Aura but no Space Center; :15307 is_ex8_tropical_motion_active, Main_Match_Core_Gameplay_Script.gd:11461/11507 retreat bodies use is_power_blocked only
- **Proposed fix:** In body_lock_active (Powers_And_Bodies_Effects.gd:525) add `if ex8_space_center_ignores_body(pokemon): return true` (body_only callers of is_power_blocked / is_power_blocked_by_status / is_body_blocked then all honour it). Make sure Basic-Pokemon body gates that only call has_ability (e.g. r4_attack_effect_shield Dragon Aura line, Attack_Effects.gd:~628) go through is_body_blocked too.
- **Files:** Powers_And_Bodies_Effects.gd, Attack_Effects.gd

### 23. [x] ex9-95 Medicham ex — Wise Aura (and every Poké-Power lock: Battle Frontier ex9-75, Lazy, Stench, Intimidating Ring...)  (effect) [OPUS]
- **Done:** is_power_usable calls is_power_blocked (status-exempt list for [Bear]/[Yield]/[Search]/[Tell]); activate_power refuses locked Poké-Powers for player and CPU (rules actions exempt).
- **Problem:** Player Poké-Power buttons ignore Wise Aura / Battle Frontier. is_power_usable (the single gate used by the board power rows and bench power buttons) never calls is_power_blocked, which is where Wise Aura (line ~437) and battle_frontier_disables (line ~405) live; activate_power only checks Mt. Moon, and ex9 power handlers (power_ex9_heal_dance, power_ex9_water_cyclone, power_ex8_form_change, power_ex2_baby_evolution, power_ex6_quick_search) only check is_power_blocked_by_status. So with Medicham ex Active the player can still use Gardevoir's Heal Dance, Pichu's Baby Evolution, Deoxys Form Change; with Battle Frontier in play the player can still use Pidgeot's Quick Search (Colorless Stage 2).
- **Evidence:** Powers_And_Bodies_Effects.gd:635-672 is_power_usable checks toxic gas, power_disabled, gaze, scare, is_power_blocked_by_status, mt_moon only; Main_Match_Core_Gameplay_Script.gd:2577 and :2892 use it; Powers_And_Bodies_Effects.gd:895 activate_power checks only mt_moon_blocks_power
- **Proposed fix:** In is_power_usable, after the Toxic Gas check add `if is_power_blocked(pokemon, ability_name in ["[Bear]","[Yield]","[Search]","[Tell]"]): return false` (works_through_status param for the status-exempt powers). Also add the same is_power_blocked guard at the top of activate_power (pokemon != null) so CPU paths are covered too.
- **Files:** Powers_And_Bodies_Effects.gd

### 24. [x] gym1-120 Vermilion City Gym — Stadium  (effect) [OPUS]
- **Done:** Vermilion flip records vermilion_lt_surge_attacker; the +10 applies only to that attacker vs current_defender while its attack is in progress (no consuming by estimates); self-damage gated to that attacker; new Main.vermilion_settle() at the start of inbetween_turn_checks pays leftover tails self-damage and clears everything.
- **Problem:** Tails: 'the attacking Pokemon does 10 damage to itself in addition to whatever its attack usually does' — the queued 10 self-damage (vermilion_lt_surge_self_damage_pending) is only applied inside display_and_apply_attack_damage, so an attack that deals no damage to the Defender (Charge, Fidget-style 0-damage attacks, Shadow Images dodge, Agility shield, Transparency) never pays it and the pending 10 then leaks onto the NEXT damaging attack by ANY Pokemon (including the opponent's). Same leak for heads: vermilion_lt_surge_bonus_damage stays at 10 until some later calculate_final_damage call with damage>0 consumes it (possibly the opponent's attack, a bench hit via hit_active_no_wr, or a CPU estimator calling calculate_final_damage).
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:11657-11698 sets the flags; consumed only at Main:9871-9880 (self-damage) and Main:10369-10372 / Attack_Effects.gd:3650-3653 (bonus); nothing clears them at end of attack.
- **Proposed fix:** Store the attacker id with the flags; in Attack_Effects.end_attack() (or _attack_finish + the generic path end in perform_attack/cpu_phase_attack) apply any still-pending Vermilion self-damage to that attacker (apply_self_damage_modifiers + KO check) and reset vermilion_lt_surge_bonus_damage=0. In calculate_final_damage only add the bonus when defending_pokemon is the current Defender and attacker_pokemon is the Vermilion attacker (attack_effects.current_attacker), never for dry-run/CPU estimate calls.
- **Files:** Main_Match_Core_Gameplay_Script.gd, Attack_Effects.gd

### 25. [x] gym1-13 Rocket's Scyther — Shadow Images  (effect) [OPUS]
- **Done:** clear_all_statuses clears dodge_active (Benched / evolved).
- **Problem:** Text: the effect 'lasts until Rocket's Scyther takes damage (or is Benched or is evolved)'. dodge_active is only cleared when damage gets through; retreating/switching to the Bench, evolving, or even leaving play (shuffle/return to hand) never clears it, so the dodge flip keeps protecting it later.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:9737-9746 is the only reset of dodge_active; clear_all_statuses (Main:11120, the 'leaves Active / evolves' reset) doesn't touch dodge_active.
- **Proposed fix:** In Main.clear_all_statuses() add `pokemon.dodge_active = false` (status icon refresh is already there via had_status; also set had_status=true when it was set).
- **Files:** Main_Match_Core_Gameplay_Script.gd

### 26. [x] gym2-8 Giovanni's Persian — Call the Boss  (effect) [OPUS]
- **Done:** _after_evolution triggers trigger_call_the_boss for a Pokémon with 'Call the Boss' (same on-evolve chain as Summon Minions etc.).
- **Problem:** Call the Boss never triggers in normal play. Giovanni's Persian is a Stage 1, so it is played from the hand by evolving Giovanni's Meowth, not by Benching it. The trigger is wired only into the bench-from-hand paths, and perform_evolution has no Call the Boss hook.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:7275-7277 (run_bench_from_hand_triggers) and CPU_AI.gd:5213-5214 (CPU bench placement) are the only callers of trigger_call_the_boss; perform_evolution (Main:8807) never calls it
- **Proposed fix:** Call `await powers_and_bodies.trigger_call_the_boss(evolved_card, is_opponent)` from perform_evolution after the evolution lands, but only when the Evolution card came from the hand (not Lunar Power, Emerge or other deck-evolve effects). Keep the bench-path calls for the rare case where it is benched from the hand. Also make the CPU search situational (it always searches now; that is fine but harmless)
- **Files:** Main_Match_Core_Gameplay_Script.gd, CPU_AI.gd, Powers_And_Bodies_Effects.gd

### 27. [x] neo1-11 Meganium — Wild Growth  (effect) [OPUS]
- **Done:** is_wild_growth_active(side_is_opp) scans only that side; CPU_AI unmet-energy count passes the card's side and uses get_effective_types.
- **Problem:** Wild Growth should only double Grass Energy on the Meganium OWNER's Grass Pokémon ('your Grass Pokémon'), but is_wild_growth_active() returns true if ANY Meganium with Wild Growth is in play on either side, so the opponent's Grass Pokémon also get double Grass.
- **Evidence:** Powers_And_Bodies_Effects.gd:5369-5378 is_wild_growth_active() scans both Actives and both Benches; CPU_AI.gd:693 get_unmet_energy_count (used for player AND CPU cost checks, Main:9678) calls it without a side
- **Proposed fix:** Change to is_wild_growth_active(side_is_opp: bool) scanning only main.card_ops.get_all_pokemon_in_play(side_is_opp); at CPU_AI.gd:693 pass main.match_effects.is_card_on_opponent_side(pokemon). Also use pokemon.get_effective_types() instead of metadata types.
- **Files:** Powers_And_Bodies_Effects.gd, CPU_AI.gd

### 28. [x] neo1-47 Quilava — Char  (effect) [OPUS]
- **Done:** Char flip moved from the owner's turn start to new Powers.process_char_counters_between_turns(), run after every turn's status checkup (both sides; tails = 2 counters via gym1_place_counters).
- **Problem:** Char counter flip happens only at the start of the Char-countered Pokémon's OWNER's turn (once per round), but the text says the opponent flips 'after every turn' (both players' turns). Damage from Char is therefore half as frequent as printed.
- **Evidence:** Powers_And_Bodies_Effects.gd:5483-5503 process_turn_start_tools_and_counters(is_opponent) only collects that side's Pokémon (all_poke = is_opponent side), called from Main:8241 (player turn start) and CPU_AI:120 (CPU turn start)
- **Proposed fix:** Move the Char block out of process_turn_start_tools_and_counters into the between-turns checkup (run once at the end of EVERY turn): iterate get_all_pokemon_in_play(true)+get_all_pokemon_in_play(false), and for each with has_char_counter flip (owner flips), tails = place 2 damage counters (use gym1_place_counters / a damage-counter helper so it animates), then check_all_knockouts. Remove the Char branch from the turn-start function.
- **Files:** Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 29. [x] neo2-8 Politoed — Frog Song / Doubleslap  (effect) [OPUS]
- **Done:** Politoed Doubleslap: Frog Song +40 is added after calculate_final_damage and only when that damage > 0 (0 heads = nothing); get_frog_song_bonus gates on has_ability('Frog Song'). Counting both sides is correct per card text.
- **Problem:** Frog Song's +40 is added to the base damage BEFORE Weakness/Resistance (so Weakness doubles it to +80) and is added even when Doubleslap gets 0 heads (0-heads Doubleslap does 40 damage). Text: bonus applies only 'whenever Politoed's attack damages the Defending Pokemon (after applying Weakness and Resistance)'. Also gated by card name ('Politoed' in name) instead of has_ability.
- **Evidence:** Attack_Effects.gd:11338-11351 execute_neo2_politoed_doubleslap: base_damage = heads*40; base_damage += frog_bonus; then calculate_final_damage(base_damage,...). Powers_And_Bodies_Effects.gd:5928 name check.
- **Proposed fix:** In execute_neo2_politoed_doubleslap: if heads == 0 -> message + return (no Frog Song). Otherwise compute result = calculate_final_damage(heads*40,...), fd = result.damage; if fd > 0 and frog_bonus > 0: fd += frog_bonus (add to the post-W/R figure, before apply_defender_no_damage_shield). In get_frog_song_bonus replace the name check with has_ability(attacker,'Frog Song').
- **Files:** Attack_Effects.gd, Powers_And_Bodies_Effects.gd

### 30. [x] neo3-18 Ho-oh — Rainbow Burn  (effect) [OPUS]
- **Done:** neo3 Rainbow Burn handler and its _r3_estimate use _ex10_distinct_basic_types (Special Energy skipped). Also fixes ex3-4 Flygon, which shares the handler.
- **Problem:** Text counts 'each type of BASIC Energy card attached'. Code counts every type provided by ANY attached Energy, so a Rainbow / Multi / special Energy that provides several types adds +10 per type (Rainbow Energy alone = up to +80).
- **Evidence:** Attack_Effects.gd:12041-12048 execute_neo3_rainbow_burn loops all attached_energies and get_energy_provided_by_card(e) without a Basic check.
- **Proposed fix:** Only count energies whose metadata.subtypes contains 'Basic' (skip Special Energy entirely); keep the Colorless exclusion. Check the CPU estimate at Attack_Effects.gd:1141 (_r3_estimate 'rainbow burn') uses the same rule.
- **Files:** Attack_Effects.gd

### 31. [x] neo4-109 Shining Mewtwo — Reflect Shield  (effect) [OPUS]
- **Done:** Reflect Shield resolved before damage in display_and_apply_attack_damage (owner flips; heads = no damage + 20 to the attacker); removed from check_neo4_counters; expires in clear_neo3_flags_end_of_turn and clear_all_statuses.
- **Problem:** Reflect Shield never prevents the damage: on heads it only deals 20 to the attacker after the damage has already landed (it can even fire after Mewtwo was KO'd by damage that should have been prevented). The flag also never expires: if Mewtwo is not damaged during the opponent's next turn, neo4_counter_flip_20 stays true indefinitely (survives benching too).
- **Evidence:** Attack_Effects.gd:15091 sets attacker.neo4_counter_flip_20 = true; the only reader is Powers_And_Bodies_Effects.gd:7681 check_neo4_counters, an _on_damage_hook (line 259) run from dispatch_on_damage AFTER damage is applied (Main_Match_Core_Gameplay_Script.gd ~9861). No other clearing (grep neo4_counter_flip_20).
- **Proposed fix:** Move the flip into the pre-damage path next to the Dodge check (Main_Match_Core_Gameplay_Script.gd ~9750 in display_and_apply_attack_damage): if defender.neo4_counter_flip_20 and final_damage > 0, the owner flips; heads -> floating 'REFLECT SHIELD', skip applying damage, then deal 20 to the attacker (no W/R) and check KOs; remove the 20-damage branch from check_neo4_counters. Expiry: add `p.neo4_counter_flip_20 = false` to the own-side loop in clear_neo3_flags_end_of_turn (Powers_And_Bodies_Effects.gd:6700-6703, beside neo4_prevent_high_damage) and to clear_all_statuses.
- **Files:** Main_Match_Core_Gameplay_Script.gd, Powers_And_Bodies_Effects.gd

### 32. [x] neo4-15 Light Togetic — Gift  (choice) [OPUS]
- **Done:** Gift: opponent's search is awaited and only automatic for the CPU side; player search is cancelable (you may); CPU takes cpu_pick_best_keep and shows it.
- **Problem:** When the CPU plays Light Togetic, the PLAYER's search is automatic: they get the first Pokemon Tool in their deck with no prompt and no way to decline ('your opponent MAY search'). The first call is not awaited, so its flight runs concurrently with the second search. CPU's own pick is tools[0] and isn't shown to the player.
- **Evidence:** Powers_And_Bodies_Effects.gd:7510 `_neo4_search_tool_to_hand(not is_opponent, true)` (auto=true for the non-owner regardless of side, no await); 7527 chosen = tools[0] when auto.
- **Proposed fix:** In trigger_neo4_gift: `await _neo4_search_tool_to_hand(not is_opponent, not is_opponent)` and `await _neo4_search_tool_to_hand(is_opponent, is_opponent)` (auto only for the CPU side). In the auto branch pick main.cpu_ai.cpu_pick_best_keep(tools) and show it with card_ops.show_cards([chosen], 'GIFT', ...).
- **Files:** Powers_And_Bodies_Effects.gd

### 33. [x] neo4-87 Unown [S] — Hidden Power  (effect) [OPUS]
- **Done:** execute_neo2_hidden_power takes the printed base (parse_attack_base_damage, fallback 10); dispatch finishes with it.
- **Problem:** Unown [S] Hidden Power is printed 20 damage (cost Psychic+Colorless) but always does 10. Same for neo4-88 Unown [T]. The shared handler hardcodes the base to 10.
- **Evidence:** Attack_Effects.gd:11315 execute_neo2_hidden_power: `var total = 10 + bonus`; dispatch Attack_Effects.gd:10502 also passes 10 to _attack_finish. The 26882 wrapper only reroutes ex10 uids.
- **Proposed fix:** Pass parse_attack_base_damage(atk) into execute_neo2_hidden_power(a, d, opp, base) and use `var total = base + bonus`; change the 10502 lambda to `var b = parse_attack_base_damage(atk); await execute_neo2_hidden_power(a, d, opp, b); await _attack_finish(true, b, ...)`. Make CPU damage estimates read the printed damage too.
- **Files:** Attack_Effects.gd

### 34. [x] neo4-88 Unown [T] — Hidden Power  (effect) [OPUS]
- **Done:** Same fix - Unown [T] now 20.
- **Problem:** Printed 20 damage, engine deals 10 (same hardcoded base as Unown [S]).
- **Evidence:** Attack_Effects.gd:11315 `var total = 10 + bonus`.
- **Proposed fix:** Same fix as neo4-87: use parse_attack_base_damage(atk) as the Hidden Power base.
- **Files:** Attack_Effects.gd

### 35. [x] neo4-89 Unown [V] — [Vanish]  (effect) [OPUS]
- **Done:** [Vanish]: _r4_power_may yes/no before the flip; CPU only uses it on a damaged Unown (most damage, least Energy, Benched preferred); reset_returned_pokemon + handle_post_knockout when the Active was returned.
- **Problem:** If the returned Unown is the Active Pokemon, the Active spot is set to null and no new Active is promoted (empty Active / soft-lock risk). The CPU returns unowns[0] (often its Active) rather than a sensible pick, and the player isn't asked whether to use this 'you may' power.
- **Evidence:** Powers_And_Bodies_Effects.gd:7613-7615 sets *_active_pokemon = null with no promotion; 7598 `var chosen = unowns[0]` for the CPU; no yes/no before the flip at 7580.
- **Proposed fix:** After returning an Active Unown call `await main.handle_post_knockout(is_opponent)` (as Bubble Jump does, Attack_Effects.gd:13602). Player: ask with gym1_prompt_yes_no / _r4_power_may before flipping. CPU: pick the most damaged Unown with the least Energy, prefer Benched ones, skip if none is damaged.
- **Files:** Powers_And_Bodies_Effects.gd

### 36. [x] pop1-12 Minun — Spark  (effect) [OPUS]
- **Done:** ex5 'spark' handler always uses the printed damage for the Defender (pop1-12 / ex5-56 now hit the Active for 10 + 10 to 2 Benched).
- **Problem:** Card has printed damage 10 (to the Defending Pokemon) plus 10 to 2 chosen Benched Pokemon, but the resolved handler treats it as Bench-only and never damages the Active. (Same bug hits ex5-56 Chinchou, identical text/damage.)
- **Evidence:** Attack_Effects.gd:22180-22185 ex5 'spark' override: text contains "benched pokémon. this attack does" and no "defending" -> execute_bench_choose_spread(a, d, opp, 0, 2, 10, false) and _attack_finish(false, 0); damage field '10' ignored
- **Proposed fix:** In the ex5 'spark' handler use b = parse_attack_base_damage(atk) for the Active in that branch too: execute_bench_choose_spread(a, d, opp, b, 2, 10, false) then _attack_finish(b > 0, b, ...). (Only a Spark whose damage field is empty should be Bench-only.)
- **Files:** Attack_Effects.gd

### 37. [x] pop2-6 Venusaur — Wide Solarbeam  (effect) [OPUS]
- **Done:** pop 'wide solarbeam': printed 20 to the Defender plus 'N damage to 2' Benched; finishes as damaging.
- **Problem:** Printed damage is 20 (to the Defending Pokemon) plus 20 to 2 Benched Pokemon; the pop override does Bench damage only and skips the 20 to the Active.
- **Evidence:** Attack_Effects.gd:32276-32281 pop 'wide solarbeam': execute_bench_choose_spread(a, d, opp, 0, 2, b, false); _attack_finish(false, 0) — Active gets 0; comment says '(no Active damage)'
- **Proposed fix:** Call execute_bench_choose_spread(a, d, opp, b, 2, b, false) and _attack_finish(true, b, ...) (Active damage = printed damage field, bench amount read from 'does N damage to 2').
- **Files:** Attack_Effects.gd


## MEDIUM severity

### 38. [x] base3-8 Hypno — Prophecy  (cpu) [OPUS]
- **Done:** CPU Prophecy now compares the gain of reordering its own top 3 (best card up) vs the player's (best card off the top) by cpu_rank_keep_value and calls r3_reorder_top on the better deck. CPU_AI utility for Prophecy was already a flat 3.0 (never beats a damaging attack) - left.
- **Problem:** CPU Prophecy only ever looks at its OWN deck and only reorders when its Active lacks Energy (Energy to the top; otherwise leaves the order as-is). It never uses the 'either player's deck' option to bury the player's best cards, and the order ignores what it actually needs.
- **Evidence:** Attack_Effects.gd:3866-3898 execute_prophecy CPU branch
- **Proposed fix:** Replace the CPU branch with r3_reorder_top (Attack_Effects.gd:32612), choosing the deck by value: e.g. compare cpu_rank_keep_value of the top 3 of each deck; if the player's top 3 contains high-value cards (or the CPU's own deck is <3), call r3_reorder_top(false, 3, true, ...) to put the player's worst on top, else r3_reorder_top(true, 3, true, ...). Also in CPU_AI (utility value near CPU_AI.gd:8436) only value Prophecy when no damaging attack is available.
- **Files:** Attack_Effects.gd, CPU_AI.gd

### 39. [x] base5-34 Dark Electrode — Energy Bomb  (anim) [EASY]
- **Done:** Energy Bomb captures each Energy's rect before detaching and fly_attach-es it to its new Benched holder in both branches.
- **Problem:** When Energy is moved from Dark Electrode to Benched Pokemon (both player and CPU branches) the Energy is appended to the bench Pokemon with no card flight — cards teleport. (The no-bench discard branch does fly.)
- **Evidence:** Attack_Effects.gd:4498-4521 execute_energy_bomb: dest.attached_energies.append(e) / best_target.attached_energies.append(e) with no fly_card / fly_attach
- **Proposed fix:** Capture the rect before clearing (main.card_ops.capture_rect(e, 'attached', is_opponent)) and after choosing the destination call main.card_ops.fly_attach (or fly_card(e, 'attached', 'attached', is_opponent, -1, rect) targeting dest) before appending, for both branches.
- **Files:** Attack_Effects.gd

### 40. [x] basep-15 Cool Porygon — Texture Magic  (effect) [EASY]
- **Done:** CPU Texture Magic: Resistance = cpu_dominant_attack_type(false), Weakness only if the Defender has one, = cpu_dominant_attack_type(true).
- **Problem:** CPU branch always sets the Defending Pokemon's Weakness even when it has NO Weakness (text: 'If the Defending Pokemon has a Weakness'), and picks the new Weakness as Cool Porygon's own type ('Colorless' -> hard-coded 'Lightning') rather than a type the CPU side actually attacks with. Resistance is set to the player's Active type (fine).
- **Evidence:** Attack_Effects.gd:8796-8801 execute_texture_magic CPU branch
- **Proposed fix:** Gate the weakness change on defender.metadata.weaknesses.size() > 0, and choose the type with main.cpu_ai.cpu_dominant_attack_type(true, types) (same helper Conversion 1 uses at Attack_Effects.gd:2157); resistance with cpu_dominant_attack_type(false, types).
- **Files:** Attack_Effects.gd

### 41. [x] basep-21 Moltres — Hyper Flame  (effect) [EASY]
- **Done:** Hyper Flame flips first; heads needs a Fire Energy card (is_typed_energy_card, picked via r4_pick_own_energy) else no damage; then 60. Dispatcher passes the real damage to _attack_finish.
- **Problem:** Damage (60) is dealt BEFORE the flip, so on heads with no Fire Energy attached (only other Energy) the attack still does 60 although the text says 'If you can't discard Energy cards, this attack does nothing'. On heads the Fire Energy is also auto-picked (fire_e[0]) with no player choice when several differ.
- **Evidence:** Attack_Effects.gd:8849-8851 gym1_hit_active(60) before flip; 8333-8341 heads takes fire_e[0], 'NO FIRE ENERGY' still keeps the damage. Dispatcher at Attack_Effects.gd:102-109 only checks 'no Energy at all'.
- **Proposed fix:** In execute_hyper_flame flip first; on heads require a Fire Energy (if none: message + return 0 damage); pick it with r4_pick_own_energy(attacker, fire_e, is_opponent, 'HYPER FLAME: DISCARD A FIRE ENERGY'); on tails discard all. Then call gym1_hit_active(60). Have the dispatcher pass the real damage to _attack_finish.
- **Files:** Attack_Effects.gd

### 42. [x] basep-32 Smeargle — Paint  (cpu) [OPUS]
- **Done:** CPU Paint picks the type its own Pokémon are least weak to / most resist (_cpu_paint_type); CPU_AI only rates Paint +15 when the foe hits one of its Weaknesses (else -10).
- **Problem:** CPU picks the Defending Pokemon's own Weakness type as its new type, which has no tactical meaning. Paint changes the Defender's TYPE, which matters for which of the CPU's Pokemon it hits for Weakness (and type-based effects). The CPU should pick a type none of its own Pokemon are weak to / that its Pokemon resist.
- **Evidence:** Attack_Effects.gd:8915-8919 execute_paint CPU branch
- **Proposed fix:** For each type in `types`, score = -(count of CPU Pokemon in play weak to it)*2 + (count resisting it); pick the best. Also check CPU_AI utility value for 'paint' (CPU_AI.gd:3844) only rates it when the player's Active would otherwise hit a CPU Pokemon's Weakness.
- **Files:** Attack_Effects.gd, CPU_AI.gd

### 43. [x] basep-44 Magmar — Burning Fire  (cpu) [OPUS]
- **Done:** CPU Burning Fire discards only the fewest Fire Energy that KO (Bench first, Active last), none if no KO is reachable.
- **Problem:** CPU always discards EVERY Fire Energy on ALL its Pokemon for +10 each, even when far fewer would KO or when that strips its whole board.
- **Evidence:** Attack_Effects.gd:9113-9122 execute_burning_fire CPU branch
- **Proposed fix:** CPU: compute needed = ceil((defender HP - W/R-adjusted 10) / adjusted 10 per Energy); discard only that many (prefer Energy on Benched Pokemon that don't need Fire, via cpu_own_energy_discard_order), or 0 if no KO is reachable and the Energy is needed elsewhere.
- **Files:** Attack_Effects.gd

### 44. [x] basep-46 Electabuzz — Lightning Bolt  (effect) [EASY]
- **Done:** Lightning Bolt hits the marked Pokémon through gym1_hit_active (Active) or calculate_final_damage + card_ops.apply_bench_damage (Bench); the marker is no longer removed.
- **Problem:** The 20 damage to the marked Pokemon is a raw HP subtraction: no on-damage hooks (dispatch_on_damage), no bench-protection path (card_ops.apply_bench_damage / Defender / Protective Flame), no damage label/announce through the shared hit helpers. The marker is also removed after one Lightning Bolt, which the card text doesn't say (markers stay; only 1 per Pokemon).
- **Evidence:** Attack_Effects.gd:9184-9192 execute_lightning_bolt: marked.current_hp -= result['damage']; marked.lightning_rod_marked = false
- **Proposed fix:** If marked is the Active use gym1_hit_active(attacker, marked, is_opponent, 20); if Benched use a W/R-applying bench hit (calculate_final_damage then card_ops.apply_bench_damage with the result, or gym1_hit_raw with the W/R-modified amount). Remove the line clearing lightning_rod_marked (keep the 1-marker rule in execute_lightning_rod).
- **Files:** Attack_Effects.gd

### 45. [x] ecard1-13 Gengar — Chaos Move  (cpu) [OPUS]
- **Done:** New _cpu_chaos_move_pair(): own damaged -> player Pokémon (KO worth most), or player->player only for a KO; the CPU phase decides before announcing and the power uses the pair.
- **Problem:** CPU picks source = sources[0] and dest = first other Pokémon in play — all_pokemon lists the PLAYER's side first, so the CPU typically moves a damage counter OFF the player's damaged Active onto the player's own next Pokémon or, when only its own are damaged, onto the player's Active by accident; it can also move a counter from its own Pokémon onto its own. No board reasoning (KO chance, own heal).
- **Evidence:** Powers_And_Bodies_Effects.gd:8519-8522 `source = sources[0]` / `dest = dests[0]`; trigger at :9206-9212 only checks prizes <= 3 and announces before deciding.
- **Proposed fix:** CPU branch: build candidate pairs (source in own damaged Pokémon preferred, else any player Pokémon is NOT a valid source unless moving to another player Pokémon to set up a KO); dest = player Pokémon where current_hp <= 10 (KO) first, else the player's Active/highest-threat Pokémon. Only announce and use when a pair with positive value exists (own source healed or player KO); else skip. Compute the pair in cpu_phase_ecard1_powers before announce_cpu_power and pass it into the power (e.g. optional params).
- **Files:** Powers_And_Bodies_Effects.gd

### 46. [x] ecard1-2 Ampharos — Energy Connect  (cpu) [OPUS]
- **Done:** CPU Energy Connect uses the r4 planner (only moves that bring an Active attack closer, sparing Bench needs), all helpful moves with flights; the phase dry-runs before announcing.
- **Problem:** CPU announces Energy Connect every time the power phase runs (3x per turn) whenever Ampharos is in play, even when no Benched Pokémon has basic Energy or the Active doesn't need any; it then moves 1 Energy to the Active regardless of whether the Active's attacks need it (drains bench attackers pointlessly). Violates 'CPU decides before announce_cpu_power'.
- **Evidence:** Powers_And_Bodies_Effects.gd:9191-9196 (no condition before announce_cpu_power); :8562-8574 moves basics[0] with no need check; :8589 one move per call.
- **Proposed fix:** In cpu_phase_ecard1_powers compute: sources with basic Energy exist AND the Active has an attack with get_unmet_energy_count > 0 that a moved Energy would reduce (or retreat-cost help). Only then announce. Inside the CPU branch pick the energy whose type the Active's best attack lacks; loop while it still reduces unmet cost instead of stopping after 1.
- **Files:** Powers_And_Bodies_Effects.gd

### 47. [x] ecard1-28 Typhlosion — Heat Up  (cpu) [OPUS]
- **Done:** Heat Up CPU target = cpu_pick_benefit_recipient(own_bench, 'energy', Fire Energy).
- **Problem:** CPU always attaches the searched Fire Energy to own_bench[0] instead of the Benched Pokémon that needs Fire most.
- **Evidence:** Powers_And_Bodies_Effects.gd:8675-8676 `target = own_bench[0]`
- **Proposed fix:** Use main.cpu_ai.cpu_pick_benefit_recipient(own_bench, "energy", energy) (pick the energy first, then the target) with fallback own_bench[0].
- **Files:** Powers_And_Bodies_Effects.gd

### 48. [x] ecard1-30 Venusaur — Harvest Bounty  (effect) [EASY]
- **Done:** New player/opponent_energy_attached_to (set by the normal attach paths, reset between turns); Harvest Bounty requires it to be the Active, accepts any Energy card (Special runs apply_on_attach_effects); CPU picks by cpu_energy_need_value and only fires after attaching to the Active.
- **Problem:** Text: only usable when you attach an Energy card to your Active Pokémon as part of your turn, and the extra may be any Energy card. Code lets you attach an extra basic Energy to the Active at any time, without having attached one to the Active this turn, and refuses Special Energy.
- **Evidence:** Powers_And_Bodies_Effects.gd:8594-8631 — no check of the normal attach (e.g. player_energy_played_this_turn / target), basics filter at :8607 excludes Special Energy.
- **Proposed fix:** Require that this turn's normal Energy attachment went to the current Active (track e.g. main.<side>_energy_attached_to_active_this_turn set in the manual attach path, or check player/opponent_energy_played_this_turn plus the target); otherwise show 'ATTACH AN ENERGY TO YOUR ACTIVE FIRST'. Allow any Energy card from hand (drop the Special exclusion, run normal special-energy attach hooks). CPU trigger :9182 should run only after cpu_phase_energy_attachment attached to the Active (i.e. in the final power check).
- **Files:** Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 49. [x] ecard2-48 Furret — Scavenger Hunt  (cpu) [OPUS]
- **Done:** cpu_get_discard_priority_ecard2 sorts by cpu_rank_keep_value (valid ordering, junk first); Scavenger Hunt CPU gate _cpu_scavenger_hunt_worth (deck has a needed Energy, hand lacks it, 2 junk cards); fetch = highest cpu_energy_need_value.
- **Problem:** CPU uses it whenever hand>=2 and its put-back helper sorts ENERGY cards first, so it shuffles 2 cards (often Energy) back to fetch 1 Energy — net card loss every turn; no check that the deck even has an Energy; fetched Energy is always energies[0] regardless of need. The sort_custom comparator is also not a valid strict ordering.
- **Evidence:** Powers_And_Bodies_Effects.gd cpu_get_discard_priority_ecard2 (~10270): sort puts Energy first; cpu_phase_ecard2_powers Scavenger Hunt block (~10510); power picks energies[0] for CPU (~10237).
- **Proposed fix:** Gate: only when the CPU needs an Energy it lacks in hand and deck has one; choose the 2 lowest cpu_rank_keep_value non-needed cards (never the needed Energy type); fetch via _r3_cpu_needed_energy / cpu_energy_need_value.
- **Files:** Powers_And_Bodies_Effects.gd

### 50. [x] ecard2-H16 Magneton — Magnetic Flow  (cpu) [OPUS]
- **Done:** New _cpu_magnetic_flow_plan(): tries every pair/energy swap on the player's side, value = increase in cheapest unmet cost (Active x2); CPU uses its pair and energies.
- **Problem:** CPU always swaps between with_energy[0] and with_energy[1] (opponent Active + first Benched) regardless of benefit.
- **Evidence:** Powers_And_Bodies_Effects.gd:9830-9831 defaults used for CPU; only the player prompts.
- **Proposed fix:** CPU: choose the pair that most disrupts the player (e.g. move a type-matched/Special Energy off the Active onto a Benched Pokémon that can't use it, take a Colorless-only Energy onto the Active); skip if no pair helps.
- **Files:** Powers_And_Bodies_Effects.gd

### 51. [x] ecard2-H16 Magneton — Magnetic Flow  (cpu) [OPUS]
- **Done:** The CPU phase only announces Magnetic Flow when that plan is non-empty (>= 2 player Pokémon with Energy and a real gain).
- **Problem:** CPU announces Magnetic Flow every turn Magneton is Active, even when the player has fewer than 2 Pokémon with Energy (power then fails) and with no benefit test.
- **Evidence:** Powers_And_Bodies_Effects.gd cpu_phase_ecard2_powers Magnetic Flow block (~10452): no precondition before announce_cpu_power.
- **Proposed fix:** Require >=2 player Pokémon with Energy and a computed gain (see the Magnetic Flow target finding) before announcing.
- **Files:** Powers_And_Bodies_Effects.gd

### 52. [x] ecard2-H21 Scizor — Snatch  (effect) [EASY]
- **Done:** Snatch's pre-damage switch now also requires not is_protected_from_effects(defender) and not active_switch_locked.
- **Problem:** The pre-damage gust ignores effect shields and switch locks: Spiral Aura/Sleep Inducer check is_protected_from_effects(defender) and active_switch_locked(), Snatch does not.
- **Evidence:** Attack_Effects.gd:16935 `if candidates.size() > 0:` — no is_protected_from_effects / active_switch_locked guard (compare 16985 / 17026).
- **Proposed fix:** Change the condition to `if candidates.size() > 0 and not is_protected_from_effects(defender) and not active_switch_locked(not is_opponent):`.
- **Files:** Attack_Effects.gd

### 53. [x] ecard2-H27 Togetic — Miracle Shift  (effect) [EASY]
- **Done:** Miracle Shift builds the attach pool from the discard pile AFTER the discard (the discarded card is choosable).
- **Problem:** The new Energy is chosen only from basics that were in the discard BEFORE the discard step, so if there were none, the power discards an Energy and attaches nothing (Pokémon loses an Energy); the just-discarded card is legally choosable.
- **Evidence:** Powers_And_Bodies_Effects.gd ~10069 discard_basics_before captured before discard_energy_from_pokemon; 'NO OTHER BASIC ENERGY IN DISCARD TO ATTACH!' path.
- **Proposed fix:** Build the choice pool from the discard pile AFTER discarding (include to_discard).
- **Files:** Powers_And_Bodies_Effects.gd

### 54. [x] ecard2-H27 Togetic — Miracle Shift  (cpu) [OPUS]
- **Done:** New _cpu_miracle_shift_plan(): swap only when the new basic type lowers that Pokémon's cheapest unmet cost; gate + power use the plan.
- **Problem:** CPU uses it whenever any basic Energy is in its discard and attaches discard_basics_before[0] — often the same type it discarded (no gain) or an unneeded type; the type change that is the point of the power isn't evaluated.
- **Evidence:** Powers_And_Bodies_Effects.gd cpu_phase_ecard2_powers Miracle Shift block (~10485) and ~10076 `new_energy = discard_basics_before[0]`.
- **Proposed fix:** CPU: only use when some own Pokémon has a basic Energy of a type its attacks don't need AND the discard has a basic of a type that reduces get_unmet_energy_count; pick that pair.
- **Files:** Powers_And_Bodies_Effects.gd

### 55. [x] ecard2-H29 Umbreon — Dark Moon  (cpu) [OPUS]
- **Done:** CPU Dark Moon takes the player's highest cpu_rank_keep_value cards and only fires when one is worth >= 60.
- **Problem:** CPU always uses Dark Moon and shuffles away the first N cards of the player's hand (opp_hand[0..]) instead of the most valuable ones.
- **Evidence:** Powers_And_Bodies_Effects.gd ~10138 `for i in range(want): chosen.append(opp_hand[i])`.
- **Proposed fix:** Sort player's hand by main.cpu_ai.cpu_rank_keep_value (desc) and take the top `want`; skip using it when the player's hand is tiny/low-value.
- **Files:** Powers_And_Bodies_Effects.gd

### 56. [x] ecard2-H7 Electrode — Super Dynamo  (cpu) [OPUS]
- **Done:** Super Dynamo CPU target = cpu_pick_benefit_recipient over all its Pokémon (fallback Electrode).
- **Problem:** CPU branch always attaches the first Lightning Energy in the discard to Electrode itself; text lets it choose any of its Pokémon.
- **Evidence:** Powers_And_Bodies_Effects.gd:9663-9665 `energy = lightning_e[0]; target = electrode` — only the player branch picks a target.
- **Proposed fix:** For is_opponent: target = main.cpu_ai.cpu_pick_benefit_recipient(all_own, "energy", energy) (fallback electrode).
- **Files:** Powers_And_Bodies_Effects.gd

### 57. [x] ecard2-H7 Electrode — Super Dynamo  (cpu) [OPUS]
- **Done:** CPU gate requires a Lightning Energy card in its discard pile before announcing.
- **Problem:** CPU announces and runs Super Dynamo every turn Electrode is Active, without checking there is a Lightning Energy in its discard pile — breaks the 'decide before announce_cpu_power' rule (announces then 'NO LIGHTNING ENERGY IN DISCARD PILE!').
- **Evidence:** Powers_And_Bodies_Effects.gd cpu_phase_ecard2_powers, Super Dynamo block (~line 10402): no discard check before announce_cpu_power.
- **Proposed fix:** Add `and main.opponent_discard_pile.any(func(c): return main.is_typed_energy_card(c, "Lightning"))` (and a useful recipient) to the condition before announcing.
- **Files:** Powers_And_Bodies_Effects.gd

### 58. [x] ecard2-H9 Espeon — Energy Return  (cpu) [OPUS]
- **Done:** New _cpu_energy_return_pick(): the badly damaged (<30% HP) Pokémon's most-needed Energy (cpu_energy_need_value).
- **Problem:** CPU branch returns attached_energies[0] from sources[0] (first Pokémon with Energy, usually its Active) — no board-based choice of which Energy/Pokémon.
- **Evidence:** Powers_And_Bodies_Effects.gd:9698-9702 `source = sources[0]` / `energy = source.attached_energies[0]`.
- **Proposed fix:** CPU: pick the source/energy by purpose (e.g. a Pokémon about to be KO'd, or an Energy needed in hand for a re-attach/Pure Body/retreat), else skip; use cpu_energy_need_value to choose the card.
- **Files:** Powers_And_Bodies_Effects.gd, CPU_AI.gd

### 59. [x] ecard2-H9 Espeon — Energy Return  (cpu) [OPUS]
- **Done:** The gate and the power both use _cpu_energy_return_pick, so they agree.
- **Problem:** CPU gate looks for a heavily damaged Pokémon with Energy, but the power then returns Energy from sources[0] (normally the Active), not from that damaged Pokémon — gate and action disagree.
- **Evidence:** Powers_And_Bodies_Effects.gd ~10409 worth_it loop vs 9698 `source = sources[0]`.
- **Proposed fix:** Pass the chosen Pokémon into power_ecard2_energy_return (or compute it inside the CPU branch with the same <30% HP rule) and return its Energy.
- **Files:** Powers_And_Bodies_Effects.gd

### 60. [x] ecard3-100 Snorlax — Lolling About  (cpu) [OPUS]
- **Done:** Lolling About only in the final power pass and only when Snorlax has no attack it can use (_cpu_active_can_attack).
- **Problem:** CPU uses Lolling About during the power phase whenever Snorlax is damaged; Snorlax then falls Asleep and cannot attack (or retreat) that turn, trading the turn's attack for a 10 HP heal.
- **Evidence:** Powers_And_Bodies_Effects.gd:11273-11279 — only checks current_hp < max and no special condition.
- **Proposed fix:** Only use it when Snorlax can't attack this turn anyway (no payable attack / no useful attack) or after the attack decision says it will not attack; otherwise skip.
- **Files:** Powers_And_Bodies_Effects.gd

### 61. [x] ecard3-34 Wigglytuff — Good Neighbor  (effect) [EASY]
- **Done:** Per-side _good_neighbor_turn checked/set in power_ecard3_good_neighbor and in the CPU gate.
- **Problem:** Text: 'can't be used if you have already used another Wigglytuff's Good Neighbor Poké-Power this turn.' Only the per-card power_used_this_turn flag is checked, so two Wigglytuffs can each use Good Neighbor in the same turn.
- **Evidence:** Powers_And_Bodies_Effects.gd:10794-10803 — no side-wide once-per-turn check.
- **Proposed fix:** Add a per-side per-turn flag (e.g. main.<side>_good_neighbor_used_turn = main.turn_number) checked at the top of power_ecard3_good_neighbor and set when the power is used; also gate the power-menu entry / CPU block on it.
- **Files:** Powers_And_Bodies_Effects.gd

### 62. [x] ecard3-34 Wigglytuff — Good Neighbor  (cpu) [OPUS]
- **Done:** _cpu_good_neighbor_worth(): CPU heal must exceed the player's, and never when the player's heal would save a Pokémon within the CPU Active's reach (cpu_best_damage_vs).
- **Problem:** CPU uses Good Neighbor whenever its own Active is damaged, ignoring that heads also heals the player's Active up to 20 (can undo the CPU's progress toward a KO).
- **Evidence:** Powers_And_Bodies_Effects.gd:11259 — only checks opponent_active_pokemon.current_hp < max.
- **Proposed fix:** Use it only if healing the CPU Active (min(20, damage)) is worth more than healing the player's Active (min(20, its damage)), and never when the player's Active is within reach of a KO this turn that the heal would prevent.
- **Files:** Powers_And_Bodies_Effects.gd

### 63. [x] ecard3-H1 Alakazam — Energy Jump  (cpu) [OPUS]
- **Done:** not a bug - the ex11 registration of 'Energy Jump' (power_ex11_energy_jump) replaces ecard3's dispatch entry, and cpu_phase_ex11_powers (run for every CPU deck) already uses it for ANY holder incl. ecard3 Alakazam via r4_cpu_plan_energy_moves. Comment added in cpu_phase_ecard3_powers.
- **Problem:** CPU never uses Energy Jump (deliberately skipped in cpu_phase_ecard3_powers), so a CPU Alakazam never moves Energy to power up or retreat-enable a Pokémon.
- **Evidence:** Powers_And_Bodies_Effects.gd:11281 — comment 'Energy Jump/Investigate ... skipped intentionally'; power_ecard3_energy_jump (10601) already has a CPU branch (cpu_rank_benefit_recipient / cpu_pick_benefit_recipient) that is never reached.
- **Proposed fix:** In cpu_phase_ecard3_powers add an Energy Jump block: use it when moving one Energy lets a Pokémon (Active first) meet an attack cost it currently can't (main.cpu_ai.get_unmet_energy_count drops to 0) or lets the Active retreat, taking the Energy from a Pokémon that keeps its own attack paid; decide before announce_cpu_power. Also make the CPU energy pick choose the Energy whose removal hurts the source least instead of attached_energies[0] (10626).
- **Files:** Powers_And_Bodies_Effects.gd

### 64. [x] ecard3-H17 Magcargo — Streaming Mantle  (cpu) [OPUS]
- **Done:** CPU Streaming Mantle only with deck > 10, >= 3 basic Energy in its discard, and no bigger gain for the player.
- **Problem:** CPU always triggers Streaming Mantle (do_it = is_opponent) with no board check — mills 3 of its own cards even with a small deck or no basic Energy in its discard.
- **Evidence:** Powers_And_Bodies_Effects.gd:11113 — var do_it = is_opponent.
- **Proposed fix:** For CPU: use it only when its deck has plenty of cards (e.g. > 10), its discard has >=3 basic Energy it wants back, and the player's deck is smaller/the player gains less; otherwise skip.
- **Files:** Powers_And_Bodies_Effects.gd

### 65. [x] ecard3-H18 Magneton — Attract Energy  (cpu) [OPUS]
- **Done:** CPU Attract Energy uses the r4 planner targeting Magneton (only cost-reducing moves) and never takes Energy the non-Magneton Active needs for its cheapest attack; moves fly.
- **Problem:** CPU moves EVERY basic Energy from all its other Pokémon (including its Active when Magneton evolved on the Bench) onto Magneton, which can leave the Active unable to attack or retreat.
- **Evidence:** Powers_And_Bodies_Effects.gd:11166-11175 — loops all 'others' and all their basic Energy, no selection.
- **Proposed fix:** CPU: only move Energy that Magneton needs for its attacks (up to the unmet cost + 1 spare), and never strip the Active below its own best attack's cost unless Magneton is the Active.
- **Files:** Powers_And_Bodies_Effects.gd

### 66. [x] ecard3-H24 Poliwrath — Strange Spiral  (cpu) [OPUS]
- **Done:** New _cpu_strange_spiral_energy(): the least valuable basic Energy whose discard keeps a payable attack (any if it can't attack anyway); gate + power use it.
- **Problem:** CPU fires Strange Spiral whenever the player's Active has no Special Condition, discarding a basic Energy even when that Energy is needed to pay for Poliwrath's attack this turn (Spiral Punch costs FFC), so it can confuse the Defender and then be unable to attack.
- **Evidence:** Powers_And_Bodies_Effects.gd:11251 — condition only checks basic energy exists and defender.special_condition == ''; no check of Poliwrath's attack cost after the discard.
- **Proposed fix:** Only use it if, after removing the chosen Energy, get_unmet_energy_count for Poliwrath's best attack is still 0 (or Poliwrath can't attack anyway), or if the confusion stops a KO threat; pick the Energy whose loss keeps the attack payable.
- **Files:** Powers_And_Bodies_Effects.gd

### 67. [x] ecard3-H5 Crobat — Carry Off  (cpu) [OPUS]
- **Done:** CPU Carry Off picks the player's best Pokémon card (Evolution fitting their board > Evolution > Basic > Baby).
- **Problem:** When the CPU's Carry Off hits heads it always shuffles away the FIRST Pokémon card in the player's hand rather than the most valuable one (e.g. a Stage 2 the player is about to play).
- **Evidence:** Powers_And_Bodies_Effects.gd:10682 — chosen = candidates[0]; only the player branch (10683) chooses.
- **Proposed fix:** For is_opponent, pick with main.cpu_ai.cpu_pick_best_keep(candidates) (or the card that evolves from something the player has in play, Evolution > Basic > Baby) instead of candidates[0].
- **Files:** Powers_And_Bodies_Effects.gd

### 68. [x] ex1-18 Nosepass — Repulsion  (effect) [EASY]
- **Done:** Repulsion: after heads, returns 'NO EFFECT' when the Defender is protected (is_protected_from_effects) or invincible.
- **Problem:** Bounces the Defending Pokemon to hand even when it is protected from attack effects (Agility/Fly invincibility, Protective Dust-style shields, Transparency).
- **Evidence:** Attack_Effects.gd:18649-18666 execute_ex1_repulsion never calls is_protected_from_effects / check_defender_invincible before gym1_return_pokemon_to_hand
- **Proposed fix:** After the heads result, if defender == null or is_protected_from_effects(defender) or main.check_defender_invincible(defender, not is_opponent): show 'REPULSION HAD NO EFFECT' and return.
- **Files:** Attack_Effects.gd

### 69. [x] ex1-5 Delcatty — Max Energy Source  (effect) [EASY]
- **Done:** Max Energy Source counts r4_energy_amount per Active.
- **Problem:** Counts Energy CARDS (attached_energies.size()) instead of the amount of Energy provided; a Double Rainbow / Scramble-style card (2-3 Energy) is counted as 1.
- **Evidence:** Attack_Effects.gd:18500 total_energy += p.attached_energies.size()
- **Proposed fix:** In execute_ex1_max_energy_source use total_energy += r4_energy_amount(p).
- **Files:** Attack_Effects.gd

### 70. [x] ex1-7 Gardevoir — Energy Burst  (effect) [EASY]
- **Done:** Energy Burst = r4_energy_amount(attacker) + r4_energy_amount(defender), null-safe.
- **Problem:** 'Total amount of Energy attached to Gardevoir and the Defending Pokemon' is computed from card counts, so multi-Energy special cards undercount. Also no null-guard on defender.
- **Evidence:** Attack_Effects.gd:18515 attacker.attached_energies.size() + defender.attached_energies.size()
- **Proposed fix:** In execute_ex1_energy_burst use r4_energy_amount(attacker) + (r4_energy_amount(defender) if defender != null else 0).
- **Files:** Attack_Effects.gd

### 71. [x] ex2-4 Dusclops — Judgement  (effect) [EASY]
- **Done:** Judgement's both-heads KO checks is_protected_from_effects (with a 'protected' message) instead of only is_invincible.
- **Problem:** Both-heads KO only checks defender.is_invincible; other 'prevent all effects of attacks' shields (Wonder Guard vs evolved attacker, Transparency, Light Wave, Safeguard-class r4 shields) are ignored, so the KO lands through them.
- **Evidence:** Attack_Effects.gd:19128 — `if heads == 2 and defender != null and not defender.is_invincible:`
- **Proposed fix:** Replace `not defender.is_invincible` with `not is_protected_from_effects(defender)` (Attack_Effects.gd:575), and show a 'protected' message in that case.
- **Files:** Attack_Effects.gd

### 72. [x] ex2-4 Dusclops — Random Curse  (effect) [EASY]
- **Done:** Random Curse skips is_protected_from_effects targets and places 5 counters via gym1_place_counters (no dispatch_on_damage).
- **Problem:** Counter placement skips only is_invincible targets; effect shields (is_protected_from_effects / r4_attack_effect_shield, e.g. Wonder Guard vs Stage 1 Dusclops) don't stop the 5 counters. It also calls dispatch_on_damage for counters, so on-damage bodies like Poison Payback / Fire Veil / Jagged Stone trigger from damage counters, which are not damage.
- **Evidence:** Attack_Effects.gd:19144-19150 — `if dp.is_invincible: continue` ... `await main.powers_and_bodies.dispatch_on_damage(dp, attacker, dmg, not is_opponent)`
- **Proposed fix:** Use `if is_protected_from_effects(dp): continue`; place counters via gym1_place_counters(dp, 50, not is_opponent) (as Haunt does) rather than raw HP + dispatch_on_damage, or skip dispatch_on_damage for counter placement.
- **Files:** Attack_Effects.gd

### 73. [x] ex2-55 Xatu — Psyimpact  (effect) [EASY]
- **Done:** Psyimpact: is_protected_from_effects skip + gym1_place_counters(p, 10) (no on-damage hooks).
- **Problem:** Skips only is_invincible Pokémon, ignoring other effect shields (is_protected_from_effects). Also fires dispatch_on_damage for a damage counter, so an Active Cacturne/Cacnea (Poison Payback), Arcanine/Growlithe (Fire Veil) or Claw Fossil (Jagged Stone) retaliates against counters, which aren't attack damage.
- **Evidence:** Attack_Effects.gd:19871-19877 — `if p.is_invincible: continue` ... `dispatch_on_damage(p, attacker, 10, target_is_opp)`
- **Proposed fix:** Use `if is_protected_from_effects(p): continue` and place the counter via gym1_place_counters(p, 10, target_is_opp) (no dispatch_on_damage).
- **Files:** Attack_Effects.gd

### 74. [x] ex2-87 Lanette's Net Search — Lanette's Net Search  (choice) [OPUS]
- **Done:** Lanette's Net Search offers EVERY non-Baby Basic on one choose_cards screen with distinct_key_validator(type); CPU takes best per type; cards fly, are revealed, deck shuffled.
- **Problem:** Only the FIRST Basic of each type in the deck goes into the pool (one card per type), so the player can't choose which Fire/Water/... Basic to take. The text lets them pick any up to 3 Basics of different types.
- **Evidence:** Trainer_Effects.gd:10413-10427 — `if t in seen_types: continue` builds a 1-per-type candidates list, then search_deck_to_hand(filter c in candidates, 3)
- **Proposed fix:** Show all eligible non-Baby Basics with Card_Ops.prompt_select_cards(pool, 0, 3, ...) and reject or re-prompt a selection with a repeated type, or pick sequentially, removing same-type cards after each pick (agreed per-pick exception). CPU: pick the best-ranked card per type with cpu_rank_keep_value.
- **Files:** Trainer_Effects.gd

### 75. [x] ex2-87 Lanette's Net Search — CPU score  (cpu) [OPUS]
- **Done:** New _cpu_score_lanettes_net_search (ex2-87 and ex9-77): -100 with no Basic, scaled by distinct types vs Bench room and Basics already in hand.
- **Problem:** Flat 55 score: the CPU plays it whenever it can, even with a full Bench, a deck with no Basics, or a hand already full of Basics, and ahead of better Supporters.
- **Evidence:** CPU_AI.gd:5625 — `"ex2-87": return 55.0`
- **Proposed fix:** Score by need: -100 if the deck has no non-Baby Basic; scale with open Bench slots and how many distinct types it would find, and lower when the hand already has Basics to bench (like the other Basic-search Supporters' scorers).
- **Files:** CPU_AI.gd

### 76. [x] ex2-89 Wally's Training — Wally's Training  (effect) [EASY]
- **Done:** Wally's Training refuses when the Active is not in get_pokemon_that_may_evolve_now; new validator for ex2-89/ex9-85; CPU scorer uses the same check.
- **Problem:** No evolution-legality check: it evolves the Active even if it was played/evolved this turn, on the first turn, or under an evolve lock. Rare Candy right above it uses get_pokemon_that_may_evolve_now. The CPU scorer checks placed_on_field_this_turn, but the player can break the rule.
- **Evidence:** Trainer_Effects.gd:10496-10512 — only filters deck by can_evolve_from(c, active); no may-evolve gate
- **Proposed fix:** At the top: `if not (active in main.get_pokemon_that_may_evolve_now(is_opponent)):` show 'CAN'T EVOLVE THIS TURN' and return (still shuffle). Ideally also add a play validator so the card isn't spent. CPU scorer: use get_pokemon_that_may_evolve_now(true) instead of only placed_on_field_this_turn.
- **Files:** Trainer_Effects.gd, CPU_AI.gd

### 77. [x] ex2-96 Gardevoir ex — Feedback  (effect) [EASY]
- **Done:** Feedback: is_protected_from_effects guard + gym1_place_counters (no dispatch_on_damage).
- **Problem:** Counter placement skips only is_invincible defenders, ignoring other effect shields (Wonder Guard vs evolved/ex attacker, Safeguard-class r4 shields such as ex8 Psychic Shield / ex12 ex Shield, Transparency). It also fires dispatch_on_damage for counters, so Poison Payback / Fire Veil / Jagged Stone retaliate against damage counters.
- **Evidence:** Attack_Effects.gd:19904-19911 — `if defender == null or defender.is_invincible: return` ... `dispatch_on_damage(defender, attacker, dmg, not is_opponent)`
- **Proposed fix:** Use `if defender == null or is_protected_from_effects(defender): return` and place the counters via gym1_place_counters(defender, dmg, not is_opponent) (no dispatch_on_damage).
- **Files:** Attack_Effects.gd

### 78. [x] ex3-2 Altaria — Dragon Dance  (effect) [EASY]
- **Done:** Dragon Dance / Crystal Laser store the user (player/opponent_dragon_dance_pending_src -> _src at turn start); _hook_dragon_dance requires attacker == that Pokémon.
- **Problem:** Text: 'During your next turn, if any of your CURRENT Active Pokémon does damage...' +40. The final handler sets a side-wide pending buff (player/opponent_dragon_dance_pending), and _hook_dragon_dance adds it to WHATEVER Pokémon is Active next turn. So you can Dragon Dance with Altaria, retreat or switch, and the new Active gets +40.
- **Evidence:** Attack_Effects.gd:26442-26450 sets main.*_dragon_dance_pending; Powers_And_Bodies_Effects.gd:15230-15239 applies the bonus to any attacker == current active; Main_Match_Core_Gameplay_Script.gd:8345-8352 promotes pending to active
- **Proposed fix:** Record the attacker too: store main.*_dragon_dance_source = a (card_object) next to the pending value, promote it with the value at 8345-8352, and in _hook_dragon_dance require attacker == the stored source (keep the defender unrestricted for Dragon Dance). Clear the source when the buff clears.
- **Files:** Attack_Effects.gd, Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 79. [x] ex3-45 Swellow — Quick Dive  (effect) [EASY]
- **Done:** Quick Dive's Active hit goes through hit_active_no_wr (all non-W/R modifiers and the hit animation).
- **Problem:** On the Active target, damage is applied by hand (current_hp -= fd, after apply_defender_no_damage_shield only). This skips everything except W/R that should still apply: the defender's damage-reducing Bodies and Tools (Buffer Piece, Exoskeleton, Energy Guard, Shell Retreat, Intimidating Fang, Expand/Granite Head reductions), the attacker-side modifiers (PlusPower, Dragon Dance, Power Pinchers), Wonder Guard checks beyond is_invincible, and the normal hit animation. The text only removes Weakness and Resistance.
- **Evidence:** Attack_Effects.gd:20780-20786 execute_ex3_quick_dive manual HP subtraction + show_floating_label
- **Proposed fix:** Route the Active hit through the shared 'ignore W/R only' damage path (the one execute_sonicboom uses at Attack_Effects.gd:344, or gym1_hit_active with a skip-W/R flag if it has one) instead of the manual subtraction. Keep apply_bench_damage for Bench targets.
- **Files:** Attack_Effects.gd

### 80. [x] ex3-6 Grumpig — Psychic Boom  (effect) [EASY]
- **Done:** Psychic Boom (both the '+' and '×' handlers) uses r4_energy_amount(defender). The CPU estimate reads the same handlers' text rules.
- **Problem:** '10 more damage for each Energy attached to the Defending Pokémon' counts Energy CARDS (attached_energies.size()), so a Double Colorless or other multi-Energy card counts as 1 instead of its provided amount. Grind and Magnetic Force in the same set correctly use r4_energy_amount.
- **Evidence:** Attack_Effects.gd:21001 execute_ex3_energy_boom: base_damage + 10 * defender.attached_energies.size()
- **Proposed fix:** Use r4_energy_amount(defender) instead of defender.attached_energies.size(). Make the CPU estimator for 'psychic boom' match.
- **Files:** Attack_Effects.gd, CPU_AI.gd

### 81. [x] ex4-4 Team Aqua's Manectric — Power Shift  (anim) [EASY]
- **Done:** Power Shift / Magma Switch CPU: planner moves are undone and redone with capture_rect + fly_attach.
- **Problem:** CPU branch moves Energy between Pokémon with no flight animation (data mutated inside r4_cpu_plan_energy_moves, then only sfx + redraw).
- **Evidence:** Powers_And_Bodies_Effects.gd:12660-12668 (power_ex4_energy_move CPU branch) + r4_cpu_plan_energy_moves 12611-12643 — attachments moved directly, no fly_attach.
- **Proposed fix:** In the CPU branch, plan with a dry run (revert each move), then for each planned move: capture_rect(e,'attached',true), erase from source, append to dest, await card_ops.fly_attach(e,'attached',rect), play_energy_attach_sfx() — same as the player branch at ~12700.
- **Files:** Powers_And_Bodies_Effects.gd

### 82. [x] ex4-4 Team Aqua's Manectric — Power Shift  (effect) [EASY]
- **Done:** r4_cpu_plan_energy_moves gained a same_dest flag (locks the destination after the first move); Power Shift passes it.
- **Problem:** Text moves Energy from 1 Pokémon to ANOTHER (single) Pokémon. The CPU planner locks the source (same_source=true) but not the destination, so the CPU can split the moved Energy across several Pokémon.
- **Evidence:** Powers_And_Bodies_Effects.gd:12611 r4_cpu_plan_energy_moves — only locked_src; each iteration picks the best dst freely; called from 12660 with max_move -1.
- **Proposed fix:** Add a same_dest flag to r4_cpu_plan_energy_moves (lock dst after the first move like locked_src) and pass it from power_ex4_energy_move for Power Shift.
- **Files:** Powers_And_Bodies_Effects.gd

### 83. [x] ex4-71 Archie — Supporter (CPU score)  (cpu) [OPUS]
- **Done:** Archie -> _cpu_score_ex4_team_bench('Team Aqua', deck): -100 on full Bench / nothing to find, 65-70 when it skips evolving, 30 for a Stage 2 that would land at <= 20 HP.
- **Problem:** Flat CPU score 50 — CPU plays Archie even when its deck has no Team Aqua Pokémon or its Bench is full (Supporter wasted), and doesn't prefer it for a Stage 2 jump.
- **Evidence:** CPU_AI.gd:5640 `"ex4-71": return 50.0`.
- **Proposed fix:** Replace with _cpu_score_ex4_team_bench("Team Aqua", from_deck=true): -100 if bench full or no Team Aqua Pokémon in opponent_deck; else base 45, +25 if a Stage 1/Stage 2 Team Aqua is available (skips evolving), -15 if the only Stage 2 would come in at <=20 HP.
- **Files:** CPU_AI.gd

### 84. [x] ex4-72 Dual Ball — Item (CPU score)  (cpu) [OPUS]
- **Done:** Dual Ball -> _cpu_score_ex4_basic_search: -100 with no Basic in deck, else 32+ by Bench room.
- **Problem:** Flat CPU score 45 regardless of whether any Basic Pokémon remain in the deck or the CPU needs one.
- **Evidence:** CPU_AI.gd:5641 `"ex4-72": return 45.0`.
- **Proposed fix:** Score like _cpu_score_poke_ball(): -100 if no Basic Pokémon in opponent_deck; higher when bench has free slots / few Pokémon in play.
- **Files:** CPU_AI.gd

### 85. [x] ex4-73 Maxie — Supporter (CPU score)  (cpu) [OPUS]
- **Done:** Maxie -> _cpu_score_ex4_team_bench('Team Magma', hand + discard).
- **Problem:** Flat CPU score 50 — CPU plays Maxie with no Team Magma Pokémon in hand/discard or a full Bench (Supporter wasted).
- **Evidence:** CPU_AI.gd:5642 `"ex4-73": return 50.0`; effect Trainer_Effects.gd:10760 just shows NO MATCHING POKEMON.
- **Proposed fix:** Same helper as Archie but pool = opponent_hand + opponent_discard_pile Team Magma Pokémon; -100 if empty or bench full.
- **Files:** CPU_AI.gd

### 86. [x] ex4-75 Team Aqua Ball — Item (CPU score)  (cpu) [OPUS]
- **Done:** Team Aqua Ball -> _cpu_score_ex4_basic_search(true, 'Team Aqua'): -100 when the deck has no Team Aqua Pokémon.
- **Problem:** Flat CPU score 45 even when the deck holds no Team Aqua Pokémon (card does nothing).
- **Evidence:** CPU_AI.gd:5644 `"ex4-75": return 45.0`.
- **Proposed fix:** Return -100 if no Team Aqua Pokémon in opponent_deck; else scale on need (bench space, evolutions missing) like _cpu_score_poke_ball.
- **Files:** CPU_AI.gd

### 87. [x] ex4-76 Team Aqua Belt — Tool (CPU score)  (cpu) [OPUS]
- **Done:** Team Aqua Belt -> _cpu_score_ex4_belt: -100 unless a Tool-free Team Aqua Pokémon in play has an evolution in the deck (Active 50, Bench 35).
- **Problem:** Flat CPU score 40 — CPU attaches it whether or not the deck contains an evolution of the holder or the holder will be Active (the only time it works).
- **Evidence:** CPU_AI.gd:5645 `"ex4-76": return 40.0`.
- **Proposed fix:** Score -100 unless a Team Aqua Pokémon in play (prefer Active) has a card in opponent_deck that can_evolve_from it; attach to that Pokémon.
- **Files:** CPU_AI.gd

### 88. [x] ex4-77 Team Aqua Conspirator — Supporter (CPU score)  (cpu) [OPUS]
- **Done:** Team Aqua Conspirator -> _cpu_score_ex4_conspirator: -100 with no Basic Team Pokémon / basic Energy in deck, else by count and Energy need.
- **Problem:** Flat CPU score 55 even when no Basic Team Aqua Pokémon or basic Energy remain in the deck.
- **Evidence:** CPU_AI.gd:5646 `"ex4-77": return 55.0`.
- **Proposed fix:** Count eligible cards in opponent_deck; -100 if 0; else base on need (energy short for attacks, bench space) like _cpu_score_energy_fetch.
- **Files:** CPU_AI.gd

### 89. [x] ex4-80 Team Magma Ball — Item (CPU score)  (cpu) [OPUS]
- **Done:** Team Magma Ball -> same helper with 'Team Magma'.
- **Problem:** Flat CPU score 45 even when the deck holds no Team Magma Pokémon.
- **Evidence:** CPU_AI.gd:5647 `"ex4-80": return 45.0`.
- **Proposed fix:** Same as Team Aqua Ball with team "Team Magma".
- **Files:** CPU_AI.gd

### 90. [x] ex4-81 Team Magma Belt — Tool (CPU score)  (cpu) [OPUS]
- **Done:** Team Magma Belt -> same helper with 'Team Magma'.
- **Problem:** Flat CPU score 40 regardless of evolution availability.
- **Evidence:** CPU_AI.gd:5648 `"ex4-81": return 40.0`.
- **Proposed fix:** Same as Team Aqua Belt with Team Magma.
- **Files:** CPU_AI.gd

### 91. [x] ex4-82 Team Magma Conspirator — Supporter (CPU score)  (cpu) [OPUS]
- **Done:** Team Magma Conspirator -> same helper with 'Team Magma'.
- **Problem:** Flat CPU score 55 regardless of whether eligible cards exist in the deck.
- **Evidence:** CPU_AI.gd:5649 `"ex4-82": return 55.0`.
- **Proposed fix:** Same as Team Aqua Conspirator with "Team Magma".
- **Files:** CPU_AI.gd

### 92. [x] ex5-4 Dark Celebi — Dark Provide  (effect) [EASY]
- **Done:** execute_ex5_attach_from_hand got typed_cards (is_typed_energy_card); Dark Provide passes true so Special Darkness Energy cards qualify.
- **Problem:** Text says 'Attach up to 1 Grass or Darkness Energy card from your hand'. In this engine Darkness Energy (ex1-93 etc.) is a Special Energy card, but the hand filter requires subtype Basic, so a Darkness Energy card can never be attached - only basic Grass.
- **Evidence:** Attack_Effects.gd:22408 execute_ex5_attach_from_hand type_filter rejects any card without 'Basic' in subtypes; Card_Set_Data ex1-93/ex9-86/ex16-87 Darkness Energy subtypes ['Special']
- **Proposed fix:** Add a parameter allow_special:bool to execute_ex5_attach_from_hand (default false) and pass true from the 'dark provide' registration (Attack_Effects.gd:22232); when true accept any Energy card whose get_energy_provided_by_card includes one of `types`.
- **Files:** Attack_Effects.gd

### 93. [x] ex5-5 Electrode — Mass Destruction  (cpu) [OPUS]
- **Done:** Mass Destruction CPU: +1000 when the mutual KO wins (player has no Bench, or the Prizes taken are the CPU's last), -9999 when it loses (CPU has no Bench or Electrode is the player's last Prize), +200 vs an ex, else the old doomed/healthy rule.
- **Problem:** CPU scoring for Mass Destruction ignores the prize/bench situation: it gives -150 whenever its Active is not doomed, even when the player has no Bench (mutual KO wins the game if the CPU has a Bench) or the Defending Pokemon is a Pokemon-ex (2 prizes for 1); and gives +300 when doomed even if the CPU has no Benched Pokemon (it then loses immediately instead of maybe surviving a turn).
- **Evidence:** CPU_AI.gd:4219-4228 (only md_has_special / cpu_will_be_koed considered)
- **Proposed fix:** In the 'mass destruction' branch: if main.opponent_bench.is_empty() -> score = -9999 unless the player also has no Bench and CPU prizes left <= 1; if main.player_bench.is_empty() and CPU bench not empty -> +1000 (win); if player Active is ex -> +200 (2 prizes for 1) even when not doomed; also add +250 when the CPU takes its last prize(s) with it.
- **Files:** CPU_AI.gd

### 94. [x] ex5-84 Ancient Technical Machine [Ice] — Trainer score / Ice Generator  (cpu) [OPUS]
- **Done:** ATM [Ice]: _cpu_score_ex5_atm / _cpu_atm_attack_value - needs an Evolved non-ex non-owner Active and player Trainers in play (Tools/TMs + their Stadium); 'ice generator' added to cpu_utility_attack_value.
- **Problem:** CPU scores all three Ancient TMs at a flat 35 (> 29.9 threshold) whenever _cpu_score_attack_granting finds no damage gain (always, they do no damage), so it attaches them blindly; and no CPU attack-valuation exists for 'ice generator' / 'stone generator' / 'steel generator', so having attached it the CPU has no reason to use the attack. Ice Generator is only useful when the player has Tools/TMs/Stadium in play.
- **Evidence:** CPU_AI.gd:5750 flat 35.0 for ex5-84/85/86; CPU_AI.gd:6328 _cpu_score_attack_granting returns 0 for non-damage attacks; grep 'generator' in CPU_AI.gd = no hits (cpu_utility_attack_value CPU_AI.gd:8342 has no case)
- **Proposed fix:** Replace the flat score with per-card situational scores: ex5-84 = 40 + 15 per player Trainer in play (attached_cards Trainers on player Pokemon + player-owned stadium) else -50; ex5-85 = 30 + 20 per player Pokemon with attached_pre_evolutions non-empty, else -50; ex5-86 = 35 if player Active has abilities and another player Pokemon has basic Energy, else -50; require an Evolved non-ex non-owner CPU Active that can pay the cost. Add matching cases in cpu_utility_attack_value for the three attack names using the same conditions.
- **Files:** CPU_AI.gd

### 95. [x] ex5-85 Ancient Technical Machine [Rock] — Trainer score / Stone Generator  (cpu) [OPUS]
- **Done:** ATM [Rock]: value 30 + 20 per player Evolved Pokémon, else none; 'stone generator' utility case added.
- **Problem:** Same flat 35 score and no attack valuation as ATM [Ice]; CPU attaches it even when the player has no Evolved Pokemon (attack does nothing).
- **Evidence:** CPU_AI.gd:5750; no 'stone generator' case in CPU_AI.gd
- **Proposed fix:** See ex5-84 finding: score 30 + 20 per player Evolved Pokemon (else -50) and add a 'stone generator' case to cpu_utility_attack_value.
- **Files:** CPU_AI.gd

### 96. [x] ex5-86 Ancient Technical Machine [Steel] — Trainer score / Steel Generator  (cpu) [OPUS]
- **Done:** ATM [Steel]: needs a Power/Body on the player's Active and basic Energy on another player Pokémon; 'steel generator' utility case added.
- **Problem:** Same flat 35 score and no attack valuation; attack does nothing unless the Defending Pokemon has a Poke-Power/Body and another player Pokemon has basic Energy.
- **Evidence:** CPU_AI.gd:5750; no 'steel generator' case in CPU_AI.gd
- **Proposed fix:** See ex5-84 finding: condition the score on player Active abilities + movable basic Energy, and add a 'steel generator' case to cpu_utility_attack_value.
- **Files:** CPU_AI.gd

### 97. [x] ex6-10 Pidgeot — Quick Search  (effect) [EASY]
- **Done:** Per-side _quick_search_turn: refuses a second Quick Search the same turn; CPU gate checks it.
- **Problem:** Text: 'You can't use more than 1 Quick Search Poké-Power each turn.' The power only checks the individual Pidgeot's power_used_this_turn, so with 2+ Pidgeot in play the player (and CPU via _find_cpu_pokemon_with_power) can use Quick Search once per Pidgeot each turn.
- **Evidence:** Powers_And_Bodies_Effects.gd:13560-13570 power_ex6_quick_search — only `if pidgeot.power_used_this_turn`; no per-side turn flag anywhere (grep 'Quick Search' finds only the dispatch, the function and the CPU call at :13849)
- **Proposed fix:** Add per-side flags main.player_quick_search_used / main.opponent_quick_search_used (reset at turn start where other *_used_this_turn side flags reset, e.g. opponent_ex5_heal_dance_used); refuse with a message when set; set it on use; CPU phase at :13849 must check the flag before announce_cpu_power.
- **Files:** Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 98. [x] ex6-72 Paras — Call for Family  (choice) [OPUS]
- **Done:** execute_call_for_pokemon got max_n: 'up to 2' is one choose_cards screen capped by Bench room (CPU keep-value rank); _ex6_call_for_family and execute_ex13_call_two_basics call it once.
- **Problem:** 'up to 2' is implemented as two sequential single-card prompts (loop of execute_call_for_pokemon), violating the one-screen multi-select rule; same for ex6-86 Weedle ('up to 2 Grass Basic Pokémon'). The deck is also shuffled between the two picks.
- **Evidence:** Attack_Effects.gd:23820-23822 (_ex6_call_for_family: `for i in range(count): await execute_call_for_pokemon(...)`) ; execute_call_for_pokemon uses prompt_select_card at :3577
- **Proposed fix:** For count>1 build the eligible pool once (supertype Pokémon, Basic, optional type filter), clamp max to free bench slots, player: Card_Ops.prompt_select_cards(pool, 0, mini(2, room), 'CALL FOR FAMILY', ...); CPU: take top-2 by cpu_rank_keep_value; place each with place_on_bench, shuffle once. execute_ex13_call_two_basics (used by ex14 Tauros) may already do this — reuse it with a type filter param for Weedle.
- **Files:** Attack_Effects.gd

### 99. [x] ex7-103 Rocket's Sneasel ex — Dark Ring  (cpu) [OPUS]
- **Done:** _r3_estimate now reads 'more damage for each of your Darkness Pokémon in play' (Dark Ring).
- **Problem:** CPU damage estimate ignores the conditional bonus (+10 per own Darkness Pokemon in play); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): count own Pokemon whose get_effective_types() has 'Darkness'; return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 100. [x] ex7-105 Rocket's Suicune ex — Hyper Splash  (cpu) [OPUS]
- **Done:** _r3_estimate: '... is a Stage 2 Evolved Pokémon' bonus (Hyper Splash).
- **Problem:** CPU damage estimate ignores the conditional bonus (+40 vs a Stage 2 Defending Pokemon); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): if 'stage 2 evolved pokémon' in t: + more when defender has 'Stage 2' subtype; return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 101. [x] ex7-107 Mudkip Star — Spring Back  (cpu) [OPUS]
- **Done:** _r3_estimate: 'your opponent has only 1 Prize card left' bonus (Spring Back x3, ex13 Pikachu Star).
- **Problem:** CPU damage estimate ignores the conditional bonus (+50 (and status) when the opponent has exactly 1 Prize left (also Torchic Star ex7-108, Treecko Star ex7-109)); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): opp prize count == 1; return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 102. [x] ex7-19 Dark Tyranitar — Spinning Tail  (cpu) [OPUS]
- **Done:** ex7 CPU block reads N from 'damage to each' for Dark Drain / Spinning Tail (20 for Spinning Tail).
- **Problem:** ex7 CPU scoring block treats Spinning Tail like Dark Drain (10 per target): score 20/target and KO bonus only when 10 >= player HP. ex7-19 Spinning Tail does 20 to each opposing Pokemon, so it is under-valued and misses KOs at 20 HP.
- **Evidence:** CPU_AI.gd:4302-4305 ('dark drain' or 'spinning tail' share 10-damage numbers).
- **Proposed fix:** Split the branch: read n = extract_number_before(text,'damage to each') (20 for Spinning Tail, 10 for Dark Drain); score += 2.0*n*(1+bench); KO bonus if n >= player_hp.
- **Files:** CPU_AI.gd

### 103. [x] ex7-19 Dark Tyranitar — Bite Off  (cpu) [OPUS]
- **Done:** _r3_estimate: '... is Pokémon-ex' bonus (Bite Off and all its reprints).
- **Problem:** CPU damage estimate ignores the conditional bonus (+50 if the Defending Pokemon is Pokemon-ex); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): main.is_ex_pokemon(defender); return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 104. [x] ex7-2 Dark Ampharos — Darkest Impulse  (effect) [EASY]
- **Done:** Per-side _darkest_impulse_turn: Darkest Impulse fires once per turn.
- **Problem:** Text: 'You can't use more than 1 Darkest Impulse Poke-Body each turn.' Code fires on EVERY evolution (the early return only stops a 2nd Ampharos firing on the same evolution), so an opponent evolving 2-3 Pokemon in one turn takes 2 counters on each.
- **Evidence:** Powers_And_Bodies_Effects.gd:14637-14649 check_ex7_darkest_impulse has no per-turn flag; called from Main_Match_Core_Gameplay_Script.gd:9003 (_after_evolution) for every from-hand evolution.
- **Proposed fix:** Add a per-turn flag (e.g. main.ex7_darkest_impulse_used_turn = main.turn_number or a side bool reset at turn start); in check_ex7_darkest_impulse return early if already used this turn, set it when it fires.
- **Files:** Powers_And_Bodies_Effects.gd

### 105. [x] ex7-20 Dark Tyranitar — Second Strike  (cpu) [OPUS]
- **Done:** _r3_estimate: 'already has at least 2 damage counters' bonus (Second Strike).
- **Problem:** CPU damage estimate ignores the conditional bonus (+20 if the Defending Pokemon already has >= 2 damage counters); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): defender.get_damage_counters() >= 2; return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 106. [x] ex7-29 Dark Arbok — Swallow Up  (cpu) [OPUS]
- **Done:** _r3_estimate: 'fewer remaining HP than' bonus (Swallow Up).
- **Problem:** CPU damage estimate ignores the conditional bonus (+30 if the Defending Pokemon has fewer remaining HP than Dark Arbok); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): defender.current_hp < attacker.current_hp; return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 107. [x] ex7-32 Dark Dragonair — Double Tackle  (cpu) [OPUS]
- **Done:** Double Tackle split from Black Suction Cups and scored from 'damage to each' (20).
- **Problem:** ex7 CPU block scores Double Tackle (20 to each Defending) as 10 damage: +20 score and KO bonus only if 10 >= player HP. Also applies to ex7-40 Dark Pupitar Double Tackle. Base damage field is blank so the generic estimate is 0.
- **Evidence:** CPU_AI.gd:4306-4308 (black suction cups / double tackle grouped at 10).
- **Proposed fix:** Separate 'double tackle': score += 40.0; if 20 >= player_hp: score += 500.0 (or read N from 'damage to each').
- **Files:** CPU_AI.gd

### 108. [x] ex7-37 Dark Houndoom — Fire Payback  (cpu) [OPUS]
- **Done:** _r3_estimate: 'less Benched Pokémon than your opponent' bonus (Fire Payback).
- **Problem:** CPU damage estimate ignores the conditional bonus (+20 when you have fewer Benched Pokemon than the opponent); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): if 'if you have less benched pokémon than your opponent' in t: add more when own_bench.size() < opp_bench.size(); return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 109. [x] ex7-38 Dark Magcargo — Energy Press  (cpu) [OPUS]
- **Done:** _r3_estimate: + per basic Energy card on your Active(s) (Energy Press).
- **Problem:** CPU damage estimate ignores the conditional bonus (+10 per basic Energy card on your Active Pokemon); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): count basic energy cards on own active(s); return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 110. [x] ex7-43 Heracross — Get Even  (cpu) [OPUS]
- **Done:** _r3_estimate: + per Prize card more than the opponent (Get Even).
- **Problem:** CPU damage estimate ignores the conditional bonus (+10 per Prize card you have more than the opponent); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): if 'for each prize card more than your opponent' in t: b + per*max(0, own_prizes - opp_prizes); return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 111. [x] ex7-5 Dark Houndoom — Dark Fire  (cpu) [OPUS]
- **Done:** _r3_estimate: ex7 Dark Fire's optional Fire/Darkness discard adds +20 when such Energy is attached; neo4 rule unchanged.
- **Problem:** CPU damage estimate uses the neo4 Dark Fire rule (60 if any Darkness attached, else 30). ex7 Dark Fire is 40, +20 if it discards a Fire OR Darkness Energy, so with only Fire Energy the CPU thinks it does 30 (real 40-60) and with Darkness it never accounts for the optional discard.
- **Evidence:** Attack_Effects.gd:1201-1203 _r3_estimate match 'dark fire' — neo4-only formula applied to ex7-5.
- **Proposed fix:** In _r3_estimate 'dark fire': if 'you may discard a fire energy or darkness energy' in t: var k = count of attached energy providing Fire or Darkness; return mk.call(b, b + (r4_num(atk,'more damage',20) if k>0 else 0), same max); else keep neo4 formula.
- **Files:** Attack_Effects.gd

### 112. [x] ex7-6 Dark Hypno — Black Magic  (cpu) [OPUS]
- **Done:** _r3_estimate: 'N damage times the number of your opponent's Benched Pokémon' (Dark Hypno Black Magic) and the ex11 '+N times' wording.
- **Problem:** Damage field '20×' with no coins: the raw estimator's × branch returns {min 0, max 40} (generic ×2) regardless of the opponent's Bench, so CPU values Black Magic as 0-40 instead of 20 × opponent's Benched Pokemon (0-100).
- **Evidence:** Attack_Effects.gd:1403-1416 (× branch default base*2); no 'times the number of your opponent's benched' rule in _estimate_board_scaled.
- **Proposed fix:** In _estimate_board_scaled add: if times and "times the number of your opponent's benched pokémon" in text: n = opp bench size; return mk.call(base*n, base*n, base*n).
- **Files:** Attack_Effects.gd

### 113. [x] ex7-9 Dark Slowking — Litter  (cpu) [OPUS]
- **Done:** _r3_estimate: Litter + 30 per Tool / Rocket's Secret Machine in hand (max 2).
- **Problem:** CPU damage estimate ignores the conditional bonus (+30 per Tool / Rocket's Secret Machine discarded from hand (up to 2)); it only sees the printed base, so the CPU under-rates the attack and misses KOs when the condition holds.
- **Evidence:** Attack_Effects.gd:987 estimate_attack_damage_range -> _estimate_board_scaled / _r3_estimate (1111) / _estimate_attack_damage_range_raw (1397) have no rule for this wording, so CPU attack choice, KO tests (min/max) and lookahead see only the printed base.
- **Proposed fix:** Add a text-keyed case to _r3_estimate (or _estimate_board_scaled): max = b + per*min(2, count of tool/RSM in own hand); return mk.call(dmg,dmg,dmg) with the real total.
- **Files:** Attack_Effects.gd

### 114. [x] ex8-13 Ninjask — Fast Protection  (effect) [EASY]
- **Done:** Dropped 'and not a_ex' from the Fast Protection line in r4_attack_effect_shield.
- **Problem:** 'Prevent all effects, including damage, done to Ninjask by your opponent's attacks from his or her Basic Pokemon.' Basic Pokemon-ex ARE Basic Pokemon. The damage hook blocks a Basic ex's damage (is_basic_pokemon only), but the effect shield excludes ex (`not a_ex`), so a Basic ex's attack effects (status, energy discard, gust, counters) still land while its damage is blocked - inconsistent and wrong.
- **Evidence:** Attack_Effects.gd:~611 r4_attack_effect_shield `if main.is_basic_pokemon(a) and not a_ex and body.call("Fast Protection")`; Powers_And_Bodies_Effects.gd:15179 _hook_ex8_fast_protection uses is_basic_pokemon(attacker) only
- **Proposed fix:** Drop `and not a_ex` from the Fast Protection line in r4_attack_effect_shield.
- **Files:** Attack_Effects.gd

### 115. [x] ex8-21 Pelipper — Bay Dance  (effect) [EASY]
- **Done:** Bay Dance stores the user (ex8_bay_dance_src_pending -> ex8_bay_dance_src at turn start); _hook_ex8_bay_dance requires that attacker and the opposing Active as defender.
- **Problem:** 'During your next turn, if any of your CURRENT Active Pokemon does damage to any Defending Pokemon, +30.' The buff is a side-wide flag that boosts whatever Pokemon is Active next turn (switch in a big attacker after Bay Dance = +30 it should not get), and it also boosts damage to Benched Pokemon from the Active (hook does not check defender is Active).
- **Evidence:** Attack_Effects.gd:25941-25944 sets side flag; Powers_And_Bodies_Effects.gd:15218 _hook_ex8_bay_dance checks only attacker == current Active; Main_Match_Core_Gameplay_Script.gd:8334-8343 promotes flag
- **Proposed fix:** Store the Bay Dance user's instance id (e.g. main.player_ex8_bay_dance_id = attacker.get_instance_id()) and in _hook_ex8_bay_dance require attacker.get_instance_id() == that id AND defender is the opposing Active.
- **Files:** Attack_Effects.gd, Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 116. [x] ex8-51 Weezing — Liability  (effect) [EASY]
- **Done:** Liability: is_protected_from_effects guard + gym1_place_counters to 10 HP.
- **Problem:** Sets defender.current_hp = 10 directly, checking only is_invincible: ignores is_protected_from_effects (e.g. Silcoon Advanced Armor vs Evolved Weezing, Fluff heads, Psychic Shield-style shields) and bypasses the damage-counter placement path (no counter animation, Mirror-type hooks), uses hard-coded floating-label coordinates.
- **Evidence:** Attack_Effects.gd:26131-26135 execute_ex8_liability
- **Proposed fix:** Replace with `if defender != null and defender.current_hp > 10 and not is_protected_from_effects(defender): await gym1_place_counters(defender, defender.current_hp - 10, not is_opponent)` (as Powerful Hand does at :25822).
- **Files:** Attack_Effects.gd

### 117. [x] ex8-85 Crystal Shard — CPU score  (cpu) [OPUS]
- **Done:** ex8-85 now uses _cpu_score_crystal_shard().
- **Problem:** Flat 30.0 (just above the 29.9 threshold) = always played onto something, even when making the holder Colorless throws away Weakness on the opponent's Active. ex14-76 (same card text) already uses situational _cpu_score_crystal_shard.
- **Evidence:** CPU_AI.gd:5653 `"ex8-85": return 30.0`; CPU_AI.gd:~5808 ex14-76 -> _cpu_score_crystal_shard()
- **Proposed fix:** Change ex8-85 to `return _cpu_score_crystal_shard()`.
- **Files:** CPU_AI.gd

### 118. [x] ex8-86 Energy Charge — CPU score  (cpu) [OPUS]
- **Done:** New _cpu_score_ex8_energy_charge: -100 with no Energy in discard, 10 with > 4 Energy left in deck, else 25 + 10 per (max 2).
- **Problem:** Flat 30.0 (above threshold) = always played, even with 0 Energy in the discard pile or plenty of Energy left in deck (wastes a card, thins nothing).
- **Evidence:** CPU_AI.gd:5654
- **Proposed fix:** Return -100 when opponent_discard_pile has no Energy; otherwise scale with Energy in discard vs Energy left in deck (e.g. 25 + 10*min(2,discard_energy) when deck energy is low).
- **Files:** CPU_AI.gd

### 119. [x] ex8-88 Master Ball — CPU score  (cpu) [OPUS]
- **Done:** New _cpu_score_ex8_master_ball: -100 on a thin / Pokémon-less deck, else _cpu_score_poke_ball() + 8.
- **Problem:** Flat 55.0: CPU always plays it, even with a full Bench and nothing to evolve, or a thin deck. Should be scored like other Pokemon searches (ex14-82 Poke Ball uses _cpu_score_poke_ball).
- **Evidence:** CPU_AI.gd:5656
- **Proposed fix:** Score with the existing Pokemon-search heuristic (e.g. _cpu_score_poke_ball()/_cpu_score_evolution_search-style: value only when a Basic would fit on the Bench or an Evolution in deck matches a Pokemon in play), -100 when deck < 2.
- **Files:** CPU_AI.gd

### 120. [x] ex8-91 Space Center — CPU score  (cpu) [OPUS]
- **Done:** _cpu_score_stadium_generic: ex8-91 Space Center +-12 per Basic non-ex non-owner Body Pokémon (theirs - mine); ex8-89 Meteor Falls +-10 per Evolved non-ex (mine - theirs).
- **Problem:** No card-specific branch in _cpu_score_stadium_generic: CPU plays Space Center at 32 even when it switches off its OWN Basic Poke-Bodies and none of the player's.
- **Evidence:** CPU_AI.gd _cpu_score_stadium_generic (no ex8-91 / ex8-89 case)
- **Proposed fix:** Add `"ex8-91": return s + 12.0 * (count of player's Basic non-ex non-owner Pokemon with a Poke-Body - same for CPU)`; and `"ex8-89"` (Meteor Falls): s + 10*(CPU evolved non-ex with useful pre-evo attacks - player's).
- **Files:** CPU_AI.gd

### 121. [x] ex8-92 Strength Charm — CPU score  (cpu) [OPUS]
- **Done:** New _cpu_score_strength_charm for ex8-92 / ecard1-150 / ex4-74 / ex15-81: 70 when +10 turns the Active's best payable attack into a KO, 25 otherwise, low when it can't attack.
- **Problem:** Flat 35.0: played on any Pokemon any turn, though it is discarded at end of the turn the holder attacks; best played on the Active the turn the +10 changes a KO.
- **Evidence:** CPU_AI.gd:5658 (same flat 35 for ecard1-150/ex4-74/ex15-81)
- **Proposed fix:** Score situationally: high when Active can attack this turn and +10 reaches a KO (r4_would_ko with +10), low/negative otherwise; attach to the Active.
- **Files:** CPU_AI.gd

### 122. [x] ex9-4 Gardevoir — Heal Dance (CPU)  (cpu) [OPUS]
- **Done:** CPU Water Cyclone / Heal Dance / Form Change / Baby Evolution use is_power_blocked (Wise Aura, Battle Frontier...) instead of is_power_blocked_by_status.
- **Problem:** CPU uses Heal Dance / Water Cyclone / Form Change / Baby Evolution even while Wise Aura (Medicham ex Active, either side) or another Poké-Power lock is up: cpu_phase_ex9_powers gates only on is_power_blocked_by_status + Toxic/Goop Gas; it announces the power and runs it.
- **Evidence:** Powers_And_Bodies_Effects.gd:15543-15570 (cpu_phase_ex9_powers), :15106 (Form Change CPU), :12176 (Baby Evolution CPU) use is_power_blocked_by_status only
- **Proposed fix:** Replace `not is_power_blocked_by_status(x)` with `not is_power_blocked(x)` in cpu_phase_ex9_powers (Water Cyclone + Heal Dance), the Form Change block (~15106) and cpu_phase_ex2_powers Baby Evolution (~12176); or use _cpu_power_free(x, false) which already calls is_power_blocked.
- **Files:** Powers_And_Bodies_Effects.gd

### 123. [x] gym1-11 Rocket's Hitmonchan — Crosscounter  (effect) [EASY]
- **Done:** clear_all_statuses resets counter_attack_double, counter_attack_fixed and damage_halved_next_turn.
- **Problem:** counter_attack_double (and Fire Wall's counter_attack_fixed, Deflector's damage_halved_next_turn) are cleared only by clear_jungle_defensive_statuses on the ACTIVE Pokemon at the end of the opponent's turn. If the Pokemon is switched to the Bench during that turn (Whirlwind/Gust/retreat), the flag stays on it and fires on a later turn.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:8699-8707 (only clears the active passed in from :8412/:8438); clear_all_statuses (Main:11120) doesn't reset these fields.
- **Proposed fix:** In Main.clear_all_statuses() also reset `counter_attack_double=false`, `counter_attack_fixed=0`, `damage_halved_next_turn=false`, or in clear_jungle_defensive_statuses loop over active + bench of that side.
- **Files:** Main_Match_Core_Gameplay_Script.gd

### 124. [x] gym1-14 Sabrina's Gengar — Call of the Night  (effect) [EASY]
- **Done:** Call of the Night: both heads checks is_protected_from_effects / check_transparency before shuffling.
- **Problem:** The both-heads shuffle of the Defending Pokemon is an attack effect, but it ignores 'prevent all effects of attacks' shields (Agility-style is_invincible after damage was blocked, Transparency, effect shields). Take Away checks is_protected_from_effects; Call of the Night doesn't.
- **Evidence:** Attack_Effects.gd:5504-5515 — goes straight to gym1_shuffle_into_deck(defender, ...) after the flip.
- **Proposed fix:** Before shuffling (Attack_Effects.gd:5510) add `if is_protected_from_effects(defender) or await main.powers_and_bodies.check_transparency(defender): return` (same guard as execute_take_away at :5363).
- **Files:** Attack_Effects.gd

### 125. [x] gym2-10 Koga's Ditto — Giant Growth  (effect) [EASY]
- **Done:** Giant Growth ending keeps the damage: current_hp = real max - damage taken (min 0, KO handled by the next KO check).
- **Problem:** When Giant Growth ends (Ditto is Benched), the damage counters on Ditto are lost. Code caps current_hp at the printed 40 instead of keeping the damage. Example: max HP 80 with 30 damage (50 HP left) becomes 40/40 when Benched, when it should be 10/40. If Ditto has 40 or more damage it should be Knocked Out.
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:11172-11177 (clear_all_statuses) — `if pokemon.current_hp > real_max: pokemon.current_hp = real_max` throws the damage away
- **Proposed fix:** In clear_all_statuses keep the damage. Read `var dmg = pokemon.get_max_hp() - pokemon.current_hp` BEFORE resetting max_hp_override, then set `pokemon.current_hp = real_max - dmg` (allow <=0 and let check_all_knockouts handle the KO; or clamp to 0)
- **Files:** Main_Match_Core_Gameplay_Script.gd

### 126. [x] gym2-3 Brock's Ninetales — Shapeshift  (cpu) [OPUS]
- **Done:** New _cpu_pick_shapeshift_form (old rule + form HP vs damage on Ninetales + Weakness to the player's Active); the CPU phase only announces when it returns a form, and power_shapeshift uses it. The 'discard form' half stays player-only.
- **Problem:** The CPU announces Shapeshift whenever it holds any Stage 1 or Stage 2 card, but power_shapeshift's CPU branch then returns without attaching when no form beats Ninetales' own best usable attack damage, or when every Evolution in hand has a valid evolve target. This is announce-then-skip, against the rule that the CPU decides before announce_cpu_power. The CPU also never uses the 'discard the Evolution card' half of the power (for example to get back to Ninetales' own HP or attacks), and it ignores the form's HP and Weakness when choosing.
- **Evidence:** Powers_And_Bodies_Effects.gd:4874-4887 (has_evo check only) vs 4110-4125 (CPU selection can return null after the announce)
- **Proposed fix:** Split the CPU choice out of power_shapeshift into a pure helper `_cpu_pick_shapeshift_form(ninetales) -> card_object` (same logic as 4110-4123, plus a score for form HP vs current damage and Weakness to the player's Active types). Call it in cpu_phase_gym_powers and only announce + attach when it returns non-null (pass the pick into power_shapeshift)
- **Files:** Powers_And_Bodies_Effects.gd

### 127. [x] gym2-35 Brock's Primeape — Scram  (effect) [EASY]
- **Done:** check_scram calls card_ops.reset_returned_pokemon before the shuffle and handle_post_knockout when it was the Active; new Powers.sweep_scram() runs at the start of check_all_knockouts so recoil / Poison / Bench damage / counters trigger it too.
- **Problem:** (1) Scram is checked only in the on-damage hook for the attacked Pokemon. Text says 'If Brock's Primeape ever has exactly 10 HP left', so its own Mega Thrash recoil (20), Poison/Burn between turns, bench damage and damage-counter effects that leave it at 10 HP never trigger it. (2) When it does trigger, the card goes into the deck without clear_all_statuses. Poison, Special Conditions and effect flags stay on the card object, and a Primeape later played from the deck carries them. (3) If it Scrams as the Active during the opponent's attack, nothing in check_scram fills the empty Active spot (Rebellion and Obscuring Gas call handle_post_knockout, Scram does not).
- **Evidence:** Powers_And_Bodies_Effects.gd:252 (only registered as an _on_damage_hook); 4503-4537 (check_scram: no main.clear_all_statuses, no handle_post_knockout)
- **Proposed fix:** In check_scram call main.clear_all_statuses(pokemon, is_opp) before moving the card. If it was the Active, await main.handle_post_knockout(is_opp) after the shuffle (or return a flag the caller handles). Add a check_scram sweep for both sides' Primeapes after self-damage (gym2_self_damage), after between-turn Poison/Burn and after bench damage (for example inside check_all_knockouts before the KO pass)
- **Files:** Powers_And_Bodies_Effects.gd, Attack_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 128. [x] gym2-38 Erika's Bellsprout — Soak Up  (cpu) [OPUS]
- **Done:** Soak Up CPU gate uses the executor's test (_cpu_type_surplus > 0 and a basic Grass Energy).
- **Problem:** The CPU announces Soak Up and then often moves nothing. The pre-check in cpu_phase_gym_powers accepts any attached card that provides Grass (Rainbow, Photosynthesis and so on) with no surplus test. power_soak_up's CPU branch only takes BASIC Grass Energy that the source can spare (_cpu_type_surplus > 0), so it breaks out with 0 moved after the announcement. It also burns power_used_this_turn.
- **Evidence:** Powers_And_Bodies_Effects.gd:4893-4911 (pre-check uses get_energy_provided_by_card 'Grass' and no surplus) vs 4581-4596 (_is_basic_energy_of + _cpu_type_surplus > 0)
- **Proposed fix:** In cpu_phase_gym_powers replace the has_grass loop with the same test the executor uses: any other own Pokemon sp with `_cpu_type_surplus(sp, "Grass") > 0` and at least one `_is_basic_energy_of(e, "Grass")`. Only then announce_cpu_power + power_soak_up
- **Files:** Powers_And_Bodies_Effects.gd

### 129. [x] neo1-17 Typhlosion — Fire Recharge  (cpu) [OPUS]
- **Done:** Fire Recharge CPU target = cpu_pick_benefit_recipient over its Fire Pokémon; gate also needs an own Fire Pokémon with an unmet attack cost.
- **Problem:** CPU attaches the recovered Fire Energy to fire_poke[0] (Active first, else first Bench slot) regardless of who needs it; it also activates (and announces) the power even when it has no Fire Pokémon that needs Energy.
- **Evidence:** Powers_And_Bodies_Effects.gd:5731-5733 `target = fire_poke[0]; energy = fire_in_discard[0]`; CPU gate at 6487-6498 only checks Fire Energy in discard
- **Proposed fix:** CPU branch: `target = main.cpu_ai.cpu_pick_benefit_recipient(fire_poke, "energy", fire_in_discard[0])` (fallback fire_poke[0]). In cpu_phase_neo1_powers also require at least one own Fire Pokémon in play before announcing.
- **Files:** Powers_And_Bodies_Effects.gd

### 130. [x] neo1-18 Typhlosion — Fire Boost  (choice) [OPUS]
- **Done:** Fire Boost: the player picks 0-4 Fire Energy on one prompt_select_cards screen; CPU takes up to 4.
- **Problem:** 'search your deck for UP TO 4 Fire Energy cards' — the player is never shown the deck or allowed to pick fewer/specific cards; the first 4 Fire Energy found are attached automatically.
- **Evidence:** Powers_And_Bodies_Effects.gd:5663-5671 trigger_neo1_fire_boost loops fire_in_deck[0..picks) for both sides
- **Proposed fix:** For the player branch: `var picks = await main.card_ops.prompt_select_cards(fire_in_deck, 0, min(4, fire_in_deck.size()), "FIRE BOOST", "Choose up to 4 Fire Energy to attach to Typhlosion", "ATTACH")` then attach those; CPU keeps taking min(4, n). Shuffle afterward either way (also shuffle when 0 picked).
- **Files:** Powers_And_Bodies_Effects.gd

### 131. [x] neo1-22 Elekid — Playful Punch  (cpu) [OPUS]
- **Done:** Playful Punch's 'can't attack anyway' branch only in the final power pass (cpu_final_power_check); the KO branch unchanged.
- **Problem:** CPU fires Playful Punch (which ENDS the turn) whenever its Active can't currently pay for an attack — this runs in the power phase, so it can end the turn before the CPU has attached its Energy, evolved or played Trainers that would have enabled an attack (or retreated).
- **Evidence:** Powers_And_Bodies_Effects.gd:6550-6560 pp_use = no attack payable NOW; no check of energy-attach-this-turn / hand Energy / evolutions
- **Proposed fix:** Only use the 'no attack' branch after the CPU has finished attaching Energy / playing Trainers (move Playful Punch to a late phase just before cpu_phase_attack), and require that no attack becomes payable with an Energy still in hand when energy_attached_this_turn is false. Keep the KO branch as is.
- **Files:** Powers_And_Bodies_Effects.gd, CPU_AI.gd

### 132. [x] neo1-39 Ledian — Baton Pass  (anim) [EASY]
- **Done:** Baton Pass captures each Energy's rect and fly_attach-es it to the Benched target.
- **Problem:** Grass Energy cards are moved from Ledian to the Benched Grass Pokémon with no flight animation (they just reappear on the target).
- **Evidence:** Attack_Effects.gd:9853-9857 execute_neo1_baton_pass — attached_energies.erase/append loop with only play_energy_attach_sfx(), no capture_rect/fly_attach
- **Proposed fix:** In the loop at Attack_Effects.gd:9854, capture `var r = main.card_ops.capture_rect(e, "attached", is_opponent)` before erase, then `await main.card_ops.fly_attach(e, "attached", r)` after appending to target (same pattern as execute_electric_current:5808-5811); bail-check after each.
- **Files:** Attack_Effects.gd

### 133. [x] neo1-47 Quilava — Char  (effect) [EASY]
- **Done:** perform_evolution carries has_char_counter to the evolution; the leaving-play cleanup and reset_returned_pokemon clear it.
- **Problem:** has_char_counter is never cleared or carried: (a) a Knocked Out / discarded / scooped-up Pokémon keeps the Char counter and starts taking Char damage again if it returns to play (Super Rod, Revival etc.); (b) when the Char-countered Pokémon evolves, the counter is lost because the new evolution card object has has_char_counter=false ('Char counters stay on the Pokémon as long as it's in play').
- **Evidence:** grep has_char_counter: only Card_Class_Object_Script.gd:114 (decl), Attack_Effects.gd:9521/9526 (set), Powers_And_Bodies_Effects.gd:5493 (read). No reset in Card_Ops.send_to_discard (~399) / discard_all_attachments, and perform_evolution (Main:8807) doesn't copy it.
- **Proposed fix:** In Card_Ops.send_to_discard (where #404 resets current_hp for Pokémon) and wherever a Pokémon returns to hand/deck, set card.has_char_counter = false. In Main.perform_evolution copy `evolved.has_char_counter = base.has_char_counter` (and clear it on the pre-evolution). Same for devolve helpers (execute_devolution_beam, _ex2_devolve_pokemon).
- **Files:** Card_Ops.gd, Main_Match_Core_Gameplay_Script.gd, Attack_Effects.gd

### 134. [x] neo2-61 Pineco — Burst  (effect) [EASY]
- **Done:** Data fix, not code: the single flip in the handler matches the real card; removed the stray second 'Flip a coin.' from neo2-61's text in Card_Set_Data/neo2.json (seed holds ids only).
- **Problem:** Card text has TWO independent coin flips: flip 1 heads -> 40 to Pineco itself + 10 to every Benched Pokemon; flip 2 tails -> attack does nothing (no 40 to the Defender). Code flips ONE coin: heads = everything (40 to defender + self 40 + bench 10), tails = nothing. So Pineco can never deal 40 without hurting itself, and never self-destruct-free. (If the JSON text is a mis-transcription, fix the data instead.)
- **Evidence:** Attack_Effects.gd:11112-11142 execute_neo2_burst: single flip_coin; Card_Set_Data/neo2.json neo2-61 text 'Flip a coin. If heads, Pineco does 40 damage to itself ... Flip a coin. If tails, this attack does nothing'.
- **Proposed fix:** execute_neo2_burst: coin_a = flip (self 40 via gym2_self_damage + 10 to each bench via apply_bench_damage if heads); coin_b = flip; if coin_b tails -> no damage to defender (message), else deal 40 to defender via gym1_hit_active. Order: resolve 'does nothing' flip first only if card text intends it; simplest faithful order = flip both up front, if coin_b tails skip the defender damage, apply coin_a side effects regardless. Update CPU estimate (_r3_estimate / cpu_utility) to 0.5*40 expected and count 0.5*40 self-damage.
- **Files:** Attack_Effects.gd, Card_Set_Data/neo2.json

### 135. [x] neo4-1 Dark Ampharos — Conductivity  (effect) [EASY]
- **Done:** check_neo4_conductivity awaits apply_bench_damage then check_all_knockouts; both callers (Main player attach, CPU attach) await it.
- **Problem:** Conductivity's 10 damage is applied without await and with no Knock Out check, so a Pokemon reduced to 0 HP stays in play until some later check_all_knockouts.
- **Evidence:** Powers_And_Bodies_Effects.gd:7647 `main.card_ops.apply_bench_damage(target, 10, target_is_opponent, false)` not awaited; callers Main_Match_Core_Gameplay_Script.gd:7594 and CPU_AI.gd:2435 neither await nor check KOs.
- **Proposed fix:** `await main.card_ops.apply_bench_damage(...)` then `await main.check_all_knockouts()`; make both callers `await powers_and_bodies.check_neo4_conductivity(...)` + _should_bail.
- **Files:** Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd, CPU_AI.gd

### 136. [x] neo4-107 Shining Charizard — White-hot Flame  (effect) [EASY]
- **Done:** White-hot Flame recoil is awaited (+ bail check). Also awaited the same un-awaited gym2_self_damage in Lightning Tackle (~12053) and the 30 recoil at ~12620.
- **Problem:** Tails recoil gym2_self_damage is not awaited: its HP change happens after an internal await (show_self_damage_modifiers waits 0.5s per PlusPower/Defender), so check_all_knockouts can run before the 30 recoil lands (self-KO missed until a later check), and its 'TOOK 30 DAMAGE' message overlaps the 'WHITE-HOT FLAME! TAILS!' message.
- **Evidence:** Attack_Effects.gd:14974 `gym2_self_damage(attacker, is_opponent, 30)` without await; gym2_self_damage (6366) awaits before setting current_hp at 6379.
- **Proposed fix:** `await gym2_self_damage(attacker, is_opponent, 30)` + `if main._should_bail(): return`.
- **Files:** Attack_Effects.gd

### 137. [x] neo4-108 Shining Kabutops — Lightning Cut  (effect) [EASY]
- **Done:** Lightning Cut 10 recoil awaited (+ bail check).
- **Problem:** Tails 10 recoil via un-awaited gym2_self_damage: recoil may land after check_all_knockouts and messages overlap.
- **Evidence:** Attack_Effects.gd:15057 `gym2_self_damage(attacker, is_opponent, 10)` without await.
- **Proposed fix:** `await gym2_self_damage(attacker, is_opponent, 10)` then bail check.
- **Files:** Attack_Effects.gd

### 138. [x] neo4-19 Dark Omastar — Prehistoric Water  (effect) [EASY]
- **Done:** Prehistoric Water only offers evolved Pokémon that are not is_protected_from_effects.
- **Problem:** Devolving ignores attack-effect shields: if the chosen evolved Pokemon is the opponent's Active and is protected from attack effects (Light Dragonite Light Wave, Agility/Protective Wave invincibility, Unown [Q] Quicken), it is still devolved.
- **Evidence:** Attack_Effects.gd:13732-13799 execute_neo4_prehistoric_water — no is_protected_from_effects(chosen) check anywhere (other neo4 handlers like Tusk Toss 13253 do check).
- **Proposed fix:** Build `evolved` from targets filtered by `not (t == opp_active and is_protected_from_effects(t))` (Quicken also covers Benched Unown — use is_protected_from_effects for any target if it handles bench), or after the heads flip bail with a 'PROTECTED' message when is_protected_from_effects(chosen).
- **Files:** Attack_Effects.gd

### 139. [x] neo4-26 Light Piloswine — Fluffy Wool  (effect) [EASY]
- **Done:** Fluffy Wool returns when is_power_blocked(defender) or Asleep/Confused/Paralyzed.
- **Problem:** Fluffy Wool only checks Asleep/Confused/Paralyzed; it still triggers under Toxic Gas / Goop Gas / power-disabled effects (e.g. Stun Wave).
- **Evidence:** Powers_And_Bodies_Effects.gd:7669 `if defender.is_status_blocked(): return` (Card_Class_Object_Script.gd:253 is status only).
- **Proposed fix:** `if is_power_blocked(defender) or defender.is_status_blocked(): return`.
- **Files:** Powers_And_Bodies_Effects.gd

### 140. [x] pop4-2 Deoxys δ — Crystal Laser  (effect) [EASY]
- **Done:** Crystal Laser stores the Defender (player/opponent_dragon_dance_pending_target -> _target) and the hook requires attacker == Deoxys (#78) and defender == that target; Form Change re-points the stored Deoxys to the new form card. Covers ex13-5 and pop4-2.
- **Problem:** Text: 'During your next turn, Deoxys's attacks do 40 more damage to the Defending Pokémon'. execute_ex13_crystal_laser reuses the side-wide Dragon Dance buff, so (a) any Pokémon Active next turn gets +40, not only Deoxys, and (b) the +40 applies against any defender, including a new Active the opponent promoted or switched in.
- **Evidence:** Attack_Effects.gd:30183-30194 sets main.*_dragon_dance_pending = 40; Powers_And_Bodies_Effects.gd:15230 _hook_dragon_dance checks neither attacker identity nor defender
- **Proposed fix:** Give Crystal Laser its own effect: attacker.set_effect('crystal_laser', ...) with data {target_uid: defender instance, expires next own turn end}; add a damage-modifier hook adding +40 only when attacker has the effect and defender is that stored card. Keep Form Change carrying effects (the text says effects move to the new Deoxys). Same fix applies to ex13 Deoxys δ Crystal Laser.
- **Files:** Attack_Effects.gd, Powers_And_Bodies_Effects.gd


## LOW severity

### 141. [x] base2-15 Vileplume — Heal  (effect) [EASY]
- **Done:** CPU Vileplume Heal skips (before announcing) when modify_heal_amount(10) <= 0 and heals through card_ops.heal_pokemon.
- **Problem:** CPU branch of Heal sets current_hp directly (+10) and skips the match-effect heal gate (no_healing / healing_multiplier) that the player branch applies via match_effects.modify_heal_amount; under a no-healing match rule the CPU still heals.
- **Evidence:** Powers_And_Bodies_Effects.gd:2332 — most_damaged.current_hp = min(max, current_hp + 10); player branch at :1457 uses match_effects.modify_heal_amount
- **Proposed fix:** In the CPU Vileplume block (~2318) compute rule_heal = main.match_effects.modify_heal_amount(10, true) and skip the power entirely (before announce) when <= 0; or route the heal through main.card_ops.heal_pokemon(most_damaged, 10, true).
- **Files:** Powers_And_Bodies_Effects.gd

### 142. [x] base3-33 Gastly — Energy Conversion  (effect) [EASY]
- **Done:** Energy Conversion: Pokémon Tower shows its message and skips only the retrieval; the 10 self-damage still happens.
- **Problem:** With Pokemon Tower in play the handler returns before the 10 self-damage. Tower only stops the Energy going to hand; 'Gastly does 10 damage to itself' still happens.
- **Evidence:** Attack_Effects.gd:3936-3939 execute_energy_conversion early return
- **Proposed fix:** In execute_energy_conversion, when check_pokemon_tower_blocks_recovery() is true show the Tower message, skip the retrieval block, but fall through to the self-damage at lines 3992-4000.
- **Files:** Attack_Effects.gd

### 143. [x] base5-13 Dark Vileplume — Petal Whirlwind  (data) [EASY]
- **Done:** base5.json Dark Vileplume Petal Whirlwind text 'Flip a coins.' -> 'Flip 3 coins.' (seed holds ids only).
- **Problem:** Card text reads 'Flip a coins.' (garbled); the real card is 'Flip 3 coins.' The dedicated handler hardcodes 3 coins so play is correct, but the displayed text and any text-based CPU estimator (parse_coin_flip_count) read it wrong.
- **Evidence:** Card_Set_Data/base5.json Dark Vileplume Petal Whirlwind text; Attack_Effects.gd:4450 execute_petal_whirlwind uses range(3)
- **Proposed fix:** Edit base5.json: 'Flip a coins.' -> 'Flip 3 coins.'
- **Files:** Card_Set_Data/base5.json

### 144. [x] basep-12 Mewtwo — Energy Control  (anim) [EASY]
- **Done:** not a bug - Card_Ops.capture_rect ignores side_opp for the 'attached' zone (the rect is looked up from the card / its holder), so the flight already starts at the right place.
- **Problem:** capture_rect for the moved Energy is always taken from the player side (third arg false) even when the player attacks and the Energy sits on a CPU Pokemon, so the flight starts from the wrong place.
- **Evidence:** Attack_Effects.gd:8765 capture_rect(energy, 'attached', false)
- **Proposed fix:** Pass opp_is (the side that owns source_pokemon) instead of false.
- **Files:** Attack_Effects.gd

### 145. [x] ecard1-16 Machamp — Terraforming  (choice) [OPUS]
- **Done:** Terraforming uses r3_reorder_top (prompt_reorder_cards for the player, keep-value order for the CPU) with N read from the text - also fixes ex16-1 Aggron (shares the handler, was 4 not 5).
- **Problem:** Player reorder uses the legacy Pokédex reorder state machine (pokedex_cards / trainer_reorder_done) instead of the agreed Card_Ops.prompt_reorder_cards helper; the CPU uses _cpu_pokedex_priority instead of the shared r3_reorder_top heuristic.
- **Evidence:** Powers_And_Bodies_Effects.gd:9111-9138
- **Proposed fix:** Replace the whole body after the power_used flag with `await main.attack_effects.r3_reorder_top(is_opponent, 4, is_opponent, "TERRAFORMING")` (Attack_Effects.gd:32612), which uses prompt_reorder_cards for the player and cpu_rank_keep_value for the CPU.
- **Files:** Powers_And_Bodies_Effects.gd

### 146. [x] ecard1-2 Ampharos — Energy Connect  (anim) [EASY]
- **Done:** not a bug - same as #144: capture_rect's side argument is unused for 'attached'; all four sites already fly from the right Pokémon.
- **Problem:** Energy-move flights capture the source rect with is_opponent hard-coded false, so when the CPU moves Energy the card flies from the wrong side of the board. Same pattern in Plunge (Poliwrath ecard1-24), Energy Patch (Pichu ecard1-22) and Reflect Energy (Electabuzz ecard1-76).
- **Evidence:** Powers_And_Bodies_Effects.gd:8579 and :8916 `capture_rect(energy, "attached", false)`; Attack_Effects.gd:16111 and :16228 same.
- **Proposed fix:** Pass is_opponent (the owner side) as the third argument of capture_rect at all four sites.
- **Files:** Powers_And_Bodies_Effects.gd, Attack_Effects.gd

### 147. [x] ecard1-4 Blastoise — Jet Stream  (cpu) [OPUS]
- **Done:** New _cpu_jet_stream_worth: only when Blastoise can spare an Energy (still has a payable attack, or can't attack anyway) or removing one stops the player's Active's attack.
- **Problem:** CPU uses Jet Stream whenever the Defending Pokémon has any Energy, even when discarding one of Blastoise's own Energy on heads drops it below Energy Cannon's cost (WWC) and the defender's Energy loss doesn't matter.
- **Evidence:** Powers_And_Bodies_Effects.gd:9174-9180
- **Proposed fix:** Only trigger when Blastoise has more Energy than its best attack needs, or when the player's Active is exactly at its attack cost (removal denies its attack).
- **Files:** Powers_And_Bodies_Effects.gd

### 148. [x] ecard2-82 Hitmontop — Triple Spin  (choice) [OPUS]
- **Done:** Triple Spin's switch prompt is no longer cancelable ('(optional)' dropped); null falls back to own_bench[0].
- **Problem:** Text: 'If you get 2 or more heads, switch Hitmontop with 1 of your Benched Pokémon, if any' is mandatory, but the player prompt is cancellable so the player can skip the switch (CPU always switches).
- **Evidence:** Attack_Effects.gd:17108 prompt_select_card(..., "SWITCH", true) — last arg allows cancel; message says '(optional)'.
- **Proposed fix:** Pass false for the cancellable arg, drop '(optional)' from the caption, and fall back to own_bench[0] if null.
- **Files:** Attack_Effects.gd

### 149. [x] ecard2-H15 Lanturn — Ion Coating  (effect) [EASY]
- **Done:** clear_all_statuses clears the ecard2_ion_coating effect (retreat / switch); returning to hand already wiped active_effects.
- **Problem:** 'This effect ends if your Active Pokémon retreats or is returned to your hand' not implemented: the effect is set on the Pokémon until end of turn, so after retreating it keeps converting Lightning to Water on the Bench (and the new Active gets nothing).
- **Evidence:** Powers_And_Bodies_Effects.gd:9804 active.set_effect("ecard2_ion_coating", "end_of_own_turn"); no clear on retreat/switch.
- **Proposed fix:** Clear the effect in the retreat/switch path (e.g. in Main retreat completion and animate_retreat data swap: old_active.clear_effect("ecard2_ion_coating")).
- **Files:** Powers_And_Bodies_Effects.gd, Main_Match_Core_Gameplay_Script.gd

### 150. [x] ecard2-H15 Lanturn — Ion Coating  (cpu) [OPUS]
- **Done:** CPU Ion Coating: Lanturn anywhere in play; used when the effect on the current Active lowers its cheapest unmet attack cost.
- **Problem:** Ion Coating affects whatever Pokémon is Active (Lanturn may be Benched), but the CPU only considers it when Lanturn itself is the Active and checks Lanturn's own attacks.
- **Evidence:** Powers_And_Bodies_Effects.gd ~10439 `ion_coating == main.opponent_active_pokemon` and loop over ion_coating's attacks.
- **Proposed fix:** Find Lanturn anywhere in play; test main.opponent_active_pokemon's attacks for a Water shortfall that Lightning Energy would cover.
- **Files:** Powers_And_Bodies_Effects.gd

### 151. [x] ecard2-H16 Magneton — Steel Wave  (effect) [EASY]
- **Done:** Steel Wave uses get_effective_types() for the Defender and the Benched Pokémon.
- **Problem:** 'Same type (color) as the Defending Pokémon' uses printed metadata types, ignoring type changes (Crystal Type, Crystal Shard etc.) on the Defender or Benched Pokémon.
- **Evidence:** Attack_Effects.gd:17131/17135 use metadata.get("types").
- **Proposed fix:** Use defender.get_effective_types() and bp.get_effective_types().
- **Files:** Attack_Effects.gd

### 152. [x] ecard2-H22 Slowking — Shuffle Attack  (effect) [EASY]
- **Done:** Shuffle Attack counts the Defender's Energy BEFORE the damage / KO.
- **Problem:** The number of cards to look at is counted AFTER damage/KO; if the 40 damage Knocks Out the Defending Pokémon its Energy is already discarded, so n=0 and the effect is skipped.
- **Evidence:** Attack_Effects.gd:16830-16834: gym1_hit_active + check_all_knockouts run before `var n = defender.attached_energies.size()`.
- **Proposed fix:** Capture `var n = defender.attached_energies.size() if defender != null else 0` before gym1_hit_active.
- **Files:** Attack_Effects.gd

### 153. [x] ecard2-H5 Bellossom — Flower Supplement  (cpu) [OPUS]
- **Done:** Flower Supplement CPU: recipient first (cpu_pick_benefit_recipient), then _r3_cpu_needed_energy for it.
- **Problem:** CPU picks the Energy to attach with cpu_pick_best_keep(basics) (the card it most wants to KEEP in hand) rather than the one the recipient needs.
- **Evidence:** Powers_And_Bodies_Effects.gd ~9560 `energy = main.cpu_ai.cpu_pick_best_keep(basics)`.
- **Proposed fix:** Choose recipient first, then energy = main.attack_effects._r3_cpu_needed_energy(basics, target).
- **Files:** Powers_And_Bodies_Effects.gd

### 154. [x] ecard2-H6 Blissey — Happy Healing  (effect) [EASY]
- **Done:** Happy Healing heals 10 x r4_energy_amount(blissey).
- **Problem:** Heals 10 per Energy CARD attached (attached_energies.size()), but text counts Energy (units) — Double Colorless/Boost Energy count as more.
- **Evidence:** Powers_And_Bodies_Effects.gd:9613 `var heal = blissey.attached_energies.size() * 10`.
- **Proposed fix:** Sum provided units: for e in attached_energies: heal += 10 * main.get_energy_provided_by_card(e).size().
- **Files:** Powers_And_Bodies_Effects.gd

### 155. [x] ecard3-61 Granbull — Fling  (effect) [EASY]
- **Done:** basep Fling (also Granbull / Machop): KO check before the switch; no switch when the Defender was KO'd, replaced or is protected.
- **Problem:** Fling (also ecard3-74 Machop) forces the switch even when the damage just Knocked Out the Defending Pokémon or the Defender is protected — the 0-HP Pokémon is swapped to the Bench before the KO check, giving the opponent a pointless switch prompt.
- **Evidence:** Attack_Effects.gd:9060 execute_basep_fling — hits, then apply_force_switch without check_all_knockouts / _ko_alive(defender) first (execute_ex5_gust_opp_choose at 23202 does this correctly).
- **Proposed fix:** In execute_basep_fling: after gym1_hit_active call await main.check_all_knockouts(); only call apply_force_switch if _ko_alive(defender) and defender is still the Active (or simply route 'fling' with '(do the damage before switching' text to execute_ex5_gust_opp_choose).
- **Files:** Attack_Effects.gd

### 156. [x] ecard3-H18 Magneton — Attract Energy  (choice) [OPUS]
- **Done:** Attract Energy (player): every basic Energy on the other Pokémon on one prompt_select_cards screen (0..all), each flown to Magneton.
- **Problem:** 'Move any number of basic Energy' is done as a loop of single prompt_select_card picks (source, then energy, repeated) instead of one multi-pick screen.
- **Evidence:** Powers_And_Bodies_Effects.gd:11180-11197 — while loop of prompt_select_card.
- **Proposed fix:** Gather all basic Energy on the other Pokémon into one pool and call main.card_ops.prompt_select_cards(pool, 0, pool.size(), 'ATTRACT ENERGY', ...), then fly each picked card to Magneton.
- **Files:** Powers_And_Bodies_Effects.gd

### 157. [x] ex1-23 Swampert — Natural Remedy  (effect) [EASY]
- **Done:** New Powers.on_effect_attach_from_hand (Natural Cure + Natural Remedy) called from Water Call (player + CPU), Plus Energy and execute_ex5_attach_from_hand; Natural Remedy is once per turn (ex1_natural_remedy_used effect); Natural Cure now uses cure_special_conditions instead of clear_all_statuses.
- **Problem:** Only fires from the normal once-per-turn hand attach. Attaching a Water Energy from hand to this Swampert by another effect (Water Call from ex1-13 Swampert, Plus Energy etc.) never triggers it, and the 'once during your turn' limit is not tracked (relies on the single manual attach). Same gap for Natural Cure (ex1-28/32/41).
- **Evidence:** Main_Match_Core_Gameplay_Script.gd:7607-7609 and CPU_AI.gd:2448-2450 are the only callers; Powers_And_Bodies_Effects.gd power_ex1_water_call / cpu_ex1_water_call and Attack_Effects.gd execute_ex1_plus_energy don't call check_ex1_natural_remedy / check_ex1_natural_cure
- **Proposed fix:** Add a per-turn flag (e.g. set_effect('ex1_natural_remedy_used','end_of_own_turn')) checked in check_ex1_natural_remedy, and call check_ex1_natural_cure + check_ex1_natural_remedy from the from-hand attach effects (Water Call, Plus Energy, ex5 attach-from-hand helpers).
- **Files:** Powers_And_Bodies_Effects.gd, Attack_Effects.gd

### 158. [x] ex1-68 Ralts — Link Blast  (effect) [EASY]
- **Done:** Link Blast compares r4_energy_amount of both Pokémon (all Link Blast cards share it).
- **Problem:** 'Different amount of Energy attached' compares card counts, not Energy amounts (a Pokemon with 1 Double Rainbow vs 2 basics compares wrongly).
- **Evidence:** Attack_Effects.gd:18834 attacker.attached_energies.size() != defender.attached_energies.size()
- **Proposed fix:** Compare r4_energy_amount(attacker) != r4_energy_amount(defender) in execute_ex1_link_blast.
- **Files:** Attack_Effects.gd

### 159. [x] ex2-62 Duskull — Haunt  (effect) [EASY]
- **Done:** gym1_place_counters now skips opposing Pokémon that are is_protected_from_effects during an attack - fixes Haunt and every counter-placing attack.
- **Problem:** Haunt returns early only for is_invincible; gym1_place_counters also only checks is_invincible, so other 'prevent all effects of attacks' shields (is_protected_from_effects) don't stop the counter.
- **Evidence:** Attack_Effects.gd:19889 — `if defender == null or defender.is_invincible: return`; gym1_place_counters checks `pokemon.is_invincible` only
- **Proposed fix:** Change the guard to `if defender == null or is_protected_from_effects(defender): return` (or make gym1_place_counters check is_protected_from_effects for opposing Pokémon during an attack, which fixes every counter-placing attack).
- **Files:** Attack_Effects.gd

### 160. [x] ex3-100 Charizard — Collect Fire  (choice) [OPUS]
- **Done:** Collect Fire: empty pool = message and no picker; otherwise the player picks exactly min(2, pool).
- **Problem:** Heads: 'search your discard pile for 2 Fire Energy cards and attach them (1 if there is only 1)' is mandatory, but the player prompt allows min 1 out of 2. The CPU takes pool[0] with no thought (harmless, since all are Fire). If the pool is empty, prompt_select_cards is still opened with min 1.
- **Evidence:** Attack_Effects.gd:21043-21044 prompt_select_cards(pool, 1, 2, ...)
- **Proposed fix:** Build the pool first; if it is empty, show the message and return. Otherwise call prompt_select_cards(pool, min(2, pool.size()), min(2, pool.size()), ...).
- **Files:** Attack_Effects.gd

### 161. [x] ex3-21 Skarmory — Power Count  (effect) [EASY]
- **Done:** Power Count sums r4_energy_amount on both sides.
- **Problem:** 'Count the amount of Energy attached to all of your Pokémon and all of your opponent's' counts Energy cards (attached_energies.size()) on both sides, not the amount of Energy provided (DCE = 2, etc.).
- **Evidence:** Attack_Effects.gd:20271-20276 execute_ex3_power_count sums p.attached_energies.size()
- **Proposed fix:** Sum r4_energy_amount(p) for both sides.
- **Files:** Attack_Effects.gd

### 162. [x] ex4-69 Team Aqua Schemer — Supporter (CPU discard pick)  (cpu) [OPUS]
- **Done:** CPU Schemer discard: the general least-valuable Pokémon vs the least valuable team one; the team one only when it costs at most ~25 keep value more.
- **Problem:** CPU always discards the FIRST Team Aqua Pokémon in hand to get the 4th card, even if it is its only copy of a key evolution/attacker; never weighs the card's value against +1 draw.
- **Evidence:** Trainer_Effects.gd:10694-10698 — loop picks the first team-named Pokémon then breaks.
- **Proposed fix:** Rank team-named Pokémon with cpu_get_discard_priority(team_pokes,1); use it only if its keep value is below a threshold (e.g. cpu_rank_keep_value < that of the general discard pick + one card's worth), else fall back to the general cpu_get_discard_priority pick.
- **Files:** Trainer_Effects.gd

### 163. [x] ex4-71 Archie — Supporter (validator)  (effect) [EASY]
- **Done:** Validators for ex4-71 Archie / ex4-73 Maxie: 'Your Bench is full!'.
- **Problem:** Player can play Archie/Maxie with a full Bench; the Supporter is spent for nothing (no validator).
- **Evidence:** Trainer_Effects.gd:10717 _ex4_bench_team_pokemon only shows BENCH IS FULL after the card is played; no validator for ex4-71/ex4-73.
- **Proposed fix:** Add validators for ex4-71/ex4-73 returning "Bench is full!" when bench.size() >= main.get_max_bench_size() (same as Clefairy Doll validator at Trainer_Effects.gd:492).
- **Files:** Trainer_Effects.gd

### 164. [x] ex4-74 Strength Charm — Tool (CPU score)  (cpu) [OPUS]
- **Done:** Done under #121: ex4-74 now uses _cpu_score_strength_charm (70 when +10 makes the KO, else 25 / 15).
- **Problem:** Flat CPU score 35 (just above threshold) — not tied to whether the Active is about to attack or whether +10 reaches a KO.
- **Evidence:** CPU_AI.gd:5643 `"ex4-74": return 35.0`.
- **Proposed fix:** Score higher (e.g. 60) when the Active can attack this turn and +10 turns a non-KO into a KO (r4_would_ko), else ~32.
- **Files:** CPU_AI.gd

### 165. [x] ex5-29 Beldum — Metal Charge  (effect) [EASY]
- **Done:** Metal Charge places the counter with gym1_place_counters (no PlusPower / Defender modifiers).
- **Problem:** 'Put 1 damage counter on Beldum' is a damage counter, not damage, but the self-counter goes through apply_self_damage_modifiers, so a PlusPower on Beldum makes it 2 counters and a Defender on Beldum reduces it to 0.
- **Evidence:** Attack_Effects.gd:23196 execute_ex5_damage_self_counter uses main.apply_self_damage_modifiers(attacker, n*10) (Main_Match_Core_Gameplay_Script.gd:10477 adds PlusPower, subtracts Defender)
- **Proposed fix:** In execute_ex5_damage_self_counter use `attacker.current_hp = max(0, attacker.current_hp - n * 10)` (no modifiers).
- **Files:** Attack_Effects.gd

### 166. [x] ex5-8 Jirachi — Make a Wish  (effect) [EASY]
- **Done:** Make a Wish places its counter with gym1_place_counters.
- **Problem:** 'Put 1 damage counter on Jirachi' is routed through apply_self_damage_modifiers, so PlusPower/Defender attached to Jirachi change the counter (2 counters / none).
- **Evidence:** Attack_Effects.gd:22543 execute_ex5_make_a_wish
- **Proposed fix:** Use `attacker.current_hp = max(0, attacker.current_hp - 10)` without apply_self_damage_modifiers.
- **Files:** Attack_Effects.gd

### 167. [x] ex6-15 Snorlax — Rest Up  (effect) [EASY]
- **Done:** Rest Up requires not is_power_blocked(p, true) (works while Asleep).
- **Problem:** Rest Up (Poké-Body) heal between turns has no ability-blocker gate at all, so a Poké-Body lock (body_lock_active / power_disabled_until_end_of_next_turn / Imprison) does not stop it, unlike Sooth Dust / Acid Sampler / Eerie Aura right next to it.
- **Evidence:** Powers_And_Bodies_Effects.gd:8226-8236 — `if p.has_ability("Rest Up") and p.special_condition == "Asleep":` with no is_power_blocked check
- **Proposed fix:** Add `and not is_power_blocked(p, true)` (works_through_status=true since it must work while Asleep) to the Rest Up condition.
- **Files:** Powers_And_Bodies_Effects.gd

### 168. [x] ex6-4 Ditto — Form Variation  (effect) [EASY]
- **Done:** Form Variation also carries active_effects, disabled_attacks, Blind, damage reduction, Leer-style block, Char counter, markers, power_used_this_turn and placed_on_field_this_turn to the new Pokémon.
- **Problem:** Text: 'Any cards attached to Ditto, damage counters, Special Conditions, and effects on it are now on the new Pokémon.' Only energies, attached_cards, special_condition, poison/burn and HP are copied; lingering effects (card effects dictionary, disabled_attacks, damage-reduction flags, retreat locks), attached_pre_evolutions-independent state and turn-played flags are dropped, so e.g. a retreat lock or 'can't attack next turn' on Ditto is silently cleared by the swap. The new card also keeps power_used_this_turn=false.
- **Evidence:** Powers_And_Bodies_Effects.gd:13498-13506 power_ex6_form_variation copies only a handful of fields
- **Proposed fix:** Also copy the effect containers (e.g. new_basic.effects = ditto.effects.duplicate(true) or whatever card_object uses for has_effect, disabled_attacks, retreat-lock flags, turn_played) before stripping Ditto.
- **Files:** Powers_And_Bodies_Effects.gd

### 169. [x] ex7-42 Dark Weezing — Darkness Charge  (effect) [EASY]
- **Done:** Darkness Charge (ex7-42 / ex16-38) places counters with gym1_place_counters.
- **Problem:** Text 'Put 2 damage counters on Dark Weezing' — damage counters are not damage, but the handler runs them through apply_self_damage_modifiers, so PlusPower adds +10 and a Defender on Dark Weezing removes 20 (0 counters).
- **Evidence:** Attack_Effects.gd:25217 execute_ex7_self_counter_damage: attacker.current_hp -= main.apply_self_damage_modifiers(attacker, counters * 10).
- **Proposed fix:** Replace with attacker.current_hp = max(0, attacker.current_hp - counters * 10) (no modifiers), keep the HP display + KO check.
- **Files:** Attack_Effects.gd

### 170. [x] ex8-84 Balloon Berry — CPU score  (cpu) [OPUS]
- **Done:** New _cpu_score_balloon_berry: -100 at Retreat Cost 0 or with a Tool already on, 60 when stuck (2+) and r4_cpu_wants_self_switch, else 20 + 5 x cost.
- **Problem:** Flat 35.0 regardless of whether the Active needs to retreat or already has 0 retreat cost.
- **Evidence:** CPU_AI.gd:5652
- **Proposed fix:** Score higher when Active is stuck (Retreat Cost >=2, wants to switch), negative when target retreat cost is already 0.
- **Files:** CPU_AI.gd

### 171. [x] ex9-10 Sceptile — Green Essence  (effect) [EASY]
- **Done:** ex9_blocks_status: Battle Frontier now only disables the holder's own Magma Armor and a Battle-Frontier-locked Sceptile's Green Essence, not Green Essence given to a locked Pokémon.
- **Problem:** ex9_blocks_status returns false early when the PROTECTED Pokémon is a Colorless/Darkness/Metal Evolved Pokémon under Battle Frontier. Battle Frontier only stops that Pokémon's OWN bodies; Sceptile (Grass) still gives Green Essence to it. Such an Active with Grass Energy wrongly loses status immunity.
- **Evidence:** Powers_And_Bodies_Effects.gd:15621 `if battle_frontier_disables(pokemon): return false` placed before both Magma Armor and Green Essence checks
- **Proposed fix:** Move the Battle Frontier check into the Magma Armor branch only (`pokemon.has_ability("Magma Armor") and not battle_frontier_disables(pokemon) ...`), and in the Green Essence loop skip a Sceptile `p` only if battle_frontier_disables(p).
- **Files:** Powers_And_Bodies_Effects.gd

### 172. [x] ex9-2 Deoxys — Form Change (CPU)  (cpu) [OPUS]
- **Done:** CPU Form Change also considers Benched Deoxys (Active first), still once per turn.
- **Problem:** CPU only ever Form Changes its ACTIVE Deoxys; a Benched Deoxys/Deoxys ex is never switched to a better form for next turn.
- **Evidence:** Powers_And_Bodies_Effects.gd:15106 block only considers `oa` (opponent_active_pokemon)
- **Proposed fix:** If the Active doesn't qualify, loop opponent_bench Deoxys with Form Change and use _r4_cpu_best_form(bench_mon, pool) against the player Active; still once per turn via opponent_ex8_form_change_used.
- **Files:** Powers_And_Bodies_Effects.gd

### 173. [x] ex9-67 Swablu — Feathery  (effect) [EASY]
- **Done:** Card_Ops.apply_bench_damage: a Body worded 'opponent's attacks' (Feathery, ex3 Whiscash Submerge) lets damage from its own side's attack through; 'both yours and your opponent's' still blocks all.
- **Problem:** Feathery only prevents damage from the OPPONENT's attacks while Benched, but the generic bench guard (any Body text with 'prevent all damage' + 'bench') also blocks damage from Swablu's own side's attacks (e.g. own Earthquake-style bench hits). Correct for Feebas Submerge ('both yours and your opponent's'), wrong for Feathery.
- **Evidence:** Card_Ops.gd:1414-1420 apply_bench_damage generic text guard has no attacker-side check
- **Proposed fix:** In that loop, if abtext contains "opponent's attacks" and not "both yours", only return when the damage comes from the other side (attacker side != is_opponent; pass/derive attacker side from main.opponents_turn_active).
- **Files:** Card_Ops.gd

### 174. [x] gym1-20 Brock's Golem — Rock Slide  (choice) [OPUS]
- **Done:** gym1_choose_bench_targets: when the attack in progress says 'choose up to', the player may pick 0 (Rock Slide gym1-20, Tunneling).
- **Problem:** 'choose up to 3 of them' — player prompt forces at least 1 pick (min 1) instead of min 0 per the 'up to N' rule. Same helper for Tunneling (gym1-21, 'up to 2').
- **Evidence:** Attack_Effects.gd:5329 gym1_choose_bench_targets passes `1 if allow_fewer else limit` as min.
- **Proposed fix:** Pass `0 if allow_fewer else limit` as min_n in gym1_choose_bench_targets (Attack_Effects.gd:5329).
- **Files:** Attack_Effects.gd

### 175. [x] neo1-14 Slowking — Mind Games  (effect) [EASY]
- **Done:** Mind Games is now checked for Stadium cards too (the non-Stadium gate removed; heads puts the Stadium on top of the deck before it enters play).
- **Problem:** Mind Games never triggers on Stadium cards, but the text says 'Whenever your opponent plays a Trainer card' (Stadiums are Trainer cards).
- **Evidence:** Trainer_Effects.gd:1322 `if not is_stadium_trainer(card): if await main.powers_and_bodies.check_mind_games(...)`; the Stadium play path skips it
- **Proposed fix:** Call check_mind_games for Stadium plays too (in the Stadium play path before the Stadium enters play); on heads put the Stadium on top of its owner's deck.
- **Files:** Trainer_Effects.gd

### 176. [x] neo1-52 Xatu — Prophecy  (cpu) [OPUS]
- **Done:** Done under #38: Xatu shares execute_prophecy, whose CPU branch now picks the deck (own or player's) where reordering gains most via r3_reorder_top.
- **Problem:** Text lets the user look at EITHER player's deck; the CPU branch only ever rearranges its own deck (and only puts Energy first when it needs Energy, otherwise does nothing). It never uses Prophecy to bury good cards on the player's deck top.
- **Evidence:** Attack_Effects.gd:3866-3897 execute_prophecy CPU branch hard-codes main.opponent_deck
- **Proposed fix:** In execute_prophecy CPU branch: if the CPU has no useful reorder for its own top 3 (no Energy need / already ordered), instead take the player's top 3 and order them worst-first for the player (e.g. Energy the player's Active doesn't need / Trainers last), using cpu_ai.cpu_pick_best_keep inverted. Announce which deck was looked at.
- **Files:** Attack_Effects.gd

### 177. [x] neo2-4 Houndoom — Flamethrower  (choice) [OPUS]
- **Done:** neo2 Flamethrower ('or this attack does nothing') discards via r4_pick_own_energy over every Fire-providing card.
- **Problem:** 'Discard 1 Fire Energy card' — handler takes the first Fire-providing card, no player choice, CPU doesn't prefer a basic Fire over Rainbow/special.
- **Evidence:** Attack_Effects.gd:10511-10520 (breaks on first Fire, discards fire_e[0]).
- **Proposed fix:** Collect all Fire candidates; if >1 distinct, player picks via r4_pick_own_energy, CPU via cpu_own_energy_discard_order.
- **Files:** Attack_Effects.gd

### 178. [x] neo3-1 Ampharos — Attract Current  (choice) [OPUS]
- **Done:** Attract Current (neo3): Lightning targets via get_effective_types; the player's target prompt is cancelable (stops the remaining attachments); the message reports the real count.
- **Problem:** 'For each heads, you MAY search ... and attach it to 1 of your Lightning Pokemon' — the player can't decline (cancel defaults to the first target), and Lightning-ness is read from printed types/temporary_type instead of get_effective_types().
- **Evidence:** Attack_Effects.gd:11476-11509 (target==null -> lightning_targets[0]).
- **Proposed fix:** Make the target prompt cancellable (cancel = skip remaining attachments); build lightning_targets with p.get_effective_types().
- **Files:** Attack_Effects.gd

### 179. [x] neo3-17 Entei — Mega Flame  (choice) [OPUS]
- **Done:** Mega Flame discards via pick_own_energies(min(tails, pool)).
- **Problem:** Each tails discards fire_e[0] automatically; player gets no choice of which Fire Energy card goes.
- **Evidence:** Attack_Effects.gd:12023-12029.
- **Proposed fix:** After counting tails, player picks min(tails, fire_e.size()) via pick_own_energies; CPU via cpu_own_energy_discard_order.
- **Files:** Attack_Effects.gd

### 180. [x] neo3-6 Entei — Searing Flames  (choice) [OPUS]
- **Done:** Searing Flames discards via pick_own_energies(fire_e, 2).
- **Problem:** 'Discard 2 Fire Energy cards attached to Entei' auto-discards the first two Fire-providing cards; when Entei has more than 2 Fire-providing cards of different kinds (basic Fire vs Rainbow/Multi/special) the player gets no choice and the CPU may throw away a special energy.
- **Evidence:** Attack_Effects.gd:11666-11668 discards fire_e[0], fire_e[1].
- **Proposed fix:** If fire_e.size() > 2 and the cards differ: player -> pick_own_energies(attacker, fire_e, 2, false, 'SEARING FLAMES: DISCARD 2 FIRE ENERGY'); CPU -> cpu_ai.cpu_own_energy_discard_order filtered to fire_e (same pattern as execute_neo3_lava_flow:12431-12438).
- **Files:** Attack_Effects.gd

### 181. [x] neo3-8 Houndoom — Dark Flame  (choice) [OPUS]
- **Done:** Dark Flame discards via r4_pick_own_energy.
- **Problem:** 'Discard 1 Fire Energy card' auto-discards fire_e[0] with no choice when several different Fire-providing cards are attached.
- **Evidence:** Attack_Effects.gd:11752 discard_energy_from_pokemon(fire_e[0]).
- **Proposed fix:** Use r4_pick_own_energy / pick_own_energies(attacker, fire_e, 1, ...) for the player when >1 distinct candidate; CPU uses cpu_own_energy_discard_order.
- **Files:** Attack_Effects.gd

### 182. [x] neo4-107 Shining Charizard — White-hot Flame  (effect) [EASY]
- **Done:** White-hot Flame finds a distinct Fire + Lightning pair order-independently and lets the owner pick each card (r4_pick_own_energy).
- **Problem:** Fire/Lightning pick is order-dependent: the first card providing Fire is always taken as the Fire card, so with Miracle Energy (counts as every type) attached before a basic Fire and no basic Lightning, the attack wrongly 'does nothing' although basic Fire + Miracle(as Lightning) satisfies it. The player also gets no choice of which Fire/Lightning cards to discard.
- **Evidence:** Attack_Effects.gd:14953-14958 — `if fire == null and "Fire" in prov: fire = e elif lightning == null and "Lightning" in prov: lightning = e`.
- **Proposed fix:** Collect fire_cards and lightning_cards separately; find a pair of distinct cards (prefer single-type cards first, multi-type like Miracle/Rainbow last). For the player when more than one valid pair exists, use pick_own_energies(attacker, fire_cards, 1, ...) then pick_own_energies(attacker, lightning_cards minus picked, 1, ...).
- **Files:** Attack_Effects.gd

### 183. [x] pop2-10 Pokémon Park — Stadium  (effect) [EASY]
- **Done:** Pokémon Park: per-side once-per-turn flag, heal obeys modify_heal_amount and is announced with float_label_over.
- **Problem:** 'Once during each player's turn' is not tracked; the heal also is not announced (silent HP change).
- **Evidence:** Trainer_Effects.gd:9385 pokemon_park_on_bench_energy_attach heals on every call with no per-turn flag
- **Proposed fix:** Track a per-side flag (reset at turn start) and skip if already used this turn; show a short 'POKEMON PARK: REMOVED 1 DAMAGE COUNTER' message.
- **Files:** Trainer_Effects.gd

### 184. [x] pop4-4 Mew — Psyshock  (anim) [EASY]
- **Done:** not a bug - the map's 'status' list (union over every 'Psyshock') only feeds the DEL VFX tester preview, which shows st[0] = Paralyzed; in matches the overlay plays only for the status that actually lands (Card_FX.status). No generator change needed.
- **Problem:** The vfx status overlay list is ['Paralyzed','Confused'], but the attack only Paralyzes (on heads), so it plays a Confused overlay it shouldn't.
- **Evidence:** batch vfx: Psyshock status ['Paralyzed','Confused']
- **Proposed fix:** Set the Psyshock recipe status to ['Paralyzed'] only for this card (in the attack-VFX generator / per-attack status map, keyed by text).
- **Files:** Attack VFX recipe
