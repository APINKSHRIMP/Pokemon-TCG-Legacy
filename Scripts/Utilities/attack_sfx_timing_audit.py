"""Attack animation / sound timing audit.

Models what Attack_VFX.gd does with every attack's recipe + sound clip (at match speed 1, no SUPER windup) and
lists where the sound and the picture disagree. Reads only the generated JSON in Attack_Animation_Data, so run
`py -I Scripts/Utilities/attack_vfx_build.py` first. Writes audit_out/anim_audio_timing.md.

    py -I Scripts/Utilities/attack_sfx_timing_audit.py

The constants below mirror Attack_VFX.gd -- keep them in step if those change.
"""
import collections
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'Attack_Animation_Data')
OUT = os.path.join(ROOT, 'audit_out', 'anim_audio_timing.md')

# ---- Attack_VFX.gd constants ----
FRAME_FPS, RUN_MIN, RUN_MAX = 20.0, 0.25, 1.1
TRAVEL_TIME, BEAM_TIME = 0.42, 0.7
BODY_TIMES = {'lunge': [0.08, 0.16, 0.24], 'dash': [0.05, 0.10, 0.22], 'spin': [0.08, 0.22, 0.28],
              'leap': [0.12, 0.30, 0.30], 'dive': [0.28, 0.12, 0.13, 0.28], 'vanish_strike': [0.14, 0.12, 0.06, 0.22]}
CONTACT_BODIES = list(BODY_TIMES)
KNOCK_OUT, KNOCK_SETTLE, WIGGLE_STEP, WIGGLE_N = 0.07, 0.22, 0.05, 5
MULTI_GAP = 0.13
FLASH_FADE = 0.22
DIM_OUT = 0.25
SCREEN_FLASH_TIME, SCREEN_SHAKE_TIME = 0.32, 0.42
SFX_MAX_LEN, SFX_TAIL = 2.4, 0.6
SFX_END_TAIL, SFX_END_FADE = 0.45, 0.3
SFX_ALIGN_SLACK = 0.08
HIT_BUILDUP = 0.2   # a clip whose hit is past this has a build-up

# ---- thresholds (seconds) ----
OFF_HIGH, OFF_MED = 0.30, 0.15          # sound hit vs visual impact
SKIP_MED = 0.6                          # build-up skipped into by this much (its start is lost)
SILENT_MED = 0.55                       # lead-in with no sound at all before the hit
TAIL_HIGH, TAIL_MED = 1.0, 0.5          # clip tail faded out after the animation ends


def load(name):
    with open(os.path.join(DATA, name), encoding='utf-8') as fh:
        return json.load(fh)


VFX = load('vfx_manifest.json')
SFX = load('sfx_manifest.json')
REC_ALL = load('vfx_recipes.json')
RECIPES = REC_ALL['recipes']
ELEMENTS = REC_ALL['elements']
MAP = load('attack_vfx_map.json')


def groups(steps):
    out = []
    for s in steps:
        if not out or not s.get('par', False):
            out.append([s])
        else:
            out[-1].append(s)
    return out


def run_time(s):
    if 'dur' in s:
        return float(s['dur'])
    n = len(VFX.get(str(s.get('fx', '')), {}).get('frames', []))
    return min(max(n / FRAME_FPS, RUN_MIN), RUN_MAX)


def estimate(steps):
    total = 0.0
    for g in groups(steps):
        longest = 0.0
        for s in g:
            at = s.get('at', 'target')
            if at in ('travel', 'return', 'drop'):
                one = float(s.get('time', TRAVEL_TIME))
                if at == 'drop' and one <= 0.0:
                    one = run_time(s)
            elif at == 'beam':
                one = float(s.get('dur', BEAM_TIME))
            elif at == 'quake':
                one = float(s.get('dur', 0.6))
            else:
                one = run_time(s) * max(1.0, float(s.get('loops', 1)))
            one += float(s.get('delay', 0.0)) + float(s.get('stagger', 0.0)) * max(0, int(s.get('count', 1)) - 1)
            longest = max(longest, one)
        total += longest
    return total


