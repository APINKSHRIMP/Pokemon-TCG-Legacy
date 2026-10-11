"""
Deep analysis of the CPU lab's branch replays (ISSUE #375): per CARD and per situation, where the CPU's own choice is
beaten by the alternative. Writes lab/deep_analysis.txt.

  py cpu_lab_analyse.py [--min 40] [--z 3]

For every decision kind:
  trainer : UNDER-PLAYED  = CPU held / played something else, the branch played card X  -> delta > 0 means play X more
            OVER-PLAYED   = CPU played X, the branch skipped it                           -> delta > 0 means play X less
  bench   : under-benched / over-benched per Pokémon
  energy  : "skip the attach" vs CPU's attach; per Energy card
  retreat : retreat vs stay, by situation
  attack  : per attacking Pokémon + attack name the CPU chose (did another attack do better?)
  replace / fetch : per card brought up / fetched
Situations: ctx rel features (hits_weak, is_weak, i_ohko, they_ohko, hp_adv...), ahead/behind, early/late, hand size,
bench size. A z threshold of 3 is used because thousands of groups are tested (z 2 would give many false hits).
"""
import json
import math
import os
import sys
from collections import defaultdict

import cpu_tuner as T

args = sys.argv[1:]
MIN_N = int(args[args.index("--min") + 1]) if "--min" in args else 40
Z = float(args[args.index("--z") + 1]) if "--z" in args else 3.0
LAB = os.path.join(os.path.dirname(T.TUNER_DIR), "lab")
SRC = os.path.join(LAB, "branch_results.jsonl")
OUT = os.path.join(LAB, "deep_analysis.txt")


def stats(d):
    n = len(d)
    if n < 2:
        return n, 0.0, 0.0
    m = sum(d) / n
    v = sum((x - m) ** 2 for x in d) / (n - 1)
    se = math.sqrt(v / n) if v > 0 else 0.0
    return n, m, (m / se if se > 0 else 0.0)


def situations(ctx):
    s = ["any"]
    s += ["rel:" + r for r in ctx.get("rel", [])]
    a = ctx.get("ahead", 0)
    s.append("prizes:" + ("ahead" if a > 0 else "behind" if a < 0 else "even"))
    t = ctx.get("turn", 0)
    s.append("turn:" + ("1-4" if t <= 4 else "5-10" if t <= 10 else "11+"))
    h = ctx.get("hand", 0)
    s.append("hand:" + ("0-3" if h <= 3 else "4-6" if h <= 6 else "7+"))
    b = ctx.get("bench", 0)
    s.append("mybench:" + ("0-1" if b <= 1 else "2-3" if b <= 3 else "4+"))
    fb = ctx.get("foe_bench", 0)
    s.append("foebench:" + ("0-1" if fb <= 1 else "2-3" if fb <= 3 else "4+"))
    return s


groups = defaultdict(list)
total = 0
for line in open(SRC, encoding="utf-8"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    total += 1
    k, lab, ch, alt, d = r["kind"], r.get("labels", []), r["chosen"], r["alt"], r["delta"]
    if ch >= len(lab) or alt >= len(lab):
        continue
    c_lab, a_lab = lab[ch], lab[alt]
    ctx = r.get("ctx", {})
    keys = []
    if k == "trainer":
        if a_lab != "none":
            keys.append(("TRAINER UNDER-PLAYED (play it more)", a_lab))
        if c_lab != "none" and a_lab == "none":
            keys.append(("TRAINER OVER-PLAYED (hold it more)", c_lab))
    elif k == "bench":
        keys.append(("BENCH: bench it more" if a_lab != "hold" else "BENCH: hold it more", lab[1] if len(lab) > 1 else "?"))
    elif k == "energy":
        if a_lab == "no attach":
            keys.append(("ENERGY: attaching at all", c_lab.split(" -> ")[0]))
        else:
            keys.append(("ENERGY: other target than CPU's", c_lab.split(" -> ")[0]))
    elif k == "retreat":
        keys.append(("RETREAT: CPU retreated, staying" if a_lab == "stay" else "RETREAT: CPU stayed, retreating", "-"))
    elif k == "attack":
        keys.append(("ATTACK: CPU's choice vs another attack", "%s [%s]" % (c_lab, ctx.get("me", "?"))))
    elif k == "replace":
        keys.append(("REPLACE: CPU's pick vs another", c_lab))
    elif k == "fetch":
        keys.append(("FETCH: CPU's pick vs another", c_lab))
    for cat, item in keys:
        for s in situations(ctx):
            groups[(cat, item, s)].append(d)
            groups[(cat, "ALL", s)].append(d)

cats = sorted({c for c, _, _ in groups})
lines = ["DEEP BRANCH ANALYSIS (%s) — %s branched games. delta = alternative minus CPU choice; listed: |z| >= %.1f, n >= %d"
         % (T.now(), f"{total:,}", Z, MIN_N), ""]
for cat in cats:
    rows = []
    for (c, item, s), d in groups.items():
        if c != cat:
            continue
        n, m, z = stats(d)
        if n >= MIN_N and abs(z) >= Z:
            rows.append((z, m, n, item, s))
    alln, allm, allz = stats(groups.get((cat, "ALL", "any"), []))
    lines.append("== %s — overall %+.4f z %+.2f (n %d)" % (cat, allm, allz, alln))
    rows.sort(key=lambda r: -r[0])
    for z, m, n, item, s in rows[:45]:
        lines.append("   %+.4f  z %+6.2f  n %6d   %-38s %s" % (m, z, n, item[:38], s))
    lines.append("")
T.atomic_write_text(OUT, "\n".join(lines) + "\n")
print("\n".join(lines))
