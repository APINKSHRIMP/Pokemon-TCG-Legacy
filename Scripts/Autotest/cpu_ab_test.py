"""
A/B test of the self-play tuner's outputs (ISSUE #375): plays the SAME fresh seeds with
  O   original CPU (no multipliers, no synergy, no learned matchups)
  W   tuned weights only (best_weights.json)
  WS  + learned synergy (synergy.json)
  WSL + learned matchups (learned.json)
and reports paired win-rate differences, so only parts with a real gain get shipped.

  py cpu_ab_test.py [--seeds 3000] [--workers 34]
Writes TUNER_DIR/ab_report.txt.
"""
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import cpu_tuner as T

args = sys.argv[1:]
N = int(args[args.index("--seeds") + 1]) if "--seeds" in args else 3000
W = int(args[args.index("--workers") + 1]) if "--workers" in args else 34
SEED0 = 700_000_000 + int(time.time()) % 1000 * 10_000

os.makedirs(T.WORK, exist_ok=True)
champ = {k: v for k, v in json.load(open(T.BEST, encoding="utf-8")).items() if not k.startswith("_")} if os.path.exists(T.BEST) else {}
syn = T.SYNERGY if os.path.exists(T.SYNERGY) else None
lrn = T.LEARNED if os.path.exists(T.LEARNED) else None
ALL = {"O": ({}, None, None, None), "W": (champ, None, None, None), "WS": (champ, syn, None, None), "WL": (champ, None, lrn, None),
       "WSL": (champ, syn, lrn, None), "CARDS": (champ, None, None, ["--cheat-cards=1.0"]), "COINS": (champ, None, None, ["--cheat-coins=1.0"]),
       "BOTH": (champ, None, None, ["--cheat-cards=1.0", "--cheat-coins=1.0"]),
       # ISSUE #375 lab follow-up: old trainer scoring vs the data-driven fixes, + threshold / counters / learned on top
       "OLD": ({**champ, "rule.trainer_value_fix": 0.0}, None, None, None),
       "NEW": (champ, None, None, None),
       "T75": ({**champ, "trainer.play_threshold": 0.75}, None, None, None),
       "NEWK": (champ, None, None, ["--counters=" + os.path.join(T.TUNER_DIR, "counters.json")]),
       "NEWL": (champ, None, lrn, None),
       "NEW75": ({**champ, "trainer.play_threshold": 0.75}, None, None, None),
       # ISSUE #375 lookahead phase 1: off vs on (+ attack-only / retreat-only to see which half helps)
       "NOLOOK": ({**champ, "rule.lookahead": 0.0}, None, None, None),
       "LOOK": (champ, None, None, None),
       "LOOKATK": ({**champ, "look.retreat_stay_margin": 1000.0, "look.retreat_go_margin": 1000.0}, None, None, None),
       "LOOKRET": ({**champ, "look.attack": 0.0}, None, None, None),
       "LOOKCARDS": (champ, None, None, ["--cheat-cards=1.0"]),
       "LOOKBOTH": (champ, None, None, ["--cheat-cards=1.0", "--cheat-coins=1.0"]),
       # ISSUE #375 lookahead phase 2: phase-1 only vs everything vs each new piece on its own
       "LOOK1": ({**champ, "look.energy_attach": 0.0, "look.gust": 0.0, "look.heal": 0.0}, None, None, None),
       "LOOK2": (champ, None, None, None),
       "L2E": ({**champ, "look.gust": 0.0, "look.heal": 0.0}, None, None, None),
       "L2G": ({**champ, "look.energy_attach": 0.0, "look.heal": 0.0}, None, None, None),
       "L2H": ({**champ, "look.energy_attach": 0.0, "look.gust": 0.0}, None, None, None),
       # ISSUE #375 phase 3 planner: off vs N turns, fair vs cheater
       "PLAN1": (champ, None, None, ["--plan-turns=1"]),
       "PLAN2": (champ, None, None, ["--plan-turns=2"]),
       "PLAN3": (champ, None, None, ["--plan-turns=3"]),
       "PLAN2C": (champ, None, None, ["--plan-turns=2", "--cheat-cards=1.0"]),
       "PLAN3C": (champ, None, None, ["--plan-turns=3", "--cheat-cards=1.0"])}