def impact_estimate(steps, body, contact):
    """Attack_VFX._impact_estimate, verbatim."""
    if contact:
        pre = []
        for s in steps:
            if s.get('at', '') != 'self':
                break
            pre.append(s)
        return estimate(pre) + sum(BODY_TIMES[body][:-1])
    t = 0.0
    for g in groups(steps):
        for s in g:
            at = s.get('at', '')
            if at in ('target', 'drop', 'screen', 'bench', 'quake', 'beam'):
                extra = float(s.get('delay', 0.0))
                if at == 'beam':
                    extra += float(s.get('dur', BEAM_TIME)) * 0.22
                elif at == 'drop':
                    extra += max(0.0, float(s.get('time', TRAVEL_TIME)))
                return t + extra
        t += estimate(g)
    return t


def impact_actual(steps, body, contact):
    """When _impact really fires (what _run_groups / _play_step / _beam do), or the end for a no-target recipe."""
    if contact:
        return impact_estimate(steps, body, contact)
    t = 0.0
    for g in groups(steps):
        quake_hits = not any(s.get('at', 'target') in ('target', 'drop', 'screen', 'beam') or s.get('impact') for s in g)
        cands = []
        for s in g:
            at = s.get('at', 'target')
            d = float(s.get('delay', 0.0))
            if s.get('impact') or at in ('target', 'screen', 'bench'):
                cands.append(d)
            elif at == 'quake' and quake_hits:
                cands.append(d)
            elif at == 'drop':
                tm = float(s.get('time', TRAVEL_TIME))
                cands.append(d + (tm if tm > 0.0 else 0.0))
            elif at == 'beam':
                cands.append(d + float(s.get('dur', BEAM_TIME)) * 0.22)
        if cands:
            return t + min(cands)
        t += estimate(g)
    return t


def react_time(r, damaging):
    style = r.get('react', 'knock')
    hits = max(1, int(r.get('hits', 1)))
    el = ELEMENTS.get(r.get('element', 'normal'), {})
    linger = float(el.get('linger_time', 0.0)) if (r.get('linger', True) and 'linger' in el) else 0.0
    if not damaging:
        return max(linger, 0.5) if linger > 0 else 0.0
    st = {'multi': MULTI_GAP * hits + KNOCK_SETTLE, 'spin': 0.55, 'lift': 0.6, 'toss': 1.65 + 0.45, 'squash': 0.5,
          'squeeze': 0.5, 'jolt': 0.55, 'shake': 0.55, 'freeze': 0.3}.get(style, KNOCK_OUT + max(KNOCK_SETTLE, WIGGLE_STEP * WIGGLE_N))
    return max(st, FLASH_FADE + linger)


def has_target(steps):
    return any(s.get('at', '') != 'self' for s in steps)


def one_hit(clip):
    base = clip.removesuffix(' 1hit').removesuffix(' 2hits')
    return base + ' 1hit' if base + ' 1hit' in SFX else ''


def run_start(hit, onsets, gap=0.35):
    """Attack_VFX._run_start: the first onset of the run of quick hits ending at `hit`."""
    start = hit
    for o in reversed(onsets):
        if o > hit + 0.001:
            continue
        if start - o > gap:
            break
        start = o
    return start


def rapid_onsets(onsets, frm, to):
    """Onsets in [frm, to) that come in a quick run (< 0.35 s apart): how many hits the ear hears."""
    o = [x for x in onsets if frm - 0.03 <= x < to]
    if len(o) < 2:
        return len(o)
    best = run = 1
    for a, b in zip(o, o[1:]):
        run = run + 1 if b - a < 0.35 else 1
        best = max(best, run)
    return best


def analyse(rid, r, clip, pitch, damaging, sfx_len):
    steps = r['steps']
    body = r.get('body', 'none')
    contact = body in CONTACT_BODIES
    info = SFX[clip]
    dur, hit = float(info['dur']), float(info.get('hit', 0.0))
    onsets = [float(x) for x in info.get('onsets', [0.0])]
    base = clip.removesuffix(' part 1').removesuffix(' part 2')
    split = base + ' part 1' in SFX and base + ' part 2' in SFX
    hits = int(r.get('hits', 1))
    est = estimate(steps)
    imp_est = impact_estimate(steps, body, contact)
    imp = impact_actual(steps, body, contact)
    react = react_time(r, damaging)
    sc = r.get('screen', {})
    if contact:
        times = BODY_TIMES[body]
        first_out = next((i for i, s in enumerate(steps) if s.get('at', '') != 'self'), len(steps))
        rest = steps[first_out:]
        while rest and rest[0].get('at', '') in ('travel', 'return', 'beam'):
            rest = rest[1:]
        end = imp + max(estimate(rest), times[-1], react)
    else:
        end = max(est, imp + react) if has_target(steps) else est + (react if damaging else 0.0)
    if 'shake' in sc and damaging:
        end = max(end, imp + SCREEN_SHAKE_TIME)
    if 'flash' in sc and damaging:
        end = max(end, imp + SCREEN_FLASH_TIME)
    if 'dim' in sc:
        end += DIM_OUT
    fade_at = end + SFX_END_TAIL + SFX_END_FADE * 0.5   # roughly where the end-of-animation fade has eaten the sound
    f = []   # (severity, kind, text)
    p = pitch

    aligned = damaging or hit > HIT_BUILDUP or split or r.get('sfx_align', False)
    start_mode = (not has_target(steps)) or (not aligned) or r.get('sfx_start', False)
    windup = r.get('sfx_windup', '')
    mode = 'start' if start_mode else ('multi' if (hits > 1 and one_hit(clip)) or sfx_len else 'aligned')
    if start_mode:
        frm = 0.0
        # AUDIT 2026-11-19 runtime: a self-side clip whose hit is past the animation is skipped into.
        if (not has_target(steps) or r.get('sfx_start', False)) and hit > HIT_BUILDUP and hit / p > est + 0.08:
            frm = hit - est * p
            mode = 'start, skipped in'
        cap = (dur - frm) / p
        if not damaging:
            cap = min(cap, est + SFX_TAIL)
        heard_to = min(cap, fade_at)
        hit_t = (hit - frm) / p
        dur = dur - frm
        visual = imp if has_target(steps) else None
        if hit_t > heard_to - 0.05:
            f.append(('HIGH', 'cut before hit', f"clip's hit at {hit_t:.2f}s but the sound is cut/faded by {heard_to:.2f}s "
                      f"(anim ends {end:.2f}s)"))
        elif visual is not None and has_target(steps) and not r.get('sfx_start', False):
            off = hit_t - visual
            over = dur / p < visual - 0.05
            if over:
                f.append(('HIGH', 'sound over before impact', f"plays from the start: the {dur / p:.2f}s clip has ended "
                          f"before the effect reaches the target at {visual:.2f}s"))
            elif abs(off) >= OFF_HIGH:
                f.append(('MEDIUM', 'hit off impact',
                          f"plays from the start: sound hit {hit_t:.2f}s vs visual impact {visual:.2f}s ({off:+.2f}s)"
                          + ('' if damaging else '; the damaging version of this recipe plays it AT the impact')))
            elif abs(off) >= OFF_MED:
                f.append(('LOW', 'hit off impact', f"plays from the start: sound hit {hit_t:.2f}s vs impact {visual:.2f}s ({off:+.2f}s)"))
        lost = dur / p - heard_to
        if lost >= TAIL_HIGH and hit_t < heard_to:
            f.append(('MEDIUM', 'clip longer than anim', f"{dur / p:.2f}s clip, {lost:.2f}s of it faded away (anim {end:.2f}s)"))
    elif mode == 'multi':
        oh = one_hit(clip) if hits > 1 else clip
        oi = SFX[oh]
        # AUDIT 2026-11-19 runtime: each repeat starts at the 1hit clip's own hit (unless cut by sfx_len).
        rfrom = 0.0 if sfx_len else max(0.0, float(oi.get('hit', 0.0)) - 0.02)
        per = sfx_len if sfx_len else float(oi['dur'])
        heard = rapid_onsets([float(x) for x in oi.get('onsets', [0])], rfrom, per)
        if heard > 1 and not sfx_len:
            f.append(('MEDIUM', 'multi-hit count', f"'{oh}' itself holds {heard} quick hits, repeated x{hits} = ~{heard * hits} hits heard"))
        stg = [float(s.get('stagger', 0.0)) for s in steps if int(s.get('count', 1)) > 1]
        if stg and abs(stg[0] - MULTI_GAP) > 0.08:
            f.append(('LOW', 'multi-hit spacing', f"hits sound {MULTI_GAP}s apart, the effect copies land {stg[0]}s apart"))
    else:
        # The aligned path: the build-up is skipped into / delayed so its hit lands on the ESTIMATED impact.
        if hits > 1 and hit > HIT_BUILDUP and not split:
            hit = run_start(hit, onsets)   # AUDIT 2026-11-19 runtime: multi-hit aligns the first hit of the last run
        buildup = (float(SFX[base + ' part 1']['dur']) if split else (hit if hit > HIT_BUILDUP else 0.0)) / p
        drift = imp - imp_est
        if abs(drift) >= OFF_MED:
            f.append(('HIGH' if abs(drift) >= OFF_HIGH else 'MEDIUM', 'estimate drift',
                      f"_impact_estimate says {imp_est:.2f}s, the impact really fires at {imp:.2f}s ({drift:+.2f}s): "
                      f"the build-up's hit lands off the impact"))
        if buildup > 0:
            if buildup - imp_est >= SKIP_MED:
                f.append(('LOW', 'build-up skipped', f"{buildup:.2f}s build-up before a {imp_est:.2f}s lead-in: "
                          f"its first {buildup - imp_est:.2f}s are skipped"))
        elif imp_est >= SILENT_MED and not windup:
            f.append(('MEDIUM', 'silent lead-in', f"no build-up in the clip: {imp_est:.2f}s of silence before the hit"))
        played_from = 0.0 if split else max(0.0, hit - 0.02)
        pclip = base + ' part 2' if split else clip
        tail = (min(float(SFX[pclip]['dur']) - played_from, SFX_MAX_LEN * p)) / p
        lost = (imp + tail) - fade_at
        if lost >= TAIL_HIGH:
            f.append(('MEDIUM', 'clip longer than anim', f"{tail:.2f}s after the hit, the animation ends {end - imp:.2f}s after it: "
                      f"{lost:.2f}s faded away"))
        elif lost >= TAIL_MED:
            f.append(('LOW', 'clip longer than anim', f"{tail:.2f}s after the hit vs {end - imp:.2f}s of animation: {lost:.2f}s faded"))
        if hits > 1 and not one_hit(clip) and len(onsets) >= 2:
            # The clip's own hits, placed so its main hit lands on the impact, vs the visual hits MULTI_GAP apart.
            rel = [(o - (hit if not split else 0.0)) / p for o in onsets]
            if split:
                rel = [(o - float(SFX[base + ' part 1']['dur'])) / p for o in onsets]
            heard = [x for x in rel if x >= -imp_est - 0.02 and x <= tail + 0.01]
            early = [x for x in heard if x < -0.06]
            if early and len(heard) >= 2:
                # Onsets more than SFX_RUN_GAP before the run are a launch / lead-in, not hits.
                f.append(('LOW', 'multi-hit lead-in',
                          f"{hits} visual hits at 0..+{MULTI_GAP * (hits - 1):.2f}s, the clip's onsets at "
                          + ', '.join(f'{x:+.2f}' for x in heard) + 's (a sound before the first hit)'))
            elif len(heard) != hits and abs(len(heard) - hits) >= 2:
                f.append(('MEDIUM', 'multi-hit count', f"recipe has {hits} hits, the clip has {len(heard)}"))
        if hits <= 1:
            heard = rapid_onsets(onsets, played_from, played_from + tail * p)
            if heard >= 3:
                f.append(('LOW', 'multi-hit count', f"single-hit recipe, the clip has a run of {heard} quick hits after its hit"))
    return {'mode': mode, 'est': est, 'imp': imp, 'imp_est': imp_est, 'end': end, 'dur': dur / p, 'hit': hit / p,
            'findings': f}