pick = args[args.index("--configs") + 1].split(",") if "--configs" in args else ["O", "W", "WS", "WSL"]
# Ad-hoc variants: "M:key=mult;key=mult" = the current champion with those multipliers (ISSUE #375 sweeps).
for k in pick:
    if k.startswith("M:") and k not in ALL:
        ws = dict(champ)
        extra = []
        for kv in k[2:].split(";"):
            if kv.startswith("--"):
                extra.append(kv)          # runner options, e.g. --plan-turns=3 / --cheat-cards=1
                continue
            kk, vv = kv.split("=")
            ws[kk] = float(vv)
        ALL[k] = (ws, None, None, extra or None)
configs = [(k,) + ALL[k] for k in pick]

t0 = time.time()
jobs = []
with ThreadPoolExecutor(max_workers=W) as pool:
    for name, w, s, l, x in configs:
        for st in range(SEED0, SEED0 + N, T.JOB_MATCHES):
            jobs.append((name, pool.submit(T.run_job, w, st, min(T.JOB_MATCHES, SEED0 + N - st), s, 0.0, l, None, x)))
    res = {name: {} for name, *_ in configs}
    for name, f in jobs:
        try:
            res[name].update(f.result())
        except Exception as e:
            print("job failed", e)

lines = ["CPU A/B TEST (%s) — %d fresh seeds per config, smart bot v2, %.0f min" % (T.now(), N, (time.time() - t0) / 60), ""]
for name, *_ in configs:
    lines.append("  %-40s CPU win rate %.2f%%  (%d games)" % (name, T.winrate(res[name]) * 100, len(res[name])))
lines.append("")
for a, b in [(k, pick[0]) for k in pick[1:]] + [("W", "O"), ("WS", "W"), ("WSL", "WS"), ("WSL", "O"), ("WL", "W"), ("WL", "O"), ("CARDS", "W"), ("COINS", "W"), ("BOTH", "W"), ("BOTH", "CARDS"),
             ("NEW", "OLD"), ("T75", "NEW"), ("NEWK", "NEW"), ("NEWL", "NEW"), ("T75", "OLD"), ("NEW75", "OLD"), ("NEW", "OLD"),
             ("LOOK", "NOLOOK"), ("LOOKATK", "NOLOOK"), ("LOOKRET", "NOLOOK"),
             ("LOOKCARDS", "LOOK"), ("LOOKBOTH", "LOOK"), ("LOOKBOTH", "LOOKCARDS"),
             ("LOOK2", "LOOK1"), ("L2E", "LOOK1"), ("L2G", "LOOK1"), ("L2H", "LOOK1")]:
    if a not in res or b not in res:
        continue
    p = T.paired(res[a], res[b])
    lines.append("  %-40s vs %-6s  paired mean %+.4f  z %+.2f  (n %d, %d games changed)  wins %d vs %d"
                 % (a, b, p["mean"], p["z"], p["n"], p["changed"], p["wins_c"], p["wins_b"]))
for name, *_ in configs:
    ms = sum(float(r.get("plan_ms", 0)) for r in res[name].values())
    calls = sum(int(r.get("plan_calls", 0)) for r in res[name].values())
    if calls:
        lines.append("  %-40s planner: %.1f ms per plan (%d plans)" % (name, ms / calls, calls))
lines += ["", "z >= 2 = a real gain (95%); |z| < 1 = no measurable difference."]
txt = "\n".join(lines)
print(txt)
T.atomic_write_text(os.path.join(T.TUNER_DIR, "ab_report.txt"), txt + "\n")