def combos():
    """(recipe id, clip, pitch, damaging, sfx_len) -> attack names, from the map exactly as recipe_by_name does it."""
    out = collections.defaultdict(list)
    used = set()
    for name, m in MAP.items():
        rids = {m['fx']} | set(m.get('by_type', {}).values())
        for rid in rids:
            r = RECIPES.get(rid)
            if r is None:
                continue
            used.add(rid)
            clip = m.get('sfx') or r.get('sfx')
            if not clip or clip not in SFX:
                continue
            pitch = 1.0 if 'sfx' in m else float(r.get('sfx_pitch', 1.0))
            out[(rid, clip, pitch, bool(m.get('dmg', True)), float(m.get('sfx_len', 0.0)))].append(name)
    for fb in REC_ALL['fallback'].values():
        for tiers in fb.values():
            for rid in tiers:
                r = RECIPES.get(rid)
                if r and r.get('sfx') and rid not in used:
                    out[(rid, r['sfx'], float(r.get('sfx_pitch', 1.0)), True, 0.0)].append('(type fallback)')
    return out


NOTES = """## Fixed in the generator (2026-11-19)

- **`sfx_start`** (new `SFX_START` in attack_vfx_build.py) on **Flamethrower, WaterGun, Screech, Supersonic, Acid,
  PoisonSpray**: their clips have no build-up, so as DAMAGING attacks they only started at the impact after 0.58-1.10 s of
  silence (the stream / sound wave flew silently), while the 0-damage versions already played from the start. Now both
  play from the start.
- **`sfx_windup`** (new `SFX_WINDUP`) on **Selfdestruct, HyperBeam** (`Charge Beam part 1`) and **DragonRage** (`Roar`):
  1.0-1.2 s charge with a clip that only starts at the hit; the windup now fills the charge and is cut at the impact.

Only `vfx_recipes.json` changed on regenerating; the attack map is unchanged.

## Attack_VFX.gd items (approved and done 2026-11-19, tagged `AUDIT 2026-11-19`; this audit models the new behaviour)

1. [x] **Multi-hit "1hit" clips with a lead-in** (Pin Missile 1hit hit at 0.93 s, Double Slap 1hit 0.58 s, Bone Rush 1hit
   0.22 s): `_sfx_repeat` plays every repeat from 0, so each lands that late after its visual hit. Start each repeat at
   `max(0, hit - 0.02)` instead (Comet Punch's `sfx_len` path is unaffected).
   - DONE: `_sfx_repeat` starts each repeat at the 1hit clip's `hit - 0.02` (only when not cut by `sfx_len`).
2. [x] **Multi-hit clips aligned on their LAST hit** (Swift, Twineedle, Razor Leaf, Shadow Punch, Cut, Hail, Bullet Seed):
   the build-up path lines the clip's last onset up with the impact, so its earlier hits sound BEFORE the first visual
   hit. For `hits > 1` recipes align the first onset of the final run instead, or add a manifest/recipe hit override.
   - DONE: `hits > 1` recipes align `_run_start()` (first onset of the run < `SFX_RUN_GAP` 0.35 s apart ending at the
     hit). Onsets further back are a launch sound and now show as LOW "multi-hit lead-in".
3. [x] **0-damage recipes with a no-build-up clip and a target effect** (Hyper Beam, Encore, Flatter, Feint Attack, Horn
   Drill, Rock Throw, Sonic Boom, Stomp, Smog, Sacred Fire, Magma Storm, Lava Plume, Mud Slap, Silver Wind): played
   from the start, 0.3-1.1 s before the effect reaches the target, while the damaging version of the same recipe plays
   AT the impact. Needs an "align" path for 0-damage attacks (the reverse of `sfx_start`) before the generator can
   choose per recipe.
   - DONE: new recipe flag `sfx_align` (generator `SFX_ALIGN`: HyperBeam, FeintAttack, HornDrill, Pebbles, Sonicboom,
     Stomp, Smog, SacredFire, Magma, HotRocks, MudSlap, Barrage) lines the clip up with the impact at 0 damage too.
     Encore, Flatter, HealBench, RainbowWing went to `SFX_START` instead (the attacker makes the sound; aligning them
     left 0.6-1.9 s of silence), so they now play from the start whether or not the attack does damage.
4. [x] **Self-only clips whose main hit is never heard** (Charge x13, Nasty Plot, Wish, Moonlight, Baton Pass, Foresight,
   Recycle, Teeter Dance, Tail Glow, Follow Me, Conversion 2): the clip is 1.5-5 s against a 0.25-1.6 s animation and
   is faded before its climax. Either skip into these clips so the hit lands as the animation ends (as target-side
   build-ups already do), or pick shorter clips in SFX_OF -- a sound-taste call, left for the user.
   - DONE (skip-in): a self-side clip (no target step, or `sfx_start`) whose hit lands after the animation is now
     played from `hit - anim_length`, so its hit lands as the animation ends (prints `AUDIT 2026-11-19 FIX ACTIVE`).
     No clips were swapped.
5. [ ] **Clips much longer than the animation** are faded 0.45 s after it ends (the kept `_sfx_end_with_anim`); the MEDIUM
   ones lose over a second of tail. Listed for awareness.
   - LEFT: by design, no change.

Also left: MEDIUM "multi-hit count" (one long clip under 3-4 visual hits: Thrash, Outrage, Fury Swipes, Drill Peck,
Bubble Beam...) is a choice of sound, not timing. The two remaining "silent lead-in"s (Spike Cannon, Kinesis on SpoonBend)
are left as they are too.

"build-up skipped" (LOW) is by design: a build-up longer than the lead-in is skipped into so its hit lands on the
impact. Onsets come from `attack_sfx_import.py`'s detector and are approximate -- nothing here was listened to.
"""

SEV = ['HIGH', 'MEDIUM', 'LOW']


def main():
    rows = []
    for (rid, clip, pitch, dmg, sl), names in combos().items():
        a = analyse(rid, RECIPES[rid], clip, pitch, dmg, sl)
        for sev, kind, text in a['findings']:
            rows.append((sev, kind, rid, clip, pitch, dmg, a, text, names))
    by = collections.defaultdict(list)
    for row in rows:
        by[row[0]].append(row)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    total = len(combos())
    with open(OUT, 'w', encoding='utf-8') as fh:
        fh.write('# Attack animation / audio timing audit\n\n')
        fh.write(f'Generated by `Scripts/Utilities/attack_sfx_timing_audit.py` from Attack_Animation_Data '
                 f'({len(RECIPES)} recipes, {len(MAP)} attacks, {total} recipe+clip combinations). Times are base seconds at '
                 f'match speed 1, modelled on `_impact_estimate` / `_sfx_begin` / `_sfx_end_with_anim` in Attack_VFX.gd '
                 f'(clip times divided by pitch). "imp" = when the impact really fires, "end" = when the animation is over.\n\n')
        cnt = collections.Counter((r[0], r[1]) for r in rows)
        fh.write(NOTES + '\n## Summary of remaining findings\n\n')
        fh.write('| severity | kind | combos |\n|---|---|---|\n')
        for (sev, kind), n in sorted(cnt.items(), key=lambda kv: (SEV.index(kv[0][0]), -kv[1])):
            fh.write(f'| {sev} | {kind} | {n} |\n')
        fh.write('\n')
        for sev in SEV:
            fh.write(f'## {sev} ({len(by[sev])})\n\n')
            for row in sorted(by[sev], key=lambda r: (r[1], r[2].lower())):
                _, kind, rid, clip, pitch, dmg, a, text, names = row
                nm = ', '.join(sorted(names)[:6]) + (f' +{len(names) - 6} more' if len(names) > 6 else '')
                ptxt = f' @{pitch:g}' if pitch != 1.0 else ''
                fh.write(f"- **{rid}** / `{clip}`{ptxt} ({'dmg' if dmg else 'no dmg'}, {a['mode']}; imp {a['imp']:.2f}s, "
                         f"end {a['end']:.2f}s, clip {a['dur']:.2f}s hit {a['hit']:.2f}s) **{kind}**: {text}. _{nm}_\n")
            fh.write('\n')
    print(f'{total} combos, ' + ', '.join(f'{s} {len(by[s])}' for s in SEV) + f' -> {OUT}')
    if '--list' in sys.argv:
        for sev in SEV:
            for row in sorted(by[sev], key=lambda r: (r[1], r[2].lower())):
                print(sev, row[1], row[2], '|', row[3], '|', row[7], '|', len(row[8]))


if __name__ == '__main__':
    main()
